import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/widgets/diff_view.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('profiles heavy diff scrolling and selection latency', (
    tester,
  ) async {
    final timings = <FrameTiming>[];
    void collectTimings(List<FrameTiming> values) => timings.addAll(values);
    binding.addTimingsCallback(collectTimings);
    addTearDown(() => binding.removeTimingsCallback(collectTimings));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Set<String> selected = {};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DiffView(
              itemCount: 100000,
              controller: controller,
              layout: DiffViewLayout.sideBySide,
              selectedIds: selected,
              rowAt: profileRow,
              textStyler: (_, row) => TextSpan(
                text: utf8.decode(row.text),
                children: const [
                  TextSpan(
                    text: ' keyword',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              onSelectionChanged: (value) => setState(() => selected = value),
            ),
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
      final stopwatch = Stopwatch()..start();
      await tester.tap(find.byType(InkWell).hitTestable().first);
      await binding.endOfFrame.timeout(const Duration(seconds: 1));
      stopwatch.stop();
      selectionSamples.add(stopwatch.elapsedMicroseconds);
    }
    selectionSamples.sort();
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
                (widget.key! as ValueKey<String>).value.startsWith('diff-row-'),
          )
          .evaluate()
          .length,
    };
    debugPrint('GITLAMA_DIFF_PROFILE ${jsonEncode(report)}');
  });
}

Future<void> waitForProfileScroll() async {
  // benchmarkLive lets the engine schedule real device frames. Waiting for a
  // fixed window avoids pumpAndSettle deadlocks when the desktop is occluded.
  await Future<void>.delayed(const Duration(milliseconds: 900));
}

DiffDisplayRow profileRow(int index) => DiffDisplayRow(
  stableId: 'line-$index',
  kind: index.isEven ? DiffRowKind.addition : DiffRowKind.deletion,
  oldLine: index,
  newLine: index,
  text: utf8.encode(
    index % 97 == 0
        ? 'token_$index ${'x' * 16000}'
        : 'token_$index representative source line',
  ),
  selectable: true,
);
