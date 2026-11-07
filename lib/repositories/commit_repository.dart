import '../models/commit.dart';
import '../models/repository_state.dart';

/// Commits made from the Composer.
abstract interface class CommitRepository {
  Future<CommitTools> commitTools(RepositorySessionIdentity identity);

  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  );

  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  );
}
