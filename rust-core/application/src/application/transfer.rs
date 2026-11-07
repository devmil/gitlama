//! Session entry points of fetch, pull, push and remote branch deletion.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::dto::{
    NativeCloneCommandResult, NativeCloneFailure, NativeCloneFailureKind, NativeHostKeyResult,
};
use crate::transfer::{
    NativeTransferExecutionResult, NativeTransferExecutionState, NativeTransferFailure,
    NativeTransferFailureKind, NativeTransferPreviewResult, NativeTransferRequest,
};
use std::sync::Arc;

#[must_use]
pub fn repository_session_transfer_preview(
    session_id: u64,
    generation: u64,
    request: NativeTransferRequest,
) -> NativeTransferPreviewResult {
    let repository = match repository_for_session(session_id, generation) {
        Ok(repository) => repository,
        Err(_) => {
            return NativeTransferPreviewResult {
                preview: None,
                failure: Some(NativeTransferFailure {
                    kind: NativeTransferFailureKind::Stale,
                }),
            }
        }
    };
    crate::transfer::preview(session_id, generation, &repository, request)
}

#[must_use]
pub fn repository_session_transfer_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeTransferExecutionResult {
    repository_session_transfer_execute_inner(session_id, generation, token, None, false)
}

/// Runs a previewed fetch that the application started by itself. It never
/// prompts, and the operation center lists it as background work.
#[must_use]
pub fn repository_session_transfer_execute_background(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeTransferExecutionResult {
    repository_session_transfer_execute_inner(session_id, generation, token, None, true)
}

#[must_use]
pub fn repository_session_transfer_execute_with_credentials(
    session_id: u64,
    generation: u64,
    token: u64,
    username: Option<String>,
    password: Option<String>,
    credential_token: Option<String>,
) -> NativeTransferExecutionResult {
    repository_session_transfer_execute_inner(
        session_id,
        generation,
        token,
        Some((username, password, credential_token)),
        false,
    )
}

pub(crate) fn repository_session_transfer_execute_inner(
    session_id: u64,
    generation: u64,
    token: u64,
    credentials: Option<(Option<String>, Option<String>, Option<String>)>,
    background: bool,
) -> NativeTransferExecutionResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => {
                return NativeTransferExecutionResult {
                    state: NativeTransferExecutionState::Stale,
                    failure: Some(NativeTransferFailure {
                        kind: NativeTransferFailureKind::Stale,
                    }),
                    diagnosis: None,
                    stash: None,
                    activity_id: None,
                    ahead: 0,
                    behind: 0,
                }
            }
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    crate::transfer::execute(
        session_id,
        generation,
        token,
        &repository,
        &activity,
        credentials,
        background,
    )
}

#[must_use]
pub fn repository_session_transfer_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::transfer::cancel(session_id, token),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_transfer_probe_host_key(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeHostKeyResult {
    let activity = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(_) => {
                return NativeHostKeyResult {
                    challenge: None,
                    failure: Some(NativeCloneFailure {
                        kind: NativeCloneFailureKind::InvalidAttemptState,
                    }),
                }
            }
        };
        session.activity.clone()
    };
    crate::transfer::probe_transfer_host_key(session_id, token, &activity)
}

#[must_use]
pub fn repository_session_transfer_resolve_host_key(
    session_id: u64,
    generation: u64,
    token: u64,
    challenge_id: u64,
    accept: bool,
) -> NativeCloneCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return NativeCloneCommandResult {
            accepted: false,
            failure: Some(NativeCloneFailure {
                kind: NativeCloneFailureKind::InvalidAttemptState,
            }),
        };
    }
    crate::transfer::resolve_transfer_host_key(session_id, token, challenge_id, accept)
}

/// Deletes remote-tracking refs a fetch could not update; see
/// [`crate::transfer::delete_tracking_refs`].
#[must_use]
pub fn repository_session_delete_tracking_refs(
    session_id: u64,
    generation: u64,
    references: Vec<String>,
) -> NativeTransferExecutionResult {
    let (repository, activity) = {
        let sessions = lock_sessions();
        match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => (Arc::clone(&session.repository), session.activity.clone()),
            Err(_) => {
                return NativeTransferExecutionResult {
                    state: NativeTransferExecutionState::Stale,
                    failure: Some(NativeTransferFailure {
                        kind: NativeTransferFailureKind::Stale,
                    }),
                    diagnosis: None,
                    stash: None,
                    activity_id: None,
                    ahead: 0,
                    behind: 0,
                };
            }
        }
    };
    crate::transfer::delete_tracking_refs(&repository, &activity, &references)
}
