import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

import '../../models/app_update.dart';
import '../release_index_repository.dart';

/// Reads the release index over HTTPS and opens the downloads page and the
/// issue tracker.
///
/// The request is bounded in time and size and follows no redirect. Nothing
/// from the index is opened or downloaded: both pages are fixed.
final class NativeReleaseIndexRepository implements ReleaseIndexRepository {
  NativeReleaseIndexRepository({
    Uri? index,
    Uri? downloads,
    Uri? issues,
    bool? available,
    HttpClient Function()? createClient,
    Future<bool> Function(Uri uri)? open,
    this.timeout = const Duration(seconds: 15),
  }) : _index = index ?? Uri.parse(indexUrl),
       _downloads = downloads ?? Uri.parse(downloadsUrl),
       _issues = issues ?? Uri.parse(issuesUrl),
       isAvailable = available ?? (Platform.isLinux || Platform.isWindows),
       _createClient = createClient ?? HttpClient.new,
       _open = open ?? _openExternally;

  static const indexUrl = 'https://devmil.de/gitlama/_data/releases.json';
  static const downloadsUrl = 'https://devmil.de/gitlama/releases.html';
  static const issuesUrl = 'https://github.com/devmil/gitlama/issues';

  final Uri _index;
  final Uri _downloads;
  final Uri _issues;
  final HttpClient Function() _createClient;
  final Future<bool> Function(Uri uri) _open;
  final Duration timeout;

  @override
  final bool isAvailable;

  static Future<bool> _openExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<List<PublishedRelease>> load() async {
    if (_index.scheme != 'https' || _index.userInfo.isNotEmpty) {
      throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
    }
    final client = _createClient()..connectionTimeout = timeout;
    try {
      return parseReleaseIndex(await _fetch(client).timeout(timeout));
    } on AppUpdateException {
      rethrow;
    } on Object {
      // Socket, TLS, HTTP and timeout failures carry host details.
      throw const AppUpdateException(AppUpdateFailureCode.unavailable);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _fetch(HttpClient client) async {
    final request = await client.getUrl(_index);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const AppUpdateException(AppUpdateFailureCode.unavailable);
    }
    if (response.contentLength > releaseIndexMaximumBytes) {
      throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > releaseIndexMaximumBytes) {
        throw const AppUpdateException(AppUpdateFailureCode.invalidIndex);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<void> openDownloads() => _openPage(_downloads);

  @override
  Future<void> openIssues() => _openPage(_issues);

  Future<void> _openPage(Uri page) async {
    final bool opened;
    try {
      opened = await _open(page);
    } on Object {
      throw const AppUpdateException(AppUpdateFailureCode.openFailed);
    }
    if (!opened) {
      throw const AppUpdateException(AppUpdateFailureCode.openFailed);
    }
  }
}
