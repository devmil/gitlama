enum PowerFailureCode {
  invalidRequest,
  busy,
  canceled,
  timedOut,
  stale,
  git,
  read,
  tooLarge,
}

final class PowerToolsException implements Exception {
  const PowerToolsException(this.code);
  final PowerFailureCode code;
}

enum PowerJobState { pending, completed, failed, canceled }

enum SearchCompleteness { complete, commitLimitReached, resultLimitReached }

enum DiffSearchScope { allRefs, currentBranch }

final class DiffContentMatch {
  const DiffContentMatch({required this.commit, required this.summary});
  final String commit;
  final String summary;
}

final class DiffContentSearchResult {
  const DiffContentSearchResult({
    required this.state,
    required this.matches,
    required this.examinedCommits,
    required this.activityIds,
    this.completeness,
    this.failure,
  });
  final PowerJobState state;
  final List<DiffContentMatch> matches;
  final int examinedCommits;
  final SearchCompleteness? completeness;
  final List<String> activityIds;
  final PowerFailureCode? failure;
}

final class RepositoryStatisticsResult {
  const RepositoryStatisticsResult({
    required this.state,
    required this.commitCount,
    required this.localBranchCount,
    required this.tagCount,
    required this.changedPathCount,
    required this.incomplete,
    required this.activityIds,
    this.failure,
  });
  final PowerJobState state;
  final int commitCount;
  final int localBranchCount;
  final int tagCount;
  final int changedPathCount;
  final bool incomplete;
  final List<String> activityIds;
  final PowerFailureCode? failure;
}

enum BisectMark { good, bad, skip }

final class BisectTimelineEntry {
  const BisectTimelineEntry({required this.revision, required this.mark});
  final String revision;
  final BisectMark mark;
}

final class BisectState {
  const BisectState({
    required this.active,
    required this.timeline,
    this.current,
    this.originalHead,
    this.remainingSteps,
    this.nextStepSummary,
  });
  final bool active;
  final String? current;
  final String? originalHead;
  final List<BisectTimelineEntry> timeline;
  final int? remainingSteps;
  final String? nextStepSummary;
}

enum BisectAction { start, good, bad, skip, reset }

final class BisectPreview {
  const BisectPreview({
    required this.token,
    required this.action,
    required this.arguments,
  });
  final BigInt token;
  final BisectAction action;
  final List<String> arguments;
}

enum BisectExecutionState {
  completed,
  stale,
  failed,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class BisectExecutionResult {
  const BisectExecutionResult({
    required this.state,
    this.bisect,
    this.activityId,
    this.failure,
  });
  final BisectExecutionState state;
  final BisectState? bisect;
  final String? activityId;
  final PowerFailureCode? failure;
}
