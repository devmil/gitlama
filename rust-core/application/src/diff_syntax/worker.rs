//! The one low-priority syntax worker: bounded admission, deduplication, retirement and
//! cancellation. Admission and retirement only take this module's own lock briefly; nothing
//! here waits while a session lock is held, and retiring work never waits for it to stop.
use super::{
    priority, Engine, Job, NativeDiffSyntaxOrigin, NativeDiffSyntaxRow, NativeSyntaxSideState,
    NativeTextSyntaxPage, TextJob, ViewKey,
};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

/// Requests waiting for the worker, across every view.
const QUEUED_REQUESTS: usize = 8;
/// Requests one view may have waiting; an older one is retired for a newer one.
const QUEUED_PER_VIEW: usize = 2;
/// Finished pages kept for a repeated demand (a caller that stopped waiting asks again).
const CACHED_RESULTS: usize = 64;
const CACHED_RESULT_BYTES: usize = 16 * 1024 * 1024;
/// Cancellations remembered for requests that have not arrived yet.
const REMEMBERED_CANCELLATIONS: usize = 64;
/// Source bytes queued and running text requests carry together; more waits for capacity.
const QUEUED_TEXT_BYTES: usize = 16 * 1024 * 1024;

type Rows = Arc<Vec<NativeDiffSyntaxRow>>;

/// What one request asks the worker for.
pub(crate) enum Work {
    Diff(Job),
    Text(TextJob),
}

/// What the worker answers one request with.
#[derive(Clone)]
enum Output {
    Rows(Rows),
    Text(Arc<NativeTextSyntaxPage>),
}

/// Whose requests queue, retire and cancel together.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum Owner {
    Diff(ViewKey),
    /// A caller-held text's view.
    Text(u64),
}

/// What became of an admitted text request.
pub(crate) enum TextAdmission {
    Ready(Arc<NativeTextSyntaxPage>),
    /// No lines now: the whole text shows plain for this reason.
    Plain(NativeSyntaxSideState),
    Canceled,
    Conflict,
}

/// What became of an admitted request.
pub(crate) enum Admission {
    /// The rows, one per requested row, in order.
    Ready(Rows),
    /// No rows now: every side shows plain text for this reason.
    Plain(NativeSyntaxSideState),
    /// The caller canceled this request before it ran.
    Canceled,
    /// The request ID already names different rows of this view.
    Conflict,
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
struct JobKey {
    view: Owner,
    offset: u64,
    count: usize,
}

struct Pending {
    key: JobKey,
    syntax_request_id: u64,
    job: Work,
    cancellation: Arc<AtomicBool>,
    replies: Vec<SyncSender<Output>>,
}

struct Active {
    key: JobKey,
    syntax_request_id: u64,
    cancellation: Arc<AtomicBool>,
    replies: Vec<SyncSender<Output>>,
    text_bytes: usize,
}

fn text_bytes(work: &Work) -> usize {
    match work {
        Work::Diff(_) => 0,
        Work::Text(job) => job.source.len(),
    }
}

#[derive(Default)]
struct State {
    started: bool,
    unavailable: bool,
    pending: VecDeque<Pending>,
    active: Option<Active>,
    results: HashMap<JobKey, (Rows, u64, usize)>,
    result_bytes: usize,
    clock: u64,
    canceled: VecDeque<(Owner, u64)>,
}

impl State {
    fn queued_text_bytes(&self) -> usize {
        self.pending
            .iter()
            .map(|pending| text_bytes(&pending.job))
            .sum::<usize>()
            + self.active.as_ref().map_or(0, |active| active.text_bytes)
    }
}

struct Worker {
    state: Mutex<State>,
    ready: Condvar,
}

static WORKER: OnceLock<Worker> = OnceLock::new();

fn worker() -> &'static Worker {
    WORKER.get_or_init(|| Worker {
        state: Mutex::new(State::default()),
        ready: Condvar::new(),
    })
}

fn lock() -> MutexGuard<'static, State> {
    worker()
        .state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Admits `job` and waits at most `wait` for its rows. A request still running when the wait
/// ends keeps running; its rows answer the next identical request.
pub(crate) fn submit(job: Job, wait: Duration) -> Admission {
    let key = JobKey {
        view: Owner::Diff(job.view),
        offset: job.offset,
        count: job.rows.len(),
    };
    let request = job.syntax_request_id;
    let receiver = match admit(Work::Diff(job), key, request) {
        Ok(receiver) => receiver,
        Err(Refusal::Cached(Output::Rows(rows))) => return Admission::Ready(rows),
        Err(Refusal::Plain(state)) => return Admission::Plain(state),
        Err(Refusal::Canceled) => return Admission::Canceled,
        Err(Refusal::Conflict | Refusal::Cached(Output::Text(_))) => return Admission::Conflict,
    };
    match receiver.recv_timeout(wait) {
        Ok(Output::Rows(rows)) => Admission::Ready(rows),
        Ok(Output::Text(_)) | Err(_) => Admission::Plain(NativeSyntaxSideState::Deferred),
    }
}

/// Admits a text request and waits at most `wait` for its lines. Text results are not cached:
/// a repeated request resumes from the parser's checkpoints instead.
pub(crate) fn submit_text(job: TextJob, wait: Duration) -> TextAdmission {
    let key = JobKey {
        view: Owner::Text(job.view_id),
        offset: u64::from(job.first_line),
        count: job.maximum_lines as usize,
    };
    let request = job.syntax_request_id;
    let receiver = match admit(Work::Text(job), key, request) {
        Ok(receiver) => receiver,
        Err(Refusal::Plain(state)) => return TextAdmission::Plain(state),
        Err(Refusal::Canceled) => return TextAdmission::Canceled,
        Err(Refusal::Conflict | Refusal::Cached(_)) => return TextAdmission::Conflict,
    };
    match receiver.recv_timeout(wait) {
        Ok(Output::Text(page)) => TextAdmission::Ready(page),
        Ok(Output::Rows(_)) | Err(_) => TextAdmission::Plain(NativeSyntaxSideState::Deferred),
    }
}

enum Refusal {
    Cached(Output),
    Plain(NativeSyntaxSideState),
    Canceled,
    Conflict,
}

fn admit(job: Work, key: JobKey, request: u64) -> Result<Receiver<Output>, Refusal> {
    let mut state = lock();
    if !state.started {
        state.started = true;
        let spawned = std::thread::Builder::new()
            .name("gitlama-diff-syntax".to_owned())
            .spawn(run);
        if spawned.is_err() {
            state.unavailable = true;
        }
    }
    if state.unavailable {
        return Err(Refusal::Plain(NativeSyntaxSideState::Unavailable));
    }
    if state.canceled.contains(&(key.view, request)) {
        return Err(Refusal::Canceled);
    }
    let conflicting = state
        .pending
        .iter()
        .map(|pending| (pending.key, pending.syntax_request_id))
        .chain(
            state
                .active
                .as_ref()
                .map(|active| (active.key, active.syntax_request_id)),
        )
        .any(|(other, id)| other.view == key.view && id == request && other != key);
    if conflicting {
        return Err(Refusal::Conflict);
    }
    state.clock += 1;
    let clock = state.clock;
    if let Some((rows, used, _)) = state.results.get_mut(&key) {
        *used = clock;
        return Err(Refusal::Cached(Output::Rows(Arc::clone(rows))));
    }
    let (sender, receiver) = mpsc::sync_channel(1);
    if let Some(active) = state.active.as_mut().filter(|active| active.key == key) {
        active.replies.push(sender);
        return Ok(receiver);
    }
    if let Some(pending) = state.pending.iter_mut().find(|pending| pending.key == key) {
        pending.replies.push(sender);
        return Ok(receiver);
    }
    // Newer demand of a view supersedes its older queued requests, and the queue as a whole.
    while state
        .pending
        .iter()
        .filter(|pending| pending.key.view == key.view)
        .count()
        >= QUEUED_PER_VIEW
    {
        let index = state
            .pending
            .iter()
            .position(|pending| pending.key.view == key.view)
            .expect("counted above");
        retire_pending(&mut state, index);
    }
    while state.pending.len() >= QUEUED_REQUESTS {
        retire_pending(&mut state, 0);
    }
    if text_bytes(&job) > 0 && state.queued_text_bytes() + text_bytes(&job) > QUEUED_TEXT_BYTES {
        return Err(Refusal::Plain(NativeSyntaxSideState::Deferred));
    }
    state.pending.push_back(Pending {
        key,
        syntax_request_id: request,
        job,
        cancellation: Arc::new(AtomicBool::new(false)),
        replies: vec![sender],
    });
    drop(state);
    worker().ready.notify_one();
    Ok(receiver)
}

/// Drops a queued request: its waiters see a disconnect and answer deferred.
fn retire_pending(state: &mut State, index: usize) {
    if let Some(pending) = state.pending.remove(index) {
        pending.cancellation.store(true, Ordering::Release);
    }
}

/// Cancels one request. Idempotent; a cancellation that arrives first is remembered so the
/// request cannot run later.
pub(crate) fn cancel(view: Owner, syntax_request_id: u64) -> bool {
    let mut state = lock();
    if let Some(index) = state.pending.iter().position(|pending| {
        pending.key.view == view && pending.syntax_request_id == syntax_request_id
    }) {
        retire_pending(&mut state, index);
        return true;
    }
    if let Some(active) = state
        .active
        .as_ref()
        .filter(|active| active.key.view == view && active.syntax_request_id == syntax_request_id)
    {
        active.cancellation.store(true, Ordering::Release);
        return true;
    }
    if !state.canceled.contains(&(view, syntax_request_id)) {
        if state.canceled.len() >= REMEMBERED_CANCELLATIONS {
            state.canceled.pop_front();
        }
        state.canceled.push_back((view, syntax_request_id));
    }
    true
}

/// Retires every request of a session's `origin` projection other than `current`: a new diff
/// replaced it. Never waits for running work.
pub(crate) fn retire_view(session_id: u64, origin: NativeDiffSyntaxOrigin, current: u64) {
    retire(|owner| {
        matches!(owner, Owner::Diff(view) if view.session_id == session_id
            && view.origin == origin
            && view.diff_request_id != current)
    });
}

/// Retires every request of a closed session.
pub(crate) fn cancel_session(session_id: u64) {
    retire(|owner| matches!(owner, Owner::Diff(view) if view.session_id == session_id));
}

fn retire(matches: impl Fn(&Owner) -> bool) {
    let Some(worker) = WORKER.get() else {
        return;
    };
    let mut state = worker
        .state
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let mut index = 0;
    while index < state.pending.len() {
        if matches(&state.pending[index].key.view) {
            retire_pending(&mut state, index);
        } else {
            index += 1;
        }
    }
    if let Some(active) = state
        .active
        .as_ref()
        .filter(|active| matches(&active.key.view))
    {
        active.cancellation.store(true, Ordering::Release);
    }
    let stale = state
        .results
        .keys()
        .filter(|key| matches(&key.view))
        .copied()
        .collect::<Vec<_>>();
    for key in stale {
        if let Some((_, _, bytes)) = state.results.remove(&key) {
            state.result_bytes -= bytes;
        }
    }
    state.canceled.retain(|(view, _)| !matches(view));
}

/// The worker thread: lowers its priority first and refuses all work when it cannot.
fn run() {
    if !priority::lower_current_thread() {
        let mut state = lock();
        state.unavailable = true;
        state.pending.clear();
        return;
    }
    let mut engine = Engine::new();
    loop {
        let (job, cancellation, key) = {
            let mut state = lock();
            let pending = loop {
                if let Some(pending) = state.pending.pop_front() {
                    break pending;
                }
                state = worker()
                    .ready
                    .wait(state)
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
            };
            state.active = Some(Active {
                key: pending.key,
                syntax_request_id: pending.syntax_request_id,
                cancellation: Arc::clone(&pending.cancellation),
                replies: pending.replies,
                text_bytes: text_bytes(&pending.job),
            });
            (pending.job, pending.cancellation, pending.key)
        };
        let rows = if cancellation.load(Ordering::Acquire) {
            None
        } else {
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match &job {
                Work::Diff(job) => Output::Rows(Arc::new(engine.run(job, &cancellation))),
                Work::Text(job) => Output::Text(Arc::new(engine.run_text(job, &cancellation))),
            }));
            Some(outcome.unwrap_or_else(|_| {
                engine = Engine::new();
                match &job {
                    Work::Diff(job) => Output::Rows(Arc::new(plain_rows(
                        job,
                        NativeSyntaxSideState::Unavailable,
                    ))),
                    Work::Text(job) => {
                        Output::Text(Arc::new(job.plain(NativeSyntaxSideState::Unavailable)))
                    }
                }
            }))
        };
        // Sources and documents are released before the next job is taken.
        drop(job);
        let mut state = lock();
        let replies = state
            .active
            .take()
            .map(|active| active.replies)
            .unwrap_or_default();
        let (Some(output), false) = (rows, cancellation.load(Ordering::Acquire)) else {
            continue;
        };
        for reply in replies {
            let _ = reply.try_send(output.clone());
        }
        if let Output::Rows(rows) = output {
            remember(&mut state, key, rows);
        }
    }
}

fn plain_rows(job: &Job, state: NativeSyntaxSideState) -> Vec<NativeDiffSyntaxRow> {
    job.rows
        .iter()
        .map(|row| NativeDiffSyntaxRow {
            stable_id: row.stable_id.clone(),
            old_state: state,
            new_state: state,
            old_spans: Vec::new(),
            new_spans: Vec::new(),
        })
        .collect()
}

fn remember(state: &mut State, key: JobKey, rows: Rows) {
    // Deferred rows are transient; only settled pages answer a repeated demand.
    if rows.iter().any(|row| {
        row.old_state == NativeSyntaxSideState::Deferred
            || row.new_state == NativeSyntaxSideState::Deferred
    }) {
        return;
    }
    let bytes = rows
        .iter()
        .map(|row| row.stable_id.len() + (row.old_spans.len() + row.new_spans.len()) * 12 + 32)
        .sum::<usize>();
    while !state.results.is_empty()
        && (state.results.len() >= CACHED_RESULTS
            || state.result_bytes + bytes > CACHED_RESULT_BYTES)
    {
        let Some(oldest) = state
            .results
            .iter()
            .min_by_key(|(_, (_, used, _))| *used)
            .map(|(key, _)| *key)
        else {
            break;
        };
        if let Some((_, _, removed)) = state.results.remove(&oldest) {
            state.result_bytes -= removed;
        }
    }
    state.clock += 1;
    state.result_bytes += bytes;
    let clock = state.clock;
    state.results.insert(key, (rows, clock, bytes));
}
