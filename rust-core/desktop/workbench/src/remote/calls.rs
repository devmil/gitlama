//! The repository session calls of one remote helper connection. Reads go through the generated wire encoding
//! ([`crate::backend::calls::wire_reads`]); session lifecycle, events and the write families are
//! implemented here: events arrive as publications and are drained locally, writes are
//! recorded in the ledger before Execute is sent and resolve from the helper's receipt.

use super::channel::{CallFault, Channel};
use super::protocol::Publication;
use crate::backend::{
    CallError, CallResult, RemoteCalls, RemoteCustom, SessionCalls, WireTransport,
};
use futures::future::{FutureExt, LocalBoxFuture};
use gitlama_application::wire::contract::{
    self, RemoteCapability, RemoteErrorCode, RemoteWriteFamily,
};
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Value};
use gitlama_contract::domain::path_identity::{NativePathPlatform, NativeRemoteAuthority};
use gitlama_contract::remote_pending::NativeRemotePendingOperation;
use gitlama_core::api::*;
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet, VecDeque};
use std::rc::{Rc, Weak};

/// Reads whose results depend only on their identities and arguments; kept locally.
const IMMUTABLE_READS: [&str; 3] = [
    "repositorySessionCommitInspection",
    "repositorySessionTree",
    "repositorySessionCommitFileContent",
];
/// The local memory budget for immutable read results of one connection.
const CONTENT_CACHE_BYTES: usize = 32 * 1024 * 1024;
/// Events kept per session between drains; older ones collapse.
const MAXIMUM_QUEUED_EVENTS: usize = 1024;
const MAXIMUM_ORPHAN_SESSIONS: usize = 8;
const MAXIMUM_ORPHAN_BATCHES: usize = 16;

/// Records remote writes durably on this computer.
pub trait Ledger {
    /// Records `operation`; fails when the record cannot be kept.
    fn record(
        &self,
        operation: NativeRemotePendingOperation,
    ) -> LocalBoxFuture<'static, Result<(), ()>>;
}

struct Session {
    helper_id: u64,
    binding: Option<String>,
    events: Vec<NativeRepositoryEvent>,
    failure: Option<NativeRepositoryFailure>,
}

/// A helper preview of a write the core previewed too, kept by family and core token.
#[derive(Clone)]
struct CorePreview {
    helper_session: u64,
    token: String,
    epoch: String,
    digest: String,
    binding: String,
    summary: String,
}

#[derive(Default)]
struct Inner {
    sessions: HashMap<u64, Session>,
    local_by_helper: HashMap<u64, u64>,
    orphans: HashMap<u64, Vec<NativeRepositoryEventsResult>>,
    closed_helper_sessions: HashSet<u64>,
    core_previews: HashMap<String, CorePreview>,
    content: HashMap<String, (Value, usize)>,
    content_order: VecDeque<String>,
    content_bytes: usize,
}

/// What an admitted write answered.
enum Admitted {
    /// The helper's result value (absent when the receipt existed already).
    Result(Value),
    /// The host refused it because its preview expired or its preconditions changed.
    Stale,
}

/// The session calls of one connection.
pub struct RemoteSessions {
    channel: Rc<Channel>,
    pub authority: NativeRemoteAuthority,
    ledger: Rc<dyn Ledger>,
    allocate: Rc<dyn Fn() -> u64>,
    expected_binding: Rc<dyn Fn(&[u8]) -> Option<String>>,
    remember_binding: Rc<dyn Fn(&[u8], &str)>,
    inner: RefCell<Inner>,
    writes_in_flight: Cell<u32>,
    last_write_at_ms: Cell<u64>,
    on_events: RefCell<Option<Rc<dyn Fn()>>>,
    this: Weak<RemoteSessions>,
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |elapsed| {
            u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX)
        })
}

fn fault(fault: CallFault) -> CallError {
    match fault {
        CallFault::Disconnected => CallError::Transport("disconnected".to_owned()),
        CallFault::Code(code) => CallError::Remote(code.name().to_owned()),
    }
}

fn outcome_unknown() -> CallError {
    CallError::Remote("outcomeUnknown".to_owned())
}

fn unknown_session<T>() -> CallResult<T> {
    Err(CallError::UnknownSession)
}

fn wire<T>(result: Result<T, w::WireError>) -> CallResult<T> {
    result.map_err(CallError::Wire)
}

fn summary(text: &str) -> String {
    text.chars().take(contract::SUMMARY_CHARACTERS).collect()
}

impl RemoteSessions {
    #[must_use]
    pub fn new(
        channel: Rc<Channel>,
        authority: NativeRemoteAuthority,
        ledger: Rc<dyn Ledger>,
        allocate: Rc<dyn Fn() -> u64>,
        expected_binding: Rc<dyn Fn(&[u8]) -> Option<String>>,
        remember_binding: Rc<dyn Fn(&[u8], &str)>,
    ) -> Rc<Self> {
        let sessions = Rc::new_cyclic(|this| Self {
            channel: Rc::clone(&channel),
            authority,
            ledger,
            allocate,
            expected_binding,
            remember_binding,
            inner: RefCell::new(Inner::default()),
            writes_in_flight: Cell::new(0),
            last_write_at_ms: Cell::new(0),
            on_events: RefCell::new(None),
            this: this.clone(),
        });
        let weak = Rc::downgrade(&sessions);
        channel.on_publication(move |publication| {
            if let Some(sessions) = weak.upgrade() {
                sessions.publish(publication);
            }
        });
        sessions
    }

    /// The session calls of this connection.
    #[must_use]
    pub fn calls(self: &Rc<Self>) -> Rc<dyn SessionCalls> {
        Rc::new(RemoteCalls {
            custom: Rc::clone(self),
        })
    }

    #[must_use]
    pub fn channel(&self) -> &Rc<Channel> {
        &self.channel
    }

    fn rc(&self) -> Rc<Self> {
        self.this
            .upgrade()
            .expect("remote sessions are alive while called")
    }

    fn can(&self, capability: RemoteCapability) -> bool {
        self.channel.has(capability)
    }

    fn mark(&self, path: &mut NativePathIdentity) {
        path.remote = Some(self.authority.clone());
    }

    fn mark_snapshot(&self, snapshot: &mut NativeRepositorySnapshot) {
        if let Some(identity) = snapshot.identity.as_mut() {
            self.mark(&mut identity.common_git_dir);
            self.mark(&mut identity.worktree_root);
            self.mark(&mut identity.git_dir);
        }
    }

    /// Whether any session of this connection is still open here.
    #[must_use]
    pub fn has_sessions(&self) -> bool {
        !self.inner.borrow().sessions.is_empty()
    }

    /// Whether `session_id` is one of this connection's sessions.
    #[must_use]
    pub fn owns(&self, session_id: u64) -> bool {
        self.inner.borrow().sessions.contains_key(&session_id)
    }

    /// The binding of a local session, if it is live.
    #[must_use]
    pub fn binding_of(&self, session_id: u64) -> Option<String> {
        self.inner
            .borrow()
            .sessions
            .get(&session_id)
            .and_then(|session| session.binding.clone())
    }

    /// Whether a write is running or started within `within_ms`.
    #[must_use]
    pub fn recently_wrote(&self, within_ms: u64) -> bool {
        self.writes_in_flight.get() > 0
            || now_ms().saturating_sub(self.last_write_at_ms.get()) < within_ms
    }

    /// Installs a callback invoked whenever a remote publication queues session events.
    pub fn set_on_events(&self, callback: Rc<dyn Fn()>) {
        *self.on_events.borrow_mut() = Some(callback);
    }

    fn publish(&self, publication: &Publication) {
        let Ok(result) = g::dec_native_repository_events_result(&publication.events) else {
            return;
        };
        let mut inner = self.inner.borrow_mut();
        let Some(local) = inner.local_by_helper.get(&publication.session_id).copied() else {
            if inner
                .closed_helper_sessions
                .contains(&publication.session_id)
            {
                return;
            }
            // The open reply may still be on its way; keep a bounded backlog.
            if inner.orphans.len() >= MAXIMUM_ORPHAN_SESSIONS
                && !inner.orphans.contains_key(&publication.session_id)
            {
                return;
            }
            let backlog = inner.orphans.entry(publication.session_id).or_default();
            if backlog.len() >= MAXIMUM_ORPHAN_BATCHES {
                backlog.remove(0);
            }
            backlog.push(result);
            return;
        };
        let queued = if let Some(session) = inner.sessions.get_mut(&local) {
            queue(session, result);
            true
        } else {
            false
        };
        drop(inner);
        if queued && let Some(callback) = self.on_events.borrow().clone() {
            callback();
        }
    }

    async fn call(&self, method: &str, arguments: Value, bulk: bool) -> CallResult<Value> {
        self.channel
            .call(method, arguments, bulk)
            .await
            .map_err(fault)
    }

    // Operation center ----------------------------------------------------------

    /// The helper's operation center with entries of this connection's live sessions under
    /// their local session identifiers.
    pub async fn operation_center(
        &self,
        maximum_entries: u32,
    ) -> CallResult<Option<NativeOperationCenterSnapshot>> {
        let value = self
            .call(
                "operationCenter",
                serde_json::json!({ "maximumEntries": maximum_entries }),
                false,
            )
            .await?;
        let result = wire(g::dec_native_operation_center_result(&value))?;
        let Some(snapshot) = result.snapshot else {
            return Ok(None);
        };
        let inner = self.inner.borrow();
        Ok(Some(NativeOperationCenterSnapshot {
            entries: snapshot
                .entries
                .into_iter()
                .filter_map(|entry| {
                    let local = inner.local_by_helper.get(&entry.session_id?).copied()?;
                    Some(NativeOperationCenterEntry {
                        session_id: Some(local),
                        // A remote operation is neither canceled nor retried from here.
                        can_cancel: false,
                        can_retry: false,
                        ..entry
                    })
                })
                .collect(),
            ..snapshot
        }))
    }

    /// Dismisses a finished operation of local session `session_id`.
    pub async fn dismiss_operation(
        &self,
        session_id: u64,
        generation: u64,
        activity_id: u64,
    ) -> CallResult<()> {
        let helper = self
            .inner
            .borrow()
            .sessions
            .get(&session_id)
            .map(|session| session.helper_id);
        let Some(helper) = helper else { return Ok(()) };
        self.call(
            "operationDismiss",
            serde_json::json!({
                "sessionId": helper.to_string(),
                "generation": generation.to_string(),
                "activityId": activity_id.to_string(),
            }),
            false,
        )
        .await
        .map(|_| ())
    }

    // Directories and initialization ------------------------------------------

    /// One page of a remote directory.
    pub async fn list_directory(
        &self,
        directory: Option<&[u8]>,
        cursor: Option<&str>,
    ) -> Result<super::model::DirectoryPage, super::model::Failure> {
        use super::model::{DirectoryEntry, DirectoryPage, EntryKind, Failure};
        let reply = self
            .channel
            .call(
                "listDirectory",
                serde_json::json!({
                    "directory": directory.map(w::bytes_e),
                    "cursor": cursor,
                }),
                false,
            )
            .await
            .map_err(|fault| match fault {
                CallFault::Disconnected => Failure::Disconnected,
                CallFault::Code(code) => super::protocol::failure_of(code),
            })?;
        (|| -> Result<DirectoryPage, w::WireError> {
            let page = w::object(
                &reply,
                "listDirectory",
                &["directory", "parent", "entries", "cursor", "truncated"],
            )?;
            Ok(DirectoryPage {
                directory: w::bytes_d(page.field("directory"))?,
                parent: w::opt_d(page.field("parent"), w::bytes_d)?,
                entries: w::list_d(page.field("entries"), |value| {
                    let entry = w::object(value, "entry", &["name", "kind", "repository"])?;
                    Ok(DirectoryEntry {
                        name: w::bytes_d(entry.field("name"))?,
                        kind: match w::str_d(entry.field("kind"))?.as_str() {
                            "directory" => EntryKind::Directory,
                            "file" => EntryKind::File,
                            "symlink" => EntryKind::Symlink,
                            _ => EntryKind::Other,
                        },
                        repository: w::bool_d(entry.field("repository"))?,
                    })
                })?,
                cursor: w::opt_d(page.field("cursor"), w::str_d)?,
                truncated: w::bool_d(page.field("truncated"))?,
            })
        })()
        .map_err(|_| Failure::ProtocolViolation)
    }

    /// Creates a repository at the host `path` without opening it.
    ///
    /// # Errors
    /// The host's reason for creating nothing, or a connection failure.
    pub async fn initialize_repository(
        &self,
        path: &[u8],
        initial_branch: &str,
        bare: bool,
    ) -> Result<Option<NativeRepositoryFailureKind>, super::model::Failure> {
        use super::model::Failure;
        if !self.can(RemoteCapability::Initialize) {
            return Err(Failure::WriteNotPermitted);
        }
        let reply = self
            .channel
            .call(
                "initializeRepository",
                serde_json::json!({ "path": w::bytes_e(path), "initialBranch": initial_branch, "bare": bare }),
                false,
            )
            .await
            .map_err(|fault| match fault {
                CallFault::Disconnected => Failure::Disconnected,
                CallFault::Code(code) => super::protocol::failure_of(code),
            })?;
        (|| -> Result<Option<NativeRepositoryFailureKind>, w::WireError> {
            let result = w::object(&reply, "initializeRepository", &["failure"])?;
            w::opt_d(
                result.field("failure"),
                g::dec_native_repository_failure_kind,
            )
        })()
        .map_err(|_| Failure::ProtocolViolation)
    }

    // Writes -------------------------------------------------------------------

    fn operation(
        &self,
        family: RemoteWriteFamily,
        epoch: String,
        digest: String,
        binding: String,
        text: &str,
    ) -> NativeRemotePendingOperation {
        let now = now_ms();
        NativeRemotePendingOperation {
            operation_id: super::model::random_hex32(),
            epoch,
            digest,
            family: family.name().to_owned(),
            profile_id: self.authority.profile_id.clone(),
            store_id: self.authority.store_id.clone(),
            account_uid: self.authority.account_uid.clone(),
            binding,
            state: "pending".to_owned(),
            outcome: None,
            result_object_id: None,
            summary: summary(text),
            created_at_ms: now,
            updated_at_ms: now,
        }
    }

    /// Records `operation`, sends `method` and resolves the record from the helper's
    /// operation object.
    async fn admit(
        &self,
        operation: NativeRemotePendingOperation,
        method: &str,
        mut arguments: w::Map<String, Value>,
    ) -> CallResult<Admitted> {
        // No Execute byte leaves before the intent is durable.
        self.ledger
            .record(operation.clone())
            .await
            .map_err(|()| CallError::Remote("internal".to_owned()))?;
        arguments.insert(
            "operationId".to_owned(),
            Value::String(operation.operation_id.clone()),
        );
        self.writes_in_flight.set(self.writes_in_flight.get() + 1);
        self.last_write_at_ms.set(now_ms());
        // Hooks and signing run inside Execute: it gets the long deadline.
        let reply = self
            .channel
            .call(method, Value::Object(arguments), true)
            .await;
        self.writes_in_flight.set(self.writes_in_flight.get() - 1);
        let reply = match reply {
            Ok(reply) => reply,
            Err(error) => {
                let definite = matches!(
                    error,
                    CallFault::Code(
                        RemoteErrorCode::PreviewExpired
                            | RemoteErrorCode::PreconditionFailed
                            | RemoteErrorCode::AdmissionEpochRetired
                            | RemoteErrorCode::ReceiptCapacity
                            | RemoteErrorCode::WriteNotPermitted
                            | RemoteErrorCode::InvalidRequest
                            | RemoteErrorCode::UnknownSession
                            | RemoteErrorCode::Capacity
                    )
                );
                if !definite {
                    // Lost transport, timeouts and store failures leave the outcome open.
                    let _ = self
                        .ledger
                        .record(still_pending(&operation, Some("unknown")))
                        .await;
                    return Err(outcome_unknown());
                }
                let _ = self
                    .ledger
                    .record(resolved(&operation, "notApplied", None))
                    .await;
                if matches!(
                    error,
                    CallFault::Code(
                        RemoteErrorCode::PreviewExpired | RemoteErrorCode::PreconditionFailed
                    )
                ) {
                    return Ok(Admitted::Stale);
                }
                return Err(fault(error));
            }
        };
        let (record, result) = wire((|| {
            let object = w::object(&reply, "executed", &["operation", "result"])?;
            let record = w::object(
                object.field("operation"),
                "operation",
                &["operationId", "epoch", "state", "outcome", "resultObjectId"],
            )?;
            let outcome = w::opt_d(record.field("outcome"), w::str_d)?;
            let result_object_id = w::opt_d(record.field("resultObjectId"), w::str_d)?;
            Ok(((outcome, result_object_id), object.field("result").clone()))
        })())?;
        let (outcome, result_object_id) = record;
        let definite = outcome
            .as_deref()
            .and_then(contract::RemoteOutcome::parse)
            .is_some_and(contract::RemoteOutcome::definite);
        if definite {
            // A failed record leaves the operation pending; the next lookup resolves it.
            let _ = self
                .ledger
                .record(resolved(
                    &operation,
                    outcome.as_deref().unwrap_or("unknown"),
                    result_object_id,
                ))
                .await;
            Ok(Admitted::Result(result))
        } else {
            let _ = self
                .ledger
                .record(still_pending(&operation, outcome.as_deref()))
                .await;
            Err(outcome_unknown())
        }
    }

    fn live(&self, session_id: u64) -> CallResult<(u64, String)> {
        let inner = self.inner.borrow();
        match inner.sessions.get(&session_id) {
            Some(Session {
                helper_id,
                binding: Some(binding),
                ..
            }) => Ok((*helper_id, binding.clone())),
            _ => unknown_session(),
        }
    }

    /// Previews a `family` write in the helper and keeps the helper's token under the core's
    /// token of the decoded preview, so the matching execute admits exactly this preview.
    async fn preview_write<T>(
        &self,
        session_id: u64,
        generation: u64,
        family: RemoteWriteFamily,
        method: &str,
        request: Value,
        decode: fn(&Value) -> Result<T, w::WireError>,
        core_token: fn(&T) -> Option<u64>,
        text: String,
    ) -> CallResult<T> {
        let (helper, binding) = self.live(session_id)?;
        let reply = self
            .call(
                method,
                serde_json::json!({ "sessionId": helper.to_string(), "generation": generation.to_string(), "request": request }),
                false,
            )
            .await?;
        let reply = wire(w::object(
            &reply,
            "preview",
            &["token", "epoch", "digest", "expiresInMs", "preview"],
        ))?;
        let preview = wire(decode(reply.field("preview")))?;
        let token = wire(w::opt_d(reply.field("token"), w::str_d))?;
        if let (Some(token), Some(core)) = (token, core_token(&preview)) {
            let epoch = wire(w::str_d(reply.field("epoch")))?;
            let digest = wire(w::str_d(reply.field("digest")))?;
            self.inner.borrow_mut().core_previews.insert(
                format!("{}/{core}", family.name()),
                CorePreview {
                    helper_session: helper,
                    token,
                    epoch,
                    digest,
                    binding,
                    summary: text,
                },
            );
        }
        Ok(preview)
    }

    /// Admits the kept preview of `core_token`; `None` when no live preview matches.
    async fn execute_write(
        &self,
        session_id: u64,
        generation: u64,
        family: RemoteWriteFamily,
        method: &str,
        core_token: u64,
    ) -> CallResult<Option<Admitted>> {
        let preview = self
            .inner
            .borrow_mut()
            .core_previews
            .remove(&format!("{}/{core_token}", family.name()));
        let helper = self
            .inner
            .borrow()
            .sessions
            .get(&session_id)
            .map(|session| session.helper_id);
        let Some(preview) = preview.filter(|preview| Some(preview.helper_session) == helper) else {
            return Ok(None);
        };
        let operation = self.operation(
            family,
            preview.epoch.clone(),
            preview.digest.clone(),
            preview.binding.clone(),
            &preview.summary,
        );
        let mut arguments = w::Map::new();
        arguments.insert(
            "sessionId".to_owned(),
            Value::String(preview.helper_session.to_string()),
        );
        arguments.insert(
            "generation".to_owned(),
            Value::String(generation.to_string()),
        );
        arguments.insert("token".to_owned(), Value::String(preview.token));
        arguments.insert("epoch".to_owned(), Value::String(preview.epoch));
        arguments.insert("digest".to_owned(), Value::String(preview.digest));
        self.admit(operation, method, arguments).await.map(Some)
    }

    /// Previews and admits a write the core runs without a preview of its own (direct) or with
    /// a token it issued before (pass-through). A direct Execute carries `request` again.
    async fn admit_now(
        &self,
        session_id: u64,
        generation: u64,
        family: RemoteWriteFamily,
        name: &str,
        request: Value,
        text: &str,
        direct: bool,
    ) -> CallResult<Option<Admitted>> {
        let (helper, binding) = self.live(session_id)?;
        let method = format!("preview{name}");
        let preview = self
            .call(
                &method,
                serde_json::json!({ "sessionId": helper.to_string(), "generation": generation.to_string(), "request": request }),
                false,
            )
            .await?;
        let preview = wire(w::object(
            &preview,
            "preview",
            &["token", "epoch", "digest", "expiresInMs"],
        ))?;
        let Some(token) = wire(w::opt_d(preview.field("token"), w::str_d))? else {
            return Ok(None);
        };
        let epoch = wire(w::str_d(preview.field("epoch")))?;
        let digest = wire(w::str_d(preview.field("digest")))?;
        let operation = self.operation(family, epoch.clone(), digest.clone(), binding, text);
        let mut arguments = w::Map::new();
        arguments.insert("sessionId".to_owned(), Value::String(helper.to_string()));
        arguments.insert(
            "generation".to_owned(),
            Value::String(generation.to_string()),
        );
        arguments.insert("token".to_owned(), Value::String(token));
        arguments.insert("epoch".to_owned(), Value::String(epoch));
        arguments.insert("digest".to_owned(), Value::String(digest));
        if direct {
            arguments.insert("request".to_owned(), request);
        }
        self.admit(operation, &format!("execute{name}"), arguments)
            .await
            .map(Some)
    }

    /// Drops a preview that was never executed.
    fn drop_preview(&self, family: RemoteWriteFamily, token: u64) -> NativeRepositoryCommandResult {
        NativeRepositoryCommandResult {
            accepted: self
                .inner
                .borrow_mut()
                .core_previews
                .remove(&format!("{}/{token}", family.name()))
                .is_some(),
            failure: None,
        }
    }

    /// Reads the helper's receipt of `operation`.
    pub async fn lookup(
        &self,
        operation: &NativeRemotePendingOperation,
    ) -> CallResult<NativeRemotePendingOperation> {
        let reply = self
            .call(
                "lookupOperation",
                serde_json::json!({ "epoch": operation.epoch, "operationId": operation.operation_id, "digest": operation.digest }),
                false,
            )
            .await?;
        let (state, outcome, result_object_id) = wire((|| {
            let reply = w::object(&reply, "lookupOperation", &["operation"])?;
            let record = w::object(
                reply.field("operation"),
                "operation",
                &["operationId", "epoch", "state", "outcome", "resultObjectId"],
            )?;
            Ok((
                w::str_d(record.field("state"))?,
                w::opt_d(record.field("outcome"), w::str_d)?,
                w::opt_d(record.field("resultObjectId"), w::str_d)?,
            ))
        })())?;
        let parsed = outcome.as_deref().and_then(contract::RemoteOutcome::parse);
        let definite = state == "terminal" && parsed.is_some_and(contract::RemoteOutcome::definite);
        // A dead owner's Prepared receipt is proven not applied.
        let not_started = state == "prepared" && outcome.as_deref() == Some("notApplied");
        if definite || not_started {
            return Ok(resolved(
                operation,
                outcome.as_deref().unwrap_or("unknown"),
                result_object_id,
            ));
        }
        Ok(still_pending(
            operation,
            if outcome.as_deref() == Some("running") {
                None
            } else {
                outcome.as_deref()
            },
        ))
    }
}

fn queue(session: &mut Session, result: NativeRepositoryEventsResult) {
    session.events.extend(result.events);
    if result.failure.is_some() {
        session.failure = result.failure;
    }
    if session.events.len() > MAXIMUM_QUEUED_EVENTS {
        // Keep the newest snapshot as a resynchronization.
        let newest = session
            .events
            .iter()
            .rev()
            .find(|event| event.snapshot.is_some())
            .or(session.events.last())
            .cloned()
            .expect("events are queued");
        session.events = vec![NativeRepositoryEvent {
            kind: if newest.snapshot.is_some() {
                NativeRepositoryEventKind::Resynchronize
            } else {
                newest.kind
            },
            ..newest
        }];
    }
}

fn resolved(
    operation: &NativeRemotePendingOperation,
    outcome: &str,
    result_object_id: Option<String>,
) -> NativeRemotePendingOperation {
    NativeRemotePendingOperation {
        state: "terminal".to_owned(),
        outcome: Some(outcome.to_owned()),
        result_object_id: result_object_id.or_else(|| operation.result_object_id.clone()),
        updated_at_ms: now_ms(),
        ..operation.clone()
    }
}

fn still_pending(
    operation: &NativeRemotePendingOperation,
    outcome: Option<&str>,
) -> NativeRemotePendingOperation {
    NativeRemotePendingOperation {
        state: "pending".to_owned(),
        outcome: outcome.map(str::to_owned),
        updated_at_ms: now_ms(),
        ..operation.clone()
    }
}

fn value<T>(
    admitted: Option<Admitted>,
    stale: impl FnOnce() -> T,
    decode: fn(&Value) -> Result<T, w::WireError>,
) -> CallResult<T> {
    match admitted {
        Some(Admitted::Result(Value::Null)) | Some(Admitted::Stale) | None => Ok(stale()),
        Some(Admitted::Result(result)) => wire(decode(&result)),
    }
}

impl WireTransport for RemoteSessions {
    fn invoke_read(
        &self,
        method: &'static str,
        args: Value,
    ) -> LocalBoxFuture<'static, CallResult<Value>> {
        let this = self.rc();
        async move {
            if !IMMUTABLE_READS.contains(&method) {
                let bulk = contract::BULK_METHODS.contains(&method);
                return this.call(method, args, bulk).await;
            }
            let key = format!("{method} {args}");
            let cached = {
                let mut inner = this.inner.borrow_mut();
                let cached = inner.content.get(&key).map(|(value, _)| value.clone());
                if cached.is_some() {
                    inner.content_order.retain(|existing| existing != &key);
                    inner.content_order.push_back(key.clone());
                }
                cached
            };
            if let Some(cached) = cached {
                return Ok(cached);
            }
            let value = this.call(method, args, false).await?;
            if value.get("failure").is_some_and(Value::is_null) {
                let bytes = w::to_bytes(&value).len() + key.len();
                if bytes <= CONTENT_CACHE_BYTES / 4 {
                    let mut inner = this.inner.borrow_mut();
                    inner.content.insert(key.clone(), (value.clone(), bytes));
                    inner.content_order.push_back(key);
                    inner.content_bytes += bytes;
                    while inner.content_bytes > CONTENT_CACHE_BYTES {
                        let Some(oldest) = inner.content_order.pop_front() else {
                            break;
                        };
                        if let Some((_, size)) = inner.content.remove(&oldest) {
                            inner.content_bytes -= size;
                        }
                    }
                }
            }
            Ok(value)
        }
        .boxed_local()
    }

    fn helper_session(&self, session_id: u64) -> CallResult<u64> {
        self.inner
            .borrow()
            .sessions
            .get(&session_id)
            .map(|session| session.helper_id)
            .ok_or(CallError::UnknownSession)
    }
}

macro_rules! boxed {
    ($this:ident, $body:expr) => {{
        let $this = $this.rc();
        async move { $body }.boxed_local()
    }};
}

impl RemoteCustom for RemoteSessions {
    fn transport(&self) -> Rc<dyn WireTransport> {
        self.rc()
    }

    /// Every absolute path a read reports carries this connection's authority, so a remote
    /// path can never satisfy a local path boundary.
    fn adapt<T: 'static>(&self, value: T) -> T {
        use std::any::Any;
        let mut value = value;
        let any = &mut value as &mut dyn Any;
        if let Some(result) = any.downcast_mut::<NativeExtensionInventoryResult>() {
            if let Some(inventory) = result.inventory.as_mut() {
                for entry in &mut inventory.worktrees {
                    self.mark(&mut entry.worktree_root);
                    self.mark(&mut entry.git_dir);
                    self.mark(&mut entry.common_git_dir);
                }
            }
        } else if let Some(result) = any.downcast_mut::<NativeSubmoduleEnterResult>()
            && let Some(root) = result.worktree_root.as_mut()
        {
            self.mark(root);
        }
        value
    }

    fn repository_session_open(
        &self,
        _path: String,
        _generation: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryOpenResult>> {
        async { Err(CallError::Unsupported("repository_session_open")) }.boxed_local()
    }

    fn repository_session_open_identity(
        &self,
        identity: NativePathIdentity,
        generation: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryOpenResult>> {
        let this = self;
        boxed!(this, {
            if identity.platform != NativePathPlatform::Unix
                || identity.units.iter().any(|unit| *unit > 0xff)
            {
                return Ok(NativeRepositoryOpenResult {
                    session: None,
                    failure: Some(NativeRepositoryFailure {
                        kind: NativeRepositoryFailureKind::InvalidOptions,
                    }),
                });
            }
            let path: Vec<u8> = identity.units.iter().map(|unit| *unit as u8).collect();
            let reply = this
                .call(
                    "openRepository",
                    serde_json::json!({
                        "path": w::bytes_e(&path),
                        "generation": generation.to_string(),
                        "expectedBinding": (this.expected_binding)(&path),
                    }),
                    false,
                )
                .await?;
            let reply = wire(w::object(&reply, "openRepository", &["binding", "open"]))?;
            let binding = wire(w::opt_d(reply.field("binding"), w::str_d))?;
            let opened = wire(g::dec_native_repository_open_result(reply.field("open")))?;
            let Some(session) = opened.session else {
                return Ok(opened);
            };
            let local = (this.allocate)();
            {
                let mut inner = this.inner.borrow_mut();
                let mut state = Session {
                    helper_id: session.session_id,
                    binding: binding.clone(),
                    events: Vec::new(),
                    failure: None,
                };
                for backlog in inner
                    .orphans
                    .remove(&session.session_id)
                    .unwrap_or_default()
                {
                    queue(&mut state, backlog);
                }
                inner.sessions.insert(local, state);
                inner.local_by_helper.insert(session.session_id, local);
                inner.closed_helper_sessions.remove(&session.session_id);
            }
            if let Some(binding) = &binding {
                (this.remember_binding)(&path, binding);
            }
            let mut snapshot = session.snapshot;
            this.mark_snapshot(&mut snapshot);
            Ok(NativeRepositoryOpenResult {
                session: Some(NativeRepositorySession {
                    session_id: local,
                    generation: session.generation,
                    snapshot,
                }),
                failure: opened.failure,
            })
        })
    }

    fn repository_session_events(
        &self,
        session_id: u64,
        _generation: u64,
        maximum_events: u32,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryEventsResult>> {
        let result = {
            let mut inner = self.inner.borrow_mut();
            match inner.sessions.get_mut(&session_id) {
                None => NativeRepositoryEventsResult {
                    events: Vec::new(),
                    failure: None,
                },
                Some(session) => {
                    let count = (maximum_events as usize).min(session.events.len());
                    let mut events: Vec<NativeRepositoryEvent> =
                        session.events.drain(..count).collect();
                    for event in &mut events {
                        if let Some(snapshot) = event.snapshot.as_mut() {
                            self.mark_snapshot(snapshot);
                        }
                    }
                    NativeRepositoryEventsResult {
                        events,
                        failure: session.failure.take(),
                    }
                }
            }
        };
        async move { Ok(result) }.boxed_local()
    }

    fn repository_session_close(
        &self,
        session_id: u64,
        generation: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryCommandResult>> {
        let this = self;
        boxed!(this, {
            let accepted = NativeRepositoryCommandResult {
                accepted: true,
                failure: None,
            };
            let helper = {
                let mut inner = this.inner.borrow_mut();
                let Some(session) = inner.sessions.remove(&session_id) else {
                    return Ok(accepted);
                };
                inner.local_by_helper.remove(&session.helper_id);
                inner.closed_helper_sessions.insert(session.helper_id);
                inner.orphans.remove(&session.helper_id);
                let key = format!("\"sessionId\":\"{}\"", session.helper_id);
                let removed: Vec<String> = inner
                    .content
                    .keys()
                    .filter(|entry| entry.contains(&key))
                    .cloned()
                    .collect();
                for entry in removed {
                    if let Some((_, size)) = inner.content.remove(&entry) {
                        inner.content_bytes -= size;
                    }
                    inner.content_order.retain(|existing| existing != &entry);
                }
                inner
                    .core_previews
                    .retain(|_, preview| preview.helper_session != session.helper_id);
                session.helper_id
            };
            if !this.channel.is_open() {
                return Ok(accepted);
            }
            match this
                .call("closeRepository", serde_json::json!({ "sessionId": helper.to_string(), "generation": generation.to_string() }), false)
                .await
            {
                Ok(value) => wire(g::dec_native_repository_command_result(&value)),
                // The helper closes every session when its connection ends.
                Err(_) => Ok(accepted),
            }
        })
    }

    fn repository_session_staging_execute(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeStagingRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeStagingExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Stage) {
                return Err(CallError::Unsupported("repository_session_staging_execute"));
            }
            let (helper, binding) = this.live(session_id)?;
            let encoded = g::enc_native_staging_request(&request);
            let preview = this
                .call(
                    "previewStage",
                    serde_json::json!({ "sessionId": helper.to_string(), "generation": generation.to_string(), "request": encoded }),
                    false,
                )
                .await?;
            let preview = wire(w::object(
                &preview,
                "previewStage",
                &["token", "epoch", "digest", "expiresInMs"],
            ))?;
            let epoch = wire(w::str_d(preview.field("epoch")))?;
            let digest = wire(w::str_d(preview.field("digest")))?;
            let token = wire(w::str_d(preview.field("token")))?;
            let text = if request.side == NativeStagingSide::Unstaged {
                "stage"
            } else {
                "unstage"
            };
            let operation = this.operation(
                RemoteWriteFamily::Stage,
                epoch.clone(),
                digest.clone(),
                binding,
                text,
            );
            let mut arguments = w::Map::new();
            arguments.insert("sessionId".to_owned(), Value::String(helper.to_string()));
            arguments.insert(
                "generation".to_owned(),
                Value::String(generation.to_string()),
            );
            arguments.insert("token".to_owned(), Value::String(token));
            arguments.insert("epoch".to_owned(), Value::String(epoch));
            arguments.insert("digest".to_owned(), Value::String(digest));
            arguments.insert("request".to_owned(), encoded);
            let admitted = this.admit(operation, "executeStage", arguments).await?;
            match admitted {
                Admitted::Stale => Ok(NativeStagingExecutionResult {
                    state: NativeStagingExecutionState::Stale,
                    failure: None,
                    diagnostic: None,
                }),
                Admitted::Result(Value::Null) => Ok(NativeStagingExecutionResult {
                    state: NativeStagingExecutionState::Completed,
                    failure: None,
                    diagnostic: None,
                }),
                Admitted::Result(result) => wire(g::dec_native_staging_execution_result(&result)),
            }
        })
    }

    fn repository_session_commit_preview(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeCommitRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeCommitPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Commit) {
                return Err(CallError::Unsupported("repository_session_commit_preview"));
            }
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Commit,
                "previewCommit",
                g::enc_native_commit_request(&request),
                g::dec_native_commit_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                request.subject.clone(),
            )
            .await
        })
    }

    fn repository_session_commit_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeCommitExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Commit) {
                return Err(CallError::Unsupported("repository_session_commit_execute"));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Commit,
                    "executeCommit",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeCommitExecutionResult {
                    state: NativeCommitExecutionState::Stale,
                    commit: None,
                    failure_kind: None,
                    exit_code: None,
                    output: Vec::new(),
                    failure: None,
                },
                g::dec_native_commit_execution_result,
            )
        })
    }

    fn repository_session_ref_mutation_preview(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeRefMutationRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeRefMutationPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Refs) {
                return Err(CallError::Unsupported(
                    "repository_session_ref_mutation_preview",
                ));
            }
            let text = [request.name.clone(), request.second_name.clone()]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" \u{2192} ");
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Refs,
                "previewRefs",
                g::enc_native_ref_mutation_request(&request),
                g::dec_native_ref_mutation_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                text,
            )
            .await
        })
    }

    fn repository_session_ref_mutation_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRefMutationExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Refs) {
                return Err(CallError::Unsupported(
                    "repository_session_ref_mutation_execute",
                ));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Refs,
                    "executeRefs",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeRefMutationExecutionResult {
                    state: NativeRefMutationExecutionState::Stale,
                    failure: None,
                },
                g::dec_native_ref_mutation_execution_result,
            )
        })
    }

    fn repository_session_stash_preview(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeStashRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeStashPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Stash) {
                return Err(CallError::Unsupported("repository_session_stash_preview"));
            }
            let text = request
                .message
                .clone()
                .or_else(|| request.selector.clone())
                .unwrap_or_default();
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Stash,
                "previewStash",
                g::enc_native_stash_request(&request),
                g::dec_native_stash_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                text,
            )
            .await
        })
    }

    fn repository_session_stash_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeStashExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Stash) {
                return Err(CallError::Unsupported("repository_session_stash_execute"));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Stash,
                    "executeStash",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeStashExecutionResult {
                    state: NativeStashExecutionState::Stale,
                    failure: None,
                    activity_ids: Vec::new(),
                    stash_created: false,
                    checkout_completed: false,
                    reapply_completed: false,
                    stash_retained: true,
                },
                g::dec_native_stash_execution_result,
            )
        })
    }

    fn repository_session_discard_preview(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeDiscardRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeDiscardPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Discard) {
                return Err(CallError::Unsupported("repository_session_discard_preview"));
            }
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Discard,
                "previewDiscard",
                g::enc_native_discard_request(&request),
                g::dec_native_discard_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                String::new(),
            )
            .await
        })
    }

    fn repository_session_discard_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeDiscardExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Discard) {
                return Err(CallError::Unsupported("repository_session_discard_execute"));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Discard,
                    "executeDiscard",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeDiscardExecutionResult {
                    state: NativeDiscardExecutionState::Stale,
                    failure: None,
                },
                g::dec_native_discard_execution_result,
            )
        })
    }

    fn repository_session_transfer_preview(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeTransferRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeTransferPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Transfer) {
                return Err(CallError::Unsupported(
                    "repository_session_transfer_preview",
                ));
            }
            let text = [request.remote.clone(), request.branch.clone()]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join("/");
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Transfer,
                "previewTransfer",
                g::enc_native_transfer_request(&request),
                g::dec_native_transfer_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                text,
            )
            .await
        })
    }

    /// Runs on the host with its own Git credentials; credentials are never sent.
    fn repository_session_transfer_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeTransferExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Transfer) {
                return Err(CallError::Unsupported(
                    "repository_session_transfer_execute",
                ));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Transfer,
                    "executeTransfer",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeTransferExecutionResult {
                    state: NativeTransferExecutionState::Stale,
                    failure: Some(NativeTransferFailure {
                        kind: NativeTransferFailureKind::Stale,
                    }),
                    diagnosis: None,
                    stash: None,
                    activity_id: None,
                    ahead: 0,
                    behind: 0,
                },
                g::dec_native_transfer_execution_result,
            )
        })
    }

    fn repository_session_history_mutation_preview(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeHistoryMutationRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeHistoryMutationPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported(
                    "repository_session_history_mutation_preview",
                ));
            }
            let text = g::enc_native_history_mutation_kind(&request.kind)
                .as_str()
                .unwrap_or_default()
                .to_owned();
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::History,
                "previewHistory",
                g::enc_native_history_mutation_request(&request),
                g::dec_native_history_mutation_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                text,
            )
            .await
        })
    }

    fn repository_session_history_mutation_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeHistoryMutationExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported(
                    "repository_session_history_mutation_execute",
                ));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::History,
                    "executeHistory",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeHistoryMutationExecutionResult {
                    state: NativeHistoryMutationExecutionState::Stale,
                    failure: None,
                    activity_ids: Vec::new(),
                    conflicting_paths: Vec::new(),
                    sequencer: None,
                    set_aside: None,
                },
                g::dec_native_history_mutation_execution_result,
            )
        })
    }

    fn repository_session_history_mutation_cancel(
        &self,
        _session_id: u64,
        _generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryCommandResult>> {
        let result = self.drop_preview(RemoteWriteFamily::History, token);
        async move { Ok(result) }.boxed_local()
    }

    fn repository_session_rebase_preview(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
        instructions: Vec<NativeRebaseInstruction>,
        acknowledge_published_history: bool,
        apply_autosquash: bool,
    ) -> LocalBoxFuture<'static, CallResult<NativeRebasePreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported("repository_session_rebase_preview"));
            }
            let request = serde_json::json!({
                "planToken": token.to_string(),
                "instructions": instructions.iter().map(g::enc_native_rebase_instruction).collect::<Vec<_>>(),
                "acknowledgePublishedHistory": acknowledge_published_history,
                "applyAutosquash": apply_autosquash,
            });
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Rebase,
                "previewRebase",
                request,
                g::dec_native_rebase_preview_result,
                |preview| preview.token,
                "rebase".to_owned(),
            )
            .await
        })
    }

    fn repository_session_rebase_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRebaseExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported("repository_session_rebase_execute"));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Rebase,
                    "executeRebase",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeRebaseExecutionResult {
                    state: NativeRebaseExecutionState::Stale,
                    failure: None,
                    activity_ids: Vec::new(),
                    conflicting_paths: Vec::new(),
                    running_instruction: None,
                },
                g::dec_native_rebase_execution_result,
            )
        })
    }

    fn repository_session_rebase_cancel(
        &self,
        _session_id: u64,
        _generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryCommandResult>> {
        let result = self.drop_preview(RemoteWriteFamily::Rebase, token);
        async move { Ok(result) }.boxed_local()
    }

    fn repository_session_restack_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
        acknowledge_published_history: bool,
    ) -> LocalBoxFuture<'static, CallResult<NativeRestackExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported("repository_session_restack_execute"));
            }
            let request = serde_json::json!({ "planToken": token.to_string(), "acknowledgePublishedHistory": acknowledge_published_history });
            let admitted = this
                .admit_now(
                    session_id,
                    generation,
                    RemoteWriteFamily::Restack,
                    "Restack",
                    request,
                    "restack",
                    false,
                )
                .await?;
            value(
                admitted,
                || NativeRestackExecutionResult {
                    state: NativeRestackExecutionState::Stale,
                    completed_steps: 0,
                    total_steps: 0,
                    current_branch: None,
                    recovery_refs: Vec::new(),
                    conflicting_paths: Vec::new(),
                    activity_ids: Vec::new(),
                    failure: None,
                },
                g::dec_native_restack_execution_result,
            )
        })
    }

    /// A restack runs on the host and reports its own outcome.
    fn repository_session_restack_cancel(
        &self,
        _session_id: u64,
        _generation: u64,
        _token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryCommandResult>> {
        async {
            Ok(NativeRepositoryCommandResult {
                accepted: false,
                failure: None,
            })
        }
        .boxed_local()
    }

    fn repository_session_bisect_preview(
        &self,
        session_id: u64,
        generation: u64,
        action: NativeBisectAction,
        good: Option<String>,
        bad: Option<String>,
    ) -> LocalBoxFuture<'static, CallResult<NativeBisectPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported("repository_session_bisect_preview"));
            }
            let encoded = g::enc_native_bisect_action(&action);
            let text = encoded.as_str().unwrap_or_default().to_owned();
            let request = serde_json::json!({ "action": encoded, "good": good, "bad": bad });
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Bisect,
                "previewBisect",
                request,
                g::dec_native_bisect_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                text,
            )
            .await
        })
    }

    fn repository_session_bisect_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeBisectExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported("repository_session_bisect_execute"));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Bisect,
                    "executeBisect",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeBisectExecutionResult {
                    state: NativeBisectExecutionState::Stale,
                    bisect: None,
                    activity_id: None,
                    failure: None,
                },
                g::dec_native_bisect_execution_result,
            )
        })
    }

    fn repository_session_bisect_cancel_preview(
        &self,
        _session_id: u64,
        _generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryCommandResult>> {
        let result = self.drop_preview(RemoteWriteFamily::Bisect, token);
        async move { Ok(result) }.boxed_local()
    }

    fn repository_session_named_snapshot_create(
        &self,
        session_id: u64,
        generation: u64,
        name: String,
        include_untracked: bool,
        keep_index: bool,
    ) -> LocalBoxFuture<'static, CallResult<NativeNamedSnapshotExecutionResult>> {
        let text = name.clone();
        self.snapshot(session_id, generation, serde_json::json!({
            "action": "create", "name": name, "includeUntracked": include_untracked, "keepIndex": keep_index,
            "snapshotId": null, "branch": null,
        }), text)
    }

    fn repository_session_named_snapshot_delete(
        &self,
        session_id: u64,
        generation: u64,
        snapshot_id: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeNamedSnapshotExecutionResult>> {
        self.snapshot(
            session_id,
            generation,
            serde_json::json!({
                "action": "delete", "name": null, "includeUntracked": false, "keepIndex": false,
                "snapshotId": snapshot_id.to_string(), "branch": null,
            }),
            "delete".to_owned(),
        )
    }

    fn repository_session_named_snapshot_branch(
        &self,
        session_id: u64,
        generation: u64,
        snapshot_id: u64,
        branch: Vec<u8>,
    ) -> LocalBoxFuture<'static, CallResult<NativeNamedSnapshotExecutionResult>> {
        let text = String::from_utf8_lossy(&branch).into_owned();
        self.snapshot(
            session_id,
            generation,
            serde_json::json!({
                "action": "branch", "name": null, "includeUntracked": false, "keepIndex": false,
                "snapshotId": snapshot_id.to_string(), "branch": w::bytes_e(&branch),
            }),
            text,
        )
    }

    fn repository_session_named_snapshot_restore_preview(
        &self,
        session_id: u64,
        generation: u64,
        snapshot_id: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeNamedSnapshotRestorePreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported(
                    "repository_session_named_snapshot_restore_preview",
                ));
            }
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::SnapshotRestore,
                "previewSnapshotRestore",
                serde_json::json!({ "snapshotId": snapshot_id.to_string() }),
                g::dec_native_named_snapshot_restore_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                "restore".to_owned(),
            )
            .await
        })
    }

    fn repository_session_named_snapshot_restore_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeNamedSnapshotExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported(
                    "repository_session_named_snapshot_restore_execute",
                ));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::SnapshotRestore,
                    "executeSnapshotRestore",
                    token,
                )
                .await?;
            value(
                admitted,
                stale_snapshot,
                g::dec_native_named_snapshot_execution_result,
            )
        })
    }

    fn repository_session_named_snapshot_restore_cancel(
        &self,
        _session_id: u64,
        _generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRepositoryCommandResult>> {
        let result = self.drop_preview(RemoteWriteFamily::SnapshotRestore, token);
        async move { Ok(result) }.boxed_local()
    }

    fn repository_session_restore_preview(
        &self,
        session_id: u64,
        generation: u64,
        commit: String,
        path: Vec<u8>,
        byte_limit: u32,
    ) -> LocalBoxFuture<'static, CallResult<NativeRestorePreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported("repository_session_restore_preview"));
            }
            let text = String::from_utf8_lossy(&path).into_owned();
            this.preview_write(
                session_id, generation, RemoteWriteFamily::Restore, "previewRestore",
                serde_json::json!({ "commit": commit, "path": w::bytes_e(&path), "byteLimit": byte_limit }),
                g::dec_native_restore_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token), text,
            ).await
        })
    }

    fn repository_session_restore_file(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeRestoreResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported("repository_session_restore_file"));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Restore,
                    "executeRestore",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativeRestoreResult {
                    state: NativeRestoreState::Stale,
                    failure: None,
                },
                g::dec_native_restore_result,
            )
        })
    }

    fn repository_session_remove_index_lock(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeIndexLockRemovalResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported(
                    "repository_session_remove_index_lock",
                ));
            }
            let admitted = this
                .admit_now(
                    session_id,
                    generation,
                    RemoteWriteFamily::IndexLock,
                    "IndexLock",
                    serde_json::json!({ "token": token.to_string() }),
                    "index.lock",
                    false,
                )
                .await?;
            value(
                admitted,
                || NativeIndexLockRemovalResult {
                    removed: false,
                    failure: Some(NativeIndexLockFailureKind::InvalidToken),
                },
                g::dec_native_index_lock_removal_result,
            )
        })
    }

    /// Refs on a host are repaired there; a fetch without pruning still works.
    fn repository_session_delete_tracking_refs(
        &self,
        _session_id: u64,
        _generation: u64,
        _references: Vec<String>,
    ) -> LocalBoxFuture<'static, CallResult<NativeTransferExecutionResult>> {
        async {
            Err(CallError::Unsupported(
                "repository_session_delete_tracking_refs",
            ))
        }
        .boxed_local()
    }

    /// Lock files on a host are removed there; this computer only lists them.
    fn repository_session_remove_lock(
        &self,
        _session_id: u64,
        _generation: u64,
        _token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativeIndexLockRemovalResult>> {
        async { Err(CallError::Unsupported("repository_session_remove_lock")) }.boxed_local()
    }

    fn repository_session_conflict_choose_side(
        &self,
        session_id: u64,
        generation: u64,
        path: Vec<u8>,
        expected_fingerprint: u64,
        choice: NativeConflictSideChoice,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictSnapshotResult>> {
        self.conflict(session_id, generation, path, serde_json::json!({
            "action": "chooseSide", "expectedFingerprint": expected_fingerprint.to_string(),
            "side": g::enc_native_conflict_side_choice(&choice), "regionIndex": null, "region": null, "result": null,
        }))
    }

    fn repository_session_conflict_take_region(
        &self,
        session_id: u64,
        generation: u64,
        path: Vec<u8>,
        expected_fingerprint: u64,
        region_index: u32,
        choice: NativeConflictRegionChoice,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictSnapshotResult>> {
        self.conflict(session_id, generation, path, serde_json::json!({
            "action": "takeRegion", "expectedFingerprint": expected_fingerprint.to_string(), "side": null,
            "regionIndex": region_index, "region": g::enc_native_conflict_region_choice(&choice), "result": null,
        }))
    }

    fn repository_session_conflict_save_result(
        &self,
        session_id: u64,
        generation: u64,
        path: Vec<u8>,
        expected_fingerprint: u64,
        result: Vec<u8>,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictSnapshotResult>> {
        self.conflict(session_id, generation, path, serde_json::json!({
            "action": "saveResult", "expectedFingerprint": expected_fingerprint.to_string(), "side": null,
            "regionIndex": null, "region": null, "result": w::bytes_e(&result),
        }))
    }

    fn repository_session_conflict_undo_resolution(
        &self,
        session_id: u64,
        generation: u64,
        path: Vec<u8>,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictSnapshotResult>> {
        self.conflict(session_id, generation, path, serde_json::json!({
            "action": "undoResolution", "expectedFingerprint": null, "side": null, "regionIndex": null, "region": null, "result": null,
        }))
    }

    fn repository_session_conflict_continue(
        &self,
        session_id: u64,
        generation: u64,
        action: NativeConflictSequencerAction,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictContinuationResult>> {
        self.sequencer(session_id, generation, action, None)
    }

    fn repository_session_conflict_continue_with_message(
        &self,
        session_id: u64,
        generation: u64,
        action: NativeConflictSequencerAction,
        message: String,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictContinuationResult>> {
        self.sequencer(session_id, generation, action, Some(message))
    }

    /// Reads the patch on this computer and hands its bytes to the host.
    fn repository_session_patch_apply_preview(
        &self,
        session_id: u64,
        generation: u64,
        patch_path: String,
    ) -> LocalBoxFuture<'static, CallResult<NativePatchApplyPreviewResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported(
                    "repository_session_patch_apply_preview",
                ));
            }
            let invalid = NativePatchApplyPreviewResult {
                preview: None,
                failure: Some(NativeRepositoryFailure {
                    kind: NativeRepositoryFailureKind::InvalidOptions,
                }),
            };
            let path = std::path::PathBuf::from(&patch_path);
            if !path.is_absolute() {
                return Ok(invalid);
            }
            let read = crate::rt::blocking(move || -> std::io::Result<Option<Vec<u8>>> {
                let length = std::fs::metadata(&path)?.len();
                if length == 0 || length > contract::PATCH_BYTES as u64 {
                    return Ok(None);
                }
                std::fs::read(&path).map(Some)
            })
            .await;
            let content = match read {
                Ok(Some(content))
                    if !content.is_empty() && content.len() <= contract::PATCH_BYTES =>
                {
                    content
                }
                Ok(_) => return Ok(invalid),
                Err(_) => {
                    return Ok(NativePatchApplyPreviewResult {
                        preview: None,
                        failure: Some(NativeRepositoryFailure {
                            kind: NativeRepositoryFailureKind::Read,
                        }),
                    });
                }
            };
            let text = std::path::Path::new(&patch_path).file_name().map_or_else(
                || "patch".to_owned(),
                |name| name.to_string_lossy().into_owned(),
            );
            this.preview_write(
                session_id,
                generation,
                RemoteWriteFamily::Patch,
                "previewPatch",
                serde_json::json!({ "content": w::bytes_e(&content) }),
                g::dec_native_patch_apply_preview_result,
                |preview| preview.preview.as_ref().map(|preview| preview.token),
                text,
            )
            .await
        })
    }

    fn repository_session_patch_apply_execute(
        &self,
        session_id: u64,
        generation: u64,
        token: u64,
    ) -> LocalBoxFuture<'static, CallResult<NativePatchApplyExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported(
                    "repository_session_patch_apply_execute",
                ));
            }
            let admitted = this
                .execute_write(
                    session_id,
                    generation,
                    RemoteWriteFamily::Patch,
                    "executePatch",
                    token,
                )
                .await?;
            value(
                admitted,
                || NativePatchApplyExecutionResult {
                    state: NativePatchApplyExecutionState::Stale,
                    failure: None,
                },
                g::dec_native_patch_apply_execution_result,
            )
        })
    }

    /// Worktree roots name paths on the host: their remote authority is not sent.
    fn repository_session_extension_execute(
        &self,
        session_id: u64,
        generation: u64,
        request: NativeExtensionMutationRequest,
    ) -> LocalBoxFuture<'static, CallResult<NativeExtensionMutationResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Extensions) {
                return Err(CallError::Unsupported(
                    "repository_session_extension_execute",
                ));
            }
            let text = g::enc_native_extension_mutation_kind(&request.kind)
                .as_str()
                .unwrap_or_default()
                .to_owned();
            let request = NativeExtensionMutationRequest {
                worktree_root: request.worktree_root.map(|root| NativePathIdentity {
                    remote: None,
                    ..root
                }),
                ..request
            };
            let admitted = this
                .admit_now(
                    session_id,
                    generation,
                    RemoteWriteFamily::Extension,
                    "Extension",
                    g::enc_native_extension_mutation_request(&request),
                    &text,
                    true,
                )
                .await?;
            value(
                admitted,
                || NativeExtensionMutationResult {
                    state: NativeExtensionMutationState::Failed,
                    activity_ids: Vec::new(),
                    failure: None,
                },
                g::dec_native_extension_mutation_result,
            )
        })
    }
}

fn stale_snapshot() -> NativeNamedSnapshotExecutionResult {
    NativeNamedSnapshotExecutionResult {
        state: NativeNamedSnapshotExecutionState::Stale,
        snapshot: None,
        recovery_ref: None,
        conflicting_paths: Vec::new(),
        activity_ids: Vec::new(),
        failure: None,
    }
}

impl RemoteSessions {
    fn snapshot(
        &self,
        session_id: u64,
        generation: u64,
        request: Value,
        text: String,
    ) -> LocalBoxFuture<'static, CallResult<NativeNamedSnapshotExecutionResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::Recovery) {
                return Err(CallError::Unsupported("repository_session_named_snapshot"));
            }
            let admitted = this
                .admit_now(
                    session_id,
                    generation,
                    RemoteWriteFamily::Snapshot,
                    "Snapshot",
                    request,
                    &text,
                    true,
                )
                .await?;
            value(
                admitted,
                stale_snapshot,
                g::dec_native_named_snapshot_execution_result,
            )
        })
    }

    fn conflict(
        &self,
        session_id: u64,
        generation: u64,
        path: Vec<u8>,
        mut request: Value,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictSnapshotResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported("repository_session_conflict"));
            }
            request["path"] = w::bytes_e(&path);
            let text = String::from_utf8_lossy(&path).into_owned();
            let admitted = this
                .admit_now(
                    session_id,
                    generation,
                    RemoteWriteFamily::Conflict,
                    "Conflict",
                    request,
                    &text,
                    true,
                )
                .await?;
            value(
                admitted,
                || NativeConflictSnapshotResult {
                    snapshot: None,
                    activity_ids: Vec::new(),
                    failure: None,
                },
                g::dec_native_conflict_snapshot_result,
            )
        })
    }

    fn sequencer(
        &self,
        session_id: u64,
        generation: u64,
        action: NativeConflictSequencerAction,
        message: Option<String>,
    ) -> LocalBoxFuture<'static, CallResult<NativeConflictContinuationResult>> {
        let this = self;
        boxed!(this, {
            if !this.can(RemoteCapability::History) {
                return Err(CallError::Unsupported(
                    "repository_session_conflict_continue",
                ));
            }
            let encoded = g::enc_native_conflict_sequencer_action(&action);
            let text = message
                .clone()
                .unwrap_or_else(|| encoded.as_str().unwrap_or_default().to_owned());
            let request = serde_json::json!({ "action": encoded, "message": message });
            let admitted = this
                .admit_now(
                    session_id,
                    generation,
                    RemoteWriteFamily::Sequencer,
                    "Sequencer",
                    request,
                    &text,
                    true,
                )
                .await?;
            value(
                admitted,
                || NativeConflictContinuationResult {
                    state: NativeConflictContinuationState::Failed,
                    activity_ids: Vec::new(),
                    failure: None,
                },
                g::dec_native_conflict_continuation_result,
            )
        })
    }
}
