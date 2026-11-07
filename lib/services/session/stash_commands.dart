import '../../models/repository_state.dart';
import '../../models/stash.dart';
import '../../repositories/stash_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Stashing, applying, popping and dropping stashes of the active repository.
final class StashCommands {
  StashCommands(this._repository, this._scope, PreviewRegistry previews)
    : _previews = previews.sessions();

  final StashRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _previews;

  Future<StashPreview> preview(StashRequest request) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewStash(identity, request);
    _previews[preview.token] = identity;
    return preview;
  }

  Future<StashExecutionResult> execute(StashPreview preview) async {
    _scope.ensureActive();
    final identity = _previews[preview.token];
    if (identity == null) throw unknownPreviewFailure;
    // The identity stays while the stash runs, so it can be canceled.
    try {
      return await _repository.executeStash(identity, preview.token);
    } finally {
      _previews.remove(preview.token);
    }
  }

  Future<bool> cancel(StashPreview preview) async {
    final identity = _previews[preview.token];
    if (identity == null) return false;
    return _repository.cancelStash(identity, preview.token);
  }
}
