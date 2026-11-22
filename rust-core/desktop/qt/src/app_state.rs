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
        pub command_registry: Value,
        pub(crate) shortcuts: Value,
    }

    impl Default for AppState {
        fn default() -> Self {
            Self {
                commands: None,
                startup: "loading".into(),
                appearance: Value::Null,
                platform: Value::Null,
                command_registry: Value::Null,
                shortcuts: Value::Null,
            }
        }
    }

    impl AppState {
        qproperty!("startup", Member = startup, Notify = startup_changed);
        qproperty!("appearance", Member = appearance, Notify = appearance_changed);
        qproperty!("platform", Member = platform, Notify = platform_changed);
        qproperty!("commands", Member = command_registry, Notify = platform_changed);
        qproperty!("shortcuts", Member = shortcuts, Notify = appearance_changed);

        #[qsignal]
        pub fn startup_changed(&mut self);
        #[qsignal]
        pub fn appearance_changed(&mut self);
        #[qsignal]
        pub fn platform_changed(&mut self);

        /// A workflow asks the window: show dialog `kind` and answer `id`.
        #[qsignal]
        pub fn prompt(&mut self, id: i64, kind: String, payload: String);

        /// A status bar message; an error also opens the failure dialog.
        #[qsignal]
        pub fn notice(&mut self, key: String, args: String, error: bool);

        /// Answers prompt `id` with a JSON value; an empty string cancels.
        #[qslot]
        fn answer_prompt(&self, id: i64, value: String) {
            let answer = if value.is_empty() {
                None
            } else {
                serde_json::from_str::<Value>(&value).ok()
            };
            self.post(move |driver| driver.app.prompts.answer(id as u64, answer));
        }

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
