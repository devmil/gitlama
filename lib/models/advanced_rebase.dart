enum AdvancedRebaseFailureCode {
  invalidRequest,
  dirtyWorktree,
  detachedHead,
  activeOperation,
  publicationConfirmationRequired,
  stale,
  canceled,
  conflict,
  tooLarge,
  unsupported,
  read,
  git,
}

enum FixupSuggestionState { suggested, ambiguous, noBase, incomplete }

final class FixupEvidence {
  const FixupEvidence({required this.commit, required this.subject, this.path});

  final List<int>? path;
  final String commit;
  final List<int> subject;
}

final class FixupSuggestion {
  const FixupSuggestion({
    required this.state,
    required this.evidence,
    required this.activityIds,
    this.candidate,
    this.subject,
    this.fixupMessage,
    this.squashMessage,
  });

  final FixupSuggestionState state;
  final String? candidate;
  final List<int>? subject;
  final List<int>? fixupMessage;
  final List<int>? squashMessage;
  final List<FixupEvidence> evidence;
  final List<String> activityIds;
}

final class RestackStep {
  const RestackStep({
    required this.id,
    required this.branch,
    required this.expectedHead,
    required this.oldParent,
    required this.newParent,
    required this.expectedNewParentHead,
    required this.published,
  });

  final int id;
  final List<int> branch;
  final String expectedHead;
  final String oldParent;
  final List<int> newParent;
  final String expectedNewParentHead;
  final bool published;
}

final class RestackPlan {
  const RestackPlan({
    required this.token,
    required this.rootBranch,
    required this.steps,
    required this.publishedCount,
    required this.incomplete,
    required this.activityIds,
  });

  final BigInt token;
  final List<int> rootBranch;
  final List<RestackStep> steps;
  final int publishedCount;
  final bool incomplete;
  final List<String> activityIds;
}

enum RestackExecutionState {
  completed,
  conflict,
  partial,
  stale,
  canceled,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class RestackExecutionResult {
  const RestackExecutionResult({
    required this.state,
    required this.completedSteps,
    required this.totalSteps,
    required this.recoveryRefs,
    required this.conflictingPaths,
    required this.activityIds,
    this.currentBranch,
    this.failure,
  });

  final RestackExecutionState state;
  final int completedSteps;
  final int totalSteps;
  final List<int>? currentBranch;
  final List<List<int>> recoveryRefs;
  final List<List<int>> conflictingPaths;
  final List<String> activityIds;
  final AdvancedRebaseFailureCode? failure;
}

final class AdvancedRebaseException implements Exception {
  const AdvancedRebaseException(this.code);

  final AdvancedRebaseFailureCode code;
}
