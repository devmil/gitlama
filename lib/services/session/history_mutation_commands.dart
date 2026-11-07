import '../../models/history_mutation.dart';
import '../../models/repository_state.dart';
import '../../repositories/history_mutation_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Merge, cherry-pick, revert, reset and the other history mutations of the
/// active repository, and the conflict predictions shown before them.
final class HistoryMutationCommands {
  HistoryMutationCommands(
    this._repository,
    this._scope,
    PreviewRegistry previews,
  ) : _previews = previews.sessions(),
      _predictions = previews.sessions();

  final HistoryMutationRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _previews;
  final PreviewTokens<RepositorySessionIdentity> _predictions;

  Future<HistoryMutationPreview> preview(HistoryMutationRequest request) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewHistoryMutation(identity, request);
    _previews[preview.token] = identity;
    return preview;
  }

  Future<HistoryMutationExecutionResult> execute(
    HistoryMutationPreview preview,
  ) async {
    _scope.ensureActive();
    final identity = _previews[preview.token];
    if (identity == null) throw unknownPreviewFailure;
    // The identity stays while the operation runs, so it can be canceled.
    try {
      return await _scope.followingHead(
        identity,
        () => _repository.executeHistoryMutation(identity, preview.token),
        (result) =>
            result.state == HistoryMutationExecutionState.completed ||
            result.state == HistoryMutationExecutionState.reconciledWithWarning,
      );
    } finally {
      _previews.remove(preview.token);
    }
  }

  Future<bool> cancel(HistoryMutationPreview preview) async {
    final identity = _previews[preview.token];
    if (identity == null) return false;
    return _repository.cancelHistoryMutation(identity, preview.token);
  }

  Future<ConflictPredictionTask> beginConflictPrediction(
    ConflictPredictionKind kind,
    String target,
  ) async {
    final identity = _scope.requireCurrent();
    final token = await _repository.beginConflictPrediction(identity);
    _predictions[token] = identity;
    return ConflictPredictionTask(token: token, kind: kind, target: target);
  }

  Future<ConflictPredictionResult> executeConflictPrediction(
    ConflictPredictionTask task,
  ) async {
    final identity = _predictions[task.token];
    if (identity == null) {
      throw const HistoryMutationException(
        HistoryMutationFailureCode.invalidRequest,
      );
    }
    try {
      return await _repository.executeConflictPrediction(
        identity,
        task.token,
        task.kind,
        task.target,
      );
    } finally {
      _predictions.remove(task.token);
    }
  }

  Future<bool> cancelConflictPrediction(ConflictPredictionTask task) async {
    final identity = _predictions[task.token];
    if (identity == null) return false;
    return _repository.cancelConflictPrediction(identity, task.token);
  }
}
