import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/shell_chrome.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/repository_appearance.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';

import 'motion/motion_support.dart';

const _head = '1111111111111111111111111111111111111111';

NativePathIdentity _path(String path) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: path.codeUnits,
);

RepositoryIdentity _identity({
  HeadKind headKind = HeadKind.attached,
  String? headReference = 'refs/heads/master',
}) => RepositoryIdentity(
  commonGitDir: _path('/repository/.git'),
  worktreeRoot: _path('/repository'),
  gitDir: _path('/repository/.git'),
  kind: RepositoryKind.worktree,
  headKind: headKind,
  headReference: headReference?.codeUnits,
  headObjectId: _head,
  gitMajor: 2,
  gitMinor: 50,
  gitPatch: 1,
);

Widget _toolbar({
  RepositoryIdentity? identity,
  List<OperationCenterEntry> entries = const [],
}) => motionHost(
  SizedBox(
    width: 1400,
    child: WorkspaceToolbar(
      active: RepositoryTabState(
        id: 1,
        generation: 1,
        label: 'big-app',
        phase: RepositoryTabPhase.open,
        session: RepositorySessionState(
          identity: RepositorySessionIdentity(
            nativeId: BigInt.one,
            generation: 1,
          ),
          // References are published before the first worktree scan ends.
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.loading,
            identity: identity,
          ),
        ),
      ),
      onCommand:
          (
            id, {
            force = false,
            initialName,
            initialTarget,
            initialReference,
          }) {},
      operations: OperationCenterSnapshot(
        entries: entries,
        runningCount: entries.length,
        failedCount: 0,
        attentionCount: 0,
        truncated: false,
      ),
      operationsVisible: false,
      activityVisible: false,
      shortcuts: const {},
      compassKey: GlobalKey(),
    ),
  ),
);

GitLamaCompass _compass(WidgetTester tester) =>
    tester.widget<GitLamaCompass>(find.byType(GitLamaCompass));

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1600, 900);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  testWidgets('the branch discovery found is shown before the first status', (
    tester,
  ) async {
    await tester.pumpWidget(_toolbar(identity: _identity()));
    expect(_compass(tester).branch, 'master');
    expect(_compass(tester).detached, isFalse);
    expect(find.text('Detached HEAD'), findsNothing);

    await tester.pumpWidget(
      _toolbar(
        identity: _identity(headKind: HeadKind.detached, headReference: null),
      ),
    );
    await tester.pumpAndSettle();
    expect(_compass(tester).branch, 'Detached at 11111111');
    expect(_compass(tester).detached, isTrue);
  });

  testWidgets('a running transfer reports its phase and completion', (
    tester,
  ) async {
    OperationCenterEntry pull(ActivityProgress? progress) =>
        OperationCenterEntry(
          activityId: BigInt.from(7),
          state: OperationCenterState.running,
          origin: OperationCenterOrigin.user,
          action: OperationCenterAction.pull,
          startedAtUnixMs: BigInt.one,
          canCancel: true,
          canRetry: false,
          hasDetails: true,
          progress: progress,
        );
    ActivityProgress updating(int percent) => ActivityProgress(
      phase: 'Updating files',
      completed: BigInt.from(percent),
      total: BigInt.from(100),
      unit: 'percent',
    );

    await tester.pumpWidget(
      _toolbar(identity: _identity(), entries: [pull(null)]),
    );
    // The indeterminate rule never settles while the transfer runs.
    await pumpFrames(tester, const Duration(milliseconds: 600));
    expect(find.text('Pull…'), findsOneWidget);

    for (final percent in [40, 85]) {
      await tester.pumpWidget(
        _toolbar(identity: _identity(), entries: [pull(updating(percent))]),
      );
      // The text changes in place: a percentage must not replay the swap.
      await tester.pump();
      expect(find.text('Pull · Updating files $percent%'), findsOneWidget);
      expect(_compass(tester).operation, 'Pull…');
      expect(_compass(tester).progress, percent / 100);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the compass names a tab as its strip does, after its group', (
    tester,
  ) async {
    const tab = RepositoryTabState(
      id: 1,
      generation: 1,
      label: '2026-09-24_folder',
      phase: RepositoryTabPhase.open,
      groupId: 7,
    );
    WorkspaceState workspace(String groupName) => WorkspaceState(
      tabs: const [tab],
      activeTabId: 1,
      groups: [
        RepositoryTabGroup(
          id: 7,
          color: const PaletteColor(RepositoryAppearanceColor.blue),
          name: groupName,
        ),
      ],
    );
    final titles = <String>[];
    await tester.pumpWidget(
      motionHost(
        Builder(
          builder: (context) {
            titles
              ..clear()
              ..addAll([
                repositoryTitle(context, workspace('Mobile'), tab),
                repositoryTitle(context, workspace('Mobile'), tab, name: 'App'),
                repositoryTitle(context, workspace(''), tab, name: 'App'),
                repositoryTitle(
                  context,
                  const WorkspaceState(tabs: [tab], activeTabId: 1),
                  tab,
                  name: 'App',
                ),
              ]);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(titles, [
      'Mobile / 2026-09-24_folder',
      'Mobile / App',
      'App',
      'App',
    ]);

    await tester.pumpWidget(
      motionHost(
        SizedBox(
          width: 1400,
          child: WorkspaceToolbar(
            active: tab,
            repositoryLabel: 'Mobile / App',
            onCommand:
                (
                  id, {
                  force = false,
                  initialName,
                  initialTarget,
                  initialReference,
                }) {},
            operations: const OperationCenterSnapshot(
              entries: [],
              runningCount: 0,
              failedCount: 0,
              attentionCount: 0,
              truncated: false,
            ),
            operationsVisible: false,
            activityVisible: false,
            shortcuts: const {},
            compassKey: GlobalKey(),
          ),
        ),
      ),
    );
    expect(_compass(tester).repository, 'Mobile / App');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
