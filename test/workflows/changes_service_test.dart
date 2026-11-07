import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/host_platform.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/working_tree.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/changes_service.dart';
import 'package:gitlama/services/workflows/window_workflows.dart';
import 'package:gitlama/services/workflows/workflow.dart';

import '../support/workflow_fake_repository.dart';

RepositoryStatusEntry _entry(
  String path, {
  StatusEntryKind kind = StatusEntryKind.ordinary,
  ChangeKind index = ChangeKind.unmodified,
  ChangeKind worktree = ChangeKind.modified,
}) => RepositoryStatusEntry(
  kind: kind,
  path: NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: path.codeUnits,
  ),
  index: index,
  worktree: worktree,
);

RepositorySnapshot _snapshot(List<RepositoryStatusEntry> entries) =>
    RepositorySnapshot(
      revision: BigInt.one,
      phase: RepositoryPhase.ready,
      status: RepositoryStatus(
        workingTree: WorkingTreeState.dirty,
        headObjectId: '1' * 40,
        ahead: BigInt.zero,
        behind: BigInt.zero,
        entries: entries,
        totalEntries: BigInt.from(entries.length),
        entriesTruncated: false,
        operations: const [],
      ),
    );

final class _Interaction implements ChangesInteraction {
  @override
  bool active = true;
  bool confirm = true;
  final List<ChangesOutcome> reports = [];

  final List<DiscardReview> reviews = [];
  FutureOr<void> Function()? onConfirm;
  @override
  Future<bool> confirmDiscard(DiscardReview preview) async {
    reviews.add(preview);
    await onConfirm?.call();
    return confirm;
  }

  @override
  void reportChanges(ChangesOutcome outcome) => reports.add(outcome);
}

void main() {
  final a = _entry('a.txt');
  final b = _entry('b.txt');
  final c = _entry('c.txt');
  final staged = _entry(
    's.txt',
    index: ChangeKind.modified,
    worktree: ChangeKind.unmodified,
  );
  final untracked = _entry(
    'new.txt',
    kind: StatusEntryKind.untracked,
    worktree: ChangeKind.unmodified,
  );

  late WorkflowFakeRepository repository;
  late RepositorySessionService repositories;
  late WindowWorkflows workflows;
  late ChangesService changes;
  late _Interaction interaction;
  late int tab;

  Future<void> open(List<RepositoryStatusEntry> entries) async {
    repository = WorkflowFakeRepository(_snapshot(entries));
    repositories = RepositorySessionService(repository);
    await repositories.open('/repository');
    workflows = WindowWorkflows(
      repositories: repositories,
      operationCenter: OperationCenterService.empty(),
      platform: HostPlatform.linux,
    );
    changes = workflows.changes;
    interaction = _Interaction();
    tab = repositories.activeTabId!;
  }

  tearDown(() async {
    await workflows.dispose();
    await repositories.dispose();
  });

  test('staging a file selects the next one of the same list', () async {
    await open([a, b, c, staged]);
    changes.select(tab, StagingSide.unstaged, {changeKey(b)});
    await changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [b],
    );
    final request = repository.stagingRequests.single;
    expect(request.side, StagingSide.unstaged);
    expect(request.requestId, BigInt.zero);
    expect(request.paths, [utf8Bytes('b.txt')]);
    expect(changes.selectionOf(tab).unstaged, {changeKey(c)});
    expect(changes.selectionOf(tab).focusedSide, StagingSide.unstaged);
    expect(repositories.activeTab?.navigation.selectedIdentity, 'c.txt');
    expect(
      (interaction.reports.single as StagingFinished).state,
      StagingExecutionState.completed,
    );
  });

  test(
    'whole-file selection sends row identities and leaves rename expansion to native',
    () async {
      final renamed = RepositoryStatusEntry(
        kind: StatusEntryKind.rename,
        path: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: 'new.txt'.codeUnits,
        ),
        source: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: 'old.txt'.codeUnits,
        ),
        index: ChangeKind.renamed,
        worktree: ChangeKind.modified,
      );
      await open([renamed]);
      await changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [renamed],
      );
      expect(repository.stagingRequests.single.paths, ['new.txt'.codeUnits]);
    },
  );

  test(
    'unexpected staging errors roll back movement and report a safe failure',
    () async {
      await open([a]);
      repository.stagingError = StateError('confidential-error-sentinel');
      await changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.all,
        [a],
      );
      expect(
        (interaction.reports.single as StagingFailed).failure,
        isA<UnexpectedFailure>(),
      );
      expect(changes.selectionOf(tab).unstaged, isEmpty);
    },
  );

  test('the last file of a list follows itself to the other list', () async {
    await open([a, staged]);
    await changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    expect(changes.selectionOf(tab).staged, {changeKey(a)});
    expect(changes.selectionOf(tab).unstaged, isEmpty);
    expect(changes.selectionOf(tab).focusedSide, StagingSide.staged);
  });

  test('a moving file is announced and a failed move comes back', () async {
    await open([a, b]);
    final effects = <ChangesEffect>[];
    changes.effects.listen(effects.add);
    repository.stagingState = StagingExecutionState.stale;
    await changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    expect(effects[0], isA<ChangesMoveStarted>());
    expect((effects[0] as ChangesMoveStarted).single, same(a));
    expect(effects[1], isA<ChangesActionFailed>());
    expect((effects[2] as ChangesMoveEnded).moved, isFalse);
    expect(changes.selectionOf(tab).unstaged, isEmpty);
  });

  test('whole-file requests queue and execute serially per tab', () async {
    await open([a, b]);
    final gate = repository.stagingGate = Completer<void>();
    final first = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    final second = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [b],
    );
    expect(repository.stagingRequests, hasLength(1));
    expect(changes.pendingStages(tab), 1);
    expect(changes.pendingKeys(tab, StagingSide.unstaged), {
      changeKey(a),
      changeKey(b),
    });
    gate.complete();
    await Future.wait([first, second]);
    expect(repository.stagingRequests, hasLength(2));
    expect(repository.stagingRequests[1].paths, [utf8Bytes('b.txt')]);
    expect(changes.pendingStages(tab), 0);
    expect(changes.busy(tab), isFalse);
  });

  test(
    'completion preserves selection and navigation made during staging',
    () async {
      await open([a, b, c]);
      changes.select(tab, StagingSide.unstaged, {changeKey(a)});
      final gate = repository.stagingGate = Completer<void>();
      final running = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [a],
      );
      changes.select(tab, StagingSide.unstaged, {changeKey(c)});
      workflows.navigator.selectIdentity('c.txt');
      gate.complete();
      await running;
      expect(changes.selectionOf(tab).unstaged, {changeKey(c)});
      expect(repositories.activeTab?.navigation.selectedIdentity, 'c.txt');
    },
  );

  test(
    'queued work stays bound to its original session after tab switch',
    () async {
      await open([a, b]);
      final identity = repositories.activeTab!.session!.identity;
      final gate = repository.stagingGate = Completer<void>();
      final first = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [a],
      );
      final second = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [b],
      );
      await repositories.open('/other');
      gate.complete();
      await Future.wait([first, second]);
      expect(repository.stagingIdentities, hasLength(2));
      expect(
        repository.stagingIdentities.every(
          (value) => identical(value, identity),
        ),
        isTrue,
      );
      expect(
        repositories.activeTab!.navigation.selectedIdentity,
        isNot('b.txt'),
      );
    },
  );

  test('canceling pending actions leaves the running write alone', () async {
    await open([a, b]);
    final gate = repository.stagingGate = Completer<void>();
    final first = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    final second = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [b],
    );
    changes.clearPendingStages(tab);
    await second;
    expect(changes.pendingStages(tab), 0);
    expect(changes.busy(tab), isTrue);
    gate.complete();
    await first;
    expect(repository.stagingRequests, hasLength(1));
  });

  for (final result in [
    StagingExecutionState.failed,
    StagingExecutionState.stale,
    StagingExecutionState.outcomeUncertain,
    StagingExecutionState.reconciledWithWarning,
  ]) {
    test('$result stops queued actions', () async {
      await open([a, b]);
      repository.stagingState = result;
      final gate = repository.stagingGate = Completer<void>();
      final first = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [a],
      );
      final second = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [b],
      );
      gate.complete();
      await Future.wait([first, second]);
      // Whole-file stale is retried once by WorkingCopyCommands, never replayed from the queue.
      expect(
        repository.stagingRequests,
        hasLength(result == StagingExecutionState.stale ? 2 : 1),
      );
      expect(
        repository.stagingRequests.every(
          (request) => String.fromCharCodes(request.paths.single) == 'a.txt',
        ),
        isTrue,
      );
      expect(changes.pendingStages(tab), 0);
      expect(changes.stoppedStages(tab), 1);
      changes.dismissStoppedStages(tab);
      expect(changes.stoppedStages(tab), 0);
    });
  }

  test(
    'closing a tab retires pending requests before the running result',
    () async {
      await open([a, b]);
      final gate = repository.stagingGate = Completer<void>();
      final first = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [a],
      );
      final second = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [b],
      );
      await repositories.closeTab(tab);
      await second;
      gate.complete();
      await first;
      expect(repository.stagingRequests, hasLength(1));
      expect(interaction.reports, isEmpty);
    },
  );

  test('duplicates are ignored and row patches cannot queue', () async {
    await open([a, b]);
    final gate = repository.stagingGate = Completer<void>();
    final first = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    await changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    await changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.rows,
      [b],
      rowIds: ['row'],
    );
    await changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.all,
      [a, b],
    );
    expect(changes.pendingStages(tab), 0);
    gate.complete();
    await first;
    expect(repository.stagingRequests, hasLength(1));
  });

  test('queue admission is bounded and resumes after cancellation', () async {
    final entries = List.generate(
      ChangesService.maximumPendingStages + 2,
      (i) => _entry('$i.txt'),
    );
    await open(entries);
    final gate = repository.stagingGate = Completer<void>();
    final requests = [
      changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [entries.first],
      ),
    ];
    for (final entry in entries.skip(1)) {
      requests.add(
        changes.stage(
          interaction,
          tab,
          StagingSide.unstaged,
          StagingScope.files,
          [entry],
        ),
      );
    }
    expect(changes.pendingStages(tab), ChangesService.maximumPendingStages);
    expect(changes.canStageFiles(tab), isFalse);
    changes.clearPendingStages(tab);
    expect(changes.canStageFiles(tab), isTrue);
    gate.complete();
    await Future.wait(requests);
    expect(repository.stagingRequests, hasLength(1));
  });

  test('native phases publish while a staging call is still pending', () async {
    await open([a]);
    final gate = repository.stagingGate = Completer<void>();
    final running = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    expect(changes.stagingPhase(tab), StagingPhase.waiting);
    repository.currentStagingPhase = StagingPhase.refreshing;
    await changes.changes
        .firstWhere((_) => changes.stagingPhase(tab) == StagingPhase.refreshing)
        .timeout(const Duration(seconds: 5));
    gate.complete();
    await running;
    expect(changes.stagingPhase(tab), isNull);
  });

  test(
    'retiring the workflow settles queued requests before the active write',
    () async {
      await open([a, b]);
      final gate = repository.stagingGate = Completer<void>();
      final first = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [a],
      );
      final second = changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [b],
      );
      await changes.dispose();
      await second;
      gate.complete();
      await first;
      expect(repository.stagingRequests, hasLength(1));
      expect(interaction.reports, isEmpty);
    },
  );

  test('a late phase reply cannot resurrect a finished operation', () async {
    await open([a]);
    final gate = repository.stagingGate = Completer<void>();
    final reply = repository.stagingPhaseGate = Completer<StagingPhase?>();
    final started = repository.stagingPhaseStarted = Completer<void>();
    final running = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    await started.future.timeout(const Duration(seconds: 5));
    gate.complete();
    await running;
    reply.complete(StagingPhase.refreshing);
    await Future<void>.delayed(Duration.zero);
    expect(changes.stagingPhase(tab), isNull);
  });

  test('an unknown remote outcome stops every queued request', () async {
    await open([a, b]);
    repository.stagingError = const RemoteOutcomeUnknownException();
    final gate = repository.stagingGate = Completer<void>();
    final first = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [a],
    );
    final second = changes.stage(
      interaction,
      tab,
      StagingSide.unstaged,
      StagingScope.files,
      [b],
    );
    gate.complete();
    await Future.wait([first, second]);
    expect(repository.stagingRequests, hasLength(1));
    expect(changes.stoppedStages(tab), 1);
    expect(
      (interaction.reports.single as StagingFailed).failure,
      isA<OutcomeUnknownFailure>(),
    );
  });

  test(
    'an unknown remote staging outcome is neither failed nor retried',
    () async {
      await open([a]);
      repository.stagingError = const RemoteOutcomeUnknownException();
      final effects = <ChangesEffect>[];
      changes.effects.listen(effects.add);
      await changes.stage(
        interaction,
        tab,
        StagingSide.unstaged,
        StagingScope.files,
        [a],
      );
      expect(
        (interaction.reports.single as StagingFailed).failure,
        isA<OutcomeUnknownFailure>(),
      );
      expect(effects.whereType<ChangesActionFailed>(), isEmpty);
    },
  );

  test(
    'mixed discard reviews both scopes once before cleaning then restoring',
    () async {
      await open([a, untracked]);
      expect(discardKindOf([a]), DiscardKind.discard);
      expect(discardKindOf([untracked]), DiscardKind.clean);
      expect(discardKindOf([a, untracked]), DiscardKind.discard);
      expect(discardKindOf([]), isNull);
      expect(
        discardKindOf([_entry('x', kind: StatusEntryKind.unmerged)]),
        isNull,
      );
      interaction.onConfirm = () {
        expect(repository.discardRequests.length, 2);
        expect(repository.discards, 0);
      };
      await changes.discard(interaction, tab, [a, untracked]);
      expect(interaction.reviews.single.trackedFiles, 1);
      expect(interaction.reviews.single.untrackedFiles, 1);
      expect(repository.discardRequests.first.paths, [untracked.path.units]);
      expect(repository.discardRequests.last.paths, [a.path.units]);
      expect(repository.executedDiscardKinds, [
        DiscardKind.clean,
        DiscardKind.discard,
      ]);
      expect(
        (interaction.reports.single as DiscardFinished).state,
        DiscardExecutionState.completed,
      );
    },
  );

  test('canceling a mixed discard executes neither part', () async {
    await open([a, untracked]);
    interaction.confirm = false;
    await changes.discard(interaction, tab, [a, untracked]);
    expect(repository.discardRequests.length, 2);
    expect(repository.discards, 0);
    expect(interaction.reports, isEmpty);
  });

  test(
    'retiring the interaction during confirmation executes neither part',
    () async {
      await open([a, untracked]);
      interaction.onConfirm = () => interaction.active = false;
      await changes.discard(interaction, tab, [a, untracked]);
      expect(repository.discards, 0);
    },
  );

  test('changing tabs during confirmation executes neither part', () async {
    await open([a, untracked]);
    interaction.onConfirm = () async {
      await repositories.open('/other');
    };
    await changes.discard(interaction, tab, [a, untracked]);
    expect(repository.discards, 0);
  });

  test(
    'a failed second preview executes neither part or confirmation',
    () async {
      await open([a, untracked]);
      repository.discardPreviewErrors.addAll([
        null,
        StateError('preview failed'),
      ]);
      await changes.discard(interaction, tab, [a, untracked]);
      expect(repository.discards, 0);
      expect(interaction.reviews, isEmpty);
      expect(interaction.reports.single, isA<DiscardFailed>());
    },
  );

  test(
    'a second execution exception reports the first completed scope',
    () async {
      await open([a, untracked]);
      repository.discardErrors.addAll([null, StateError('execution failed')]);
      await changes.discard(interaction, tab, [a, untracked]);
      final outcome = interaction.reports.single as DiscardPartiallyFinished;
      expect(outcome.completedFiles, 1);
      expect(outcome.totalFiles, 2);
    },
  );

  test(
    'single-kind discard still cleans or restores and supports cancel',
    () async {
      await open([a, untracked]);
      await changes.discard(interaction, tab, [untracked]);
      expect(repository.discardRequests.single.kind, DiscardKind.clean);
      expect(repository.discards, 1);
      interaction.confirm = false;
      await changes.discard(interaction, tab, [a]);
      expect(repository.discards, 1);
    },
  );

  test('a stale clean stops before tracked changes are restored', () async {
    await open([a, untracked]);
    repository.discardStates.add(DiscardExecutionState.stale);
    await changes.discard(interaction, tab, [a, untracked]);
    expect(repository.discards, 1);
    expect(
      (interaction.reports.single as DiscardFinished).state,
      DiscardExecutionState.stale,
    );
  });

  for (final state in [
    DiscardExecutionState.stale,
    DiscardExecutionState.failed,
    DiscardExecutionState.outcomeUncertain,
  ]) {
    test('tracked $state after clean reports partial completion', () async {
      await open([a, untracked]);
      repository.discardStates.addAll([DiscardExecutionState.completed, state]);
      await changes.discard(interaction, tab, [a, untracked]);
      final outcome = interaction.reports.single as DiscardPartiallyFinished;
      expect(outcome.completedFiles, 1);
      expect(outcome.totalFiles, 2);
    });
  }

  test('an untracked file has no lines to discard', () {
    expect(canDiscardLines(untracked, StagingSide.unstaged), isFalse);
    expect(canDiscardLines(a, StagingSide.unstaged), isTrue);
    expect(canDiscardLines(staged, StagingSide.staged), isFalse);
    expect(canDiscardLines(null, StagingSide.unstaged), isFalse);
  });

  test('selection commands follow what is selected', () async {
    await open([a, untracked, staged]);
    expect(changes.disabledSelectionCommands(tab), {
      AppCommandId.stageSelection,
      AppCommandId.unstageSelection,
      AppCommandId.discardChanges,
      AppCommandId.stageToggle,
    });
    // Mixed tracked and untracked selections can be discarded together.
    changes.select(tab, StagingSide.unstaged, {
      changeKey(a),
      changeKey(untracked),
    });
    expect(changes.disabledSelectionCommands(tab), {
      AppCommandId.unstageSelection,
    });
    changes.select(tab, StagingSide.unstaged, {changeKey(a)});
    expect(changes.disabledSelectionCommands(tab), {
      AppCommandId.unstageSelection,
    });
    // Selected diff lines count for the focused list.
    changes
      ..select(tab, StagingSide.staged, const {})
      ..setDiffRowsSelected(tab, true);
    expect(changes.disabledSelectionCommands(tab), {
      AppCommandId.stageSelection,
      AppCommandId.discardChanges,
    });
  });

  test('selected diff lines take Space and Discard', () async {
    await open([a]);
    final effects = <ChangesEffect>[];
    changes.effects.listen(effects.add);
    changes.setDiffRowsSelected(tab, true);
    changes
      ..toggleFocused(interaction, tab)
      ..discardSelection(interaction, tab);
    expect(effects.whereType<DiffSelectionRequested>().map((e) => e.discard), [
      false,
      true,
    ]);
    expect(repository.stagingRequests, isEmpty);
  });

  test('a filter keeps only the selected files it shows', () async {
    await open([a, b]);
    changes.select(tab, StagingSide.unstaged, {changeKey(a), changeKey(b)});
    changes.retain(tab, {changeKey(b)});
    expect(changes.selectionOf(tab).unstaged, {changeKey(b)});
  });

  test(
    'a patch covers the other list when the focused one has nothing',
    () async {
      await open([a, staged]);
      changes.select(tab, StagingSide.staged, {changeKey(staged)});
      changes.focus(tab, StagingSide.unstaged);
      final selection = changes.patchSelection(tab);
      expect(selection.side, StagingSide.staged);
      expect(selection.entries, [staged]);
    },
  );

  test(
    'a paused operation without conflicts still opens the resolver',
    () async {
      await open([a]);
      repository.conflictSnapshots.add(
        ConflictSnapshot(
          operation: ConflictOperationKind.rebase,
          currentLabel: const [],
          incomingLabel: const [],
          files: const [],
          resolvedUndoPaths: const [],
          canContinue: true,
          canSkip: true,
        ),
      );
      expect(changes.conflictFlow(tab), isFalse);
      await changes.probeConflicts(tab);
      expect(changes.conflictFlow(tab), isTrue);
      changes.finishConflictFlow(tab);
      expect(changes.conflictFlow(tab), isFalse);
      // No operation left: the probe keeps the lists.
      repository.conflictError = const ConflictException(
        ConflictFailureCode.noActiveOperation,
      );
      await changes.probeConflicts(tab);
      expect(changes.conflictFlow(tab), isFalse);
    },
  );

  test(
    'a conflicted status opens the resolver until the user leaves it',
    () async {
      await open([_entry('x', kind: StatusEntryKind.unmerged)]);
      expect(changes.conflictFlow(tab), isTrue);
      changes.finishConflictFlow(tab);
      expect(changes.conflictFlow(tab), isFalse);
    },
  );

  test('a window that closed hears nothing', () async {
    await open([a, b]);
    interaction.active = false;
    final done = Completer<void>();
    unawaited(
      changes
          .stage(interaction, tab, StagingSide.unstaged, StagingScope.files, [
            a,
          ])
          .whenComplete(done.complete),
    );
    await done.future;
    expect(interaction.reports, isEmpty);
  });
}

List<int> utf8Bytes(String value) => value.codeUnits;
