import 'dart:async';

import '../../models/history.dart';
import '../../models/inspector.dart';
import '../history_service.dart';
import '../inspector/inspector_service.dart';

/// Keeps the History Detail inspector on the graph's selection, and the
/// graph on what the inspector reaches by Back, Forward or a link.
final class HistoryInspectorLink {
  HistoryInspectorLink(this._history, this._inspector) {
    _selections = _history.selections.listen(_inspectSelection);
    _targets = _inspector.targetShown.listen(_selectInspected);
  }

  final HistoryService _history;
  final InspectorService _inspector;
  late final StreamSubscription<HistorySelection> _selections;
  late final StreamSubscription<InspectorTarget> _targets;

  void _inspectSelection(HistorySelection selection) {
    // The graph following the inspector does not show its selection again.
    // The origin travels with the selection, so a selection the user makes
    // meanwhile is still inspected.
    if (selection.origin == HistorySelectionOrigin.inspector) return;
    final identity = _history.identity;
    final commit = selection.commit;
    if (identity == null || commit == null) {
      _inspector.detach();
      if (identity != null) _inspector.attach(identity);
      return;
    }
    _inspector.attach(identity);
    final base = selection.base;
    unawaited(
      _inspector.navigate(
        InspectorLocation(
          target: base == null
              ? CommitTarget(commit)
              : ComparisonTarget(base: base, commit: commit),
        ),
        fromHost: true,
        parentHint: base == null ? selection.parents : null,
      ),
    );
  }

  /// Selects what the inspector reached without showing it again.
  Future<void> _selectInspected(InspectorTarget target) async {
    const origin = HistorySelectionOrigin.inspector;
    try {
      switch (target) {
        case ComparisonTarget(:final base, :final commit):
          await _history.select(
            base,
            reveal: true,
            focus: false,
            origin: origin,
          );
          await _history.select(
            commit,
            toggle: true,
            focus: false,
            origin: origin,
          );
        case CommitTarget(:final commit):
          await _history.select(
            commit,
            reveal: true,
            focus: false,
            origin: origin,
          );
      }
    } on Object {
      // The graph keeps its selection when the commit is not loaded.
    }
  }

  /// Stops following. Not awaited: a broadcast subscription's cancel future
  /// belongs to the root zone, and nothing is pending behind it.
  void dispose() {
    unawaited(_selections.cancel());
    unawaited(_targets.cancel());
  }
}
