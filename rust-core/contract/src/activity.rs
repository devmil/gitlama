//! The bridge types of `activity`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeActivityStatus {
    Running,
    Succeeded,
    Failed,
    Canceled,
    TimedOut,
    LaunchError,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeActivityProgress {
    pub phase: String,
    pub completed: u64,
    pub total: Option<u64>,
    pub unit: String,
}

/// User-selectable command data. This is product content and must never be diagnostic-logged.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeActivityRecord {
    pub id: u64,
    pub executable: String,
    pub arguments: Vec<String>,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub status: NativeActivityStatus,
    pub exit_code: Option<i32>,
    pub stdout: Vec<u8>,
    pub stdout_total_bytes: u64,
    pub stdout_truncated: bool,
    pub stderr: Vec<u8>,
    pub stderr_total_bytes: u64,
    pub stderr_truncated: bool,
    pub progress: Option<NativeActivityProgress>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeActivityPage {
    pub records: Vec<NativeActivityRecord>,
    pub evicted_through_id: Option<u64>,
}
