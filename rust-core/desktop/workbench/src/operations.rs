//! The operation center (the Dart OperationCenterService and
//! OperationCenterActions): the application's running and recent Git
//! operations, polled while the window runs, with Cancel, Retry and Dismiss
//! routed to whatever runs each entry.

use crate::notify::{Notifier, Topics};
use crate::rt::{self, TimerHandle};
use crate::session::SessionIdentity;
use crate::transfers::TransferService;
use gitlama_contract::dto::{
    NativeOperationCenterAction, NativeOperationCenterEntry, NativeOperationCenterOrigin,
    NativeOperationCenterSnapshot, NativeOperationCenterState,
};
use gitlama_contract::transfer::NativeTransferKind;
use std::cell::{Cell, RefCell};
use std::rc::{Rc, Weak};
use std::time::Duration;

/// How often the operation center polls the application.
const POLL: Duration = Duration::from_millis(250);
const MAXIMUM_ENTRIES: u32 = 256;

/// An entry's stable key: its activity, else its start time.
pub fn entry_key(entry: &NativeOperationCenterEntry) -> u64 {
    entry.activity_id.unwrap_or(entry.started_at_unix_ms)
}

pub struct OperationCenter {
    this: Weak<Self>,
    remote: RefCell<Weak<crate::remote::service::RemoteService>>,
    notifier: Notifier,
    transfers: Rc<TransferService>,
    snapshot: RefCell<NativeOperationCenterSnapshot>,
    timer: RefCell<TimerHandle>,
    refreshing: Cell<bool>,
    disposed: Cell<bool>,
}

fn empty() -> NativeOperationCenterSnapshot {
    NativeOperationCenterSnapshot {
        entries: Vec::new(),
        running_count: 0,
        failed_count: 0,
        warning_count: 0,
        attention_count: 0,
        truncated: false,
    }
}

impl OperationCenter {
    pub fn new(notifier: Notifier, transfers: Rc<TransferService>) -> Rc<Self> {
        Rc::new_cyclic(|this| Self {
            remote: RefCell::new(std::rc::Weak::new()),
            this: this.clone(),
            notifier,
            transfers,
            snapshot: RefCell::new(empty()),
            timer: RefCell::new(TimerHandle::default()),
            refreshing: Cell::new(false),
            disposed: Cell::new(false),
        })
    }

    /// Lists the operations of remote hosts' helpers beside this computer's.
    pub fn set_remote(&self, remote: &Rc<crate::remote::service::RemoteService>) {
        *self.remote.borrow_mut() = Rc::downgrade(remote);
    }

    pub fn current(&self) -> NativeOperationCenterSnapshot {
        self.snapshot.borrow().clone()
    }

    /// Polls now and then every [`POLL`].
    pub fn start(&self) {
        let weak = self.this.clone();
        rt::spawn_detached(async move {
            if let Some(center) = weak.upgrade() {
                center.refresh().await;
                center.schedule();
            }
        });
    }

    fn schedule(&self) {
        if self.disposed.get() {
            return;
        }
        let weak = self.this.clone();
        *self.timer.borrow_mut() = TimerHandle::start(POLL, move || {
            let Some(center) = weak.upgrade() else { return };
            rt::spawn_detached(async move {
                center.refresh().await;
                center.schedule();
            });
        });
    }

    /// Reads the application's operations; publishes only a change.
    pub async fn refresh(&self) {
        if self.disposed.get() || self.refreshing.replace(true) {
            return;
        }
        let result =
            rt::blocking(|| gitlama_core::api::application_operation_center(MAXIMUM_ENTRIES)).await;
        self.refreshing.set(false);
        // A session retiring meanwhile keeps the last coherent projection.
        let Some(mut snapshot) = result.snapshot.filter(|_| result.failure.is_none()) else {
            return;
        };
        let remote = self.remote.borrow().upgrade();
        if let Some(remote) = remote {
            for other in remote.remote_operations().await {
                snapshot.running_count += other.running_count;
                snapshot.failed_count += other.failed_count;
                snapshot.warning_count += other.warning_count;
                snapshot.attention_count += other.attention_count;
                snapshot.truncated |= other.truncated;
                snapshot.entries.extend(other.entries);
            }
            snapshot
                .entries
                .sort_by_key(|entry| entry.started_at_unix_ms);
        }
        if self.disposed.get() || *self.snapshot.borrow() == snapshot {
            return;
        }
        *self.snapshot.borrow_mut() = snapshot;
        self.notifier.notify(Topics::OPERATIONS);
    }

    fn entry(&self, key: u64) -> Option<NativeOperationCenterEntry> {
        self.snapshot
            .borrow()
            .entries
            .iter()
            .find(|entry| entry_key(entry) == key)
            .cloned()
    }

    /// The running transfer this window started for `entry`.
    fn transfer_for(&self, entry: &NativeOperationCenterEntry) -> Option<(u64, SessionIdentity)> {
        if entry.state != NativeOperationCenterState::Running
            || entry.origin != NativeOperationCenterOrigin::User
        {
            return None;
        }
        let kinds: &[NativeTransferKind] = match entry.action {
            NativeOperationCenterAction::Fetch => &[NativeTransferKind::Fetch],
            NativeOperationCenterAction::Pull => &[NativeTransferKind::Pull],
            NativeOperationCenterAction::Push => &[
                NativeTransferKind::Push,
                NativeTransferKind::PushTag,
                NativeTransferKind::DeleteTag,
                NativeTransferKind::DeleteBranch,
            ],
            _ => &[],
        };
        self.transfers
            .running()
            .into_iter()
            .find(|(_, kind, identity)| {
                kinds.contains(kind)
                    && Some(identity.native_id) == entry.session_id
                    && identity.generation == entry.generation
            })
            .map(|(token, _, identity)| (token, identity))
    }

    /// Whether Cancel can stop `entry`.
    pub fn can_cancel(&self, entry: &NativeOperationCenterEntry) -> bool {
        entry.can_cancel || self.transfer_for(entry).is_some()
    }

    pub async fn cancel(&self, key: u64) {
        let Some(entry) = self.entry(key) else { return };
        if let Some((token, identity)) = self.transfer_for(&entry) {
            self.transfers.cancel(identity, token).await;
        }
    }

    /// Retries `key`: only a clone attempt can (clone is not part of this
    /// window yet).
    pub async fn retry(&self, _key: u64) {}

    pub async fn dismiss(&self, key: u64) {
        let Some(entry) = self.entry(key) else { return };
        if let (Some(session), Some(activity)) = (entry.session_id, entry.activity_id)
            && session >= crate::remote::service::REMOTE_SESSION_BASE
        {
            let remote = self.remote.borrow().upgrade();
            if let Some(remote) = remote {
                remote
                    .dismiss_remote_operation(session, entry.generation, activity)
                    .await;
            }
        } else if let (Some(session), Some(activity)) = (entry.session_id, entry.activity_id) {
            let generation = entry.generation;
            rt::blocking(move || {
                gitlama_core::api::application_operation_dismiss(session, generation, activity)
            })
            .await;
        }
        self.refresh().await;
    }

    pub async fn dismiss_all(&self) {
        rt::blocking(gitlama_core::api::application_operation_dismiss_all).await;
        self.refresh().await;
    }

    /// The newest entry Retry (or Cancel) applies to.
    pub fn latest(&self, retry: bool) -> Option<u64> {
        let snapshot = self.snapshot.borrow();
        snapshot
            .entries
            .iter()
            .rev()
            .find(|entry| {
                if retry {
                    entry.can_retry
                } else {
                    self.can_cancel(entry)
                }
            })
            .map(entry_key)
    }

    pub fn dispose(&self) {
        self.disposed.set(true);
        self.timer.borrow_mut().cancel();
    }
}

/// Runs of background fetches that succeeded, one after another, show as
/// one row: (entry index, count).
pub fn present(entries: &[NativeOperationCenterEntry]) -> Vec<(usize, usize)> {
    let quiet_fetch = |entry: &NativeOperationCenterEntry| {
        entry.action == NativeOperationCenterAction::Fetch
            && entry.origin == NativeOperationCenterOrigin::Background
            && entry.state == NativeOperationCenterState::Succeeded
    };
    let mut rows: Vec<(usize, usize)> = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        match rows.last_mut() {
            Some((previous, count)) if quiet_fetch(entry) && quiet_fetch(&entries[*previous]) => {
                *count += 1
            }
            _ => rows.push((index, 1)),
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(
        action: NativeOperationCenterAction,
        origin: NativeOperationCenterOrigin,
        state: NativeOperationCenterState,
    ) -> NativeOperationCenterEntry {
        NativeOperationCenterEntry {
            activity_id: None,
            session_id: None,
            clone_attempt_id: None,
            generation: 0,
            state,
            origin,
            action,
            started_at_unix_ms: 1,
            finished_at_unix_ms: None,
            progress: None,
            can_cancel: false,
            can_retry: false,
            has_details: false,
        }
    }

    #[test]
    fn repeated_background_fetches_fold_into_one_row() {
        use NativeOperationCenterAction::{Fetch, Push};
        use NativeOperationCenterOrigin::{Background, User};
        use NativeOperationCenterState::{Failed, Succeeded};
        let entries = vec![
            entry(Fetch, Background, Succeeded),
            entry(Fetch, Background, Succeeded),
            entry(Fetch, Background, Succeeded),
            entry(Push, User, Succeeded),
            entry(Fetch, Background, Failed),
            entry(Fetch, Background, Succeeded),
        ];
        assert_eq!(present(&entries), vec![(0, 3), (3, 1), (4, 1), (5, 1)]);
    }
}
