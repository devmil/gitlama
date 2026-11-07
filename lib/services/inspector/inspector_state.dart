import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../models/repository_state.dart';

enum InspectorPhase { empty, loading, ready, failed }

/// The loaded entries of one folder of the All files tree.
final class InspectorTreeDirectory {
  const InspectorTreeDirectory({
    this.entries = const [],
    this.nextOffset,
    this.loading = false,
    this.failed = false,
  });

  final List<CommitTreeEntry> entries;
  final int? nextOffset;
  final bool loading;
  final bool failed;
}

/// Key of a folder in [InspectorState.tree]: one character per path byte, so
/// distinct byte paths never share a key. The root is the empty string.
String inspectorTreeKey(List<int>? directory) =>
    directory == null ? '' : String.fromCharCodes(directory);

/// Everything an inspector shows. Content not belonging to the location's
/// lens is null.
final class InspectorState {
  const InspectorState({
    this.location,
    this.phase = InspectorPhase.empty,
    this.failureCode,
    this.inspection,
    this.diff,
    this.contentLoading = false,
    this.contentFailureCode,
    this.fileBytes,
    this.blame,
    this.history,
    this.rangeHistory,
    this.historyLoadingMore = false,
    this.historyMoreFailed = false,
    this.historyEntry,
    this.tree = const {},
    this.expanded = const {},
    this.lensAvailability = const {},
    this.canBack = false,
    this.canForward = false,
    this.backLocations = const [],
    this.forwardLocations = const [],
  });

  final InspectorLocation? location;
  final InspectorPhase phase;

  /// Why the target could not be loaded.
  final RepositoryFailureCode? failureCode;

  /// The target's commit detail and changed files.
  final CommitInspection? inspection;

  /// The diff on screen: the target's, or the selected history entry's.
  final InspectorDiff? diff;

  /// The lens content is loading while the target stays shown.
  final bool contentLoading;

  /// Why the lens content could not be loaded.
  final RepositoryFailureCode? contentFailureCode;
  final List<int>? fileBytes;

  /// The first blame page; later pages come from the service.
  final BlamePage? blame;
  final PathHistoryPage? history;
  final RangeHistoryResult? rangeHistory;
  final bool historyLoadingMore;
  final bool historyMoreFailed;

  /// The commit detail of the selected history entry.
  final CommitInspection? historyEntry;

  /// Loaded folders of the All files tree, by [inspectorTreeKey].
  final Map<String, InspectorTreeDirectory> tree;

  /// Expanded folders of the All files tree, by [inspectorTreeKey].
  final Set<String> expanded;
  final Map<InspectorLens, LensUnavailableReason?> lensAvailability;
  final bool canBack;
  final bool canForward;

  /// Earlier locations, newest first.
  final List<InspectorLocation> backLocations;

  /// Later locations, nearest first.
  final List<InspectorLocation> forwardLocations;

  InspectorTarget? get target => location?.target;

  InspectorState copyWith({
    InspectorLocation? location,
    InspectorPhase? phase,
    RepositoryFailureCode? failureCode,
    bool clearFailure = false,
    CommitInspection? inspection,
    InspectorDiff? diff,
    bool clearDiff = false,
    bool? contentLoading,
    RepositoryFailureCode? contentFailureCode,
    bool clearContentFailure = false,
    List<int>? fileBytes,
    bool clearFileBytes = false,
    BlamePage? blame,
    bool clearBlame = false,
    PathHistoryPage? history,
    bool clearHistory = false,
    RangeHistoryResult? rangeHistory,
    bool clearRangeHistory = false,
    bool? historyLoadingMore,
    bool? historyMoreFailed,
    CommitInspection? historyEntry,
    bool clearHistoryEntry = false,
    Map<String, InspectorTreeDirectory>? tree,
    Set<String>? expanded,
    Map<InspectorLens, LensUnavailableReason?>? lensAvailability,
    bool? canBack,
    bool? canForward,
    List<InspectorLocation>? backLocations,
    List<InspectorLocation>? forwardLocations,
  }) => InspectorState(
    location: location ?? this.location,
    phase: phase ?? this.phase,
    failureCode: clearFailure ? null : failureCode ?? this.failureCode,
    inspection: inspection ?? this.inspection,
    diff: clearDiff ? null : diff ?? this.diff,
    contentLoading: contentLoading ?? this.contentLoading,
    contentFailureCode: clearContentFailure
        ? null
        : contentFailureCode ?? this.contentFailureCode,
    fileBytes: clearFileBytes ? null : fileBytes ?? this.fileBytes,
    blame: clearBlame ? null : blame ?? this.blame,
    history: clearHistory ? null : history ?? this.history,
    rangeHistory: clearRangeHistory ? null : rangeHistory ?? this.rangeHistory,
    historyLoadingMore: historyLoadingMore ?? this.historyLoadingMore,
    historyMoreFailed: historyMoreFailed ?? this.historyMoreFailed,
    historyEntry: clearHistoryEntry ? null : historyEntry ?? this.historyEntry,
    tree: tree ?? this.tree,
    expanded: expanded ?? this.expanded,
    lensAvailability: lensAvailability ?? this.lensAvailability,
    canBack: canBack ?? this.canBack,
    canForward: canForward ?? this.canForward,
    backLocations: backLocations ?? this.backLocations,
    forwardLocations: forwardLocations ?? this.forwardLocations,
  );
}
