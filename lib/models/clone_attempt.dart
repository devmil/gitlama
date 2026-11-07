import 'activity.dart';
import 'repository_state.dart';

enum CloneAttemptPhase { pending, running, succeeded, failed, canceled }

enum CloneFailureCode {
  invalidSource,
  embeddedCredential,
  invalidDestination,
  destinationOccupied,
  attemptCapacity,
  unknownAttempt,
  invalidAttemptState,
  missingGit,
  authentication,
  credentialBrokerUnavailable,
  hostKey,
  git,
  timedOut,
  canceled,
  discovery,
  hostKeyProbeFailed,
  hostKeyChallengeExpired,
  hostKeyWriteFailed,
}

final class HostKeyChallenge {
  const HostKeyChallenge({
    required this.challengeId,
    required this.host,
    required this.port,
    required this.algorithm,
    required this.fingerprint,
  });

  final BigInt challengeId;
  final String host;
  final int port;
  final String algorithm;
  final String fingerprint;
}

final class CloneFailure {
  const CloneFailure(this.code);
  final CloneFailureCode code;
}

final class CloneAttemptSnapshot {
  const CloneAttemptSnapshot({
    required this.attemptId,
    required this.generation,
    required this.phase,
    required this.partialDestination,
    this.failure,
    this.progress,
    this.hostKeyChallenge,
  });

  final BigInt attemptId;
  final int generation;
  final CloneAttemptPhase phase;
  final CloneFailure? failure;
  final bool partialDestination;
  final ActivityProgress? progress;
  final HostKeyChallenge? hostKeyChallenge;
}

typedef OpenedRepositorySession = ({
  RepositorySessionIdentity identity,
  RepositorySnapshot snapshot,
});

final class CloneRunCompletion {
  const CloneRunCompletion({required this.snapshot, this.openedSession});
  final CloneAttemptSnapshot snapshot;
  final OpenedRepositorySession? openedSession;
}

final class CloneException implements Exception {
  const CloneException(this.failure);
  final CloneFailure failure;

  @override
  String toString() => 'CloneException(${failure.code.name})';
}
