#![recursion_limit = "512"]
//! Qt Bridges adapters: the pump that drives the workbench runtime, the
//! window's QObjects and the item models.

mod app_state;
mod driver;
mod json;
mod plumbing;
mod projection;
pub mod row_model;
mod sidebar_state;
mod workspace_state;

pub use app_state::AppState;
pub use driver::{Driver, Pump};
pub use plumbing::{Commands, PumpWaker};
pub use row_model::RowModel;
pub use sidebar_state::{SIDEBAR_ROLES, SidebarState};
pub use workspace_state::WorkspaceState;

/// The command registry as QML reads it.
pub fn command_registry() -> serde_json::Value {
    projection::commands()
}
