import '../../models/commit_archive.dart';
import '../../repositories/commit_archive_repository.dart';
import 'session_scope.dart';

/// Zip snapshots of the active repository's commits.
final class CommitArchiveCommands {
  CommitArchiveCommands(this._repository, this._scope);

  final CommitArchiveRepositorySessionRepository _repository;
  final SessionScope _scope;

  /// Saves the snapshot of [commit], with every file under the folder
  /// [prefix], to [destination] on this computer.
  Future<CommitArchiveStatus> save({
    required String commit,
    required String prefix,
    required String destination,
    required void Function(CommitArchiveStatus status) onProgress,
    required bool Function() isCanceled,
  }) => _repository.saveCommitArchive(
    _scope.requireCurrent(),
    commit: commit,
    prefix: prefix,
    destination: destination,
    onProgress: onProgress,
    isCanceled: isCanceled,
  );
}
