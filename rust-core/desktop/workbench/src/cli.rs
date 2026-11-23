//! Commands forwarded from the command line to the running window (the Dart
//! CliForwardingService): this process owns the instance, polls the
//! forwarded commands every tenth of a second and answers each one. Opening
//! a repository, refreshing, fetching and pulling raise the window first.

use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::transfers::{Draft, TransferService};
use crate::workspace::WorkspaceService;
use gitlama_contract::cli_forwarding::{
    NativeCliCommand, NativeCliCommandKind, NativeCliPathPlatform, NativeCliPullStrategy, NativeCliResponseKind, NativeCliStartupState,
};
use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
use gitlama_contract::transfer::{NativePullStrategy, NativeTransferKind};
use std::cell::Cell;
use std::rc::{Rc, Weak};
use std::time::Duration;

/// A forwarded command comes from a terminal: a tenth of a second is
/// imperceptible there.
const POLL: Duration = Duration::from_millis(100);
/// The most commands one poll handles.
const BATCH: usize = 8;

pub struct CliForwarding {
    workspace: Rc<WorkspaceService>,
    transfers: Rc<TransferService>,
    notifier: Notifier,
    /// Bumps whenever the window should come to the front.
    activations: Cell<u64>,
    polling: Cell<bool>,
    disposed: Cell<bool>,
}

/// The path a forwarded command names.
pub fn command_path(command: &NativeCliCommand) -> Option<NativePathIdentity> {
    let platform = match command.path_platform? {
        NativeCliPathPlatform::Unix => NativePathPlatform::Unix,
        NativeCliPathPlatform::Windows => NativePathPlatform::Windows,
    };
    let units = command.path_units.iter().map(|unit| u16::try_from(*unit).ok()).collect::<Option<Vec<_>>>()?;
    Some(NativePathIdentity { platform, units, remote: None })
}

pub fn pull_strategy(strategy: Option<NativeCliPullStrategy>) -> NativePullStrategy {
    match strategy {
        Some(NativeCliPullStrategy::FastForwardIfPossible) => NativePullStrategy::FastForwardIfPossible,
        Some(NativeCliPullStrategy::Rebase) => NativePullStrategy::Rebase,
        _ => NativePullStrategy::FastForwardOnly,
    }
}

impl CliForwarding {
    /// Takes the instance (the process may already own it from its start).
    pub async fn start(workspace: Rc<WorkspaceService>, transfers: Rc<TransferService>, notifier: Notifier) -> Result<Rc<Self>, ()> {
        let startup = rt::blocking(gitlama_core::api::cli_forwarding_ensure_owner).await;
        if startup.state != NativeCliStartupState::Owner {
            return Err(());
        }
        let this = Rc::new(Self {
            workspace,
            transfers,
            notifier,
            activations: Cell::new(0),
            polling: Cell::new(false),
            disposed: Cell::new(false),
        });
        let weak = Rc::downgrade(&this);
        rt::spawn_detached(async move { Self::serve(weak).await });
        Ok(this)
    }

    pub fn activations(&self) -> u64 {
        self.activations.get()
    }

    fn activate(&self) {
        self.activations.set(self.activations.get() + 1);
        self.notifier.notify(Topics::STARTUP);
    }

    async fn serve(this: Weak<Self>) {
        loop {
            let Some(service) = this.upgrade() else { return };
            if service.disposed.get() {
                return;
            }
            service.drain().await;
            drop(service);
            rt::sleep(POLL).await;
        }
    }

    async fn drain(&self) {
        if self.polling.replace(true) {
            return;
        }
        for _ in 0..BATCH {
            if self.disposed.get() {
                break;
            }
            let polled = rt::blocking(gitlama_core::api::cli_forwarding_poll).await;
            // The next poll retries a failure; no native detail is logged.
            let Some(command) = polled.command.filter(|_| polled.failure.is_none()) else { break };
            self.dispatch(command).await;
        }
        self.polling.set(false);
    }

    async fn respond(&self, command: &NativeCliCommand, response: NativeCliResponseKind) {
        let request = command.request_id;
        rt::blocking(move || gitlama_core::api::cli_forwarding_respond(request, response)).await;
    }

    async fn dispatch(&self, command: NativeCliCommand) {
        let has_session = self.workspace.current().is_some();
        match command.kind {
            NativeCliCommandKind::Activate => {
                self.respond(&command, NativeCliResponseKind::Accepted).await;
                self.activate();
            }
            NativeCliCommandKind::OpenRepository => {
                let Some(path) = command_path(&command) else {
                    return self.respond(&command, NativeCliResponseKind::Precondition).await;
                };
                self.respond(&command, NativeCliResponseKind::Accepted).await;
                self.activate();
                // A failure shows in the repository's own state.
                let _ = self.workspace.open_recent(path).await;
            }
            // Remote workspaces are not available in this window.
            NativeCliCommandKind::OpenRemoteRepository => self.respond(&command, NativeCliResponseKind::Precondition).await,
            NativeCliCommandKind::Refresh => {
                if !has_session {
                    return self.respond(&command, NativeCliResponseKind::Precondition).await;
                }
                self.respond(&command, NativeCliResponseKind::Accepted).await;
                self.activate();
                let _ = self.workspace.refresh().await;
            }
            NativeCliCommandKind::Fetch | NativeCliCommandKind::Pull => {
                if !has_session {
                    return self.respond(&command, NativeCliResponseKind::Precondition).await;
                }
                self.respond(&command, NativeCliResponseKind::Accepted).await;
                self.activate();
                // The usual dialog opens.
                let mut draft = Draft::new(if command.kind == NativeCliCommandKind::Fetch {
                    NativeTransferKind::Fetch
                } else {
                    NativeTransferKind::Pull
                });
                draft.initial_pull_strategy = pull_strategy(command.pull_strategy);
                self.transfers.start(draft).await;
            }
        }
    }

    pub async fn dispose(&self) {
        if self.disposed.replace(true) {
            return;
        }
        rt::blocking(gitlama_core::api::cli_forwarding_shutdown).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn command(platform: Option<NativeCliPathPlatform>, units: Vec<u32>) -> NativeCliCommand {
        NativeCliCommand {
            request_id: 1,
            kind: NativeCliCommandKind::OpenRepository,
            path_platform: platform,
            path_units: units,
            pull_strategy: None,
            remote_alias: None,
        }
    }

    #[test]
    fn forwarded_paths_keep_their_platform() {
        let path = command_path(&command(Some(NativeCliPathPlatform::Unix), vec![47, 114])).unwrap();
        assert_eq!(path.units, [47, 114]);
        assert_eq!(path.platform, NativePathPlatform::Unix);
        assert!(command_path(&command(None, vec![47])).is_none());
        assert!(command_path(&command(Some(NativeCliPathPlatform::Windows), vec![0x1_0000])).is_none());
    }

    #[test]
    fn pull_strategies_default_to_fast_forward_only() {
        assert_eq!(pull_strategy(None), NativePullStrategy::FastForwardOnly);
        assert_eq!(pull_strategy(Some(NativeCliPullStrategy::Rebase)), NativePullStrategy::Rebase);
    }
}
