//! Private, disposable per-repository entries on this computer: the repository view cache
//! and the hosting link cache, each in its own folder. Remote identities are never stored:
//! their paths may equal local ones, and fetched remote content never reaches the disk.

use crate::rt;
use gitlama_contract::domain::path_identity::NativePathIdentity;
use std::cell::OnceCell;
use std::path::Path;
use std::rc::Rc;

pub struct EntryStore {
    /// The folder beside the default `views` folder; `views` itself for the view cache.
    folder: &'static str,
    directory: OnceCell<Option<String>>,
}

impl EntryStore {
    #[must_use]
    pub fn new(folder: &'static str) -> Rc<Self> {
        Rc::new(Self {
            folder,
            directory: OnceCell::new(),
        })
    }

    async fn directory(&self) -> Option<String> {
        if let Some(known) = self.directory.get() {
            return known.clone();
        }
        let views = rt::blocking(gitlama_core::api::application_view_cache_default_directory).await;
        let resolved = views.and_then(|views| {
            if self.folder == "views" {
                return Some(views);
            }
            Path::new(&views)
                .parent()
                .map(|parent| parent.join(self.folder))
                .and_then(|path| path.into_os_string().into_string().ok())
        });
        let _ = self.directory.set(resolved.clone());
        resolved
    }

    /// The stored bytes; `None` when absent, unreadable or remote.
    pub async fn read(&self, repository: &NativePathIdentity) -> Option<Vec<u8>> {
        if repository.remote.is_some() {
            return None;
        }
        let directory = self.directory().await?;
        let identity = repository.clone();
        let result = rt::blocking(move || {
            gitlama_core::api::application_view_cache_read(directory, identity)
        })
        .await;
        result.failure.is_none().then_some(result.bytes).flatten()
    }

    /// Best effort: the next change writes again.
    pub async fn write(&self, repository: &NativePathIdentity, bytes: Vec<u8>) {
        if repository.remote.is_some() {
            return;
        }
        let Some(directory) = self.directory().await else {
            return;
        };
        let identity = repository.clone();
        rt::blocking(move || {
            gitlama_core::api::application_view_cache_write(directory, identity, bytes)
        })
        .await;
    }

    /// Best effort: a stale entry is rejected again when it is read.
    pub async fn remove(&self, repository: &NativePathIdentity) {
        if repository.remote.is_some() {
            return;
        }
        let Some(directory) = self.directory().await else {
            return;
        };
        let identity = repository.clone();
        rt::blocking(move || gitlama_core::api::application_view_cache_remove(directory, identity))
            .await;
    }
}
