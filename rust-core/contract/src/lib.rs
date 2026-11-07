//! GitLama's bridge contract: the plain data types the FRB facade and the remote wire adapter
//! carry between Dart, the desktop library and the remote helper. It holds types only, with
//! no public functions or methods, so flutter_rust_bridge (which reads this crate as a
//! third-party input) generates Dart classes and no Dart functions from it.
pub mod activity;
pub mod advanced_rebase;
pub mod archive;
pub mod avatar;
pub mod child_process;
pub mod cli_forwarding;
pub mod clone;
pub mod conflict;
pub mod diff;
pub mod diff_renderer;
pub mod domain {
    pub mod path_identity;
}
pub mod dto;
pub mod extensions;
pub mod history_operation;
pub mod hosting;
pub mod hosting_reference;
pub mod hosting_review;
pub mod hosting_runtime;
pub mod hosting_settings;
pub mod image_decoder;
pub mod integrations;
pub mod named_snapshot;
pub mod power_tools;
pub mod rebase_operation;
pub mod recovery;
pub mod remote_pending;
pub mod stash;
pub mod storage;
pub mod transfer;
pub mod view_cache;
