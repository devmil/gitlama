/// Why a commit's zip snapshot failed.
enum CommitArchiveFailureCode {
  stale,
  invalidRequest,
  missingCommit,
  tooLarge,
  busy,
  git,
  write,
  canceled,
}

enum CommitArchiveState { running, completed, failed, canceled }

/// The progress or result of a commit's zip snapshot.
final class CommitArchiveStatus {
  const CommitArchiveStatus({
    required this.state,
    this.files = 0,
    this.totalFiles = 0,
    this.archiveBytes = 0,
    this.missingSubmodules = const [],
    this.missingSubmoduleCount = 0,
    this.unresolvedLfs = const [],
    this.unresolvedLfsCount = 0,
    this.failure,
  });

  final CommitArchiveState state;

  /// Files written, submodule files included.
  final int files;

  /// Files known so far; grows as submodules are entered.
  final int totalFiles;

  /// The size of the finished zip.
  final int archiveBytes;

  /// Submodules kept as empty folders; a few are named, the count is exact.
  final List<List<int>> missingSubmodules;
  final int missingSubmoduleCount;

  /// LFS files kept as their pointers.
  final List<List<int>> unresolvedLfs;
  final int unresolvedLfsCount;
  final CommitArchiveFailureCode? failure;
}

/// A commit's zip snapshot that failed or was canceled.
final class CommitArchiveException implements Exception {
  const CommitArchiveException(this.code);

  final CommitArchiveFailureCode code;

  @override
  String toString() => 'CommitArchiveException(${code.name})';
}
