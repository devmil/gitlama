//! Questions workflows ask the window (the Dart `WorkflowInteraction`
//! callbacks): a workflow awaits [`Prompts::ask`]; the window shows the
//! dialog the prompt's kind names and answers with [`Prompts::answer`].

use crate::notify::{Notifier, Topics};
use futures::channel::oneshot;
use serde_json::Value;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;

/// One open question.
#[derive(Clone, Debug, PartialEq)]
pub struct Prompt {
    pub id: u64,
    /// The dialog to show, such as `chooseDirectory` or `cloneSource`.
    pub kind: &'static str,
    pub payload: Value,
}

#[derive(Default)]
pub struct Prompts {
    next: Cell<u64>,
    pending: RefCell<HashMap<u64, oneshot::Sender<Option<Value>>>>,
    fresh: RefCell<Vec<Prompt>>,
    notifier: Notifier,
}

impl Prompts {
    pub fn new(notifier: Notifier) -> Self {
        Self {
            notifier,
            ..Self::default()
        }
    }

    /// Asks the window; None when the user canceled or the window could not
    /// show the question.
    pub async fn ask(&self, kind: &'static str, payload: Value) -> Option<Value> {
        let id = self.next.get() + 1;
        self.next.set(id);
        let (sender, receiver) = oneshot::channel();
        self.pending.borrow_mut().insert(id, sender);
        self.fresh.borrow_mut().push(Prompt { id, kind, payload });
        self.notifier.notify(Topics::EVENTS);
        receiver.await.ok().flatten()
    }

    /// Answers prompt `id`; an unknown or answered prompt is ignored.
    pub fn answer(&self, id: u64, value: Option<Value>) {
        if let Some(sender) = self.pending.borrow_mut().remove(&id) {
            let _ = sender.send(value);
        }
    }

    /// The prompts asked since the last call.
    pub fn take_fresh(&self) -> Vec<Prompt> {
        std::mem::take(&mut *self.fresh.borrow_mut())
    }

    /// Cancels every open prompt, as when the window closes.
    pub fn cancel_all(&self) {
        for (_, sender) in self.pending.borrow_mut().drain() {
            let _ = sender.send(None);
        }
    }
}
