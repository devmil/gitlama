//! The Changes pane's workflows and state for every tab (the Dart
//! ChangesService): the selection and focused list, staging of files or
//! lines (queued, merged and run one at a time), Discard or Clean with a
//! review, and which selection follows a move. The pane renders it.

use crate::backend::SessionCalls;
use crate::busy::{BusyActivity, BusyService};
use crate::navigator::Navigator;
use crate::notices::Notices;
use crate::notify::{Notifier, Topics};
use crate::prompts::Prompts;
use crate::rt;
use crate::session::{FailureCode, SessionIdentity, display_path};
use crate::workspace::WorkspaceService;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{
    NativeChangeKind, NativeDiscardExecutionState, NativeDiscardKind, NativeDiscardRequest,
    NativeDiscardScope, NativeOperationKind, NativeRepositoryStatus, NativeStagingExecutionState,
    NativeStagingFailureCode, NativeStagingPhase, NativeStagingRequest, NativeStagingScope,
    NativeStagingSide, NativeStatusEntry, NativeStatusEntryKind, NativeWorkingTreeState,
};
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::Duration;

/// Paths one staging request carries (ContractLimits.stagePaths).
pub const STAGE_PATHS: usize = 4096;

pub fn side_name(side: NativeStagingSide) -> &'static str {
    match side {
        NativeStagingSide::Unstaged => "unstaged",
        NativeStagingSide::Staged => "staged",
    }
}

pub fn other_side(side: NativeStagingSide) -> NativeStagingSide {
    match side {
        NativeStagingSide::Staged => NativeStagingSide::Unstaged,
        NativeStagingSide::Unstaged => NativeStagingSide::Staged,
    }
}

/// The bytes Git names `path` by.
pub fn path_bytes(path: &NativePathIdentity) -> Vec<u8> {
    display_path(path).into_bytes()
}

/// A stable key of one status entry.
pub fn change_key(entry: &NativeStatusEntry) -> String {
    let mut parts: Vec<String> = vec![(entry.path.platform as u8).to_string()];
    parts.extend(entry.path.units.iter().map(u16::to_string));
    if let Some(source) = &entry.source {
        parts.extend(source.units.iter().map(u16::to_string));
    }
    parts.join(":")
}

/// How Changes and History name a file.
pub fn display_identity(entry: &NativeStatusEntry) -> String {
    display_path(&entry.path)
}

pub fn is_staged(entry: &NativeStatusEntry) -> bool {
    entry.index != NativeChangeKind::Unmodified
}

pub fn is_unstaged(entry: &NativeStatusEntry) -> bool {
    entry.worktree != NativeChangeKind::Unmodified || entry.kind == NativeStatusEntryKind::Untracked
}

/// The entries of `status` on `side`.
pub fn entries_on(
    status: &NativeRepositoryStatus,
    side: NativeStagingSide,
) -> Vec<NativeStatusEntry> {
    status
        .entries
        .iter()
        .filter(|entry| {
            if side == NativeStagingSide::Staged {
                is_staged(entry)
            } else {
                is_unstaged(entry)
            }
        })
        .cloned()
        .collect()
}

/// Whether `status` shows a conflict or a paused operation other than bisect.
pub fn has_active_conflicts(status: Option<&NativeRepositoryStatus>) -> bool {
    status.is_some_and(|status| {
        status.working_tree == NativeWorkingTreeState::Conflicted
            || status
                .entries
                .iter()
                .any(|entry| entry.kind == NativeStatusEntryKind::Unmerged)
            || status
                .operations
                .iter()
                .any(|operation| operation.kind != NativeOperationKind::Bisect)
    })
}

pub fn discardable(entry: &NativeStatusEntry) -> bool {
    matches!(
        entry.kind,
        NativeStatusEntryKind::Untracked
            | NativeStatusEntryKind::Ordinary
            | NativeStatusEntryKind::Rename
    )
}

/// What Discard does to `entries`: Clean when all are untracked, Discard
/// when any are tracked; None when empty or holding a conflict or ignored file.
pub fn discard_kind_of(entries: &[NativeStatusEntry]) -> Option<NativeDiscardKind> {
    let (mut untracked, mut tracked) = (false, false);
    for entry in entries {
        if !discardable(entry) {
            return None;
        }
        if entry.kind == NativeStatusEntryKind::Untracked {
            untracked = true;
        } else {
            tracked = true;
        }
    }
    match (untracked, tracked) {
        (false, false) => None,
        (_, false) => Some(NativeDiscardKind::Clean),
        _ => Some(NativeDiscardKind::Discard),
    }
}

/// The status letter of `entry` on `side` (the Dart changeStatusCode).
pub fn status_code(entry: &NativeStatusEntry, side: NativeStagingSide) -> &'static str {
    if entry.kind == NativeStatusEntryKind::Unmerged {
        return "U";
    }
    if entry.kind == NativeStatusEntryKind::Untracked {
        return "?";
    }
    if entry.kind == NativeStatusEntryKind::Ignored {
        return "!";
    }
    if entry.kind == NativeStatusEntryKind::Rename {
        return "R";
    }
    match if side == NativeStagingSide::Staged {
        entry.index
    } else {
        entry.worktree
    } {
        NativeChangeKind::Added => "A",
        NativeChangeKind::Deleted => "D",
        NativeChangeKind::Renamed => "R",
        NativeChangeKind::Copied => "C",
        NativeChangeKind::UpdatedButUnmerged => "U",
        NativeChangeKind::TypeChanged | NativeChangeKind::Modified => "M",
        NativeChangeKind::Unmodified => "!",
    }
}

/// The Git paths a command on `entries` takes: each once, with rename sources.
pub fn unique_command_paths(entries: &[NativeStatusEntry]) -> Vec<Vec<u8>> {
    let mut seen = HashSet::new();
    let mut paths = Vec::new();
    for entry in entries {
        for path in entry.source.iter().chain(std::iter::once(&entry.path)) {
            let bytes = path_bytes(path);
            if seen.insert(bytes.clone()) {
                paths.push(bytes);
            }
        }
    }
    paths
}

/// The old and new paths of `entry`'s diff on `side`.
pub fn diff_paths(
    entry: &NativeStatusEntry,
    side: NativeStagingSide,
) -> (Option<Vec<u8>>, Option<Vec<u8>>) {
    let path = path_bytes(&entry.path);
    if entry.kind == NativeStatusEntryKind::Untracked {
        return (None, Some(path));
    }
    let change = if side == NativeStagingSide::Staged {
        entry.index
    } else {
        entry.worktree
    };
    if matches!(change, NativeChangeKind::Renamed | NativeChangeKind::Copied)
        && let Some(source) = &entry.source
    {
        return (Some(path_bytes(source)), Some(path));
    }
    match change {
        NativeChangeKind::Added => (None, Some(path)),
        NativeChangeKind::Deleted => (Some(path), None),
        _ => (Some(path.clone()), Some(path)),
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Selection {
    pub staged: HashSet<String>,
    pub unstaged: HashSet<String>,
    pub focused: NativeStagingSide,
}

impl Default for Selection {
    fn default() -> Self {
        Self {
            staged: HashSet::new(),
            unstaged: HashSet::new(),
            focused: NativeStagingSide::Unstaged,
        }
    }
}

impl Selection {
    pub fn of(&self, side: NativeStagingSide) -> &HashSet<String> {
        if side == NativeStagingSide::Staged {
            &self.staged
        } else {
            &self.unstaged
        }
    }
}

/// One-shot events for the pane's animations.
#[derive(Clone, Debug)]
pub enum ChangesEffect {
    MoveStarted {
        tab: u64,
        side: NativeStagingSide,
        keys: Vec<String>,
        single: bool,
    },
    MoveEnded {
        tab: u64,
        moved: bool,
    },
    ActionFailed {
        tab: u64,
        side: NativeStagingSide,
    },
    DiffSelectionRequested {
        tab: u64,
        discard: bool,
    },
}

struct StageIntent {
    identity: SessionIdentity,
    side: NativeStagingSide,
    scope: NativeStagingScope,
    entries: Vec<NativeStatusEntry>,
    paths: Vec<Vec<u8>>,
    accepted_request: Option<u64>,
    row_ids: Vec<String>,
    shown_detail: Option<String>,
    selection_revision: u64,
}

#[derive(Default)]
struct TabChanges {
    selection: Selection,
    diff_rows_selected: bool,
    selection_revision: u64,
    pending: Vec<StageIntent>,
    running: Option<(NativeStagingSide, Vec<String>)>,
    phase: Option<NativeStagingPhase>,
    stopped_pending: usize,
    conflict_flow_active: bool,
    conflict_flow_dismissed: bool,
}

pub struct ChangesService {
    workspace: Rc<WorkspaceService>,
    calls: Rc<dyn SessionCalls>,
    busy: Rc<BusyService>,
    navigator: Rc<Navigator>,
    prompts: Rc<Prompts>,
    notices: Rc<Notices>,
    notifier: Notifier,
    tabs: RefCell<HashMap<u64, TabChanges>>,
    effects: RefCell<Vec<ChangesEffect>>,
    disposed: Cell<bool>,
    this: RefCell<Weak<Self>>,
}

impl ChangesService {
    pub fn new(
        workspace: Rc<WorkspaceService>,
        calls: Rc<dyn SessionCalls>,
        busy: Rc<BusyService>,
        navigator: Rc<Navigator>,
        prompts: Rc<Prompts>,
        notices: Rc<Notices>,
        notifier: Notifier,
    ) -> Rc<Self> {
        let service = Rc::new(Self {
            workspace,
            calls,
            busy,
            navigator,
            prompts,
            notices,
            notifier,
            tabs: RefCell::new(HashMap::new()),
            effects: RefCell::new(Vec::new()),
            disposed: Cell::new(false),
            this: RefCell::new(Weak::new()),
        });
        *service.this.borrow_mut() = Rc::downgrade(&service);
        service
    }

    fn this(&self) -> Rc<Self> {
        self.this.borrow().upgrade().expect("changes service alive")
    }

    fn notify(&self) {
        if !self.disposed.get() {
            self.notifier.notify(Topics::CHANGES);
        }
    }

    fn effect(&self, effect: ChangesEffect) {
        if !self.disposed.get() {
            self.effects.borrow_mut().push(effect);
            self.notifier.notify(Topics::CHANGES);
        }
    }

    /// The effects since the last call.
    pub fn take_effects(&self) -> Vec<ChangesEffect> {
        std::mem::take(&mut *self.effects.borrow_mut())
    }

    fn with_tab<R>(&self, tab: u64, read: impl FnOnce(&mut TabChanges) -> R) -> R {
        read(self.tabs.borrow_mut().entry(tab).or_default())
    }

    pub fn selection_of(&self, tab: u64) -> Selection {
        self.with_tab(tab, |state| state.selection.clone())
    }

    pub fn busy(&self, tab: u64) -> bool {
        self.busy.is_busy(Some(tab))
    }

    pub fn staging_phase(&self, tab: u64) -> Option<NativeStagingPhase> {
        self.with_tab(tab, |state| state.phase)
    }

    pub fn stopped_stages(&self, tab: u64) -> usize {
        self.with_tab(tab, |state| state.stopped_pending)
    }

    pub fn dismiss_stopped_stages(&self, tab: u64) {
        self.with_tab(tab, |state| state.stopped_pending = 0);
        self.notify();
    }

    /// Drops the queued staging work that has not started (Clear queue);
    /// the running step finishes.
    pub fn clear_pending_stages(&self, tab: u64) {
        self.with_tab(tab, |state| state.pending.clear());
        self.notify();
    }

    pub fn pending_stages(&self, tab: u64) -> usize {
        self.with_tab(tab, |state| state.pending.len())
    }

    /// Keys of entries queued or moving on `side`.
    pub fn pending_keys(&self, tab: u64, side: NativeStagingSide) -> HashSet<String> {
        self.with_tab(tab, |state| {
            let mut keys: HashSet<String> = state
                .pending
                .iter()
                .filter(|intent| intent.side == side)
                .flat_map(|intent| intent.entries.iter().map(change_key))
                .collect();
            if let Some((running_side, running)) = &state.running
                && *running_side == side
            {
                keys.extend(running.iter().cloned());
            }
            keys
        })
    }

    /// Whether whole-file staging can still queue while the tab is busy.
    pub fn can_stage_files(&self, tab: u64) -> bool {
        !self.busy.is_busy(Some(tab)) || self.with_tab(tab, |state| state.running.is_some())
    }

    pub fn conflict_flow(&self, tab: u64) -> bool {
        let status = self.status(tab);
        let conflicts = has_active_conflicts(status.as_ref());
        self.with_tab(tab, |state| {
            if !conflicts && state.conflict_flow_dismissed {
                state.conflict_flow_dismissed = false;
            }
            if conflicts && !state.conflict_flow_dismissed {
                state.conflict_flow_active = true;
            }
            state.conflict_flow_active
        })
    }

    /// Opens (or closes) the resolver of `tab` after probing for a paused
    /// operation the status does not show.
    pub fn set_conflict_flow(&self, tab: u64, active: bool) {
        let changed = self.with_tab(tab, |state| {
            let before = state.conflict_flow_active;
            state.conflict_flow_active = active;
            state.conflict_flow_dismissed = !active;
            before != active
        });
        if changed {
            self.notify();
        }
    }

    pub fn finish_conflict_flow(&self, tab: u64) {
        self.with_tab(tab, |state| {
            state.conflict_flow_active = false;
            state.conflict_flow_dismissed = true;
        });
        self.notify();
    }

    fn identity(&self, tab: u64) -> Option<SessionIdentity> {
        self.workspace
            .tab(tab)?
            .session
            .map(|session| session.identity)
    }

    fn status(&self, tab: u64) -> Option<NativeRepositoryStatus> {
        self.workspace.tab(tab)?.session?.snapshot.status.clone()
    }

    fn session_open(&self, tab: u64, identity: SessionIdentity) -> bool {
        !self.disposed.get() && self.identity(tab) == Some(identity)
    }

    /// Drops selected files the status no longer lists and pending work of
    /// closed tabs (the Dart `_sync`).
    pub fn sync(&self) {
        let open: HashSet<u64> = self
            .workspace
            .with_tabs(|tabs, _, _| tabs.iter().map(|tab| tab.id).collect());
        let mut changed = false;
        for tab in open.iter().copied() {
            let Some(status) = self.status(tab) else {
                continue;
            };
            let current: HashSet<String> = status.entries.iter().map(change_key).collect();
            self.with_tab(tab, |state| {
                let selection = &state.selection;
                if !selection.staged.iter().all(|key| current.contains(key))
                    || !selection.unstaged.iter().all(|key| current.contains(key))
                {
                    state.selection.staged.retain(|key| current.contains(key));
                    state.selection.unstaged.retain(|key| current.contains(key));
                    changed = true;
                }
            });
        }
        self.tabs.borrow_mut().retain(|tab, state| {
            if open.contains(tab) {
                return true;
            }
            state.pending.clear();
            false
        });
        if changed {
            self.notify();
        }
    }

    /// Selects `keys` on `side`, which becomes the focused list.
    pub fn select(&self, tab: u64, side: NativeStagingSide, keys: HashSet<String>) {
        self.with_tab(tab, |state| {
            state.selection_revision += 1;
            state.selection = Selection {
                staged: if side == NativeStagingSide::Staged {
                    keys.clone()
                } else {
                    HashSet::new()
                },
                unstaged: if side == NativeStagingSide::Unstaged {
                    keys
                } else {
                    HashSet::new()
                },
                focused: side,
            };
        });
        self.notify();
    }

    /// Makes `side` the list Space and the diff follow.
    pub fn focus(&self, tab: u64, side: NativeStagingSide) {
        let changed = self.with_tab(tab, |state| {
            if state.selection.focused == side {
                return false;
            }
            state.selection_revision += 1;
            state.selection.focused = side;
            true
        });
        if changed {
            self.notify();
        }
    }

    /// Keeps only the selected files a filter still shows.
    pub fn retain(&self, tab: u64, shown: &HashSet<String>) {
        self.with_tab(tab, |state| {
            state.selection_revision += 1;
            state.selection.staged.retain(|key| shown.contains(key));
            state.selection.unstaged.retain(|key| shown.contains(key));
        });
        self.notify();
    }

    pub fn set_diff_rows_selected(&self, tab: u64, selected: bool) {
        self.with_tab(tab, |state| state.diff_rows_selected = selected);
    }

    /// The selected entries of `side`, in status order.
    pub fn selected_entries(&self, tab: u64, side: NativeStagingSide) -> Vec<NativeStatusEntry> {
        let Some(status) = self.status(tab) else {
            return Vec::new();
        };
        let keys = self.with_tab(tab, |state| state.selection.of(side).clone());
        entries_on(&status, side)
            .into_iter()
            .filter(|entry| keys.contains(&change_key(entry)))
            .collect()
    }

    /// The selection commands with nothing to act on.
    pub fn disabled_selection_commands(&self, tab: u64) -> Vec<&'static str> {
        let (selection, diff_selected) = self.with_tab(tab, |state| {
            (state.selection.clone(), state.diff_rows_selected)
        });
        let unstaged = !selection.unstaged.is_empty()
            || (selection.focused == NativeStagingSide::Unstaged && diff_selected);
        let staged = !selection.staged.is_empty()
            || (selection.focused == NativeStagingSide::Staged && diff_selected);
        let discard = (selection.focused == NativeStagingSide::Unstaged && diff_selected)
            || discard_kind_of(&self.selected_entries(tab, NativeStagingSide::Unstaged)).is_some();
        let mut disabled = Vec::new();
        if !unstaged {
            disabled.push("stageSelection");
        }
        if !staged {
            disabled.push("unstageSelection");
        }
        if !discard {
            disabled.push("discardChanges");
        }
        if !unstaged && !staged {
            disabled.push("stageToggle");
        }
        disabled
    }

    /// The file the diff shows: `selected` when it names a changed file,
    /// else the first highlighted row of the focused list.
    pub fn detail_identity(&self, tab: u64, selected: Option<String>) -> Option<String> {
        let Some(status) = self.status(tab) else {
            return selected;
        };
        if let Some(selected) = &selected
            && status
                .entries
                .iter()
                .any(|entry| &display_identity(entry) == selected)
        {
            return Some(selected.clone());
        }
        let focused = self.with_tab(tab, |state| state.selection.focused);
        match self.selected_entries(tab, focused).first() {
            Some(entry) => Some(display_identity(entry)),
            None => selected,
        }
    }

    /// Stages or unstages the selection of `side`: its chosen diff lines
    /// when the diff of that list has some, otherwise its selected files.
    pub fn stage_selection(&self, tab: u64, side: NativeStagingSide) {
        let (rows, focused) = self.with_tab(tab, |state| {
            (state.diff_rows_selected, state.selection.focused)
        });
        if rows && focused == side {
            self.effect(ChangesEffect::DiffSelectionRequested {
                tab,
                discard: false,
            });
            return;
        }
        let entries = self.selected_entries(tab, side);
        if !entries.is_empty() {
            let this = self.this();
            rt::spawn_detached(async move {
                this.stage(
                    tab,
                    side,
                    NativeStagingScope::Files,
                    entries,
                    None,
                    Vec::new(),
                    None,
                )
                .await
            });
        }
    }

    /// Space: stages or unstages what the focused list selects.
    pub fn toggle_focused(&self, tab: u64) {
        let (rows, side) = self.with_tab(tab, |state| {
            (state.diff_rows_selected, state.selection.focused)
        });
        if rows {
            self.effect(ChangesEffect::DiffSelectionRequested {
                tab,
                discard: false,
            });
            return;
        }
        self.stage_selection(tab, side);
    }

    /// Discards the selected diff lines, or the selected unstaged files.
    pub fn discard_selection(&self, tab: u64) {
        if self.with_tab(tab, |state| state.diff_rows_selected) {
            self.effect(ChangesEffect::DiffSelectionRequested { tab, discard: true });
            return;
        }
        let entries = self.selected_entries(tab, NativeStagingSide::Unstaged);
        let this = self.this();
        rt::spawn_detached(async move { this.discard(tab, entries, None, Vec::new()).await });
    }

    /// The file to select after `moving` leave `side`.
    pub fn next_selection(
        status: &NativeRepositoryStatus,
        side: NativeStagingSide,
        moving: &[NativeStatusEntry],
    ) -> Option<String> {
        let source = entries_on(status, side);
        let keys: HashSet<String> = moving.iter().map(change_key).collect();
        let anchor = source
            .iter()
            .position(|entry| keys.contains(&change_key(entry)))?;
        source[anchor..]
            .iter()
            .find(|entry| !keys.contains(&change_key(entry)))
            .or_else(|| {
                source[..anchor]
                    .iter()
                    .rev()
                    .find(|entry| !keys.contains(&change_key(entry)))
            })
            .map(display_identity)
    }

    /// Stages (or, from the staged list, unstages) `entries`, or the lines
    /// `row_ids` of the accepted diff `accepted_request`.
    #[allow(clippy::too_many_arguments)]
    pub async fn stage(
        &self,
        tab: u64,
        side: NativeStagingSide,
        scope: NativeStagingScope,
        entries: Vec<NativeStatusEntry>,
        accepted_request: Option<u64>,
        row_ids: Vec<String>,
        shown_detail: Option<String>,
    ) {
        let Some(identity) = self.identity(tab) else {
            return;
        };
        if self.disposed.get() || self.status(tab).is_none() || self.refused(tab, "stageSelection")
        {
            return;
        }
        if self.busy(tab) && (scope != NativeStagingScope::Files || !self.can_stage_files(tab)) {
            return;
        }
        let reserved = self.pending_keys(tab, side);
        let selected: Vec<NativeStatusEntry> = if scope == NativeStagingScope::Files {
            entries
                .into_iter()
                .filter(|entry| !reserved.contains(&change_key(entry)))
                .collect()
        } else {
            entries
        };
        if scope == NativeStagingScope::Files && selected.is_empty() {
            return;
        }
        let paths = selected
            .iter()
            .map(|entry| path_bytes(&entry.path))
            .collect::<Vec<_>>();
        let revision = self.with_tab(tab, |state| state.selection_revision);
        let start = self.with_tab(tab, |state| {
            state.stopped_pending = 0;
            // Merge only the tail so opposite-side actions keep their order.
            if scope == NativeStagingScope::Files
                && let Some(tail) = state.pending.last_mut()
                && tail.scope == scope
                && tail.side == side
                && tail.identity == identity
                && tail.paths.len() + paths.len() <= STAGE_PATHS
            {
                tail.entries.extend(selected.iter().cloned());
                tail.paths.extend(paths.iter().cloned());
                tail.selection_revision = revision;
                return false;
            }
            state.pending.push(StageIntent {
                identity,
                side,
                scope,
                entries: selected,
                paths,
                accepted_request,
                row_ids,
                shown_detail,
                selection_revision: revision,
            });
            state.running.is_none() && state.pending.len() == 1
        });
        self.notify();
        if start {
            self.drain_stages(tab).await;
        }
    }

    async fn drain_stages(&self, tab: u64) {
        let this = self.this();
        self.busy
            .run(Some(tab), BusyActivity::Changes, false, None, async move {
                loop {
                    let intent = this.with_tab(tab, |state| {
                        if state.pending.is_empty() {
                            return None;
                        }
                        let intent = state.pending.remove(0);
                        state.running =
                            Some((intent.side, intent.entries.iter().map(change_key).collect()));
                        state.phase = Some(NativeStagingPhase::Waiting);
                        Some(intent)
                    });
                    let Some(intent) = intent else { break };
                    this.notify();
                    if !this.session_open(tab, intent.identity) {
                        break;
                    }
                    if !this.execute_stage(tab, intent).await {
                        break;
                    }
                }
                let identity = this.identity(tab);
                this.with_tab(tab, |state| {
                    if !state.pending.is_empty()
                        && identity.is_some_and(|identity| state.pending[0].identity == identity)
                    {
                        state.stopped_pending = state.pending.len();
                    }
                    state.pending.clear();
                    state.running = None;
                    state.phase = None;
                });
                this.notify();
            })
            .await;
    }

    async fn execute_stage(&self, tab: u64, intent: StageIntent) -> bool {
        let Some(status) = self.status(tab) else {
            return false;
        };
        let side = intent.side;
        let scope = intent.scope;
        let next = if scope == NativeStagingScope::Rows {
            intent.shown_detail.clone()
        } else {
            Self::next_selection(&status, side, &intent.entries)
        };
        self.effect(ChangesEffect::MoveStarted {
            tab,
            side,
            keys: intent.entries.iter().map(change_key).collect(),
            single: scope == NativeStagingScope::Files && intent.entries.len() == 1,
        });
        let mut moved = false;
        // Staging phases while the write runs.
        let polling = Rc::new(Cell::new(true));
        {
            let polling = Rc::clone(&polling);
            let this = self.this();
            let identity = intent.identity;
            rt::spawn_detached(async move {
                while polling.get() {
                    rt::sleep(Duration::from_millis(150)).await;
                    if !polling.get() {
                        break;
                    }
                    let phase = this
                        .calls
                        .repository_session_staging_phase(identity.native_id, identity.generation)
                        .await;
                    if let Ok(Some(phase)) = phase
                        && phase != NativeStagingPhase::Idle
                        && polling.get()
                        && this.session_open(tab, identity)
                    {
                        let changed =
                            this.with_tab(tab, |state| state.phase.replace(phase) != Some(phase));
                        if changed {
                            this.notify();
                        }
                    }
                }
            });
        }
        let paths = if scope == NativeStagingScope::Files {
            intent.paths.clone()
        } else {
            Vec::new()
        };
        let batches = if paths.is_empty() {
            1
        } else {
            paths.len().div_ceil(STAGE_PATHS)
        };
        let mut outcome: Result<
            (
                NativeStagingExecutionState,
                Option<NativeStagingFailureCode>,
            ),
            FailureCode,
        > = Ok((NativeStagingExecutionState::Failed, None));
        for batch in 0..batches {
            let slice = if paths.is_empty() {
                Vec::new()
            } else {
                paths[batch * STAGE_PATHS..((batch + 1) * STAGE_PATHS).min(paths.len())].to_vec()
            };
            let request = NativeStagingRequest {
                request_id: intent.accepted_request.unwrap_or(0),
                side,
                scope,
                paths: slice,
                row_ids: intent.row_ids.clone(),
            };
            outcome = self.execute_staging(intent.identity, request).await;
            if let Ok((state, _)) = &outcome {
                moved |= matches!(
                    state,
                    NativeStagingExecutionState::Completed
                        | NativeStagingExecutionState::ReconciledWithWarning
                );
            }
            if !matches!(outcome, Ok((NativeStagingExecutionState::Completed, _)))
                || !self.session_open(tab, intent.identity)
            {
                break;
            }
        }
        polling.set(false);
        if !self.session_open(tab, intent.identity) {
            return false;
        }
        let proceed = match outcome {
            Ok((state, diagnostic)) => {
                if matches!(
                    state,
                    NativeStagingExecutionState::Completed
                        | NativeStagingExecutionState::ReconciledWithWarning
                ) {
                    if self.with_tab(tab, |current| current.selection_revision)
                        == intent.selection_revision
                    {
                        self.follow_move(tab, &status, side, &intent.entries, next);
                    }
                } else {
                    self.effect(ChangesEffect::ActionFailed { tab, side });
                }
                self.report_staging(state, diagnostic);
                state == NativeStagingExecutionState::Completed
            }
            Err(code) => {
                self.effect(ChangesEffect::ActionFailed { tab, side });
                self.report_failure(code, "stagingFailed");
                false
            }
        };
        self.effect(ChangesEffect::MoveEnded { tab, moved });
        proceed
    }

    /// Runs one staging request; a stale whole-file intent is rebuilt once.
    async fn execute_staging(
        &self,
        identity: SessionIdentity,
        request: NativeStagingRequest,
    ) -> Result<
        (
            NativeStagingExecutionState,
            Option<NativeStagingFailureCode>,
        ),
        FailureCode,
    > {
        let run = |request: NativeStagingRequest| {
            self.calls.repository_session_staging_execute(
                identity.native_id,
                identity.generation,
                request,
            )
        };
        let scope = request.scope;
        let retry = NativeStagingRequest {
            request_id: 0,
            row_ids: Vec::new(),
            ..request.clone()
        };
        let mut result = run(request)
            .await
            .map_err(|error| crate::session::SessionError::from(error).code())?;
        if result.state == NativeStagingExecutionState::Stale && scope != NativeStagingScope::Rows {
            result = run(retry)
                .await
                .map_err(|error| crate::session::SessionError::from(error).code())?;
        }
        if let Some(failure) = &result.failure
            && result.state == NativeStagingExecutionState::Failed
            && result.diagnostic.is_none()
        {
            return Err(FailureCode::from(failure));
        }
        Ok((
            result.state,
            result.diagnostic.map(|diagnostic| diagnostic.code),
        ))
    }

    fn follow_move(
        &self,
        tab: u64,
        status: &NativeRepositoryStatus,
        side: NativeStagingSide,
        entries: &[NativeStatusEntry],
        next: Option<String>,
    ) {
        let moving: HashSet<String> = entries.iter().map(change_key).collect();
        self.with_tab(tab, |state| {
            let selection = &state.selection;
            let source: HashSet<String> = selection.of(side).difference(&moving).cloned().collect();
            let (mut staged, mut unstaged) = if side == NativeStagingSide::Staged {
                (source, selection.unstaged.clone())
            } else {
                (selection.staged.clone(), source)
            };
            let mut focused = selection.focused;
            if let Some(next) = &next {
                // The next file of the same list takes the selection.
                if side == NativeStagingSide::Staged {
                    unstaged.clear();
                } else {
                    staged.clear();
                }
                if let Some(entry) = entries_on(status, side)
                    .into_iter()
                    .find(|entry| &display_identity(entry) == next)
                {
                    let keys = HashSet::from([change_key(&entry)]);
                    if side == NativeStagingSide::Staged {
                        staged = keys;
                    } else {
                        unstaged = keys;
                    }
                    focused = side;
                }
            } else if let Some(first) = entries.first() {
                // The last file follows itself to the other list.
                let keys = HashSet::from([change_key(first)]);
                if side == NativeStagingSide::Staged {
                    unstaged = keys;
                } else {
                    staged = keys;
                }
                focused = other_side(side);
            }
            state.selection = Selection {
                staged,
                unstaged,
                focused,
            };
        });
        self.notify();
        let identity = next.or_else(|| entries.first().map(display_identity));
        if let Some(identity) = identity
            && self.workspace.active_tab_id() == Some(tab)
        {
            self.navigator.select_identity(identity);
        }
    }

    fn refused(&self, _tab: u64, _command: &str) -> bool {
        // Remote access rules arrive with remote workspaces.
        false
    }

    fn report_staging(
        &self,
        state: NativeStagingExecutionState,
        diagnostic: Option<NativeStagingFailureCode>,
    ) {
        let (key, error) = match state {
            NativeStagingExecutionState::Completed => ("stagingCompleted", false),
            NativeStagingExecutionState::Stale => ("stagingStale", true),
            NativeStagingExecutionState::Failed => (
                diagnostic.map_or("stagingFailed", staging_failure_key),
                true,
            ),
            NativeStagingExecutionState::ReconciledWithWarning => ("stagingWarning", false),
            NativeStagingExecutionState::OutcomeUncertain => ("mutationOutcomeUncertain", true),
        };
        if error {
            self.notices.error(key, Value::Null);
        } else {
            self.notices.status(key, Value::Null);
        }
    }

    /// The message every workflow shows for a session failure.
    pub fn report_failure(&self, code: FailureCode, operation: &str) {
        // A remote write whose outcome is unknown waits for review under Remote changes.
        if code == FailureCode::RemoteOutcomeUnknown {
            let key = if operation == "stagingFailed" {
                "remoteOutcomeUnknownStage"
            } else {
                "remoteOutcomeUnknownChange"
            };
            self.notices.error(key, Value::Null);
            return;
        }
        self.notices.error(
            "operationFailureWithReason",
            json!({"operation": {"l10n": operation}, "reason": {"l10n": failure_reason_key(code)}}),
        );
    }

    /// Reviews every part of the selection before cleaning new files and
    /// restoring tracked changes.
    pub async fn discard(
        &self,
        tab: u64,
        entries: Vec<NativeStatusEntry>,
        accepted_request: Option<u64>,
        row_ids: Vec<String>,
    ) {
        let kind = if accepted_request.is_some() {
            Some(NativeDiscardKind::Discard)
        } else {
            discard_kind_of(&entries)
        };
        if kind.is_none()
            || entries.is_empty()
            || self.busy(tab)
            || self.refused(tab, "discardChanges")
        {
            return;
        }
        let Some(identity) = self.identity(tab) else {
            return;
        };
        let current =
            || self.workspace.active_tab_id() == Some(tab) && self.identity(tab) == Some(identity);
        if !current() {
            return;
        }
        let this = self.this();
        self.busy
            .run(Some(tab), BusyActivity::Changes, false, None, async move {
                let requests: Vec<NativeDiscardRequest> = match accepted_request {
                    Some(request) => vec![NativeDiscardRequest {
                        kind: NativeDiscardKind::Discard,
                        scope: NativeDiscardScope::Rows,
                        working_diff_request_id: Some(request),
                        paths: Vec::new(),
                        row_ids,
                    }],
                    None => [NativeDiscardKind::Clean, NativeDiscardKind::Discard]
                        .into_iter()
                        .filter_map(|part| {
                            let clean = part == NativeDiscardKind::Clean;
                            let chosen: Vec<NativeStatusEntry> = entries
                                .iter()
                                .filter(|entry| {
                                    (entry.kind == NativeStatusEntryKind::Untracked) == clean
                                })
                                .cloned()
                                .collect();
                            (!chosen.is_empty()).then(|| NativeDiscardRequest {
                                kind: part,
                                scope: NativeDiscardScope::Files,
                                working_diff_request_id: None,
                                paths: unique_command_paths(&chosen),
                                row_ids: Vec::new(),
                            })
                        })
                        .collect(),
                };
                let mut previews = Vec::new();
                for request in requests {
                    if !current() {
                        return;
                    }
                    match this
                        .calls
                        .repository_session_discard_preview(
                            identity.native_id,
                            identity.generation,
                            request,
                        )
                        .await
                    {
                        Ok(result) => match (result.preview, result.failure) {
                            (Some(preview), None) => previews.push(preview),
                            (_, Some(failure)) => {
                                return this
                                    .report_failure(FailureCode::from(&failure), "discardFailed");
                            }
                            _ => {
                                return this
                                    .report_failure(FailureCode::InvalidOutput, "discardFailed");
                            }
                        },
                        Err(error) => {
                            return this.report_failure(
                                crate::session::SessionError::from(error).code(),
                                "discardFailed",
                            );
                        }
                    }
                }
                let total: u64 = previews.iter().map(|preview| preview.file_count).sum();
                let tracked: u64 = previews
                    .iter()
                    .filter(|preview| preview.kind == NativeDiscardKind::Discard)
                    .map(|preview| preview.file_count)
                    .sum();
                let untracked: u64 = previews
                    .iter()
                    .filter(|preview| preview.kind == NativeDiscardKind::Clean)
                    .map(|preview| preview.file_count)
                    .sum();
                let answer = this
                    .prompts
                    .ask(
                        "confirmDiscard",
                        json!({"trackedFiles": tracked, "untrackedFiles": untracked}),
                    )
                    .await;
                if answer != Some(Value::Bool(true)) || !current() {
                    return;
                }
                let started = accepted_request.is_none();
                if started {
                    this.effect(ChangesEffect::MoveStarted {
                        tab,
                        side: NativeStagingSide::Unstaged,
                        keys: entries.iter().map(change_key).collect(),
                        single: false,
                    });
                }
                let mut moved = false;
                let mut completed = 0u64;
                let mut warning = false;
                for preview in previews {
                    if !current() {
                        break;
                    }
                    let result = this
                        .calls
                        .repository_session_discard_execute(
                            identity.native_id,
                            identity.generation,
                            preview.token,
                        )
                        .await;
                    let state = match result {
                        Ok(result) => result.state,
                        Err(error) => {
                            this.report_discard_stop(completed, total, || {
                                this.report_failure(
                                    crate::session::SessionError::from(error).code(),
                                    "discardFailed",
                                )
                            });
                            break;
                        }
                    };
                    if !matches!(
                        state,
                        NativeDiscardExecutionState::Completed
                            | NativeDiscardExecutionState::ReconciledWithWarning
                    ) {
                        moved |= state == NativeDiscardExecutionState::OutcomeUncertain;
                        this.report_discard_stop(completed, total, || this.report_discard(state));
                        if started {
                            this.effect(ChangesEffect::MoveEnded { tab, moved });
                        }
                        return;
                    }
                    moved = true;
                    completed += preview.file_count;
                    warning |= state == NativeDiscardExecutionState::ReconciledWithWarning;
                }
                if completed == total {
                    this.report_discard(if warning {
                        NativeDiscardExecutionState::ReconciledWithWarning
                    } else {
                        NativeDiscardExecutionState::Completed
                    });
                }
                if started {
                    this.effect(ChangesEffect::MoveEnded { tab, moved });
                }
            })
            .await;
    }

    fn report_discard_stop(&self, completed: u64, total: u64, otherwise: impl FnOnce()) {
        if completed > 0 {
            self.notices.error(
                "discardPartial",
                json!({"completed": completed, "total": total}),
            );
        } else {
            otherwise();
        }
    }

    fn report_discard(&self, state: NativeDiscardExecutionState) {
        let (key, error) = match state {
            NativeDiscardExecutionState::Completed => ("discardCompleted", false),
            NativeDiscardExecutionState::Stale => ("discardStale", false),
            NativeDiscardExecutionState::Failed => ("discardFailed", false),
            NativeDiscardExecutionState::ReconciledWithWarning => ("discardWarning", false),
            NativeDiscardExecutionState::OutcomeUncertain => ("mutationOutcomeUncertain", true),
        };
        if error {
            self.notices.error(key, Value::Null);
        } else {
            self.notices.status(key, Value::Null);
        }
    }

    pub fn dispose(&self) {
        self.disposed.set(true);
        self.tabs.borrow_mut().clear();
    }
}

pub fn staging_failure_key(code: NativeStagingFailureCode) -> &'static str {
    match code {
        NativeStagingFailureCode::IndexLocked => "stagingFailureIndexLocked",
        NativeStagingFailureCode::IndexChanged | NativeStagingFailureCode::ContentChanged => {
            "stagingStale"
        }
        NativeStagingFailureCode::StatusRead => "stagingFailureStatusRead",
        NativeStagingFailureCode::IndexRead | NativeStagingFailureCode::IndexUnsafe => {
            "stagingFailureIndexRead"
        }
        NativeStagingFailureCode::ContentRead => "stagingFailureContentRead",
        NativeStagingFailureCode::IndexPrepare | NativeStagingFailureCode::IndexInstall => {
            "stagingFailureIndexWrite"
        }
        NativeStagingFailureCode::GitLaunch => "gitUnavailable",
        NativeStagingFailureCode::GitTimeout => "operationFailureTimeout",
        NativeStagingFailureCode::GitFailed => "stagingFailureGit",
        NativeStagingFailureCode::InvalidRequest | NativeStagingFailureCode::PatchUnavailable => {
            "operationFailureInvalidRequest"
        }
        NativeStagingFailureCode::RepositoryUnavailable => "stagingFailed",
    }
}

/// The reason part of a session failure message (operationFailureReason).
pub fn failure_reason_key(code: FailureCode) -> &'static str {
    match code {
        FailureCode::Canceled => "operationFailureCanceled",
        FailureCode::TooLarge => "operationFailureLimit",
        FailureCode::TimedOut => "operationFailureTimeout",
        FailureCode::PermissionDenied => "repositoryPermissionDenied",
        FailureCode::MissingGit => "gitUnavailable",
        FailureCode::MissingObject => "operationFailureMissingObject",
        FailureCode::InvalidOptions | FailureCode::InvalidOutput => {
            "operationFailureInvalidRequest"
        }
        FailureCode::Capacity => "operationFailureBusy",
        FailureCode::RemoteDisconnected => "remoteCommandDisconnected",
        FailureCode::RemoteNotOffered => "remoteCommandUnsupported",
        FailureCode::RemoteWriteNotPermitted => "remoteCommandWritesUnavailable",
        _ => "operationFailureRead",
    }
}
