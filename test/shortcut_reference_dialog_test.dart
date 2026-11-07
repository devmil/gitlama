import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/settings_dialog.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/app_shortcut.dart';
import 'package:gitlama/models/settings.dart';

void main() {
  testWidgets('conflicts come from the shortcuts in effect', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Two commands the user bound to one key; their defaults differ.
    final shortcuts = <AppCommandId, AppShortcut?>{
      ...AppShortcutCatalog.shown(const [], macOS: false),
      AppCommandId.showChanges: AppShortcut.parse('Ctrl+Alt+J'),
      AppCommandId.showHistory: AppShortcut.parse('Ctrl+Alt+J'),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ShortcutReferenceDialog(shortcuts: shortcuts)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ctrl+Alt+J:'), findsOneWidget);
  });

  testWidgets('each platform shows its own modifier keys', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (platform, keys) in [
      (TargetPlatform.linux, ['Ctrl', 'Shift', 'P']),
      (TargetPlatform.macOS, ['⌘', '⇧', 'P']),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final shortcuts = AppShortcutCatalog.shown(
        const [],
        macOS: platform == TargetPlatform.macOS,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ShortcutReferenceDialog(shortcuts: shortcuts)),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('shortcut-search')),
        'Create patch',
      );
      await tester.pump();
      final kbd = tester.widget<MeridianKbd>(find.byType(MeridianKbd));
      expect(kbd.keys, keys, reason: platform.name);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('default shortcuts come from the command registry alone', () {
    for (final command in AppCommandRegistry.commands) {
      for (final macOS in const [false, true]) {
        final binding = command.defaultShortcut(macOS: macOS);
        expect(
          AppShortcutCatalog.defaultBinding(command.id, macOS: macOS),
          binding,
        );
        // Every default parses, and a key hint never binds globally.
        if (binding != null) AppShortcut.parse(binding);
        if (command.keyHint != null) expect(binding, isNull);
      }
    }
    expect(
      AppShortcutCatalog.defaultBinding(AppCommandId.showHistory, macOS: true),
      'Cmd+2',
    );
  });

  test('a key hint shows until the user overrides its command', () {
    final shown = AppShortcutCatalog.shown(const [], macOS: false);
    expect(shown[AppCommandId.createBranch]?.canonical, 'Insert');
    final overridden = AppShortcutCatalog.shown(const [
      ShortcutOverride(commandId: 'createBranch', binding: 'Ctrl+Alt+B'),
      ShortcutOverride(commandId: 'inspectorToggleFiles', binding: null),
    ], macOS: false);
    expect(overridden[AppCommandId.createBranch]?.canonical, 'Ctrl+Alt+B');
  });
}
