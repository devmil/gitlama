import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/meridian_finders.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/widgets/history_graph_view.dart';
import 'package:gitlama/widgets/gitlama_scroll.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/gitlama_ref_chip.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  test('a reveal scrolls only to a row out of view, and centres it', () {
    double? reveal(int index, double pixels) => gitlamaRevealOffset(
      index: index,
      extent: 20,
      pixels: pixels,
      viewportDimension: 200,
      leadingPadding: 4,
    );
    // Below the padding, rows 0 to 8 are fully in view at the top.
    expect(reveal(0, 0), isNull);
    expect(reveal(8, 0), isNull);
    // Row 9 ends below the viewport; row 5 starts above it.
    expect(reveal(9, 0), 4 + 9 * 20 - 90);
    expect(reveal(5, 200), 4 + 5 * 20 - 90);
    expect(reveal(15, 200), isNull);
    expect(reveal(500, 0), 4 + 500 * 20 - 90);
  });

  testWidgets('the date column fits every date its format can show', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (built) {
              context = built;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final style = context.text.rowMeta;
      double width(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final result = painter.width;
        painter.dispose();
        return result;
      }

      final dates = [
        for (var day = 0; day < 365; day++)
          DateTime(2026, 1, 1).add(Duration(days: day)),
        DateTime(2026, 10, 2),
        DateTime(2088, 8, 8),
      ];
      final localizations = MaterialLocalizations.of(context);
      // Test fonts give every glyph one width, so also check that each
      // weekday and month pairing is measured; samples use two-digit days.
      String shape(String text) => text.replaceAll(RegExp('[0-9]+'), '0');
      for (final format in const ['local', 'relative']) {
        final shapes = historyDateColumnSamples(
          context,
          format,
        ).map(shape).toSet();
        for (final date in dates) {
          final text = localizations.formatMediumDate(date);
          expect(shapes, contains(shape(text)), reason: '$locale $text');
        }
      }
      for (final format in const ['iso', 'local', 'relative']) {
        final column = historyDateColumnWidth(context, format, style);
        for (final date in dates) {
          final text = format == 'iso'
              ? date.toIso8601String().substring(0, 10)
              : localizations.formatMediumDate(date);
          expect(
            width(text),
            lessThanOrEqualTo(column),
            reason: '$locale $format $text',
          );
        }
      }
    }
  });

  testWidgets('new head moves existing graph rows without recreating them', (
    tester,
  ) async {
    const geometry = HistoryRowGeometry(
      metadataLeft: 700,
      graphClipRight: 688,
      contentStart: 40,
      contentAvailable: 648,
    );
    Widget graph(List<String> ids) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: SizedBox(
        height: 300,
        child: HistoryGraphView(
          itemCount: ids.length,
          rowAt: (index) => HistoryGraphRow(
            objectId: ids[index],
            lane: 0,
            shape: HistoryNodeShape.commit,
            segments: const [],
            geometry: geometry,
          ),
          indexOfObjectId: (id) {
            final index = ids.indexOf(id);
            return index < 0 ? null : index;
          },
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(graph(const ['a', 'b', 'c']));
    final before = tester.element(find.byKey(const ValueKey('history-row-b')));
    await tester.pumpWidget(graph(const ['new', 'a', 'b', 'c']));
    expect(
      tester.element(find.byKey(const ValueKey('history-row-b'))),
      same(before),
    );
  });

  testWidgets('loading a distant selection preserves the revealed scrollable', (
    tester,
  ) async {
    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    Widget build(int? selectedIndex) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: SizedBox(
        height: 400,
        child: HistoryGraphView(
          controller: controller,
          itemCount: 2000,
          selectedIndex: selectedIndex,
          selectedObjectId: 'commit-1000',
          selectedObjectIds: const {'commit-1000'},
          rowExtent: 24,
          rowAt: (index) => HistoryGraphRow(
            objectId: 'commit-$index',
            lane: 0,
            shape: HistoryNodeShape.commit,
            segments: const [],
            geometry: const HistoryRowGeometry(
              metadataLeft: 700,
              graphClipRight: 688,
              contentStart: 40,
              contentAvailable: 648,
            ),
          ),
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(build(null));
    controller.jumpTo(24000);
    await tester.pump();
    final position = controller.position;
    await tester.pumpWidget(build(1000));
    await tester.pump();
    expect(controller.position, same(position));
    expect(controller.offset, 24000);
    await tester.pumpWidget(build(null));
    expect(controller.position, same(position));
  });

  testWidgets('explicit selection clears a stale navigation highlight', (
    tester,
  ) async {
    const ids = ['a', 'b', 'c'];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: ids.length,
            selectedObjectId: 'a',
            selectedObjectIds: const {'c'},
            rowAt: (index) => HistoryGraphRow(
              objectId: ids[index],
              compared: true,
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: const HistoryRowGeometry(
                metadataLeft: 700,
                graphClipRight: 688,
                contentStart: 40,
                contentAvailable: 648,
              ),
            ),
            onSelected: (_) {},
          ),
        ),
      ),
    );
    Semantics row(String id) => tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(ValueKey('history-row-$id')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(row('a').properties.selected, isFalse);
    expect(row('c').properties.selected, isTrue);
  });

  test('only configured remote upstreams at the same target are aligned', () {
    final refs = RepositoryRefs(
      branches: [
        RepositoryReference(
          name: utf8.encode('main'),
          target: 'a' * 40,
          upstream: utf8.encode('refs/remotes/origin/main'),
        ),
        RepositoryReference(
          name: utf8.encode('topic'),
          target: 'a' * 40,
          upstream: utf8.encode('refs/remotes/upstream/topic'),
        ),
        RepositoryReference(name: utf8.encode('untracked'), target: 'a' * 40),
        RepositoryReference(
          name: utf8.encode('feature'),
          target: 'a' * 40,
          upstream: utf8.encode('refs/remotes/origin/review'),
        ),
      ],
      remotes: [
        RepositoryRemote(
          name: utf8.encode('origin'),
          displayUrl: const [],
          branches: [
            RepositoryReference(name: utf8.encode('main'), target: 'a' * 40),
            RepositoryReference(
              name: utf8.encode('untracked'),
              target: 'a' * 40,
            ),
            RepositoryReference(name: utf8.encode('review'), target: 'a' * 40),
          ],
        ),
        RepositoryRemote(
          name: utf8.encode('upstream'),
          displayUrl: const [],
          branches: [
            RepositoryReference(name: utf8.encode('topic'), target: 'b' * 40),
          ],
        ),
      ],
    );
    expect(alignedHistoryUpstreams(refs), {
      'refs/heads/main': 'refs/remotes/origin/main',
      'refs/heads/feature': 'refs/remotes/origin/review',
    });
  });

  testWidgets('aligned branch and upstream share one cloud pill', (
    tester,
  ) async {
    String? copied;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            alignedUpstreams: alignedHistoryUpstreams(
              RepositoryRefs(
                branches: [
                  RepositoryReference(
                    name: utf8.encode('main'),
                    target: 'a' * 40,
                    upstream: utf8.encode('refs/remotes/origin/main'),
                  ),
                ],
                remotes: [
                  RepositoryRemote(
                    name: utf8.encode('origin'),
                    displayUrl: const [],
                    branches: [
                      RepositoryReference(
                        name: utf8.encode('main'),
                        target: 'a' * 40,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            rowAt: (_) => HistoryGraphRow(
              objectId: 'a' * 40,
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: const HistoryRowGeometry(
                metadataLeft: 700,
                graphClipRight: 688,
                contentStart: 40,
                contentAvailable: 648,
              ),
              refs: [
                utf8.encode('refs/remotes/origin/main'),
                utf8.encode('refs/heads/main'),
                utf8.encode('refs/tags/v1'),
              ],
              refCount: 3,
            ),
            onSelected: (_) {},
            onCopyValue: (value) => copied = value,
          ),
        ),
      ),
    );
    expect(findRefName('main'), findsOneWidget);
    expect(
      tester.widget<GitLamaRefChip>(find.byType(GitLamaRefChip).first).upstream,
      'origin/main',
    );
    expect(findRefName('v1'), findsOneWidget);
    expect(find.text('+1'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is MeridianIcon && widget.name == 'cloud',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('refs/heads/main\nrefs/remotes/origin/main'),
      findsOneWidget,
    );
    await tester.tap(findRefName('main'), buttons: kSecondaryMouseButton);
    expect(copied, 'refs/heads/main');
  });

  test('graph column follows the compact QSpline lane geometry', () {
    expect(historyGraphWidthForLaneCount(1), 31);
    expect(historyGraphWidthForLaneCount(5), 87);
    expect(historyGraphWidthForLaneCount(100), 1417);
    expect(historyLaneX(0), 9);
    expect(historyLaneX(5), 79);
    expect(
      historyRowContentStart(2, const [
        HistoryGraphSegment(
          fromLane: 2,
          toLane: 5,
          kind: HistorySegmentKind.merge,
        ),
      ]),
      95,
    );
  });

  testWidgets('100k history keeps a bounded fixed-extent widget window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var builds = 0;
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            controller: controller,
            itemCount: 100000,
            rowAt: (index) {
              builds += 1;
              return row(index, lane: index == 50000 ? 31 : index % 3);
            },
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(builds, lessThan(100));
    expect(
      find.byKey(const ValueKey('history-row-0000000000')),
      findsOneWidget,
    );
    builds = 0;
    controller.jumpTo(50000 * 24);
    await tester.pump();
    expect(builds, lessThan(100));
    expect(
      find.byKey(const ValueKey('history-row-0000050000')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('history-row-0000050000')));
    await tester.pump();
    expect(selected, '0000050000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('newly committed object receives the bounded accent flash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 2,
            rowAt: (index) => row(index, lane: index),
            onSelected: (_) {},
            flashObjectId: '0000000001',
            flashSequence: 7,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('history-flash-0000000001-7')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('history-flash-0000000000-7')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancestry lighting changes at the commit node', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 48,
            child: HistoryGraphView(
              itemCount: 2,
              rowExtent: 24,
              lightingActive: true,
              rowAt: (index) => HistoryGraphRow(
                objectId: 'node-$index',
                lane: 0,
                shape: HistoryNodeShape.commit,
                segments: index == 0
                    ? const []
                    : const [
                        HistoryGraphSegment(
                          fromLane: 0,
                          toLane: 0,
                          kind: HistorySegmentKind.straight,
                          startsAtTop: true,
                          endsAtCenter: true,
                          lit: false,
                        ),
                        HistoryGraphSegment(
                          fromLane: 1,
                          toLane: 1,
                          kind: HistorySegmentKind.straight,
                          startsAtTop: true,
                          lit: true,
                        ),
                      ],
                geometry: const HistoryRowGeometry(
                  metadataLeft: 300,
                  graphClipRight: 288,
                  contentStart: 56,
                  contentAvailable: 232,
                ),
                lit: index == 1,
              ),
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final laneColor = gitlamaColors(Brightness.light).series[0];
    final throughLaneColor = gitlamaColors(Brightness.light).series[1];
    expect(
      tester.renderObject(
        find.descendant(
          of: find.byKey(const ValueKey('history-row-node-1')),
          matching: find.byKey(const ValueKey('history-graph-paint')),
        ),
      ),
      paints
        ..path(color: laneColor.withValues(alpha: 0.3), strokeWidth: 2)
        ..path(color: throughLaneColor, strokeWidth: 2.5)
        ..circle(
          x: 9,
          y: 12,
          radius: 4.5,
          color: gitlamaColors(Brightness.light).pane,
        )
        ..circle(x: 9, y: 12, radius: 4.5, color: laneColor, strokeWidth: 2),
    );
  });

  testWidgets('row text outside the lit ancestry dims with its lanes', (
    tester,
  ) async {
    Widget build({required bool lighting}) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          height: 48,
          child: HistoryGraphView(
            itemCount: 2,
            rowExtent: 24,
            lightingActive: lighting,
            rowAt: (index) => HistoryGraphRow(
              objectId: 'node-$index',
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              subject: utf8.encode(
                index == 0 ? 'lit subject' : 'unlit subject',
              ),
              author: utf8.encode(index == 0 ? 'Ada' : 'Grace'),
              geometry: const HistoryRowGeometry(
                metadataLeft: 300,
                graphClipRight: 288,
                contentStart: 56,
                contentAvailable: 232,
              ),
              lit: index == 0,
            ),
            onSelected: (_) {},
          ),
        ),
      ),
    );
    double opacityOf(String text) => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Opacity))
              .first,
        )
        .opacity;

    await tester.pumpWidget(build(lighting: true));
    expect(opacityOf('lit subject'), 1);
    expect(opacityOf('Ada'), 1);
    expect(opacityOf('unlit subject'), GitLamaOpacity.unlitText);
    expect(opacityOf('Grace'), GitLamaOpacity.unlitText);

    await tester.pumpWidget(build(lighting: false));
    expect(opacityOf('unlit subject'), 1);
    expect(opacityOf('Grace'), 1);
  });

  testWidgets('working-tree marker masks its outgoing edge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 24,
            child: HistoryGraphView(
              itemCount: 1,
              rowExtent: 24,
              rowAt: (_) => const HistoryGraphRow(
                objectId: 'wip',
                lane: 0,
                shape: HistoryNodeShape.wip,
                segments: [
                  HistoryGraphSegment(
                    fromLane: 0,
                    toLane: 0,
                    kind: HistorySegmentKind.straight,
                  ),
                ],
                geometry: HistoryRowGeometry(
                  metadataLeft: 300,
                  graphClipRight: 288,
                  contentStart: 40,
                  contentAvailable: 248,
                ),
              ),
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.renderObject(
        find.descendant(
          of: find.byKey(const ValueKey('history-row-wip')),
          matching: find.byKey(const ValueKey('history-graph-paint')),
        ),
      ),
      paints
        ..path(
          color: gitlamaColors(Brightness.light).series[0],
          strokeWidth: 2.5,
        )
        ..arc(color: gitlamaColors(Brightness.light).inkMuted, strokeWidth: 2),
    );
  });

  testWidgets('empty text and dense clipped lanes preserve pinned metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => HistoryGraphRow(
              objectId: '1234567890abcdef',
              lane: 40,
              shape: HistoryNodeShape.merge,
              segments: const [
                HistoryGraphSegment(
                  fromLane: 40,
                  toLane: 1,
                  kind: HistorySegmentKind.octopus,
                ),
              ],
              geometry: const HistoryRowGeometry(
                metadataLeft: 192,
                graphClipRight: 180,
                contentStart: 660,
                contentAvailable: 0,
              ),
              author: utf8.encode('A very long author that must elide'),
              authorTime: 1789776000,
            ),
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('1234567890'), findsOneWidget);
    expect(find.text('2026-09-19'), findsOneWidget);
    await tester.tap(find.text('1234567890'));
    await tester.pump();
    expect(selected, '1234567890abcdef');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned metadata follows Author, SHA, Date order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => HistoryGraphRow(
              objectId: '1234567890abcdef',
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: const HistoryRowGeometry(
                metadataLeft: 520,
                graphClipRight: 508,
                contentStart: 40,
                contentAvailable: 468,
              ),
              author: utf8.encode('Fixture Author'),
              authorTime: 1789776000,
            ),
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final authorX = tester.getCenter(find.text('Fixture Author')).dx;
    final hashX = tester.getCenter(find.text('1234567890')).dx;
    final dateX = tester.getCenter(find.text('2026-09-19')).dx;
    expect(authorX, lessThan(hashX));
    expect(hashX, lessThan(dateX));
  });

  testWidgets('elided row actions copy full values without selecting the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final copied = <String>[];
    String? selected;
    const objectId = '1234567890abcdef1234567890abcdef12345678';
    const author = 'A very long author whose complete value stays available';
    const reference = 'refs/heads/feature/full-reference-value';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => HistoryGraphRow(
              objectId: objectId,
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: const HistoryRowGeometry(
                metadataLeft: 650,
                graphClipRight: 638,
                contentStart: 40,
                contentAvailable: 598,
              ),
              subject: utf8.encode('Copy actions'),
              author: utf8.encode(author),
              refs: [utf8.encode(reference)],
              refCount: 1,
              authorTime: 1789776000,
            ),
            onSelected: (value) => selected = value,
            onCopyValue: copied.add,
          ),
        ),
      ),
    );

    expect(find.text(reference), findsNothing);
    for (final visible in [author, '1234567890', '2026-09-19']) {
      await tester.tap(find.text(visible));
      await tester.pump();
    }
    await tester.tap(find.byTooltip(reference).first);
    await tester.pump();
    expect(copied, contains(reference));
    expect(copied, contains(author));
    expect(copied, contains(objectId));
    expect(copied.any((value) => value.startsWith('2026-09-19T')), isTrue);
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modifier click toggles ordered selection', (tester) async {
    String? replaced;
    String? toggled;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => row(1, lane: 0),
            onSelected: (value) => replaced = value,
            onToggleSelected: (value) => toggled = value,
          ),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byKey(const ValueKey('history-row-0000000001')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(toggled, '0000000001');
    expect(replaced, isNull);
  });

  testWidgets('ref activation emits an explicit reveal and keeps copy', (
    tester,
  ) async {
    String? revealed;
    String? copied;
    const reference = 'refs/heads/main';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => HistoryGraphRow(
              objectId: 'abcdef1234567890',
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: const HistoryRowGeometry(
                metadataLeft: 700,
                graphClipRight: 688,
                contentStart: 40,
                contentAvailable: 648,
              ),
              refs: [
                utf8.encode(reference),
                utf8.encode('refs/remotes/origin/main'),
                utf8.encode('refs/tags/v1.0.0'),
              ],
              refCount: 3,
              current: true,
            ),
            onSelected: (_) {},
            onRevealObjectId: (value) => revealed = value,
            onCopyValue: (value) => copied = value,
            headLabel: 'HEAD',
            checkedOutRef: reference,
          ),
        ),
      ),
    );
    expect(find.text('HEAD'), findsNothing);
    expect(findRefName('main'), findsOneWidget);
    expect(findRefName('origin/main'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.byTooltip('refs/tags/v1.0.0'), findsOneWidget);
    expect(find.text(reference), findsNothing);
    await tester.tap(findRefName('main'));
    expect(revealed, 'abcdef1234567890');
    expect(copied, isNull);
    await tester.tap(findRefName('main'), buttons: kSecondaryMouseButton);
    expect(copied, reference);
  });

  testWidgets('secondary click requests a context menu for the exact row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 2,
            rowAt: (index) => row(index, lane: index),
            onSelected: (_) {},
            onContextMenu: (value) => const [],
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('history-row-0000000001')),
        matching: find.byType(GitLamaContextMenuWidget),
      ),
      findsOneWidget,
    );
  });
}

HistoryGraphRow row(int index, {required int lane}) => HistoryGraphRow(
  objectId: index.toString().padLeft(10, '0'),
  lane: lane,
  shape: index % 17 == 0 ? HistoryNodeShape.merge : HistoryNodeShape.commit,
  segments: [
    HistoryGraphSegment(
      fromLane: lane,
      toLane: index == 0 ? lane : (lane + 1) % 4,
      kind: HistorySegmentKind.join,
    ),
  ],
  geometry: const HistoryRowGeometry(
    metadataLeft: 818,
    graphClipRight: 806,
    contentStart: 72,
    contentAvailable: 734,
  ),
  subject: utf8.encode(index.isEven ? 'Commit $index' : ''),
  author: utf8.encode('Fixture'),
  authorTime: 1789776000,
);
