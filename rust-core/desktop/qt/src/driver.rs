//! The pump: runs QML's commands and the workbench's ready tasks on the GUI
//! thread, then projects what changed onto the QObjects, one borrow at a time.

use crate::app_state::AppState;
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
