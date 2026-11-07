//! Loading pull requests, issues and checks into the cache.
#![allow(clippy::wildcard_imports)]
use super::*;

#[allow(clippy::too_many_arguments)]
pub(super) fn run_resource_load(
    request_id: u64,
    connection: NativeHostingConnection,
    repository_id: String,
    page: u32,
    change_generation: u64,
    issue_generation: u64,
    cancellation: Arc<AtomicBool>,
    cache: &HostingCache,
    sessions: &Mutex<HashMap<u64, ResourceSession>>,
) {
    if cancellation.load(Ordering::Acquire) {
        publish_resource_canceled(sessions, request_id);
        return;
    }
    let result = load_credential(&connection, cancellation.as_ref())
        .map_err(map_credential_failure)
        .and_then(|envelope| {
            let credential = HostingCredential::new(envelope.access_token().to_vec())
                .map_err(|_| NativeHostingResourceFailure::CredentialUnreadable)?;
            let requester = CurlTransport { page };
            load_resources_with(
                &requester,
                &to_shared(&connection),
                &repository_id,
                &credential,
                cancellation.as_ref(),
            )
        });
    if cancellation.load(Ordering::Acquire) {
        publish_resource_canceled(sessions, request_id);
        return;
    }
    match result {
        Ok((resources, has_more)) => {
            if page == 1 {
                let changes = NativeHostingResources {
                    change_requests: resources.change_requests.clone(),
                    issues: Vec::new(),
                    remote_references: resources
                        .remote_references
                        .iter()
                        .filter(|reference| {
                            reference.kind == NativeHostingRemoteReferenceKind::ChangeRequest
                        })
                        .cloned()
                        .collect(),
                };
                let issues = NativeHostingResources {
                    change_requests: Vec::new(),
                    issues: resources.issues.clone(),
                    remote_references: resources
                        .remote_references
                        .iter()
                        .filter(|reference| {
                            reference.kind == NativeHostingRemoteReferenceKind::Issue
                        })
                        .cloned()
                        .collect(),
                };
                if !cache.publish(
                    &connection.id,
                    &repository_id,
                    HostingCacheClass::ChangeRequests,
                    change_generation,
                    changes,
                ) || !cache.publish(
                    &connection.id,
                    &repository_id,
                    HostingCacheClass::Issues,
                    issue_generation,
                    issues,
                ) {
                    publish_resource_canceled(sessions, request_id);
                    return;
                }
            }
            if let Some(session) = sessions
                .lock()
                .expect("hosting resource sessions lock")
                .get_mut(&request_id)
            {
                session.snapshot.state = NativeHostingResourceLoadState::Ready;
                session.snapshot.resources = resources;
                session.snapshot.stale = false;
                session.snapshot.has_more = has_more;
                session.snapshot.failure = None;
            }
        }
        Err(failure) => {
            if let Some(session) = sessions
                .lock()
                .expect("hosting resource sessions lock")
                .get_mut(&request_id)
            {
                session.snapshot.state = NativeHostingResourceLoadState::Failed;
                session.snapshot.failure = Some(failure);
            }
        }
    }
}

pub(super) fn publish_resource_canceled(
    sessions: &Mutex<HashMap<u64, ResourceSession>>,
    request_id: u64,
) {
    if let Some(session) = sessions
        .lock()
        .expect("hosting resource sessions lock")
        .get_mut(&request_id)
    {
        session.snapshot.state = NativeHostingResourceLoadState::Canceled;
        session.snapshot.failure = None;
    }
}

pub(super) fn cached_resources(
    cache: &HostingCache,
    connection_id: &str,
    repository_id: &str,
) -> Option<(NativeHostingResources, bool)> {
    let now = Instant::now();
    let changes = cache.lookup(
        connection_id,
        repository_id,
        HostingCacheClass::ChangeRequests,
        now,
    );
    let issues = cache.lookup(connection_id, repository_id, HostingCacheClass::Issues, now);
    if changes.is_none() && issues.is_none() {
        return None;
    }
    let mut resources = crate::hosting::empty_resources();
    let mut stale = false;
    if let Some(changes) = changes {
        resources.change_requests = changes.resources.change_requests;
        resources
            .remote_references
            .extend(changes.resources.remote_references);
        stale |= changes.stale;
    }
    if let Some(issues) = issues {
        resources.issues = issues.resources.issues;
        resources
            .remote_references
            .extend(issues.resources.remote_references);
        stale |= issues.stale;
    }
    Some((resources, stale))
}

pub(super) fn load_resources_with(
    requester: &dyn HostingProviderRequester,
    connection: &HostingConnection,
    repository_id: &str,
    credential: &HostingCredential,
    cancellation: &dyn Cancellation,
) -> Result<(NativeHostingResources, bool), NativeHostingResourceFailure> {
    let repository = HostingRepositoryId::new(repository_id.to_owned())
        .map_err(|_| NativeHostingResourceFailure::InvalidRequest)?;
    let plugin = provider_plugin(connection.provider());
    let pulls = if connection
        .capabilities
        .supports(HostingCapability::ChangeRequests)
    {
        plugin
            .pull_requests(requester, connection, &repository, credential, cancellation)
            .map_err(map_resource_error)?
    } else {
        Vec::new()
    };
    let issues = if connection.capabilities.supports(HostingCapability::Issues) {
        plugin
            .issues(requester, connection, &repository, credential, cancellation)
            .map_err(map_resource_error)?
    } else {
        Vec::new()
    };
    let has_more = pulls.len() == HOSTING_PAGE_CAPACITY || issues.len() == HOSTING_PAGE_CAPACITY;
    let mut resources = NativeHostingResources {
        change_requests: pulls
            .into_iter()
            .map(|pull| map_pull_request(repository_id, pull))
            .collect(),
        issues: issues.into_iter().map(map_issue).collect(),
        remote_references: Vec::new(),
    };
    resources
        .remote_references
        .extend(
            resources
                .change_requests
                .iter()
                .map(|pull| NativeHostingRemoteReference {
                    stable_id: pull.stable_id.clone(),
                    kind: NativeHostingRemoteReferenceKind::ChangeRequest,
                    number: pull.number,
                    title: pull.title.clone(),
                    insertion: format!("#{}", pull.number),
                    web_url: pull.web_url.clone(),
                }),
        );
    resources
        .remote_references
        .extend(
            resources
                .issues
                .iter()
                .map(|issue| NativeHostingRemoteReference {
                    stable_id: issue.stable_id.clone(),
                    kind: NativeHostingRemoteReferenceKind::Issue,
                    number: issue.number,
                    title: issue.title.clone(),
                    insertion: format!("#{}", issue.number),
                    web_url: issue.web_url.clone(),
                }),
        );
    Ok((resources, has_more))
}

pub(super) fn map_pull_request(
    repository_id: &str,
    pull: devmil_git::hosting::HostingPullRequest,
) -> NativeHostingChangeRequest {
    let source_repository = pull
        .source_repository
        .as_ref()
        .map_or_else(String::new, |repository| repository.as_str().to_owned());
    let target_repository = pull.target_repository.as_ref().map_or_else(
        || repository_id.to_owned(),
        |repository| repository.as_str().to_owned(),
    );
    NativeHostingChangeRequest {
        stable_id: pull.web_url.clone(),
        number: pull.number,
        title: pull.title,
        author: pull.author,
        state: match pull.state {
            PullRequestState::Open | PullRequestState::Draft => {
                NativeHostingChangeRequestState::Open
            }
            PullRequestState::Merged => NativeHostingChangeRequestState::Merged,
            PullRequestState::Closed => NativeHostingChangeRequestState::Closed,
        },
        draft: pull.state == PullRequestState::Draft,
        source_repository,
        source_branch: pull.source_branch,
        target_repository,
        target_branch: pull.target_branch,
        head_sha: pull.head_sha,
        web_url: pull.web_url,
        review_summary: NativeHostingReviewSummary::Unknown,
        mergeability: match pull.mergeability {
            Mergeability::Mergeable => NativeHostingMergeability::Mergeable,
            Mergeability::Conflicting => NativeHostingMergeability::Conflicting,
            Mergeability::Checking => NativeHostingMergeability::Checking,
            Mergeability::Unknown => NativeHostingMergeability::Unknown,
        },
        checks: NativeHostingCheckSummary {
            state: map_ci_state(pull.ci_status),
            checks: Vec::new(),
        },
    }
}

pub(super) fn map_issue(issue: devmil_git::hosting::HostingIssue) -> NativeHostingIssue {
    NativeHostingIssue {
        stable_id: issue.web_url.clone(),
        number: issue.number,
        title: issue.title,
        state: match issue.state {
            IssueState::Open => NativeHostingIssueState::Open,
            IssueState::Closed => NativeHostingIssueState::Closed,
        },
        author: issue.author,
        assignees: Vec::new(),
        labels: Vec::new(),
        private: false,
        updated_at: String::new(),
        web_url: issue.web_url,
    }
}

pub(super) const fn map_ci_state(status: CiStatus) -> NativeHostingCheckState {
    match status {
        CiStatus::Pending => NativeHostingCheckState::Pending,
        CiStatus::Passing => NativeHostingCheckState::Passing,
        CiStatus::Failing => NativeHostingCheckState::Failing,
        CiStatus::Canceled => NativeHostingCheckState::Canceled,
        CiStatus::Unknown => NativeHostingCheckState::Unknown,
    }
}

pub(super) fn map_credential_failure(failure: CredentialLoadError) -> NativeHostingResourceFailure {
    use crate::hosting::CredentialFailure;
    match failure.classify() {
        CredentialFailure::Missing => NativeHostingResourceFailure::CredentialMissing,
        CredentialFailure::Expired => NativeHostingResourceFailure::CredentialExpired,
        CredentialFailure::Unreadable => NativeHostingResourceFailure::CredentialUnreadable,
        CredentialFailure::Invalid => NativeHostingResourceFailure::InvalidRequest,
        CredentialFailure::Refresh(error) => map_resource_error(error),
    }
}

pub(super) fn map_resource_error(error: HostingError) -> NativeHostingResourceFailure {
    match error {
        HostingError::Unauthorized => NativeHostingResourceFailure::Unauthorized,
        HostingError::PermissionDenied => NativeHostingResourceFailure::PermissionDenied,
        HostingError::RateLimited => NativeHostingResourceFailure::RateLimited,
        HostingError::MalformedResponse => NativeHostingResourceFailure::MalformedResponse,
        HostingError::Canceled => NativeHostingResourceFailure::Unavailable,
        HostingError::InvalidIdentity
        | HostingError::InvalidAccount
        | HostingError::InvalidCredential => NativeHostingResourceFailure::InvalidRequest,
        HostingError::CredentialUnavailable => NativeHostingResourceFailure::CredentialUnreadable,
        HostingError::Unavailable(reason) => match TransportFailure::from_reason(&reason) {
            Some(TransportFailure::NotFound) => NativeHostingResourceFailure::NotFound,
            Some(TransportFailure::Redirected) => NativeHostingResourceFailure::Redirected,
            Some(TransportFailure::ServerError) => NativeHostingResourceFailure::ServerError,
            Some(TransportFailure::Network) => NativeHostingResourceFailure::Network,
            Some(TransportFailure::Certificate) => NativeHostingResourceFailure::Certificate,
            Some(TransportFailure::TimedOut) => NativeHostingResourceFailure::TimedOut,
            None => NativeHostingResourceFailure::Unavailable,
        },
    }
}
