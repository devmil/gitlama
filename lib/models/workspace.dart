import 'history.dart';
import 'repository_appearance.dart';
import 'repository_state.dart';
import 'settings.dart';

enum WorkspacePane { changes, history }

enum WorkspaceRoute { repository, commit, file, blame, operation }

final class WorkspaceNavigation {
  const WorkspaceNavigation({
    this.pane = WorkspacePane.changes,
    this.route = WorkspaceRoute.repository,
    this.selectedIdentity,
    this.changesScrollOffset = 0,
    this.historyScrollOffset = 0,
    this.branchFilter = HistoryBranchFilter.none,
  });

  final WorkspacePane pane;
  final WorkspaceRoute route;
  final String? selectedIdentity;
  final double changesScrollOffset;
  final double historyScrollOffset;

  /// The branches this repository's history graph shows.
  final HistoryBranchFilter branchFilter;

  WorkspaceNavigation copyWith({
    WorkspacePane? pane,
    WorkspaceRoute? route,
    String? selectedIdentity,
    bool clearSelectedIdentity = false,
    double? changesScrollOffset,
    double? historyScrollOffset,
    HistoryBranchFilter? branchFilter,
  }) => WorkspaceNavigation(
    pane: pane ?? this.pane,
    route: route ?? this.route,
    selectedIdentity: clearSelectedIdentity
        ? null
        : selectedIdentity ?? this.selectedIdentity,
    changesScrollOffset: changesScrollOffset ?? this.changesScrollOffset,
    historyScrollOffset: historyScrollOffset ?? this.historyScrollOffset,
    branchFilter: branchFilter ?? this.branchFilter,
  );
}

enum RepositoryTabPhase { choosing, opening, open, failed }

final class RepositoryTabState {
  const RepositoryTabState({
    required this.id,
    required this.generation,
    required this.label,
    required this.phase,
    this.requestedIdentity,
    this.session,
    this.failure,
    this.watchOverflowRevision,
    this.navigation = const WorkspaceNavigation(),
    this.groupId,
  });

  final int id;
  final int generation;
  final String label;
  final RepositoryTabPhase phase;
  final NativePathIdentity? requestedIdentity;
  final RepositorySessionState? session;
  final RepositoryFailure? failure;
  final BigInt? watchOverflowRevision;
  final WorkspaceNavigation navigation;

  /// The [RepositoryTabGroup] the tab belongs to, if any.
  final int? groupId;

  NativePathIdentity? get canonicalIdentity =>
      session?.snapshot.identity?.worktreeRoot ?? requestedIdentity;

  /// The repository the tab shows a worktree of, as its common Git
  /// directory; tabs of one repository's worktrees share it.
  NativePathIdentity? get repository =>
      session?.snapshot.identity?.commonGitDir;

  /// Whether the tab shows the repository's main worktree rather than a
  /// linked one.
  bool get isMainWorktree {
    final identity = session?.snapshot.identity;
    return identity == null || identity.gitDir == identity.commonGitDir;
  }

  RepositoryTabState copyWith({
    String? label,
    RepositoryTabPhase? phase,
    RepositorySessionState? session,
    RepositoryFailure? failure,
    bool clearFailure = false,
    BigInt? watchOverflowRevision,
    bool clearWatchOverflow = false,
    WorkspaceNavigation? navigation,
    int? groupId,
    bool clearGroup = false,
  }) => RepositoryTabState(
    id: id,
    generation: generation,
    label: label ?? this.label,
    phase: phase ?? this.phase,
    requestedIdentity: requestedIdentity,
    session: session ?? this.session,
    failure: clearFailure ? null : failure ?? this.failure,
    watchOverflowRevision: clearWatchOverflow
        ? null
        : watchOverflowRevision ?? this.watchOverflowRevision,
    navigation: navigation ?? this.navigation,
    groupId: clearGroup ? null : groupId ?? this.groupId,
  );
}

/// Tabs kept side by side under a [name], a [color] and an optional [icon].
/// A [collapsed] group shows only its chip; its tabs stay open.
final class RepositoryTabGroup {
  const RepositoryTabGroup({
    required this.id,
    required this.color,
    this.name = '',
    this.icon,
    this.collapsed = false,
  });

  final int id;
  final String name;
  final AppearanceColor color;

  /// One of [repositoryAppearanceIcons], drawn in [color] on the chip.
  final String? icon;
  final bool collapsed;

  RepositoryTabGroup copyWith({
    String? name,
    AppearanceColor? color,
    String? icon,
    bool clearIcon = false,
    bool? collapsed,
  }) => RepositoryTabGroup(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    icon: clearIcon ? null : icon ?? this.icon,
    collapsed: collapsed ?? this.collapsed,
  );

  @override
  bool operator ==(Object other) =>
      other is RepositoryTabGroup &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.icon == icon &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(id, name, color, icon, collapsed);
}

final class WorkspaceState {
  const WorkspaceState({
    required this.tabs,
    required this.activeTabId,
    this.groups = const [],
  });

  final List<RepositoryTabState> tabs;
  final int? activeTabId;

  /// Every group has at least one tab, and its tabs stand side by side.
  final List<RepositoryTabGroup> groups;

  RepositoryTabGroup? group(int? id) {
    if (id == null) return null;
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// The tab strip's entries in order. The tabs of one repository's
  /// worktrees stand side by side and form one entry; any other tab is an
  /// entry of its own.
  List<List<RepositoryTabState>> get tabEntries {
    final entries = <List<RepositoryTabState>>[];
    for (final tab in tabs) {
      final repository = tab.repository;
      if (repository != null &&
          entries.isNotEmpty &&
          entries.last.last.repository == repository) {
        entries.last.add(tab);
      } else {
        entries.add([tab]);
      }
    }
    return entries;
  }

  /// The entry of [tabEntries] that holds [tabId], or an empty list.
  List<RepositoryTabState> entryOf(int? tabId) {
    if (tabId == null) return const [];
    for (final entry in tabEntries) {
      if (entry.any((tab) => tab.id == tabId)) return entry;
    }
    return const [];
  }

  /// The open worktrees of the active tab's repository, the active one
  /// included, when there is more than one; otherwise empty. They make the
  /// worktree row under the tab strip.
  List<RepositoryTabState> get activeWorktrees {
    final entry = entryOf(activeTabId);
    return entry.length > 1 ? entry : const [];
  }

  RepositoryTabState? get activeTab {
    final active = activeTabId;
    if (active == null) return null;
    for (final tab in tabs) {
      if (tab.id == active) return tab;
    }
    return null;
  }
}
