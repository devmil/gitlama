import '../../models/conflict.dart';
import '../../models/integrations.dart';
import '../../models/repository_state.dart';
import '../../repositories/integration_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// External editors, diff and merge tools and file managers run on the
/// active repository.
final class IntegrationCommands {
  IntegrationCommands(this._repository, this._scope, PreviewRegistry previews)
    : _previews = previews.sessions();

  final IntegrationRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _previews;

  Future<List<IntegrationCandidate>> discover(IntegrationKind kind) =>
      _repository.discoverIntegrations(kind);

  Future<IntegrationPreview> preview(IntegrationRequest request) => _remember(
    (identity) => _repository.previewIntegration(identity, request),
  );

  Future<IntegrationPreview> previewExternalConflictMerge(
    ConflictFile file,
    IntegrationDefinition definition,
  ) => _remember(
    (identity) =>
        _repository.previewExternalConflictMerge(identity, file, definition),
  );

  Future<IntegrationPreview> previewExternalCommitDiff({
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  }) => _remember(
    (identity) => _repository.previewExternalCommitDiff(
      identity,
      oldRevision: oldRevision,
      newRevision: newRevision,
      oldPath: oldPath,
      newPath: newPath,
      definition: definition,
    ),
  );

  Future<IntegrationExecutionResult> execute(
    IntegrationPreview preview, {
    required bool confirmed,
  }) async {
    final identity = _previews.remove(preview.token);
    if (identity == null) {
      throw const IntegrationException(IntegrationFailureCode.invalidRequest);
    }
    return _repository.executeIntegration(
      identity,
      preview.token,
      confirmed: confirmed,
    );
  }

  Future<bool> cancel(IntegrationPreview preview) async {
    final identity = _previews.remove(preview.token);
    if (identity == null) return false;
    return _repository.cancelIntegration(identity, preview.token);
  }

  Future<IntegrationPreview> _remember(
    Future<IntegrationPreview> Function(RepositorySessionIdentity identity)
    preview,
  ) async {
    final identity = _scope.requireCurrent();
    final result = await preview(identity);
    _previews[result.token] = identity;
    return result;
  }
}
