@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/widgets/history_graph_view.dart';

import 'support/visual_capture.dart';

void main() {
  if (const bool.fromEnvironment('CAPTURE_UI_REVIEW')) {
    setUpAll(() async {
      final mono = FontLoader('packages/meridian_ui/JetBrains Mono')
        ..addFont(
          rootBundle.load(
            'packages/meridian_ui/assets/fonts/JetBrainsMono-Regular.ttf',
          ),
        );
      await mono.load();
      const fontPath = String.fromEnvironment('UI_REVIEW_FONT');
      if (fontPath.isNotEmpty) {
        final body = FontLoader('Roboto')
          ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        await body.load();
      }
    });
  }
  final viewports = <(String, Size, double)>[
    ('compact-minimum', const Size(900, 600), 1),
    ('laptop', const Size(1280, 720), 1),
    ('desktop', const Size(1440, 900), 1),
    ('wide', const Size(1920, 1080), 1),
    ('desktop-scaled', const Size(1440, 900), 1.3),
  ];

  for (final (viewport, size, scale) in viewports) {
    for (final brightness in Brightness.values) {
      for (final density in gitlamaDensities) {
        const capture = bool.fromEnvironment('CAPTURE_UI_REVIEW');
        final golden = capture
            ? '../build/evidence/meridian/M10-history-${brightness.name}.png'
            : '../build/evidence/p04-w02/graph-$viewport-${brightness.name}-${density.name}.png';
        testWidgets(
          '$viewport ${brightness.name} ${density.name}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(brightness, density: density),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: MeridianSurfaceScope(
                    focused: const bool.fromEnvironment('CAPTURE_UI_REVIEW'),
                    child: const Scaffold(body: _GraphCapture()),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            await expectLater(find.byType(Scaffold), matchesGoldenFile(golden));
          },
          skip:
              (capture &&
                  !(viewport == 'laptop' &&
                      density == MeridianDensity.regular)) ||
              visualCaptureSkip(golden),
        );
      }
    }
  }

  test('fixture covers dense topology and every exceptional primitive', () {
    final rows = [
      for (var index = 0; index < 24; index += 1) _fixtureRow(index),
    ];
    final segments = rows.expand((row) => row.segments).toList();
    expect(rows.map((row) => row.lane).toSet(), containsAll([0, 1, 2, 3, 4]));
    expect(
      segments.map((segment) => segment.kind).toSet(),
      containsAll([
        HistorySegmentKind.straight,
        HistorySegmentKind.join,
        HistorySegmentKind.merge,
        HistorySegmentKind.octopus,
        HistorySegmentKind.boundary,
        HistorySegmentKind.missing,
        HistorySegmentKind.collapsedMerge,
      ]),
    );
    expect(
      segments.where((segment) => segment.startsAtTop).length,
      greaterThan(20),
    );
    expect(
      rows,
      contains(predicate<HistoryGraphRow>((row) => row.refCount > 2)),
    );
    expect(
      rows.map((row) => row.shape).toSet(),
      containsAll(HistoryNodeShape.values),
    );
  });
}

class _GraphCapture extends StatelessWidget {
  const _GraphCapture();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tokens = MeridianTheme.of(context);
      final metadataLeft = constraints.maxWidth * 0.62;
      return HistoryGraphView(
        itemCount: 80,
        rowExtent: tokens.density.rowExtent,
        selectedObjectId: _fixtureRow(2).objectId,
        lightingActive: true,
        headLabel: 'HEAD',
        checkedOutRef: 'refs/heads/main',
        onSelected: (_) {},
        onCopyValue: (_) {},
        rowAt: (index) {
          final fixture = _fixtureRow(index);
          return HistoryGraphRow(
            objectId: fixture.objectId,
            lane: fixture.lane,
            shape: fixture.shape,
            segments: fixture.segments,
            geometry: HistoryRowGeometry(
              metadataLeft: metadataLeft,
              graphClipRight: metadataLeft - 12,
              contentStart: historyGraphWidthForLaneCount(5),
              contentAvailable:
                  (metadataLeft - historyGraphWidthForLaneCount(5) - 12).clamp(
                    0,
                    constraints.maxWidth,
                  ),
            ),
            subject: fixture.subject,
            author: fixture.author,
            refs: fixture.refs,
            refCount: fixture.refCount,
            authorTime: fixture.authorTime,
            lit: fixture.lit,
            current: fixture.current,
          );
        },
      );
    },
  );
}

HistoryGraphRow _fixtureRow(int index) {
  final position = index % 24;
  final segments = <HistoryGraphSegment>[
    const HistoryGraphSegment(
      fromLane: 0,
      toLane: 0,
      kind: HistorySegmentKind.straight,
      startsAtTop: true,
    ),
  ];
  if (position == 0) {
    segments.addAll(const [
      HistoryGraphSegment(
        fromLane: 0,
        toLane: 1,
        kind: HistorySegmentKind.merge,
      ),
      HistoryGraphSegment(
        fromLane: 0,
        toLane: 3,
        kind: HistorySegmentKind.octopus,
      ),
    ]);
  }
  if (position >= 1 && position < 6) {
    segments.add(_continuation(1, endsAtCenter: position == 5));
  }
  if (position == 4) {
    segments.add(
      const HistoryGraphSegment(
        fromLane: 1,
        toLane: 2,
        kind: HistorySegmentKind.merge,
      ),
    );
  }
  if (position >= 1 && position < 10) {
    segments.add(_continuation(3, endsAtCenter: position == 9));
  }
  if (position >= 5 && position < 8) {
    segments.add(_continuation(2, endsAtCenter: position == 7));
  }
  if (position == 5) {
    segments.add(
      const HistoryGraphSegment(
        fromLane: 1,
        toLane: 0,
        kind: HistorySegmentKind.join,
      ),
    );
  }
  if (position == 7) {
    segments.add(
      const HistoryGraphSegment(
        fromLane: 2,
        toLane: 0,
        kind: HistorySegmentKind.join,
      ),
    );
  }
  if (position == 9) {
    segments.add(
      const HistoryGraphSegment(
        fromLane: 3,
        toLane: 0,
        kind: HistorySegmentKind.join,
      ),
    );
  }
  if (position == 12) {
    segments.addAll(const [
      HistoryGraphSegment(
        fromLane: 4,
        toLane: 4,
        kind: HistorySegmentKind.missing,
      ),
      HistoryGraphSegment(
        fromLane: 4,
        toLane: 2,
        kind: HistorySegmentKind.boundary,
      ),
    ]);
  }
  if (position == 16) {
    segments.add(
      const HistoryGraphSegment(
        fromLane: 0,
        toLane: 2,
        kind: HistorySegmentKind.collapsedMerge,
      ),
    );
  }
  final lane = switch (position) {
    1 || 3 || 4 || 5 => 1,
    2 || 6 || 9 => 3,
    7 => 2,
    12 => 4,
    _ => 0,
  };
  final shape = switch (position) {
    0 || 4 => HistoryNodeShape.merge,
    12 => HistoryNodeShape.boundary,
    16 => HistoryNodeShape.graft,
    18 => HistoryNodeShape.stash,
    20 => HistoryNodeShape.replace,
    22 => HistoryNodeShape.wip,
    23 => HistoryNodeShape.wipConflict,
    _ => HistoryNodeShape.commit,
  };
  return HistoryGraphRow(
    objectId: position == 22
        ? historyWorktreeObjectId
        : index.toRadixString(16).padLeft(40, '0'),
    lane: lane,
    shape: shape,
    segments: segments,
    geometry: _unusedGeometry,
    subject: utf8.encode(switch (shape) {
      HistoryNodeShape.wip => 'Uncommitted changes · 3 files · 1 staged',
      HistoryNodeShape.wipConflict => 'Conflicts · 2 files · open resolver',
      HistoryNodeShape.stash => 'WIP on main: Mainline change ${index - 1}',
      _ =>
        lane == 0
            ? 'Mainline change $index'
            : 'Refine graph topology lane $lane',
    }),
    author: utf8.encode(index.isEven ? 'Ada Lovelace' : 'Grace Hopper'),
    refs: position == 0
        ? [
            utf8.encode(
              index == 0 ? 'refs/heads/main' : 'refs/heads/release/$index',
            ),
            utf8.encode('refs/remotes/origin/release/$index'),
          ]
        : shape == HistoryNodeShape.stash
        ? [utf8.encode('refs/stash')]
        : const [],
    refCount: position == 0 ? 5 : 0,
    authorTime: 1789776000 - index * 3600,
    lit: position <= 9,
    current: index == 0,
  );
}

HistoryGraphSegment _continuation(int lane, {required bool endsAtCenter}) =>
    HistoryGraphSegment(
      fromLane: lane,
      toLane: lane,
      kind: HistorySegmentKind.straight,
      startsAtTop: true,
      endsAtCenter: endsAtCenter,
    );

const _unusedGeometry = HistoryRowGeometry(
  metadataLeft: 0,
  graphClipRight: 0,
  contentStart: 0,
  contentAvailable: 0,
);
