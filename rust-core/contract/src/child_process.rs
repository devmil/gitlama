//! The bridge types of `child_process`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeChildEventKind {
    /// The child runs; `child_id` names it for writes and signals.
    Started,
    /// The executable could not be started.
    StartFailed,
    /// Bytes from standard output.
    Stdout,
    /// Standard output reached its end.
    StdoutClosed,
    /// The child exited; `exit_code` follows `dart:io` (a negative signal number when killed).
    Exited,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeChildEvent {
    pub kind: NativeChildEventKind,
    pub child_id: u64,
    pub bytes: Vec<u8>,
    pub exit_code: Option<i32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeEnvironmentVariable {
    pub name: String,
    pub value: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCapturedProcess {
    pub started: bool,
    pub timed_out: bool,
    pub exit_code: Option<i32>,
    pub stderr: Vec<u8>,
}
