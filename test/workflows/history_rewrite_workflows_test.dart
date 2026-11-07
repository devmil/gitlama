import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/advanced_rebase.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/host_platform.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/history_rewrite_workflows.dart';
import 'package:gitlama/services/workflows/repository_busy.dart';
import 'package:gitlama/services/workflows/window_workflows.dart';
import 'package:gitlama/services/workflows/workflow.dart';

import '../support/recording_interaction.dart';
import '../support/workflow_fake_repository.dart';

const _main = '1111111111111111111111111111111111111111';
const _topic = '2222222222222222222222222222222222222222';

RepositorySnapshot _snapshot() => RepositorySnapshot(
  revision: BigInt.one,
  phase: RepositoryPhase.ready,
  status: RepositoryStatus(
    workingTree: WorkingTreeState.dirty,
    branchName: 'main'.codeUnits,
    headObjectId: _main,
    ahead: BigInt.zero,
    behind: BigInt.zero,
    entries: const [],
    totalEntries: BigInt.zero,
    entriesTruncated: false,
    operations: const [],
  ),
  refs: RepositoryRefs(
    branches: [
      RepositoryReference(
        name: 'main'.codeUnits,
        target: _main,
        head: true,
        published: true,
      ),
      RepositoryReference(name: 'topic'.codeUnits, target: _topic),
    ],
    remotes: [
      RepositoryRemote(
        name: 'origin'.codeUnits,
        displayUrl: const [],
        branches: [RepositoryReference(name: 'main'.codeUnits, target: _main)],
      ),
    ],
    stashes: [
      RepositoryStash(
        selector: 'stash@{0}'.codeUnits,
        objectId: '3' * 40,
        subject: 'WIP on main'.codeUnits,
      ),
    ],
  ),
);

void main() {
  late WorkflowFakeRepository repository;
  late RepositorySessionService repositories;
  late OperationCenterService operationCenter;
  late WindowWorkflows workflows;
  late RecordingInteraction interaction;

  setUp(() async {
    repository = WorkflowFakeRepository(_snapshot());
    repositories = RepositorySessionService(repository);
    operationCenter = OperationCenterService.empty();
    await repositories.open('/repository');
    workflows = WindowWorkflows(
      repositories: repositories,
      operationCenter: operationCenter,
      platform: HostPlatform.linux,
    );
    interaction = RecordingInteraction();
  });

  tearDown(() async {
    await workflows.dispose();
    await repositories.dispose();
  });

  WorkspacePane? pane() => repositories.activeTab?.navigation.pane;

  group('detached commit checkout', () {
    test(
      'clean confirmation targets the exact commit and executes once',
      () async {
        interaction.checkoutChoice = CommitCheckoutChoice.checkout;
        await workflows.history.checkoutCommit(interaction, _topic);
        expect(interaction.lastCheckoutReview?.target, _topic);
        expect(interaction.lastCheckoutReview?.dirty, isFalse);
        expect(
          repository.refRequests.single.kind,
          RefMutationKind.checkoutCommit,
        );
        expect(repository.refRequests.single.target, _topic);
        expect(
          repository.calls.where((call) => call.startsWith('executeRef')),
          hasLength(1),
        );
        expect(repository.stashRequests, isEmpty);
      },
    );
    test(
      'window retirement during preview never offers later checkout plans',
      () async {
        repository.refWarnings = [RefMutationWarning.dirtyCheckout];
        repository.refPreviewGate = Completer<void>();
        final pending = workflows.history.checkoutCommit(interaction, _topic);
        interaction.active = false;
        repository.refPreviewGate!.complete();
        await pending;
        expect(repository.stashRequests, isEmpty);
        expect(interaction.lastCheckoutReview, isNull);
        expect(
          repository.calls.where((call) => call.startsWith('execute')),
          isEmpty,
        );
      },
    );
    test('dismiss and window retirement execute nothing', () async {
      await workflows.history.checkoutCommit(interaction, _topic);
      expect(
        repository.calls.where((call) => call.startsWith('execute')),
        isEmpty,
      );
      interaction.checkoutChoice = CommitCheckoutChoice.checkout;
      interaction.onAsk = (_) => interaction.active = false;
      await workflows.history.checkoutCommit(interaction, _topic);
      expect(
        repository.calls.where((call) => call.startsWith('execute')),
        isEmpty,
      );
    });
    for (final choice in [
      CommitCheckoutChoice.stash,
      CommitCheckoutChoice.stashAndReapply,
    ]) {
      test('dirty checkout executes only the chosen $choice plan', () async {
        repository.refWarnings = [RefMutationWarning.dirtyCheckout];
        interaction.checkoutChoice = choice;
        await workflows.history.checkoutCommit(interaction, _topic);
        expect(interaction.lastCheckoutReview?.dirty, isTrue);
        expect(repository.stashRequests.map((request) => request.objectId), [
          _topic,
          _topic,
        ]);
        expect(
          repository.executedStashRequest?.kind,
          choice == CommitCheckoutChoice.stash
              ? StashKind.stashCheckoutCommit
              : StashKind.autoStashCheckoutCommit,
        );
        expect(
          repository.calls.where((call) => call == 'executeStash'),
          hasLength(1),
        );
        expect(
          repository.calls.where((call) => call.startsWith('executeRef')),
          isEmpty,
        );
      });
    }
    test('dirty dismissal and invalid targets produce no mutation', () async {
      repository.refWarnings = [RefMutationWarning.dirtyCheckout];
      await workflows.history.checkoutCommit(interaction, _topic);
      await workflows.history.checkoutCommit(interaction, 'loading-1');
      await workflows.history.checkoutCommit(interaction, null);
      expect(repository.refRequests, hasLength(1));
      expect(
        repository.calls.where((call) => call.startsWith('execute')),
        isEmpty,
      );
    });
  });

  group('stash', () {
    test(
      'a stash runs under the busy overlay and reports its result',
      () async {
        interaction.stash = (draft) => StashRequest(
          kind: draft.kind,
          message: 'checkpoint',
          includeUntracked: true,
          keepIndex: true,
        );
        final busy = <bool>[];
        workflows.busy.changes.listen(
          (_) => busy.add(workflows.busy.isBlocked(repositories.activeTabId)),
        );
        interaction.onAsk = (question) {
          if (question == 'confirmStash') expect(busy, isEmpty);
        };
        await workflows.history.stash(interaction, StashKind.push);
        expect(repository.stashRequest?.message, 'checkpoint');
        expect(repository.stashRequest?.includeUntracked, isTrue);
        expect(repository.calls, ['previewStash:push', 'executeStash']);
        expect(busy, [true, false]);
        expect(interaction.log, [
          'chooseStash',
          'confirmStash',
          'history:StashFinished',
        ]);
      },
    );

    test('renaming a stash starts from its message, found by bytes', () async {
      await workflows.history.stash(
        interaction,
        StashKind.rename,
        selector: 'stash@{0}',
      );
      expect(interaction.lastStashDraft?.initialMessage, 'WIP on main');
      await workflows.history.stash(
        interaction,
        StashKind.rename,
        selector: 'stash@{9}',
      );
      expect(interaction.lastStashDraft?.initialMessage, isNull);
      expect(interaction.lastStashDraft?.branches, ['main', 'topic']);
    });

    test('a stash conflict shows Changes', () async {
      repositories.updateNavigation(
        repositories.activeTabId!,
        const WorkspaceNavigation(pane: WorkspacePane.history),
      );
      repository.stashResult = const StashExecutionResult(
        state: StashExecutionState.conflict,
        activityIds: [],
        stashCreated: false,
        checkoutCompleted: false,
        reapplyCompleted: false,
        stashRetained: true,
      );
      interaction.stash = (draft) => StashRequest(kind: draft.kind);
      await workflows.history.stash(interaction, StashKind.pop);
      expect(pane(), WorkspacePane.changes);
    });

    test('refusals and failures are reported per family', () async {
      interaction.stash = (draft) => StashRequest(kind: draft.kind);
      repository.stashPreviewError = const StashException(
        StashFailureCode.nothingToStash,
      );
      await workflows.history.stash(interaction, StashKind.push);
      expect(
        (interaction.outcomes.single as StashRefused).code,
        StashFailureCode.nothingToStash,
      );
      repository.stashPreviewError = const RemoteWorkspaceException(
        RemoteFailureCode.disconnected,
      );
      await workflows.history.stash(interaction, StashKind.push);
      final failed = interaction.outcomes.last as HistoryRewriteFailed;
      expect(failed.kind, HistoryRewriteKind.stash);
      expect(failed.failure, isA<RemoteConnectionFailure>());
    });
  });

  group('history mutations', () {
    test('a merge predicts conflicts before it asks to confirm', () async {
      interaction.mutation = (draft) => HistoryMutationRequest(
        kind: draft.kind,
        targets: const [_topic],
        sourceName: 'topic'.codeUnits,
      );
      await workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.merge,
        sourceName: 'topic',
        target: _topic,
      );
      expect(repository.calls, [
        'previewHistory:merge',
        'beginPrediction',
        'predict:merge:$_topic',
        'executeHistory',
      ]);
      expect(interaction.lastPrediction?.target, _topic);
      final draft = interaction.lastMutationDraft!;
      // Local and remote-tracking branches, with published history from the
      // snapshot. Its worktree is dirty but not conflicted.
      expect(
        draft.branches.map((branch) => String.fromCharCodes(branch.name)),
        ['main', 'topic', 'origin/main'],
      );
      expect(draft.publishedHistory, isTrue);
      expect(draft.conflictedWorktree, isFalse);
      expect(interaction.outcomes.single, isA<HistoryMutationFinished>());
    });

    test('a merge that is already contained skips prediction', () async {
      repository.historyMutationAlreadyContained = true;
      interaction.mutation = (draft) =>
          HistoryMutationRequest(kind: draft.kind, targets: const [_topic]);
      await workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.merge,
      );
      expect(repository.calls, isNot(contains('beginPrediction')));
      expect(interaction.lastPrediction, isNull);
    });

    test('a cherry-pick targets the commit it was asked for', () async {
      interaction.mutation = (draft) => HistoryMutationRequest(
        kind: draft.kind,
        targets: draft.selectedTargets,
      );
      await workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.cherryPick,
        target: _topic,
      );
      expect(interaction.lastMutationDraft?.selectedTargets, [_topic]);
      expect(repository.calls, isNot(contains('beginPrediction')));
    });

    test('a preview for another tab is dropped', () async {
      await repositories.open('/second');
      final first = repositories.workspace.tabs.first.id;
      repositories.activateTab(first);
      interaction.mutation = (draft) =>
          HistoryMutationRequest(kind: draft.kind, targets: const [_topic]);
      interaction.onAsk = (question) {
        // The user switches tabs while the dialog is open.
        if (question == 'chooseMutation') {
          repositories.activateTab(repositories.workspace.tabs.last.id);
        }
      };
      await workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.revert,
        target: _topic,
      );
      expect(repository.calls, isEmpty);
    });

    // The workflow part of home_screen_test 'a running merge blocks only its
    // own repository tab'.
    test('a running merge blocks only its own tab and cancels', () async {
      await repositories.open('/second');
      final second = repositories.activeTabId!;
      final first = repositories.workspace.tabs.first.id;
      final gate = Completer<HistoryMutationExecutionResult>();
      repository.historyMutationGate = gate;
      interaction.mutation = (draft) =>
          HistoryMutationRequest(kind: draft.kind, targets: const [_topic]);
      final running = workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.merge,
      );
      await pumpEventQueue();
      final blocking = workflows.busy.blockingOf(second)!;
      expect(blocking.activity, isA<HistoryMutationBusy>());
      expect(workflows.busy.isBlocked(first), isFalse);
      expect(blocking.cancellable, isTrue);
      await workflows.busy.cancel(blocking);
      await workflows.busy.cancel(blocking);
      expect(repository.historyMutationCancels, 1);
      expect(blocking.canceling, isTrue);
      gate.complete(
        const HistoryMutationExecutionResult(
          state: HistoryMutationExecutionState.completed,
          activityIds: [],
          conflictingPaths: [],
        ),
      );
      await running;
      expect(workflows.busy.isBlocked(second), isFalse);
      expect(interaction.outcomes.single, isA<HistoryMutationFinished>());
    });

    test('a conflict or an uncommitted revert shows Changes', () async {
      repositories.updateNavigation(
        repositories.activeTabId!,
        const WorkspaceNavigation(pane: WorkspacePane.history),
      );
      repository.historyMutationNoCommit = true;
      interaction.mutation = (draft) =>
          HistoryMutationRequest(kind: draft.kind, targets: const [_topic]);
      await workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.revert,
        target: _topic,
      );
      expect(pane(), WorkspacePane.changes);
    });

    test('a remote connection failure is reported, not thrown', () async {
      repository.historyMutationPreviewError = const RemoteWorkspaceException(
        RemoteFailureCode.disconnected,
      );
      interaction.mutation = (draft) =>
          HistoryMutationRequest(kind: draft.kind, targets: const [_topic]);
      await workflows.history.mutateHistory(
        interaction,
        HistoryMutationKind.merge,
      );
      final failed = interaction.outcomes.single as HistoryRewriteFailed;
      expect(failed.kind, HistoryRewriteKind.historyMutation);
    });

    test('integrating a branch merges or rebases as chosen', () async {
      interaction
        ..integration = BranchIntegration.rebase
        ..rebaseEdit = (
          instructions: const <RebaseInstruction>[],
          acknowledgePublishedHistory: false,
          applyAutosquash: false,
        );
      await workflows.history.integrateBranch(
        interaction,
        sourceName: 'topic',
        target: _topic,
      );
      expect(repository.calls.first, 'loadRebasePlan:$_topic');
      repository.calls.clear();
      interaction.integration = BranchIntegration.merge;
      await workflows.history.integrateBranch(
        interaction,
        sourceName: 'topic',
        target: _topic,
      );
      expect(interaction.lastMutationDraft?.initialSourceName, 'topic');
      interaction.integration = null;
      repository.calls.clear();
      await workflows.history.integrateBranch(interaction);
      expect(repository.calls, isEmpty);
    });
  });

  group('rebase and restack', () {
    test('a rebase predicts, edits, previews and runs in order', () async {
      interaction
        ..rebaseTarget = RepositoryReference(
          name: 'topic'.codeUnits,
          target: _topic,
        )
        ..rebaseEdit = (
          instructions: const <RebaseInstruction>[],
          acknowledgePublishedHistory: true,
          applyAutosquash: true,
        );
      repository.rebaseResult = const RebaseExecutionResult(
        state: RebaseExecutionState.conflict,
        activityIds: [],
        conflictingPaths: [],
      );
      await workflows.history.rebase(interaction);
      expect(repository.calls, [
        'loadRebasePlan:$_topic',
        'beginPrediction',
        'predict:rebase:$_topic',
        'previewRebase',
        'executeRebase',
      ]);
      expect(interaction.log, [
        'chooseRebaseTarget',
        'editRebase',
        'confirmRebase',
        'history:RebaseFinished',
      ]);
      expect(pane(), WorkspacePane.changes);
    });

    test('a rebase onto a known target asks for no target', () async {
      await workflows.history.rebase(interaction, target: _topic);
      expect(interaction.log.first, 'editRebase');
    });

    test('a restack with nothing to move says so', () async {
      await workflows.history.restack(interaction, 'main');
      expect(repository.calls, ['planRestack:main']);
      expect(interaction.outcomes.single, isA<RestackNothingToDo>());
    });

    test('a dismissed restack review cancels the plan', () async {
      repository.restackSteps = [
        RestackStep(
          id: 1,
          branch: 'topic'.codeUnits,
          expectedHead: _topic,
          oldParent: _main,
          newParent: 'main'.codeUnits,
          expectedNewParentHead: _main,
          published: false,
        ),
      ];
      interaction.restackReview = null;
      await workflows.history.restack(interaction, 'main');
      expect(repository.restackCancels, 1);
      interaction.restackReview = true;
      await workflows.history.restack(interaction, 'main');
      expect(repository.restackAcknowledged, isTrue);
      expect(interaction.outcomes.last, isA<RestackFinished>());
    });

    test('a refused restack reports the restack failure', () async {
      repository.restackPlanError = AdvancedRebaseException(
        AdvancedRebaseFailureCode.values.first,
      );
      await workflows.history.restack(interaction, 'main');
      final failed = interaction.outcomes.single as HistoryRewriteFailed;
      expect(failed.kind, HistoryRewriteKind.restack);
      expect(failed.failure, isNull);
    });
  });

  group('busy registry', () {
    test('operations of one tab overlap and the latest blocks', () async {
      final busy = RepositoryBusyService();
      addTearDown(busy.dispose);
      final first = Completer<void>();
      final second = Completer<void>();
      final a = busy.run(
        1,
        const StashBusy(StashKind.push),
        () => first.future,
      );
      final b = busy.run(
        1,
        const ConflictPredictionBusy(),
        () => second.future,
      );
      final c = busy.run(1, const ChangesBusy(), () async {}, blocking: false);
      expect(busy.blockingOf(1)?.activity, isA<ConflictPredictionBusy>());
      second.complete();
      await b;
      expect(busy.blockingOf(1)?.activity, isA<StashBusy>());
      first.complete();
      await a;
      await c;
      expect(busy.isBusy(1), isFalse);
      // Without a tab the work simply runs.
      expect(await busy.run(null, const ChangesBusy(), () async => 3), 3);
    });
  });

  test('workflow failures map every repository failure', () {
    expect(
      WorkflowFailure.of(const RemoteOutcomeUnknownException()),
      isA<OutcomeUnknownFailure>(),
    );
    expect(
      (WorkflowFailure.of(
                const RepositorySessionException(
                  RepositoryFailure(RepositoryFailureCode.canceled),
                ),
              )
              as SessionFailure)
          .code,
      RepositoryFailureCode.canceled,
    );
    expect(WorkflowFailure.of(StateError('other')), isNull);
  });
}
