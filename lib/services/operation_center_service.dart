import 'dart:async';

import '../models/operation_center.dart';
import '../models/repository_state.dart';
import '../models/operation_failure.dart';
import '../repositories/operation_center_repository.dart';

/// Operations that run on other computers, for the operation center to show
/// next to local ones.
abstract interface class RemoteOperationSource {
  /// One snapshot per live remote connection.
  Future<List<OperationCenterSnapshot>> remoteOperations();

  /// Dismisses a finished remote operation.
  Future<void> dismissRemoteOperation(OperationCenterEntry entry);
}

final class OperationCenterService {
  OperationCenterService(this._repository, {this._remote});
  OperationCenterService.empty()
    : _repository = const _EmptyOperationCenterRepository(),
      _remote = null;

  final OperationCenterRepository _repository;
  final RemoteOperationSource? _remote;
  final StreamController<OperationCenterSnapshot> _states =
      StreamController<OperationCenterSnapshot>.broadcast(sync: true);
  final StreamController<void> _polls = StreamController<void>.broadcast(
    sync: true,
  );
  OperationCenterSnapshot _current = OperationCenterSnapshot.empty;
  OperationCenterSnapshot _backend = OperationCenterSnapshot.empty;
  final List<OperationCenterEntry> _userFailures = [];
  int _nextFailure = 0;
  static const userFailureCapacity = 32;
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;

  /// Publishes only when the projection differs from the previous one. An
  /// unchanged poll must not rebuild its listeners.
  Stream<OperationCenterSnapshot> get states => _states.stream;

  /// Fires after every completed poll, including unchanged ones.
  Stream<void> get polls => _polls.stream;
  OperationCenterSnapshot get current => _current;

  Future<void> initialize() async {
    await refresh();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final local = await _repository.snapshot();
      final remote = _remote;
      final next = remote == null
          ? local
          : _merge([local, ...await remote.remoteOperations()]);
      if (!_disposed) {
        _backend = next;
        _publish();
        _polls.add(null);
      }
    } on RepositorySessionException {
      // Preserve the last coherent application-wide projection while a native
      // session is concurrently retiring. The next bounded poll reconciles it.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> dismiss(OperationCenterEntry entry) async {
    if (entry.userFailure case final failure?) {
      _userFailures.removeWhere((entry) => entry.userFailure?.id == failure.id);
      _publish();
      return;
    }
    final remote = _remote;
    if (entry.session?.backend == RepositoryBackendKind.remote &&
        remote != null) {
      await remote.dismissRemoteOperation(entry);
    } else {
      await _repository.dismiss(entry);
    }
    await refresh();
  }

  Future<void> dismissAll() async {
    _userFailures.clear();
    _publish();
    await _repository.dismissAll();
    final remote = _remote;
    if (remote != null) {
      for (final entry in _current.entries) {
        // Like the local dismiss-all: failures and background warnings.
        if (entry.session?.backend == RepositoryBackendKind.remote &&
            (entry.state == OperationCenterState.failed ||
                entry.state == OperationCenterState.warning)) {
          try {
            await remote.dismissRemoteOperation(entry);
          } on Object {
            // A dropped connection keeps its entries until it reconnects.
          }
        }
      }
    }
    await refresh();
  }

  void recordUserFailure(String message, OperationFailureDetails details) {
    if (_disposed) return;
    final id = BigInt.from(-(++_nextFailure));
    final time = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    _userFailures.insert(
      0,
      OperationCenterEntry(
        activityId: id,
        state: OperationCenterState.failed,
        origin: OperationCenterOrigin.user,
        action: OperationCenterAction.other,
        startedAtUnixMs: time,
        finishedAtUnixMs: time,
        canCancel: false,
        canRetry: false,
        hasDetails: true,
        userFailure: UserOperationFailure(
          id: id,
          message: message,
          details: details,
        ),
      ),
    );
    if (_userFailures.length > userFailureCapacity) _userFailures.removeLast();
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    final failures = OperationCenterSnapshot(
      entries: List.unmodifiable(_userFailures),
      runningCount: 0,
      failedCount: _userFailures.length,
      attentionCount: 0,
      truncated: false,
    );
    final next = _userFailures.isEmpty
        ? _backend
        : _merge([_backend, failures]);
    if (!next.sameContent(_current)) {
      _current = next;
      _states.add(next);
    }
  }

  /// One projection of several operation centers, ordered as the native one
  /// orders its own: attention, failures, warnings, running, then finished;
  /// newest first within each.
  static OperationCenterSnapshot _merge(List<OperationCenterSnapshot> parts) {
    if (parts.length == 1) return parts.single;
    int priority(OperationCenterState state) => switch (state) {
      OperationCenterState.attention => 0,
      OperationCenterState.failed => 1,
      OperationCenterState.warning => 2,
      OperationCenterState.running => 3,
      OperationCenterState.succeeded || OperationCenterState.canceled => 4,
    };
    final entries = [for (final part in parts) ...part.entries]
      ..sort((left, right) {
        final byState = priority(left.state).compareTo(priority(right.state));
        if (byState != 0) return byState;
        return right.startedAtUnixMs.compareTo(left.startedAtUnixMs);
      });
    int count(OperationCenterState state) =>
        entries.where((entry) => entry.state == state).length;
    return OperationCenterSnapshot(
      entries: entries,
      runningCount: count(OperationCenterState.running),
      failedCount: count(OperationCenterState.failed),
      warningCount: count(OperationCenterState.warning),
      attentionCount: count(OperationCenterState.attention),
      truncated: parts.any((part) => part.truncated),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _states.close();
    await _polls.close();
  }
}

final class _EmptyOperationCenterRepository
    implements OperationCenterRepository {
  const _EmptyOperationCenterRepository();

  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async =>
      OperationCenterSnapshot.empty;

  @override
  Future<void> dismiss(OperationCenterEntry entry) async {}

  @override
  Future<void> dismissAll() async {}
}
