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

        /// A branch, tag or remote change of `kind` (refs.rs kind names);
        /// `options` may carry initialName and initialTarget.
        #[qslot]
        fn reference(&self, kind: String, options: Value) {
            let Some(kind) = gitlama_workbench::refs::parse_kind(&kind) else { return };
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let name = options["initialName"].as_str().map(str::to_owned);
                let target = options["initialTarget"].as_str().map(str::to_owned);
                rt::spawn_detached(async move { refs.mutate(kind, name, target).await });
            });
        }

        /// Renames a branch and changes its upstream.
        #[qslot]
        fn edit_branch(&self, name: String) {
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let name = (!name.is_empty()).then_some(name);
                rt::spawn_detached(async move { refs.edit_branch(name).await });
            });
        }

        /// Checks out branch `name` (`reference` is its full name when known).
        #[qslot]
        fn checkout(&self, name: String, reference: String) {
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let name = (!name.is_empty()).then_some(name);
                let reference = (!reference.is_empty()).then_some(reference);
                rt::spawn_detached(async move { refs.checkout(name, reference).await });
            });
        }

        /// Deletes a branch on its remote.
        #[qslot]
        fn delete_remote_branch(&self, reference: String) {
            self.with_services(move |services| {
                let refs = Rc::clone(&services.refs);
                let reference = (!reference.is_empty()).then_some(reference);
                rt::spawn_detached(async move { refs.delete_remote_branch(reference).await });
            });
        }

        /// A stash change of `kind` (push, apply, pop, drop, rename,
        /// autoStashCheckout); `options` may carry selector, objectId and
        /// targetBranch.
        #[qslot]
        fn stash(&self, kind: String, options: Value) {
            let Some(kind) = gitlama_workbench::rewrite::parse_stash_kind(&kind) else { return };
            self.with_services(move |services| {
                let rewrite = Rc::clone(&services.rewrite);
                let text = |key: &str| options[key].as_str().filter(|text| !text.is_empty()).map(str::to_owned);
                let (selector, object_id, target) = (text("selector"), text("objectId"), text("targetBranch"));
                rt::spawn_detached(async move { rewrite.stash(kind, selector, object_id, target).await });
            });
        }

        /// Checks out commit `target` (detached).
        #[qslot]
        fn checkout_commit(&self, target: String) {
            self.with_services(move |services| {
                let rewrite = Rc::clone(&services.rewrite);
                let target = (!target.is_empty()).then_some(target);
                rt::spawn_detached(async move { rewrite.checkout_commit(target).await });
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
