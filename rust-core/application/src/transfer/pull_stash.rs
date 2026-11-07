//! GitLama's opt-in pull protection. Recovery stashes are never dropped implicitly.
use super::{NativePullStashResult, NativeTransferFailureKind, TransferPlan};
use crate::activity::ActivityStore;
use crate::operations::ExecutionFailure;
use crate::stash_handoff::{Handoff, Saved};
use devmil_git::cancellation::Cancellation;
use devmil_git::model::RepositoryMutation;
use devmil_git::status::{BranchHead, WorkingTreeState};
use devmil_git::types::ObjectId;
use devmil_git::Repository;

fn branch_matches(plan: &TransferPlan, branch: &BranchHead) -> bool {
    let expected = plan
        .facts
        .head_ref
        .as_ref()
        .and_then(|name| name.as_bytes().strip_prefix(b"refs/heads/"));
    matches!((branch, expected), (BranchHead::Attached(name), Some(expected)) if name.as_bytes() == expected)
}

fn handoff<'a>(
    plan: &'a TransferPlan,
    repository: &'a Repository,
    activity: &'a ActivityStore,
) -> Handoff<'a> {
    Handoff {
        repository,
        worktree: &plan.facts.worktree,
        common_git_dir: &plan.facts.common_git_dir,
        activity,
        intent: crate::activity::OperationIntent::Pull,
    }
}

fn stash_result(stash: &ObjectId) -> NativePullStashResult {
    NativePullStashResult {
        object_id: stash.as_str().to_owned(),
        pull_completed: false,
        reapply_completed: false,
        conflicted: false,
    }
}

pub(super) fn prepare(
    plan: &TransferPlan,
    repository: &Repository,
    mutation: &RepositoryMutation,
    cancellation: &dyn Cancellation,
    activity: &ActivityStore,
    failure: &mut Option<NativeTransferFailureKind>,
) -> Result<Option<NativePullStashResult>, ExecutionFailure> {
    let status = mutation
        .fresh_status(Some(cancellation))
        .ok()
        .flatten()
        .ok_or(ExecutionFailure::Definite)?;
    if status.branch.oid != plan.facts.head_oid || !branch_matches(plan, &status.branch.head) {
        *failure = Some(NativeTransferFailureKind::Stale);
        return Err(ExecutionFailure::Definite);
    }
    if !status.operations.is_empty()
        || status.working_tree == WorkingTreeState::Conflicted
        || crate::stash::active_conflict(&plan.facts.common_git_dir).is_some()
    {
        *failure = Some(NativeTransferFailureKind::ConflictedWorktree);
        return Err(ExecutionFailure::Definite);
    }
    if status.working_tree == WorkingTreeState::Clean {
        return Ok(None);
    }
    match handoff(plan, repository, activity).save("GitLama before pull", cancellation) {
        Err(()) => {
            *failure = Some(NativeTransferFailureKind::Read);
            Err(ExecutionFailure::Uncertain)
        }
        Ok(Saved::Stash(stash)) => Ok(Some(stash_result(&stash))),
        Ok(Saved::Failed { stash, canceled }) => {
            *failure = Some(if canceled {
                NativeTransferFailureKind::Canceled
            } else {
                NativeTransferFailureKind::Rejected
            });
            // The caller keeps the recovered identity even when preparation failed.
            Ok(stash.as_ref().map(stash_result))
        }
        Ok(Saved::Nothing) => {
            // Submodule-only dirt can yield a successful no-op. Do not consume an old stash.
            *failure = Some(NativeTransferFailureKind::DirtyWorktree);
            Err(ExecutionFailure::Definite)
        }
    }
}

pub(super) fn reapply(
    saved: &mut NativePullStashResult,
    plan: &TransferPlan,
    repository: &Repository,
    mutation: &RepositoryMutation,
    activity: &ActivityStore,
) {
    // Cancellation stops the pull, not the best-effort restoration of already saved work.
    // Never apply over an active merge/rebase or newly dirty tree.
    let Ok(oid) = ObjectId::parse(saved.object_id.clone()) else {
        return;
    };
    if let Some(result) = handoff(plan, repository, activity)
        .reapply(&oid, mutation, |branch| branch_matches(plan, branch))
    {
        saved.reapply_completed = result.completed;
        saved.conflicted = result.conflicted;
    }
}

#[cfg(test)]
mod tests {
    use crate::activity::ActivityStore;
    use crate::application::{session::*, transfer::*};
    use crate::test_support::*;
    use crate::transfer::*;
    use devmil_git::RepositoryOptions;
    use std::fs;

    fn request(strategy: NativePullStrategy, stash: bool) -> NativeTransferRequest {
        NativeTransferRequest {
            kind: NativeTransferKind::Pull,
            remote: Some("origin".into()),
            branch: Some("main".into()),
            pull_strategy: strategy,
            allow_dirty: !stash,
            stash_before_pull: stash,
            force_with_lease: false,
            set_upstream: false,
            refetch: false,
            prune: true,
        }
    }

    fn run(
        fixture: &TransferFixture,
        request: NativeTransferRequest,
    ) -> NativeTransferExecutionResult {
        let session = repository_session_open_with_options(
            fixture.client.clone(),
            9_101,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview =
            repository_session_transfer_preview(session.session_id, session.generation, request)
                .preview
                .expect("explicit dirty policy admits preview");
        let result = repository_session_transfer_execute(
            session.session_id,
            session.generation,
            preview.token,
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
        result
    }

    fn upstream_addition(fixture: &TransferFixture) -> Vec<u8> {
        fs::write(fixture.peer.join("upstream.txt"), b"upstream\n").unwrap();
        transfer_git(&fixture.peer, &["add", "upstream.txt"]);
        transfer_git(&fixture.peer, &["commit", "-qm", "upstream"]);
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        transfer_git(&fixture.peer, &["rev-parse", "HEAD"])
    }

    #[test]
    fn dirty_pull_does_not_implicitly_stash_even_if_repository_config_enables_it() {
        for strategy in [
            NativePullStrategy::FastForwardOnly,
            NativePullStrategy::Rebase,
        ] {
            let fixture = TransferFixture::new();
            fixture.commit(&fixture.peer, b"upstream overlap\n", "upstream");
            transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
            fs::write(fixture.client.join("tracked.txt"), b"staged edit\n").unwrap();
            transfer_git(&fixture.client, &["add", "tracked.txt"]);
            transfer_git(&fixture.client, &["config", "rebase.autoStash", "true"]);
            transfer_git(&fixture.client, &["config", "merge.autoStash", "true"]);
            let head = transfer_git(&fixture.client, &["rev-parse", "HEAD"]);
            let index = transfer_git(&fixture.client, &["ls-files", "--stage", "-z"]);
            let result = run(&fixture, request(strategy, false));
            assert_eq!(
                result.failure.unwrap().kind,
                NativeTransferFailureKind::Rejected
            );
            assert!(result.stash.is_none());
            assert_eq!(transfer_git(&fixture.client, &["rev-parse", "HEAD"]), head);
            assert_eq!(
                transfer_git(&fixture.client, &["ls-files", "--stage", "-z"]),
                index
            );
            assert_eq!(
                fs::read(fixture.client.join("tracked.txt")).unwrap(),
                b"staged edit\n"
            );
            assert!(transfer_git(&fixture.client, &["stash", "list"]).is_empty());
        }
    }

    #[test]
    fn protected_pull_restores_staged_unstaged_and_untracked_changes_for_all_strategies() {
        for strategy in [
            NativePullStrategy::FastForwardOnly,
            NativePullStrategy::FastForwardIfPossible,
            NativePullStrategy::Rebase,
        ] {
            let fixture = TransferFixture::new();
            let tip = upstream_addition(&fixture);
            fs::write(fixture.client.join("tracked.txt"), b"staged\n").unwrap();
            transfer_git(&fixture.client, &["add", "tracked.txt"]);
            fs::write(fixture.client.join("tracked.txt"), b"staged\nunstaged\n").unwrap();
            fs::write(fixture.client.join("untracked.txt"), b"new\0bytes").unwrap();
            let staged = transfer_git(&fixture.client, &["diff", "--cached", "--binary"]);
            let unstaged = transfer_git(&fixture.client, &["diff", "--binary"]);
            let result = run(&fixture, request(strategy, true));
            assert_eq!(result.state, NativeTransferExecutionState::Completed);
            let saved = result.stash.unwrap();
            assert!(saved.pull_completed && saved.reapply_completed && !saved.conflicted);
            assert_eq!(transfer_git(&fixture.client, &["rev-parse", "HEAD"]), tip);
            assert_eq!(
                transfer_git(&fixture.client, &["diff", "--cached", "--binary"]),
                staged
            );
            assert_eq!(
                transfer_git(&fixture.client, &["diff", "--binary"]),
                unstaged
            );
            assert_eq!(
                fs::read(fixture.client.join("untracked.txt")).unwrap(),
                b"new\0bytes"
            );
            assert_eq!(
                transfer_git(&fixture.client, &["rev-parse", "refs/stash"]),
                format!("{}\n", saved.object_id).as_bytes()
            );
        }
    }

    #[test]
    fn failed_fast_forward_restores_local_work_and_keeps_recovery_identity() {
        let fixture = TransferFixture::new();
        upstream_addition(&fixture);
        fixture.commit(&fixture.client, b"local commit\n", "local");
        fs::write(fixture.client.join("tracked.txt"), b"local staged\n").unwrap();
        transfer_git(&fixture.client, &["add", "tracked.txt"]);
        fs::write(fixture.client.join("tracked.txt"), b"local unstaged\n").unwrap();
        let head = transfer_git(&fixture.client, &["rev-parse", "HEAD"]);
        let index = transfer_git(&fixture.client, &["ls-files", "--stage", "-z"]);
        let result = run(&fixture, request(NativePullStrategy::FastForwardOnly, true));
        assert_eq!(result.state, NativeTransferExecutionState::Failed);
        let saved = result.stash.unwrap();
        assert!(!saved.pull_completed && saved.reapply_completed);
        assert_eq!(transfer_git(&fixture.client, &["rev-parse", "HEAD"]), head);
        assert_eq!(
            transfer_git(&fixture.client, &["ls-files", "--stage", "-z"]),
            index
        );
        assert_eq!(
            fs::read(fixture.client.join("tracked.txt")).unwrap(),
            b"local unstaged\n"
        );
    }

    #[test]
    fn staged_overlap_keeps_successful_pull_and_opens_restart_safe_stash_conflict() {
        let fixture = TransferFixture::new();
        fixture.commit(&fixture.peer, b"upstream overlap\n", "upstream");
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        let tip = transfer_git(&fixture.peer, &["rev-parse", "HEAD"]);
        fs::write(fixture.client.join("tracked.txt"), b"local staged\n").unwrap();
        transfer_git(&fixture.client, &["add", "tracked.txt"]);
        let result = run(&fixture, request(NativePullStrategy::FastForwardOnly, true));
        let saved = result.stash.unwrap();
        assert_eq!(result.state, NativeTransferExecutionState::Completed);
        assert!(saved.pull_completed && !saved.reapply_completed && saved.conflicted);
        assert_eq!(transfer_git(&fixture.client, &["rev-parse", "HEAD"]), tip);
        assert!(!transfer_git(&fixture.client, &["ls-files", "--unmerged"]).is_empty());
        let marker = crate::stash::active_conflict(&fixture.client.join(".git")).unwrap();
        assert_eq!(marker.stash_oid, saved.object_id);
        assert_eq!(format!("{}\n", marker.original_head).as_bytes(), tip);
        assert_eq!(
            transfer_git(
                &fixture.client,
                &["show", &format!("{}^2:tracked.txt", saved.object_id)]
            ),
            b"local staged\n"
        );
    }

    #[test]
    fn pull_merge_conflict_does_not_apply_saved_changes_into_active_merge() {
        let fixture = TransferFixture::new();
        fixture.commit(&fixture.peer, b"upstream\n", "upstream");
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        fixture.commit(&fixture.client, b"local\n", "local");
        fs::write(fixture.client.join("staged.txt"), b"saved\n").unwrap();
        transfer_git(&fixture.client, &["add", "staged.txt"]);
        let result = run(
            &fixture,
            request(NativePullStrategy::FastForwardIfPossible, true),
        );
        let saved = result.stash.unwrap();
        assert!(!saved.pull_completed && !saved.reapply_completed);
        assert!(fixture.client.join(".git/MERGE_HEAD").is_file());
        assert!(!fixture.client.join("staged.txt").exists());
        assert!(crate::stash::active_conflict(&fixture.client.join(".git")).is_none());
        transfer_git(&fixture.client, &["merge", "--abort"]);
        transfer_git(
            &fixture.client,
            &["stash", "apply", "--index", &saved.object_id],
        );
        assert_eq!(
            fs::read(fixture.client.join("staged.txt")).unwrap(),
            b"saved\n"
        );
    }
    #[test]
    fn untracked_file_collision_keeps_its_original_bytes_in_recovery_stash() {
        let fixture = TransferFixture::new();
        upstream_addition(&fixture);
        fs::write(fixture.client.join("upstream.txt"), b"my untracked bytes\n").unwrap();
        let result = run(&fixture, request(NativePullStrategy::FastForwardOnly, true));
        let saved = result.stash.unwrap();
        assert!(saved.pull_completed && !saved.reapply_completed);
        assert_eq!(
            fs::read(fixture.client.join("upstream.txt")).unwrap(),
            b"upstream\n"
        );
        assert_eq!(
            transfer_git(
                &fixture.client,
                &["show", &format!("{}^3:upstream.txt", saved.object_id)]
            ),
            b"my untracked bytes\n"
        );
    }

    #[test]
    fn submodule_only_edits_do_not_apply_an_existing_stash_or_start_pull() {
        let fixture = TransferFixture::new();
        let git = |args: &[&str]| transfer_git(&fixture.client, args);
        fs::create_dir(fixture.client.join("sub")).unwrap();
        git(&["-C", "sub", "init", "-q"]);
        fs::write(fixture.client.join("sub/file"), b"nested base\n").unwrap();
        git(&["-C", "sub", "add", "."]);
        git(&["-C", "sub", "commit", "-qm", "nested"]);
        git(&["add", "sub"]);
        git(&["commit", "-qm", "nested repository"]);
        fs::write(fixture.client.join("tracked.txt"), b"previous saved work\n").unwrap();
        git(&["stash", "push", "-qm", "existing"]);
        let original = git(&["rev-parse", "refs/stash"]);
        let head = git(&["rev-parse", "HEAD"]);
        fs::write(fixture.client.join("sub/file"), b"nested local work\n").unwrap();
        upstream_addition(&fixture);
        let result = run(
            &fixture,
            request(NativePullStrategy::FastForwardIfPossible, true),
        );
        assert_eq!(
            result.failure.unwrap().kind,
            NativeTransferFailureKind::DirtyWorktree
        );
        assert!(result.stash.is_none());
        assert_eq!(git(&["rev-parse", "refs/stash"]), original);
        assert_eq!(git(&["rev-parse", "HEAD"]), head);
        assert_eq!(
            fs::read(fixture.client.join("tracked.txt")).unwrap(),
            b"base\n"
        );
        assert_eq!(
            fs::read(fixture.client.join("sub/file")).unwrap(),
            b"nested local work\n"
        );
    }

    #[test]
    fn reapply_conflict_survives_reopening_and_abort_keeps_pulled_head_and_backup() {
        use crate::application::conflicts::*;
        use crate::conflict::{
            NativeConflictContinuationState, NativeConflictOperationKind,
            NativeConflictSequencerAction,
        };
        let fixture = TransferFixture::new();
        fixture.commit(&fixture.peer, b"upstream\n", "upstream");
        transfer_git(&fixture.peer, &["push", "-q", "origin", "main"]);
        fs::write(fixture.client.join("tracked.txt"), b"mine\n").unwrap();
        transfer_git(&fixture.client, &["add", "tracked.txt"]);
        let result = run(&fixture, request(NativePullStrategy::FastForwardOnly, true));
        let saved = result.stash.unwrap();
        let head = transfer_git(&fixture.client, &["rev-parse", "HEAD"]);
        let session = repository_session_open_with_options(
            fixture.client.clone(),
            9_102,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let conflicts = repository_session_conflicts(session.session_id, session.generation)
            .snapshot
            .unwrap();
        assert_eq!(conflicts.operation, NativeConflictOperationKind::Stash);
        let aborted = repository_session_conflict_continue(
            session.session_id,
            session.generation,
            NativeConflictSequencerAction::Abort,
        );
        assert_eq!(aborted.state, NativeConflictContinuationState::Aborted);
        assert_eq!(transfer_git(&fixture.client, &["rev-parse", "HEAD"]), head);
        assert_eq!(
            transfer_git(&fixture.client, &["rev-parse", "refs/stash"]),
            format!("{}\n", saved.object_id).as_bytes()
        );
        assert!(repository_session_close(session.session_id, session.generation).accepted);
    }

    #[cfg(unix)]
    #[test]
    fn canceling_pull_restores_saved_work_with_an_uncanceled_cleanup() {
        use std::os::unix::fs::PermissionsExt;
        use std::time::{Duration, Instant};
        let fixture = TransferFixture::new();
        upstream_addition(&fixture);
        fs::write(
            fixture.client.join("tracked.txt"),
            b"staged before cancel\n",
        )
        .unwrap();
        transfer_git(&fixture.client, &["add", "tracked.txt"]);
        let script = fixture.root.join("slow-upload-pack");
        fs::write(&script, b"#!/bin/sh\ntouch \"$0.started\"\nsleep 120\n").unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o700)).unwrap();
        transfer_git(
            &fixture.client,
            &[
                "config",
                "remote.origin.uploadpack",
                script.to_str().unwrap(),
            ],
        );
        let session = repository_session_open_with_options(
            fixture.client.clone(),
            9_103,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let preview = repository_session_transfer_preview(
            session.session_id,
            session.generation,
            request(NativePullStrategy::FastForwardOnly, true),
        )
        .preview
        .unwrap();
        let id = session.session_id;
        let generation = session.generation;
        let worker = std::thread::spawn(move || {
            repository_session_transfer_execute(id, generation, preview.token)
        });
        let started = Instant::now();
        while !script.with_extension("started").exists() {
            assert!(
                started.elapsed() < Duration::from_secs(10),
                "upload did not start"
            );
            std::thread::sleep(Duration::from_millis(20));
        }
        assert!(repository_session_transfer_cancel(id, generation, preview.token).accepted);
        let result = worker.join().unwrap();
        let saved = result.stash.unwrap();
        assert!(!saved.pull_completed && saved.reapply_completed);
        assert_eq!(
            fs::read(fixture.client.join("tracked.txt")).unwrap(),
            b"staged before cancel\n"
        );
        assert_eq!(
            transfer_git(&fixture.client, &["show", ":tracked.txt"]),
            b"staged before cancel\n"
        );
        assert!(started.elapsed() < Duration::from_secs(15));
        assert!(repository_session_close(id, generation).accepted);
    }
}
