import 'hosting.dart';
import 'reference_name.dart';
import 'repository_state.dart';

/// Local refs whose configured remote upstream currently has the same
/// target, by full name.
Map<String, String> alignedHistoryUpstreams(RepositoryRefs refs) {
  final remoteTargets = <ReferenceName, String>{
    for (final remote in refs.remotes)
      for (final branch in remote.branches)
        remoteBranchReference(remote, branch): branch.target,
  };
  final aligned = <String, String>{};
  for (final branch in refs.branches) {
    final upstream = upstreamOf(branch);
    if (upstream == null || upstream.kind != ReferenceKind.remoteBranch) {
      continue;
    }
    if (remoteTargets[upstream] != branch.target) continue;
    aligned[branchReference(branch).fullText] = upstream.fullText;
  }
  return aligned;
}

enum HistoryNodeShape {
  commit,
  merge,
  boundary,
  graft,
  replace,
  wip,
  wipConflict,
  stash,
}

const historyWorktreeObjectId = 'wip';

enum HistorySegmentKind {
  straight,
  join,
  merge,
  octopus,
  boundary,
  missing,
  collapsedMerge,
}

final class HistoryGraphSegment {
  const HistoryGraphSegment({
    required this.fromLane,
    required this.toLane,
    required this.kind,
    this.startsAtTop = false,
    this.endsAtCenter = false,
    this.lit,
  });

  final int fromLane;
  final int toLane;
  final HistorySegmentKind kind;
  final bool startsAtTop;
  final bool endsAtCenter;
  final bool? lit;
}

final class HistoryRowGeometry {
  const HistoryRowGeometry({
    required this.metadataLeft,
    required this.graphClipRight,
    required this.contentStart,
    required this.contentAvailable,
  });

  final double metadataLeft;
  final double graphClipRight;
  final double contentStart;
  final double contentAvailable;
}

/// The pull request opened from the branch a history reference names: an
/// open one, or else the latest merged one.
final class HistoryReferencePullRequest {
  const HistoryReferencePullRequest({
    required this.number,
    required this.title,
    required this.webUrl,
    this.draft = false,
    this.merged = false,
    this.checks = HostingCheckState.unknown,
    this.mergeability = HostingMergeability.unknown,
    this.outdated = false,
  });

  final int number;
  final String title;
  final String webUrl;
  final bool draft;
  final bool merged;

  /// The CI result of the pull request's head, where the provider reports it.
  final HostingCheckState checks;

  /// Whether the open pull request merges without conflicts, where the
  /// provider reports it.
  final HostingMergeability mergeability;

  /// The pull request's head is at none of its branch's refs, so the chip
  /// stands on the ref the provider branch was last fetched to.
  final bool outdated;
}

final class HistoryGraphRow {
  const HistoryGraphRow({
    required this.objectId,
    required this.lane,
    required this.shape,
    required this.segments,
    required this.geometry,
    this.subject = const [],
    this.author = const [],
    this.avatarHash = '',
    this.refs = const [],
    this.refCount = 0,
    this.authorTime = 0,
    this.lit = false,
    this.selected = false,
    this.compared = false,
    this.searchMatch = false,
    this.current = false,
    this.wipChangedFiles = 0,
    this.wipStagedFiles = 0,
    this.pullRequests = const {},
    this.branchChecks = const {},
  });

  final String objectId;
  final int lane;
  final HistoryNodeShape shape;
  final List<HistoryGraphSegment> segments;
  final HistoryRowGeometry geometry;
  final List<int> subject;
  final List<int> author;
  final String avatarHash;
  final List<List<int>> refs;
  final int refCount;
  final int authorTime;
  final bool lit;
  final bool selected;

  /// The commit belongs to one side of a two-commit comparison only.
  final bool compared;
  final bool searchMatch;
  final bool current;
  final int wipChangedFiles;
  final int wipStagedFiles;

  /// Pull requests by the full name of the reference whose branch they come
  /// from.
  final Map<String, HistoryReferencePullRequest> pullRequests;

  /// The CI result of a branch without a pull request, such as the bound
  /// remote's main branch, by the full name of its reference.
  final Map<String, HostingCheckState> branchChecks;
}
