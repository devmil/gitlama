//! Repository session identities, states and failures.

use crate::backend::CallError;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{
    NativeRepositoryFailure, NativeRepositoryFailureKind, NativeRepositoryPhase,
    NativeRepositorySnapshot, NativeRepositoryStatus,
};
use std::rc::Rc;

/// Which backend owns a repository session.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackendKind {
    Local,
    Remote,
}

/// A session as the workspace addresses it. Remote sessions use identifiers
/// the router allocates, never the helper's own numbers.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SessionIdentity {
    pub native_id: u64,
    pub generation: u64,
    pub backend: BackendKind,
}

/// A repository failure: the native kinds and the remote workspace ones.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum FailureCode {
    Canceled,
    MissingObject,
    TooLarge,
    InvalidOutput,
    MissingGit,
    Unsupported,
    InvalidOptions,
    Discovery,
    Read,
    Watch,
    Closed,
    Capacity,
    InvalidGeneration,
    UnknownSession,
    StaleGeneration,
    RetiredSession,
    ExistingRepository,
    DestinationNotEmpty,
    DestinationNotDirectory,
    InitializationFailed,
    TimedOut,
    PathNotFound,
    PermissionDenied,
    NotRepository,
    /// A remote workspace whose connection is not established.
    RemoteDisconnected,
    /// A remote workspace whose identity no longer matches.
    RemoteIdentityChanged,
    /// A remote write whose outcome is unknown.
    RemoteOutcomeUnknown,
    /// The host does not offer this command.
    RemoteNotOffered,
    /// The host offers this change only when changes are allowed for it.
    RemoteWriteNotPermitted,
}

impl FailureCode {
    /// The stable name the UI localizes and diagnostics record.
    pub fn name(self) -> &'static str {
        match self {
            Self::Canceled => "canceled",
            Self::MissingObject => "missingObject",
            Self::TooLarge => "tooLarge",
            Self::InvalidOutput => "invalidOutput",
            Self::MissingGit => "missingGit",
            Self::Unsupported => "unsupported",
            Self::InvalidOptions => "invalidOptions",
            Self::Discovery => "discovery",
            Self::Read => "read",
            Self::Watch => "watch",
            Self::Closed => "closed",
            Self::Capacity => "capacity",
            Self::InvalidGeneration => "invalidGeneration",
            Self::UnknownSession => "unknownSession",
            Self::StaleGeneration => "staleGeneration",
            Self::RetiredSession => "retiredSession",
            Self::ExistingRepository => "existingRepository",
            Self::DestinationNotEmpty => "destinationNotEmpty",
            Self::DestinationNotDirectory => "destinationNotDirectory",
            Self::InitializationFailed => "initializationFailed",
            Self::TimedOut => "timedOut",
            Self::PathNotFound => "pathNotFound",
            Self::PermissionDenied => "permissionDenied",
            Self::NotRepository => "notRepository",
            Self::RemoteDisconnected => "remoteDisconnected",
            Self::RemoteIdentityChanged => "remoteIdentityChanged",
            Self::RemoteOutcomeUnknown => "remoteOutcomeUnknown",
            Self::RemoteNotOffered => "remoteNotOffered",
            Self::RemoteWriteNotPermitted => "remoteWriteNotPermitted",
        }
    }
}

impl From<NativeRepositoryFailureKind> for FailureCode {
    fn from(kind: NativeRepositoryFailureKind) -> Self {
        use NativeRepositoryFailureKind as K;
        match kind {
            K::Canceled => Self::Canceled,
            K::MissingObject => Self::MissingObject,
            K::TooLarge => Self::TooLarge,
            K::InvalidOutput => Self::InvalidOutput,
            K::MissingGit => Self::MissingGit,
            K::Unsupported => Self::Unsupported,
            K::InvalidOptions => Self::InvalidOptions,
            K::Discovery => Self::Discovery,
            K::Read => Self::Read,
            K::Watch => Self::Watch,
            K::Closed => Self::Closed,
            K::Capacity => Self::Capacity,
            K::InvalidGeneration => Self::InvalidGeneration,
            K::UnknownSession => Self::UnknownSession,
            K::StaleGeneration => Self::StaleGeneration,
            K::RetiredSession => Self::RetiredSession,
            K::ExistingRepository => Self::ExistingRepository,
            K::DestinationNotEmpty => Self::DestinationNotEmpty,
            K::DestinationNotDirectory => Self::DestinationNotDirectory,
            K::InitializationFailed => Self::InitializationFailed,
            K::TimedOut => Self::TimedOut,
            K::PathNotFound => Self::PathNotFound,
            K::PermissionDenied => Self::PermissionDenied,
            K::NotRepository => Self::NotRepository,
        }
    }
}

impl From<&NativeRepositoryFailure> for FailureCode {
    fn from(failure: &NativeRepositoryFailure) -> Self {
        failure.kind.into()
    }
}

/// The error of a session call.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SessionError(pub FailureCode);

impl SessionError {
    pub fn code(&self) -> FailureCode {
        self.0
    }

    pub const UNKNOWN_SESSION: SessionError = SessionError(FailureCode::UnknownSession);
    pub const UNKNOWN_PREVIEW: SessionError = SessionError(FailureCode::InvalidOptions);
}

impl From<CallError> for SessionError {
    fn from(error: CallError) -> Self {
        match error {
            CallError::Unsupported(_) => Self(FailureCode::RemoteNotOffered),
            CallError::Transport(_) => Self(FailureCode::RemoteDisconnected),
            CallError::Remote(code) => Self(remote_failure(&code)),
            CallError::Wire(_) => Self(FailureCode::InvalidOutput),
            CallError::UnknownSession => Self(FailureCode::UnknownSession),
        }
    }
}

impl From<FailureCode> for SessionError {
    fn from(code: FailureCode) -> Self {
        Self(code)
    }
}

/// Maps a helper's failure code (a remote error code, or a client code such as
/// `outcomeUnknown`) to the repository failure it means.
fn remote_failure(code: &str) -> FailureCode {
    match code {
        "outcome_unknown" | "outcomeUnknown" => FailureCode::RemoteOutcomeUnknown,
        "identity_changed" | "identityChanged" | "identityMismatch" => {
            FailureCode::RemoteIdentityChanged
        }
        "not_offered" | "notOffered" | "unsupportedCommand" => FailureCode::RemoteNotOffered,
        "write_not_permitted" | "writeNotPermitted" => FailureCode::RemoteWriteNotPermitted,
        "timedOut" => FailureCode::TimedOut,
        "canceled" => FailureCode::Canceled,
        "capacity" | "receiptCapacity" => FailureCode::Capacity,
        "unknownSession" => FailureCode::UnknownSession,
        "invalidRequest" | "operationIdConflict" => FailureCode::InvalidOptions,
        "pathInvalid" | "pathNotFound" | "notDirectory" => FailureCode::PathNotFound,
        "permissionDenied" => FailureCode::PermissionDenied,
        "previewExpired"
        | "preconditionFailed"
        | "admissionEpochRetired"
        | "cursorExpired"
        | "directoryChanged" => FailureCode::StaleGeneration,
        "storeUnavailable" | "internal" => FailureCode::Read,
        _ => FailureCode::RemoteDisconnected,
    }
}

pub type SessionResult<T> = Result<T, SessionError>;

/// Fails with the native failure, when there is one.
pub fn check(failure: &Option<NativeRepositoryFailure>) -> SessionResult<()> {
    match failure {
        Some(failure) => Err(SessionError(failure.into())),
        None => Ok(()),
    }
}

/// The value of a result that must carry one, or `InvalidOutput`.
pub fn required<T>(value: Option<T>) -> SessionResult<T> {
    value.ok_or(SessionError(FailureCode::InvalidOutput))
}

/// One open session and its latest snapshot.
#[derive(Clone, Debug)]
pub struct SessionState {
    pub identity: SessionIdentity,
    pub snapshot: Rc<NativeRepositorySnapshot>,
    pub transport_failure: Option<FailureCode>,
}

impl SessionState {
    pub fn with_snapshot(&self, snapshot: Rc<NativeRepositorySnapshot>) -> Self {
        Self {
            identity: self.identity,
            snapshot,
            transport_failure: None,
        }
    }

    pub fn status(&self) -> Option<&NativeRepositoryStatus> {
        self.snapshot.status.as_ref()
    }

    pub fn head_object_id(&self) -> Option<&str> {
        self.snapshot
            .status
            .as_ref()
            .and_then(|status| status.head_object_id.as_deref())
    }

    pub fn ready(&self) -> bool {
        self.snapshot.phase == NativeRepositoryPhase::Ready
    }
}

/// A session opened by a backend, with its first snapshot.
#[derive(Clone, Debug)]
pub struct OpenedSession {
    pub identity: SessionIdentity,
    pub snapshot: NativeRepositorySnapshot,
}

/// The last path segment of a native path, for tab labels.
pub fn basename(identity: &NativePathIdentity) -> String {
    let text = display_path(identity);
    text.rsplit(['/', '\\'])
        .find(|segment| !segment.is_empty())
        .unwrap_or(&text)
        .to_owned()
}

/// A native path as text for display; invalid encodings are replaced.
/// The identity of a path on this computer, as the platform's file dialogs
/// name it.
pub fn local_path(path: &str) -> NativePathIdentity {
    if cfg!(windows) {
        NativePathIdentity {
            platform: gitlama_contract::dto::NativePathPlatform::Windows,
            units: path.encode_utf16().collect(),
            remote: None,
        }
    } else {
        NativePathIdentity {
            platform: gitlama_contract::dto::NativePathPlatform::Unix,
            units: path.bytes().map(u16::from).collect(),
            remote: None,
        }
    }
}

pub fn display_path(identity: &NativePathIdentity) -> String {
    use gitlama_contract::domain::path_identity::NativePathPlatform;
    match identity.platform {
        NativePathPlatform::Windows => String::from_utf16_lossy(&identity.units),
        NativePathPlatform::Unix => {
            let bytes: Vec<u8> = identity.units.iter().map(|unit| *unit as u8).collect();
            String::from_utf8_lossy(&bytes).into_owned()
        }
    }
}

/// The last path segment of a path string.
pub fn path_label(path: &str) -> String {
    path.split(['/', '\\'])
        .rfind(|segment| !segment.is_empty())
        .unwrap_or(path)
        .to_owned()
}
