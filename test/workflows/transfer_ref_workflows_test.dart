import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/host_platform.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/repositories/operation_center_repository.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/ref_workflows.dart';
import 'package:gitlama/services/workflows/transfer_workflows.dart';
import 'package:gitlama/services/workflows/window_workflows.dart';
import 'package:gitlama/services/workflows/workflow.dart';

import '../support/recording_interaction.dart';
import '../support/workflow_fake_repository.dart';

const _commit = '1111111111111111111111111111111111111111';

RepositorySnapshot _snapshot({
  int revision = 1,
  String head = _commit,
  int ahead = 0,
  int behind = 0,
  RepositoryRefs? refs,
}) => RepositorySnapshot(
  revision: BigInt.from(revision),
  phase: RepositoryPhase.ready,
  status: RepositoryStatus(
    workingTree: WorkingTreeState.clean,
    branchName: 'main'.codeUnits,
    headObjectId: head,
    upstream: 'origin/main'.codeUnits,
    ahead: BigInt.from(ahead),
    behind: BigInt.from(behind),
    entries: const [],
    totalEntries: BigInt.zero,
    entriesTruncated: false,
    operations: const [],
  ),
  refs:
      refs ??
      RepositoryRefs(
        branches: [
          RepositoryReference(
            name: 'main'.codeUnits,
            target: _commit,
            head: true,
          ),
          RepositoryReference(
            name: 'topic'.codeUnits,
            target: _commit,
            upstream: 'refs/remotes/origin/topic'.codeUnits,
          ),
        ],
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: 'example.test/repository'.codeUnits,
            branches: [
              RepositoryReference(name: 'topic'.codeUnits, target: _commit),
              RepositoryReference(name: 'stale'.codeUnits, target: _commit),
            ],
          ),
        ],
        tags: [RepositoryReference(name: 'v1.0.0'.codeUnits, target: _commit)],
      ),
);

final class _Operations implements OperationCenterRepository {
  OperationCenterSnapshot current = OperationCenterSnapshot.empty;

  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async =>
      current;

  @override
  Future<void> dismiss(OperationCenterEntry entry) async {}

  @override
  Future<void> dismissAll() async {}
}

TransferExecutionResult _failed(TransferFailureCode code) =>
    TransferExecutionResult(
      state: TransferExecutionState.failed,
      failure: code,
      ahead: BigInt.zero,
      behind: BigInt.zero,
    );

void main() {
  late WorkflowFakeRepository repository;
  late RepositorySessionService repositories;
  late _Operations operationRepository;
  late OperationCenterService operationCenter;
  late WindowWorkflows workflows;
  late RecordingInteraction interaction;

  Future<void> open([RepositorySnapshot? snapshot]) async {
    repository = WorkflowFakeRepository(snapshot ?? _snapshot());
    repositories = RepositorySessionService(repository);
    operationRepository = _Operations();
    operationCenter = OperationCenterService(operationRepository);
    await operationCenter.initialize();
    await repositories.open('/repository');
    workflows = WindowWorkflows(
      repositories: repositories,
      operationCenter: operationCenter,
      platform: HostPlatform.linux,
    );
    interaction = RecordingInteraction();
  }

  tearDown(() async {
    await workflows.dispose();
    await repositories.dispose();
    await operationCenter.dispose();
  });

  group('transfers', () {
    test('a pushed draft runs the chosen transfer and reports it', () async {
      await open();
      interaction.transfer = (draft) => TransferRequest(
        kind: draft.kind,
        remote: draft.initialRemote,
        forceWithLease: draft.initialForce,
      );
      await workflows.transfers.start(
        interaction,
        TransferDraft(
          kind: TransferKind.push,
          snapshot: repositories.activeTab!.session!.snapshot,
          initialRemote: 'origin',
        ),
      );
      expect(repository.transferRequests.single.kind, TransferKind.push);
      expect(repository.transferRequests.single.remote, 'origin');
      expect(repository.transferRequests.single.forceWithLease, isFalse);
      expect(interaction.log, ['chooseTransfer', 'transfer:TransferFinished']);
    });

    test(
      'an unrestored stash opens recovery without retrying authentication or pull',
      () async {
        await open();
        repository.transferResults.add(
          TransferExecutionResult(
            state: TransferExecutionState.failed,
            failure: TransferFailureCode.authentication,
            stash: const PullStashResult(
              objectId: _commit,
              pullCompleted: false,
              reapplyCompleted: false,
              conflicted: false,
            ),
            ahead: BigInt.zero,
            behind: BigInt.zero,
          ),
        );
        await workflows.transfers.execute(
          interaction,
          const TransferRequest(
            kind: TransferKind.pull,
            remote: 'origin',
            stashBeforePull: true,
          ),
        );
        expect(interaction.log, ['resolveTransferFailure']);
        expect(repository.transferRequests, hasLength(1));
        expect(interaction.lastFailureReport?.result.stash?.objectId, _commit);
      },
    );

    test(
      'a completed pull with stash conflicts asks for recovery without repeating pull',
      () async {
        await open();
        repository.transferResults.add(
          TransferExecutionResult(
            state: TransferExecutionState.completed,
            stash: const PullStashResult(
              objectId: _commit,
              pullCompleted: true,
              reapplyCompleted: false,
              conflicted: true,
            ),
            ahead: BigInt.zero,
            behind: BigInt.zero,
          ),
        );
        await workflows.transfers.execute(
          interaction,
          const TransferRequest(
            kind: TransferKind.pull,
            remote: 'origin',
            stashBeforePull: true,
          ),
        );
        expect(interaction.log, ['resolveTransferFailure']);
        expect(repository.transferRequests, hasLength(1));
      },
    );

    test('canceling the dialog runs nothing', () async {
      await open();
      await workflows.transfers.start(
        interaction,
        TransferDraft(
          kind: TransferKind.fetch,
          snapshot: repositories.activeTab!.session!.snapshot,
        ),
      );
      expect(repository.transferRequests, isEmpty);
      expect(interaction.outcomes, isEmpty);
    });

    // Moved from home_screen_test: 'a missing object offers an explicit
    // refetch without repeating pull'.
    test(
      'a missing object offers an explicit refetch without repeating pull',
      () async {
        await open();
        repository.transferResults.add(
          _failed(TransferFailureCode.missingObject),
        );
        final succeeded = await workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.pull, remote: 'origin'),
        );
        expect(succeeded, isFalse);
        expect(repository.transferRequests.map((request) => request.kind), [
          TransferKind.pull,
          TransferKind.fetch,
        ]);
        final refetch = repository.transferRequests.last;
        expect(refetch.remote, 'origin');
        expect(refetch.refetch, isTrue);
        expect(interaction.log, [
          'transfer:TransferFinished',
          'offerRefetch:origin',
          'transfer:TransferFinished',
        ]);
        final finished = interaction.outcomes.last as TransferFinished;
        expect(finished.request.refetch, isTrue);
      },
    );

    test('a held lock asks before it reports and retries on request', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.locked));
      interaction.remedy = const RetryTransfer();
      final succeeded = await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.fetch, remote: 'origin'),
      );
      expect(succeeded, isTrue);
      expect(interaction.log, [
        'resolveTransferFailure',
        'transfer:TransferFinished',
      ]);
      final report = interaction.lastFailureReport!;
      expect(report.request.remote, 'origin');
      expect(report.session, isNotNull);
      expect(report.remote, isFalse);
      expect(repository.transferRequests, hasLength(2));
    });

    test('a held lock the user leaves runs nothing more', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.locked));
      final succeeded = await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.pull, remote: 'origin'),
      );
      expect(succeeded, isFalse);
      expect(interaction.log, ['resolveTransferFailure']);
      expect(repository.transferRequests, hasLength(1));
    });

    test('fetching without pruning keeps every other choice', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.locked));
      interaction.remedy = const RetryWithoutPrune();
      await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.fetch, remote: 'origin'),
      );
      expect(repository.transferRequests.map((request) => request.prune), [
        true,
        false,
      ]);
      expect(repository.transferRequests.last.remote, 'origin');
    });

    test('a case collision repairs the tracking refs, then fetches', () async {
      await open();
      repository.transferResults.add(
        TransferExecutionResult(
          state: TransferExecutionState.failed,
          failure: TransferFailureCode.locked,
          diagnosis: const TransferDiagnosis(
            kind: TransferDiagnosisKind.refCaseCollision,
            reference: 'refs/remotes/origin/npt/x',
            related: ['refs/remotes/origin/NPT/x'],
          ),
          ahead: BigInt.zero,
          behind: BigInt.zero,
        ),
      );
      interaction.remedy = const RepairTrackingRefs([
        'refs/remotes/origin/npt/x',
        'refs/remotes/origin/NPT/x',
      ]);
      final succeeded = await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.fetch, remote: 'origin'),
      );
      expect(succeeded, isTrue);
      expect(repository.deletedTrackingRefs.single, [
        'refs/remotes/origin/npt/x',
        'refs/remotes/origin/NPT/x',
      ]);
      expect(repository.transferRequests, hasLength(2));
    });

    test('a push behind the remote offers a fetch', () async {
      await open();
      repository.transferResults.add(
        TransferExecutionResult(
          state: TransferExecutionState.failed,
          failure: TransferFailureCode.rejected,
          diagnosis: const TransferDiagnosis(
            kind: TransferDiagnosisKind.remoteAhead,
          ),
          ahead: BigInt.zero,
          behind: BigInt.zero,
        ),
      );
      interaction.remedy = const FetchRemote();
      await workflows.transfers.execute(
        interaction,
        const TransferRequest(
          kind: TransferKind.push,
          remote: 'origin',
          branch: 'main',
        ),
      );
      expect(repository.transferRequests.map((request) => request.kind), [
        TransferKind.push,
        TransferKind.fetch,
      ]);
    });

    test('a declined refetch fetches nothing more', () async {
      await open();
      repository.transferResults.add(
        _failed(TransferFailureCode.missingObject),
      );
      interaction.refetch = false;
      await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.pull, remote: 'origin'),
      );
      expect(repository.transferRequests, hasLength(1));
    });

    test('a trusted host key runs the transfer again', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.hostKey));
      final succeeded = await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.fetch),
      );
      expect(succeeded, isTrue);
      expect(repository.hostKeyDecisions, [true]);
      expect(
        repository.calls.where((call) => call.startsWith('executeTransfer')),
        hasLength(2),
      );
    });

    test('a rejected host key is recorded and nothing runs again', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.hostKey));
      interaction.trustHost = false;
      final succeeded = await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.fetch),
      );
      expect(succeeded, isFalse);
      expect(repository.hostKeyDecisions, [false]);
      expect(
        repository.calls.where((call) => call.startsWith('executeTransfer')),
        hasLength(1),
      );
      expect(interaction.outcomes, isEmpty);
    });

    test('authentication retries once with the entered credentials', () async {
      await open();
      repository.transferResults.add(
        _failed(TransferFailureCode.authentication),
      );
      interaction.credentials = const TransferCredentials(
        username: 'me',
        token: 'secret',
      );
      final succeeded = await workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.push, remote: 'origin'),
      );
      expect(succeeded, isTrue);
      expect(repository.transferCredentials.first, isNull);
      expect(repository.transferCredentials.last?.token, 'secret');
      expect(interaction.log.first, 'credentials:origin');
    });

    test(
      'a refused transfer and an unknown remote outcome are reported',
      () async {
        await open();
        repository.transferPreviewError = const TransferException(
          TransferFailureCode.detachedHead,
        );
        await workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.push),
        );
        expect(
          (interaction.outcomes.single as TransferRefused).code,
          TransferFailureCode.detachedHead,
        );
        repository.transferPreviewError = const RemoteOutcomeUnknownException();
        await workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.push),
        );
        expect(
          (interaction.outcomes.last as TransferWorkflowFailed).failure,
          isA<OutcomeUnknownFailure>(),
        );
        repository.transferPreviewError = const RemoteWorkspaceException(
          RemoteFailureCode.disconnected,
        );
        await workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.push),
        );
        expect(
          ((interaction.outcomes.last as TransferWorkflowFailed).failure
                  as RemoteConnectionFailure)
              .code,
          RemoteFailureCode.disconnected,
        );
      },
    );

    test('a window that closed is never asked or told anything', () async {
      await open();
      repository.transferResults.add(
        _failed(TransferFailureCode.missingObject),
      );
      final gate = Completer<TransferExecutionResult>();
      repository.transferGate = gate;
      final running = workflows.transfers.execute(
        interaction,
        const TransferRequest(kind: TransferKind.pull, remote: 'origin'),
      );
      await pumpEventQueue();
      interaction.active = false;
      gate.complete(_failed(TransferFailureCode.missingObject));
      expect(await running, isFalse);
      expect(interaction.log, isEmpty);
    });

    // Moved from home_screen_test: 'a running push leaves no dialog open and
    // cancels from the operation center'.
    test(
      'a running push asks nothing and cancels from the operation center',
      () async {
        await open();
        final gate = Completer<TransferExecutionResult>();
        repository.transferGate = gate;
        final running = workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.push, remote: 'origin'),
        );
        await pumpEventQueue();
        // No progress dialog: the operation center shows the running push.
        expect(interaction.log, isEmpty);
        final entry = OperationCenterEntry(
          activityId: BigInt.from(7),
          session: repositories.activeTab?.session?.identity,
          state: OperationCenterState.running,
          origin: OperationCenterOrigin.user,
          action: OperationCenterAction.push,
          startedAtUnixMs: BigInt.one,
          canCancel: false,
          canRetry: false,
          hasDetails: true,
        );
        operationRepository.current = OperationCenterSnapshot(
          entries: [entry],
          runningCount: 1,
          failedCount: 0,
          attentionCount: 0,
          truncated: false,
        );
        await operationCenter.refresh();
        expect(workflows.operations.canCancel(entry), isTrue);
        expect(workflows.operations.latest(retry: false), same(entry));
        workflows.operations.cancel(entry);
        await pumpEventQueue();
        expect(repository.canceledTransfers, [BigInt.from(200)]);

        gate.complete(_failed(TransferFailureCode.canceled));
        await running;
        // Once it ended nothing is left to cancel.
        expect(workflows.operations.canCancel(entry), isFalse);
        // A fetch entry never stands for the push.
        workflows.operations.cancel(entry);
        expect(repository.canceledTransfers, hasLength(1));
      },
    );

    test(
      'a transfer that changes the repository publishes a sync change',
      () async {
        await open();
        expect(workflows.sync.current.sequence, 0);
        final changes = <int>[];
        workflows.sync.changes.listen((change) => changes.add(change.sequence));
        // A fetch that moved nothing.
        await workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.fetch),
        );
        repository.pendingEvents.add(
          RepositorySessionEvent(
            kind: RepositorySessionEventKind.snapshot,
            snapshot: _snapshot(revision: 2),
          ),
        );
        await repositories.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(changes, isEmpty);

        await workflows.transfers.execute(
          interaction,
          const TransferRequest(kind: TransferKind.pull),
        );
        repository.pendingEvents.add(
          RepositorySessionEvent(
            kind: RepositorySessionEventKind.snapshot,
            snapshot: _snapshot(
              revision: 3,
              head: '2222222222222222222222222222222222222222',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(changes, [1]);
        expect(workflows.sync.current.changed, isTrue);
      },
    );
  });

  group('references', () {
    test('editing a branch renames before changing its upstream', () async {
      await open();
      interaction.edit = const EditBranchResult(
        name: 'renamed',
        upstream: 'origin/stale',
      );
      await workflows.refs.editBranch(interaction, 'topic');
      expect(repository.refRequests.map((request) => request.kind), [
        RefMutationKind.renameBranch,
        RefMutationKind.setUpstream,
      ]);
      expect(repository.refRequests.first.name, 'topic');
      expect(repository.refRequests.first.secondName, 'renamed');
      // The upstream change addresses the new name.
      expect(repository.refRequests.last.name, 'renamed');
      expect(repository.refRequests.last.secondName, 'origin/stale');
      final finished = interaction.outcomes.single as RefMutationFinished;
      expect(finished.state, RefMutationExecutionState.completed);
    });

    test('a failed rename leaves the upstream alone', () async {
      await open();
      repository.refResult = (request) =>
          request.kind == RefMutationKind.renameBranch
          ? RefMutationExecutionState.failed
          : RefMutationExecutionState.completed;
      interaction.edit = const EditBranchResult(
        name: 'renamed',
        upstream: null,
      );
      await workflows.refs.editBranch(interaction, 'topic');
      expect(repository.calls, [
        'previewRef:renameBranch',
        'executeRef:renameBranch',
      ]);
      expect(
        (interaction.outcomes.single as RefMutationFinished).state,
        RefMutationExecutionState.failed,
      );
    });

    test(
      'an unchanged edit changes nothing; warnings need confirmation',
      () async {
        await open();
        interaction.edit = const EditBranchResult(
          name: 'topic',
          upstream: 'origin/topic',
        );
        await workflows.refs.editBranch(interaction, 'topic');
        expect(repository.refRequests, isEmpty);

        repository.refWarnings = [RefMutationWarning.values.first];
        interaction
          ..edit = const EditBranchResult(
            name: 'other',
            upstream: 'origin/topic',
          )
          ..confirmRef = false;
        await workflows.refs.editBranch(interaction, 'topic');
        expect(repository.calls, ['previewRef:renameBranch']);
      },
    );

    // The workflow part of home_screen_test 'deleting a branch can delete
    // its upstream afterwards'.
    test('a deleted branch takes its upstream only after it went', () async {
      await open();
      interaction.refMutation = (draft) => const RefMutationRequest(
        kind: RefMutationKind.deleteBranch,
        name: 'topic',
        deleteUpstream: RefMutationUpstream(remote: 'origin', branch: 'topic'),
      );
      await workflows.refs.mutate(
        interaction,
        RefMutationKind.deleteBranch,
        initialName: 'topic',
      );
      expect(repository.calls, [
        'previewRef:deleteBranch',
        'executeRef:deleteBranch',
        'previewTransfer:deleteBranch',
        'executeTransfer:200',
      ]);
      final transfer = repository.transferRequests.single;
      expect(transfer.remote, 'origin');
      expect(transfer.branch, 'topic');
      expect(interaction.outcomes.single, isA<RefMutationFinished>());

      // A branch git refuses to delete keeps its upstream.
      repository.calls.clear();
      repository.refResult = (_) => RefMutationExecutionState.failed;
      await workflows.refs.mutate(interaction, RefMutationKind.deleteBranch);
      expect(repository.calls, [
        'previewRef:deleteBranch',
        'executeRef:deleteBranch',
      ]);
    });

    test('a failed upstream deletion is reported by its name', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.rejected));
      await workflows.refs.run(
        interaction,
        const RefMutationRequest(
          kind: RefMutationKind.deleteBranch,
          name: 'topic',
          deleteUpstream: RefMutationUpstream(
            remote: 'origin',
            branch: 'topic',
          ),
        ),
      );
      expect(
        (interaction.outcomes.single as UpstreamDeleteFailed).label,
        'origin/topic',
      );
    });

    test('a tag goes on its remotes before it goes locally', () async {
      await open();
      await workflows.refs.run(
        interaction,
        const RefMutationRequest(
          kind: RefMutationKind.deleteTag,
          name: 'v1.0.0',
          remoteNames: ['origin'],
        ),
      );
      // The confirmation shows the lease on the local tag's target.
      expect(interaction.log.first, 'confirmRef:deleteTag:$_commit');
      expect(repository.calls, [
        'previewRef:deleteTag',
        'previewTransfer:deleteTag',
        'executeTransfer:200',
        'executeRef:deleteTag',
      ]);
      expect(repository.transferRequests.single.branch, 'v1.0.0');
    });

    test('a tag a remote kept stays locally too', () async {
      await open();
      repository.transferResults.add(_failed(TransferFailureCode.rejected));
      await workflows.refs.run(
        interaction,
        const RefMutationRequest(
          kind: RefMutationKind.deleteTag,
          name: 'v1.0.0',
          remoteNames: ['origin'],
        ),
      );
      expect(repository.calls, isNot(contains('executeRef:deleteTag')));
      expect(
        (interaction.outcomes.single as RemoteTagDeleteFailed).remote,
        'origin',
      );
    });

    test(
      'a local failure after the remote deletion says the remote went',
      () async {
        await open();
        repository.refResult = (_) => RefMutationExecutionState.failed;
        await workflows.refs.run(
          interaction,
          const RefMutationRequest(
            kind: RefMutationKind.deleteTag,
            name: 'v1.0.0',
            remoteNames: ['origin'],
          ),
        );
        final finished = interaction.outcomes.single as RefMutationFinished;
        expect(finished.remoteTagDeleted, isTrue);
        expect(finished.state, RefMutationExecutionState.failed);
      },
    );

    test(
      'a remote-tracking branch checks out the branch tracking it',
      () async {
        await open();
        await workflows.refs.checkout(
          interaction,
          'origin/topic',
          'refs/remotes/origin/topic',
        );
        expect(interaction.lastRefDraft?.kind, RefMutationKind.checkoutBranch);
        expect(interaction.lastRefDraft?.initialName, 'topic');

        // Without a local branch a new one tracks it.
        await workflows.refs.checkout(interaction, 'origin/stale', null);
        expect(interaction.lastRefDraft?.kind, RefMutationKind.createBranch);
        expect(interaction.lastRefDraft?.initialName, 'stale');
        expect(
          interaction.lastRefDraft?.initialTarget,
          'refs/remotes/origin/stale',
        );

        // A local branch checks out as it is.
        await workflows.refs.checkout(interaction, 'topic', null);
        expect(interaction.lastRefDraft?.kind, RefMutationKind.checkoutBranch);
        expect(interaction.lastRefDraft?.initialName, 'topic');
      },
    );

    test(
      'branch defaults to HEAD and keeps an explicit context target',
      () async {
        await open();
        const selected = '2222222222222222222222222222222222222222';
        repository.historyResult = HistoryPage(
          requestId: BigInt.one,
          complete: true,
          totalRows: 1,
          offset: 0,
          rows: const [
            HistoryTopologyRow(
              objectId: selected,
              parents: [],
              refs: [],
              lane: 0,
              shape: 0,
            ),
          ],
          laneCount: 1,
          payloadBytes: 0,
          selectedObjectIds: const [selected],
        );
        // History has a genuine selection different from HEAD.
        await repositories.history.load(
          repositories.activeTab!.session!.identity,
        );
        await repositories.history.select(selected);
        expect(repositories.history.current.targetObjectId, selected);
        await workflows.refs.mutate(interaction, RefMutationKind.createBranch);
        expect(interaction.lastRefDraft?.initialTarget, _commit);
        expect(
          interaction.lastRefDraft?.session,
          repositories.activeTab!.session!.identity,
        );
        await workflows.refs.mutate(
          interaction,
          RefMutationKind.createBranch,
          initialTarget: 'explicit',
        );
        expect(interaction.lastRefDraft?.initialTarget, 'explicit');
      },
    );

    test(
      'missing target preserves input and refresh never replays the write',
      () async {
        await open();
        const request = RefMutationRequest(
          kind: RefMutationKind.createBranch,
          name: 'release/v2',
          target: 'missing',
          checkout: false,
        );
        repository.refPreviewError = const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.missingObject),
        );
        interaction.recoverTarget = true;
        repository.publishRefreshSnapshot = true;
        var choices = 0;
        interaction.refMutation = (draft) {
          choices++;
          if (choices == 1) return request;
          expect(draft.previousRequest, same(request));
          expect(draft.previousRequest!.target, 'missing');
          expect(draft.previousRequest!.checkout, isFalse);
          return null; // Refresh alone must never retry the mutation.
        };
        await workflows.refs.mutate(interaction, RefMutationKind.createBranch);
        expect(choices, 2);
        expect(repository.refRequests, [request]);
        expect(
          repository.calls.where((c) => c.startsWith('executeRef')),
          isEmpty,
        );
        expect(interaction.log, contains('recoverRefTarget'));
      },
    );

    test('missing target can be reselected and explicitly confirmed', () async {
      await open();
      repository.refPreviewError = const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.missingObject),
      );
      interaction.recoverTarget = true;
      repository.publishRefreshSnapshot = true;
      var choices = 0;
      interaction.refMutation = (draft) {
        if (++choices == 2) repository.refPreviewError = null;
        return RefMutationRequest(
          kind: RefMutationKind.createBranch,
          name: 'release/v2',
          target: choices == 1 ? 'missing' : _commit,
          checkout: true,
        );
      };
      await workflows.refs.mutate(interaction, RefMutationKind.createBranch);
      expect(repository.refRequests.map((r) => r.target), ['missing', _commit]);
      expect(
        repository.calls.where((c) => c.startsWith('executeRef')).length,
        1,
      );
      expect(
        interaction.log.where((c) => c.startsWith('confirmRef')).length,
        1,
      );
      expect(
        (interaction.outcomes.single as RefMutationFinished).state,
        RefMutationExecutionState.completed,
      );
    });

    test(
      'reselection waits for refreshed references to reach the workspace',
      () async {
        await open();
        repository.refPreviewError = const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.missingObject),
        );
        repository.publishRefreshSnapshot = true;
        final refreshed = repository.refreshGate = Completer<void>();
        interaction.recoverTarget = true;
        var choices = 0;
        interaction.refMutation = (draft) {
          if (++choices == 2) {
            expect(
              repositories.activeTab!.session!.snapshot.revision,
              BigInt.two,
            );
            return null;
          }
          return const RefMutationRequest(
            kind: RefMutationKind.createBranch,
            name: 'topic',
            target: 'missing',
          );
        };
        final operation = workflows.refs.mutate(
          interaction,
          RefMutationKind.createBranch,
        );
        await Future<void>.delayed(Duration.zero);
        expect(choices, 1);
        refreshed.complete();
        await operation;
        expect(choices, 2);
      },
    );

    test(
      'switching repositories during confirmation prevents execution',
      () async {
        await open();
        final firstTab = repositories.activeTab!.id;
        await repositories.open('/other');
        final otherTab = repositories.activeTab!.id;
        repositories.activateTab(firstTab);
        interaction.onAsk = (question) {
          if (question.startsWith('confirmRef:')) {
            repositories.activateTab(otherTab);
          }
        };
        await workflows.refs.run(
          interaction,
          const RefMutationRequest(
            kind: RefMutationKind.createBranch,
            name: 'topic',
            target: _commit,
          ),
        );
        expect(
          repository.calls.where((c) => c.startsWith('executeRef')),
          isEmpty,
        );
        expect(
          (interaction.outcomes.single as RefWorkflowFailed).failure,
          isA<SessionFailure>(),
        );
      },
    );

    test('refresh failure releases its snapshot wait', () async {
      await open();
      repository.refreshError = const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.read),
      );
      await expectLater(
        repositories.refreshAndWait(repositories.activeTab!.session!.identity),
        throwsA(isA<RepositorySessionException>()),
      );
    });

    test(
      'closing the repository retires an outstanding refresh wait',
      () async {
        await open();
        final gate = repository.refreshGate = Completer<void>();
        final tab = repositories.activeTab!;
        final waiting = expectLater(
          repositories.refreshAndWait(tab.session!.identity),
          throwsA(isA<RepositorySessionException>()),
        );
        await repositories.closeTab(tab.id);
        await waiting;
        gate.complete();
      },
    );

    test('canceling missing-target recovery does not retry', () async {
      await open();
      repository.refPreviewError = const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.missingObject),
      );
      interaction.refMutation = (draft) => const RefMutationRequest(
        kind: RefMutationKind.createBranch,
        name: 'topic',
        target: _commit,
      );
      await workflows.refs.mutate(interaction, RefMutationKind.createBranch);
      expect(repository.refRequests.length, 1);
      expect(
        repository.calls.where((c) => c.startsWith('executeRef')),
        isEmpty,
      );
    });

    test('a repository switch while choosing rejects the draft', () async {
      await open();
      final firstTab = repositories.activeTab!.id;
      await repositories.open('/other');
      repositories.activateTab(firstTab);
      interaction.refMutation = (draft) {
        repositories.activateTab(repositories.workspace.tabs.last.id);
        return const RefMutationRequest(
          kind: RefMutationKind.createBranch,
          name: 'topic',
          target: _commit,
        );
      };
      await workflows.refs.mutate(interaction, RefMutationKind.createBranch);
      expect(repository.refRequests, isEmpty);
      expect(
        (interaction.outcomes.single as RefMutationFinished).state,
        RefMutationExecutionState.stale,
      );
    });

    test('a late preview after a repository switch never executes', () async {
      await open();
      final gate = repository.refPreviewGate = Completer<void>();
      final operation = workflows.refs.run(
        interaction,
        const RefMutationRequest(
          kind: RefMutationKind.createBranch,
          name: 'topic',
          target: _commit,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await repositories.open('/other');
      gate.complete();
      await operation;
      expect(
        repository.calls.where((c) => c.startsWith('executeRef')),
        isEmpty,
      );
      expect(interaction.log.where((c) => c.startsWith('confirmRef')), isEmpty);
      expect(
        (interaction.outcomes.single as RefWorkflowFailed).failure,
        isA<SessionFailure>(),
      );
    });

    test('a remote branch deletion preselects exactly that branch', () async {
      await open();
      await workflows.refs.deleteRemoteBranch(
        interaction,
        'refs/remotes/origin/stale',
      );
      expect(interaction.lastTransferDraft?.kind, TransferKind.deleteBranch);
      expect(interaction.lastTransferDraft?.initialRemote, 'origin');
      expect(interaction.lastTransferDraft?.initialBranch, 'stale');

      // An unknown reference preselects nothing, not even the current branch.
      await workflows.refs.deleteRemoteBranch(interaction, 'refs/remotes/x/y');
      expect(interaction.lastTransferDraft?.initialRemote, isNull);
      expect(interaction.lastTransferDraft?.initialBranch, '');
    });

    test('session failures and unknown outcomes are reported', () async {
      await open();
      repository.refPreviewError = const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.unknownSession),
      );
      await workflows.refs.run(
        interaction,
        const RefMutationRequest(
          kind: RefMutationKind.deleteTag,
          name: 'v1.0.0',
        ),
      );
      expect(
        (interaction.outcomes.single as RefWorkflowFailed).failure,
        isA<SessionFailure>(),
      );
      repository.refPreviewError = const RemoteOutcomeUnknownException();
      interaction.edit = const EditBranchResult(name: 'x', upstream: null);
      await workflows.refs.editBranch(interaction, 'topic');
      expect(
        (interaction.outcomes.last as RefWorkflowFailed).failure,
        isA<OutcomeUnknownFailure>(),
      );
    });
  });
}
