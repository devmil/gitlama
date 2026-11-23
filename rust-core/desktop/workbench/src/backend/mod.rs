//! Repository session backends: where a session's calls run.
//!
//! [`calls::LocalCalls`] runs the in-process native core; the remote backend
//! sends calls over a helper connection. [`BackendRouter`] picks the backend
//! of each session by its location, never by a path string.

// Generated (tooling/remote_wire/generate_calls.py): kept as generated.
#[rustfmt::skip]
pub mod calls;
pub mod lifecycle;

use futures::future::LocalBoxFuture;
use gitlama_application::wire::runtime::{Value, WireError};

pub use calls::{CallRouter, LocalCalls, RemoteCalls, RemoteCustom, RoutedCalls, SessionCalls};

/// Why a call did not reach the core or its answer could not be read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CallError {
    /// The backend does not serve this call (a remote backend and a local-only
    /// command).
    Unsupported(&'static str),
    /// The remote connection failed or closed; the code is a stable name.
    Transport(String),
    /// The helper answered with a remote failure code.
    Remote(String),
    /// The answer did not match the wire contract.
    Wire(WireError),
    /// The session is not known to the backend.
    UnknownSession,
}

impl From<WireError> for CallError {
    fn from(error: WireError) -> Self {
        Self::Wire(error)
    }
}

pub type CallResult<T> = Result<T, CallError>;

/// A remote helper connection's read channel.
pub trait WireTransport {
    /// Sends one read request and returns its JSON result.
    fn invoke_read(
        &self,
        method: &'static str,
        args: Value,
    ) -> LocalBoxFuture<'static, CallResult<Value>>;

    /// The helper's session for an application session identifier.
    fn helper_session(&self, session_id: u64) -> CallResult<u64>;
}
