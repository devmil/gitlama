//! The repository session's bridge types (defined in `gitlama_contract::dto`) and the
//! product failure categories of their failure kinds.
pub use gitlama_contract::dto::*;

crate::family_failures!(NativeRepositoryFailureKind, "repository", {
    Canceled => Canceled,
    MissingObject => NotFound,
    TooLarge => TooLarge,
    InvalidOutput => Internal,
    MissingGit => Unavailable,
    Unsupported => Unsupported,
    InvalidOptions => InvalidRequest,
    Discovery => NotFound,
    Read => Read,
    Watch => Unavailable,
    Closed => Unavailable,
    Capacity => Busy,
    InvalidGeneration => Stale,
    UnknownSession => Stale,
    StaleGeneration => Stale,
    RetiredSession => Stale,
    ExistingRepository => Precondition,
    DestinationNotEmpty => Precondition,
    DestinationNotDirectory => Precondition,
    InitializationFailed => Write,
    TimedOut => TimedOut,
    PathNotFound => NotFound,
    PermissionDenied => PermissionDenied,
    NotRepository => NotFound,
});

crate::family_failures!(NativeIndexLockFailureKind, "indexLock", {
    Missing => NotFound,
    Changed => Stale,
    UnsafeFile => Precondition,
    Io => Read,
    ActiveOperation => Precondition,
    RepositoryNotReady => Precondition,
    InvalidToken => Stale,
    StaleGeneration => Stale,
    UnknownSession => Stale,
    RetiredSession => Stale,
});

crate::family_failures!(NativeHistoryMetadataFailure, "historyMetadata", {
    Missing => NotFound,
    ObjectTooLarge => TooLarge,
    AuthorTooLarge => TooLarge,
    SubjectTooLarge => TooLarge,
    MalformedCommit => Internal,
});

crate::family_failures!(NativeCommitFailureKind, "commit", {
    Hook => Rejected,
    Signing => Authentication,
    Other => Git,
});

crate::family_failures!(NativeCloneFailureKind, "clone", {
    InvalidSource => InvalidRequest,
    EmbeddedCredential => InvalidRequest,
    InvalidDestination => InvalidRequest,
    DestinationOccupied => Precondition,
    AttemptCapacity => Busy,
    UnknownAttempt => NotFound,
    InvalidAttemptState => InvalidRequest,
    MissingGit => Unavailable,
    Authentication => Authentication,
    CredentialBrokerUnavailable => Unavailable,
    HostKey => Authentication,
    Git => Git,
    TimedOut => TimedOut,
    Canceled => Canceled,
    Discovery => NotFound,
    HostKeyProbeFailed => Authentication,
    HostKeyChallengeExpired => Stale,
    HostKeyWriteFailed => Write,
});
