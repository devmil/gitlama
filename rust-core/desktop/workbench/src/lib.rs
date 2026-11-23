//! GitLama's desktop services.
//!
//! The services are the Rust successors of the Flutter application's Dart
//! services: single-threaded state owners whose async workflows run on the
//! [`rt`] runtime of the GUI thread. They call the native core through
//! [`gitlama_core::api`] on the blocking pool and publish what changed
//! through [`notify::Notifier`]; the Qt layer projects their state.

pub mod app;
pub mod archive;
pub mod appearance;
pub mod appearances;
pub mod auto_fetch;
pub mod backend;
pub mod busy;
pub mod changes;
pub mod clone;
pub mod commit;
pub mod conflict_draft;
pub mod conflicts;
pub mod commands;
pub mod diagnostics;
pub mod diff_doc;
pub mod entry;
pub mod extensions;
pub mod file_actions;
pub mod history;
pub mod history_mutations;
pub mod history_rows;
pub mod images;
pub mod integrations;
pub mod line_selection;
pub mod inspector;
pub mod inspector_actions;
pub mod notices;
pub mod notify;
pub mod operations;
pub mod patches;
pub mod path_tree;
pub mod preferences;
pub mod prompts;
pub mod rebases;
pub mod refs;
pub mod rewrite;
pub mod rt;
pub mod navigator;
pub mod session;
pub mod sidebar;
pub mod snapshots;
pub mod settings;
pub mod view_cache;
pub mod working_detail;
pub mod transfers;
pub mod workspace;
