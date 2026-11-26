//! Which repository tabs are busy with a workflow. Blocking operations hold the tab's other
//! commands; non-blocking ones (staging) only mark it busy.

use crate::notify::{Notifier, Topics};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::future::Future;
use std::rc::Rc;

/// What a busy tab is doing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BusyActivity {
    CommitCheckout,
    Stash(&'static str),
    /// kind (merge, cherryPick, revert), source label, commit count and
    /// the current branch.
    HistoryMutation {
        kind: &'static str,
        source: String,
        count: usize,
        branch: String,
    },
    Rebase {
        current_branch: Vec<u8>,
        onto: Vec<u8>,
    },
    Restack {
        root_branch: Vec<u8>,
    },
    ConflictPrediction,
    /// Staging, unstaging or discarding: "stage" or "discard".
    Changes(&'static str),
    Commit,
}

impl BusyActivity {
    /// What the busy overlay says: an l10n key and its arguments.
    pub fn label(&self) -> (&'static str, serde_json::Value) {
        use serde_json::{Value, json};
        let text = |bytes: &[u8]| String::from_utf8_lossy(bytes).into_owned();
        match self {
            Self::CommitCheckout => ("commitCheckoutBusy", Value::Null),
            Self::Stash(kind) => (
                match *kind {
                    "push" => "stashBusyPush",
                    "apply" => "stashBusyApply",
                    "pop" => "stashBusyPop",
                    "drop" => "stashBusyDrop",
                    "rename" => "stashBusyRename",
                    _ => "stashBusyAutoStashCheckout",
                },
                Value::Null,
            ),
            Self::HistoryMutation {
                kind,
                source,
                count,
                branch,
            } => match *kind {
                "merge" => (
                    "historyMutationBusyMerge",
                    json!({"source": source, "branch": branch}),
                ),
                "cherryPick" => (
                    "historyMutationBusyCherryPick",
                    json!({"count": count, "branch": branch}),
                ),
                _ => (
                    "historyMutationBusyRevert",
                    json!({"count": count, "branch": branch}),
                ),
            },
            Self::Rebase {
                current_branch,
                onto,
            } => (
                "rebaseBusy",
                json!({"branch": text(current_branch), "target": text(onto)}),
            ),
            Self::Restack { root_branch } => ("restackBusy", json!({"root": text(root_branch)})),
            Self::ConflictPrediction => ("conflictPredictionBusy", Value::Null),
            Self::Changes(kind) => (
                if *kind == "discard" {
                    "changesBusyDiscard"
                } else {
                    "changesBusyStage"
                },
                Value::Null,
            ),
            Self::Commit => ("commitBusy", Value::Null),
        }
    }
}

pub struct BusyOperation {
    id: u64,
    pub activity: BusyActivity,
    pub blocking: bool,
    pub cancel: Option<Rc<dyn Fn()>>,
    pub canceling: Cell<bool>,
}

pub struct BusyService {
    notifier: Notifier,
    operations: RefCell<HashMap<u64, Vec<Rc<BusyOperation>>>>,
    next: Cell<u64>,
}

impl BusyService {
    pub fn new(notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            notifier,
            operations: RefCell::new(HashMap::new()),
            next: Cell::new(1),
        })
    }

    /// The latest blocking operation of `tab`.
    pub fn blocking_of(&self, tab: Option<u64>) -> Option<Rc<BusyOperation>> {
        self.operations.borrow().get(&tab?).and_then(|operations| {
            operations
                .iter()
                .rev()
                .find(|operation| operation.blocking)
                .cloned()
        })
    }

    /// The latest operation of `tab`, blocking or not: what the Compass names.
    pub fn latest_of(&self, tab: Option<u64>) -> Option<Rc<BusyOperation>> {
        self.operations
            .borrow()
            .get(&tab?)
            .and_then(|operations| operations.last().cloned())
    }

    pub fn is_blocked(&self, tab: Option<u64>) -> bool {
        self.blocking_of(tab).is_some()
    }

    pub fn is_busy(&self, tab: Option<u64>) -> bool {
        tab.is_some_and(|tab| {
            self.operations
                .borrow()
                .get(&tab)
                .is_some_and(|operations| !operations.is_empty())
        })
    }

    /// Asks the blocking operation of `tab` to stop.
    pub fn cancel(&self, tab: u64) {
        if let Some(operation) = self.blocking_of(Some(tab))
            && let Some(cancel) = operation.cancel.clone()
            && !operation.canceling.replace(true)
        {
            self.notifier.notify(Topics::OPERATIONS);
            cancel();
        }
    }

    /// Runs `operation` while `tab` is busy with `activity`.
    pub async fn run<T>(
        &self,
        tab: Option<u64>,
        activity: BusyActivity,
        blocking: bool,
        cancel: Option<Rc<dyn Fn()>>,
        operation: impl Future<Output = T>,
    ) -> T {
        let Some(tab) = tab else {
            return operation.await;
        };
        let id = self.next.get();
        self.next.set(id + 1);
        self.operations
            .borrow_mut()
            .entry(tab)
            .or_default()
            .push(Rc::new(BusyOperation {
                id,
                activity,
                blocking,
                cancel,
                canceling: Cell::new(false),
            }));
        self.notifier.notify(Topics::OPERATIONS);
        struct Done<'a>(&'a BusyService, u64, u64);
        impl Drop for Done<'_> {
            fn drop(&mut self) {
                let mut operations = self.0.operations.borrow_mut();
                if let Some(list) = operations.get_mut(&self.1) {
                    list.retain(|operation| operation.id != self.2);
                    if list.is_empty() {
                        operations.remove(&self.1);
                    }
                }
                drop(operations);
                self.0.notifier.notify(Topics::OPERATIONS);
            }
        }
        let _done = Done(self, tab, id);
        operation.await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::pin::pin;
    use std::task::{Context, Poll, Waker};

    #[test]
    fn a_running_commit_names_the_tab_without_blocking_it() {
        let busy = BusyService::new(Notifier::new());
        let mut run = pin!(busy.run(
            Some(7),
            BusyActivity::Commit,
            false,
            None,
            std::future::pending::<()>(),
        ));
        let mut context = Context::from_waker(Waker::noop());
        assert!(matches!(run.as_mut().poll(&mut context), Poll::Pending));
        let latest = busy.latest_of(Some(7)).expect("the commit");
        assert_eq!(latest.activity.label().0, "commitBusy");
        assert!(busy.blocking_of(Some(7)).is_none());
        assert!(busy.latest_of(Some(8)).is_none());
    }

    #[test]
    fn staging_and_discarding_have_their_own_labels() {
        assert_eq!(BusyActivity::Changes("stage").label().0, "changesBusyStage");
        assert_eq!(
            BusyActivity::Changes("discard").label().0,
            "changesBusyDiscard"
        );
    }
}
