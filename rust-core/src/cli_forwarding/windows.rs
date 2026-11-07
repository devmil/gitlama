//! Owner-only Windows named-pipe transport for command forwarding.
//!
//! This is the sole Win32 security boundary in GitLama's Rust core. The
//! pipe DACL grants only the current user SID, remote clients are rejected,
//! and both endpoints verify the peer process token before protocol data is
//! accepted. The bearer token is stored in Windows Credential Manager.

#![allow(unsafe_code)]

use super::protocol::{
    read_request, read_response, write_request, write_response, ForwardAction, ForwardRequest,
    ForwardResponse, ProtocolError, ResponseCode, MAX_FRAME_LEN, NONCE_LEN, TOKEN_LEN,
};
use std::collections::{BTreeSet, VecDeque};
use std::ffi::c_void;
use std::fmt::Write as _;
use std::io::{Read, Write};
use std::os::windows::ffi::OsStrExt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use windows::core::{Error as WindowsError, PCWSTR, PWSTR};
use windows::Win32::Foundation::{
    CloseHandle, GetLastError, LocalFree, ERROR_ACCESS_DENIED, ERROR_FILE_NOT_FOUND,
    ERROR_NOT_FOUND, ERROR_NO_DATA, ERROR_PIPE_BUSY, ERROR_PIPE_CONNECTED, ERROR_PIPE_LISTENING,
    GENERIC_READ, GENERIC_WRITE, HANDLE, HLOCAL,
};
use windows::Win32::Security::Authorization::{
    ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
};
use windows::Win32::Security::Credentials::{
    CredFree, CredGetSessionTypes, CredReadW, CredWriteW, CREDENTIALW, CRED_PERSIST,
    CRED_PERSIST_ENTERPRISE, CRED_PERSIST_LOCAL_MACHINE, CRED_PERSIST_SESSION, CRED_TYPE_GENERIC,
    CRED_TYPE_MAXIMUM,
};
use windows::Win32::Security::Cryptography::{BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG};
use windows::Win32::Security::{
    GetLengthSid, GetTokenInformation, RevertToSelf, TokenUser, PSECURITY_DESCRIPTOR, PSID,
    SECURITY_ATTRIBUTES, TOKEN_QUERY, TOKEN_USER,
};
use windows::Win32::Storage::FileSystem::{
    CreateFileW, ReadFile, WriteFile, FILE_ATTRIBUTE_NORMAL, FILE_FLAG_FIRST_PIPE_INSTANCE,
    FILE_SHARE_MODE, OPEN_EXISTING, PIPE_ACCESS_DUPLEX,
};
use windows::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, GetNamedPipeServerProcessId,
    ImpersonateNamedPipeClient, SetNamedPipeHandleState, PIPE_NOWAIT, PIPE_READMODE_BYTE,
    PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE,
};
use windows::Win32::System::SystemServices::SECURITY_DESCRIPTOR_REVISION;
use windows::Win32::System::Threading::{
    GetCurrentProcess, GetCurrentThread, OpenProcess, OpenProcessToken, OpenThreadToken,
    PROCESS_QUERY_LIMITED_INFORMATION,
};

const PIPE_BUFFER_BYTES: u32 = 64 * 1024;
const MAX_CLIENTS: usize = 4;
const PIPE_MAX_INSTANCES: u32 = 5;
const MAX_REPLAY_NONCES: usize = 1024;
const POLL_INTERVAL: Duration = Duration::from_millis(2);
// The application handler can use its full two-second response allowance.
// Leave time for the client's ten-second deadline and its response acknowledgement.
const PIPE_EXCHANGE_TIMEOUT: Duration = Duration::from_secs(12);
const RESPONSE_ACK: [u8; 1] = [1];
const CREDENTIAL_TARGET: &str = "GitLama/local-command-forwarding/v1";

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum IpcError {
    InsecurePipe,
    Authentication,
    CredentialMissing,
    InsecureCredential,
    NotRunning,
    TimedOut,
    Canceled,
    Io(u32),
    Protocol(ProtocolError),
}

impl From<ProtocolError> for IpcError {
    fn from(value: ProtocolError) -> Self {
        Self::Protocol(value)
    }
}

#[derive(Clone, Debug)]
pub struct RuntimeAddress {
    pipe_name: Vec<u16>,
    owner_sid: Sid,
    owner_sid_string: String,
    credential_target: Vec<u16>,
}

impl RuntimeAddress {
    pub fn discover() -> Result<Self, IpcError> {
        let owner_sid = current_process_sid()?;
        let owner_sid_string = sid_string(owner_sid.as_psid())?;
        let mut suffix = String::with_capacity(owner_sid.bytes.len() * 2);
        for byte in &owner_sid.bytes {
            write!(suffix, "{byte:02x}").expect("writing to a String cannot fail");
        }
        Ok(Self {
            pipe_name: wide(&format!(r"\\.\pipe\GitLama-{suffix}")),
            owner_sid,
            owner_sid_string,
            credential_target: wide(CREDENTIAL_TARGET),
        })
    }
}

#[derive(Debug)]
pub enum InstanceClaim {
    Owner {
        listener: PipeListener,
        token: [u8; TOKEN_LEN],
    },
    Existing,
}

pub fn claim_instance(address: &RuntimeAddress) -> Result<InstanceClaim, IpcError> {
    match PipeListener::first(address.clone()) {
        Ok(listener) => {
            let token = random_token()?;
            store_token(&address.credential_target, &token)?;
            Ok(InstanceClaim::Owner { listener, token })
        }
        Err(IpcError::Io(code)) if code == ERROR_ACCESS_DENIED.0 || code == ERROR_PIPE_BUSY.0 => {
            let deadline = Instant::now() + Duration::from_secs(2);
            loop {
                match connect_verified(address, deadline, &AtomicBool::new(false)) {
                    Ok(stream) => {
                        drop(stream);
                        return Ok(InstanceClaim::Existing);
                    }
                    Err(IpcError::NotRunning) => {
                        check_deadline(&AtomicBool::new(false), deadline)?;
                        std::thread::sleep(POLL_INTERVAL);
                    }
                    Err(error) => return Err(error),
                }
            }
        }
        Err(error) => Err(error),
    }
}

pub fn forward_action(
    address: &RuntimeAddress,
    action: ForwardAction,
    timeout: Duration,
) -> Result<ForwardResponse, IpcError> {
    let token =
        load_token(&address.credential_target).map_err(|error| trace("load_token", error))?;
    let mut nonce = [0; NONCE_LEN];
    random_bytes(&mut nonce).map_err(|error| trace("random_nonce", error))?;
    let cancellation = AtomicBool::new(false);
    let deadline = Instant::now() + timeout;
    let mut stream = connect_verified(address, deadline, &cancellation)
        .map_err(|error| trace("connect", error))?;
    let mut encoded = Vec::new();
    write_request(
        &mut encoded,
        &ForwardRequest {
            nonce,
            token,
            action,
        },
    )
    .map_err(|error| trace("encode_request", error.into()))?;
    write_all_cancellable(&mut stream, &encoded, deadline, &cancellation)
        .map_err(|error| trace("write_request", error))?;
    read_response_and_ack(&mut stream, deadline, &cancellation)
        .map_err(|error| trace("read_response", error))
}

fn trace(stage: &'static str, error: IpcError) -> IpcError {
    if std::env::var_os("GITLAMA_FORWARDING_DIAGNOSTICS").as_deref()
        == Some(std::ffi::OsStr::new("1"))
    {
        let kind = match &error {
            IpcError::Io(code) => format!("io_{code}"),
            IpcError::Protocol(ProtocolError::Truncated) => "protocol_truncated".to_owned(),
            IpcError::Protocol(_) => "protocol_other".to_owned(),
            IpcError::TimedOut => "timeout".to_owned(),
            IpcError::Authentication => "authentication".to_owned(),
            IpcError::NotRunning => "not_running".to_owned(),
            IpcError::CredentialMissing => "credential_missing".to_owned(),
            _ => "other".to_owned(),
        };
        eprintln!("gitlama_windows_ipc={stage}:{kind}");
    }
    error
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
        mut listener: PipeListener,
        token: [u8; TOKEN_LEN],
        handler: Arc<dyn Fn(ForwardAction) -> ForwardResponse + Send + Sync>,
    ) -> Result<Self, IpcError> {
        let cancellation = Arc::new(AtomicBool::new(false));
        let stopping = Arc::clone(&cancellation);
        let worker = std::thread::Builder::new()
            .name("gitlama-cli-forwarding".to_owned())
            .spawn(move || {
                let replay = Arc::new(ReplayGuard::default());
                let mut clients: Vec<std::thread::JoinHandle<()>> = Vec::new();
                while !stopping.load(Ordering::Acquire) {
                    let mut pending = Vec::new();
                    for client in clients.drain(..) {
                        if client.is_finished() {
                            let _ = client.join();
                        } else {
                            pending.push(client);
                        }
                    }
                    clients = pending;
                    if clients.len() >= MAX_CLIENTS {
                        std::thread::sleep(POLL_INTERVAL);
                        continue;
                    }
                    match listener.accept() {
                        Ok(Some(stream)) => {
                            let replay = Arc::clone(&replay);
                            let handler = Arc::clone(&handler);
                            clients.push(std::thread::spawn(move || {
                                if let Err(error) = serve_connection(
                                    stream,
                                    &token,
                                    &replay,
                                    &handler,
                                    PIPE_EXCHANGE_TIMEOUT,
                                ) {
                                    let _ = trace("server_connection", error);
                                }
                            }));
                        }
                        Ok(None) => std::thread::sleep(POLL_INTERVAL),
                        Err(_) => break,
                    }
                }
                for client in clients {
                    let _ = client.join();
                }
            })
            .map_err(|error| IpcError::Io(error.raw_os_error().unwrap_or(0).cast_unsigned()))?;
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
    mut stream: PipeStream,
    token: &[u8; TOKEN_LEN],
    replay: &ReplayGuard,
    handler: &Arc<dyn Fn(ForwardAction) -> ForwardResponse + Send + Sync>,
    timeout: Duration,
) -> Result<(), IpcError> {
    let deadline = Instant::now() + timeout;
    let cancellation = AtomicBool::new(false);
    let request = read_request_cancellable(&mut stream, deadline, &cancellation)
        .map_err(|error| trace("server_read_request", error))?;
    // Named-pipe impersonation uses the security context of the last message read.
    // Verify the peer after the bounded read and before inspecting or handling its request.
    verify_client_sid(&stream, &stream.owner_sid)
        .map_err(|error| trace("server_verify_client", error))?;
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
    let mut encoded = Vec::new();
    write_response(&mut encoded, &response)
        .map_err(|error| trace("server_encode_response", error.into()))?;
    write_all_cancellable(&mut stream, &encoded, deadline, &cancellation)
        .map_err(|error| trace("server_write_response", error))?;
    // DisconnectNamedPipe discards unread response bytes. Wait for the client
    // to confirm it read the response before dropping the server pipe handle.
    let mut ack = [0; RESPONSE_ACK.len()];
    read_exact_cancellable(&mut stream, &mut ack, deadline, &cancellation)
        .map_err(|error| trace("server_read_ack", error))?;
    if ack != RESPONSE_ACK {
        return Err(IpcError::Protocol(ProtocolError::Malformed));
    }
    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Sid {
    bytes: Vec<u8>,
}

impl Sid {
    fn as_psid(&self) -> PSID {
        PSID(self.bytes.as_ptr().cast_mut().cast::<c_void>())
    }
}

#[derive(Debug)]
pub struct PipeListener {
    address: RuntimeAddress,
    pending: Option<PipeStream>,
}

impl PipeListener {
    fn first(address: RuntimeAddress) -> Result<Self, IpcError> {
        let pending = PipeStream::server(&address, true)?;
        Ok(Self {
            address,
            pending: Some(pending),
        })
    }

    fn accept(&mut self) -> Result<Option<PipeStream>, IpcError> {
        let Some(pending) = self.pending.as_ref() else {
            return Err(IpcError::InsecurePipe);
        };
        if !pending.poll_connect()? {
            return Ok(None);
        }
        let connected = self.pending.take().ok_or(IpcError::InsecurePipe)?;
        self.pending = Some(PipeStream::server(&self.address, false)?);
        Ok(Some(connected))
    }
}

#[derive(Debug)]
struct PipeStream {
    raw: usize,
    server_end: bool,
    owner_sid: Sid,
}

impl PipeStream {
    fn server(address: &RuntimeAddress, first: bool) -> Result<Self, IpcError> {
        let descriptor = SecurityDescriptor::owner_only(&address.owner_sid_string)?;
        let attributes = SECURITY_ATTRIBUTES {
            nLength: u32::try_from(std::mem::size_of::<SECURITY_ATTRIBUTES>())
                .map_err(|_| IpcError::InsecurePipe)?,
            lpSecurityDescriptor: descriptor.raw.0,
            bInheritHandle: false.into(),
        };
        let mut open_mode = PIPE_ACCESS_DUPLEX;
        if first {
            open_mode |= FILE_FLAG_FIRST_PIPE_INSTANCE;
        }
        let pipe_mode =
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS;
        let handle = unsafe {
            CreateNamedPipeW(
                PCWSTR(address.pipe_name.as_ptr()),
                open_mode,
                pipe_mode,
                PIPE_MAX_INSTANCES,
                PIPE_BUFFER_BYTES,
                PIPE_BUFFER_BYTES,
                2_000,
                Some(&raw const attributes),
            )
        };
        if handle.is_invalid() {
            return Err(IpcError::Io(unsafe { GetLastError() }.0));
        }
        Ok(Self {
            raw: handle.0 as usize,
            server_end: true,
            owner_sid: address.owner_sid.clone(),
        })
    }

    fn client(address: &RuntimeAddress) -> Result<Self, IpcError> {
        let handle = unsafe {
            CreateFileW(
                PCWSTR(address.pipe_name.as_ptr()),
                GENERIC_READ.0 | GENERIC_WRITE.0,
                FILE_SHARE_MODE(0),
                None,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                None,
            )
        }
        .map_err(win_error)?;
        let mode = PIPE_READMODE_BYTE | PIPE_NOWAIT;
        if let Err(error) =
            unsafe { SetNamedPipeHandleState(handle, Some(&raw const mode), None, None) }
        {
            let _ = unsafe { CloseHandle(handle) };
            return Err(win_error(error));
        }
        Ok(Self {
            raw: handle.0 as usize,
            server_end: false,
            owner_sid: address.owner_sid.clone(),
        })
    }

    fn handle(&self) -> HANDLE {
        HANDLE(self.raw as *mut c_void)
    }

    fn poll_connect(&self) -> Result<bool, IpcError> {
        match unsafe { ConnectNamedPipe(self.handle(), None) } {
            Ok(()) => Ok(true),
            Err(error) => match win_code(&error) {
                code if code == ERROR_PIPE_CONNECTED.0 => Ok(true),
                code if code == ERROR_PIPE_LISTENING.0 => Ok(false),
                code if code == ERROR_NO_DATA.0 => {
                    // A client can close before the server accepts it. The
                    // instance must be disconnected and rearmed before it can
                    // listen again. In nonblocking mode, the first successful
                    // ConnectNamedPipe after a disconnect only rearms it.
                    unsafe { DisconnectNamedPipe(self.handle()) }.map_err(win_error)?;
                    match unsafe { ConnectNamedPipe(self.handle(), None) } {
                        Ok(()) => Ok(false),
                        Err(error) => match win_code(&error) {
                            code if code == ERROR_PIPE_CONNECTED.0 => Ok(true),
                            code if code == ERROR_PIPE_LISTENING.0 || code == ERROR_NO_DATA.0 => {
                                Ok(false)
                            }
                            code => Err(IpcError::Io(code)),
                        },
                    }
                }
                code => Err(IpcError::Io(code)),
            },
        }
    }
}

impl Drop for PipeStream {
    fn drop(&mut self) {
        if self.server_end {
            let _ = unsafe { DisconnectNamedPipe(self.handle()) };
        }
        let _ = unsafe { CloseHandle(self.handle()) };
    }
}

impl Read for PipeStream {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        let mut read = 0;
        match unsafe { ReadFile(self.handle(), Some(buffer), Some(&raw mut read), None) } {
            Ok(()) => Ok(read as usize),
            Err(error) if would_block(win_code(&error)) => {
                Err(std::io::Error::from(std::io::ErrorKind::WouldBlock))
            }
            Err(error) => Err(std::io::Error::from_raw_os_error(
                win_code(&error).cast_signed(),
            )),
        }
    }
}

impl Write for PipeStream {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        let mut written = 0;
        match unsafe { WriteFile(self.handle(), Some(buffer), Some(&raw mut written), None) } {
            Ok(()) => Ok(written as usize),
            Err(error) if would_block(win_code(&error)) => {
                Err(std::io::Error::from(std::io::ErrorKind::WouldBlock))
            }
            Err(error) => Err(std::io::Error::from_raw_os_error(
                win_code(&error).cast_signed(),
            )),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn connect_verified(
    address: &RuntimeAddress,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<PipeStream, IpcError> {
    loop {
        check_deadline(cancellation, deadline)?;
        match PipeStream::client(address) {
            Ok(stream) => {
                verify_server_sid(&stream, &address.owner_sid)?;
                return Ok(stream);
            }
            Err(IpcError::Io(code)) if code == ERROR_FILE_NOT_FOUND.0 => {
                return Err(IpcError::NotRunning);
            }
            Err(IpcError::Io(code)) if code == ERROR_PIPE_BUSY.0 => {
                std::thread::sleep(POLL_INTERVAL);
            }
            Err(error) => return Err(error),
        }
    }
}

fn verify_server_sid(stream: &PipeStream, owner_sid: &Sid) -> Result<(), IpcError> {
    let mut process_id = 0;
    unsafe { GetNamedPipeServerProcessId(stream.handle(), &raw mut process_id) }
        .map_err(win_error)?;
    let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process_id) }
        .map_err(win_error)?;
    let mut token = HANDLE::default();
    let result = unsafe { OpenProcessToken(process, TOKEN_QUERY, &raw mut token) };
    let _ = unsafe { CloseHandle(process) };
    result.map_err(win_error)?;
    let server_sid = token_sid(token);
    let _ = unsafe { CloseHandle(token) };
    if server_sid? != *owner_sid {
        return Err(IpcError::Authentication);
    }
    Ok(())
}

fn verify_client_sid(stream: &PipeStream, owner_sid: &Sid) -> Result<(), IpcError> {
    unsafe { ImpersonateNamedPipeClient(stream.handle()) }.map_err(win_error)?;
    let mut token = HANDLE::default();
    let opened = unsafe { OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, false, &raw mut token) };
    let sid = opened.map_err(win_error).and_then(|()| token_sid(token));
    if !token.is_invalid() {
        let _ = unsafe { CloseHandle(token) };
    }
    unsafe { RevertToSelf() }.map_err(win_error)?;
    if sid? != *owner_sid {
        return Err(IpcError::Authentication);
    }
    Ok(())
}

fn current_process_sid() -> Result<Sid, IpcError> {
    let mut token = HANDLE::default();
    unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw mut token) }
        .map_err(win_error)?;
    let sid = token_sid(token);
    let _ = unsafe { CloseHandle(token) };
    sid
}

fn token_sid(token: HANDLE) -> Result<Sid, IpcError> {
    let mut required = 0;
    let _ = unsafe { GetTokenInformation(token, TokenUser, None, 0, &raw mut required) };
    if required == 0 {
        return Err(IpcError::Authentication);
    }
    let words = usize::try_from(required)
        .ok()
        .and_then(|bytes| bytes.checked_add(std::mem::size_of::<usize>() - 1))
        .map(|bytes| bytes / std::mem::size_of::<usize>())
        .ok_or(IpcError::Authentication)?;
    let mut storage = vec![0_usize; words];
    unsafe {
        GetTokenInformation(
            token,
            TokenUser,
            Some(storage.as_mut_ptr().cast::<c_void>()),
            required,
            &raw mut required,
        )
    }
    .map_err(win_error)?;
    let token_user = unsafe { &*storage.as_ptr().cast::<TOKEN_USER>() };
    let length = unsafe { GetLengthSid(token_user.User.Sid) };
    if length == 0 {
        return Err(IpcError::Authentication);
    }
    let source =
        unsafe { std::slice::from_raw_parts(token_user.User.Sid.0.cast::<u8>(), length as usize) };
    Ok(Sid {
        bytes: source.to_vec(),
    })
}

fn sid_string(sid: PSID) -> Result<String, IpcError> {
    let mut value = PWSTR::null();
    unsafe { ConvertSidToStringSidW(sid, &raw mut value) }.map_err(win_error)?;
    let string = unsafe { value.to_string() }.map_err(|_| IpcError::Authentication);
    let _ = unsafe { LocalFree(Some(HLOCAL(value.0.cast::<c_void>()))) };
    string
}

struct SecurityDescriptor {
    raw: PSECURITY_DESCRIPTOR,
}

impl SecurityDescriptor {
    fn owner_only(owner_sid: &str) -> Result<Self, IpcError> {
        let sddl = wide(&format!("D:P(A;;GA;;;{owner_sid})"));
        let mut raw = PSECURITY_DESCRIPTOR::default();
        unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                PCWSTR(sddl.as_ptr()),
                SECURITY_DESCRIPTOR_REVISION,
                &raw mut raw,
                None,
            )
        }
        .map_err(win_error)?;
        Ok(Self { raw })
    }
}

impl Drop for SecurityDescriptor {
    fn drop(&mut self) {
        let _ = unsafe { LocalFree(Some(HLOCAL(self.raw.0))) };
    }
}

fn token_persistence(maximum: u32) -> Result<CRED_PERSIST, IpcError> {
    match CRED_PERSIST(maximum) {
        CRED_PERSIST_SESSION => Ok(CRED_PERSIST_SESSION),
        CRED_PERSIST_LOCAL_MACHINE | CRED_PERSIST_ENTERPRISE => Ok(CRED_PERSIST_LOCAL_MACHINE),
        _ => Err(IpcError::InsecureCredential),
    }
}

fn store_token(target: &[u16], token: &[u8; TOKEN_LEN]) -> Result<(), IpcError> {
    // The bearer is valid only while the authenticated pipe owner is alive.
    // Some interactive Windows logons permit only session credentials. Keep
    // machine persistence where available and honour session-only policy.
    let mut supported = [0; CRED_TYPE_MAXIMUM.0 as usize];
    unsafe { CredGetSessionTypes(&mut supported) }.map_err(win_error)?;
    let persistence = token_persistence(supported[CRED_TYPE_GENERIC.0 as usize])?;
    let mut target = target.to_vec();
    let mut blob = token.to_vec();
    let credential = CREDENTIALW {
        Type: CRED_TYPE_GENERIC,
        TargetName: PWSTR(target.as_mut_ptr()),
        CredentialBlobSize: u32::try_from(blob.len()).map_err(|_| IpcError::InsecureCredential)?,
        CredentialBlob: blob.as_mut_ptr(),
        Persist: persistence,
        ..Default::default()
    };
    unsafe { CredWriteW(&raw const credential, 0) }.map_err(win_error)
}

fn load_token(target: &[u16]) -> Result<[u8; TOKEN_LEN], IpcError> {
    let mut credential = std::ptr::null_mut();
    unsafe {
        CredReadW(
            PCWSTR(target.as_ptr()),
            CRED_TYPE_GENERIC,
            None,
            &raw mut credential,
        )
    }
    .map_err(|error| {
        if matches!(win_code(&error), code if code == ERROR_NOT_FOUND.0 || code == ERROR_FILE_NOT_FOUND.0)
        {
            IpcError::CredentialMissing
        } else {
            win_error(error)
        }
    })?;
    if credential.is_null() {
        return Err(IpcError::InsecureCredential);
    }
    let entry = unsafe { &*credential };
    let result =
        if entry.CredentialBlobSize as usize == TOKEN_LEN && !entry.CredentialBlob.is_null() {
            let bytes = unsafe {
                std::slice::from_raw_parts(entry.CredentialBlob, entry.CredentialBlobSize as usize)
            };
            let mut token = [0; TOKEN_LEN];
            token.copy_from_slice(bytes);
            Ok(token)
        } else {
            Err(IpcError::InsecureCredential)
        };
    unsafe { CredFree(credential.cast::<c_void>()) };
    result
}

fn random_token() -> Result<[u8; TOKEN_LEN], IpcError> {
    let mut token = [0; TOKEN_LEN];
    random_bytes(&mut token)?;
    Ok(token)
}

fn random_bytes(bytes: &mut [u8]) -> Result<(), IpcError> {
    let status = unsafe { BCryptGenRandom(None, bytes, BCRYPT_USE_SYSTEM_PREFERRED_RNG) };
    if status.is_ok() {
        Ok(())
    } else {
        Err(IpcError::Io(status.0.cast_unsigned()))
    }
}

fn read_request_cancellable(
    stream: &mut PipeStream,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<ForwardRequest, IpcError> {
    let frame = read_frame_cancellable(stream, deadline, cancellation)?;
    Ok(read_request(&mut frame.as_slice())?)
}

fn read_response_cancellable(
    stream: &mut PipeStream,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<ForwardResponse, IpcError> {
    let frame = read_frame_cancellable(stream, deadline, cancellation)?;
    Ok(read_response(&mut frame.as_slice())?)
}

fn read_response_and_ack(
    stream: &mut PipeStream,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<ForwardResponse, IpcError> {
    let response = read_response_cancellable(stream, deadline, cancellation)?;
    // Once the response has been consumed, a failed acknowledgement does not
    // change the result of the already completed forwarding operation.
    let _ = write_all_cancellable(stream, &RESPONSE_ACK, deadline, cancellation);
    Ok(response)
}

fn read_frame_cancellable(
    stream: &mut PipeStream,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<Vec<u8>, IpcError> {
    let mut length = [0; 4];
    read_exact_cancellable(stream, &mut length, deadline, cancellation)?;
    let length = usize::try_from(u32::from_be_bytes(length))
        .map_err(|_| IpcError::Protocol(ProtocolError::Oversized))?;
    if length > MAX_FRAME_LEN {
        return Err(IpcError::Protocol(ProtocolError::Oversized));
    }
    let mut frame = Vec::with_capacity(length + 4);
    frame.extend_from_slice(&u32::try_from(length).unwrap_or(0).to_be_bytes());
    let mut payload = vec![0; length];
    read_exact_cancellable(stream, &mut payload, deadline, cancellation)?;
    frame.extend_from_slice(&payload);
    Ok(frame)
}

fn write_all_cancellable(
    stream: &mut PipeStream,
    mut bytes: &[u8],
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<(), IpcError> {
    while !bytes.is_empty() {
        check_deadline(cancellation, deadline)?;
        match stream.write(bytes) {
            Ok(0) => return Err(IpcError::Io(0)),
            Ok(written) => bytes = &bytes[written..],
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::yield_now();
            }
            Err(error) => {
                return Err(IpcError::Io(
                    error.raw_os_error().unwrap_or(0).cast_unsigned(),
                ));
            }
        }
    }
    Ok(())
}

fn read_exact_cancellable(
    stream: &mut PipeStream,
    mut bytes: &mut [u8],
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<(), IpcError> {
    while !bytes.is_empty() {
        check_deadline(cancellation, deadline)?;
        match stream.read(bytes) {
            Ok(0) => return Err(IpcError::Protocol(ProtocolError::Truncated)),
            Ok(read) => bytes = &mut bytes[read..],
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::yield_now();
            }
            Err(error) => {
                return Err(IpcError::Io(
                    error.raw_os_error().unwrap_or(0).cast_unsigned(),
                ));
            }
        }
    }
    Ok(())
}

fn check_deadline(cancellation: &AtomicBool, deadline: Instant) -> Result<(), IpcError> {
    if cancellation.load(Ordering::Acquire) {
        Err(IpcError::Canceled)
    } else if Instant::now() >= deadline {
        Err(IpcError::TimedOut)
    } else {
        Ok(())
    }
}

fn constant_time_eq(left: &[u8; TOKEN_LEN], right: &[u8; TOKEN_LEN]) -> bool {
    left.iter()
        .zip(right)
        .fold(0_u8, |difference, (left, right)| {
            difference | (left ^ right)
        })
        == 0
}

fn wide(value: &str) -> Vec<u16> {
    std::ffi::OsStr::new(value)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect()
}

fn would_block(code: u32) -> bool {
    code == ERROR_NO_DATA.0 || code == ERROR_PIPE_LISTENING.0 || code == ERROR_PIPE_BUSY.0
}

fn win_code(error: &WindowsError) -> u32 {
    error.code().0.cast_unsigned() & 0xffff
}

#[allow(clippy::needless_pass_by_value)]
fn win_error(error: WindowsError) -> IpcError {
    IpcError::Io(win_code(&error))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn credential_persistence_honours_the_session_capability() {
        assert_eq!(
            token_persistence(CRED_PERSIST_SESSION.0),
            Ok(CRED_PERSIST_SESSION)
        );
        assert_eq!(
            token_persistence(CRED_PERSIST_LOCAL_MACHINE.0),
            Ok(CRED_PERSIST_LOCAL_MACHINE)
        );
        assert_eq!(
            token_persistence(CRED_PERSIST_ENTERPRISE.0),
            Ok(CRED_PERSIST_LOCAL_MACHINE)
        );
        assert_eq!(token_persistence(0), Err(IpcError::InsecureCredential));
        assert_eq!(
            token_persistence(u32::MAX),
            Err(IpcError::InsecureCredential)
        );
    }

    #[test]
    fn ipc_token_round_trips_through_the_supported_credential_store() {
        use windows::Win32::Security::Credentials::CredDeleteW;
        let target = wide(&format!("GitLama/test-ipc-token/{}", std::process::id()));
        let token = [19; TOKEN_LEN];
        store_token(&target, &token).expect("credential store supports IPC tokens");
        let loaded = load_token(&target);
        // Attempt cleanup before asserting so a read failure does not retain
        // the synthetic entry. No existing product credential is touched.
        let deleted = unsafe { CredDeleteW(PCWSTR(target.as_ptr()), CRED_TYPE_GENERIC, None) };
        assert_eq!(loaded, Ok(token));
        deleted.expect("synthetic credential cleanup");
    }

    #[test]
    fn disconnected_client_does_not_strand_the_pending_pipe() {
        let mut address = RuntimeAddress::discover().expect("current user SID");
        address.pipe_name = wide(&format!(r"\\.\pipe\GitLama-test-{}", std::process::id()));
        let mut listener = PipeListener::first(address.clone()).expect("first pipe instance");

        let first = PipeStream::client(&address).expect("first client");
        drop(first);
        assert!(listener
            .accept()
            .expect("reset disconnected client")
            .is_none());

        let second = PipeStream::client(&address).expect("second client");
        assert!(listener.accept().expect("accept second client").is_some());
        drop(second);
    }

    #[test]
    fn authenticated_request_receives_a_pipe_response() {
        let mut address = RuntimeAddress::discover().expect("current user SID");
        address.pipe_name = wide(&format!(
            r"\\.\pipe\GitLama-roundtrip-test-{}",
            std::process::id()
        ));
        let listener = PipeListener::first(address.clone()).expect("first pipe instance");
        let token = [7; TOKEN_LEN];
        let server =
            ForwardingServer::start(listener, token, Arc::new(|_| ForwardResponse::Accepted))
                .expect("forwarding server");
        let cancellation = AtomicBool::new(false);
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut stream = connect_verified(&address, deadline, &cancellation).expect("pipe client");
        let mut encoded = Vec::new();
        write_request(
            &mut encoded,
            &ForwardRequest {
                nonce: [3; NONCE_LEN],
                token,
                action: ForwardAction::Activate,
            },
        )
        .expect("encode request");
        write_all_cancellable(&mut stream, &encoded, deadline, &cancellation)
            .expect("send request");
        std::thread::sleep(Duration::from_millis(200));
        assert_eq!(
            read_response_and_ack(&mut stream, deadline, &cancellation).expect("receive response"),
            ForwardResponse::Accepted
        );
        drop(stream);
        drop(server);
    }

    #[test]
    fn slow_application_response_is_delivered_before_pipe_closes() {
        let mut address = RuntimeAddress::discover().expect("current user SID");
        address.pipe_name = wide(&format!(
            r"\\.\pipe\GitLama-slow-response-test-{}",
            std::process::id()
        ));
        let listener = PipeListener::first(address.clone()).expect("first pipe instance");
        let token = [9; TOKEN_LEN];
        let server = ForwardingServer::start(
            listener,
            token,
            Arc::new(|_| {
                std::thread::sleep(Duration::from_millis(2100));
                ForwardResponse::Rejected {
                    code: ResponseCode::Busy,
                    detail: "application_response_unavailable".to_owned(),
                }
            }),
        )
        .expect("forwarding server");
        let cancellation = AtomicBool::new(false);
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut stream = connect_verified(&address, deadline, &cancellation).expect("pipe client");
        let mut encoded = Vec::new();
        write_request(
            &mut encoded,
            &ForwardRequest {
                nonce: [4; NONCE_LEN],
                token,
                action: ForwardAction::Activate,
            },
        )
        .expect("encode request");
        write_all_cancellable(&mut stream, &encoded, deadline, &cancellation)
            .expect("send request");
        assert!(matches!(
            read_response_and_ack(&mut stream, deadline, &cancellation).expect("receive response"),
            ForwardResponse::Rejected {
                code: ResponseCode::Busy,
                ..
            }
        ));
        drop(stream);
        drop(server);
    }
}
