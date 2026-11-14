import 'package:flutter/widgets.dart';
import 'package:gitlama/l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/history_mutation_dialogs.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/history_mutation.dart';

void main() {
  for (final count in [1, 2]) {
    testWidgets(
      'apply-only revert remains visible for $count selected commits',
      (tester) async {
        await tester.pumpWidget(
          MeridianApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: gitLamaLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MeridianScaffold(
              body: HistoryMutationInputDialog(
                kind: HistoryMutationKind.revert,
                selectedTargets: List.generate(count, (index) => '$index'),
                branches: const [],
                publishedHistory: false,
              ),
            ),
          ),
        );
        final apply = tester.widget<MeridianButton>(
          find.widgetWithText(MeridianButton, 'Apply without committing'),
        );
        final commit = tester.widget<MeridianButton>(
          find.widgetWithText(MeridianButton, 'Commit revert'),
        );
        expect(apply.onPressed != null, count == 1);
        expect(commit.onPressed, isNotNull);
        if (count > 1) {
          expect(
            find.text(
              'Applying without committing works with one commit at a time.',
            ),
            findsOneWidget,
          );
        }
      },
    );
  }
}
