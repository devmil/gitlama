import '../../models/conflict.dart';
import '../../models/repository_state.dart';
import '../../repositories/conflict_repository.dart';
import 'session_scope.dart';

/// Resolving the conflicts of a paused merge, rebase, cherry-pick or revert
/// in the session they were loaded from.
final class ConflictCommands {
  ConflictCommands(this._repository, this._scope);

  final ConflictRepositorySessionRepository _repository;
  final SessionScope _scope;

  /// The session whose conflicts were loaded last; resolutions act on it.
  RepositorySessionIdentity? _identity;

  Future<ConflictSnapshot> load() async {
    final identity = _scope.requireCurrent();
    final snapshot = await _repository.loadConflicts(identity);
    _identity = identity;
    return snapshot;
  }

  Future<ConflictSnapshot> saveResult(ConflictFile file, List<int> result) =>
      _withIdentity(
        (identity) => _repository.saveConflictResult(
          identity,
          file.path,
          file.fingerprint,
          result,
        ),
      );

  Future<ConflictSnapshot> chooseSide(
    ConflictFile file,
    ConflictSideChoice choice,
  ) => _withIdentity(
    (identity) => _repository.chooseConflictSide(
      identity,
      file.path,
      file.fingerprint,
      choice,
    ),
  );

  Future<ConflictSnapshot> takeRegion(
    ConflictFile file,
    int regionIndex,
    ConflictRegionChoice choice,
  ) => _withIdentity(
    (identity) => _repository.takeConflictRegion(
      identity,
      file.path,
      file.fingerprint,
      regionIndex,
      choice,
    ),
  );

  Future<ConflictSnapshot> undoResolution(List<int> path) => _withIdentity(
    (identity) => _repository.undoConflictResolution(identity, path),
  );

  Future<ConflictContinuationResult> continueOperation(
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) async {
    final identity = _identity;
    if (identity == null || !_scope.isOpen(identity)) {
      throw const ConflictException(ConflictFailureCode.noActiveOperation);
    }
    final result = await _repository.continueConflictOperation(
      identity,
      action,
      mergeMessage: mergeMessage,
    );
    if (result.state == ConflictContinuationState.completed ||
        result.state == ConflictContinuationState.aborted) {
      _identity = null;
    }
    return result;
  }

  /// Forgets the loaded conflicts of a closed [session].
  void forgetSession(RepositorySessionIdentity session) {
    if (_identity == session) _identity = null;
  }

  Future<ConflictSnapshot> _withIdentity(
    Future<ConflictSnapshot> Function(RepositorySessionIdentity identity)
    operation,
  ) async {
    final identity = _identity;
    if (identity == null || !_scope.isOpen(identity)) {
      throw const ConflictException(ConflictFailureCode.noActiveOperation);
    }
    final result = await operation(identity);
    await _scope.refreshIfOpen(identity);
    return result;
  }
}
