import 'dart:convert';
import 'dart:async';

import '../../models/diff.dart';
import '../../models/diff_syntax.dart';
import '../../models/discard.dart';
import '../../models/index_lock.dart';
import '../../models/remote_contract.g.dart';
import '../../models/repository_lock.dart';
import '../../models/repository_state.dart';
import '../../models/status_acceleration.dart';
import '../../repositories/working_copy_repository.dart';
import '../diff_syntax_service.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// The working tree and index of the active repository: diffs, staging,
/// discarding and the index lock.
final class WorkingCopyCommands {
  WorkingCopyCommands(
    this._repository,
    this._scope,
    PreviewRegistry previews, {
    this._syntax,
  }) : _discards = previews.sessions();

  final WorkingCopyRepository _repository;
  final DiffSyntaxService? _syntax;

  /// A syntax view for the accepted working diff [requestId] of the active
  /// session, or null when diffs stay plain. The caller gives it the pages
  /// it shows and disposes it with the diff.
  DiffSyntaxView? syntaxView(BigInt requestId) => _syntax?.view(
    identity: _scope.requireCurrent(),
    origin: DiffSyntaxOrigin.working,
    diffRequestId: requestId,
  );
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _discards;

  Future<DiffPage> diff({
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = ContractLimits.pageRows,
  }) => diffFor(
    _scope.requireCurrent(),
    side: side,
    oldPath: oldPath,
    newPath: newPath,
    contextLines: contextLines,
    whitespace: whitespace,
    layout: layout,
    forceText: forceText,
    maximumRows: maximumRows,
  );

  Future<DiffPage> diffFor(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = ContractLimits.pageRows,
  }) => _repository.workingDiff(
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

  Future<ImageDiffContent> imageDiff({
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
  }) => _repository.workingImageDiff(
    _scope.requireCurrent(),
    side: side,
    oldPath: oldPath,
    newPath: newPath,
  );

  Future<DiffPage> diffPage({
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _repository.workingDiffPage(
    _scope.requireCurrent(),
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  Future<DiffSearchResult> search({
    required BigInt requestId,
    required String query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) => _repository.searchDiff(
    _scope.requireCurrent(),
    requestId: requestId,
    query: utf8.encode(query),
    caseSensitive: caseSensitive,
    maximumMatches: maximumMatches,
  );

  /// A unified patch of the selected working-diff rows; see
  /// [WorkingCopyRepository.diffSelectionPatch].
  Future<List<int>?> selectionPatch({
    required BigInt requestId,
    required List<String> rowIds,
  }) => _repository.diffSelectionPatch(
    _scope.requireCurrent(),
    requestId: requestId,
    working: true,
    rowIds: rowIds,
  );

  Future<StagingExecutionResult> stage(StagingRequest request) async {
    return stageFor(_scope.requireCurrent(), request);
  }

  Future<StagingExecutionResult> stageFor(
    RepositorySessionIdentity identity,
    StagingRequest request, {
    void Function(StagingPhase)? onPhase,
  }) async {
    _scope.ensureActive();
    if (!_scope.isOpen(identity)) throw unknownSessionFailure;
    var finished = false;
    var polling = false;
    Future<void> poll() async {
      if (polling || finished) return;
      polling = true;
      try {
        final phase = await _repository.stagingPhase(identity);
        if (!finished && phase != null && phase != StagingPhase.idle) {
          onPhase?.call(phase);
        }
      } on Object {
        // Progress is optional; a failed read never changes the write's outcome.
      } finally {
        polling = false;
      }
    }

    final timer = onPhase == null
        ? null
        : Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => unawaited(poll()),
          );
    try {
      var result = await _repository.executeStaging(identity, request);
      // Stale means the private index was never installed. Whole-file intent
      // can be rebuilt once; row patches must retain their exact accepted bytes.
      if (result.state == StagingExecutionState.stale &&
          request.scope != StagingScope.rows &&
          _scope.isOpen(identity)) {
        result = await _repository.executeStaging(
          identity,
          StagingRequest(
            requestId: BigInt.zero,
            side: request.side,
            scope: request.scope,
            paths: request.paths,
          ),
        );
      }
      return result;
    } finally {
      finished = true;
      timer?.cancel();
    }
  }

  Future<DiscardPreview> previewDiscard(DiscardRequest request) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewDiscard(identity, request);
    _discards[preview.token] = identity;
    return preview;
  }

  Future<DiscardExecutionResult> executeDiscard(DiscardPreview preview) async {
    _scope.ensureActive();
    final identity = _discards.remove(preview.token);
    if (identity == null) throw unknownPreviewFailure;
    return _repository.executeDiscard(identity, preview.token);
  }

  /// The index lock of the active repository, with the session it was
  /// inspected in so that removing it acts on the same one.
  Future<({RepositorySessionIdentity identity, IndexLockInspection inspection})>
  inspectIndexLock() async {
    _scope.ensureActive();
    final RepositorySessionIdentity identity;
    try {
      identity = _scope.requireCurrent();
    } on RepositorySessionException {
      throw const IndexLockException(IndexLockFailureCode.unknownSession);
    }
    return (
      identity: identity,
      inspection: await _repository.inspectIndexLock(identity),
    );
  }

  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    _scope.ensureActive();
    await _repository.removeIndexLock(identity, token);
  }

  final _accelerationChecks = <(BigInt, int), Future<StatusAcceleration?>>{};
  final _accelerationDismissed = <(BigInt, int)>{};
  final _accelerationEnabled =
      StreamController<RepositorySessionIdentity>.broadcast();

  /// The sessions whose status accelerators were just enabled, from the
  /// offer or the settings, so a shown offer can follow.
  Stream<RepositorySessionIdentity> get statusAccelerationEnabled =>
      _accelerationEnabled.stream;

  static (BigInt, int) _accelerationKey(RepositorySessionIdentity identity) =>
      (identity.nativeId, identity.generation);

  /// The status accelerators to offer for [identity]'s repository: checked
  /// once per session, after its first status scan. Null when the session is
  /// remote, the check failed or the user dismissed the offer.
  Future<StatusAcceleration?> statusAccelerationOffer(
    RepositorySessionIdentity identity,
  ) async {
    if (identity.backend != RepositoryBackendKind.local) return null;
    final key = _accelerationKey(identity);
    if (_accelerationDismissed.contains(key)) return null;
    final acceleration = await (_accelerationChecks[key] ??= _repository
        .statusAcceleration(identity)
        .then<StatusAcceleration?>(
          (value) => value,
          onError: (Object _) => null,
        ));
    if (_accelerationDismissed.contains(key)) return null;
    return acceleration;
  }

  /// The status accelerators of [identity]'s repository as they are now,
  /// for the settings: read fresh and shown even after the offer was
  /// dismissed. Null when the session is remote.
  Future<StatusAcceleration?> statusAcceleration(
    RepositorySessionIdentity identity,
  ) async {
    if (identity.backend != RepositoryBackendKind.local) return null;
    _scope.ensureActive();
    final acceleration = await _repository.statusAcceleration(identity);
    _accelerationChecks[_accelerationKey(identity)] = Future.value(
      acceleration,
    );
    return acceleration;
  }

  /// Hides the offer for [identity]'s session.
  void dismissStatusAccelerationOffer(RepositorySessionIdentity identity) =>
      _accelerationDismissed.add(_accelerationKey(identity));

  /// Enables the missing status accelerators of [identity]'s repository in
  /// its local Git configuration and completes with the settings in effect.
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  ) async {
    _scope.ensureActive();
    final enabled = await _repository.enableStatusAcceleration(identity);
    _accelerationChecks[_accelerationKey(identity)] = Future.value(enabled);
    _accelerationEnabled.add(identity);
    return enabled;
  }

  /// The Git lock files of the repository [identity] names.
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  ) {
    _scope.ensureActive();
    return _repository.inspectRepositoryLocks(identity);
  }

  /// Removes [locks] from the last inspection of [identity], stopping at the
  /// first that changed. Completes with how many were removed; one already
  /// gone counts as handled.
  Future<int> removeRepositoryLocks(
    RepositorySessionIdentity identity,
    List<RepositoryLock> locks,
  ) async {
    var removed = 0;
    for (final lock in locks) {
      _scope.ensureActive();
      if (await _repository.removeRepositoryLock(identity, lock.token)) {
        removed++;
      }
    }
    return removed;
  }
}
