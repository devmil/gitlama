import '../../models/diff.dart';
import '../../models/history.dart';
import '../../models/inspector.dart';
import '../../models/patch.dart';

/// Decides what a patch contains, from where the user asked for it. The
/// window only chooses the destination.
abstract final class PatchRequestBuilder {
  /// A patch of what History shows: the compared commits, the one selected
  /// commit, the selected commits as a range (oldest first) or, with nothing
  /// selected, the working tree. [commit] names one commit instead.
  static PatchRequestFactory history(HistoryPage? page, {String? commit}) {
    final comparisonOld = commit == null ? page?.comparisonOldObjectId : null;
    final comparisonNew = commit == null ? page?.comparisonNewObjectId : null;
    var single = commit;
    var range = const <String>[];
    if (commit == null && (comparisonOld == null || comparisonNew == null)) {
      final selected = page?.selectedObjectIds ?? const <String>[];
      if (selected.length == 1) {
        single = selected.single;
      } else if (selected.length > 1) {
        final selectedSet = selected.toSet();
        final visible =
            page?.rows
                .where((row) => selectedSet.contains(row.objectId))
                .map((row) => row.objectId)
                .toList(growable: false) ??
            selected;
        range = visible.reversed.toList(growable: false);
      }
    }
    return (destination, overwrite) => PatchExportRequest(
      comparisonOld: comparisonOld,
      comparisonNew: comparisonNew,
      rangeCommits: range,
      commit: single,
      workspaceDefault:
          comparisonOld == null &&
          comparisonNew == null &&
          range.isEmpty &&
          single == null,
      destinationDirectory: destination,
      overwrite: overwrite,
    );
  }

  /// A patch of the commit or comparison whose diff is on screen, limited
  /// to [paths] when the diff shows one file.
  static PatchRequestFactory diff(
    InspectorTarget target,
    List<List<int>> paths,
  ) {
    final base = target.base;
    final comparison = base != null;
    return (destination, overwrite) => PatchExportRequest(
      comparisonOld: base,
      comparisonNew: comparison ? target.commit : null,
      commit: comparison ? null : target.commit,
      historyPaths: paths,
      destinationDirectory: destination,
      overwrite: overwrite,
    );
  }

  /// A patch of working-tree changes: the chosen lines of the diff
  /// [accepted] (its [rowIds]), the [paths] selected on [side], or, with
  /// neither, everything on [side].
  static PatchRequestFactory workingTree({
    required StagingSide side,
    List<List<int>> paths = const [],
    DiffPage? accepted,
    List<String> rowIds = const [],
  }) =>
      (destination, overwrite) => PatchExportRequest(
        workingDiffRequestId: accepted?.requestId,
        rowIds: rowIds,
        selectedSide: paths.isEmpty ? null : PatchSide.of(side),
        selectedPaths: paths,
        focusedSide: accepted == null && paths.isEmpty
            ? PatchSide.of(side)
            : null,
        destinationDirectory: destination,
        overwrite: overwrite,
      );

  /// A patch of exactly [paths] on [side].
  static PatchRequestFactory files(StagingSide side, List<List<int>> paths) =>
      (destination, overwrite) => PatchExportRequest(
        selectedSide: PatchSide.of(side),
        selectedPaths: paths,
        destinationDirectory: destination,
        overwrite: overwrite,
      );
}
