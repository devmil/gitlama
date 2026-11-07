import 'dart:convert';

import 'inspector.dart';
import 'remote_workspace.dart';
import 'settings.dart';

/// Asks the main window to select a commit, or the two commits of a
/// comparison, in the graph of a repository it has open.
final class InspectorRevealRequest {
  const InspectorRevealRequest({
    required this.repository,
    required this.commit,
    this.base,
  });

  final NativePathIdentity repository;
  final String commit;
  final String? base;

  String encode() => jsonEncode({
    'schema': 2,
    'platform': repository.platform.name,
    'units': repository.units.toList(),
    'commit': commit,
    'base': ?base,
    'remote': ?repository.remote?.toMessage(),
  });

  static InspectorRevealRequest? decode(Object? value) {
    if (value is! String || value.isEmpty || value.length > 65536) return null;
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic>) return null;
      final schema = data['schema'];
      if (schema != 1 && schema != 2) return null;
      final remoteData = data['remote'];
      final remote = remoteData == null
          ? null
          : remoteAuthorityFromMessage(remoteData);
      if (remoteData != null && (schema != 2 || remote == null)) return null;
      final platform = NativePathPlatform.values
          .where((item) => item.name == data['platform'])
          .firstOrNull;
      final units = data['units'];
      final commit = data['commit'];
      final base = data['base'];
      if (platform == null ||
          units is! List ||
          units.isEmpty ||
          units.length > 16384 ||
          units.any((unit) => unit is! int || unit < 0 || unit > 65535) ||
          !InspectorLocation.isObjectId(commit) ||
          (base != null && !InspectorLocation.isObjectId(base))) {
        return null;
      }
      final repository = NativePathIdentity(
        platform: platform,
        units: units.cast<int>(),
        remote: remote,
      );
      if (!repository.isValidLocation) return null;
      return InspectorRevealRequest(
        repository: repository,
        commit: commit as String,
        base: base as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
