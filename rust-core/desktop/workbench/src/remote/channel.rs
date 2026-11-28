//! One handshaken connection to a remote helper over an owned process: the bootstrap probe, the hello, calls with deadlines, cancels,
//! pings, liveness, publications and a bounded shutdown.

use super::model::{Failure, HelperInfo, RemoteError};
use super::process::{ProcessEvent, RemoteProcess};
use super::protocol::{
    self, BootstrapProbe, BootstrapState, EnvelopeSession, FrameDecoder, Hello, HelperMessage,
    Publication, TransactionAssembler,
};
use crate::rt::{self, PeriodicHandle, TimerHandle};
use futures::StreamExt;
use futures::channel::{mpsc, oneshot};
use gitlama_application::wire::contract::{self, RemoteCapability, RemoteErrorCode};
use gitlama_application::wire::runtime::{self as w, ParseLimits, Value};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::sync::Arc;
use std::time::Duration;

/// The helper must send its hello this long after the process started.
pub const HELLO_DEADLINE: Duration = Duration::from_secs(10);
pub const INTERACTIVE_DEADLINE: Duration = Duration::from_secs(30);
pub const BULK_DEADLINE: Duration = Duration::from_secs(120);
pub const PING_INTERVAL: Duration = Duration::from_secs(15);
/// No frame for this long marks the connection disconnected.
pub const LIVENESS_TIMEOUT: Duration = Duration::from_secs(45);
/// [`Channel::close`] waits this long for `goodbye` or exit.
pub const SHUTDOWN_GRACE: Duration = Duration::from_secs(5);
/// An incomplete frame fails this long after its first byte.
pub const PARTIAL_FRAME_DEADLINE: Duration = Duration::from_secs(15);
/// After the process exits, stdout gets this long to deliver its end.
const EXIT_DRAIN_GRACE: Duration = Duration::from_secs(2);
/// Request slots kept for cancel, ping and shutdown.
const RESERVED_CONTROL_SLOTS: usize = 4;
/// Frames at least this large are parsed on the blocking pool.
const OFFLOAD_BYTES: usize = 256 * 1024;

/// Why a call has no result.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CallFault {
    /// The helper or this client answered with a typed code.
    Code(RemoteErrorCode),
    /// The connection is gone.
    Disconnected,
}

/// Cancels a connection attempt or an installation.
#[derive(Default)]
pub struct Cancel {
    canceled: Cell<bool>,
    listeners: RefCell<Vec<Box<dyn FnOnce()>>>,
}

impl Cancel {
    #[must_use]
    pub fn new() -> Rc<Self> {
        Rc::new(Self::default())
    }

    pub fn cancel(&self) {
        if self.canceled.replace(true) {
            return;
        }
        let listeners = std::mem::take(&mut *self.listeners.borrow_mut());
        for listener in listeners {
            listener();
        }
    }

    #[must_use]
    pub fn is_canceled(&self) -> bool {
        self.canceled.get()
    }

    /// Runs `listener` on cancel, at once when already canceled.
    pub fn on_cancel(&self, listener: impl FnOnce() + 'static) {
        if self.canceled.get() {
            listener();
        } else {
            self.listeners.borrow_mut().push(Box::new(listener));
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Stage {
    Handshake,
    Open,
    Closing,
    Closed,
}

struct Pending {
    sender: oneshot::Sender<Result<Value, CallFault>>,
    _deadline: TimerHandle,
}

type PublicationListener = Rc<dyn Fn(&Publication)>;
type ClosedListener = Box<dyn FnOnce(Option<Failure>)>;

struct State {
    stage: Stage,
    probe: BootstrapProbe,
    decoder: FrameDecoder,
    hello: Option<Hello>,
    session: Option<EnvelopeSession>,
    assembler: Option<TransactionAssembler>,
    pending: HashMap<u64, Pending>,
    stdout_done: bool,
    exit: Option<Option<i32>>,
    hello_timer: Option<TimerHandle>,
    exit_drain: Option<TimerHandle>,
    partial: Option<TimerHandle>,
    ping: Option<PeriodicHandle>,
    liveness: Option<TimerHandle>,
    handshake: Option<oneshot::Sender<Result<(), RemoteError>>>,
    goodbye: Option<oneshot::Sender<()>>,
    closed: Option<Option<Failure>>,
    closed_listeners: Vec<ClosedListener>,
    publication_listeners: Vec<PublicationListener>,
}

/// A connection to a remote helper.
pub struct Channel {
    process: Arc<RemoteProcess>,
    build_id: String,
    requested: HashSet<RemoteCapability>,
    state: RefCell<State>,
    this: Weak<Channel>,
}

impl Channel {
    /// Performs the handshake on `process` and returns the open channel. The process is
    /// terminated on failure.
    ///
    /// # Errors
    /// The typed failure of the bootstrap or handshake.
    pub async fn connect(
        process: Arc<RemoteProcess>,
        mut events: mpsc::UnboundedReceiver<ProcessEvent>,
        build_id: String,
        capabilities: HashSet<RemoteCapability>,
        cancel: Option<Rc<Cancel>>,
    ) -> Result<Rc<Self>, RemoteError> {
        let (handshake, handshaken) = oneshot::channel();
        let channel = Rc::new_cyclic(|this| Self {
            process,
            build_id,
            requested: capabilities,
            state: RefCell::new(State {
                stage: Stage::Handshake,
                probe: BootstrapProbe::default(),
                decoder: FrameDecoder::new(contract::HELLO_BYTES),
                hello: None,
                session: None,
                assembler: None,
                pending: HashMap::new(),
                stdout_done: false,
                exit: None,
                hello_timer: None,
                exit_drain: None,
                partial: None,
                ping: None,
                liveness: None,
                handshake: Some(handshake),
                goodbye: None,
                closed: None,
                closed_listeners: Vec::new(),
                publication_listeners: Vec::new(),
            }),
            this: this.clone(),
        });
        let weak = Rc::downgrade(&channel);
        channel.state.borrow_mut().hello_timer = Some(TimerHandle::start(HELLO_DEADLINE, {
            let weak = weak.clone();
            move || {
                if let Some(channel) = weak.upgrade() {
                    channel.fail_handshake(Failure::HandshakeTimeout.into());
                }
            }
        }));
        if let Some(cancel) = cancel {
            let weak = weak.clone();
            cancel.on_cancel(move || {
                if let Some(channel) = weak.upgrade() {
                    channel.fail_handshake(Failure::Canceled.into());
                }
            });
        }
        // The reader holds the channel only while it handles one event.
        rt::spawn_detached(async move {
            while let Some(event) = events.next().await {
                let Some(channel) = weak.upgrade() else {
                    return;
                };
                channel.on_event(event).await;
            }
        });
        match handshaken.await {
            Ok(Ok(())) => Ok(channel),
            Ok(Err(error)) => Err(error),
            Err(_) => Err(Failure::Canceled.into()),
        }
    }

    /// The validated hello and the negotiated capabilities.
    ///
    /// # Panics
    /// Never on a connected channel.
    #[must_use]
    pub fn helper(&self) -> HelperInfo {
        self.state
            .borrow()
            .hello
            .as_ref()
            .expect("connected")
            .info
            .clone()
    }

    #[must_use]
    pub fn has(&self, capability: RemoteCapability) -> bool {
        self.state
            .borrow()
            .hello
            .as_ref()
            .is_some_and(|hello| hello.info.capabilities.contains(&capability))
    }

    #[must_use]
    pub fn is_open(&self) -> bool {
        self.state.borrow().stage == Stage::Open
    }

    /// The close reason once closed: `None` for an orderly close this client requested.
    #[must_use]
    pub fn closed(&self) -> Option<Option<Failure>> {
        self.state.borrow().closed
    }

    /// Runs `listener` once when the channel becomes unusable.
    pub fn on_closed(&self, listener: impl FnOnce(Option<Failure>) + 'static) {
        let closed = self.state.borrow().closed;
        match closed {
            Some(reason) => listener(reason),
            None => self
                .state
                .borrow_mut()
                .closed_listeners
                .push(Box::new(listener)),
        }
    }

    /// Receives every publication while open.
    pub fn on_publication(&self, listener: impl Fn(&Publication) + 'static) {
        self.state
            .borrow_mut()
            .publication_listeners
            .push(Rc::new(listener));
    }

    fn capacity(&self) -> usize {
        self.state.borrow().hello.as_ref().map_or(1, |hello| {
            hello
                .limits
                .requests_per_connection
                .saturating_sub(RESERVED_CONTROL_SLOTS)
                .max(1)
        })
    }

    // Input -------------------------------------------------------------------

    async fn on_event(&self, event: ProcessEvent) {
        match event {
            ProcessEvent::Stdout(bytes) => self.on_data(&bytes).await,
            ProcessEvent::StdoutEnd => self.on_stdout_end().await,
            ProcessEvent::Exited(code) => {
                let mut state = self.state.borrow_mut();
                state.exit = Some(code);
                if state.stdout_done || state.stage == Stage::Closed {
                    return;
                }
                // A descendant (ProxyCommand) can hold stdout open after ssh exited.
                let weak = self.this.clone();
                state.exit_drain = Some(TimerHandle::start(EXIT_DRAIN_GRACE, move || {
                    if let Some(channel) = weak.upgrade() {
                        rt::spawn_detached(async move { channel.on_stdout_end().await });
                    }
                }));
            }
        }
    }

    async fn on_data(&self, bytes: &[u8]) {
        {
            let mut state = self.state.borrow_mut();
            if state.stage == Stage::Closed {
                return;
            }
            if state.stage == Stage::Handshake && state.probe.state() != BootstrapState::Frames {
                match state.probe.add(bytes) {
                    BootstrapState::Failed => {
                        drop(state);
                        self.fail_handshake(Failure::BootstrapFailed.into());
                        return;
                    }
                    BootstrapState::Pending => return,
                    BootstrapState::Frames => {}
                }
            }
            state.decoder.add(bytes);
        }
        self.drain().await;
    }

    async fn drain(&self) {
        loop {
            let next = {
                let mut state = self.state.borrow_mut();
                if state.stage == Stage::Closed {
                    return;
                }
                state.decoder.next_frame()
            };
            let frame = match next {
                Err(_) => {
                    self.protocol_failure();
                    return;
                }
                Ok(None) => {
                    self.arm_partial_deadline();
                    return;
                }
                Ok(Some(frame)) => frame,
            };
            self.state.borrow_mut().partial = None;
            if self.state.borrow().stage == Stage::Handshake {
                self.on_hello(&frame);
                continue;
            }
            self.touch_liveness();
            let parsed = if frame.len() >= OFFLOAD_BYTES {
                rt::blocking(move || w::parse(&frame, ParseLimits::FRAME)).await
            } else {
                w::parse(&frame, ParseLimits::FRAME)
            };
            match parsed {
                Ok(value) => self.on_envelope(&value, None).await,
                Err(_) => {
                    self.protocol_failure();
                    return;
                }
            }
        }
    }

    fn arm_partial_deadline(&self) {
        let mut state = self.state.borrow_mut();
        if !state.decoder.partial() {
            state.partial = None;
            return;
        }
        if state.partial.is_some() {
            return;
        }
        let weak = self.this.clone();
        state.partial = Some(TimerHandle::start(PARTIAL_FRAME_DEADLINE, move || {
            if let Some(channel) = weak.upgrade() {
                channel.protocol_failure();
            }
        }));
    }

    fn on_hello(&self, frame: &[u8]) {
        let hello = match protocol::parse_hello(frame, &self.build_id, &self.requested) {
            Ok(hello) => hello,
            Err(code) => {
                self.fail_handshake(code.into());
                return;
            }
        };
        let nonce = super::model::random_hex32();
        let ack = protocol::hello_ack(&hello, &nonce);
        let Ok(frame) = protocol::encode_frame(&w::to_bytes(&ack), contract::HELLO_BYTES) else {
            self.fail_handshake(Failure::BootstrapFailed.into());
            return;
        };
        let handshake = {
            let mut state = self.state.borrow_mut();
            state.session = Some(EnvelopeSession::new(nonce, hello.info.incarnation.clone()));
            state.assembler = Some(TransactionAssembler::new(hello.limits.transaction_bytes));
            state.decoder.max_frame_bytes = hello.limits.frame_bytes;
            state.hello = Some(hello);
            state.hello_timer = None;
            state.stage = Stage::Open;
            let weak = self.this.clone();
            state.ping = Some(PeriodicHandle::start(PING_INTERVAL, move || {
                if let Some(channel) = weak.upgrade() {
                    channel.send_control("ping", serde_json::json!({}));
                }
            }));
            state.handshake.take()
        };
        self.process.write(frame);
        self.touch_liveness();
        if let Some(handshake) = handshake {
            let _ = handshake.send(Ok(()));
        }
    }

    async fn on_envelope(&self, value: &Value, carried: Option<u64>) {
        let message = {
            let mut state = self.state.borrow_mut();
            if state.stage == Stage::Closed {
                return;
            }
            let Some(session) = state.session.as_mut() else {
                return;
            };
            session.read(value, carried)
        };
        let message = match message {
            Ok(message) => message,
            Err(_) => {
                self.protocol_failure();
                return;
            }
        };
        if let HelperMessage::Chunk {
            request_id,
            payload,
        } = &message
        {
            let completed = {
                let mut state = self.state.borrow_mut();
                let Some(assembler) = state.assembler.as_mut() else {
                    return;
                };
                assembler.add(*request_id, payload)
            };
            let transaction = match completed {
                Ok(Some(transaction)) => transaction,
                Ok(None) => return,
                Err(_) => {
                    self.protocol_failure();
                    return;
                }
            };
            let request_id = transaction.request_id;
            let decoded = rt::blocking(move || protocol::decode_transaction(&transaction)).await;
            let inner = match decoded {
                Ok(inner) => inner,
                Err(_) => {
                    self.protocol_failure();
                    return;
                }
            };
            let message = {
                let mut state = self.state.borrow_mut();
                if state.stage == Stage::Closed {
                    return;
                }
                let Some(session) = state.session.as_mut() else {
                    return;
                };
                session.read(&inner, Some(request_id))
            };
            match message {
                Ok(message) => self.dispatch(message),
                Err(_) => self.protocol_failure(),
            }
            return;
        }
        self.dispatch(message);
    }

    fn dispatch(&self, message: HelperMessage) {
        match message {
            HelperMessage::Result {
                request_id,
                outcome,
            } => {
                // A retired, timed out or unknown request: the late result is ignored.
                let pending = self.state.borrow_mut().pending.remove(&request_id);
                if let Some(pending) = pending {
                    let _ = pending.sender.send(outcome.map_err(CallFault::Code));
                }
            }
            HelperMessage::Publication(publication) => {
                let listeners = {
                    let state = self.state.borrow();
                    if state.stage != Stage::Open {
                        return;
                    }
                    state.publication_listeners.clone()
                };
                for listener in listeners {
                    listener(&publication);
                }
            }
            HelperMessage::Chunk { .. } | HelperMessage::Pong => {}
            HelperMessage::Goodbye => {
                if let Some(goodbye) = self.state.borrow_mut().goodbye.take() {
                    let _ = goodbye.send(());
                }
            }
            HelperMessage::Fatal(code) => self.fail(code),
        }
    }

    async fn on_stdout_end(&self) {
        let stage = {
            let mut state = self.state.borrow_mut();
            if state.stdout_done {
                return;
            }
            state.stdout_done = true;
            state.exit_drain = None;
            state.stage
        };
        match stage {
            Stage::Handshake => self.bootstrap_ended().await,
            Stage::Open => self.fail(Failure::Disconnected),
            Stage::Closing => {
                if let Some(goodbye) = self.state.borrow_mut().goodbye.take() {
                    let _ = goodbye.send(());
                }
            }
            Stage::Closed => {}
        }
    }

    async fn bootstrap_ended(&self) {
        let sentinel = self.state.borrow().probe.sentinel();
        if let Some(sentinel) = sentinel {
            self.fail_handshake(sentinel.into());
            return;
        }
        for _ in 0..(EXIT_DRAIN_GRACE.as_millis() / 50) {
            if self.state.borrow().exit.is_some() || self.process.exit_status().is_some() {
                break;
            }
            rt::sleep(Duration::from_millis(50)).await;
        }
        let exit = self
            .state
            .borrow()
            .exit
            .or_else(|| self.process.exit_status());
        self.fail_handshake(
            if exit == Some(Some(255)) {
                Failure::SshConnectionFailed
            } else {
                Failure::BootstrapFailed
            }
            .into(),
        );
    }

    fn fail_handshake(&self, error: RemoteError) {
        let (handshake, listeners) = {
            let mut state = self.state.borrow_mut();
            if state.stage != Stage::Handshake {
                return;
            }
            state.stage = Stage::Closed;
            state.closed = Some(Some(error.code));
            (
                state.handshake.take(),
                std::mem::take(&mut state.closed_listeners),
            )
        };
        self.release();
        super::note(
            crate::diagnostics::Level::Info,
            "remote_handshake_failed",
            &[("failure_code", error.code.name().into())],
        );
        for listener in listeners {
            listener(Some(error.code));
        }
        if let Some(handshake) = handshake {
            let _ = handshake.send(Err(error));
        }
    }

    fn fail(&self, code: Failure) {
        let listeners = {
            let mut state = self.state.borrow_mut();
            if state.stage == Stage::Closing {
                if let Some(goodbye) = state.goodbye.take() {
                    let _ = goodbye.send(());
                }
                return;
            }
            if state.stage != Stage::Open {
                return;
            }
            state.stage = Stage::Closed;
            state.closed = Some(Some(code));
            std::mem::take(&mut state.closed_listeners)
        };
        self.release();
        super::note(
            crate::diagnostics::Level::Warning,
            "remote_channel_failed",
            &[("failure_code", code.name().into())],
        );
        for listener in listeners {
            listener(Some(code));
        }
    }

    fn protocol_failure(&self) {
        if self.state.borrow().stage == Stage::Handshake {
            self.fail_handshake(Failure::BootstrapFailed.into());
        } else {
            self.fail(Failure::ProtocolViolation);
        }
    }

    /// Stops timers and input, fails every pending call once and terminates the process.
    fn release(&self) {
        let pending = {
            let mut state = self.state.borrow_mut();
            state.hello_timer = None;
            state.exit_drain = None;
            state.partial = None;
            state.ping = None;
            state.liveness = None;
            state.decoder = FrameDecoder::new(0);
            if let Some(assembler) = state.assembler.as_mut() {
                assembler.discard();
            }
            state.publication_listeners.clear();
            std::mem::take(&mut state.pending)
        };
        for (_, call) in pending {
            let _ = call.sender.send(Err(CallFault::Disconnected));
        }
        let process = Arc::clone(&self.process);
        rt::spawn_detached(async move { process.terminate().await });
    }

    /// Graceful shutdown, bounded, followed by process termination.
    pub async fn close(&self) {
        let stage = self.state.borrow().stage;
        match stage {
            Stage::Handshake => {
                self.fail_handshake(Failure::Canceled.into());
                self.process.terminate().await;
                return;
            }
            Stage::Closed | Stage::Closing => {
                self.process.terminate().await;
                return;
            }
            Stage::Open => {}
        }
        let (goodbye, pending, listeners) = {
            let mut state = self.state.borrow_mut();
            state.stage = Stage::Closing;
            state.closed = Some(None);
            state.ping = None;
            state.liveness = None;
            let (sender, receiver) = oneshot::channel();
            state.goodbye = Some(sender);
            state.publication_listeners.clear();
            (
                receiver,
                std::mem::take(&mut state.pending),
                std::mem::take(&mut state.closed_listeners),
            )
        };
        for (_, call) in pending {
            let _ = call.sender.send(Err(CallFault::Disconnected));
        }
        for listener in listeners {
            listener(None);
        }
        self.send_control("shutdown", serde_json::json!({}));
        if !self.state.borrow().stdout_done {
            let _ = rt::timeout(SHUTDOWN_GRACE, goodbye).await;
        }
        self.state.borrow_mut().stage = Stage::Closed;
        self.release();
        self.process.terminate().await;
    }

    // Output ------------------------------------------------------------------

    /// Sends a call and resolves with the decoded `ok` value. `bulk` selects the 120 second
    /// deadline instead of 30 seconds.
    pub fn call(
        &self,
        method: &str,
        arguments: Value,
        bulk: bool,
    ) -> impl Future<Output = Result<Value, CallFault>> + 'static {
        let receiver = self.send_call(method, arguments, bulk);
        async move {
            match receiver {
                Ok(receiver) => receiver.await.unwrap_or(Err(CallFault::Disconnected)),
                Err(fault) => Err(fault),
            }
        }
    }

    fn send_call(
        &self,
        method: &str,
        arguments: Value,
        bulk: bool,
    ) -> Result<oneshot::Receiver<Result<Value, CallFault>>, CallFault> {
        let capacity = self.capacity();
        let mut state = self.state.borrow_mut();
        if state.stage != Stage::Open {
            return Err(CallFault::Disconnected);
        }
        if state.pending.len() >= capacity {
            return Err(CallFault::Code(RemoteErrorCode::Capacity));
        }
        let frame_bytes = state
            .hello
            .as_ref()
            .map_or(0, |hello| hello.limits.frame_bytes);
        let Some(session) = state.session.as_mut() else {
            return Err(CallFault::Disconnected);
        };
        let Ok(request_id) = session.next_request_id() else {
            drop(state);
            self.fail(Failure::Disconnected);
            return Err(CallFault::Disconnected);
        };
        let envelope = session.envelope(
            request_id,
            "call",
            serde_json::json!({ "method": method, "args": arguments }),
        );
        // Unencodable or oversized arguments never reach the helper.
        let frame = protocol::encode_frame(&w::to_bytes(&envelope), frame_bytes)
            .map_err(|_| CallFault::Code(RemoteErrorCode::InvalidRequest))?;
        let (sender, receiver) = oneshot::channel();
        let weak = self.this.clone();
        let deadline = TimerHandle::start(
            if bulk {
                BULK_DEADLINE
            } else {
                INTERACTIVE_DEADLINE
            },
            move || {
                if let Some(channel) = weak.upgrade() {
                    channel.expire(request_id);
                }
            },
        );
        state.pending.insert(
            request_id,
            Pending {
                sender,
                _deadline: deadline,
            },
        );
        drop(state);
        self.process.write(frame);
        Ok(receiver)
    }

    fn expire(&self, request_id: u64) {
        let pending = self.state.borrow_mut().pending.remove(&request_id);
        let Some(pending) = pending else { return };
        let _ = pending
            .sender
            .send(Err(CallFault::Code(RemoteErrorCode::TimedOut)));
        // Expiry is not proof the helper stopped; a late result is ignored.
        self.send_control(
            "cancel",
            serde_json::json!({ "target": request_id.to_string() }),
        );
    }

    fn send_control(&self, kind: &str, payload: Value) {
        let frame = {
            let mut state = self.state.borrow_mut();
            if state.stage != Stage::Open && state.stage != Stage::Closing {
                return;
            }
            let Some(session) = state.session.as_mut() else {
                return;
            };
            let Ok(request_id) = session.next_request_id() else {
                drop(state);
                self.fail(Failure::Disconnected);
                return;
            };
            let envelope = session.envelope(request_id, kind, payload);
            protocol::encode_frame(&w::to_bytes(&envelope), contract::FRAME_BYTES)
        };
        if let Ok(frame) = frame {
            self.process.write(frame);
        }
    }

    fn touch_liveness(&self) {
        let mut state = self.state.borrow_mut();
        if state.stage != Stage::Open {
            state.liveness = None;
            return;
        }
        let weak = self.this.clone();
        state.liveness = Some(TimerHandle::start(LIVENESS_TIMEOUT, move || {
            if let Some(channel) = weak.upgrade() {
                channel.fail(Failure::Disconnected);
            }
        }));
    }
}
