//! One accepted diff projection (the committed diff of an inspector, or a
//! working diff of Changes): its pages, loaded as rows are shown, and the
//! syntax categories of its rows, requested once the rows have been on
//! screen for a moment.

use crate::backend::SessionCalls;
use crate::notify::{Notifier, Topics};
use crate::rt;
use crate::session::SessionIdentity;
use gitlama_contract::diff::{NativeDiffLayout, NativeDiffPage, NativeDiffRow, NativeDiffSyntaxOrigin, NativeDiffSyntaxRequest, NativeDiffSyntaxRow};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::rc::Rc;

/// Rows per diff page (ContractLimits.pageRows).
pub const DIFF_PAGE_ROWS: u64 = 512;
/// Rows per syntax read (ContractLimits.syntaxPageRows).
pub const SYNTAX_PAGE_ROWS: u64 = 32;

static NEXT_SYNTAX_REQUEST: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

pub struct DiffDocument {
    calls: Rc<dyn SessionCalls>,
    notifier: Notifier,
    topic: Topics,
    identity: SessionIdentity,
    origin: NativeDiffSyntaxOrigin,
    request_id: u64,
    total: u64,
    layout: NativeDiffLayout,
    pages: RefCell<BTreeMap<u64, Rc<NativeDiffPage>>>,
    loading: RefCell<HashSet<u64>>,
    syntax: RefCell<HashMap<String, Rc<NativeDiffSyntaxRow>>>,
    syntax_requested: RefCell<HashSet<u64>>,
    retired: Cell<bool>,
    /// Bumps whenever rows or colours arrive.
    revision: Cell<u64>,
}

impl DiffDocument {
    pub fn new(
        calls: Rc<dyn SessionCalls>,
        notifier: Notifier,
        topic: Topics,
        identity: SessionIdentity,
        origin: NativeDiffSyntaxOrigin,
        first: NativeDiffPage,
    ) -> Rc<Self> {
        let mut pages = BTreeMap::new();
        let request_id = first.request_id;
        let total = first.total_rows;
        let layout = first.layout;
        pages.insert(first.offset, Rc::new(first));
        Rc::new(Self {
            calls,
            notifier,
            topic,
            identity,
            origin,
            request_id,
            total,
            layout,
            pages: RefCell::new(pages),
            loading: RefCell::new(HashSet::new()),
            syntax: RefCell::new(HashMap::new()),
            syntax_requested: RefCell::new(HashSet::new()),
            retired: Cell::new(false),
            revision: Cell::new(0),
        })
    }

    pub fn request_id(&self) -> u64 {
        self.request_id
    }

    pub fn total(&self) -> u64 {
        self.total
    }

    pub fn layout(&self) -> NativeDiffLayout {
        self.layout
    }

    pub fn identity(&self) -> SessionIdentity {
        self.identity
    }

    pub fn revision(&self) -> u64 {
        self.revision.get()
    }

    /// Stops loading: rows that arrive later are dropped.
    pub fn retire(&self) {
        self.retired.set(true);
    }

    /// Row `index`, when its page is loaded.
    pub fn row(&self, index: u64) -> Option<NativeDiffRow> {
        self.with_row(index, Clone::clone)
    }

    pub fn with_row<R>(&self, index: u64, read: impl FnOnce(&NativeDiffRow) -> R) -> Option<R> {
        let pages = self.pages.borrow();
        let page = pages.get(&((index / DIFF_PAGE_ROWS) * DIFF_PAGE_ROWS))?;
        let local = index.checked_sub(page.offset)? as usize;
        page.rows.get(local).map(read)
    }

    /// Every loaded row with its index.
    /// The added and deleted lines once every row has loaded (the Dart
    /// inspector sidebar's +/− counts); None while rows are missing.
    pub fn complete_counts(&self) -> Option<(u64, u64)> {
        use gitlama_contract::diff::NativeDiffRowKind;
        let (mut loaded, mut added, mut deleted) = (0u64, 0u64, 0u64);
        self.for_each_loaded(|_, row| {
            loaded += 1;
            match row.kind {
                NativeDiffRowKind::Addition => added += 1,
                NativeDiffRowKind::Deletion => deleted += 1,
                _ => {}
            }
        });
        (loaded == self.total).then_some((added, deleted))
    }

    pub fn for_each_loaded(&self, mut visit: impl FnMut(u64, &NativeDiffRow)) {
        for page in self.pages.borrow().values() {
            for (local, row) in page.rows.iter().enumerate() {
                visit(page.offset + local as u64, row);
            }
        }
    }

    /// The rows that contain `query` (at most 1000, as in Flutter), or None
    /// when the search failed or the diff moved on.
    pub async fn search(&self, query: &str, case_sensitive: bool) -> Option<Vec<u32>> {
        let result = self
            .calls
            .repository_session_diff_search(
                self.identity.native_id,
                self.identity.generation,
                self.request_id,
                query.as_bytes().to_vec(),
                case_sensitive,
                1000,
            )
            .await
            .ok()?;
        (result.failure.is_none() && result.request_id == self.request_id && !self.retired.get()).then_some(result.matches)
    }

    /// The rows of every hunk header, loaded or not.
    pub async fn hunks(&self) -> Vec<u32> {
        match self
            .calls
            .repository_session_diff_hunks(self.identity.native_id, self.identity.generation, self.request_id, 10_000)
            .await
        {
            Ok(result) if result.failure.is_none() && result.request_id == self.request_id => result.positions,
            _ => Vec::new(),
        }
    }

    /// Loads the page of row `index` unless it is loaded or loading.
    pub fn ensure(self: &Rc<Self>, index: u64) {
        if index >= self.total || self.retired.get() {
            return;
        }
        let offset = (index / DIFF_PAGE_ROWS) * DIFF_PAGE_ROWS;
        if self.pages.borrow().contains_key(&offset) || !self.loading.borrow_mut().insert(offset) {
            return;
        }
        let this = Rc::clone(self);
        let identity = self.identity;
        let request = match self.origin {
            NativeDiffSyntaxOrigin::Committed => self.calls.repository_session_diff_page(
                identity.native_id,
                identity.generation,
                self.request_id,
                offset,
                DIFF_PAGE_ROWS as u32,
            ),
            NativeDiffSyntaxOrigin::Working => self.calls.repository_session_working_diff_page(
                identity.native_id,
                identity.generation,
                self.request_id,
                offset,
                DIFF_PAGE_ROWS as u32,
            ),
        };
        rt::spawn_detached(async move {
            let result = request.await;
            this.loading.borrow_mut().remove(&offset);
            if this.retired.get() {
                return;
            }
            if let Ok(result) = result
                && let Some(page) = result.page
                && result.failure.is_none()
                && page.request_id == this.request_id
            {
                this.pages.borrow_mut().insert(page.offset, Rc::new(page));
                this.changed();
            }
        });
    }

    /// Loads the pages at `offsets` and waits for them (an in-place reload
    /// fetches what the old diff showed before it is swapped in).
    pub async fn preload(self: &Rc<Self>, offsets: Vec<u64>) {
        for offset in offsets {
            if self.pages.borrow().contains_key(&offset) {
                continue;
            }
            let identity = self.identity;
            let request = match self.origin {
                NativeDiffSyntaxOrigin::Committed => self.calls.repository_session_diff_page(
                    identity.native_id,
                    identity.generation,
                    self.request_id,
                    offset,
                    DIFF_PAGE_ROWS as u32,
                ),
                NativeDiffSyntaxOrigin::Working => self.calls.repository_session_working_diff_page(
                    identity.native_id,
                    identity.generation,
                    self.request_id,
                    offset,
                    DIFF_PAGE_ROWS as u32,
                ),
            };
            if let Ok(result) = request.await
                && let Some(page) = result.page
                && result.failure.is_none()
                && page.request_id == self.request_id
            {
                self.pages.borrow_mut().insert(page.offset, Rc::new(page));
            }
        }
    }

    fn changed(&self) {
        self.revision.set(self.revision.get() + 1);
        self.notifier.notify(self.topic);
    }

    /// The categories of row `stable_id`, once read.
    pub fn syntax(&self, stable_id: &str) -> Option<Rc<NativeDiffSyntaxRow>> {
        self.syntax.borrow().get(stable_id).cloned()
    }

    /// Reads the categories of rows `first..=last` (the rows on screen).
    pub fn demand_syntax(self: &Rc<Self>, first: u64, last: u64) {
        if self.retired.get() || self.total == 0 {
            return;
        }
        let last = last.min(self.total - 1);
        let mut offset = (first / SYNTAX_PAGE_ROWS) * SYNTAX_PAGE_ROWS;
        while offset <= last {
            let loaded = self.pages.borrow().contains_key(&((offset / DIFF_PAGE_ROWS) * DIFF_PAGE_ROWS));
            if loaded && self.syntax_requested.borrow_mut().insert(offset) {
                self.request_syntax(offset);
            }
            offset += SYNTAX_PAGE_ROWS;
        }
    }

    fn request_syntax(self: &Rc<Self>, offset: u64) {
        let identity = self.identity;
        let request = NativeDiffSyntaxRequest {
            origin: self.origin,
            diff_request_id: self.request_id,
            syntax_request_id: NEXT_SYNTAX_REQUEST.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            offset,
            maximum_rows: SYNTAX_PAGE_ROWS as u32,
        };
        let call = self.calls.repository_session_diff_syntax_page(identity.native_id, identity.generation, request);
        let this = Rc::clone(self);
        rt::spawn_detached(async move {
            let result = call.await;
            if this.retired.get() {
                return;
            }
            match result {
                Ok(result) if result.failure.is_none() => {
                    let Some(page) = result.page else { return };
                    {
                        let mut syntax = this.syntax.borrow_mut();
                        for row in page.rows {
                            syntax.insert(row.stable_id.clone(), Rc::new(row));
                        }
                    }
                    // A reply bound ended the page early: continue there.
                    if let Some(next) = page.next_offset
                        && next < offset + SYNTAX_PAGE_ROWS
                    {
                        this.syntax_requested.borrow_mut().remove(&offset);
                    }
                    this.changed();
                }
                // Transient failures may succeed on a later demand.
                _ => {
                    this.syntax_requested.borrow_mut().remove(&offset);
                }
            }
        });
    }
}
