import 'dart:async';

import 'package:gitlama/models/advanced_rebase.dart';
import 'package:gitlama/models/clone_attempt.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';

import 'fake_repository_session_repository.dart';

/// A session repository whose reference, transfer, stash, history, rebase,
/// restack, integration and index-lock calls are scripted per test. Every
/// call is recorded in [calls] in order, so tests assert sequences.
class WorkflowFakeRepository extends FakeRepositorySessionRepository
    implements
        TransferRepositorySessionRepository,
        StashRepositorySessionRepository,
        HistoryMutationRepositorySessionRepository,
        RebaseRepositorySessionRepository,
        AdvancedRebaseRepositorySessionRepository,
        IntegrationRepositorySessionRepository,
        ConflictRepositorySessionRepository {
  WorkflowFakeRepository(super.snapshot);

  /// Each call by name, with its main argument where one matters.
  final List<String> calls = [];

  /// Snapshot events the session drains next.
  final List<RepositorySessionEvent> pendingEvents = [];

  HistoryPage? historyResult;

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = 512,
  }) async =>
      historyResult ??
      await super.loadHistory(
        identity,
        complete: complete,
        otherRefs: otherRefs,
        maximumRows: maximumRows,
      );

  // References.
  final List<RefMutationRequest> refRequests = [];
  List<RefMutationWarning> refWarnings = const [];
  Object? refPreviewError;
  Completer<void>? refPreviewGate;
  RefMutationExecutionState Function(RefMutationRequest request) refResult =
      (_) => RefMutationExecutionState.completed;
  var _refToken = 100;
  final Map<BigInt, RefMutationRequest> _refPreviews = {};

  bool publishRefreshSnapshot = false;
  Object? refreshError;
  Completer<void>? refreshGate;

  @override
  Future<void> refresh(RepositorySessionIdentity identity) async {
    await refreshGate?.future;
    if (refreshError case final error?) throw error;
    if (!publishRefreshSnapshot) return;
    final old = snapshot!;
    pendingEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: RepositorySnapshot(
          revision: old.revision + BigInt.one,
          phase: old.phase,
          status: old.status,
          refs: old.refs,
        ),
      ),
    );
  }

  // Transfers.
  final List<TransferRequest> transferRequests = [];
  final List<TransferCredentials?> transferCredentials = [];

  /// Results of successive transfer executions; completed when it runs out.
  final List<TransferExecutionResult> transferResults = [];
  Completer<TransferExecutionResult>? transferGate;
  Object? transferPreviewError;
  final List<BigInt> canceledTransfers = [];
  final List<bool> hostKeyDecisions = [];
  var _transferToken = 200;

  // Stash.
  StashRequest? stashRequest;
  final stashRequests = <StashRequest>[];
  final _stashPreviews = <BigInt, StashRequest>{};
  StashRequest? executedStashRequest;
  var _stashToken = 84;
  StashExecutionResult stashResult = const StashExecutionResult(
    state: StashExecutionState.completed,
    activityIds: [],
    stashCreated: true,
    checkoutCompleted: false,
    reapplyCompleted: false,
    stashRetained: false,
  );
  Object? stashPreviewError;

  // History mutations and prediction.
  HistoryMutationRequest? historyMutationRequest;
  var historyMutationAlreadyContained = false;
  var historyMutationNoCommit = false;
  HistoryMutationExecutionResult historyMutationResult =
      const HistoryMutationExecutionResult(
        state: HistoryMutationExecutionState.completed,
        activityIds: [],
        conflictingPaths: [],
      );
  Completer<HistoryMutationExecutionResult>? historyMutationGate;
  var historyMutationCancels = 0;
  Object? historyMutationPreviewError;

  // Rebase.
  RebaseExecutionResult rebaseResult = const RebaseExecutionResult(
    state: RebaseExecutionState.completed,
    activityIds: [],
    conflictingPaths: [],
  );
  Object? rebasePlanError;

  // Restack.
  List<RestackStep> restackSteps = const [];
  RestackExecutionResult restackResult = const RestackExecutionResult(
    state: RestackExecutionState.completed,
    completedSteps: 1,
    totalSteps: 1,
    recoveryRefs: [],
    conflictingPaths: [],
    activityIds: [],
  );
  Object? restackPlanError;
  bool? restackAcknowledged;
  var restackCancels = 0;

  // Integrations.
  List<IntegrationCandidate> candidates = const [];
  final List<IntegrationRequest> integrationRequests = [];
  var integrationRequiresConfirmation = false;
  IntegrationExecutionState integrationState =
      IntegrationExecutionState.detached;
  var integrationCancels = 0;

  // Index lock.
  IndexLockInspection indexLock = const IndexLockInspection(present: false);
  Object? removeIndexLockError;
  BigInt? removedIndexLockToken;

  @override
  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  }) async {
    final events = List.of(pendingEvents);
    pendingEvents.clear();
    return events;
  }

  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) async {
    calls.add('previewRef:${request.kind.name}');
    await refPreviewGate?.future;
    refRequests.add(request);
    if (refPreviewError case final error?) throw error;
    final token = BigInt.from(_refToken++);
    _refPreviews[token] = request;
    return RefMutationPreview(
      token: token,
      kind: request.kind,
      arguments: const ['branch'],
      warnings: refWarnings,
    );
  }

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    final request = _refPreviews[token]!;
    calls.add('executeRef:${request.kind.name}');
    return RefMutationExecutionResult(state: refResult(request));
  }

  @override
  Future<TransferPreview> previewTransfer(
    RepositorySessionIdentity identity,
    TransferRequest request,
  ) async {
    calls.add('previewTransfer:${request.kind.name}');
    transferRequests.add(request);
    if (transferPreviewError case final error?) throw error;
    return TransferPreview(
      token: BigInt.from(_transferToken++),
      kind: request.kind,
      remote: request.remote ?? 'origin',
      branch: request.branch,
      arguments: const ['push'],
      ahead: BigInt.zero,
      behind: BigInt.zero,
      dirty: false,
      expectedRemoteObjectId: null,
      forceWithLease: request.forceWithLease,
    );
  }

  @override
  Future<TransferExecutionResult> executeTransfer(
    RepositorySessionIdentity identity,
    BigInt token, {
    TransferCredentials? credentials,
  }) async {
    calls.add('executeTransfer:$token');
    transferCredentials.add(credentials);
    if (transferGate case final gate?) {
      transferGate = null;
      return gate.future;
    }
    if (transferResults.isNotEmpty) return transferResults.removeAt(0);
    return TransferExecutionResult(
      state: TransferExecutionState.completed,
      ahead: BigInt.zero,
      behind: BigInt.zero,
    );
  }

  @override
  Future<TransferExecutionResult> executeBackgroundFetch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => executeTransfer(identity, token);

  final List<List<String>> deletedTrackingRefs = [];

  @override
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity identity,
    List<String> references,
  ) async {
    calls.add('deleteTrackingRefs');
    deletedTrackingRefs.add(references);
    return TransferExecutionResult(
      state: TransferExecutionState.completed,
      ahead: BigInt.zero,
      behind: BigInt.zero,
    );
  }

  @override
  Future<bool> cancelTransfer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledTransfers.add(token);
    return true;
  }

  @override
  Future<HostKeyChallenge> probeTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    calls.add('probeHostKey');
    return HostKeyChallenge(
      challengeId: BigInt.one,
      host: 'example.test',
      port: 22,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:test',
    );
  }

  @override
  Future<void> resolveTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
    HostKeyChallenge challenge, {
    required bool accept,
  }) async {
    calls.add('resolveHostKey:$accept');
    hostKeyDecisions.add(accept);
  }

  @override
  Future<StashPreview> previewStash(
    RepositorySessionIdentity identity,
    StashRequest request,
  ) async {
    calls.add('previewStash:${request.kind.name}');
    stashRequest = request;
    stashRequests.add(request);
    if (stashPreviewError case final error?) throw error;
    final token = BigInt.from(_stashToken++);
    _stashPreviews[token] = request;
    return StashPreview(
      token: token,
      kind: request.kind,
      commands: const [
        ['git', 'stash', 'push'],
      ],
      affectedPaths: 1,
      includesUntracked: request.includeUntracked,
      keepsIndex: request.keepIndex,
      destructive: false,
    );
  }

  @override
  Future<StashExecutionResult> executeStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    calls.add('executeStash');
    executedStashRequest = _stashPreviews.remove(token);
    return stashResult;
  }

  @override
  Future<bool> cancelStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    calls.add('cancelStash');
    return true;
  }

  @override
  Future<HistoryMutationPreview> previewHistoryMutation(
    RepositorySessionIdentity identity,
    HistoryMutationRequest request,
  ) async {
    calls.add('previewHistory:${request.kind.name}');
    historyMutationRequest = request;
    if (historyMutationPreviewError case final error?) throw error;
    return HistoryMutationPreview(
      token: BigInt.from(85),
      kind: request.kind,
      arguments: const ['merge'],
      targets: request.targets,
      currentBranch: 'main'.codeUnits,
      currentHead: '1' * 40,
      publishedHistory: false,
      alreadyContained: historyMutationAlreadyContained,
      noCommit: historyMutationNoCommit,
    );
  }

  @override
  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    calls.add('executeHistory');
    if (historyMutationGate case final gate?) return gate.future;
    return historyMutationResult;
  }

  @override
  Future<bool> cancelHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    historyMutationCancels += 1;
    return true;
  }

  @override
  Future<BigInt> beginConflictPrediction(
    RepositorySessionIdentity identity,
  ) async {
    calls.add('beginPrediction');
    return BigInt.from(90);
  }

  @override
  Future<ConflictPredictionResult> executeConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
    ConflictPredictionKind kind,
    String target,
  ) async {
    calls.add('predict:${kind.name}:$target');
    return ConflictPredictionResult(
      kind: kind,
      target: target,
      conflictingPaths: const [],
      analyzedCommits: 1,
      totalCommits: 1,
      complete: true,
      activityIds: const [],
    );
  }

  @override
  Future<bool> cancelConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<RebasePlan> loadRebasePlan(
    RepositorySessionIdentity identity,
    String onto,
    List<int>? ontoName,
  ) async {
    calls.add('loadRebasePlan:$onto');
    if (rebasePlanError case final error?) throw error;
    return RebasePlan(
      token: BigInt.from(91),
      onto: onto,
      ontoName: ontoName,
      currentBranch: 'main'.codeUnits,
      currentHead: '1' * 40,
      instructions: const [],
      publishedCount: 0,
      activityIds: const [],
    );
  }

  @override
  Future<RebasePreview> previewRebase(
    RepositorySessionIdentity identity,
    BigInt token,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) async {
    calls.add('previewRebase');
    return RebasePreview(
      // The plan's token carries through to its execution.
      token: token,
      arguments: const ['rebase'],
      todo: const [],
      instructionCount: 0,
      publishedCount: 0,
      instructions: const [],
      autosquashApplied: 0,
    );
  }

  @override
  Future<RebaseExecutionResult> executeRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    calls.add('executeRebase');
    return rebaseResult;
  }

  @override
  Future<bool> cancelRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<RestackPlan> planRestack(
    RepositorySessionIdentity identity,
    List<int> rootBranch,
  ) async {
    calls.add('planRestack:${String.fromCharCodes(rootBranch)}');
    if (restackPlanError case final error?) throw error;
    return RestackPlan(
      token: BigInt.from(93),
      rootBranch: rootBranch,
      steps: restackSteps,
      publishedCount: 0,
      incomplete: false,
      activityIds: const [],
    );
  }

  @override
  Future<RestackExecutionResult> executeRestack(
    RepositorySessionIdentity identity,
    BigInt token,
    bool acknowledgePublishedHistory,
  ) async {
    calls.add('executeRestack');
    restackAcknowledged = acknowledgePublishedHistory;
    return restackResult;
  }

  @override
  Future<bool> cancelRestack(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    restackCancels += 1;
    return true;
  }

  @override
  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) async => candidates.where((candidate) => candidate.kind == kind).toList();

  @override
  Future<IntegrationPreview> previewIntegration(
    RepositorySessionIdentity identity,
    IntegrationRequest request,
  ) async {
    integrationRequests.add(request);
    return IntegrationPreview(
      token: BigInt.from(94),
      kind: request.kind,
      definitionId: request.configured?.id ?? request.discoveredId ?? '',
      executable: 'tool',
      arguments: request.configured?.arguments ?? const [],
      explicitShell: false,
      waitsForExit: false,
      requiresConfirmation: integrationRequiresConfirmation,
    );
  }

  @override
  Future<IntegrationExecutionResult> executeIntegration(
    RepositorySessionIdentity identity,
    BigInt token, {
    required bool confirmed,
  }) async {
    calls.add('executeIntegration');
    return IntegrationExecutionResult(state: integrationState);
  }

  @override
  Future<bool> cancelIntegration(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    integrationCancels += 1;
    return true;
  }

  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) async => indexLock;

  @override
  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    if (removeIndexLockError case final error?) throw error;
    removedIndexLockToken = token;
  }

  // Commits.
  final List<CommitRequest> commitRequests = [];
  List<CommitWarning> commitWarnings = const [];
  final List<CommitExecutionResult> commitResults = [];
  Object? commitError;

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) async {
    calls.add('previewCommit');
    commitRequests.add(request);
    return CommitPreview(
      token: BigInt.from(commitRequests.length),
      warnings: commitWarnings,
      arguments: const ['commit'],
    );
  }

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    calls.add('executeCommit');
    if (commitError case final error?) throw error;
    return commitResults.isEmpty
        ? const CommitExecutionResult(
            state: CommitExecutionState.completed,
            commit: 'abcdef0123',
          )
        : commitResults.removeAt(0);
  }

  // Staging and discard.
  final List<StagingRequest> stagingRequests = [];
  StagingExecutionState stagingState = StagingExecutionState.completed;
  Object? stagingError;
  Completer<void>? stagingGate;
  final stagingIdentities = <RepositorySessionIdentity>[];
  StagingPhase currentStagingPhase = StagingPhase.updating;
  Completer<StagingPhase?>? stagingPhaseGate;
  Completer<void>? stagingPhaseStarted;

  @override
  Future<StagingPhase?> stagingPhase(RepositorySessionIdentity identity) async {
    if (stagingPhaseStarted case final started?) {
      if (!started.isCompleted) started.complete();
    }
    return stagingPhaseGate?.future ?? Future.value(currentStagingPhase);
  }

  final List<DiscardRequest> discardRequests = [];
  var discards = 0;
  final List<DiscardExecutionState> discardStates = [];
  final List<DiscardKind> executedDiscardKinds = [];
  final List<Object?> discardErrors = [];
  final List<Object?> discardPreviewErrors = [];
  final Map<BigInt, DiscardKind> _discardKinds = {};

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) async {
    calls.add('stage:${request.side.name}:${request.scope.name}');
    stagingRequests.add(request);
    stagingIdentities.add(identity);
    await stagingGate?.future;
    if (stagingError case final error?) throw error;
    return StagingExecutionResult(state: stagingState);
  }

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) async {
    discardRequests.add(request);
    if (discardPreviewErrors.isNotEmpty) {
      final error = discardPreviewErrors.removeAt(0);
      if (error != null) throw error;
    }
    final token = BigInt.from(discardRequests.length);
    _discardKinds[token] = request.kind;
    return DiscardPreview(
      token: token,
      kind: request.kind,
      fileCount: request.paths.length,
      arguments: const [],
    );
  }

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    discards += 1;
    executedDiscardKinds.add(_discardKinds.remove(token)!);
    if (discardErrors.isNotEmpty) {
      final error = discardErrors.removeAt(0);
      if (error != null) throw error;
    }
    return DiscardExecutionResult(
      state: discardStates.isEmpty
          ? DiscardExecutionState.completed
          : discardStates.removeAt(0),
    );
  }

  // Conflicts.
  /// Snapshots returned by successive conflict calls; the last one repeats.
  final List<ConflictSnapshot> conflictSnapshots = [];
  Object? conflictError;
  String? continuedMergeMessage;
  ConflictContinuationState continuation = ConflictContinuationState.completed;
  final List<List<int>> savedResults = [];

  ConflictSnapshot _nextConflicts() {
    if (conflictError case final error?) throw error;
    return conflictSnapshots.length > 1
        ? conflictSnapshots.removeAt(0)
        : conflictSnapshots.single;
  }

  @override
  Future<ConflictSnapshot> loadConflicts(
    RepositorySessionIdentity identity,
  ) async {
    calls.add('loadConflicts');
    return _nextConflicts();
  }

  @override
  Future<ConflictSnapshot> saveConflictResult(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    List<int> result,
  ) async {
    calls.add('saveConflict');
    savedResults.add(result);
    return _nextConflicts();
  }

  @override
  Future<ConflictSnapshot> chooseConflictSide(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    ConflictSideChoice choice,
  ) async {
    calls.add('chooseSide:${choice.name}');
    return _nextConflicts();
  }

  @override
  Future<ConflictSnapshot> takeConflictRegion(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    int regionIndex,
    ConflictRegionChoice choice,
  ) async => _nextConflicts();

  @override
  Future<ConflictSnapshot> undoConflictResolution(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    calls.add('undoConflict');
    return _nextConflicts();
  }

  @override
  Future<ConflictContinuationResult> continueConflictOperation(
    RepositorySessionIdentity identity,
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) async {
    calls.add('continue:${action.name}');
    continuedMergeMessage = mergeMessage;
    return ConflictContinuationResult(
      state: continuation,
      activityIds: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'WorkflowFakeRepository does not script ${invocation.memberName}',
  );
}
