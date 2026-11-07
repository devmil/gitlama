//! The bridge types of `cli_forwarding`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCliStartupState {
    Owner,
    Forwarded,
    Rejected,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCliFailureKind {
    UnsupportedPlatform,
    InvalidArguments,
    NotRunning,
    Authentication,
    VersionSkew,
    InvalidPath,
    NotRepository,
    Busy,
    Precondition,
    Transport,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCliStartupResult {
    pub state: NativeCliStartupState,
    pub failure: Option<NativeCliFailureKind>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCliCommandKind {
    Activate,
    OpenRepository,
    /// Opens `path_units` (POSIX bytes) on the saved host `remote_alias`.
    OpenRemoteRepository,
    Refresh,
    Fetch,
    Pull,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCliPullStrategy {
    FastForwardOnly,
    FastForwardIfPossible,
    Rebase,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCliPathPlatform {
    Unix,
    Windows,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCliCommand {
    pub request_id: u64,
    pub kind: NativeCliCommandKind,
    pub path_platform: Option<NativeCliPathPlatform>,
    pub path_units: Vec<u32>,
    pub pull_strategy: Option<NativeCliPullStrategy>,
    /// The SSH alias of the host an `OpenRemoteRepository` names.
    pub remote_alias: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeCliPollResult {
    pub command: Option<NativeCliCommand>,
    pub failure: Option<NativeCliFailureKind>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeCliResponseKind {
    Accepted,
    Precondition,
    Busy,
    Unsupported,
    Internal,
}
