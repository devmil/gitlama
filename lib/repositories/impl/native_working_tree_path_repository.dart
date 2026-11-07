import 'dart:convert';
import 'dart:io';

import '../../models/settings.dart';
import '../working_tree_path_repository.dart';

/// Looks working-tree paths up in this computer's file system. A symbolic
/// link counts as present, whatever it points at.
final class NativeWorkingTreePathRepository
    implements WorkingTreePathRepository {
  const NativeWorkingTreePathRepository();

  @override
  Future<bool?> exists(NativePathIdentity root, List<int> path) async {
    if (root.isRemote || path.isEmpty) return false;
    final String relative;
    try {
      relative = utf8.decode(path);
    } on FormatException {
      return null;
    }
    final String base = switch (root.platform) {
      NativePathPlatform.unix => utf8.decode(root.units, allowMalformed: true),
      NativePathPlatform.windows => String.fromCharCodes(root.units),
    };
    final separator = root.platform == NativePathPlatform.windows ? r'\' : '/';
    final joined = [
      base.endsWith(separator) ? base.substring(0, base.length - 1) : base,
      if (separator == '/') relative else relative.replaceAll('/', separator),
    ].join(separator);
    try {
      return await FileSystemEntity.type(joined, followLinks: false) !=
          FileSystemEntityType.notFound;
    } on FileSystemException {
      return null;
    }
  }
}
