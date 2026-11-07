import '../models/inspector.dart';
import '../models/inspector_reveal.dart';
import '../models/settings.dart';
import '../repositories/inspector_reveal_repository.dart';

/// Lets inspector windows reveal commits in the main window's graph.
final class InspectorRevealService {
  InspectorRevealService(this._repository);

  /// A window without inspector windows: nothing asks it to reveal, and it
  /// reaches no main window.
  InspectorRevealService.unavailable() : _repository = const _NoReveal();

  final InspectorRevealRepository _repository;

  /// Serves requests from inspector windows (main window only).
  Future<void> listen(
    Future<bool> Function(InspectorRevealRequest request) onReveal,
  ) => _repository.listen(onReveal);

  /// Reveals [target] of [repository] in the main window; false when it is
  /// not open there.
  Future<bool> reveal(NativePathIdentity repository, InspectorTarget target) =>
      _repository.reveal(
        InspectorRevealRequest(
          repository: repository,
          commit: target.commit,
          base: target.base,
        ),
      );

  Future<void> dispose() => _repository.dispose();
}

final class _NoReveal implements InspectorRevealRepository {
  const _NoReveal();

  @override
  Future<void> listen(
    Future<bool> Function(InspectorRevealRequest) onReveal,
  ) async {}

  @override
  Future<bool> reveal(InspectorRevealRequest request) async => false;

  @override
  Future<void> dispose() async {}
}
