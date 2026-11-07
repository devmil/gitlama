import 'dart:async';

import '../../models/inspector.dart';
import '../../models/inspector_reveal.dart';
import '../../models/workspace.dart';
import '../repository_session_service.dart';

/// The workspace's navigation sequences: which pane a tab shows, which
/// commit History selects and how a commit is brought on screen. Every
/// surface that navigates goes through these, so the steps exist once.
final class WorkspaceNavigator {
  WorkspaceNavigator(this._repositories) {
    _activeTab = _repositories.activeTabId;
    _workspace = _repositories.workspaceStates.listen((workspace) {
      final active = workspace.activeTabId;
      if (active == _activeTab) return;
      // A tab's sidebar selection, like its revealed reference, ends when
      // the tab is left.
      if (_selectedReferences.remove(_activeTab) != null) _notifyReferences();
      _activeTab = active;
    });
  }

  final RepositorySessionService _repositories;
  late final StreamSubscription<WorkspaceState> _workspace;
  int? _activeTab;
  final Map<int, String> _selectedReferences = {};
  final StreamController<void> _referenceChanges =
      StreamController<void>.broadcast(sync: true);

  /// Fires when the sidebar selection of a tab changes.
  Stream<void> get referenceChanges => _referenceChanges.stream;

  void _notifyReferences() {
    if (!_referenceChanges.isClosed) _referenceChanges.add(null);
  }

  /// The sidebar row selected in tab [tabId].
  String? selectedReference(int? tabId) => _selectedReferences[tabId];

  /// Selects the sidebar row [reference] in the active tab. [reveal] is the
  /// reference History shows while it is selected, even when its branch
  /// filter hides it; null shows the filter as it is.
  void selectReference(String reference, {String? reveal}) {
    final tabId = _repositories.activeTabId;
    if (tabId == null) return;
    _selectedReferences[tabId] = reference;
    _notifyReferences();
    unawaited(_repositories.revealReference(tabId, reveal));
  }

  Future<void> dispose() async {
    await _workspace.cancel();
    await _referenceChanges.close();
  }

  /// Shows [pane] in tab [tabId], the active tab when null. The active tab
  /// loads History or leaves its selection; another tab only remembers the
  /// pane until it is shown.
  void selectPane(WorkspacePane pane, {int? tabId}) {
    final active = _repositories.activeTab;
    final tab = tabId == null || tabId == active?.id
        ? active
        : _repositories.workspace.tabs
              .where((tab) => tab.id == tabId)
              .firstOrNull;
    if (tab == null) return;
    _repositories.updateNavigation(
      tab.id,
      tab.navigation.copyWith(
        pane: pane,
        route: WorkspaceRoute.repository,
        clearSelectedIdentity: true,
      ),
    );
    if (tab.id != active?.id) return;
    if (pane == WorkspacePane.history) {
      unawaited(_repositories.showHistory(tab.id));
    } else if (pane == WorkspacePane.changes) {
      unawaited(_repositories.history.select(null, focus: false));
    }
  }

  /// Switches the active tab between Changes and History.
  void nextPane() => selectPane(
    _repositories.activeTab?.navigation.pane == WorkspacePane.changes
        ? WorkspacePane.history
        : WorkspacePane.changes,
  );

  /// Selects [identity] (a commit or a path) in the active tab.
  void selectIdentity(String identity) {
    final active = _remember(identity);
    if (active?.navigation.pane == WorkspacePane.history) {
      unawaited(_repositories.history.select(identity));
    }
  }

  /// Adds [identity] to History's selection or removes it.
  void toggleIdentity(String identity) {
    if (_remember(identity) == null) return;
    unawaited(
      _repositories.history.select(identity, toggle: true, focus: true),
    );
  }

  /// Selects [identity] in History and scrolls it into view without moving
  /// focus.
  void revealIdentity(String identity) {
    if (_remember(identity) == null) return;
    unawaited(
      _repositories.history.select(identity, reveal: true, focus: false),
    );
  }

  RepositoryTabState? _remember(String identity) {
    final active = _repositories.activeTab;
    if (active == null) return null;
    _repositories.updateNavigation(
      active.id,
      active.navigation.copyWith(selectedIdentity: identity),
    );
    return active;
  }

  /// Shows History in the active tab with [commit] selected and revealed.
  /// With [base] History compares [base] and [commit]. Without [reload] an
  /// already shown History keeps its rows.
  Future<void> showCommit(
    String commit, {
    String? base,
    bool focus = true,
    bool reload = true,
  }) async {
    final active = _repositories.activeTab;
    final session = active?.session;
    if (active == null || session == null) return;
    final needsHistory =
        reload || active.navigation.pane != WorkspacePane.history;
    _repositories.updateNavigation(
      active.id,
      active.navigation.copyWith(
        pane: WorkspacePane.history,
        route: WorkspaceRoute.repository,
        selectedIdentity: commit,
      ),
    );
    if (needsHistory) await _repositories.history.load(session.identity);
    if (base == null) {
      await _repositories.history.select(commit, reveal: true, focus: focus);
    } else {
      await _repositories.history.select(base, reveal: true);
      await _repositories.history.select(commit, toggle: true);
    }
  }

  /// Selects the commit an inspector window asks for in the tab of its
  /// repository; false when that repository is not open here.
  Future<bool> revealFromInspectorWindow(InspectorRevealRequest request) async {
    final tab = _repositories.workspace.tabs
        .where((tab) => tab.canonicalIdentity == request.repository)
        .firstOrNull;
    if (tab == null) return false;
    if (_repositories.activeTabId != tab.id) {
      _repositories.activateTab(tab.id);
    }
    if (tab.session == null) return false;
    await showCommit(request.commit, base: request.base);
    return true;
  }

  /// Shows [location] in the History inspector of the active tab, with its
  /// commit selected in the graph.
  Future<void> showInHistoryInspector(
    InspectorLocation location, {
    bool Function()? stillWanted,
  }) async {
    if (_repositories.activeTab?.session == null) return;
    await showCommit(location.target.commit, focus: false);
    if (!(stillWanted?.call() ?? true)) return;
    await _repositories.inspector.navigate(location);
  }

  /// Selects exactly the two commits History has selected again, which
  /// compares them.
  Future<bool> compareSelected() async {
    final selected =
        _repositories.history.current.page?.selectedObjectIds ??
        const <String>[];
    if (selected.length != 2) return false;
    await _repositories.history.select(null);
    await _repositories.history.select(selected.first, toggle: true);
    await _repositories.history.select(selected.last, toggle: true);
    return true;
  }
}
