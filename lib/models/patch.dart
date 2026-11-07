import 'diff.dart';

enum PatchSide {
  unstaged,
  staged;

  /// The patch side that holds the changes of staging [side].
  static PatchSide of(StagingSide side) => switch (side) {
    StagingSide.unstaged => PatchSide.unstaged,
    StagingSide.staged => PatchSide.staged,
  };
}

enum PatchExportScope {
  lines,
  selectedFilesUnstaged,
  selectedFilesStaged,
  unstaged,
  staged,
  head,
  commit,
  range,
  compare,
}

enum PatchFormat { unifiedDiff, formatPatch }

/// Builds the export request once the user chose where the patch goes.
typedef PatchRequestFactory =
    PatchExportRequest Function(String destination, bool overwrite);

final class PatchExportRequest {
  const PatchExportRequest({
    this.workingDiffRequestId,
    this.rowIds = const [],
    this.selectedSide,
    this.selectedPaths = const [],
    this.focusedSide,
    this.comparisonOld,
    this.comparisonNew,
    this.rangeCommits = const [],
    this.commit,
    this.historyPaths = const [],
    this.workspaceDefault = false,
    required this.destinationDirectory,
    this.overwrite = false,
  });

  final BigInt? workingDiffRequestId;
  final List<String> rowIds;
  final PatchSide? selectedSide;
  final List<List<int>> selectedPaths;
  final PatchSide? focusedSide;
  final String? comparisonOld;
  final String? comparisonNew;
  final List<String> rangeCommits;
  final String? commit;

  /// Limits a comparison or commit patch to these paths.
  final List<List<int>> historyPaths;
  final bool workspaceDefault;
  final String destinationDirectory;
  final bool overwrite;

  PatchExportRequest copyWith({bool? overwrite}) => PatchExportRequest(
    workingDiffRequestId: workingDiffRequestId,
    rowIds: rowIds,
    selectedSide: selectedSide,
    selectedPaths: selectedPaths,
    focusedSide: focusedSide,
    comparisonOld: comparisonOld,
    comparisonNew: comparisonNew,
    rangeCommits: rangeCommits,
    commit: commit,
    historyPaths: historyPaths,
    workspaceDefault: workspaceDefault,
    destinationDirectory: destinationDirectory,
    overwrite: overwrite ?? this.overwrite,
  );
}

final class PatchExportPreview {
  const PatchExportPreview({
    required this.token,
    required this.scope,
    required this.format,
    required this.filename,
    required this.destination,
    required this.byteCount,
    required this.requiresOverwrite,
  });

  final BigInt? token;
  final PatchExportScope scope;
  final PatchFormat format;
  final String filename;
  final String destination;
  final int byteCount;
  final bool requiresOverwrite;
}

/// A patch built for a repository on another computer, to be saved on this
/// one.
final class PatchExportContent {
  const PatchExportContent({
    required this.scope,
    required this.format,
    required this.filename,
    required this.bytes,
  });

  final PatchExportScope scope;
  final PatchFormat format;
  final String filename;
  final List<int> bytes;
}

enum PatchExportExecutionState { completed, stale, failed }

final class PatchExportExecutionResult {
  const PatchExportExecutionResult({required this.state, this.destination});

  final PatchExportExecutionState state;
  final String? destination;
}

final class PatchApplyPreview {
  const PatchApplyPreview({
    required this.token,
    required this.paths,
    required this.binary,
    required this.arguments,
  });

  final BigInt token;
  final List<List<int>> paths;
  final bool binary;
  final List<String> arguments;
}

enum PatchApplyExecutionState {
  completed,
  stale,
  failed,
  reconciledWithWarning,
  outcomeUncertain,
}

final class PatchApplyExecutionResult {
  const PatchApplyExecutionResult({required this.state});

  final PatchApplyExecutionState state;
}
