//! The client side of the remote helper protocol (docs/remote-workspaces/PROTOCOL.md): frames,
//! the bootstrap probe, the hello and its acknowledgement, envelopes and chunk transactions.
//! Every violation is a [`WireError`]; the channel then closes the connection.

use super::model::{Failure, HelperInfo, HelperTarget, RemoteError};
use gitlama_application::wire::contract::{self, RemoteCapability, RemoteErrorCode};
use gitlama_application::wire::runtime::{self as w, ParseLimits, Value, WireError};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet, VecDeque};

pub const PROTOCOL_MAJOR: i64 = 1;
pub const PROTOCOL_MINOR: i64 = 0;
pub const HELPER_MAGIC: &str = "gitlama-remote-helper";
/// Bounded display/version strings in a hello.
const MAX_HELLO_TEXT_BYTES: usize = 128;
const HEADER_BYTES: usize = 4;

fn invalid(detail: &'static str) -> WireError {
    WireError::invalid(detail)
}

/// Whether `text` is `length` lowercase hexadecimal digits.
#[must_use]
pub fn is_lower_hex(text: &str, length: usize) -> bool {
    text.len() == length
        && text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// Whether `build_id` is a helper ID: 40 lowercase hexadecimal digits.
#[must_use]
pub fn is_valid_build_id(build_id: &str) -> bool {
    is_lower_hex(build_id, 40)
}

/// Encodes one frame: a 4-byte big-endian length and `payload`.
///
/// # Errors
/// An empty or oversized payload.
pub fn encode_frame(payload: &[u8], max_frame_bytes: usize) -> Result<Vec<u8>, WireError> {
    if payload.is_empty() || payload.len() > max_frame_bytes {
        return Err(invalid("frame length"));
    }
    let length = u32::try_from(payload.len()).map_err(|_| invalid("frame length"))?;
    let mut frame = Vec::with_capacity(HEADER_BYTES + payload.len());
    frame.extend_from_slice(&length.to_be_bytes());
    frame.extend_from_slice(payload);
    Ok(frame)
}

/// Incremental frame decoder. [`Self::add`] only buffers; [`Self::next`] extracts complete
/// frames in order so the caller can change `max_frame_bytes` between frames (the hello limit
/// before the negotiated one). A declared length of zero or above the limit fails before any
/// payload buffer is allocated.
pub struct FrameDecoder {
    pub max_frame_bytes: usize,
    input: VecDeque<u8>,
    header: Option<usize>,
}

impl FrameDecoder {
    #[must_use]
    pub fn new(max_frame_bytes: usize) -> Self {
        Self {
            max_frame_bytes,
            input: VecDeque::new(),
            header: None,
        }
    }

    pub fn add(&mut self, bytes: &[u8]) {
        self.input.extend(bytes);
    }

    /// Whether a partial frame is buffered (the caller's deadline runs while it is).
    #[must_use]
    pub fn partial(&self) -> bool {
        self.header.is_some() || !self.input.is_empty()
    }

    /// The next complete frame payload, or `None` when more bytes are needed.
    ///
    /// # Errors
    /// A zero or oversized length.
    pub fn next_frame(&mut self) -> Result<Option<Vec<u8>>, WireError> {
        let length = match self.header {
            Some(length) => length,
            None => {
                if self.input.len() < HEADER_BYTES {
                    return Ok(None);
                }
                let header: Vec<u8> = self.input.drain(..HEADER_BYTES).collect();
                let length =
                    u32::from_be_bytes([header[0], header[1], header[2], header[3]]) as usize;
                if length == 0 || length > self.max_frame_bytes {
                    self.input.clear();
                    return Err(invalid("frame length"));
                }
                self.header = Some(length);
                length
            }
        };
        if self.input.len() < length {
            return Ok(None);
        }
        self.header = None;
        Ok(Some(self.input.drain(..length).collect()))
    }
}

/// What a bootstrap line reports instead of a hello.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sentinel {
    pub code: Failure,
    pub host_target: Option<HelperTarget>,
}

fn sentinels() -> Vec<(Vec<u8>, Sentinel)> {
    let mut all: Vec<(Vec<u8>, Sentinel)> = HelperTarget::ALL
        .iter()
        .map(|target| {
            (
                format!("GITLAMA-BOOTSTRAP 1 missing {}\n", target.host()).into_bytes(),
                Sentinel {
                    code: Failure::HelperNotInstalled,
                    host_target: Some(*target),
                },
            )
        })
        .collect();
    all.push((
        b"GITLAMA-BOOTSTRAP 1 platform\n".to_vec(),
        Sentinel {
            code: Failure::UnsupportedPlatform,
            host_target: None,
        },
    ));
    all
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BootstrapState {
    /// Nothing conclusive yet.
    Pending,
    /// The bytes are a hello frame candidate; decode them as frames.
    Frames,
    /// The bytes cannot be a sentinel or a hello.
    Failed,
}

/// Classifies stdout before a hello. A hello frame begins with a zero byte (its length is at
/// most 64 KiB); anything else must be exactly one sentinel line followed by end of file.
pub struct BootstrapProbe {
    bytes: Vec<u8>,
    state: BootstrapState,
    sentinels: Vec<(Vec<u8>, Sentinel)>,
}

impl Default for BootstrapProbe {
    fn default() -> Self {
        Self {
            bytes: Vec::new(),
            state: BootstrapState::Pending,
            sentinels: sentinels(),
        }
    }
}

impl BootstrapProbe {
    #[must_use]
    pub fn state(&self) -> BootstrapState {
        self.state
    }

    pub fn add(&mut self, bytes: &[u8]) -> BootstrapState {
        if self.state != BootstrapState::Pending || bytes.is_empty() {
            return self.state;
        }
        if self.bytes.is_empty() && bytes[0] == 0 {
            self.state = BootstrapState::Frames;
            return self.state;
        }
        let longest = self
            .sentinels
            .iter()
            .map(|(line, _)| line.len())
            .max()
            .unwrap_or(0);
        let room = (longest + 1).saturating_sub(self.bytes.len());
        self.bytes.extend(bytes.iter().take(room));
        let prefix = self
            .sentinels
            .iter()
            .any(|(line, _)| self.bytes.len() <= line.len() && line.starts_with(&self.bytes));
        if !prefix {
            self.state = BootstrapState::Failed;
        }
        self.state
    }

    /// The failure for end of file before a hello.
    #[must_use]
    pub fn sentinel(&self) -> Option<Sentinel> {
        if self.state != BootstrapState::Pending {
            return None;
        }
        self.sentinels
            .iter()
            .find(|(line, _)| *line == self.bytes)
            .map(|(_, sentinel)| *sentinel)
    }
}

/// Per-connection limits; the effective value is the smaller peer's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    pub frame_bytes: usize,
    pub transaction_bytes: usize,
    pub requests_per_connection: usize,
    pub sessions_per_connection: usize,
}

impl Limits {
    pub const LOCAL: Self = Self {
        frame_bytes: contract::FRAME_BYTES,
        transaction_bytes: contract::TRANSACTION_BYTES,
        requests_per_connection: contract::REQUESTS_PER_CONNECTION,
        sessions_per_connection: contract::SESSIONS_PER_CONNECTION,
    };
}

/// A validated hello.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hello {
    /// Carries the negotiated capability intersection.
    pub info: HelperInfo,
    pub limits: Limits,
    /// Every known capability the helper offered.
    pub offered: HashSet<RemoteCapability>,
}

const HELLO_KEYS: [&str; 14] = [
    "kind",
    "magic",
    "protocolMajor",
    "protocolMinor",
    "buildId",
    "platform",
    "architecture",
    "gitState",
    "gitVersion",
    "helperIncarnation",
    "store",
    "account",
    "capabilities",
    "limits",
];

fn bounded_text(value: &Value) -> Result<String, WireError> {
    let text = w::str_d(value)?;
    if text.len() > MAX_HELLO_TEXT_BYTES {
        return Err(invalid("text"));
    }
    Ok(text)
}

fn negotiate(value: &Value, local: Limits) -> Result<Limits, WireError> {
    let limits = w::object(
        value,
        "limits",
        &[
            "frameBytes",
            "transactionBytes",
            "requestsPerConnection",
            "sessionsPerConnection",
        ],
    )?;
    let effective = |name: &str, local: usize| -> Result<usize, WireError> {
        let remote: u64 = w::big_d(limits.field(name))?;
        if remote == 0 {
            return Err(invalid("limit"));
        }
        Ok(usize::try_from(remote).map_or(local, |remote| remote.min(local)))
    };
    Ok(Limits {
        frame_bytes: effective("frameBytes", local.frame_bytes)?,
        transaction_bytes: effective("transactionBytes", local.transaction_bytes)?,
        requests_per_connection: effective("requestsPerConnection", local.requests_per_connection)?,
        sessions_per_connection: effective("sessionsPerConnection", local.sessions_per_connection)?,
    })
}

/// Validates a hello frame for a client of `build_id` that wants `requested`. A frame that is
/// not a hello is `bootstrapFailed`.
///
/// # Errors
/// The typed failure of a hello this client cannot accept.
pub fn parse_hello(
    payload: &[u8],
    build_id: &str,
    requested: &HashSet<RemoteCapability>,
) -> Result<Hello, Failure> {
    if payload.len() > contract::HELLO_BYTES {
        return Err(Failure::BootstrapFailed);
    }
    let value = w::parse(payload, ParseLimits::FRAME).map_err(|_| Failure::BootstrapFailed)?;
    let Value::Object(map) = &value else {
        return Err(Failure::BootstrapFailed);
    };
    if map.get("kind").and_then(Value::as_str) != Some("hello")
        || map.get("magic").and_then(Value::as_str) != Some(HELPER_MAGIC)
    {
        return Err(Failure::BootstrapFailed);
    }
    match map.get("protocolMajor").and_then(Value::as_i64) {
        Some(PROTOCOL_MAJOR) => {}
        Some(_) => return Err(Failure::ProtocolMismatch),
        None => return Err(Failure::BootstrapFailed),
    }
    let hello = (|| -> Result<Result<Hello, Failure>, WireError> {
        let hello = w::object(&value, "hello", &HELLO_KEYS)?;
        let minor: i64 = w::int_d(hello.field("protocolMinor"))?;
        if minor < 0 {
            return Err(invalid("minor"));
        }
        let helper_build = w::str_d(hello.field("buildId"))?;
        if !is_valid_build_id(&helper_build) {
            return Err(invalid("build"));
        }
        bounded_text(hello.field("platform"))?;
        bounded_text(hello.field("architecture"))?;
        let git_state = w::str_d(hello.field("gitState"))?;
        let git_version = w::opt_d(hello.field("gitVersion"), bounded_text)?;
        let incarnation = w::str_d(hello.field("helperIncarnation"))?;
        if !is_lower_hex(&incarnation, 32) {
            return Err(invalid("incarnation"));
        }
        let store = w::object(hello.field("store"), "store", &["state", "storeId"])?;
        let store_state = w::str_d(store.field("state"))?;
        let store_id = w::opt_d(store.field("storeId"), w::str_d)?;
        let account = w::object(hello.field("account"), "account", &["uid", "name"])?;
        let uid: u64 = w::big_d(account.field("uid"))?;
        let account_name = bounded_text(account.field("name"))?;
        let offered: HashSet<RemoteCapability> = w::list_d(hello.field("capabilities"), w::str_d)?
            .iter()
            .filter_map(|name| RemoteCapability::parse(name))
            .collect();
        let limits = negotiate(hello.field("limits"), Limits::LOCAL)?;
        if !matches!(git_state.as_str(), "available" | "missing" | "unsupported") {
            return Err(invalid("gitState"));
        }
        match (store_state.as_str(), &store_id) {
            ("ready", Some(id)) if is_lower_hex(id, 32) => {}
            ("unavailable", None) => {}
            _ => return Err(invalid("store")),
        }
        if helper_build != build_id {
            return Ok(Err(Failure::BuildMismatch));
        }
        if git_state == "missing" {
            return Ok(Err(Failure::GitMissing));
        }
        if git_state == "unsupported" {
            return Ok(Err(Failure::GitUnsupported));
        }
        let Some(store_id) = store_id else {
            return Ok(Err(Failure::StoreUnavailable));
        };
        Ok(Ok(Hello {
            info: HelperInfo {
                build_id: helper_build,
                incarnation,
                store_id,
                account_uid: uid.to_string(),
                account_name,
                git_version,
                capabilities: requested.intersection(&offered).copied().collect(),
            },
            limits,
            offered,
        }))
    })();
    hello.unwrap_or(Err(Failure::BootstrapFailed))
}

/// The acknowledgement of a validated hello.
#[must_use]
pub fn hello_ack(hello: &Hello, nonce: &str) -> Value {
    serde_json::json!({
        "kind": "helloAck",
        "protocolMajor": PROTOCOL_MAJOR,
        "protocolMinor": PROTOCOL_MINOR,
        "buildId": hello.info.build_id,
        "helperIncarnation": hello.info.incarnation,
        "connectionNonce": nonce,
        "capabilities": RemoteCapability::ALL
            .iter()
            .filter(|capability| hello.info.capabilities.contains(capability))
            .map(|capability| capability.name())
            .collect::<Vec<_>>(),
    })
}

/// An unsolicited helper message.
#[derive(Clone, Debug, PartialEq)]
pub enum Publication {
    /// A session's queued events.
    SessionEvents {
        /// The helper-local session ID.
        session_id: u64,
        /// The decoded `NativeRepositoryEventsResult` JSON.
        events: Value,
    },
    /// The helper's operation center changed: the `NativeOperationCenterResult` JSON.
    OperationCenter { operations: Value },
}

/// A message the helper sent after the acknowledgement.
#[derive(Clone, Debug, PartialEq)]
pub enum HelperMessage {
    Result {
        request_id: u64,
        outcome: Result<Value, RemoteErrorCode>,
    },
    Publication(Publication),
    Chunk {
        request_id: u64,
        payload: Value,
    },
    Pong,
    Goodbye,
    Fatal(Failure),
}

const ENVELOPE_KEYS: [&str; 6] = [
    "protocolMajor",
    "connectionNonce",
    "helperIncarnation",
    "requestId",
    "kind",
    "payload",
];

fn fatal_failure(code: &str) -> Failure {
    match code {
        "handshakeRejected" => Failure::ProtocolMismatch,
        "handshakeTimeout" => Failure::HandshakeTimeout,
        "shutdown" => Failure::Disconnected,
        _ => Failure::ProtocolViolation,
    }
}

/// One connection's envelope state: identity, client request IDs and the publication sequence.
pub struct EnvelopeSession {
    pub nonce: String,
    pub incarnation: String,
    last_request_id: u64,
    last_sequence: u64,
}

impl EnvelopeSession {
    #[must_use]
    pub fn new(nonce: String, incarnation: String) -> Self {
        Self {
            nonce,
            incarnation,
            last_request_id: 0,
            last_sequence: 0,
        }
    }

    /// Allocates the next client request ID. Overflow retires the connection.
    ///
    /// # Errors
    /// The counter is exhausted.
    pub fn next_request_id(&mut self) -> Result<u64, WireError> {
        self.last_request_id = self
            .last_request_id
            .checked_add(1)
            .ok_or_else(|| invalid("request id overflow"))?;
        Ok(self.last_request_id)
    }

    #[must_use]
    pub fn envelope(&self, request_id: u64, kind: &str, payload: Value) -> Value {
        serde_json::json!({
            "protocolMajor": PROTOCOL_MAJOR,
            "connectionNonce": self.nonce,
            "helperIncarnation": self.incarnation,
            "requestId": request_id.to_string(),
            "kind": kind,
            "payload": payload,
        })
    }

    /// Validates a decoded helper envelope. `carried` is the request ID of the chunks of a
    /// reassembled transaction; its inner envelope may only be a result or publication with
    /// the same ID.
    ///
    /// # Errors
    /// Any envelope rule violation.
    pub fn read(
        &mut self,
        value: &Value,
        carried: Option<u64>,
    ) -> Result<HelperMessage, WireError> {
        let envelope = w::object(value, "envelope", &ENVELOPE_KEYS)?;
        if envelope.field("protocolMajor").as_i64() != Some(PROTOCOL_MAJOR)
            || envelope.field("connectionNonce").as_str() != Some(self.nonce.as_str())
            || envelope.field("helperIncarnation").as_str() != Some(self.incarnation.as_str())
        {
            return Err(invalid("envelope identity"));
        }
        let request_id: u64 = w::big_d(envelope.field("requestId"))?;
        if request_id > self.last_request_id {
            return Err(invalid("request id"));
        }
        let kind = w::str_d(envelope.field("kind"))?;
        let payload = envelope.field("payload");
        let Value::Object(fields) = payload else {
            return Err(invalid("payload"));
        };
        if let Some(carried) = carried
            && (request_id != carried || (kind != "result" && kind != "publication"))
        {
            return Err(invalid("transaction envelope"));
        }
        match kind.as_str() {
            "result" => {
                if request_id == 0 || fields.len() != 1 {
                    return Err(invalid("result"));
                }
                if let Some(ok) = fields.get("ok") {
                    return Ok(HelperMessage::Result {
                        request_id,
                        outcome: Ok(ok.clone()),
                    });
                }
                let error = w::object(
                    payload.get("error").unwrap_or(&Value::Null),
                    "error",
                    &["code"],
                )?;
                let code = RemoteErrorCode::parse(&w::str_d(error.field("code"))?)
                    .ok_or_else(|| invalid("error code"))?;
                Ok(HelperMessage::Result {
                    request_id,
                    outcome: Err(code),
                })
            }
            "publication" => {
                if request_id != 0 {
                    return Err(invalid("request id"));
                }
                let kind = payload.get("type").and_then(Value::as_str);
                let fields: &[&str] = match kind {
                    Some("sessionEvents") => &["sequence", "type", "sessionId", "events"],
                    Some("operationCenter") => &["sequence", "type", "operations"],
                    _ => return Err(invalid("publication type")),
                };
                let publication = w::object(payload, "publication", fields)?;
                let sequence: u64 = w::big_d(publication.field("sequence"))?;
                if sequence <= self.last_sequence {
                    return Err(invalid("sequence"));
                }
                let message = if kind == Some("sessionEvents") {
                    Publication::SessionEvents {
                        session_id: w::big_d(publication.field("sessionId"))?,
                        events: publication.field("events").clone(),
                    }
                } else {
                    Publication::OperationCenter {
                        operations: publication.field("operations").clone(),
                    }
                };
                self.last_sequence = sequence;
                Ok(HelperMessage::Publication(message))
            }
            "chunk" => Ok(HelperMessage::Chunk {
                request_id,
                payload: payload.clone(),
            }),
            "pong" | "goodbye" => {
                if request_id == 0 || !fields.is_empty() {
                    return Err(invalid("control"));
                }
                Ok(if kind == "pong" {
                    HelperMessage::Pong
                } else {
                    HelperMessage::Goodbye
                })
            }
            "fatal" => {
                let fatal = w::object(payload, "fatal", &["code"])?;
                Ok(HelperMessage::Fatal(fatal_failure(&w::str_d(
                    fatal.field("code"),
                )?)))
            }
            _ => Err(invalid("kind")),
        }
    }
}

/// At most this many transactions assemble at once per connection.
pub const MAX_ASSEMBLING: usize = 4;
/// Aggregate declared bytes of assembling transactions per connection.
pub const MAX_ASSEMBLING_BYTES: usize = 32 * 1024 * 1024;
const MIN_CHUNKS: usize = 2;
const MAX_CHUNKS: usize = 16;
const MAX_CHUNK_BYTES: usize = 1024 * 1024;

/// A transaction whose last chunk arrived with an exact length.
pub struct CompletedTransaction {
    pub request_id: u64,
    pub bytes: Vec<u8>,
    /// Lowercase hex SHA-256 the helper declared.
    pub digest: String,
}

/// Verifies the digest and parses the inner envelope with transaction bounds.
///
/// # Errors
/// A digest mismatch or invalid JSON.
pub fn decode_transaction(transaction: &CompletedTransaction) -> Result<Value, WireError> {
    let digest = super::model::hex(&Sha256::digest(&transaction.bytes));
    if digest != transaction.digest {
        return Err(invalid("transaction digest"));
    }
    w::parse(&transaction.bytes, ParseLimits::TRANSACTION)
}

struct Assembly {
    request_id: u64,
    count: usize,
    total_bytes: usize,
    digest: String,
    bytes: Vec<u8>,
    next_index: usize,
}

/// Reassembles chunked results and publications. Partial transactions are never presented.
pub struct TransactionAssembler {
    max_transaction_bytes: usize,
    assembling: HashMap<u64, Assembly>,
    last_transaction: u64,
    reserved: usize,
}

impl TransactionAssembler {
    #[must_use]
    pub fn new(max_transaction_bytes: usize) -> Self {
        Self {
            max_transaction_bytes,
            assembling: HashMap::new(),
            last_transaction: 0,
            reserved: 0,
        }
    }

    fn small(value: &Value) -> Result<usize, WireError> {
        let number: u64 = w::big_d(value)?;
        usize::try_from(number)
            .ok()
            .filter(|number| *number <= contract::TRANSACTION_BYTES)
            .ok_or_else(|| invalid("chunk field"))
    }

    /// Adds one chunk; returns the transaction when this was its last chunk.
    ///
    /// # Errors
    /// Any chunk or transaction rule violation.
    pub fn add(
        &mut self,
        request_id: u64,
        payload: &Value,
    ) -> Result<Option<CompletedTransaction>, WireError> {
        let fields = w::object(
            payload,
            "chunk",
            &[
                "transaction",
                "index",
                "count",
                "totalBytes",
                "digest",
                "data",
            ],
        )?;
        let id: u64 = w::big_d(fields.field("transaction"))?;
        let index = Self::small(fields.field("index"))?;
        let count = Self::small(fields.field("count"))?;
        let total_bytes = Self::small(fields.field("totalBytes"))?;
        let digest = w::str_d(fields.field("digest"))?;
        let data = w::bytes_d(fields.field("data"))?;
        if data.is_empty() || data.len() > MAX_CHUNK_BYTES {
            return Err(invalid("chunk data"));
        }
        if !self.assembling.contains_key(&id) {
            if id <= self.last_transaction || index != 0 {
                return Err(invalid("transaction order"));
            }
            if !(MIN_CHUNKS..=MAX_CHUNKS).contains(&count)
                || total_bytes < 1
                || total_bytes > self.max_transaction_bytes
                || !is_lower_hex(&digest, 64)
            {
                return Err(invalid("transaction header"));
            }
            if self.assembling.len() >= MAX_ASSEMBLING
                || self.reserved + total_bytes > MAX_ASSEMBLING_BYTES
            {
                return Err(invalid("transaction capacity"));
            }
            self.last_transaction = id;
            self.reserved += total_bytes;
            self.assembling.insert(
                id,
                Assembly {
                    request_id,
                    count,
                    total_bytes,
                    digest: digest.clone(),
                    bytes: Vec::with_capacity(total_bytes),
                    next_index: 0,
                },
            );
        }
        let assembly = self.assembling.get_mut(&id).expect("inserted above");
        if index != assembly.next_index
            || count != assembly.count
            || total_bytes != assembly.total_bytes
            || digest != assembly.digest
            || request_id != assembly.request_id
        {
            return Err(invalid("transaction chunk"));
        }
        if assembly.bytes.len() + data.len() > assembly.total_bytes {
            return Err(invalid("transaction length"));
        }
        assembly.bytes.extend_from_slice(&data);
        assembly.next_index += 1;
        if assembly.next_index < assembly.count {
            return Ok(None);
        }
        let assembly = self.assembling.remove(&id).expect("present");
        self.reserved -= assembly.total_bytes;
        if assembly.bytes.len() != assembly.total_bytes {
            return Err(invalid("transaction length"));
        }
        Ok(Some(CompletedTransaction {
            request_id: assembly.request_id,
            bytes: assembly.bytes,
            digest: assembly.digest,
        }))
    }

    /// Drops every partial transaction (disconnect).
    pub fn discard(&mut self) {
        self.assembling.clear();
        self.reserved = 0;
    }
}

/// The typed failure of a call error code a helper returned.
#[must_use]
pub fn failure_of(code: RemoteErrorCode) -> Failure {
    match code {
        RemoteErrorCode::PathInvalid => Failure::PathInvalid,
        RemoteErrorCode::PathNotFound => Failure::PathNotFound,
        RemoteErrorCode::PermissionDenied => Failure::PermissionDenied,
        RemoteErrorCode::NotDirectory => Failure::NotDirectory,
        RemoteErrorCode::CursorExpired => Failure::CursorExpired,
        RemoteErrorCode::DirectoryChanged => Failure::DirectoryChanged,
        RemoteErrorCode::TimedOut => Failure::TimedOut,
        RemoteErrorCode::Capacity => Failure::Capacity,
        RemoteErrorCode::UnsupportedCommand => Failure::Unsupported,
        RemoteErrorCode::WriteNotPermitted => Failure::WriteNotPermitted,
        _ => Failure::Internal,
    }
}

impl From<Sentinel> for RemoteError {
    fn from(sentinel: Sentinel) -> Self {
        Self {
            code: sentinel.code,
            host_target: sentinel.host_target,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BUILD: &str = "0000000000000000000000000000000000000023";

    fn hello(build: &str, git: &str) -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "kind": "hello", "magic": HELPER_MAGIC, "protocolMajor": 1, "protocolMinor": 0,
            "buildId": build, "platform": "linux", "architecture": "x86_64",
            "gitState": git, "gitVersion": "2.43.0",
            "helperIncarnation": "a".repeat(32),
            "store": {"state": "ready", "storeId": "b".repeat(32)},
            "account": {"uid": "1000", "name": "alice"},
            "capabilities": ["read", "listDirectory", "stage", "future"],
            "limits": {"frameBytes": "1048576", "transactionBytes": "99999999999",
                       "requestsPerConnection": "8", "sessionsPerConnection": "16"},
        }))
        .unwrap()
    }

    #[test]
    fn frames_decode_incrementally_and_reject_bad_lengths() {
        let frame = encode_frame(b"{}", 10).unwrap();
        let mut decoder = FrameDecoder::new(10);
        decoder.add(&frame[..3]);
        assert_eq!(decoder.next_frame().unwrap(), None);
        assert!(decoder.partial());
        decoder.add(&frame[3..]);
        assert_eq!(decoder.next_frame().unwrap(), Some(b"{}".to_vec()));
        assert!(!decoder.partial());
        decoder.add(&[0, 0, 0, 11]);
        assert!(decoder.next_frame().is_err());
        let mut zero = FrameDecoder::new(10);
        zero.add(&[0, 0, 0, 0]);
        assert!(zero.next_frame().is_err());
        assert!(encode_frame(&[], 10).is_err());
    }

    #[test]
    fn bootstrap_lines_name_the_host_or_fail() {
        let mut probe = BootstrapProbe::default();
        probe.add(b"GITLAMA-BOOTSTRAP 1 missing ");
        probe.add(b"Linux/aarch64\n");
        assert_eq!(probe.state(), BootstrapState::Pending);
        assert_eq!(
            probe.sentinel(),
            Some(Sentinel {
                code: Failure::HelperNotInstalled,
                host_target: Some(HelperTarget::LinuxArm64)
            })
        );
        let mut banner = BootstrapProbe::default();
        assert_eq!(banner.add(b"Welcome!\n"), BootstrapState::Failed);
        let mut frames = BootstrapProbe::default();
        assert_eq!(frames.add(&[0, 0, 1]), BootstrapState::Frames);
    }

    #[test]
    fn hello_negotiates_capabilities_and_limits() {
        let requested: HashSet<_> = [
            RemoteCapability::Read,
            RemoteCapability::ListDirectory,
            RemoteCapability::Commit,
        ]
        .into_iter()
        .collect();
        let parsed = parse_hello(&hello(BUILD, "available"), BUILD, &requested).unwrap();
        assert_eq!(
            parsed.info.capabilities,
            [RemoteCapability::Read, RemoteCapability::ListDirectory]
                .into_iter()
                .collect()
        );
        assert_eq!(parsed.limits.frame_bytes, 1_048_576);
        assert_eq!(parsed.limits.transaction_bytes, contract::TRANSACTION_BYTES);
        assert_eq!(parsed.limits.requests_per_connection, 8);
        assert_eq!(parsed.info.account_uid, "1000");
        let ack = hello_ack(&parsed, &"c".repeat(32));
        assert_eq!(
            ack["capabilities"],
            serde_json::json!(["read", "listDirectory"])
        );
        let other = "1".repeat(40);
        assert_eq!(
            parse_hello(&hello(&other, "available"), BUILD, &requested),
            Err(Failure::BuildMismatch)
        );
        assert_eq!(
            parse_hello(&hello(BUILD, "missing"), BUILD, &requested),
            Err(Failure::GitMissing)
        );
        assert_eq!(
            parse_hello(b"{\"kind\":\"x\"}", BUILD, &requested),
            Err(Failure::BootstrapFailed)
        );
    }

    #[test]
    fn envelopes_check_identity_ids_and_sequences() {
        let mut session = EnvelopeSession::new("n".repeat(32), "i".repeat(32));
        let id = session.next_request_id().unwrap();
        let result = session.envelope(id, "result", serde_json::json!({"ok": 5}));
        assert_eq!(
            session.read(&result, None).unwrap(),
            HelperMessage::Result {
                request_id: 1,
                outcome: Ok(serde_json::json!(5))
            }
        );
        let error = session.envelope(
            id,
            "result",
            serde_json::json!({"error": {"code": "timedOut"}}),
        );
        assert_eq!(
            session.read(&error, None).unwrap(),
            HelperMessage::Result {
                request_id: 1,
                outcome: Err(RemoteErrorCode::TimedOut)
            }
        );
        let future = session.envelope(9, "result", serde_json::json!({"ok": 1}));
        assert!(session.read(&future, None).is_err());
        let publication =
            |sequence: &str| {
                session.envelope(0, "publication", serde_json::json!({
                "sequence": sequence, "type": "sessionEvents", "sessionId": "3", "events": {}
            }))
            };
        let first = publication("1");
        let replay = publication("1");
        assert!(matches!(
            session.read(&first, None).unwrap(),
            HelperMessage::Publication(Publication::SessionEvents { session_id: 3, .. })
        ));
        assert!(session.read(&replay, None).is_err());
        let operations = session.envelope(
            0,
            "publication",
            serde_json::json!({"sequence": "2", "type": "operationCenter", "operations": {}}),
        );
        assert!(matches!(
            session.read(&operations, None).unwrap(),
            HelperMessage::Publication(Publication::OperationCenter { .. })
        ));
        let unknown = session.envelope(
            0,
            "publication",
            serde_json::json!({"sequence": "3", "type": "other", "operations": {}}),
        );
        assert!(session.read(&unknown, None).is_err());
        let mut forged = session.envelope(id, "pong", serde_json::json!({}));
        forged["connectionNonce"] = serde_json::json!("x".repeat(32));
        assert!(session.read(&forged, None).is_err());
    }

    #[test]
    fn transactions_reassemble_only_complete_verified_bytes() {
        let inner = br#"{"protocolMajor":1}"#.to_vec();
        let digest = super::super::model::hex(&Sha256::digest(&inner));
        let chunk = |index: usize, data: &[u8]| {
            serde_json::json!({
                "transaction": "1", "index": index.to_string(), "count": "2",
                "totalBytes": inner.len().to_string(), "digest": digest, "data": w::base64_encode(data),
            })
        };
        let mut assembler = TransactionAssembler::new(contract::TRANSACTION_BYTES);
        assert!(assembler.add(4, &chunk(0, &inner[..5])).unwrap().is_none());
        let done = assembler.add(4, &chunk(1, &inner[5..])).unwrap().unwrap();
        assert_eq!(done.request_id, 4);
        assert!(decode_transaction(&done).is_ok());
        // A repeated transaction ID and out-of-order chunks are violations.
        assert!(assembler.add(4, &chunk(0, &inner[..5])).is_err());
        let mut fresh = TransactionAssembler::new(contract::TRANSACTION_BYTES);
        assert!(fresh.add(4, &chunk(1, &inner[5..])).is_err());
    }
}
