import '../models/repository_extensions.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';

abstract interface class ExtensionRepositorySessionRepository {
  Future<RepositoryExtensionInventory> repositoryExtensions(
    RepositorySessionIdentity identity,
  );

  Future<NativePathIdentity> enterSubmodule(
    RepositorySessionIdentity identity,
    List<int> path,
  );

  Future<LfsPointer?> inspectLfsPointer(
    RepositorySessionIdentity identity,
    List<int> path,
  );

  /// The top-level `.gitignore` entry that matches exactly [path], a folder
  /// when [directory], or null when no entry can express it. A pure
  /// computation: it reads no repository.
  String? exactIgnorePattern(List<int> path, {required bool directory});

  Future<RepositoryExtensionMutationResult> executeRepositoryExtension(
    RepositorySessionIdentity identity,
    RepositoryExtensionMutationRequest request,
  );
}
