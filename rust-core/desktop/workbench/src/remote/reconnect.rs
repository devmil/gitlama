//! Automatic reconnection of hosts whose open tabs lost their connection: growing pauses for a bounded time. Each attempt is a fresh connection;
//! no write is ever resent.

use super::model::{ConnectionState, Failure, Phase};
use crate::rt::{self, TimerHandle};
use futures::future::LocalBoxFuture;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::{Duration, Instant};

/// Pauses before the attempts after a loss; the last repeats.
pub const DELAYS: [Duration; 5] = [
    Duration::from_secs(2),
    Duration::from_secs(5),
    Duration::from_secs(15),
    Duration::from_secs(30),
    Duration::from_secs(60),
];
/// How long after a loss automatic attempts continue.
pub const WINDOW: Duration = Duration::from_secs(600);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReconnectPhase {
    /// The next attempt starts at `next_attempt_at`.
    Waiting,
    /// An attempt runs.
    Connecting,
    /// Automatic attempts ended; only the user starts the next one.
    Stopped,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReconnectState {
    pub phase: ReconnectPhase,
    /// Attempts made since the connection was lost.
    pub attempt: u32,
    pub next_attempt_at: Option<Instant>,
    /// Why the connection was lost or the last attempt failed.
    pub failure: Option<Failure>,
    /// Whether automatic attempts ended by themselves.
    pub gave_up: bool,
}

type Reconnect = Box<dyn Fn(String) -> LocalBoxFuture<'static, Result<ConnectionState, Failure>>>;
type Wanted = Box<dyn Fn(&str) -> bool>;

#[derive(Default)]
struct Inner {
    states: HashMap<String, ReconnectState>,
    timers: HashMap<String, TimerHandle>,
    lost_at: HashMap<String, Instant>,
    running: HashSet<String>,
    quiet: HashSet<String>,
    disposed: bool,
}

pub struct Reconnector {
    reconnect: Reconnect,
    wanted: Wanted,
    /// Runs on every change of a host's state.
    on_change: Box<dyn Fn(&str)>,
    /// Runs when a host connected again after its connection was lost (not at startup).
    on_reconnected: Box<dyn Fn(&str)>,
    inner: RefCell<Inner>,
    this: Weak<Reconnector>,
}

impl Reconnector {
    #[must_use]
    pub fn new(
        reconnect: Reconnect,
        wanted: Wanted,
        on_change: Box<dyn Fn(&str)>,
        on_reconnected: Box<dyn Fn(&str)>,
    ) -> Rc<Self> {
        Rc::new_cyclic(|this| Self {
            reconnect,
            wanted,
            on_change,
            on_reconnected,
            inner: RefCell::new(Inner::default()),
            this: this.clone(),
        })
    }

    /// The state of `profile_id`; `None` while nothing is to be done.
    #[must_use]
    pub fn state_of(&self, profile_id: &str) -> Option<ReconnectState> {
        self.inner.borrow().states.get(profile_id).cloned()
    }

    #[must_use]
    pub fn running(&self, profile_id: &str) -> bool {
        self.inner.borrow().running.contains(profile_id)
    }

    /// The connection of `profile_id` was lost: reconnect automatically when the failure
    /// allows it and tabs still need the host.
    pub fn lost(&self, profile_id: &str, failure: Option<Failure>) {
        if self.inner.borrow().disposed || !(self.wanted)(profile_id) || self.running(profile_id) {
            return;
        }
        if !failure.is_some_and(Failure::retriable) {
            self.stop_with(profile_id, failure, false);
            return;
        }
        self.inner
            .borrow_mut()
            .lost_at
            .insert(profile_id.to_owned(), Instant::now());
        self.schedule(profile_id, 0, failure, None);
    }

    /// Connects `profile_id` now, at startup, without announcing it.
    pub fn connect_soon(&self, profile_id: &str) {
        {
            let inner = self.inner.borrow();
            if inner.disposed
                || inner.running.contains(profile_id)
                || inner.states.contains_key(profile_id)
            {
                return;
            }
        }
        if !(self.wanted)(profile_id) {
            return;
        }
        {
            let mut inner = self.inner.borrow_mut();
            inner.lost_at.insert(profile_id.to_owned(), Instant::now());
            inner.quiet.insert(profile_id.to_owned());
        }
        self.schedule(profile_id, 0, None, Some(Duration::ZERO));
    }

    /// An attempt the user asked for. A failure that allows it continues the automatic
    /// attempts, from the start when they had ended.
    pub async fn reconnect_now(&self, profile_id: &str) -> Result<ConnectionState, Failure> {
        if self.running(profile_id) {
            // The attempt in progress settles the host; report where it stands.
            while self.running(profile_id) {
                rt::sleep(Duration::from_millis(100)).await;
            }
            return Err(Failure::Canceled);
        }
        let attempt = {
            let mut inner = self.inner.borrow_mut();
            inner.timers.remove(profile_id);
            let previous = inner.states.get(profile_id).cloned();
            let restart = previous
                .as_ref()
                .is_none_or(|state| state.phase == ReconnectPhase::Stopped);
            if restart {
                inner.lost_at.insert(profile_id.to_owned(), Instant::now());
                0
            } else {
                previous.map_or(0, |state| state.attempt)
            }
        };
        self.attempt(profile_id.to_owned(), attempt).await
    }

    /// Ends automatic attempts for `profile_id` until the user reconnects.
    pub fn stop(&self, profile_id: &str) {
        let failure = match self.state_of(profile_id) {
            Some(state) if state.phase != ReconnectPhase::Stopped => state.failure,
            _ => return,
        };
        self.stop_with(profile_id, failure, false);
    }

    /// The host connected or was closed outside an automatic attempt: forget it.
    pub fn settled(&self, profile_id: &str) {
        if !self.running(profile_id) {
            self.clear(profile_id);
        }
    }

    /// The host connected or no longer needs reconnecting: forget it.
    pub fn clear(&self, profile_id: &str) {
        let removed = {
            let mut inner = self.inner.borrow_mut();
            inner.timers.remove(profile_id);
            inner.lost_at.remove(profile_id);
            inner.quiet.remove(profile_id);
            inner.states.remove(profile_id).is_some() && !inner.disposed
        };
        if removed {
            (self.on_change)(profile_id);
        }
    }

    pub fn dispose(&self) {
        let mut inner = self.inner.borrow_mut();
        inner.disposed = true;
        inner.timers.clear();
    }

    fn publish(&self, profile_id: &str, state: ReconnectState) {
        let disposed = {
            let mut inner = self.inner.borrow_mut();
            inner.states.insert(profile_id.to_owned(), state);
            inner.disposed
        };
        if !disposed {
            (self.on_change)(profile_id);
        }
    }

    fn stop_with(&self, profile_id: &str, failure: Option<Failure>, gave_up: bool) {
        let attempt = {
            let mut inner = self.inner.borrow_mut();
            inner.timers.remove(profile_id);
            inner
                .states
                .get(profile_id)
                .map_or(0, |state| state.attempt)
        };
        self.publish(
            profile_id,
            ReconnectState {
                phase: ReconnectPhase::Stopped,
                attempt,
                next_attempt_at: None,
                failure,
                gave_up,
            },
        );
    }

    fn schedule(
        &self,
        profile_id: &str,
        attempt: u32,
        failure: Option<Failure>,
        delay: Option<Duration>,
    ) {
        let pause = delay.unwrap_or(DELAYS[(attempt as usize).min(DELAYS.len() - 1)]);
        let lost_at = self
            .inner
            .borrow()
            .lost_at
            .get(profile_id)
            .copied()
            .unwrap_or_else(Instant::now);
        let at = Instant::now() + pause;
        if at.duration_since(lost_at) > WINDOW {
            self.stop_with(profile_id, failure, true);
            return;
        }
        self.publish(
            profile_id,
            ReconnectState {
                phase: ReconnectPhase::Waiting,
                attempt,
                next_attempt_at: Some(at),
                failure,
                gave_up: false,
            },
        );
        let weak = self.this.clone();
        let profile = profile_id.to_owned();
        let timer = TimerHandle::start(pause, move || {
            let Some(this) = weak.upgrade() else { return };
            this.inner.borrow_mut().timers.remove(&profile);
            if this.inner.borrow().disposed {
                return;
            }
            if !(this.wanted)(&profile) {
                this.clear(&profile);
                return;
            }
            rt::spawn_detached(async move {
                let _ = this.attempt(profile, attempt).await;
            });
        });
        self.inner
            .borrow_mut()
            .timers
            .insert(profile_id.to_owned(), timer);
    }

    async fn attempt(&self, profile_id: String, attempt: u32) -> Result<ConnectionState, Failure> {
        let previous = self.state_of(&profile_id).and_then(|state| state.failure);
        self.publish(
            &profile_id,
            ReconnectState {
                phase: ReconnectPhase::Connecting,
                attempt: attempt + 1,
                next_attempt_at: None,
                failure: previous,
                gave_up: false,
            },
        );
        self.inner.borrow_mut().running.insert(profile_id.clone());
        let result = (self.reconnect)(profile_id.clone()).await;
        self.inner.borrow_mut().running.remove(&profile_id);
        if self.inner.borrow().disposed {
            return result;
        }
        if let Ok(state) = &result
            && state.ready()
        {
            let announce = !self.inner.borrow().quiet.contains(&profile_id);
            self.clear(&profile_id);
            if announce {
                (self.on_reconnected)(&profile_id);
            }
            return result;
        }
        // Only the first attempt after startup is quiet; a later one reconnects.
        self.inner.borrow_mut().quiet.remove(&profile_id);
        let failure = match &result {
            Err(failure) => Some(*failure),
            Ok(state) => state.failure,
        };
        let identity_changed =
            matches!(&result, Ok(state) if state.phase == Phase::IdentityChanged);
        if identity_changed || failure == Some(Failure::Canceled) || !(self.wanted)(&profile_id) {
            self.clear(&profile_id);
            return result;
        }
        if !failure.is_some_and(Failure::retriable) {
            self.stop_with(&profile_id, failure, false);
            return result;
        }
        self.schedule(&profile_id, attempt + 1, failure, None);
        result
    }
}
