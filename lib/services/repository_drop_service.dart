import 'dart:async';

import '../models/repository_drop.dart';
import '../models/repository_state.dart';
import '../repositories/repository_drop_repository.dart';
import 'repository_opener.dart';

abstract interface class RepositoryDropController {
  Stream<bool> get dragStates;
  Stream<RepositoryDropOutcome> get outcomes;
  bool get dragging;
}

/// A window that accepts no dropped folders.
final class DisabledRepositoryDrops implements RepositoryDropController {
  const DisabledRepositoryDrops();

  @override
  Stream<bool> get dragStates => const Stream.empty();

  @override
  Stream<RepositoryDropOutcome> get outcomes => const Stream.empty();

  @override
  bool get dragging => false;
}

final class RepositoryDropService implements RepositoryDropController {
  RepositoryDropService(this._repository, this._sessions);

  final RepositoryDropRepository _repository;
  final RepositoryOpener _sessions;
  final StreamController<bool> _dragStates = StreamController<bool>.broadcast(
    sync: true,
  );
  final StreamController<RepositoryDropOutcome> _outcomes =
      StreamController<RepositoryDropOutcome>.broadcast(sync: true);
  StreamSubscription<RepositoryDropEvent>? _subscription;
  Future<void> _openQueue = Future.value();
  var _dragging = false;
  var _initialized = false;
  var _disposed = false;

  @override
  Stream<bool> get dragStates => _dragStates.stream;

  @override
  Stream<RepositoryDropOutcome> get outcomes => _outcomes.stream;

  @override
  bool get dragging => _dragging;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _subscription = _repository.events.listen(_handle);
    try {
      await _repository.initialize();
      _initialized = true;
    } on Object {
      await _subscription?.cancel();
      _subscription = null;
      await _repository.dispose();
      rethrow;
    }
  }

  void _handle(RepositoryDropEvent event) {
    switch (event.phase) {
      case RepositoryDropPhase.entered:
        _setDragging(true);
      case RepositoryDropPhase.exited:
        _setDragging(false);
      case RepositoryDropPhase.dropped:
        _setDragging(false);
        _openQueue = _openQueue.then((_) => _open(event));
    }
  }

  void _setDragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    if (!_dragStates.isClosed) _dragStates.add(value);
  }

  Future<void> _open(RepositoryDropEvent event) async {
    var opened = 0;
    var failed = 0;
    for (final directory in event.directories) {
      try {
        await _sessions.open(directory);
        opened += 1;
      } on RepositorySessionException {
        failed += 1;
      }
    }
    if (!_outcomes.isClosed) {
      _outcomes.add(
        RepositoryDropOutcome(
          openedRepositories: opened,
          rejectedItems: event.rejectedItems,
          failedDirectories: failed,
        ),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _repository.dispose();
    await _openQueue;
    await _dragStates.close();
    await _outcomes.close();
  }
}
