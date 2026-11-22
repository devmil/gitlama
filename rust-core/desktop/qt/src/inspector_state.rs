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
            "anchor": location.anchor,
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
