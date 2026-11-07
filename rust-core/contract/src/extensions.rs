//! The bridge types of `extensions`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::domain::path_identity::NativePathIdentity;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeExtensionFailureKind {
    InvalidRequest,
    Unavailable,
    Dirty,
    Locked,
    CurrentWorktree,
    Stale,
    Canceled,
    TooLarge,
    Read,
    Git,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeExtensionFailure {
    pub kind: NativeExtensionFailureKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSubmoduleState {
    AtRecordedCommit,
    DifferentCommit,
    Uninitialized,
    Conflicted,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSubmoduleEntry {
    pub path: Vec<u8>,
    pub commit: String,
    pub state: NativeSubmoduleState,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeWorktreeEntry {
    pub worktree_root: NativePathIdentity,
    pub git_dir: NativePathIdentity,
    pub common_git_dir: NativePathIdentity,
    pub head: Option<String>,
    pub branch: Option<Vec<u8>>,
    pub locked: bool,
    pub prunable: bool,
    pub current: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeLfsPathState {
    Pointer,
    Materialized,
    Missing,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeLfsPointer {
    pub oid_sha256: String,
    pub size: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeLfsPointerResult {
    pub pointer: Option<NativeLfsPointer>,
    pub failure: Option<NativeExtensionFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeLfsEntry {
    pub path: Vec<u8>,
    pub state: NativeLfsPathState,
    pub pointer: Option<NativeLfsPointer>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeExtensionInventory {
    pub worktrees: Vec<NativeWorktreeEntry>,
    pub submodules: Vec<NativeSubmoduleEntry>,
    pub lfs_available: bool,
    pub lfs_unavailable_reason: bool,
    pub lfs_entries: Vec<NativeLfsEntry>,
    pub activity_ids: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeExtensionInventoryResult {
    pub inventory: Option<NativeExtensionInventory>,
    pub failure: Option<NativeExtensionFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeExtensionMutationKind {
    SubmoduleInit,
    SubmoduleUpdate,
    LfsTrack,
    LfsUntrack,
    LfsPull,
    WorktreeCreate,
    WorktreeDelete,
    /// Appends `pattern` to the worktree's top-level `.gitignore`.
    IgnoreAdd,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeExtensionMutationRequest {
    pub kind: NativeExtensionMutationKind,
    pub path: Option<Vec<u8>>,
    pub worktree_root: Option<NativePathIdentity>,
    pub pattern: Option<String>,
    pub reference: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeExtensionMutationState {
    Completed,
    Failed,
    Canceled,
    ReconciledWithWarning,
    /// Git may have changed the worktree or submodule; the result cannot be confirmed.
    OutcomeUncertain,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeExtensionMutationResult {
    pub state: NativeExtensionMutationState,
    pub activity_ids: Vec<String>,
    pub failure: Option<NativeExtensionFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSubmoduleEnterResult {
    pub worktree_root: Option<NativePathIdentity>,
    pub failure: Option<NativeExtensionFailure>,
}
