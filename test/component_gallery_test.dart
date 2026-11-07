import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'support/component_gallery.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/widgets/native_menu.dart';

Widget gallery({
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  MeridianDensity density = MeridianDensity.regular,
  double textScale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildAppTheme(brightness, density: density),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
    child: MeridianMenuPresenter(
      present: presentNativeMeridianMenu,
      textContextMenuBuilder: nativeTextContextMenuBuilder,
      child: child!,
    ),
  ),
  home: const ComponentGallery(),
);

void main() {
  testWidgets('interaction exposes hover and press without painting a tint', (
    tester,
  ) async {
    var activations = 0;
    MeridianInteractionState? interaction;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: MeridianInteraction(
              onTap: () => activations += 1,
              builder: (context, state) {
                interaction = state;
                return const SizedBox(
                  key: ValueKey('interaction-target'),
                  width: 120,
                  height: 32,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).splashFactory,
      same(NoSplash.splashFactory),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await tester.pump();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('interaction-target'))),
    );
    await tester.pump();
    expect(interaction!.hovered, isTrue);
    expect(interaction!.pressed, isFalse);

    final press = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('interaction-target'))),
    );
    await tester.pump();
    expect(interaction!.pressed, isTrue);
    expect(
      find.descendant(
        of: find.byType(MeridianInteraction),
        matching: find.byType(AnimatedContainer),
      ),
      findsNothing,
    );
    await press.up();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 2);
  });

  testWidgets('button supports keyboard activation and disabled explanation', (
    tester,
  ) async {
    await tester.pumpWidget(gallery());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.textContaining('Activations: 1'), findsOneWidget);

    final semantics = tester.getSemantics(
      find.bySemanticsLabel(
        'Unavailable action with a deliberately long label',
      ),
    );
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.text('Unavailable action with a deliberately long label'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No repository is open'), findsWidgets);
  });

  testWidgets('menu dismisses with Escape and restores invoking focus', (
    tester,
  ) async {
    await tester.pumpWidget(gallery());
    await tester.pump(const Duration(milliseconds: 100));
    final menu = find
        .byWidgetPredicate((widget) => widget is MeridianMenuAnchor)
        .first;
    final visibleChanges = find.text('Changes').evaluate().length;
    await tester.tap(menu);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Changes'), findsNWidgets(visibleChanges + 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Changes'), findsNWidgets(visibleChanges));
    expect(FocusManager.instance.primaryFocus, isNotNull);

    final segmentedChanges = find.descendant(
      of: find.byType(MeridianSegmented<String>),
      matching: find.text('Changes'),
    );
    await tester.ensureVisible(segmentedChanges);
    await tester.tap(segmentedChanges);
    await tester.pump();
    expect(find.textContaining('Menu: Changes'), findsOneWidget);
  });

  testWidgets('density, dark tokens, German labels and scaled text compose', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      gallery(
        locale: const Locale('de'),
        brightness: Brightness.dark,
        density: MeridianDensity.comfortable,
        textScale: 1.3,
        disableAnimations: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Repository öffnen'), findsWidgets);
    final row = tester.getSize(
      find.byWidgetPredicate(
        (widget) =>
            widget is MeridianListRow &&
            widget.title.contains('Branch-Beschriftung'),
      ),
    );
    expect(row.height, MeridianSize.rowComfortable);
    final context = tester.element(find.byType(ComponentGallery));
    expect(MeridianTheme.of(context).colors.ground, const Color(0xFF0B151A));
    expect(MediaQuery.of(context).disableAnimations, isTrue);
  });

  testWidgets('desktop text field keeps compact control height', (
    tester,
  ) async {
    await tester.pumpWidget(gallery());
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.getSize(find.byType(TextField).first).height,
      lessThanOrEqualTo(36),
    );
  });
}
