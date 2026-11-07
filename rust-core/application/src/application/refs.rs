//! Branch, tag, remote and reset mutations with previewed facts.
#![allow(clippy::wildcard_imports)]
use crate::application::session::*;
use crate::domain::ids::SessionKey;
use crate::domain::outcome::{MutationOutcome, MutationState};
use crate::dto::*;
use crate::ref_operations::{
    plan_ref_mutation, RefMutationFacts, RefMutationRequest, RefMutationWarning, RefResetMode,
};
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::status::WorkingTreeState;
use devmil_git::types::{HeadState, ObjectId};
use devmil_git::RepositorySnapshot;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

pub(crate) struct OwnedRefMutationPreview {
    pub(crate) request: RefMutationRequest,
    pub(crate) facts: RefMutationFacts,
}

#[must_use]
pub fn repository_session_ref_mutation_preview(
    session_id: u64,
    generation: u64,
    request: NativeRefMutationRequest,
) -> NativeRefMutationPreviewResult {
    let kind = request.kind;
    let request = match owned_ref_mutation_request(request) {
        Ok(value) => value,
        Err(kind) => return ref_mutation_preview_failure(kind),
    };
    let repository = match repository_for_session(session_id, generation) {
        Ok(value) => value,
        Err(kind) => return ref_mutation_preview_failure(kind),
    };
    let facts = match ref_mutation_facts(&repository.snapshot()) {
        Some(value) => value,
        None => return ref_mutation_preview_failure(NativeRepositoryFailureKind::Read),
    };
    if let Err(kind) = validate_ref_target(&request, &facts.worktree) {
        return ref_mutation_preview_failure(kind);
    }
    let plan = match plan_ref_mutation(request.clone(), &facts) {
        Ok(value) => value,
        Err(_) => return ref_mutation_preview_failure(NativeRepositoryFailureKind::InvalidOptions),
    };
    let arguments = plan.command.activity().arguments;
    let warnings = plan
        .warnings
        .iter()
        .copied()
        .map(native_ref_mutation_warning)
        .collect();
    let mut sessions = lock_sessions();
    let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
        Ok(session) => session,
        Err(kind) => return ref_mutation_preview_failure(kind),
    };
    let token = session
        .refs
        .issue(OwnedRefMutationPreview { request, facts });
    NativeRefMutationPreviewResult {
        preview: Some(NativeRefMutationPreview {
            token,
            kind,
            arguments,
            warnings,
        }),
        failure: None,
    }
}

#[must_use]
pub fn repository_session_ref_mutation_execute(
    session_id: u64,
    generation: u64,
    token: u64,
) -> NativeRefMutationExecutionResult {
    let (repository, activity, preview) = {
        let mut sessions = lock_sessions();
        let session = match sessions.session_mut(SessionKey::new(session_id, generation)) {
            Ok(session) => session,
            Err(kind) => return ref_mutation_execution_failure(kind),
        };
        let Some(preview) = session.refs.take(token) else {
            return ref_mutation_execution_failure(NativeRepositoryFailureKind::InvalidOptions);
        };
        (
            Arc::clone(&session.repository),
            session.activity.clone(),
            preview,
        )
    };
    let refreshed = repository.reload().ok().and_then(|ticket| {
        ticket
            .recv_timeout(Duration::from_secs(5))
            .and_then(Result::ok)
    });
    let Some(snapshot) = refreshed else {
        return ref_mutation_execution_failure(NativeRepositoryFailureKind::Read);
    };
    let Some(facts) = ref_mutation_facts(&snapshot) else {
        return ref_mutation_execution_failure(NativeRepositoryFailureKind::Read);
    };
    if facts != preview.facts {
        return NativeRefMutationExecutionResult {
            state: NativeRefMutationExecutionState::Stale,
            failure: None,
        };
    }
    // Ref equality does not prove object availability: GC or an external writer can
    // remove an unreferenced selected commit without moving any branch.
    if let Err(kind) = validate_ref_target(&preview.request, &facts.worktree) {
        return ref_mutation_execution_failure(kind);
    }
    let plan = match plan_ref_mutation(preview.request, &facts) {
        Ok(value) => value,
        Err(_) => {
            return NativeRefMutationExecutionResult {
                state: NativeRefMutationExecutionState::Stale,
                failure: None,
            };
        }
    };
    let sink = activity.sink();
    let mut publish = |event| sink(event);
    let cancellation = AtomicBool::new(false);
    let outcome = crate::operations::coordinate_process_mutation(
        &repository,
        &cancellation,
        plan.command,
        crate::activity::allocate_operation_id(crate::activity::OperationIntent::Change),
        &mut publish,
    );
    ref_mutation_result(MutationOutcome::from_terminal(outcome))
}

/// Application preconditions, using the shared uncached Git probes. Both peels
/// parse their object, unlike validating the hexadecimal shape of an ID. Do not
/// use cached inspector data here: objects may disappear with unchanged refs.
fn validate_ref_target(
    request: &RefMutationRequest,
    worktree: &std::path::Path,
) -> Result<(), NativeRepositoryFailureKind> {
    let target = match request {
        RefMutationRequest::CreateBranch { target, .. } => target.revision(),
        RefMutationRequest::CreateTag { target, .. }
        | RefMutationRequest::CheckoutCommit { target }
        | RefMutationRequest::Reset { target, .. } => target.as_str(),
        _ => return Ok(()),
    };
    let mut executor = crate::git_probe::ProbeExecutor::new(None);
    for kind in ["commit", "tree"] {
        let revision = format!("{}^{{{kind}}}", target);
        let resolved = devmil_git::probes::resolve(
            std::ffi::OsStr::new("git"),
            worktree,
            &revision,
            &mut executor,
        )
        .map_err(|failure| match failure {
            devmil_git::probes::ProbeFailure::MissingGit => NativeRepositoryFailureKind::MissingGit,
            devmil_git::probes::ProbeFailure::Canceled => NativeRepositoryFailureKind::Canceled,
            _ => NativeRepositoryFailureKind::Read,
        })?;
        if resolved.is_none() {
            return Err(NativeRepositoryFailureKind::MissingObject);
        }
    }
    Ok(())
}

/// The bridge result of a ref mutation: the one place its outcome becomes a state.
pub(crate) fn ref_mutation_result(
    outcome: MutationOutcome<NativeRepositoryFailureKind>,
) -> NativeRefMutationExecutionResult {
    NativeRefMutationExecutionResult {
        state: match outcome.state {
            MutationState::Completed | MutationState::AlreadyContained | MutationState::Aborted => {
                NativeRefMutationExecutionState::Completed
            }
            MutationState::ReconciledWithWarning => {
                NativeRefMutationExecutionState::ReconciledWithWarning
            }
            MutationState::Stale => NativeRefMutationExecutionState::Stale,
            MutationState::Conflict
            | MutationState::Interrupted
            | MutationState::EditStop
            | MutationState::Partial
            | MutationState::Canceled
            | MutationState::Failed => NativeRefMutationExecutionState::Failed,
            MutationState::OutcomeUncertain => NativeRefMutationExecutionState::OutcomeUncertain,
        },
        failure: outcome.failure.map(|kind| NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn ref_mutation_preview_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeRefMutationPreviewResult {
    NativeRefMutationPreviewResult {
        preview: None,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn ref_mutation_execution_failure(
    kind: NativeRepositoryFailureKind,
) -> NativeRefMutationExecutionResult {
    NativeRefMutationExecutionResult {
        state: NativeRefMutationExecutionState::Failed,
        failure: Some(NativeRepositoryFailure { kind }),
    }
}

pub(crate) fn owned_ref_mutation_request(
    request: NativeRefMutationRequest,
) -> Result<RefMutationRequest, NativeRepositoryFailureKind> {
    let invalid = || NativeRepositoryFailureKind::InvalidOptions;
    let name = || request.name.clone().ok_or_else(invalid);
    let target = || {
        request
            .target
            .clone()
            .ok_or_else(invalid)
            .and_then(|value| ObjectId::parse(value).map_err(|_| invalid()))
    };
    Ok(match request.kind {
        NativeRefMutationKind::CreateBranch => RefMutationRequest::CreateBranch {
            name: name()?,
            target: devmil_git::commands::BranchTarget::parse(
                request.target.as_deref().ok_or_else(invalid)?,
            )
            .map_err(|_| invalid())?,
            checkout: request.checkout,
        },
        NativeRefMutationKind::RenameBranch => RefMutationRequest::RenameBranch {
            from: name()?,
            to: request.second_name.ok_or_else(invalid)?,
        },
        NativeRefMutationKind::DeleteBranch => RefMutationRequest::DeleteBranch {
            name: name()?,
            force: request.force,
        },
        NativeRefMutationKind::CheckoutBranch => {
            RefMutationRequest::CheckoutBranch { name: name()? }
        }
        NativeRefMutationKind::CheckoutCommit => {
            RefMutationRequest::CheckoutCommit { target: target()? }
        }
        NativeRefMutationKind::SetUpstream => RefMutationRequest::SetUpstream {
            branch: name()?,
            upstream: request.second_name.ok_or_else(invalid)?,
        },
        NativeRefMutationKind::UnsetUpstream => {
            RefMutationRequest::UnsetUpstream { branch: name()? }
        }
        NativeRefMutationKind::CreateTag => RefMutationRequest::CreateTag {
            name: name()?,
            target: target()?,
            message: request.message,
        },
        NativeRefMutationKind::DeleteTag => RefMutationRequest::DeleteTag { name: name()? },
        NativeRefMutationKind::AddRemote => RefMutationRequest::AddRemote {
            name: name()?,
            url: request.url.ok_or_else(invalid)?,
        },
        NativeRefMutationKind::EditRemote => RefMutationRequest::EditRemote {
            name: name()?,
            url: request.url.ok_or_else(invalid)?,
        },
        NativeRefMutationKind::RenameRemote => RefMutationRequest::RenameRemote {
            name: name()?,
            new_name: request.second_name.ok_or_else(invalid)?,
        },
        NativeRefMutationKind::RemoveRemote => RefMutationRequest::RemoveRemote { name: name()? },
        NativeRefMutationKind::Reset => RefMutationRequest::Reset {
            mode: match request.reset_mode.ok_or_else(invalid)? {
                NativeRefResetMode::Soft => RefResetMode::Soft,
                NativeRefResetMode::Mixed => RefResetMode::Mixed,
                NativeRefResetMode::Hard => RefResetMode::Hard,
            },
            target: target()?,
        },
    })
}

pub(crate) fn native_ref_mutation_warning(value: RefMutationWarning) -> NativeRefMutationWarning {
    match value {
        RefMutationWarning::DirtyCheckout => NativeRefMutationWarning::DirtyCheckout,
        RefMutationWarning::DetachedHead => NativeRefMutationWarning::DetachedHead,
        RefMutationWarning::PublishedBranch => NativeRefMutationWarning::PublishedBranch,
        RefMutationWarning::CheckedOutElsewhere => NativeRefMutationWarning::CheckedOutElsewhere,
        RefMutationWarning::DestructiveReset => NativeRefMutationWarning::DestructiveReset,
    }
}

pub(crate) fn ref_mutation_facts(snapshot: &RepositorySnapshot) -> Option<RefMutationFacts> {
    let discovered = snapshot.repository.as_ref()?;
    let (head_reference, head_target) = match &discovered.head {
        HeadState::Attached { branch, target } => {
            (Some(branch.as_bytes().to_vec()), Some(target.clone()))
        }
        HeadState::Detached { target } => (None, Some(target.clone())),
        HeadState::Unborn { branch } => (Some(branch.as_bytes().to_vec()), None),
    };
    let mut facts = RefMutationFacts {
        worktree: discovered.worktree.worktree_root().as_path().to_path_buf(),
        head_reference,
        head_target,
        dirty: snapshot
            .status
            .as_ref()
            .is_some_and(|status| status.working_tree != WorkingTreeState::Clean),
        ..RefMutationFacts::default()
    };
    let mut remote_refs = Vec::new();
    for section in snapshot.refs.iter() {
        match section {
            RefsSectionData::Branches { rows, .. } | RefsSectionData::Tags(rows) => {
                facts.refs.extend(
                    rows.iter().map(|reference| {
                        (reference.id.as_bytes().to_vec(), reference.target.clone())
                    }),
                );
            }
            RefsSectionData::Remotes {
                references,
                remotes,
            } => {
                remote_refs.extend(
                    references
                        .iter()
                        .map(|reference| reference.id.as_bytes().to_vec()),
                );
                facts.refs.extend(
                    references.iter().map(|reference| {
                        (reference.id.as_bytes().to_vec(), reference.target.clone())
                    }),
                );
                facts.remotes.extend(remotes.iter().filter_map(|remote| {
                    std::str::from_utf8(remote.id.as_bytes())
                        .ok()
                        .map(str::to_owned)
                }));
            }
            RefsSectionData::Worktrees(worktrees) => {
                facts.checked_out_elsewhere.extend(
                    worktrees
                        .iter()
                        .filter(|worktree| worktree.id != discovered.worktree)
                        .filter_map(|worktree| {
                            worktree
                                .branch
                                .as_ref()
                                .map(|branch| branch.as_bytes().to_vec())
                        }),
                );
            }
            RefsSectionData::Stashes(_) => {}
        }
    }
    for reference in facts
        .refs
        .keys()
        .filter(|reference| reference.starts_with(b"refs/heads/"))
    {
        let short = &reference[b"refs/heads/".len()..];
        if remote_refs.iter().any(|remote| {
            remote.starts_with(b"refs/remotes/")
                && remote.ends_with(short)
                && remote.get(remote.len().saturating_sub(short.len() + 1)) == Some(&b'/')
        }) {
            facts.published_branches.insert(reference.clone());
        }
    }
    Some(facts)
}

#[cfg(test)]
mod session_tests {
    #![allow(clippy::wildcard_imports)]
    use crate::activity::ActivityStore;
    use crate::test_support::*;

    use crate::application::refs::*;

    use devmil_git::RepositoryOptions;

    use std::fs;

    use std::process::Command;

    #[test]
    fn remote_ref_checkout_links_upstream_and_refuses_moved_targets() {
        for dirty in [false, true] {
            let fixture = GitFixture::new();
            let git = |args: &[&str]| {
                let output = Command::new("git")
                    .args(args)
                    .current_dir(&fixture.0)
                    .env("GIT_AUTHOR_NAME", "Test")
                    .env("GIT_AUTHOR_EMAIL", "test@example.invalid")
                    .env("GIT_COMMITTER_NAME", "Test")
                    .env("GIT_COMMITTER_EMAIL", "test@example.invalid")
                    .output()
                    .unwrap();
                assert!(output.status.success(), "{:?}", output.stderr);
                String::from_utf8(output.stdout).unwrap().trim().to_owned()
            };
            fs::write(fixture.0.join("file"), b"baseline").unwrap();
            git(&["add", "file"]);
            git(&["commit", "-qm", "baseline"]);
            let original = git(&["rev-parse", "HEAD"]);
            git(&["remote", "add", "origin", "."]);
            git(&["config", "branch.autoSetupMerge", "false"]);
            let reference = "refs/remotes/origin/release/2026.11_global";
            git(&["update-ref", reference, &original]);
            if dirty {
                fs::write(fixture.0.join("file"), b"local").unwrap();
            }
            let session = repository_session_open_with_options(
                fixture.0.clone(),
                990,
                RepositoryOptions {
                    watch: false,
                    ..RepositoryOptions::default()
                },
                ActivityStore::default(),
            )
            .session
            .unwrap();
            wait_for_ready(&session);
            let request = |name: &str| NativeRefMutationRequest {
                kind: NativeRefMutationKind::CreateBranch,
                name: Some(name.into()),
                second_name: None,
                target: Some(reference.into()),
                message: None,
                url: None,
                force: false,
                reset_mode: None,
                checkout: true,
            };
            let preview = repository_session_ref_mutation_preview(
                session.session_id,
                990,
                request("release/2026.11_global"),
            )
            .preview
            .unwrap();
            assert!(preview.warnings.is_empty());
            assert_eq!(
                repository_session_ref_mutation_execute(session.session_id, 990, preview.token)
                    .state,
                NativeRefMutationExecutionState::Completed
            );
            assert_eq!(
                git(&["symbolic-ref", "--short", "HEAD"]),
                "release/2026.11_global"
            );
            assert_eq!(git(&["rev-parse", "HEAD"]), original);
            assert_eq!(
                git(&["config", "branch.release/2026.11_global.remote"]),
                "origin"
            );
            assert_eq!(
                git(&["config", "branch.release/2026.11_global.merge"]),
                "refs/heads/release/2026.11_global"
            );
            assert_eq!(
                fs::read(fixture.0.join("file")).unwrap(),
                if dirty {
                    b"local".as_slice()
                } else {
                    b"baseline".as_slice()
                }
            );
            let preview = repository_session_ref_mutation_preview(
                session.session_id,
                990,
                request("must-not-exist"),
            )
            .preview
            .unwrap();
            let tree = git(&["rev-parse", "HEAD^{tree}"]);
            let moved = git(&["commit-tree", &tree, "-p", &original, "-m", "moved"]);
            git(&["update-ref", reference, &moved]);
            assert_eq!(
                repository_session_ref_mutation_execute(session.session_id, 990, preview.token)
                    .state,
                NativeRefMutationExecutionState::Stale
            );
            assert!(!Command::new("git")
                .args([
                    "show-ref",
                    "--verify",
                    "--quiet",
                    "refs/heads/must-not-exist"
                ])
                .current_dir(&fixture.0)
                .status()
                .unwrap()
                .success());
            let _ = repository_session_close(session.session_id, 990);
        }
    }

    #[test]
    fn missing_ref_targets_are_rejected_without_writes_even_when_refs_do_not_change() {
        for remove_tree in [false, true] {
            for after_preview in [false, true] {
                let fixture = GitFixture::new();
                let git = |args: &[&str]| {
                    let output = Command::new("git")
                        .args(args)
                        .current_dir(&fixture.0)
                        .env("GIT_AUTHOR_NAME", "Test")
                        .env("GIT_AUTHOR_EMAIL", "test@example.invalid")
                        .env("GIT_COMMITTER_NAME", "Test")
                        .env("GIT_COMMITTER_EMAIL", "test@example.invalid")
                        .output()
                        .unwrap();
                    assert!(output.status.success(), "{:?}", output.stderr);
                    String::from_utf8(output.stdout).unwrap().trim().to_owned()
                };
                fs::write(fixture.0.join("file"), b"baseline").unwrap();
                git(&["add", "file"]);
                git(&["commit", "-qm", "baseline"]);
                let head = git(&["rev-parse", "HEAD"]);
                fs::write(fixture.0.join("orphan"), b"orphan tree").unwrap();
                git(&["add", "orphan"]);
                let tree = git(&["write-tree"]);
                git(&["reset", "-q", "HEAD"]);
                fs::remove_file(fixture.0.join("orphan")).unwrap();
                let target = git(&["commit-tree", &tree, "-m", "unreferenced"]);
                let opened = repository_session_open_with_options(
                    fixture.0.clone(),
                    907,
                    RepositoryOptions {
                        watch: false,
                        ..RepositoryOptions::default()
                    },
                    ActivityStore::default(),
                );
                let session = opened.session.unwrap();
                wait_for_ready(&session);
                let request = || NativeRefMutationRequest {
                    kind: NativeRefMutationKind::CreateBranch,
                    name: Some("new-branch".into()),
                    second_name: None,
                    target: Some(target.clone()),
                    message: None,
                    url: None,
                    force: false,
                    reset_mode: None,
                    checkout: true,
                };
                let preview = after_preview.then(|| {
                    repository_session_ref_mutation_preview(session.session_id, 907, request())
                        .preview
                        .unwrap()
                });
                let missing = if remove_tree { &tree } else { &target };
                fs::remove_file(
                    fixture
                        .0
                        .join(".git/objects")
                        .join(&missing[..2])
                        .join(&missing[2..]),
                )
                .unwrap();
                let failure = if let Some(preview) = preview {
                    repository_session_ref_mutation_execute(session.session_id, 907, preview.token)
                        .failure
                } else {
                    let result =
                        repository_session_ref_mutation_preview(session.session_id, 907, request());
                    assert!(
                        result.preview.is_none(),
                        "tree={remove_tree} after_preview={after_preview}"
                    );
                    result.failure
                };
                assert_eq!(
                    failure.unwrap().kind,
                    NativeRepositoryFailureKind::MissingObject,
                    "tree={remove_tree} after_preview={after_preview}"
                );
                assert_eq!(git(&["rev-parse", "HEAD"]), head);
                assert!(git(&["for-each-ref", "refs/heads/new-branch"]).is_empty());
                assert!(git(&["status", "--porcelain"]).is_empty());
                assert_eq!(fs::read(fixture.0.join("file")).unwrap(), b"baseline");
                assert!(repository_session_close(session.session_id, 907).accepted);
            }
        }
    }

    #[test]
    fn ref_mutation_preview_revalidates_before_execution() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
            String::from_utf8_lossy(&output.stdout).trim().to_owned()
        };
        fs::write(fixture.0.join("file"), b"one").unwrap();
        git(&["add", "file"]);
        git(&["commit", "-qm", "one"]);
        let head = git(&["rev-parse", "HEAD"]);
        let opened = repository_session_open_with_options(
            fixture.0.clone(),
            902,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let request = |name: &str| NativeRefMutationRequest {
            kind: NativeRefMutationKind::CreateBranch,
            name: Some(name.into()),
            second_name: None,
            target: Some(head.clone()),
            message: None,
            url: None,
            force: false,
            reset_mode: None,
            checkout: false,
        };
        let stale =
            repository_session_ref_mutation_preview(session.session_id, 902, request("raced"))
                .preview
                .unwrap();
        assert_eq!(stale.arguments, ["branch", "raced", &head]);
        git(&["branch", "raced", &head]);
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 902, stale.token).state,
            NativeRefMutationExecutionState::Stale
        );

        let preview =
            repository_session_ref_mutation_preview(session.session_id, 902, request("created"))
                .preview
                .unwrap();
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 902, preview.token).state,
            NativeRefMutationExecutionState::Completed
        );
        assert_eq!(git(&["rev-parse", "created"]), head);
        assert_eq!(
            repository_session_ref_mutation_preview(session.session_id, 902, request("--invalid"),)
                .failure
                .unwrap()
                .kind,
            NativeRepositoryFailureKind::InvalidOptions
        );
        assert!(repository_session_close(session.session_id, 902).accepted);
    }

    #[test]
    fn created_branch_is_checked_out_with_local_changes() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
            String::from_utf8_lossy(&output.stdout).trim().to_owned()
        };
        fs::write(fixture.0.join("file"), b"one").unwrap();
        git(&["add", "file"]);
        git(&["commit", "-qm", "one"]);
        let first = git(&["rev-parse", "HEAD"]);
        fs::write(fixture.0.join("file"), b"two").unwrap();
        git(&["commit", "-qam", "two"]);
        let head = git(&["rev-parse", "HEAD"]);
        // Tracked, staged and untracked local changes all have to survive the switch.
        fs::write(fixture.0.join("file"), b"local").unwrap();
        fs::write(fixture.0.join("staged"), b"staged").unwrap();
        git(&["add", "staged"]);
        fs::write(fixture.0.join("untracked"), b"untracked").unwrap();
        let opened = repository_session_open_with_options(
            fixture.0.clone(),
            903,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        );
        let session = opened.session.unwrap();
        wait_for_ready(&session);
        let request = |name: &str, target: &str| NativeRefMutationRequest {
            kind: NativeRefMutationKind::CreateBranch,
            name: Some(name.into()),
            second_name: None,
            target: Some(target.into()),
            message: None,
            url: None,
            force: false,
            reset_mode: None,
            checkout: true,
        };

        let preview = repository_session_ref_mutation_preview(
            session.session_id,
            903,
            request("created", &head),
        )
        .preview
        .unwrap();
        assert_eq!(preview.arguments, ["checkout", "-b", "created", &head]);
        assert!(preview.warnings.is_empty());
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 903, preview.token).state,
            NativeRefMutationExecutionState::Completed
        );
        assert_eq!(git(&["symbolic-ref", "--short", "HEAD"]), "created");
        assert_eq!(fs::read(fixture.0.join("file")).unwrap(), b"local");
        assert_eq!(fs::read(fixture.0.join("untracked")).unwrap(), b"untracked");
        assert_eq!(git(&["diff", "--cached", "--name-only"]), "staged");

        // Off HEAD the overlapping local change makes Git refuse, and nothing is created.
        let conflicting = repository_session_ref_mutation_preview(
            session.session_id,
            903,
            request("older", &first),
        )
        .preview
        .unwrap();
        assert_eq!(
            conflicting.warnings,
            [NativeRefMutationWarning::DirtyCheckout]
        );
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 903, conflicting.token)
                .state,
            NativeRefMutationExecutionState::Failed
        );
        assert_eq!(git(&["symbolic-ref", "--short", "HEAD"]), "created");
        assert_eq!(fs::read(fixture.0.join("file")).unwrap(), b"local");
        assert!(!Command::new("git")
            .args(["show-ref", "--verify", "--quiet", "refs/heads/older"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());

        assert!(repository_session_close(session.session_id, 903).accepted);
    }

    #[test]
    fn ref_mutations_cover_branch_tag_remote_and_linked_worktree_truth() {
        let fixture = GitFixture::new();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&fixture.0)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "git {arguments:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            String::from_utf8_lossy(&output.stdout).trim().to_owned()
        };
        fs::write(fixture.0.join("file"), b"one").unwrap();
        git(&["add", "file"]);
        git(&["commit", "-qm", "one"]);
        let head = git(&["rev-parse", "HEAD"]);
        git(&["branch", "topic", &head]);
        let linked = fixture_path("linked");
        git(&["worktree", "add", "-q", linked.to_str().unwrap(), "topic"]);

        let session = repository_session_open_with_options(
            fixture.0.clone(),
            903,
            RepositoryOptions {
                watch: false,
                ..RepositoryOptions::default()
            },
            ActivityStore::default(),
        )
        .session
        .unwrap();
        wait_for_ready(&session);
        let request = |kind, name: Option<&str>, second_name: Option<&str>, url: Option<&str>| {
            NativeRefMutationRequest {
                kind,
                name: name.map(str::to_owned),
                second_name: second_name.map(str::to_owned),
                target: Some(head.clone()),
                message: None,
                url: url.map(str::to_owned),
                force: true,
                reset_mode: None,
                checkout: false,
            }
        };

        let checkout = repository_session_ref_mutation_preview(
            session.session_id,
            903,
            request(
                NativeRefMutationKind::CheckoutBranch,
                Some("topic"),
                None,
                None,
            ),
        )
        .preview
        .unwrap();
        assert!(checkout
            .warnings
            .contains(&NativeRefMutationWarning::CheckedOutElsewhere));

        git(&["worktree", "remove", "--force", linked.to_str().unwrap()]);
        assert!(repository_session_refresh(session.session_id, 903).accepted);
        let ready = wait_for_new_revision(&session, 1);
        assert_eq!(ready.ref_counts.worktrees, 1);

        let rename = repository_session_ref_mutation_preview(
            session.session_id,
            903,
            request(
                NativeRefMutationKind::RenameBranch,
                Some("topic"),
                Some("renamed"),
                None,
            ),
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 903, rename.token).state,
            NativeRefMutationExecutionState::Completed
        );
        assert_eq!(git(&["rev-parse", "renamed"]), head);

        let delete = repository_session_ref_mutation_preview(
            session.session_id,
            903,
            request(
                NativeRefMutationKind::DeleteBranch,
                Some("renamed"),
                None,
                None,
            ),
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 903, delete.token).state,
            NativeRefMutationExecutionState::Completed
        );
        assert!(!Command::new("git")
            .args(["show-ref", "--verify", "--quiet", "refs/heads/renamed"])
            .current_dir(&fixture.0)
            .status()
            .unwrap()
            .success());

        let create_tag = repository_session_ref_mutation_preview(
            session.session_id,
            903,
            request(NativeRefMutationKind::CreateTag, Some("v1"), None, None),
        )
        .preview
        .unwrap();
        assert_eq!(
            repository_session_ref_mutation_execute(session.session_id, 903, create_tag.token)
                .state,
            NativeRefMutationExecutionState::Completed
        );
        assert_eq!(git(&["rev-parse", "v1"]), head);

        for (kind, name, url) in [
            (
                NativeRefMutationKind::AddRemote,
                "origin",
                Some("https://example.invalid/one.git"),
            ),
            (
                NativeRefMutationKind::EditRemote,
                "origin",
                Some("https://example.invalid/two.git"),
            ),
            (NativeRefMutationKind::RemoveRemote, "origin", None),
        ] {
            let preview = repository_session_ref_mutation_preview(
                session.session_id,
                903,
                request(kind, Some(name), None, url),
            )
            .preview
            .unwrap();
            assert_eq!(
                repository_session_ref_mutation_execute(session.session_id, 903, preview.token)
                    .state,
                NativeRefMutationExecutionState::Completed
            );
        }
        assert!(!git(&["remote"]).contains("origin"));
        assert!(repository_session_close(session.session_id, 903).accepted);
    }

    #[test]
    fn reset_modes_execute_exact_scope() {
        for (index, mode) in [
            NativeRefResetMode::Soft,
            NativeRefResetMode::Mixed,
            NativeRefResetMode::Hard,
        ]
        .into_iter()
        .enumerate()
        {
            let fixture = GitFixture::new();
            let git = |arguments: &[&str]| {
                let output = Command::new("git")
                    .args(arguments)
                    .current_dir(&fixture.0)
                    .env("GIT_CONFIG_NOSYSTEM", "1")
                    .env("GIT_CONFIG_GLOBAL", fixture.0.join("empty-config"))
                    .env("GIT_AUTHOR_NAME", "GitLama Test")
                    .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                    .env("GIT_COMMITTER_NAME", "GitLama Test")
                    .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                    .output()
                    .unwrap();
                assert!(output.status.success());
                String::from_utf8_lossy(&output.stdout).trim().to_owned()
            };
            fs::write(fixture.0.join("file"), b"one").unwrap();
            git(&["add", "file"]);
            git(&["commit", "-qm", "one"]);
            let first = git(&["rev-parse", "HEAD"]);
            fs::write(fixture.0.join("file"), b"two").unwrap();
            git(&["commit", "-qam", "two"]);
            let generation = 910 + index as u64;
            let session = repository_session_open_with_options(
                fixture.0.clone(),
                generation,
                RepositoryOptions {
                    watch: false,
                    ..RepositoryOptions::default()
                },
                ActivityStore::default(),
            )
            .session
            .unwrap();
            wait_for_ready(&session);
            let preview = repository_session_ref_mutation_preview(
                session.session_id,
                generation,
                NativeRefMutationRequest {
                    kind: NativeRefMutationKind::Reset,
                    name: None,
                    second_name: None,
                    target: Some(first.clone()),
                    message: None,
                    url: None,
                    force: false,
                    reset_mode: Some(mode),
                    checkout: false,
                },
            )
            .preview
            .unwrap();
            let flag = match mode {
                NativeRefResetMode::Soft => "--soft",
                NativeRefResetMode::Mixed => "--mixed",
                NativeRefResetMode::Hard => "--hard",
            };
            assert_eq!(preview.arguments, ["reset", flag, &first]);
            assert_eq!(
                repository_session_ref_mutation_execute(
                    session.session_id,
                    generation,
                    preview.token,
                )
                .state,
                NativeRefMutationExecutionState::Completed
            );
            assert_eq!(git(&["rev-parse", "HEAD"]), first);
            match mode {
                NativeRefResetMode::Soft => {
                    // The change of the commit reset away stays staged.
                    assert!(!Command::new("git")
                        .args(["diff", "--cached", "--quiet"])
                        .current_dir(&fixture.0)
                        .status()
                        .unwrap()
                        .success());
                }
                NativeRefResetMode::Mixed => {
                    assert!(Command::new("git")
                        .args(["diff", "--cached", "--quiet"])
                        .current_dir(&fixture.0)
                        .status()
                        .unwrap()
                        .success());
                    assert!(!Command::new("git")
                        .args(["diff", "--quiet"])
                        .current_dir(&fixture.0)
                        .status()
                        .unwrap()
                        .success());
                }
                NativeRefResetMode::Hard => {
                    assert_eq!(fs::read(fixture.0.join("file")).unwrap(), b"one");
                    assert!(Command::new("git")
                        .args(["status", "--porcelain"])
                        .current_dir(&fixture.0)
                        .output()
                        .unwrap()
                        .stdout
                        .is_empty());
                }
            }
            assert!(repository_session_close(session.session_id, generation).accepted);
        }
    }
}
