import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/commit_workflow.dart';
import 'package:gitlama/services/workflows/workflow.dart';

import '../support/workflow_fake_repository.dart';

final class _Interaction implements CommitInteraction {
  @override
  bool active = true;
  bool amend = true;
  bool skip = true;
  final List<String> asked = [];

  @override
  Future<bool> confirmPublishedAmend() async {
    asked.add('amend');
    return amend;
  }

  @override
  Future<bool> confirmSkipHooks() async {
    asked.add('skipHooks');
    return skip;
  }
}

void main() {
  late WorkflowFakeRepository repository;
  late RepositorySessionService repositories;
  late CommitWorkflow commits;
  late _Interaction interaction;
  const draft = CommitDraft(subject: 'Subject', description: 'Body');
  const request = CommitRequest(subject: 'Subject', description: 'Body');

  setUp(() async {
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/repository'.codeUnits,
    );
    repository = WorkflowFakeRepository(
      RepositorySnapshot(
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
    repositories = RepositorySessionService(repository);
    await repositories.open('/repository');
    commits = CommitWorkflow(repositories);
    interaction = _Interaction();
  });

  tearDown(() => repositories.dispose());

  test('a commit and push pushes only once it committed', () async {
    final outcome =
        await commits.commit(interaction, request, draft, push: true)
            as CommitFinished;
    expect(outcome.committed, isTrue);
    expect(outcome.pushNext, isTrue);
    repository.commitResults.add(
      const CommitExecutionResult(state: CommitExecutionState.stale),
    );
    final stale =
        await commits.commit(interaction, request, draft, push: true)
            as CommitFinished;
    expect(stale.pushNext, isFalse);
  });

  test('amending published history asks first', () async {
    repository.commitWarnings = [CommitWarning.publishedAmend];
    interaction.amend = false;
    final outcome = await commits.commit(
      interaction,
      const CommitRequest(subject: 'Subject', amend: true),
      draft,
      push: false,
    );
    expect(outcome, isA<CommitDeclined>());
    expect(repository.calls, ['previewCommit']);
    expect(interaction.asked, ['amend']);
  });

  test('a hook rejection is retried without hooks once confirmed', () async {
    repository.commitResults.add(
      const CommitExecutionResult(
        state: CommitExecutionState.failed,
        failureKind: CommitFailureKind.hook,
        output: ['lint failed'],
      ),
    );
    final rejected =
        await commits.commit(interaction, request, draft, push: true)
            as CommitRejected;
    expect(rejected.result.failureKind, CommitFailureKind.hook);
    expect(rejected.push, isTrue);

    interaction.skip = false;
    expect(
      await commits.commit(
        interaction,
        request,
        draft,
        push: true,
        retry: CommitRetry.skipHooks,
      ),
      isA<CommitDeclined>(),
    );
    interaction.skip = true;
    await commits.commit(
      interaction,
      request,
      draft,
      push: true,
      retry: CommitRetry.skipHooks,
    );
    expect(repository.commitRequests.last.skipHooks, isTrue);
    await commits.commit(
      interaction,
      request,
      draft,
      push: false,
      retry: CommitRetry.unsigned,
    );
    expect(repository.commitRequests.last.signing, CommitSigning.disable);
    expect(repository.commitRequests.last.skipHooks, isFalse);
  });

  test('an unknown remote outcome is reported, never retried', () async {
    repository.commitError = const RemoteOutcomeUnknownException();
    final outcome =
        await commits.commit(interaction, request, draft, push: true)
            as CommitWorkflowFailed;
    expect(outcome.failure, isA<OutcomeUnknownFailure>());
    expect(
      repository.calls.where((call) => call == 'executeCommit'),
      hasLength(1),
    );
  });
}
