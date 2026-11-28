//! Committing: the commit
//! draft each worktree keeps in the settings, the commit tools (recent
//! messages, template), and preview → confirm → execute with retries
//! without hooks or unsigned. A committed draft is cleared durably.

use crate::backend::SessionCalls;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::session::{FailureCode, SessionError, SessionIdentity};
use crate::settings::SettingsService;
use crate::workspace::WorkspaceService;
use gitlama_contract::advanced_rebase::NativeFixupSuggestionResult;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{
    NativeCommitExecutionResult, NativeCommitExecutionState, NativeCommitRequest,
    NativeCommitSigning, NativeCommitTools, NativeCommitWarning,
};
use gitlama_contract::storage::{
    NativeCommitDraft, NativeSettingsDocument, NativeWorktreeSettings,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;

/// How a failed commit is tried again.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Retry {
    SkipHooks,
    Unsigned,
}

/// What a commit attempt ended in.
#[derive(Clone, Debug)]
pub enum Outcome {
    /// The person declined a confirmation.
    Declined,
    /// Git refused the commit (a hook, signing); the editor shows why.
    Rejected {
        result: NativeCommitExecutionResult,
        push: bool,
    },
    Finished {
        result: NativeCommitExecutionResult,
        push_next: bool,
    },
    /// The repository may have changed; never retried.
    OutcomeUnknown,
    Failed(FailureCode),
}

/// The flash History shows for a new commit.
#[derive(Clone, Debug)]
pub struct Committed {
    pub sequence: u64,
    pub object_id: String,
    pub amend: bool,
}

pub struct CommitService {
    calls: Rc<dyn SessionCalls>,
    settings: Rc<SettingsService>,
    workspace: Rc<WorkspaceService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    busy: Rc<crate::busy::BusyService>,
    flashes: RefCell<VecDeque<(NativePathIdentity, Committed)>>,
    sequence: Cell<u64>,
    /// Per session and HEAD: a new HEAD brings new recent messages.
    tools: RefCell<HashMap<(u64, u64, Option<String>), Rc<NativeCommitTools>>>,
}

fn with_draft(
    document: &mut NativeSettingsDocument,
    canonical: &NativePathIdentity,
    draft: NativeCommitDraft,
) {
    match document
        .worktrees
        .iter_mut()
        .find(|worktree| &worktree.identity == canonical)
    {
        Some(worktree) => worktree.draft = draft,
        None => document.worktrees.push(NativeWorktreeSettings {
            draft,
            ..worktree_settings(canonical.clone())
        }),
    }
}

fn worktree_settings(identity: NativePathIdentity) -> NativeWorktreeSettings {
    NativeWorktreeSettings {
        identity,
        filter: String::new(),
        anchor: None,
        pane: "changes".into(),
        route: "repository".into(),
        changes_scroll_offset: 0,
        history_scroll_offset: 0,
        draft: NativeCommitDraft {
            subject: String::new(),
            description: String::new(),
        },
        branch_filter: Vec::new(),
    }
}

impl CommitService {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        settings: Rc<SettingsService>,
        workspace: Rc<WorkspaceService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
        busy: Rc<crate::busy::BusyService>,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            settings,
            workspace,
            prompts,
            notices,
            notifier,
            busy,
            flashes: RefCell::new(VecDeque::new()),
            sequence: Cell::new(0),
            tools: RefCell::new(HashMap::new()),
        })
    }

    /// The draft the worktree `canonical` keeps.
    pub fn draft(&self, canonical: Option<&NativePathIdentity>) -> NativeCommitDraft {
        let Some(canonical) = canonical else {
            return NativeCommitDraft {
                subject: String::new(),
                description: String::new(),
            };
        };
        self.settings.with(|document| {
            document
                .worktrees
                .iter()
                .find(|worktree| &worktree.identity == canonical)
                .map(|worktree| worktree.draft.clone())
                .unwrap_or(NativeCommitDraft {
                    subject: String::new(),
                    description: String::new(),
                })
        })
    }

    /// Keeps the editor's text as the worktree's draft (saved after a pause).
    pub fn update_draft(&self, canonical: &NativePathIdentity, draft: NativeCommitDraft) {
        if self.draft(Some(canonical)) == draft {
            return;
        }
        let mut document = self.settings.current();
        with_draft(&mut document, canonical, draft);
        drop(self.settings.update_view(document));
    }

    /// The newest commit `canonical` made here, for History's flash.
    pub fn last_committed(&self, canonical: Option<&NativePathIdentity>) -> Option<Committed> {
        let canonical = canonical?;
        self.flashes
            .borrow()
            .iter()
            .find(|(identity, _)| identity == canonical)
            .map(|(_, committed)| committed.clone())
    }

    /// Recent messages and the template of `session` (loaded once).
    pub async fn tools(
        &self,
        session: SessionIdentity,
        head: Option<String>,
    ) -> Option<Rc<NativeCommitTools>> {
        let key = (session.native_id, session.generation, head);
        if let Some(tools) = self.tools.borrow().get(&key) {
            return Some(Rc::clone(tools));
        }
        let result = self
            .calls
            .repository_session_commit_tools(session.native_id, session.generation)
            .await
            .ok()?;
        let tools = Rc::new(result.tools.filter(|_| result.failure.is_none())?);
        let mut cache = self.tools.borrow_mut();
        // Only the session's current HEAD stays.
        cache.retain(|(id, generation, _), _| (*id, *generation) != (key.0, key.1));
        cache.insert(key, Rc::clone(&tools));
        Some(tools)
    }

    /// The commit the staged change most likely fixes, from the history of `paths`.
    pub async fn fixup_suggestion(
        &self,
        session: SessionIdentity,
        paths: Vec<Vec<u8>>,
    ) -> Option<NativeFixupSuggestionResult> {
        self.calls
            .repository_session_fixup_suggestion(session.native_id, session.generation, None, paths)
            .await
            .ok()
    }

    /// Commits `request` in the active tab; `draft` is the editor's text.
    pub async fn commit(
        &self,
        mut request: NativeCommitRequest,
        draft: NativeCommitDraft,
        push: bool,
        retry: Option<Retry>,
    ) -> Outcome {
        if retry == Some(Retry::SkipHooks)
            && self.prompts.ask("confirmSkipHooks", Value::Null).await != Some(Value::Bool(true))
        {
            return Outcome::Declined;
        }
        match retry {
            Some(Retry::SkipHooks) => request.skip_hooks = true,
            Some(Retry::Unsigned) => request.signing = NativeCommitSigning::Disable,
            None => {}
        }
        let Some(tab) = self.workspace.active_tab() else {
            return Outcome::Failed(FailureCode::UnknownSession);
        };
        let (Some(session), Some(canonical)) = (
            tab.session.as_ref().map(|session| session.identity),
            tab.canonical_identity().cloned(),
        ) else {
            return Outcome::Failed(FailureCode::UnknownSession);
        };
        self.update_draft(&canonical, draft.clone());
        let amend = request.amend;
        let preview = match self
            .calls
            .repository_session_commit_preview(session.native_id, session.generation, request)
            .await
        {
            Ok(result) => match (result.preview, result.failure) {
                (Some(preview), None) => preview,
                (_, Some(failure)) => return Outcome::Failed(FailureCode::from(&failure)),
                _ => return Outcome::Failed(FailureCode::InvalidOutput),
            },
            Err(error) => return Outcome::Failed(SessionError::from(error).code()),
        };
        if preview
            .warnings
            .contains(&NativeCommitWarning::PublishedAmend)
            && self.prompts.ask("confirmPublishedAmend", Value::Null).await
                != Some(Value::Bool(true))
        {
            return Outcome::Declined;
        }
        // Hooks and signing can take a while: the Compass names the commit meanwhile.
        let execute = self.calls.repository_session_commit_execute(
            session.native_id,
            session.generation,
            preview.token,
        );
        let result = match self
            .busy
            .run(
                Some(tab.id),
                crate::busy::BusyActivity::Commit,
                false,
                None,
                execute,
            )
            .await
        {
            Ok(result) => result,
            Err(error) => {
                return match error {
                    crate::backend::CallError::Transport(_) => Outcome::OutcomeUnknown,
                    crate::backend::CallError::Remote(code) if code == "outcomeUnknown" => {
                        Outcome::OutcomeUnknown
                    }
                    other => Outcome::Failed(SessionError::from(other).code()),
                };
            }
        };
        if let Some(failure) = &result.failure
            && result.state == NativeCommitExecutionState::Failed
            && result.failure_kind.is_none()
        {
            return Outcome::Failed(FailureCode::from(failure));
        }
        if result.state == NativeCommitExecutionState::Failed {
            return Outcome::Rejected { result, push };
        }
        let committed = matches!(
            result.state,
            NativeCommitExecutionState::Completed
                | NativeCommitExecutionState::ReconciledWithWarning
        );
        if committed && let Some(object_id) = result.commit.clone() {
            let sequence = self.sequence.get() + 1;
            self.sequence.set(sequence);
            let mut flashes = self.flashes.borrow_mut();
            flashes.retain(|(identity, _)| identity != &canonical);
            flashes.push_front((
                canonical.clone(),
                Committed {
                    sequence,
                    object_id,
                    amend,
                },
            ));
            flashes.truncate(16);
            drop(flashes);
            self.notifier.notify(Topics::HISTORY | Topics::CHANGES);
        }
        if committed && self.draft(Some(&canonical)) == draft {
            let empty = NativeCommitDraft {
                subject: String::new(),
                description: String::new(),
            };
            let previous = draft.clone();
            let target = canonical.clone();
            let restore_target = canonical.clone();
            drop(
                self.settings
                    .update_durable(
                        move |document| with_draft(document, &target, empty),
                        move |document, _| with_draft(document, &restore_target, previous),
                    )
                    .await,
            );
        }
        self.report(&result);
        Outcome::Finished {
            push_next: push && committed,
            result,
        }
    }

    fn report(&self, result: &NativeCommitExecutionResult) {
        let short = result
            .commit
            .as_deref()
            .map(|commit| &commit[..commit.len().min(7)]);
        match result.state {
            NativeCommitExecutionState::Stale => self.notices.status("commitStale", Value::Null),
            NativeCommitExecutionState::Failed => self.notices.status("commitFailed", Value::Null),
            NativeCommitExecutionState::ReconciledWithWarning => {
                self.notices.status("commitWarning", Value::Null)
            }
            NativeCommitExecutionState::Completed => match short {
                Some(short) => self
                    .notices
                    .status("commitCommittedObject", json!({"objectId": short})),
                None => self.notices.status("commitCompleted", Value::Null),
            },
            NativeCommitExecutionState::OutcomeUncertain => {
                self.notices.error("mutationOutcomeUncertain", Value::Null)
            }
        }
    }
}
