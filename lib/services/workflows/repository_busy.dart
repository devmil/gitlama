import 'dart:async';

import '../../models/history_mutation.dart';
import '../../models/stash.dart';

/// What keeps a repository tab busy, for the window to put into words.
sealed class BusyActivity {
  const BusyActivity();
}

final class CommitCheckoutBusy extends BusyActivity {
  const CommitCheckoutBusy();
}

final class StashBusy extends BusyActivity {
  const StashBusy(this.kind);

  final StashKind kind;
}

final class HistoryMutationBusy extends BusyActivity {
  const HistoryMutationBusy(this.preview);

  final HistoryMutationPreview preview;
}

final class RebaseBusy extends BusyActivity {
  const RebaseBusy({required this.currentBranch, required this.onto});

  final List<int> currentBranch;
  final List<int> onto;
}

final class RestackBusy extends BusyActivity {
  const RestackBusy(this.rootBranch);

  final List<int> rootBranch;
}

final class ConflictPredictionBusy extends BusyActivity {
  const ConflictPredictionBusy();
}

/// A staging, unstaging or discard of the Changes pane. It does not block
/// the repository; it keeps further file actions from overlapping it.
final class ChangesBusy extends BusyActivity {
  const ChangesBusy();
}

/// One operation keeping a repository tab busy.
final class BusyOperation {
  BusyOperation._(this.activity, this.blocking, this._cancel);

  final BusyActivity activity;

  /// Whether the tab waits under a busy overlay while it runs.
  final bool blocking;
  final Future<Object?> Function()? _cancel;
  var _canceling = false;

  /// Whether the user may stop it.
  bool get cancellable => _cancel != null;

  /// Whether a requested cancellation is under way.
  bool get canceling => _canceling;
}

/// The one owner of which repository tabs are busy and with what. Blocking
/// operations put their tab under an overlay while the other tabs stay
/// usable; non-blocking ones only keep overlapping work out.
final class RepositoryBusyService {
  final Map<int, List<BusyOperation>> _operations = {};
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  var _disposed = false;

  /// Fires whenever an operation starts, ends or begins canceling.
  Stream<void> get changes => _changes.stream;

  /// The latest blocking operation of [tabId], if any.
  BusyOperation? blockingOf(int? tabId) =>
      _operations[tabId]?.where((operation) => operation.blocking).lastOrNull;

  /// Whether [tabId] waits under a blocking operation.
  bool isBlocked(int? tabId) => blockingOf(tabId) != null;

  /// Whether [tabId] runs any operation, blocking or not.
  bool isBusy(int? tabId) => _operations[tabId]?.isNotEmpty ?? false;

  /// Runs [operation] while [tabId] is busy with [activity]. [cancel] offers
  /// to stop it. Without a tab the operation simply runs.
  Future<T> run<T>(
    int? tabId,
    BusyActivity activity,
    Future<T> Function() operation, {
    Future<Object?> Function()? cancel,
    bool blocking = true,
  }) async {
    if (tabId == null) return operation();
    final entry = BusyOperation._(activity, blocking, cancel);
    (_operations[tabId] ??= []).add(entry);
    _notify();
    try {
      return await operation();
    } finally {
      final list = _operations[tabId];
      list?.remove(entry);
      if (list != null && list.isEmpty) _operations.remove(tabId);
      _notify();
    }
  }

  /// Asks [operation] to stop; a second request while it stops is ignored.
  Future<void> cancel(BusyOperation operation) async {
    final cancel = operation._cancel;
    if (cancel == null || operation._canceling) return;
    operation._canceling = true;
    _notify();
    await cancel();
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _changes.close();
  }
}
