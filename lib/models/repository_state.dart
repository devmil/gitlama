import 'settings.dart';

enum RepositoryPhase { unloaded, loading, ready, failed, closed }

enum RepositoryKind { worktree, bare }

enum HeadKind { attached, detached, unborn }

enum WorkingTreeState { clean, dirty, conflicted }

enum ChangeKind {
  unmodified,
  modified,
  typeChanged,
  added,
  deleted,
  renamed,
  copied,
  updatedButUnmerged,
}

enum StatusEntryKind { ordinary, rename, unmerged, untracked, ignored }

enum RepositoryOperationKind {
  merge,
  rebase,
  cherryPick,
  revert,
  bisect;

  /// Whether the paused operation can skip its current step. The native
  /// conflict snapshot's `canSkip` applies the same rule.
  bool get canSkip => switch (this) {
    rebase || cherryPick || revert => true,
    merge || bisect => false,
  };
}

final class RepositoryOperationState {
  const RepositoryOperationState({
    required this.kind,
    this.current,
    this.total,
  });
  final RepositoryOperationKind kind;
  final int? current;
  final int? total;
}

final class RepositoryStatusEntry {
  const RepositoryStatusEntry({
    required this.kind,
    required this.path,
    required this.index,
    required this.worktree,
    this.source,
  });

  final StatusEntryKind kind;
  final NativePathIdentity path;
  final NativePathIdentity? source;
  final ChangeKind index;
  final ChangeKind worktree;

  bool get conflicted => kind == StatusEntryKind.unmerged;
  bool get staged => index != ChangeKind.unmodified;
  bool get unstaged =>
      worktree != ChangeKind.unmodified || kind == StatusEntryKind.untracked;
}

final class RepositoryStatus {
  const RepositoryStatus({
    required this.workingTree,
    required this.ahead,
    required this.behind,
    required this.entries,
    required this.totalEntries,
    required this.entriesTruncated,
    required this.operations,
    this.branchName,
    this.headObjectId,
    this.upstream,
  });

  final WorkingTreeState workingTree;
  final List<int>? branchName;
  final String? headObjectId;
  final List<int>? upstream;
  final BigInt ahead;
  final BigInt behind;
  final List<RepositoryStatusEntry> entries;
  final BigInt totalEntries;
  final bool entriesTruncated;
  final List<RepositoryOperationState> operations;
}

final class RepositoryRefCounts {
  const RepositoryRefCounts({
    this.branches = 0,
    this.remotes = 0,
    this.tags = 0,
    this.stashes = 0,
    this.worktrees = 0,
  });

  final int branches;
  final int remotes;
  final int tags;
  final int stashes;
  final int worktrees;
}

final class RepositoryReference {
  const RepositoryReference({
    required this.name,
    required this.target,
    this.head = false,
    this.published = false,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.upstreamGone = false,
    this.fullName,
  });

  /// The name within its section: `main`, `v1.0`, or `main` of a remote.
  final List<int> name;

  /// The full reference name as the core reports it, such as
  /// `refs/heads/main`; null only in narrow test doubles. Use
  /// [ReferenceName] (`reference_name.dart`) rather than this directly.
  final List<int>? fullName;
  final String target;
  final bool head;
  final bool published;
  final List<int>? upstream;
  final int ahead;
  final int behind;
  final bool upstreamGone;
}

final class RepositoryRemote {
  const RepositoryRemote({
    required this.name,
    required this.displayUrl,
    this.branches = const [],
  });

  final List<int> name;
  final List<int> displayUrl;
  final List<RepositoryReference> branches;
}

final class RepositoryStash {
  const RepositoryStash({
    required this.selector,
    required this.objectId,
    required this.subject,
  });

  final List<int> selector;
  final String objectId;
  final List<int> subject;
}

final class RepositoryRefs {
  const RepositoryRefs({
    this.branches = const [],
    this.remotes = const [],
    this.tags = const [],
    this.stashes = const [],
    this.truncated = false,
  });

  final List<RepositoryReference> branches;
  final List<RepositoryRemote> remotes;
  final List<RepositoryReference> tags;
  final List<RepositoryStash> stashes;
  final bool truncated;
}

final class RepositoryIdentity {
  const RepositoryIdentity({
    required this.commonGitDir,
    required this.worktreeRoot,
    required this.gitDir,
    required this.kind,
    required this.headKind,
    this.headReference,
    this.headObjectId,
    required this.gitMajor,
    required this.gitMinor,
    required this.gitPatch,
  });

  final NativePathIdentity commonGitDir;
  final NativePathIdentity worktreeRoot;
  final NativePathIdentity gitDir;
  final RepositoryKind kind;
  final HeadKind headKind;
  final List<int>? headReference;
  final String? headObjectId;
  final int gitMajor;
  final int gitMinor;
  final int gitPatch;
}

enum RepositoryFailureCode {
  canceled,
  missingObject,
  tooLarge,
  invalidOutput,
  missingGit,
  unsupported,
  invalidOptions,
  discovery,
  read,
  watch,
  closed,
  capacity,
  invalidGeneration,
  unknownSession,
  staleGeneration,
  retiredSession,
  existingRepository,
  destinationNotEmpty,
  destinationNotDirectory,
  initializationFailed,
  timedOut,
  pathNotFound,
  permissionDenied,
  notRepository,

  /// A remote workspace whose connection is not established.
  remoteDisconnected,

  /// A remote workspace whose host, account, store or repository identity no
  /// longer matches; it needs an explicit reopen or rebind.
  remoteIdentityChanged,

  /// A remote write whose outcome is unknown; see
  /// [RemoteOutcomeUnknownException].
  remoteOutcomeUnknown,

  /// The host does not offer this command.
  remoteNotOffered,

  /// The host offers this change only when changes are allowed for it.
  remoteWriteNotPermitted,
}

final class RepositoryFailure {
  const RepositoryFailure(this.code);
  final RepositoryFailureCode code;
}

final class RepositorySnapshot {
  const RepositorySnapshot({
    required this.revision,
    required this.phase,
    this.failure,
    this.watchFailure,
    this.identity,
    this.status,
    this.statusFailure,
    this.refsFailure,
    this.refCounts = const RepositoryRefCounts(),
    this.refs = const RepositoryRefs(),
  });

  final BigInt revision;
  final RepositoryPhase phase;
  final RepositoryFailure? failure;
  final RepositoryFailure? watchFailure;
  final RepositoryIdentity? identity;
  final RepositoryStatus? status;
  final RepositoryFailure? statusFailure;
  final RepositoryFailure? refsFailure;
  final RepositoryRefCounts refCounts;
  final RepositoryRefs refs;

  /// This snapshot with the given parts replaced; every other field, including
  /// ones added later, carries over.
  RepositorySnapshot copyWith({
    RepositoryIdentity? identity,
    RepositoryStatus? status,
    RepositoryRefCounts? refCounts,
    RepositoryRefs? refs,
  }) => RepositorySnapshot(
    revision: revision,
    phase: phase,
    failure: failure,
    watchFailure: watchFailure,
    identity: identity ?? this.identity,
    status: status ?? this.status,
    statusFailure: statusFailure,
    refsFailure: refsFailure,
    refCounts: refCounts ?? this.refCounts,
    refs: refs ?? this.refs,
  );
}

/// Which backend owns a repository session.
enum RepositoryBackendKind { local, remote }

final class RepositorySessionIdentity {
  const RepositorySessionIdentity({
    required this.nativeId,
    required this.generation,
    this.backend = RepositoryBackendKind.local,
  });

  /// Unique across backends: remote sessions use identifiers the routing
  /// repository allocates, never the helper's own numbers.
  final BigInt nativeId;
  final int generation;
  final RepositoryBackendKind backend;
}

enum RepositorySessionEventKind {
  snapshot,
  resynchronize,
  readCompleted,
  watchOverflow,
}

final class RepositorySessionEvent {
  const RepositorySessionEvent({
    required this.kind,
    this.snapshot,
    this.readId,
    this.cacheHit = false,
    this.watchOverflowRevision,
  });

  final RepositorySessionEventKind kind;
  final RepositorySnapshot? snapshot;
  final BigInt? readId;
  final bool cacheHit;
  final BigInt? watchOverflowRevision;
}

final class RepositorySessionState {
  const RepositorySessionState({
    required this.identity,
    required this.snapshot,
    this.transportFailure,
  });

  final RepositorySessionIdentity identity;
  final RepositorySnapshot snapshot;
  final RepositoryFailure? transportFailure;

  RepositorySessionState copyWith({
    RepositorySnapshot? snapshot,
    RepositoryFailure? transportFailure,
  }) => RepositorySessionState(
    identity: identity,
    snapshot: snapshot ?? this.snapshot,
    transportFailure: transportFailure,
  );
}

final class RepositorySessionException implements Exception {
  const RepositorySessionException(this.failure);
  final RepositoryFailure failure;

  @override
  String toString() => 'RepositorySessionException(${failure.code.name})';
}

/// A remote write whose outcome could not be established: the connection
/// ended or the helper could not confirm it. It waits for review under Remote
/// changes and is never retried automatically.
///
/// It is a [RepositorySessionException], so every handler that catches
/// repository failures also catches it; handlers that can name the unknown
/// outcome catch this type first.
final class RemoteOutcomeUnknownException extends RepositorySessionException {
  const RemoteOutcomeUnknownException()
    : super(
        const RepositoryFailure(RepositoryFailureCode.remoteOutcomeUnknown),
      );

  @override
  String toString() => 'RemoteOutcomeUnknownException';
}
