import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/widgets/blame_code_view.dart';

void main() {
  testWidgets(
    'blame displays selectable source with a grouped attribution gutter',
    (tester) async {
      const commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final rows = [
        BlameRow(
          stableId: '1',
          finalLine: 1,
          originalLine: 1,
          content: '  final value = 42;'.codeUnits,
          commit: commit,
          author: 'Ada'.codeUnits,
          authorTime: 1,
          summary: 'Add value'.codeUnits,
          originalPath: 'lib/a.dart'.codeUnits,
          boundary: false,
          spanFirstLine: 1,
          spanLastLine: 2,
        ),
        BlameRow(
          stableId: '2',
          finalLine: 2,
          originalLine: 2,
          content: '  print(value);'.codeUnits,
          commit: commit,
          author: 'Ada'.codeUnits,
          authorTime: 1,
          summary: 'Add value'.codeUnits,
          originalPath: 'lib/a.dart'.codeUnits,
          boundary: false,
          spanFirstLine: 1,
          spanLastLine: 2,
        ),
        BlameRow(
          stableId: '3',
          finalLine: 3,
          originalLine: 3,
          content: '  return value;'.codeUnits,
          commit: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          author: 'Ben'.codeUnits,
          authorTime: 2,
          summary: 'Return value'.codeUnits,
          originalPath: 'lib/a.dart'.codeUnits,
          boundary: false,
          spanFirstLine: 3,
          spanLastLine: 3,
        ),
      ];
      BlameRow? before;
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: BlameCodeView(
              page: BlamePage(
                requestId: BigInt.one,
                revision: commit,
                path: 'lib/a.dart'.codeUnits,
                totalRows: 3,
                offset: 0,
                rows: rows,
              ),
              rowAt: (index) => rows[index],
              ensureRow: (_) async {},
              onSelectCommit: (commit) => selected = commit,
              onBlameBefore: (row) => before = row,
            ),
          ),
        ),
      );

      expect(
        find.widgetWithText(SelectableText, '  final value = 42;'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SelectableText, '  print(value);'),
        findsOneWidget,
      );
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Ada'));
      expect(before, same(rows.first));
      expect(selected, isNull);
    },
  );
}
