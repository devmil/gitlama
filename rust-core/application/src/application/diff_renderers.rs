//! Configured diff renderers and external diff tools for a session or a detached file.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::diff_renderer::{
    NativeDiffRendererDefinition, NativeDiffRendererFailure, NativeDiffRendererFailureKind,
    NativeDiffRendererPreviewResult, NativeDiffRendererResult, NativeDiffRendererState,
};
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::integrations::{
    NativeIntegrationDefinition, NativeIntegrationExecutionResult, NativeIntegrationPreviewResult,
};
use std::path::PathBuf;

#[must_use]
pub fn repository_session_diff_renderer_preview(
    session_id: u64,
    generation: u64,
    request_id: u64,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(_) => return diff_renderer_preview_failure(),
    };
    let projection = session
        .diff
        .projection
        .as_ref()
        .filter(|value| value.request_id == request_id)
        .or_else(|| {
            session
                .staging
                .projection
                .as_ref()
                .filter(|value| value.request_id == request_id)
                .map(|value| &value.projection)
        });
    let Some(input) = projection
        .and_then(|value| value.renderer_input(crate::diff_renderer::MAX_RENDERER_INPUT_BYTES))
    else {
        return NativeDiffRendererPreviewResult {
            preview: None,
            failure: Some(NativeDiffRendererFailure {
                kind: NativeDiffRendererFailureKind::InputTooLarge,
            }),
        };
    };
    let Some(worktree) = session
        .repository
        .snapshot()
        .repository
        .as_ref()
        .map(|value| value.worktree.worktree_root().as_path().to_path_buf())
    else {
        return diff_renderer_preview_failure();
    };
    crate::diff_renderer::preview(session_id, request_id, worktree, input, definition)
}

#[must_use]
pub fn repository_session_diff_renderer_validate(
    session_id: u64,
    generation: u64,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(_) => return diff_renderer_preview_failure(),
    };
    let Some(worktree) = session
        .repository
        .snapshot()
        .repository
        .as_ref()
        .map(|value| value.worktree.worktree_root().as_path().to_path_buf())
    else {
        return diff_renderer_preview_failure();
    };
    crate::diff_renderer::validate_definition(definition, worktree, session.activity.clone())
}

#[must_use]
pub fn repository_session_diff_renderer_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiffRendererResult {
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(_) => return diff_renderer_failure(NativeDiffRendererFailureKind::Stale),
    };
    let Some(expected_request) = crate::diff_renderer::request_id(session_id, token) else {
        return diff_renderer_failure(NativeDiffRendererFailureKind::Stale);
    };
    let current = session
        .diff
        .projection
        .as_ref()
        .is_some_and(|value| value.request_id == expected_request)
        || session
            .staging
            .projection
            .as_ref()
            .is_some_and(|value| value.request_id == expected_request);
    if !current {
        return diff_renderer_failure(NativeDiffRendererFailureKind::Stale);
    }
    crate::diff_renderer::execute(
        session_id,
        token,
        expected_request,
        session.activity.clone(),
    )
}

#[must_use]
pub fn repository_session_diff_renderer_poll(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiffRendererResult {
    if repository_for_session(session_id, generation).is_err() {
        return diff_renderer_failure(NativeDiffRendererFailureKind::Stale);
    }
    crate::diff_renderer::poll(session_id, token)
}

#[must_use]
pub fn repository_session_diff_renderer_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::diff_renderer::cancel(session_id, token),
        failure: None,
    }
}

/// The diff a renderer would read, for a repository on another computer whose renderer runs on
/// this one. A diff above the renderer's input limit is refused as too large.
#[must_use]
pub fn repository_session_diff_renderer_input(
    session_id: u64,
    generation: u64,
    request_id: u64,
) -> NativeDiffRendererInputResult {
    let failure = |kind| NativeDiffRendererInputResult {
        input: None,
        failure: Some(NativeDiffRendererFailure { kind }),
    };
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(_) => return failure(NativeDiffRendererFailureKind::Stale),
    };
    let projection = session
        .diff
        .projection
        .as_ref()
        .filter(|value| value.request_id == request_id)
        .or_else(|| {
            session
                .staging
                .projection
                .as_ref()
                .filter(|value| value.request_id == request_id)
                .map(|value| &value.projection)
        });
    let Some(projection) = projection else {
        return failure(NativeDiffRendererFailureKind::Stale);
    };
    match projection.renderer_input(crate::diff_renderer::MAX_RENDERER_INPUT_BYTES) {
        Some(input) => NativeDiffRendererInputResult {
            input: Some(input),
            failure: None,
        },
        None => failure(NativeDiffRendererFailureKind::InputTooLarge),
    }
}

/// The directory a renderer for a repository on another computer runs in: there is no local
/// worktree.
pub(crate) fn detached_directory() -> PathBuf {
    std::env::temp_dir()
}

/// Previews a renderer on this computer for a diff read from a repository on another computer.
#[must_use]
pub fn diff_renderer_detached_preview(
    input: Vec<u8>,
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    crate::diff_renderer::preview(
        crate::integrations::DETACHED_OWNER,
        0,
        detached_directory(),
        input,
        definition,
    )
}

#[must_use]
pub fn diff_renderer_detached_validate(
    definition: NativeDiffRendererDefinition,
) -> NativeDiffRendererPreviewResult {
    crate::diff_renderer::validate_definition(
        definition,
        detached_directory(),
        crate::integrations::detached_activity(),
    )
}

#[must_use]
pub fn diff_renderer_detached_execute(token: u64) -> NativeDiffRendererResult {
    crate::diff_renderer::execute(
        crate::integrations::DETACHED_OWNER,
        token,
        0,
        crate::integrations::detached_activity(),
    )
}

#[must_use]
pub fn diff_renderer_detached_poll(token: u64) -> NativeDiffRendererResult {
    crate::diff_renderer::poll(crate::integrations::DETACHED_OWNER, token)
}

#[must_use]
pub fn diff_renderer_detached_cancel(token: u64) -> bool {
    crate::diff_renderer::cancel(crate::integrations::DETACHED_OWNER, token)
}

/// Previews a diff tool on this computer for two versions of a file read from a repository on
/// another computer.
#[must_use]
pub fn external_diff_detached_preview(
    old: Vec<u8>,
    new: Vec<u8>,
    configured: NativeIntegrationDefinition,
) -> NativeIntegrationPreviewResult {
    crate::integrations::preview_diff_bytes(&old, &new, configured)
}

#[must_use]
pub fn external_diff_detached_execute(
    token: u64,
    confirmed: bool,
) -> NativeIntegrationExecutionResult {
    crate::integrations::execute_detached(token, confirmed)
}

#[must_use]
pub fn external_diff_detached_cancel(token: u64) -> bool {
    crate::integrations::cancel(crate::integrations::DETACHED_OWNER, token)
}

pub(crate) const fn diff_renderer_preview_failure() -> NativeDiffRendererPreviewResult {
    NativeDiffRendererPreviewResult {
        preview: None,
        failure: Some(NativeDiffRendererFailure {
            kind: NativeDiffRendererFailureKind::Stale,
        }),
    }
}

pub(crate) const fn diff_renderer_failure(
    kind: NativeDiffRendererFailureKind,
) -> NativeDiffRendererResult {
    NativeDiffRendererResult {
        state: NativeDiffRendererState::Fallback,
        title: None,
        text: None,
        accessibility_text: None,
        activity_ids: Vec::new(),
        failure: Some(NativeDiffRendererFailure { kind }),
    }
}
