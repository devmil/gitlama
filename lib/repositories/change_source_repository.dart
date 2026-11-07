import '../models/diff.dart';
import '../models/diff_renderer.dart';
import '../models/integrations.dart';
import '../models/repository_state.dart';

/// Content of a repository on another computer that this computer turns into
/// something itself: the host reads it, and images are decoded, diff tools
/// run and diff renderers run here. Tools run on this computer belong to no
/// local session.
abstract interface class ChangeSourceRepositorySessionRepository {
  /// Both sides of a file changed between commits; a missing path has no
  /// side.
  Future<ChangeSourceBytes> changeSource(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    List<int>? oldPath,
    List<int>? newPath,
    required int byteLimit,
  });

  /// Both sides of one staged or unstaged working-tree change.
  Future<ChangeSourceBytes> workingChangeSource(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    required int byteLimit,
  });

  /// The diff a renderer reads for the loaded diff [requestId].
  Future<List<int>> diffRendererInput(
    RepositorySessionIdentity identity,
    BigInt requestId,
  );

  Future<ImageDiffContent> decodeImage(ChangeSourceBytes source);

  Future<IntegrationPreview> previewDetachedDiffTool(
    ChangeSourceBytes source,
    IntegrationDefinition definition,
  );

  Future<IntegrationExecutionResult> executeDetachedIntegration(
    BigInt token, {
    required bool confirmed,
  });

  Future<bool> cancelDetachedIntegration(BigInt token);

  /// Validates [definition] for [source], whose renderer runs here.
  Future<DiffRendererPreview> validateDetachedDiffRenderer(
    RepositorySessionIdentity source,
    DiffRendererDefinition definition,
  );

  Future<DiffRendererPreview> previewDetachedDiffRenderer(
    RepositorySessionIdentity source,
    List<int> input,
    DiffRendererDefinition definition,
  );

  Future<DiffRendererResult> executeDetachedDiffRenderer(BigInt token);

  Future<DiffRendererResult> pollDetachedDiffRenderer(BigInt token);

  Future<bool> cancelDetachedDiffRenderer(BigInt token);
}
