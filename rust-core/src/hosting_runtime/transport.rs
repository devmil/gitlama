//! The curl transport for provider and OAuth requests.
#![allow(clippy::wildcard_imports)]
use super::*;
pub(super) use devmil_git::hosting::http::TransportFailure;
use devmil_git::hosting::http::{
    curl_form_command, curl_form_loopback_command, curl_result_response, require_success_status,
};

pub(super) trait OAuthFormTransport: Sync {
    fn post_form(
        &self,
        url: &str,
        form: &str,
        cancellation: &dyn Cancellation,
    ) -> Result<HostingHttpResponse, HostingError>;
}

pub(super) struct CurlTransport {
    pub(super) page: u32,
}

impl CurlTransport {
    pub(super) const fn first_page() -> Self {
        Self { page: 1 }
    }

    pub(super) fn execute_form(
        &self,
        url: &str,
        form: &str,
        cancellation: &dyn Cancellation,
    ) -> Result<HostingHttpResponse, HostingError> {
        let command =
            curl_form_command("curl".as_ref(), url, form.as_bytes()).or_else(|error| {
                // Tests exercise the flows against a plain-HTTP server on the loopback interface.
                if cfg!(test) {
                    curl_form_loopback_command("curl".as_ref(), url, form.as_bytes())
                } else {
                    Err(error)
                }
            })?;
        execute_curl(command, cancellation)
    }
}

impl OAuthFormTransport for CurlTransport {
    fn post_form(
        &self,
        url: &str,
        form: &str,
        cancellation: &dyn Cancellation,
    ) -> Result<HostingHttpResponse, HostingError> {
        self.execute_form(url, form, cancellation)
    }
}

impl HostingProviderRequester for CurlTransport {
    fn request(
        &self,
        connection: &HostingConnection,
        path: String,
        credential: &HostingCredential,
        cancellation: &dyn Cancellation,
    ) -> Result<HostingHttpResponse, HostingError> {
        let path = page_path(path, self.page)?;
        let request = devmil_git::hosting::providers::HostingHttpRequest {
            base_url: connection.api_base_url.clone(),
            path,
            provider: connection.provider(),
        };
        let command = curl_get_command("curl".as_ref(), &request, credential.expose())?;
        let response = execute_curl(command, cancellation)?;
        require_success_status(response.status)?;
        Ok(response)
    }
}

pub(super) fn page_path(mut path: String, page: u32) -> Result<String, HostingError> {
    if page == 0 || page > 1000 || path.len() > 8192 {
        return Err(HostingError::InvalidAccount);
    }
    if page > 1 {
        if !path.contains('?') {
            return Err(HostingError::InvalidAccount);
        }
        use std::fmt::Write as _;
        write!(path, "&page={page}").map_err(|_| HostingError::InvalidAccount)?;
    }
    Ok(path)
}

pub(super) fn execute_curl(
    command: GitProcessCommand,
    cancellation: &dyn Cancellation,
) -> Result<HostingHttpResponse, HostingError> {
    let mut discard = |_event| {};
    curl_result_response(ActivityGitRunner::run_private(
        command,
        allocate_activity_id(),
        Some(cancellation),
        &mut discard,
    ))
}

pub(super) const fn oauth_failure(failure: TransportFailure) -> NativeHostingOAuthFailure {
    match failure {
        TransportFailure::NotFound => NativeHostingOAuthFailure::NotFound,
        TransportFailure::Redirected => NativeHostingOAuthFailure::Redirected,
        TransportFailure::ServerError => NativeHostingOAuthFailure::ServerError,
        TransportFailure::Network => NativeHostingOAuthFailure::Network,
        TransportFailure::Certificate => NativeHostingOAuthFailure::Certificate,
        TransportFailure::TimedOut => NativeHostingOAuthFailure::TimedOut,
    }
}

pub(super) fn require_success(status: u16) -> Result<(), FlowFailure> {
    match status {
        200..=299 => Ok(()),
        401 | 403 => Err(FlowFailure::Native(NativeHostingOAuthFailure::Unauthorized)),
        429 => Err(FlowFailure::Native(NativeHostingOAuthFailure::RateLimited)),
        status => Err(FlowFailure::Native(
            TransportFailure::from_status(status)
                .map_or(NativeHostingOAuthFailure::Unavailable, oauth_failure),
        )),
    }
}

pub(super) fn require_success_or_oauth(status: u16) -> Result<(), FlowFailure> {
    match status {
        200..=299 | 400 => Ok(()),
        _ => require_success(status),
    }
}

pub(super) fn map_hosting_error(error: HostingError) -> FlowFailure {
    FlowFailure::Native(match error {
        HostingError::Canceled => return FlowFailure::Canceled,
        HostingError::Unauthorized | HostingError::PermissionDenied => {
            NativeHostingOAuthFailure::Unauthorized
        }
        HostingError::RateLimited => NativeHostingOAuthFailure::RateLimited,
        HostingError::MalformedResponse => NativeHostingOAuthFailure::MalformedResponse,
        HostingError::InvalidIdentity
        | HostingError::InvalidAccount
        | HostingError::InvalidCredential => NativeHostingOAuthFailure::InvalidConnection,
        HostingError::CredentialUnavailable => NativeHostingOAuthFailure::Unavailable,
        HostingError::Unavailable(reason) => TransportFailure::from_reason(&reason)
            .map_or(NativeHostingOAuthFailure::Unavailable, oauth_failure),
    })
}

pub(super) fn wait_cancellable(
    duration: Duration,
    cancellation: &AtomicBool,
) -> Result<(), FlowFailure> {
    let deadline = Instant::now() + duration;
    while Instant::now() < deadline {
        if cancellation.load(Ordering::Acquire) {
            return Err(FlowFailure::Canceled);
        }
        thread::sleep(
            Duration::from_millis(25).min(deadline.saturating_duration_since(Instant::now())),
        );
    }
    Ok(())
}
