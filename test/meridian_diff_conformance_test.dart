import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/meridian_finders.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/widgets/diff_view.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Meridian diff geometry and picked colours ${brightness.name}',
      (tester) async {
        final colors = buildAppTheme(
          brightness,
        ).extension<MeridianTheme>()!.colors;
        const rows = [
          DiffDisplayRow(
            stableId: 'hunk',
            kind: DiffRowKind.hunk,
            text: [64, 64, 32, 45, 49, 44, 49, 32, 43, 49, 44, 49, 32, 64, 64],
          ),
          DiffDisplayRow(
            stableId: 'deleted',
            kind: DiffRowKind.deletion,
            text: [111, 108, 100],
            oldLine: 11,
            selectable: true,
          ),
          DiffDisplayRow(
            stableId: 'added',
            kind: DiffRowKind.addition,
            text: [110, 101, 119],
            newLine: 12,
            selectable: true,
            intraLine: [DiffSpan(0, 3)],
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SizedBox(
              width: 640,
              height: 130,
              child: DiffView(
                itemCount: rows.length,
                rowAt: (index) => rows[index],
                hunkIndices: const {0},
                layout: DiffViewLayout.unified,
                selectedIds: const {'added'},
                onSelectionChanged: (_) {},
              ),
            ),
          ),
        );
        final hunk = find.byKey(const ValueKey('diff-row-hunk'));
        final added = find.byKey(const ValueKey('diff-row-added'));
        expect(tester.getSize(hunk).height, GitLamaLayout.hunkHeaderHeight);
        expect(tester.getSize(added).height, GitLamaLayout.diffLineHeight);
        expect(
          tester.widget<Text>(find.text('+')).style?.color,
          colors.success,
        );
        expect(
          tester.widget<Text>(find.text('−')).style?.color,
          (brightness == Brightness.dark
                  ? GitLamaGitColors.dark
                  : GitLamaGitColors.light)
              .deleted,
        );
        expect(
          tester.widget<Text>(find.text('+')).style?.fontWeight,
          FontWeight.w700,
        );
        expect(
          find.descendant(
            of: added,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).color ==
                      Color.alphaBlend(
                        colors.accent.withValues(
                          alpha: GitLamaOpacity.diffSelectedLine,
                        ),
                        colors.successBg,
                      ),
            ),
          ),
          findsOneWidget,
        );
        final marks = tester.widget<DiffLineMarks>(
          find.descendant(of: added, matching: find.byType(DiffLineMarks)),
        );
        expect(marks.marks, [const TextRange(start: 0, end: 3)]);
        expect(
          marks.markColor,
          (brightness == Brightness.dark
                  ? GitLamaGitColors.dark
                  : GitLamaGitColors.light)
              .addedStrong,
        );
        expect(marks.markRadius, Radius.circular(gitlamaRadius.xs));
        // Selected lines sit in one accent frame.
        final frame =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('diff-selection-frame-added')),
                    )
                    .decoration
                as BoxDecoration;
        final border = frame.border! as Border;
        for (final side in [
          border.left,
          border.right,
          border.top,
          border.bottom,
        ]) {
          expect(side.color, colors.accent);
          expect(side.width, MeridianLayout.hairline);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('hunk strip pins after its source row scrolls away', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox(
          width: 640,
          height: 90,
          child: DiffView(
            itemCount: 100,
            controller: controller,
            rowAt: (index) => index == 0
                ? const DiffDisplayRow(
                    stableId: 'hunk',
                    kind: DiffRowKind.hunk,
                    text: [
                      64,
                      64,
                      32,
                      45,
                      49,
                      44,
                      49,
                      32,
                      43,
                      49,
                      44,
                      49,
                      32,
                      64,
                      64,
                    ],
                  )
                : DiffDisplayRow(
                    stableId: 'line-$index',
                    kind: DiffRowKind.context,
                    text: const [99, 111, 100, 101],
                  ),
            hunkIndices: const {0},
            layout: DiffViewLayout.unified,
            selectedIds: const {},
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    );
    controller.jumpTo(90);
    await tester.pump();
    expect(find.text('@@ -1,1 +1,1 @@'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
