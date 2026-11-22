//! The Changes pane's diff (the Dart WorkingTreeDetailPane's loading): the
//! working diff of the file Changes shows, on the focused side. Another
//! file loads afresh; a new status of the same file reloads in place, so an
//! unaffected diff keeps its rows and selected lines. While Git has not
//! answered for a while the pane says it is waiting.

use crate::backend::SessionCalls;
use crate::changes::{ChangesService, diff_paths, display_identity, is_staged, is_unstaged};
use crate::diff_doc::{DIFF_PAGE_ROWS, DiffDocument};
use crate::inspector::DiffOptions;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::session::{FailureCode, SessionError, SessionIdentity};
use crate::workspace::{Pane, WorkspaceService};
use gitlama_contract::diff::NativeDiffSyntaxOrigin;
use gitlama_contract::dto::{NativeRepositorySnapshot, NativeStagingSide, NativeStatusEntry, NativeWorkingDiffOptions};
use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::rc::{Rc, Weak};
use std::time::Duration;

/// What the diff shows: a tab's file on one side.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DetailKey {
    pub tab: u64,
    pub identity: String,
    pub side: NativeStagingSide,
}

#[derive(Default)]
struct State {
    key: Option<DetailKey>,
    entry: Option<NativeStatusEntry>,
    snapshot: Option<Rc<NativeRepositorySnapshot>>,
    document: Option<Rc<DiffDocument>>,
    loading: bool,
    waiting: bool,
    failure: Option<FailureCode>,
    force_text: bool,
    selected_rows: HashSet<String>,
    generation: u64,
    in_flight: bool,
    queued: bool,
    quiet: bool,
}

pub struct WorkingDetail {
    calls: Rc<dyn SessionCalls>,
    notifier: Notifier,
    workspace: Rc<WorkspaceService>,
    changes: Rc<ChangesService>,
    options: Cell<DiffOptions>,
    state: RefCell<State>,
    this: RefCell<Weak<Self>>,
}

/// How long a diff may load before the pane says it is waiting for Git.
const WAITING_NOTICE: Duration = Duration::from_secs(2);

impl WorkingDetail {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        notifier: Notifier,
        workspace: Rc<WorkspaceService>,
        changes: Rc<ChangesService>,
    ) -> Rc<Self> {
        let detail = Rc::new(Self {
            calls,
            notifier,
            workspace,
            changes,
            options: Cell::new(DiffOptions::default()),
            state: RefCell::new(State::default()),
            this: RefCell::new(Weak::new()),
        });
        *detail.this.borrow_mut() = Rc::downgrade(&detail);
        detail
    }

    fn this(&self) -> Rc<Self> {
        self.this.borrow().upgrade().expect("working detail alive")
    }

    fn changed(&self) {
        self.notifier.notify(Topics::DIFF);
    }

    pub fn key(&self) -> Option<DetailKey> {
        self.state.borrow().key.clone()
    }

    pub fn entry(&self) -> Option<NativeStatusEntry> {
        self.state.borrow().entry.clone()
    }

    pub fn document(&self) -> Option<Rc<DiffDocument>> {
        self.state.borrow().document.clone()
    }

    pub fn loading(&self) -> bool {
        self.state.borrow().loading
    }

    pub fn waiting(&self) -> bool {
        self.state.borrow().waiting
    }

    pub fn failure(&self) -> Option<FailureCode> {
        self.state.borrow().failure
    }

    pub fn options(&self) -> DiffOptions {
        self.options.get()
    }

    pub fn force_text(&self) -> bool {
        self.state.borrow().force_text
    }

    pub fn selected_rows(&self) -> HashSet<String> {
        self.state.borrow().selected_rows.clone()
    }

    /// Chooses the diff's selected lines (for line staging).
    pub fn set_selected_rows(&self, rows: HashSet<String>) {
        let tab = self.state.borrow().key.as_ref().map(|key| key.tab);
        let any = !rows.is_empty();
        self.state.borrow_mut().selected_rows = rows;
        if let Some(tab) = tab {
            self.changes.set_diff_rows_selected(tab, any);
        }
        self.changed();
    }

    /// Loads the diff again with other display options.
    pub fn set_options(&self, options: DiffOptions, force_text: bool) {
        let (same, keep_selection) = {
            let state = self.state.borrow();
            let current = self.options.get();
            (
                current == options && state.force_text == force_text,
                current.context_lines == options.context_lines && current.whitespace == options.whitespace,
            )
        };
        if same {
            return;
        }
        self.options.set(options);
        self.state.borrow_mut().force_text = force_text;
        self.schedule(keep_selection, false);
    }

    /// Follows what Changes shows in the active tab (call on workspace,
    /// session and Changes changes).
    pub fn follow(&self) {
        let active = self.workspace.active_tab();
        let target = active.as_ref().filter(|tab| tab.navigation.pane == Pane::Changes).and_then(|tab| {
            let session = tab.session.as_ref()?;
            let identity = self.changes.detail_identity(tab.id, tab.navigation.selected_identity.clone())?;
            let side = self.changes.selection_of(tab.id).focused;
            Some((DetailKey { tab: tab.id, identity, side }, Rc::clone(&session.snapshot)))
        });
        let (key_changed, status_changed) = {
            let state = self.state.borrow();
            let key = target.as_ref().map(|(key, _)| key);
            let key_changed = state.key.as_ref() != key;
            let status_changed = match (&state.snapshot, &target) {
                (Some(shown), Some((_, snapshot))) => shown.status != snapshot.status,
                (None, None) => false,
                _ => true,
            };
            (key_changed, status_changed)
        };
        if !key_changed && !status_changed {
            return;
        }
        {
            let mut state = self.state.borrow_mut();
            if key_changed {
                // Another file is detected as Git sees it again.
                state.force_text = false;
            }
            state.key = target.as_ref().map(|(key, _)| key.clone());
            state.snapshot = target.map(|(_, snapshot)| snapshot);
        }
        if key_changed {
            self.schedule(false, false);
        } else {
            // A new status of the same file reloads in place.
            self.schedule(true, true);
        }
    }

    fn schedule(&self, keep_selection: bool, quiet: bool) {
        let start = {
            let mut state = self.state.borrow_mut();
            state.generation += 1;
            if !keep_selection {
                state.selected_rows.clear();
            }
            state.quiet = if state.queued { state.quiet && quiet } else { quiet };
            state.queued = true;
            !state.in_flight
        };
        if start {
            let this = self.this();
            rt::spawn_detached(async move { this.drain().await });
        }
    }

    async fn drain(&self) {
        self.state.borrow_mut().in_flight = true;
        loop {
            let (generation, quiet) = {
                let mut state = self.state.borrow_mut();
                if !state.queued {
                    break;
                }
                state.queued = false;
                (state.generation, state.quiet)
            };
            self.load(generation, quiet).await;
        }
        self.state.borrow_mut().in_flight = false;
    }

    fn entry_for(&self, key: &DetailKey) -> Option<NativeStatusEntry> {
        let snapshot = self.state.borrow().snapshot.clone()?;
        snapshot.status.as_ref()?.entries.iter().find(|entry| display_identity(entry) == key.identity).cloned()
    }

    fn session(&self, tab: u64) -> Option<SessionIdentity> {
        self.workspace.tab(tab)?.session.map(|session| session.identity)
    }

    async fn load(&self, generation: u64, quiet: bool) {
        let key = self.state.borrow().key.clone();
        let entry = key.as_ref().and_then(|key| self.entry_for(key));
        let (Some(key), Some(entry), Some(identity)) =
            (key.clone(), entry, key.as_ref().and_then(|key| self.session(key.tab)))
        else {
            let previous = {
                let mut state = self.state.borrow_mut();
                state.entry = None;
                state.loading = false;
                state.failure = None;
                state.document.take()
            };
            if let Some(previous) = previous {
                previous.retire();
            }
            self.changed();
            return;
        };
        let side = if key.side == NativeStagingSide::Staged && is_staged(&entry) {
            NativeStagingSide::Staged
        } else if is_unstaged(&entry) {
            NativeStagingSide::Unstaged
        } else {
            NativeStagingSide::Staged
        };
        let (old_path, new_path) = diff_paths(&entry, side);
        let in_place = quiet && self.state.borrow().document.is_some() && self.state.borrow().failure.is_none();
        {
            let mut state = self.state.borrow_mut();
            state.entry = Some(entry.clone());
            if !in_place {
                state.loading = true;
                state.failure = None;
                if let Some(previous) = state.document.take() {
                    previous.retire();
                }
            }
        }
        self.changed();
        // Git has not answered for a while: say so, keep waiting.
        {
            let this = self.this();
            rt::spawn_detached(async move {
                rt::sleep(WAITING_NOTICE).await;
                let waiting = {
                    let state = this.state.borrow();
                    state.generation == generation && state.loading
                };
                if waiting {
                    this.state.borrow_mut().waiting = true;
                    this.changed();
                }
            });
        }
        let options = self.options.get();
        let force_text = self.state.borrow().force_text;
        let request = NativeWorkingDiffOptions {
            side,
            old_path,
            new_path,
            context_lines: options.context_lines,
            whitespace: options.whitespace,
            layout: options.layout,
            maximum_rows: DIFF_PAGE_ROWS as u32,
            force_text,
        };
        let result = loop {
            let result = self
                .calls
                .repository_session_working_diff_load(identity.native_id, identity.generation, request.clone())
                .await;
            let timed_out = matches!(&result, Ok(result) if result.failure.as_ref().map(FailureCode::from) == Some(FailureCode::TimedOut));
            if timed_out && self.state.borrow().generation == generation {
                // Each retry resumes the read already running.
                self.state.borrow_mut().waiting = true;
                self.changed();
                continue;
            }
            break result;
        };
        if self.state.borrow().generation != generation {
            return;
        }
        let page = match result {
            Ok(result) => match (result.page, result.failure) {
                (Some(page), None) => Ok(page),
                (_, Some(failure)) => Err(FailureCode::from(&failure)),
                _ => Err(FailureCode::InvalidOutput),
            },
            Err(error) => Err(SessionError::from(error).code()),
        };
        let page = match page {
            Ok(page) => page,
            Err(code) => {
                let mut state = self.state.borrow_mut();
                state.failure = Some(code);
                state.loading = false;
                state.waiting = false;
                drop(state);
                self.changed();
                return;
            }
        };
        let document = DiffDocument::new(
            Rc::clone(&self.calls),
            self.notifier.clone(),
            Topics::DIFF,
            identity,
            NativeDiffSyntaxOrigin::Working,
            page,
        );
        if in_place {
            // Fetch every other page shown so far, so rows never fall back
            // to placeholders.
            let shown = self.state.borrow().document.clone();
            if let Some(shown) = shown {
                let mut offsets = HashSet::new();
                shown.for_each_loaded(|index, _| {
                    offsets.insert((index / DIFF_PAGE_ROWS) * DIFF_PAGE_ROWS);
                });
                offsets.remove(&0);
                document.preload(offsets.into_iter().filter(|offset| *offset < document.total()).collect()).await;
                if self.state.borrow().generation != generation {
                    return;
                }
            }
        }
        let ids: HashSet<String> = {
            let mut ids = HashSet::new();
            document.for_each_loaded(|_, row| {
                ids.insert(row.stable_id.clone());
            });
            ids
        };
        let previous = {
            let mut state = self.state.borrow_mut();
            state.selected_rows.retain(|row| ids.contains(row));
            state.loading = false;
            state.waiting = false;
            state.document.replace(document)
        };
        if let Some(previous) = previous {
            previous.retire();
        }
        let any = !self.state.borrow().selected_rows.is_empty();
        self.changes.set_diff_rows_selected(key.tab, any);
        self.changed();
    }
}
