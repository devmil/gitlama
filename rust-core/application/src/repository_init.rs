//! Creates a repository in an explicit destination. Desktop initialization opens the result in
//! a session afterwards; the remote helper runs the same checks and `git init` for a host path.
use crate::activity::{allocate_activity_id, ActivityStore};
use crate::dto::NativeRepositoryFailureKind;
use devmil_git::activity::{ActivityEvent, ActivityStatus};
use devmil_git::clone::InitialBranch;
use devmil_git::process::{ActivityGitRunner, GitProcessCommand, ProcessArgument};
use devmil_git::repository::{DiscoveryRequest, RepositoryDiscovery};
use devmil_git::types::RepositoryPath;
use std::path::Path;

/// Whether `name` is an acceptable initial branch.
#[must_use]
pub fn valid_initial_branch(name: &str) -> bool {
    InitialBranch::parse(name.to_owned()).is_ok()
}

/// Initializes a repository at `destination`, creating missing directories.
///
/// The destination must be missing or an empty directory that is not a symbolic link and not
/// already a repository. Git's activity goes to `activity`. The path is passed to Git as is, so a
/// Unix path need not be UTF-8.
///
/// # Errors
/// The failure kind a user is told about: `InvalidOptions` for an unacceptable branch or path,
/// `DestinationNotDirectory`, `ExistingRepository`, `DestinationNotEmpty`, `PermissionDenied`,
/// `Discovery` for an unreadable destination, `MissingGit` or `InitializationFailed`.
pub fn initialize_repository(
    destination: &Path,
    initial_branch: &str,
    bare: bool,
    activity: &ActivityStore,
) -> Result<(), NativeRepositoryFailureKind> {
    if !valid_initial_branch(initial_branch) {
        return Err(NativeRepositoryFailureKind::InvalidOptions);
    }
    if let Ok(metadata) = std::fs::symlink_metadata(destination) {
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(NativeRepositoryFailureKind::DestinationNotDirectory);
        }
        let Ok(repository_path) = RepositoryPath::new(destination) else {
            return Err(NativeRepositoryFailureKind::InvalidOptions);
        };
        let request = DiscoveryRequest {
            path: repository_path,
            discover_parents: false,
        };
        let mut discard = |_event: ActivityEvent| {};
        if RepositoryDiscovery::default()
            .discover(&request, &mut |command| {
                ActivityGitRunner::run(command, allocate_activity_id(), None, &mut discard)
            })
            .is_ok()
        {
            return Err(NativeRepositoryFailureKind::ExistingRepository);
        }
        match std::fs::read_dir(destination) {
            Ok(mut entries) => {
                if entries.next().is_some() {
                    return Err(NativeRepositoryFailureKind::DestinationNotEmpty);
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
                return Err(NativeRepositoryFailureKind::PermissionDenied);
            }
            Err(_) => return Err(NativeRepositoryFailureKind::Discovery),
        }
    }
    // The shared builder ends options with `--`, so a destination never reads as one.
    let branch = InitialBranch::parse(initial_branch.to_owned())
        .map_err(|_| NativeRepositoryFailureKind::InvalidOptions)?;
    let target = RepositoryPath::new(destination)
        .ok()
        .and_then(|path| devmil_git::clone::CloneDestination::new(path).ok())
        .ok_or(NativeRepositoryFailureKind::InvalidOptions)?;
    let arguments = devmil_git::clone::init_arguments(&target, bare, Some(&branch));
    let command =
        GitProcessCommand::git("git").args(arguments.into_iter().map(ProcessArgument::visible));
    let activity_sink = activity.sink();
    let mut sink = move |event| activity_sink(event);
    let id = crate::activity::allocate_operation_id(crate::activity::OperationIntent::Initialize);
    let init = ActivityGitRunner::run(command, id, None, &mut sink);
    match init.status {
        ActivityStatus::LaunchError { .. } => Err(NativeRepositoryFailureKind::MissingGit),
        ActivityStatus::Succeeded { .. } => Ok(()),
        _ => Err(NativeRepositoryFailureKind::InitializationFailed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root(name: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!(
            "gitlama-init-{name}-{}-{:?}",
            std::process::id(),
            allocate_activity_id()
        ));
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn creates_a_missing_destination_and_refuses_existing_or_non_empty_ones() {
        let parent = root("destinations");
        let activity = ActivityStore::default();
        let created = parent.join("nested").join("project");
        assert_eq!(
            initialize_repository(&created, "main", false, &activity),
            Ok(())
        );
        assert!(created.join(".git").is_dir());
        assert_eq!(
            initialize_repository(&created, "main", false, &activity),
            Err(NativeRepositoryFailureKind::ExistingRepository)
        );
        let full = parent.join("full");
        std::fs::create_dir(&full).unwrap();
        std::fs::write(full.join("file"), b"x").unwrap();
        assert_eq!(
            initialize_repository(&full, "main", false, &activity),
            Err(NativeRepositoryFailureKind::DestinationNotEmpty)
        );
        let file = parent.join("file");
        std::fs::write(&file, b"x").unwrap();
        assert_eq!(
            initialize_repository(&file, "main", true, &activity),
            Err(NativeRepositoryFailureKind::DestinationNotDirectory)
        );
        assert_eq!(
            initialize_repository(&parent.join("bad"), "bad..name", false, &activity),
            Err(NativeRepositoryFailureKind::InvalidOptions)
        );
        let bare = parent.join("bare.git");
        assert_eq!(
            initialize_repository(&bare, "trunk", true, &activity),
            Ok(())
        );
        assert!(bare.join("HEAD").is_file());
        std::fs::remove_dir_all(&parent).unwrap();
    }
}
