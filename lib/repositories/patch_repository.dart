import '../models/patch.dart';
import '../models/repository_state.dart';

abstract interface class PatchRepositorySessionRepository {
  Future<PatchExportPreview> previewPatchExport(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  );

  Future<PatchExportExecutionResult> executePatchExport(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  /// Builds the patch [request] names without saving it; its destination
  /// fields are ignored.
  Future<PatchExportContent> patchExportContent(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  );

  /// Prepares saving [content] in [destinationDirectory] on this computer.
  Future<PatchExportPreview> previewPatchSave(
    PatchExportContent content, {
    required String destinationDirectory,
    required bool overwrite,
  });

  /// Saves a prepared patch once.
  Future<PatchExportExecutionResult> executePatchSave(BigInt token);

  Future<PatchApplyPreview> previewPatchApply(
    RepositorySessionIdentity identity,
    String patchPath,
  );

  Future<PatchApplyExecutionResult> executePatchApply(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
