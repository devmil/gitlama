import 'dart:async';

/// A manual clock for the remote transport's timer seam.
final class FakeTimers {
  var now = Duration.zero;
  final _timers = <FakeTimer>[];
  var _created = 0;

  Timer call(Duration duration, void Function() callback) {
    final timer = FakeTimer._(this, now + duration, _created++, callback);
    _timers.add(timer);
    return timer;
  }

  /// Timers still pending.
  int get active => _timers.length;

  /// Advances the clock, firing due timers in deadline then creation order,
  /// including timers created by callbacks that fall due within [duration].
  void elapse(Duration duration) {
    final target = now + duration;
    while (true) {
      final due = _timers.where((timer) => timer.at <= target).toList()
        ..sort((a, b) {
          final byTime = a.at.compareTo(b.at);
          return byTime != 0 ? byTime : a.order.compareTo(b.order);
        });
      if (due.isEmpty) break;
      final timer = due.first;
      _timers.remove(timer);
      now = timer.at;
      timer._fire();
    }
    now = target;
  }
}

final class FakeTimer implements Timer {
  FakeTimer._(this._owner, this.at, this.order, this._callback);

  final FakeTimers _owner;
  final Duration at;
  final int order;
  final void Function() _callback;
  var _active = true;

  void _fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
    _owner._timers.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// Lets queued microtasks and zero-delay events run.
Future<void> settle() async {
  for (var index = 0; index < 20; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
