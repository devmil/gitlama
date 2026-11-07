//! The history graph projection: loading, paging, queries, the branch filter, collapse, selection and metadata.
#![allow(clippy::wildcard_imports)]
use crate::application::{session::*, snapshot::*};
use crate::domain::history::MAX_HISTORY_BRANCH_FILTER_REFS;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::graph::{
    layout_graph, GraphBoundary, GraphCommit, GraphLayout, GraphNodeShape, GraphSegmentKind,
    HISTORY_PAGE_CAPACITY,
};
use devmil_git::cache::CacheLimit;
use devmil_git::loading::graph::{
    GraphCondition, GraphHistoryOrder, GraphMetadataStatus, GraphMetadataUnavailableKind,
    GraphTraversalScope, LoadedTopology,
};
use devmil_git::loading::graph_search::GraphPathQuery;
use devmil_git::loading::history_index::{
    HistoryFilter, HistoryIndex, HistorySearchScope, MAX_HISTORY_PAGE_ROWS,
};
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::status::WorkingTreeState;
use devmil_git::types::{ObjectId, RefId};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

/// A session's history graph: request and query identities, the branch filter and the
/// current projection.
#[derive(Default)]
pub(crate) struct HistoryState {
    pub(crate) next_request: u64,
    pub(crate) next_query: u64,
    /// Survives history reloads so every projection publishes already filtered.
    pub(crate) branch_filter: std::collections::BTreeSet<devmil_git::types::RefId>,
    pub(crate) projection: Option<OwnedHistoryProjection>,
}

pub(crate) struct OwnedHistoryProjection {
    pub(crate) request_id: u64,
    pub(crate) complete: bool,
    /// The references the topology starts from; its completion keeps them.
    pub(crate) scope: GraphTraversalScope,
    pub(crate) head: Option<String>,
    pub(crate) topology: Arc<LoadedTopology>,
    pub(crate) row_positions: HashMap<String, usize>,
    pub(crate) segment_pages: Vec<Vec<usize>>,
    pub(crate) index: HistoryIndex,
    pub(crate) layout: GraphLayout,
    pub(crate) visible_order: Vec<String>,
    pub(crate) visible_positions: HashMap<String, usize>,
    pub(crate) query_sequence: u64,
    pub(crate) accepted_query: String,
    pub(crate) branch_filter: BTreeSet<RefId>,
    pub(crate) matched_order: Vec<String>,
    pub(crate) collapsed: HashSet<String>,
    pub(crate) collapsed_count: usize,
    pub(crate) metadata: HashMap<String, NativeHistoryMetadataRow>,
    pub(crate) stash_refs: HashMap<String, Vec<Vec<u8>>>,
    pub(crate) stash_commits: HashSet<String>,
    pub(crate) expanded_stashes: HashSet<String>,
    pub(crate) current: Option<String>,
    pub(crate) selected: Vec<String>,
    pub(crate) focused: Option<String>,
    pub(crate) lit: HashSet<String>,
    pub(crate) compared: HashSet<String>,
    pub(crate) reveal_sequence: u64,
    pub(crate) reveal: Option<(String, usize)>,
    pub(crate) include_wip: bool,
    pub(crate) wip_conflicted: bool,
    pub(crate) wip_changed_files: u32,
    pub(crate) wip_staged_files: u32,
}

/// Loads a frozen topological history projection and returns its first bounded page.
///
/// Lane reservations use complete topology even for the first bounded page: a prefix
/// cannot identify HEAD ancestry through parents outside that prefix. The accepted
/// projection remains session-owned for cheap bounded
/// window reads and is replaced only by the newest request.
///
/// The history starts from HEAD, branches, remote-tracking branches, tags and the stash.
/// With `other_refs` it also starts from every other reference, such as notes or a tool's
/// checkpoints.
#[must_use]
pub fn repository_session_history_load(
    session_id: u64,
    generation: u64,
    complete: bool,
    maximum_rows: u32,
    other_refs: bool,
) -> NativeHistoryResult {
    if maximum_rows == 0 || maximum_rows as usize > HISTORY_PAGE_CAPACITY {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let (
        repository,
        request_id,
        head,
        include_wip,
        wip_conflicted,
        wip_changed_files,
        wip_staged_files,
    ) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return history_failure(kind),
        };
        session.history.next_request = session.history.next_request.saturating_add(1).max(1);
        let snapshot = session.repository.snapshot();
        let status = snapshot.status.as_deref();
        let head = status
            .as_ref()
            .and_then(|status| status.branch.oid.clone())
            .or_else(|| {
                snapshot
                    .repository
                    .as_ref()
                    .and_then(|repository| match &repository.head {
                        devmil_git::types::HeadState::Attached { target, .. }
                        | devmil_git::types::HeadState::Detached { target } => Some(target.clone()),
                        devmil_git::types::HeadState::Unborn { .. } => None,
                    })
            })
            .map(|id| id.as_str().to_owned());
        let include_wip =
            status.is_some_and(|status| status.working_tree != WorkingTreeState::Clean);
        let wip_conflicted =
            status.is_some_and(|status| status.working_tree == WorkingTreeState::Conflicted);
        let wip_changed_files = status
            .map_or(0, |status| status.entries.len())
            .try_into()
            .unwrap_or(u32::MAX);
        let wip_staged_files = status
            .map_or(0, |status| {
                status
                    .entries
                    .iter()
                    .filter(|entry| map_status_entry(entry).index != NativeChangeKind::Unmodified)
                    .count()
            })
            .try_into()
            .unwrap_or(u32::MAX);
        (
            Arc::clone(&session.repository),
            session.history.next_request,
            head,
            include_wip,
            wip_conflicted,
            wip_changed_files,
            wip_staged_files,
        )
    };
    let scope = history_scope(other_refs);
    let ticket = repository.history(GraphHistoryOrder::Topological, scope);
    let ticket = match ticket {
        Ok(ticket) => ticket,
        Err(error) => return history_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return history_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let topology = match result {
        Ok(topology) => topology,
        Err(error) => return history_failure(map_error_kind(error.kind)),
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    if session.history.next_request != request_id {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    let valid = topology
        .rows
        .iter()
        .map(|row| row.id.as_str())
        .collect::<HashSet<_>>();
    let previous = session.history.projection.as_ref();
    let current = previous
        .and_then(|value| value.current.clone())
        .filter(|value| valid.contains(value.as_str()));
    let selected = previous.map_or_else(Vec::new, |value| {
        value
            .selected
            .iter()
            .filter(|id| valid.contains(id.as_str()))
            .cloned()
            .collect()
    });
    let focused = previous
        .and_then(|value| value.focused.clone())
        .filter(|value| valid.contains(value.as_str()));
    let reveal_sequence = previous.map_or(0, |value| value.reveal_sequence);
    let expanded_stashes =
        previous.map_or_else(HashSet::new, |value| value.expanded_stashes.clone());
    let index = HistoryIndex::new(
        Arc::clone(&topology),
        CacheLimit::new(32, 4 * 1024 * 1024).expect("nonzero history query cache"),
    );
    let lit = history_ancestry(&index, current.as_deref());
    let compared = history_comparison(&index, &selected);
    let commit_order = topology
        .rows
        .iter()
        .map(|row| row.id.as_str().to_owned())
        .collect::<Vec<_>>();
    let visible_order = if include_wip {
        std::iter::once("wip".to_owned())
            .chain(commit_order.iter().cloned())
            .collect()
    } else {
        commit_order.clone()
    };
    let snapshot = session.repository.snapshot();
    let refs = &snapshot.refs;
    let stash_refs = history_ref_decorations(refs);
    let stash_commits = history_stash_commits(refs);
    let mut projection = OwnedHistoryProjection {
        request_id,
        complete,
        scope,
        head,
        index,
        row_positions: topology
            .rows
            .iter()
            .enumerate()
            .map(|(index, row)| (row.id.as_str().to_owned(), index))
            .collect(),
        segment_pages: Vec::new(),
        topology,
        layout: GraphLayout {
            lanes: HashMap::new(),
            segments: Vec::new(),
            lane_count: 0,
        },
        visible_order: visible_order.clone(),
        visible_positions: HashMap::new(),
        query_sequence: 0,
        accepted_query: String::new(),
        branch_filter: session.history.branch_filter.clone(),
        matched_order: commit_order,
        collapsed: HashSet::new(),
        collapsed_count: 0,
        metadata: HashMap::new(),
        stash_refs,
        stash_commits,
        expanded_stashes,
        current,
        selected,
        focused,
        lit,
        compared,
        reveal_sequence,
        reveal: None,
        include_wip,
        wip_conflicted,
        wip_changed_files,
        wip_staged_files,
    };
    if apply_history_branch_filter(&mut projection).is_err() {
        return history_failure(NativeRepositoryFailureKind::InvalidOutput);
    }
    session.history.projection = Some(projection);
    history_page_for(
        session.history.projection.as_ref().unwrap(),
        0,
        maximum_rows as usize,
    )
}

#[must_use]
pub fn repository_session_history_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > HISTORY_PAGE_CAPACITY
        || usize::try_from(offset).is_err()
    {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    let Some(history) = session.history.projection.as_ref() else {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    if history.request_id != request_id {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    history_page_for(
        history,
        usize::try_from(offset).unwrap(),
        maximum_rows as usize,
    )
}

/// Completes a retained preview against the same frozen tips and request identity.
#[must_use]
pub fn repository_session_history_complete(
    session_id: u64,
    generation: u64,
    request_id: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    if request_id == 0 || maximum_rows == 0 || maximum_rows as usize > HISTORY_PAGE_CAPACITY {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let (repository, scope) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return history_failure(kind),
        };
        let Some(history) = session.history.projection.as_ref() else {
            return history_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        if history.request_id != request_id || history.complete {
            return history_failure(NativeRepositoryFailureKind::StaleGeneration);
        }
        (Arc::clone(&session.repository), history.scope)
    };
    let ticket = match repository.history(GraphHistoryOrder::Topological, scope) {
        Ok(ticket) => ticket,
        Err(error) => return history_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return history_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let topology = match result {
        Ok(value) => value,
        Err(error) => return history_failure(map_error_kind(error.kind)),
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    if session
        .history
        .projection
        .as_ref()
        .map(|value| value.request_id)
        != Some(request_id)
    {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    let previous = session.history.projection.as_ref().unwrap();
    if previous.topology.frozen_tips != topology.frozen_tips {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    if Arc::ptr_eq(&previous.topology, &topology) {
        let history = session.history.projection.as_mut().unwrap();
        history.complete = true;
        return history_page_for(history, 0, maximum_rows as usize);
    }
    let retained_head = previous.head.clone();
    let include_wip = previous.include_wip;
    let current = previous.current.clone();
    let selected = previous.selected.clone();
    let focused = previous.focused.clone();
    let lit = previous.lit.clone();
    let reveal_sequence = previous.reveal_sequence;
    let reveal = previous.reveal.clone();
    let wip_conflicted = previous.wip_conflicted;
    let wip_changed_files = previous.wip_changed_files;
    let wip_staged_files = previous.wip_staged_files;
    let query_sequence = previous.query_sequence;
    let accepted_query = previous.accepted_query.clone();
    let expanded_stashes = previous.expanded_stashes.clone();
    let metadata = std::mem::take(&mut session.history.projection.as_mut().unwrap().metadata);
    let snapshot = session.repository.snapshot();
    let refs = &snapshot.refs;
    let stash_refs = history_ref_decorations(refs);
    let stash_commits = history_stash_commits(refs);
    let commit_order = topology
        .rows
        .iter()
        .map(|row| row.id.as_str().to_owned())
        .collect::<Vec<_>>();
    let visible_order = if include_wip {
        std::iter::once("wip".to_owned())
            .chain(commit_order.iter().cloned())
            .collect()
    } else {
        commit_order.clone()
    };
    let mut projection = OwnedHistoryProjection {
        request_id,
        complete: true,
        scope,
        head: retained_head,
        index: HistoryIndex::new(
            Arc::clone(&topology),
            CacheLimit::new(32, 4 * 1024 * 1024).expect("nonzero history query cache"),
        ),
        row_positions: topology
            .rows
            .iter()
            .enumerate()
            .map(|(index, row)| (row.id.as_str().to_owned(), index))
            .collect(),
        segment_pages: Vec::new(),
        topology,
        layout: GraphLayout {
            lanes: HashMap::new(),
            segments: Vec::new(),
            lane_count: 0,
        },
        visible_order: visible_order.clone(),
        visible_positions: HashMap::new(),
        query_sequence,
        accepted_query,
        branch_filter: session.history.branch_filter.clone(),
        matched_order: commit_order,
        collapsed: HashSet::new(),
        collapsed_count: 0,
        metadata,
        stash_refs,
        stash_commits,
        expanded_stashes,
        current,
        selected,
        focused,
        lit,
        compared: HashSet::new(),
        reveal_sequence,
        reveal,
        include_wip,
        wip_conflicted,
        wip_changed_files,
        wip_staged_files,
    };
    // The complete topology reaches ancestry the preview could not.
    projection.compared = history_comparison(&projection.index, &projection.selected);
    // A filtered view's lanes follow its visible set, so only the complete
    // unfiltered graph must keep every lane the preview published.
    let unfiltered = projection.branch_filter.is_empty()
        && session
            .history
            .projection
            .as_ref()
            .unwrap()
            .branch_filter
            .is_empty();
    if apply_history_branch_filter(&mut projection).is_err()
        || unfiltered
            && session
                .history
                .projection
                .as_ref()
                .unwrap()
                .topology
                .rows
                .iter()
                .any(|row| {
                    session
                        .history
                        .projection
                        .as_ref()
                        .unwrap()
                        .layout
                        .lanes
                        .get(row.id.as_str())
                        != projection.layout.lanes.get(row.id.as_str())
                })
    {
        return history_failure(NativeRepositoryFailureKind::InvalidOutput);
    }
    session.history.projection = Some(projection);
    history_page_for(
        session.history.projection.as_ref().unwrap(),
        0,
        maximum_rows as usize,
    )
}

/// Replaces the accepted query over the retained complete topology.
///
/// Metadata and path matches are loaded through shared repository reads. Publication is
/// conditional on the newest query sequence, so a delayed query cannot replace a newer one.
#[must_use]
pub fn repository_session_history_query(
    session_id: u64,
    generation: u64,
    request_id: u64,
    options: NativeHistoryQueryOptions,
) -> NativeHistoryResult {
    let NativeHistoryQueryOptions {
        text,
        search_hash,
        search_message,
        search_author,
        search_path,
        offset,
        maximum_rows,
    } = options;
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > HISTORY_PAGE_CAPACITY
        || text.len() > 1024
        || (!text.is_empty() && !(search_hash || search_message || search_author || search_path))
        || usize::try_from(offset).is_err()
    {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let (repository, topology, query_sequence) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return history_failure(kind),
        };
        let Some(history) = session.history.projection.as_ref() else {
            return history_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        if history.request_id != request_id || !history.complete {
            return history_failure(NativeRepositoryFailureKind::StaleGeneration);
        }
        session.history.next_query = session.history.next_query.saturating_add(1).max(1);
        (
            Arc::clone(&session.repository),
            Arc::clone(&history.topology),
            session.history.next_query,
        )
    };

    let needs_metadata = !text.is_empty() && (search_message || search_author);
    let mut metadata = Vec::new();
    if needs_metadata {
        for batch in topology.rows.chunks(512) {
            let objects = batch.iter().map(|row| row.id.clone()).collect::<Vec<_>>();
            let ticket = match repository.commit_metadata(objects) {
                Ok(value) => value,
                Err(error) => return history_failure(map_error_kind(error.kind)),
            };
            let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
                return history_failure(NativeRepositoryFailureKind::TimedOut);
            };
            let loaded = match result {
                Ok(value) => value,
                Err(error) => return history_failure(map_error_kind(error.kind)),
            };
            if !loaded.missing.is_empty()
                || loaded
                    .records
                    .iter()
                    .any(|record| record.status != GraphMetadataStatus::Available)
            {
                return history_failure(NativeRepositoryFailureKind::InvalidOutput);
            }
            metadata.extend(loaded.records.iter().cloned());
        }
    }

    let mut path_matches = BTreeSet::new();
    if !text.is_empty() && search_path && !topology.rows.is_empty() {
        let ticket = match repository.search_history_paths(
            topology.frozen_tips.clone(),
            GraphPathQuery::DisplaySubstring(text.clone()),
            100_000,
        ) {
            Ok(value) => value,
            Err(error) => return history_failure(map_error_kind(error.kind)),
        };
        let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
            return history_failure(NativeRepositoryFailureKind::TimedOut);
        };
        let loaded = match result {
            Ok(value) => value,
            Err(error) => return history_failure(map_error_kind(error.kind)),
        };
        if loaded.truncated {
            return history_failure(NativeRepositoryFailureKind::TooLarge);
        }
        path_matches.extend(loaded.matches.iter().cloned());
    }

    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    if session.history.next_query != query_sequence {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    let Some(history) = session.history.projection.as_mut() else {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    if history.request_id != request_id || !Arc::ptr_eq(&history.topology, &topology) {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    if !metadata.is_empty() && history.index.hydrate(metadata).is_err() {
        return history_failure(NativeRepositoryFailureKind::InvalidOutput);
    }
    let mut scopes = BTreeSet::new();
    if search_hash {
        scopes.insert(HistorySearchScope::Hash);
    }
    if search_message {
        scopes.insert(HistorySearchScope::Message);
    }
    if search_author {
        scopes.insert(HistorySearchScope::Author);
    }
    if search_path {
        scopes.insert(HistorySearchScope::Path);
    }
    let filter = HistoryFilter {
        text: text.clone(),
        scopes,
        refs: history.branch_filter.clone(),
        path_matches,
    };
    let cancellation = AtomicBool::new(false);
    let mut token = None;
    let mut matches = Vec::new();
    loop {
        let page = match history.index.query(
            &filter,
            MAX_HISTORY_PAGE_ROWS,
            token.as_ref(),
            &cancellation,
        ) {
            Ok(value) => value,
            Err(_) => return history_failure(NativeRepositoryFailureKind::InvalidOptions),
        };
        matches.extend(page.commits.into_iter().map(|id| id.as_str().to_owned()));
        token = page.next;
        if token.is_none() {
            break;
        }
    }
    history.query_sequence = query_sequence;
    history.accepted_query = text;
    history.matched_order = matches;
    if rebuild_history_view(history).is_err() {
        return history_failure(NativeRepositoryFailureKind::InvalidOutput);
    }
    history.reveal = history.current.as_ref().and_then(|id| {
        history
            .visible_order
            .iter()
            .position(|value| value == id)
            .map(|index| (id.clone(), index))
    });
    history_page_for(
        history,
        usize::try_from(offset).unwrap(),
        maximum_rows as usize,
    )
}

/// Replaces the session's history branch filter.
///
/// The filter shows every commit reachable from the named references and
/// survives history reloads, so later previews and completions publish already
/// filtered. An empty filter shows all references. When the retained history
/// matches `request_id`, its view is rebuilt only if the filter changed and the
/// requested window is returned; otherwise the result carries no page. Unknown
/// references match nothing.
#[must_use]
pub fn repository_session_history_branch_filter(
    session_id: u64,
    generation: u64,
    request_id: u64,
    references: Vec<Vec<u8>>,
    offset: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    if maximum_rows == 0
        || maximum_rows as usize > HISTORY_PAGE_CAPACITY
        || references.len() > MAX_HISTORY_BRANCH_FILTER_REFS
        || usize::try_from(offset).is_err()
    {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let mut filter = BTreeSet::new();
    for reference in references {
        if !reference.starts_with(b"refs/") {
            return history_failure(NativeRepositoryFailureKind::InvalidOptions);
        }
        match RefId::from_bytes(reference) {
            Ok(value) => {
                filter.insert(value);
            }
            Err(_) => return history_failure(NativeRepositoryFailureKind::InvalidOptions),
        }
    }
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    session.history.branch_filter.clone_from(&filter);
    let Some(history) = session.history.projection.as_mut() else {
        return NativeHistoryResult {
            page: None,
            failure: None,
        };
    };
    if history.branch_filter != filter {
        // A text query still running was evaluated against the old view.
        session.history.next_query = session.history.next_query.saturating_add(1).max(1);
        history.query_sequence = session.history.next_query;
        history.branch_filter = filter;
        if apply_history_branch_filter(history).is_err() {
            return history_failure(NativeRepositoryFailureKind::InvalidOutput);
        }
        // Keep the selected commit in view when it survives the filter.
        history.reveal = history.current.as_ref().and_then(|id| {
            history
                .visible_order
                .iter()
                .position(|value| value == id)
                .map(|index| (id.clone(), index))
        });
    }
    if request_id == 0 || history.request_id != request_id {
        return NativeHistoryResult {
            page: None,
            failure: None,
        };
    }
    history_page_for(
        history,
        usize::try_from(offset).unwrap(),
        maximum_rows as usize,
    )
}

/// Toggles one merge side-branch collapse while retaining identity-based selection.
#[must_use]
pub fn repository_session_history_collapse(
    session_id: u64,
    generation: u64,
    request_id: u64,
    object_id: String,
    offset: u64,
    maximum_rows: u32,
) -> NativeHistoryResult {
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > HISTORY_PAGE_CAPACITY
        || usize::try_from(offset).is_err()
    {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    let Some(history) = session.history.projection.as_mut() else {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let Some(row) = history
        .topology
        .rows
        .iter()
        .find(|row| row.id.as_str() == object_id)
    else {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    if history.request_id != request_id || row.parents.len() < 2 {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    if history.stash_commits.contains(&object_id) {
        if !history.expanded_stashes.insert(object_id.clone()) {
            history.expanded_stashes.remove(&object_id);
        }
    } else if !history.collapsed.insert(object_id.clone()) {
        history.collapsed.remove(&object_id);
    }
    if rebuild_history_view(history).is_err() {
        return history_failure(NativeRepositoryFailureKind::InvalidOutput);
    }
    history_page_for(
        history,
        usize::try_from(offset).unwrap(),
        maximum_rows as usize,
    )
}

/// Applies ancestry lighting to the retained topology without rebuilding it.
#[must_use]
pub fn repository_session_history_select(
    session_id: u64,
    generation: u64,
    request_id: u64,
    options: NativeHistorySelectionOptions,
) -> NativeHistoryResult {
    let NativeHistorySelectionOptions {
        object_id,
        toggle,
        reveal,
        focus,
        offset,
        maximum_rows,
    } = options;
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > HISTORY_PAGE_CAPACITY
        || usize::try_from(offset).is_err()
    {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_failure(kind),
    };
    let Some(history) = session.history.projection.as_mut() else {
        return history_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    if history.request_id != request_id {
        return history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }

    let changed_current = history.current != object_id;
    if let Some(current) = object_id.as_deref() {
        if !history.row_positions.contains_key(current) {
            return history_failure(NativeRepositoryFailureKind::InvalidOptions);
        }
        history.current = Some(current.to_owned());
        if toggle {
            if let Some(index) = history.selected.iter().position(|id| id == current) {
                history.selected.remove(index);
            } else {
                history.selected.push(current.to_owned());
            }
        } else {
            history.selected.clear();
            history.selected.push(current.to_owned());
        }
        if focus {
            history.focused = Some(current.to_owned());
        }
        if reveal {
            let index = history.row_positions[current];
            history.reveal_sequence = history.reveal_sequence.saturating_add(1).max(1);
            history.reveal = Some((current.to_owned(), index));
        }
    } else {
        history.current = None;
        history.selected.clear();
        history.lit.clear();
        history.reveal = None;
        if focus {
            history.focused = None;
        }
    }
    if changed_current {
        history.lit = history_ancestry(&history.index, history.current.as_deref());
    }
    history.compared = history_comparison(&history.index, &history.selected);
    history_page_for(
        history,
        usize::try_from(offset).unwrap(),
        maximum_rows as usize,
    )
}

/// Hydrates one caller-prioritized bounded metadata batch for the retained topology.
#[must_use]
pub fn repository_session_history_metadata(
    session_id: u64,
    generation: u64,
    request_id: u64,
    object_ids: Vec<String>,
) -> NativeHistoryMetadataResult {
    const MAX_BATCH: usize = 256;
    if request_id == 0 || object_ids.is_empty() || object_ids.len() > MAX_BATCH {
        return history_metadata_failure(request_id, NativeRepositoryFailureKind::InvalidOptions);
    }
    let parsed = match object_ids
        .iter()
        .map(|value| ObjectId::parse(value.clone()))
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(values) => values,
        Err(_) => {
            return history_metadata_failure(
                request_id,
                NativeRepositoryFailureKind::InvalidOptions,
            )
        }
    };
    let repository = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return history_metadata_failure(request_id, kind),
        };
        let Some(history) = session.history.projection.as_ref() else {
            return history_metadata_failure(
                request_id,
                NativeRepositoryFailureKind::InvalidOptions,
            );
        };
        if history.request_id != request_id
            || parsed
                .iter()
                .any(|id| !history.topology.rows.iter().any(|row| row.id == *id))
        {
            return history_metadata_failure(
                request_id,
                NativeRepositoryFailureKind::StaleGeneration,
            );
        }
        Arc::clone(&session.repository)
    };
    let ticket = match repository.commit_metadata(parsed) {
        Ok(ticket) => ticket,
        Err(error) => return history_metadata_failure(request_id, map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return history_metadata_failure(request_id, NativeRepositoryFailureKind::TimedOut);
    };
    let loaded = match result {
        Ok(value) => value,
        Err(error) => return history_metadata_failure(request_id, map_error_kind(error.kind)),
    };
    let mut rows = loaded
        .records
        .iter()
        .map(|record| NativeHistoryMetadataRow {
            object_id: record.id.as_str().to_owned(),
            subject: record.metadata.subject.clone(),
            author: record.metadata.author.clone(),
            avatar_hash: record.metadata.avatar_hash.clone(),
            author_time: record.metadata.author_time,
            failure: match record.status {
                GraphMetadataStatus::Available => None,
                GraphMetadataStatus::Unavailable(kind) => Some(match kind {
                    GraphMetadataUnavailableKind::ObjectTooLarge => {
                        NativeHistoryMetadataFailure::ObjectTooLarge
                    }
                    GraphMetadataUnavailableKind::AuthorTooLarge => {
                        NativeHistoryMetadataFailure::AuthorTooLarge
                    }
                    GraphMetadataUnavailableKind::SubjectTooLarge => {
                        NativeHistoryMetadataFailure::SubjectTooLarge
                    }
                    GraphMetadataUnavailableKind::MalformedCommit => {
                        NativeHistoryMetadataFailure::MalformedCommit
                    }
                }),
            },
        })
        .collect::<Vec<_>>();
    rows.extend(loaded.missing.iter().map(|id| NativeHistoryMetadataRow {
        object_id: id.as_str().to_owned(),
        subject: Vec::new(),
        author: Vec::new(),
        avatar_hash: String::new(),
        author_time: 0,
        failure: Some(NativeHistoryMetadataFailure::Missing),
    }));
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return history_metadata_failure(request_id, kind),
    };
    if session
        .history
        .projection
        .as_ref()
        .map(|value| value.request_id)
        != Some(request_id)
    {
        return history_metadata_failure(request_id, NativeRepositoryFailureKind::StaleGeneration);
    }
    let history = session.history.projection.as_mut().unwrap();
    for row in &rows {
        history.metadata.insert(row.object_id.clone(), row.clone());
    }
    NativeHistoryMetadataResult {
        request_id,
        rows,
        failure: None,
    }
}

pub(crate) fn history_layout_view(
    topology: &LoadedTopology,
    requested_head: Option<&str>,
    visible_order: &[String],
    collapsed_edges: &HashSet<(String, String)>,
    first_parent_only: &HashSet<String>,
    include_wip: bool,
) -> Result<GraphLayout, NativeRepositoryFailureKind> {
    let mut commits = topology
        .rows
        .iter()
        .map(|row| {
            let parents = row.parents.iter().map(|parent| parent.as_str().to_owned());
            GraphCommit::topology(
                row.id.as_str().to_owned(),
                if first_parent_only.contains(row.id.as_str()) {
                    parents.take(1).collect()
                } else {
                    parents.collect()
                },
            )
        })
        .collect::<Vec<_>>();
    for condition in &topology.conditions {
        match condition {
            GraphCondition::ShallowBoundary { commit, .. } => {
                if let Some(row) = commits.iter_mut().find(|row| row.id == commit.as_str()) {
                    row.boundary = Some(GraphBoundary::Shallow);
                    row.shape = GraphNodeShape::Boundary;
                }
            }
            GraphCondition::MissingObject { commit, object } => {
                if let Some(row) = commits.iter_mut().find(|row| row.id == commit.as_str()) {
                    row.missing_parents.insert(object.as_str().to_owned());
                }
            }
            GraphCondition::ReplaceRef { commit } => {
                if let Some(row) = commits.iter_mut().find(|row| row.id == commit.as_str()) {
                    row.shape = GraphNodeShape::Replace;
                }
            }
            GraphCondition::Graft { commit } => {
                if let Some(row) = commits.iter_mut().find(|row| row.id == commit.as_str()) {
                    row.shape = GraphNodeShape::Graft;
                }
            }
        }
    }
    let head = requested_head
        .filter(|head| commits.iter().any(|commit| commit.id == *head))
        .or_else(|| topology.rows.first().map(|row| row.id.as_str()));
    layout_graph(&commits, visible_order, head, collapsed_edges, include_wip)
        .map_err(|_| NativeRepositoryFailureKind::InvalidOutput)
}

pub(crate) fn rebuild_history_view(
    history: &mut OwnedHistoryProjection,
) -> Result<(), NativeRepositoryFailureKind> {
    let mut hidden = HashSet::new();
    let mut stash_hidden = HashSet::new();
    let mut collapsed_edges = HashSet::new();
    // A collapsed stash is drawn as a leaf on its base commit: no edge to its
    // index or untracked commits, and no lane held for them.
    let mut first_parent_only = HashSet::new();
    for merge in history.collapsed.iter().chain(
        history
            .stash_commits
            .iter()
            .filter(|id| !history.expanded_stashes.contains(*id)),
    ) {
        let Some(&position) = history.row_positions.get(merge) else {
            continue;
        };
        let row = &history.topology.rows[position];
        let Some(first_parent) = row.parents.first() else {
            continue;
        };
        let protected = history_ancestry(&history.index, Some(first_parent.as_str()));
        let stash = history.stash_commits.contains(merge);
        if stash {
            first_parent_only.insert(merge.clone());
        }
        for side_parent in row.parents.iter().skip(1) {
            if !stash {
                collapsed_edges.insert((merge.clone(), side_parent.as_str().to_owned()));
            }
            for id in history_ancestry(&history.index, Some(side_parent.as_str())) {
                if !protected.contains(&id) {
                    if history.stash_commits.contains(merge) {
                        stash_hidden.insert(id.clone());
                    }
                    hidden.insert(id);
                }
            }
        }
    }
    for merge in history.collapsed.iter().chain(history.stash_commits.iter()) {
        hidden.remove(merge);
        stash_hidden.remove(merge);
    }
    let visible_commits = history
        .matched_order
        .iter()
        .filter(|id| !hidden.contains(id.as_str()))
        .cloned()
        .collect::<Vec<_>>();
    history.collapsed_count = history
        .matched_order
        .iter()
        .filter(|id| hidden.contains(id.as_str()) && !stash_hidden.contains(id.as_str()))
        .count();
    // A branch filter can hide HEAD. The working-tree row then has nothing to
    // attach to, and lane 0 follows the newest visible commit's first parents
    // instead of leaving an empty lane beside the filtered branches.
    let head_visible = history.branch_filter.is_empty()
        || history
            .head
            .as_deref()
            .is_some_and(|head| visible_commits.iter().any(|id| id == head));
    let include_wip = history.include_wip && head_visible;
    let layout_head = if head_visible {
        history.head.clone()
    } else {
        visible_commits.first().cloned()
    };
    history.layout = history_layout_view(
        &history.topology,
        layout_head.as_deref(),
        &visible_commits,
        &collapsed_edges,
        &first_parent_only,
        include_wip,
    )?;
    history.visible_order = if include_wip {
        std::iter::once("wip".to_owned())
            .chain(visible_commits)
            .collect()
    } else {
        visible_commits
    };
    history.visible_positions = history
        .visible_order
        .iter()
        .enumerate()
        .map(|(position, id)| (id.clone(), position))
        .collect();
    history.segment_pages =
        vec![Vec::new(); history.visible_order.len().div_ceil(HISTORY_PAGE_CAPACITY)];
    for (index, segment) in history.layout.segments.iter().enumerate() {
        let Some(&from) = history.visible_positions.get(&segment.from) else {
            continue;
        };
        let to = history
            .visible_positions
            .get(&segment.to)
            .copied()
            .unwrap_or(from)
            .max(from);
        for page in from / HISTORY_PAGE_CAPACITY..=to / HISTORY_PAGE_CAPACITY {
            history.segment_pages[page].push(index);
        }
    }
    Ok(())
}

/// Resets the view to every commit reachable from the projection's branch
/// filter, in topology order, and lays it out again. Accepted search text
/// belonged to the previous view and is cleared; collapsed merges remain.
pub(crate) fn apply_history_branch_filter(
    history: &mut OwnedHistoryProjection,
) -> Result<(), NativeRepositoryFailureKind> {
    history.accepted_query.clear();
    history.matched_order = if history.branch_filter.is_empty() {
        history
            .topology
            .rows
            .iter()
            .map(|row| row.id.as_str().to_owned())
            .collect()
    } else {
        let filter = HistoryFilter {
            refs: history.branch_filter.clone(),
            ..HistoryFilter::default()
        };
        let cancellation = AtomicBool::new(false);
        let mut token = None;
        let mut matches = Vec::new();
        loop {
            let page = history
                .index
                .query(
                    &filter,
                    MAX_HISTORY_PAGE_ROWS,
                    token.as_ref(),
                    &cancellation,
                )
                .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?;
            matches.extend(page.commits.into_iter().map(|id| id.as_str().to_owned()));
            token = page.next;
            if token.is_none() {
                break;
            }
        }
        matches
    };
    rebuild_history_view(history)
}

pub(crate) fn history_ref_decorations(refs: &[RefsSectionData]) -> HashMap<String, Vec<Vec<u8>>> {
    let mut decorations = HashMap::new();
    for section in refs {
        if let RefsSectionData::Tags(entries) = section {
            for entry in entries {
                let target = entry.peeled_target.as_ref().unwrap_or(&entry.target);
                decorations
                    .entry(target.as_str().to_owned())
                    .or_insert_with(Vec::new)
                    .push(entry.id.as_bytes().to_vec());
            }
        }
        if let RefsSectionData::Stashes(entries) = section {
            for entry in entries {
                decorations
                    .entry(entry.id.0.as_str().to_owned())
                    .or_insert_with(Vec::new)
                    .push(entry.selector.clone());
            }
        }
    }
    decorations
}

pub(crate) fn history_stash_commits(refs: &[RefsSectionData]) -> HashSet<String> {
    refs.iter()
        .filter_map(|section| match section {
            RefsSectionData::Stashes(entries) => Some(entries),
            _ => None,
        })
        .flat_map(|entries| entries.iter().map(|entry| entry.id.0.as_str().to_owned()))
        .collect()
}

/// The references a history starts from: the standard ones, or with `other_refs` every one.
const fn history_scope(other_refs: bool) -> GraphTraversalScope {
    if other_refs {
        GraphTraversalScope::AllReferences
    } else {
        GraphTraversalScope::StandardReferences
    }
}

pub(crate) fn history_page_for(
    history: &OwnedHistoryProjection,
    offset: usize,
    maximum_rows: usize,
) -> NativeHistoryResult {
    const MAX_PARENTS: usize = 64;
    const MAX_REFS: usize = 64;
    let start = offset.min(history.visible_order.len());
    let end = start
        .saturating_add(maximum_rows)
        .min(history.visible_order.len());
    let mut payload_bytes = 0usize;
    let rows = history.visible_order[start..end]
        .iter()
        .filter_map(|visible_id| {
            if visible_id == "wip" {
                let parents = history
                    .head
                    .as_ref()
                    .map(|head| vec![head.clone()])
                    .unwrap_or_default();
                payload_bytes = payload_bytes
                    .saturating_add(visible_id.len())
                    .saturating_add(parents.iter().map(String::len).sum::<usize>())
                    .saturating_add(64);
                return Some(NativeHistoryRow {
                    object_id: visible_id.clone(),
                    parent_count: u32::try_from(parents.len()).unwrap_or(u32::MAX),
                    parents,
                    parents_truncated: false,
                    refs: Vec::new(),
                    ref_count: 0,
                    refs_truncated: false,
                    lane: 0,
                    shape: if history.wip_conflicted {
                        NativeHistoryNodeShape::WipConflict
                    } else {
                        NativeHistoryNodeShape::Wip
                    },
                    metadata_available: true,
                    subject: Vec::new(),
                    author: Vec::new(),
                    avatar_hash: String::new(),
                    author_time: 0,
                    metadata_failure: None,
                    selected: false,
                    current: false,
                    lit: history.current.is_none(),
                    compared: false,
                    wip_changed_files: history.wip_changed_files,
                    wip_staged_files: history.wip_staged_files,
                });
            }
            let row = &history.topology.rows[*history.row_positions.get(visible_id)?];
            let id = row.id.as_str().to_owned();
            let parents = row
                .parents
                .iter()
                .take(MAX_PARENTS)
                .map(|parent| parent.as_str().to_owned())
                .collect::<Vec<_>>();
            let mut all_refs = Vec::new();
            if let Some(stash_refs) = history.stash_refs.get(&id) {
                for reference in stash_refs {
                    if !all_refs.contains(reference) {
                        all_refs.push(reference.clone());
                    }
                }
            }
            for reference in &row.refs {
                let bytes = reference.as_bytes();
                if bytes != b"refs/stash" && !all_refs.iter().any(|value| value == bytes) {
                    all_refs.push(bytes.to_vec());
                }
            }
            let ref_count = all_refs.len();
            let refs = all_refs.into_iter().take(MAX_REFS).collect::<Vec<_>>();
            payload_bytes = payload_bytes
                .saturating_add(id.len())
                .saturating_add(parents.iter().map(String::len).sum::<usize>())
                .saturating_add(refs.iter().map(Vec::len).sum::<usize>())
                .saturating_add(64);
            let shape = match history_shape(&history.topology, &id, row.parents.len()) {
                _ if history.stash_commits.contains(&id) => NativeHistoryNodeShape::Stash,
                GraphNodeShape::Commit => NativeHistoryNodeShape::Commit,
                GraphNodeShape::Merge => NativeHistoryNodeShape::Merge,
                GraphNodeShape::Boundary => NativeHistoryNodeShape::Boundary,
                GraphNodeShape::Graft => NativeHistoryNodeShape::Graft,
                GraphNodeShape::Replace => NativeHistoryNodeShape::Replace,
            };
            let metadata = history.metadata.get(&id);
            let embedded = row.metadata.as_ref();
            let subject = metadata.map_or_else(
                || embedded.map_or_else(Vec::new, |value| value.subject.clone()),
                |value| value.subject.clone(),
            );
            let author = metadata.map_or_else(
                || embedded.map_or_else(Vec::new, |value| value.author.clone()),
                |value| value.author.clone(),
            );
            let avatar_hash = metadata.map_or_else(
                || embedded.map_or_else(String::new, |value| value.avatar_hash.clone()),
                |value| value.avatar_hash.clone(),
            );
            let author_time = metadata.map_or_else(
                || embedded.map_or(0, |value| value.author_time),
                |value| value.author_time,
            );
            payload_bytes = payload_bytes
                .saturating_add(subject.len())
                .saturating_add(author.len())
                .saturating_add(avatar_hash.len());
            Some(NativeHistoryRow {
                object_id: id.clone(),
                parents,
                parent_count: u32::try_from(row.parents.len()).unwrap_or(u32::MAX),
                parents_truncated: row.parents.len() > MAX_PARENTS,
                refs,
                ref_count: u32::try_from(ref_count).unwrap_or(u32::MAX),
                refs_truncated: ref_count > MAX_REFS,
                lane: u32::try_from(history.layout.lanes.get(&id).copied().unwrap_or(0))
                    .unwrap_or(u32::MAX),
                shape,
                metadata_available: metadata.is_some() || embedded.is_some(),
                subject,
                author,
                avatar_hash,
                author_time,
                metadata_failure: metadata.and_then(|value| value.failure),
                selected: history.selected.contains(&id),
                current: history.current.as_deref() == Some(id.as_str()),
                lit: history.lit.contains(&id),
                compared: history.compared.contains(&id),
                wip_changed_files: 0,
                wip_staged_files: 0,
            })
        })
        .collect::<Vec<_>>();
    // Index crossing edges by page so a distant jump needs neither endpoint
    // page nor a scan of the complete graph. Deduplicate unaligned page reads.
    let mut segment_indices = Vec::new();
    if start < end {
        for page in start / HISTORY_PAGE_CAPACITY..=(end - 1) / HISTORY_PAGE_CAPACITY {
            segment_indices.extend_from_slice(&history.segment_pages[page]);
        }
    }
    segment_indices.sort_unstable();
    segment_indices.dedup();
    let segments = segment_indices
        .into_iter()
        .map(|index| &history.layout.segments[index])
        .filter(|segment| {
            let from = history.visible_positions[&segment.from];
            let to = history
                .visible_positions
                .get(&segment.to)
                .copied()
                .unwrap_or(from);
            from < end && to.max(from) >= start
        })
        .map(|segment| {
            payload_bytes = payload_bytes
                .saturating_add(segment.from.len())
                .saturating_add(segment.to.len())
                .saturating_add(49);
            NativeHistorySegment {
                from_row: history.visible_positions[&segment.from] as u64,
                to_row: history
                    .visible_positions
                    .get(&segment.to)
                    .map(|row| *row as u64),
                lit: history.lit.contains(&segment.from),
                from_object_id: segment.from.clone(),
                to_object_id: segment.to.clone(),
                parent_ordinal: u32::try_from(segment.parent_ordinal).unwrap_or(u32::MAX),
                from_lane: u32::try_from(segment.from_lane).unwrap_or(u32::MAX),
                to_lane: u32::try_from(segment.to_lane).unwrap_or(u32::MAX),
                kind: match segment.kind {
                    GraphSegmentKind::Straight => NativeHistorySegmentKind::Straight,
                    GraphSegmentKind::Join => NativeHistorySegmentKind::Join,
                    GraphSegmentKind::Merge => NativeHistorySegmentKind::Merge,
                    GraphSegmentKind::Octopus => NativeHistorySegmentKind::Octopus,
                    GraphSegmentKind::Boundary => NativeHistorySegmentKind::Boundary,
                    GraphSegmentKind::Missing => NativeHistorySegmentKind::Missing,
                    GraphSegmentKind::CollapsedMerge => NativeHistorySegmentKind::CollapsedMerge,
                },
            }
        })
        .collect();
    NativeHistoryResult {
        page: Some(NativeHistoryPage {
            request_id: history.request_id,
            topology_complete: history.complete,
            total_rows: history.visible_order.len() as u64,
            offset: start as u64,
            rows,
            segments,
            lane_count: u32::try_from(history.layout.lane_count).unwrap_or(u32::MAX),
            payload_bytes: payload_bytes as u64,
            lighting_active: history.current.is_some(),
            current_object_id: history.current.clone(),
            selected_object_ids: history.selected.clone(),
            focused_object_id: history.focused.clone(),
            comparison_old_object_id: (history.selected.len() == 2)
                .then(|| history.selected[0].clone()),
            comparison_new_object_id: (history.selected.len() == 2)
                .then(|| history.selected[1].clone()),
            reveal_sequence: history.reveal_sequence,
            reveal_object_id: history.reveal.as_ref().map(|(id, _)| id.clone()),
            reveal_index: history
                .reveal
                .as_ref()
                .and_then(|(id, _)| history.visible_positions.get(id).copied())
                .and_then(|index| u64::try_from(index).ok()),
            query_sequence: history.query_sequence,
            query_active: !history.accepted_query.is_empty(),
            accepted_query: history.accepted_query.clone(),
            branch_filter: history
                .branch_filter
                .iter()
                .map(|reference| reference.as_bytes().to_vec())
                .collect(),
            selected_filtered_out: history
                .selected
                .iter()
                .any(|id| !history.visible_positions.contains_key(id)),
            collapsed_commits: history.collapsed_count as u64,
            other_refs: history.scope == GraphTraversalScope::AllReferences,
        }),
        failure: None,
    }
}

pub(crate) fn history_ancestry(index: &HistoryIndex, selected: Option<&str>) -> HashSet<String> {
    let Some(selected) = selected.and_then(|id| ObjectId::parse(id).ok()) else {
        return HashSet::new();
    };
    index
        .ancestor_positions(&selected)
        .into_iter()
        .map(|position| index.topology().rows[position].id.as_str().to_owned())
        .collect()
}

/// The commits only one of two compared commits reaches: what the comparison
/// spans, also when the two lie on diverged branches.
pub(crate) fn history_comparison(index: &HistoryIndex, selected: &[String]) -> HashSet<String> {
    let [old, new] = selected else {
        return HashSet::new();
    };
    let old = history_ancestry(index, Some(old));
    let new = history_ancestry(index, Some(new));
    old.symmetric_difference(&new).cloned().collect()
}

pub(crate) fn history_shape(
    topology: &LoadedTopology,
    id: &str,
    parent_count: usize,
) -> GraphNodeShape {
    for condition in &topology.conditions {
        match condition {
            GraphCondition::ShallowBoundary { commit, .. } if commit.as_str() == id => {
                return GraphNodeShape::Boundary;
            }
            GraphCondition::ReplaceRef { commit } if commit.as_str() == id => {
                return GraphNodeShape::Replace;
            }
            GraphCondition::Graft { commit } if commit.as_str() == id => {
                return GraphNodeShape::Graft;
            }
            _ => {}
        }
    }
    if parent_count > 1 {
        GraphNodeShape::Merge
    } else {
        GraphNodeShape::Commit
    }
}

pub(crate) const fn history_failure(kind: NativeRepositoryFailureKind) -> NativeHistoryResult {
    NativeHistoryResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn history_metadata_failure(
    request_id: u64,
    kind: NativeRepositoryFailureKind,
) -> NativeHistoryMetadataResult {
    NativeHistoryMetadataResult {
        request_id,
        rows: Vec::new(),
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::{allocate_activity_id, ActivityStore};
    use crate::test_support::*;

    use crate::application::{diff::*, history::*, inspection::*};

    use crate::diff::NativeDiffLayout;

    use crate::domain::history::MAX_HISTORY_BRANCH_FILTER_REFS;

    use devmil_git::RepositoryOptions;
    use std::collections::HashSet;
    use std::fs;

    use std::process::Command;

    use std::sync::Arc;
    use std::time::Duration;
    use std::time::Instant;

    #[test]
    fn history_decorates_annotated_and_lightweight_tags_and_retains_overflow_refs() {
        let fixture = GitFixture::new();
        fast_import_linear(&fixture.0, 3);
        transfer_git(&fixture.0, &["tag", "-a", "v-annotated", "-m", "release"]);
        transfer_git(&fixture.0, &["tag", "v-lightweight"]);
        transfer_git(&fixture.0, &["branch", "topic"]);
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            79,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let snapshot = wait_for_ready(&session);
        let page = repository_session_history_load(session.session_id, 79, true, 5, false)
            .page
            .unwrap();
        let head = &page.rows[0];
        assert!(head.refs.contains(&b"refs/tags/v-annotated".to_vec()));
        assert!(head.refs.contains(&b"refs/tags/v-lightweight".to_vec()));
        assert!(head.refs.contains(&b"refs/heads/topic".to_vec()));
        assert_eq!(head.refs.len(), head.ref_count as usize);
        assert!(!head.refs_truncated);
        let tag = snapshot
            .refs
            .tags
            .iter()
            .find(|tag| tag.name == b"v-annotated")
            .unwrap();
        assert_eq!(tag.target, head.object_id);
        assert!(repository_session_close(session.session_id, 79).accepted);
    }

    #[test]
    fn history_shows_commits_only_other_refs_reach_on_request() {
        let fixture = GitFixture::new();
        let rev = |name: &str| {
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", name]))
                .unwrap()
                .trim()
                .to_owned()
        };
        transfer_git(&fixture.0, &["commit", "-q", "--allow-empty", "-m", "base"]);
        transfer_git(&fixture.0, &["commit", "-q", "--allow-empty", "-m", "tool"]);
        let checkpoint = rev("HEAD");
        transfer_git(&fixture.0, &["update-ref", "refs/t3/checkpoints/1", "HEAD"]);
        transfer_git(&fixture.0, &["reset", "-q", "--hard", "HEAD~1"]);
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            86,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let ids = |page: &NativeHistoryPage| {
            page.rows
                .iter()
                .map(|row| row.object_id.clone())
                .collect::<Vec<_>>()
        };

        let preview = repository_session_history_load(session.session_id, 86, false, 16, false)
            .page
            .unwrap();
        assert!(!preview.other_refs);
        assert!(!ids(&preview).contains(&checkpoint));
        // Completion keeps the references the preview started from.
        let complete =
            repository_session_history_complete(session.session_id, 86, preview.request_id, 16)
                .page
                .unwrap();
        assert!(!complete.other_refs);
        assert_eq!(complete.total_rows, 1);
        assert!(!ids(&complete).contains(&checkpoint));
        let hidden = repository_session_history_select(
            session.session_id,
            86,
            complete.request_id,
            NativeHistorySelectionOptions {
                object_id: Some(checkpoint.clone()),
                toggle: false,
                reveal: true,
                focus: false,
                offset: 0,
                maximum_rows: 16,
            },
        );
        assert_eq!(
            hidden.failure.map(|failure| failure.kind),
            Some(NativeRepositoryFailureKind::InvalidOptions)
        );

        let all = repository_session_history_load(session.session_id, 86, true, 16, true)
            .page
            .unwrap();
        assert!(all.other_refs);
        assert_eq!(all.total_rows, 2);
        let row = all
            .rows
            .iter()
            .find(|row| row.object_id == checkpoint)
            .unwrap();
        assert_eq!(row.refs, vec![b"refs/t3/checkpoints/1".to_vec()]);
        assert!(repository_session_close(session.session_id, 86).accepted);
    }

    #[test]
    fn history_comparison_marks_both_sides_of_diverged_branches() {
        let fixture = GitFixture::new();
        let rev = |name: &str| {
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", name]))
                .unwrap()
                .trim()
                .to_owned()
        };
        transfer_git(&fixture.0, &["commit", "-q", "--allow-empty", "-m", "base"]);
        let base = rev("HEAD");
        transfer_git(&fixture.0, &["checkout", "-q", "-b", "side"]);
        transfer_git(&fixture.0, &["commit", "-q", "--allow-empty", "-m", "side"]);
        let side = rev("HEAD");
        transfer_git(&fixture.0, &["checkout", "-q", "main"]);
        transfer_git(
            &fixture.0,
            &["commit", "-q", "--allow-empty", "-m", "main one"],
        );
        let main_one = rev("HEAD");
        transfer_git(
            &fixture.0,
            &["commit", "-q", "--allow-empty", "-m", "main two"],
        );
        let main_two = rev("HEAD");
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            85,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let page = repository_session_history_load(session.session_id, 85, true, 16, false)
            .page
            .unwrap();
        let select = |object_id: &str, toggle: bool| {
            repository_session_history_select(
                session.session_id,
                85,
                page.request_id,
                NativeHistorySelectionOptions {
                    object_id: Some(object_id.to_owned()),
                    toggle,
                    reveal: false,
                    focus: false,
                    offset: 0,
                    maximum_rows: 16,
                },
            )
            .page
            .unwrap()
        };
        let compared = |page: &NativeHistoryPage| {
            page.rows
                .iter()
                .filter(|row| row.compared)
                .map(|row| row.object_id.clone())
                .collect::<HashSet<_>>()
        };

        assert!(compared(&select(&main_two, false)).is_empty());
        // Rows between the two in graph order need not be on either side.
        let diverged = select(&side, true);
        assert_eq!(
            compared(&diverged),
            HashSet::from([main_two.clone(), main_one.clone(), side.clone()])
        );
        assert!(!compared(&diverged).contains(&base));

        select(&main_one, false);
        let linear = select(&main_two, true);
        assert_eq!(compared(&linear), HashSet::from([main_two.clone()]));
        assert!(compared(&select(&base, true)).is_empty());
        assert!(repository_session_close(session.session_id, 85).accepted);
    }

    #[test]
    fn history_projection_uses_bounded_pages_and_rejects_replaced_requests() {
        let fixture = GitFixture::new();
        fast_import_linear(&fixture.0, 12);
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            78,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let preview = repository_session_history_load(session.session_id, 78, false, 5, false)
            .page
            .unwrap();
        assert!(!preview.topology_complete);
        assert_eq!(preview.total_rows, 12);
        assert_eq!(preview.rows.len(), 5);
        assert!(preview.payload_bytes < 64 * 1024);
        assert!(preview.rows.iter().all(|row| row.parents.len() <= 64));
        assert!(preview.rows.iter().all(|row| row.refs.len() <= 64));
        let old_request = preview.request_id;

        let complete = repository_session_history_complete(session.session_id, 78, old_request, 4)
            .page
            .unwrap();
        assert!(complete.topology_complete);
        assert_eq!(complete.total_rows, 12);
        assert_eq!(complete.request_id, old_request);
        let second =
            repository_session_history_page(session.session_id, 78, complete.request_id, 4, 4)
                .page
                .unwrap();
        assert_eq!(second.offset, 4);
        assert_eq!(second.rows.len(), 4);
        assert_eq!(second.rows[0].object_id, complete.rows[3].parents[0]);
        let visible_ids = complete
            .rows
            .iter()
            .take(3)
            .map(|row| row.object_id.clone())
            .collect::<Vec<_>>();
        let metadata = repository_session_history_metadata(
            session.session_id,
            78,
            complete.request_id,
            visible_ids,
        );
        assert!(metadata.failure.is_none());
        assert_eq!(metadata.rows.len(), 3);
        assert!(metadata.rows.iter().all(|row| row.failure.is_none()));
        let hydrated =
            repository_session_history_page(session.session_id, 78, complete.request_id, 0, 4)
                .page
                .unwrap();
        assert!(hydrated.rows.iter().take(3).all(|row| {
            row.metadata_available && !row.subject.is_empty() && !row.author.is_empty()
        }));
        let selected_id = complete.rows[2].object_id.clone();
        let lit = repository_session_history_select(
            session.session_id,
            78,
            complete.request_id,
            NativeHistorySelectionOptions {
                object_id: Some(selected_id.clone()),
                toggle: false,
                reveal: true,
                focus: true,
                offset: 0,
                maximum_rows: 4,
            },
        )
        .page
        .unwrap();
        assert!(lit.lighting_active);
        assert!(!lit.rows[0].lit, "newer descendants must remain unlit");
        assert!(lit.rows[2].selected && lit.rows[2].lit);
        assert!(lit.rows[3].lit, "selected ancestors must be lit");
        assert_eq!(lit.current_object_id.as_deref(), Some(selected_id.as_str()));
        assert_eq!(lit.focused_object_id.as_deref(), Some(selected_id.as_str()));
        assert_eq!(lit.reveal_sequence, 1);
        let second_id = complete.rows[1].object_id.clone();
        let compared = repository_session_history_select(
            session.session_id,
            78,
            complete.request_id,
            NativeHistorySelectionOptions {
                object_id: Some(second_id.clone()),
                toggle: true,
                reveal: true,
                focus: false,
                offset: 0,
                maximum_rows: 4,
            },
        )
        .page
        .unwrap();
        assert_eq!(
            compared.comparison_old_object_id.as_deref(),
            Some(selected_id.as_str())
        );
        assert_eq!(
            compared.comparison_new_object_id.as_deref(),
            Some(second_id.as_str())
        );
        assert_eq!(compared.reveal_sequence, 2);
        assert_eq!(
            compared.focused_object_id.as_deref(),
            Some(selected_id.as_str()),
            "selection and focus identities are independent"
        );
        let repeated = repository_session_history_select(
            session.session_id,
            78,
            complete.request_id,
            NativeHistorySelectionOptions {
                object_id: Some(second_id),
                toggle: false,
                reveal: true,
                focus: false,
                offset: 0,
                maximum_rows: 4,
            },
        )
        .page
        .unwrap();
        assert_eq!(repeated.reveal_sequence, 3);
        let replacement = repository_session_history_load(session.session_id, 78, false, 4, false)
            .page
            .unwrap();
        assert!(replacement.request_id > old_request);
        assert_eq!(replacement.current_object_id, repeated.current_object_id);
        assert_eq!(
            replacement.selected_object_ids,
            repeated.selected_object_ids
        );
        assert_eq!(replacement.focused_object_id, repeated.focused_object_id);
        assert_eq!(replacement.reveal_sequence, repeated.reveal_sequence);
        assert!(replacement.reveal_object_id.is_none());
        assert_eq!(
            repository_session_history_page(session.session_id, 78, old_request, 0, 4)
                .failure
                .unwrap()
                .kind,
            NativeRepositoryFailureKind::StaleGeneration
        );
        assert_eq!(
            repository_session_history_select(
                session.session_id,
                78,
                old_request,
                NativeHistorySelectionOptions {
                    object_id: Some(selected_id),
                    toggle: false,
                    reveal: false,
                    focus: true,
                    offset: 0,
                    maximum_rows: 4,
                },
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::StaleGeneration
        );
        assert!(repository_session_close(session.session_id, 78).accepted);
        assert_eq!(
            repository_session_history_select(
                session.session_id,
                78,
                replacement.request_id,
                NativeHistorySelectionOptions {
                    object_id: replacement.current_object_id,
                    toggle: false,
                    reveal: true,
                    focus: false,
                    offset: 0,
                    maximum_rows: 4,
                },
            )
            .failure
            .unwrap()
            .kind,
            NativeRepositoryFailureKind::RetiredSession
        );
    }

    #[test]
    fn history_completion_reserves_lanes_beyond_a_merge_heavy_prefix() {
        use std::io::Write;
        let fixture = GitFixture::new();
        let mut import = Command::new("git")
            .args(["fast-import", "--quiet"])
            .current_dir(&fixture.0)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        {
            let mut input = import.stdin.take().unwrap();
            for mark in 1..=600 {
                writeln!(input, "commit refs/heads/main\nmark :{mark}\ncommitter Test <test@example.invalid> {} +0000\ndata 4\nmain", 1_700_000_000 + mark).unwrap();
                if mark > 1 {
                    writeln!(input, "from :{}", mark - 1).unwrap();
                }
                writeln!(input).unwrap();
            }
            for mark in 601..=1200 {
                writeln!(input, "commit refs/heads/side\nmark :{mark}\ncommitter Test <test@example.invalid> {} +0000\ndata 4\nside\nfrom :{}\nmerge :{}\n", 1_700_000_000 + mark, if mark == 601 { 1 } else { mark - 1 }, mark - 600).unwrap();
            }
            writeln!(input, "commit refs/heads/main\ncommitter Test <test@example.invalid> 1700001201 +0000\ndata 4\nhead\nfrom :1\nmerge :1200\n").unwrap();
        }
        assert!(import.wait().unwrap().success());
        transfer_git(&fixture.0, &["symbolic-ref", "HEAD", "refs/heads/main"]);
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            783,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let preview = repository_session_history_load(session.session_id, 783, false, 512, false)
            .page
            .unwrap();
        let completed =
            repository_session_history_complete(session.session_id, 783, preview.request_id, 512);
        assert!(completed.failure.is_none(), "{:?}", completed.failure);
        let completed = completed.page.unwrap();
        assert_eq!(completed.total_rows, 1201);
        assert_eq!(preview.rows, completed.rows);
        assert_eq!(preview.segments, completed.segments);
        let tail =
            repository_session_history_page(session.session_id, 783, preview.request_id, 1024, 512)
                .page
                .unwrap();
        assert_eq!(tail.rows.len(), 177);
        assert!(tail.segments.iter().any(|edge| edge.from_row < tail.offset));
        // A single row in the middle of a long edge must carry the full span,
        // even when neither endpoint belongs to the requested window.
        let edge = completed
            .segments
            .iter()
            .find(|edge| edge.to_row.is_some_and(|to| to > edge.from_row + 512))
            .expect("fixture must contain an edge spanning pages");
        let middle = edge.from_row + 256;
        let window =
            repository_session_history_page(session.session_id, 783, preview.request_id, middle, 1)
                .page
                .unwrap();
        assert!(window.segments.contains(edge));
        assert!(!window
            .rows
            .iter()
            .any(|row| row.object_id == edge.from_object_id || row.object_id == edge.to_object_id));
        let unaligned =
            repository_session_history_page(session.session_id, 783, preview.request_id, 500, 32)
                .page
                .unwrap();
        let identities = unaligned
            .segments
            .iter()
            .map(|edge| (&edge.from_object_id, edge.parent_ordinal))
            .collect::<HashSet<_>>();
        assert_eq!(identities.len(), unaligned.segments.len());

        assert!(repository_session_close(session.session_id, 783).accepted);
    }

    #[test]
    fn history_completion_keeps_worktree_head_when_remote_ref_is_ahead() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let head = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        fs::write(fixture.0.join("tracked.txt"), b"remote\n").unwrap();
        transfer_git(&fixture.0, &["commit", "-qam", "remote"]);
        let remote = String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
            .unwrap()
            .trim()
            .to_owned();
        transfer_git(
            &fixture.0,
            &["update-ref", "refs/remotes/origin/main", &remote],
        );
        transfer_git(&fixture.0, &["reset", "--hard", &head]);
        fs::write(fixture.0.join("tracked.txt"), b"worktree\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            78,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let preview = repository_session_history_load(session.session_id, 78, false, 8, false)
            .page
            .unwrap();
        let completed =
            repository_session_history_complete(session.session_id, 78, preview.request_id, 8)
                .page
                .unwrap();
        assert_eq!(completed.rows[1].object_id, remote);
        assert_eq!(completed.rows[2].object_id, head);
        assert_eq!(completed.rows[0].parents, [head.as_str()]);
        assert!(completed
            .segments
            .iter()
            .any(|segment| { segment.from_object_id == "wip" && segment.to_object_id == head }));
        assert!(repository_session_close(session.session_id, 78).accepted);
    }

    #[test]
    fn history_projection_tracks_worktree_row_and_head_edge() {
        let fixture = GitFixture::new();
        fast_import_linear(&fixture.0, 2);
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            782,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let ready = wait_for_ready(&session);

        let clean = repository_session_history_load(session.session_id, 782, true, 8, false)
            .page
            .unwrap();
        assert_eq!(clean.total_rows, 2);
        assert!(clean.rows.iter().all(|row| row.object_id != "wip"));

        fs::write(fixture.0.join("staged.txt"), b"staged\n").unwrap();
        assert!(Command::new("git")
            .args(["add", "--", "staged.txt"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        fs::write(fixture.0.join("unstaged.txt"), b"unstaged\n").unwrap();
        assert!(repository_session_refresh(session.session_id, 782).accepted);
        let dirty = wait_for_new_revision(&session, ready.revision);
        assert_eq!(
            dirty.status.as_ref().unwrap().working_tree,
            NativeWorkingTreeState::Dirty
        );

        let projected = repository_session_history_load(session.session_id, 782, true, 8, false)
            .page
            .unwrap();
        assert_eq!(projected.total_rows, 3);
        let wip = &projected.rows[0];
        assert_eq!(wip.object_id, "wip");
        assert_eq!(wip.shape, NativeHistoryNodeShape::Wip);
        assert_eq!(wip.wip_changed_files, 2);
        assert_eq!(wip.wip_staged_files, 1);
        let head = &projected.rows[1].object_id;
        assert_eq!(wip.parents, vec![head.clone()]);
        assert!(projected.segments.iter().any(|segment| {
            segment.from_object_id == "wip"
                && segment.to_object_id == *head
                && segment.kind == NativeHistorySegmentKind::Straight
        }));

        assert!(Command::new("git")
            .args(["reset", "--hard", "-q"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        fs::remove_file(fixture.0.join("unstaged.txt")).unwrap();
        assert!(repository_session_refresh(session.session_id, 782).accepted);
        let clean_again = wait_for_new_revision(&session, dirty.revision);
        assert_eq!(
            clean_again.status.as_ref().unwrap().working_tree,
            NativeWorkingTreeState::Clean
        );
        let reloaded = repository_session_history_load(session.session_id, 782, true, 8, false)
            .page
            .unwrap();
        assert_eq!(reloaded.total_rows, 2);
        assert!(reloaded.rows.iter().all(|row| row.object_id != "wip"));
        assert!(repository_session_close(session.session_id, 782).accepted);
    }

    #[test]
    fn history_branch_filter_shows_reachable_union_and_survives_reloads() {
        let fixture = GitFixture::new();
        let commit = |message: &str| {
            fs::write(fixture.0.join("file.txt"), message).unwrap();
            transfer_git(&fixture.0, &["add", "file.txt"]);
            transfer_git(&fixture.0, &["commit", "-qm", message]);
            String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                .unwrap()
                .trim()
                .to_owned()
        };
        let base = commit("base");
        transfer_git(&fixture.0, &["checkout", "-qb", "topic"]);
        let topic_one = commit("topic one");
        let topic_two = commit("topic two");
        transfer_git(&fixture.0, &["checkout", "-q", "main"]);
        transfer_git(&fixture.0, &["checkout", "-qb", "other"]);
        let other = commit("other marker");
        transfer_git(&fixture.0, &["checkout", "-q", "main"]);
        let main = commit("main");
        transfer_git(
            &fixture.0,
            &["update-ref", "refs/remotes/origin/other", &other],
        );
        fs::write(fixture.0.join("file.txt"), b"dirty").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            784,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let ready = wait_for_ready(&session);
        assert_eq!(
            ready.status.as_ref().unwrap().working_tree,
            NativeWorkingTreeState::Dirty
        );
        let history = repository_session_history_load(session.session_id, 784, true, 32, false)
            .page
            .unwrap();
        assert_eq!(history.total_rows, 6, "five commits and the working tree");
        let filter = |references: Vec<&[u8]>| {
            repository_session_history_branch_filter(
                session.session_id,
                784,
                history.request_id,
                references.into_iter().map(<[u8]>::to_vec).collect(),
                0,
                32,
            )
        };

        // HEAD is outside the filter: no working-tree row, lane 0 follows the
        // filtered branch, and every edge stays inside the filtered history.
        let topic = filter(vec![b"refs/heads/topic"]).page.unwrap();
        let ids = topic
            .rows
            .iter()
            .map(|row| row.object_id.clone())
            .collect::<Vec<_>>();
        assert_eq!(ids, [topic_two.clone(), topic_one.clone(), base.clone()]);
        assert!(topic.rows.iter().all(|row| row.lane == 0));
        assert_eq!(topic.lane_count, 1);
        assert!(topic
            .segments
            .iter()
            .all(|segment| segment.from_object_id != "wip"));
        assert_filtered_edges_closed(&topic, &topic);

        // Several references show the union of their histories.
        let union = filter(vec![b"refs/heads/topic", b"refs/remotes/origin/other"])
            .page
            .unwrap();
        assert_eq!(union.total_rows, 4);
        assert!(union.rows.iter().any(|row| row.object_id == other));
        assert!(union.rows.iter().all(|row| row.object_id != main));
        assert_eq!(
            union.branch_filter,
            vec![
                b"refs/heads/topic".to_vec(),
                b"refs/remotes/origin/other".to_vec()
            ],
        );
        assert_eq!(union.rows[0].lane, 0);
        assert_filtered_edges_closed(&union, &union);

        // The checked-out branch keeps its working-tree row on lane 0.
        let current = filter(vec![b"refs/heads/main"]).page.unwrap();
        assert_eq!(current.rows[0].object_id, "wip");
        assert_eq!(current.rows[1].object_id, main);
        assert_eq!(current.total_rows, 3);

        // Search stays inside the filter; an unchanged filter is not rebuilt.
        let searched = repository_session_history_query(
            session.session_id,
            784,
            history.request_id,
            NativeHistoryQueryOptions {
                text: "other marker".into(),
                search_hash: false,
                search_message: true,
                search_author: false,
                search_path: false,
                offset: 0,
                maximum_rows: 32,
            },
        )
        .page
        .unwrap();
        assert_eq!(searched.total_rows, 0);
        let unchanged = filter(vec![b"refs/heads/main"]).page.unwrap();
        assert_eq!(unchanged.query_sequence, searched.query_sequence);
        assert_eq!(unchanged.accepted_query, "other marker");
        let changed = filter(vec![b"refs/heads/topic"]).page.unwrap();
        assert!(changed.query_sequence > searched.query_sequence);
        assert!(changed.accepted_query.is_empty());

        // Reloads publish already filtered, from the first page on.
        let preview = repository_session_history_load(session.session_id, 784, false, 32, false)
            .page
            .unwrap();
        assert_eq!(preview.total_rows, 3);
        assert_eq!(preview.branch_filter, vec![b"refs/heads/topic".to_vec()]);
        let completed =
            repository_session_history_complete(session.session_id, 784, preview.request_id, 32)
                .page
                .unwrap();
        assert_eq!(completed.rows, preview.rows);

        // Unknown references match nothing; malformed input is rejected and
        // leaves the filter in place.
        let unknown = repository_session_history_branch_filter(
            session.session_id,
            784,
            completed.request_id,
            vec![b"refs/heads/missing".to_vec()],
            0,
            32,
        )
        .page
        .unwrap();
        assert_eq!(unknown.total_rows, 0);
        for invalid in [
            vec![b"topic".to_vec()],
            vec![b"refs/heads/..".to_vec()],
            (0..=MAX_HISTORY_BRANCH_FILTER_REFS)
                .map(|index| format!("refs/heads/b{index}").into_bytes())
                .collect(),
        ] {
            assert_eq!(
                repository_session_history_branch_filter(
                    session.session_id,
                    784,
                    completed.request_id,
                    invalid,
                    0,
                    32,
                )
                .failure
                .map(|failure| failure.kind),
                Some(NativeRepositoryFailureKind::InvalidOptions),
            );
        }

        // Without a matching history the filter is stored for the next load.
        let stored =
            repository_session_history_branch_filter(session.session_id, 784, 0, Vec::new(), 0, 32);
        assert!(stored.page.is_none() && stored.failure.is_none());
        let reloaded = repository_session_history_load(session.session_id, 784, true, 32, false)
            .page
            .unwrap();
        assert_eq!(reloaded.total_rows, 6);
        assert!(reloaded.branch_filter.is_empty());
        assert!(repository_session_close(session.session_id, 784).accepted);
    }

    #[test]
    fn history_query_collapse_and_reflog_preserve_repository_truth_and_identity() {
        let fixture = GitFixture::new();
        let commit = |message: &str, path: &str, content: &[u8]| {
            fs::write(fixture.0.join(path), content).unwrap();
            assert!(Command::new("git")
                .args(["add", "--", path])
                .current_dir(&fixture.0)
                .status()
                .unwrap()
                .success());
            assert!(Command::new("git")
                .args(["commit", "-q", "-m", message])
                .current_dir(&fixture.0)
                .env("GIT_AUTHOR_NAME", "Query Author")
                .env("GIT_AUTHOR_EMAIL", "query@example.invalid")
                .env("GIT_COMMITTER_NAME", "Query Author")
                .env("GIT_COMMITTER_EMAIL", "query@example.invalid")
                .status()
                .unwrap()
                .success());
        };
        commit("base", "base.txt", b"base\n");
        assert!(Command::new("git")
            .args(["checkout", "-q", "-b", "topic"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        commit("topic marker", "deep-match.txt", b"topic\n");
        assert!(Command::new("git")
            .args(["checkout", "-q", "main"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        commit("main marker", "main.txt", b"main\n");
        assert!(Command::new("git")
            .args(["merge", "-q", "--no-ff", "topic", "-m", "merge topic"])
            .current_dir(&fixture.0)
            .env("GIT_AUTHOR_NAME", "Query Author")
            .env("GIT_AUTHOR_EMAIL", "query@example.invalid")
            .env("GIT_COMMITTER_NAME", "Query Author")
            .env("GIT_COMMITTER_EMAIL", "query@example.invalid")
            .status()
            .unwrap()
            .success());

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            781,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let history = repository_session_history_load(session.session_id, 781, true, 32, false)
            .page
            .unwrap();
        assert_eq!(history.total_rows, 4);
        let merge = history.rows[0].object_id.clone();
        let topic = String::from_utf8(
            Command::new("git")
                .args(["rev-parse", "topic"])
                .current_dir(&fixture.0)
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap()
        .trim()
        .to_owned();
        assert!(history.rows.iter().any(|row| {
            row.object_id == topic
                && row
                    .refs
                    .iter()
                    .any(|reference| reference == b"refs/heads/topic")
        }));
        let topic_branch = repository_session_history_branch_filter(
            session.session_id,
            781,
            history.request_id,
            vec![b"refs/heads/topic".to_vec()],
            0,
            32,
        )
        .page
        .unwrap();
        assert_eq!(
            topic_branch.total_rows, 2,
            "topic tip and its base are reachable"
        );
        assert_eq!(
            topic_branch.branch_filter,
            vec![b"refs/heads/topic".to_vec()]
        );
        assert!(!topic_branch.query_active);
        assert!(repository_session_history_branch_filter(
            session.session_id,
            781,
            history.request_id,
            Vec::new(),
            0,
            32,
        )
        .page
        .is_some_and(|page| page.total_rows == 4 && page.branch_filter.is_empty()));
        let filtered = repository_session_history_query(
            session.session_id,
            781,
            history.request_id,
            NativeHistoryQueryOptions {
                text: "topic marker".into(),
                search_hash: false,
                search_message: true,
                search_author: false,
                search_path: false,
                offset: 0,
                maximum_rows: 32,
            },
        )
        .page
        .unwrap();
        assert_eq!(filtered.total_rows, 1);
        assert_eq!(filtered.rows[0].object_id, topic);
        assert_eq!(filtered.accepted_query, "topic marker");
        let activity_count = repository_session_activity(session.session_id, 781, 64)
            .page
            .unwrap()
            .records
            .len();
        let repeated_filter = repository_session_history_query(
            session.session_id,
            781,
            history.request_id,
            NativeHistoryQueryOptions {
                text: "topic marker".into(),
                search_hash: false,
                search_message: true,
                search_author: false,
                search_path: false,
                offset: 0,
                maximum_rows: 32,
            },
        )
        .page
        .unwrap();
        assert_eq!(repeated_filter.rows[0].object_id, topic);
        assert_eq!(
            repository_session_activity(session.session_id, 781, 64)
                .page
                .unwrap()
                .records
                .len(),
            activity_count,
            "cached query must not issue another Git command"
        );
        let path_filtered = repository_session_history_query(
            session.session_id,
            781,
            history.request_id,
            NativeHistoryQueryOptions {
                text: "deep-match.txt".into(),
                search_hash: false,
                search_message: false,
                search_author: false,
                search_path: true,
                offset: 0,
                maximum_rows: 32,
            },
        )
        .page
        .unwrap();
        assert!(path_filtered.rows.iter().any(|row| row.object_id == topic));

        let selected = repository_session_history_select(
            session.session_id,
            781,
            history.request_id,
            NativeHistorySelectionOptions {
                object_id: Some(topic.clone()),
                toggle: false,
                reveal: false,
                focus: true,
                offset: 0,
                maximum_rows: 32,
            },
        );
        assert!(selected.failure.is_none());
        let excluded = repository_session_history_query(
            session.session_id,
            781,
            history.request_id,
            NativeHistoryQueryOptions {
                text: "main marker".into(),
                search_hash: false,
                search_message: true,
                search_author: false,
                search_path: true,
                offset: 0,
                maximum_rows: 32,
            },
        )
        .page
        .unwrap();
        assert!(excluded.selected_filtered_out);
        assert_eq!(excluded.selected_object_ids, vec![topic.clone()]);

        let reset = repository_session_history_query(
            session.session_id,
            781,
            history.request_id,
            NativeHistoryQueryOptions {
                text: String::new(),
                search_hash: true,
                search_message: true,
                search_author: true,
                search_path: true,
                offset: 0,
                maximum_rows: 32,
            },
        )
        .page
        .unwrap();
        let collapsed = repository_session_history_collapse(
            session.session_id,
            781,
            history.request_id,
            merge,
            0,
            32,
        )
        .page
        .unwrap();
        assert!(collapsed.total_rows < reset.total_rows);
        assert!(collapsed.collapsed_commits > 0);
        assert!(collapsed.selected_filtered_out);
        assert_eq!(collapsed.selected_object_ids, vec![topic]);
        assert!(collapsed
            .segments
            .iter()
            .any(|segment| segment.kind == NativeHistorySegmentKind::CollapsedMerge));

        let reflog = repository_session_reflog(session.session_id, 781, 0, 2);
        assert!(reflog.failure.is_none());
        assert_eq!(reflog.page.entries.len(), 2);
        assert!(reflog.page.entries[0]
            .actions
            .contains(&NativeReflogAction::ResetCurrentBranch));
        let git_dir = fixture.0.join(".git");
        let hidden_git_dir = fixture.0.join(".git-hidden");
        fs::rename(&git_dir, &hidden_git_dir).unwrap();
        let failed =
            repository_session_reflog(session.session_id, 781, reflog.page.next_offset.unwrap(), 2);
        fs::rename(&hidden_git_dir, &git_dir).unwrap();
        assert!(failed.failure.is_some());
        assert!(failed.page.retained_after_failure);
        assert_eq!(failed.page.entries, reflog.page.entries);
        assert!(repository_session_close(session.session_id, 781).accepted);
    }

    #[test]
    fn missing_history_metadata_keeps_the_topology_identity_navigable() {
        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"content\n").unwrap();
        assert!(Command::new("git")
            .args(["add", "."])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        assert!(Command::new("git")
            .args(["commit", "-q", "-m", "temporary"])
            .current_dir(&fixture.0)
            .env("GIT_AUTHOR_NAME", "Fixture")
            .env("GIT_AUTHOR_EMAIL", "fixture@example.invalid")
            .env("GIT_COMMITTER_NAME", "Fixture")
            .env("GIT_COMMITTER_EMAIL", "fixture@example.invalid")
            .status()
            .unwrap()
            .success());
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            80,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let preview = repository_session_history_load(session.session_id, 80, false, 8, false)
            .page
            .unwrap();
        let object_id = preview.rows[0].object_id.clone();
        let object_path = fixture
            .0
            .join(".git/objects")
            .join(&object_id[..2])
            .join(&object_id[2..]);
        fs::remove_file(object_path).unwrap();
        let metadata = repository_session_history_metadata(
            session.session_id,
            80,
            preview.request_id,
            vec![object_id.clone()],
        );
        assert_eq!(metadata.rows.len(), 1);
        assert_eq!(metadata.rows[0].object_id, object_id);
        assert_eq!(
            metadata.rows[0].failure,
            Some(NativeHistoryMetadataFailure::Missing)
        );
        let retained =
            repository_session_history_page(session.session_id, 80, preview.request_id, 0, 8)
                .page
                .unwrap();
        assert_eq!(retained.rows.len(), 1);
        assert_eq!(
            retained.rows[0].metadata_failure,
            Some(NativeHistoryMetadataFailure::Missing)
        );
        assert!(repository_session_close(session.session_id, 80).accepted);
    }

    #[test]
    #[ignore = "explicit 100k-commit release/profile proof"]
    fn history_projection_scales_to_100k_with_bounded_transport() {
        let fixture = GitFixture::new();
        fast_import_linear(&fixture.0, 100_000);
        let activity = ActivityStore::default();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            79,
            RepositoryOptions {
                watch: false,
                cache_bytes: 512 * 1024 * 1024,
                activity_sink: Some(activity.sink()),
                activity_id: Some(Arc::new(allocate_activity_id)),
                ..RepositoryOptions::default()
            },
            activity,
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let preview_started = Instant::now();
        let preview = repository_session_history_load(session.session_id, 79, false, 512, false)
            .page
            .unwrap();
        let preview_elapsed = preview_started.elapsed();
        assert_eq!(preview.rows.len(), 512);
        assert!(!preview.topology_complete);
        assert!(preview.payload_bytes < 512 * 1024);
        let complete_started = Instant::now();
        let complete =
            repository_session_history_complete(session.session_id, 79, preview.request_id, 512)
                .page
                .unwrap();
        let complete_elapsed = complete_started.elapsed();
        assert_eq!(complete.total_rows, 100_000);
        assert_eq!(complete.rows.len(), 512);
        assert!(complete.topology_complete);
        assert!(complete.payload_bytes < 512 * 1024);
        let metadata = repository_session_history_metadata(
            session.session_id,
            79,
            complete.request_id,
            complete
                .rows
                .iter()
                .take(256)
                .map(|row| row.object_id.clone())
                .collect(),
        );
        assert!(metadata.failure.is_none());
        assert_eq!(metadata.rows.len(), 256);
        assert_eq!(
            metadata.rows[0].failure,
            Some(NativeHistoryMetadataFailure::ObjectTooLarge)
        );
        let command_count = repository_session_activity(session.session_id, 79, 64)
            .page
            .unwrap()
            .records
            .len();
        let cache_started = Instant::now();
        let cached = repository_session_history_load(session.session_id, 79, true, 1, false)
            .page
            .unwrap();
        let cache_elapsed = cache_started.elapsed();
        assert_eq!(cached.total_rows, 100_000);
        assert_eq!(
            repository_session_activity(session.session_id, 79, 64)
                .page
                .unwrap()
                .records
                .len(),
            command_count,
            "a shared cache hit must not spawn another Git process"
        );
        let events = repository_session_events(session.session_id, 79, 256);
        assert!(
            events.events.iter().any(|event| {
                event.kind == NativeRepositoryEventKind::ReadCompleted && event.cache_hit
            }),
            "events: {:?}",
            events.events
        );
        let diff_rows = complete.rows.iter().skip(300).take(100).collect::<Vec<_>>();
        assert_eq!(diff_rows.len(), 100);
        let load_diff = |row: &NativeHistoryRow| {
            let started = Instant::now();
            let result = repository_session_commit_diff_load(
                session.session_id,
                79,
                NativeCommitDiffOptions {
                    commit: row.object_id.clone(),
                    first_parent: row.parents.first().cloned(),
                    old_path: None,
                    new_path: None,
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: 64,
                    force_text: false,
                },
            );
            assert!(result.failure.is_none(), "{:?}", result.failure);
            assert!(result.page.is_some());
            started.elapsed().as_micros()
        };
        let mut uncached_diff_us = diff_rows
            .iter()
            .map(|row| load_diff(row))
            .collect::<Vec<_>>();
        for row in diff_rows.iter().take(5) {
            let _ = load_diff(row);
        }
        let mut cached_diff_us = diff_rows
            .iter()
            .map(|row| load_diff(row))
            .collect::<Vec<_>>();
        uncached_diff_us.sort_unstable();
        cached_diff_us.sort_unstable();
        // The linear history is the branch filter's worst case: the filter
        // reaches every commit, so reachability and layout cover all rows.
        let filter_started = Instant::now();
        let filtered = repository_session_history_branch_filter(
            session.session_id,
            79,
            cached.request_id,
            vec![b"refs/heads/main".to_vec()],
            0,
            512,
        )
        .page
        .unwrap();
        let filter_elapsed = filter_started.elapsed();
        assert_eq!(filtered.total_rows, 100_000);
        let clear_started = Instant::now();
        let cleared = repository_session_history_branch_filter(
            session.session_id,
            79,
            cached.request_id,
            Vec::new(),
            0,
            512,
        )
        .page
        .unwrap();
        let clear_elapsed = clear_started.elapsed();
        assert_eq!(cleared.total_rows, 100_000);
        assert!(
            filter_elapsed < Duration::from_secs(1) && clear_elapsed < Duration::from_secs(1),
            "branch filter {filter_elapsed:?}, clear {clear_elapsed:?}"
        );
        let uncached_p95_us = uncached_diff_us[94];
        let cached_p95_us = cached_diff_us[94];
        assert!(
            cached_p95_us < 100_000,
            "cached selection-to-diff p95 was {cached_p95_us} us"
        );
        eprintln!(
            "100k history preview_ms={} complete_ms={} cache_ms={} branch_filter_ms={} branch_filter_clear_ms={} lanes={} payload_bytes={} git_activity_records={} uncached_diff_median_us={} uncached_diff_p95_us={} uncached_diff_max_us={} cached_diff_median_us={} cached_diff_p95_us={} cached_diff_max_us={}",
            preview_elapsed.as_millis(),
            complete_elapsed.as_millis(),
            cache_elapsed.as_millis(),
            filter_elapsed.as_millis(),
            clear_elapsed.as_millis(),
            complete.lane_count,
            complete.payload_bytes,
            command_count,
            uncached_diff_us[49],
            uncached_p95_us,
            uncached_diff_us[99],
            cached_diff_us[49],
            cached_p95_us,
            cached_diff_us[99],
        );
        assert!(repository_session_close(session.session_id, 79).accepted);
    }
}
