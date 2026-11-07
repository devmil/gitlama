import 'history.dart';
import 'repository_state.dart';

/// What a repository showed when it was last open: enough to present it
/// again at once while the repository itself loads.
///
/// The entry is disposable. It is never the source of truth, and any entry
/// that cannot be decoded is treated as absent.
final class RepositoryViewCacheEntry {
  const RepositoryViewCacheEntry({
    this.refs,
    this.refCounts,
    this.status,
    this.history,
  });

  final RepositoryRefs? refs;
  final RepositoryRefCounts? refCounts;
  final RepositoryStatus? status;

  /// The first page of the history last shown, without selection. It names
  /// the branch filter it was shown under and stands in only for that one.
  final HistoryPage? history;

  bool get isEmpty => refs == null && status == null && history == null;

  RepositoryViewCacheEntry withSnapshot(RepositorySnapshot snapshot) =>
      RepositoryViewCacheEntry(
        refs: snapshot.refs,
        refCounts: snapshot.refCounts,
        status: snapshot.status,
        history: history,
      );

  RepositoryViewCacheEntry withHistory(HistoryPage page) =>
      RepositoryViewCacheEntry(
        refs: refs,
        refCounts: refCounts,
        status: status,
        history: page,
      );
}

/// The request identity of a history page presented from the cache. Native
/// request identities start at one, so no native read accepts this one.
final BigInt cachedHistoryRequestId = BigInt.zero;

/// Whether [page] may stand in later for the first page of the history
/// under the same branch filter.
bool isCacheableHistoryPage(HistoryPage page) =>
    page.complete &&
    page.offset == 0 &&
    !page.queryActive &&
    page.acceptedQuery.isEmpty &&
    page.collapsedCommits == 0 &&
    page.rows.isNotEmpty;

/// [page] as the cache keeps it: no selection, lighting or reveal, which
/// belong to the session that produced them.
HistoryPage cacheableHistoryPage(HistoryPage page) => HistoryPage(
  requestId: cachedHistoryRequestId,
  complete: false,
  totalRows: page.totalRows,
  offset: 0,
  rows: [
    for (final row in page.rows)
      HistoryTopologyRow(
        objectId: row.objectId,
        parents: row.parents,
        refs: row.refs,
        refCount: row.refCount,
        refsTruncated: row.refsTruncated,
        lane: row.lane,
        shape: row.shape,
        subject: row.subject,
        author: row.author,
        avatarHash: row.avatarHash,
        authorTime: row.authorTime,
        metadataFailure: row.metadataFailure,
        current: row.current,
        wipChangedFiles: row.wipChangedFiles,
        wipStagedFiles: row.wipStagedFiles,
      ),
  ],
  segments: page.segments,
  laneCount: page.laneCount,
  payloadBytes: 0,
  currentObjectId: page.currentObjectId,
  branchFilter: page.branchFilter,
  otherRefs: page.otherRefs,
);
