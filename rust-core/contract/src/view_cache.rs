//! The bridge types of `view_cache`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeViewCacheFailureKind {
    /// The profile directory cannot be determined.
    Unavailable,
    Io,
    TooLarge,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeViewCacheFailure {
    pub kind: NativeViewCacheFailureKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeViewCacheReadResult {
    /// `None` without a failure means that no entry exists.
    pub bytes: Option<Vec<u8>>,
    pub failure: Option<NativeViewCacheFailure>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeViewCacheCommandResult {
    pub accepted: bool,
    pub failure: Option<NativeViewCacheFailure>,
}
