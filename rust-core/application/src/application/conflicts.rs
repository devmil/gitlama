//! Session entry points of conflict resolution and sequencer continuation.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::conflict::{
    NativeConflictContinuationResult, NativeConflictContinuationState, NativeConflictFailure,
    NativeConflictFailureKind, NativeConflictRegionChoice, NativeConflictSequencerAction,
    NativeConflictSideChoice, NativeConflictSnapshotResult,
};

#[must_use]
pub fn repository_session_conflicts(
    session_id: u64,
    generation: u64,
) -> NativeConflictSnapshotResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_snapshot_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::inspect(session_id, &repository, &activity)
}

#[must_use]
pub fn repository_session_conflict_save_result(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    result: Vec<u8>,
) -> NativeConflictSnapshotResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_snapshot_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::save_result(
        session_id,
        &repository,
        &activity,
        path,
        expected_fingerprint,
        result,
    )
}

#[must_use]
pub fn repository_session_conflict_choose_side(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    choice: NativeConflictSideChoice,
) -> NativeConflictSnapshotResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_snapshot_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::choose_side(
        session_id,
        &repository,
        &activity,
        path,
        expected_fingerprint,
        choice,
    )
}

#[must_use]
pub fn repository_session_conflict_take_region(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
    expected_fingerprint: u64,
    region_index: u32,
    choice: NativeConflictRegionChoice,
) -> NativeConflictSnapshotResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_snapshot_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::take_region(
        session_id,
        &repository,
        &activity,
        path,
        expected_fingerprint,
        region_index,
        choice,
    )
}

#[must_use]
pub fn repository_session_conflict_undo_resolution(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
) -> NativeConflictSnapshotResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_snapshot_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::undo_resolution(session_id, &repository, &activity, path)
}

#[must_use]
pub fn repository_session_conflict_continue(
    session_id: u64,
    generation: u64,
    action: NativeConflictSequencerAction,
) -> NativeConflictContinuationResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_continuation_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::continue_operation(session_id, &repository, &activity, action)
}

#[must_use]
pub fn repository_session_conflict_continue_with_message(
    session_id: u64,
    generation: u64,
    action: NativeConflictSequencerAction,
    message: String,
) -> NativeConflictContinuationResult {
    let (repository, activity) = match repository_and_activity(session_id, generation) {
        Some(value) => value,
        None => return conflict_continuation_failure(NativeConflictFailureKind::Stale),
    };
    crate::conflict::continue_operation_with_message(
        session_id,
        &repository,
        &activity,
        action,
        Some(&message),
    )
}

pub(crate) fn conflict_snapshot_failure(
    kind: NativeConflictFailureKind,
) -> NativeConflictSnapshotResult {
    NativeConflictSnapshotResult {
        snapshot: None,
        activity_ids: Vec::new(),
        failure: Some(NativeConflictFailure { kind }),
    }
}

pub(crate) fn conflict_continuation_failure(
    kind: NativeConflictFailureKind,
) -> NativeConflictContinuationResult {
    NativeConflictContinuationResult {
        state: NativeConflictContinuationState::Failed,
        activity_ids: Vec::new(),
        failure: Some(NativeConflictFailure { kind }),
    }
}
