//! Messages for the status bar and failure dialogs, and other one-shot window events.

use crate::notify::{Notifier, Topics};
use serde_json::Value;
use std::cell::RefCell;

/// A one-shot event for the window.
#[derive(Clone, Debug, PartialEq)]
pub enum Notice {
    /// A status bar message: `key` names the localized text, `args` fill it.
    /// An error also opens the failure dialog.
    Status {
        key: String,
        args: Value,
        error: bool,
    },
}

#[derive(Default)]
pub struct Notices {
    queue: RefCell<Vec<Notice>>,
    notifier: Notifier,
}

impl Notices {
    pub fn new(notifier: Notifier) -> Self {
        Self {
            queue: RefCell::new(Vec::new()),
            notifier,
        }
    }

    pub fn status(&self, key: &str, args: Value) {
        self.push(Notice::Status {
            key: key.to_owned(),
            args,
            error: false,
        });
    }

    pub fn error(&self, key: &str, args: Value) {
        self.push(Notice::Status {
            key: key.to_owned(),
            args,
            error: true,
        });
    }

    pub fn push(&self, notice: Notice) {
        self.queue.borrow_mut().push(notice);
        self.notifier.notify(Topics::EVENTS);
    }

    pub fn take(&self) -> Vec<Notice> {
        std::mem::take(&mut *self.queue.borrow_mut())
    }
}
