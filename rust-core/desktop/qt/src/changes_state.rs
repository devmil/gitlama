//! The Changes pane: its state, the unstaged and staged file lists (keyed
//! `RowModel`s) and the slots that select, stage and discard. The working
//! diff's rows are a `DiffModel`.

use crate::inspector_state::parse_whitespace;
use crate::plumbing::Commands;
use gitlama_contract::diff::NativeDiffLayout;
use gitlama_contract::dto::{
    NativeDiscardKind, NativeStagingPhase, NativeStagingScope, NativeStagingSide,
    NativeStatusEntry, NativeStatusEntryKind,
};
use gitlama_workbench::app::Services;
use gitlama_workbench::changes::{
    change_key, discard_kind_of, display_identity, entries_on, entry_in_folder, is_staged,
    is_unstaged, side_name,
};
use gitlama_workbench::inspector::DiffOptions;
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

/// The roles of a Changes file list.
pub const FILE_ROLES: &[&str] = &[
    "key",
    "path",
    "label",
    "depth",
    "directory",
    "expanded",
    "descendantCount",
    "status",
    "partial",
    "conflicted",
    "untracked",
    "discardable",
    "source",
    "selected",
    "pending",
];

/// A Changes file's label: its path, or "old → new" for a rename; as base
/// names in a tree.
fn file_label(entry: &NativeStatusEntry, basename: bool) -> String {
    let shown = |path: &gitlama_contract::dto::NativePathIdentity| {
        let value = gitlama_workbench::session::display_path(path).replace('\\', "/");
        if basename {
            value.rsplit('/').next().unwrap_or_default().to_owned()
        } else {
            value
        }
    };
    let target = shown(&entry.path);
    match &entry.source {
        Some(source) => format!("{} → {target}", shown(source)),
        None => target,
    }
}

pub use gitlama_workbench::changes::status_code;

/// Whether `entry` matches every whitespace-separated term of `query`.
pub fn filter_matches(entry: &NativeStatusEntry, query: &str) -> bool {
    let path = display_identity(entry).to_lowercase();
    query
        .to_lowercase()
        .split_whitespace()
        .all(|term| path.contains(term))
}

pub fn parse_side(name: &str) -> NativeStagingSide {
    if name == "staged" {
        NativeStagingSide::Staged
    } else {
        NativeStagingSide::Unstaged
    }
}

fn phase_name(phase: NativeStagingPhase) -> &'static str {
    match phase {
        NativeStagingPhase::Idle | NativeStagingPhase::Waiting => "waiting",
        NativeStagingPhase::Preparing => "preparing",
        NativeStagingPhase::Updating => "updating",
        NativeStagingPhase::Refreshing => "refreshing",
    }
}

/// The Changes pane of the active tab: its state and both file lists.
pub struct Projection {
    pub state: Value,
    pub unstaged: Vec<Value>,
    pub staged: Vec<Value>,
}

pub fn project(services: &Services, filter: &str, collapsed: &[HashSet<String>; 2]) -> Projection {
    let changes = &services.changes;
    let detail = &services.working_detail;
    let active = services.workspace.active_tab();
    let Some(tab) = active.as_ref() else {
        return Projection {
            state: json!({"hasStatus": false}),
            unstaged: Vec::new(),
            staged: Vec::new(),
        };
    };
    let status = tab
        .session
        .as_ref()
        .and_then(|session| session.snapshot.status.clone());
    let Some(status) = status else {
        return Projection {
            state: json!({"hasStatus": false, "tabId": tab.id}),
            unstaged: Vec::new(),
            staged: Vec::new(),
        };
    };
    let selection = changes.selection_of(tab.id);
    let filtering = !filter.trim().is_empty();
    let rows = |side: NativeStagingSide| -> (Vec<Value>, usize, usize, bool, bool, bool) {
        let all = entries_on(&status, side);
        let total = all.len();
        let pending = changes.pending_keys(tab.id, side);
        let selected = selection.of(side);
        let selected_entries: Vec<&NativeStatusEntry> = all
            .iter()
            .filter(|entry| selected.contains(&change_key(entry)))
            .collect();
        let selected_discard = discard_kind_of(selected_entries.iter().copied());
        let selected_discardable = selected_discard.is_some();
        let selected_clean_only = selected_discard == Some(NativeDiscardKind::Clean);
        let selected_all_pending =
            !selected.is_empty() && selected.iter().all(|key| pending.contains(key));
        let tree = services.settings.with(|document| {
            let mode = if side == NativeStagingSide::Staged {
                &document.appearance.changes_staged_mode
            } else {
                &document.appearance.changes_unstaged_mode
            };
            mode == "tree"
        });
        let file = |entry: &NativeStatusEntry, depth: usize| {
            let key = change_key(entry);
            json!({
                "key": key,
                "path": display_identity(entry),
                "label": file_label(entry, tree),
                "depth": depth,
                "directory": false,
                "expanded": false,
                "descendantCount": 0,
                "status": status_code(entry, side),
                "partial": is_staged(entry) && is_unstaged(entry),
                "conflicted": entry.kind == NativeStatusEntryKind::Unmerged,
                "untracked": entry.kind == NativeStatusEntryKind::Untracked,
                "discardable": gitlama_workbench::changes::discardable(entry),
                "source": entry.source.as_ref().map(gitlama_workbench::session::display_path),
                "selected": selected.contains(&key),
                "pending": pending.contains(&key),
            })
        };
        let visible: Vec<&NativeStatusEntry> = all
            .iter()
            .filter(|entry| !filtering || filter_matches(entry, filter))
            .collect();
        let visible_count = visible.len();
        if !tree {
            return (
                visible.into_iter().map(|entry| file(entry, 0)).collect(),
                total,
                visible_count,
                selected_discardable,
                selected_clean_only,
                selected_all_pending,
            );
        }
        let folded = &collapsed[usize::from(side == NativeStagingSide::Staged)];
        let shown = gitlama_workbench::path_tree::flatten(
            visible,
            |entry| display_identity(entry),
            folded,
            true,
            None,
        )
        .into_iter()
        .map(|row| match row.item {
            Some(entry) => file(entry, row.depth),
            None => {
                let descendant_count = row.descendants.len();
                let discard = discard_kind_of(row.descendants.iter().copied());
                let all_selected = descendant_count > 0
                    && row
                        .descendants
                        .iter()
                        .all(|entry| selected.contains(&change_key(entry)));
                json!({
                    "key": format!("dir:{}", row.identity),
                    "path": row.identity,
                    "label": row.label,
                    "depth": row.depth,
                    "directory": true,
                    "expanded": !folded.contains(&row.identity),
                    "descendantCount": descendant_count,
                    "status": "",
                    "partial": false,
                    "conflicted": false,
                    "untracked": discard == Some(NativeDiscardKind::Clean),
                    "discardable": discard.is_some(),
                    "source": null,
                    "selected": all_selected,
                    "pending": false,
                })
            }
        })
        .collect();
        (
            shown,
            total,
            visible_count,
            selected_discardable,
            selected_clean_only,
            selected_all_pending,
        )
    };
    let (
        unstaged,
        unstaged_total,
        unstaged_shown,
        selected_unstaged_discardable,
        selected_unstaged_clean_only,
        selected_unstaged_all_pending,
    ) = rows(NativeStagingSide::Unstaged);
    let (staged, staged_total, staged_shown, _, _, selected_staged_all_pending) =
        rows(NativeStagingSide::Staged);
    let key = detail.key();
    let entry = detail.entry();
    let options = detail.options();
    let document = detail.document();
    let state = json!({
        "hasStatus": true,
        "tabId": tab.id,
        "conflictFlow": changes.conflict_flow(tab.id),
        "busy": changes.busy(tab.id),
        "blocked": services.busy.is_blocked(Some(tab.id)),
        "canQueue": changes.can_stage_files(tab.id),
        "phase": changes.staging_phase(tab.id).map(phase_name),
        "pending": changes.pending_stages(tab.id),
        "stopped": changes.stopped_stages(tab.id),
        "focused": side_name(selection.focused),
        "filtering": filtering,
        "unstagedTotal": unstaged_total,
        "stagedTotal": staged_total,
        "unstagedShown": unstaged_shown,
        "stagedShown": staged_shown,
        "selectedUnstaged": selection.unstaged.len(),
        "selectedStaged": selection.staged.len(),
        "selectedUnstagedDiscardable": selected_unstaged_discardable,
        "selectedUnstagedCleanOnly": selected_unstaged_clean_only,
        "selectedUnstagedAllPending": selected_unstaged_all_pending,
        "selectedStagedAllPending": selected_staged_all_pending,
        "disabled": changes.disabled_selection_commands(tab.id),
        "headObjectId": status.head_object_id,
        // The last commit made in this repository: the staged list empties as it leaves.
        "commitSequence": services
            .commit
            .last_committed(tab.canonical_identity())
            .map_or(0, |committed| committed.sequence),
        "detail": {
            "identity": key.as_ref().map(|key| key.identity.clone()),
            "side": key.as_ref().map(|key| side_name(key.side)),
            "status": entry.as_ref().zip(key.as_ref()).map(|(entry, key)| status_code(entry, key.side)),
            "untracked": entry.as_ref().is_some_and(|entry| entry.kind == NativeStatusEntryKind::Untracked),
            "loading": detail.loading(),
            "waiting": detail.waiting(),
            "failure": detail.failure().map(|code| code.name()),
            "hasDiff": document.is_some(),
            "rows": document.as_ref().map_or(0, |document| document.total()),
            "selectedRows": detail.selected_rows().into_iter().collect::<Vec<_>>(),
            "forceText": detail.force_text(),
            "options": {
                "contextLines": options.context_lines,
                "layout": match options.layout { NativeDiffLayout::Unified => "unified", NativeDiffLayout::SideBySide => "sideBySide" },
            },
        },
    });
    Projection {
        state,
        unstaged,
        staged,
    }
}

/// Stages (or unstages) these rows of the working diff: lines, or a hunk's
/// header row for all its lines.
fn stage_row_ids(services: &Services, tab: u64, rows: Vec<String>) {
    let detail = &services.working_detail;
    let (Some(key), Some(entry), Some(document)) =
        (detail.key(), detail.entry(), detail.document())
    else {
        return;
    };
    if rows.is_empty() {
        return;
    }
    let changes = Rc::clone(&services.changes);
    let request = document.request_id();
    rt::spawn_detached(async move {
        changes
            .stage(
                tab,
                key.side,
                NativeStagingScope::Rows,
                vec![entry],
                Some(request),
                rows,
                Some(key.identity),
            )
            .await
    });
}

/// Discards these rows of the working diff after a review.
fn discard_row_ids(services: &Services, tab: u64, rows: Vec<String>) {
    let detail = &services.working_detail;
    let (Some(entry), Some(document)) = (detail.entry(), detail.document()) else {
        return;
    };
    if rows.is_empty() {
        return;
    }
    let changes = Rc::clone(&services.changes);
    let request = document.request_id();
    rt::spawn_detached(async move { changes.discard(tab, vec![entry], Some(request), rows).await });
}

#[qobject(ConvertToCamelCase)]
mod changes_state {
    use super::*;

    #[derive(Default)]
    pub struct ChangesState {
        pub commands: Option<Commands>,
        pub(crate) state: Value,
        /// The file filter, shared by both lists.
        pub filter: Rc<RefCell<String>>,
        /// The collapsed folders of the unstaged and the staged tree.
        pub collapsed: Rc<RefCell<[HashSet<String>; 2]>>,
    }

    impl ChangesState {
        qproperty!("state", Member = state, Notify = state_changed);

        #[qsignal]
        pub fn state_changed(&mut self);
        /// The answer of `search_diff`.
        #[qsignal]
        pub fn diff_searched(&mut self, query: String, case_sensitive: bool, matches: Value);
        /// The answer of `load_image_diff` for `key`.
        #[qsignal]
        pub fn image_diff_loaded(&mut self, key: String, image: Value);
        /// The answer of `load_hunks`.
        #[qsignal]
        pub fn hunks_loaded(&mut self, rows: Value);
        /// The answer of `copy_patch`: the patch text, empty when the
        /// selected rows hold no change or the diff was replaced.
        #[qsignal]
        pub fn patch_ready(&mut self, patch: String);
        /// A move started or ended, for the lists' animations.
        #[qsignal]
        pub fn effect(&mut self, kind: String, payload: String);

        /// Filters both lists by path terms; hidden files leave the selection.
        #[qslot]
        fn set_filter(&self, text: String) {
            let filter = Rc::clone(&self.filter);
            self.with_services(move |services| {
                *filter.borrow_mut() = text.clone();
                let Some(tab) = services.workspace.active_tab() else {
                    return;
                };
                let Some(status) = tab
                    .session
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let shown: HashSet<String> = status
                    .entries
                    .iter()
                    .filter(|entry| filter_matches(entry, &text))
                    .map(change_key)
                    .collect();
                services.changes.retain(tab.id, &shown);
            });
        }

        /// The rows of the shown diff that contain `query`: answered by
        /// `diff_searched` (matches null when the search failed).
        #[qslot]
        fn search_diff(&self, query: String, case_sensitive: bool) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(document) = services.working_detail.document() else {
                    return;
                };
                let shared = Rc::clone(&driver.changes);
                rt::spawn_detached(async move {
                    let matches = document.search(&query, case_sensitive).await;
                    let value = matches.map_or(Value::Null, Value::from);
                    shared
                        .borrow_mut()
                        .diff_searched(query, case_sensitive, value);
                });
            });
        }

        /// Decodes both sides of the working diff's image change: answered by
        /// `image_diff_loaded` with `key`.
        #[qslot]
        fn load_image_diff(&self, key: String) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let detail = &services.working_detail;
                let (Some(entry), Some(detail_key)) = (detail.entry(), detail.key()) else {
                    return;
                };
                let Some(identity) = services.workspace.current().map(|session| session.identity)
                else {
                    return;
                };
                let (old_path, new_path) =
                    gitlama_workbench::changes::diff_paths(&entry, detail_key.side);
                let calls = Rc::clone(&services.calls);
                let shared = Rc::clone(&driver.changes);
                let side = detail_key.side;
                rt::spawn_detached(async move {
                    let result = calls
                        .repository_session_working_image_diff(
                            identity.native_id,
                            identity.generation,
                            side,
                            old_path,
                            new_path,
                            8 * 1024 * 1024,
                        )
                        .await
                        .ok();
                    let value =
                        rt::blocking(move || gitlama_workbench::images::image_diff_value(result))
                            .await;
                    shared.borrow_mut().image_diff_loaded(key, value);
                });
            });
        }

        /// The patch of these rows of the shown diff (Copy as patch),
        /// answered by `patch_ready`; Latin-1 text when `latin1`.
        #[qslot]
        fn copy_patch(&self, rows: Vec<String>, latin1: bool) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(document) = services.working_detail.document() else {
                    return;
                };
                let shared = Rc::clone(&driver.changes);
                let patch = document.selection_patch(rows);
                rt::spawn_detached(async move {
                    let text = patch.await.map_or_else(String::new, |bytes| {
                        if latin1 {
                            bytes.iter().map(|byte| char::from(*byte)).collect()
                        } else {
                            String::from_utf8_lossy(&bytes).into_owned()
                        }
                    });
                    shared.borrow_mut().patch_ready(text);
                });
            });
        }

        /// Every hunk header row of the shown diff: answered by `hunks_loaded`.
        #[qslot]
        fn load_hunks(&self) {
            let Some(commands) = self.commands.clone() else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(document) = services.working_detail.document() else {
                    return;
                };
                let shared = Rc::clone(&driver.changes);
                rt::spawn_detached(async move {
                    let rows = document.hunks().await;
                    shared.borrow_mut().hunks_loaded(Value::from(rows));
                });
            });
        }

        /// Folds or unfolds folder `identity` of the tree `side`.
        #[qslot]
        fn toggle_folder(&self, side: String, identity: String) {
            let collapsed = Rc::clone(&self.collapsed);
            let Some(commands) = &self.commands else {
                return;
            };
            commands.post(move |driver| {
                {
                    let mut folded = collapsed.borrow_mut();
                    let set = &mut folded[usize::from(side == "staged")];
                    if !set.remove(&identity) {
                        set.insert(identity);
                    }
                }
                driver.project_changes();
            });
        }

        /// Selects `keys` in the list `side`, which takes the focus.
        #[qslot]
        fn select(&self, side: String, keys: Vec<String>) {
            self.with_tab(move |services, tab| {
                services
                    .changes
                    .select(tab, parse_side(&side), keys.into_iter().collect());
            });
        }

        /// Toggles `key` in the selection of `side`, which takes the focus.
        #[qslot]
        fn toggle_select(&self, side: String, key: String) {
            self.with_tab(move |services, tab| {
                services.changes.toggle_select(tab, parse_side(&side), key);
            });
        }

        /// Selects every file matching the current filter on `side`,
        /// including files inside collapsed folders.
        #[qslot]
        fn select_all(&self, side: String) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let filtering = !filter.trim().is_empty();
                let keys: HashSet<String> = entries_on(&status, side)
                    .iter()
                    .filter(|entry| !filtering || filter_matches(entry, &filter))
                    .map(change_key)
                    .collect();
                services.changes.select(tab, side, keys);
            });
        }

        /// Selects every file under `folder` matching the current filter on `side`.
        #[qslot]
        fn select_folder(&self, side: String, folder: String) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let filtering = !filter.trim().is_empty();
                let keys: HashSet<String> = entries_on(&status, side)
                    .iter()
                    .filter(|entry| {
                        (!filtering || filter_matches(entry, &filter))
                            && entry_in_folder(entry, &folder)
                    })
                    .map(change_key)
                    .collect();
                services.changes.select(tab, side, keys);
            });
        }

        /// Selects every file in display rows `from..=to` of `side`, expanding
        /// any folder rows in the range (including collapsed folders).
        #[qslot]
        fn select_range(&self, side: String, from: i32, to: i32) {
            let filter = self.filter.borrow().clone();
            let Some(commands) = &self.commands else {
                return;
            };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else {
                    return;
                };
                let Some(tab) = services.workspace.active_tab_id() else {
                    return;
                };
                let parsed = parse_side(&side);
                let model = if parsed == NativeStagingSide::Staged {
                    &driver.staged_rows
                } else {
                    &driver.unstaged_rows
                };
                let rows = model.borrow();
                let slice = rows.rows();
                if slice.is_empty() {
                    return;
                }
                let start = from.min(to).clamp(0, slice.len() as i32 - 1) as usize;
                let end = from.max(to).clamp(0, slice.len() as i32 - 1) as usize;
                let mut keys = HashSet::new();
                let mut folders = Vec::new();
                for row in &slice[start..=end] {
                    if row.get("directory").and_then(Value::as_bool) == Some(true) {
                        if let Some(path) = row.get("path").and_then(Value::as_str) {
                            folders.push(path.to_owned());
                        }
                    } else if let Some(key) = row.get("key").and_then(Value::as_str) {
                        keys.insert(key.to_owned());
                    }
                }
                drop(rows);
                if !folders.is_empty()
                    && let Some(status) = services
                        .workspace
                        .tab(tab)
                        .and_then(|tab| tab.session)
                        .and_then(|session| session.snapshot.status.clone())
                {
                    let filtering = !filter.trim().is_empty();
                    for entry in entries_on(&status, parsed) {
                        if (!filtering || filter_matches(&entry, &filter))
                            && folders.iter().any(|folder| entry_in_folder(&entry, folder))
                        {
                            keys.insert(change_key(&entry));
                        }
                    }
                }
                services.changes.select(tab, parsed, keys);
            });
        }

        #[qslot]
        fn focus(&self, side: String) {
            self.with_tab(move |services, tab| services.changes.focus(tab, parse_side(&side)));
        }

        /// Stages (or unstages, from the staged list) the currently selected
        /// files of `side`, including files inside collapsed folders.
        #[qslot]
        fn stage_selected_files(&self, side: String) {
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let entries = services.changes.selected_entries(tab, side);
                if entries.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move {
                    changes
                        .stage(
                            tab,
                            side,
                            NativeStagingScope::Files,
                            entries,
                            None,
                            Vec::new(),
                            None,
                        )
                        .await
                });
            });
        }

        /// Stages (or unstages) every filtered file under `folder` on `side`.
        #[qslot]
        fn stage_folder(&self, side: String, folder: String) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let filtering = !filter.trim().is_empty();
                let entries: Vec<NativeStatusEntry> = entries_on(&status, side)
                    .into_iter()
                    .filter(|entry| {
                        (!filtering || filter_matches(entry, &filter))
                            && entry_in_folder(entry, &folder)
                    })
                    .collect();
                if entries.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move {
                    changes
                        .stage(
                            tab,
                            side,
                            NativeStagingScope::Files,
                            entries,
                            None,
                            Vec::new(),
                            None,
                        )
                        .await
                });
            });
        }

        /// Stages (or unstages, from the staged list) the files `keys`.
        #[qslot]
        fn stage_files(&self, side: String, keys: Vec<String>) {
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let keys: HashSet<String> = keys.into_iter().collect();
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let entries: Vec<NativeStatusEntry> = entries_on(&status, side)
                    .into_iter()
                    .filter(|entry| keys.contains(&change_key(entry)))
                    .collect();
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move {
                    changes
                        .stage(
                            tab,
                            side,
                            NativeStagingScope::Files,
                            entries,
                            None,
                            Vec::new(),
                            None,
                        )
                        .await
                });
            });
        }

        /// Stages every file of `side` (the shown ones while filtering).
        #[qslot]
        fn stage_all(&self, side: String) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let all = entries_on(&status, side);
                let changes = Rc::clone(&services.changes);
                if filter.trim().is_empty() {
                    rt::spawn_detached(async move {
                        changes
                            .stage(
                                tab,
                                side,
                                NativeStagingScope::All,
                                all,
                                None,
                                Vec::new(),
                                None,
                            )
                            .await
                    });
                } else {
                    let shown = all
                        .into_iter()
                        .filter(|entry| filter_matches(entry, &filter))
                        .collect();
                    rt::spawn_detached(async move {
                        changes
                            .stage(
                                tab,
                                side,
                                NativeStagingScope::Files,
                                shown,
                                None,
                                Vec::new(),
                                None,
                            )
                            .await
                    });
                }
            });
        }

        /// Stages the selection of `side` (its chosen lines, or its files).
        #[qslot]
        fn stage_selection(&self, side: String) {
            self.with_tab(move |services, tab| {
                services.changes.stage_selection(tab, parse_side(&side))
            });
        }

        /// Space: stages or unstages what the focused list selects.
        #[qslot]
        fn toggle_focused(&self) {
            self.with_tab(|services, tab| services.changes.toggle_focused(tab));
        }

        /// Discards (or cleans) the unstaged files `keys` after a review.
        #[qslot]
        fn discard_files(&self, keys: Vec<String>) {
            self.with_tab(move |services, tab| {
                let keys: HashSet<String> = keys.into_iter().collect();
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let entries: Vec<NativeStatusEntry> =
                    entries_on(&status, NativeStagingSide::Unstaged)
                        .into_iter()
                        .filter(|entry| keys.contains(&change_key(entry)))
                        .collect();
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(
                    async move { changes.discard(tab, entries, None, Vec::new()).await },
                );
            });
        }

        /// Discards the currently selected unstaged files, including files
        /// inside collapsed folders.
        #[qslot]
        fn discard_selected_files(&self) {
            self.with_tab(move |services, tab| {
                let entries = services
                    .changes
                    .selected_entries(tab, NativeStagingSide::Unstaged);
                if entries.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(
                    async move { changes.discard(tab, entries, None, Vec::new()).await },
                );
            });
        }

        /// Discards every filtered unstaged file under `folder`.
        #[qslot]
        fn discard_folder(&self, folder: String) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let filtering = !filter.trim().is_empty();
                let entries: Vec<NativeStatusEntry> =
                    entries_on(&status, NativeStagingSide::Unstaged)
                        .into_iter()
                        .filter(|entry| {
                            (!filtering || filter_matches(entry, &filter))
                                && entry_in_folder(entry, &folder)
                        })
                        .collect();
                if entries.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(
                    async move { changes.discard(tab, entries, None, Vec::new()).await },
                );
            });
        }

        /// Discards every filtered unstaged file, including files inside
        /// collapsed folders.
        #[qslot]
        fn discard_all(&self) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let Some(status) = services
                    .workspace
                    .tab(tab)
                    .and_then(|tab| tab.session)
                    .and_then(|session| session.snapshot.status.clone())
                else {
                    return;
                };
                let filtering = !filter.trim().is_empty();
                let entries: Vec<NativeStatusEntry> =
                    entries_on(&status, NativeStagingSide::Unstaged)
                        .into_iter()
                        .filter(|entry| !filtering || filter_matches(entry, &filter))
                        .collect();
                if entries.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(
                    async move { changes.discard(tab, entries, None, Vec::new()).await },
                );
            });
        }

        /// Discards the selected diff lines, or the selected unstaged files.
        #[qslot]
        fn discard_selection(&self) {
            self.with_tab(|services, tab| services.changes.discard_selection(tab));
        }

        /// Stages (or unstages) the diff's selected lines.
        #[qslot]
        fn stage_rows(&self) {
            self.with_tab(|services, tab| {
                let rows: Vec<String> = services
                    .working_detail
                    .selected_rows()
                    .into_iter()
                    .collect();
                stage_row_ids(services, tab, rows);
            });
        }

        /// Stages (or unstages) one hunk: its header row stands for its lines.
        #[qslot]
        fn stage_hunk(&self, row: String) {
            self.with_tab(move |services, tab| stage_row_ids(services, tab, vec![row]));
        }

        /// Discards the diff's selected lines after a review.
        #[qslot]
        fn discard_rows(&self) {
            self.with_tab(|services, tab| {
                let rows: Vec<String> = services
                    .working_detail
                    .selected_rows()
                    .into_iter()
                    .collect();
                discard_row_ids(services, tab, rows);
            });
        }

        /// Discards one hunk after a review.
        #[qslot]
        fn discard_hunk(&self, row: String) {
            self.with_tab(move |services, tab| discard_row_ids(services, tab, vec![row]));
        }

        /// Chooses the diff's selected lines.
        #[qslot]
        fn set_selected_rows(&self, rows: Vec<String>) {
            self.with_services(move |services| {
                services
                    .working_detail
                    .set_selected_rows(rows.into_iter().collect())
            });
        }

        /// Drops the queued staging work that has not started.
        #[qslot]
        fn clear_queue(&self) {
            self.with_tab(|services, tab| services.changes.clear_pending_stages(tab));
        }

        #[qslot]
        fn dismiss_stopped(&self) {
            self.with_tab(|services, tab| services.changes.dismiss_stopped_stages(tab));
        }

        /// Loads the diff with these options (`forceText` shows a binary file as text).
        #[qslot]
        fn set_diff_options(
            &self,
            context_lines: i32,
            whitespace: String,
            layout: String,
            force_text: bool,
        ) {
            self.with_services(move |services| {
                let options = DiffOptions {
                    context_lines: context_lines.clamp(0, 100) as u32,
                    whitespace: parse_whitespace(&whitespace),
                    layout: if layout == "sideBySide" {
                        NativeDiffLayout::SideBySide
                    } else {
                        NativeDiffLayout::Unified
                    },
                };
                drop(
                    services
                        .settings
                        .update(|document| options.store(&mut document.appearance)),
                );
                services.working_detail.set_options(options, force_text);
            });
        }

        /// Shows three more unchanged lines around each hunk of the working
        /// diff, for this diff only.
        #[qslot]
        fn show_more_context(&self) {
            self.with_services(|services| {
                let detail = &services.working_detail;
                let mut options = detail.options();
                options.context_lines = (options.context_lines + 3).min(10_000);
                detail.set_options(options, detail.force_text());
            });
        }

        fn with_tab(&self, action: impl FnOnce(&Services, u64) + 'static) {
            self.with_services(move |services| {
                if let Some(tab) = services.workspace.active_tab_id() {
                    action(services, tab);
                }
            });
        }

        fn with_services(&self, action: impl FnOnce(&Services) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        action(&services);
                    }
                });
            }
        }
    }
}

pub use changes_state::ChangesState;
