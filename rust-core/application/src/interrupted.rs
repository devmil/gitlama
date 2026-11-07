//! Operations that stop with conflicts and continue, skip or abort from the conflict resolver.
//!
//! Each operation family implements [`InterruptedOperation`] next to the code that starts it
//! and owns its on-disk state; the conflict resolver only finds the interrupted operation and
//! asks its family to resume it. Families that Git's sequencer drives describe the sequencer
//! command and what happens around it; the others resume themselves.
use crate::activity::ActivityStore;
use crate::conflict::{
    NativeConflictContinuationResult, NativeConflictFailureKind, NativeConflictOperationKind,
    NativeConflictSequencerAction,
};
use devmil_git::model::RepositoryMutation;
use devmil_git::{Repository, RepositorySnapshot};
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

/// The repository an interrupted operation is resumed in.
pub(crate) struct Interruption<'a> {
    pub(crate) repository: &'a Repository,
    pub(crate) activity: &'a ActivityStore,
    pub(crate) snapshot: &'a RepositorySnapshot,
    pub(crate) worktree: &'a Path,
    pub(crate) git_dir: &'a Path,
    pub(crate) common_git_dir: &'a Path,
}

/// The Git sequencer command that resumes an operation.
pub(crate) struct SequencerStep {
    pub(crate) arguments: Vec<String>,
    /// Editor and plan files the family prepared when it started; Git's own editor is
    /// replaced by `true` when there are none.
    pub(crate) environment: Vec<(&'static str, PathBuf)>,
    /// Family state the step continues from, removed once the operation ended.
    pub(crate) runtime: Option<PathBuf>,
    /// The step finishes an apply-only revert instead of continuing Git's sequencer.
    pub(crate) apply_only: bool,
}

impl SequencerStep {
    pub(crate) fn new(arguments: Vec<String>) -> Self {
        Self {
            arguments,
            environment: Vec::new(),
            runtime: None,
            apply_only: false,
        }
    }
}

/// One family of operations that can be interrupted by conflicts.
pub(crate) trait InterruptedOperation: Sync {
    /// The operation kind the conflict resolver shows.
    fn kind(&self) -> NativeConflictOperationKind;

    /// Whether the family offers `action` while interrupted.
    fn offers(&self, action: NativeConflictSequencerAction) -> bool {
        let _ = action;
        true
    }

    /// Whether the family left an interruption of its own in `common_git_dir`, for families
    /// Git's status does not report.
    fn active(&self, common_git_dir: &Path) -> bool {
        let _ = common_git_dir;
        false
    }

    /// Resumes the operation. The default runs [`Self::sequencer`] through the conflict
    /// resolver's sequencer driver.
    fn resume(
        &self,
        interruption: &Interruption<'_>,
        action: NativeConflictSequencerAction,
        message: Option<&str>,
    ) -> NativeConflictContinuationResult {
        crate::conflict::resume_sequencer(self, interruption, action, message)
    }

    /// The sequencer command for `action`.
    fn sequencer(
        &self,
        interruption: &Interruption<'_>,
        action: NativeConflictSequencerAction,
    ) -> Result<SequencerStep, NativeConflictFailureKind> {
        let _ = (interruption, action);
        Err(NativeConflictFailureKind::Unsupported)
    }

    /// Checks under the mutation lease, with the index read fresh, right before Git runs.
    fn check_under_lease(
        &self,
        interruption: &Interruption<'_>,
        step: &SequencerStep,
        lease: &RepositoryMutation,
        cancellation: &AtomicBool,
    ) -> Result<(), NativeConflictFailureKind> {
        let _ = (interruption, step, lease, cancellation);
        Ok(())
    }

    /// Finishes what the family kept for an operation that completed.
    fn completed(
        &self,
        interruption: &Interruption<'_>,
        step: &SequencerStep,
        current: &RepositorySnapshot,
    ) {
        let _ = (interruption, step, current);
    }

    /// Drops what the family kept for an operation the user abandoned.
    fn aborted(&self, interruption: &Interruption<'_>, step: &SequencerStep) {
        let _ = (interruption, step);
    }
}

/// Every family, in the order the conflict resolver looks for its own interruptions.
fn families() -> [&'static dyn InterruptedOperation; 6] {
    [
        &crate::history_operation::MERGE,
        &crate::history_operation::CHERRY_PICK,
        &crate::history_operation::REVERT,
        &crate::rebase_operation::REBASE,
        &crate::named_snapshot::SNAPSHOT_RESTORE,
        &crate::stash::STASH_CONFLICT,
    ]
}

/// The family that resumes operations of `kind`; none for conflicts no operation left.
pub(crate) fn family(
    kind: NativeConflictOperationKind,
) -> Option<&'static dyn InterruptedOperation> {
    families().into_iter().find(|family| family.kind() == kind)
}

/// The interruption a family left in `common_git_dir` that Git's status does not report.
pub(crate) fn own_interruption(common_git_dir: &Path) -> Option<NativeConflictOperationKind> {
    families()
        .into_iter()
        .find(|family| family.active(common_git_dir))
        .map(|family| family.kind())
}
