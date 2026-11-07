import '../models/conflict.dart';
import '../models/integrations.dart';
import '../models/repository_state.dart';

abstract interface class IntegrationRepositorySessionRepository {
  Future<List<IntegrationCandidate>> discoverIntegrations(IntegrationKind kind);

  Future<IntegrationPreview> previewIntegration(
    RepositorySessionIdentity identity,
    IntegrationRequest request,
  );

  Future<IntegrationPreview> previewExternalConflictMerge(
    RepositorySessionIdentity identity,
    ConflictFile file,
    IntegrationDefinition definition,
  );

  Future<IntegrationPreview> previewExternalCommitDiff(
    RepositorySessionIdentity identity, {
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  });

  Future<IntegrationExecutionResult> executeIntegration(
    RepositorySessionIdentity identity,
    BigInt token, {
    required bool confirmed,
  });

  Future<bool> cancelIntegration(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
