//! The bridge types of `stash`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeStashKind {
    Push,
    Apply,
    Pop,
    Drop,
    Rename,
    AutoStashCheckout,
    /// Stash all changes, then detach at object_id and retain the stash.
    StashCheckoutCommit,
    /// Stash all changes, detach at object_id, then reapply.
    AutoStashCheckoutCommit,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeStashRequest {
    pub kind: NativeStashKind,
    pub message: Option<String>,
    pub selector: Option<String>,
    pub object_id: Option<String>,
    pub paths: Vec<Vec<u8>>,
    pub include_untracked: bool,
    pub keep_index: bool,
    pub target_branch: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeStashFailureKind {
    InvalidRequest,
    NothingToStash,
    MissingStash,
    Stale,
    Conflict,
    Canceled,
    TimedOut,
    MissingGit,
    Failed,
    Read,
    Write,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeStashFailure {
    pub kind: NativeStashFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeStashCommandPreview {
    pub arguments: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeStashPreview {
    pub token: u64,
    pub kind: NativeStashKind,
    pub commands: Vec<NativeStashCommandPreview>,
    pub affected_paths: u32,
    pub includes_untracked: bool,
    pub keeps_index: bool,
    pub selected_object_id: Option<String>,
    pub target_branch: Option<String>,
    pub destructive: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeStashPreviewResult {
    pub preview: Option<NativeStashPreview>,
    pub failure: Option<NativeStashFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeStashExecutionState {
    Completed,
    Failed,
    Stale,
    Conflict,
    ReconciledWithWarning,
    /// Git may have changed the stash list or the worktree; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeStashExecutionResult {
    pub state: NativeStashExecutionState,
    pub failure: Option<NativeStashFailure>,
    pub activity_ids: Vec<String>,
    pub stash_created: bool,
    pub checkout_completed: bool,
    pub reapply_completed: bool,
    pub stash_retained: bool,
}
