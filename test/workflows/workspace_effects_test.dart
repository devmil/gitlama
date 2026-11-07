import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/workspace_effects.dart';
import 'package:gitlama/services/workflows/workspace_navigator.dart';

import '../support/workflow_fake_repository.dart';

void main() {
  late RepositorySessionService repositories;
  late WorkspaceEffects effects;

  setUp(() async {
    repositories = RepositorySessionService(
      WorkflowFakeRepository(
        RepositorySnapshot(revision: BigInt.one, phase: RepositoryPhase.ready),
      ),
    );
    effects = WorkspaceEffects(repositories);
  });

  tearDown(() async {
    await effects.dispose();
    await repositories.dispose();
  });

  test('every effect has a new ID, and the latest of a kind stays', () {
    final seen = <WorkspaceEffect>[];
    effects.effects.listen(seen.add);
    effects.emit(WorkspaceEffectKind.flashCommit, (
      repository: null,
      objectId: 'a',
      amend: false,
    ));
    effects.emit(WorkspaceEffectKind.focusHistorySearch);
    expect(seen.map((effect) => effect.id), [1, 2]);
    expect(
      (effects.latest(WorkspaceEffectKind.flashCommit)!.payload!
              as CommittedFlash)
          .objectId,
      'a',
    );
  });

  test('a focus request is taken once, by whoever shows first', () {
    effects.emit(WorkspaceEffectKind.focusHistorySearch);
    expect(effects.take(WorkspaceEffectKind.focusHistorySearch), isNotNull);
    expect(effects.take(WorkspaceEffectKind.focusHistorySearch), isNull);
    // A surface that was listening marks it handled; nobody takes it later.
    effects.emit(WorkspaceEffectKind.focusHistorySearch);
    effects.handled(effects.latest(WorkspaceEffectKind.focusHistorySearch)!);
    expect(effects.take(WorkspaceEffectKind.focusHistorySearch), isNull);
  });

  test('the sidebar selection of a tab ends when the tab is left', () async {
    await repositories.open('/first');
    await repositories.open('/second');
    final navigator = WorkspaceNavigator(repositories);
    addTearDown(navigator.dispose);
    final second = repositories.activeTabId!;
    navigator.selectReference('refs/heads/topic');
    expect(navigator.selectedReference(second), 'refs/heads/topic');
    repositories.activateTab(repositories.workspace.tabs.first.id);
    expect(navigator.selectedReference(second), isNull);
  });
}
