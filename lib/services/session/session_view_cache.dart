import '../../models/history.dart';
import '../../models/repository_state.dart';
import '../../models/repository_view_cache.dart';
import '../../models/settings.dart';
import '../repository_view_cache_service.dart';

/// What each repository showed when it was last open, presented while it
/// loads again.
abstract interface class SessionViewCache {
  /// Reads the stored entries of [repositories] ahead of their tabs.
  Future<void> warm(Iterable<NativePathIdentity> repositories);

  RepositoryViewCacheEntry? entry(NativePathIdentity repository);

  /// [snapshot] with what the repository showed last time in the places it
  /// has not loaded yet. A loaded or failed snapshot is never changed.
  RepositorySnapshot present(RepositorySnapshot snapshot);

  /// Keeps the references and status of [snapshot].
  void remember(RepositorySnapshot snapshot);

  /// Keeps the first history [page] of [repository].
  void rememberHistory(NativePathIdentity repository, HistoryPage page);
}

/// Keeps nothing: every repository loads as usual.
final class NoSessionViewCache implements SessionViewCache {
  const NoSessionViewCache();

  @override
  Future<void> warm(Iterable<NativePathIdentity> repositories) async {}

  @override
  RepositoryViewCacheEntry? entry(NativePathIdentity repository) => null;

  @override
  RepositorySnapshot present(RepositorySnapshot snapshot) => snapshot;

  @override
  void remember(RepositorySnapshot snapshot) {}

  @override
  void rememberHistory(NativePathIdentity repository, HistoryPage page) {}
}

/// The view cache of [RepositoryViewCacheService].
final class ServiceSessionViewCache implements SessionViewCache {
  ServiceSessionViewCache(this._service);

  final RepositoryViewCacheService _service;

  @override
  Future<void> warm(Iterable<NativePathIdentity> repositories) =>
      _service.warm(repositories);

  @override
  RepositoryViewCacheEntry? entry(NativePathIdentity repository) =>
      _service.entry(repository);

  @override
  RepositorySnapshot present(RepositorySnapshot snapshot) {
    final repository = snapshot.identity?.worktreeRoot;
    final known = repository == null ? null : _service.entry(repository);
    if (known == null ||
        snapshot.failure != null ||
        (snapshot.phase != RepositoryPhase.loading &&
            snapshot.phase != RepositoryPhase.unloaded)) {
      return snapshot;
    }
    final counts = snapshot.refCounts;
    final refs = snapshot.refs;
    final refsLoaded =
        snapshot.refsFailure != null ||
        counts.branches + counts.remotes + counts.tags + counts.stashes > 0 ||
        refs.branches.isNotEmpty ||
        refs.remotes.isNotEmpty ||
        refs.tags.isNotEmpty ||
        refs.stashes.isNotEmpty;
    final statusLoaded =
        snapshot.status != null || snapshot.statusFailure != null;
    if ((refsLoaded || known.refs == null) &&
        (statusLoaded || known.status == null)) {
      return snapshot;
    }
    return snapshot.copyWith(
      status: statusLoaded ? snapshot.status : known.status,
      refCounts: refsLoaded ? counts : known.refCounts ?? counts,
      refs: refsLoaded ? refs : known.refs ?? refs,
    );
  }

  @override
  void remember(RepositorySnapshot snapshot) {
    final repository = snapshot.identity?.worktreeRoot;
    if (repository != null) _service.rememberSnapshot(repository, snapshot);
  }

  @override
  void rememberHistory(NativePathIdentity repository, HistoryPage page) =>
      _service.rememberHistory(repository, page);
}
