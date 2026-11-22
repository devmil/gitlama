//! Merges, cherry-picks and reverts (the Dart HistoryRewriteWorkflowService's
//! mutateHistory and integrateBranch): ask, preview, predict a merge's
//! conflicts, confirm and run while the tab is busy.

use crate::backend::SessionCalls;
use crate::busy::{BusyActivity, BusyService};
use crate::navigator::Navigator;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::session::{SessionError, SessionIdentity};
use crate::workspace::{Pane, WorkspaceService};
use gitlama_contract::dto::{NativeRepositoryRefs, NativeRepositorySnapshot, NativeWorkingTreeState};
use gitlama_contract::history_operation::{
    NativeConflictPredictionKind, NativeConflictPredictionResult, NativeHistoryLocalChanges, NativeHistoryMergeMode,
    NativeHistoryMutationExecutionResult, NativeHistoryMutationExecutionState, NativeHistoryMutationFailureKind,
    NativeHistoryMutationKind, NativeHistoryMutationPreview, NativeHistoryMutationRequest,
};
use serde_json::{Value, json};
use std::rc::Rc;

/// Overlapping paths a revert preview lists before "and N more".
const LISTED_PATHS: usize = 6;

pub fn kind_name(kind: NativeHistoryMutationKind) -> &'static str {
    match kind {
        NativeHistoryMutationKind::Merge => "merge",
        NativeHistoryMutationKind::CherryPick => "cherryPick",
        NativeHistoryMutationKind::Revert => "revert",
    }
}

pub fn parse_kind(name: &str) -> Option<NativeHistoryMutationKind> {
    Some(match name {
        "merge" => NativeHistoryMutationKind::Merge,
        "cherryPick" => NativeHistoryMutationKind::CherryPick,
        "revert" => NativeHistoryMutationKind::Revert,
        _ => return None,
    })
}

fn parse_merge_mode(name: &str) -> NativeHistoryMergeMode {
    match name {
        "fastForwardOnly" => NativeHistoryMergeMode::FastForwardOnly,
        "noFastForward" => NativeHistoryMergeMode::NoFastForward,
        _ => NativeHistoryMergeMode::FastForwardIfPossible,
    }
}

pub fn failure_key(kind: NativeHistoryMutationFailureKind) -> &'static str {
    match kind {
        NativeHistoryMutationFailureKind::InvalidRequest => "historyMutationFailureInvalid",
        NativeHistoryMutationFailureKind::DirtyWorktree => "historyMutationFailureDirty",
        NativeHistoryMutationFailureKind::DetachedHead => "historyMutationFailureDetached",
        NativeHistoryMutationFailureKind::ActiveOperation => "historyMutationFailureActive",
        NativeHistoryMutationFailureKind::PublicationConfirmationRequired => "historyMutationFailurePublished",
        NativeHistoryMutationFailureKind::Stale => "historyMutationStale",
        NativeHistoryMutationFailureKind::Canceled => "historyMutationFailureCanceled",
        NativeHistoryMutationFailureKind::Read | NativeHistoryMutationFailureKind::Failed => "historyMutationFailed",
        NativeHistoryMutationFailureKind::MergeCommit => "historyRevertMergeUnsupported",
        NativeHistoryMutationFailureKind::LocalChangesOverlap => "historyMutationFailureLocalChanges",
    }
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// Every local branch and every remote-tracking branch (`origin/main`).
pub fn branch_choices(refs: &NativeRepositoryRefs) -> Vec<Value> {
    let mut choices: Vec<Value> = refs
        .branches
        .iter()
        .map(|branch| json!({"name": text(&branch.name), "target": branch.target, "head": branch.head}))
        .collect();
    for remote in &refs.remotes {
        for branch in &remote.branches {
            choices.push(json!({
                "name": format!("{}/{}", text(&remote.name), text(&branch.name)),
                "target": branch.target,
                "head": false,
            }));
        }
    }
    choices
}

/// The status line of a finished mutation: (key, args, error).
pub fn result_message(preview: &NativeHistoryMutationPreview, result: &NativeHistoryMutationExecutionResult) -> (&'static str, Value, bool) {
    let error = matches!(result.state, NativeHistoryMutationExecutionState::Failed | NativeHistoryMutationExecutionState::Stale);
    let base = || -> (&'static str, Value) {
        match result.state {
            NativeHistoryMutationExecutionState::Completed => ("historyMutationCompleted", Value::Null),
            NativeHistoryMutationExecutionState::AlreadyContained => ("historyMutationAlreadyContained", Value::Null),
            NativeHistoryMutationExecutionState::Conflict => {
                ("historyMutationConflict", json!({"count": result.conflicting_paths.len()}))
            }
            NativeHistoryMutationExecutionState::Interrupted => ("historyMutationInterrupted", Value::Null),
            NativeHistoryMutationExecutionState::Stale => ("historyMutationStale", Value::Null),
            NativeHistoryMutationExecutionState::ReconciledWithWarning => ("historyMutationReconciledWarning", Value::Null),
            NativeHistoryMutationExecutionState::Failed => (
                failure_key(result.failure.as_ref().map_or(NativeHistoryMutationFailureKind::Failed, |failure| failure.kind)),
                Value::Null,
            ),
            NativeHistoryMutationExecutionState::OutcomeUncertain => ("mutationOutcomeUncertain", Value::Null),
        }
    };
    let completed = result.state == NativeHistoryMutationExecutionState::Completed;
    let set_aside = result.set_aside.as_ref().and_then(|saved| {
        if saved.pending {
            Some("historyRevertSetAsidePending")
        } else if saved.conflicted {
            Some("historyRevertSetAsideConflict")
        } else if saved.restored {
            completed.then_some("historyRevertSetAsideRestored")
        } else {
            Some("historyRevertSetAsideSaved")
        }
    });
    match set_aside {
        Some(key) if completed || result.set_aside.as_ref().is_some_and(|saved| saved.pending) => (key, Value::Null, error),
        // Both sentences: what happened, then where the changes are.
        Some(key) => {
            let (first, args) = base();
            ("historyRewriteTwoSentences", json!({"first": {"l10n": first, "args": args}, "second": {"l10n": key}}), error)
        }
        None if preview.no_commit && completed => ("historyRevertApplied", Value::Null, error),
        None => {
            let (key, args) = base();
            (key, args, error)
        }
    }
}

fn prediction_payload(prediction: Option<&NativeConflictPredictionResult>) -> Value {
    match prediction {
        None => Value::Null,
        Some(prediction) => json!({
            "failed": prediction.failure.is_some(),
            "conflicts": prediction.conflicting_paths.len(),
            "complete": prediction.complete,
        }),
    }
}

fn preview_payload(preview: &NativeHistoryMutationPreview, prediction: Option<&NativeConflictPredictionResult>) -> Value {
    let set_aside = preview.local_changes == NativeHistoryLocalChanges::SetAside;
    let mut commands = Vec::new();
    if set_aside {
        commands.push("git stash push --include-untracked -m \"GitLama before revert …\"".to_owned());
    }
    commands.push(format!("git {}", preview.arguments.join(" ")));
    if set_aside {
        commands.push("git stash apply --index <stash>".to_owned());
    }
    json!({
        "kind": kind_name(preview.kind),
        "source": preview.source_name.as_deref().map(text),
        "firstTarget": preview.targets.first(),
        "targets": preview.targets.len(),
        "currentBranch": text(&preview.current_branch),
        "localChanges": match preview.local_changes {
            NativeHistoryLocalChanges::None => "none",
            NativeHistoryLocalChanges::InPlace => "inPlace",
            NativeHistoryLocalChanges::SetAside => "setAside",
        },
        "overlappingPaths": preview.overlapping_paths.iter().take(LISTED_PATHS).map(|path| text(path)).collect::<Vec<_>>(),
        "overlapMore": preview.overlapping_paths.len().saturating_sub(LISTED_PATHS),
        "overlapCount": preview.overlapping_paths.len(),
        "stagedChanges": preview.staged_changes,
        "alreadyContained": preview.already_contained,
        "noCommit": preview.no_commit,
        "prediction": prediction_payload(prediction),
        "commands": commands,
    })
}

pub struct HistoryMutations {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    busy: Rc<BusyService>,
    navigator: Rc<Navigator>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    selected: Box<dyn Fn() -> Vec<String>>,
}

impl HistoryMutations {
    /// `selected` reads the commits History has selected.
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        busy: Rc<BusyService>,
        navigator: Rc<Navigator>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        selected: Box<dyn Fn() -> Vec<String>>,
    ) -> Rc<Self> {
        Rc::new(Self { calls, workspace, busy, navigator, prompts, notices, selected })
    }

    fn session(&self) -> Option<(u64, SessionIdentity)> {
        Some((self.workspace.active_tab_id()?, self.workspace.current()?.identity))
    }

    fn same(&self, tab: u64, identity: SessionIdentity) -> bool {
        self.session() == Some((tab, identity))
    }

    fn report_session(&self, operation: &str, error: SessionError) {
        self.notices.error(
            "operationFailureWithReason",
            json!({"operation": {"l10n": operation}, "reason": {"l10n": crate::changes::failure_reason_key(error.code())}}),
        );
    }

    /// Predicts the conflicts of bringing `target` in, while the tab is busy
    /// and cancelable. None when the prediction could not start.
    pub async fn predict(
        &self,
        tab: u64,
        identity: SessionIdentity,
        kind: NativeConflictPredictionKind,
        target: String,
    ) -> Result<NativeConflictPredictionResult, SessionError> {
        let start = self
            .calls
            .repository_session_conflict_prediction_begin(identity.native_id, identity.generation)
            .await
            .map_err(SessionError::from)?;
        let Some(token) = start.token else {
            return Ok(NativeConflictPredictionResult {
                kind,
                target,
                conflicting_paths: Vec::new(),
                analyzed_commits: 0,
                total_commits: 0,
                complete: false,
                activity_ids: Vec::new(),
                failure: start.failure,
            });
        };
        let calls = Rc::clone(&self.calls);
        let cancel: Rc<dyn Fn()> = Rc::new(move || {
            let calls = Rc::clone(&calls);
            crate::rt::spawn_detached(async move {
                drop(calls.repository_session_conflict_prediction_cancel(identity.native_id, identity.generation, token).await);
            });
        });
        self.busy
            .run(
                Some(tab),
                BusyActivity::ConflictPrediction,
                true,
                Some(cancel),
                self.calls.repository_session_conflict_prediction(identity.native_id, identity.generation, token, kind, target),
            )
            .await
            .map_err(SessionError::from)
    }

    /// Merges a branch, or cherry-picks or reverts `target` (or the commits
    /// History has selected). A merge predicts its conflicts first.
    pub async fn mutate(&self, kind: NativeHistoryMutationKind, source_name: Option<String>, target: Option<String>) {
        let Some(session) = self.workspace.current() else { return };
        let snapshot: Rc<NativeRepositorySnapshot> = Rc::clone(&session.snapshot);
        let Some((tab, identity)) = self.session() else { return };
        let selected = match (&target, kind) {
            (Some(target), NativeHistoryMutationKind::CherryPick | NativeHistoryMutationKind::Revert) => vec![target.clone()],
            _ => (self.selected)(),
        };
        let status = snapshot.status.as_ref();
        let payload = json!({
            "kind": kind_name(kind),
            "selectedTargets": selected,
            "initialSourceName": source_name,
            "initialTarget": target,
            "branches": branch_choices(&snapshot.refs),
            "publishedHistory": snapshot.refs.branches.iter().any(|branch| branch.head && branch.published),
            "conflictedWorktree": status.is_some_and(|status| status.working_tree == NativeWorkingTreeState::Conflicted),
            "activeOperation": status.is_some_and(|status| !status.operations.is_empty()),
        });
        let Some(answer) = self.prompts.ask("chooseHistoryMutation", payload).await else { return };
        if !self.same(tab, identity) {
            return;
        }
        let request = NativeHistoryMutationRequest {
            kind,
            targets: answer["targets"]
                .as_array()
                .map(|targets| targets.iter().filter_map(|target| target.as_str().map(str::to_owned)).collect())
                .unwrap_or_default(),
            source_name: answer["sourceName"].as_str().filter(|name| !name.is_empty()).map(|name| name.as_bytes().to_vec()),
            merge_mode: parse_merge_mode(answer["mergeMode"].as_str().unwrap_or_default()),
            acknowledge_published_history: answer["acknowledgePublishedHistory"].as_bool().unwrap_or(false),
            no_commit: answer["noCommit"].as_bool().unwrap_or(false),
        };
        let preview = match self
            .calls
            .repository_session_history_mutation_preview(identity.native_id, identity.generation, request)
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, Some(failure)) => return self.notices.error(failure_key(failure.kind), Value::Null),
                _ => return self.notices.error("historyMutationFailed", Value::Null),
            },
            Err(error) => return self.report_session("historyMutationFailed", SessionError::from(error)),
        };
        let mut prediction = None;
        if kind == NativeHistoryMutationKind::Merge
            && !preview.already_contained
            && let Some(target) = preview.targets.first().cloned()
        {
            match self.predict(tab, identity, NativeConflictPredictionKind::Merge, target).await {
                Ok(result) => prediction = Some(result),
                Err(error) => return self.report_session("historyMutationFailed", error),
            }
        }
        // The preview belongs to the tab it was asked for.
        if !self.same(tab, identity) {
            return;
        }
        if self.prompts.ask("confirmHistoryMutation", preview_payload(&preview, prediction.as_ref())).await != Some(Value::Bool(true))
            || !self.same(tab, identity)
        {
            return;
        }
        let calls = Rc::clone(&self.calls);
        let token = preview.token;
        let cancel: Rc<dyn Fn()> = Rc::new(move || {
            let calls = Rc::clone(&calls);
            crate::rt::spawn_detached(async move {
                drop(calls.repository_session_history_mutation_cancel(identity.native_id, identity.generation, token).await);
            });
        });
        let result = self
            .busy
            .run(
                Some(tab),
                BusyActivity::HistoryMutation {
                    kind: kind_name(preview.kind),
                    source: preview
                        .source_name
                        .as_deref()
                        .map(text)
                        .unwrap_or_else(|| preview.targets.first().map(|target| target.chars().take(10).collect()).unwrap_or_default()),
                    count: preview.targets.len(),
                    branch: text(&preview.current_branch),
                },
                true,
                Some(cancel),
                self.calls.repository_session_history_mutation_execute(identity.native_id, identity.generation, token),
            )
            .await;
        let result = match result {
            Ok(result) => result,
            Err(error) => return self.report_session("historyMutationFailed", SessionError::from(error)),
        };
        let (key, args, error) = result_message(&preview, &result);
        if error {
            self.notices.error(key, args);
        } else {
            self.notices.status(key, args);
        }
        if result.state == NativeHistoryMutationExecutionState::Conflict
            || result.set_aside.as_ref().is_some_and(|saved| saved.conflicted)
            || (preview.no_commit && result.state == NativeHistoryMutationExecutionState::Completed)
        {
            self.navigator.select_pane(Pane::Changes, Some(tab));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::history_operation::NativeHistorySetAside;

    fn preview(no_commit: bool) -> NativeHistoryMutationPreview {
        NativeHistoryMutationPreview {
            token: 1,
            kind: NativeHistoryMutationKind::Revert,
            arguments: vec!["revert".into()],
            targets: vec!["a".repeat(40)],
            source_name: None,
            current_branch: b"main".to_vec(),
            current_head: "b".repeat(40),
            published_history: false,
            already_contained: false,
            no_commit,
            local_changes: NativeHistoryLocalChanges::None,
            overlapping_paths: Vec::new(),
            staged_changes: false,
        }
    }

    fn result(state: NativeHistoryMutationExecutionState, set_aside: Option<NativeHistorySetAside>) -> NativeHistoryMutationExecutionResult {
        NativeHistoryMutationExecutionResult {
            state,
            failure: None,
            activity_ids: Vec::new(),
            conflicting_paths: vec![b"a".to_vec(), b"b".to_vec()],
            sequencer: None,
            set_aside,
        }
    }

    #[test]
    fn results_read_as_the_flutter_status_lines() {
        let completed = result(NativeHistoryMutationExecutionState::Completed, None);
        assert_eq!(result_message(&preview(false), &completed).0, "historyMutationCompleted");
        assert_eq!(result_message(&preview(true), &completed).0, "historyRevertApplied");
        let conflict = result(NativeHistoryMutationExecutionState::Conflict, None);
        let (key, args, error) = result_message(&preview(false), &conflict);
        assert_eq!((key, args["count"].as_u64(), error), ("historyMutationConflict", Some(2), false));
        let failed = result(NativeHistoryMutationExecutionState::Failed, None);
        assert_eq!(result_message(&preview(false), &failed), ("historyMutationFailed", Value::Null, true));
    }

    #[test]
    fn set_aside_changes_say_where_they_are() {
        let saved = |restored, conflicted, pending| NativeHistorySetAside {
            stash_object_id: "c".repeat(40),
            restored,
            conflicted,
            pending,
        };
        let restored = result(NativeHistoryMutationExecutionState::Completed, Some(saved(true, false, false)));
        assert_eq!(result_message(&preview(false), &restored).0, "historyRevertSetAsideRestored");
        let pending = result(NativeHistoryMutationExecutionState::Conflict, Some(saved(false, false, true)));
        assert_eq!(result_message(&preview(false), &pending).0, "historyRevertSetAsidePending");
        let kept = result(NativeHistoryMutationExecutionState::Interrupted, Some(saved(false, false, false)));
        let (key, args, _) = result_message(&preview(false), &kept);
        assert_eq!(key, "historyRewriteTwoSentences");
        assert_eq!(args["first"]["l10n"], "historyMutationInterrupted");
        assert_eq!(args["second"]["l10n"], "historyRevertSetAsideSaved");
    }

    #[test]
    fn remote_tracking_branches_are_named_with_their_remote() {
        let mut refs = NativeRepositoryRefs::default();
        refs.remotes.push(gitlama_contract::dto::NativeRepositoryRemote {
            name: b"origin".to_vec(),
            display_url: Vec::new(),
            branches: vec![gitlama_contract::dto::NativeRepositoryReference {
                name: b"main".to_vec(),
                full_name: b"refs/remotes/origin/main".to_vec(),
                target: "d".repeat(40),
                head: false,
                published: true,
                upstream: None,
                ahead: 0,
                behind: 0,
                upstream_gone: false,
            }],
        });
        assert_eq!(branch_choices(&refs)[0]["name"], "origin/main");
    }
}
