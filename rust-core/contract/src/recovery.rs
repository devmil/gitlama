//! The bridge types of `recovery`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::storage::NativeSettingsDocument;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativePreviousShutdown {
    Clean,
    Unclean,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeRecoveryFailureKind {
    Io,
    Locked,
    AlreadyRunning,
    NotRunning,
    InvalidCheckpoint,
    UnsafeGitState,
    NotRepository,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRecoveryFailure {
    pub kind: NativeRecoveryFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRecoveryStartResult {
    pub previous_shutdown: Option<NativePreviousShutdown>,
    pub checkpoint: Option<NativeSettingsDocument>,
    pub failure: Option<NativeRecoveryFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRecoveryCommandResult {
    pub completed: bool,
    pub failure: Option<NativeRecoveryFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeRecoveryPathResult {
    pub path: Option<String>,
    pub failure: Option<NativeRecoveryFailure>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeSequencerKind {
    Rebase,
    Merge,
    CherryPick,
    Revert,
    Bisect,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSequencerState {
    pub kind: NativeSequencerKind,
    pub current: Option<u32>,
    pub total: Option<u32>,
    pub index_has_conflicts: bool,
    pub can_continue: bool,
    pub can_abort: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeSequencerInspectionResult {
    pub state: Option<NativeSequencerState>,
    pub failure: Option<NativeRecoveryFailure>,
}
