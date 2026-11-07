import 'dart:async';

import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../models/remote_inspection.dart';
import '../models/remote_workspace.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';
import '../repositories/remote_inspection_host_repository.dart';

final _log = AppLogger('RemoteInspectionHost');

/// One window's session on a connection.
final class _WindowSession {
  _WindowSession({
    required this.window,
    required this.authority,
    required this.reads,
    required this.generation,
  });

  final String window;
  final RemoteAuthority authority;

  /// The connection the session was opened on. A reconnect is a new
  /// connection, on which the session does not exist.
  final RemoteDetachedReads reads;
  final BigInt generation;
}

/// Lets inspector windows inspect repositories on a remote host through the
/// main window's connections, which another window cannot reach.
///
/// Each window gets read-only sessions of its own, independent of the tabs.
/// Only the inspector's reads ([remoteInspectionReadMethods]) are forwarded;
/// nothing else, and no write, reaches the host. A window's sessions close
/// when it asks, when the window closes, when the connection that served
/// them is gone, and when the main window shuts down.
final class RemoteInspectionHostService implements RemoteInspectionServer {
  RemoteInspectionHostService(this._repository, this._connections);

  final RemoteInspectionHostRepository _repository;

  /// The live connections' detached reads, as the composition root reads
  /// them from the connections the remote workspace service publishes.
  final RemoteConnectionReads _connections;

  final Map<BigInt, _WindowSession> _sessions = {};
  StreamSubscription<Set<String>>? _windows;
  bool _disposed = false;

  /// The number of sessions windows hold.
  int get sessionCount => _sessions.length;

  Future<void> initialize() async {
    try {
      _windows = _repository.openWindows.listen(_closeWindowsExcept);
      await _repository.serve(this);
    } on Object catch (error) {
      // The main window still works; only remote inspector windows cannot
      // reach their host.
      _log.warning('remote_inspection_host_unavailable', {
        'error_type': LogField(error.runtimeType, LogSensitivity.diagnostic),
      });
    }
  }

  @override
  Future<Object?> open(
    String window,
    NativePathIdentity repository,
    BigInt generation,
  ) async {
    _checkOpen();
    final authority = repository.remote;
    if (authority == null || !repository.isValidLocation || window.isEmpty) {
      throw _failure(RepositoryFailureCode.invalidOptions);
    }
    _dropDisconnected();
    final reads = _connections(authority);
    if (reads == null) {
      throw _failure(RepositoryFailureCode.remoteDisconnected);
    }
    final held = _sessions.values.where((entry) => entry.window == window);
    if (held.length >= remoteInspectionSessionsPerWindow ||
        _sessions.length >= remoteInspectionSessionsTotal) {
      throw _failure(RepositoryFailureCode.capacity);
    }
    final opened = await reads.open(repository.units, generation);
    final session = opened.session;
    if (session == null) return opened.result;
    if (_disposed || _connections(authority) != reads) {
      // The main window or the connection went away while it opened.
      await _closeQuietly(reads, session, generation);
      throw _failure(
        _disposed
            ? RepositoryFailureCode.closed
            : RepositoryFailureCode.remoteDisconnected,
      );
    }
    _sessions[session] = _WindowSession(
      window: window,
      authority: authority,
      reads: reads,
      generation: generation,
    );
    _log.info('remote_inspection_session_opened');
    return opened.result;
  }

  @override
  Future<Object?> read(
    String window,
    BigInt session,
    String method,
    Map<String, Object?> arguments,
  ) async {
    _checkOpen();
    final entry = _sessions[session];
    if (entry == null || entry.window != window) {
      throw _failure(RepositoryFailureCode.unknownSession);
    }
    if (!remoteInspectionReadMethods.contains(method)) {
      throw _failure(RepositoryFailureCode.remoteNotOffered);
    }
    if (_connections(entry.authority) != entry.reads) {
      _sessions.remove(session);
      throw _failure(RepositoryFailureCode.remoteDisconnected);
    }
    final result = await entry.reads.read(session, method, arguments);
    // A session closed while it read answers nothing more.
    if (_sessions[session] != entry) {
      throw _failure(RepositoryFailureCode.closed);
    }
    return result;
  }

  @override
  Future<void> close(String window, BigInt session, BigInt generation) async {
    final entry = _sessions[session];
    if (entry == null || entry.window != window) return;
    _sessions.remove(session);
    await _closeQuietly(entry.reads, session, entry.generation);
  }

  /// Closes the sessions of windows that are no longer open.
  void _closeWindowsExcept(Set<String> open) {
    final gone = [
      for (final MapEntry(:key, :value) in _sessions.entries)
        if (!open.contains(value.window)) key,
    ];
    for (final session in gone) {
      final entry = _sessions.remove(session)!;
      unawaited(_closeQuietly(entry.reads, session, entry.generation));
    }
    if (gone.isNotEmpty) {
      _log.info('remote_inspection_window_sessions_closed', {
        'count': LogField(gone.length, LogSensitivity.diagnostic),
      });
    }
  }

  /// Forgets sessions whose connection is gone; the helper ended them with
  /// it.
  void _dropDisconnected() => _sessions.removeWhere(
    (_, entry) => _connections(entry.authority) != entry.reads,
  );

  Future<void> _closeQuietly(
    RemoteDetachedReads reads,
    BigInt session,
    BigInt generation,
  ) async {
    try {
      await reads.close(session, generation);
    } on Object {
      // The helper ends its sessions with the connection either way.
    }
  }

  void _checkOpen() {
    if (_disposed) throw _failure(RepositoryFailureCode.closed);
  }

  static RepositorySessionException _failure(RepositoryFailureCode code) =>
      RepositorySessionException(RepositoryFailure(code));

  /// Stops serving windows and closes every session they hold.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _windows?.cancel();
    } on Object {
      // Closing the sessions matters more.
    }
    try {
      await _repository.dispose();
    } on Object {
      // The engine is going away.
    }
    final open = Map.of(_sessions);
    _sessions.clear();
    for (final MapEntry(:key, :value) in open.entries) {
      await _closeQuietly(value.reads, key, value.generation);
    }
  }
}
