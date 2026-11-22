//! Observable settings with bounded persistence scheduling (the Dart
//! `SettingsService`). The document is the native settings document; the
//! native store validates and writes it atomically at the same path the
//! Flutter application used, so an update keeps every setting.

use crate::notify::{Notifier, Topics};
use crate::rt::{self, TimerHandle};
use futures::future::{FutureExt, LocalBoxFuture, Shared};
use gitlama_contract::storage::{
    NativeSettingsDocument, NativeSettingsFailure, NativeSettingsFailureKind,
    NativeSettingsLoadState,
};
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::time::Duration;

/// A settings failure: the store's kind and the rule a rejected document broke.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SettingsError {
    pub kind: NativeSettingsFailureKind,
    pub rule: Option<String>,
}

impl SettingsError {
    fn io() -> Self {
        Self {
            kind: NativeSettingsFailureKind::Io,
            rule: None,
        }
    }

    /// The stable code diagnostics record.
    pub fn code(&self) -> String {
        let kind = format!("{:?}", self.kind);
        match &self.rule {
            Some(rule) => format!("{kind}_{rule}"),
            None => kind,
        }
    }
}

impl From<NativeSettingsFailure> for SettingsError {
    fn from(failure: NativeSettingsFailure) -> Self {
        Self {
            kind: failure.kind,
            rule: failure.rule,
        }
    }
}

/// Where and how the settings document is stored.
pub trait SettingsStore {
    fn load(&self) -> LocalBoxFuture<'static, Result<(NativeSettingsLoadState, NativeSettingsDocument), SettingsError>>;
    fn save(&self, document: NativeSettingsDocument) -> LocalBoxFuture<'static, Result<(), SettingsError>>;
}

/// The native store at the platform's settings path.
#[derive(Default)]
pub struct NativeSettingsStore {
    path: Rc<RefCell<Option<String>>>,
}

impl NativeSettingsStore {
    async fn path(cell: Rc<RefCell<Option<String>>>) -> Result<String, SettingsError> {
        if let Some(path) = cell.borrow().clone() {
            return Ok(path);
        }
        let result = rt::blocking(gitlama_core::api::application_settings_default_path).await;
        if let Some(failure) = result.failure {
            return Err(failure.into());
        }
        let path = result.path.ok_or_else(SettingsError::io)?;
        *cell.borrow_mut() = Some(path.clone());
        Ok(path)
    }
}

impl SettingsStore for NativeSettingsStore {
    fn load(&self) -> LocalBoxFuture<'static, Result<(NativeSettingsLoadState, NativeSettingsDocument), SettingsError>> {
        let cell = Rc::clone(&self.path);
        async move {
            let path = Self::path(cell).await?;
            let result =
                rt::blocking(move || gitlama_core::api::application_settings_load(path)).await;
            if let Some(failure) = result.failure {
                return Err(failure.into());
            }
            let document = result.document.ok_or(SettingsError {
                kind: NativeSettingsFailureKind::InvalidDocument,
                rule: None,
            })?;
            Ok((result.state, document))
        }
        .boxed_local()
    }

    fn save(&self, mut document: NativeSettingsDocument) -> LocalBoxFuture<'static, Result<(), SettingsError>> {
        let cell = Rc::clone(&self.path);
        async move {
            let path = Self::path(cell).await?;
            // Written as true so earlier versions keep offering remote workspaces.
            document.remote_workspaces_enabled = true;
            let result =
                rt::blocking(move || gitlama_core::api::application_settings_save(path, document))
                    .await;
            if let Some(failure) = result.failure {
                return Err(failure.into());
            }
            if !result.saved {
                return Err(SettingsError::io());
            }
            Ok(())
        }
        .boxed_local()
    }
}

type SaveFuture = Shared<LocalBoxFuture<'static, Result<(), SettingsError>>>;

struct State {
    current: NativeSettingsDocument,
    load_state: NativeSettingsLoadState,
    debounce_timer: TimerHandle,
    maximum_timer: TimerHandle,
    save_chain: SaveFuture,
    revision: u64,
    saved_revision: u64,
    scheduled_revision: u64,
    initialized: bool,
    disposed: bool,
    /// Validates a document before it is published.
    validator: Option<Rc<dyn Fn(&NativeSettingsDocument) -> Result<(), SettingsError>>>,
}

/// Owns observable settings and bounded persistence scheduling.
pub struct SettingsService {
    store: Rc<dyn SettingsStore>,
    debounce: Duration,
    maximum_flush_delay: Duration,
    notifier: Notifier,
    state: RefCell<State>,
    this: RefCell<Weak<SettingsService>>,
}

fn ready_chain() -> SaveFuture {
    futures::future::ready(Ok(())).boxed_local().shared()
}

impl SettingsService {
    pub fn new(store: Rc<dyn SettingsStore>, notifier: Notifier) -> Rc<Self> {
        Self::with_timing(
            store,
            notifier,
            Duration::from_millis(250),
            Duration::from_secs(2),
        )
    }

    pub fn with_timing(
        store: Rc<dyn SettingsStore>,
        notifier: Notifier,
        debounce: Duration,
        maximum_flush_delay: Duration,
    ) -> Rc<Self> {
        let service = Rc::new(Self {
            store,
            debounce,
            maximum_flush_delay,
            notifier,
            state: RefCell::new(State {
                current: NativeSettingsDocument::default(),
                load_state: NativeSettingsLoadState::Absent,
                debounce_timer: TimerHandle::default(),
                maximum_timer: TimerHandle::default(),
                save_chain: ready_chain(),
                revision: 0,
                saved_revision: 0,
                scheduled_revision: 0,
                initialized: false,
                disposed: false,
                validator: None,
            }),
            this: RefCell::new(Weak::new()),
        });
        *service.this.borrow_mut() = Rc::downgrade(&service);
        service
    }

    /// Installs the check every published document passes (the shortcut
    /// catalogue's conflicts).
    pub fn set_validator(
        &self,
        validator: Rc<dyn Fn(&NativeSettingsDocument) -> Result<(), SettingsError>>,
    ) {
        self.state.borrow_mut().validator = Some(validator);
    }

    pub fn current(&self) -> NativeSettingsDocument {
        self.state.borrow().current.clone()
    }

    /// Reads part of the current document without cloning it.
    pub fn with<R>(&self, read: impl FnOnce(&NativeSettingsDocument) -> R) -> R {
        read(&self.state.borrow().current)
    }

    pub fn load_state(&self) -> NativeSettingsLoadState {
        self.state.borrow().load_state
    }

    pub fn is_initialized(&self) -> bool {
        self.state.borrow().initialized
    }

    pub async fn initialize(&self) -> Result<(), SettingsError> {
        if self.state.borrow().initialized {
            return Ok(());
        }
        let (load_state, document) = self.store.load().await?;
        self.validate(&document)?;
        let mut state = self.state.borrow_mut();
        state.current = document;
        state.load_state = load_state;
        state.initialized = true;
        drop(state);
        self.notifier.notify(Topics::SETTINGS);
        Ok(())
    }

    /// Publishes `document` and schedules a background save.
    pub fn update_view(&self, document: NativeSettingsDocument) -> Result<(), SettingsError> {
        self.ensure_active()?;
        self.publish(document)?;
        let weak = self.this.borrow().clone();
        let mut state = self.state.borrow_mut();
        state.debounce_timer.cancel();
        let debounce_target = weak.clone();
        state.debounce_timer = TimerHandle::start(self.debounce, move || {
            if let Some(service) = debounce_target.upgrade() {
                service.background_flush();
            }
        });
        if !state.maximum_timer.is_active() {
            state.maximum_timer = TimerHandle::start(self.maximum_flush_delay, move || {
                if let Some(service) = weak.upgrade() {
                    service.background_flush();
                }
            });
        }
        Ok(())
    }

    /// A scheduled save has no caller to report to; the next save retries.
    fn background_flush(self: Rc<Self>) {
        let save = self.flush();
        rt::spawn_detached(async move {
            if let Err(error) = save.await {
                crate::diagnostics::warning(
                    "Settings",
                    "settings_background_save_failed",
                    &[("failure_code", error.code().into())],
                );
            }
        });
    }

    /// Applies `change` to the current document and schedules a save.
    pub fn update(
        &self,
        change: impl FnOnce(&mut NativeSettingsDocument),
    ) -> Result<(), SettingsError> {
        let mut document = self.current();
        change(&mut document);
        self.update_view(document)
    }

    /// Applies `change` and saves at once. When the store rejects the save,
    /// `restore` puts back only the section `change` wrote, taken from the
    /// document before it, into whatever is current then.
    pub async fn update_durable(
        &self,
        change: impl FnOnce(&mut NativeSettingsDocument),
        restore: impl FnOnce(&mut NativeSettingsDocument, &NativeSettingsDocument),
    ) -> Result<(), SettingsError> {
        self.ensure_active()?;
        let previous = self.current();
        let mut next = previous.clone();
        change(&mut next);
        self.publish(next)?;
        if let Err(error) = self.flush().await {
            if !self.state.borrow().disposed {
                let mut restored = self.current();
                restore(&mut restored, &previous);
                let _ = self.publish(restored);
            }
            return Err(error);
        }
        Ok(())
    }

    pub async fn save_durable(&self, document: NativeSettingsDocument) -> Result<(), SettingsError> {
        self.ensure_active()?;
        self.publish(document)?;
        self.flush().await
    }

    /// Saves the current document unless it is already saved or scheduled.
    pub fn flush(&self) -> SaveFuture {
        let mut state = self.state.borrow_mut();
        state.debounce_timer.cancel();
        state.maximum_timer.cancel();
        if state.scheduled_revision >= state.revision {
            return state.save_chain.clone();
        }
        let document = state.current.clone();
        let revision = state.revision;
        let previous = state.save_chain.clone();
        state.scheduled_revision = revision;
        let store = Rc::clone(&self.store);
        let weak = self.this.borrow().clone();
        let chain = async move {
            // A later explicit save may recover after a failed attempt.
            let _ = previous.await;
            let result = store.save(document).await;
            if let Some(service) = weak.upgrade() {
                let mut state = service.state.borrow_mut();
                match &result {
                    Ok(()) => {
                        if state.saved_revision < revision {
                            state.saved_revision = revision;
                        }
                    }
                    Err(_) => {
                        if state.scheduled_revision == revision {
                            state.scheduled_revision = state.saved_revision;
                        }
                    }
                }
            }
            result
        }
        .boxed_local()
        .shared();
        state.save_chain = chain.clone();
        // Run the save even when nobody awaits it.
        let driver = chain.clone();
        rt::spawn_detached(async move {
            let _ = driver.await;
        });
        chain
    }

    /// Flushes once and stops accepting changes.
    pub async fn dispose(&self) {
        if self.state.borrow().disposed {
            return;
        }
        self.state.borrow_mut().disposed = true;
        let _ = self.flush().await;
    }

    fn publish(&self, document: NativeSettingsDocument) -> Result<(), SettingsError> {
        self.validate(&document)?;
        let mut state = self.state.borrow_mut();
        state.current = document;
        state.revision += 1;
        drop(state);
        self.notifier.notify(Topics::SETTINGS);
        Ok(())
    }

    fn validate(&self, document: &NativeSettingsDocument) -> Result<(), SettingsError> {
        let validator = self.state.borrow().validator.clone();
        match validator {
            Some(validator) => validator(document),
            None => Ok(()),
        }
    }

    fn ensure_active(&self) -> Result<(), SettingsError> {
        let state = self.state.borrow();
        if !state.initialized || state.disposed {
            return Err(SettingsError {
                kind: NativeSettingsFailureKind::Io,
                rule: Some("service_unavailable".into()),
            });
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rt::Runtime;
    use std::cell::Cell;
    use std::time::Instant;

    #[derive(Default)]
    struct MemoryStore {
        saved: Rc<RefCell<Vec<NativeSettingsDocument>>>,
        fail: Rc<Cell<bool>>,
    }

    impl SettingsStore for MemoryStore {
        fn load(&self) -> LocalBoxFuture<'static, Result<(NativeSettingsLoadState, NativeSettingsDocument), SettingsError>> {
            async { Ok((NativeSettingsLoadState::Absent, NativeSettingsDocument::default())) }
                .boxed_local()
        }

        fn save(&self, document: NativeSettingsDocument) -> LocalBoxFuture<'static, Result<(), SettingsError>> {
            let saved = Rc::clone(&self.saved);
            let fail = self.fail.get();
            async move {
                if fail {
                    return Err(SettingsError::io());
                }
                saved.borrow_mut().push(document);
                Ok(())
            }
            .boxed_local()
        }
    }

    fn drive(runtime: &Runtime, done: impl Fn() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !done() && Instant::now() < deadline {
            runtime.run_until_stalled();
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    #[test]
    fn view_updates_coalesce_into_one_debounced_save() {
        let runtime = Runtime::install();
        let store = Rc::new(MemoryStore::default());
        let saved = Rc::clone(&store.saved);
        let service = SettingsService::with_timing(
            store,
            Notifier::new(),
            Duration::from_millis(10),
            Duration::from_secs(5),
        );
        let ready = Rc::new(Cell::new(false));
        {
            let service = Rc::clone(&service);
            let ready = Rc::clone(&ready);
            rt::spawn_detached(async move {
                service.initialize().await.unwrap();
                ready.set(true);
            });
        }
        drive(&runtime, || ready.get());
        for width in [300, 310, 320] {
            service
                .update(|document| document.appearance.sidebar_width = width)
                .unwrap();
        }
        drive(&runtime, || !saved.borrow().is_empty());
        std::thread::sleep(Duration::from_millis(30));
        runtime.run_until_stalled();
        assert_eq!(saved.borrow().len(), 1);
        assert_eq!(saved.borrow()[0].appearance.sidebar_width, 320);
    }

    #[test]
    fn a_rejected_durable_save_restores_only_its_section() {
        let runtime = Runtime::install();
        let store = Rc::new(MemoryStore::default());
        let fail = Rc::clone(&store.fail);
        let service = SettingsService::new(store, Notifier::new());
        let outcome = Rc::new(RefCell::new(None));
        {
            let service = Rc::clone(&service);
            let outcome = Rc::clone(&outcome);
            rt::spawn_detached(async move {
                service.initialize().await.unwrap();
                service
                    .update(|document| document.appearance.sidebar_width = 333)
                    .unwrap();
                let _ = service.flush().await;
                fail.set(true);
                let result = service
                    .update_durable(
                        |document| document.appearance.theme = "dark".into(),
                        |current, previous| {
                            current.appearance.theme = previous.appearance.theme.clone();
                        },
                    )
                    .await;
                *outcome.borrow_mut() = Some(result);
            });
        }
        drive(&runtime, || outcome.borrow().is_some());
        assert!(outcome.borrow().as_ref().unwrap().is_err());
        assert_eq!(service.current().appearance.theme, "system");
        assert_eq!(service.current().appearance.sidebar_width, 333);
    }
}
