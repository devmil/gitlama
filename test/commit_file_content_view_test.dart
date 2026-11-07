import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/commit_file_content_view.dart';

Widget _host(List<int> bytes) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: CommitFileContentView(bytes: bytes)),
);

void main() {
  testWidgets('a binary file can be shown as text until another file loads', (
    tester,
  ) async {
    await tester.pumpWidget(_host([0x61, 0, 0x62, 0x0a, 0xff, 0x63]));
    expect(find.text('This file cannot be previewed as text.'), findsOneWidget);

    await tester.tap(find.text('Show as text'));
    await tester.pump();
    expect(find.text('a␀b'), findsOneWidget);
    expect(find.text('�c'), findsOneWidget);

    await tester.pumpWidget(_host([0, 1, 2]));
    expect(find.text('This file cannot be previewed as text.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
