import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../widgets/native_menu.dart';
import 'command_availability.dart';
import 'labels.dart';

/// Every registered command has a discoverable, stable place in the native menu.
const workspaceCommandGroups = <String, List<AppCommandId>>{
  'repository': [
    AppCommandId.openRepository,
    AppCommandId.openRemoteRepository,
    AppCommandId.cloneRepository,
    AppCommandId.initializeRepository,
    AppCommandId.closeRepositoryTab,
    AppCommandId.refreshRepository,
    AppCommandId.showRepositoryDetails,
  ],
  'changes': [
    AppCommandId.commitCreate,
    AppCommandId.commitAmend,
    AppCommandId.stageToggle,
    AppCommandId.stageSelection,
    AppCommandId.unstageSelection,
    AppCommandId.discardChanges,
    AppCommandId.patch,
    AppCommandId.createPatch,
    AppCommandId.applyPatch,
    AppCommandId.createStash,
    AppCommandId.applyStash,
    AppCommandId.popStash,
    AppCommandId.renameStash,
    AppCommandId.dropStash,
  ],
  'history': [
    AppCommandId.historyCompare,
    AppCommandId.saveCommitArchive,
    AppCommandId.checkoutCommit,
    AppCommandId.historyBlame,
    AppCommandId.historyPathHistory,
    AppCommandId.inspectorBack,
    AppCommandId.inspectorForward,
    AppCommandId.inspectorLensDiff,
    AppCommandId.inspectorLensContents,
    AppCommandId.inspectorLensBlame,
    AppCommandId.inspectorLensHistory,
    AppCommandId.inspectorOpenInWindow,
    AppCommandId.inspectorToggleMaximize,
    AppCommandId.inspectorToggleFiles,
    AppCommandId.inspectorAllFiles,
    AppCommandId.cherryPickSelected,
    AppCommandId.revertSelected,
    AppCommandId.resetBranch,
  ],
  'branches': [
    AppCommandId.createBranch,
    AppCommandId.checkoutBranch,
    AppCommandId.autoStashCheckout,
    AppCommandId.renameBranch,
    AppCommandId.deleteBranch,
    AppCommandId.deleteRemoteBranch,
    AppCommandId.integrateBranch,
    AppCommandId.mergeBranch,
    AppCommandId.rebaseBranch,
    AppCommandId.interactiveRebase,
    AppCommandId.restackBranches,
    AppCommandId.createTag,
    AppCommandId.deleteTag,
    AppCommandId.pushTag,
  ],
  'remotes': [
    AppCommandId.fetch,
    AppCommandId.pull,
    AppCommandId.push,
    AppCommandId.addRemote,
    AppCommandId.renameRemote,
    AppCommandId.editRemote,
    AppCommandId.removeRemote,
    AppCommandId.remoteFetch,
    AppCommandId.remotePush,
    AppCommandId.hostingCreatePullRequest,
  ],
  'recovery': [
    AppCommandId.showSnapshots,
    AppCommandId.inspectIndexLock,
    AppCommandId.rebaseContinue,
    AppCommandId.rebaseAbort,
    AppCommandId.conflictNext,
    AppCommandId.conflictPrevious,
    AppCommandId.conflictTakeCurrent,
    AppCommandId.conflictTakeIncoming,
    AppCommandId.conflictTakeBoth,
    AppCommandId.conflictOpenExternal,
    AppCommandId.rebaseSquash,
    AppCommandId.rebaseFixup,
    AppCommandId.rebaseReword,
    AppCommandId.rebaseDrop,
  ],
  'tools': [
    AppCommandId.openInEditor,
    AppCommandId.openInTerminal,
    AppCommandId.openInFileManager,
    AppCommandId.addWorktree,
    AppCommandId.trackLfsPattern,
    AppCommandId.addIntegration,
    AppCommandId.showIntegrations,
    AppCommandId.showPowerTools,
  ],
  'view': [
    AppCommandId.showChanges,
    AppCommandId.showHistory,
    AppCommandId.nextPane,
    AppCommandId.find,
    AppCommandId.diffToggleLayout,
    AppCommandId.diffRenderConfigured,
    AppCommandId.diffToggleWrap,
    AppCommandId.diffNextHunk,
    AppCommandId.diffPreviousHunk,
    AppCommandId.showOperations,
    AppCommandId.showActivity,
    AppCommandId.activityCopy,
    AppCommandId.activityRetry,
    AppCommandId.activityCancel,
  ],
  'application': [
    AppCommandId.showCommandPalette,
    AppCommandId.showSettings,
    AppCommandId.showShortcutReference,
    AppCommandId.showLicenses,
    AppCommandId.reportIssue,
  ],
};

String commandMenuGroupLabel(BuildContext context, String group) =>
    switch (group) {
      'repository' => context.l10n.menuRepository,
      'changes' => context.l10n.menuChanges,
      'history' => context.l10n.menuHistory,
      'branches' => context.l10n.menuBranches,
      'remotes' => context.l10n.menuRemotes,
      'recovery' => context.l10n.menuRecovery,
      'tools' => context.l10n.menuTools,
      'view' => context.l10n.menuView,
      'application' => context.l10n.menuApplication,
      _ => throw ArgumentError.value(group),
    };

const _nestedCommandGroups = <String, Map<String, List<AppCommandId>>>{
  'changes': {
    'patch': [
      AppCommandId.patch,
      AppCommandId.createPatch,
      AppCommandId.applyPatch,
    ],
    'stash': [
      AppCommandId.createStash,
      AppCommandId.applyStash,
      AppCommandId.popStash,
      AppCommandId.renameStash,
      AppCommandId.dropStash,
    ],
  },
  'branches': {
    'tags': [
      AppCommandId.createTag,
      AppCommandId.deleteTag,
      AppCommandId.pushTag,
    ],
  },
  'recovery': {
    'conflicts': [
      AppCommandId.conflictNext,
      AppCommandId.conflictPrevious,
      AppCommandId.conflictTakeCurrent,
      AppCommandId.conflictTakeIncoming,
      AppCommandId.conflictTakeBoth,
      AppCommandId.conflictOpenExternal,
    ],
    'rebase': [
      AppCommandId.rebaseContinue,
      AppCommandId.rebaseAbort,
      AppCommandId.rebaseSquash,
      AppCommandId.rebaseFixup,
      AppCommandId.rebaseReword,
      AppCommandId.rebaseDrop,
    ],
  },
  'view': {
    'diff': [
      AppCommandId.diffToggleLayout,
      AppCommandId.diffRenderConfigured,
      AppCommandId.diffToggleWrap,
      AppCommandId.diffNextHunk,
      AppCommandId.diffPreviousHunk,
    ],
    'activity': [
      AppCommandId.showOperations,
      AppCommandId.showActivity,
      AppCommandId.activityCopy,
      AppCommandId.activityRetry,
      AppCommandId.activityCancel,
    ],
  },
};

String _nestedLabel(BuildContext context, String group) => switch (group) {
  'patch' => context.l10n.patchTitle,
  'stash' => context.l10n.workspaceStashes,
  'tags' => context.l10n.workspaceTags,
  'conflicts' => context.l10n.conflictResolverTitle,
  'rebase' => context.l10n.menuRebase,
  'diff' => context.l10n.menuDiff,
  'activity' => context.l10n.menuActivity,
  _ => throw ArgumentError.value(group),
};

List<NativeMenuItem<AppCommandId>> workspaceCommandMenu(
  BuildContext context, {
  required CommandMenuState state,
  required Map<AppCommandId, AppShortcut?> shortcuts,
}) {
  List<NativeMenuItem<AppCommandId>> items(Iterable<AppCommandId> ids) =>
      commandMenuItems(context, ids, shortcuts, reason: state.reason);
  return [
    for (final group in workspaceCommandGroups.entries)
      NativeMenuItem.submenu(
        title: commandMenuGroupLabel(context, group.key),
        children: [
          ...items(
            group.value.where(
              (id) =>
                  !(_nestedCommandGroups[group.key]?.values.any(
                        (ids) => ids.contains(id),
                      ) ??
                      false),
            ),
          ),
          for (final nested
              in _nestedCommandGroups[group.key]?.entries ??
                  const <MapEntry<String, List<AppCommandId>>>[])
            NativeMenuItem.submenu(
              title: _nestedLabel(context, nested.key),
              children: items(nested.value),
            ),
        ],
      ),
  ];
}
