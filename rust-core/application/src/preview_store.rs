//! One-use preview tokens of one operation family, owned per session.
//!
//! A preview records the exact plan the user confirmed under a token; execution takes it once.
//! Each session keeps a bounded number of previews, evicting the oldest idle one first, and a
//! running operation is never evicted. Closing a session cancels its running operations and
//! drops its idle previews.
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

/// A previewed plan and the state of its execution.
pub(crate) struct Owned<T> {
    pub value: T,
    pub cancellation: Arc<AtomicBool>,
    pub running: bool,
}

pub(crate) struct PreviewStore<T> {
    capacity_per_session: usize,
    next_token: u64,
    order: VecDeque<(u64, u64)>,
    entries: HashMap<(u64, u64), Owned<T>>,
}

impl<T> PreviewStore<T> {
    pub(crate) fn new(capacity_per_session: usize) -> Self {
        Self {
            capacity_per_session,
            next_token: 0,
            order: VecDeque::new(),
            entries: HashMap::new(),
        }
    }

    /// Records `value` for `session_id` and returns its token, never zero.
    pub(crate) fn issue(&mut self, session_id: u64, value: T) -> u64 {
        self.issue_evicting(session_id, value).0
    }

    /// [`Self::issue`], also returning the idle previews evicted to stay within capacity, for
    /// families that release resources with a preview.
    pub(crate) fn issue_evicting(&mut self, session_id: u64, value: T) -> (u64, Vec<T>) {
        self.next_token = self.next_token.saturating_add(1).max(1);
        let token = self.next_token;
        self.order.push_back((session_id, token));
        self.entries.insert(
            (session_id, token),
            Owned {
                value,
                cancellation: Arc::new(AtomicBool::new(false)),
                running: false,
            },
        );
        let evicted = self.trim(session_id);
        (token, evicted)
    }

    pub(crate) fn get(&self, session_id: u64, token: u64) -> Option<&Owned<T>> {
        self.entries.get(&(session_id, token))
    }

    pub(crate) fn get_mut(&mut self, session_id: u64, token: u64) -> Option<&mut Owned<T>> {
        self.entries.get_mut(&(session_id, token))
    }

    /// Requests cancellation of a running operation; false when none runs under the token.
    pub(crate) fn cancel(&self, session_id: u64, token: u64) -> bool {
        match self.entries.get(&(session_id, token)) {
            Some(owned) if owned.running => {
                owned.cancellation.store(true, Ordering::Release);
                true
            }
            _ => false,
        }
    }

    /// Removes the token after its execution ended.
    pub(crate) fn finish(&mut self, session_id: u64, token: u64) -> Option<T> {
        self.order.retain(|key| *key != (session_id, token));
        self.entries
            .remove(&(session_id, token))
            .map(|owned| owned.value)
    }

    /// Cancels the session's running operations and drops its idle previews, which it
    /// returns. A running operation keeps its entry until it finishes, so its late result is
    /// still routed.
    pub(crate) fn dismiss_session(&mut self, session_id: u64) -> Vec<T> {
        let mut dropped = Vec::new();
        let keys = self
            .entries
            .keys()
            .filter(|(owned_session, _)| *owned_session == session_id)
            .copied()
            .collect::<Vec<_>>();
        for key in keys {
            let running = self.entries.get(&key).is_some_and(|owned| {
                owned.cancellation.store(true, Ordering::Release);
                owned.running
            });
            if !running {
                if let Some(owned) = self.entries.remove(&key) {
                    dropped.push(owned.value);
                }
            }
        }
        self.order
            .retain(|(owned_session, _)| *owned_session != session_id);
        dropped
    }

    /// Cancels every operation of the session and drops all of its entries, running ones
    /// too, for families whose late results nobody collects once the session is gone.
    pub(crate) fn discard_session(&mut self, session_id: u64) -> Vec<T> {
        let mut discarded = Vec::new();
        let keys = self
            .entries
            .keys()
            .filter(|(owned_session, _)| *owned_session == session_id)
            .copied()
            .collect::<Vec<_>>();
        for key in keys {
            if let Some(owned) = self.entries.remove(&key) {
                owned.cancellation.store(true, Ordering::Release);
                discarded.push(owned.value);
            }
        }
        self.order
            .retain(|(owned_session, _)| *owned_session != session_id);
        discarded
    }

    fn trim(&mut self, session_id: u64) -> Vec<T> {
        let mut evicted = Vec::new();
        while self
            .entries
            .keys()
            .filter(|(owned_session, _)| *owned_session == session_id)
            .count()
            > self.capacity_per_session
        {
            let Some(position) = self.order.iter().position(|(owned_session, token)| {
                *owned_session == session_id
                    && self
                        .entries
                        .get(&(*owned_session, *token))
                        .is_some_and(|owned| !owned.running)
            }) else {
                break;
            };
            if let Some(key) = self.order.remove(position) {
                if let Some(owned) = self.entries.remove(&key) {
                    owned.cancellation.store(true, Ordering::Release);
                    evicted.push(owned.value);
                }
            }
        }
        evicted
    }
}

/// Previews keyed by token alone: those of one family that a session owns itself, which go
/// when the session goes, or those of the process. The same bounded store: the oldest preview
/// is evicted first.
pub(crate) struct SessionPreviews<T> {
    store: PreviewStore<T>,
}

impl<T> SessionPreviews<T> {
    /// Every session-owned store is keyed under this one session.
    const OWNER: u64 = 0;

    pub(crate) fn new(capacity: usize) -> Self {
        Self {
            store: PreviewStore::new(capacity),
        }
    }

    /// Records `value` and returns its token, never zero.
    pub(crate) fn issue(&mut self, value: T) -> u64 {
        self.store.issue(Self::OWNER, value)
    }

    /// The preview under `token`, which stays issued.
    pub(crate) fn get(&self, token: u64) -> Option<&T> {
        self.store.get(Self::OWNER, token).map(|owned| &owned.value)
    }

    /// Takes the preview under `token` for its one execution.
    pub(crate) fn take(&mut self, token: u64) -> Option<T> {
        self.store.finish(Self::OWNER, token)
    }
}

/// Locks a process-wide store, recovering from a poisoned lock: every update leaves the store
/// consistent.
pub(crate) fn lock<T>(store: &Mutex<PreviewStore<T>>) -> MutexGuard<'_, PreviewStore<T>> {
    store.lock().unwrap_or_else(PoisonError::into_inner)
}

#[cfg(test)]
mod tests {
    use super::{PreviewStore, SessionPreviews};
    use std::sync::atomic::Ordering;

    #[test]
    fn evicted_and_dismissed_previews_are_handed_back_for_cleanup() {
        let mut store = PreviewStore::new(1);
        let (first, evicted) = store.issue_evicting(1, "a");
        assert!(evicted.is_empty());
        let (second, evicted) = store.issue_evicting(1, "b");
        assert_eq!(evicted, ["a"]);
        assert!(store.get(1, first).is_none());
        store.get_mut(1, second).unwrap().running = true;
        let flag = std::sync::Arc::clone(&store.get(1, second).unwrap().cancellation);
        assert!(store.dismiss_session(1).is_empty(), "running work is kept");
        assert!(flag.load(Ordering::Acquire), "and asked to stop");
        assert_eq!(store.discard_session(1), ["b"], "discarding drops it too");
        assert!(store.get(1, second).is_none());
    }

    #[test]
    fn session_previews_are_one_use_and_bounded() {
        let mut previews = SessionPreviews::new(2);
        let first = previews.issue(1);
        let second = previews.issue(2);
        let third = previews.issue(3);
        assert!(
            previews.get(first).is_none(),
            "the oldest preview goes first"
        );
        assert_eq!(previews.get(second), Some(&2));
        assert_eq!(previews.take(third), Some(3));
        assert_eq!(previews.take(third), None, "a token runs once");
    }

    #[test]
    fn tokens_are_bounded_per_session_and_never_evict_running_work() {
        let mut store = PreviewStore::new(2);
        let first = store.issue(1, "a");
        store.get_mut(1, first).unwrap().running = true;
        let second = store.issue(1, "b");
        let third = store.issue(1, "c");
        let other = store.issue(2, "d");
        assert!(store.get(1, first).is_some(), "running work is kept");
        assert!(
            store.get(1, second).is_none(),
            "the oldest idle preview goes first"
        );
        assert!(store.get(1, third).is_some());
        assert!(store.get(2, other).is_some());
        assert!(store.cancel(1, first));
        assert!(
            !store.cancel(1, third),
            "an idle preview has nothing to cancel"
        );
        store.dismiss_session(1);
        assert!(store.get(1, third).is_none());
        assert!(
            store.get(1, first).is_some(),
            "running work routes its late result"
        );
        assert_eq!(store.finish(1, first), Some("a"));
        assert!(store.get(1, first).is_none());
        assert_ne!(first, 0);
    }
}
