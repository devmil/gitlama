import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/git_reference_field.dart';
import 'package:gitlama/widgets/gitlama_selection_field.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  testWidgets('remote and editable branch share selection styling', (
    tester,
  ) async {
    final branch = TextEditingController(text: 'main');
    addTearDown(branch.dispose);
    String? remote = 'origin';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: Column(
              children: [
                GitLamaSelectionField<String>(
                  label: 'Remote',
                  icon: 'cloud',
                  initialValue: remote,
                  items: const [
                    GitLamaSelectOption(value: 'origin', label: 'origin'),
                    GitLamaSelectOption(value: 'backup', label: 'backup'),
                  ],
                  onChanged: (value) => remote = value,
                ),
                GitReferenceField(
                  controller: branch,
                  label: 'Branch',
                  names: const ['main', 'feature'],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final fields = find.byType(MeridianTextField);
    expect(fields, findsNWidgets(2));
    expect(tester.widget<MeridianTextField>(fields.first).icon, 'cloud');
    expect(tester.widget<MeridianTextField>(fields.last).icon, 'branch');
    expect(
      tester.getSize(fields.first).height,
      tester.getSize(fields.last).height,
    );

    await tester.tap(find.text('origin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('backup').last);
    await tester.pumpAndSettle();
    expect(remote, 'backup');

    await tester.enterText(
      find.descendant(of: fields.last, matching: find.byType(TextField)),
      'feature',
    );
    expect(branch.text, 'feature');
    expect(tester.takeException(), isNull);
  });
}
