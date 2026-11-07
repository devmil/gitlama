import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/stash_dialogs.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/stash.dart';

NativePathIdentity _path(String path) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: path.codeUnits,
);

RepositoryStatusEntry _entry(String path, StatusEntryKind kind) =>
    RepositoryStatusEntry(
      kind: kind,
      path: _path(path),
      index: ChangeKind.unmodified,
      worktree: kind == StatusEntryKind.untracked
          ? ChangeKind.unmodified
          : ChangeKind.modified,
    );

final _entries = [
  _entry('docs/ARCHITECTURE.md', StatusEntryKind.ordinary),
  _entry('docs/MISSION.md', StatusEntryKind.ordinary),
  _entry('notes.txt', StatusEntryKind.untracked),
];

/// Opens [dialog] and returns a getter for its result once it closes.
Future<T? Function()> _open<T>(WidgetTester tester, Widget dialog) async {
  T? result;
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
              result = await showMeridianDialog<T>(
                context: context,
                builder: (context) => dialog,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => result;
}

const _push = StashInputDialog(
  kind: StashKind.push,
  selector: null,
  objectId: null,
  initialMessage: null,
  initialTargetBranch: null,
  statusEntries: [],
  branches: [],
);

void main() {
  testWidgets('Enter in the new name submits Rename stash when valid', (
    tester,
  ) async {
    StashRequest? result;
    var closed = false;
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
                result = await showMeridianDialog<StashRequest>(
                  context: context,
                  builder: (context) => const StashInputDialog(
                    kind: StashKind.rename,
                    selector: 'stash@{0}',
                    objectId: '1111111111111111111111111111111111111111',
                    initialMessage: '',
                    initialTargetBranch: null,
                    statusEntries: [],
                    branches: [],
                  ),
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
    // The verb names the command; there is no generic "Confirm".
    expect(find.widgetWithText(MeridianButton, 'Rename stash'), findsWidgets);
    expect(find.text('Confirm'), findsNothing);

    final name = find.descendant(
      of: find.byType(MeridianTextField),
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(closed, isFalse);

    await tester.enterText(name, 'work in progress');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result?.kind, StashKind.rename);
    expect(result?.message, 'work in progress');
    expect(result?.selector, 'stash@{0}');
  });

  testWidgets('Create stash takes all changes and offers new files', (
    tester,
  ) async {
    final result = await _open<StashRequest>(
      tester,
      StashInputDialog(
        kind: StashKind.push,
        selector: null,
        objectId: null,
        initialMessage: null,
        initialTargetBranch: null,
        statusEntries: _entries,
        branches: const [],
      ),
    );
    // Tracked changes only, until new files are included.
    expect(find.text('All changes (2 files)'), findsOneWidget);
    expect(find.byKey(const ValueKey('stash-file-0')), findsNothing);
    await tester.tap(find.text('Include new files'));
    await tester.pump();
    expect(find.text('All changes (3 files)'), findsOneWidget);

    await tester.tap(find.widgetWithText(MeridianButton, 'Create stash'));
    await tester.pumpAndSettle();
    expect(result()?.paths, isEmpty);
    expect(result()?.includeUntracked, isTrue);
  });

  testWidgets('Only selected files lists tracked changes to pick', (
    tester,
  ) async {
    final result = await _open<StashRequest>(
      tester,
      StashInputDialog(
        kind: StashKind.push,
        selector: null,
        objectId: null,
        initialMessage: null,
        initialTargetBranch: null,
        statusEntries: _entries,
        branches: const [],
      ),
    );
    await tester.tap(find.text('Include new files'));
    await tester.tap(find.text('Only selected files'));
    await tester.pumpAndSettle();

    // Untracked files cannot join a partial stash; the note says why.
    expect(find.byKey(const ValueKey('stash-file-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('stash-file-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('stash-file-2')), findsNothing);
    expect(
      find.text('1 new file can only be stashed with all changes.'),
      findsOneWidget,
    );
    expect(find.text('Include new files'), findsNothing);
    expect(find.text('0 of 2 selected'), findsOneWidget);

    // Nothing picked: Enter does not submit.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(StashInputDialog), findsOneWidget);

    await tester.tap(find.text('MISSION.md'));
    await tester.pump();
    expect(find.text('1 of 2 selected'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Create stash'));
    await tester.pumpAndSettle();
    expect(result()?.paths, ['docs/MISSION.md'.codeUnits]);
    expect(result()?.includeUntracked, isFalse);
  });

  testWidgets('Select all toggles every listed file', (tester) async {
    final result = await _open<StashRequest>(
      tester,
      StashInputDialog(
        kind: StashKind.push,
        selector: null,
        objectId: null,
        initialMessage: null,
        initialTargetBranch: null,
        statusEntries: _entries,
        branches: const [],
      ),
    );
    await tester.tap(find.text('Only selected files'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stash-select-all')));
    await tester.pump();
    expect(find.text('2 of 2 selected'), findsOneWidget);
    expect(find.text('Select none'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stash-select-all')));
    await tester.pump();
    expect(find.text('0 of 2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stash-select-all')));
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianButton, 'Create stash'));
    await tester.pumpAndSettle();
    expect(result()?.paths, [
      'docs/ARCHITECTURE.md'.codeUnits,
      'docs/MISSION.md'.codeUnits,
    ]);
  });

  testWidgets('Without tracked changes only all changes can be stashed', (
    tester,
  ) async {
    await _open<StashRequest>(tester, _push);
    await tester.tap(find.text('Only selected files'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stash-select-all')), findsNothing);
  });

  testWidgets('The stash review lists what the stash will do', (tester) async {
    final result = await _open<bool>(
      tester,
      StashPreviewDialog(
        preview: StashPreview(
          token: BigInt.one,
          kind: StashKind.push,
          commands: const [
            ['stash', 'push', '--include-untracked'],
          ],
          affectedPaths: 3,
          includesUntracked: true,
          keepsIndex: true,
          destructive: false,
        ),
      ),
    );
    expect(find.text('3 files'), findsOneWidget);
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('Stay staged'), findsOneWidget);
    expect(find.textContaining('Recovery history'), findsNothing);
    await tester.tap(find.widgetWithText(MeridianButton, 'Create stash'));
    await tester.pumpAndSettle();
    expect(result(), isTrue);
  });
}
