//! The bridge types of `history_operation`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHistoryMutationKind {
    Merge,
    CherryPick,
    Revert,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHistoryMergeMode {
    FastForwardIfPossible,
    FastForwardOnly,
    NoFastForward,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHistoryMutationRequest {
    pub kind: NativeHistoryMutationKind,
    pub targets: Vec<String>,
    pub source_name: Option<Vec<u8>>,
    pub merge_mode: NativeHistoryMergeMode,
    pub acknowledge_published_history: bool,
    pub no_commit: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHistoryMutationFailureKind {
    InvalidRequest,
    DirtyWorktree,
    DetachedHead,
    ActiveOperation,
    PublicationConfirmationRequired,
    Stale,
    Canceled,
    Failed,
    Read,
    MergeCommit,
    /// Local changes collide with an apply-only revert, which never sets them aside.
    LocalChangesOverlap,
}

/// What happens to local changes during a revert.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHistoryLocalChanges {
    /// The worktree is clean.
    None,
    /// Git reverts with the local changes left where they are: none is staged and none
    /// touches a path the reverted commits change.
    InPlace,
    /// The local changes are saved in a stash, the revert runs on a clean worktree and the
    /// changes are reapplied with their staging; conflicts go to the conflict resolver.
    SetAside,
}

/// Local changes a revert set aside and how restoring them went. The stash is kept as a
/// recovery copy in every case.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHistorySetAside {
    pub stash_object_id: String,
    /// The changes and their staging were restored.
    pub restored: bool,
    /// Restoring them stopped with conflicts the conflict resolver shows.
    pub conflicted: bool,
    /// The revert stopped at conflicts first; the changes are reapplied once it is
    /// continued or aborted.
    pub pending: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHistoryMutationFailure {
    pub kind: NativeHistoryMutationFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHistoryMutationPreview {
    pub token: u64,
    pub kind: NativeHistoryMutationKind,
    pub arguments: Vec<String>,
    pub targets: Vec<String>,
    pub source_name: Option<Vec<u8>>,
    pub current_branch: Vec<u8>,
    pub current_head: String,
    pub published_history: bool,
    pub already_contained: bool,
    pub no_commit: bool,
    pub local_changes: NativeHistoryLocalChanges,
    /// Local paths that collide with the reverted commits, raw bytes in status order.
    pub overlapping_paths: Vec<Vec<u8>>,
    /// Some local change is staged, which Git's sequencer refuses to revert over.
    pub staged_changes: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHistoryMutationPreviewResult {
    pub preview: Option<NativeHistoryMutationPreview>,
    pub failure: Option<NativeHistoryMutationFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeHistoryMutationExecutionState {
    Completed,
    AlreadyContained,
    Conflict,
    Interrupted,
    Stale,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the branch; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeHistoryMutationExecutionResult {
    pub state: NativeHistoryMutationExecutionState,
    pub failure: Option<NativeHistoryMutationFailure>,
    pub activity_ids: Vec<String>,
    pub conflicting_paths: Vec<Vec<u8>>,
    pub sequencer: Option<NativeHistoryMutationKind>,
    /// Present when the revert set local changes aside.
    pub set_aside: Option<NativeHistorySetAside>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictPredictionKind {
    Merge,
    Rebase,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictPredictionResult {
    pub kind: NativeConflictPredictionKind,
    pub target: String,
    pub conflicting_paths: Vec<Vec<u8>>,
    pub analyzed_commits: u32,
    pub total_commits: u32,
    pub complete: bool,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeHistoryMutationFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictPredictionStartResult {
    pub token: Option<u64>,
    pub failure: Option<NativeHistoryMutationFailure>,
}
