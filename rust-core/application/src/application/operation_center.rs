//! The operation center: running and finished work across sessions and clones.
#![allow(clippy::wildcard_imports)]
use crate::activity::{NativeActivityRecord, OperationIntent, OperationOrigin};
use crate::application::session::*;
use crate::clone::NativeCloneState;
use crate::domain::ids::SessionKey;
use crate::dto::*;
use crate::dto::{NativeCloneFailure, NativeCloneFailureKind};
use devmil_git::RepositoryPhase;

/// The operations a session lists: refreshes the user asked for and dismissed entries.
#[derive(Default)]
pub(crate) struct OperationCenterState {
    pub(crate) dismissed: std::collections::HashSet<u64>,
    pub(crate) user_refreshes: Vec<UserRefreshAttempt>,
}

#[must_use]
pub fn application_operation_center(maximum_entries: u32) -> NativeOperationCenterResult {
    if maximum_entries == 0 || maximum_entries > 256 {
        return NativeOperationCenterResult {
            snapshot: None,
            failure: Some(NativeRepositoryFailure {
                kind: NativeRepositoryFailureKind::InvalidOptions,
            }),
        };
    }
    let mut sessions = lock_sessions();
    let mut entries = Vec::new();
    for (session_id, session) in &mut sessions.active {
        for refresh in &mut session.operations.user_refreshes {
            let outcome = refresh.ticket.as_ref().and_then(|ticket| ticket.try_recv());
            if let Some(outcome) = outcome {
                refresh.end_id = Some(crate::activity::next_activity_id());
                refresh.result = Some(match outcome {
                    Ok(snapshot)
                        if snapshot.error.is_none() && snapshot.phase == RepositoryPhase::Ready =>
                    {
                        NativeOperationCenterState::Succeeded
                    }
                    Ok(_) | Err(_) => NativeOperationCenterState::Failed,
                });
                refresh.finished_at_unix_ms = Some(crate::clock::unix_millis());
                refresh.ticket = None;
            }
        }
        let activity = session.activity.operation_records();
        let mut latest_refresh = None;
        let mut latest_background_fetch = None;
        for record in activity.records {
            if session.operations.dismissed.contains(&record.id) {
                continue;
            }
            let user_refresh = session.operations.user_refreshes.iter().any(|refresh| {
                record.id >= refresh.start_id && refresh.end_id.is_none_or(|end| record.id < end)
            });
            let entry =
                map_operation_center_entry(*session_id, session.generation, record, user_refresh);
            if user_refresh && entry.action == NativeOperationCenterAction::Refresh {
                continue;
            }
            if entry.action == NativeOperationCenterAction::Other
                && entry.origin == NativeOperationCenterOrigin::Background
                && entry.state == NativeOperationCenterState::Succeeded
            {
                continue;
            }
            if entry.action == NativeOperationCenterAction::Refresh
                && entry.origin == NativeOperationCenterOrigin::Background
                && entry.state == NativeOperationCenterState::Succeeded
            {
                latest_refresh = Some(entry);
            } else if entry.action == NativeOperationCenterAction::Fetch
                && entry.origin == NativeOperationCenterOrigin::Background
                && entry.state != NativeOperationCenterState::Running
            {
                // A periodic fetch repeats; only its last outcome is worth a row.
                latest_background_fetch = Some(entry);
            } else {
                entries.push(entry);
            }
        }
        if let Some(entry) = latest_refresh {
            entries.push(entry);
        }
        if let Some(entry) = latest_background_fetch {
            entries.push(entry);
        }
        for refresh in &session.operations.user_refreshes {
            if session.operations.dismissed.contains(&refresh.id)
                || refresh.result == Some(NativeOperationCenterState::Succeeded)
            {
                continue;
            }
            entries.push(NativeOperationCenterEntry {
                activity_id: Some(refresh.id),
                session_id: Some(*session_id),
                clone_attempt_id: None,
                generation: session.generation,
                state: refresh
                    .result
                    .unwrap_or(NativeOperationCenterState::Running),
                origin: NativeOperationCenterOrigin::User,
                action: NativeOperationCenterAction::Refresh,
                started_at_unix_ms: refresh.started_at_unix_ms,
                finished_at_unix_ms: refresh.finished_at_unix_ms,
                progress: None,
                can_cancel: false,
                can_retry: false,
                has_details: false,
            });
        }
    }
    drop(sessions);
    for attempt in crate::clone::clone_operation_snapshots() {
        if matches!(
            attempt.state,
            NativeCloneState::Succeeded | NativeCloneState::Canceled
        ) {
            continue;
        }
        let state = match attempt.state {
            NativeCloneState::Pending | NativeCloneState::Running => {
                NativeOperationCenterState::Running
            }
            NativeCloneState::Failed
                if matches!(
                    attempt.failure,
                    Some(NativeCloneFailure {
                        kind: NativeCloneFailureKind::Authentication
                            | NativeCloneFailureKind::CredentialBrokerUnavailable
                            | NativeCloneFailureKind::HostKey
                    })
                ) =>
            {
                NativeOperationCenterState::Attention
            }
            NativeCloneState::Failed => NativeOperationCenterState::Failed,
            NativeCloneState::Succeeded => NativeOperationCenterState::Succeeded,
            NativeCloneState::Canceled => NativeOperationCenterState::Canceled,
        };
        let can_retry = attempt.state == NativeCloneState::Failed
            && !attempt.partial_destination
            && !matches!(state, NativeOperationCenterState::Attention);
        entries.push(NativeOperationCenterEntry {
            activity_id: None,
            session_id: None,
            clone_attempt_id: Some(attempt.attempt_id),
            generation: attempt.generation,
            state,
            origin: NativeOperationCenterOrigin::User,
            action: NativeOperationCenterAction::Clone,
            started_at_unix_ms: attempt.attempt_id,
            finished_at_unix_ms: None,
            progress: attempt.progress,
            can_cancel: attempt.state == NativeCloneState::Running,
            can_retry,
            has_details: false,
        });
    }
    entries.sort_by(|left, right| {
        operation_center_priority(left.state)
            .cmp(&operation_center_priority(right.state))
            .then_with(|| right.started_at_unix_ms.cmp(&left.started_at_unix_ms))
            .then_with(|| right.activity_id.cmp(&left.activity_id))
    });
    let running_count = entries
        .iter()
        .filter(|entry| entry.state == NativeOperationCenterState::Running)
        .count() as u32;
    let failed_count = entries
        .iter()
        .filter(|entry| entry.state == NativeOperationCenterState::Failed)
        .count() as u32;
    let warning_count = entries
        .iter()
        .filter(|entry| entry.state == NativeOperationCenterState::Warning)
        .count() as u32;
    let attention_count = entries
        .iter()
        .filter(|entry| entry.state == NativeOperationCenterState::Attention)
        .count() as u32;
    let truncated = entries.len() > maximum_entries as usize;
    entries.truncate(maximum_entries as usize);
    NativeOperationCenterResult {
        snapshot: Some(NativeOperationCenterSnapshot {
            entries,
            running_count,
            failed_count,
            warning_count,
            attention_count,
            truncated,
        }),
        failure: None,
    }
}

#[must_use]
pub fn application_operation_dismiss(
    session_id: u64,
    generation: u64,
    activity_id: u64,
) -> NativeRepositoryCommandResult {
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return command_failure(kind),
    };
    let failed = session.operations.user_refreshes.iter().any(|refresh| {
        refresh.id == activity_id && refresh.result == Some(NativeOperationCenterState::Failed)
    }) || session
        .activity
        .operation_records()
        .records
        .into_iter()
        .any(|record| {
            record.id == activity_id
                && matches!(
                    record.status,
                    crate::activity::NativeActivityStatus::Failed
                        | crate::activity::NativeActivityStatus::TimedOut
                        | crate::activity::NativeActivityStatus::LaunchError
                )
        });
    if !failed {
        return command_failure(NativeRepositoryFailureKind::InvalidOptions);
    }
    session.operations.dismissed.insert(activity_id);
    NativeRepositoryCommandResult {
        accepted: true,
        failure: None,
    }
}

#[must_use]
pub fn application_operation_dismiss_all() -> NativeRepositoryCommandResult {
    let mut sessions = lock_sessions();
    for session in sessions.active.values_mut() {
        for refresh in &session.operations.user_refreshes {
            if refresh.result == Some(NativeOperationCenterState::Failed) {
                session.operations.dismissed.insert(refresh.id);
            }
        }
        for record in session.activity.operation_records().records {
            if matches!(
                record.status,
                crate::activity::NativeActivityStatus::Failed
                    | crate::activity::NativeActivityStatus::TimedOut
                    | crate::activity::NativeActivityStatus::LaunchError
            ) {
                session.operations.dismissed.insert(record.id);
            }
        }
    }
    drop(sessions);
    crate::clone::dismiss_failed_clone_operations();
    NativeRepositoryCommandResult {
        accepted: true,
        failure: None,
    }
}

pub(crate) fn map_operation_center_entry(
    session_id: u64,
    generation: u64,
    record: NativeActivityRecord,
    user_refresh: bool,
) -> NativeOperationCenterEntry {
    let first = devmil_git::process::git_subcommand(&record.arguments);
    let (action, mut origin) = match crate::activity::operation_intent(record.id) {
        // The use case that ran the command said what it was for.
        Some((intent, origin)) => (operation_action(intent), operation_origin(origin)),
        None => (
            background_read_action(first),
            NativeOperationCenterOrigin::Background,
        ),
    };
    if user_refresh && action == NativeOperationCenterAction::Refresh {
        origin = NativeOperationCenterOrigin::User;
    }
    let state = match record.status {
        crate::activity::NativeActivityStatus::Running => NativeOperationCenterState::Running,
        crate::activity::NativeActivityStatus::Succeeded => NativeOperationCenterState::Succeeded,
        crate::activity::NativeActivityStatus::Canceled => NativeOperationCenterState::Canceled,
        // Exit status 1 is how these probes answer "no": an unset key, a path that is not
        // ignored. The question was answered, so there is nothing to look at.
        crate::activity::NativeActivityStatus::Failed if expected_probe_miss(&record, first) => {
            NativeOperationCenterState::Succeeded
        }
        crate::activity::NativeActivityStatus::Failed
        | crate::activity::NativeActivityStatus::TimedOut
        | crate::activity::NativeActivityStatus::LaunchError => {
            if origin == NativeOperationCenterOrigin::Background {
                NativeOperationCenterState::Warning
            } else {
                NativeOperationCenterState::Failed
            }
        }
    };
    NativeOperationCenterEntry {
        activity_id: Some(record.id),
        session_id: Some(session_id),
        clone_attempt_id: None,
        generation,
        state,
        origin,
        action,
        started_at_unix_ms: record.started_at_unix_ms,
        finished_at_unix_ms: record.finished_at_unix_ms,
        progress: record.progress,
        can_cancel: false,
        can_retry: false,
        has_details: true,
    }
}

const fn operation_action(intent: OperationIntent) -> NativeOperationCenterAction {
    match intent {
        OperationIntent::Fetch => NativeOperationCenterAction::Fetch,
        OperationIntent::Pull => NativeOperationCenterAction::Pull,
        OperationIntent::Push => NativeOperationCenterAction::Push,
        OperationIntent::Initialize => NativeOperationCenterAction::Initialize,
        OperationIntent::Clone => NativeOperationCenterAction::Clone,
        OperationIntent::Change => NativeOperationCenterAction::Other,
    }
}

const fn operation_origin(origin: OperationOrigin) -> NativeOperationCenterOrigin {
    match origin {
        OperationOrigin::User => NativeOperationCenterOrigin::User,
        OperationOrigin::Background => NativeOperationCenterOrigin::Background,
    }
}

/// A command no use case registered is a background read. Those that keep the repository
/// snapshot current are a refresh; every change registers its intent, so a `stash`, `branch`
/// or `tag` here only lists.
fn background_read_action(command: Option<&str>) -> NativeOperationCenterAction {
    match command {
        Some(
            "status" | "for-each-ref" | "show-ref" | "check-ignore" | "worktree" | "config"
            | "rev-parse" | "symbolic-ref" | "ls-files" | "stash" | "branch" | "tag",
        ) => NativeOperationCenterAction::Refresh,
        _ => NativeOperationCenterAction::Other,
    }
}

pub(crate) fn expected_probe_miss(record: &NativeActivityRecord, command: Option<&str>) -> bool {
    if record.exit_code != Some(1) {
        return false;
    }
    let has = |flag| record.arguments.iter().any(|argument| argument == flag);
    match command {
        Some("config") => has("--get") || has("--get-all") || has("--get-regexp"),
        Some("check-ignore") => true,
        // `diff --no-index` also exits 1 when the files differ, which is the
        // answer for a new file; a real failure writes to stderr.
        Some("diff") => {
            has("--quiet")
                || has("--exit-code")
                || (has("--no-index") && record.stderr_total_bytes == 0)
        }
        Some("merge-base") => has("--is-ancestor"),
        Some("show-ref") => has("--verify"),
        _ => false,
    }
}

pub(crate) const fn operation_center_priority(state: NativeOperationCenterState) -> u8 {
    match state {
        NativeOperationCenterState::Attention => 0,
        NativeOperationCenterState::Failed => 1,
        NativeOperationCenterState::Warning => 2,
        NativeOperationCenterState::Running => 3,
        NativeOperationCenterState::Succeeded | NativeOperationCenterState::Canceled => 4,
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::{allocate_activity_id, ActivityStore, NativeActivityRecord};
    use crate::test_support::*;

    use crate::application::{operation_center::*, transfer::*};

    use crate::transfer::{
        NativePullStrategy, NativeTransferExecutionState, NativeTransferFailureKind,
        NativeTransferKind, NativeTransferRequest,
    };

    use devmil_git::activity::ActivityStatus;

    use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};

    use crate::clone::{
        clone_create as repository_clone_create, clone_dismiss as repository_clone_dismiss,
    };

    use devmil_git::activity::ActivityEvent;

    use devmil_git::RepositoryOptions;

    use std::fs;

    use std::time::Duration;
    use std::time::Instant;

    #[test]
    fn activity_classification_skips_global_options_without_matching_operands() {
        for (arguments, expected) in [
            (vec!["-C", "push", "status"], Some("status")),
            (
                vec![
                    "--literal-pathspecs",
                    "-c",
                    "alias.x=push",
                    "add",
                    "--",
                    "push",
                ],
                Some("add"),
            ),
            (
                vec!["--git-dir=private", "--work-tree", "private", "push"],
                Some("push"),
            ),
            (vec!["-C"], None),
        ] {
            let arguments = arguments.into_iter().map(str::to_owned).collect::<Vec<_>>();
            assert_eq!(devmil_git::process::git_subcommand(&arguments), expected);
        }
    }

    #[test]
    fn operation_center_distinguishes_expected_probe_and_background_failures() {
        let mut record = NativeActivityRecord {
            id: 9,
            executable: "git".to_owned(),
            arguments: ["config", "--path", "--get", "commit.template"]
                .map(str::to_owned)
                .to_vec(),
            started_at_unix_ms: 1,
            finished_at_unix_ms: Some(2),
            status: crate::activity::NativeActivityStatus::Failed,
            exit_code: Some(1),
            stdout: Vec::new(),
            stdout_total_bytes: 0,
            stdout_truncated: false,
            stderr: Vec::new(),
            stderr_total_bytes: 0,
            stderr_truncated: false,
            progress: None,
        };
        let expected = map_operation_center_entry(1, 1, record.clone(), true);
        assert_eq!(expected.state, NativeOperationCenterState::Succeeded);
        assert_eq!(expected.origin, NativeOperationCenterOrigin::User);

        // A new file's diff against the null device differs, so Git exits 1
        // without saying anything. Only an exit with diagnostics is a warning.
        let mut new_file = record.clone();
        new_file.arguments = [
            "--literal-pathspecs",
            "diff",
            "--no-ext-diff",
            "--raw",
            "--patch",
            "--no-index",
            "--",
            "/dev/null",
            "[PATH]",
        ]
        .map(str::to_owned)
        .to_vec();
        new_file.stdout_total_bytes = 120;
        assert_eq!(
            map_operation_center_entry(1, 1, new_file.clone(), false).state,
            NativeOperationCenterState::Succeeded
        );
        new_file.stderr_total_bytes = 40;
        assert_eq!(
            map_operation_center_entry(1, 1, new_file, false).state,
            NativeOperationCenterState::Warning
        );

        let mut listing = record.clone();
        listing.status = crate::activity::NativeActivityStatus::Succeeded;
        listing.exit_code = Some(0);
        let change = || {
            crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change).get()
        };
        // What a command was for comes from the use case that registered it, never from its
        // arguments: an unregistered command is a background read whatever it names.
        for (id, arguments, action, origin) in [
            (
                9,
                vec!["stash", "list", "--format=%H"],
                NativeOperationCenterAction::Refresh,
                NativeOperationCenterOrigin::Background,
            ),
            (
                9,
                vec!["branch", "-r", "--contains", "HEAD"],
                NativeOperationCenterAction::Refresh,
                NativeOperationCenterOrigin::Background,
            ),
            (
                change(),
                vec!["stash", "push", "--include-untracked"],
                NativeOperationCenterAction::Other,
                NativeOperationCenterOrigin::User,
            ),
            (
                change(),
                vec!["branch", "-D", "list"],
                NativeOperationCenterAction::Other,
                NativeOperationCenterOrigin::User,
            ),
            (
                change(),
                vec!["worktree", "add", "--", "elsewhere"],
                NativeOperationCenterAction::Other,
                NativeOperationCenterOrigin::User,
            ),
            (
                crate::activity::allocate_operation_id_from(
                    crate::activity::OperationIntent::Fetch,
                    crate::activity::OperationOrigin::Background,
                )
                .get(),
                vec!["fetch", "--prune", "origin"],
                NativeOperationCenterAction::Fetch,
                NativeOperationCenterOrigin::Background,
            ),
        ] {
            listing.id = id;
            listing.arguments = arguments.into_iter().map(str::to_owned).collect();
            let entry = map_operation_center_entry(1, 1, listing.clone(), false);
            assert_eq!((entry.action, entry.origin), (action, origin));
        }

        record.arguments = vec!["status".to_owned(), "--invalid".to_owned()];
        record.exit_code = Some(129);
        let background = map_operation_center_entry(1, 1, record.clone(), false);
        assert_eq!(background.state, NativeOperationCenterState::Warning);
        assert_eq!(background.origin, NativeOperationCenterOrigin::Background);
        let requested = map_operation_center_entry(1, 1, record.clone(), true);
        assert_eq!(requested.state, NativeOperationCenterState::Failed);
        assert_eq!(requested.origin, NativeOperationCenterOrigin::User);

        record.id =
            crate::activity::allocate_operation_id(crate::activity::OperationIntent::Push).get();
        record.arguments = vec!["push".to_owned()];
        let push = map_operation_center_entry(1, 1, record, false);
        assert_eq!(push.action, NativeOperationCenterAction::Push);
        assert_eq!(push.state, NativeOperationCenterState::Failed);
    }

    #[test]
    fn requested_refresh_failure_is_user_error() {
        let fixture = GitFixture::new();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            761,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        fs::write(fixture.0.join(".git/index"), b"invalid index").unwrap();
        assert!(repository_session_refresh(session.session_id, 761).accepted);
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            let center = application_operation_center(256).snapshot.unwrap();
            if let Some(entry) = center.entries.iter().find(|entry| {
                entry.session_id == Some(session.session_id)
                    && entry.action == NativeOperationCenterAction::Refresh
                    && entry.origin == NativeOperationCenterOrigin::User
                    && entry.state == NativeOperationCenterState::Failed
            }) {
                assert!(center.failed_count >= 1);
                assert!(!entry.has_details);
                assert!(
                    application_operation_dismiss(
                        session.session_id,
                        761,
                        entry.activity_id.unwrap()
                    )
                    .accepted
                );
                assert!(!application_operation_center(256)
                    .snapshot
                    .unwrap()
                    .entries
                    .iter()
                    .any(|candidate| candidate.activity_id == entry.activity_id));
                break;
            }
            assert!(
                Instant::now() < deadline,
                "requested refresh failure was not classified"
            );
            std::thread::sleep(Duration::from_millis(25));
        }
        assert!(repository_session_close(session.session_id, 761).accepted);
    }

    #[test]
    fn operation_center_classifies_globally_and_retains_failures_until_dismissed() {
        let fixture = GitFixture::new();
        let destination = fixture.0.join("operation-center");
        let session = repository_initialize(
            destination.to_string_lossy().into_owned(),
            "main".into(),
            false,
            76,
        )
        .session
        .unwrap();
        let _ = wait_for_ready(&session);
        let activity = {
            let sessions = lock_sessions();
            sessions
                .active
                .get(&session.session_id)
                .unwrap()
                .activity
                .clone()
        };
        let sink = activity.sink();
        let mut publish = move |event| sink(event);
        let failure = ActivityGitRunner::run(
            GitProcessCommand::git("git").args([
                ProcessArgument::visible("--no-pager"),
                ProcessArgument::visible("-c"),
                ProcessArgument::visible("color.ui=false"),
                ProcessArgument::visible("-C"),
                ProcessArgument::visible(destination.as_os_str()),
                ProcessArgument::visible("push"),
            ]),
            crate::activity::allocate_operation_id(crate::activity::OperationIntent::Push),
            None,
            &mut publish,
        );
        assert!(matches!(failure.status, ActivityStatus::Failed { .. }));
        let mut running = failure.clone();
        running.status = ActivityStatus::Running;
        running.finished_at_unix_ms = None;
        activity.sink()(ActivityEvent::Created(running));
        let live = application_operation_center(256).snapshot.unwrap();
        assert!(live
            .entries
            .iter()
            .any(|entry| entry.activity_id == Some(failure.id.get())
                && entry.action == NativeOperationCenterAction::Push
                && entry.state == NativeOperationCenterState::Running));
        activity.sink()(ActivityEvent::Finished(failure));

        let warning = ActivityGitRunner::run(
            GitProcessCommand::git("git").args([
                ProcessArgument::visible("-C"),
                ProcessArgument::visible(destination.as_os_str()),
                ProcessArgument::visible("rev-parse"),
                ProcessArgument::visible("--verify"),
                ProcessArgument::visible("refs/heads/gitlama-missing"),
            ]),
            allocate_activity_id(),
            None,
            &mut publish,
        );
        assert!(matches!(warning.status, ActivityStatus::Failed { .. }));
        // An unset key is an answer, not a failure.
        let miss = ActivityGitRunner::run(
            GitProcessCommand::git("git").args([
                ProcessArgument::visible("-C"),
                ProcessArgument::visible(destination.as_os_str()),
                ProcessArgument::visible("config"),
                ProcessArgument::visible("--local"),
                ProcessArgument::visible("--path"),
                ProcessArgument::visible("--get"),
                ProcessArgument::visible("gitlama.missing"),
            ]),
            allocate_activity_id(),
            None,
            &mut publish,
        );
        assert!(matches!(
            miss.status,
            ActivityStatus::Failed { exit_code: Some(1) }
        ));

        let center = application_operation_center(256).snapshot.unwrap();
        assert!(center.warning_count >= 1);
        assert!(!center.entries.iter().any(|entry| {
            entry.activity_id == Some(miss.id.get())
                && entry.state != NativeOperationCenterState::Succeeded
        }));
        assert!(center.entries.iter().any(|entry| {
            entry.activity_id == Some(warning.id.get())
                && entry.state == NativeOperationCenterState::Warning
        }));
        assert!(center.entries.iter().any(|entry| {
            entry.action == NativeOperationCenterAction::Initialize
                && entry.origin == NativeOperationCenterOrigin::User
        }));
        let failed = center
            .entries
            .iter()
            .find(|entry| {
                entry.state == NativeOperationCenterState::Failed
                    && entry.session_id == Some(session.session_id)
            })
            .unwrap();
        assert!(center.failed_count >= 1);
        assert!(failed.has_details);
        assert!(!failed.can_retry);
        let bounded = application_operation_center(1).snapshot.unwrap();
        assert!(bounded.truncated);
        assert_eq!(bounded.entries.len(), 1);
        assert!(bounded.failed_count >= 1);
        assert!(
            application_operation_dismiss(session.session_id, 76, failed.activity_id.unwrap())
                .accepted
        );
        let after = application_operation_center(256).snapshot.unwrap();
        assert!(!after
            .entries
            .iter()
            .any(|entry| entry.activity_id == failed.activity_id));
        assert!(repository_session_close(session.session_id, 76).accepted);
    }

    #[test]
    fn operation_center_includes_pending_clone_before_repository_session_exists() {
        let source = GitFixture::new();
        let destination = fixture_path("clone-operation");
        let created = repository_clone_create(
            source.0.to_string_lossy().into_owned(),
            destination.to_string_lossy().into_owned(),
            None,
            77,
        )
        .snapshot
        .unwrap();
        let center = application_operation_center(256).snapshot.unwrap();
        let entry = center
            .entries
            .iter()
            .find(|entry| entry.clone_attempt_id == Some(created.attempt_id))
            .unwrap();
        assert_eq!(entry.state, NativeOperationCenterState::Running);
        assert_eq!(entry.action, NativeOperationCenterAction::Clone);
        assert!(entry.session_id.is_none());
        assert!(entry.activity_id.is_none());
        assert!(repository_clone_dismiss(created.attempt_id, 77).accepted);
        let _ = fs::remove_dir_all(destination);
    }

    #[test]
    fn a_background_fetch_is_listed_once_as_background_work() {
        let fixture = TransferFixture::new();
        let opened = repository_session_open_with_options(
            fixture.client.clone(),
            1_204,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let preview = |kind| {
            repository_session_transfer_preview(
                session.session_id,
                session.generation,
                NativeTransferRequest {
                    kind,
                    remote: None,
                    branch: None,
                    pull_strategy: NativePullStrategy::FastForwardOnly,
                    allow_dirty: false,
                    stash_before_pull: false,
                    force_with_lease: false,
                    set_upstream: false,
                    refetch: false,
                    prune: true,
                },
            )
            .preview
            .unwrap()
        };
        let fetches = || {
            application_operation_center(256)
                .snapshot
                .unwrap()
                .entries
                .into_iter()
                .filter(|entry| {
                    entry.session_id == Some(session.session_id)
                        && entry.action == NativeOperationCenterAction::Fetch
                })
                .collect::<Vec<_>>()
        };
        for _ in 0..2 {
            assert_eq!(
                repository_session_transfer_execute_background(
                    session.session_id,
                    session.generation,
                    preview(NativeTransferKind::Fetch).token,
                )
                .state,
                NativeTransferExecutionState::Completed
            );
        }
        let listed = fetches();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].origin, NativeOperationCenterOrigin::Background);

        assert_eq!(
            repository_session_transfer_execute(
                session.session_id,
                session.generation,
                preview(NativeTransferKind::Fetch).token,
            )
            .state,
            NativeTransferExecutionState::Completed
        );
        assert!(fetches()
            .iter()
            .any(|entry| entry.origin == NativeOperationCenterOrigin::User));

        // Only a fetch may run without the user asking for it.
        assert_eq!(
            repository_session_transfer_execute_background(
                session.session_id,
                session.generation,
                preview(NativeTransferKind::Pull).token,
            )
            .failure
            .unwrap()
            .kind,
            NativeTransferFailureKind::InvalidRequest
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
