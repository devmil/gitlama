//! The bridge types of `named_snapshot`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeNamedSnapshotState {
    Ready,
    Missing,
    Corrupt,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeNamedSnapshotFailureKind {
    InvalidRequest,
    NothingToCapture,
    Missing,
    Corrupt,
    DirtyConflict,
    ActiveOperation,
    Stale,
    Conflict,
    Canceled,
    TooLarge,
    Read,
    Write,
    Git,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeNamedSnapshotFailure {
    pub kind: NativeNamedSnapshotFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeNamedSnapshot {
    pub id: u64,
    pub name: String,
    pub created_at_unix_ms: u64,
    pub base_ref: Option<Vec<u8>>,
    pub base_oid: String,
    pub object_id: String,
    pub staged_count: u32,
    pub unstaged_count: u32,
    pub untracked_count: u32,
    pub includes_untracked: bool,
    pub keeps_index: bool,
    pub state: NativeNamedSnapshotState,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeNamedSnapshotListResult {
    pub entries: Vec<NativeNamedSnapshot>,
    pub total: u32,
    pub next_offset: Option<u32>,
    pub failure: Option<NativeNamedSnapshotFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeNamedSnapshotExecutionState {
    Completed,
    Conflict,
    Stale,
    Canceled,
    Failed,
    ReconciledWithWarning,
    /// Git may have changed the snapshot refs or the worktree; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeNamedSnapshotExecutionResult {
    pub state: NativeNamedSnapshotExecutionState,
    pub snapshot: Option<NativeNamedSnapshot>,
    pub recovery_ref: Option<Vec<u8>>,
    pub conflicting_paths: Vec<Vec<u8>>,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeNamedSnapshotFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeNamedSnapshotRestorePreview {
    pub token: u64,
    pub snapshot: NativeNamedSnapshot,
    pub replacement_paths: Vec<Vec<u8>>,
    pub replacement_paths_truncated: bool,
    pub replaces_index: bool,
    pub replaces_worktree: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeNamedSnapshotRestorePreviewResult {
    pub preview: Option<NativeNamedSnapshotRestorePreview>,
    pub failure: Option<NativeNamedSnapshotFailure>,
}
