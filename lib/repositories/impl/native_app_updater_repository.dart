import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/app_update.dart';
import '../app_updater_repository.dart';

/// Drives Sparkle through the macOS runner.
///
/// Sparkle keeps its state in the user's defaults for the bundle identifier.
/// A debug run or a qualification launch with an isolated profile must not
/// touch that state or prompt, so neither has an updater.
final class NativeAppUpdaterRepository implements AppUpdaterRepository {
  NativeAppUpdaterRepository({MethodChannel? channel, bool? available})
    : _channel = channel ?? const MethodChannel(channelName),
      isAvailable = available ?? _platformHasUpdater();

  static const channelName = 'gitlama/app_update';

  /// The appcast the release workflow publishes beside the release index.
  static const feedUrl = 'https://devmil.de/gitlama/appcast.xml';

  final MethodChannel _channel;

  @override
  final bool isAvailable;

  static bool _platformHasUpdater() =>
      Platform.isMacOS &&
      !kDebugMode &&
      !Platform.environment.containsKey('GITLAMA_PROFILE_ROOT');

  @override
  Future<void> configure({
    required ReleaseChannel channel,
    required Duration checkInterval,
  }) => _invoke('configure', {
    'feedUrl': feedUrl,
    'releaseChannel': channel.name,
    'checkIntervalSeconds': checkInterval.inSeconds,
  });

  @override
  Future<void> checkForUpdates() => _invoke('checkForUpdates');

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!isAvailable) {
      throw const AppUpdateException(AppUpdateFailureCode.unsupported);
    }
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      throw const AppUpdateException(AppUpdateFailureCode.nativeUpdater);
    } on MissingPluginException {
      throw const AppUpdateException(AppUpdateFailureCode.unsupported);
    }
  }
}
