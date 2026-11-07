import '../models/power_tools.dart';
import '../models/repository_state.dart';

abstract interface class PowerToolsRepositorySessionRepository {
  Future<BigInt> startDiffContentSearch(
    RepositorySessionIdentity identity, {
    required String query,
    required int maximumCommits,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,

    /// With [DiffSearchScope.allRefs], whether commits only references
    /// outside branches, remote branches, tags and the stash reach are
    /// searched too.
    bool otherRefs = false,
  });

  Future<DiffContentSearchResult> pollDiffContentSearch(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<BigInt> startRepositoryStatistics(RepositorySessionIdentity identity);

  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelPowerJob(RepositorySessionIdentity identity, BigInt token);

  Future<BisectState> bisectState(RepositorySessionIdentity identity);

  Future<BisectPreview> previewBisect(
    RepositorySessionIdentity identity,
    BisectAction action, {
    String? good,
    String? bad,
  });

  Future<BisectExecutionResult> executeBisect(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelBisectPreview(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
