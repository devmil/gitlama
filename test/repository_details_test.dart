import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/app/workspace/repository_details.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'motion/motion_support.dart';

NativePathIdentity _path(String value, {RemoteAuthority? remote}) =>
    NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: value.codeUnits,
      remote: remote,
    );

const _authority = RemoteAuthority(
  profileId: '00000000-0000-4000-8000-000000000001',
  storeId: '0123456789abcdef0123456789abcdef',
  accountUid: '1000',
);

void main() {
  late ValueNotifier<int> changes;
  late List<NativePathIdentity> copied;
  late List<NativePathIdentity> opened;
  RepositoryDetails? details;

  setUp(() {
    changes = ValueNotifier(0);
    copied = [];
    opened = [];
  });
  tearDown(() => changes.dispose());

  Future<void> open(
    WidgetTester tester, {
    Rect? anchor = const Rect.fromLTWH(400, 6, 400, 32),
    bool reduced = false,
  }) async {
    await tester.pumpWidget(
      motionHost(
        Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'open',
              onPressed: () => showRepositoryDetails(
                context: context,
                anchor: anchor,
                builder: (context) => RepositoryDetailsPanel(
                  read: () => details,
                  changes: changes,
                  fileBrowserName: 'Files',
                  onCopyPath: copied.add,
                  onOpenFolder: opened.add,
                ),
              ),
            ),
          ),
        ),
        reduced: reduced,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('a local repository grows from the Compass and stays live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    details = RepositoryDetails(
      name: 'gitlama',
      group: 'Work',
      path: _path('/home/me/gitlama'),
      kind: RepositoryKind.worktree,
      headKind: HeadKind.attached,
      branch: 'main'.codeUnits,
      upstream: 'origin/main'.codeUnits,
      ahead: 2,
      behind: 1,
      changed: 3,
      conflicts: 1,
      inProgress: const [RepositoryOperationKind.rebase],
      gitVersion: '2.50.1',
    );
    await open(tester);
    // Half way the surface is between the Compass and its full size.
    await tester.pump(GitLamaMotion.paletteMorph ~/ 3);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find.byKey(const ValueKey('repository-details')),
    );
    expect(panel.top, greaterThanOrEqualTo(6));
    expect(panel.center.dx, closeTo(600, 1));
    for (final text in [
      'gitlama',
      'This computer',
      'Work',
      'Repository with working tree',
      'main',
      'origin/main',
      '3 changed files',
      '1 conflict',
      'Rebase in progress',
      'Nothing running',
      '2.50.1',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }

    // Work that starts while the overlay is open shows up in place.
    details = RepositoryDetails(
      name: 'gitlama',
      path: _path('/home/me/gitlama'),
      kind: RepositoryKind.worktree,
      branch: 'main'.codeUnits,
      operation: OperationCenterEntry(
        state: OperationCenterState.running,
        origin: OperationCenterOrigin.user,
        action: OperationCenterAction.fetch,
        startedAtUnixMs: BigInt.zero,
        canCancel: true,
        canRetry: false,
        hasDetails: false,
        progress: ActivityProgress(
          phase: 'Receiving objects',
          completed: BigInt.one,
          total: BigInt.two,
          unit: 'objects',
        ),
      ),
      gitVersion: '2.50.1',
    );
    changes.value++;
    await tester.pump();
    expect(find.text('Nothing running'), findsNothing);
    expect(find.byType(MeridianProgressBar), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('repository-details-copy-path')),
    );
    await tester.pump();
    expect(copied, [_path('/home/me/gitlama')]);
    await tester.tap(
      find.byKey(const ValueKey('repository-details-open-folder')),
    );
    await tester.pumpAndSettle();
    // Opening the folder closes the overlay first.
    expect(opened, [_path('/home/me/gitlama')]);
    expect(find.byKey(const ValueKey('repository-details')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a remote bare repository names its host and copies its path', (
    tester,
  ) async {
    details = RepositoryDetails(
      name: 'mirror',
      remote: true,
      host: 'Build server',
      hostAlias: 'build',
      hostDisconnected: true,
      path: _path('/srv/git/mirror.git', remote: _authority),
      kind: RepositoryKind.bare,
      headKind: HeadKind.attached,
      branch: 'main'.codeUnits,
      gitVersion: '2.43.0',
    );
    await open(tester, reduced: true);
    await tester.pumpAndSettle();
    expect(find.text('Build server (build) · disconnected'), findsOneWidget);
    expect(find.text('Bare repository'), findsOneWidget);
    // A bare repository has no working tree to change or track.
    expect(find.text('Changes'), findsNothing);
    expect(find.text('Upstream'), findsNothing);
    // There is no local folder to open.
    expect(
      find.byKey(const ValueKey('repository-details-open-folder')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('repository-details-copy-path')),
    );
    expect(copied.single.remote, _authority);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository-details')), findsNothing);
  });

  testWidgets('the overlay closes when its repository goes away', (
    tester,
  ) async {
    details = RepositoryDetails(name: 'gone', path: _path('/gone'));
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository-details')), findsOneWidget);
    details = null;
    changes.value++;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository-details')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window with large German text does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    details = RepositoryDetails(
      name: 'ein-sehr-langer-repository-name-der-umbricht',
      remote: true,
      host: 'Entwicklungsrechner im Keller',
      hostAlias: 'keller',
      path: _path('/home/jemand/projekte/ein/sehr/tiefer/pfad/zum/repository'),
      kind: RepositoryKind.worktree,
      branch: 'feature/eine-sehr-lange-branch-bezeichnung'.codeUnits,
      changed: 1200,
      gitVersion: '2.50.1',
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          locale: const Locale('de'),
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MeridianGround(
            child: MeridianMotionScope(
              child: Builder(
                builder: (context) => Center(
                  child: MeridianButton(
                    label: 'open',
                    onPressed: () => showRepositoryDetails(
                      context: context,
                      anchor: const Rect.fromLTWH(60, 6, 300, 32),
                      builder: (context) => RepositoryDetailsPanel(
                        read: () => details,
                        changes: changes,
                        fileBrowserName: 'Dateien',
                        onCopyPath: copied.add,
                        onOpenFolder: opened.add,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('repository-details-copy-path')),
      findsOneWidget,
    );
    // Too narrow for side-by-side tiles: branch, upstream and changes stack.
    final changesTile = tester.getRect(
      find.byKey(const ValueKey('repository-details-changes')),
    );
    expect(
      changesTile.top,
      greaterThan(
        tester
            .getRect(find.text('feature/eine-sehr-lange-branch-bezeichnung'))
            .bottom,
      ),
    );
    final panel = tester.getRect(
      find.byKey(const ValueKey('repository-details')),
    );
    expect(panel.left, greaterThanOrEqualTo(0));
    expect(panel.right, lessThanOrEqualTo(420));
    expect(tester.takeException(), isNull);
  });

  test('the details of a tab follow its snapshot and its own running work', () {
    final session = RepositorySessionIdentity(
      nativeId: BigInt.from(7),
      generation: 2,
    );
    final tab = RepositoryTabState(
      id: 1,
      generation: 2,
      label: 'linked',
      phase: RepositoryTabPhase.open,
      requestedIdentity: _path('/work/linked'),
      session: RepositorySessionState(
        identity: session,
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: RepositoryIdentity(
            commonGitDir: _path('/work/main/.git'),
            worktreeRoot: _path('/work/linked'),
            gitDir: _path('/work/main/.git/worktrees/linked'),
            kind: RepositoryKind.worktree,
            headKind: HeadKind.attached,
            headReference: 'refs/heads/topic'.codeUnits,
            gitMajor: 2,
            gitMinor: 47,
            gitPatch: 0,
          ),
        ),
      ),
    );
    OperationCenterEntry entry(RepositorySessionIdentity owner) =>
        OperationCenterEntry(
          session: owner,
          state: OperationCenterState.running,
          origin: OperationCenterOrigin.user,
          action: OperationCenterAction.pull,
          startedAtUnixMs: BigInt.zero,
          canCancel: false,
          canRetry: false,
          hasDetails: false,
        );
    final details = RepositoryDetails.of(
      tab,
      name: 'linked',
      operations: OperationCenterSnapshot(
        runningCount: 2,
        failedCount: 0,
        attentionCount: 0,
        truncated: false,
        entries: [
          entry(
            RepositorySessionIdentity(nativeId: BigInt.from(9), generation: 1),
          ),
          entry(session),
        ],
      ),
    );
    expect(details.linkedWorktree, isTrue);
    expect(details.remote, isFalse);
    expect(String.fromCharCodes(details.branch!), 'topic');
    expect(details.operation?.session, same(session));
    expect(details.gitVersion, '2.47.0');
    expect(details.path?.displayText, '/work/linked');
  });
}
