import '../models/clone_attempt.dart';
import '../models/repository_state.dart';
import '../models/transfer.dart';

abstract interface class TransferRepositorySessionRepository {
  Future<TransferPreview> previewTransfer(
    RepositorySessionIdentity identity,
    TransferRequest request,
  );

  Future<TransferExecutionResult> executeTransfer(
    RepositorySessionIdentity identity,
    BigInt token, {
    TransferCredentials? credentials,
  });

  /// Runs a previewed fetch that the application started by itself. It never
  /// prompts and is listed as background work.
  Future<TransferExecutionResult> executeBackgroundFetch(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  /// Deletes remote-tracking refs a fetch could not update, each only while
  /// it is unchanged. The next fetch recreates what the remote has.
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity identity,
    List<String> references,
  );

  Future<bool> cancelTransfer(RepositorySessionIdentity identity, BigInt token);

  Future<HostKeyChallenge> probeTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
  );

  Future<void> resolveTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
    HostKeyChallenge challenge, {
    required bool accept,
  });
}
