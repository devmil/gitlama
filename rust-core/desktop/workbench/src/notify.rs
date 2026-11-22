//! Change notification from services to the presentation layer.

use std::cell::Cell;
use std::rc::Rc;

/// What changed since the presentation last projected the services.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Topics(pub u64);

impl Topics {
    pub const SETTINGS: Topics = Topics(1 << 0);
    pub const WORKSPACE: Topics = Topics(1 << 1);
    pub const SESSION: Topics = Topics(1 << 2);
    pub const HISTORY: Topics = Topics(1 << 3);
    pub const CHANGES: Topics = Topics(1 << 4);
    pub const DIFF: Topics = Topics(1 << 5);
    pub const INSPECTOR: Topics = Topics(1 << 6);
    pub const OPERATIONS: Topics = Topics(1 << 7);
    pub const REMOTE: Topics = Topics(1 << 8);
    pub const HOSTING: Topics = Topics(1 << 9);
    pub const UPDATES: Topics = Topics(1 << 10);
    pub const EVENTS: Topics = Topics(1 << 11);
    pub const STARTUP: Topics = Topics(1 << 12);
    pub const ALL: Topics = Topics(u64::MAX);

    pub fn contains(self, other: Topics) -> bool {
        self.0 & other.0 == other.0
    }

    pub fn intersects(self, other: Topics) -> bool {
        self.0 & other.0 != 0
    }

    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
}

impl std::ops::BitOr for Topics {
    type Output = Topics;
    fn bitor(self, other: Topics) -> Topics {
        Topics(self.0 | other.0)
    }
}

/// Collects changed topics; cheap to clone into every service.
#[derive(Clone, Default)]
pub struct Notifier {
    changed: Rc<Cell<u64>>,
}

impl Notifier {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn notify(&self, topics: Topics) {
        self.changed.set(self.changed.get() | topics.0);
    }

    /// The topics changed since the last call.
    pub fn take(&self) -> Topics {
        Topics(self.changed.replace(0))
    }

    pub fn peek(&self) -> Topics {
        Topics(self.changed.get())
    }
}
