import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/tab_group_dialog.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/repository_appearance.dart';
import 'package:gitlama/models/workspace.dart';

const _group = RepositoryTabGroup(
  id: 7,
  name: 'Client',
  color: PaletteColor(RepositoryAppearanceColor.violet),
  icon: 'server',
);

/// Opens the editor for [group] and returns a reader for its result.
Future<TabGroupEdit? Function()> _open(
  WidgetTester tester, {
  RepositoryTabGroup group = _group,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  TabGroupEdit? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MeridianGround(
        child: Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'Open',
              onPressed: () async {
                result = await showTabGroupDialog(
                  context,
                  group: group,
                  tabLabels: const ['api', 'web', 'docs', 'infra'],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => result;
}

Finder get _preview => find.byKey(const ValueKey('tab-group-preview'));

Finder get _nameField => find.descendant(
  of: find.byKey(const ValueKey('tab-group-name')),
  matching: find.byType(EditableText),
);

void main() {
  group('appearance colours', () {
    test('palette names and rgb values round-trip through their keys', () {
      for (final palette in RepositoryAppearanceColor.values) {
        final color = PaletteColor(palette);
        expect(AppearanceColor.byKey(color.key), color);
      }
      const custom = CustomColor(0xFFC2410C);
      expect(custom.rgb, 0xC2410C);
      expect(custom.key, 'rgb-c2410c');
      expect(custom.hex, '#C2410C');
      expect(AppearanceColor.byKey('rgb-c2410c'), custom);
      expect(AppearanceColor.byKey('rgb-00000a'), const CustomColor(0xA));
    });

    test('anything else names no colour', () {
      for (final key in [
        null,
        '',
        'Violet',
        'rgb-C2410C',
        'rgb-c2410',
        'rgb-c2410c0',
        '#c2410c',
      ]) {
        expect(AppearanceColor.byKey(key), isNull, reason: '$key');
      }
    });
  });

  group('tab group editor', () {
    testWidgets('previews and saves the name, colour and icon together', (
      tester,
    ) async {
      final result = await _open(tester);
      expect(find.text('Edit group'), findsOneWidget);
      // The preview shows the group's chip and its first three tabs.
      expect(
        find.descendant(of: _preview, matching: find.text('Client')),
        findsOneWidget,
      );
      for (final label in ['api', 'web', 'docs']) {
        expect(
          find.descendant(of: _preview, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: _preview, matching: find.text('infra')),
        findsNothing,
      );

      await tester.enterText(_nameField, '  Mobile\tapps ');
      await tester.pump();
      expect(
        find.descendant(of: _preview, matching: find.text('Mobile apps')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('meridian-color-series-1')));
      await tester.tap(find.byKey(const ValueKey('tab-group-icon-users')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tab-group-save')));
      await tester.pumpAndSettle();

      expect(find.text('Edit group'), findsNothing);
      expect(result(), (
        name: 'Mobile apps',
        color: const PaletteColor(RepositoryAppearanceColor.teal),
        icon: 'users',
      ));
    });

    testWidgets('Enter in the name saves; Cancel saves nothing', (
      tester,
    ) async {
      var result = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('tab-group-icon-none')));
      await tester.enterText(_nameField, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result(), (
        name: '',
        color: const PaletteColor(RepositoryAppearanceColor.violet),
        icon: null,
      ));

      result = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('meridian-color-series-1')));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit group'), findsNothing);
      expect(result(), isNull);
    });

    testWidgets('the colour well picks a custom colour by its hex value', (
      tester,
    ) async {
      final result = await _open(tester);
      final well = find.byKey(const ValueKey('meridian-color-custom'));
      expect(
        tester.widget<MeridianColorWell>(well),
        isA<MeridianColorWell>()
            .having((well) => well.color, 'color', isNull)
            .having((well) => well.selected, 'selected', isFalse),
      );

      await tester.tap(well);
      await tester.pumpAndSettle();
      final picker = find.byType(MeridianColorPicker);
      expect(picker, findsOneWidget);
      // Wide enough to stand the wheel beside the controls.
      expect(
        tester.getSize(picker).width,
        greaterThanOrEqualTo(MeridianLayout.colorPickerWide),
      );
      final hex = find.descendant(
        of: picker,
        matching: find.byType(EditableText),
      );
      await tester.enterText(hex, '#c2410c');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);

      // The palette swatch is no longer chosen; the well is.
      expect(
        tester
            .widget<MeridianColorSwatch>(
              find.byKey(const ValueKey('meridian-color-series-5')),
            )
            .selected,
        isFalse,
      );
      expect(tester.widget<MeridianColorWell>(well).selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('tab-group-save')));
      await tester.pumpAndSettle();
      expect(result()?.color, const CustomColor(0xC2410C));
    });

    testWidgets('a custom colour opens with the well chosen and stays when a '
        'palette colour is tried', (tester) async {
      final result = await _open(
        tester,
        group: const RepositoryTabGroup(id: 3, color: CustomColor(0x1A5F3C)),
      );
      final well = find.byKey(const ValueKey('meridian-color-custom'));
      expect(tester.widget<MeridianColorWell>(well).selected, isTrue);
      expect(
        tester.widget<MeridianColorWell>(well).color,
        const Color(0xFF1A5F3C),
      );
      // The well names the custom colour.
      expect(find.bySemanticsLabel(RegExp('#1A5F3C')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('meridian-color-series-2')));
      await tester.pump();
      expect(tester.widget<MeridianColorWell>(well).selected, isFalse);
      expect(
        tester.widget<MeridianColorWell>(well).color,
        const Color(0xFF1A5F3C),
      );
      await tester.tap(find.byKey(const ValueKey('tab-group-save')));
      await tester.pumpAndSettle();
      expect(
        result()?.color,
        const PaletteColor(RepositoryAppearanceColor.amber),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('lays out in the $brightness theme at enlarged text', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _open(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('meridian-color-custom')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
