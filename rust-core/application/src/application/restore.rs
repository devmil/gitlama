//! Restoring one file from a commit, previewed and rechecked before Git runs.
#![allow(clippy::wildcard_imports)]
use crate::application::{session::*, snapshot::*};
use crate::domain::ids::SessionKey;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::*;
use devmil_git::diff::model::DiffPath;
use devmil_git::loading::working_diff::DiffEndpoint;
use devmil_git::types::{HeadState, ObjectId};
use devmil_git::RepositoryErrorKind;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

pub(crate) struct OwnedRestorePreview {
    pub(crate) commit: ObjectId,
    pub(crate) path: DiffPath,
    pub(crate) current_bytes: Option<Vec<u8>>,
    pub(crate) expected_head: Option<String>,
}

/// Previews a byte-exact file restore and retains current-target preconditions.
#[must_use]
pub fn repository_session_restore_preview(
    session_id: u64,
    generation: u64,
    commit: String,
    path: Vec<u8>,
    byte_limit: u32,
) -> NativeRestorePreviewResult {
    if byte_limit == 0 || byte_limit > 8 * 1024 * 1024 {
        return restore_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let commit_id = match ObjectId::parse(commit.clone()) {
        Ok(value) => value,
        Err(_) => return restore_preview_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let path_value = match DiffPath::from_bytes(path.clone()) {
        Ok(value) => value,
        Err(_) => return restore_preview_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return restore_preview_failure(kind),
    };
    let source_ticket = match repository.content(
        DiffEndpoint::Commit(commit_id.clone()),
        path_value.clone(),
        byte_limit as usize,
    ) {
        Ok(value) => value,
        Err(error) => return restore_preview_failure(map_error_kind(error.kind)),
    };
    let current_ticket = match repository.content(
        DiffEndpoint::WorkingTree,
        path_value.clone(),
        byte_limit as usize,
    ) {
        Ok(value) => value,
        Err(error) => return restore_preview_failure(map_error_kind(error.kind)),
    };
    let Some(source) = source_ticket.recv_timeout(Duration::from_secs(30)) else {
        return restore_preview_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let Some(current) = current_ticket.recv_timeout(Duration::from_secs(30)) else {
        return restore_preview_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let source = match source {
        Ok(value) => value,
        Err(error) => return restore_preview_failure(map_error_kind(error.kind)),
    };
    let current = match current {
        Ok(value) => value,
        Err(error) if error.kind == RepositoryErrorKind::MissingObject => Arc::new(None),
        Err(error) => return restore_preview_failure(map_error_kind(error.kind)),
    };
    let Some(source) = source.as_ref() else {
        return restore_preview_failure(NativeRepositoryFailureKind::MissingObject);
    };
    let current_bytes = current.as_ref().as_ref().map(|value| value.bytes.clone());
    let expected_head =
        repository
            .snapshot()
            .repository
            .as_ref()
            .and_then(|value| match &value.head {
                HeadState::Attached { target, .. } | HeadState::Detached { target } => {
                    Some(target.as_str().to_owned())
                }
                HeadState::Unborn { .. } => None,
            });
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return restore_preview_failure(kind),
    };
    let token = session.restore.issue(OwnedRestorePreview {
        commit: commit_id,
        path: path_value,
        current_bytes: current_bytes.clone(),
        expected_head: expected_head.clone(),
    });
    NativeRestorePreviewResult {
        preview: Some(NativeRestorePreview {
            token,
            commit,
            path,
            source_bytes: source.bytes.clone(),
            current_bytes,
            expected_head,
        }),
        failure: None,
    }
}

/// Restores a previewed file only while HEAD and current bytes match the preview.
#[must_use]
pub fn repository_session_restore_file(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRestoreResult {
    let (repository, activity, preview) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return restore_failure(kind),
        };
        let Some(preview) = session.restore.take(token) else {
            return restore_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            preview,
        )
    };
    let actual_head =
        repository
            .snapshot()
            .repository
            .as_ref()
            .and_then(|value| match &value.head {
                HeadState::Attached { target, .. } | HeadState::Detached { target } => {
                    Some(target.as_str().to_owned())
                }
                HeadState::Unborn { .. } => None,
            });
    if actual_head != preview.expected_head {
        return NativeRestoreResult {
            state: NativeRestoreState::Stale,
            failure: Some(NativeRepositoryFailure {
                kind: NativeRepositoryFailureKind::StaleGeneration,
            }),
        };
    }
    let current_ticket = match repository.content(
        DiffEndpoint::WorkingTree,
        preview.path.clone(),
        8 * 1024 * 1024,
    ) {
        Ok(value) => value,
        Err(error) => return restore_failure(map_error_kind(error.kind)),
    };
    let Some(current) = current_ticket.recv_timeout(Duration::from_secs(30)) else {
        return restore_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let current = match current {
        Ok(value) => value,
        Err(error) if error.kind == RepositoryErrorKind::MissingObject => Arc::new(None),
        Err(error) => return restore_failure(map_error_kind(error.kind)),
    };
    if current.as_ref().as_ref().map(|value| &value.bytes) != preview.current_bytes.as_ref() {
        return NativeRestoreResult {
            state: NativeRestoreState::Stale,
            failure: Some(NativeRepositoryFailure {
                kind: NativeRepositoryFailureKind::StaleGeneration,
            }),
        };
    }
    let Some(worktree) = repository
        .snapshot()
        .repository
        .as_ref()
        .map(|value| value.worktree.worktree_root().as_path().to_path_buf())
    else {
        return restore_failure(NativeRepositoryFailureKind::Discovery);
    };
    let Ok(invocation) = devmil_git::commands::restore::restore_worktree_from(
        &preview.commit,
        std::slice::from_ref(&preview.path),
        devmil_git::commands::index::PathspecForm::Arguments,
    ) else {
        return restore_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let command = invocation
        .process_command(repository.git_executable(), &worktree)
        .redact_output();
    let mut publish = |event| sink(event);
    let outcome = crate::operations::coordinate_process_mutation(
        &repository,
        &cancellation,
        command,
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change),
        &mut publish,
    );
    let outcome = MutationOutcome::from_terminal(outcome);
    // Git ran: whatever did not succeed is reported as a read failure.
    restore_result(if outcome.committed {
        outcome
    } else {
        outcome.with_failure(Some(NativeRepositoryFailureKind::Read))
    })
}

/// The bridge result of a file restore: the one place its outcome becomes a state.
pub(crate) fn restore_result(
    outcome: MutationOutcome<NativeRepositoryFailureKind>,
) -> NativeRestoreResult {
    NativeRestoreResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeRestoreState::Restored
            }
            MutationState::ReconciledWithWarning => NativeRestoreState::ReconciledWithWarning,
            MutationState::Stale => NativeRestoreState::Stale,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Canceled
            | MutationState::Failed => NativeRestoreState::Failed,
            MutationState::OutcomeUncertain => NativeRestoreState::OutcomeUncertain,
        },
        failure: outcome.failure.map(|kind| NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn restore_preview_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeRestorePreviewResult {
    NativeRestorePreviewResult {
        preview: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn restore_failure(kind: NativeRepositoryFailureKind) -> NativeRestoreResult {
    NativeRestoreResult {
        state: NativeRestoreState::Failed,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}
