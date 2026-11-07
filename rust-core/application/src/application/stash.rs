//! Session entry points of stash operations.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::stash::{
    NativeStashExecutionResult, NativeStashExecutionState, NativeStashFailure,
    NativeStashFailureKind, NativeStashPreviewResult, NativeStashRequest,
};
use std::sync::Arc;

#[must_use]
pub fn repository_session_stash_preview(
    session_id: u64,
    generation: u64,
    request: NativeStashRequest,
) -> NativeStashPreviewResult {
    let repository = match repository_for_session(session_id, generation) {
        Ok(repository) => repository,
        Err(_) => {
            return NativeStashPreviewResult {
                preview: None,
                failure: Some(NativeStashFailure {
                    kind: NativeStashFailureKind::Stale,
                }),
            }
        }
    };
    crate::stash::preview(session_id, &repository, request)
}

#[must_use]
pub fn repository_session_stash_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeStashExecutionResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => return stash_session_execution_failure(NativeStashFailureKind::Stale),
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    crate::stash::execute(session_id, token, &repository, &activity)
}

#[must_use]
pub fn repository_session_stash_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::stash::cancel(session_id, token),
        failure: None,
    }
}

pub(crate) fn stash_session_execution_failure(
    kind: NativeStashFailureKind,
) -> NativeStashExecutionResult {
    NativeStashExecutionResult {
        state: if kind == NativeStashFailureKind::Stale {
            NativeStashExecutionState::Stale
        } else {
            NativeStashExecutionState::Failed
        },
        failure: Some(NativeStashFailure { kind }),
        activity_ids: Vec::new(),
        stash_created: false,
        checkout_completed: false,
        reapply_completed: false,
        stash_retained: false,
    }
}
