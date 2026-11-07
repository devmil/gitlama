//! Commit and working-tree diffs, their pages, searches and hunks, images and change sources.
#![allow(clippy::wildcard_imports)]
use crate::application::{patch::*, paths::*, session::*, snapshot::*, staging::*};
use crate::diff::NativeDiffLayout;
use crate::diff::{selection_patch, DiffProjection, DIFF_PAGE_CAPACITY};
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::preview_store::SessionPreviews;
use devmil_git::diff::model::DiffPath;
use devmil_git::diff::model::{ContextLines, DiffFileId, DiffLayout, DiffWhitespacePolicy};
use devmil_git::loading::commit::{CommitDiffBase, CommitDiffOptions, CommitDiffScope};
use devmil_git::loading::working_diff::{DiffEndpoint, WorkingDiffKey, WorkingDiffLimits};
use devmil_git::status::StatusEntry;
use devmil_git::types::{HeadState, ObjectId};
use devmil_git::RepositoryErrorKind;
use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

/// A session's commit diff projection and the change sides another computer reads.
pub(crate) struct DiffState {
    pub(crate) next_request: u64,
    pub(crate) projection: Option<crate::diff::DiffProjection>,
    pub(crate) document: Option<Arc<devmil_git::diff::model::DiffDocument>>,
    /// Change sides whose bytes another computer reads.
    pub(crate) change_sources: SessionPreviews<ChangeSourceBytes>,
}

impl Default for DiffState {
    fn default() -> Self {
        Self {
            next_request: 0,
            projection: None,
            document: None,
            change_sources: SessionPreviews::new(PATCH_PREVIEW_CAPACITY),
        }
    }
}

/// Loads a committed diff through the shared repository cache and publishes one bounded page.
#[must_use]
pub fn repository_session_commit_diff_load(
    session_id: u64,
    generation: u64,
    options: NativeCommitDiffOptions,
) -> NativeDiffResult {
    let NativeCommitDiffOptions {
        commit,
        first_parent,
        old_path,
        new_path,
        context_lines,
        whitespace,
        layout,
        maximum_rows,
        force_text,
    } = options;
    if maximum_rows == 0 || maximum_rows as usize > DIFF_PAGE_CAPACITY {
        return diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let commit = match ObjectId::parse(commit) {
        Ok(value) => value,
        Err(_) => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let base = match first_parent {
        Some(parent) => match ObjectId::parse(parent) {
            Ok(parent) => CommitDiffBase::FirstParent(parent),
            Err(_) => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
        },
        None => CommitDiffBase::EmptyTree,
    };
    let scope = match (old_path, new_path) {
        (None, None) => CommitDiffScope::All,
        (Some(old_path), Some(new_path)) => {
            let old_path = match DiffPath::from_bytes(old_path) {
                Ok(value) => value,
                Err(_) => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
            };
            let new_path = match DiffPath::from_bytes(new_path) {
                Ok(value) => value,
                Err(_) => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
            };
            CommitDiffScope::File { old_path, new_path }
        }
        _ => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let context = match u16::try_from(context_lines)
        .ok()
        .and_then(|value| ContextLines::new(value).ok())
    {
        Some(value) => value,
        None => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let (repository, request_id) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return diff_failure(kind),
        };
        session.diff.next_request = session.diff.next_request.saturating_add(1).max(1);
        (Arc::clone(&session.repository), session.diff.next_request)
    };
    let ticket = match repository.commit_diff(
        commit,
        base,
        CommitDiffOptions {
            scope,
            context,
            whitespace: match whitespace {
                NativeDiffWhitespace::Preserve => DiffWhitespacePolicy::Preserve,
                NativeDiffWhitespace::IgnoreAll => DiffWhitespacePolicy::IgnoreAll,
                NativeDiffWhitespace::IgnoreAmount => DiffWhitespacePolicy::IgnoreAmount,
                NativeDiffWhitespace::IgnoreEndOfLine => DiffWhitespacePolicy::IgnoreEndOfLine,
            },
            layout: match layout {
                NativeDiffLayout::Unified => DiffLayout::Unified,
                NativeDiffLayout::SideBySide => DiffLayout::SideBySide,
            },
            force_text,
        },
    ) {
        Ok(ticket) => ticket,
        Err(error) => return diff_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return diff_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let document = match result {
        Ok(value) => value,
        Err(error) => return diff_failure(map_error_kind(error.kind)),
    };
    // Syntax work for the projection this read replaces is obsolete.
    crate::diff_syntax::retire_view(
        session_id,
        crate::diff_syntax::NativeDiffSyntaxOrigin::Committed,
        request_id,
    );
    let projection = DiffProjection::from_document(request_id, &document);
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return diff_failure(kind),
    };
    if session.diff.next_request != request_id {
        return diff_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    session.diff.projection = Some(projection);
    session.diff.document = Some(document);
    NativeDiffResult {
        page: Some(
            session
                .diff
                .projection
                .as_ref()
                .unwrap()
                .page(0, maximum_rows as usize),
        ),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_diff_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeDiffResult {
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > DIFF_PAGE_CAPACITY
        || usize::try_from(offset).is_err()
    {
        return diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return diff_failure(kind),
    };
    let Some(diff) = session.diff.projection.as_ref() else {
        return diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    if diff.request_id != request_id {
        return diff_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeDiffResult {
        page: Some(diff.page(usize::try_from(offset).unwrap(), maximum_rows as usize)),
        failure: None,
    }
}

pub(crate) fn selection_patch_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeDiffSelectionPatchResult {
    NativeDiffSelectionPatchResult {
        patch: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

/// Builds a forward unified patch for the change lines among [row_ids] of the
/// current commit diff or, when [working] is set, the current working diff.
/// Context rows are accepted and stay context. `patch` is `None` when the
/// selection holds no change line.
#[must_use]
pub fn repository_session_diff_selection_patch(
    session_id: u64,
    generation: u64,
    request_id: u64,
    working: bool,
    row_ids: Vec<String>,
) -> NativeDiffSelectionPatchResult {
    if request_id == 0 || row_ids.is_empty() || row_ids.len() > crate::domain::limits::STAGE_ROWS {
        return selection_patch_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let document = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return selection_patch_failure(kind),
        };
        let current = if working {
            session
                .staging
                .projection
                .as_ref()
                .map(|value| (value.request_id, Arc::clone(&value.document)))
        } else {
            session
                .diff
                .projection
                .as_ref()
                .map(|value| value.request_id)
                .zip(session.diff.document.clone())
        };
        let Some((current_request, document)) = current else {
            return selection_patch_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        if current_request != request_id {
            return selection_patch_failure(NativeRepositoryFailureKind::StaleGeneration);
        }
        document
    };
    match selection_patch(&document, &row_ids).map_err(|error| map_diff_error_kind(error.kind)) {
        Ok(patch) => NativeDiffSelectionPatchResult {
            patch: (!patch.is_empty()).then_some(patch),
            failure: None,
        },
        Err(kind) => selection_patch_failure(kind),
    }
}

#[must_use]
pub fn repository_session_diff_search(
    session_id: u64,
    generation: u64,
    request_id: u64,
    query: Vec<u8>,
    case_sensitive: bool,
    maximum_matches: u32,
) -> NativeDiffSearchResult {
    if request_id == 0
        || query.is_empty()
        || query.len() > 1024
        || maximum_matches == 0
        || maximum_matches > 10_000
    {
        return diff_search_failure(request_id, NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return diff_search_failure(request_id, kind),
    };
    let Some(diff) = session.diff.projection.as_ref() else {
        return diff_search_failure(request_id, NativeRepositoryFailureKind::InvalidOptions);
    };
    if diff.request_id != request_id {
        return diff_search_failure(request_id, NativeRepositoryFailureKind::StaleGeneration);
    }
    let (matches, total_matches, truncated) =
        diff.search(&query, case_sensitive, maximum_matches as usize);
    NativeDiffSearchResult {
        request_id,
        matches,
        total_matches,
        truncated,
        failure: None,
    }
}

#[must_use]
pub fn repository_session_diff_hunks(
    session_id: u64,
    generation: u64,
    request_id: u64,
    maximum_positions: u32,
) -> NativeDiffPositionsResult {
    if request_id == 0 || maximum_positions == 0 || maximum_positions > 10_000 {
        return diff_positions_failure(request_id, NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return diff_positions_failure(request_id, kind),
    };
    let Some(diff) = session.diff.projection.as_ref() else {
        return diff_positions_failure(request_id, NativeRepositoryFailureKind::InvalidOptions);
    };
    if diff.request_id != request_id {
        return diff_positions_failure(request_id, NativeRepositoryFailureKind::StaleGeneration);
    }
    let (positions, total_positions, truncated) = diff.hunk_positions(maximum_positions as usize);
    NativeDiffPositionsResult {
        request_id,
        positions,
        total_positions,
        truncated,
        failure: None,
    }
}

/// How long one working-diff call waits before reporting `TimedOut`. The read keeps running
/// and the next identical call resumes it.
const WORKING_DIFF_WAIT: Duration = Duration::from_secs(15);

#[cfg(test)]
thread_local! {
    /// Lets a test on this thread wait less than [`WORKING_DIFF_WAIT`].
    pub(crate) static WORKING_DIFF_WAIT_OVERRIDE: std::cell::Cell<Option<Duration>> =
        const { std::cell::Cell::new(None) };
}

fn working_diff_wait() -> Duration {
    #[cfg(test)]
    if let Some(wait) = WORKING_DIFF_WAIT_OVERRIDE.with(std::cell::Cell::get) {
        return wait;
    }
    WORKING_DIFF_WAIT
}

/// Loads an authoritative staged or unstaged diff and retains exact index/worktree preconditions.
#[must_use]
pub fn repository_session_working_diff_load(
    session_id: u64,
    generation: u64,
    options: NativeWorkingDiffOptions,
) -> NativeDiffResult {
    if options.maximum_rows == 0 || options.maximum_rows as usize > DIFF_PAGE_CAPACITY {
        return diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let file = match (options.old_path, options.new_path) {
        (None, None) => None,
        (old_path, new_path) if old_path.is_some() || new_path.is_some() => {
            let old_path = match old_path.map(DiffPath::from_bytes).transpose() {
                Ok(value) => value,
                Err(_) => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
            };
            let new_path = match new_path.map(DiffPath::from_bytes).transpose() {
                Ok(value) => value,
                Err(_) => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
            };
            Some(DiffFileId { old_path, new_path })
        }
        _ => unreachable!(),
    };
    let (repository, request_id, discovered, untracked_paths) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return diff_failure(kind),
        };
        let snapshot = session.repository.snapshot();
        let Some(discovered) = snapshot.repository.clone() else {
            return diff_failure(NativeRepositoryFailureKind::Discovery);
        };
        let untracked_paths = if options.side == NativeStagingSide::Unstaged && file.is_none() {
            snapshot.status.as_deref().map(|status| {
                status
                    .entries
                    .iter()
                    .filter(|entry| matches!(entry, StatusEntry::Untracked(_)))
                    .filter_map(|entry| {
                        let identity = crate::domain::path_identity::native_path_identity(
                            entry.path().as_path(),
                        );
                        native_identity_bytes(&identity)
                    })
                    .collect::<HashSet<_>>()
            })
        } else {
            None
        };
        session.staging.next_request = session.staging.next_request.saturating_add(1).max(1);
        (
            Arc::clone(&session.repository),
            session.staging.next_request,
            discovered,
            untracked_paths,
        )
    };
    let unborn = matches!(discovered.head, HeadState::Unborn { .. });
    let base = match options.side {
        NativeStagingSide::Unstaged => DiffEndpoint::Index,
        NativeStagingSide::Staged if unborn => DiffEndpoint::EmptyTree,
        NativeStagingSide::Staged => DiffEndpoint::Head,
    };
    let target = match options.side {
        NativeStagingSide::Unstaged => DiffEndpoint::WorkingTree,
        NativeStagingSide::Staged => DiffEndpoint::Index,
    };
    let context = match u16::try_from(options.context_lines)
        .ok()
        .and_then(|value| ContextLines::new(value).ok())
    {
        Some(value) => value,
        None => return diff_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let key = WorkingDiffKey {
        worktree: discovered.worktree.clone(),
        base,
        target,
        file,
        layout: match options.layout {
            NativeDiffLayout::Unified => DiffLayout::Unified,
            NativeDiffLayout::SideBySide => DiffLayout::SideBySide,
        },
        context,
        whitespace: match options.whitespace {
            NativeDiffWhitespace::Preserve => DiffWhitespacePolicy::Preserve,
            NativeDiffWhitespace::IgnoreAll => DiffWhitespacePolicy::IgnoreAll,
            NativeDiffWhitespace::IgnoreAmount => DiffWhitespacePolicy::IgnoreAmount,
            NativeDiffWhitespace::IgnoreEndOfLine => DiffWhitespacePolicy::IgnoreEndOfLine,
        },
        force_text: options.force_text,
    };
    // A retry of a diff that outlasted its last wait resumes the same Git read.
    let resumed = {
        let mut sessions = lock_sessions();
        match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => match session.staging.pending_diff.take() {
                Some((pending, ticket)) if pending == key => Some(ticket),
                _ => None,
            },
            Err(kind) => return diff_failure(kind),
        }
    };
    let ticket = match resumed {
        Some(ticket) => ticket,
        None => match repository.working_diff(key.clone(), WorkingDiffLimits::default()) {
            Ok(value) => value,
            Err(error) => return diff_failure(map_error_kind(error.kind)),
        },
    };
    let Some(result) = ticket.recv_timeout(working_diff_wait()) else {
        let mut sessions = lock_sessions();
        if let Ok(session) = sessions.session_mut(SessionKey::new(session_id, generation)) {
            if session.staging.pending_diff.is_none() {
                session.staging.pending_diff = Some((key, ticket));
            }
        }
        return diff_failure(NativeRepositoryFailureKind::TimedOut);
    };
    let result = match result {
        Ok(value) => value,
        Err(error) => return diff_failure(map_diff_error_kind(error.kind)),
    };
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    let git_dir = discovered.worktree.git_dir().as_path().to_path_buf();
    let index_bytes = match read_optional_bounded(&git_dir.join("index"), 128 * 1024 * 1024) {
        Ok(value) => value,
        Err(kind) => return diff_failure(kind),
    };
    let mut paths = HashSet::new();
    if options.side == NativeStagingSide::Unstaged {
        for file in &result.document.files {
            for path in [&file.id.old_path, &file.id.new_path].into_iter().flatten() {
                paths.insert(path.as_bytes().to_vec());
            }
        }
        if let Some(untracked_paths) = &untracked_paths {
            paths.extend(untracked_paths.iter().cloned());
        }
    }
    let worktree_states = match capture_staging_fingerprints(&worktree, paths, true) {
        Ok(value) => value,
        Err(kind) => return diff_failure(kind),
    };
    crate::diff_syntax::retire_view(
        session_id,
        crate::diff_syntax::NativeDiffSyntaxOrigin::Working,
        request_id,
    );
    let projection = DiffProjection::from_document(request_id, &result.document);
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return diff_failure(kind),
    };
    if session.staging.next_request != request_id {
        return diff_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    session.staging.projection = Some(OwnedStagingProjection {
        request_id,
        side: options.side,
        document: Arc::new(result.document.clone()),
        projection,
        worktree,
        git_dir,
        unborn,
        index_bytes,
        worktree_states,
        untracked_paths: untracked_paths.unwrap_or_default(),
        force_text: options.force_text,
    });
    NativeDiffResult {
        page: Some(
            session
                .staging
                .projection
                .as_ref()
                .unwrap()
                .projection
                .page(0, options.maximum_rows as usize),
        ),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_working_diff_page(
    session_id: u64,
    generation: u64,
    request_id: u64,
    offset: u64,
    maximum_rows: u32,
) -> NativeDiffResult {
    if request_id == 0
        || maximum_rows == 0
        || maximum_rows as usize > DIFF_PAGE_CAPACITY
        || usize::try_from(offset).is_err()
    {
        return diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return diff_failure(kind),
    };
    let Some(staging) = session.staging.projection.as_ref() else {
        return diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    if staging.request_id != request_id {
        return diff_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeDiffResult {
        page: Some(
            staging
                .projection
                .page(usize::try_from(offset).unwrap(), maximum_rows as usize),
        ),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_image_diff(
    session_id: u64,
    generation: u64,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Vec<u8>,
    new_path: Vec<u8>,
    byte_limit: u32,
) -> NativeImageDiffResult {
    match commit_change_sides(
        old_revision,
        new_revision,
        Some(old_path),
        Some(new_path),
        byte_limit,
        IMAGE_BYTES,
    ) {
        Ok((old, new)) => load_image_diff(session_id, generation, old, new, byte_limit),
        Err(kind) => image_diff_failure(kind),
    }
}

pub(crate) type ImageSide = Option<(DiffEndpoint, DiffPath)>;

/// Any malformed part of an image request.
#[allow(clippy::needless_pass_by_value)]
pub(crate) fn invalid<E>(_: E) -> NativeRepositoryFailureKind {
    NativeRepositoryFailureKind::InvalidOptions
}
pub(crate) type ChangeSourceBytes = (Option<Arc<Vec<u8>>>, Option<Arc<Vec<u8>>>);

/// Largest image side decoded: as many bytes as an image diff reads.
pub(crate) const IMAGE_BYTES: u32 = 8 * 1024 * 1024;

/// Largest side of a change kept for another computer: as many bytes as an external diff
/// materializes.
pub(crate) const CHANGE_SOURCE_BYTES: u32 = 64 * 1024 * 1024;

/// The two sides of a file changed between commits; a missing path has no side.
pub(crate) fn commit_change_sides(
    old_revision: Option<String>,
    new_revision: String,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
    maximum_bytes: u32,
) -> Result<(ImageSide, ImageSide), NativeRepositoryFailureKind> {
    if byte_limit == 0 || byte_limit > maximum_bytes || (old_path.is_none() && new_path.is_none()) {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    let old_revision = old_revision
        .map(ObjectId::parse)
        .transpose()
        .map_err(invalid)?;
    let new_revision = ObjectId::parse(new_revision).map_err(invalid)?;
    let old_path = old_path
        .map(DiffPath::from_bytes)
        .transpose()
        .map_err(invalid)?;
    let new_path = new_path
        .map(DiffPath::from_bytes)
        .transpose()
        .map_err(invalid)?;
    let old_endpoint = old_revision.map_or(DiffEndpoint::EmptyTree, DiffEndpoint::Commit);
    Ok((
        old_path.map(|path| (old_endpoint, path)),
        new_path.map(|path| (DiffEndpoint::Commit(new_revision), path)),
    ))
}

/// The two sides of one staged or unstaged working-tree change.
pub(crate) fn working_change_sides(
    side: NativeStagingSide,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
    maximum_bytes: u32,
) -> Result<(ImageSide, ImageSide), NativeRepositoryFailureKind> {
    if byte_limit == 0 || byte_limit > maximum_bytes || (old_path.is_none() && new_path.is_none()) {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    let old_path = old_path
        .map(DiffPath::from_bytes)
        .transpose()
        .map_err(invalid)?;
    let new_path = new_path
        .map(DiffPath::from_bytes)
        .transpose()
        .map_err(invalid)?;
    let (old_endpoint, new_endpoint) = match side {
        NativeStagingSide::Staged => (DiffEndpoint::Head, DiffEndpoint::Index),
        NativeStagingSide::Unstaged => (DiffEndpoint::Index, DiffEndpoint::WorkingTree),
    };
    Ok((
        old_path.map(|path| (old_endpoint, path)),
        new_path.map(|path| (new_endpoint, path)),
    ))
}

/// Decodes the image sides of one staged or unstaged working-tree change.
///
/// A missing path loads no image for that side, so additions and deletions
/// compare against an empty side.
#[must_use]
pub fn repository_session_working_image_diff(
    session_id: u64,
    generation: u64,
    side: NativeStagingSide,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
) -> NativeImageDiffResult {
    match working_change_sides(side, old_path, new_path, byte_limit, IMAGE_BYTES) {
        Ok((old, new)) => load_image_diff(session_id, generation, old, new, byte_limit),
        Err(kind) => image_diff_failure(kind),
    }
}

pub(crate) fn load_image_diff(
    session_id: u64,
    generation: u64,
    old: ImageSide,
    new: ImageSide,
    byte_limit: u32,
) -> NativeImageDiffResult {
    let (old, new) = match load_image_bytes(session_id, generation, old, new, byte_limit) {
        Ok(value) => value,
        Err(kind) => return image_diff_failure(kind),
    };
    let decoded = crate::image_decoder::decode_pair(session_id, old, new);
    if !session_is_current(session_id, generation) {
        return image_diff_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeImageDiffResult {
        old: decoded.old,
        new: decoded.new,
        decode_failure: decoded.failure,
        failure: None,
    }
}

/// The stored bytes of both image sides, at most `byte_limit` each.
pub(crate) type ImageBytes = (Option<Vec<u8>>, Option<Vec<u8>>);

pub(crate) fn load_image_bytes(
    session_id: u64,
    generation: u64,
    old: ImageSide,
    new: ImageSide,
    byte_limit: u32,
) -> Result<ImageBytes, NativeRepositoryFailureKind> {
    let repository = repository_for_session(session_id, generation)?;
    let request = |side: Option<(DiffEndpoint, DiffPath)>| match side {
        Some((endpoint, path)) => repository
            .content(endpoint, path, byte_limit as usize)
            .map(Some),
        None => Ok(None),
    };
    let old_ticket = request(old).map_err(|error| map_error_kind(error.kind))?;
    let new_ticket = request(new).map_err(|error| map_error_kind(error.kind))?;
    let old = receive_image_content(old_ticket)?;
    let new = receive_image_content(new_ticket)?;
    if !session_is_current(session_id, generation) {
        return Err(NativeRepositoryFailureKind::StaleGeneration);
    }
    Ok((
        old.as_ref().as_ref().map(|value| value.bytes.clone()),
        new.as_ref().as_ref().map(|value| value.bytes.clone()),
    ))
}

/// Bytes of a change side one source page carries; a page stays within one wire frame.
pub(crate) const CHANGE_SOURCE_PAGE_BYTES: usize = 1024 * 1024;

/// Keeps the stored bytes of both sides of a file changed between commits for another computer
/// that decodes, compares or renders them itself;
/// [`repository_session_change_source_page`] returns them. A missing path has no side.
#[must_use]
pub fn repository_session_change_source(
    session_id: u64,
    generation: u64,
    old_revision: Option<String>,
    new_revision: String,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
) -> NativeChangeSourceResult {
    match commit_change_sides(
        old_revision,
        new_revision,
        old_path,
        new_path,
        byte_limit,
        CHANGE_SOURCE_BYTES,
    ) {
        Ok((old, new)) => keep_change_source(session_id, generation, old, new, byte_limit),
        Err(kind) => change_source_failure(kind),
    }
}

/// Keeps the stored bytes of both sides of one staged or unstaged working-tree change for
/// another computer.
#[must_use]
pub fn repository_session_working_change_source(
    session_id: u64,
    generation: u64,
    side: NativeStagingSide,
    old_path: Option<Vec<u8>>,
    new_path: Option<Vec<u8>>,
    byte_limit: u32,
) -> NativeChangeSourceResult {
    match working_change_sides(side, old_path, new_path, byte_limit, CHANGE_SOURCE_BYTES) {
        Ok((old, new)) => keep_change_source(session_id, generation, old, new, byte_limit),
        Err(kind) => change_source_failure(kind),
    }
}

pub(crate) fn keep_change_source(
    session_id: u64,
    generation: u64,
    old: ImageSide,
    new: ImageSide,
    byte_limit: u32,
) -> NativeChangeSourceResult {
    let (old, new) = match load_image_bytes(session_id, generation, old, new, byte_limit) {
        Ok(value) => value,
        Err(kind) => return change_source_failure(kind),
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return change_source_failure(kind),
    };
    let old_bytes = old.as_ref().map(|bytes| bytes.len() as u64);
    let new_bytes = new.as_ref().map(|bytes| bytes.len() as u64);
    let token = session
        .diff
        .change_sources
        .issue((old.map(Arc::new), new.map(Arc::new)));
    NativeChangeSourceResult {
        token,
        old_bytes,
        new_bytes,
        failure: None,
    }
}

/// Bytes of a kept change side from `offset`, at most one page.
#[must_use]
pub fn repository_session_change_source_page(
    session_id: u64,
    generation: u64,
    token: u64,
    new_side: bool,
    offset: u64,
) -> NativeChangeSourcePage {
    let page_failure = |kind| NativeChangeSourcePage {
        bytes: Vec::new(),
        failure: Some(NativeRepositoryFailure { kind }),
    };
    let sessions = lock_sessions();
    let session = match sessions.session(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return page_failure(kind),
    };
    let Some((old, new)) = session.diff.change_sources.get(token) else {
        return page_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let Some(bytes) = (if new_side { new } else { old }) else {
        return page_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let Some(start) = usize::try_from(offset)
        .ok()
        .filter(|start| *start <= bytes.len())
    else {
        return page_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let end = bytes.len().min(start + CHANGE_SOURCE_PAGE_BYTES);
    NativeChangeSourcePage {
        bytes: bytes[start..end].to_vec(),
        failure: None,
    }
}

/// Decodes image bytes read from a repository on another computer, as an image diff of a local
/// repository decodes its own.
#[must_use]
pub fn image_decode_pair(old: Option<Vec<u8>>, new: Option<Vec<u8>>) -> NativeImageDiffResult {
    if old
        .as_ref()
        .is_some_and(|bytes| bytes.len() > 8 * 1024 * 1024)
        || new
            .as_ref()
            .is_some_and(|bytes| bytes.len() > 8 * 1024 * 1024)
    {
        return image_diff_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    // Decodes that belong to no local session share session 0 for cancellation.
    let decoded = crate::image_decoder::decode_pair(0, old, new);
    NativeImageDiffResult {
        old: decoded.old,
        new: decoded.new,
        decode_failure: decoded.failure,
        failure: None,
    }
}

pub(crate) const fn change_source_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeChangeSourceResult {
    NativeChangeSourceResult {
        token: 0,
        old_bytes: None,
        new_bytes: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn diff_failure(kind: NativeRepositoryFailureKind) -> NativeDiffResult {
    NativeDiffResult {
        page: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn diff_search_failure(
    request_id: u64,
    kind: NativeRepositoryFailureKind,
) -> NativeDiffSearchResult {
    NativeDiffSearchResult {
        request_id,
        matches: Vec::new(),
        total_matches: 0,
        truncated: false,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn diff_positions_failure(
    request_id: u64,
    kind: NativeRepositoryFailureKind,
) -> NativeDiffPositionsResult {
    NativeDiffPositionsResult {
        request_id,
        positions: Vec::new(),
        total_positions: 0,
        truncated: false,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) type ImageContent = Option<devmil_git::loading::content::ContentBytes>;

pub(crate) fn receive_image_content(
    ticket: Option<devmil_git::model::ReadTicket<ImageContent>>,
) -> Result<Arc<ImageContent>, NativeRepositoryFailureKind> {
    let Some(ticket) = ticket else {
        return Ok(Arc::new(None));
    };
    match ticket.recv_timeout(Duration::from_secs(30)) {
        None => Err(NativeRepositoryFailureKind::TimedOut),
        Some(Ok(value)) => Ok(value),
        Some(Err(error)) if error.kind == RepositoryErrorKind::MissingObject => Ok(Arc::new(None)),
        Some(Err(error)) => Err(map_error_kind(error.kind)),
    }
}

pub(crate) const fn image_diff_failure(kind: NativeRepositoryFailureKind) -> NativeImageDiffResult {
    NativeImageDiffResult {
        old: None,
        new: None,
        decode_failure: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn map_diff_error_kind(
    kind: devmil_git::diff::DiffErrorKind,
) -> NativeRepositoryFailureKind {
    match kind {
        devmil_git::diff::DiffErrorKind::Canceled => NativeRepositoryFailureKind::Canceled,
        devmil_git::diff::DiffErrorKind::TooLarge => NativeRepositoryFailureKind::TooLarge,
        devmil_git::diff::DiffErrorKind::UnsupportedBinary => {
            NativeRepositoryFailureKind::Unsupported
        }
        devmil_git::diff::DiffErrorKind::InvalidSelection => {
            NativeRepositoryFailureKind::InvalidOptions
        }
        devmil_git::diff::DiffErrorKind::GitFailed
        | devmil_git::diff::DiffErrorKind::MalformedMetadata
        | devmil_git::diff::DiffErrorKind::MalformedPatch => {
            NativeRepositoryFailureKind::InvalidOutput
        }
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::application::{diff::*, diff_renderers::*};

    use crate::diff::DIFF_PAGE_CAPACITY;
    use crate::diff::{NativeDiffLayout, NativeDiffRowKind};
    #[allow(unused_imports)] // Only some platforms' tests use all of them.
    use crate::diff_renderer::{
        NativeDiffRendererDefinition, NativeDiffRendererFailureKind, NativeDiffRendererState,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;

    use std::process::Command;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::time::Duration;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::time::Instant;

    #[cfg(unix)]
    #[test]
    fn a_timed_out_working_diff_resumes_the_same_git_read_on_retry() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
        };
        fs::write(fixture.0.join("a.txt"), b"before\n").unwrap();
        git(&["add", "a.txt"]);
        git(&["commit", "-qm", "base"]);
        fs::write(fixture.0.join("a.txt"), b"after\n").unwrap();
        let gate = fixture.0.with_extension("gate");
        fs::create_dir_all(&gate).unwrap();
        let real = Command::new("sh")
            .args(["-c", "command -v git"])
            .output()
            .unwrap();
        let real = String::from_utf8(real.stdout).unwrap().trim().to_owned();
        let wrapper = gate.join("git");
        fs::write(
            &wrapper,
            format!(
                "#!/bin/sh\ncase \" $* \" in\n*' --patch '*) echo run >> '{dir}/patches'; while [ ! -f '{dir}/release' ]; do sleep 0.02; done;;\nesac\nexec '{real}' \"$@\"\n",
                dir = gate.display(),
            ),
        )
        .unwrap();
        fs::set_permissions(&wrapper, fs::Permissions::from_mode(0o755)).unwrap();
        let generation = 928;
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            generation,
            RepositoryOptions {
                watch: false,
                git_executable: wrapper.into_os_string(),
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        WORKING_DIFF_WAIT_OVERRIDE.with(|wait| wait.set(Some(Duration::from_millis(300))));
        let load = || {
            repository_session_working_diff_load(
                session.session_id,
                generation,
                NativeWorkingDiffOptions {
                    side: NativeStagingSide::Unstaged,
                    old_path: Some(b"a.txt".to_vec()),
                    new_path: Some(b"a.txt".to_vec()),
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: DIFF_PAGE_CAPACITY as u32,
                    force_text: false,
                },
            )
        };
        let patches = || {
            fs::read_to_string(gate.join("patches"))
                .unwrap_or_default()
                .lines()
                .count()
        };
        let timed_out = || {
            load()
                .failure
                .is_some_and(|failure| failure.kind == NativeRepositoryFailureKind::TimedOut)
        };
        assert!(timed_out());
        assert!(timed_out());
        assert_eq!(patches(), 1, "a retry must not start another diff");
        fs::write(gate.join("release"), b"").unwrap();
        let loaded = load();
        assert!(loaded.failure.is_none(), "{:?}", loaded.failure);
        assert!(loaded
            .page
            .unwrap()
            .rows
            .iter()
            .any(|row| row.kind == NativeDiffRowKind::Addition && row.text == b"after"));
        assert_eq!(patches(), 1);
        let _ = repository_session_close(session.session_id, generation);
        let _ = fs::remove_dir_all(&gate);
    }

    #[test]
    fn staged_rename_and_untracked_replacement_have_independent_diff_identities() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        fs::write(
            fixture.0.join("entrypoint.dart"),
            b"native implementation\n",
        )
        .unwrap();
        git(&["add", "entrypoint.dart"]);
        git(&["commit", "-qm", "base"]);
        git(&["mv", "entrypoint.dart", "entrypoint_native.dart"]);
        fs::write(
            fixture.0.join("entrypoint.dart"),
            b"export native or web implementation;\n",
        )
        .unwrap();
        fs::write(
            fixture.0.join("entrypoint_web.dart"),
            b"web implementation\n",
        )
        .unwrap();
        fs::write(
            fixture.0.join("entrypoint_native.dart"),
            b"native implementation\nunstaged edit\n",
        )
        .unwrap();
        let generation = 927;
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            generation,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let load = |side, old: Option<&[u8]>, new: Option<&[u8]>| {
            let loaded = repository_session_working_diff_load(
                session.session_id,
                generation,
                NativeWorkingDiffOptions {
                    side,
                    old_path: old.map(<[u8]>::to_vec),
                    new_path: new.map(<[u8]>::to_vec),
                    context_lines: 3,
                    whitespace: NativeDiffWhitespace::Preserve,
                    layout: NativeDiffLayout::Unified,
                    maximum_rows: DIFF_PAGE_CAPACITY as u32,
                    force_text: false,
                },
            );
            assert!(
                loaded.failure.is_none(),
                "{side:?} {old:?} {new:?}: {:?}",
                loaded.failure
            );
            loaded.page.unwrap()
        };
        for (path, text) in [
            (
                b"entrypoint.dart".as_slice(),
                b"export native or web implementation;".as_slice(),
            ),
            (
                b"entrypoint_web.dart".as_slice(),
                b"web implementation".as_slice(),
            ),
        ] {
            let page = load(NativeStagingSide::Unstaged, None, Some(path));
            assert!(page
                .rows
                .iter()
                .any(|row| row.kind == NativeDiffRowKind::Addition && row.text == text));
        }
        let rename = load(
            NativeStagingSide::Staged,
            Some(b"entrypoint.dart"),
            Some(b"entrypoint_native.dart"),
        );
        assert!(rename
            .rows
            .iter()
            .any(|row| row.file_kind == Some(crate::diff::NativeDiffFileKind::Renamed)));
        let modified = load(
            NativeStagingSide::Unstaged,
            Some(b"entrypoint_native.dart"),
            Some(b"entrypoint_native.dart"),
        );
        assert!(modified
            .rows
            .iter()
            .any(|row| row.kind == NativeDiffRowKind::Addition && row.text == b"unstaged edit"));
        assert_eq!(
            git(&["show", ":entrypoint_native.dart"]),
            b"native implementation\n"
        );
        assert!(repository_session_close(session.session_id, generation).accepted);
    }

    #[test]
    fn untracked_svg_preview_reads_and_renders_repository_content() {
        let fixture = GitFixture::new();
        let svg = include_bytes!("../../test-fixtures/images/wallpaper.svg");
        fs::write(fixture.0.join("wallpaper.svg"), svg).unwrap();
        let generation = 928;
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            generation,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let loaded = repository_session_working_image_diff(
            session.session_id,
            generation,
            NativeStagingSide::Unstaged,
            None,
            Some(b"wallpaper.svg".to_vec()),
            8 * 1024 * 1024,
        );
        assert!(loaded.failure.is_none());
        assert!(loaded.decode_failure.is_none());
        assert!(loaded.old.is_none());
        let image = loaded.new.unwrap();
        assert_eq!((image.width, image.height), (24, 24));
        assert!(image.rgba.chunks_exact(4).any(|pixel| pixel[3] > 0));

        // For another computer: the stored bytes, read by page and decoded there alike.
        let source = repository_session_working_change_source(
            session.session_id,
            generation,
            NativeStagingSide::Unstaged,
            None,
            Some(b"wallpaper.svg".to_vec()),
            8 * 1024 * 1024,
        );
        assert!(source.failure.is_none());
        assert_eq!(source.old_bytes, None);
        assert_eq!(source.new_bytes, Some(svg.len() as u64));
        let page = repository_session_change_source_page(
            session.session_id,
            generation,
            source.token,
            true,
            0,
        );
        assert_eq!(page.bytes, svg);
        assert!(repository_session_change_source_page(
            session.session_id,
            generation,
            source.token,
            false,
            0,
        )
        .failure
        .is_some());
        let decoded = image_decode_pair(None, Some(page.bytes));
        assert!(decoded.failure.is_none() && decoded.decode_failure.is_none());
        assert_eq!(decoded.new.unwrap(), image);
        assert!(repository_session_close(session.session_id, generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn renderer_failure_cannot_change_staging_selection_identity() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
            output.stdout
        };
        fs::write(fixture.0.join("file.txt"), b"one\ntwo\nthree\n").unwrap();
        git(&["add", "file.txt"]);
        git(&["commit", "-qm", "base"]);
        fs::write(fixture.0.join("file.txt"), b"ONE\ntwo\nTHREE\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            923,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let page = repository_session_working_diff_load(
            session.session_id,
            923,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: Some(b"file.txt".to_vec()),
                new_path: Some(b"file.txt".to_vec()),
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        let selected = page
            .rows
            .iter()
            .filter(|row| row.text == b"one" || row.text == b"ONE")
            .map(|row| row.stable_id.clone())
            .collect::<Vec<_>>();
        assert_eq!(selected.len(), 2);

        let executable = fixture.0.join("renderer.sh");
        fs::write(
            &executable,
            b"#!/bin/sh\nmode=''\nfor argument do mode=$argument; done\ncase \"$mode\" in\n--gitlama-capabilities) printf 'gitlama-diff-renderer-v1\\nmedia=text/plain\\n' ;;\n--gitlama-render=text/plain) exit 23 ;;\nesac\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&executable).unwrap().permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(&executable, permissions).unwrap();
        let preview = repository_session_diff_renderer_preview(
            session.session_id,
            923,
            page.request_id,
            NativeDiffRendererDefinition {
                id: "crashing".to_owned(),
                title: "Crashing renderer".to_owned(),
                executable: crate::domain::path_identity::native_path_identity(&executable),
                arguments: Vec::new(),
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_diff_renderer_execute(session.session_id, 923, preview.token).state,
            NativeDiffRendererState::Pending
        );
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            let result =
                repository_session_diff_renderer_poll(session.session_id, 923, preview.token);
            if result.state != NativeDiffRendererState::Pending {
                assert_eq!(result.state, NativeDiffRendererState::Fallback);
                assert_eq!(
                    result.failure.unwrap().kind,
                    NativeDiffRendererFailureKind::ProcessFailed
                );
                break;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        }

        // A repository on another computer: its host returns the same input, and a renderer
        // runs on it here without a local repository.
        let input =
            repository_session_diff_renderer_input(session.session_id, 923, page.request_id)
                .input
                .unwrap();
        assert_eq!(input.len() as u64, preview.input_bytes);
        assert_eq!(
            repository_session_diff_renderer_input(session.session_id, 923, page.request_id + 99)
                .failure
                .unwrap()
                .kind,
            NativeDiffRendererFailureKind::Stale
        );
        let echo = fixture.0.join("echo-renderer.sh");
        fs::write(
            &echo,
            b"#!/bin/sh\nmode=''\nfor argument do mode=$argument; done\ncase \"$mode\" in\n--gitlama-capabilities) printf 'gitlama-diff-renderer-v1\\nmedia=text/plain\\n' ;;\n--gitlama-render=text/plain) cat ;;\nesac\n",
        )
        .unwrap();
        let mut echo_permissions = fs::metadata(&echo).unwrap().permissions();
        echo_permissions.set_mode(0o700);
        fs::set_permissions(&echo, echo_permissions).unwrap();
        let echo_definition = NativeDiffRendererDefinition {
            id: "echo".to_owned(),
            title: "Echo renderer".to_owned(),
            executable: crate::domain::path_identity::native_path_identity(&echo),
            arguments: Vec::new(),
        };
        assert!(diff_renderer_detached_validate(echo_definition.clone())
            .preview
            .is_some());
        let detached = diff_renderer_detached_preview(input.clone(), echo_definition)
            .preview
            .unwrap();
        assert_eq!(
            diff_renderer_detached_execute(detached.token).state,
            NativeDiffRendererState::Pending
        );
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            let result = diff_renderer_detached_poll(detached.token);
            if result.state != NativeDiffRendererState::Pending {
                assert_eq!(result.state, NativeDiffRendererState::Ready);
                assert_eq!(result.text.unwrap().as_bytes(), input.as_slice());
                break;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        }

        let staged = repository_session_staging_execute(
            session.session_id,
            923,
            NativeStagingRequest {
                request_id: page.request_id,
                side: NativeStagingSide::Unstaged,
                scope: NativeStagingScope::Rows,
                paths: Vec::new(),
                row_ids: selected,
            },
        );
        assert_eq!(staged.state, NativeStagingExecutionState::Completed);
        assert_eq!(git(&["show", ":file.txt"]), b"ONE\ntwo\nthree\n");
        assert!(repository_session_close(session.session_id, 923).accepted);
    }
}
