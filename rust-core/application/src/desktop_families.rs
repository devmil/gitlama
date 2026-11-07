//! The product failure categories of the desktop-only families (hosting and CLI forwarding).
//! Their use cases live in the desktop library, but the failure taxonomy is the application's,
//! so their mappings sit here beside the others.
use gitlama_contract::cli_forwarding::NativeCliFailureKind;
use gitlama_contract::hosting::NativeHostingFailureKind;
use gitlama_contract::hosting_reference::NativeHostingReferenceFailure;
use gitlama_contract::hosting_review::NativeHostingReviewFailure;
use gitlama_contract::hosting_runtime::NativeHostingOAuthFailure;
use gitlama_contract::hosting_runtime::NativeHostingResourceFailure;

crate::family_failures!(NativeHostingFailureKind, "hosting", {
    InvalidConnection => InvalidRequest,
    InvalidRemote => InvalidRequest,
    InvalidLink => InvalidRequest,
    Ambiguous => InvalidRequest,
    CredentialMissing => NotFound,
    CredentialUnreadable => Authentication,
    CredentialExpired => Authentication,
    CredentialStore => Unavailable,
});

crate::family_failures!(NativeHostingReferenceFailure, "hostingReference", {
    InvalidRequest => InvalidRequest,
    StaleRevision => Stale,
    ChangedText => Stale,
    StaleRange => Stale,
});

crate::family_failures!(NativeHostingReviewFailure, "hostingReview", {
    InvalidRequest => InvalidRequest,
    IntegrationDisabled => Precondition,
    CredentialMissing => NotFound,
    CredentialUnreadable => Authentication,
    CredentialExpired => Authentication,
    Unauthorized => Authentication,
    PermissionDenied => PermissionDenied,
    RateLimited => Busy,
    MalformedResponse => Internal,
    Unavailable => Unavailable,
    Canceled => Canceled,
    Unsupported => Unsupported,
    MovedBase => Stale,
    StaleAuthorization => Stale,
    Uncertain => Uncertain,
    DraftStorage => Write,
});

crate::family_failures!(NativeHostingOAuthFailure, "hostingOAuth", {
    InvalidConnection => InvalidRequest,
    Busy => Busy,
    Unavailable => Unavailable,
    Unauthorized => Authentication,
    RateLimited => Busy,
    MalformedResponse => Internal,
    Expired => Stale,
    Denied => Authentication,
    SecureStore => Unavailable,
    NotFound => NotFound,
    Redirected => Rejected,
    ServerError => Rejected,
    Network => Unavailable,
    Certificate => Authentication,
    TimedOut => TimedOut,
});

crate::family_failures!(NativeHostingResourceFailure, "hostingResource", {
    InvalidRequest => InvalidRequest,
    IntegrationDisabled => Precondition,
    CredentialMissing => NotFound,
    CredentialUnreadable => Authentication,
    CredentialExpired => Authentication,
    Unauthorized => Authentication,
    PermissionDenied => PermissionDenied,
    RateLimited => Busy,
    MalformedResponse => Internal,
    Unavailable => Unavailable,
    NotFound => NotFound,
    Redirected => Rejected,
    ServerError => Rejected,
    Network => Unavailable,
    Certificate => Authentication,
    TimedOut => TimedOut,
});

crate::family_failures!(NativeCliFailureKind, "cli", {
    UnsupportedPlatform => Unavailable,
    InvalidArguments => InvalidRequest,
    NotRunning => Unavailable,
    Authentication => Authentication,
    VersionSkew => Stale,
    InvalidPath => InvalidRequest,
    NotRepository => NotFound,
    Busy => Busy,
    Precondition => Precondition,
    Transport => Unavailable,
});
