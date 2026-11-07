//! Application layer: the session registry, every session-scoped use case and the projections
//! the adapters translate. The FRB facade (`crate::api`) and the remote wire adapter
//! (`crate::wire`) call into these modules; nothing here depends on either adapter.
pub mod archive;
pub mod commit;
pub mod conflicts;
pub mod diff;
pub mod diff_renderers;
pub mod diff_syntax;
pub mod discard;
pub mod extensions;
pub mod history;
pub mod history_mutations;
pub mod index_lock;
pub mod inspection;
pub mod integrations;
pub mod operation_center;
pub mod patch;
pub mod paths;
pub mod power_tools;
pub mod rebase;
pub mod refs;
pub mod repository_locks;
pub mod restore;
pub mod session;
pub mod snapshot;
pub mod snapshots;
pub mod staging;
pub mod stash;
pub mod status_acceleration;
pub mod transfer;
