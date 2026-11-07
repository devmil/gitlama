import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/widgets/git_reference_field.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_state.dart';

void main() {
  test(
    'name formatter replaces invalid characters without moving the caret',
    () {
      const formatter = GitRefNameFormatter();
      const input = TextEditingValue(
        text: 'feature/a b?c..d@{x',
        selection: TextSelection.collapsed(offset: 9),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, input);
      expect(result.text, 'feature/a-b-c.-d@-x');
      expect(result.selection, input.selection);
      final composing = input.copyWith(
        composing: const TextRange(start: 8, end: 11),
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, composing),
        composing,
      );
    },
  );

  testWidgets('suggestions select with keyboard and disappear for no matches', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: GitReferenceField(
                controller: controller,
                label: 'Branch',
                normalize: true,
                suggestSegments: true,
                names: const ['feature/alpha', 'feature/beta', 'fix/crash'],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'fea');
    await tester.pumpAndSettle();
    expect(find.text('feature'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'feature');
    // Picking a path fragment with Enter keeps typing in the field.
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.byType(MeridianSuggestionRow), findsNothing);
    await tester.enterText(find.byType(TextField), 'feature/a');
    await tester.pumpAndSettle();
    expect(find.text('feature/alpha'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('feature/alpha'), findsNothing);
    await tester.enterText(find.byType(TextField), 'unknown');
    await tester.pumpAndSettle();
    expect(find.byType(MeridianSuggestionRow), findsNothing);
    await tester.enterText(find.byType(TextField), 'topic with spaces');
    expect(controller.text, 'topic-with-spaces');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reference browser searches commit subjects and inserts exact IDs',
    (tester) async {
      final controller = TextEditingController(text: 'HEAD');
      addTearDown(controller.dispose);
      const commit = '1234567890123456789012345678901234567890';
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 440,
                child: GitReferenceField(
                  controller: controller,
                  label: 'Reference',
                  names: const ['HEAD', 'origin/main'],
                  choices: const [
                    GitReferenceChoice(
                      commit,
                      description: 'Fix the login timeout',
                      icon: 'git-commit-horizontal',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Select reference'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.text, 'origin/main');
      await tester.tap(find.byTooltip('Select reference'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name, commit ID, or subject'),
        'login',
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(MeridianSuggestionRow, 'origin/main'),
        findsNothing,
      );
      await tester.tap(find.text('Fix the login timeout'));
      await tester.pumpAndSettle();
      expect(controller.text, commit);
      await tester.enterText(find.byType(TextField), 'HEAD~3');
      expect(controller.text, 'HEAD~3');
      expect(tester.takeException(), isNull);
    },
  );

  test('remote catalog preserves qualified branch names', () {
    final refs = RepositoryRefs(
      remotes: [
        RepositoryRemote(
          name: 'origin'.codeUnits,
          displayUrl: const [],
          branches: [
            RepositoryReference(name: 'topic'.codeUnits, target: 'a' * 40),
          ],
        ),
      ],
    );
    expect(gitReferenceNames(refs), contains('origin/topic'));
    expect(gitBranchNameSuggestions(refs), contains('topic'));
  });
}
