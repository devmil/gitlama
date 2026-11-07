//! The remote helper's identity and the session policy it opens sessions with
//! ([`SessionPolicy::HELPER`], defined in the domain).

pub use crate::domain::session_policy::{SessionPolicy, SESSION_CACHE_BYTES};

/// The helper ID both the client library and the helper are built with: the helper's
/// compatibility version as 40 decimal digits. A client connects only to a helper reporting
/// the same ID; builds that keep the version share their hosts' installed helper.
pub const BUILD_ID: &str = env!("GITLAMA_REMOTE_HELPER_ID");

/// The source commit this build was made from, for diagnostics and packaging checks only.
pub const SOURCE_COMMIT: &str = env!("GITLAMA_SOURCE_COMMIT");
