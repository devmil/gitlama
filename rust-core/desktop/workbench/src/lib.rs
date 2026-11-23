//! GitLama's desktop services.
//!
//! The services are single-threaded state owners whose async workflows run on the
//! [`rt`] runtime of the GUI thread. They call the native core through
//! [`gitlama_core::api`] on the blocking pool and publish what changed
//! through [`notify::Notifier`]; the Qt layer projects their state.

// Service hooks and projections carry callback types; workflows take their
// collaborators explicitly.
#![allow(clippy::type_complexity, clippy::too_many_arguments)]

pub mod acceleration;
pub mod app;
pub mod appearance;
pub mod appearances;
pub mod archive;
pub mod auto_fetch;
pub mod avatars;
pub mod backend;
pub mod busy;
pub mod changes;
pub mod cli;
pub mod clone;
pub mod commands;
pub mod commit;
pub mod conflict_draft;
pub mod conflicts;
pub mod diagnostics;
pub mod diff_doc;
pub mod diff_renderer;
pub mod entry;
pub mod entry_store;
pub mod extensions;
pub mod file_actions;
pub mod history;
pub mod history_mutations;
pub mod history_rows;
pub mod hosting;
pub mod hosting_links;
pub mod hosting_review;
pub mod images;
pub mod inspector;
pub mod inspector_actions;
pub mod integrations;
pub mod line_selection;
pub mod locks;
pub mod navigator;
pub mod notices;
pub mod notify;
pub mod operations;
pub mod patches;
pub mod path_tree;
pub mod power_tools;
pub mod preferences;
pub mod prompts;
pub mod rebases;
pub mod refs;
pub mod remote;
pub mod rewrite;
pub mod rt;
pub mod session;
pub mod settings;
pub mod sidebar;
pub mod snapshots;
pub mod tools;
pub mod transfers;
pub mod updates;
pub mod view_cache;
pub mod working_detail;
pub mod workspace;
