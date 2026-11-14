import 'package:flutter/widgets.dart';
import 'package:gitlama/l10n/l10n.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/welcome_screen.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_state.dart';

void main() {
  for (final language in ['en', 'de']) {
    testWidgets('opening capacity has an actionable message in $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        MeridianApp(
          theme: MeridianTheme.resolve(
            brand: MeridianBrands.gitlama,
            brightness: Brightness.light,
          ),
          locale: Locale(language),
          localizationsDelegates: gitLamaLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(
              repositoryFailureMessage(context, RepositoryFailureCode.capacity),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          language == 'en'
              ? 'This connection has reached its open repository limit. Close another repository tab on this host, then try again.'
              : 'Die maximale Anzahl geöffneter Repositorys für diese Verbindung ist erreicht. Schließe einen anderen Repository-Tab auf diesem Host und versuche es erneut.',
        ),
        findsOneWidget,
      );
    });
  }
}
