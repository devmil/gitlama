//! Named snapshots of the active repository's working state (the Dart
//! NamedSnapshotCommands and NamedSnapshotsPanel workflows): capture,
//! list, restore after a preview, branch from, delete.

use crate::backend::SessionCalls;
use crate::navigator::Navigator;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::workspace::{Pane, WorkspaceService};
use gitlama_contract::named_snapshot::{
    NativeNamedSnapshot, NativeNamedSnapshotExecutionResult, NativeNamedSnapshotExecutionState, NativeNamedSnapshotFailureKind,
};
use serde_json::{Value, json};
use std::cell::RefCell;
use std::rc::Rc;

const PAGE: u32 = 24;

pub fn failure_key(kind: NativeNamedSnapshotFailureKind) -> &'static str {
    use NativeNamedSnapshotFailureKind::*;
    match kind {
        NothingToCapture => "namedSnapshotNothingToCapture",
        Missing => "namedSnapshotMissing",
        Corrupt => "namedSnapshotCorrupt",
        DirtyConflict => "namedSnapshotDirtyConflict",
        ActiveOperation => "namedSnapshotActiveOperation",
        Stale => "namedSnapshotStale",
        Conflict => "namedSnapshotConflict",
        Canceled => "namedSnapshotCanceled",
        TooLarge => "namedSnapshotTooLarge",
        InvalidRequest | Read | Write | Git => "namedSnapshotFailed",
    }
}

/// The panel's state.
#[derive(Clone, Debug, Default)]
pub struct Panel {
    pub entries: Vec<NativeNamedSnapshot>,
    pub next_offset: Option<u32>,
    pub loading: bool,
    pub busy: bool,
    pub failure: Option<&'static str>,
    pub selected: Option<u64>,
    /// Bumps when the panel should close (a restore met conflicts).
    pub close_sequence: u64,
}

pub struct SnapshotService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    navigator: Rc<Navigator>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    panel: RefCell<Panel>,
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

impl SnapshotService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        navigator: Rc<Navigator>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self { calls, workspace, navigator, prompts, notices, notifier, panel: RefCell::new(Panel::default()) })
    }

    pub fn panel(&self) -> Panel {
        self.panel.borrow().clone()
    }

    fn update(&self, change: impl FnOnce(&mut Panel)) {
        change(&mut self.panel.borrow_mut());
        self.notifier.notify(Topics::OPERATIONS);
    }

    fn session(&self) -> Option<(u64, u64)> {
        self.workspace.current().map(|session| (session.identity.native_id, session.identity.generation))
    }

    pub fn select(&self, id: u64) {
        self.update(|panel| panel.selected = Some(id));
    }

    /// Reads the first page again, or the next one.
    pub async fn load(&self, reset: bool) {
        let offset = if reset { 0 } else {
            match self.panel.borrow().next_offset {
                Some(offset) => offset,
                None => return,
            }
        };
        let Some((session, generation)) = self.session() else { return };
        self.update(|panel| {
            panel.loading = true;
            panel.failure = None;
            if reset {
                panel.entries.clear();
                panel.next_offset = None;
            }
        });
        let result = self.calls.repository_session_named_snapshots(session, generation, offset, PAGE).await;
        self.update(|panel| {
            panel.loading = false;
            match result {
                Ok(result) if result.failure.is_none() => {
                    if reset {
                        panel.entries.clear();
                    }
                    panel.entries.extend(result.entries);
                    panel.next_offset = result.next_offset;
                    if panel.selected.is_none_or(|selected| !panel.entries.iter().any(|entry| entry.id == selected)) {
                        panel.selected = panel.entries.first().map(|entry| entry.id);
                    }
                }
                Ok(result) => panel.failure = Some(failure_key(result.failure.map_or(NativeNamedSnapshotFailureKind::Git, |failure| failure.kind))),
                Err(_) => panel.failure = Some("namedSnapshotStale"),
            }
        });
    }

    /// Reports the outcome of a change; true when it went through.
    fn settle(&self, result: Result<NativeNamedSnapshotExecutionResult, ()>) -> Option<NativeNamedSnapshotExecutionResult> {
        match result {
            Ok(result) => {
                if result.state == NativeNamedSnapshotExecutionState::Conflict {
                    // The conflicts are resolved in Changes.
                    self.update(|panel| panel.close_sequence += 1);
                    self.navigator.select_pane(Pane::Changes, None);
                    return None;
                }
                if result.state == NativeNamedSnapshotExecutionState::OutcomeUncertain {
                    self.notices.error("mutationOutcomeUncertain", Value::Null);
                }
                if let Some(failure) = &result.failure
                    && !matches!(result.state, NativeNamedSnapshotExecutionState::Completed | NativeNamedSnapshotExecutionState::ReconciledWithWarning)
                {
                    let key = failure_key(failure.kind);
                    self.update(|panel| panel.failure = Some(key));
                    return None;
                }
                Some(result)
            }
            Err(()) => {
                self.update(|panel| panel.failure = Some("namedSnapshotStale"));
                None
            }
        }
    }

    pub async fn create(&self, name: String, include_untracked: bool, keep_index: bool) {
        let name = name.trim().to_owned();
        if name.is_empty() || self.panel.borrow().busy {
            return;
        }
        let Some((session, generation)) = self.session() else { return };
        self.update(|panel| {
            panel.busy = true;
            panel.failure = None;
        });
        let result = self
            .calls
            .repository_session_named_snapshot_create(session, generation, name, include_untracked, keep_index)
            .await
            .map_err(|_| ());
        let settled = self.settle(result);
        self.update(|panel| panel.busy = false);
        if let Some(result) = settled {
            if let Some(snapshot) = result.snapshot {
                self.update(|panel| panel.selected = Some(snapshot.id));
            }
            self.load(true).await;
        }
    }

    pub async fn restore(&self, id: u64) {
        let Some((session, generation)) = self.session() else { return };
        self.update(|panel| {
            panel.busy = true;
            panel.failure = None;
        });
        let preview = self.calls.repository_session_named_snapshot_restore_preview(session, generation, id).await;
        self.update(|panel| panel.busy = false);
        let preview = match preview {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, failure) => {
                    let key = failure_key(failure.map_or(NativeNamedSnapshotFailureKind::Git, |failure| failure.kind));
                    return self.update(|panel| panel.failure = Some(key));
                }
            },
            Err(_) => return self.update(|panel| panel.failure = Some("namedSnapshotStale")),
        };
        let payload = json!({
            "name": preview.snapshot.name,
            "paths": preview.replacement_paths.iter().map(|path| text(path)).collect::<Vec<_>>(),
            "truncated": preview.replacement_paths_truncated,
        });
        if self.prompts.ask("confirmSnapshotRestore", payload).await != Some(Value::Bool(true)) {
            let _ = self.calls.repository_session_named_snapshot_restore_cancel(session, generation, preview.token).await;
            return;
        }
        self.update(|panel| panel.busy = true);
        let result = self
            .calls
            .repository_session_named_snapshot_restore_execute(session, generation, preview.token)
            .await
            .map_err(|_| ());
        self.update(|panel| {
            panel.busy = false;
            panel.selected = Some(id);
        });
        if self.settle(result).is_some() {
            self.load(true).await;
        }
    }

    pub async fn branch(&self, id: u64) {
        let Some((session, generation)) = self.session() else { return };
        let branches: Vec<String> = self
            .workspace
            .current()
            .map(|session| session.snapshot.refs.branches.iter().map(|branch| text(&branch.name)).collect())
            .unwrap_or_default();
        let Some(answer) = self.prompts.ask("chooseSnapshotBranch", json!({"branches": branches})).await else { return };
        let Some(name) = answer.as_str().map(str::trim).filter(|name| !name.is_empty()).map(str::to_owned) else { return };
        self.update(|panel| {
            panel.busy = true;
            panel.failure = None;
        });
        let result = self
            .calls
            .repository_session_named_snapshot_branch(session, generation, id, name.into_bytes())
            .await
            .map_err(|_| ());
        if let Some(session) = self.workspace.current() {
            let _ = self.workspace.refresh_if_open(session.identity).await;
        }
        self.update(|panel| panel.busy = false);
        if self.settle(result).is_some() {
            self.notices.status("namedSnapshotBranchCreated", Value::Null);
        }
    }

    pub async fn delete(&self, id: u64) {
        let Some((session, generation)) = self.session() else { return };
        let name = self.panel.borrow().entries.iter().find(|entry| entry.id == id).map(|entry| entry.name.clone()).unwrap_or_default();
        if self.prompts.ask("confirmSnapshotDelete", json!({"name": name})).await != Some(Value::Bool(true)) {
            return;
        }
        self.update(|panel| {
            panel.busy = true;
            panel.failure = None;
        });
        let result = self.calls.repository_session_named_snapshot_delete(session, generation, id).await.map_err(|_| ());
        if let Some(session) = self.workspace.current() {
            let _ = self.workspace.refresh_if_open(session.identity).await;
        }
        self.update(|panel| panel.busy = false);
        if self.settle(result).is_some() {
            self.load(true).await;
        }
    }
}

/// The panel as the presentation shows it.
pub fn panel_value(panel: &Panel) -> Value {
    json!({
        "loading": panel.loading,
        "busy": panel.busy,
        "failure": panel.failure,
        "selected": panel.selected.map(|id| id.to_string()),
        "nextOffset": panel.next_offset,
        "closeSequence": panel.close_sequence,
        "entries": panel.entries.iter().map(|entry| json!({
            "id": entry.id.to_string(),
            "name": entry.name,
            "created": entry.created_at_unix_ms,
            "baseRef": entry.base_ref.as_deref().map(text),
            "baseOid": entry.base_oid,
            "objectId": entry.object_id,
            "staged": entry.staged_count,
            "unstaged": entry.unstaged_count,
            "untracked": entry.untracked_count,
            "ready": entry.state == gitlama_contract::named_snapshot::NativeNamedSnapshotState::Ready,
        })).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failures_name_their_messages() {
        assert_eq!(failure_key(NativeNamedSnapshotFailureKind::NothingToCapture), "namedSnapshotNothingToCapture");
        assert_eq!(failure_key(NativeNamedSnapshotFailureKind::Write), "namedSnapshotFailed");
    }
}
