import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/services/remote_reconnect.dart';

final class _Timer implements Timer {
  _Timer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  var cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

final class _Harness {
  _Harness({bool wanted = true}) : wanted = {'p': wanted};

  final Map<String, bool> wanted;
  final List<_Timer> timers = [];
  final List<String> attempts = [];
  final List<String> reconnected = [];
  var now = DateTime(2026, 10, 9, 12);

  /// What the next attempts answer, in order; ready once exhausted.
  final List<Object> answers = [];

  late final RemoteReconnector reconnector = RemoteReconnector(
    reconnect: (profileId) async {
      attempts.add(profileId);
      final answer = answers.isEmpty ? null : answers.removeAt(0);
      if (answer is RemoteWorkspaceException) throw answer;
      if (answer is RemoteFailureCode) {
        return RemoteConnectionState(
          profileId: profileId,
          phase: RemoteConnectionPhase.failed,
          failure: answer,
        );
      }
      if (answer is RemoteConnectionState) return answer;
      return RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.ready,
      );
    },
    wanted: (profileId) => wanted[profileId] ?? false,
    timer: (delay, callback) {
      final timer = _Timer(delay, callback);
      timers.add(timer);
      return timer;
    },
    now: () => now,
  )..reconnected.listen(reconnected.add);

  _Timer get pending => timers.lastWhere((timer) => !timer.cancelled);

  RemoteReconnectState? get state => reconnector.stateOf('p');

  /// Lets the pending pause pass and the attempt finish.
  Future<void> elapse() async {
    final timer = pending;
    now = now.add(timer.delay);
    timer.cancelled = true;
    timer.callback();
    await pumpEventQueue();
  }
}

void main() {
  test(
    'a lost connection is retried with growing pauses until it connects',
    () async {
      final harness = _Harness();
      harness.answers.addAll([
        RemoteFailureCode.timedOut,
        RemoteFailureCode.sshConnectionFailed,
      ]);
      harness.reconnector.lost('p', RemoteFailureCode.disconnected);
      expect(harness.state?.phase, RemoteReconnectPhase.waiting);
      expect(harness.state?.failure, RemoteFailureCode.disconnected);
      expect(harness.pending.delay, const Duration(seconds: 2));
      expect(
        harness.state?.nextAttemptAt,
        harness.now.add(const Duration(seconds: 2)),
      );

      await harness.elapse();
      expect(harness.attempts, ['p']);
      expect(harness.state?.failure, RemoteFailureCode.timedOut);
      expect(harness.pending.delay, const Duration(seconds: 5));
      await harness.elapse();
      expect(harness.pending.delay, const Duration(seconds: 15));
      await harness.elapse();
      expect(harness.attempts, hasLength(3));
      expect(harness.state, isNull);
      expect(harness.reconnected, ['p']);
      await harness.reconnector.dispose();
    },
  );

  test('failures that need the user stop at once', () async {
    for (final failure in [
      RemoteFailureCode.identityChanged,
      RemoteFailureCode.helperNotInstalled,
      RemoteFailureCode.buildMismatch,
      RemoteFailureCode.gitMissing,
    ]) {
      final harness = _Harness();
      harness.reconnector.lost('p', failure);
      expect(
        harness.state?.phase,
        RemoteReconnectPhase.stopped,
        reason: '$failure',
      );
      expect(harness.state?.gaveUp, isFalse);
      expect(harness.timers, isEmpty);
      await harness.reconnector.dispose();
    }
    // An attempt that finds a changed identity hands it to the user.
    final harness = _Harness();
    harness.answers.add(
      const RemoteConnectionState(
        profileId: 'p',
        phase: RemoteConnectionPhase.identityChanged,
      ),
    );
    harness.reconnector.lost('p', RemoteFailureCode.disconnected);
    await harness.elapse();
    expect(harness.state, isNull);
    expect(harness.timers.where((timer) => !timer.cancelled), isEmpty);
    await harness.reconnector.dispose();
  });

  test('attempts end after the window and Try again starts over', () async {
    final harness = _Harness();
    harness.answers.addAll(
      List.filled(20, RemoteFailureCode.sshConnectionFailed),
    );
    harness.reconnector.lost('p', RemoteFailureCode.disconnected);
    while (harness.state?.phase == RemoteReconnectPhase.waiting) {
      await harness.elapse();
    }
    expect(harness.state?.phase, RemoteReconnectPhase.stopped);
    expect(harness.state?.gaveUp, isTrue);
    expect(harness.state?.failure, RemoteFailureCode.sshConnectionFailed);
    // 2 + 5 + 15 + 30 s, then a minute apart within ten minutes.
    expect(harness.attempts.length, inInclusiveRange(10, 14));

    harness.answers.clear();
    harness.answers.add(RemoteFailureCode.timedOut);
    await harness.reconnector.reconnectNow('p');
    // The pauses start over: after this first attempt comes the second
    // pause, within a new window.
    expect(harness.state?.phase, RemoteReconnectPhase.waiting);
    expect(harness.state?.attempt, 1);
    expect(harness.pending.delay, const Duration(seconds: 5));
    await harness.reconnector.dispose();
  });

  test('Stop ends the attempts and closing the tabs drops them', () async {
    final harness = _Harness();
    harness.reconnector.lost('p', RemoteFailureCode.disconnected);
    harness.reconnector.stop('p');
    expect(harness.state?.phase, RemoteReconnectPhase.stopped);
    expect(harness.state?.gaveUp, isFalse);
    expect(harness.timers.single.cancelled, isTrue);

    harness.reconnector.lost('p', RemoteFailureCode.disconnected);
    harness.wanted['p'] = false;
    await harness.elapse();
    expect(harness.attempts, isEmpty);
    expect(harness.state, isNull);
    await harness.reconnector.dispose();
  });

  test('a host without tabs is not reconnected', () async {
    final harness = _Harness(wanted: false);
    harness.reconnector.lost('p', RemoteFailureCode.disconnected);
    harness.reconnector.connectSoon('p');
    expect(harness.state, isNull);
    expect(harness.timers, isEmpty);
    await harness.reconnector.dispose();
  });

  test('startup connects at once without announcing it', () async {
    final harness = _Harness();
    harness.reconnector.connectSoon('p');
    expect(harness.pending.delay, Duration.zero);
    await harness.elapse();
    expect(harness.attempts, ['p']);
    expect(harness.state, isNull);
    expect(harness.reconnected, isEmpty);
    await harness.reconnector.dispose();
  });

  test('a connection made elsewhere settles only outside an attempt', () async {
    final harness = _Harness();
    final gate = Completer<void>();
    final reconnector = RemoteReconnector(
      reconnect: (profileId) async {
        await gate.future;
        return RemoteConnectionState(
          profileId: profileId,
          phase: RemoteConnectionPhase.ready,
        );
      },
      wanted: (_) => true,
      timer: (delay, callback) => _Timer(delay, callback),
    );
    final attempt = reconnector.reconnectNow('p');
    reconnector.settled('p');
    expect(reconnector.stateOf('p')?.phase, RemoteReconnectPhase.connecting);
    gate.complete();
    await attempt;
    expect(reconnector.stateOf('p'), isNull);

    harness.reconnector.lost('p', RemoteFailureCode.disconnected);
    harness.reconnector.settled('p');
    expect(harness.state, isNull);
    await reconnector.dispose();
    await harness.reconnector.dispose();
  });
}
