//! Git's status accelerators (the Dart WorkingCopyCommands status
//! acceleration, the slow-status offer in RepositoryConditions and
//! StatusAccelerationSettings): the untracked cache and the file system
//! monitor, offered once per session after a slow first scan and shown in
//! the Git settings.

use crate::backend::SessionCalls;
use crate::notify::{Notifier, Topics};
use crate::session::{BackendKind, SessionIdentity};
use crate::workspace::WorkspaceService;
use gitlama_contract::dto::NativeStatusAcceleration;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// A status scan this slow is worth an offer to speed it up.
pub const SLOW_SCAN_MILLIS: u64 = 3_000;

/// Enabling would change a setting.
pub fn can_improve(acceleration: &NativeStatusAcceleration) -> bool {
    !acceleration.untracked_cache || (acceleration.fsmonitor_available && !acceleration.fsmonitor)
}

/// The last scan was slow and enabling would change a setting.
pub fn worth_offering(acceleration: &NativeStatusAcceleration) -> bool {
    acceleration
        .last_scan_millis
        .is_some_and(|millis| millis >= SLOW_SCAN_MILLIS)
        && can_improve(acceleration)
}

type Key = (u64, u64);

fn key(identity: SessionIdentity) -> Key {
    (identity.native_id, identity.generation)
}

/// The offer of one session.
#[derive(Clone, Debug, Default)]
struct Offer {
    acceleration: Option<NativeStatusAcceleration>,
    enabling: bool,
    failed: bool,
}

/// The settings view of the active session.
#[derive(Clone, Debug, Default)]
struct View {
    session: Option<Key>,
    loading: bool,
    read_failed: bool,
    acceleration: Option<NativeStatusAcceleration>,
    enabling: bool,
    enable_failed: bool,
}

#[derive(Default)]
struct Inner {
    checked: HashSet<Key>,
    dismissed: HashSet<Key>,
    offers: HashMap<Key, Offer>,
    view: View,
}

pub struct Acceleration {
    calls: Rc<dyn SessionCalls>,
    workspace: Rc<WorkspaceService>,
    notifier: Notifier,
    inner: RefCell<Inner>,
}

impl Acceleration {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        workspace: Rc<WorkspaceService>,
        notifier: Notifier,
    ) -> Rc<Self> {
        Rc::new(Self {
            calls,
            workspace,
            notifier,
            inner: RefCell::new(Inner::default()),
        })
    }

    fn changed(&self) {
        self.notifier.notify(Topics::OPERATIONS);
    }

    /// Checks once per session, after its first status scan, whether the
    /// active repository's slow status is worth speeding up.
    pub fn check_offer(self: &Rc<Self>) {
        let Some(session) = self.workspace.current() else {
            return;
        };
        if session.identity.backend != BackendKind::Local || session.snapshot.status.is_none() {
            return;
        }
        let key = key(session.identity);
        if !self.inner.borrow_mut().checked.insert(key) {
            return;
        }
        let this = Rc::clone(self);
        let request = self
            .calls
            .repository_session_status_acceleration(key.0, key.1);
        crate::rt::spawn_detached(async move {
            let acceleration = request.await.ok().and_then(|result| result.acceleration);
            let mut inner = this.inner.borrow_mut();
            if inner.dismissed.contains(&key) {
                return;
            }
            inner.offers.entry(key).or_default().acceleration = acceleration;
            drop(inner);
            this.changed();
        });
    }

    /// Hides the offer for the active session.
    pub fn dismiss(&self) {
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        let key = key(identity);
        let mut inner = self.inner.borrow_mut();
        inner.dismissed.insert(key);
        inner.offers.remove(&key);
        drop(inner);
        self.changed();
    }

    /// Reads the active repository's accelerators for the settings.
    pub async fn read(&self) {
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        let key = key(identity);
        self.inner.borrow_mut().view = View {
            session: Some(key),
            loading: identity.backend == BackendKind::Local,
            ..View::default()
        };
        self.changed();
        if identity.backend != BackendKind::Local {
            return;
        }
        let result = self
            .calls
            .repository_session_status_acceleration(key.0, key.1)
            .await;
        let mut inner = self.inner.borrow_mut();
        if inner.view.session != Some(key) {
            return;
        }
        inner.view.loading = false;
        match result.ok().and_then(|result| result.acceleration) {
            Some(acceleration) => inner.view.acceleration = Some(acceleration),
            None => inner.view.read_failed = true,
        }
        drop(inner);
        self.changed();
    }

    /// Enables the missing accelerators of the active repository, from the
    /// offer or the settings; both then show the settings in effect.
    pub async fn enable(&self, from_settings: bool) {
        let Some(identity) = self.workspace.current().map(|session| session.identity) else {
            return;
        };
        let key = key(identity);
        {
            let mut inner = self.inner.borrow_mut();
            if from_settings {
                inner.view.enabling = true;
                inner.view.enable_failed = false;
            } else {
                let offer = inner.offers.entry(key).or_default();
                offer.enabling = true;
                offer.failed = false;
            }
        }
        self.changed();
        let result = self
            .calls
            .repository_session_enable_status_acceleration(key.0, key.1)
            .await;
        let enabled = result.ok().and_then(|result| result.acceleration);
        let mut inner = self.inner.borrow_mut();
        if from_settings {
            inner.view.enabling = false;
            match &enabled {
                Some(acceleration) if inner.view.session == Some(key) => {
                    inner.view.acceleration = Some(acceleration.clone())
                }
                Some(_) => {}
                None => inner.view.enable_failed = true,
            }
            // Settings enabled elsewhere end the offer for that session.
            if enabled.is_some() {
                inner.offers.remove(&key);
            }
        } else if let Some(offer) = inner.offers.get_mut(&key) {
            offer.enabling = false;
            match enabled {
                Some(acceleration) => offer.acceleration = Some(acceleration),
                None => offer.failed = true,
            }
        }
        drop(inner);
        self.changed();
    }

    /// The offer and the settings view of the active session.
    pub fn value(&self) -> Value {
        let identity = self.workspace.current().map(|session| session.identity);
        let inner = self.inner.borrow();
        let offer = identity
            .and_then(|identity| inner.offers.get(&key(identity)))
            .and_then(|offer| {
                let acceleration = offer.acceleration.as_ref()?;
                if !offer.failed && !offer.enabling && !worth_offering(acceleration) {
                    return None;
                }
                let seconds =
                    (acceleration.last_scan_millis.unwrap_or(0) as f64 / 1000.0).round() as u64;
                Some(json!({
                    "failed": offer.failed,
                    "enabling": offer.enabling,
                    "seconds": seconds,
                    "monitor": acceleration.fsmonitor_available && !acceleration.fsmonitor,
                }))
            });
        let view = &inner.view;
        let settings = (view.session.is_some() && view.session == identity.map(key)).then(|| {
            json!({
                "remote": identity.is_some_and(|identity| identity.backend != BackendKind::Local),
                "loading": view.loading,
                "readFailed": view.read_failed || (!view.loading && view.acceleration.is_none()),
                "enabling": view.enabling,
                "enableFailed": view.enable_failed,
                "acceleration": view.acceleration.as_ref().map(|acceleration| json!({
                    "untrackedCache": acceleration.untracked_cache,
                    "fsmonitor": acceleration.fsmonitor,
                    "fsmonitorAvailable": acceleration.fsmonitor_available,
                    "lastScanMillis": acceleration.last_scan_millis,
                    "canImprove": can_improve(acceleration),
                })),
            })
        });
        json!({"offer": offer, "settings": settings})
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn acceleration(
        untracked: bool,
        monitor: bool,
        available: bool,
        scan: Option<u64>,
    ) -> NativeStatusAcceleration {
        NativeStatusAcceleration {
            untracked_cache: untracked,
            fsmonitor: monitor,
            fsmonitor_available: available,
            last_scan_millis: scan,
        }
    }

    #[test]
    fn only_slow_scans_that_can_improve_are_offered() {
        assert!(worth_offering(&acceleration(
            false,
            false,
            false,
            Some(3_000)
        )));
        assert!(!worth_offering(&acceleration(
            false,
            false,
            false,
            Some(2_999)
        )));
        assert!(!worth_offering(&acceleration(
            true,
            false,
            false,
            Some(9_000)
        )));
        assert!(worth_offering(&acceleration(
            true,
            false,
            true,
            Some(9_000)
        )));
        assert!(!worth_offering(&acceleration(
            true,
            true,
            true,
            Some(9_000)
        )));
        assert!(!worth_offering(&acceleration(false, false, true, None)));
    }
}
