#![recursion_limit = "512"]
//! Qt Bridges adapters: the pump that drives the workbench runtime, the
//! window's QObjects and the item models.

mod app_state;
mod blame_model;
mod changes_state;
mod commit_state;
mod conflicts_state;
mod diff_model;
mod driver;
mod history_model;
mod history_state;
mod hosting_state;
mod inspector_state;
mod json;
mod line_selection_state;
mod operations_state;
mod patch_state;
mod plumbing;
mod projection;
pub mod row_model;
mod settings_state;
mod sidebar_state;
mod workflows_state;
mod workspace_state;

pub use app_state::AppState;
pub use blame_model::BlameModel;
pub use changes_state::{ChangesState, FILE_ROLES};
pub use commit_state::CommitState;
pub use conflicts_state::{CONFLICT_ROW_ROLES, ConflictsState};
pub use diff_model::DiffModel;
pub use driver::{Driver, Pump};
pub use history_model::HistoryModel;
pub use history_state::HistoryState;
pub use hosting_state::HostingState;
pub use inspector_state::InspectorState;
pub use line_selection_state::{LINE_ROLES, LineSelectionState};
pub use operations_state::OperationsState;
pub use patch_state::PatchState;
pub use plumbing::{Commands, PumpWaker};
pub use row_model::RowModel;
pub use settings_state::SettingsState;
pub use sidebar_state::{SIDEBAR_ROLES, SidebarState};
pub use workflows_state::WorkflowsState;
pub use workspace_state::WorkspaceState;

/// The command registry as QML reads it.
pub fn command_registry() -> serde_json::Value {
    projection::commands()
}
