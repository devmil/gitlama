import 'dart:convert';

import 'inspector.dart';
import 'remote_workspace.dart';
import 'settings.dart';

/// In-process launch data for a read-only desktop inspector window.
///
/// Schema 3 carries the remote authority of a repository on a remote host;
/// schemas 1 and 2 always meant a repository on this computer.
final class InspectionWindowRequest {
  const InspectionWindowRequest({
    required this.repository,
    required this.location,
  });

  final NativePathIdentity repository;
  final InspectorLocation location;

  String encode() => jsonEncode({
    'schema': 3,
    'platform': repository.platform.name,
    'units': repository.units.toList(),
    'location': location.toJson(),
    'remote': ?repository.remote?.toMessage(),
  });

  static InspectionWindowRequest? decode(String value) {
    if (value.isEmpty || value.length > 65536) return null;
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, dynamic>) return null;
      final platform = NativePathPlatform.values
          .where((item) => item.name == data['platform'])
          .firstOrNull;
      final units = data['units'];
      if (platform == null ||
          units is! List ||
          units.isEmpty ||
          units.length > 16384 ||
          units.any((unit) => unit is! int || unit < 0 || unit > 65535)) {
        return null;
      }
      final schema = data['schema'];
      final remoteData = data['remote'];
      final remote = remoteData == null
          ? null
          : remoteAuthorityFromMessage(remoteData);
      if (remoteData != null && (schema != 3 || remote == null)) return null;
      final repository = NativePathIdentity(
        platform: platform,
        units: units.cast<int>(),
        remote: remote,
      );
      if (!repository.isValidLocation) return null;
      final location = switch (schema) {
        1 => _schemaOneLocation(data),
        2 || 3 => InspectorLocation.fromJson(data['location']),
        _ => null,
      };
      if (location == null) return null;
      return InspectionWindowRequest(
        repository: repository,
        location: location.normalized(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Schema 1 opened either a file's blame or a commit's tree, optionally at
  /// a folder.
  static InspectorLocation? _schemaOneLocation(Map<String, dynamic> data) {
    final kind = data['kind'];
    final commit = data['commit'];
    final path = data['path'];
    if (!InspectorLocation.isObjectId(commit)) return null;
    final pathBytes = path == null
        ? null
        : InspectorLocation.validPathBytes(path);
    if (path != null && pathBytes == null) return null;
    final target = CommitTarget(commit as String);
    return switch (kind) {
      'blame' when pathBytes != null => InspectorLocation(
        target: target,
        path: pathBytes,
        lens: InspectorLens.blame,
      ),
      'tree' => InspectorLocation(
        target: target,
        scope: InspectorScope.all,
        path: pathBytes,
        directory: pathBytes != null,
        lens: pathBytes != null ? InspectorLens.history : InspectorLens.diff,
      ),
      _ => null,
    };
  }
}
