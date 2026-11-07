//! Owner-only Unix-domain transport for command forwarding.

use super::protocol::{
    read_request, read_response, write_request, write_response, ForwardAction, ForwardRequest,
    ForwardResponse, ProtocolError, ResponseCode, MAX_FRAME_LEN, NONCE_LEN, TOKEN_LEN,
};
use rustix::process::getuid;
use std::collections::{BTreeSet, VecDeque};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{DirBuilderExt, FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const DIRECTORY_MODE: u32 = 0o700;
const PRIVATE_FILE_MODE: u32 = 0o600;
const MAX_REPLAY_NONCES: usize = 1024;
const INSTANCE_ELECTION_RETRIES: usize = 32;
const MAX_CLIENTS: usize = 4;
static TOKEN_TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum IpcError {
    #[cfg(not(any(target_os = "linux", target_os = "android", target_os = "macos")))]
    UnsupportedPlatform,
    InsecureRuntimeDirectory,
    InsecureSocket,
    InsecureToken,
    NotRunning,
    Authentication,
    TimedOut,
    InvalidPath,
    Io(std::io::ErrorKind),
    Protocol(ProtocolError),
}

impl From<ProtocolError> for IpcError {
    fn from(value: ProtocolError) -> Self {
        Self::Protocol(value)
    }
}

#[derive(Clone, Debug)]
pub struct RuntimePaths {
    pub directory: PathBuf,
    pub socket: PathBuf,
    pub token: PathBuf,
}

impl RuntimePaths {
    #[must_use]
    pub fn under(directory: PathBuf) -> Self {
        Self {
            socket: directory.join("forward.sock"),
            token: directory.join("forward.token"),
            directory,
        }
    }

    pub fn discover() -> Result<Self, IpcError> {
        runtime_paths_from(
            std::env::var_os("GITLAMA_RUNTIME_DIR").as_deref(),
            std::env::var_os("XDG_RUNTIME_DIR").as_deref(),
            &std::env::temp_dir(),
            getuid().as_raw(),
        )
    }
}

fn runtime_paths_from(
    product_configured: Option<&std::ffi::OsStr>,
    configured: Option<&std::ffi::OsStr>,
    temporary: &Path,
    uid: u32,
) -> Result<RuntimePaths, IpcError> {
    let directory = if let Some(product_configured) = product_configured {
        let base = PathBuf::from(product_configured);
        if !base.is_absolute() {
            return Err(IpcError::InsecureRuntimeDirectory);
        }
        base
    } else if let Some(configured) = configured {
        let base = PathBuf::from(configured);
        if !base.is_absolute() {
            return Err(IpcError::InsecureRuntimeDirectory);
        }
        base.join("gitlama")
    } else {
        if !temporary.is_absolute() {
            return Err(IpcError::InsecureRuntimeDirectory);
        }
        temporary.join(format!("gitlama-{uid}"))
    };
    Ok(RuntimePaths::under(directory))
}

#[derive(Debug)]
pub enum InstanceClaim {
    Owner {
        listener: UnixListener,
        token: [u8; TOKEN_LEN],
    },
    Existing,
}

pub fn claim_instance(paths: &RuntimePaths) -> Result<InstanceClaim, IpcError> {
    prepare_directory(&paths.directory)?;
    let token = load_or_create_token(&paths.token)?;
    for attempt in 0..INSTANCE_ELECTION_RETRIES {
        match UnixStream::connect(&paths.socket) {
            Ok(_) => return Ok(InstanceClaim::Existing),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) if error.kind() == std::io::ErrorKind::ConnectionRefused => {
                match validate_socket_type_and_owner(&paths.socket) {
                    Ok(()) => {}
                    Err(IpcError::Io(std::io::ErrorKind::NotFound)) => continue,
                    Err(error) => return Err(error),
                }
                if attempt + 1 < INSTANCE_ELECTION_RETRIES {
                    std::thread::sleep(Duration::from_millis(1));
                    continue;
                }
                prepare_directory(&paths.directory)?;
                validate_private_entry(&paths.socket, EntryKind::Socket)?;
                match fs::remove_file(&paths.socket) {
                    Ok(()) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => return Err(io_error(error)),
                }
            }
            Err(error) => return Err(io_error(error)),
        }
        match UnixListener::bind(&paths.socket) {
            Ok(listener) => {
                fs::set_permissions(&paths.socket, fs::Permissions::from_mode(PRIVATE_FILE_MODE))
                    .map_err(io_error)?;
                validate_private_entry(&paths.socket, EntryKind::Socket)?;
                return Ok(InstanceClaim::Owner { listener, token });
            }
            Err(error)
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::AddrInUse | std::io::ErrorKind::AlreadyExists
                ) =>
            {
                validate_socket_type_and_owner(&paths.socket)?;
                match UnixStream::connect(&paths.socket) {
                    Ok(_) => return Ok(InstanceClaim::Existing),
                    Err(error)
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
                        ) => {}
                    Err(error) => return Err(io_error(error)),
                }
            }
            Err(error) => return Err(io_error(error)),
        }
    }
    Err(IpcError::Io(std::io::ErrorKind::WouldBlock))
}

pub fn forward_action(
    paths: &RuntimePaths,
    action: ForwardAction,
    timeout: Duration,
) -> Result<ForwardResponse, IpcError> {
    prepare_directory(&paths.directory)?;
    validate_private_entry(&paths.socket, EntryKind::Socket).map_err(|error| match error {
        IpcError::Io(std::io::ErrorKind::NotFound) => IpcError::NotRunning,
        other => other,
    })?;
    let token = load_token(&paths.token)?;
    let mut nonce = [0; NONCE_LEN];
    File::open("/dev/urandom")
        .and_then(|mut source| source.read_exact(&mut nonce))
        .map_err(io_error)?;
    forward_request(
        paths,
        &ForwardRequest {
            nonce,
            token,
            action,
        },
        timeout,
    )
}

fn forward_request(
    paths: &RuntimePaths,
    request: &ForwardRequest,
    timeout: Duration,
) -> Result<ForwardResponse, IpcError> {
    let mut stream = UnixStream::connect(&paths.socket).map_err(|error| {
        if matches!(
            error.kind(),
            std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
        ) {
            IpcError::NotRunning
        } else {
            io_error(error)
        }
    })?;
    stream.set_nonblocking(true).map_err(io_error)?;
    let deadline = Instant::now() + timeout;
    let mut encoded = Vec::new();
    write_request(&mut encoded, request)?;
    write_all_bounded(&mut stream, &encoded, deadline)?;
    let mut length = [0; 4];
    read_exact_bounded(&mut stream, &mut length, deadline)?;
    let length = usize::try_from(u32::from_be_bytes(length))
        .map_err(|_| IpcError::Protocol(ProtocolError::Oversized))?;
    if length > MAX_FRAME_LEN {
        return Err(IpcError::Protocol(ProtocolError::Oversized));
    }
    let mut frame = Vec::with_capacity(length + 4);
    frame.extend_from_slice(
        &u32::try_from(length)
            .map_err(|_| IpcError::Protocol(ProtocolError::Oversized))?
            .to_be_bytes(),
    );
    let mut payload = vec![0; length];
    read_exact_bounded(&mut stream, &mut payload, deadline)?;
    frame.extend_from_slice(&payload);
    Ok(read_response(&mut frame.as_slice())?)
}

#[derive(Default)]
struct ReplayState {
    ordered: VecDeque<[u8; NONCE_LEN]>,
    seen: BTreeSet<[u8; NONCE_LEN]>,
}

#[derive(Default)]
struct ReplayGuard {
    state: Mutex<ReplayState>,
}

impl ReplayGuard {
    fn accept(&self, nonce: [u8; NONCE_LEN]) -> bool {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.seen.insert(nonce) {
            return false;
        }
        state.ordered.push_back(nonce);
        if state.ordered.len() > MAX_REPLAY_NONCES {
            if let Some(expired) = state.ordered.pop_front() {
                state.seen.remove(&expired);
            }
        }
        true
    }
}

pub struct ForwardingServer {
    cancellation: Arc<AtomicBool>,
    worker: Option<std::thread::JoinHandle<()>>,
}

impl ForwardingServer {
    pub fn start(
        listener: UnixListener,
        token: [u8; TOKEN_LEN],
        paths: RuntimePaths,
        handler: Arc<dyn Fn(ForwardAction) -> ForwardResponse + Send + Sync>,
    ) -> Result<Self, IpcError> {
        listener.set_nonblocking(true).map_err(io_error)?;
        let cancellation = Arc::new(AtomicBool::new(false));
        let stopping = Arc::clone(&cancellation);
        let worker = std::thread::Builder::new()
            .name("gitlama-cli-forwarding".to_owned())
            .spawn(move || {
                let replay = Arc::new(ReplayGuard::default());
                let mut clients: Vec<std::thread::JoinHandle<()>> = Vec::new();
                while !stopping.load(Ordering::Acquire) {
                    let mut pending = Vec::with_capacity(clients.len());
                    for client in clients.drain(..) {
                        if client.is_finished() {
                            let _ = client.join();
                        } else {
                            pending.push(client);
                        }
                    }
                    clients = pending;
                    if clients.len() >= MAX_CLIENTS {
                        std::thread::sleep(Duration::from_millis(2));
                        continue;
                    }
                    match listener.accept() {
                        Ok((stream, _)) => {
                            let replay = Arc::clone(&replay);
                            let handler = Arc::clone(&handler);
                            clients.push(std::thread::spawn(move || {
                                let _ = serve_connection(stream, &token, &replay, &handler);
                            }));
                        }
                        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                            std::thread::sleep(Duration::from_millis(2))
                        }
                        Err(_) => break,
                    }
                }
                for client in clients {
                    let _ = client.join();
                }
                if validate_private_entry(&paths.socket, EntryKind::Socket).is_ok() {
                    let _ = fs::remove_file(paths.socket);
                }
            })
            .map_err(io_error)?;
        Ok(Self {
            cancellation,
            worker: Some(worker),
        })
    }

    fn stop(&mut self) {
        self.cancellation.store(true, Ordering::Release);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

impl Drop for ForwardingServer {
    fn drop(&mut self) {
        self.stop();
    }
}

fn serve_connection(
    mut stream: UnixStream,
    token: &[u8; TOKEN_LEN],
    replay: &ReplayGuard,
    handler: &Arc<dyn Fn(ForwardAction) -> ForwardResponse + Send + Sync>,
) -> Result<(), IpcError> {
    stream.set_nonblocking(false).map_err(io_error)?;
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .map_err(io_error)?;
    stream
        .set_write_timeout(Some(Duration::from_secs(2)))
        .map_err(io_error)?;
    verify_peer(&stream)?;
    let request = read_request(&mut stream)?;
    let response = if !constant_time_eq(&request.token, token) {
        ForwardResponse::Rejected {
            code: ResponseCode::Authentication,
            detail: "authentication_failed".to_owned(),
        }
    } else if !replay.accept(request.nonce) {
        ForwardResponse::Rejected {
            code: ResponseCode::Replay,
            detail: "replay_rejected".to_owned(),
        }
    } else {
        handler(request.action)
    };
    write_response(&mut stream, &response)?;
    Ok(())
}

pub fn validate_repository_path(native_path: &[u8]) -> Result<PathBuf, IpcError> {
    use std::os::unix::ffi::OsStrExt;
    if native_path.is_empty() || native_path.contains(&0) {
        return Err(IpcError::InvalidPath);
    }
    let path = PathBuf::from(std::ffi::OsStr::from_bytes(native_path));
    if !path.is_absolute() {
        return Err(IpcError::InvalidPath);
    }
    let canonical = fs::canonicalize(path).map_err(|_| IpcError::InvalidPath)?;
    if !canonical.is_dir() {
        return Err(IpcError::InvalidPath);
    }
    Ok(canonical)
}

fn prepare_directory(directory: &Path) -> Result<(), IpcError> {
    if !directory.is_absolute() {
        return Err(IpcError::InsecureRuntimeDirectory);
    }
    match fs::symlink_metadata(directory) {
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            let mut builder = fs::DirBuilder::new();
            builder.mode(DIRECTORY_MODE);
            match builder.create(directory) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
                Err(error) => return Err(io_error(error)),
            }
        }
        Err(error) => return Err(io_error(error)),
    }
    let metadata = fs::symlink_metadata(directory).map_err(io_error)?;
    if !metadata.file_type().is_dir()
        || metadata.file_type().is_symlink()
        || metadata.uid() != getuid().as_raw()
        || metadata.mode() & 0o077 != 0
    {
        return Err(IpcError::InsecureRuntimeDirectory);
    }
    Ok(())
}

fn load_or_create_token(path: &Path) -> Result<[u8; TOKEN_LEN], IpcError> {
    match fs::symlink_metadata(path) {
        Ok(_) => validate_private_entry(path, EntryKind::Regular)?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            let token = random_token()?;
            let sequence = TOKEN_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let temporary = path.with_extension(format!("tmp-{}-{sequence}", std::process::id()));
            let mut options = OpenOptions::new();
            options.write(true).create_new(true).mode(PRIVATE_FILE_MODE);
            let mut file = options.open(&temporary).map_err(io_error)?;
            file.write_all(&token)
                .and_then(|()| file.sync_all())
                .map_err(io_error)?;
            validate_private_entry(&temporary, EntryKind::Regular)?;
            match fs::hard_link(&temporary, path) {
                Ok(()) => {
                    fs::remove_file(&temporary).map_err(io_error)?;
                    return Ok(token);
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                    fs::remove_file(&temporary).map_err(io_error)?;
                }
                Err(error) => {
                    let _ = fs::remove_file(&temporary);
                    return Err(io_error(error));
                }
            }
        }
        Err(error) => return Err(io_error(error)),
    }
    load_token(path)
}

fn load_token(path: &Path) -> Result<[u8; TOKEN_LEN], IpcError> {
    validate_private_entry(path, EntryKind::Regular)?;
    let mut file = File::open(path).map_err(io_error)?;
    let mut token = [0; TOKEN_LEN];
    file.read_exact(&mut token)
        .map_err(|_| IpcError::InsecureToken)?;
    let mut trailing = [0; 1];
    if file.read(&mut trailing).map_err(io_error)? != 0 {
        return Err(IpcError::InsecureToken);
    }
    Ok(token)
}

fn random_token() -> Result<[u8; TOKEN_LEN], IpcError> {
    let mut token = [0; TOKEN_LEN];
    File::open("/dev/urandom")
        .and_then(|mut source| source.read_exact(&mut token))
        .map_err(io_error)?;
    Ok(token)
}

#[derive(Clone, Copy)]
enum EntryKind {
    Regular,
    Socket,
}

fn validate_private_entry(path: &Path, kind: EntryKind) -> Result<(), IpcError> {
    let metadata = fs::symlink_metadata(path).map_err(io_error)?;
    let type_matches = match kind {
        EntryKind::Regular => metadata.file_type().is_file(),
        EntryKind::Socket => metadata.file_type().is_socket(),
    };
    if !type_matches
        || metadata.file_type().is_symlink()
        || metadata.uid() != getuid().as_raw()
        || metadata.mode() & 0o077 != 0
    {
        return Err(match kind {
            EntryKind::Regular => IpcError::InsecureToken,
            EntryKind::Socket => IpcError::InsecureSocket,
        });
    }
    Ok(())
}

fn validate_socket_type_and_owner(path: &Path) -> Result<(), IpcError> {
    let metadata = fs::symlink_metadata(path).map_err(io_error)?;
    if !metadata.file_type().is_socket()
        || metadata.file_type().is_symlink()
        || metadata.uid() != getuid().as_raw()
    {
        return Err(IpcError::InsecureSocket);
    }
    Ok(())
}

#[cfg(any(target_os = "linux", target_os = "android"))]
fn verify_peer(stream: &UnixStream) -> Result<(), IpcError> {
    let credentials = rustix::net::sockopt::socket_peercred(stream)
        .map_err(|_| IpcError::Io(std::io::ErrorKind::Other))?;
    if !peer_uid_allowed(credentials.uid.as_raw(), getuid().as_raw()) {
        return Err(IpcError::Authentication);
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn verify_peer(stream: &UnixStream) -> Result<(), IpcError> {
    let (uid, _) =
        nix::unistd::getpeereid(stream).map_err(|_| IpcError::Io(std::io::ErrorKind::Other))?;
    if !peer_uid_allowed(uid.as_raw(), getuid().as_raw()) {
        return Err(IpcError::Authentication);
    }
    Ok(())
}

const fn peer_uid_allowed(peer: u32, owner: u32) -> bool {
    peer == owner
}

#[cfg(not(any(target_os = "linux", target_os = "android", target_os = "macos")))]
fn verify_peer(_: &UnixStream) -> Result<(), IpcError> {
    Err(IpcError::UnsupportedPlatform)
}

fn constant_time_eq(left: &[u8; TOKEN_LEN], right: &[u8; TOKEN_LEN]) -> bool {
    left.iter()
        .zip(right)
        .fold(0_u8, |difference, (left, right)| {
            difference | (left ^ right)
        })
        == 0
}

fn write_all_bounded(
    stream: &mut UnixStream,
    mut bytes: &[u8],
    deadline: Instant,
) -> Result<(), IpcError> {
    while !bytes.is_empty() {
        if Instant::now() >= deadline {
            return Err(IpcError::TimedOut);
        }
        match stream.write(bytes) {
            Ok(0) => return Err(IpcError::Io(std::io::ErrorKind::WriteZero)),
            Ok(written) => bytes = &bytes[written..],
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::yield_now()
            }
            Err(error) => return Err(io_error(error)),
        }
    }
    Ok(())
}

fn read_exact_bounded(
    stream: &mut UnixStream,
    mut bytes: &mut [u8],
    deadline: Instant,
) -> Result<(), IpcError> {
    while !bytes.is_empty() {
        if Instant::now() >= deadline {
            return Err(IpcError::TimedOut);
        }
        match stream.read(bytes) {
            Ok(0) => return Err(IpcError::Protocol(ProtocolError::Truncated)),
            Ok(read) => bytes = &mut bytes[read..],
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::yield_now()
            }
            Err(error) => return Err(io_error(error)),
        }
    }
    Ok(())
}

fn io_error(error: std::io::Error) -> IpcError {
    IpcError::Io(error.kind())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli_forwarding::protocol::AllowedCommand;
    use std::os::unix::fs::symlink;

    fn fixture() -> RuntimePaths {
        let suffix = TOKEN_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        RuntimePaths::under(
            std::env::temp_dir().join(format!("ns-{}-{suffix}", std::process::id())),
        )
    }

    #[test]
    fn product_runtime_directory_overrides_shared_system_locations() {
        let product = std::env::temp_dir().join("gitlama-product-runtime");
        let paths = runtime_paths_from(
            Some(product.as_os_str()),
            Some(Path::new("relative-xdg").as_os_str()),
            Path::new("relative-temporary"),
            42,
        )
        .unwrap();
        assert_eq!(paths.directory, product);
        assert_eq!(paths.socket, product.join("forward.sock"));
        assert!(matches!(
            runtime_paths_from(
                Some(Path::new("relative-product").as_os_str()),
                None,
                Path::new("/tmp"),
                42,
            ),
            Err(IpcError::InsecureRuntimeDirectory),
        ));
    }

    #[test]
    fn authenticated_owner_rejects_wrong_token_replay_and_substitution() {
        let paths = fixture();
        let InstanceClaim::Owner { listener, token } = claim_instance(&paths).unwrap() else {
            panic!()
        };
        let handler = Arc::new(|_| ForwardResponse::Accepted);
        let server = ForwardingServer::start(listener, token, paths.clone(), handler).unwrap();
        assert!(matches!(
            forward_request(
                &paths,
                &ForwardRequest {
                    nonce: [1; NONCE_LEN],
                    token: [0; TOKEN_LEN],
                    action: ForwardAction::Invoke(AllowedCommand::Refresh),
                },
                Duration::from_secs(1),
            )
            .unwrap(),
            ForwardResponse::Rejected {
                code: ResponseCode::Authentication,
                ..
            }
        ));
        let replay = ForwardRequest {
            nonce: [2; NONCE_LEN],
            token,
            action: ForwardAction::Invoke(AllowedCommand::Refresh),
        };
        assert_eq!(
            forward_request(&paths, &replay, Duration::from_secs(1)).unwrap(),
            ForwardResponse::Accepted
        );
        assert!(matches!(
            forward_request(&paths, &replay, Duration::from_secs(1)).unwrap(),
            ForwardResponse::Rejected {
                code: ResponseCode::Replay,
                ..
            }
        ));
        assert!(!peer_uid_allowed(
            getuid().as_raw().wrapping_add(1),
            getuid().as_raw(),
        ));
        drop(server);

        let substituted = fixture();
        prepare_directory(&substituted.directory).unwrap();
        symlink("attacker", &substituted.token).unwrap();
        assert_eq!(
            claim_instance(&substituted).unwrap_err(),
            IpcError::InsecureToken
        );
        let _ = fs::remove_dir_all(paths.directory);
        let _ = fs::remove_dir_all(substituted.directory);
    }

    #[test]
    fn stale_socket_is_reclaimed_and_untrusted_runtime_fails_closed() {
        let paths = fixture();
        prepare_directory(&paths.directory).unwrap();
        let stale = UnixListener::bind(&paths.socket).unwrap();
        fs::set_permissions(&paths.socket, fs::Permissions::from_mode(PRIVATE_FILE_MODE)).unwrap();
        drop(stale);
        assert!(matches!(
            claim_instance(&paths).unwrap(),
            InstanceClaim::Owner { .. }
        ));

        let insecure = fixture();
        fs::create_dir(&insecure.directory).unwrap();
        fs::set_permissions(&insecure.directory, fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(
            claim_instance(&insecure).unwrap_err(),
            IpcError::InsecureRuntimeDirectory
        );
        let _ = fs::remove_dir_all(paths.directory);
        let _ = fs::remove_dir_all(insecure.directory);
    }

    #[test]
    fn forwarding_to_a_stale_private_socket_allows_owner_recovery() {
        let paths = fixture();
        prepare_directory(&paths.directory).unwrap();
        let stale = UnixListener::bind(&paths.socket).unwrap();
        fs::set_permissions(&paths.socket, fs::Permissions::from_mode(PRIVATE_FILE_MODE)).unwrap();
        drop(stale);
        let mut refused = false;
        for _ in 0..100 {
            match UnixStream::connect(&paths.socket) {
                Err(error) if error.kind() == std::io::ErrorKind::ConnectionRefused => {
                    refused = true;
                    break;
                }
                Ok(stream) => drop(stream),
                Err(error) => panic!("unexpected stale-socket state: {error:?}"),
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        assert!(refused, "stale listener never became connection-refused");
        fs::write(&paths.token, [7; TOKEN_LEN]).unwrap();
        fs::set_permissions(&paths.token, fs::Permissions::from_mode(PRIVATE_FILE_MODE)).unwrap();

        assert_eq!(
            forward_action(
                &paths,
                ForwardAction::Invoke(AllowedCommand::Refresh),
                Duration::from_secs(1),
            )
            .unwrap_err(),
            IpcError::NotRunning
        );
        assert!(matches!(
            claim_instance(&paths).unwrap(),
            InstanceClaim::Owner { .. }
        ));

        let _ = fs::remove_dir_all(paths.directory);
    }

    #[test]
    fn live_owner_prevents_a_second_instance_claim() {
        let paths = fixture();
        let InstanceClaim::Owner { listener, .. } = claim_instance(&paths).unwrap() else {
            panic!()
        };
        assert!(matches!(
            claim_instance(&paths).unwrap(),
            InstanceClaim::Existing
        ));
        drop(listener);
        let _ = fs::remove_dir_all(paths.directory);
    }
}
