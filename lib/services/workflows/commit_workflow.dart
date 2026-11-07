import '../../models/commit.dart';
import '../../models/settings.dart';
import '../repository_session_service.dart';
import 'workflow.dart';
import 'workspace_effects.dart';

/// What committing asks of the window it runs in.
abstract interface class CommitInteraction implements WorkflowInteraction {
  /// Asks to amend a commit that is already published.
  Future<bool> confirmPublishedAmend();

  /// Asks to run the commit without its hooks; the user types a word to
  /// confirm.
  Future<bool> confirmSkipHooks();
}

/// How a commit attempt ended.
sealed class CommitOutcome {
  const CommitOutcome();
}

/// The user declined a confirmation; nothing ran.
final class CommitDeclined extends CommitOutcome {
  const CommitDeclined();
}

/// Git refused the commit, for example in a hook or while signing. The
/// editor shows [result]'s output and offers the retries that apply.
final class CommitRejected extends CommitOutcome {
  const CommitRejected(this.result, {required this.push});

  final CommitExecutionResult result;

  /// Whether the attempt was a Commit & Push, which a retry repeats.
  final bool push;
}

/// The commit ran: completed, stale or reconciled with a warning. With
/// [pushNext] the window starts the push it asked for.
final class CommitFinished extends CommitOutcome {
  const CommitFinished(this.result, {required this.pushNext});

  final CommitExecutionResult result;
  final bool pushNext;

  bool get committed =>
      result.state == CommitExecutionState.completed ||
      result.state == CommitExecutionState.reconciledWithWarning;
}

final class CommitWorkflowFailed extends CommitOutcome {
  const CommitWorkflowFailed(this.failure);

  final WorkflowFailure failure;
}

/// How a rejected commit is tried again.
enum CommitRetry {
  /// Without the hooks that rejected it, once the user confirmed that.
  skipHooks,

  /// Without signing.
  unsigned,
}

/// The Composer's commit: preview, confirm amending published history,
/// commit, and decide whether a push follows. A rejected commit is retried
/// without hooks or without signing.
final class CommitWorkflow {
  CommitWorkflow(this._repositories, [this._effects]);

  final RepositorySessionService _repositories;
  final WorkspaceEffects? _effects;

  /// Commits [request], whose message is [draft]; [push] pushes afterwards.
  /// A [retry] changes the request as it says; skipping hooks asks first.
  Future<CommitOutcome> commit(
    CommitInteraction interaction,
    CommitRequest request,
    CommitDraft draft, {
    required bool push,
    CommitRetry? retry,
  }) async {
    if (retry == CommitRetry.skipHooks &&
        !await interaction.confirmSkipHooks()) {
      return const CommitDeclined();
    }
    final effective = switch (retry) {
      null => request,
      CommitRetry.skipHooks => _with(request, skipHooks: true),
      CommitRetry.unsigned => _with(request, signing: CommitSigning.disable),
    };
    _repositories.updateCommitDraft(draft);
    final repository = _repositories.activeTab?.canonicalIdentity;
    try {
      final preview = await _repositories.previewCommit(effective);
      if (preview.warnings.contains(CommitWarning.publishedAmend) &&
          !await interaction.confirmPublishedAmend()) {
        return const CommitDeclined();
      }
      final result = await _repositories.executeCommit(preview, draft);
      if (result.state == CommitExecutionState.failed) {
        return CommitRejected(result, push: push);
      }
      final committed =
          result.state == CommitExecutionState.completed ||
          result.state == CommitExecutionState.reconciledWithWarning;
      // History flashes the commit, the staged list empties.
      final objectId = result.commit;
      if (committed && objectId != null) {
        _effects?.emit(WorkspaceEffectKind.flashCommit, (
          repository: repository,
          objectId: objectId,
          amend: effective.amend,
        ));
      }
      return CommitFinished(result, pushNext: push && committed);
    } on Object catch (error) {
      final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
      return CommitWorkflowFailed(failure);
    }
  }

  static CommitRequest _with(
    CommitRequest request, {
    bool? skipHooks,
    CommitSigning? signing,
  }) => CommitRequest(
    subject: request.subject,
    description: request.description,
    coauthors: request.coauthors,
    author: request.author,
    amend: request.amend,
    skipHooks: skipHooks ?? request.skipHooks,
    signing: signing ?? request.signing,
    signOff: request.signOff,
  );
}
