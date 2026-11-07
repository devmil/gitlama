import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:gitlama/app/workspace/shell_chrome.dart';
import 'package:gitlama/app/inspector/commit_diff_pane.dart';
import 'package:gitlama/app/workspace/logbook.dart';
import 'package:gitlama/app/workspace/rebase_dialogs.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';
import 'package:gitlama/widgets/gitlama_git_glyphs.dart';
import 'package:gitlama/widgets/gitlama_repo_tabs.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/meridian_finders.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/main.dart' show applySlowMotion;
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/widgets/history_graph_view.dart';
import 'package:gitlama/widgets/history_motion.dart';
import 'package:gitlama/widgets/gitlama_scroll.dart';
import 'package:gitlama/widgets/diff_view.dart';
import 'package:gitlama/widgets/gitlama_timeline_row.dart';

import 'history_support.dart';
import 'motion_support.dart';

void main() {
  group('NM-46', () {
    testWidgets(
      'unified and split rows crossfade without moving the viewport',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        var layout = DiffViewLayout.unified;
        late StateSetter rebuild;
        await tester.pumpWidget(
          motionHost(
            SizedBox(
              width: 480,
              height: 220,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return DiffView(
                    itemCount: 100,
                    controller: scroll,
                    rowAt: (index) => DiffDisplayRow(
                      stableId: 'line-$index',
                      kind: DiffRowKind.context,
                      text: 'line $index'.codeUnits,
                      oldLine: index + 1,
                      newLine: index + 1,
                    ),
                    layout: layout,
                    selectedIds: const {},
                    onSelectionChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        scroll.jumpTo(300);
        await tester.pump();
        final before = scroll.offset;
        rebuild(() => layout = DiffViewLayout.sideBySide);
        await tester.pump();
        expect(scroll.offset, before);
        expect(
          tester
              .widgetList<MeridianSwap>(find.byType(MeridianSwap))
              .any((swap) => swap.swapKey == DiffViewLayout.sideBySide),
          isTrue,
        );
        await pumpFrames(tester, MeridianDurations.select);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('NM-72 and NM-73', () {
    for (final reduced in [false, true]) {
      testWidgets(
        'dropping an instruction draws the strike and swaps action, reduced=$reduced',
        (tester) async {
          final plan = RebasePlan(
            token: BigInt.one,
            onto: '0123456789abcdef',
            currentBranch: const [109, 97, 105, 110],
            currentHead: '0123456789abcdef',
            instructions: [
              RebaseInstruction(
                id: BigInt.one,
                action: RebaseAction.pick,
                oid: '123456789abcdef0',
                subject: const [84, 101, 115, 116],
                published: false,
              ),
            ],
            publishedCount: 0,
            activityIds: const [],
          );
          await tester.pumpWidget(
            motionHost(
              RebaseEditorDialog(
                plan: plan,
                prediction: null,
                shortcuts: const {},
              ),
              reduced: reduced,
            ),
          );
          final select = find.byType(MeridianSelect<RebaseAction>);
          expect(
            tester.widget<MeridianSelect<RebaseAction>>(select).animateValue,
            isTrue,
          );
          tester.widget<MeridianSelect<RebaseAction>>(select).onChanged!(
            RebaseAction.drop,
          );
          await tester.pump();
          expect(
            tester
                .widget<MeridianSwap>(
                  find.descendant(
                    of: select,
                    matching: find.byType(MeridianSwap),
                  ),
                )
                .swapKey,
            RebaseAction.drop,
          );
          if (!reduced) await pumpFrames(tester, MeridianDurations.quick);
          // The strike through the dropped commit's subject.
          expect(
            tester
                .widgetList<MeridianStroke>(find.byType(MeridianStroke))
                .singleWhere(
                  (stroke) =>
                      stroke.key is ValueKey<String> &&
                      (stroke.key! as ValueKey<String>).value.startsWith(
                        'rebase-strike-',
                      ),
                )
                .progress,
            closeTo(1, 0.01),
          );
        },
      );
    }
  });

  group('NM-71', () {
    for (final reduced in [false, true]) {
      testWidgets('squash draws the grouping connector, reduced=$reduced', (
        tester,
      ) async {
        final plan = RebasePlan(
          token: BigInt.one,
          onto: '0123456789abcdef',
          currentBranch: const [109, 97, 105, 110],
          currentHead: '0123456789abcdef',
          instructions: [
            RebaseInstruction(
              id: BigInt.one,
              action: RebaseAction.pick,
              oid: '123456789abcdef0',
              subject: const [84, 101, 115, 116],
              published: false,
            ),
          ],
          publishedCount: 0,
          activityIds: const [],
        );
        await tester.pumpWidget(
          motionHost(
            RebaseEditorDialog(
              plan: plan,
              prediction: null,
              shortcuts: const {},
            ),
            reduced: reduced,
          ),
        );
        final select = find.byType(MeridianSelect<RebaseAction>);
        expect(
          tester.widget<MeridianStroke>(find.byType(MeridianStroke)).progress,
          0,
        );
        tester.widget<MeridianSelect<RebaseAction>>(select).onChanged!(
          RebaseAction.squash,
        );
        await tester.pump();
        if (!reduced) await pumpFrames(tester, GitLamaMotion.laneDrawRow);
        expect(
          tester.widget<MeridianStroke>(find.byType(MeridianStroke)).progress,
          closeTo(1, 0.01),
        );
      });
    }
  });

  group('NM-65', () {
    testWidgets('Dismiss all collapses Logbook rows bottom up', (tester) async {
      final entries = [
        for (var index = 1; index <= 3; index++)
          OperationCenterEntry(
            activityId: BigInt.from(index),
            state: OperationCenterState.failed,
            origin: OperationCenterOrigin.user,
            action: OperationCenterAction.fetch,
            startedAtUnixMs: BigInt.from(index * 1000),
            canCancel: false,
            canRetry: false,
            hasDetails: false,
          ),
      ];
      var shown = entries;
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return OperationCenterPanel(
                snapshot: OperationCenterSnapshot(
                  entries: shown,
                  runningCount: 0,
                  failedCount: shown.length,
                  attentionCount: 0,
                  truncated: false,
                ),
                workspace: const WorkspaceState(tabs: [], activeTabId: null),
                onClose: () {},
                onCancel: (_) {},
                onRetry: (_) {},
                onDismiss: (_) {},
                onDismissAll: () {},
              );
            },
          ),
        ),
      );
      await pumpFrames(tester, const Duration(milliseconds: 200));
      rebuild(() => shown = []);
      await tester.pump();
      final rows = tester
          .widgetList<MeridianRemovingRow>(find.byType(MeridianRemovingRow))
          .toList();
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.delay), [
        MeridianDurations.stagger * 2,
        MeridianDurations.stagger,
        Duration.zero,
      ]);
      await pumpFrames(tester, const Duration(milliseconds: 500));
      expect(find.byType(MeridianRemovingRow), findsNothing);
    });
  });

  group('Logbook dismissal', () {
    testWidgets(
      'a dismissed selection leaves expanded and passes to the next',
      (tester) async {
        final entries = [
          for (var index = 1; index <= 3; index++)
            OperationCenterEntry(
              activityId: BigInt.from(index),
              state: OperationCenterState.failed,
              origin: OperationCenterOrigin.user,
              action: OperationCenterAction.fetch,
              startedAtUnixMs: BigInt.from(index * 1000),
              canCancel: false,
              canRetry: false,
              hasDetails: false,
            ),
        ];
        var shown = entries;
        late StateSetter rebuild;
        await tester.pumpWidget(
          motionHost(
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return OperationCenterPanel(
                  snapshot: OperationCenterSnapshot(
                    entries: shown,
                    runningCount: 0,
                    failedCount: shown.length,
                    attentionCount: 0,
                    truncated: false,
                  ),
                  workspace: const WorkspaceState(tabs: [], activeTabId: null),
                  onClose: () {},
                  onCancel: (_) {},
                  onRetry: (_) {},
                  onDismiss: (_) {},
                  onDismissAll: () {},
                );
              },
            ),
          ),
        );
        await pumpFrames(tester, const Duration(milliseconds: 200));
        GitLamaTimelineRow row(int id) => tester.widget<GitLamaTimelineRow>(
          find.byKey(ValueKey('operation-${BigInt.from(id)}')),
        );
        await tester.tap(find.byKey(ValueKey('operation-${BigInt.two}')));
        await tester.pump();
        expect(row(2).selected, isTrue);

        rebuild(() => shown = [entries[0], entries[2]]);
        await tester.pump();
        final leaving = tester.widget<GitLamaTimelineRow>(
          find.descendant(
            of: find.byType(MeridianRemovingRow),
            matching: find.byType(GitLamaTimelineRow),
          ),
        );
        expect(leaving.selected, isTrue);
        expect(leaving.expanded, isNotNull);
        expect(row(3).selected, isTrue);
        expect(row(1).selected, isFalse);
        await pumpFrames(tester, const Duration(milliseconds: 500));
        expect(find.byType(MeridianRemovingRow), findsNothing);
      },
    );
  });

  group('NM-45', () {
    testWidgets('minimap marker follows scroll and click uses shared scroll', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        motionHost(
          SizedBox(
            height: 300,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 20,
                    itemCount: 100,
                    itemBuilder: (context, index) => Text('row $index'),
                  ),
                ),
                SizedBox(
                  width: GitLamaLayout.diffMinimapWidth,
                  child: DiffMinimap(
                    controller: controller,
                    totalRows: 100,
                    rows: const {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      DiffMinimapPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('diff-minimap-paint')),
                  )
                  .painter!
              as DiffMinimapPainter;
      expect(painter().offsetFraction, 0);
      controller.jumpTo(500);
      await tester.pump();
      expect(
        painter().offsetFraction,
        closeTo(500 / controller.position.maxScrollExtent, 0.001),
      );
      await tester.tapAt(
        tester.getBottomRight(find.byType(DiffMinimap)) - const Offset(2, 2),
      );
      await tester.pump();
      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );
    });
  });

  group('NM-75', () {
    testWidgets('Compass conflict count rolls to zero before collapsing', (
      tester,
    ) async {
      var conflicts = 1;
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Center(
                child: GitLamaCompass(
                  repository: 'Repo',
                  branch: 'main',
                  conflicts: conflicts,
                  onShowDetails: () {},
                ),
              );
            },
          ),
        ),
      );
      MeridianReveal conflictReveal() =>
          tester.widget<MeridianReveal>(find.byType(MeridianReveal).first);
      expect(conflictReveal().visible, isTrue);
      rebuild(() => conflicts = 0);
      await tester.pump();
      expect(conflictReveal().visible, isTrue);
      await tester.pump(const Duration(milliseconds: 199));
      expect(conflictReveal().visible, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(conflictReveal().visible, isFalse);
    });
  });

  group('NM-62 and NM-64', () {
    testWidgets('Logbook mark swaps on completion and detail reveals', (
      tester,
    ) async {
      var state = GitLamaTimelineState.running;
      var open = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return GitLamaTimelineRow(
                state: state,
                verb: 'Fetch',
                target: 'origin',
                metadata: '',
                time: 'now',
                onActivate: () {},
                expanded: open ? const Text('output') : null,
              );
            },
          ),
        ),
      );
      expect(find.byType(MeridianSpinner), findsOneWidget);
      rebuild(() {
        state = GitLamaTimelineState.succeeded;
        open = true;
      });
      await tester.pump();
      expect(find.byType(MeridianSwap), findsOneWidget);
      expect(find.byType(MeridianStrokeIcon), findsOneWidget);
      expect(find.byType(MeridianReveal), findsOneWidget);
      await pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.text('output'), findsOneWidget);
      rebuild(() => open = false);
      await tester.pump();
      expect(find.text('output'), findsOneWidget);
      await pumpFrames(tester, const Duration(milliseconds: 400));
      expect(find.text('output'), findsNothing);
    });
  });

  group('NM-63', () {
    testWidgets('an open Logbook row shakes once when it fails', (
      tester,
    ) async {
      var state = GitLamaTimelineState.running;
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return GitLamaTimelineRow(
                state: state,
                shakeOnFailure: true,
                verb: 'Push',
                target: 'origin',
                metadata: '',
                time: 'now',
                onActivate: () {},
              );
            },
          ),
        ),
      );
      expect(
        tester.widget<MeridianShake>(find.byType(MeridianShake)).trigger,
        0,
      );
      rebuild(() => state = GitLamaTimelineState.failed);
      await tester.pump();
      expect(
        tester.widget<MeridianShake>(find.byType(MeridianShake)).trigger,
        1,
      );
      await pumpFrames(tester, const Duration(milliseconds: 350));
      expect(
        tester.widget<MeridianShake>(find.byType(MeridianShake)).trigger,
        1,
      );
    });
  });

  group('NS01', () {
    Future<(ScrollController, BuildContext)> pumpList(
      WidgetTester tester, {
      bool reduced = false,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        motionHost(
          reduced: reduced,
          SizedBox(
            height: 200,
            child: Builder(
              builder: (c) {
                context = c;
                return ListView.builder(
                  controller: controller,
                  itemExtent: 20,
                  itemCount: 500,
                  itemBuilder: (context, i) => Text('line $i'),
                );
              },
            ),
          ),
        ),
      );
      return (controller, context);
    }

    testWidgets('gitlamaScrollTo animates a short distance', (tester) async {
      final (controller, context) = await pumpList(tester);
      unawaited(gitlamaScrollTo(controller, 150, context));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.offset, inExclusiveRange(0, 150));
      await pumpFrames(tester, const Duration(milliseconds: 250));
      expect(controller.offset, 150);
    });

    testWidgets('gitlamaScrollTo jumps more than a screen', (tester) async {
      final (controller, context) = await pumpList(tester);
      unawaited(gitlamaScrollTo(controller, 4000, context));
      await tester.pump();
      expect(controller.offset, 4000);
    });

    testWidgets('gitlamaScrollTo jumps under reduce motion', (tester) async {
      final (controller, context) = await pumpList(tester, reduced: true);
      unawaited(gitlamaScrollTo(controller, 150, context));
      await tester.pump();
      expect(controller.offset, 150);
    });

    test('slow motion applies a factor outside release builds', () {
      addTearDown(() => timeDilation = 1);
      applySlowMotion(factor: '5');
      expect(timeDilation, 5);
      applySlowMotion(factor: 'x');
      expect(timeDilation, 5);
      timeDilation = 1;
      applySlowMotion(factor: '');
      expect(timeDilation, 1);
    });

    testWidgets('the app theme uses the soft selection', (tester) async {
      await tester.pumpWidget(motionHost(const SizedBox()));
      final theme = MeridianTheme.of(tester.element(find.byType(SizedBox)));
      expect(theme.selection, MeridianSelectionStyle.soft);
      expect(
        buildAppTheme(Brightness.dark).extension<MeridianTheme>()!.selection,
        MeridianSelectionStyle.soft,
      );
    });
  });

  group('NS02', () {
    Widget graph({
      required List<HistoryGraphRow> rows,
      String? selected,
      int? selectedIndex,
      bool queryActive = false,
      String? attentionId,
      int attentionSequence = 0,
      void Function(HistoryMotion)? onMotion,
      bool reduced = false,
      ValueChanged<String>? onCopy,
    }) => motionHost(
      reduced: reduced,
      _GraphHarness(
        rows: rows,
        selected: selected,
        selectedIndex: selectedIndex,
        queryActive: queryActive,
        attentionId: attentionId,
        attentionSequence: attentionSequence,
        onMotion: onMotion,
        onCopy: onCopy,
      ),
    );
    final rows = [for (var i = 0; i < 12; i++) historyRow('c$i')];

    testWidgets('NM-31 the History selection bar glides; the row is clear', (
      tester,
    ) async {
      await tester.pumpWidget(
        graph(rows: rows, selected: 'c1', selectedIndex: 1),
      );
      expect(find.byType(MeridianSelectionFill), findsOneWidget);
      final start = tester.getRect(find.byType(MeridianSelectionFill)).top;
      await tester.pumpWidget(
        graph(rows: rows, selected: 'c3', selectedIndex: 3),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final mid = tester.getRect(find.byType(MeridianSelectionFill)).top;
      await pumpFrames(tester, const Duration(milliseconds: 300));
      final end = tester.getRect(find.byType(MeridianSelectionFill)).top;
      expect(mid, inExclusiveRange(start, end));
      expect(
        end,
        closeTo(
          tester.getRect(find.byKey(const ValueKey('history-row-c3'))).top,
          0.5,
        ),
      );
    });

    testWidgets('NM-31 multi-selection keeps per-row fills', (tester) async {
      await tester.pumpWidget(
        motionHost(
          HistoryGraphView(
            itemCount: rows.length,
            rowAt: (i) => rows[i],
            onSelected: (_) {},
            controller: ScrollController(),
            selectedIndex: 1,
            selectedObjectIds: const {'c1', 'c2'},
          ),
        ),
      );
      expect(find.byType(MeridianSelectionFill), findsNothing);
    });

    double rowOpacity(WidgetTester tester, String id) => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byKey(ValueKey('history-row-$id')),
                matching: find.byType(Opacity),
              )
              .at(1),
        )
        .opacity;

    testWidgets('NM-32 search dims non-matching rows over laneDim', (
      tester,
    ) async {
      final searched = [
        historyRow('m', searchMatch: true),
        historyRow('n', searchMatch: false),
      ];
      await tester.pumpWidget(graph(rows: searched));
      expect(rowOpacity(tester, 'n'), 1);
      await tester.pumpWidget(graph(rows: searched, queryActive: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(rowOpacity(tester, 'n'), inExclusiveRange(0.3, 1));
      await pumpFrames(tester, const Duration(milliseconds: 200));
      expect(rowOpacity(tester, 'n'), closeTo(0.3, 0.001));
      expect(rowOpacity(tester, 'm'), 1);
    });

    testWidgets('NM-32 search dims at once under reduce motion', (
      tester,
    ) async {
      final searched = [historyRow('n', searchMatch: false)];
      await tester.pumpWidget(graph(rows: searched, reduced: true));
      await tester.pumpWidget(
        graph(rows: searched, queryActive: true, reduced: true),
      );
      await tester.pump();
      expect(rowOpacity(tester, 'n'), closeTo(0.3, 0.001));
    });

    testWidgets('NM-33 a reached search match tints once', (tester) async {
      await tester.pumpWidget(graph(rows: rows));
      await tester.pumpWidget(
        graph(rows: rows, attentionId: 'c4', attentionSequence: 1),
      );
      await tester.pump();
      final state = tester.state<MeridianAttentionState>(
        find.byKey(const ValueKey('history-search-attention-c4')),
      );
      expect(state.progress, greaterThan(0.9));
      await pumpFrames(tester, const Duration(milliseconds: 950));
      expect(state.progress, 0);
    });

    testWidgets('NM-34 copying a hash shows Copied for copiedHold', (
      tester,
    ) async {
      final copied = <String>[];
      await tester.pumpWidget(graph(rows: rows, onCopy: copied.add));
      await tester.tap(find.text('c2'));
      await tester.pump();
      expect(copied, ['c2']);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Copied'), findsOneWidget);
      expect(find.text('c2'), findsNothing);
      await tester.pump(GitLamaMotion.copiedHold);
      await pumpFrames(tester, const Duration(milliseconds: 200));
      expect(find.text('Copied'), findsNothing);
      expect(find.text('c2'), findsOneWidget);
    });

    testWidgets('NM-35 a ref added on screen pops in; a removed one leaves', (
      tester,
    ) async {
      Widget build(List<String> refs) => graph(
        rows: [
          historyRow('c0', refs: refs),
          historyRow('c1'),
        ],
      );
      await tester.pumpWidget(build(const []));
      await tester.pumpWidget(build(const ['refs/tags/v1']));
      await tester.pump();
      final chip = find.ancestor(
        of: findRefName('v1'),
        matching: find.byType(Transform),
      );
      expect(
        tester.widget<Transform>(chip.first).transform.storage[0],
        lessThan(0.7),
      );
      await pumpFrames(tester, const Duration(milliseconds: 500));
      expect(
        tester.widget<Transform>(chip.first).transform.storage[0],
        closeTo(1, 0.01),
      );
      await tester.pumpWidget(build(const []));
      await tester.pump();
      expect(findRefName('v1'), findsOneWidget);
      await pumpFrames(tester, const Duration(milliseconds: 400));
      expect(findRefName('v1'), findsNothing);
    });

    testWidgets('NM-36 an inserted row slides the rows below from above', (
      tester,
    ) async {
      late HistoryMotion motion;
      await tester.pumpWidget(graph(rows: rows, onMotion: (m) => motion = m));
      final subject = find.text('Subject c2');
      final rest = tester.getRect(subject);
      motion.insertRow(0, reduced: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.getRect(subject).top, lessThan(rest.top));
      await pumpFrames(tester, const Duration(milliseconds: 250));
      expect(tester.getRect(subject).top, closeTo(rest.top, 0.01));
    });

    testWidgets('NM-37 the WIP node is static', (tester) async {
      await tester.pumpWidget(
        graph(
          rows: [
            historyRow('wip', shape: HistoryNodeShape.wip),
            historyRow('c1'),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('NM-38 loading rows breathe; loaded rows fade in', (
      tester,
    ) async {
      final loading = [historyRow('loading-0'), historyRow('c1')];
      await tester.pumpWidget(graph(rows: loading));
      expect(find.byType(MeridianSkeleton), findsWidgets);
      await tester.pumpWidget(
        graph(rows: [historyRow('c0'), historyRow('c1')]),
      );
      await tester.pump();
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byKey(const ValueKey('history-row-c0')),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, lessThan(1));
      await pumpFrames(tester, const Duration(milliseconds: 150));
      expect(fade.opacity.value, 1);
    });
  });

  group('NS03', () {
    Widget compass({
      String? branch = 'main',
      int dirty = 0,
      int ahead = 0,
      String? operation,
      bool reduced = false,
    }) => motionHost(
      reduced: reduced,
      Center(
        child: GitLamaCompass(
          repository: 'GitLama',
          branch: branch,
          dirty: dirty,
          ahead: ahead,
          operation: operation,
          onShowDetails: () {},
        ),
      ),
    );

    testWidgets('NM-01 the state and a running operation swap with a rise '
        'and the rule enters', (tester) async {
      await tester.pumpWidget(compass(ahead: 2));
      expect(find.byType(MeridianProgressBar), findsNothing);
      await tester.pumpWidget(compass(ahead: 2, operation: 'Fetching…'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('Fetching…'), findsOneWidget);
      expect(find.byType(GitLamaSyncBadge), findsOneWidget);
      final rule = find.byType(MeridianProgressBar);
      expect(rule, findsOneWidget);
      await pumpFrames(tester, const Duration(milliseconds: 200));
      expect(find.byType(GitLamaSyncBadge), findsNothing);
      // The operation ends: the rule fills, holds and fades, then goes.
      await tester.pumpWidget(compass(ahead: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MeridianProgressBar), findsOneWidget);
      await pumpFrames(tester, const Duration(milliseconds: 1000));
      expect(find.byType(MeridianProgressBar), findsNothing);
    });

    testWidgets('NM-02 a checkout swaps the branch and the pill follows', (
      tester,
    ) async {
      await tester.pumpWidget(compass());
      final width = tester.getSize(find.byType(GitLamaCompass)).width;
      await tester.pumpWidget(compass(branch: 'feature/motion-polish-long'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('main'), findsOneWidget);
      expect(find.text('feature/motion-polish-long'), findsOneWidget);
      final growing = tester.getSize(find.byType(GitLamaCompass)).width;
      await pumpFrames(tester, const Duration(milliseconds: 300));
      final end = tester.getSize(find.byType(GitLamaCompass)).width;
      expect(growing, inExclusiveRange(width, end));
      expect(find.text('main'), findsNothing);
    });

    testWidgets('NM-03 sync counts roll; NM-04 the dirty dot pops in', (
      tester,
    ) async {
      await tester.pumpWidget(compass(ahead: 1));
      await tester.pumpWidget(compass(ahead: 2, dirty: 3));
      await tester.pump();
      expect(find.byType(MeridianRollingNumber), findsNWidgets(2));
      final dot = tester.widget<Transform>(
        find
            .ancestor(of: find.text('●'), matching: find.byType(Transform))
            .first,
      );
      expect(dot.transform.storage[0], lessThan(0.5));
      await pumpFrames(tester, const Duration(milliseconds: 500));
      final settled = tester.widget<Transform>(
        find
            .ancestor(of: find.text('●'), matching: find.byType(Transform))
            .first,
      );
      expect(settled.transform.storage[0], closeTo(1, 0.01));
    });

    testWidgets('NM-04 the dirty dot does not pop on the first build', (
      tester,
    ) async {
      await tester.pumpWidget(compass(dirty: 3));
      final dot = tester.widget<Transform>(
        find
            .ancestor(of: find.text('●'), matching: find.byType(Transform))
            .first,
      );
      expect(dot.transform.storage[0], 1);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('NM-05 the Compass edge fades in on hover', (tester) async {
      await tester.pumpWidget(compass());
      AnimatedContainer pill() => tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(GitLamaCompass),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(pill().duration, MeridianDurations.hoverOut);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(GitLamaCompass)),
      );
      await tester.pump();
      expect(pill().duration, MeridianDurations.hover);
    });

    testWidgets('NM-10 to NM-12 toolbar nudges, refresh spin and Logbook '
        'badge', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget build({bool refreshing = false, int failed = 0}) => motionHost(
        SizedBox(
          width: 1400,
          child: WorkspaceToolbar(
            active: RepositoryTabState(
              id: 1,
              generation: 1,
              label: 'GitLama',
              phase: RepositoryTabPhase.open,
              session: RepositorySessionState(
                identity: RepositorySessionIdentity(
                  nativeId: BigInt.one,
                  generation: 1,
                ),
                snapshot: RepositorySnapshot(
                  revision: BigInt.zero,
                  phase: RepositoryPhase.ready,
                ),
              ),
            ),
            onCommand:
                (
                  id, {
                  force = false,
                  initialName,
                  initialTarget,
                  initialReference,
                }) {},
            operations: OperationCenterSnapshot(
              entries: const [],
              runningCount: 0,
              failedCount: failed,
              attentionCount: 0,
              truncated: false,
            ),
            operationsVisible: false,
            activityVisible: false,
            shortcuts: const {},
            compassKey: GlobalKey(),
            refreshing: refreshing,
          ),
        ),
      );
      await tester.pumpWidget(build());
      MeridianNudge nudgeOf(String label) => tester
          .widget<MeridianToolbarButton>(
            find.byWidgetPredicate(
              (w) => w is MeridianToolbarButton && w.label == label,
            ),
          )
          .nudge;
      expect(nudgeOf('Fetch…'), MeridianNudge.down);
      expect(nudgeOf('Pull…'), MeridianNudge.down);
      expect(nudgeOf('Push…'), MeridianNudge.up);
      final refresh = tester.widget<MeridianIconButton>(
        find.byWidgetPredicate(
          (w) => w is MeridianIconButton && w.icon == 'refresh',
        ),
      );
      expect(refresh.nudge, MeridianNudge.rotate);
      expect(refresh.spinning, isFalse);
      await tester.pumpWidget(build(refreshing: true, failed: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<MeridianIconButton>(
              find.byWidgetPredicate(
                (w) => w is MeridianIconButton && w.icon == 'refresh',
              ),
            )
            .spinning,
        isTrue,
      );
      final logbook = tester.widget<MeridianIconButton>(
        find.byWidgetPredicate(
          (w) => w is MeridianIconButton && w.icon == 'history',
        ),
      );
      expect(logbook.badge, 2);
      expect(logbook.badgeTone, MeridianCountTone.attention);
      await tester.pumpWidget(build());
      await pumpFrames(tester, const Duration(milliseconds: 800));
    });

    Widget tabs(
      List<(int, String, bool)> open,
      int active, {
      bool reduced = false,
    }) => motionHost(
      reduced: reduced,
      SizedBox(
        width: 900,
        child: GitLamaRepoTabs(
          workspace: WorkspaceState(
            tabs: [
              for (final (id, label, dirty) in open)
                RepositoryTabState(
                  id: id,
                  generation: 1,
                  label: label,
                  phase: RepositoryTabPhase.open,
                  session: RepositorySessionState(
                    identity: RepositorySessionIdentity(
                      nativeId: BigInt.from(id),
                      generation: 1,
                    ),
                    snapshot: RepositorySnapshot(
                      revision: BigInt.zero,
                      phase: RepositoryPhase.ready,
                      status: RepositoryStatus(
                        workingTree: dirty
                            ? WorkingTreeState.dirty
                            : WorkingTreeState.clean,
                        ahead: BigInt.zero,
                        behind: BigInt.zero,
                        entries: const [],
                        totalEntries: dirty ? BigInt.one : BigInt.zero,
                        entriesTruncated: false,
                        operations: const [],
                      ),
                    ),
                  ),
                ),
            ],
            activeTabId: active,
          ),
          onActivate: (_) {},
          onClose: (_) {},
          onMoveTab: (_, _, _) {},
          onOpenRepository: () {},
        ),
      ),
    );

    testWidgets('NM-13 the active repository pill glides', (tester) async {
      await tester.pumpWidget(tabs([(1, 'a', false), (2, 'b', false)], 1));
      Rect pill() =>
          tester.getRect(find.byKey(const ValueKey('tab-strip-indicator')));
      final start = pill();
      await tester.pumpWidget(tabs([(1, 'a', false), (2, 'b', false)], 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final mid = pill();
      await pumpFrames(tester, const Duration(milliseconds: 300));
      expect(mid.left, inExclusiveRange(start.left, pill().left));
    });

    testWidgets('NM-14 the tab dirty dot pops in and shrinks out', (
      tester,
    ) async {
      await tester.pumpWidget(tabs([(1, 'a', false)], 1));
      await tester.pumpWidget(tabs([(1, 'a', true)], 1));
      await tester.pump();
      final dot = find.byKey(const ValueKey('tab-dirty-dot'));
      final starting = tester.widget<Transform>(dot).transform.storage[0];
      expect(starting, lessThan(1));
      await pumpFrames(tester, const Duration(milliseconds: 500));
      expect(
        tester.widget<Transform>(dot).transform.storage[0],
        closeTo(1, 0.01),
      );
      await tester.pumpWidget(tabs([(1, 'a', false)], 1));
      await pumpFrames(tester, const Duration(milliseconds: 250));
      expect(dot, findsNothing);
    });

    testWidgets('the tab dirty dot sits next to a short label', (tester) async {
      await tester.pumpWidget(tabs([(1, 'a', true)], 1, reduced: true));
      await tester.pump();
      final label = find.text('a');
      final textEnd =
          tester.getTopLeft(label).dx +
          tester
              .renderObject<RenderParagraph>(label)
              .getMaxIntrinsicWidth(double.infinity);
      final dot = tester.getRect(find.byKey(const ValueKey('tab-dirty-dot')));
      expect(dot.left - textEnd, lessThanOrEqualTo(MeridianSpace.space2 + 1));
    });

    testWidgets('NM-14 dirty state snaps under reduce motion', (tester) async {
      final dot = find.byKey(const ValueKey('tab-dirty-dot'));
      await tester.pumpWidget(tabs([(1, 'a', false)], 1, reduced: true));
      await tester.pumpWidget(tabs([(1, 'a', true)], 1, reduced: true));
      await tester.pump();
      expect(tester.widget<Transform>(dot).transform.storage[0], 1);
      await tester.pumpWidget(tabs([(1, 'a', false)], 1, reduced: true));
      await tester.pump();
      expect(dot, findsNothing);
    });

    testWidgets('NM-15 an opened tab grows in and a closed tab collapses', (
      tester,
    ) async {
      await tester.pumpWidget(tabs([(1, 'a', false)], 1));
      await tester.pumpWidget(tabs([(1, 'a', false), (2, 'b', false)], 1));
      Finder pill(int id) => find.byKey(ValueKey(('tab-pill', id)));
      // While it grows the tab is clipped to less than its width.
      Rect slot(int id) => tester.getRect(
        find.ancestor(of: pill(id), matching: find.byType(ClipRect)).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(slot(2).width, lessThan(tester.getSize(pill(2)).width));
      await pumpFrames(tester, const Duration(milliseconds: 300));
      await tester.pumpWidget(tabs([(1, 'a', false)], 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(pill(2), findsOneWidget);
      expect(slot(2).width, lessThan(tester.getSize(pill(2)).width));
      await pumpFrames(tester, const Duration(milliseconds: 400));
      expect(pill(2), findsNothing);
    });
  });

  group('NS06', () {
    testWidgets('NM-50 status glyph flips at its midpoint', (tester) async {
      var status = 'M';
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return GitLamaFileRow(
                status: status,
                path: 'file.txt',
                onActivate: () {},
              );
            },
          ),
        ),
      );
      expect(
        tester
            .widget<GitLamaStatusGlyph>(find.byType(GitLamaStatusGlyph))
            .status,
        'M',
      );
      rebuild(() => status = 'A');
      await tester.pump();
      expect(
        tester
            .widget<GitLamaStatusGlyph>(find.byType(GitLamaStatusGlyph))
            .status,
        'M',
      );
      await pumpFrames(tester, MeridianDurations.quick ~/ 2);
      expect(
        tester
            .widget<GitLamaStatusGlyph>(find.byType(GitLamaStatusGlyph))
            .status,
        'A',
      );
      await pumpFrames(tester, MeridianDurations.quick ~/ 2);
      final scale = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(GitLamaStatusGlyph),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(scale.transform.entry(1, 1), closeTo(1, 0.01));
    });

    testWidgets('NM-50 reduced motion shows the new glyph immediately', (
      tester,
    ) async {
      var status = 'M';
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          reduced: true,
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return GitLamaFileRow(
                status: status,
                path: 'file.txt',
                onActivate: () {},
              );
            },
          ),
        ),
      );
      rebuild(() => status = 'A');
      await tester.pump();
      expect(
        tester
            .widget<GitLamaStatusGlyph>(find.byType(GitLamaStatusGlyph))
            .status,
        'A',
      );
    });
  });
}

/// A `HistoryGraphView` with its own motion and scroll controller.
class _GraphHarness extends StatefulWidget {
  const _GraphHarness({
    required this.rows,
    this.selected,
    this.selectedIndex,
    this.queryActive = false,
    this.attentionId,
    this.attentionSequence = 0,
    this.onMotion,
    this.onCopy,
  });

  final List<HistoryGraphRow> rows;
  final String? selected;
  final int? selectedIndex;
  final bool queryActive;
  final String? attentionId;
  final int attentionSequence;
  final void Function(HistoryMotion)? onMotion;
  final ValueChanged<String>? onCopy;

  @override
  State<_GraphHarness> createState() => _GraphHarnessState();
}

class _GraphHarnessState extends State<_GraphHarness>
    with TickerProviderStateMixin {
  late final HistoryMotion _motion = HistoryMotion(vsync: this);
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.onMotion?.call(_motion);
  }

  @override
  void dispose() {
    _motion.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 700,
    height: 400,
    child: HistoryGraphView(
      itemCount: widget.rows.length,
      rowAt: (i) => widget.rows[i],
      onSelected: (_) {},
      controller: _controller,
      motion: _motion,
      selectedObjectId: widget.selected,
      selectedIndex: widget.selectedIndex,
      queryActive: widget.queryActive,
      attentionObjectId: widget.attentionId,
      attentionSequence: widget.attentionSequence,
      copiedLabel: 'Copied',
      onCopyValue: widget.onCopy,
      metadataHashWidth: 120,
    ),
  );
}
