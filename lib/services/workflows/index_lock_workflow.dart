import '../../models/index_lock.dart';
import '../repository_session_service.dart';
import 'workflow.dart';

/// What removing a stale index lock asks of the window it runs in.
abstract interface class IndexLockInteraction implements WorkflowInteraction {
  /// Asks to remove the lock file of [sizeBytes] bytes.
  Future<bool> confirmIndexLockRemoval(int sizeBytes);

  void reportIndexLock(IndexLockOutcome outcome);
}

/// How an index-lock inspection ended, for the window to report.
sealed class IndexLockOutcome {
  const IndexLockOutcome();
}

final class IndexLockNotFound extends IndexLockOutcome {
  const IndexLockNotFound();
}

final class IndexLockRemoved extends IndexLockOutcome {
  const IndexLockRemoved();
}

/// The lock could not be inspected or removed, for [code].
final class IndexLockRefused extends IndexLockOutcome {
  const IndexLockRefused(this.code);

  final IndexLockFailureCode code;
}

final class IndexLockFailed extends IndexLockOutcome {
  const IndexLockFailed(this.failure);

  final WorkflowFailure failure;
}

/// Finds a leftover `index.lock` of the active repository and removes it
/// once the user confirmed. The lock is removed only while it is the file
/// that was inspected.
final class IndexLockWorkflow {
  IndexLockWorkflow(this._repositories);

  final RepositorySessionService _repositories;

  Future<void> run(IndexLockInteraction interaction) async {
    void report(IndexLockOutcome outcome) {
      if (interaction.active) interaction.reportIndexLock(outcome);
    }

    try {
      final result = await _repositories.workingCopy.inspectIndexLock();
      if (!interaction.active) return;
      final inspection = result.inspection;
      if (!inspection.present) {
        report(const IndexLockNotFound());
        return;
      }
      final token = inspection.token;
      if (token == null) return;
      final confirmed = await interaction.confirmIndexLockRemoval(
        inspection.sizeBytes?.toInt() ?? 0,
      );
      if (!confirmed || !interaction.active) return;
      await _repositories.workingCopy.removeIndexLock(result.identity, token);
      report(const IndexLockRemoved());
    } on IndexLockException catch (error) {
      report(IndexLockRefused(error.code));
    } on Object catch (error) {
      final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
      report(IndexLockFailed(failure));
    }
  }
}
