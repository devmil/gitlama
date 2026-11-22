//! The pump: runs QML's commands and the workbench's ready tasks on the GUI
//! thread, then projects what changed onto the QObjects, one borrow at a time.

use crate::app_state::AppState;
use crate::projection;
use crate::workspace_state::WorkspaceState;
use crate::json::to_value;
use crate::plumbing::{Commands, PumpWaker};
use gitlama_workbench::app::{App, StartupPhase};
use gitlama_workbench::notify::Topics;
use gitlama_workbench::rt::Runtime;
use qtbridge::qobject;
use serde_json::Value;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

pub struct Driver {
    pub app: Rc<App>,
    pub runtime: Runtime,
    pub commands: Commands,
    pub waker: Arc<PumpWaker>,
    pub state: Rc<RefCell<AppState>>,
    pub workspace: Rc<RefCell<WorkspaceState>>,
}

#[qobject(ConvertToCamelCase)]
mod pump {
    use super::*;

    #[derive(Default)]
    pub struct Pump {
        pub driver: Option<Rc<Driver>>,
    }

    impl Pump {
        #[qslot]
        fn pump(&mut self) {
            if let Some(driver) = self.driver.clone() {
                driver.pump();
            }
        }
    }
}

pub use pump::Pump;

impl Driver {
    pub fn pump(&self) {
        self.waker.begin_pump();
        for command in self.commands.take() {
            command(self);
        }
        self.runtime.run_until_stalled();
        let changed = self.app.notifier().take();
        if !changed.is_empty() {
            self.project(changed);
        }
    }

    fn project(&self, changed: Topics) {
        if changed.intersects(Topics::STARTUP) {
            let phase = match self.app.phase() {
                StartupPhase::Loading => "loading",
                StartupPhase::Failed => "failed",
                StartupPhase::Ready => "ready",
            };
            let mut state = self.state.borrow_mut();
            if state.startup != phase {
                state.startup = phase.to_owned();
                state.startup_changed();
            }
        }
        if changed.intersects(Topics::EVENTS) {
            self.emit_events();
        }
        if changed.intersects(Topics::WORKSPACE | Topics::SESSION | Topics::SETTINGS) {
            self.project_workspace(changed);
        }
        if changed.intersects(Topics::SETTINGS) {
            let appearance = self
                .app
                .services()
                .map(|services| services.settings.with(|document| to_value(&document.appearance)))
                .unwrap_or(Value::Null);
            let mut state = self.state.borrow_mut();
            if state.appearance != appearance {
                state.appearance = appearance;
                state.appearance_changed();
            }
        }
    }
}

impl Driver {
    fn emit_events(&self) {
        for prompt in self.app.prompts.take_fresh() {
            self.state.borrow_mut().prompt(
                prompt.id as i64,
                prompt.kind.to_owned(),
                prompt.payload.to_string(),
            );
        }
        for notice in self.app.notices.take() {
            match notice {
                gitlama_workbench::notices::Notice::Status { key, args, error } => {
                    self.state.borrow_mut().notice(key, args.to_string(), error);
                }
            }
        }
    }

    fn project_workspace(&self, changed: Topics) {
        let Some(services) = self.app.services() else { return };
        if changed.intersects(Topics::SETTINGS) {
            let recents = services
                .settings
                .with(|document| projection::recents(&document.recent_repositories));
            let mut workspace = self.workspace.borrow_mut();
            if workspace.recents != recents {
                workspace.recents = recents;
                workspace.recents_changed();
            }
        }
        if changed.intersects(Topics::WORKSPACE | Topics::SESSION) {
            services.entry.follow_session(services.workspace.current().as_ref());
            let (tabs, active, groups) = services.workspace.with_tabs(|tabs, active, groups| {
                (
                    Value::Array(tabs.iter().map(projection::tab).collect()),
                    active.map_or(-1, |id| id as i64),
                    Value::Array(groups.iter().map(projection::group).collect()),
                )
            });
            let entry = projection::entry(services.entry.current());
            let mut workspace = self.workspace.borrow_mut();
            if workspace.tabs != tabs || workspace.active_tab_id != active || workspace.groups != groups {
                workspace.tabs = tabs;
                workspace.active_tab_id = active;
                workspace.groups = groups;
                workspace.tabs_changed();
            }
            if workspace.entry != entry {
                workspace.entry = entry;
                workspace.entry_changed();
            }
        }
    }
}
