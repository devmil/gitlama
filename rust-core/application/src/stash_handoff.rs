//! Setting local changes aside around an operation that needs a clean worktree, and
//! reapplying them afterwards (protected pull, revert over local changes).
//!
//! The saved stash is identified by a unique marker in its message and its immutable object,
//! never by its stack position, and it is never dropped implicitly: it stays in Stashes as a
//! recovery copy. See the Foundry guidance on Git stash handoffs.
use crate::activity::{ActivityStore, OperationIntent};
use devmil_git::activity::ActivityStatus;
use devmil_git::cancellation::Cancellation;
use devmil_git::commands::stash::{
    entry_arguments, list_arguments, push_arguments, EntryOperation,
};
use devmil_git::model::RepositoryMutation;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::status::{BranchHead, WorkingTreeState};
use devmil_git::types::ObjectId;
use devmil_git::Repository;
use std::ffi::OsString;
use std::path::Path;
use std::sync::atomic::AtomicBool;

/// Where a handoff runs and how its Git commands are attributed in Activity.
pub(crate) struct Handoff<'a> {
    pub(crate) repository: &'a Repository,
    pub(crate) worktree: &'a Path,
    pub(crate) common_git_dir: &'a Path,
    pub(crate) activity: &'a ActivityStore,
    pub(crate) intent: OperationIntent,
}

/// What saving the local changes produced.
pub(crate) enum Saved {
    /// A new stash holds the changes; the worktree is clean.
    Stash(ObjectId),
    /// `git stash push` failed or was canceled. It may still have created the stash.
    Failed {
        stash: Option<ObjectId>,
        canceled: bool,
    },
    /// Git reported success without creating a stash, as for submodule-only edits.
    Nothing,
}

/// How reapplying a saved stash ended.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct Reapplied {
    /// The changes and their staging were restored.
    pub(crate) completed: bool,
    /// Git stopped with conflicts; the stash conflict marker lets the conflict resolver
    /// finish or abort the reapply.
    pub(crate) conflicted: bool,
}

impl Handoff<'_> {
    fn run(
        &self,
        arguments: Vec<OsString>,
        cancellation: &dyn Cancellation,
    ) -> devmil_git::process::PrivateActivityResult {
        let id = crate::activity::allocate_operation_id(self.intent);
        let sink = self.activity.sink();
        ActivityGitRunner::run_private(
            GitProcessCommand::git(self.repository.git_executable())
                .current_dir(self.worktree)
                .args(arguments.into_iter().map(ProcessArgument::visible))
                .redact_output(),
            id,
            Some(cancellation),
            &mut |event| sink(event),
        )
    }

    /// Saves staged, unstaged and untracked changes in a new stash whose message is `label`
    /// followed by a unique marker.
    ///
    /// # Errors
    /// The stash list could not be read afterwards, so whether a stash exists is unknown.
    pub(crate) fn save(&self, label: &str, cancellation: &dyn Cancellation) -> Result<Saved, ()> {
        let previous = devmil_git::probes::resolve(
            self.repository.git_executable(),
            self.worktree,
            "refs/stash",
            &mut crate::git_probe::ProbeExecutor::new(Some(cancellation)),
        )
        .map_err(|_| ())?;
        // A unique marker proves which immutable stash this workflow created, including when
        // another worktree or external Git writer changes the stack.
        let mut nonce = [0_u8; 16];
        getrandom::fill(&mut nonce).map_err(|_| ())?;
        let suffix = nonce
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        let message = format!("{label} {suffix}");
        let pushed = self.run(
            push_arguments(Some(&message), &[], true).map_err(|_| ())?,
            cancellation,
        );
        // Even a failed or canceled stash command may have created a recovery object. Inspect
        // without the canceled token; never assume that a zero exit created one.
        let inspect = AtomicBool::new(false);
        let listed = self.run(list_arguments(), &inspect);
        if !matches!(listed.activity.status, ActivityStatus::Succeeded { .. }) {
            return Err(());
        }
        let stash = devmil_git::refs::parse_stashes(&listed.stdout.bytes)
            .map_err(|_| ())?
            .into_iter()
            .find(|entry| {
                entry.subject.ends_with(message.as_bytes())
                    && previous.as_ref() != Some(&entry.id.0)
            })
            .map(|entry| entry.id.0);
        if !matches!(pushed.activity.status, ActivityStatus::Succeeded { .. }) {
            return Ok(Saved::Failed {
                stash,
                canceled: cancellation.is_cancelled(),
            });
        }
        Ok(stash.map_or(Saved::Nothing, Saved::Stash))
    }

    /// Reapplies `stash` with its staging onto a clean worktree without an active operation
    /// on a branch `branch_matches` accepts; `None` when those conditions do not hold, so
    /// nothing was attempted and the stash keeps the changes.
    ///
    /// Cancellation of the surrounding operation does not stop this best-effort restoration.
    pub(crate) fn reapply(
        &self,
        stash: &ObjectId,
        mutation: &RepositoryMutation,
        branch_matches: impl Fn(&BranchHead) -> bool,
    ) -> Option<Reapplied> {
        let cleanup = AtomicBool::new(false);
        let status = mutation.fresh_status(Some(&cleanup)).ok().flatten()?;
        if status.working_tree != WorkingTreeState::Clean
            || !status.operations.is_empty()
            || !branch_matches(&status.branch.head)
        {
            return None;
        }
        let head = status.branch.oid?;
        let branch = match status.branch.head {
            BranchHead::Attached(name) => {
                Some(String::from_utf8_lossy(name.as_bytes()).into_owned())
            }
            _ => None,
        };
        if !crate::stash::begin_reapply(self.common_git_dir, stash.as_str(), head.as_str(), branch)
        {
            return None;
        }
        let applied = self.run(
            entry_arguments(EntryOperation::ApplyWithIndex, stash, "stash@{0}")
                .expect("constant selector is valid"),
            &cleanup,
        );
        let mut result = Reapplied {
            completed: matches!(applied.activity.status, ActivityStatus::Succeeded { .. }),
            conflicted: false,
        };
        // An overlapping staged patch can be refused before Git creates conflict entries.
        // Only when that attempt left a completely clean tree may Git merge the saved work
        // without its index, for the conflict resolver. The original staging remains in the
        // retained stash.
        if !result.completed
            && mutation
                .fresh_status(Some(&cleanup))
                .ok()
                .flatten()
                .is_some_and(|status| {
                    status.working_tree == WorkingTreeState::Clean && status.operations.is_empty()
                })
        {
            let _ = self.run(
                entry_arguments(EntryOperation::Apply, stash, "stash@{0}")
                    .expect("constant selector is valid"),
                &cleanup,
            );
            // Even a clean merge without --index has not restored the original staging.
        }
        result.conflicted = mutation
            .fresh_status(Some(&cleanup))
            .ok()
            .flatten()
            .is_some_and(|status| status.working_tree == WorkingTreeState::Conflicted);
        if !result.conflicted {
            let _ = crate::stash::finish_active_conflict(self.common_git_dir);
        }
        Some(result)
    }
}
