import '../models/rebase.dart';
import '../models/repository_state.dart';

abstract interface class RebaseRepositorySessionRepository {
  Future<RebasePlan> loadRebasePlan(
    RepositorySessionIdentity identity,
    String onto,
    List<int>? ontoName,
  );

  Future<RebasePreview> previewRebase(
    RepositorySessionIdentity identity,
    BigInt token,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  );

  Future<RebaseExecutionResult> executeRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelRebase(RepositorySessionIdentity identity, BigInt token);
}
