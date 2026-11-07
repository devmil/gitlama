//! The resource cache: entries per connection, repository and class, bounded and aged.
#![allow(clippy::wildcard_imports)]
use super::*;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum HostingCacheClass {
    ChangeRequests,
    Issues,
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub(super) struct HostingCacheKey {
    pub(super) connection_id: String,
    pub(super) repository_id: String,
    pub(super) class: HostingCacheClass,
}

#[derive(Clone)]
pub(super) struct HostingCacheEntry {
    pub(super) resources: NativeHostingResources,
    pub(super) published_at: Instant,
    pub(super) generation: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HostingCacheSnapshot {
    pub resources: NativeHostingResources,
    pub stale: bool,
}

#[derive(Default)]
pub(super) struct HostingCacheState {
    pub(super) active_repositories: HashSet<(String, String)>,
    pub(super) generations: HashMap<HostingCacheKey, u64>,
    pub(super) in_flight: HashMap<HostingCacheKey, Arc<AtomicBool>>,
    pub(super) entries: HashMap<HostingCacheKey, HostingCacheEntry>,
}

#[derive(Default)]
pub struct HostingCache {
    state: Mutex<HostingCacheState>,
}

impl HostingCache {
    pub fn activate(&self, connection_id: String, repository_id: String) {
        self.state
            .lock()
            .expect("hosting cache lock")
            .active_repositories
            .insert((connection_id, repository_id));
    }

    pub fn deactivate(&self, connection_id: &str, repository_id: &str) {
        let mut state = self.state.lock().expect("hosting cache lock");
        state
            .active_repositories
            .remove(&(connection_id.to_owned(), repository_id.to_owned()));
        for (key, cancellation) in &state.in_flight {
            if key.connection_id == connection_id && key.repository_id == repository_id {
                cancellation.store(true, Ordering::Release);
            }
        }
    }

    pub fn shutdown(&self) {
        let mut state = self.state.lock().expect("hosting cache lock");
        state.active_repositories.clear();
        for cancellation in state.in_flight.values() {
            cancellation.store(true, Ordering::Release);
        }
    }

    pub fn begin_refresh(
        &self,
        connection_id: &str,
        repository_id: &str,
        class: HostingCacheClass,
    ) -> Option<(u64, Arc<AtomicBool>)> {
        let mut state = self.state.lock().expect("hosting cache lock");
        if !state
            .active_repositories
            .contains(&(connection_id.to_owned(), repository_id.to_owned()))
        {
            return None;
        }
        let key = HostingCacheKey {
            connection_id: connection_id.to_owned(),
            repository_id: repository_id.to_owned(),
            class,
        };
        if let Some(previous) = state.in_flight.remove(&key) {
            previous.store(true, Ordering::Release);
        }
        let generation = state
            .generations
            .get(&key)
            .copied()
            .unwrap_or(0)
            .saturating_add(1);
        state.generations.insert(key.clone(), generation);
        let cancellation = Arc::new(AtomicBool::new(false));
        state.in_flight.insert(key, Arc::clone(&cancellation));
        Some((generation, cancellation))
    }

    pub(super) fn begin_refresh_with(
        &self,
        connection_id: &str,
        repository_id: &str,
        class: HostingCacheClass,
        cancellation: Arc<AtomicBool>,
    ) -> Option<u64> {
        let mut state = self.state.lock().expect("hosting cache lock");
        if !state
            .active_repositories
            .contains(&(connection_id.to_owned(), repository_id.to_owned()))
        {
            return None;
        }
        let key = HostingCacheKey {
            connection_id: connection_id.to_owned(),
            repository_id: repository_id.to_owned(),
            class,
        };
        if let Some(previous) = state.in_flight.remove(&key) {
            previous.store(true, Ordering::Release);
        }
        let generation = state
            .generations
            .get(&key)
            .copied()
            .unwrap_or(0)
            .saturating_add(1);
        state.generations.insert(key.clone(), generation);
        state.in_flight.insert(key, cancellation);
        Some(generation)
    }

    pub fn publish(
        &self,
        connection_id: &str,
        repository_id: &str,
        class: HostingCacheClass,
        generation: u64,
        resources: NativeHostingResources,
    ) -> bool {
        let mut state = self.state.lock().expect("hosting cache lock");
        let key = HostingCacheKey {
            connection_id: connection_id.to_owned(),
            repository_id: repository_id.to_owned(),
            class,
        };
        if !state
            .active_repositories
            .contains(&(connection_id.to_owned(), repository_id.to_owned()))
            || state.generations.get(&key).copied() != Some(generation)
            || state
                .in_flight
                .get(&key)
                .is_none_or(|flag| flag.load(Ordering::Acquire))
        {
            return false;
        }
        state.in_flight.remove(&key);
        state.entries.insert(
            key,
            HostingCacheEntry {
                resources,
                published_at: Instant::now(),
                generation,
            },
        );
        true
    }

    #[must_use]
    pub fn lookup(
        &self,
        connection_id: &str,
        repository_id: &str,
        class: HostingCacheClass,
        now: Instant,
    ) -> Option<HostingCacheSnapshot> {
        let state = self.state.lock().expect("hosting cache lock");
        let key = HostingCacheKey {
            connection_id: connection_id.to_owned(),
            repository_id: repository_id.to_owned(),
            class,
        };
        let entry = state.entries.get(&key)?;
        debug_assert_eq!(state.generations.get(&key), Some(&entry.generation));
        let freshness = match class {
            HostingCacheClass::ChangeRequests => CHANGE_REQUEST_FRESHNESS,
            HostingCacheClass::Issues => ISSUE_FRESHNESS,
        };
        Some(HostingCacheSnapshot {
            resources: entry.resources.clone(),
            stale: now.saturating_duration_since(entry.published_at) > freshness,
        })
    }
}
