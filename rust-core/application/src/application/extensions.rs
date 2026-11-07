//! Session entry points of worktrees, submodules and Git LFS.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::extensions::{
    NativeExtensionFailure, NativeExtensionFailureKind, NativeExtensionInventoryResult,
    NativeExtensionMutationRequest, NativeExtensionMutationResult, NativeExtensionMutationState,
    NativeLfsPointerResult, NativeSubmoduleEnterResult,
};

#[must_use]
pub fn repository_session_extensions(
    session_id: u64,
    generation: u64,
) -> NativeExtensionInventoryResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeExtensionInventoryResult {
            inventory: None,
            failure: Some(NativeExtensionFailure {
                kind: NativeExtensionFailureKind::Stale,
            }),
        };
    };
    crate::extensions::inventory(&repository)
}

#[must_use]
pub fn repository_session_submodule_enter(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
) -> NativeSubmoduleEnterResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeSubmoduleEnterResult {
            worktree_root: None,
            failure: Some(NativeExtensionFailure {
                kind: NativeExtensionFailureKind::Stale,
            }),
        };
    };
    crate::extensions::enter_submodule(&repository, path)
}

#[must_use]
pub fn repository_session_lfs_pointer(
    session_id: u64,
    generation: u64,
    path: Vec<u8>,
) -> NativeLfsPointerResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeLfsPointerResult {
            pointer: None,
            failure: Some(NativeExtensionFailure {
                kind: NativeExtensionFailureKind::Stale,
            }),
        };
    };
    crate::extensions::lfs_pointer(&repository, path)
}

#[must_use]
pub fn repository_session_extension_execute(
    session_id: u64,
    generation: u64,
    request: NativeExtensionMutationRequest,
) -> NativeExtensionMutationResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return NativeExtensionMutationResult {
            state: NativeExtensionMutationState::Failed,
            activity_ids: Vec::new(),
            failure: Some(NativeExtensionFailure {
                kind: NativeExtensionFailureKind::Stale,
            }),
        };
    };
    crate::extensions::execute(&repository, &activity, request)
}
