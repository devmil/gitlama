/// One Git lock file (`*.lock`) in the repository's Git directories. Git
/// creates it while it rewrites the file it protects and removes it when done;
/// a lock that stays behind blocks other Git operations.
final class RepositoryLock {
  const RepositoryLock({
    required this.token,
    required this.path,
    required this.worktreeScoped,
    required this.sizeBytes,
    this.age,
  });

  /// Removes this lock while it is the inspected file.
  final BigInt token;

  /// Relative to its Git directory, such as `refs/heads/main.lock`.
  final String path;

  /// Lives in this worktree's own Git directory rather than the shared one.
  final bool worktreeScoped;
  final int sizeBytes;

  /// How long ago Git took the lock, when the filesystem reports it.
  final Duration? age;
}

/// The lock files one inspection found.
final class RepositoryLockInspection {
  const RepositoryLockInspection({required this.locks, this.truncated = false});

  final List<RepositoryLock> locks;

  /// The inspection stopped at its bound; more locks may exist.
  final bool truncated;
}
