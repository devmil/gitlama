//! "Select changed lines" (the Dart WorkingDiffSelectionDialog): a file's
//! working diff loaded page by page, its hunks and lines picked with
//! checkboxes, then staged, discarded or made into a patch.

use crate::plumbing::Commands;
use gitlama_contract::diff::{NativeDiffLayout, NativeDiffRow, NativeDiffRowKind};
use gitlama_contract::dto::{NativeDiffWhitespace, NativeStagingScope, NativeStagingSide, NativeStatusEntry, NativeStatusEntryKind, NativeWorkingDiffOptions};
use gitlama_workbench::changes::{change_key, diff_paths, entries_on};
use gitlama_workbench::diff_doc::DIFF_PAGE_ROWS;
use gitlama_workbench::line_selection::LineSelection;
use gitlama_workbench::rt;
use gitlama_workbench::session::SessionIdentity;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

/// The roles of the dialog's rows.
pub const LINE_ROLES: &[&str] = &["rowId", "kind", "text", "oldLine", "newLine", "pickable", "checked"];

fn kind_name(kind: NativeDiffRowKind) -> &'static str {
    match kind {
        NativeDiffRowKind::File => "file",
        NativeDiffRowKind::Hunk => "hunk",
        NativeDiffRowKind::Context => "context",
        NativeDiffRowKind::Addition => "addition",
        NativeDiffRowKind::Deletion => "deletion",
        NativeDiffRowKind::NoNewline => "noNewline",
        NativeDiffRowKind::Binary => "binary",
        NativeDiffRowKind::Image => "image",
        NativeDiffRowKind::Submodule => "submodule",
        NativeDiffRowKind::ModeOnly => "modeOnly",
        NativeDiffRowKind::TooLarge => "tooLarge",
    }
}

/// One row as the dialog shows it; `checked` is null on a partly picked hunk.
pub fn row_value(row: &NativeDiffRow, selection: &LineSelection) -> Value {
    let hunk = row.kind == NativeDiffRowKind::Hunk;
    let checked = if hunk { selection.hunk_checked(&row.stable_id).map_or(Value::Null, Value::Bool) } else { json!(selection.line_checked(&row.stable_id)) };
    json!({
        "rowId": row.stable_id,
        "kind": kind_name(row.kind),
        "text": String::from_utf8_lossy(&row.text).trim_end_matches(['\n', '\r']).replace('\t', "    "),
        "oldLine": row.old_line,
        "newLine": row.new_line,
        "pickable": hunk || row.selectable,
        "checked": checked,
    })
}

#[qobject(ConvertToCamelCase)]
mod line_selection_state {
    use super::*;

    #[derive(Default)]
    pub struct LineSelectionState {
        pub commands: Option<Commands>,
        /// {side, loading, failed, hasPage, hasMore, count, more, allChecked,
        /// empty, canDiscard}.
        pub(crate) state: Value,
        pub(crate) tab: Option<u64>,
        identity: Option<SessionIdentity>,
        side: Option<NativeStagingSide>,
        entry: Option<NativeStatusEntry>,
        request_id: Option<u64>,
        total: u64,
        pub(crate) rows: Vec<NativeDiffRow>,
        pub(crate) selection: LineSelection,
        loading: bool,
        failed: bool,
        sequence: u64,
    }

    impl LineSelectionState {
        qproperty!("state", Member = state, Notify = state_changed);

        #[qsignal]
        pub fn state_changed(&mut self);

        /// Loads the diff of the Changes file `key` on `side`.
        #[qslot]
        fn begin(&self, side: String, key: String) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(tab) = services.workspace.active_tab() else { return };
                let Some(session) = tab.session.as_ref() else { return };
                let side = if side == "staged" { NativeStagingSide::Staged } else { NativeStagingSide::Unstaged };
                let Some(status) = session.snapshot.status.as_ref() else { return };
                let Some(entry) = entries_on(status, side).into_iter().find(|entry| change_key(entry) == key) else { return };
                services.changes.focus(tab.id, side);
                let identity = session.identity;
                let shared = Rc::clone(&driver.line_selection);
                let sequence = {
                    let mut state = shared.borrow_mut();
                    state.sequence += 1;
                    state.tab = Some(tab.id);
                    state.identity = Some(identity);
                    state.side = Some(side);
                    state.entry = Some(entry.clone());
                    state.request_id = None;
                    state.total = 0;
                    state.rows.clear();
                    state.selection = LineSelection::default();
                    state.loading = true;
                    state.failed = false;
                    state.sequence
                };
                driver.publish_line_selection();
                let (old_path, new_path) = diff_paths(&entry, side);
                let request = NativeWorkingDiffOptions {
                    side,
                    old_path,
                    new_path,
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: DIFF_PAGE_ROWS as u32,
                    force_text: false,
                };
                let calls = Rc::clone(&services.calls);
                let commands = driver.commands.clone();
                rt::spawn_detached(async move {
                    let result = calls.repository_session_working_diff_load(identity.native_id, identity.generation, request).await;
                    let page = result.ok().and_then(|result| result.page.filter(|_| result.failure.is_none()));
                    commands.post(move |driver| {
                        {
                            let mut state = driver.line_selection.borrow_mut();
                            if state.sequence != sequence {
                                return;
                            }
                            state.loading = false;
                            match page {
                                Some(page) => {
                                    state.request_id = Some(page.request_id);
                                    state.total = page.total_rows;
                                    state.rows = page.rows;
                                    let (rows, total) = (state.rows.clone(), state.total);
                                    state.selection.update(&rows, total);
                                }
                                None => state.failed = true,
                            }
                        }
                        driver.publish_line_selection();
                    });
                });
            });
        }

        /// Loads the next page of rows.
        #[qslot]
        fn load_more(&self) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let (identity, request_id, offset, sequence) = {
                    let mut state = driver.line_selection.borrow_mut();
                    let (Some(identity), Some(request_id)) = (state.identity, state.request_id) else { return };
                    if state.loading || state.rows.len() as u64 >= state.total {
                        return;
                    }
                    state.loading = true;
                    (identity, request_id, state.rows.len() as u64, state.sequence)
                };
                driver.publish_line_selection();
                let calls = Rc::clone(&services.calls);
                let commands = driver.commands.clone();
                rt::spawn_detached(async move {
                    let result = calls
                        .repository_session_working_diff_page(identity.native_id, identity.generation, request_id, offset, DIFF_PAGE_ROWS as u32)
                        .await;
                    let page = result.ok().and_then(|result| result.page.filter(|_| result.failure.is_none()));
                    commands.post(move |driver| {
                        {
                            let mut state = driver.line_selection.borrow_mut();
                            if state.sequence != sequence {
                                return;
                            }
                            state.loading = false;
                            match page {
                                Some(page) if page.request_id == request_id => {
                                    state.rows.extend(page.rows);
                                    let (rows, total) = (state.rows.clone(), state.total);
                                    state.selection.update(&rows, total);
                                }
                                _ => state.failed = true,
                            }
                        }
                        driver.publish_line_selection();
                    });
                });
            });
        }

        /// Picks or unpicks row `id` (a hunk or a change line).
        #[qslot]
        fn toggle(&self, id: String, value: bool) {
            self.update(move |state| {
                let Some(row) = state.rows.iter().find(|row| row.stable_id == id) else { return };
                let hunk = row.kind == NativeDiffRowKind::Hunk;
                // Only hunks and change lines can be picked.
                if !hunk && !row.selectable {
                    return;
                }
                if hunk {
                    state.selection.set_hunk(&id, value);
                } else {
                    state.selection.set_line(&id, value);
                }
            });
        }

        /// Picks every hunk, or none when all are picked.
        #[qslot]
        fn toggle_all(&self) {
            self.update(|state| {
                if state.selection.all_checked() {
                    state.selection.clear();
                } else {
                    state.selection.select_all();
                }
            });
        }

        /// Stages (or unstages) the picked rows.
        #[qslot]
        fn stage(&self) {
            self.finish(|services, tab, side, entry, request, rows| {
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move {
                    changes.stage(tab, side, NativeStagingScope::Rows, vec![entry], Some(request), rows, None).await
                });
            });
        }

        /// Discards the picked rows after a review.
        #[qslot]
        fn discard(&self) {
            self.finish(|services, tab, _, entry, request, rows| {
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move { changes.discard(tab, vec![entry], Some(request), rows).await });
            });
        }

        /// The patch source of the picked rows: {kind: lines, requestId, rows}.
        #[qslot]
        fn patch_source(&self) -> Value {
            match self.request_id {
                Some(request) if !self.selection.is_empty() => {
                    json!({"kind": "lines", "requestId": request.to_string(), "rows": self.selection.row_ids()})
                }
                _ => Value::Null,
            }
        }

        /// The dialog closed: later answers are dropped.
        #[qslot]
        fn end(&self) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(|driver| {
                {
                    let mut state = driver.line_selection.borrow_mut();
                    state.sequence += 1;
                    state.rows.clear();
                    state.selection = LineSelection::default();
                    state.request_id = None;
                    state.entry = None;
                }
                driver.publish_line_selection();
            });
        }
    }

    impl LineSelectionState {
        fn update(&self, change: impl FnOnce(&mut LineSelectionState) + 'static) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                change(&mut driver.line_selection.borrow_mut());
                driver.publish_line_selection();
            });
        }

        fn finish(
            &self,
            run: impl FnOnce(&gitlama_workbench::app::Services, u64, NativeStagingSide, NativeStatusEntry, u64, Vec<String>) + 'static,
        ) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let (tab, side, entry, request, rows) = {
                    let state = driver.line_selection.borrow();
                    let (Some(tab), Some(side), Some(entry), Some(request)) = (state.tab, state.side, state.entry.clone(), state.request_id) else {
                        return;
                    };
                    if state.selection.is_empty() {
                        return;
                    }
                    (tab, side, entry, request, state.selection.row_ids())
                };
                run(&services, tab, side, entry, request, rows);
            });
        }

        /// The dialog's state after a change.
        pub(crate) fn project(&self) -> Value {
            let (count, more) = self.selection.picked_lines();
            json!({
                "side": self.side.map(|side| if side == NativeStagingSide::Staged { "staged" } else { "unstaged" }),
                "loading": self.loading,
                "failed": self.failed,
                "hasPage": self.request_id.is_some(),
                "hasMore": (self.rows.len() as u64) < self.total,
                "count": count,
                "more": more,
                "allChecked": self.selection.all_checked(),
                "empty": self.selection.is_empty(),
                "canDiscard": self.side == Some(NativeStagingSide::Unstaged)
                    && self.entry.as_ref().is_some_and(|entry| entry.kind != NativeStatusEntryKind::Untracked),
            })
        }
    }
}

pub use line_selection_state::LineSelectionState;
