//! Session entry points of merge, cherry-pick and revert, and conflict prediction.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::history_operation::{
    NativeConflictPredictionKind, NativeConflictPredictionResult,
    NativeConflictPredictionStartResult, NativeHistoryMutationExecutionResult,
    NativeHistoryMutationExecutionState, NativeHistoryMutationFailure,
    NativeHistoryMutationFailureKind, NativeHistoryMutationPreviewResult,
    NativeHistoryMutationRequest,
};
use std::sync::Arc;

#[must_use]
pub fn repository_session_history_mutation_preview(
    session_id: u64,
    generation: u64,
    request: NativeHistoryMutationRequest,
) -> NativeHistoryMutationPreviewResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => {
                return history_mutation_preview_failure(NativeHistoryMutationFailureKind::Stale)
            }
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    crate::history_operation::preview(session_id, &repository, &activity, request)
}

#[must_use]
pub fn repository_session_history_mutation_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeHistoryMutationExecutionResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => {
                return history_mutation_execution_failure(NativeHistoryMutationFailureKind::Stale)
            }
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    crate::history_operation::execute(session_id, token, &repository, &activity)
}

#[must_use]
pub fn repository_session_history_mutation_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::history_operation::cancel(session_id, token),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_conflict_prediction_begin(
    session_id: u64,
    generation: u64,
) -> NativeConflictPredictionStartResult {
    if repository_for_session(session_id, generation).is_err() {
        return NativeConflictPredictionStartResult {
            token: None,
            failure: Some(NativeHistoryMutationFailure {
                kind: NativeHistoryMutationFailureKind::Stale,
            }),
        };
    }
    crate::history_operation::begin_prediction(session_id)
}

#[must_use]
pub fn repository_session_conflict_prediction(
    session_id: u64,
    generation: u64,
    token: u64,
    kind: NativeConflictPredictionKind,
    target: String,
) -> NativeConflictPredictionResult {
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(_) => {
            return NativeConflictPredictionResult {
                kind,
                target,
                conflicting_paths: Vec::new(),
                analyzed_commits: 0,
                total_commits: 0,
                complete: false,
                activity_ids: Vec::new(),
                failure: Some(NativeHistoryMutationFailure {
                    kind: NativeHistoryMutationFailureKind::Stale,
                }),
            };
        }
    };
    crate::history_operation::predict(session_id, token, &repository, kind, target)
}

#[must_use]
pub fn repository_session_conflict_prediction_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::history_operation::cancel_prediction(session_id, token),
        failure: None,
    }
}

pub(crate) fn history_mutation_preview_failure(
    kind: NativeHistoryMutationFailureKind,
) -> NativeHistoryMutationPreviewResult {
    NativeHistoryMutationPreviewResult {
        preview: None,
        failure: Some(NativeHistoryMutationFailure { kind }),
    }
}

pub(crate) fn history_mutation_execution_failure(
    kind: NativeHistoryMutationFailureKind,
) -> NativeHistoryMutationExecutionResult {
    NativeHistoryMutationExecutionResult {
        state: if kind == NativeHistoryMutationFailureKind::Stale {
            NativeHistoryMutationExecutionState::Stale
        } else {
            NativeHistoryMutationExecutionState::Failed
        },
        failure: Some(NativeHistoryMutationFailure { kind }),
        activity_ids: Vec::new(),
        conflicting_paths: Vec::new(),
        sequencer: None,
    }
}
