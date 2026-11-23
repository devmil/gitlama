//! The production composition of the workbench services and its bootstrap
//! (the Dart `AppComponents`, `bootstrapApp` and `AppLauncher` lifecycle).
//!
//! A failed start disposes what it built; Retry starts a fresh composition.

use crate::appearances::AppearanceService;
use crate::backend::lifecycle::LocalLifecycle;
use crate::backend::{LocalCalls, SessionCalls};
use crate::diagnostics;
use crate::entry::EntryWorkflows;
use crate::history::{HistoryHooks, HistoryService};
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::rt;
use crate::settings::{NativeSettingsStore, SettingsService};
use crate::view_cache::{NoViewCache, SessionViewCache};
use crate::workspace::{NoRemotes, WorkspaceHooks, WorkspaceService};
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
    pub calls: Rc<dyn SessionCalls>,
    pub history: Rc<HistoryService>,
    pub workspace: Rc<WorkspaceService>,
    pub entry: Rc<EntryWorkflows>,
    pub appearances: Rc<AppearanceService>,
    pub prompts: Rc<Prompts>,
    pub notices: Rc<Notices>,
    pub navigator: Rc<crate::navigator::Navigator>,
    pub sidebar: Rc<crate::sidebar::SidebarService>,
    pub inspector: Rc<crate::inspector::InspectorService>,
    pub busy: Rc<crate::busy::BusyService>,
    pub changes: Rc<crate::changes::ChangesService>,
    pub working_detail: Rc<crate::working_detail::WorkingDetail>,
    pub commit: Rc<crate::commit::CommitService>,
    pub transfers: Rc<crate::transfers::TransferService>,
    pub auto_fetch: Rc<crate::auto_fetch::AutoFetchScheduler>,
    pub history_mutations: Rc<crate::history_mutations::HistoryMutations>,
    pub rebases: Rc<crate::rebases::Rebases>,
    pub integrations: Rc<crate::integrations::Integrations>,
    pub extensions: Rc<crate::extensions::Extensions>,
    pub inspector_actions: Rc<crate::inspector_actions::InspectorActions>,
    pub patches: Rc<crate::patches::PatchService>,
    pub archives: Rc<crate::archive::ArchiveService>,
    pub snapshots: Rc<crate::snapshots::SnapshotService>,
    pub conflicts: Rc<crate::conflicts::ConflictService>,
    pub operations: Rc<crate::operations::OperationCenter>,
    pub refs: Rc<crate::refs::RefService>,
    pub rewrite: Rc<crate::rewrite::RewriteService>,
}

impl Services {
    async fn start(notifier: &Notifier, prompts: Rc<Prompts>, notices: Rc<Notices>) -> Result<Self, &'static str> {
        let info = rt::blocking(gitlama_core::api::core_info).await;
        if info.protocol_version != 1 {
            return Err("native_protocol_mismatch");
        }
        let settings = SettingsService::new(Rc::new(NativeSettingsStore::default()), notifier.clone());
        settings
            .initialize()
            .await
            .map_err(|_| "settings")?;
        let calls: Rc<dyn SessionCalls> = Rc::new(LocalCalls);
        let view_cache: Rc<dyn SessionViewCache> = Rc::new(NoViewCache);
        let history = HistoryService::new(Rc::clone(&calls), notifier.clone());
        let workspace = WorkspaceService::new(
            Rc::new(LocalLifecycle { calls: Rc::clone(&calls) }),
            Rc::clone(&history),
            Some(Rc::clone(&settings)),
            Rc::clone(&view_cache),
            Rc::new(NoRemotes),
            notifier.clone(),
        );
        let entry = EntryWorkflows::new(Rc::clone(&workspace), Rc::clone(&prompts), notifier.clone());
        let appearances = AppearanceService::new(Rc::clone(&settings), notifier.clone());
        {
            let weak = Rc::downgrade(&workspace);
            let cache = Rc::clone(&view_cache);
            let remember_cache = Rc::clone(&view_cache);
            let filter_workspace = Rc::downgrade(&workspace);
            let first_page_workspace = Rc::downgrade(&workspace);
            let other_refs_settings = Rc::clone(&settings);
            history.set_hooks(HistoryHooks {
                cached_first_page: Some(Box::new(move |session| {
                    let workspace = weak.upgrade()?;
                    let tab = workspace.tab_for_session(session)?;
                    cache.history(tab.canonical_identity()?)
                })),
                on_first_page: Some(Box::new(move |session, page| {
                    let Some(workspace) = first_page_workspace.upgrade() else { return };
                    let Some(tab) = workspace.tab_for_session(session) else { return };
                    let Some(repository) = tab.canonical_identity() else { return };
                    // A branch revealed from the sidebar is gone on the next visit.
                    if crate::history::BranchFilter::of_page(page) != tab.navigation.branch_filter {
                        return;
                    }
                    remember_cache.remember_history(repository, page);
                })),
                branch_filter_for: Some(Box::new(move |session| {
                    let Some(workspace) = filter_workspace.upgrade() else {
                        return crate::history::BranchFilter::NONE;
                    };
                    workspace
                        .tab_for_session(session)
                        .map_or(crate::history::BranchFilter::NONE, |tab| workspace.shown_branch_filter(tab.id))
                })),
                other_refs: Some(Box::new(move || {
                    other_refs_settings.with(|document| document.appearance.history_other_refs)
                })),
            });
        }
        {
            let entry_prompts = Rc::downgrade(&entry);
            workspace.set_hooks(WorkspaceHooks {
                choose_repository: Some(Box::new(move || {
                    let entry = entry_prompts.clone();
                    Box::pin(async move {
                        match entry.upgrade() {
                            Some(entry) => entry.choose_directory(false).await,
                            None => None,
                        }
                    })
                })),
                on_published: None,
                on_session_closed: None,
            });
        }
        workspace.restore_workspace().await.map_err(|_| "workspace")?;
        let navigator = crate::navigator::Navigator::new(Rc::clone(&workspace), notifier.clone());
        let sidebar = crate::sidebar::SidebarService::new(
            Rc::clone(&workspace),
            Rc::clone(&settings),
            Rc::clone(&calls),
            notifier.clone(),
        );
        let inspector = crate::inspector::InspectorService::new(Rc::clone(&calls), notifier.clone());
        inspector.follow(&history);
        let busy = crate::busy::BusyService::new(notifier.clone());
        let changes = crate::changes::ChangesService::new(
            Rc::clone(&workspace),
            Rc::clone(&calls),
            Rc::clone(&busy),
            Rc::clone(&navigator),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            notifier.clone(),
        );
        let working_detail = crate::working_detail::WorkingDetail::new(
            Rc::clone(&calls),
            notifier.clone(),
            Rc::clone(&workspace),
            Rc::clone(&changes),
        );
        let commit = crate::commit::CommitService::new(
            Rc::clone(&calls),
            Rc::clone(&settings),
            Rc::clone(&workspace),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            notifier.clone(),
        );
        let transfers = crate::transfers::TransferService::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            notifier.clone(),
        );
        let auto_fetch =
            crate::auto_fetch::AutoFetchScheduler::new(Rc::clone(&settings), Rc::clone(&workspace), Rc::clone(&transfers));
        let refs = crate::refs::RefService::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&transfers),
            Rc::clone(&prompts),
            Rc::clone(&notices),
        );
        let rewrite = crate::rewrite::RewriteService::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&busy),
            Rc::clone(&navigator),
            Rc::clone(&prompts),
            Rc::clone(&notices),
        );
        let selected_history = Rc::clone(&history);
        let history_mutations = crate::history_mutations::HistoryMutations::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&busy),
            Rc::clone(&navigator),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            Box::new(move || {
                selected_history
                    .current()
                    .page
                    .map(|page| page.selected_object_ids.iter().filter(|id| id.as_str() != "wip").cloned().collect())
                    .unwrap_or_default()
            }),
        );
        let rebases = crate::rebases::Rebases::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&busy),
            Rc::clone(&navigator),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            Rc::clone(&history_mutations),
        );
        let conflicts = crate::conflicts::ConflictService::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&changes),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            notifier.clone(),
        );
        let integrations = crate::integrations::Integrations::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&history),
            Rc::clone(&settings),
            Rc::clone(&prompts),
            Rc::clone(&notices),
        );
        let inspector_actions = crate::inspector_actions::InspectorActions::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&settings),
            Rc::clone(&integrations),
            Rc::clone(&prompts),
            Rc::clone(&notices),
        );
        let patches = crate::patches::PatchService::new(Rc::clone(&calls), Rc::clone(&workspace), Rc::clone(&history), Rc::clone(&changes));
        let archives = crate::archive::ArchiveService::new(Rc::clone(&calls), Rc::clone(&workspace), Rc::clone(&notices), notifier.clone());
        let snapshots = crate::snapshots::SnapshotService::new(
            Rc::clone(&calls),
            Rc::clone(&workspace),
            Rc::clone(&navigator),
            Rc::clone(&prompts),
            Rc::clone(&notices),
            notifier.clone(),
        );
        let extensions =
            crate::extensions::Extensions::new(
                Rc::clone(&calls),
                Rc::clone(&workspace),
                Rc::clone(&sidebar),
                Rc::clone(&prompts),
                Rc::clone(&notices),
            );
        let operations = crate::operations::OperationCenter::new(notifier.clone(), Rc::clone(&transfers));
        operations.start();
        Ok(Self {
            integrations,
            extensions,
            inspector_actions,
            patches,
            archives,
            snapshots,
            operations,
            conflicts,
            rebases,
            history_mutations,
            rewrite,
            refs,
            auto_fetch,
            transfers,
            commit,
            working_detail,
            busy,
            changes,
            inspector,
            navigator,
            sidebar,
            settings,
            calls,
            history,
            workspace,
            entry,
            appearances,
            prompts,
            notices,
        })
    }

    async fn dispose(&self) {
        self.prompts.cancel_all();
        self.auto_fetch.dispose();
        self.operations.dispose();
        self.workspace.retire();
        self.workspace.close().await;
        self.history.dispose();
        self.settings.dispose().await;
    }
}

/// The window's application: startup, the services once ready, and shutdown.
pub struct App {
    notifier: Notifier,
    pub prompts: Rc<Prompts>,
    pub notices: Rc<Notices>,
    phase: Cell<StartupPhase>,
    services: RefCell<Option<Rc<Services>>>,
    attempt: Cell<u64>,
}

impl App {
    pub fn new(notifier: Notifier) -> Rc<Self> {
        Rc::new(Self {
            prompts: Rc::new(Prompts::new(notifier.clone())),
            notices: Rc::new(Notices::new(notifier.clone())),
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
            match Services::start(&app.notifier, Rc::clone(&app.prompts), Rc::clone(&app.notices)).await {
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
