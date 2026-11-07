//! Bounded diff-content search, bisect control and on-demand statistics.
pub use gitlama_contract::power_tools::*;

use crate::activity::ActivityStore;
use crate::domain::outcome::MutationState;
use crate::preview_store::PreviewStore;
use devmil_git::activity::ActivityStatus;
use devmil_git::loading::deep_graph::{
    BisectMark, BisectState, DiffContentSearchOptions, DiffContentSearchResult,
    DiffContentSearchScope, SearchCompleteness,
};
use devmil_git::loading::statistics::RepositoryStatistics;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::types::{HeadState, ObjectId};
use devmil_git::{ReadTicket, Repository, RepositoryErrorKind};
use std::collections::HashMap;
use std::sync::atomic::AtomicBool;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

const MAX_SEARCH_RESULTS: usize = 512;
const MAX_SEARCH_COMMITS: usize = 10_000;
const JOB_CAPACITY_PER_SESSION: usize = 4;

/// The one place a bisect step's outcome becomes a bridge state.
const fn native_bisect_state(state: MutationState) -> NativeBisectExecutionState {
    match state {
        MutationState::Completed
        | MutationState::AlreadyContained
        | MutationState::Aborted
        | MutationState::ReconciledWithWarning => NativeBisectExecutionState::Completed,
        MutationState::Stale => NativeBisectExecutionState::Stale,
        MutationState::Conflict
        | MutationState::Interrupted
        | MutationState::EditStop
        | MutationState::Partial
        | MutationState::Canceled
        | MutationState::Failed => NativeBisectExecutionState::Failed,
        MutationState::OutcomeUncertain => NativeBisectExecutionState::OutcomeUncertain,
    }
}

enum PowerJob {
    Search(ReadTicket<DiffContentSearchResult>),
    Statistics(ReadTicket<RepositoryStatistics>),
}

struct BisectPreviewOwned {
    arguments: Vec<String>,
    expected_head: Option<String>,
    expected_active: bool,
}

struct PowerRegistry {
    next_token: u64,
    jobs: HashMap<(u64, u64), PowerJob>,
    bisect: PreviewStore<BisectPreviewOwned>,
}

/// Bisect previews a session keeps; the oldest goes first.
const BISECT_PREVIEWS_PER_SESSION: usize = 4;

static REGISTRY: OnceLock<Mutex<PowerRegistry>> = OnceLock::new();

fn lock_registry() -> std::sync::MutexGuard<'static, PowerRegistry> {
    REGISTRY
        .get_or_init(|| {
            Mutex::new(PowerRegistry {
                next_token: 0,
                jobs: HashMap::new(),
                bisect: PreviewStore::new(BISECT_PREVIEWS_PER_SESSION),
            })
        })
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn token(registry: &mut PowerRegistry) -> u64 {
    registry.next_token = registry.next_token.saturating_add(1).max(1);
    registry.next_token
}

pub(crate) fn start_search(
    session_id: u64,
    repository: &Repository,
    query: String,
    maximum_commits: u32,
) -> NativePowerJobStartResult {
    start_search_with_options(
        session_id,
        repository,
        NativeDiffSearchOptions {
            query,
            maximum_commits,
            case_sensitive: false,
            scope: NativeDiffSearchScope::AllRefs,
            other_refs: true,
        },
    )
}

pub(crate) fn start_search_with_options(
    session_id: u64,
    repository: &Repository,
    options: NativeDiffSearchOptions,
) -> NativePowerJobStartResult {
    let NativeDiffSearchOptions {
        query,
        maximum_commits,
        case_sensitive,
        scope,
        other_refs,
    } = options;
    if query.is_empty()
        || query.len() > 1_024
        || maximum_commits == 0
        || maximum_commits as usize > MAX_SEARCH_COMMITS
    {
        return start_failure(NativePowerFailureKind::InvalidRequest);
    }
    let ticket = match repository.search_diff_content_with_options(
        query,
        maximum_commits as usize,
        MAX_SEARCH_RESULTS,
        DiffContentSearchOptions {
            case_sensitive,
            scope: match scope {
                NativeDiffSearchScope::AllRefs if other_refs => DiffContentSearchScope::AllRefs,
                NativeDiffSearchScope::AllRefs => DiffContentSearchScope::StandardRefs,
                NativeDiffSearchScope::CurrentBranch => DiffContentSearchScope::CurrentBranch,
            },
        },
    ) {
        Ok(value) => value,
        Err(error) => return start_failure(map_error(error.kind)),
    };
    let mut registry = lock_registry();
    if registry
        .jobs
        .keys()
        .filter(|(owner, _)| *owner == session_id)
        .count()
        >= JOB_CAPACITY_PER_SESSION
    {
        return start_failure(NativePowerFailureKind::Busy);
    }
    let token = token(&mut registry);
    registry
        .jobs
        .insert((session_id, token), PowerJob::Search(ticket));
    NativePowerJobStartResult {
        token: Some(token),
        failure: None,
    }
}

pub(crate) fn poll_search(session_id: u64, token: u64) -> NativeDiffContentSearchResult {
    let mut registry = lock_registry();
    let result = match registry.jobs.get(&(session_id, token)) {
        Some(PowerJob::Search(ticket)) => ticket.try_recv(),
        Some(PowerJob::Statistics(_)) | None => {
            return search_failure(NativePowerFailureKind::InvalidRequest)
        }
    };
    let Some(result) = result else {
        return NativeDiffContentSearchResult {
            state: NativePowerJobState::Pending,
            matches: Vec::new(),
            examined_commits: 0,
            completeness: None,
            activity_ids: Vec::new(),
            failure: None,
        };
    };
    registry.jobs.remove(&(session_id, token));
    drop(registry);
    match result {
        Ok(result) => NativeDiffContentSearchResult {
            state: NativePowerJobState::Completed,
            matches: result
                .matches
                .iter()
                .map(|value| NativeDiffContentMatch {
                    commit: value.commit.as_str().to_owned(),
                    summary: value.summary.clone(),
                })
                .collect(),
            examined_commits: result.examined_commits as u64,
            completeness: Some(match result.completeness {
                SearchCompleteness::Complete => NativeSearchCompleteness::Complete,
                SearchCompleteness::CommitLimitReached => {
                    NativeSearchCompleteness::CommitLimitReached
                }
                SearchCompleteness::ResultLimitReached => {
                    NativeSearchCompleteness::ResultLimitReached
                }
            }),
            activity_ids: result
                .activities
                .iter()
                .map(|value| value.get().to_string())
                .collect(),
            failure: None,
        },
        Err(error) => search_failure(map_error(error.kind)),
    }
}

pub(crate) fn start_statistics(
    session_id: u64,
    repository: &Repository,
) -> NativePowerJobStartResult {
    let ticket = match repository.statistics() {
        Ok(value) => value,
        Err(error) => return start_failure(map_error(error.kind)),
    };
    let mut registry = lock_registry();
    if registry
        .jobs
        .keys()
        .filter(|(owner, _)| *owner == session_id)
        .count()
        >= JOB_CAPACITY_PER_SESSION
    {
        return start_failure(NativePowerFailureKind::Busy);
    }
    let token = token(&mut registry);
    registry
        .jobs
        .insert((session_id, token), PowerJob::Statistics(ticket));
    NativePowerJobStartResult {
        token: Some(token),
        failure: None,
    }
}

pub(crate) fn poll_statistics(session_id: u64, token: u64) -> NativeRepositoryStatisticsResult {
    let mut registry = lock_registry();
    let result = match registry.jobs.get(&(session_id, token)) {
        Some(PowerJob::Statistics(ticket)) => ticket.try_recv(),
        Some(PowerJob::Search(_)) | None => {
            return statistics_failure(NativePowerFailureKind::InvalidRequest)
        }
    };
    let Some(result) = result else {
        return NativeRepositoryStatisticsResult {
            state: NativePowerJobState::Pending,
            commit_count: 0,
            local_branch_count: 0,
            tag_count: 0,
            changed_path_count: 0,
            incomplete: false,
            activity_ids: Vec::new(),
            failure: None,
        };
    };
    registry.jobs.remove(&(session_id, token));
    drop(registry);
    match result {
        Ok(result) => NativeRepositoryStatisticsResult {
            state: NativePowerJobState::Completed,
            commit_count: result.commit_count,
            local_branch_count: result.local_branch_count as u64,
            tag_count: result.tag_count as u64,
            changed_path_count: result.changed_path_count as u64,
            incomplete: result.incomplete,
            activity_ids: result
                .activities
                .iter()
                .map(|value| value.id.get().to_string())
                .collect(),
            failure: None,
        },
        Err(error) => statistics_failure(map_error(error.kind)),
    }
}

pub(crate) fn cancel_job(session_id: u64, token: u64) -> bool {
    lock_registry().jobs.remove(&(session_id, token)).is_some()
}

pub(crate) fn bisect_state(repository: &Repository) -> NativeBisectStateResult {
    match load_bisect_state(repository) {
        Ok(value) => NativeBisectStateResult {
            state: Some(native_bisect(&value)),
            failure: None,
        },
        Err(kind) => NativeBisectStateResult {
            state: None,
            failure: Some(NativePowerFailure { kind }),
        },
    }
}

pub(crate) fn preview_bisect(
    session_id: u64,
    repository: &Repository,
    action: NativeBisectAction,
    good: Option<String>,
    bad: Option<String>,
) -> NativeBisectPreviewResult {
    let state = match load_bisect_state(repository) {
        Ok(value) => value,
        Err(kind) => return bisect_preview_failure(kind),
    };
    use devmil_git::commands::bisect::{bisect_arguments, BisectRequest};
    let request = match action {
        NativeBisectAction::Start => {
            if state.active {
                return bisect_preview_failure(NativePowerFailureKind::InvalidRequest);
            }
            let (Some(good), Some(bad)) = (good, bad) else {
                return bisect_preview_failure(NativePowerFailureKind::InvalidRequest);
            };
            let (Ok(good), Ok(bad)) = (ObjectId::parse(good), ObjectId::parse(bad)) else {
                return bisect_preview_failure(NativePowerFailureKind::InvalidRequest);
            };
            BisectRequest::Start { bad, good }
        }
        NativeBisectAction::Good
        | NativeBisectAction::Bad
        | NativeBisectAction::Skip
        | NativeBisectAction::Reset => {
            if !state.active || good.is_some() || bad.is_some() {
                return bisect_preview_failure(NativePowerFailureKind::InvalidRequest);
            }
            match action {
                NativeBisectAction::Good => BisectRequest::Good,
                NativeBisectAction::Bad => BisectRequest::Bad,
                NativeBisectAction::Skip => BisectRequest::Skip,
                NativeBisectAction::Start | NativeBisectAction::Reset => BisectRequest::Reset,
            }
        }
    };
    let arguments = bisect_arguments(&request);
    let expected_head =
        repository
            .snapshot()
            .repository
            .as_ref()
            .and_then(|value| match &value.head {
                HeadState::Attached { target, .. } | HeadState::Detached { target } => {
                    Some(target.as_str().to_owned())
                }
                HeadState::Unborn { .. } => None,
            });
    let token = lock_registry().bisect.issue(
        session_id,
        BisectPreviewOwned {
            arguments: arguments.clone(),
            expected_head,
            expected_active: state.active,
        },
    );
    NativeBisectPreviewResult {
        preview: Some(NativeBisectPreview {
            token,
            action,
            arguments,
        }),
        failure: None,
    }
}

pub(crate) fn execute_bisect(
    session_id: u64,
    token: u64,
    repository: &Repository,
    activity: &ActivityStore,
) -> NativeBisectExecutionResult {
    let Some(preview) = lock_registry().bisect.finish(session_id, token) else {
        return bisect_execution_failure(NativePowerFailureKind::InvalidRequest);
    };
    let current_state = match load_bisect_state(repository) {
        Ok(value) => value,
        Err(kind) => return bisect_execution_failure(kind),
    };
    let current_head =
        repository
            .snapshot()
            .repository
            .as_ref()
            .and_then(|value| match &value.head {
                HeadState::Attached { target, .. } | HeadState::Detached { target } => {
                    Some(target.as_str().to_owned())
                }
                HeadState::Unborn { .. } => None,
            });
    if current_head != preview.expected_head || current_state.active != preview.expected_active {
        return NativeBisectExecutionResult {
            state: native_bisect_state(MutationState::Stale),
            bisect: Some(native_bisect(&current_state)),
            activity_id: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    }
    let snapshot = repository.snapshot();
    let Some(discovered) = snapshot.repository.as_ref() else {
        return bisect_execution_failure(NativePowerFailureKind::Read);
    };
    let cancellation = AtomicBool::new(false);
    let Ok(lease) = repository.begin_mutation_with_cancellation(&cancellation) else {
        return bisect_execution_failure(NativePowerFailureKind::Busy);
    };
    let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change);
    let command = GitProcessCommand::git(repository.git_executable())
        .current_dir(discovered.worktree.worktree_root().as_path())
        .args(preview.arguments.into_iter().map(ProcessArgument::visible))
        .redact_output();
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let result = ActivityGitRunner::run_private(command, id, Some(&cancellation), &mut publish);
    drop(lease);
    reload(repository);
    let state = load_bisect_state(repository)
        .ok()
        .map(|value| native_bisect(&value));
    if matches!(result.activity.status, ActivityStatus::Succeeded { .. }) {
        NativeBisectExecutionResult {
            state: native_bisect_state(MutationState::Completed),
            bisect: state,
            activity_id: Some(id.get().to_string()),
            failure: None,
        }
    } else {
        NativeBisectExecutionResult {
            state: native_bisect_state(MutationState::Failed),
            bisect: state,
            activity_id: Some(id.get().to_string()),
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Git,
            }),
        }
    }
}

pub(crate) fn cancel_bisect_preview(session_id: u64, token: u64) -> bool {
    lock_registry().bisect.finish(session_id, token).is_some()
}

pub(crate) fn dismiss_session(session_id: u64) {
    let mut registry = lock_registry();
    registry.jobs.retain(|(owner, _), _| *owner != session_id);
    registry.bisect.discard_session(session_id);
}

fn load_bisect_state(repository: &Repository) -> Result<BisectState, NativePowerFailureKind> {
    let ticket = repository
        .bisect_state()
        .map_err(|error| map_error(error.kind))?;
    ticket
        .recv_timeout(Duration::from_secs(30))
        .ok_or(NativePowerFailureKind::TimedOut)?
        .map(|value| value.as_ref().clone())
        .map_err(|error| map_error(error.kind))
}

fn native_bisect(value: &BisectState) -> NativeBisectState {
    NativeBisectState {
        active: value.active,
        current: value
            .current
            .as_ref()
            .map(|value| value.as_str().to_owned()),
        original_head: value
            .original_head
            .as_ref()
            .map(|value| value.as_str().to_owned()),
        timeline: value
            .timeline
            .iter()
            .map(|entry| NativeBisectTimelineEntry {
                revision: entry.revision.as_str().to_owned(),
                mark: match entry.mark {
                    BisectMark::Good => NativeBisectMark::Good,
                    BisectMark::Bad => NativeBisectMark::Bad,
                    BisectMark::Skip => NativeBisectMark::Skip,
                },
            })
            .collect(),
        remaining_steps: value.remaining_steps.map(|value| value as u64),
        next_step_summary: value.next_step_summary.clone(),
    }
}

fn reload(repository: &Repository) {
    let _ = repository.reload().ok().and_then(|ticket| {
        ticket
            .recv_timeout(Duration::from_secs(5))
            .and_then(Result::ok)
    });
}

fn map_error(kind: RepositoryErrorKind) -> NativePowerFailureKind {
    match kind {
        RepositoryErrorKind::Canceled => NativePowerFailureKind::Canceled,
        RepositoryErrorKind::TimedOut => NativePowerFailureKind::TimedOut,
        RepositoryErrorKind::TooLarge => NativePowerFailureKind::TooLarge,
        RepositoryErrorKind::InvalidOptions => NativePowerFailureKind::InvalidRequest,
        RepositoryErrorKind::Capacity => NativePowerFailureKind::Busy,
        RepositoryErrorKind::Closed => NativePowerFailureKind::Stale,
        RepositoryErrorKind::MissingObject
        | RepositoryErrorKind::InvalidOutput
        | RepositoryErrorKind::MissingGit
        | RepositoryErrorKind::Unsupported
        | RepositoryErrorKind::Discovery
        | RepositoryErrorKind::Read
        | RepositoryErrorKind::Watch => NativePowerFailureKind::Read,
    }
}

fn start_failure(kind: NativePowerFailureKind) -> NativePowerJobStartResult {
    NativePowerJobStartResult {
        token: None,
        failure: Some(NativePowerFailure { kind }),
    }
}

fn search_failure(kind: NativePowerFailureKind) -> NativeDiffContentSearchResult {
    NativeDiffContentSearchResult {
        state: if kind == NativePowerFailureKind::Canceled {
            NativePowerJobState::Canceled
        } else {
            NativePowerJobState::Failed
        },
        matches: Vec::new(),
        examined_commits: 0,
        completeness: None,
        activity_ids: Vec::new(),
        failure: Some(NativePowerFailure { kind }),
    }
}

fn statistics_failure(kind: NativePowerFailureKind) -> NativeRepositoryStatisticsResult {
    NativeRepositoryStatisticsResult {
        state: if kind == NativePowerFailureKind::Canceled {
            NativePowerJobState::Canceled
        } else {
            NativePowerJobState::Failed
        },
        commit_count: 0,
        local_branch_count: 0,
        tag_count: 0,
        changed_path_count: 0,
        incomplete: false,
        activity_ids: Vec::new(),
        failure: Some(NativePowerFailure { kind }),
    }
}

fn bisect_preview_failure(kind: NativePowerFailureKind) -> NativeBisectPreviewResult {
    NativeBisectPreviewResult {
        preview: None,
        failure: Some(NativePowerFailure { kind }),
    }
}

fn bisect_execution_failure(kind: NativePowerFailureKind) -> NativeBisectExecutionResult {
    NativeBisectExecutionResult {
        state: native_bisect_state(if kind == NativePowerFailureKind::Stale {
            MutationState::Stale
        } else {
            MutationState::Failed
        }),
        bisect: None,
        activity_id: None,
        failure: Some(NativePowerFailure { kind }),
    }
}

crate::family_failures!(NativePowerFailureKind, "power", {
    InvalidRequest => InvalidRequest,
    Busy => Busy,
    Canceled => Canceled,
    TimedOut => TimedOut,
    Stale => Stale,
    Git => Git,
    Read => Read,
    TooLarge => TooLarge,
});

#[cfg(test)]
mod outcome_tests {
    use super::*;

    #[test]
    fn an_uncertain_bisect_step_stays_uncertain() {
        assert_eq!(
            native_bisect_state(MutationState::OutcomeUncertain),
            NativeBisectExecutionState::OutcomeUncertain
        );
    }
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::{power_tools::*, session::*};

    use crate::power_tools::{
        NativeBisectAction, NativeBisectExecutionState, NativeDiffSearchOptions,
        NativeDiffSearchScope, NativePowerFailureKind, NativePowerJobState,
        NativeSearchCompleteness,
    };

    use devmil_git::RepositoryOptions;

    use std::fs;

    #[cfg(unix)]
    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::os::unix::fs::PermissionsExt;

    #[allow(unused_imports)] // Only some platforms' tests use it.
    use std::process::Command;

    use std::time::Duration;
    use std::time::Instant;

    #[test]
    fn power_tools_bound_search_report_statistics_and_resume_bisect_after_restart() {
        let fixture = GitFixture::new();
        let mut commits = Vec::new();
        for index in 0..6 {
            fs::write(
                fixture.0.join("tracked.txt"),
                format!("line {index} searchable-needle\n"),
            )
            .unwrap();
            transfer_git(&fixture.0, &["add", "tracked.txt"]);
            transfer_git(&fixture.0, &["commit", "-qm", &format!("commit {index}")]);
            commits.push(
                String::from_utf8(transfer_git(&fixture.0, &["rev-parse", "HEAD"]))
                    .unwrap()
                    .trim()
                    .to_owned(),
            );
        }
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_225,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);

        let search = repository_session_diff_content_search_start(
            session.session_id,
            session.generation,
            "searchable-needle".to_owned(),
            3,
        )
        .token
        .unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let search = loop {
            let value = repository_session_diff_content_search_poll(
                session.session_id,
                session.generation,
                search,
            );
            if value.state != NativePowerJobState::Pending {
                break value;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        };
        assert_eq!(search.state, NativePowerJobState::Completed);
        assert_eq!(search.examined_commits, 3);
        assert_eq!(
            search.completeness,
            Some(NativeSearchCompleteness::CommitLimitReached)
        );

        let configured = repository_session_diff_content_search_start_configured(
            session.session_id,
            session.generation,
            NativeDiffSearchOptions {
                query: "SEARCHABLE-NEEDLE".to_owned(),
                maximum_commits: 10_000,
                case_sensitive: true,
                scope: NativeDiffSearchScope::CurrentBranch,
                other_refs: false,
            },
        )
        .token
        .unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let configured = loop {
            let value = repository_session_diff_content_search_poll(
                session.session_id,
                session.generation,
                configured,
            );
            if value.state != NativePowerJobState::Pending {
                break value;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        };
        assert_eq!(configured.state, NativePowerJobState::Completed);
        assert!(configured.matches.is_empty());

        let statistics =
            repository_session_statistics_start(session.session_id, session.generation)
                .token
                .unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let statistics = loop {
            let value = repository_session_statistics_poll(
                session.session_id,
                session.generation,
                statistics,
            );
            if value.state != NativePowerJobState::Pending {
                break value;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        };
        assert_eq!(statistics.state, NativePowerJobState::Completed);
        assert_eq!(statistics.commit_count, 6);
        assert_eq!(statistics.local_branch_count, 1);

        let saturated = ["line", "searchable", "needle", "commit"]
            .into_iter()
            .map(|query| {
                repository_session_diff_content_search_start(
                    session.session_id,
                    session.generation,
                    query.to_owned(),
                    10_000,
                )
                .token
                .unwrap()
            })
            .collect::<Vec<_>>();
        let mut interaction_samples = Vec::new();
        for _ in 0..100 {
            let started = Instant::now();
            let events = repository_session_events(session.session_id, session.generation, 32);
            assert!(events.failure.is_none());
            interaction_samples.push(started.elapsed().as_nanos());
        }
        interaction_samples.sort_unstable();
        let p95 = interaction_samples[94];
        let maximum = *interaction_samples.last().unwrap();
        eprintln!(
            "power_tools_foreground_events_ns count=100 p95={p95} max={maximum} samples={interaction_samples:?}"
        );
        assert!(p95 < 50_000_000, "foreground event drain p95 was {p95} ns");
        for token in saturated {
            assert!(
                repository_session_power_job_cancel(session.session_id, session.generation, token,)
                    .accepted
            );
        }

        let canceled = repository_session_diff_content_search_start(
            session.session_id,
            session.generation,
            "line".to_owned(),
            10_000,
        )
        .token
        .unwrap();
        assert!(
            repository_session_power_job_cancel(session.session_id, session.generation, canceled,)
                .accepted
        );
        assert_eq!(
            repository_session_diff_content_search_poll(
                session.session_id,
                session.generation,
                canceled,
            )
            .failure
            .unwrap()
            .kind,
            NativePowerFailureKind::InvalidRequest
        );

        let start = repository_session_bisect_preview(
            session.session_id,
            session.generation,
            NativeBisectAction::Start,
            Some(commits[0].clone()),
            Some(commits[5].clone()),
        )
        .preview
        .unwrap();
        assert_eq!(
            start.arguments,
            vec!["bisect", "start", commits[5].as_str(), commits[0].as_str()]
        );
        let started =
            repository_session_bisect_execute(session.session_id, session.generation, start.token);
        assert_eq!(started.state, NativeBisectExecutionState::Completed);
        assert!(started.bisect.unwrap().active);
        let closed_job = repository_session_diff_content_search_start(
            session.session_id,
            session.generation,
            "searchable-needle".to_owned(),
            10_000,
        )
        .token
        .unwrap();
        assert!(repository_session_close(session.session_id, session.generation).accepted);
        assert_eq!(
            repository_session_diff_content_search_poll(
                session.session_id,
                session.generation,
                closed_job,
            )
            .failure
            .unwrap()
            .kind,
            NativePowerFailureKind::Stale
        );

        let reopened = repository_session_open_with_options(
            fixture.0.clone(),
            1_226,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&reopened);
        let resumed = repository_session_bisect_state(reopened.session_id, reopened.generation)
            .state
            .unwrap();
        assert!(resumed.active);
        assert_eq!(resumed.original_head.as_deref(), Some(commits[5].as_str()));
        let mut skipped_all = false;
        for _ in 0..16 {
            let state = repository_session_bisect_state(reopened.session_id, reopened.generation)
                .state
                .unwrap();
            if !state.active {
                break;
            }
            let skipped = repository_session_bisect_preview(
                reopened.session_id,
                reopened.generation,
                NativeBisectAction::Skip,
                None,
                None,
            )
            .preview
            .unwrap();
            let result = repository_session_bisect_execute(
                reopened.session_id,
                reopened.generation,
                skipped.token,
            );
            if result.state == NativeBisectExecutionState::Failed {
                assert_eq!(result.failure.unwrap().kind, NativePowerFailureKind::Git);
                assert!(result.bisect.unwrap().active);
                skipped_all = true;
                break;
            }
            assert_eq!(result.state, NativeBisectExecutionState::Completed);
        }
        assert!(
            skipped_all,
            "skipping every candidate must remain recoverable"
        );
        let reset = repository_session_bisect_preview(
            reopened.session_id,
            reopened.generation,
            NativeBisectAction::Reset,
            None,
            None,
        )
        .preview
        .unwrap();
        let reset = repository_session_bisect_execute(
            reopened.session_id,
            reopened.generation,
            reset.token,
        );
        assert_eq!(reset.state, NativeBisectExecutionState::Completed);
        assert!(!reset.bisect.unwrap().active);
        assert!(repository_session_close(reopened.session_id, reopened.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn power_search_rejects_malformed_commit_enumeration() {
        use std::os::unix::fs::PermissionsExt;

        let fixture = GitFixture::new();
        fs::write(fixture.0.join("tracked.txt"), b"searchable\n").unwrap();
        transfer_git(&fixture.0, &["add", "tracked.txt"]);
        transfer_git(&fixture.0, &["commit", "-qm", "base"]);
        let wrapper = fixture.0.join("malformed-git");
        let git = Command::new("which").arg("git").output().unwrap();
        assert!(git.status.success());
        let git = String::from_utf8(git.stdout).unwrap();
        let git = git.trim().replace('\'', "'\\''");
        fs::write(
            &wrapper,
            format!(
                "#!/bin/sh\nif [ \"$1\" = \"rev-list\" ]; then printf 'not-an-object-id\\n'; exit 0; fi\nexec '{git}' \"$@\"\n"
            ),
        )
        .unwrap();
        fs::set_permissions(&wrapper, fs::Permissions::from_mode(0o700)).unwrap();
        let session = repository_session_open_with_options(
            fixture.0.clone(),
            1_227,
            RepositoryOptions {
                git_executable: wrapper.into_os_string(),
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let token = repository_session_diff_content_search_start(
            session.session_id,
            session.generation,
            "searchable".to_owned(),
            10_000,
        )
        .token
        .unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let result = loop {
            let value = repository_session_diff_content_search_poll(
                session.session_id,
                session.generation,
                token,
            );
            if value.state != NativePowerJobState::Pending {
                break value;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(10));
        };
        assert_eq!(result.state, NativePowerJobState::Failed);
        assert_eq!(result.failure.unwrap().kind, NativePowerFailureKind::Read);
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }
}
