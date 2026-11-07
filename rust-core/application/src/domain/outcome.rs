//! The one outcome every mutation use case returns.
//!
//! A mutation has a commit point: the moment its external effect becomes durable. The
//! [`MutationTerminalState`] records where the coordinator stopped relative to that point;
//! [`MutationOutcome`] is what a use case reports, with its family's failure detail. An
//! uncertain outcome stays uncertain all the way to the user, who must inspect the repository
//! before trying again.

/// Where a coordinated mutation stopped relative to its commit point.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MutationTerminalState {
    CanceledBeforeCommit,
    FailedBeforeCommit,
    /// Git may have changed the repository, but its effect could not be confirmed.
    OutcomeUncertain,
    Succeeded,
    /// Committed; the refresh that reconciles the snapshot failed afterwards.
    SucceededRefreshFailed,
}

impl MutationTerminalState {
    /// Whether the external effect is known to have happened.
    #[must_use]
    pub const fn committed(self) -> bool {
        matches!(self, Self::Succeeded | Self::SucceededRefreshFailed)
    }
}

/// The state a mutation use case ends in. Each family reports the subset it can reach.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MutationState {
    /// Committed and reconciled.
    Completed,
    /// Committed; the refresh afterwards failed.
    ReconciledWithWarning,
    /// Nothing to do: the change is already present.
    AlreadyContained,
    /// An interrupted operation was abandoned and its start restored.
    Aborted,
    /// Ran and stopped at conflicts the user resolves.
    Conflict,
    /// Ran and stopped part way; the operation can continue.
    Interrupted,
    /// An interactive rebase stopped to edit a commit.
    EditStop,
    /// Some steps completed, others did not.
    Partial,
    /// Refused because the previewed state changed; nothing ran.
    Stale,
    /// Canceled before its commit point.
    Canceled,
    /// Failed; the family failure says why.
    Failed,
    /// Git may have changed the repository, but the outcome could not be confirmed.
    OutcomeUncertain,
}

/// What a mutation use case reports: whether its effect committed, the state it ended in and
/// the family failure that explains a refusal or failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MutationOutcome<F> {
    pub committed: bool,
    pub state: MutationState,
    pub failure: Option<F>,
}

impl<F> MutationOutcome<F> {
    /// The outcome of a coordinated mutation, without failure detail.
    #[must_use]
    pub const fn from_terminal(terminal: MutationTerminalState) -> Self {
        Self {
            committed: terminal.committed(),
            state: match terminal {
                MutationTerminalState::Succeeded => MutationState::Completed,
                MutationTerminalState::SucceededRefreshFailed => {
                    MutationState::ReconciledWithWarning
                }
                MutationTerminalState::CanceledBeforeCommit => MutationState::Canceled,
                MutationTerminalState::FailedBeforeCommit => MutationState::Failed,
                MutationTerminalState::OutcomeUncertain => MutationState::OutcomeUncertain,
            },
            failure: None,
        }
    }

    /// An outcome in `state` that committed nothing.
    #[must_use]
    pub const fn uncommitted(state: MutationState) -> Self {
        Self {
            committed: false,
            state,
            failure: None,
        }
    }

    /// Refused before running because the previewed state changed.
    #[must_use]
    pub const fn stale() -> Self {
        Self::uncommitted(MutationState::Stale)
    }

    /// Failed before running, for `failure`.
    #[must_use]
    pub const fn refused(failure: F) -> Self {
        Self {
            committed: false,
            state: MutationState::Failed,
            failure: Some(failure),
        }
    }

    /// The same outcome with `failure` as its detail.
    #[must_use]
    pub fn with_failure(self, failure: Option<F>) -> Self {
        Self {
            committed: self.committed,
            state: self.state,
            failure,
        }
    }

    /// The same outcome in `state`.
    #[must_use]
    pub fn with_state(self, state: MutationState) -> Self {
        Self {
            committed: self.committed,
            state,
            failure: self.failure,
        }
    }

    /// Whether Git may have changed the repository without confirmation.
    #[must_use]
    pub const fn is_uncertain(&self) -> bool {
        matches!(self.state, MutationState::OutcomeUncertain)
    }

    /// The failure in product terms.
    #[must_use]
    pub fn product_failure(&self) -> Option<crate::domain::failure::ProductFailure>
    where
        F: crate::domain::failure::FamilyFailure,
    {
        self.failure
            .map(crate::domain::failure::FamilyFailure::product_failure)
    }

    /// The same outcome with its failure detail mapped.
    #[must_use]
    pub fn map_failure<G>(self, map: impl FnOnce(F) -> G) -> MutationOutcome<G> {
        MutationOutcome {
            committed: self.committed,
            state: self.state,
            failure: self.failure.map(map),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_states_keep_commitment_and_uncertainty() {
        let cases = [
            (
                MutationTerminalState::Succeeded,
                MutationState::Completed,
                true,
            ),
            (
                MutationTerminalState::SucceededRefreshFailed,
                MutationState::ReconciledWithWarning,
                true,
            ),
            (
                MutationTerminalState::CanceledBeforeCommit,
                MutationState::Canceled,
                false,
            ),
            (
                MutationTerminalState::FailedBeforeCommit,
                MutationState::Failed,
                false,
            ),
            (
                MutationTerminalState::OutcomeUncertain,
                MutationState::OutcomeUncertain,
                false,
            ),
        ];
        for (terminal, state, committed) in cases {
            let outcome = MutationOutcome::<()>::from_terminal(terminal);
            assert_eq!(outcome.state, state, "{terminal:?}");
            assert_eq!(outcome.committed, committed, "{terminal:?}");
            assert_eq!(terminal.committed(), committed);
        }
        assert!(
            MutationOutcome::<()>::from_terminal(MutationTerminalState::OutcomeUncertain)
                .is_uncertain()
        );
    }
}
