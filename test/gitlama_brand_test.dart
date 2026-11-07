import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/brand_about.dart';
import 'package:gitlama/app/workspace/status_bar.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/app_update.dart';

void main() {
  for (final locale in ['en', 'de']) {
    for (final brightness in Brightness.values) {
      testWidgets('signature opens About $locale ${brightness.name}', (
        tester,
      ) async {
        var sourceOpened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              bottomNavigationBar: StatusBar(
                active: null,
                installed: const InstalledRelease(
                  version: '0.1.0-beta.30',
                  build: 31,
                ),
                onOpenSource: () => sourceOpened += 1,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = locale == 'en' ? 'About GitLama' : 'Über GitLama';
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pumpAndSettle();
        // About is a title page: the mark, the name, the version and the
        // maker, then the family as chips. The dialog names itself for
        // assistive technology instead of repeating a title.
        final about = find.byKey(const ValueKey('brand-about'));
        expect(about, findsOneWidget);
        expect(
          tester.getSize(find.byType(BrandAboutContent)).width,
          MeridianLayout.dialogConfirmWidth - 2 * MeridianSpace.space7,
        );
        expect(find.bySemanticsLabel(label), findsWidgets);
        expect(find.text('GitLama'), findsWidgets);
        expect(
          find.text(
            locale == 'en'
                ? 'Version 0.1.0-beta.30 (build 31)'
                : 'Version 0.1.0-beta.30 (Build 31)',
          ),
          findsOneWidget,
        );
        expect(find.byType(MeridianChip), findsNWidgets(5));
        expect(
          tester
              .widget<MeridianChip>(
                find.widgetWithText(MeridianChip, 'GitLama'),
              )
              .tone,
          MeridianChipTone.accent,
        );
        expect(find.widgetWithText(MeridianChip, 'ProcessLama'), findsOne);
        // The source link opens GitHub through the shell's callback.
        await tester.tap(
          find.widgetWithText(
            MeridianButton,
            locale == 'en' ? 'Source code on GitHub' : 'Quellcode auf GitHub',
          ),
        );
        expect(sourceOpened, 1);
        await tester.tap(
          find.byTooltip(locale == 'en' ? 'Close' : 'Schließen').last,
        );
        await tester.pumpAndSettle();
        expect(about, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
