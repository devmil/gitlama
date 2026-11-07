import 'history_graph.dart';
import 'remote_contract.g.dart';

enum HistoryLoadPhase { loading, preview, complete, empty, failed }

enum HistoryMetadataFailure {
  missing,
  objectTooLarge,
  authorTooLarge,
  subjectTooLarge,
  malformedCommit,
}

final class HistoryTopologyRow {
  const HistoryTopologyRow({
    required this.objectId,
    required this.parents,
    required this.refs,
    this.refCount = 0,
    this.refsTruncated = false,
    required this.lane,
    required this.shape,
    this.subject = const [],
    this.author = const [],
    this.avatarHash = '',
    this.authorTime = 0,
    this.metadataFailure,
    this.selected = false,
    this.lit = false,
    this.compared = false,
    this.current = false,
    this.wipChangedFiles = 0,
    this.wipStagedFiles = 0,
  });

  final String objectId;
  final List<String> parents;
  final List<List<int>> refs;
  final int refCount;
  final bool refsTruncated;
  final int lane;
  final int shape;
  final List<int> subject;
  final List<int> author;
  final String avatarHash;
  final int authorTime;
  final HistoryMetadataFailure? metadataFailure;
  final bool selected;
  final bool lit;

  /// The commit belongs to one side of a two-commit comparison only.
  final bool compared;
  final bool current;
  final int wipChangedFiles;
  final int wipStagedFiles;

  bool get isWorktree => objectId == historyWorktreeObjectId;

  bool get hasMetadata =>
      subject.isNotEmpty || author.isNotEmpty || metadataFailure != null;

  HistoryTopologyRow withMetadata(HistoryMetadata value) => HistoryTopologyRow(
    objectId: objectId,
    parents: parents,
    refs: refs,
    refCount: refCount,
    refsTruncated: refsTruncated,
    lane: lane,
    shape: shape,
    subject: value.subject,
    author: value.author,
    avatarHash: value.avatarHash,
    authorTime: value.authorTime,
    metadataFailure: value.failure,
    selected: selected,
    lit: lit,
    compared: compared,
    current: current,
    wipChangedFiles: wipChangedFiles,
    wipStagedFiles: wipStagedFiles,
  );
}

final class HistoryMetadata {
  const HistoryMetadata({
    required this.objectId,
    this.subject = const [],
    this.author = const [],
    this.avatarHash = '',
    this.authorTime = 0,
    this.failure,
  });

  final String objectId;
  final List<int> subject;
  final List<int> author;
  final String avatarHash;
  final int authorTime;
  final HistoryMetadataFailure? failure;
}

final class HistoryPage {
  const HistoryPage({
    required this.requestId,
    required this.complete,
    required this.totalRows,
    required this.offset,
    required this.rows,
    this.segments = const [],
    required this.laneCount,
    required this.payloadBytes,
    this.lightingActive = false,
    this.currentObjectId,
    this.selectedObjectIds = const [],
    this.focusedObjectId,
    this.comparisonOldObjectId,
    this.comparisonNewObjectId,
    this.revealSequence = 0,
    this.revealObjectId,
    this.revealIndex,
    this.querySequence = 0,
    this.queryActive = false,
    this.acceptedQuery = '',
    this.branchFilter = HistoryBranchFilter.none,
    this.selectedFilteredOut = false,
    this.collapsedCommits = 0,
    this.otherRefs = false,
  });

  final BigInt requestId;
  final bool complete;
  final int totalRows;
  final int offset;
  final List<HistoryTopologyRow> rows;
  final List<HistoryTopologySegment> segments;
  final int laneCount;
  final int payloadBytes;
  final bool lightingActive;
  final String? currentObjectId;
  final List<String> selectedObjectIds;
  final String? focusedObjectId;
  final String? comparisonOldObjectId;
  final String? comparisonNewObjectId;
  final int revealSequence;
  final String? revealObjectId;
  final int? revealIndex;
  final int querySequence;
  final bool queryActive;
  final String acceptedQuery;

  /// The branches this view shows; [HistoryBranchFilter.none] shows all.
  final HistoryBranchFilter branchFilter;
  final bool selectedFilteredOut;
  final int collapsedCommits;

  /// Whether this history includes commits only references outside
  /// branches, remote branches, tags and the stash reach.
  final bool otherRefs;
}

final class HistoryQuery {
  const HistoryQuery({
    this.text = '',
    this.searchHash = true,
    this.searchMessage = true,
    this.searchAuthor = true,
    this.searchPath = false,
  });

  final String text;
  final bool searchHash;
  final bool searchMessage;
  final bool searchAuthor;
  final bool searchPath;

  bool get active => text.isNotEmpty;
}

/// The branches the history graph shows: every commit reachable from any of
/// [references] (full names such as `refs/heads/main`). The empty filter shows
/// every reference.
final class HistoryBranchFilter {
  HistoryBranchFilter(Iterable<String> references)
    : references = List.unmodifiable(references.toSet().toList()..sort());

  const HistoryBranchFilter._empty() : references = const [];

  static const none = HistoryBranchFilter._empty();

  /// The most references one filter may name (native bound).
  static const maximumReferences = ContractLimits.branchFilterReferences;

  /// Sorted and distinct.
  final List<String> references;

  bool get isEmpty => references.isEmpty;
  bool get isNotEmpty => references.isNotEmpty;
  int get length => references.length;

  /// Whether [reference] is shown alone or with only its [upstream], as
  /// after [focus].
  bool isFocusedOn(String reference, {String? upstream}) =>
      contains(reference) &&
      references.every((value) => value == reference || value == upstream);

  bool contains(String reference) => references.contains(reference);

  /// Shows only [reference] and the [upstream] it tracks.
  static HistoryBranchFilter focus(String reference, {String? upstream}) =>
      HistoryBranchFilter([reference, ?upstream]);

  /// Adds [reference] when absent, together with the [upstream] it tracks;
  /// otherwise removes [reference] and leaves the upstream to be removed on
  /// its own. Adding beyond [maximumReferences] leaves the filter unchanged,
  /// and an upstream is left out when only [reference] still fits.
  HistoryBranchFilter toggled(String reference, {String? upstream}) {
    if (contains(reference)) {
      final remaining = [
        for (final value in references)
          if (value != reference) value,
      ];
      return remaining.isEmpty ? none : HistoryBranchFilter(remaining);
    }
    if (references.length >= maximumReferences) return this;
    return HistoryBranchFilter([
      ...references,
      reference,
      if (upstream != null &&
          !contains(upstream) &&
          references.length + 1 < maximumReferences)
        upstream,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryBranchFilter &&
      other.references.length == references.length &&
      Iterable<int>.generate(
        references.length,
      ).every((index) => other.references[index] == references[index]);

  @override
  int get hashCode => Object.hashAll(references);
}

final class HistoryTopologySegment {
  const HistoryTopologySegment({
    required this.fromObjectId,
    required this.toObjectId,
    required this.parentOrdinal,
    required this.fromLane,
    required this.toLane,
    required this.kind,
    this.fromRow,
    this.toRow,
    this.lit,
  });

  /// Absolute endpoint positions let a page render edges with unloaded endpoints.
  final int? fromRow;
  final int? toRow;
  final bool? lit;
  final String fromObjectId;
  final String toObjectId;
  final int parentOrdinal;
  final int fromLane;
  final int toLane;
  final int kind;
}

final class HistoryState {
  const HistoryState({
    required this.phase,
    this.page,
    this.failureCode,
    this.targetObjectId,
    this.pendingQuery,
    this.queryFailureCode,
    this.targetNotShown = false,
  });

  final HistoryLoadPhase phase;
  final HistoryPage? page;
  final String? failureCode;

  /// The commit the graph selected for inspection: the single selection, or
  /// the newer side of a comparison.
  final String? targetObjectId;

  /// Whether [targetObjectId] was asked to be shown but is not part of the
  /// loaded history, for example because only other references reach it.
  final bool targetNotShown;
  final HistoryQuery? pendingQuery;
  final String? queryFailureCode;
}

/// What the graph selected for inspection: one commit, an ordered pair, or
/// nothing.
/// Who chose a History selection.
enum HistorySelectionOrigin {
  /// The user or the workspace, in the graph or through a command.
  graph,

  /// The inspector, which already shows it; it is not inspected again.
  inspector,
}

final class HistorySelection {
  const HistorySelection({
    this.commit,
    this.base,
    this.parents,
    this.origin = HistorySelectionOrigin.graph,
  });

  /// Who made this selection.
  final HistorySelectionOrigin origin;

  /// The selected commit, or the newer side of a comparison.
  final String? commit;

  /// The older side of a comparison.
  final String? base;

  /// The selected commit's parents as the graph knows them.
  final List<String>? parents;
}

enum ReflogAction {
  inspectCommit,
  createBranch,
  createTag,
  resetCurrentBranch,
  cherryPick,
}

final class ReflogEntry {
  const ReflogEntry({
    required this.id,
    required this.reference,
    required this.commit,
    required this.recordedAtUnixSeconds,
    required this.timezone,
    required this.summary,
    required this.actorName,
    required this.actorEmail,
    required this.actions,
  });

  final String id;
  final List<int> reference;
  final String commit;
  final int recordedAtUnixSeconds;
  final List<int> timezone;
  final List<int> summary;
  final List<int> actorName;
  final List<int> actorEmail;
  final Set<ReflogAction> actions;
}

final class ReflogPage {
  const ReflogPage({
    required this.entries,
    this.nextOffset,
    this.activityId,
    this.retainedAfterFailure = false,
    this.failureCode,
  });

  final List<ReflogEntry> entries;
  final int? nextOffset;
  final BigInt? activityId;
  final bool retainedAfterFailure;
  final String? failureCode;
}
