//! The bridge types of `transfer`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeTransferKind {
    Fetch,
    Pull,
    Push,
    PushTag,
    DeleteTag,
    /// Deletes a branch on the remote, leased on its fetched remote-tracking ref.
    DeleteBranch,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativePullStrategy {
    FastForwardOnly,
    FastForwardIfPossible,
    Rebase,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTransferRequest {
    pub kind: NativeTransferKind,
    pub remote: Option<String>,
    pub branch: Option<String>,
    pub pull_strategy: NativePullStrategy,
    pub allow_dirty: bool,
    /// Save all tracked and untracked changes before pull, then restore the index too.
    pub stash_before_pull: bool,
    pub force_with_lease: bool,
    pub set_upstream: bool,
    pub refetch: bool,
    /// For a fetch: remove remote-tracking refs whose branch the remote deleted.
    pub prune: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeTransferFailureKind {
    InvalidRequest,
    DetachedHead,
    MissingUpstream,
    DirtyWorktree,
    ConflictedWorktree,
    Stale,
    Authentication,
    CredentialBrokerUnavailable,
    HostKey,
    Rejected,
    TimedOut,
    Canceled,
    MissingGit,
    Read,
    MissingObject,
    /// Another Git process held one of the repository's lock files.
    Locked,
}

/// A failure mechanism recognised from Git's diagnostics.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeTransferDiagnosisKind {
    HostKey,
    MissingObject,
    Authentication,
    LockConflict,
    /// Refs differing only in letter case share one file on a case-insensitive file system.
    RefCaseCollision,
    RemoteAhead,
    StaleLease,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTransferDiagnosis {
    pub kind: NativeTransferDiagnosisKind,
    /// The full ref name the failure is about, such as the ref Git could not lock.
    pub reference: Option<String>,
    /// For a case collision: the other spellings of `reference`.
    pub related: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTransferFailure {
    pub kind: NativeTransferFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTransferPreview {
    pub token: u64,
    pub kind: NativeTransferKind,
    pub remote: String,
    pub branch: Option<String>,
    pub arguments: Vec<String>,
    pub ahead: u64,
    pub behind: u64,
    pub dirty: bool,
    pub expected_remote_object_id: Option<String>,
    pub force_with_lease: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTransferPreviewResult {
    pub preview: Option<NativeTransferPreview>,
    pub failure: Option<NativeTransferFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeTransferExecutionState {
    Completed,
    Failed,
    Stale,
    ReconciledWithWarning,
    /// Git may have changed the local or the remote refs; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativePullStashResult {
    /// Immutable recovery identity, also kept in the stash stack for review.
    pub object_id: String,
    pub pull_completed: bool,
    pub reapply_completed: bool,
    pub conflicted: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeTransferExecutionResult {
    pub state: NativeTransferExecutionState,
    pub failure: Option<NativeTransferFailure>,
    /// What Git's diagnostics show about a failure, when a known rule matched.
    pub diagnosis: Option<NativeTransferDiagnosis>,
    pub stash: Option<NativePullStashResult>,
    pub activity_id: Option<u64>,
    pub ahead: u64,
    pub behind: u64,
}
