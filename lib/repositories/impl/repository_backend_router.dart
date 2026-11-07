import '../../models/activity.dart';
import '../../models/advanced_rebase.dart';
import '../../models/commit.dart';
import '../../models/commit_archive.dart';
import '../../models/conflict.dart';
import '../../models/discard.dart';
import '../../models/index_lock.dart';
import '../../models/repository_lock.dart';
import '../../models/history.dart';
import '../../models/history_mutation.dart';
import '../../models/integrations.dart';
import '../../models/rebase.dart';
import '../../models/named_snapshot.dart';
import '../../models/inspection.dart';
import '../../models/diff.dart';
import '../../models/diff_renderer.dart';
import '../../models/diff_syntax.dart';
import '../../models/patch.dart';
import '../../models/power_tools.dart';
import '../../models/repository_state.dart';
import '../../models/status_acceleration.dart';
import '../../models/settings.dart';
import '../../models/stash.dart';
import '../../models/ref_mutation.dart';
import '../../models/transfer.dart';
import '../../models/clone_attempt.dart';
import '../../models/repository_extensions.dart';

import '../../models/remote_workspace.dart';
import '../remote_session_repository.dart';
import '../repository_session_repository.dart';

/// Routes repository session calls to the backend that owns each session.
///
/// Routing follows the typed session identity, never a path or label. Local
/// sessions reach the native library unchanged. Remote sessions reach their
/// connection's helper for the remote read surface and the write families
/// the connection negotiated. Calls that need this computer's tools,
/// credentials or prompts fail on a remote session with an unsupported
/// failure before anything is sent.
final class RepositoryBackendRouter implements CompleteSessionBackend {
  RepositoryBackendRouter(this._local, this._remotes);

  final RepositorySessionRepository _local;

  /// The surfaces of the live remote connections.
  final RemoteSessionDirectory _remotes;

  /// The connection surface of each open remote session.
  final Map<BigInt, RemoteSessionSurface> _remoteSessions = {};

  T _localAs<T>() {
    final local = _local;
    if (local is T) return local as T;
    throw const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.invalidOptions),
    );
  }

  bool _isRemote(RepositorySessionIdentity identity) =>
      identity.backend == RepositoryBackendKind.remote;

  /// The backend that serves [identity]: its host or this computer.
  RepositorySessionRepository _for(RepositorySessionIdentity identity) =>
      _isRemote(identity) ? _remote(identity) : _local;

  /// The [T] family of the backend that serves [identity].
  T _familyFor<T>(RepositorySessionIdentity identity) =>
      _isRemote(identity) ? _remoteAs<T>(identity) : _localAs<T>();

  RepositorySessionRepository _remote(RepositorySessionIdentity identity) =>
      _remoteSessions[identity.nativeId]?.sessions ??
      const _DisconnectedRepository();

  T _remoteAs<T>(RepositorySessionIdentity identity) {
    final remote = _remote(identity);
    // A disconnected session reports its connection for every family,
    // not only for those the fallback implements.
    if (remote is _DisconnectedRepository) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.remoteDisconnected),
      );
    }
    if (remote is T) return remote as T;
    throw const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
    );
  }

  /// Where a remote session's content is read: its host.
  ChangeSourceRepositorySessionRepository _remoteSource(
    RepositorySessionIdentity identity,
  ) => _remoteAs<ChangeSourceRepositorySessionRepository>(identity);

  /// Where a remote session's content is decoded, compared and rendered:
  /// this computer, since the helper runs no image decoder and no local
  /// tool.
  ChangeSourceRepositorySessionRepository get _detached =>
      _localAs<ChangeSourceRepositorySessionRepository>();

  /// The largest side an external diff compares, as for a local repository.
  static const _externalDiffBytes = 64 * 1024 * 1024;

  Future<ImageDiffContent> _remoteImage(
    Future<ChangeSourceBytes> source,
  ) async => _detached.decodeImage(await source);

  /// Fails asynchronously, like every other repository call: the command is
  /// not offered for a repository on another computer.
  Future<Never> _unsupported() => Future.error(
    const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
    ),
  );

  /// Whether [identity] names a live remote session.
  bool isLiveRemote(RepositorySessionIdentity identity) =>
      _remoteSessions.containsKey(identity.nativeId);

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  open(String path, int generation) => _local.open(path, generation);

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  }) => _local.initialize(
    path,
    generation,
    initialBranch: initialBranch,
    bare: bare,
  );

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) async {
    final authority = identity.remote;
    if (authority == null) return _local.openIdentity(identity, generation);
    final surface = _remotes.surfaceFor(authority);
    if (surface == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.remoteDisconnected),
      );
    }
    // The connection's adapter marks the session and its paths as remote.
    final opened = await surface.sessions.openIdentity(identity, generation);
    _remoteSessions[opened.identity.nativeId] = surface;
    return opened;
  }

  @override
  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  }) async {
    if (!_isRemote(identity)) {
      return _local.events(identity, maximumEvents: maximumEvents);
    }
    final surface = _remoteSessions[identity.nativeId];
    if (surface == null) return const [];
    return surface.sessions.events(identity, maximumEvents: maximumEvents);
  }

  @override
  Future<bool> close(RepositorySessionIdentity identity) async {
    if (!_isRemote(identity)) return _local.close(identity);
    final surface = _remoteSessions.remove(identity.nativeId);
    if (surface == null) return true;
    try {
      return await surface.sessions.close(identity);
    } on RepositorySessionException {
      return true;
    }
  }

  // RepositorySessionRepository
  @override
  Future<void> refresh(RepositorySessionIdentity identity) =>
      _for(identity).refresh(identity);

  @override
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) => _for(identity).activity(identity, maximumRecords: maximumRecords);

  @override
  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) => _for(identity).activityRecord(identity, activityId);

  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) => _for(identity).inspectIndexLock(identity);

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).loadHistory(
    identity,
    complete: complete,
    otherRefs: otherRefs,
    maximumRows: maximumRows,
  );

  @override
  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).historyPage(
    identity,
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(
    identity,
  ).completeHistory(identity, requestId: requestId, maximumRows: maximumRows);

  @override
  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  }) => _for(
    identity,
  ).historyMetadata(identity, requestId: requestId, objectIds: objectIds);

  @override
  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _for(identity).removeIndexLock(identity, token);

  @override
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  ) => _for(identity).inspectRepositoryLocks(identity);

  @override
  Future<StatusAcceleration> statusAcceleration(
    RepositorySessionIdentity identity,
  ) => _for(identity).statusAcceleration(identity);

  @override
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  ) => _for(identity).enableStatusAcceleration(identity);

  @override
  Future<bool> removeRepositoryLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _for(identity).removeRepositoryLock(identity, token);

  @override
  Future<HistoryPage> selectHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String? objectId,
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).selectHistory(
    identity,
    requestId: requestId,
    objectId: objectId,
    toggle: toggle,
    reveal: reveal,
    focus: focus,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).queryHistory(
    identity,
    requestId: requestId,
    query: query,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).filterHistoryBranches(
    identity,
    requestId: requestId,
    filter: filter,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).collapseHistory(
    identity,
    requestId: requestId,
    objectId: objectId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<ReflogPage> reflog(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximumRows = 256,
  }) =>
      _for(identity).reflog(identity, offset: offset, maximumRows: maximumRows);

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) => _for(
    identity,
  ).inspectCommit(identity, commit: commit, firstParent: firstParent);

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) => _for(identity).commitTree(
    identity,
    commit: commit,
    directory: directory,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) => _for(identity).commitFileContent(identity, commit: commit, path: path);

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) => _for(identity).pathHistory(
    identity,
    revision: revision,
    path: path,
    directory: directory,
    offset: offset,
    maximumRows: maximumRows,
    renameHopsBefore: renameHopsBefore,
  );

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) => _for(identity).rangeHistory(
    identity,
    revision: revision,
    path: path,
    firstLine: firstLine,
    lastLine: lastLine,
    maximumRows: maximumRows,
  );

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).blame(
    identity,
    revision: revision,
    path: path,
    firstLine: firstLine,
    lastLine: lastLine,
    detectMoves: detectMoves,
    detectCopies: detectCopies,
    maximumRows: maximumRows,
  );

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).blamePage(
    identity,
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) => _for(
    identity,
  ).previewRestore(identity, commit: commit, path: path, byteLimit: byteLimit);

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) => _for(identity).restoreFile(identity, token: token);

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).commitDiff(
    identity,
    commit: commit,
    firstParent: firstParent,
    options: options,
    maximumRows: maximumRows,
  );

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).diffPage(
    identity,
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

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
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).workingDiff(
    identity,
    side: side,
    oldPath: oldPath,
    newPath: newPath,
    contextLines: contextLines,
    whitespace: whitespace,
    layout: layout,
    forceText: forceText,
    maximumRows: maximumRows,
  );

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _for(identity).workingDiffPage(
    identity,
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<StagingPhase?> stagingPhase(RepositorySessionIdentity identity) =>
      _for(identity).stagingPhase(identity);

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) => _for(identity).executeStaging(identity, request);

  @override
  Future<CommitTools> commitTools(RepositorySessionIdentity identity) =>
      _for(identity).commitTools(identity);

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) => _for(identity).previewCommit(identity, request);

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _for(identity).executeCommit(identity, token);

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) => _for(identity).previewDiscard(identity, request);

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _for(identity).executeDiscard(identity, token);

  @override
  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) => _for(identity).searchDiff(
    identity,
    requestId: requestId,
    query: query,
    caseSensitive: caseSensitive,
    maximumMatches: maximumMatches,
  );

  @override
  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  }) => _for(identity).diffSelectionPatch(
    identity,
    requestId: requestId,
    working: working,
    rowIds: rowIds,
  );

  @override
  Future<List<int>> diffHunks(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumPositions = 10000,
  }) => _for(identity).diffHunks(
    identity,
    requestId: requestId,
    maximumPositions: maximumPositions,
  );

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) => _isRemote(identity)
      ? _remoteImage(
          _remoteSource(identity).changeSource(
            identity,
            oldRevision: oldRevision,
            newRevision: newRevision,
            oldPath: oldPath,
            newPath: newPath,
            byteLimit: byteLimit,
          ),
        )
      : _local.imageDiff(
          identity,
          oldRevision: oldRevision,
          newRevision: newRevision,
          oldPath: oldPath,
          newPath: newPath,
          byteLimit: byteLimit,
        );

  @override
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) => _isRemote(identity)
      ? _remoteImage(
          _remoteSource(identity).workingChangeSource(
            identity,
            side: side,
            oldPath: oldPath,
            newPath: newPath,
            byteLimit: byteLimit,
          ),
        )
      : _local.workingImageDiff(
          identity,
          side: side,
          oldPath: oldPath,
          newPath: newPath,
          byteLimit: byteLimit,
        );

  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) => _for(identity).previewRefMutation(identity, request);

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _for(identity).executeRefMutation(identity, token);

  // PatchRepositorySessionRepository
  @override
  Future<PatchExportPreview> previewPatchExport(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async {
    if (!_isRemote(identity)) {
      return _localAs<PatchRepositorySessionRepository>().previewPatchExport(
        identity,
        request,
      );
    }
    // The host builds the patch; it is saved on this computer.
    final content = await patchExportContent(identity, request);
    return previewPatchSave(
      content,
      destinationDirectory: request.destinationDirectory,
      overwrite: request.overwrite,
    );
  }

  @override
  Future<PatchExportExecutionResult> executePatchExport(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? executePatchSave(token)
      : _localAs<PatchRepositorySessionRepository>().executePatchExport(
          identity,
          token,
        );

  @override
  Future<PatchExportContent> patchExportContent(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) => _familyFor<PatchRepositorySessionRepository>(
    identity,
  ).patchExportContent(identity, request);

  @override
  Future<PatchExportPreview> previewPatchSave(
    PatchExportContent content, {
    required String destinationDirectory,
    required bool overwrite,
  }) => _localAs<PatchRepositorySessionRepository>().previewPatchSave(
    content,
    destinationDirectory: destinationDirectory,
    overwrite: overwrite,
  );

  @override
  Future<PatchExportExecutionResult> executePatchSave(BigInt token) =>
      _localAs<PatchRepositorySessionRepository>().executePatchSave(token);

  @override
  Future<PatchApplyPreview> previewPatchApply(
    RepositorySessionIdentity identity,
    String patchPath,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PatchRepositorySessionRepository>(identity)
              : _localAs<PatchRepositorySessionRepository>())
          .previewPatchApply(identity, patchPath);

  @override
  Future<PatchApplyExecutionResult> executePatchApply(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PatchRepositorySessionRepository>(identity)
              : _localAs<PatchRepositorySessionRepository>())
          .executePatchApply(identity, token);

  // TransferRepositorySessionRepository
  @override
  Future<TransferPreview> previewTransfer(
    RepositorySessionIdentity identity,
    TransferRequest request,
  ) => _familyFor<TransferRepositorySessionRepository>(
    identity,
  ).previewTransfer(identity, request);

  @override
  Future<TransferExecutionResult> executeTransfer(
    RepositorySessionIdentity identity,
    BigInt token, {
    TransferCredentials? credentials,
  }) => _isRemote(identity)
      // A remote transfer uses the host's own credentials; nothing entered
      // here is sent to it.
      ? credentials != null
            ? _unsupported()
            : _remoteAs<TransferRepositorySessionRepository>(
                identity,
              ).executeTransfer(identity, token)
      : _localAs<TransferRepositorySessionRepository>().executeTransfer(
          identity,
          token,
          credentials: credentials,
        );

  @override
  Future<TransferExecutionResult> executeBackgroundFetch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _unsupported()
      : _localAs<TransferRepositorySessionRepository>().executeBackgroundFetch(
          identity,
          token,
        );

  @override
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity identity,
    List<String> references,
  ) => _isRemote(identity)
      ? _unsupported()
      : _localAs<TransferRepositorySessionRepository>().deleteTrackingRefs(
          identity,
          references,
        );

  @override
  Future<bool> cancelTransfer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _unsupported()
      : _localAs<TransferRepositorySessionRepository>().cancelTransfer(
          identity,
          token,
        );

  @override
  Future<HostKeyChallenge> probeTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _unsupported()
      : _localAs<TransferRepositorySessionRepository>().probeTransferHostKey(
          identity,
          token,
        );

  @override
  Future<void> resolveTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
    HostKeyChallenge challenge, {
    required bool accept,
  }) => _isRemote(identity)
      ? _unsupported()
      : _localAs<TransferRepositorySessionRepository>().resolveTransferHostKey(
          identity,
          token,
          challenge,
          accept: accept,
        );

  // StashRepositorySessionRepository
  @override
  Future<StashPreview> previewStash(
    RepositorySessionIdentity identity,
    StashRequest request,
  ) => _familyFor<StashRepositorySessionRepository>(
    identity,
  ).previewStash(identity, request);

  @override
  Future<StashExecutionResult> executeStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _familyFor<StashRepositorySessionRepository>(
    identity,
  ).executeStash(identity, token);

  @override
  Future<bool> cancelStash(RepositorySessionIdentity identity, BigInt token) =>
      _isRemote(identity)
      ? _unsupported()
      : _localAs<StashRepositorySessionRepository>().cancelStash(
          identity,
          token,
        );

  // HistoryMutationRepositorySessionRepository
  @override
  Future<HistoryMutationPreview> previewHistoryMutation(
    RepositorySessionIdentity identity,
    HistoryMutationRequest request,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<HistoryMutationRepositorySessionRepository>(identity)
              : _localAs<HistoryMutationRepositorySessionRepository>())
          .previewHistoryMutation(identity, request);

  @override
  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<HistoryMutationRepositorySessionRepository>(identity)
              : _localAs<HistoryMutationRepositorySessionRepository>())
          .executeHistoryMutation(identity, token);

  @override
  Future<bool> cancelHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<HistoryMutationRepositorySessionRepository>(identity)
              : _localAs<HistoryMutationRepositorySessionRepository>())
          .cancelHistoryMutation(identity, token);

  @override
  Future<BigInt> beginConflictPrediction(RepositorySessionIdentity identity) =>
      (_isRemote(identity)
              ? _remoteAs<HistoryMutationRepositorySessionRepository>(identity)
              : _localAs<HistoryMutationRepositorySessionRepository>())
          .beginConflictPrediction(identity);

  @override
  Future<ConflictPredictionResult> executeConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
    ConflictPredictionKind kind,
    String target,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<HistoryMutationRepositorySessionRepository>(identity)
              : _localAs<HistoryMutationRepositorySessionRepository>())
          .executeConflictPrediction(identity, token, kind, target);

  @override
  Future<bool> cancelConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<HistoryMutationRepositorySessionRepository>(identity)
              : _localAs<HistoryMutationRepositorySessionRepository>())
          .cancelConflictPrediction(identity, token);

  // RebaseRepositorySessionRepository
  @override
  Future<RebasePlan> loadRebasePlan(
    RepositorySessionIdentity identity,
    String onto,
    List<int>? ontoName,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<RebaseRepositorySessionRepository>(identity)
              : _localAs<RebaseRepositorySessionRepository>())
          .loadRebasePlan(identity, onto, ontoName);

  @override
  Future<RebasePreview> previewRebase(
    RepositorySessionIdentity identity,
    BigInt token,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<RebaseRepositorySessionRepository>(identity)
              : _localAs<RebaseRepositorySessionRepository>())
          .previewRebase(
            identity,
            token,
            instructions,
            acknowledgePublishedHistory,
            applyAutosquash,
          );

  @override
  Future<RebaseExecutionResult> executeRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<RebaseRepositorySessionRepository>(identity)
              : _localAs<RebaseRepositorySessionRepository>())
          .executeRebase(identity, token);

  @override
  Future<bool> cancelRebase(RepositorySessionIdentity identity, BigInt token) =>
      (_isRemote(identity)
              ? _remoteAs<RebaseRepositorySessionRepository>(identity)
              : _localAs<RebaseRepositorySessionRepository>())
          .cancelRebase(identity, token);

  // ConflictRepositorySessionRepository
  @override
  Future<ConflictSnapshot> loadConflicts(RepositorySessionIdentity identity) =>
      (_isRemote(identity)
              ? _remoteAs<ConflictRepositorySessionRepository>(identity)
              : _localAs<ConflictRepositorySessionRepository>())
          .loadConflicts(identity);

  @override
  Future<ConflictSnapshot> saveConflictResult(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    List<int> result,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<ConflictRepositorySessionRepository>(identity)
              : _localAs<ConflictRepositorySessionRepository>())
          .saveConflictResult(identity, path, expectedFingerprint, result);

  @override
  Future<ConflictSnapshot> chooseConflictSide(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    ConflictSideChoice choice,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<ConflictRepositorySessionRepository>(identity)
              : _localAs<ConflictRepositorySessionRepository>())
          .chooseConflictSide(identity, path, expectedFingerprint, choice);

  @override
  Future<ConflictSnapshot> takeConflictRegion(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    int regionIndex,
    ConflictRegionChoice choice,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<ConflictRepositorySessionRepository>(identity)
              : _localAs<ConflictRepositorySessionRepository>())
          .takeConflictRegion(
            identity,
            path,
            expectedFingerprint,
            regionIndex,
            choice,
          );

  @override
  Future<ConflictSnapshot> undoConflictResolution(
    RepositorySessionIdentity identity,
    List<int> path,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<ConflictRepositorySessionRepository>(identity)
              : _localAs<ConflictRepositorySessionRepository>())
          .undoConflictResolution(identity, path);

  @override
  Future<ConflictContinuationResult> continueConflictOperation(
    RepositorySessionIdentity identity,
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) =>
      (_isRemote(identity)
              ? _remoteAs<ConflictRepositorySessionRepository>(identity)
              : _localAs<ConflictRepositorySessionRepository>())
          .continueConflictOperation(
            identity,
            action,
            mergeMessage: mergeMessage,
          );

  // AdvancedRebaseRepositorySessionRepository
  @override
  Future<FixupSuggestion> suggestFixupBase(
    RepositorySessionIdentity identity, {
    String? selectedCommit,
    List<List<int>> paths = const [],
  }) =>
      (_isRemote(identity)
              ? _remoteAs<AdvancedRebaseRepositorySessionRepository>(identity)
              : _localAs<AdvancedRebaseRepositorySessionRepository>())
          .suggestFixupBase(
            identity,
            selectedCommit: selectedCommit,
            paths: paths,
          );

  @override
  Future<RestackPlan> planRestack(
    RepositorySessionIdentity identity,
    List<int> rootBranch,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<AdvancedRebaseRepositorySessionRepository>(identity)
              : _localAs<AdvancedRebaseRepositorySessionRepository>())
          .planRestack(identity, rootBranch);

  @override
  Future<RestackExecutionResult> executeRestack(
    RepositorySessionIdentity identity,
    BigInt token,
    bool acknowledgePublishedHistory,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<AdvancedRebaseRepositorySessionRepository>(identity)
              : _localAs<AdvancedRebaseRepositorySessionRepository>())
          .executeRestack(identity, token, acknowledgePublishedHistory);

  @override
  Future<bool> cancelRestack(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<AdvancedRebaseRepositorySessionRepository>(identity)
              : _localAs<AdvancedRebaseRepositorySessionRepository>())
          .cancelRestack(identity, token);

  // NamedSnapshotRepositorySessionRepository
  @override
  Future<NamedSnapshotPage> namedSnapshots(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximum = 32,
  }) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .namedSnapshots(identity, offset: offset, maximum: maximum);

  @override
  Future<NamedSnapshotExecutionResult> createNamedSnapshot(
    RepositorySessionIdentity identity, {
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .createNamedSnapshot(
            identity,
            name: name,
            includeUntracked: includeUntracked,
            keepIndex: keepIndex,
          );

  @override
  Future<NamedSnapshotRestorePreview> previewNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .previewNamedSnapshotRestore(identity, snapshotId);

  @override
  Future<NamedSnapshotExecutionResult> executeNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .executeNamedSnapshotRestore(identity, token);

  @override
  Future<bool> cancelNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .cancelNamedSnapshotRestore(identity, token);

  @override
  Future<NamedSnapshotExecutionResult> branchFromNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
    List<int> branch,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .branchFromNamedSnapshot(identity, snapshotId, branch);

  @override
  Future<NamedSnapshotExecutionResult> deleteNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<NamedSnapshotRepositorySessionRepository>(identity)
              : _localAs<NamedSnapshotRepositorySessionRepository>())
          .deleteNamedSnapshot(identity, snapshotId);

  // ExtensionRepositorySessionRepository
  /// A remote inventory names worktrees on its host; its adapter marks them.
  @override
  Future<RepositoryExtensionInventory> repositoryExtensions(
    RepositorySessionIdentity identity,
  ) => _familyFor<ExtensionRepositorySessionRepository>(
    identity,
  ).repositoryExtensions(identity);

  /// A submodule of a remote repository opens on the same host.
  @override
  Future<NativePathIdentity> enterSubmodule(
    RepositorySessionIdentity identity,
    List<int> path,
  ) => _familyFor<ExtensionRepositorySessionRepository>(
    identity,
  ).enterSubmodule(identity, path);

  @override
  Future<LfsPointer?> inspectLfsPointer(
    RepositorySessionIdentity identity,
    List<int> path,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<ExtensionRepositorySessionRepository>(identity)
              : _localAs<ExtensionRepositorySessionRepository>())
          .inspectLfsPointer(identity, path);

  /// Computed on this computer for every repository: it reads none.
  @override
  String? exactIgnorePattern(List<int> path, {required bool directory}) =>
      _localAs<ExtensionRepositorySessionRepository>().exactIgnorePattern(
        path,
        directory: directory,
      );

  @override
  Future<RepositoryExtensionMutationResult> executeRepositoryExtension(
    RepositorySessionIdentity identity,
    RepositoryExtensionMutationRequest request,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<ExtensionRepositorySessionRepository>(identity)
              : _localAs<ExtensionRepositorySessionRepository>())
          .executeRepositoryExtension(identity, request);

  // IntegrationRepositorySessionRepository
  @override
  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) => _localAs<IntegrationRepositorySessionRepository>().discoverIntegrations(
    kind,
  );

  @override
  Future<IntegrationPreview> previewIntegration(
    RepositorySessionIdentity identity,
    IntegrationRequest request,
  ) => _isRemote(identity)
      ? _unsupported()
      : _localAs<IntegrationRepositorySessionRepository>().previewIntegration(
          identity,
          request,
        );

  @override
  Future<IntegrationPreview> previewExternalConflictMerge(
    RepositorySessionIdentity identity,
    ConflictFile file,
    IntegrationDefinition definition,
  ) => _isRemote(identity)
      ? _unsupported()
      : _localAs<IntegrationRepositorySessionRepository>()
            .previewExternalConflictMerge(identity, file, definition);

  @override
  Future<IntegrationPreview> previewExternalCommitDiff(
    RepositorySessionIdentity identity, {
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  }) => _isRemote(identity)
      ? _remoteSource(identity)
            .changeSource(
              identity,
              oldRevision: oldRevision,
              newRevision: newRevision,
              oldPath: oldPath,
              newPath: newPath,
              byteLimit: _externalDiffBytes,
            )
            .then(
              (source) => _detached.previewDetachedDiffTool(source, definition),
            )
      : _localAs<IntegrationRepositorySessionRepository>()
            .previewExternalCommitDiff(
              identity,
              oldRevision: oldRevision,
              newRevision: newRevision,
              oldPath: oldPath,
              newPath: newPath,
              definition: definition,
            );

  @override
  Future<IntegrationExecutionResult> executeIntegration(
    RepositorySessionIdentity identity,
    BigInt token, {
    required bool confirmed,
  }) => _isRemote(identity)
      // Only a diff tool previewed on this computer runs for a remote tab.
      ? _detached.executeDetachedIntegration(token, confirmed: confirmed)
      : _localAs<IntegrationRepositorySessionRepository>().executeIntegration(
          identity,
          token,
          confirmed: confirmed,
        );

  @override
  Future<bool> cancelIntegration(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _detached.cancelDetachedIntegration(token)
      : _localAs<IntegrationRepositorySessionRepository>().cancelIntegration(
          identity,
          token,
        );

  // CommitArchiveRepositorySessionRepository
  /// The host builds a remote repository's snapshot; this computer saves it.
  @override
  Future<CommitArchiveStatus> saveCommitArchive(
    RepositorySessionIdentity identity, {
    required String commit,
    required String prefix,
    required String destination,
    required void Function(CommitArchiveStatus status) onProgress,
    required bool Function() isCanceled,
  }) =>
      (_isRemote(identity)
              ? _remoteAs<CommitArchiveRepositorySessionRepository>(identity)
              : _localAs<CommitArchiveRepositorySessionRepository>())
          .saveCommitArchive(
            identity,
            commit: commit,
            prefix: prefix,
            destination: destination,
            onProgress: onProgress,
            isCanceled: isCanceled,
          );

  // PowerToolsRepositorySessionRepository
  @override
  Future<BigInt> startDiffContentSearch(
    RepositorySessionIdentity identity, {
    required String query,
    required int maximumCommits,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
    bool otherRefs = false,
  }) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .startDiffContentSearch(
            identity,
            query: query,
            maximumCommits: maximumCommits,
            caseSensitive: caseSensitive,
            scope: scope,
            otherRefs: otherRefs,
          );

  @override
  Future<DiffContentSearchResult> pollDiffContentSearch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .pollDiffContentSearch(identity, token);

  @override
  Future<BigInt> startRepositoryStatistics(
    RepositorySessionIdentity identity,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .startRepositoryStatistics(identity);

  @override
  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .pollRepositoryStatistics(identity, token);

  @override
  Future<bool> cancelPowerJob(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .cancelPowerJob(identity, token);

  @override
  Future<BisectState> bisectState(RepositorySessionIdentity identity) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .bisectState(identity);

  @override
  Future<BisectPreview> previewBisect(
    RepositorySessionIdentity identity,
    BisectAction action, {
    String? good,
    String? bad,
  }) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .previewBisect(identity, action, good: good, bad: bad);

  @override
  Future<BisectExecutionResult> executeBisect(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .executeBisect(identity, token);

  @override
  Future<bool> cancelBisectPreview(
    RepositorySessionIdentity identity,
    BigInt token,
  ) =>
      (_isRemote(identity)
              ? _remoteAs<PowerToolsRepositorySessionRepository>(identity)
              : _localAs<PowerToolsRepositorySessionRepository>())
          .cancelBisectPreview(identity, token);

  // DiffRendererRepositorySessionRepository
  @override
  Future<DiffRendererPreview> validateDiffRenderer(
    RepositorySessionIdentity identity,
    DiffRendererDefinition definition,
  ) => _isRemote(identity)
      ? _detached.validateDetachedDiffRenderer(identity, definition)
      : _localAs<DiffRendererRepositorySessionRepository>()
            .validateDiffRenderer(identity, definition);

  @override
  Future<DiffRendererPreview> previewDiffRenderer(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required DiffRendererDefinition definition,
  }) => _isRemote(identity)
      ? _remoteSource(identity)
            .diffRendererInput(identity, requestId)
            .then(
              (input) => _detached.previewDetachedDiffRenderer(
                identity,
                input,
                definition,
              ),
            )
      : _localAs<DiffRendererRepositorySessionRepository>().previewDiffRenderer(
          identity,
          requestId: requestId,
          definition: definition,
        );

  @override
  Future<DiffRendererResult> executeDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _detached.executeDetachedDiffRenderer(token)
      : _localAs<DiffRendererRepositorySessionRepository>().executeDiffRenderer(
          identity,
          token,
        );

  @override
  Future<DiffRendererResult> pollDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _detached.pollDetachedDiffRenderer(token)
      : _localAs<DiffRendererRepositorySessionRepository>().pollDiffRenderer(
          identity,
          token,
        );

  @override
  Future<bool> cancelDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _isRemote(identity)
      ? _detached.cancelDetachedDiffRenderer(token)
      : _localAs<DiffRendererRepositorySessionRepository>().cancelDiffRenderer(
          identity,
          token,
        );

  // DiffSyntaxRepository: parsed where the repository is, here or on its host.
  @override
  Future<DiffSyntaxPage> diffSyntaxPage(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
    required int offset,
    required int maximumRows,
  }) => _familyFor<DiffSyntaxRepository>(identity).diffSyntaxPage(
    identity,
    origin: origin,
    diffRequestId: diffRequestId,
    syntaxRequestId: syntaxRequestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<bool> cancelDiffSyntax(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
  }) => _familyFor<DiffSyntaxRepository>(identity).cancelDiffSyntax(
    identity,
    origin: origin,
    diffRequestId: diffRequestId,
    syntaxRequestId: syntaxRequestId,
  );
}

/// Stands in for a remote session whose connection is gone: every call fails
/// asynchronously with [RepositoryFailureCode.remoteDisconnected].
final class _DisconnectedRepository
    implements
        RepositorySessionRepository,
        ChangeSourceRepositorySessionRepository,
        PatchRepositorySessionRepository,
        TransferRepositorySessionRepository,
        StashRepositorySessionRepository {
  const _DisconnectedRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(
    const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteDisconnected),
    ),
  );
}
