//! Repository extensions (the Dart RepositoryExtensionCommands): for now the
//! `.gitignore` entry that hides a changed path.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::prompts::Prompts;
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

/// The field error of the ignore dialog for `kind`.
pub fn ignore_failure_key(kind: NativeExtensionFailureKind) -> &'static str {
    if kind == NativeExtensionFailureKind::InvalidRequest { "ignoreFailureInvalid" } else { "ignoreFailureWrite" }
}

pub struct Extensions {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
}

impl Extensions {
    pub fn new(calls: Rc<dyn SessionCalls>, workspace: Rc<WorkspaceService>, prompts: Rc<Prompts>, notices: Rc<Notices>) -> Rc<Self> {
        Rc::new(Self { calls, workspace, prompts, notices })
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
