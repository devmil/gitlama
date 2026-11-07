import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import '../models/app_shortcut.dart';

extension AppShortcutActivator on AppShortcut {
  SingleActivator get activator => SingleActivator(
    _logicalKey(key),
    control: control,
    meta: meta,
    alt: alt,
    shift: shift,
  );
}

List<String> platformShortcutKeys(AppShortcut shortcut) {
  final macOS = defaultTargetPlatform == TargetPlatform.macOS;
  return [
    if (shortcut.control) macOS ? '⌃' : 'Ctrl',
    if (shortcut.meta) macOS ? '⌘' : 'Meta',
    if (shortcut.shift) macOS ? '⇧' : 'Shift',
    if (shortcut.alt) macOS ? '⌥' : 'Alt',
    switch (shortcut.key) {
      'Enter' when macOS => '↵',
      'Enter' => 'Enter',
      _ => shortcut.key,
    },
  ];
}

LogicalKeyboardKey _logicalKey(String key) {
  final named = switch (key) {
    'Enter' => LogicalKeyboardKey.enter,
    'Space' => LogicalKeyboardKey.space,
    'Tab' => LogicalKeyboardKey.tab,
    'Up' => LogicalKeyboardKey.arrowUp,
    'Down' => LogicalKeyboardKey.arrowDown,
    'Left' => LogicalKeyboardKey.arrowLeft,
    'Right' => LogicalKeyboardKey.arrowRight,
    'Insert' => LogicalKeyboardKey.insert,
    '?' || '/' => LogicalKeyboardKey.slash,
    ',' => LogicalKeyboardKey.comma,
    '[' => LogicalKeyboardKey.bracketLeft,
    ']' => LogicalKeyboardKey.bracketRight,
    _ => null,
  };
  if (named != null) return named;
  if (RegExp(r'^[A-Z]$').hasMatch(key)) {
    return LogicalKeyboardKey.findKeyByKeyId(key.toLowerCase().codeUnitAt(0))!;
  }
  if (RegExp(r'^[0-9]$').hasMatch(key)) {
    const keys = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    return keys[int.parse(key)];
  }
  final function = RegExp(r'^F([1-9]|1[0-9]|2[0-4])$').firstMatch(key);
  if (function != null) {
    return LogicalKeyboardKey(
      LogicalKeyboardKey.f1.keyId + int.parse(function.group(1)!) - 1,
    );
  }
  throw StateError('Validated shortcut contains an unknown key token.');
}

/// [shortcut] as the platform writes it: `⌘⇧P` on macOS, `Ctrl+Shift+P`
/// elsewhere. Every shortcut label in the application uses this.
String platformShortcutLabel(AppShortcut shortcut) => platformShortcutKeys(
  shortcut,
).join(defaultTargetPlatform == TargetPlatform.macOS ? '' : '+');

/// The portable binding (`Ctrl+Shift+P`) for a recorded key press, or null
/// when no shortcut can use [key]. [AppShortcut.parse] still validates the
/// result.
String? shortcutBinding(
  LogicalKeyboardKey key, {
  required bool control,
  required bool meta,
  required bool alt,
  required bool shift,
}) {
  final token = _keyToken(key);
  if (token == null) return null;
  return [
    if (control) 'Ctrl',
    if (meta) 'Cmd',
    if (alt) 'Alt',
    if (shift) 'Shift',
    token,
  ].join('+');
}

String? _keyToken(LogicalKeyboardKey key) {
  final named = switch (key) {
    LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'Enter',
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.tab => 'Tab',
    LogicalKeyboardKey.arrowUp => 'Up',
    LogicalKeyboardKey.arrowDown => 'Down',
    LogicalKeyboardKey.arrowLeft => 'Left',
    LogicalKeyboardKey.arrowRight => 'Right',
    LogicalKeyboardKey.insert => 'Insert',
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.bracketLeft => '[',
    LogicalKeyboardKey.bracketRight => ']',
    _ => null,
  };
  if (named != null) return named;
  final id = key.keyId;
  if (id >= LogicalKeyboardKey.keyA.keyId &&
      id <= LogicalKeyboardKey.keyZ.keyId) {
    return String.fromCharCode(id).toUpperCase();
  }
  if (id >= LogicalKeyboardKey.digit0.keyId &&
      id <= LogicalKeyboardKey.digit9.keyId) {
    return String.fromCharCode(id);
  }
  if (id >= LogicalKeyboardKey.f1.keyId && id <= LogicalKeyboardKey.f24.keyId) {
    return 'F${id - LogicalKeyboardKey.f1.keyId + 1}';
  }
  return null;
}
