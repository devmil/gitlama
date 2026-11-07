//! The bridge types of `clone`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::activity::NativeActivityProgress;
use crate::dto::{NativeCloneFailure, NativeHostKeyChallenge, NativeRepositorySession};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCloneState {
    Pending,
    Running,
    Succeeded,
    Failed,
    Canceled,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCloneSnapshot {
    pub attempt_id: u64,
    pub generation: u64,
    pub state: NativeCloneState,
    pub failure: Option<NativeCloneFailure>,
    pub partial_destination: bool,
    pub progress: Option<NativeActivityProgress>,
    pub host_key_challenge: Option<NativeHostKeyChallenge>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCloneCreateResult {
    pub snapshot: Option<NativeCloneSnapshot>,
    pub failure: Option<NativeCloneFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCloneRunResult {
    pub snapshot: Option<NativeCloneSnapshot>,
    pub session: Option<NativeRepositorySession>,
    pub failure: Option<NativeCloneFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCloneSnapshotResult {
    pub snapshot: Option<NativeCloneSnapshot>,
    pub failure: Option<NativeCloneFailure>,
}
