import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';

void main() {
  testWidgets('file counts give way to stage and discard actions on hover', (
    tester,
  ) async {
    var staged = 0;
    var discarded = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: GitLamaFileRow(
                status: 'M',
                path: 'lib/app/main.dart',
                added: 8,
                deleted: 3,
                onActivate: () {},
                onStage: () => staged++,
                onDiscard: () => discarded++,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('−3'), findsOneWidget);
    expect(find.text('lib/app/'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(find.byType(GitLamaFileRow)),
    );
    await tester.pump();
    expect(find.text('+8'), findsNothing);
    expect(find.text('−3'), findsNothing);
    expect(find.byTooltip('Stage file'), findsOneWidget);
    expect(find.byTooltip('Discard file changes'), findsOneWidget);
    await tester.tap(find.byTooltip('Stage file'));
    await tester.tap(find.byTooltip('Discard file changes'));
    expect(staged, 1);
    expect(discarded, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a focused file row stages with Space', (tester) async {
    var staged = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MeridianSurfaceScope(
            focused: true,
            child: GitLamaFileRow(
              status: 'A',
              path: 'README.md',
              selected: true,
              onActivate: () {},
              onStage: () => staged++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GitLamaFileRow));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(staged, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a focused selected row keeps its actions and grip visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MeridianSurfaceScope(
            focused: true,
            child: Center(
              child: SizedBox(
                width: 420,
                child: GitLamaFileRow(
                  status: 'M',
                  path: 'CHANGELOG.md',
                  selected: true,
                  onActivate: () {},
                  onStage: () {},
                  onDiscard: () {},
                  trailing: const MeridianIcon('grip-vertical'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(find.text('CHANGELOG.md')),
    );
    await tester.pump();
    final colors = MeridianTheme.of(
      tester.element(find.byType(GitLamaFileRow)),
    ).colors;
    for (final tooltip in ['Stage file', 'Discard file changes']) {
      final icon = tester.widget<MeridianIcon>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(MeridianIcon),
        ),
      );
      // The soft selection keeps the normal inks, so the actions stay
      // visible on it.
      expect(icon.color, colors.inkMuted, reason: tooltip);
    }
    final grip = find.byWidgetPredicate(
      (widget) => widget is MeridianIcon && widget.name == 'grip-vertical',
    );
    expect(IconTheme.of(tester.element(grip)).color, colors.inkMuted);
  });

  testWidgets('long directories elide at the start and keep the file name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 210,
            child: GitLamaFileRow(
              status: 'M',
              path: 'src/very-long-feature-directory/deep/module/README.md',
              onActivate: () {},
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(GitLamaFileRow),
            matching: find.byWidgetPredicate(
              (widget) => widget is Text && widget.textSpan != null,
            ),
          )
          .first,
    );
    final displayed = text.textSpan!.toPlainText();
    expect(displayed, startsWith('…'));
    expect(displayed, endsWith('README.md'));
  });
}
