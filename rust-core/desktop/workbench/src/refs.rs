//! Branches, tags and remotes: the reference
//! dialog, preview → confirm → execute, deleting a tag on remotes first and
//! a branch's upstream after it, recovering a missing target by refreshing,
//! editing a branch (rename and upstream), checking out remote-tracking
//! branches and deleting remote branches.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::prompts::Prompts;
use crate::session::{FailureCode, SessionError, SessionIdentity};
use crate::sidebar::display_reference;
use crate::transfers::{Draft, TransferService};
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::{
    NativeRefMutationExecutionState, NativeRefMutationKind, NativeRefMutationRequest,
    NativeRefMutationWarning, NativeRefResetMode, NativeRepositoryRefs,
};
use gitlama_contract::transfer::{NativePullStrategy, NativeTransferKind, NativeTransferRequest};
use serde_json::{Value, json};
use std::rc::Rc;

pub fn kind_name(kind: NativeRefMutationKind) -> &'static str {
    match kind {
        NativeRefMutationKind::CreateBranch => "createBranch",
        NativeRefMutationKind::RenameBranch => "renameBranch",
        NativeRefMutationKind::DeleteBranch => "deleteBranch",
        NativeRefMutationKind::CheckoutBranch => "checkoutBranch",
        NativeRefMutationKind::SetUpstream => "setUpstream",
        NativeRefMutationKind::UnsetUpstream => "unsetUpstream",
        NativeRefMutationKind::CreateTag => "createTag",
        NativeRefMutationKind::DeleteTag => "deleteTag",
        NativeRefMutationKind::AddRemote => "addRemote",
        NativeRefMutationKind::EditRemote => "editRemote",
        NativeRefMutationKind::RenameRemote => "renameRemote",
        NativeRefMutationKind::RemoveRemote => "removeRemote",
        NativeRefMutationKind::Reset => "reset",
        NativeRefMutationKind::CheckoutCommit => "checkoutCommit",
    }
}

pub fn parse_kind(name: &str) -> Option<NativeRefMutationKind> {
    Some(match name {
        "createBranch" => NativeRefMutationKind::CreateBranch,
        "renameBranch" => NativeRefMutationKind::RenameBranch,
        "deleteBranch" => NativeRefMutationKind::DeleteBranch,
        "checkoutBranch" => NativeRefMutationKind::CheckoutBranch,
        "setUpstream" => NativeRefMutationKind::SetUpstream,
        "unsetUpstream" => NativeRefMutationKind::UnsetUpstream,
        "createTag" => NativeRefMutationKind::CreateTag,
        "deleteTag" => NativeRefMutationKind::DeleteTag,
        "addRemote" => NativeRefMutationKind::AddRemote,
        "editRemote" => NativeRefMutationKind::EditRemote,
        "renameRemote" => NativeRefMutationKind::RenameRemote,
        "removeRemote" => NativeRefMutationKind::RemoveRemote,
        "reset" => NativeRefMutationKind::Reset,
        "checkoutCommit" => NativeRefMutationKind::CheckoutCommit,
        _ => return None,
    })
}

fn warning_name(warning: NativeRefMutationWarning) -> &'static str {
    match warning {
        NativeRefMutationWarning::DirtyCheckout => "dirtyCheckout",
        NativeRefMutationWarning::DetachedHead => "detachedHead",
        NativeRefMutationWarning::PublishedBranch => "publishedBranch",
        NativeRefMutationWarning::CheckedOutElsewhere => "checkedOutElsewhere",
        NativeRefMutationWarning::DestructiveReset => "destructiveReset",
    }
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// A reference request with the remote work around it.
#[derive(Clone, Debug)]
pub struct RefRequest {
    pub native: NativeRefMutationRequest,
    /// Remotes to delete the tag on first.
    pub remote_names: Vec<String>,
    /// The fetched upstream (remote, branch) to delete after the branch.
    pub delete_upstream: Option<(String, String)>,
}

impl RefRequest {
    pub fn plain(native: NativeRefMutationRequest) -> Self {
        Self {
            native,
            remote_names: Vec::new(),
            delete_upstream: None,
        }
    }

    fn to_value(&self) -> Value {
        let native = &self.native;
        json!({
            "kind": kind_name(native.kind),
            "name": native.name,
            "secondName": native.second_name,
            "target": native.target,
            "message": native.message,
            "url": native.url,
            "force": native.force,
            "resetMode": native.reset_mode.map(|mode| match mode {
                NativeRefResetMode::Soft => "soft",
                NativeRefResetMode::Mixed => "mixed",
                NativeRefResetMode::Hard => "hard",
            }),
            "checkout": native.checkout,
            "remoteNames": self.remote_names,
            "deleteUpstream": self.delete_upstream.as_ref().map(|(remote, branch)| json!({
                "remote": remote, "branch": branch, "label": format!("{remote}/{branch}"),
            })),
        })
    }

    pub fn from_value(value: &Value) -> Option<Self> {
        let text = |key: &str| {
            value[key]
                .as_str()
                .filter(|text| !text.is_empty())
                .map(str::to_owned)
        };
        Some(Self {
            native: NativeRefMutationRequest {
                kind: parse_kind(value["kind"].as_str()?)?,
                name: text("name"),
                second_name: text("secondName"),
                target: text("target"),
                message: text("message"),
                url: text("url"),
                force: value["force"].as_bool().unwrap_or(false),
                reset_mode: match value["resetMode"].as_str() {
                    Some("soft") => Some(NativeRefResetMode::Soft),
                    Some("mixed") => Some(NativeRefResetMode::Mixed),
                    Some("hard") => Some(NativeRefResetMode::Hard),
                    _ => None,
                },
                checkout: value["checkout"].as_bool().unwrap_or(false),
            },
            remote_names: value["remoteNames"]
                .as_array()
                .map(|items| {
                    items
                        .iter()
                        .filter_map(|item| item.as_str().map(str::to_owned))
                        .collect()
                })
                .unwrap_or_default(),
            delete_upstream: value["deleteUpstream"]["remote"]
                .as_str()
                .zip(value["deleteUpstream"]["branch"].as_str())
                .map(|(remote, branch)| (remote.to_owned(), branch.to_owned())),
        })
    }
}

/// The references the dialogs offer.
pub fn references_payload(refs: &NativeRepositoryRefs) -> Value {
    json!({
        "branches": refs.branches.iter().map(|branch| json!({
            "name": text(&branch.name),
            "upstream": branch.upstream.as_deref().filter(|_| !branch.upstream_gone).map(text),
            "head": branch.head,
        })).collect::<Vec<_>>(),
        "remotes": refs.remotes.iter().map(|remote| json!({
            "name": text(&remote.name),
            "url": text(&remote.display_url),
            "branches": remote.branches.iter().map(|branch| text(&branch.name)).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
        "tags": refs.tags.iter().map(|tag| json!({"name": text(&tag.name), "target": tag.target})).collect::<Vec<_>>(),
    })
}

pub struct RefService {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    transfers: Rc<TransferService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
}

fn done(state: NativeRefMutationExecutionState) -> bool {
    matches!(
        state,
        NativeRefMutationExecutionState::Completed
            | NativeRefMutationExecutionState::ReconciledWithWarning
    )
}

impl RefService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        transfers: Rc<TransferService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            transfers,
            prompts,
            notices,
        })
    }

    fn identity(&self) -> Option<SessionIdentity> {
        self.workspace.current().map(|session| session.identity)
    }

    fn refs(&self) -> NativeRepositoryRefs {
        self.workspace
            .current()
            .map(|session| session.snapshot.refs.clone())
            .unwrap_or_default()
    }

    /// Asks for a reference change of `kind`, runs it, and reopens the
    /// dialog with its input when the target commit went missing.
    pub async fn mutate(
        &self,
        kind: NativeRefMutationKind,
        initial_name: Option<String>,
        initial_target: Option<String>,
    ) {
        let identity = self.identity();
        let mut previous: Option<RefRequest> = None;
        loop {
            let head = self.workspace.current().and_then(|session| {
                session
                    .snapshot
                    .status
                    .as_ref()
                    .and_then(|status| status.head_object_id.clone())
            });
            let payload = json!({
                "kind": kind_name(kind),
                "references": references_payload(&self.refs()),
                "initialName": initial_name,
                // Commands outside a commit context start at HEAD.
                "initialTarget": initial_target.clone().or(head),
                "previous": previous.as_ref().map(RefRequest::to_value),
            });
            let Some(answer) = self.prompts.ask("chooseRefMutation", payload).await else {
                return;
            };
            let Some(request) = RefRequest::from_value(&answer) else {
                return;
            };
            if self.identity() != identity {
                self.notices.error("refMutationStale", Value::Null);
                return;
            }
            let missing = self.run(request.clone(), true).await;
            if !missing || self.identity() != identity {
                return;
            }
            if self.prompts.ask("recoverRefTarget", Value::Null).await != Some(Value::Bool(true)) {
                return;
            }
            let Some(identity) = identity else { return };
            if self.workspace.refresh_and_wait(identity).await.is_err() {
                self.notices.status("refMutationFailed", Value::Null);
                return;
            }
            self.workspace.history.load(identity, Vec::new()).await;
            previous = Some(request);
        }
    }

    /// Runs `request`; true when its target was missing and may be recovered.
    pub async fn run(&self, request: RefRequest, recover_missing_target: bool) -> bool {
        let Some(identity) = self.identity() else {
            return false;
        };
        let same = || self.identity() == Some(identity);
        let preview = match self
            .calls
            .repository_session_ref_mutation_preview(
                identity.native_id,
                identity.generation,
                request.native.clone(),
            )
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, Some(failure)) => {
                    let code = FailureCode::from(&failure);
                    if recover_missing_target
                        && request.native.target.is_some()
                        && code == FailureCode::MissingObject
                    {
                        return true;
                    }
                    self.report_failure(code, false);
                    return false;
                }
                _ => {
                    self.report_failure(FailureCode::InvalidOutput, false);
                    return false;
                }
            },
            Err(error) => {
                self.report_failure(SessionError::from(error).code(), false);
                return false;
            }
        };
        let local_tag = if request.native.kind == NativeRefMutationKind::DeleteTag {
            let name = request.native.name.clone().unwrap_or_default();
            self.refs()
                .tags
                .iter()
                .find(|tag| text(&tag.name) == name)
                .map(|tag| tag.target.clone())
        } else {
            None
        };
        let confirmed = self
            .prompts
            .ask(
                "confirmRefMutation",
                json!({
                    "request": request.to_value(),
                    "arguments": preview.arguments,
                    "warnings": preview.warnings.iter().map(|warning| warning_name(*warning)).collect::<Vec<_>>(),
                    "localTagObjectId": local_tag,
                }),
            )
            .await
            == Some(Value::Bool(true));
        if !confirmed || !same() {
            return false;
        }
        let mut remote_tag_deleted = false;
        for remote in &request.remote_names {
            let succeeded = self
                .transfers
                .execute(
                    NativeTransferRequest {
                        kind: NativeTransferKind::DeleteTag,
                        remote: Some(remote.clone()),
                        branch: request.native.name.clone(),
                        pull_strategy: NativePullStrategy::FastForwardOnly,
                        allow_dirty: false,
                        stash_before_pull: false,
                        force_with_lease: false,
                        set_upstream: false,
                        refetch: false,
                        prune: true,
                    },
                    false,
                )
                .await;
            remote_tag_deleted |= succeeded;
            if !same() {
                return false;
            }
            if !succeeded {
                self.notices
                    .status("deleteTagRemoteFailed", json!({"remote": remote}));
                return false;
            }
        }
        let result = match self
            .calls
            .repository_session_ref_mutation_execute(
                identity.native_id,
                identity.generation,
                preview.token,
            )
            .await
        {
            Ok(result) => result,
            Err(error) => {
                self.report_failure(SessionError::from(error).code(), remote_tag_deleted);
                return false;
            }
        };
        if let Some(failure) = &result.failure
            && result.state == NativeRefMutationExecutionState::Failed
        {
            let code = FailureCode::from(failure);
            if recover_missing_target
                && request.native.target.is_some()
                && !remote_tag_deleted
                && code == FailureCode::MissingObject
            {
                return true;
            }
        }
        // The remote branch goes only after the local one.
        if let Some((remote, branch)) = &request.delete_upstream
            && done(result.state)
        {
            let label = format!("{remote}/{branch}");
            let succeeded = same()
                && self
                    .transfers
                    .execute(
                        NativeTransferRequest {
                            kind: NativeTransferKind::DeleteBranch,
                            remote: Some(remote.clone()),
                            branch: Some(branch.clone()),
                            pull_strategy: NativePullStrategy::FastForwardOnly,
                            allow_dirty: false,
                            stash_before_pull: false,
                            force_with_lease: false,
                            set_upstream: false,
                            refetch: false,
                            prune: true,
                        },
                        false,
                    )
                    .await;
            if !succeeded {
                self.notices
                    .status("deleteBranchUpstreamFailed", json!({"upstream": label}));
                return false;
            }
        }
        self.report(result.state, remote_tag_deleted);
        false
    }

    fn report(&self, state: NativeRefMutationExecutionState, remote_tag_deleted: bool) {
        let key = if remote_tag_deleted && !done(state) {
            "deleteTagLocalFailedAfterRemote"
        } else {
            match state {
                NativeRefMutationExecutionState::Completed => "refMutationCompleted",
                NativeRefMutationExecutionState::Stale => "refMutationStale",
                NativeRefMutationExecutionState::Failed => "refMutationFailed",
                NativeRefMutationExecutionState::ReconciledWithWarning => {
                    "refMutationWarningResult"
                }
                NativeRefMutationExecutionState::OutcomeUncertain => "mutationOutcomeUncertain",
            }
        };
        if matches!(
            state,
            NativeRefMutationExecutionState::Failed | NativeRefMutationExecutionState::Stale
        ) {
            self.notices.error(key, Value::Null);
        } else {
            self.notices.status(key, Value::Null);
        }
    }

    fn report_failure(&self, code: FailureCode, remote_tag_deleted: bool) {
        let operation = if remote_tag_deleted {
            "deleteTagLocalFailedAfterRemote"
        } else {
            "refMutationFailed"
        };
        self.notices.status(
            "operationFailureWithReason",
            json!({"operation": {"l10n": operation}, "reason": {"l10n": crate::changes::failure_reason_key(code)}}),
        );
    }

    /// Renames the branch `initial_name` (the current one by default) and
    /// changes its upstream.
    pub async fn edit_branch(&self, initial_name: Option<String>) {
        let snapshot = self
            .workspace
            .current()
            .map(|session| Rc::clone(&session.snapshot));
        let current = snapshot.as_ref().and_then(|snapshot| {
            snapshot
                .status
                .as_ref()
                .and_then(|status| status.branch_name.as_deref())
                .map(text)
        });
        let (Some(snapshot), Some(branch)) = (snapshot, initial_name.or(current)) else {
            return Box::pin(self.mutate(NativeRefMutationKind::RenameBranch, None, None)).await;
        };
        let upstream = snapshot
            .refs
            .branches
            .iter()
            .find(|candidate| text(&candidate.name) == branch)
            .and_then(|candidate| candidate.upstream.as_deref())
            .map(|upstream| display_reference(&text(upstream)).to_owned());
        let Some(answer) = self
            .prompts
            .ask(
                "editBranch",
                json!({"branch": branch, "upstream": upstream, "references": references_payload(&snapshot.refs)}),
            )
            .await
        else {
            return;
        };
        let name = answer["name"].as_str().unwrap_or(&branch).to_owned();
        let chosen = answer["upstream"].as_str().map(str::to_owned);
        let mut requests = Vec::new();
        let base = |kind, name: Option<String>, second: Option<String>| NativeRefMutationRequest {
            kind,
            name,
            second_name: second,
            target: None,
            message: None,
            url: None,
            force: false,
            reset_mode: None,
            checkout: false,
        };
        if name != branch {
            requests.push(base(
                NativeRefMutationKind::RenameBranch,
                Some(branch.clone()),
                Some(name.clone()),
            ));
        }
        if chosen != upstream {
            requests.push(match &chosen {
                None => base(
                    NativeRefMutationKind::UnsetUpstream,
                    Some(name.clone()),
                    None,
                ),
                Some(upstream) => base(
                    NativeRefMutationKind::SetUpstream,
                    Some(name.clone()),
                    Some(upstream.clone()),
                ),
            });
        }
        let Some(identity) = self.identity() else {
            return;
        };
        let mut state = NativeRefMutationExecutionState::Completed;
        for request in requests {
            let preview = match self
                .calls
                .repository_session_ref_mutation_preview(
                    identity.native_id,
                    identity.generation,
                    request.clone(),
                )
                .await
            {
                Ok(result) => match result.preview {
                    Some(preview) if result.failure.is_none() => preview,
                    _ => {
                        self.report_failure(
                            result
                                .failure
                                .as_ref()
                                .map_or(FailureCode::InvalidOutput, FailureCode::from),
                            false,
                        );
                        return;
                    }
                },
                Err(error) => return self.report_failure(SessionError::from(error).code(), false),
            };
            if !preview.warnings.is_empty() {
                let confirmed = self
                    .prompts
                    .ask(
                        "confirmRefMutation",
                        json!({
                            "request": RefRequest::plain(request.clone()).to_value(),
                            "arguments": preview.arguments,
                            "warnings": preview.warnings.iter().map(|warning| warning_name(*warning)).collect::<Vec<_>>(),
                        }),
                    )
                    .await
                    == Some(Value::Bool(true));
                if !confirmed {
                    return;
                }
            }
            match self
                .calls
                .repository_session_ref_mutation_execute(
                    identity.native_id,
                    identity.generation,
                    preview.token,
                )
                .await
            {
                Ok(result) => state = result.state,
                Err(error) => return self.report_failure(SessionError::from(error).code(), false),
            }
            if !done(state) {
                break;
            }
        }
        self.report(state, false);
    }

    /// Checks out `name`; a remote-tracking branch checks out the local
    /// branch tracking it, or creates one.
    pub async fn checkout(&self, name: Option<String>, reference: Option<String>) {
        let refs = self.refs();
        if let Some(name) = &name {
            let remote_tracking = reference
                .as_deref()
                .is_some_and(|reference| reference.starts_with("refs/remotes/"));
            let local_exists = refs
                .branches
                .iter()
                .any(|branch| &text(&branch.name) == name);
            if remote_tracking || (reference.is_none() && !local_exists) {
                // The longest remote name that prefixes `name`.
                let split = refs
                    .remotes
                    .iter()
                    .map(|remote| text(&remote.name))
                    .filter(|remote| {
                        name.len() > remote.len() + 1
                            && name.starts_with(remote.as_str())
                            && name.as_bytes()[remote.len()] == b'/'
                    })
                    .max_by_key(String::len)
                    .map(|remote| (name[remote.len() + 1..].to_owned(), remote));
                if let Some((branch, remote)) = split {
                    let remote_ref = format!("refs/remotes/{remote}/{branch}");
                    let tracking = refs.branches.iter().find(|candidate| {
                        candidate
                            .upstream
                            .as_deref()
                            .is_some_and(|upstream| text(upstream) == remote_ref)
                    });
                    return match tracking {
                        Some(local) => {
                            Box::pin(self.mutate(
                                NativeRefMutationKind::CheckoutBranch,
                                Some(text(&local.name)),
                                None,
                            ))
                            .await
                        }
                        None => {
                            Box::pin(self.mutate(
                                NativeRefMutationKind::CreateBranch,
                                Some(branch),
                                Some(remote_ref),
                            ))
                            .await
                        }
                    };
                }
            }
        }
        Box::pin(self.mutate(NativeRefMutationKind::CheckoutBranch, name, None)).await
    }

    /// Deletes a branch on its remote (asks which in the transfer dialog).
    pub async fn delete_remote_branch(&self, reference: Option<String>) {
        let refs = self.refs();
        let target = reference.as_deref().and_then(|reference| {
            let short = reference.strip_prefix("refs/remotes/").unwrap_or(reference);
            refs.remotes
                .iter()
                .map(|remote| text(&remote.name))
                .filter(|remote| {
                    short.len() > remote.len() + 1 && short.starts_with(remote.as_str())
                })
                .max_by_key(String::len)
                .map(|remote| (short[remote.len() + 1..].to_owned(), remote))
        });
        let mut draft = Draft::new(NativeTransferKind::DeleteBranch);
        draft.initial_remote = target.as_ref().map(|(_, remote)| remote.clone());
        draft.initial_branch = Some(target.map(|(branch, _)| branch).unwrap_or_default());
        self.transfers.start(draft).await;
    }
}
