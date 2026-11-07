enum HistoryMutationKind { merge, cherryPick, revert }

enum HistoryMergeMode { fastForwardIfPossible, fastForwardOnly, noFastForward }

enum HistoryMutationFailureCode {
  invalidRequest,
  dirtyWorktree,
  detachedHead,
  activeOperation,
  publicationConfirmationRequired,
  stale,
  canceled,
  failed,
  read,
  mergeCommit,

  /// Local changes collide with an apply-only revert, which never sets them
  /// aside.
  localChangesOverlap,
}

/// What a revert does with the local changes.
enum HistoryLocalChanges {
  /// The worktree is clean.
  none,

  /// Git reverts with the local changes left where they are.
  inPlace,

  /// The local changes are saved in a stash, the revert runs and the changes
  /// are reapplied with their staging; conflicts go to the conflict resolver.
  setAside,
}

/// Local changes a revert set aside and how restoring them went. The stash
/// stays in Stashes as a recovery copy.
final class HistorySetAside {
  const HistorySetAside({
    required this.stashObjectId,
    required this.restored,
    required this.conflicted,
    required this.pending,
  });

  final String stashObjectId;

  /// The changes and their staging were restored.
  final bool restored;

  /// Restoring them stopped with conflicts.
  final bool conflicted;

  /// The revert stopped at conflicts first; the changes come back once it is
  /// continued or aborted.
  final bool pending;
}

enum HistoryMutationExecutionState {
  completed,
  alreadyContained,
  conflict,
  interrupted,
  stale,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

enum ConflictPredictionKind { merge, rebase }

final class ConflictPredictionTask {
  const ConflictPredictionTask({
    required this.token,
    required this.kind,
    required this.target,
  });

  final BigInt token;
  final ConflictPredictionKind kind;
  final String target;
}

final class HistoryMutationRequest {
  const HistoryMutationRequest({
    required this.kind,
    required this.targets,
    this.sourceName,
    this.mergeMode = HistoryMergeMode.fastForwardIfPossible,
    this.acknowledgePublishedHistory = false,
    this.noCommit = false,
  });

  final HistoryMutationKind kind;
  final List<String> targets;
  final List<int>? sourceName;
  final HistoryMergeMode mergeMode;
  final bool acknowledgePublishedHistory;
  final bool noCommit;
}

final class HistoryMutationPreview {
  const HistoryMutationPreview({
    required this.token,
    required this.kind,
    required this.arguments,
    required this.targets,
    required this.currentBranch,
    required this.currentHead,
    required this.publishedHistory,
    required this.alreadyContained,
    this.sourceName,
    this.noCommit = false,
    this.localChanges = HistoryLocalChanges.none,
    this.overlappingPaths = const [],
    this.stagedChanges = false,
  });

  final BigInt token;
  final HistoryMutationKind kind;
  final List<String> arguments;
  final List<String> targets;
  final List<int>? sourceName;
  final List<int> currentBranch;
  final String currentHead;
  final bool publishedHistory;
  final bool alreadyContained;
  final bool noCommit;
  final HistoryLocalChanges localChanges;

  /// Local paths that collide with the reverted commits, in status order.
  final List<List<int>> overlappingPaths;

  /// Some local change is staged, which Git refuses to revert over.
  final bool stagedChanges;
}

final class HistoryMutationExecutionResult {
  const HistoryMutationExecutionResult({
    required this.state,
    required this.activityIds,
    required this.conflictingPaths,
    this.failure,
    this.sequencer,
    this.setAside,
  });

  final HistoryMutationExecutionState state;
  final HistoryMutationFailureCode? failure;
  final List<String> activityIds;
  final List<List<int>> conflictingPaths;
  final HistoryMutationKind? sequencer;

  /// Present when the revert set local changes aside.
  final HistorySetAside? setAside;
}

final class ConflictPredictionResult {
  const ConflictPredictionResult({
    required this.kind,
    required this.target,
    required this.conflictingPaths,
    required this.analyzedCommits,
    required this.totalCommits,
    required this.complete,
    required this.activityIds,
    this.failure,
  });

  final ConflictPredictionKind kind;
  final String target;
  final List<List<int>> conflictingPaths;
  final int analyzedCommits;
  final int totalCommits;
  final bool complete;
  final List<String> activityIds;
  final HistoryMutationFailureCode? failure;
}

final class HistoryMutationException implements Exception {
  const HistoryMutationException(this.code);

  final HistoryMutationFailureCode code;
}
