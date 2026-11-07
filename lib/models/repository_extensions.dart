import 'settings.dart';

enum RepositoryExtensionFailureCode {
  invalidRequest,
  unavailable,
  dirty,
  locked,
  currentWorktree,
  stale,
  canceled,
  tooLarge,
  read,
  git,
}

enum SubmoduleState {
  atRecordedCommit,
  differentCommit,
  uninitialized,
  conflicted,
}

final class SubmoduleEntry {
  const SubmoduleEntry({
    required this.path,
    required this.commit,
    required this.state,
  });

  final List<int> path;
  final String commit;
  final SubmoduleState state;
}

final class WorktreeEntry {
  const WorktreeEntry({
    required this.worktreeRoot,
    required this.gitDir,
    required this.commonGitDir,
    required this.locked,
    required this.prunable,
    required this.current,
    this.head,
    this.branch,
  });

  final NativePathIdentity worktreeRoot;
  final NativePathIdentity gitDir;
  final NativePathIdentity commonGitDir;
  final String? head;
  final List<int>? branch;
  final bool locked;
  final bool prunable;
  final bool current;
}

enum LfsPathState { pointer, materialized, missing }

final class LfsPointer {
  const LfsPointer({required this.oidSha256, required this.size});

  final String oidSha256;
  final BigInt size;
}

final class LfsEntry {
  const LfsEntry({required this.path, required this.state, this.pointer});

  final List<int> path;
  final LfsPathState state;
  final LfsPointer? pointer;
}

final class RepositoryExtensionInventory {
  const RepositoryExtensionInventory({
    required this.worktrees,
    required this.submodules,
    required this.lfsAvailable,
    required this.lfsUnavailableReason,
    required this.lfsEntries,
    required this.activityIds,
  });

  final List<WorktreeEntry> worktrees;
  final List<SubmoduleEntry> submodules;
  final bool lfsAvailable;
  final bool lfsUnavailableReason;
  final List<LfsEntry> lfsEntries;
  final List<String> activityIds;
}

enum RepositoryExtensionMutationKind {
  submoduleInit,
  submoduleUpdate,
  lfsTrack,
  lfsUntrack,
  lfsPull,
  worktreeCreate,
  worktreeDelete,

  /// Appends [RepositoryExtensionMutationRequest.pattern] to the worktree's
  /// top-level `.gitignore`.
  ignoreAdd,
}

final class RepositoryExtensionMutationRequest {
  const RepositoryExtensionMutationRequest({
    required this.kind,
    this.path,
    this.worktreeRoot,
    this.pattern,
    this.reference,
  });

  final RepositoryExtensionMutationKind kind;
  final List<int>? path;
  final NativePathIdentity? worktreeRoot;
  final String? pattern;
  final String? reference;
}

enum RepositoryExtensionMutationState {
  completed,
  failed,
  canceled,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class RepositoryExtensionMutationResult {
  const RepositoryExtensionMutationResult({
    required this.state,
    required this.activityIds,
    this.failure,
  });

  final RepositoryExtensionMutationState state;
  final List<String> activityIds;
  final RepositoryExtensionFailureCode? failure;

  /// The failure to show, or null. An uncertain outcome is not a failure:
  /// the caller asks the user to inspect the repository instead.
  RepositoryExtensionFailureCode? get reportedFailure =>
      state == RepositoryExtensionMutationState.outcomeUncertain
      ? null
      : failure ??
            switch (state) {
              RepositoryExtensionMutationState.failed =>
                RepositoryExtensionFailureCode.git,
              RepositoryExtensionMutationState.canceled =>
                RepositoryExtensionFailureCode.canceled,
              RepositoryExtensionMutationState.completed ||
              RepositoryExtensionMutationState.reconciledWithWarning ||
              // Not a failure: the caller asks the user to inspect the repository.
              RepositoryExtensionMutationState.outcomeUncertain => null,
            };
}

final class RepositoryExtensionException implements Exception {
  const RepositoryExtensionException(this.code);

  final RepositoryExtensionFailureCode code;
}
