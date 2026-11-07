import 'dart:convert';

import 'settings.dart';

/// A repository-relative Git path as a native path on [root]'s platform.
NativePathIdentity relativeNativePath(
  NativePathIdentity root,
  List<int> path,
) => NativePathIdentity(
  platform: root.platform,
  units: switch (root.platform) {
    NativePathPlatform.unix => List<int>.of(path),
    NativePathPlatform.windows =>
      utf8.decode(path, allowMalformed: true).replaceAll('/', r'\').codeUnits,
  },
);

/// [relative] inside the repository at [root]; an absolute [relative] stays
/// as it is, on [root]'s computer.
NativePathIdentity repositoryFileIdentity(
  NativePathIdentity root,
  NativePathIdentity relative,
) {
  if (root.platform != relative.platform) return relative;
  final separator = root.platform == NativePathPlatform.windows ? 92 : 47;
  final absolute =
      relative.units.isNotEmpty &&
      (relative.units.first == 47 ||
          relative.units.first == 92 ||
          (root.platform == NativePathPlatform.windows &&
              relative.units.length > 1 &&
              relative.units[1] == 58));
  if (absolute) {
    return root.remote == null
        ? relative
        : NativePathIdentity(
            platform: relative.platform,
            units: relative.units,
            remote: root.remote,
          );
  }
  return NativePathIdentity(
    platform: root.platform,
    units: [
      ...root.units,
      if (root.units.isNotEmpty && root.units.last != separator) separator,
      ...relative.units,
    ],
    // A path inside a remote repository stays on that computer.
    remote: root.remote,
  );
}

/// The directory [directory] (a repository-relative path with `/`) of the
/// native path [descendant], which lies inside it.
NativePathIdentity directoryNativePath(
  NativePathIdentity descendant,
  String directory,
) {
  final parts = directory.split('/').where((part) => part.isNotEmpty).length;
  var separators = 0;
  for (var index = 0; index < descendant.units.length; index += 1) {
    final unit = descendant.units[index];
    if (unit == 47 || unit == 92) {
      separators += 1;
      if (separators == parts) {
        return NativePathIdentity(
          platform: descendant.platform,
          units: descendant.units.sublist(0, index),
          remote: descendant.remote,
        );
      }
    }
  }
  return descendant;
}

/// The folder that contains [path]; [path] itself at the top.
NativePathIdentity parentNativePath(NativePathIdentity path) {
  for (var index = path.units.length - 1; index >= 0; index -= 1) {
    if (path.units[index] == 47 || path.units[index] == 92) {
      return NativePathIdentity(
        platform: path.platform,
        units: path.units.sublist(0, index),
        remote: path.remote,
      );
    }
  }
  return path;
}

/// The repository-relative path bytes Git uses for [identity]: UTF-8 with
/// `/` separators.
List<int> repositoryPathBytes(NativePathIdentity identity) =>
    switch (identity.platform) {
      NativePathPlatform.unix => [
        for (final unit in identity.units) unit & 0xff,
      ],
      NativePathPlatform.windows => utf8.encode(
        String.fromCharCodes(identity.units).replaceAll(r'\', '/'),
      ),
    };
