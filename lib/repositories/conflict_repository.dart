import '../models/conflict.dart';
import '../models/repository_state.dart';

abstract interface class ConflictRepositorySessionRepository {
  Future<ConflictSnapshot> loadConflicts(RepositorySessionIdentity identity);

  Future<ConflictSnapshot> saveConflictResult(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    List<int> result,
  );

  Future<ConflictSnapshot> chooseConflictSide(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    ConflictSideChoice choice,
  );

  Future<ConflictSnapshot> takeConflictRegion(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    int regionIndex,
    ConflictRegionChoice choice,
  );

  Future<ConflictSnapshot> undoConflictResolution(
    RepositorySessionIdentity identity,
    List<int> path,
  );

  Future<ConflictContinuationResult> continueConflictOperation(
    RepositorySessionIdentity identity,
    ConflictSequencerAction action, {
    String? mergeMessage,
  });
}
