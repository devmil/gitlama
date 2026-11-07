import '../../models/diff_renderer.dart';
import '../../repositories/diff_renderer_repository.dart';
import 'session_scope.dart';

/// Checking a diff renderer definition against the active repository.
final class DiffRendererCommands {
  DiffRendererCommands(this._repository, this._scope);

  final DiffRendererRepositorySessionRepository _repository;
  final SessionScope _scope;

  Future<DiffRendererPreview> validate(DiffRendererDefinition definition) =>
      _repository.validateDiffRenderer(_scope.requireCurrent(), definition);
}
