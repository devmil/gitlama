//! The checked-out branch and repository directories an operation is previewed against.
//! Rebase and merge/cherry-pick/revert compare them again before they commit.
use devmil_git::loading::refs::RefsSectionData;
use devmil_git::status::BranchHead;
use devmil_git::types::ObjectId;
use devmil_git::RepositorySnapshot;
use std::path::PathBuf;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BranchFacts {
    pub revision: u64,
    pub worktree: PathBuf,
    pub git_dir: PathBuf,
    pub common_git_dir: PathBuf,
    pub branch_ref: Vec<u8>,
    pub branch_name: Vec<u8>,
    pub head: ObjectId,
    /// The branch has an upstream.
    pub published: bool,
}

impl BranchFacts {
    /// The facts of an attached, born branch; none on a detached or unborn HEAD.
    pub(crate) fn capture(snapshot: &RepositorySnapshot) -> Option<Self> {
        let repository = snapshot.repository.as_ref()?;
        let status = snapshot.status.as_ref()?;
        let (branch_name, branch_ref, head) = match &status.branch.head {
            BranchHead::Attached(name) => {
                let short = name.as_bytes().to_vec();
                let mut full = b"refs/heads/".to_vec();
                full.extend_from_slice(&short);
                (short, full, status.branch.oid.clone()?)
            }
            BranchHead::Detached | BranchHead::Unborn { .. } => return None,
        };
        let published = snapshot.refs.iter().any(|section| match section {
            RefsSectionData::Branches { rows, .. } => rows
                .iter()
                .any(|row| row.id.as_bytes() == branch_ref && row.upstream.is_some()),
            _ => false,
        });
        Some(Self {
            revision: snapshot.revision,
            worktree: repository.worktree.worktree_root().as_path().to_path_buf(),
            git_dir: repository.worktree.git_dir().as_path().to_path_buf(),
            common_git_dir: repository
                .worktree
                .repository()
                .common_git_dir()
                .as_path()
                .to_path_buf(),
            branch_ref,
            branch_name,
            head,
            published,
        })
    }
}
