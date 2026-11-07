import '../../models/history.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../settings_service.dart';

/// The workspace as it was saved: its open worktrees, the active one and the
/// tab groups.
typedef SavedWorkspace = ({
  List<NativePathIdentity> openWorktrees,
  NativePathIdentity? activeWorktree,
  List<TabGroupSettings> tabGroups,
});

/// Where the workspace keeps its tabs, groups, navigation and recent
/// repositories between runs.
abstract interface class WorkspacePersistence {
  /// The saved workspace; null where nothing is kept.
  SavedWorkspace? get saved;

  /// Saves [tabs], [groups] and the active worktree, when they changed.
  void persist({
    required List<RepositoryTabState> tabs,
    required List<RepositoryTabGroup> groups,
    required NativePathIdentity? activeIdentity,
  });

  /// Puts a loaded repository first among the recent ones.
  void recordRecent(RepositorySnapshot snapshot);

  /// The navigation a tab of [identity] had when it was saved.
  WorkspaceNavigation navigationFor(NativePathIdentity? identity);
}

/// Keeps nothing: a workspace that starts empty every time, as in narrow
/// tests and windows without settings.
final class TransientWorkspacePersistence implements WorkspacePersistence {
  const TransientWorkspacePersistence();

  @override
  SavedWorkspace? get saved => null;

  @override
  void persist({
    required List<RepositoryTabState> tabs,
    required List<RepositoryTabGroup> groups,
    required NativePathIdentity? activeIdentity,
  }) {}

  @override
  void recordRecent(RepositorySnapshot snapshot) {}

  @override
  WorkspaceNavigation navigationFor(NativePathIdentity? identity) =>
      const WorkspaceNavigation();
}

/// Keeps the workspace in the settings document.
final class SettingsWorkspacePersistence implements WorkspacePersistence {
  SettingsWorkspacePersistence(this._settings);

  final SettingsService _settings;

  @override
  SavedWorkspace? get saved {
    final current = _settings.current;
    return (
      openWorktrees: current.openWorktrees,
      activeWorktree: current.activeWorktree,
      tabGroups: current.tabGroups,
    );
  }

  @override
  void persist({
    required List<RepositoryTabState> tabs,
    required List<RepositoryTabGroup> groups,
    required NativePathIdentity? activeIdentity,
  }) {
    final current = _settings.current;
    final identities = <NativePathIdentity>[];
    for (final tab in tabs) {
      final identity = tab.canonicalIdentity;
      if (identity != null && !identities.contains(identity)) {
        identities.add(identity);
      }
    }
    final worktrees = List<WorktreeSettings>.of(current.worktrees);
    for (final tab in tabs) {
      final identity = tab.canonicalIdentity;
      if (identity == null) continue;
      final index = worktrees.indexWhere(
        (worktree) => worktree.identity == identity,
      );
      final existing = index < 0
          ? WorktreeSettings(identity: identity)
          : worktrees[index];
      final navigation = tab.navigation;
      final updated = existing.copyWith(
        anchor: navigation.selectedIdentity,
        clearAnchor: navigation.selectedIdentity == null,
        pane: navigation.pane.name,
        route: navigation.route.name,
        changesScrollOffset: navigation.changesScrollOffset.round(),
        historyScrollOffset: navigation.historyScrollOffset.round(),
        branchFilter: navigation.branchFilter.references,
      );
      if (index < 0) {
        worktrees.add(updated);
      } else {
        worktrees[index] = updated;
      }
    }
    final tabGroups = <TabGroupSettings>[];
    for (final group in groups) {
      final members = [
        for (final tab in tabs)
          if (tab.groupId == group.id) ?tab.canonicalIdentity,
      ];
      if (members.isEmpty) continue;
      tabGroups.add(
        TabGroupSettings(
          name: group.name,
          color: group.color.key,
          icon: group.icon,
          collapsed: group.collapsed,
          members: members,
        ),
      );
    }
    final unchangedGroups =
        tabGroups.length == current.tabGroups.length &&
        List.generate(
          tabGroups.length,
          (index) => tabGroups[index] == current.tabGroups[index],
        ).every((same) => same);
    final unchangedWorktrees =
        worktrees.length == current.worktrees.length &&
        List.generate(
          worktrees.length,
          (index) =>
              _sameWorktreeSettings(worktrees[index], current.worktrees[index]),
        ).every((same) => same);
    final unchangedOpen =
        identities.length == current.openWorktrees.length &&
        List.generate(
          identities.length,
          (index) => identities[index] == current.openWorktrees[index],
        ).every((same) => same);
    if (unchangedWorktrees &&
        unchangedOpen &&
        unchangedGroups &&
        activeIdentity == current.activeWorktree) {
      return;
    }
    _settings.updateView(
      current.copyWith(
        worktrees: worktrees,
        openWorktrees: identities,
        tabGroups: tabGroups,
        activeWorktree: activeIdentity,
        clearActiveWorktree: activeIdentity == null,
      ),
    );
  }

  @override
  void recordRecent(RepositorySnapshot snapshot) {
    if (snapshot.phase != RepositoryPhase.ready) return;
    final identity = snapshot.identity?.worktreeRoot;
    if (identity == null) return;
    final current = _settings.current;
    if (current.recentRepositories.isNotEmpty &&
        current.recentRepositories.first == identity) {
      return;
    }
    final recents = [
      identity,
      ...current.recentRepositories.where((recent) => recent != identity),
    ];
    _settings.updateView(
      current.copyWith(
        recentRepositories: recents.take(100).toList(growable: false),
      ),
    );
  }

  @override
  WorkspaceNavigation navigationFor(NativePathIdentity? identity) {
    if (identity == null) return const WorkspaceNavigation();
    final saved = _settings.current.worktrees.where(
      (worktree) => worktree.identity == identity,
    );
    if (saved.isEmpty) return const WorkspaceNavigation();
    final worktree = saved.first;
    return WorkspaceNavigation(
      pane: WorkspacePane.values.firstWhere(
        (pane) => pane.name == worktree.pane,
        orElse: () => WorkspacePane.changes,
      ),
      route: WorkspaceRoute.values.firstWhere(
        (route) => route.name == worktree.route,
        orElse: () => WorkspaceRoute.repository,
      ),
      selectedIdentity: worktree.anchor,
      changesScrollOffset: worktree.changesScrollOffset.toDouble(),
      historyScrollOffset: worktree.historyScrollOffset.toDouble(),
      branchFilter: worktree.branchFilter.isEmpty
          ? HistoryBranchFilter.none
          : HistoryBranchFilter(worktree.branchFilter),
    );
  }
}

bool _sameWorktreeSettings(WorktreeSettings left, WorktreeSettings right) =>
    left.identity == right.identity &&
    left.filter == right.filter &&
    left.anchor == right.anchor &&
    left.pane == right.pane &&
    left.route == right.route &&
    left.changesScrollOffset == right.changesScrollOffset &&
    left.historyScrollOffset == right.historyScrollOffset &&
    _sameValues(left.branchFilter, right.branchFilter) &&
    left.draft.subject == right.draft.subject &&
    left.draft.description == right.draft.description;

bool _sameValues<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
