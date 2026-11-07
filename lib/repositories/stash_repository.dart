import '../models/repository_state.dart';
import '../models/stash.dart';

abstract interface class StashRepositorySessionRepository {
  Future<StashPreview> previewStash(
    RepositorySessionIdentity identity,
    StashRequest request,
  );

  Future<StashExecutionResult> executeStash(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelStash(RepositorySessionIdentity identity, BigInt token);
}
