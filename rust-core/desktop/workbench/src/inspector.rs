//! One inspector: its location, Back/Forward
//! stack and the reads behind it. A native session keeps a single committed
//! diff, so one session serves one inspector and every navigation reloads
//! it.
//!
//! Ported so far: commit and comparison targets, the changed-files scope,
//! the diff lens (whole target or one file) with paging and syntax, Back,
//! Forward, Up and retry. The contents, blame and history lenses and the
//! All files tree follow.

use crate::backend::SessionCalls;
use crate::diff_doc::{DIFF_PAGE_ROWS, DiffDocument};
use crate::history::{HistorySelection, HistoryService, SelectionOrigin};
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::session::{FailureCode, SessionError, SessionIdentity, SessionResult, check, required};
use gitlama_contract::diff::{NativeDiffLayout, NativeDiffSyntaxOrigin};
use gitlama_contract::dto::{
    NativeCommitDiffOptions, NativeCommitFile, NativeCommitInspection, NativeDiffWhitespace,
    NativeFileChangeKind,
};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::{Rc, Weak};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Target {
    Commit(String),
    Comparison { base: String, commit: String },
}

impl Target {
    pub fn commit(&self) -> &str {
        match self {
            Target::Commit(commit) | Target::Comparison { commit, .. } => commit,
        }
    }

    pub fn base(&self) -> Option<&str> {
        match self {
            Target::Commit(_) => None,
            Target::Comparison { base, .. } => Some(base),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Scope {
    Changed,
    All,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lens {
    Diff,
    Contents,
    Blame,
    History,
}

impl Lens {
    pub fn name(self) -> &'static str {
        match self {
            Lens::Diff => "diff",
            Lens::Contents => "contents",
            Lens::Blame => "blame",
            Lens::History => "history",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Unavailable {
    NotChanged,
    Deleted,
    NeedsText,
    Submodule,
    Directory,
}

impl Unavailable {
    pub fn name(self) -> &'static str {
        match self {
            Unavailable::NotChanged => "notChanged",
            Unavailable::Deleted => "deleted",
            Unavailable::NeedsText => "needsText",
            Unavailable::Submodule => "submodule",
            Unavailable::Directory => "directory",
        }
    }
}

/// Where the inspector is: a target, optionally one of its paths and a lens.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Location {
    pub target: Target,
    pub scope: Scope,
    pub path: Option<Vec<u8>>,
    pub directory: bool,
    pub lens: Lens,
    /// Restricts the history lens to these lines (1-based, inclusive).
    pub lines: Option<(u64, u64)>,
    /// The history lens's selected commit.
    pub history_commit: Option<String>,
    /// The first visible row, restored by Back and Forward.
    pub anchor: u64,
}

impl Location {
    pub fn of(target: Target) -> Self {
        Self {
            target,
            scope: Scope::Changed,
            path: None,
            directory: false,
            lens: Lens::Diff,
            lines: None,
            history_commit: None,
            anchor: 0,
        }
    }

    pub fn normalized(mut self) -> Self {
        if matches!(self.target, Target::Comparison { .. }) {
            self.scope = Scope::Changed;
        }
        if self.path.as_ref().is_none_or(Vec::is_empty) {
            self.path = None;
            self.directory = false;
            self.lens = Lens::Diff;
        } else if self.directory {
            self.lens = Lens::History;
        }
        // A line range and a history selection only exist in the history
        // lens; a folder's history has no lines.
        if self.lens != Lens::History {
            self.history_commit = None;
            self.lines = None;
        } else if self.directory {
            self.lines = None;
        }
        self
    }

    pub fn same_as(&self, other: &Location) -> bool {
        self.target == other.target
            && self.scope == other.scope
            && self.path == other.path
            && self.directory == other.directory
            && self.lens == other.lens
            && self.lines == other.lines
            && self.history_commit == other.history_commit
    }
}

/// The Back/Forward stack.
#[derive(Default)]
struct Navigation {
    entries: VecDeque<Location>,
    index: Option<usize>,
}

impl Navigation {
    const CAPACITY: usize = 100;

    fn current(&self) -> Option<&Location> {
        self.entries.get(self.index?)
    }

    fn can_back(&self) -> bool {
        self.index.is_some_and(|index| index > 0)
    }

    fn can_forward(&self) -> bool {
        self.index
            .is_some_and(|index| index + 1 < self.entries.len())
    }

    fn push(&mut self, location: Location) {
        if let Some(index) = self.index {
            self.entries.truncate(index + 1);
        }
        self.entries.push_back(location);
        if self.entries.len() > Self::CAPACITY {
            self.entries.pop_front();
        }
        self.index = Some(self.entries.len() - 1);
    }

    fn replace(&mut self, location: Location) {
        match self.index {
            Some(index) => self.entries[index] = location,
            None => self.push(location),
        }
    }

    fn jump(&mut self, delta: i64) -> Option<Location> {
        let target = self.index? as i64 + delta;
        if delta == 0 || target < 0 || target as usize >= self.entries.len() {
            return None;
        }
        self.index = Some(target as usize);
        self.current().cloned()
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.index = None;
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Phase {
    #[default]
    Empty,
    Loading,
    Ready,
    Failed,
}

/// How diffs load (the stored diff view preferences).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DiffOptions {
    pub context_lines: u32,
    pub whitespace: NativeDiffWhitespace,
    pub layout: NativeDiffLayout,
}

impl Default for DiffOptions {
    fn default() -> Self {
        Self {
            context_lines: 3,
            whitespace: NativeDiffWhitespace::Preserve,
            layout: NativeDiffLayout::Unified,
        }
    }
}

impl DiffOptions {
    /// The options the stored diff view preferences choose.
    pub fn of(appearance: &gitlama_contract::storage::NativeAppearanceSettings) -> Self {
        Self {
            context_lines: appearance.diff_context_lines.min(100),
            whitespace: whitespace_of(&appearance.diff_whitespace),
            layout: if appearance.diff_layout == "sideBySide" {
                NativeDiffLayout::SideBySide
            } else {
                NativeDiffLayout::Unified
            },
        }
    }

    /// Stores these options in `appearance`.
    pub fn store(self, appearance: &mut gitlama_contract::storage::NativeAppearanceSettings) {
        appearance.diff_context_lines = self.context_lines;
        appearance.diff_whitespace = whitespace_name(self.whitespace).to_owned();
        appearance.diff_layout = match self.layout {
            NativeDiffLayout::SideBySide => "sideBySide",
            NativeDiffLayout::Unified => "unified",
        }
        .to_owned();
    }
}

/// The stored name of a whitespace mode.
pub fn whitespace_name(whitespace: NativeDiffWhitespace) -> &'static str {
    match whitespace {
        NativeDiffWhitespace::Preserve => "preserve",
        NativeDiffWhitespace::IgnoreAll => "ignoreAll",
        NativeDiffWhitespace::IgnoreAmount => "ignoreAmount",
        NativeDiffWhitespace::IgnoreEndOfLine => "ignoreEndOfLine",
    }
}

/// The whitespace mode of a stored name; unknown names preserve.
pub fn whitespace_of(name: &str) -> NativeDiffWhitespace {
    match name {
        "ignoreAll" => NativeDiffWhitespace::IgnoreAll,
        "ignoreAmount" => NativeDiffWhitespace::IgnoreAmount,
        "ignoreEndOfLine" => NativeDiffWhitespace::IgnoreEndOfLine,
        _ => NativeDiffWhitespace::Preserve,
    }
}

/// Everything the inspector shows.
#[derive(Clone, Default)]
pub struct InspectorState {
    pub location: Option<Location>,
    pub phase: Phase,
    pub failure: Option<FailureCode>,
    pub inspection: Option<Rc<NativeCommitInspection>>,
    pub diff: Option<Rc<DiffDocument>>,
    pub content_loading: bool,
    pub content_failure: Option<FailureCode>,
    pub lens_availability: Vec<(Lens, Option<Unavailable>)>,
    pub can_back: bool,
    pub can_forward: bool,
    pub all_changes_too_large: bool,
    /// The contents lens's bytes.
    pub file_bytes: Option<Rc<Vec<u8>>>,
    /// The blame lens: the first page's facts and the loaded rows by line.
    pub blame: Option<Rc<BlameView>>,
    /// The history lens: the path's commits, or a line range's.
    pub history: Option<Rc<HistoryList>>,
    /// The commit the history lens shows.
    pub history_entry: Option<Rc<NativeCommitInspection>>,
    pub history_loading_more: bool,
    pub history_more_failed: bool,
    /// The All files tree: each loaded folder's entries by its path ("" is
    /// the root), and the folders shown open.
    pub tree: HashMap<String, Rc<TreeDirectory>>,
    pub expanded: std::collections::HashSet<String>,
}

/// One folder of the All files tree, read a page at a time.
#[derive(Clone, Debug, Default)]
pub struct TreeDirectory {
    pub entries: Vec<gitlama_contract::dto::NativeTreeEntry>,
    pub next_offset: Option<u64>,
    pub loading: bool,
    pub failed: bool,
}

/// The tree key of a folder path (None is the root).
pub fn tree_key(directory: Option<&[u8]>) -> String {
    directory
        .map(|path| String::from_utf8_lossy(path).into_owned())
        .unwrap_or_default()
}

/// Entries per page of a folder.
const TREE_PAGE_ROWS: u32 = 250;

/// The blame lens's rows: the request, how many lines, and those loaded.
#[derive(Clone, Debug, Default)]
pub struct BlameView {
    pub request_id: u64,
    pub revision: String,
    pub path: Vec<u8>,
    pub total_rows: u64,
    pub rows: HashMap<u64, gitlama_contract::dto::NativeBlameRow>,
}

/// One commit of a path's (or a line range's) history.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryItem {
    pub commit: String,
    pub author: Vec<u8>,
    pub author_time: i64,
    pub summary: Vec<u8>,
    pub path: Option<Vec<u8>>,
    pub old_path: Option<Vec<u8>>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HistoryList {
    pub entries: Vec<HistoryItem>,
    pub next_offset: Option<u64>,
    pub rename_hops: u64,
    pub incomplete: bool,
    /// Lines' history (no more pages).
    pub range: bool,
}

const SYMLINK_MODE: u32 = 0xA000;
const GITLINK_MODE: u32 = 0xE000;
const MODE_TYPE: u32 = 0xF000;

/// Which lenses can show `change`.
pub fn lens_availability(
    directory: bool,
    change: Option<&NativeCommitFile>,
) -> Vec<(Lens, Option<Unavailable>)> {
    if directory {
        return vec![
            (Lens::Diff, Some(Unavailable::Directory)),
            (Lens::Contents, Some(Unavailable::Directory)),
            (Lens::Blame, Some(Unavailable::Directory)),
            (Lens::History, None),
        ];
    }
    let kind = change.map(|change| change.kind);
    let mode = change.map(|change| change.new_mode);
    let kind_of_mode = mode.map(|mode| mode & MODE_TYPE);
    let submodule =
        kind == Some(NativeFileChangeKind::Submodule) || kind_of_mode == Some(GITLINK_MODE);
    let symlink = kind_of_mode == Some(SYMLINK_MODE);
    let (contents, blame) = if kind == Some(NativeFileChangeKind::Deleted) {
        (Some(Unavailable::Deleted), Some(Unavailable::Deleted))
    } else if submodule {
        (Some(Unavailable::Submodule), Some(Unavailable::Submodule))
    } else if symlink
        || matches!(
            kind,
            Some(NativeFileChangeKind::Binary | NativeFileChangeKind::Image)
        )
    {
        (None, Some(Unavailable::NeedsText))
    } else {
        (None, None)
    };
    vec![
        (
            Lens::Diff,
            if change.is_some() {
                None
            } else {
                Some(Unavailable::NotChanged)
            },
        ),
        (Lens::Contents, contents),
        (Lens::Blame, blame),
        (Lens::History, None),
    ]
}

fn available(availability: &[(Lens, Option<Unavailable>)], lens: Lens) -> bool {
    availability
        .iter()
        .any(|(candidate, reason)| *candidate == lens && reason.is_none())
}

/// The requested lens when it can show the file, else the first that can.
pub fn sticky_lens(requested: Lens, availability: &[(Lens, Option<Unavailable>)]) -> Lens {
    if available(availability, requested) {
        return requested;
    }
    [Lens::Diff, Lens::Contents, Lens::History]
        .into_iter()
        .find(|lens| available(availability, *lens))
        .unwrap_or(Lens::History)
}

/// The path a change is listed under.
pub fn change_path(change: &NativeCommitFile) -> &[u8] {
    if change.new_path.is_empty() {
        &change.old_path
    } else {
        &change.new_path
    }
}

struct Inner {
    identity: Option<SessionIdentity>,
    navigation: Navigation,
    current: InspectorState,
    first_parent: Option<String>,
    diff_source: Option<(String, Option<String>)>,
    inspections: HashMap<String, Rc<NativeCommitInspection>>,
    inspection_order: VecDeque<String>,
    token: u64,
    diff_token: u64,
    history_token: u64,
    loading_blame_pages: std::collections::HashSet<u64>,
    tree_token: u64,
}

/// Owns one inspector.
pub struct InspectorService {
    calls: Rc<dyn SessionCalls>,
    notifier: Notifier,
    inner: RefCell<Inner>,
    options: Cell<DiffOptions>,
    /// The shown diff reads a binary file as text (Show as text); a new
    /// location reads it as Git decides again.
    force_text: Cell<bool>,
    /// Targets reached inside the inspector, for the graph to follow.
    on_target: RefCell<Option<Box<dyn Fn(&Target)>>>,
    this: RefCell<Weak<Self>>,
}

const INSPECTION_CACHE: usize = 8;
/// Blame rows per page (the contract's page rows).
const BLAME_PAGE_ROWS: u32 = 512;
/// Commits per page of a path's history.
const HISTORY_PAGE_ROWS: u32 = 100;

fn history_list(page: gitlama_contract::dto::NativePathHistoryPage) -> HistoryList {
    HistoryList {
        entries: page
            .entries
            .into_iter()
            .map(|entry| HistoryItem {
                commit: entry.commit,
                author: entry.author,
                author_time: entry.author_time,
                summary: entry.summary,
                path: Some(entry.path),
                old_path: entry.old_path,
            })
            .collect(),
        next_offset: page.next_offset,
        rename_hops: page.rename_hops,
        incomplete: page.incomplete,
        range: false,
    }
}

impl InspectorService {
    pub fn new(calls: Rc<dyn SessionCalls>, notifier: Notifier) -> Rc<Self> {
        let service = Rc::new(Self {
            calls,
            notifier,
            inner: RefCell::new(Inner {
                identity: None,
                navigation: Navigation::default(),
                current: InspectorState::default(),
                first_parent: None,
                diff_source: None,
                inspections: HashMap::new(),
                inspection_order: VecDeque::new(),
                token: 0,
                diff_token: 0,
                history_token: 0,
                loading_blame_pages: std::collections::HashSet::new(),
                tree_token: 0,
            }),
            options: Cell::new(DiffOptions::default()),
            force_text: Cell::new(false),
            on_target: RefCell::new(None),
            this: RefCell::new(Weak::new()),
        });
        *service.this.borrow_mut() = Rc::downgrade(&service);
        service
    }

    pub fn current(&self) -> InspectorState {
        self.inner.borrow().current.clone()
    }

    pub fn identity(&self) -> Option<SessionIdentity> {
        self.inner.borrow().identity
    }

    pub fn diff_options(&self) -> DiffOptions {
        self.options.get()
    }

    /// Calls `listener` with targets reached by Back, Forward or Show Commit.
    pub fn on_target(&self, listener: impl Fn(&Target) + 'static) {
        *self.on_target.borrow_mut() = Some(Box::new(listener));
    }

    fn publish(&self, state: InspectorState) {
        self.inner.borrow_mut().current = state;
        self.notifier.notify(Topics::INSPECTOR);
    }

    fn update(&self, change: impl FnOnce(&mut InspectorState)) {
        change(&mut self.inner.borrow_mut().current);
        self.notifier.notify(Topics::INSPECTOR);
    }

    /// Starts serving `identity`; another session discards everything.
    pub fn attach(&self, identity: SessionIdentity) {
        if self.inner.borrow().identity == Some(identity) {
            return;
        }
        self.reset();
        self.inner.borrow_mut().identity = Some(identity);
    }

    /// Forgets the session, the stack and everything shown.
    pub fn detach(&self) {
        self.reset();
        self.inner.borrow_mut().identity = None;
        self.publish(InspectorState::default());
    }

    fn reset(&self) {
        let diff = {
            let mut inner = self.inner.borrow_mut();
            inner.token += 1;
            inner.diff_token += 1;
            inner.navigation.clear();
            inner.inspections.clear();
            inner.inspection_order.clear();
            inner.first_parent = None;
            inner.diff_source = None;
            inner.current.diff.take()
        };
        if let Some(diff) = diff {
            diff.retire();
        }
        if self.inner.borrow().current.phase != Phase::Empty {
            self.publish(InspectorState::default());
        }
    }

    /// Shows `location`; `push` adds it after the current entry, otherwise
    /// it replaces the current entry. `from_host` marks a navigation the
    /// graph asked for, which is not echoed back to it.
    pub async fn navigate(
        &self,
        location: Location,
        push: bool,
        from_host: bool,
        parent_hint: Option<Vec<String>>,
    ) {
        self.force_text.set(false);
        if let Some(next) = self.record(location, push) {
            self.show(next, !from_host, parent_hint, false).await;
        }
    }

    /// The synchronous start of [`Self::navigate`]: records `location` in
    /// the navigation and returns it when it still has to be shown.
    fn record(&self, location: Location, push: bool) -> Option<Location> {
        self.inner.borrow().identity?;
        let next = location.normalized();
        let mut inner = self.inner.borrow_mut();
        let shown = inner.navigation.current().cloned();
        if let Some(shown) = shown
            && shown.same_as(&next)
        {
            if inner.current.phase != Phase::Failed && inner.current.content_failure.is_none() {
                if !push {
                    inner.navigation.replace(next.clone());
                    inner.current.location = Some(next);
                }
                return None;
            }
            inner.navigation.replace(next.clone());
        } else if push {
            inner.navigation.push(next.clone());
        } else {
            inner.navigation.replace(next.clone());
        }
        Some(next)
    }

    /// Navigates to `location` for the graph: recorded now, as a link's
    /// navigation starts synchronously, and shown unless another
    /// navigation replaced it meanwhile.
    fn navigate_for_graph(self: &Rc<Self>, location: Location, parent_hint: Option<Vec<String>>) {
        let Some(next) = self.record(location, true) else {
            return;
        };
        let shown = Rc::clone(self);
        rt::spawn_detached(async move {
            let current = shown
                .inner
                .borrow()
                .navigation
                .current()
                .is_some_and(|location| location.same_as(&next));
            if current {
                shown.show(next, false, parent_hint, false).await;
            }
        });
    }

    /// Loads the current location again, after a failure.
    pub async fn retry(&self) {
        let Some(location) = self.inner.borrow().navigation.current().cloned() else {
            return;
        };
        self.show(location, false, None, true).await;
    }

    /// Moves `delta` entries along the stack: negative goes back.
    pub async fn jump(&self, delta: i64) {
        let location = self.inner.borrow_mut().navigation.jump(delta);
        if let Some(location) = location {
            self.show(location, true, None, false).await;
        }
    }

    /// One level up: from a lens to the diff, from a file to every change,
    /// from all files to the changed ones.
    pub async fn up(&self) -> bool {
        let (location, availability) = {
            let inner = self.inner.borrow();
            (
                inner.navigation.current().cloned(),
                inner.current.lens_availability.clone(),
            )
        };
        let Some(location) = location else {
            return false;
        };
        let next = if location.path.is_none() {
            if location.scope != Scope::All {
                return false;
            }
            Location {
                scope: Scope::Changed,
                anchor: 0,
                ..location
            }
        } else if location.lens == Lens::History && location.lines.is_some() {
            Location {
                lines: None,
                history_commit: None,
                anchor: 0,
                ..location
            }
        } else if location.lens != Lens::Diff
            && available(&availability, Lens::Diff)
            && !availability.is_empty()
        {
            Location {
                lens: Lens::Diff,
                anchor: 0,
                ..location
            }
        } else {
            Location {
                path: None,
                directory: false,
                anchor: 0,
                ..location
            }
        };
        self.navigate(next, true, false, None).await;
        true
    }

    /// Records the first visible row so Back and Forward restore it.
    pub fn report_anchor(&self, anchor: u64) {
        let mut inner = self.inner.borrow_mut();
        let Some(mut location) = inner.navigation.current().cloned() else {
            return;
        };
        if location.anchor == anchor {
            return;
        }
        location.anchor = anchor;
        inner.navigation.replace(location.clone());
        if inner
            .current
            .location
            .as_ref()
            .is_some_and(|shown| shown.same_as(&location))
        {
            inner.current.location = Some(location);
        }
    }

    fn accepts(&self, identity: SessionIdentity, token: u64) -> bool {
        let inner = self.inner.borrow();
        inner.identity == Some(identity) && inner.token == token
    }

    async fn show(
        &self,
        location: Location,
        emit_target: bool,
        parent_hint: Option<Vec<String>>,
        force: bool,
    ) {
        let Some(identity) = self.inner.borrow().identity else {
            return;
        };
        let (token, previous, can_back, can_forward) = {
            let mut inner = self.inner.borrow_mut();
            inner.token += 1;
            inner.diff_token += 1;
            if let Some(diff) = inner.current.diff.take() {
                diff.retire();
            }
            (
                inner.token,
                inner.current.clone(),
                inner.navigation.can_back(),
                inner.navigation.can_forward(),
            )
        };
        let target_changed = force
            || previous.inspection.is_none()
            || previous.phase == Phase::Failed
            || previous.location.as_ref().map(|location| &location.target)
                != Some(&location.target);
        if target_changed {
            self.inner.borrow_mut().tree_token += 1;
        }
        if target_changed
            && emit_target
            && previous.location.as_ref().map(|location| &location.target) != Some(&location.target)
            && let Some(listener) = self.on_target.borrow().as_ref()
        {
            listener(&location.target);
        }
        self.publish(InspectorState {
            location: Some(location.clone()),
            phase: if target_changed {
                Phase::Loading
            } else {
                Phase::Ready
            },
            inspection: if target_changed {
                None
            } else {
                previous.inspection.clone()
            },
            content_loading: true,
            can_back,
            can_forward,
            all_changes_too_large: if target_changed {
                false
            } else {
                previous.all_changes_too_large
            },
            tree: if target_changed {
                HashMap::new()
            } else {
                previous.tree.clone()
            },
            expanded: if target_changed {
                Default::default()
            } else {
                previous.expanded.clone()
            },
            ..InspectorState::default()
        });
        let result: SessionResult<()> = async {
            let inspection = if target_changed {
                let (inspection, first_parent) = self
                    .load_target(identity, &location.target, parent_hint)
                    .await?;
                if !self.accepts(identity, token) {
                    return Ok(());
                }
                self.inner.borrow_mut().first_parent = first_parent;
                self.update(|state| {
                    state.phase = Phase::Ready;
                    state.inspection = Some(Rc::clone(&inspection));
                });
                inspection
            } else {
                previous
                    .inspection
                    .clone()
                    .expect("a shown target has its inspection")
            };
            let mut shown = location.clone();
            let change = shown
                .path
                .as_ref()
                .and_then(|path| {
                    inspection
                        .files
                        .iter()
                        .find(|file| change_path(file) == path.as_slice())
                })
                .cloned();
            // A file the target did not change is only listed in All files.
            if shown.path.is_some()
                && change.is_none()
                && !shown.directory
                && shown.scope == Scope::Changed
                && matches!(shown.target, Target::Commit(_))
            {
                shown.scope = Scope::All;
                self.inner.borrow_mut().navigation.replace(shown.clone());
                self.update(|state| state.location = Some(shown.clone()));
            }
            if shown.scope == Scope::All {
                self.ensure_tree(identity, token, &shown).await;
                if !self.accepts(identity, token) {
                    return Ok(());
                }
            }
            let mut availability = Vec::new();
            if shown.path.is_some() {
                availability = lens_availability(shown.directory, change.as_ref());
                let lens = sticky_lens(shown.lens, &availability);
                if lens != shown.lens {
                    shown.lens = lens;
                    shown = shown.normalized();
                    self.inner.borrow_mut().navigation.replace(shown.clone());
                }
            }
            self.update(|state| {
                state.location = Some(shown.clone());
                state.lens_availability = availability;
            });
            match shown.lens {
                Lens::Diff => {
                    self.load_target_diff(identity, token, &shown, &inspection, change.as_ref())
                        .await
                }
                Lens::Contents => self.load_contents(identity, token, &shown).await,
                Lens::Blame => self.load_blame(identity, token, &shown).await,
                Lens::History => self.load_history(identity, token, shown).await,
            }
        }
        .await;
        if let Err(error) = result {
            if !self.accepts(identity, token) {
                return;
            }
            crate::diagnostics::warning(
                "Inspector",
                "inspector_failed",
                &[
                    ("session_id", identity.native_id.into()),
                    ("failure", error.code().name().into()),
                ],
            );
            self.update(|state| {
                if state.inspection.is_none() {
                    state.phase = Phase::Failed;
                    state.failure = Some(error.code());
                } else {
                    state.content_failure = Some(error.code());
                }
                state.content_loading = false;
            });
        }
    }

    /// Loads the root of the All files tree and every folder on the way to
    /// the shown path, opening them.
    async fn ensure_tree(&self, identity: SessionIdentity, token: u64, location: &Location) {
        self.load_directory(identity, None, false).await;
        let Some(path) = location.path.clone() else {
            return;
        };
        let mut expanded = self.inner.borrow().current.expanded.clone();
        for (index, byte) in path.iter().enumerate() {
            if *byte != b'/' || index == 0 {
                continue;
            }
            let directory = path[..index].to_vec();
            expanded.insert(tree_key(Some(&directory)));
            if !self.accepts(identity, token) {
                return;
            }
            self.load_directory(identity, Some(directory), false).await;
        }
        if location.directory {
            expanded.insert(tree_key(Some(&path)));
            self.load_directory(identity, Some(path), false).await;
        }
        if self.accepts(identity, token) {
            self.update(|state| state.expanded = expanded);
        }
    }

    /// Shows `directory`'s entries in the All files tree, loading them once
    /// or again after a failure. None is the root.
    pub async fn expand_directory(&self, directory: Option<Vec<u8>>) {
        let Some(identity) = self.inner.borrow().identity else {
            return;
        };
        if self.inner.borrow().current.inspection.is_none() {
            return;
        }
        let key = tree_key(directory.as_deref());
        self.update(|state| {
            state.expanded.insert(key);
        });
        self.load_directory(identity, directory, false).await;
    }

    pub fn collapse_directory(&self, directory: &[u8]) {
        let key = tree_key(Some(directory));
        if self.inner.borrow().current.expanded.contains(&key) {
            self.update(|state| {
                state.expanded.remove(&key);
            });
        }
    }

    pub async fn load_more_directory(&self, directory: Option<Vec<u8>>) {
        let Some(identity) = self.inner.borrow().identity else {
            return;
        };
        self.load_directory(identity, directory, true).await;
    }

    async fn load_directory(
        &self,
        identity: SessionIdentity,
        directory: Option<Vec<u8>>,
        more: bool,
    ) {
        let Some(commit) = self
            .inner
            .borrow()
            .current
            .location
            .as_ref()
            .map(|location| location.target.commit().to_owned())
        else {
            return;
        };
        let key = tree_key(directory.as_deref());
        let loaded = self.inner.borrow().current.tree.get(&key).cloned();
        if let Some(loaded) = &loaded
            && (loaded.loading
                || (!more && !loaded.failed)
                || (more && loaded.next_offset.is_none()))
        {
            return;
        }
        let token = self.inner.borrow().tree_token;
        let offset = if more {
            loaded
                .as_ref()
                .and_then(|loaded| loaded.next_offset)
                .unwrap_or(0)
        } else {
            0
        };
        let previous_entries = loaded
            .as_ref()
            .map(|loaded| loaded.entries.clone())
            .unwrap_or_default();
        let previous_next = loaded.as_ref().and_then(|loaded| loaded.next_offset);
        self.update(|state| {
            state.tree.insert(
                key.clone(),
                Rc::new(TreeDirectory {
                    entries: previous_entries.clone(),
                    next_offset: previous_next,
                    loading: true,
                    failed: false,
                }),
            );
        });
        let result = self
            .calls
            .repository_session_tree(
                identity.native_id,
                identity.generation,
                commit,
                directory,
                offset,
                TREE_PAGE_ROWS,
            )
            .await;
        let page = match result {
            Ok(result) if result.failure.is_none() => result.page,
            _ => None,
        };
        {
            let inner = self.inner.borrow();
            if inner.identity != Some(identity) || inner.tree_token != token {
                return;
            }
        }
        self.update(|state| {
            let folder = match page {
                Some(page) => {
                    let mut entries = if more { previous_entries } else { Vec::new() };
                    entries.extend(page.entries);
                    TreeDirectory {
                        entries,
                        next_offset: page.next_offset,
                        loading: false,
                        failed: false,
                    }
                }
                None => TreeDirectory {
                    entries: previous_entries,
                    next_offset: previous_next,
                    loading: false,
                    failed: true,
                },
            };
            state.tree.insert(key, Rc::new(folder));
        });
    }

    async fn load_target(
        &self,
        identity: SessionIdentity,
        target: &Target,
        parent_hint: Option<Vec<String>>,
    ) -> SessionResult<(Rc<NativeCommitInspection>, Option<String>)> {
        if let Some(base) = target.base() {
            let inspection = self
                .inspect(identity, target.commit(), Some(base.to_owned()), None)
                .await?;
            return Ok((inspection, Some(base.to_owned())));
        }
        let inspection = self
            .inspect(identity, target.commit(), None, parent_hint)
            .await?;
        let first_parent = inspection.detail.parents.first().cloned();
        Ok((inspection, first_parent))
    }

    fn cached(&self, key: &str) -> Option<Rc<NativeCommitInspection>> {
        self.inner.borrow().inspections.get(key).cloned()
    }

    fn remember(&self, key: String, inspection: &Rc<NativeCommitInspection>) {
        let mut inner = self.inner.borrow_mut();
        if inner
            .inspections
            .insert(key.clone(), Rc::clone(inspection))
            .is_none()
        {
            inner.inspection_order.push_back(key);
            while inner.inspection_order.len() > INSPECTION_CACHE {
                if let Some(oldest) = inner.inspection_order.pop_front() {
                    inner.inspections.remove(&oldest);
                }
            }
        }
    }

    /// The detail and changed files of `commit` against `first_parent`, or
    /// against its own first parent when none is given.
    async fn inspect(
        &self,
        identity: SessionIdentity,
        commit: &str,
        first_parent: Option<String>,
        parent_hint: Option<Vec<String>>,
    ) -> SessionResult<Rc<NativeCommitInspection>> {
        let parent =
            first_parent.or_else(|| parent_hint.as_ref().and_then(|hint| hint.first().cloned()));
        let key = format!("{}:{commit}", parent.clone().unwrap_or_default());
        if let Some(cached) = self.cached(&key) {
            return Ok(cached);
        }
        let started = std::time::Instant::now();
        let read = |parent: Option<String>| {
            self.calls.repository_session_commit_inspection(
                identity.native_id,
                identity.generation,
                commit.to_owned(),
                parent,
            )
        };
        if parent.is_some() || parent_hint.is_some() {
            let result = read(parent).await?;
            check(&result.failure)?;
            let inspection = Rc::new(required(result.inspection)?);
            crate::diagnostics::debug(
                "Inspector",
                "inspector_commit_inspected",
                &[
                    ("session_id", identity.native_id.into()),
                    ("files", inspection.files.len().into()),
                    ("discovered_parent", false.into()),
                    ("elapsed_ms", (started.elapsed().as_millis() as u64).into()),
                ],
            );
            self.remember(key, &inspection);
            return Ok(inspection);
        }
        let result = read(None).await?;
        check(&result.failure)?;
        let first = Rc::new(required(result.inspection)?);
        let Some(discovered) = first.detail.parents.first().cloned() else {
            self.remember(key, &first);
            return Ok(first);
        };
        let discovered_key = format!("{discovered}:{commit}");
        if let Some(cached) = self.cached(&discovered_key) {
            return Ok(cached);
        }
        let result = read(Some(discovered)).await?;
        check(&result.failure)?;
        let inspection = Rc::new(required(result.inspection)?);
        crate::diagnostics::debug(
            "Inspector",
            "inspector_commit_inspected",
            &[
                ("session_id", identity.native_id.into()),
                ("files", inspection.files.len().into()),
                ("discovered_parent", true.into()),
                ("elapsed_ms", (started.elapsed().as_millis() as u64).into()),
            ],
        );
        self.remember(discovered_key, &inspection);
        self.remember(key, &inspection);
        Ok(inspection)
    }

    fn diff_request(
        &self,
        commit: &str,
        first_parent: Option<String>,
        change: Option<&NativeCommitFile>,
    ) -> NativeCommitDiffOptions {
        let options = self.options.get();
        let (old_path, new_path) = match change {
            Some(file) => (
                Some(if file.old_path.is_empty() {
                    file.new_path.clone()
                } else {
                    file.old_path.clone()
                }),
                Some(if file.new_path.is_empty() {
                    file.old_path.clone()
                } else {
                    file.new_path.clone()
                }),
            ),
            None => (None, None),
        };
        NativeCommitDiffOptions {
            commit: commit.to_owned(),
            first_parent,
            old_path,
            new_path,
            context_lines: options.context_lines,
            whitespace: options.whitespace,
            layout: options.layout,
            maximum_rows: DIFF_PAGE_ROWS as u32,
            force_text: self.force_text.get(),
        }
    }

    async fn load_contents(
        &self,
        identity: SessionIdentity,
        token: u64,
        location: &Location,
    ) -> SessionResult<()> {
        let Some(path) = location.path.clone() else {
            return Ok(());
        };
        let result = self
            .calls
            .repository_session_commit_file_content(
                identity.native_id,
                identity.generation,
                location.target.commit().to_owned(),
                path,
            )
            .await?;
        check(&result.failure)?;
        let bytes = required(result.bytes)?;
        if self.accepts(identity, token) {
            self.update(|state| {
                state.file_bytes = Some(Rc::new(bytes));
                state.content_loading = false;
            });
        }
        Ok(())
    }

    async fn load_blame(
        &self,
        identity: SessionIdentity,
        token: u64,
        location: &Location,
    ) -> SessionResult<()> {
        let Some(path) = location.path.clone() else {
            return Ok(());
        };
        let options = gitlama_contract::dto::NativeBlameOptions {
            revision: location.target.commit().to_owned(),
            path,
            first_line: None,
            last_line: None,
            detect_moves: true,
            detect_copies: true,
            maximum_rows: BLAME_PAGE_ROWS,
        };
        let result = self
            .calls
            .repository_session_blame_load(identity.native_id, identity.generation, options)
            .await?;
        check(&result.failure)?;
        let page = required(result.page)?;
        if self.accepts(identity, token) {
            let mut view = BlameView {
                request_id: page.request_id,
                revision: page.revision,
                path: page.path,
                total_rows: page.total_rows,
                rows: HashMap::new(),
            };
            for (index, row) in page.rows.into_iter().enumerate() {
                view.rows.insert(page.offset + index as u64, row);
            }
            self.update(|state| {
                state.blame = Some(Rc::new(view));
                state.content_loading = false;
            });
        }
        Ok(())
    }

    /// Loads the blame page holding row `index` when it is missing.
    pub async fn ensure_blame_row(&self, index: u64) {
        let (identity, token, blame) = {
            let inner = self.inner.borrow();
            (inner.identity, inner.token, inner.current.blame.clone())
        };
        let (Some(identity), Some(blame)) = (identity, blame) else {
            return;
        };
        if index >= blame.total_rows || blame.rows.contains_key(&index) {
            return;
        }
        let offset = index / u64::from(BLAME_PAGE_ROWS) * u64::from(BLAME_PAGE_ROWS);
        if !self.inner.borrow_mut().loading_blame_pages.insert(offset) {
            return;
        }
        let result = self
            .calls
            .repository_session_blame_page(
                identity.native_id,
                identity.generation,
                blame.request_id,
                offset,
                BLAME_PAGE_ROWS,
            )
            .await;
        self.inner.borrow_mut().loading_blame_pages.remove(&offset);
        let Ok(result) = result else { return };
        let Some(page) = result.page.filter(|_| result.failure.is_none()) else {
            return;
        };
        if !self.accepts(identity, token) {
            return;
        }
        self.update(|state| {
            let Some(shown) = &state.blame else { return };
            if shown.request_id != blame.request_id {
                return;
            }
            let mut view = (**shown).clone();
            for (index, row) in page.rows.into_iter().enumerate() {
                view.rows.insert(page.offset + index as u64, row);
            }
            state.blame = Some(Rc::new(view));
        });
    }

    /// Shows the blame of `row`'s file in the parent of the commit that
    /// last changed the line, at that line.
    pub async fn blame_before(&self, line: u64) {
        let (identity, row) = {
            let inner = self.inner.borrow();
            (
                inner.identity,
                inner
                    .current
                    .blame
                    .as_ref()
                    .and_then(|blame| blame.rows.get(&line).cloned()),
            )
        };
        let (Some(identity), Some(row)) = (identity, row) else {
            return;
        };
        let Some(commit) = row.commit.clone().filter(|_| !row.boundary) else {
            return;
        };
        let Ok(inspection) = self.inspect(identity, &commit, None, None).await else {
            return;
        };
        let Some(parent) = inspection.detail.parents.first().cloned() else {
            return;
        };
        if self.inner.borrow().identity != Some(identity) {
            return;
        }
        let mut location = Location::of(Target::Commit(parent));
        location.path = Some(row.original_path.clone());
        location.lens = Lens::Blame;
        location.anchor = row.original_line.saturating_sub(1);
        self.navigate(location, true, false, None).await;
    }

    /// Shows the history of `first`…`last` (1-based) of the blamed file.
    pub async fn line_history(&self, first: u64, last: u64) {
        let location = self.inner.borrow().navigation.current().cloned();
        let Some(location) = location else { return };
        let next = Location {
            lens: Lens::History,
            lines: Some((first, last)),
            history_commit: None,
            anchor: 0,
            ..location
        };
        self.navigate(next, true, false, None).await;
    }

    async fn load_history(
        &self,
        identity: SessionIdentity,
        token: u64,
        location: Location,
    ) -> SessionResult<()> {
        let Some(path) = location.path.clone() else {
            return Ok(());
        };
        let commit = location.target.commit().to_owned();
        let list = if let Some((first, last)) = location.lines {
            let result = self
                .calls
                .repository_session_range_history(
                    identity.native_id,
                    identity.generation,
                    commit,
                    path,
                    first as u32,
                    last as u32,
                    HISTORY_PAGE_ROWS,
                )
                .await?;
            check(&result.failure)?;
            HistoryList {
                entries: result
                    .entries
                    .into_iter()
                    .map(|entry| HistoryItem {
                        commit: entry.commit,
                        author: entry.author,
                        author_time: entry.author_time,
                        summary: entry.summary,
                        path: None,
                        old_path: None,
                    })
                    .collect(),
                next_offset: None,
                rename_hops: 0,
                incomplete: result.incomplete,
                range: true,
            }
        } else {
            let page = self.path_history(identity, &location, 0, 0).await?;
            history_list(page)
        };
        if !self.accepts(identity, token) {
            return Ok(());
        }
        let selected = location
            .history_commit
            .clone()
            .or_else(|| list.entries.first().map(|entry| entry.commit.clone()));
        self.update(|state| state.history = Some(Rc::new(list)));
        let Some(selected) = selected else {
            self.update(|state| state.content_loading = false);
            return Ok(());
        };
        let mut shown = location;
        if shown.history_commit.is_none() {
            shown.history_commit = Some(selected.clone());
            self.inner.borrow_mut().navigation.replace(shown.clone());
            self.update(|state| state.location = Some(shown.clone()));
        }
        self.load_history_entry(identity, token, &shown, &selected)
            .await
    }

    async fn path_history(
        &self,
        identity: SessionIdentity,
        location: &Location,
        offset: u64,
        rename_hops_before: u64,
    ) -> SessionResult<gitlama_contract::dto::NativePathHistoryPage> {
        let options = gitlama_contract::dto::NativePathHistoryOptions {
            revision: Some(location.target.commit().to_owned()),
            path: location.path.clone().unwrap_or_default(),
            directory: location.directory,
            offset,
            maximum_rows: HISTORY_PAGE_ROWS,
            rename_hops_before,
        };
        let result = self
            .calls
            .repository_session_path_history(identity.native_id, identity.generation, options)
            .await?;
        check(&result.failure)?;
        required(result.page)
    }

    /// Selects the history entry of `commit` and shows its change to the path.
    pub async fn select_history_entry(&self, commit: String) {
        let (identity, location, token) = {
            let mut inner = self.inner.borrow_mut();
            let Some(location) = inner.navigation.current().cloned() else {
                return;
            };
            if location.lens != Lens::History
                || location.history_commit.as_deref() == Some(commit.as_str())
            {
                return;
            }
            let shown = Location {
                history_commit: Some(commit.clone()),
                anchor: 0,
                ..location
            };
            inner.navigation.replace(shown.clone());
            inner.diff_token += 1;
            if let Some(diff) = inner.current.diff.take() {
                diff.retire();
            }
            (inner.identity, shown, inner.token)
        };
        let Some(identity) = identity else { return };
        self.update(|state| {
            state.location = Some(location.clone());
            state.history_entry = None;
            state.content_failure = None;
            state.content_loading = true;
        });
        if let Err(error) = self
            .load_history_entry(identity, token, &location, &commit)
            .await
            && self.accepts(identity, token)
        {
            self.update(|state| {
                state.content_loading = false;
                state.content_failure = Some(error.code());
            });
        }
    }

    async fn load_history_entry(
        &self,
        identity: SessionIdentity,
        token: u64,
        location: &Location,
        commit: &str,
    ) -> SessionResult<()> {
        let history_token = {
            let mut inner = self.inner.borrow_mut();
            inner.history_token += 1;
            inner.history_token
        };
        let current =
            || self.accepts(identity, token) && self.inner.borrow().history_token == history_token;
        let inspection = self.inspect(identity, commit, None, None).await?;
        if !current() {
            return Ok(());
        }
        if location.directory {
            self.update(|state| {
                state.history_entry = Some(inspection);
                state.content_loading = false;
            });
            return Ok(());
        }
        let path = location.path.clone().unwrap_or_default();
        let entry = self
            .inner
            .borrow()
            .current
            .history
            .as_ref()
            .and_then(|history| {
                history
                    .entries
                    .iter()
                    .find(|item| item.commit == commit)
                    .cloned()
            });
        let new_path = entry
            .as_ref()
            .and_then(|entry| entry.path.clone())
            .unwrap_or(path);
        let old_path = entry
            .and_then(|entry| entry.old_path)
            .unwrap_or_else(|| new_path.clone());
        let first_parent = inspection.detail.parents.first().cloned();
        let options = self.options.get();
        let request = NativeCommitDiffOptions {
            commit: commit.to_owned(),
            first_parent: first_parent.clone(),
            old_path: Some(old_path),
            new_path: Some(new_path),
            context_lines: options.context_lines,
            whitespace: options.whitespace,
            layout: options.layout,
            maximum_rows: DIFF_PAGE_ROWS as u32,
            force_text: self.force_text.get(),
        };
        let result = self
            .calls
            .repository_session_commit_diff_load(identity.native_id, identity.generation, request)
            .await?;
        check(&result.failure)?;
        let page = required(result.page)?;
        if !current() {
            return Ok(());
        }
        let document = DiffDocument::new(
            Rc::clone(&self.calls),
            self.notifier.clone(),
            Topics::INSPECTOR,
            identity,
            NativeDiffSyntaxOrigin::Committed,
            page,
        );
        self.inner.borrow_mut().diff_source = Some((commit.to_owned(), first_parent));
        self.update(|state| {
            state.history_entry = Some(inspection);
            state.diff = Some(document);
            state.content_loading = false;
        });
        Ok(())
    }

    /// Loads the next page of the path's history.
    pub async fn load_more_history(&self) {
        let (identity, location, history, token) = {
            let inner = self.inner.borrow();
            (
                inner.identity,
                inner.navigation.current().cloned(),
                inner.current.history.clone(),
                inner.token,
            )
        };
        let (Some(identity), Some(location), Some(history)) = (identity, location, history) else {
            return;
        };
        let Some(offset) = history
            .next_offset
            .filter(|_| location.lens == Lens::History && location.lines.is_none())
        else {
            return;
        };
        if self.inner.borrow().current.history_loading_more {
            return;
        }
        self.update(|state| {
            state.history_loading_more = true;
            state.history_more_failed = false;
        });
        let result = self
            .path_history(identity, &location, offset, history.rename_hops)
            .await;
        if !self.accepts(identity, token) {
            return;
        }
        match result {
            Ok(page) => {
                let next = history_list(page);
                self.update(|state| {
                    let mut list = (*history).clone();
                    list.entries.extend(next.entries);
                    list.next_offset = next.next_offset;
                    list.rename_hops = next.rename_hops;
                    list.incomplete |= next.incomplete;
                    state.history = Some(Rc::new(list));
                    state.history_loading_more = false;
                });
            }
            Err(_) => self.update(|state| {
                state.history_loading_more = false;
                state.history_more_failed = true;
            }),
        }
    }

    async fn load_target_diff(
        &self,
        identity: SessionIdentity,
        token: u64,
        location: &Location,
        inspection: &NativeCommitInspection,
        change: Option<&NativeCommitFile>,
    ) -> SessionResult<()> {
        let commit = location.target.commit().to_owned();
        let first_parent = self.inner.borrow().first_parent.clone();
        let started = std::time::Instant::now();
        let mut too_large_fallback = false;
        let load = |change: Option<&NativeCommitFile>| {
            self.calls.repository_session_commit_diff_load(
                identity.native_id,
                identity.generation,
                self.diff_request(&commit, first_parent.clone(), change),
            )
        };
        let mut result = load(change).await?;
        if change.is_none()
            && result.failure.as_ref().map(FailureCode::from) == Some(FailureCode::TooLarge)
        {
            too_large_fallback = true;
            // Two distant commits can differ by more than one patch may hold;
            // their file list still loads, and so does each file's diff.
            let Some(file) = inspection.files.first() else {
                return check(&result.failure);
            };
            if !self.accepts(identity, token) {
                return Ok(());
            }
            let focused = Location {
                path: Some(change_path(file).to_vec()),
                lens: Lens::Diff,
                ..location.clone()
            }
            .normalized();
            self.inner.borrow_mut().navigation.replace(focused.clone());
            self.update(|state| {
                state.location = Some(focused);
                state.lens_availability = lens_availability(false, Some(file));
                state.all_changes_too_large = true;
            });
            result = load(Some(file)).await?;
        }
        check(&result.failure)?;
        let page = required(result.page)?;
        crate::diagnostics::debug(
            "Inspector",
            "inspector_diff_loaded",
            &[
                ("session_id", identity.native_id.into()),
                ("rows", page.rows.len().into()),
                ("total_rows", page.total_rows.into()),
                ("too_large_fallback", too_large_fallback.into()),
                ("elapsed_ms", (started.elapsed().as_millis() as u64).into()),
            ],
        );
        if !self.accepts(identity, token) {
            return Ok(());
        }
        let document = DiffDocument::new(
            Rc::clone(&self.calls),
            self.notifier.clone(),
            Topics::INSPECTOR,
            identity,
            NativeDiffSyntaxOrigin::Committed,
            page,
        );
        self.inner.borrow_mut().diff_source = Some((commit, first_parent));
        self.update(|state| {
            state.diff = Some(document);
            state.content_loading = false;
        });
        Ok(())
    }

    /// The images of an image change of the shown diff, for the image diff.
    pub async fn image_diff(
        &self,
        old_path: Vec<u8>,
        new_path: Vec<u8>,
    ) -> Option<gitlama_contract::dto::NativeImageDiffResult> {
        let (identity, source) = {
            let inner = self.inner.borrow();
            (inner.identity?, inner.diff_source.clone()?)
        };
        let (commit, first_parent) = source;
        self.calls
            .repository_session_image_diff(
                identity.native_id,
                identity.generation,
                first_parent,
                commit,
                old_path,
                new_path,
                8 * 1024 * 1024,
            )
            .await
            .ok()
    }

    /// Whether the shown diff reads a binary file as text.
    pub fn force_text(&self) -> bool {
        self.force_text.get()
    }

    /// Reloads the shown diff reading its binary file as text.
    pub async fn show_as_text(&self) {
        self.force_text.set(true);
        self.update_diff_options(self.options.get()).await;
    }

    /// Reloads the shown diff with other display options, keeping its file.
    pub async fn update_diff_options(&self, options: DiffOptions) {
        self.options.set(options);
        let (identity, source, location, inspection, token) = {
            let mut inner = self.inner.borrow_mut();
            inner.diff_token += 1;
            (
                inner.identity,
                inner.diff_source.clone(),
                inner.current.location.clone(),
                inner.current.inspection.clone(),
                inner.diff_token,
            )
        };
        let (Some(identity), Some((commit, first_parent)), Some(location), Some(inspection)) =
            (identity, source, location, inspection)
        else {
            return;
        };
        let change = location.path.as_ref().and_then(|path| {
            inspection
                .files
                .iter()
                .find(|file| change_path(file) == path.as_slice())
        });
        let result = self
            .calls
            .repository_session_commit_diff_load(
                identity.native_id,
                identity.generation,
                self.diff_request(&commit, first_parent, change),
            )
            .await;
        let Ok(result) = result else { return };
        let Some(page) = result.page.filter(|_| result.failure.is_none()) else {
            return;
        };
        if self.inner.borrow().identity != Some(identity) || self.inner.borrow().diff_token != token
        {
            return;
        }
        let document = DiffDocument::new(
            Rc::clone(&self.calls),
            self.notifier.clone(),
            Topics::INSPECTOR,
            identity,
            NativeDiffSyntaxOrigin::Committed,
            page,
        );
        self.update(|state| {
            if let Some(previous) = state.diff.replace(document) {
                previous.retire();
            }
        });
    }

    /// Inspects History's selection.
    pub fn follow(self: &Rc<Self>, history: &Rc<HistoryService>) {
        let inspector = Rc::downgrade(self);
        let history_for_selection = Rc::downgrade(history);
        history.on_selection(move |selection: &HistorySelection| {
            // The graph following the inspector does not show its selection again.
            if selection.origin == SelectionOrigin::Inspector {
                return;
            }
            let (Some(inspector), Some(history)) =
                (inspector.upgrade(), history_for_selection.upgrade())
            else {
                return;
            };
            let Some(identity) = history.identity() else {
                inspector.detach();
                return;
            };
            let Some(commit) = selection.commit.clone() else {
                inspector.detach();
                inspector.attach(identity);
                return;
            };
            inspector.attach(identity);
            let target = match selection.base.clone() {
                Some(base) => Target::Comparison { base, commit },
                None => Target::Commit(commit),
            };
            let parents = if matches!(target, Target::Commit(_)) {
                selection.parents.clone()
            } else {
                None
            };
            inspector.navigate_for_graph(Location::of(target), parents);
        });
        let graph = Rc::downgrade(history);
        self.on_target(move |target| {
            let Some(history) = graph.upgrade() else {
                return;
            };
            let target = target.clone();
            rt::spawn_detached(async move {
                match target {
                    Target::Comparison { base, commit } => {
                        history
                            .select(
                                Some(base),
                                false,
                                true,
                                false,
                                0,
                                SelectionOrigin::Inspector,
                            )
                            .await;
                        history
                            .select(
                                Some(commit),
                                true,
                                false,
                                false,
                                0,
                                SelectionOrigin::Inspector,
                            )
                            .await;
                    }
                    Target::Commit(commit) => {
                        history
                            .select(
                                Some(commit),
                                false,
                                true,
                                false,
                                0,
                                SelectionOrigin::Inspector,
                            )
                            .await;
                    }
                }
            });
        });
    }

    pub fn session_error(code: FailureCode) -> SessionError {
        SessionError(code)
    }
}
