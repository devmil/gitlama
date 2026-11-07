import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/widgets/conflict_scroll_map.dart';

void main() {
  test('anchors pair exactly and unchanged text keeps one pace', () {
    final map = ConflictScrollMap(
      comparisonMax: 5000,
      resultMax: 5200,
      anchors: const [(0, 0), (1000, 1000), (1200, 1400), (5000, 5200)],
    );
    expect(map.resultFor(1000, current: 0), 1000);
    expect(map.resultFor(1200, current: 0), 1400);
    expect(map.comparisonFor(1400, current: 0), 1200);
    // Inside the conflict the longer result moves faster.
    expect(map.resultFor(1100, current: 0), 1200);
    // Before and after it both panes move alike.
    expect(map.resultFor(400, current: 0), 400);
    expect(map.resultFor(2200, current: 0), 2400);
    expect(map.comparisonFor(2400, current: 0), 2200);
  });

  test('both panes reach their start and end together', () {
    final map = ConflictScrollMap(
      comparisonMax: 900,
      resultMax: 300,
      anchors: const [(400, 100)],
    );
    expect(map.resultFor(0, current: 50), 0);
    expect(map.resultFor(900, current: 50), 300);
    expect(map.comparisonFor(0, current: 50), 0);
    expect(map.comparisonFor(300, current: 50), 900);
    expect(map.resultFor(-40, current: 50), 0);
    expect(map.resultFor(2000, current: 50), 300);
  });

  test('an anchor outside the range keeps its place level', () {
    // Both panes would have to scroll 150 past the end of the result.
    final map = ConflictScrollMap(
      comparisonMax: 2000,
      resultMax: 1000,
      anchors: const [(1000, 300), (1850, 1150)],
    );
    expect(map.resultFor(1500, current: 0), closeTo(800, 0.001));
    expect(map.resultFor(2000, current: 0), 1000);
    // Before the first line can reach the reference line, 40 further down.
    final start = ConflictScrollMap(
      comparisonMax: 2000,
      resultMax: 2000,
      anchors: const [(-40, -10), (500, 530)],
    );
    expect(start.resultFor(500, current: 0), 530);
    expect(start.resultFor(300, current: 0), 330);
  });

  test('an empty side never makes the other pane jump', () {
    final map = ConflictScrollMap(
      comparisonMax: 4000,
      resultMax: 4000,
      // The conflict takes 300 in the comparison and nothing in the result.
      anchors: const [(1000, 1000), (1300, 1000), (3000, 2700)],
    );
    var previous = map.comparisonFor(0, current: 0);
    for (var offset = 1.0; offset <= 4000; offset++) {
      final next = map.comparisonFor(offset, current: previous);
      expect(next, greaterThanOrEqualTo(previous));
      expect(
        next - previous,
        lessThanOrEqualTo(ConflictScrollMap.maxPace + 0.001),
      );
      previous = next;
    }
    expect(previous, 4000);
    // The text after the conflict is level again.
    expect(map.resultFor(2000, current: 0), closeTo(1700, 0.001));
  });

  test('a pane that cannot scroll leaves the other one free', () {
    final map = ConflictScrollMap(
      comparisonMax: 0,
      resultMax: 800,
      anchors: const [(0, 0), (120, 400)],
    );
    expect(map.comparisonFor(500, current: 0), 0);
    expect(map.resultFor(0, current: 250), 250);
  });
}
