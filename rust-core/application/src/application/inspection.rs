//! Commit inspection, trees, file contents, path and range history, blame and the reflog.
#![allow(clippy::wildcard_imports)]
use crate::application::{session::*, snapshot::*};
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::graph::HISTORY_PAGE_CAPACITY;
use devmil_git::diff::model::{DiffPath, FileChangeKind};
use devmil_git::loading::commit::CommitDiffBase;
use devmil_git::loading::reflog::ReflogQuery;
use devmil_git::loading::working_diff::DiffEndpoint;
use devmil_git::loading::{blame, path_history, tree};
use devmil_git::model::pages::{BlameQuery, PathHistoryQuery, RangeHistoryQuery, TreeQuery};
use devmil_git::types::{HeadState, ObjectId};
use std::sync::Arc;
use std::time::Duration;

/// A session's reflog pages and blame projection.
#[derive(Default)]
pub(crate) struct InspectionState {
    pub(crate) reflog_entries: Vec<NativeReflogEntry>,
    pub(crate) reflog_next_offset: Option<usize>,
    pub(crate) reflog_activity_id: Option<u64>,
    pub(crate) next_request: u64,
    pub(crate) blame: Option<OwnedBlameProjection>,
}

pub(crate) struct OwnedBlameProjection {
    pub(crate) request_id: u64,
    pub(crate) revision: String,
    pub(crate) path: Vec<u8>,
    pub(crate) result: Arc<blame::BlameResult>,
}

/// Loads a bounded reflog page while retaining the last successfully loaded rows on failure.
#[must_use]
pub fn repository_session_reflog(
    session_id: u64,
    generation: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeReflogResult {
    let Ok(offset) = usize::try_from(offset) else {
        return reflog_failure_result(
            session_id,
            generation,
            NativeRepositoryFailureKind::InvalidOptions,
        );
    };
    let query = match ReflogQuery::new(offset, maximum_rows as usize) {
        Ok(value) => value,
        Err(_) => {
            return reflog_failure_result(
                session_id,
                generation,
                NativeRepositoryFailureKind::InvalidOptions,
            )
        }
    };
    let (repository, attached) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return native_reflog_failure(Vec::new(), None, None, kind),
        };
        if offset != 0 && session.inspection.reflog_next_offset != Some(offset) {
            return native_reflog_failure(
                session.inspection.reflog_entries.clone(),
                session.inspection.reflog_next_offset,
                session.inspection.reflog_activity_id,
                NativeRepositoryFailureKind::StaleGeneration,
            );
        }
        let attached = session
            .repository
            .snapshot()
            .repository
            .as_ref()
            .is_some_and(|value| matches!(value.head, HeadState::Attached { .. }));
        (Arc::clone(&session.repository), attached)
    };
    let ticket = match repository.reflog(query) {
        Ok(value) => value,
        Err(error) => {
            return reflog_failure_result(session_id, generation, map_error_kind(error.kind))
        }
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return reflog_failure_result(
            session_id,
            generation,
            NativeRepositoryFailureKind::TimedOut,
        );
    };
    let loaded = match result {
        Ok(value) => value,
        Err(error) => {
            return reflog_failure_result(session_id, generation, map_error_kind(error.kind))
        }
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return native_reflog_failure(Vec::new(), None, None, kind),
    };
    let mut actions = vec![
        NativeReflogAction::InspectCommit,
        NativeReflogAction::CreateBranch,
        NativeReflogAction::CreateTag,
        NativeReflogAction::CherryPick,
    ];
    if attached {
        actions.push(NativeReflogAction::ResetCurrentBranch);
    }
    let entries = loaded
        .entries
        .iter()
        .map(|entry| NativeReflogEntry {
            id: entry.id().hex(),
            reference: entry.reference().to_vec(),
            commit: entry.commit().as_str().to_owned(),
            recorded_at_unix_seconds: entry.recorded_at_unix_seconds(),
            timezone: entry.timezone().to_vec(),
            summary: entry.summary().to_vec(),
            actor_name: entry.actor_name().to_vec(),
            actor_email: entry.actor_email().to_vec(),
            actions: actions.clone(),
        })
        .collect::<Vec<_>>();
    if offset == 0 {
        session.inspection.reflog_entries = entries;
    } else {
        session.inspection.reflog_entries.extend(entries);
    }
    session.inspection.reflog_next_offset = loaded.next_offset;
    session.inspection.reflog_activity_id = Some(loaded.activity_id.get());
    NativeReflogResult {
        page: NativeReflogPage {
            entries: session.inspection.reflog_entries.clone(),
            next_offset: session
                .inspection
                .reflog_next_offset
                .map(|value| value as u64),
            activity_id: session.inspection.reflog_activity_id,
            retained_after_failure: false,
        },
        failure: None,
    }
}

/// Loads byte-preserving commit metadata and its changed-file inventory.
#[must_use]
pub fn repository_session_commit_inspection(
    session_id: u64,
    generation: u64,
    commit: String,
    first_parent: Option<String>,
) -> NativeCommitInspectionResult {
    let commit_id = match ObjectId::parse(commit) {
        Ok(value) => value,
        Err(_) => return inspection_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let base = match first_parent {
        Some(value) => match ObjectId::parse(value) {
            Ok(value) => CommitDiffBase::FirstParent(value),
            Err(_) => return inspection_failure(NativeRepositoryFailureKind::InvalidOptions),
        },
        None => CommitDiffBase::EmptyTree,
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return inspection_failure(kind),
    };
    let detail_ticket = match repository.commit_detail(commit_id.clone()) {
        Ok(value) => value,
        Err(error) => return inspection_failure(map_error_kind(error.kind)),
    };
    let files_ticket = match repository.commit_files(commit_id, base) {
        Ok(value) => value,
        Err(error) => return inspection_failure(map_error_kind(error.kind)),
    };
    let Some(detail) = detail_ticket.recv_timeout(Duration::from_secs(30)) else {
        return inspection_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let Some(files) = files_ticket.recv_timeout(Duration::from_secs(30)) else {
        return inspection_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let detail = match detail {
        Ok(value) => value,
        Err(error) => return inspection_failure(map_error_kind(error.kind)),
    };
    let files = match files {
        Ok(value) => value,
        Err(error) => return inspection_failure(map_error_kind(error.kind)),
    };
    if !session_is_current(session_id, generation) {
        return inspection_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeCommitInspectionResult {
        inspection: Some(NativeCommitInspection {
            detail: native_commit_detail(&detail),
            files: files.iter().map(native_commit_file).collect(),
        }),
        failure: None,
    }
}

/// Loads an ordered commit-detail batch with one shared cached Git invocation.
#[must_use]
pub fn repository_session_commit_details(
    session_id: u64,
    generation: u64,
    commits: Vec<String>,
) -> NativeCommitDetailsResult {
    if commits.is_empty() || commits.len() > 256 {
        return commit_details_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let commits = match commits
        .into_iter()
        .map(ObjectId::parse)
        .collect::<Result<Vec<_>, _>>()
    {
        Ok(value) => value,
        Err(_) => return commit_details_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return commit_details_failure(kind),
    };
    let ticket = match repository.commit_details(commits) {
        Ok(value) => value,
        Err(error) => return commit_details_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return commit_details_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let details = match result {
        Ok(value) => value,
        Err(error) => return commit_details_failure(map_error_kind(error.kind)),
    };
    if !session_is_current(session_id, generation) {
        return commit_details_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeCommitDetailsResult {
        details: details.iter().map(native_commit_detail).collect(),
        failure: None,
    }
}

/// Loads one commit directory through the repository cache and pages its immutable snapshot.
#[must_use]
pub fn repository_session_tree(
    session_id: u64,
    generation: u64,
    commit: String,
    directory: Option<Vec<u8>>,
    offset: u64,
    maximum_rows: u32,
) -> NativeTreeResult {
    if maximum_rows == 0 || maximum_rows > 1_000 || usize::try_from(offset).is_err() {
        return tree_failure_result(NativeRepositoryFailureKind::InvalidOptions);
    }
    let commit_id = match ObjectId::parse(commit.clone()) {
        Ok(value) => value,
        Err(_) => return tree_failure_result(NativeRepositoryFailureKind::InvalidOptions),
    };
    let directory_path = match directory.clone() {
        Some(value) => match DiffPath::from_bytes(value) {
            Ok(value) => Some(value),
            Err(_) => return tree_failure_result(NativeRepositoryFailureKind::InvalidOptions),
        },
        None => None,
    };
    // The repository's bounded read cache retains the snapshot between pages.
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return tree_failure_result(kind),
    };
    let ticket = match repository.tree(TreeQuery {
        commit: commit_id.clone(),
        directory: directory_path,
    }) {
        Ok(value) => value,
        Err(error) => return tree_failure_result(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return tree_failure_result(NativeRepositoryFailureKind::TimedOut);
    };
    let snapshot = match result {
        Ok(value) => value,
        Err(error) => return tree_failure_result(map_error_kind(error.kind)),
    };
    let page = match snapshot.page(usize::try_from(offset).unwrap(), maximum_rows as usize) {
        Ok(value) => value,
        Err(_) => return tree_failure_result(NativeRepositoryFailureKind::InvalidOptions),
    };
    NativeTreeResult {
        page: Some(NativeTreePage {
            commit: commit_id.as_str().to_owned(),
            directory,
            entries: page
                .entries
                .iter()
                .map(|entry| NativeTreeEntry {
                    stable_id: entry.stable_identity(&commit_id),
                    path: entry.path.as_bytes().to_vec(),
                    object_id: entry.object.as_str().to_owned(),
                    kind: match entry.kind {
                        tree::CommitTreeEntryKind::Directory => NativeTreeEntryKind::Directory,
                        tree::CommitTreeEntryKind::File => NativeTreeEntryKind::File,
                        tree::CommitTreeEntryKind::Symlink => NativeTreeEntryKind::Symlink,
                        tree::CommitTreeEntryKind::Submodule => NativeTreeEntryKind::Submodule,
                    },
                    mode: entry.mode,
                    size: entry.size,
                })
                .collect(),
            next_offset: page.next_offset.map(|value| value as u64),
        }),
        failure: None,
    }
}

/// Reads the selected commit's file bytes for the bounded tree preview.
#[must_use]
pub fn repository_session_commit_file_content(
    session_id: u64,
    generation: u64,
    commit: String,
    path: Vec<u8>,
) -> NativeCommitFileContentResult {
    const PREVIEW_LIMIT: usize = 1024 * 1024;
    let failure = |kind| NativeCommitFileContentResult {
        bytes: None,
        failure: Some(NativeRepositoryFailure { kind }),
    };
    let commit = match ObjectId::parse(commit) {
        Ok(value) => value,
        Err(_) => return failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let path = match DiffPath::from_bytes(path) {
        Ok(value) => value,
        Err(_) => return failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return failure(kind),
    };
    let ticket = match repository.content(DiffEndpoint::Commit(commit), path, PREVIEW_LIMIT) {
        Ok(value) => value,
        Err(error) => return failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return failure(NativeRepositoryFailureKind::TimedOut);
    };
    let content = match result {
        Ok(value) => value,
        Err(error) => return failure(map_error_kind(error.kind)),
    };
    if !session_is_current(session_id, generation) {
        return failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    match content.as_ref() {
        Some(content) => NativeCommitFileContentResult {
            bytes: Some(content.bytes.clone()),
            failure: None,
        },
        None => failure(NativeRepositoryFailureKind::MissingObject),
    }
}

#[must_use]
pub fn repository_session_path_history(
    session_id: u64,
    generation: u64,
    options: NativePathHistoryOptions,
) -> NativePathHistoryResult {
    let NativePathHistoryOptions {
        revision,
        path,
        directory,
        offset,
        maximum_rows,
        rename_hops_before,
    } = options;
    if maximum_rows == 0
        || maximum_rows > 500
        || usize::try_from(offset).is_err()
        || usize::try_from(rename_hops_before).is_err()
    {
        return path_history_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let revision = match revision {
        Some(value) => match ObjectId::parse(value) {
            Ok(value) => Some(value),
            Err(_) => return path_history_failure(NativeRepositoryFailureKind::InvalidOptions),
        },
        None => None,
    };
    let path = match DiffPath::from_bytes(path) {
        Ok(value) => value,
        Err(_) => return path_history_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return path_history_failure(kind),
    };
    let ticket = match repository.path_history(PathHistoryQuery {
        revision,
        path,
        kind: if directory {
            path_history::PathHistoryKind::Directory
        } else {
            path_history::PathHistoryKind::File
        },
        offset: usize::try_from(offset).unwrap(),
        limit: maximum_rows as usize,
        rename_hops_before: usize::try_from(rename_hops_before).unwrap(),
    }) {
        Ok(value) => value,
        Err(error) => return path_history_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return path_history_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let loaded = match result {
        Ok(value) => value,
        Err(error) => return path_history_failure(map_error_kind(error.kind)),
    };
    if !session_is_current(session_id, generation) {
        return path_history_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativePathHistoryResult {
        page: Some(NativePathHistoryPage {
            entries: loaded
                .entries
                .iter()
                .map(|entry| NativePathHistoryEntry {
                    stable_id: entry.stable_identity(),
                    commit: entry.commit.as_str().to_owned(),
                    author: entry.author.clone(),
                    author_time: entry.author_time_unix,
                    summary: entry.summary.clone(),
                    path: entry.path.as_bytes().to_vec(),
                    old_path: entry
                        .old_path
                        .as_ref()
                        .map(|value| value.as_bytes().to_vec()),
                })
                .collect(),
            next_offset: loaded.next_offset.map(|value| value as u64),
            rename_hops: loaded.rename_hops as u64,
            incomplete: loaded.incomplete_reason.is_some(),
        }),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_range_history(
    session_id: u64,
    generation: u64,
    revision: String,
    path: Vec<u8>,
    first_line: u32,
    last_line: u32,
    maximum_rows: u32,
) -> NativeRangeHistoryResult {
    let revision = match ObjectId::parse(revision) {
        Ok(value) => value,
        Err(_) => return range_history_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let path = match DiffPath::from_bytes(path) {
        Ok(value) => value,
        Err(_) => return range_history_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return range_history_failure(kind),
    };
    let ticket = match repository.range_history(RangeHistoryQuery {
        revision,
        path,
        first_line,
        last_line,
        limit: maximum_rows as usize,
    }) {
        Ok(value) => value,
        Err(error) => return range_history_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return range_history_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let loaded = match result {
        Ok(value) => value,
        Err(error) => return range_history_failure(map_error_kind(error.kind)),
    };
    NativeRangeHistoryResult {
        entries: loaded
            .entries
            .iter()
            .map(|entry| NativeRangeHistoryEntry {
                stable_id: entry.stable_identity(),
                commit: entry.commit.as_str().to_owned(),
                author: entry.author.clone(),
                author_time: entry.author_time_unix,
                summary: entry.summary.clone(),
            })
            .collect(),
        incomplete: loaded.incomplete,
        failure: None,
    }
}

#[must_use]
pub fn repository_session_blame_load(
    session_id: u64,
    generation: u64,
    options: NativeBlameOptions,
) -> NativeBlameResult {
    let NativeBlameOptions {
        revision,
        path,
        first_line,
        last_line,
        detect_moves,
        detect_copies,
        maximum_rows,
    } = options;
    if maximum_rows == 0 || maximum_rows as usize > HISTORY_PAGE_CAPACITY {
        return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions);
    }
    let revision_id = match ObjectId::parse(revision.clone()) {
        Ok(value) => value,
        Err(_) => return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions),
    };
    let path_value = match DiffPath::from_bytes(path.clone()) {
        Ok(value) => value,
        Err(_) => return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions),
    };
    let range = match (first_line, last_line) {
        (None, None) => None,
        (Some(first), Some(last)) => match blame::BlameRange::new(first, last) {
            Ok(value) => Some(value),
            Err(_) => return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions),
        },
        _ => return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions),
    };
    let (repository, request_id) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return blame_failure_result(kind),
        };
        session.inspection.next_request = session.inspection.next_request.saturating_add(1).max(1);
        (
            Arc::clone(&session.repository),
            session.inspection.next_request,
        )
    };
    let ticket = match repository.blame(BlameQuery {
        revision: blame::BlameRevision::Commit(revision_id),
        path: path_value,
        options: blame::BlameOptions {
            detect_moves,
            detect_copies,
            range,
        },
    }) {
        Ok(value) => value,
        Err(error) => return blame_failure_result(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return blame_failure_result(NativeRepositoryFailureKind::TimedOut);
    };
    let loaded = match result {
        Ok(value) => value,
        Err(error) => return blame_failure_result(map_error_kind(error.kind)),
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return blame_failure_result(kind),
    };
    if session.inspection.next_request != request_id {
        return blame_failure_result(NativeRepositoryFailureKind::StaleGeneration);
    }
    session.inspection.blame = Some(OwnedBlameProjection {
        request_id,
        revision,
        path,
        result: loaded,
    });
    blame_page_for(
        session.inspection.blame.as_ref().unwrap(),
        0,
        maximum_rows as usize,
    )
}

#[must_use]
pub fn repository_session_blame_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeBlameResult {
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > HISTORY_PAGE_CAPACITY
        || usize::try_from(offset).is_err()
    {
        return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return blame_failure_result(kind),
    };
    let Some(projection) = session.inspection.blame.as_ref() else {
        return blame_failure_result(NativeRepositoryFailureKind::InvalidOptions);
    };
    if projection.request_id != request_id {
        return blame_failure_result(NativeRepositoryFailureKind::StaleGeneration);
    }
    blame_page_for(
        projection,
        usize::try_from(offset).unwrap(),
        maximum_rows as usize,
    )
}

pub(crate) fn native_commit_detail(
    value: &devmil_git::loading::commit::CommitDetail,
) -> NativeCommitDetail {
    use sha2::{Digest, Sha256};
    let avatar_hash = value.author_email().map_or_else(String::new, |email| {
        let normalized = String::from_utf8_lossy(email).trim().to_lowercase();
        format!("{:x}", Sha256::digest(normalized.as_bytes()))
    });
    NativeCommitDetail {
        commit: value.commit.as_str().to_owned(),
        tree: value.tree.as_str().to_owned(),
        parents: value
            .parents
            .iter()
            .map(|parent| parent.as_str().to_owned())
            .collect(),
        author: value.author.clone(),
        avatar_hash,
        author_time: value.author_time,
        author_timezone: value.author_timezone.clone(),
        committer: value.committer.clone(),
        committer_time: value.committer_time,
        committer_timezone: value.committer_timezone.clone(),
        message: value.message.clone(),
    }
}

pub(crate) fn native_commit_file(
    value: &devmil_git::loading::commit::CommitFileChange,
) -> NativeCommitFile {
    let (kind, similarity) = match value.kind {
        FileChangeKind::Modified => (NativeFileChangeKind::Modified, None),
        FileChangeKind::Added => (NativeFileChangeKind::Added, None),
        FileChangeKind::Deleted => (NativeFileChangeKind::Deleted, None),
        FileChangeKind::Renamed { similarity } => {
            (NativeFileChangeKind::Renamed, Some(u32::from(similarity)))
        }
        FileChangeKind::Copied { similarity } => {
            (NativeFileChangeKind::Copied, Some(u32::from(similarity)))
        }
        FileChangeKind::ModeChanged => (NativeFileChangeKind::ModeChanged, None),
        FileChangeKind::TypeChanged => (NativeFileChangeKind::TypeChanged, None),
        FileChangeKind::Binary => (NativeFileChangeKind::Binary, None),
        FileChangeKind::Image => (NativeFileChangeKind::Image, None),
        FileChangeKind::Submodule => (NativeFileChangeKind::Submodule, None),
        FileChangeKind::Conflict => (NativeFileChangeKind::Conflict, None),
        FileChangeKind::Untracked => (NativeFileChangeKind::Untracked, None),
    };
    NativeCommitFile {
        old_mode: value.old_mode.value(),
        new_mode: value.new_mode.value(),
        old_object_id: value.old_object.as_ref().map(|id| id.as_str().to_owned()),
        new_object_id: value.new_object.as_ref().map(|id| id.as_str().to_owned()),
        kind,
        similarity,
        old_path: value.old_path.as_bytes().to_vec(),
        new_path: value.new_path.as_bytes().to_vec(),
    }
}

pub(crate) fn blame_page_for(
    projection: &OwnedBlameProjection,
    offset: usize,
    maximum_rows: usize,
) -> NativeBlameResult {
    let start = offset.min(projection.result.lines.len());
    let end = start
        .saturating_add(maximum_rows)
        .min(projection.result.lines.len());
    let rows = projection.result.lines[start..end]
        .iter()
        .map(|line| {
            let span = projection.result.spans.iter().find(|span| {
                line.final_line >= span.first_line && line.final_line <= span.last_line
            });
            NativeBlameRow {
                stable_id: format!("blame:{}:{}", projection.request_id, line.final_line),
                final_line: line.final_line,
                original_line: line.original_line,
                content: line.content.clone(),
                commit: line
                    .attribution
                    .commit
                    .as_ref()
                    .map(|value| value.as_str().to_owned()),
                author: line.attribution.author.clone(),
                author_time: line.attribution.author_time_unix,
                summary: line.attribution.summary.clone(),
                original_path: line.attribution.original_path.as_bytes().to_vec(),
                boundary: line.attribution.boundary,
                span_first_line: span.map_or(line.final_line, |value| value.first_line),
                span_last_line: span.map_or(line.final_line, |value| value.last_line),
            }
        })
        .collect();
    NativeBlameResult {
        page: Some(NativeBlamePage {
            request_id: projection.request_id,
            revision: projection.revision.clone(),
            path: projection.path.clone(),
            total_rows: projection.result.lines.len() as u64,
            offset: start as u64,
            rows,
        }),
        failure: None,
    }
}

pub(crate) const fn inspection_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeCommitInspectionResult {
    NativeCommitInspectionResult {
        inspection: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn commit_details_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeCommitDetailsResult {
    NativeCommitDetailsResult {
        details: Vec::new(),
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn tree_failure_result(kind: NativeRepositoryFailureKind) -> NativeTreeResult {
    NativeTreeResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn path_history_failure(
    kind: NativeRepositoryFailureKind,
) -> NativePathHistoryResult {
    NativePathHistoryResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn range_history_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeRangeHistoryResult {
    NativeRangeHistoryResult {
        entries: Vec::new(),
        incomplete: false,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn blame_failure_result(kind: NativeRepositoryFailureKind) -> NativeBlameResult {
    NativeBlameResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn reflog_failure_result(
    session_id: u64,
    generation: u64,
    kind: NativeRepositoryFailureKind,
) -> NativeReflogResult {
    let sessions = lock_sessions();
    let retained = sessions
        .active
        .get(&session_id)
        .filter(|session| session.generation == generation);
    native_reflog_failure(
        retained.map_or_else(Vec::new, |session| {
            session.inspection.reflog_entries.clone()
        }),
        retained.and_then(|session| session.inspection.reflog_next_offset),
        retained.and_then(|session| session.inspection.reflog_activity_id),
        kind,
    )
}

pub(crate) fn native_reflog_failure(
    entries: Vec<NativeReflogEntry>,
    next_offset: Option<usize>,
    activity_id: Option<u64>,
    kind: NativeRepositoryFailureKind,
) -> NativeReflogResult {
    NativeReflogResult {
        page: NativeReflogPage {
            entries,
            next_offset: next_offset.map(|value| value as u64),
            activity_id,
            retained_after_failure: true,
        },
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::{allocate_activity_id, ActivityStore};
    use crate::test_support::*;

    use crate::application::{diff::*, inspection::*, restore::*};

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;

    use std::process::Command;

    use std::sync::Arc;

    #[test]
    fn commit_tree_path_range_and_blame_reads_are_bounded_and_byte_safe() {
        let fixture = GitFixture::new();
        fs::create_dir_all(fixture.0.join("src")).unwrap();
        fs::write(
            fixture.0.join("src/old.txt"),
            b"one\ntwo\nthree\nfour\nfive\n",
        )
        .unwrap();
        fs::write(fixture.0.join("run.sh"), b"#!/bin/sh\nexit 0\n").unwrap();
        #[cfg(target_os = "linux")]
        {
            use std::os::unix::ffi::OsStringExt;

            fs::write(
                fixture
                    .0
                    .join(std::ffi::OsString::from_vec(vec![b'n', 0x80, b'z'])),
                b"native path\n",
            )
            .unwrap();
        }
        assert!(Command::new("git")
            .args(["add", "."])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        assert!(Command::new("git")
            .args(["update-index", "--chmod=+x", "run.sh"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        assert!(Command::new("git")
            .args(["commit", "-q", "-m", "initial tree"])
            .current_dir(&fixture.0)
            .env("GIT_AUTHOR_NAME", "Inspector")
            .env("GIT_AUTHOR_EMAIL", "inspector@example.invalid")
            .env("GIT_COMMITTER_NAME", "Inspector")
            .env("GIT_COMMITTER_EMAIL", "inspector@example.invalid")
            .status()
            .unwrap()
            .success());
        let first = String::from_utf8(
            Command::new("git")
                .args(["rev-parse", "HEAD"])
                .current_dir(&fixture.0)
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap()
        .trim()
        .to_owned();
        fs::rename(fixture.0.join("src/old.txt"), fixture.0.join("src/new.txt")).unwrap();
        fs::write(
            fixture.0.join("src/new.txt"),
            b"one\ntwo changed\nthree\nfour\nfive\n",
        )
        .unwrap();
        fs::write(fixture.0.join("binary.bin"), [0, 1, 0xff, 2]).unwrap();
        fs::remove_file(fixture.0.join("run.sh")).unwrap();
        assert!(Command::new("git")
            .args(["add", "-A"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());
        assert!(Command::new("git")
            .args(["commit", "-q", "-m", "rename and inspect"])
            .current_dir(&fixture.0)
            .env("GIT_AUTHOR_NAME", "Inspector")
            .env("GIT_AUTHOR_EMAIL", "inspector@example.invalid")
            .env("GIT_COMMITTER_NAME", "Inspector")
            .env("GIT_COMMITTER_EMAIL", "inspector@example.invalid")
            .status()
            .unwrap()
            .success());
        let second = String::from_utf8(
            Command::new("git")
                .args(["rev-parse", "HEAD"])
                .current_dir(&fixture.0)
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap()
        .trim()
        .to_owned();
        let activity = ActivityStore::default();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            782,
            RepositoryOptions {
                watch: false,
                activity_sink: Some(activity.sink()),
                activity_id: Some(Arc::new(allocate_activity_id)),
                ..RepositoryOptions::default()
            },
            activity,
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);

        let before_batch = repository_session_activity(session.session_id, 782, 64)
            .page
            .unwrap()
            .records
            .len();
        let batch_order = vec![second.clone(), first.clone(), second.clone()];
        let details =
            repository_session_commit_details(session.session_id, 782, batch_order.clone());
        assert!(details.failure.is_none());
        assert_eq!(
            details
                .details
                .iter()
                .map(|detail| detail.commit.clone())
                .collect::<Vec<_>>(),
            batch_order
        );
        let after_batch = repository_session_activity(session.session_id, 782, 64)
            .page
            .unwrap()
            .records
            .len();
        assert_eq!(after_batch, before_batch + 1);
        let cached = repository_session_commit_details(
            session.session_id,
            782,
            vec![second.clone(), first.clone(), second.clone()],
        );
        assert!(cached.failure.is_none());
        assert_eq!(
            repository_session_activity(session.session_id, 782, 64)
                .page
                .unwrap()
                .records
                .len(),
            after_batch
        );
        let missing = repository_session_commit_details(
            session.session_id,
            782,
            vec!["0000000000000000000000000000000000000000".into()],
        );
        assert_eq!(
            missing.failure.unwrap().kind,
            NativeRepositoryFailureKind::MissingObject
        );

        let inspection = repository_session_commit_inspection(
            session.session_id,
            782,
            second.clone(),
            Some(first.clone()),
        )
        .inspection
        .unwrap();
        assert_eq!(inspection.detail.commit, second);
        assert_eq!(
            inspection.detail.avatar_hash,
            format!(
                "{:x}",
                <sha2::Sha256 as sha2::Digest>::digest(b"inspector@example.invalid")
            )
        );
        assert_eq!(inspection.detail.parents, vec![first.clone()]);
        assert!(inspection.detail.message.starts_with(b"rename and inspect"));
        assert!(inspection
            .files
            .iter()
            .any(|file| file.new_path == b"src/new.txt"));
        assert!(inspection.files.iter().any(|file| {
            file.kind == NativeFileChangeKind::Deleted && file.old_mode == 0o100_755
        }));

        let root = repository_session_tree(session.session_id, 782, second.clone(), None, 0, 1)
            .page
            .unwrap();
        assert_eq!(root.entries.len(), 1);
        assert!(root.next_offset.is_some());
        #[cfg(target_os = "linux")]
        {
            let complete_root =
                repository_session_tree(session.session_id, 782, second.clone(), None, 0, 32)
                    .page
                    .unwrap();
            assert!(complete_root
                .entries
                .iter()
                .any(|entry| entry.path == [b'n', 0x80, b'z']));
        }
        let src = repository_session_tree(
            session.session_id,
            782,
            second.clone(),
            Some(b"src".to_vec()),
            0,
            32,
        )
        .page
        .unwrap();
        assert!(src.entries.iter().any(|entry| {
            entry.path == b"src/new.txt" && entry.kind == NativeTreeEntryKind::File
        }));

        let first_content = repository_session_commit_file_content(
            session.session_id,
            782,
            first.clone(),
            b"src/old.txt".to_vec(),
        );
        assert_eq!(
            first_content.bytes.as_deref(),
            Some(b"one\ntwo\nthree\nfour\nfive\n".as_slice())
        );
        let second_content = repository_session_commit_file_content(
            session.session_id,
            782,
            second.clone(),
            b"src/new.txt".to_vec(),
        );
        assert_eq!(
            second_content.bytes.as_deref(),
            Some(b"one\ntwo changed\nthree\nfour\nfive\n".as_slice())
        );
        assert_eq!(
            repository_session_commit_file_content(
                session.session_id,
                782,
                second.clone(),
                b"binary.bin".to_vec(),
            )
            .bytes,
            Some(vec![0, 1, 0xff, 2])
        );

        let path = repository_session_path_history(
            session.session_id,
            782,
            NativePathHistoryOptions {
                revision: Some(second.clone()),
                path: b"src/new.txt".to_vec(),
                directory: false,
                offset: 0,
                maximum_rows: 32,
                rename_hops_before: 0,
            },
        )
        .page
        .unwrap();
        assert!(path.entries.len() >= 2);
        assert!(path
            .entries
            .iter()
            .any(|entry| { entry.old_path.as_deref() == Some(b"src/old.txt".as_slice()) }));

        let range = repository_session_range_history(
            session.session_id,
            782,
            second.clone(),
            b"src/new.txt".to_vec(),
            2,
            2,
            32,
        );
        assert!(range.failure.is_none());
        assert!(!range.entries.is_empty());

        let blame = repository_session_blame_load(
            session.session_id,
            782,
            NativeBlameOptions {
                revision: second.clone(),
                path: b"src/new.txt".to_vec(),
                first_line: None,
                last_line: None,
                detect_moves: true,
                detect_copies: true,
                maximum_rows: 2,
            },
        )
        .page
        .unwrap();
        assert_eq!(blame.total_rows, 5);
        assert_eq!(blame.rows.len(), 2);
        assert_eq!(blame.rows[0].final_line, 1);
        let remaining =
            repository_session_blame_page(session.session_id, 782, blame.request_id, 4, 2)
                .page
                .unwrap();
        assert_eq!(remaining.rows.len(), 1);
        assert_eq!(remaining.rows[0].final_line, 5);

        let binary_preview = repository_session_restore_preview(
            session.session_id,
            782,
            second.clone(),
            b"binary.bin".to_vec(),
            1024,
        )
        .preview
        .unwrap();
        assert_eq!(binary_preview.source_bytes, [0, 1, 0xff, 2]);
        assert_eq!(
            binary_preview.current_bytes.as_deref(),
            Some([0, 1, 0xff, 2].as_slice())
        );
        let image_content = repository_session_image_diff(
            session.session_id,
            782,
            None,
            second.clone(),
            b"binary.bin".to_vec(),
            b"binary.bin".to_vec(),
            1024,
        );
        assert!(image_content.failure.is_none());
        assert!(image_content.old.is_none());
        assert!(image_content.new.is_none());
        assert_eq!(
            image_content.decode_failure,
            Some(crate::image_decoder::NativeImageDecodeFailureKind::Unsupported)
        );

        fs::write(fixture.0.join("src/new.txt"), b"local edit\n").unwrap();
        let stale_preview = repository_session_restore_preview(
            session.session_id,
            782,
            first.clone(),
            b"src/old.txt".to_vec(),
            1024,
        )
        .preview
        .unwrap();
        fs::write(fixture.0.join("src/old.txt"), b"newer local edit\n").unwrap();
        let stale = repository_session_restore_file(session.session_id, 782, stale_preview.token);
        assert_eq!(stale.state, NativeRestoreState::Stale);
        assert_eq!(
            fs::read(fixture.0.join("src/old.txt")).unwrap(),
            b"newer local edit\n"
        );

        let executable_preview = repository_session_restore_preview(
            session.session_id,
            782,
            first,
            b"run.sh".to_vec(),
            1024,
        )
        .preview
        .unwrap();
        assert!(executable_preview.current_bytes.is_none());
        let restored =
            repository_session_restore_file(session.session_id, 782, executable_preview.token);
        assert_eq!(restored.state, NativeRestoreState::Restored);
        assert_eq!(
            fs::read(fixture.0.join("run.sh")).unwrap(),
            b"#!/bin/sh\nexit 0\n"
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;

            let mode = fs::metadata(fixture.0.join("run.sh"))
                .unwrap()
                .permissions()
                .mode();
            assert_ne!(mode & 0o111, 0);
        }
        assert!(repository_session_close(session.session_id, 782).accepted);
    }
}
