import 'dart:async';
import 'dart:isolate';

import '../../models/hosting_link_cache.dart';
import '../../models/repository_view_cache.dart';
import '../../models/settings.dart';
import '../hosting_link_cache_repository.dart';
import '../repository_view_cache_repository.dart';
import 'hosting_link_cache_codec.dart';
import 'private_entry_store.dart';
import 'repository_view_cache_codec.dart';

/// Runs [work] away from the interface thread.
typedef BackgroundRunner = Future<T> Function<T>(T Function() work);

Future<T> _runInIsolate<T>(T Function() work) => Isolate.run(work);

/// The repository view cache in a [PrivateEntryStore], encoded and decoded
/// away from the interface thread. An entry that cannot be decoded (another
/// schema, a damaged file) is removed and reported absent.
final class CodedRepositoryViewCacheRepository
    implements RepositoryViewCacheRepository {
  CodedRepositoryViewCacheRepository(
    this._store, {
    this._runInBackground = _runInIsolate,
  });

  final PrivateEntryStore _store;
  final BackgroundRunner _runInBackground;

  @override
  Future<RepositoryViewCacheEntry?> read(NativePathIdentity repository) async {
    final bytes = await _store.read(repository);
    if (bytes == null) return null;
    final decoded = await _runInBackground(() => decodeRepositoryView(bytes));
    // Another schema or a damaged file. Loading rebuilds the entry.
    if (decoded == null) await _store.remove(repository);
    return decoded;
  }

  @override
  Future<void> write(
    NativePathIdentity repository,
    RepositoryViewCacheEntry entry,
  ) async => _store.write(
    repository,
    await _runInBackground(() => encodeRepositoryView(entry)),
  );

  @override
  Future<void> remove(NativePathIdentity repository) =>
      _store.remove(repository);
}

/// The hosting link cache in a [PrivateEntryStore].
final class CodedHostingLinkCacheRepository
    implements HostingLinkCacheRepository {
  CodedHostingLinkCacheRepository(this._store);

  final PrivateEntryStore _store;

  @override
  Future<HostingLinkCacheEntry?> read(NativePathIdentity repository) async {
    final bytes = await _store.read(repository);
    if (bytes == null) return null;
    final decoded = decodeHostingLinks(bytes);
    // Another schema or damaged data; the links are looked up again.
    if (decoded == null) unawaited(_store.remove(repository));
    return decoded;
  }

  @override
  Future<void> write(
    NativePathIdentity repository,
    HostingLinkCacheEntry entry,
  ) => _store.write(repository, encodeHostingLinks(entry));

  @override
  Future<void> remove(NativePathIdentity repository) =>
      _store.remove(repository);
}
