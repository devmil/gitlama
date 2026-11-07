import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/widgets/gitlama_repo_tabs.dart';

import 'motion/motion_support.dart';

NativePathIdentity _path(String value) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: value.codeUnits,
);

/// A tab open on the worktree [root] of the repository at [repository];
/// a [linked] one has its own Git directory.
RepositoryTabState _worktree(
  int id,
  String label,
  String repository, {
  bool linked = false,
}) => RepositoryTabState(
  id: id,
  generation: id,
  label: label,
  phase: RepositoryTabPhase.open,
  session: RepositorySessionState(
    identity: RepositorySessionIdentity(
      nativeId: BigInt.from(id),
      generation: id,
    ),
    snapshot: RepositorySnapshot(
      revision: BigInt.zero,
      phase: RepositoryPhase.ready,
      identity: RepositoryIdentity(
        commonGitDir: _path('$repository/.git'),
        worktreeRoot: _path(linked ? '/worktrees/$label' : repository),
        gitDir: _path(
          linked ? '$repository/.git/worktrees/$label' : '$repository/.git',
        ),
        kind: RepositoryKind.worktree,
        headKind: HeadKind.attached,
        gitMajor: 2,
        gitMinor: 50,
        gitPatch: 1,
      ),
    ),
  ),
);

void main() {
  final tabs = [
    _worktree(1, 'alpha', '/alpha'),
    _worktree(2, 'feature', '/alpha', linked: true),
    _worktree(3, 'beta', '/beta'),
  ];

  Widget strip(
    int active, {
    List<RepositoryTabState>? open,
    List<int>? activated,
    List<List<int>>? closedTogether,
    List<(int, int, int?)>? moved,
    List<(int, int)>? movedWorktrees,
  }) => motionHost(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 900,
        child: GitLamaRepoTabs(
          workspace: WorkspaceState(tabs: open ?? tabs, activeTabId: active),
          onActivate: (id) => activated?.add(id),
          onClose: (_) {},
          onCloseWorktrees: (ids) => closedTogether?.add(ids),
          onMoveTab: (id, index, group) => moved?.add((id, index, group)),
          onMoveWorktree: (id, index) => movedWorktrees?.add((id, index)),
          onOpenRepository: () {},
          worktreeLabelBuilder: (tab) => 'branch-${tab.label}',
          onOpenWorktree: (_) {},
        ),
      ),
    ),
  );

  final row = find.byKey(const ValueKey('repository-worktree-row'));

  testWidgets('a repository with several worktrees is one tab with a row', (
    tester,
  ) async {
    final activated = <int>[];
    await tester.pumpWidget(strip(2, activated: activated));
    await tester.pumpAndSettle();

    // The strip shows the repository once, marked with its worktree count.
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('feature'), findsNothing);

    // The row names each worktree by what it has checked out.
    expect(row, findsOneWidget);
    expect(find.text('branch-alpha'), findsOneWidget);
    expect(find.text('branch-feature'), findsOneWidget);
    expect(find.byTooltip('Open worktree'), findsOneWidget);

    await tester.tap(find.text('branch-alpha'));
    await tester.pump();
    expect(activated, [1]);
  });

  testWidgets('the row folds away for another repository and returns', (
    tester,
  ) async {
    final activated = <int>[];
    await tester.pumpWidget(strip(2, activated: activated));
    await tester.pumpAndSettle();
    final unfolded = tester.getSize(find.byType(GitLamaRepoTabs)).height;

    await tester.pumpWidget(strip(3, activated: activated));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(
      tester.getSize(find.byType(GitLamaRepoTabs)).height,
      lessThan(unfolded),
    );

    // The repository's tab returns to the worktree it showed last.
    await tester.tap(find.text('alpha'));
    await tester.pump();
    expect(activated, [2]);
  });

  testWidgets('one open worktree is an ordinary tab without a row', (
    tester,
  ) async {
    await tester.pumpWidget(strip(2, open: [tabs[1], tabs[2]]));
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsOneWidget);
    expect(row, findsNothing);
  });

  testWidgets('closing the repository tab closes all its worktrees', (
    tester,
  ) async {
    final closed = <List<int>>[];
    await tester.pumpWidget(strip(3, closedTogether: closed));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'), buttons: 4);
    await tester.pump();
    expect(closed, [
      [1, 2],
    ]);
  });
}
