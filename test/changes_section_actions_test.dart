import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/changes_section.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/widgets/git_file_list/git_file_list.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'motion/motion_support.dart';
import 'support/native_menu_model.dart';

void main() {
  for (final side in StagingSide.values) {
    testWidgets(
      '${side.name} row actions use the selection or the unselected row',
      (tester) async {
        final entries = [
          _entry('one.txt', side),
          _entry('two.txt', side),
          _entry('other.txt', side),
        ];
        final controller = ScrollController();
        addTearDown(controller.dispose);
        List<RepositoryStatusEntry>? staged;
        List<RepositoryStatusEntry>? discarded;
        List<RepositoryStatusEntry>? patched;
        await tester.pumpWidget(
          motionHost(
            SizedBox(
              width: 700,
              height: 300,
              child: ChangesSection(
                title: 'Changes',
                side: side,
                stacked: true,
                mode: GitFileListMode.list,
                onModeChanged: (_) {},
                entries: entries,
                controller: controller,
                selected: entries.take(2).map(changeKey).toSet(),
                busy: false,
                onSelectIdentity: (_) {},
                onSelectionChanged: (_) {},
                onSelected: () {},
                onAll: () {},
                onFiles: (value) => staged = value,
                onPartial: (_) {},
                onCreatePatch: (value) => patched = value,
                fileBrowserName: 'Files',
                onDropFiles: (_) {},
                onDiscardSelected: () {},
                onDiscardFiles: (value) => discarded = value,
                onDiscardAll: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rows = tester
            .widgetList<GitLamaFileRow>(find.byType(GitLamaFileRow))
            .toList();
        for (var i = 0; i < rows.length; i++) {
          final expected = i < 2 ? entries.take(2).toList() : [entries[2]];
          rows[i].onStage!();
          expect(staged, expected);
          if (side == StagingSide.unstaged) {
            rows[i].onDiscard!();
            expect(discarded, expected);
          }
        }
        // Context-menu commands retain explicit selection and single-file scopes.
        final menuWidget = tester.widget<GitLamaContextMenuWidget>(
          find.ancestor(
            of: find.byKey(
              ValueKey('changes-${side.name}-file-${changeKey(entries.first)}'),
            ),
            matching: find.byType(GitLamaContextMenuWidget),
          ),
        );
        final menu = (await menuWidget.testMenu())!;
        final actions = menu.children
            .whereType<MenuAction>()
            .where((a) => !a.header)
            .toList();
        actions
            .firstWhere(
              (a) =>
                  a.title ==
                  (side == StagingSide.staged
                      ? 'Unstage selected'
                      : 'Stage selected'),
            )
            .callback();
        expect(staged, entries.take(2).toList());
        actions
            .firstWhere((a) => a.title == 'Create patch from selection')
            .callback();
        expect(patched, entries.take(2).toList());
        if (side == StagingSide.unstaged) {
          actions.firstWhere((a) => a.title == 'Discard selected').callback();
          expect(discarded, entries.take(2).toList());
          actions
              .firstWhere((a) => a.title == 'Discard file changes')
              .callback();
          expect(discarded, [entries.first]);
        }
      },
    );
  }

  testWidgets(
    'row clean covers all selected untracked files and supports mixed and rejects blocked selections',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final untracked = [
        for (final name in ['one.txt', 'two.txt'])
          RepositoryStatusEntry(
            kind: StatusEntryKind.untracked,
            path: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: name.codeUnits,
            ),
            index: ChangeKind.unmodified,
            worktree: ChangeKind.added,
          ),
      ];
      List<RepositoryStatusEntry>? discarded;
      Future<List<GitLamaFileRow>> pump(
        List<RepositoryStatusEntry> entries, {
        bool busy = false,
        String? reason,
      }) async {
        await tester.pumpWidget(
          motionHost(
            SizedBox(
              width: 700,
              height: 300,
              child: ChangesSection(
                title: 'Changes',
                side: StagingSide.unstaged,
                stacked: true,
                mode: GitFileListMode.list,
                onModeChanged: (_) {},
                entries: entries,
                controller: controller,
                selected: entries.map(changeKey).toSet(),
                busy: busy,
                onSelectIdentity: (_) {},
                onSelectionChanged: (_) {},
                onSelected: () {},
                onAll: () {},
                onFiles: (_) {},
                onPartial: (_) {},
                onCreatePatch: (_) {},
                fileBrowserName: 'Files',
                onDropFiles: (_) {},
                onDiscardSelected: () {},
                onDiscardFiles: (value) => discarded = value,
                onDiscardAll: () {},
                discardDisabledReason: reason,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widgetList<GitLamaFileRow>(find.byType(GitLamaFileRow))
            .toList();
      }

      var rows = await pump(untracked);
      rows.first.onDiscard!();
      expect(discarded, untracked);
      expect(rows.first.discardActionLabel, 'Clean selected');
      final menu = (await tester
          .widget<GitLamaContextMenuWidget>(
            find.byType(GitLamaContextMenuWidget).first,
          )
          .testMenu())!;
      final clean = menu.children.whereType<MenuAction>().singleWhere(
        (a) => a.title == 'Clean selected',
      );
      discarded = null;
      clean.callback();
      expect(discarded, untracked);
      rows = await pump([
        untracked.first,
        _entry('tracked.txt', StagingSide.unstaged),
      ]);
      expect(rows.every((row) => row.onDiscard != null), isTrue);
      rows.first.onDiscard!();
      expect(discarded, hasLength(2));
      expect(discarded!.first, untracked.first);
      expect(discarded!.last.kind, StatusEntryKind.ordinary);
      expect(rows.first.discardActionLabel, 'Discard selected');
      rows = await pump(untracked, busy: true);
      expect(
        rows.every((row) => row.onDiscard == null && row.onStage == null),
        isTrue,
      );
      rows = await pump(untracked, reason: 'Unavailable');
      expect(rows.every((row) => row.onDiscard == null), isTrue);
    },
  );

  testWidgets('discarding sits apart from staging behind a divider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var discardedAll = 0;
    var stagedAll = 0;
    await tester.pumpWidget(
      motionHost(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 520,
            height: 300,
            child: ChangesSection(
              title: 'Unstaged changes',
              side: StagingSide.unstaged,
              stacked: true,
              mode: GitFileListMode.list,
              onModeChanged: (_) {},
              entries: [
                RepositoryStatusEntry(
                  kind: StatusEntryKind.ordinary,
                  path: NativePathIdentity(
                    platform: NativePathPlatform.unix,
                    units: 'one.txt'.codeUnits,
                  ),
                  index: ChangeKind.unmodified,
                  worktree: ChangeKind.modified,
                ),
              ],
              mutationSequence: 0,
              mutationSource: StagingSide.unstaged,
              movingKeys: const {},
              controller: controller,
              selected: const {},
              busy: false,
              onSelectIdentity: (_) {},
              onSelectionChanged: (_) {},
              onSelected: () {},
              onAll: () => stagedAll++,
              onFiles: (_) {},
              onPartial: (_) {},
              onCreatePatch: (_) {},
              fileBrowserName: 'Files',
              onDropFiles: (_) {},
              onDiscardSelected: () {},
              onDiscardFiles: (_) {},
              onDiscardAll: () => discardedAll++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder icon(String name) => find.byWidgetPredicate(
      (widget) => widget is MeridianIconButton && widget.icon == name,
    );
    final discardSelected = tester.getRect(icon('trash'));
    final discardAll = tester.getRect(icon('brush-cleaning'));
    final divider = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is MeridianHairline && widget.axis == Axis.vertical,
      ),
    );
    final stageAllButton = find.widgetWithText(MeridianButton, 'Stage all');
    final stageAll = tester.getRect(stageAllButton);

    // Destructive actions first, then the divider, then staging with its
    // primary action at the trailing edge.
    expect(discardSelected.right, lessThanOrEqualTo(discardAll.left));
    expect(discardAll.right, lessThan(divider.left));
    expect(divider.right, lessThan(stageAll.left));
    final stageSelected = find.byWidgetPredicate(
      (widget) =>
          widget is MeridianIconButton &&
          widget.icon != 'trash' &&
          widget.icon != 'brush-cleaning',
    );
    expect(tester.getRect(stageSelected).left, greaterThan(divider.right));

    // Discard actions read as destructive.
    expect(
      tester.widget<MeridianIconButton>(icon('trash')).color,
      MeridianTheme.of(tester.element(stageAllButton)).colors.danger,
    );

    // Nothing is clipped: Stage all stays visible and both ends still act.
    expect(stageAll.right, lessThanOrEqualTo(520));
    await tester.tap(stageAllButton);
    await tester.tap(icon('brush-cleaning'));
    expect(stagedAll, 1);
    expect(discardedAll, 1);
  });
}

RepositoryStatusEntry _entry(String name, StagingSide side) =>
    RepositoryStatusEntry(
      kind: StatusEntryKind.ordinary,
      path: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: name.codeUnits,
      ),
      index: side == StagingSide.staged
          ? ChangeKind.modified
          : ChangeKind.unmodified,
      worktree: side == StagingSide.unstaged
          ? ChangeKind.modified
          : ChangeKind.unmodified,
    );
