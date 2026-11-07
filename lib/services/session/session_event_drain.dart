import 'dart:async';

import '../../models/repository_state.dart';

/// The open sessions the drain serves, and whether each is the active tab's.
typedef DrainedSession = ({RepositorySessionIdentity session, bool active});

/// The one scheduler that drains repository session events.
///
/// The native core queues events per session and offers no stream, so the
/// workspace asks for them: the active tab's session on every tick, hidden
/// tabs' sessions on every tenth, since they only feed their tab marker and
/// their next activation. A session is never drained twice at once.
final class SessionEventDrain {
  SessionEventDrain({
    required this._sessions,
    required this._drain,
    this.interval = const Duration(milliseconds: 20),
    this.hiddenEvery = 10,
  });

  final Iterable<DrainedSession> Function() _sessions;
  final Future<void> Function(RepositorySessionIdentity session) _drain;

  /// How often the active session is drained.
  final Duration interval;

  /// Hidden sessions drain on every this many ticks.
  final int hiddenEvery;

  final Set<BigInt> _draining = {};
  Timer? _timer;
  var _tick = 0;
  var _disposed = false;

  bool get running => _timer != null;

  /// Starts draining, when it is not running already.
  void start() {
    if (_disposed) return;
    _timer ??= Timer.periodic(interval, (_) {
      _tick += 1;
      final includeHidden = _tick % hiddenEvery == 0;
      for (final session in _sessions().toList(growable: false)) {
        if (!includeHidden && !session.active) continue;
        unawaited(drainNow(session.session));
      }
    });
  }

  /// Drains [session] once, unless a drain of it is running.
  Future<void> drainNow(RepositorySessionIdentity session) async {
    if (_disposed || !_draining.add(session.nativeId)) return;
    try {
      await _drain(session);
    } finally {
      _draining.remove(session.nativeId);
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
