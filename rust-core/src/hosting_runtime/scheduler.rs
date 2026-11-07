//! The bounded worker pool every hosting request runs on.
#![allow(clippy::wildcard_imports)]
use super::*;

pub(super) struct ScheduledTask {
    pub(super) connection_id: String,
    pub(super) cancellation: Arc<AtomicBool>,
    pub(super) operation: Box<dyn FnOnce(Arc<AtomicBool>) + Send>,
}

#[derive(Default)]
pub(super) struct SchedulerState {
    pub(super) queue: VecDeque<ScheduledTask>,
    pub(super) active_connections: HashMap<String, Arc<AtomicBool>>,
    pub(super) shutdown: bool,
}

pub(super) struct SchedulerShared {
    pub(super) state: Mutex<SchedulerState>,
    pub(super) changed: Condvar,
}

pub(super) struct BoundedScheduler {
    pub(super) shared: Arc<SchedulerShared>,
    pub(super) workers: Vec<JoinHandle<()>>,
}

impl BoundedScheduler {
    pub(super) fn new() -> Self {
        let shared = Arc::new(SchedulerShared {
            state: Mutex::new(SchedulerState::default()),
            changed: Condvar::new(),
        });
        let workers = (0..GLOBAL_REQUEST_LIMIT)
            .map(|_| {
                let shared = Arc::clone(&shared);
                thread::spawn(move || worker_loop(&shared))
            })
            .collect();
        Self { shared, workers }
    }

    pub(super) fn schedule(&self, task: ScheduledTask) -> bool {
        let mut state = self.shared.state.lock().expect("hosting scheduler lock");
        if state.shutdown {
            return false;
        }
        state.queue.push_back(task);
        self.shared.changed.notify_all();
        true
    }

    pub(super) fn stop(mut self) {
        {
            let mut state = self.shared.state.lock().expect("hosting scheduler lock");
            state.shutdown = true;
            for task in &state.queue {
                task.cancellation.store(true, Ordering::Release);
            }
            for cancellation in state.active_connections.values() {
                cancellation.store(true, Ordering::Release);
            }
            self.shared.changed.notify_all();
        }
        for worker in self.workers.drain(..) {
            let _ = worker.join();
        }
    }
}

pub(super) fn worker_loop(shared: &SchedulerShared) {
    loop {
        let task =
            {
                let mut state = shared.state.lock().expect("hosting scheduler lock");
                loop {
                    if state.shutdown && state.queue.is_empty() {
                        return;
                    }
                    if let Some(index) = state.queue.iter().position(|task| {
                        !state.active_connections.contains_key(&task.connection_id)
                    }) {
                        let task = state.queue.remove(index).expect("queued hosting task");
                        state
                            .active_connections
                            .insert(task.connection_id.clone(), Arc::clone(&task.cancellation));
                        break task;
                    }
                    state = shared.changed.wait(state).expect("hosting scheduler wait");
                }
            };
        let connection_id = task.connection_id.clone();
        (task.operation)(Arc::clone(&task.cancellation));
        let mut state = shared.state.lock().expect("hosting scheduler lock");
        state.active_connections.remove(&connection_id);
        shared.changed.notify_all();
    }
}
