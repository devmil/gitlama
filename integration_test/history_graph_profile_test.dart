import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/widgets/history_graph_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('profile 100k history scroll and selection', (tester) async {
    final timings = <FrameTiming>[];
    void collectTimings(List<FrameTiming> values) => timings.addAll(values);
    binding.addTimingsCallback(collectTimings);
    addTearDown(() => binding.removeTimingsCallback(collectTimings));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            controller: controller,
            itemCount: 100000,
            rowAt: profileRow,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );
    await waitForProfileScroll();
    for (var warmup = 0; warmup < 5; warmup += 1) {
      await tester.fling(find.byType(ListView), const Offset(0, -600), 2400);
      await waitForProfileScroll();
    }
    timings.clear();
    for (var sample = 0; sample < 30; sample += 1) {
      await tester.fling(find.byType(ListView), const Offset(0, -900), 3200);
      await waitForProfileScroll();
    }
    expect(timings.length, greaterThan(30));
    final builds =
        timings.map((timing) => timing.buildDuration.inMicroseconds).toList()
          ..sort();
    final rasters =
        timings.map((timing) => timing.rasterDuration.inMicroseconds).toList()
          ..sort();
    final totals =
        timings.map((timing) => timing.totalSpan.inMicroseconds).toList()
          ..sort();
    final p95Index = ((timings.length - 1) * 0.95).round();
    final missed = totals.where((value) => value > 16667).length;

    final selectionSamples = <int>[];
    for (var sample = 0; sample < 30; sample += 1) {
      final target = find.byType(InkWell).hitTestable().first;
      final stopwatch = Stopwatch()..start();
      await tester.tap(target);
      await binding.endOfFrame.timeout(const Duration(seconds: 1));
      stopwatch.stop();
      selectionSamples.add(stopwatch.elapsedMicroseconds);
    }
    selectionSamples.sort();
    expect(selected, isNotNull);
    expect(builds[p95Index], lessThan(16667));
    expect(rasters[p95Index], lessThan(16667));
    expect(selectionSamples[28], lessThan(100000));
    final report = {
      'frames': timings.length,
      'buildP95Us': builds[p95Index],
      'rasterP95Us': rasters[p95Index],
      'totalMaxUs': totals.last,
      'missedFrameFraction': missed / timings.length,
      'selectionP95Us': selectionSamples[28],
      'liveRows': find
          .byWidgetPredicate(
            (widget) =>
                widget is RepaintBoundary &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'history-row-',
                ),
          )
          .evaluate()
          .length,
    };
    // The integration driver preserves this structured measurement in its output.
    // No repository or user content is included.
    debugPrint('GITLAMA_HISTORY_PROFILE ${jsonEncode(report)}');
  });
}

Future<void> waitForProfileScroll() async {
  // benchmarkLive lets the engine schedule real device frames. Waiting for a
  // fixed window avoids pumpAndSettle deadlocks when the desktop is occluded.
  await Future<void>.delayed(const Duration(milliseconds: 900));
}

HistoryGraphRow profileRow(int index) {
  final lane = index % 24;
  final merge = index % 19 == 0;
  return HistoryGraphRow(
    objectId: index.toRadixString(16).padLeft(40, '0'),
    lane: lane,
    shape: merge ? HistoryNodeShape.merge : HistoryNodeShape.commit,
    segments: [
      for (var activeLane = 0; activeLane < 24; activeLane += 1)
        HistoryGraphSegment(
          fromLane: activeLane,
          toLane: activeLane,
          kind: HistorySegmentKind.straight,
          startsAtTop: true,
        ),
      if (merge)
        HistoryGraphSegment(
          fromLane: lane,
          toLane: (lane + 7) % 24,
          kind: HistorySegmentKind.merge,
        ),
    ],
    geometry: const HistoryRowGeometry(
      metadataLeft: 818,
      graphClipRight: 806,
      contentStart: 406,
      contentAvailable: 400,
    ),
    subject: utf8.encode('Commit $index'),
    author: utf8.encode('Fixture'),
    authorTime: 1789776000,
  );
}
