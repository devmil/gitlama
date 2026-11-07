import '../models/settings.dart';

/// Whether paths exist in a working tree on this computer.
abstract interface class WorkingTreePathRepository {
  /// Whether the repository-relative [path] (Git's bytes, `/`-separated)
  /// exists below [root]; null when this cannot be told, such as for a path
  /// that is not valid UTF-8.
  Future<bool?> exists(NativePathIdentity root, List<int> path);
}
