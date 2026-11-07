//! Session entry points of interactive rebase, fixup suggestions and restack.
#![allow(clippy::wildcard_imports)]
use crate::advanced_rebase::{
    NativeAdvancedRebaseFailure, NativeAdvancedRebaseFailureKind, NativeFixupSuggestionResult,
    NativeFixupSuggestionState, NativeRestackExecutionResult, NativeRestackExecutionState,
    NativeRestackPlanResult,
};
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::rebase_operation::{
    NativeRebaseExecutionResult, NativeRebaseExecutionState, NativeRebaseFailure,
    NativeRebaseFailureKind, NativeRebaseInstruction, NativeRebasePlanResult,
    NativeRebasePreviewResult,
};
use std::sync::Arc;

#[must_use]
pub fn repository_session_rebase_plan(
    session_id: u64,
    generation: u64,
    onto: String,
    onto_name: Option<Vec<u8>>,
) -> NativeRebasePlanResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => return rebase_plan_failure(onto, onto_name, NativeRebaseFailureKind::Stale),
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    crate::rebase_operation::load_plan(session_id, &repository, &activity, onto, onto_name)
}

#[must_use]
pub fn repository_session_rebase_preview(
    session_id: u64,
    generation: u64,
    token: u64,
    instructions: Vec<NativeRebaseInstruction>,
    acknowledge_published_history: bool,
    apply_autosquash: bool,
) -> NativeRebasePreviewResult {
    if repository_for_session(session_id, generation).is_err() {
        return rebase_preview_failure(NativeRebaseFailureKind::Stale);
    }
    crate::rebase_operation::preview(
        session_id,
        token,
        instructions,
        acknowledge_published_history,
        apply_autosquash,
    )
}

#[must_use]
pub fn repository_session_rebase_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRebaseExecutionResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => return rebase_execution_failure(NativeRebaseFailureKind::Stale),
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    crate::rebase_operation::execute(session_id, token, &repository, &activity)
}

#[must_use]
pub fn repository_session_rebase_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::rebase_operation::cancel(session_id, token),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_fixup_suggestion(
    session_id: u64,
    generation: u64,
    selected_commit: Option<String>,
    paths: Vec<Vec<u8>>,
) -> NativeFixupSuggestionResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeFixupSuggestionResult {
            state: NativeFixupSuggestionState::NoBase,
            candidate: None,
            subject: None,
            fixup_message: None,
            squash_message: None,
            evidence: Vec::new(),
            activity_ids: Vec::new(),
            failure: Some(NativeAdvancedRebaseFailure {
                kind: NativeAdvancedRebaseFailureKind::Stale,
            }),
        };
    };
    crate::advanced_rebase::suggest_fixup_base(&repository, selected_commit, paths)
}

#[must_use]
pub fn repository_session_restack_plan(
    session_id: u64,
    generation: u64,
    root_branch: Vec<u8>,
) -> NativeRestackPlanResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeRestackPlanResult {
            token: None,
            root_branch,
            steps: Vec::new(),
            published_count: 0,
            incomplete: false,
            activity_ids: Vec::new(),
            failure: Some(NativeAdvancedRebaseFailure {
                kind: NativeAdvancedRebaseFailureKind::Stale,
            }),
        };
    };
    crate::advanced_rebase::plan_restack(session_id, &repository, root_branch)
}

#[must_use]
pub fn repository_session_restack_execute(
    session_id: u64,
    generation: u64,
    token: u64,
    acknowledge_published_history: bool,
) -> NativeRestackExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return NativeRestackExecutionResult {
            state: NativeRestackExecutionState::Stale,
            completed_steps: 0,
            total_steps: 0,
            current_branch: None,
            recovery_refs: Vec::new(),
            conflicting_paths: Vec::new(),
            activity_ids: Vec::new(),
            failure: Some(NativeAdvancedRebaseFailure {
                kind: NativeAdvancedRebaseFailureKind::Stale,
            }),
        };
    };
    crate::advanced_rebase::execute_restack(
        session_id,
        token,
        &repository,
        &activity,
        acknowledge_published_history,
    )
}

#[must_use]
pub fn repository_session_restack_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::advanced_rebase::cancel_restack(session_id, token),
        failure: None,
    }
}

pub(crate) fn rebase_plan_failure(
    onto: String,
    onto_name: Option<Vec<u8>>,
    kind: NativeRebaseFailureKind,
) -> NativeRebasePlanResult {
    NativeRebasePlanResult {
        token: None,
        onto,
        onto_name,
        current_branch: Vec::new(),
        current_head: String::new(),
        instructions: Vec::new(),
        published_count: 0,
        activity_ids: Vec::new(),
        failure: Some(NativeRebaseFailure { kind }),
    }
}

pub(crate) fn rebase_preview_failure(kind: NativeRebaseFailureKind) -> NativeRebasePreviewResult {
    NativeRebasePreviewResult {
        token: None,
        arguments: Vec::new(),
        todo: Vec::new(),
        instruction_count: 0,
        published_count: 0,
        instructions: Vec::new(),
        autosquash_applied: 0,
        failure: Some(NativeRebaseFailure { kind }),
    }
}

pub(crate) fn rebase_execution_failure(
    kind: NativeRebaseFailureKind,
) -> NativeRebaseExecutionResult {
    NativeRebaseExecutionResult {
        state: if kind == NativeRebaseFailureKind::Stale {
            NativeRebaseExecutionState::Stale
        } else {
            NativeRebaseExecutionState::Failed
        },
        failure: Some(NativeRebaseFailure { kind }),
        activity_ids: Vec::new(),
        conflicting_paths: Vec::new(),
        running_instruction: None,
    }
}
