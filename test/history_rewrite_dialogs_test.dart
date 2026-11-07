import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/app/workspace/history_mutation_dialogs.dart';
import 'package:gitlama/app/workspace/named_snapshots.dart';
import 'package:gitlama/app/workspace/rebase_dialogs.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/advanced_rebase.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/named_snapshot.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/widgets/command_preview.dart';
import 'package:gitlama/widgets/gitlama_list_well.dart';
import 'package:meridian_ui/meridian_ui.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';

List<int> _bytes(String value) => utf8.encode(value);

/// Shows [dialog] the way the app does and records what it returns.
class _Host {
  Object? result;
  var closed = false;

  Future<void> open(WidgetTester tester, Widget dialog) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'Open',
              onPressed: () async {
                result = await showMeridianDialog<Object>(
                  context: context,
                  builder: (_) => dialog,
                );
                closed = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

MeridianButton _button(WidgetTester tester, String label) =>
    tester.widget<MeridianButton>(find.widgetWithText(MeridianButton, label));

RebaseInstruction _instruction(
  int id,
  RebaseAction action,
  String subject, {
  bool published = false,
  String? message,
  int? base,
}) => RebaseInstruction(
  id: BigInt.from(id),
  action: action,
  oid: '${id}23456789abcdef0',
  subject: _bytes(subject),
  published: published,
  replacementMessage: message == null ? null : _bytes(message),
  autosquashBaseId: base == null ? null : BigInt.from(base),
);

void main() {
  group('restack review', () {
    RestackPlan plan({int published = 1, bool incomplete = false}) =>
        RestackPlan(
          token: BigInt.one,
          rootBranch: _bytes('main'),
          publishedCount: published,
          incomplete: incomplete,
          activityIds: const [],
          steps: [
            for (final (index, (name, parent)) in [
              ('feature/a', 'main'),
              ('feature/b', 'feature/a'),
            ].indexed)
              RestackStep(
                id: index,
                branch: _bytes(name),
                expectedHead: _sha,
                oldParent: _sha,
                newParent: _bytes(parent),
                expectedNewParentHead: _sha,
                published: index == 1 && published > 0,
              ),
          ],
        );

    testWidgets('numbers the steps in a bounded well and names each base', (
      tester,
    ) async {
      final host = _Host();
      await host.open(tester, RestackPreviewDialog(plan: plan()));
      expect(find.text('Restack 2 branches'), findsOneWidget);
      final well = find.byType(GitLamaListWell);
      expect(well, findsOneWidget);
      expect(
        tester.widget<GitLamaListWell>(well).maxHeight,
        GitLamaLayout.dialogListMaxHeight,
      );
      final second = find.byKey(const ValueKey('restack-step-1'));
      expect(
        find.descendant(of: second, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: second, matching: find.text('feature/b')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: second, matching: find.text('onto feature/a')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: second, matching: find.text('Published')),
        findsOneWidget,
      );
      // No hash pairs: the plan reads as branches, not object IDs.
      expect(find.textContaining('01234567'), findsNothing);
    });

    testWidgets('runs only after rewriting published branches is accepted', (
      tester,
    ) async {
      final host = _Host();
      await host.open(tester, RestackPreviewDialog(plan: plan()));
      expect(_button(tester, 'Restack branches').onPressed, isNull);
      await tester.tap(find.byType(MeridianCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Restack branches'));
      await tester.pumpAndSettle();
      expect(host.result, isTrue);
    });

    testWidgets('warns when the stack could not be mapped completely', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        RestackPreviewDialog(plan: plan(published: 0, incomplete: true)),
      );
      expect(find.byType(MeridianBanner), findsOneWidget);
      expect(find.byType(MeridianCheckbox), findsNothing);
      expect(_button(tester, 'Restack branches').onPressed, isNotNull);
    });
  });

  group('history operation input', () {
    testWidgets('a revert blocked by changes says so in one banner', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        const HistoryMutationInputDialog(
          kind: HistoryMutationKind.revert,
          selectedTargets: ['a', 'b'],
          branches: [],
          publishedHistory: false,
          dirtyWorktree: true,
        ),
      );
      expect(
        find.text(
          'Adds new commits that undo the 2 selected commits. The originals stay in the history.',
        ),
        findsOneWidget,
      );
      expect(find.byType(MeridianBanner), findsOneWidget);
      expect(
        find.text(
          'Commit or stash your changes first: reverting needs a clean working tree.',
        ),
        findsOneWidget,
      );
      expect(_button(tester, 'Commit revert').onPressed, isNull);
      final apply = _button(tester, 'Apply without committing');
      expect(apply.onPressed, isNull);
      expect(
        apply.disabledReason,
        'Applying without committing works with one commit at a time.',
      );
    });

    testWidgets('an operation in progress takes the banner', (tester) async {
      final host = _Host();
      await host.open(
        tester,
        const HistoryMutationInputDialog(
          kind: HistoryMutationKind.revert,
          selectedTargets: ['a'],
          branches: [],
          publishedHistory: false,
          dirtyWorktree: true,
          activeOperation: true,
        ),
      );
      expect(find.byType(MeridianBanner), findsOneWidget);
      expect(
        find.text('Continue or abort the current Git operation first.'),
        findsOneWidget,
      );
    });

    testWidgets('a clean single revert offers review without a banner', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        const HistoryMutationInputDialog(
          kind: HistoryMutationKind.revert,
          selectedTargets: ['a'],
          branches: [],
          publishedHistory: false,
        ),
      );
      expect(find.byType(MeridianBanner), findsNothing);
      expect(
        find.text(
          'To review the changes first, apply them without committing.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(MeridianButton, 'Apply without committing'),
      );
      await tester.pumpAndSettle();
      expect((host.result! as HistoryMutationRequest).noCommit, isTrue);
    });

    testWidgets('cherry-picking onto a published branch needs consent', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        const HistoryMutationInputDialog(
          kind: HistoryMutationKind.cherryPick,
          selectedTargets: ['a', 'b', 'c'],
          branches: [],
          publishedHistory: true,
        ),
      );
      expect(
        find.text(
          'Copies the 3 selected commits onto the current branch as new commits.',
        ),
        findsOneWidget,
      );
      const label = 'Cherry-pick selected commits';
      expect(_button(tester, label).onPressed, isNull);
      await tester.tap(find.byType(MeridianCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, label));
      await tester.pumpAndSettle();
      final request = host.result! as HistoryMutationRequest;
      expect(request.acknowledgePublishedHistory, isTrue);
      expect(request.targets, ['a', 'b', 'c']);
    });
  });

  group('history operation review', () {
    HistoryMutationPreview preview({
      HistoryMutationKind kind = HistoryMutationKind.merge,
      bool alreadyContained = false,
    }) => HistoryMutationPreview(
      token: BigInt.one,
      kind: kind,
      arguments: const ['merge', '--no-edit', '--ff', _sha],
      targets: const [_sha],
      sourceName: _bytes('feature/login'),
      currentBranch: _bytes('main'),
      currentHead: _sha,
      publishedHistory: false,
      alreadyContained: alreadyContained,
    );

    testWidgets('lists the branches and the conflict check as facts', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        HistoryMutationPreviewDialog(
          preview: preview(),
          prediction: ConflictPredictionResult(
            kind: ConflictPredictionKind.merge,
            target: _sha,
            conflictingPaths: [_bytes('a'), _bytes('b'), _bytes('c')],
            analyzedCommits: 2,
            totalCommits: 3,
            complete: false,
            activityIds: const [],
          ),
        ),
      );
      expect(find.text('Review merge'), findsOneWidget);
      final facts = tester
          .widget<MeridianPropertyList>(find.byType(MeridianPropertyList))
          .properties;
      expect(
        [for (final fact in facts) (fact.label, fact.value)],
        [
          ('Source branch', 'feature/login'),
          ('Current branch', 'main'),
          ('Conflicts', 'Likely in 3 files'),
        ],
      );
      expect(
        find.text(
          "The conflict check is an estimate and didn't cover every commit.",
        ),
        findsOneWidget,
      );
      expect(find.byType(GitCommandDetails), findsOneWidget);
      await tester.tap(find.widgetWithText(MeridianButton, 'Merge branch'));
      await tester.pumpAndSettle();
      expect(host.result, isTrue);
    });

    testWidgets('says when nothing would change', (tester) async {
      final host = _Host();
      await host.open(
        tester,
        HistoryMutationPreviewDialog(
          preview: preview(
            kind: HistoryMutationKind.revert,
            alreadyContained: true,
          ),
          prediction: null,
        ),
      );
      expect(find.text('Review revert'), findsOneWidget);
      expect(find.byType(MeridianBanner), findsOneWidget);
      final facts = tester
          .widget<MeridianPropertyList>(find.byType(MeridianPropertyList))
          .properties;
      expect([for (final fact in facts) fact.label], ['Current branch']);
    });
  });

  group('interactive rebase editor', () {
    RebasePlan plan(int count, {int published = 0}) => RebasePlan(
      token: BigInt.one,
      onto: _sha,
      ontoName: _bytes('main'),
      currentBranch: _bytes('feature/login'),
      currentHead: _sha,
      instructions: [
        for (var index = 1; index <= count; index++)
          _instruction(
            index,
            RebaseAction.pick,
            'Commit $index',
            published: index <= published,
          ),
      ],
      publishedCount: published,
      activityIds: const [],
    );

    testWidgets('names the branches and bounds a long plan', (tester) async {
      final host = _Host();
      await host.open(
        tester,
        RebaseEditorDialog(
          plan: plan(30),
          prediction: null,
          shortcuts: const {},
        ),
      );
      expect(find.text('Interactive rebase'), findsOneWidget);
      expect(
        find.text(
          'Choose what happens to each commit of feature/login. They are replayed from top to bottom onto main.',
        ),
        findsOneWidget,
      );
      expect(find.text('30 commits, oldest first'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ReorderableListView)).height,
        lessThanOrEqualTo(GitLamaLayout.rebaseInstructionListMaxHeight),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dropped commit is struck through to its text end only', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        RebaseEditorDialog(
          plan: RebasePlan(
            token: BigInt.one,
            onto: _sha,
            ontoName: _bytes('main'),
            currentBranch: _bytes('feature/login'),
            currentHead: _sha,
            instructions: [
              _instruction(1, RebaseAction.drop, 'WIP'),
              _instruction(
                2,
                RebaseAction.drop,
                'Rework the session handling so expired tokens refresh '
                'without a full reload of the window and every open tab',
                published: true,
              ),
            ],
            publishedCount: 1,
            activityIds: const [],
          ),
          prediction: null,
          shortcuts: const {},
        ),
      );
      for (final index in [0, 1]) {
        final strike = tester.getRect(
          find.byKey(ValueKey('rebase-strike-$index')),
        );
        final subject = tester.getRect(
          find.byKey(ValueKey('rebase-subject-$index')),
        );
        expect(strike.left, closeTo(subject.left, 0.5));
        expect(strike.right, closeTo(subject.right, 0.5));
      }
      // A short subject's strike stops long before the row's controls.
      expect(
        tester.getRect(find.byKey(const ValueKey('rebase-strike-0'))).width,
        lessThan(MeridianSize.controlSm * 3),
      );
      // An ellipsised one ends before the Published badge.
      expect(
        tester.getRect(find.byKey(const ValueKey('rebase-strike-1'))).right,
        lessThan(tester.getRect(find.text('Published')).left),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('options are checkboxes and published history needs consent', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        RebaseEditorDialog(
          plan: plan(2, published: 1),
          prediction: ConflictPredictionResult(
            kind: ConflictPredictionKind.rebase,
            target: _sha,
            conflictingPaths: [_bytes('a')],
            analyzedCommits: 2,
            totalCommits: 2,
            complete: true,
            activityIds: const [],
          ),
          shortcuts: const {},
        ),
      );
      expect(find.byType(MeridianSwitch), findsNothing);
      expect(
        find.text(
          '1 file will likely conflict. You can resolve it during the rebase.',
        ),
        findsOneWidget,
      );
      expect(_button(tester, 'Start rebase').onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('rebase-autosquash')));
      await tester.tap(
        find.byKey(const ValueKey('rebase-acknowledge-published')),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Start rebase'));
      await tester.pumpAndSettle();
      final result = host.result! as RebaseEditResult;
      expect(result.applyAutosquash, isTrue);
      expect(result.acknowledgePublishedHistory, isTrue);
    });
  });

  group('rebase review', () {
    testWidgets('shows the plan in plain steps and the todo with the command', (
      tester,
    ) async {
      final instructions = [
        _instruction(1, RebaseAction.pick, 'Add login form'),
        _instruction(2, RebaseAction.fixup, 'fixup! Add login form', base: 1),
        _instruction(3, RebaseAction.reword, 'wip', message: 'Validate email'),
        _instruction(4, RebaseAction.squash, 'Tweak spacing'),
        _instruction(5, RebaseAction.drop, 'Debug logging'),
      ];
      final host = _Host();
      await host.open(
        tester,
        RebasePreviewDialog(
          preview: RebasePreview(
            token: BigInt.one,
            arguments: const ['rebase', '--interactive', _sha],
            todo: _bytes('pick 12345678 Add login form\nfixup 22345678 x\n'),
            instructionCount: 5,
            publishedCount: 0,
            instructions: instructions,
            autosquashApplied: 1,
          ),
        ),
      );
      expect(find.text('Review rebase'), findsOneWidget);
      expect(find.byType(GitLamaListWell), findsOneWidget);
      MeridianListRow row(int index) => tester.widget<MeridianListRow>(
        find.byKey(ValueKey('rebase-step-$index')),
      );
      expect(row(0).meta, 'Pick');
      expect(row(1).subtitle, 'combined with Add login form');
      expect(row(2).subtitle, 'new message: Validate email');
      expect(row(3).subtitle, 'combined with the commit above');
      expect(row(4).dimmed, isTrue);
      expect(
        find.text('1 fixup commit was combined automatically.'),
        findsOneWidget,
      );
      // The exact todo is a detail, behind the command disclosure.
      expect(find.textContaining('pick 12345678'), findsNothing);
      await tester.tap(find.text('Git command details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('pick 12345678 Add login form'),
        findsOneWidget,
      );
      expect(_button(tester, 'Cancel').autofocus, isTrue);
      expect(
        _button(tester, 'Start rebase').variant,
        MeridianButtonVariant.danger,
      );
    });
  });

  group('snapshot restore', () {
    NamedSnapshotRestorePreview preview({required bool truncated}) =>
        NamedSnapshotRestorePreview(
          token: BigInt.one,
          snapshot: NamedSnapshot(
            id: BigInt.one,
            name: 'before refactor',
            createdAtUnixMs: BigInt.zero,
            baseOid: _sha,
            objectId: _sha,
            stagedCount: 1,
            unstagedCount: 1,
            untrackedCount: 0,
            includesUntracked: true,
            keepsIndex: true,
            state: NamedSnapshotState.ready,
          ),
          replacementPaths: [
            _bytes('README.md'),
            for (var index = 0; index < 20; index++)
              _bytes('lib/settings/page_$index.dart'),
          ],
          replacementPathsTruncated: truncated,
          replacesIndex: true,
          replacesWorktree: true,
        );

    testWidgets('lists the files that change as names with their folder', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        NamedSnapshotRestoreDialog(preview: preview(truncated: true)),
      );
      expect(find.text('Restore “before refactor”?'), findsOneWidget);
      expect(find.text('21 files change'), findsOneWidget);
      final first = tester.widget<MeridianListRow>(
        find.byKey(const ValueKey('snapshot-restore-path-0')),
      );
      expect((first.title, first.subtitle), ('README.md', null));
      final second = tester.widget<MeridianListRow>(
        find.byKey(const ValueKey('snapshot-restore-path-1')),
      );
      expect((second.title, second.subtitle), ('page_0.dart', 'lib/settings'));
      expect(
        tester.getSize(find.byType(GitLamaListWell)).height,
        lessThan(GitLamaLayout.dialogListMaxHeight + MeridianSize.control * 2),
      );
      expect(
        find.text('More files change than are listed here.'),
        findsOneWidget,
      );
    });

    testWidgets('restores only after the replacement is accepted', (
      tester,
    ) async {
      final host = _Host();
      await host.open(
        tester,
        NamedSnapshotRestoreDialog(preview: preview(truncated: false)),
      );
      expect(
        find.text('More files change than are listed here.'),
        findsNothing,
      );
      expect(_button(tester, 'Cancel').autofocus, isTrue);
      expect(_button(tester, 'Restore').onPressed, isNull);
      await tester.tap(find.byType(MeridianCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(host.result, isTrue);
    });
  });
}
