import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/app/workspace/branch_filter.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/l10n/app_localizations_en.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/repository_state.dart';

void main() {
  group('HistoryBranchFilter', () {
    test('keeps sorted distinct references and toggles them', () {
      final filter = HistoryBranchFilter([
        'refs/heads/topic',
        'refs/heads/main',
        'refs/heads/topic',
      ]);
      expect(filter.references, ['refs/heads/main', 'refs/heads/topic']);
      expect(
        filter,
        HistoryBranchFilter(['refs/heads/main', 'refs/heads/topic']),
      );
      expect(filter.isFocusedOn('refs/heads/main'), isFalse);

      final removed = filter.toggled('refs/heads/topic');
      expect(removed.references, ['refs/heads/main']);
      expect(removed.isFocusedOn('refs/heads/main'), isTrue);
      expect(
        removed.toggled('refs/heads/main'),
        same(HistoryBranchFilter.none),
      );
      expect(HistoryBranchFilter.none.toggled('refs/heads/x').references, [
        'refs/heads/x',
      ]);
    });

    test('a branch brings the upstream it tracks, removed on its own', () {
      const upstream = 'refs/remotes/origin/topic';
      final focused = HistoryBranchFilter.focus(
        'refs/heads/topic',
        upstream: upstream,
      );
      expect(focused.references, ['refs/heads/topic', upstream]);
      expect(
        focused.isFocusedOn('refs/heads/topic', upstream: upstream),
        isTrue,
      );
      expect(focused.isFocusedOn('refs/heads/topic'), isFalse);

      // The upstream is deselected like any other branch.
      final local = focused.toggled(upstream);
      expect(local.references, ['refs/heads/topic']);
      expect(local.isFocusedOn('refs/heads/topic', upstream: upstream), isTrue);

      final added = HistoryBranchFilter([
        'refs/heads/main',
      ]).toggled('refs/heads/topic', upstream: upstream);
      expect(added.references, [
        'refs/heads/main',
        'refs/heads/topic',
        upstream,
      ]);
      expect(
        added.isFocusedOn('refs/heads/topic', upstream: upstream),
        isFalse,
      );
      // Removing the branch leaves the upstream to its own row.
      expect(added.toggled('refs/heads/topic', upstream: upstream).references, [
        'refs/heads/main',
        upstream,
      ]);
    });

    test('an upstream is left out when only the branch still fits', () {
      final nearlyFull = HistoryBranchFilter([
        for (
          var index = 0;
          index < HistoryBranchFilter.maximumReferences - 1;
          index += 1
        )
          'refs/heads/b$index',
      ]);
      final added = nearlyFull.toggled(
        'refs/heads/extra',
        upstream: 'refs/remotes/origin/extra',
      );
      expect(added.length, HistoryBranchFilter.maximumReferences);
      expect(added.contains('refs/heads/extra'), isTrue);
      expect(added.contains('refs/remotes/origin/extra'), isFalse);
    });

    test('adding beyond the native bound leaves the filter unchanged', () {
      final full = HistoryBranchFilter([
        for (
          var index = 0;
          index < HistoryBranchFilter.maximumReferences;
          index += 1
        )
          'refs/heads/b$index',
      ]);
      expect(full.toggled('refs/heads/extra'), same(full));
      expect(full.toggled('refs/heads/b0').length, full.length - 1);
    });
  });

  test('choices list local branches, then remotes, by full name', () {
    final choices = buildBranchFilterChoices(
      RepositoryRefs(
        branches: [
          RepositoryReference(name: 'alpha'.codeUnits, target: 'a'),
          RepositoryReference(name: 'main'.codeUnits, target: 'b', head: true),
          // Not UTF-8: it could not round-trip through the filter.
          const RepositoryReference(name: [0xff, 0xfe], target: 'c'),
        ],
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: const [],
            branches: [
              RepositoryReference(name: 'HEAD'.codeUnits, target: 'b'),
              RepositoryReference(name: 'feature/x'.codeUnits, target: 'd'),
            ],
          ),
        ],
      ),
    );
    expect(choices.map((choice) => choice.reference), [
      'refs/heads/main',
      'refs/heads/alpha',
      'refs/remotes/origin/feature/x',
    ]);
    expect(choices.map((choice) => choice.label), [
      'main',
      'alpha',
      'origin/feature/x',
    ]);
    expect(choices.first.current, isTrue);
    expect(choices.last.remote, 'origin');
    expect(choices.last.name, 'feature/x');
    expect(choices.first.name, 'main');
    expect(choices.last.matches('feature/'), isTrue);
    expect(choices.last.matches('main'), isFalse);
    expect(isFilterableBranch('refs/remotes/origin/HEAD'), isFalse);
    expect(isFilterableBranch('refs/tags/v1'), isFalse);
    expect(isFilterableBranch('refs/heads/main'), isTrue);
  });

  test('choices list the main branch first, locally and on each remote', () {
    final choices = buildBranchFilterChoices(
      RepositoryRefs(
        branches: [
          RepositoryReference(
            name: 'alpha'.codeUnits,
            target: 'a',
            head: true,
            upstream: 'refs/remotes/origin/alpha'.codeUnits,
          ),
          RepositoryReference(
            name: 'gone'.codeUnits,
            target: 'g',
            upstream: 'refs/remotes/origin/gone'.codeUnits,
            upstreamGone: true,
          ),
          RepositoryReference(
            name: 'main'.codeUnits,
            target: 'b',
            upstream: 'refs/remotes/origin/main'.codeUnits,
          ),
          RepositoryReference(name: 'master'.codeUnits, target: 'c'),
        ],
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: const [],
            branches: [
              RepositoryReference(name: 'HEAD'.codeUnits, target: 'b'),
              RepositoryReference(name: 'alpha'.codeUnits, target: 'a'),
              RepositoryReference(name: 'main'.codeUnits, target: 'b'),
            ],
          ),
          RepositoryRemote(
            name: 'upstream'.codeUnits,
            displayUrl: const [],
            branches: [
              RepositoryReference(name: 'develop'.codeUnits, target: 'd'),
              RepositoryReference(name: 'master'.codeUnits, target: 'c'),
            ],
          ),
        ],
      ),
    );
    expect(choices.map((choice) => choice.label), [
      'main',
      'alpha',
      'gone',
      'master',
      'origin/main',
      'origin/alpha',
      'upstream/master',
      'upstream/develop',
    ]);
    expect(choices.map((choice) => choice.upstream).take(4), [
      'refs/remotes/origin/main',
      'refs/remotes/origin/alpha',
      // Gone from its remote: nothing to show along with the branch.
      null,
      null,
    ]);
    expect(choices[1].current, isTrue);
  });

  test('menu actions bring the upstream of a branch', () {
    final l10n = AppLocalizationsEn();
    const upstream = 'refs/remotes/origin/topic';
    List<({String title, HistoryBranchFilter filter})> actions(
      HistoryBranchFilter filter,
    ) => branchFilterMenuActions(
      l10n,
      filter,
      'refs/heads/topic',
      upstream: upstream,
    );

    final initial = actions(HistoryBranchFilter.none);
    expect(initial.map((action) => action.title), [
      'Show only this branch',
      'Add to graph filter',
    ]);
    expect(initial[0].filter.references, ['refs/heads/topic', upstream]);
    expect(initial[1].filter.references, ['refs/heads/topic', upstream]);

    // Focused with or without the upstream: nothing left to focus on.
    for (final focused in [
      initial[0].filter,
      HistoryBranchFilter(['refs/heads/topic']),
    ]) {
      expect(actions(focused).map((action) => action.title), [
        'Remove from graph filter',
        'Show all branches',
      ]);
    }
    expect(actions(initial[0].filter).first.filter.references, [upstream]);
  });

  test('menu actions follow the current filter', () {
    final l10n = AppLocalizationsEn();
    List<String> titles(HistoryBranchFilter filter) => [
      for (final action in branchFilterMenuActions(
        l10n,
        filter,
        'refs/heads/topic',
      ))
        action.title,
    ];
    expect(titles(HistoryBranchFilter.none), [
      'Show only this branch',
      'Add to graph filter',
    ]);
    expect(titles(HistoryBranchFilter(['refs/heads/topic'])), [
      'Remove from graph filter',
      'Show all branches',
    ]);
    final other = HistoryBranchFilter(['refs/heads/main']);
    final actions = branchFilterMenuActions(l10n, other, 'refs/heads/topic');
    expect(actions.map((action) => action.title), [
      'Show only this branch',
      'Add to graph filter',
      'Show all branches',
    ]);
    expect(actions[0].filter.references, ['refs/heads/topic']);
    expect(actions[1].filter.references, [
      'refs/heads/main',
      'refs/heads/topic',
    ]);
    expect(actions[2].filter, HistoryBranchFilter.none);
  });

  Widget editor({
    required List<BranchFilterChoice> choices,
    required HistoryBranchFilter filter,
    required ValueChanged<HistoryBranchFilter> onChanged,
    Locale? locale,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: GitLamaLayout.branchFilterWidth,
          child: BranchFilterEditor(
            choices: choices,
            filter: filter,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );

  List<String> titles(WidgetTester tester) => [
    for (final row in tester.widgetList<MeridianListRow>(
      find.byType(MeridianListRow),
    ))
      row.title,
  ];

  testWidgets(
    'the editor is a virtualized tree, fits long translations and uses the keyboard',
    (tester) async {
      final changes = <HistoryBranchFilter>[];
      await tester.pumpWidget(
        editor(
          locale: const Locale('de'),
          choices: [
            BranchFilterChoice(
              reference: 'refs/heads/main',
              label: 'main',
              current: true,
            ),
            for (var index = 0; index < 4000; index += 1)
              BranchFilterChoice(
                reference: 'refs/remotes/origin/group/topic-$index',
                label: 'origin/group/topic-$index',
                remote: 'origin',
              ),
          ],
          // A filtered branch the repository no longer lists stays
          // removable, ahead of everything else.
          filter: HistoryBranchFilter(['refs/heads/gone']),
          onChanged: changes.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Groups are open; folders stay closed unless they hold the current
      // or a filtered branch.
      expect(titles(tester), ['gone', 'Branches', 'main', 'origin', 'group']);

      await tester.tap(
        find.byKey(const ValueKey('refs/remotes/origin/group/')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(MeridianListRow).evaluate().length,
        lessThan(40),
        reason: 'only the rows in view are built',
      );
      await tester.tap(
        find.byKey(const ValueKey('refs/remotes/origin/group/')),
      );
      await tester.pumpAndSettle();
      expect(titles(tester), hasLength(5));

      await tester.enterText(
        find.byKey(const ValueKey('branch-filter-search')),
        'topic-399',
      );
      await tester.pumpAndSettle();
      // Its folders open for topic-399 and topic-3990 … topic-3999; nothing
      // else matches.
      expect(titles(tester).take(3), ['origin', 'group', 'topic-399']);
      expect(find.byKey(const ValueKey('refs/heads/main')), findsNothing);
      // The cursor starts on the first branch, below its folders.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes.single.references, [
        'refs/heads/gone',
        'refs/remotes/origin/group/topic-3990',
      ]);
      expect(find.text('2 Branches angezeigt'), findsOneWidget);

      // A closed folder counts the branches it holds that the graph shows.
      await tester.enterText(
        find.byKey(const ValueKey('branch-filter-search')),
        '',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('refs/remotes/origin/group/')),
          matching: find.byWidgetPredicate(
            (widget) => widget is MeridianCount && widget.label == '1',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the editor opens folders holding filtered branches', (
    tester,
  ) async {
    await tester.pumpWidget(
      editor(
        choices: [
          BranchFilterChoice(reference: 'refs/heads/main', label: 'main'),
          BranchFilterChoice(
            reference: 'refs/heads/feature/a',
            label: 'feature/a',
          ),
          BranchFilterChoice(
            reference: 'refs/heads/fix/b',
            label: 'fix/b',
            current: true,
          ),
          BranchFilterChoice(reference: 'refs/heads/spike/c', label: 'spike/c'),
        ],
        filter: HistoryBranchFilter(['refs/heads/feature/a']),
        onChanged: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(titles(tester), [
      'Branches',
      'main',
      'feature',
      'a',
      'fix',
      'b',
      'spike',
    ]);

    // Enter opens and closes a folder instead of focusing on it.
    for (var step = 0; step < 6; step += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(titles(tester).last, 'c');
    expect(find.byType(BranchFilterEditor), findsOneWidget);
  });

  testWidgets('the editor shows a branch together with its upstream', (
    tester,
  ) async {
    final changes = <HistoryBranchFilter>[];
    await tester.pumpWidget(
      editor(
        choices: [
          BranchFilterChoice(
            reference: 'refs/heads/main',
            label: 'main',
            upstream: 'refs/remotes/origin/main',
          ),
          BranchFilterChoice(
            reference: 'refs/remotes/origin/main',
            label: 'origin/main',
            remote: 'origin',
          ),
        ],
        filter: HistoryBranchFilter.none,
        onChanged: changes.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(titles(tester), ['Branches', 'main', 'origin', 'main']);

    await tester.tap(find.byKey(const ValueKey('refs/heads/main')));
    await tester.pumpAndSettle();
    expect(changes.last.references, [
      'refs/heads/main',
      'refs/remotes/origin/main',
    ]);
    expect(find.text('2 branches shown'), findsOneWidget);

    // The upstream has a row of its own to deselect it.
    await tester.tap(find.byKey(const ValueKey('refs/remotes/origin/main')));
    await tester.pumpAndSettle();
    expect(changes.last.references, ['refs/heads/main']);
    expect(tester.takeException(), isNull);
  });
}
