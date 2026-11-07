import '../models/diff.dart';
import '../models/discard.dart';
import '../models/index_lock.dart';
import '../models/repository_lock.dart';
import '../models/remote_contract.g.dart';
import '../models/repository_state.dart';
import '../models/status_acceleration.dart';

/// The working tree and index of a session: their diffs, staging, discarding
/// and the index lock.
abstract interface class WorkingCopyRepository {
  /// Loads a staged or unstaged projection for viewing and exact patch actions.
  /// A new load supersedes the previous staging request for this session.
  Future<DiffPage> workingDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  });

  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  });

  /// Decodes both image sides of a staged or unstaged working-tree change.
  ///
  /// A null path loads no image for that side.
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  });

  /// Zero request IDs select whole-file status rows under the native mutation
  /// lease. Paths identify selected rows; the shared Git library expands rename
  /// endpoints. Nonzero requests retain their accepted diff preconditions.
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  );

  /// Cheap progress read; never joins the repository's Git read queue.
  Future<StagingPhase?> stagingPhase(RepositorySessionIdentity identity);

  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  );

  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  );

  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  /// Lists the Git lock files of the repository; nothing changes.
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  );

  /// Removes the inspected lock named by [token] while it is unchanged;
  /// completes with false when it was already gone. Throws
  /// [IndexLockException] when it changed or cannot be removed.
  Future<bool> removeRepositoryLock(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  /// Git's status accelerators for the repository and how long its last
  /// status scan took. Changes nothing.
  Future<StatusAcceleration> statusAcceleration(
    RepositorySessionIdentity identity,
  );

  /// Enables the accelerators the repository lacks in its local Git
  /// configuration and completes with the settings now in effect.
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  );
}
