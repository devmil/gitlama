import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/history.dart';
import '../../widgets/native_menu.dart';
import '../../widgets/status_notification.dart';
import 'branch_filter.dart';
import 'labels.dart';
import 'sidebar.dart';

/// The graph filter a reference menu offers: the current filter and how to
/// change it.
typedef ReferenceMenuFilter = ({
  HistoryBranchFilter filter,
  ValueChanged<HistoryBranchFilter> onChanged,
});

/// The context menu of one branch, tag, stash or remote, wherever it is
/// shown (the sidebar row, a history reference chip or the commit menu).
///
/// Graph-filter actions come first, then the entry's own actions and its
/// commands, then copying its name. Destructive actions and commands come
/// last, behind a separator, flagged as dangerous.
List<NativeMenuAction> referenceMenuItems(
  BuildContext context, {
  required SidebarEntry entry,
  required String? reference,
  required Map<AppCommandId, AppShortcut?> shortcuts,
  required AppCommandDisabledReason? Function(AppCommandId) reason,
  required RunAppCommand onCommand,
  ReferenceMenuFilter? branchFilter,
}) {
  final name = entry.commandName ?? entry.name;
  void run(AppCommandId command) {
    if (reason(command) != null) return;
    onCommand(
      command,
      initialName:
          command == AppCommandId.createBranch ||
              command == AppCommandId.createTag
          ? null
          : name,
      initialTarget: entry.target,
      initialReference: reference,
    );
  }

  final filterActions = switch ((reference, branchFilter)) {
    (final reference?, final scope?) when isFilterableBranch(reference) =>
      branchFilterMenuActions(
        context.l10n,
        scope.filter,
        reference,
        upstream: entry.filterUpstream,
      ),
    _ => const <({String title, HistoryBranchFilter filter})>[],
  };
  return withDestructiveLast<VoidCallback>([
    for (final action in filterActions)
      NativeMenuAction(
        value: () => branchFilter!.onChanged(action.filter),
        title: action.title,
        icon: 'list-filter',
      ),
    const NativeMenuAction.separator(),
    for (final action in entry.actions)
      NativeMenuAction(
        value: () {
          if (action.enabled) action.onSelected();
        },
        title: action.label,
        enabled: action.enabled,
        danger: action.danger,
      ),
    ...nativeMenuActions(
      commandMenuItems(context, entry.commands, shortcuts, reason: reason),
      run,
    ),
    const NativeMenuAction.separator(),
    NativeMenuAction(
      value: () => unawaited(
        copyWithStatusNotification(context, name, context.l10n.menuNameCopied),
      ),
      title: context.l10n.sidebarCopyName,
      icon: 'copy',
    ),
  ]);
}
