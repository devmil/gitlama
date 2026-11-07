/// The combined destructive scope shown before spending native preview tokens.
final class DiscardReview {
  const DiscardReview({
    required this.trackedFiles,
    required this.untrackedFiles,
  });

  final int trackedFiles;
  final int untrackedFiles;
  int get fileCount => trackedFiles + untrackedFiles;
  bool get mixed => trackedFiles > 0 && untrackedFiles > 0;
  DiscardKind get kind =>
      trackedFiles == 0 ? DiscardKind.clean : DiscardKind.discard;
}

enum DiscardKind { discard, clean }

enum DiscardScope { files, rows }

final class DiscardRequest {
  const DiscardRequest({
    required this.kind,
    required this.scope,
    this.workingDiffRequestId,
    this.paths = const [],
    this.rowIds = const [],
  });

  final DiscardKind kind;
  final DiscardScope scope;
  final BigInt? workingDiffRequestId;
  final List<List<int>> paths;
  final List<String> rowIds;
}

final class DiscardPreview {
  const DiscardPreview({
    required this.token,
    required this.kind,
    required this.fileCount,
    required this.arguments,
  });

  final BigInt token;
  final DiscardKind kind;
  final int fileCount;
  final List<String> arguments;
}

enum DiscardExecutionState {
  completed,
  stale,
  failed,
  reconciledWithWarning,

  /// Git may have changed the repository, but GitLama could not confirm the
  /// result. The user inspects the repository before trying again.
  outcomeUncertain,
}

final class DiscardExecutionResult {
  const DiscardExecutionResult({required this.state});

  final DiscardExecutionState state;
}
