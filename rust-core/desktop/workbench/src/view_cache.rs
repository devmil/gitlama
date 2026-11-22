//! What each repository showed when it was last open, presented while it
//! loads again (the Dart `SessionViewCache`).

use futures::future::{FutureExt, LocalBoxFuture};
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{NativeHistoryPage, NativeRepositorySnapshot};
use std::rc::Rc;

pub trait SessionViewCache {
    /// Reads the stored entries of `repositories` ahead of their tabs.
    fn warm(&self, repositories: Vec<NativePathIdentity>) -> LocalBoxFuture<'static, ()>;
    /// The first history page `repository` showed last time.
    fn history(&self, repository: &NativePathIdentity) -> Option<Rc<NativeHistoryPage>>;
    /// `snapshot` with what the repository showed last time in the places it
    /// has not loaded yet. A loaded or failed snapshot is never changed.
    fn present(&self, snapshot: &NativeRepositorySnapshot) -> NativeRepositorySnapshot;
    /// Keeps the references and status of `snapshot`.
    fn remember(&self, snapshot: &NativeRepositorySnapshot);
    /// Keeps the first history `page` of `repository`.
    fn remember_history(&self, repository: &NativePathIdentity, page: &NativeHistoryPage);
}

/// Keeps nothing: every repository loads as usual.
pub struct NoViewCache;

impl SessionViewCache for NoViewCache {
    fn warm(&self, _: Vec<NativePathIdentity>) -> LocalBoxFuture<'static, ()> {
        async {}.boxed_local()
    }
    fn history(&self, _: &NativePathIdentity) -> Option<Rc<NativeHistoryPage>> {
        None
    }
    fn present(&self, snapshot: &NativeRepositorySnapshot) -> NativeRepositorySnapshot {
        snapshot.clone()
    }
    fn remember(&self, _: &NativeRepositorySnapshot) {}
    fn remember_history(&self, _: &NativePathIdentity, _: &NativeHistoryPage) {}
}
