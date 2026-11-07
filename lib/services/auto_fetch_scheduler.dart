import 'dart:async';

import '../models/repository_state.dart';
import '../models/settings.dart';
import 'settings_service.dart';

/// A repository the scheduler may fetch: its session, its canonical
/// identity and whether it has remotes to fetch from.
typedef AutoFetchCandidate = ({
  RepositorySessionIdentity session,
  NativePathIdentity canonical,
  bool hasRemotes,
});

/// Runs background fetches at the interval the settings choose, while a
/// repository that wants them is open. Remote repositories never fetch in
/// the background: they would use the host's credentials unasked.
final class AutoFetchScheduler {
  AutoFetchScheduler(
    this._settings, {
    required this._candidates,
    required this._fetch,
  });

  final SettingsService _settings;
  final Iterable<AutoFetchCandidate> Function() _candidates;
  final Future<void> Function(RepositorySessionIdentity session) _fetch;
  StreamSubscription<SettingsDocument>? _changes;
  Timer? _timer;
  int? _minutes;
  var _running = false;
  var _disposed = false;

  bool _wants(AutoFetchCandidate candidate) =>
      !candidate.canonical.isRemote &&
      _settings.current.autoFetches(candidate.canonical);

  /// Starts, retimes or stops the timer for the open repositories.
  void sync() {
    if (_disposed) return;
    _changes ??= _settings.changes.listen((_) => sync());
    final minutes = _settings.current.autoFetch.intervalMinutes;
    if (!_candidates().any(_wants)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null && _minutes == minutes) return;
    _timer?.cancel();
    _minutes = minutes;
    _timer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(run()),
    );
  }

  /// Fetches every open repository that wants it, one after another.
  Future<void> run() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      for (final candidate in _candidates().toList(growable: false)) {
        if (_disposed) return;
        if (!candidate.hasRemotes || !_wants(candidate)) continue;
        await _fetch(candidate.session);
      }
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _changes?.cancel();
  }
}
