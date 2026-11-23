//! What each repository showed when it was last open, presented while it
//! loads again.

use futures::future::{FutureExt, LocalBoxFuture};
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{NativeHistoryPage, NativeRepositorySnapshot};
use std::rc::Rc;

pub trait SessionViewCache {
    /// Reads the stored entries of `repositories` ahead of their tabs.
    fn warm(&self, repositories: Vec<NativePathIdentity>) -> LocalBoxFuture<'static, ()>;
    /// The first history page `repository` showed last time.
    fn history(&self, repository: &NativePathIdentity) -> Option<Rc<NativeHistoryPage>>;
    /// `snapshot` with what the repository showed last time in the places it
    /// has not loaded yet. A loaded or failed snapshot is never changed.
    fn present(&self, snapshot: &NativeRepositorySnapshot) -> NativeRepositorySnapshot;
    /// Keeps the references and status of `snapshot`.
    fn remember(&self, snapshot: &NativeRepositorySnapshot);
    /// Keeps the first history `page` of `repository`.
    fn remember_history(&self, repository: &NativePathIdentity, page: &NativeHistoryPage);
}

/// Keeps nothing: every repository loads as usual.
pub struct NoViewCache;

impl SessionViewCache for NoViewCache {
    fn warm(&self, _: Vec<NativePathIdentity>) -> LocalBoxFuture<'static, ()> {
        async {}.boxed_local()
    }
    fn history(&self, _: &NativePathIdentity) -> Option<Rc<NativeHistoryPage>> {
        None
    }
    fn present(&self, snapshot: &NativeRepositorySnapshot) -> NativeRepositorySnapshot {
        snapshot.clone()
    }
    fn remember(&self, _: &NativeRepositorySnapshot) {}
    fn remember_history(&self, _: &NativePathIdentity, _: &NativeHistoryPage) {}
}

// Stored view cache ---------------------------------------------------------------

use crate::entry_store::EntryStore;
use crate::rt::{self, TimerHandle};
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Map, ParseLimits, Value};
use gitlama_contract::dto::{
    NativeHistoryRow, NativeRepositoryPhase, NativeRepositoryRefCounts, NativeRepositoryRefs,
    NativeRepositoryStatus,
};
use std::cell::RefCell;
use std::rc::Weak;
use std::time::Duration;

/// The schema of a stored entry. An entry of another schema (such as one an earlier release
/// wrote) is removed and the repository loads as usual.
const SCHEMA: &str = "gitlama.view-cache.v2";
/// Entries kept in memory, matching the bound of the private storage.
const CAPACITY: usize = gitlama_application::view_cache::VIEW_CACHE_ENTRY_LIMIT;
/// How long changes settle before an entry is written.
const PERSIST_DELAY: Duration = Duration::from_secs(2);

/// What a repository showed when it was last open: enough to present it again at once while
/// the repository itself loads. Never the source of truth.
#[derive(Clone, Default, PartialEq)]
struct Entry {
    refs: Option<NativeRepositoryRefs>,
    ref_counts: Option<NativeRepositoryRefCounts>,
    status: Option<NativeRepositoryStatus>,
    /// The first history page last shown, without selection. It names the branch filter it
    /// was shown under and stands in only for that one.
    history: Option<Rc<NativeHistoryPage>>,
}

impl Entry {
    fn is_empty(&self) -> bool {
        self.refs.is_none() && self.status.is_none() && self.history.is_none()
    }
}

fn optional<T>(value: Option<&T>, encode: impl Fn(&T) -> Value) -> Value {
    value.map_or(Value::Null, encode)
}

/// An entry as the codec reads and writes it, away from the interface thread.
#[derive(Debug, PartialEq)]
struct Stored {
    refs: Option<NativeRepositoryRefs>,
    ref_counts: Option<NativeRepositoryRefCounts>,
    status: Option<NativeRepositoryStatus>,
    history: Option<NativeHistoryPage>,
}

impl Stored {
    fn of(entry: &Entry) -> Self {
        Self {
            refs: entry.refs.clone(),
            ref_counts: entry.ref_counts.clone(),
            status: entry.status.clone(),
            history: entry.history.as_deref().cloned(),
        }
    }

    fn into_entry(self) -> Entry {
        Entry {
            refs: self.refs,
            ref_counts: self.ref_counts,
            status: self.status,
            history: self.history.map(Rc::new),
        }
    }
}

fn encode(entry: &Stored) -> Vec<u8> {
    let mut map = Map::new();
    map.insert("schema".to_owned(), Value::String(SCHEMA.to_owned()));
    map.insert(
        "refs".to_owned(),
        optional(entry.refs.as_ref(), g::enc_native_repository_refs),
    );
    map.insert(
        "refCounts".to_owned(),
        optional(
            entry.ref_counts.as_ref(),
            g::enc_native_repository_ref_counts,
        ),
    );
    map.insert(
        "status".to_owned(),
        optional(entry.status.as_ref(), g::enc_native_repository_status),
    );
    map.insert(
        "history".to_owned(),
        optional(entry.history.as_ref(), g::enc_native_history_page),
    );
    w::to_bytes(&Value::Object(map))
}

fn decode(bytes: &[u8]) -> Option<Stored> {
    let value = w::parse(bytes, ParseLimits::TRANSACTION).ok()?;
    let object = w::object(
        &value,
        "viewCache",
        &["schema", "refs", "refCounts", "status", "history"],
    )
    .ok()?;
    if object.field("schema").as_str() != Some(SCHEMA) {
        return None;
    }
    let entry = Stored {
        refs: w::opt_d(object.field("refs"), g::dec_native_repository_refs).ok()?,
        ref_counts: w::opt_d(
            object.field("refCounts"),
            g::dec_native_repository_ref_counts,
        )
        .ok()?,
        status: w::opt_d(object.field("status"), g::dec_native_repository_status).ok()?,
        history: w::opt_d(object.field("history"), g::dec_native_history_page).ok()?,
    };
    let empty = entry.refs.is_none() && entry.status.is_none() && entry.history.is_none();
    (!empty).then_some(entry)
}

/// The request identity of a history page presented from the cache. Native request
/// identities start at one, so no native read accepts this one.
pub const CACHED_HISTORY_REQUEST_ID: u64 = 0;

/// Whether `page` may stand in later for the first page of the history under the same filter.
fn is_cacheable(page: &NativeHistoryPage) -> bool {
    page.topology_complete
        && page.offset == 0
        && !page.query_active
        && page.accepted_query.is_empty()
        && page.collapsed_commits == 0
        && !page.rows.is_empty()
}

/// `page` as the cache keeps it: no selection, lighting or reveal, which belong to the session
/// that produced them.
fn cacheable(page: &NativeHistoryPage) -> NativeHistoryPage {
    NativeHistoryPage {
        request_id: CACHED_HISTORY_REQUEST_ID,
        topology_complete: false,
        total_rows: page.total_rows,
        offset: 0,
        rows: page
            .rows
            .iter()
            .map(|row| NativeHistoryRow {
                selected: false,
                lit: false,
                compared: false,
                ..row.clone()
            })
            .collect(),
        segments: page.segments.clone(),
        lane_count: page.lane_count,
        payload_bytes: 0,
        lighting_active: false,
        current_object_id: page.current_object_id.clone(),
        selected_object_ids: Vec::new(),
        focused_object_id: None,
        comparison_old_object_id: None,
        comparison_new_object_id: None,
        reveal_sequence: 0,
        reveal_object_id: None,
        reveal_index: None,
        query_sequence: 0,
        query_active: false,
        accepted_query: String::new(),
        branch_filter: page.branch_filter.clone(),
        selected_filtered_out: false,
        collapsed_commits: 0,
        other_refs: page.other_refs,
    }
}

#[derive(Default)]
struct Inner {
    /// Least recently used first.
    entries: Vec<(NativePathIdentity, Rc<Entry>)>,
    pending: Vec<(NativePathIdentity, TimerHandle)>,
    disposed: bool,
}

/// Remembers what each local repository showed, so that opening it again presents that at
/// once while it loads. Entries live in memory for tab changes and in private storage for the
/// next start; storage is best effort in both directions.
pub struct StoredViewCache {
    store: Rc<EntryStore>,
    inner: RefCell<Inner>,
    this: Weak<StoredViewCache>,
}

impl StoredViewCache {
    #[must_use]
    pub fn new() -> Rc<Self> {
        Rc::new_cyclic(|this| Self {
            store: EntryStore::new("views"),
            inner: RefCell::new(Inner::default()),
            this: this.clone(),
        })
    }

    fn entry(&self, repository: &NativePathIdentity) -> Option<Rc<Entry>> {
        if repository.remote.is_some() {
            return None;
        }
        let inner = self.inner.borrow();
        inner
            .entries
            .iter()
            .find(|(key, _)| key == repository)
            .map(|(_, entry)| Rc::clone(entry))
    }

    fn trim(inner: &mut Inner) {
        while inner.entries.len() > CAPACITY {
            inner.entries.remove(0);
        }
    }

    fn store(&self, repository: &NativePathIdentity, entry: Entry) {
        let mut inner = self.inner.borrow_mut();
        // Reinsert so that the list keeps its most recently used entries last.
        inner.entries.retain(|(key, _)| key != repository);
        inner.entries.push((repository.clone(), Rc::new(entry)));
        Self::trim(&mut inner);
        inner.pending.retain(|(key, _)| key != repository);
        let this = self.this.clone();
        let key = repository.clone();
        let timer = TimerHandle::start(PERSIST_DELAY, move || {
            if let Some(this) = this.upgrade() {
                this.inner
                    .borrow_mut()
                    .pending
                    .retain(|(pending, _)| pending != &key);
                rt::spawn_detached(async move { this.write(&key).await });
            }
        });
        inner.pending.push((repository.clone(), timer));
    }

    async fn write(&self, repository: &NativePathIdentity) {
        let Some(entry) = self.entry(repository) else {
            return;
        };
        if entry.is_empty() {
            return;
        }
        let stored = Stored::of(&entry);
        let bytes = rt::blocking(move || encode(&stored)).await;
        self.store.write(repository, bytes).await;
    }

    /// Writes every changed entry now.
    pub async fn flush(&self) {
        let repositories: Vec<NativePathIdentity> = {
            let mut inner = self.inner.borrow_mut();
            inner
                .pending
                .drain(..)
                .map(|(key, mut timer)| {
                    timer.cancel();
                    key
                })
                .collect()
        };
        for repository in repositories {
            self.write(&repository).await;
        }
    }

    pub async fn dispose(&self) {
        if self.inner.borrow().disposed {
            return;
        }
        self.flush().await;
        let mut inner = self.inner.borrow_mut();
        inner.disposed = true;
        inner.entries.clear();
    }

    async fn read(self: Rc<Self>, repository: NativePathIdentity) {
        let Some(bytes) = self.store.read(&repository).await else {
            return;
        };
        let decoded = rt::blocking(move || decode(&bytes)).await;
        let Some(decoded) = decoded else {
            // Another schema or a damaged file; loading rebuilds the entry.
            self.store.remove(&repository).await;
            return;
        };
        let mut inner = self.inner.borrow_mut();
        if inner.disposed {
            return;
        }
        // What this session has learned meanwhile is newer than the storage.
        if inner.entries.iter().all(|(key, _)| key != &repository) {
            inner
                .entries
                .insert(0, (repository, Rc::new(decoded.into_entry())));
            Self::trim(&mut inner);
        }
    }
}

impl SessionViewCache for StoredViewCache {
    fn warm(&self, repositories: Vec<NativePathIdentity>) -> LocalBoxFuture<'static, ()> {
        let Some(this) = self.this.upgrade() else {
            return async {}.boxed_local();
        };
        let mut unique: Vec<NativePathIdentity> = Vec::new();
        for repository in repositories {
            if repository.remote.is_none()
                && !unique.contains(&repository)
                && self.entry(&repository).is_none()
            {
                unique.push(repository);
            }
        }
        async move {
            futures::future::join_all(
                unique
                    .into_iter()
                    .map(|repository| Rc::clone(&this).read(repository)),
            )
            .await;
        }
        .boxed_local()
    }

    fn history(&self, repository: &NativePathIdentity) -> Option<Rc<NativeHistoryPage>> {
        self.entry(repository)?.history.clone()
    }

    fn present(&self, snapshot: &NativeRepositorySnapshot) -> NativeRepositorySnapshot {
        let Some(repository) = snapshot
            .identity
            .as_ref()
            .map(|identity| &identity.worktree_root)
        else {
            return snapshot.clone();
        };
        let Some(known) = self.entry(repository) else {
            return snapshot.clone();
        };
        if snapshot.failure.is_some()
            || !matches!(
                snapshot.phase,
                NativeRepositoryPhase::Loading | NativeRepositoryPhase::Unloaded
            )
        {
            return snapshot.clone();
        }
        let counts = &snapshot.ref_counts;
        let refs = &snapshot.refs;
        let refs_loaded = snapshot.refs_failure.is_some()
            || counts.branches + counts.remotes + counts.tags + counts.stashes > 0
            || !refs.branches.is_empty()
            || !refs.remotes.is_empty()
            || !refs.tags.is_empty()
            || !refs.stashes.is_empty();
        let status_loaded = snapshot.status.is_some() || snapshot.status_failure.is_some();
        if (refs_loaded || known.refs.is_none()) && (status_loaded || known.status.is_none()) {
            return snapshot.clone();
        }
        let mut presented = snapshot.clone();
        if !status_loaded {
            presented.status.clone_from(&known.status);
        }
        if !refs_loaded {
            if let Some(known_counts) = &known.ref_counts {
                presented.ref_counts = known_counts.clone();
            }
            if let Some(known_refs) = &known.refs {
                presented.refs = known_refs.clone();
            }
        }
        presented
    }

    fn remember(&self, snapshot: &NativeRepositorySnapshot) {
        let Some(repository) = snapshot
            .identity
            .as_ref()
            .map(|identity| &identity.worktree_root)
        else {
            return;
        };
        if self.inner.borrow().disposed
            || repository.remote.is_some()
            || snapshot.phase != NativeRepositoryPhase::Ready
            || snapshot.failure.is_some()
            || snapshot.refs_failure.is_some()
            || snapshot.status_failure.is_some()
        {
            return;
        }
        let known = self.entry(repository);
        if let Some(known) = &known
            && known.refs.as_ref() == Some(&snapshot.refs)
            && known.status == snapshot.status
            && known.ref_counts.as_ref() == Some(&snapshot.ref_counts)
        {
            return;
        }
        let history = known.and_then(|known| known.history.clone());
        self.store(
            repository,
            Entry {
                refs: Some(snapshot.refs.clone()),
                ref_counts: Some(snapshot.ref_counts.clone()),
                status: snapshot.status.clone(),
                history,
            },
        );
    }

    fn remember_history(&self, repository: &NativePathIdentity, page: &NativeHistoryPage) {
        if self.inner.borrow().disposed || repository.remote.is_some() || !is_cacheable(page) {
            return;
        }
        let mut entry = self
            .entry(repository)
            .map(|known| (*known).clone())
            .unwrap_or_default();
        entry.history = Some(Rc::new(cacheable(page)));
        self.store(repository, entry);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entries_round_trip_and_reject_other_schemas() {
        let entry = Stored {
            refs: Some(NativeRepositoryRefs::default()),
            ref_counts: Some(NativeRepositoryRefCounts {
                branches: 2,
                remotes: 1,
                tags: 0,
                stashes: 0,
                worktrees: 1,
            }),
            status: None,
            history: None,
        };
        let bytes = encode(&entry);
        assert!(decode(&bytes) == Some(entry));
        let other = String::from_utf8(bytes)
            .unwrap()
            .replace(SCHEMA, "gitlama.view-cache.v1");
        assert!(decode(other.as_bytes()).is_none());
        assert!(decode(b"{\"refs\":null}").is_none());
        assert!(decode(b"not json").is_none());
    }
}
