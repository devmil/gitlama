import '../../models/ref_mutation.dart';
import '../../models/repository_state.dart';
import '../preview_registry.dart';
import '../../repositories/ref_mutation_repository.dart';
import 'session_scope.dart';

/// Creating, renaming, moving and deleting the active repository's branches
/// and tags.
final class RefMutationCommands {
  RefMutationCommands(this._repository, this._scope, PreviewRegistry previews)
    : _previews = previews.sessions();

  final RefMutationRepository _repository;
  final SessionScope _scope;

  final PreviewTokens<RepositorySessionIdentity> _previews;

  Future<RefMutationPreview> preview(RefMutationRequest request) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewRefMutation(identity, request);
    if (!_scope.isOpen(identity)) throw unknownSessionFailure;
    _previews[preview.token] = identity;
    return preview;
  }

  void discard(BigInt token) => _previews.remove(token);

  Future<RefMutationExecutionResult> execute(BigInt token) async {
    _scope.ensureActive();
    final identity = _previews.remove(token);
    if (identity == null) throw unknownPreviewFailure;
    if (!_scope.isOpen(identity)) throw unknownSessionFailure;
    final current = _scope.requireCurrent();
    if (current.nativeId != identity.nativeId ||
        current.generation != identity.generation ||
        current.backend != identity.backend) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.staleGeneration),
      );
    }
    return _repository.executeRefMutation(identity, token);
  }
}
