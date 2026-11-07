import 'package:gitlama/models/history.dart';

/// The rows reachable from [filter]'s references through their parents, in
/// order: the native branch-filter contract.
List<HistoryTopologyRow> branchFilteredRows(
  List<HistoryTopologyRow> rows,
  HistoryBranchFilter filter,
) {
  if (filter.isEmpty) return rows;
  final byId = {for (final row in rows) row.objectId: row};
  final pending = [
    for (final row in rows)
      if (row.refs.any(
        (reference) => filter.contains(String.fromCharCodes(reference)),
      ))
        row.objectId,
  ];
  final reachable = <String>{};
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (!reachable.add(id)) continue;
    pending.addAll(byId[id]?.parents ?? const []);
  }
  return [
    for (final row in rows)
      if (reachable.contains(row.objectId)) row,
  ];
}
