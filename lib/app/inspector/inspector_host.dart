import '../../models/inspector.dart';
import '../../services/repository_session_service.dart';

/// Where an inspector lives: the Detail pane of a repository window or an
/// inspector window. The inspector widget asks its host for everything that
/// reaches beyond the inspector itself.
abstract class InspectorHost {
  const InspectorHost();

  bool get isWindow;

  /// Whether the host can hide the history graph for the inspector.
  bool get canMaximize => false;
  bool get maximized => false;
  void toggleMaximize() {}

  /// Whether a location can open in a new inspector window.
  bool get supportsWindows;
  Future<void> openInWindow(InspectorLocation location);

  /// Selects [target] in a history graph: the pane's own, or the main
  /// window's for an inspector window.
  Future<bool> showInGraph(InspectorTarget target);

  /// Whether [showInGraph] can currently reach a graph.
  bool get canShowInGraph => true;

  /// `pane` or `window`: where Blame, Contents and History open.
  String get inspectionOpenIn;

  /// The repository's tools: external diff, editor and file manager. Null
  /// where none can run.
  RepositorySessionService? get repositories;

  /// Whether files of the working tree can be opened or revealed.
  bool get canOpenWorkingCopy;

  /// Whether the repository-relative [path] exists in the working tree,
  /// asked when a file menu opens. False where [canOpenWorkingCopy] is.
  Future<bool> existsInWorkingTree(List<int> path) async => false;

  /// Opens a repository-relative path of the working tree in the editor, or
  /// reveals it in the file manager.
  void openWorkingCopy(List<int> path, {required bool reveal});

  /// The file manager's name for "Reveal in …".
  String get fileBrowserName;

  /// Whether patches can be created here.
  bool get canCreatePatch;

  /// Creates a patch of [target] limited to [paths]; every change when empty.
  void createPatch(InspectorTarget target, List<List<int>> paths);

  /// Whether a commit's zip snapshot can be saved from here.
  bool get canSaveArchive => false;

  /// Saves the zip snapshot of [commit].
  void saveArchive(String commit) {}

  /// Whether a file can be restored to its content in a commit.
  bool get canRestore;

  /// Whether the repository lives on another computer, where restoring and
  /// local tools are unavailable. Its windows read through the main
  /// window's connection.
  bool get remote => false;

  /// Whether windows would open but the repository's remote host is not
  /// connected now; the window action is shown disabled.
  bool get windowsDisconnected => false;

  /// Full ref names pointing at [commit], for the summary card.
  List<String> refsFor(String commit) => const [];
}
