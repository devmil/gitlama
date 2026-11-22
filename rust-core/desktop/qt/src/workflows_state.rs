//! Slots that start the repository workflows the commands run (transfers,
//! references, stashes, ...). Each asks its own questions through prompts.

use crate::plumbing::Commands;
use gitlama_workbench::rt;
use gitlama_workbench::transfers::{Draft, parse_kind};
use qtbridge::qobject;
use serde_json::Value;
use std::rc::Rc;

#[qobject(ConvertToCamelCase)]
mod workflows_state {
    use super::*;

    #[derive(Default)]
    pub struct WorkflowsState {
        pub commands: Option<Commands>,
    }

    impl WorkflowsState {
        /// Fetch, pull, push, push or delete a tag, delete a remote branch:
        /// `options` may carry initialRemote, initialBranch, initialForce.
        #[qslot]
        fn transfer(&self, kind: String, options: Value) {
            let Some(kind) = parse_kind(&kind) else { return };
            self.with_services(move |services| {
                let mut draft = Draft::new(kind);
                draft.initial_remote = options["initialRemote"].as_str().map(str::to_owned);
                draft.initial_branch = options["initialBranch"].as_str().map(str::to_owned);
                draft.initial_force = options["initialForce"].as_bool().unwrap_or(false);
                let transfers = Rc::clone(&services.transfers);
                rt::spawn_detached(async move { transfers.start(draft).await });
            });
        }

        fn with_services(&self, action: impl FnOnce(&gitlama_workbench::app::Services) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(move |driver| {
                    if let Some(services) = driver.app.services() {
                        action(&services);
                    }
                });
            }
        }
    }
}

pub use workflows_state::WorkflowsState;
