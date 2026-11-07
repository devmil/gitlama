import 'dart:async';

import '../../models/history.dart';
import '../../models/history_graph.dart';
import '../../models/repository_state.dart';
import '../repository_session_service.dart';

/// What a transfer changed, once its effect shows: the toolbar's Sync
/// control and History's arrival animation follow [sequence].
final class SyncChange {
  const SyncChange({
    this.sequence = 0,
    this.changed = false,
    this.previousRows = const {},
    this.previousHistoryRequestId,
  });

  /// Increments with each transfer whose effect showed.
  final int sequence;

  /// Whether any transfer in this window has changed the repository.
  final bool changed;

  /// The History rows before the last such transfer.
  final Set<String> previousRows;
  final BigInt? previousHistoryRequestId;
}

/// The state of the active tab before a transfer, compared with what the
/// repository and its History show afterwards.
final class SyncBaseline {
  const SyncBaseline({
    required this.tabId,
    required this.revision,
    required this.ahead,
    required this.behind,
    required this.head,
    required this.rows,
    required this.historyRequestId,
    required this.remoteTargets,
  });

  final int tabId;
  final BigInt revision;
  final BigInt ahead;
  final BigInt behind;
  final String? head;
  final Set<String> rows;
  final BigInt? historyRequestId;
  final Set<String> remoteTargets;
}

/// The one owner of the sync-change baseline: it captures the active tab
/// before a transfer and tells when the snapshot or History shows its
/// effect.
final class SyncChangeTracker {
  SyncChangeTracker(this._repositories) {
    _subscriptions = [
      _repositories.workspaceStates.listen((_) => _check()),
      _repositories.states.listen((_) => _check()),
      _repositories.history.states.listen((_) => _check()),
    ];
  }

  final RepositorySessionService _repositories;
  late final List<StreamSubscription<Object?>> _subscriptions;
  final StreamController<SyncChange> _changes =
      StreamController<SyncChange>.broadcast(sync: true);
  SyncBaseline? _pending;
  var _current = const SyncChange();
  var _disposed = false;

  SyncChange get current => _current;
  Stream<SyncChange> get changes => _changes.stream;

  /// The active tab as it is now, or null when it shows no status.
  SyncBaseline? capture() {
    final tab = _repositories.activeTab;
    final snapshot = tab?.session?.snapshot;
    final status = snapshot?.status;
    if (tab == null || snapshot == null || status == null) return null;
    final page = _repositories.history.current.page;
    return SyncBaseline(
      tabId: tab.id,
      revision: snapshot.revision,
      ahead: status.ahead,
      behind: status.behind,
      head: status.headObjectId,
      rows: {
        for (final row in page?.rows ?? const <HistoryTopologyRow>[])
          row.objectId,
      },
      historyRequestId: page?.requestId,
      remoteTargets: remoteTargets(snapshot),
    );
  }

  /// Watches for the effect of a transfer that started from [baseline].
  void expect(SyncBaseline baseline) {
    _pending = baseline;
    _check();
  }

  void _check() {
    final pending = _pending;
    if (pending == null || _disposed) return;
    final active = _repositories.activeTab;
    if (active == null || active.id != pending.tabId) {
      _pending = null;
      return;
    }
    final snapshot = active.session?.snapshot;
    final status = snapshot?.status;
    if (snapshot == null || status == null) return;
    final page = _repositories.history.current.page;
    final changed =
        status.ahead != pending.ahead ||
        status.behind != pending.behind ||
        status.headObjectId != pending.head ||
        !_sameTargets(remoteTargets(snapshot), pending.remoteTargets) ||
        (page?.rows.any(
              (row) =>
                  row.objectId != historyWorktreeObjectId &&
                  !pending.rows.contains(row.objectId),
            ) ??
            false);
    if (!changed) {
      if (snapshot.revision > pending.revision) _pending = null;
      return;
    }
    _pending = null;
    _current = SyncChange(
      sequence: _current.sequence + 1,
      changed: true,
      previousRows: pending.rows,
      previousHistoryRequestId: pending.historyRequestId,
    );
    _changes.add(_current);
  }

  /// Every remote-tracking branch with its target, as comparable keys.
  static Set<String> remoteTargets(RepositorySnapshot snapshot) => {
    for (final remote in snapshot.refs.remotes)
      for (final branch in remote.branches)
        '${remote.name.join(',')}/${branch.name.join(',')}:${branch.target}',
  };

  static bool _sameTargets(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> dispose() async {
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }
}
