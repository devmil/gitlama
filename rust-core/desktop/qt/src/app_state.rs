//! The window's application state: startup, appearance and platform.
//!
//! Properties are projections the driver sets after each pump; slots post
//! commands and never publish synchronously.

use crate::plumbing::Commands;
use qtbridge::qobject;
use serde_json::Value;

#[qobject(ConvertToCamelCase)]
mod app_state {
    use super::*;

    pub struct AppState {
        pub commands: Option<Commands>,
        pub(crate) startup: String,
        pub(crate) appearance: Value,
        pub platform: Value,
    }

    impl Default for AppState {
        fn default() -> Self {
            Self {
                commands: None,
                startup: "loading".into(),
                appearance: Value::Null,
                platform: Value::Null,
            }
        }
    }

    impl AppState {
        qproperty!("startup", Member = startup, Notify = startup_changed);
        qproperty!("appearance", Member = appearance, Notify = appearance_changed);
        qproperty!("platform", Member = platform, Notify = platform_changed);

        #[qsignal]
        pub fn startup_changed(&mut self);
        #[qsignal]
        pub fn appearance_changed(&mut self);
        #[qsignal]
        pub fn platform_changed(&mut self);

        /// Starts the application again after a failed start.
        #[qslot]
        fn retry(&self) {
            self.post(|driver| driver.app.start());
        }

        /// Saves pending settings before the window closes.
        #[qslot]
        fn flush_settings(&self) {
            self.post(|driver| {
                if let Some(services) = driver.app.services() {
                    drop(services.settings.flush());
                }
            });
        }
    }

    impl AppState {
        pub(crate) fn post(&self, command: impl FnOnce(&crate::driver::Driver) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(command);
            }
        }
    }
}

pub use app_state::AppState;
