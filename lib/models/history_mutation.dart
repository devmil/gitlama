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
}

final class HistoryMutationExecutionResult {
  const HistoryMutationExecutionResult({
    required this.state,
    required this.activityIds,
    required this.conflictingPaths,
    this.failure,
    this.sequencer,
  });

  final HistoryMutationExecutionState state;
  final HistoryMutationFailureCode? failure;
  final List<String> activityIds;
  final List<List<int>> conflictingPaths;
  final HistoryMutationKind? sequencer;
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
