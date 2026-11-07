import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The macOS runner covers the window with the app icon until Dart draws.
/// The Flutter startup screen shows the same mark in the same place, so the
/// cover fades out as soon as that first frame is on screen.
abstract final class NativeLaunchScreen {
  static const channel = MethodChannel('gitlama/native_launch_screen');

  static Future<void> dismiss() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Test runners and secondary engines have no launch cover.
    } on PlatformException {
      // The cover is cosmetic; startup continues without it.
    }
  }
}
