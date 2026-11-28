//! The History graph of the active tab:
//! preview, complete topology and prioritized bounded metadata, coordinated
//! independently; selection, search, collapse and the branch filter.

use crate::backend::SessionCalls;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::session::{FailureCode, SessionError, SessionIdentity, SessionResult, check, required};
use futures::future::{FutureExt, LocalBoxFuture, Shared};
use gitlama_contract::dto::{
    NativeHistoryMetadataFailure, NativeHistoryPage, NativeHistoryQueryOptions,
    NativeHistoryResult, NativeHistoryRow, NativeHistorySegmentKind, NativeHistorySelectionOptions,
};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::rc::{Rc, Weak};

pub const PAGE_ROWS: u64 = 512;
pub const METADATA_BATCH: usize = 256;
pub const BRANCH_FILTER_REFERENCES: usize = 1024;
/// The object ID of the working tree row.
pub const WORKTREE_OBJECT_ID: &str = "wip";
/// The request ID of a page presented from the view cache.
pub const CACHED_REQUEST_ID: u64 = 0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LoadPhase {
    Loading,
    Preview,
    Complete,
    Empty,
    Failed,
}

/// The branches the history graph shows; sorted and unique. Empty shows all.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub struct BranchFilter(Vec<String>);

impl BranchFilter {
    pub const NONE: BranchFilter = BranchFilter(Vec::new());

    pub fn new(references: impl IntoIterator<Item = String>) -> Self {
        let mut values: Vec<String> = references.into_iter().collect();
        values.sort();
        values.dedup();
        Self(values)
    }

    pub fn references(&self) -> &[String] {
        &self.0
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn contains(&self, reference: &str) -> bool {
        self.0.iter().any(|value| value == reference)
    }

    pub fn is_focused_on(&self, reference: &str, upstream: Option<&str>) -> bool {
        self.contains(reference)
            && self
                .0
                .iter()
                .all(|value| value == reference || Some(value.as_str()) == upstream)
    }

    pub fn focus(reference: &str, upstream: Option<&str>) -> Self {
        Self::new(std::iter::once(reference.to_owned()).chain(upstream.map(str::to_owned)))
    }

    pub fn toggled(&self, reference: &str, upstream: Option<&str>) -> Self {
        if self.contains(reference) {
            return Self::new(self.0.iter().filter(|value| *value != reference).cloned());
        }
        if self.0.len() >= BRANCH_FILTER_REFERENCES {
            return self.clone();
        }
        let mut next = self.0.clone();
        next.push(reference.to_owned());
        if let Some(upstream) = upstream
            && !self.contains(upstream)
            && self.0.len() + 1 < BRANCH_FILTER_REFERENCES
        {
            next.push(upstream.to_owned());
        }
        Self::new(next)
    }

    /// The filter a native page shows.
    pub fn of_page(page: &NativeHistoryPage) -> Self {
        Self::new(
            page.branch_filter
                .iter()
                .map(|bytes| String::from_utf8_lossy(bytes).into_owned()),
        )
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HistoryQuery {
    pub text: String,
    pub search_hash: bool,
    pub search_message: bool,
    pub search_author: bool,
    pub search_path: bool,
}

impl HistoryQuery {
    pub fn new(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            search_hash: true,
            search_message: true,
            search_author: true,
            search_path: false,
        }
    }

    pub fn active(&self) -> bool {
        !self.text.is_empty()
    }
}

/// What the History graph shows.
#[derive(Clone, Debug)]
pub struct HistoryState {
    pub phase: LoadPhase,
    pub page: Option<Rc<NativeHistoryPage>>,
    pub failure_code: Option<&'static str>,
    pub target_object_id: Option<String>,
    pub pending_query: Option<HistoryQuery>,
    pub query_failure_code: Option<&'static str>,
    pub target_not_shown: bool,
}

impl HistoryState {
    pub fn new(phase: LoadPhase) -> Self {
        Self {
            phase,
            page: None,
            failure_code: None,
            target_object_id: None,
            pending_query: None,
            query_failure_code: None,
            target_not_shown: false,
        }
    }

    fn with_page(phase: LoadPhase, page: Rc<NativeHistoryPage>) -> Self {
        Self {
            page: Some(page),
            ..Self::new(phase)
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum SelectionOrigin {
    #[default]
    Graph,
    Search,
    Reference,
    Keyboard,
    /// The inspector moved and the graph follows it.
    Inspector,
}

/// The parents the inspector compares a selected row with. A shallow clone's
/// boundary row draws the parents the clone does not have; the commit is a
/// root there, so it is compared with the empty tree instead.
fn inspection_parents(row: NativeHistoryRow) -> Vec<String> {
    if row.shape == gitlama_contract::dto::NativeHistoryNodeShape::Boundary {
        Vec::new()
    } else {
        row.parents
    }
}

/// The commit or comparison the graph selects for inspection.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HistorySelection {
    pub commit: Option<String>,
    pub base: Option<String>,
    pub parents: Option<Vec<String>>,
    pub origin: SelectionOrigin,
}

/// One drawn piece of a lane on one row.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DisplaySegment {
    pub from_lane: u32,
    pub to_lane: u32,
    pub kind: NativeHistorySegmentKind,
    pub starts_at_top: bool,
    pub ends_at_center: bool,
    pub lit: bool,
}

pub fn is_worktree(row: &NativeHistoryRow) -> bool {
    row.object_id == WORKTREE_OBJECT_ID
}

pub fn has_metadata(row: &NativeHistoryRow) -> bool {
    !row.subject.is_empty() || !row.author.is_empty() || row.metadata_failure.is_some()
}

/// Commit metadata the graph rows show.
#[derive(Clone, Debug)]
pub struct HistoryMetadata {
    pub object_id: String,
    pub subject: Vec<u8>,
    pub author: Vec<u8>,
    pub avatar_hash: String,
    pub author_time: i64,
    pub failure: Option<NativeHistoryMetadataFailure>,
}

fn with_metadata(row: &NativeHistoryRow, value: &HistoryMetadata) -> NativeHistoryRow {
    let mut next = row.clone();
    next.subject = value.subject.clone();
    next.author = value.author.clone();
    next.avatar_hash = value.avatar_hash.clone();
    next.author_time = value.author_time;
    next.metadata_failure = value.failure;
    next
}

/// Whether `page` can stand in for the history the next time it opens.
pub fn is_cacheable_page(page: &NativeHistoryPage) -> bool {
    page.topology_complete
        && page.offset == 0
        && !page.query_active
        && page.accepted_query.is_empty()
        && page.collapsed_commits == 0
        && !page.rows.is_empty()
}

fn page_of(result: NativeHistoryResult) -> SessionResult<NativeHistoryPage> {
    check(&result.failure)?;
    required(result.page)
}

/// Loaded pages with change counters, so derived lookups know when they are
/// stale.
#[derive(Default)]
struct Pages {
    by_offset: BTreeMap<u64, Rc<NativeHistoryPage>>,
    generation: u64,
    view: u64,
}

impl Pages {
    fn get(&self, offset: u64) -> Option<Rc<NativeHistoryPage>> {
        self.by_offset.get(&offset).cloned()
    }

    fn set(&mut self, page: Rc<NativeHistoryPage>) {
        self.by_offset.insert(page.offset, page);
        self.generation += 1;
    }

    fn clear(&mut self) {
        self.by_offset.clear();
        self.generation += 1;
        self.view += 1;
    }

    fn replace(&mut self, page: Rc<NativeHistoryPage>) {
        self.clear();
        self.set(page);
    }
}

type SharedUnit = Shared<LocalBoxFuture<'static, ()>>;

struct Inner {
    shown_selection: Option<(String, Option<String>)>,
    operation: u64,
    selection_operation: u64,
    retained_selected: Vec<String>,
    query_operation: u64,
    identity: Option<SessionIdentity>,
    current: HistoryState,
    disposed: bool,
    pages: Pages,
    display_segments: HashMap<String, Vec<DisplaySegment>>,
    display_generation: Option<u64>,
    row_index_generation: Option<u64>,
    row_index: HashMap<String, u64>,
    loading_pages: HashSet<u64>,
    search_query: Option<HistoryQuery>,
    search_matches: Rc<Vec<String>>,
    search_match_set: Rc<HashSet<String>>,
    search_index: i64,
    search_pending: bool,
    search_failure_code: Option<&'static str>,
    requested_filter: Option<(SessionIdentity, BranchFilter)>,
    filter_runner: Option<SharedUnit>,
    pending_filter: Option<(u64, SharedUnit)>,
    reloading_operation: Option<u64>,
    branch_filter_sequence: u64,
    pending_load: Option<(u64, SharedUnit)>,
    cache_replaced: Option<futures::channel::oneshot::Sender<()>>,
    cache_replaced_wait: Option<SharedUnit>,
    next_token: u64,
}

/// Callbacks into the workspace that owns the History graph.
#[derive(Default)]
pub struct HistoryHooks {
    /// The first page a repository showed when it was last open.
    pub cached_first_page: Option<Box<dyn Fn(SessionIdentity) -> Option<Rc<NativeHistoryPage>>>>,
    /// Receives each complete, hydrated first page as shown under its filter.
    pub on_first_page: Option<Box<dyn Fn(SessionIdentity, &Rc<NativeHistoryPage>)>>,
    /// The branch filter a repository's history should show when it loads.
    pub branch_filter_for: Option<Box<dyn Fn(SessionIdentity) -> BranchFilter>>,
    /// Whether histories also start from other references.
    pub other_refs: Option<Box<dyn Fn() -> bool>>,
}

/// Coordinates preview, complete topology and prioritized bounded metadata.
pub struct HistoryService {
    calls: Rc<dyn SessionCalls>,
    notifier: Notifier,
    hooks: RefCell<HistoryHooks>,
    selection_listeners: RefCell<Vec<Box<dyn Fn(&HistorySelection)>>>,
    inner: RefCell<Inner>,
    this: RefCell<Weak<HistoryService>>,
    revision: Cell<u64>,
}

impl HistoryService {
    pub fn new(calls: Rc<dyn SessionCalls>, notifier: Notifier) -> Rc<Self> {
        let service = Rc::new(Self {
            calls,
            notifier,
            hooks: RefCell::new(HistoryHooks::default()),
            selection_listeners: RefCell::new(Vec::new()),
            inner: RefCell::new(Inner {
                shown_selection: None,
                operation: 0,
                selection_operation: 0,
                retained_selected: Vec::new(),
                query_operation: 0,
                identity: None,
                current: HistoryState::new(LoadPhase::Empty),
                disposed: false,
                pages: Pages::default(),
                display_segments: HashMap::new(),
                display_generation: None,
                row_index_generation: None,
                row_index: HashMap::new(),
                loading_pages: HashSet::new(),
                search_query: None,
                search_matches: Rc::new(Vec::new()),
                search_match_set: Rc::new(HashSet::new()),
                search_index: -1,
                search_pending: false,
                search_failure_code: None,
                requested_filter: None,
                filter_runner: None,
                pending_filter: None,
                reloading_operation: None,
                branch_filter_sequence: 0,
                pending_load: None,
                cache_replaced: None,
                cache_replaced_wait: None,
                next_token: 0,
            }),
            this: RefCell::new(Weak::new()),
            revision: Cell::new(0),
        });
        *service.this.borrow_mut() = Rc::downgrade(&service);
        service
    }

    pub fn set_hooks(&self, hooks: HistoryHooks) {
        *self.hooks.borrow_mut() = hooks;
    }

    /// Calls `listener` with every new selection for inspection.
    pub fn on_selection(&self, listener: impl Fn(&HistorySelection) + 'static) {
        self.selection_listeners
            .borrow_mut()
            .push(Box::new(listener));
    }

    fn this(&self) -> Rc<Self> {
        self.this.borrow().upgrade().expect("history service alive")
    }

    // Reads --------------------------------------------------------------------

    pub fn current(&self) -> HistoryState {
        self.inner.borrow().current.clone()
    }

    /// Increments with every publication; the projection compares it.
    pub fn revision(&self) -> u64 {
        self.revision.get()
    }

    pub fn identity(&self) -> Option<SessionIdentity> {
        self.inner.borrow().identity
    }

    pub fn branch_filter_sequence(&self) -> u64 {
        self.inner.borrow().branch_filter_sequence
    }

    pub fn search_query(&self) -> Option<HistoryQuery> {
        self.inner.borrow().search_query.clone()
    }

    pub fn search_matches(&self) -> Rc<Vec<String>> {
        Rc::clone(&self.inner.borrow().search_matches)
    }

    pub fn search_index(&self) -> i64 {
        self.inner.borrow().search_index
    }

    pub fn search_pending(&self) -> bool {
        self.inner.borrow().search_pending
    }

    pub fn search_failure_code(&self) -> Option<&'static str> {
        self.inner.borrow().search_failure_code
    }

    pub fn is_search_match(&self, object_id: &str) -> bool {
        self.inner.borrow().search_match_set.contains(object_id)
    }

    pub fn pages_generation(&self) -> u64 {
        self.inner.borrow().pages.generation
    }

    pub fn row_at(&self, index: u64) -> Option<NativeHistoryRow> {
        let inner = self.inner.borrow();
        let offset = (index / PAGE_ROWS) * PAGE_ROWS;
        let page = inner.pages.get(offset)?;
        let local = index.checked_sub(page.offset)?;
        page.rows.get(local as usize).cloned()
    }

    /// Calls `visit` with each loaded row and its absolute index.
    pub fn for_each_loaded_row(&self, mut visit: impl FnMut(u64, &NativeHistoryRow)) {
        let inner = self.inner.borrow();
        for page in inner.pages.by_offset.values() {
            for (local, row) in page.rows.iter().enumerate() {
                visit(page.offset + local as u64, row);
            }
        }
    }

    /// Commits of the loaded pages, for reference pickers.
    pub fn reference_picker_commits(
        &self,
        identity: Option<SessionIdentity>,
    ) -> Vec<NativeHistoryRow> {
        let inner = self.inner.borrow();
        if identity.is_none() || inner.identity != identity {
            return Vec::new();
        }
        inner
            .pages
            .by_offset
            .values()
            .flat_map(|page| page.rows.iter())
            .filter(|row| !is_worktree(row))
            .cloned()
            .collect()
    }

    pub fn index_of_loaded(&self, object_id: &str) -> Option<u64> {
        self.ensure_row_index();
        self.inner.borrow().row_index.get(object_id).copied()
    }

    fn ensure_row_index(&self) {
        let mut inner = self.inner.borrow_mut();
        if inner.row_index_generation == Some(inner.pages.generation) {
            return;
        }
        let generation = inner.pages.generation;
        let mut index = HashMap::new();
        for page in inner.pages.by_offset.values() {
            for (local, row) in page.rows.iter().enumerate() {
                index
                    .entry(row.object_id.clone())
                    .or_insert(page.offset + local as u64);
            }
        }
        inner.row_index = index;
        inner.row_index_generation = Some(generation);
    }

    pub fn row_by_id(&self, object_id: &str) -> Option<NativeHistoryRow> {
        let index = self.index_of_loaded(object_id)?;
        let inner = self.inner.borrow();
        for page in inner.pages.by_offset.values() {
            let Some(local) = index.checked_sub(page.offset) else {
                continue;
            };
            if let Some(row) = page.rows.get(local as usize)
                && row.object_id == object_id
            {
                return Some(row.clone());
            }
        }
        None
    }

    /// The lane pieces drawn on the row of `object_id`.
    pub fn segments_for(&self, object_id: &str) -> Vec<DisplaySegment> {
        {
            let inner = self.inner.borrow();
            if inner.display_generation == Some(inner.pages.generation) {
                return inner
                    .display_segments
                    .get(object_id)
                    .cloned()
                    .unwrap_or_default();
            }
        }
        self.rebuild_display_segments();
        self.inner
            .borrow()
            .display_segments
            .get(object_id)
            .cloned()
            .unwrap_or_default()
    }

    fn rebuild_display_segments(&self) {
        let mut inner = self.inner.borrow_mut();
        let pages: Vec<Rc<NativeHistoryPage>> = inner.pages.by_offset.values().cloned().collect();
        let mut display: HashMap<String, Vec<DisplaySegment>> = HashMap::new();
        let mut row_at: HashMap<u64, &NativeHistoryRow> = HashMap::new();
        let mut index_of: HashMap<&str, u64> = HashMap::new();
        for page in &pages {
            for (local, row) in page.rows.iter().enumerate() {
                let index = page.offset + local as u64;
                row_at.insert(index, row);
                index_of.insert(row.object_id.as_str(), index);
            }
        }
        for page in &pages {
            let page_start = page.offset;
            let page_end = page_start + page.rows.len() as u64;
            for segment in &page.segments {
                let from = segment.from_row;
                let to = segment
                    .to_row
                    .or_else(|| index_of.get(segment.to_object_id.as_str()).copied());
                let lit = segment.lit;
                // A side branch joins its parent only on the parent's row.
                let late_join = segment.kind == NativeHistorySegmentKind::Join
                    && segment.from_lane != segment.to_lane
                    && to.is_some_and(|to| to > from);
                if from >= page_start && from < page_end {
                    display
                        .entry(segment.from_object_id.clone())
                        .or_default()
                        .push(DisplaySegment {
                            from_lane: segment.from_lane,
                            to_lane: if late_join {
                                segment.from_lane
                            } else {
                                segment.to_lane
                            },
                            kind: segment.kind,
                            starts_at_top: false,
                            ends_at_center: false,
                            lit,
                        });
                }
                let Some(to) = to else { continue };
                if to <= from {
                    continue;
                }
                let first = (from + 1).max(page_start);
                let last = to.min(page_end.saturating_sub(1));
                let mut index = first;
                while index <= last {
                    if let Some(row) = row_at.get(&index) {
                        display
                            .entry(row.object_id.clone())
                            .or_default()
                            .push(DisplaySegment {
                                from_lane: if late_join {
                                    segment.from_lane
                                } else {
                                    segment.to_lane
                                },
                                to_lane: if late_join && index != to {
                                    segment.from_lane
                                } else {
                                    segment.to_lane
                                },
                                kind: segment.kind,
                                starts_at_top: true,
                                ends_at_center: index == to,
                                lit,
                            });
                    }
                    index += 1;
                }
            }
        }
        inner.display_segments = display;
        inner.display_generation = Some(inner.pages.generation);
    }

    // Lifecycle ------------------------------------------------------------------

    pub fn clear(&self) {
        {
            let mut inner = self.inner.borrow_mut();
            inner.operation += 1;
            inner.reloading_operation = None;
            inner.selection_operation += 1;
            inner.query_operation += 1;
            inner.identity = None;
            inner.retained_selected.clear();
            inner.pages.clear();
            inner.loading_pages.clear();
            Self::clear_search(&mut inner);
        }
        self.reset_inspection();
        self.publish(HistoryState::new(LoadPhase::Empty));
        self.finish_cache_presentation();
    }

    pub fn dispose(&self) {
        let mut inner = self.inner.borrow_mut();
        if inner.disposed {
            return;
        }
        inner.disposed = true;
        inner.operation += 1;
        inner.selection_operation += 1;
        inner.query_operation += 1;
        drop(inner);
        self.finish_cache_presentation();
    }

    fn presenting_cache(&self) -> bool {
        self.inner
            .borrow()
            .current
            .page
            .as_ref()
            .is_some_and(|page| page.request_id == CACHED_REQUEST_ID)
    }

    fn reloading(&self) -> bool {
        let inner = self.inner.borrow();
        inner.reloading_operation.is_some() && inner.reloading_operation == Some(inner.operation)
    }

    fn accepts(&self, identity: SessionIdentity, operation: u64) -> bool {
        let inner = self.inner.borrow();
        !inner.disposed && inner.identity == Some(identity) && inner.operation == operation
    }

    fn accepts_selection(&self, identity: SessionIdentity, operation: u64, selection: u64) -> bool {
        self.accepts(identity, operation) && self.inner.borrow().selection_operation == selection
    }

    fn accepts_query(&self, identity: SessionIdentity, operation: u64, query: u64) -> bool {
        self.accepts(identity, operation) && self.inner.borrow().query_operation == query
    }

    fn publish(&self, state: HistoryState) {
        self.inner.borrow_mut().current = state;
        self.revision.set(self.revision.get() + 1);
        self.notifier.notify(Topics::HISTORY);
    }

    fn republish(&self) {
        self.revision.set(self.revision.get() + 1);
        self.notifier.notify(Topics::HISTORY);
    }

    fn clear_search(inner: &mut Inner) {
        inner.search_query = None;
        inner.search_matches = Rc::new(Vec::new());
        inner.search_match_set = Rc::new(HashSet::new());
        inner.search_index = -1;
        inner.search_pending = false;
        inner.search_failure_code = None;
    }

    fn reset_inspection(&self) {
        let had = self.inner.borrow_mut().shown_selection.take().is_some();
        if had {
            self.emit_selection(&HistorySelection::default());
        }
    }

    fn emit_selection(&self, selection: &HistorySelection) {
        let listeners = self.selection_listeners.borrow();
        for listener in listeners.iter() {
            listener(selection);
        }
    }

    fn finish_cache_presentation(&self) {
        let sender = self.inner.borrow_mut().cache_replaced.take();
        if let Some(sender) = sender {
            let _ = sender.send(());
        }
    }

    // Loading --------------------------------------------------------------------

    /// Loads the history of `identity`; a history already shown is replaced in place.
    pub fn load(&self, identity: SessionIdentity, priority: Vec<String>) -> SharedUnit {
        let this = self.this();
        let token = {
            let mut inner = self.inner.borrow_mut();
            inner.next_token += 1;
            inner.next_token
        };
        let weak = Rc::downgrade(&this);
        let future = async move {
            this.load_once(identity, priority).await;
            if let Some(service) = weak.upgrade() {
                let mut inner = service.inner.borrow_mut();
                if inner
                    .pending_load
                    .as_ref()
                    .is_some_and(|(id, _)| *id == token)
                {
                    inner.pending_load = None;
                }
            }
        }
        .boxed_local()
        .shared();
        self.inner.borrow_mut().pending_load = Some((token, future.clone()));
        let driver = future.clone();
        rt::spawn_detached(driver);
        future
    }

    async fn load_once(self: Rc<Self>, identity: SessionIdentity, priority: Vec<String>) {
        if self.inner.borrow().disposed {
            return;
        }
        let shown = self.inner.borrow().current.page.clone();
        let (reloading, operation) = {
            let presenting_cache = self.presenting_cache();
            let mut inner = self.inner.borrow_mut();
            let reloading = inner.identity == Some(identity)
                && shown.is_some()
                && !presenting_cache
                && matches!(
                    inner.current.phase,
                    LoadPhase::Preview | LoadPhase::Complete
                );
            if inner.identity.map(|i| i.native_id) != Some(identity.native_id) {
                inner.retained_selected.clear();
            } else if inner.current.phase == LoadPhase::Complete
                && let Some(page) = &inner.current.page
            {
                inner.retained_selected = page.selected_object_ids.clone();
            }
            inner.identity = Some(identity);
            inner.selection_operation += 1;
            inner.query_operation += 1;
            if !reloading {
                inner.pages.clear();
                inner.loading_pages.clear();
                Self::clear_search(&mut inner);
            }
            inner.operation += 1;
            let operation = inner.operation;
            inner.reloading_operation = reloading.then_some(operation);
            (reloading, operation)
        };
        if !reloading {
            self.reset_inspection();
        }
        let (filter, other_refs, remembered) = {
            let hooks = self.hooks.borrow();
            let filter = hooks
                .branch_filter_for
                .as_ref()
                .map_or(BranchFilter::NONE, |hook| hook(identity));
            let other_refs = hooks.other_refs.as_ref().is_some_and(|hook| hook());
            let remembered = if reloading {
                None
            } else {
                hooks
                    .cached_first_page
                    .as_ref()
                    .and_then(|hook| hook(identity))
            };
            (filter, other_refs, remembered)
        };
        let cached = remembered
            .filter(|page| BranchFilter::of_page(page) == filter && page.other_refs == other_refs);
        let known = if reloading {
            shown.clone()
        } else {
            cached.clone()
        };
        self.finish_cache_presentation();
        if reloading {
            // The shown page stands in.
        } else if let Some(cached) = &cached {
            let (sender, receiver) = futures::channel::oneshot::channel::<()>();
            let wait = async move {
                let _ = receiver.await;
            }
            .boxed_local()
            .shared();
            {
                let mut inner = self.inner.borrow_mut();
                inner.cache_replaced = Some(sender);
                inner.cache_replaced_wait = Some(wait);
                inner.pages.set(Rc::clone(cached));
            }
            self.publish(HistoryState::with_page(
                LoadPhase::Preview,
                Rc::clone(cached),
            ));
        } else {
            self.publish(HistoryState::new(LoadPhase::Loading));
        }
        for attempt in 0..2 {
            let attempt_started = std::time::Instant::now();
            match self
                .load_attempt(
                    identity,
                    operation,
                    reloading,
                    &filter,
                    other_refs,
                    known.clone(),
                    &priority,
                )
                .await
            {
                Ok(()) => return,
                Err(error) => {
                    if !self.accepts(identity, operation) {
                        return;
                    }
                    crate::diagnostics::warning(
                        "History",
                        "history_load_failed",
                        &[
                            ("session_id", identity.native_id.into()),
                            ("attempt", (attempt as u64).into()),
                            ("failure", error.code().name().into()),
                            (
                                "elapsed_ms",
                                (attempt_started.elapsed().as_millis() as u64).into(),
                            ),
                        ],
                    );
                    if attempt == 0 && error.code() == FailureCode::StaleGeneration {
                        if !self.reloading() {
                            self.inner.borrow_mut().pages.clear();
                            self.publish(HistoryState::new(LoadPhase::Loading));
                        }
                        self.finish_cache_presentation();
                        continue;
                    }
                    self.inner.borrow_mut().pages.clear();
                    self.finish_reload(false);
                    let mut state = HistoryState::new(LoadPhase::Failed);
                    state.failure_code = Some(error.code().name());
                    self.publish(state);
                    self.finish_cache_presentation();
                    return;
                }
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    async fn load_attempt(
        self: &Rc<Self>,
        identity: SessionIdentity,
        operation: u64,
        reloading: bool,
        filter: &BranchFilter,
        other_refs: bool,
        known: Option<Rc<NativeHistoryPage>>,
        priority: &[String],
    ) -> SessionResult<()> {
        let preview_started = std::time::Instant::now();
        crate::diagnostics::debug(
            "History",
            "history_load_started",
            &[
                ("session_id", identity.native_id.into()),
                ("reloading", reloading.into()),
                ("branch_filter_count", filter.len().into()),
                ("other_refs", other_refs.into()),
            ],
        );
        // Native keeps the filter across loads, so every page arrives filtered.
        self.request_branch_filter(identity, filter.clone()).await;
        if !self.accepts(identity, operation) {
            return Ok(());
        }
        let result = self
            .calls
            .repository_session_history_load(
                identity.native_id,
                identity.generation,
                false,
                PAGE_ROWS as u32,
                other_refs,
            )
            .await
            .map_err(SessionError::from)?;
        let mut preview = page_of(result)?;
        crate::diagnostics::debug(
            "History",
            "history_preview_loaded",
            &[
                ("session_id", identity.native_id.into()),
                ("rows", preview.rows.len().into()),
                ("total_rows", preview.total_rows.into()),
                ("complete", preview.topology_complete.into()),
                (
                    "elapsed_ms",
                    (preview_started.elapsed().as_millis() as u64).into(),
                ),
            ],
        );
        if !self.accepts(identity, operation) {
            return Ok(());
        }
        // A filter can match nothing; its page keeps the toolbar that clears it.
        if preview.total_rows == 0 && preview.branch_filter.is_empty() {
            self.inner.borrow_mut().pages.clear();
            if reloading {
                self.finish_reload(false);
            }
            self.publish(HistoryState::new(LoadPhase::Empty));
            self.finish_cache_presentation();
            return Ok(());
        }
        if let Some(known) = &known {
            preview = with_known_metadata(preview, known);
        }
        let mut preview = Rc::new(preview);
        if !reloading {
            self.inner.borrow_mut().pages.replace(Rc::clone(&preview));
            self.publish(HistoryState::with_page(
                LoadPhase::Preview,
                Rc::clone(&preview),
            ));
            self.finish_cache_presentation();
        }
        preview = self.hydrate(identity, operation, preview, priority).await?;
        if !reloading && self.accepts(identity, operation) {
            self.inner.borrow_mut().pages.set(Rc::clone(&preview));
            self.publish(HistoryState::with_page(
                LoadPhase::Preview,
                Rc::clone(&preview),
            ));
        }
        let complete_started = std::time::Instant::now();
        let result = self
            .calls
            .repository_session_history_complete(
                identity.native_id,
                identity.generation,
                preview.request_id,
                PAGE_ROWS as u32,
            )
            .await
            .map_err(SessionError::from)?;
        let complete = page_of(result)?;
        crate::diagnostics::debug(
            "History",
            "history_complete_loaded",
            &[
                ("session_id", identity.native_id.into()),
                ("rows", complete.rows.len().into()),
                ("total_rows", complete.total_rows.into()),
                (
                    "elapsed_ms",
                    (complete_started.elapsed().as_millis() as u64).into(),
                ),
            ],
        );
        if !self.accepts(identity, operation) {
            return Ok(());
        }
        let mut complete = with_known_metadata(complete, &preview);
        let retained = self.inner.borrow().retained_selected.clone();
        if !retained.is_empty() && !same_selection(&complete.selected_object_ids, &retained) {
            complete = self
                .select_native(identity, complete.request_id, None, false, false, false, 0)
                .await?;
            if !self.accepts(identity, operation) {
                return Ok(());
            }
        }
        for selected in &retained {
            if complete.selected_object_ids.contains(selected) {
                continue;
            }
            // A selected commit can disappear when the repository changes.
            if let Ok(page) = self
                .select_native(
                    identity,
                    complete.request_id,
                    Some(selected.clone()),
                    true,
                    false,
                    false,
                    0,
                )
                .await
            {
                complete = page;
                if !self.accepts(identity, operation) {
                    return Ok(());
                }
            }
        }
        self.inner.borrow_mut().retained_selected = complete.selected_object_ids.clone();
        let complete = Rc::new(complete);
        let keep_inspection = reloading && self.shows_detail_of(&complete);
        if reloading {
            self.finish_reload(keep_inspection);
        }
        self.inner.borrow_mut().pages.replace(Rc::clone(&complete));
        self.publish(self.loaded_state(Rc::clone(&complete), keep_inspection));
        let complete = self
            .hydrate(identity, operation, complete, priority)
            .await?;
        if self.accepts(identity, operation) {
            self.inner.borrow_mut().pages.set(Rc::clone(&complete));
            self.publish(self.loaded_state(Rc::clone(&complete), keep_inspection));
            if is_cacheable_page(&complete) {
                let hooks = self.hooks.borrow();
                if let Some(hook) = &hooks.on_first_page {
                    hook(identity, &complete);
                }
            }
            self.restore_detail();
        }
        Ok(())
    }

    fn finish_reload(&self, keep_inspection: bool) {
        {
            let mut inner = self.inner.borrow_mut();
            inner.reloading_operation = None;
            inner.loading_pages.clear();
            Self::clear_search(&mut inner);
        }
        if !keep_inspection {
            self.reset_inspection();
        }
    }

    fn loaded_state(&self, page: Rc<NativeHistoryPage>, keep_inspection: bool) -> HistoryState {
        let target = if keep_inspection {
            self.inner.borrow().current.target_object_id.clone()
        } else {
            None
        };
        HistoryState {
            target_object_id: target,
            ..HistoryState::with_page(LoadPhase::Complete, page)
        }
    }

    fn detail_object_id(page: &NativeHistoryPage) -> Option<String> {
        page.comparison_new_object_id.clone().or_else(|| {
            (page.selected_object_ids.len() == 1).then(|| page.selected_object_ids[0].clone())
        })
    }

    fn shows_detail_of(&self, page: &NativeHistoryPage) -> bool {
        let inner = self.inner.borrow();
        inner
            .shown_selection
            .as_ref()
            .is_some_and(|(commit, base)| {
                Some(commit) == Self::detail_object_id(page).as_ref()
                    && base == &page.comparison_old_object_id
            })
    }

    /// Shows the selected commit in the inspector again when it shows something else.
    pub(crate) fn restore_detail(&self) {
        let Some(page) = self.inner.borrow().current.page.clone() else {
            return;
        };
        if self.shows_detail_of(&page) {
            return;
        }
        let Some(new_object_id) = Self::detail_object_id(&page) else {
            return;
        };
        let old = page.comparison_old_object_id.clone();
        self.announce(page, old, new_object_id, SelectionOrigin::Graph);
    }

    // Native calls ---------------------------------------------------------------

    #[allow(clippy::too_many_arguments)]
    async fn select_native(
        &self,
        identity: SessionIdentity,
        request_id: u64,
        object_id: Option<String>,
        toggle: bool,
        reveal: bool,
        focus: bool,
        offset: u64,
    ) -> SessionResult<NativeHistoryPage> {
        let result = self
            .calls
            .repository_session_history_select(
                identity.native_id,
                identity.generation,
                request_id,
                NativeHistorySelectionOptions {
                    object_id,
                    toggle,
                    reveal,
                    focus,
                    offset,
                    maximum_rows: PAGE_ROWS as u32,
                },
            )
            .await
            .map_err(SessionError::from)?;
        page_of(result)
    }

    async fn page_native(
        &self,
        identity: SessionIdentity,
        request_id: u64,
        offset: u64,
    ) -> SessionResult<NativeHistoryPage> {
        let result = self
            .calls
            .repository_session_history_page(
                identity.native_id,
                identity.generation,
                request_id,
                offset,
                PAGE_ROWS as u32,
            )
            .await
            .map_err(SessionError::from)?;
        page_of(result)
    }

    async fn query_native(
        &self,
        identity: SessionIdentity,
        request_id: u64,
        query: &HistoryQuery,
    ) -> SessionResult<NativeHistoryPage> {
        let result = self
            .calls
            .repository_session_history_query(
                identity.native_id,
                identity.generation,
                request_id,
                NativeHistoryQueryOptions {
                    text: query.text.clone(),
                    search_hash: query.search_hash,
                    search_message: query.search_message,
                    search_author: query.search_author,
                    search_path: query.search_path,
                    offset: 0,
                    maximum_rows: PAGE_ROWS as u32,
                },
            )
            .await
            .map_err(SessionError::from)?;
        page_of(result)
    }

    async fn hydrate(
        &self,
        identity: SessionIdentity,
        operation: u64,
        page: Rc<NativeHistoryPage>,
        priorities: &[String],
    ) -> SessionResult<Rc<NativeHistoryPage>> {
        // Commit metadata never changes for an object ID.
        let missing: Vec<String> = page
            .rows
            .iter()
            .filter(|row| !is_worktree(row) && !has_metadata(row))
            .map(|row| row.object_id.clone())
            .collect();
        if missing.is_empty() {
            return Ok(page);
        }
        let visible: HashSet<&String> = missing.iter().collect();
        let mut seen = HashSet::new();
        let unique: Vec<String> = priorities
            .iter()
            .filter(|id| visible.contains(id))
            .chain(missing.iter())
            .filter(|id| seen.insert((*id).clone()))
            .cloned()
            .collect();
        let mut metadata: HashMap<String, HistoryMetadata> = HashMap::new();
        for batch in unique.chunks(METADATA_BATCH) {
            if !self.accepts(identity, operation) {
                return Ok(page);
            }
            let result = self
                .calls
                .repository_session_history_metadata(
                    identity.native_id,
                    identity.generation,
                    page.request_id,
                    batch.to_vec(),
                )
                .await
                .map_err(SessionError::from)?;
            check(&result.failure)?;
            for row in result.rows {
                metadata.insert(
                    row.object_id.clone(),
                    HistoryMetadata {
                        object_id: row.object_id,
                        subject: row.subject,
                        author: row.author,
                        avatar_hash: row.avatar_hash,
                        author_time: row.author_time,
                        failure: row.failure,
                    },
                );
            }
        }
        let mut next = (*page).clone();
        for row in &mut next.rows {
            if let Some(value) = metadata.get(&row.object_id) {
                *row = with_metadata(row, value);
            }
        }
        Ok(Rc::new(next))
    }

    // Paging -----------------------------------------------------------------------

    /// Loads the page that holds row `index`, when it is not loaded.
    pub fn ensure_index(&self, index: u64) {
        let this = self.this();
        rt::spawn_detached(async move { this.ensure_index_once(index).await });
    }

    async fn ensure_index_once(self: Rc<Self>, index: u64) {
        let (identity, page, operation, view, offset) = {
            if self.presenting_cache() || self.reloading() {
                return;
            }
            let mut inner = self.inner.borrow_mut();
            let (Some(identity), Some(page)) = (inner.identity, inner.current.page.clone()) else {
                return;
            };
            if index >= page.total_rows {
                return;
            }
            let offset = (index / PAGE_ROWS) * PAGE_ROWS;
            if inner.pages.by_offset.contains_key(&offset) || !inner.loading_pages.insert(offset) {
                return;
            }
            (identity, page, inner.operation, inner.pages.view, offset)
        };
        let result = async {
            let loaded = self.page_native(identity, page.request_id, offset).await?;
            if !self.accepts(identity, operation) || self.inner.borrow().pages.view != view {
                return Ok(());
            }
            let loaded = self
                .hydrate(identity, operation, Rc::new(loaded), &[])
                .await?;
            if !self.accepts(identity, operation) || self.inner.borrow().pages.view != view {
                return Ok(());
            }
            self.inner.borrow_mut().pages.set(loaded);
            self.republish();
            Ok::<(), SessionError>(())
        }
        .await;
        // The retained first page remains usable on failure.
        let _ = result;
        self.inner.borrow_mut().loading_pages.remove(&offset);
    }

    // Selection --------------------------------------------------------------------

    /// Selects (or with `toggle`, adds/removes) `object_id`.
    pub fn select(
        &self,
        object_id: Option<String>,
        toggle: bool,
        reveal: bool,
        focus: bool,
        offset: u64,
        origin: SelectionOrigin,
    ) -> LocalBoxFuture<'static, ()> {
        let this = self.this();
        async move {
            this.select_once(object_id, toggle, reveal, focus, offset, origin)
                .await;
        }
        .boxed_local()
    }

    async fn select_once(
        self: Rc<Self>,
        object_id: Option<String>,
        toggle: bool,
        reveal: bool,
        focus: bool,
        offset: u64,
        origin: SelectionOrigin,
    ) {
        if self.inner.borrow().disposed {
            return;
        }
        let pending = self
            .inner
            .borrow()
            .pending_load
            .as_ref()
            .map(|(_, f)| f.clone());
        if let Some(pending) = pending {
            let intent = self.bump_selection();
            pending.await;
            if self.inner.borrow().disposed || intent != self.inner.borrow().selection_operation {
                return;
            }
        }
        if self.presenting_cache() {
            let replaced = self.inner.borrow().cache_replaced_wait.clone();
            let intent = self.bump_selection();
            let Some(replaced) = replaced else { return };
            replaced.await;
            if self.inner.borrow().disposed
                || intent != self.inner.borrow().selection_operation
                || self.presenting_cache()
            {
                return;
            }
        }
        let filtering = self
            .inner
            .borrow()
            .pending_filter
            .as_ref()
            .map(|(_, f)| f.clone());
        if let Some(filtering) = filtering {
            let intent = self.bump_selection();
            filtering.await;
            if self.inner.borrow().disposed || intent != self.inner.borrow().selection_operation {
                return;
            }
        }
        let (identity, current_page, operation, view) = {
            let inner = self.inner.borrow();
            let (Some(identity), Some(page)) = (inner.identity, inner.current.page.clone()) else {
                return;
            };
            (identity, page, inner.operation, inner.pages.view)
        };
        let selection_operation = self.bump_selection();
        let phase = self.inner.borrow().current.phase;
        self.publish(HistoryState {
            target_object_id: object_id.clone(),
            ..HistoryState::with_page(phase, Rc::clone(&current_page))
        });
        match self
            .select_native(
                identity,
                current_page.request_id,
                object_id.clone(),
                toggle,
                reveal,
                focus,
                offset,
            )
            .await
        {
            Ok(selection) => {
                if !self.accepts_selection(identity, operation, selection_operation) {
                    return;
                }
                let known = self
                    .inner
                    .borrow()
                    .pages
                    .get(selection.offset)
                    .unwrap_or_else(|| Rc::clone(&current_page));
                let selected = Rc::new(with_known_metadata(selection, &known));
                let first = {
                    let mut inner = self.inner.borrow_mut();
                    inner.retained_selected = selected.selected_object_ids.clone();
                    if inner.pages.view == view {
                        inner.pages.set(Rc::clone(&selected));
                        if selected.offset == 0 {
                            Rc::clone(&selected)
                        } else {
                            inner
                                .pages
                                .get(0)
                                .unwrap_or_else(|| Rc::clone(&current_page))
                        }
                    } else {
                        inner
                            .current
                            .page
                            .clone()
                            .unwrap_or_else(|| Rc::clone(&current_page))
                    }
                };
                match Self::detail_object_id(&selected) {
                    None => {
                        let phase = self.inner.borrow().current.phase;
                        self.publish(HistoryState::with_page(phase, first));
                        self.reset_inspection();
                    }
                    Some(new_object_id) => {
                        let old = selected.comparison_old_object_id.clone();
                        self.announce(first, old, new_object_id, origin);
                    }
                }
            }
            Err(error) => {
                if !self.accepts_selection(identity, operation, selection_operation) {
                    return;
                }
                let current = self.current();
                self.publish(HistoryState {
                    phase: current.phase,
                    page: current.page,
                    target_object_id: object_id.clone(),
                    target_not_shown: reveal
                        && object_id.is_some()
                        && error.code() == FailureCode::InvalidOptions,
                    ..HistoryState::new(current.phase)
                });
            }
        }
    }

    fn bump_selection(&self) -> u64 {
        let mut inner = self.inner.borrow_mut();
        inner.selection_operation += 1;
        inner.selection_operation
    }

    fn announce(
        &self,
        page: Rc<NativeHistoryPage>,
        old_object_id: Option<String>,
        new_object_id: String,
        origin: SelectionOrigin,
    ) {
        let phase = self.inner.borrow().current.phase;
        self.publish(HistoryState {
            target_object_id: Some(new_object_id.clone()),
            ..HistoryState::with_page(phase, page)
        });
        {
            let mut inner = self.inner.borrow_mut();
            if inner
                .shown_selection
                .as_ref()
                .is_some_and(|(commit, base)| *commit == new_object_id && *base == old_object_id)
            {
                return;
            }
            inner.shown_selection = Some((new_object_id.clone(), old_object_id.clone()));
        }
        let parents = self.row_by_id(&new_object_id).map(inspection_parents);
        self.emit_selection(&HistorySelection {
            commit: Some(new_object_id),
            base: old_object_id,
            parents,
            origin,
        });
    }

    // Search -------------------------------------------------------------------------

    pub fn apply_query(&self, query: HistoryQuery) -> LocalBoxFuture<'static, ()> {
        let this = self.this();
        async move { this.apply_query_once(query).await }.boxed_local()
    }

    async fn apply_query_once(self: Rc<Self>, query: HistoryQuery) {
        if self.reloading() {
            let pending = self
                .inner
                .borrow()
                .pending_load
                .as_ref()
                .map(|(_, f)| f.clone());
            if let Some(pending) = pending {
                pending.await;
            }
        }
        let (identity, current_page, operation, query_operation) = {
            let mut inner = self.inner.borrow_mut();
            let (Some(identity), Some(page)) = (inner.identity, inner.current.page.clone()) else {
                return;
            };
            inner.query_operation += 1;
            inner.search_query = query.active().then(|| query.clone());
            inner.search_matches = Rc::new(Vec::new());
            inner.search_match_set = Rc::new(HashSet::new());
            inner.search_index = -1;
            inner.search_pending = query.active();
            inner.search_failure_code = None;
            (identity, page, inner.operation, inner.query_operation)
        };
        let current = self.current();
        self.publish(HistoryState {
            target_object_id: current.target_object_id.clone(),
            pending_query: Some(query.clone()),
            ..HistoryState::with_page(current.phase, Rc::clone(&current_page))
        });
        let outcome: SessionResult<Option<Rc<NativeHistoryPage>>> = async {
            let mut matches_page = self
                .query_native(identity, current_page.request_id, &query)
                .await?;
            if !self.accepts_query(identity, operation, query_operation) {
                return Ok(None);
            }
            let mut matches: Vec<String> = Vec::new();
            if query.active() {
                matches.extend(
                    matches_page
                        .rows
                        .iter()
                        .filter(|row| !is_worktree(row))
                        .map(|row| row.object_id.clone()),
                );
                let mut offset = matches_page.rows.len() as u64;
                while offset < matches_page.total_rows {
                    matches_page = self
                        .page_native(identity, matches_page.request_id, offset)
                        .await?;
                    if !self.accepts_query(identity, operation, query_operation) {
                        return Ok(None);
                    }
                    matches.extend(
                        matches_page
                            .rows
                            .iter()
                            .filter(|row| !is_worktree(row))
                            .map(|row| row.object_id.clone()),
                    );
                    offset += PAGE_ROWS;
                }
            }
            let accepted = if query.active() {
                self.query_native(identity, matches_page.request_id, &HistoryQuery::default())
                    .await?
            } else {
                matches_page
            };
            if !self.accepts_query(identity, operation, query_operation) {
                return Ok(None);
            }
            let accepted = Rc::new(accepted);
            self.inner.borrow_mut().pages.replace(Rc::clone(&accepted));
            let accepted = self.hydrate(identity, operation, accepted, &[]).await?;
            if !self.accepts_query(identity, operation, query_operation) {
                return Ok(None);
            }
            {
                let mut inner = self.inner.borrow_mut();
                inner.pages.set(Rc::clone(&accepted));
                inner.search_index = if matches.is_empty() { -1 } else { 0 };
                inner.search_match_set = Rc::new(matches.iter().cloned().collect());
                inner.search_matches = Rc::new(matches);
                inner.search_pending = false;
            }
            Ok(Some(accepted))
        }
        .await;
        match outcome {
            Ok(Some(accepted)) => {
                let current = self.current();
                self.publish(HistoryState {
                    target_object_id: current.target_object_id,
                    ..HistoryState::with_page(current.phase, accepted)
                });
                let first = {
                    let inner = self.inner.borrow();
                    (inner.search_index >= 0).then(|| inner.search_matches[0].clone())
                };
                if let Some(first) = first {
                    rt::spawn_detached(self.select(
                        Some(first),
                        false,
                        true,
                        true,
                        0,
                        SelectionOrigin::Search,
                    ));
                }
            }
            Ok(None) => {}
            Err(error) => {
                if !self.accepts_query(identity, operation, query_operation) {
                    return;
                }
                {
                    let mut inner = self.inner.borrow_mut();
                    inner.search_pending = false;
                    inner.search_failure_code = Some(error.code().name());
                }
                let current = self.current();
                self.publish(HistoryState {
                    target_object_id: current.target_object_id,
                    query_failure_code: Some(error.code().name()),
                    ..HistoryState::with_page(current.phase, current_page)
                });
            }
        }
    }

    pub fn navigate_search(&self, backwards: bool) {
        let target = {
            let mut inner = self.inner.borrow_mut();
            let count = inner.search_matches.len() as i64;
            if count == 0 {
                return;
            }
            inner.search_index = if backwards {
                (inner.search_index - 1 + count) % count
            } else {
                (inner.search_index + 1) % count
            };
            inner.search_matches[inner.search_index as usize].clone()
        };
        self.republish();
        rt::spawn_detached(self.select(
            Some(target),
            false,
            true,
            true,
            0,
            SelectionOrigin::Search,
        ));
    }

    // Branch filter ------------------------------------------------------------------

    /// Shows only the commits reachable from `filter`'s branches.
    pub fn apply_branch_filter(&self, filter: BranchFilter) -> SharedUnit {
        let this = self.this();
        let token = {
            let mut inner = self.inner.borrow_mut();
            inner.next_token += 1;
            inner.next_token
        };
        let weak = Rc::downgrade(&this);
        let future = async move {
            let identity = this.inner.borrow().identity;
            if let Some(identity) = identity {
                let loading = this
                    .inner
                    .borrow()
                    .pending_load
                    .as_ref()
                    .map(|(_, f)| f.clone());
                let proceed = match loading {
                    Some(loading) => {
                        loading.await;
                        !this.inner.borrow().disposed
                            && this.inner.borrow().identity == Some(identity)
                    }
                    None => true,
                };
                if proceed {
                    this.request_branch_filter(identity, filter).await;
                }
            }
            if let Some(service) = weak.upgrade() {
                let mut inner = service.inner.borrow_mut();
                if inner
                    .pending_filter
                    .as_ref()
                    .is_some_and(|(id, _)| *id == token)
                {
                    inner.pending_filter = None;
                }
            }
        }
        .boxed_local()
        .shared();
        self.inner.borrow_mut().pending_filter = Some((token, future.clone()));
        rt::spawn_detached(future.clone());
        future
    }

    fn request_branch_filter(&self, identity: SessionIdentity, filter: BranchFilter) -> SharedUnit {
        let mut inner = self.inner.borrow_mut();
        inner.requested_filter = Some((identity, filter));
        if let Some(runner) = &inner.filter_runner {
            return runner.clone();
        }
        let this = self.this();
        let runner = async move {
            loop {
                let request = {
                    let mut inner = this.inner.borrow_mut();
                    if inner.disposed {
                        None
                    } else {
                        inner.requested_filter.take()
                    }
                };
                let Some((identity, filter)) = request else {
                    break;
                };
                this.send_branch_filter(identity, filter).await;
            }
            this.inner.borrow_mut().filter_runner = None;
        }
        .boxed_local()
        .shared();
        inner.filter_runner = Some(runner.clone());
        drop(inner);
        rt::spawn_detached(runner.clone());
        runner
    }

    async fn send_branch_filter(self: &Rc<Self>, identity: SessionIdentity, filter: BranchFilter) {
        let current_page = self.inner.borrow().current.page.clone();
        let showing = self.inner.borrow().identity == Some(identity)
            && current_page.is_some()
            && !self.presenting_cache()
            && !self.reloading();
        if showing
            && current_page
                .as_ref()
                .is_some_and(|page| BranchFilter::of_page(page) == filter)
        {
            return;
        }
        let (operation, query_operation) = {
            let mut inner = self.inner.borrow_mut();
            if showing {
                inner.query_operation += 1;
            }
            (inner.operation, inner.query_operation)
        };
        let request_id = if showing {
            current_page.as_ref().map_or(0, |page| page.request_id)
        } else {
            0
        };
        let result = self
            .calls
            .repository_session_history_branch_filter(
                identity.native_id,
                identity.generation,
                request_id,
                filter
                    .references()
                    .iter()
                    .map(|reference| reference.as_bytes().to_vec())
                    .collect(),
                0,
                PAGE_ROWS as u32,
            )
            .await
            .map_err(SessionError::from)
            .and_then(|result| {
                check(&result.failure)?;
                Ok(result.page)
            });
        match result {
            Ok(Some(page)) => {
                let stale = self.inner.borrow().requested_filter.is_some()
                    || !self.accepts_query(identity, operation, query_operation)
                    || self
                        .inner
                        .borrow()
                        .current
                        .page
                        .as_ref()
                        .map(|current| current.request_id)
                        != Some(page.request_id);
                if stale {
                    return;
                }
                let page = Rc::new(page);
                let view = {
                    let mut inner = self.inner.borrow_mut();
                    Self::clear_search(&mut inner);
                    inner.branch_filter_sequence += 1;
                    inner.pages.replace(Rc::clone(&page));
                    inner.pages.view
                };
                let current = self.current();
                self.publish(HistoryState {
                    target_object_id: current.target_object_id.clone(),
                    ..HistoryState::with_page(current.phase, Rc::clone(&page))
                });
                let Ok(page) = self.hydrate(identity, operation, page, &[]).await else {
                    return;
                };
                if !self.accepts_query(identity, operation, query_operation)
                    || self.inner.borrow().pages.view != view
                {
                    return;
                }
                self.inner.borrow_mut().pages.set(Rc::clone(&page));
                let current = self.current();
                self.publish(HistoryState {
                    target_object_id: current.target_object_id,
                    ..HistoryState::with_page(current.phase, Rc::clone(&page))
                });
                if is_cacheable_page(&page) {
                    let hooks = self.hooks.borrow();
                    if let Some(hook) = &hooks.on_first_page {
                        hook(identity, &page);
                    }
                }
            }
            Ok(None) => {}
            Err(error) => {
                if !showing || !self.accepts_query(identity, operation, query_operation) {
                    return;
                }
                let current = self.current();
                self.publish(HistoryState {
                    query_failure_code: Some(error.code().name()),
                    ..current
                });
            }
        }
    }

    // Collapse -----------------------------------------------------------------------

    pub fn toggle_collapse(&self, object_id: String, offset: u64) {
        let this = self.this();
        rt::spawn_detached(async move {
            if this.reloading() {
                let pending = this
                    .inner
                    .borrow()
                    .pending_load
                    .as_ref()
                    .map(|(_, f)| f.clone());
                if let Some(pending) = pending {
                    pending.await;
                }
            }
            let (identity, current_page, operation, query_operation) = {
                let mut inner = this.inner.borrow_mut();
                let (Some(identity), Some(page)) = (inner.identity, inner.current.page.clone())
                else {
                    return;
                };
                inner.query_operation += 1;
                (identity, page, inner.operation, inner.query_operation)
            };
            let result = async {
                let result = this
                    .calls
                    .repository_session_history_collapse(
                        identity.native_id,
                        identity.generation,
                        current_page.request_id,
                        object_id,
                        offset,
                        PAGE_ROWS as u32,
                    )
                    .await
                    .map_err(SessionError::from)?;
                let page = Rc::new(page_of(result)?);
                if !this.accepts_query(identity, operation, query_operation) {
                    return Ok(None);
                }
                this.inner.borrow_mut().pages.replace(Rc::clone(&page));
                let page = this.hydrate(identity, operation, page, &[]).await?;
                Ok::<_, SessionError>(Some(page))
            }
            .await;
            match result {
                Ok(Some(page)) => {
                    if !this.accepts_query(identity, operation, query_operation) {
                        return;
                    }
                    this.inner.borrow_mut().pages.set(Rc::clone(&page));
                    let current = this.current();
                    this.publish(HistoryState {
                        target_object_id: current.target_object_id,
                        ..HistoryState::with_page(current.phase, page)
                    });
                }
                Ok(None) => {}
                Err(error) => {
                    if !this.accepts_query(identity, operation, query_operation) {
                        return;
                    }
                    let current = this.current();
                    this.publish(HistoryState {
                        target_object_id: current.target_object_id,
                        query_failure_code: Some(error.code().name()),
                        ..HistoryState::with_page(current.phase, current_page)
                    });
                }
            }
        });
    }
}

fn same_selection(left: &[String], right: &[String]) -> bool {
    left.len() == right.len() && right.iter().all(|id| left.contains(id))
}

/// A fresh topology arrives without subjects and authors; rows `known`
/// described keep them, so the list does not blank while metadata reloads.
fn with_known_metadata(
    mut page: NativeHistoryPage,
    known: &NativeHistoryPage,
) -> NativeHistoryPage {
    let described: HashMap<&str, &NativeHistoryRow> = known
        .rows
        .iter()
        .filter(|row| has_metadata(row))
        .map(|row| (row.object_id.as_str(), row))
        .collect();
    if described.is_empty() {
        return page;
    }
    for row in &mut page.rows {
        if has_metadata(row) {
            continue;
        }
        if let Some(value) = described.get(row.object_id.as_str()) {
            row.subject = value.subject.clone();
            row.author = value.author.clone();
            row.avatar_hash = value.avatar_hash.clone();
            row.author_time = value.author_time;
            row.metadata_failure = value.metadata_failure;
        }
    }
    page
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(shape: gitlama_contract::dto::NativeHistoryNodeShape) -> NativeHistoryRow {
        NativeHistoryRow {
            object_id: "a".repeat(40),
            parents: vec!["b".repeat(40)],
            parent_count: 1,
            parents_truncated: false,
            refs: vec![],
            ref_count: 0,
            refs_truncated: false,
            lane: 0,
            shape,
            metadata_available: false,
            subject: vec![],
            author: vec![],
            avatar_hash: String::new(),
            author_time: 0,
            metadata_failure: None,
            selected: false,
            current: false,
            lit: false,
            compared: false,
            wip_changed_files: 0,
            wip_staged_files: 0,
        }
    }

    #[test]
    fn a_shallow_boundary_is_inspected_against_the_empty_tree() {
        use gitlama_contract::dto::NativeHistoryNodeShape;
        // The boundary row draws the parent the shallow clone does not have.
        assert!(inspection_parents(row(NativeHistoryNodeShape::Boundary)).is_empty());
        assert_eq!(
            inspection_parents(row(NativeHistoryNodeShape::Commit)),
            vec!["b".repeat(40)]
        );
    }

    #[test]
    fn branch_filter_toggles_with_upstream() {
        let filter =
            BranchFilter::NONE.toggled("refs/heads/main", Some("refs/remotes/origin/main"));
        assert_eq!(filter.len(), 2);
        assert!(filter.is_focused_on("refs/heads/main", Some("refs/remotes/origin/main")));
        let filter = filter.toggled("refs/heads/main", None);
        assert_eq!(filter.references(), ["refs/remotes/origin/main".to_owned()]);
    }
}
