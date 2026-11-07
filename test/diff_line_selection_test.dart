import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/changes_section.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/widgets/diff_line_selection.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'support/fake_repository_session_repository.dart';

DiffDisplayRow _row(
  String id,
  DiffRowKind kind, {
  String text = 'line',
  int? oldLine,
  int? newLine,
}) => DiffDisplayRow(
  stableId: id,
  kind: kind,
  text: utf8.encode(text),
  oldLine: oldLine,
  newLine: newLine,
  selectable: kind == DiffRowKind.addition || kind == DiffRowKind.deletion,
);

/// Two hunks: h1 with d1, a1, a2 between context lines; h2 with a3.
final _first = [
  _row('file', DiffRowKind.file, text: 'lib/a.dart'),
  _row('h1', DiffRowKind.hunk, text: '@@ -1,3 +1,4 @@ main'),
  _row('c1', DiffRowKind.context, oldLine: 1, newLine: 1),
  _row('d1', DiffRowKind.deletion, text: 'old', oldLine: 2),
  _row('a1', DiffRowKind.addition, text: 'new', newLine: 2),
  _row('a2', DiffRowKind.addition, text: 'more', newLine: 3),
  _row('c2', DiffRowKind.context, oldLine: 3, newLine: 4),
  _row('h2', DiffRowKind.hunk, text: '@@ -9,1 +10,2 @@'),
  _row('a3', DiffRowKind.addition, newLine: 10),
];

/// The rest of h2, delivered by Load more.
final _second = [_row('a4', DiffRowKind.addition, newLine: 11)];

DiffPage _page(List<DiffDisplayRow> rows, int total, {int offset = 0}) =>
    DiffPage(
      requestId: BigInt.from(7),
      layout: DiffViewLayout.unified,
      totalRows: total,
      offset: offset,
      rows: rows,
      payloadBytes: 0,
    );

class _DiffRepository extends FakeRepositorySessionRepository {
  _DiffRepository() : super(null);

  final pageOffsets = <int>[];

  @override
  Future<DiffPage> workingDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = 512,
  }) async => _page(_first, _first.length + _second.length);

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async {
    pageOffsets.add(offset);
    return _page(_second, _first.length + _second.length, offset: offset);
  }
}

void main() {
  group('DiffLineSelection', () {
    DiffLineSelection indexed({bool complete = true}) =>
        DiffLineSelection()
          ..update(_first, complete ? _first.length : _first.length + 1);

    test('a picked hunk is sent as its hunk ID and checks its lines', () {
      final selection = indexed()..setLine(_first[3], true);
      selection.setHunk('h1', true);
      expect(selection.rowIds, ['h1']);
      expect(selection.lineChecked(_first[4]), isTrue);
      expect(selection.lineChecked(_first[8]), isFalse);
      expect(selection.hunkChecked('h1'), isTrue);
      expect(selection.pickedLines, (count: 3, more: false));
    });

    test('unpicking a line of a picked hunk keeps its other lines', () {
      final selection = indexed()..setHunk('h1', true);
      selection.setLine(_first[4], false);
      expect(selection.rowIds, unorderedEquals(['d1', 'a2']));
      expect(selection.hunkChecked('h1'), isNull);
      selection.setHunk('h1', false);
      expect(selection.isEmpty, isTrue);
      expect(selection.hunkChecked('h1'), isFalse);
    });

    test('a hunk with every loaded line picked is checked once complete', () {
      final selection = indexed(complete: false)..setLine(_first[8], true);
      // h2 may have more lines to load: only some of it is known picked.
      expect(selection.hunkChecked('h2'), isNull);
      selection.setHunk('h2', true);
      expect(selection.pickedLines, (count: 1, more: true));
      final complete = indexed()..setLine(_first[8], true);
      expect(complete.hunkChecked('h2'), isTrue);
    });

    test('select all picks every hunk; clear picks nothing', () {
      final selection = indexed()..setLine(_first[3], true);
      selection.selectAll();
      expect(selection.rowIds, unorderedEquals(['h1', 'h2']));
      expect(selection.allChecked, isTrue);
      expect(selection.pickedLines.count, 4);
      selection.clear();
      expect(selection.isEmpty, isTrue);
      expect(selection.allChecked, isFalse);
    });
  });

  group('WorkingDiffSelectionDialog', () {
    late _DiffRepository repository;
    late RepositorySessionService service;
    Object? result;

    Future<void> open(WidgetTester tester, {Locale? locale}) async {
      repository = _DiffRepository();
      service = RepositorySessionService(repository);
      await tester.runAsync(() => service.open('/repository'));
      result = null;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Center(
              child: MeridianButton(
                key: const ValueKey('launch'),
                label: 'Open',
                onPressed: () async => result = await showMeridianDialog(
                  context: context,
                  builder: (_) => WorkingDiffSelectionDialog(
                    side: StagingSide.unstaged,
                    oldPath: null,
                    newPath: null,
                    repositories: service,
                    allowDiscard: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await tester.pumpAndSettle();
    }

    Finder row(String id) => find.byKey(ValueKey('line-selection-$id'));
    String count(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('line-selection-count')))
        .data!;

    testWidgets('shows code rows with gutters and picks a hunk', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Select changed lines'), findsOneWidget);
      expect(count(tester), 'No lines selected');
      // Line numbers sit in their own gutter, the text in code type.
      expect(
        find.descendant(of: row('a1'), matching: find.text('2')),
        findsOneWidget,
      );
      final text = tester.widget<Text>(
        find.descendant(of: row('a1'), matching: find.text('new')),
      );
      expect(text.style?.fontFamily, contains('Mono'));
      // Context lines have no checkbox.
      expect(
        find.descendant(of: row('c1'), matching: find.byType(MeridianCheckbox)),
        findsNothing,
      );

      await tester.tap(row('h1'));
      await tester.pump();
      expect(count(tester), '3 lines selected');
      await tester.tap(find.text('Stage selected changes'));
      await tester.pumpAndSettle();
      final choice = result! as PartialStagingChoice;
      expect(choice.rowIds, ['h1']);
      expect(choice.page.requestId, BigInt.from(7));
    });

    testWidgets('picks single lines and loads more rows', (tester) async {
      await open(tester);
      await tester.tap(
        find.descendant(of: row('a1'), matching: find.byType(MeridianCheckbox)),
      );
      await tester.pump();
      expect(
        tester
            .widget<MeridianCheckbox>(
              find.descendant(
                of: row('h1'),
                matching: find.byType(MeridianCheckbox),
              ),
            )
            .value,
        isNull,
      );
      // h2 continues on the next page: picking it is a lower bound.
      await tester.tap(row('h2'));
      await tester.pump();
      expect(count(tester), 'At least 2 lines selected');

      await tester.tap(find.text('Load more changes'));
      await tester.pumpAndSettle();
      expect(repository.pageOffsets, [_first.length]);
      expect(row('a4'), findsOneWidget);
      expect(find.text('Load more changes'), findsNothing);
      expect(count(tester), '3 lines selected');

      await tester.tap(find.text('Discard selected changes'));
      await tester.pumpAndSettle();
      final choice = result! as PartialDiscardChoice;
      expect(choice.rowIds, ['a1', 'h2']);
    });

    testWidgets('select all and none, in German', (tester) async {
      await open(tester, locale: const Locale('de'));
      await tester.tap(find.byKey(const ValueKey('line-selection-all')));
      await tester.pump();
      // h2 has a row still to load.
      expect(count(tester), 'Mindestens 4 Zeilen ausgewählt');
      expect(find.text('Keine auswählen'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('line-selection-all')));
      await tester.pump();
      expect(count(tester), 'Keine Zeilen ausgewählt');
      expect(find.text('Alle auswählen'), findsOneWidget);
    });
  });
}
