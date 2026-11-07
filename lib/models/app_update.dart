/// A public release track. Beta subscribers also receive stable releases.
enum ReleaseChannel {
  stable,
  beta;

  static ReleaseChannel? fromStorage(String? value) => switch (value) {
    'stable' => ReleaseChannel.stable,
    'beta' => ReleaseChannel.beta,
    _ => null,
  };
}

/// The release this application was built as.
final class InstalledRelease {
  const InstalledRelease({required this.version, required this.build});

  final String version;
  final int build;

  /// A prerelease build follows the beta channel until the user chooses.
  ReleaseChannel get channel =>
      version.contains('-') ? ReleaseChannel.beta : ReleaseChannel.stable;
}

/// One release from the public index.
final class PublishedRelease {
  const PublishedRelease({
    required this.version,
    required this.build,
    required this.channel,
  });

  final String version;
  final int build;
  final ReleaseChannel channel;
}

enum AppUpdateStatus {
  /// The platform updater took over and shows its own progress.
  nativeCheckerOpened,
  upToDate,
  updateAvailable,
  noPublishedRelease,
}

final class AppUpdateCheck {
  const AppUpdateCheck({
    required this.status,
    required this.installed,
    this.available,
  });

  final AppUpdateStatus status;
  final InstalledRelease installed;
  final PublishedRelease? available;
}

enum AppUpdateFailureCode {
  /// This build or platform has no update check.
  unsupported,

  /// The release index could not be reached in time.
  unavailable,

  /// The release index was oversized, malformed or for another product.
  invalidIndex,

  /// The platform updater rejected the request.
  nativeUpdater,

  /// The downloads page could not be opened.
  openFailed,
}

final class AppUpdateException implements Exception {
  const AppUpdateException(this.code);
  final AppUpdateFailureCode code;

  @override
  String toString() => 'AppUpdateException(${code.name})';
}
