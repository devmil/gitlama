import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/gitlama_layout.dart';

/// What lights one graph row: its node and outgoing edges, its incoming
/// edges, and edges the core lit on their own.
@immutable
final class HistoryLitFlags {
  const HistoryLitFlags({
    required this.lit,
    required this.incomingLit,
    required this.segmentLit,
    required this.lightingActive,
  });

  final bool lit;
  final bool incomingLit;
  final List<bool?> segmentLit;
  final bool lightingActive;

  @override
  bool operator ==(Object other) =>
      other is HistoryLitFlags &&
      other.lit == lit &&
      other.incomingLit == incomingLit &&
      other.lightingActive == lightingActive &&
      listEquals(other.segmentLit, segmentLit);

  @override
  int get hashCode =>
      Object.hash(lit, incomingLit, lightingActive, Object.hashAll(segmentLit));
}

/// A row's lighting on its way from [from] to [to]; [t] runs 0 → 1.
typedef HistoryLitTransition = ({
  HistoryLitFlags from,
  HistoryLitFlags to,
  double t,
});

/// The NH-1 landing of a new commit's node.
typedef HistoryLanding = ({
  /// 0 → 1: the temporary dashed ring's gaps close (`landRingClose`).
  double ringClose,

  /// 1 → 0: the temporary ring fades out by `commitLand`.
  double ringOpacity,

  /// 0 → 1 on `spring-pop`: the core fill.
  double core,

  /// 0 → 1 on `spring-snappy`: the HEAD halo growing from the inner radius.
  double halo,
});

class _Transition {
  _Transition(this.from, this.to, this.start, this.duration);

  final HistoryLitFlags from;
  final HistoryLitFlags to;
  final Duration start;
  final Duration duration;
}

/// The History graph's motion (docs/design-system/specs/motion.md): lane
/// lighting (NH-3), lane drawing (NH-2, NH-7) and one-time row effects
/// (NH-1). One ticker drives every row; rows read their values while they
/// paint, so a tick repaints the graph without rebuilding rows.
///
/// Owned by `HistoryPaneState`, passed to `HistoryGraphView` and reached by
/// rows through [HistoryMotionScope].
final class HistoryMotion extends ChangeNotifier {
  HistoryMotion({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration _now = Duration.zero;

  /// Time since the ticker started, advancing only while effects run.
  Duration get now => _now;
  Duration _clockBase = Duration.zero;

  // ---------------------------------------------------------------- clock

  void _tick(Duration elapsed) {
    _now = _clockBase + elapsed;
    notifyListeners();
    if (!_running) {
      _clockBase = _now;
      _ticker.stop();
    }
  }

  void _ensureTicking() {
    if (_ticker.isActive) return;
    _ticker.start();
  }

  bool get _running =>
      _transitions.values.any((t) => _now < t.start + t.duration) ||
      _now < _drawEnd ||
      _now < _landingEnd ||
      _now < _insertEnd;

  // ---------------------------------------------------------------- lighting

  final Map<String, HistoryLitFlags> _settled = {};
  final Map<String, _Transition> _transitions = {};
  Duration _lightStart = Duration.zero;
  Duration? _lastLightChange;
  int? _focusIndex;
  var _returning = false;
  var _instant = true;

  /// The lit ancestry changed (a new selection lights its path, or lighting
  /// ended). Rows whose lighting differs then light up flowing down from
  /// [focusIndex] (`laneFlowStep` per row, at most `laneFlowMaxRows`), or
  /// dim over `laneDim`; when lighting ends everything returns over
  /// `motion-hover-out` at once (NH-3). Changes faster than
  /// `detailDebounce` apart (keyboard scrubbing) and reduce motion switch at
  /// once.
  void lightingChanged({
    required int? focusIndex,
    required bool active,
    required bool reduced,
  }) {
    // Frame time, which runs even while no effect does.
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final last = _lastLightChange;
    _lastLightChange = frame;
    // A new change finishes the running one first (rule 1.3.2).
    _transitions.clear();
    _instant =
        reduced ||
        (last != null &&
            frame - last < GitLamaMotion.detailDebounce * timeDilation);
    _focusIndex = focusIndex;
    _returning = !active;
    _lightStart = _now;
  }

  /// Records a row's current lighting while it builds and starts its
  /// transition when it changed since it was last seen.
  void observeLighting(String objectId, int index, HistoryLitFlags flags) {
    final previous = _settled[objectId];
    _settled[objectId] = flags;
    if (_settled.length > 4096) _settled.remove(_settled.keys.first);
    if (previous == null || previous == flags || _instant) {
      if (previous != flags) _transitions.remove(objectId);
      return;
    }
    final focus = _focusIndex;
    final distance = focus == null || index <= focus
        ? 0
        : math.min(index - focus, GitLamaMotion.laneFlowMaxRows);
    final delay = _returning
        ? Duration.zero
        : GitLamaMotion.laneFlowStep * distance;
    final duration = _returning
        ? MeridianDurations.hoverOut
        : GitLamaMotion.laneDim;
    _transitions[objectId] = _Transition(
      previous,
      flags,
      _lightStart + delay,
      duration,
    );
    _ensureTicking();
  }

  /// The row's lighting transition, or `null` when it is at rest.
  HistoryLitTransition? litTransition(String objectId) {
    final transition = _transitions[objectId];
    if (transition == null) return null;
    final elapsed = _now - transition.start;
    if (elapsed >= transition.duration) {
      _transitions.remove(objectId);
      return null;
    }
    final linear = elapsed.isNegative
        ? 0.0
        : elapsed.inMicroseconds / transition.duration.inMicroseconds;
    return (
      from: transition.from,
      to: transition.to,
      t: MeridianCurves.standard.transform(linear.clamp(0.0, 1.0)),
    );
  }

  // ---------------------------------------------------------------- drawing

  int _drawFirst = 0;
  int _drawCount = 0;
  Duration _drawStart = Duration.zero;
  Duration _drawEnd = Duration.zero;

  /// Draws the lanes of rows [firstIndex] to `firstIndex + count − 1` in
  /// from the top (`laneDrawStep` apart, `laneDrawRow` each, at most
  /// `laneDrawMaxRows` rows; the rest appear at once), starting after
  /// [delay] (NH-2, NH-7).
  void drawLanes(
    int firstIndex,
    int count, {
    Duration delay = Duration.zero,
    required bool reduced,
  }) {
    if (reduced || count <= 0) {
      _drawCount = 0;
      return;
    }
    _drawFirst = firstIndex;
    _drawCount = math.min(count, GitLamaMotion.laneDrawMaxRows);
    _drawStart = _now + delay;
    _drawEnd =
        _drawStart +
        GitLamaMotion.laneDrawStep * (_drawCount - 1) +
        GitLamaMotion.laneDrawRow;
    _ensureTicking();
  }

  /// How much of row [index]'s graph is drawn, 0 → 1 from the top; 1 when
  /// no draw runs.
  double drawProgress(int index) {
    if (_drawCount == 0 || _now >= _drawEnd) return 1;
    final offset = index - _drawFirst;
    if (offset < 0 || offset >= _drawCount) return 1;
    final start = _drawStart + GitLamaMotion.laneDrawStep * offset;
    final elapsed = _now - start;
    if (elapsed.isNegative) return 0;
    final t = elapsed.inMicroseconds / GitLamaMotion.laneDrawRow.inMicroseconds;
    return MeridianCurves.standard.transform(t.clamp(0.0, 1.0));
  }

  // ---------------------------------------------------------------- landing

  String? _landingId;
  Duration _landingStart = Duration.zero;
  Duration _landingEnd = Duration.zero;
  SpringSimulation? _core;
  SpringSimulation? _halo;

  /// NH-1: the node of the new commit [objectId] lands: its temporary ring
  /// closes over `landRingClose`, then the core pops (`spring-pop`) and the
  /// HEAD halo grows (`spring-snappy`); the ring fades by `commitLand`.
  void landCommit(String objectId, {required bool reduced}) {
    if (reduced) {
      _landingId = null;
      return;
    }
    _landingId = objectId;
    _landingStart = _now;
    _core = SpringSimulation(MeridianSprings.pop, 0, 1, 0);
    _halo = SpringSimulation(MeridianSprings.snappy, 0, 1, 0);
    _landingEnd =
        _landingStart +
        GitLamaMotion.landRingClose +
        MeridianDurations.celebrate;
    _ensureTicking();
  }

  /// The landing of [objectId]'s node, or `null` when it is not landing.
  HistoryLanding? landing(String objectId) {
    if (_landingId != objectId || _now >= _landingEnd) return null;
    final elapsed = _now - _landingStart;
    final close = GitLamaMotion.landRingClose;
    final ringClose = (elapsed.inMicroseconds / close.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    final afterClose = elapsed - close;
    final seconds = afterClose.isNegative
        ? 0.0
        : afterClose.inMicroseconds / Duration.microsecondsPerSecond;
    final fadeFrom = close;
    final fadeLength = GitLamaMotion.commitLand - close;
    final fade =
        ((elapsed - fadeFrom).inMicroseconds / fadeLength.inMicroseconds).clamp(
          0.0,
          1.0,
        );
    return (
      ringClose: MeridianCurves.standard.transform(ringClose),
      ringOpacity: 1 - MeridianCurves.exit.transform(fade),
      core: afterClose.isNegative ? 0 : _core!.x(seconds),
      halo: afterClose.isNegative ? 0 : _halo!.x(seconds),
    );
  }

  // ---------------------------------------------------------------- insert

  int? _insertIndex;
  var _insertDirection = 1;
  Duration _insertStart = Duration.zero;
  Duration _insertEnd = Duration.zero;

  /// NH-1, NM-36: a row was inserted at [index]; rows from it down slide
  /// from their old places over `motion-layout` and the new row fades in
  /// over `motion-select`.
  void insertRow(int index, {required bool reduced}) =>
      _shift(index, 1, reduced: reduced);

  /// NM-36: the row at [index] went away; the rows below slide up from
  /// their old places over `motion-layout`.
  void removeRow(int index, {required bool reduced}) =>
      _shift(index, -1, reduced: reduced);

  void _shift(int index, int direction, {required bool reduced}) {
    if (reduced) {
      _insertIndex = null;
      return;
    }
    _insertIndex = index;
    _insertDirection = direction;
    _insertStart = _now;
    _insertEnd = _now + MeridianDurations.layout;
    _ensureTicking();
  }

  /// How far rows at or below an insert or removal still sit from their
  /// place, in rows (±1 → 0; positive is above), and an inserted row's
  /// opacity. `null` when nothing moves.
  ({double shift, double opacity})? insertion(int index) {
    final at = _insertIndex;
    if (at == null || _now >= _insertEnd || index < at) return null;
    final elapsed = (_now - _insertStart).inMicroseconds;
    final moved = MeridianDurations.layoutCurve.transform(
      (elapsed / MeridianDurations.layout.inMicroseconds).clamp(0.0, 1.0),
    );
    final opacity = MeridianDurations.selectCurve.transform(
      (elapsed / MeridianDurations.select.inMicroseconds).clamp(0.0, 1.0),
    );
    return (
      shift: _insertDirection * (1 - moved),
      opacity: _insertDirection > 0 && index == at ? opacity : 1,
    );
  }

  // ---------------------------------------------------------------- loading

  final Set<int> _placeholders = {};

  /// Row [index] shows a loading placeholder (NM-38).
  void notePlaceholder(int index) {
    _placeholders.add(index);
    if (_placeholders.length > 512) _placeholders.remove(_placeholders.first);
  }

  /// Whether row [index] replaces a placeholder: it then fades in over it.
  bool consumePlaceholder(int index) => _placeholders.remove(index);

  // ---------------------------------------------------------------- control

  /// Jumps every running effect to its end state (rule 1.3.2).
  void finishAll() {
    _transitions.clear();
    _drawCount = 0;
    _landingId = null;
    _insertIndex = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Gives rows of a `HistoryGraphView` its [HistoryMotion].
class HistoryMotionScope extends InheritedWidget {
  const HistoryMotionScope({
    super.key,
    required this.motion,
    required super.child,
  });

  final HistoryMotion motion;

  static HistoryMotion? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HistoryMotionScope>()?.motion;

  @override
  bool updateShouldNotify(HistoryMotionScope oldWidget) =>
      motion != oldWidget.motion;
}
