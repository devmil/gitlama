import '../models/repository_state.dart';
import '../models/settings.dart';

/// What services that only open repositories need from the workspace:
/// opening by path or recent identity, the active session, and a rescan.
abstract interface class RepositoryOpener {
  RepositorySessionState? get current;

  Future<RepositorySessionState> open(String path);

  Future<RepositorySessionState> openRecent(NativePathIdentity identity);

  /// Rescans the active repository for changes made outside the application.
  Future<void> refresh();
}
