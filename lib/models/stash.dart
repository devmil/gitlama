enum StashKind {
  push,
  apply,
  pop,
  drop,
  rename,
  autoStashCheckout,
  stashCheckoutCommit,
  autoStashCheckoutCommit,
}

enum StashFailureCode {
  invalidRequest,
  nothingToStash,
  missingStash,
  stale,
  conflict,
  canceled,
  timedOut,
  missingGit,
  failed,
  read,
  write,
}

enum StashExecutionState {
  completed,
  failed,
  stale,
  conflict,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class StashRequest {
  const StashRequest({
    required this.kind,
    this.message,
    this.selector,
    this.objectId,
    this.paths = const [],
    this.includeUntracked = false,
    this.keepIndex = false,
    this.targetBranch,
  });

  final StashKind kind;
  final String? message;
  final String? selector;

  /// Stash identity for entry actions; exact checkout target for commit checkout actions.
  final String? objectId;
  final List<List<int>> paths;
  final bool includeUntracked;
  final bool keepIndex;
  final String? targetBranch;
}

final class StashPreview {
  const StashPreview({
    required this.token,
    required this.kind,
    required this.commands,
    required this.affectedPaths,
    required this.includesUntracked,
    required this.keepsIndex,
    required this.destructive,
    this.selectedObjectId,
    this.targetBranch,
  });

  final BigInt token;
  final StashKind kind;
  final List<List<String>> commands;
  final int affectedPaths;
  final bool includesUntracked;
  final bool keepsIndex;
  final String? selectedObjectId;
  final String? targetBranch;
  final bool destructive;
}

final class StashExecutionResult {
  const StashExecutionResult({
    required this.state,
    required this.activityIds,
    required this.stashCreated,
    required this.checkoutCompleted,
    required this.reapplyCompleted,
    required this.stashRetained,
    this.failure,
  });

  final StashExecutionState state;
  final StashFailureCode? failure;
  final List<String> activityIds;
  final bool stashCreated;
  final bool checkoutCompleted;
  final bool reapplyCompleted;
  final bool stashRetained;
}

final class StashException implements Exception {
  const StashException(this.code);

  final StashFailureCode code;
}
