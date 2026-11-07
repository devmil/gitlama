enum TransferKind { fetch, pull, push, pushTag, deleteTag, deleteBranch }

enum PullStrategy { fastForwardOnly, fastForwardIfPossible, rebase }

enum TransferFailureCode {
  invalidRequest,
  detachedHead,
  missingUpstream,
  dirtyWorktree,
  conflictedWorktree,
  stale,
  authentication,
  credentialBrokerUnavailable,
  hostKey,
  rejected,
  timedOut,
  canceled,
  missingGit,
  read,
  missingObject,

  /// Another Git process held one of the repository's lock files.
  locked,
}

enum TransferExecutionState {
  completed,
  failed,
  stale,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class TransferRequest {
  const TransferRequest({
    required this.kind,
    this.remote,
    this.branch,
    this.pullStrategy = PullStrategy.fastForwardOnly,
    this.allowDirty = false,
    this.stashBeforePull = false,
    this.forceWithLease = false,
    this.setUpstream = false,
    this.refetch = false,
    this.prune = true,
  });

  final TransferKind kind;
  final String? remote;
  final String? branch;
  final PullStrategy pullStrategy;
  final bool allowDirty;
  final bool stashBeforePull;
  final bool forceWithLease;
  final bool setUpstream;
  final bool refetch;

  /// For a fetch: remove remote-tracking branches the remote deleted.
  final bool prune;

  /// This request with the given choices changed.
  TransferRequest copyWith({bool? prune}) => TransferRequest(
    kind: kind,
    remote: remote,
    branch: branch,
    pullStrategy: pullStrategy,
    allowDirty: allowDirty,
    stashBeforePull: stashBeforePull,
    forceWithLease: forceWithLease,
    setUpstream: setUpstream,
    refetch: refetch,
    prune: prune ?? this.prune,
  );
}

final class TransferPreview {
  const TransferPreview({
    required this.token,
    required this.kind,
    required this.remote,
    required this.branch,
    required this.arguments,
    required this.ahead,
    required this.behind,
    required this.dirty,
    required this.expectedRemoteObjectId,
    required this.forceWithLease,
  });

  final BigInt token;
  final TransferKind kind;
  final String remote;
  final String? branch;
  final List<String> arguments;
  final BigInt ahead;
  final BigInt behind;
  final bool dirty;
  final String? expectedRemoteObjectId;
  final bool forceWithLease;
}

final class TransferCredentials {
  const TransferCredentials({this.username, this.password, this.token});

  final String? username;
  final String? password;
  final String? token;
}

/// A failure mechanism recognised from Git's diagnostics.
enum TransferDiagnosisKind {
  hostKey,
  missingObject,
  authentication,
  lockConflict,

  /// Refs differing only in letter case share one file on a case-insensitive
  /// file system, so Git cannot update both at once.
  refCaseCollision,
  remoteAhead,
  staleLease,
}

/// What Git's diagnostics showed about a failed transfer.
final class TransferDiagnosis {
  const TransferDiagnosis({
    required this.kind,
    this.reference,
    this.related = const [],
  });

  final TransferDiagnosisKind kind;

  /// The full ref name the failure is about, such as the ref Git could not lock.
  final String? reference;

  /// For a case collision: the other spellings of [reference].
  final List<String> related;
}

/// A named recovery stash is kept until the user reviews and removes it.
final class PullStashResult {
  const PullStashResult({
    required this.objectId,
    required this.pullCompleted,
    required this.reapplyCompleted,
    required this.conflicted,
  });
  final String objectId;
  final bool pullCompleted;
  final bool reapplyCompleted;
  final bool conflicted;
}

final class TransferExecutionResult {
  const TransferExecutionResult({
    required this.state,
    this.failure,
    this.diagnosis,
    this.stash,
    this.activityId,
    required this.ahead,
    required this.behind,
  });

  final TransferExecutionState state;
  final TransferFailureCode? failure;
  final TransferDiagnosis? diagnosis;
  final PullStashResult? stash;
  final BigInt? activityId;
  final BigInt ahead;
  final BigInt behind;
}

final class TransferException implements Exception {
  const TransferException(this.code);

  final TransferFailureCode code;
}
