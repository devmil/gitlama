//! Session entry points of content search, statistics and bisect.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::dto::*;
use crate::power_tools::{
    NativeBisectAction, NativeBisectExecutionResult, NativeBisectExecutionState,
    NativeBisectPreviewResult, NativeBisectStateResult, NativeDiffContentSearchResult,
    NativeDiffSearchOptions, NativePowerFailure, NativePowerFailureKind, NativePowerJobStartResult,
    NativePowerJobState, NativeRepositoryStatisticsResult,
};

#[must_use]
pub fn repository_session_diff_content_search_start(
    session_id: u64,
    generation: u64,
    query: String,
    maximum_commits: u32,
) -> NativePowerJobStartResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativePowerJobStartResult {
            token: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    };
    crate::power_tools::start_search(session_id, &repository, query, maximum_commits)
}

#[must_use]
pub fn repository_session_diff_content_search_start_configured(
    session_id: u64,
    generation: u64,
    options: NativeDiffSearchOptions,
) -> NativePowerJobStartResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativePowerJobStartResult {
            token: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    };
    crate::power_tools::start_search_with_options(session_id, &repository, options)
}

#[must_use]
pub fn repository_session_diff_content_search_poll(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeDiffContentSearchResult {
    if repository_for_session(session_id, generation).is_err() {
        return NativeDiffContentSearchResult {
            state: NativePowerJobState::Failed,
            matches: Vec::new(),
            examined_commits: 0,
            completeness: None,
            activity_ids: Vec::new(),
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    }
    crate::power_tools::poll_search(session_id, token)
}

#[must_use]
pub fn repository_session_statistics_start(
    session_id: u64,
    generation: u64,
) -> NativePowerJobStartResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativePowerJobStartResult {
            token: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    };
    crate::power_tools::start_statistics(session_id, &repository)
}

#[must_use]
pub fn repository_session_statistics_poll(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryStatisticsResult {
    if repository_for_session(session_id, generation).is_err() {
        return NativeRepositoryStatisticsResult {
            state: NativePowerJobState::Failed,
            commit_count: 0,
            local_branch_count: 0,
            tag_count: 0,
            changed_path_count: 0,
            incomplete: false,
            activity_ids: Vec::new(),
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    }
    crate::power_tools::poll_statistics(session_id, token)
}

#[must_use]
pub fn repository_session_power_job_cancel(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::power_tools::cancel_job(session_id, token),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_bisect_state(
    session_id: u64,
    generation: u64,
) -> NativeBisectStateResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeBisectStateResult {
            state: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    };
    crate::power_tools::bisect_state(&repository)
}

#[must_use]
pub fn repository_session_bisect_preview(
    session_id: u64,
    generation: u64,
    action: NativeBisectAction,
    good: Option<String>,
    bad: Option<String>,
) -> NativeBisectPreviewResult {
    let Ok(repository) = repository_for_session(session_id, generation) else {
        return NativeBisectPreviewResult {
            preview: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    };
    crate::power_tools::preview_bisect(session_id, &repository, action, good, bad)
}

#[must_use]
pub fn repository_session_bisect_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeBisectExecutionResult {
    let Some((repository, activity)) = repository_and_activity(session_id, generation) else {
        return NativeBisectExecutionResult {
            state: NativeBisectExecutionState::Failed,
            bisect: None,
            activity_id: None,
            failure: Some(NativePowerFailure {
                kind: NativePowerFailureKind::Stale,
            }),
        };
    };
    crate::power_tools::execute_bisect(session_id, token, &repository, &activity)
}

#[must_use]
pub fn repository_session_bisect_cancel_preview(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRepositoryCommandResult {
    if repository_for_session(session_id, generation).is_err() {
        return command_failure(NativeRepositoryFailureKind::StaleGeneration);
    }
    NativeRepositoryCommandResult {
        accepted: crate::power_tools::cancel_bisect_preview(session_id, token),
        failure: None,
    }
}
