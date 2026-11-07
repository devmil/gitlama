import 'dart:async';

import '../models/clone_attempt.dart';
import '../repositories/clone_repository.dart';

/// Owns clone attempts: creating, running, retrying with credentials or a
/// trusted host key, progress polling, cancellation and dismissal.
///
/// It never opens tabs. A finished attempt returns its opened session, and
/// the workspace adopts it; [isCurrent] tells whether the attempt is still the
/// one the user is looking at.
final class CloneService {
  CloneService(
    this._repository, {
    this.progressInterval = const Duration(milliseconds: 50),
  });

  final CloneRepository _repository;

  /// How often a running attempt's progress is read.
  final Duration progressInterval;

  final StreamController<CloneAttemptSnapshot> _states =
      StreamController<CloneAttemptSnapshot>.broadcast(sync: true);
  CloneAttemptSnapshot? _current;
  Timer? _progress;
  var _disposed = false;

  Stream<CloneAttemptSnapshot> get states => _states.stream;
  CloneAttemptSnapshot? get current => _current;

  /// Whether [attempt] is still the current attempt.
  bool isCurrent(CloneAttemptSnapshot attempt) =>
      !_disposed && _current?.attemptId == attempt.attemptId;

  /// Starts a clone of [source] into [destination] as attempt [generation];
  /// a running attempt is canceled first.
  Future<CloneOutcome> clone({
    required String source,
    required String destination,
    required int generation,
    String? initialBranch,
  }) async {
    if (cancelRunning() case final cancellation?) await cancellation;
    final attempt = await _repository.create(
      source: source,
      destination: destination,
      initialBranch: initialBranch,
      generation: generation,
    );
    _publish(attempt);
    return _run(attempt);
  }

  /// Runs the current attempt again, into [destination] when its partial
  /// destination had to be replaced.
  Future<CloneOutcome> retry({String? destination}) async {
    final attempt = await _repository.retry(
      _requireCurrent(),
      destination: destination,
    );
    _publish(attempt);
    return _run(attempt);
  }

  /// Runs the current attempt again with credentials the user entered. They
  /// reach the native broker only.
  Future<CloneOutcome> retryWithCredentials({
    String? username,
    String? password,
    String? token,
    String? destination,
  }) async {
    final attempt = await _repository.retry(
      _requireCurrent(),
      destination: destination,
    );
    _publish(attempt);
    return _run(
      attempt,
      run: () => _repository.runWithCredentials(
        attempt,
        username: username,
        password: password,
        token: token,
      ),
    );
  }

  Future<HostKeyChallenge> probeHostKey() async {
    final current = _requireCurrent();
    final challenge = await _repository.probeHostKey(current);
    _publish(await _repository.snapshot(current));
    return challenge;
  }

  /// Trusts or rejects [challenge]. A trusted key runs the attempt again;
  /// a rejected one returns null.
  Future<CloneOutcome?> resolveHostKey({
    required HostKeyChallenge challenge,
    required bool accept,
    String? destination,
  }) async {
    final current = _current;
    if (current == null ||
        current.hostKeyChallenge?.challengeId != challenge.challengeId) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.hostKeyChallengeExpired),
      );
    }
    if (!accept) {
      await _repository.rejectHostKey(current, challenge);
      _publish(await _repository.snapshot(current));
      return null;
    }
    await _repository.acceptHostKey(current, challenge);
    final pending = await _repository.retry(current, destination: destination);
    _publish(pending);
    return _run(pending, run: () => _repository.runWithHostKey(pending));
  }

  Future<void> cancel() async {
    final attempt = _current;
    if (attempt == null || attempt.phase != CloneAttemptPhase.running) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.invalidAttemptState),
      );
    }
    await _repository.cancel(attempt);
  }

  Future<void> dismiss() async {
    final attempt = _current;
    if (attempt == null || attempt.phase == CloneAttemptPhase.running) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.invalidAttemptState),
      );
    }
    await _repository.dismiss(attempt);
    if (_current?.attemptId == attempt.attemptId) _current = null;
  }

  /// Cancels a running attempt, or returns null when none runs.
  Future<void>? cancelRunning() {
    final attempt = _current;
    if (attempt == null || attempt.phase != CloneAttemptPhase.running) {
      return null;
    }
    return () async {
      try {
        await _repository.cancel(attempt);
      } on CloneException {
        // A concurrently finishing attempt is already releasing its process tree.
      }
    }();
  }

  /// Stops polling and cancels a running attempt.
  Future<void> close() async {
    if (cancelRunning() case final cancellation?) await cancellation;
    _progress?.cancel();
    _progress = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await close();
    _disposed = true;
    await _states.close();
  }

  CloneAttemptSnapshot _requireCurrent() =>
      _current ??
      (throw const CloneException(
        CloneFailure(CloneFailureCode.invalidAttemptState),
      ));

  Future<CloneOutcome> _run(
    CloneAttemptSnapshot attempt, {
    Future<CloneRunCompletion> Function()? run,
  }) async {
    _progress?.cancel();
    _progress = Timer.periodic(
      progressInterval,
      (_) => unawaited(_refresh(attempt)),
    );
    final CloneRunCompletion completion;
    try {
      completion = await (run ?? () => _repository.run(attempt))();
    } finally {
      _progress?.cancel();
      _progress = null;
    }
    if (!_disposed) _publish(completion.snapshot);
    return CloneOutcome(
      attempt: attempt,
      opened: completion.openedSession,
      current: isCurrent(attempt),
    );
  }

  Future<void> _refresh(CloneAttemptSnapshot attempt) async {
    if (!isCurrent(attempt)) return;
    try {
      final snapshot = await _repository.snapshot(attempt);
      if (isCurrent(attempt)) _publish(snapshot);
    } on CloneException {
      // The blocking run result remains authoritative. A missed progress poll
      // must not replace the attempt's terminal state.
    }
  }

  void _publish(CloneAttemptSnapshot snapshot) {
    if (_disposed) return;
    _current = snapshot;
    _states.add(snapshot);
  }
}

/// How a clone run ended: its session when it opened one, and whether the
/// attempt is still current, so a superseded session is closed instead of
/// adopted.
final class CloneOutcome {
  const CloneOutcome({
    required this.attempt,
    required this.opened,
    required this.current,
  });

  final CloneAttemptSnapshot attempt;
  final OpenedRepositorySession? opened;
  final bool current;
}
