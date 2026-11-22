//! GitLama's desktop services.
//!
//! The services are the Rust successors of the Flutter application's Dart
//! services: single-threaded state owners whose async workflows run on the
//! [`rt`] runtime of the GUI thread. They call the native core through
//! [`gitlama_core::api`] on the blocking pool and publish what changed
//! through [`notify::Notifier`]; the Qt layer projects their state.

pub mod app;
pub mod appearance;
pub mod appearances;
pub mod backend;
pub mod commands;
pub mod diagnostics;
pub mod entry;
pub mod history;
pub mod images;
pub mod notices;
pub mod notify;
pub mod prompts;
pub mod rt;
pub mod navigator;
pub mod session;
pub mod sidebar;
pub mod settings;
pub mod view_cache;
pub mod workspace;
