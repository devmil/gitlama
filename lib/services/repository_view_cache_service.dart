import 'dart:async';

import '../models/history.dart';
import '../models/repository_state.dart';
import '../models/repository_view_cache.dart';
import '../models/settings.dart';
import '../repositories/repository_view_cache_repository.dart';

/// Remembers what each repository showed, so that opening it again presents
/// that at once while the repository loads.
///
/// Entries live in memory for tab changes and in private storage for the next
/// start. Storage is best effort in both directions: an entry that is absent,
/// unreadable or of another schema simply means the repository loads as usual.
///
/// Remote workspaces are not cached here: their paths may equal local ones and
/// fetched remote content never reaches the disk.
final class RepositoryViewCacheService {
  RepositoryViewCacheService(
    this._repository, {
    this.persistDelay = const Duration(seconds: 2),
  });

  /// Entries kept in memory, matching the bound of the private storage.
  static const capacity = 32;

  final RepositoryViewCacheRepository _repository;
  final Duration persistDelay;
  final Map<NativePathIdentity, RepositoryViewCacheEntry> _entries = {};
  final Map<NativePathIdentity, Timer> _pending = {};
  final Set<Future<void>> _writes = {};
  var _disposed = false;

  RepositoryViewCacheEntry? entry(NativePathIdentity repository) =>
      repository.isRemote ? null : _entries[repository];

  /// Reads the stored entries of [repositories] that are not in memory yet.
  /// Never throws; a repository without a usable entry loads as usual.
  Future<void> warm(Iterable<NativePathIdentity> repositories) => Future.wait([
    for (final repository in repositories.toSet())
      if (!repository.isRemote && !_entries.containsKey(repository))
        _read(repository),
  ]);

  Future<void> _read(NativePathIdentity repository) async {
    try {
      final decoded = await _repository.read(repository);
      if (decoded == null || _disposed) return;
      // What this session has learned meanwhile is newer than the storage.
      _entries.putIfAbsent(repository, () => decoded);
      _trim();
    } on Object {
      // The cache must never stand between a person and their repository.
    }
  }

  /// Keeps the references and status of a loaded [snapshot].
  void rememberSnapshot(
    NativePathIdentity repository,
    RepositorySnapshot snapshot,
  ) {
    if (_disposed ||
        repository.isRemote ||
        snapshot.phase != RepositoryPhase.ready ||
        snapshot.failure != null ||
        snapshot.refsFailure != null ||
        snapshot.statusFailure != null) {
      return;
    }
    final known = _entries[repository];
    if (known != null &&
        identical(known.refs, snapshot.refs) &&
        identical(known.status, snapshot.status)) {
      return;
    }
    _store(
      repository,
      (known ?? const RepositoryViewCacheEntry()).withSnapshot(snapshot),
    );
  }

  /// Keeps a complete first [page] of the history and its branch filter.
  void rememberHistory(NativePathIdentity repository, HistoryPage page) {
    if (_disposed || repository.isRemote || !isCacheableHistoryPage(page)) {
      return;
    }
    _store(
      repository,
      (_entries[repository] ?? const RepositoryViewCacheEntry()).withHistory(
        cacheableHistoryPage(page),
      ),
    );
  }

  void forget(NativePathIdentity repository) {
    if (repository.isRemote) return;
    _entries.remove(repository);
    _pending.remove(repository)?.cancel();
    if (!_disposed) _track(_repository.remove(repository));
  }

  void _store(NativePathIdentity repository, RepositoryViewCacheEntry entry) {
    // Reinsert so that the map keeps its most recently used entries last.
    _entries
      ..remove(repository)
      ..[repository] = entry;
    _trim();
    _pending.remove(repository)?.cancel();
    _pending[repository] = Timer(persistDelay, () {
      _pending.remove(repository);
      _track(_write(repository));
    });
  }

  void _trim() {
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  Future<void> _write(NativePathIdentity repository) async {
    final entry = _entries[repository];
    if (entry == null || entry.isEmpty) return;
    try {
      await _repository.write(repository, entry);
    } on Object {
      // The next change writes again.
    }
  }

  void _track(Future<void> write) {
    late final Future<void> tracked;
    tracked = write.whenComplete(() => _writes.remove(tracked));
    _writes.add(tracked);
  }

  /// Writes every changed entry now.
  Future<void> flush() async {
    final repositories = _pending.keys.toList();
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    for (final repository in repositories) {
      _track(_write(repository));
    }
    await Future.wait(_writes.toList());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await flush();
    _disposed = true;
    _entries.clear();
  }
}
