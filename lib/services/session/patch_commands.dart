import '../../models/patch.dart';
import '../../models/repository_state.dart';
import '../../repositories/patch_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Exporting and applying patches in the active repository.
final class PatchCommands {
  PatchCommands(this._repository, this._scope, PreviewRegistry previews)
    : _exports = previews.sessions(),
      _applies = previews.sessions();

  final PatchRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _exports;
  final PreviewTokens<RepositorySessionIdentity> _applies;

  Future<PatchExportPreview> previewExport(PatchExportRequest request) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewPatchExport(identity, request);
    final token = preview.token;
    if (token != null) _exports[token] = identity;
    return preview;
  }

  Future<PatchExportExecutionResult> executeExport(
    PatchExportPreview preview,
  ) async {
    _scope.ensureActive();
    final token = preview.token;
    if (token == null) throw unknownPreviewFailure;
    final identity = _exports.remove(token);
    if (identity == null) throw unknownPreviewFailure;
    return _repository.executePatchExport(identity, token);
  }

  Future<PatchApplyPreview> previewApply(String patchPath) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewPatchApply(identity, patchPath);
    _applies[preview.token] = identity;
    return preview;
  }

  Future<PatchApplyExecutionResult> executeApply(
    PatchApplyPreview preview,
  ) async {
    _scope.ensureActive();
    final identity = _applies.remove(preview.token);
    if (identity == null) throw unknownPreviewFailure;
    return _repository.executePatchApply(identity, preview.token);
  }
}
