//! The bridge types of `conflict`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictOperationKind {
    Merge,
    Rebase,
    CherryPick,
    Revert,
    Snapshot,
    Stash,
    Standalone,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictFileKind {
    Text,
    Binary,
    Huge,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictSideChoice {
    Current,
    Incoming,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictRegionChoice {
    Current,
    Incoming,
    Both,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictSequencerAction {
    Continue,
    Skip,
    Abort,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictFailureKind {
    NoActiveOperation,
    MissingPath,
    InvalidRequest,
    Stale,
    Unresolved,
    TooLarge,
    Binary,
    Unsupported,
    Read,
    Write,
    Git,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictFailure {
    pub kind: NativeConflictFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictSide {
    pub present: bool,
    pub mode: Option<u32>,
    pub content: Option<Vec<u8>>,
    pub byte_count: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictRegion {
    pub index: u32,
    pub current: Vec<u8>,
    pub incoming: Vec<u8>,
    pub ancestor: Option<Vec<u8>>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictFile {
    pub path: Vec<u8>,
    pub kind: NativeConflictFileKind,
    pub ancestor: NativeConflictSide,
    pub current: NativeConflictSide,
    pub incoming: NativeConflictSide,
    pub result: Option<Vec<u8>>,
    pub result_present: bool,
    pub result_mode: Option<u32>,
    pub marker_free: bool,
    pub regions: Vec<NativeConflictRegion>,
    pub fingerprint: u64,
    pub can_undo_resolution: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictSnapshot {
    pub operation: NativeConflictOperationKind,
    pub current_label: Vec<u8>,
    pub incoming_label: Vec<u8>,
    pub current_step: Option<u32>,
    pub total_steps: Option<u32>,
    pub files: Vec<NativeConflictFile>,
    pub resolved_undo_paths: Vec<Vec<u8>>,
    pub can_continue: bool,
    pub can_skip: bool,
    pub suggested_message: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictSnapshotResult {
    pub snapshot: Option<NativeConflictSnapshot>,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeConflictFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeConflictContinuationState {
    Completed,
    Conflict,
    Interrupted,
    Aborted,
    Failed,
    /// Git may have continued or abandoned the operation; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeConflictContinuationResult {
    pub state: NativeConflictContinuationState,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeConflictFailure>,
}
