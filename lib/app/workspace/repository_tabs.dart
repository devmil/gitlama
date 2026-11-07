import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/reference_name.dart';
import '../../models/repository_extensions.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/repository_appearance_service.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/gitlama_repo_tabs.dart';
import '../../widgets/repository_icon.dart';
import '../../widgets/status_notification.dart';
import 'repository_icon_dialog.dart';
import 'tab_group_dialog.dart';
import 'labels.dart';
import 'status_bar.dart';

/// What a repository tab's context menu does.
sealed class _TabAction {
  const _TabAction();
}

final class _TabOpenFolder extends _TabAction {
  const _TabOpenFolder();
}

final class _TabCopyPath extends _TabAction {
  const _TabCopyPath();
}

final class _TabRename extends _TabAction {
  const _TabRename();
}

final class _TabResetName extends _TabAction {
  const _TabResetName();
}

final class _TabChangeIcon extends _TabAction {
  const _TabChangeIcon();
}

final class _TabRemoveIcon extends _TabAction {
  const _TabRemoveIcon();
}

final class _TabNewGroup extends _TabAction {
  const _TabNewGroup();
}

final class _TabJoinGroup extends _TabAction {
  const _TabJoinGroup(this.groupId);
  final int groupId;
}

final class _TabLeaveGroup extends _TabAction {
  const _TabLeaveGroup();
}

final class _TabClose extends _TabAction {
  const _TabClose();
}

final class _TabCloseWorktrees extends _TabAction {
  const _TabCloseWorktrees();
}

/// What the worktree row's open menu does.
sealed class _WorktreeAction {
  const _WorktreeAction();
}

final class _WorktreeOpen extends _WorktreeAction {
  const _WorktreeOpen(this.worktree);
  final WorktreeEntry worktree;
}

final class _WorktreeAdd extends _WorktreeAction {
  const _WorktreeAdd();
}

/// What a tab group chip's context menu does.
sealed class _GroupAction {
  const _GroupAction();
}

final class _GroupRename extends _GroupAction {
  const _GroupRename();
}

final class _GroupEdit extends _GroupAction {
  const _GroupEdit();
}

final class _GroupToggle extends _GroupAction {
  const _GroupToggle();
}

final class _GroupUngroup extends _GroupAction {
  const _GroupUngroup();
}

final class _GroupClose extends _GroupAction {
  const _GroupClose();
}

/// A tab group's name as menus show it: the colour stands in for a
/// missing name.
/// The compass title of [tab]: the [name] the user gave it, or its folder's,
/// after the name of the group it belongs to.
String repositoryTitle(
  BuildContext context,
  WorkspaceState workspace,
  RepositoryTabState tab, {
  String? name,
}) {
  final title = name ?? tab.label;
  return switch (workspace.group(tab.groupId)) {
    final group? when group.name.isNotEmpty =>
      context.l10n.repositoryTitleInGroup(group.name, title),
    _ => title,
  };
}

String tabGroupLabel(BuildContext context, RepositoryTabGroup group) =>
    group.name.isNotEmpty
    ? group.name
    : context.l10n.tabGroupUnnamed(repositoryColorLabel(context, group.color));

class RepositoryTabs extends StatefulWidget {
  const RepositoryTabs({
    super.key,
    required this.workspace,
    required this.repositories,
    required this.onOpenRepository,
    this.appearances,
    this.fileBrowserName,
    this.onOpenFolder,
    this.remoteHost,
    this.onAddWorktree,
  });

  final WorkspaceState workspace;
  final RepositorySessionService repositories;
  final VoidCallback onOpenRepository;

  /// The host a tab's repository lives on, or null for a local one.
  final RemoteTabHost? Function(RepositoryTabState tab)? remoteHost;
  final RepositoryAppearanceService? appearances;

  /// The file manager's name for "Open in …"; the platform's by default.
  final String? fileBrowserName;
  final ValueChanged<NativePathIdentity>? onOpenFolder;

  /// Starts adding a worktree to the active repository.
  final VoidCallback? onAddWorktree;

  @override
  State<RepositoryTabs> createState() => _RepositoryTabsState();
}

class _RepositoryTabsState extends State<RepositoryTabs> {
  final _strip = GlobalKey<GitLamaRepoTabsState>();

  WorkspaceState get workspace => widget.workspace;
  RepositorySessionService get repositories => widget.repositories;

  String _label(RepositoryTabState tab) =>
      widget.appearances?.nameFor(tab.canonicalIdentity) ??
      (tab.label.isEmpty
          ? context.l10n.repositoryIconNameRepository
          : tab.label);

  /// The name of a repository with several open worktrees: its main
  /// worktree's, or the folder that holds its Git directory.
  String _repositoryLabel(List<RepositoryTabState> worktrees) {
    if (worktrees.where((tab) => tab.isMainWorktree).firstOrNull
        case final main?) {
      return _label(main);
    }
    final common = worktrees.first.repository;
    if (common == null) return _label(worktrees.first);
    final parts = common.displayText
        .split(RegExp(r'[/\\]'))
        .where((part) => part.isNotEmpty)
        .toList();
    // `repo/.git` names the repository by its folder; a bare `repo.git`
    // by itself.
    final folder = parts.length > 1 && parts.last == '.git'
        ? parts[parts.length - 2]
        : parts.lastOrNull ?? '';
    final name = folder.endsWith('.git')
        ? folder.substring(0, folder.length - '.git'.length)
        : folder;
    return name.isEmpty ? _label(worktrees.first) : name;
  }

  /// A worktree row tab's name: the one the user gave it, or what it has
  /// checked out.
  String _worktreeLabel(RepositoryTabState tab) =>
      widget.appearances?.nameFor(tab.canonicalIdentity) ??
      checkedOut(context, tab.session?.snapshot)?.label ??
      _label(tab);

  Future<void> _showWorktreeMenu(BuildContext context, Offset position) async {
    final l10n = context.l10n;
    final open = {
      for (final tab in workspace.activeWorktrees) ?tab.canonicalIdentity,
    };
    final List<WorktreeEntry> worktrees;
    try {
      worktrees = (await repositories.extensions.inventory()).worktrees;
    } on Object {
      if (context.mounted) {
        StatusNotificationScope.show(
          context,
          l10n.worktreeListFailed,
          error: true,
        );
      }
      return;
    }
    if (!context.mounted) return;
    final closed = [
      for (final worktree in worktrees)
        if (!open.contains(worktree.worktreeRoot) && !worktree.prunable)
          worktree,
    ];
    final action = await showNativeMenuItems<_WorktreeAction>(
      context: context,
      position: position,
      items: [
        if (closed.isEmpty)
          NativeMenuItem(
            value: const _WorktreeAdd(),
            title: l10n.worktreeAllOpen,
            enabled: false,
          ),
        for (final worktree in closed)
          NativeMenuItem(
            value: _WorktreeOpen(worktree),
            title: worktree.branch == null
                ? worktree.worktreeRoot.basename
                : ReferenceName(worktree.branch!).display,
            icon: worktree.gitDir == worktree.commonGitDir
                ? 'house'
                : 'git-branch',
          ),
        if (widget.onAddWorktree != null) ...[
          const NativeMenuItem.separator(),
          NativeMenuItem(
            value: const _WorktreeAdd(),
            title: l10n.commandAddWorktree,
            icon: 'plus',
          ),
        ],
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _WorktreeOpen(:final worktree):
        try {
          await repositories.extensions.openWorktree(worktree);
        } on RepositorySessionException {
          // The workspace keeps the failed tab visible with its error.
        }
      case _WorktreeAdd():
        widget.onAddWorktree?.call();
    }
  }

  Future<void> _rename(RepositoryTabState tab, String? name) async {
    final identity = tab.canonicalIdentity;
    final appearances = widget.appearances;
    if (identity == null || appearances == null) return;
    try {
      await appearances.rename(identity, name);
    } on Object {
      if (mounted) {
        StatusNotificationScope.show(
          context,
          context.l10n.repositoryIconSaveFailed,
          error: true,
        );
      }
    }
  }

  Future<void> _showMenu(
    BuildContext context,
    int tabId,
    Offset position,
  ) async {
    final tab = workspace.tabs.where((tab) => tab.id == tabId).firstOrNull;
    if (tab == null) return;
    final identity = tab.canonicalIdentity;
    final path = identity ?? tab.requestedIdentity;
    // A repository on another computer has no local folder. Its name and
    // icon are kept on this computer like a local one's.
    final remote = identity?.isRemote ?? false;
    final appearances = widget.appearances;
    final appearance = appearances?.appearanceFor(identity);
    final l10n = context.l10n;
    final otherGroups = [
      for (final group in workspace.groups)
        if (group.id != tab.groupId) group,
    ];
    final label = _label(tab);
    final worktrees = workspace.entryOf(tab.id);
    final action = await showNativeMenuItems<_TabAction>(
      context: context,
      position: position,
      items: [
        if (widget.onOpenFolder != null)
          NativeMenuItem(
            value: const _TabOpenFolder(),
            title: l10n.openInFileBrowser(
              widget.fileBrowserName ?? platformFileBrowserName(),
            ),
            icon: 'folder-open',
            enabled: identity != null && !remote,
          ),
        // A remote repository's path is its path on the host.
        NativeMenuItem(
          value: const _TabCopyPath(),
          title: l10n.repositoryCopyPath,
          icon: 'copy',
          enabled: path != null,
        ),
        const NativeMenuItem.separator(),
        if (appearances != null) ...[
          NativeMenuItem(
            value: const _TabRename(),
            title: l10n.repositoryTabRename,
            icon: 'pencil',
            enabled: identity != null && tab.phase == RepositoryTabPhase.open,
          ),
          if (appearance?.name != null)
            NativeMenuItem(
              value: const _TabResetName(),
              title: l10n.repositoryTabResetName,
              icon: 'rotate-ccw',
            ),
          NativeMenuItem(
            value: const _TabChangeIcon(),
            title: l10n.repositoryTabChangeIcon,
            icon: 'image',
            enabled: identity != null,
          ),
          NativeMenuItem(
            value: const _TabRemoveIcon(),
            title: l10n.repositoryTabRemoveIcon,
            icon: 'eraser',
            enabled: appearance?.hasMark ?? false,
          ),
          const NativeMenuItem.separator(),
        ],
        if (otherGroups.isEmpty)
          NativeMenuItem(
            value: const _TabNewGroup(),
            title: l10n.tabGroupAddToNew,
            icon: 'folder-plus',
          )
        else
          NativeMenuItem.submenu(
            title: l10n.tabGroupAddTo,
            icon: 'folder-plus',
            children: [
              NativeMenuItem(
                value: const _TabNewGroup(),
                title: l10n.tabGroupNew,
                icon: 'plus',
              ),
              const NativeMenuItem.separator(),
              for (final group in otherGroups)
                NativeMenuItem(
                  value: _TabJoinGroup(group.id),
                  title: tabGroupLabel(context, group),
                ),
            ],
          ),
        if (tab.groupId != null)
          NativeMenuItem(
            value: const _TabLeaveGroup(),
            title: l10n.tabGroupRemoveTab,
            icon: 'circle-minus',
          ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          value: const _TabClose(),
          title: l10n.workspaceCloseTab(
            worktrees.length > 1 ? _worktreeLabel(tab) : label,
          ),
          icon: 'close',
        ),
        if (worktrees.length > 1)
          NativeMenuItem(
            value: const _TabCloseWorktrees(),
            title: l10n.worktreeCloseAll(worktrees.length),
            icon: 'close',
          ),
      ],
    );
    // The menu has closed: follow-up dialogs may open now.
    if (action == null || !context.mounted) return;
    switch (action) {
      case _TabOpenFolder():
        if (identity != null) widget.onOpenFolder?.call(identity);
      case _TabCopyPath():
        if (path == null) return;
        await copyWithStatusNotification(
          context,
          path.displayText,
          l10n.repositoryPathCopied,
        );
      case _TabRename():
        if (worktrees.length > 1 && workspace.activeTabId != tab.id) {
          // A worktree is renamed in its row, which shows once it is active.
          repositories.activateTab(tab.id);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _strip.currentState?.renameTab(tab.id),
          );
        } else {
          _strip.currentState?.renameTab(tab.id);
        }
      case _TabResetName():
        await _rename(tab, null);
      case _TabChangeIcon():
        if (identity == null || appearances == null) return;
        await showRepositoryIconDialog(
          context,
          appearances: appearances,
          identity: identity,
          repositoryName: label,
        );
      case _TabRemoveIcon():
        if (identity == null || appearances == null) return;
        try {
          await appearances.save(
            (appearance ?? RepositoryAppearance(identity: identity))
                .withoutMark(),
          );
        } on Object {
          if (context.mounted) {
            StatusNotificationScope.show(
              context,
              l10n.repositoryIconSaveFailed,
              error: true,
            );
          }
        }
      case _TabNewGroup():
        final groupId = repositories.createTabGroup(tab.id);
        // A new group asks for its name at once.
        if (groupId != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _strip.currentState?.renameGroup(groupId),
          );
        }
      case _TabJoinGroup(:final groupId):
        repositories.addTabToGroup(tab.id, groupId);
      case _TabLeaveGroup():
        repositories.removeTabFromGroup(tab.id);
      case _TabClose():
        await repositories.closeTab(tab.id);
      case _TabCloseWorktrees():
        await repositories.closeTabs([for (final tab in worktrees) tab.id]);
    }
  }

  Future<void> _showGroupMenu(
    BuildContext context,
    int groupId,
    Offset position,
  ) async {
    final group = workspace.group(groupId);
    if (group == null) return;
    final l10n = context.l10n;
    final action = await showNativeMenuItems<_GroupAction>(
      context: context,
      position: position,
      items: [
        NativeMenuItem(
          value: const _GroupRename(),
          title: l10n.tabGroupRename,
          icon: 'pencil',
        ),
        NativeMenuItem(
          value: const _GroupEdit(),
          title: l10n.tabGroupEdit,
          icon: 'palette',
        ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          value: const _GroupToggle(),
          title: group.collapsed
              ? l10n.tabGroupExpandAction
              : l10n.tabGroupCollapseAction,
          icon: group.collapsed ? 'chevrons-up-down' : 'chevrons-down-up',
        ),
        NativeMenuItem(
          value: const _GroupUngroup(),
          title: l10n.tabGroupUngroup,
          icon: 'unlink',
        ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          value: const _GroupClose(),
          title: l10n.tabGroupClose,
          icon: 'close',
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _GroupRename():
        _strip.currentState?.renameGroup(groupId);
      case _GroupEdit():
        final edit = await showTabGroupDialog(
          context,
          group: group,
          tabLabels: [
            for (final tab in workspace.tabs)
              if (tab.groupId == groupId) _label(tab),
          ],
        );
        if (edit == null) return;
        repositories.editTabGroup(
          groupId,
          name: edit.name,
          color: edit.color,
          icon: edit.icon,
        );
      case _GroupToggle():
        repositories.setTabGroupCollapsed(groupId, !group.collapsed);
      case _GroupUngroup():
        repositories.ungroupTabs(groupId);
      case _GroupClose():
        await repositories.closeTabGroup(groupId);
    }
  }

  Widget? _leading(BuildContext context, RepositoryTabState tab) {
    final appearances = widget.appearances;
    final appearance = appearances?.appearanceFor(tab.canonicalIdentity);
    if (appearances == null || !RepositoryIcon.shows(appearance)) return null;
    final image = appearance!.image;
    return RepositoryIcon(
      appearance: appearance,
      image: image == null ? null : appearances.imageAt(image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearances = widget.appearances;
    Widget tabs(BuildContext context) => GitLamaRepoTabs(
      key: _strip,
      workspace: workspace,
      onActivate: repositories.activateTab,
      onClose: (id) => unawaited(repositories.closeTab(id)),
      onMoveTab: (id, index, groupId) =>
          repositories.moveTab(id, index, groupId: groupId),
      onMoveGroup: repositories.moveTabGroup,
      onOpenRepository: widget.onOpenRepository,
      leadingBuilder: appearances == null ? null : _leading,
      labelBuilder: _label,
      hostBuilder: widget.remoteHost,
      onContextMenu: (id, position) =>
          unawaited(_showMenu(context, id, position)),
      onRenameTab: appearances == null
          ? null
          : (id, name) {
              final tab = workspace.tabs
                  .where((tab) => tab.id == id)
                  .firstOrNull;
              if (tab != null) unawaited(_rename(tab, name));
            },
      onToggleGroup: (id) {
        final group = workspace.group(id);
        if (group != null) {
          repositories.setTabGroupCollapsed(id, !group.collapsed);
        }
      },
      onGroupContextMenu: (id, position) =>
          unawaited(_showGroupMenu(context, id, position)),
      onRenameGroup: repositories.renameTabGroup,
      onMoveWorktree: repositories.moveWorktreeTab,
      onCloseWorktrees: (ids) => unawaited(repositories.closeTabs(ids)),
      repositoryLabelBuilder: _repositoryLabel,
      worktreeLabelBuilder: _worktreeLabel,
      onOpenWorktree: (position) =>
          unawaited(_showWorktreeMenu(context, position)),
    );
    if (appearances == null) return tabs(context);
    return StreamBuilder<void>(
      stream: appearances.changes,
      builder: (context, _) => tabs(context),
    );
  }
}

/// The short name of the branch discovery found checked out, if any.
