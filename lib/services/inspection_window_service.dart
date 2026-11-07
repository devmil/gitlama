import '../models/inspection_window.dart';
import '../models/inspector.dart';
import '../models/settings.dart';
import '../repositories/inspection_window_repository.dart';

final class InspectionWindowService {
  const InspectionWindowService(this._repository) : available = true;

  /// A window that cannot open inspector windows, such as a narrow test.
  const InspectionWindowService.unavailable()
    : _repository = const _NoInspectionWindows(),
      available = false;

  final InspectionWindowRepository _repository;

  /// Whether locations can open in inspector windows here.
  final bool available;

  /// Opens [location] of [repository] in a new inspector window.
  Future<void> open({
    required NativePathIdentity repository,
    required InspectorLocation location,
  }) => _repository.open(
    InspectionWindowRequest(
      repository: repository,
      location: location.normalized(),
    ),
  );

  Future<void> openBlame({
    required NativePathIdentity repository,
    required String commit,
    required List<int> path,
  }) => open(
    repository: repository,
    location: InspectorLocation(
      target: CommitTarget(commit),
      path: path,
      lens: InspectorLens.blame,
    ),
  );

  Future<void> openTree({
    required NativePathIdentity repository,
    required String commit,
    List<int>? directory,
  }) => open(
    repository: repository,
    location: InspectorLocation(
      target: CommitTarget(commit),
      scope: InspectorScope.all,
      path: directory,
      directory: directory != null,
      lens: directory != null ? InspectorLens.history : InspectorLens.diff,
    ),
  );
}

final class _NoInspectionWindows implements InspectionWindowRepository {
  const _NoInspectionWindows();

  @override
  Future<void> open(InspectionWindowRequest request) =>
      Future.error(StateError('inspection_windows_unavailable'));
}
