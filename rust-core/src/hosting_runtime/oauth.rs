//! Authorization: device flow, PKCE with a loopback callback, provider CLIs and token refresh.
#![allow(clippy::wildcard_imports)]
use super::*;

pub(super) fn run_oauth(
    request_id: u64,
    connection: NativeHostingConnection,
    cancellation: Arc<AtomicBool>,
    sessions: &Mutex<HashMap<u64, OAuthSession>>,
) {
    if cancellation.load(Ordering::Acquire) {
        publish_canceled(sessions, request_id);
        return;
    }
    let shared = to_shared(&connection);
    let result = match provider_plugin(shared.provider()).login_flow() {
        OAuthLoginFlow::DeviceAuthorization(specification) => run_device_flow(
            request_id,
            &connection,
            &shared,
            specification,
            cancellation.as_ref(),
            sessions,
        ),
        OAuthLoginFlow::AuthorizationCodePkce(specification) => run_pkce_flow(
            request_id,
            &connection,
            &shared,
            specification,
            cancellation.as_ref(),
            sessions,
        ),
    };
    match result {
        Ok(login) => publish(sessions, request_id, |snapshot| {
            snapshot.state = NativeHostingOAuthState::Succeeded;
            snapshot.authenticated_login = Some(login);
            snapshot.browser_url = None;
            snapshot.user_code = None;
            snapshot.failure = None;
        }),
        Err(FlowFailure::Canceled) => publish_canceled(sessions, request_id),
        Err(failure) => publish(sessions, request_id, |snapshot| {
            snapshot.state = NativeHostingOAuthState::Failed;
            snapshot.browser_url = None;
            snapshot.user_code = None;
            snapshot.failure = Some(failure.into_native());
        }),
    }
}

#[derive(Debug, Eq, PartialEq)]
pub(super) enum FlowFailure {
    Canceled,
    Expired,
    Denied,
    Native(NativeHostingOAuthFailure),
}

impl FlowFailure {
    pub(super) fn into_native(self) -> NativeHostingOAuthFailure {
        match self {
            Self::Canceled => NativeHostingOAuthFailure::Unavailable,
            Self::Expired => NativeHostingOAuthFailure::Expired,
            Self::Denied => NativeHostingOAuthFailure::Denied,
            Self::Native(failure) => failure,
        }
    }
}

pub(super) fn publish_canceled(sessions: &Mutex<HashMap<u64, OAuthSession>>, request_id: u64) {
    publish(sessions, request_id, |snapshot| {
        snapshot.state = NativeHostingOAuthState::Canceled;
        snapshot.browser_url = None;
        snapshot.user_code = None;
        snapshot.failure = None;
    });
}

pub(super) fn run_device_flow(
    request_id: u64,
    native: &NativeHostingConnection,
    connection: &HostingConnection,
    specification: devmil_git::hosting::providers::DeviceAuthorization,
    cancellation: &AtomicBool,
    sessions: &Mutex<HashMap<u64, OAuthSession>>,
) -> Result<String, FlowFailure> {
    let transport = CurlTransport::first_page();
    run_device_flow_with(
        request_id,
        native,
        connection,
        specification,
        cancellation,
        sessions,
        &transport,
        &transport,
        &KeyringCredentialWriter,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn run_device_flow_with(
    request_id: u64,
    native: &NativeHostingConnection,
    connection: &HostingConnection,
    specification: devmil_git::hosting::providers::DeviceAuthorization,
    cancellation: &AtomicBool,
    sessions: &Mutex<HashMap<u64, OAuthSession>>,
    form_transport: &dyn OAuthFormTransport,
    requester: &dyn HostingProviderRequester,
    credential_writer: &dyn CredentialWriter,
) -> Result<String, FlowFailure> {
    let response = form_transport
        .post_form(
            &device_authorization_url(connection, specification),
            &device_authorization_request_form(connection, specification),
            cancellation,
        )
        .map_err(map_hosting_error)?;
    require_success(response.status)?;
    let authorization = parse_device_authorization(&response.body).map_err(map_hosting_error)?;
    validate_device_verification_uri(connection, specification, &authorization.verification_uri)
        .map_err(map_hosting_error)?;
    publish(sessions, request_id, |snapshot| {
        snapshot.state = NativeHostingOAuthState::WaitingForDevice;
        snapshot.browser_url = Some(authorization.verification_uri.clone());
        snapshot.user_code = Some(authorization.user_code.clone());
    });
    let deadline =
        Instant::now() + Duration::from_secs(authorization.expires_in).min(OAUTH_TIMEOUT);
    let mut interval = Duration::from_secs(authorization.interval.max(1));
    loop {
        wait_cancellable(interval, cancellation)?;
        if Instant::now() >= deadline {
            return Err(FlowFailure::Expired);
        }
        let mut poll_form = device_authorization_poll_form(connection, &authorization.device_code);
        let response = form_transport
            .post_form(&oauth_token_url(connection), &poll_form, cancellation)
            .map_err(map_hosting_error);
        poll_form.zeroize();
        let response = response?;
        require_success_or_oauth(response.status)?;
        match parse_device_authorization_poll(&response.body).map_err(map_hosting_error)? {
            DeviceAuthorizationPoll::Authorized(token) => {
                return finish_authorization_with(
                    native,
                    connection,
                    token,
                    cancellation,
                    requester,
                    credential_writer,
                );
            }
            DeviceAuthorizationPoll::Pending => {}
            DeviceAuthorizationPoll::SlowDown(suggested) => {
                let minimum = interval + Duration::from_secs(5);
                interval = suggested
                    .map(Duration::from_secs)
                    .unwrap_or(minimum)
                    .max(minimum);
            }
            DeviceAuthorizationPoll::Denied => return Err(FlowFailure::Denied),
            DeviceAuthorizationPoll::Expired => return Err(FlowFailure::Expired),
            DeviceAuthorizationPoll::Disabled => {
                return Err(FlowFailure::Native(NativeHostingOAuthFailure::Unavailable));
            }
        }
    }
}

pub(super) fn run_pkce_flow(
    request_id: u64,
    native: &NativeHostingConnection,
    connection: &HostingConnection,
    specification: devmil_git::hosting::providers::AuthorizationCodePkce,
    cancellation: &AtomicBool,
    sessions: &Mutex<HashMap<u64, OAuthSession>>,
) -> Result<String, FlowFailure> {
    let transport = CurlTransport::first_page();
    run_pkce_flow_with(
        request_id,
        native,
        connection,
        specification,
        cancellation,
        sessions,
        &transport,
        &transport,
        &KeyringCredentialWriter,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn run_pkce_flow_with(
    request_id: u64,
    native: &NativeHostingConnection,
    connection: &HostingConnection,
    specification: devmil_git::hosting::providers::AuthorizationCodePkce,
    cancellation: &AtomicBool,
    sessions: &Mutex<HashMap<u64, OAuthSession>>,
    form_transport: &dyn OAuthFormTransport,
    requester: &dyn HostingProviderRequester,
    credential_writer: &dyn CredentialWriter,
) -> Result<String, FlowFailure> {
    let listener = TcpListener::bind(LOOPBACK_ADDRESS)
        .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::Unavailable))?;
    listener
        .set_nonblocking(true)
        .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::Unavailable))?;
    let mut state_bytes = [0_u8; 32];
    let mut verifier_bytes = [0_u8; 32];
    getrandom::fill(&mut state_bytes)
        .and_then(|_| getrandom::fill(&mut verifier_bytes))
        .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::Unavailable))?;
    let state = base64_url(&state_bytes);
    let mut verifier = base64_url(&verifier_bytes);
    state_bytes.zeroize();
    verifier_bytes.zeroize();
    let challenge = base64_url(&Sha256::digest(verifier.as_bytes()));
    let browser_url = oauth_authorize_url(
        connection,
        specification,
        LOOPBACK_CALLBACK,
        &state,
        &challenge,
    );
    publish(sessions, request_id, |snapshot| {
        snapshot.state = NativeHostingOAuthState::WaitingForBrowser;
        snapshot.browser_url = Some(browser_url);
    });
    let callback = wait_for_callback(&listener, &state, cancellation);
    let code = match callback {
        Ok(code) => code,
        Err(failure) => {
            verifier.zeroize();
            return Err(failure);
        }
    };
    publish(sessions, request_id, |snapshot| {
        snapshot.state = NativeHostingOAuthState::Exchanging;
        snapshot.browser_url = None;
    });
    let mut form = oauth_authorization_code_form(connection, &code, LOOPBACK_CALLBACK, &verifier);
    let response = form_transport
        .post_form(&oauth_token_url(connection), &form, cancellation)
        .map_err(map_hosting_error);
    form.zeroize();
    verifier.zeroize();
    let response = response?;
    let token =
        parse_oauth_token_response(response.status, &response.body).map_err(map_hosting_error)?;
    finish_authorization_with(
        native,
        connection,
        token,
        cancellation,
        requester,
        credential_writer,
    )
}

pub(super) fn wait_for_callback(
    listener: &TcpListener,
    expected_state: &str,
    cancellation: &AtomicBool,
) -> Result<String, FlowFailure> {
    let deadline = Instant::now() + OAUTH_TIMEOUT;
    loop {
        if cancellation.load(Ordering::Acquire) {
            return Err(FlowFailure::Canceled);
        }
        if Instant::now() >= deadline {
            return Err(FlowFailure::Expired);
        }
        match listener.accept() {
            Ok((mut stream, peer)) if peer.ip().is_loopback() => {
                let result = parse_callback(&mut stream, expected_state);
                let status = if result.is_ok() {
                    "200 OK"
                } else {
                    "400 Bad Request"
                };
                let body = if result.is_ok() {
                    "Authorization received. You can return to GitLama."
                } else {
                    "Authorization rejected. Return to GitLama and try again."
                };
                let response = format!(
                    "HTTP/1.1 {status}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                let _ = stream.write_all(response.as_bytes());
                return result;
            }
            Ok((_stream, _)) => {
                return Err(FlowFailure::Native(
                    NativeHostingOAuthFailure::MalformedResponse,
                ))
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(25));
            }
            Err(_) => return Err(FlowFailure::Native(NativeHostingOAuthFailure::Unavailable)),
        }
    }
}

pub(super) fn parse_callback(
    stream: &mut TcpStream,
    expected_state: &str,
) -> Result<String, FlowFailure> {
    const MAX_CALLBACK_BYTES: usize = 8 * 1024;
    stream
        .set_nonblocking(false)
        .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::MalformedResponse))?;
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut bytes = Vec::with_capacity(1024);
    loop {
        let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
            return Err(FlowFailure::Native(
                NativeHostingOAuthFailure::MalformedResponse,
            ));
        };
        stream
            .set_read_timeout(Some(remaining))
            .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::MalformedResponse))?;
        let mut chunk = [0_u8; 1024];
        let read = stream
            .read(&mut chunk)
            .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::MalformedResponse))?;
        if read == 0 || bytes.len() + read > MAX_CALLBACK_BYTES {
            return Err(FlowFailure::Native(
                NativeHostingOAuthFailure::MalformedResponse,
            ));
        }
        bytes.extend_from_slice(&chunk[..read]);
        if bytes.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
    }
    let request = std::str::from_utf8(&bytes)
        .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::MalformedResponse))?;
    let first = request.split("\r\n").next().ok_or(FlowFailure::Native(
        NativeHostingOAuthFailure::MalformedResponse,
    ))?;
    let target = first
        .strip_prefix("GET ")
        .and_then(|value| value.strip_suffix(" HTTP/1.1"))
        .ok_or(FlowFailure::Native(
            NativeHostingOAuthFailure::MalformedResponse,
        ))?;
    let query = target
        .strip_prefix("/oauth/callback?")
        .ok_or(FlowFailure::Native(
            NativeHostingOAuthFailure::MalformedResponse,
        ))?;
    let state = devmil_git::hosting::oauth::query_value(query, "state").ok_or(
        FlowFailure::Native(NativeHostingOAuthFailure::MalformedResponse),
    )?;
    if state != expected_state {
        return Err(FlowFailure::Native(NativeHostingOAuthFailure::Unauthorized));
    }
    devmil_git::hosting::oauth::query_value(query, "code")
        .filter(|code| !code.is_empty() && code.len() <= 2048)
        .ok_or(FlowFailure::Native(
            NativeHostingOAuthFailure::MalformedResponse,
        ))
}

pub(super) fn finish_authorization_with(
    native: &NativeHostingConnection,
    connection: &HostingConnection,
    mut token: OAuthTokenResponse,
    cancellation: &AtomicBool,
    requester: &dyn HostingProviderRequester,
    credential_writer: &dyn CredentialWriter,
) -> Result<String, FlowFailure> {
    if cancellation.load(Ordering::Acquire) {
        return Err(FlowFailure::Canceled);
    }
    let credential = HostingCredential::new(token.access_token.as_bytes().to_vec())
        .map_err(map_hosting_error)?;
    let response = requester
        .request(connection, "/user".into(), &credential, cancellation)
        .map_err(map_hosting_error)?;
    require_success(response.status)?;
    let login = identity_login(connection.provider(), &response.body).ok_or(
        FlowFailure::Native(NativeHostingOAuthFailure::MalformedResponse),
    )?;
    let expires_at = token
        .expires_in
        .and_then(|seconds| gitlama_application::clock::unix_seconds().checked_add(seconds));
    let envelope = CredentialEnvelope::new(
        std::mem::take(&mut token.access_token),
        token.refresh_token.take(),
        expires_at,
    )
    .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::SecureStore))?;
    credential_writer
        .store(native, &envelope)
        .map_err(|_| FlowFailure::Native(NativeHostingOAuthFailure::SecureStore))?;
    Ok(login)
}

/// The account login in a provider's `/user` response, read from the provider's identity field.
pub(super) fn identity_login(
    provider: devmil_git::hosting::model::HostingProvider,
    body: &[u8],
) -> Option<String> {
    let identity: devmil_git::hosting::oauth::OAuthIdentity = serde_json::from_slice(body).ok()?;
    let login = match provider_plugin(provider).identity_field() {
        OAuthIdentityField::Login => identity.login,
        OAuthIdentityField::Username => identity.username,
    };
    (!login.is_empty() && login.len() <= 512 && !login.chars().any(char::is_control))
        .then_some(login)
}

pub(super) trait CredentialWriter: Sync {
    fn store(
        &self,
        connection: &NativeHostingConnection,
        envelope: &CredentialEnvelope,
    ) -> Result<(), ()>;
}

pub(super) struct KeyringCredentialWriter;

impl CredentialWriter for KeyringCredentialWriter {
    fn store(
        &self,
        connection: &NativeHostingConnection,
        envelope: &CredentialEnvelope,
    ) -> Result<(), ()> {
        store_credential(connection, envelope).map_err(|_| ())
    }
}

pub(crate) fn refresh_credential(
    native: &NativeHostingConnection,
    envelope: &CredentialEnvelope,
    cancellation: &dyn Cancellation,
) -> Result<CredentialEnvelope, HostingError> {
    refresh_credential_with(
        &CurlTransport::first_page(),
        native,
        envelope,
        cancellation,
        gitlama_application::clock::unix_seconds,
    )
}

pub(super) fn refresh_credential_with(
    transport: &dyn OAuthFormTransport,
    native: &NativeHostingConnection,
    envelope: &CredentialEnvelope,
    cancellation: &dyn Cancellation,
    now: impl Fn() -> u64,
) -> Result<CredentialEnvelope, HostingError> {
    if cancellation.is_cancelled() {
        return Err(HostingError::Canceled);
    }
    let refresh_token = envelope
        .refresh_token()
        .ok_or(HostingError::CredentialUnavailable)?;
    let shared = to_shared(native);
    let mut form = oauth_refresh_token_form(&shared, refresh_token);
    let response = transport.post_form(&oauth_token_url(&shared), &form, cancellation);
    form.zeroize();
    let mut response = response?;
    let result = parse_oauth_token_response(response.status, &response.body);
    response.body.zeroize();
    let mut token = result?;
    let expires_at = token
        .expires_in
        .and_then(|seconds| now().checked_add(seconds))
        .ok_or(HostingError::MalformedResponse)?;
    CredentialEnvelope::new(
        std::mem::take(&mut token.access_token),
        token
            .refresh_token
            .take()
            .or_else(|| Some(refresh_token.to_owned())),
        Some(expires_at),
    )
    .map_err(|_| HostingError::MalformedResponse)
}
