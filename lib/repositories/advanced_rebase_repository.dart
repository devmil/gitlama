import '../models/advanced_rebase.dart';
import '../models/repository_state.dart';

abstract interface class AdvancedRebaseRepositorySessionRepository {
  Future<FixupSuggestion> suggestFixupBase(
    RepositorySessionIdentity identity, {
    String? selectedCommit,
    List<List<int>> paths = const [],
  });

  Future<RestackPlan> planRestack(
    RepositorySessionIdentity identity,
    List<int> rootBranch,
  );

  Future<RestackExecutionResult> executeRestack(
    RepositorySessionIdentity identity,
    BigInt token,
    bool acknowledgePublishedHistory,
  );

  Future<bool> cancelRestack(RepositorySessionIdentity identity, BigInt token);
}
