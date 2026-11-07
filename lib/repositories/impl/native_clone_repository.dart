import '../../models/activity.dart';
import '../../models/clone_attempt.dart';
import '../../rust/api.dart' as native_api;
import '../../rust/third_party/gitlama_contract/clone.dart' as native;
import '../../rust/third_party/gitlama_contract/dto.dart' as native;
import '../clone_repository.dart';
import 'native_mappers.dart';
import 'native_enum_mappers.g.dart';

final class NativeCloneRepository implements CloneRepository {
  @override
  Future<CloneAttemptSnapshot> create({
    required String source,
    required String destination,
    String? initialBranch,
    required int generation,
  }) async {
    final result = await native_api.repositoryCloneCreate(
      source: source,
      destination: destination,
      initialBranch: initialBranch,
      generation: BigInt.from(generation),
    );
    _throwFailure(result.failure);
    return _requireSnapshot(result.snapshot);
  }

  @override
  Future<CloneRunCompletion> run(CloneAttemptSnapshot attempt) async {
    final result = await native_api.repositoryCloneRun(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
    );
    _throwFailure(result.failure);
    return _completion(result);
  }

  @override
  Future<CloneRunCompletion> runWithCredentials(
    CloneAttemptSnapshot attempt, {
    String? username,
    String? password,
    String? token,
  }) async {
    final result = await native_api.repositoryCloneRunWithCredentials(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
      username: username,
      password: password,
      token: token,
    );
    _throwFailure(result.failure);
    return _completion(result);
  }

  @override
  Future<HostKeyChallenge> probeHostKey(CloneAttemptSnapshot attempt) async {
    final result = await native_api.repositoryCloneProbeHostKey(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
    );
    _throwFailure(result.failure);
    final challenge = result.challenge;
    if (challenge == null) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.hostKeyProbeFailed),
      );
    }
    return _challenge(challenge);
  }

  @override
  Future<void> acceptHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) async {
    final result = await native_api.repositoryCloneAcceptHostKey(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
      challengeId: challenge.challengeId,
    );
    _throwFailure(result.failure);
  }

  @override
  Future<void> rejectHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) async {
    final result = await native_api.repositoryCloneRejectHostKey(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
      challengeId: challenge.challengeId,
    );
    _throwFailure(result.failure);
  }

  @override
  Future<CloneRunCompletion> runWithHostKey(
    CloneAttemptSnapshot attempt,
  ) async {
    final result = await native_api.repositoryCloneRunWithHostKey(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
    );
    _throwFailure(result.failure);
    return _completion(result);
  }

  CloneRunCompletion _completion(native.NativeCloneRunResult result) {
    return CloneRunCompletion(
      snapshot: _requireSnapshot(result.snapshot),
      openedSession: result.session == null
          ? null
          : repositorySessionFromNative(result.session!),
    );
  }

  @override
  Future<CloneAttemptSnapshot> retry(
    CloneAttemptSnapshot attempt, {
    String? destination,
  }) async {
    final result = destination == null
        ? await native_api.repositoryCloneRetry(
            attemptId: attempt.attemptId,
            generation: BigInt.from(attempt.generation),
          )
        : await native_api.repositoryCloneRetryAtDestination(
            attemptId: attempt.attemptId,
            generation: BigInt.from(attempt.generation),
            destination: destination,
          );
    _throwFailure(result.failure);
    return _requireSnapshot(result.snapshot);
  }

  @override
  Future<CloneAttemptSnapshot> snapshot(CloneAttemptSnapshot attempt) async {
    final result = await native_api.repositoryCloneSnapshot(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
    );
    _throwFailure(result.failure);
    return _requireSnapshot(result.snapshot);
  }

  @override
  Future<void> cancel(CloneAttemptSnapshot attempt) async {
    final result = await native_api.repositoryCloneCancel(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
    );
    _throwFailure(result.failure);
    if (!result.accepted) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.invalidAttemptState),
      );
    }
  }

  @override
  Future<void> dismiss(CloneAttemptSnapshot attempt) async {
    final result = await native_api.repositoryCloneDismiss(
      attemptId: attempt.attemptId,
      generation: BigInt.from(attempt.generation),
    );
    _throwFailure(result.failure);
    if (!result.accepted) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.invalidAttemptState),
      );
    }
  }

  CloneAttemptSnapshot _requireSnapshot(native.NativeCloneSnapshot? snapshot) {
    if (snapshot == null) {
      throw const CloneException(CloneFailure(CloneFailureCode.git));
    }
    return CloneAttemptSnapshot(
      attemptId: snapshot.attemptId,
      generation: snapshot.generation.toInt(),
      phase: snapshot.state.toModel(),
      failure: snapshot.failure == null
          ? null
          : CloneFailure(snapshot.failure!.kind.toModel()),
      partialDestination: snapshot.partialDestination,
      progress: switch (snapshot.progress) {
        final progress? => ActivityProgress(
          phase: progress.phase,
          completed: progress.completed,
          total: progress.total,
          unit: progress.unit,
        ),
        null => null,
      },
      hostKeyChallenge: snapshot.hostKeyChallenge == null
          ? null
          : _challenge(snapshot.hostKeyChallenge!),
    );
  }

  HostKeyChallenge _challenge(native.NativeHostKeyChallenge challenge) =>
      HostKeyChallenge(
        challengeId: challenge.challengeId,
        host: challenge.host,
        port: challenge.port,
        algorithm: challenge.algorithm,
        fingerprint: challenge.fingerprint,
      );

  Never _throw(native.NativeCloneFailure failure) =>
      throw CloneException(CloneFailure(failure.kind.toModel()));

  void _throwFailure(native.NativeCloneFailure? failure) {
    if (failure != null) _throw(failure);
  }
}
