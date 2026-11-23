//! The window's remote workspace workflows: connecting for use, installing the helper, reconnecting, changing a
//! host's access, opening and creating repositories on hosts. Decisions only the user can
//! make go through window prompts; messages go to the status bar.

use super::model::{Failure, Phase};
use super::reconnect::ReconnectPhase;
use super::service::RemoteService;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::session::{FailureCode, SessionState};
use crate::workspace::{RemoteInitializeError, WorkspaceService};
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::storage::NativeRemoteHostProfile;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

/// The localized message key (and arguments) of a remote failure.
#[must_use]
pub fn failure_message(code: Failure, alias: Option<&str>) -> (String, Value) {
    match code {
        Failure::SshConnectionFailed => (
            "remoteFailureSshConnectionFailed".to_owned(),
            json!({ "alias": alias }),
        ),
        Failure::PathInvalid => ("remotePathAbsoluteRequired".to_owned(), Value::Null),
        Failure::WriteNotPermitted => ("remoteCommandWritesUnavailable".to_owned(), Value::Null),
        other => (failure_key(other).to_owned(), Value::Null),
    }
}

fn failure_key(code: Failure) -> &'static str {
    match code {
        Failure::OutcomeUnknown => "remoteFailureOutcomeUnknown",
        Failure::SshUnavailable => "remoteFailureSshUnavailable",
        Failure::SshUnsupported => "remoteFailureSshUnsupported",
        Failure::HelperNotInstalled => "remoteFailureHelperNotInstalled",
        Failure::InstallUnavailable => "remoteFailureInstallUnavailable",
        Failure::InstallDirectory => "remoteFailureInstallDirectory",
        Failure::InstallWrite => "remoteFailureInstallWrite",
        Failure::InstallDigest => "remoteFailureInstallDigest",
        Failure::InstallExecute => "remoteFailureInstallExecute",
        Failure::InstallFailed => "remoteFailureInstallFailed",
        Failure::UnsupportedPlatform => "remoteFailureUnsupportedPlatform",
        Failure::BootstrapFailed => "remoteFailureBootstrapFailed",
        Failure::HandshakeTimeout => "remoteFailureHandshakeTimeout",
        Failure::ProtocolMismatch => "remoteFailureProtocolMismatch",
        Failure::BuildMismatch => "remoteFailureBuildMismatch",
        Failure::GitMissing => "remoteFailureGitMissing",
        Failure::GitUnsupported => "remoteFailureGitUnsupported",
        Failure::StoreUnavailable => "remoteFailureStoreUnavailable",
        Failure::IdentityChanged => "remoteFailureIdentityChanged",
        Failure::IdentityMismatch => "remoteFailureIdentityMismatch",
        Failure::ProtocolViolation => "remoteFailureProtocolViolation",
        Failure::Disconnected => "remoteFailureDisconnected",
        Failure::TimedOut => "remoteFailureTimedOut",
        Failure::Canceled => "remoteFailureCanceled",
        Failure::Capacity => "remoteFailureCapacity",
        Failure::Unsupported => "remoteFailureUnsupported",
        Failure::PathNotFound => "remoteFailurePathNotFound",
        Failure::PermissionDenied => "remoteFailurePermissionDenied",
        Failure::NotDirectory => "remoteFailureNotDirectory",
        Failure::DirectoryChanged => "remoteFailureDirectoryChanged",
        Failure::CursorExpired => "remoteFailureCursorExpired",
        Failure::PreviewExpired => "remoteFailurePreviewExpired",
        Failure::PreconditionFailed => "remoteFailurePreconditionFailed",
        Failure::OperationIdConflict => "remoteFailureOperationIdConflict",
        Failure::ReceiptCapacity => "remoteFailureReceiptCapacity",
        Failure::Internal => "remoteFailureInternal",
        Failure::SshConnectionFailed => "remoteFailureSshConnectionFailed",
        Failure::PathInvalid => "remotePathAbsoluteRequired",
        Failure::WriteNotPermitted => "remoteCommandWritesUnavailable",
    }
}

pub struct RemoteWorkflows {
    pub service: Rc<RemoteService>,
    workspace: Rc<WorkspaceService>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    reconnects: RefCell<HashSet<String>>,
    installs: RefCell<HashSet<String>>,
}

impl RemoteWorkflows {
    #[must_use]
    pub fn new(
        service: Rc<RemoteService>,
        workspace: Rc<WorkspaceService>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            service,
            workspace,
            prompts,
            notices,
            notifier,
            reconnects: RefCell::new(HashSet::new()),
            installs: RefCell::new(HashSet::new()),
        })
    }

    fn report_failure(&self, code: Failure, alias: Option<&str>) {
        let (key, args) = failure_message(code, alias);
        self.notices.error(&key, args);
    }

    fn report(&self, key: &str) {
        self.notices.error(key, Value::Null);
    }

    fn alias(&self, profile_id: &str) -> Option<String> {
        self.service
            .profile(profile_id)
            .map(|profile| profile.alias)
    }

    /// Whether `profile_id` is connecting right now.
    #[must_use]
    pub fn connecting(&self, profile_id: &str) -> bool {
        self.installs.borrow().contains(profile_id)
            || self.reconnects.borrow().contains(profile_id)
            || self
                .service
                .reconnector()
                .and_then(|reconnector| reconnector.state_of(profile_id))
                .is_some_and(|state| state.phase == ReconnectPhase::Connecting)
            || matches!(
                self.service.state(profile_id).phase,
                Phase::Installing | Phase::Connecting | Phase::Handshaking
            )
    }

    /// Whether a (re)installation of the helper resolves the host's failure.
    #[must_use]
    pub fn needs_helper(&self, profile_id: &str) -> bool {
        let reconnect = self
            .service
            .reconnector()
            .and_then(|reconnector| reconnector.state_of(profile_id))
            .and_then(|state| state.failure);
        reconnect
            .or(self.service.state(profile_id).failure)
            .is_some_and(Failure::install_resolves)
    }

    fn track(&self, set: &RefCell<HashSet<String>>, profile_id: &str) -> bool {
        let added = set.borrow_mut().insert(profile_id.to_owned());
        self.notifier.notify(Topics::REMOTE);
        added
    }

    fn untrack(&self, set: &RefCell<HashSet<String>>, profile_id: &str) {
        set.borrow_mut().remove(profile_id);
        self.notifier.notify(Topics::REMOTE);
    }

    /// Opens the hosts dialog (optionally choosing a host): the chosen host's ID.
    async fn show_hosts(&self, profile_id: Option<&str>, choosing: bool) -> Option<String> {
        self.prompts
            .ask(
                "remoteHosts",
                json!({ "profileId": profile_id, "choosing": choosing }),
            )
            .await
            .and_then(|answer| answer.as_str().map(str::to_owned))
    }

    /// Installs this version's helper on the host after the user confirmed it, then
    /// reconnects the host's tabs. Without a helper to install the hosts dialog shows the
    /// manual setup. Completes with whether the host is connected.
    pub async fn install_helper(&self, profile_id: &str) -> bool {
        if !self.track(&self.installs, profile_id) {
            return false;
        }
        let connected = self.install_helper_once(profile_id).await;
        self.untrack(&self.installs, profile_id);
        connected
    }

    async fn install_helper_once(&self, profile_id: &str) -> bool {
        let Some(profile) = self.service.profile(profile_id) else {
            return false;
        };
        let Some(artifact) = self.service.installable_helper(profile_id).await else {
            self.show_hosts(Some(profile_id), false).await;
            return self.service.state(profile_id).ready();
        };
        let decision = self
            .prompts
            .ask(
                "remoteInstallHelper",
                json!({
                    "profileId": profile.id,
                    "label": profile.label,
                    "alias": profile.alias,
                    "automatic": profile.auto_install_helper,
                    "location": artifact.install_path(),
                    "sha256": artifact.sha256,
                    "bytes": artifact.bytes.len(),
                    "platform": artifact.target.host(),
                }),
            )
            .await;
        let Some(decision) = decision.filter(|decision| !decision.is_null()) else {
            return false;
        };
        let automatic = decision["automatic"].as_bool().unwrap_or(false);
        if automatic != profile.auto_install_helper
            && self
                .service
                .set_auto_install_helper(profile_id, automatic)
                .await
                .is_err()
        {
            // The installation still runs; only the preference was not saved.
            self.report("remoteProfileSaveFailed");
        }
        let result = match self.service.install_helper(profile_id, artifact).await {
            Ok(result) => result,
            Err(code) => {
                if code != Failure::Canceled {
                    self.report_failure(code, Some(&profile.alias));
                }
                return false;
            }
        };
        if result.ready() {
            // The host is connected; its tabs reopen on the new connection.
            if let Some(reconnector) = self.service.reconnector() {
                let _ = reconnector.reconnect_now(profile_id).await;
            }
            return true;
        }
        if result.phase == Phase::IdentityChanged {
            self.show_hosts(Some(profile_id), false).await;
            return false;
        }
        if let Some(failure) = result.failure {
            self.report_failure(failure, Some(&profile.alias));
        }
        false
    }

    /// Connects `profile_id` again and reopens its tabs in place. A changed identity opens
    /// the hosts dialog for an explicit decision.
    pub async fn reconnect(&self, profile_id: &str) {
        if !self.track(&self.reconnects, profile_id) {
            return;
        }
        let result = match self.service.reconnector() {
            Some(reconnector) => reconnector.reconnect_now(profile_id).await,
            None => Err(Failure::Unsupported),
        };
        self.untrack(&self.reconnects, profile_id);
        let (state, failure) = match result {
            Ok(state) => {
                let failure =
                    (!state.ready()).then(|| state.failure.unwrap_or(Failure::Disconnected));
                (Some(state), failure)
            }
            Err(failure) => (None, Some(failure)),
        };
        if state
            .as_ref()
            .is_some_and(|state| state.phase == Phase::IdentityChanged)
        {
            self.show_hosts(Some(profile_id), false).await;
            return;
        }
        // A missing or broken helper is fixed where it happened, unless this reconnect
        // follows an installation.
        if failure.is_some_and(Failure::install_resolves)
            && !self.installs.borrow().contains(profile_id)
        {
            self.install_helper(profile_id).await;
            return;
        }
        // A failure that is retried shows in the tab with its next attempt.
        if let Some(failure) = failure
            && failure != Failure::Canceled
            && !failure.retriable()
        {
            self.report_failure(failure, self.alias(profile_id).as_deref());
        }
    }

    /// Lets GitLama only read on a host, or also change its repositories. A live
    /// connection reconnects with its tabs at once.
    pub async fn set_access(&self, profile_id: &str, allow_changes: bool) {
        let Some(profile) = self.service.profile(profile_id) else {
            return;
        };
        if profile.writes_allowed == allow_changes {
            return;
        }
        if self
            .service
            .set_writes_allowed(profile_id, allow_changes)
            .await
            .is_err()
        {
            self.report("remoteProfileSaveFailed");
            return;
        }
        if self.service.state(profile_id).ready() {
            let _ = self.workspace.apply_remote_access(profile_id).await;
        }
    }

    /// Reconnects a host whose access changed, with its tabs.
    pub async fn apply_access(&self, profile_id: &str) {
        let _ = self.workspace.apply_remote_access(profile_id).await;
    }

    /// Connects a host for something the user asked for, installing its helper or showing
    /// the hosts dialog where that resolves a failure. Whether the host is ready.
    pub async fn connect_for_use(&self, profile: &NativeRemoteHostProfile) -> bool {
        let state = match self.service.connect(&profile.id).await {
            Ok(state) => state,
            Err(code) => {
                self.report_failure(code, Some(&profile.alias));
                return false;
            }
        };
        if state.phase == Phase::IdentityChanged {
            self.show_hosts(Some(&profile.id), false).await;
            return false;
        }
        if !state.ready() && state.failure.is_some_and(Failure::install_resolves) {
            return self.install_helper(&profile.id).await;
        }
        if !state.ready() {
            if let Some(failure) = state.failure {
                self.report_failure(failure, Some(&profile.alias));
            }
            return false;
        }
        true
    }

    fn report_open(&self, code: FailureCode) {
        self.report(if code == FailureCode::Capacity {
            "remoteRepositoryCapacity"
        } else {
            "remoteOpenFailed"
        });
    }

    /// Lets the user choose a folder on the host: its path bytes.
    async fn choose_folder(
        &self,
        profile: &NativeRemoteHostProfile,
        initialize: bool,
    ) -> Option<Vec<u8>> {
        let answer = self
            .prompts
            .ask(
                "remoteChooseFolder",
                json!({ "profileId": profile.id, "purpose": if initialize { "initialize" } else { "open" } }),
            )
            .await?;
        let path: Vec<u8> = answer
            .as_array()?
            .iter()
            .map(|byte| byte.as_u64().and_then(|byte| u8::try_from(byte).ok()))
            .collect::<Option<_>>()?;
        super::model::is_valid_path(&path).then_some(path)
    }

    /// Chooses a host, then a folder on it, and opens the repository there. `tab` replaces
    /// a chooser tab with it instead of opening a new tab.
    pub async fn open_remote_repository(&self, tab: Option<u64>) {
        let Some(profile_id) = self.show_hosts(None, true).await else {
            return;
        };
        let Some(profile) = self.service.profile(&profile_id) else {
            return;
        };
        let Some(authority) = super::model::authority_of(&profile) else {
            return;
        };
        let Some(path) = self.choose_folder(&profile, false).await else {
            return;
        };
        let identity = WorkspaceService::remote_path_identity(authority, &path);
        let result = match tab {
            Some(tab) => self
                .workspace
                .open_from_chooser(tab, Some(identity))
                .await
                .map(|_| ()),
            None => self.workspace.open_recent(identity).await.map(|_| ()),
        };
        if let Err(error) = result {
            self.report_open(error.code());
        }
    }

    /// Opens `path` on the saved host with SSH alias `alias`, as asked from the command
    /// line: offers to save an unknown alias as a host first.
    pub async fn open_on_host(&self, alias: &str, path: Vec<u8>) {
        let known = self
            .service
            .profiles()
            .into_iter()
            .find(|profile| profile.alias == alias);
        let profile = match known {
            Some(profile) => profile,
            None => {
                let answer = self
                    .prompts
                    .ask("remoteAddHost", json!({ "alias": alias }))
                    .await;
                let Some(profile) = answer
                    .and_then(|answer| answer.as_str().map(str::to_owned))
                    .and_then(|id| self.service.profile(&id))
                else {
                    return;
                };
                profile
            }
        };
        if !self.connect_for_use(&profile).await {
            return;
        }
        // Connecting verifies a new host, which gives the profile its authority.
        let Some(authority) = self
            .service
            .profile(&profile.id)
            .as_ref()
            .and_then(super::model::authority_of)
        else {
            self.report("remoteOpenFailed");
            return;
        };
        if let Err(error) = self
            .workspace
            .open_recent(WorkspaceService::remote_path_identity(authority, &path))
            .await
        {
            self.report_open(error.code());
        }
    }

    /// Opens a recent remote repository, connecting its host first; `tab` replaces a
    /// chooser tab with it.
    pub async fn open_recent(&self, identity: NativePathIdentity, tab: Option<u64>) {
        let Some(authority) = identity.remote.clone() else {
            return;
        };
        let profile = self.service.profile(&authority.profile_id);
        let Some(profile) = profile
            .filter(|profile| super::model::authority_of(profile).as_ref() == Some(&authority))
        else {
            self.report("remoteRecentHostMissing");
            return;
        };
        if !self.connect_for_use(&profile).await {
            return;
        }
        let result = match tab {
            Some(tab) => self
                .workspace
                .open_from_chooser(tab, Some(identity))
                .await
                .map(|_| ()),
            None => self.workspace.open_recent(identity).await.map(|_| ()),
        };
        if let Err(error) = result {
            self.report_open(error.code());
        }
    }

    /// Why repositories cannot be created on a host before connecting, as a message key;
    /// `None` when they may be.
    #[must_use]
    pub fn initialize_block(&self, profile_id: &str) -> Option<&'static str> {
        match self.service.profile(profile_id) {
            None => Some("remoteRecentHostMissing"),
            Some(profile) if !profile.writes_allowed => Some("remoteCommandWritesOff"),
            Some(_) => None,
        }
    }

    /// Creates a repository on a host and opens it in a new tab: connects the host, lets the
    /// user choose an empty folder or type a new one, then initializes it there. `None` when
    /// the user canceled or a connection failure was reported; the host's reasons for creating
    /// nothing are the session failures of initializing on this computer.
    pub async fn initialize_remote_repository(
        &self,
        profile_id: &str,
        bare: bool,
    ) -> crate::session::SessionResult<Option<SessionState>> {
        Ok(self
            .initialize_remote_inner(profile_id, bare)
            .await?
            .flatten())
    }

    async fn initialize_remote_inner(
        &self,
        profile_id: &str,
        bare: bool,
    ) -> crate::session::SessionResult<Option<Option<SessionState>>> {
        let Some(selected) = self.service.profile(profile_id) else {
            return Ok(None);
        };
        if !self.connect_for_use(&selected).await {
            return Ok(None);
        }
        // Changes allowed after the connection started need a new connection.
        if self.service.write_block(profile_id) == Some(super::model::WriteBlock::Reconnect) {
            self.apply_access(profile_id).await;
        }
        let Some(profile) = self.service.profile(profile_id) else {
            return Ok(None);
        };
        let Some(authority) = super::model::authority_of(&profile) else {
            return Ok(None);
        };
        if self.service.can_initialize(profile_id) != Some(true) {
            self.report(match self.service.write_block(profile_id) {
                Some(super::model::WriteBlock::NotAllowed) => "remoteCommandWritesOff",
                Some(super::model::WriteBlock::Reconnect) => "remoteCommandWritesReconnect",
                Some(super::model::WriteBlock::LedgerUnavailable) => "remoteCommandWritesLedger",
                None => "remoteCommandWritesUnavailable",
            });
            return Ok(None);
        }
        let Some(path) = self.choose_folder(&profile, true).await else {
            return Ok(None);
        };
        match self
            .workspace
            .initialize_remote(authority, path, "main".to_owned(), bare)
            .await
        {
            Ok(state) => Ok(Some(Some(state))),
            Err(RemoteInitializeError::Remote(code)) => {
                self.report_failure(code, Some(&profile.alias));
                Ok(None)
            }
            Err(RemoteInitializeError::Session(error)) => Err(error),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failure_messages_have_stable_keys() {
        assert_eq!(
            failure_message(Failure::BuildMismatch, None).0,
            "remoteFailureBuildMismatch"
        );
        assert_eq!(
            failure_message(Failure::SshConnectionFailed, Some("box")),
            (
                "remoteFailureSshConnectionFailed".to_owned(),
                json!({ "alias": "box" })
            )
        );
        assert_eq!(
            failure_message(Failure::PathInvalid, None).0,
            "remotePathAbsoluteRequired"
        );
    }
}
