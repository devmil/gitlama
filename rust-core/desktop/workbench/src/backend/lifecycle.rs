//! Opening, observing and closing repository sessions (the Dart
//! `SessionLifecycleRepository`). The workspace owns this capability; every
//! command family works on the sessions it opens.

use super::SessionCalls;
use crate::session::{
    BackendKind, FailureCode, OpenedSession, SessionError, SessionIdentity, SessionResult, check,
    required,
};
use futures::future::{FutureExt, LocalBoxFuture};
use gitlama_contract::domain::path_identity::NativePathIdentity;
use gitlama_contract::dto::{NativeRepositoryEvent, NativeRepositoryOpenResult};
use std::rc::Rc;

pub trait SessionLifecycle {
    fn open(
        &self,
        path: String,
        generation: u64,
    ) -> LocalBoxFuture<'static, SessionResult<OpenedSession>>;
    fn open_identity(
        &self,
        identity: NativePathIdentity,
        generation: u64,
    ) -> LocalBoxFuture<'static, SessionResult<OpenedSession>>;
    fn initialize(
        &self,
        path: String,
        generation: u64,
        initial_branch: String,
        bare: bool,
    ) -> LocalBoxFuture<'static, SessionResult<OpenedSession>>;
    fn events(
        &self,
        identity: SessionIdentity,
        maximum_events: u32,
    ) -> LocalBoxFuture<'static, SessionResult<Vec<NativeRepositoryEvent>>>;
    /// Rescans `identity` for changes made outside the application.
    fn refresh(&self, identity: SessionIdentity) -> LocalBoxFuture<'static, SessionResult<()>>;
    fn close(&self, identity: SessionIdentity) -> LocalBoxFuture<'static, SessionResult<bool>>;
}

fn opened(
    result: NativeRepositoryOpenResult,
    backend: BackendKind,
) -> SessionResult<OpenedSession> {
    check(&result.failure)?;
    let session = required(result.session)?;
    Ok(OpenedSession {
        identity: SessionIdentity {
            native_id: session.session_id,
            generation: session.generation,
            backend,
        },
        snapshot: session.snapshot,
    })
}

/// The lifecycle of sessions whose calls run through `calls` on this
/// computer.
pub struct LocalLifecycle {
    pub calls: Rc<dyn SessionCalls>,
}

impl SessionLifecycle for LocalLifecycle {
    fn open(
        &self,
        path: String,
        generation: u64,
    ) -> LocalBoxFuture<'static, SessionResult<OpenedSession>> {
        let call = self.calls.repository_session_open(path, generation);
        async move { opened(call.await?, BackendKind::Local) }.boxed_local()
    }

    fn open_identity(
        &self,
        identity: NativePathIdentity,
        generation: u64,
    ) -> LocalBoxFuture<'static, SessionResult<OpenedSession>> {
        let call = self
            .calls
            .repository_session_open_identity(identity, generation);
        async move { opened(call.await?, BackendKind::Local) }.boxed_local()
    }

    fn initialize(
        &self,
        path: String,
        generation: u64,
        initial_branch: String,
        bare: bool,
    ) -> LocalBoxFuture<'static, SessionResult<OpenedSession>> {
        let call = self
            .calls
            .repository_initialize(path, initial_branch, bare, generation);
        async move { opened(call.await?, BackendKind::Local) }.boxed_local()
    }

    fn events(
        &self,
        identity: SessionIdentity,
        maximum_events: u32,
    ) -> LocalBoxFuture<'static, SessionResult<Vec<NativeRepositoryEvent>>> {
        let call = self.calls.repository_session_events(
            identity.native_id,
            identity.generation,
            maximum_events,
        );
        async move {
            let result = call.await?;
            check(&result.failure)?;
            Ok(result.events)
        }
        .boxed_local()
    }

    fn refresh(&self, identity: SessionIdentity) -> LocalBoxFuture<'static, SessionResult<()>> {
        let call = self
            .calls
            .repository_session_refresh(identity.native_id, identity.generation);
        async move {
            let result = call.await?;
            check(&result.failure)?;
            if !result.accepted {
                return Err(SessionError(FailureCode::Closed));
            }
            Ok(())
        }
        .boxed_local()
    }

    fn close(&self, identity: SessionIdentity) -> LocalBoxFuture<'static, SessionResult<bool>> {
        let call = self
            .calls
            .repository_session_close(identity.native_id, identity.generation);
        async move {
            let result = call.await?;
            check(&result.failure)?;
            Ok(result.accepted)
        }
        .boxed_local()
    }
}
