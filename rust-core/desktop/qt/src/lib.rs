#![recursion_limit = "512"]
//! Qt Bridges adapters: the pump that drives the workbench runtime, the
//! window's QObjects and the item models.

mod app_state;
mod driver;
mod json;
mod plumbing;
mod projection;
mod workspace_state;

pub use app_state::AppState;
pub use driver::{Driver, Pump};
pub use plumbing::{Commands, PumpWaker};
pub use workspace_state::WorkspaceState;

/// The command registry as QML reads it.
pub fn command_registry() -> serde_json::Value {
    projection::commands()
}
