//! Authenticated process-local CLI forwarding and single-instance ownership.
pub use gitlama_contract::cli_forwarding::*;

pub mod protocol;
#[cfg(unix)]
mod unix;
#[cfg(windows)]
mod windows;

use protocol::{AllowedCommand, AllowedPullStrategy, ForwardAction, ForwardResponse, ResponseCode};
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TryRecvError, TrySendError};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const COMMAND_QUEUE_CAPACITY: usize = 8;
const APPLICATION_RESPONSE_TIMEOUT: Duration = Duration::from_secs(2);
const CLIENT_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone, Debug, Eq, PartialEq)]
enum Invocation {
    Gui,
    Forward {
        action: ForwardAction,
        start_if_absent: bool,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum ParseError {
    InvalidArguments,
    InvalidPath,
}

struct QueuedCommand {
    request_id: u64,
    action: ForwardAction,
    response: Option<SyncSender<ForwardResponse>>,
}

#[cfg(any(unix, windows))]
struct RuntimeOwner {
    #[cfg(unix)]
    _unix_server: unix::ForwardingServer,
    #[cfg(windows)]
    _windows_server: windows::ForwardingServer,
    receiver: Receiver<QueuedCommand>,
    initial: VecDeque<QueuedCommand>,
    awaiting: HashMap<u64, SyncSender<ForwardResponse>>,
}

#[cfg(not(any(unix, windows)))]
struct RuntimeOwner;

static OWNER: OnceLock<Mutex<Option<RuntimeOwner>>> = OnceLock::new();
static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

fn owner() -> &'static Mutex<Option<RuntimeOwner>> {
    OWNER.get_or_init(|| Mutex::new(None))
}

#[must_use]
pub fn prepare_process_invocation() -> NativeCliStartupResult {
    let invocation = match parse_process_invocation(std::env::args_os().skip(1)) {
        Ok(invocation) => invocation,
        Err(_) => return startup_rejected(NativeCliFailureKind::InvalidArguments),
    };
    prepare_invocation(invocation)
}

#[must_use]
pub fn ensure_owner() -> NativeCliStartupResult {
    if owner()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .is_some()
    {
        return startup_owner();
    }
    prepare_invocation(Invocation::Gui)
}

#[cfg(unix)]
fn prepare_invocation(invocation: Invocation) -> NativeCliStartupResult {
    use unix::{claim_instance, forward_action, InstanceClaim, RuntimePaths};

    let paths = match RuntimePaths::discover() {
        Ok(paths) => paths,
        Err(error) => return startup_rejected(map_ipc_error(&error)),
    };
    match invocation {
        Invocation::Gui => match claim_instance(&paths) {
            Ok(InstanceClaim::Owner { listener, token }) => {
                start_owner(listener, token, paths, None)
            }
            Ok(InstanceClaim::Existing) => {
                match forward_action(&paths, ForwardAction::Activate, CLIENT_TIMEOUT) {
                    Ok(ForwardResponse::Accepted) => startup_forwarded(),
                    Ok(ForwardResponse::Rejected { code, .. }) => {
                        startup_rejected(map_response(code))
                    }
                    Err(error) => startup_rejected(map_ipc_error(&error)),
                }
            }
            Err(error) => startup_rejected(map_ipc_error(&error)),
        },
        Invocation::Forward {
            action,
            start_if_absent,
        } => match forward_action(&paths, action.clone(), CLIENT_TIMEOUT) {
            Ok(ForwardResponse::Accepted) => startup_forwarded(),
            Ok(ForwardResponse::Rejected { code, .. }) => startup_rejected(map_response(code)),
            Err(unix::IpcError::NotRunning) if start_if_absent => match claim_instance(&paths) {
                Ok(InstanceClaim::Owner { listener, token }) => {
                    start_owner(listener, token, paths, Some(action))
                }
                Ok(InstanceClaim::Existing) => {
                    match forward_action(&paths, action, CLIENT_TIMEOUT) {
                        Ok(ForwardResponse::Accepted) => startup_forwarded(),
                        Ok(ForwardResponse::Rejected { code, .. }) => {
                            startup_rejected(map_response(code))
                        }
                        Err(error) => startup_rejected(map_ipc_error(&error)),
                    }
                }
                Err(error) => startup_rejected(map_ipc_error(&error)),
            },
            Err(error) => startup_rejected(map_ipc_error(&error)),
        },
    }
}

#[cfg(windows)]
fn prepare_windows_invocation(invocation: Invocation) -> NativeCliStartupResult {
    use windows::{claim_instance, forward_action, InstanceClaim, RuntimeAddress};

    let address = match RuntimeAddress::discover() {
        Ok(address) => address,
        Err(error) => return startup_rejected(map_windows_ipc_error(&error)),
    };
    match invocation {
        Invocation::Gui => match claim_instance(&address) {
            Ok(InstanceClaim::Owner { listener, token }) => {
                start_windows_owner(listener, token, None)
            }
            Ok(InstanceClaim::Existing) => {
                match forward_action(&address, ForwardAction::Activate, CLIENT_TIMEOUT) {
                    Ok(ForwardResponse::Accepted) => startup_forwarded(),
                    Ok(ForwardResponse::Rejected { code, .. }) => {
                        startup_rejected(map_response(code))
                    }
                    Err(error) => startup_rejected(map_windows_ipc_error(&error)),
                }
            }
            Err(error) => startup_rejected(map_windows_ipc_error(&error)),
        },
        Invocation::Forward {
            action,
            start_if_absent,
        } => match forward_action(&address, action.clone(), CLIENT_TIMEOUT) {
            Ok(ForwardResponse::Accepted) => startup_forwarded(),
            Ok(ForwardResponse::Rejected { code, .. }) => startup_rejected(map_response(code)),
            Err(windows::IpcError::NotRunning | windows::IpcError::CredentialMissing)
                if start_if_absent =>
            {
                match claim_instance(&address) {
                    Ok(InstanceClaim::Owner { listener, token }) => {
                        start_windows_owner(listener, token, Some(action))
                    }
                    Ok(InstanceClaim::Existing) => {
                        match forward_action(&address, action, CLIENT_TIMEOUT) {
                            Ok(ForwardResponse::Accepted) => startup_forwarded(),
                            Ok(ForwardResponse::Rejected { code, .. }) => {
                                startup_rejected(map_response(code))
                            }
                            Err(error) => startup_rejected(map_windows_ipc_error(&error)),
                        }
                    }
                    Err(error) => startup_rejected(map_windows_ipc_error(&error)),
                }
            }
            Err(error) => startup_rejected(map_windows_ipc_error(&error)),
        },
    }
}

#[cfg(windows)]
fn prepare_invocation(invocation: Invocation) -> NativeCliStartupResult {
    prepare_windows_invocation(invocation)
}

#[cfg(not(any(unix, windows)))]
fn prepare_invocation(_: Invocation) -> NativeCliStartupResult {
    startup_rejected(NativeCliFailureKind::UnsupportedPlatform)
}

#[cfg(unix)]
fn start_owner(
    listener: std::os::unix::net::UnixListener,
    token: [u8; protocol::TOKEN_LEN],
    paths: unix::RuntimePaths,
    initial_action: Option<ForwardAction>,
) -> NativeCliStartupResult {
    let (sender, receiver) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
    let handler_sender = sender;
    let handler = Arc::new(move |action: ForwardAction| {
        let action = match validate_action(action) {
            Ok(action) => action,
            Err(response) => return response,
        };
        let request_id = NEXT_REQUEST_ID.fetch_add(1, Ordering::Relaxed).max(1);
        let (response, response_receiver) = mpsc::sync_channel(1);
        match handler_sender.try_send(QueuedCommand {
            request_id,
            action,
            response: Some(response),
        }) {
            Ok(()) => response_receiver
                .recv_timeout(APPLICATION_RESPONSE_TIMEOUT)
                .unwrap_or_else(|error| ForwardResponse::Rejected {
                    code: if matches!(error, mpsc::RecvTimeoutError::Timeout) {
                        ResponseCode::Busy
                    } else {
                        ResponseCode::Internal
                    },
                    detail: "application_response_unavailable".to_owned(),
                }),
            Err(TrySendError::Full(_)) => ForwardResponse::Rejected {
                code: ResponseCode::Busy,
                detail: "command_queue_full".to_owned(),
            },
            Err(TrySendError::Disconnected(_)) => ForwardResponse::Rejected {
                code: ResponseCode::Internal,
                detail: "command_queue_closed".to_owned(),
            },
        }
    });
    let server = match unix::ForwardingServer::start(listener, token, paths, handler) {
        Ok(server) => server,
        Err(error) => return startup_rejected(map_ipc_error(&error)),
    };
    let mut initial = VecDeque::new();
    if let Some(action) = initial_action {
        let action = match validate_action(action) {
            Ok(action) => action,
            Err(ForwardResponse::Rejected { code, .. }) => {
                return startup_rejected(map_response(code))
            }
            Err(ForwardResponse::Accepted) => {
                unreachable!("validation cannot synthesize acceptance")
            }
        };
        initial.push_back(QueuedCommand {
            // The process that won ownership carries its own initial command.
            // It has no waiting IPC client, so reserve zero as the explicit
            // fire-and-forget request identifier.
            request_id: 0,
            action,
            response: None,
        });
    }
    *owner()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(RuntimeOwner {
        _unix_server: server,
        receiver,
        initial,
        awaiting: HashMap::new(),
    });
    startup_owner()
}

#[cfg(windows)]
fn start_windows_owner(
    listener: windows::PipeListener,
    token: [u8; protocol::TOKEN_LEN],
    initial_action: Option<ForwardAction>,
) -> NativeCliStartupResult {
    let (sender, receiver) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
    let handler = Arc::new(move |action: ForwardAction| {
        let action = match validate_action(action) {
            Ok(action) => action,
            Err(response) => return response,
        };
        let request_id = NEXT_REQUEST_ID.fetch_add(1, Ordering::Relaxed).max(1);
        let (response, response_receiver) = mpsc::sync_channel(1);
        match sender.try_send(QueuedCommand {
            request_id,
            action,
            response: Some(response),
        }) {
            Ok(()) => response_receiver
                .recv_timeout(APPLICATION_RESPONSE_TIMEOUT)
                .unwrap_or_else(|error| ForwardResponse::Rejected {
                    code: if matches!(error, mpsc::RecvTimeoutError::Timeout) {
                        ResponseCode::Busy
                    } else {
                        ResponseCode::Internal
                    },
                    detail: "application_response_unavailable".to_owned(),
                }),
            Err(TrySendError::Full(_)) => rejected(ResponseCode::Busy, "command_queue_full"),
            Err(TrySendError::Disconnected(_)) => {
                rejected(ResponseCode::Internal, "command_queue_closed")
            }
        }
    });
    let server = match windows::ForwardingServer::start(listener, token, handler) {
        Ok(server) => server,
        Err(error) => return startup_rejected(map_windows_ipc_error(&error)),
    };
    let mut initial = VecDeque::new();
    if let Some(action) = initial_action {
        let action = match validate_action(action) {
            Ok(action) => action,
            Err(ForwardResponse::Rejected { code, .. }) => {
                return startup_rejected(map_response(code));
            }
            Err(ForwardResponse::Accepted) => unreachable!("validation cannot accept"),
        };
        initial.push_back(QueuedCommand {
            request_id: 0,
            action,
            response: None,
        });
    }
    *owner()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(RuntimeOwner {
        _windows_server: server,
        receiver,
        initial,
        awaiting: HashMap::new(),
    });
    startup_owner()
}

#[cfg(unix)]
fn validate_action(action: ForwardAction) -> Result<ForwardAction, ForwardResponse> {
    if let ForwardAction::OpenRemoteRepository { alias, path } = &action {
        validate_remote_action(alias, path)?;
        return Ok(action);
    }
    let ForwardAction::OpenRepository { native_path } = action else {
        return Ok(action);
    };
    let canonical =
        unix::validate_repository_path(&native_path).map_err(|_| ForwardResponse::Rejected {
            code: ResponseCode::InvalidPath,
            detail: "invalid_repository_path".to_owned(),
        })?;
    if !discover_repository(&canonical) {
        return Err(ForwardResponse::Rejected {
            code: ResponseCode::NotRepository,
            detail: "not_a_repository".to_owned(),
        });
    }
    use std::os::unix::ffi::OsStrExt;
    Ok(ForwardAction::OpenRepository {
        native_path: canonical.as_os_str().as_bytes().to_vec(),
    })
}

#[cfg(windows)]
fn validate_action(action: ForwardAction) -> Result<ForwardAction, ForwardResponse> {
    use std::os::windows::ffi::{OsStrExt, OsStringExt};

    if let ForwardAction::OpenRemoteRepository { alias, path } = &action {
        validate_remote_action(alias, path)?;
        return Ok(action);
    }
    let ForwardAction::OpenRepository { native_path } = action else {
        return Ok(action);
    };
    if native_path.is_empty() || !native_path.len().is_multiple_of(2) {
        return Err(rejected(
            ResponseCode::InvalidPath,
            "invalid_repository_path",
        ));
    }
    let wide = native_path
        .chunks_exact(2)
        .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
        .collect::<Vec<_>>();
    if wide.contains(&0) {
        return Err(rejected(
            ResponseCode::InvalidPath,
            "invalid_repository_path",
        ));
    }
    let path = PathBuf::from(std::ffi::OsString::from_wide(&wide));
    if !path.is_absolute() {
        return Err(rejected(
            ResponseCode::InvalidPath,
            "invalid_repository_path",
        ));
    }
    let canonical = std::fs::canonicalize(path)
        .map_err(|_| rejected(ResponseCode::InvalidPath, "invalid_repository_path"))?;
    if !canonical.is_dir() {
        return Err(rejected(
            ResponseCode::InvalidPath,
            "invalid_repository_path",
        ));
    }
    if !discover_repository(&canonical) {
        return Err(rejected(ResponseCode::NotRepository, "not_a_repository"));
    }
    let bytes = canonical
        .as_os_str()
        .encode_wide()
        .flat_map(u16::to_le_bytes)
        .collect();
    Ok(ForwardAction::OpenRepository { native_path: bytes })
}

#[cfg(any(unix, windows))]
fn discover_repository(path: &Path) -> bool {
    use devmil_git::activity::{ActivityEvent, ActivityId};
    use devmil_git::process::ActivityGitRunner;
    use devmil_git::repository::{DiscoveryRequest, RepositoryDiscovery};
    use devmil_git::types::RepositoryPath;

    let Ok(path) = RepositoryPath::new(path) else {
        return false;
    };
    let request = DiscoveryRequest {
        path,
        discover_parents: false,
    };
    let mut discard = |_event: ActivityEvent| {};
    RepositoryDiscovery::default()
        .discover(&request, &mut |command| {
            ActivityGitRunner::run(
                command,
                ActivityId::new(1).expect("constant activity identity is valid"),
                None,
                &mut discard,
            )
        })
        .is_ok()
}

#[must_use]
pub fn poll() -> NativeCliPollResult {
    #[cfg(any(unix, windows))]
    {
        let mut guard = owner()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(owner) = guard.as_mut() else {
            return NativeCliPollResult {
                command: None,
                failure: Some(NativeCliFailureKind::Transport),
            };
        };
        let queued = owner
            .initial
            .pop_front()
            .or_else(|| match owner.receiver.try_recv() {
                Ok(command) => Some(command),
                Err(TryRecvError::Empty) => None,
                Err(TryRecvError::Disconnected) => None,
            });
        let Some(queued) = queued else {
            return NativeCliPollResult {
                command: None,
                failure: None,
            };
        };
        if let Some(response) = queued.response {
            owner.awaiting.insert(queued.request_id, response);
        }
        NativeCliPollResult {
            command: Some(map_command(queued.request_id, queued.action)),
            failure: None,
        }
    }
    #[cfg(not(any(unix, windows)))]
    NativeCliPollResult {
        command: None,
        failure: Some(NativeCliFailureKind::UnsupportedPlatform),
    }
}

#[must_use]
pub fn respond(request_id: u64, response: NativeCliResponseKind) -> bool {
    #[cfg(any(unix, windows))]
    {
        let sender = owner()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_mut()
            .and_then(|owner| owner.awaiting.remove(&request_id));
        let Some(sender) = sender else {
            return request_id == 0;
        };
        sender.send(map_native_response(response)).is_ok()
    }
    #[cfg(not(any(unix, windows)))]
    false
}

pub fn shutdown() {
    *owner()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
}

fn map_command(request_id: u64, action: ForwardAction) -> NativeCliCommand {
    match action {
        ForwardAction::Activate => NativeCliCommand {
            request_id,
            kind: NativeCliCommandKind::Activate,
            path_platform: None,
            path_units: Vec::new(),
            pull_strategy: None,
            remote_alias: None,
        },
        ForwardAction::OpenRepository { native_path } => {
            let (path_platform, path_units) = map_native_path(native_path);
            NativeCliCommand {
                request_id,
                kind: NativeCliCommandKind::OpenRepository,
                path_platform: Some(path_platform),
                path_units,
                pull_strategy: None,
                remote_alias: None,
            }
        }
        ForwardAction::OpenRemoteRepository { alias, path } => NativeCliCommand {
            request_id,
            kind: NativeCliCommandKind::OpenRemoteRepository,
            path_platform: Some(NativeCliPathPlatform::Unix),
            path_units: path.into_iter().map(u32::from).collect(),
            pull_strategy: None,
            remote_alias: Some(alias),
        },
        ForwardAction::Invoke(AllowedCommand::Refresh) => {
            simple_command(request_id, NativeCliCommandKind::Refresh)
        }
        ForwardAction::Invoke(AllowedCommand::Fetch) => {
            simple_command(request_id, NativeCliCommandKind::Fetch)
        }
        ForwardAction::Invoke(AllowedCommand::Pull { strategy }) => NativeCliCommand {
            request_id,
            kind: NativeCliCommandKind::Pull,
            path_platform: None,
            path_units: Vec::new(),
            remote_alias: None,
            pull_strategy: Some(match strategy {
                AllowedPullStrategy::FastForwardOnly => NativeCliPullStrategy::FastForwardOnly,
                AllowedPullStrategy::FastForwardIfPossible => {
                    NativeCliPullStrategy::FastForwardIfPossible
                }
                AllowedPullStrategy::Rebase => NativeCliPullStrategy::Rebase,
            }),
        },
    }
}

fn map_native_path(native_path: Vec<u8>) -> (NativeCliPathPlatform, Vec<u32>) {
    #[cfg(unix)]
    {
        (
            NativeCliPathPlatform::Unix,
            native_path.into_iter().map(u32::from).collect(),
        )
    }
    #[cfg(windows)]
    {
        (
            NativeCliPathPlatform::Windows,
            native_path
                .chunks_exact(2)
                .map(|pair| u32::from(u16::from_le_bytes([pair[0], pair[1]])))
                .collect(),
        )
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = native_path;
        (NativeCliPathPlatform::Unix, Vec::new())
    }
}

fn simple_command(request_id: u64, kind: NativeCliCommandKind) -> NativeCliCommand {
    NativeCliCommand {
        request_id,
        kind,
        path_platform: None,
        path_units: Vec::new(),
        pull_strategy: None,
        remote_alias: None,
    }
}

fn map_native_response(response: NativeCliResponseKind) -> ForwardResponse {
    match response {
        NativeCliResponseKind::Accepted => ForwardResponse::Accepted,
        NativeCliResponseKind::Precondition => {
            rejected(ResponseCode::Precondition, "precondition_failed")
        }
        NativeCliResponseKind::Busy => rejected(ResponseCode::Busy, "application_busy"),
        NativeCliResponseKind::Unsupported => {
            rejected(ResponseCode::UnsupportedCommand, "unsupported_command")
        }
        NativeCliResponseKind::Internal => {
            rejected(ResponseCode::Internal, "application_unavailable")
        }
    }
}

fn rejected(code: ResponseCode, detail: &str) -> ForwardResponse {
    ForwardResponse::Rejected {
        code,
        detail: detail.to_owned(),
    }
}

fn parse_process_invocation(
    arguments: impl IntoIterator<Item = std::ffi::OsString>,
) -> Result<Invocation, ParseError> {
    let mut arguments = arguments.into_iter().collect::<Vec<_>>();
    if arguments.is_empty() {
        return Ok(Invocation::Gui);
    }
    let start_if_absent = if arguments
        .last()
        .is_some_and(|value| value == "--start-if-absent")
    {
        arguments.pop();
        true
    } else {
        false
    };
    let action = if arguments.first().is_some_and(|value| value == "--open") {
        if arguments.len() != 2 {
            return Err(ParseError::InvalidArguments);
        }
        open_action(&arguments[1])?
    } else if arguments.first().is_some_and(|value| value == "--remote") {
        if arguments.len() != 3 {
            return Err(ParseError::InvalidArguments);
        }
        remote_action(&arguments[1], &arguments[2])?
    } else if arguments.first().is_some_and(|value| value == "--command") {
        parse_command(&arguments[1..])?
    } else if arguments.len() == 1 && !arguments[0].to_string_lossy().starts_with('-') {
        open_action(&arguments[0])?
    } else {
        return Err(ParseError::InvalidArguments);
    };
    let start_if_absent = start_if_absent
        || matches!(
            action,
            ForwardAction::OpenRepository { .. } | ForwardAction::OpenRemoteRepository { .. }
        );
    Ok(Invocation::Forward {
        action,
        start_if_absent,
    })
}

fn parse_command(arguments: &[std::ffi::OsString]) -> Result<ForwardAction, ParseError> {
    let id = arguments
        .first()
        .and_then(|value| value.to_str())
        .ok_or(ParseError::InvalidArguments)?;
    let command = match id {
        "repository.refresh" if arguments.len() == 1 => AllowedCommand::Refresh,
        "repository.fetch" if arguments.len() == 1 => AllowedCommand::Fetch,
        "repository.pull" if arguments.len() == 3 && arguments[1] == "--strategy" => {
            let strategy = match arguments[2].to_str() {
                Some("ff-only") => AllowedPullStrategy::FastForwardOnly,
                Some("ff-if-possible") => AllowedPullStrategy::FastForwardIfPossible,
                Some("rebase") => AllowedPullStrategy::Rebase,
                _ => return Err(ParseError::InvalidArguments),
            };
            AllowedCommand::Pull { strategy }
        }
        _ => return Err(ParseError::InvalidArguments),
    };
    Ok(ForwardAction::Invoke(command))
}

fn open_action(path: &std::ffi::OsStr) -> Result<ForwardAction, ParseError> {
    if let Some(url) = path
        .to_str()
        .and_then(|path| path.strip_prefix(SSH_URL_PREFIX))
    {
        return ssh_url_action(url);
    }
    let mut path = PathBuf::from(path);
    if path.is_relative() {
        path = std::env::current_dir()
            .map_err(|_| ParseError::InvalidPath)?
            .join(path);
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        Ok(ForwardAction::OpenRepository {
            native_path: path.as_os_str().as_bytes().to_vec(),
        })
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        let native_path = path
            .as_os_str()
            .encode_wide()
            .flat_map(u16::to_le_bytes)
            .collect();
        Ok(ForwardAction::OpenRepository { native_path })
    }
    #[cfg(not(any(unix, windows)))]
    Err(ParseError::InvalidPath)
}

const SSH_URL_PREFIX: &str = "ssh://";

/// `--remote <alias> <path>`: an absolute POSIX path on a saved host.
fn remote_action(
    alias: &std::ffi::OsStr,
    path: &std::ffi::OsStr,
) -> Result<ForwardAction, ParseError> {
    let alias = alias.to_str().ok_or(ParseError::InvalidArguments)?;
    #[cfg(unix)]
    let path = path.as_encoded_bytes().to_vec();
    #[cfg(not(unix))]
    let path = path
        .to_str()
        .ok_or(ParseError::InvalidPath)?
        .as_bytes()
        .to_vec();
    remote_target(alias.to_owned(), path)
}

/// `ssh://<host-or-user@host>/<path>`, with a percent-decoded path.
/// Ports and SSH options are refused.
fn ssh_url_action(rest: &str) -> Result<ForwardAction, ParseError> {
    let split = rest.find('/').ok_or(ParseError::InvalidPath)?;
    let (alias, path) = rest.split_at(split);
    remote_target(alias.to_owned(), percent_decode(path)?)
}

fn percent_decode(text: &str) -> Result<Vec<u8>, ParseError> {
    let bytes = text.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            let hex = bytes
                .get(index + 1..index + 3)
                .and_then(|hex| std::str::from_utf8(hex).ok())
                .and_then(|hex| u8::from_str_radix(hex, 16).ok())
                .ok_or(ParseError::InvalidPath)?;
            decoded.push(hex);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    Ok(decoded)
}

fn remote_target(alias: String, path: Vec<u8>) -> Result<ForwardAction, ParseError> {
    if !valid_remote_alias(&alias) {
        return Err(ParseError::InvalidArguments);
    }
    if !valid_remote_path(&path) {
        return Err(ParseError::InvalidPath);
    }
    Ok(ForwardAction::OpenRemoteRepository { alias, path })
}

/// A bounded SSH host or user@host destination, matching profile validation.
fn valid_remote_alias(alias: &str) -> bool {
    let mut parts = alias.split('@');
    let valid_part = |part: &str| {
        part.as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
            && part
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
    };
    alias.len() <= protocol::MAX_ALIAS_LEN
        && valid_part(parts.next().unwrap_or_default())
        && parts.next().is_none_or(valid_part)
        && parts.next().is_none()
}

/// An absolute POSIX path without NUL that the remote helper may accept.
fn valid_remote_path(path: &[u8]) -> bool {
    path.first() == Some(&b'/') && !path.contains(&0) && path.len() <= protocol::MAX_PATH_LEN
}

/// A remote target is only checked for form here: the window looks up the
/// host and the helper decides whether a repository is there.
fn validate_remote_action(alias: &str, path: &[u8]) -> Result<(), ForwardResponse> {
    if valid_remote_alias(alias) && valid_remote_path(path) {
        Ok(())
    } else {
        Err(rejected(ResponseCode::InvalidPath, "invalid_remote_target"))
    }
}

const fn startup_owner() -> NativeCliStartupResult {
    NativeCliStartupResult {
        state: NativeCliStartupState::Owner,
        failure: None,
    }
}

const fn startup_forwarded() -> NativeCliStartupResult {
    NativeCliStartupResult {
        state: NativeCliStartupState::Forwarded,
        failure: None,
    }
}

const fn startup_rejected(failure: NativeCliFailureKind) -> NativeCliStartupResult {
    NativeCliStartupResult {
        state: NativeCliStartupState::Rejected,
        failure: Some(failure),
    }
}

const fn map_response(code: ResponseCode) -> NativeCliFailureKind {
    match code {
        ResponseCode::Authentication | ResponseCode::Replay => NativeCliFailureKind::Authentication,
        ResponseCode::InvalidPath => NativeCliFailureKind::InvalidPath,
        ResponseCode::NotRepository => NativeCliFailureKind::NotRepository,
        ResponseCode::UnsupportedCommand => NativeCliFailureKind::InvalidArguments,
        ResponseCode::Busy | ResponseCode::Internal => NativeCliFailureKind::Busy,
        ResponseCode::Precondition => NativeCliFailureKind::Precondition,
    }
}

#[cfg(unix)]
fn map_ipc_error(error: &unix::IpcError) -> NativeCliFailureKind {
    match error {
        #[cfg(not(any(target_os = "linux", target_os = "android", target_os = "macos")))]
        unix::IpcError::UnsupportedPlatform => NativeCliFailureKind::UnsupportedPlatform,
        unix::IpcError::NotRunning => NativeCliFailureKind::NotRunning,
        unix::IpcError::Authentication
        | unix::IpcError::InsecureRuntimeDirectory
        | unix::IpcError::InsecureSocket
        | unix::IpcError::InsecureToken => NativeCliFailureKind::Authentication,
        unix::IpcError::InvalidPath => NativeCliFailureKind::InvalidPath,
        unix::IpcError::Protocol(protocol::ProtocolError::VersionSkew { .. }) => {
            NativeCliFailureKind::VersionSkew
        }
        unix::IpcError::TimedOut => NativeCliFailureKind::Busy,
        _ => NativeCliFailureKind::Transport,
    }
}

#[cfg(windows)]
fn map_windows_ipc_error(error: &windows::IpcError) -> NativeCliFailureKind {
    match error {
        windows::IpcError::NotRunning | windows::IpcError::CredentialMissing => {
            NativeCliFailureKind::NotRunning
        }
        windows::IpcError::Authentication
        | windows::IpcError::InsecurePipe
        | windows::IpcError::InsecureCredential => NativeCliFailureKind::Authentication,
        windows::IpcError::Protocol(protocol::ProtocolError::VersionSkew { .. }) => {
            NativeCliFailureKind::VersionSkew
        }
        windows::IpcError::TimedOut => NativeCliFailureKind::Busy,
        _ => NativeCliFailureKind::Transport,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    use std::sync::atomic::{AtomicU64, Ordering};

    #[cfg(unix)]
    static FIXTURE_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    #[test]
    fn grammar_is_closed_and_open_paths_are_startable() {
        let open = parse_process_invocation([std::ffi::OsString::from(".")]).unwrap();
        assert!(matches!(
            open,
            Invocation::Forward {
                start_if_absent: true,
                ..
            }
        ));
        assert_eq!(
            parse_process_invocation(["--command".into(), "repository.push".into()]),
            Err(ParseError::InvalidArguments)
        );
        assert!(matches!(
            parse_process_invocation([
                "--command".into(),
                "repository.pull".into(),
                "--strategy".into(),
                "rebase".into(),
            ])
            .unwrap(),
            Invocation::Forward {
                action: ForwardAction::Invoke(AllowedCommand::Pull {
                    strategy: AllowedPullStrategy::Rebase
                }),
                start_if_absent: false,
            }
        ));
    }

    fn remote(alias: &str, path: &[u8]) -> Invocation {
        Invocation::Forward {
            action: ForwardAction::OpenRemoteRepository {
                alias: alias.into(),
                path: path.to_vec(),
            },
            start_if_absent: true,
        }
    }

    #[test]
    fn remote_opens_name_a_saved_alias_and_an_absolute_path() {
        assert_eq!(
            parse_process_invocation([
                "--remote".into(),
                "fedora".into(),
                "/home/me/notelama".into(),
            ]),
            Ok(remote("fedora", b"/home/me/notelama"))
        );
        assert_eq!(
            parse_process_invocation(["--remote".into(), "me@fedora".into(), "/home/me".into()]),
            Ok(remote("me@fedora", b"/home/me"))
        );
        assert_eq!(
            parse_process_invocation(["ssh://me@fedora/home/me".into()]),
            Ok(remote("me@fedora", b"/home/me"))
        );
        // The URL form, as editors and "open with" integrations pass it.
        assert_eq!(
            parse_process_invocation(["ssh://fedora/home/me/my%20repo".into()]),
            Ok(remote("fedora", b"/home/me/my repo"))
        );
        assert_eq!(
            parse_process_invocation(["--open".into(), "ssh://dev-box.lan/srv/git".into()]),
            Ok(remote("dev-box.lan", b"/srv/git"))
        );
        for refused in [
            vec!["--remote", "fedora", "home/me/relative"],
            vec!["--remote", "me@@fedora", "/home/me"],
            vec!["--remote", "-oProxyCommand=x", "/home/me"],
            vec!["--remote", "fedora"],
            vec!["ssh://me@-fedora/home/me"],
            vec!["ssh://fedora:22/home/me"],
            vec!["ssh://fedora"],
            vec!["ssh://fedora/home/%zz"],
            vec!["ssh://fedora/home/%00"],
        ] {
            assert!(
                parse_process_invocation(refused.iter().map(std::ffi::OsString::from)).is_err(),
                "{refused:?}"
            );
        }
    }

    #[test]
    fn forwarded_remote_targets_are_checked_again_and_mapped() {
        assert!(validate_action(ForwardAction::OpenRemoteRepository {
            alias: "fedora".into(),
            path: b"relative".to_vec(),
        })
        .is_err());
        let action = ForwardAction::OpenRemoteRepository {
            alias: "fedora".into(),
            path: b"/srv/git".to_vec(),
        };
        let command = map_command(5, validate_action(action).unwrap());
        assert_eq!(command.kind, NativeCliCommandKind::OpenRemoteRepository);
        assert_eq!(command.remote_alias.as_deref(), Some("fedora"));
        assert_eq!(command.path_platform, Some(NativeCliPathPlatform::Unix));
        assert_eq!(
            command.path_units,
            b"/srv/git"
                .iter()
                .copied()
                .map(u32::from)
                .collect::<Vec<_>>()
        );
    }

    #[cfg(unix)]
    #[test]
    fn repository_validation_is_exact_and_canonical() {
        use std::os::unix::ffi::OsStrExt;

        let root = std::env::temp_dir().join(format!(
            "gitlama-cli-repository-{}-{}",
            std::process::id(),
            FIXTURE_SEQUENCE.fetch_add(1, Ordering::Relaxed),
        ));
        let repository = root.join("repository");
        let nested = repository.join("nested");
        std::fs::create_dir_all(&nested).unwrap();
        assert!(matches!(
            validate_action(ForwardAction::OpenRepository {
                native_path: nested.as_os_str().as_bytes().to_vec(),
            }),
            Err(ForwardResponse::Rejected {
                code: ResponseCode::NotRepository,
                ..
            })
        ));
        let output = std::process::Command::new("git")
            .args(["init", "--quiet"])
            .current_dir(&repository)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(matches!(
            validate_action(ForwardAction::OpenRepository {
                native_path: repository.as_os_str().as_bytes().to_vec(),
            }),
            Ok(ForwardAction::OpenRepository { .. })
        ));
        assert!(matches!(
            validate_action(ForwardAction::OpenRepository {
                native_path: nested.as_os_str().as_bytes().to_vec(),
            }),
            Err(ForwardResponse::Rejected {
                code: ResponseCode::NotRepository,
                ..
            })
        ));
        std::fs::remove_dir_all(root).unwrap();
    }
}
