//! Interactive rebases, restacks and branch integration (the Dart
//! HistoryRewriteWorkflowService's rebase, restack and integrateBranch).

use crate::backend::SessionCalls;
use crate::busy::{BusyActivity, BusyService};
use crate::history_mutations::{HistoryMutations, branch_choices};
use crate::navigator::Navigator;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::session::{SessionError, SessionIdentity};
use crate::workspace::{Pane, WorkspaceService};
use gitlama_contract::advanced_rebase::{NativeRestackExecutionResult, NativeRestackExecutionState, NativeRestackPlanResult};
use gitlama_contract::history_operation::{NativeConflictPredictionKind, NativeHistoryMutationKind};
use gitlama_contract::rebase_operation::{
    NativeRebaseAction, NativeRebaseExecutionResult, NativeRebaseExecutionState, NativeRebaseFailureKind,
    NativeRebaseInstruction, NativeRebasePlanResult, NativeRebasePreviewResult,
};
use serde_json::{Value, json};
use std::rc::Rc;

pub fn action_name(action: NativeRebaseAction) -> &'static str {
    match action {
        NativeRebaseAction::Pick => "pick",
        NativeRebaseAction::Reword => "reword",
        NativeRebaseAction::Edit => "edit",
        NativeRebaseAction::Squash => "squash",
        NativeRebaseAction::Fixup => "fixup",
        NativeRebaseAction::Drop => "drop",
    }
}

pub fn parse_action(name: &str) -> Option<NativeRebaseAction> {
    Some(match name {
        "pick" => NativeRebaseAction::Pick,
        "reword" => NativeRebaseAction::Reword,
        "edit" => NativeRebaseAction::Edit,
        "squash" => NativeRebaseAction::Squash,
        "fixup" => NativeRebaseAction::Fixup,
        "drop" => NativeRebaseAction::Drop,
        _ => return None,
    })
}

pub fn failure_key(kind: NativeRebaseFailureKind) -> &'static str {
    match kind {
        NativeRebaseFailureKind::DirtyWorktree => "historyMutationFailureDirty",
        NativeRebaseFailureKind::DetachedHead => "historyMutationFailureDetached",
        NativeRebaseFailureKind::ActiveOperation => "historyMutationFailureActive",
        NativeRebaseFailureKind::PublicationConfirmationRequired => "historyMutationFailurePublished",
        NativeRebaseFailureKind::Stale => "rebaseStale",
        NativeRebaseFailureKind::Canceled => "historyMutationFailureCanceled",
        NativeRebaseFailureKind::InvalidRequest
        | NativeRebaseFailureKind::EmptyPlan
        | NativeRebaseFailureKind::InvalidPlan
        | NativeRebaseFailureKind::Failed
        | NativeRebaseFailureKind::Read
        | NativeRebaseFailureKind::Unsupported => "rebaseFailed",
    }
}

/// The status line of a finished rebase: (key, args, error).
pub fn rebase_message(result: &NativeRebaseExecutionResult) -> (&'static str, Value, bool) {
    let error = matches!(result.state, NativeRebaseExecutionState::Failed | NativeRebaseExecutionState::Stale);
    let (key, args) = match result.state {
        NativeRebaseExecutionState::Completed => ("rebaseCompleted", Value::Null),
        NativeRebaseExecutionState::Conflict => ("rebaseConflict", json!({"count": result.conflicting_paths.len()})),
        NativeRebaseExecutionState::EditStop => ("rebaseEditStop", Value::Null),
        NativeRebaseExecutionState::Interrupted => ("rebaseInterrupted", Value::Null),
        NativeRebaseExecutionState::Stale => ("rebaseStale", Value::Null),
        NativeRebaseExecutionState::Failed => ("rebaseFailed", Value::Null),
        NativeRebaseExecutionState::ReconciledWithWarning => ("historyMutationReconciledWarning", Value::Null),
        NativeRebaseExecutionState::OutcomeUncertain => ("mutationOutcomeUncertain", Value::Null),
    };
    (key, args, error)
}

/// The status line of a finished restack: (key, args, error).
pub fn restack_message(result: &NativeRestackExecutionResult) -> (&'static str, Value, bool) {
    let error = matches!(result.state, NativeRestackExecutionState::Failed | NativeRestackExecutionState::Stale);
    let steps = json!({"completed": result.completed_steps, "total": result.total_steps});
    let (key, args) = match result.state {
        NativeRestackExecutionState::Completed => ("restackCompleted", json!({"count": result.completed_steps})),
        NativeRestackExecutionState::Conflict => ("restackConflict", steps),
        NativeRestackExecutionState::Partial => ("restackPartial", steps),
        NativeRestackExecutionState::Stale => ("restackStale", Value::Null),
        NativeRestackExecutionState::Canceled => ("restackCanceled", Value::Null),
        NativeRestackExecutionState::Failed => ("restackFailed", Value::Null),
        NativeRestackExecutionState::ReconciledWithWarning => ("historyMutationReconciledWarning", Value::Null),
        NativeRestackExecutionState::OutcomeUncertain => ("mutationOutcomeUncertain", Value::Null),
    };
    (key, args, error)
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

fn instruction_value(instruction: &NativeRebaseInstruction) -> Value {
    json!({
        "id": instruction.id.to_string(),
        "action": action_name(instruction.action),
        "oid": instruction.oid,
        "subject": text(&instruction.subject),
        "published": instruction.published,
        "message": instruction.replacement_message.as_deref().map(text),
        "baseId": instruction.autosquash_base_id.map(|id| id.to_string()),
    })
}

fn plan_payload(plan: &NativeRebasePlanResult, conflicts: usize) -> Value {
    json!({
        "currentBranch": text(&plan.current_branch),
        "onto": plan.onto_name.as_deref().map(text).unwrap_or_else(|| plan.onto.chars().take(8).collect()),
        "publishedCount": plan.published_count,
        "conflicts": conflicts,
        "instructions": plan.instructions.iter().map(instruction_value).collect::<Vec<_>>(),
    })
}

/// The editor's answer as instructions: `edited` lists {id, action,
/// message} in their new order; unknown IDs are dropped.
pub fn edited_instructions(plan: &[NativeRebaseInstruction], edited: &Value) -> Vec<NativeRebaseInstruction> {
    edited
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let id = item["id"].as_str()?.parse::<u64>().ok()?;
                    let mut instruction = plan.iter().find(|instruction| instruction.id == id)?.clone();
                    instruction.action = parse_action(item["action"].as_str()?)?;
                    instruction.replacement_message = (instruction.action == NativeRebaseAction::Reword)
                        .then(|| item["message"].as_str().map(|message| message.as_bytes().to_vec()))
                        .flatten();
                    Some(instruction)
                })
                .collect()
        })
        .unwrap_or_default()
}

fn preview_payload(preview: &NativeRebasePreviewResult) -> Value {
    json!({
        "instructions": preview.instructions.iter().map(instruction_value).collect::<Vec<_>>(),
        "autosquashApplied": preview.autosquash_applied,
        "commands": [format!("git {}", preview.arguments.join(" ")), String::new(), text(&preview.todo).trim_end().to_owned()],
    })
}

fn restack_payload(plan: &NativeRestackPlanResult) -> Value {
    json!({
        "incomplete": plan.incomplete,
        "publishedCount": plan.published_count,
        "steps": plan.steps.iter().map(|step| json!({
            "branch": text(&step.branch),
            "onto": text(&step.new_parent),
            "published": step.published,
        })).collect::<Vec<_>>(),
    })
}

pub struct Rebases {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    busy: Rc<BusyService>,
    navigator: Rc<Navigator>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    mutations: Rc<HistoryMutations>,
}

impl Rebases {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        busy: Rc<BusyService>,
        navigator: Rc<Navigator>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        mutations: Rc<HistoryMutations>,
    ) -> Rc<Self> {
        Rc::new(Self { calls, workspace, busy, navigator, prompts, notices, mutations })
    }

    fn session(&self) -> Option<(u64, SessionIdentity)> {
        Some((self.workspace.active_tab_id()?, self.workspace.current()?.identity))
    }

    fn same(&self, tab: u64, identity: SessionIdentity) -> bool {
        self.session() == Some((tab, identity))
    }

    fn report(&self, (key, args, error): (&'static str, Value, bool)) {
        if error {
            self.notices.error(key, args);
        } else {
            self.notices.status(key, args);
        }
    }

    fn report_session(&self, operation: &str, error: SessionError) {
        self.notices.error(
            "operationFailureWithReason",
            json!({"operation": {"l10n": operation}, "reason": {"l10n": crate::changes::failure_reason_key(error.code())}}),
        );
    }

    /// Lets the user merge `source_name` or rebase onto it.
    pub async fn integrate(&self, source_name: Option<String>, target: Option<String>) {
        let choice = self.prompts.ask("chooseBranchIntegration", json!({"sourceName": source_name})).await;
        match choice.as_ref().and_then(Value::as_str) {
            Some("merge") => self.mutations.mutate(NativeHistoryMutationKind::Merge, source_name, target).await,
            Some("rebase") => Box::pin(self.rebase(target)).await,
            _ => {}
        }
    }

    /// Rebases the current branch interactively onto the branch at
    /// `target`, or one the user chooses, after predicting its conflicts.
    pub async fn rebase(&self, target: Option<String>) {
        let Some(session) = self.workspace.current() else { return };
        let Some((tab, identity)) = self.session() else { return };
        let choices = branch_choices(&session.snapshot.refs);
        let chosen = match target.as_ref().and_then(|target| choices.iter().find(|choice| choice["target"] == *target)) {
            Some(choice) => Some(choice.clone()),
            None => {
                let offered: Vec<Value> = choices.iter().filter(|choice| choice["head"] != true).cloned().collect();
                self.prompts.ask("chooseRebaseTarget", json!({"branches": offered})).await
            }
        };
        let Some(chosen) = chosen else { return };
        let (Some(onto), Some(name)) = (chosen["target"].as_str(), chosen["name"].as_str()) else { return };
        if !self.same(tab, identity) {
            return;
        }
        let plan = match self
            .calls
            .repository_session_rebase_plan(identity.native_id, identity.generation, onto.to_owned(), Some(name.as_bytes().to_vec()))
            .await
        {
            Ok(plan) => plan,
            Err(error) => return self.report_session("rebaseFailed", SessionError::from(error)),
        };
        if let Some(failure) = &plan.failure {
            return self.notices.error(failure_key(failure.kind), Value::Null);
        }
        let Some(plan_token) = plan.token else { return self.notices.error("rebaseFailed", Value::Null) };
        let prediction = match self.mutations.predict(tab, identity, NativeConflictPredictionKind::Rebase, onto.to_owned()).await {
            Ok(prediction) => prediction,
            Err(error) => return self.report_session("rebaseFailed", error),
        };
        // The editor belongs to the tab it was asked for.
        if !self.same(tab, identity) {
            return;
        }
        let conflicts = if prediction.failure.is_none() { prediction.conflicting_paths.len() } else { 0 };
        let Some(edit) = self.prompts.ask("editRebase", plan_payload(&plan, conflicts)).await else { return };
        if !self.same(tab, identity) {
            return;
        }
        let instructions = edited_instructions(&plan.instructions, &edit["instructions"]);
        let preview = match self
            .calls
            .repository_session_rebase_preview(
                identity.native_id,
                identity.generation,
                plan_token,
                instructions,
                edit["acknowledgePublishedHistory"].as_bool().unwrap_or(false),
                edit["applyAutosquash"].as_bool().unwrap_or(false),
            )
            .await
        {
            Ok(preview) => preview,
            Err(error) => return self.report_session("rebaseFailed", SessionError::from(error)),
        };
        if let Some(failure) = &preview.failure {
            return self.notices.error(failure_key(failure.kind), Value::Null);
        }
        let Some(token) = preview.token else { return self.notices.error("rebaseFailed", Value::Null) };
        if self.prompts.ask("confirmRebase", preview_payload(&preview)).await != Some(Value::Bool(true)) || !self.same(tab, identity) {
            return;
        }
        let calls = Rc::clone(&self.calls);
        let cancel: Rc<dyn Fn()> = Rc::new(move || {
            let calls = Rc::clone(&calls);
            crate::rt::spawn_detached(async move {
                drop(calls.repository_session_rebase_cancel(identity.native_id, identity.generation, token).await);
            });
        });
        let result = self
            .busy
            .run(
                Some(tab),
                BusyActivity::Rebase { current_branch: plan.current_branch.clone(), onto: name.as_bytes().to_vec() },
                true,
                Some(cancel),
                self.calls.repository_session_rebase_execute(identity.native_id, identity.generation, token),
            )
            .await;
        let result = match result {
            Ok(result) => result,
            Err(error) => return self.report_session("rebaseFailed", SessionError::from(error)),
        };
        self.report(rebase_message(&result));
        if matches!(
            result.state,
            NativeRebaseExecutionState::Conflict | NativeRebaseExecutionState::EditStop | NativeRebaseExecutionState::Interrupted
        ) {
            self.navigator.select_pane(Pane::Changes, Some(tab));
        }
    }

    /// Moves every branch stacked on `root` (or a root the user chooses)
    /// onto its updated base.
    pub async fn restack(&self, root: Option<String>) {
        let Some(session) = self.workspace.current() else { return };
        let Some((tab, identity)) = self.session() else { return };
        let branches: Vec<Value> = session
            .snapshot
            .refs
            .branches
            .iter()
            .map(|branch| json!({"name": text(&branch.name), "target": branch.target}))
            .collect();
        let root = match root.filter(|root| branches.iter().any(|branch| branch["name"] == *root)) {
            Some(root) => root,
            None => match self.prompts.ask("chooseRestackRoot", json!({"branches": branches})).await {
                Some(choice) => match choice["name"].as_str() {
                    Some(name) => name.to_owned(),
                    None => return,
                },
                None => return,
            },
        };
        if !self.same(tab, identity) {
            return;
        }
        let plan = match self
            .calls
            .repository_session_restack_plan(identity.native_id, identity.generation, root.as_bytes().to_vec())
            .await
        {
            Ok(plan) => plan,
            Err(error) => return self.report_session("restackFailed", SessionError::from(error)),
        };
        let Some(token) = plan.token.filter(|_| plan.failure.is_none()) else {
            return self.notices.error("restackFailed", Value::Null);
        };
        let cancel_plan = || {
            let calls = Rc::clone(&self.calls);
            crate::rt::spawn_detached(async move {
                drop(calls.repository_session_restack_cancel(identity.native_id, identity.generation, token).await);
            });
        };
        if plan.steps.is_empty() {
            cancel_plan();
            return self.notices.status("restackNothingToDo", Value::Null);
        }
        let acknowledge = match self.prompts.ask("reviewRestack", restack_payload(&plan)).await {
            Some(Value::Bool(acknowledge)) if self.same(tab, identity) => acknowledge,
            _ => return cancel_plan(),
        };
        let calls = Rc::clone(&self.calls);
        let cancel: Rc<dyn Fn()> = Rc::new(move || {
            let calls = Rc::clone(&calls);
            crate::rt::spawn_detached(async move {
                drop(calls.repository_session_restack_cancel(identity.native_id, identity.generation, token).await);
            });
        });
        let result = self
            .busy
            .run(
                Some(tab),
                BusyActivity::Restack { root_branch: plan.root_branch.clone() },
                true,
                Some(cancel),
                self.calls.repository_session_restack_execute(identity.native_id, identity.generation, token, acknowledge),
            )
            .await;
        let result = match result {
            Ok(result) => result,
            Err(error) => return self.report_session("restackFailed", SessionError::from(error)),
        };
        self.report(restack_message(&result));
        if matches!(result.state, NativeRestackExecutionState::Conflict | NativeRestackExecutionState::Partial) {
            self.navigator.select_pane(Pane::Changes, Some(tab));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instruction(id: u64, subject: &str) -> NativeRebaseInstruction {
        NativeRebaseInstruction {
            id,
            action: NativeRebaseAction::Pick,
            oid: format!("{id:040}"),
            subject: subject.as_bytes().to_vec(),
            published: false,
            replacement_message: None,
            autosquash_base_id: None,
        }
    }

    #[test]
    fn the_edited_plan_keeps_its_order_actions_and_reword_messages() {
        let plan = vec![instruction(1, "one"), instruction(2, "two"), instruction(3, "three")];
        let edited = json!([
            {"id": "3", "action": "reword", "message": "Three, better"},
            {"id": "1", "action": "pick", "message": "ignored"},
            {"id": "2", "action": "squash"},
            {"id": "9", "action": "pick"},
        ]);
        let result = edited_instructions(&plan, &edited);
        assert_eq!(result.iter().map(|item| item.id).collect::<Vec<_>>(), [3, 1, 2]);
        assert_eq!(result[0].replacement_message.as_deref(), Some(&b"Three, better"[..]));
        assert_eq!(result[1].replacement_message, None);
        assert_eq!(result[2].action, NativeRebaseAction::Squash);
    }

    #[test]
    fn outcomes_read_as_the_flutter_status_lines() {
        let result = NativeRestackExecutionResult {
            state: NativeRestackExecutionState::Conflict,
            completed_steps: 1,
            total_steps: 3,
            current_branch: None,
            recovery_refs: Vec::new(),
            conflicting_paths: Vec::new(),
            activity_ids: Vec::new(),
            failure: None,
        };
        let (key, args, error) = restack_message(&result);
        assert_eq!((key, error), ("restackConflict", false));
        assert_eq!((args["completed"].as_u64(), args["total"].as_u64()), (Some(1), Some(3)));
        let rebase = NativeRebaseExecutionResult {
            state: NativeRebaseExecutionState::Failed,
            failure: None,
            activity_ids: Vec::new(),
            conflicting_paths: Vec::new(),
            running_instruction: None,
        };
        assert_eq!(rebase_message(&rebase), ("rebaseFailed", Value::Null, true));
    }
}
