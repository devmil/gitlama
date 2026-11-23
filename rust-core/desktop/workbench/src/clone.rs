//! Clone attempts (the Dart CloneService): creating, running, retrying with
//! credentials or a trusted host key, progress polling, cancellation and
//! dismissal. A finished attempt hands its opened session to the workspace.

use crate::notify::{Notifier, Topics};
use crate::rt::{self, TimerHandle};
use crate::session::{BackendKind, OpenedSession, SessionIdentity};
use gitlama_contract::clone::{NativeCloneRunResult, NativeCloneSnapshot, NativeCloneState};
use gitlama_contract::dto::{NativeCloneFailureKind, NativeHostKeyChallenge};
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::time::Duration;

/// How often a running attempt's progress is read.
const PROGRESS: Duration = Duration::from_millis(50);

pub fn failure_name(kind: NativeCloneFailureKind) -> &'static str {
    match kind {
        NativeCloneFailureKind::InvalidSource => "invalidSource",
        NativeCloneFailureKind::EmbeddedCredential => "embeddedCredential",
        NativeCloneFailureKind::InvalidDestination => "invalidDestination",
        NativeCloneFailureKind::DestinationOccupied => "destinationOccupied",
        NativeCloneFailureKind::AttemptCapacity => "attemptCapacity",
        NativeCloneFailureKind::UnknownAttempt => "unknownAttempt",
        NativeCloneFailureKind::InvalidAttemptState => "invalidAttemptState",
        NativeCloneFailureKind::MissingGit => "missingGit",
        NativeCloneFailureKind::Authentication => "authentication",
        NativeCloneFailureKind::CredentialBrokerUnavailable => "credentialBrokerUnavailable",
        NativeCloneFailureKind::HostKey => "hostKey",
        NativeCloneFailureKind::Git => "git",
        NativeCloneFailureKind::TimedOut => "timedOut",
        NativeCloneFailureKind::Canceled => "canceled",
        NativeCloneFailureKind::Discovery => "discovery",
        NativeCloneFailureKind::HostKeyProbeFailed => "hostKeyProbeFailed",
        NativeCloneFailureKind::HostKeyChallengeExpired => "hostKeyChallengeExpired",
        NativeCloneFailureKind::HostKeyWriteFailed => "hostKeyWriteFailed",
    }
}

/// Why a clone call failed: a clone failure name.
pub type CloneResult<T> = Result<T, &'static str>;

fn invalid_state() -> &'static str {
    failure_name(NativeCloneFailureKind::InvalidAttemptState)
}

pub struct CloneService {
    this: Weak<Self>,
    notifier: Notifier,
    current: RefCell<Option<NativeCloneSnapshot>>,
    progress: RefCell<TimerHandle>,
}

impl CloneService {
    pub fn new(notifier: Notifier) -> Rc<Self> {
        Rc::new_cyclic(|this| Self {
            this: this.clone(),
            notifier,
            current: RefCell::new(None),
            progress: RefCell::new(TimerHandle::default()),
        })
    }

    pub fn current(&self) -> Option<NativeCloneSnapshot> {
        self.current.borrow().clone()
    }

    fn publish(&self, snapshot: NativeCloneSnapshot) {
        *self.current.borrow_mut() = Some(snapshot);
        self.notifier.notify(Topics::WORKSPACE);
    }

    fn is_current(&self, attempt: &NativeCloneSnapshot) -> bool {
        self.current
            .borrow()
            .as_ref()
            .is_some_and(|current| current.attempt_id == attempt.attempt_id)
    }

    fn require_current(&self) -> CloneResult<NativeCloneSnapshot> {
        self.current().ok_or_else(invalid_state)
    }

    /// Starts a clone of `source` into `destination` as attempt
    /// `generation`; a running attempt is canceled first.
    pub async fn start(
        &self,
        source: String,
        destination: String,
        generation: u64,
    ) -> CloneResult<(Option<OpenedSession>, bool)> {
        self.cancel_running().await;
        let created = rt::blocking(move || {
            gitlama_core::api::repository_clone_create(source, destination, None, generation)
        })
        .await;
        if let Some(failure) = created.failure {
            return Err(failure_name(failure.kind));
        }
        let attempt = created.snapshot.ok_or_else(invalid_state)?;
        self.publish(attempt.clone());
        let (id, generation) = (attempt.attempt_id, attempt.generation);
        self.run(attempt, move || {
            gitlama_core::api::repository_clone_run(id, generation)
        })
        .await
    }

    /// Runs the current attempt again, into `destination` when its partial
    /// destination had to be replaced.
    async fn again(&self, destination: Option<String>) -> CloneResult<NativeCloneSnapshot> {
        let current = self.require_current()?;
        let (id, generation) = (current.attempt_id, current.generation);
        let result = rt::blocking(move || match destination {
            Some(destination) => gitlama_core::api::repository_clone_retry_at_destination(
                id,
                generation,
                destination,
            ),
            None => gitlama_core::api::repository_clone_retry(id, generation),
        })
        .await;
        if let Some(failure) = result.failure {
            return Err(failure_name(failure.kind));
        }
        let attempt = result.snapshot.ok_or_else(invalid_state)?;
        self.publish(attempt.clone());
        Ok(attempt)
    }

    pub async fn retry(
        &self,
        destination: Option<String>,
    ) -> CloneResult<(Option<OpenedSession>, bool)> {
        let attempt = self.again(destination).await?;
        let (id, generation) = (attempt.attempt_id, attempt.generation);
        self.run(attempt, move || {
            gitlama_core::api::repository_clone_run(id, generation)
        })
        .await
    }

    /// Runs the current attempt again with credentials the user entered;
    /// they reach the native broker only.
    pub async fn retry_with_credentials(
        &self,
        username: Option<String>,
        password: Option<String>,
        token: Option<String>,
        destination: Option<String>,
    ) -> CloneResult<(Option<OpenedSession>, bool)> {
        let attempt = self.again(destination).await?;
        let (id, generation) = (attempt.attempt_id, attempt.generation);
        self.run(attempt, move || {
            gitlama_core::api::repository_clone_run_with_credentials(
                id, generation, username, password, token,
            )
        })
        .await
    }

    pub async fn probe_host_key(&self) -> CloneResult<NativeHostKeyChallenge> {
        let current = self.require_current()?;
        let (id, generation) = (current.attempt_id, current.generation);
        let result = rt::blocking(move || {
            gitlama_core::api::repository_clone_probe_host_key(id, generation)
        })
        .await;
        if let Some(snapshot) =
            rt::blocking(move || gitlama_core::api::repository_clone_snapshot(id, generation))
                .await
                .snapshot
        {
            self.publish(snapshot);
        }
        match (result.challenge, result.failure) {
            (Some(challenge), None) => Ok(challenge),
            (_, Some(failure)) => Err(failure_name(failure.kind)),
            _ => Err(failure_name(NativeCloneFailureKind::HostKeyProbeFailed)),
        }
    }

    /// Trusts or rejects `challenge`. A trusted key runs the attempt again;
    /// a rejected one returns None.
    pub async fn resolve_host_key(
        &self,
        challenge: &NativeHostKeyChallenge,
        accept: bool,
        destination: Option<String>,
    ) -> CloneResult<Option<(Option<OpenedSession>, bool)>> {
        let current = self.require_current()?;
        if current
            .host_key_challenge
            .as_ref()
            .map(|shown| shown.challenge_id)
            != Some(challenge.challenge_id)
        {
            return Err(failure_name(
                NativeCloneFailureKind::HostKeyChallengeExpired,
            ));
        }
        let (id, generation, challenge_id) = (
            current.attempt_id,
            current.generation,
            challenge.challenge_id,
        );
        if !accept {
            rt::blocking(move || {
                gitlama_core::api::repository_clone_reject_host_key(id, generation, challenge_id)
            })
            .await;
            if let Some(snapshot) =
                rt::blocking(move || gitlama_core::api::repository_clone_snapshot(id, generation))
                    .await
                    .snapshot
            {
                self.publish(snapshot);
            }
            return Ok(None);
        }
        let accepted = rt::blocking(move || {
            gitlama_core::api::repository_clone_accept_host_key(id, generation, challenge_id)
        })
        .await;
        if let Some(failure) = accepted.failure {
            return Err(failure_name(failure.kind));
        }
        let attempt = self.again(destination).await?;
        let (id, generation) = (attempt.attempt_id, attempt.generation);
        self.run(attempt, move || {
            gitlama_core::api::repository_clone_run_with_host_key(id, generation)
        })
        .await
        .map(Some)
    }

    pub async fn cancel(&self) -> CloneResult<()> {
        let attempt = self
            .current()
            .filter(|attempt| attempt.state == NativeCloneState::Running)
            .ok_or_else(invalid_state)?;
        let (id, generation) = (attempt.attempt_id, attempt.generation);
        let result =
            rt::blocking(move || gitlama_core::api::repository_clone_cancel(id, generation)).await;
        result
            .failure
            .map_or(Ok(()), |failure| Err(failure_name(failure.kind)))
    }

    pub async fn dismiss(&self) -> CloneResult<()> {
        let attempt = self
            .current()
            .filter(|attempt| attempt.state != NativeCloneState::Running)
            .ok_or_else(invalid_state)?;
        let (id, generation) = (attempt.attempt_id, attempt.generation);
        rt::blocking(move || gitlama_core::api::repository_clone_dismiss(id, generation)).await;
        if self
            .current()
            .is_some_and(|current| current.attempt_id == attempt.attempt_id)
        {
            *self.current.borrow_mut() = None;
            self.notifier.notify(Topics::WORKSPACE);
        }
        Ok(())
    }

    async fn cancel_running(&self) {
        if let Some(attempt) = self
            .current()
            .filter(|attempt| attempt.state == NativeCloneState::Running)
        {
            let (id, generation) = (attempt.attempt_id, attempt.generation);
            rt::blocking(move || gitlama_core::api::repository_clone_cancel(id, generation)).await;
        }
    }

    fn poll(&self, attempt: NativeCloneSnapshot) {
        let weak = self.this.clone();
        *self.progress.borrow_mut() = TimerHandle::start(PROGRESS, move || {
            let Some(service) = weak.upgrade() else {
                return;
            };
            rt::spawn_detached(async move {
                if !service.is_current(&attempt) {
                    return;
                }
                let (id, generation) = (attempt.attempt_id, attempt.generation);
                let result = rt::blocking(move || {
                    gitlama_core::api::repository_clone_snapshot(id, generation)
                })
                .await;
                // The run's own result stays authoritative over a late poll.
                if let Some(snapshot) = result
                    .snapshot
                    .filter(|snapshot| snapshot.state == NativeCloneState::Running)
                    && service.is_current(&attempt)
                    && service
                        .current()
                        .is_some_and(|current| current.state == NativeCloneState::Running)
                {
                    service.publish(snapshot);
                }
                if service
                    .current()
                    .is_some_and(|current| current.state == NativeCloneState::Running)
                {
                    service.poll(attempt);
                }
            });
        });
    }

    /// Runs `attempt` with `run` while polling its progress; returns its
    /// opened session and whether the attempt is still current.
    async fn run(
        &self,
        attempt: NativeCloneSnapshot,
        run: impl FnOnce() -> NativeCloneRunResult + Send + 'static,
    ) -> CloneResult<(Option<OpenedSession>, bool)> {
        let mut running = attempt.clone();
        running.state = NativeCloneState::Running;
        self.publish(running);
        self.poll(attempt.clone());
        let completion = rt::blocking(run).await;
        self.progress.borrow_mut().cancel();
        if let Some(snapshot) = completion.snapshot {
            self.publish(snapshot);
        }
        if let Some(failure) = completion.failure {
            return Err(failure_name(failure.kind));
        }
        let opened = completion.session.map(|session| OpenedSession {
            identity: SessionIdentity {
                native_id: session.session_id,
                generation: session.generation,
                backend: BackendKind::Local,
            },
            snapshot: session.snapshot,
        });
        Ok((opened, self.is_current(&attempt)))
    }
}

/// How far a clone has come (0…1), or None while it cannot tell.
pub fn progress(snapshot: &NativeCloneSnapshot) -> Option<f64> {
    let progress = snapshot.progress.as_ref()?;
    let total = progress.total.filter(|total| *total > 0)?;
    Some((progress.completed as f64 / total as f64).clamp(0.0, 1.0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use gitlama_contract::activity::NativeActivityProgress;

    #[test]
    fn progress_needs_a_total() {
        let mut snapshot = NativeCloneSnapshot {
            attempt_id: 1,
            generation: 1,
            state: NativeCloneState::Running,
            failure: None,
            partial_destination: false,
            progress: None,
            host_key_challenge: None,
        };
        assert_eq!(progress(&snapshot), None);
        snapshot.progress = Some(NativeActivityProgress {
            phase: "Receiving objects".into(),
            completed: 5,
            total: Some(20),
            unit: String::new(),
        });
        assert_eq!(progress(&snapshot), Some(0.25));
        snapshot.progress.as_mut().unwrap().total = Some(0);
        assert_eq!(progress(&snapshot), None);
    }
}
