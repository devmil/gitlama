import '../models/history_mutation.dart';
import '../models/repository_state.dart';

abstract interface class HistoryMutationRepositorySessionRepository {
  Future<HistoryMutationPreview> previewHistoryMutation(
    RepositorySessionIdentity identity,
    HistoryMutationRequest request,
  );

  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<BigInt> beginConflictPrediction(RepositorySessionIdentity identity);

  Future<ConflictPredictionResult> executeConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
    ConflictPredictionKind kind,
    String target,
  );

  Future<bool> cancelConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
