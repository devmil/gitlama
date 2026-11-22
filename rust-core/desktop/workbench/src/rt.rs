//! The workbench's single-threaded async runtime.
//!
//! Services are `!Send` state machines that live on the GUI thread, like the
//! Dart services they replace lived on the Dart event loop. Their async
//! functions run as local tasks; blocking native work (Git, files, network)
//! runs on the blocking pool and wakes its task when it finishes. The host
//! polls ready tasks with [`Runtime::run_until_stalled`] whenever the wake
//! hook fires, and publishes the services' state after each poll.
//!
//! Rules: never hold a `RefCell` borrow across an `.await`, and never block
//! inside a task; use [`blocking`] for anything that can take time.

use futures::channel::oneshot;
use std::cell::RefCell;
use std::collections::{BinaryHeap, HashMap, VecDeque};
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::task::{Context, Poll, Wake, Waker};
use std::thread;
use std::time::{Duration, Instant};

type LocalTask = Pin<Box<dyn Future<Output = ()>>>;

/// Called from any thread when a task became ready; the host schedules a poll.
pub type WakeHook = Arc<dyn Fn() + Send + Sync>;

struct ReadyQueue {
    ready: Mutex<VecDeque<u64>>,
    hook: Mutex<Option<WakeHook>>,
}

impl ReadyQueue {
    fn push(&self, id: u64) {
        if let Ok(mut ready) = self.ready.lock() {
            ready.push_back(id);
        }
        let hook = self.hook.lock().ok().and_then(|hook| hook.clone());
        if let Some(hook) = hook {
            hook();
        }
    }
}

struct TaskWaker {
    id: u64,
    queue: Arc<ReadyQueue>,
}

impl Wake for TaskWaker {
    fn wake(self: Arc<Self>) {
        self.queue.push(self.id);
    }

    fn wake_by_ref(self: &Arc<Self>) {
        self.queue.push(self.id);
    }
}

struct RuntimeInner {
    tasks: RefCell<HashMap<u64, LocalTask>>,
    spawned: RefCell<Vec<(u64, LocalTask)>>,
    next: std::cell::Cell<u64>,
    queue: Arc<ReadyQueue>,
}

thread_local! {
    static CURRENT: RefCell<Option<Rc<RuntimeInner>>> = const { RefCell::new(None) };
}

/// The GUI thread's task runtime. One per thread; [`spawn`] reaches it.
pub struct Runtime {
    inner: Rc<RuntimeInner>,
}

impl Runtime {
    /// Installs a runtime on the current thread.
    pub fn install() -> Self {
        let inner = Rc::new(RuntimeInner {
            tasks: RefCell::new(HashMap::new()),
            spawned: RefCell::new(Vec::new()),
            next: std::cell::Cell::new(1),
            queue: Arc::new(ReadyQueue {
                ready: Mutex::new(VecDeque::new()),
                hook: Mutex::new(None),
            }),
        });
        CURRENT.with(|current| *current.borrow_mut() = Some(Rc::clone(&inner)));
        Self { inner }
    }

    /// Sets the hook that asks the host for a poll.
    pub fn set_wake_hook(&self, hook: WakeHook) {
        if let Ok(mut slot) = self.inner.queue.hook.lock() {
            *slot = Some(hook);
        }
    }

    /// Polls every ready task until none is ready. Returns the number of polls.
    pub fn run_until_stalled(&self) -> usize {
        let mut polls = 0;
        loop {
            self.adopt_spawned();
            let next = self
                .inner
                .queue
                .ready
                .lock()
                .ok()
                .and_then(|mut ready| ready.pop_front());
            let Some(id) = next else {
                if self.inner.spawned.borrow().is_empty() {
                    return polls;
                }
                continue;
            };
            let task = self.inner.tasks.borrow_mut().remove(&id);
            let Some(mut task) = task else {
                continue;
            };
            let waker = Waker::from(Arc::new(TaskWaker {
                id,
                queue: Arc::clone(&self.inner.queue),
            }));
            let mut context = Context::from_waker(&waker);
            polls += 1;
            if task.as_mut().poll(&mut context).is_pending() {
                self.inner.tasks.borrow_mut().insert(id, task);
            }
        }
    }

    fn adopt_spawned(&self) {
        let spawned = std::mem::take(&mut *self.inner.spawned.borrow_mut());
        if spawned.is_empty() {
            return;
        }
        let mut tasks = self.inner.tasks.borrow_mut();
        let mut ready = self.inner.queue.ready.lock().ok();
        for (id, task) in spawned {
            tasks.insert(id, task);
            if let Some(ready) = ready.as_mut() {
                ready.push_back(id);
            }
        }
    }

    /// Tasks that have not finished.
    pub fn pending_tasks(&self) -> usize {
        self.inner.tasks.borrow().len() + self.inner.spawned.borrow().len()
    }

    /// Drops every unfinished task; their futures never complete.
    pub fn shutdown(&self) {
        self.inner.spawned.borrow_mut().clear();
        let tasks = std::mem::take(&mut *self.inner.tasks.borrow_mut());
        drop(tasks);
    }
}

impl Drop for Runtime {
    fn drop(&mut self) {
        self.shutdown();
        CURRENT.with(|current| {
            let mut current = current.borrow_mut();
            if current
                .as_ref()
                .is_some_and(|installed| Rc::ptr_eq(installed, &self.inner))
            {
                *current = None;
            }
        });
    }
}

/// The result of a spawned task. Dropping it does not cancel the task.
pub struct JoinHandle<T> {
    receiver: oneshot::Receiver<T>,
}

impl<T> Future for JoinHandle<T> {
    type Output = Option<T>;

    fn poll(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Option<T>> {
        Pin::new(&mut self.receiver)
            .poll(context)
            .map(Result::ok)
    }
}

/// Spawns `future` on the current thread's runtime. Without a runtime (a
/// test that forgot to install one) it panics.
pub fn spawn<T: 'static>(future: impl Future<Output = T> + 'static) -> JoinHandle<T> {
    let (sender, receiver) = oneshot::channel();
    let task: LocalTask = Box::pin(async move {
        let value = future.await;
        let _ = sender.send(value);
    });
    CURRENT.with(|current| {
        let current = current.borrow();
        let inner = current.as_ref().expect("no workbench runtime on this thread");
        let id = inner.next.get();
        inner.next.set(id + 1);
        inner.spawned.borrow_mut().push((id, task));
        let hook = inner.queue.hook.lock().ok().and_then(|hook| hook.clone());
        if let Some(hook) = hook {
            hook();
        }
    });
    JoinHandle { receiver }
}

/// Spawns `future` and forgets its result.
pub fn spawn_detached(future: impl Future<Output = ()> + 'static) {
    drop(spawn(future));
}

// The blocking pool -----------------------------------------------------------

type BlockingJob = Box<dyn FnOnce() + Send>;

struct BlockingPool {
    state: Mutex<BlockingState>,
    signal: Condvar,
}

#[derive(Default)]
struct BlockingState {
    jobs: VecDeque<BlockingJob>,
    idle: usize,
    threads: usize,
}

/// More than enough for every concurrent Git command the workbench starts;
/// beyond it jobs queue.
const MAX_BLOCKING_THREADS: usize = 64;
const BLOCKING_IDLE: Duration = Duration::from_secs(10);
static BLOCKING_NAMES: AtomicUsize = AtomicUsize::new(0);

fn blocking_pool() -> &'static Arc<BlockingPool> {
    static POOL: OnceLock<Arc<BlockingPool>> = OnceLock::new();
    POOL.get_or_init(|| {
        Arc::new(BlockingPool {
            state: Mutex::new(BlockingState::default()),
            signal: Condvar::new(),
        })
    })
}

fn submit_blocking(job: BlockingJob) {
    let pool = blocking_pool();
    let Ok(mut state) = pool.state.lock() else {
        return;
    };
    state.jobs.push_back(job);
    if state.idle > 0 {
        pool.signal.notify_one();
        return;
    }
    if state.threads >= MAX_BLOCKING_THREADS {
        return;
    }
    state.threads += 1;
    drop(state);
    let worker = Arc::clone(pool);
    let index = BLOCKING_NAMES.fetch_add(1, Ordering::Relaxed);
    let started = thread::Builder::new()
        .name(format!("gitlama-blocking-{index}"))
        .spawn(move || blocking_worker(&worker));
    if started.is_err()
        && let Ok(mut state) = pool.state.lock()
    {
        state.threads -= 1;
    }
}

fn blocking_worker(pool: &BlockingPool) {
    let Ok(mut state) = pool.state.lock() else {
        return;
    };
    loop {
        if let Some(job) = state.jobs.pop_front() {
            drop(state);
            // A panicking job must not take the worker down; its future
            // resolves as canceled.
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(job));
            state = match pool.state.lock() {
                Ok(state) => state,
                Err(_) => return,
            };
            continue;
        }
        state.idle += 1;
        let (next, timeout) = match pool.signal.wait_timeout(state, BLOCKING_IDLE) {
            Ok(result) => result,
            Err(_) => return,
        };
        state = next;
        state.idle -= 1;
        if timeout.timed_out() && state.jobs.is_empty() {
            state.threads -= 1;
            return;
        }
    }
}

/// Runs `work` on the blocking pool; the future resolves with its result.
///
/// # Panics
/// The future panics when `work` panicked, like an awaited Dart future that
/// failed with an unexpected error.
pub async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> T {
    let (sender, receiver) = oneshot::channel();
    submit_blocking(Box::new(move || {
        let _ = sender.send(work());
    }));
    receiver.await.expect("blocking work panicked")
}

/// Runs `work` on its own thread, for long-lived loops such as a reader.
pub fn spawn_thread(name: &str, work: impl FnOnce() + Send + 'static) {
    let _ = thread::Builder::new().name(name.to_owned()).spawn(work);
}

// Timers ------------------------------------------------------------------------

struct TimerEntry {
    at: Instant,
    sequence: u64,
    waker: Waker,
    fired: Arc<std::sync::atomic::AtomicBool>,
}

impl PartialEq for TimerEntry {
    fn eq(&self, other: &Self) -> bool {
        self.at == other.at && self.sequence == other.sequence
    }
}
impl Eq for TimerEntry {}
impl PartialOrd for TimerEntry {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for TimerEntry {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        // A min-heap on the deadline.
        other
            .at
            .cmp(&self.at)
            .then(other.sequence.cmp(&self.sequence))
    }
}

struct TimerWheel {
    heap: Mutex<(BinaryHeap<TimerEntry>, u64)>,
    signal: Condvar,
}

fn timers() -> &'static Arc<TimerWheel> {
    static TIMERS: OnceLock<Arc<TimerWheel>> = OnceLock::new();
    TIMERS.get_or_init(|| {
        let wheel = Arc::new(TimerWheel {
            heap: Mutex::new((BinaryHeap::new(), 0)),
            signal: Condvar::new(),
        });
        let worker = Arc::clone(&wheel);
        thread::Builder::new()
            .name("gitlama-timers".into())
            .spawn(move || timer_loop(&worker))
            .expect("start the timer thread");
        wheel
    })
}

fn timer_loop(wheel: &TimerWheel) {
    let Ok(mut guard) = wheel.heap.lock() else {
        return;
    };
    loop {
        let now = Instant::now();
        while guard.0.peek().is_some_and(|entry| entry.at <= now) {
            if let Some(entry) = guard.0.pop() {
                entry.fired.store(true, Ordering::Release);
                entry.waker.wake();
            }
        }
        let wait = guard.0.peek().map(|entry| entry.at - now);
        guard = match wait {
            Some(wait) => match wheel.signal.wait_timeout(guard, wait) {
                Ok((guard, _)) => guard,
                Err(_) => return,
            },
            None => match wheel.signal.wait(guard) {
                Ok(guard) => guard,
                Err(_) => return,
            },
        };
    }
}

/// Resolves after `duration`.
pub fn sleep(duration: Duration) -> Sleep {
    Sleep {
        at: Instant::now() + duration,
        fired: None,
    }
}

/// Resolves at `at`.
pub fn sleep_until(at: Instant) -> Sleep {
    Sleep { at, fired: None }
}

pub struct Sleep {
    at: Instant,
    fired: Option<Arc<std::sync::atomic::AtomicBool>>,
}

impl Future for Sleep {
    type Output = ();

    fn poll(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<()> {
        if Instant::now() >= self.at
            || self
                .fired
                .as_ref()
                .is_some_and(|fired| fired.load(Ordering::Acquire))
        {
            return Poll::Ready(());
        }
        let fired = Arc::new(std::sync::atomic::AtomicBool::new(false));
        self.fired = Some(Arc::clone(&fired));
        let wheel = timers();
        if let Ok(mut guard) = wheel.heap.lock() {
            guard.1 += 1;
            let sequence = guard.1;
            guard.0.push(TimerEntry {
                at: self.at,
                sequence,
                waker: context.waker().clone(),
                fired,
            });
            wheel.signal.notify_one();
        }
        Poll::Pending
    }
}

/// Runs `future` with a deadline; `None` when it took longer.
pub async fn timeout<T>(duration: Duration, future: impl Future<Output = T>) -> Option<T> {
    use futures::future::{Either, select};
    let future = std::pin::pin!(future);
    let sleeper = std::pin::pin!(sleep(duration));
    match select(future, sleeper).await {
        Either::Left((value, _)) => Some(value),
        Either::Right(((), _)) => None,
    }
}

// Cancelable delayed work ---------------------------------------------------------

/// A one-shot timer that runs a callback on the runtime unless canceled,
/// like a Dart `Timer`.
#[derive(Default)]
pub struct TimerHandle {
    canceled: Option<Rc<std::cell::Cell<bool>>>,
}

impl TimerHandle {
    /// Runs `callback` after `duration` unless [`cancel`](Self::cancel) runs first.
    pub fn start(duration: Duration, callback: impl FnOnce() + 'static) -> Self {
        let canceled = Rc::new(std::cell::Cell::new(false));
        let flag = Rc::clone(&canceled);
        spawn_detached(async move {
            sleep(duration).await;
            if !flag.get() {
                flag.set(true);
                callback();
            }
        });
        Self {
            canceled: Some(canceled),
        }
    }

    pub fn cancel(&mut self) {
        if let Some(canceled) = self.canceled.take() {
            canceled.set(true);
        }
    }

    /// Whether the timer is armed and has not fired.
    pub fn is_active(&self) -> bool {
        self.canceled.as_ref().is_some_and(|canceled| !canceled.get())
    }
}

impl Drop for TimerHandle {
    fn drop(&mut self) {
        self.cancel();
    }
}

/// A repeating timer, like `Timer.periodic`.
#[derive(Default)]
pub struct PeriodicHandle {
    canceled: Option<Rc<std::cell::Cell<bool>>>,
}

impl PeriodicHandle {
    pub fn start(period: Duration, mut callback: impl FnMut() + 'static) -> Self {
        let canceled = Rc::new(std::cell::Cell::new(false));
        let flag = Rc::clone(&canceled);
        spawn_detached(async move {
            let mut next = Instant::now() + period;
            loop {
                sleep_until(next).await;
                if flag.get() {
                    return;
                }
                callback();
                next += period;
                let now = Instant::now();
                if next < now {
                    next = now + period;
                }
            }
        });
        Self {
            canceled: Some(canceled),
        }
    }

    pub fn cancel(&mut self) {
        if let Some(canceled) = self.canceled.take() {
            canceled.set(true);
        }
    }

    pub fn is_active(&self) -> bool {
        self.canceled.as_ref().is_some_and(|canceled| !canceled.get())
    }
}

impl Drop for PeriodicHandle {
    fn drop(&mut self) {
        self.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    /// Polls until `done` or the deadline, sleeping briefly between polls.
    fn drive(runtime: &Runtime, done: impl Fn() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !done() && Instant::now() < deadline {
            runtime.run_until_stalled();
            thread::sleep(Duration::from_millis(1));
        }
    }

    #[test]
    fn a_task_awaits_blocking_work_and_a_timer() {
        let runtime = Runtime::install();
        let result = Rc::new(Cell::new(0));
        let out = Rc::clone(&result);
        spawn_detached(async move {
            let value = blocking(|| 40).await;
            sleep(Duration::from_millis(5)).await;
            out.set(value + 2);
        });
        drive(&runtime, || result.get() == 42);
        assert_eq!(result.get(), 42);
        assert_eq!(runtime.pending_tasks(), 0);
    }

    #[test]
    fn the_wake_hook_fires_when_work_completes() {
        let runtime = Runtime::install();
        let woken = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&woken);
        runtime.set_wake_hook(Arc::new(move || {
            counter.fetch_add(1, Ordering::Relaxed);
        }));
        let handle = spawn(async { blocking(|| 7).await });
        let result = Rc::new(Cell::new(None));
        let out = Rc::clone(&result);
        spawn_detached(async move { out.set(handle.await) });
        drive(&runtime, || result.get().is_some());
        assert_eq!(result.get(), Some(7));
        assert!(woken.load(Ordering::Relaxed) > 0);
    }

    #[test]
    fn a_canceled_timer_never_runs() {
        let runtime = Runtime::install();
        let ran = Rc::new(Cell::new(false));
        let flag = Rc::clone(&ran);
        let mut timer = TimerHandle::start(Duration::from_millis(5), move || flag.set(true));
        timer.cancel();
        let done = Rc::new(Cell::new(false));
        let finished = Rc::clone(&done);
        spawn_detached(async move {
            sleep(Duration::from_millis(20)).await;
            finished.set(true);
        });
        drive(&runtime, || done.get());
        assert!(!ran.get());
    }

    #[test]
    fn timeout_reports_slow_work() {
        let runtime = Runtime::install();
        let result = Rc::new(Cell::new(None));
        let out = Rc::clone(&result);
        spawn_detached(async move {
            let slow = timeout(Duration::from_millis(5), sleep(Duration::from_secs(5))).await;
            let fast = timeout(Duration::from_secs(5), async { 3 }).await;
            out.set(Some((slow.is_none(), fast)));
        });
        drive(&runtime, || result.get().is_some());
        assert_eq!(result.get(), Some((true, Some(3))));
    }
}
