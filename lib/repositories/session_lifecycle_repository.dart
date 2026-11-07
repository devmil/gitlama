import '../models/clone_attempt.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';

/// Opening, observing and closing repository sessions. The workspace owns
/// this capability; every family of commands works on the sessions it opens.
abstract interface class SessionLifecycleRepository {
  Future<OpenedRepositorySession> open(String path, int generation);

  Future<OpenedRepositorySession> openIdentity(
    NativePathIdentity identity,
    int generation,
  );

  Future<OpenedRepositorySession> initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  });

  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  });

  /// Rescans [identity] for changes made outside the application.
  Future<void> refresh(RepositorySessionIdentity identity);

  Future<bool> close(RepositorySessionIdentity identity);
}
