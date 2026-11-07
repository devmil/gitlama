//! Authorized hosting review loading, previews, submission, reconciliation, and drafts.
pub use gitlama_contract::hosting_review::*;

use crate::hosting::NativeHostingCheckState;
use crate::hosting::{to_shared, CredentialLoadError, NativeHostingCheck, NativeHostingConnection};
use crate::hosting_runtime::load_credential;
use devmil_git::activity::ActivityStatus;
use devmil_git::cancellation::Cancellation;
use devmil_git::hosting::model::{
    HostingCapability, HostingError, HostingProvider, HostingRepositoryId,
};
use devmil_git::hosting::providers::{provider_plugin, HostingProviderPlugin};
use devmil_git::hosting::rest::{rerun_in_progress, HostingCheckState};
use devmil_git::hosting::review::{
    curl_command, parse_curl_result, ReviewAction, ReviewClient, ReviewDiffRow, ReviewHttpMethod,
    ReviewHttpRequest, ReviewHttpResponse, ReviewInlineComment, ReviewScope, ReviewThread,
};
use devmil_git::process::ActivityGitRunner;
use devmil_git::types::ObjectId;
use gitlama_application::activity::allocate_activity_id;
use serde::{Deserialize, Serialize};
use std::cell::Cell;
use std::collections::HashMap;
#[cfg(unix)]
use std::fs::File;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

const MAX_ANCHORS: usize = 5_000;
const MAX_DRAFTS: usize = 128;
const MAX_DRAFT_DOCUMENT: usize = 2 * 1024 * 1024;
const AUTHORIZATION_LIFETIME: Duration = Duration::from_secs(10 * 60);

#[derive(Clone, Debug, Eq, PartialEq)]
struct AuthorizationScope {
    connection_id: String,
    repository: String,
    pull_request: u64,
    head_sha: String,
    action: NativeHostingReviewAction,
    body: String,
    inline_comments: Vec<NativeHostingInlineDraft>,
    target: String,
    payload: Vec<u8>,
}

struct Authorization {
    scope: AuthorizationScope,
    expires: Instant,
}

static NEXT_AUTHORIZATION: AtomicU64 = AtomicU64::new(1);
static AUTHORIZATIONS: OnceLock<Mutex<HashMap<u64, Authorization>>> = OnceLock::new();
static CHECK_AUTHORIZATIONS: OnceLock<Mutex<HashMap<u64, Authorization>>> = OnceLock::new();
static REVIEW_CANCELLATIONS: OnceLock<Mutex<HashMap<String, Arc<AtomicBool>>>> = OnceLock::new();
static DRAFT_IO_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn authorizations() -> &'static Mutex<HashMap<u64, Authorization>> {
    AUTHORIZATIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn check_authorizations() -> &'static Mutex<HashMap<u64, Authorization>> {
    CHECK_AUTHORIZATIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn cancellations() -> &'static Mutex<HashMap<String, Arc<AtomicBool>>> {
    REVIEW_CANCELLATIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn draft_io_lock() -> &'static Mutex<()> {
    DRAFT_IO_LOCK.get_or_init(|| Mutex::new(()))
}

fn cancellation_key(connection_id: &str, repository: &str, pull_request: u64) -> String {
    format!(
        "{}:{connection_id}{}:{repository}:{pull_request}",
        connection_id.len(),
        repository.len()
    )
}

fn begin_request(key: &str) -> Arc<AtomicBool> {
    let cancellation = Arc::new(AtomicBool::new(false));
    if let Some(previous) = cancellations()
        .lock()
        .expect("review cancellation lock")
        .insert(key.to_owned(), Arc::clone(&cancellation))
    {
        previous.store(true, Ordering::Release);
    }
    cancellation
}

fn finish_request(key: &str, cancellation: &Arc<AtomicBool>) {
    let mut guard = cancellations().lock().expect("review cancellation lock");
    if guard
        .get(key)
        .is_some_and(|current| Arc::ptr_eq(current, cancellation))
    {
        guard.remove(key);
    }
}

pub fn review_cancel(connection_id: String, repository: String, pull_request: u64) -> bool {
    let key = cancellation_key(&connection_id, &repository, pull_request);
    let cancellation = cancellations()
        .lock()
        .expect("review cancellation lock")
        .remove(&key);
    if let Some(cancellation) = cancellation {
        cancellation.store(true, Ordering::Release);
        true
    } else {
        false
    }
}

fn shared_scope(
    connection: &NativeHostingConnection,
    repository: &str,
    pull_request: u64,
    head_sha: &str,
    action: NativeHostingReviewAction,
    body: &str,
    inline_comments: &[NativeHostingInlineDraft],
) -> Result<ReviewScope, NativeHostingReviewFailure> {
    let shared = to_shared(connection);
    let repository = HostingRepositoryId::new(repository.to_owned())
        .map_err(|_| NativeHostingReviewFailure::InvalidRequest)?;
    let scope = ReviewScope {
        account: shared.id,
        repository,
        pull_request,
        head_sha: head_sha.to_owned(),
        action: match action {
            NativeHostingReviewAction::Comment => ReviewAction::Comment,
            NativeHostingReviewAction::Approve => ReviewAction::Approve,
            NativeHostingReviewAction::RequestChanges => ReviewAction::RequestChanges,
        },
        body: body.to_owned(),
        inline_comments: inline_comments
            .iter()
            .map(|comment| ReviewInlineComment {
                stable_id: comment.stable_id.clone(),
                path: comment.path.clone(),
                line: comment.line,
                body: comment.body.clone(),
            })
            .collect(),
    };
    scope
        .validate()
        .map_err(|_| NativeHostingReviewFailure::InvalidRequest)?;
    Ok(scope)
}

fn validate_connection(
    connection: NativeHostingConnection,
) -> Result<NativeHostingConnection, NativeHostingReviewFailure> {
    let Some(connection) = crate::hosting::validate_native_connection(connection).connection else {
        return Err(NativeHostingReviewFailure::InvalidRequest);
    };
    let shared = to_shared(&connection);
    if !shared.enabled {
        return Err(NativeHostingReviewFailure::IntegrationDisabled);
    }
    if !shared
        .capabilities
        .supports(HostingCapability::ChangeRequestReview)
    {
        return Err(NativeHostingReviewFailure::Unsupported);
    }
    Ok(connection)
}

pub fn review_load(
    connection: NativeHostingConnection,
    repository: String,
    pull_request: u64,
    head_sha: String,
    page: Option<String>,
) -> NativeHostingReviewLoadResult {
    let connection = match validate_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => return load_failure(failure),
    };
    let key = cancellation_key(&connection.id, &repository, pull_request);
    let cancellation = begin_request(&key);
    let envelope = match load_credential(&connection, cancellation.as_ref()) {
        Ok(envelope) => envelope,
        Err(failure) => {
            finish_request(&key, &cancellation);
            return load_failure(map_credential_failure(failure));
        }
    };
    let uncertain = Cell::new(false);
    let mut transport = CurlReviewTransport {
        connection: &connection,
        credential: envelope.access_token(),
        uncertain: &uncertain,
        cancellation: cancellation.as_ref(),
    };
    let result = review_load_with(
        &connection,
        repository,
        pull_request,
        head_sha,
        page,
        cancellation.as_ref(),
        &mut |request| transport.execute(request),
    );
    finish_request(&key, &cancellation);
    result
}

fn review_load_with(
    connection: &NativeHostingConnection,
    repository: String,
    pull_request: u64,
    head_sha: String,
    page: Option<String>,
    cancellation: &dyn Cancellation,
    execute: &mut dyn FnMut(&ReviewHttpRequest) -> Result<ReviewHttpResponse, HostingError>,
) -> NativeHostingReviewLoadResult {
    let scope = match shared_scope(
        connection,
        &repository,
        pull_request,
        &head_sha,
        NativeHostingReviewAction::Comment,
        "",
        &[],
    ) {
        Ok(scope) => scope,
        Err(failure) => return load_failure(failure),
    };
    let shared = to_shared(connection);
    let provider = shared.provider();
    let client = ReviewClient::new(shared.id, provider);
    match load_remote_head(connection, &repository, pull_request, execute) {
        Ok(remote_head) if remote_head != head_sha => {
            return load_failure(NativeHostingReviewFailure::MovedBase);
        }
        Ok(_) => {}
        Err(failure) => return load_failure(failure),
    }
    match client.load(&scope, page.as_deref(), cancellation, execute) {
        Ok(page) if page.scope.head_sha == head_sha => {
            let checks = match load_checks(connection, &repository, &head_sha, execute) {
                Ok(checks) => checks,
                Err(failure) => return load_failure(failure),
            };
            let mut mapped = map_page(connection, repository, page);
            mapped.checks = checks;
            NativeHostingReviewLoadResult {
                page: Some(mapped),
                failure: None,
            }
        }
        Ok(_) => load_failure(NativeHostingReviewFailure::MovedBase),
        Err(error) => load_failure(map_error(error)),
    }
}

/// The connection, repository and provider unit of a review; Forgejo has no review support.
fn review_target(
    connection: &NativeHostingConnection,
    repository: &str,
) -> Result<
    (
        devmil_git::hosting::model::HostingConnection,
        HostingRepositoryId,
        &'static dyn HostingProviderPlugin,
    ),
    NativeHostingReviewFailure,
> {
    let shared = to_shared(connection);
    if shared.provider() == HostingProvider::Forgejo {
        return Err(NativeHostingReviewFailure::Unsupported);
    }
    let repository = HostingRepositoryId::new(repository.to_owned())
        .map_err(|_| NativeHostingReviewFailure::InvalidRequest)?;
    let plugin = provider_plugin(shared.provider());
    Ok((shared, repository, plugin))
}

fn load_remote_head(
    connection: &NativeHostingConnection,
    repository: &str,
    pull_request: u64,
    execute: &mut dyn FnMut(&ReviewHttpRequest) -> Result<ReviewHttpResponse, HostingError>,
) -> Result<String, NativeHostingReviewFailure> {
    let (_, repository, plugin) = review_target(connection, repository)?;
    let path = plugin
        .pull_request_head_path(&repository, pull_request)
        .map_err(map_error)?;
    let response = execute(&ReviewHttpRequest {
        method: ReviewHttpMethod::Get,
        path,
        body: Vec::new(),
    })
    .map_err(map_error)?;
    require_response_success(response.status)?;
    plugin
        .parse_pull_request_head(&response.body)
        .map(|head| head.as_str().to_owned())
        .map_err(map_error)
}

fn load_checks(
    connection: &NativeHostingConnection,
    repository: &str,
    head_sha: &str,
    execute: &mut dyn FnMut(&ReviewHttpRequest) -> Result<ReviewHttpResponse, HostingError>,
) -> Result<Vec<NativeHostingCheck>, NativeHostingReviewFailure> {
    let (shared, repository, plugin) = review_target(connection, repository)?;
    let head = ObjectId::parse(head_sha.to_owned())
        .map_err(|_| NativeHostingReviewFailure::InvalidRequest)?;
    let Some(path) = plugin
        .checks_path(&repository, &head, &shared.capabilities)
        .map_err(map_error)?
    else {
        return Ok(Vec::new());
    };
    let response = execute(&ReviewHttpRequest {
        method: ReviewHttpMethod::Get,
        path,
        body: Vec::new(),
    })
    .map_err(map_error)?;
    require_response_success(response.status)?;
    Ok(plugin
        .parse_checks(&response.body)
        .map_err(map_error)?
        .into_iter()
        .map(|check| NativeHostingCheck {
            stable_id: check.stable_id,
            name: check.name,
            state: map_check_state(check.state),
            conclusion: check.conclusion,
            details_url: check.details_url,
            updated_at: None,
        })
        .collect())
}

fn require_response_success(status: u16) -> Result<(), NativeHostingReviewFailure> {
    match status {
        200..=299 => Ok(()),
        401 => Err(NativeHostingReviewFailure::Unauthorized),
        403 => Err(NativeHostingReviewFailure::PermissionDenied),
        429 => Err(NativeHostingReviewFailure::RateLimited),
        _ => Err(NativeHostingReviewFailure::Unavailable),
    }
}

pub(crate) const fn map_check_state(state: HostingCheckState) -> NativeHostingCheckState {
    match state {
        HostingCheckState::Pending => NativeHostingCheckState::Pending,
        HostingCheckState::Passing => NativeHostingCheckState::Passing,
        HostingCheckState::Failing => NativeHostingCheckState::Failing,
        HostingCheckState::Canceled => NativeHostingCheckState::Canceled,
        HostingCheckState::Skipped => NativeHostingCheckState::Skipped,
        HostingCheckState::Unknown => NativeHostingCheckState::Unknown,
    }
}

pub fn check_retry_preview(
    connection: NativeHostingConnection,
    repository: String,
    head_sha: String,
    check_stable_id: String,
) -> NativeHostingCheckRetryPreviewResult {
    let connection = match validate_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => return check_preview_failure(failure),
    };
    if head_sha.len() != 40 || !head_sha.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return check_preview_failure(NativeHostingReviewFailure::InvalidRequest);
    }
    let (shared, repository_id, plugin) = match review_target(&connection, &repository) {
        Ok(value) => value,
        Err(failure) => return check_preview_failure(failure),
    };
    let target = match plugin.check_rerun(&repository_id, &check_stable_id, &shared.capabilities) {
        Ok(Some(rerun)) => rerun.path,
        Ok(None) => return check_preview_failure(NativeHostingReviewFailure::Unsupported),
        Err(_) => return check_preview_failure(NativeHostingReviewFailure::InvalidRequest),
    };
    let authorization_id = NEXT_AUTHORIZATION.fetch_add(1, Ordering::Relaxed);
    let authorization_scope = AuthorizationScope {
        connection_id: connection.id.clone(),
        repository: repository.clone(),
        pull_request: 0,
        head_sha: head_sha.clone(),
        action: NativeHostingReviewAction::Comment,
        body: check_stable_id.clone(),
        inline_comments: Vec::new(),
        target: target.clone(),
        payload: b"{}".to_vec(),
    };
    let mut authorizations = check_authorizations()
        .lock()
        .expect("check authorization lock");
    authorizations.retain(|_, authorization| authorization.expires > Instant::now());
    authorizations.insert(
        authorization_id,
        Authorization {
            scope: authorization_scope,
            expires: Instant::now() + AUTHORIZATION_LIFETIME,
        },
    );
    NativeHostingCheckRetryPreviewResult {
        preview: Some(NativeHostingCheckRetryPreview {
            authorization_id,
            target,
            payload: "{}".into(),
            connection_id: connection.id,
            repository,
            head_sha,
            check_stable_id,
        }),
        failure: None,
    }
}

pub fn check_retry_submit(
    connection: NativeHostingConnection,
    authorization_id: u64,
    repository: String,
    head_sha: String,
    check_stable_id: String,
) -> NativeHostingReviewSubmitResult {
    let preview = check_retry_preview(
        connection.clone(),
        repository.clone(),
        head_sha.clone(),
        check_stable_id.clone(),
    );
    let Some(generated) = preview.preview else {
        return submit_failure(
            preview
                .failure
                .unwrap_or(NativeHostingReviewFailure::InvalidRequest),
        );
    };
    check_authorizations()
        .lock()
        .expect("check authorization lock")
        .remove(&generated.authorization_id);
    let authorization = check_authorizations()
        .lock()
        .expect("check authorization lock")
        .remove(&authorization_id);
    let expected = AuthorizationScope {
        connection_id: connection.id.clone(),
        repository,
        pull_request: 0,
        head_sha,
        action: NativeHostingReviewAction::Comment,
        body: check_stable_id,
        inline_comments: Vec::new(),
        target: generated.target.clone(),
        payload: b"{}".to_vec(),
    };
    let Some(authorization) = authorization else {
        return submit_failure(NativeHostingReviewFailure::StaleAuthorization);
    };
    if authorization.expires <= Instant::now() || authorization.scope != expected {
        return submit_failure(NativeHostingReviewFailure::StaleAuthorization);
    }
    let cancellation = AtomicBool::new(false);
    let envelope = match load_credential(&connection, &cancellation) {
        Ok(envelope) => envelope,
        Err(failure) => return submit_failure(map_credential_failure(failure)),
    };
    let uncertain = Cell::new(false);
    let mut transport = CurlReviewTransport {
        connection: &connection,
        credential: envelope.access_token(),
        uncertain: &uncertain,
        cancellation: &cancellation,
    };
    match transport.execute(&ReviewHttpRequest {
        method: ReviewHttpMethod::Post,
        path: generated.target.clone(),
        body: b"{}".to_vec(),
    }) {
        Ok(response) => match require_response_success(response.status) {
            Ok(()) => NativeHostingReviewSubmitResult {
                state: NativeHostingReviewSubmitState::Submitted,
                failure: None,
            },
            Err(failure) => submit_failure(failure),
        },
        Err(_) if uncertain.get() => {
            let status_target = review_target(&connection, &expected.repository)
                .ok()
                .and_then(|(shared, repository, plugin)| {
                    plugin
                        .check_rerun(&repository, &expected.body, &shared.capabilities)
                        .ok()
                        .flatten()
                })
                .map(|rerun| rerun.status_path);
            let reconciled = status_target
                .and_then(|path| {
                    transport
                        .execute(&ReviewHttpRequest {
                            method: ReviewHttpMethod::Get,
                            path,
                            body: Vec::new(),
                        })
                        .ok()
                })
                .filter(|response| (200..300).contains(&response.status))
                .is_some_and(|response| rerun_in_progress(&response.body));
            if reconciled {
                NativeHostingReviewSubmitResult {
                    state: NativeHostingReviewSubmitState::Reconciled,
                    failure: None,
                }
            } else {
                NativeHostingReviewSubmitResult {
                    state: NativeHostingReviewSubmitState::Uncertain,
                    failure: Some(NativeHostingReviewFailure::Uncertain),
                }
            }
        }
        Err(error) => submit_failure(map_error(error)),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn review_preview(
    connection: NativeHostingConnection,
    repository: String,
    pull_request: u64,
    head_sha: String,
    action: NativeHostingReviewAction,
    body: String,
    inline_comments: Vec<NativeHostingInlineDraft>,
) -> NativeHostingReviewPreviewResult {
    let connection = match validate_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => return preview_failure(failure),
    };
    let scope = match shared_scope(
        &connection,
        &repository,
        pull_request,
        &head_sha,
        action,
        &body,
        &inline_comments,
    ) {
        Ok(scope) => scope,
        Err(failure) => return preview_failure(failure),
    };
    let shared = to_shared(&connection);
    let provider = shared.provider();
    if matches!(provider, HostingProvider::Forgejo)
        || (matches!(provider, HostingProvider::GitLab)
            && (action == NativeHostingReviewAction::RequestChanges || !inline_comments.is_empty()))
    {
        return preview_failure(NativeHostingReviewFailure::Unsupported);
    }
    let client = ReviewClient::new(shared.id, provider);
    let request = match client.submission_request(&scope) {
        Ok(request) => request,
        Err(error) => return preview_failure(map_error(error)),
    };
    let authorization_id = NEXT_AUTHORIZATION.fetch_add(1, Ordering::Relaxed);
    let authorization_scope = AuthorizationScope {
        connection_id: connection.id.clone(),
        repository: repository.clone(),
        pull_request,
        head_sha: head_sha.clone(),
        action,
        body: body.clone(),
        inline_comments: inline_comments.clone(),
        target: request.path.clone(),
        payload: request.body.clone(),
    };
    let mut guard = authorizations().lock().expect("review authorization lock");
    guard.retain(|_, authorization| authorization.expires > Instant::now());
    guard.insert(
        authorization_id,
        Authorization {
            scope: authorization_scope,
            expires: Instant::now() + AUTHORIZATION_LIFETIME,
        },
    );
    NativeHostingReviewPreviewResult {
        preview: Some(NativeHostingReviewPreview {
            authorization_id,
            target: request.path,
            payload: String::from_utf8(request.body).unwrap_or_default(),
            connection_id: connection.id,
            repository,
            pull_request,
            head_sha,
            action,
            body,
            inline_comments,
        }),
        failure: None,
    }
}

#[allow(clippy::too_many_arguments)]
pub fn review_submit(
    connection: NativeHostingConnection,
    preview: NativeHostingReviewPreview,
) -> NativeHostingReviewSubmitResult {
    let connection = match validate_connection(connection) {
        Ok(connection) => connection,
        Err(failure) => return submit_failure(failure),
    };
    let scope = match take_review_authorization(
        &connection,
        preview.authorization_id,
        &preview.repository,
        preview.pull_request,
        &preview.head_sha,
        preview.action,
        &preview.body,
        &preview.inline_comments,
    ) {
        Ok(scope) => scope,
        Err(failure) => return submit_failure(failure),
    };
    let key = cancellation_key(&connection.id, &preview.repository, preview.pull_request);
    let cancellation = begin_request(&key);
    let envelope = match load_credential(&connection, cancellation.as_ref()) {
        Ok(envelope) => envelope,
        Err(failure) => {
            finish_request(&key, &cancellation);
            return submit_failure(map_credential_failure(failure));
        }
    };
    let uncertain = Cell::new(false);
    let mut submit_transport = CurlReviewTransport {
        connection: &connection,
        credential: envelope.access_token(),
        uncertain: &uncertain,
        cancellation: cancellation.as_ref(),
    };
    let mut reconcile_transport = CurlReviewTransport {
        connection: &connection,
        credential: envelope.access_token(),
        uncertain: &uncertain,
        cancellation: cancellation.as_ref(),
    };
    let result = review_submit_authorized_with(
        &connection,
        &scope,
        preview.action,
        &preview.body,
        cancellation.as_ref(),
        &mut |request| submit_transport.execute(request),
        &mut |request| reconcile_transport.execute(request),
        &uncertain,
    );
    finish_request(&key, &cancellation);
    result
}

#[allow(clippy::too_many_arguments)]
#[cfg(test)]
fn review_submit_with(
    connection: &NativeHostingConnection,
    authorization_id: u64,
    repository: String,
    pull_request: u64,
    head_sha: String,
    action: NativeHostingReviewAction,
    body: String,
    inline_comments: Vec<NativeHostingInlineDraft>,
    cancellation: &dyn Cancellation,
    submit_execute: &mut dyn FnMut(&ReviewHttpRequest) -> Result<ReviewHttpResponse, HostingError>,
    reconcile_execute: &mut dyn FnMut(
        &ReviewHttpRequest,
    ) -> Result<ReviewHttpResponse, HostingError>,
    transport_uncertain: &Cell<bool>,
) -> NativeHostingReviewSubmitResult {
    let scope = match take_review_authorization(
        connection,
        authorization_id,
        &repository,
        pull_request,
        &head_sha,
        action,
        &body,
        &inline_comments,
    ) {
        Ok(scope) => scope,
        Err(failure) => return submit_failure(failure),
    };
    review_submit_authorized_with(
        connection,
        &scope,
        action,
        &body,
        cancellation,
        submit_execute,
        reconcile_execute,
        transport_uncertain,
    )
}

#[allow(clippy::too_many_arguments)]
fn take_review_authorization(
    connection: &NativeHostingConnection,
    authorization_id: u64,
    repository: &str,
    pull_request: u64,
    head_sha: &str,
    action: NativeHostingReviewAction,
    body: &str,
    inline_comments: &[NativeHostingInlineDraft],
) -> Result<ReviewScope, NativeHostingReviewFailure> {
    let scope = shared_scope(
        connection,
        repository,
        pull_request,
        head_sha,
        action,
        body,
        inline_comments,
    )?;
    let shared = to_shared(connection);
    let provider = shared.provider();
    let client = ReviewClient::new(shared.id, provider);
    let request = client.submission_request(&scope).map_err(map_error)?;
    let expected = AuthorizationScope {
        connection_id: connection.id.clone(),
        repository: repository.to_owned(),
        pull_request,
        head_sha: head_sha.to_owned(),
        action,
        body: body.to_owned(),
        inline_comments: inline_comments.to_vec(),
        target: request.path,
        payload: request.body,
    };
    let authorization = authorizations()
        .lock()
        .expect("review authorization lock")
        .remove(&authorization_id);
    let Some(authorization) = authorization else {
        return Err(NativeHostingReviewFailure::StaleAuthorization);
    };
    if authorization.expires <= Instant::now() || authorization.scope != expected {
        return Err(NativeHostingReviewFailure::StaleAuthorization);
    }
    Ok(scope)
}

#[allow(clippy::too_many_arguments)]
fn review_submit_authorized_with(
    connection: &NativeHostingConnection,
    scope: &ReviewScope,
    action: NativeHostingReviewAction,
    body: &str,
    cancellation: &dyn Cancellation,
    submit_execute: &mut dyn FnMut(&ReviewHttpRequest) -> Result<ReviewHttpResponse, HostingError>,
    reconcile_execute: &mut dyn FnMut(
        &ReviewHttpRequest,
    ) -> Result<ReviewHttpResponse, HostingError>,
    transport_uncertain: &Cell<bool>,
) -> NativeHostingReviewSubmitResult {
    let shared = to_shared(connection);
    let provider = shared.provider();
    let client = ReviewClient::new(shared.id, provider);
    match client.submit(scope, cancellation, submit_execute) {
        Ok(()) => NativeHostingReviewSubmitResult {
            state: NativeHostingReviewSubmitState::Submitted,
            failure: None,
        },
        Err(error)
            if transport_uncertain.get() || matches!(error, HostingError::Unavailable(_)) =>
        {
            let reconciled = client
                .load(scope, None, cancellation, reconcile_execute)
                .ok()
                .is_some_and(|page| {
                    action == NativeHostingReviewAction::Comment
                        && page.threads.iter().any(|thread| thread.body == body)
                });
            if reconciled {
                NativeHostingReviewSubmitResult {
                    state: NativeHostingReviewSubmitState::Reconciled,
                    failure: None,
                }
            } else {
                NativeHostingReviewSubmitResult {
                    state: NativeHostingReviewSubmitState::Uncertain,
                    failure: Some(NativeHostingReviewFailure::Uncertain),
                }
            }
        }
        Err(error) => submit_failure(map_error(error)),
    }
}

struct CurlReviewTransport<'a> {
    connection: &'a NativeHostingConnection,
    credential: &'a [u8],
    uncertain: &'a Cell<bool>,
    cancellation: &'a AtomicBool,
}

impl CurlReviewTransport<'_> {
    fn execute(&mut self, request: &ReviewHttpRequest) -> Result<ReviewHttpResponse, HostingError> {
        let shared = to_shared(self.connection);
        let command = curl_command(
            "curl".as_ref(),
            &shared.api_base_url,
            shared.provider(),
            request,
            self.credential,
            Duration::from_secs(20),
        )?;
        let mut discard = |_event| {};
        let result = ActivityGitRunner::run_private(
            command,
            allocate_activity_id(),
            Some(self.cancellation),
            &mut discard,
        );
        if request.method == ReviewHttpMethod::Post
            && matches!(result.activity.status, ActivityStatus::TimedOut { .. })
        {
            self.uncertain.set(true);
            return Err(HostingError::Unavailable("review result uncertain".into()));
        }
        parse_curl_result(result)
    }
}

fn map_page(
    connection: &NativeHostingConnection,
    repository: String,
    page: devmil_git::hosting::review::ReviewPage,
) -> NativeHostingReviewPage {
    let diffs = page
        .diffs
        .into_iter()
        .map(|diff| map_diff(&page.scope.head_sha, diff))
        .collect::<Vec<_>>();
    let anchors = diffs
        .iter()
        .flat_map(|diff| diff.anchors.iter())
        .map(|anchor| ((anchor.path.clone(), anchor.line), anchor.stable_id.clone()))
        .collect::<HashMap<_, _>>();
    let threads = page
        .threads
        .into_iter()
        .map(|thread| map_thread(thread, &anchors))
        .collect();
    NativeHostingReviewPage {
        connection_id: connection.id.clone(),
        repository,
        pull_request: page.scope.pull_request,
        head_sha: page.scope.head_sha,
        diffs,
        threads,
        checks: Vec::new(),
        next_page: page.next_page,
        incomplete: page.incomplete,
    }
}

fn map_diff(head_sha: &str, diff: ReviewDiffRow) -> NativeHostingReviewDiff {
    let anchors = patch_lines(&diff.patch)
        .into_iter()
        .take(MAX_ANCHORS)
        .map(|line| NativeHostingReviewAnchor {
            stable_id: format!("{head_sha}:{}:{line}", diff.path),
            path: diff.path.clone(),
            line,
        })
        .collect();
    NativeHostingReviewDiff {
        stable_id: diff.stable_id,
        path: diff.path,
        patch: diff.patch,
        anchors,
    }
}

fn map_thread(
    thread: ReviewThread,
    anchors: &HashMap<(String, u64), String>,
) -> NativeHostingReviewThread {
    let anchor_id = thread
        .path
        .as_ref()
        .zip(thread.line)
        .and_then(|(path, line)| anchors.get(&(path.clone(), line)).cloned());
    NativeHostingReviewThread {
        stable_id: thread.stable_id,
        path: thread.path,
        line: thread.line,
        outdated: anchor_id.is_none(),
        anchor_id,
        author: thread.author,
        body: thread.body,
        resolved: thread.resolved,
    }
}

/// The new-side line numbers a provider's per-file patch shows (context and added lines), in
/// order. Inside a hunk every `-` line is a deletion, even when its content starts with `--`.
fn patch_lines(patch: &str) -> Vec<u64> {
    let mut lines = Vec::new();
    let mut current = None;
    for line in patch.lines() {
        if line.starts_with("@@") {
            current = devmil_git::diff::parse_unified_hunk_header(line.as_bytes())
                .ok()
                .map(|header| u64::from(header.new_start));
            continue;
        }
        let Some(number) = current else { continue };
        if line.starts_with('-') || line.starts_with('\\') {
            continue;
        }
        lines.push(number);
        current = number.checked_add(1);
    }
    lines
}

#[derive(Default, Serialize, Deserialize)]
struct DraftDocument {
    drafts: Vec<NativeHostingReviewDraft>,
}

pub fn draft_load(key: String) -> NativeHostingReviewDraftResult {
    let _guard = draft_io_lock().lock().expect("review draft lock");
    draft_load_from(&draft_path(), key)
}

fn draft_load_from(path: &Path, key: String) -> NativeHostingReviewDraftResult {
    if !valid_draft_key(&key) {
        return draft_failure(NativeHostingReviewFailure::InvalidRequest);
    }
    match load_drafts(path) {
        Ok(document) => NativeHostingReviewDraftResult {
            draft: document.drafts.into_iter().find(|draft| draft.key == key),
            saved: false,
            failure: None,
        },
        Err(failure) => draft_failure(failure),
    }
}

pub fn draft_save(draft: NativeHostingReviewDraft) -> NativeHostingReviewDraftResult {
    let _guard = draft_io_lock().lock().expect("review draft lock");
    draft_save_to(&draft_path(), draft)
}

fn draft_save_to(
    path: &Path,
    mut draft: NativeHostingReviewDraft,
) -> NativeHostingReviewDraftResult {
    if !valid_draft(&draft) {
        return draft_failure(NativeHostingReviewFailure::InvalidRequest);
    }
    draft.updated_at = gitlama_application::clock::unix_seconds();
    let mut document = match load_drafts(path) {
        Ok(document) => document,
        Err(failure) => return draft_failure(failure),
    };
    document.drafts.retain(|value| value.key != draft.key);
    document.drafts.push(draft.clone());
    document
        .drafts
        .sort_by_key(|draft| std::cmp::Reverse(draft.updated_at));
    document.drafts.truncate(MAX_DRAFTS);
    if save_drafts(path, &document).is_err() {
        return draft_failure(NativeHostingReviewFailure::DraftStorage);
    }
    NativeHostingReviewDraftResult {
        draft: Some(draft),
        saved: true,
        failure: None,
    }
}

pub fn draft_delete(key: String) -> NativeHostingReviewDraftResult {
    let _guard = draft_io_lock().lock().expect("review draft lock");
    draft_delete_from(&draft_path(), key)
}

fn draft_delete_from(path: &Path, key: String) -> NativeHostingReviewDraftResult {
    if !valid_draft_key(&key) {
        return draft_failure(NativeHostingReviewFailure::InvalidRequest);
    }
    let mut document = match load_drafts(path) {
        Ok(document) => document,
        Err(failure) => return draft_failure(failure),
    };
    document.drafts.retain(|draft| draft.key != key);
    if save_drafts(path, &document).is_err() {
        return draft_failure(NativeHostingReviewFailure::DraftStorage);
    }
    NativeHostingReviewDraftResult {
        draft: None,
        saved: true,
        failure: None,
    }
}

fn draft_path() -> PathBuf {
    gitlama_application::storage::settings_default_path()
        .path
        .map(PathBuf::from)
        .and_then(|path| {
            path.parent()
                .map(|parent| parent.join("review-drafts.json"))
        })
        .unwrap_or_else(|| PathBuf::from("review-drafts.json"))
}

fn load_drafts(path: &Path) -> Result<DraftDocument, NativeHostingReviewFailure> {
    if !path.exists() {
        return Ok(DraftDocument::default());
    }
    let metadata =
        fs::symlink_metadata(path).map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
    if metadata.file_type().is_symlink() || metadata.len() > MAX_DRAFT_DOCUMENT as u64 {
        return Err(NativeHostingReviewFailure::DraftStorage);
    }
    let bytes = fs::read(path).map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
    let document: DraftDocument =
        serde_json::from_slice(&bytes).map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
    if document.drafts.len() > MAX_DRAFTS || !document.drafts.iter().all(valid_draft) {
        return Err(NativeHostingReviewFailure::DraftStorage);
    }
    Ok(document)
}

fn save_drafts(path: &Path, document: &DraftDocument) -> Result<(), NativeHostingReviewFailure> {
    let bytes =
        serde_json::to_vec(document).map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
    if bytes.len() > MAX_DRAFT_DOCUMENT {
        return Err(NativeHostingReviewFailure::DraftStorage);
    }
    let parent = path
        .parent()
        .ok_or(NativeHostingReviewFailure::DraftStorage)?;
    fs::create_dir_all(parent).map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
    if path.exists()
        && fs::symlink_metadata(path)
            .map_err(|_| NativeHostingReviewFailure::DraftStorage)?
            .file_type()
            .is_symlink()
    {
        return Err(NativeHostingReviewFailure::DraftStorage);
    }
    let temporary = parent.join(format!(
        ".review-drafts-{}-{}.tmp",
        std::process::id(),
        NEXT_AUTHORIZATION.fetch_add(1, Ordering::Relaxed)
    ));
    let mut options = OpenOptions::new();
    options.create_new(true).write(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&temporary)
        .map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
    let result = (|| {
        file.write_all(&bytes)
            .map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
        file.sync_all()
            .map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
        fs::rename(&temporary, path).map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
        #[cfg(unix)]
        File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| NativeHostingReviewFailure::DraftStorage)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

fn valid_draft(draft: &NativeHostingReviewDraft) -> bool {
    valid_draft_key(&draft.key)
        && !draft.connection_id.is_empty()
        && !draft.repository.is_empty()
        && draft.pull_request > 0
        && draft.head_sha.len() == 40
        && draft.body.len() <= 65_536
        && draft.inline_comments.len() <= 500
        && draft.inline_comments.iter().all(|comment| {
            !comment.stable_id.is_empty()
                && !comment.path.is_empty()
                && comment.line > 0
                && !comment.body.trim().is_empty()
                && comment.body.len() <= 65_536
        })
}

fn valid_draft_key(key: &str) -> bool {
    !key.is_empty() && key.len() <= 1_024 && !key.chars().any(char::is_control)
}

fn map_credential_failure(failure: CredentialLoadError) -> NativeHostingReviewFailure {
    use crate::hosting::CredentialFailure;
    match failure.classify() {
        CredentialFailure::Missing => NativeHostingReviewFailure::CredentialMissing,
        CredentialFailure::Expired => NativeHostingReviewFailure::CredentialExpired,
        CredentialFailure::Unreadable => NativeHostingReviewFailure::CredentialUnreadable,
        CredentialFailure::Invalid => NativeHostingReviewFailure::InvalidRequest,
        CredentialFailure::Refresh(error) => map_error(error),
    }
}

fn map_error(error: HostingError) -> NativeHostingReviewFailure {
    match error {
        HostingError::InvalidIdentity | HostingError::InvalidAccount => {
            NativeHostingReviewFailure::InvalidRequest
        }
        HostingError::InvalidCredential | HostingError::CredentialUnavailable => {
            NativeHostingReviewFailure::CredentialUnreadable
        }
        HostingError::Canceled => NativeHostingReviewFailure::Canceled,
        HostingError::Unauthorized => NativeHostingReviewFailure::Unauthorized,
        HostingError::PermissionDenied => NativeHostingReviewFailure::PermissionDenied,
        HostingError::RateLimited => NativeHostingReviewFailure::RateLimited,
        HostingError::MalformedResponse => NativeHostingReviewFailure::MalformedResponse,
        HostingError::Unavailable(_) => NativeHostingReviewFailure::Unavailable,
    }
}

const fn load_failure(failure: NativeHostingReviewFailure) -> NativeHostingReviewLoadResult {
    NativeHostingReviewLoadResult {
        page: None,
        failure: Some(failure),
    }
}

const fn preview_failure(failure: NativeHostingReviewFailure) -> NativeHostingReviewPreviewResult {
    NativeHostingReviewPreviewResult {
        preview: None,
        failure: Some(failure),
    }
}

const fn check_preview_failure(
    failure: NativeHostingReviewFailure,
) -> NativeHostingCheckRetryPreviewResult {
    NativeHostingCheckRetryPreviewResult {
        preview: None,
        failure: Some(failure),
    }
}

const fn submit_failure(failure: NativeHostingReviewFailure) -> NativeHostingReviewSubmitResult {
    NativeHostingReviewSubmitResult {
        state: NativeHostingReviewSubmitState::Failed,
        failure: Some(failure),
    }
}

const fn draft_failure(failure: NativeHostingReviewFailure) -> NativeHostingReviewDraftResult {
    NativeHostingReviewDraftResult {
        draft: None,
        saved: false,
        failure: Some(failure),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hosting::{NativeHostingCapability, NativeHostingPreset};
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;

    fn connection() -> NativeHostingConnection {
        NativeHostingConnection {
            id: "github:test".into(),
            preset: NativeHostingPreset::GitHub,
            login: "alice".into(),
            web_base_url: "https://github.com".into(),
            api_base_url: "https://api.github.com".into(),
            oauth_client_id: "client".into(),
            authentication: crate::hosting::NativeHostingAuthentication::OAuth,
            enabled: true,
            refresh_enabled: true,
            capabilities: vec![NativeHostingCapability::ChangeRequestReview],
            credential_identity: "credential:test".into(),
            allow_split_origin: false,
        }
    }

    fn preview(body: &str) -> NativeHostingReviewPreview {
        review_preview(
            connection(),
            "team/project".into(),
            7,
            "a".repeat(40),
            NativeHostingReviewAction::Comment,
            body.into(),
            vec![NativeHostingInlineDraft {
                stable_id: "draft:1".into(),
                path: "src/lib.rs".into(),
                line: 3,
                body: "inline".into(),
            }],
        )
        .preview
        .unwrap()
    }

    #[test]
    fn review_client_runs_through_the_bounded_local_transport_contract() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            for _ in 0..3 {
                let mut stream = crate::loopback_fixture::accept_client(&listener);
                stream
                    .set_read_timeout(Some(Duration::from_secs(2)))
                    .unwrap();
                let mut request = [0_u8; 8_192];
                let read = stream.read(&mut request).unwrap();
                let request = String::from_utf8_lossy(&request[..read]);
                let target = request
                    .lines()
                    .next()
                    .and_then(|line| line.split_whitespace().nth(1))
                    .unwrap();
                let body = if target == "/repos/team/project/pulls/7" {
                    format!(r#"{{"head":{{"sha":"{}"}}}}"#, "a".repeat(40))
                } else if target.starts_with("/repos/team/project/pulls/7/files") {
                    r#"[{"sha":"1","filename":"src/lib.rs","patch":"@@ -1 +1 @@\n+line"}]"#.into()
                } else if target.starts_with("/repos/team/project/pulls/7/comments") {
                    "[]".into()
                } else {
                    panic!("unexpected review request target: {target}");
                };
                let response = format!(
                    "HTTP/1.1 200 Fixture\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                stream.write_all(response.as_bytes()).unwrap();
            }
        });
        let mut fixture = connection();
        fixture.api_base_url = format!("http://{address}");
        let uncertain = Cell::new(false);
        let cancellation = AtomicBool::new(false);
        let mut transport = CurlReviewTransport {
            connection: &fixture,
            credential: b"fixture-token",
            uncertain: &uncertain,
            cancellation: &cancellation,
        };
        let result = review_load_with(
            &fixture,
            "team/project".into(),
            7,
            "a".repeat(40),
            None,
            &cancellation,
            &mut |request| transport.execute(request),
        );
        server.join().unwrap();
        assert_eq!(result.failure, None);
        assert_eq!(result.page.unwrap().diffs[0].path, "src/lib.rs");
    }

    #[test]
    fn patch_lines_count_a_removed_line_starting_with_dashes_as_removed() {
        // Regression: a removed line whose content starts with "--" was taken for context.
        let patch = "@@ -3,3 +3,2 @@ fn section\n context\n---removed\n+added\n-gone\n\\ No newline at end of file\n@@ -20 +19,2 @@\n tail\n+new";
        assert_eq!(patch_lines(patch), [3, 4, 19, 20]);
    }

    #[test]
    fn patch_projection_has_stable_anchors_and_marks_outdated_threads() {
        let diff = map_diff(
            &"a".repeat(40),
            ReviewDiffRow {
                stable_id: "diff:1".into(),
                path: "src/lib.rs".into(),
                patch: "@@ -1,2 +1,3 @@\n same\n-old\n+new\n+third".into(),
            },
        );
        assert_eq!(
            diff.anchors
                .iter()
                .map(|anchor| anchor.line)
                .collect::<Vec<_>>(),
            [1, 2, 3]
        );
        let anchors = diff
            .anchors
            .iter()
            .map(|anchor| ((anchor.path.clone(), anchor.line), anchor.stable_id.clone()))
            .collect();
        assert!(
            !map_thread(
                ReviewThread {
                    stable_id: "thread:1".into(),
                    path: Some("src/lib.rs".into()),
                    line: Some(2),
                    author: "alice".into(),
                    body: "current".into(),
                    resolved: false,
                },
                &anchors
            )
            .outdated
        );
        assert!(
            map_thread(
                ReviewThread {
                    stable_id: "thread:2".into(),
                    path: Some("old.rs".into()),
                    line: Some(2),
                    author: "bob".into(),
                    body: "old".into(),
                    resolved: false,
                },
                &anchors
            )
            .outdated
        );
    }

    #[test]
    fn provider_paths_are_encoded_without_changing_repository_structure() {
        let head_path = |connection: &NativeHostingConnection, repository: &str| {
            let (_, repository, plugin) = review_target(connection, repository)?;
            plugin
                .pull_request_head_path(&repository, 1)
                .map_err(map_error)
        };
        assert_eq!(
            head_path(&connection(), "team/project"),
            Ok("/repos/team/project/pulls/1".into())
        );
        assert_eq!(
            head_path(&connection(), "team/project/extra"),
            Err(NativeHostingReviewFailure::InvalidRequest)
        );
        let gitlab = NativeHostingConnection {
            id: "gitlab:test".into(),
            preset: NativeHostingPreset::GitLab,
            web_base_url: "https://gitlab.com".into(),
            api_base_url: "https://gitlab.com/api/v4".into(),
            ..connection()
        };
        assert_eq!(
            head_path(&gitlab, "group/sub/project"),
            Ok("/projects/group%2Fsub%2Fproject/merge_requests/1".into())
        );
        let forgejo = NativeHostingConnection {
            id: "forgejo:test".into(),
            preset: NativeHostingPreset::Codeberg,
            web_base_url: "https://codeberg.org".into(),
            api_base_url: "https://codeberg.org/api/v1".into(),
            ..connection()
        };
        assert_eq!(
            head_path(&forgejo, "team/project"),
            Err(NativeHostingReviewFailure::Unsupported)
        );
    }

    #[test]
    fn replacement_and_explicit_cancel_signal_in_flight_review_work() {
        let key = cancellation_key("github:test", "team/cancel-test", 91);
        let first = begin_request(&key);
        let second = begin_request(&key);
        assert!(first.load(Ordering::Acquire));
        assert!(!second.load(Ordering::Acquire));
        assert!(review_cancel(
            "github:test".into(),
            "team/cancel-test".into(),
            91
        ));
        assert!(second.load(Ordering::Acquire));
        assert!(!review_cancel(
            "github:test".into(),
            "team/cancel-test".into(),
            91
        ));
    }

    #[test]
    fn authorization_binds_exact_target_payload_and_is_one_shot() {
        let authorized = preview("body");
        let mut calls = 0;
        let uncertain = Cell::new(false);
        let result = review_submit_with(
            &connection(),
            authorized.authorization_id,
            "team/project".into(),
            7,
            "a".repeat(40),
            NativeHostingReviewAction::Comment,
            "changed".into(),
            authorized.inline_comments.clone(),
            &AtomicBool::new(false),
            &mut |_| {
                calls += 1;
                Ok(ReviewHttpResponse {
                    status: 201,
                    body: vec![],
                    next_page: None,
                })
            },
            &mut |_| unreachable!(),
            &uncertain,
        );
        assert_eq!(
            result.failure,
            Some(NativeHostingReviewFailure::StaleAuthorization)
        );
        assert_eq!(calls, 0);
        let authorized = preview("body");
        let result = review_submit_with(
            &connection(),
            authorized.authorization_id,
            "team/project".into(),
            7,
            "a".repeat(40),
            NativeHostingReviewAction::Comment,
            "body".into(),
            authorized.inline_comments,
            &AtomicBool::new(false),
            &mut |_| {
                calls += 1;
                Ok(ReviewHttpResponse {
                    status: 201,
                    body: vec![],
                    next_page: None,
                })
            },
            &mut |_| unreachable!(),
            &uncertain,
        );
        assert_eq!(result.state, NativeHostingReviewSubmitState::Submitted);
        assert_eq!(calls, 1);
    }

    #[test]
    fn uncertain_comment_reconciles_before_any_resend() {
        let authorized = preview("unique body");
        let uncertain = Cell::new(true);
        let mut submit_calls = 0;
        let mut reconcile_calls = 0;
        let result = review_submit_with(
            &connection(),
            authorized.authorization_id,
            "team/project".into(),
            7,
            "a".repeat(40),
            NativeHostingReviewAction::Comment,
            "unique body".into(),
            authorized.inline_comments,
            &AtomicBool::new(false),
            &mut |_| {
                submit_calls += 1;
                Err(HostingError::Unavailable("timeout".into()))
            },
            &mut |request| {
                reconcile_calls += 1;
                Ok(ReviewHttpResponse {
                    status: 200,
                    next_page: None,
                    body: if request.path.contains("/files?") {
                        br#"[{"filename":"src/lib.rs","patch":"@@ -1 +1 @@\n+line"}]"#.to_vec()
                    } else {
                        br#"[{"id":3,"path":"src/lib.rs","line":1,"user":{"login":"alice"},"body":"unique body"}]"#.to_vec()
                    },
                })
            },
            &uncertain,
        );
        assert_eq!(result.state, NativeHostingReviewSubmitState::Reconciled);
        assert_eq!(submit_calls, 1);
        assert_eq!(reconcile_calls, 2);
    }

    #[test]
    fn duplicate_provider_response_reconciles_without_a_second_submission() {
        let authorized = preview("already present");
        let uncertain = Cell::new(false);
        let mut submit_calls = 0;
        let mut reconcile_calls = 0;
        let result = review_submit_with(
            &connection(),
            authorized.authorization_id,
            "team/project".into(),
            7,
            "a".repeat(40),
            NativeHostingReviewAction::Comment,
            "already present".into(),
            authorized.inline_comments,
            &AtomicBool::new(false),
            &mut |_| {
                submit_calls += 1;
                Ok(ReviewHttpResponse {
                    status: 409,
                    body: Vec::new(),
                    next_page: None,
                })
            },
            &mut |request| {
                reconcile_calls += 1;
                Ok(ReviewHttpResponse {
                    status: 200,
                    next_page: None,
                    body: if request.path.contains("/files?") {
                        br#"[{"filename":"src/lib.rs","patch":"@@ -1 +1 @@\n+line"}]"#.to_vec()
                    } else {
                        br#"[{"id":4,"path":"src/lib.rs","line":1,"user":{"login":"alice"},"body":"already present"}]"#.to_vec()
                    },
                })
            },
            &uncertain,
        );
        assert_eq!(result.state, NativeHostingReviewSubmitState::Reconciled);
        assert_eq!(submit_calls, 1);
        assert_eq!(reconcile_calls, 2);
    }

    #[test]
    fn moved_base_and_permission_loss_stop_before_review_loading() {
        let mut calls = 0;
        let moved = review_load_with(
            &connection(),
            "team/project".into(),
            7,
            "a".repeat(40),
            None,
            &AtomicBool::new(false),
            &mut |_| {
                calls += 1;
                Ok(ReviewHttpResponse {
                    status: 200,
                    body: format!(r#"{{"head":{{"sha":"{}"}}}}"#, "b".repeat(40)).into_bytes(),
                    next_page: None,
                })
            },
        );
        assert_eq!(moved.failure, Some(NativeHostingReviewFailure::MovedBase));
        assert_eq!(calls, 1);

        let denied = review_load_with(
            &connection(),
            "team/project".into(),
            7,
            "a".repeat(40),
            None,
            &AtomicBool::new(false),
            &mut |_| {
                Ok(ReviewHttpResponse {
                    status: 403,
                    body: Vec::new(),
                    next_page: None,
                })
            },
        );
        assert_eq!(
            denied.failure,
            Some(NativeHostingReviewFailure::PermissionDenied)
        );
    }

    #[test]
    fn offline_draft_round_trips_outside_preferences() {
        let directory = std::env::temp_dir().join(format!(
            "gitlama-review-draft-{}-{}",
            std::process::id(),
            NEXT_AUTHORIZATION.fetch_add(1, Ordering::Relaxed)
        ));
        let path = directory.join("review-drafts.json");
        let draft = NativeHostingReviewDraft {
            key: "11:github:test12:team/project:7".into(),
            connection_id: "github:test".into(),
            repository: "team/project".into(),
            pull_request: 7,
            head_sha: "a".repeat(40),
            action: NativeHostingReviewAction::RequestChanges,
            body: "keep offline".into(),
            inline_comments: vec![NativeHostingInlineDraft {
                stable_id: "draft:1".into(),
                path: "src/lib.rs".into(),
                line: 3,
                body: "inline".into(),
            }],
            updated_at: 0,
        };
        assert!(draft_save_to(&path, draft.clone()).saved);
        let loaded = draft_load_from(&path, draft.key.clone()).draft.unwrap();
        assert_eq!(loaded.body, "keep offline");
        assert_eq!(loaded.inline_comments, draft.inline_comments);
        assert!(draft_delete_from(&path, draft.key.clone()).saved);
        assert!(draft_load_from(&path, draft.key).draft.is_none());
        std::fs::remove_dir_all(directory).unwrap();
    }
}
