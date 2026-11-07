import '../models/named_snapshot.dart';
import '../models/repository_state.dart';

abstract interface class NamedSnapshotRepositorySessionRepository {
  Future<NamedSnapshotPage> namedSnapshots(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximum = 32,
  });

  Future<NamedSnapshotExecutionResult> createNamedSnapshot(
    RepositorySessionIdentity identity, {
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  });

  Future<NamedSnapshotRestorePreview> previewNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  );

  Future<NamedSnapshotExecutionResult> executeNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<bool> cancelNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<NamedSnapshotExecutionResult> branchFromNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
    List<int> branch,
  );

  Future<NamedSnapshotExecutionResult> deleteNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  );
}
