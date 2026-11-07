import 'app_command.dart';
import 'settings.dart';

enum AppShortcutFailureCode {
  invalid,
  reserved,
  unknownCommand,
  duplicateOverride,
  conflict,
  tooManyOverrides,
}

final class AppShortcutException implements Exception {
  const AppShortcutException(
    this.code, {
    this.command,
    this.conflictingCommand,
  });

  final AppShortcutFailureCode code;
  final AppCommandId? command;
  final AppCommandId? conflictingCommand;
}

final class AppShortcut {
  const AppShortcut({
    required this.canonical,
    required this.key,
    required this.control,
    required this.meta,
    required this.alt,
    required this.shift,
  });

  final String canonical;
  final String key;
  final bool control;
  final bool meta;
  final bool alt;
  final bool shift;

  static AppShortcut parse(String input) {
    if (input.isEmpty || input.length > 64 || input.trim() != input) {
      throw const AppShortcutException(AppShortcutFailureCode.invalid);
    }
    final parts = input.split('+');
    if (parts.any((part) => part.isEmpty)) {
      throw const AppShortcutException(AppShortcutFailureCode.invalid);
    }
    final keyToken = parts.last;
    final modifiers = <String>{};
    for (final raw in parts.take(parts.length - 1)) {
      final modifier = switch (raw.toLowerCase()) {
        'ctrl' || 'control' => 'Ctrl',
        'cmd' || 'command' || 'meta' => 'Cmd',
        'alt' || 'option' => 'Alt',
        'shift' => 'Shift',
        _ => null,
      };
      if (modifier == null || !modifiers.add(modifier)) {
        throw const AppShortcutException(AppShortcutFailureCode.invalid);
      }
    }
    if (modifiers.contains('Ctrl') && modifiers.contains('Cmd')) {
      throw const AppShortcutException(AppShortcutFailureCode.invalid);
    }
    final parsedKey = _parseKey(keyToken);
    final question = parsedKey == '?';
    if (question) modifiers.add('Shift');
    if ((modifiers.contains('Alt') && parsedKey == 'F4') ||
        (modifiers.contains('Ctrl') && parsedKey == 'Q') ||
        (modifiers.contains('Cmd') && parsedKey == 'Q')) {
      throw const AppShortcutException(AppShortcutFailureCode.reserved);
    }
    final canonicalModifiers = [
      'Ctrl',
      'Cmd',
      'Alt',
      'Shift',
    ].where(modifiers.contains).toList(growable: true);
    if (question) canonicalModifiers.remove('Shift');
    canonicalModifiers.add(parsedKey);
    return AppShortcut(
      canonical: canonicalModifiers.join('+'),
      key: parsedKey,
      control: modifiers.contains('Ctrl'),
      meta: modifiers.contains('Cmd'),
      alt: modifiers.contains('Alt'),
      shift: modifiers.contains('Shift'),
    );
  }

  static String _parseKey(String value) {
    final normalized = value.length == 1 ? value.toUpperCase() : value;
    final named = switch (normalized.toLowerCase()) {
      'enter' => 'Enter',
      'space' => 'Space',
      'tab' => 'Tab',
      'up' => 'Up',
      'down' => 'Down',
      'left' => 'Left',
      'right' => 'Right',
      'insert' => 'Insert',
      '?' => '?',
      ',' => ',',
      '/' => '/',
      '[' => '[',
      ']' => ']',
      _ => null,
    };
    if (named != null) return named;
    if (RegExp(r'^[A-Z]$').hasMatch(normalized)) {
      return normalized;
    }
    if (RegExp(r'^[0-9]$').hasMatch(normalized)) {
      return normalized;
    }
    final function = RegExp(
      r'^F([1-9]|1[0-9]|2[0-4])$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (function != null) {
      final number = int.parse(function.group(1)!);
      return 'F$number';
    }
    throw const AppShortcutException(AppShortcutFailureCode.invalid);
  }
}

abstract final class AppShortcutCatalog {
  static const maximumOverrides = 512;

  /// Commands that were removed. Settings written before may still carry
  /// overrides for them; loading drops those (ADR 0005 removed undo).
  static const retiredCommandIds = {'undo', 'redo', 'showRecovery'};

  /// The default binding of [command]; the registry is its only source.
  static String? defaultBinding(AppCommandId command, {required bool macOS}) =>
      AppCommandRegistry.byId(command).defaultShortcut(macOS: macOS);

  static Map<AppCommandId, AppShortcut?> resolve(
    List<ShortcutOverride> overrides, {
    required bool macOS,
  }) {
    if (overrides.length > maximumOverrides) {
      throw const AppShortcutException(AppShortcutFailureCode.tooManyOverrides);
    }
    final bindings = <AppCommandId, AppShortcut?>{
      for (final command in AppCommandId.values)
        command: switch (defaultBinding(command, macOS: macOS)) {
          final value? => AppShortcut.parse(value),
          null => null,
        },
    };
    final seen = <AppCommandId>{};
    for (final override in overrides) {
      final command = AppCommandId.values
          .where((value) => value.name == override.commandId)
          .firstOrNull;
      if (command == null) {
        throw const AppShortcutException(AppShortcutFailureCode.unknownCommand);
      }
      if (!seen.add(command)) {
        throw AppShortcutException(
          AppShortcutFailureCode.duplicateOverride,
          command: command,
        );
      }
      try {
        bindings[command] = override.binding == null
            ? null
            : AppShortcut.parse(override.binding!);
      } on AppShortcutException catch (error) {
        throw AppShortcutException(error.code, command: command);
      }
    }
    for (final scope in AppCommandShortcutScope.values) {
      final claimed = <String, AppCommandId>{};
      for (final entry in bindings.entries) {
        final definition = AppCommandRegistry.byId(entry.key);
        if (!definition.shortcutScopes.contains(
              AppCommandShortcutScope.global,
            ) &&
            !definition.shortcutScopes.contains(scope)) {
          continue;
        }
        final shortcut = entry.value;
        if (shortcut == null) continue;
        final previous = claimed[shortcut.canonical];
        if (previous != null) {
          throw AppShortcutException(
            AppShortcutFailureCode.conflict,
            command: entry.key,
            conflictingCommand: previous,
          );
        }
        claimed[shortcut.canonical] = entry.key;
      }
    }
    return Map.unmodifiable(bindings);
  }

  /// The shortcut each command shows: its binding in effect, or the key a
  /// focused list handles for it ([AppCommandDefinition.keyHint]) unless the
  /// user overrode the command.
  static Map<AppCommandId, AppShortcut?> shown(
    List<ShortcutOverride> overrides, {
    required bool macOS,
  }) {
    final overridden = overrides.map((entry) => entry.commandId).toSet();
    final resolved = resolve(overrides, macOS: macOS);
    return Map.unmodifiable({
      for (final command in AppCommandRegistry.commands)
        command.id:
            resolved[command.id] ??
            switch (command.keyHint) {
              final hint? when !overridden.contains(command.id.name) =>
                AppShortcut.parse(hint),
              _ => null,
            },
    });
  }

  static List<ShortcutOverride> replace(
    List<ShortcutOverride> overrides,
    AppCommandId command,
    String? input, {
    required bool macOS,
  }) {
    final normalized = input == null || input.trim().isEmpty
        ? null
        : AppShortcut.parse(input.trim()).canonical;
    final next = [
      for (final override in overrides)
        if (override.commandId != command.name) override,
      ShortcutOverride(commandId: command.name, binding: normalized),
    ];
    resolve(next, macOS: macOS);
    return List.unmodifiable(next);
  }
}
