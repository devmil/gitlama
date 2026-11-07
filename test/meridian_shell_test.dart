import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/meridian_finders.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace_shell.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';
import 'package:gitlama/widgets/gitlama_repo_tabs.dart';
import 'package:gitlama/widgets/status_notification.dart';

import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/widgets/gitlama_git_glyphs.dart';
import 'support/inert_runtime.dart';
import 'support/fake_recovery_repository.dart';

void main() {
  if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
    setUpAll(() async {
      final mono = FontLoader('packages/meridian_ui/JetBrains Mono')
        ..addFont(
          rootBundle.load(
            'packages/meridian_ui/assets/fonts/JetBrainsMono-Regular.ttf',
          ),
        );
      await mono.load();
      const fontPath = String.fromEnvironment('UI_REVIEW_FONT');
      if (fontPath.isNotEmpty) {
        final body = FontLoader('Roboto')
          ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        await body.load();
      }
    });
  }
  for (final brightness in Brightness.values) {
    for (final density in gitlamaDensities) {
      testWidgets(
        'Meridian sidebar geometry and refs ${brightness.name} ${density.name}',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final settings = fakeSettingsService();
          await settings.initialize();
          final repositories = fakeRepositorySessionService(
            snapshot: RepositorySnapshot(
              revision: BigInt.one,
              phase: RepositoryPhase.ready,
              refCounts: const RepositoryRefCounts(branches: 2),
              refs: RepositoryRefs(
                branches: [
                  RepositoryReference(
                    name: 'main'.codeUnits,
                    target: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                    head: true,
                  ),
                  RepositoryReference(
                    name: 'feature'.codeUnits,
                    target: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                    upstream: 'origin/feature'.codeUnits,
                    ahead: 2,
                    behind: 1,
                  ),
                ],
              ),
            ),
          );
          final operations = OperationCenterService.empty();
          await repositories.open('/repository');
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) =>
                  StatusNotificationScope(child: child!),
              theme: buildAppTheme(brightness, density: density),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: WorkspaceShell(
                runtime: testRuntime(
                  repositorySessions: repositories,
                  settings: settings,
                  recovery: fakeRecoveryService(settings),
                  operationCenter: operations,
                  shutdown: () async {},
                ),
                workspace: repositories.workspace,
                onOpenRepository: () {},
                onCloneRepository: () {},
                onInitializeRepository: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final header = find.text('BRANCHES');
          final headerBox = find
              .ancestor(of: header, matching: find.byType(SizedBox))
              .first;
          expect(
            tester.getSize(headerBox).height,
            MeridianLayout.navSectionHeight,
          );
          final headerStyle = tester.widget<Text>(header).style!;
          expect(headerStyle.fontSize, gitlamaText.overline.fontSize);
          final main = find.byKey(const Key('sidebar-ref-main'));
          final feature = find.byKey(const Key('sidebar-ref-feature'));
          expect(tester.getSize(main).height, density.rowExtent);
          expect(tester.getSize(feature).height, density.rowExtent);
          final mainText = tester.widget<Text>(
            find.descendant(of: main, matching: find.text('main')),
          );
          expect(mainText.style!.fontWeight, gitlamaText.bodyStrong.fontWeight);
          final badge = find.descendant(
            of: feature,
            matching: find.byType(GitLamaSyncBadge),
          );
          expect(badge, findsOneWidget);
          final sync = tester.widget<GitLamaSyncBadge>(badge);
          expect((sync.ahead, sync.behind), (2, 1));
          final colors = brightness == Brightness.light
              ? gitlamaColors(Brightness.light)
              : gitlamaColors(Brightness.dark);
          expect(
            tester
                .widget<Text>(
                  find.descendant(of: badge, matching: find.text('2')),
                )
                .style!
                .color,
            colors.accentInk,
          );
          expect(
            tester
                .widget<Text>(
                  find.descendant(of: badge, matching: find.text('1')),
                )
                .style!
                .color,
            colors.warning,
          );
          if (const bool.fromEnvironment('CAPTURE_UI_REVIEW') &&
              density == MeridianDensity.regular) {
            await expectLater(
              find.byType(Scaffold).first,
              matchesGoldenFile(
                '../build/evidence/meridian/M09-sidebar-${brightness.name}.png',
              ),
            );
          }
          await tester.tap(
            find.descendant(of: feature, matching: find.text('feature')),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          tester.widget<Focus>(feature).focusNode!.requestFocus();
          await tester.pump();
          final selectedRow = tester.widget<MeridianListRow>(
            find.descendant(
              of: feature,
              matching: find.byType(MeridianListRow),
            ),
          );
          expect(selectedRow.selected, isTrue);
          expect(
            MeridianSurfaceScope.maybeOf(tester.element(feature))!.focused,
            isTrue,
          );
          // GitLama's soft selection keeps the badge's normal inks
          // with island focus.
          expect(tester.widget<GitLamaSyncBadge>(badge).onAccent, isFalse);
          final refRow = find.descendant(
            of: feature,
            matching: find.byType(MeridianListRow),
          );
          // The selection fill stays `accent-soft` with island focus.
          await tester.pump(MeridianDurations.select);
          final refFill = tester.widget<AnimatedContainer>(
            find
                .descendant(
                  of: refRow,
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          );
          expect(
            (refFill.decoration! as BoxDecoration).color,
            colors.accentSoft,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await repositories.dispose();
          await operations.dispose();
          await settings.dispose();
        },
      );
    }
  }

  testWidgets('Meridian window shell keeps its frame and gutter geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = fakeSettingsService();
    await settings.initialize();
    final repositories = fakeRepositorySessionService(
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
    );
    final operations = OperationCenterService.empty();
    await repositories.open('/repository');
    Widget shell() => MaterialApp(
      builder: (context, child) => StatusNotificationScope(child: child!),
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkspaceShell(
        runtime: testRuntime(
          repositorySessions: repositories,
          settings: settings,
          recovery: fakeRecoveryService(settings),
          operationCenter: operations,
          shutdown: () async {},
        ),
        workspace: repositories.workspace,
        onOpenRepository: () {},
        onCloneRepository: () {},
        onInitializeRepository: () {},
      ),
    );

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(GitLamaCompass)).height,
      GitLamaLayout.compassHeight,
    );
    expect(
      tester.getSize(find.byKey(const Key('toolbar-row'))).height,
      MeridianSize.toolbar,
    );
    expect(
      tester.getSize(find.byType(GitLamaRepoTabs)).height,
      MeridianLayout.tabStripHeight,
    );
    final sidebar = tester.getRect(
      find.byKey(const Key('sidebar-pane-splitter')),
    );
    expect(sidebar.width, MeridianSpace.space3);
    final islands = find.byType(MeridianIsland);
    expect(islands, findsWidgets);
    final firstIsland = tester.widget<DecoratedBox>(
      find
          .descendant(of: islands.first, matching: find.byType(DecoratedBox))
          .first,
    );
    final decoration = firstIsland.decoration as BoxDecoration;
    expect(decoration.color, gitlamaColors(Brightness.light).pane);
    expect(decoration.borderRadius, BorderRadius.circular(gitlamaRadius.lg));
    await tester.tap(find.text('History').first);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(
      repositories.workspace.activeTab?.navigation.pane,
      WorkspacePane.history,
    );
    final historyIsland = tester.getRect(find.byType(MeridianIsland).first);
    expect(historyIsland.left - sidebar.left, MeridianSpace.space3);
    expect(find.byType(MeridianIsland), findsNWidgets(2));
    expect(find.byKey(const Key('detail-pane')), findsOneWidget);

    tester.view.physicalSize = const Size(900, 600);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('sidebar-rail'))).width,
      MeridianLayout.sidebarRailWidth,
    );
    expect(find.byTooltip('Changes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await repositories.dispose();
    await operations.dispose();
    await settings.dispose();
  });
}
