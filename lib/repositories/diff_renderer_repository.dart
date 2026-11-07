import '../models/diff_renderer.dart';
import '../models/repository_state.dart';

/// Diff renderers the user configured, run on a session's diffs.
abstract interface class DiffRendererRepositorySessionRepository {
  Future<DiffRendererPreview> validateDiffRenderer(
    RepositorySessionIdentity identity,
    DiffRendererDefinition definition,
  );

  Future<DiffRendererPreview> previewDiffRenderer(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required DiffRendererDefinition definition,
  });

  Future<DiffRendererResult> executeDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<DiffRendererResult> pollDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
