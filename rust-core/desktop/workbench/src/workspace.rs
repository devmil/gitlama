//! The repository tabs of one window: their
//! order and groups, each tab's navigation, the active tab and its session,
//! and the sessions' events. It is the one owner of the session lifecycle.

use crate::appearance::{PALETTE_COLORS, is_color_key, is_icon, normalize_tab_name};
use crate::backend::lifecycle::SessionLifecycle;
use crate::history::{BranchFilter, HistoryService, SelectionOrigin};
use crate::notify::{Notifier, Topics};
use crate::rt::{self, PeriodicHandle};
use crate::session::{
    FailureCode, OpenedSession, SessionError, SessionIdentity, SessionResult, SessionState,
    basename, path_label,
};
use crate::settings::SettingsService;
use crate::view_cache::SessionViewCache;
use futures::future::LocalBoxFuture;
use gitlama_contract::domain::path_identity::{
    NativePathIdentity, NativePathPlatform, NativeRemoteAuthority,
};
use gitlama_contract::dto::{
    NativeRepositoryEventKind, NativeRepositoryPhase, NativeRepositorySnapshot,
    NativeRepositoryStatus,
};
use gitlama_contract::storage::{NativeTabGroup, NativeWorktreeSettings};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Pane {
    Changes,
    History,
}

impl Pane {
    pub fn name(self) -> &'static str {
        match self {
            Self::Changes => "changes",
            Self::History => "history",
        }
    }

    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "changes" => Some(Self::Changes),
            "history" => Some(Self::History),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Route {
    Repository,
    Commit,
    File,
    Blame,
    Operation,
}

impl Route {
    pub fn name(self) -> &'static str {
        match self {
            Self::Repository => "repository",
            Self::Commit => "commit",
            Self::File => "file",
            Self::Blame => "blame",
            Self::Operation => "operation",
        }
    }

    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "repository" => Some(Self::Repository),
            "commit" => Some(Self::Commit),
            "file" => Some(Self::File),
            "blame" => Some(Self::Blame),
            "operation" => Some(Self::Operation),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Navigation {
    pub pane: Pane,
    pub route: Route,
    pub selected_identity: Option<String>,
    pub changes_scroll_offset: f64,
    pub history_scroll_offset: f64,
    /// The branches this repository's history graph shows.
    pub branch_filter: BranchFilter,
}

impl Default for Navigation {
    fn default() -> Self {
        Self {
            pane: Pane::Changes,
            route: Route::Repository,
            selected_identity: None,
            changes_scroll_offset: 0.0,
            history_scroll_offset: 0.0,
            branch_filter: BranchFilter::NONE,
        }
    }
}

impl Navigation {
    fn is_default(&self) -> bool {
        self.pane == Pane::Changes
            && self.route == Route::Repository
            && self.selected_identity.is_none()
            && self.changes_scroll_offset == 0.0
            && self.history_scroll_offset == 0.0
            && self.branch_filter.is_empty()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TabPhase {
    Choosing,
    Opening,
    Open,
    Failed,
}

#[derive(Clone, Debug)]
pub struct Tab {
    pub id: u64,
    pub generation: u64,
    pub label: String,
    pub phase: TabPhase,
    pub requested_identity: Option<NativePathIdentity>,
    pub session: Option<SessionState>,
    pub failure: Option<FailureCode>,
    pub watch_overflow_revision: Option<u64>,
    pub navigation: Navigation,
    /// The tab group the tab belongs to, if any.
    pub group_id: Option<u64>,
}

impl Tab {
    fn new(id: u64, generation: u64, label: String, phase: TabPhase) -> Self {
        Self {
            id,
            generation,
            label,
            phase,
            requested_identity: None,
            session: None,
            failure: None,
            watch_overflow_revision: None,
            navigation: Navigation::default(),
            group_id: None,
        }
    }

    pub fn canonical_identity(&self) -> Option<&NativePathIdentity> {
        self.session
            .as_ref()
            .and_then(|session| session.snapshot.identity.as_ref())
            .map(|identity| &identity.worktree_root)
            .or(self.requested_identity.as_ref())
    }

    /// The repository the tab shows a worktree of, as its common Git directory.
    pub fn repository(&self) -> Option<&NativePathIdentity> {
        self.session
            .as_ref()
            .and_then(|session| session.snapshot.identity.as_ref())
            .map(|identity| &identity.common_git_dir)
    }

    /// Whether the tab shows the repository's main worktree.
    pub fn is_main_worktree(&self) -> bool {
        self.session
            .as_ref()
            .and_then(|session| session.snapshot.identity.as_ref())
            .is_none_or(|identity| identity.git_dir == identity.common_git_dir)
    }

    fn remote_profile(&self) -> Option<&str> {
        self.requested_identity
            .as_ref()
            .or(self.canonical_identity())
            .and_then(|identity| identity.remote.as_ref())
            .map(|remote| remote.profile_id.as_str())
    }
}

/// Tabs kept side by side under a name, a colour and an optional icon.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TabGroup {
    pub id: u64,
    pub name: String,
    /// A palette colour name or `rgb-rrggbb`.
    pub color: String,
    pub icon: Option<String>,
    pub collapsed: bool,
}

#[derive(Clone, Debug, Default)]
pub struct WorkspaceState {
    pub tabs: Vec<Tab>,
    pub active_tab_id: Option<u64>,
    pub groups: Vec<TabGroup>,
}

impl WorkspaceState {
    pub fn group(&self, id: Option<u64>) -> Option<&TabGroup> {
        let id = id?;
        self.groups.iter().find(|group| group.id == id)
    }

    /// The tab strip's entries: the tabs of one repository's worktrees stand
    /// side by side and form one entry.
    pub fn tab_entries(&self) -> Vec<Vec<&Tab>> {
        let mut entries: Vec<Vec<&Tab>> = Vec::new();
        for tab in &self.tabs {
            let repository = tab.repository();
            if let (Some(repository), Some(last)) = (repository, entries.last_mut())
                && last.last().and_then(|tab| tab.repository()) == Some(repository)
            {
                last.push(tab);
                continue;
            }
            entries.push(vec![tab]);
        }
        entries
    }

    pub fn entry_of(&self, tab_id: Option<u64>) -> Vec<&Tab> {
        let Some(tab_id) = tab_id else {
            return Vec::new();
        };
        self.tab_entries()
            .into_iter()
            .find(|entry| entry.iter().any(|tab| tab.id == tab_id))
            .unwrap_or_default()
    }

    /// The open worktrees of the active tab's repository when more than one.
    pub fn active_worktrees(&self) -> Vec<&Tab> {
        let entry = self.entry_of(self.active_tab_id);
        if entry.len() > 1 { entry } else { Vec::new() }
    }

    pub fn active_tab(&self) -> Option<&Tab> {
        let active = self.active_tab_id?;
        self.tabs.iter().find(|tab| tab.id == active)
    }
}

/// Why a repository could not be created on a host.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RemoteInitializeError {
    Remote(crate::remote::model::Failure),
    Session(SessionError),
}

/// What the workspace needs from remote workspaces: their states, and connecting,
/// disconnecting and creating repositories on them.
pub trait WorkspaceRemotes {
    /// Whether this window offers remote workspaces.
    fn available(&self) -> bool;
    /// Whether `authority`'s connection is established.
    fn is_live(&self, authority: &NativeRemoteAuthority) -> bool;
    /// Whether a host profile exists.
    fn has_profile(&self, profile_id: &str) -> bool;
    /// Whether the profile's connection is ready.
    fn is_ready(&self, profile_id: &str) -> bool;
    /// Forgets the verified binding of a remote path.
    fn forget_binding(&self, authority: &NativeRemoteAuthority, path: &[u16]);
    /// Connects a profile; concurrent requests share one attempt.
    fn connect(
        &self,
        profile_id: &str,
    ) -> LocalBoxFuture<
        'static,
        Result<crate::remote::model::ConnectionState, crate::remote::model::Failure>,
    >;
    /// Closes a profile's connection.
    fn disconnect(&self, profile_id: &str) -> LocalBoxFuture<'static, ()>;
    /// Creates a repository at `path` on `authority`'s connected host without opening it:
    /// the host's reason for creating nothing, or a connection failure.
    fn initialize_repository(
        &self,
        authority: &NativeRemoteAuthority,
        path: Vec<u8>,
        initial_branch: String,
        bare: bool,
    ) -> LocalBoxFuture<
        'static,
        Result<
            Option<gitlama_contract::dto::NativeRepositoryFailureKind>,
            crate::remote::model::Failure,
        >,
    >;
}

/// A window without remote workspaces.
pub struct NoRemotes;

impl WorkspaceRemotes for NoRemotes {
    fn available(&self) -> bool {
        false
    }
    fn is_live(&self, _: &NativeRemoteAuthority) -> bool {
        false
    }
    fn has_profile(&self, _: &str) -> bool {
        false
    }
    fn is_ready(&self, _: &str) -> bool {
        false
    }
    fn forget_binding(&self, _: &NativeRemoteAuthority, _: &[u16]) {}
    fn connect(
        &self,
        _: &str,
    ) -> LocalBoxFuture<
        'static,
        Result<crate::remote::model::ConnectionState, crate::remote::model::Failure>,
    > {
        Box::pin(async { Err(crate::remote::model::Failure::Unsupported) })
    }
    fn disconnect(&self, _: &str) -> LocalBoxFuture<'static, ()> {
        Box::pin(async {})
    }
    fn initialize_repository(
        &self,
        _: &NativeRemoteAuthority,
        _: Vec<u8>,
        _: String,
        _: bool,
    ) -> LocalBoxFuture<
        'static,
        Result<
            Option<gitlama_contract::dto::NativeRepositoryFailureKind>,
            crate::remote::model::Failure,
        >,
    > {
        Box::pin(async { Err(crate::remote::model::Failure::Unsupported) })
    }
}

/// The HEADs operations move to, so History selects and reveals them.
#[derive(Default)]
struct FollowedHeads {
    followed: HashMap<u64, Rc<FollowedHead>>,
    reveals: HashMap<u64, String>,
}

struct FollowedHead {
    before: Option<String>,
    finished: Cell<bool>,
}

impl FollowedHeads {
    fn take(
        &mut self,
        identity: SessionIdentity,
        snapshot: &NativeRepositorySnapshot,
    ) -> Option<String> {
        let follow = self.followed.get(&identity.native_id)?.clone();
        let head = snapshot.status.as_ref()?.head_object_id.clone()?;
        if Some(&head) == follow.before.as_ref() {
            if follow.finished.get() {
                self.followed.remove(&identity.native_id);
            }
            return None;
        }
        self.followed.remove(&identity.native_id);
        Some(head)
    }

    fn keep_reveal(&mut self, tab_id: u64, head: String) {
        self.reveals.insert(tab_id, head);
    }

    fn take_reveal(&mut self, tab_id: u64, current_head: Option<&str>) -> Option<String> {
        let kept = self.reveals.remove(&tab_id)?;
        (Some(kept.as_str()) == current_head).then_some(kept)
    }

    fn forget_tab(&mut self, tab_id: u64) {
        self.reveals.remove(&tab_id);
    }
}

struct Inner {
    tabs: Vec<Tab>,
    groups: Vec<TabGroup>,
    next_group_id: u64,
    opening_panes: HashSet<u64>,
    history_selections: HashMap<u64, String>,
    revealed_references: HashMap<u64, String>,
    current: Option<SessionState>,
    generation: u64,
    next_tab_id: u64,
    active_tab_id: Option<u64>,
    disposed: bool,
    connection_epochs: HashMap<String, u64>,
    tab_epochs: HashMap<u64, u64>,
    /// Tabs being reopened; a second request for one of them waits for none.
    reopening: HashSet<u64>,
    draining: HashSet<u64>,
    drain_tick: u64,
    heads: FollowedHeads,
    /// The tab and snapshot History was last loaded for: entering History again keeps what it
    /// shows while nothing History depends on changed.
    history_basis: Option<(u64, Rc<NativeRepositorySnapshot>)>,
}

/// Window callbacks the workspace calls.
#[derive(Default)]
pub struct WorkspaceHooks {
    /// Asks for the folder of a repository to open; None when canceled.
    pub choose_repository: Option<Box<dyn Fn() -> LocalBoxFuture<'static, Option<String>>>>,
    /// Runs after every published workspace change.
    pub on_published: Option<Box<dyn Fn()>>,
    /// Runs when a tab's session closes, so its previews are forgotten.
    pub on_session_closed: Option<Box<dyn Fn(SessionIdentity)>>,
}

pub struct WorkspaceService {
    sessions: Rc<dyn SessionLifecycle>,
    pub history: Rc<HistoryService>,
    settings: Option<Rc<SettingsService>>,
    view_cache: Rc<dyn SessionViewCache>,
    remotes: RefCell<Rc<dyn WorkspaceRemotes>>,
    hooks: RefCell<WorkspaceHooks>,
    notifier: Notifier,
    inner: RefCell<Inner>,
    drain: RefCell<PeriodicHandle>,
    drain_interval: Duration,
    revision: Cell<u64>,
    this: RefCell<Weak<WorkspaceService>>,
}

const DRAIN_HIDDEN_EVERY: u64 = 10;

impl WorkspaceService {
    pub fn new(
        sessions: Rc<dyn SessionLifecycle>,
        history: Rc<HistoryService>,
        settings: Option<Rc<SettingsService>>,
        view_cache: Rc<dyn SessionViewCache>,
        remotes: Rc<dyn WorkspaceRemotes>,
        notifier: Notifier,
    ) -> Rc<Self> {
        let service = Rc::new(Self {
            sessions,
            history,
            settings,
            view_cache,
            remotes: RefCell::new(remotes),
            hooks: RefCell::new(WorkspaceHooks::default()),
            notifier,
            inner: RefCell::new(Inner {
                tabs: Vec::new(),
                groups: Vec::new(),
                next_group_id: 1,
                opening_panes: HashSet::new(),
                history_selections: HashMap::new(),
                revealed_references: HashMap::new(),
                current: None,
                generation: 0,
                next_tab_id: 1,
                active_tab_id: None,
                disposed: false,
                connection_epochs: HashMap::new(),
                tab_epochs: HashMap::new(),
                reopening: HashSet::new(),
                draining: HashSet::new(),
                drain_tick: 0,
                heads: FollowedHeads::default(),
                history_basis: None,
            }),
            drain: RefCell::new(PeriodicHandle::default()),
            drain_interval: Duration::from_millis(20),
            revision: Cell::new(0),
            this: RefCell::new(Weak::new()),
        });
        *service.this.borrow_mut() = Rc::downgrade(&service);
        service
    }

    pub fn set_hooks(&self, hooks: WorkspaceHooks) {
        *self.hooks.borrow_mut() = hooks;
    }

    /// Installs the window's remote workspaces (they need the workspace themselves).
    pub fn set_remotes(&self, remotes: Rc<dyn WorkspaceRemotes>) {
        *self.remotes.borrow_mut() = remotes;
    }

    fn remotes(&self) -> Rc<dyn WorkspaceRemotes> {
        Rc::clone(&self.remotes.borrow())
    }

    #[allow(dead_code)]
    fn this(&self) -> Rc<Self> {
        self.this.borrow().upgrade().expect("workspace alive")
    }

    // Reads ------------------------------------------------------------------------

    pub fn workspace(&self) -> WorkspaceState {
        let inner = self.inner.borrow();
        WorkspaceState {
            tabs: inner.tabs.clone(),
            active_tab_id: inner.active_tab_id,
            groups: inner.groups.clone(),
        }
    }

    /// Reads the workspace without cloning it.
    pub fn with_tabs<R>(&self, read: impl FnOnce(&[Tab], Option<u64>, &[TabGroup]) -> R) -> R {
        let inner = self.inner.borrow();
        read(&inner.tabs, inner.active_tab_id, &inner.groups)
    }

    pub fn revision(&self) -> u64 {
        self.revision.get()
    }

    pub fn current(&self) -> Option<SessionState> {
        self.inner.borrow().current.clone()
    }

    pub fn active_tab_id(&self) -> Option<u64> {
        self.inner.borrow().active_tab_id
    }

    pub fn active_tab(&self) -> Option<Tab> {
        let inner = self.inner.borrow();
        let active = inner.active_tab_id?;
        inner.tabs.iter().find(|tab| tab.id == active).cloned()
    }

    pub fn active_canonical(&self) -> Option<NativePathIdentity> {
        self.active_tab()
            .and_then(|tab| tab.canonical_identity().cloned())
    }

    pub fn tab(&self, tab_id: u64) -> Option<Tab> {
        self.inner
            .borrow()
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .cloned()
    }

    pub fn tab_for_session(&self, session: SessionIdentity) -> Option<Tab> {
        let inner = self.inner.borrow();
        Self::index_for_session(&inner, session).map(|index| inner.tabs[index].clone())
    }

    /// The open tabs' sessions with their repositories, for background work.
    pub fn open_sessions(
        &self,
    ) -> Vec<(
        SessionIdentity,
        NativePathIdentity,
        Rc<NativeRepositorySnapshot>,
    )> {
        let inner = self.inner.borrow();
        inner
            .tabs
            .iter()
            .filter_map(|tab| {
                let session = tab.session.as_ref()?;
                let canonical = tab.canonical_identity()?.clone();
                Some((session.identity, canonical, Rc::clone(&session.snapshot)))
            })
            .collect()
    }

    pub fn next_generation(&self) -> u64 {
        let mut inner = self.inner.borrow_mut();
        inner.generation += 1;
        inner.generation
    }

    pub fn disposed(&self) -> bool {
        self.inner.borrow().disposed
    }

    // SessionScope -----------------------------------------------------------------

    pub fn ensure_active(&self) -> SessionResult<()> {
        if self.inner.borrow().disposed {
            return Err(SessionError(FailureCode::Closed));
        }
        Ok(())
    }

    pub fn require_current(&self) -> SessionResult<SessionIdentity> {
        self.ensure_active()?;
        self.inner
            .borrow()
            .current
            .as_ref()
            .map(|current| current.identity)
            .ok_or(SessionError::UNKNOWN_SESSION)
    }

    pub fn is_open(&self, identity: SessionIdentity) -> bool {
        Self::index_for_session(&self.inner.borrow(), identity).is_some()
    }

    pub async fn refresh_if_open(&self, identity: SessionIdentity) -> SessionResult<()> {
        if self.is_open(identity) {
            self.sessions.refresh(identity).await?;
        }
        Ok(())
    }

    /// Runs `operation` so History selects and reveals the HEAD it moves the
    /// session to; `moved` tells whether the outcome may have moved it.
    pub async fn following_head<T>(
        &self,
        identity: SessionIdentity,
        operation: impl std::future::Future<Output = T>,
        moved: impl FnOnce(&T) -> bool,
    ) -> T {
        let before = self.head_of(identity);
        let follow = Rc::new(FollowedHead {
            before,
            finished: Cell::new(false),
        });
        self.inner
            .borrow_mut()
            .heads
            .followed
            .insert(identity.native_id, Rc::clone(&follow));
        let result = operation.await;
        if moved(&result) {
            follow.finished.set(true);
        } else {
            let mut inner = self.inner.borrow_mut();
            if inner
                .heads
                .followed
                .get(&identity.native_id)
                .is_some_and(|current| Rc::ptr_eq(current, &follow))
            {
                inner.heads.followed.remove(&identity.native_id);
            }
        }
        result
    }

    fn head_of(&self, identity: SessionIdentity) -> Option<String> {
        let inner = self.inner.borrow();
        let index = Self::index_for_session(&inner, identity)?;
        inner.tabs[index]
            .session
            .as_ref()?
            .head_object_id()
            .map(str::to_owned)
    }

    // Restoring --------------------------------------------------------------------

    /// Reopens the saved tabs side by side; only the selected one is activated.
    pub async fn restore_workspace(self: &Rc<Self>) -> SessionResult<()> {
        self.ensure_active()?;
        let Some(settings) = self.settings.clone() else {
            return Ok(());
        };
        let (open, active, groups) = settings.with(|document| {
            (
                document.open_worktrees.clone(),
                document.active_worktree.clone(),
                document.tab_groups.clone(),
            )
        });
        self.view_cache.warm(open.clone()).await;
        if self.disposed() {
            return Ok(());
        }
        let selected = if active.as_ref().is_some_and(|active| open.contains(active)) {
            active.clone()
        } else {
            open.last().cloned()
        };
        // Groups return with the first of their tabs.
        let mut restored_groups: HashMap<usize, u64> = HashMap::new();
        let mut opening = Vec::new();
        for identity in &open {
            let group_index = groups
                .iter()
                .position(|group| group.members.contains(identity));
            let group_id = group_index.map(|index| {
                *restored_groups.entry(index).or_insert_with(|| {
                    let saved = &groups[index];
                    self.add_group(
                        saved.name.clone(),
                        Some(saved.color.clone()).filter(|key| is_color_key(key)),
                        saved.icon.clone().filter(|icon| is_icon(icon)),
                        saved.collapsed,
                    )
                })
            });
            let this = Rc::clone(self);
            let identity = identity.clone();
            let activate = Some(&identity) == selected.as_ref();
            opening.push(rt::spawn(async move {
                let start_identity = identity.clone();
                let sessions = Rc::clone(&this.sessions);
                let _ = this
                    .open_tab(
                        basename(&identity),
                        None,
                        Some(identity),
                        group_id,
                        activate,
                        move |generation| sessions.open_identity(start_identity, generation),
                    )
                    .await;
            }));
        }
        for handle in opening {
            handle.await;
        }
        if self.disposed() {
            return Ok(());
        }
        if let Some(active) = active {
            let found = self
                .inner
                .borrow()
                .tabs
                .iter()
                .find(|tab| tab.canonical_identity() == Some(&active))
                .map(|tab| tab.id);
            if let Some(tab_id) = found {
                self.activate_tab(tab_id);
            }
        }
        Ok(())
    }

    // Opening tabs ------------------------------------------------------------------

    pub fn add_repository_chooser(&self) -> u64 {
        let id = {
            let mut inner = self.inner.borrow_mut();
            let id = inner.next_tab_id;
            inner.next_tab_id += 1;
            inner.generation += 1;
            let generation = inner.generation;
            inner
                .tabs
                .push(Tab::new(id, generation, String::new(), TabPhase::Choosing));
            inner.active_tab_id = Some(id);
            inner.current = None;
            id
        };
        self.publish_workspace();
        id
    }

    pub async fn open_from_chooser(
        self: &Rc<Self>,
        tab_id: u64,
        recent: Option<NativePathIdentity>,
    ) -> SessionResult<Option<SessionState>> {
        self.ensure_active()?;
        let available = |service: &Self| {
            !service.disposed()
                && service
                    .inner
                    .borrow()
                    .tabs
                    .iter()
                    .any(|tab| tab.id == tab_id && tab.phase == TabPhase::Choosing)
        };
        if !available(self) {
            return Ok(None);
        }
        let path = match &recent {
            None => {
                let chooser = self
                    .hooks
                    .borrow()
                    .choose_repository
                    .as_ref()
                    .map(|choose| choose());
                match chooser {
                    Some(chooser) => chooser.await,
                    None => None,
                }
            }
            Some(_) => None,
        };
        if !available(self) || (recent.is_none() && path.is_none()) {
            return Ok(None);
        }
        let sessions = Rc::clone(&self.sessions);
        let state = match recent {
            Some(recent) => {
                let start = recent.clone();
                self.open_tab(
                    basename(&recent),
                    Some(tab_id),
                    Some(recent),
                    None,
                    true,
                    move |generation| sessions.open_identity(start, generation),
                )
                .await?
            }
            None => {
                let path = path.unwrap_or_default();
                let start = path.clone();
                self.open_tab(
                    path_label(&path),
                    Some(tab_id),
                    None,
                    None,
                    true,
                    move |generation| sessions.open(start, generation),
                )
                .await?
            }
        };
        Ok(Some(state))
    }

    /// Opens the repository at `path` in a new tab.
    pub async fn open(self: &Rc<Self>, path: String) -> SessionResult<SessionState> {
        let sessions = Rc::clone(&self.sessions);
        let start = path.clone();
        self.open_tab(
            path_label(&path),
            None,
            None,
            None,
            true,
            move |generation| sessions.open(start, generation),
        )
        .await
    }

    /// Opens a known repository, or activates its tab.
    pub async fn open_recent(
        self: &Rc<Self>,
        identity: NativePathIdentity,
    ) -> SessionResult<SessionState> {
        let sessions = Rc::clone(&self.sessions);
        let start = identity.clone();
        self.open_tab(
            basename(&identity),
            None,
            Some(identity),
            None,
            true,
            move |generation| sessions.open_identity(start, generation),
        )
        .await
    }

    pub async fn initialize(
        self: &Rc<Self>,
        path: String,
        initial_branch: String,
        bare: bool,
    ) -> SessionResult<SessionState> {
        let sessions = Rc::clone(&self.sessions);
        let start = path.clone();
        self.open_tab(
            path_label(&path),
            None,
            None,
            None,
            true,
            move |generation| sessions.initialize(start, generation, initial_branch, bare),
        )
        .await
    }

    /// The identity of the remote `path` of a connected host.
    pub fn remote_path_identity(
        authority: NativeRemoteAuthority,
        path: &[u8],
    ) -> NativePathIdentity {
        NativePathIdentity {
            platform: NativePathPlatform::Unix,
            units: path.iter().map(|byte| u16::from(*byte)).collect(),
            remote: Some(authority),
        }
    }

    // Remote tabs --------------------------------------------------------------------

    /// The host profile a tab belongs to.
    #[must_use]
    pub fn remote_profile_of(tab: &Tab) -> Option<String> {
        tab.remote_profile().map(str::to_owned)
    }

    /// Whether a remote tab shows state its connection no longer backs: it has no session,
    /// no connection, or a session of an earlier connection, which the host closed with it.
    #[must_use]
    pub fn is_remote_tab_stale(&self, tab: &Tab) -> bool {
        let Some(authority) = tab
            .canonical_identity()
            .or(tab.requested_identity.as_ref())
            .and_then(|identity| identity.remote.as_ref())
        else {
            return false;
        };
        let inner = self.inner.borrow();
        tab.session.is_none()
            || !self.remotes().is_live(authority)
            || inner.tab_epochs.get(&tab.id).copied()
                != Some(
                    inner
                        .connection_epochs
                        .get(&authority.profile_id)
                        .copied()
                        .unwrap_or(0),
                )
    }

    /// Whether `profile_id` has open tabs that need it, in a window offering remote
    /// workspaces.
    #[must_use]
    pub fn wants_remote(&self, profile_id: &str) -> bool {
        if self.disposed() || !self.remotes().has_profile(profile_id) {
            return false;
        }
        self.inner
            .borrow()
            .tabs
            .iter()
            .any(|tab| tab.remote_profile() == Some(profile_id))
    }

    /// The hosts of restored tabs no connection backs yet.
    #[must_use]
    pub fn stale_remote_profiles(&self) -> Vec<String> {
        let tabs = self.inner.borrow().tabs.clone();
        let mut profiles = Vec::new();
        for tab in &tabs {
            if self.is_remote_tab_stale(tab)
                && let Some(profile) = tab.remote_profile()
                && !profiles.iter().any(|known| known == profile)
            {
                profiles.push(profile.to_owned());
            }
        }
        profiles
    }

    /// A host connected (from any dialog): tabs whose sessions belong to an earlier
    /// connection reopen on this one.
    pub fn remote_connection_ready(self: &Rc<Self>, profile_id: &str) {
        *self
            .inner
            .borrow_mut()
            .connection_epochs
            .entry(profile_id.to_owned())
            .or_insert(0) += 1;
        self.publish_workspace();
        let this = Rc::clone(self);
        let profile = profile_id.to_owned();
        rt::spawn_detached(async move { this.reopen_stale_remote_tabs(&profile).await });
    }

    /// A host's connection state changed; tabs re-evaluate whether they are stale.
    pub fn remote_state_changed(&self) {
        self.publish_workspace();
    }

    /// Connects `profile_id` and reopens its tabs on the new connection. Their navigation
    /// and drafts stay; the snapshot is replaced as a whole.
    pub async fn reconnect_remote(
        self: &Rc<Self>,
        profile_id: &str,
    ) -> Result<crate::remote::model::ConnectionState, crate::remote::model::Failure> {
        let remotes = self.remotes();
        if !remotes.available() || self.disposed() {
            return Err(crate::remote::model::Failure::Unsupported);
        }
        let state = remotes.connect(profile_id).await?;
        if self.disposed() || !state.ready() {
            return Ok(state);
        }
        let tabs = self.inner.borrow().tabs.clone();
        for tab in tabs {
            if tab.remote_profile() != Some(profile_id) || tab.phase == TabPhase::Opening {
                continue;
            }
            let _ = self.reopen_tab(tab.id).await;
        }
        Ok(state)
    }

    /// Applies a changed "Allow changes" choice to a live connection: it reconnects, since
    /// write capabilities are negotiated when a connection starts, and its tabs reopen.
    pub async fn apply_remote_access(
        self: &Rc<Self>,
        profile_id: &str,
    ) -> Option<Result<crate::remote::model::ConnectionState, crate::remote::model::Failure>> {
        let remotes = self.remotes();
        if self.disposed() || !remotes.available() || !remotes.is_ready(profile_id) {
            return None;
        }
        remotes.disconnect(profile_id).await;
        if self.disposed() {
            return None;
        }
        Some(self.reconnect_remote(profile_id).await)
    }

    /// Reopens a remote tab whose repository no longer matches the one it opened, after the
    /// user chose to trust the repository found there now.
    pub async fn reopen_changed_remote_tab(
        self: &Rc<Self>,
        tab_id: u64,
    ) -> Option<SessionResult<SessionState>> {
        let tab = self.tab(tab_id)?;
        let identity = tab
            .requested_identity
            .clone()
            .or_else(|| tab.canonical_identity().cloned())?;
        let authority = identity.remote.clone()?;
        if tab.failure != Some(FailureCode::RemoteIdentityChanged) {
            return None;
        }
        self.remotes().forget_binding(&authority, &identity.units);
        self.reopen_tab(tab_id).await
    }

    async fn reopen_stale_remote_tabs(self: &Rc<Self>, profile_id: &str) {
        let tabs = self.inner.borrow().tabs.clone();
        for tab in tabs {
            if self.disposed() {
                return;
            }
            if tab.remote_profile() != Some(profile_id) || tab.phase == TabPhase::Opening {
                continue;
            }
            let Some(current) = self.tab(tab.id) else {
                continue;
            };
            if !self.is_remote_tab_stale(&current) {
                continue;
            }
            // A tab that could not reopen is left failed and offers Reconnect.
            let _ = self.reopen_tab(tab.id).await;
        }
    }

    /// Reopens a tab's repository in place, keeping its position, group and navigation. A
    /// failure leaves the tab failed with its identity.
    pub async fn reopen_tab(self: &Rc<Self>, tab_id: u64) -> Option<SessionResult<SessionState>> {
        if !self.inner.borrow_mut().reopening.insert(tab_id) {
            return None;
        }
        let result = self.reopen_tab_once(tab_id).await;
        self.inner.borrow_mut().reopening.remove(&tab_id);
        result
    }

    async fn reopen_tab_once(self: &Rc<Self>, tab_id: u64) -> Option<SessionResult<SessionState>> {
        let tab = self.tab(tab_id)?;
        let identity = tab
            .requested_identity
            .clone()
            .or_else(|| tab.canonical_identity().cloned())?;
        if let Some(previous) = tab.session.as_ref().map(|session| session.identity) {
            // The old session may belong to a closed connection.
            let _ = self.sessions.close(previous).await;
            if let Some(on_closed) = self.hooks.borrow().on_session_closed.as_ref() {
                on_closed(previous);
            }
        }
        let generation = {
            let mut inner = self.inner.borrow_mut();
            if inner.disposed {
                return None;
            }
            let index = Self::index(&inner, tab_id)?;
            inner.generation += 1;
            let generation = inner.generation;
            let mut opening = Tab::new(tab_id, generation, tab.label.clone(), TabPhase::Opening);
            opening.requested_identity = Some(identity.clone());
            opening.navigation = tab.navigation.clone();
            opening.group_id = tab.group_id;
            inner.tabs[index] = opening;
            if inner.active_tab_id == Some(tab_id) {
                inner.current = None;
            }
            generation
        };
        self.publish_workspace();
        match self.sessions.open_identity(identity, generation).await {
            Ok(opened) => {
                if self.disposed()
                    || self
                        .tab(tab_id)
                        .is_none_or(|tab| tab.generation != generation)
                {
                    let _ = self.sessions.close(opened.identity).await;
                    return Some(Err(SessionError(FailureCode::StaleGeneration)));
                }
                let state = self.adopt(opened, Some(tab_id), Some(tab.label.clone()));
                if self.active_tab_id() == Some(tab_id) {
                    self.activate_tab(tab_id);
                }
                Some(Ok(state))
            }
            Err(error) => {
                {
                    let mut inner = self.inner.borrow_mut();
                    if let Some(index) = Self::index(&inner, tab_id) {
                        inner.tabs[index].phase = TabPhase::Failed;
                        inner.tabs[index].failure = Some(error.code());
                    }
                }
                self.publish_workspace();
                Some(Err(error))
            }
        }
    }

    /// Creates a repository at `path` on `authority`'s connected host and opens it in a new
    /// tab. The host's reasons for creating nothing are the failures of initializing a
    /// repository on this computer.
    pub async fn initialize_remote(
        self: &Rc<Self>,
        authority: NativeRemoteAuthority,
        path: Vec<u8>,
        initial_branch: String,
        bare: bool,
    ) -> Result<SessionState, RemoteInitializeError> {
        self.ensure_active()
            .map_err(RemoteInitializeError::Session)?;
        let remotes = self.remotes();
        if !remotes.available() {
            return Err(RemoteInitializeError::Remote(
                crate::remote::model::Failure::Unsupported,
            ));
        }
        let failure = remotes
            .initialize_repository(&authority, path.clone(), initial_branch, bare)
            .await
            .map_err(RemoteInitializeError::Remote)?;
        if let Some(kind) = failure {
            let failure = gitlama_contract::dto::NativeRepositoryFailure { kind };
            return Err(RemoteInitializeError::Session(SessionError(
                FailureCode::from(&failure),
            )));
        }
        self.ensure_active()
            .map_err(RemoteInitializeError::Session)?;
        self.open_recent(Self::remote_path_identity(authority, &path))
            .await
            .map_err(RemoteInitializeError::Session)
    }

    /// Opens a session that opened outside the workspace (a finished clone).
    pub async fn adopt_opened(
        self: &Rc<Self>,
        opened: OpenedSession,
        current: bool,
    ) -> SessionResult<SessionState> {
        if self.disposed() || !current {
            let _ = self.sessions.close(opened.identity).await;
            return Err(SessionError(FailureCode::StaleGeneration));
        }
        let label = opened
            .snapshot
            .identity
            .as_ref()
            .map(|identity| basename(&identity.worktree_root))
            .unwrap_or_default();
        Ok(self.adopt(opened, None, Some(label)))
    }

    #[allow(clippy::too_many_arguments)]
    async fn open_tab(
        self: &Rc<Self>,
        label: String,
        replace_tab_id: Option<u64>,
        requested_identity: Option<NativePathIdentity>,
        group_id: Option<u64>,
        activate: bool,
        start: impl FnOnce(u64) -> LocalBoxFuture<'static, SessionResult<OpenedSession>>,
    ) -> SessionResult<SessionState> {
        self.ensure_active()?;
        if let Some(requested) = &requested_identity {
            let existing = self
                .inner
                .borrow()
                .tabs
                .iter()
                .find(|tab| {
                    tab.session.is_some()
                        && (tab.canonical_identity() == Some(requested)
                            || tab.requested_identity.as_ref() == Some(requested))
                })
                .map(|tab| (tab.id, tab.session.clone()));
            if let Some((existing_id, session)) = existing {
                if let Some(replace) = replace_tab_id {
                    self.inner.borrow_mut().tabs.retain(|tab| tab.id != replace);
                }
                if activate {
                    self.activate_tab(existing_id);
                }
                return session.ok_or(SessionError::UNKNOWN_SESSION);
            }
        }
        let navigation = self.navigation_for(requested_identity.as_ref());
        let (generation, tab_id) = {
            let mut inner = self.inner.borrow_mut();
            inner.generation += 1;
            let generation = inner.generation;
            let tab_id = replace_tab_id.unwrap_or_else(|| {
                let id = inner.next_tab_id;
                inner.next_tab_id += 1;
                id
            });
            let replaced = replace_tab_id.and_then(|id| Self::index(&inner, id));
            let mut opening = Tab::new(tab_id, generation, label.clone(), TabPhase::Opening);
            opening.requested_identity = requested_identity.clone();
            opening.navigation = navigation;
            opening.group_id = match replaced {
                Some(index) => inner.tabs[index].group_id,
                None => group_id,
            };
            match replaced {
                Some(index) => inner.tabs[index] = opening,
                None => inner.tabs.push(opening),
            }
            if activate || inner.active_tab_id.is_none() {
                inner.active_tab_id = Some(tab_id);
                inner.current = None;
            }
            (generation, tab_id)
        };
        self.publish_workspace();
        let opened = match start(generation).await {
            Ok(opened) => opened,
            Err(error) => {
                {
                    let mut inner = self.inner.borrow_mut();
                    if let Some(index) = Self::index(&inner, tab_id) {
                        if replace_tab_id.is_none() {
                            inner.tabs[index].phase = TabPhase::Failed;
                            inner.tabs[index].failure = Some(error.code());
                        } else {
                            let group = inner.tabs[index].group_id;
                            let mut choosing =
                                Tab::new(tab_id, generation, String::new(), TabPhase::Choosing);
                            choosing.failure = Some(error.code());
                            choosing.group_id = group;
                            inner.tabs[index] = choosing;
                        }
                    }
                }
                self.publish_workspace();
                return Err(error);
            }
        };
        if self.disposed() || Self::index(&self.inner.borrow(), tab_id).is_none() {
            let _ = self.sessions.close(opened.identity).await;
            return Err(SessionError(FailureCode::StaleGeneration));
        }
        if let Some(canonical) = opened
            .snapshot
            .identity
            .as_ref()
            .map(|identity| identity.worktree_root.clone())
        {
            let duplicate = self
                .inner
                .borrow()
                .tabs
                .iter()
                .find(|tab| {
                    tab.id != tab_id
                        && tab.session.is_some()
                        && (tab.canonical_identity() == Some(&canonical)
                            || tab.requested_identity.as_ref() == Some(&canonical))
                })
                .map(|tab| (tab.id, tab.session.clone()));
            if let Some((duplicate_id, session)) = duplicate {
                let _ = self.sessions.close(opened.identity).await;
                let replaced_active = {
                    let mut inner = self.inner.borrow_mut();
                    let replaced_active = inner.active_tab_id == Some(tab_id);
                    inner.tabs.retain(|tab| tab.id != tab_id);
                    replaced_active
                };
                if activate || replaced_active {
                    self.activate_tab(duplicate_id);
                } else {
                    self.publish_workspace();
                }
                return session.ok_or(SessionError::UNKNOWN_SESSION);
            }
        }
        Ok(self.adopt(opened, Some(tab_id), Some(label)))
    }

    fn adopt(
        self: &Rc<Self>,
        opened: OpenedSession,
        tab_id: Option<u64>,
        label: Option<String>,
    ) -> SessionState {
        let presented = Rc::new(self.view_cache.present(&opened.snapshot));
        self.view_cache.remember(&opened.snapshot);
        let state = SessionState {
            identity: opened.identity,
            snapshot: Rc::clone(&presented),
            transport_failure: None,
        };
        let worktree_root = opened
            .snapshot
            .identity
            .as_ref()
            .map(|identity| identity.worktree_root.clone());
        let load_history_for;
        {
            let mut inner = self.inner.borrow_mut();
            let effective = tab_id.unwrap_or_else(|| {
                let id = inner.next_tab_id;
                inner.next_tab_id += 1;
                id
            });
            let index = Self::index(&inner, effective);
            let existing = index.map(|index| inner.tabs[index].clone());
            drop(inner);
            let navigation = match &existing {
                None => self.navigation_for(worktree_root.as_ref()),
                Some(existing) if existing.navigation.is_default() => self.navigation_for(
                    worktree_root
                        .as_ref()
                        .or(existing.requested_identity.as_ref()),
                ),
                Some(existing) => existing.navigation.clone(),
            };
            let mut inner = self.inner.borrow_mut();
            let tab = Tab {
                id: effective,
                generation: opened.identity.generation,
                label: label
                    .or_else(|| existing.as_ref().map(|tab| tab.label.clone()))
                    .unwrap_or_else(|| worktree_root.as_ref().map(basename).unwrap_or_default()),
                phase: TabPhase::Open,
                requested_identity: existing
                    .as_ref()
                    .and_then(|tab| tab.requested_identity.clone()),
                session: Some(state.clone()),
                failure: None,
                watch_overflow_revision: None,
                navigation,
                group_id: existing.as_ref().and_then(|tab| tab.group_id),
            };
            let remote_profile = tab.remote_profile().map(str::to_owned);
            match Self::index(&inner, effective) {
                Some(index) => inner.tabs[index] = tab,
                None => inner.tabs.push(tab),
            }
            let open_ids: HashSet<u64> = inner.tabs.iter().map(|tab| tab.id).collect();
            inner.tab_epochs.retain(|id, _| open_ids.contains(id));
            match remote_profile {
                None => {
                    inner.tab_epochs.remove(&effective);
                }
                Some(profile) => {
                    let epoch = inner.connection_epochs.get(&profile).copied().unwrap_or(0);
                    inner.tab_epochs.insert(effective, epoch);
                }
            }
            if tab_id.is_none() {
                inner.active_tab_id = Some(effective);
            }
            load_history_for = if inner.active_tab_id == Some(effective) {
                inner.current = Some(state.clone());
                let index = Self::index(&inner, effective).expect("adopted tab");
                (inner.tabs[index].navigation.pane == Pane::History).then_some(effective)
            } else {
                None
            };
            inner.opening_panes.insert(effective);
            drop(inner);
            if let Some(tab_id) = load_history_for {
                self.load_history_for_tab(tab_id, true, None);
            }
            self.choose_opening_pane(effective, &opened.snapshot);
        }
        self.record_recent(&presented);
        self.start_drain();
        self.publish_workspace();
        state
    }

    /// Shows History for a repository that opens without local changes.
    fn choose_opening_pane(self: &Rc<Self>, tab_id: u64, loaded: &NativeRepositorySnapshot) {
        let load = {
            let mut inner = self.inner.borrow_mut();
            if !inner.opening_panes.contains(&tab_id) {
                return;
            }
            let Some(index) = Self::index(&inner, tab_id) else {
                inner.opening_panes.remove(&tab_id);
                return;
            };
            if loaded.status.is_some() || loaded.status_failure.is_some() {
                inner.opening_panes.remove(&tab_id);
            }
            let tab = &inner.tabs[index];
            let Some(status) = tab
                .session
                .as_ref()
                .and_then(|session| session.snapshot.status.as_ref())
            else {
                return;
            };
            if !status.entries.is_empty() || !status.operations.is_empty() {
                return;
            }
            inner.opening_panes.remove(&tab_id);
            if inner.tabs[index].navigation.pane != Pane::Changes {
                return;
            }
            let navigation = &mut inner.tabs[index].navigation;
            navigation.pane = Pane::History;
            navigation.route = Route::Repository;
            navigation.selected_identity = None;
            inner.active_tab_id == Some(tab_id)
        };
        if load {
            self.load_history_for_tab(tab_id, true, None);
        }
    }

    // Tabs and groups -------------------------------------------------------------

    pub fn activate_tab(self: &Rc<Self>, tab_id: u64) {
        let load = {
            let mut inner = self.inner.borrow_mut();
            if inner.disposed || inner.active_tab_id == Some(tab_id) {
                return;
            }
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            Self::expand_group_of(&mut inner, index);
            if let Some(previous) = inner.active_tab_id {
                inner.revealed_references.remove(&previous);
            }
            inner.active_tab_id = Some(tab_id);
            inner.current = inner.tabs[index].session.clone();
            inner.tabs[index].navigation.pane == Pane::History
        };
        self.history.clear();
        if load {
            self.load_history_for_tab(tab_id, true, None);
        }
        self.publish_workspace();
    }

    pub fn reorder_tab(&self, tab_id: u64, target_index: usize) {
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            if inner.tabs.len() < 2 {
                return;
            }
            let bounded = target_index.min(inner.tabs.len() - 1);
            if index == bounded {
                return;
            }
            let tab = inner.tabs.remove(index);
            inner.tabs.insert(bounded, tab.clone());
            let before = if bounded > 0 {
                inner.tabs[bounded - 1].group_id
            } else {
                None
            };
            let after = if bounded + 1 < inner.tabs.len() {
                inner.tabs[bounded + 1].group_id
            } else {
                None
            };
            let group = if before.is_some() && before == after {
                before
            } else if tab.group_id.is_some() && (before == tab.group_id || after == tab.group_id) {
                tab.group_id
            } else {
                None
            };
            inner.tabs[bounded].group_id = group;
            Self::keep_worktrees_together(&mut inner, Some(tab_id));
            Self::keep_groups_together(&mut inner);
        }
        self.publish_workspace();
    }

    /// Puts `tab_id` at `target_index` in `group_id`, or in no group.
    pub fn move_tab(&self, tab_id: u64, target_index: usize, group_id: Option<u64>) {
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            let group = group_id.filter(|id| Self::group_index(&inner, *id).is_some());
            let mut tab = inner.tabs.remove(index);
            tab.group_id = group;
            let target = target_index.min(inner.tabs.len());
            inner.tabs.insert(target, tab);
            Self::keep_worktrees_together(&mut inner, Some(tab_id));
            Self::keep_groups_together(&mut inner);
        }
        self.publish_workspace();
    }

    /// Puts `tab_id` at `target_index` among the other open worktrees of its
    /// repository.
    pub fn move_worktree_tab(&self, tab_id: u64, target_index: i64) {
        let others: Vec<u64> = {
            let state = self.workspace();
            state
                .entry_of(Some(tab_id))
                .iter()
                .filter(|tab| tab.id != tab_id)
                .map(|tab| tab.id)
                .collect()
        };
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            if others.is_empty() {
                return;
            }
            let tab = inner.tabs.remove(index);
            let target = if target_index < 0 {
                Self::index(&inner, others[0]).unwrap_or(0)
            } else if (target_index as usize) < others.len() {
                Self::index(&inner, others[target_index as usize]).unwrap_or(0)
            } else {
                Self::index(&inner, *others.last().expect("others")).map_or(0, |index| index + 1)
            };
            let target = target.min(inner.tabs.len());
            inner.tabs.insert(target, tab);
        }
        self.publish_workspace();
    }

    /// Moves every tab of `group_id` so the group starts at `target_index`.
    pub fn move_tab_group(&self, group_id: u64, target_index: usize) {
        {
            let mut inner = self.inner.borrow_mut();
            if Self::group_index(&inner, group_id).is_none() {
                return;
            }
            let members: Vec<Tab> = inner
                .tabs
                .iter()
                .filter(|tab| tab.group_id == Some(group_id))
                .cloned()
                .collect();
            if members.is_empty() {
                return;
            }
            inner.tabs.retain(|tab| tab.group_id != Some(group_id));
            let mut target = target_index.min(inner.tabs.len());
            if target > 0 && target < inner.tabs.len() {
                let split = inner.tabs[target - 1].group_id;
                if split.is_some() && split == inner.tabs[target].group_id {
                    target = inner
                        .tabs
                        .iter()
                        .rposition(|tab| tab.group_id == split)
                        .map_or(target, |index| index + 1);
                }
            }
            for (offset, member) in members.into_iter().enumerate() {
                inner.tabs.insert(target + offset, member);
            }
        }
        self.publish_workspace();
    }

    /// Gives `group_id` its name, colour and icon at once.
    pub fn edit_tab_group(&self, group_id: u64, name: &str, color: &str, icon: Option<&str>) {
        let name = normalize_tab_name(name).unwrap_or_default();
        let color = color.to_owned();
        let icon = icon.filter(|icon| is_icon(icon)).map(str::to_owned);
        self.update_group(group_id, |group| {
            group.name = name;
            if is_color_key(&color) {
                group.color = color;
            }
            group.icon = icon;
        });
    }

    /// Puts `tab_id` in a new group with the first colour no group has.
    pub fn create_tab_group(&self, tab_id: u64) -> Option<u64> {
        let group_id = {
            let mut inner = self.inner.borrow_mut();
            let index = Self::index(&inner, tab_id)?;
            let used: HashSet<&str> = inner
                .groups
                .iter()
                .map(|group| group.color.as_str())
                .collect();
            let color = PALETTE_COLORS
                .iter()
                .find(|color| !used.contains(**color))
                .copied()
                .unwrap_or(PALETTE_COLORS[inner.groups.len() % PALETTE_COLORS.len()])
                .to_owned();
            let group_id = Self::add_group_to(&mut inner, String::new(), Some(color), None, false);
            Self::move_into_group(&mut inner, index, group_id);
            Self::keep_worktrees_together(&mut inner, Some(tab_id));
            group_id
        };
        self.publish_workspace();
        Some(group_id)
    }

    pub fn add_tab_to_group(&self, tab_id: u64, group_id: u64) {
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            if Self::group_index(&inner, group_id).is_none()
                || inner.tabs[index].group_id == Some(group_id)
            {
                return;
            }
            Self::move_into_group(&mut inner, index, group_id);
            Self::keep_worktrees_together(&mut inner, Some(tab_id));
        }
        self.publish_workspace();
    }

    /// Takes `tab_id` out of its group; it stands right after the group.
    pub fn remove_tab_from_group(&self, tab_id: u64) {
        let worktrees = self.worktree_ids(tab_id);
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            let Some(group_id) = inner.tabs[index].group_id else {
                return;
            };
            let mut tab = inner.tabs.remove(index);
            tab.group_id = None;
            let last = inner
                .tabs
                .iter()
                .rposition(|item| item.group_id == Some(group_id) && !worktrees.contains(&item.id));
            let target = last.map_or(0, |last| last + 1);
            inner.tabs.insert(target, tab);
            Self::keep_worktrees_together(&mut inner, Some(tab_id));
        }
        self.publish_workspace();
    }

    pub fn rename_tab_group(&self, group_id: u64, name: &str) {
        let name = normalize_tab_name(name).unwrap_or_default();
        self.update_group(group_id, |group| group.name = name);
    }

    /// Collapses or expands `group_id`. Collapsing the active tab's group
    /// activates the nearest tab outside it; with none, it stays open.
    pub fn set_tab_group_collapsed(self: &Rc<Self>, group_id: u64, collapsed: bool) {
        let replacement = {
            let mut inner = self.inner.borrow_mut();
            let Some(group_index) = Self::group_index(&inner, group_id) else {
                return;
            };
            if inner.groups[group_index].collapsed == collapsed {
                return;
            }
            let active_index = inner.active_tab_id.and_then(|id| Self::index(&inner, id));
            if collapsed
                && let Some(active_index) = active_index
                && inner.tabs[active_index].group_id == Some(group_id)
            {
                let Some(replacement) =
                    Self::visible_neighbour(&inner, active_index, Some(group_id))
                else {
                    return;
                };
                inner.groups[group_index].collapsed = true;
                Some(replacement)
            } else {
                inner.groups[group_index].collapsed = collapsed;
                None
            }
        };
        match replacement {
            Some(tab_id) => self.activate_tab(tab_id),
            None => self.publish_workspace(),
        }
    }

    /// Dissolves `group_id`; its tabs stay open where they are.
    pub fn ungroup_tabs(&self, group_id: u64) {
        {
            let mut inner = self.inner.borrow_mut();
            if Self::group_index(&inner, group_id).is_none() {
                return;
            }
            for tab in &mut inner.tabs {
                if tab.group_id == Some(group_id) {
                    tab.group_id = None;
                }
            }
            inner.groups.retain(|group| group.id != group_id);
        }
        self.publish_workspace();
    }

    pub async fn close_tabs(self: &Rc<Self>, tab_ids: Vec<u64>) {
        for tab_id in tab_ids {
            if self.disposed() {
                return;
            }
            self.close_tab(tab_id).await;
        }
    }

    pub async fn close_tab_group(self: &Rc<Self>, group_id: u64) {
        let members: Vec<u64> = self
            .inner
            .borrow()
            .tabs
            .iter()
            .filter(|tab| tab.group_id == Some(group_id))
            .map(|tab| tab.id)
            .collect();
        self.close_tabs(members).await;
    }

    fn add_group(
        &self,
        name: String,
        color: Option<String>,
        icon: Option<String>,
        collapsed: bool,
    ) -> u64 {
        Self::add_group_to(&mut self.inner.borrow_mut(), name, color, icon, collapsed)
    }

    fn add_group_to(
        inner: &mut Inner,
        name: String,
        color: Option<String>,
        icon: Option<String>,
        collapsed: bool,
    ) -> u64 {
        let id = inner.next_group_id;
        inner.next_group_id += 1;
        inner.groups.push(TabGroup {
            id,
            name,
            color: color.unwrap_or_else(|| PALETTE_COLORS[0].to_owned()),
            icon,
            collapsed,
        });
        id
    }

    fn group_index(inner: &Inner, group_id: u64) -> Option<usize> {
        inner.groups.iter().position(|group| group.id == group_id)
    }

    fn update_group(&self, group_id: u64, update: impl FnOnce(&mut TabGroup)) {
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::group_index(&inner, group_id) else {
                return;
            };
            let mut next = inner.groups[index].clone();
            update(&mut next);
            if next == inner.groups[index] {
                return;
            }
            inner.groups[index] = next;
        }
        self.publish_workspace();
    }

    fn move_into_group(inner: &mut Inner, index: usize, group_id: u64) {
        let state = WorkspaceState {
            tabs: inner.tabs.clone(),
            active_tab_id: inner.active_tab_id,
            groups: inner.groups.clone(),
        };
        let worktrees: HashSet<u64> = state
            .entry_of(Some(inner.tabs[index].id))
            .iter()
            .map(|tab| tab.id)
            .collect();
        let mut tab = inner.tabs.remove(index);
        let previous = tab.group_id;
        let last = inner
            .tabs
            .iter()
            .rposition(|item| item.group_id == Some(group_id) && !worktrees.contains(&item.id));
        let previous_last = previous.and_then(|previous| {
            inner
                .tabs
                .iter()
                .rposition(|item| item.group_id == Some(previous) && !worktrees.contains(&item.id))
        });
        let target = match (last, previous_last) {
            (Some(last), _) => last + 1,
            (None, Some(previous_last)) => previous_last + 1,
            (None, None) => index,
        };
        tab.group_id = Some(group_id);
        let target = target.min(inner.tabs.len());
        inner.tabs.insert(target, tab);
    }

    /// Gathers each group's tabs where its first tab stands, keeping order.
    fn keep_groups_together(inner: &mut Inner) {
        let mut placed = HashSet::new();
        let mut ordered = Vec::with_capacity(inner.tabs.len());
        for tab in &inner.tabs {
            match tab.group_id {
                None => ordered.push(tab.clone()),
                Some(group) => {
                    if placed.insert(group) {
                        ordered.extend(
                            inner
                                .tabs
                                .iter()
                                .filter(|item| item.group_id == Some(group))
                                .cloned(),
                        );
                    }
                }
            }
        }
        inner.tabs = ordered;
    }

    fn worktree_ids(&self, tab_id: u64) -> HashSet<u64> {
        self.workspace()
            .entry_of(Some(tab_id))
            .iter()
            .map(|tab| tab.id)
            .collect()
    }

    /// Gathers the open worktrees of each repository where its leader tab
    /// stands, or its first tab, in the leader's group.
    fn keep_worktrees_together(inner: &mut Inner, leader: Option<u64>) {
        let mut worktrees: HashMap<NativePathIdentity, Vec<u64>> = HashMap::new();
        for tab in &inner.tabs {
            if let Some(repository) = tab.repository() {
                worktrees
                    .entry(repository.clone())
                    .or_default()
                    .push(tab.id);
            }
        }
        if !worktrees.values().any(|tabs| tabs.len() > 1) {
            return;
        }
        let by_id: HashMap<u64, Tab> = inner.tabs.iter().map(|tab| (tab.id, tab.clone())).collect();
        let mut ordered = Vec::with_capacity(inner.tabs.len());
        for tab in &inner.tabs {
            let members = tab
                .repository()
                .and_then(|repository| worktrees.get(repository));
            let Some(members) = members.filter(|members| members.len() >= 2) else {
                ordered.push(tab.clone());
                continue;
            };
            let anchor = if leader.is_some_and(|leader| members.contains(&leader)) {
                leader.expect("leader")
            } else {
                members[0]
            };
            if tab.id != anchor {
                continue;
            }
            let group = tab.group_id;
            for member in members {
                let mut member = by_id[member].clone();
                member.group_id = group;
                ordered.push(member);
            }
        }
        inner.tabs = ordered;
    }

    /// Drops groups without tabs and opens the active tab's group.
    fn settle_groups(inner: &mut Inner) {
        let used: HashSet<Option<u64>> = inner.tabs.iter().map(|tab| tab.group_id).collect();
        inner.groups.retain(|group| used.contains(&Some(group.id)));
        if let Some(active) = inner.active_tab_id.and_then(|id| Self::index(inner, id)) {
            Self::expand_group_of(inner, active);
        }
    }

    fn expand_group_of(inner: &mut Inner, tab_index: usize) {
        let Some(group_id) = inner.tabs[tab_index].group_id else {
            return;
        };
        if let Some(index) = Self::group_index(inner, group_id)
            && inner.groups[index].collapsed
        {
            inner.groups[index].collapsed = false;
        }
    }

    fn hidden(inner: &Inner, tab: &Tab) -> bool {
        inner
            .groups
            .iter()
            .any(|group| Some(group.id) == tab.group_id && group.collapsed)
    }

    /// The closest shown tab to `index` outside `except`, looking right first.
    fn visible_neighbour(inner: &Inner, index: usize, except: Option<u64>) -> Option<u64> {
        let count = inner.tabs.len() as i64;
        for distance in 1..count {
            for candidate in [index as i64 + distance, index as i64 - distance] {
                if candidate < 0 || candidate >= count {
                    continue;
                }
                let tab = &inner.tabs[candidate as usize];
                if tab.group_id.is_some() && tab.group_id == except {
                    continue;
                }
                if !Self::hidden(inner, tab) {
                    return Some(tab.id);
                }
            }
        }
        None
    }

    /// Closes every tab of the worktree `root` except the one of `source`,
    /// and returns the worktrees it closed.
    pub async fn close_worktree_tabs(
        self: &Rc<Self>,
        root: &NativePathIdentity,
        source: SessionIdentity,
    ) -> Vec<NativePathIdentity> {
        let affected: Vec<u64> = self
            .inner
            .borrow()
            .tabs
            .iter()
            .filter(|tab| {
                tab.session.as_ref().map(|session| session.identity) != Some(source)
                    && tab.canonical_identity() == Some(root)
            })
            .map(|tab| tab.id)
            .collect();
        let mut closed = Vec::new();
        for tab_id in affected {
            closed.push(root.clone());
            self.close_tab(tab_id).await;
        }
        closed
    }

    /// Reopens `worktrees` and activates `source`'s tab again.
    pub async fn restore_worktree_tabs(
        self: &Rc<Self>,
        worktrees: Vec<NativePathIdentity>,
        source: SessionIdentity,
    ) {
        for worktree in worktrees {
            // A concurrent external delete makes reopening impossible.
            let _ = self.open_recent(worktree).await;
        }
        if let Some(tab) = self.tab_for_session(source) {
            self.activate_tab(tab.id);
        }
    }

    pub async fn close_tab(self: &Rc<Self>, tab_id: u64) {
        let (removed, was_active, index) = {
            let mut inner = self.inner.borrow_mut();
            if inner.disposed {
                return;
            }
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            let was_active = inner.active_tab_id == Some(tab_id);
            let removed = inner.tabs.remove(index);
            inner.history_selections.remove(&tab_id);
            inner.heads.forget_tab(tab_id);
            inner.revealed_references.remove(&tab_id);
            inner.opening_panes.remove(&tab_id);
            (removed, was_active, index)
        };
        if let Some(session) = &removed.session {
            if let Some(hook) = &self.hooks.borrow().on_session_closed {
                hook(session.identity);
            }
            let _ = self.sessions.close(session.identity).await;
        }
        if was_active {
            self.history.clear();
            let load = {
                let mut inner = self.inner.borrow_mut();
                if inner.tabs.is_empty() {
                    inner.active_tab_id = None;
                    inner.current = None;
                    None
                } else {
                    let nearest = index.min(inner.tabs.len() - 1);
                    let replacement = if !Self::hidden(&inner, &inner.tabs[nearest]) {
                        inner.tabs[nearest].id
                    } else {
                        Self::visible_neighbour(&inner, nearest, None)
                            .unwrap_or(inner.tabs[nearest].id)
                    };
                    let replacement_index = Self::index(&inner, replacement).expect("replacement");
                    inner.active_tab_id = Some(replacement);
                    inner.current = inner.tabs[replacement_index].session.clone();
                    (inner.tabs[replacement_index].navigation.pane == Pane::History)
                        .then_some(replacement)
                }
            };
            if let Some(load) = load {
                self.load_history_for_tab(load, true, None);
            }
        }
        if !self
            .inner
            .borrow()
            .tabs
            .iter()
            .any(|tab| tab.session.is_some())
        {
            self.drain.borrow_mut().cancel();
        }
        self.publish_workspace();
    }

    // Navigation and History -------------------------------------------------------

    pub fn update_navigation(&self, tab_id: u64, navigation: Navigation) {
        {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            if navigation.pane != inner.tabs[index].navigation.pane {
                inner.opening_panes.remove(&tab_id);
            }
            if navigation.pane == Pane::History
                && let Some(selected) = &navigation.selected_identity
            {
                inner.history_selections.insert(tab_id, selected.clone());
            }
            inner.tabs[index].navigation = navigation;
        }
        self.publish_workspace();
    }

    /// Reloads the history the active tab shows in place.
    pub fn reload_shown_history(self: &Rc<Self>) {
        let Some(tab) = self.active_tab() else { return };
        if tab.navigation.pane != Pane::History {
            return;
        }
        self.load_history_for_tab(tab.id, false, None);
    }

    /// Loads the history of `tab_id` and selects its remembered commit or HEAD.
    pub async fn show_history(self: &Rc<Self>, tab_id: u64) {
        let Some(tab) = self.tab(tab_id) else { return };
        let Some(session) = tab.session.clone() else {
            return;
        };
        let reveal = self.take_head_reveal(&tab);
        match reveal {
            Some(reveal) => {
                self.load_history_and_reveal(tab_id, session.identity, reveal)
                    .await
            }
            None => {
                self.load_history_and_restore_selection(
                    tab_id,
                    session.identity,
                    tab.navigation.selected_identity.clone(),
                    true,
                )
                .await
            }
        }
    }

    /// Filters the history graph of `tab_id` and remembers the filter.
    pub async fn set_branch_filter(self: &Rc<Self>, tab_id: u64, filter: BranchFilter) {
        let apply = {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            if inner.tabs[index].navigation.branch_filter == filter {
                return;
            }
            inner.tabs[index].navigation.branch_filter = filter;
            let active = inner.active_tab_id == Some(tab_id) && inner.tabs[index].session.is_some();
            active.then(|| Self::shown_filter(&inner, &inner.tabs[index]))
        };
        self.publish_workspace();
        if let Some(shown) = apply {
            self.history.apply_branch_filter(shown).await;
        }
    }

    /// Shows `reference` in the graph of `tab_id` even when the filter leaves
    /// it out, until another reference or None replaces it.
    pub async fn reveal_reference(self: &Rc<Self>, tab_id: u64, reference: Option<String>) {
        let apply = {
            let mut inner = self.inner.borrow_mut();
            let Some(index) = Self::index(&inner, tab_id) else {
                return;
            };
            let before = Self::shown_filter(&inner, &inner.tabs[index]);
            match reference {
                None => {
                    inner.revealed_references.remove(&tab_id);
                }
                Some(reference) => {
                    inner.revealed_references.insert(tab_id, reference);
                }
            }
            let shown = Self::shown_filter(&inner, &inner.tabs[index]);
            (shown != before
                && inner.active_tab_id == Some(tab_id)
                && inner.tabs[index].session.is_some())
            .then_some(shown)
        };
        if let Some(shown) = apply {
            self.history.apply_branch_filter(shown).await;
        }
    }

    /// The tab's branch filter plus the reference revealed in it.
    pub fn shown_branch_filter(&self, tab_id: u64) -> BranchFilter {
        let inner = self.inner.borrow();
        Self::index(&inner, tab_id).map_or(BranchFilter::NONE, |index| {
            Self::shown_filter(&inner, &inner.tabs[index])
        })
    }

    fn shown_filter(inner: &Inner, tab: &Tab) -> BranchFilter {
        let filter = &tab.navigation.branch_filter;
        match inner.revealed_references.get(&tab.id) {
            Some(revealed)
                if !filter.is_empty()
                    && !filter.contains(revealed)
                    && filter.len() < crate::history::BRANCH_FILTER_REFERENCES =>
            {
                BranchFilter::new(
                    filter
                        .references()
                        .iter()
                        .cloned()
                        .chain(std::iter::once(revealed.clone())),
                )
            }
            _ => filter.clone(),
        }
    }

    /// Rescans the active repository for changes made outside the application.
    pub async fn refresh(&self) -> SessionResult<()> {
        let current = self.require_current()?;
        self.sessions.refresh(current).await
    }

    /// Completes only when a newer snapshot has reached the workspace.
    pub async fn refresh_and_wait(self: &Rc<Self>, identity: SessionIdentity) -> SessionResult<()> {
        self.ensure_active()?;
        let revision = {
            let inner = self.inner.borrow();
            let index =
                Self::index_for_session(&inner, identity).ok_or(SessionError::UNKNOWN_SESSION)?;
            inner.tabs[index]
                .session
                .as_ref()
                .map_or(0, |session| session.snapshot.revision)
        };
        self.sessions.refresh(identity).await?;
        let deadline = std::time::Instant::now() + Duration::from_secs(30);
        loop {
            {
                let inner = self.inner.borrow();
                let index = Self::index_for_session(&inner, identity)
                    .ok_or(SessionError::UNKNOWN_SESSION)?;
                let snapshot = &inner.tabs[index]
                    .session
                    .as_ref()
                    .ok_or(SessionError::UNKNOWN_SESSION)?
                    .snapshot;
                if snapshot.revision > revision {
                    if let Some(failure) = snapshot
                        .failure
                        .as_ref()
                        .or(snapshot.refs_failure.as_ref())
                        .or(snapshot.status_failure.as_ref())
                    {
                        return Err(SessionError(failure.into()));
                    }
                    if snapshot.phase == NativeRepositoryPhase::Ready {
                        return Ok(());
                    }
                }
            }
            if std::time::Instant::now() >= deadline {
                return Err(SessionError(FailureCode::TimedOut));
            }
            self.drain_now(identity).await;
            rt::sleep(Duration::from_millis(20)).await;
        }
    }

    // Events ----------------------------------------------------------------------------

    fn start_drain(self: &Rc<Self>) {
        if self.inner.borrow().disposed || self.drain.borrow().is_active() {
            return;
        }
        let weak = Rc::downgrade(self);
        let handle = PeriodicHandle::start(self.drain_interval, move || {
            let Some(service) = weak.upgrade() else {
                return;
            };
            let sessions: Vec<(SessionIdentity, bool)> = {
                let mut inner = service.inner.borrow_mut();
                inner.drain_tick += 1;
                let include_hidden = inner.drain_tick % DRAIN_HIDDEN_EVERY == 0;
                let active = inner.active_tab_id;
                inner
                    .tabs
                    .iter()
                    .filter_map(|tab| {
                        let session = tab.session.as_ref()?;
                        let is_active = Some(tab.id) == active;
                        (include_hidden || is_active).then_some((session.identity, is_active))
                    })
                    .collect()
            };
            for (session, _) in sessions {
                let service = Rc::clone(&service);
                rt::spawn_detached(async move { service.drain_now(session).await });
            }
        });
        *self.drain.borrow_mut() = handle;
    }

    /// Drains `session` once, unless a drain of it is running.
    pub async fn drain_now(self: &Rc<Self>, session: SessionIdentity) {
        if self.inner.borrow().disposed
            || !self.inner.borrow_mut().draining.insert(session.native_id)
        {
            return;
        }
        self.drain_events(session).await;
        self.inner.borrow_mut().draining.remove(&session.native_id);
    }

    async fn drain_events(self: &Rc<Self>, identity: SessionIdentity) {
        if self.disposed() {
            return;
        }
        let events = match self.sessions.events(identity, 64).await {
            Ok(events) => events,
            Err(error) => {
                let changed = {
                    let mut inner = self.inner.borrow_mut();
                    match Self::index_for_session(&inner, identity) {
                        Some(index) => {
                            let tab = &mut inner.tabs[index];
                            if let Some(session) = &mut tab.session {
                                session.transport_failure = Some(error.code());
                            }
                            tab.phase = TabPhase::Failed;
                            tab.failure = Some(error.code());
                            if inner.active_tab_id == Some(inner.tabs[index].id) {
                                inner.current = inner.tabs[index].session.clone();
                            }
                            true
                        }
                        None => false,
                    }
                };
                if changed {
                    self.notifier.notify(Topics::SESSION);
                    self.publish_workspace();
                }
                return;
            }
        };
        if self.disposed() {
            return;
        }
        for event in events {
            let Some(index) = Self::index_for_session(&self.inner.borrow(), identity) else {
                continue;
            };
            if event.kind == NativeRepositoryEventKind::WatchOverflow
                && let Some(revision) = event.watch_overflow_revision
            {
                let changed = {
                    let mut inner = self.inner.borrow_mut();
                    let tab = &mut inner.tabs[index];
                    if tab
                        .watch_overflow_revision
                        .is_none_or(|previous| revision > previous)
                    {
                        tab.watch_overflow_revision = Some(revision);
                        true
                    } else {
                        false
                    }
                };
                if changed {
                    self.publish_workspace();
                }
            }
            let Some(snapshot) = event.snapshot else {
                continue;
            };
            let current = self.inner.borrow().tabs[index].session.clone();
            let Some(current) = current else { continue };
            if event.kind != NativeRepositoryEventKind::Resynchronize
                && snapshot.revision < current.snapshot.revision
            {
                continue;
            }
            self.view_cache.remember(&snapshot);
            let presented = Rc::new(self.view_cache.present(&snapshot));
            let next = current.with_snapshot(Rc::clone(&presented));
            let (tab_id, reload_visible, followed, recovered) = {
                let mut inner = self.inner.borrow_mut();
                let tab_id = inner.tabs[index].id;
                let reload_visible = inner.active_tab_id == Some(tab_id)
                    && inner.tabs[index].navigation.pane == Pane::History
                    && history_projection_changed(&current.snapshot, &presented);
                let followed = inner.heads.take(identity, &presented);
                let overflow = inner.tabs[index].watch_overflow_revision;
                let recovered = overflow.is_some_and(|overflow| {
                    snapshot.phase == NativeRepositoryPhase::Ready
                        && snapshot.failure.is_none()
                        && snapshot.revision > overflow
                });
                let tab = &mut inner.tabs[index];
                tab.phase = if snapshot.phase == NativeRepositoryPhase::Failed {
                    TabPhase::Failed
                } else {
                    TabPhase::Open
                };
                tab.session = Some(next.clone());
                tab.failure = snapshot.failure.as_ref().map(FailureCode::from);
                if recovered {
                    tab.watch_overflow_revision = None;
                }
                (tab_id, reload_visible, followed, recovered)
            };
            let _ = recovered;
            let is_active = self.inner.borrow().active_tab_id == Some(tab_id);
            if is_active {
                self.inner.borrow_mut().current = Some(next);
                self.notifier.notify(Topics::SESSION);
                if reload_visible {
                    self.load_history_for_tab(tab_id, false, followed);
                } else if let Some(head) = followed {
                    self.inner.borrow_mut().heads.keep_reveal(tab_id, head);
                }
            } else if let Some(head) = followed {
                self.inner.borrow_mut().heads.keep_reveal(tab_id, head);
            }
            self.choose_opening_pane(tab_id, &snapshot);
            self.record_recent(&snapshot);
            self.publish_workspace();
        }
    }

    /// `entering` is false for a reload of the history already shown;
    /// `reveal` names a commit the reloaded history selects and scrolls to.
    fn load_history_for_tab(self: &Rc<Self>, tab_id: u64, entering: bool, reveal: Option<String>) {
        let Some(tab) = self.tab(tab_id) else { return };
        let Some(session) = tab.session.clone() else {
            return;
        };
        let kept = self.take_head_reveal(&tab);
        let reveal = reveal.or(kept);
        if entering && reveal.is_none() && self.history_is_current(&tab, &session) {
            self.history.restore_detail();
            return;
        }
        self.inner.borrow_mut().history_basis = Some((tab_id, Rc::clone(&session.snapshot)));
        let this = Rc::clone(self);
        match reveal {
            Some(reveal) => rt::spawn_detached(async move {
                this.load_history_and_reveal(tab_id, session.identity, reveal)
                    .await
            }),
            None => {
                let selected = tab.navigation.selected_identity.clone();
                rt::spawn_detached(async move {
                    this.load_history_and_restore_selection(
                        tab_id,
                        session.identity,
                        selected,
                        entering,
                    )
                    .await
                })
            }
        }
    }

    /// Whether History still shows `tab`'s complete graph and nothing it depends on changed
    /// since it was loaded: switching back to History then reloads nothing, which on a large
    /// repository rebuilt the graph, the selection and the inspected commit every time.
    fn history_is_current(&self, tab: &Tab, session: &SessionState) -> bool {
        let state = self.history.current();
        if self.history.identity() != Some(session.identity)
            || state.phase != crate::history::LoadPhase::Complete
        {
            return false;
        }
        let Some(page) = state.page.as_ref() else {
            return false;
        };
        // A commit chosen elsewhere meanwhile (the sidebar) is selected by a load.
        if let Some(selected) = &tab.navigation.selected_identity
            && !page.selected_object_ids.contains(selected)
        {
            return false;
        }
        let inner = self.inner.borrow();
        inner
            .history_basis
            .as_ref()
            .is_some_and(|(basis_tab, basis)| {
                *basis_tab == tab.id && !history_projection_changed(basis, &session.snapshot)
            })
    }

    fn take_head_reveal(&self, tab: &Tab) -> Option<String> {
        let head = tab
            .session
            .as_ref()
            .and_then(|session| session.head_object_id())
            .map(str::to_owned);
        self.inner
            .borrow_mut()
            .heads
            .take_reveal(tab.id, head.as_deref())
    }

    fn tab_shows_history_of(&self, tab_id: u64, identity: SessionIdentity) -> Option<Tab> {
        let inner = self.inner.borrow();
        let index = Self::index(&inner, tab_id)?;
        if inner.active_tab_id != Some(tab_id) {
            return None;
        }
        let tab = &inner.tabs[index];
        let session = tab.session.as_ref()?;
        (session.identity.native_id == identity.native_id
            && session.identity.generation == identity.generation
            && tab.navigation.pane == Pane::History)
            .then(|| tab.clone())
    }

    async fn load_history_and_reveal(
        self: &Rc<Self>,
        tab_id: u64,
        identity: SessionIdentity,
        object_id: String,
    ) {
        self.history.load(identity, vec![object_id.clone()]).await;
        for attempt in 0..3 {
            let Some(tab) = self.tab_shows_history_of(tab_id, identity) else {
                return;
            };
            if attempt == 0 {
                let mut navigation = tab.navigation.clone();
                navigation.selected_identity = Some(object_id.clone());
                self.update_navigation(tab_id, navigation);
            } else if tab.navigation.selected_identity.as_ref() != Some(&object_id) {
                return;
            }
            self.history
                .select(
                    Some(object_id.clone()),
                    false,
                    true,
                    false,
                    0,
                    SelectionOrigin::Graph,
                )
                .await;
            if self
                .history
                .current()
                .page
                .is_some_and(|page| page.selected_object_ids.contains(&object_id))
            {
                return;
            }
        }
    }

    async fn load_history_and_restore_selection(
        self: &Rc<Self>,
        tab_id: u64,
        identity: SessionIdentity,
        selected: Option<String>,
        entering: bool,
    ) {
        let remembered = selected.clone().or_else(|| {
            entering
                .then(|| self.inner.borrow().history_selections.get(&tab_id).cloned())
                .flatten()
        });
        self.history
            .load(identity, remembered.iter().cloned().collect())
            .await;
        if self
            .history
            .current()
            .page
            .is_some_and(|page| !page.selected_object_ids.is_empty())
        {
            return;
        }
        let mut expected = selected;
        for use_head in [false, true] {
            let Some(tab) = self.tab_shows_history_of(tab_id, identity) else {
                return;
            };
            if tab.navigation.selected_identity != expected {
                return;
            }
            let session = tab.session.as_ref().expect("session");
            let candidate = if use_head {
                session.head_object_id().map(str::to_owned).or_else(|| {
                    session
                        .snapshot
                        .identity
                        .as_ref()
                        .and_then(|identity| identity.head_object_id.clone())
                })
            } else {
                remembered.clone()
            };
            let Some(candidate) = candidate else { continue };
            if use_head && (!entering || Some(&candidate) == remembered.as_ref()) {
                continue;
            }
            if expected.as_ref() != Some(&candidate) {
                expected = Some(candidate.clone());
                let mut navigation = tab.navigation.clone();
                navigation.selected_identity = Some(candidate.clone());
                self.update_navigation(tab_id, navigation);
            }
            self.history
                .select(
                    Some(candidate.clone()),
                    false,
                    false,
                    true,
                    0,
                    SelectionOrigin::Graph,
                )
                .await;
            if self
                .history
                .current()
                .page
                .is_some_and(|page| page.selected_object_ids.contains(&candidate))
            {
                return;
            }
        }
    }

    // Lifecycle ----------------------------------------------------------------------

    /// Closes every tab and its session.
    pub async fn close(&self) {
        self.drain.borrow_mut().cancel();
        let sessions: Vec<SessionIdentity> = {
            let mut inner = self.inner.borrow_mut();
            let sessions = inner
                .tabs
                .iter()
                .filter_map(|tab| tab.session.as_ref().map(|session| session.identity))
                .collect();
            inner.tabs.clear();
            inner.active_tab_id = None;
            inner.current = None;
            inner.generation += 1;
            sessions
        };
        self.history.clear();
        for identity in sessions {
            let _ = self.sessions.close(identity).await;
        }
        self.publish_workspace();
    }

    /// Marks the workspace disposed: every later call fails, the drain stops.
    pub fn retire(&self) {
        let mut inner = self.inner.borrow_mut();
        if inner.disposed {
            return;
        }
        inner.disposed = true;
        drop(inner);
        self.drain.borrow_mut().cancel();
    }

    fn index(inner: &Inner, tab_id: u64) -> Option<usize> {
        inner.tabs.iter().position(|tab| tab.id == tab_id)
    }

    fn index_for_session(inner: &Inner, identity: SessionIdentity) -> Option<usize> {
        inner.tabs.iter().position(|tab| {
            tab.session.as_ref().is_some_and(|session| {
                session.identity.native_id == identity.native_id
                    && session.identity.generation == identity.generation
            })
        })
    }

    fn publish_workspace(&self) {
        {
            let mut inner = self.inner.borrow_mut();
            Self::keep_worktrees_together(&mut inner, None);
            Self::settle_groups(&mut inner);
        }
        self.revision.set(self.revision.get() + 1);
        self.notifier.notify(Topics::WORKSPACE);
        if !self.disposed() {
            self.persist();
            if let Some(hook) = &self.hooks.borrow().on_published {
                hook();
            }
        }
    }

    // Persistence -------------------------------------------------------------------

    fn navigation_for(&self, identity: Option<&NativePathIdentity>) -> Navigation {
        let (Some(settings), Some(identity)) = (&self.settings, identity) else {
            return Navigation::default();
        };
        settings.with(|document| {
            let Some(saved) = document
                .worktrees
                .iter()
                .find(|worktree| &worktree.identity == identity)
            else {
                return Navigation::default();
            };
            Navigation {
                pane: Pane::parse(&saved.pane).unwrap_or(Pane::Changes),
                route: Route::parse(&saved.route).unwrap_or(Route::Repository),
                selected_identity: saved.anchor.clone(),
                changes_scroll_offset: saved.changes_scroll_offset as f64,
                history_scroll_offset: saved.history_scroll_offset as f64,
                branch_filter: BranchFilter::new(saved.branch_filter.iter().cloned()),
            }
        })
    }

    fn persist(&self) {
        let Some(settings) = &self.settings else {
            return;
        };
        let inner = self.inner.borrow();
        let active_identity = inner
            .active_tab_id
            .and_then(|id| inner.tabs.iter().find(|tab| tab.id == id))
            .and_then(|tab| tab.canonical_identity().cloned());
        let mut identities: Vec<NativePathIdentity> = Vec::new();
        for tab in &inner.tabs {
            if let Some(identity) = tab.canonical_identity()
                && !identities.contains(identity)
            {
                identities.push(identity.clone());
            }
        }
        let (mut worktrees, current_groups, current_open, current_active) =
            settings.with(|document| {
                (
                    document.worktrees.clone(),
                    document.tab_groups.clone(),
                    document.open_worktrees.clone(),
                    document.active_worktree.clone(),
                )
            });
        let before = worktrees.clone();
        for tab in &inner.tabs {
            let Some(identity) = tab.canonical_identity() else {
                continue;
            };
            let navigation = &tab.navigation;
            let position = worktrees
                .iter()
                .position(|worktree| &worktree.identity == identity);
            let mut updated = match position {
                Some(position) => worktrees[position].clone(),
                None => NativeWorktreeSettings {
                    identity: identity.clone(),
                    filter: String::new(),
                    anchor: None,
                    pane: "changes".into(),
                    route: "repository".into(),
                    changes_scroll_offset: 0,
                    history_scroll_offset: 0,
                    draft: gitlama_contract::storage::NativeCommitDraft {
                        subject: String::new(),
                        description: String::new(),
                    },
                    branch_filter: Vec::new(),
                },
            };
            updated.anchor = navigation.selected_identity.clone();
            updated.pane = navigation.pane.name().into();
            updated.route = navigation.route.name().into();
            updated.changes_scroll_offset =
                navigation.changes_scroll_offset.round().max(0.0) as u64;
            updated.history_scroll_offset =
                navigation.history_scroll_offset.round().max(0.0) as u64;
            updated.branch_filter = navigation.branch_filter.references().to_vec();
            match position {
                Some(position) => worktrees[position] = updated,
                None => worktrees.push(updated),
            }
        }
        let mut tab_groups = Vec::new();
        for group in &inner.groups {
            let members: Vec<NativePathIdentity> = inner
                .tabs
                .iter()
                .filter(|tab| tab.group_id == Some(group.id))
                .filter_map(|tab| tab.canonical_identity().cloned())
                .collect();
            if members.is_empty() {
                continue;
            }
            tab_groups.push(NativeTabGroup {
                name: group.name.clone(),
                color: group.color.clone(),
                icon: group.icon.clone(),
                collapsed: group.collapsed,
                members,
            });
        }
        if worktrees == before
            && identities == current_open
            && tab_groups == current_groups
            && active_identity == current_active
        {
            return;
        }
        drop(inner);
        let _ = settings.update(|document| {
            document.worktrees = worktrees;
            document.open_worktrees = identities;
            document.tab_groups = tab_groups;
            document.active_worktree = active_identity;
        });
    }

    /// Puts a loaded repository first among the recent ones.
    fn record_recent(&self, snapshot: &NativeRepositorySnapshot) {
        let Some(settings) = &self.settings else {
            return;
        };
        if snapshot.phase != NativeRepositoryPhase::Ready {
            return;
        }
        let Some(identity) = snapshot
            .identity
            .as_ref()
            .map(|identity| identity.worktree_root.clone())
        else {
            return;
        };
        if settings.with(|document| document.recent_repositories.first() == Some(&identity)) {
            return;
        }
        let _ = settings.update(|document| {
            let mut recents = vec![identity.clone()];
            recents.extend(
                document
                    .recent_repositories
                    .iter()
                    .filter(|recent| **recent != identity)
                    .cloned(),
            );
            recents.truncate(100);
            document.recent_repositories = recents;
        });
    }
}

fn staged_entry_count(status: Option<&NativeRepositoryStatus>) -> usize {
    status.map_or(0, |status| {
        status
            .entries
            .iter()
            .filter(|entry| entry.index != gitlama_contract::dto::NativeChangeKind::Unmodified)
            .count()
    })
}

/// Whether what History shows (HEAD, WIP state, file counts, references)
/// changed between two snapshots.
fn history_projection_changed(
    previous: &NativeRepositorySnapshot,
    next: &NativeRepositorySnapshot,
) -> bool {
    let old = previous.status.as_ref();
    let new = next.status.as_ref();
    if old.and_then(|s| s.head_object_id.as_ref()) != new.and_then(|s| s.head_object_id.as_ref())
        || old.map(|s| s.working_tree) != new.map(|s| s.working_tree)
        || old.map(|s| s.entries.len()) != new.map(|s| s.entries.len())
        || staged_entry_count(old) != staged_entry_count(new)
        || old.and_then(|s| s.branch_name.as_ref()) != new.and_then(|s| s.branch_name.as_ref())
    {
        return true;
    }
    let (old, new) = (&previous.refs, &next.refs);
    let branches = old.branches.len() == new.branches.len()
        && old.branches.iter().zip(&new.branches).all(|(left, right)| {
            left.name == right.name && left.target == right.target && left.head == right.head
        });
    let remotes = old.remotes.len() == new.remotes.len()
        && old.remotes.iter().zip(&new.remotes).all(|(left, right)| {
            left.name == right.name
                && left.branches.len() == right.branches.len()
                && left
                    .branches
                    .iter()
                    .zip(&right.branches)
                    .all(|(a, b)| a.name == b.name && a.target == b.target)
        });
    let tags = old.tags.len() == new.tags.len()
        && old
            .tags
            .iter()
            .zip(&new.tags)
            .all(|(left, right)| left.name == right.name && left.target == right.target);
    let stashes = old.stashes.len() == new.stashes.len()
        && old.stashes.iter().zip(&new.stashes).all(|(left, right)| {
            left.selector == right.selector
                && left.object_id == right.object_id
                && left.subject == right.subject
        });
    !(branches && remotes && tags && stashes)
}
