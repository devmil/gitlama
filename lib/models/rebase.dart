enum RebaseAction { pick, reword, edit, squash, fixup, drop }

enum RebaseFailureCode {
  invalidRequest,
  emptyPlan,
  invalidPlan,
  dirtyWorktree,
  detachedHead,
  activeOperation,
  publicationConfirmationRequired,
  stale,
  canceled,
  failed,
  read,
  unsupported,
}

enum RebaseExecutionState {
  completed,
  conflict,
  editStop,
  interrupted,
  stale,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class RebaseInstruction {
  const RebaseInstruction({
    required this.id,
    required this.action,
    required this.oid,
    required this.subject,
    required this.published,
    this.replacementMessage,
    this.autosquashBaseId,
  });

  final BigInt id;
  final RebaseAction action;
  final String oid;
  final List<int> subject;
  final bool published;
  final List<int>? replacementMessage;
  final BigInt? autosquashBaseId;

  RebaseInstruction copyWith({
    RebaseAction? action,
    List<int>? replacementMessage,
    bool clearReplacementMessage = false,
    BigInt? autosquashBaseId,
  }) => RebaseInstruction(
    id: id,
    action: action ?? this.action,
    oid: oid,
    subject: subject,
    published: published,
    replacementMessage: clearReplacementMessage
        ? null
        : replacementMessage ?? this.replacementMessage,
    autosquashBaseId: autosquashBaseId ?? this.autosquashBaseId,
  );
}

final class RebasePlan {
  const RebasePlan({
    required this.token,
    required this.onto,
    required this.currentBranch,
    required this.currentHead,
    required this.instructions,
    required this.publishedCount,
    required this.activityIds,
    this.ontoName,
  });

  final BigInt token;
  final String onto;
  final List<int>? ontoName;
  final List<int> currentBranch;
  final String currentHead;
  final List<RebaseInstruction> instructions;
  final int publishedCount;
  final List<String> activityIds;
}

final class RebasePreview {
  const RebasePreview({
    required this.token,
    required this.arguments,
    required this.todo,
    required this.instructionCount,
    required this.publishedCount,
    required this.instructions,
    required this.autosquashApplied,
  });

  final BigInt token;
  final List<String> arguments;
  final List<int> todo;
  final int instructionCount;
  final int publishedCount;
  final List<RebaseInstruction> instructions;
  final int autosquashApplied;
}

final class RebaseExecutionResult {
  const RebaseExecutionResult({
    required this.state,
    required this.activityIds,
    required this.conflictingPaths,
    this.failure,
    this.runningInstruction,
  });

  final RebaseExecutionState state;
  final RebaseFailureCode? failure;
  final List<String> activityIds;
  final List<List<int>> conflictingPaths;
  final List<int>? runningInstruction;
}

final class RebaseException implements Exception {
  const RebaseException(this.code);

  final RebaseFailureCode code;
}

/// What the interactive rebase editor returns: the edited plan and the
/// acknowledgements it asked for.
typedef RebaseEditResult = ({
  List<RebaseInstruction> instructions,
  bool acknowledgePublishedHistory,
  bool applyAutosquash,
});
