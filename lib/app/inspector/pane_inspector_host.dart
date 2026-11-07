import 'dart:convert';

import '../../models/history.dart';
import '../../models/inspector.dart';
import '../../models/settings.dart';
import '../../services/history_service.dart';
import '../../services/inspection_window_service.dart';
import '../../services/repository_session_service.dart';
import '../workspace/status_bar.dart';
import 'inspector_host.dart';

/// The Detail island of a repository window.
final class PaneInspectorHost extends InspectorHost {
  const PaneInspectorHost({
    required this.historyService,
    required this.repositoryIdentity,
    required this.inspectionWindows,
    required this.repositories,
    required this.inspectionOpenIn,
    required this.fileBrowserName,
    required this.maximized,
    required this.onToggleMaximize,
    required this.onOpenFile,
    required this.onRevealFile,
    required this.onCreatePatch,
    this.onSaveArchive,
    required this.onOpenWindowFailed,
    required this.remote,
    this.remoteConnected = true,
    this.restoreAllowed = true,
  });

  final HistoryService historyService;
  final NativePathIdentity? repositoryIdentity;
  final InspectionWindowService inspectionWindows;
  @override
  final RepositorySessionService repositories;
  @override
  final String inspectionOpenIn;
  @override
  final String fileBrowserName;
  @override
  final bool maximized;
  final void Function() onToggleMaximize;

  /// Opens or reveals a path relative to the repository root.
  final void Function(NativePathIdentity relative) onOpenFile;
  final void Function(NativePathIdentity relative) onRevealFile;
  final void Function(InspectorTarget target, List<List<int>> paths)
  onCreatePatch;

  /// Saves the zip snapshot of a commit; null where none can be saved.
  final void Function(String commit)? onSaveArchive;
  final void Function() onOpenWindowFailed;

  /// The repository lives on another computer.
  @override
  final bool remote;

  /// Whether the remote host of the repository is connected now: its
  /// inspector windows read through that connection.
  final bool remoteConnected;

  /// Whether files may be restored: a host must allow recovery changes.
  final bool restoreAllowed;

  @override
  bool get isWindow => false;

  @override
  bool get canMaximize => true;

  @override
  void toggleMaximize() => onToggleMaximize();

  @override
  bool get supportsWindows => _windowsOffered && (!remote || remoteConnected);

  /// A remote repository's window must name its host, never a local path.
  bool get _windowsOffered =>
      inspectionWindows.available &&
      switch (repositoryIdentity) {
        null => false,
        final identity => identity.isRemote == remote,
      };

  @override
  bool get windowsDisconnected => _windowsOffered && remote && !remoteConnected;

  @override
  Future<void> openInWindow(InspectorLocation location) async {
    final repository = repositoryIdentity;
    if (!supportsWindows || repository == null) return;
    try {
      await inspectionWindows.open(repository: repository, location: location);
    } on Object {
      onOpenWindowFailed();
    }
  }

  @override
  Future<bool> showInGraph(InspectorTarget target) async {
    switch (target) {
      case ComparisonTarget(:final base, :final commit):
        await historyService.select(base, reveal: true, focus: false);
        await historyService.select(commit, toggle: true, focus: false);
      case CommitTarget(:final commit):
        await historyService.select(commit, reveal: true, focus: false);
    }
    return true;
  }

  @override
  bool get canOpenWorkingCopy => !remote && repositoryIdentity != null;

  NativePathIdentity? _relative(List<int> path) {
    final root = repositoryIdentity;
    return root == null ? null : relativeNativePath(root, path);
  }

  @override
  Future<bool> existsInWorkingTree(List<int> path) async {
    final root = repositoryIdentity;
    if (!canOpenWorkingCopy || root == null) return false;
    return repositories.workingTreePaths.exists(root, path);
  }

  @override
  void openWorkingCopy(List<int> path, {required bool reveal}) {
    final relative = _relative(path);
    if (relative == null) return;
    reveal ? onRevealFile(relative) : onOpenFile(relative);
  }

  @override
  bool get canCreatePatch => true;

  @override
  void createPatch(InspectorTarget target, List<List<int>> paths) =>
      onCreatePatch(target, paths);

  @override
  bool get canSaveArchive => onSaveArchive != null;

  @override
  void saveArchive(String commit) => onSaveArchive?.call(commit);

  @override
  bool get canRestore => restoreAllowed;

  /// Hosts are equal when they show the same repository the same way, so a
  /// rebuild of the workspace does not recreate the inspector's actions.
  /// The callbacks reach the same shell whatever closure carries them.
  @override
  bool operator ==(Object other) =>
      other is PaneInspectorHost &&
      other.historyService == historyService &&
      other.repositoryIdentity == repositoryIdentity &&
      other.inspectionWindows == inspectionWindows &&
      other.repositories == repositories &&
      other.inspectionOpenIn == inspectionOpenIn &&
      other.fileBrowserName == fileBrowserName &&
      other.maximized == maximized &&
      other.remote == remote &&
      other.remoteConnected == remoteConnected &&
      other.restoreAllowed == restoreAllowed;

  @override
  int get hashCode => Object.hash(
    historyService,
    repositoryIdentity,
    inspectionWindows,
    repositories,
    inspectionOpenIn,
    fileBrowserName,
    maximized,
    remote,
    remoteConnected,
    restoreAllowed,
  );

  @override
  List<String> refsFor(String commit) => [
    for (final row
        in historyService.current.page?.rows ?? const <HistoryTopologyRow>[])
      if (row.objectId == commit)
        for (final ref in row.refs) utf8.decode(ref, allowMalformed: true),
  ];
}
