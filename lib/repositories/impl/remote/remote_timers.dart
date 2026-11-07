import 'dart:async';

/// Creates one-shot timers. The remote transport takes it as a seam so tests
/// drive every deadline (frame, hello, call, liveness, teardown) without
/// sleeping.
typedef RemoteTimerFactory =
    Timer Function(Duration duration, void Function() callback);

Timer systemRemoteTimer(Duration duration, void Function() callback) =>
    Timer(duration, callback);

/// Completes with true when [future] completes within [limit], false when the
/// timer fires first. Errors of [future] count as completion.
Future<bool> completesWithin(
  Future<Object?> future,
  Duration limit,
  RemoteTimerFactory timer,
) {
  final result = Completer<bool>();
  final deadline = timer(limit, () {
    if (!result.isCompleted) result.complete(false);
  });
  future.then<void>(
    (_) {
      deadline.cancel();
      if (!result.isCompleted) result.complete(true);
    },
    onError: (Object _) {
      deadline.cancel();
      if (!result.isCompleted) result.complete(true);
    },
  );
  return result.future;
}
