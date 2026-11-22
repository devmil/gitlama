//! Repository extensions (the Dart RepositoryExtensionCommands): for now the
//! `.gitignore` entry that hides a changed path.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::session::display_path;
use crate::sidebar::{SidebarService, worktree_deletion_protected};
use crate::workspace::WorkspaceService;
use gitlama_contract::extensions::{
    NativeExtensionFailureKind, NativeExtensionMutationKind, NativeExtensionMutationRequest, NativeExtensionMutationResult,
    NativeExtensionMutationState,
};
use serde_json::{Value, json};
use std::rc::Rc;

/// The failure a mutation reports, unless its outcome is uncertain.
pub fn reported_failure(result: &NativeExtensionMutationResult) -> Option<NativeExtensionFailureKind> {
    if result.state == NativeExtensionMutationState::OutcomeUncertain {
        return None;
    }
    result.failure.as_ref().map(|failure| failure.kind).or(match result.state {
        NativeExtensionMutationState::Failed => Some(NativeExtensionFailureKind::Git),
        NativeExtensionMutationState::Canceled => Some(NativeExtensionFailureKind::Canceled),
        _ => None,
    })
}

/// What a failed extension change says (the Dart extensionFailureLabel).
pub fn failure_key(kind: NativeExtensionFailureKind) -> &'static str {
    match kind {
        NativeExtensionFailureKind::InvalidRequest => "extensionFailureInvalid",
        NativeExtensionFailureKind::Unavailable => "extensionFailureUnavailable",
        NativeExtensionFailureKind::Dirty => "extensionFailureDirty",
        NativeExtensionFailureKind::Locked => "extensionFailureLocked",
        NativeExtensionFailureKind::CurrentWorktree => "extensionFailureCurrent",
        NativeExtensionFailureKind::Stale => "extensionFailureStale",
        NativeExtensionFailureKind::Canceled => "extensionFailureCanceled",
        NativeExtensionFailureKind::TooLarge => "extensionFailureTooLarge",
        NativeExtensionFailureKind::Read | NativeExtensionFailureKind::Git => "extensionFailureGit",
    }
}

/// The field error of the ignore dialog for `kind`.
pub fn ignore_failure_key(kind: NativeExtensionFailureKind) -> &'static str {
    if kind == NativeExtensionFailureKind::InvalidRequest { "ignoreFailureInvalid" } else { "ignoreFailureWrite" }
}

pub struct Extensions {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    sidebar: Rc<SidebarService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
}

impl Extensions {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        sidebar: Rc<SidebarService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
    ) -> Rc<Self> {
        Rc::new(Self { calls, workspace, sidebar, prompts, notices })
    }

    /// Deletes linked worktree `index` of the sidebar's inventory after a
    /// confirmation (the Dart sidebar _delete).
    pub async fn delete_worktree(&self, index: usize) {
        let Some(inventory) = self.sidebar.worktrees() else { return };
        let Some(entry) = inventory.worktrees.get(index).cloned() else { return };
        if worktree_deletion_protected(&inventory, &entry) {
            return;
        }
        let Some(session) = self.workspace.current() else { return };
        let identity = session.identity;
        let payload = json!({"path": display_path(&entry.worktree_root)});
        if self.prompts.ask("confirmWorktreeDelete", payload).await != Some(Value::Bool(true)) {
            return;
        }
        if self.workspace.current().map(|session| session.identity) != Some(identity) {
            return;
        }
        self.sidebar.set_worktree_failure(None);
        let request = NativeExtensionMutationRequest {
            kind: NativeExtensionMutationKind::WorktreeDelete,
            path: None,
            worktree_root: Some(entry.worktree_root),
            pattern: None,
            reference: None,
        };
        let failure = match self.calls.repository_session_extension_execute(identity.native_id, identity.generation, request).await {
            Ok(result) if result.state == NativeExtensionMutationState::OutcomeUncertain => {
                self.notices.error("mutationOutcomeUncertain", Value::Null);
                self.sidebar.reload_worktrees();
                return;
            }
            Ok(result) => reported_failure(&result),
            Err(_) => Some(NativeExtensionFailureKind::Git),
        };
        if let Some(failure) = failure {
            self.notices.error(failure_key(failure), Value::Null);
        }
        self.sidebar.set_worktree_failure(failure.map(failure_key));
        self.sidebar.reload_worktrees();
    }

    /// Offers the `.gitignore` entry that matches exactly `path` and adds
    /// the entry the person confirms; a failed write asks again with the
    /// entry kept and the failure shown.
    pub async fn ignore(&self, path: String, directory: bool, tracked: bool) {
        let Some(session) = self.workspace.current() else { return };
        let identity = session.identity;
        let mut entry = gitlama_core::api::ignore_exact_pattern(path.into_bytes(), directory).unwrap_or_default();
        let mut failure: Option<&'static str> = None;
        loop {
            let payload = json!({"entry": entry, "directory": directory, "tracked": tracked, "failure": failure});
            let Some(answer) = self.prompts.ask("ignorePath", payload).await else { return };
            let Some(pattern) = answer.as_str().map(str::to_owned).filter(|pattern| !pattern.trim().is_empty()) else { return };
            if self.workspace.current().map(|session| session.identity) != Some(identity) {
                return;
            }
            let request = NativeExtensionMutationRequest {
                kind: NativeExtensionMutationKind::IgnoreAdd,
                path: None,
                worktree_root: None,
                pattern: Some(pattern.clone()),
                reference: None,
            };
            match self.calls.repository_session_extension_execute(identity.native_id, identity.generation, request).await {
                Ok(result) => {
                    if let Some(kind) = reported_failure(&result) {
                        entry = pattern;
                        failure = Some(ignore_failure_key(kind));
                        continue;
                    }
                    if result.state == NativeExtensionMutationState::OutcomeUncertain {
                        self.notices.error("mutationOutcomeUncertain", Value::Null);
                    }
                    return;
                }
                Err(_) => {
                    entry = pattern;
                    failure = Some("ignoreFailureWrite");
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::extensions::NativeExtensionFailure;

    fn result(state: NativeExtensionMutationState, failure: Option<NativeExtensionFailureKind>) -> NativeExtensionMutationResult {
        NativeExtensionMutationResult { state, activity_ids: vec![], failure: failure.map(|kind| NativeExtensionFailure { kind }) }
    }

    #[test]
    fn failures_are_reported_unless_the_outcome_is_uncertain() {
        use NativeExtensionMutationState::*;
        assert_eq!(reported_failure(&result(Completed, None)), None);
        assert_eq!(reported_failure(&result(Failed, None)), Some(NativeExtensionFailureKind::Git));
        assert_eq!(reported_failure(&result(Canceled, None)), Some(NativeExtensionFailureKind::Canceled));
        assert_eq!(
            reported_failure(&result(Failed, Some(NativeExtensionFailureKind::InvalidRequest))),
            Some(NativeExtensionFailureKind::InvalidRequest)
        );
        assert_eq!(reported_failure(&result(OutcomeUncertain, Some(NativeExtensionFailureKind::Git))), None);
        assert_eq!(ignore_failure_key(NativeExtensionFailureKind::InvalidRequest), "ignoreFailureInvalid");
        assert_eq!(ignore_failure_key(NativeExtensionFailureKind::Locked), "ignoreFailureWrite");
    }
}
