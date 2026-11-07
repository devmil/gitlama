import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace_shell.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/widgets/status_notification.dart';

import 'support/fake_recovery_repository.dart';
import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';
import 'support/inert_runtime.dart';

RepositoryReference _branch(String name, {bool head = false}) =>
    RepositoryReference(name: name.codeUnits, target: 'a' * 40, head: head);

void main() {
  Future<Future<void> Function()> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = fakeSettingsService();
    await settings.initialize();
    final repositories = fakeRepositorySessionService(
      snapshot: RepositorySnapshot(
        revision: BigInt.one,
        phase: RepositoryPhase.ready,
        refCounts: const RepositoryRefCounts(branches: 4, remotes: 1, tags: 1),
        refs: RepositoryRefs(
          branches: [
            _branch('main', head: true),
            _branch('feature/one'),
            _branch('feature/two'),
            _branch('fix'),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: const [],
              branches: [_branch('main'), _branch('feature/one')],
            ),
          ],
          tags: [_branch('v1-one')],
        ),
      ),
    );
    final operations = OperationCenterService.empty();
    await repositories.open('/repository');
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    return () async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repositories.dispose();
      await operations.dispose();
      await settings.dispose();
    };
  }

  final field = find.byKey(const ValueKey('sidebar-filter'));
  Finder row(String key) => find.byKey(ValueKey('sidebar-ref-$key'));
  EditableText editable(WidgetTester tester) => tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );

  testWidgets('the filter appears on request, reveals matches without '
      'changing saved expansion, and Escape clears it', (tester) async {
    final dispose = await pumpShell(tester);
    expect(field, findsNothing);
    expect(row('main'), findsOneWidget);
    // The feature group starts closed and the tags section too.
    expect(row('1-feature/one'), findsNothing);
    expect(row('v1-one'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sidebar-filter-show')));
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    expect(editable(tester).focusNode.hasFocus, isTrue);

    await tester.enterText(field, 'ONE');
    await tester.pumpAndSettle();
    expect(row('main'), findsNothing);
    expect(row('fix'), findsNothing);
    expect(row('feature/'), findsOneWidget);
    expect(row('1-feature/one'), findsOneWidget);
    expect(row('1-feature/two'), findsNothing);
    // The remote branch `origin/feature/one` and the tag match too.
    expect(row('origin'), findsOneWidget);
    expect(row('2-feature/one'), findsOneWidget);
    expect(row('v1-one'), findsOneWidget);

    // The remote's own name matches its branches.
    await tester.enterText(field, 'origin/');
    await tester.pumpAndSettle();
    expect(row('1-main'), findsOneWidget);
    expect(row('main'), findsNothing);

    await tester.enterText(field, 'nothing');
    await tester.pumpAndSettle();
    expect(find.text('No matching branches or tags.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(row('main'), findsOneWidget);
    expect(row('fix'), findsOneWidget);
    expect(row('1-feature/one'), findsNothing);
    expect(row('v1-one'), findsNothing);
    await dispose();
  });

  testWidgets('typing in the sidebar starts filtering and the clear button '
      'ends it', (tester) async {
    final dispose = await pumpShell(tester);
    tester.widget<Focus>(row('fix')).focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    expect(editable(tester).controller.text, 'f');
    expect(editable(tester).focusNode.hasFocus, isTrue);
    expect(row('fix'), findsOneWidget);
    expect(row('main'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sidebar-filter-clear')));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(row('main'), findsOneWidget);

    // Modified keys stay shortcuts.
    tester.widget<Focus>(row('main')).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    await dispose();
  });
}
