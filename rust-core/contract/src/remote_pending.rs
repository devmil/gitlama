//! The bridge types of `remote_pending`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeRemotePendingOperation {
    /// 32 lowercase hex digits, random per user execution.
    pub operation_id: String,
    pub epoch: String,
    pub digest: String,
    /// A write family of the remote contract, such as `stage` or `rebase`.
    pub family: String,
    pub profile_id: String,
    pub store_id: String,
    pub account_uid: String,
    pub binding: String,
    /// `pending` until a terminal outcome is known, then `terminal`.
    pub state: String,
    /// The helper's outcome once known: `succeeded`, `failed`, `notApplied`,
    /// `desiredStateObserved`, `partial` or `unknown`.
    pub outcome: Option<String>,
    pub result_object_id: Option<String>,
    /// A short user-facing description, such as the commit subject.
    pub summary: String,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeRemotePendingLoadState {
    Absent,
    Loaded,
    /// The file exists but could not be read; it was not replaced.
    Unreadable,
    /// The file exists but is invalid; it was not replaced.
    Corrupt,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRemotePendingLoadResult {
    pub state: NativeRemotePendingLoadState,
    pub operations: Vec<NativeRemotePendingOperation>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeRemotePendingSaveResult {
    pub saved: bool,
}
