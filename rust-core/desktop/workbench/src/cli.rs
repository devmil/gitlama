//! Commands forwarded from the command line to the running window: this process owns the instance, polls the
//! forwarded commands every tenth of a second and answers each one. Opening
//! a repository, refreshing, fetching and pulling raise the window first.

use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::transfers::{Draft, TransferService};
use crate::workspace::WorkspaceService;
use gitlama_contract::cli_forwarding::{
    NativeCliCommand, NativeCliCommandKind, NativeCliPathPlatform, NativeCliPullStrategy,
    NativeCliResponseKind, NativeCliStartupState,
};
use gitlama_contract::dto::{NativePathIdentity, NativePathPlatform};
use gitlama_contract::transfer::{NativePullStrategy, NativeTransferKind};
use std::cell::Cell;
use std::rc::{Rc, Weak};
use std::sync::{Arc, Mutex, OnceLock};

/// The most commands one drain handles before yielding.
const BATCH: usize = 8;
/// The most paths the operating system may queue before the window takes them.
const OPEN_QUEUE: usize = 64;
/// The longest path accepted from the operating system.
const OPEN_PATH_LIMIT: usize = 32 * 1024;

/// Folders the operating system asked GitLama to open (macOS Launch Services delivers
/// `open -a GitLama <folder>` and Finder drops as open-document events, possibly before the
/// window is ready). They wait here until the forwarding loop opens them.
static OPEN_REQUESTS: Mutex<std::collections::VecDeque<Vec<u8>>> =
    Mutex::new(std::collections::VecDeque::new());
static OPEN_WAKEUP: OnceLock<Mutex<Option<Arc<rt::WakeSignal>>>> = OnceLock::new();

fn set_open_wakeup(signal: Option<Arc<rt::WakeSignal>>) {
    let lock = OPEN_WAKEUP.get_or_init(|| Mutex::new(None));
    if let Ok(mut slot) = lock.lock() {
        *slot = signal;
    }
}

/// Queues a folder the operating system asked to open. False when the path is empty, too
/// long, contains NUL or the queue is full.
pub fn queue_open_request(path: &[u8]) -> bool {
    if path.is_empty() || path.len() > OPEN_PATH_LIMIT || path.contains(&0) {
        return false;
    }
    let Ok(mut queue) = OPEN_REQUESTS.lock() else {
        return false;
    };
    if queue.len() >= OPEN_QUEUE {
        return false;
    }
    queue.push_back(path.to_vec());
    drop(queue);
    if let Some(lock) = OPEN_WAKEUP.get()
        && let Ok(slot) = lock.lock()
        && let Some(signal) = slot.as_ref()
    {
        signal.notify();
    }
    true
}

fn take_open_requests() -> Vec<Vec<u8>> {
    OPEN_REQUESTS.lock().map_or_else(
        |_| Vec::new(),
        |mut queue| {
            let count = queue.len().min(BATCH);
            queue.drain(..count).collect()
        },
    )
}

pub struct CliForwarding {
    workspace: Rc<WorkspaceService>,
    transfers: Rc<TransferService>,
    notifier: Notifier,
    /// Bumps whenever the window should come to the front.
    activations: Cell<u64>,
    polling: Cell<bool>,
    disposed: Cell<bool>,
    wakeup: Arc<rt::WakeSignal>,
    /// The window's remote workspace workflows, once composed.
    pub remote: std::cell::RefCell<Option<Rc<crate::remote::workflows::RemoteWorkflows>>>,
}

/// The path a forwarded command names.
pub fn command_path(command: &NativeCliCommand) -> Option<NativePathIdentity> {
    let platform = match command.path_platform? {
        NativeCliPathPlatform::Unix => NativePathPlatform::Unix,
        NativeCliPathPlatform::Windows => NativePathPlatform::Windows,
    };
    let units = command
        .path_units
        .iter()
        .map(|unit| u16::try_from(*unit).ok())
        .collect::<Option<Vec<_>>>()?;
    Some(NativePathIdentity {
        platform,
        units,
        remote: None,
    })
}

pub fn pull_strategy(strategy: Option<NativeCliPullStrategy>) -> NativePullStrategy {
    match strategy {
        Some(NativeCliPullStrategy::FastForwardIfPossible) => {
            NativePullStrategy::FastForwardIfPossible
        }
        Some(NativeCliPullStrategy::Rebase) => NativePullStrategy::Rebase,
        _ => NativePullStrategy::FastForwardOnly,
    }
}

impl CliForwarding {
    /// Takes the instance (the process may already own it from its start).
    pub async fn start(
        workspace: Rc<WorkspaceService>,
        transfers: Rc<TransferService>,
        notifier: Notifier,
    ) -> Result<Rc<Self>, ()> {
        let startup = rt::blocking(gitlama_core::api::cli_forwarding_ensure_owner).await;
        if startup.state != NativeCliStartupState::Owner {
            return Err(());
        }
        let wakeup = Arc::new(rt::WakeSignal::new());
        set_open_wakeup(Some(Arc::clone(&wakeup)));
        {
            let signal = Arc::clone(&wakeup);
            gitlama_core::api::cli_forwarding_set_wakeup(Some(Arc::new(move || signal.notify())));
        }
        let this = Rc::new(Self {
            workspace,
            transfers,
            notifier,
            activations: Cell::new(0),
            polling: Cell::new(false),
            disposed: Cell::new(false),
            wakeup: Arc::clone(&wakeup),
            remote: std::cell::RefCell::new(None),
        });
        let weak = Rc::downgrade(&this);
        rt::spawn_detached(async move { Self::serve(weak, wakeup).await });
        Ok(this)
    }

    pub fn activations(&self) -> u64 {
        self.activations.get()
    }

    fn activate(&self) {
        self.activations.set(self.activations.get() + 1);
        self.notifier.notify(Topics::STARTUP);
    }

    async fn serve(this: Weak<Self>, wakeup: Arc<rt::WakeSignal>) {
        // Drain any initial invocation command or early open-document request once, then sleep
        // until a forwarded CLI command or OS open request arrives.
        loop {
            let Some(service) = this.upgrade() else {
                return;
            };
            if service.disposed.get() {
                return;
            }
            service.drain().await;
            service.open_requested().await;
            drop(service);
            if !wakeup.next().await {
                return;
            }
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
            let Some(command) = polled.command.filter(|_| polled.failure.is_none()) else {
                break;
            };
            self.dispatch(command).await;
        }
        self.polling.set(false);
    }

    /// Opens the folders the operating system asked for, in the order it delivered them.
    async fn open_requested(&self) {
        for path in take_open_requests() {
            if self.disposed.get() {
                return;
            }
            self.activate();
            let identity = NativePathIdentity {
                platform: NativePathPlatform::Unix,
                units: path.iter().map(|byte| u16::from(*byte)).collect(),
                remote: None,
            };
            // A failure shows in the repository's own state.
            let _ = self.workspace.open_recent(identity).await;
        }
    }

    async fn respond(&self, command: &NativeCliCommand, response: NativeCliResponseKind) {
        let request = command.request_id;
        rt::blocking(move || gitlama_core::api::cli_forwarding_respond(request, response)).await;
    }

    async fn dispatch(&self, command: NativeCliCommand) {
        let has_session = self.workspace.current().is_some();
        match command.kind {
            NativeCliCommandKind::Activate => {
                self.respond(&command, NativeCliResponseKind::Accepted)
                    .await;
                self.activate();
            }
            NativeCliCommandKind::OpenRepository => {
                let Some(path) = command_path(&command) else {
                    return self
                        .respond(&command, NativeCliResponseKind::Precondition)
                        .await;
                };
                self.respond(&command, NativeCliResponseKind::Accepted)
                    .await;
                self.activate();
                // A failure shows in the repository's own state.
                let _ = self.workspace.open_recent(path).await;
            }
            // The window connects the host, with its dialogs.
            NativeCliCommandKind::OpenRemoteRepository => {
                let remote = self.remote.borrow().clone();
                let path: Option<Vec<u8>> = command
                    .path_units
                    .iter()
                    .map(|unit| u8::try_from(*unit).ok())
                    .collect();
                let (Some(remote), Some(alias), Some(path)) =
                    (remote, command.remote_alias.clone(), path)
                else {
                    return self
                        .respond(&command, NativeCliResponseKind::Precondition)
                        .await;
                };
                if !crate::remote::model::is_valid_path(&path) {
                    return self
                        .respond(&command, NativeCliResponseKind::Precondition)
                        .await;
                }
                self.respond(&command, NativeCliResponseKind::Accepted)
                    .await;
                self.activate();
                remote.open_on_host(&alias, path).await;
            }
            NativeCliCommandKind::Refresh => {
                if !has_session {
                    return self
                        .respond(&command, NativeCliResponseKind::Precondition)
                        .await;
                }
                self.respond(&command, NativeCliResponseKind::Accepted)
                    .await;
                self.activate();
                let _ = self.workspace.refresh().await;
            }
            NativeCliCommandKind::Fetch | NativeCliCommandKind::Pull => {
                if !has_session {
                    return self
                        .respond(&command, NativeCliResponseKind::Precondition)
                        .await;
                }
                self.respond(&command, NativeCliResponseKind::Accepted)
                    .await;
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
        set_open_wakeup(None);
        gitlama_core::api::cli_forwarding_set_wakeup(None);
        self.wakeup.close();
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
    fn open_requests_are_bounded_and_taken_in_order() {
        assert!(!queue_open_request(b""));
        assert!(!queue_open_request(b"/a\0b"));
        assert!(!queue_open_request(&vec![b'a'; OPEN_PATH_LIMIT + 1]));
        assert!(queue_open_request(b"/first"));
        assert!(queue_open_request(b"/second"));
        assert_eq!(
            take_open_requests(),
            vec![b"/first".to_vec(), b"/second".to_vec()]
        );
        for _ in 0..OPEN_QUEUE {
            assert!(queue_open_request(b"/many"));
        }
        assert!(!queue_open_request(b"/full"));
        assert_eq!(take_open_requests().len(), BATCH);
        while !take_open_requests().is_empty() {}
    }

    #[test]
    fn forwarded_paths_keep_their_platform() {
        let path =
            command_path(&command(Some(NativeCliPathPlatform::Unix), vec![47, 114])).unwrap();
        assert_eq!(path.units, [47, 114]);
        assert_eq!(path.platform, NativePathPlatform::Unix);
        assert!(command_path(&command(None, vec![47])).is_none());
        assert!(
            command_path(&command(
                Some(NativeCliPathPlatform::Windows),
                vec![0x1_0000]
            ))
            .is_none()
        );
    }

    #[test]
    fn pull_strategies_default_to_fast_forward_only() {
        assert_eq!(pull_strategy(None), NativePullStrategy::FastForwardOnly);
        assert_eq!(
            pull_strategy(Some(NativeCliPullStrategy::Rebase)),
            NativePullStrategy::Rebase
        );
    }
}
