import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/app/workspace/diff_toolbar.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:meridian_ui/meridian_ui.dart';

Widget _toolbar(double width) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      key: const ValueKey('toolbar-host'),
      width: width,
      child: DiffToolbar(
        path: 'lib/pubspec.lock',
        pinned: [
          MeridianIconButton(
            key: const ValueKey('pinned'),
            label: 'Create patch',
            icon: 'file-diff',
            size: MeridianControlSize.small,
            onPressed: () {},
          ),
        ],
        children: [
          for (var index = 0; index < 24; index++)
            MeridianIconButton(
              key: ValueKey('control-$index'),
              label: 'Control $index',
              icon: 'wrap',
              size: MeridianControlSize.small,
              onPressed: () {},
            ),
        ],
      ),
    ),
  ),
);

void main() {
  for (final width in [1200.0, 480.0]) {
    testWidgets('pinned diff actions sit at the toolbar end at $width', (
      tester,
    ) async {
      await tester.pumpWidget(_toolbar(width));
      expect(tester.takeException(), isNull);
      final host = tester.getRect(find.byKey(const ValueKey('toolbar-host')));
      final pinned = tester.getRect(find.byKey(const ValueKey('pinned')));
      expect(host.right - pinned.right, MeridianSpace.space3);
      // The scrolling controls end before the pinned action instead of
      // running under it.
      final strip = tester.getRect(find.byType(SingleChildScrollView));
      expect(strip.right, lessThanOrEqualTo(pinned.left));
    });
  }

  testWidgets('a narrow diff toolbar drops the path label first', (
    tester,
  ) async {
    await tester.pumpWidget(_toolbar(GitLamaLayout.diffToolbarPathMinWidth));
    expect(find.text('lib/pubspec.lock', findRichText: true), findsOneWidget);
    await tester.pumpWidget(
      _toolbar(GitLamaLayout.diffToolbarPathMinWidth - 1),
    );
    expect(find.text('lib/pubspec.lock', findRichText: true), findsNothing);
    expect(find.byKey(const ValueKey('pinned')), findsOneWidget);
  });
}
