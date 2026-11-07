import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/git_reference_field.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_DIALOG_REVIEW');
  if (capture) {
    setUpAll(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      const fontPath = String.fromEnvironment('UI_REVIEW_FONT');
      if (fontPath.isNotEmpty) {
        final loader = FontLoader('Roboto')
          ..addFont(
            File(
              fontPath,
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'shared ${brightness.name} chrome and nested picker keep one light scrim',
      (tester) async {
        tester.view.physicalSize = const Size(900, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController(text: 'main');
        addTearDown(controller.dispose);
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      const ListTile(
                        title: Text('Repository'),
                        subtitle: Text('main · Working tree clean'),
                      ),
                      TextButton(
                        onPressed: () => showMeridianDialog<void>(
                          context: context,
                          builder: (dialogContext) => MeridianDialog(
                            title: 'Check out branch',
                            content: SizedBox(
                              width: 400,
                              child: GitReferenceField(
                                controller: controller,
                                label: 'Branch',
                                names: const ['main'],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () {},
                                child: const Text('Check out'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Open dialog'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open dialog'));
          await tester.pumpAndSettle();
          final dialog = tester.element(find.byType(MeridianDialog));
          final chrome = tester.widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(MeridianDialog).first,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is DecoratedBox &&
                        widget.decoration is BoxDecoration &&
                        (widget.decoration as BoxDecoration)
                                .boxShadow
                                ?.length ==
                            2,
                  ),
                )
                .first,
          );
          expect(
            (chrome.decoration as BoxDecoration).boxShadow,
            brightness == Brightness.dark
                ? MeridianShadows.dark.shadowFloat
                : MeridianShadows.light.shadowFloat,
          );
          final route = ModalRoute.of(dialog)! as PopupRoute<void>;
          expect(
            route.barrierColor,
            brightness == Brightness.dark
                ? gitlamaColors(Brightness.dark).scrim
                : gitlamaColors(Brightness.light).scrim,
          );
          if (capture) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../build/evidence/dialogs/checkout-${brightness.name}.png',
              ),
            );
          }
          await tester.tap(find.byTooltip('Select reference'));
          await tester.pumpAndSettle();
          final picker = tester.element(find.byType(MeridianDialog).last);
          expect((ModalRoute.of(picker)! as PopupRoute).barrierColor!.a, 0);
          expect(
            tester
                .getSize(
                  find
                      .descendant(
                        of: find.byType(MeridianDialog).last,
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is DecoratedBox &&
                              widget.decoration is BoxDecoration &&
                              (widget.decoration as BoxDecoration)
                                      .boxShadow
                                      ?.length ==
                                  2,
                        ),
                      )
                      .first,
                )
                .height,
            lessThan(350),
          );
          expect(find.byType(MeridianDialog), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          if (capture) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../build/evidence/dialogs/picker-${brightness.name}.png',
              ),
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(MeridianDialog), findsOneWidget);
        } finally {
          debugDisableShadows = shadows;
        }
      },
    );
  }

  testWidgets('choice and custom content dialogs use the same chrome', (
    tester,
  ) async {
    for (final dialog in [
      const MeridianDialog(title: 'Choose', content: Text('One')),
      const MeridianDialogSurface(child: SizedBox(width: 300, height: 200)),
    ]) {
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(Brightness.light), home: dialog),
      );
      final chrome = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(MeridianDialogSurface),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).boxShadow?.length == 2,
              ),
            )
            .first,
      );
      expect(
        (chrome.decoration as BoxDecoration).boxShadow,
        MeridianShadows.light.shadowFloat,
      );
    }
  });

  testWidgets('destructive confirm focuses Cancel and keeps Escape available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMeridianConfirm(
                context,
                title: 'Discard changes?',
                description: 'Three files will be discarded.',
                confirmLabel: 'Discard',
                destructive: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final cancel = find.byWidgetPredicate(
      (widget) => widget is MeridianButton && widget.label == 'Cancel',
    );
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byElementPredicate((element) => element == focused),
        matching: cancel,
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MeridianDialog), findsNothing);
  });
}
