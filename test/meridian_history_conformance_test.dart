import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/meridian_finders.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/widgets/history_graph_view.dart';
import 'package:gitlama/widgets/gitlama_ref_chip.dart';
import 'package:gitlama/widgets/hosting_status.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';

void main() {
  const row = HistoryGraphRow(
    objectId: '1234567890abcdef',
    lane: 0,
    shape: HistoryNodeShape.commit,
    segments: [],
    geometry: HistoryRowGeometry(
      metadataLeft: 570,
      graphClipRight: 558,
      contentStart: 40,
      contentAvailable: 518,
    ),
    selected: true,
  );

  for (final density in gitlamaDensities) {
    testWidgets('History row uses ${density.name} density extent', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light, density: density),
          home: Scaffold(
            body: HistoryGraphView(
              itemCount: 1,
              rowExtent: density.rowExtent,
              rowAt: (_) => row,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('history-row-1234567890abcdef')))
            .height,
        density.rowExtent,
      );
    });
  }

  for (final focused in [false, true]) {
    testWidgets('selected History fill stays soft with island focus $focused', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: MeridianSurfaceScope(
              focused: focused,
              child: HistoryGraphView(
                itemCount: 1,
                rowAt: (_) => row,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      final fills = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const ValueKey('history-row-1234567890abcdef')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.color);
      // GitLama's soft selection is `accent-soft` with or without
      // island focus.
      expect(fills, contains(gitlamaColors(Brightness.light).accentSoft));
    });
  }

  for (final kind in GitLamaRefKind.values) {
    testWidgets('${kind.name} ref chip follows Meridian colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: GitLamaRefChip(name: 'main', kind: kind),
            ),
          ),
        ),
      );
      final chip = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GitLamaRefChip),
              matching: find.byType(Container),
            )
            .first,
      );
      final fill = (chip.decoration! as BoxDecoration).color;
      final expected = switch (kind) {
        GitLamaRefKind.head => gitlamaColors(Brightness.light).ink,
        GitLamaRefKind.local => gitlamaColors(Brightness.light).accentSoft,
        GitLamaRefKind.tag => GitLamaGitColors.light.tagBg,
        _ => Colors.transparent,
      };
      expect(fill, expected);
      expect(
        tester.getSize(find.byType(GitLamaRefChip)).height,
        GitLamaLayout.refChipHeight,
      );
    });
  }

  test('lane positions use the 9 + 14n Meridian rule', () {
    expect(
      [for (var lane = 0; lane < 8; lane++) historyLaneX(lane)],
      [9, 23, 37, 51, 65, 79, 93, 107],
    );
  });

  testWidgets('only the checked-out local branch uses the HEAD chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            checkedOutRef: 'refs/heads/feature',
            rowAt: (_) => HistoryGraphRow(
              objectId: '1234567890abcdef',
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: const HistoryRowGeometry(
                metadataLeft: 570,
                graphClipRight: 558,
                contentStart: 40,
                contentAvailable: 518,
              ),
              current: true,
              refs: [
                utf8.encode('refs/heads/main'),
                utf8.encode('refs/heads/feature'),
              ],
            ),
            onSelected: (_) {},
          ),
        ),
      ),
    );
    final chips = tester
        .widgetList<GitLamaRefChip>(find.byType(GitLamaRefChip))
        .toList();
    expect(chips.map((chip) => (chip.name, chip.kind)), [
      ('feature', GitLamaRefKind.head),
      ('main', GitLamaRefKind.local),
    ]);
  });

  testWidgets('a ref chip hugs its name and keeps both ends of a long one', (
    tester,
  ) async {
    Widget chips(List<String> names) => MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Row(
          children: [
            for (final name in names)
              GitLamaRefChip(name: name, kind: GitLamaRefKind.remote),
          ],
        ),
      ),
    );
    const long = 'origin/feature/very-long-branch-name-for-a-route-dialog-🙂';
    await tester.pumpWidget(chips(const ['origin/main', long]));
    final sizes = [
      for (final chip in find.byType(GitLamaRefChip).evaluate())
        tester.getSize(find.byWidget(chip.widget)),
    ];
    // A short name does not reserve the maximum width.
    expect(sizes[0].width, lessThan(sizes[1].width));
    expect(sizes[0].width, lessThan(GitLamaLayout.refChipMaxWidth));
    expect(sizes[1].width, lessThanOrEqualTo(GitLamaLayout.refChipMaxWidth));
    final shown = tester
        .renderObjectList<RenderMeridianMiddleEllipsis>(
          find.byType(MeridianMiddleEllipsis),
        )
        .map((render) => render.shownText)
        .toList();
    expect(shown[0], 'origin/main');
    expect(shown[1], startsWith('origin/'));
    expect(shown[1], contains('…'));
    expect(shown[1], endsWith('🙂'));
    // The shortened name fills the chip instead of leaving it half empty.
    expect(sizes[1].width, greaterThan(GitLamaLayout.refChipMaxWidth - 24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('metadata remains pinned at 900 px and 130% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: HistoryGraphView(
              itemCount: 1,
              rowAt: (_) => HistoryGraphRow(
                objectId: '1234567890abcdef',
                lane: 6,
                shape: HistoryNodeShape.commit,
                segments: const [],
                geometry: const HistoryRowGeometry(
                  metadataLeft: 520,
                  graphClipRight: 508,
                  contentStart: 109,
                  contentAvailable: 399,
                ),
                author: utf8.encode('A long author name'),
                authorTime: 1789776000,
              ),
              metadataAuthorWidth: 132,
              metadataHashWidth: 90,
              metadataDateWidth: 125,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final hash = find.text('1234567890');
    expect(
      tester.widget<Text>(hash).style?.fontFamily,
      gitlamaText.code.fontFamily,
    );
    expect(
      tester.widget<Text>(hash).style?.fontSize,
      gitlamaText.codeSm.fontSize,
    );
    expect(tester.getTopLeft(hash).dx, greaterThan(520));
    expect(tester.getTopRight(find.text('2026-09-19')).dx, lessThan(900));
  });

  testWidgets('end footer occupies the row after the final commit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 84,
            child: HistoryGraphView(
              itemCount: 2,
              rowExtent: 28,
              rowAt: (index) => index == 0
                  ? row
                  : const HistoryGraphRow(
                      objectId: 'second',
                      lane: 0,
                      shape: HistoryNodeShape.commit,
                      segments: [],
                      geometry: HistoryRowGeometry(
                        metadataLeft: 570,
                        graphClipRight: 558,
                        contentStart: 40,
                        contentAvailable: 518,
                      ),
                    ),
              onSelected: (_) {},
              footer: const Text('End of history'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('End of history'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('End of history')).dy,
      greaterThanOrEqualTo(
        tester
                .getTopLeft(
                  find.byKey(const ValueKey('history-row-1234567890abcdef')),
                )
                .dy +
            28,
      ),
    );
  });

  testWidgets('a branch chip is followed by its open pull request', (
    tester,
  ) async {
    final opened = <int>[];
    const pull = HistoryReferencePullRequest(
      number: 5604,
      title: 'Find on map',
      checks: HostingCheckState.passing,
      webUrl: 'https://github.example/team/project/pull/5604',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => HistoryGraphRow(
              objectId: row.objectId,
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: row.geometry,
              refs: [
                utf8.encode('refs/heads/topic'),
                utf8.encode('refs/tags/v1'),
              ],
              refCount: 2,
              pullRequests: const {'refs/heads/topic': pull},
              branchChecks: const {
                'refs/heads/topic': HostingCheckState.failing,
              },
            ),
            onSelected: (_) {},
            onOpenPullRequest: (value) => opened.add(value.number),
          ),
        ),
      ),
    );
    expect(find.byType(GitLamaPullRequestChip), findsOneWidget);
    expect(find.text('#5604'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-branch-checks')), findsNothing);
    expect(find.byKey(const ValueKey('hosting-status-checks')), findsOneWidget);
    double startOf(String name) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (widget) => widget is GitLamaRefChip && widget.name == name,
          ),
        )
        .dx;
    final chip = tester.getTopLeft(find.byType(GitLamaPullRequestChip)).dx;
    expect(chip, greaterThan(startOf('topic')));
    expect(chip, lessThan(startOf('v1')));

    await tester.tap(find.byKey(const ValueKey('history-pull-request-5604')));
    expect(opened, [5604]);
  });

  testWidgets('a pull request chip shows the CI result and conflicts the '
      'provider reported', (tester) async {
    Future<void> pump(HistoryReferencePullRequest pull) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HistoryGraphView(
            itemCount: 1,
            rowAt: (_) => HistoryGraphRow(
              objectId: row.objectId,
              lane: 0,
              shape: HistoryNodeShape.commit,
              segments: const [],
              geometry: row.geometry,
              refs: [utf8.encode('refs/heads/topic')],
              refCount: 1,
              pullRequests: {'refs/heads/topic': pull},
            ),
            onSelected: (_) {},
          ),
        ),
      ),
    );
    const checks = ValueKey('hosting-status-checks');
    const conflicts = ValueKey('hosting-status-conflicts');

    await pump(
      const HistoryReferencePullRequest(
        number: 7,
        title: 'Topic',
        webUrl: 'https://github.example/team/project/pull/7',
        checks: HostingCheckState.failing,
        mergeability: HostingMergeability.conflicting,
      ),
    );
    expect(find.byKey(checks), findsOneWidget);
    expect(find.byKey(conflicts), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.byType(GitLamaPullRequestChip),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.message, '#7 Topic\nChecks failed\nMerge conflicts');

    // A provider that reports neither adds nothing to the chip.
    await pump(
      const HistoryReferencePullRequest(
        number: 7,
        title: 'Topic',
        webUrl: 'https://github.example/team/project/pull/7',
        outdated: true,
      ),
    );
    expect(find.byKey(checks), findsNothing);
    expect(find.byKey(conflicts), findsNothing);
    expect(
      tester
          .widget<Tooltip>(
            find
                .ancestor(
                  of: find.byType(GitLamaPullRequestChip),
                  matching: find.byType(Tooltip),
                )
                .first,
          )
          .message,
      startsWith("#7 Topic\nThe pull request's head on the host"),
    );
  });

  for (final paired in [false, true]) {
    for (final selected in [false, true]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'branch CI stays inside its chip paired=$paired selected=$selected $brightness',
          (tester) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(brightness),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: HistoryGraphView(
                    itemCount: 1,
                    rowAt: (_) => HistoryGraphRow(
                      objectId: row.objectId,
                      lane: 0,
                      shape: HistoryNodeShape.commit,
                      segments: const [],
                      geometry: row.geometry,
                      refs: [
                        if (paired) utf8.encode('refs/heads/main'),
                        utf8.encode('refs/remotes/origin/main'),
                        utf8.encode('refs/tags/v1'),
                      ],
                      refCount: paired ? 3 : 2,
                      selected: selected,
                      current: paired && selected,
                      branchChecks: const {
                        'refs/remotes/origin/main': HostingCheckState.passing,
                      },
                    ),
                    alignedUpstreams: paired
                        ? const {'refs/heads/main': 'refs/remotes/origin/main'}
                        : const {},
                    checkedOutRef: paired && selected
                        ? 'refs/heads/main'
                        : null,
                    onSelected: (_) {},
                  ),
                ),
              ),
            );
            final badge = find.byKey(const ValueKey('history-branch-checks'));
            expect(badge, findsOneWidget);
            expect(tester.widget<Tooltip>(badge).message, 'Checks passed');
            expect(find.byType(GitLamaPullRequestChip), findsNothing);
            final branch = find.byWidgetPredicate(
              (widget) =>
                  widget is GitLamaRefChip &&
                  widget.name == (paired ? 'main' : 'origin/main'),
            );
            expect(
              find.descendant(of: branch, matching: badge),
              findsOneWidget,
            );
            final chipRect = tester.getRect(branch);
            final statusRect = tester.getRect(badge);
            expect(chipRect.contains(statusRect.topLeft), isTrue);
            expect(chipRect.contains(statusRect.bottomRight), isTrue);
            expect(
              tester
                  .widget<HostingPullRequestStatus>(
                    find.byType(HostingPullRequestStatus),
                  )
                  .onAccent,
              isFalse,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets('branch CI reads on the checked-out chip $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Center(
              child: GitLamaRefChip(
                name: 'main',
                kind: GitLamaRefKind.head,
                upstream: 'origin/main',
                checks: HostingCheckState.passing,
              ),
            ),
          ),
        ),
      );
      final colors = gitlamaColors(brightness);
      final icon = tester.widget<MeridianIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('hosting-status-checks')),
          matching: find.byType(MeridianIcon),
        ),
      );
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
      }

      // The chip is filled with `ink`; the theme's own success colour is
      // made for `pane` and would sink into it.
      expect(contrast(icon.color!, colors.ink), greaterThanOrEqualTo(3));
      expect(icon.color, isNot(colors.success));
    });
  }
}
