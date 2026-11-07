import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/changes_section.dart';
import 'package:gitlama/app/workspace/ignore_dialog.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/repository_extensions.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/widgets/git_file_list/git_file_list.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';

import 'motion/motion_support.dart';
import 'support/native_menu_model.dart';

RepositoryStatusEntry _entry(String path, StatusEntryKind kind) =>
    RepositoryStatusEntry(
      kind: kind,
      path: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: path.codeUnits,
      ),
      index: ChangeKind.unmodified,
      worktree: kind == StatusEntryKind.untracked
          ? ChangeKind.added
          : ChangeKind.modified,
    );

const _completed = RepositoryExtensionMutationResult(
  state: RepositoryExtensionMutationState.completed,
  activityIds: [],
);

void main() {
  testWidgets('a changed file offers its exact path as .gitignore entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final previous = nativeMenuTestPresenter;
    addTearDown(() => nativeMenuTestPresenter = previous);
    nativeMenuTestPresenter = (context, menu, position) async {
      final action = menu.children.whereType<MenuAction>().where(
        (item) => item.title == 'Add to .gitignore…',
      );
      if (action.isEmpty) return MenuResult(itemSelected: false);
      action.single.callback();
      return MenuResult(itemSelected: true);
    };
    final requests = <(String, bool, bool)>[];
    Future<void> pump(RepositoryStatusEntry entry, {String? reason}) =>
        tester.pumpWidget(
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
                  entries: [entry],
                  controller: controller,
                  selected: const {},
                  busy: false,
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
                  onDiscardFiles: (_) {},
                  onDiscardAll: () {},
                  onIgnore: (path, {required directory, required tracked}) =>
                      requests.add((
                        String.fromCharCodes(path),
                        directory,
                        tracked,
                      )),
                  ignoreDisabledReason: reason,
                ),
              ),
            ),
          ),
        );

    await pump(_entry('build/out.log', StatusEntryKind.untracked));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(GitLamaFileRow),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await pump(_entry('lib/main.dart', StatusEntryKind.ordinary));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(GitLamaFileRow),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(requests, [
      ('build/out.log', false, false),
      ('lib/main.dart', false, true),
    ]);
  });

  testWidgets('the entry can be edited before it is added', (tester) async {
    final added = <String>[];
    var result = const RepositoryExtensionMutationResult(
      state: RepositoryExtensionMutationState.failed,
      activityIds: [],
      failure: RepositoryExtensionFailureCode.invalidRequest,
    );
    await tester.pumpWidget(
      motionHost(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showIgnoreDialog(
                context,
                suggestion: '/build/out.log',
                directory: false,
                tracked: false,
                onAdd: (pattern) async {
                  added.add(pattern);
                  return result;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add to .gitignore'), findsOneWidget);
    final field = find.byKey(const Key('ignore-entry'));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '/build/out.log',
    );

    await tester.enterText(field, '# note');
    await tester.tap(find.byKey(const ValueKey('ignore-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Git cannot use this entry'), findsOneWidget);
    expect(find.text('Add to .gitignore'), findsOneWidget);

    result = _completed;
    await tester.enterText(field, '*.log');
    await tester.tap(find.byKey(const ValueKey('ignore-add')));
    await tester.pumpAndSettle();
    expect(added, ['# note', '*.log']);
    expect(find.text('Add to .gitignore'), findsNothing);
  });

  testWidgets('a tracked file explains that the entry does not hide it yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      motionHost(
        IgnoreDialog(
          suggestion: '/lib/main.dart',
          directory: false,
          tracked: true,
          onAdd: (_) async => _completed,
        ),
      ),
    );
    expect(find.textContaining('Git already tracks this file'), findsOneWidget);
  });
}
