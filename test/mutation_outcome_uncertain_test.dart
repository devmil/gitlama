import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/labels.dart';
import 'package:gitlama/app/workspace/status_bar.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/advanced_rebase.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/named_snapshot.dart';
import 'package:gitlama/models/power_tools.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_extensions.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/repositories/impl/native_enum_mappers.g.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/advanced_rebase.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/dto.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/conflict.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/extensions.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/history_operation.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/named_snapshot.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/power_tools.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/rebase_operation.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/stash.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/transfer.dart';
import 'package:gitlama/services/workflows/changes_service.dart';
import 'package:gitlama/services/workflows/conflict_resolution.dart';

/// A mutation Git could not confirm stays uncertain from the bridge to the
/// message: no family turns it into a failure or a success.
void main() {
  test('every family maps the bridge uncertain state to its model', () {
    expect(
      NativeStagingExecutionState.outcomeUncertain.toModel(),
      StagingExecutionState.outcomeUncertain,
    );
    expect(
      NativeCommitExecutionState.outcomeUncertain.toModel(),
      CommitExecutionState.outcomeUncertain,
    );
    expect(
      NativeDiscardExecutionState.outcomeUncertain.toModel(),
      DiscardExecutionState.outcomeUncertain,
    );
    expect(
      NativeRefMutationExecutionState.outcomeUncertain.toModel(),
      RefMutationExecutionState.outcomeUncertain,
    );
    expect(
      NativeStashExecutionState.outcomeUncertain.toModel(),
      StashExecutionState.outcomeUncertain,
    );
    expect(
      NativeTransferExecutionState.outcomeUncertain.toModel(),
      TransferExecutionState.outcomeUncertain,
    );
    expect(
      NativeHistoryMutationExecutionState.outcomeUncertain.toModel(),
      HistoryMutationExecutionState.outcomeUncertain,
    );
    expect(
      NativeRebaseExecutionState.outcomeUncertain.toModel(),
      RebaseExecutionState.outcomeUncertain,
    );
    expect(
      NativeRestackExecutionState.outcomeUncertain.toModel(),
      RestackExecutionState.outcomeUncertain,
    );
    expect(
      NativeNamedSnapshotExecutionState.outcomeUncertain.toModel(),
      NamedSnapshotExecutionState.outcomeUncertain,
    );
    expect(
      NativeBisectExecutionState.outcomeUncertain.toModel(),
      BisectExecutionState.outcomeUncertain,
    );
    expect(
      NativeConflictContinuationState.outcomeUncertain.toModel(),
      ConflictContinuationState.outcomeUncertain,
    );
    expect(
      NativeExtensionMutationState.outcomeUncertain.toModel(),
      RepositoryExtensionMutationState.outcomeUncertain,
    );
  });

  test('an uncertain extension change is not reported as its failure', () {
    const result = RepositoryExtensionMutationResult(
      state: RepositoryExtensionMutationState.outcomeUncertain,
      activityIds: [],
      failure: RepositoryExtensionFailureCode.read,
    );
    expect(result.reportedFailure, isNull);
  });

  testWidgets('every family asks the user to inspect an uncertain change', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (built) {
            context = built;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final inspect = AppLocalizations.of(context).mutationOutcomeUncertain;
    expect(
      refMutationResultLabel(
        context,
        RefMutationExecutionState.outcomeUncertain,
      ),
      inspect,
    );
    expect(
      stashResultLabel(
        context,
        const StashExecutionResult(
          state: StashExecutionState.outcomeUncertain,
          activityIds: [],
          stashCreated: false,
          checkoutCompleted: false,
          reapplyCompleted: false,
          stashRetained: false,
          failure: StashFailureCode.write,
        ),
      ),
      inspect,
    );
    expect(
      transferResultLabel(
        context,
        TransferExecutionResult(
          state: TransferExecutionState.outcomeUncertain,
          ahead: BigInt.zero,
          behind: BigInt.zero,
        ),
      ),
      inspect,
    );
    expect(
      historyMutationResultLabel(
        context,
        const HistoryMutationExecutionResult(
          state: HistoryMutationExecutionState.outcomeUncertain,
          activityIds: [],
          conflictingPaths: [],
        ),
      ),
      inspect,
    );
    expect(
      rebaseResultLabel(
        context,
        const RebaseExecutionResult(
          state: RebaseExecutionState.outcomeUncertain,
          activityIds: [],
          conflictingPaths: [],
        ),
      ),
      inspect,
    );
    expect(
      restackResultLabel(
        context,
        const RestackExecutionResult(
          state: RestackExecutionState.outcomeUncertain,
          completedSteps: 1,
          totalSteps: 2,
          recoveryRefs: [],
          conflictingPaths: [],
          activityIds: [],
        ),
      ),
      inspect,
    );
    expect(
      commitResultMessage(
        context,
        const CommitExecutionResult(
          state: CommitExecutionState.outcomeUncertain,
        ),
      ),
      (text: inspect, error: true),
    );
    expect(
      changesOutcomeMessage(
        context,
        const StagingFinished(StagingExecutionState.outcomeUncertain),
      ),
      (text: inspect, error: true),
    );
    expect(
      changesOutcomeMessage(
        context,
        const DiscardFinished(DiscardExecutionState.outcomeUncertain),
      ),
      (text: inspect, error: true),
    );
    expect(
      conflictOutcomeMessage(
        context,
        const ConflictContinued(ConflictContinuationState.outcomeUncertain),
      ).text,
      inspect,
    );
  });

  testWidgets('revert results say what became of set-aside changes', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    String? label(
      HistoryMutationExecutionState state, {
      bool restored = false,
      bool conflicted = false,
      bool pending = false,
    }) => historySetAsideLabel(
      context,
      HistoryMutationExecutionResult(
        state: state,
        activityIds: const [],
        conflictingPaths: const [],
        setAside: HistorySetAside(
          stashObjectId: 'a' * 40,
          restored: restored,
          conflicted: conflicted,
          pending: pending,
        ),
      ),
    );
    const completed = HistoryMutationExecutionState.completed;
    expect(
      label(completed, restored: true),
      'Reverted. Your local changes and staging were restored. A recovery copy remains in Stashes.',
    );
    expect(label(completed, conflicted: true), contains('caused conflicts'));
    expect(
      label(HistoryMutationExecutionState.conflict, pending: true),
      contains('come back when you continue or abort'),
    );
    expect(label(completed), contains('remain saved in Stashes'));
    // A failed revert that put the changes back adds nothing to its failure.
    expect(label(HistoryMutationExecutionState.failed, restored: true), isNull);
    expect(
      historySetAsideLabel(
        context,
        const HistoryMutationExecutionResult(
          state: completed,
          activityIds: [],
          conflictingPaths: [],
        ),
      ),
      isNull,
    );
  });
}
