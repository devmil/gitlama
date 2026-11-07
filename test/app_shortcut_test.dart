import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_shortcut_activator.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/app_shortcut.dart';
import 'package:gitlama/models/settings.dart';

void main() {
  test('shortcut key caps follow the active desktop platform', () {
    final shortcut = AppShortcut.parse('Cmd+Shift+Enter');
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(platformShortcutKeys(shortcut), ['⌘', '⇧', '↵']);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(platformShortcutKeys(shortcut), ['Meta', 'Shift', 'Enter']);
  });

  test('selected staging commands use directional icons', () {
    final stageSelected = AppCommandRegistry.byId(AppCommandId.stageSelection);
    final unstageSelected = AppCommandRegistry.byId(
      AppCommandId.unstageSelection,
    );
    final stageAll = AppCommandRegistry.byId(AppCommandId.stageToggle);

    expect(stageSelected.icon, 'arrow-right');
    expect(unstageSelected.icon, 'arrow-left');
    expect(stageSelected.icon, isNot(stageAll.icon));
  });

  test('portable shortcut parser canonicalizes aliases and question mark', () {
    final shortcut = AppShortcut.parse('control+option+h');
    expect(shortcut.canonical, 'Ctrl+Alt+H');
    expect(shortcut.activator.trigger, LogicalKeyboardKey.keyH);
    expect(shortcut.activator.control, isTrue);
    expect(shortcut.activator.alt, isTrue);

    final help = AppShortcut.parse('?');
    expect(help.canonical, '?');
    expect(help.activator.trigger, LogicalKeyboardKey.slash);
    expect(help.activator.shift, isTrue);
  });

  test('malformed and operating-system-reserved shortcuts are rejected', () {
    expect(
      () => AppShortcut.parse('Ctrl+Ctrl+P'),
      throwsA(
        isA<AppShortcutException>().having(
          (error) => error.code,
          'code',
          AppShortcutFailureCode.invalid,
        ),
      ),
    );
    expect(
      () => AppShortcut.parse('Alt+F4'),
      throwsA(
        isA<AppShortcutException>().having(
          (error) => error.code,
          'code',
          AppShortcutFailureCode.reserved,
        ),
      ),
    );
  });

  test(
    'catalog applies platform defaults, overrides, and explicit unbinding',
    () {
      final mac = AppShortcutCatalog.resolve(const [], macOS: true);
      final other = AppShortcutCatalog.resolve(const [], macOS: false);
      expect(mac[AppCommandId.showHistory]!.canonical, 'Cmd+2');
      expect(other[AppCommandId.showHistory]!.canonical, 'Ctrl+2');
      expect(mac[AppCommandId.fetch]!.canonical, 'Cmd+Shift+K');
      expect(mac[AppCommandId.refreshRepository]!.canonical, 'Ctrl+R');
      expect(other[AppCommandId.pull]!.canonical, 'Ctrl+Down');
      expect(mac[AppCommandId.push]!.canonical, 'Cmd+Up');
      expect(other[AppCommandId.createStash]!.canonical, 'Ctrl+S');
      expect(mac[AppCommandId.createPatch]!.canonical, 'Cmd+Shift+P');
      expect(mac[AppCommandId.patch], isNull);

      final overridden = AppShortcutCatalog.resolve(const [
        ShortcutOverride(commandId: 'showHistory', binding: 'Alt+H'),
        ShortcutOverride(commandId: 'find', binding: null),
      ], macOS: true);
      expect(overridden[AppCommandId.showHistory]!.canonical, 'Alt+H');
      expect(overridden[AppCommandId.find], isNull);
    },
  );

  test('catalog rejects unknown, duplicate, and conflicting overrides', () {
    expect(
      () => AppShortcutCatalog.resolve(const [
        ShortcutOverride(commandId: 'notACommand', binding: 'Alt+H'),
      ], macOS: false),
      throwsA(
        isA<AppShortcutException>().having(
          (error) => error.code,
          'code',
          AppShortcutFailureCode.unknownCommand,
        ),
      ),
    );
    expect(
      () => AppShortcutCatalog.resolve(const [
        ShortcutOverride(commandId: 'showHistory', binding: 'Alt+H'),
        ShortcutOverride(commandId: 'showHistory', binding: 'Alt+J'),
      ], macOS: false),
      throwsA(
        isA<AppShortcutException>().having(
          (error) => error.code,
          'code',
          AppShortcutFailureCode.duplicateOverride,
        ),
      ),
    );
    expect(
      () => AppShortcutCatalog.resolve(const [
        ShortcutOverride(commandId: 'showHistory', binding: 'Ctrl+F'),
      ], macOS: false),
      throwsA(
        isA<AppShortcutException>().having(
          (error) => error.code,
          'code',
          AppShortcutFailureCode.conflict,
        ),
      ),
    );
  });

  test(
    'contextual commands conflict with globals but not sibling contexts',
    () {
      expect(
        () => AppShortcutCatalog.resolve(const [
          ShortcutOverride(commandId: 'stageToggle', binding: 'Ctrl+F'),
        ], macOS: false),
        throwsA(
          isA<AppShortcutException>().having(
            (error) => error.code,
            'code',
            AppShortcutFailureCode.conflict,
          ),
        ),
      );

      final resolved = AppShortcutCatalog.resolve(const [
        ShortcutOverride(commandId: 'stageToggle', binding: 'Alt+9'),
        ShortcutOverride(commandId: 'conflictNext', binding: 'Alt+9'),
      ], macOS: false);
      expect(resolved[AppCommandId.stageToggle]!.canonical, 'Alt+9');
      expect(resolved[AppCommandId.conflictNext]!.canonical, 'Alt+9');

      expect(
        () => AppShortcutCatalog.resolve(const [
          ShortcutOverride(commandId: 'stageSelection', binding: 'Alt+8'),
          ShortcutOverride(commandId: 'historyBlame', binding: 'Alt+8'),
        ], macOS: false),
        throwsA(
          isA<AppShortcutException>().having(
            (error) => error.code,
            'code',
            AppShortcutFailureCode.conflict,
          ),
        ),
      );
    },
  );
}
