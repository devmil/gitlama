import '../models/repository_view_cache.dart';
import '../models/settings.dart';

/// Private storage for disposable per-repository view entries.
///
/// A failure to read, or an entry that cannot be decoded, is reported as an
/// absent entry; a failure to write or remove is ignored: the cache only
/// ever speeds up what loading provides. Remote repositories are never
/// stored.
abstract interface class RepositoryViewCacheRepository {
  Future<RepositoryViewCacheEntry?> read(NativePathIdentity repository);
  Future<void> write(
    NativePathIdentity repository,
    RepositoryViewCacheEntry entry,
  );
  Future<void> remove(NativePathIdentity repository);
}
