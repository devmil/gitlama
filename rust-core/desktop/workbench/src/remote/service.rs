//! Host profiles, remote connections and the record of remote writes (the Dart
//! `RemoteWorkspaceService` and `RemoteSessionDirectory`).
//!
//! Nothing connects at startup except the hosts of restored tabs. A helper reporting another
//! store or account than its profile verified is never attached silently; the user rebinds,
//! which also withdraws write permission.

use super::calls::{Ledger, RemoteSessions};
use super::channel::{Cancel, Channel};
use super::connector::Connector;
use super::model::{
    self, ConnectionState, DirectoryPage, Failure, HelperArtifact, HelperTarget, Phase, WriteBlock,
};
use super::reconnect::Reconnector;
use crate::backend::{CallRouter, SessionCalls};
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::settings::SettingsService;
use crate::workspace::{WorkspaceRemotes, WorkspaceService};
use futures::future::{FutureExt, LocalBoxFuture, Shared};
use gitlama_application::wire::contract::{self, RemoteCapability};
use gitlama_contract::domain::path_identity::{NativePathIdentity, NativeRemoteAuthority};
use gitlama_contract::dto::NativeRepositoryFailureKind;
use gitlama_contract::remote_pending::{
    NativeRemotePendingLoadState, NativeRemotePendingOperation,
};
use gitlama_contract::storage::{NativeRemoteHostProfile, NativeRemoteVerifiedIdentity};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::Duration;

/// Remote sessions use identifiers from here up, disjoint from local ones.
pub const REMOTE_SESSION_BASE: u64 = 1 << 62;
/// How long application shutdown waits for remote connections to close.
pub const SHUTDOWN_DEADLINE: Duration = Duration::from_secs(5);

struct Connection {
    channel: Rc<Channel>,
    sessions: Rc<RemoteSessions>,
    calls: Rc<dyn SessionCalls>,
    authority: NativeRemoteAuthority,
    closing: Cell<bool>,
    /// The helper's operations as last read, and when.
    operations: RefCell<
        Option<(
            gitlama_contract::dto::NativeOperationCenterSnapshot,
            std::time::Instant,
        )>,
    >,
}

/// How long a quiet connection answers from its last read of the helper's operations.
const OPERATIONS_QUIET: Duration = Duration::from_secs(3);
/// How long after a write the helper is asked on every poll.
const OPERATIONS_AFTER_WRITE_MS: u64 = 10_000;

type Attempt = Shared<LocalBoxFuture<'static, Result<ConnectionState, Failure>>>;

/// Why a profile change could not be saved.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProfileError {
    Invalid,
    Capacity,
    /// The settings store refused the change.
    Save(crate::settings::SettingsError),
}

pub struct RemoteService {
    settings: Rc<SettingsService>,
    connector: Connector,
    notifier: Notifier,
    workspace: RefCell<Weak<WorkspaceService>>,
    reconnector: RefCell<Option<Rc<Reconnector>>>,
    live: RefCell<HashMap<String, Rc<Connection>>>,
    /// Closed connections whose sessions tabs still hold: their events drain from what
    /// arrived, and every other call fails as disconnected, until the tabs reopen.
    retired: RefCell<Vec<Rc<Connection>>>,
    attempts: RefCell<HashMap<String, Attempt>>,
    cancels: RefCell<HashMap<String, Rc<Cancel>>>,
    states: RefCell<HashMap<String, ConnectionState>>,
    writes_requested: RefCell<HashMap<String, bool>>,
    host_targets: RefCell<HashMap<String, HelperTarget>>,
    observed: RefCell<HashMap<String, NativeRemoteVerifiedIdentity>>,
    bindings: RefCell<HashMap<String, String>>,
    operations: RefCell<Vec<NativeRemotePendingOperation>>,
    ledger_usable: Cell<bool>,
    ledger_directory: Option<String>,
    next_session: Cell<u64>,
    /// Hosts that connected again after a loss, for the window to announce.
    reconnected: RefCell<Vec<String>>,
    disposed: Cell<bool>,
    this: Weak<RemoteService>,
}

fn binding_key(authority: &NativeRemoteAuthority, path: &[u8]) -> String {
    format!(
        "{}/{}/{}/{}",
        authority.profile_id,
        authority.store_id,
        authority.account_uid,
        path.iter().map(u8::to_string).collect::<Vec<_>>().join(",")
    )
}

impl RemoteService {
    /// Loads the record of remote writes. An unreadable record is kept, and writes stay
    /// unavailable until it can be read.
    pub async fn new(settings: Rc<SettingsService>, notifier: Notifier) -> Rc<Self> {
        let directory = rt::blocking(gitlama_core::api::remote_pending_default_directory).await;
        let (usable, operations) = match directory.clone() {
            None => (false, Vec::new()),
            Some(directory) => {
                let loaded =
                    rt::blocking(move || gitlama_core::api::remote_pending_load(directory)).await;
                match loaded.state {
                    NativeRemotePendingLoadState::Absent | NativeRemotePendingLoadState::Loaded => {
                        (true, loaded.operations)
                    }
                    _ => (false, Vec::new()),
                }
            }
        };
        Rc::new_cyclic(|this| Self {
            settings,
            connector: Connector::new(),
            notifier,
            workspace: RefCell::new(Weak::new()),
            reconnector: RefCell::new(None),
            live: RefCell::new(HashMap::new()),
            retired: RefCell::new(Vec::new()),
            attempts: RefCell::new(HashMap::new()),
            cancels: RefCell::new(HashMap::new()),
            states: RefCell::new(HashMap::new()),
            writes_requested: RefCell::new(HashMap::new()),
            host_targets: RefCell::new(HashMap::new()),
            observed: RefCell::new(HashMap::new()),
            bindings: RefCell::new(HashMap::new()),
            operations: RefCell::new(operations),
            ledger_usable: Cell::new(usable),
            ledger_directory: directory,
            next_session: Cell::new(REMOTE_SESSION_BASE),
            reconnected: RefCell::new(Vec::new()),
            disposed: Cell::new(false),
            this: this.clone(),
        })
    }

    fn rc(&self) -> Rc<Self> {
        self.this.upgrade().expect("remote service alive")
    }

    /// Attaches the workspace whose tabs the connections serve, and its reconnector.
    pub fn attach(&self, workspace: &Rc<WorkspaceService>) {
        *self.workspace.borrow_mut() = Rc::downgrade(workspace);
        let reconnect_workspace = Rc::downgrade(workspace);
        let wanted_workspace = Rc::downgrade(workspace);
        let notifier = self.notifier.clone();
        let announced = self.this.clone();
        let reconnector = Reconnector::new(
            Box::new(move |profile: String| {
                let workspace = reconnect_workspace.clone();
                async move {
                    let Some(workspace) = workspace.upgrade() else {
                        return Err(Failure::Canceled);
                    };
                    workspace.reconnect_remote(&profile).await
                }
                .boxed_local()
            }),
            Box::new(move |profile: &str| {
                wanted_workspace
                    .upgrade()
                    .is_some_and(|workspace| workspace.wants_remote(profile))
            }),
            Box::new(move |_profile: &str| notifier.notify(Topics::REMOTE)),
            Box::new(move |profile: &str| {
                if let Some(service) = announced.upgrade() {
                    service.reconnected.borrow_mut().push(profile.to_owned());
                    service.notifier.notify(Topics::REMOTE);
                }
            }),
        );
        *self.reconnector.borrow_mut() = Some(reconnector);
    }

    #[must_use]
    pub fn reconnector(&self) -> Option<Rc<Reconnector>> {
        self.reconnector.borrow().clone()
    }

    /// Hosts that connected again since the last call, for an announcement.
    pub fn take_reconnected(&self) -> Vec<String> {
        std::mem::take(&mut *self.reconnected.borrow_mut())
    }

    /// Restored remote tabs connect their hosts on their own.
    pub fn connect_restored_tabs(&self) {
        let Some(workspace) = self.workspace.borrow().upgrade() else {
            return;
        };
        let Some(reconnector) = self.reconnector() else {
            return;
        };
        for profile in workspace.stale_remote_profiles() {
            reconnector.connect_soon(&profile);
        }
    }

    // Profiles -------------------------------------------------------------------

    #[must_use]
    pub fn profiles(&self) -> Vec<NativeRemoteHostProfile> {
        self.settings
            .with(|document| document.remote_profiles.clone())
    }

    #[must_use]
    pub fn profile(&self, id: &str) -> Option<NativeRemoteHostProfile> {
        self.settings.with(|document| {
            document
                .remote_profiles
                .iter()
                .find(|profile| profile.id == id)
                .cloned()
        })
    }

    #[must_use]
    pub fn state(&self, profile_id: &str) -> ConnectionState {
        self.states
            .borrow()
            .get(profile_id)
            .cloned()
            .unwrap_or_else(|| ConnectionState::new(profile_id, Phase::Idle))
    }

    fn publish(&self, state: ConnectionState) {
        let profile = state.profile_id.clone();
        let phase = state.phase;
        let failure = state.failure;
        self.states.borrow_mut().insert(profile.clone(), state);
        self.notifier.notify(Topics::REMOTE | Topics::WORKSPACE);
        let workspace = self.workspace.borrow().upgrade();
        let reconnector = self.reconnector();
        match phase {
            Phase::Disconnected => {
                if let Some(reconnector) = reconnector {
                    reconnector.lost(&profile, failure);
                }
            }
            Phase::Ready => {
                // Connected by the user, from any dialog: stale tabs reopen on it.
                if let Some(reconnector) = reconnector {
                    reconnector.settled(&profile);
                }
                if let Some(workspace) = &workspace {
                    workspace.remote_connection_ready(&profile);
                }
            }
            Phase::Idle => {
                // Closed on purpose.
                if let Some(reconnector) = reconnector {
                    reconnector.settled(&profile);
                }
            }
            _ => {}
        }
        if let Some(workspace) = workspace {
            workspace.remote_state_changed();
        }
    }

    /// Why the live connection of `profile_id` grants no writes; `None` when it asked for
    /// them, so a missing capability is the host's decision.
    #[must_use]
    pub fn write_block(&self, profile_id: &str) -> Option<WriteBlock> {
        if !self
            .profile(profile_id)
            .is_some_and(|profile| profile.writes_allowed)
        {
            return Some(WriteBlock::NotAllowed);
        }
        if !self.ledger_usable.get() {
            return Some(WriteBlock::LedgerUnavailable);
        }
        if self.writes_requested.borrow().get(profile_id) != Some(&true) {
            return Some(WriteBlock::Reconnect);
        }
        None
    }

    /// The identity a helper reported that did not match its profile.
    #[must_use]
    pub fn observed_identity(&self, profile_id: &str) -> Option<NativeRemoteVerifiedIdentity> {
        self.observed.borrow().get(profile_id).cloned()
    }

    async fn save_profiles(
        &self,
        profiles: Vec<NativeRemoteHostProfile>,
    ) -> Result<(), ProfileError> {
        // A rejected save restores only the profiles, not settings others changed meanwhile.
        self.settings
            .update_durable(
                move |document| document.remote_profiles = profiles,
                |current, previous| current.remote_profiles = previous.remote_profiles.clone(),
            )
            .await
            .map_err(|error| {
                super::note(
                    crate::diagnostics::Level::Warning,
                    "remote_profiles_save_failed",
                    &[("failure_code", error.code().as_str().into())],
                );
                ProfileError::Save(error)
            })
    }

    fn replace_profile(&self, saved: &NativeRemoteHostProfile) -> Vec<NativeRemoteHostProfile> {
        let mut profiles: Vec<NativeRemoteHostProfile> = self
            .profiles()
            .into_iter()
            .filter(|profile| profile.id != saved.id)
            .collect();
        profiles.push(saved.clone());
        profiles
    }

    /// Creates or edits a profile with the colour and icon its tabs show. Changing the alias
    /// withdraws its verified identity and write permission: it may reach another computer.
    pub async fn save_profile(
        &self,
        id: Option<&str>,
        label: &str,
        alias: &str,
        color: Option<String>,
        icon: Option<String>,
    ) -> Result<NativeRemoteHostProfile, ProfileError> {
        if !model::is_valid_label(label) || !model::is_valid_alias(alias) {
            return Err(ProfileError::Invalid);
        }
        let existing = id.and_then(|id| self.profile(id));
        if id.is_some() && existing.is_none() {
            return Err(ProfileError::Invalid);
        }
        if existing.is_none() && self.profiles().len() >= model::PROFILE_CAPACITY {
            return Err(ProfileError::Capacity);
        }
        let saved = match existing {
            None => NativeRemoteHostProfile {
                id: model::new_uuid(),
                label: label.to_owned(),
                alias: alias.to_owned(),
                verified: None,
                writes_allowed: false,
                auto_install_helper: false,
                color,
                icon,
            },
            Some(existing) if existing.alias != alias => {
                self.disconnect(&existing.id).await;
                self.observed.borrow_mut().remove(&existing.id);
                NativeRemoteHostProfile {
                    label: label.to_owned(),
                    alias: alias.to_owned(),
                    verified: None,
                    writes_allowed: false,
                    auto_install_helper: false,
                    color,
                    icon,
                    ..existing
                }
            }
            Some(existing) => NativeRemoteHostProfile {
                label: label.to_owned(),
                color,
                icon,
                ..existing
            },
        };
        self.save_profiles(self.replace_profile(&saved)).await?;
        self.notifier.notify(Topics::REMOTE);
        Ok(saved)
    }

    /// Removes a profile's local record. Remote files, open tabs, drafts and recorded
    /// operations are kept; they stay bound to the old authority.
    pub async fn delete_profile(&self, id: &str) -> Result<(), ProfileError> {
        self.disconnect(id).await;
        self.observed.borrow_mut().remove(id);
        let profiles = self
            .profiles()
            .into_iter()
            .filter(|profile| profile.id != id)
            .collect();
        self.save_profiles(profiles).await?;
        self.states.borrow_mut().remove(id);
        self.notifier.notify(Topics::REMOTE);
        Ok(())
    }

    /// Allows or withdraws changes on a host. A live connection keeps what it negotiated
    /// until it reconnects.
    pub async fn set_writes_allowed(&self, id: &str, allowed: bool) -> Result<(), ProfileError> {
        let existing = self.profile(id).ok_or(ProfileError::Invalid)?;
        self.save_profiles(self.replace_profile(&NativeRemoteHostProfile {
            writes_allowed: allowed,
            ..existing
        }))
        .await?;
        self.notifier.notify(Topics::REMOTE);
        Ok(())
    }

    /// Lets GitLama install its helper on the host without asking, or asks again.
    pub async fn set_auto_install_helper(
        &self,
        id: &str,
        enabled: bool,
    ) -> Result<(), ProfileError> {
        let existing = self.profile(id).ok_or(ProfileError::Invalid)?;
        if existing.auto_install_helper == enabled {
            return Ok(());
        }
        self.save_profiles(self.replace_profile(&NativeRemoteHostProfile {
            auto_install_helper: enabled,
            ..existing
        }))
        .await?;
        self.notifier.notify(Topics::REMOTE);
        Ok(())
    }

    // Helpers --------------------------------------------------------------------

    /// The compatibility version of the helper this application needs.
    #[must_use]
    pub fn helper_version(&self) -> Option<u64> {
        self.connector.build_id().and_then(|id| id.parse().ok())
    }

    #[must_use]
    pub fn helper_build_id(&self) -> Option<String> {
        self.connector.build_id().map(str::to_owned)
    }

    /// The platform a host reported when its helper was missing.
    #[must_use]
    pub fn host_target(&self, profile_id: &str) -> Option<HelperTarget> {
        self.host_targets.borrow().get(profile_id).copied()
    }

    /// The helper this application can install on `profile_id`'s host.
    pub async fn installable_helper(&self, profile_id: &str) -> Option<HelperArtifact> {
        let target = self.host_target(profile_id)?;
        self.connector.bundled_helper(target).await
    }

    pub async fn bundled_helper(&self, target: HelperTarget) -> Option<HelperArtifact> {
        self.connector.bundled_helper(target).await
    }

    // Connections ----------------------------------------------------------------

    fn ensure_active(&self) -> Result<(), Failure> {
        if self.disposed.get() {
            Err(Failure::Canceled)
        } else {
            Ok(())
        }
    }

    fn live_connection(&self, profile_id: &str) -> Option<Rc<Connection>> {
        self.live
            .borrow()
            .get(profile_id)
            .filter(|connection| !connection.closing.get())
            .cloned()
    }

    fn shared_attempt(
        &self,
        profile_id: &str,
        start: impl FnOnce() -> LocalBoxFuture<'static, Result<ConnectionState, Failure>>,
    ) -> LocalBoxFuture<'static, Result<ConnectionState, Failure>> {
        if let Some(existing) = self.attempts.borrow().get(profile_id).cloned() {
            return existing.boxed_local();
        }
        let this = self.rc();
        let profile = profile_id.to_owned();
        let started = start();
        let attempt: Attempt = async move {
            let result = started.await;
            this.attempts.borrow_mut().remove(&profile);
            this.cancels.borrow_mut().remove(&profile);
            result
        }
        .boxed_local()
        .shared();
        self.attempts
            .borrow_mut()
            .insert(profile_id.to_owned(), attempt.clone());
        attempt.boxed_local()
    }

    /// Connects a profile. Concurrent requests share one attempt.
    pub fn connect(
        &self,
        profile_id: &str,
    ) -> LocalBoxFuture<'static, Result<ConnectionState, Failure>> {
        if let Err(failure) = self.ensure_active() {
            return async move { Err(failure) }.boxed_local();
        }
        if self.live_connection(profile_id).is_some() {
            let state = self.state(profile_id);
            return async move { Ok(state) }.boxed_local();
        }
        let this = self.rc();
        let profile = profile_id.to_owned();
        self.shared_attempt(profile_id, move || {
            async move { this.connect_once(&profile, None, true).await }.boxed_local()
        })
    }

    /// Installs `artifact` on the host after the user confirmed it, then connects. Shares
    /// the attempt slot with [`Self::connect`]; [`Self::cancel`] stops either step.
    pub fn install_helper(
        &self,
        profile_id: &str,
        artifact: HelperArtifact,
    ) -> LocalBoxFuture<'static, Result<ConnectionState, Failure>> {
        if let Err(failure) = self.ensure_active() {
            return async move { Err(failure) }.boxed_local();
        }
        if self.live_connection(profile_id).is_some() {
            let state = self.state(profile_id);
            return async move { Ok(state) }.boxed_local();
        }
        let this = self.rc();
        let profile = profile_id.to_owned();
        self.shared_attempt(profile_id, move || {
            async move { this.install(&profile, artifact, None).await }.boxed_local()
        })
    }

    /// Cancels a connection attempt in progress.
    pub fn cancel(&self, profile_id: &str) {
        let cancel = self.cancels.borrow().get(profile_id).cloned();
        if let Some(cancel) = cancel {
            cancel.cancel();
        }
    }

    fn cancel_for(&self, profile_id: &str, cancel: Option<Rc<Cancel>>) -> Rc<Cancel> {
        let cancel = cancel.unwrap_or_default();
        self.cancels
            .borrow_mut()
            .insert(profile_id.to_owned(), Rc::clone(&cancel));
        cancel
    }

    fn settle(&self, profile_id: &str, failure: Failure) -> ConnectionState {
        let state = if failure == Failure::Canceled {
            ConnectionState::new(profile_id, Phase::Idle)
        } else {
            ConnectionState::failed(profile_id, Phase::Failed, failure)
        };
        self.publish(state.clone());
        state
    }

    async fn install(
        &self,
        profile_id: &str,
        artifact: HelperArtifact,
        cancel: Option<Rc<Cancel>>,
    ) -> Result<ConnectionState, Failure> {
        let selected = self.profile(profile_id).ok_or(Failure::Unsupported)?;
        let cancel = self.cancel_for(profile_id, cancel);
        self.publish(ConnectionState::new(profile_id, Phase::Installing));
        if let Err(failure) = self
            .connector
            .install_helper(&selected.alias, &artifact, Rc::clone(&cancel))
            .await
        {
            return Ok(self.settle(profile_id, failure));
        }
        if cancel.is_canceled() || self.disposed.get() {
            let idle = ConnectionState::new(profile_id, Phase::Idle);
            self.publish(idle.clone());
            return Ok(idle);
        }
        // Never installs twice in one attempt: a helper still missing is a failure to show.
        Box::pin(self.connect_once(profile_id, Some(cancel), false)).await
    }

    async fn connect_once(
        &self,
        profile_id: &str,
        cancel: Option<Rc<Cancel>>,
        auto_install: bool,
    ) -> Result<ConnectionState, Failure> {
        let selected = self.profile(profile_id).ok_or(Failure::Unsupported)?;
        let cancel = self.cancel_for(profile_id, cancel);
        self.publish(ConnectionState::new(profile_id, Phase::Connecting));
        let writes = selected.writes_allowed && self.ledger_usable.get();
        self.writes_requested
            .borrow_mut()
            .insert(profile_id.to_owned(), writes);
        let mut requested: HashSet<RemoteCapability> =
            [RemoteCapability::Read, RemoteCapability::ListDirectory]
                .into_iter()
                .collect();
        if writes {
            requested.extend(RemoteCapability::WRITES);
        }
        let this = self.rc();
        let phase_profile = profile_id.to_owned();
        let on_phase = move |phase: Phase| {
            if phase != Phase::Connecting {
                this.publish(ConnectionState::new(&phase_profile, phase));
            }
        };
        let channel = match self
            .connector
            .open(&selected.alias, requested, Rc::clone(&cancel), &on_phase)
            .await
        {
            Ok(channel) => channel,
            Err(error) => {
                if let Some(target) = error.host_target {
                    self.host_targets
                        .borrow_mut()
                        .insert(profile_id.to_owned(), target);
                }
                // A host the user lets GitLama look after receives this version's helper
                // within the same attempt.
                if auto_install
                    && error.code == Failure::HelperNotInstalled
                    && !cancel.is_canceled()
                    && !self.disposed.get()
                    && self
                        .profile(profile_id)
                        .is_some_and(|profile| profile.auto_install_helper)
                    && let Some(artifact) = self.installable_helper(profile_id).await
                    && !cancel.is_canceled()
                {
                    super::note(
                        crate::diagnostics::Level::Info,
                        "remote_helper_auto_install",
                        &[],
                    );
                    return Box::pin(self.install(profile_id, artifact, Some(cancel))).await;
                }
                return Ok(self.settle(profile_id, error.code));
            }
        };
        let helper = channel.helper();
        let reported = model::identity_of(&helper);
        let current = self.profile(profile_id);
        let Some(mut current) =
            current.filter(|current| !self.disposed.get() && current.alias == selected.alias)
        else {
            channel.close().await;
            return Err(Failure::Canceled);
        };
        if let Some(verified) = &current.verified
            && (verified.store_id != reported.store_id
                || verified.account_uid != reported.account_uid)
        {
            self.observed
                .borrow_mut()
                .insert(profile_id.to_owned(), reported);
            channel.close().await;
            let changed = ConnectionState::failed(
                profile_id,
                Phase::IdentityChanged,
                Failure::IdentityChanged,
            );
            self.publish(changed.clone());
            return Ok(changed);
        }
        if current
            .verified
            .as_ref()
            .is_none_or(|verified| verified.account_name != reported.account_name)
        {
            // The first explicit connection of a profile verifies its identity.
            current.verified = Some(reported);
            if self
                .save_profiles(self.replace_profile(&current))
                .await
                .is_err()
            {
                channel.close().await;
                return Ok(self.settle(profile_id, Failure::Internal));
            }
        }
        let authority = model::authority_of(&current).expect("verified above");
        let ledger: Rc<dyn Ledger> = self.rc();
        let allocate_service = self.this.clone();
        let expected_service = self.this.clone();
        let remember_service = self.this.clone();
        let expected_authority = authority.clone();
        let remember_authority = authority.clone();
        let sessions = RemoteSessions::new(
            Rc::clone(&channel),
            authority.clone(),
            ledger,
            Rc::new(move || {
                allocate_service
                    .upgrade()
                    .map_or(REMOTE_SESSION_BASE, |service| {
                        let next = service.next_session.get() + 1;
                        service.next_session.set(next);
                        next
                    })
            }),
            Rc::new(move |path: &[u8]| {
                expected_service.upgrade().and_then(|service| {
                    service
                        .bindings
                        .borrow()
                        .get(&binding_key(&expected_authority, path))
                        .cloned()
                })
            }),
            Rc::new(move |path: &[u8], binding: &str| {
                if let Some(service) = remember_service.upgrade() {
                    service
                        .bindings
                        .borrow_mut()
                        .insert(binding_key(&remember_authority, path), binding.to_owned());
                }
            }),
        );
        let connection = Rc::new(Connection {
            calls: sessions.calls(),
            channel: Rc::clone(&channel),
            sessions,
            authority,
            closing: Cell::new(false),
            operations: RefCell::new(None),
        });
        self.live
            .borrow_mut()
            .insert(profile_id.to_owned(), Rc::clone(&connection));
        self.observed.borrow_mut().remove(profile_id);
        let ready = ConnectionState {
            helper: Some(helper),
            ..ConnectionState::new(profile_id, Phase::Ready)
        };
        self.publish(ready.clone());
        let weak = self.this.clone();
        let closed_profile = profile_id.to_owned();
        let closed_connection = Rc::downgrade(&connection);
        channel.on_closed(move |reason| {
            let Some(service) = weak.upgrade() else {
                return;
            };
            let current = service.live.borrow().get(&closed_profile).cloned();
            let Some(current) = current else { return };
            if !closed_connection
                .upgrade()
                .is_some_and(|connection| Rc::ptr_eq(&connection, &current))
            {
                return;
            }
            service.live.borrow_mut().remove(&closed_profile);
            {
                // Keep it routable while tabs hold its sessions; forget emptied ones.
                let mut retired = service.retired.borrow_mut();
                retired.retain(|connection| connection.sessions.has_sessions());
                retired.push(Rc::clone(&current));
            }
            if service.disposed.get() {
                return;
            }
            let closing = current.closing.get();
            service.publish(match reason {
                Some(failure) if !closing => {
                    ConnectionState::failed(&closed_profile, Phase::Disconnected, failure)
                }
                _ => ConnectionState::new(&closed_profile, Phase::Idle),
            });
        });
        let this = self.rc();
        let reconcile = Rc::clone(&connection);
        rt::spawn_detached(async move { this.reconcile_connection(&reconcile).await });
        Ok(ready)
    }

    /// Accepts the identity a helper reported after it changed, withdrawing write
    /// permission, and connects again.
    pub async fn rebind(&self, profile_id: &str) -> Result<ConnectionState, Failure> {
        let observed = self
            .observed_identity(profile_id)
            .ok_or(Failure::Unsupported)?;
        let existing = self.profile(profile_id).ok_or(Failure::Unsupported)?;
        self.save_profiles(self.replace_profile(&NativeRemoteHostProfile {
            verified: Some(observed),
            writes_allowed: false,
            auto_install_helper: false,
            ..existing
        }))
        .await
        .map_err(|_| Failure::Internal)?;
        self.observed.borrow_mut().remove(profile_id);
        self.connect(profile_id).await
    }

    /// Closes a profile's connection. Its tabs keep their last received state as stale.
    pub async fn disconnect(&self, profile_id: &str) {
        self.cancel(profile_id);
        let Some(connection) = self.live.borrow().get(profile_id).cloned() else {
            return;
        };
        connection.closing.set(true);
        self.publish(ConnectionState::new(profile_id, Phase::Disconnecting));
        connection.channel.close().await;
    }

    /// Whether the profile's live connection may create repositories; `None` when it is not
    /// connected.
    #[must_use]
    pub fn can_initialize(&self, profile_id: &str) -> Option<bool> {
        let connection = self
            .live_connection(profile_id)
            .filter(|connection| connection.channel.is_open())?;
        Some(connection.channel.has(RemoteCapability::Initialize))
    }

    /// The capabilities of a profile's ready connection.
    #[must_use]
    pub fn capabilities(&self, profile_id: &str) -> HashSet<RemoteCapability> {
        self.state(profile_id)
            .helper
            .map(|helper| helper.capabilities)
            .unwrap_or_default()
    }

    /// One page of a remote directory on a connected profile.
    pub async fn list_directory(
        &self,
        profile_id: &str,
        directory: Option<Vec<u8>>,
        cursor: Option<String>,
    ) -> Result<DirectoryPage, Failure> {
        let connection = self
            .live_connection(profile_id)
            .ok_or(Failure::Disconnected)?;
        connection
            .sessions
            .list_directory(directory.as_deref(), cursor.as_deref())
            .await
    }

    fn connection_of(&self, authority: &NativeRemoteAuthority) -> Option<Rc<Connection>> {
        self.live
            .borrow()
            .values()
            .find(|connection| {
                &connection.authority == authority
                    && !connection.closing.get()
                    && connection.channel.is_open()
            })
            .cloned()
    }

    // The record of remote writes ------------------------------------------------

    /// Remote writes, newest last. Pending ones need reconciliation.
    #[must_use]
    pub fn operations(&self) -> Vec<NativeRemotePendingOperation> {
        self.operations.borrow().clone()
    }

    #[must_use]
    pub fn ledger_usable(&self) -> bool {
        self.ledger_usable.get()
    }

    async fn save_operations(
        &self,
        operations: Vec<NativeRemotePendingOperation>,
    ) -> Result<(), ()> {
        let directory = self.ledger_directory.clone().ok_or(())?;
        let saving = operations.clone();
        let saved =
            rt::blocking(move || gitlama_core::api::remote_pending_save(directory, saving)).await;
        if !saved.saved {
            return Err(());
        }
        *self.operations.borrow_mut() = operations;
        self.notifier.notify(Topics::REMOTE);
        Ok(())
    }

    /// Removes a resolved operation the user acknowledged.
    pub async fn dismiss_operation(&self, operation_id: &str) {
        let operations = self.operations();
        let remaining: Vec<_> = operations
            .iter()
            .filter(|operation| {
                operation.operation_id != operation_id || operation.state == "pending"
            })
            .cloned()
            .collect();
        if remaining.len() != operations.len() {
            let _ = self.save_operations(remaining).await;
        }
    }

    /// Looks up every unresolved operation of the connection's authority. A lookup never
    /// executes anything; unresolved operations stay pending.
    async fn reconcile_connection(&self, connection: &Connection) {
        for operation in self.operations() {
            if operation.state != "pending"
                || operation.profile_id != connection.authority.profile_id
                || operation.store_id != connection.authority.store_id
                || operation.account_uid != connection.authority.account_uid
            {
                continue;
            }
            if let Ok(looked) = connection.sessions.lookup(&operation).await {
                let _ = self.record_operation(looked).await;
            }
        }
    }

    /// Looks up a profile's unresolved operations again.
    pub async fn reconcile(&self, profile_id: &str) {
        if let Some(connection) = self.live_connection(profile_id) {
            self.reconcile_connection(&connection).await;
        }
    }

    async fn record_operation(&self, operation: NativeRemotePendingOperation) -> Result<(), ()> {
        if !self.ledger_usable.get() {
            return Err(());
        }
        let mut next: Vec<_> = self
            .operations()
            .into_iter()
            .filter(|existing| existing.operation_id != operation.operation_id)
            .collect();
        next.push(operation);
        // Resolved operations beyond the bound go first; unresolved ones never.
        while next.len() > contract::PENDING_OPERATIONS {
            let Some(index) = next.iter().position(|entry| entry.state != "pending") else {
                return Err(());
            };
            next.remove(index);
        }
        self.save_operations(next).await
    }

    // The operation center -------------------------------------------------------

    /// The helpers' operations of every live connection, under local session identifiers.
    pub async fn remote_operations(
        &self,
    ) -> Vec<gitlama_contract::dto::NativeOperationCenterSnapshot> {
        let connections: Vec<_> = self
            .live
            .borrow()
            .values()
            .filter(|c| !c.closing.get() && c.channel.is_open())
            .cloned()
            .collect();
        let mut snapshots = Vec::new();
        for connection in connections {
            let cached = connection.operations.borrow().clone();
            let eager = cached.as_ref().is_none_or(|(snapshot, at)| {
                snapshot.running_count > 0 || at.elapsed() >= OPERATIONS_QUIET
            }) || connection
                .sessions
                .recently_wrote(OPERATIONS_AFTER_WRITE_MS);
            if !eager {
                if let Some((snapshot, _)) = cached {
                    snapshots.push(snapshot);
                }
                continue;
            }
            match connection.sessions.operation_center(64).await {
                Ok(Some(snapshot)) => {
                    *connection.operations.borrow_mut() =
                        Some((snapshot.clone(), std::time::Instant::now()));
                    snapshots.push(snapshot);
                }
                // A lost connection keeps the last known state until it is gone.
                _ => {
                    if let Some((snapshot, _)) = cached {
                        snapshots.push(snapshot);
                    }
                }
            }
        }
        snapshots
    }

    /// Dismisses a finished helper operation of a remote session.
    pub async fn dismiss_remote_operation(
        &self,
        session_id: u64,
        generation: u64,
        activity_id: u64,
    ) {
        let connection = self
            .live
            .borrow()
            .values()
            .find(|c| c.sessions.owns(session_id))
            .cloned();
        if let Some(connection) = connection {
            let _ = connection
                .sessions
                .dismiss_operation(session_id, generation, activity_id)
                .await;
            *connection.operations.borrow_mut() = None;
        }
    }

    /// Whether a remote write is running or started recently on any connection.
    #[must_use]
    pub fn recently_wrote(&self, within_ms: u64) -> bool {
        self.live
            .borrow()
            .values()
            .any(|connection| connection.sessions.recently_wrote(within_ms))
    }

    /// Closes every connection, bounded.
    pub async fn dispose(&self) {
        if self.disposed.replace(true) {
            return;
        }
        if let Some(reconnector) = self.reconnector() {
            reconnector.dispose();
        }
        for cancel in self.cancels.borrow().values() {
            cancel.cancel();
        }
        let connections: Vec<_> = self
            .live
            .borrow_mut()
            .drain()
            .map(|(_, connection)| connection)
            .collect();
        let closing = async move {
            for connection in connections {
                connection.closing.set(true);
                connection.channel.close().await;
            }
        };
        let _ = rt::timeout(SHUTDOWN_DEADLINE, closing).await;
    }
}

impl Ledger for RemoteService {
    fn record(
        &self,
        operation: NativeRemotePendingOperation,
    ) -> LocalBoxFuture<'static, Result<(), ()>> {
        let this = self.rc();
        async move { this.record_operation(operation).await }.boxed_local()
    }
}

impl WorkspaceRemotes for RemoteService {
    fn available(&self) -> bool {
        true
    }

    fn is_live(&self, authority: &NativeRemoteAuthority) -> bool {
        self.connection_of(authority).is_some()
    }

    fn has_profile(&self, profile_id: &str) -> bool {
        self.profile(profile_id).is_some()
    }

    fn is_ready(&self, profile_id: &str) -> bool {
        self.state(profile_id).ready()
    }

    fn forget_binding(&self, authority: &NativeRemoteAuthority, path: &[u16]) {
        let bytes: Vec<u8> = path.iter().map(|unit| *unit as u8).collect();
        self.bindings
            .borrow_mut()
            .remove(&binding_key(authority, &bytes));
    }

    fn connect(
        &self,
        profile_id: &str,
    ) -> LocalBoxFuture<'static, Result<ConnectionState, Failure>> {
        RemoteService::connect(self, profile_id)
    }

    fn disconnect(&self, profile_id: &str) -> LocalBoxFuture<'static, ()> {
        let this = self.rc();
        let profile = profile_id.to_owned();
        async move { RemoteService::disconnect(&this, &profile).await }.boxed_local()
    }

    fn initialize_repository(
        &self,
        authority: &NativeRemoteAuthority,
        path: Vec<u8>,
        initial_branch: String,
        bare: bool,
    ) -> LocalBoxFuture<'static, Result<Option<NativeRepositoryFailureKind>, Failure>> {
        let connection = self.connection_of(authority);
        let allowed = self.can_initialize(&authority.profile_id) == Some(true);
        async move {
            let connection = connection.ok_or(Failure::Disconnected)?;
            if !allowed {
                return Err(Failure::WriteNotPermitted);
            }
            let result = connection
                .sessions
                .initialize_repository(&path, &initial_branch, bare)
                .await;
            if result.is_ok() {
                super::note(
                    crate::diagnostics::Level::Info,
                    "remote_repository_initialized",
                    &[],
                );
            }
            result
        }
        .boxed_local()
    }
}

/// Routes each call to this computer or to the connection that owns its session.
pub struct Router {
    pub local: Rc<dyn SessionCalls>,
    pub remote: RefCell<Weak<RemoteService>>,
}

impl CallRouter for Router {
    fn local(&self) -> Rc<dyn SessionCalls> {
        Rc::clone(&self.local)
    }

    fn for_session(&self, session_id: u64) -> Option<Rc<dyn SessionCalls>> {
        if session_id < REMOTE_SESSION_BASE {
            return Some(Rc::clone(&self.local));
        }
        let service = self.remote.borrow().upgrade()?;
        let live = service.live.borrow();
        let found = live
            .values()
            .find(|connection| connection.sessions.owns(session_id))
            .map(|connection| Rc::clone(&connection.calls));
        found.or_else(|| {
            service
                .retired
                .borrow()
                .iter()
                .find(|connection| connection.sessions.owns(session_id))
                .map(|connection| Rc::clone(&connection.calls))
        })
    }

    fn for_identity(&self, identity: &NativePathIdentity) -> Option<Rc<dyn SessionCalls>> {
        let Some(authority) = &identity.remote else {
            return Some(Rc::clone(&self.local));
        };
        let service = self.remote.borrow().upgrade()?;
        service
            .connection_of(authority)
            .map(|connection| Rc::clone(&connection.calls))
    }
}
