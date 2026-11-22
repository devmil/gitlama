//! Background fetches at the interval the settings choose, while an open
//! repository wants them (the Dart AutoFetchScheduler). Remote repositories
//! never fetch in the background: they would use the host's credentials
//! unasked.

use std::cell::{Cell, RefCell};
use std::rc::{Rc, Weak};
use std::time::Duration;

use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::storage::{NativeRepositoryOptions, NativeSettingsDocument};

use crate::rt::{self, TimerHandle};
use crate::settings::SettingsService;
use crate::transfers::TransferService;
use crate::workspace::WorkspaceService;

/// Whether `repository` is fetched in the background: its own override, or
/// the application's choice.
pub fn auto_fetches(document: &NativeSettingsDocument, repository: &NativePathIdentity) -> bool {
    repository.remote.is_none() && auto_fetch_override(document, repository).unwrap_or(document.auto_fetch.enabled)
}

/// The override stored for `repository`; None follows the application.
pub fn auto_fetch_override(document: &NativeSettingsDocument, repository: &NativePathIdentity) -> Option<bool> {
    document
        .repository_options
        .iter()
        .find(|options| &options.identity == repository)
        .and_then(|options| options.auto_fetch)
}

/// `document` with `repository` overriding automatic fetching, or following
/// the application again when `value` is None.
pub fn set_auto_fetch_override(document: &mut NativeSettingsDocument, repository: &NativePathIdentity, value: Option<bool>) {
    document.repository_options.retain(|options| &options.identity != repository);
    if let Some(value) = value {
        document.repository_options.push(NativeRepositoryOptions {
            identity: repository.clone(),
            auto_fetch: Some(value),
        });
    }
}

pub struct AutoFetchScheduler {
    this: Weak<Self>,
    settings: Rc<SettingsService>,
    workspace: Rc<WorkspaceService>,
    transfers: Rc<TransferService>,
    timer: RefCell<TimerHandle>,
    minutes: Cell<Option<u32>>,
    running: Cell<bool>,
    disposed: Cell<bool>,
}

impl AutoFetchScheduler {
    pub fn new(settings: Rc<SettingsService>, workspace: Rc<WorkspaceService>, transfers: Rc<TransferService>) -> Rc<Self> {
        Rc::new_cyclic(|this| Self {
            this: this.clone(),
            settings,
            workspace,
            transfers,
            timer: RefCell::new(TimerHandle::default()),
            minutes: Cell::new(None),
            running: Cell::new(false),
            disposed: Cell::new(false),
        })
    }

    fn wanted(&self) -> bool {
        self.settings.with(|document| {
            self.workspace
                .open_sessions()
                .iter()
                .any(|(_, canonical, _)| auto_fetches(document, canonical))
        })
    }

    /// Starts, retimes or stops the timer for the open repositories. Cheap:
    /// call it whenever settings or the workspace change.
    pub fn sync(&self) {
        if self.disposed.get() {
            return;
        }
        if !self.wanted() {
            self.timer.borrow_mut().cancel();
            self.minutes.set(None);
            return;
        }
        let minutes = self.settings.with(|document| document.auto_fetch.interval_minutes).max(1);
        if self.minutes.get() == Some(minutes) && self.timer.borrow().is_active() {
            return;
        }
        self.minutes.set(Some(minutes));
        self.schedule(minutes);
    }

    fn schedule(&self, minutes: u32) {
        let weak = self.this.clone();
        *self.timer.borrow_mut() = TimerHandle::start(Duration::from_secs(u64::from(minutes) * 60), move || {
            let Some(scheduler) = weak.upgrade() else { return };
            scheduler.schedule(minutes);
            rt::spawn_detached(async move { scheduler.run().await });
        });
    }

    /// Fetches every open repository that wants it, one after another.
    pub async fn run(&self) {
        if self.running.get() || self.disposed.get() {
            return;
        }
        self.running.set(true);
        for (identity, canonical, snapshot) in self.workspace.open_sessions() {
            if self.disposed.get() {
                break;
            }
            if snapshot.refs.remotes.is_empty() || !self.settings.with(|document| auto_fetches(document, &canonical)) {
                continue;
            }
            self.transfers.background_fetch(identity).await;
        }
        self.running.set(false);
    }

    pub fn dispose(&self) {
        self.disposed.set(true);
        self.timer.borrow_mut().cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::domain::path_identity::{NativePathPlatform, NativeRemoteAuthority};

    fn path(name: &str) -> NativePathIdentity {
        NativePathIdentity { platform: NativePathPlatform::Unix, units: name.encode_utf16().collect(), remote: None }
    }

    #[test]
    fn an_override_wins_over_the_application_and_clears_back_to_it() {
        let mut document = NativeSettingsDocument::default();
        let repository = path("/a");
        assert!(auto_fetches(&document, &repository));
        set_auto_fetch_override(&mut document, &repository, Some(false));
        assert_eq!(auto_fetch_override(&document, &repository), Some(false));
        assert!(!auto_fetches(&document, &repository));
        document.auto_fetch.enabled = false;
        set_auto_fetch_override(&mut document, &repository, Some(true));
        assert!(auto_fetches(&document, &repository));
        assert_eq!(document.repository_options.len(), 1);
        set_auto_fetch_override(&mut document, &repository, None);
        assert!(document.repository_options.is_empty());
        assert!(!auto_fetches(&document, &repository));
    }

    #[test]
    fn a_remote_repository_never_fetches_in_the_background() {
        let document = NativeSettingsDocument::default();
        let mut repository = path("/a");
        repository.remote = Some(NativeRemoteAuthority { profile_id: "p".into(), store_id: "s".into(), account_uid: "1".into() });
        assert!(!auto_fetches(&document, &repository));
    }
}
