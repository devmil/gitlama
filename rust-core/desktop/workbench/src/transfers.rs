//! Fetch, pull and push: the transfer dialog, preview, execution with host-key
//! trust and credentials, failure remedies (retry, without prune, repair
//! tracking refs, fetch), the missing-object refetch offer and the result.
//! A pull follows HEAD so History reveals where it moved.

use crate::backend::SessionCalls;
use crate::diagnostics;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::session::{SessionError, SessionIdentity};
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{NativeRepositorySnapshot, NativeWorkingTreeState};
use gitlama_contract::transfer::{
    NativePullStrategy, NativeTransferExecutionResult, NativeTransferExecutionState,
    NativeTransferFailureKind, NativeTransferKind, NativeTransferPreview, NativeTransferRequest,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

pub fn kind_name(kind: NativeTransferKind) -> &'static str {
    match kind {
        NativeTransferKind::Fetch => "fetch",
        NativeTransferKind::Pull => "pull",
        NativeTransferKind::Push => "push",
        NativeTransferKind::PushTag => "pushTag",
        NativeTransferKind::DeleteTag => "deleteTag",
        NativeTransferKind::DeleteBranch => "deleteBranch",
    }
}

pub fn parse_kind(name: &str) -> Option<NativeTransferKind> {
    Some(match name {
        "fetch" => NativeTransferKind::Fetch,
        "pull" => NativeTransferKind::Pull,
        "push" => NativeTransferKind::Push,
        "pushTag" => NativeTransferKind::PushTag,
        "deleteTag" => NativeTransferKind::DeleteTag,
        "deleteBranch" => NativeTransferKind::DeleteBranch,
        _ => return None,
    })
}

fn strategy_name(strategy: NativePullStrategy) -> &'static str {
    match strategy {
        NativePullStrategy::FastForwardOnly => "fastForwardOnly",
        NativePullStrategy::FastForwardIfPossible => "fastForwardIfPossible",
        NativePullStrategy::Rebase => "rebase",
    }
}

fn parse_strategy(name: &str) -> NativePullStrategy {
    match name {
        "fastForwardIfPossible" => NativePullStrategy::FastForwardIfPossible,
        "rebase" => NativePullStrategy::Rebase,
        _ => NativePullStrategy::FastForwardOnly,
    }
}

pub fn failure_key(kind: NativeTransferFailureKind) -> &'static str {
    match kind {
        NativeTransferFailureKind::InvalidRequest => "transferFailureInvalid",
        NativeTransferFailureKind::DetachedHead => "transferFailureDetached",
        NativeTransferFailureKind::MissingUpstream => "transferFailureUpstream",
        NativeTransferFailureKind::DirtyWorktree => "transferFailureDirty",
        NativeTransferFailureKind::ConflictedWorktree => "transferFailureConflicted",
        NativeTransferFailureKind::Stale => "transferFailureStale",
        NativeTransferFailureKind::Authentication => "transferFailureAuthentication",
        NativeTransferFailureKind::CredentialBrokerUnavailable => "transferFailureCredentialBroker",
        NativeTransferFailureKind::HostKey => "transferFailureHostKey",
        NativeTransferFailureKind::Rejected => "transferFailureRejected",
        NativeTransferFailureKind::TimedOut => "transferFailureTimeout",
        NativeTransferFailureKind::Canceled => "transferFailureCanceled",
        NativeTransferFailureKind::MissingGit => "transferFailureMissingGit",
        NativeTransferFailureKind::Read => "transferFailed",
        NativeTransferFailureKind::MissingObject => "transferFailureMissingObject",
        NativeTransferFailureKind::Locked => "transferFailureLocked",
    }
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// What the transfer dialog starts from.
#[derive(Clone, Debug)]
pub struct Draft {
    pub kind: NativeTransferKind,
    pub initial_force: bool,
    pub initial_remote: Option<String>,
    pub initial_branch: Option<String>,
    pub initial_pull_strategy: NativePullStrategy,
}

impl Draft {
    pub fn new(kind: NativeTransferKind) -> Self {
        Self {
            kind,
            initial_force: false,
            initial_remote: None,
            initial_branch: None,
            initial_pull_strategy: NativePullStrategy::FastForwardOnly,
        }
    }
}

/// The dialog's payload: the draft and the references it offers.
pub fn dialog_payload(draft: &Draft, snapshot: &NativeRepositorySnapshot) -> Value {
    let refs = &snapshot.refs;
    let status = snapshot.status.as_ref();
    let branch_name = status
        .and_then(|status| status.branch_name.as_deref())
        .map(text);
    json!({
        "kind": kind_name(draft.kind),
        "initialForce": draft.initial_force,
        "initialRemote": draft.initial_remote,
        "initialPullStrategy": strategy_name(draft.initial_pull_strategy),
        "branch": draft.initial_branch.clone().or_else(|| branch_name.clone()),
        "currentBranch": branch_name,
        "currentUpstream": status.and_then(|status| status.upstream.as_deref()).map(text),
        "dirty": status.is_some_and(|status| status.working_tree != NativeWorkingTreeState::Clean),
        "remotes": refs.remotes.iter().map(|remote| text(&remote.name)).collect::<Vec<_>>(),
        "remoteBranches": refs.remotes.iter().map(|remote| json!({
            "remote": text(&remote.name),
            "branches": remote.branches.iter().map(|branch| text(&branch.name)).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
        "branches": refs.branches.iter().map(|branch| json!({
            "name": text(&branch.name),
            "hasUpstream": branch.upstream.is_some(),
        })).collect::<Vec<_>>(),
        "tags": refs.tags.iter().map(|tag| text(&tag.name)).collect::<Vec<_>>(),
    })
}

/// The request the dialog answered with.
pub fn parse_request(value: &Value) -> Option<NativeTransferRequest> {
    let text = |key: &str| {
        value[key]
            .as_str()
            .filter(|text| !text.is_empty())
            .map(str::to_owned)
    };
    let flag = |key: &str| value[key].as_bool().unwrap_or(false);
    Some(NativeTransferRequest {
        kind: parse_kind(value["kind"].as_str()?)?,
        remote: text("remote"),
        branch: text("branch"),
        pull_strategy: parse_strategy(value["pullStrategy"].as_str().unwrap_or_default()),
        allow_dirty: flag("allowDirty"),
        stash_before_pull: flag("stashBeforePull"),
        force_with_lease: flag("forceWithLease"),
        set_upstream: flag("setUpstream"),
        refetch: flag("refetch"),
        prune: value["prune"].as_bool().unwrap_or(true),
    })
}

fn fetch_of(remote: Option<String>) -> NativeTransferRequest {
    NativeTransferRequest {
        kind: NativeTransferKind::Fetch,
        remote,
        branch: None,
        pull_strategy: NativePullStrategy::FastForwardOnly,
        allow_dirty: false,
        stash_before_pull: false,
        force_with_lease: false,
        set_upstream: false,
        refetch: false,
        prune: true,
    }
}

/// Whether the failure guide explains `result` (and offers remedies).
fn explained(result: &NativeTransferExecutionResult) -> bool {
    use gitlama_contract::transfer::NativeTransferDiagnosisKind as Diagnosis;
    result
        .stash
        .as_ref()
        .is_some_and(|stash| !stash.reapply_completed)
        || result
            .failure
            .as_ref()
            .is_some_and(|failure| failure.kind == NativeTransferFailureKind::Locked)
        || result.diagnosis.as_ref().is_some_and(|diagnosis| {
            matches!(
                diagnosis.kind,
                Diagnosis::RefCaseCollision | Diagnosis::RemoteAhead
            )
        })
}

fn result_payload(
    result: &NativeTransferExecutionResult,
    request: &NativeTransferRequest,
) -> Value {
    use gitlama_contract::transfer::NativeTransferDiagnosisKind as Diagnosis;
    json!({
        "kind": kind_name(request.kind),
        "remote": request.remote,
        "failure": result.failure.as_ref().map(|failure| failure_key(failure.kind)),
        "diagnosis": result.diagnosis.as_ref().map(|diagnosis| match diagnosis.kind {
            Diagnosis::HostKey => "hostKey",
            Diagnosis::MissingObject => "missingObject",
            Diagnosis::Authentication => "authentication",
            Diagnosis::LockConflict => "lockConflict",
            Diagnosis::RefCaseCollision => "refCaseCollision",
            Diagnosis::RemoteAhead => "remoteAhead",
            Diagnosis::StaleLease => "staleLease",
        }),
        "reference": result.diagnosis.as_ref().and_then(|diagnosis| diagnosis.reference.clone()),
        "related": result.diagnosis.as_ref().map(|diagnosis| diagnosis.related.clone()).unwrap_or_default(),
        "stash": result.stash.as_ref().map(|stash| json!({
            "objectId": stash.object_id,
            "pullCompleted": stash.pull_completed,
            "reapplyCompleted": stash.reapply_completed,
            "conflicted": stash.conflicted,
        })),
        "prune": request.prune,
    })
}

/// A transfer the person started that has ended: the event the Compass's
/// finish answers, so even a transfer that ends before any refresh shows it
/// ran.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TransferFinished {
    /// Grows by one per finished transfer.
    pub sequence: u64,
    pub tab: u64,
    pub succeeded: bool,
}

/// The latest finished transfer, for the driver to announce once.
#[derive(Default)]
pub struct FinishedTransfers {
    latest: Cell<Option<TransferFinished>>,
}

impl FinishedTransfers {
    pub fn record(&self, tab: u64, succeeded: bool) {
        let sequence = self.latest.get().map_or(1, |latest| latest.sequence + 1);
        self.latest.set(Some(TransferFinished {
            sequence,
            tab,
            succeeded,
        }));
    }

    /// The latest finished transfer when it is newer than `seen`.
    pub fn after(&self, seen: u64) -> Option<TransferFinished> {
        self.latest.get().filter(|latest| latest.sequence > seen)
    }
}

pub struct TransferService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    /// Transfers running now: kind and session, for the operation center.
    running: RefCell<Vec<(u64, NativeTransferKind, SessionIdentity)>>,
    /// What the person's transfers changed (NH-2); background fetches never reach it.
    pub sync: Rc<crate::sync::SyncTracker>,
    /// The active tab before the transfer running now.
    baseline: RefCell<Option<crate::sync::SyncBaseline>>,
    /// The person's transfers as they end.
    pub finished: FinishedTransfers,
}

impl TransferService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        sync: Rc<crate::sync::SyncTracker>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            prompts,
            notices,
            notifier,
            running: RefCell::new(Vec::new()),
            sync,
            baseline: RefCell::new(None),
            finished: FinishedTransfers::default(),
        })
    }

    /// The transfer's effect is expected now: the tracker reports it once it shows.
    fn settle(&self) {
        if let Some(baseline) = self.baseline.borrow_mut().take() {
            self.sync.expect(baseline);
        }
    }

    /// The transfers running now.
    pub fn running(&self) -> Vec<(u64, NativeTransferKind, SessionIdentity)> {
        self.running.borrow().clone()
    }

    /// Asks for the transfer, then runs it.
    pub async fn start(&self, draft: Draft) {
        let Some(snapshot) = self
            .workspace
            .current()
            .map(|session| Rc::clone(&session.snapshot))
        else {
            return;
        };
        let Some(answer) = self
            .prompts
            .ask("chooseTransfer", dialog_payload(&draft, &snapshot))
            .await
        else {
            return;
        };
        let Some(request) = parse_request(&answer) else {
            return;
        };
        let tab = self.workspace.active_tab_id();
        let succeeded = Box::pin(self.execute(request, true)).await;
        if let Some(tab) = tab {
            self.finished.record(tab, succeeded);
            self.notifier.notify(Topics::ACTIVITY);
        }
    }

    fn same_session(&self, tab: u64, identity: SessionIdentity) -> bool {
        self.workspace.active_tab_id() == Some(tab)
            && self.workspace.current().map(|session| session.identity) == Some(identity)
    }

    /// Runs `request` in the active tab; true when it succeeded.
    pub async fn execute(&self, request: NativeTransferRequest, notify_result: bool) -> bool {
        *self.baseline.borrow_mut() = self.sync.capture();
        let succeeded = self.execute_captured(request, notify_result).await;
        if succeeded {
            self.settle();
        }
        succeeded
    }

    async fn execute_captured(&self, request: NativeTransferRequest, notify_result: bool) -> bool {
        let (Some(tab), Some(session)) = (self.workspace.active_tab_id(), self.workspace.current())
        else {
            return false;
        };
        let identity = session.identity;
        let preview = match self
            .calls
            .repository_session_transfer_preview(
                identity.native_id,
                identity.generation,
                request.clone(),
            )
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, Some(failure)) => {
                    self.notices.error(failure_key(failure.kind), Value::Null);
                    return false;
                }
                _ => {
                    self.notices.error("transferFailed", Value::Null);
                    return false;
                }
            },
            Err(error) => {
                self.report_session_failure(SessionError::from(error));
                return false;
            }
        };
        diagnostics::info(
            "Transfers",
            "transfer_preview_finished",
            &[("kind", (request.kind as u64).into())],
        );
        let mut result = match self.run(identity, &preview, None).await {
            Ok(result) => result,
            Err(error) => {
                self.report_session_failure(error);
                return false;
            }
        };
        let needs_stash_recovery = |result: &NativeTransferExecutionResult| {
            result
                .stash
                .as_ref()
                .is_some_and(|stash| !stash.reapply_completed)
        };
        let failure = |result: &NativeTransferExecutionResult| {
            result.failure.as_ref().map(|failure| failure.kind)
        };
        // A host transfers with its own keys and credentials, which GitLama never handles
        // from here: the user fixes them on the host.
        if identity.backend == crate::session::BackendKind::Remote && !needs_stash_recovery(&result)
        {
            match failure(&result) {
                Some(NativeTransferFailureKind::HostKey) => {
                    self.notices.error("remoteTransferHostKey", Value::Null);
                    return false;
                }
                Some(NativeTransferFailureKind::Authentication) => {
                    self.notices
                        .error("remoteTransferAuthentication", Value::Null);
                    return false;
                }
                _ => {}
            }
        }
        if !needs_stash_recovery(&result)
            && failure(&result) == Some(NativeTransferFailureKind::HostKey)
        {
            let challenge = match self
                .calls
                .repository_session_transfer_probe_host_key(
                    identity.native_id,
                    identity.generation,
                    preview.token,
                )
                .await
            {
                Ok(result) => result.challenge,
                Err(_) => None,
            };
            let Some(challenge) = challenge else {
                self.notices.error("hostKeyProbeFailed", Value::Null);
                return false;
            };
            let accept = self
                .prompts
                .ask(
                    "trustHostKey",
                    json!({
                        "host": challenge.host,
                        "port": challenge.port,
                        "algorithm": challenge.algorithm,
                        "fingerprint": challenge.fingerprint,
                    }),
                )
                .await
                == Some(Value::Bool(true));
            drop(
                self.calls
                    .repository_session_transfer_resolve_host_key(
                        identity.native_id,
                        identity.generation,
                        preview.token,
                        challenge.challenge_id,
                        accept,
                    )
                    .await,
            );
            if !accept {
                return false;
            }
            result = match self.run(identity, &preview, None).await {
                Ok(result) => result,
                Err(error) => {
                    self.report_session_failure(error);
                    return false;
                }
            };
        }
        if !needs_stash_recovery(&result)
            && failure(&result) == Some(NativeTransferFailureKind::Authentication)
        {
            let Some(answer) = self
                .prompts
                .ask(
                    "gitCredentials",
                    json!({"target": preview.remote, "allowToken": true}),
                )
                .await
            else {
                return false;
            };
            let credentials = (
                answer["username"].as_str().map(str::to_owned),
                answer["secret"].as_str().map(str::to_owned),
                answer["token"].as_bool().unwrap_or(false),
            );
            result = match self.run(identity, &preview, Some(credentials)).await {
                Ok(result) => result,
                Err(error) => {
                    self.report_session_failure(error);
                    return false;
                }
            };
        }
        if needs_stash_recovery(&result) {
            // The pull may already be complete while the saved work waits.
            if result
                .stash
                .as_ref()
                .is_some_and(|stash| stash.pull_completed)
            {
                self.settle();
            }
            if self.same_session(tab, identity) {
                drop(
                    self.prompts
                        .ask("transferFailure", result_payload(&result, &request))
                        .await,
                );
            } else {
                self.report(&request, &result);
            }
            return false;
        }
        if explained(&result) && self.same_session(tab, identity) {
            let remedy = self
                .prompts
                .ask("transferFailure", result_payload(&result, &request))
                .await;
            let Some(remedy) = remedy else { return false };
            if !self.same_session(tab, identity) {
                return false;
            }
            return match remedy["remedy"].as_str().unwrap_or_default() {
                "retry" => Box::pin(self.execute(request, notify_result)).await,
                "retryWithoutPrune" => {
                    Box::pin(self.execute(
                        NativeTransferRequest {
                            prune: false,
                            ..request
                        },
                        notify_result,
                    ))
                    .await
                }
                "fetchRemote" => {
                    Box::pin(self.execute(fetch_of(request.remote.clone()), true)).await
                }
                "repairTrackingRefs" => {
                    let references: Vec<String> = remedy["references"]
                        .as_array()
                        .map(|items| {
                            items
                                .iter()
                                .filter_map(|item| item.as_str().map(str::to_owned))
                                .collect()
                        })
                        .unwrap_or_default();
                    let repaired = self
                        .calls
                        .repository_session_delete_tracking_refs(
                            identity.native_id,
                            identity.generation,
                            references,
                        )
                        .await;
                    match repaired {
                        Ok(repaired)
                            if repaired.state == NativeTransferExecutionState::Completed =>
                        {
                            Box::pin(self.execute(request, notify_result)).await
                        }
                        Ok(repaired) => {
                            self.report(&request, &repaired);
                            false
                        }
                        Err(error) => {
                            self.report_session_failure(SessionError::from(error));
                            false
                        }
                    }
                }
                _ => false,
            };
        }
        if notify_result {
            self.report(&request, &result);
        }
        if failure(&result) == Some(NativeTransferFailureKind::MissingObject)
            && !request.refetch
            && self.same_session(tab, identity)
            && self
                .prompts
                .ask("offerRefetch", json!({"remote": preview.remote}))
                .await
                == Some(Value::Bool(true))
            && self.same_session(tab, identity)
        {
            Box::pin(self.execute(
                NativeTransferRequest {
                    refetch: true,
                    ..fetch_of(Some(preview.remote.clone()))
                },
                true,
            ))
            .await;
        }
        matches!(
            result.state,
            NativeTransferExecutionState::Completed
                | NativeTransferExecutionState::ReconciledWithWarning
        )
    }

    async fn run(
        &self,
        identity: SessionIdentity,
        preview: &NativeTransferPreview,
        credentials: Option<(Option<String>, Option<String>, bool)>,
    ) -> Result<NativeTransferExecutionResult, SessionError> {
        self.running
            .borrow_mut()
            .push((preview.token, preview.kind, identity));
        self.notifier.notify(Topics::OPERATIONS | Topics::ACTIVITY);
        let call = match credentials {
            None => self.calls.repository_session_transfer_execute(
                identity.native_id,
                identity.generation,
                preview.token,
            ),
            Some((username, secret, token)) => self
                .calls
                .repository_session_transfer_execute_with_credentials(
                    identity.native_id,
                    identity.generation,
                    preview.token,
                    username,
                    if token { None } else { secret.clone() },
                    if token { secret } else { None },
                ),
        };
        let result = if preview.kind == NativeTransferKind::Pull {
            self.workspace
                .following_head(identity, call, |result| {
                    matches!(
                        result,
                        Ok(result) if matches!(result.state, NativeTransferExecutionState::Completed | NativeTransferExecutionState::ReconciledWithWarning)
                    )
                })
                .await
        } else {
            call.await
        };
        self.running
            .borrow_mut()
            .retain(|(token, _, _)| *token != preview.token);
        self.notifier.notify(Topics::OPERATIONS | Topics::ACTIVITY);
        diagnostics::info(
            "Transfers",
            "transfer_execute_finished",
            &[
                ("kind", (preview.kind as u64).into()),
                (
                    "state",
                    result
                        .as_ref()
                        .map_or(u64::MAX, |result| result.state as u64)
                        .into(),
                ),
            ],
        );
        result.map_err(SessionError::from)
    }

    /// Fetches `identity`'s remote without prompting or reporting. A fetch
    /// that cannot run (nothing to fetch from, busy, closed) waits for the
    /// next run.
    pub async fn background_fetch(&self, identity: SessionIdentity) {
        let request = NativeTransferRequest {
            kind: NativeTransferKind::Fetch,
            remote: None,
            branch: None,
            pull_strategy: NativePullStrategy::FastForwardOnly,
            allow_dirty: false,
            stash_before_pull: false,
            force_with_lease: false,
            set_upstream: false,
            refetch: false,
            prune: false,
        };
        let fields = [("kind", (NativeTransferKind::Fetch as u64).into())];
        diagnostics::info("Transfers", "background_fetch_preview_started", &fields);
        let preview = match self
            .calls
            .repository_session_transfer_preview(identity.native_id, identity.generation, request)
            .await
        {
            Ok(result) => match result.preview {
                Some(preview) if result.failure.is_none() => preview,
                _ => return,
            },
            Err(_) => return,
        };
        diagnostics::info("Transfers", "background_fetch_execute_started", &fields);
        let result = self
            .calls
            .repository_session_transfer_execute_background(
                identity.native_id,
                identity.generation,
                preview.token,
            )
            .await;
        diagnostics::info(
            "Transfers",
            "background_fetch_execute_finished",
            &[(
                "state",
                result
                    .as_ref()
                    .map_or(u64::MAX, |result| result.state as u64)
                    .into(),
            )],
        );
    }

    /// Cancels the running transfer `token` of `identity`.
    pub async fn cancel(&self, identity: SessionIdentity, token: u64) -> bool {
        self.calls
            .repository_session_transfer_cancel(identity.native_id, identity.generation, token)
            .await
            .is_ok_and(|result| result.accepted)
    }

    fn report_session_failure(&self, error: SessionError) {
        self.notices.error(
            "operationFailureWithReason",
            json!({"operation": {"l10n": "transferFailed"}, "reason": {"l10n": crate::changes::failure_reason_key(error.code())}}),
        );
    }

    fn report(&self, request: &NativeTransferRequest, result: &NativeTransferExecutionResult) {
        let error = matches!(
            result.state,
            NativeTransferExecutionState::Failed | NativeTransferExecutionState::Stale
        ) || result
            .stash
            .as_ref()
            .is_some_and(|stash| !stash.reapply_completed);
        let failure = result
            .failure
            .as_ref()
            .map_or("transferFailed", |failure| failure_key(failure.kind));
        let (key, args) = if request.refetch
            && result.state == NativeTransferExecutionState::Completed
        {
            ("transferRefetchCompleted", Value::Null)
        } else if let Some(stash) = &result.stash {
            let key = if !stash.pull_completed {
                if stash.reapply_completed {
                    "transferPullFailedStashRestored"
                } else {
                    "transferPullFailedStashSaved"
                }
            } else if stash.reapply_completed {
                "transferPullStashRestored"
            } else if stash.conflicted {
                "transferPullStashConflict"
            } else {
                "transferPullStashSaved"
            };
            (key, json!({"reason": {"l10n": failure}}))
        } else {
            match result.state {
                NativeTransferExecutionState::Completed => (
                    "transferCompleted",
                    json!({"ahead": result.ahead.to_string(), "behind": result.behind.to_string()}),
                ),
                NativeTransferExecutionState::ReconciledWithWarning => {
                    ("transferReconciledWarning", Value::Null)
                }
                NativeTransferExecutionState::Stale => ("transferFailureStale", Value::Null),
                NativeTransferExecutionState::Failed => (failure, Value::Null),
                NativeTransferExecutionState::OutcomeUncertain => {
                    ("mutationOutcomeUncertain", Value::Null)
                }
            }
        };
        if error {
            self.notices.error(key, args);
        } else {
            self.notices.status(key, args);
        }
    }
}

#[cfg(test)]
mod finished_tests {
    use super::FinishedTransfers;

    #[test]
    fn a_finished_transfer_is_announced_once() {
        let finished = FinishedTransfers::default();
        assert_eq!(finished.after(0), None);
        finished.record(7, true);
        let first = finished.after(0).expect("announced");
        assert_eq!((first.tab, first.succeeded), (7, true));
        assert_eq!(finished.after(first.sequence), None);
        finished.record(7, false);
        let second = finished.after(first.sequence).expect("the next one");
        assert!(second.sequence > first.sequence);
        assert!(!second.succeeded);
    }
}
