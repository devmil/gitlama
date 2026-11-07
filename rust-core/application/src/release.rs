//! The release this build belongs to, from the canonical `VERSION` file (embedded by
//! `build.rs`), so the desktop library can compare itself with published releases.

/// The marketing version, such as `0.1.0-beta.42`.
pub const RELEASE_VERSION: &str = env!("GITLAMA_RELEASE_VERSION");

/// The positive build number; `build.rs` validated it.
pub const RELEASE_BUILD: &str = env!("GITLAMA_RELEASE_BUILD");
