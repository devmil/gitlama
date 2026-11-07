enum RepositoryDropPhase { entered, exited, dropped }

final class RepositoryDropEvent {
  const RepositoryDropEvent._({
    required this.phase,
    this.directories = const [],
    this.rejectedItems = 0,
  });

  const RepositoryDropEvent.entered()
    : this._(phase: RepositoryDropPhase.entered);

  const RepositoryDropEvent.exited()
    : this._(phase: RepositoryDropPhase.exited);

  const RepositoryDropEvent.dropped({
    required List<String> directories,
    required int rejectedItems,
  }) : this._(
         phase: RepositoryDropPhase.dropped,
         directories: directories,
         rejectedItems: rejectedItems,
       );

  final RepositoryDropPhase phase;

  /// Native directory paths retained only long enough to open the repositories.
  final List<String> directories;
  final int rejectedItems;
}

final class RepositoryDropOutcome {
  const RepositoryDropOutcome({
    required this.openedRepositories,
    required this.rejectedItems,
    required this.failedDirectories,
  });

  final int openedRepositories;
  final int rejectedItems;
  final int failedDirectories;
}
