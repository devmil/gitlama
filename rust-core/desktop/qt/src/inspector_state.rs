//! The detail inspector: what it shows and the slots that navigate it. The
//! diff rows are a `DiffModel`.

use crate::plumbing::Commands;
use gitlama_contract::diff::NativeDiffLayout;
use gitlama_contract::dto::NativeFileChangeKind;
use gitlama_workbench::inspector::{DiffOptions, InspectorService, Lens, Location, Phase, Scope, Target, change_path};
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

pub fn change_kind_name(kind: NativeFileChangeKind) -> &'static str {
    match kind {
        NativeFileChangeKind::Modified => "modified",
        NativeFileChangeKind::Added => "added",
        NativeFileChangeKind::Deleted => "deleted",
        NativeFileChangeKind::Renamed => "renamed",
        NativeFileChangeKind::Copied => "copied",
        NativeFileChangeKind::ModeChanged => "modeChanged",
        NativeFileChangeKind::TypeChanged => "typeChanged",
        NativeFileChangeKind::Binary => "binary",
        NativeFileChangeKind::Image => "image",
        NativeFileChangeKind::Submodule => "submodule",
        NativeFileChangeKind::Conflict => "conflict",
        NativeFileChangeKind::Untracked => "untracked",
    }
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

use gitlama_workbench::inspector::whitespace_name;
pub use gitlama_workbench::inspector::whitespace_of as parse_whitespace;

/// The inspector's state as QML reads it.
pub fn project(inspector: &InspectorService) -> Value {
    let state = inspector.current();
    let location = state.location.as_ref().map(|location| {
        json!({
            "kind": match location.target { Target::Commit(_) => "commit", Target::Comparison { .. } => "comparison" },
            "commit": location.target.commit(),
            "base": location.target.base(),
            "scope": match location.scope { Scope::Changed => "changed", Scope::All => "all" },
            "path": location.path.as_deref().map(text),
            "directory": location.directory,
            "lens": location.lens.name(),
            "lines": location.lines.map(|(first, last)| json!([first, last])),
            "historyCommit": location.history_commit,
            "anchor": location.anchor,
        })
    });
    // The contents lens: the file's lines, or why it shows none.
    let contents = state.file_bytes.as_ref().map(|bytes| {
        if bytes.is_empty() {
            return json!({"empty": true});
        }
        match std::str::from_utf8(bytes) {
            Ok(text) if !bytes.contains(&0) => {
                let mut lines: Vec<&str> = text.split('\n').collect();
                if lines.last() == Some(&"") {
                    lines.pop();
                }
                json!({"lines": lines.iter().map(|line| line.trim_end_matches('\r').replace('\t', "    ")).collect::<Vec<_>>()})
            }
            _ => {
                // Shown as text on request, NUL bytes as visible symbols.
                let text = String::from_utf8_lossy(bytes).replace('\0', "\u{2400}");
                let mut lines: Vec<&str> = text.split('\n').collect();
                if lines.last() == Some(&"") {
                    lines.pop();
                }
                json!({"binary": true, "lines": lines.iter().map(|line| line.replace('\t', "    ")).collect::<Vec<_>>()})
            }
        }
    });
    let history = state.history.as_ref().map(|history| {
        json!({
            "range": history.range,
            "incomplete": history.incomplete,
            "hasMore": history.next_offset.is_some(),
            "loadingMore": state.history_loading_more,
            "moreFailed": state.history_more_failed,
            "entries": history.entries.iter().map(|entry| json!({
                "commit": entry.commit,
                "author": text(&entry.author),
                "authorTime": entry.author_time,
                "summary": text(&entry.summary),
                "path": entry.path.as_deref().map(text),
                "oldPath": entry.old_path.as_deref().map(text),
            })).collect::<Vec<_>>(),
        })
    });
    let summary = state.inspection.as_ref().map(|inspection| {
        let detail = &inspection.detail;
        let message = text(&detail.message);
        let message = message.trim();
        let (subject, body) = match message.split_once('\n') {
            Some((subject, body)) => (subject.to_owned(), body.trim().to_owned()),
            None => (message.to_owned(), String::new()),
        };
        json!({
            "commit": detail.commit,
            "parents": detail.parents,
            "author": text(&detail.author),
            "avatarHash": detail.avatar_hash,
            "authorTime": detail.author_time,
            "committer": text(&detail.committer),
            "committerTime": detail.committer_time,
            "subject": subject,
            "body": body,
            "message": message,
        })
    });
    let files: Vec<Value> = state
        .inspection
        .as_ref()
        .map(|inspection| {
            inspection
                .files
                .iter()
                .map(|file| {
                    json!({
                        "path": text(change_path(file)),
                        "oldPath": text(&file.old_path),
                        "newPath": text(&file.new_path),
                        "kind": change_kind_name(file.kind),
                        "mode": file.new_mode,
                        "similarity": file.similarity,
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    let options = inspector.diff_options();
    json!({
        "phase": match state.phase { Phase::Empty => "empty", Phase::Loading => "loading", Phase::Ready => "ready", Phase::Failed => "failed" },
        "failure": state.failure.map(|code| code.name()),
        "contentFailure": state.content_failure.map(|code| code.name()),
        "contentLoading": state.content_loading,
        "location": location,
        "summary": summary,
        "files": files,
        "hasDiff": state.diff.is_some(),
        "contents": contents,
        "hasBlame": state.blame.is_some(),
        "history": history,
        "historyEntry": state.history_entry.as_ref().map(|inspection| {
            let message = text(&inspection.detail.message);
            json!({
                "commit": inspection.detail.commit,
                "subject": message.trim().lines().next().unwrap_or_default(),
                "author": text(&inspection.detail.author),
                "authorTime": inspection.detail.author_time,
                "files": inspection.files.len(),
            })
        }),
        "diffRows": state.diff.as_ref().map_or(0, |diff| diff.total()),
        "lensAvailability": state.lens_availability.iter().map(|(lens, reason)| json!({"lens": lens.name(), "reason": reason.map(|reason| reason.name())})).collect::<Vec<_>>(),
        "canBack": state.can_back,
        "canForward": state.can_forward,
        "allChangesTooLarge": state.all_changes_too_large,
        "options": {
            "contextLines": options.context_lines,
            "whitespace": whitespace_name(options.whitespace),
            "layout": match options.layout { NativeDiffLayout::Unified => "unified", NativeDiffLayout::SideBySide => "sideBySide" },
        },
    })
}

#[qobject(ConvertToCamelCase)]
mod inspector_state {
    use super::*;

    #[derive(Default)]
    pub struct InspectorState {
        pub commands: Option<Commands>,
        pub(crate) state: Value,
        /// The file menus' host actions, set once the services run.
        pub(crate) actions: Option<Rc<gitlama_workbench::inspector_actions::InspectorActions>>,
    }

    impl InspectorState {
        qproperty!("state", Member = state, Notify = state_changed);

        #[qsignal]
        pub fn state_changed(&mut self);

        #[qslot]
        fn back(&self) {
            self.with_inspector(|inspector| async move { inspector.jump(-1).await });
        }

        #[qslot]
        fn forward(&self) {
            self.with_inspector(|inspector| async move { inspector.jump(1).await });
        }

        #[qslot]
        fn up(&self) {
            self.with_inspector(|inspector| async move {
                inspector.up().await;
            });
        }

        #[qslot]
        fn retry(&self) {
            self.with_inspector(|inspector| async move { inspector.retry().await });
        }

        /// Shows file `path` of the target (an empty path shows every change).
        #[qslot]
        fn select_file(&self, path: String) {
            self.with_inspector(move |inspector| async move {
                let Some(location) = inspector.current().location else { return };
                let path = (!path.is_empty()).then(|| path.into_bytes());
                inspector
                    .navigate(Location { path, directory: false, anchor: 0, ..location }, true, false, None)
                    .await;
            });
        }

        /// Shows lens `lens` (diff, contents, blame, history) of the file.
        #[qslot]
        fn select_lens(&self, lens: String) {
            self.with_inspector(move |inspector| async move {
                let Some(location) = inspector.current().location else { return };
                let lens = match lens.as_str() {
                    "contents" => Lens::Contents,
                    "blame" => Lens::Blame,
                    "history" => Lens::History,
                    _ => Lens::Diff,
                };
                inspector.navigate(Location { lens, anchor: 0, ..location }, true, false, None).await;
            });
        }

        /// What the file menus of this inspector can do:
        /// {canOpenWorkingCopy, remote, hasDiffTool}.
        #[qslot]
        fn file_host(&self) -> Value {
            let Some(actions) = &self.actions else { return json!({}) };
            json!({
                "canOpenWorkingCopy": actions.can_open_working_copy(),
                "remote": actions.remote(),
                "hasDiffTool": actions.diff_tool().is_some(),
            })
        }

        /// Whether the repository-relative `path` exists in the working tree.
        #[qslot]
        fn exists_in_working_tree(&self, path: String) -> bool {
            self.actions.as_ref().is_some_and(|actions| actions.exists_in_working_tree(&path))
        }

        /// Shows lens `lens` of `path` (a folder when `directory`) in
        /// `revision`, or in the shown target when it is that target's commit;
        /// the shown scope stays while the target does.
        #[qslot]
        fn open_file_lens(&self, path: String, lens: String, directory: bool, revision: String) {
            self.with_inspector(move |inspector| async move {
                let shown = inspector.current().location;
                let target = match &shown {
                    Some(location) if revision.is_empty() || location.target.commit() == revision => location.target.clone(),
                    _ if revision.is_empty() => return,
                    _ => Target::Commit(revision),
                };
                let scope = shown.as_ref().filter(|location| location.target == target).map_or(Scope::Changed, |location| location.scope);
                let lens = if directory {
                    Lens::History
                } else {
                    match lens.as_str() {
                        "contents" => Lens::Contents,
                        "blame" => Lens::Blame,
                        "history" => Lens::History,
                        _ => Lens::Diff,
                    }
                };
                let location = Location { scope, path: Some(path.into_bytes()), directory, lens, ..Location::of(target) };
                inspector.navigate(location, true, false, None).await;
            });
        }

        /// Restores `path` to its content in `commit` after a preview.
        #[qslot]
        fn restore_file(&self, path: String, commit: String) {
            let Some(commands) = &self.commands else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let actions = Rc::clone(&services.inspector_actions);
                rt::spawn_detached(async move { actions.restore(path, commit).await });
            });
        }

        /// Opens a change in the configured diff tool.
        #[qslot]
        fn external_diff(&self, old_revision: String, new_revision: String, old_path: String, new_path: String) {
            let Some(commands) = &self.commands else { return };
            let old_revision = (!old_revision.is_empty()).then_some(old_revision);
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let actions = Rc::clone(&services.inspector_actions);
                rt::spawn_detached(async move { actions.external_diff(old_revision, new_revision, old_path, new_path).await });
            });
        }

        /// Shows lens `lens` of the working-tree `path` (a folder when
        /// `directory`) at the current commit in the History inspector.
        #[qslot]
        fn inspect_working_file(&self, path: String, lens: String, directory: bool) {
            let Some(commands) = &self.commands else { return };
            commands.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let head = services.workspace.current().and_then(|session| session.snapshot.status.as_ref()?.head_object_id.clone());
                let Some(head) = head else {
                    services.notices.status("commandContextUnavailable", Value::Null);
                    return;
                };
                let navigator = Rc::clone(&services.navigator);
                let inspector = Rc::clone(&services.inspector);
                rt::spawn_detached(async move {
                    navigator.show_commit(head.clone(), None, false, false).await;
                    let lens = match lens.as_str() {
                        "blame" => Lens::Blame,
                        "contents" => Lens::Contents,
                        _ => Lens::History,
                    };
                    let location = Location {
                        path: Some(path.into_bytes()),
                        directory,
                        lens,
                        ..Location::of(Target::Commit(head))
                    };
                    inspector.navigate(location, true, false, None).await;
                });
            });
        }

        /// Shows commit `commit` (a parent of the shown one).
        #[qslot]
        fn show_commit(&self, commit: String) {
            self.with_inspector(move |inspector| async move {
                inspector.navigate(Location::of(Target::Commit(commit)), true, false, None).await;
            });
        }

        /// Lists every file of the shown commit, or only the changed ones.
        #[qslot]
        fn set_all_files(&self, all: bool) {
            self.with_inspector(move |inspector| async move {
                let Some(location) = inspector.current().location else { return };
                let scope = if all { Scope::All } else { Scope::Changed };
                inspector.navigate(Location { scope, anchor: 0, ..location }, true, false, None).await;
            });
        }

        /// Loads the diff again with these options.
        #[qslot]
        fn set_diff_options(&self, context_lines: i32, whitespace: String, layout: String) {
            let options = DiffOptions {
                context_lines: context_lines.clamp(0, 100) as u32,
                whitespace: parse_whitespace(&whitespace),
                layout: if layout == "sideBySide" { NativeDiffLayout::SideBySide } else { NativeDiffLayout::Unified },
            };
            // The stored preferences are the source; the driver reloads
            // every diff that shows other options.
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        drop(services.settings.update(|document| options.store(&mut document.appearance)));
                    }
                });
            }
        }

        /// Loads the blame page holding line `index` (0-based).
        #[qslot]
        fn ensure_blame_row(&self, index: i32) {
            self.with_inspector(move |inspector| async move { inspector.ensure_blame_row(index.max(0) as u64).await });
        }

        /// Blames line `index`'s file in the parent of its commit.
        #[qslot]
        fn blame_before(&self, index: i32) {
            self.with_inspector(move |inspector| async move { inspector.blame_before(index.max(0) as u64).await });
        }

        /// The history of lines `first`…`last` (1-based).
        #[qslot]
        fn line_history(&self, first: i32, last: i32) {
            self.with_inspector(move |inspector| async move {
                inspector.line_history(first.max(1) as u64, last.max(first).max(1) as u64).await
            });
        }

        #[qslot]
        fn select_history_entry(&self, commit: String) {
            self.with_inspector(move |inspector| async move { inspector.select_history_entry(commit).await });
        }

        #[qslot]
        fn load_more_history(&self) {
            self.with_inspector(|inspector| async move { inspector.load_more_history().await });
        }

        /// Records the first visible row for Back and Forward.
        #[qslot]
        fn report_anchor(&self, anchor: i32) {
            self.with_inspector(move |inspector| async move {
                inspector.report_anchor(anchor.max(0) as u64);
            });
        }

        fn with_inspector<F, Fut>(&self, action: F)
        where
            F: FnOnce(Rc<InspectorService>) -> Fut + 'static,
            Fut: std::future::Future<Output = ()> + 'static,
        {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        rt::spawn_detached(action(Rc::clone(&services.inspector)));
                    }
                });
            }
        }
    }
}

pub use inspector_state::InspectorState;
