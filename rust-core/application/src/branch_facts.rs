//! What an operation re-reads before it commits: HEAD, and whether Git still runs a rebase or
//! another operation in a worktree. Rebase and merge/cherry-pick/revert share them.
use devmil_git::activity::ActivityEvent;
use devmil_git::types::ObjectId;
use std::path::Path;
use std::sync::{Arc, Mutex};

/// Reads HEAD in `worktree` as an activity of the running operation.
pub(crate) fn resolve_head(
    worktree: &Path,
    cancellation: &dyn devmil_git::cancellation::Cancellation,
    sink: &Arc<dyn Fn(ActivityEvent) + Send + Sync>,
    activity_ids: &Mutex<Vec<u64>>,
) -> Option<ObjectId> {
    let publish = |event| sink(event);
    let mut record = |id: devmil_git::activity::ActivityId| {
        activity_ids
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(id.get());
    };
    devmil_git::probes::resolve(
        std::ffi::OsStr::new("git"),
        worktree,
        "HEAD",
        &mut crate::git_probe::ProbeExecutor::publishing(Some(cancellation), &publish, &mut record),
    )
    .ok()
    .flatten()
}

/// Whether `kind` is in progress in `git_dir` (a rebase of either backend). State that
/// devmil-git's checked discovery rejects as unsafe or ambiguous falls back to the lenient
/// test, so a half-written operation is never reported as cleanly finished.
pub(crate) fn operation_in_progress(
    git_dir: &Path,
    kind: devmil_git::status::OperationKind,
) -> bool {
    use devmil_git::status::{discover_operations, discover_operations_checked};
    discover_operations_checked(git_dir)
        .map(|found| found.operations)
        .unwrap_or_else(|_| discover_operations(git_dir))
        .iter()
        .any(|operation| operation.kind == kind)
}

pub(crate) fn rebase_in_progress(git_dir: &Path) -> bool {
    operation_in_progress(git_dir, devmil_git::status::OperationKind::Rebase)
}
