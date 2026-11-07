enum ConflictOperationKind {
  merge,
  rebase,
  cherryPick,
  revert,
  snapshot,
  stash,
  standalone,
}

enum ConflictFileKind { text, binary, huge }

enum ConflictSideChoice { current, incoming }

enum ConflictRegionChoice { current, incoming, both }

/// How a conflicted file was resolved: [deleted], the whole [current] or
/// [incoming] file, a [merged] result, or in an [external] merge tool.
enum ConflictResolutionKind { deleted, current, incoming, merged, external }

enum ConflictSequencerAction { continueOperation, skip, abort }

enum ConflictFailureCode {
  noActiveOperation,
  missingPath,
  invalidRequest,
  stale,
  unresolved,
  tooLarge,
  binary,
  unsupported,
  read,
  write,
  git,
}

enum ConflictContinuationState {
  completed,
  conflict,
  interrupted,
  aborted,
  failed,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class ConflictSide {
  const ConflictSide({
    required this.present,
    required this.byteCount,
    this.mode,
    this.content,
  });

  final bool present;
  final int? mode;
  final List<int>? content;
  final int byteCount;
}

final class ConflictRegion {
  const ConflictRegion({
    required this.index,
    required this.current,
    required this.incoming,
    this.ancestor,
  });

  final int index;
  final List<int> current;
  final List<int> incoming;
  final List<int>? ancestor;
}

final class ConflictFile {
  const ConflictFile({
    required this.path,
    required this.kind,
    required this.ancestor,
    required this.current,
    required this.incoming,
    required this.resultPresent,
    required this.markerFree,
    required this.regions,
    required this.fingerprint,
    required this.canUndoResolution,
    this.result,
    this.resultMode,
  });

  final List<int> path;
  final ConflictFileKind kind;
  final ConflictSide ancestor;
  final ConflictSide current;
  final ConflictSide incoming;
  final List<int>? result;
  final bool resultPresent;
  final int? resultMode;
  final bool markerFree;
  final List<ConflictRegion> regions;
  final BigInt fingerprint;
  final bool canUndoResolution;
}

final class ConflictSnapshot {
  const ConflictSnapshot({
    required this.operation,
    required this.currentLabel,
    required this.incomingLabel,
    required this.files,
    required this.resolvedUndoPaths,
    required this.canContinue,
    required this.canSkip,
    this.currentStep,
    this.totalSteps,
    this.suggestedMessage,
  });

  final ConflictOperationKind operation;
  final List<int> currentLabel;
  final List<int> incomingLabel;
  final int? currentStep;
  final int? totalSteps;
  final String? suggestedMessage;
  final List<ConflictFile> files;
  final List<List<int>> resolvedUndoPaths;
  final bool canContinue;
  final bool canSkip;
}

final class ConflictContinuationResult {
  const ConflictContinuationResult({
    required this.state,
    required this.activityIds,
    this.failure,
  });

  final ConflictContinuationState state;
  final List<String> activityIds;
  final ConflictFailureCode? failure;
}

final class ConflictException implements Exception {
  const ConflictException(this.code);

  final ConflictFailureCode code;
}
