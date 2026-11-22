#![recursion_limit = "512"]
//! Qt Bridges adapters: the pump that drives the workbench runtime, the
//! window's QObjects and the item models.

mod app_state;
mod driver;
mod json;
mod plumbing;

pub use app_state::AppState;
pub use driver::{Driver, Pump};
pub use plumbing::{Commands, PumpWaker};
