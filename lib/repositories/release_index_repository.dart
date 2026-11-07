import 'dart:convert';

import '../models/app_update.dart';

/// Owns the public project pages: the release index, the downloads page,
/// the issue tracker and the source repository.
abstract interface class ReleaseIndexRepository {
  /// Whether this platform reports updates from the public index.
  bool get isAvailable;

  /// Retained releases, newest build first.
  Future<List<PublishedRelease>> load();

  Future<void> openDownloads();

  /// Opens the public issue tracker, where users report problems.
  Future<void> openIssues();

  /// Opens the public source repository.
  Future<void> openSource();
}

/// The index is signed metadata of at most this size; the publisher enforces
/// the same bound.
const releaseIndexMaximumBytes = 1024 * 1024;

/// The publisher retains five releases per channel.
const releaseIndexMaximumReleases = 10;

/// Reads the releases of a GitLama release index.
///
/// The check only reports that a newer build exists and sends the user to
/// the downloads page, so asset records are not read here.
List<PublishedRelease> parseReleaseIndex(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > releaseIndexMaximumBytes) {
    throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
  }
  final Object? document;
  try {
    document = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
  }
  if (document is! Map<String, Object?> ||
      document['schema_version'] != 1 ||
      document['product'] != 'GitLama') {
    throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
  }
  final records = document['releases'];
  if (records is! List<Object?> ||
      records.isEmpty ||
      records.length > releaseIndexMaximumReleases) {
    throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
  }
  final releases = <PublishedRelease>[];
  final builds = <int>{};
  for (final record in records) {
    if (record is! Map<String, Object?>) {
      throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
    }
    final version = record['version'];
    final build = record['build'];
    final channel = ReleaseChannel.fromStorage(switch (record['channel']) {
      final String value => value,
      _ => null,
    });
    if (version is! String ||
        version.isEmpty ||
        version.length > 128 ||
        build is! int ||
        build < 1 ||
        channel == null ||
        version.contains('-') != (channel == ReleaseChannel.beta) ||
        !builds.add(build)) {
      throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
    }
    releases.add(
      PublishedRelease(version: version, build: build, channel: channel),
    );
  }
  releases.sort((left, right) => right.build.compareTo(left.build));
  return List.unmodifiable(releases);
}
