import '../../models/advanced_rebase.dart';
import '../../models/repository_state.dart';
import '../../repositories/advanced_rebase_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Fixup suggestions and restacking branches of the active repository.
final class AdvancedRebaseCommands {
  AdvancedRebaseCommands(
    this._repository,
    this._scope,
    PreviewRegistry previews,
  ) : _plans = previews.sessions();

  final AdvancedRebaseRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _plans;

  Future<FixupSuggestion> suggestFixupBase({
    String? selectedCommit,
    List<List<int>> paths = const [],
  }) => _repository.suggestFixupBase(
    _scope.requireCurrent(),
    selectedCommit: selectedCommit,
    paths: paths,
  );

  Future<RestackPlan> planRestack(List<int> rootBranch) async {
    final identity = _scope.requireCurrent();
    final plan = await _repository.planRestack(identity, rootBranch);
    _plans[plan.token] = identity;
    return plan;
  }

  Future<RestackExecutionResult> executeRestack(
    RestackPlan plan, {
    required bool acknowledgePublishedHistory,
  }) async {
    final identity = _plans[plan.token];
    if (identity == null) {
      throw const AdvancedRebaseException(
        AdvancedRebaseFailureCode.invalidRequest,
      );
    }
    try {
      final result = await _scope.followingHead(
        identity,
        () => _repository.executeRestack(
          identity,
          plan.token,
          acknowledgePublishedHistory,
        ),
        (result) =>
            result.state == RestackExecutionState.completed ||
            result.state == RestackExecutionState.reconciledWithWarning,
      );
      await _scope.refreshIfOpen(identity);
      return result;
    } finally {
      _plans.remove(plan.token);
    }
  }

  Future<bool> cancelRestack(RestackPlan plan) async {
    final identity = _plans[plan.token];
    if (identity == null) return false;
    return _repository.cancelRestack(identity, plan.token);
  }
}
