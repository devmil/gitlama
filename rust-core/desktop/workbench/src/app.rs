//! The production composition of the workbench services and its bootstrap
//! (the Dart `AppComponents`, `bootstrapApp` and `AppLauncher` lifecycle).
//!
//! A failed start disposes what it built; Retry starts a fresh composition.

use crate::diagnostics;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::settings::{NativeSettingsStore, SettingsService};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

/// Where the window's startup is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StartupPhase {
    Loading,
    Failed,
    Ready,
}

/// The initialized services of one successful start (the Dart `AppRuntime`).
pub struct Services {
    pub settings: Rc<SettingsService>,
}

impl Services {
    async fn start(notifier: &Notifier) -> Result<Self, &'static str> {
        let info = rt::blocking(gitlama_core::api::core_info).await;
        if info.protocol_version != 1 {
            return Err("native_protocol_mismatch");
        }
        let settings = SettingsService::new(Rc::new(NativeSettingsStore::default()), notifier.clone());
        settings
            .initialize()
            .await
            .map_err(|_| "settings")?;
        Ok(Self { settings })
    }

    async fn dispose(&self) {
        self.settings.dispose().await;
    }
}

/// The window's application: startup, the services once ready, and shutdown.
pub struct App {
    notifier: Notifier,
    phase: Cell<StartupPhase>,
    services: RefCell<Option<Rc<Services>>>,
    attempt: Cell<u64>,
}

impl App {
    pub fn new(notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            notifier,
            phase: Cell::new(StartupPhase::Loading),
            services: RefCell::new(None),
            attempt: Cell::new(0),
        })
    }

    pub fn notifier(&self) -> &Notifier {
        &self.notifier
    }

    pub fn phase(&self) -> StartupPhase {
        self.phase.get()
    }

    pub fn services(&self) -> Option<Rc<Services>> {
        self.services.borrow().clone()
    }

    /// Starts (or, after a failure, retries) the composition.
    pub fn start(self: &Rc<Self>) {
        if self.phase.get() == StartupPhase::Ready {
            return;
        }
        let attempt = self.attempt.get() + 1;
        self.attempt.set(attempt);
        if attempt > 1 {
            diagnostics::info("Launcher", "application_bootstrap_retried", &[]);
        }
        self.set_phase(StartupPhase::Loading);
        let app = Rc::clone(self);
        rt::spawn_detached(async move {
            match Services::start(&app.notifier).await {
                Ok(services) => {
                    if app.attempt.get() != attempt {
                        services.dispose().await;
                        return;
                    }
                    *app.services.borrow_mut() = Some(Rc::new(services));
                    app.set_phase(StartupPhase::Ready);
                    app.notifier.notify(Topics::ALL);
                }
                Err(component) => {
                    diagnostics::warning(
                        "Bootstrap",
                        "application_initialization_failed",
                        &[("component", component.into())],
                    );
                    if app.attempt.get() == attempt {
                        app.set_phase(StartupPhase::Failed);
                    }
                }
            }
        });
    }

    fn set_phase(&self, phase: StartupPhase) {
        self.phase.set(phase);
        self.notifier.notify(Topics::STARTUP);
    }

    /// Disposes the services; awaited by the host before exit.
    pub async fn shutdown(&self) {
        let services = self.services.borrow_mut().take();
        if let Some(services) = services {
            services.dispose().await;
        }
    }
}
