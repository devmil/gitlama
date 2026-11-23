//! The Changes pane: its state, the unstaged and staged file lists (keyed
//! `RowModel`s) and the slots that select, stage and discard. The working
//! diff's rows are a `DiffModel`.

use crate::inspector_state::parse_whitespace;
use crate::plumbing::Commands;
use gitlama_contract::diff::NativeDiffLayout;
use gitlama_contract::dto::{NativeChangeKind, NativeStagingPhase, NativeStagingScope, NativeStagingSide, NativeStatusEntry, NativeStatusEntryKind};
use gitlama_workbench::app::Services;
use gitlama_workbench::changes::{change_key, display_identity, entries_on, is_staged, is_unstaged, side_name};
use gitlama_workbench::inspector::DiffOptions;
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

/// The roles of a Changes file list.
pub const FILE_ROLES: &[&str] = &[
    "key", "path", "label", "depth", "directory", "expanded", "keys", "status", "partial", "conflicted", "untracked", "discardable", "source",
    "selected", "pending",
];

/// A Changes file's label: its path, or "old → new" for a rename; as base
/// names in a tree (the Dart _changesFileLabel).
fn file_label(entry: &NativeStatusEntry, basename: bool) -> String {
    let shown = |path: &gitlama_contract::dto::NativePathIdentity| {
        let value = gitlama_workbench::session::display_path(path).replace('\\', "/");
        if basename { value.rsplit('/').next().unwrap_or_default().to_owned() } else { value }
    };
    let target = shown(&entry.path);
    match &entry.source {
        Some(source) => format!("{} → {target}", shown(source)),
        None => target,
    }
}

/// The status letter of `entry` on `side` (the Dart changeStatusCode).
pub fn status_code(entry: &NativeStatusEntry, side: NativeStagingSide) -> &'static str {
    if entry.kind == NativeStatusEntryKind::Unmerged {
        return "U";
    }
    if entry.kind == NativeStatusEntryKind::Untracked {
        return "?";
    }
    if entry.kind == NativeStatusEntryKind::Ignored {
        return "!";
    }
    if entry.kind == NativeStatusEntryKind::Rename {
        return "R";
    }
    match if side == NativeStagingSide::Staged { entry.index } else { entry.worktree } {
        NativeChangeKind::Added => "A",
        NativeChangeKind::Deleted => "D",
        NativeChangeKind::Renamed => "R",
        NativeChangeKind::Copied => "C",
        NativeChangeKind::UpdatedButUnmerged => "U",
        NativeChangeKind::TypeChanged | NativeChangeKind::Modified => "M",
        NativeChangeKind::Unmodified => "!",
    }
}

/// Whether `entry` matches every whitespace-separated term of `query`.
pub fn filter_matches(entry: &NativeStatusEntry, query: &str) -> bool {
    let path = display_identity(entry).to_lowercase();
    query.to_lowercase().split_whitespace().all(|term| path.contains(term))
}

pub fn parse_side(name: &str) -> NativeStagingSide {
    if name == "staged" { NativeStagingSide::Staged } else { NativeStagingSide::Unstaged }
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
        return Projection { state: json!({"hasStatus": false}), unstaged: Vec::new(), staged: Vec::new() };
    };
    let status = tab.session.as_ref().and_then(|session| session.snapshot.status.clone());
    let Some(status) = status else {
        return Projection { state: json!({"hasStatus": false, "tabId": tab.id}), unstaged: Vec::new(), staged: Vec::new() };
    };
    let selection = changes.selection_of(tab.id);
    let filtering = !filter.trim().is_empty();
    let rows = |side: NativeStagingSide| -> (Vec<Value>, usize) {
        let all = entries_on(&status, side);
        let total = all.len();
        let pending = changes.pending_keys(tab.id, side);
        let selected = selection.of(side);
        let tree = services.settings.with(|document| {
            let mode = if side == NativeStagingSide::Staged { &document.appearance.changes_staged_mode } else { &document.appearance.changes_unstaged_mode };
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
                    "keys": [],
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
        let visible: Vec<&NativeStatusEntry> = all.iter().filter(|entry| !filtering || filter_matches(entry, filter)).collect();
        if !tree {
            return (visible.into_iter().map(|entry| file(entry, 0)).collect(), total);
        }
        let folded = &collapsed[usize::from(side == NativeStagingSide::Staged)];
        let shown = gitlama_workbench::path_tree::flatten(visible, |entry| display_identity(entry), folded, true, None)
            .into_iter()
            .map(|row| match row.item {
                Some(entry) => file(entry, row.depth),
                None => {
                    let keys: Vec<String> = row.descendants.iter().map(|entry| change_key(entry)).collect();
                    let entries: Vec<NativeStatusEntry> = row.descendants.iter().map(|entry| (*entry).clone()).collect();
                    let discard = gitlama_workbench::changes::discard_kind_of(&entries);
                    json!({
                        "key": format!("dir:{}", row.identity),
                        "path": row.identity,
                        "label": row.label,
                        "depth": row.depth,
                        "directory": true,
                        "expanded": !folded.contains(&row.identity),
                        "keys": keys,
                        "status": "",
                        "partial": false,
                        "conflicted": false,
                        "untracked": discard == Some(gitlama_contract::dto::NativeDiscardKind::Clean),
                        "discardable": discard.is_some(),
                        "source": null,
                        "selected": !keys.is_empty() && keys.iter().all(|key| selected.contains(key)),
                        "pending": false,
                    })
                }
            })
            .collect();
        (shown, total)
    };
    let (unstaged, unstaged_total) = rows(NativeStagingSide::Unstaged);
    let (staged, staged_total) = rows(NativeStagingSide::Staged);
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
        "unstagedShown": unstaged.iter().filter(|row| row["directory"] != true).count(),
        "stagedShown": staged.iter().filter(|row| row["directory"] != true).count(),
        "selectedUnstaged": selection.unstaged.len(),
        "selectedStaged": selection.staged.len(),
        "disabled": changes.disabled_selection_commands(tab.id),
        "headObjectId": status.head_object_id,
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
    Projection { state, unstaged, staged }
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
        /// A move started or ended, for the lists' animations.
        #[qsignal]
        pub fn effect(&mut self, kind: String, payload: String);

        /// Filters both lists by path terms; hidden files leave the selection.
        #[qslot]
        fn set_filter(&self, text: String) {
            let filter = Rc::clone(&self.filter);
            self.with_services(move |services| {
                *filter.borrow_mut() = text.clone();
                let Some(tab) = services.workspace.active_tab() else { return };
                let Some(status) = tab.session.and_then(|session| session.snapshot.status.clone()) else { return };
                let shown: HashSet<String> =
                    status.entries.iter().filter(|entry| filter_matches(entry, &text)).map(change_key).collect();
                services.changes.retain(tab.id, &shown);
            });
        }

        /// The rows of the shown diff that contain `query`: answered by
        /// `diff_searched` (matches null when the search failed).
        #[qslot]
        fn search_diff(&self, query: String, case_sensitive: bool) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(document) = services.working_detail.document() else { return };
                let shared = Rc::clone(&driver.changes);
                rt::spawn_detached(async move {
                    let matches = document.search(&query, case_sensitive).await;
                    let value = matches.map_or(Value::Null, |rows| Value::from(rows));
                    shared.borrow_mut().diff_searched(query, case_sensitive, value);
                });
            });
        }

        /// Decodes both sides of the working diff's image change: answered by
        /// `image_diff_loaded` with `key`.
        #[qslot]
        fn load_image_diff(&self, key: String) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let detail = &services.working_detail;
                let (Some(entry), Some(detail_key)) = (detail.entry(), detail.key()) else { return };
                let Some(identity) = services.workspace.current().map(|session| session.identity) else { return };
                let (old_path, new_path) = gitlama_workbench::changes::diff_paths(&entry, detail_key.side);
                let calls = Rc::clone(&services.calls);
                let shared = Rc::clone(&driver.changes);
                let side = detail_key.side;
                rt::spawn_detached(async move {
                    let result = calls
                        .repository_session_working_image_diff(identity.native_id, identity.generation, side, old_path, new_path, 8 * 1024 * 1024)
                        .await
                        .ok();
                    let value = rt::blocking(move || gitlama_workbench::images::image_diff_value(result)).await;
                    shared.borrow_mut().image_diff_loaded(key, value);
                });
            });
        }

        /// Every hunk header row of the shown diff: answered by `hunks_loaded`.
        #[qslot]
        fn load_hunks(&self) {
            let Some(commands) = self.commands.clone() else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(document) = services.working_detail.document() else { return };
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
            let Some(commands) = &self.commands else { return };
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
                services.changes.select(tab, parse_side(&side), keys.into_iter().collect());
            });
        }

        #[qslot]
        fn focus(&self, side: String) {
            self.with_tab(move |services, tab| services.changes.focus(tab, parse_side(&side)));
        }

        /// Stages (or unstages, from the staged list) the files `keys`.
        #[qslot]
        fn stage_files(&self, side: String, keys: Vec<String>) {
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let keys: HashSet<String> = keys.into_iter().collect();
                let Some(status) = services.workspace.tab(tab).and_then(|tab| tab.session).and_then(|session| session.snapshot.status.clone()) else {
                    return;
                };
                let entries: Vec<NativeStatusEntry> =
                    entries_on(&status, side).into_iter().filter(|entry| keys.contains(&change_key(entry))).collect();
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move {
                    changes.stage(tab, side, NativeStagingScope::Files, entries, None, Vec::new(), None).await
                });
            });
        }

        /// Stages every file of `side` (the shown ones while filtering).
        #[qslot]
        fn stage_all(&self, side: String) {
            let filter = self.filter.borrow().clone();
            self.with_tab(move |services, tab| {
                let side = parse_side(&side);
                let Some(status) = services.workspace.tab(tab).and_then(|tab| tab.session).and_then(|session| session.snapshot.status.clone()) else {
                    return;
                };
                let all = entries_on(&status, side);
                let changes = Rc::clone(&services.changes);
                if filter.trim().is_empty() {
                    rt::spawn_detached(async move {
                        changes.stage(tab, side, NativeStagingScope::All, all, None, Vec::new(), None).await
                    });
                } else {
                    let shown = all.into_iter().filter(|entry| filter_matches(entry, &filter)).collect();
                    rt::spawn_detached(async move {
                        changes.stage(tab, side, NativeStagingScope::Files, shown, None, Vec::new(), None).await
                    });
                }
            });
        }

        /// Stages the selection of `side` (its chosen lines, or its files).
        #[qslot]
        fn stage_selection(&self, side: String) {
            self.with_tab(move |services, tab| services.changes.stage_selection(tab, parse_side(&side)));
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
                let Some(status) = services.workspace.tab(tab).and_then(|tab| tab.session).and_then(|session| session.snapshot.status.clone()) else {
                    return;
                };
                let entries: Vec<NativeStatusEntry> = entries_on(&status, NativeStagingSide::Unstaged)
                    .into_iter()
                    .filter(|entry| keys.contains(&change_key(entry)))
                    .collect();
                let changes = Rc::clone(&services.changes);
                rt::spawn_detached(async move { changes.discard(tab, entries, None, Vec::new()).await });
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
                let detail = &services.working_detail;
                let (Some(key), Some(entry), Some(document)) = (detail.key(), detail.entry(), detail.document()) else {
                    return;
                };
                let rows: Vec<String> = detail.selected_rows().into_iter().collect();
                if rows.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                let request = document.request_id();
                rt::spawn_detached(async move {
                    changes
                        .stage(tab, key.side, NativeStagingScope::Rows, vec![entry], Some(request), rows, Some(key.identity))
                        .await
                });
            });
        }

        /// Discards the diff's selected lines after a review.
        #[qslot]
        fn discard_rows(&self) {
            self.with_tab(|services, tab| {
                let detail = &services.working_detail;
                let (Some(entry), Some(document)) = (detail.entry(), detail.document()) else { return };
                let rows: Vec<String> = detail.selected_rows().into_iter().collect();
                if rows.is_empty() {
                    return;
                }
                let changes = Rc::clone(&services.changes);
                let request = document.request_id();
                rt::spawn_detached(async move { changes.discard(tab, vec![entry], Some(request), rows).await });
            });
        }

        /// Chooses the diff's selected lines.
        #[qslot]
        fn set_selected_rows(&self, rows: Vec<String>) {
            self.with_services(move |services| services.working_detail.set_selected_rows(rows.into_iter().collect()));
        }

        #[qslot]
        fn dismiss_stopped(&self) {
            self.with_tab(|services, tab| services.changes.dismiss_stopped_stages(tab));
        }

        /// Loads the diff with these options (`forceText` shows a binary file as text).
        #[qslot]
        fn set_diff_options(&self, context_lines: i32, whitespace: String, layout: String, force_text: bool) {
            self.with_services(move |services| {
                let options = DiffOptions {
                    context_lines: context_lines.clamp(0, 100) as u32,
                    whitespace: parse_whitespace(&whitespace),
                    layout: if layout == "sideBySide" { NativeDiffLayout::SideBySide } else { NativeDiffLayout::Unified },
                };
                drop(services.settings.update(|document| options.store(&mut document.appearance)));
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
