import '../models/settings.dart';
import '../repositories/working_tree_path_repository.dart';

/// Tells file menus whether a path of a commit exists in the working tree,
/// so local editors and the file manager are only offered for files that
/// are there.
final class WorkingTreePaths {
  WorkingTreePaths(this._repository);

  /// Every path counts as present: what windows without a file system check
  /// offered before the check existed.
  WorkingTreePaths.unchecked() : _repository = const _Unchecked();

  final WorkingTreePathRepository _repository;

  /// Whether [path] exists below [root]. A remote root has no local working
  /// tree; a path that cannot be checked counts as present, and opening it
  /// reports its own failure.
  Future<bool> exists(NativePathIdentity root, List<int> path) async {
    if (root.isRemote) return false;
    try {
      return await _repository.exists(root, path) ?? true;
    } on Object {
      return true;
    }
  }
}

final class _Unchecked implements WorkingTreePathRepository {
  const _Unchecked();

  @override
  Future<bool?> exists(NativePathIdentity root, List<int> path) async => null;
}
