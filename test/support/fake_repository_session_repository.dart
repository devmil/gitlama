import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/repository_lock.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/status_acceleration.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/repository_session_service.dart';

RepositorySessionService fakeRepositorySessionService({
  RepositorySnapshot? snapshot,
}) => RepositorySessionService(FakeRepositorySessionRepository(snapshot));

/// The same fake as a repository, for services built with more
/// collaborators. [executeCommitError], [executeStagingError] and
/// [executeDiscardError] are thrown by those calls when set.
RepositorySessionRepository fakeRepositorySessionRepository({
  RepositorySnapshot? snapshot,
  Object? executeCommitError,
  Object? executeStagingError,
  Object? executeDiscardError,
}) => FakeRepositorySessionRepository(
  snapshot,
  executeCommitError: executeCommitError,
  executeStagingError: executeStagingError,
  executeDiscardError: executeDiscardError,
);

/// A repository whose session opens with [snapshot] and answers every read
/// with empty data. Tests extend it to script the families they exercise.
class FakeRepositorySessionRepository implements RepositorySessionRepository {
  FakeRepositorySessionRepository(
    this.snapshot, {
    this.executeCommitError,
    this.executeStagingError,
    this.executeDiscardError,
  });

  final RepositorySnapshot? snapshot;
  final Object? executeCommitError;
  final Object? executeStagingError;
  final Object? executeDiscardError;
  @override
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) async => const ActivityPage(records: [], evictedThroughId: null);

  @override
  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) async => const ActivityPage(records: [], evictedThroughId: null);

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = 512,
  }) async => HistoryPage(
    requestId: BigInt.one,
    complete: complete,
    totalRows: 0,
    offset: 0,
    rows: const [],
    laneCount: 0,
    payloadBytes: 0,
  );

  @override
  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) => loadHistory(identity, complete: true, maximumRows: maximumRows);

  @override
  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = 512,
  }) => loadHistory(identity, complete: true, maximumRows: maximumRows);

  @override
  Future<HistoryPage> selectHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String? objectId,
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    required int offset,
    int maximumRows = 512,
  }) => historyPage(identity, requestId: requestId, offset: offset);

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = 512,
  }) async => _emptyDiff;

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => _emptyDiff;

  @override
  Future<DiffPage> workingDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = 512,
  }) async => _emptyDiff;

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => _emptyDiff;

  @override
  Future<StagingPhase?> stagingPhase(
    RepositorySessionIdentity identity,
  ) async => null;

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) async {
    if (executeStagingError case final error?) throw error;
    return const StagingExecutionResult(state: StagingExecutionState.completed);
  }

  @override
  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) async => DiffSearchResult(
    requestId: requestId,
    matches: const [],
    totalMatches: 0,
    truncated: false,
  );

  @override
  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  }) async => null;

  @override
  Future<List<int>> diffHunks(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumPositions = 10000,
  }) async => const [];

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => const ImageDiffContent();

  @override
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => const ImageDiffContent();

  @override
  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  }) async => const [];

  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) async => const IndexLockInspection(present: false);

  @override
  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {}

  /// What [statusAcceleration] reports; [enableStatusAcceleration] turns
  /// on what it lacks.
  StatusAcceleration acceleration = const StatusAcceleration(
    untrackedCache: true,
    fsmonitor: false,
    fsmonitorAvailable: false,
  );
  int accelerationReads = 0;
  int accelerationEnables = 0;

  @override
  Future<StatusAcceleration> statusAcceleration(
    RepositorySessionIdentity identity,
  ) async {
    accelerationReads += 1;
    return acceleration;
  }

  @override
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  ) async {
    accelerationEnables += 1;
    return acceleration = StatusAcceleration(
      untrackedCache: true,
      fsmonitor: acceleration.fsmonitorAvailable,
      fsmonitorAvailable: acceleration.fsmonitorAvailable,
      lastScan: acceleration.lastScan,
    );
  }

  /// What [inspectRepositoryLocks] lists.
  RepositoryLockInspection repositoryLocks = const RepositoryLockInspection(
    locks: [],
  );
  final List<BigInt> removedRepositoryLocks = [];

  @override
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  ) async => repositoryLocks;

  @override
  Future<bool> removeRepositoryLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    removedRepositoryLocks.add(token);
    return true;
  }

  @override
  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = 512,
  }) => historyPage(identity, requestId: requestId, offset: offset);

  @override
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = 512,
  }) async => null;

  @override
  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = 512,
  }) => historyPage(identity, requestId: requestId, offset: offset);

  @override
  Future<ReflogPage> reflog(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximumRows = 256,
  }) async => const ReflogPage(entries: []);

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) async => CommitInspection(
    detail: CommitIdentityDetail(
      commit: commit,
      tree: commit,
      parents: const [],
      author: const [],
      authorTime: 0,
      authorTimezone: const [],
      committer: const [],
      committerTime: 0,
      committerTimezone: const [],
      message: const [],
    ),
    files: const [],
  );

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) async => CommitTreePage(commit: commit, entries: const []);

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) async => const [];

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) async =>
      const PathHistoryPage(entries: [], renameHops: 0, incomplete: false);

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) async => const RangeHistoryResult(entries: [], incomplete: false);

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = 512,
  }) async => BlamePage(
    requestId: BigInt.one,
    revision: revision,
    path: path,
    totalRows: 0,
    offset: 0,
    rows: const [],
  );

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => BlamePage(
    requestId: requestId,
    revision: '',
    path: const [],
    totalRows: 0,
    offset: offset,
    rows: const [],
  );

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) async => RestorePreview(
    token: BigInt.one,
    commit: commit,
    path: path,
    sourceBytes: const [],
  );

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) async => const RestoreResult(state: RestoreState.restored);

  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => throw UnimplementedError();

  @override
  Future<CommitTools> commitTools(RepositorySessionIdentity identity) async =>
      const CommitTools();

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) async => CommitPreview(
    token: BigInt.one,
    warnings: const [],
    arguments: const ['commit', '--file=-'],
  );

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    if (executeCommitError case final error?) throw error;
    return const CommitExecutionResult(state: CommitExecutionState.completed);
  }

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) async => DiscardPreview(
    token: BigInt.one,
    kind: request.kind,
    fileCount: request.paths.length,
    arguments: const [],
  );

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    if (executeDiscardError case final error?) throw error;
    return const DiscardExecutionResult(state: DiscardExecutionState.completed);
  }

  @override
  Future<bool> close(RepositorySessionIdentity identity) async => true;

  @override
  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  }) async => const [];

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  open(String path, int generation) async => (
    identity: RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: generation,
    ),
    snapshot:
        snapshot ??
        RepositorySnapshot(
          revision: BigInt.zero,
          phase: RepositoryPhase.unloaded,
        ),
  );

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) =>
      open('native-identity', generation);

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  }) => open(path, generation);

  @override
  Future<void> refresh(RepositorySessionIdentity identity) async {}
}

final _emptyDiff = DiffPage(
  requestId: BigInt.zero,
  layout: DiffViewLayout.unified,
  totalRows: 0,
  offset: 0,
  rows: [],
  payloadBytes: 0,
);
