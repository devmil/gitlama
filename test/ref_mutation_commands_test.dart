import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/preview_registry.dart';
import 'package:gitlama/services/session/ref_mutation_commands.dart';
import 'package:gitlama/services/session/session_scope.dart';

import 'support/workflow_fake_repository.dart';

class _Scope implements SessionScope {
  RepositorySessionIdentity current = RepositorySessionIdentity(
    nativeId: BigInt.one,
    generation: 1,
  );
  bool open = true;
  @override
  RepositorySessionIdentity requireCurrent() => current;
  @override
  void ensureActive() {}
  @override
  bool isOpen(RepositorySessionIdentity identity) => open;
  @override
  Future<void> refreshIfOpen(RepositorySessionIdentity identity) async {}
  @override
  Future<T> followingHead<T>(
    RepositorySessionIdentity identity,
    Future<T> Function() operation,
    bool Function(T) moved,
  ) => operation();
}

void main() {
  const request = RefMutationRequest(
    kind: RefMutationKind.createBranch,
    name: 'topic',
    target: '1111111111111111111111111111111111111111',
  );

  test('a token cannot execute against another active repository', () async {
    final scope = _Scope();
    final repository = WorkflowFakeRepository(
      RepositorySnapshot(revision: BigInt.one, phase: RepositoryPhase.ready),
    );
    final registry = PreviewRegistry();
    final commands = RefMutationCommands(repository, scope, registry);
    final preview = await commands.preview(request);
    scope.current = RepositorySessionIdentity(
      nativeId: BigInt.two,
      generation: 1,
    );
    await expectLater(
      commands.execute(preview.token),
      throwsA(isA<RepositorySessionException>()),
    );
    expect(repository.calls.where((c) => c.startsWith('executeRef')), isEmpty);
    expect(registry.length, 0);
  });

  test(
    'closing a session retires its previews; execution is one-shot',
    () async {
      final scope = _Scope();
      final repository = WorkflowFakeRepository(
        RepositorySnapshot(revision: BigInt.one, phase: RepositoryPhase.ready),
      );
      final registry = PreviewRegistry();
      final commands = RefMutationCommands(repository, scope, registry);
      final retired = await commands.preview(request);
      registry.forgetSession(scope.current);
      await expectLater(
        commands.execute(retired.token),
        throwsA(isA<RepositorySessionException>()),
      );
      final preview = await commands.preview(request);
      await commands.execute(preview.token);
      await expectLater(
        commands.execute(preview.token),
        throwsA(isA<RepositorySessionException>()),
      );
      expect(
        repository.calls.where((c) => c.startsWith('executeRef')).length,
        1,
      );
    },
  );
}
