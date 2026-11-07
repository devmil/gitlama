//! One connection: the request reader, the prioritized writer, the worker pool and the session
//! event pump.
//!
//! Control replies never wait behind data, accepted results are never dropped, and queued
//! publications of a session merge while the client is slow. Close and shutdown stop admission
//! first, so teardown never waits on work queued behind itself.
use crate::frame::{self, FrameClock, FrameError};
use crate::protocol::{self, Capability, Session};
use crate::sessions::Sessions;
use gitlama_application::dto::{
    NativeRepositoryEvent, NativeRepositoryEventKind, NativeRepositoryEventsResult,
};
use gitlama_application::wire::generated as g;
use gitlama_application::wire::runtime::{self as w, Map, ParseLimits, Value};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

const WORKERS: usize = 4;
/// Bulk reads may occupy at most this many workers, so interactive reads always find one.
const BULK_WORKERS: usize = 2;
/// Accepted results wait for the writer while this many bytes are queued.
const RESULT_BUFFER_BYTES: usize = 8 * 1024 * 1024;
const PUMP_INTERVAL: Duration = Duration::from_millis(25);
const PUMP_EVENTS: u32 = 64;
/// Pending events per session before they collapse into one resynchronization.
const PENDING_EVENTS: usize = 256;
/// The whole teardown, from the decision to stop to process exit.
pub const SHUTDOWN_DEADLINE: Duration = Duration::from_secs(5);
const WORKER_DRAIN: Duration = Duration::from_secs(3);

/// Reads that may take minutes; they are served after interactive reads.
use gitlama_application::wire::contract::BULK_METHODS;

pub fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

struct Pending {
    events: Vec<NativeRepositoryEvent>,
    failure: Option<gitlama_application::dto::NativeRepositoryFailure>,
}

#[derive(Default)]
struct OutState {
    control: VecDeque<Vec<u8>>,
    results: VecDeque<Vec<u8>>,
    result_bytes: usize,
    publications: VecDeque<u64>,
    pending: HashMap<u64, Pending>,
    next_sequence: u64,
    next_transaction: u64,
    closed: bool,
}

/// The single writer's queues.
pub struct Outbound {
    state: Mutex<OutState>,
    ready: Condvar,
    space: Condvar,
}

impl Outbound {
    fn new() -> Self {
        Self {
            state: Mutex::new(OutState::default()),
            ready: Condvar::new(),
            space: Condvar::new(),
        }
    }

    fn control(&self, payload: Vec<u8>) {
        let mut state = lock(&self.state);
        if state.closed {
            return;
        }
        state.control.push_back(payload);
        self.ready.notify_all();
    }

    /// Queues an accepted result, splitting it into a transaction when it is large. Waits while
    /// the writer is behind, unless the connection is closing.
    fn result(&self, session: &Session, request_id: u64, payload: Value, closing: &AtomicBool) {
        let bytes = w::to_bytes(&session.envelope(request_id, "result", payload));
        let bytes = if bytes.len() > protocol::TRANSACTION_BYTES {
            w::to_bytes(&session.envelope(request_id, "result", protocol::error("capacity")))
        } else {
            bytes
        };
        let mut state = lock(&self.state);
        while state.result_bytes > RESULT_BUFFER_BYTES
            && !state.closed
            && !closing.load(Ordering::Acquire)
        {
            state = self
                .space
                .wait_timeout(state, Duration::from_millis(100))
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .0;
        }
        if state.closed {
            return;
        }
        let frames = frames(session, request_id, bytes, &mut state.next_transaction);
        for frame in frames {
            state.result_bytes += frame.len();
            state.results.push_back(frame);
        }
        self.ready.notify_all();
    }

    /// Queues a session's events, merging them with an unsent publication of the same session.
    fn publish(&self, session_id: u64, result: NativeRepositoryEventsResult) {
        let mut state = lock(&self.state);
        if state.closed {
            return;
        }
        if let Some(pending) = state.pending.get_mut(&session_id) {
            merge(pending, result);
        } else {
            state.pending.insert(
                session_id,
                Pending {
                    events: result.events,
                    failure: result.failure,
                },
            );
            state.publications.push_back(session_id);
        }
        self.ready.notify_all();
    }

    fn forget(&self, session_id: u64) {
        let mut state = lock(&self.state);
        state.pending.remove(&session_id);
        state.publications.retain(|id| *id != session_id);
    }

    /// Stops accepting output; queued control frames are still written.
    fn close(&self) {
        let mut state = lock(&self.state);
        state.closed = true;
        self.ready.notify_all();
        self.space.notify_all();
    }

    /// The writer loop. Returns when the output fails or the queues are closed and empty.
    fn write_all(&self, session: &Session, output: &mut impl Write) {
        let mut inflight: VecDeque<Vec<u8>> = VecDeque::new();
        loop {
            let frame = {
                let mut state = lock(&self.state);
                loop {
                    if let Some(frame) = state.control.pop_front() {
                        break Some(frame);
                    }
                    if let Some(frame) = inflight.pop_front() {
                        break Some(frame);
                    }
                    if let Some(frame) = state.results.pop_front() {
                        state.result_bytes -= frame.len();
                        self.space.notify_all();
                        break Some(frame);
                    }
                    if !state.closed {
                        if let Some(session_id) = state.publications.pop_front() {
                            if let Some(pending) = state.pending.remove(&session_id) {
                                state.next_sequence += 1;
                                let sequence = state.next_sequence;
                                let mut transaction = state.next_transaction;
                                inflight.extend(publication_frames(
                                    session,
                                    session_id,
                                    sequence,
                                    pending,
                                    &mut transaction,
                                ));
                                state.next_transaction = transaction;
                            }
                            continue;
                        }
                    }
                    if state.closed {
                        break None;
                    }
                    state = self
                        .ready
                        .wait(state)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                }
            };
            let Some(frame) = frame else {
                let _ = output.flush();
                return;
            };
            if frame::write_frame(output, &frame).is_err() {
                self.close();
                return;
            }
        }
    }
}

fn merge(pending: &mut Pending, result: NativeRepositoryEventsResult) {
    let carries_snapshot = |event: &NativeRepositoryEvent| {
        matches!(
            event.kind,
            NativeRepositoryEventKind::Snapshot | NativeRepositoryEventKind::Resynchronize
        )
    };
    if result.failure.is_some() {
        pending.failure = result.failure;
    }
    if result.events.iter().any(carries_snapshot) {
        // The newest snapshot supersedes older ones; a superseded resynchronization survives
        // as the kind of the newest one.
        let resynchronize = pending
            .events
            .iter()
            .any(|event| event.kind == NativeRepositoryEventKind::Resynchronize);
        pending.events.retain(|event| !carries_snapshot(event));
        let mut events = result.events;
        if resynchronize {
            if let Some(newest) = events
                .iter_mut()
                .rev()
                .find(|event| carries_snapshot(event))
            {
                newest.kind = NativeRepositoryEventKind::Resynchronize;
            }
        }
        pending.events.extend(events);
    } else {
        pending.events.extend(result.events);
    }
    if pending.events.len() > PENDING_EVENTS {
        let newest = pending
            .events
            .iter()
            .rev()
            .find(|event| carries_snapshot(event))
            .cloned();
        pending.events = match newest {
            Some(mut event) => {
                event.kind = NativeRepositoryEventKind::Resynchronize;
                vec![event]
            }
            None => pending
                .events
                .split_off(pending.events.len() - PENDING_EVENTS),
        };
    }
}

fn publication_frames(
    session: &Session,
    session_id: u64,
    sequence: u64,
    pending: Pending,
    transaction: &mut u64,
) -> Vec<Vec<u8>> {
    let encode = |result: &NativeRepositoryEventsResult| {
        let mut payload = Map::new();
        payload.insert("sequence".into(), Value::from(sequence.to_string()));
        payload.insert("type".into(), Value::from("sessionEvents"));
        payload.insert("sessionId".into(), Value::from(session_id.to_string()));
        payload.insert(
            "events".into(),
            g::enc_native_repository_events_result(result),
        );
        w::to_bytes(&session.envelope_publication(Value::Object(payload)))
    };
    let mut bytes = encode(&NativeRepositoryEventsResult {
        events: pending.events,
        failure: pending.failure,
    });
    if bytes.len() > protocol::TRANSACTION_BYTES {
        // Too large to carry: the client reports the session's state as too large.
        bytes = encode(&NativeRepositoryEventsResult {
            events: Vec::new(),
            failure: Some(gitlama_application::dto::NativeRepositoryFailure {
                kind: gitlama_application::dto::NativeRepositoryFailureKind::TooLarge,
            }),
        });
    }
    frames(session, 0, bytes, transaction)
}

/// One frame, or a chunk transaction for a message above the chunk size.
fn frames(
    session: &Session,
    request_id: u64,
    bytes: Vec<u8>,
    transaction: &mut u64,
) -> Vec<Vec<u8>> {
    if bytes.len() <= protocol::CHUNK_BYTES {
        return vec![bytes];
    }
    *transaction += 1;
    let digest = protocol::hex(&Sha256::digest(&bytes));
    let count = bytes.len().div_ceil(protocol::CHUNK_BYTES);
    bytes
        .chunks(protocol::CHUNK_BYTES)
        .enumerate()
        .map(|(index, data)| {
            let mut payload = Map::new();
            payload.insert("transaction".into(), Value::from(transaction.to_string()));
            payload.insert("index".into(), Value::from(index.to_string()));
            payload.insert("count".into(), Value::from(count.to_string()));
            payload.insert("totalBytes".into(), Value::from(bytes.len().to_string()));
            payload.insert("digest".into(), Value::from(digest.clone()));
            payload.insert("data".into(), w::bytes_e(data));
            w::to_bytes(&session.envelope(request_id, "chunk", Value::Object(payload)))
        })
        .collect()
}

impl Session {
    fn envelope_publication(&self, payload: Value) -> Value {
        let mut map = Map::new();
        map.insert(
            "protocolMajor".into(),
            Value::from(protocol::PROTOCOL_MAJOR),
        );
        map.insert("connectionNonce".into(), Value::from(self.nonce.as_str()));
        map.insert(
            "helperIncarnation".into(),
            Value::from(self.incarnation.as_str()),
        );
        map.insert("requestId".into(), Value::from("0"));
        map.insert("kind".into(), Value::from("publication"));
        map.insert("payload".into(), payload);
        Value::Object(map)
    }
}

struct Job {
    request_id: u64,
    method: String,
    arguments: Value,
    bulk: bool,
}

#[derive(Default)]
struct WorkState {
    interactive: VecDeque<Job>,
    bulk: VecDeque<Job>,
    running_bulk: usize,
    outstanding: HashSet<u64>,
    closed: bool,
}

/// Everything one connection's threads share.
pub struct Connection {
    pub session: Session,
    pub capabilities: Vec<Capability>,
    pub home: Option<PathBuf>,
    pub sessions: Sessions,
    pub writes: Option<crate::writes::Writes>,
    outbound: Outbound,
    work: Mutex<WorkState>,
    work_ready: Condvar,
    listings: Mutex<crate::directory::Listings>,
    closing: AtomicBool,
}

impl Connection {
    pub fn new(
        session: Session,
        capabilities: Vec<Capability>,
        home: Option<PathBuf>,
        store_id: String,
        writes: Option<crate::writes::Writes>,
    ) -> Arc<Self> {
        Arc::new(Self {
            session,
            capabilities,
            home,
            sessions: Sessions::new(store_id),
            writes,
            outbound: Outbound::new(),
            work: Mutex::new(WorkState::default()),
            work_ready: Condvar::new(),
            listings: Mutex::new(crate::directory::Listings::default()),
            closing: AtomicBool::new(false),
        })
    }

    pub fn listings(&self) -> &Mutex<crate::directory::Listings> {
        &self.listings
    }

    pub fn allows(&self, capability: Capability) -> bool {
        self.capabilities.contains(&capability)
    }

    fn reply(&self, request_id: u64, payload: Value) {
        self.outbound
            .result(&self.session, request_id, payload, &self.closing);
    }

    fn reply_control(&self, request_id: u64, kind: &str) {
        let envelope = self
            .session
            .envelope(request_id, kind, Value::Object(Map::new()));
        self.outbound.control(w::to_bytes(&envelope));
    }

    /// Admits a call or answers it at once when the connection is full.
    fn admit(&self, job: Job) {
        let mut work = lock(&self.work);
        if work.closed {
            drop(work);
            self.reply(job.request_id, protocol::error("canceled"));
            return;
        }
        if work.outstanding.len() >= protocol::REQUESTS_PER_CONNECTION {
            drop(work);
            self.reply(job.request_id, protocol::error("capacity"));
            return;
        }
        work.outstanding.insert(job.request_id);
        if job.bulk {
            work.bulk.push_back(job);
        } else {
            work.interactive.push_back(job);
        }
        self.work_ready.notify_one();
    }

    fn cancel(&self, target: u64) {
        let mut work = lock(&self.work);
        let before = work.interactive.len() + work.bulk.len();
        work.interactive.retain(|job| job.request_id != target);
        work.bulk.retain(|job| job.request_id != target);
        if work.interactive.len() + work.bulk.len() < before {
            work.outstanding.remove(&target);
            drop(work);
            self.reply(target, protocol::error("canceled"));
        }
    }

    fn next_job(&self) -> Option<Job> {
        let mut work = lock(&self.work);
        loop {
            if let Some(job) = work.interactive.pop_front() {
                return Some(job);
            }
            if work.running_bulk < BULK_WORKERS {
                if let Some(job) = work.bulk.pop_front() {
                    work.running_bulk += 1;
                    return Some(job);
                }
            }
            if work.closed {
                return None;
            }
            work = self
                .work_ready
                .wait(work)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    }

    fn finish_job(&self, job: &Job) {
        let mut work = lock(&self.work);
        work.outstanding.remove(&job.request_id);
        if job.bulk {
            work.running_bulk -= 1;
        }
        self.work_ready.notify_all();
    }

    fn worker(self: &Arc<Self>) {
        while let Some(job) = self.next_job() {
            let payload = match crate::dispatch::call(self, &job.method, &job.arguments) {
                Ok(value) => protocol::ok(value),
                Err(code) => protocol::error(code),
            };
            self.finish_job(&job);
            self.reply(job.request_id, payload);
        }
    }

    fn pump(self: &Arc<Self>) {
        while !self.closing.load(Ordering::Acquire) {
            for (session_id, generation) in self.sessions.live() {
                let result = gitlama_application::application::session::repository_session_events(
                    session_id,
                    generation,
                    PUMP_EVENTS,
                );
                if (!result.events.is_empty() || result.failure.is_some())
                    && self.sessions.is_live(session_id)
                {
                    self.outbound.publish(session_id, result);
                }
            }
            std::thread::sleep(PUMP_INTERVAL);
        }
    }

    /// Forgets a closed session's queued publications.
    pub fn forget_session(&self, session_id: u64) {
        self.outbound.forget(session_id);
    }
}

/// Why the reader stopped.
enum Stop {
    /// End of input: nobody reads the replies.
    End,
    /// An orderly shutdown request.
    Shutdown(u64),
    /// A malformed or out-of-contract frame.
    Violation,
}

/// Serves one acknowledged connection until it ends, then tears it down within the deadline.
pub fn serve(
    connection: &Arc<Connection>,
    mut input: impl Read,
    mut output: impl Write + Send + 'static,
    clock: &FrameClock,
) {
    let writer = {
        let connection = Arc::clone(connection);
        std::thread::spawn(move || {
            connection
                .outbound
                .write_all(&connection.session, &mut output);
        })
    };
    let workers: Vec<_> = (0..WORKERS)
        .map(|_| {
            let connection = Arc::clone(connection);
            std::thread::spawn(move || connection.worker())
        })
        .collect();
    let pump = {
        let connection = Arc::clone(connection);
        std::thread::spawn(move || connection.pump())
    };
    let stop = read_requests(connection, &mut input, clock);
    let deadline = Instant::now() + SHUTDOWN_DEADLINE;
    {
        let connection = Arc::clone(connection);
        std::thread::spawn(move || {
            // Teardown never outlives its deadline, even when Git or the client is stuck.
            std::thread::sleep(deadline.saturating_duration_since(Instant::now()));
            let _ = &connection;
            std::process::exit(0);
        });
    }
    connection.closing.store(true, Ordering::Release);
    let queued: Vec<u64> = {
        let mut work = lock(&connection.work);
        work.closed = true;
        let state = &mut *work;
        let queued: Vec<u64> = state
            .interactive
            .drain(..)
            .chain(state.bulk.drain(..))
            .map(|job| job.request_id)
            .collect();
        for id in &queued {
            work.outstanding.remove(id);
        }
        connection.work_ready.notify_all();
        queued
    };
    match stop {
        Stop::Violation => {
            let fatal = connection.session.envelope(
                0,
                "fatal",
                protocol::fatal_payload("protocolViolation"),
            );
            connection.outbound.control(w::to_bytes(&fatal));
        }
        Stop::Shutdown(_) => {
            for id in queued {
                connection.reply(id, protocol::error("canceled"));
            }
        }
        Stop::End => {}
    }
    let drain_until = Instant::now() + WORKER_DRAIN;
    for worker in workers {
        while !worker.is_finished() && Instant::now() < drain_until {
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    connection.sessions.close_all(connection);
    let _ = pump.join();
    if let Stop::Shutdown(request_id) = stop {
        connection.reply_control(request_id, "goodbye");
    }
    connection.outbound.close();
    let _ = writer.join();
}

fn read_requests(connection: &Arc<Connection>, input: &mut impl Read, clock: &FrameClock) -> Stop {
    let mut last_request = 0_u64;
    loop {
        let payload = match frame::read_frame(input, frame::MAX_FRAME_BYTES, clock) {
            Ok(payload) => payload,
            // A truncated frame means the client went away: nobody reads replies either way.
            Err(FrameError::End | FrameError::Truncated) => return Stop::End,
            Err(FrameError::Length) => return Stop::Violation,
        };
        let Ok(value) = w::parse(&payload, ParseLimits::FRAME) else {
            return Stop::Violation;
        };
        let Ok(envelope) = connection.session.parse(&value) else {
            return Stop::Violation;
        };
        if envelope.request_id <= last_request {
            return Stop::Violation;
        }
        last_request = envelope.request_id;
        match envelope.kind.as_str() {
            "call" => {
                let Ok(call) = w::object(&envelope.payload, "call", &["method", "args"]) else {
                    return Stop::Violation;
                };
                let (Some(method), arguments) = (call.field("method").as_str(), call.field("args"))
                else {
                    return Stop::Violation;
                };
                if !arguments.is_object() || method.len() > 64 {
                    return Stop::Violation;
                }
                connection.admit(Job {
                    request_id: envelope.request_id,
                    bulk: BULK_METHODS.contains(&method),
                    method: method.to_owned(),
                    arguments: arguments.clone(),
                });
            }
            "cancel" => {
                let Ok(cancel) = w::object(&envelope.payload, "cancel", &["target"]) else {
                    return Stop::Violation;
                };
                let Ok(target) = w::big_d::<u64>(cancel.field("target")) else {
                    return Stop::Violation;
                };
                connection.cancel(target);
            }
            "ping" => connection.reply_control(envelope.request_id, "pong"),
            "shutdown" => return Stop::Shutdown(envelope.request_id),
            _ => return Stop::Violation,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_application::dto::{NativeRepositoryFailure, NativeRepositoryFailureKind};

    fn event(kind: NativeRepositoryEventKind, read_id: Option<u64>) -> NativeRepositoryEvent {
        NativeRepositoryEvent {
            kind,
            snapshot: None,
            read_id,
            cache_hit: false,
            watch_overflow_revision: None,
        }
    }

    #[test]
    fn newest_snapshot_supersedes_and_keeps_resynchronization() {
        let mut pending = Pending {
            events: vec![
                event(NativeRepositoryEventKind::Resynchronize, None),
                event(NativeRepositoryEventKind::ReadCompleted, Some(1)),
            ],
            failure: None,
        };
        merge(
            &mut pending,
            NativeRepositoryEventsResult {
                events: vec![event(NativeRepositoryEventKind::Snapshot, None)],
                failure: Some(NativeRepositoryFailure {
                    kind: NativeRepositoryFailureKind::Watch,
                }),
            },
        );
        let kinds: Vec<_> = pending.events.iter().map(|event| event.kind).collect();
        assert_eq!(
            kinds,
            vec![
                NativeRepositoryEventKind::ReadCompleted,
                NativeRepositoryEventKind::Resynchronize
            ]
        );
        assert!(pending.failure.is_some());
    }

    #[test]
    fn overflowing_events_collapse_to_one_resynchronization() {
        let mut pending = Pending {
            events: vec![event(NativeRepositoryEventKind::Snapshot, None)],
            failure: None,
        };
        let reads = (0..300)
            .map(|id| event(NativeRepositoryEventKind::ReadCompleted, Some(id)))
            .collect();
        merge(
            &mut pending,
            NativeRepositoryEventsResult {
                events: reads,
                failure: None,
            },
        );
        assert_eq!(pending.events.len(), 1);
        assert_eq!(
            pending.events[0].kind,
            NativeRepositoryEventKind::Resynchronize
        );
    }

    #[test]
    fn large_messages_become_ordered_chunk_transactions() {
        let session = Session {
            nonce: "0".repeat(32),
            incarnation: "1".repeat(32),
        };
        let bytes = vec![b'x'; protocol::CHUNK_BYTES * 2 + 5];
        let mut transaction = 0;
        let chunks = frames(&session, 9, bytes.clone(), &mut transaction);
        assert_eq!(chunks.len(), 3);
        assert_eq!(transaction, 1);
        let mut joined = Vec::new();
        for (index, frame) in chunks.iter().enumerate() {
            assert!(frame.len() <= frame::MAX_FRAME_BYTES);
            let value = w::parse(frame, ParseLimits::FRAME).unwrap();
            assert_eq!(value["requestId"], "9");
            assert_eq!(value["payload"]["index"], index.to_string());
            assert_eq!(value["payload"]["count"], "3");
            joined.extend(w::bytes_d(&value["payload"]["data"]).unwrap());
        }
        assert_eq!(joined, bytes);
        assert_eq!(
            frames(&session, 9, vec![b'y'; 10], &mut transaction).len(),
            1
        );
    }
}
