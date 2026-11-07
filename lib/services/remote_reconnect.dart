import 'dart:async';

import '../models/remote_workspace.dart';

/// Where automatic reconnection of one host stands.
enum RemoteReconnectPhase {
  /// The next attempt starts at [RemoteReconnectState.nextAttemptAt].
  waiting,

  /// An attempt runs.
  connecting,

  /// Automatic attempts ended; only the user starts the next one.
  stopped,
}

/// Automatic reconnection of one host whose open tabs lost their
/// connection.
final class RemoteReconnectState {
  const RemoteReconnectState({
    required this.profileId,
    required this.phase,
    required this.attempt,
    this.nextAttemptAt,
    this.failure,
    this.gaveUp = false,
  });

  final String profileId;
  final RemoteReconnectPhase phase;

  /// Attempts made since the connection was lost.
  final int attempt;

  /// When the next attempt starts while [phase] is waiting.
  final DateTime? nextAttemptAt;

  /// Why the connection was lost or the last attempt failed.
  final RemoteFailureCode? failure;

  /// Whether automatic attempts ended by themselves, rather than because
  /// the user stopped them or the failure needs the user.
  final bool gaveUp;
}

/// Failures a later attempt can overcome without the user: the network or
/// the host was briefly unreachable. A changed identity, a missing helper or
/// Git, or a refused setup always needs the user.
bool remoteFailureRetriable(RemoteFailureCode? failure) => switch (failure) {
  RemoteFailureCode.disconnected ||
  RemoteFailureCode.timedOut ||
  RemoteFailureCode.sshConnectionFailed ||
  RemoteFailureCode.handshakeTimeout ||
  RemoteFailureCode.bootstrapFailed => true,
  _ => false,
};

/// Reconnects hosts whose open tabs lost their connection, with growing
/// pauses and for a bounded time. Each attempt is a fresh connection: no
/// write is ever resent, and changes stay unavailable until it succeeds.
final class RemoteReconnector {
  RemoteReconnector({
    required this._reconnect,
    required this._wanted,
    Timer Function(Duration delay, void Function() callback)? timer,
    DateTime Function()? now,
    this.delays = defaultDelays,
    this.window = defaultWindow,
  }) : _timer = timer ?? Timer.new,
       _now = now ?? DateTime.now;

  /// Pauses before the attempts after a loss; the last repeats.
  static const defaultDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// How long after a loss automatic attempts continue.
  static const defaultWindow = Duration(minutes: 10);

  final List<Duration> delays;
  final Duration window;
  final Future<RemoteConnectionState?> Function(String) _reconnect;
  final bool Function(String) _wanted;
  final Timer Function(Duration, void Function()) _timer;
  final DateTime Function() _now;

  final Map<String, RemoteReconnectState> _states = {};
  final Map<String, Timer> _timers = {};
  final Map<String, DateTime> _lostAt = {};
  final Map<String, Future<RemoteConnectionState?>> _running = {};
  final _changes = StreamController<String>.broadcast();
  final Set<String> _quiet = {};
  final _reconnected = StreamController<String>.broadcast();
  var _disposed = false;

  /// The state of [profileId]; null while nothing is to be done.
  RemoteReconnectState? stateOf(String profileId) => _states[profileId];

  /// The host of every change; [stateOf] tells its new state.
  Stream<String> get changes => _changes.stream;

  /// Hosts that connected again after their connection was lost. A startup
  /// connection is not announced.
  Stream<String> get reconnected => _reconnected.stream;

  /// The connection of [profileId] was lost with [failure]: reconnect
  /// automatically when the failure allows it and tabs still need the host.
  void lost(String profileId, RemoteFailureCode? failure) {
    if (_disposed || !_wanted(profileId)) return;
    if (_running.containsKey(profileId)) return;
    if (!remoteFailureRetriable(failure)) {
      _stop(profileId, failure: failure);
      return;
    }
    _lostAt[profileId] = _now();
    _schedule(profileId, attempt: 0, failure: failure);
  }

  /// Connects [profileId] now, at startup, without waiting.
  void connectSoon(String profileId) {
    if (_disposed || !_wanted(profileId)) return;
    if (_running.containsKey(profileId) || _states.containsKey(profileId)) {
      return;
    }
    _lostAt[profileId] = _now();
    _quiet.add(profileId);
    _schedule(profileId, attempt: 0, delay: Duration.zero);
  }

  /// An attempt the user asked for. A failure that allows it continues the
  /// automatic attempts, from the start when they had ended.
  Future<RemoteConnectionState?> reconnectNow(String profileId) {
    final running = _running[profileId];
    if (running != null) return running;
    _timers.remove(profileId)?.cancel();
    final previous = _states[profileId];
    final restart =
        previous == null || previous.phase == RemoteReconnectPhase.stopped;
    if (restart) _lostAt[profileId] = _now();
    return _attempt(profileId, restart ? 0 : previous.attempt);
  }

  /// Ends automatic attempts for [profileId] until the user reconnects.
  void stop(String profileId) {
    final state = _states[profileId];
    if (state == null || state.phase == RemoteReconnectPhase.stopped) return;
    _stop(profileId, failure: state.failure);
  }

  /// The host connected or was closed outside an automatic attempt: forget
  /// it. An attempt in progress settles itself.
  void settled(String profileId) {
    if (!_running.containsKey(profileId)) clear(profileId);
  }

  /// The host connected or no longer needs reconnecting: forget it.
  void clear(String profileId) {
    _timers.remove(profileId)?.cancel();
    _lostAt.remove(profileId);
    _quiet.remove(profileId);
    if (_states.remove(profileId) != null && !_disposed) {
      _changes.add(profileId);
    }
  }

  void _publish(RemoteReconnectState state) {
    _states[state.profileId] = state;
    if (!_disposed) _changes.add(state.profileId);
  }

  void _stop(
    String profileId, {
    RemoteFailureCode? failure,
    bool gaveUp = false,
  }) {
    _timers.remove(profileId)?.cancel();
    _publish(
      RemoteReconnectState(
        profileId: profileId,
        phase: RemoteReconnectPhase.stopped,
        attempt: _states[profileId]?.attempt ?? 0,
        failure: failure,
        gaveUp: gaveUp,
      ),
    );
  }

  void _schedule(
    String profileId, {
    required int attempt,
    RemoteFailureCode? failure,
    Duration? delay,
  }) {
    final pause = delay ?? delays[attempt.clamp(0, delays.length - 1)];
    final lostAt = _lostAt[profileId] ?? _now();
    final at = _now().add(pause);
    if (at.difference(lostAt) > window) {
      _stop(profileId, failure: failure, gaveUp: true);
      return;
    }
    _timers.remove(profileId)?.cancel();
    _publish(
      RemoteReconnectState(
        profileId: profileId,
        phase: RemoteReconnectPhase.waiting,
        attempt: attempt,
        nextAttemptAt: at,
        failure: failure,
      ),
    );
    _timers[profileId] = _timer(pause, () {
      _timers.remove(profileId);
      if (_disposed) return;
      if (!_wanted(profileId)) {
        clear(profileId);
        return;
      }
      unawaited(_attempt(profileId, attempt));
    });
  }

  Future<RemoteConnectionState?> _attempt(String profileId, int attempt) {
    final previous = _states[profileId];
    _publish(
      RemoteReconnectState(
        profileId: profileId,
        phase: RemoteReconnectPhase.connecting,
        attempt: attempt + 1,
        failure: previous?.failure,
      ),
    );
    final running = _run(profileId, attempt + 1);
    _running[profileId] = running;
    return running.whenComplete(() => _running.remove(profileId));
  }

  Future<RemoteConnectionState?> _run(String profileId, int attempt) async {
    RemoteConnectionState? result;
    RemoteFailureCode? failure;
    try {
      result = await _reconnect(profileId);
    } on RemoteWorkspaceException catch (error) {
      failure = error.code;
    } on Object {
      failure = RemoteFailureCode.internal;
    }
    if (_disposed) return result;
    if (result != null && result.ready) {
      final announce = !_quiet.contains(profileId);
      clear(profileId);
      if (announce) _reconnected.add(profileId);
      return result;
    }
    // Only the first attempt after startup is quiet; a later one reconnects.
    _quiet.remove(profileId);
    failure ??= result?.failure;
    if (result?.phase == RemoteConnectionPhase.identityChanged ||
        failure == RemoteFailureCode.canceled ||
        !_wanted(profileId)) {
      clear(profileId);
      return result;
    }
    if (!remoteFailureRetriable(failure)) {
      _stop(profileId, failure: failure);
      return result;
    }
    _schedule(profileId, attempt: attempt, failure: failure);
    return result;
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await _changes.close();
    await _reconnected.close();
  }
}
