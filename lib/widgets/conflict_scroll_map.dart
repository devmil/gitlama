import 'dart:math' as math;

/// Pairs the scroll offsets of the source comparison and the merge result so
/// both panes show the same place of a conflicted file.
///
/// Every anchor is a pair of offsets at which one place (the start or end of
/// the file or of a conflict) sits on the same line of the window in both
/// panes. Offsets between two anchors are interpolated, so unchanged text
/// scrolls at the same pace and a conflict whose result is shorter or longer
/// than its sources absorbs the difference. Both panes reach their start and
/// their end together.
final class ConflictScrollMap {
  ConflictScrollMap._(this._comparison, this._result);

  factory ConflictScrollMap({
    required Iterable<(double comparison, double result)> anchors,
    required double comparisonMax,
    required double resultMax,
  }) {
    final comparisonEnd = math.max(0.0, comparisonMax);
    final resultEnd = math.max(0.0, resultMax);
    final comparison = <double>[0];
    final result = <double>[0];
    for (final (left, right) in anchors) {
      // An anchor outside the scroll range moves both panes by the same
      // amount, so its place stays level across them wherever it is shown.
      var shift = math.max(0.0, math.max(-left, -right));
      shift += math.min(
        0.0,
        math.min(comparisonEnd - left - shift, resultEnd - right - shift),
      );
      comparison.add(
        math.max(comparison.last, (left + shift).clamp(0.0, comparisonEnd)),
      );
      result.add(math.max(result.last, (right + shift).clamp(0.0, resultEnd)));
    }
    comparison.add(comparisonEnd);
    result.add(resultEnd);
    _limitPace(comparison, result, comparisonEnd, resultEnd);
    return ConflictScrollMap._(comparison, result);
  }

  /// One pane moves at most this many times as fast as the other. A conflict
  /// that is empty on one side would otherwise make the other pane jump.
  static const double maxPace = 12;

  final List<double> _comparison;
  final List<double> _result;

  /// The result offset for a [comparison] offset. Where a range of result
  /// offsets matches, [current] stays if it is inside that range.
  double resultFor(double comparison, {required double current}) =>
      _map(_comparison, _result, comparison, current);

  /// The comparison offset for a [result] offset. Where a range of comparison
  /// offsets matches, [current] stays if it is inside that range.
  double comparisonFor(double result, {required double current}) =>
      _map(_result, _comparison, result, current);

  /// Moves anchors that would make one pane race. An anchor moves both panes
  /// by the same amount, which keeps the unchanged text beside it level.
  static void _limitPace(
    List<double> left,
    List<double> right,
    double leftEnd,
    double rightEnd,
  ) {
    double excess(double leftStep, double rightStep) => math.max(
      0,
      math.max(rightStep - maxPace * leftStep, leftStep - maxPace * rightStep) /
          (maxPace - 1),
    );

    final last = left.length - 1;
    for (var i = 1; i < last; i++) {
      final shift = math.min(
        excess(left[i] - left[i - 1], right[i] - right[i - 1]),
        math.min(leftEnd - left[i], rightEnd - right[i]),
      );
      left[i] += shift;
      right[i] += shift;
    }
    for (var i = last - 1; i > 0; i--) {
      final shift = math.min(
        excess(left[i + 1] - left[i], right[i + 1] - right[i]),
        math.min(left[i], right[i]),
      );
      left[i] -= shift;
      right[i] -= shift;
    }
    // Two bounds that cannot both hold leave the order intact.
    for (var i = 1; i < last; i++) {
      left[i] = math.max(left[i], left[i - 1]);
      right[i] = math.max(right[i], right[i - 1]);
    }
  }

  static double _map(
    List<double> from,
    List<double> to,
    double offset,
    double current,
  ) {
    final value = offset.clamp(from.first, from.last);
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (var i = 0; i + 1 < from.length; i++) {
      final start = from[i];
      final end = from[i + 1];
      if (value < start) break;
      if (value > end) continue;
      if (end == start) {
        low = math.min(low, to[i]);
        high = math.max(high, to[i + 1]);
        continue;
      }
      final mapped =
          to[i] + (to[i + 1] - to[i]) * (value - start) / (end - start);
      low = math.min(low, mapped);
      high = math.max(high, mapped);
    }
    return current.clamp(low, high);
  }
}
