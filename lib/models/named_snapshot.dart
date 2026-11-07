enum NamedSnapshotState { ready, missing, corrupt }

enum NamedSnapshotFailureCode {
  invalidRequest,
  nothingToCapture,
  missing,
  corrupt,
  dirtyConflict,
  activeOperation,
  stale,
  conflict,
  canceled,
  tooLarge,
  read,
  write,
  git,
}

final class NamedSnapshot {
  const NamedSnapshot({
    required this.id,
    required this.name,
    required this.createdAtUnixMs,
    required this.baseOid,
    required this.objectId,
    required this.stagedCount,
    required this.unstagedCount,
    required this.untrackedCount,
    required this.includesUntracked,
    required this.keepsIndex,
    required this.state,
    this.baseRef,
  });

  final BigInt id;
  final String name;
  final BigInt createdAtUnixMs;
  final List<int>? baseRef;
  final String baseOid;
  final String objectId;
  final int stagedCount;
  final int unstagedCount;
  final int untrackedCount;
  final bool includesUntracked;
  final bool keepsIndex;
  final NamedSnapshotState state;
}

final class NamedSnapshotPage {
  const NamedSnapshotPage({
    required this.entries,
    required this.total,
    this.nextOffset,
  });

  final List<NamedSnapshot> entries;
  final int total;
  final int? nextOffset;
}

enum NamedSnapshotExecutionState {
  completed,
  conflict,
  stale,
  canceled,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class NamedSnapshotExecutionResult {
  const NamedSnapshotExecutionResult({
    required this.state,
    required this.conflictingPaths,
    required this.activityIds,
    this.snapshot,
    this.recoveryRef,
    this.failure,
  });

  final NamedSnapshotExecutionState state;
  final NamedSnapshot? snapshot;
  final List<int>? recoveryRef;
  final List<List<int>> conflictingPaths;
  final List<String> activityIds;
  final NamedSnapshotFailureCode? failure;
}

final class NamedSnapshotRestorePreview {
  const NamedSnapshotRestorePreview({
    required this.token,
    required this.snapshot,
    required this.replacementPaths,
    required this.replacementPathsTruncated,
    required this.replacesIndex,
    required this.replacesWorktree,
  });

  final BigInt token;
  final NamedSnapshot snapshot;
  final List<List<int>> replacementPaths;
  final bool replacementPathsTruncated;
  final bool replacesIndex;
  final bool replacesWorktree;
}

final class NamedSnapshotException implements Exception {
  const NamedSnapshotException(this.code);

  final NamedSnapshotFailureCode code;
}
