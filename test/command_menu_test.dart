import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:gitlama/app/workspace/command_availability.dart';
import 'package:gitlama/app/workspace/command_menus.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/repository_state.dart';

const head = '1111111111111111111111111111111111111111';
const other = '2222222222222222222222222222222222222222';

RepositorySnapshot snapshot({WorkingTreeState tree = WorkingTreeState.clean}) =>
    RepositorySnapshot(
      revision: BigInt.one,
      phase: RepositoryPhase.ready,
      refs: RepositoryRefs(
        branches: [
          RepositoryReference(
            name: 'main'.codeUnits,
            target: head,
            head: true,
            upstream: 'refs/remotes/origin/main'.codeUnits,
          ),
          RepositoryReference(name: 'topic'.codeUnits, target: other),
          RepositoryReference(name: 'same-commit'.codeUnits, target: head),
        ],
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: [],
            branches: [
              RepositoryReference(name: 'main'.codeUnits, target: other),
              RepositoryReference(name: 'topic'.codeUnits, target: other),
            ],
          ),
        ],
      ),
      status: RepositoryStatus(
        workingTree: tree,
        headObjectId: head,
        branchName: 'main'.codeUnits,
        ahead: BigInt.zero,
        behind: BigInt.zero,
        entries: [],
        totalEntries: BigInt.zero,
        entriesTruncated: false,
        operations: [],
      ),
    );

void main() {
  test(
    'staging queue permits file commands while other mutations remain blocked',
    () {
      final state = CommandMenuState(
        snapshot: snapshot(tree: WorkingTreeState.dirty),
        busy: true,
        canQueueStaging: true,
      );
      for (final command in [
        AppCommandId.stageSelection,
        AppCommandId.unstageSelection,
        AppCommandId.stageToggle,
      ]) {
        expect(
          state.reason(command),
          isNot(AppCommandDisabledReason.repositoryBusy),
        );
      }
      for (final command in [
        AppCommandId.commitCreate,
        AppCommandId.commitAmend,
        AppCommandId.discardChanges,
        AppCommandId.checkoutCommit,
      ]) {
        expect(state.reason(command), AppCommandDisabledReason.repositoryBusy);
      }
      expect(state.reason(AppCommandId.showHistory), isNull);
      expect(
        CommandMenuState(
          snapshot: snapshot(),
          busy: true,
        ).reason(AppCommandId.stageSelection),
        AppCommandDisabledReason.repositoryBusy,
      );
    },
  );

  testWidgets('native grouped menus retain every unavailable command', (
    tester,
  ) async {
    late List<NativeMenuItem<AppCommandId>> menu;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            menu = workspaceCommandMenu(
              context,
              state: const CommandMenuState(),
              shortcuts: const {},
            );
            return const SizedBox();
          },
        ),
      ),
    );
    Iterable<NativeMenuItem<AppCommandId>> flatten(
      Iterable<NativeMenuItem<AppCommandId>> items,
    ) sync* {
      for (final item in items) {
        yield item;
        yield* flatten(item.children ?? []);
      }
    }

    final actions = flatten(menu).where((item) => item.value != null).toList();
    expect(
      actions.map((item) => item.value).toSet(),
      AppCommandId.values.toSet(),
    );
    expect(actions, hasLength(AppCommandId.values.length));
    expect(
      actions
          .singleWhere((item) => item.value == AppCommandId.revertSelected)
          .enabled,
      isFalse,
    );
    expect(
      actions
          .singleWhere((item) => item.value == AppCommandId.checkoutBranch)
          .enabled,
      isFalse,
    );
    expect(
      menu.map((group) => group.title),
      containsAll(['Repository', 'Branches and tags', 'Application']),
    );
  });
  test('all registered commands have exactly one grouped menu location', () {
    final commands = workspaceCommandGroups.values
        .expand((group) => group)
        .toList();
    expect(commands.toSet(), AppCommandId.values.toSet());
    expect(commands.length, AppCommandId.values.length);
  });

  test(
    'current local and tracked remote checkout are unavailable, even at different tips',
    () {
      final state = CommandMenuState(snapshot: snapshot());
      expect(
        state.reason(
          AppCommandId.checkoutBranch,
          reference: 'refs/heads/main',
          contextual: true,
        ),
        isNotNull,
      );
      expect(
        state.reason(
          AppCommandId.checkoutBranch,
          reference: 'refs/remotes/origin/main',
          target: other,
          contextual: true,
        ),
        isNotNull,
      );
      expect(
        state.reason(
          AppCommandId.checkoutBranch,
          reference: 'refs/heads/same-commit',
          target: head,
          contextual: true,
        ),
        isNull,
      );
      expect(
        state.reason(
          AppCommandId.checkoutBranch,
          reference: 'refs/remotes/origin/topic',
          target: other,
          contextual: true,
        ),
        isNull,
      );
      expect(
        state.reason(
          AppCommandId.deleteBranch,
          reference: 'refs/heads/main',
          contextual: true,
        ),
        isNotNull,
      );
      expect(
        state.reason(
          AppCommandId.renameBranch,
          reference: 'refs/heads/main',
          contextual: true,
        ),
        isNull,
      );
      for (final id in [AppCommandId.mergeBranch, AppCommandId.rebaseBranch]) {
        expect(
          state.reason(
            id,
            reference: 'refs/heads/main',
            target: head,
            contextual: true,
          ),
          isNotNull,
        );
        expect(
          state.reason(
            id,
            reference: 'refs/heads/same-commit',
            target: head,
            contextual: true,
          ),
          isNotNull,
        );
        expect(
          state.reason(
            id,
            reference: 'refs/remotes/origin/main',
            target: other,
            contextual: true,
          ),
          isNull,
        );
      }
    },
  );

  test(
    'history actions require their exact selections and a safe mutation state',
    () {
      final clean = CommandMenuState(
        snapshot: snapshot(),
        selectedCommits: [other],
        scopes: {AppCommandShortcutScope.history},
      );
      expect(clean.reason(AppCommandId.revertSelected), isNull);
      expect(clean.reason(AppCommandId.historyCompare), isNotNull);
      final dirty = CommandMenuState(
        snapshot: snapshot(tree: WorkingTreeState.dirty),
        selectedCommits: [other],
      );
      // A revert keeps local changes in place or sets them aside; a
      // cherry-pick still needs a clean tree, and conflicts block both.
      expect(dirty.reason(AppCommandId.revertSelected), isNull);
      expect(dirty.reason(AppCommandId.cherryPickSelected), isNotNull);
      final conflicted = CommandMenuState(
        snapshot: snapshot(tree: WorkingTreeState.conflicted),
        selectedCommits: [other],
      );
      expect(conflicted.reason(AppCommandId.revertSelected), isNotNull);
      final merge = CommandMenuState(
        snapshot: snapshot(),
        selectedCommits: [other],
        mergeCommits: {other},
      );
      expect(merge.reason(AppCommandId.revertSelected), isNotNull);
      final empty = CommandMenuState(snapshot: snapshot());
      expect(empty.reason(AppCommandId.revertSelected), isNotNull);
      expect(empty.reason(AppCommandId.conflictTakeBoth), isNotNull);
      expect(empty.reason(AppCommandId.rebaseContinue), isNotNull);
      expect(empty.reason(AppCommandId.activityRetry), isNotNull);
    },
  );
}
