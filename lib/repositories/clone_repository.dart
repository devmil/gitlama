import '../models/clone_attempt.dart';

abstract interface class CloneRepository {
  Future<CloneAttemptSnapshot> create({
    required String source,
    required String destination,
    String? initialBranch,
    required int generation,
  });

  Future<CloneRunCompletion> run(CloneAttemptSnapshot attempt);

  Future<CloneRunCompletion> runWithCredentials(
    CloneAttemptSnapshot attempt, {
    String? username,
    String? password,
    String? token,
  });

  Future<HostKeyChallenge> probeHostKey(CloneAttemptSnapshot attempt);

  Future<void> acceptHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  );

  Future<void> rejectHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  );

  Future<CloneRunCompletion> runWithHostKey(CloneAttemptSnapshot attempt);

  Future<CloneAttemptSnapshot> retry(
    CloneAttemptSnapshot attempt, {
    String? destination,
  });

  Future<CloneAttemptSnapshot> snapshot(CloneAttemptSnapshot attempt);

  Future<void> cancel(CloneAttemptSnapshot attempt);

  Future<void> dismiss(CloneAttemptSnapshot attempt);
}
