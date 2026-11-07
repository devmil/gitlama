import 'dart:async';

import '../models/app_update.dart';
import '../models/settings.dart';
import '../repositories/app_updater_repository.dart';
import '../repositories/installed_release_repository.dart';
import '../repositories/release_index_repository.dart';
import 'settings_service.dart';

/// Owns update checks and the release channel.
///
/// macOS hands the work to its platform updater, which checks on its own
/// schedule and installs. Linux and Windows compare the installed build with
/// the public release index when the user asks and point to the downloads
/// page. A failure here never blocks startup.
final class AppUpdateService {
  AppUpdateService(
    this._installedReleases,
    this._updater,
    this._index,
    this._settings, {
    this.checkInterval = const Duration(days: 1),
  });

  final InstalledReleaseRepository _installedReleases;
  final AppUpdaterRepository _updater;
  final ReleaseIndexRepository _index;
  final SettingsService _settings;
  final Duration checkInterval;

  StreamSubscription<SettingsDocument>? _subscription;
  InstalledRelease? _installed;
  ReleaseChannel? _configured;
  Future<void> _configuration = Future.value();
  var _disposed = false;

  /// Null when the installed release could not be identified.
  InstalledRelease? get installed => _installed;

  bool get isSupported =>
      _installed != null && (_updater.isAvailable || _index.isAvailable);

  /// True when the platform updater downloads and installs releases.
  bool get installsUpdates => _installed != null && _updater.isAvailable;

  ReleaseChannel get channel =>
      _settings.current.releaseChannel ??
      _installed?.channel ??
      ReleaseChannel.stable;

  Future<void> initialize() async {
    try {
      _installed = await _installedReleases.load();
    } on Object {
      return;
    }
    if (!_updater.isAvailable) return;
    _subscription = _settings.changes.listen((_) => unawaited(_configure()));
    await _configure();
  }

  Future<void> selectChannel(ReleaseChannel channel) => _settings.updateDurable(
    (document) => document.copyWith(releaseChannel: channel),
    restore: (current, previous) => current.copyWith(
      releaseChannel: previous.releaseChannel,
      clearReleaseChannel: previous.releaseChannel == null,
    ),
  );

  Future<AppUpdateCheck> check() async {
    final installed = _installed;
    if (installed == null || !isSupported || _disposed) {
      throw const AppUpdateException(AppUpdateFailureCode.unsupported);
    }
    if (_updater.isAvailable) {
      await _configure();
      if (_configured != channel) {
        throw const AppUpdateException(AppUpdateFailureCode.nativeUpdater);
      }
      await _updater.checkForUpdates();
      return AppUpdateCheck(
        status: AppUpdateStatus.nativeCheckerOpened,
        installed: installed,
      );
    }
    final selected = channel;
    final latest = latestRelease(await _index.load(), selected);
    if (latest == null) {
      return AppUpdateCheck(
        status: AppUpdateStatus.noPublishedRelease,
        installed: installed,
      );
    }
    return AppUpdateCheck(
      status: latest.build > installed.build
          ? AppUpdateStatus.updateAvailable
          : AppUpdateStatus.upToDate,
      installed: installed,
      available: latest,
    );
  }

  Future<void> openDownloads() => _index.openDownloads();

  Future<void> openIssues() => _index.openIssues();

  /// The newest release a subscriber of [channel] receives.
  static PublishedRelease? latestRelease(
    Iterable<PublishedRelease> releases,
    ReleaseChannel channel,
  ) {
    PublishedRelease? latest;
    for (final release in releases) {
      if (channel == ReleaseChannel.stable &&
          release.channel != ReleaseChannel.stable) {
        continue;
      }
      if (latest == null || release.build > latest.build) latest = release;
    }
    return latest;
  }

  /// Serialized so a quick channel change cannot be overtaken by an older one.
  Future<void> _configure() {
    return _configuration = _configuration.then((_) async {
      final selected = channel;
      if (_disposed || _configured == selected) return;
      try {
        await _updater.configure(
          channel: selected,
          checkInterval: checkInterval,
        );
        _configured = selected;
      } on AppUpdateException {
        _configured = null;
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _configuration;
  }
}
