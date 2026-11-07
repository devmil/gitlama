//! Discarding worktree changes and cleaning untracked files.
#![allow(clippy::wildcard_imports)]
use crate::application::{diff::*, paths::*, session::*, snapshot::*, staging::*};
use crate::diff::selection_for_rows;
use crate::domain::ids::SessionKey;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::*;
use devmil_git::activity::ActivityStatus;
use devmil_git::diff::model::ContextLines;
use devmil_git::diff::model::DiffPath;
use devmil_git::diff::{BytePatchBuilder, PatchConstructionRequest};
use devmil_git::process::{ActivityGitRunner, GitProcessCommand};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// Freezes the exact paths or working-diff rows that an irreversible action may change.
pub fn repository_session_discard_preview(
    session_id: u64,
    generation: u64,
    request: NativeDiscardRequest,
) -> NativeDiscardPreviewResult {
    if request.paths.len() > crate::domain::limits::STAGE_PATHS
        || request.row_ids.len() > crate::domain::limits::STAGE_ROWS
        || request.paths.iter().any(Vec::is_empty)
    {
        return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let (repository, staging) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return discard_preview_failure(kind),
        };
        (
            Arc::clone(&session.repository),
            session
                .staging
                .projection
                .as_ref()
                .map(|value| OwnedStagingProjection {
                    request_id: value.request_id,
                    side: value.side,
                    document: Arc::clone(&value.document),
                    projection: value.projection.clone(),
                    worktree: value.worktree.clone(),
                    git_dir: value.git_dir.clone(),
                    unborn: value.unborn,
                    index_bytes: value.index_bytes.clone(),
                    worktree_states: value.worktree_states.clone(),
                    untracked_paths: value.untracked_paths.clone(),
                    force_text: value.force_text,
                }),
        )
    };
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return discard_preview_failure(NativeRepositoryFailureKind::Discovery);
    };
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    let git_dir = discovered.worktree.git_dir().as_path().to_path_buf();
    let index_bytes = match read_optional_bounded(&git_dir.join("index"), 128 * 1024 * 1024) {
        Ok(value) => value,
        Err(kind) => return discard_preview_failure(kind),
    };
    let (operation, selected_paths, arguments) = match request.scope {
        NativeDiscardScope::Rows => {
            if request.kind != NativeDiscardKind::Discard
                || !request.paths.is_empty()
                || request.row_ids.is_empty()
            {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            let Some(request_id) = request.working_diff_request_id else {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            };
            let Some(staging) = staging else {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            };
            if staging.request_id != request_id || staging.side != NativeStagingSide::Unstaged {
                return discard_preview_failure(NativeRepositoryFailureKind::StaleGeneration);
            }
            if staging.force_text {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            if staging.index_bytes != index_bytes || !staging_preconditions_match(&staging) {
                return discard_preview_failure(NativeRepositoryFailureKind::StaleGeneration);
            }
            let Some(file) = staging.document.files.first() else {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            };
            if staging.document.files.len() != 1 {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            let Some(selection) = selection_for_rows(file, 0, &request.row_ids) else {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            };
            let patch = match BytePatchBuilder.construct_patch(&PatchConstructionRequest {
                file: file.clone(),
                selection,
                context: ContextLines::new(3).expect("constant context is valid"),
                reverse: true,
            }) {
                Ok(value) => value.bytes,
                Err(error) => return discard_preview_failure(map_diff_error_kind(error.kind)),
            };
            (
                OwnedDiscardOperation::ReversePatch(patch),
                staging.worktree_states.keys().cloned().collect::<Vec<_>>(),
                vec![
                    "apply".to_owned(),
                    "--reverse".to_owned(),
                    "--selected-rows".to_owned(),
                ],
            )
        }
        NativeDiscardScope::Files => {
            if request.working_diff_request_id.is_some()
                || request.paths.is_empty()
                || !request.row_ids.is_empty()
            {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            let Some(status) = snapshot.status.as_deref() else {
                return discard_preview_failure(NativeRepositoryFailureKind::Read);
            };
            let requested = request.paths.iter().cloned().collect::<HashSet<_>>();
            if requested.len() != request.paths.len() {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            let mut selected = BTreeSet::new();
            for entry in &status.entries {
                let mapped = map_status_entry(entry);
                let Some(path) = native_identity_bytes(&mapped.path) else {
                    return discard_preview_failure(NativeRepositoryFailureKind::Unsupported);
                };
                if !requested.contains(&path) {
                    continue;
                }
                match (request.kind, mapped.kind) {
                    (NativeDiscardKind::Clean, NativeStatusEntryKind::Untracked) => {
                        selected.insert(path);
                    }
                    (NativeDiscardKind::Discard, NativeStatusEntryKind::Ordinary) => {
                        if mapped.worktree == NativeChangeKind::Unmodified {
                            return discard_preview_failure(
                                NativeRepositoryFailureKind::InvalidOptions,
                            );
                        }
                        selected.insert(path);
                    }
                    (NativeDiscardKind::Discard, NativeStatusEntryKind::Rename) => {
                        selected.insert(path);
                        if let Some(source) = mapped.source {
                            let Some(source) = native_identity_bytes(&source) else {
                                return discard_preview_failure(
                                    NativeRepositoryFailureKind::Unsupported,
                                );
                            };
                            selected.insert(source);
                        }
                    }
                    _ => {
                        return discard_preview_failure(
                            NativeRepositoryFailureKind::InvalidOptions,
                        );
                    }
                }
            }
            if selected.is_empty() || !request.paths.iter().all(|path| selected.contains(path)) {
                return discard_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            let selected = selected.into_iter().collect::<Vec<_>>();
            let operation = match request.kind {
                NativeDiscardKind::Discard => OwnedDiscardOperation::RestoreFiles(selected.clone()),
                NativeDiscardKind::Clean => OwnedDiscardOperation::Clean(selected.clone()),
            };
            let arguments = match request.kind {
                NativeDiscardKind::Discard => vec![
                    "restore".to_owned(),
                    "--worktree".to_owned(),
                    format!("<{} paths>", selected.len()),
                ],
                NativeDiscardKind::Clean => vec![
                    "clean".to_owned(),
                    "-f".to_owned(),
                    "-d".to_owned(),
                    format!("<{} paths>", selected.len()),
                ],
            };
            (operation, selected, arguments)
        }
    };
    let worktree_states = match capture_staging_fingerprints(
        &worktree,
        selected_paths.iter().cloned().collect(),
        false,
    ) {
        Ok(value) => value,
        Err(kind) => return discard_preview_failure(kind),
    };
    let file_count = match request.scope {
        NativeDiscardScope::Files => u64::try_from(request.paths.len()).unwrap_or(u64::MAX),
        NativeDiscardScope::Rows => 1,
    };
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return discard_preview_failure(kind),
    };
    let token = session.discard.issue(OwnedDiscardPreview {
        operation,
        worktree,
        git_dir,
        index_bytes,
        worktree_states,
    });
    NativeDiscardPreviewResult {
        preview: Some(NativeDiscardPreview {
            token,
            kind: request.kind,
            file_count,
            arguments,
        }),
        failure: None,
    }
}

/// Executes one confirmed irreversible action.
pub fn repository_session_discard_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiscardExecutionResult {
    let (repository, activity, preview) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return discard_execution_failure(kind),
        };
        let Some(preview) = session.discard.take(token) else {
            return discard_execution_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            preview,
        )
    };
    if !discard_preconditions_match(&preview) {
        return NativeDiscardExecutionResult {
            state: NativeDiscardExecutionState::Stale,
            failure: None,
        };
    }
    let command = match discard_command(repository.git_executable(), &preview) {
        Ok(value) => value,
        Err(kind) => return discard_execution_failure(kind),
    };
    let drifted = AtomicBool::new(false);
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let outcome = crate::operations::coordinate_mutation(&repository, &cancellation, |_| {
        if !discard_preconditions_match(&preview) {
            drifted.store(true, Ordering::Release);
            return Err(crate::operations::ExecutionFailure::Definite);
        }
        let process = ActivityGitRunner::run(
            command,
            crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change),
            Some(&cancellation),
            &mut publish,
        );
        match process.status {
            ActivityStatus::Succeeded { .. } => Ok(()),
            ActivityStatus::Canceled { .. } => Err(crate::operations::ExecutionFailure::Canceled),
            _ => Err(crate::operations::ExecutionFailure::Definite),
        }
    });
    let outcome = MutationOutcome::from_terminal(outcome);
    discard_result(if !outcome.committed && drifted.load(Ordering::Acquire) {
        MutationOutcome::stale()
    } else if matches!(
        outcome.state,
        MutationState::Canceled | MutationState::Failed
    ) {
        outcome.with_failure(Some(NativeRepositoryFailureKind::Read))
    } else {
        outcome
    })
}

/// The bridge result of a discard: the one place its outcome becomes a state.
pub(crate) fn discard_result(
    outcome: MutationOutcome<NativeRepositoryFailureKind>,
) -> NativeDiscardExecutionResult {
    NativeDiscardExecutionResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeDiscardExecutionState::Completed
            }
            MutationState::ReconciledWithWarning => {
                NativeDiscardExecutionState::ReconciledWithWarning
            }
            MutationState::Stale => NativeDiscardExecutionState::Stale,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Canceled
            | MutationState::Failed => NativeDiscardExecutionState::Failed,
            MutationState::OutcomeUncertain => NativeDiscardExecutionState::OutcomeUncertain,
        },
        failure: outcome.failure.map(|kind| NativeRepositoryFailure { kind }),
    }
}

pub(crate) enum OwnedDiscardOperation {
    RestoreFiles(Vec<Vec<u8>>),
    ReversePatch(Vec<u8>),
    Clean(Vec<Vec<u8>>),
}

pub(crate) struct OwnedDiscardPreview {
    pub(crate) operation: OwnedDiscardOperation,
    pub(crate) worktree: PathBuf,
    pub(crate) git_dir: PathBuf,
    pub(crate) index_bytes: Option<Vec<u8>>,
    pub(crate) worktree_states: HashMap<Vec<u8>, StagingPathState>,
}

pub(crate) const fn discard_preview_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeDiscardPreviewResult {
    NativeDiscardPreviewResult {
        preview: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn discard_execution_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeDiscardExecutionResult {
    NativeDiscardExecutionResult {
        state: NativeDiscardExecutionState::Failed,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn discard_preconditions_match(preview: &OwnedDiscardPreview) -> bool {
    read_optional_bounded(&preview.git_dir.join("index"), 128 * 1024 * 1024)
        .is_ok_and(|current| current == preview.index_bytes)
        && staging_states_match(&preview.worktree, &preview.worktree_states)
}

/// Git path bytes as literal pathspec paths for the shared builders.
pub(crate) fn literal_paths(paths: &[Vec<u8>]) -> Option<Vec<DiffPath>> {
    paths
        .iter()
        .map(|path| devmil_git::commands::index::status_path(path).ok())
        .collect()
}

pub(crate) fn discard_command(
    executable: &std::ffi::OsStr,
    preview: &OwnedDiscardPreview,
) -> Result<GitProcessCommand, NativeRepositoryFailureKind> {
    use devmil_git::commands::index::PathspecForm;
    use devmil_git::commands::restore::{
        apply_patch, clean_paths, discard_worktree_paths, ApplyOptions,
    };
    let invocation = match &preview.operation {
        OwnedDiscardOperation::RestoreFiles(paths) => discard_worktree_paths(
            &literal_paths(paths).ok_or(NativeRepositoryFailureKind::InvalidOptions)?,
            PathspecForm::Arguments,
        )
        .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?,
        OwnedDiscardOperation::ReversePatch(bytes) => apply_patch(
            bytes.clone(),
            ApplyOptions {
                check: false,
                unidiff_zero: true,
            },
        ),
        OwnedDiscardOperation::Clean(paths) => {
            clean_paths(&literal_paths(paths).ok_or(NativeRepositoryFailureKind::InvalidOptions)?)
                .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?
        }
    };
    Ok(invocation
        .process_command(executable, &preview.worktree)
        .redact_output())
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::outcome::MutationTerminalState;

    #[test]
    fn an_uncertain_discard_stays_uncertain() {
        let result = discard_result(MutationOutcome::from_terminal(
            MutationTerminalState::OutcomeUncertain,
        ));
        assert_eq!(result.state, NativeDiscardExecutionState::OutcomeUncertain);
        assert_eq!(result.failure, None);
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{diff::*, discard::*};

    use crate::diff::NativeDiffLayout;
    use crate::diff::DIFF_PAGE_CAPACITY;

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::path::PathBuf;
    use std::process::Command;

    #[test]
    fn mixed_discard_previews_can_clean_then_restore_without_touching_other_content() {
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
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"other base\n").unwrap();
        fs::write(fixture.0.join(".gitignore"), b"ignored.log\n").unwrap();
        git(&["add", "."]);
        git(&[
            "-c",
            "user.name=GitLama Test",
            "-c",
            "user.email=gitlama@example.invalid",
            "commit",
            "-qm",
            "base",
        ]);
        fs::write(fixture.0.join("tracked.txt"), b"staged\n").unwrap();
        git(&["add", "tracked.txt"]);
        fs::write(fixture.0.join("tracked.txt"), b"unstaged\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"keep tracked edit\n").unwrap();
        fs::write(fixture.0.join("new.txt"), b"remove new file\n").unwrap();
        fs::write(fixture.0.join("other-new.txt"), b"keep new file\n").unwrap();
        fs::write(fixture.0.join("ignored.log"), b"keep ignored file\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            9511,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = |kind, path: &[u8]| {
            repository_session_discard_preview(
                session.session_id,
                9511,
                NativeDiscardRequest {
                    kind,
                    scope: NativeDiscardScope::Files,
                    working_diff_request_id: None,
                    paths: vec![path.to_vec()],
                    row_ids: vec![],
                },
            )
            .preview
            .unwrap()
        };
        // Both tokens must be frozen before the user confirms either effect.
        let clean = preview(NativeDiscardKind::Clean, b"new.txt");
        let restore = preview(NativeDiscardKind::Discard, b"tracked.txt");
        let index_before = fs::read(fixture.0.join(".git/index")).unwrap();
        assert_eq!(
            repository_session_discard_execute(session.session_id, 9511, clean.token).state,
            NativeDiscardExecutionState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join(".git/index")).unwrap(),
            index_before
        );
        assert_eq!(
            repository_session_discard_execute(session.session_id, 9511, restore.token).state,
            NativeDiscardExecutionState::Completed
        );
        assert!(!fixture.0.join("new.txt").exists());
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"staged\n"
        );
        assert_eq!(git(&["show", ":tracked.txt"]), b"staged\n");
        assert_eq!(
            fs::read(fixture.0.join("other.txt")).unwrap(),
            b"keep tracked edit\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("other-new.txt")).unwrap(),
            b"keep new file\n"
        );
        assert_eq!(
            fs::read(fixture.0.join("ignored.log")).unwrap(),
            b"keep ignored file\n"
        );
        assert!(repository_session_close(session.session_id, 9511).accepted);
    }

    #[test]
    #[cfg(unix)]
    fn discarding_a_file_named_like_a_glob_keeps_other_changes() {
        // Regression: discard paths are literal pathspecs, so discarding `*.txt` must not
        // discard the unselected `other.txt`.
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
        fs::write(fixture.0.join("*.txt"), b"before\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"before\n").unwrap();
        git(&["add", "--", "*.txt", "other.txt"]);
        git(&[
            "-c",
            "user.name=GitLama Test",
            "-c",
            "user.email=gitlama@example.invalid",
            "commit",
            "-qm",
            "base",
        ]);
        fs::write(fixture.0.join("*.txt"), b"after\n").unwrap();
        fs::write(fixture.0.join("other.txt"), b"after\n").unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            941,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_discard_preview(
            session.session_id,
            941,
            NativeDiscardRequest {
                kind: NativeDiscardKind::Discard,
                scope: NativeDiscardScope::Files,
                working_diff_request_id: None,
                paths: vec![b"*.txt".to_vec()],
                row_ids: vec![],
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_discard_execute(session.session_id, 941, preview.token).state,
            NativeDiscardExecutionState::Completed
        );
        assert_eq!(fs::read(fixture.0.join("*.txt")).unwrap(), b"before\n");
        assert_eq!(fs::read(fixture.0.join("other.txt")).unwrap(), b"after\n");
        assert!(repository_session_close(session.session_id, 941).accepted);
    }

    #[test]
    fn discard_and_clean_freeze_scope_and_preserve_index() {
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
            assert!(
                output.status.success(),
                "git {arguments:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            output.stdout
        };
        fs::write(fixture.0.join(".gitignore"), b"ignored.log\n").unwrap();
        fs::write(fixture.0.join("tracked.txt"), b"one\r\ntwo\r\nthree\r\n").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink("target-one", fixture.0.join("tracked-link")).unwrap();
        #[cfg(unix)]
        git(&["add", ".gitignore", "tracked.txt", "tracked-link"]);
        #[cfg(not(unix))]
        git(&["add", ".gitignore", "tracked.txt"]);
        git(&["commit", "-qm", "base"]);
        fs::write(fixture.0.join("tracked.txt"), b"ONE\r\ntwo\r\nTHREE\r\n").unwrap();
        #[cfg(unix)]
        {
            fs::remove_file(fixture.0.join("tracked-link")).unwrap();
            std::os::unix::fs::symlink("target-two", fixture.0.join("tracked-link")).unwrap();
        }
        fs::create_dir(fixture.0.join("nested")).unwrap();
        fs::write(fixture.0.join("nested/untracked.txt"), b"untracked\n").unwrap();
        fs::write(fixture.0.join("ignored.log"), b"ignored\n").unwrap();

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            940,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);

        let diff = repository_session_working_diff_load(
            session.session_id,
            940,
            NativeWorkingDiffOptions {
                side: NativeStagingSide::Unstaged,
                old_path: Some(b"tracked.txt".to_vec()),
                new_path: Some(b"tracked.txt".to_vec()),
                context_lines: 3,
                whitespace: NativeDiffWhitespace::Preserve,
                layout: NativeDiffLayout::Unified,
                maximum_rows: DIFF_PAGE_CAPACITY as u32,
                force_text: false,
            },
        )
        .page
        .unwrap();
        let first = diff
            .rows
            .iter()
            .filter(|row| row.text == b"one" || row.text == b"ONE")
            .map(|row| row.stable_id.clone())
            .collect::<Vec<_>>();
        let partial = repository_session_discard_preview(
            session.session_id,
            940,
            NativeDiscardRequest {
                kind: NativeDiscardKind::Discard,
                scope: NativeDiscardScope::Rows,
                working_diff_request_id: Some(diff.request_id),
                paths: vec![],
                row_ids: first,
            },
        )
        .preview
        .unwrap();
        assert_eq!(partial.file_count, 1);
        assert_eq!(
            repository_session_discard_execute(session.session_id, 940, partial.token).state,
            NativeDiscardExecutionState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"one\r\ntwo\r\nTHREE\r\n"
        );

        fs::write(fixture.0.join("tracked.txt"), b"staged\r\nbytes\r\n").unwrap();
        git(&["add", "tracked.txt"]);
        fs::write(fixture.0.join("tracked.txt"), b"dirty\r\nbytes\r\n").unwrap();
        let revision = repository_for_session(session.session_id, 940)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, 940).accepted);
        wait_for_new_revision(&session, revision);
        let raced = repository_session_discard_preview(
            session.session_id,
            940,
            NativeDiscardRequest {
                kind: NativeDiscardKind::Discard,
                scope: NativeDiscardScope::Files,
                working_diff_request_id: None,
                paths: vec![b"tracked.txt".to_vec()],
                row_ids: vec![],
            },
        )
        .preview
        .unwrap();
        fs::write(fixture.0.join("tracked.txt"), b"external\r\nedit\r\n").unwrap();
        assert_eq!(
            repository_session_discard_execute(session.session_id, 940, raced.token).state,
            NativeDiscardExecutionState::Stale
        );
        let revision = repository_for_session(session.session_id, 940)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, 940).accepted);
        wait_for_new_revision(&session, revision);
        let tracked = repository_session_discard_preview(
            session.session_id,
            940,
            NativeDiscardRequest {
                kind: NativeDiscardKind::Discard,
                scope: NativeDiscardScope::Files,
                working_diff_request_id: None,
                paths: vec![b"tracked.txt".to_vec()],
                row_ids: vec![],
            },
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_discard_execute(session.session_id, 940, tracked.token).state,
            NativeDiscardExecutionState::Completed
        );
        assert_eq!(
            fs::read(fixture.0.join("tracked.txt")).unwrap(),
            b"staged\r\nbytes\r\n"
        );
        assert_eq!(git(&["show", ":tracked.txt"]), b"staged\r\nbytes\r\n");

        #[cfg(unix)]
        {
            let revision = repository_for_session(session.session_id, 940)
                .unwrap()
                .snapshot()
                .revision;
            assert!(repository_session_refresh(session.session_id, 940).accepted);
            wait_for_new_revision(&session, revision);
            let link = repository_session_discard_preview(
                session.session_id,
                940,
                NativeDiscardRequest {
                    kind: NativeDiscardKind::Discard,
                    scope: NativeDiscardScope::Files,
                    working_diff_request_id: None,
                    paths: vec![b"tracked-link".to_vec()],
                    row_ids: vec![],
                },
            )
            .preview
            .unwrap();
            assert_eq!(
                repository_session_discard_execute(session.session_id, 940, link.token).state,
                NativeDiscardExecutionState::Completed
            );
            assert_eq!(
                fs::read_link(fixture.0.join("tracked-link")).unwrap(),
                PathBuf::from("target-one")
            );
        }

        let revision = repository_for_session(session.session_id, 940)
            .unwrap()
            .snapshot()
            .revision;
        assert!(repository_session_refresh(session.session_id, 940).accepted);
        wait_for_new_revision(&session, revision);
        let clean = repository_session_discard_preview(
            session.session_id,
            940,
            NativeDiscardRequest {
                kind: NativeDiscardKind::Clean,
                scope: NativeDiscardScope::Files,
                working_diff_request_id: None,
                paths: vec![b"nested/untracked.txt".to_vec()],
                row_ids: vec![],
            },
        )
        .preview
        .unwrap();
        assert_eq!(clean.file_count, 1);
        assert_eq!(
            repository_session_discard_execute(session.session_id, 940, clean.token).state,
            NativeDiscardExecutionState::Completed
        );
        assert!(!fixture.0.join("nested/untracked.txt").exists());
        assert_eq!(
            fs::read(fixture.0.join("ignored.log")).unwrap(),
            b"ignored\n"
        );
        assert!(repository_session_close(session.session_id, 940).accepted);
    }
}
