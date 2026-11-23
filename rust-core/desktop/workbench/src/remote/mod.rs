//! Remote workspaces: repositories on other computers reached over OpenSSH through the
//! GitLama remote helper (docs/remote-workspaces/). The protocol client, the transport, the
//! session calls of a connection and the service that owns host profiles and connections.

pub mod calls;
pub mod channel;
pub mod connector;
pub mod model;
pub mod process;
pub mod protocol;
pub mod reconnect;
pub mod service;
pub mod ssh;

use crate::diagnostics::{self, Field, Level};

/// Records a remote diagnostic event with only static codes and safe fields.
pub(crate) fn note(level: Level, code: &str, fields: &[(&str, Field)]) {
    diagnostics::record(level, "remote", code, fields);
}
