import '../../models/rebase.dart';
import '../../models/repository_state.dart';
import '../../repositories/rebase_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Interactive rebase of the active repository.
final class RebaseCommands {
  RebaseCommands(this._repository, this._scope, PreviewRegistry previews)
    : _plans = previews.sessions();

  final RebaseRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _plans;

  Future<RebasePlan> loadPlan(String onto, List<int>? ontoName) async {
    final identity = _scope.requireCurrent();
    final plan = await _repository.loadRebasePlan(identity, onto, ontoName);
    _plans[plan.token] = identity;
    return plan;
  }

  Future<RebasePreview> preview(
    RebasePlan plan,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) {
    final identity = _plans[plan.token];
    if (identity == null) {
      throw const RebaseException(RebaseFailureCode.invalidRequest);
    }
    return _repository.previewRebase(
      identity,
      plan.token,
      instructions,
      acknowledgePublishedHistory,
      applyAutosquash,
    );
  }

  Future<RebaseExecutionResult> execute(RebasePreview preview) async {
    final identity = _plans[preview.token];
    if (identity == null) {
      throw const RebaseException(RebaseFailureCode.invalidRequest);
    }
    try {
      return await _scope.followingHead(
        identity,
        () => _repository.executeRebase(identity, preview.token),
        (result) =>
            result.state == RebaseExecutionState.completed ||
            result.state == RebaseExecutionState.reconciledWithWarning,
      );
    } finally {
      _plans.remove(preview.token);
    }
  }

  Future<bool> cancel(BigInt token) async {
    final identity = _plans[token];
    if (identity == null) return false;
    return _repository.cancelRebase(identity, token);
  }
}
