//! What a transfer the person started changed, once its effect shows: the Compass glint
//! (NH-2) and History's arrival of new rows follow [`SyncChange::sequence`]. The tracker
//! captures the active tab before the transfer and compares the repository and its History
//! with it as they update; background fetches never reach it.

use crate::history::{HistoryService, WORKTREE_OBJECT_ID};
use crate::notify::{Notifier, Topics};
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::NativeRepositorySnapshot;
use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

/// The most new rows a change names: the arrival animates at most a screen of them.
const NEW_ROWS: usize = 64;

/// The last change a transfer showed.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SyncChange {
    /// Increments with each transfer whose effect showed.
    pub sequence: u64,
    /// The History rows that were not there before it (the working-tree row excluded), in
    /// page order, bounded.
    pub new_rows: Vec<String>,
    /// The History page request shown before it; a page with this request shows nothing new.
    pub previous_history_request: Option<u64>,
}

/// The active tab before a transfer.
#[derive(Clone, Debug)]
pub struct SyncBaseline {
    tab: u64,
    revision: u64,
    ahead: u64,
    behind: u64,
    head: Option<String>,
    rows: HashSet<String>,
    history_request: Option<u64>,
    remote_targets: HashSet<String>,
}

pub struct SyncTracker {
    workspace: Rc<WorkspaceService>,
    history: Rc<HistoryService>,
    notifier: Notifier,
    pending: RefCell<Option<SyncBaseline>>,
    current: RefCell<SyncChange>,
}

/// Every remote-tracking branch with its target, as comparable keys.
fn remote_targets(snapshot: &NativeRepositorySnapshot) -> HashSet<String> {
    snapshot
        .refs
        .remotes
        .iter()
        .flat_map(|remote| {
            remote.branches.iter().map(move |branch| {
                format!(
                    "{}/{}:{}",
                    String::from_utf8_lossy(&remote.name),
                    String::from_utf8_lossy(&branch.name),
                    branch.target
                )
            })
        })
        .collect()
}

impl SyncTracker {
    pub fn new(
        workspace: Rc<WorkspaceService>,
        history: Rc<HistoryService>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            workspace,
            history,
            notifier,
            pending: RefCell::new(None),
            current: RefCell::new(SyncChange::default()),
        })
    }

    pub fn current(&self) -> SyncChange {
        self.current.borrow().clone()
    }

    /// The active tab as it is now, or `None` when it shows no status.
    pub fn capture(&self) -> Option<SyncBaseline> {
        let tab = self.workspace.active_tab_id()?;
        let session = self.workspace.current()?;
        let status = session.snapshot.status.as_ref()?;
        let page = self.history.current().page;
        Some(SyncBaseline {
            tab,
            revision: session.snapshot.revision,
            ahead: status.ahead,
            behind: status.behind,
            head: status.head_object_id.clone(),
            rows: page
                .as_ref()
                .map(|page| page.rows.iter().map(|row| row.object_id.clone()).collect())
                .unwrap_or_default(),
            history_request: page.as_ref().map(|page| page.request_id),
            remote_targets: remote_targets(&session.snapshot),
        })
    }

    /// Watches for the effect of a transfer that started from `baseline`.
    pub fn expect(&self, baseline: SyncBaseline) {
        *self.pending.borrow_mut() = Some(baseline);
        self.check();
    }

    /// Compares the active tab with the pending baseline; called whenever the workspace or
    /// History changed.
    pub fn check(&self) {
        let Some(pending) = self.pending.borrow().clone() else {
            return;
        };
        if self.workspace.active_tab_id() != Some(pending.tab) {
            *self.pending.borrow_mut() = None;
            return;
        }
        let Some(session) = self.workspace.current() else {
            return;
        };
        let Some(status) = session.snapshot.status.as_ref() else {
            return;
        };
        let page = self.history.current().page;
        let new_rows: Vec<String> = page
            .as_ref()
            .map(|page| {
                page.rows
                    .iter()
                    .filter(|row| {
                        row.object_id != WORKTREE_OBJECT_ID
                            && !pending.rows.contains(&row.object_id)
                    })
                    .take(NEW_ROWS)
                    .map(|row| row.object_id.clone())
                    .collect()
            })
            .unwrap_or_default();
        let changed = status.ahead != pending.ahead
            || status.behind != pending.behind
            || status.head_object_id != pending.head
            || remote_targets(&session.snapshot) != pending.remote_targets
            || !new_rows.is_empty();
        if !changed {
            if session.snapshot.revision > pending.revision {
                *self.pending.borrow_mut() = None;
            }
            return;
        }
        *self.pending.borrow_mut() = None;
        let sequence = self.current.borrow().sequence + 1;
        *self.current.borrow_mut() = SyncChange {
            sequence,
            new_rows,
            previous_history_request: pending.history_request,
        };
        self.notifier.notify(Topics::WORKSPACE);
    }
}
