import 'package:flutter/widgets.dart';

import '../../models/hosting.dart';
import '../../models/inspector.dart';
import '../../models/settings.dart';
import '../../services/hosting_connection_service.dart';
import '../file_actions/file_actions.dart';
import 'hosting_links.dart';

/// What the shell does with a file or folder a pane names: open it in the
/// editor or the file manager, open a folder, or inspect it at HEAD. Panes
/// read it here instead of receiving each callback through every layer.
class FileActionsScope extends InheritedWidget {
  const FileActionsScope({
    super.key,
    required this.openExternal,
    required this.revealInFileBrowser,
    required this.openFolder,
    required this.fileBrowserName,
    this.inspectWorkingFile,
    required super.child,
  });

  final ValueChanged<NativePathIdentity> openExternal;
  final ValueChanged<NativePathIdentity> revealInFileBrowser;

  /// Opens a repository or worktree folder in the file manager.
  final ValueChanged<NativePathIdentity> openFolder;

  /// The file manager's name in menus, such as Finder or Dolphin.
  final String fileBrowserName;

  /// Opens a working-tree file's blame or history at the current commit.
  final InspectWorkingFile? inspectWorkingFile;

  static FileActionsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FileActionsScope>();

  static FileActionsScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FileActionsScope>();
    assert(scope != null, 'No FileActionsScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(FileActionsScope oldWidget) =>
      fileBrowserName != oldWidget.fileBrowserName ||
      (inspectWorkingFile == null) != (oldWidget.inspectWorkingFile == null);
}

/// The hosting account's view of the active repository: its binding, the
/// pull requests and checks it found and their branch decorations.
class HostingScope extends InheritedWidget {
  const HostingScope({
    super.key,
    this.hosting,
    this.binding,
    this.resources = const HostingResources(),
    this.stale = false,
    this.branchDecorations = const {},
    this.links,
    required super.child,
  });

  final HostingConnectionService? hosting;
  final HostingBindingResolution? binding;
  final HostingResources resources;

  /// The resources are from an earlier refresh that failed since.
  final bool stale;
  final Map<String, HostingCheckState> branchDecorations;

  /// Pull requests linked to the shown branches, when an account is bound.
  final HostingLinks? links;

  static HostingScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HostingScope>() ??
      const HostingScope(child: SizedBox.shrink());

  @override
  bool updateShouldNotify(HostingScope oldWidget) =>
      hosting != oldWidget.hosting ||
      binding != oldWidget.binding ||
      !identical(resources, oldWidget.resources) ||
      stale != oldWidget.stale ||
      !identical(branchDecorations, oldWidget.branchDecorations) ||
      links != oldWidget.links;
}

/// How the History inspector sits in the workspace: maximized or not, its
/// file list hidden or not, and what it asks of the shell.
class InspectorHostScope extends InheritedWidget {
  const InspectorHostScope({
    super.key,
    required this.maximized,
    required this.onToggleMaximized,
    required this.onOpenWindowFailed,
    required this.filesHidden,
    required this.onCreatePatch,
    required super.child,
  });

  /// The inspector fills the workspace column instead of sharing it with
  /// the history graph.
  final bool maximized;
  final VoidCallback onToggleMaximized;
  final VoidCallback onOpenWindowFailed;
  final ValueNotifier<bool> filesHidden;

  /// Creates a patch of the commit diff on screen, limited to the paths.
  final void Function(InspectorTarget target, List<List<int>> paths)
  onCreatePatch;

  static InspectorHostScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<InspectorHostScope>();
    assert(scope != null, 'No InspectorHostScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(InspectorHostScope oldWidget) =>
      maximized != oldWidget.maximized || filesHidden != oldWidget.filesHidden;
}
