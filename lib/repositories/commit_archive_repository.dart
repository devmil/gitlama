import '../models/commit_archive.dart';
import '../models/repository_state.dart';

abstract interface class CommitArchiveRepositorySessionRepository {
  /// Builds the zip snapshot of [commit] with every file under the top folder
  /// [prefix], on the computer that holds the repository, and writes it to
  /// [destination] on this computer. [onProgress] sees each status while it
  /// is built; [isCanceled] stops it between steps. Completes with the final
  /// status or throws [CommitArchiveException].
  Future<CommitArchiveStatus> saveCommitArchive(
    RepositorySessionIdentity identity, {
    required String commit,
    required String prefix,
    required String destination,
    required void Function(CommitArchiveStatus status) onProgress,
    required bool Function() isCanceled,
  });
}
