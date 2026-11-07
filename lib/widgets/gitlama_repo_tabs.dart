import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';
import '../models/repository_appearance.dart';
import '../models/settings.dart';
import '../models/workspace.dart';
import 'gitlama_window_caption.dart';
import 'repository_icon.dart';

/// The host a remote tab's repository lives on, as its tab shows it: with a
/// [color] or [icon] the tab shows them instead of the host's name.
typedef RemoteTabHost = ({
  String name,
  bool disconnected,
  Color? color,
  String? icon,
});

/// The repository tabs in the title bar: Meridian's tab strip over the
/// workspace's tabs and groups, the window's drag area beside it and the
/// button that opens another repository.
class GitLamaRepoTabs extends StatefulWidget {
  const GitLamaRepoTabs({
    required this.workspace,
    required this.onActivate,
    required this.onClose,
    required this.onMoveTab,
    required this.onOpenRepository,
    this.onMoveGroup,
    this.leadingBuilder,
    this.labelBuilder,
    this.hostBuilder,
    this.onContextMenu,
    this.onRenameTab,
    this.onToggleGroup,
    this.onGroupContextMenu,
    this.onRenameGroup,
    this.onMoveWorktree,
    this.onCloseWorktrees,
    this.repositoryLabelBuilder,
    this.worktreeLabelBuilder,
    this.onOpenWorktree,
    super.key,
  });

  final WorkspaceState workspace;
  final ValueChanged<int> onActivate;

  /// Also runs for a middle click on the tab.
  final ValueChanged<int> onClose;

  /// A tab dropped so it stands at [index] among the other tabs, in
  /// [groupId] or in no group.
  final void Function(int tabId, int index, int? groupId) onMoveTab;
  final VoidCallback onOpenRepository;

  /// A group's chip dropped so the group starts at [index] among the other
  /// tabs; `null` keeps chips in place.
  final void Function(int groupId, int index)? onMoveGroup;

  /// A mark before the label (the repository's icon), or `null` for none.
  final Widget? Function(BuildContext context, RepositoryTabState tab)?
  leadingBuilder;

  /// The name the tab shows; the repository's folder name by default.
  final String Function(RepositoryTabState tab)? labelBuilder;

  /// The host of a tab whose repository lives on another computer, or null.
  /// Such a tab shows a host icon and the host's name beside its label.
  final RemoteTabHost? Function(RepositoryTabState tab)? hostBuilder;

  /// A right click or the menu key on a tab, with the global menu position.
  final void Function(int tabId, Offset position)? onContextMenu;

  /// A tab renamed in place (a second click on the active tab, or
  /// [GitLamaRepoTabsState.renameTab]); an empty name restores the
  /// folder's name.
  final void Function(int tabId, String name)? onRenameTab;

  /// A click on a group's chip: collapses or expands the group.
  final ValueChanged<int>? onToggleGroup;

  /// A right click or the menu key on a group's chip.
  final void Function(int groupId, Offset position)? onGroupContextMenu;

  /// A group renamed in place ([GitLamaRepoTabsState.renameGroup]).
  final void Function(int groupId, String name)? onRenameGroup;

  /// A worktree tab dropped at [index] among the other open worktrees of its
  /// repository, in the worktree row.
  final void Function(int tabId, int index)? onMoveWorktree;

  /// The close button of a repository with several open worktrees: closes
  /// all of them. Without it, each one closes through [onClose].
  final ValueChanged<List<int>>? onCloseWorktrees;

  /// The name the strip shows for a repository with several open
  /// worktrees, which stand in its row; the first one's label by default.
  final String Function(List<RepositoryTabState> worktrees)?
  repositoryLabelBuilder;

  /// The name a tab shows in the worktree row: what it has checked out, by
  /// default the tab's label.
  final String Function(RepositoryTabState tab)? worktreeLabelBuilder;

  /// The worktree row's open button, with the global position for its menu.
  final ValueChanged<Offset>? onOpenWorktree;

  @override
  State<GitLamaRepoTabs> createState() => GitLamaRepoTabsState();
}

class GitLamaRepoTabsState extends State<GitLamaRepoTabs> {
  final _strip = GlobalKey<MeridianTabStripState<int, int>>();
  final _worktreeStrip = GlobalKey<MeridianTabStripState<int, int>>();
  final _openWorktreeKey = GlobalKey();

  /// The strip id of each repository with several open worktrees: the id of
  /// a tab it held, kept while the entry stands so the entry neither grows
  /// in again nor loses its place when its first worktree closes.
  final Map<NativePathIdentity, int> _entryIds = {};

  /// The worktree each such repository showed last, which its entry
  /// activates.
  final Map<NativePathIdentity, int> _lastActive = {};

  /// The strip's entries by their strip id, from the last build.
  Map<int, List<RepositoryTabState>> _entries = const {};

  /// Edits [tabId]'s name in place, in the worktree row when it stands
  /// there.
  void renameTab(int tabId) =>
      (widget.workspace.activeWorktrees.any((tab) => tab.id == tabId)
              ? _worktreeStrip
              : _strip)
          .currentState
          ?.renameTab(tabId);

  /// Edits [groupId]'s name in place.
  void renameGroup(int groupId) => _strip.currentState?.renameGroup(groupId);

  String _label(BuildContext context, RepositoryTabState tab) =>
      tab.phase == RepositoryTabPhase.choosing
      ? context.l10n.openRepository
      : widget.labelBuilder?.call(tab) ?? tab.label;

  /// Gives each entry of the strip its id: a tab's own, or a stable one for
  /// a repository with several open worktrees.
  Map<int, List<RepositoryTabState>> _resolveEntries() {
    final workspace = widget.workspace;
    final entries = <int, List<RepositoryTabState>>{};
    final repositories = <NativePathIdentity>{};
    for (final entry in workspace.tabEntries) {
      final repository = entry.first.repository;
      if (entry.length < 2 || repository == null) {
        entries[entry.single.id] = entry;
        continue;
      }
      repositories.add(repository);
      final members = {for (final tab in entry) tab.id};
      var id = _entryIds[repository];
      // An id another tab of the strip shows would collide.
      if (id == null ||
          (!members.contains(id) &&
              workspace.tabs.any((tab) => tab.id == id))) {
        id = entry.first.id;
      }
      _entryIds[repository] = id;
      entries[id] = entry;
      if (members.contains(workspace.activeTabId)) {
        _lastActive[repository] = workspace.activeTabId!;
      }
    }
    _entryIds.removeWhere((key, _) => !repositories.contains(key));
    _lastActive.removeWhere((key, _) => !repositories.contains(key));
    return entries;
  }

  /// The worktree an entry stands for: the active one, the one shown last,
  /// or the main worktree.
  RepositoryTabState _representative(List<RepositoryTabState> entry) {
    final active = widget.workspace.activeTabId;
    final last = _lastActive[entry.first.repository];
    return entry.where((tab) => tab.id == active).firstOrNull ??
        entry.where((tab) => tab.id == last).firstOrNull ??
        entry.where((tab) => tab.isMainWorktree).firstOrNull ??
        entry.first;
  }

  int? _entryIdOf(int? tabId) {
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (value.any((tab) => tab.id == tabId)) return key;
    }
    return null;
  }

  /// The tab [index] among the strip's other entries stands for, as an
  /// index among the tabs outside [moved].
  int _tabIndexFor(Iterable<int> others, int index, Set<int> moved) {
    final remaining = [
      for (final tab in widget.workspace.tabs)
        if (!moved.contains(tab.id)) tab.id,
    ];
    final ids = others.toList();
    if (index >= ids.length) return remaining.length;
    return remaining.indexOf(_entries[ids[index]]!.first.id);
  }

  void _moveEntry(int id, int index, int? group) {
    final entry = _entries[id];
    if (entry == null) return;
    // The first tab leads; the service keeps the others beside it.
    final leader = entry.first.id;
    final others = _entries.keys.where((other) => other != id);
    widget.onMoveTab(leader, _tabIndexFor(others, index, {leader}), group);
  }

  void _moveGroup(int groupId, int index) {
    final members = {
      for (final tab in widget.workspace.tabs)
        if (tab.groupId == groupId) tab.id,
    };
    final others = _entries.entries
        .where((entry) => entry.value.first.groupId != groupId)
        .map((entry) => entry.key);
    widget.onMoveGroup?.call(groupId, _tabIndexFor(others, index, members));
  }

  MeridianStripTab<int, int> _tab(
    BuildContext context,
    RepositoryTabState tab, {
    int? id,
    String? label,
    Widget? leading,
    String? tooltip,
    bool? dirty,
    bool? renamable,
  }) {
    final l10n = context.l10n;
    final colors = context.meridian.colors;
    final name = label ?? _label(context, tab);
    final host = tab.phase == RepositoryTabPhase.choosing
        ? null
        : widget.hostBuilder?.call(tab);
    final marked = host != null && (host.color != null || host.icon != null);
    // A marked host is told by its icon; its name would crowd the label.
    final shown = host == null || marked || label != null
        ? name
        : l10n.remoteTabLabel(name, host.name);
    final status = tab.session?.snapshot.status;
    final mark = switch (tab.phase) {
      RepositoryTabPhase.opening => const MeridianSpinner(
        size: MeridianLayout.tabCloseIconSize,
      ),
      RepositoryTabPhase.failed => MeridianIcon(
        'circle-alert',
        size: MeridianIconSize.small,
        color: colors.danger,
      ),
      _ when host != null => MeridianIcon(
        host.disconnected ? 'wifi-off' : host.icon ?? 'server',
        key: ValueKey('remote-tab-host-${tab.id}'),
        size: MeridianIconSize.small,
        color: host.color,
      ),
      _ => leading ?? widget.leadingBuilder?.call(context, tab),
    };
    final hostNote = host == null
        ? null
        : host.disconnected
        ? l10n.remoteHostBadgeDisconnected(host.name)
        : l10n.remoteHostBadge(host.name);
    return MeridianStripTab(
      id: id ?? tab.id,
      label: shown,
      group: tab.groupId,
      leading: mark,
      tooltip: [
        tooltip ?? (hostNote == null ? shown : '$name · $hostNote'),
        if (status != null)
          l10n.syncAheadBehind(status.ahead.toInt(), status.behind.toInt()),
      ].join(' · '),
      semanticLabel: hostNote == null ? null : '$name, $hostNote',
      dirty: dirty ?? (status != null && status.totalEntries > BigInt.zero),
      // The label carries the host; renaming edits only local names.
      renamable:
          renamable ?? (host == null && tab.phase == RepositoryTabPhase.open),
      renamePlaceholder: tab.label,
    );
  }

  /// A repository with several open worktrees: one entry, named for the
  /// repository and marked with how many worktrees its row holds.
  MeridianStripTab<int, int> _repositoryTab(
    BuildContext context,
    int id,
    List<RepositoryTabState> worktrees,
  ) {
    final representative = _representative(worktrees);
    final name =
        widget.repositoryLabelBuilder?.call(worktrees) ??
        _label(context, worktrees.first);
    final main = worktrees.where((tab) => tab.isMainWorktree).firstOrNull;
    final icon = main == null
        ? null
        : widget.leadingBuilder?.call(context, main);
    final tooltip = context.l10n.worktreeTabsTooltip(name, worktrees.length);
    return _tab(
      context,
      representative,
      id: id,
      label: name,
      tooltip: tooltip,
      leading: Row(
        key: ValueKey('repository-worktrees-$id'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon,
            const SizedBox(width: MeridianSpace.space2),
          ],
          MeridianIcon(
            'git-fork',
            size: MeridianIconSize.small,
            color: context.meridian.colors.inkMuted,
          ),
          MeridianCount(
            label: '${worktrees.length}',
            tone: MeridianCountTone.quiet,
            semanticLabel: tooltip,
          ),
        ],
      ),
      dirty: worktrees.any(
        (tab) =>
            (tab.session?.snapshot.status?.totalEntries ?? BigInt.zero) >
            BigInt.zero,
      ),
      renamable: false,
    );
  }

  MeridianStripGroup<int> _group(
    BuildContext context,
    RepositoryTabGroup group,
  ) => MeridianStripGroup(
    id: group.id,
    color: repositoryAppearanceColor(context, group.color),
    name: group.name,
    icon: repositoryAppearanceIcons.contains(group.icon) ? group.icon : null,
    collapsed: group.collapsed,
    label: context.l10n.tabGroupUnnamed(
      repositoryColorLabel(context, group.color),
    ),
  );

  MeridianTabStripLabels _labels(BuildContext context) {
    final l10n = context.l10n;
    return MeridianTabStripLabels(
      close: l10n.workspaceCloseTab,
      collapseGroup: l10n.tabGroupCollapse,
      expandGroup: l10n.tabGroupExpand,
      group: l10n.tabGroupSemantics,
      renameTab: l10n.repositoryTabRenameLabel,
      renameGroup: l10n.tabGroupRenameLabel,
      groupNamePlaceholder: l10n.tabGroupNamePlaceholder,
      moveLeft: l10n.repositoryTabMoveLeft,
      moveRight: l10n.repositoryTabMoveRight,
      dirty: l10n.repositoryTabUnsaved,
    );
  }

  /// The open worktrees of the active tab's repository, under the strip.
  Widget _worktreeRow(
    BuildContext context,
    List<RepositoryTabState> worktrees,
  ) {
    final l10n = context.l10n;
    final colors = context.meridian.colors;
    final repository =
        widget.repositoryLabelBuilder?.call(worktrees) ??
        _label(context, worktrees.first);
    final group = widget.workspace.group(worktrees.first.groupId);
    final rowLabel = l10n.worktreeRowLabel(repository);
    final onOpenWorktree = widget.onOpenWorktree;
    return Container(
      key: const ValueKey('repository-worktree-row'),
      height: MeridianLayout.tabStripHeight,
      color: colors.ground,
      padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space3),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            // The row hangs from its repository's entry: the fork mark, in
            // the colour of the entry's group.
            Tooltip(
              message: rowLabel,
              child: Semantics(
                label: rowLabel,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: MeridianSpace.space3,
                  ),
                  child: MeridianIcon(
                    'git-fork',
                    size: MeridianIconSize.small,
                    color: group == null
                        ? colors.inkMuted
                        : repositoryAppearanceColor(context, group.color),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    (constraints.maxWidth -
                            MeridianSize.controlSm -
                            context.meridian.density.iconSmallSize -
                            MeridianSpace.space3 * 2)
                        .clamp(0, double.infinity),
              ),
              child: MeridianTabStrip<int, int>(
                key: _worktreeStrip,
                tabs: [
                  for (final tab in worktrees)
                    _tab(
                      context,
                      tab,
                      label: widget.worktreeLabelBuilder?.call(tab),
                      leading: MeridianIcon(
                        tab.isMainWorktree ? 'house' : 'git-branch',
                        key: ValueKey('worktree-tab-mark-${tab.id}'),
                        size: MeridianIconSize.small,
                        color: colors.inkMuted,
                      ),
                      tooltip: [
                        widget.worktreeLabelBuilder?.call(tab) ??
                            _label(context, tab),
                        if (tab.isMainWorktree) l10n.worktreeMainTab,
                        ?tab.canonicalIdentity?.displayText,
                      ].join(' · '),
                    ).withoutGroup(),
                ],
                groups: const [],
                activeTab: widget.workspace.activeTabId,
                onActivate: widget.onActivate,
                onClose: widget.onClose,
                onMoveTab: widget.onMoveWorktree == null
                    ? null
                    : (id, index, _) => widget.onMoveWorktree!(id, index),
                onContextMenu: widget.onContextMenu,
                onRenameTab: widget.onRenameTab,
                nameMaxLength: maxTabNameBytes,
                labels: _labels(context),
              ),
            ),
            Expanded(
              child: GitLamaWindowDragArea(
                child: SizedBox(height: MeridianLayout.tabStripHeight),
              ),
            ),
            if (onOpenWorktree != null)
              MeridianIconButton(
                key: _openWorktreeKey,
                label: l10n.worktreeOpen,
                icon: 'folder-git-2',
                size: MeridianControlSize.small,
                onGround: true,
                onPressed: () {
                  final box =
                      _openWorktreeKey.currentContext?.findRenderObject()
                          as RenderBox?;
                  if (box == null) return;
                  onOpenWorktree(box.localToGlobal(Offset(0, box.size.height)));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workspace = widget.workspace;
    _entries = _resolveEntries();
    final worktrees = workspace.activeWorktrees;
    final strip = Container(
      height: MeridianLayout.tabStripHeight,
      color: context.meridian.colors.ground,
      padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space3),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - MeridianSize.controlSm).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: MeridianTabStrip<int, int>(
                key: _strip,
                tabs: [
                  for (final MapEntry(key: id, value: entry)
                      in _entries.entries)
                    entry.length > 1
                        ? _repositoryTab(context, id, entry)
                        : _tab(context, entry.single),
                ],
                groups: [
                  for (final group in workspace.groups) _group(context, group),
                ],
                activeTab: _entryIdOf(workspace.activeTabId),
                onActivate: (id) {
                  final entry = _entries[id];
                  if (entry == null) return;
                  widget.onActivate(
                    entry.length > 1 ? _representative(entry).id : id,
                  );
                },
                onClose: (id) {
                  final entry = _entries[id];
                  if (entry == null) return;
                  if (entry.length < 2) {
                    widget.onClose(id);
                  } else if (widget.onCloseWorktrees case final close?) {
                    close([for (final tab in entry) tab.id]);
                  } else {
                    for (final tab in entry) {
                      widget.onClose(tab.id);
                    }
                  }
                },
                onMoveTab: _moveEntry,
                onMoveGroup: widget.onMoveGroup == null ? null : _moveGroup,
                onContextMenu: widget.onContextMenu == null
                    ? null
                    : (id, position) {
                        final entry = _entries[id];
                        if (entry == null) return;
                        widget.onContextMenu!(
                          entry.length > 1 ? _representative(entry).id : id,
                          position,
                        );
                      },
                onRenameTab: widget.onRenameTab,
                onToggleGroup: widget.onToggleGroup,
                onGroupContextMenu: widget.onGroupContextMenu,
                onRenameGroup: widget.onRenameGroup,
                nameMaxLength: maxTabNameBytes,
                labels: _labels(context),
              ),
            ),
            Expanded(
              child: GitLamaWindowDragArea(
                child: SizedBox(
                  key: const ValueKey('repository-titlebar-tab-gap'),
                  height: MeridianLayout.tabStripHeight,
                ),
              ),
            ),
            MeridianIconButton(
              key: const ValueKey('repository-open-tab'),
              label: l10n.workspaceOpenAnother,
              icon: 'plus',
              size: MeridianControlSize.small,
              onGround: true,
              onPressed: widget.onOpenRepository,
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        strip,
        // The row unfolds under the strip while the active repository has
        // several worktrees open, and folds away with the last but one.
        ClipRect(
          child: AnimatedSize(
            duration: MeridianMotion.of(context, MeridianDurations.layout),
            curve: MeridianDurations.layoutCurve,
            alignment: AlignmentDirectional.topStart,
            child: worktrees.isEmpty
                ? const SizedBox(width: double.infinity)
                : _worktreeRow(context, worktrees),
          ),
        ),
      ],
    );
  }
}

extension on MeridianStripTab<int, int> {
  /// The tab outside any group: the worktree row has none.
  MeridianStripTab<int, int> withoutGroup() => MeridianStripTab(
    id: id,
    label: label,
    leading: leading,
    tooltip: tooltip,
    dirty: dirty,
    renamable: renamable,
    renamePlaceholder: renamePlaceholder,
    semanticLabel: semanticLabel,
  );
}
