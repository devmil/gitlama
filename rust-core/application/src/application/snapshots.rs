//! Session entry points of named snapshots.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::dto::*;
use crate::named_snapshot::{
    NativeNamedSnapshotExecutionResult, NativeNamedSnapshotExecutionState,
    NativeNamedSnapshotFailure, NativeNamedSnapshotFailureKind, NativeNamedSnapshotListResult,
    NativeNamedSnapshotRestorePreviewResult,
};

#[must_use]
pub fn repository_session_named_snapshots(
    session_id: u64,
    generation: u64,
    offset: u32,
    maximum: u32,
) -> NativeNamedSnapshotListResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeNamedSnapshotListResult {
            entries: Vec::new(),
            total: 0,
            next_offset: None,
            failure: Some(NativeNamedSnapshotFailure {
                kind: NativeNamedSnapshotFailureKind::Stale,
            }),
        };
    };
    crate::named_snapshot::list(&repository, offset, maximum)
}

#[must_use]
pub fn repository_session_named_snapshot_create(
    session_id: u64,
    generation: u64,
    name: String,
    include_untracked: bool,
    keep_index: bool,
) -> NativeNamedSnapshotExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return named_snapshot_execution_failure(NativeNamedSnapshotFailureKind::Stale);
    };
    crate::named_snapshot::create(&repository, &activity, name, include_untracked, keep_index)
}

#[must_use]
pub fn repository_session_named_snapshot_restore_preview(
    session_id: u64,
    generation: u64,
    snapshot_id: u64,
) -> NativeNamedSnapshotRestorePreviewResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeNamedSnapshotRestorePreviewResult {
            preview: None,
            failure: Some(NativeNamedSnapshotFailure {
                kind: NativeNamedSnapshotFailureKind::Stale,
            }),
        };
    };
    crate::named_snapshot::preview_restore(session_id, &repository, snapshot_id)
}

#[must_use]
pub fn repository_session_named_snapshot_restore_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeNamedSnapshotExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return named_snapshot_execution_failure(NativeNamedSnapshotFailureKind::Stale);
    };
    crate::named_snapshot::execute_restore(session_id, token, &repository, &activity)
}

#[must_use]
pub fn repository_session_named_snapshot_restore_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::named_snapshot::cancel_restore(session_id, token),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_named_snapshot_branch(
    session_id: u64,
    generation: u64,
    snapshot_id: u64,
    branch: Vec<u8>,
) -> NativeNamedSnapshotExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return named_snapshot_execution_failure(NativeNamedSnapshotFailureKind::Stale);
    };
    crate::named_snapshot::create_branch(&repository, &activity, snapshot_id, branch)
}

#[must_use]
pub fn repository_session_named_snapshot_delete(
    session_id: u64,
    generation: u64,
    snapshot_id: u64,
) -> NativeNamedSnapshotExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return named_snapshot_execution_failure(NativeNamedSnapshotFailureKind::Stale);
    };
    crate::named_snapshot::delete(&repository, &activity, snapshot_id)
}

pub(crate) fn named_snapshot_execution_failure(
    kind: NativeNamedSnapshotFailureKind,
) -> NativeNamedSnapshotExecutionResult {
    NativeNamedSnapshotExecutionResult {
        state: if kind == NativeNamedSnapshotFailureKind::Stale {
            NativeNamedSnapshotExecutionState::Stale
        } else {
            NativeNamedSnapshotExecutionState::Failed
        },
        snapshot: None,
        recovery_ref: None,
        conflicting_paths: Vec::new(),
        activity_ids: Vec::new(),
        failure: Some(NativeNamedSnapshotFailure { kind }),
    }
}
