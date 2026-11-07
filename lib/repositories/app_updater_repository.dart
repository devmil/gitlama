import '../models/app_update.dart';

/// Owns the platform updater that downloads and installs releases itself.
///
/// Only macOS has one (Sparkle). It keeps its own schedule and windows, so
/// the application configures it and asks it to check.
abstract interface class AppUpdaterRepository {
  /// Whether this process may drive a platform updater.
  bool get isAvailable;

  Future<void> configure({
    required ReleaseChannel channel,
    required Duration checkInterval,
  });

  /// Opens the updater's own check window.
  Future<void> checkForUpdates();
}
