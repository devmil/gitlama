//! Commit tools, previews and commits with untranslated Git diagnostics.
#![allow(clippy::wildcard_imports)]
use crate::activity::allocate_activity_id;
use crate::activity::ActivityStore;
use crate::application::{paths::*, session::*, snapshot::*};
use crate::domain::ids::SessionKey;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::*;
use devmil_git::activity::ActivityStatus;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::types::HeadState;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

pub(crate) use crate::git_probe::run_published_probe;

pub(crate) use devmil_git::commands::commit::CommitTrace;

/// Loads bounded recent messages and the configured commit template through the shared worker.
pub fn repository_session_commit_tools(
    session_id: u64,
    generation: u64,
) -> NativeCommitToolsResult {
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return commit_tools_failure(kind),
    };
    let ticket = match repository.commit_tools() {
        Ok(value) => value,
        Err(error) => return commit_tools_failure(map_error_kind(error.kind)),
    };
    let Some(result) = ticket.recv_timeout(Duration::from_secs(30)) else {
        return commit_tools_failure(NativeRepositoryFailureKind::TimedOut);
    };
    match result {
        Ok(tools) => NativeCommitToolsResult {
            tools: Some(NativeCommitTools {
                recent: tools
                    .recent
                    .iter()
                    .map(|message| NativeRecentCommitMessage {
                        object_id: message.object.as_str().to_owned(),
                        subject: message.subject.clone(),
                        description: message.description.clone(),
                    })
                    .collect(),
                template: tools.template.clone(),
            }),
            failure: None,
        },
        Err(error) => commit_tools_failure(map_error_kind(error.kind)),
    }
}

/// Validates a commit request and retains the exact HEAD and index accepted by the user.
pub fn repository_session_commit_preview(
    session_id: u64,
    generation: u64,
    request: NativeCommitRequest,
) -> NativeCommitPreviewResult {
    if !valid_commit_request(&request) {
        return commit_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let (repository, activity) = {
        let sessions = lock_sessions();
        let session = match sessions.session(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return commit_preview_failure(kind),
        };
        (Arc::clone(&session.repository), session.activity.clone())
    };
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return commit_preview_failure(NativeRepositoryFailureKind::Discovery);
    };
    let worktree = discovered.worktree.worktree_root().as_path().to_path_buf();
    let git_dir = discovered.worktree.git_dir().as_path().to_path_buf();
    let expected_head = match current_head_identity(&activity, &worktree) {
        Some(value) => value,
        None => return commit_preview_failure(NativeRepositoryFailureKind::Read),
    };
    if request.amend && expected_head.is_none() {
        return commit_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    let index_bytes = match read_optional_bounded(&git_dir.join("index"), 128 * 1024 * 1024) {
        Ok(value) => value,
        Err(kind) => return commit_preview_failure(kind),
    };
    if !request.amend {
        let staged = run_published_probe(&activity, |executor| {
            devmil_git::probes::has_changes(
                repository.git_executable(),
                &worktree,
                devmil_git::probes::ChangeScope::Staged,
                executor,
            )
        });
        match staged {
            Ok(true) => {}
            Ok(false) => {
                return commit_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
            }
            Err(devmil_git::probes::ProbeFailure::MissingGit) => {
                return commit_preview_failure(NativeRepositoryFailureKind::MissingGit);
            }
            Err(_) => return commit_preview_failure(NativeRepositoryFailureKind::Read),
        }
    }
    if request.author.is_none() {
        let author = run_commit_probe(&activity, &worktree, ["var", "GIT_AUTHOR_IDENT"], 16 * 1024);
        if !matches!(author, ActivityStatus::Succeeded { .. }) {
            return commit_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
        }
    }
    let mut warnings = Vec::new();
    if request.amend {
        let Some(Some(head)) = expected_head
            .as_ref()
            .map(|head| devmil_git::types::ObjectId::parse(head.clone()).ok())
        else {
            return commit_preview_failure(NativeRepositoryFailureKind::Read);
        };
        match run_published_probe(&activity, |executor| {
            devmil_git::probes::is_published(
                repository.git_executable(),
                &worktree,
                &head,
                executor,
            )
        }) {
            Ok(true) => warnings.push(NativeCommitWarning::PublishedAmend),
            Ok(false) => {}
            Err(_) => return commit_preview_failure(NativeRepositoryFailureKind::Read),
        }
    }
    // The preview shows the invocation execution runs; the message is not part of the display.
    let Ok(invocation) = commit_invocation(&request, Vec::new()) else {
        return commit_preview_failure(NativeRepositoryFailureKind::InvalidOptions);
    };
    let arguments = invocation.display_arguments();
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return commit_preview_failure(kind),
    };
    let token = session.commit.issue(OwnedCommitPreview {
        request,
        expected_head,
        index_bytes,
        worktree,
        git_dir,
    });
    NativeCommitPreviewResult {
        preview: Some(NativeCommitPreview {
            token,
            warnings,
            arguments,
        }),
        failure: None,
    }
}

/// Executes one accepted commit. A requested push is a separate terminal outcome.
pub fn repository_session_commit_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeCommitExecutionResult {
    let (repository, activity, preview) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return commit_execution_failure(kind),
        };
        let Some(preview) = session.commit.take(token) else {
            return commit_execution_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            preview,
        )
    };
    if !commit_preconditions_match(&activity, &preview) {
        return NativeCommitExecutionResult {
            state: NativeCommitExecutionState::Stale,
            commit: None,
            failure_kind: None,
            exit_code: None,
            output: Vec::new(),
            failure: None,
        };
    }
    let message = commit_message(&preview.request);
    let Ok(trace) = CommitTrace::create(&std::env::temp_dir()) else {
        return commit_execution_failure(NativeRepositoryFailureKind::Read);
    };
    let command = match commit_command(
        repository.git_executable(),
        &preview.worktree,
        &preview.request,
        message,
        &trace,
    ) {
        Ok(value) => value,
        Err(()) => return commit_execution_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let cancellation = AtomicBool::new(false);
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let mut process_failure = None;
    let outcome = crate::operations::coordinate_mutation(&repository, &cancellation, |_| {
        if !commit_preconditions_match(&activity, &preview) {
            return Err(crate::operations::ExecutionFailure::Definite);
        }
        let mut process = ActivityGitRunner::run_private(
            command,
            crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change),
            Some(&cancellation),
            &mut publish,
        );
        match process.activity.status {
            ActivityStatus::Succeeded { .. } => Ok(()),
            ActivityStatus::Canceled { .. } => Err(crate::operations::ExecutionFailure::Canceled),
            ActivityStatus::Failed { exit_code } => {
                let stderr = process.stderr.take_bytes();
                let traced = trace.failure();
                process_failure = Some((
                    traced.map_or_else(
                        || commit_failure_kind(&preview.request, &stderr),
                        |failure| map_commit_failure_kind(failure.kind),
                    ),
                    traced.and_then(|failure| failure.exit_code).or(exit_code),
                    commit_failure_output(&stderr, &preview.worktree),
                ));
                Err(crate::operations::ExecutionFailure::Definite)
            }
            _ => Err(crate::operations::ExecutionFailure::Definite),
        }
    });
    let outcome = MutationOutcome::<NativeRepositoryFailureKind>::from_terminal(outcome);
    match outcome.state {
        MutationState::Canceled | MutationState::Failed => {
            if let Some((failure_kind, exit_code, output)) = process_failure {
                return NativeCommitExecutionResult {
                    state: NativeCommitExecutionState::Failed,
                    commit: None,
                    failure_kind: Some(failure_kind),
                    exit_code,
                    output,
                    failure: None,
                };
            }
            return commit_execution_failure(NativeRepositoryFailureKind::Read);
        }
        MutationState::OutcomeUncertain => return commit_result(outcome, None),
        _ => {}
    }
    let commit = repository
        .snapshot()
        .repository
        .as_ref()
        .and_then(head_identity);
    commit_result(outcome, commit)
}

/// The bridge result of a commit without Git diagnostics: the one place its outcome becomes a
/// state.
pub(crate) fn commit_result(
    outcome: MutationOutcome<NativeRepositoryFailureKind>,
    commit: Option<String>,
) -> NativeCommitExecutionResult {
    NativeCommitExecutionResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeCommitExecutionState::Completed
            }
            MutationState::ReconciledWithWarning => {
                NativeCommitExecutionState::ReconciledWithWarning
            }
            MutationState::Stale => NativeCommitExecutionState::Stale,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Canceled
            | MutationState::Failed => NativeCommitExecutionState::Failed,
            MutationState::OutcomeUncertain => NativeCommitExecutionState::OutcomeUncertain,
        },
        commit,
        failure_kind: None,
        exit_code: None,
        output: Vec::new(),
        failure: outcome.failure.map(|kind| NativeRepositoryFailure { kind }),
    }
}

pub(crate) struct OwnedCommitPreview {
    pub(crate) request: NativeCommitRequest,
    pub(crate) expected_head: Option<String>,
    pub(crate) index_bytes: Option<Vec<u8>>,
    pub(crate) worktree: PathBuf,
    pub(crate) git_dir: PathBuf,
}

pub(crate) const fn commit_tools_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeCommitToolsResult {
    NativeCommitToolsResult {
        tools: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn commit_preview_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeCommitPreviewResult {
    NativeCommitPreviewResult {
        preview: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) const fn commit_execution_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeCommitExecutionResult {
    NativeCommitExecutionResult {
        state: NativeCommitExecutionState::Failed,
        commit: None,
        failure_kind: None,
        exit_code: None,
        output: Vec::new(),
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

/// Runs a small read in `worktree` and publishes it as an activity; returns its status.
pub(crate) fn run_commit_probe<const N: usize>(
    activity: &ActivityStore,
    worktree: &Path,
    arguments: [&str; N],
    output_limit: usize,
) -> ActivityStatus {
    let command = GitProcessCommand::git("git")
        .current_dir(worktree)
        .args(arguments.into_iter().map(ProcessArgument::visible))
        .output_limit(output_limit)
        .redact_output();
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    ActivityGitRunner::run_private(command, allocate_activity_id(), None, &mut publish)
        .activity
        .status
}

/// `HEAD`'s object: `Some(None)` when it is unborn, `None` when it could not be read.
pub(crate) fn current_head_identity(
    activity: &ActivityStore,
    worktree: &Path,
) -> Option<Option<String>> {
    run_published_probe(activity, |executor| {
        devmil_git::probes::resolve(std::ffi::OsStr::new("git"), worktree, "HEAD", executor)
    })
    .ok()
    .map(|object| object.map(|object| object.as_str().to_owned()))
}

pub(crate) fn valid_commit_request(request: &NativeCommitRequest) -> bool {
    crate::commit_rules::valid_commit_message(
        &request.subject,
        &request.description,
        &request.coauthors,
        request.author.as_deref(),
    )
}

/// The shared `git commit` request for a GitLama commit; the message always arrives on stdin.
pub(crate) fn shared_commit_request(
    request: &NativeCommitRequest,
) -> devmil_git::commands::commit::CommitRequest {
    use devmil_git::commands::commit::{CommitRequest, CommitSigning};
    CommitRequest {
        amend: request.amend,
        no_verify: request.skip_hooks,
        signing: match request.signing {
            NativeCommitSigning::UseGitConfiguration => CommitSigning::UseGitConfiguration,
            NativeCommitSigning::Require => CommitSigning::Require,
            NativeCommitSigning::Disable => CommitSigning::Disable,
        },
        sign_off: request.sign_off,
        author: request.author.clone(),
        ..CommitRequest::default()
    }
}

/// The exact commit invocation, shared by the preview display and execution.
pub(crate) fn commit_invocation(
    request: &NativeCommitRequest,
    message: Vec<u8>,
) -> Result<devmil_git::commands::invocation::GitInvocation, ()> {
    devmil_git::commands::commit::commit_invocation_with_message(
        &shared_commit_request(request),
        message,
    )
    .map_err(|_| ())
}

pub(crate) fn commit_message(request: &NativeCommitRequest) -> Vec<u8> {
    let mut message = request.subject.as_bytes().to_vec();
    if !request.description.is_empty() {
        message.extend_from_slice(b"\n\n");
        message.extend_from_slice(request.description.as_bytes());
    }
    for coauthor in &request.coauthors {
        message.extend_from_slice(b"\n\nCo-authored-by: ");
        message.extend_from_slice(coauthor.trim().as_bytes());
    }
    message.push(b'\n');
    message
}

pub(crate) fn commit_command(
    executable: &std::ffi::OsStr,
    worktree: &Path,
    request: &NativeCommitRequest,
    message: Vec<u8>,
    trace: &CommitTrace,
) -> Result<GitProcessCommand, ()> {
    Ok(trace
        .invocation(commit_invocation(request, message)?)
        .process_command(executable, worktree)
        .output_limit(64 * 1024)
        .redact_output())
}

pub(crate) const fn map_commit_failure_kind(
    kind: devmil_git::commands::commit::CommitFailureKind,
) -> NativeCommitFailureKind {
    use devmil_git::commands::commit::CommitFailureKind;
    match kind {
        CommitFailureKind::Hook => NativeCommitFailureKind::Hook,
        CommitFailureKind::Signing => NativeCommitFailureKind::Signing,
        CommitFailureKind::Other => NativeCommitFailureKind::Other,
    }
}

/// Classifies a failed commit without trace evidence from its `LC_ALL=C` diagnostics.
pub(crate) fn commit_failure_kind(
    request: &NativeCommitRequest,
    stderr: &[u8],
) -> NativeCommitFailureKind {
    map_commit_failure_kind(devmil_git::commands::commit::classify_commit_stderr(
        stderr,
        request.skip_hooks,
    ))
}

pub(crate) fn commit_failure_output(stderr: &[u8], worktree: &Path) -> Vec<String> {
    let mut diagnostic = String::from_utf8_lossy(stderr).into_owned();
    let root = worktree.to_string_lossy();
    if !root.is_empty() {
        diagnostic = diagnostic.replace(root.as_ref(), "<repository>");
    }
    if let Some(home) = std::env::var_os("HOME") {
        let home = home.to_string_lossy();
        if !home.is_empty() {
            diagnostic = diagnostic.replace(home.as_ref(), "<home>");
        }
    }
    diagnostic
        .lines()
        .take(40)
        .map(|line| {
            line.chars()
                .filter(|character| !character.is_control() || *character == '\t')
                .take(240)
                .collect::<String>()
                .trim_end()
                .to_owned()
        })
        .filter(|line| !line.is_empty())
        .collect()
}

pub(crate) fn commit_preconditions_match(
    activity: &ActivityStore,
    preview: &OwnedCommitPreview,
) -> bool {
    current_head_identity(activity, &preview.worktree) == Some(preview.expected_head.clone())
        && read_optional_bounded(&preview.git_dir.join("index"), 128 * 1024 * 1024)
            .is_ok_and(|current| current == preview.index_bytes)
}

pub(crate) fn head_identity(
    repository: &devmil_git::repository::DiscoveredRepository,
) -> Option<String> {
    match &repository.head {
        HeadState::Attached { target, .. } | HeadState::Detached { target } => {
            Some(target.as_str().to_owned())
        }
        HeadState::Unborn { .. } => None,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::outcome::MutationTerminalState;

    #[test]
    fn an_uncertain_commit_stays_uncertain() {
        let result = commit_result(
            MutationOutcome::from_terminal(MutationTerminalState::OutcomeUncertain),
            None,
        );
        assert_eq!(result.state, NativeCommitExecutionState::OutcomeUncertain);
        assert_eq!(result.commit, None);
        assert_eq!(result.failure, None);
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::activity::ActivityStore;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use crate::test_support::*;

    use crate::application::commit::*;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use devmil_git::RepositoryOptions;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::fs;

    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;
    use std::path::Path;
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::process::Command;

    #[test]
    fn commit_runs_the_previewed_invocation_with_untranslated_diagnostics() {
        // Regression: the stderr classifier matches Git's English messages, so the commit must
        // run with LC_ALL=C; the preview and the execution must come from one invocation.
        let request = NativeCommitRequest {
            subject: "subject".into(),
            description: String::new(),
            coauthors: vec![],
            author: Some("A U Thor <author@example.invalid>".into()),
            amend: true,
            skip_hooks: true,
            signing: NativeCommitSigning::Disable,
            sign_off: true,
        };
        let trace = CommitTrace::create(&std::env::temp_dir()).unwrap();
        let command = commit_command(
            std::ffi::OsStr::new("git"),
            Path::new("/fixture"),
            &request,
            b"subject\n".to_vec(),
            &trace,
        )
        .unwrap()
        .activity_command();
        assert!(command
            .environment
            .iter()
            .any(|variable| variable.name == "LC_ALL" && variable.display == "C"));
        let displayed = command
            .arguments
            .iter()
            .map(|argument| argument.display.clone())
            .collect::<Vec<_>>();
        assert_eq!(
            displayed,
            commit_invocation(&request, Vec::new())
                .unwrap()
                .display_arguments()
        );
        assert_eq!(
            displayed,
            [
                "commit",
                "--file=-",
                "--amend",
                "--no-verify",
                "--no-gpg-sign",
                "--signoff",
                "--author=<author>"
            ]
        );
    }

    #[test]
    #[cfg(unix)]
    fn commit_preview_execute_preserves_truth_across_hooks_head_races_and_push_failure() {
        use std::os::unix::fs::PermissionsExt as _;

        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "git {arguments:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            output.stdout
        };
        git(&["config", "user.name", "Fixture"]);
        git(&["config", "user.email", "fixture@example.invalid"]);
        fs::write(fixture.0.join("tracked.txt"), b"base\n").unwrap();
        git(&["add", "tracked.txt"]);
        git(&["commit", "-qm", "base subject\n\nbase body"]);
        fs::write(fixture.0.join("template.txt"), b"template subject\n").unwrap();
        git(&["config", "commit.template", "template.txt"]);

        let opened = repository_session_open_with_options(
            fixture.0.clone(),
            930,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let tools = repository_session_commit_tools(session.session_id, 930)
            .tools
            .unwrap();
        assert_eq!(tools.recent[0].subject, "base subject");
        assert_eq!(tools.recent[0].description, "base body");
        assert_eq!(tools.template.as_deref(), Some("template subject\n"));

        fs::write(fixture.0.join("tracked.txt"), b"first\n").unwrap();
        git(&["add", "tracked.txt"]);
        let request = NativeCommitRequest {
            subject: "first change".into(),
            description: "body".into(),
            coauthors: vec!["Pair <pair@example.invalid>".into()],
            author: None,
            amend: false,
            skip_hooks: false,
            signing: NativeCommitSigning::UseGitConfiguration,
            sign_off: true,
        };
        let stale = repository_session_commit_preview(session.session_id, 930, request.clone())
            .preview
            .unwrap();
        git(&["commit", "--allow-empty", "-qm", "external head"]);
        assert_eq!(
            repository_session_commit_execute(session.session_id, 930, stale.token).state,
            NativeCommitExecutionState::Stale
        );

        fs::write(fixture.0.join("tracked.txt"), b"second\n").unwrap();
        git(&["add", "tracked.txt"]);
        let hooks = fixture.0.join("hooks");
        fs::create_dir_all(&hooks).unwrap();
        let hook = hooks.join("pre-commit");
        fs::write(
            &hook,
            b"#!/bin/sh\nprintf 'pre-commit hook rejected fixture at %s\\n' \"$PWD\" >&2\nexit 17\n",
        )
        .unwrap();
        fs::set_permissions(&hook, fs::Permissions::from_mode(0o700)).unwrap();
        git(&["config", "core.hooksPath", "hooks"]);
        let failed = repository_session_commit_preview(session.session_id, 930, request.clone())
            .preview
            .unwrap();
        let head_before = git(&["rev-parse", "HEAD"]);
        let staged_before = git(&["show", ":tracked.txt"]);
        let hook_failure = repository_session_commit_execute(session.session_id, 930, failed.token);
        assert_eq!(hook_failure.state, NativeCommitExecutionState::Failed);
        assert_eq!(
            hook_failure.failure_kind,
            Some(NativeCommitFailureKind::Hook)
        );
        assert_eq!(hook_failure.exit_code, Some(17));
        assert_eq!(hook_failure.output.len(), 1);
        assert!(hook_failure.output[0].contains("pre-commit hook rejected"));
        assert!(hook_failure.output[0].contains("<repository>"));
        assert!(!hook_failure.output[0].contains(fixture.0.to_string_lossy().as_ref()));
        assert_eq!(git(&["rev-parse", "HEAD"]), head_before);
        assert_eq!(git(&["show", ":tracked.txt"]), staged_before);

        git(&["config", "gpg.program", "/bin/false"]);
        let signing = repository_session_commit_preview(
            session.session_id,
            930,
            NativeCommitRequest {
                skip_hooks: true,
                signing: NativeCommitSigning::Require,
                ..request.clone()
            },
        )
        .preview
        .unwrap();
        let signing_failure =
            repository_session_commit_execute(session.session_id, 930, signing.token);
        assert_eq!(signing_failure.state, NativeCommitExecutionState::Failed);
        assert_eq!(
            signing_failure.failure_kind,
            Some(NativeCommitFailureKind::Signing)
        );
        assert!(signing_failure.exit_code.is_some_and(|code| code != 0));
        assert!(!signing_failure.output.is_empty());
        git(&["config", "--unset", "gpg.program"]);

        let completed = repository_session_commit_preview(
            session.session_id,
            930,
            NativeCommitRequest {
                skip_hooks: true,
                ..request
            },
        )
        .preview
        .unwrap();
        let result = repository_session_commit_execute(session.session_id, 930, completed.token);
        assert_eq!(result.state, NativeCommitExecutionState::Completed);
        assert!(result.commit.is_some());
        let message = String::from_utf8(git(&["show", "-s", "--format=%B", "HEAD"])).unwrap();
        assert!(message.contains("first change\n\nbody"));
        assert!(message.contains("Co-authored-by: Pair <pair@example.invalid>"));
        assert!(message.contains("Signed-off-by: Fixture <fixture@example.invalid>"));

        git(&["init", "-q", "--bare", "remote.git"]);
        git(&["remote", "add", "origin", "remote.git"]);
        git(&["push", "-qu", "origin", "main"]);
        let amend = repository_session_commit_preview(
            session.session_id,
            930,
            NativeCommitRequest {
                subject: "amended subject".into(),
                description: String::new(),
                coauthors: vec![],
                author: None,
                amend: true,
                skip_hooks: true,
                signing: NativeCommitSigning::UseGitConfiguration,
                sign_off: false,
            },
        )
        .preview
        .unwrap();
        assert_eq!(amend.warnings, [NativeCommitWarning::PublishedAmend]);
        git(&["config", "user.name", ""]);
        assert!(repository_session_commit_preview(
            session.session_id,
            930,
            NativeCommitRequest {
                subject: "missing author".into(),
                description: String::new(),
                coauthors: vec![],
                author: None,
                amend: true,
                skip_hooks: true,
                signing: NativeCommitSigning::UseGitConfiguration,
                sign_off: false,
            },
        )
        .preview
        .is_none());
        git(&["config", "user.name", "Fixture"]);

        assert!(repository_session_commit_preview(
            session.session_id,
            930,
            NativeCommitRequest {
                subject: "empty index".into(),
                description: String::new(),
                coauthors: vec![],
                author: None,
                amend: false,
                skip_hooks: true,
                signing: NativeCommitSigning::UseGitConfiguration,
                sign_off: false,
            },
        )
        .preview
        .is_none());
        assert!(repository_session_close(session.session_id, 930).accepted);
    }
}
