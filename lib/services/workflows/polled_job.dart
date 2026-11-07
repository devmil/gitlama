import 'dart:async';

/// Runs a native background job to its end: it starts the job, polls it
/// while it is pending and cancels it when nobody wants its result any more.
/// The poll loops of the repository tools and the diff renderer share it, so
/// no widget owns a loop.
final class PolledJob<T> {
  PolledJob({
    required this._start,
    required this._poll,
    required this._pending,
    required this._cancel,
    this.interval = const Duration(milliseconds: 50),
  });

  final Future<BigInt> Function() _start;
  final Future<T> Function(BigInt token) _poll;
  final bool Function(T result) _pending;
  final Future<Object?> Function(BigInt token) _cancel;
  final Duration interval;
  BigInt? _token;
  var _stopped = false;

  /// Whether the job runs.
  bool get running => _token != null;

  /// Starts the job and completes with its final result, or null once it
  /// was stopped. Errors of the job propagate.
  Future<T?> run() async {
    final token = await _start();
    if (_stopped) {
      await _cancel(token);
      return null;
    }
    _token = token;
    try {
      while (!_stopped) {
        final result = await _poll(token);
        if (_stopped) return null;
        if (!_pending(result)) return result;
        await Future<void>.delayed(interval);
      }
      return null;
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  /// Stops waiting and cancels the job when it already started.
  Future<void> stop() async {
    _stopped = true;
    final token = _token;
    _token = null;
    if (token != null) await _cancel(token);
  }
}
