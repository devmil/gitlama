//! Typed ref-operation planning above the shared Git command builders.

use devmil_git::commands::remote::{
    command_shape, RemoteAddRequest, RemoteEditRequest, RemoteName, RemoteOperationRequest,
    RemoteRemoveRequest, RemoteRenameRequest, RemoteUrl,
};
use devmil_git::commands::{
    branch_arguments, branch_create_arguments, tag_arguments, BranchRequest, BranchTarget,
    TagRequest, TagTarget,
};
use devmil_git::merge::{reset_arguments, ResetMode};
use devmil_git::process::{GitProcessCommand, ProcessArgument};
use devmil_git::types::ObjectId;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

const MAX_REF_NAME_BYTES: usize = 1024;
const MAX_TAG_MESSAGE_BYTES: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RefResetMode {
    Soft,
    Mixed,
    Hard,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RefMutationRequest {
    CreateBranch {
        name: String,
        target: BranchTarget,
        /// Switch to the new branch as part of creating it.
        checkout: bool,
    },
    RenameBranch {
        from: String,
        to: String,
    },
    DeleteBranch {
        name: String,
        force: bool,
    },
    CheckoutBranch {
        name: String,
    },
    CheckoutCommit {
        target: ObjectId,
    },
    SetUpstream {
        branch: String,
        upstream: String,
    },
    UnsetUpstream {
        branch: String,
    },
    CreateTag {
        name: String,
        target: ObjectId,
        message: Option<String>,
    },
    DeleteTag {
        name: String,
    },
    AddRemote {
        name: String,
        url: String,
    },
    EditRemote {
        name: String,
        url: String,
    },
    RenameRemote {
        name: String,
        new_name: String,
    },
    RemoveRemote {
        name: String,
    },
    Reset {
        mode: RefResetMode,
        target: ObjectId,
    },
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct RefMutationFacts {
    pub worktree: PathBuf,
    pub head_reference: Option<Vec<u8>>,
    pub head_target: Option<ObjectId>,
    pub dirty: bool,
    pub refs: HashMap<Vec<u8>, ObjectId>,
    pub published_branches: HashSet<Vec<u8>>,
    pub checked_out_elsewhere: HashSet<Vec<u8>>,
    pub remotes: HashSet<String>,
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum RefMutationWarning {
    DirtyCheckout,
    DetachedHead,
    PublishedBranch,
    CheckedOutElsewhere,
    DestructiveReset,
}

#[derive(Clone, Debug)]
pub struct RefMutationPlan {
    pub request: RefMutationRequest,
    pub command: GitProcessCommand,
    pub warnings: Vec<RefMutationWarning>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RefPlanError {
    InvalidInput,
    MissingRef,
    ExistingRef,
    MissingHead,
    ExistingRemote,
    MissingRemote,
}

pub fn plan_ref_mutation(
    request: RefMutationRequest,
    facts: &RefMutationFacts,
) -> Result<RefMutationPlan, RefPlanError> {
    let mut warnings = Vec::new();
    let arguments = match &request {
        RefMutationRequest::CreateBranch {
            name,
            target,
            checkout,
        } => {
            let (reference, _) = devmil_git::commands::parse_branch_name(name, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            require_absent(facts, reference.as_bytes())?;
            let target_object = match target {
                BranchTarget::Head => facts.head_target.as_ref(),
                BranchTarget::Commit(object) => Some(object),
                BranchTarget::Reference(reference) => facts.refs.get(reference.as_bytes()),
            };
            // Local changes always carry over to a branch at HEAD. At another commit Git
            // refuses when they overlap the difference, and then creates nothing.
            if *checkout && facts.dirty && facts.head_target.as_ref() != target_object {
                warnings.push(RefMutationWarning::DirtyCheckout);
            }
            visible_arguments(
                branch_create_arguments(name, target, *checkout)
                    .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::RenameBranch { from, to } => {
            let (from_ref, _) = devmil_git::commands::parse_branch_name(from, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            let (to_ref, _) = devmil_git::commands::parse_branch_name(to, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            require_ref(facts, from_ref.as_bytes())?;
            require_absent(facts, to_ref.as_bytes())?;
            if facts.published_branches.contains(from_ref.as_bytes()) {
                warnings.push(RefMutationWarning::PublishedBranch);
            }
            if facts.checked_out_elsewhere.contains(from_ref.as_bytes()) {
                warnings.push(RefMutationWarning::CheckedOutElsewhere);
            }
            visible_arguments(
                branch_arguments(&BranchRequest::Rename {
                    from: from.clone(),
                    to: to.clone(),
                })
                .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::DeleteBranch { name, force } => {
            let (reference, _) = devmil_git::commands::parse_branch_name(name, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            require_ref(facts, reference.as_bytes())?;
            if facts.published_branches.contains(reference.as_bytes()) {
                warnings.push(RefMutationWarning::PublishedBranch);
            }
            if facts.checked_out_elsewhere.contains(reference.as_bytes()) {
                warnings.push(RefMutationWarning::CheckedOutElsewhere);
            }
            visible_arguments(
                branch_arguments(&BranchRequest::Delete {
                    name: name.clone(),
                    force: *force,
                })
                .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::CheckoutBranch { name } => {
            let (reference, _) = devmil_git::commands::parse_branch_name(name, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            require_ref(facts, reference.as_bytes())?;
            if facts.dirty {
                warnings.push(RefMutationWarning::DirtyCheckout);
            }
            if facts.head_reference.is_none() {
                warnings.push(RefMutationWarning::DetachedHead);
            }
            if facts.checked_out_elsewhere.contains(reference.as_bytes()) {
                warnings.push(RefMutationWarning::CheckedOutElsewhere);
            }
            visible_arguments(
                branch_arguments(&BranchRequest::Checkout { name: name.clone() })
                    .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::CheckoutCommit { target } => {
            if facts.dirty {
                warnings.push(RefMutationWarning::DirtyCheckout);
            }
            visible_arguments(
                branch_arguments(&BranchRequest::CheckoutDetached {
                    target: target.clone(),
                })
                .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::SetUpstream { branch, upstream } => {
            let (reference, _) =
                devmil_git::commands::parse_branch_name(branch, MAX_REF_NAME_BYTES)
                    .map_err(|_| RefPlanError::InvalidInput)?;
            require_ref(facts, reference.as_bytes())?;
            if upstream.is_empty() || upstream.len() > MAX_REF_NAME_BYTES {
                return Err(RefPlanError::InvalidInput);
            }
            require_ref(facts, format!("refs/remotes/{upstream}").as_bytes())?;
            visible_arguments(
                branch_arguments(&BranchRequest::SetUpstream {
                    branch: branch.clone(),
                    upstream: upstream.clone(),
                })
                .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::UnsetUpstream { branch } => {
            let (reference, _) =
                devmil_git::commands::parse_branch_name(branch, MAX_REF_NAME_BYTES)
                    .map_err(|_| RefPlanError::InvalidInput)?;
            require_ref(facts, reference.as_bytes())?;
            visible_arguments(
                branch_arguments(&BranchRequest::UnsetUpstream {
                    branch: branch.clone(),
                })
                .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::CreateTag {
            name,
            target,
            message,
        } => {
            if message
                .as_ref()
                .is_some_and(|value| value.len() > MAX_TAG_MESSAGE_BYTES)
            {
                return Err(RefPlanError::InvalidInput);
            }
            let (reference, _) = devmil_git::commands::parse_tag_name(name, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            require_absent(facts, reference.as_bytes())?;
            visible_arguments(
                tag_arguments(&TagRequest::Create {
                    name: name.clone(),
                    target: TagTarget::Commit(target.clone()),
                    message: message.clone(),
                })
                .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::DeleteTag { name } => {
            let (reference, _) = devmil_git::commands::parse_tag_name(name, MAX_REF_NAME_BYTES)
                .map_err(|_| RefPlanError::InvalidInput)?;
            require_ref(facts, reference.as_bytes())?;
            visible_arguments(
                tag_arguments(&TagRequest::Delete { name: name.clone() })
                    .map_err(|_| RefPlanError::InvalidInput)?,
            )
        }
        RefMutationRequest::AddRemote { name, url } => {
            if facts.remotes.contains(name) {
                return Err(RefPlanError::ExistingRemote);
            }
            remote_arguments(RemoteOperationRequest::Add(RemoteAddRequest {
                name: RemoteName::new(name.clone()).map_err(|_| RefPlanError::InvalidInput)?,
                url: RemoteUrl::new(url.clone()).map_err(|_| RefPlanError::InvalidInput)?,
            }))?
        }
        RefMutationRequest::EditRemote { name, url } => {
            require_remote(facts, name)?;
            remote_arguments(RemoteOperationRequest::Edit(RemoteEditRequest {
                name: RemoteName::new(name.clone()).map_err(|_| RefPlanError::InvalidInput)?,
                url: RemoteUrl::new(url.clone()).map_err(|_| RefPlanError::InvalidInput)?,
            }))?
        }
        RefMutationRequest::RenameRemote { name, new_name } => {
            require_remote(facts, name)?;
            if facts.remotes.contains(new_name) {
                return Err(RefPlanError::ExistingRemote);
            }
            remote_arguments(RemoteOperationRequest::Rename(RemoteRenameRequest {
                name: RemoteName::new(name.clone()).map_err(|_| RefPlanError::InvalidInput)?,
                new_name: RemoteName::new(new_name.clone())
                    .map_err(|_| RefPlanError::InvalidInput)?,
            }))?
        }
        RefMutationRequest::RemoveRemote { name } => {
            require_remote(facts, name)?;
            remote_arguments(RemoteOperationRequest::Remove(RemoteRemoveRequest {
                name: RemoteName::new(name.clone()).map_err(|_| RefPlanError::InvalidInput)?,
            }))?
        }
        RefMutationRequest::Reset { mode, target } => {
            facts
                .head_target
                .as_ref()
                .ok_or(RefPlanError::MissingHead)?;
            if facts.head_reference.is_none() {
                warnings.push(RefMutationWarning::DetachedHead);
                return command_plan(request.clone(), facts, reset_args(*mode, target), warnings);
            }
            if matches!(mode, RefResetMode::Hard) {
                warnings.push(RefMutationWarning::DestructiveReset);
            }
            reset_args(*mode, target)
        }
    };
    command_plan(request, facts, arguments, warnings)
}

fn command_plan(
    request: RefMutationRequest,
    facts: &RefMutationFacts,
    arguments: Vec<ProcessArgument>,
    warnings: Vec<RefMutationWarning>,
) -> Result<RefMutationPlan, RefPlanError> {
    Ok(RefMutationPlan {
        request,
        command: GitProcessCommand::git("git")
            .args(arguments)
            .current_dir(&facts.worktree)
            // Git's diagnostics (a branch held by another worktree, a
            // missing upstream) must stay readable in Activity; redacted
            // remote credentials are still replaced in the output.
            .publish_sanitized_output(),
        warnings,
    })
}

fn reset_args(mode: RefResetMode, target: &ObjectId) -> Vec<ProcessArgument> {
    reset_arguments(
        match mode {
            RefResetMode::Soft => ResetMode::Soft,
            RefResetMode::Mixed => ResetMode::Mixed,
            RefResetMode::Hard => ResetMode::Hard,
        },
        target,
    )
    .into_iter()
    .map(ProcessArgument::visible)
    .collect()
}

fn remote_arguments(request: RemoteOperationRequest) -> Result<Vec<ProcessArgument>, RefPlanError> {
    command_shape(&request)
        .map_err(|_| RefPlanError::InvalidInput)
        .map(|shape| {
            shape
                .arguments
                .into_iter()
                .map(|argument| {
                    if argument.is_redacted() {
                        ProcessArgument::redacted(argument.value(), argument.display())
                    } else {
                        ProcessArgument::visible(argument.value())
                    }
                })
                .collect()
        })
}

fn require_ref<'a>(facts: &'a RefMutationFacts, name: &[u8]) -> Result<&'a ObjectId, RefPlanError> {
    facts.refs.get(name).ok_or(RefPlanError::MissingRef)
}

fn require_absent(facts: &RefMutationFacts, name: &[u8]) -> Result<(), RefPlanError> {
    if facts.refs.contains_key(name) {
        Err(RefPlanError::ExistingRef)
    } else {
        Ok(())
    }
}

fn require_remote(facts: &RefMutationFacts, name: &str) -> Result<(), RefPlanError> {
    if facts.remotes.contains(name) {
        Ok(())
    } else {
        Err(RefPlanError::MissingRemote)
    }
}

fn visible_arguments(values: Vec<String>) -> Vec<ProcessArgument> {
    values.into_iter().map(ProcessArgument::visible).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use devmil_git::activity::{ActivityEvent, ActivityId, ActivityStatus};
    use devmil_git::process::ActivityGitRunner;
    use std::process::Command;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT_FIXTURE: AtomicUsize = AtomicUsize::new(1);

    fn oid(byte: char) -> ObjectId {
        ObjectId::parse(byte.to_string().repeat(40)).unwrap()
    }

    fn facts() -> RefMutationFacts {
        RefMutationFacts {
            worktree: PathBuf::from("/repository"),
            head_reference: Some(b"refs/heads/main".to_vec()),
            head_target: Some(oid('1')),
            refs: HashMap::from([
                (b"refs/heads/main".to_vec(), oid('1')),
                (b"refs/heads/topic".to_vec(), oid('2')),
                (b"refs/tags/v1".to_vec(), oid('1')),
            ]),
            remotes: HashSet::from(["origin".into()]),
            ..RefMutationFacts::default()
        }
    }

    #[test]
    fn branch_plans_use_shared_argv() {
        let plan = plan_ref_mutation(
            RefMutationRequest::CreateBranch {
                name: "feature".into(),
                target: oid('2').into(),
                checkout: false,
            },
            &facts(),
        )
        .unwrap();
        assert_eq!(
            plan.command.activity().arguments,
            ["branch", "feature", &"2".repeat(40)]
        );
    }

    #[test]
    fn checked_out_creation_switches_in_one_command_and_warns_only_off_head() {
        let mut state = facts();
        state.dirty = true;
        let at_head = plan_ref_mutation(
            RefMutationRequest::CreateBranch {
                name: "feature".into(),
                target: oid('1').into(),
                checkout: true,
            },
            &state,
        )
        .unwrap();
        assert_eq!(
            at_head.command.activity().arguments,
            ["checkout", "-b", "feature", &"1".repeat(40)]
        );
        assert!(at_head.warnings.is_empty());

        let elsewhere = plan_ref_mutation(
            RefMutationRequest::CreateBranch {
                name: "feature".into(),
                target: oid('2').into(),
                checkout: true,
            },
            &state,
        )
        .unwrap();
        assert_eq!(elsewhere.warnings, [RefMutationWarning::DirtyCheckout]);
        state.dirty = false;
        assert!(plan_ref_mutation(
            RefMutationRequest::CreateBranch {
                name: "feature".into(),
                target: oid('2').into(),
                checkout: true,
            },
            &state,
        )
        .unwrap()
        .warnings
        .is_empty());
    }

    #[test]
    fn rename_reports_published_and_other_worktree_risks() {
        let mut state = facts();
        state
            .published_branches
            .insert(b"refs/heads/topic".to_vec());
        state
            .checked_out_elsewhere
            .insert(b"refs/heads/topic".to_vec());
        let plan = plan_ref_mutation(
            RefMutationRequest::RenameBranch {
                from: "topic".into(),
                to: "renamed".into(),
            },
            &state,
        )
        .unwrap();
        assert_eq!(
            plan.command.activity().arguments,
            ["branch", "-m", "topic", "renamed"]
        );
        assert!(plan.warnings.contains(&RefMutationWarning::PublishedBranch));
        assert!(plan
            .warnings
            .contains(&RefMutationWarning::CheckedOutElsewhere));
    }

    #[test]
    fn upstream_plans_require_the_branch_and_remote_tracking_ref() {
        let mut state = facts();
        state
            .refs
            .insert(b"refs/remotes/origin/topic".to_vec(), oid('2'));
        let set = plan_ref_mutation(
            RefMutationRequest::SetUpstream {
                branch: "topic".into(),
                upstream: "origin/topic".into(),
            },
            &state,
        )
        .unwrap();
        assert_eq!(
            set.command.activity().arguments,
            ["branch", "--set-upstream-to=origin/topic", "topic"]
        );
        assert!(set.warnings.is_empty());
        let unset = plan_ref_mutation(
            RefMutationRequest::UnsetUpstream {
                branch: "topic".into(),
            },
            &state,
        )
        .unwrap();
        assert_eq!(
            unset.command.activity().arguments,
            ["branch", "--unset-upstream", "topic"]
        );
        assert_eq!(
            plan_ref_mutation(
                RefMutationRequest::SetUpstream {
                    branch: "topic".into(),
                    upstream: "origin/missing".into(),
                },
                &state,
            )
            .unwrap_err(),
            RefPlanError::MissingRef
        );
        assert_eq!(
            plan_ref_mutation(
                RefMutationRequest::UnsetUpstream {
                    branch: "missing".into(),
                },
                &state,
            )
            .unwrap_err(),
            RefPlanError::MissingRef
        );
    }

    #[test]
    fn remote_plans_redact_embedded_credentials_and_validate_existence() {
        let plan = plan_ref_mutation(
            RefMutationRequest::EditRemote {
                name: "origin".into(),
                url: "https://user:secret@example.invalid/repo.git".into(),
            },
            &facts(),
        )
        .unwrap();
        let activity = plan.command.activity();
        assert_eq!(&activity.arguments[..3], ["remote", "set-url", "origin"]);
        assert!(!activity.arguments[3].contains("secret"));
        assert_eq!(
            plan_ref_mutation(
                RefMutationRequest::RemoveRemote {
                    name: "missing".into(),
                },
                &facts(),
            )
            .unwrap_err(),
            RefPlanError::MissingRemote
        );
    }

    #[test]
    fn remote_rename_requires_the_old_name_and_a_free_new_name() {
        let plan = plan_ref_mutation(
            RefMutationRequest::RenameRemote {
                name: "origin".into(),
                new_name: "upstream".into(),
            },
            &facts(),
        )
        .unwrap();
        assert_eq!(
            plan.command.activity().arguments,
            ["remote", "rename", "origin", "upstream"]
        );
        for (name, new_name, error) in [
            ("missing", "upstream", RefPlanError::MissingRemote),
            ("origin", "origin", RefPlanError::ExistingRemote),
            ("origin", "bad name", RefPlanError::InvalidInput),
        ] {
            assert_eq!(
                plan_ref_mutation(
                    RefMutationRequest::RenameRemote {
                        name: name.into(),
                        new_name: new_name.into(),
                    },
                    &facts(),
                )
                .unwrap_err(),
                error
            );
        }
    }

    #[test]
    fn reset_and_checkout_state_their_risks_before_execution() {
        let soft = plan_ref_mutation(
            RefMutationRequest::Reset {
                mode: RefResetMode::Soft,
                target: oid('2'),
            },
            &facts(),
        )
        .unwrap();
        assert_eq!(
            soft.command.activity().arguments,
            ["reset", "--soft", &"2".repeat(40)]
        );

        let mut dirty = facts();
        dirty.dirty = true;
        let checkout = plan_ref_mutation(
            RefMutationRequest::CheckoutBranch {
                name: "topic".into(),
            },
            &dirty,
        )
        .unwrap();
        assert!(checkout
            .warnings
            .contains(&RefMutationWarning::DirtyCheckout));

        let hard = plan_ref_mutation(
            RefMutationRequest::Reset {
                mode: RefResetMode::Hard,
                target: oid('2'),
            },
            &facts(),
        )
        .unwrap();
        assert!(hard
            .warnings
            .contains(&RefMutationWarning::DestructiveReset));
    }

    #[test]
    fn failed_checkout_keeps_git_diagnostics_in_activity() {
        let root = std::env::temp_dir().join(format!(
            "gitlama-ref-checkout-{}-{}",
            std::process::id(),
            NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed)
        ));
        let other = root.with_extension("other");
        std::fs::create_dir_all(&root).unwrap();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&root)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", root.join(".git-empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
        };
        std::fs::write(root.join(".git-empty-config"), []).unwrap();
        git(&["init", "-q", "-b", "main"]);
        std::fs::write(root.join("file"), b"one").unwrap();
        git(&["add", "file"]);
        git(&["commit", "-qm", "one"]);
        git(&[
            "worktree",
            "add",
            "-q",
            "-b",
            "topic",
            other.to_str().unwrap(),
        ]);
        let plan = plan_ref_mutation(
            RefMutationRequest::CheckoutBranch {
                name: "topic".into(),
            },
            &RefMutationFacts {
                worktree: root.clone(),
                refs: HashMap::from([(b"refs/heads/topic".to_vec(), oid('1'))]),
                ..RefMutationFacts::default()
            },
        )
        .unwrap();
        let mut sink = |_event: ActivityEvent| {};
        let record =
            ActivityGitRunner::run(plan.command, ActivityId::new(1).unwrap(), None, &mut sink);
        assert!(matches!(record.status, ActivityStatus::Failed { .. }));
        let stderr = String::from_utf8_lossy(&record.stderr.bytes);
        assert!(
            stderr.contains("topic"),
            "checkout diagnostic omitted branch"
        );
        assert!(
            stderr.contains(&*other.file_name().unwrap().to_string_lossy()),
            "checkout diagnostic omitted worktree"
        );
        assert!(!stderr.contains("[REDACTED]"));
        std::fs::remove_dir_all(&other).unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn real_branch_plan_executes_shared_argv() {
        let root = std::env::temp_dir().join(format!(
            "gitlama-ref-plan-{}-{}",
            std::process::id(),
            NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&root).unwrap();
        let git = |arguments: &[&str]| {
            let output = Command::new("git")
                .args(arguments)
                .current_dir(&root)
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_CONFIG_GLOBAL", root.join("empty-config"))
                .env("GIT_AUTHOR_NAME", "GitLama Test")
                .env("GIT_AUTHOR_EMAIL", "gitlama@example.invalid")
                .env("GIT_COMMITTER_NAME", "GitLama Test")
                .env("GIT_COMMITTER_EMAIL", "gitlama@example.invalid")
                .output()
                .unwrap();
            assert!(output.status.success());
            String::from_utf8_lossy(&output.stdout).trim().to_owned()
        };
        std::fs::write(root.join("empty-config"), []).unwrap();
        git(&["init", "-q", "-b", "main"]);
        std::fs::write(root.join("file"), b"one").unwrap();
        git(&["add", "file"]);
        git(&["commit", "-qm", "one"]);
        let head = ObjectId::parse(git(&["rev-parse", "HEAD"])).unwrap();
        let plan = plan_ref_mutation(
            RefMutationRequest::CreateBranch {
                name: "topic".into(),
                target: head.clone().into(),
                checkout: false,
            },
            &RefMutationFacts {
                worktree: root.clone(),
                head_reference: Some(b"refs/heads/main".to_vec()),
                head_target: Some(head),
                ..RefMutationFacts::default()
            },
        )
        .unwrap();
        let mut sink = |_event: ActivityEvent| {};
        assert!(matches!(
            ActivityGitRunner::run(plan.command, ActivityId::new(1).unwrap(), None, &mut sink,)
                .status,
            ActivityStatus::Succeeded { .. }
        ));
        assert!(Command::new("git")
            .args(["show-ref", "--verify", "--quiet", "refs/heads/topic"])
            .current_dir(&root)
            .status()
            .unwrap()
            .success());
        std::fs::remove_dir_all(root).unwrap();
    }
}
