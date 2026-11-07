// Drives the production shell against the workspace stored in the selected
// profile root and reports frame timings per scenario. The output contains
// counts and durations only; no repository or user content is printed.
//
// GITLAMA_PROFILE_ROOT=/path/to/profile-copy flutter drive -d macos \
//   --profile --driver test_driver/integration_test.dart \
//   --target integration_test/real_repository_profile_test.dart
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FrameTiming, ImageByteFormat;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_launcher.dart';
import 'package:gitlama/app/workspace/sidebar.dart';
import 'package:gitlama/widgets/history_graph_view.dart';

/// A directory for window captures, for local visual review only.
const _captureDirectory = String.fromEnvironment(
  'GITLAMA_PROFILE_CAPTURES',
);
const _captureOnly = bool.fromEnvironment('GITLAMA_PROFILE_CAPTURE_ONLY');

const _attachDelay = Duration(
  milliseconds: int.fromEnvironment('GITLAMA_PROFILE_ATTACH_MS'),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets(
    'profile the stored workspace',
    (tester) async {
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> values) => timings.addAll(values);
      binding.addTimingsCallback(collect);
      addTearDown(() => binding.removeTimingsCallback(collect));
      final report = <String, Object?>{};

      Future<void> wait(int milliseconds) =>
          Future<void>.delayed(Duration(milliseconds: milliseconds));

      Future<void> scenario(String name, Future<void> Function() body) async {
        await wait(1200);
        timings.clear();
        final started = Timeline.now;
        final watch = Stopwatch()..start();
        await body();
        watch.stop();
        final finished = Timeline.now;
        await wait(1200);
        report[name] = _summary(
          timings,
          startedMicros: started,
          finishedMicros: finished,
          elapsedMicros: watch.elapsedMicroseconds,
        );
        debugPrint(
          'GITLAMA_REAL_PROFILE_PHASE ${jsonEncode({name: report[name]})}',
        );
      }

      Future<void> capture(String name) async {
        if (_captureDirectory.isEmpty) return;
        final view = binding.renderViews.first;
        // The debug accessor is unavailable in profile builds.
        // ignore: invalid_use_of_protected_member
        final layer = view.layer! as OffsetLayer;
        final image = await layer.toImage(
          Offset.zero & view.size,
          pixelRatio: view.flutterView.devicePixelRatio,
        );
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        image.dispose();
        File(
          '$_captureDirectory/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      }

      await wait(_attachDelay.inMilliseconds);

      final historyRows = find.byWidgetPredicate(
        (widget) =>
            widget is RepaintBoundary &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('history-row-'),
      );

      await scenario('open', () async {
        final watch = Stopwatch()..start();
        await tester.pumpWidget(const AppLauncher());
        int? firstRowMicros;
        int? firstReferenceMicros;
        final references = find.byWidgetPredicate(
          (widget) =>
              widget is Focus &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'sidebar-ref-',
              ),
        );
        while (watch.elapsed < const Duration(seconds: _captureOnly ? 8 : 25)) {
          await wait(10);
          if (firstRowMicros == null && historyRows.evaluate().isNotEmpty) {
            firstRowMicros = watch.elapsedMicroseconds;
            final sidebars = find.byType(WorkspaceSidebar).evaluate();
            report['sidebarMountedAtFirstRow'] = sidebars.isNotEmpty;
            if (sidebars.isNotEmpty) {
              final snapshot = (sidebars.first.widget as WorkspaceSidebar)
                  .active
                  ?.session
                  ?.snapshot;
              report['remotesAtFirstRow'] = snapshot?.refs.remotes.length;
              report['statusAtFirstRow'] = snapshot?.status != null;
              report['phaseAtFirstRow'] = snapshot?.phase.name;
            }
          }
          if (firstReferenceMicros == null &&
              references.evaluate().isNotEmpty) {
            firstReferenceMicros = watch.elapsedMicroseconds;
          }
        }
        report['firstHistoryRowMicros'] = firstRowMicros;
        report['firstSidebarReferenceMicros'] = firstReferenceMicros;
      });

      expect(historyRows, findsWidgets);
      await capture('open');
      if (_captureOnly) {
        report.removeWhere((name, value) => value is Map);
        debugPrint('GITLAMA_REAL_PROFILE ${jsonEncode(report)}');
        return;
      }
      report['liveHistoryRows'] = historyRows.evaluate().length;

      await scenario('idle', () => wait(8000));

      final history = find.byType(HistoryGraphView);
      final graph = tester.widget<HistoryGraphView>(history);
      var segments = 0;
      var clipped = 0;
      for (var index = 0; index < 40 && index < graph.itemCount; index += 1) {
        final row = graph.rowAt(index);
        for (final segment in row.segments) {
          segments += 1;
          final left = historyLaneX(
            segment.fromLane < segment.toLane
                ? segment.fromLane
                : segment.toLane,
          );
          if (left > row.geometry.graphClipRight) clipped += 1;
        }
      }
      report['graphSegmentsInFirstRows'] = segments;
      report['graphSegmentsBeyondClip'] = clipped;
      final historyCenter = tester.getCenter(history);
      await scenario('historyFling', () async {
        for (var sample = 0; sample < 12; sample += 1) {
          await tester.flingFrom(historyCenter, const Offset(0, -700), 3200);
          await wait(900);
        }
      });

      await scenario('historyWheel', () async {
        final pointer = TestPointer(90, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(historyCenter));
        for (var tick = 0; tick < 360; tick += 1) {
          await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
          await wait(8);
        }
        await tester.sendEventToBinding(pointer.removePointer());
      });

      await scenario('historyHover', () async {
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: historyCenter);
        for (var step = 0; step < 300; step += 1) {
          final phase = (step % 100) / 100;
          await gesture.moveTo(historyCenter + Offset(0, -260 + 520 * phase));
          await wait(8);
        }
        await gesture.removePointer();
      });

      await scenario('historySelection', () async {
        final box = tester.getRect(history);
        final samples = <int>[];
        for (var sample = 0; sample < 12; sample += 1) {
          final target = Offset(
            box.left + box.width * 0.45,
            box.top + 60 + sample * 31,
          );
          final watch = Stopwatch()..start();
          await tester.tapAt(target);
          await binding.endOfFrame.timeout(const Duration(seconds: 2));
          watch.stop();
          samples.add(watch.elapsedMicroseconds);
          await wait(700);
        }
        samples.sort();
        report['selectionFirstFrameMicros'] = samples;
      });

      final sidebar = find.byType(WorkspaceSidebar);
      if (sidebar.evaluate().isNotEmpty) {
        // Groups start collapsed. Open them so the scenarios below exercise
        // the complete reference tree of a large repository.
        for (var pass = 0; pass < 3; pass += 1) {
          final collapsed = find.descendant(
            of: sidebar,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is MeridianIcon && widget.name == 'chevron-right',
            ),
          );
          final targets = [
            for (final element in collapsed.evaluate())
              if (element.findAncestorWidgetOfExactType<MeridianListRow>() !=
                  null)
                tester.getCenter(
                  find.byElementPredicate((it) => it == element),
                ),
          ];
          // Opening a group moves the rows below it, so work upwards.
          for (final target in targets.reversed) {
            await tester.tapAt(target);
            await wait(120);
          }
        }
        report['sidebarRowsMounted'] = find
            .descendant(of: sidebar, matching: find.byType(Focus))
            .evaluate()
            .length;
        final sidebarRect = tester.getRect(sidebar);
        final sidebarPoint = Offset(
          sidebarRect.center.dx,
          sidebarRect.top + sidebarRect.height * 0.7,
        );
        await scenario('sidebarFling', () async {
          for (var sample = 0; sample < 12; sample += 1) {
            await tester.flingFrom(sidebarPoint, const Offset(0, -500), 3200);
            await wait(900);
          }
        });
        await scenario('sidebarWheel', () async {
          final pointer = TestPointer(91, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(pointer.hover(sidebarPoint));
          for (var tick = 0; tick < 360; tick += 1) {
            await tester.sendEventToBinding(
              pointer.scroll(const Offset(0, 40)),
            );
            await wait(8);
          }
          await tester.sendEventToBinding(pointer.removePointer());
        });
        await scenario('sidebarHover', () async {
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await gesture.addPointer(location: sidebarPoint);
          for (var step = 0; step < 300; step += 1) {
            final phase = (step % 100) / 100;
            await gesture.moveTo(
              Offset(
                sidebarPoint.dx,
                sidebarRect.top + 80 + (sidebarRect.height - 160) * phase,
              ),
            );
            await wait(8);
          }
          await gesture.removePointer();
        });
      }

      report.removeWhere((name, value) => value is Map);
      debugPrint('GITLAMA_REAL_PROFILE ${jsonEncode(report)}');
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Map<String, Object?> _summary(
  List<FrameTiming> timings, {
  required int startedMicros,
  required int finishedMicros,
  required int elapsedMicros,
}) {
  List<int> sorted(int Function(FrameTiming) read) =>
      [for (final timing in timings) read(timing)]..sort();
  int percentile(List<int> values, double fraction) =>
      values.isEmpty ? 0 : values[((values.length - 1) * fraction).round()];
  final builds = sorted((timing) => timing.buildDuration.inMicroseconds);
  final rasters = sorted((timing) => timing.rasterDuration.inMicroseconds);
  final totals = sorted((timing) => timing.totalSpan.inMicroseconds);
  return {
    'startedMicros': startedMicros,
    'finishedMicros': finishedMicros,
    'elapsedMicros': elapsedMicros,
    'frames': timings.length,
    'buildP50': percentile(builds, 0.5),
    'buildP90': percentile(builds, 0.9),
    'buildP99': percentile(builds, 0.99),
    'buildMax': builds.isEmpty ? 0 : builds.last,
    'rasterP50': percentile(rasters, 0.5),
    'rasterP90': percentile(rasters, 0.9),
    'rasterP99': percentile(rasters, 0.99),
    'rasterMax': rasters.isEmpty ? 0 : rasters.last,
    'totalP90': percentile(totals, 0.9),
    'totalMax': totals.isEmpty ? 0 : totals.last,
    'buildOver8ms': builds.where((value) => value > 8333).length,
    'buildOver16ms': builds.where((value) => value > 16667).length,
  };
}
