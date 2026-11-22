//! The commit editor: the active worktree's draft, the commit in flight and
//! its outcome; slots to keep the draft and to commit.

use crate::plumbing::Commands;
use gitlama_contract::dto::{NativeCommitExecutionResult, NativeCommitFailureKind, NativeCommitRequest, NativeCommitSigning};
use gitlama_contract::storage::NativeCommitDraft;
use gitlama_workbench::commit::{Outcome, Retry};
use gitlama_workbench::rt;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::rc::Rc;

fn failure_value(result: &NativeCommitExecutionResult, push: bool) -> Value {
    json!({
        "kind": match result.failure_kind {
            Some(NativeCommitFailureKind::Hook) => "hook",
            Some(NativeCommitFailureKind::Signing) => "signing",
            _ => "other",
        },
        "exitCode": result.exit_code,
        // The command's own output, shown to the person who ran it.
        "output": result.output.iter().take(40).cloned().collect::<Vec<_>>().join("\n"),
        "push": push,
    })
}

#[qobject(ConvertToCamelCase)]
mod commit_state {
    use super::*;

    #[derive(Default)]
    pub struct CommitState {
        pub commands: Option<Commands>,
        /// {tabId, subject, description}: the draft of the active worktree,
        /// published when the tab changes.
        pub(crate) draft: Value,
        /// {busy, failure, outcomeUnknown, succeeded, template, recent}.
        pub(crate) state: Value,
    }

    impl CommitState {
        qproperty!("draft", Member = draft, Notify = draft_changed);
        qproperty!("state", Member = state, Notify = state_changed);

        #[qsignal]
        pub fn draft_changed(&mut self);
        #[qsignal]
        pub fn state_changed(&mut self);
        /// The commit finished; `push` asks the window to push next.
        #[qsignal]
        pub fn committed(&mut self, push: bool);

        /// Keeps the editor's text as the active worktree's draft.
        #[qslot]
        fn update_draft(&self, subject: String, description: String) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(canonical) = services.workspace.active_tab().and_then(|tab| tab.canonical_identity().cloned()) else {
                    return;
                };
                services.commit.update_draft(&canonical, NativeCommitDraft { subject, description });
            });
        }

        /// Commits: `request` is {subject, description, coauthors, author,
        /// amend, skipHooks, signOff}; `retry` is "", "skipHooks" or "unsigned".
        #[qslot]
        fn commit(&self, request: Value, push: bool, retry: String) {
            self.post(move |driver| {
                let Some(services) = driver.app.services() else { return };
                let text = |key: &str| request[key].as_str().unwrap_or_default().to_owned();
                let native = NativeCommitRequest {
                    subject: text("subject"),
                    description: text("description"),
                    coauthors: request["coauthors"]
                        .as_array()
                        .map(|items| items.iter().filter_map(|item| item.as_str().map(str::to_owned)).collect())
                        .unwrap_or_default(),
                    author: request["author"].as_str().filter(|author| !author.trim().is_empty()).map(|author| author.trim().to_owned()),
                    amend: request["amend"].as_bool().unwrap_or(false),
                    skip_hooks: request["skipHooks"].as_bool().unwrap_or(false),
                    signing: NativeCommitSigning::UseGitConfiguration,
                    sign_off: request["signOff"].as_bool().unwrap_or(false),
                };
                let draft = NativeCommitDraft { subject: native.subject.clone(), description: native.description.clone() };
                let retry = match retry.as_str() {
                    "skipHooks" => Some(Retry::SkipHooks),
                    "unsigned" => Some(Retry::Unsigned),
                    _ => None,
                };
                let commit = Rc::clone(&services.commit);
                let changes = Rc::clone(&services.changes);
                let state = Rc::clone(&driver.commit);
                {
                    let mut shown = state.borrow_mut();
                    shown.state["busy"] = json!(true);
                    shown.state["failure"] = Value::Null;
                    shown.state["outcomeUnknown"] = json!(false);
                    shown.state["succeeded"] = json!(false);
                    shown.state_changed();
                }
                rt::spawn_detached(async move {
                    let outcome = commit.commit(native, draft, push, retry).await;
                    let mut shown = state.borrow_mut();
                    shown.state["busy"] = json!(false);
                    match outcome {
                        Outcome::Declined => {}
                        Outcome::Rejected { result, push } => shown.state["failure"] = failure_value(&result, push),
                        Outcome::Finished { result, push_next } => {
                            let committed = matches!(
                                result.state,
                                gitlama_contract::dto::NativeCommitExecutionState::Completed
                                    | gitlama_contract::dto::NativeCommitExecutionState::ReconciledWithWarning
                            );
                            shown.state["succeeded"] = json!(committed);
                            shown.state_changed();
                            shown.committed(push_next);
                            return;
                        }
                        Outcome::OutcomeUnknown => shown.state["outcomeUnknown"] = json!(true),
                        Outcome::Failed(code) => changes.report_failure(code, "commitFailed"),
                    }
                    shown.state_changed();
                });
            });
        }

        /// Loads the recent messages and template of the active session.
        #[qslot]
        fn load_tools(&self) {
            self.post(|driver| {
                let Some(services) = driver.app.services() else { return };
                let Some(session) = services.workspace.current().map(|session| session.identity) else { return };
                let commit = Rc::clone(&services.commit);
                let state = Rc::clone(&driver.commit);
                rt::spawn_detached(async move {
                    let Some(tools) = commit.tools(session).await else { return };
                    let mut shown = state.borrow_mut();
                    shown.state["template"] = json!(tools.template);
                    shown.state["recent"] = Value::Array(
                        tools
                            .recent
                            .iter()
                            .map(|message| json!({"objectId": message.object_id, "subject": message.subject, "description": message.description}))
                            .collect(),
                    );
                    shown.state_changed();
                });
            });
        }

        fn post(&self, command: impl FnOnce(&crate::driver::Driver) + 'static) {
            if let Some(commands) = &self.commands {
                commands.post(command);
            }
        }
    }
}

pub use commit_state::CommitState;
