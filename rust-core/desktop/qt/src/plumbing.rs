//! The pump's two inputs: QML commands and wake-ups.
//!
//! Slots never act synchronously: they post a command to the [`Commands`]
//! queue and return, so no QML binding re-enters a borrowed bridge object.
//! Any thread may [`PumpWaker::notify`]; at most one pump call is queued at a
//! time.

use qtbridge::{QmlMethodInvoker, invoke_method};
use std::cell::RefCell;
use std::collections::VecDeque;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

/// A command from QML, handled by the driver on the next pump.
pub type Command = Box<dyn FnOnce(&crate::driver::Driver) + 'static>;

/// Queues a pump call on the GUI thread; shared with every thread.
pub struct PumpWaker {
    queued: AtomicBool,
    invoker: Mutex<Option<QmlMethodInvoker>>,
}

impl PumpWaker {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            queued: AtomicBool::new(false),
            invoker: Mutex::new(None),
        })
    }

    /// Connects the waker to the pump and pumps once.
    pub fn bind(&self, invoker: QmlMethodInvoker) {
        if let Ok(mut slot) = self.invoker.lock() {
            *slot = Some(invoker);
        }
        self.queued.store(false, Ordering::Release);
        self.notify();
    }

    /// Detaches the pump at shutdown; later wake-ups are ignored.
    pub fn unbind(&self) {
        if let Ok(mut slot) = self.invoker.lock() {
            *slot = None;
        }
    }

    pub(crate) fn begin_pump(&self) {
        self.queued.store(false, Ordering::Release);
    }

    pub fn notify(&self) {
        if self.queued.swap(true, Ordering::AcqRel) {
            return;
        }
        let invoked = self
            .invoker
            .lock()
            .ok()
            .and_then(|invoker| {
                invoker
                    .as_ref()
                    .map(|invoker| invoke_method!(invoker, "pump"))
            })
            .unwrap_or(false);
        if !invoked {
            self.queued.store(false, Ordering::Release);
        }
    }
}

/// QML's commands, on the GUI thread.
#[derive(Clone)]
pub struct Commands {
    queue: Rc<RefCell<VecDeque<Command>>>,
    waker: Arc<PumpWaker>,
}

impl Commands {
    pub fn new(waker: Arc<PumpWaker>) -> Self {
        Self {
            queue: Rc::new(RefCell::new(VecDeque::new())),
            waker,
        }
    }

    /// Queues `command` for the next pump.
    pub fn post(&self, command: impl FnOnce(&crate::driver::Driver) + 'static) {
        self.queue.borrow_mut().push_back(Box::new(command));
        self.waker.notify();
    }

    pub(crate) fn take(&self) -> Vec<Command> {
        self.queue.borrow_mut().drain(..).collect()
    }
}
