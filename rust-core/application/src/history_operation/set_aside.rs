//! Local changes a revert set aside while Git's sequencer is stopped at conflicts.
//!
//! The marker names the stash that holds the changes and the worktree whose revert must end
//! first. Continuing or aborting that revert from the conflict resolver reapplies the stash;
//! a marker whose revert ended outside GitLama is forgotten, and its stash stays in Stashes.
use crate::activity::ActivityStore;
use crate::stash_handoff::{Handoff, Reapplied};
use devmil_git::model::RepositoryMutation;
use devmil_git::status::{BranchHead, OperationKind};
use devmil_git::types::ObjectId;
use devmil_git::Repository;
use serde::{Deserialize, Serialize};
use std::path::Path;

const SCHEMA: u32 = 1;
const MARKER_LIMIT: u64 = 16 * 1024;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(crate) struct Pending {
    schema: u32,
    git_dir: Vec<u8>,
    pub(crate) stash: String,
    pub(crate) branch: Vec<u8>,
}

/// One marker per worktree: its Git directory, hashed with 64-bit FNV-1a so the name stays
/// stable across builds.
fn marker_name(git_dir: &Path) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in devmil_git::native_bytes::path_to_bytes(git_dir) {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{hash:016x}.json")
}

fn store(common_git_dir: &Path) -> std::io::Result<crate::private_store::PrivateDir> {
    crate::private_store::PrivateDir::repository(common_git_dir, &["set-aside"])
}

/// Records that `stash` waits for the revert stopped in `git_dir` on `branch`.
pub(crate) fn record(
    common_git_dir: &Path,
    git_dir: &Path,
    stash: &ObjectId,
    branch: &[u8],
) -> std::io::Result<()> {
    let value = Pending {
        schema: SCHEMA,
        git_dir: devmil_git::native_bytes::path_to_bytes(git_dir),
        stash: stash.as_str().to_owned(),
        branch: branch.to_vec(),
    };
    let bytes = serde_json::to_vec(&value).map_err(std::io::Error::other)?;
    // Never replace another worktree's or an unreadable marker.
    store(common_git_dir)?.write_new(&marker_name(git_dir), &bytes)
}

/// The changes waiting for the revert in `git_dir`, if any.
pub(crate) fn pending(common_git_dir: &Path, git_dir: &Path) -> Option<Pending> {
    let bytes = store(common_git_dir)
        .ok()?
        .read(&marker_name(git_dir), MARKER_LIMIT)
        .ok()??;
    let value: Pending = serde_json::from_slice(&bytes).ok()?;
    (value.schema == SCHEMA
        && value.git_dir == devmil_git::native_bytes::path_to_bytes(git_dir)
        && ObjectId::parse(value.stash.clone()).is_ok())
    .then_some(value)
}

fn forget(common_git_dir: &Path, git_dir: &Path) {
    if let Ok(store) = store(common_git_dir) {
        let _ = store.remove(&marker_name(git_dir));
    }
}

/// Forgets a marker whose revert is no longer in progress, for example after the user ran
/// `git revert --abort` in a terminal. The stash itself stays in Stashes.
pub(crate) fn forget_stale(common_git_dir: &Path, git_dir: &Path) {
    if pending(common_git_dir, git_dir).is_some()
        && !crate::branch_facts::operation_in_progress(git_dir, OperationKind::Revert)
    {
        forget(common_git_dir, git_dir);
    }
}

/// Reapplies `stash` under `mutation` on the attached `branch`.
pub(crate) fn restore(
    repository: &Repository,
    activity: &ActivityStore,
    worktree: &Path,
    common_git_dir: &Path,
    stash: &ObjectId,
    branch: &[u8],
    mutation: &RepositoryMutation,
) -> Option<Reapplied> {
    Handoff {
        repository,
        worktree,
        common_git_dir,
        activity,
        intent: crate::activity::OperationIntent::Change,
    }
    .reapply(
        stash,
        mutation,
        |head| matches!(head, BranchHead::Attached(name) if name.as_bytes() == branch),
    )
}

/// Reapplies the changes a revert in `git_dir` set aside, once that revert was continued to
/// its end or aborted. The marker is removed first, so a failed restoration is never
/// retried over newer work; the stash keeps the changes either way.
pub(crate) fn restore_after_revert(
    repository: &Repository,
    activity: &ActivityStore,
    worktree: &Path,
    git_dir: &Path,
    common_git_dir: &Path,
) {
    let Some(pending) = pending(common_git_dir, git_dir) else {
        return;
    };
    forget(common_git_dir, git_dir);
    let Ok(stash) = ObjectId::parse(pending.stash.clone()) else {
        return;
    };
    let cancellation = std::sync::atomic::AtomicBool::new(false);
    let Ok(lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
        return;
    };
    let _ = restore(
        repository,
        activity,
        worktree,
        common_git_dir,
        &stash,
        &pending.branch,
        &lease,
    );
}
