import 'support/inert_runtime.dart';
import 'support/meridian_finders.dart';
import 'support/native_menu_model.dart';
import 'package:gitlama/app/workspace/changes_section.dart';
import 'package:gitlama/app/workspace/sidebar.dart';
import 'package:gitlama/widgets/status_notification.dart';
import 'package:gitlama/widgets/hosting_reference_text_field.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:gitlama/widgets/git_reference_field.dart';
import 'package:window_manager/window_manager.dart';
import 'package:gitlama/app/app_runtime.dart';
import 'package:gitlama/app/app_licenses.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/home_screen.dart';
import 'package:gitlama/app/workspace/commit_editor.dart';
import 'package:gitlama/app/workspace/patch_dialog.dart' show PatchDialogMode;
import 'package:gitlama/app/workspace/logbook.dart';
import 'package:gitlama/app/workspace/settings_dialog.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/cli_forwarding.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/clone_attempt.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/app/workspace/status_bar.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector_reveal.dart';
import 'package:gitlama/repositories/inspection_window_repository.dart';
import 'package:gitlama/repositories/inspector_reveal_repository.dart';
import 'package:gitlama/services/inspection_window_service.dart';
import 'package:gitlama/services/inspector_reveal_service.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/diff_renderer.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/patch.dart';
import 'package:gitlama/models/power_tools.dart';
import 'package:gitlama/models/repository_lock.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/status_acceleration.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_extensions.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/named_snapshot.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/repositories/directory_picker_repository.dart';
import 'package:gitlama/repositories/clone_repository.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/repositories/operation_center_repository.dart';
import 'package:gitlama/services/clone_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/source_syntax_service.dart';
import 'package:gitlama/services/session/session_view_cache.dart';
import 'package:gitlama/services/session/workspace_remotes.dart';
import 'package:gitlama/repositories/source_syntax_repository.dart';
import 'package:gitlama/models/source_syntax.dart';
import 'package:gitlama/models/diff_syntax.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/cli_forwarding_service.dart';
import 'package:gitlama/services/repository_appearance_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';
import 'package:gitlama/widgets/gitlama_composer.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';
import 'package:gitlama/widgets/gitlama_repo_tabs.dart';
import 'package:gitlama/widgets/gitlama_window_caption.dart';
import 'package:gitlama/widgets/diff_view.dart';
import 'package:gitlama/widgets/image_diff_view.dart';
import 'package:gitlama/widgets/conflict_resolver.dart';
import 'package:gitlama/widgets/history_graph_view.dart';

import 'support/branch_filter_rows.dart';
import 'support/fake_recovery_repository.dart';
import 'support/fake_repository_icon_repository.dart';
import 'support/fake_settings_repository.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/widgets/gitlama_git_glyphs.dart';

Finder findMeridianField(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is MeridianTextField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

Finder findTextFieldValue(String value) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.controller?.text == value,
);

Finder findComposerCommitButton() => find.descendant(
  of: find.byKey(const ValueKey('changes-commit-editor')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is MeridianButton &&
        widget.variant == MeridianButtonVariant.primary,
  ),
);

void selectComposerOption(WidgetTester tester, String title) {
  final finder = find.byKey(const ValueKey('commit-options-menu'));
  final menu = tester.widget<NativeMenuButton<CommitOverflowAction>>(finder);
  final items = menu.itemBuilder(tester.element(finder));
  final item = items.firstWhere((candidate) => candidate.title == title);
  menu.onSelected(item.value!);
}

Finder findWorkspacePaneAction(String label) {
  final railButton = find.byTooltip(label);
  return railButton.evaluate().isNotEmpty ? railButton : find.text(label).first;
}

Iterable<NativeMenuItem<T>> flattenNativeMenuItems<T>(
  NativeMenuItem<T> item,
) sync* {
  yield item;
  for (final child in item.children ?? <NativeMenuItem<T>>[]) {
    yield* flattenNativeMenuItems(child);
  }
}

Iterable<MenuAction> flatMenuActions(Menu menu) sync* {
  for (final item in menu.children) {
    if (item is MenuAction) yield item;
    if (item is Menu) yield* flatMenuActions(item);
  }
}

void main() {
  testWidgets('Linux History omits row semantics while macOS retains them', (
    tester,
  ) async {
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final semantics = tester.ensureSemantics();
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: commit,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-row-$commit')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('History row.*$commit')), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('History row.*$commit')),
      findsOneWidget,
    );
    await runtime.shutdown();
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'failed stage all shakes its action and exposes an error status',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'file.txt'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: path,
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      )..stagingOutcome = StagingExecutionState.failed;
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stage all'));
      await tester.pumpAndSettle();
      expect(repository.stagingRequests, hasLength(1));
      final shake = find
          .ancestor(
            of: find.byTooltip('Stage all'),
            matching: find.byType(MeridianShake),
          )
          .first;
      expect(tester.widget<MeridianShake>(shake).trigger, 1);
      expect(
        find.text('The staged changes could not be updated.'),
        findsWidgets,
      );
      await runtime.shutdown();
    },
  );

  testWidgets('large reference sidebar mounts only viewport rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loadedSnapshot = RepositorySnapshot(
      revision: BigInt.one,
      phase: RepositoryPhase.ready,
      refs: RepositoryRefs(
        tags: List.generate(
          163,
          (index) => RepositoryReference(
            name: 'release-tag-${index.toString().padLeft(3, '0')}'.codeUnits,
            target: '1111111111111111111111111111111111111111',
          ),
        ),
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: const [],
            branches: List.generate(
              4000,
              (index) => RepositoryReference(
                name:
                    'group/topic-${index.toString().padLeft(4, '0')}'.codeUnits,
                target: '1111111111111111111111111111111111111111',
              ),
            ),
          ),
        ],
      ),
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.zero,
        phase: RepositoryPhase.loading,
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    repository.pendingEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: loadedSnapshot,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    final sidebar = find.byType(WorkspaceSidebar);
    final rows = find.descendant(
      of: sidebar,
      matching: find.byType(MeridianListRow),
    );
    await _openSidebarTags(tester);
    // Groups start collapsed, so thousands of branches stay out of the way.
    expect(find.text('group'), findsNothing);
    expect(find.text('topic-0000'), findsNothing);
    await _expandSidebarGroup(tester, 'sidebar-ref-origin');
    expect(find.text('topic-0000'), findsNothing);
    await _expandSidebarGroup(tester, 'sidebar-ref-1-group/');
    expect(find.text('topic-0000'), findsOneWidget);
    debugPrint('sidebar_mounted_rows=${rows.evaluate().length}');
    expect(rows.evaluate().length, lessThan(100));
    final scrollable = find
        .descendant(of: sidebar, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    debugPrint('sidebar_mounted_rows=${rows.evaluate().length}');
    expect(rows.evaluate().length, lessThan(100));
    expect(find.text('release-tag-162'), findsOneWidget);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: sidebar, matching: find.text('group')),
    );
    await tester.pumpAndSettle();
    expect(find.text('topic-0000'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('topic-0000'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('topic-0000'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // Scrolling through tags disposes the remote group row. Its explicit
    // expansion differs from the default and must survive the recycling.
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('group'), findsNothing);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('topic-0000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
    setUpAll(() async {
      final mono = FontLoader('packages/meridian_ui/JetBrains Mono')
        ..addFont(
          rootBundle.load(
            'packages/meridian_ui/assets/fonts/JetBrainsMono-Regular.ttf',
          ),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await mono.load();
      await icons.load();
      const fontPath = String.fromEnvironment('UI_REVIEW_FONT');
      if (fontPath.isNotEmpty) {
        for (final family in ['Roboto', '.AppleSystemUIFont']) {
          final body = FontLoader(family)
            ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
          await body.load();
        }
      }
    });
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  registerGitLamaLicenses();

  for (final locale in const [Locale('en'), Locale('de')]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'polished reference dialogs ${locale.languageCode} ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final runtime = await _runtime(
            _WelcomeRepository(
              historyRows: const [
                HistoryTopologyRow(
                  objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  parents: [],
                  refs: [],
                  lane: 0,
                  shape: 0,
                ),
              ],
              snapshot: RepositorySnapshot(
                revision: BigInt.one,
                phase: RepositoryPhase.ready,
                refs: RepositoryRefs(
                  branches: [
                    RepositoryReference(
                      name: 'feature/example'.codeUnits,
                      target: 'a' * 40,
                    ),
                  ],
                ),
              ),
            ),
            _Picker(null),
          );
          await runtime.repositorySessions.open('/fixture');
          await runtime.repositorySessions.history.load(
            runtime.repositorySessions.workspace.activeTab!.session!.identity,
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildAppTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    locale.languageCode == 'de' ? 1.3 : 1,
                  ),
                ),
                child: StatusNotificationScope(child: child!),
              ),
              home: HomeScreen(runtime: runtime),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(HomeScreen)),
          );
          for (final entry in [
            ('remote', l10n.commandAddRemote),
            ('branch', l10n.commandCreateBranch),
            ('tag', l10n.commandCreateTag),
          ]) {
            final pointer = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await pointer.addPointer(location: Offset.zero);
            await pointer.moveTo(
              tester.getCenter(
                find.text(switch (entry.$1) {
                  'remote' => l10n.workspaceRemotes.toUpperCase(),
                  'branch' => l10n.workspaceBranches.toUpperCase(),
                  _ => l10n.workspaceTags.toUpperCase(),
                }),
              ),
            );
            await tester.pump();
            await pointer.moveTo(
              tester.getCenter(find.byTooltip(entry.$2).last),
            );
            await tester.pump();
            await tester.tap(find.byTooltip(entry.$2).last);
            await pointer.removePointer();
            await tester.pumpAndSettle();
            expect(find.byType(MeridianDialog), findsOneWidget);
            expect(
              tester
                  .getSize(
                    find
                        .descendant(
                          of: find.byType(MeridianDialog),
                          matching: find.byWidgetPredicate(
                            (widget) =>
                                widget is DecoratedBox &&
                                widget.decoration is BoxDecoration &&
                                (widget.decoration as BoxDecoration)
                                        .boxShadow
                                        ?.length ==
                                    2,
                          ),
                        )
                        .first,
                  )
                  .width,
              lessThanOrEqualTo(560),
            );
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
              await expectLater(
                find.byType(MeridianDialog),
                matchesGoldenFile(
                  '../build/evidence/ui-review/${entry.$1}-${locale.languageCode}-${brightness.name}.png',
                ),
              );
            }
            if (entry.$1 == 'branch') {
              await tester.tap(find.byTooltip(l10n.referencePickerTitle).last);
              await tester.pumpAndSettle();
              await tester.enterText(
                find.widgetWithText(TextField, l10n.referencePickerSearch),
                'Commit subject',
              );
              await tester.pumpAndSettle();
              expect(
                find.widgetWithText(MeridianSuggestionRow, 'Commit subject'),
                findsOneWidget,
              );
              if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
                await expectLater(
                  find.byType(MeridianDialog).last,
                  matchesGoldenFile(
                    '../build/evidence/ui-review/reference-picker-${locale.languageCode}-${brightness.name}.png',
                  ),
                );
              }
              await tester.tap(find.text(l10n.cancel).last);
              await tester.pumpAndSettle();
            }
            await tester.tap(find.text(l10n.cancel));
            await tester.pumpAndSettle();
          }
          await runtime.shutdown();
        },
      );
    }
  }

  testWidgets('tab plus opens chooser and recent selection replaces that tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker('/chosen'));
    await runtime.repositorySessions.open('/first');
    await runtime.settings.saveDurable(
      runtime.settings.current.copyWith(
        recentRepositories: [
          NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/recent'.codeUnits,
          ),
          NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/other/project'.codeUnits,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repository-open-tab')));
    await tester.pumpAndSettle();
    final chooserId = runtime.repositorySessions.workspace.activeTabId;
    expect(runtime.repositorySessions.workspace.tabs, hasLength(2));
    expect(find.byKey(const ValueKey('repository-chooser')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('repository-chooser-mark')),
      findsOneWidget,
    );
    expect(find.text('/recent'), findsOneWidget);
    expect(find.text('/other/project'), findsOneWidget);
    final filter = find.byKey(const ValueKey('recent-repositories-filter'));
    await tester.enterText(filter, 'other proj');
    await tester.pumpAndSettle();
    expect(find.text('/recent'), findsNothing);
    expect(find.text('/other/project'), findsOneWidget);
    await tester.enterText(filter, 'missing');
    await tester.pumpAndSettle();
    expect(
      find.text('No recent repository matches the filter.'),
      findsOneWidget,
    );
    await tester.enterText(filter, 'RECENT');
    await tester.pumpAndSettle();
    expect(find.text('/other/project'), findsNothing);
    await tester.tap(find.text('/recent'));
    await tester.pumpAndSettle();
    expect(runtime.repositorySessions.workspace.tabs, hasLength(2));
    expect(runtime.repositorySessions.workspace.activeTabId, chooserId);
    expect(find.byKey(const ValueKey('repository-chooser')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('repository-open-tab')));
    await tester.pumpAndSettle();
    final browseId = runtime.repositorySessions.workspace.activeTabId;
    await tester.tap(find.byKey(const ValueKey('repository-chooser-browse')));
    await tester.pumpAndSettle();
    expect(runtime.repositorySessions.workspace.activeTabId, browseId);
    expect(runtime.repositorySessions.workspace.activeTab!.label, 'chosen');
    await runtime.shutdown();
  });

  testWidgets('sidebar plus reveals on hover without changing its size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/first');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final add = find.byTooltip('Create branch…');
    expect(add, findsNothing);
    final bounds = tester.getRect(find.text('BRANCHES'));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(bounds.center);
    await tester.pump();
    expect(add, findsOneWidget);
    expect(tester.getRect(find.text('BRANCHES')), bounds);
    await pointer.moveTo(const Offset(799, 599));
    await tester.pump();
    expect(add, findsNothing);
    await pointer.removePointer();
    await runtime.shutdown();
  });

  testWidgets('a clicked sidebar section shows its count again when the '
      'pointer leaves', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/first');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final add = find.byTooltip('Create tag…');
    final header = tester.getCenter(find.text('TAGS'));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(header);
    await tester.pump();
    expect(add, findsOneWidget);

    // The click gives the section focus; focus alone must not hold the action.
    await pointer.down(header);
    await pointer.up();
    await tester.pumpAndSettle();
    await pointer.moveTo(const Offset(799, 599));
    await tester.pump();
    expect(add, findsNothing);

    // Keyboard focus still reveals it, until the pointer is used again.
    await tester.sendKeyEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(add, findsOneWidget);
    await pointer.down(const Offset(799, 599));
    await pointer.up();
    await tester.pump();
    expect(add, findsNothing);
    await pointer.removePointer();
    await runtime.shutdown();
  });

  testWidgets('welcome opens the settings without a repository', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const Key('welcome-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);

    // Background fetch is on until it is switched off here.
    expect(runtime.settings.current.autoFetch.enabled, isTrue);
    await tester.tap(find.byKey(const Key('settings-category-git')));
    await tester.pumpAndSettle();
    expect(find.text('Fetch automatically'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-repository-auto-fetch')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('settings-auto-fetch')),
        matching: find.text('Off'),
      ),
    );
    await tester.pumpAndSettle();
    expect(runtime.settings.current.autoFetch.enabled, isFalse);
    await runtime.shutdown();
  });

  testWidgets('Escape closes the settings opened by their shortcut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    for (var round = 0; round < 2; round++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
    }
    await runtime.shutdown();
  });

  testWidgets('macOS repository tabs occupy the integrated title bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    final leading = find.byKey(const ValueKey('macos-titlebar-leading'));
    final trailing = find.byKey(const ValueKey('macos-titlebar-trailing-drag'));
    final gap = find.byKey(const ValueKey('repository-titlebar-tab-gap'));
    final add = find.byKey(const ValueKey('repository-open-tab'));
    expect(
      tester.getSize(leading),
      const Size(MeridianLayout.macOSTrafficLightInset, MeridianSize.toolbar),
    );
    expect(tester.getSize(trailing).width, GitLamaLayout.titleBarDragWidth);
    expect(tester.getSize(gap).width, greaterThan(0));
    expect(tester.getRect(gap).right, tester.getRect(add).left);
    expect(
      find.ancestor(of: gap, matching: find.byType(DragToMoveArea)),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byKey(const Key('repository-toolbar-context'))).left,
      greaterThan(tester.getTopRight(leading).dx),
    );
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'isMaximized') return false;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.tapAt(tester.getCenter(gap));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(tester.getCenter(gap));
    await tester.pumpAndSettle();
    expect(calls, containsAllInOrder(['isMaximized', 'maximize']));
    await runtime.shutdown();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final width in [900.0, 1280.0]) {
    testWidgets('Linux welcome title bar accepts window gestures at $width', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      const channel = GitLamaWindowCaptionFrame.channel;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'captionLayout') return ':close';
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => GitLamaWindowCaptionFrame(
            child: StatusNotificationScope(child: child!),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(Brightness.light),
          home: HomeScreen(runtime: runtime),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(PreferredSize));
      final settings = find.byKey(const Key('welcome-settings'));
      final titleRight = tester.getRect(settings).left;
      final points = [
        Offset(32, bar.center.dy),
        Offset(titleRight / 2, bar.center.dy),
        Offset(titleRight - 16, bar.center.dy),
      ];
      for (final point in points) {
        calls.clear();
        final drag = await tester.startGesture(
          point,
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(40, 0));
        await drag.up();
        await tester.pumpAndSettle();
        expect(calls, ['beginMove'], reason: 'Drag at $point');
      }

      calls.clear();
      await tester.tapAt(points[1]);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(points[1]);
      await tester.pumpAndSettle();
      expect(calls, ['toggleMaximize']);

      calls.clear();
      await tester.tapAt(points[1], buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(calls, ['showWindowMenu']);

      calls.clear();
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('window-caption-close')));
      await tester.pumpAndSettle();
      expect(calls, ['close']);
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Linux window buttons follow the toolbar actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    const channel = GitLamaWindowCaptionFrame.channel;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'captionLayout') return 'close:minimize,maximize';
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GitLamaWindowCaptionFrame(
          child: StatusNotificationScope(child: child!),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(Brightness.light),
        home: HomeScreen(runtime: runtime),
      ),
    );
    await tester.pumpAndSettle();

    final close = find.byKey(const ValueKey('window-caption-close'));
    final minimize = find.byKey(const ValueKey('window-caption-minimize'));
    final maximize = find.byKey(const ValueKey('window-caption-maximize'));
    final overflow = find.byKey(const Key('toolbar-overflow'));
    expect(find.byKey(const ValueKey('macos-titlebar-leading')), findsNothing);
    // Leading-edge buttons join the trailing ones in the toolbar corner.
    expect(
      tester.getRect(close).left,
      greaterThan(tester.getRect(overflow).right),
    );
    expect(
      tester.getRect(minimize).left,
      greaterThanOrEqualTo(tester.getRect(close).right),
    );
    expect(
      tester.getRect(maximize).left,
      greaterThanOrEqualTo(tester.getRect(minimize).right),
    );
    expect(tester.getRect(maximize).right, lessThanOrEqualTo(1280));

    await tester.tap(close);
    await tester.tap(minimize);
    await tester.tap(maximize);
    await tester.pump();
    expect(calls, containsAllInOrder(['close', 'minimize', 'toggleMaximize']));

    final gap = find.byKey(const ValueKey('repository-titlebar-tab-gap'));
    await tester.tapAt(tester.getCenter(gap));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(tester.getCenter(gap));
    await tester.pumpAndSettle();
    expect(calls.last, 'toggleMaximize');
    await tester.timedDrag(
      gap,
      const Offset(0, 40),
      const Duration(milliseconds: 200),
    );
    expect(calls, contains('beginMove'));
    await runtime.shutdown();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('crowded titlebar keeps tabs scrollable and plus visible', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    for (var index = 0; index < 6; index++) {
      await runtime.repositorySessions.open('/repository-$index');
    }
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final gap = find.byKey(const ValueKey('repository-titlebar-tab-gap'));
    final add = find.byKey(const ValueKey('repository-open-tab'));
    expect(tester.getSize(gap).width, 0);
    expect(tester.getRect(add).right, lessThanOrEqualTo(900));
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('repository toolbar keeps a quiet GitLama hierarchy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(
      _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            branchName: 'main'.codeUnits,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      ),
      _Picker(null),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    expect(
      tester.getSize(find.byKey(const Key('repository-toolbar'))).height,
      MeridianSize.toolbar,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('toolbar-action-fetch'))).height,
      MeridianLayout.toolbarButtonHeight,
    );
    expect(find.byKey(const Key('repository-toolbar-context')), findsOneWidget);
    expect(find.byType(GitLamaCompass), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toolbar-command-palette')),
      findsOneWidget,
    );
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byTooltip('Recovery'), findsNothing);

    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pump();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.history,
    );

    await runtime.shutdown();
  });

  testWidgets('welcome actions use the picker and show typed init refusal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository();
    final picker = _Picker('/chosen');
    final runtime = await _runtime(repository, picker);
    await tester.pumpWidget(_app(runtime));

    expect(find.text('Start with a repository'), findsOneWidget);
    expect(find.text('Open…'), findsOneWidget);
    expect(find.text('Create…'), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/brand/tile-64.png'),
          tester.element(find.byType(HomeScreen)),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('../build/evidence/ui-review/welcome.png'),
      );
    }

    await tester.tap(find.text('Create…'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(MeridianCheckbox, 'Bare repository'),
      findsOneWidget,
    );
    await tester.tap(find.text('Choose destination'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.initializedPath, '/chosen');
    expect(repository.initializedBare, isFalse);
    expect(
      find.text('That destination is already a Git repository.'),
      findsOneWidget,
    );
    expect(find.textContaining('private'), findsNothing);
    await runtime.shutdown();
  });

  testWidgets('welcome bare initialization keeps its choice in the dialog', (
    tester,
  ) async {
    final repository = _WelcomeRepository();
    final runtime = await _runtime(repository, _Picker('/chosen'));
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.text('Initialize bare repository'));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<MeridianCheckbox>(
      find.widgetWithText(MeridianCheckbox, 'Bare repository'),
    );
    expect(checkbox.value, isTrue);
    await tester.tap(find.text('Choose destination'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.initializedBare, isTrue);
    await runtime.shutdown();
  });

  testWidgets('German welcome remains usable at 130 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: _app(runtime, locale: const Locale('de')),
      ),
    );

    expect(find.text('Mit einem Repository beginnen'), findsOneWidget);
    expect(find.text('Bare-Repository initialisieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets('welcome shows exact typed repository discovery failures', (
    tester,
  ) async {
    final cases = <RepositoryFailureCode, String>{
      RepositoryFailureCode.pathNotFound: 'The selected path no longer exists.',
      RepositoryFailureCode.permissionDenied:
          'GitLama does not have permission to read the selected path.',
      RepositoryFailureCode.notRepository:
          'The selected path is not inside a Git repository.',
    };
    for (final MapEntry(key: code, value: message) in cases.entries) {
      final runtime = await _runtime(
        _WelcomeRepository(openFailure: code),
        _Picker('/selected'),
      );
      await tester.pumpWidget(_app(runtime));
      await tester.tap(find.text('Open…'));
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      expect(find.text('The repository could not be opened.'), findsNothing);

      await runtime.shutdown();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('clone dialog validates through the typed clone boundary', (
    tester,
  ) async {
    final clones = _FailingCloneRepository();
    final runtime = await _runtime(
      _WelcomeRepository(),
      _Picker('/clone-target'),
      clones,
    );
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.text('Clone…'));
    await tester.pumpAndSettle();
    expect(find.text('Repository URL or path'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'relative/source');
    await tester.pump();
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();

    expect(clones.destination, '/clone-target');
    expect(
      find.text('Enter a supported repository URL or absolute local path.'),
      findsOneWidget,
    );
    await runtime.shutdown();
  });

  testWidgets('SSH challenge shows bounded fields and supports rejection', (
    tester,
  ) async {
    final clones = _FailingCloneRepository(hostKeyFlow: true);
    final runtime = await _runtime(
      _WelcomeRepository(),
      _Picker('/clone-target'),
      clones,
    );
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.text('Clone…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'ssh://git@example.test/repository',
    );
    await tester.pump();
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(find.text('Inspect host key'), findsOneWidget);

    await tester.tap(find.text('Inspect host key'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Verify SSH host key'), findsOneWidget);
    expect(find.textContaining('SHA256:fixture'), findsOneWidget);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(clones.rejectCount, 1);
    expect(find.text('Verify SSH host key'), findsNothing);
    await runtime.shutdown();
  });

  testWidgets('workspace keeps independent tab navigation and closes stably', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/first');
    await runtime.repositorySessions.open('/second');
    await tester.pumpWidget(_app(runtime));

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(findWorkspacePaneAction('Changes'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(runtime.repositorySessions.workspace.tabs.map((tab) => tab.label), [
      'second',
      'first',
    ]);
    await tester.drag(find.text('second'), const Offset(420, 0));
    await tester.pumpAndSettle();
    expect(runtime.repositorySessions.workspace.tabs.map((tab) => tab.label), [
      'first',
      'second',
    ]);

    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pump();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.history,
    );
    await tester.tap(find.text('first'));
    await tester.pump();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.changes,
    );
    await tester.tap(find.byTooltip('Close first'));
    await tester.pump();
    expect(runtime.repositorySessions.workspace.tabs, hasLength(1));
    expect(runtime.repositorySessions.workspace.activeTab?.label, 'second');

    await runtime.shutdown();
  });

  testWidgets('the history query belongs to the tab that typed it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(
      _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
        ),
        historyRows: const [
          HistoryTopologyRow(
            objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
      ),
      _Picker(null),
    );
    await runtime.repositorySessions.open('/first');
    await runtime.repositorySessions.open('/second');
    await tester.pumpWidget(_app(runtime));
    // Both tabs show History, so one pane serves them in turn.
    await tester.tap(find.text('first'));
    await tester.pumpAndSettle();
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    final query = find.descendant(
      of: find.byKey(const ValueKey('history-query')),
      matching: find.byType(EditableText),
    );
    String queryText() => tester.widget<EditableText>(query).controller.text;
    await tester.enterText(query, 'needle');
    await tester.pumpAndSettle();
    expect(queryText(), 'needle');

    await tester.tap(find.text('first'));
    await tester.pumpAndSettle();
    expect(queryText(), isEmpty);
    await runtime.shutdown();
  });

  testWidgets('history toolbar stays usable beside Detail at 1100 pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(
      _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
        ),
        historyRows: const [
          HistoryTopologyRow(
            objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
      ),
      _Picker(null),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-query')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-pane')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  for (final brightness in Brightness.values) {
    testWidgets('M08 shell visual review ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = await _runtime(
        _WelcomeRepository(
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            status: RepositoryStatus(
              workingTree: WorkingTreeState.clean,
              branchName: 'main'.codeUnits,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: const [],
              totalEntries: BigInt.zero,
              entriesTruncated: false,
              operations: const [],
            ),
          ),
        ),
        _Picker(null),
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime, brightness: brightness));
      await tester.pumpAndSettle();
      expect(find.byType(GitLamaCompass), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            '../build/evidence/meridian/M08-shell-${brightness.name}.png',
          ),
        );
      }
      await runtime.shutdown();
    });
  }

  // Renders the website's workspace screenshots. Run with
  // --dart-define=CAPTURE_WEBSITE=true --dart-define=CAPTURE_UI_REVIEW=true
  // --dart-define=UI_REVIEW_FONT=<body font> --update-goldens, then copy
  // build/evidence/website/*.png to webfront/assets/.
  for (final brightness in Brightness.values) {
    testWidgets(
      'website workspace capture ${brightness.name}',
      skip: !const bool.fromEnvironment('CAPTURE_WEBSITE'),
      (tester) async {
        tester.view.physicalSize = const Size(2880, 1800);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Stable, varied object IDs from a small linear congruential walk.
        String id(int index) {
          var state = index * 2654435761 + 97;
          final digits = StringBuffer();
          while (digits.length < 40) {
            state = (state * 1103515245 + 12345) & 0x7fffffff;
            digits.write((state >> 16 & 15).toRadixString(16));
          }
          return digits.toString();
        }

        final now = DateTime.utc(2026, 9, 26, 9).millisecondsSinceEpoch ~/ 1000;
        HistoryTopologyRow commit(
          int index,
          int lane,
          List<int> parents,
          String subject,
          String author, {
          List<String> refs = const [],
          int shape = 0,
          int hoursAgo = 0,
          bool current = false,
        }) => HistoryTopologyRow(
          objectId: id(index),
          parents: [for (final parent in parents) id(parent)],
          refs: [for (final ref in refs) ref.codeUnits],
          refCount: refs.length,
          lane: lane,
          shape: shape,
          subject: subject.codeUnits,
          author: author.codeUnits,
          authorTime: now - hoursAgo * 3600,
          current: current,
        );
        HistoryTopologySegment edge(
          int from,
          int to,
          int fromLane,
          int toLane,
          HistorySegmentKind kind, {
          int ordinal = 0,
        }) => HistoryTopologySegment(
          fromObjectId: from < 0 ? 'wip' : id(from),
          toObjectId: id(to),
          parentOrdinal: ordinal,
          fromLane: fromLane,
          toLane: toLane,
          kind: kind.index,
        );
        final rows = [
          const HistoryTopologyRow(
            objectId: 'wip',
            parents: [],
            refs: [],
            lane: 0,
            shape: 5,
            wipChangedFiles: 4,
            wipStagedFiles: 1,
          ),
          commit(
            1,
            0,
            [3],
            'Draw stashes as leaves on their base commit',
            'Ada Brandt',
            refs: ['refs/heads/main', 'refs/remotes/origin/main'],
            current: true,
            hoursAgo: 1,
          ),
          commit(
            2,
            1,
            [3],
            'Lease remote branch deletion on the fetched ref',
            'Jonas Pihl',
            refs: ['refs/heads/feature/delete-upstream'],
            hoursAgo: 2,
          ),
          commit(
            3,
            0,
            [5, 4],
            "Merge branch 'feature/compass'",
            'Ada Brandt',
            shape: 1,
            hoursAgo: 5,
          ),
          commit(
            4,
            1,
            [6],
            'Reveal shortcut hints while the modifier is held',
            'Mira Castell',
            refs: ['refs/heads/feature/compass'],
            hoursAgo: 7,
          ),
          commit(
            5,
            0,
            [7],
            'Fit selects to their longest choice',
            'Ada Brandt',
            refs: ['refs/tags/v0.3.0'],
            hoursAgo: 20,
          ),
          commit(
            6,
            1,
            [7],
            'Keep toolbar clicks out of keyboard focus',
            'Mira Castell',
            hoursAgo: 26,
          ),
          commit(
            7,
            0,
            [8],
            'Resume interrupted rebases after restart',
            'Jonas Pihl',
            hoursAgo: 30,
          ),
          commit(
            8,
            0,
            [9],
            'Stage selected lines from the split diff',
            'Ada Brandt',
            hoursAgo: 49,
          ),
          commit(
            9,
            0,
            [10],
            'Prepare 0.2.5 beta 1',
            'Release Bot',
            refs: ['refs/tags/v0.2.5-beta.1'],
            hoursAgo: 72,
          ),
          commit(
            10,
            0,
            [11],
            'Show hosted pull requests beside branches',
            'Mira Castell',
            hoursAgo: 96,
          ),
          commit(
            11,
            0,
            [12],
            'Virtualize the history graph',
            'Jonas Pihl',
            hoursAgo: 120,
          ),
          commit(
            12,
            0,
            [13],
            'Add named snapshots with restart-safe undo',
            'Ada Brandt',
            hoursAgo: 150,
          ),
          commit(
            13,
            0,
            [14],
            'Preview interactive rebase before mutation',
            'Mira Castell',
            hoursAgo: 190,
          ),
          commit(
            14,
            0,
            [15],
            'Compare two commits from the graph',
            'Jonas Pihl',
            hoursAgo: 230,
          ),
          commit(
            15,
            0,
            [16],
            'Blame with ignore-revs support',
            'Ada Brandt',
            hoursAgo: 260,
          ),
          commit(
            16,
            0,
            [17],
            'Open repositories in tabs',
            'Mira Castell',
            hoursAgo: 300,
          ),
          commit(
            17,
            0,
            [18],
            'Fetch in the background every 10 minutes',
            'Jonas Pihl',
            hoursAgo: 340,
          ),
          commit(
            18,
            0,
            [19],
            'Recover the index lock safely',
            'Ada Brandt',
            hoursAgo: 400,
          ),
          commit(
            19,
            0,
            [20],
            'Initial workspace shell',
            'Ada Brandt',
            hoursAgo: 480,
          ),
        ];
        final segments = [
          edge(-1, 1, 0, 0, HistorySegmentKind.straight),
          edge(1, 3, 0, 0, HistorySegmentKind.straight),
          edge(2, 3, 1, 0, HistorySegmentKind.join),
          edge(3, 5, 0, 0, HistorySegmentKind.straight),
          edge(3, 4, 0, 1, HistorySegmentKind.merge, ordinal: 1),
          edge(4, 6, 1, 1, HistorySegmentKind.straight),
          edge(5, 7, 0, 0, HistorySegmentKind.straight),
          edge(6, 7, 1, 0, HistorySegmentKind.join),
          for (var index = 7; index < 19; index++)
            edge(index, index + 1, 0, 0, HistorySegmentKind.straight),
        ];
        RepositoryReference branch(
          String name,
          int target, {
          bool head = false,
          String? upstream,
        }) => RepositoryReference(
          name: name.codeUnits,
          target: id(target),
          head: head,
          upstream: upstream?.codeUnits,
        );
        final runtime = await _runtime(
          _WelcomeRepository(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
              status: RepositoryStatus(
                workingTree: WorkingTreeState.dirty,
                branchName: 'main'.codeUnits,
                headObjectId: id(1),
                ahead: BigInt.one,
                behind: BigInt.zero,
                entries: const [],
                totalEntries: BigInt.from(4),
                entriesTruncated: false,
                operations: const [],
              ),
              refCounts: const RepositoryRefCounts(
                branches: 3,
                remotes: 1,
                tags: 2,
              ),
              refs: RepositoryRefs(
                branches: [
                  branch(
                    'main',
                    1,
                    head: true,
                    upstream: 'refs/remotes/origin/main',
                  ),
                  branch('feature/compass', 4),
                  branch('feature/delete-upstream', 2),
                ],
                remotes: [
                  RepositoryRemote(
                    name: 'origin'.codeUnits,
                    displayUrl: 'github.com/devmil/gitlama'.codeUnits,
                    branches: [branch('main', 1)],
                  ),
                ],
                tags: [branch('v0.3.0', 5), branch('v0.2.5-beta.1', 9)],
              ),
            ),
            historyRows: rows,
            historySegments: segments,
            historyLaneCount: 2,
            inspectionFiles: [
              for (final (kind, path) in const [
                (CommitFileChangeKind.modified, 'lib/widgets/compass.dart'),
                (CommitFileChangeKind.modified, 'lib/app/shell_chrome.dart'),
                (CommitFileChangeKind.added, 'test/compass_hint_test.dart'),
                (CommitFileChangeKind.modified, 'CHANGELOG.md'),
              ])
                CommitFileChange(
                  oldMode: kind == CommitFileChangeKind.added ? 0 : 0x81a4,
                  newMode: 0x81a4,
                  kind: kind,
                  oldPath: path.codeUnits,
                  newPath: path.codeUnits,
                ),
            ],
          ),
          _Picker(null),
        );
        await runtime.repositorySessions.open('/gitlama');
        await tester.pumpWidget(_app(runtime, brightness: brightness));
        await tester.pumpAndSettle();
        await tester.tap(findWorkspacePaneAction('History'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Reveal shortcut hints while the modifier is held'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
          await expectLater(
            find.byType(Scaffold).first,
            matchesGoldenFile(
              '../build/evidence/website/workspace-${brightness.name}.png',
            ),
          );
        }
        await runtime.shutdown();
      },
    );
  }

  for (final size in const [
    Size(900, 600),
    Size(1280, 720),
    Size(1440, 900),
    Size(1920, 1080),
    Size(1100, 650),
  ]) {
    testWidgets(
      'workspace fits ${size.width}x${size.height} in German at 130%',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
        await runtime.repositorySessions.open('/repository');
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: _app(runtime, locale: const Locale('de')),
          ),
        );

        expect(findWorkspacePaneAction('Änderungen'), findsOneWidget);
        expect(find.byTooltip('Befehle (Ctrl+P)'), findsOneWidget);
        if (size.width <= GitLamaLayout.compactBreakpoint) {
          expect(find.byTooltip('Mehr'), findsOneWidget);
          expect(find.byTooltip('Aktivität'), findsNothing);
          final more = tester.widget<NativeMenuButton<AppCommandId>>(
            find.byKey(const Key('toolbar-overflow')),
          );
          expect(
            more
                .itemBuilder(
                  tester.element(find.byKey(const Key('toolbar-overflow'))),
                )
                .expand(flattenNativeMenuItems)
                .map((item) => item.value),
            contains(AppCommandId.showActivity),
          );
        } else {
          expect(find.byTooltip('Aktivität'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await runtime.shutdown();
      },
    );
  }

  testWidgets(
    'workspace projects coherent status, refs, selection, and refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'tracked.txt'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            branchName: 'main'.codeUnits,
            ahead: BigInt.one,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: path,
                index: ChangeKind.modified,
                worktree: ChangeKind.unmodified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
          refCounts: const RepositoryRefCounts(
            branches: 2,
            remotes: 1,
            tags: 3,
            stashes: 4,
            worktrees: 1,
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      expect(find.text('tracked.txt'), findsOneWidget);
      expect(find.text('main'), findsWidgets);
      expect(find.text('BRANCHES'), findsOneWidget);
      await tester.tap(find.text('tracked.txt'));
      await tester.pump();
      expect(
        runtime
            .repositorySessions
            .workspace
            .activeTab
            ?.navigation
            .selectedIdentity,
        'tracked.txt',
      );
      await tester.tap(
        find.byTooltip(
          'Reload this repository from disk. Fetch gets new commits from remotes; Pull also updates your branch.',
        ),
      );
      await tester.pump();
      expect(repository.refreshCount, 1);
      await runtime.shutdown();
    },
  );

  testWidgets(
    'staging stays selectable, queues files and shows native refresh progress',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entries = [
        for (final name in ['a.txt', 'b.txt', 'c.txt'])
          RepositoryStatusEntry(
            kind: StatusEntryKind.ordinary,
            path: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: name.codeUnits,
            ),
            index: ChangeKind.unmodified,
            worktree: ChangeKind.modified,
          ),
      ];
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: entries,
            totalEntries: BigInt.from(3),
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      );
      final gate = repository.stagingBarrier = Completer<void>();
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      Finder row(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(GitLamaFileRow),
      );
      await tester.tap(row('a.txt'));
      await tester.pump();
      await tester.tap(_sectionAction('Stage selected'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.stagingRequests, hasLength(1));
      await tester.tap(row('b.txt'));
      await tester.pump();
      expect(tester.widget<GitLamaFileRow>(row('b.txt')).selected, isTrue);
      await tester.tap(_sectionAction('Stage selected'));
      await tester.pump();
      expect(repository.stagingRequests, hasLength(1));
      expect(find.textContaining('1 action queued.'), findsOneWidget);
      await tester.tap(find.text('Cancel queued actions'));
      await tester.pump();
      expect(find.textContaining('No queued actions.'), findsOneWidget);
      await tester.tap(_sectionAction('Stage selected'));
      await tester.pump();
      await tester.tap(row('c.txt'));
      await tester.pump();
      repository.stagingPhaseValue = StagingPhase.refreshing;
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.textContaining('Index updated. Refreshing changes'),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(repository.stagingRequests, hasLength(2));
      expect(repository.stagingRequests.last.paths, ['b.txt'.codeUnits]);
      expect(tester.widget<GitLamaFileRow>(row('c.txt')).selected, isTrue);
      expect(find.byKey(const ValueKey('staging-progress')), findsNothing);
      expect(tester.takeException(), isNull);
      await runtime.shutdown();
    },
  );

  testWidgets(
    'changes stage selected files and partial hunks without duplicate runs',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stagedPath = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'staged.txt'.codeUnits,
      );
      final unstagedPath = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'unstaged.txt'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: stagedPath,
                index: ChangeKind.modified,
                worktree: ChangeKind.unmodified,
              ),
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: unstagedPath,
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.two,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        workingDiffResult: DiffPage(
          requestId: BigInt.from(73),
          layout: DiffViewLayout.unified,
          totalRows: 3,
          offset: 0,
          rows: const [
            DiffDisplayRow(
              stableId: 'file',
              kind: DiffRowKind.file,
              text: [117, 110, 115, 116, 97, 103, 101, 100, 46, 116, 120, 116],
            ),
            DiffDisplayRow(
              stableId: 'hunk-1',
              kind: DiffRowKind.hunk,
              text: [64, 64, 32, 45, 49, 32, 43, 49, 32, 64, 64],
            ),
            DiffDisplayRow(
              stableId: 'line-1',
              kind: DiffRowKind.addition,
              text: [110, 101, 119],
              newLine: 1,
              selectable: true,
            ),
          ],
          payloadBytes: 27,
        ),
      );
      repository.stagingBarrier = Completer<void>();
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      expect(find.text('Staged changes'), findsOneWidget);
      expect(find.text('Unstaged changes'), findsOneWidget);
      final unstagedRow = find.ancestor(
        of: find.text('unstaged.txt'),
        matching: find.byType(GitLamaFileRow),
      );
      await tester.tap(unstagedRow);
      await tester.pump();
      await tester.tap(find.byTooltip('Discard selected'));
      await tester.pumpAndSettle();
      expect(find.text('Permanently discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.executedDiscardToken, isNull);
      expect(repository.discardRequests.single.scope, DiscardScope.files);
      await tester.tap(find.byTooltip('Discard all'));
      await tester.pumpAndSettle();
      expect(find.text('Permanently discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.executedDiscardToken, isNull);
      expect(repository.discardRequests, hasLength(2));
      final stageSelectedButton = _sectionAction('Stage selected');
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Stage selected');
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianListRow, 'Stage selected'));
      await tester.pump();
      await tester.pump();
      expect(repository.stagingRequests, hasLength(1));
      expect(repository.stagingRequests.single.scope, StagingScope.files);
      expect(repository.stagingRequests.single.side, StagingSide.unstaged);
      expect(
        repository.stagingRequests.single.paths.single,
        unstagedPath.units,
      );
      expect(
        tester.widget<MeridianIconButton>(stageSelectedButton).onPressed,
        isNull,
      );
      repository.stagingBarrier!.complete();
      await tester.pumpAndSettle();

      final stagedRow = find.ancestor(
        of: find.text('staged.txt'),
        matching: find.byType(GitLamaFileRow),
      );
      await tester.tap(stagedRow);
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Unstage selected');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(MeridianListRow, 'Unstage selected'),
      );
      await tester.pumpAndSettle();
      expect(repository.stagingRequests, hasLength(2));
      expect(repository.stagingRequests.last.side, StagingSide.staged);

      await tester.tap(unstagedRow);
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Discard selected');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(MeridianListRow, 'Discard selected'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Permanently discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.discardRequests, hasLength(3));
      expect(repository.discardRequests.last.scope, DiscardScope.files);

      // The highlighted file's diff names it too; the menu is the row's.
      final fileMenuWidget = tester.widget<GitLamaContextMenuWidget>(
        find.ancestor(
          of: unstagedRow,
          matching: find.byType(GitLamaContextMenuWidget),
        ),
      );
      final fileMenu = fileMenuWidget.testMenu() as Menu;
      expect(
        fileMenu.children.whereType<MenuAction>().any(
          (action) => action.title?.startsWith('Open in ') == true,
        ),
        isTrue,
      );
      fileMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Select changed lines')
          .callback();
      await tester.pumpAndSettle();
      await tester.tap(find.text('@@ -1 +1 @@').last);
      await tester.pump();
      await tester.tap(find.text('Stage selected changes'));
      await tester.pumpAndSettle();

      expect(repository.stagingRequests, hasLength(3));
      expect(repository.stagingRequests.last.scope, StagingScope.rows);
      expect(repository.stagingRequests.last.requestId, BigInt.from(73));
      expect(repository.stagingRequests.last.rowIds, ['hunk-1']);
      // Each staging run rescans once, through its native mutation lease.
      expect(repository.refreshCount, 0);

      fileMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Select changed lines')
          .callback();
      await tester.pumpAndSettle();
      await tester.tap(find.text('@@ -1 +1 @@').last);
      await tester.pump();
      await tester.ensureVisible(find.text('Discard selected changes').last);
      await tester.tap(find.text('Discard selected changes').last);
      await tester.pumpAndSettle();
      expect(find.text('Permanently discard changes?'), findsOneWidget);
      expect(
        find.textContaining('The changes are deleted permanently.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Discard permanently'));
      await tester.pump();
      await tester.pump();
      expect(repository.discardRequests, hasLength(4));
      expect(repository.discardRequests.last.scope, DiscardScope.rows);
      expect(repository.discardRequests.last.rowIds, ['hunk-1']);
      expect(repository.executedDiscardToken, BigInt.from(4));
      final drag = await tester.startGesture(tester.getCenter(unstagedRow));
      await tester.pump(const Duration(milliseconds: 600));
      await drag.moveTo(
        tester.getCenter(find.byKey(const ValueKey('changes-staged-list'))),
      );
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(repository.stagingRequests, hasLength(4));
      expect(repository.stagingRequests.last.side, StagingSide.unstaged);
      expect(repository.stagingRequests.last.paths.single, unstagedPath.units);
      final grip = find.descendant(
        of: unstagedRow,
        matching: find.byTooltip('Drag to the other change list'),
      );
      final immediateDrag = await tester.startGesture(tester.getCenter(grip));
      await immediateDrag.moveTo(
        tester.getCenter(find.byKey(const ValueKey('changes-staged-list'))),
      );
      await tester.pump();
      await immediateDrag.up();
      await tester.pumpAndSettle();
      expect(repository.stagingRequests, hasLength(5));
      expect(repository.stagingRequests.last.side, StagingSide.unstaged);
      await runtime.shutdown();
    },
  );

  testWidgets('Discard all reviews and executes mixed tracked and new files', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'tracked.txt'.codeUnits,
              ),
              index: ChangeKind.unmodified,
              worktree: ChangeKind.modified,
            ),
            RepositoryStatusEntry(
              kind: StatusEntryKind.untracked,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'new.txt'.codeUnits,
              ),
              index: ChangeKind.unmodified,
              worktree: ChangeKind.unmodified,
            ),
          ],
          totalEntries: BigInt.two,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Discard all'));
    await tester.pumpAndSettle();
    expect(find.text('Permanently discard changes?'), findsOneWidget);
    expect(
      find.textContaining(
        'Restore 1 tracked file and permanently delete 1 new file?',
      ),
      findsOneWidget,
    );
    expect(repository.discardRequests.map((request) => request.kind), [
      DiscardKind.clean,
      DiscardKind.discard,
    ]);
    expect(repository.executedDiscardTokens, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.executedDiscardTokens, isEmpty);
    await tester.tap(find.byTooltip('Discard all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard permanently'));
    await tester.pumpAndSettle();
    expect(repository.executedDiscardTokens, [BigInt.from(3), BigInt.from(4)]);
    await runtime.shutdown();
  });

  testWidgets('dropping several files moves them from their own side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    NativePathIdentity path(String name) => NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: name.codeUnits,
    );
    RepositoryStatusEntry entry(String name, {required bool staged}) =>
        RepositoryStatusEntry(
          kind: StatusEntryKind.ordinary,
          path: path(name),
          index: staged ? ChangeKind.modified : ChangeKind.unmodified,
          worktree: staged ? ChangeKind.unmodified : ChangeKind.modified,
        );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            entry('staged-a.txt', staged: true),
            entry('staged-b.txt', staged: true),
            entry('unstaged-a.txt', staged: false),
            entry('unstaged-b.txt', staged: false),
          ],
          totalEntries: BigInt.from(4),
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    Finder row(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byType(GitLamaFileRow),
    );
    Future<void> dragBoth(String first, String second, Key target) async {
      await tester.tap(row(first));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(row(second));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      final grip = find.descendant(
        of: row(second),
        matching: find.byTooltip('Drag to the other change list'),
      );
      final drag = await tester.startGesture(tester.getCenter(grip));
      await drag.moveTo(tester.getCenter(find.byKey(target)));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
    }

    await dragBoth(
      'unstaged-a.txt',
      'unstaged-b.txt',
      const ValueKey('changes-staged-list'),
    );
    expect(repository.stagingRequests.last.side, StagingSide.unstaged);
    expect(repository.stagingRequests.last.paths, [
      'unstaged-a.txt'.codeUnits,
      'unstaged-b.txt'.codeUnits,
    ]);

    await dragBoth(
      'staged-a.txt',
      'staged-b.txt',
      const ValueKey('changes-unstaged-list'),
    );
    expect(repository.stagingRequests.last.side, StagingSide.staged);
    expect(repository.stagingRequests.last.paths, [
      'staged-a.txt'.codeUnits,
      'staged-b.txt'.codeUnits,
    ]);
    await runtime.shutdown();
  });

  testWidgets(
    'changes use side-by-side columns with stacked persistent staging panes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final nested = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'src/lib/alpha.dart'.codeUnits,
      );
      final stagedPath = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'docs/guide.md'.codeUnits,
      );
      final nestedTest = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'src/test/alpha_test.dart'.codeUnits,
      );
      final root = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository'.codeUnits,
      );
      final repository = _WelcomeRepository(
        integrationCandidates: [
          IntegrationCandidate(
            id: 'macos-editor',
            kind: IntegrationKind.editor,
            executable: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/usr/bin/open'.codeUnits,
            ),
            launchMode: IntegrationLaunchMode.detached,
          ),
          IntegrationCandidate(
            id: 'macos-file-manager',
            kind: IntegrationKind.fileManager,
            executable: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/usr/bin/open'.codeUnits,
            ),
            launchMode: IntegrationLaunchMode.detached,
          ),
        ],
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: root,
            worktreeRoot: root,
            gitDir: root,
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            gitMajor: 2,
            gitMinor: 50,
            gitPatch: 1,
          ),
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: nested,
                index: ChangeKind.modified,
                worktree: ChangeKind.modified,
              ),
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: stagedPath,
                index: ChangeKind.modified,
                worktree: ChangeKind.unmodified,
              ),
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: nestedTest,
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.from(3),
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.settings.saveDurable(
        runtime.settings.current.copyWith(
          integrations: [
            IntegrationDefinition(
              id: 'Editor fixture',
              kind: IntegrationKind.editor,
              executable: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/editor'.codeUnits,
              ),
              arguments: const ['{file}'],
              requiresConfirmation: true,
            ),
          ],
        ),
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();

      MeridianIcon actionIcon(String tooltip) => tester.widget(
        find
            .descendant(
              of: find.byTooltip(tooltip).first,
              matching: find.byType(MeridianIcon),
            )
            .first,
      );

      expect(find.byTooltip('Stage file'), findsNothing);
      expect(find.byTooltip('Unstage file'), findsNothing);
      expect(actionIcon('Stage selected').name, 'arrow-down');
      expect(actionIcon('Stage all').name, 'stage-all');
      expect(actionIcon('Unstage selected').name, 'arrow-up');
      expect(actionIcon('Unstage all').name, 'unstage-all');
      expect(
        actionIcon('Stage selected').name,
        isNot(actionIcon('Stage all').name),
      );
      // A file row's hover action draws the toolbar's per-selection arrow.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      Future<void> hoverRow({required bool staged}) async {
        await mouse.moveTo(
          tester.getCenter(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget is GitLamaFileRow &&
                      widget.onStage != null &&
                      widget.staged == staged,
                )
                .first,
          ),
        );
        await tester.pump();
      }

      await hoverRow(staged: false);
      expect(actionIcon('Stage file').name, actionIcon('Stage selected').name);
      await hoverRow(staged: true);
      expect(
        actionIcon('Unstage file').name,
        actionIcon('Unstage selected').name,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.textContaining('partial'), findsNWidgets(2));
      expect(find.text('M'), findsWidgets);
      final fileColumn = tester.getRect(
        find.byKey(const ValueKey('changes-file-column')),
      );
      final detailColumn = tester.getRect(
        find.byKey(const ValueKey('changes-detail-column')),
      );
      final commitEditor = tester.getRect(
        find.byKey(const ValueKey('changes-commit-editor')),
      );
      final unstagedList = tester.getRect(
        find.byKey(const ValueKey('changes-unstaged-list')),
      );
      final stagedList = tester.getRect(
        find.byKey(const ValueKey('changes-staged-list')),
      );
      expect(fileColumn.right, lessThanOrEqualTo(detailColumn.left));
      expect(unstagedList.top, lessThan(stagedList.top));
      expect(commitEditor.left, fileColumn.left);
      expect(commitEditor.right, fileColumn.right);
      expect(find.byKey(const ValueKey('detail-pane')), findsNothing);
      final description = find.byKey(
        const ValueKey('commit-description-field'),
      );
      final descriptionBefore = tester.getSize(description).height;
      final commitSplitter = find.byKey(
        const ValueKey('changes-commit-splitter'),
      );
      await tester.drag(commitSplitter, const Offset(0, -80));
      await tester.pumpAndSettle();
      final resizedEditor = tester.getRect(
        find.byKey(const ValueKey('changes-commit-editor')),
      );
      final addedHeight = resizedEditor.height - commitEditor.height;
      expect(addedHeight, greaterThan(40));
      expect(resizedEditor.bottom, commitEditor.bottom);
      // A resized composer gives its height to the description.
      expect(
        tester.getSize(description).height,
        moreOrLessEquals(descriptionBefore + addedHeight, epsilon: 1),
      );
      // A double click returns the composer to its own height.
      await tester.tap(commitSplitter);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(commitSplitter);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('changes-commit-editor'))),
        commitEditor,
      );
      expect(tester.getSize(description).height, descriptionBefore);

      Finder nestedRow() => find
          .byWidgetPredicate(
            (widget) =>
                widget is GitLamaFileRow && widget.path == 'src/lib/alpha.dart',
          )
          .first;
      final nestedMenuWidget = tester.widget<GitLamaContextMenuWidget>(
        find
            .ancestor(
              of: nestedRow(),
              matching: find.byType(GitLamaContextMenuWidget),
            )
            .first,
      );
      final nestedMenu = nestedMenuWidget.testMenu() as Menu;
      nestedMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Copy path')
          .callback();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('File path copied.'), findsOneWidget);
      nestedMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Open in external editor')
          .callback();
      await tester.pumpAndSettle();
      expect(repository.integrationRequest, isNotNull);
      expect(find.text('Review exact command'), findsOneWidget);
      expect(
        String.fromCharCodes(
          repository.integrationRequest!.variables.file!.units,
        ),
        '/repository/src/lib/alpha.dart',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      nestedMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Open in Finder')
          .callback();
      await tester.pumpAndSettle();
      expect(repository.integrationRequest?.kind, IntegrationKind.fileManager);
      expect(repository.integrationRequest?.configured?.arguments, const [
        '-R',
        '{file}',
      ]);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await runtime.settings.saveDurable(
        runtime.settings.current.copyWith(integrations: const []),
      );
      nestedMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Open in external editor')
          .callback();
      await tester.pumpAndSettle();
      expect(repository.integrationRequest?.kind, IntegrationKind.editor);
      expect(repository.integrationRequest?.configured?.arguments, const [
        '-t',
        '{file}',
      ]);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(nestedRow());
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is GitLamaFileRow &&
              widget.path == 'src/test/alpha_test.dart',
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final stageSelected = _sectionAction('Stage selected');
      expect(
        tester.widget<MeridianIconButton>(stageSelected).onPressed,
        isNotNull,
      );
      await tester.tap(stageSelected);
      await tester.pumpAndSettle();
      expect(
        repository.stagingRequests.last.paths,
        unorderedEquals([nested.units, nestedTest.units]),
      );

      await tester.tap(find.byTooltip('Show files as a tree').first);
      await tester.pumpAndSettle();
      expect(runtime.settings.current.appearance.changesUnstagedMode, 'tree');
      expect(runtime.settings.current.appearance.changesStagedMode, 'list');
      expect(find.text('src'), findsOneWidget);
      // Selecting a folder selects its files and keeps it open; only its
      // chevron folds it.
      final alphaRow = find.byWidgetPredicate(
        (widget) => widget is GitLamaFileRow && widget.path == 'alpha.dart',
      );
      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(alphaRow, findsOneWidget);
      expect(tester.widget<GitLamaFileRow>(alphaRow).selected, isTrue);
      final srcToggle = find.byKey(
        const ValueKey('changes-unstaged-directory-toggle-src'),
      );
      await tester.tap(srcToggle);
      await tester.pumpAndSettle();
      expect(alphaRow, findsNothing);
      await tester.tap(srcToggle);
      await tester.pumpAndSettle();
      expect(alphaRow, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is GitLamaFileRow && widget.path == 'alpha.dart',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is GitLamaFileRow && widget.path == 'docs/guide.md',
        ),
        findsOneWidget,
      );
      final directoryMenuWidget = tester.widget<GitLamaContextMenuWidget>(
        find.ancestor(
          of: find.text('src'),
          matching: find.byType(GitLamaContextMenuWidget),
        ),
      );
      final directoryMenu = directoryMenuWidget.testMenu() as Menu;
      directoryMenu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'Stage selected')
          .callback();
      await tester.pumpAndSettle();
      expect(
        repository.stagingRequests.last.paths,
        unorderedEquals([nested.units, nestedTest.units]),
      );

      final ratioBefore = runtime.settings.current.appearance.changesSplitRatio;
      final splitter = find.byKey(const ValueKey('changes-pane-splitter'));
      expect(
        tester.widget<MeridianResizeHandle>(splitter).direction,
        Axis.vertical,
      );
      await tester.drag(splitter, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(
        runtime.settings.current.appearance.changesSplitRatio,
        greaterThan(ratioBefore),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      expect(find.text('src'), findsOneWidget);
      expect(find.text('docs/guide.md'), findsOneWidget);

      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      expect(actionIcon('Stage selected').name, 'arrow-down');
      expect(actionIcon('Unstage selected').name, 'arrow-up');
      await runtime.shutdown();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('working diff paths follow the selected side of a staged rename', () {
    void expectPaths(
      RepositoryStatusEntry entry,
      StagingSide side,
      List<int>? oldPath,
      List<int>? newPath,
    ) {
      final actual = diffPaths(entry, side);
      expect(actual.$1, oldPath);
      expect(actual.$2, newPath);
    }

    NativePathIdentity path(String name) => NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: utf8.encode(name),
    );
    final original = path('lib/background_sync/entrypoint.dart');
    final renamed = path('lib/background_sync/entrypoint_native.dart');
    final entry = RepositoryStatusEntry(
      kind: StatusEntryKind.rename,
      path: renamed,
      source: original,
      index: ChangeKind.renamed,
      worktree: ChangeKind.modified,
    );
    expectPaths(entry, StagingSide.staged, original.units, renamed.units);
    expectPaths(entry, StagingSide.unstaged, renamed.units, renamed.units);
    final replacement = RepositoryStatusEntry(
      kind: StatusEntryKind.untracked,
      path: original,
      index: ChangeKind.unmodified,
      worktree: ChangeKind.unmodified,
    );
    expectPaths(replacement, StagingSide.unstaged, null, original.units);
    final deleted = RepositoryStatusEntry(
      kind: StatusEntryKind.rename,
      path: renamed,
      source: original,
      index: ChangeKind.renamed,
      worktree: ChangeKind.deleted,
    );
    expectPaths(deleted, StagingSide.unstaged, renamed.units, null);
  });

  test('the Changes filter matches every term of a path, ignoring case', () {
    RepositoryStatusEntry entry(String path, {String? source}) =>
        RepositoryStatusEntry(
          kind: source == null
              ? StatusEntryKind.ordinary
              : StatusEntryKind.rename,
          path: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: path.codeUnits,
          ),
          source: source == null
              ? null
              : NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: source.codeUnits,
                ),
          index: ChangeKind.modified,
          worktree: ChangeKind.unmodified,
        );
    final file = entry('lib/Widgets/Button.dart');
    expect(changesFilterMatches(file, ''), isTrue);
    expect(changesFilterMatches(file, '   '), isTrue);
    expect(changesFilterMatches(file, 'button'), isTrue);
    expect(changesFilterMatches(file, 'widgets .dart'), isTrue);
    expect(changesFilterMatches(file, 'widgets test'), isFalse);
    expect(
      changesFilterMatches(
        entry('lib/new.dart', source: 'lib/old.dart'),
        'old',
      ),
      isTrue,
    );
  });

  testWidgets('the Changes filter narrows both lists and their bulk actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RepositoryStatusEntry entry(String path, {required bool staged}) =>
        RepositoryStatusEntry(
          kind: StatusEntryKind.ordinary,
          path: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: path.codeUnits,
          ),
          index: staged ? ChangeKind.modified : ChangeKind.unmodified,
          worktree: staged ? ChangeKind.unmodified : ChangeKind.modified,
        );
    final entries = [
      entry('src/one.txt', staged: false),
      entry('src/two.txt', staged: false),
      entry('docs/three.txt', staged: false),
      entry('src/four.txt', staged: true),
      entry('docs/five.txt', staged: true),
    ];
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: entries,
          totalEntries: BigInt.from(entries.length),
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    List<String> shown(String side) => [
      for (final row in tester.widgetList<GitLamaFileRow>(
        find.descendant(
          of: find.byKey(ValueKey('changes-$side-list')),
          matching: find.byType(GitLamaFileRow),
        ),
      ))
        row.path,
    ];
    Finder button(String label) => find.byWidgetPredicate(
      (widget) =>
          (widget is MeridianButton && widget.label == label) ||
          (widget is MeridianIconButton && widget.label == label),
    );

    // A selection the filter hides is dropped, so it cannot be staged
    // unseen.
    await tester.tap(find.text('docs/three.txt'));
    await tester.pump();
    final filter = find.descendant(
      of: find.byKey(const ValueKey('changes-filter')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(filter, 'SRC');
    await tester.pumpAndSettle();
    expect(shown('unstaged'), ['src/one.txt', 'src/two.txt']);
    expect(shown('staged'), ['src/four.txt']);
    expect(find.text('3 of 5'), findsOneWidget);
    expect(
      tester.widget<MeridianIconButton>(button('Stage selected')).onPressed,
      isNull,
    );

    // The file column is too narrow for the labelled button.
    expect(button('Stage all'), findsNothing);
    await tester.tap(button('Stage shown files'));
    await tester.pumpAndSettle();
    final request = repository.stagingRequests.last;
    expect(request.scope, StagingScope.files);
    expect(request.side, StagingSide.unstaged);
    expect(request.paths, [
      for (final path in ['src/one.txt', 'src/two.txt']) path.codeUnits,
    ]);

    await tester.enterText(filter, 'nothing');
    await tester.pumpAndSettle();
    expect(find.text('No matching files'), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shown('unstaged'), hasLength(3));
    expect(shown('staged'), hasLength(2));
    expect(button('Stage all'), findsOneWidget);
    expect(button('Stage shown files'), findsNothing);
    await runtime.shutdown();
  });

  for (final dirty in [false, true]) {
    testWidgets(
      'commit double-click and context action confirm detached checkout dirty=$dirty',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final commit = '1' * 40;
        final repository = _WelcomeRepository(
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            status: RepositoryStatus(
              workingTree: dirty
                  ? WorkingTreeState.dirty
                  : WorkingTreeState.clean,
              headObjectId: commit,
              branchName: 'main'.codeUnits,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: const [],
              totalEntries: BigInt.zero,
              entriesTruncated: false,
              operations: const [],
            ),
          ),
          historyRows: [
            HistoryTopologyRow(
              objectId: commit,
              parents: const [],
              refs: const [],
              lane: 0,
              shape: 0,
            ),
          ],
        );
        repository.refMutationWarnings = dirty
            ? [RefMutationWarning.dirtyCheckout]
            : [];
        final runtime = await _runtime(repository, _Picker(null));
        await runtime.repositorySessions.open('/repository');
        await tester.pumpWidget(_app(runtime));
        await tester.tap(findWorkspacePaneAction('History'));
        await tester.pumpAndSettle();
        final row = find.byKey(ValueKey('history-row-$commit'));
        // Selection happens immediately, before the second click opens the review.
        await tester.tapAt(tester.getTopLeft(row) + const Offset(160, 12));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(tester.getTopLeft(row) + const Offset(160, 12));
        await tester.pumpAndSettle();
        expect(find.textContaining('with detached HEAD?'), findsOneWidget);
        if (dirty) {
          expect(find.widgetWithText(MeridianButton, 'Stash'), findsOneWidget);
          expect(
            find.widgetWithText(MeridianButton, 'Stash & reapply'),
            findsOneWidget,
          );
          expect(find.textContaining('tracked and untracked'), findsOneWidget);
        }
        await tester.tap(find.widgetWithText(MeridianButton, 'Dismiss'));
        await tester.pumpAndSettle();
        expect(repository.executedRefMutationToken, isNull);
        expect(repository.executedStashToken, isNull);
        final graph = tester.widget<HistoryGraphView>(
          find.byType(HistoryGraphView),
        );
        final menu = nativeMenuFromActions(
          graph.onContextMenu!(graph.rowAt(graph.indexOfObjectId!(commit)!)),
        );
        menu.children
            .whereType<MenuAction>()
            .singleWhere((action) => action.title == 'Check out commit…')
            .callback();
        await tester.pumpAndSettle();
        expect(find.textContaining('with detached HEAD?'), findsOneWidget);
        await tester.tap(
          find.widgetWithText(
            MeridianButton,
            dirty ? 'Stash & reapply' : 'Check out commit',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          repository.refMutationRequest?.kind,
          RefMutationKind.checkoutCommit,
        );
        expect(repository.refMutationRequest?.target, commit);
        expect(
          dirty
              ? repository.executedStashToken
              : repository.executedRefMutationToken,
          isNotNull,
        );
        await runtime.shutdown();
      },
    );
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets('select all in each Changes file list on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entries = [
        for (final path in ['src/one.txt', 'src/two.txt', 'docs/three.txt'])
          RepositoryStatusEntry(
            kind: StatusEntryKind.ordinary,
            path: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: path.codeUnits,
            ),
            index: ChangeKind.modified,
            worktree: ChangeKind.modified,
          ),
      ];
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: entries,
            totalEntries: BigInt.from(entries.length),
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      Future<void> selectAll(String side) async {
        final list = find.byKey(ValueKey('changes-$side-list'));
        final rows = find.descendant(
          of: list,
          matching: find.byType(GitLamaFileRow),
        );
        await tester.tap(rows.first);
        await tester.pump();
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(
          tester.widgetList<GitLamaFileRow>(rows).every((row) => row.selected),
          isTrue,
        );
      }

      await selectAll('unstaged');
      expect(
        tester
            .widget<MeridianIconButton>(_sectionAction('Stage selected'))
            .onPressed,
        isNotNull,
      );
      await selectAll('staged');
      expect(
        tester
            .widgetList<GitLamaFileRow>(
              find.descendant(
                of: find.byKey(const ValueKey('changes-unstaged-list')),
                matching: find.byType(GitLamaFileRow),
              ),
            )
            .every((row) => !row.selected),
        isTrue,
      );
      await tester.tap(find.byTooltip('Show files as a tree').first);
      await tester.pumpAndSettle();
      await selectAll('unstaged');
      expect(
        tester
            .widgetList<GitLamaFileRow>(
              find.descendant(
                of: find.byKey(const ValueKey('changes-staged-list')),
                matching: find.byType(GitLamaFileRow),
              ),
            )
            .every((row) => !row.selected),
        isTrue,
      );
      final stagedRows = find.descendant(
        of: find.byKey(const ValueKey('changes-staged-list')),
        matching: find.byType(GitLamaFileRow),
      );
      await tester.tap(stagedRows.first);
      final subject = find.descendant(
        of: find.byKey(const ValueKey('commit-subject-field')),
        matching: find.byType(TextField),
      );
      await tester.enterText(subject, 'Draft');
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(
        tester
            .widgetList<GitLamaFileRow>(stagedRows)
            .where((row) => row.selected),
        hasLength(1),
      );
      expect(tester.widget<TextField>(subject).controller!.text, 'Draft');
      await runtime.shutdown();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'staged and unstaged lists retain independent scroll positions through selection and focus restoration',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entries = List.generate(
        80,
        (index) => RepositoryStatusEntry(
          kind: StatusEntryKind.ordinary,
          path: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: 'src/file-${index.toString().padLeft(2, '0')}.txt'.codeUnits,
          ),
          index: ChangeKind.modified,
          worktree: ChangeKind.modified,
        ),
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: entries,
            totalEntries: BigInt.from(entries.length),
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      const unstagedKey = ValueKey('changes-unstaged-list');
      const stagedKey = ValueKey('changes-staged-list');
      final unstaged = find.byKey(unstagedKey);
      final staged = find.byKey(stagedKey);
      final unstagedRows = find.descendant(
        of: unstaged,
        matching: find.byType(GitLamaFileRow),
      );
      final stagedRows = find.descendant(
        of: staged,
        matching: find.byType(GitLamaFileRow),
      );
      for (final label in const [
        'Stage selected',
        'Unstage selected',
        'Discard selected',
      ]) {
        final button = find.byWidgetPredicate(
          (widget) => widget is MeridianIconButton && widget.label == label,
        );
        expect(tester.widget<MeridianIconButton>(button).onPressed, isNull);
      }
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Stage selected');
      await tester.pump();
      expect(
        tester
            .widget<MeridianListRow>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is MeridianListRow &&
                    widget.title == 'Stage selected',
              ),
            )
            .enabled,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(unstagedRows.first);
      await tester.pump();
      expect(
        tester.widget<GitLamaFileRow>(unstagedRows.first).selected,
        isTrue,
      );
      expect(tester.widget<GitLamaFileRow>(stagedRows.first).selected, isFalse);
      await tester.tap(find.byTooltip('Stage selected'));
      await tester.pumpAndSettle();
      final nextRow = find
          .byWidgetPredicate(
            (widget) =>
                widget is GitLamaFileRow && widget.path == 'src/file-01.txt',
          )
          .first;
      expect(tester.widget<GitLamaFileRow>(nextRow).selected, isTrue);
      await tester.tap(stagedRows.at(1));
      await tester.pumpAndSettle();
      expect(repository.workingDiffSide, StagingSide.staged);
      expect(tester.widget<GitLamaFileRow>(stagedRows.at(1)).selected, isTrue);
      expect(
        tester.widget<GitLamaFileRow>(unstagedRows.at(1)).selected,
        isFalse,
      );
      expect(find.byKey(const ValueKey('repository-open-tab')), findsOneWidget);
      await tester.drag(unstaged, const Offset(0, -520));
      await tester.drag(staged, const Offset(0, -760));
      await tester.pumpAndSettle();
      final unstagedController = tester.widget<ListView>(unstaged).controller!;
      final stagedController = tester.widget<ListView>(staged).controller!;
      final unstagedBefore = unstagedController.offset;
      final stagedBefore = stagedController.offset;
      expect(unstagedBefore, greaterThan(0));
      expect(stagedBefore, greaterThan(unstagedBefore));

      await tester.tap(
        find
            .descendant(of: unstaged, matching: find.byType(GitLamaFileRow))
            .hitTestable()
            .first,
      );
      await tester.pump();
      expect(unstagedController.offset, unstagedBefore);
      expect(stagedController.offset, stagedBefore);

      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(unstagedController.offset, unstagedBefore);
      expect(stagedController.offset, stagedBefore);

      await runtime.shutdown();
    },
  );

  testWidgets('a highlighted file keeps its diff when Changes is chosen again, '
      'and a diff without rows says so', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'tracked.txt'.codeUnits,
              ),
              index: ChangeKind.unmodified,
              worktree: ChangeKind.modified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.text('tracked.txt').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('working-diff-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('working-diff-empty')), findsOneWidget);
    expect(find.text('This file has no line changes to show.'), findsOneWidget);

    // Find searches the diff Changes shows, selecting the previous query.
    final diffSearch = find.byKey(const Key('working-diff-search'));
    await tester.enterText(diffSearch, 'needle');
    await tester.tap(find.text('tracked.txt').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(diffSearch).focusNode!.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(diffSearch);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
    expect(
      runtime.repositorySessions.workspace.activeTab!.navigation.pane,
      WorkspacePane.changes,
    );

    // Choosing Changes again clears the navigation selection; the row stays
    // highlighted, so its diff must stay too.
    await tester.tap(
      find.descendant(
        of: find.byType(WorkspaceSidebar),
        matching: find.text('Changes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      runtime
          .repositorySessions
          .workspace
          .activeTab!
          .navigation
          .selectedIdentity,
      isNull,
    );
    expect(find.text('Select an item to inspect it.'), findsNothing);
    expect(find.byKey(const Key('working-diff-search')), findsOneWidget);
    await runtime.shutdown();
  });

  for (final slow in [true, false]) {
    testWidgets(
      slow
          ? 'a slow status scan offers to speed it up and enables it'
          : 'a fast status scan offers nothing',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _WelcomeRepository(
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            status: RepositoryStatus(
              workingTree: WorkingTreeState.clean,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: const [],
              totalEntries: BigInt.zero,
              entriesTruncated: false,
              operations: const [],
            ),
          ),
          acceleration: StatusAcceleration(
            untrackedCache: false,
            fsmonitor: false,
            fsmonitorAvailable: true,
            lastScan: Duration(milliseconds: slow ? 7400 : 400),
          ),
        );
        final runtime = await _runtime(repository, _Picker(null));
        await runtime.repositorySessions.open('/repository');
        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        final offer = find.byKey(const ValueKey('status-acceleration-offer'));
        if (!slow) {
          expect(offer, findsNothing);
          await runtime.shutdown();
          return;
        }
        expect(offer, findsOneWidget);
        expect(
          find.textContaining('Git took 7 s to check this repository'),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(of: offer, matching: find.text('Speed up')),
        );
        await tester.pumpAndSettle();
        expect(repository.accelerationEnables, 1);
        expect(offer, findsNothing);
        await runtime.shutdown();
      },
    );
  }

  testWidgets('the Git settings show and enable the status accelerators', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: const [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
      acceleration: const StatusAcceleration(
        untrackedCache: false,
        fsmonitor: false,
        fsmonitorAvailable: true,
        lastScan: Duration(milliseconds: 7400),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final offer = find.byKey(const ValueKey('status-acceleration-offer'));
    expect(offer, findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-category-git')));
    await tester.pumpAndSettle();

    final section = find.byKey(const Key('settings-status-acceleration'));
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    expect(section, findsOneWidget);
    String state(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
    expect(state('settings-untracked-cache'), 'Off');
    expect(state('settings-fsmonitor'), 'Off');
    expect(
      find.text('The last check for changes took about 7 s.'),
      findsOneWidget,
    );

    final enable = find.byKey(const Key('settings-status-acceleration-enable'));
    await tester.ensureVisible(enable);
    await tester.tap(enable);
    await tester.pumpAndSettle();
    expect(repository.accelerationEnables, 1);
    expect(state('settings-untracked-cache'), 'On');
    expect(state('settings-fsmonitor'), 'On');
    expect(enable, findsNothing);
    expect(find.text('Everything available is on.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
    expect(offer, findsNothing);
    await runtime.shutdown();
  });

  testWidgets(
    'a working diff Git has not answered shows a wait and keeps loading',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'tracked.txt'.codeUnits,
      );
      final answer = Completer<DiffPage>();
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: path,
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        workingDiffTimeouts: 2,
        workingDiffBarriers: [Completer(), Completer(), answer],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      await tester.tap(find.text('tracked.txt').first);
      await tester.pump();
      await tester.pump();
      expect(find.text('Waiting for Git…'), findsOneWidget);
      expect(find.text('The file diff could not be loaded.'), findsNothing);
      expect(repository.workingDiffCalls, 3);

      answer.complete(
        DiffPage(
          requestId: BigInt.from(5),
          layout: DiffViewLayout.unified,
          totalRows: 1,
          offset: 0,
          rows: const [
            DiffDisplayRow(
              stableId: 'answered',
              kind: DiffRowKind.addition,
              text: [97, 110, 115, 119, 101, 114, 101, 100],
              newLine: 1,
              selectable: true,
            ),
          ],
          payloadBytes: 8,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Git…'), findsNothing);
      expect(find.byType(DiffView), findsOneWidget);
      await runtime.shutdown();
    },
  );

  testWidgets(
    'working diff search highlights and navigates matches from the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'tracked.txt'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: path,
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        workingDiffResult: DiffPage(
          requestId: BigInt.from(91),
          layout: DiffViewLayout.unified,
          totalRows: 1026,
          offset: 0,
          rows: [
            for (var index = 0; index < 1024; index += 1)
              DiffDisplayRow(
                stableId: index == 1 ? 'match-1' : 'row-$index',
                kind: index == 0
                    ? DiffRowKind.hunk
                    : index == 1
                    ? DiffRowKind.deletion
                    : DiffRowKind.context,
                selectable: index == 1,
                text: index == 0
                    ? const [64, 64, 32, 45, 49, 32, 43, 49, 32, 64, 64]
                    : index == 1
                    ? const [110, 101, 101, 100, 108, 101]
                    : const [99, 111, 110, 116, 101, 120, 116],
                oldLine: index + 1,
              ),
          ],
          payloadBytes: 8192,
        ),
        workingDiffPages: {
          1024: DiffPage(
            requestId: BigInt.from(91),
            layout: DiffViewLayout.unified,
            totalRows: 1026,
            offset: 1024,
            rows: const [
              DiffDisplayRow(
                stableId: 'row-1024',
                kind: DiffRowKind.context,
                text: [99, 111, 110, 116, 101, 120, 116],
                oldLine: 1025,
              ),
              DiffDisplayRow(
                stableId: 'match-2',
                kind: DiffRowKind.addition,
                text: [110, 101, 101, 100, 108, 101],
                newLine: 1025,
              ),
            ],
            payloadBytes: 32,
          ),
        },
        diffSearchMatches: const [1, 1025],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      await tester.tap(find.text('tracked.txt').first);
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('working-diff-search'));
      expect(search, findsOneWidget);
      expect(
        tester.getSize(
          find
              .ancestor(of: search, matching: find.byType(MeridianTextField))
              .first,
        ),
        const Size(MeridianLayout.findFieldWidth, MeridianSize.controlSm),
      );
      expect(
        tester.widget<TextField>(search).style?.fontSize,
        gitlamaText.caption.fontSize,
      );
      final toolbarRect = tester.getRect(
        find.byKey(const ValueKey('working-diff-toolbar-surface')),
      );
      final detailRect = tester.getRect(
        find.byKey(const ValueKey('changes-detail-column')),
      );
      expect(toolbarRect.left, closeTo(detailRect.left, 0.01));
      expect(toolbarRect.right, closeTo(detailRect.right, 0.01));
      // The section header's strip and its hairline.
      expect(
        toolbarRect.height,
        MeridianSize.islandHeader + MeridianLayout.hairline,
      );
      expect(tester.getCenter(search).dy, closeTo(toolbarRect.center.dy, 1));
      await tester.tapAt(_diffGutter(tester, 'match-1'));
      await tester.pump();
      expect(
        tester.widget<DiffView>(find.byType(DiffView)).selectedIds,
        contains('match-1'),
      );
      final workingToolbar = find.byKey(
        const ValueKey('working-diff-toolbar-surface'),
      );
      for (final tooltip in [
        'Side-by-side diff',
        'Context lines',
        'Cycle whitespace comparison',
        'Wrap long lines',
        'Show plus and minus indicators',
        'Show diff minimap',
        'Text encoding',
      ]) {
        expect(
          find.descendant(
            of: workingToolbar,
            matching: find.byTooltip(tooltip),
          ),
          findsOneWidget,
        );
      }
      // Create patch stays pinned while the viewing actions scroll.
      expect(
        find.descendant(
          of: workingToolbar,
          matching: find.byTooltip('Create patch from this diff'),
        ),
        findsOneWidget,
      );
      final layoutToggle = find.descendant(
        of: workingToolbar,
        matching: find.byTooltip('Side-by-side diff'),
      );
      await tester.ensureVisible(layoutToggle);
      await tester.pumpAndSettle();
      await tester.tap(layoutToggle);
      await tester.pumpAndSettle();
      expect(repository.workingDiffLayout, DiffViewLayout.sideBySide);
      expect(repository.workingDiffContextLines, 3);
      expect(repository.workingDiffWhitespace, DiffWhitespace.preserve);
      // Every diff view shares the stored choice.
      expect(
        runtime.settings.current.appearance.diffView.layout,
        DiffViewLayout.sideBySide,
      );
      final wrapToggle = find.descendant(
        of: workingToolbar,
        matching: find.byTooltip('Wrap long lines'),
      );
      await tester.ensureVisible(wrapToggle);
      await tester.pumpAndSettle();
      await tester.tap(wrapToggle);
      await tester.pumpAndSettle();
      expect(runtime.settings.current.appearance.diffView.wrap, isTrue);
      expect(tester.widget<DiffView>(find.byType(DiffView)).wrap, isTrue);
      expect(
        tester.widget<DiffView>(find.byType(DiffView)).selectedIds,
        contains('match-1'),
      );
      await tester.tap(find.byKey(const ValueKey('diff-more-row-0')));
      await tester.pumpAndSettle();
      expect(repository.workingDiffContextLines, 6);
      // More context widens this diff only.
      expect(runtime.settings.current.appearance.diffView.contextLines, 3);
      final whitespaceToggle = find.descendant(
        of: workingToolbar,
        matching: find.byTooltip('Cycle whitespace comparison'),
      );
      await tester.ensureVisible(whitespaceToggle);
      await tester.pumpAndSettle();
      await tester.tap(whitespaceToggle);
      await tester.pumpAndSettle();
      expect(repository.workingDiffWhitespace, DiffWhitespace.ignoreAll);
      expect(
        runtime.settings.current.appearance.diffView.whitespace,
        DiffWhitespace.ignoreAll,
      );
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('../build/evidence/ui-review/working-diff.png'),
        );
      }
      await tester.enterText(search, 'needle');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repository.diffSearchQuery, 'needle'.codeUnits);
      expect(repository.diffSearchCaseSensitive, isFalse);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-row-match-1')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-row-match-2')), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      // The counter disappears with the query.
      expect(find.text('1 of 2'), findsNothing);
      expect(find.text('No matches'), findsNothing);
      expect(tester.widget<TextField>(search).controller?.text, isEmpty);
      await runtime.shutdown();
    },
  );

  testWidgets('staged new file opens its index diff', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: 'staged-new.txt'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: path,
              index: ChangeKind.added,
              worktree: ChangeKind.unmodified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
      workingDiffResult: DiffPage(
        requestId: BigInt.from(93),
        layout: DiffViewLayout.unified,
        totalRows: 1,
        offset: 0,
        rows: const [
          DiffDisplayRow(
            stableId: 'staged-new-line',
            kind: DiffRowKind.addition,
            text: [110, 101, 119],
            newLine: 1,
          ),
        ],
        payloadBytes: 3,
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.text('staged-new.txt').first);
    await tester.pumpAndSettle();

    expect(repository.workingDiffSide, StagingSide.staged);
    expect(repository.workingDiffOldPath, isNull);
    expect(repository.workingDiffNewPath, 'staged-new.txt'.codeUnits);
    expect(repository.workingDiffMaximumRows, 512);
    expect(find.text('The file diff could not be loaded.'), findsNothing);
    expect(
      find.byKey(const ValueKey('diff-row-staged-new-line')),
      findsOneWidget,
    );
    await runtime.shutdown();
  });

  testWidgets('staged image change shows its comparison inline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: 'logo.png'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: path,
              index: ChangeKind.modified,
              worktree: ChangeKind.unmodified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
      workingDiffResult: DiffPage(
        requestId: BigInt.from(94),
        layout: DiffViewLayout.unified,
        totalRows: 1,
        offset: 0,
        rows: [
          DiffDisplayRow(
            stableId: 'staged-image',
            kind: DiffRowKind.image,
            text: const [],
            oldPath: 'logo.png'.codeUnits,
            newPath: 'logo.png'.codeUnits,
          ),
        ],
        payloadBytes: 16,
      ),
      imageDiffResult: const ImageDiffContent(
        old: DecodedImageContent(width: 1, height: 1, rgba: [255, 0, 0, 255]),
        newImage: DecodedImageContent(
          width: 1,
          height: 1,
          rgba: [0, 0, 255, 255],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.text('logo.png').first);
    await tester.pumpAndSettle();

    expect(repository.workingImageDiffRequests, hasLength(1));
    final request = repository.workingImageDiffRequests.single;
    expect(request.$1, StagingSide.staged);
    expect(request.$2, 'logo.png'.codeUnits);
    expect(request.$3, 'logo.png'.codeUnits);
    expect(find.byType(ImageDiffView), findsOneWidget);
    expect(find.text('Before: 1 × 1 px'), findsOneWidget);
    expect(find.text('After: 1 × 1 px'), findsOneWidget);
    expect(find.byType(DiffView), findsNothing);
    await runtime.shutdown();
  });

  testWidgets('working detail coalesces selection reloads', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = Completer<DiffPage>();
    final second = Completer<DiffPage>();
    RepositoryStatusEntry stagedNew(String path) => RepositoryStatusEntry(
      kind: StatusEntryKind.ordinary,
      path: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: path.codeUnits,
      ),
      index: ChangeKind.added,
      worktree: ChangeKind.unmodified,
    );
    DiffPage page(int requestId, String stableId) => DiffPage(
      requestId: BigInt.from(requestId),
      layout: DiffViewLayout.unified,
      totalRows: 1,
      offset: 0,
      rows: [
        DiffDisplayRow(
          stableId: stableId,
          kind: DiffRowKind.addition,
          text: const [110, 101, 119],
          newLine: 1,
        ),
      ],
      payloadBytes: 3,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [stagedNew('alpha.txt'), stagedNew('beta.txt')],
          totalEntries: BigInt.two,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
      workingDiffBarriers: [first, second],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.text('alpha.txt').first);
    await tester.pump();
    expect(repository.workingDiffCalls, 1);
    await tester.tap(find.text('beta.txt').first);
    await tester.pump();
    expect(repository.workingDiffCalls, 1);

    first.complete(page(101, 'alpha-line'));
    await tester.pump();
    await tester.pump();
    expect(repository.workingDiffCalls, 2);
    second.complete(page(102, 'beta-line'));
    await tester.pumpAndSettle();

    expect(repository.maximumWorkingDiffConcurrent, 1);
    expect(repository.workingDiffRequests.last.$3, 'beta.txt'.codeUnits);
    expect(find.byKey(const ValueKey('diff-row-beta-line')), findsOneWidget);
    expect(find.text('The file diff could not be loaded.'), findsNothing);
    await runtime.shutdown();
  });

  testWidgets(
    'a status change reloads the working diff in place and keeps selection',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reload = Completer<DiffPage>();
      RepositoryStatusEntry stagedNew(String path) => RepositoryStatusEntry(
        kind: StatusEntryKind.ordinary,
        path: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: path.codeUnits,
        ),
        index: ChangeKind.added,
        worktree: ChangeKind.unmodified,
      );
      RepositoryStatus status(List<String> paths) => RepositoryStatus(
        workingTree: WorkingTreeState.dirty,
        ahead: BigInt.zero,
        behind: BigInt.zero,
        entries: [for (final path in paths) stagedNew(path)],
        totalEntries: BigInt.from(paths.length),
        entriesTruncated: false,
        operations: const [],
      );
      DiffPage page(int requestId) => DiffPage(
        requestId: BigInt.from(requestId),
        layout: DiffViewLayout.unified,
        totalRows: 2,
        offset: 0,
        rows: const [
          DiffDisplayRow(
            stableId: 'alpha-1',
            kind: DiffRowKind.addition,
            text: [111, 110, 101],
            newLine: 1,
            selectable: true,
          ),
          DiffDisplayRow(
            stableId: 'alpha-2',
            kind: DiffRowKind.addition,
            text: [116, 119, 111],
            newLine: 2,
            selectable: true,
          ),
        ],
        payloadBytes: 6,
      );
      final first = Completer<DiffPage>()..complete(page(101));
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: status(['alpha.txt']),
        ),
        workingDiffBarriers: [first, reload],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alpha.txt').first);
      await tester.pumpAndSettle();
      await tester.tapAt(_diffGutter(tester, 'alpha-2'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('diff-selection-stage')),
        findsOneWidget,
      );

      // Another file changes: a new status arrives.
      repository.pendingEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: RepositorySnapshot(
            revision: BigInt.two,
            phase: RepositoryPhase.ready,
            status: status(['alpha.txt', 'beta.txt']),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(repository.workingDiffCalls, 2);
      // While the reload runs, the diff stays on screen.
      expect(find.byKey(const ValueKey('diff-row-alpha-1')), findsOneWidget);
      expect(find.byType(MeridianProgressBar), findsNothing);

      reload.complete(page(102));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diff-row-alpha-1')), findsOneWidget);
      expect(tester.widget<DiffView>(find.byType(DiffView)).selectedIds, {
        'alpha-2',
      });
      expect(
        find.byKey(const ValueKey('diff-selection-stage')),
        findsOneWidget,
      );
      await runtime.shutdown();
    },
  );

  testWidgets('commit diff search shares F3 navigation and Escape clearing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: commit,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      commitDiffResult: DiffPage(
        requestId: BigInt.from(92),
        layout: DiffViewLayout.unified,
        totalRows: 3,
        offset: 0,
        rows: const [
          DiffDisplayRow(
            stableId: 'commit-match-1',
            kind: DiffRowKind.deletion,
            text: [110, 101, 101, 100, 108, 101],
            oldLine: 1,
          ),
          DiffDisplayRow(
            stableId: 'commit-context',
            kind: DiffRowKind.context,
            text: [99, 111, 110, 116, 101, 120, 116],
            oldLine: 2,
            newLine: 1,
          ),
          DiffDisplayRow(
            stableId: 'commit-match-2',
            kind: DiffRowKind.addition,
            text: [110, 101, 101, 100, 108, 101],
            newLine: 2,
          ),
        ],
        payloadBytes: 32,
      ),
      diffSearchMatches: const [0, 2],
    );
    await tester.binding.setSurfaceSize(const Size(1920, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await runtime.repositorySessions.history.select(commit);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('history-query')))
          .style
          ?.fontSize,
      gitlamaText.caption.fontSize,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('commit-diff-search')))
          .style
          ?.fontSize,
      gitlamaText.caption.fontSize!,
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('commit-diff-search')),
                  matching: find.byType(MeridianTextField),
                )
                .first,
          )
          .width,
      inInclusiveRange(100, MeridianLayout.findFieldWidth),
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('history-query')),
                  matching: find.byType(MeridianTextField),
                )
                .first,
          )
          .width,
      greaterThanOrEqualTo(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('commit-diff-search')),
                    matching: find.byType(MeridianTextField),
                  )
                  .first,
            )
            .width,
      ),
    );
    final detailWidth = tester
        .getSize(find.byKey(const ValueKey('detail-pane')))
        .width;
    final filesWidth = tester
        .getSize(find.byKey(const ValueKey('commit-changed-files')))
        .width;
    final diffWidth = tester
        .getSize(find.byKey(const ValueKey('commit-diff-toolbar-surface')))
        .width;
    final commitToolbarRect = tester.getRect(
      find.byKey(const ValueKey('commit-diff-toolbar-surface')),
    );
    expect(
      commitToolbarRect.height,
      MeridianSize.islandHeader + MeridianLayout.hairline,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('commit-diff-search'))).dy,
      closeTo(commitToolbarRect.center.dy, 1),
    );
    expect(
      filesWidth + MeridianSpace.space3 + diffWidth,
      closeTo(detailWidth, 0.01),
    );
    expect(
      tester
              .getTopLeft(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('commit-diff-search')),
                      matching: find.byType(MeridianTextField),
                    )
                    .first,
              )
              .dx -
          tester
              .getTopLeft(
                find.byKey(const ValueKey('commit-diff-toolbar-surface')),
              )
              .dx,
      // The path column takes 23% of the toolbar, between 64 and 180 px.
      inInclusiveRange(
        MeridianSpace.space5 + 64 + MeridianSpace.space4,
        MeridianSpace.space5 + 180 + MeridianSpace.space4,
      ),
    );

    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('../build/evidence/ui-review/history-diff.png'),
      );
    }

    final sidebarWidthBefore = runtime.settings.current.appearance.sidebarWidth;
    await tester.drag(
      find.byKey(const ValueKey('sidebar-pane-splitter')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(
      runtime.settings.current.appearance.sidebarWidth,
      greaterThan(sidebarWidthBefore),
    );

    // History always sits above the details, with the full width.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('detail-pane'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const ValueKey('history-query'))).dy,
      ),
    );
    final detailIslandHeightBefore = tester
        .getSize(find.byKey(const ValueKey('detail-pane')))
        .height;
    await tester.drag(
      find.byKey(const ValueKey('detail-pane-splitter')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('detail-pane'))).height,
      greaterThan(detailIslandHeightBefore),
    );
    final filesWidthBefore = tester
        .getSize(find.byKey(const ValueKey('commit-changed-files')))
        .width;
    await tester.drag(
      find.byKey(const ValueKey('commit-files-splitter')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('commit-changed-files'))).width,
      greaterThan(filesWidthBefore),
    );

    // Find reaches History's search until a diff holds the focus; then it
    // searches that diff.
    bool focused(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).focusNode!.hasFocus;
    Future<void> pressFind() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await pressFind();
    expect(focused('history-query'), isTrue);
    expect(focused('commit-diff-search'), isFalse);
    Focus.of(tester.element(find.byType(DiffView))).requestFocus();
    await tester.pump();
    await pressFind();
    expect(focused('commit-diff-search'), isTrue);
    expect(focused('history-query'), isFalse);

    await tester.binding.setSurfaceSize(const Size(800, 900));
    await tester.pumpAndSettle();
    final detailHeightBefore = tester
        .getSize(find.byKey(const ValueKey('detail-pane')))
        .height;
    await tester.drag(
      find.byKey(const ValueKey('detail-pane-splitter')),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('detail-pane'))).height,
      greaterThan(detailHeightBefore),
    );

    expect(find.byKey(const ValueKey('history-query')), findsOneWidget);
    expect(find.byKey(const ValueKey('commit-diff-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('commit-changed-files')), findsOneWidget);
    expect(find.byKey(const ValueKey('commit-files-splitter')), findsOneWidget);
    final compactSplitter = tester.widget<MeridianResizeHandle>(
      find.byKey(const ValueKey('detail-pane-splitter')),
    );
    expect(compactSplitter.direction, Axis.vertical);
    final compactHeightBefore = tester
        .getSize(find.byKey(const ValueKey('detail-pane')))
        .height;
    await tester.drag(
      find.byKey(const ValueKey('detail-pane-splitter')),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('detail-pane'))).height,
      greaterThan(compactHeightBefore),
    );
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('commit-diff-toolbar-surface')),
              matching: find.byTooltip('Previous match'),
            ),
          )
          .height,
      MeridianSize.controlSm,
    );

    final search = find.widgetWithText(TextField, 'Find in diff');
    await tester.enterText(search, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // The counter disappears with the query.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('commit-diff-toolbar-surface')),
        matching: find.text('2 of 2'),
      ),
      findsNothing,
    );
    expect(tester.widget<TextField>(search).controller?.text, isEmpty);
    await runtime.shutdown();
  });

  for (final scenario in [
    'checkbox',
    'command',
    'cancel',
    'subject edit',
    'description edit',
    'existing description',
    'failure and retry',
    'dispose',
  ]) {
    testWidgets('amend waits for HEAD message: $scenario', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/repository/.git'.codeUnits,
            ),
            worktreeRoot: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/repository'.codeUnits,
            ),
            gitDir: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/repository/.git'.codeUnits,
            ),
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            headObjectId: 'head-commit',
            gitMajor: 2,
            gitMinor: 50,
            gitPatch: 1,
          ),
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            branchName: 'main'.codeUnits,
            headObjectId: 'head-commit',
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        commitToolsResult: const CommitTools(
          recent: [
            RecentCommitMessage(
              objectId: 'other-commit',
              subject: 'unrelated subject',
              description: 'unrelated body',
            ),
            RecentCommitMessage(
              objectId: 'head-commit',
              subject: 'HEAD subject',
              description: 'HEAD body',
            ),
          ],
        ),
      );
      final pending = Completer<CommitTools>();
      repository.commitToolsBarriers.add(pending);
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      final tab = runtime.repositorySessions.workspace.activeTab!;
      runtime.repositorySessions.updateNavigation(
        tab.id,
        tab.navigation.copyWith(pane: WorkspacePane.changes),
      );
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      final subject = find.descendant(
        of: find.byKey(const ValueKey('commit-subject-field')),
        matching: find.byType(TextField),
      );
      final description = find.descendant(
        of: find.byKey(const ValueKey('commit-description-field')),
        matching: find.byType(TextField),
      );
      String subjectText() =>
          tester.widget<TextField>(subject).controller!.text;
      String descriptionText() =>
          tester.widget<TextField>(description).controller!.text;
      if (scenario == 'existing description') {
        await tester.enterText(description, 'keep existing body');
      }
      if (scenario == 'command') {
        tester
            .state<CommitEditorState>(find.byType(CommitEditor))
            .prepareAmend();
      } else {
        await tester.tap(find.text('Amend'));
      }
      await tester.pump();
      expect(subjectText(), isEmpty);
      expect(repository.commitToolsCalls, 1);
      if (scenario == 'cancel') {
        await tester.tap(find.text('Amend'));
      } else if (scenario == 'subject edit') {
        await tester.enterText(subject, 'my subject');
      } else if (scenario == 'description edit') {
        await tester.enterText(description, 'my body');
      } else if (scenario == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      }
      if (scenario == 'failure and retry') {
        pending.completeError(
          const RepositorySessionException(
            RepositoryFailure(RepositoryFailureCode.read),
          ),
        );
        await tester.pumpAndSettle();
        expect(subjectText(), isEmpty);
        expect(
          find.text(
            'Could not load the last commit message. Turn Amend off and on to retry, or enter a message.',
          ),
          findsNWidgets(2),
        );
        await tester.tap(find.byKey(const ValueKey('operation-failure-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Amend'));
        await tester.pump();
        await tester.tap(find.text('Amend'));
      } else {
        pending.complete(repository.commitToolsResult);
      }
      await tester.pumpAndSettle();
      if (scenario == 'checkbox' ||
          scenario == 'command' ||
          scenario == 'failure and retry') {
        expect(subjectText(), 'HEAD subject');
        expect(descriptionText(), 'HEAD body');
        expect(
          runtime.repositorySessions.activeCommitDraft.subject,
          'HEAD subject',
        );
        expect(
          runtime.repositorySessions.activeCommitDraft.description,
          'HEAD body',
        );
      } else if (scenario != 'dispose') {
        expect(subjectText(), scenario == 'subject edit' ? 'my subject' : '');
        expect(descriptionText(), switch (scenario) {
          'description edit' => 'my body',
          'existing description' => 'keep existing body',
          _ => '',
        });
      }
      expect(repository.commitRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await runtime.shutdown();
    });
  }

  testWidgets('amend ignores tools from a superseded HEAD load', (
    tester,
  ) async {
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: root,
          worktreeRoot: root,
          gitDir: root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          headObjectId: 'old-head',
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
      ),
    );
    final oldLoad = Completer<CommitTools>();
    final newLoad = Completer<CommitTools>();
    repository.commitToolsBarriers.addAll([oldLoad, newLoad]);
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    Widget editor(String head) => MaterialApp(
      builder: (context, child) => StatusNotificationScope(child: child!),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: CommitEditor(
          repositories: runtime.repositorySessions,
          hosting: null,
          hostingResources: const HostingResources(),
          hostingResourcesStale: false,
          suggestionPaths: const [],
          shortcut: null,
          branchName: 'main'.codeUnits,
          headObjectId: head,
          stagedCount: 0,
          onFailureVisibilityChanged: (_) {},
          onPush: () {},
        ),
      ),
    );
    await tester.pumpWidget(editor('old-head'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amend'));
    await tester.pumpWidget(editor('new-head'));
    await tester.pumpAndSettle();
    expect(repository.commitToolsCalls, 2);
    oldLoad.complete(
      const CommitTools(
        recent: [
          RecentCommitMessage(
            objectId: 'old-head',
            subject: 'old subject',
            description: 'old body',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(runtime.repositorySessions.activeCommitDraft.subject, isEmpty);
    expect(find.text('old subject'), findsNothing);
    newLoad.complete(
      const CommitTools(
        recent: [
          RecentCommitMessage(
            objectId: 'new-head',
            subject: 'new subject',
            description: 'new body',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('new subject'), findsOneWidget);
    expect(find.text('new body'), findsOneWidget);
    expect(runtime.repositorySessions.activeCommitDraft.subject, 'new subject');
    expect(
      runtime.repositorySessions.activeCommitDraft.description,
      'new body',
    );
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets(
    'embedded commit editor applies tools and confirms published amend',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: root,
            worktreeRoot: root,
            gitDir: root,
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            headObjectId: '1111111111111111111111111111111111111111',
            gitMajor: 2,
            gitMinor: 50,
            gitPatch: 1,
          ),
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            branchName: 'main'.codeUnits,
            headObjectId: '1111111111111111111111111111111111111111',
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: 'tracked.txt'.codeUnits,
                ),
                index: ChangeKind.modified,
                worktree: ChangeKind.unmodified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        commitToolsResult: const CommitTools(
          template: 'template subject\n\ntemplate body\n',
          recent: [
            RecentCommitMessage(
              objectId: '1111111111111111111111111111111111111111',
              subject: 'recent subject',
              description: 'recent body',
            ),
          ],
        ),
        commitWarnings: const [CommitWarning.publishedAmend],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();

      final subjectFinder = find.descendant(
        of: find.byKey(const ValueKey('commit-subject-field')),
        matching: find.byType(TextField),
      );
      final descriptionFinder = find.descendant(
        of: find.byKey(const ValueKey('commit-description-field')),
        matching: find.byType(TextField),
      );
      final subjectField = tester.widget<TextField>(subjectFinder);
      final descriptionField = tester.widget<TextField>(descriptionFinder);
      expect(subjectField.style?.fontSize, gitlamaText.bodyStrong.fontSize);
      expect(descriptionField.style?.fontSize, gitlamaText.body.fontSize);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('commit-subject-field')))
            .height,
        greaterThanOrEqualTo(MeridianSize.control),
      );
      expect(subjectField.decoration?.hintText, 'Commit subject');
      expect(subjectField.decoration?.isCollapsed, isTrue);
      expect(subjectField.decoration?.border, InputBorder.none);
      expect(descriptionField.decoration?.hintText, 'Description');
      expect(descriptionField.expands, isFalse);
      expect(
        descriptionField.minLines,
        GitLamaLayout.composerDescriptionMinLines,
      );
      expect(
        descriptionField.maxLines,
        GitLamaLayout.composerDescriptionMaxLines,
      );
      final editorBounds = tester.getRect(
        find.byKey(const ValueKey('changes-commit-editor')),
      );
      final footerBounds = tester.getRect(
        find.byKey(const ValueKey('commit-push-menu')),
      );
      expect(editorBounds.bottom - footerBounds.bottom, lessThanOrEqualTo(12));
      expect(
        footerBounds.top -
            tester
                .getRect(find.byKey(const ValueKey('commit-description-field')))
                .bottom,
        inInclusiveRange(32, 52),
      );
      expect(descriptionField.keyboardType, TextInputType.multiline);
      expect(subjectField.textInputAction, TextInputAction.next);
      expect(descriptionField.textInputAction, TextInputAction.newline);
      expect(tester.getSize(subjectFinder).height, lessThanOrEqualTo(36));
      final composer = find.byType(GitLamaComposer);
      expect(composer, findsOneWidget);
      final composerScroll = find.descendant(
        of: composer,
        matching: find.byType(Scrollable),
      );
      expect(
        tester
            .state<ScrollableState>(composerScroll.first)
            .position
            .maxScrollExtent,
        0,
        reason: 'the default composer height fits its content',
      );
      const focusRingOutset =
          MeridianLayout.focusRingOffset + MeridianLayout.focusRingWidth;
      final composerViewport = tester.getRect(composerScroll.first);
      final subjectBounds = tester.getRect(
        find.byKey(const ValueKey('commit-subject-field')),
      );
      expect(
        subjectBounds.top - composerViewport.top,
        greaterThanOrEqualTo(focusRingOutset),
      );
      expect(
        composerViewport.right - subjectBounds.right,
        greaterThanOrEqualTo(focusRingOutset),
      );
      final composerSurface = tester.widget<DecoratedBox>(
        find
            .descendant(of: composer, matching: find.byType(DecoratedBox))
            .first,
      );
      final composerColors = MeridianTheme.of(tester.element(composer)).colors;
      expect(
        (composerSurface.decoration as BoxDecoration).color,
        composerColors.paneAlt,
      );
      for (final (length, color) in [
        (50, composerColors.inkMuted),
        (51, composerColors.warning),
        (73, composerColors.danger),
      ]) {
        await tester.enterText(subjectFinder, 'a' * length);
        await tester.pump();
        if (length > GitLamaLayout.subjectLimit) {
          expect(
            tester
                .widget<Transform>(
                  find.byKey(const ValueKey('commit-subject-counter')),
                )
                .transform
                .entry(0, 3),
            greaterThan(0),
          );
        }
        if (length > GitLamaLayout.subjectGuide) {
          await tester.pump(MeridianDurations.select);
        }
        expect(
          tester.widget<Text>(find.text('$length/50')).style?.color,
          color,
        );
      }
      expect(
        tester.getSize(descriptionFinder).height,
        greaterThan(tester.getSize(subjectFinder).height),
      );
      final beforeWarning = tester.getRect(descriptionFinder);
      final subjectHeight = tester.getSize(subjectFinder).height;
      await tester.enterText(subjectFinder, 'title ');
      await tester.pump();
      expect(tester.getRect(descriptionFinder), beforeWarning);
      expect(tester.getSize(subjectFinder).height, subjectHeight);
      expect(
        find.byTooltip('The subject ends with whitespace.'),
        findsOneWidget,
      );
      await tester.enterText(descriptionFinder, 'first line\nsecond line');
      expect(descriptionField.controller?.text, 'first line\nsecond line');
      await tester.tap(subjectFinder);
      await tester.enterText(subjectFinder, 'fix');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'fix design',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      await tester.pump();
      expect(subjectField.controller?.text, 'fix design');
      expect(repository.stagingRequests, isEmpty);
      await tester.tap(descriptionFinder);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'first line second line',
          selection: TextSelection.collapsed(offset: 22),
        ),
      );
      await tester.pump();
      expect(descriptionField.controller?.text, 'first line second line');
      expect(repository.stagingRequests, isEmpty);

      final commitButton = findComposerCommitButton();
      final commitMenu = find.byKey(const ValueKey('commit-push-menu'));
      // The shortcut uses the platform's key glyphs and shows only while
      // its modifier is held.
      final commitWidget = tester.widget<MeridianButton>(commitButton);
      expect(
        commitWidget.shortcut,
        defaultTargetPlatform == TargetPlatform.macOS
            ? ['⌘', '↵']
            : ['Ctrl', 'Enter'],
      );
      expect(commitWidget.shortcutReveal, MeridianKbdReveal.whileModifierHeld);
      expect(commitWidget.animateLabel, isTrue);
      expect(
        tester.getSize(commitButton).height,
        moreOrLessEquals(gitlamaSmallButtonHeight, epsilon: 0.01),
      );
      expect(
        tester.getSize(commitMenu).height,
        tester.getSize(commitButton).height,
      );

      selectComposerOption(tester, 'Template');
      await tester.pump();
      expect(find.text('template subject'), findsOneWidget);
      expect(find.text('template body'), findsOneWidget);
      selectComposerOption(tester, 'Commit options');
      await tester.pumpAndSettle();
      // Fields, then signing as a labelled select, then the options as one
      // column of checkboxes, then the message tools.
      expect(
        tester
            .widget<MeridianSelect<CommitSigning>>(
              find.byKey(const ValueKey('commit-options-signing')),
            )
            .showLabel,
        isTrue,
      );
      final options = find.byKey(const ValueKey('commit-options-content'));
      final checkboxes = find.descendant(
        of: options,
        matching: find.byType(MeridianCheckbox),
      );
      expect(checkboxes, findsNWidgets(3));
      expect({
        for (final element in checkboxes.evaluate())
          tester.getTopLeft(find.byWidget(element.widget)).dx,
      }, hasLength(1));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('commit-options-message-tools')),
          matching: find.byType(MeridianMenuAnchor),
        ),
        findsNWidgets(2),
      );
      await tester.enterText(
        findMeridianField('Co-authors'),
        'Pair <pair@example.invalid>',
      );
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amend'));
      await tester.pump();
      repository.commitBarrier = Completer<void>();
      await tester.tap(findComposerCommitButton());
      await tester.pumpAndSettle();
      expect(find.text('Amend published commit'), findsNWidgets(2));
      await tester.tap(
        find.widgetWithText(MeridianButton, 'Amend published commit'),
      );
      await tester.pump();

      expect(repository.commitRequests, hasLength(1));
      expect(
        runtime.repositorySessions.activeCommitDraft.subject,
        'template subject',
      );
      expect(
        runtime.repositorySessions.activeCommitDraft.description,
        'template body',
      );
      expect(
        tester.widget<MeridianButton>(findComposerCommitButton()).onPressed,
        isNull,
      );
      await tester.tap(findComposerCommitButton());
      expect(repository.commitRequests, hasLength(1));
      repository.commitBarrier!.complete();
      repository.commitBarrier = null;
      await tester.pumpAndSettle();
      expect(repository.commitRequests.single.subject, 'template subject');
      expect(repository.commitRequests.single.description, 'template body');
      expect(repository.commitRequests.single.coauthors, [
        'Pair <pair@example.invalid>',
      ]);
      expect(repository.commitRequests.single.amend, isTrue);
      expect(find.text('Commit created.'), findsOneWidget);
      expect(
        tester.widget<MeridianButton>(findComposerCommitButton()).success,
        isTrue,
      );
      expect(
        tester
            .widget<HostingReferenceTextField>(
              find.byKey(const ValueKey('commit-subject-field')),
            )
            .programmaticClearSequence,
        1,
      );
      expect(
        tester
            .widget<HostingReferenceTextField>(
              find.byKey(const ValueKey('commit-description-field')),
            )
            .programmaticClearSequence,
        1,
      );
      expect(runtime.repositorySessions.activeCommitDraft.subject, isEmpty);
      expect(runtime.repositorySessions.activeCommitDraft.description, isEmpty);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Commit subject'))
            .controller
            ?.text,
        isEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Commit subject'),
        'keyboard commit',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(repository.commitRequests, hasLength(2));
      expect(repository.commitRequests.last.subject, 'keyboard commit');
      await tester.showKeyboard(subjectFinder);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(descriptionField.focusNode?.hasFocus, isTrue);
      await runtime.shutdown();
    },
  );

  testWidgets('commit hook failure stays inline and requires typed bypass', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: root,
          worktreeRoot: root,
          gitDir: root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          headObjectId: '1' * 40,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          branchName: 'main'.codeUnits,
          headObjectId: '1' * 40,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'tracked.txt'.codeUnits,
              ),
              index: ChangeKind.modified,
              worktree: ChangeKind.unmodified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
      commitResult: const CommitExecutionResult(
        state: CommitExecutionState.failed,
        failureKind: CommitFailureKind.hook,
        exitCode: 17,
        output: ['pre-commit hook rejected the staged change'],
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Commit subject'),
      'keep this draft',
    );
    await tester.pump();
    await tester.tap(findComposerCommitButton());
    await tester.pumpAndSettle();
    expect(repository.commitRequests, hasLength(1));
    expect(repository.commitResult.state, CommitExecutionState.failed);
    expect(find.byKey(const ValueKey('commit-failure-panel')), findsOneWidget);
    expect(find.textContaining('Commit hook failed'), findsOneWidget);
    expect(find.textContaining('Exit code 17'), findsOneWidget);
    expect(
      find.text('pre-commit hook rejected the staged change'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(MeridianButton, 'Skip hooks'));
    await tester.pumpAndSettle();
    final bypass = find.widgetWithText(MeridianButton, 'Skip hooks').last;
    expect(tester.widget<MeridianButton>(bypass).onPressed, isNull);
    await tester.enterText(findMeridianField('Type SKIP'), 'SKIP');
    await tester.pump();
    repository.commitResult = const CommitExecutionResult(
      state: CommitExecutionState.completed,
      commit: 'abcdef1234567890',
    );
    await tester.tap(bypass);
    await tester.pumpAndSettle();
    expect(repository.commitRequests, hasLength(2));
    expect(repository.commitRequests.last.skipHooks, isTrue);
    expect(find.text('Committed abcdef1'), findsOneWidget);
    expect(find.byKey(const ValueKey('commit-failure-panel')), findsNothing);
    await runtime.shutdown();
  });

  testWidgets('commit and push commits and then starts the regular push', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: root,
          worktreeRoot: root,
          gitDir: root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          headObjectId: '1' * 40,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          branchName: 'main'.codeUnits,
          headObjectId: '1' * 40,
          upstream: 'origin/main'.codeUnits,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'tracked.txt'.codeUnits,
              ),
              index: ChangeKind.modified,
              worktree: ChangeKind.unmodified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
        refs: RepositoryRefs(
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
            ),
          ],
        ),
      ),
      commitResult: const CommitExecutionResult(
        state: CommitExecutionState.failed,
        failureKind: CommitFailureKind.hook,
        exitCode: 17,
        output: ['pre-commit hook rejected the staged change'],
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final commitAndPush = find.byKey(const ValueKey('commit-push-menu'));
    final pushButton = find.widgetWithText(MeridianButton, 'Push');

    // A commit that fails starts no push.
    await tester.enterText(
      find.widgetWithText(TextField, 'Commit subject'),
      'publish this',
    );
    await tester.pump();
    await tester.tap(commitAndPush);
    await tester.pumpAndSettle();
    expect(repository.commitRequests, hasLength(1));
    expect(find.byKey(const ValueKey('commit-failure-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('transfer-force')), findsNothing);
    expect(repository.transferRequest, isNull);

    // After the commit, the push is the one the Push command starts: the
    // same dialog, then the same transfer.
    repository.commitResult = const CommitExecutionResult(
      state: CommitExecutionState.completed,
      commit: 'abcdef1234567890',
    );
    await tester.tap(commitAndPush);
    await tester.pumpAndSettle();
    expect(repository.commitRequests, hasLength(2));
    expect(find.byKey(const ValueKey('transfer-force')), findsOneWidget);
    expect(repository.transferRequest, isNull);
    await tester.tap(pushButton.last);
    await tester.pumpAndSettle();
    expect(repository.transferRequest?.kind, TransferKind.push);
    expect(repository.transferRequest?.remote, 'origin');
    expect(repository.transferRequest?.forceWithLease, isFalse);
    expect(repository.executedTransferToken, BigInt.from(83));
    expect(find.textContaining('Transfer completed'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('patch dialog previews export and checked recovery apply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: 'tracked.txt'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: path,
              index: ChangeKind.unmodified,
              worktree: ChangeKind.modified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker('/chosen'));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.text('tracked.txt'));
    await tester.pump();
    final fileMenu = tester.widget<GitLamaContextMenuWidget>(
      find
          .ancestor(
            of: find.text('tracked.txt').first,
            matching: find.byType(GitLamaContextMenuWidget),
          )
          .first,
    );
    final provided = fileMenu.testMenu() as Menu;
    provided.children
        .whereType<MenuAction>()
        .firstWhere((item) => item.title == 'Create patch')
        .callback();
    await tester.pumpAndSettle();
    expect(find.text('Choose a folder to see what will be written.'), findsOne);
    // The patch dialog is a form: the form width less the dialog insets.
    expect(
      tester.getSize(find.byKey(const ValueKey('patch-dialog-content'))).width,
      MeridianLayout.dialogFormWidth - 2 * MeridianSpace.space7,
    );
    // The Create/Apply switch hugs its choices at the leading edge instead of
    // stretching an empty track across the dialog.
    final modes = find.byType(MeridianSegmented<PatchDialogMode>);
    expect(
      tester.getSize(modes).width,
      lessThan(MeridianLayout.dialogFormWidth - 2 * MeridianSpace.space7),
    );
    expect(
      tester.getTopLeft(modes).dx,
      tester.getTopLeft(find.byKey(const ValueKey('patch-dialog-content'))).dx,
    );
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(repository.patchExportRequest?.selectedPaths, [path.units]);
    expect(repository.patchExportRequest?.selectedSide, PatchSide.unstaged);
    expect(find.text('Selected unstaged files'), findsOne);
    expect(find.text('repository-selected.patch'), findsOne);
    await tester.tap(find.text('Write patch'));
    await tester.pumpAndSettle();
    expect(repository.executedPatchExportToken, BigInt.from(81));
    expect(find.text('Patch created.'), findsOne);
    expect(find.text('/chosen/repository.patch'), findsOneWidget);
    expect(
      tester
          .widget<MeridianButton>(
            find.widgetWithText(MeridianButton, 'Show in folder'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Apply patch').first);
    await tester.pump();
    expect(find.text('Choose a .patch or .diff file.'), findsOne);
    await tester.tap(find.text('Choose patch file'));
    await tester.pumpAndSettle();
    expect(repository.patchApplyPath, '/chosen');
    expect(find.text('Applies cleanly'), findsOne);
    expect(find.textContaining('undo'), findsNothing);
    // The changed files are a bounded list of names and folders.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('patch-apply-files')),
        matching: find.text('tracked.txt'),
      ),
      findsOne,
    );
    expect(find.text('1 file changes'), findsOne);
    await tester.tap(find.widgetWithText(MeridianButton, 'Apply patch'));
    await tester.pumpAndSettle();
    expect(repository.executedPatchApplyToken, BigInt.from(82));
    expect(find.text('Patch applied.'), findsOne);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Apply patch');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianListRow, 'Apply patch'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a .patch or .diff file.'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets(
    'main Changes diff stages lines and hunks and confirms scoped discard',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final path = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: 'partial.txt'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: path,
                index: ChangeKind.modified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        workingDiffResult: DiffPage(
          requestId: BigInt.from(73),
          layout: DiffViewLayout.unified,
          totalRows: 4,
          offset: 0,
          payloadBytes: 80,
          rows: [
            DiffDisplayRow(
              stableId: 'hunk-main',
              kind: DiffRowKind.hunk,
              text: '@@ -1 +1 @@'.codeUnits,
            ),
            DiffDisplayRow(
              stableId: 'context-main',
              kind: DiffRowKind.context,
              text: 'context'.codeUnits,
            ),
            DiffDisplayRow(
              stableId: 'delete-main',
              kind: DiffRowKind.deletion,
              text: 'before'.codeUnits,
              selectable: true,
            ),
            DiffDisplayRow(
              stableId: 'add-main',
              kind: DiffRowKind.addition,
              text: 'after'.codeUnits,
              selectable: true,
            ),
          ],
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      final unstaged = find.descendant(
        of: find.byKey(const ValueKey('changes-unstaged-list')),
        matching: find.byType(GitLamaFileRow),
      );
      await tester.tap(unstaged.first);
      await tester.pumpAndSettle();
      final subject = find.descendant(
        of: find.byKey(const ValueKey('commit-subject-field')),
        matching: find.byType(TextField),
      );
      final description = find.descendant(
        of: find.byKey(const ValueKey('commit-description-field')),
        matching: find.byType(TextField),
      );
      await tester.enterText(subject, 'fix');
      await tester.enterText(description, 'design');
      await tester.pumpAndSettle();
      final editorText = tester.widget<TextField>(subject);
      expect(editorText.style?.fontSize, gitlamaText.bodyStrong.fontSize);
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            '../build/evidence/ui-review/inline-patch-editor.png',
          ),
        );
      }
      await tester.tapAt(_diffGutter(tester, 'delete-main'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(_diffGutter(tester, 'add-main'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        tester
            .widget<MeridianButton>(
              find.byKey(const ValueKey('diff-selection-stage')),
            )
            .label,
        'Stage',
      );
      await tester.tap(find.byKey(const ValueKey('diff-selection-stage')));
      await tester.pumpAndSettle();
      expect(repository.stagingRequests.single.scope, StagingScope.rows);
      expect(repository.stagingRequests.single.rowIds, [
        'delete-main',
        'add-main',
      ]);
      expect(repository.stagingRequests.single.requestId, BigInt.from(73));
      await tester.tap(find.byKey(const ValueKey('stage-hunk-hunk-main')));
      await tester.pumpAndSettle();
      expect(repository.stagingRequests.last.rowIds, ['hunk-main']);
      await tester.tap(find.byKey(const ValueKey('discard-hunk-hunk-main')));
      await tester.pumpAndSettle();
      expect(repository.discardRequests.last.rowIds, ['hunk-main']);
      expect(repository.executedDiscardToken, isNull);
      await tester.tap(find.text('Discard permanently'));
      await tester.pumpAndSettle();
      expect(repository.executedDiscardToken, BigInt.one);
      final staged = find.descendant(
        of: find.byKey(const ValueKey('changes-staged-list')),
        matching: find.byType(GitLamaFileRow),
      );
      await tester.tap(staged.first);
      await tester.pumpAndSettle();
      expect(find.text('Discard hunk'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('stage-hunk-hunk-main')));
      await tester.pumpAndSettle();
      expect(repository.stagingRequests.last.side, StagingSide.staged);
      expect(repository.stagingRequests.last.rowIds, ['hunk-main']);
      tester.view.physicalSize = const Size(900, 600);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final editorBounds = tester.getRect(
        find.byKey(const ValueKey('changes-commit-editor')),
      );
      final commitMenuBounds = tester.getRect(
        find.byKey(const ValueKey('commit-push-menu')),
      );
      expect(commitMenuBounds.bottom, lessThanOrEqualTo(editorBounds.bottom));
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            '../build/evidence/ui-review/inline-patch-editor-scaled.png',
          ),
        );
      }
      expect(tester.takeException(), isNull);
      await runtime.shutdown();
    },
  );

  testWidgets('push previews remote identity and executes from commands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          branchName: 'main'.codeUnits,
          headObjectId: '1111111111111111111111111111111111111111',
          upstream: 'origin/main'.codeUnits,
          ahead: BigInt.one,
          behind: BigInt.zero,
          entries: const [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: const [],
        ),
        refs: RepositoryRefs(
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    final push = find.byKey(const ValueKey('push-primary'));
    final options = find.byTooltip('Push options');
    final split = find.byKey(const ValueKey('push-split-button'));
    expect(find.descendant(of: split, matching: push), findsOneWidget);
    expect(find.descendant(of: push, matching: options), findsOneWidget);
    expect(tester.getSize(split).height, MeridianLayout.toolbarButtonHeight);
    // The caret closes the split button at its end.
    expect(tester.getRect(options).right, tester.getRect(push).right);
    // Push counts the commits it would send, as Pull counts those to fetch.
    expect(tester.widget<MeridianToolbarButton>(push).badge, 1);
    // Force push is marked as dangerous and comes last.
    final pushMenu = tester
        .widget<MeridianToolbarButton>(push)
        .menu!
        .whereType<MeridianMenuItem>()
        .toList();
    expect(pushMenu.last.label, 'Force push with lease');
    expect(pushMenu.last.danger, isTrue);
    expect(pushMenu.where((item) => item.danger), [pushMenu.last]);
    expect(
      tester
          .widget<MeridianToolbarButton>(
            find.byKey(const ValueKey('toolbar-action-pull')),
          )
          .badge,
      isNull,
    );
    await tester.tap(push);
    await tester.pumpAndSettle();
    // A branch that already has an upstream keeps it: nothing to ask.
    expect(find.byKey(const ValueKey('transfer-set-upstream')), findsNothing);
    await tester.tap(find.widgetWithText(MeridianButton, 'Push'));
    await tester.pumpAndSettle();
    expect(repository.transferRequest?.kind, TransferKind.push);
    expect(find.text('Review transfer'), findsNothing);
    expect(repository.transferRequest?.kind, TransferKind.push);
    expect(repository.transferRequest?.remote, 'origin');
    expect(repository.transferRequest?.forceWithLease, isFalse);
    expect(repository.executedTransferToken, BigInt.from(83));
    expect(find.textContaining('Transfer completed'), findsOneWidget);
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force push with lease'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MeridianCheckbox>(
            find.byKey(const ValueKey('transfer-force')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.widgetWithText(MeridianButton, 'Push'));
    await tester.pumpAndSettle();
    expect(repository.transferRequest?.forceWithLease, isTrue);
    expect(repository.executedTransferToken, BigInt.from(83));

    await runtime.shutdown();
  });

  testWidgets('toolbar Branch creates a branch and checks it out', (
    tester,
  ) async {
    // The narrowest window that still shows the full toolbar.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1101, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          branchName: 'main'.codeUnits,
          headObjectId: '1' * 40,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: const [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    final branch = find.byKey(const ValueKey('toolbar-action-createBranch'));
    expect(
      find.descendant(of: branch, matching: find.text('Branch')),
      findsOneWidget,
    );
    // Branch sits between Push and Stash.
    expect(
      tester.getRect(branch).left,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('push-split-button'))).right,
      ),
    );
    expect(
      tester.getRect(branch).right,
      lessThan(
        tester
            .getRect(find.byKey(const ValueKey('toolbar-action-createStash')))
            .left,
      ),
    );
    expect(
      tester.getRect(branch).right,
      lessThan(tester.getRect(find.byType(GitLamaCompass)).left),
    );

    await tester.tap(branch);
    await tester.pumpAndSettle();
    final checkout = find.byKey(const ValueKey('create-branch-checkout'));
    expect(tester.widget<MeridianCheckbox>(checkout).value, isTrue);
    await tester.enterText(findMeridianField('Name'), 'topic');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianButton, 'Create branch'));
    await tester.pumpAndSettle();
    expect(repository.refMutationRequest?.kind, RefMutationKind.createBranch);
    expect(repository.refMutationRequest?.name, 'topic');
    expect(repository.refMutationRequest?.target, '1' * 40);
    expect(repository.refMutationRequest?.checkout, isTrue);
    expect(
      find.text(
        'Create local branch topic and switch to it. '
        'Uncommitted changes stay in the working tree.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Clearing the option only creates the branch.
    await tester.tap(branch);
    await tester.pumpAndSettle();
    await tester.tap(checkout);
    await tester.enterText(findMeridianField('Name'), 'other');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianButton, 'Create branch'));
    await tester.pumpAndSettle();
    expect(repository.refMutationRequest?.checkout, isFalse);
    expect(find.text('Create local branch other.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await runtime.shutdown();
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('push can set upstream when the branch has none', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          branchName: 'main'.codeUnits,
          headObjectId: '1111111111111111111111111111111111111111',
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
              target: '1111111111111111111111111111111111111111',
            ),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('command-palette-query')),
      'push',
    );
    await tester.pump();
    await tester.tap(find.text('Push…'));
    await tester.pumpAndSettle();
    final upstream = find.widgetWithText(
      MeridianCheckbox,
      'Link this branch to the remote branch',
    );
    expect(tester.widget<MeridianCheckbox>(upstream).onChanged, isNotNull);
    expect(tester.widget<MeridianCheckbox>(upstream).value, isTrue);
    await tester.tap(upstream);
    await tester.pump();
    expect(tester.widget<MeridianCheckbox>(upstream).value, isFalse);
    await tester.tap(upstream);
    await tester.pump();
    expect(tester.widget<MeridianCheckbox>(upstream).value, isTrue);
    await tester.tap(find.widgetWithText(MeridianButton, 'Push'));
    await tester.pumpAndSettle();
    expect(repository.transferRequest?.setUpstream, isTrue);
    await runtime.shutdown();
  });

  testWidgets('tag context action pushes the exact tag through transfer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          branchName: 'main'.codeUnits,
          headObjectId: '1111111111111111111111111111111111111111',
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: const [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: const [],
        ),
        refs: RepositoryRefs(
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
            ),
          ],
          tags: [
            RepositoryReference(
              name: 'v1.0.0'.codeUnits,
              target: '1111111111111111111111111111111111111111',
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await _openSidebarTags(tester);

    await tester.tap(
      find.byKey(const ValueKey('sidebar-ref-v1.0.0')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push tag…'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'v1.0.0'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Push tag'));
    await tester.pumpAndSettle();
    expect(repository.transferRequest?.kind, TransferKind.pushTag);
    expect(repository.transferRequest?.branch, 'v1.0.0');
    expect(repository.executedTransferToken, BigInt.from(83));

    await tester.tap(
      find.byKey(const ValueKey('sidebar-ref-v1.0.0')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete tag…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-tag-remote-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MeridianButton, 'Delete tag'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delete tag v1.0.0 from origin'),
      findsOneWidget,
    );
    final deleteButton = find.widgetWithText(MeridianButton, 'Delete');
    expect(
      tester.widget<MeridianButton>(deleteButton).variant,
      MeridianButtonVariant.danger,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(repository.transferRequest?.kind, TransferKind.deleteTag);
    expect(repository.transferRequest?.remote, 'origin');
    expect(repository.executedRefMutationToken, BigInt.from(88));
    await runtime.shutdown();
  });

  testWidgets('deleting a branch can delete its upstream afterwards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const commit = '1111111111111111111111111111111111111111';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          branchName: 'main'.codeUnits,
          headObjectId: commit,
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
              target: commit,
              head: true,
            ),
            RepositoryReference(
              name: 'topic'.codeUnits,
              target: commit,
              upstream: 'refs/remotes/origin/topic'.codeUnits,
            ),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
              branches: [
                RepositoryReference(name: 'topic'.codeUnits, target: commit),
              ],
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(
      find.byKey(const ValueKey('sidebar-ref-topic')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete branch…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-branch-upstream')));
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianButton, 'Delete branch'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Delete local branch topic and its upstream '
        'origin/topic',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(MeridianButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repository.refMutationRequest?.kind, RefMutationKind.deleteBranch);
    expect(repository.executedRefMutationToken, BigInt.from(88));
    expect(repository.transferRequest?.kind, TransferKind.deleteBranch);
    expect(repository.transferRequest?.remote, 'origin');
    expect(repository.transferRequest?.branch, 'topic');
    expect(repository.transferAfterRefMutation, isTrue);
    await runtime.shutdown();
  });

  testWidgets('a remote branch can be deleted on its own from the sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const commit = '1111111111111111111111111111111111111111';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          branchName: 'main'.codeUnits,
          headObjectId: commit,
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
              target: commit,
              head: true,
            ),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
              branches: [
                RepositoryReference(name: 'main'.codeUnits, target: commit),
                RepositoryReference(name: 'stale'.codeUnits, target: commit),
              ],
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await _expandSidebarGroup(tester, 'sidebar-ref-origin');

    await tester.tap(
      find.byKey(const ValueKey('sidebar-ref-1-stale')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete remote branch…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('only if it has not moved since the last fetch'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(MeridianButton, 'Delete remote branch'),
    );
    await tester.pumpAndSettle();
    expect(repository.refMutationRequest, isNull);
    expect(repository.transferRequest?.kind, TransferKind.deleteBranch);
    expect(repository.transferRequest?.remote, 'origin');
    expect(repository.transferRequest?.branch, 'stale');
    await runtime.shutdown();
  });

  testWidgets(
    'forwarded pull uses configured strategy and runs after confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            branchName: 'main'.codeUnits,
            headObjectId: '1111111111111111111111111111111111111111',
            upstream: 'origin/main'.codeUnits,
            ahead: BigInt.zero,
            behind: BigInt.one,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
          refs: RepositoryRefs(
            remotes: [
              RepositoryRemote(
                name: 'origin'.codeUnits,
                displayUrl: 'example.test/repository'.codeUnits,
              ),
            ],
          ),
        ),
      );
      final cli = _TestCliController();
      addTearDown(cli.close);
      final runtime = await _runtime(
        repository,
        _Picker(null),
        null,
        null,
        cli,
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      cli.add(
        CliForwardedCommand(
          requestId: BigInt.one,
          kind: CliForwardedCommandKind.pull,
          pullStrategy: CliPullStrategy.rebase,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Fetch a remote branch and integrate it into the current branch.',
        ),
        findsOneWidget,
      );
      final strategy = tester.widget<MeridianSelect<PullStrategy>>(
        find.byType(MeridianSelect<PullStrategy>),
      );
      expect(strategy.value, PullStrategy.rebase);
      expect(repository.transferRequest, isNull);
      expect(repository.executedTransferToken, isNull);

      await tester.tap(find.widgetWithText(MeridianButton, 'Pull'));
      await tester.pumpAndSettle();

      expect(repository.transferRequest?.kind, TransferKind.pull);
      expect(repository.transferRequest?.pullStrategy, PullStrategy.rebase);
      expect(repository.executedTransferToken, BigInt.from(83));
      expect(find.text('Review transfer'), findsNothing);
      await runtime.shutdown();
    },
  );

  testWidgets('a pull that moves HEAD reveals it in History', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const before = '1111111111111111111111111111111111111111';
    const pulled = '2222222222222222222222222222222222222222';
    RepositorySnapshot snapshot(int revision, String head, int behind) =>
        RepositorySnapshot(
          revision: BigInt.from(revision),
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            branchName: 'main'.codeUnits,
            headObjectId: head,
            upstream: 'origin/main'.codeUnits,
            ahead: BigInt.zero,
            behind: BigInt.from(behind),
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
          refs: RepositoryRefs(
            remotes: [
              RepositoryRemote(
                name: 'origin'.codeUnits,
                displayUrl: 'example.test/repository'.codeUnits,
              ),
            ],
          ),
        );
    final repository = _WelcomeRepository(
      snapshot: snapshot(1, before, 1),
      historyRows: [
        HistoryTopologyRow(
          objectId: pulled,
          parents: const [before],
          refs: ['refs/remotes/origin/main'.codeUnits],
          lane: 0,
          shape: HistoryNodeShape.commit.index,
        ),
        HistoryTopologyRow(
          objectId: before,
          parents: const [],
          refs: ['refs/heads/main'.codeUnits],
          lane: 0,
          shape: HistoryNodeShape.commit.index,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    final sessions = runtime.repositorySessions;
    await sessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    final reveals = repository._revealSequence;

    Future<void> transfer(String label) async {
      await tester.tap(
        find.byKey(ValueKey('toolbar-action-${label.toLowerCase()}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MeridianButton, label).last);
      await tester.pumpAndSettle();
    }

    // A fetch moves remote branches only; the view stays where it is.
    await transfer('Fetch');
    repository.pendingEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(2, before, 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(repository._revealSequence, reveals);

    await transfer('Pull');
    expect(repository.transferRequest?.kind, TransferKind.pull);
    expect(repository._revealSequence, reveals);
    repository.pendingEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(3, pulled, 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(repository._revealSequence, reveals + 1);
    expect(repository._selectedHistoryIds, {pulled});
    expect(sessions.workspace.activeTab?.navigation.selectedIdentity, pulled);
    await runtime.shutdown();
  });

  testWidgets('create stash previews scope and executes from commands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'tracked.txt'.codeUnits,
              ),
              index: ChangeKind.modified,
              worktree: ChangeKind.modified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('command-palette-query')),
      'create stash',
    );
    await tester.pump();
    await tester.tap(find.text('Create stash…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(MeridianTextField, 'Name (optional)'),
      'checkpoint',
    );
    await tester.tap(find.text('Include new files'));
    await tester.tap(find.text('Keep staged changes'));
    await tester.tap(find.widgetWithText(MeridianButton, 'Create stash'));
    await tester.pumpAndSettle();
    expect(repository.stashRequest?.kind, StashKind.push);
    expect(repository.stashRequest?.message, 'checkpoint');
    expect(repository.stashRequest?.includeUntracked, isTrue);
    expect(repository.stashRequest?.keepIndex, isTrue);
    expect(find.textContaining('Save the selected changes'), findsOneWidget);
    await tester.tap(find.text('Git command details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('git stash push'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Create stash'));
    await tester.pumpAndSettle();
    expect(repository.executedStashToken, BigInt.from(84));
    expect(find.text('Stash operation completed.'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('workspace localizes persistent repository conditions', (
    tester,
  ) async {
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        watchFailure: const RepositoryFailure(RepositoryFailureCode.watch),
        refsFailure: const RepositoryFailure(RepositoryFailureCode.read),
        identity: RepositoryIdentity(
          commonGitDir: path,
          worktreeRoot: path,
          gitDir: path,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.detached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.conflicted,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.unmerged,
              path: path,
              index: ChangeKind.updatedButUnmerged,
              worktree: ChangeKind.updatedButUnmerged,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [
            RepositoryOperationState(kind: RepositoryOperationKind.merge),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    expect(
      find.textContaining('Automatic repository updates are unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('No branch is checked out'), findsOneWidget);
    expect(find.textContaining('1 file has conflicts'), findsOneWidget);
    expect(find.textContaining('Merge in progress'), findsOneWidget);
    expect(find.text('Conflicts · 1'), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/evidence/ui-review/conflict-banner.png'),
      );
    }
    await runtime.shutdown();
  });

  testWidgets('changes pane exposes the three-pane conflict resolver', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: path,
          worktreeRoot: path,
          gitDir: path,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.conflicted,
          branchName: 'main'.codeUnits,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.unmerged,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'conflict.txt'.codeUnits,
              ),
              index: ChangeKind.updatedButUnmerged,
              worktree: ChangeKind.updatedButUnmerged,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.settings.saveDurable(
      runtime.settings.current.copyWith(
        integrations: [
          IntegrationDefinition(
            id: 'Merge fixture',
            kind: IntegrationKind.mergeTool,
            executable: path,
            arguments: const [
              '{merge_base}',
              '{merge_current}',
              '{merge_incoming}',
              '{merge_result}',
            ],
            launchMode: IntegrationLaunchMode.wait,
            requiresConfirmation: true,
          ),
        ],
      ),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Resolve conflicts'), findsOneWidget);
    expect(find.text('Current: main'), findsOneWidget);
    expect(find.text('Incoming: topic'), findsOneWidget);
    expect(find.byKey(const Key('conflict-result-editor')), findsOneWidget);
    // The conflict queue uses the shared rows and file menu.
    final conflictMenu = (await tester
        .widget<GitLamaContextMenuWidget>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (widget) =>
                      widget is GitLamaFileRow && widget.path == 'conflict.txt',
                ),
                matching: find.byType(GitLamaContextMenuWidget),
              )
              .first,
        )
        .testMenu())!;
    final conflictActions = conflictMenu.children
        .whereType<MenuAction>()
        .toList();
    expect(conflictActions.map((action) => action.title), [
      'Blame (HEAD) — No commit yet',
      'File history (HEAD) — No commit yet',
      'Open in external editor',
      'Open in ${platformFileBrowserName()}',
      'Copy path',
    ]);
    expect(conflictActions.first.attributes.disabled, isTrue);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/evidence/ui-review/conflict-resolver.png'),
      );
    }
    final comparison = find.byKey(const Key('conflict-comparison-lines'));
    expect(comparison, findsOneWidget);
    expect(
      tester
          .widget<MeridianRollingNumber>(
            find.byKey(const Key('conflict-resolved-count')),
          )
          .value,
      0,
    );
    expect(
      tester.getRect(find.byKey(const Key('conflict-result-editor'))).left,
      greaterThan(tester.getRect(comparison).right),
    );
    final inlineResult = tester
        .widget<TextField>(find.byKey(const Key('conflict-result-editor')))
        .controller!;
    await tester.tap(find.byKey(const ValueKey('conflict-take-0-current')));
    await tester.pump();
    expect(inlineResult.text, 'current\n');
    // Taken text is marked in its side's colour, never the selection's.
    final resultContext = tester.element(
      find.byKey(const Key('conflict-result-editor')),
    );
    final git = resultContext.git;
    Color tint(Color side) =>
        side.withValues(alpha: GitLamaOpacity.conflictUnchosen);
    expect(
      tester.renderObject(_conflictResultMarks),
      paints..rrect(color: tint(git.sideOurs)),
    );
    expect(
      tint(git.sideOurs),
      isNot(MeridianTheme.of(resultContext).colors.accentSoft),
    );
    expect(
      tester
          .widget<MeridianRollingNumber>(
            find.byKey(const Key('conflict-resolved-count')),
          )
          .value,
      1,
    );
    await tester.tap(find.byKey(const ValueKey('conflict-take-0-incoming')));
    await tester.pumpAndSettle();
    expect(inlineResult.text, 'current\nincoming\n');
    // Both sides: the current part, then the incoming part.
    expect(
      tester.renderObject(_conflictResultMarks),
      paints
        ..rrect(color: tint(git.sideOurs))
        ..rect(
          color: git.sideOurs.withValues(
            alpha: GitLamaOpacity.conflictRailChosen,
          ),
        )
        ..rrect(color: tint(git.sideTheirs)),
    );
    expect(find.text('Remove current'), findsOneWidget);
    expect(find.text('Remove incoming'), findsOneWidget);
    expect(find.text('Remove both'), findsOneWidget);
    expect(
      tester
          .widget<MeridianButton>(
            find.widgetWithText(MeridianButton, 'Resolve file'),
          )
          .onPressed,
      isNotNull,
    );
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../build/evidence/ui-review/conflict-inline-selected.png',
        ),
      );
    }
    await tester.tap(find.byKey(const ValueKey('conflict-take-0-both')));
    await tester.pump();
    expect(inlineResult.text, contains('<<<<<<< HEAD'));
    await tester.tap(find.byKey(const ValueKey('conflict-inline-0-current')));
    await tester.pump();
    expect(inlineResult.text, 'current\n');
    await tester.tap(find.byKey(const ValueKey('conflict-inline-0-incoming')));
    await tester.pump();
    expect(inlineResult.text, 'current\nincoming\n');
    await tester.tap(find.byKey(const ValueKey('conflict-take-0-both')));
    await tester.pump();
    expect(inlineResult.text, contains('<<<<<<< HEAD'));
    expect(
      find.descendant(
        of: comparison,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    final firstRow = find.byKey(const Key('conflict-comparison-row-0'));
    final rowHeight = tester.getSize(firstRow).height;
    final cells = find.descendant(
      of: firstRow,
      matching: find.byType(Container),
    );
    expect(tester.getSize(cells.first).height, rowHeight);
    await tester.binding.setSurfaceSize(const Size(1440, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(800, 640));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    await tester.pumpAndSettle();
    final resultEditor = tester.widget<TextField>(
      find.byKey(const Key('conflict-result-editor')),
    );
    final resultController = resultEditor.controller!;
    final edited = resultController.text.replaceRange(20, 20, 'X');
    resultController.value = TextEditingValue(
      text: edited,
      selection: const TextSelection.collapsed(offset: 21),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(resultController.selection.baseOffset, 21);
    expect(resultController.text, edited);
    expect(repository.conflictSavedResult, isNull);
    await tester.tap(find.byKey(const Key('conflict-external-merge')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Review exact command'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Run'));
    await tester.pumpAndSettle();
    expect(repository.integrationExecuted, isTrue);
    expect(find.text('Take both'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(repository.conflictRegionChoice, isNull);
    expect(repository.conflictSavedResult, isNull);
    expect(find.text('Resolve file'), findsOneWidget);
    final draftController = tester
        .widget<TextField>(find.byKey(const Key('conflict-result-editor')))
        .controller!;
    expect(draftController.text, 'current\nincoming\n');
    draftController.text =
        '${draftController.text}Edited after choosing both\n';
    await tester.pumpAndSettle();
    expect(repository.conflictSavedResult, isNull);
    await tester.tap(find.widgetWithText(MeridianButton, 'Resolve file'));
    await tester.pumpAndSettle();
    expect(
      repository.conflictSavedResult,
      'current\nincoming\nEdited after choosing both\n'.codeUnits,
    );
    expect(
      find.text('All conflict paths are resolved. Continue when ready.'),
      findsWidgets,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('conflict-merge-subject')))
          .controller!
          .text,
      'Merge topic',
    );
    await tester.tap(find.widgetWithText(MeridianButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(
      repository.conflictSequencerAction,
      ConflictSequencerAction.continueOperation,
    );
    expect(
      repository.conflictMergeMessage,
      'Merge topic\n\nReview the changes',
    );
    await runtime.shutdown();
  });

  testWidgets('conflict files resize, switch to tree and keep file identity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WelcomeRepository(snapshot: _conflictedSnapshot());
    ConflictFile entry(String path) => ConflictFile(
      path: utf8.encode(path),
      kind: ConflictFileKind.text,
      ancestor: ConflictSide(
        present: true,
        mode: 0x81a4,
        content: utf8.encode('base\n'),
        byteCount: 5,
      ),
      current: ConflictSide(
        present: true,
        mode: 0x81a4,
        content: utf8.encode('same\n'),
        byteCount: 5,
      ),
      incoming: ConflictSide(
        present: true,
        mode: 0x81ed,
        content: utf8.encode('same\n'),
        byteCount: 5,
      ),
      result: utf8.encode('same\n'),
      resultMode: 0x81ed,
      resultPresent: true,
      markerFree: true,
      regions: const [],
      fingerprint: BigInt.one,
      canUndoResolution: false,
    );
    repository.conflictSnapshot = ConflictSnapshot(
      operation: ConflictOperationKind.merge,
      currentLabel: utf8.encode('main'),
      incomingLabel: utf8.encode('topic'),
      files: [entry('src/nested/a.txt'), entry('src/other/b.txt')],
      resolvedUndoPaths: const [],
      canContinue: false,
      canSkip: false,
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Needs resolution'), findsNWidgets(2));
    final list = find.byKey(const Key('conflict-file-list'));
    final splitter = find.byKey(const Key('conflict-files-splitter'));
    final before = tester.getSize(list).width;
    await tester.drag(splitter, const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, greaterThan(before + 100));
    expect(find.text('Conflict 1'), findsNothing);
    expect(find.byKey(const Key('conflict-resolved-count')), findsNothing);
    expect(find.textContaining('identical file bytes'), findsOneWidget);
    // At the widened width the segmented control exposes Tree view.
    expect(find.byKey(const Key('conflict-files-mode')), findsOneWidget);
    await tester.tap(find.byTooltip('Show files as a tree'));
    await tester.pumpAndSettle();
    expect(find.text('nested'), findsOneWidget);
    expect(find.text('other'), findsOneWidget);
    final next = find.byWidgetPredicate(
      (widget) => widget is GitLamaFileRow && widget.path == 'b.txt',
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    final selected = tester.widget<GitLamaFileRow>(next);
    expect(selected.selected, isTrue);
    expect(find.text('File 2 of 2'), findsOneWidget);
    // The shared handle participates in keyboard focus traversal.
    Focus.of(
      tester.element(
        find.descendant(of: splitter, matching: find.byType(MouseRegion)).first,
      ),
    ).requestFocus();
    await tester.pump();
    final resized = tester.getSize(list).width;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, greaterThan(resized));
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../build/evidence/ui-review/conflict-metadata-wide.png',
        ),
      );
    }
    await tester.binding.setSurfaceSize(const Size(900, 600));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      _app(runtime, locale: const Locale('de'), brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, greaterThanOrEqualTo(180));
    expect(find.byKey(const Key('conflict-result-editor')), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../build/evidence/ui-review/conflict-metadata-narrow-de.png',
        ),
      );
    }
    await runtime.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('conflict sides, ancestor and result show syntax colours', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final syntax = _FirstWordSyntax();
    final service = SourceSyntaxService(syntax);
    addTearDown(service.dispose);
    final repository = _WelcomeRepository(snapshot: _conflictedSnapshot());
    final runtime = await _runtime(
      repository,
      _Picker(null),
      null,
      null,
      null,
      null,
      null,
      service,
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();
    // Plain text first; colours follow once the user is idle.
    bool coloured(InlineSpan span, String word) {
      var found = false;
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.text == word &&
            child.style?.color != null) {
          found = true;
        }
        return !found;
      });
      return found;
    }

    InlineSpan cell(String text) => tester
        .widget<RichText>(
          find.byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          ),
        )
        .text;
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(syntax.paths.toSet(), {'conflict.txt'});
    expect(coloured(cell('current'), 'current'), isTrue);
    expect(coloured(cell('incoming'), 'incoming'), isTrue);

    final editor = find.byKey(const Key('conflict-result-editor'));
    final controller = tester.widget<TextField>(editor).controller!;
    InlineSpan result() => controller.buildTextSpan(
      context: tester.element(editor),
      withComposing: false,
    );
    expect(result().toPlainText(), controller.text);
    expect(coloured(result(), '<<<<<<<'), isTrue);
    // Block marks are painted under the text, not as span fills that would
    // cover the selection.
    var filled = false;
    result().visitChildren((child) {
      filled |= child is TextSpan && child.style?.backgroundColor != null;
      return true;
    });
    expect(filled, isFalse);
    expect(
      tester.renderObject(_conflictResultMarks),
      paints..rrect(
        color: MeridianTheme.of(tester.element(editor)).colors.attentionBg,
      ),
    );

    // An edit colours the new text after the next pause.
    controller.text = 'fresh words\n${controller.text}';
    await tester.pump();
    expect(result().toPlainText(), controller.text);
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(coloured(result(), 'fresh'), isTrue);

    await tester.tap(find.text('Show ancestor'));
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ancestor = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'base\n',
      ),
    );
    expect(coloured(ancestor.textSpan!, 'base'), isTrue);
    await runtime.shutdown();
  });

  testWidgets('long conflict lines stay inside two aligned source panes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final longLine = List.filled(180, 'a long change').join(' ');
    final repository =
        _WelcomeRepository(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
              identity: RepositoryIdentity(
                commonGitDir: root,
                worktreeRoot: root,
                gitDir: root,
                kind: RepositoryKind.worktree,
                headKind: HeadKind.attached,
                gitMajor: 2,
                gitMinor: 50,
                gitPatch: 1,
              ),
              status: RepositoryStatus(
                workingTree: WorkingTreeState.conflicted,
                ahead: BigInt.zero,
                behind: BigInt.zero,
                entries: [
                  RepositoryStatusEntry(
                    kind: StatusEntryKind.unmerged,
                    path: NativePathIdentity(
                      platform: NativePathPlatform.unix,
                      units: 'long.txt'.codeUnits,
                    ),
                    index: ChangeKind.updatedButUnmerged,
                    worktree: ChangeKind.updatedButUnmerged,
                  ),
                ],
                totalEntries: BigInt.one,
                entriesTruncated: false,
                operations: const [],
              ),
            ),
          )
          ..conflictSnapshot = ConflictSnapshot(
            operation: ConflictOperationKind.merge,
            currentLabel: 'main'.codeUnits,
            incomingLabel: 'topic'.codeUnits,
            files: [
              ConflictFile(
                path: 'long.txt'.codeUnits,
                kind: ConflictFileKind.text,
                ancestor: const ConflictSide(present: false, byteCount: 0),
                current: ConflictSide(
                  present: true,
                  byteCount: longLine.length + 1,
                  content: '$longLine\n'.codeUnits,
                ),
                incoming: ConflictSide(
                  present: true,
                  byteCount: longLine.length + 1,
                  content: '$longLine\n'.codeUnits,
                ),
                resultPresent: true,
                markerFree: false,
                regions: [
                  ConflictRegion(
                    index: 0,
                    current: '$longLine\n'.codeUnits,
                    incoming: '$longLine\n'.codeUnits,
                  ),
                ],
                fingerprint: BigInt.one,
                canUndoResolution: false,
                result:
                    ('<<<<<<< HEAD\n$longLine\n=======\n$longLine\n>>>>>>> topic\n')
                        .codeUnits,
              ),
            ],
            resolvedUndoPaths: const [],
            canContinue: false,
            canSkip: false,
          );
    final runtime = await _runtime(repository, _Picker(null));
    // The resolver wraps like the diff views.
    runtime.settings.updateAppearance(
      (appearance) =>
          appearance.copyWith(diffView: const DiffViewPreferences(wrap: true)),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();

    final comparison = find.byKey(const Key('conflict-comparison-lines'));
    expect(comparison, findsOneWidget);
    expect(tester.getSize(comparison).width, lessThan(900));
    expect(
      find.descendant(
        of: comparison,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.text('Current: main'), findsOneWidget);
    expect(find.text('Incoming: topic'), findsOneWidget);
    final result = find.byKey(const Key('conflict-result-editor'));
    final span = tester
        .widget<TextField>(result)
        .controller!
        .buildTextSpan(
          context: tester.element(result),
          style: const TextStyle(),
          withComposing: false,
        );
    expect(
      (span.children ?? const <InlineSpan>[]).where(
        (child) => child.style?.backgroundColor != null,
      ),
      isEmpty,
    );
    final colors = MeridianTheme.of(tester.element(result)).colors;
    // The open conflict is one band across all its wrapped rows, under the
    // text and selection.
    late Rect band;
    expect(
      tester.renderObject(_conflictResultMarks),
      paints..something((method, arguments) {
        if (method != #drawRRect) return false;
        final paint = arguments[1] as Paint;
        if (paint.color.toARGB32() != colors.attentionBg.toARGB32()) {
          return false;
        }
        band = (arguments[0] as RRect).outerRect;
        return true;
      }),
    );
    expect(
      band.height,
      greaterThan(5 * GitLamaLayout.conflictComparisonRowHeight),
    );
    expect(tester.takeException(), isNull);

    // Wrapped long lines show both sides in full.
    const rowHeight = GitLamaLayout.conflictComparisonRowHeight;
    final firstRow = find.byKey(const Key('conflict-comparison-row-0'));
    expect(tester.getSize(firstRow).height, greaterThan(2 * rowHeight));
    expect(find.byType(MeridianSharedHorizontalScroll), findsNothing);

    // Each choice sits above the side it takes.
    final divider = tester.getCenter(comparison).dx;
    Rect take(String choice) =>
        tester.getRect(find.byKey(ValueKey('conflict-take-0-$choice')));
    expect(take('current').right, lessThan(divider));
    expect(take('incoming').left, greaterThan(divider));
    expect(take('both').left, greaterThan(take('incoming').right));

    // Pointing at a side names what a click on it does.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getTopLeft(
            find.byKey(const ValueKey('conflict-inline-0-incoming')),
          ) +
          const Offset(MeridianSpace.space8, MeridianSpace.space3),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('conflict-hover-action-0-incoming')),
      findsOneWidget,
    );
    expect(find.text('Take incoming'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('conflict-hover-action-0-current')),
      findsNothing,
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('conflict-hover-action-0-incoming')),
      findsNothing,
    );

    // Unwrapped, every line keeps one row and both sides scroll sideways.
    await tester.tap(find.byKey(const Key('conflict-wrap')));
    await tester.pumpAndSettle();
    expect(runtime.settings.current.appearance.diffView.wrap, isFalse);
    expect(tester.getSize(firstRow).height, rowHeight);
    final sideways = tester
        .widget<MeridianSharedHorizontalScroll>(
          find.byType(MeridianSharedHorizontalScroll),
        )
        .controller;
    expect(sideways.position.maxScrollExtent, greaterThan(0));
    sideways.jumpTo(sideways.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('conflict-wrap')));
    await tester.pumpAndSettle();
    expect(tester.getSize(firstRow).height, greaterThan(2 * rowHeight));
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(ConflictResolver),
        matchesGoldenFile(
          '../build/evidence/ui-review/conflict-long-lines.png',
        ),
      );
    }
    await runtime.shutdown();
  });

  testWidgets('conflict panes open on the first conflict and scroll together', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    String lines(String name, int count) =>
        [for (var line = 0; line < count; line++) '$name $line\n'].join();
    final current = [
      for (var region = 0; region < 3; region++) 'ours $region\n',
    ];
    final incoming = [
      for (var region = 0; region < 3; region++) lines('theirs $region', 6),
    ];
    String file(String Function(int region) conflict) => [
      for (var region = 0; region < 3; region++) ...[
        lines('shared $region', 120),
        conflict(region),
      ],
      lines('tail', 120),
    ].join();
    final currentText = file((region) => current[region]);
    final incomingText = file((region) => incoming[region]);
    final repository =
        _WelcomeRepository(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
              identity: RepositoryIdentity(
                commonGitDir: root,
                worktreeRoot: root,
                gitDir: root,
                kind: RepositoryKind.worktree,
                headKind: HeadKind.attached,
                gitMajor: 2,
                gitMinor: 50,
                gitPatch: 1,
              ),
              status: RepositoryStatus(
                workingTree: WorkingTreeState.conflicted,
                ahead: BigInt.zero,
                behind: BigInt.zero,
                entries: [
                  RepositoryStatusEntry(
                    kind: StatusEntryKind.unmerged,
                    path: NativePathIdentity(
                      platform: NativePathPlatform.unix,
                      units: 'regions.txt'.codeUnits,
                    ),
                    index: ChangeKind.updatedButUnmerged,
                    worktree: ChangeKind.updatedButUnmerged,
                  ),
                ],
                totalEntries: BigInt.one,
                entriesTruncated: false,
                operations: const [],
              ),
            ),
          )
          ..conflictSnapshot = ConflictSnapshot(
            operation: ConflictOperationKind.merge,
            currentLabel: 'main'.codeUnits,
            incomingLabel: 'topic'.codeUnits,
            files: [
              ConflictFile(
                path: 'regions.txt'.codeUnits,
                kind: ConflictFileKind.text,
                ancestor: const ConflictSide(present: false, byteCount: 0),
                current: ConflictSide(
                  present: true,
                  byteCount: currentText.length,
                  content: currentText.codeUnits,
                ),
                incoming: ConflictSide(
                  present: true,
                  byteCount: incomingText.length,
                  content: incomingText.codeUnits,
                ),
                resultPresent: true,
                markerFree: false,
                regions: [
                  for (var region = 0; region < 3; region++)
                    ConflictRegion(
                      index: region,
                      current: current[region].codeUnits,
                      incoming: incoming[region].codeUnits,
                    ),
                ],
                fingerprint: BigInt.one,
                canUndoResolution: false,
                result: file(
                  (region) =>
                      '<<<<<<< HEAD\n${current[region]}=======\n'
                      '${incoming[region]}>>>>>>> topic\n',
                ).codeUnits,
              ),
            ],
            resolvedUndoPaths: const [],
            canContinue: false,
            canSkip: false,
          );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();

    const row = GitLamaLayout.conflictComparisonRowHeight;
    final comparison = tester
        .widget<ListView>(find.byKey(const Key('conflict-comparison-lines')))
        .controller!;
    final editor = find.byKey(const Key('conflict-result-editor'));
    final result = tester.widget<TextField>(editor).scrollController!;
    final text = tester.widget<TextField>(editor).controller!;
    final editable = find.descendant(
      of: editor,
      matching: find.byType(EditableText),
    );
    // Window position of the result line that holds a text offset.
    double resultLine(String content) {
      final index = '\n'
          .allMatches(text.text.substring(0, text.text.indexOf(content)))
          .length;
      return tester.getTopLeft(editable).dy + index * row - result.offset;
    }

    double toolbar(int region) =>
        tester
            .getTopLeft(
              find.byKey(
                ValueKey('conflict-comparison-row-${region * 126 + 120}'),
              ),
            )
            .dy -
        GitLamaLayout.conflictRegionToolbarHeight;

    // The first conflict is in view in both panes, on one line of the window.
    expect(comparison.offset, greaterThan(0));
    expect(result.offset, greaterThan(0));
    expect(find.text('Conflict 1'), findsWidgets);
    expect(toolbar(0), closeTo(resultLine('<<<<<<< HEAD\nours 0'), 0.01));
    expect(
      toolbar(0),
      greaterThan(
        tester
            .getTopLeft(find.byKey(const Key('conflict-comparison-lines')))
            .dy,
      ),
    );

    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../build/evidence/ui-review/conflict-synchronized.png',
        ),
      );
    }

    // Unchanged text moves at the same pace in both panes.
    final comparisonStart = comparison.offset;
    final resultStart = result.offset;
    comparison.jumpTo(comparisonStart - 10 * row);
    await tester.pump();
    expect(result.offset, closeTo(resultStart - 10 * row, 0.01));
    comparison.jumpTo(comparisonStart);
    await tester.pump();

    await tester.tap(find.byTooltip('Next conflict'));
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2'), findsWidgets);
    expect(toolbar(1), closeTo(resultLine('<<<<<<< HEAD\nours 1'), 0.01));

    // Scrolling the result moves the comparison with it.
    final aligned = result.offset;
    result.jumpTo(aligned + 40 * row);
    await tester.pump();
    expect(comparison.offset, greaterThan(comparisonStart));
    result.jumpTo(aligned);
    await tester.pump();
    expect(toolbar(1), closeTo(resultLine('<<<<<<< HEAD\nours 1'), 0.01));

    // A drag that ends in a fling keeps the result in step while it settles.
    await tester.fling(
      find.byKey(const Key('conflict-comparison-lines')),
      const Offset(0, -200),
      1200,
    );
    await tester.pump();
    final released = result.offset;
    await tester.pump(const Duration(milliseconds: 80));
    expect(result.offset, greaterThan(released));
    await tester.pumpAndSettle();

    // A shorter result keeps the text after the conflict level again.
    await tester.tap(find.byTooltip('Previous conflict'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous conflict'));
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('conflict-take-0-current')));
    await tester.pumpAndSettle();
    expect(text.text, isNot(contains('theirs 0')));
    expect(toolbar(0), closeTo(resultLine('ours 0'), 0.01));
    comparison.jumpTo(comparison.offset + 20 * row);
    await tester.pump();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('conflict-comparison-row-140')))
          .dy,
      closeTo(resultLine('shared 1 14\n'), 0.01),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2'), findsWidgets);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets('ticked conflicts resolve together and list as resolved', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = _welcomeConflict.files.single;
    ConflictFile conflicted(String name) => ConflictFile(
      path: name.codeUnits,
      kind: template.kind,
      ancestor: template.ancestor,
      current: template.current,
      incoming: template.incoming,
      result: template.result,
      resultPresent: true,
      markerFree: false,
      regions: template.regions,
      fingerprint: BigInt.one,
      canUndoResolution: false,
    );
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository =
        _WelcomeRepository(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
              identity: RepositoryIdentity(
                commonGitDir: path,
                worktreeRoot: path,
                gitDir: path,
                kind: RepositoryKind.worktree,
                headKind: HeadKind.attached,
                gitMajor: 2,
                gitMinor: 50,
                gitPatch: 1,
              ),
              status: RepositoryStatus(
                workingTree: WorkingTreeState.dirty,
                ahead: BigInt.zero,
                behind: BigInt.zero,
                entries: const [],
                totalEntries: BigInt.zero,
                entriesTruncated: false,
                operations: const [],
              ),
            ),
          )
          ..resolveChosenSides = true
          ..conflictSnapshot = ConflictSnapshot(
            operation: ConflictOperationKind.merge,
            suggestedMessage: 'Merge topic',
            currentLabel: 'main'.codeUnits,
            incomingLabel: 'topic'.codeUnits,
            files: [
              conflicted('a.txt'),
              conflicted('b.txt'),
              conflicted('c.txt'),
              conflicted('d.txt'),
            ],
            resolvedUndoPaths: const [],
            canContinue: false,
            canSkip: false,
          );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conflict-bulk-current')), findsNothing);

    Finder tick(String name) => find.descendant(
      of: find.ancestor(
        of: find.text(name),
        matching: find.byType(GitLamaFileRow),
      ),
      matching: find.byType(MeridianCheckbox),
    );
    // A tick, then Shift and a tick further down, takes the range between.
    await tester.tap(tick('a.txt'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(tick('c.txt'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('conflict-bulk-incoming')));
    await tester.pumpAndSettle();
    expect(repository.conflictSideChoices, [
      'a.txt:incoming',
      'b.txt:incoming',
      'c.txt:incoming',
    ]);
    expect(find.text('d.txt'), findsWidgets);
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conflict-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conflict-bulk-current')));
    await tester.pumpAndSettle();
    expect(repository.conflictSideChoices.last, 'd.txt:current');
    expect(find.text('Resolved files'), findsOneWidget);
    expect(find.byKey(const ValueKey('conflict-resolved')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MeridianIconButton && widget.label == 'Undo resolution',
      ),
      findsNWidgets(4),
    );
    await tester.tap(find.byKey(const Key('conflict-undo-all')));
    await tester.pumpAndSettle();
    expect(repository.conflictUndos, ['a.txt', 'b.txt', 'c.txt', 'd.txt']);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets('keeping a deletion shows the choice and the resolved outcome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = _welcomeConflict.files.single;
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository =
        _WelcomeRepository(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
              identity: RepositoryIdentity(
                commonGitDir: path,
                worktreeRoot: path,
                gitDir: path,
                kind: RepositoryKind.worktree,
                headKind: HeadKind.attached,
                gitMajor: 2,
                gitMinor: 50,
                gitPatch: 1,
              ),
              status: RepositoryStatus(
                workingTree: WorkingTreeState.dirty,
                ahead: BigInt.zero,
                behind: BigInt.zero,
                entries: const [],
                totalEntries: BigInt.zero,
                entriesTruncated: false,
                operations: const [],
              ),
            ),
          )
          ..resolveChosenSides = true
          ..conflictSnapshot = ConflictSnapshot(
            operation: ConflictOperationKind.merge,
            suggestedMessage: 'Merge topic',
            currentLabel: 'main'.codeUnits,
            incomingLabel: 'topic'.codeUnits,
            files: [
              ConflictFile(
                path: 'gone.txt'.codeUnits,
                kind: ConflictFileKind.text,
                ancestor: template.ancestor,
                current: template.current,
                incoming: const ConflictSide(present: false, byteCount: 0),
                result: 'current\n'.codeUnits,
                resultPresent: true,
                markerFree: true,
                regions: const [],
                fingerprint: BigInt.one,
                canUndoResolution: false,
              ),
              ConflictFile(
                path: 'next.txt'.codeUnits,
                kind: template.kind,
                ancestor: template.ancestor,
                current: template.current,
                incoming: template.incoming,
                result: template.result,
                resultPresent: template.resultPresent,
                markerFree: template.markerFree,
                regions: template.regions,
                fingerprint: BigInt.two,
                canUndoResolution: false,
              ),
            ],
            resolvedUndoPaths: const [],
            canContinue: false,
            canSkip: false,
          );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();

    // A file deleted on one side asks for a decision, also in the list and
    // in the guide.
    expect(find.byKey(const Key('conflict-deletion-decision')), findsOneWidget);
    expect(
      find.byKey(
        ValueKey((
          'conflict-file-deleted',
          base64.encode('gone.txt'.codeUnits),
        )),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'One side deleted this file. Keep the deletion or keep the file.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 of 2 files resolved'), findsOneWidget);
    expect(find.byKey(const Key('conflict-result-editor')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conflict-keep-deletion')));
    await tester.pumpAndSettle();

    // The choice shows on its side, above the editor and in the result.
    expect(
      find.byKey(
        const ValueKey((
          'conflict-source-header',
          ConflictSideChoice.incoming,
          true,
        )),
      ),
      findsOneWidget,
    );
    expect(find.text('Resolving deletes this file'), findsOneWidget);
    expect(find.byKey(const Key('conflict-deletion-result')), findsOneWidget);
    expect(find.byKey(const Key('conflict-result-editor')), findsNothing);
    final resolveByDeleting = find.byWidgetPredicate(
      (widget) =>
          (widget is MeridianIconButton &&
              widget.label == 'Resolve by deleting') ||
          (widget is MeridianButton && widget.label == 'Resolve by deleting'),
    );
    expect(resolveByDeleting, findsOneWidget);
    expect(
      find.text('The file will be deleted. Resolve it to confirm.'),
      findsOneWidget,
    );

    // Choosing differently brings the result back; choosing again keeps it.
    await tester.tap(find.byKey(const Key('conflict-choose-differently')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conflict-deletion-decision')), findsOneWidget);
    expect(find.byKey(const Key('conflict-result-editor')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conflict-keep-deletion')));
    await tester.pumpAndSettle();

    await tester.tap(resolveByDeleting);
    await tester.pumpAndSettle();
    expect(repository.conflictSideChoices, ['gone.txt:incoming']);

    // The resolver moves on to the next file and says so.
    expect(
      find.text('Resolved gone.txt. Now showing next.txt.'),
      findsOneWidget,
    );
    expect(find.text('1 of 2 files resolved'), findsOneWidget);
    expect(find.byKey(const Key('conflict-deletion-decision')), findsNothing);
    await tester.tap(find.byKey(const Key('conflict-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conflict-bulk-current')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conflict-resolved')), findsOneWidget);
    expect(
      find.text('Check how each file was resolved, then continue.'),
      findsOneWidget,
    );
    expect(find.text('Deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets('Changes reopens a resolved operation awaiting continuation', (
    tester,
  ) async {
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: path,
          worktreeRoot: path,
          gitDir: path,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: const [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    )..conflictSnapshot = _resolvedWelcomeConflict;
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Resolve conflicts'), findsOneWidget);
    expect(find.byKey(const Key('conflict-merge-subject')), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets(
    'operations open explicitly and keep stable filters and actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      final operationRepository = _OperationRepository(
        OperationCenterSnapshot(
          entries: [
            OperationCenterEntry(
              activityId: BigInt.one,
              session: session,
              state: OperationCenterState.running,
              origin: OperationCenterOrigin.user,
              action: OperationCenterAction.fetch,
              startedAtUnixMs: BigInt.one,
              canCancel: false,
              canRetry: false,
              hasDetails: true,
            ),
            OperationCenterEntry(
              activityId: BigInt.from(2),
              session: session,
              state: OperationCenterState.failed,
              origin: OperationCenterOrigin.user,
              action: OperationCenterAction.push,
              startedAtUnixMs: BigInt.from(2),
              canCancel: false,
              canRetry: false,
              hasDetails: true,
            ),
          ],
          runningCount: 1,
          failedCount: 1,
          attentionCount: 0,
          truncated: false,
        ),
      );
      final operations = OperationCenterService(operationRepository);
      await operations.initialize();
      final runtime = await _runtime(
        _WelcomeRepository(
          activityPage: ActivityPage(
            records: [
              ActivityRecord(
                id: BigInt.one,
                executable: 'git',
                arguments: const ['fetch', '--prune', 'origin'],
                startedAtUnixMs: BigInt.one,
                status: ActivityStatus.running,
                stdout: Uint8List(0),
                stdoutTotalBytes: BigInt.zero,
                stdoutTruncated: false,
                stderr: Uint8List(0),
                stderrTotalBytes: BigInt.zero,
                stderrTruncated: false,
              ),
              for (var id = 3; id <= 66; id++)
                ActivityRecord(
                  id: BigInt.from(id),
                  executable: 'git',
                  arguments: const ['status'],
                  startedAtUnixMs: BigInt.from(id),
                  status: ActivityStatus.succeeded,
                  stdout: Uint8List(0),
                  stdoutTotalBytes: BigInt.zero,
                  stdoutTruncated: false,
                  stderr: Uint8List(0),
                  stderrTotalBytes: BigInt.zero,
                  stderrTruncated: false,
                ),
            ],
            evictedThroughId: null,
          ),
        ),
        _Picker(null),
        null,
        operations,
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));

      expect(find.byTooltip('Logbook'), findsOneWidget);
      await tester.tap(find.byTooltip('Logbook'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Logbook'), findsOneWidget);
      expect(
        (tester.getTopRight(find.byType(OperationCenterPanel)).dx -
                tester.getTopRight(find.byType(GitLamaCompass)).dx)
            .abs(),
        lessThan(1),
      );
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/evidence/ui-review/logbook.png'),
        );
      }
      expect(find.textContaining('Fetch'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.contains('git fetch --prune origin') == true,
        ),
        findsOneWidget,
      );
      expect(find.text('All'), findsWidgets);
      expect(find.textContaining('Push'), findsWidgets);
      final failedRow = find.byKey(const ValueKey('operation-2'));
      expect(
        tester
            .widget<MeridianIcon>(
              find.descendant(
                of: failedRow,
                matching: find.byType(MeridianIcon),
              ),
            )
            .color,
        MeridianTheme.of(tester.element(failedRow)).colors.danger,
      );
      operationRepository.current = OperationCenterSnapshot(
        entries: [
          OperationCenterEntry(
            activityId: BigInt.one,
            session: session,
            state: OperationCenterState.succeeded,
            origin: OperationCenterOrigin.user,
            action: OperationCenterAction.fetch,
            startedAtUnixMs: BigInt.one,
            finishedAtUnixMs: BigInt.from(3),
            canCancel: false,
            canRetry: false,
            hasDetails: true,
          ),
          operationRepository.current.entries.last,
        ],
        runningCount: 0,
        failedCount: 1,
        attentionCount: 0,
        truncated: false,
      );
      await operations.refresh();
      await tester.pump();
      expect(find.text('Logbook'), findsOneWidget);
      expect(find.text('No matching operations'), findsNothing);
      expect(find.textContaining('Push'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(OperationCenterPanel),
          matching: find.text('Details'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(OperationCenterPanel),
          matching: find.text('Activity'),
        ),
        findsNothing,
      );
      await tester.tap(failedRow);
      await tester.pump(MeridianDurations.select);
      await tester.ensureVisible(find.text('Dismiss'));
      await tester.pump(MeridianDurations.layout);
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(operationRepository.dismissedActivity, BigInt.from(2));
      expect(find.textContaining('Push'), findsWidgets);

      operationRepository.current = OperationCenterSnapshot(
        entries: [
          OperationCenterEntry(
            activityId: BigInt.from(3),
            session: session,
            state: OperationCenterState.warning,
            origin: OperationCenterOrigin.background,
            action: OperationCenterAction.refresh,
            startedAtUnixMs: BigInt.from(3),
            canCancel: false,
            canRetry: false,
            hasDetails: true,
          ),
        ],
        runningCount: 0,
        failedCount: 0,
        warningCount: 1,
        attentionCount: 0,
        truncated: false,
      );
      await operations.refresh();
      await tester.pump();
      expect(find.text('1 warning'), findsNothing);
      expect(find.text('1 recent operations'), findsNothing);
      final idleOperationsButton = tester.widget<MeridianIconButton>(
        find.byWidgetPredicate(
          (widget) => widget is MeridianIconButton && widget.label == 'Logbook',
        ),
      );
      expect(idleOperationsButton.active, isTrue);
      final warningRow = find.byKey(const ValueKey('operation-3'));
      expect(
        tester
            .widget<MeridianIcon>(
              find.descendant(
                of: warningRow,
                matching: find.byType(MeridianIcon),
              ),
            )
            .color,
        MeridianTheme.of(tester.element(warningRow)).colors.warning,
      );
      expect(
        tester
            .widget<MeridianIconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is MeridianIconButton &&
                    widget.label == 'Dismiss all',
              ),
            )
            .onPressed,
        isNotNull,
      );

      operationRepository.current = OperationCenterSnapshot(
        entries: [
          for (var id = 3; id <= 5; id++)
            OperationCenterEntry(
              activityId: BigInt.from(id),
              session: session,
              state: OperationCenterState.succeeded,
              origin: OperationCenterOrigin.background,
              action: OperationCenterAction.fetch,
              startedAtUnixMs: BigInt.from(id),
              canCancel: false,
              canRetry: false,
              hasDetails: false,
            ),
        ],
        runningCount: 0,
        failedCount: 0,
        attentionCount: 0,
        truncated: false,
      );
      await operations.refresh();
      await tester.pump();
      expect(find.textContaining('Fetched origin ×3'), findsOneWidget);
      expect(operations.current.entries, hasLength(3));

      await runtime.shutdown();
    },
  );

  testWidgets('requested refresh reports a scheduling failure', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(failRefresh: true);
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(
      find
          .byTooltip(
            'Reload this repository from disk. Fetch gets new commits from remotes; Pull also updates your branch.',
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(repository.refreshCount, 1);
    expect(find.text('Repository refresh failed.'), findsNWidgets(2));
    await runtime.shutdown();
  });

  testWidgets('activity copies the selected exact command and output', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repository = _WelcomeRepository(
      activityPage: ActivityPage(
        records: [
          ActivityRecord(
            id: BigInt.one,
            executable: 'git',
            arguments: const ['fetch', '--prune', 'origin'],
            startedAtUnixMs: BigInt.one,
            finishedAtUnixMs: BigInt.from(2),
            status: ActivityStatus.succeeded,
            exitCode: 0,
            stdout: Uint8List.fromList('updated main'.codeUnits),
            stdoutTotalBytes: BigInt.from(12),
            stdoutTruncated: false,
            stderr: Uint8List(0),
            stderrTotalBytes: BigInt.zero,
            stderrTruncated: false,
          ),
        ],
        evictedThroughId: null,
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Copy activity');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianListRow, 'Copy activity'));
    await tester.pumpAndSettle();
    expect(find.text('git fetch --prune origin'), findsWidgets);
    expect(find.text('updated main'), findsOneWidget);

    expect(clipboardText, 'git fetch --prune origin\n\nupdated main');
    expect(find.text('Activity command and output copied.'), findsOneWidget);
    await runtime.operationCenter.initialize();
    await tester.pumpAndSettle();
    repository.activityPage = const ActivityPage(
      records: [],
      evictedThroughId: null,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('git fetch --prune origin'), findsNothing);

    await runtime.shutdown();
  });

  testWidgets('welcome operation center controls the current clone attempt', (
    tester,
  ) async {
    final clones = _ControlledCloneRepository();
    final cloneAttempt = BigInt.from(41);
    final operationRepository = _OperationRepository(
      OperationCenterSnapshot(
        entries: [
          OperationCenterEntry(
            cloneAttemptId: cloneAttempt,
            state: OperationCenterState.running,
            origin: OperationCenterOrigin.user,
            action: OperationCenterAction.clone,
            startedAtUnixMs: BigInt.one,
            canCancel: true,
            canRetry: false,
            hasDetails: false,
          ),
        ],
        runningCount: 1,
        failedCount: 0,
        attentionCount: 0,
        truncated: false,
      ),
    );
    final operations = OperationCenterService(operationRepository);
    await operations.initialize();
    final runtime = await _runtime(
      _WelcomeRepository(),
      _Picker(null),
      clones,
      operations,
    );
    await runtime.repositorySessions.open('/repository');
    unawaited(
      runtime.repositorySessions.clone(
        source: '/source',
        destination: '/destination',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(_app(runtime));

    expect(find.byTooltip('Logbook'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Cancel');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianListRow, 'Cancel'));
    await tester.pump();
    expect(clones.cancelCount, 1);
    await tester.pump();
    expect(
      runtime.repositorySessions.currentClone?.phase,
      CloneAttemptPhase.canceled,
    );

    operationRepository.current = OperationCenterSnapshot(
      entries: [
        OperationCenterEntry(
          cloneAttemptId: cloneAttempt,
          state: OperationCenterState.failed,
          origin: OperationCenterOrigin.user,
          action: OperationCenterAction.clone,
          startedAtUnixMs: BigInt.one,
          finishedAtUnixMs: BigInt.from(2),
          canCancel: false,
          canRetry: true,
          hasDetails: false,
        ),
      ],
      runningCount: 0,
      failedCount: 1,
      attentionCount: 0,
      truncated: false,
    );
    await operations.refresh();
    await tester.pump(const Duration(milliseconds: 300));
    expect(operations.current.failedCount, 1);
    expect(find.byTooltip('Logbook'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Try again');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianListRow, 'Try again'));
    await tester.pumpAndSettle();
    expect(clones.retryCount, 1);
    expect(
      runtime.repositorySessions.currentClone?.phase,
      CloneAttemptPhase.failed,
    );
    await tester.tap(find.byTooltip('Logbook'));
    await tester.pump();
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pump();
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(clones.dismissCount, 1);

    await runtime.shutdown();
  });

  testWidgets('command palette confirms fresh index lock without retry', (
    tester,
  ) async {
    final repository = _WelcomeRepository(
      indexLock: IndexLockInspection(
        present: true,
        token: BigInt.from(77),
        sizeBytes: BigInt.from(14),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Search commands'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'index');
    await tester.pump();
    await tester.tap(find.text("Check Git's lock file (index.lock)…"));
    await tester.pumpAndSettle();
    expect(find.text("Remove Git's lock file?"), findsOneWidget);
    expect(find.textContaining("Git's lock file (14 bytes)"), findsOneWidget);
    await tester.tap(find.text('Remove lock'));
    await tester.pumpAndSettle();

    expect(repository.removedIndexLockToken, BigInt.from(77));
    expect(repository.removedIndexLockSession?.generation, 1);
    expect(repository.refreshCount, 0);
    expect(
      find.textContaining('The interrupted command was not run again'),
      findsOneWidget,
    );
    await runtime.shutdown();
  });

  testWidgets('command palette opens the bundled Licenses view', (
    tester,
  ) async {
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Licenses');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianListRow, 'Licenses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('GitLama'), findsWidgets);
    await runtime.shutdown();
  });

  testWidgets('command palette initializes a repository from the workspace', (
    tester,
  ) async {
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
    );
    final runtime = await _runtime(repository, _Picker('/new-repository'));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Initialize repository');
    await tester.pump();
    await tester.tap(find.text('Initialize repository').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('initialize-bare')), findsOneWidget);
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();

    expect(repository.initializedPath, '/new-repository');
    expect(
      find.text('That destination is already a Git repository.'),
      findsOneWidget,
    );
    await runtime.shutdown();
  });

  testWidgets('command palette closes the active repository tab', (
    tester,
  ) async {
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Close repository tab');
    await tester.pump();
    await tester.tap(find.text('Close repository tab').last);
    await tester.pumpAndSettle();

    expect(runtime.repositorySessions.workspace.tabs, isEmpty);
    expect(find.text('Start with a repository'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('next pane command and shortcut alternate Changes and History', (
    tester,
  ) async {
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.changes,
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Next pane');
    await tester.pump();
    await tester.tap(find.text('Next pane').last);
    await tester.pumpAndSettle();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.history,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.changes,
    );
    await runtime.shutdown();
  });

  testWidgets('find command and shortcut focus repository history search', (
    tester,
  ) async {
    final runtime = await _runtime(
      _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
        ),
        historyRows: const [
          HistoryTopologyRow(
            objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
      ),
      _Picker(null),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Find');
    await tester.pump();
    await tester.tap(find.text('Find').last);
    await tester.pumpAndSettle();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.history,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('history-query')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.tap(findWorkspacePaneAction('Changes'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      runtime.repositorySessions.workspace.activeTab?.navigation.pane,
      WorkspacePane.history,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('history-query')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await runtime.shutdown();
  });

  testWidgets('sidebar Insert route previews and confirms branch creation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 7),
        refs: const RepositoryRefs(
          branches: [
            RepositoryReference(
              name: [109, 97, 105, 110],
              target: '1111111111111111111111111111111111111111',
              head: true,
            ),
          ],
          remotes: [
            RepositoryRemote(
              name: [111, 114, 105, 103, 105, 110],
              displayUrl: [],
              branches: [
                RepositoryReference(
                  name: [109, 97, 105, 110],
                  target: '1111111111111111111111111111111111111111',
                ),
              ],
            ),
          ],
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          headObjectId: '1111111111111111111111111111111111111111',
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.settings.saveDurable(
      runtime.settings.current.copyWith(
        shortcutOverrides: const [
          ShortcutOverride(commandId: 'checkoutBranch', binding: 'Alt+B'),
        ],
      ),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    final before = tester.getTopLeft(find.text('BRANCHES'));
    expect(find.text('7'), findsOneWidget);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    await pointer.moveTo(tester.getCenter(find.text('BRANCHES')));
    await tester.pump();
    expect(find.bySemanticsLabel('Create branch…'), findsWidgets);
    expect(tester.getTopLeft(find.text('BRANCHES')), before);

    await tester.tap(find.text('BRANCHES'));
    await tester.sendKeyEvent(LogicalKeyboardKey.insert);
    await tester.pumpAndSettle();
    // The title and the verb on the primary button.
    expect(find.text('Create branch'), findsNWidgets(2));
    await tester.enterText(findMeridianField('Name'), 'topic');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianButton, 'Create branch'));
    await tester.pumpAndSettle();
    // The title and the verb on the primary button.
    expect(find.text('Create branch'), findsNWidgets(2));
    expect(find.textContaining('Create local branch topic'), findsOneWidget);
    expect(find.textContaining('Recovery history'), findsNothing);
    await tester.tap(find.widgetWithText(MeridianButton, 'Create branch'));
    await tester.pumpAndSettle();
    expect(repository.refMutationRequest?.name, 'topic');
    expect(repository.executedRefMutationToken, BigInt.from(88));
    expect(find.text('Git operation completed.'), findsOneWidget);

    await tester.tap(find.text('BRANCHES'));
    await tester.pump();
    final branchFocus = tester.widget<Focus>(
      find.byKey(const ValueKey('sidebar-ref-main')),
    );
    branchFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Check out branch'), findsNothing);
    expect(repository.refMutationRequest?.kind, RefMutationKind.createBranch);
    branchFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.text('Edit branch'), findsOneWidget);
    expect(
      tester.widget<TextField>(findMeridianField('Name')).controller?.text,
      'main',
    );
    await tester.enterText(findMeridianField('Name'), 'trunk');
    await tester.enterText(findMeridianField('Upstream'), 'origin/main');
    await tester.pumpAndSettle();
    repository.refMutationRequests.clear();
    await tester.tap(find.byKey(const ValueKey('edit-branch-save')));
    await tester.pumpAndSettle();
    // The rename runs first; the upstream then addresses the new name.
    expect(
      [
        for (final request in repository.refMutationRequests)
          (request.kind, request.name, request.secondName),
      ],
      [
        (RefMutationKind.renameBranch, 'main', 'trunk'),
        (RefMutationKind.setUpstream, 'trunk', 'origin/main'),
      ],
    );
    expect(find.text('Git operation completed.'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('sidebar exposes every QSpline add section and Insert route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(
      _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
        ),
        lfsAvailable: true,
      ),
      _Picker(null),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    for (final label in [
      'Branches',
      'Remotes',
      'Stashes',
      'Tags',
      'Worktrees',
      'Git LFS',
      'Integrations',
      'Pull requests',
    ]) {
      expect(find.text(label.toUpperCase()), findsOneWidget);
    }

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    await pointer.moveTo(tester.getCenter(find.text('GIT LFS')));
    await tester.pump();
    expect(find.bySemanticsLabel('Track LFS pattern…'), findsOneWidget);

    await tester.tap(find.text('GIT LFS'));
    await tester.sendKeyEvent(LogicalKeyboardKey.insert);
    await tester.pumpAndSettle();
    expect(find.text('Repository extensions'), findsOneWidget);
    expect(findMeridianField('Tracking pattern'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('extension-lfs-pattern')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('INTEGRATIONS'));
    await tester.sendKeyEvent(LogicalKeyboardKey.insert);
    await tester.pumpAndSettle();
    expect(find.text('Tools and commands'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('integration-id')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await runtime.shutdown();
  });

  testWidgets('branch drag previews prediction and executes a named merge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const main = '1111111111111111111111111111111111111111';
    const topic = '2222222222222222222222222222222222222222';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 2),
        refs: const RepositoryRefs(
          branches: [
            RepositoryReference(
              name: [109, 97, 105, 110],
              target: main,
              head: true,
            ),
            RepositoryReference(name: [116, 111, 112, 105, 99], target: topic),
          ],
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          headObjectId: main,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    final drag = await tester.startGesture(
      tester.getCenter(find.text('topic')),
    );
    await drag.moveTo(tester.getCenter(find.text('main')));
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('Integrate branch'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('branch-integration-merge')));
    await tester.pumpAndSettle();
    // The title and the verb on the primary button.
    expect(find.text('Merge branch'), findsNWidgets(2));
    expect(find.text('topic'), findsWidgets);
    await tester.tap(find.widgetWithText(MeridianButton, 'Merge branch'));
    await tester.pumpAndSettle();
    expect(find.text('Review merge'), findsOneWidget);
    expect(
      find.textContaining('Brings the changes of the selected branch'),
      findsOneWidget,
    );
    // The review names the branches and the conflict check's result as
    // facts, with the check's caveat below them.
    expect(find.text('Source branch'), findsOneWidget);
    expect(find.text('Current branch'), findsOneWidget);
    expect(find.text('Conflicts'), findsOneWidget);
    expect(find.text('None expected'), findsOneWidget);
    expect(
      find.textContaining('conflict check is an estimate'),
      findsOneWidget,
    );
    await tester.tap(find.text('Git command details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('git merge --no-edit --ff'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Merge branch'));
    await tester.pumpAndSettle();
    expect(repository.historyMutationRequest?.kind, HistoryMutationKind.merge);
    expect(repository.historyMutationRequest?.targets, [topic]);
    expect(repository.executedHistoryMutationToken, BigInt.from(85));
    expect(find.text('History operation completed.'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('a running merge blocks only its own repository tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const main = '1111111111111111111111111111111111111111';
    const topic = '2222222222222222222222222222222222222222';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 2),
        refs: RepositoryRefs(
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: [],
              branches: [],
            ),
          ],
          branches: [
            RepositoryReference(
              name: [109, 97, 105, 110],
              target: main,
              head: true,
            ),
            RepositoryReference(name: [116, 111, 112, 105, 99], target: topic),
          ],
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          headObjectId: main,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: [],
        ),
      ),
    );
    final gate = Completer<HistoryMutationExecutionResult>();
    repository.historyMutationGate = gate;
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/first');
    await runtime.repositorySessions.open('/second');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(find.text('topic')),
    );
    await drag.moveTo(tester.getCenter(find.text('main')));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('branch-integration-merge')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MeridianButton, 'Merge branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MeridianButton, 'Merge branch'));
    // The busy spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The merge says what it does, over its own repository only.
    expect(find.text('Merging topic into main…'), findsOneWidget);
    expect(find.byType(MeridianDialog), findsNothing);
    expect(
      tester
          .widget<MeridianToolbarButton>(
            find.byKey(const ValueKey('toolbar-action-fetch')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('first'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Merging topic into main…'), findsNothing);
    expect(
      tester
          .widget<MeridianToolbarButton>(
            find.byKey(const ValueKey('toolbar-action-fetch')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('second'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Merging topic into main…'), findsOneWidget);

    await tester.tap(find.widgetWithText(MeridianButton, 'Cancel'));
    await tester.pump();
    expect(repository.historyMutationCancels, 1);
    expect(find.widgetWithText(MeridianButton, 'Canceling…'), findsOneWidget);
    gate.complete(
      const HistoryMutationExecutionResult(
        state: HistoryMutationExecutionState.completed,
        activityIds: ['85'],
        conflictingPaths: [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Merging topic into main…'), findsNothing);
    expect(find.text('History operation completed.'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('branch context merge stays interactive after the native menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const main = '1111111111111111111111111111111111111111';
    const topic = '2222222222222222222222222222222222222222';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 2),
        refs: const RepositoryRefs(
          branches: [
            RepositoryReference(
              name: [109, 97, 105, 110],
              target: main,
              head: true,
            ),
            RepositoryReference(name: [116, 111, 112, 105, 99], target: topic),
          ],
        ),
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          headObjectId: main,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    Future<void> openMerge() async {
      await tester.tap(find.text('topic'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge branch…').last);
      await tester.pumpAndSettle();
      expect(find.text('Source branch'), findsOneWidget);
      expect(find.text('Merge mode'), findsOneWidget);
    }

    await openMerge();
    await tester.tap(find.widgetWithText(MeridianButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Source branch'), findsNothing);
    await openMerge();
    await tester.tap(find.widgetWithText(MeridianButton, 'Merge branch'));
    await tester.pumpAndSettle();
    expect(find.text('Review merge'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets(
    'branch drag selects rebase and edits a stable instruction plan',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const main = '1111111111111111111111111111111111111111';
      const topic = '2222222222222222222222222222222222222222';
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          refCounts: const RepositoryRefCounts(branches: 2),
          refs: const RepositoryRefs(
            branches: [
              RepositoryReference(
                name: [109, 97, 105, 110],
                target: main,
                head: true,
              ),
              RepositoryReference(
                name: [116, 111, 112, 105, 99],
                target: topic,
              ),
            ],
          ),
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            headObjectId: main,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: [],
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await runtime.settings.saveDurable(
        runtime.settings.current.copyWith(
          shortcutOverrides: const [
            ShortcutOverride(commandId: 'rebaseDrop', binding: 'Alt+8'),
          ],
        ),
      );
      await tester.pumpWidget(_app(runtime));
      await tester.tap(findWorkspacePaneAction('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('command-palette-query')),
        'Interactive rebase',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(MeridianListRow, 'Interactive rebase…'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rebase onto branch'), findsOneWidget);
      expect(find.text('topic'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final drag = await tester.startGesture(
        tester.getCenter(find.text('topic')),
      );
      await drag.moveTo(tester.getCenter(find.text('main')));
      await drag.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('branch-integration-rebase')));
      await tester.pumpAndSettle();
      expect(find.text('Interactive rebase'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/evidence/ui-review/rebase-editor.png'),
        );
      }

      await tester.tap(find.byType(MeridianSelect<RebaseAction>).last);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(
        tester
            .widget<MeridianSelect<RebaseAction>>(
              find.byType(MeridianSelect<RebaseAction>).last,
            )
            .value,
        RebaseAction.drop,
      );

      await tester.tap(find.byType(MeridianSelect<RebaseAction>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reword').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        findMeridianField('Replacement commit message'),
        'rewritten topic',
      );
      await tester.tap(find.byTooltip('Move instruction down').first);
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Start rebase'));
      await tester.pumpAndSettle();
      expect(find.text('Review rebase'), findsOneWidget);
      await tester.tap(find.widgetWithText(MeridianButton, 'Start rebase'));
      await tester.pumpAndSettle();
      expect(repository.rebaseInstructions!.map((item) => item.id), [
        BigInt.two,
        BigInt.one,
      ]);
      expect(
        String.fromCharCodes(
          repository.rebaseInstructions![1].replacementMessage!,
        ),
        'rewritten topic',
      );
      expect(repository.executedRebaseToken, BigInt.from(87));
      expect(find.text('Rebase completed.'), findsOneWidget);
      await runtime.shutdown();
    },
  );

  testWidgets('the workspace offers no repository undo', (tester) async {
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    for (final query in ['Undo', 'Redo', 'Recovery history']) {
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, query);
      await tester.pump();
      expect(find.widgetWithText(MeridianListRow, query), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    // Ctrl+Z and Cmd+Z belong to text editing again.
    expect(
      AppCommandRegistry.commands.where(
        (definition) =>
            definition.shortcut == 'Ctrl+Z' ||
            definition.macShortcut == 'Cmd+Z',
      ),
      isEmpty,
    );

    await runtime.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'named snapshots create, inspect, and restore with acknowledgement',
    (tester) async {
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.zero,
          phase: RepositoryPhase.ready,
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Snapshots');
      await tester.pump();
      await tester.tap(find.text('Snapshots').last);
      await tester.pumpAndSettle();
      expect(find.text('No snapshots yet'), findsOneWidget);
      await tester.enterText(
        findMeridianField('Snapshot name'),
        'before refactor',
      );
      await tester.pump();
      expect(
        tester
            .widget<MeridianButton>(
              find.widgetWithText(MeridianButton, 'Create snapshot'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(MeridianButton, 'Create snapshot'));
      await tester.pumpAndSettle();
      expect(repository.namedSnapshotEntries, hasLength(1));
      expect(find.text('before refactor'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/evidence/ui-review/snapshots.png'),
        );
      }
      // Deleting a snapshot is marked as dangerous and comes last.
      final snapshotMenu = tester
          .widget<NativeMenuButton<String>>(
            find.byType(NativeMenuButton<String>),
          )
          .itemBuilder(tester.element(find.byType(NativeMenuButton<String>)));
      expect(snapshotMenu.last.value, 'delete');
      expect(snapshotMenu.last.danger, isTrue);
      expect(snapshotMenu.where((item) => item.danger), [snapshotMenu.last]);
      await tester.tap(find.byType(NativeMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Restore “before refactor”?'), findsOneWidget);
      await tester.tap(find.byType(MeridianCheckbox).last);
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Restore'));
      await tester.pumpAndSettle();
      expect(repository.namedSnapshotRestoreExecuted, isTrue);
      await runtime.shutdown();
    },
  );

  testWidgets('repository extensions expose worktree and capability states', (
    tester,
  ) async {
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.zero,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
          worktreeRoot: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/repository'.codeUnits,
          ),
          gitDir: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/repository/.git'.codeUnits,
          ),
          commonGitDir: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/repository/.git'.codeUnits,
          ),
        ),
      ),
    );
    final picker = _Picker('/worktrees/tópico with spaces');
    final runtime = await _runtime(repository, picker);
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Add worktree');
    await tester.pump();
    await tester.tap(find.text('Add worktree…').last);
    await tester.pumpAndSettle();
    expect(find.text('Repository extensions'), findsOneWidget);
    expect(find.textContaining('Current worktree'), findsOneWidget);
    expect(
      tester
          .widget<MeridianButton>(find.widgetWithText(MeridianButton, 'Delete'))
          .onPressed,
      isNull,
    );
    expect(find.text('Git LFS is not installed or unavailable.'), findsNothing);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('../build/evidence/ui-review/worktrees.png'),
      );
    }
    await tester.tap(find.widgetWithText(MeridianButton, 'Create worktree'));
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MeridianDialog),
        matchesGoldenFile('../build/evidence/ui-review/worktree-create.png'),
      );
    }
    final create = find.widgetWithText(MeridianButton, 'Create worktree').last;
    expect(tester.widget<MeridianButton>(create).onPressed, isNull);
    await tester.tap(find.byKey(const Key('extension-worktree-choose-folder')));
    await tester.pumpAndSettle();
    expect(picker.canCreateDirectories, isTrue);
    expect(picker.directoryCalls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('extension-worktree-path')))
          .controller!
          .text,
      '/worktrees/tópico with spaces',
    );
    expect(tester.widget<MeridianButton>(create).onPressed, isNotNull);
    expect(repository.extensionRequest, isNull);
    await tester.enterText(
      find.byKey(const Key('extension-worktree-path')),
      '/worktrees/tópico with spaces-edited',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(MeridianButton, 'Create worktree').last,
    );
    await tester.pumpAndSettle();
    expect(
      repository.extensionRequest?.kind,
      RepositoryExtensionMutationKind.worktreeCreate,
    );
    expect(repository.extensionRequest?.reference, 'HEAD');
    expect(
      repository.extensionRequest?.worktreeRoot?.units,
      utf8.encode('/worktrees/tópico with spaces-edited'),
    );
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets('worktree folder picker preserves input on cancel and failure', (
    tester,
  ) async {
    final repository = _WelcomeRepository();
    final picker = _Picker(null);
    final runtime = await _runtime(repository, picker);
    await _openCreateWorktree(tester, runtime);
    final path = find.byKey(const Key('extension-worktree-path'));
    final choose = find.byKey(const Key('extension-worktree-choose-folder'));
    final create = find.widgetWithText(MeridianButton, 'Create worktree').last;
    await tester.enterText(path, '/worktrees/typed');
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(path).controller!.text, '/worktrees/typed');
    expect(tester.widget<MeridianButton>(create).onPressed, isNotNull);
    expect(repository.extensionRequest, isNull);

    picker.pendingDirectory = Completer<String?>();
    await tester.tap(choose);
    await tester.pump();
    expect(tester.widget<MeridianButton>(choose).onPressed, isNull);
    expect(tester.widget<MeridianButton>(create).onPressed, isNull);
    picker.pendingDirectory!.completeError(StateError('private picker detail'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(path).controller!.text, '/worktrees/typed');
    expect(
      find.text('Could not open the folder picker. Try again or enter a path.'),
      findsOneWidget,
    );
    expect(find.textContaining('private picker detail'), findsNothing);
    expect(tester.widget<MeridianButton>(choose).onPressed, isNotNull);
    expect(tester.widget<MeridianButton>(create).onPressed, isNotNull);
    picker.pendingDirectory = null;
    picker.path = '/worktrees/retried';
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(path).controller!.text,
      '/worktrees/retried',
    );
    expect(
      find.text('Could not open the folder picker. Try again or enter a path.'),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(MeridianButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repository.extensionRequest, isNull);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets(
    'late folder selection cannot change a reopened worktree dialog',
    (tester) async {
      final repository = _WelcomeRepository();
      final picker = _Picker(null)..pendingDirectory = Completer<String?>();
      final runtime = await _runtime(repository, picker);
      await _openCreateWorktree(tester, runtime);
      final path = find.byKey(const Key('extension-worktree-path'));
      await tester.enterText(path, '/worktrees/typed');
      await tester.tap(
        find.byKey(const Key('extension-worktree-choose-folder')),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MeridianButton, 'Create worktree'));
      await tester.pumpAndSettle();
      picker.pendingDirectory!.complete('/worktrees/late');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(path).controller!.text,
        '/worktrees/typed',
      );
      expect(repository.extensionRequest, isNull);
      await tester.tap(find.widgetWithText(MeridianButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await runtime.shutdown();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'worktree folder selector fits enlarged German text $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(900, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // Keep the inventory empty so this measures the creation dialog,
        // independently of the background worktree row's action layout.
        final runtime = await _runtime(
          _WelcomeRepository(worktreeEntries: const []),
          _Picker(null),
        );
        await _openCreateWorktree(
          tester,
          runtime,
          locale: const Locale('de'),
          brightness: brightness,
        );
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        final choose = find.byKey(
          const Key('extension-worktree-choose-folder'),
        );
        await tester.ensureVisible(choose);
        await tester.pumpAndSettle();
        expect(choose, findsOneWidget);
        expect(find.text('Ordner auswählen…'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
          await expectLater(
            find.byType(MeridianDialog),
            matchesGoldenFile(
              '../build/evidence/ui-review/worktree-create-de-200-${brightness.name}.png',
            ),
          );
        }
        await tester.tap(choose);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cancel = find.widgetWithText(MeridianButton, 'Abbrechen');
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await runtime.shutdown();
      },
    );
  }

  testWidgets('worktree count expands to the worktree rows', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(worktrees: 3),
      ),
      worktreeEntries: [
        for (final (index, branch) in ['main', 'feature', 'release'].indexed)
          WorktreeEntry(
            worktreeRoot: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/repository-$index'.codeUnits,
            ),
            gitDir: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/repository-$index/.git'.codeUnits,
            ),
            commonGitDir: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/repository/.git'.codeUnits,
            ),
            branch: 'refs/heads/$branch'.codeUnits,
            locked: false,
            prunable: false,
            current: index == 0,
          ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('release'), findsOneWidget);
    await tester.tap(find.text('WORKTREES'));
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsNothing);
    await tester.tap(find.text('WORKTREES'));
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsOneWidget);
    await runtime.shutdown();
  });

  for (final brightness in Brightness.values) {
    for (final locale in [const Locale('en'), const Locale('de')]) {
      testWidgets(
        'current worktree stays marked and refreshes its branch ${brightness.name} ${locale.languageCode}',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          WorktreeEntry entry(String? branch, {bool current = true}) =>
              WorktreeEntry(
                worktreeRoot: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units:
                      (current ? '/repository' : '/repository-other').codeUnits,
                ),
                gitDir: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: '/repository/.git'.codeUnits,
                ),
                commonGitDir: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: '/repository/.git'.codeUnits,
                ),
                branch: branch == null ? null : 'refs/heads/$branch'.codeUnits,
                locked: false,
                prunable: false,
                current: current,
              );
          RepositorySnapshot snapshot(int revision) => RepositorySnapshot(
            revision: BigInt.from(revision),
            phase: RepositoryPhase.ready,
            refCounts: const RepositoryRefCounts(worktrees: 2),
          );
          final repository = _WelcomeRepository(
            snapshot: snapshot(1),
            worktreeEntries: [
              entry('old-branch'),
              entry('other', current: false),
            ],
          );
          final runtime = await _runtime(repository, _Picker(null));
          await runtime.repositorySessions.open('/repository');
          await tester.pumpWidget(
            _app(runtime, brightness: brightness, locale: locale),
          );
          await tester.pumpAndSettle();
          final row = find.byKey(const ValueKey('sidebar-ref-/repository'));
          expect(MediaQuery.textScalerOf(tester.element(row)).scale(10), 13);
          MeridianListRow currentRow() => tester.widget<MeridianListRow>(
            find.descendant(of: row, matching: find.byType(MeridianListRow)),
          );
          final currentLabel = AppLocalizations.of(
            tester.element(row),
          ).extensionWorktreeCurrent;
          expect(currentRow().emphasized, isTrue);
          expect(currentRow().semanticValue, currentLabel);
          expect(
            find.descendant(of: row, matching: find.byTooltip(currentLabel)),
            findsOneWidget,
          );
          expect(find.text(currentLabel), findsNothing);
          final icon = find.descendant(
            of: row,
            matching: find.byType(MeridianIcon),
          );
          expect(tester.widget<MeridianIcon>(icon).name, 'check');
          final otherRow = tester.widget<MeridianListRow>(
            find.descendant(
              of: find.byKey(const ValueKey('sidebar-ref-/repository-other')),
              matching: find.byType(MeridianListRow),
            ),
          );
          expect(otherRow.emphasized, isFalse);
          if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
            await expectLater(
              find.byType(Scaffold).first,
              matchesGoldenFile(
                '../build/evidence/worktrees/current-${brightness.name}-${locale.languageCode}.png',
              ),
            );
          }
          await tester.tap(find.text('old-branch'));
          await tester.pumpAndSettle();
          final focus = tester.widget<Focus>(row).focusNode!;
          focus.requestFocus();
          await tester.pump();
          expect(currentRow().selected, isTrue);
          final reads = repository.extensionReads;
          // Selection and unrelated shell rebuilds must not reread Git.
          await tester.pump();
          expect(repository.extensionReads, reads);
          repository.worktreeEntries = [
            entry('main'),
            entry('other', current: false),
          ];
          repository.pendingEvents.add(
            RepositorySessionEvent(
              kind: RepositorySessionEventKind.snapshot,
              snapshot: snapshot(2),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pumpAndSettle();
          expect(find.text('old-branch'), findsNothing);
          expect(currentRow().title, 'main');
          expect(currentRow().selected, isTrue);
          expect(identical(tester.widget<Focus>(row).focusNode, focus), isTrue);
          expect(focus.hasFocus, isTrue);
          expect(repository.extensionReads, reads + 1);
          // A detached HEAD falls back to the folder without losing the mark.
          repository.worktreeEntries = [
            entry(null),
            entry('other', current: false),
          ];
          repository.pendingEvents.add(
            RepositorySessionEvent(
              kind: RepositorySessionEventKind.snapshot,
              snapshot: snapshot(3),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pumpAndSettle();
          expect(currentRow().title, 'repository');
          expect(currentRow().emphasized, isTrue);
          expect(currentRow().semanticValue, currentLabel);
          expect(tester.takeException(), isNull);
          semantics.dispose();
          await runtime.shutdown();
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('worktree refresh ignores an older inventory completing late', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RepositorySnapshot snapshot(int revision, {int count = 1}) =>
        RepositorySnapshot(
          revision: BigInt.from(revision),
          phase: RepositoryPhase.ready,
          refCounts: RepositoryRefCounts(worktrees: count),
        );
    WorktreeEntry entry(String branch) => WorktreeEntry(
      worktreeRoot: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository'.codeUnits,
      ),
      gitDir: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository/.git'.codeUnits,
      ),
      commonGitDir: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository/.git'.codeUnits,
      ),
      branch: 'refs/heads/$branch'.codeUnits,
      locked: false,
      prunable: false,
      current: true,
    );
    RepositoryExtensionInventory inventory(String branch) =>
        RepositoryExtensionInventory(
          worktrees: [entry(branch)],
          submodules: const [],
          lfsAvailable: false,
          lfsUnavailableReason: true,
          lfsEntries: const [],
          activityIds: const [],
        );
    final repository = _WelcomeRepository(
      snapshot: snapshot(1),
      worktreeEntries: [entry('first')],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final older = Completer<RepositoryExtensionInventory>();
    final newer = Completer<RepositoryExtensionInventory>();
    repository.extensionBarriers.addAll([older, newer]);
    for (final revision in [2, 3]) {
      repository.pendingEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: snapshot(revision),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    }
    newer.complete(inventory('newest'));
    await tester.pumpAndSettle();
    expect(find.text('newest'), findsOneWidget);
    older.complete(inventory('obsolete'));
    await tester.pumpAndSettle();
    expect(find.text('newest'), findsOneWidget);
    expect(find.text('obsolete'), findsNothing);
    // A zero count must also clear FutureBuilder's retained inventory.
    repository.pendingEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(4, count: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('newest'), findsNothing);
    await runtime.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('worktree rows open their folder or delete them from a menu', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    NativePathIdentity path(String value) => NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: value.codeUnits,
    );
    final root = path('/repository');
    final repository = _WelcomeRepository(
      integrationCandidates: [
        IntegrationCandidate(
          id: 'macos-file-manager',
          kind: IntegrationKind.fileManager,
          executable: path('/usr/bin/open'),
          launchMode: IntegrationLaunchMode.detached,
        ),
      ],
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(worktrees: 2),
        identity: RepositoryIdentity(
          commonGitDir: path('/repository/.git'),
          worktreeRoot: root,
          gitDir: path('/repository/.git'),
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
      ),
      worktreeEntries: [
        for (final (index, branch) in ['main', 'feature'].indexed)
          WorktreeEntry(
            worktreeRoot: index == 0 ? root : path('/repository-feature'),
            gitDir: index == 0
                ? path('/repository/.git')
                : path('/repository/.git/worktrees/feature'),
            commonGitDir: path('/repository/.git'),
            branch: 'refs/heads/$branch'.codeUnits,
            locked: false,
            prunable: false,
            current: index == 0,
          ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    final previousPresenter = nativeMenuTestPresenter;
    addTearDown(() => nativeMenuTestPresenter = previousPresenter);
    final shown = <Menu>[];
    String? choose;
    nativeMenuTestPresenter = (context, menu, position) async {
      shown.add(menu);
      final action = menu.children.whereType<MenuAction>().where(
        (item) => item.title == choose,
      );
      if (action.isEmpty) return MenuResult(itemSelected: false);
      action.single.callback();
      return MenuResult(itemSelected: true);
    };
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    Future<List<MenuAction>> menuOf(String row, {String? select}) async {
      shown.clear();
      choose = select;
      await tester.tap(find.text(row), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      return shown.single.children.whereType<MenuAction>().toList();
    }

    final current = await menuOf('main');
    expect(
      current.map((item) => item.title),
      containsAllInOrder(['Open in Finder', 'Delete worktree…']),
    );
    expect(current.map((item) => item.title), isNot(contains('Open')));
    expect(
      current
          .firstWhere((item) => item.title == 'Delete worktree…')
          .attributes
          .disabled,
      isTrue,
    );
    final linked = await menuOf('feature');
    expect(
      linked.map((item) => item.title),
      containsAllInOrder(['Open', 'Open in Finder', 'Delete worktree…']),
    );
    expect(
      linked
          .firstWhere((item) => item.title == 'Delete worktree…')
          .attributes
          .disabled,
      isFalse,
    );
    // Deleting is marked as dangerous and comes last, after copying.
    for (final menu in [current, linked]) {
      expect(menu.last.title, 'Delete worktree…');
      expect(menu.last.attributes.destructive, isTrue);
      expect(menu.where((item) => item.attributes.destructive), [menu.last]);
      expect(menu.map((item) => item.title), contains('Copy name'));
    }

    await menuOf('feature', select: 'Open in Finder');
    expect(repository.integrationRequest?.kind, IntegrationKind.fileManager);
    expect(repository.integrationRequest?.configured?.arguments, const [
      '{file}',
    ]);
    expect(
      String.fromCharCodes(
        repository.integrationRequest!.variables.file!.units,
      ),
      '/repository-feature',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    repository.extensionResult = const RepositoryExtensionMutationResult(
      state: RepositoryExtensionMutationState.failed,
      activityIds: [],
    );
    await menuOf('feature', select: 'Delete worktree…');
    expect(find.text('Delete worktree?'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      repository.extensionRequest?.kind,
      RepositoryExtensionMutationKind.worktreeDelete,
    );
    expect(
      String.fromCharCodes(repository.extensionRequest!.worktreeRoot!.units),
      '/repository-feature',
    );
    final error = 'The repository extension operation failed.';
    // The worktree list keeps its error; the failed action opens a dialog.
    expect(find.widgetWithText(MeridianBanner, error), findsOneWidget);
    final dialog = find.byKey(const ValueKey('operation-failure-dialog'));
    expect(
      find.descendant(of: dialog, matching: find.text(error)),
      findsOneWidget,
    );
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('../build/evidence/worktrees/deletion-error.png'),
      );
    }
    await tester.tap(find.byKey(const ValueKey('operation-failure-close')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    // The local error remains after the transient status-bar message expires.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MeridianBanner, error), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
    repository.extensionResult = const RepositoryExtensionMutationResult(
      state: RepositoryExtensionMutationState.completed,
      activityIds: [],
    );
    await menuOf('feature', select: 'Delete worktree…');
    repository.worktreeEntries = [repository.worktreeEntries!.first];
    await tester.tap(find.widgetWithText(MeridianButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsNothing);
    expect(find.widgetWithText(MeridianBanner, error), findsNothing);
    await runtime.shutdown();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'the branch filter editor focuses, combines and clears branches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _WelcomeRepository(
        snapshot: _branchFilterSnapshot(),
        historyRows: _branchFilterRows,
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(findWorkspacePaneAction('History'));
      await tester.pumpAndSettle();

      Finder row(String id) => find.byKey(ValueKey('history-row-$id'));
      Future<void> openEditor() async {
        await tester.tap(find.byKey(const ValueKey('history-branch-filter')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('branch-filter-list')),
          findsOneWidget,
        );
      }

      List<String> remembered() => runtime
          .repositorySessions
          .workspace
          .activeTab!
          .navigation
          .branchFilter
          .references;

      for (final id in [
        _filterMain,
        _filterTopic,
        _filterFeature,
        _filterBase,
      ]) {
        expect(row(id), findsOneWidget);
      }
      await openEditor();
      // The checked-out branch leads, remote branches follow in a tree.
      expect(
        tester
            .widgetList<MeridianListRow>(find.byType(MeridianListRow))
            .map((row) => row.title),
        containsAllInOrder(['Branches', 'main', 'topic', 'origin', 'feature']),
      );

      // Typing narrows the list; Enter shows only the highlighted branch.
      await tester.enterText(
        find.byKey(const ValueKey('branch-filter-search')),
        'feat',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('refs/heads/topic')), findsNothing);
      expect(
        find.byKey(const ValueKey('refs/remotes/origin/feature')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('branch-filter-list')), findsNothing);
      expect(repository.branchFilterRequests.last.references, [
        'refs/remotes/origin/feature',
      ]);
      expect(row(_filterFeature), findsOneWidget);
      expect(row(_filterBase), findsOneWidget);
      expect(row(_filterMain), findsNothing);
      expect(row(_filterTopic), findsNothing);
      expect(find.text('Branches (1)'), findsOneWidget);
      expect(remembered(), ['refs/remotes/origin/feature']);

      // Clicking a row adds it at once and keeps the editor open.
      await openEditor();
      await tester.tap(find.byKey(const ValueKey('refs/heads/topic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('branch-filter-list')), findsOneWidget);
      expect(find.text('2 branches shown'), findsOneWidget);
      expect(repository.branchFilterRequests.last.references, [
        'refs/heads/topic',
        'refs/remotes/origin/feature',
      ]);
      expect(row(_filterTopic), findsOneWidget);
      expect(row(_filterMain), findsNothing);

      await tester.tap(find.byKey(const ValueKey('branch-filter-show-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('branch-filter-list')), findsNothing);
      expect(repository.branchFilterRequests.last, HistoryBranchFilter.none);
      expect(row(_filterMain), findsOneWidget);
      expect(find.text('Branches'), findsOneWidget);
      expect(remembered(), isEmpty);
      await runtime.shutdown();
    },
  );

  testWidgets('branch menus focus, add, remove and clear the graph filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WelcomeRepository(
      snapshot: _branchFilterSnapshot(),
      historyRows: _branchFilterRows,
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    final previousPresenter = nativeMenuTestPresenter;
    addTearDown(() => nativeMenuTestPresenter = previousPresenter);
    final shown = <Menu>[];
    String? choose;
    nativeMenuTestPresenter = (context, menu, position) async {
      shown.add(menu);
      final action = menu.children.whereType<MenuAction>().where(
        (item) => item.title == choose,
      );
      if (action.isEmpty) return MenuResult(itemSelected: false);
      action.single.callback();
      return MenuResult(itemSelected: true);
    };
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    Future<List<String>> menuOf(String branch, {String? select}) async {
      shown.clear();
      choose = select;
      await tester.tap(
        find.widgetWithText(MeridianListRow, branch).first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      return shown.single.children
          .whereType<MenuAction>()
          .map((item) => item.title ?? '')
          .toList();
    }

    HistoryBranchFilter filter() =>
        runtime.repositorySessions.workspace.activeTab!.navigation.branchFilter;

    expect(
      await menuOf('topic'),
      containsAllInOrder(['Show only this branch', 'Add to graph filter']),
    );
    expect(await menuOf('topic'), isNot(contains('Show all branches')));
    const filteredMark = ValueKey('sidebar-ref-filtered');
    expect(find.byKey(filteredMark), findsNothing);
    await menuOf('topic', select: 'Add to graph filter');
    expect(filter().references, ['refs/heads/topic']);
    // The sidebar marks the branch the graph is filtered to.
    expect(
      find.descendant(
        of: find.widgetWithText(MeridianListRow, 'topic').first,
        matching: find.byKey(filteredMark),
      ),
      findsOneWidget,
    );
    expect(find.byKey(filteredMark), findsOneWidget);

    // Focused on topic: removing and clearing remain.
    final focused = await menuOf('topic');
    expect(focused, isNot(contains('Show only this branch')));
    expect(
      focused,
      containsAllInOrder(['Remove from graph filter', 'Show all branches']),
    );
    await menuOf('main', select: 'Add to graph filter');
    expect(filter().references, ['refs/heads/main', 'refs/heads/topic']);
    await menuOf('main', select: 'Show only this branch');
    expect(filter().references, ['refs/heads/main']);
    await menuOf('main', select: 'Show all branches');
    expect(filter(), HistoryBranchFilter.none);
    expect(find.byKey(filteredMark), findsNothing);
    await runtime.shutdown();
  });

  testWidgets('branch menus bring the upstream a branch tracks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refs: RepositoryRefs(
          branches: [
            RepositoryReference(
              name: 'main'.codeUnits,
              target: _filterMain,
              head: true,
            ),
            RepositoryReference(
              name: 'topic'.codeUnits,
              target: _filterTopic,
              upstream: 'refs/remotes/origin/topic'.codeUnits,
            ),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: const [],
              branches: [
                RepositoryReference(
                  name: 'topic'.codeUnits,
                  target: _filterFeature,
                ),
              ],
            ),
          ],
        ),
      ),
      historyRows: _branchFilterRows,
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    final previousPresenter = nativeMenuTestPresenter;
    addTearDown(() => nativeMenuTestPresenter = previousPresenter);
    String? choose;
    final titles = <String>[];
    nativeMenuTestPresenter = (context, menu, position) async {
      final actions = menu.children.whereType<MenuAction>();
      titles
        ..clear()
        ..addAll(actions.map((item) => item.title ?? ''));
      final action = actions.where((item) => item.title == choose);
      if (action.isEmpty) return MenuResult(itemSelected: false);
      action.single.callback();
      return MenuResult(itemSelected: true);
    };
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    await _expandSidebarGroup(tester, 'sidebar-ref-origin');

    final sidebar = find.byType(WorkspaceSidebar);
    Future<void> menuOf(int row, {String? select}) async {
      choose = select;
      await tester.tap(
        find
            .descendant(
              of: sidebar,
              matching: find.widgetWithText(MeridianListRow, 'topic'),
            )
            .at(row),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
    }

    HistoryBranchFilter filter() =>
        runtime.repositorySessions.workspace.activeTab!.navigation.branchFilter;

    await menuOf(0, select: 'Show only this branch');
    expect(filter().references, [
      'refs/heads/topic',
      'refs/remotes/origin/topic',
    ]);
    // Focused on the branch and its upstream: nothing left to focus on.
    await menuOf(0);
    expect(titles, isNot(contains('Show only this branch')));

    // The upstream is removed through its own row.
    await menuOf(1, select: 'Remove from graph filter');
    expect(filter().references, ['refs/heads/topic']);
    await runtime.shutdown();
  });

  testWidgets(
    'the sidebar lists the main branch first and shows its scrollbar on hover',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RepositoryReference branch(String name, {bool head = false}) =>
          RepositoryReference(
            name: name.codeUnits,
            target: _filterMain,
            head: head,
          );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          refs: RepositoryRefs(
            branches: [
              branch('alpha', head: true),
              branch('beta'),
              branch('main'),
            ],
            remotes: [
              RepositoryRemote(
                name: 'origin'.codeUnits,
                displayUrl: const [],
                branches: [branch('HEAD'), branch('alpha'), branch('main')],
              ),
            ],
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      await _expandSidebarGroup(tester, 'sidebar-ref-origin');

      final sidebar = find.byType(WorkspaceSidebar);
      final names = [
        for (final row in tester.widgetList<MeridianListRow>(
          find.descendant(of: sidebar, matching: find.byType(MeridianListRow)),
        ))
          if (const {'HEAD', 'alpha', 'beta', 'main'}.contains(row.title))
            row.title,
      ];
      expect(names, ['main', 'alpha', 'beta', 'main', 'HEAD', 'alpha']);

      bool? thumbVisible() => tester
          .widget<Scrollbar>(
            find.descendant(of: sidebar, matching: find.byType(Scrollbar)),
          )
          .thumbVisibility;
      expect(thumbVisible(), isFalse);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(sidebar));
      await tester.pumpAndSettle();
      expect(thumbVisible(), isTrue);
      await pointer.moveTo(
        tester.getBottomRight(sidebar) + const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      expect(thumbVisible(), isFalse);
      await runtime.shutdown();
    },
  );

  testWidgets(
    'a tab menu opens the folder, sets an icon, edits its group and closes the tab',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      NativePathIdentity path(String value) => NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: value.codeUnits,
      );
      final root = path('/repository');
      final repository = _WelcomeRepository(
        integrationCandidates: [
          IntegrationCandidate(
            id: 'macos-file-manager',
            kind: IntegrationKind.fileManager,
            executable: path('/usr/bin/open'),
            launchMode: IntegrationLaunchMode.detached,
          ),
        ],
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: path('/repository/.git'),
            worktreeRoot: root,
            gitDir: path('/repository/.git'),
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            gitMajor: 2,
            gitMinor: 50,
            gitPatch: 1,
          ),
        ),
      );
      final icons = FakeRepositoryIconRepository(
        chosen: path('/icons/repository.png'),
        files: {'/icons/repository.png': fakePngBytes},
      );
      final runtime = await _runtime(
        repository,
        _Picker(null),
        null,
        null,
        null,
        null,
        icons,
      );
      await runtime.repositorySessions.open('/repository');
      final previousPresenter = nativeMenuTestPresenter;
      addTearDown(() => nativeMenuTestPresenter = previousPresenter);
      final shown = <Menu>[];
      String? choose;
      nativeMenuTestPresenter = (context, menu, position) async {
        shown.add(menu);
        final action = menu.children.whereType<MenuAction>().where(
          (item) => item.title == choose,
        );
        if (action.isEmpty) return MenuResult(itemSelected: false);
        action.single.callback();
        return MenuResult(itemSelected: true);
      };
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      final tab = find.descendant(
        of: find.byType(GitLamaRepoTabs),
        matching: find.text('repository'),
      );
      final tabIcon = find.descendant(
        of: find.byType(GitLamaRepoTabs),
        matching: find.byKey(const ValueKey('repository-icon')),
      );

      Future<List<MenuAction>> tabMenu({String? select}) async {
        shown.clear();
        choose = select;
        await tester.tap(tab, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        return shown.single.children.whereType<MenuAction>().toList();
      }

      final items = await tabMenu();
      expect(
        items.map((item) => item.title),
        containsAllInOrder([
          'Open in Finder',
          'Change icon…',
          'Remove icon',
          'Close repository',
        ]),
      );
      expect(
        items
            .firstWhere((item) => item.title == 'Remove icon')
            .attributes
            .disabled,
        isTrue,
      );

      await tabMenu(select: 'Open in Finder');
      expect(repository.integrationRequest?.configured?.arguments, const [
        '{file}',
      ]);
      expect(
        String.fromCharCodes(
          repository.integrationRequest!.variables.file!.units,
        ),
        '/repository',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tabIcon, findsNothing);
      await tabMenu(select: 'Change icon…');
      expect(find.text('Repository icon'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repository-icon-box')));
      await tester.tap(find.byKey(const ValueKey('meridian-color-series-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repository-icon-save')));
      await tester.pumpAndSettle();
      expect(find.text('Repository icon'), findsNothing);
      final saved = runtime.settings.current.repositoryAppearances.single;
      expect(saved.identity, root);
      expect((saved.icon, saved.color, saved.image), ('box', 'teal', null));
      expect(tabIcon, findsOneWidget);
      expect(
        tester
            .widget<MeridianIcon>(
              find.descendant(of: tabIcon, matching: find.byType(MeridianIcon)),
            )
            .name,
        'box',
      );

      await tabMenu(select: 'Change icon…');
      await tester.tap(
        find.byKey(const ValueKey('repository-icon-choose-image')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('repository-icon-preview')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('repository-icon-save')));
      await tester.pumpAndSettle();
      expect(
        String.fromCharCodes(
          runtime.settings.current.repositoryAppearances.single.image!.units,
        ),
        '/icons/repository.png',
      );
      expect(
        find.descendant(of: tabIcon, matching: find.byType(Image)),
        findsOneWidget,
      );

      await tabMenu(select: 'Remove icon');
      expect(runtime.settings.current.repositoryAppearances, isEmpty);
      expect(tabIcon, findsNothing);

      // A group's name, colour and icon are edited together, after its menu
      // has closed.
      await tabMenu(select: 'Add to new group');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final groupId = runtime.repositorySessions.workspace.groups.single.id;
      shown.clear();
      choose = 'Edit group…';
      await tester.tap(
        find.byKey(ValueKey(('tab-group-chip', groupId))),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final groupItems = shown.single.children.whereType<MenuAction>().map(
        (item) => item.title,
      );
      expect(groupItems, containsAllInOrder(['Rename group…', 'Edit group…']));
      expect(groupItems, isNot(contains('Color')));
      expect(find.text('Edit group'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('tab-group-name')),
          matching: find.byType(EditableText),
        ),
        'Client',
      );
      await tester.tap(find.byKey(const ValueKey('meridian-color-series-4')));
      await tester.tap(find.byKey(const ValueKey('tab-group-icon-server')));
      await tester.tap(find.byKey(const ValueKey('tab-group-save')));
      await tester.pumpAndSettle();
      expect(find.text('Edit group'), findsNothing);
      final edited = runtime.settings.current.tabGroups.single;
      expect(
        (edited.name, edited.color, edited.icon),
        ('Client', 'rose', 'server'),
      );

      await tabMenu(select: 'Close repository');
      expect(runtime.repositorySessions.workspace.tabs, isEmpty);
      await runtime.shutdown();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'the Compass opens repository details, the tab menu copies the path and '
    'the Commands button opens the palette',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String?,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      NativePathIdentity path(String value) => NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: value.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: path('/repository/.git'),
            worktreeRoot: path('/repository'),
            gitDir: path('/repository/.git'),
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            gitMajor: 2,
            gitMinor: 50,
            gitPatch: 1,
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      final previousPresenter = nativeMenuTestPresenter;
      addTearDown(() => nativeMenuTestPresenter = previousPresenter);
      final shown = <Menu>[];
      String? choose;
      nativeMenuTestPresenter = (context, menu, position) async {
        shown.add(menu);
        final action = menu.children.whereType<MenuAction>().where(
          (item) => item.title == choose,
        );
        if (action.isEmpty) return MenuResult(itemSelected: false);
        action.single.callback();
        return MenuResult(itemSelected: true);
      };
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();

      // The Compass no longer opens the palette: it grows into the details.
      await tester.tap(find.byType(GitLamaCompass));
      await tester.pump();
      await tester.pump(GitLamaMotion.paletteMorph ~/ 2);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('command-palette-query')), findsNothing);
      expect(find.byKey(const ValueKey('repository-details')), findsOneWidget);
      expect(find.text('This computer'), findsOneWidget);
      expect(find.text('Repository with working tree'), findsOneWidget);
      expect(find.text('2.50.1'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('repository-details-path')),
            )
            .data,
        '/repository',
      );
      // The overlay starts where the Compass is.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('repository-details'))).dy,
        greaterThanOrEqualTo(tester.getTopLeft(find.byType(GitLamaCompass)).dy),
      );
      await tester.tap(
        find.byKey(const ValueKey('repository-details-copy-path')),
      );
      await tester.pump();
      expect(copied, ['/repository']);
      expect(find.text('Repository path copied.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('repository-details')), findsNothing);
      expect(tester.takeException(), isNull);

      // The tab menu copies the path next to "Open in …".
      shown.clear();
      choose = 'Copy path';
      await tester.tap(
        find.descendant(
          of: find.byType(GitLamaRepoTabs),
          matching: find.text('repository'),
        ),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final titles = shown.single.children
          .whereType<MenuAction>()
          .map((item) => item.title)
          .toList();
      expect(titles.indexOf('Copy path'), titles.indexOf('Open in Files') + 1);
      expect(copied, ['/repository', '/repository']);

      // The palette has its own button.
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('command-palette-query')), findsOneWidget);
      expect(find.byKey(const ValueKey('repository-details')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await runtime.shutdown();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('custom commands validate, persist, preview, and execute', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.zero,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
          worktreeRoot: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/repository'.codeUnits,
          ),
          gitDir: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/repository/.git'.codeUnits,
          ),
          commonGitDir: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/repository/.git'.codeUnits,
          ),
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-category-customCommands')));
    await tester.pumpAndSettle();
    expect(find.text('Add a tool or command'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('integration-id')), 'Status');
    await tester.enterText(
      find.byKey(const Key('integration-executable')),
      '/usr/bin/git',
    );
    final save = find.widgetWithText(MeridianButton, 'Check and save');
    await tester.dragUntilVisible(
      save,
      find.byType(SingleChildScrollView).last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      runtime.settings.current.integrations.map((value) => value.id),
      contains('Status'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    // The sidebar's Integrations section lists the tool as well.
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView).last,
        matching: find.text('Status'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(WorkspaceSidebar),
        matching: find.text('Status'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Status');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('command-palette-custom-Status')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Review exact command'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Run'));
    await tester.pumpAndSettle();
    expect(repository.integrationExecuted, isTrue);
    await runtime.shutdown();
  });

  testWidgets('command palette opens the repository in a configured editor', (
    tester,
  ) async {
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: root,
          worktreeRoot: root,
          gitDir: root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.settings.saveDurable(
      runtime.settings.current.copyWith(
        integrations: [
          IntegrationDefinition(
            id: 'Editor fixture',
            kind: IntegrationKind.editor,
            executable: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/editor'.codeUnits,
            ),
            arguments: const ['{file}'],
            requiresConfirmation: true,
          ),
        ],
      ),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Open in editor');
    await tester.pump();
    await tester.tap(find.text('Open in editor').last);
    await tester.pumpAndSettle();
    expect(find.text('Review exact command'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repository.integrationExecuted, isTrue);
    await runtime.shutdown();
  });

  testWidgets(
    'diff renderer configuration validates exact command before save',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository'.codeUnits,
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: root,
            worktreeRoot: root,
            gitDir: root,
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            gitMajor: 2,
            gitMinor: 50,
            gitPatch: 1,
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-category-diffRenderer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('diff-renderer-id')),
        'plain-fixture',
      );
      await tester.enterText(
        find.byKey(const Key('diff-renderer-title')),
        'Plain fixture',
      );
      await tester.enterText(
        find.byKey(const Key('diff-renderer-executable')),
        '/renderer',
      );
      final save = find.byKey(const Key('diff-renderer-validate-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save.hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save this diff renderer?'), findsOneWidget);
      // The program is a fact; the exact command lines sit behind Command
      // details, one argument per line.
      expect(find.text('/renderer'), findsWidgets);
      await tester.tap(find.text('Command details').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('--gitlama-render=text/plain'),
        findsOneWidget,
      );
      expect(find.textContaining('gitlama-diff-renderer-v1'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(MeridianButton, 'Save renderer').hitTestable().last,
      );
      await tester.pumpAndSettle();
      expect(runtime.settings.current.diffRenderer?.id, 'plain-fixture');
      expect(runtime.settings.current.diffRenderer?.title, 'Plain fixture');
      await runtime.shutdown();
    },
  );

  testWidgets('repository tools search, statistics, and preview bisect', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: root,
          worktreeRoot: root,
          gitDir: root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          headObjectId: 'abc123',
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: 'abc123',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Repository tools');
    await tester.pump();
    await tester.tap(find.text('Repository tools').last);
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.byKey(const Key('power-search-query')),
        matching: find.byType(MeridianPanel),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('history-query-toolbar')), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('../build/evidence/ui-review/power-tools-docked.png'),
      );
    }

    expect(find.textContaining('up to 10,000 commits'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('power-search-query')),
      'needle',
    );
    await tester.tap(find.text('Match case'));
    await tester.tap(find.text('Current branch'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('power-search-start')),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('power-tools-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find.byKey(const Key('power-tools-list')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('power-search-start')));
    await tester.pumpAndSettle();
    expect(repository.powerSearchCaseSensitive, isTrue);
    expect(repository.powerSearchScope, DiffSearchScope.currentBranch);
    await tester.scrollUntilVisible(
      find.text('match'),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('power-tools-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('match'), findsOneWidget);
    await tester.tap(find.text('Repository statistics').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('power-statistics-load')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('power-statistics-facts')),
        matching: find.text('6'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Find a breaking commit').first);
    await tester.pumpAndSettle();
    final start = find.byKey(const Key('power-bisect-start'));
    await tester.enterText(
      find.byKey(const Key('power-bisect-good')),
      '1111111111111111111111111111111111111111',
    );
    await tester.enterText(
      find.byKey(const Key('power-bisect-bad')),
      '2222222222222222222222222222222222222222',
    );
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Start the search for the breaking commit?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(MeridianButton, 'Start search').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('tested'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('reference groups start collapsed except around HEAD', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    RepositoryReference branch(String name, {bool head = false}) =>
        RepositoryReference(name: name.codeUnits, target: commit, head: head);
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 4, remotes: 1),
        refs: RepositoryRefs(
          branches: [
            branch('main'),
            branch('feature/ui/current', head: true),
            branch('feature/search/index'),
            branch('topic/other'),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: const [],
              branches: [branch('main')],
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    // The path to the checked-out branch is open; its siblings are not.
    expect(find.text('current'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar-ref-1-feature/search/')),
      findsOneWidget,
    );
    expect(find.text('index'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-ref-topic/')), findsOneWidget);
    expect(find.text('other'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-ref-origin')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-ref-1-main')), findsNothing);

    // An explicit choice overrides the default in both directions.
    await _expandSidebarGroup(tester, 'sidebar-ref-topic/');
    expect(find.text('other'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sidebar-ref-feature/')));
    await tester.pumpAndSettle();
    expect(find.text('current'), findsNothing);
    expect(tester.takeException(), isNull);
    await runtime.shutdown();
  });

  testWidgets('slash branches form independently expandable trees', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    RepositoryReference branch(String name) => RepositoryReference(
      name: name.codeUnits,
      target: commit,
      head: name == 'main',
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 3, remotes: 1),
        refs: RepositoryRefs(
          branches: [
            branch('main'),
            RepositoryReference(
              name: 'feature/ui/polish'.codeUnits,
              target: commit,
              upstream: 'refs/remotes/origin/feature/ui/polish'.codeUnits,
              ahead: 1,
              behind: 1,
            ),
            branch('feature/search'),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
              branches: [branch('feature/ui/polish')],
            ),
          ],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();
    final folder = find.byKey(const ValueKey('sidebar-ref-feature/'));
    final currentBranch = find.byKey(const ValueKey('sidebar-ref-main'));
    final leaf = find.byKey(const ValueKey('sidebar-ref-2-feature/ui/polish'));
    final remoteLeaf = find.byKey(
      const ValueKey('sidebar-ref-3-feature/ui/polish'),
    );
    // Groups that do not hold the checked-out branch start collapsed.
    expect(folder, findsOneWidget);
    expect(leaf, findsNothing);
    expect(remoteLeaf, findsNothing);
    for (final group in [
      'sidebar-ref-feature/',
      'sidebar-ref-1-feature/ui/',
      'sidebar-ref-origin',
      'sidebar-ref-1-feature/',
      'sidebar-ref-2-feature/ui/',
    ]) {
      await _expandSidebarGroup(tester, group);
    }
    expect(leaf, findsOneWidget);
    for (final row in [currentBranch, leaf, remoteLeaf]) {
      expect(
        find.descendant(of: row, matching: find.byType(NativeMenuButton)),
        findsNothing,
      );
    }
    expect(
      tester
          .widget<Text>(
            find.descendant(of: currentBranch, matching: find.text('main')),
          )
          .style
          ?.fontWeight,
      gitlamaText.bodyStrong.fontWeight,
    );
    expect(
      find.descendant(of: currentBranch, matching: findLucide('check')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: currentBranch, matching: find.text('aaaaaaaa')),
      findsNothing,
    );
    expect(
      find.descendant(of: remoteLeaf, matching: find.text('aaaaaaaa')),
      findsNothing,
    );
    expect(
      find.descendant(of: leaf, matching: find.byType(GitLamaSyncBadge)),
      findsOneWidget,
    );
    expect(remoteLeaf, findsOneWidget);
    expect(find.text('polish'), findsNWidgets(2));
    expect(tester.getTopLeft(leaf).dx, tester.getTopLeft(folder).dx);
    final localLabel = find.descendant(of: leaf, matching: find.text('polish'));
    final folderLabel = find.descendant(
      of: folder,
      matching: find.text('feature'),
    );
    expect(
      tester.getTopLeft(localLabel).dx,
      greaterThan(tester.getTopLeft(folderLabel).dx),
    );

    await tester.tap(folder);
    await tester.pumpAndSettle();
    expect(leaf, findsNothing);
    expect(remoteLeaf, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(leaf, findsOneWidget);

    // A shortened leaf still supplies the complete name to branch actions.
    await tester.tap(leaf, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check out branch…'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'feature/ui/polish'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await runtime.shutdown();
  });

  testWidgets(
    'sidebar refs activate history and reveal remote branch commits',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          refCounts: const RepositoryRefCounts(remotes: 1, tags: 1, stashes: 1),
          refs: RepositoryRefs(
            tags: [RepositoryReference(name: 'v1.0'.codeUnits, target: commit)],
            stashes: [
              RepositoryStash(
                selector: 'stash@{0}'.codeUnits,
                objectId: commit,
                subject: 'WIP feature'.codeUnits,
              ),
            ],
            remotes: [
              RepositoryRemote(
                name: 'origin'.codeUnits,
                displayUrl: 'example.test/repository'.codeUnits,
                branches: [
                  RepositoryReference(
                    name: 'main'.codeUnits,
                    target: commit,
                    published: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        historyRows: const [
          HistoryTopologyRow(
            objectId: commit,
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('fixture');
      await tester.pumpWidget(_app(runtime));

      expect(find.byKey(const ValueKey('sidebar-ref-origin')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-ref-1-main')), findsNothing);
      await _expandSidebarGroup(tester, 'sidebar-ref-origin');
      expect(find.byKey(const ValueKey('sidebar-ref-1-main')), findsOneWidget);
      expect(find.text('example.test/repository'), findsNothing);
      // Tags start closed.
      expect(find.byKey(const ValueKey('sidebar-ref-v1.0')), findsNothing);
      await _openSidebarTags(tester);
      expect(find.byKey(const ValueKey('sidebar-ref-v1.0')), findsOneWidget);
      for (final name in ['origin', 'v1.0', 'WIP feature']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('sidebar-ref-$name')),
            matching: find.byType(NativeMenuButton),
          ),
          findsNothing,
        );
      }
      expect(find.text('aaaaaaaa'), findsNothing);
      final remoteFocus = tester.widget<Focus>(
        find.byKey(const ValueKey('sidebar-ref-origin')),
      );
      remoteFocus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      // F2 renames the remote; the remote it renames is shown, not edited.
      // The title and the verb on the primary button.
      expect(find.text('Rename remote'), findsNWidgets(2));
      final fixedName = tester.widget<MeridianTextField>(
        find.byKey(const ValueKey('ref-mutation-fixed-name')),
      );
      expect(fixedName.readOnly, isTrue);
      expect(fixedName.controller?.text, 'origin');
      expect(
        tester
            .widget<GitReferenceField>(
              find.byKey(const ValueKey('ref-mutation-new-name')),
            )
            .controller
            .text,
        'origin',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final stashFocus = tester.widget<Focus>(
        find.byKey(const ValueKey('sidebar-ref-WIP feature')),
      );
      stashFocus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      // The title and the verb on the primary button.
      expect(find.text('Rename stash'), findsNWidgets(2));
      expect(
        tester
            .widget<MeridianTextField>(
              find.widgetWithText(MeridianTextField, 'New stash name'),
            )
            .controller
            ?.text,
        'WIP feature',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sidebar-ref-1-main')));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('history-row-$commit')), findsOneWidget);
      expect(
        runtime.repositorySessions.workspace.activeTab!.navigation.pane,
        WorkspacePane.history,
      );
      expect(
        runtime
            .repositorySessions
            .workspace
            .activeTab!
            .navigation
            .selectedIdentity,
        commit,
      );
      await tester.tap(
        find.byKey(const ValueKey('sidebar-ref-1-main')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Create branch…'), findsOneWidget);
      await tester.tap(find.text('Create branch…'));
      await tester.pumpAndSettle();
      expect(findTextFieldValue(commit), findsOneWidget);
      final nameField = tester.widget<TextField>(findMeridianField('Name'));
      expect(nameField.controller!.text, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await runtime.shutdown();
    },
  );

  testWidgets('history pane loads native rows and preserves stable selection', (
    tester,
  ) async {
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    expect(find.text('aaaaaaaaaa'), findsOneWidget);
    expect(find.byType(HistoryGraphView), findsOneWidget);
    expect(find.text('Graph'), findsNothing);
    expect(find.byKey(const ValueKey('history-query')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-branch-filter')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('history-query')),
      'Commit subject',
    );
    await tester.tap(find.byTooltip('Apply filter'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.textContaining('Showing accepted filter'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'history-row-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
        matching: find.text('Commit subject'),
      ),
    );
    await tester.pump();
    expect(
      runtime
          .repositorySessions
          .workspace
          .activeTab!
          .navigation
          .selectedIdentity,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await runtime.shutdown();
  });

  testWidgets('history search clears from the mouse and Escape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final runtime = await _runtime(
      _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
        ),
        historyRows: const [
          HistoryTopologyRow(
            objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
      ),
      _Picker(null),
    );
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();

    final clearSearch = find.byWidgetPredicate(
      (widget) =>
          widget is MeridianIconButton && widget.label == 'Clear search',
    );
    final search = find.byKey(const ValueKey('history-query'));
    await tester.enterText(search, 'Commit subject');
    await tester.tap(find.byKey(const ValueKey('history-apply-filter')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(clearSearch, findsOneWidget);

    await tester.tap(clearSearch);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller?.text, isEmpty);
    expect(find.text('1 of 1'), findsNothing);
    expect(find.text('No matches'), findsNothing);
    expect(clearSearch, findsNothing);

    await tester.enterText(search, 'Commit subject');
    await tester.tap(find.byKey(const ValueKey('history-apply-filter')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller?.text, isEmpty);
    expect(find.text('1 of 1'), findsNothing);
    expect(find.text('No matches'), findsNothing);
    expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
    await runtime.shutdown();
  });

  testWidgets('history HEAD badge stays on repository head after selection', (
    tester,
  ) async {
    const head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const older = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.clean,
          headObjectId: head,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: const [],
          totalEntries: BigInt.zero,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: head,
          parents: [older],
          refs: [],
          lane: 0,
          shape: 0,
          subject: [72, 101, 97, 100],
        ),
        HistoryTopologyRow(
          objectId: older,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
          subject: [79, 108, 100, 101, 114],
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();

    final headRow = find.byKey(const ValueKey('history-row-$head'));
    final olderRow = find.byKey(const ValueKey('history-row-$older'));
    bool hasHeadSemantics(Finder row) => tester
        .widgetList<Semantics>(
          find.descendant(of: row, matching: find.byType(Semantics)),
        )
        .any((widget) => widget.properties.label?.contains('HEAD') ?? false);
    expect(hasHeadSemantics(headRow), isTrue);
    // History opens with the repository head selected.
    expect(runtime.repositorySessions.history.current.page?.selectedObjectIds, [
      head,
    ]);

    await tester.tap(olderRow);
    await tester.pumpAndSettle();
    expect(runtime.repositorySessions.history.current.page?.selectedObjectIds, [
      older,
    ]);

    expect(hasHeadSemantics(headRow), isTrue);
    expect(hasHeadSemantics(olderRow), isFalse);
    await runtime.shutdown();
  });

  testWidgets(
    'restored history selection opens full-width detail with file mode toggle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final root = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository'.codeUnits,
      );
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(
              worktrees: [
                WorktreeSettings(
                  identity: root,
                  pane: 'history',
                  route: 'commit',
                  anchor: commit,
                ),
              ],
              openWorktrees: [root],
              activeWorktree: root,
            ),
          ),
        ),
      );
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            branchName: 'main'.codeUnits,
            headObjectId: commit,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
        historyRows: const [
          HistoryTopologyRow(
            objectId: commit,
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
        inspectionFiles: [
          CommitFileChange(
            oldMode: 0x81a4,
            newMode: 0x81a4,
            kind: CommitFileChangeKind.modified,
            oldPath: 'lib/app/main.dart'.codeUnits,
            newPath: 'lib/app/main.dart'.codeUnits,
          ),
          CommitFileChange(
            oldMode: 0x81a4,
            newMode: 0x81a4,
            kind: CommitFileChangeKind.modified,
            oldPath: 'README.md'.codeUnits,
            newPath: 'README.md'.codeUnits,
          ),
        ],
      );
      final runtime = await _runtime(
        repository,
        _Picker(null),
        null,
        null,
        null,
        settings,
      );

      await runtime.repositorySessions.restoreWorkspace();
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();

      expect(runtime.repositorySessions.inspector.current.diff, isNotNull);
      expect(find.text('Select an item to inspect.'), findsNothing);
      expect(find.text('All files'), findsOneWidget);
      expect(find.byKey(const ValueKey('inspector-back')), findsOneWidget);
      expect(find.text('2 files'), findsOneWidget);
      expect(find.text('lib'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('detail-pane'))).width,
        greaterThanOrEqualTo(MeridianLayout.islandMinWidth),
      );

      List<Map<String, Object?>>? fileMenu;
      final previousPresenter = nativeMenuTestPresenter;
      nativeMenuTestPresenter = (context, menu, position) async {
        fileMenu = encodeMenuForTest(menu);
        return MenuResult(itemSelected: false);
      };
      addTearDown(() => nativeMenuTestPresenter = previousPresenter);
      await tester.tapAt(
        tester.getCenter(
          find.byKey(const ValueKey('commit-file-lib/app/main.dart')),
        ),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(fileMenu?.map((item) => item['title']), contains('Blame'));
      expect(fileMenu?.map((item) => item['title']), contains('File history'));

      await tester.tap(find.byKey(const ValueKey('commit-files-mode')));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is GitLamaFileRow && widget.path == 'lib/app/main.dart',
        ),
        findsOneWidget,
      );

      await runtime.shutdown();
    },
  );

  testWidgets('history commands compare and inspect the selected file', (
    tester,
  ) async {
    const older = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const newer = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final path = 'lib/main.dart'.codeUnits;
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: newer,
          parents: [older],
          refs: [],
          lane: 0,
          shape: 0,
        ),
        HistoryTopologyRow(
          objectId: older,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      inspectionFiles: [
        CommitFileChange(
          oldMode: 0x81a4,
          newMode: 0x81a4,
          kind: CommitFileChangeKind.modified,
          oldPath: path,
          newPath: path,
        ),
      ],
      treeHistoryEntries: [
        PathHistoryEntry(
          stableId: 'main-history',
          commit: newer,
          author: 'Fixture'.codeUnits,
          authorTime: 1,
          summary: 'Tracked file'.codeUnits,
          path: path,
          oldPath: 'old/main.dart'.codeUnits,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker('/chosen'));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await runtime.repositorySessions.history.select(older, toggle: true);
    await runtime.repositorySessions.history.select(newer, toggle: true);
    await tester.pumpAndSettle();

    Future<void> runCommand(String label) async {
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, label);
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianListRow, label));
      await tester.pumpAndSettle();
    }

    await runCommand('Compare commits');
    expect(
      runtime.repositorySessions.inspector.current.diff?.oldObjectId,
      older,
    );
    expect(
      runtime.repositorySessions.inspector.current.diff?.newObjectId,
      newer,
    );

    await runCommand('Create patch');
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(repository.patchExportRequest?.comparisonOld, older);
    expect(repository.patchExportRequest?.comparisonNew, newer);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await runCommand('Blame file');
    expect(repository.blamePath, path);
    await runCommand('File history');
    expect(repository.pathHistoryPath, path);
    expect(find.byType(MeridianSegmented<InspectorLens>), findsOneWidget);
    expect(find.textContaining('old/main.dart'), findsOneWidget);
    expect(find.text('Show commit'), findsOneWidget);
    // Back and Forward stay in the location bar in every lens.
    expect(find.byKey(const ValueKey('inspector-back')), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/evidence/ui-review/path-history.png'),
      );
    }
    await tester.tap(find.text('Show commit'));
    await tester.pumpAndSettle();
    final shown = runtime.repositorySessions.inspector.current.location!;
    expect(shown.target, const CommitTarget(newer));
    expect(shown.lens, InspectorLens.diff);
    expect(shown.path, path);
    await runtime.shutdown();
  });

  testWidgets('all files shows committed contents before optional history', (
    tester,
  ) async {
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final path = 'README.md'.codeUnits;
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: commit,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      treeEntries: [
        CommitTreeEntry(
          stableId: 'readme',
          path: path,
          objectId: 'blob',
          kind: CommitTreeEntryKind.file,
          mode: 0x81a4,
        ),
      ],
      treeHistoryEntries: [
        PathHistoryEntry(
          stableId: 'readme-history',
          commit: commit,
          author: 'Fixture'.codeUnits,
          authorTime: 1,
          summary: 'Document change'.codeUnits,
          path: path,
        ),
      ],
      treeFileBytes: 'Contents at the selected commit\n'.codeUnits,
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await runtime.repositorySessions.history.select(commit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    expect(repository.treeContentPath, path);
    expect(repository.pathHistoryPath, isNull);
    expect(find.text('README.md'), findsWidgets);
    expect(find.text('Contents at the selected commit'), findsOneWidget);
    // The file was not changed, so its diff explains why it is unavailable.
    final inspector = runtime.repositorySessions.inspector;
    expect(inspector.current.location!.lens, InspectorLens.contents);
    expect(
      inspector.current.lensAvailability[InspectorLens.diff],
      LensUnavailableReason.notChanged,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('inspector-lens')),
        matching: find.byTooltip('History'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.pathHistoryPath, path);
    expect(find.text('Document change'), findsWidgets);
    expect(inspector.current.location!.historyCommit, commit);
    // Back returns to the contents; the tree keeps its scope.
    await tester.tap(find.byKey(const ValueKey('inspector-back')));
    await tester.pumpAndSettle();
    expect(inspector.current.location!.lens, InspectorLens.contents);
    expect(inspector.current.location!.scope, InspectorScope.all);
    // Esc climbs to every change, then back to the changed files.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(inspector.current.location!.path, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(inspector.current.location!.scope, InspectorScope.changed);
    expect(
      find.byKey(const ValueKey('commit-summary-$commit')),
      findsOneWidget,
    );
    await runtime.shutdown();
  });

  testWidgets(
    'working-tree graph row opens Changes without selecting a commit',
    (tester) async {
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
        ),
        historyRows: [
          HistoryTopologyRow(
            objectId: historyWorktreeObjectId,
            parents: const ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
            refs: const [],
            lane: 0,
            shape: HistoryNodeShape.wip.index,
            wipChangedFiles: 3,
            wipStagedFiles: 1,
          ),
          HistoryTopologyRow(
            objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            parents: const [],
            refs: const [],
            lane: 0,
            shape: HistoryNodeShape.commit.index,
            subject: 'Initial commit'.codeUnits,
          ),
        ],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('fixture');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(findWorkspacePaneAction('History'));
      await tester.pumpAndSettle();

      expect(
        find.text('Uncommitted changes · 3 files · 1 staged'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('history-row-$historyWorktreeObjectId')),
      );
      await tester.pumpAndSettle();

      expect(
        runtime.repositorySessions.workspace.activeTab!.navigation.pane,
        WorkspacePane.changes,
      );
      expect(
        runtime
            .repositorySessions
            .workspace
            .activeTab!
            .navigation
            .selectedIdentity,
        isNull,
      );
      await runtime.shutdown();
    },
  );

  testWidgets('history filters precede a headerless QSpline graph', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();

    final branch = find.byKey(const ValueKey('history-branch-filter'));
    final search = find.byKey(const ValueKey('history-query'));
    final toolbar = find.byKey(const ValueKey('history-query-toolbar'));
    expect(
      tester.getTopLeft(branch).dx,
      lessThan(tester.getTopLeft(search).dx),
    );
    expect(tester.getSize(toolbar).height, MeridianSize.islandHeader);
    final centerY = tester.getCenter(search).dy;
    for (final key in const [
      'history-branch-filter',
      'history-view-options',
      'meridian-find-previous',
      'meridian-find-next',
      'history-search-scopes',
      'history-apply-filter',
      'history-collapse-selected',
      'history-reflog-toggle',
    ]) {
      final control = find.descendant(
        of: toolbar,
        matching: find.byKey(ValueKey(key)),
      );
      expect(
        tester.getSize(control).height,
        lessThanOrEqualTo(MeridianSize.control),
        reason: '$key should fit the compact history header',
      );
      expect(
        tester.getCenter(control).dy,
        closeTo(centerY, 0.01),
        reason: '$key should share the search field center line',
      );
    }
    expect(find.text('Graph'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Author'), findsNothing);
    expect(find.text('SHA'), findsNothing);
    expect(find.text('Date'), findsNothing);
    final graph = find.byType(HistoryGraphView);
    expect(
      tester.getTopLeft(graph).dy - tester.getBottomLeft(search).dy,
      inInclusiveRange(0, 12),
    );
    await runtime.shutdown();
  });

  testWidgets('history shows other refs on request and names hidden commits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const branch = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const checkpoint = 'cccccccccccccccccccccccccccccccccccccccc';
    final repository =
        _WelcomeRepository(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
            ),
            historyRows: const [
              HistoryTopologyRow(
                objectId: branch,
                parents: [],
                refs: [],
                lane: 0,
                shape: 0,
              ),
            ],
          )
          ..otherRefsHistoryRows = const [
            HistoryTopologyRow(
              objectId: checkpoint,
              parents: [branch],
              refs: [],
              lane: 1,
              shape: 0,
            ),
          ];
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    final previousPresenter = nativeMenuTestPresenter;
    addTearDown(() => nativeMenuTestPresenter = previousPresenter);
    final shown = <MenuAction>[];
    nativeMenuTestPresenter = (context, menu, position) async {
      final items = menu.children.whereType<MenuAction>().toList();
      shown
        ..clear()
        ..addAll(items);
      final item = items.singleWhere((item) => item.title == 'Show other refs');
      item.callback();
      return MenuResult(itemSelected: true);
    };
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    final history = runtime.repositorySessions.history;
    expect(runtime.settings.current.appearance.historyOtherRefs, isFalse);
    expect(history.current.page!.totalRows, 1);
    expect(find.text('End of history · 1 commits'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-view-options')));
    await tester.pumpAndSettle();
    expect(shown.single.state, MenuActionState.checkOff);
    expect(runtime.settings.current.appearance.historyOtherRefs, isTrue);
    expect(history.current.page!.otherRefs, isTrue);
    expect(history.current.page!.totalRows, 2);
    expect(find.text('End of history · 2 commits'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-view-options')));
    await tester.pumpAndSettle();
    expect(shown.single.state, MenuActionState.checkOn);
    expect(runtime.settings.current.appearance.historyOtherRefs, isFalse);
    expect(history.current.page!.totalRows, 1);

    // A commit only another reference reaches is named, not silently lost.
    await runtime.repositorySessions.history.select(checkpoint, reveal: true);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Commits that only other refs reach'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('history-show-other-refs')));
    await tester.pumpAndSettle();
    expect(runtime.settings.current.appearance.historyOtherRefs, isTrue);
    expect(history.current.targetNotShown, isFalse);
    expect(history.current.page!.selectedObjectIds, [checkpoint]);
    expect(
      find.textContaining('Commits that only other refs reach'),
      findsNothing,
    );
    await runtime.shutdown();
  });

  for (final applyOnly in [false, true]) {
    testWidgets(
      'commit revert chooses apply-only=$applyOnly and targets the clicked commit',
      (tester) async {
        const clicked = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        const selected = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        final repository = _WelcomeRepository(
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            refs: RepositoryRefs(
              branches: [
                RepositoryReference(
                  name: 'main'.codeUnits,
                  target: selected,
                  head: true,
                ),
              ],
            ),
            status: RepositoryStatus(
              workingTree: WorkingTreeState.clean,
              branchName: 'main'.codeUnits,
              headObjectId: selected,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: [],
              totalEntries: BigInt.zero,
              entriesTruncated: false,
              operations: [],
            ),
          ),
          historyRows: const [
            HistoryTopologyRow(
              objectId: selected,
              parents: [clicked],
              refs: [],
              lane: 0,
              shape: 0,
            ),
            HistoryTopologyRow(
              objectId: clicked,
              parents: [],
              refs: [],
              lane: 0,
              shape: 0,
            ),
          ],
        );
        final runtime = await _runtime(repository, _Picker(null));
        await runtime.repositorySessions.open('fixture');
        await tester.pumpWidget(_app(runtime));
        await tester.tap(findWorkspacePaneAction('History'));
        await runtime.repositorySessions.history.select(selected);
        await tester.pumpAndSettle();
        final widget = tester.widget<GitLamaContextMenuWidget>(
          find.descendant(
            of: find.byKey(const ValueKey('history-row-$clicked')),
            matching: find.byType(GitLamaContextMenuWidget),
          ),
        );
        final menu = widget.testMenu() as Menu;
        final revert = menu.children.whereType<MenuAction>().firstWhere(
          (item) => item.title == 'Revert commit',
        );
        expect(revert.attributes.disabled, isFalse);
        revert.callback();
        await tester.pumpAndSettle();
        expect(find.text('Revert commit'), findsOneWidget);
        expect(
          find.textContaining('a new commit that undoes the selected commit'),
          findsOneWidget,
        );
        // The working tree is clean, so no clean-tree warning stands in the
        // way.
        expect(find.textContaining('clean working tree'), findsNothing);
        await tester.tap(
          find.widgetWithText(
            MeridianButton,
            applyOnly ? 'Apply without committing' : 'Commit revert',
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.historyMutationRequest?.targets, [clicked]);
        expect(repository.historyMutationRequest?.noCommit, applyOnly);
        expect(
          repository.historyMutationRequest?.acknowledgePublishedHistory,
          isFalse,
        );
        await tester.tap(
          find.widgetWithText(
            MeridianButton,
            applyOnly ? 'Apply without committing' : 'Commit revert',
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.executedHistoryMutationToken, BigInt.from(85));
        if (applyOnly) {
          expect(
            find.text(
              'Revert applied. Review the staged changes before committing.',
            ),
            findsOneWidget,
          );
        }
        await runtime.shutdown();
      },
    );
  }

  testWidgets(
    'commit and chip menus include hidden refs and retain disabled current-branch actions',
    (tester) async {
      const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          refs: RepositoryRefs(
            branches: [
              RepositoryReference(
                name: 'main'.codeUnits,
                target: commit,
                head: true,
                upstream: 'refs/remotes/origin/main'.codeUnits,
              ),
              RepositoryReference(
                name: 'origin/main'.codeUnits,
                target: commit,
              ),
            ],
            remotes: [
              RepositoryRemote(
                name: 'origin'.codeUnits,
                displayUrl: [],
                branches: [
                  RepositoryReference(name: 'main'.codeUnits, target: commit),
                ],
              ),
            ],
            tags: [RepositoryReference(name: 'v1'.codeUnits, target: commit)],
          ),
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            branchName: 'main'.codeUnits,
            headObjectId: commit,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: [],
          ),
        ),
        // Only main has a displayed chip. The other refs still belong in the menu.
        historyRows: [
          HistoryTopologyRow(
            objectId: commit,
            parents: [],
            refs: ['refs/heads/main'.codeUnits],
            lane: 0,
            shape: 0,
          ),
        ],
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('fixture');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(findWorkspacePaneAction('History'));
      await tester.pumpAndSettle();
      final graph = tester.widget<HistoryGraphView>(
        find.byType(HistoryGraphView),
      );
      final row = graph.rowAt(0);
      final menu = nativeMenuFromActions(graph.onContextMenu!(row));
      final chip = nativeMenuFromActions(
        graph.onReferenceContextMenu!(row, 'refs/heads/main')!,
      );
      expect(menu.children.whereType<Menu>().map((item) => item.title), [
        'refs/heads/main',
        'refs/heads/origin/main',
        'refs/remotes/origin/main',
        'refs/tags/v1',
      ]);
      expect(
        chip.children.map((item) => item.title),
        menu.children.map((item) => item.title),
      );
      expect(menu.children.whereType<MenuAction>().map((item) => item.title), [
        'Revert commit',
        'Cherry-pick selected commits…',
        'Create patch from this commit',
        'Check out commit…',
        'Save snapshot as ZIP…',
        'Create branch…',
        'Create tag…',
        'Copy commit SHA',
        'Copy commit subject',
        // Destructive commands come last.
        'Reset current branch…',
      ]);
      expect(
        menu.children
            .whereType<MenuAction>()
            .firstWhere((item) => item.title == 'Reset current branch…')
            .attributes
            .destructive,
        isTrue,
      );
      MenuAction action(String ref, String label) => menu.children
          .whereType<Menu>()
          .firstWhere((item) => item.title == ref)
          .children
          .whereType<MenuAction>()
          .firstWhere((item) => item.title == label);
      expect(
        action('refs/heads/main', 'Check out branch…').attributes.disabled,
        isTrue,
      );
      expect(
        action('refs/heads/main', 'Delete branch…').attributes.disabled,
        isTrue,
      );
      expect(
        action('refs/heads/main', 'Merge branch…').attributes.disabled,
        isTrue,
      );
      expect(
        action('refs/heads/main', 'Rebase onto branch…').attributes.disabled,
        isTrue,
      );
      expect(
        action(
          'refs/heads/origin/main',
          'Check out branch…',
        ).attributes.disabled,
        isFalse,
      );
      expect(
        action(
          'refs/remotes/origin/main',
          'Check out branch…',
        ).attributes.disabled,
        isTrue,
      );
      action('refs/heads/origin/main', 'Check out branch…').callback();
      await tester.pumpAndSettle();
      expect(findTextFieldValue('origin/main'), findsOneWidget);
      await tester.tap(find.widgetWithText(MeridianButton, 'Check out branch'));
      await tester.pumpAndSettle();
      expect(
        repository.refMutationRequest?.kind,
        RefMutationKind.checkoutBranch,
      );
      expect(repository.refMutationRequest?.name, 'origin/main');
      await runtime.shutdown();
    },
  );

  testWidgets('history row context menu creates a branch at that commit', (
    tester,
  ) async {
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: commit,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker('/chosen'));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();

    final contextMenu = tester.widget<GitLamaContextMenuWidget>(
      find.descendant(
        of: find.byKey(ValueKey('history-row-$commit')),
        matching: find.byType(GitLamaContextMenuWidget),
      ),
    );
    final provided = contextMenu.testMenu();
    final menu = provided as Menu;
    expect(menu.children.whereType<Menu>(), isEmpty);
    expect(menu.children.whereType<MenuAction>().length, 10);
    expect(
      menu.children.whereType<MenuAction>().map((action) => action.title),
      contains('Check out commit…'),
    );
    menu.children
        .whereType<MenuAction>()
        .firstWhere((action) => action.title == 'Create patch from this commit')
        .callback();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(repository.patchExportRequest?.commit, commit);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    menu.children
        .whereType<MenuAction>()
        .firstWhere((action) => action.title == 'Create branch…')
        .callback();
    await tester.pumpAndSettle();

    expect(findTextFieldValue(commit), findsOneWidget);
    await tester.enterText(findMeridianField('Name'), 'topic');
    await tester.pump();
    await tester.tap(find.widgetWithText(MeridianButton, 'Create branch'));
    await tester.pumpAndSettle();
    // The title and the verb on the primary button.
    expect(find.text('Create branch'), findsNWidgets(2));
    expect(repository.refMutationRequest?.kind, RefMutationKind.createBranch);
    expect(repository.refMutationRequest?.name, 'topic');
    expect(repository.refMutationRequest?.target, commit);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await runtime.shutdown();
  });

  testWidgets('commit menu separates the selection from the commit', (
    tester,
  ) async {
    const older = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const newer = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: newer,
          parents: [older],
          refs: [],
          lane: 0,
          shape: 0,
        ),
        HistoryTopologyRow(
          objectId: older,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker('/chosen'));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();

    Menu menuOf(String commit) =>
        tester
                .widget<GitLamaContextMenuWidget>(
                  find.descendant(
                    of: find.byKey(ValueKey('history-row-$commit')),
                    matching: find.byType(GitLamaContextMenuWidget),
                  ),
                )
                .testMenu()
            as Menu;
    final singleCommitMenu = menuOf(newer);
    expect(singleCommitMenu.children.whereType<Menu>(), isEmpty);
    expect(singleCommitMenu.children.whereType<MenuAction>(), hasLength(10));
    expect(
      singleCommitMenu.children.whereType<MenuAction>().map(
        (action) => action.title,
      ),
      contains('Check out commit…'),
    );

    await runtime.repositorySessions.history.select(older, toggle: true);
    await runtime.repositorySessions.history.select(newer, toggle: true);
    await tester.pumpAndSettle();
    final menu = menuOf(newer);
    final selectionMenu = menu.children.whereType<Menu>().single;
    expect(selectionMenu.title, '2 selected commits');
    expect(menu.children[1], isA<MenuSeparator>());
    expect(
      menu.children.whereType<MenuAction>().map((item) => item.title),
      singleCommitMenu.children.whereType<MenuAction>().map(
        (item) => item.title,
      ),
    );
    expect(
      selectionMenu.children.whereType<MenuAction>().map((item) => item.title),
      [
        'Compare commits',
        'Cherry-pick selected commits…',
        'Revert selected commits…',
        'Create patch from selection',
      ],
    );
    selectionMenu.children
        .whereType<MenuAction>()
        .firstWhere((action) => action.title == 'Create patch from selection')
        .callback();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(repository.patchExportRequest?.comparisonOld, older);
    expect(repository.patchExportRequest?.comparisonNew, newer);
    expect(repository.patchExportRequest?.commit, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    menu.children
        .whereType<MenuAction>()
        .firstWhere((action) => action.title == 'Create patch from this commit')
        .callback();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(repository.patchExportRequest?.commit, newer);
    expect(repository.patchExportRequest?.comparisonOld, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await runtime.shutdown();
  });

  testWidgets('commit diff returns to all changes and exports what it shows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final path = 'lib/main.dart'.codeUnits;
    final renamed = 'lib/renamed.dart'.codeUnits;
    final renamedFrom = 'lib/original.dart'.codeUnits;
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: commit,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      inspectionFiles: [
        CommitFileChange(
          oldMode: 0x81a4,
          newMode: 0x81a4,
          kind: CommitFileChangeKind.modified,
          oldPath: path,
          newPath: path,
        ),
        CommitFileChange(
          oldMode: 0x81a4,
          newMode: 0x81a4,
          kind: CommitFileChangeKind.renamed,
          oldPath: renamedFrom,
          newPath: renamed,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker('/chosen'));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await runtime.repositorySessions.history.select(commit);
    await tester.pumpAndSettle();
    final history = runtime.repositorySessions.inspector;

    Future<PatchExportRequest?> exportShownDiff() async {
      await tester.tap(find.byKey(const ValueKey('commit-diff-create-patch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose destination'));
      await tester.pumpAndSettle();
      final request = repository.patchExportRequest;
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      return request;
    }

    MeridianListRow allChanges() => tester.widget<MeridianListRow>(
      find.byKey(const ValueKey('commit-files-all-changes')),
    );

    // The diff starts with every file; nothing to return from.
    expect(allChanges().selected, isTrue);
    expect(find.byKey(const ValueKey('commit-diff-all-files')), findsNothing);
    var request = await exportShownDiff();
    expect(request?.commit, commit);
    expect(request?.historyPaths, isEmpty);

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(history.diffOptions.newPath, path);
    expect(allChanges().selected, isFalse);
    expect(
      tester
          .widget<GitLamaFileRow>(
            find.byKey(const ValueKey('commit-file-lib/main.dart')),
          )
          .selected,
      isTrue,
    );
    request = await exportShownDiff();
    expect(request?.commit, commit);
    expect(request?.historyPaths, [path]);

    // Back leads to every file again.
    await tester.tap(find.byKey(const ValueKey('inspector-back')));
    await tester.pumpAndSettle();
    expect(history.diffOptions.newPath, isNull);
    expect(allChanges().selected, isTrue);

    // A renamed file is exported with the path it came from.
    await tester.tap(find.text('renamed.dart'));
    await tester.pumpAndSettle();
    request = await exportShownDiff();
    expect(request?.historyPaths, [renamed, renamedFrom]);

    // So does the first row of the file list.
    await tester.tap(find.byKey(const ValueKey('commit-files-all-changes')));
    await tester.pumpAndSettle();
    expect(history.diffOptions.newPath, isNull);
    expect(find.byKey(const ValueKey('commit-diff-all-files')), findsNothing);

    final fileMenu = (await tester
        .widget<GitLamaContextMenuWidget>(
          find.ancestor(
            of: find.byKey(const ValueKey('commit-file-lib/main.dart')),
            matching: find.byType(GitLamaContextMenuWidget),
          ),
        )
        .testMenu())!;
    final restore = fileMenu.children.last as MenuAction;
    expect(restore.title, 'Restore this version');
    expect(restore.attributes.destructive, isTrue);
    fileMenu.children
        .whereType<MenuAction>()
        .firstWhere((item) => item.title == 'Create patch from this file')
        .callback();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(repository.patchExportRequest?.commit, commit);
    expect(repository.patchExportRequest?.historyPaths, [path]);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await runtime.shutdown();
  });

  testWidgets('history ref badges use the sidebar branch and tag actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const branchCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const tagCommit = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const remoteCommit = 'cccccccccccccccccccccccccccccccccccccccc';
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refs: RepositoryRefs(
          branches: [
            RepositoryReference(name: 'topic'.codeUnits, target: branchCommit),
          ],
          tags: [
            RepositoryReference(name: 'v1.0'.codeUnits, target: tagCommit),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: 'example.test/repository'.codeUnits,
              branches: [
                RepositoryReference(
                  name: 'review'.codeUnits,
                  target: remoteCommit,
                ),
              ],
            ),
          ],
        ),
      ),
      historyRows: [
        HistoryTopologyRow(
          objectId: branchCommit,
          parents: const [],
          refs: ['refs/heads/topic'.codeUnits],
          lane: 0,
          shape: 0,
        ),
        HistoryTopologyRow(
          objectId: tagCommit,
          parents: const [],
          refs: ['refs/tags/v1.0'.codeUnits],
          lane: 0,
          shape: 0,
        ),
        HistoryTopologyRow(
          objectId: remoteCommit,
          parents: const [],
          refs: ['refs/remotes/origin/review'.codeUnits],
          lane: 0,
          shape: 0,
        ),
      ],
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    final previousPresenter = nativeMenuTestPresenter;
    final shown = <Menu>[];
    nativeMenuTestPresenter = (_, menu, _) async {
      shown.add(menu);
      return MenuResult(itemSelected: false);
    };
    addTearDown(() => nativeMenuTestPresenter = previousPresenter);
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();

    Future<List<String?>> menuFor(String reference) async {
      shown.clear();
      await tester.tap(
        find.byKey(ValueKey('history-ref-$reference')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(shown, hasLength(1));
      expect(
        shown.single.children.whereType<MenuAction>().map((item) => item.title),
        containsAll([
          'Revert commit',
          'Create patch from this commit',
          'Save snapshot as ZIP…',
          'Create branch…',
        ]),
      );
      return flatMenuActions(shown.single).map((item) => item.title).toList();
    }

    expect(await menuFor('refs/heads/topic'), contains('Edit branch…'));
    expect(
      flatMenuActions(shown.single).map((item) => item.title),
      contains('Delete branch…'),
    );
    // The reference menu ends with its destructive commands, flagged.
    final topic = shown.single.children.whereType<Menu>().firstWhere(
      (item) => item.title == 'refs/heads/topic',
    );
    final topicActions = topic.children.whereType<MenuAction>().toList();
    final copyName = topicActions.indexWhere(
      (item) => item.title == 'Copy name',
    );
    expect(copyName, isNonNegative);
    expect(topicActions.last.title, 'Delete branch…');
    expect(
      topicActions
          .skip(copyName + 1)
          .every((item) => item.attributes.destructive),
      isTrue,
    );
    expect(
      topicActions
          .take(copyName + 1)
          .any((item) => item.attributes.destructive),
      isFalse,
    );
    final copied = <Object?>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    topicActions[copyName].callback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, [
      {'text': 'topic'},
    ]);
    expect(find.text('Name copied.'), findsOneWidget);
    await tester.pumpAndSettle();
    flatMenuActions(
      shown.single,
    ).firstWhere((item) => item.title == 'Edit branch…').callback();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(findMeridianField('Name')).controller?.text,
      'topic',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await menuFor('refs/tags/v1.0'), contains('Push tag…'));
    expect(
      flatMenuActions(shown.single).map((item) => item.title),
      contains('Delete tag…'),
    );
    flatMenuActions(
      shown.single,
    ).firstWhere((item) => item.title == 'Push tag…').callback();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'v1.0'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      await menuFor('refs/remotes/origin/review'),
      contains('Merge branch…'),
    );
    expect(
      flatMenuActions(shown.single).map((item) => item.title),
      isNot(contains('Delete branch…')),
    );
    shown.clear();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(ValueKey('history-row-$branchCommit'))) +
          const Offset(500, 10),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(shown, hasLength(1));
    expect(shown.single.children.whereType<Menu>().map((item) => item.title), [
      'refs/heads/topic',
    ]);
    expect(
      shown.single.children.whereType<MenuAction>().map((item) => item.title),
      containsAll([
        'Revert commit',
        'Create patch from this commit',
        'Save snapshot as ZIP…',
        'Create branch…',
      ]),
    );
    await runtime.shutdown();
  });

  testWidgets('renderer failure keeps the built-in diff selection active', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        identity: RepositoryIdentity(
          commonGitDir: root,
          worktreeRoot: root,
          gitDir: root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      commitDiffResult: DiffPage(
        requestId: BigInt.one,
        layout: DiffViewLayout.unified,
        totalRows: 1,
        offset: 0,
        rows: const [
          DiffDisplayRow(
            stableId: 'selected-line',
            kind: DiffRowKind.addition,
            text: [99, 104, 97, 110, 103, 101, 100],
            newLine: 1,
            selectable: true,
          ),
        ],
        payloadBytes: 64,
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await runtime.settings.saveDurable(
      runtime.settings.current.copyWith(
        diffRenderer: DiffRendererDefinition(
          id: 'fixture',
          title: 'Fixture renderer',
          executable: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: '/renderer'.codeUnits,
          ),
        ),
      ),
    );
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await runtime.repositorySessions.history.select(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.pumpAndSettle();
    expect(runtime.repositorySessions.inspector.current.diff, isNotNull);
    expect(
      runtime.repositorySessions.workspace.activeTab!.navigation.pane,
      WorkspacePane.history,
    );

    final row = find.byKey(const ValueKey('diff-row-selected-line'));
    await tester.tapAt(_diffGutter(tester, 'selected-line'));
    await tester.pump();
    expect(
      tester.getSemantics(row).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Toggle diff layout');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(MeridianListRow, 'Toggle diff layout'),
    );
    await tester.pumpAndSettle();
    expect(repository.commitDiffOptions?.layout, DiffViewLayout.sideBySide);

    await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Render diff with configured renderer',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(
        MeridianListRow,
        'Render diff with configured renderer',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Run the diff renderer?'), findsOneWidget);
    await tester.tap(find.widgetWithText(MeridianButton, 'Render diff'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The renderer exited with a failure. The built-in diff remains active.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(row).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.text('changed'), findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets('commit image diff shows decoded RGBA inline in all modes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: const [
        HistoryTopologyRow(
          objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      commitDiffResult: DiffPage(
        requestId: BigInt.one,
        layout: DiffViewLayout.unified,
        totalRows: 1,
        offset: 0,
        rows: const [
          DiffDisplayRow(
            stableId: 'image-line',
            kind: DiffRowKind.image,
            text: [],
            oldPath: [111, 108, 100],
            newPath: [110, 101, 119],
          ),
        ],
        payloadBytes: 32,
      ),
      imageDiffResult: const ImageDiffContent(
        old: DecodedImageContent(width: 1, height: 1, rgba: [255, 0, 0, 255]),
        newImage: DecodedImageContent(
          width: 1,
          height: 1,
          rgba: [0, 0, 255, 255],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    await runtime.repositorySessions.history.select(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImageDiffView), findsOneWidget);
    expect(find.byKey(const ValueKey('diff-row-image-line')), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Before: 1 × 1 px'), findsOneWidget);
    expect(find.text('After: 1 × 1 px'), findsOneWidget);
    await tester.tap(find.text('Swipe'));
    await tester.pump();
    expect(find.byKey(const Key('image-diff-amount')), findsOneWidget);
    await tester.tap(find.text('Onion skin'));
    await tester.pump();
    expect(find.byType(Opacity), findsWidgets);
    await runtime.shutdown();
  });

  testWidgets('repeated reveal returns the same commit after scrolling away', (
    tester,
  ) async {
    final rows = [
      for (var index = 0; index < 100; index += 1)
        HistoryTopologyRow(
          objectId:
              '${index.toString().padLeft(10, '0')}000000000000000000000000000000',
          parents: const [],
          refs: index == 0 ? ['main'.codeUnits] : const [],
          lane: index % 4,
          shape: 0,
        ),
    ];
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
      ),
      historyRows: rows,
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.repositorySessions.open('fixture');
    await tester.pumpWidget(_app(runtime));
    await tester.tap(findWorkspacePaneAction('History'));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(HistoryGraphView),
      matching: find.byType(Scrollable),
    );
    final graphHash = find.descendant(
      of: find.byType(HistoryGraphView),
      matching: find.text('0000000000'),
    );
    await tester.drag(scrollable, const Offset(0, -1400));
    await tester.pump();
    expect(graphHash, findsNothing);
    await runtime.repositorySessions.history.select(
      rows.first.objectId,
      reveal: true,
      focus: false,
    );
    await tester.pump();
    await tester.pump();
    expect(graphHash, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -1200));
    await tester.pump();
    await runtime.repositorySessions.history.select(
      rows.first.objectId,
      reveal: true,
      focus: false,
    );
    await tester.pump();
    await tester.pump();
    expect(graphHash, findsOneWidget);
    await runtime.shutdown();
  });

  testWidgets(
    'settings apply appearance immediately and reset one repository',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final identity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/repository'.codeUnits,
      );
      final runtime = await _runtime(
        _WelcomeRepository(
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            identity: RepositoryIdentity(
              kind: RepositoryKind.worktree,
              headKind: HeadKind.attached,
              gitMajor: 2,
              gitMinor: 50,
              gitPatch: 1,
              worktreeRoot: identity,
              gitDir: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository/.git'.codeUnits,
              ),
              commonGitDir: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository/.git'.codeUnits,
              ),
            ),
          ),
        ),
        _Picker(null),
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/evidence/ui-review/shell-toolbar.png'),
        );
      }

      final toolbar = find.byKey(const ValueKey('toolbar-row'));
      final compass = find.byType(GitLamaCompass);
      final toolbarCenter = tester.getCenter(toolbar);
      final compassCenter = tester.getCenter(compass);
      final compassSlot = find.byKey(const ValueKey('toolbar-compass-slot'));
      final leading = find.byKey(const ValueKey('toolbar-leading-group'));
      final trailing = find.byKey(const ValueKey('toolbar-trailing-group'));
      expect(
        (compassCenter.dx - tester.getCenter(compassSlot).dx).abs(),
        lessThan(1),
      );
      expect(
        tester.getRect(compass).left,
        greaterThan(tester.getRect(leading).right),
      );
      expect(
        tester.getRect(compass).right,
        lessThan(tester.getRect(trailing).left),
      );
      expect((compassCenter.dy - toolbarCenter.dy).abs(), lessThan(1));
      final push = find.byKey(const ValueKey('push-primary'));
      expect((tester.getCenter(push).dy - compassCenter.dy).abs(), lessThan(1));
      for (final label in ['Fetch…', 'Pull…', 'Create stash…']) {
        final button = find.byWidgetPredicate(
          (widget) => widget is MeridianToolbarButton && widget.label == label,
        );
        expect(button, findsOneWidget);
        final icon = find
            .descendant(of: button, matching: find.byType(MeridianIcon))
            .first;
        final caption = find.descendant(
          of: button,
          matching: find.text(label.replaceAll('…', '')),
        );
        expect(
          ((tester.getTopLeft(icon).dy + tester.getBottomRight(caption).dy) /
                      2 -
                  tester.getCenter(button).dy)
              .abs(),
          lessThan(1),
        );
        expect(
          (tester.getCenter(button).dy - compassCenter.dy).abs(),
          lessThan(1),
        );
      }
      final pushIcon = find
          .descendant(of: push, matching: find.byType(MeridianIcon))
          .first;
      final pushLabel = find.descendant(of: push, matching: find.text('Push'));
      expect(
        ((tester.getTopLeft(pushIcon).dy +
                        tester.getBottomRight(pushLabel).dy) /
                    2 -
                tester.getCenter(push).dy)
            .abs(),
        lessThan(1),
      );

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final settingsDialog = find.byType(MeridianDialogSurface);
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/evidence/ui-review/settings.png'),
        );
      }
      Finder settingLabel(String label) =>
          find.descendant(of: settingsDialog, matching: find.text(label));
      void expectReadableSelectedCategory() {
        final selectedRow = find.byKey(
          const Key('settings-category-appearance'),
        );
        final row = tester.widget<MeridianNavRow>(selectedRow);
        final colors = MeridianRowColors.resolve(
          tester.element(selectedRow),
          selected: true,
          hovered: false,
        );
        final background = colors.fill;
        double contrast(Color foreground) {
          final light = foreground.computeLuminance();
          final dark = background.computeLuminance();
          return (light > dark ? light + 0.05 : dark + 0.05) /
              (light > dark ? dark + 0.05 : light + 0.05);
        }

        expect(row.selected, isTrue);
        expect(contrast(colors.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(colors.icon), greaterThanOrEqualTo(3));
      }

      expectReadableSelectedCategory();
      expect(settingLabel('Appearance'), findsWidgets);
      expect(settingLabel('Git'), findsOneWidget);
      expect(settingLabel('Hosting accounts'), findsOneWidget);
      expect(settingLabel('Repository link'), findsOneWidget);
      expect(settingLabel('Tools and commands'), findsOneWidget);
      expect(settingLabel('Diff renderer'), findsOneWidget);
      expect(settingLabel('Accessibility'), findsOneWidget);
      expect(settingLabel('Licenses'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-category-integrations')));
      await tester.pumpAndSettle();
      expect(
        find.text('Add and manage connections to Git hosting providers.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('integration-id')), findsNothing);
      expect(find.byKey(const Key('hosting-resource-filter')), findsNothing);

      await tester.tap(
        find.byKey(const Key('settings-category-repositoryBinding')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Choose which hosting account and remote belong to this repository.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('hosting-add-connection')), findsNothing);

      await tester.tap(
        find.byKey(const Key('settings-category-customCommands')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('integration-id')), findsOneWidget);
      expect(find.byKey(const Key('hosting-add-connection')), findsNothing);
      expect(find.byKey(const Key('diff-renderer-id')), findsNothing);

      await tester.tap(find.byKey(const Key('settings-category-diffRenderer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diff-renderer-id')), findsOneWidget);
      expect(find.byKey(const Key('integration-id')), findsNothing);

      // One stored choice for every diff view; the toolbars change it too.
      await tester.tap(find.byKey(const Key('settings-category-diffView')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings-diff-wrap')),
          matching: find.text('Wrap'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings-diff-layout')),
          matching: find.text('Side by side'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings-diff-minimap')),
          matching: find.text('Off'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        runtime.settings.current.appearance.diffView,
        const DiffViewPreferences(
          wrap: true,
          layout: DiffViewLayout.sideBySide,
          showMinimap: false,
        ),
      );

      await tester.tap(find.byKey(const Key('settings-category-appearance')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings-theme')),
          matching: find.text('Dark'),
        ),
      );
      await tester.pumpAndSettle();
      expect(runtime.settings.current.appearance.theme, 'dark');
      expectReadableSelectedCategory();

      // The same stored choice as the History toolbar's view menu.
      expect(runtime.settings.current.appearance.historyOtherRefs, isFalse);
      await tester.ensureVisible(
        find.byKey(const Key('settings-history-other-refs')),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings-history-other-refs')),
          matching: find.text('On'),
        ),
      );
      await tester.pumpAndSettle();
      expect(runtime.settings.current.appearance.historyOtherRefs, isTrue);

      await tester.tap(find.byKey(const Key('settings-category-git')));
      await tester.pumpAndSettle();
      expect(find.text('Active repository: repository'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-reset-repository')));
      await tester.pumpAndSettle();
      expect(find.text('Reset repository settings?'), findsOneWidget);
      expect(find.textContaining('Other repositories'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(MeridianButton, 'Reset repository settings').last,
      );
      await tester.pumpAndSettle();
      expect(runtime.settings.current.worktrees, isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'reset-repository-settings',
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await runtime.shutdown();
    },
  );

  testWidgets('shortcut reference searches and explains contextual winners', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime, brightness: brightness));

      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Keyboard shortcuts');
      await tester.pump();
      await tester.tap(find.text('Keyboard shortcuts').last);
      await tester.pumpAndSettle();

      expect(find.text('Context-dependent shortcuts'), findsOneWidget);
      expect(
        find.text('Each key runs the command of the focused sidebar section.'),
        findsOneWidget,
      );
      expect(find.textContaining('Create branch'), findsWidgets);
      expect(find.textContaining('Add remote'), findsWidgets);
      expect(find.textContaining('Create tag'), findsWidgets);
      expect(find.textContaining('Add worktree'), findsWidgets);
      if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../build/evidence/ui-review/shortcut-reference-${brightness.name}.png',
          ),
        );
      }

      await tester.enterText(find.byKey(const Key('shortcut-search')), 'stash');
      await tester.pump();
      expect(find.text('Create stash…'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('shortcut-search')), 'fetch');
      await tester.pump();
      expect(find.text('Fetch…'), findsOneWidget);
      expect(find.text('Open another repository'), findsNothing);

      await runtime.shutdown();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('shortcut settings validate, persist, and apply live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-category-shortcuts')));
    await tester.pumpAndSettle();

    Finder shortcutField(String command) =>
        find.byKey(Key('settings-shortcut-$command'));
    final history = shortcutField('showHistory');
    await tester.ensureVisible(history);
    Future<void> record(
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.tap(history);
      await tester.pumpAndSettle();
      expect(find.text('Press a key combination…'), findsOneWidget);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    await record(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);
    expect(
      find.text('That shortcut is already assigned to another command.'),
      findsOneWidget,
    );
    expect(runtime.settings.current.shortcutOverrides, isEmpty);

    await record(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.escape);
    expect(
      find.text(
        'Use Ctrl, Cmd, Alt or Shift with a letter, digit, function, arrow '
        'or Enter key.',
      ),
      findsOneWidget,
    );
    expect(runtime.settings.current.shortcutOverrides, isEmpty);

    await record(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyH);
    expect(runtime.settings.current.shortcutOverrides.single.binding, 'Alt+H');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(
      runtime.repositorySessions.workspace.activeTab!.navigation.pane,
      WorkspacePane.changes,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
      runtime.repositorySessions.workspace.activeTab!.navigation.pane,
      WorkspacePane.history,
    );

    await runtime.shutdown();
  });

  testWidgets(
    'commit subject and description forward Space to text input',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _WelcomeRepository(
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: 'space.txt'.codeUnits,
                ),
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      );
      final runtime = await _runtime(repository, _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      for (final key in ['commit-subject-field', 'commit-description-field']) {
        final field = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'First');
        await tester.pump();
        // Desktop text insertion happens only if Flutter leaves the key unhandled.
        // enterText alone bypasses shortcut dispatch and cannot catch this bug.
        expect(
          await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' '),
          isFalse,
        );
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'First second',
            selection: TextSelection.collapsed(offset: 12),
          ),
        );
        await tester.pump();
        expect(
          tester.widget<TextField>(field).controller!.text,
          'First second',
        );
        expect(repository.stagingRequests, isEmpty);
      }
      await tester.tap(
        find.ancestor(
          of: find.text('space.txt'),
          matching: find.byType(GitLamaFileRow),
        ),
      );
      await tester.pump();
      Focus.of(
        tester.element(find.byKey(const Key('changes-file-column'))),
      ).requestFocus();
      await tester.pump();
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isTrue);
      await tester.pumpAndSettle();
      expect(repository.stagingRequests, hasLength(1));
      await runtime.shutdown();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('contextual staging shortcut applies its persisted override', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final path = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: 'shortcut.txt'.codeUnits,
    );
    final repository = _WelcomeRepository(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        status: RepositoryStatus(
          workingTree: WorkingTreeState.dirty,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: path,
              index: ChangeKind.unmodified,
              worktree: ChangeKind.modified,
            ),
          ],
          totalEntries: BigInt.one,
          entriesTruncated: false,
          operations: const [],
        ),
      ),
    );
    final runtime = await _runtime(repository, _Picker(null));
    await runtime.settings.saveDurable(
      runtime.settings.current.copyWith(
        shortcutOverrides: const [
          ShortcutOverride(commandId: 'stageToggle', binding: 'Alt+9'),
        ],
      ),
    );
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('shortcut.txt'),
      matching: find.byType(GitLamaFileRow),
    );
    await tester.tap(row);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(repository.stagingRequests, hasLength(1));
    expect(repository.stagingRequests.single.side, StagingSide.unstaged);
    expect(repository.stagingRequests.single.paths, [path.units]);
    await runtime.shutdown();
  });

  testWidgets('settings swap the page list for a menu in narrow windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await _runtime(_WelcomeRepository(), _Picker(null));
    await runtime.repositorySessions.open('/repository');
    await tester.pumpWidget(_app(runtime));

    await _selectToolbarOverflow(tester, 'Settings');
    final dialog = find.byType(MeridianSettingsDialog);
    expect(find.byKey(const Key('settings-category-appearance')), findsOne);
    expect(
      find.descendant(of: dialog, matching: find.byType(MeridianSelect<int>)),
      findsNothing,
    );

    // Below 600 pixels of dialog width the pages move into a menu.
    tester.view.physicalSize = const Size(560, 600);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.byType(MeridianSelect<int>)),
      findsOne,
    );
    expect(find.byKey(const Key('settings-category-appearance')), findsNothing);
    expect(tester.takeException(), isNull);

    await runtime.shutdown();
  });
  group('inspection outside the inspector', () {
    const head = 'cccccccccccccccccccccccccccccccccccccccc';
    final file = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: 'lib/file.txt'.codeUnits,
    );

    _WelcomeRepository changesRepository({String? headObjectId = head}) =>
        _WelcomeRepository(
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            identity: RepositoryIdentity(
              commonGitDir: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository/.git'.codeUnits,
              ),
              worktreeRoot: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository'.codeUnits,
              ),
              gitDir: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository/.git'.codeUnits,
              ),
              kind: RepositoryKind.worktree,
              headKind: HeadKind.attached,
              gitMajor: 2,
              gitMinor: 45,
              gitPatch: 0,
            ),
            status: RepositoryStatus(
              workingTree: WorkingTreeState.dirty,
              headObjectId: headObjectId,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: [
                RepositoryStatusEntry(
                  kind: StatusEntryKind.ordinary,
                  path: file,
                  index: ChangeKind.unmodified,
                  worktree: ChangeKind.modified,
                ),
              ],
              totalEntries: BigInt.one,
              entriesTruncated: false,
              operations: const [],
            ),
          ),
          historyRows: const [
            HistoryTopologyRow(
              objectId: head,
              parents: [],
              refs: [],
              lane: 0,
              shape: 0,
            ),
          ],
          inspectionFiles: [
            CommitFileChange(
              oldMode: 0x81a4,
              newMode: 0x81a4,
              kind: CommitFileChangeKind.modified,
              oldPath: 'lib/file.txt'.codeUnits,
              newPath: 'lib/file.txt'.codeUnits,
            ),
          ],
        );

    Future<Menu> changesMenu(WidgetTester tester) async => (await tester
        .widget<GitLamaContextMenuWidget>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (widget) =>
                      widget is GitLamaFileRow &&
                      widget.path.endsWith('file.txt'),
                ),
                matching: find.byType(GitLamaContextMenuWidget),
              )
              .first,
        )
        .testMenu())!;

    testWidgets('a Changes file opens its blame at HEAD in a window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final windows = _InspectionWindows();
      final runtime = await _withInspection(
        await _runtime(changesRepository(), _Picker(null)),
        windows: windows,
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      final menu = await changesMenu(tester);
      final blame = menu.children.whereType<MenuAction>().firstWhere(
        (action) => action.title == 'Blame (HEAD)',
      );
      blame.callback();
      await tester.pumpAndSettle();
      final location = windows.opened.single.location;
      expect(location.target, const CommitTarget(head));
      expect(location.path, 'lib/file.txt'.codeUnits);
      expect(location.lens, InspectorLens.blame);
      menu.children
          .whereType<MenuAction>()
          .firstWhere((action) => action.title == 'File history (HEAD)')
          .callback();
      await tester.pumpAndSettle();
      expect(windows.opened.last.location.lens, InspectorLens.history);
      await runtime.shutdown();
    });

    testWidgets('an unborn HEAD explains why inspection is unavailable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = await _withInspection(
        await _runtime(changesRepository(headObjectId: null), _Picker(null)),
        windows: _InspectionWindows(),
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      final blame = (await changesMenu(tester)).children
          .whereType<MenuAction>()
          .firstWhere(
            (action) => action.title?.startsWith('Blame (HEAD)') ?? false,
          );
      expect(blame.title, 'Blame (HEAD) — No commit yet');
      expect(blame.attributes.disabled, isTrue);
      await runtime.shutdown();
    });

    testWidgets('the open-in setting and the modifier choose pane or window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final windows = _InspectionWindows();
      final runtime = await _withInspection(
        await _runtime(changesRepository(), _Picker(null)),
        windows: windows,
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(findWorkspacePaneAction('History'));
      await tester.pumpAndSettle();
      await runtime.repositorySessions.history.select(head);
      await tester.pumpAndSettle();
      final inspector = runtime.repositorySessions.inspector;

      // The default opens Blame in the pane.
      final fileRow = find.byKey(const ValueKey('commit-file-lib/file.txt'));
      await tester.tap(fileRow);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('inspector-lens')),
          matching: find.byTooltip('Blame'),
        ),
      );
      await tester.pumpAndSettle();
      expect(inspector.current.location!.lens, InspectorLens.blame);
      expect(windows.opened, isEmpty);

      // Holding the modifier opens the other place once.
      await tester.tap(find.byKey(const ValueKey('inspector-back')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('inspector-lens')),
          matching: find.byTooltip('History'),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(windows.opened.single.location.lens, InspectorLens.history);
      expect(inspector.current.location!.lens, InspectorLens.diff);

      // The setting flips the default.
      await runtime.settings.saveDurable(
        runtime.settings.current.copyWith(
          appearance: runtime.settings.current.appearance.copyWith(
            inspectionOpenIn: 'window',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('inspector-lens')),
          matching: find.byTooltip('Blame'),
        ),
      );
      await tester.pumpAndSettle();
      expect(windows.opened.last.location.lens, InspectorLens.blame);
      expect(inspector.current.location!.lens, InspectorLens.diff);
      await runtime.shutdown();
    });

    testWidgets('inspector commands navigate the History inspector', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = await _runtime(changesRepository(), _Picker(null));
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.tap(findWorkspacePaneAction('History'));
      await tester.pumpAndSettle();
      await runtime.repositorySessions.history.select(head);
      await tester.pumpAndSettle();
      final inspector = runtime.repositorySessions.inspector;

      Future<void> runCommand(String label) async {
        await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, label);
        await tester.pump();
        await tester.tap(find.widgetWithText(MeridianListRow, label));
        await tester.pumpAndSettle();
      }

      await runCommand('Show contents of the file');
      expect(inspector.current.location!.path, 'lib/file.txt'.codeUnits);
      expect(inspector.current.location!.lens, InspectorLens.contents);
      await runCommand('Inspector back');
      expect(inspector.current.location!.path, isNull);
      await runCommand('Inspector forward');
      expect(inspector.current.location!.lens, InspectorLens.contents);
      await runCommand('Browse all files of the commit');
      expect(inspector.current.location!.scope, InspectorScope.all);
      await runCommand('Maximize or restore inspector');
      expect(find.byKey(const ValueKey('history-row-$head')), findsNothing);
      await runCommand('Maximize or restore inspector');
      expect(find.byKey(const ValueKey('history-row-$head')), findsOneWidget);
      await runtime.shutdown();
    });

    testWidgets('the main window reveals commits for inspector windows', (
      tester,
    ) async {
      final reveal = _InspectorReveal();
      final runtime = await _withInspection(
        await _runtime(changesRepository(), _Picker(null)),
        windows: _InspectionWindows(),
        reveal: reveal,
      );
      await runtime.repositorySessions.open('/repository');
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      final repository =
          runtime.repositorySessions.workspace.activeTab!.canonicalIdentity!;
      late bool revealed;
      await tester.runAsync(() async {
        revealed = await reveal.handler!(
          InspectorRevealRequest(repository: repository, commit: head),
        );
      });
      await tester.pumpAndSettle();
      expect(revealed, isTrue);
      expect(
        runtime.repositorySessions.workspace.activeTab!.navigation.pane,
        WorkspacePane.history,
      );
      expect(
        runtime.repositorySessions.history.current.page!.selectedObjectIds,
        [head],
      );
      late bool unknown;
      await tester.runAsync(() async {
        unknown = await reveal.handler!(
          InspectorRevealRequest(
            repository: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: '/elsewhere'.codeUnits,
            ),
            commit: head,
          ),
        );
      });
      expect(unknown, isFalse);
      await runtime.shutdown();
    });
  });
}

Future<void> _selectToolbarOverflow(WidgetTester tester, String label) async {
  final previousPresenter = nativeMenuTestPresenter;
  nativeMenuTestPresenter = (context, menu, position) async {
    final action = flatMenuActions(
      menu,
    ).firstWhere((item) => item.title == label);
    action.callback();
    return MenuResult(itemSelected: true);
  };
  addTearDown(() => nativeMenuTestPresenter = previousPresenter);
  await tester.tap(find.byKey(const Key('toolbar-overflow')));
  await tester.pumpAndSettle();
}

Future<void> _openCreateWorktree(
  WidgetTester tester,
  AppRuntime runtime, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) async {
  await runtime.repositorySessions.open('/repository');
  await tester.pumpWidget(
    _app(runtime, locale: locale, brightness: brightness),
  );
  final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));
  await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, l10n.commandAddWorktree);
  await tester.pump();
  await tester.tap(find.text(l10n.commandAddWorktree).last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(MeridianButton, l10n.extensionWorktreeCreate),
  );
  await tester.pumpAndSettle();
}

Future<AppRuntime> _runtime(
  RepositorySessionRepository repository,
  DirectoryPickerRepository picker, [
  CloneRepository? clones,
  OperationCenterService? operationCenter,
  CliForwardingController? cliForwarding,
  SettingsService? providedSettings,
  FakeRepositoryIconRepository? icons,
  SourceSyntaxService? sourceSyntax,
]) async {
  final settings = providedSettings ?? fakeSettingsService();
  await settings.initialize();
  final sessions = sourceSyntax == null
      ? RepositorySessionService(
          repository,
          settings,
          picker,
          clones == null ? null : CloneService(clones),
        )
      : RepositorySessionService.composed(
          SessionBackends.of(repository),
          settings: settings,
          picker: picker,
          clones: clones == null ? null : CloneService(clones),
          viewCache: const NoSessionViewCache(),
          remotes: const NoWorkspaceRemotes(),
          sourceSyntax: sourceSyntax,
        );
  final recovery = fakeRecoveryService(settings);
  final operations = operationCenter ?? OperationCenterService.empty();
  final appearances = RepositoryAppearanceService(
    icons ?? FakeRepositoryIconRepository(),
    settings,
  )..initialize();
  return testRuntime(
    repositorySessions: sessions,
    settings: settings,
    repositoryAppearances: appearances,
    recovery: recovery,
    operationCenter: operations,
    cliForwarding: cliForwarding ?? const DisabledCliForwardingController(),
    shutdown: () async {
      await sessions.dispose();
      await operations.dispose();
      await appearances.dispose();
      await settings.dispose();
    },
  );
}

final class _TestCliController implements CliForwardingController {
  final StreamController<CliForwardedCommand> _commands =
      StreamController<CliForwardedCommand>.broadcast(sync: true);

  @override
  Stream<CliForwardedCommand> get commands => _commands.stream;

  @override
  void attach() {}

  @override
  void detach() {}

  void add(CliForwardedCommand command) => _commands.add(command);

  Future<void> close() => _commands.close();
}

final class _FailingCloneRepository implements CloneRepository {
  _FailingCloneRepository({this.hostKeyFlow = false});

  final bool hostKeyFlow;
  CloneAttemptSnapshot? _snapshot;
  String? destination;
  var rejectCount = 0;

  @override
  Future<CloneAttemptSnapshot> create({
    required String source,
    required String destination,
    String? initialBranch,
    required int generation,
  }) async {
    this.destination = destination;
    if (hostKeyFlow) {
      return _snapshot = CloneAttemptSnapshot(
        attemptId: BigInt.one,
        generation: generation,
        phase: CloneAttemptPhase.pending,
        partialDestination: false,
      );
    }
    throw const CloneException(CloneFailure(CloneFailureCode.invalidSource));
  }

  @override
  Future<void> cancel(CloneAttemptSnapshot attempt) async {}

  @override
  Future<void> dismiss(CloneAttemptSnapshot attempt) async {}

  @override
  Future<CloneRunCompletion> run(CloneAttemptSnapshot attempt) async {
    if (!hostKeyFlow) throw UnimplementedError();
    _snapshot = CloneAttemptSnapshot(
      attemptId: attempt.attemptId,
      generation: attempt.generation,
      phase: CloneAttemptPhase.failed,
      failure: const CloneFailure(CloneFailureCode.hostKey),
      partialDestination: false,
    );
    return CloneRunCompletion(snapshot: _snapshot!);
  }

  @override
  Future<CloneRunCompletion> runWithCredentials(
    CloneAttemptSnapshot attempt, {
    String? username,
    String? password,
    String? token,
  }) => throw UnimplementedError();

  @override
  Future<HostKeyChallenge> probeHostKey(CloneAttemptSnapshot attempt) async {
    final challenge = HostKeyChallenge(
      challengeId: BigInt.from(7),
      host: 'example.test',
      port: 22,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:fixture',
    );
    _snapshot = CloneAttemptSnapshot(
      attemptId: attempt.attemptId,
      generation: attempt.generation,
      phase: CloneAttemptPhase.failed,
      failure: const CloneFailure(CloneFailureCode.hostKey),
      partialDestination: false,
      hostKeyChallenge: challenge,
    );
    return challenge;
  }

  @override
  Future<void> acceptHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) => throw UnimplementedError();

  @override
  Future<void> rejectHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) async {
    rejectCount += 1;
    _snapshot = CloneAttemptSnapshot(
      attemptId: attempt.attemptId,
      generation: attempt.generation,
      phase: CloneAttemptPhase.failed,
      failure: const CloneFailure(CloneFailureCode.hostKey),
      partialDestination: false,
    );
  }

  @override
  Future<CloneRunCompletion> runWithHostKey(CloneAttemptSnapshot attempt) =>
      throw UnimplementedError();

  @override
  Future<CloneAttemptSnapshot> retry(
    CloneAttemptSnapshot attempt, {
    String? destination,
  }) => throw UnimplementedError();

  @override
  Future<CloneAttemptSnapshot> snapshot(CloneAttemptSnapshot attempt) =>
      Future.value(_snapshot!);
}

final class _ControlledCloneRepository implements CloneRepository {
  final _firstRun = Completer<CloneRunCompletion>();
  late CloneAttemptSnapshot _snapshot;
  var _runCount = 0;
  var cancelCount = 0;
  var retryCount = 0;
  var dismissCount = 0;

  @override
  Future<CloneAttemptSnapshot> create({
    required String source,
    required String destination,
    String? initialBranch,
    required int generation,
  }) async => _snapshot = CloneAttemptSnapshot(
    attemptId: BigInt.from(41),
    generation: generation,
    phase: CloneAttemptPhase.running,
    partialDestination: false,
  );

  @override
  Future<CloneRunCompletion> run(CloneAttemptSnapshot attempt) async {
    _runCount += 1;
    if (_runCount == 1) return _firstRun.future;
    _snapshot = CloneAttemptSnapshot(
      attemptId: attempt.attemptId,
      generation: attempt.generation,
      phase: CloneAttemptPhase.failed,
      failure: const CloneFailure(CloneFailureCode.git),
      partialDestination: false,
    );
    return CloneRunCompletion(snapshot: _snapshot);
  }

  @override
  Future<void> cancel(CloneAttemptSnapshot attempt) async {
    cancelCount += 1;
    _snapshot = CloneAttemptSnapshot(
      attemptId: attempt.attemptId,
      generation: attempt.generation,
      phase: CloneAttemptPhase.canceled,
      partialDestination: false,
    );
    if (!_firstRun.isCompleted) {
      _firstRun.complete(CloneRunCompletion(snapshot: _snapshot));
    }
  }

  @override
  Future<CloneAttemptSnapshot> retry(
    CloneAttemptSnapshot attempt, {
    String? destination,
  }) async {
    retryCount += 1;
    return _snapshot = CloneAttemptSnapshot(
      attemptId: attempt.attemptId,
      generation: attempt.generation,
      phase: CloneAttemptPhase.pending,
      partialDestination: false,
    );
  }

  @override
  Future<void> dismiss(CloneAttemptSnapshot attempt) async {
    dismissCount += 1;
  }

  @override
  Future<CloneAttemptSnapshot> snapshot(CloneAttemptSnapshot attempt) async =>
      _snapshot;

  @override
  Future<CloneRunCompletion> runWithCredentials(
    CloneAttemptSnapshot attempt, {
    String? username,
    String? password,
    String? token,
  }) => throw UnimplementedError();

  @override
  Future<HostKeyChallenge> probeHostKey(CloneAttemptSnapshot attempt) =>
      throw UnimplementedError();

  @override
  Future<void> acceptHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) => throw UnimplementedError();

  @override
  Future<void> rejectHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) => throw UnimplementedError();

  @override
  Future<CloneRunCompletion> runWithHostKey(CloneAttemptSnapshot attempt) =>
      throw UnimplementedError();
}

Widget _app(
  AppRuntime runtime, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  builder: (context, child) => StatusNotificationScope(child: child!),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildAppTheme(brightness),
  home: HomeScreen(runtime: runtime),
);

final class _Picker implements DirectoryPickerRepository {
  @override
  Future<String?> chooseSaveFile({
    required String suggestedName,
    required String extension,
  }) async => null;

  _Picker(this.path);
  String? path;
  Completer<String?>? pendingDirectory;
  bool? canCreateDirectories;
  int directoryCalls = 0;

  @override
  Future<String?> chooseDirectory({required bool canCreateDirectories}) async {
    this.canCreateDirectories = canCreateDirectories;
    directoryCalls += 1;
    return pendingDirectory == null ? path : await pendingDirectory!.future;
  }

  @override
  Future<String?> choosePatchFile() async => path;
}

final class _WelcomeRepository
    implements
        RepositorySessionRepository,
        PatchRepositorySessionRepository,
        TransferRepositorySessionRepository,
        StashRepositorySessionRepository,
        HistoryMutationRepositorySessionRepository,
        RebaseRepositorySessionRepository,
        ConflictRepositorySessionRepository,
        NamedSnapshotRepositorySessionRepository,
        ExtensionRepositorySessionRepository,
        IntegrationRepositorySessionRepository,
        PowerToolsRepositorySessionRepository,
        DiffRendererRepositorySessionRepository {
  _WelcomeRepository({
    this.snapshot,
    this.openFailure,
    this.indexLock,
    this.historyRows = const [],
    this.historySegments = const [],
    this.historyLaneCount,
    this.workingDiffResult,
    this.workingDiffPages = const {},
    this.workingDiffBarriers = const [],
    this.commitDiffResult,
    this.diffSearchMatches = const [],
    this.inspectionFiles = const [],
    this.treeEntries = const [],
    this.treeHistoryEntries = const [],
    this.treeFileBytes = const [],
    this.imageDiffResult = const ImageDiffContent(),
    this.commitToolsResult = const CommitTools(),
    this.commitWarnings = const [],
    this.commitResult = const CommitExecutionResult(
      state: CommitExecutionState.completed,
    ),
    this.activityPage = const ActivityPage(records: [], evictedThroughId: null),
    this.lfsAvailable = false,
    this.integrationCandidates = const [],
    this.worktreeEntries,
    this.failRefresh = false,
    this.workingDiffTimeouts = 0,
    StatusAcceleration? acceleration,
  }) : acceleration =
           acceleration ??
           const StatusAcceleration(
             untrackedCache: true,
             fsmonitor: false,
             fsmonitorAvailable: false,
           );

  /// What [statusAcceleration] reports; enabling turns on what it lacks.
  StatusAcceleration acceleration;
  int accelerationEnables = 0;

  @override
  Future<StatusAcceleration> statusAcceleration(
    RepositorySessionIdentity identity,
  ) async => acceleration;

  @override
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  ) async {
    accelerationEnables += 1;
    return acceleration = StatusAcceleration(
      untrackedCache: true,
      fsmonitor: acceleration.fsmonitorAvailable,
      fsmonitorAvailable: acceleration.fsmonitorAvailable,
      lastScan: acceleration.lastScan,
    );
  }

  /// How many first working-diff calls report that Git has not answered yet.
  final int workingDiffTimeouts;

  final RepositorySnapshot? snapshot;
  List<WorktreeEntry>? worktreeEntries;
  final extensionBarriers = <Completer<RepositoryExtensionInventory>>[];
  int extensionReads = 0;
  final RepositoryFailureCode? openFailure;
  final IndexLockInspection? indexLock;
  final List<HistoryTopologyRow> historyRows;
  final List<HistoryTopologySegment> historySegments;
  final int? historyLaneCount;
  final DiffPage? workingDiffResult;
  final Map<int, DiffPage> workingDiffPages;
  final List<Completer<DiffPage>> workingDiffBarriers;
  final List<(StagingSide, List<int>?, List<int>?)> workingDiffRequests = [];
  var workingDiffCalls = 0;
  var workingDiffConcurrent = 0;
  var maximumWorkingDiffConcurrent = 0;
  StagingSide? workingDiffSide;
  DiffViewLayout? workingDiffLayout;
  int? workingDiffContextLines;
  DiffWhitespace? workingDiffWhitespace;
  List<int>? workingDiffOldPath;
  List<int>? workingDiffNewPath;
  int? workingDiffMaximumRows;
  final DiffPage? commitDiffResult;
  final List<int> diffSearchMatches;
  final List<CommitFileChange> inspectionFiles;
  final List<CommitTreeEntry> treeEntries;
  final List<PathHistoryEntry> treeHistoryEntries;
  final List<int> treeFileBytes;
  List<int>? treeContentPath;
  DiffLoadOptions? commitDiffOptions;
  List<int>? diffSearchQuery;
  bool? diffSearchCaseSensitive;
  bool? powerSearchCaseSensitive;
  DiffSearchScope? powerSearchScope;
  List<int>? blamePath;
  List<int>? pathHistoryPath;
  final Set<String> _selectedHistoryIds = {};
  final ImageDiffContent imageDiffResult;
  final workingImageDiffRequests = <(StagingSide, List<int>?, List<int>?)>[];
  final CommitTools commitToolsResult;
  final commitToolsBarriers = <Completer<CommitTools>>[];
  var commitToolsCalls = 0;
  final List<CommitWarning> commitWarnings;
  CommitExecutionResult commitResult;
  ActivityPage activityPage;
  final bool lfsAvailable;
  final bool integrationRequiresConfirmation = true;
  final bool failRefresh;
  final List<IntegrationCandidate> integrationCandidates;
  ConflictSnapshot? conflictSnapshot;

  /// Each whole side chosen, as `path:side`. With [resolveChosenSides] the
  /// chosen file moves from the conflicts to the resolved files.
  final conflictSideChoices = <String>[];
  var resolveChosenSides = false;
  final conflictUndos = <String>[];
  RefMutationRequest? refMutationRequest;
  final refMutationRequests = <RefMutationRequest>[];
  List<RefMutationWarning> refMutationWarnings = const [];

  /// Whether a ref mutation had run when the last transfer was previewed.
  bool? transferAfterRefMutation;
  BigInt? executedRefMutationToken;
  String? initializedPath;
  bool? initializedBare;
  var refreshCount = 0;
  var integrationExecuted = false;
  IntegrationRequest? integrationRequest;
  final List<StagingRequest> stagingRequests = [];
  StagingExecutionState stagingOutcome = StagingExecutionState.completed;
  final List<CommitRequest> commitRequests = [];
  final List<DiscardRequest> discardRequests = [];
  BigInt? executedDiscardToken;
  final List<BigInt> executedDiscardTokens = [];
  PatchExportRequest? patchExportRequest;
  String? patchApplyPath;
  BigInt? executedPatchExportToken;
  BigInt? executedPatchApplyToken;
  final List<NamedSnapshot> namedSnapshotEntries = [];
  var namedSnapshotRestoreExecuted = false;
  RepositoryExtensionMutationResult extensionResult =
      const RepositoryExtensionMutationResult(
        state: RepositoryExtensionMutationState.completed,
        activityIds: [],
      );
  RepositoryExtensionMutationRequest? extensionRequest;
  TransferRequest? transferRequest;
  BigInt? executedTransferToken;
  Completer<TransferExecutionResult>? transferGate;
  final pendingEvents = <RepositorySessionEvent>[];
  BigInt? canceledTransferToken;
  HistoryMutationRequest? historyMutationRequest;
  BigInt? executedHistoryMutationToken;
  Completer<HistoryMutationExecutionResult>? historyMutationGate;
  var historyMutationCancels = 0;
  List<RebaseInstruction>? rebaseInstructions;
  BigInt? executedRebaseToken;
  ConflictRegionChoice? conflictRegionChoice;
  List<int>? conflictSavedResult;
  ConflictSequencerAction? conflictSequencerAction;
  String? conflictMergeMessage;
  StashRequest? stashRequest;
  BigInt? executedStashToken;
  Completer<void>? stagingBarrier;
  StagingPhase? stagingPhaseValue;
  Completer<void>? commitBarrier;
  BigInt? removedIndexLockToken;
  RepositorySessionIdentity? removedIndexLockSession;
  var _revealSequence = 0;

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  }) async {
    initializedPath = path;
    initializedBare = bare;
    throw const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.existingRepository),
    );
  }

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  open(String path, int generation) async {
    final failure = openFailure;
    if (failure != null) {
      throw RepositorySessionException(RepositoryFailure(failure));
    }
    return (
      identity: RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: generation,
      ),
      snapshot:
          snapshot ??
          RepositorySnapshot(
            revision: BigInt.zero,
            phase: RepositoryPhase.unloaded,
          ),
    );
  }

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) =>
      open('recent', generation);

  @override
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) async => ActivityPage(
    records: activityPage.records
        .skip(
          (activityPage.records.length - maximumRecords).clamp(
            0,
            activityPage.records.length,
          ),
        )
        .toList(),
    evictedThroughId: activityPage.evictedThroughId,
  );

  @override
  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) async => ActivityPage(
    records: activityPage.records
        .where((record) => record.id == activityId)
        .toList(),
    evictedThroughId: activityPage.evictedThroughId,
  );

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = 512,
  }) async {
    if (!complete) _shownOtherRefs = otherRefs;
    final rows = branchFilteredRows([
      ...historyRows,
      if (_shownOtherRefs) ...otherRefsHistoryRows,
    ], branchFilter);
    return HistoryPage(
      requestId: BigInt.one,
      complete: complete,
      totalRows: rows.length,
      offset: 0,
      rows: rows,
      segments: branchFilter.isEmpty ? historySegments : const [],
      laneCount: historyLaneCount ?? (rows.isEmpty ? 0 : 1),
      payloadBytes: 0,
      branchFilter: branchFilter,
      otherRefs: _shownOtherRefs,
    );
  }

  /// Commits only references outside the standard namespaces reach; the
  /// history has them when it loads with other references.
  List<HistoryTopologyRow> otherRefsHistoryRows = const [];
  var _shownOtherRefs = false;

  /// The native session's branch filter, which later loads keep.
  var branchFilter = HistoryBranchFilter.none;
  final List<HistoryBranchFilter> branchFilterRequests = [];

  @override
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = 512,
  }) async {
    branchFilterRequests.add(filter);
    branchFilter = filter;
    if (requestId == BigInt.zero) return null;
    return loadHistory(identity, complete: true, maximumRows: maximumRows);
  }

  @override
  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) => loadHistory(identity, complete: true, maximumRows: maximumRows);

  @override
  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = 512,
  }) => loadHistory(identity, complete: true, maximumRows: maximumRows);

  @override
  Future<HistoryPage> selectHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String? objectId,
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    required int offset,
    int maximumRows = 512,
  }) async {
    if (!_shownOtherRefs &&
        otherRefsHistoryRows.any((row) => row.objectId == objectId)) {
      // Native refuses a commit the loaded history does not have.
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOptions),
      );
    }
    if (reveal) _revealSequence += 1;
    if (objectId == null) {
      _selectedHistoryIds.clear();
    } else if (toggle) {
      if (!_selectedHistoryIds.add(objectId)) {
        _selectedHistoryIds.remove(objectId);
      }
    } else {
      _selectedHistoryIds
        ..clear()
        ..add(objectId);
    }
    final selected = _selectedHistoryIds.toList(growable: false);
    final page = await historyPage(
      identity,
      requestId: requestId,
      offset: offset,
      maximumRows: maximumRows,
    );
    return HistoryPage(
      requestId: page.requestId,
      complete: page.complete,
      totalRows: page.totalRows,
      offset: page.offset,
      rows: [
        for (final row in page.rows)
          HistoryTopologyRow(
            objectId: row.objectId,
            parents: row.parents,
            refs: row.refs,
            refCount: row.refCount,
            refsTruncated: row.refsTruncated,
            lane: row.lane,
            shape: row.shape,
            subject: row.subject,
            author: row.author,
            avatarHash: row.avatarHash,
            authorTime: row.authorTime,
            metadataFailure: row.metadataFailure,
            selected: _selectedHistoryIds.contains(row.objectId),
            lit: _selectedHistoryIds.contains(row.objectId),
            current: row.current,
            wipChangedFiles: row.wipChangedFiles,
            wipStagedFiles: row.wipStagedFiles,
          ),
      ],
      segments: page.segments,
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes,
      lightingActive: _selectedHistoryIds.isNotEmpty,
      currentObjectId: objectId,
      selectedObjectIds: selected,
      comparisonOldObjectId: selected.length == 2 ? selected.first : null,
      comparisonNewObjectId: selected.length == 2 ? selected.last : null,
      focusedObjectId: focus ? objectId : page.focusedObjectId,
      revealSequence: _revealSequence,
      revealObjectId: reveal ? objectId : null,
      revealIndex: reveal && objectId != null
          ? page.rows.indexWhere((row) => row.objectId == objectId)
          : null,
    );
  }

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = 512,
  }) async {
    commitDiffOptions = options;
    return commitDiffResult ?? _emptyWelcomeDiff;
  }

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => commitDiffResult ?? _emptyWelcomeDiff;

  @override
  Future<DiffRendererPreview> validateDiffRenderer(
    RepositorySessionIdentity identity,
    DiffRendererDefinition definition,
  ) async => _rendererPreview(identity, definition);

  @override
  Future<DiffRendererPreview> previewDiffRenderer(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required DiffRendererDefinition definition,
  }) async => _rendererPreview(identity, definition);

  DiffRendererPreview _rendererPreview(
    RepositorySessionIdentity identity,
    DiffRendererDefinition definition,
  ) => DiffRendererPreview(
    token: BigInt.one,
    source: identity,
    title: definition.title,
    executable: '/renderer',
    capabilityArguments: const ['--gitlama-capabilities'],
    arguments: const ['--gitlama-render=text/plain'],
    protocol: 'gitlama-diff-renderer-v1',
    mediaType: 'text/plain',
    inputBytes: 32,
    outputLimitBytes: 65536,
    timeoutSeconds: 5,
  );

  @override
  Future<DiffRendererResult> executeDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const DiffRendererResult(
    state: DiffRendererState.fallback,
    failure: DiffRendererFailureCode.processFailed,
  );

  @override
  Future<DiffRendererResult> pollDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const DiffRendererResult(
    state: DiffRendererState.fallback,
    failure: DiffRendererFailureCode.processFailed,
  );

  @override
  Future<bool> cancelDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<DiffPage> workingDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = 512,
  }) async {
    workingDiffSide = side;
    workingDiffLayout = layout;
    workingDiffContextLines = contextLines;
    workingDiffWhitespace = whitespace;
    workingDiffOldPath = oldPath;
    workingDiffNewPath = newPath;
    workingDiffMaximumRows = maximumRows;
    workingDiffRequests.add((side, oldPath, newPath));
    final call = workingDiffCalls++;
    workingDiffConcurrent += 1;
    if (workingDiffConcurrent > maximumWorkingDiffConcurrent) {
      maximumWorkingDiffConcurrent = workingDiffConcurrent;
    }
    try {
      if (call < workingDiffTimeouts) {
        throw const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.timedOut),
        );
      }
      if (call < workingDiffBarriers.length) {
        return await workingDiffBarriers[call].future;
      }
      return workingDiffResult ?? _emptyWelcomeDiff;
    } finally {
      workingDiffConcurrent -= 1;
    }
  }

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => workingDiffPages[offset] ?? _emptyWelcomeDiff;

  @override
  Future<StagingPhase?> stagingPhase(
    RepositorySessionIdentity identity,
  ) async => stagingPhaseValue;

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) async {
    stagingRequests.add(request);
    await stagingBarrier?.future;
    return StagingExecutionResult(state: stagingOutcome);
  }

  @override
  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) async {
    diffSearchQuery = query;
    diffSearchCaseSensitive = caseSensitive;
    return DiffSearchResult(
      requestId: requestId,
      matches: diffSearchMatches,
      totalMatches: diffSearchMatches.length,
      truncated: false,
    );
  }

  @override
  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  }) async => utf8.encode(
    'patch ${working ? 'working' : 'commit'} ${rowIds.join(',')}',
  );

  @override
  Future<List<int>> diffHunks(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumPositions = 10000,
  }) async => const [];

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => imageDiffResult;

  @override
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async {
    workingImageDiffRequests.add((side, oldPath, newPath));
    return imageDiffResult;
  }

  @override
  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  }) async => [
    for (final objectId in objectIds)
      switch (historyRows
          .where((row) => row.objectId == objectId && row.subject.isNotEmpty)
          .firstOrNull) {
        final row? => HistoryMetadata(
          objectId: objectId,
          subject: row.subject,
          author: row.author,
          authorTime: row.authorTime,
        ),
        null => HistoryMetadata(
          objectId: objectId,
          subject: 'Commit subject'.codeUnits,
          author: 'Fixture'.codeUnits,
        ),
      },
  ];

  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) async => indexLock ?? const IndexLockInspection(present: false);

  @override
  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    removedIndexLockSession = identity;
    removedIndexLockToken = token;
  }

  @override
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  ) async => const RepositoryLockInspection(locks: []);

  @override
  Future<bool> removeRepositoryLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => false;

  @override
  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = 512,
  }) async {
    final page = await historyPage(
      identity,
      requestId: requestId,
      offset: offset,
    );
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: page.totalRows,
      offset: page.offset,
      rows: page.rows,
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes,
      querySequence: 1,
      queryActive: query.active,
      acceptedQuery: query.text,
      branchFilter: branchFilter,
    );
  }

  @override
  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = 512,
  }) => historyPage(identity, requestId: requestId, offset: offset);

  @override
  Future<ReflogPage> reflog(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximumRows = 256,
  }) async => const ReflogPage(entries: []);

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) async {
    final row = historyRows
        .where((row) => row.objectId == commit && row.subject.isNotEmpty)
        .firstOrNull;
    return CommitInspection(
      detail: CommitIdentityDetail(
        commit: commit,
        tree: commit,
        parents:
            row?.parents ?? (firstParent == null ? const [] : [firstParent]),
        author: row?.author ?? 'Fixture'.codeUnits,
        authorTime: row?.authorTime ?? 1,
        authorTimezone: '+0000'.codeUnits,
        committer: row?.author ?? 'Fixture'.codeUnits,
        committerTime: row?.authorTime ?? 1,
        committerTimezone: '+0000'.codeUnits,
        message: row?.subject ?? 'Commit subject'.codeUnits,
      ),
      files: inspectionFiles,
    );
  }

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) async => CommitTreePage(commit: commit, entries: treeEntries);

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) async {
    treeContentPath = path;
    return treeFileBytes;
  }

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) async {
    pathHistoryPath = path;
    return PathHistoryPage(
      entries: treeHistoryEntries,
      renameHops: 0,
      incomplete: false,
    );
  }

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) async => const RangeHistoryResult(entries: [], incomplete: false);

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = 512,
  }) async {
    blamePath = path;
    return BlamePage(
      requestId: BigInt.one,
      revision: revision,
      path: path,
      totalRows: 0,
      offset: 0,
      rows: const [],
    );
  }

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => BlamePage(
    requestId: requestId,
    revision: '',
    path: const [],
    totalRows: 0,
    offset: offset,
    rows: const [],
  );

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) async => RestorePreview(
    token: BigInt.one,
    commit: commit,
    path: path,
    sourceBytes: const [],
  );

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) async => const RestoreResult(state: RestoreState.restored);

  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) async {
    refMutationRequest = request;
    refMutationRequests.add(request);
    return RefMutationPreview(
      token: BigInt.from(88),
      kind: request.kind,
      arguments: ['branch', request.name ?? ''],
      warnings: refMutationWarnings,
    );
  }

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedRefMutationToken = token;
    return const RefMutationExecutionResult(
      state: RefMutationExecutionState.completed,
    );
  }

  @override
  Future<CommitTools> commitTools(RepositorySessionIdentity identity) async {
    final call = commitToolsCalls++;
    return call < commitToolsBarriers.length
        ? await commitToolsBarriers[call].future
        : commitToolsResult;
  }

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) async {
    commitRequests.add(request);
    return CommitPreview(
      token: BigInt.from(commitRequests.length),
      warnings: request.amend ? commitWarnings : const [],
      arguments: const ['commit', '--file=-'],
    );
  }

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    await commitBarrier?.future;
    return commitResult;
  }

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) async {
    discardRequests.add(request);
    return DiscardPreview(
      token: BigInt.from(discardRequests.length),
      kind: request.kind,
      fileCount: request.paths.isEmpty ? 1 : request.paths.length,
      arguments: const [],
    );
  }

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedDiscardToken = token;
    executedDiscardTokens.add(token);
    return const DiscardExecutionResult(state: DiscardExecutionState.completed);
  }

  @override
  Future<PatchExportPreview> previewPatchExport(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async {
    patchExportRequest = request;
    return PatchExportPreview(
      token: BigInt.from(81),
      scope: request.selectedPaths.isEmpty
          ? PatchExportScope.head
          : PatchExportScope.selectedFilesUnstaged,
      format: PatchFormat.unifiedDiff,
      filename: request.selectedPaths.isEmpty
          ? 'repository.patch'
          : 'repository-selected.patch',
      destination: '${request.destinationDirectory}/repository.patch',
      byteCount: 128,
      requiresOverwrite: false,
    );
  }

  @override
  Future<PatchExportContent> patchExportContent(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async => PatchExportContent(
    scope: PatchExportScope.unstaged,
    format: PatchFormat.unifiedDiff,
    filename: 'repository.patch',
    bytes: 'diff\n'.codeUnits,
  );

  @override
  Future<PatchExportPreview> previewPatchSave(
    PatchExportContent content, {
    required String destinationDirectory,
    required bool overwrite,
  }) async => PatchExportPreview(
    token: BigInt.one,
    scope: content.scope,
    format: content.format,
    filename: content.filename,
    destination: '$destinationDirectory/${content.filename}',
    byteCount: content.bytes.length,
    requiresOverwrite: false,
  );

  @override
  Future<PatchExportExecutionResult> executePatchSave(BigInt token) async =>
      const PatchExportExecutionResult(
        state: PatchExportExecutionState.completed,
      );

  @override
  Future<PatchExportExecutionResult> executePatchExport(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedPatchExportToken = token;
    return const PatchExportExecutionResult(
      state: PatchExportExecutionState.completed,
      destination: '/chosen/repository.patch',
    );
  }

  @override
  Future<PatchApplyPreview> previewPatchApply(
    RepositorySessionIdentity identity,
    String patchPath,
  ) async {
    patchApplyPath = patchPath;
    return PatchApplyPreview(
      token: BigInt.from(82),
      paths: [List<int>.unmodifiable('tracked.txt'.codeUnits)],
      binary: false,
      arguments: const ['apply', '--recount', '<patch>'],
    );
  }

  @override
  Future<PatchApplyExecutionResult> executePatchApply(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedPatchApplyToken = token;
    return PatchApplyExecutionResult(state: PatchApplyExecutionState.completed);
  }

  @override
  Future<TransferPreview> previewTransfer(
    RepositorySessionIdentity identity,
    TransferRequest request,
  ) async {
    transferRequest = request;
    transferAfterRefMutation = executedRefMutationToken != null;
    final tag =
        request.kind == TransferKind.pushTag ||
        request.kind == TransferKind.deleteTag;
    return TransferPreview(
      token: BigInt.from(83),
      kind: request.kind,
      remote: request.remote ?? 'origin',
      branch: request.branch ?? 'main',
      arguments: request.kind == TransferKind.deleteTag
          ? [
              'push',
              '--progress',
              request.remote ?? 'origin',
              ':refs/tags/${request.branch}',
            ]
          : tag
          ? [
              'push',
              '--progress',
              request.remote ?? 'origin',
              'refs/tags/${request.branch}:refs/tags/${request.branch}',
            ]
          : const [
              'push',
              '--progress',
              '--force-with-lease=refs/heads/main:2222222222222222222222222222222222222222',
              'origin',
              'refs/heads/main:refs/heads/main',
            ],
      ahead: BigInt.one,
      behind: BigInt.zero,
      dirty: false,
      expectedRemoteObjectId: tag
          ? null
          : '2222222222222222222222222222222222222222',
      forceWithLease: !tag,
    );
  }

  @override
  Future<TransferExecutionResult> executeTransfer(
    RepositorySessionIdentity identity,
    BigInt token, {
    TransferCredentials? credentials,
  }) async {
    executedTransferToken = token;
    if (transferGate case final gate?) return gate.future;
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
  ) async => TransferExecutionResult(
    state: TransferExecutionState.completed,
    ahead: BigInt.zero,
    behind: BigInt.zero,
  );

  @override
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity identity,
    List<String> references,
  ) async => TransferExecutionResult(
    state: TransferExecutionState.completed,
    ahead: BigInt.zero,
    behind: BigInt.zero,
  );

  @override
  Future<bool> cancelTransfer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledTransferToken = token;
    return true;
  }

  @override
  Future<HostKeyChallenge> probeTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => HostKeyChallenge(
    challengeId: BigInt.one,
    host: 'example.test',
    port: 22,
    algorithm: 'ssh-ed25519',
    fingerprint: 'SHA256:test',
  );

  @override
  Future<void> resolveTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
    HostKeyChallenge challenge, {
    required bool accept,
  }) async {}

  @override
  Future<StashPreview> previewStash(
    RepositorySessionIdentity identity,
    StashRequest request,
  ) async {
    stashRequest = request;
    return StashPreview(
      token: BigInt.from(84),
      kind: request.kind,
      commands: const [
        ['stash', 'push', '--include-untracked', '-m', 'checkpoint'],
      ],
      affectedPaths: request.paths.isEmpty ? 2 : request.paths.length,
      includesUntracked: request.includeUntracked,
      keepsIndex: request.keepIndex,
      destructive: request.kind == StashKind.drop,
      selectedObjectId: request.objectId,
      targetBranch: request.targetBranch,
    );
  }

  @override
  Future<StashExecutionResult> executeStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedStashToken = token;
    return const StashExecutionResult(
      state: StashExecutionState.completed,
      activityIds: ['84'],
      stashCreated: true,
      checkoutCompleted: false,
      reapplyCompleted: false,
      stashRetained: false,
    );
  }

  @override
  Future<bool> cancelStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<HistoryMutationPreview> previewHistoryMutation(
    RepositorySessionIdentity identity,
    HistoryMutationRequest request,
  ) async {
    historyMutationRequest = request;
    return HistoryMutationPreview(
      token: BigInt.from(85),
      kind: request.kind,
      arguments: request.kind == HistoryMutationKind.merge
          ? ['merge', '--no-edit', '--ff', request.targets.first]
          : [
              request.kind == HistoryMutationKind.revert
                  ? 'revert'
                  : 'cherry-pick',
              if (request.kind == HistoryMutationKind.revert)
                request.noCommit ? '--no-commit' : '--no-edit',
              ...request.targets,
            ],
      targets: request.targets,
      sourceName: request.sourceName,
      currentBranch: 'main'.codeUnits,
      currentHead: '0' * 40,
      publishedHistory: false,
      alreadyContained: false,
      noCommit: request.noCommit,
    );
  }

  @override
  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedHistoryMutationToken = token;
    if (historyMutationGate case final gate?) return gate.future;
    return const HistoryMutationExecutionResult(
      state: HistoryMutationExecutionState.completed,
      activityIds: ['85'],
      conflictingPaths: [],
    );
  }

  @override
  Future<bool> cancelHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    historyMutationCancels++;
    return true;
  }

  @override
  Future<BigInt> beginConflictPrediction(
    RepositorySessionIdentity identity,
  ) async => BigInt.from(86);

  @override
  Future<ConflictPredictionResult> executeConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
    ConflictPredictionKind kind,
    String target,
  ) async => ConflictPredictionResult(
    kind: kind,
    target: target,
    conflictingPaths: const [],
    analyzedCommits: 1,
    totalCommits: 1,
    complete: true,
    activityIds: const ['86'],
  );

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
  ) async => RebasePlan(
    token: BigInt.from(87),
    onto: onto,
    ontoName: ontoName,
    currentBranch: 'topic'.codeUnits,
    currentHead: '2' * 40,
    instructions: [
      RebaseInstruction(
        id: BigInt.one,
        action: RebaseAction.pick,
        oid: '2' * 40,
        subject: 'topic commit'.codeUnits,
        published: false,
      ),
      RebaseInstruction(
        id: BigInt.two,
        action: RebaseAction.pick,
        oid: '3' * 40,
        subject: 'second topic commit'.codeUnits,
        published: false,
      ),
    ],
    publishedCount: 0,
    activityIds: const ['87'],
  );

  @override
  Future<RebasePreview> previewRebase(
    RepositorySessionIdentity identity,
    BigInt token,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) async {
    rebaseInstructions = instructions;
    return RebasePreview(
      token: token,
      arguments: const [
        '-c',
        'rebase.autoStash=false',
        'rebase',
        '--interactive',
        '1111111111111111111111111111111111111111',
      ],
      todo: 'pick 33333333 second topic commit\nreword 22222222 topic commit\n'
          .codeUnits,
      instructionCount: instructions.length,
      publishedCount: 0,
      instructions: instructions,
      autosquashApplied: 0,
    );
  }

  @override
  Future<RebaseExecutionResult> executeRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedRebaseToken = token;
    return const RebaseExecutionResult(
      state: RebaseExecutionState.completed,
      activityIds: ['87'],
      conflictingPaths: [],
    );
  }

  @override
  Future<bool> cancelRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<ConflictSnapshot> loadConflicts(
    RepositorySessionIdentity identity,
  ) async {
    if (conflictSnapshot != null) return conflictSnapshot!;
    final status = snapshot?.status;
    if (status == null ||
        (status.workingTree != WorkingTreeState.conflicted &&
            status.operations.isEmpty &&
            !status.entries.any((entry) => entry.conflicted))) {
      throw const ConflictException(ConflictFailureCode.noActiveOperation);
    }
    return _welcomeConflict;
  }

  @override
  Future<ConflictSnapshot> saveConflictResult(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    List<int> result,
  ) async {
    conflictSavedResult = result;
    conflictSnapshot = _resolvedWelcomeConflict;
    return conflictSnapshot!;
  }

  @override
  Future<ConflictSnapshot> chooseConflictSide(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    ConflictSideChoice choice,
  ) async {
    conflictSideChoices.add('${utf8.decode(path)}:${choice.name}');
    final current = conflictSnapshot;
    if (resolveChosenSides && current != null) {
      final files = [
        for (final file in current.files)
          if (!listEquals(file.path, path)) file,
      ];
      conflictSnapshot = ConflictSnapshot(
        operation: current.operation,
        suggestedMessage: current.suggestedMessage,
        currentLabel: current.currentLabel,
        incomingLabel: current.incomingLabel,
        files: files,
        resolvedUndoPaths: [...current.resolvedUndoPaths, path],
        canContinue: files.isEmpty,
        canSkip: false,
      );
    }
    return conflictSnapshot ?? _welcomeConflict;
  }

  @override
  Future<ConflictSnapshot> takeConflictRegion(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    int regionIndex,
    ConflictRegionChoice choice,
  ) async {
    conflictRegionChoice = choice;
    conflictSnapshot = _resolvedWelcomeConflict;
    return conflictSnapshot!;
  }

  @override
  Future<ConflictSnapshot> undoConflictResolution(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    conflictUndos.add(utf8.decode(path));
    return conflictSnapshot ?? _welcomeConflict;
  }

  @override
  Future<ConflictContinuationResult> continueConflictOperation(
    RepositorySessionIdentity identity,
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) async {
    conflictSequencerAction = action;
    conflictMergeMessage = mergeMessage;
    return const ConflictContinuationResult(
      state: ConflictContinuationState.completed,
      activityIds: ['88'],
    );
  }

  NamedSnapshot get _namedSnapshot => NamedSnapshot(
    id: BigInt.one,
    name: 'before refactor',
    createdAtUnixMs: BigInt.one,
    baseRef: 'main'.codeUnits,
    baseOid: '1' * 40,
    objectId: '2' * 40,
    stagedCount: 1,
    unstagedCount: 1,
    untrackedCount: 1,
    includesUntracked: true,
    keepsIndex: false,
    state: NamedSnapshotState.ready,
  );

  @override
  Future<NamedSnapshotPage> namedSnapshots(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximum = 32,
  }) async => NamedSnapshotPage(
    entries: List.unmodifiable(namedSnapshotEntries),
    total: namedSnapshotEntries.length,
  );

  @override
  Future<NamedSnapshotExecutionResult> createNamedSnapshot(
    RepositorySessionIdentity identity, {
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) async {
    namedSnapshotEntries
      ..clear()
      ..add(_namedSnapshot);
    return NamedSnapshotExecutionResult(
      state: NamedSnapshotExecutionState.completed,
      snapshot: _namedSnapshot,
      conflictingPaths: const [],
      activityIds: const ['89'],
    );
  }

  @override
  Future<NamedSnapshotRestorePreview> previewNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) async => NamedSnapshotRestorePreview(
    token: BigInt.from(89),
    snapshot: _namedSnapshot,
    replacementPaths: ['tracked.txt'.codeUnits],
    replacementPathsTruncated: false,
    replacesIndex: true,
    replacesWorktree: true,
  );

  @override
  Future<NamedSnapshotExecutionResult> executeNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    namedSnapshotRestoreExecuted = true;
    return const NamedSnapshotExecutionResult(
      state: NamedSnapshotExecutionState.completed,
      conflictingPaths: [],
      activityIds: ['89'],
    );
  }

  @override
  Future<bool> cancelNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<NamedSnapshotExecutionResult> branchFromNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
    List<int> branch,
  ) => createNamedSnapshot(
    identity,
    name: 'branch',
    includeUntracked: false,
    keepIndex: false,
  );

  @override
  Future<NamedSnapshotExecutionResult> deleteNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) async {
    namedSnapshotEntries.clear();
    return const NamedSnapshotExecutionResult(
      state: NamedSnapshotExecutionState.completed,
      conflictingPaths: [],
      activityIds: ['89'],
    );
  }

  @override
  Future<RepositoryExtensionInventory> repositoryExtensions(
    RepositorySessionIdentity identity,
  ) async {
    extensionReads += 1;
    if (extensionBarriers.isNotEmpty) {
      return extensionBarriers.removeAt(0).future;
    }
    return RepositoryExtensionInventory(
      worktrees:
          worktreeEntries ??
          [
            WorktreeEntry(
              worktreeRoot: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository'.codeUnits,
              ),
              gitDir: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository/.git'.codeUnits,
              ),
              commonGitDir: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: '/repository/.git'.codeUnits,
              ),
              head: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              locked: false,
              prunable: false,
              current: true,
            ),
          ],
      submodules: const [],
      lfsAvailable: lfsAvailable,
      lfsUnavailableReason: !lfsAvailable,
      lfsEntries: const [],
      activityIds: const [],
    );
  }

  @override
  Future<NativePathIdentity> enterSubmodule(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async => NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: '/repository/submodule'.codeUnits,
  );

  @override
  Future<LfsPointer?> inspectLfsPointer(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async => null;

  @override
  String? exactIgnorePattern(List<int> path, {required bool directory}) =>
      '/${String.fromCharCodes(path)}${directory ? '/' : ''}';

  @override
  Future<RepositoryExtensionMutationResult> executeRepositoryExtension(
    RepositorySessionIdentity identity,
    RepositoryExtensionMutationRequest request,
  ) async {
    extensionRequest = request;
    return extensionResult;
  }

  @override
  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) async => integrationCandidates
      .where((candidate) => candidate.kind == kind)
      .toList(growable: false);

  @override
  Future<IntegrationPreview> previewIntegration(
    RepositorySessionIdentity identity,
    IntegrationRequest request,
  ) async {
    integrationRequest = request;
    return IntegrationPreview(
      token: BigInt.from(33),
      kind: request.kind,
      definitionId: request.configured?.id ?? request.discoveredId ?? 'tool',
      executable: '/tool',
      arguments: const [],
      explicitShell: false,
      waitsForExit: true,
      requiresConfirmation: integrationRequiresConfirmation,
    );
  }

  @override
  Future<IntegrationPreview> previewExternalConflictMerge(
    RepositorySessionIdentity identity,
    ConflictFile file,
    IntegrationDefinition definition,
  ) => previewIntegration(
    identity,
    IntegrationRequest(kind: IntegrationKind.mergeTool, configured: definition),
  );

  @override
  Future<IntegrationPreview> previewExternalCommitDiff(
    RepositorySessionIdentity identity, {
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  }) => previewIntegration(
    identity,
    IntegrationRequest(kind: IntegrationKind.diffTool, configured: definition),
  );

  @override
  Future<IntegrationExecutionResult> executeIntegration(
    RepositorySessionIdentity identity,
    BigInt token, {
    required bool confirmed,
  }) async {
    integrationExecuted = true;
    return const IntegrationExecutionResult(
      state: IntegrationExecutionState.completed,
    );
  }

  @override
  Future<bool> cancelIntegration(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<BigInt> startDiffContentSearch(
    RepositorySessionIdentity identity, {
    required String query,
    required int maximumCommits,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
    bool otherRefs = false,
  }) async {
    powerSearchCaseSensitive = caseSensitive;
    powerSearchScope = scope;
    return BigInt.from(201);
  }

  @override
  Future<DiffContentSearchResult> pollDiffContentSearch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const DiffContentSearchResult(
    state: PowerJobState.completed,
    matches: [DiffContentMatch(commit: 'abc123', summary: 'match')],
    examinedCommits: 1,
    completeness: SearchCompleteness.complete,
    activityIds: [],
  );

  @override
  Future<BigInt> startRepositoryStatistics(
    RepositorySessionIdentity identity,
  ) async => BigInt.from(202);

  @override
  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const RepositoryStatisticsResult(
    state: PowerJobState.completed,
    commitCount: 6,
    localBranchCount: 2,
    tagCount: 1,
    changedPathCount: 3,
    incomplete: false,
    activityIds: [],
  );

  @override
  Future<bool> cancelPowerJob(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<BisectState> bisectState(RepositorySessionIdentity identity) async =>
      const BisectState(active: false, timeline: []);

  @override
  Future<BisectPreview> previewBisect(
    RepositorySessionIdentity identity,
    BisectAction action, {
    String? good,
    String? bad,
  }) async => BisectPreview(
    token: BigInt.from(203),
    action: action,
    arguments: const ['bisect', 'start'],
  );

  @override
  Future<BisectExecutionResult> executeBisect(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const BisectExecutionResult(
    state: BisectExecutionState.completed,
    bisect: BisectState(active: true, timeline: []),
  );

  @override
  Future<bool> cancelBisectPreview(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<bool> close(RepositorySessionIdentity identity) async => true;

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
  Future<void> refresh(RepositorySessionIdentity identity) async {
    refreshCount += 1;
    if (failRefresh) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.read),
      );
    }
  }
}

/// A repository paused on one conflicted file, `conflict.txt`.
RepositorySnapshot _conflictedSnapshot() {
  final path = NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: '/repository'.codeUnits,
  );
  return RepositorySnapshot(
    revision: BigInt.one,
    phase: RepositoryPhase.ready,
    identity: RepositoryIdentity(
      commonGitDir: path,
      worktreeRoot: path,
      gitDir: path,
      kind: RepositoryKind.worktree,
      headKind: HeadKind.attached,
      gitMajor: 2,
      gitMinor: 50,
      gitPatch: 1,
    ),
    status: RepositoryStatus(
      workingTree: WorkingTreeState.conflicted,
      branchName: 'main'.codeUnits,
      ahead: BigInt.zero,
      behind: BigInt.zero,
      entries: [
        RepositoryStatusEntry(
          kind: StatusEntryKind.unmerged,
          path: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: 'conflict.txt'.codeUnits,
          ),
          index: ChangeKind.updatedButUnmerged,
          worktree: ChangeKind.updatedButUnmerged,
        ),
      ],
      totalEntries: BigInt.one,
      entriesTruncated: false,
      operations: const [],
    ),
  );
}

/// Colours the first word of every line as a keyword, at once.
final class _FirstWordSyntax implements SourceSyntaxRepository {
  final paths = <String>[];

  @override
  Future<SourceSyntaxPage> sourceSyntaxPage({
    required BigInt viewId,
    required BigInt syntaxRequestId,
    required List<int> path,
    required Uint8List source,
    required int firstLine,
    required int maximumLines,
  }) async {
    paths.add(utf8.decode(path));
    final text = utf8.decode(source);
    final lines = text.split('\n');
    if (text.endsWith('\n')) lines.removeLast();
    return SourceSyntaxPage(
      viewId: viewId,
      syntaxRequestId: syntaxRequestId,
      firstLine: firstLine,
      state: DiffSyntaxSideState.ready,
      lines: [
        for (final line in lines.skip(firstLine - 1).take(maximumLines))
          SourceSyntaxLine(
            state: DiffSyntaxSideState.ready,
            runs: [
              if (line.split(' ').first.isNotEmpty)
                DiffSyntaxRun(
                  0,
                  line.split(' ').first.length,
                  DiffSyntaxKind.keyword,
                ),
            ],
          ),
      ],
    );
  }

  @override
  Future<bool> cancelSourceSyntax({
    required BigInt viewId,
    required BigInt syntaxRequestId,
  }) async => true;
}

final _welcomeConflict = ConflictSnapshot(
  operation: ConflictOperationKind.merge,
  suggestedMessage: 'Merge topic\n\nReview the changes',
  currentLabel: 'main'.codeUnits,
  incomingLabel: 'topic'.codeUnits,
  files: [
    ConflictFile(
      path: 'conflict.txt'.codeUnits,
      kind: ConflictFileKind.text,
      ancestor: ConflictSide(
        present: true,
        content: 'base\n'.codeUnits,
        byteCount: 5,
      ),
      current: ConflictSide(
        present: true,
        content: 'current\n'.codeUnits,
        byteCount: 8,
      ),
      incoming: ConflictSide(
        present: true,
        content: 'incoming\n'.codeUnits,
        byteCount: 9,
      ),
      result:
          '<<<<<<< HEAD\ncurrent\n=======\nincoming\n>>>>>>> topic\n'.codeUnits,
      resultPresent: true,
      markerFree: false,
      regions: [
        ConflictRegion(
          index: 0,
          current: 'current\n'.codeUnits,
          incoming: 'incoming\n'.codeUnits,
          ancestor: 'base\n'.codeUnits,
        ),
      ],
      fingerprint: BigInt.one,
      canUndoResolution: false,
    ),
  ],
  resolvedUndoPaths: const [],
  canContinue: false,
  canSkip: false,
);

final _resolvedWelcomeConflict = ConflictSnapshot(
  operation: ConflictOperationKind.merge,
  suggestedMessage: 'Merge topic\n\nReview the changes',
  currentLabel: 'main'.codeUnits,
  incomingLabel: 'topic'.codeUnits,
  files: const [],
  resolvedUndoPaths: ['conflict.txt'.codeUnits],
  canContinue: true,
  canSkip: false,
);

final _emptyWelcomeDiff = DiffPage(
  requestId: BigInt.zero,
  layout: DiffViewLayout.unified,
  totalRows: 0,
  offset: 0,
  rows: const [],
  payloadBytes: 0,
);

final class _OperationRepository implements OperationCenterRepository {
  _OperationRepository(this.current);

  OperationCenterSnapshot current;
  BigInt? dismissedActivity;

  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async =>
      current;

  @override
  Future<void> dismiss(OperationCenterEntry entry) async {
    dismissedActivity = entry.activityId;
  }

  @override
  Future<void> dismissAll() async {}
}

/// The line number gutter of diff row [id]; a click there selects the line.
Offset _diffGutter(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('diff-row-$id'))) +
    const Offset(
      GitLamaLayout.diffGutterWidth / 2,
      GitLamaLayout.diffLineHeight / 2,
    );

Future<void> _openSidebarTags(WidgetTester tester) async {
  await tester.ensureVisible(find.text('TAGS'));
  await tester.tap(find.text('TAGS'));
  await tester.pumpAndSettle();
}

Future<void> _expandSidebarGroup(WidgetTester tester, String key) async {
  tester.widget<Focus>(find.byKey(ValueKey(key))).focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pumpAndSettle();
}

const _filterMain = '1111111111111111111111111111111111111111';
const _filterTopic = '2222222222222222222222222222222222222222';
const _filterFeature = '3333333333333333333333333333333333333333';
const _filterBase = '4444444444444444444444444444444444444444';

final _branchFilterRows = [
  HistoryTopologyRow(
    objectId: _filterMain,
    parents: const [_filterBase],
    refs: ['refs/heads/main'.codeUnits],
    lane: 0,
    shape: 0,
  ),
  HistoryTopologyRow(
    objectId: _filterTopic,
    parents: const [_filterBase],
    refs: ['refs/heads/topic'.codeUnits],
    lane: 1,
    shape: 0,
  ),
  HistoryTopologyRow(
    objectId: _filterFeature,
    parents: const [_filterBase],
    refs: ['refs/remotes/origin/feature'.codeUnits],
    lane: 2,
    shape: 0,
  ),
  const HistoryTopologyRow(
    objectId: _filterBase,
    parents: [],
    refs: [],
    lane: 0,
    shape: 0,
  ),
];

RepositorySnapshot _branchFilterSnapshot() => RepositorySnapshot(
  revision: BigInt.one,
  phase: RepositoryPhase.ready,
  refs: RepositoryRefs(
    branches: [
      RepositoryReference(
        name: 'main'.codeUnits,
        target: _filterMain,
        head: true,
      ),
      RepositoryReference(name: 'topic'.codeUnits, target: _filterTopic),
    ],
    remotes: [
      RepositoryRemote(
        name: 'origin'.codeUnits,
        displayUrl: const [],
        branches: [
          RepositoryReference(
            name: 'feature'.codeUnits,
            target: _filterFeature,
          ),
        ],
      ),
    ],
  ),
);

final class _InspectionWindows implements InspectionWindowRepository {
  final List<InspectionWindowRequest> opened = [];

  @override
  Future<void> open(InspectionWindowRequest request) async =>
      opened.add(request);
}

final class _InspectorReveal implements InspectorRevealRepository {
  Future<bool> Function(InspectorRevealRequest)? handler;

  @override
  Future<void> listen(
    Future<bool> Function(InspectorRevealRequest) onReveal,
  ) async => handler = onReveal;

  @override
  Future<bool> reveal(InspectorRevealRequest request) async => false;

  @override
  Future<void> dispose() async {}
}

/// [runtime] with inspector windows and the reveal channel faked.
Future<AppRuntime> _withInspection(
  AppRuntime runtime, {
  required _InspectionWindows windows,
  _InspectorReveal? reveal,
}) async => AppRuntime(
  repositorySessions: runtime.repositorySessions,
  remoteWorkspaces: runtime.remoteWorkspaces,
  inspectionWindows: InspectionWindowService(windows),
  inspectorReveal: InspectorRevealService(reveal ?? _InspectorReveal()),
  settings: runtime.settings,
  avatars: runtime.avatars,
  repositoryAppearances: runtime.repositoryAppearances,
  recovery: runtime.recovery,
  operationCenter: runtime.operationCenter,
  repositoryDrops: runtime.repositoryDrops,
  hosting: runtime.hosting,
  hostingReview: runtime.hostingReview,
  cliForwarding: runtime.cliForwarding,
  updates: runtime.updates,
  shutdown: runtime.shutdown,
);

/// Pane header actions can share a label with selection-aware row actions.
Finder _sectionAction(String label) => find.descendant(
  of: find.byType(MeridianSectionHeader),
  matching: find.byWidgetPredicate(
    (widget) => widget is MeridianIconButton && widget.label == label,
  ),
);

/// The merge result's block marks under its text.
final _conflictResultMarks = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_ResultMarks',
);
