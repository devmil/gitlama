//! Session entry points of external tools and custom commands.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::dto::*;
use crate::integrations::{
    NativeIntegrationDefinition, NativeIntegrationDiscoveryResult,
    NativeIntegrationExecutionResult, NativeIntegrationExecutionState, NativeIntegrationFailure,
    NativeIntegrationFailureKind, NativeIntegrationKind, NativeIntegrationPreviewResult,
    NativeIntegrationRequest,
};

#[must_use]
pub fn integration_discover(kind: NativeIntegrationKind) -> NativeIntegrationDiscoveryResult {
    crate::integrations::discover(kind)
}

#[must_use]
pub fn repository_session_integration_preview(
    session_id: u64,
    generation: u64,
    request: NativeIntegrationRequest,
) -> NativeIntegrationPreviewResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeIntegrationPreviewResult {
            preview: None,
            failure: Some(NativeIntegrationFailure {
                kind: NativeIntegrationFailureKind::Stale,
            }),
        };
    };
    crate::integrations::preview(session_id, &repository, request)
}

#[must_use]
pub fn repository_session_conflict_external_merge_preview(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return NativeIntegrationPreviewResult {
            preview: None,
            failure: Some(NativeIntegrationFailure {
                kind: NativeIntegrationFailureKind::Stale,
            }),
        };
    };
    crate::integrations::preview_conflict_merge(
        session_id,
        &repository,
        &activity,
        path,
        expected_fingerprint,
        configured,
    )
}

#[must_use]
pub fn repository_session_commit_external_diff_preview(
    session_id: u64,
    generation: u64,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeIntegrationPreviewResult {
            preview: None,
            failure: Some(NativeIntegrationFailure {
                kind: NativeIntegrationFailureKind::Stale,
            }),
        };
    };
    crate::integrations::preview_commit_diff(
        session_id,
        &repository,
        old_revision,
        new_revision,
        old_path,
        new_path,
        configured,
    )
}

#[must_use]
pub fn repository_session_integration_execute(
    session_id: u64,
    generation: u64,
    token: u64,
    confirmed: bool,
) -> NativeIntegrationExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return NativeIntegrationExecutionResult {
            state: NativeIntegrationExecutionState::Failed,
            activity_id: None,
            process_id: None,
            failure: Some(NativeIntegrationFailure {
                kind: NativeIntegrationFailureKind::Stale,
            }),
        };
    };
    crate::integrations::execute(session_id, token, confirmed, &repository, &activity)
}

#[must_use]
pub fn repository_session_integration_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::integrations::cancel(session_id, token),
        failure: None,
    }
}
