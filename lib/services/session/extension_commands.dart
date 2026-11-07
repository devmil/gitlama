import '../../models/repository_extensions.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../repositories/extension_repository.dart';
import 'session_scope.dart';

/// What worktree and submodule commands need from the workspace's tabs.
abstract interface class ExtensionTabs {
  /// Opens [identity] in a tab, or activates the tab that shows it.
  Future<RepositorySessionState> openRecent(NativePathIdentity identity);

  /// Closes every tab of the worktree [root] except the one of [source], and
  /// returns the worktrees it closed.
  Future<List<NativePathIdentity>> closeWorktreeTabs(
    NativePathIdentity root,
    RepositorySessionIdentity source,
  );

  /// Reopens [worktrees] and activates [source]'s tab again.
  Future<void> restoreWorktreeTabs(
    List<NativePathIdentity> worktrees,
    RepositorySessionIdentity source,
  );
}

/// Worktrees, submodules, LFS and `.gitignore` entries of the active
/// repository.
final class ExtensionCommands {
  ExtensionCommands(this._repository, this._scope, this._tabs);

  final ExtensionRepositorySessionRepository _repository;
  final SessionScope _scope;
  final ExtensionTabs _tabs;

  Future<RepositoryExtensionInventory> inventory() =>
      _repository.repositoryExtensions(_scope.requireCurrent());

  Future<RepositorySessionState> enterSubmodule(
    SubmoduleEntry submodule,
  ) async {
    final identity = await _repository.enterSubmodule(
      _scope.requireCurrent(),
      submodule.path,
    );
    return _tabs.openRecent(identity);
  }

  Future<RepositorySessionState> openWorktree(WorktreeEntry worktree) =>
      _tabs.openRecent(worktree.worktreeRoot);

  Future<LfsPointer?> inspectLfsPointer(LfsEntry entry) =>
      _repository.inspectLfsPointer(_scope.requireCurrent(), entry.path);

  /// The `.gitignore` entry that matches exactly [path], or null when none
  /// can.
  String? exactIgnorePattern(List<int> path, {required bool directory}) =>
      _repository.exactIgnorePattern(path, directory: directory);

  /// Runs [request]. Deleting a worktree first closes its other tabs, and
  /// reopens them when the deletion does not happen.
  Future<RepositoryExtensionMutationResult> execute(
    RepositoryExtensionMutationRequest request,
  ) async {
    final identity = _scope.requireCurrent();
    var closedWorktrees = const <NativePathIdentity>[];
    if (request.kind == RepositoryExtensionMutationKind.worktreeDelete &&
        request.worktreeRoot != null) {
      closedWorktrees = await _tabs.closeWorktreeTabs(
        request.worktreeRoot!,
        identity,
      );
    }
    RepositoryExtensionMutationResult result;
    try {
      result = await _repository.executeRepositoryExtension(identity, request);
    } catch (_) {
      await _tabs.restoreWorktreeTabs(closedWorktrees, identity);
      rethrow;
    }
    // An uncertain deletion may have kept the worktree: its tabs come back.
    if (result.state == RepositoryExtensionMutationState.failed ||
        result.state == RepositoryExtensionMutationState.canceled ||
        result.state == RepositoryExtensionMutationState.outcomeUncertain) {
      await _tabs.restoreWorktreeTabs(closedWorktrees, identity);
    }
    return result;
  }
}
