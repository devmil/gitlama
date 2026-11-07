//! GitLama's application layer: the domain, the use cases with their session state, the
//! feature modules and the remote wire adapter. The desktop library (`gitlama_core`, the FRB
//! facade) and the headless remote helper both build on it; the bridge types they carry live
//! in `gitlama_contract` and are re-exported here beside the behaviour that produces them.
pub mod activity;
pub mod advanced_rebase;
pub mod application;
/// The shared Git crate, for the remote helper, which runs Git through the same runner.
pub use devmil_git;
pub(crate) mod branch_facts;
pub mod clock;
pub mod clone;
pub mod commit_rules;
pub mod conflict;
pub(crate) mod credentials;
pub mod desktop_families;
pub mod diff;
pub mod diff_renderer;
pub mod diff_syntax;
pub mod domain;
pub mod dto;
pub mod extensions;
pub(crate) mod git_probe;
pub mod graph;
pub mod history_operation;
pub mod hosting_settings;
pub mod image_decoder;
pub mod integrations;
pub(crate) mod interrupted;
#[cfg(test)]
mod loopback_fixture;
pub mod named_snapshot;
pub mod operations;
pub mod power_tools;
pub(crate) mod preview_store;
pub(crate) mod private_store;
#[cfg(test)]
mod product_failures;
pub mod rebase_operation;
pub mod recovery;
pub mod ref_operations;
pub mod release;
pub mod remote_pending;
pub mod remote_session_policy;
pub mod repository_init;
pub(crate) mod ssh_trust;
pub mod stash;
pub(crate) mod stash_handoff;
pub mod storage;
#[cfg(test)]
pub(crate) mod test_support;
pub mod transfer;
pub mod view_cache;
#[cfg(windows)]
mod windows_security;
pub mod wire;
