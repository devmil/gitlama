//! Workflows that rewrite the working tree or history (the Dart
//! HistoryRewriteWorkflowService): stashes and checking out a commit (with
//! stashing when the tree is dirty). Merges, cherry-picks, reverts,
//! integration and rebases follow.

use crate::backend::SessionCalls;
use crate::busy::{BusyActivity, BusyService};
use crate::navigator::Navigator;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::session::{SessionError, SessionIdentity, display_path};
use crate::workspace::{Pane, WorkspaceService};
use gitlama_contract::dto::{
    NativeRefMutationExecutionState, NativeRefMutationKind, NativeRefMutationRequest,
    NativeRefMutationWarning, NativeStatusEntryKind,
};
use gitlama_contract::stash::{
    NativeStashExecutionResult, NativeStashExecutionState, NativeStashFailureKind, NativeStashKind,
    NativeStashPreview, NativeStashRequest,
};
use serde_json::{Value, json};
use std::rc::Rc;

pub fn stash_kind_name(kind: NativeStashKind) -> &'static str {
    match kind {
        NativeStashKind::Push => "push",
        NativeStashKind::Apply => "apply",
        NativeStashKind::Pop => "pop",
        NativeStashKind::Drop => "drop",
        NativeStashKind::Rename => "rename",
        NativeStashKind::AutoStashCheckout => "autoStashCheckout",
        NativeStashKind::StashCheckoutCommit => "stashCheckoutCommit",
        NativeStashKind::AutoStashCheckoutCommit => "autoStashCheckoutCommit",
    }
}

pub fn parse_stash_kind(name: &str) -> Option<NativeStashKind> {
    Some(match name {
        "push" => NativeStashKind::Push,
        "apply" => NativeStashKind::Apply,
        "pop" => NativeStashKind::Pop,
        "drop" => NativeStashKind::Drop,
        "rename" => NativeStashKind::Rename,
        "autoStashCheckout" => NativeStashKind::AutoStashCheckout,
        "stashCheckoutCommit" => NativeStashKind::StashCheckoutCommit,
        "autoStashCheckoutCommit" => NativeStashKind::AutoStashCheckoutCommit,
        _ => return None,
    })
}

fn stash_failure_key(kind: NativeStashFailureKind) -> &'static str {
    match kind {
        NativeStashFailureKind::InvalidRequest => "stashFailureInvalid",
        NativeStashFailureKind::NothingToStash => "stashFailureNothing",
        NativeStashFailureKind::MissingStash => "stashFailureMissing",
        NativeStashFailureKind::Stale => "stashFailureStale",
        NativeStashFailureKind::Conflict => "stashConflictRetained",
        NativeStashFailureKind::Canceled => "stashFailureCanceled",
        NativeStashFailureKind::TimedOut => "stashFailureTimeout",
        NativeStashFailureKind::MissingGit => "stashFailureMissingGit",
        NativeStashFailureKind::Failed
        | NativeStashFailureKind::Read
        | NativeStashFailureKind::Write => "stashFailed",
    }
}

fn preview_payload(preview: &NativeStashPreview) -> Value {
    json!({
        "kind": stash_kind_name(preview.kind),
        "commands": preview.commands.iter().map(|command| format!("git {}", command.arguments.join(" "))).collect::<Vec<_>>(),
        "affectedPaths": preview.affected_paths,
        "includesUntracked": preview.includes_untracked,
        "keepsIndex": preview.keeps_index,
        "selectedObjectId": preview.selected_object_id,
        "targetBranch": preview.target_branch,
        "destructive": preview.destructive,
    })
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

pub struct RewriteService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    busy: Rc<BusyService>,
    navigator: Rc<Navigator>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
}

impl RewriteService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        busy: Rc<BusyService>,
        navigator: Rc<Navigator>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            busy,
            navigator,
            prompts,
            notices,
        })
    }

    fn session(&self) -> Option<(u64, SessionIdentity)> {
        Some((
            self.workspace.active_tab_id()?,
            self.workspace.current()?.identity,
        ))
    }

    fn current(&self, tab: u64, identity: SessionIdentity) -> bool {
        self.session() == Some((tab, identity))
    }

    async fn stash_preview(
        &self,
        identity: SessionIdentity,
        request: NativeStashRequest,
    ) -> Result<NativeStashPreview, Value> {
        match self
            .calls
            .repository_session_stash_preview(identity.native_id, identity.generation, request)
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => Ok(preview),
                (_, Some(failure)) => Err(json!({"key": stash_failure_key(failure.kind)})),
                _ => Err(json!({"key": "stashFailed"})),
            },
            Err(error) => Err(
                json!({"failure": crate::changes::failure_reason_key(SessionError::from(error).code())}),
            ),
        }
    }

    async fn stash_execute(
        &self,
        tab: u64,
        identity: SessionIdentity,
        preview: &NativeStashPreview,
    ) -> Result<NativeStashExecutionResult, SessionError> {
        let calls = Rc::clone(&self.calls);
        let token = preview.token;
        let cancel: Rc<dyn Fn()> = Rc::new(move || {
            let calls = Rc::clone(&calls);
            crate::rt::spawn_detached(async move {
                drop(
                    calls
                        .repository_session_stash_cancel(
                            identity.native_id,
                            identity.generation,
                            token,
                        )
                        .await,
                );
            });
        });
        self.busy
            .run(
                Some(tab),
                BusyActivity::Stash(stash_kind_name(preview.kind)),
                true,
                Some(cancel),
                self.calls.repository_session_stash_execute(
                    identity.native_id,
                    identity.generation,
                    preview.token,
                ),
            )
            .await
            .map_err(SessionError::from)
    }

    fn report_stash(&self, result: &NativeStashExecutionResult) {
        let (key, error) = match result.state {
            NativeStashExecutionState::Completed => ("stashCompleted", false),
            NativeStashExecutionState::ReconciledWithWarning => ("stashReconciledWarning", false),
            NativeStashExecutionState::Stale => ("stashFailureStale", true),
            NativeStashExecutionState::Conflict => (
                if result.stash_retained {
                    "stashConflictRetained"
                } else {
                    "stashConflict"
                },
                false,
            ),
            NativeStashExecutionState::Failed => (
                result
                    .failure
                    .as_ref()
                    .map_or("stashFailed", |failure| stash_failure_key(failure.kind)),
                true,
            ),
            NativeStashExecutionState::OutcomeUncertain => ("mutationOutcomeUncertain", true),
        };
        if error {
            self.notices.error(key, Value::Null);
        } else {
            self.notices.status(key, Value::Null);
        }
    }

    fn report_refused(&self, refusal: Value) {
        match refusal["key"].as_str() {
            Some(key) => self.notices.error(key, Value::Null),
            None => self.notices.status(
                "operationFailureWithReason",
                json!({"operation": {"l10n": "stashFailed"}, "reason": {"l10n": refusal["failure"].as_str().unwrap_or("operationFailureRead")}}),
            ),
        }
    }

    /// Asks for a stash change of `kind`, previews, confirms and runs it.
    pub async fn stash(
        &self,
        kind: NativeStashKind,
        selector: Option<String>,
        object_id: Option<String>,
        target_branch: Option<String>,
    ) {
        let Some(session) = self.workspace.current() else {
            return;
        };
        let snapshot = Rc::clone(&session.snapshot);
        let stash = selector.as_ref().and_then(|selector| {
            snapshot
                .refs
                .stashes
                .iter()
                .find(|stash| &text(&stash.selector) == selector)
        });
        let entries = snapshot
            .status
            .as_ref()
            .map(|status| status.entries.clone())
            .unwrap_or_default();
        let payload = json!({
            "kind": stash_kind_name(kind),
            "selector": selector,
            "objectId": object_id,
            "initialMessage": if kind == NativeStashKind::Rename { stash.map(|stash| text(&stash.subject)) } else { None },
            "initialTargetBranch": target_branch,
            "tracked": entries.iter().filter(|entry| entry.kind != NativeStatusEntryKind::Untracked).map(|entry| display_path(&entry.path)).collect::<Vec<_>>(),
            "untracked": entries.iter().filter(|entry| entry.kind == NativeStatusEntryKind::Untracked).count(),
            "branches": snapshot.refs.branches.iter().map(|branch| text(&branch.name)).collect::<Vec<_>>(),
        });
        let Some(answer) = self.prompts.ask("chooseStash", payload).await else {
            return;
        };
        let Some((tab, identity)) = self.session() else {
            return;
        };
        let request = NativeStashRequest {
            kind,
            message: answer["message"]
                .as_str()
                .filter(|message| !message.is_empty())
                .map(str::to_owned),
            selector: selector.clone(),
            object_id: object_id.clone(),
            paths: answer["paths"]
                .as_array()
                .map(|paths| {
                    paths
                        .iter()
                        .filter_map(|path| path.as_str().map(|path| path.as_bytes().to_vec()))
                        .collect()
                })
                .unwrap_or_default(),
            include_untracked: answer["includeUntracked"].as_bool().unwrap_or(false),
            keep_index: answer["keepIndex"].as_bool().unwrap_or(false),
            target_branch: answer["targetBranch"]
                .as_str()
                .filter(|branch| !branch.is_empty())
                .map(str::to_owned),
        };
        let preview = match self.stash_preview(identity, request).await {
            Ok(preview) => preview,
            Err(refusal) => return self.report_refused(refusal),
        };
        if self
            .prompts
            .ask("confirmStash", preview_payload(&preview))
            .await
            != Some(Value::Bool(true))
            || !self.current(tab, identity)
        {
            return;
        }
        match self.stash_execute(tab, identity, &preview).await {
            Ok(result) => {
                self.report_stash(&result);
                if result.state == NativeStashExecutionState::Conflict {
                    self.navigator.select_pane(Pane::Changes, Some(tab));
                }
            }
            Err(error) => self.report_refused(
                json!({"failure": crate::changes::failure_reason_key(error.code())}),
            ),
        }
    }

    /// Checks out commit `target`; a dirty tree offers stashing first.
    pub async fn checkout_commit(&self, target: Option<String>) {
        let Some(target) = target.filter(|target| {
            (target.len() == 40 || target.len() == 64)
                && target.chars().all(|ch| ch.is_ascii_hexdigit())
        }) else {
            return;
        };
        let Some((tab, identity)) = self.session() else {
            return;
        };
        let Some(status) = self
            .workspace
            .current()
            .and_then(|session| session.snapshot.status.clone())
        else {
            return;
        };
        if self.busy.is_busy(Some(tab))
            || !status.operations.is_empty()
            || status
                .entries
                .iter()
                .any(|entry| entry.kind == NativeStatusEntryKind::Unmerged)
        {
            return;
        }
        let request = NativeRefMutationRequest {
            kind: NativeRefMutationKind::CheckoutCommit,
            name: None,
            second_name: None,
            target: Some(target.clone()),
            message: None,
            url: None,
            force: false,
            reset_mode: None,
            checkout: false,
        };
        let checkout = match self
            .calls
            .repository_session_ref_mutation_preview(
                identity.native_id,
                identity.generation,
                request,
            )
            .await
        {
            Ok(result) => match result.preview {
                Some(preview) if result.failure.is_none() => preview,
                _ => return self.notices.error("refMutationFailed", Value::Null),
            },
            Err(_) => return self.notices.error("refMutationFailed", Value::Null),
        };
        if !self.current(tab, identity) {
            return;
        }
        let dirty = checkout
            .warnings
            .contains(&NativeRefMutationWarning::DirtyCheckout);
        let stash_request = |kind| NativeStashRequest {
            kind,
            message: None,
            selector: None,
            object_id: Some(target.clone()),
            paths: Vec::new(),
            include_untracked: false,
            keep_index: false,
            target_branch: None,
        };
        let (stash, reapply) = if dirty {
            let stash = self
                .stash_preview(
                    identity,
                    stash_request(NativeStashKind::StashCheckoutCommit),
                )
                .await
                .ok();
            let reapply = self
                .stash_preview(
                    identity,
                    stash_request(NativeStashKind::AutoStashCheckoutCommit),
                )
                .await
                .ok();
            (stash, reapply)
        } else {
            (None, None)
        };
        if !self.current(tab, identity) {
            return;
        }
        let choice = self
            .prompts
            .ask(
                "confirmCommitCheckout",
                json!({
                    "target": target,
                    "dirty": dirty,
                    "arguments": checkout.arguments,
                    "stash": stash.as_ref().map(preview_payload),
                    "stashAndReapply": reapply.as_ref().map(preview_payload),
                }),
            )
            .await;
        let Some(choice) = choice.as_ref().and_then(Value::as_str).map(str::to_owned) else {
            return;
        };
        if !self.current(tab, identity) || self.busy.is_busy(Some(tab)) {
            return;
        }
        if choice == "checkout" {
            if dirty {
                return;
            }
            let result = self
                .busy
                .run(
                    Some(tab),
                    BusyActivity::CommitCheckout,
                    true,
                    None,
                    self.calls.repository_session_ref_mutation_execute(
                        identity.native_id,
                        identity.generation,
                        checkout.token,
                    ),
                )
                .await;
            let key = match result.map(|result| result.state) {
                Ok(NativeRefMutationExecutionState::Completed) => "refMutationCompleted",
                Ok(NativeRefMutationExecutionState::ReconciledWithWarning) => {
                    "refMutationWarningResult"
                }
                Ok(NativeRefMutationExecutionState::Stale) => "refMutationStale",
                Ok(NativeRefMutationExecutionState::OutcomeUncertain) => "mutationOutcomeUncertain",
                _ => "refMutationFailed",
            };
            self.notices.status(key, Value::Null);
        } else {
            let preview = if choice == "stash" { stash } else { reapply };
            let Some(preview) = preview else { return };
            match self.stash_execute(tab, identity, &preview).await {
                Ok(result) => {
                    self.report_stash(&result);
                    if result.state == NativeStashExecutionState::Conflict {
                        self.navigator.select_pane(Pane::Changes, Some(tab));
                    }
                }
                Err(error) => self.report_refused(
                    json!({"failure": crate::changes::failure_reason_key(error.code())}),
                ),
            }
        }
    }
}
