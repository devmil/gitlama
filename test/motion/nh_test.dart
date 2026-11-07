import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/app/workspace/changes_section.dart';
import 'package:gitlama/app/workspace/command_palette.dart';
import 'package:gitlama/app/workspace/shell_chrome.dart';
import 'package:gitlama/widgets/git_file_list/git_file_list.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/widgets/history_graph_view.dart';
import 'package:gitlama/widgets/history_motion.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';

import 'history_support.dart';
import 'motion_support.dart';

void main() {
  group('NH-5', () {
    testWidgets('last conflict changes the banner and delays Continue halo', (
      tester,
    ) async {
      var conflicted = true;
      late StateSetter rebuild;
      RepositoryTabState active() => RepositoryTabState(
        id: 1,
        generation: 1,
        label: 'Repo',
        phase: RepositoryTabPhase.open,
        session: RepositorySessionState(
          identity: RepositorySessionIdentity(
            nativeId: BigInt.one,
            generation: 1,
          ),
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            status: RepositoryStatus(
              workingTree: conflicted
                  ? WorkingTreeState.conflicted
                  : WorkingTreeState.clean,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: conflicted
                  ? [
                      RepositoryStatusEntry(
                        kind: StatusEntryKind.unmerged,
                        path: NativePathIdentity(
                          platform: NativePathPlatform.unix,
                          units: 'file.txt'.codeUnits,
                        ),
                        index: ChangeKind.updatedButUnmerged,
                        worktree: ChangeKind.updatedButUnmerged,
                      ),
                    ]
                  : const [],
              totalEntries: conflicted ? BigInt.one : BigInt.zero,
              entriesTruncated: false,
              operations: const [
                RepositoryOperationState(kind: RepositoryOperationKind.rebase),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RepositoryConditions(
                active: active(),
                onCommand:
                    (
                      id, {
                      initialName,
                      initialTarget,
                      initialReference,
                      force = false,
                    }) {},
              );
            },
          ),
        ),
      );
      expect(
        tester
            .widgetList<MeridianBanner>(find.byType(MeridianBanner))
            .any((banner) => banner.tone == MeridianBannerTone.attention),
        isTrue,
      );
      rebuild(() => conflicted = false);
      await tester.pump();
      expect(
        tester
            .widgetList<MeridianBanner>(find.byType(MeridianBanner))
            .any((banner) => banner.tone == MeridianBannerTone.success),
        isTrue,
      );
      expect(
        tester.widget<MeridianPulse>(find.byType(MeridianPulse)).active,
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<MeridianPulse>(find.byType(MeridianPulse)).active,
        isTrue,
      );
    });
  });

  group('NH-6', () {
    testWidgets('NH-6 running a command fades the palette out', (tester) async {
      const origin = Rect.fromLTWH(40, 30, 200, 40);
      var ran = false;
      await tester.pumpWidget(
        motionHost(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommandPalette<void>(
                context: context,
                originRect: origin,
                ranCommand: () => ran,
                builder: (context) => MeridianDialogSurface(
                  maxWidth: GitLamaLayout.paletteWidth,
                  child: SizedBox(
                    key: const ValueKey('command-palette'),
                    width: GitLamaLayout.paletteWidth,
                    height: 200,
                    child: TextButton(
                      onPressed: () {
                        ran = true;
                        Navigator.pop(context);
                      },
                      child: const Text('Run'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await pumpFrames(tester, const Duration(milliseconds: 320));
      final surface = find.byKey(const ValueKey('command-palette'));
      final atRest = tester.getRect(surface);
      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(ran, isTrue);
      expect(tester.getRect(surface), atRest);
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(of: surface, matching: find.byType(Opacity)),
            )
            .any((widget) => widget.opacity < 1),
        isTrue,
      );
      await pumpFrames(tester, MeridianDurations.dialog);
      expect(surface, findsNothing);
    });

    testWidgets('palette surface follows the route corner radius', (
      tester,
    ) async {
      const origin = Rect.fromLTWH(40, 30, 200, 40);
      await tester.pumpWidget(
        motionHost(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommandPalette<void>(
                context: context,
                originRect: origin,
                builder: (context) => const CommandPaletteDialog(
                  hasRepository: false,
                  disabledSelectionCommands: {},
                  shortcuts: {},
                  activeScopes: {},
                  customCommands: [],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      final surface = tester.widget<MeridianDialogSurface>(
        find.byType(MeridianDialogSurface),
      );
      expect(surface.borderRadius, isNotNull);
      await pumpFrames(tester, const Duration(milliseconds: 320));
      expect(
        tester
            .widget<MeridianDialogSurface>(find.byType(MeridianDialogSurface))
            .borderRadius,
        BorderRadius.circular(
          MeridianTheme.of(
            tester.element(find.byType(CommandPaletteDialog)),
          ).radius.lg,
        ),
      );
    });

    testWidgets('reduce motion uses the dialog fade for Compass opening', (
      tester,
    ) async {
      const origin = Rect.fromLTWH(40, 30, 200, 40);
      await tester.pumpWidget(
        motionHost(
          reduced: true,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommandPalette<void>(
                context: context,
                originRect: origin,
                builder: (context) => MeridianDialogSurface(
                  maxWidth: GitLamaLayout.paletteWidth,
                  child: SizedBox(
                    key: const ValueKey('reduced-palette'),
                    width: GitLamaLayout.paletteWidth,
                    height:
                        MediaQuery.sizeOf(context).height *
                        GitLamaLayout.paletteMaxHeightFraction,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      final rect = tester.getRect(
        find.byKey(const ValueKey('reduced-palette')),
      );
      expect(rect.width, closeTo(GitLamaLayout.paletteWidth, 1));
      expect(rect.center.dx, closeTo(400, 1));
    });

    testWidgets('Compass route morphs to the palette and keeps query focus', (
      tester,
    ) async {
      const origin = Rect.fromLTWH(40, 30, 200, 40);
      final query = TextEditingController();
      addTearDown(query.dispose);
      await tester.pumpWidget(
        motionHost(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showCommandPalette<void>(
                  context: context,
                  originRect: origin,
                  builder: (context) => MeridianDialogSurface(
                    maxWidth: GitLamaLayout.paletteWidth,
                    child: SizedBox(
                      key: const ValueKey('palette-test-surface'),
                      width: GitLamaLayout.paletteWidth,
                      height:
                          MediaQuery.sizeOf(context).height *
                          GitLamaLayout.paletteMaxHeightFraction,
                      child: TextField(controller: query, autofocus: true),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      final surface = find.byKey(const ValueKey('palette-test-surface'));
      final start = tester.getRect(surface);
      expect(start.left, closeTo(origin.left, 1));
      expect(start.top, closeTo(origin.top, 1));
      expect(start.width, closeTo(origin.width, 1));
      expect(start.height, closeTo(origin.height, 1));
      await tester.enterText(find.byType(TextField), 'status');
      expect(query.text, 'status');
      await pumpFrames(tester, const Duration(milliseconds: 320));
      final end = tester.getRect(surface);
      expect(end.width, closeTo(GitLamaLayout.paletteWidth, 1));
      expect(end.center.dx, closeTo(400, 1));
      expect(end.center.dy, closeTo(300, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester, const Duration(milliseconds: 250));
      expect(surface, findsNothing);
    });
  });

  group('NH-4', () {
    testWidgets('NH-4 several files enter without a flight', (tester) async {
      final sourceScroll = ScrollController();
      final destinationScroll = ScrollController();
      addTearDown(sourceScroll.dispose);
      addTearDown(destinationScroll.dispose);
      final entries = [
        for (final name in ['one.txt', 'two.txt', 'three.txt'])
          RepositoryStatusEntry(
            kind: StatusEntryKind.ordinary,
            path: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: name.codeUnits,
            ),
            index: ChangeKind.unmodified,
            worktree: ChangeKind.modified,
          ),
      ];
      var source = entries;
      var destination = <RepositoryStatusEntry>[];
      var sequence = 0;
      late StateSetter rebuild;
      Widget section(
        StagingSide side,
        List<RepositoryStatusEntry> items,
        ScrollController controller,
      ) => SizedBox(
        width: 500,
        height: 250,
        child: ChangesSection(
          title: side.name,
          side: side,
          stacked: true,
          mode: GitFileListMode.list,
          onModeChanged: (_) {},
          entries: items,
          mutationSequence: sequence,
          mutationSource: StagingSide.unstaged,
          movingKeys: sequence == 0 ? const {} : entries.map(changeKey).toSet(),
          controller: controller,
          selected: const {},
          busy: false,
          onSelectIdentity: (_) {},
          onSelectionChanged: (_) {},
          onSelected: () {},
          onAll: () {},
          onFiles: (_) {},
          onPartial: (_) {},
          onCreatePatch: (_) {},
          fileBrowserName: 'Files',
          onDropFiles: (_) {},
          onDiscardSelected: null,
          onDiscardFiles: null,
          onDiscardAll: null,
        ),
      );
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Column(
                children: [
                  section(StagingSide.unstaged, source, sourceScroll),
                  section(StagingSide.staged, destination, destinationScroll),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      rebuild(() {
        source = [];
        destination = entries;
        sequence = 1;
      });
      await tester.pump();
      expect(MeridianTravel.flying, isFalse);
      expect(find.byType(MeridianRemovingRow), findsNWidgets(3));
      expect(find.byType(MeridianEntrance), findsNWidgets(3));
      await pumpFrames(tester, const Duration(milliseconds: 700));
      expect(find.byType(MeridianRemovingRow), findsNothing);
    });

    testWidgets('NH-4 one visible file flies while its source collapses', (
      tester,
    ) async {
      final sourceScroll = ScrollController();
      final destinationScroll = ScrollController();
      addTearDown(sourceScroll.dispose);
      addTearDown(destinationScroll.dispose);
      final sourceKey = GlobalKey<ChangesSectionState>();
      final destinationKey = GlobalKey<ChangesSectionState>();
      final entry = RepositoryStatusEntry(
        kind: StatusEntryKind.ordinary,
        path: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: 'moving.txt'.codeUnits,
        ),
        index: ChangeKind.unmodified,
        worktree: ChangeKind.modified,
      );
      final movingKey = changeKey(entry);
      var source = [entry];
      var destination = <RepositoryStatusEntry>[];
      var sequence = 0;
      String? flightKey;
      late StateSetter rebuild;
      Widget section(
        StagingSide side,
        List<RepositoryStatusEntry> entries,
        ScrollController controller,
        GlobalKey<ChangesSectionState> key,
      ) => SizedBox(
        width: 500,
        height: 250,
        child: ChangesSection(
          key: key,
          title: side.name,
          side: side,
          stacked: true,
          mode: GitFileListMode.list,
          onModeChanged: (_) {},
          entries: entries,
          mutationSequence: sequence,
          mutationSource: StagingSide.unstaged,
          movingKeys: sequence == 0 ? const {} : {movingKey},
          flightKey: flightKey,
          controller: controller,
          selected: const {},
          busy: false,
          onSelectIdentity: (_) {},
          onSelectionChanged: (_) {},
          onSelected: () {},
          onAll: () {},
          onFiles: (_) {},
          onPartial: (_) {},
          onCreatePatch: (_) {},
          fileBrowserName: 'Files',
          onDropFiles: (_) {},
          onDiscardSelected: null,
          onDiscardFiles: null,
          onDiscardAll: null,
        ),
      );
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Column(
                children: [
                  section(
                    StagingSide.unstaged,
                    source,
                    sourceScroll,
                    sourceKey,
                  ),
                  section(
                    StagingSide.staged,
                    destination,
                    destinationScroll,
                    destinationKey,
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(destinationKey.currentState!.willShowEntry(entry), isTrue);
      expect(sourceKey.currentState!.captureEntry(entry), isTrue);
      rebuild(() {
        source = [];
        destination = [entry];
        sequence = 1;
        flightKey = movingKey;
      });
      await tester.pump();
      await tester.pump();
      expect(find.byType(MeridianRemovingRow), findsOneWidget);
      expect(find.byType(MeridianAttention), findsOneWidget);
      expect(MeridianTravel.flying, isTrue);
      await pumpFrames(tester, const Duration(milliseconds: 700));
      expect(MeridianTravel.flying, isFalse);
      expect(find.byType(MeridianRemovingRow), findsNothing);
    });
  });

  group('NH-2', () {
    testWidgets('NH-2 new visible rows enter and distant lanes stay drawn', (
      tester,
    ) async {
      late HistoryMotion motion;
      await tester.pumpWidget(
        motionHost(
          TestMotionHost(
            onReady: (value) => motion = value,
            childBuilder: (value) => SizedBox(
              height: 100,
              child: HistoryGraphView(
                itemCount: 1,
                rowAt: (_) => historyRow('fetched'),
                onSelected: (_) {},
                motion: value,
                syncEntranceIds: const {'fetched'},
                syncSequence: 1,
              ),
            ),
          ),
        ),
      );
      motion.drawLanes(0, 40, reduced: false);
      await tester.pump();
      expect(find.byType(MeridianEntrance), findsOneWidget);
      expect(motion.drawProgress(30), 1);
      await pumpFrames(tester, MeridianDurations.select);
      final entrance = tester.widget<MeridianEntrance>(
        find.byType(MeridianEntrance),
      );
      expect(entrance.entranceKey, ('history-sync-row', 'fetched', 1));
    });

    testWidgets('NH-2 changed user sync sweeps after the hold', (tester) async {
      var sequence = 0;
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
                  syncSequence: sequence,
                  syncChanged: true,
                  onShowDetails: () {},
                ),
              );
            },
          ),
        ),
      );
      rebuild(() => sequence++);
      await tester.pump();
      CompassGlintPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('compass-glint-paint')),
                  )
                  .painter!
              as CompassGlintPainter;
      final size = tester.getSize(
        find.byKey(const ValueKey('compass-glint-paint')),
      );
      expect(painter().centerX(size), -GitLamaMotion.glintWidth);
      await tester.pump(GitLamaMotion.syncGlintDelay);
      await tester.pump();
      expect(painter().centerX(size), -GitLamaMotion.glintWidth);
      await pumpFrames(tester, GitLamaMotion.glint ~/ 2);
      expect(painter().centerX(size), inExclusiveRange(0, size.width));
      await pumpFrames(tester, GitLamaMotion.glint ~/ 2);
      expect(
        painter().centerX(size),
        closeTo(size.width + GitLamaMotion.glintWidth, 1),
      );
    });

    testWidgets('NH-2 unchanged sync and reduce motion omit the glint', (
      tester,
    ) async {
      for (final (changed, reduced) in [(false, false), (true, true)]) {
        var sequence = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          motionHost(
            reduced: reduced,
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return GitLamaCompass(
                  repository: 'Repo',
                  branch: 'main',
                  syncSequence: sequence,
                  syncChanged: changed,
                  onShowDetails: () {},
                );
              },
            ),
          ),
        );
        rebuild(() => sequence++);
        await tester.pump();
        expect(find.byKey(const ValueKey('compass-glint-paint')), findsNothing);
      }
    });
  });

  group('NH-1', () {
    testWidgets('NH-1 committed staged rows collapse before the empty state', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final entry = RepositoryStatusEntry(
        kind: StatusEntryKind.ordinary,
        path: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: 'committed.txt'.codeUnits,
        ),
        index: ChangeKind.modified,
        worktree: ChangeKind.unmodified,
      );
      var entries = [entry];
      var sequence = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        motionHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                width: 500,
                height: 300,
                child: ChangesSection(
                  title: 'Staged',
                  side: StagingSide.staged,
                  stacked: true,
                  mode: GitFileListMode.list,
                  onModeChanged: (_) {},
                  entries: entries,
                  commitSequence: sequence,
                  controller: scroll,
                  selected: const {},
                  busy: false,
                  onSelectIdentity: (_) {},
                  onSelectionChanged: (_) {},
                  onSelected: () {},
                  onAll: () {},
                  onFiles: (_) {},
                  onPartial: (_) {},
                  onCreatePatch: (_) {},
                  fileBrowserName: 'Files',
                  onDropFiles: (_) {},
                  onDiscardSelected: null,
                  onDiscardFiles: null,
                  onDiscardAll: null,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('committed.txt'), findsOneWidget);
      rebuild(() {
        entries = [];
        sequence = 1;
      });
      await tester.pump();
      expect(find.byType(MeridianRemovingRow), findsOneWidget);
      expect(find.text('committed.txt'), findsOneWidget);
      await pumpFrames(tester, const Duration(milliseconds: 700));
      await tester.pump();
      expect(find.byType(MeridianRemovingRow), findsNothing);
    });

    testWidgets('NH-1 new commit node closes, fills and settles', (
      tester,
    ) async {
      late HistoryMotion motion;
      await tester.pumpWidget(
        motionHost(TestMotionHost(onReady: (value) => motion = value)),
      );
      motion.landCommit('new-head', reduced: false);
      await tester.pump();
      expect(motion.landing('new-head')!.ringClose, 0);
      expect(motion.landing('new-head')!.core, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(motion.landing('new-head')!.ringClose, inExclusiveRange(0, 1));
      await tester.pump(GitLamaMotion.landRingClose ~/ 2);
      expect(motion.landing('new-head')!.ringClose, 1);
      expect(motion.landing('new-head')!.core, 0);
      await tester.pump(const Duration(milliseconds: 120));
      expect(motion.landing('new-head')!.core, greaterThan(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(motion.landing('new-head')!.core, closeTo(1, 0.01));
      await pumpFrames(tester, const Duration(milliseconds: 400));
      expect(motion.landing('new-head'), isNull);
    });

    testWidgets('NH-1 reduce motion shows the settled node at once', (
      tester,
    ) async {
      late HistoryMotion motion;
      await tester.pumpWidget(
        motionHost(TestMotionHost(onReady: (value) => motion = value)),
      );
      motion.landCommit('new-head', reduced: true);
      expect(motion.landing('new-head'), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('NH-1 the row tints after 120 ms and does not replay', (
      tester,
    ) async {
      Widget graph({bool present = true, bool reduced = false}) => motionHost(
        reduced: reduced,
        SizedBox(
          height: 100,
          child: HistoryGraphView(
            itemCount: present ? 1 : 0,
            rowAt: (_) => historyRow('new-head', current: true),
            onSelected: (_) {},
            flashObjectId: 'new-head',
            flashSequence: 1,
          ),
        ),
      );
      final tint = find
          .descendant(
            of: find.byKey(const ValueKey('history-flash-new-head-1')),
            matching: find.byType(MeridianAttention),
          )
          .first;
      await tester.pumpWidget(graph());
      MeridianAttentionState state() =>
          tester.state<MeridianAttentionState>(tint);
      expect(state().progress, 0);
      await tester.pump(const Duration(milliseconds: 120));
      expect(state().progress, greaterThan(0.9));
      await pumpFrames(tester, const Duration(milliseconds: 900));
      expect(state().progress, 0);
      await tester.pumpWidget(graph(present: false));
      await tester.pumpWidget(graph());
      expect(state().progress, 0);
    });

    testWidgets('NH-1 the new HEAD chip rises when History opens', (
      tester,
    ) async {
      await tester.pumpWidget(
        motionHost(
          TestMotionHost(
            onReady: (motion) => motion.landCommit('new-head', reduced: false),
            childBuilder: (motion) => SizedBox(
              height: 100,
              child: HistoryGraphView(
                itemCount: 1,
                rowAt: (_) => historyRow(
                  'new-head',
                  current: true,
                  refs: const ['refs/heads/main'],
                ),
                checkedOutRef: 'refs/heads/main',
                onSelected: (_) {},
                flashObjectId: 'new-head',
                flashSequence: 4,
                motion: motion,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(MeridianEntrance), findsOneWidget);
    });
  });

  group('NH-3', () {
    Future<HistoryMotion> pumpMotion(WidgetTester tester) async {
      late HistoryMotion motion;
      await tester.pumpWidget(
        motionHost(TestMotionHost(onReady: (value) => motion = value)),
      );
      return motion;
    }

    HistoryLitFlags flags({required bool lit, bool active = true}) =>
        HistoryLitFlags(
          lit: lit,
          incomingLit: lit,
          segmentLit: const [null],
          lightingActive: active,
        );

    testWidgets('NH-3 lit rows flow down from the focused node and dim '
        'over laneDim', (tester) async {
      final motion = await pumpMotion(tester);
      for (var i = 0; i < 25; i++) {
        motion.observeLighting('c$i', i, flags(lit: false));
      }
      motion.lightingChanged(focusIndex: 0, active: true, reduced: false);
      for (var i = 0; i < 25; i++) {
        motion.observeLighting('c$i', i, flags(lit: true));
      }
      await tester.pump();
      // The focused row dims and lights at once, over laneDim.
      expect(motion.litTransition('c0')!.t, 0);
      await tester.pump(const Duration(milliseconds: 90));
      expect(motion.litTransition('c0')!.t, inExclusiveRange(0.4, 1));
      // Row 5 starts 60 ms later.
      await tester.pump(const Duration(milliseconds: 0));
      expect(motion.litTransition('c5')!.t, greaterThan(0));
      // Rows 20 below light together with row 16.
      expect(motion.litTransition('c20')!.t, motion.litTransition('c16')!.t);
      await tester.pump(const Duration(milliseconds: 100));
      expect(motion.litTransition('c0'), isNull);
      await tester.pump(const Duration(milliseconds: 300));
      expect(motion.litTransition('c20'), isNull);
    });

    testWidgets('NH-3 row 5 has not started at 50 ms', (tester) async {
      final motion = await pumpMotion(tester);
      motion.observeLighting('c5', 5, flags(lit: false));
      motion.lightingChanged(focusIndex: 0, active: true, reduced: false);
      motion.observeLighting('c5', 5, flags(lit: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(motion.litTransition('c5')!.t, 0);
      await tester.pump(const Duration(milliseconds: 40));
      expect(motion.litTransition('c5')!.t, greaterThan(0));
    });

    testWidgets('NH-3 leaving returns every row at once over hover-out', (
      tester,
    ) async {
      final motion = await pumpMotion(tester);
      motion.observeLighting('c9', 9, flags(lit: false));
      motion.lightingChanged(focusIndex: null, active: false, reduced: false);
      motion.observeLighting('c9', 9, flags(lit: true, active: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(motion.litTransition('c9')!.t, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(motion.litTransition('c9'), isNull);
    });

    testWidgets('NH-3 is instant under reduce motion and while scrubbing', (
      tester,
    ) async {
      final motion = await pumpMotion(tester);
      motion.observeLighting('c1', 1, flags(lit: false));
      motion.lightingChanged(focusIndex: 0, active: true, reduced: true);
      motion.observeLighting('c1', 1, flags(lit: true));
      expect(motion.litTransition('c1'), isNull);
      // Two changes within detailDebounce: the second is instant.
      await tester.pump(const Duration(seconds: 1));
      motion.lightingChanged(focusIndex: 0, active: true, reduced: false);
      motion.observeLighting('c1', 1, flags(lit: false));
      expect(motion.litTransition('c1'), isNotNull);
      await tester.pump(const Duration(milliseconds: 50));
      motion.lightingChanged(focusIndex: 0, active: true, reduced: false);
      motion.observeLighting('c1', 1, flags(lit: true));
      expect(motion.litTransition('c1'), isNull);
      expect(timeDilation, 1);
    });
  });
}
