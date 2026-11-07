# ADR 0005: No repository undo

- Status: accepted
- Date: 2026-10-17

## Context

GitLama inherited a per-repository undo and redo ledger from QSpline: Recovery history, the Undo and Redo commands on Ctrl+Z and Cmd+Z, and a "You can undo this from Recovery history" line in the reviews of the operations it recorded. The ledger covered commits, checkout, merges, rebases, cherry-picks, reverts, branch and tag changes, soft resets, patch application and some stash actions.

It never covered every action that changes a repository. Discard, Clean, push, deleting a branch or tag on a remote, the working-tree part of a hard or mixed reset, a fast-forward or merging pull, remote changes, worktrees, LFS tracking, `.gitignore` additions and staging were not recorded. Undo also refused entries the repository had moved past. Two reviews promised undo for actions the ledger never recorded: applying, popping or auto-stashing a stash, and restoring a named snapshot. Covering every action would need GitLama-owned backups of state Git itself cannot restore.

A partial undo leaves the user to remember which actions can be taken back. Behind the actions the user can least afford to get wrong, it offers no help.

## Decision

GitLama has no repository-wide undo or redo. The ledger, Recovery history, the Undo and Redo commands and their shortcuts, the remote helper's `Undo` write family and every review line promising undo are removed. Ctrl+Z and Cmd+Z belong to text editing.

What stays is explicit:

- Each review says what an action changes before it runs. A destructive action says what it deletes (Discard, Clean, a hard reset, dropping a stash) or that others may already have fetched what it removes on a remote.
- Named snapshots are the way back the user chooses: they record work on purpose and restore it later. Restoring a snapshot saves the current changes as a stash first, visible under Stashes.
- Git's own record stays visible: the reflog in History shows where branches pointed.
- Undoing a conflict resolution while the conflict is open, and resuming or abandoning an interrupted operation after a restart, are unchanged. Neither is a repository undo.

## Consequences

- The remote helper drops the `Undo` family and receives a new version. Pending remote writes of that family in older stores are dropped when the store loads, because no helper can reconcile them.
- Ledgers already written to `.git/gitlama/undo` by earlier versions are left in place and no longer read.
- A mutation no longer becomes "completed with a warning" because recording its recovery anchor failed; only a failed refresh does that.

## Rejected alternatives

- Extending the ledger to every action: it needs content backups for discarded and cleaned files and cannot take back anything already sent to a remote.
- Keeping undo for the recorded actions with clearer labels: the user would still need to know the list, and the promise invites trust where none is earned.
