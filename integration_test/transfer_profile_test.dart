// Drives the production shell through one pull in a real repository and
// reports when each visible consequence arrives. The output contains durations
// and interface states only; no repository or user content is printed.
//
// Prepare a clone that is behind a reachable remote, for example a local clone
// reset to an older commit, then:
//
// flutter build macos --profile \
//   --target integration_test/transfer_profile_test.dart \
//   --dart-define=GITLAMA_TRANSFER_REPOSITORY=/path/to/clone \
//   --dart-define=GITLAMA_TRANSFER_REPORT=/path/to/report.json
// GITLAMA_PROFILE_ROOT=/tmp/profile GITLAMA_RUNTIME_DIR=/tmp/runtime \
//   build/macos/Build/Products/Profile/GitLama.app/Contents/MacOS/GitLama
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_launcher.dart';
import 'package:gitlama/app/home_screen.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/widgets/history_graph_view.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';

const _repository = String.fromEnvironment('GITLAMA_TRANSFER_REPOSITORY');
const _reportPath = String.fromEnvironment('GITLAMA_TRANSFER_REPORT');

/// A directory for window captures, for local visual review only.
const _captureDirectory = String.fromEnvironment(
  'GITLAMA_PROFILE_CAPTURES',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets(
    'profile one pull',
    (tester) async {
      expect(_repository, isNotEmpty, reason: 'pass the repository to pull');
      final report = <String, Object?>{};
      Future<void> wait(int milliseconds) =>
          Future<void>.delayed(Duration(milliseconds: milliseconds));

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

      await tester.pumpWidget(const AppLauncher());
      final home = find.byType(HomeScreen);
      for (
        var attempt = 0;
        attempt < 1500 && home.evaluate().isEmpty;
        attempt++
      ) {
        await wait(10);
      }
      final runtime = tester.widget<HomeScreen>(home).runtime;
      final sessions = runtime.repositorySessions;
      final opening = Stopwatch()..start();
      await sessions.open(_repository);
      final tab = sessions.workspace.activeTab!;
      sessions.updateNavigation(
        tab.id,
        tab.navigation.copyWith(pane: WorkspacePane.history),
      );
      final historyRows = find.byWidgetPredicate(
        (widget) =>
            widget is RepaintBoundary &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('history-row-'),
      );
      // The newest row and the number of references drawn on it. The remote
      // branch is there before the pull; the local one joins it afterwards.
      (String, int)? firstRow() {
        final graphs = find.byType(HistoryGraphView).evaluate();
        if (graphs.isEmpty) return null;
        final graph = graphs.first.widget as HistoryGraphView;
        if (graph.itemCount == 0) return null;
        final row = graph.rowAt(0);
        return (row.objectId, row.refCount);
      }

      while (opening.elapsed < const Duration(seconds: 60) &&
          (historyRows.evaluate().isEmpty ||
              sessions.workspace.activeTab?.session?.snapshot.status == null)) {
        await wait(10);
      }
      report['openToStatusAndRowsMillis'] = opening.elapsedMilliseconds;
      // Let the first watcher pass and ignore discovery finish.
      await wait(4000);
      final before = sessions.workspace.activeTab!.session!.snapshot;
      report['behindBefore'] = before.status?.behind.toInt();
      final headBefore = before.status?.headObjectId;
      final firstRowBefore = firstRow();
      // Look at older history first, as one does while a pull is due.
      final history = find.byType(HistoryGraphView);
      for (var fling = 0; fling < 3; fling++) {
        await tester.flingFrom(
          tester.getCenter(history),
          const Offset(0, -700),
          3200,
        );
        await wait(700);
      }
      await capture('before');

      GitLamaCompass compass() =>
          tester.widget<GitLamaCompass>(find.byType(GitLamaCompass));
      await tester.tap(find.byKey(const ValueKey('toolbar-action-pull')));
      for (var attempt = 0; attempt < 300; attempt++) {
        await wait(10);
        if (find.byType(MeridianDialog).evaluate().isNotEmpty) break;
      }
      await wait(400);
      final confirm = find.descendant(
        of: find.byType(MeridianDialog),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MeridianButton &&
              widget.variant == MeridianButtonVariant.primary,
        ),
      );
      final pull = Stopwatch()..start();
      await tester.tap(confirm);

      final marks = <String, int>{};
      void mark(String name) =>
          marks.putIfAbsent(name, () => pull.elapsedMilliseconds);
      final details = <String>{};
      final banners = <String>{};
      var captured = 0;
      var settledSince = -1;
      while (pull.elapsed < const Duration(seconds: 180)) {
        await wait(10);
        final pill = compass();
        if (pill.operation != null) mark('operationShown');
        if (pill.operationDetail case final detail?) {
          mark('progressShown');
          // Keep the phase, drop the counter.
          details.add(detail.replaceAll(RegExp(r'\d+'), '#'));
          if (captured < 3 && pull.elapsedMilliseconds > 400 * (captured + 1)) {
            captured += 1;
            await capture('running-$captured');
          }
        }
        for (final banner in find.byType(MeridianBanner).evaluate()) {
          banners.add((banner.widget as MeridianBanner).tone.name);
        }
        final snapshot = sessions.workspace.activeTab?.session?.snapshot;
        final status = snapshot?.status;
        if (status != null && status.headObjectId != headBefore) {
          mark('headMoved');
        }
        if (marks.containsKey('operationShown') && pill.operation == null) {
          mark('operationEnded');
        }
        final first = firstRow();
        if (first != null &&
            first != firstRowBefore &&
            first.$1 == status?.headObjectId) {
          mark('graphShowsNewHead');
        }
        final operations = runtime.operationCenter.current;
        final quiet =
            marks.containsKey('graphShowsNewHead') &&
            marks.containsKey('operationEnded') &&
            operations.runningCount == 0;
        if (!quiet) {
          settledSince = -1;
        } else if (settledSince < 0) {
          settledSince = pull.elapsedMilliseconds;
        } else if (pull.elapsedMilliseconds - settledSince > 3000) {
          marks['quiet'] = settledSince;
          break;
        }
      }
      await capture('after');
      final after = sessions.workspace.activeTab!.session!.snapshot;
      final operations = runtime.operationCenter.current;
      report
        ..['marksMillis'] = marks
        ..['progressTexts'] = details.toList()
        ..['bannerTones'] = banners.toList()
        ..['behindAfter'] = after.status?.behind.toInt()
        ..['headSelected'] =
            sessions.workspace.activeTab?.navigation.selectedIdentity ==
            after.status?.headObjectId
        ..['headRowMounted'] = find
            .byKey(ValueKey('history-row-${after.status?.headObjectId}'))
            .evaluate()
            .isNotEmpty
        ..['watchOverflowPending'] =
            sessions.workspace.activeTab?.watchOverflowRevision != null
        ..['logbook'] = [
          for (final entry in operations.entries)
            '${entry.action.name}/${entry.origin.name}/${entry.state.name}',
        ]
        ..['failedCount'] = operations.failedCount
        ..['warnings'] = operations.entries
            .where((entry) => entry.state == OperationCenterState.warning)
            .length;
      final encoded = jsonEncode(report);
      debugPrint('GITLAMA_TRANSFER_PROFILE $encoded');
      if (_reportPath.isNotEmpty) File(_reportPath).writeAsStringSync(encoded);
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
