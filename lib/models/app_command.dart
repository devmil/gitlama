enum AppCommandId {
  openRepository,
  openRemoteRepository,
  cloneRepository,
  initializeRepository,
  closeRepositoryTab,
  refreshRepository,
  showRepositoryDetails,
  showChanges,
  showHistory,
  commitCreate,
  commitAmend,
  stageToggle,
  stageSelection,
  unstageSelection,
  discardChanges,
  diffToggleLayout,
  diffRenderConfigured,
  diffToggleWrap,
  diffNextHunk,
  diffPreviousHunk,
  conflictNext,
  conflictPrevious,
  conflictTakeCurrent,
  conflictTakeIncoming,
  conflictTakeBoth,
  conflictOpenExternal,
  rebaseContinue,
  rebaseAbort,
  rebaseSquash,
  rebaseFixup,
  rebaseReword,
  rebaseDrop,
  nextPane,
  find,
  showOperations,
  showActivity,
  activityCopy,
  activityRetry,
  activityCancel,
  showSnapshots,
  patch,
  createPatch,
  saveCommitArchive,
  checkoutCommit,
  applyPatch,
  showCommandPalette,
  showSettings,
  showShortcutReference,
  showLicenses,
  reportIssue,
  inspectIndexLock,
  createBranch,
  renameBranch,
  deleteBranch,
  deleteRemoteBranch,
  checkoutBranch,
  addRemote,
  editRemote,
  renameRemote,
  removeRemote,
  remoteFetch,
  remotePush,
  hostingCreatePullRequest,
  createTag,
  deleteTag,
  pushTag,
  resetBranch,
  fetch,
  pull,
  push,
  openInEditor,
  openInTerminal,
  openInFileManager,
  createStash,
  applyStash,
  popStash,
  renameStash,
  dropStash,
  autoStashCheckout,
  integrateBranch,
  mergeBranch,
  rebaseBranch,
  interactiveRebase,
  historyCompare,
  historyBlame,
  historyPathHistory,
  inspectorBack,
  inspectorForward,
  inspectorLensDiff,
  inspectorLensContents,
  inspectorLensBlame,
  inspectorLensHistory,
  inspectorOpenInWindow,
  inspectorToggleMaximize,
  inspectorToggleFiles,
  inspectorAllFiles,
  restackBranches,
  cherryPickSelected,
  revertSelected,
  addWorktree,
  trackLfsPattern,
  addIntegration,
  showIntegrations,
  showPowerTools,
}

enum AppCommandGroup { commands, repository, settings }

enum AppCommandShortcutScope {
  global,
  changes,
  history,
  diff,
  conflict,
  rebase,
  sidebar,
}

enum AppCommandDisabledReason {
  repositoryRequired,
  repositoryBusy,
  contextRequired,
  featureUnavailable,

  /// The repository lives on another computer and the command is not
  /// offered there.
  remoteUnsupported,

  /// The repository lives on another computer whose connection is down.
  remoteDisconnected,

  /// The host did not offer the change although this computer asked for it.
  remoteWritesUnavailable,

  /// "Allow changes on this host" is off.
  remoteWritesOff,

  /// Changes were allowed after the connection started; reconnecting applies
  /// them.
  remoteWritesReconnect,

  /// The record of remote changes on this computer cannot be read.
  remoteWritesLedger,
}

final class AppCommandDefinition {
  const AppCommandDefinition({
    required this.id,
    required this.group,
    required this.icon,
    this.shortcut,
    this.macShortcut,
    this.keyHint,
    this.shortcutScopes = const [AppCommandShortcutScope.global],
    this.requiresRepository = false,
    this.available = true,
    this.destructive = false,
  });

  final AppCommandId id;
  final AppCommandGroup group;
  final String icon;

  /// The default binding on Windows and Linux, in the form
  /// [AppShortcutCatalog] parses (`Ctrl+Shift+P`).
  final String? shortcut;

  /// The default binding on macOS; [shortcut] when absent.
  final String? macShortcut;

  /// A key a focused list handles for this command itself, such as the
  /// sidebar's Insert. It is shown with the command but never bound globally.
  final String? keyHint;

  /// The default binding on the platform [macOS] names.
  String? defaultShortcut({required bool macOS}) =>
      macOS ? macShortcut ?? shortcut : shortcut;
  final List<AppCommandShortcutScope> shortcutScopes;
  final bool requiresRepository;
  final bool available;

  /// Whether the command deletes or discards something that may not be
  /// recoverable. Menus mark it as dangerous and list it last.
  final bool destructive;

  /// [repositoryBusy] is true while an operation blocks the open repository.
  AppCommandDisabledReason? disabledReason({
    required bool hasRepository,
    bool repositoryBusy = false,
    Set<AppCommandShortcutScope>? activeScopes,
  }) {
    if (requiresRepository && !hasRepository) {
      return AppCommandDisabledReason.repositoryRequired;
    }
    if (requiresRepository && repositoryBusy) {
      return AppCommandDisabledReason.repositoryBusy;
    }
    if (!available) return AppCommandDisabledReason.featureUnavailable;
    if (activeScopes != null &&
        !shortcutScopes.contains(AppCommandShortcutScope.global) &&
        !shortcutScopes.any(activeScopes.contains)) {
      return AppCommandDisabledReason.contextRequired;
    }
    return null;
  }
}

abstract final class AppCommandRegistry {
  static const commands = <AppCommandDefinition>[
    AppCommandDefinition(
      id: AppCommandId.openRepository,
      group: AppCommandGroup.repository,
      icon: 'folder-open',
      shortcut: 'Ctrl+O',
      macShortcut: 'Cmd+O',
    ),
    AppCommandDefinition(
      id: AppCommandId.openRemoteRepository,
      group: AppCommandGroup.repository,
      icon: 'server',
      shortcut: 'Ctrl+Shift+O',
      macShortcut: 'Cmd+Shift+O',
    ),
    AppCommandDefinition(
      id: AppCommandId.cloneRepository,
      group: AppCommandGroup.repository,
      icon: 'fetch',
    ),
    AppCommandDefinition(
      id: AppCommandId.initializeRepository,
      group: AppCommandGroup.repository,
      icon: 'plus',
    ),
    AppCommandDefinition(
      id: AppCommandId.closeRepositoryTab,
      group: AppCommandGroup.repository,
      icon: 'close',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.refreshRepository,
      group: AppCommandGroup.repository,
      icon: 'refresh',
      shortcut: 'Ctrl+R',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showRepositoryDetails,
      group: AppCommandGroup.repository,
      icon: 'info',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showChanges,
      group: AppCommandGroup.commands,
      icon: 'changes',
      shortcut: 'Ctrl+1',
      macShortcut: 'Cmd+1',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showHistory,
      group: AppCommandGroup.commands,
      icon: 'history',
      shortcut: 'Ctrl+2',
      macShortcut: 'Cmd+2',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.commitCreate,
      group: AppCommandGroup.commands,
      icon: 'check',
      shortcut: 'Ctrl+Enter',
      macShortcut: 'Cmd+Enter',
      shortcutScopes: [AppCommandShortcutScope.changes],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.commitAmend,
      group: AppCommandGroup.commands,
      icon: 'pencil',
      shortcutScopes: [AppCommandShortcutScope.changes],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.stageToggle,
      group: AppCommandGroup.commands,
      icon: 'stage-all',
      shortcut: 'Space',
      shortcutScopes: [AppCommandShortcutScope.changes],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.stageSelection,
      group: AppCommandGroup.commands,
      icon: 'arrow-right',
      shortcutScopes: [
        AppCommandShortcutScope.changes,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.unstageSelection,
      group: AppCommandGroup.commands,
      icon: 'arrow-left',
      shortcutScopes: [
        AppCommandShortcutScope.changes,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.discardChanges,
      destructive: true,
      group: AppCommandGroup.commands,
      icon: 'trash',
      shortcutScopes: [
        AppCommandShortcutScope.changes,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.diffToggleLayout,
      group: AppCommandGroup.commands,
      icon: 'side-by-side',
      shortcutScopes: [AppCommandShortcutScope.diff],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.diffRenderConfigured,
      group: AppCommandGroup.commands,
      icon: 'brush-cleaning',
      shortcutScopes: [
        AppCommandShortcutScope.changes,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.diffToggleWrap,
      group: AppCommandGroup.commands,
      icon: 'wrap',
      shortcutScopes: [AppCommandShortcutScope.diff],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.diffNextHunk,
      group: AppCommandGroup.commands,
      icon: 'arrow-down',
      shortcutScopes: [AppCommandShortcutScope.diff],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.diffPreviousHunk,
      group: AppCommandGroup.commands,
      icon: 'arrow-up',
      shortcutScopes: [AppCommandShortcutScope.diff],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.conflictNext,
      group: AppCommandGroup.commands,
      icon: 'arrow-down',
      shortcut: 'F8',
      shortcutScopes: [AppCommandShortcutScope.conflict],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.conflictPrevious,
      group: AppCommandGroup.commands,
      icon: 'arrow-up',
      shortcut: 'Shift+F8',
      shortcutScopes: [AppCommandShortcutScope.conflict],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.conflictTakeCurrent,
      group: AppCommandGroup.commands,
      icon: 'arrow-left',
      shortcut: 'Alt+1',
      shortcutScopes: [AppCommandShortcutScope.conflict],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.conflictTakeIncoming,
      group: AppCommandGroup.commands,
      icon: 'arrow-right',
      shortcut: 'Alt+2',
      shortcutScopes: [AppCommandShortcutScope.conflict],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.conflictTakeBoth,
      group: AppCommandGroup.commands,
      icon: 'git-merge',
      shortcut: 'Alt+3',
      shortcutScopes: [AppCommandShortcutScope.conflict],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.conflictOpenExternal,
      group: AppCommandGroup.commands,
      icon: 'external-link',
      shortcutScopes: [AppCommandShortcutScope.conflict],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseContinue,
      group: AppCommandGroup.repository,
      icon: 'skip-forward',
      shortcutScopes: [
        AppCommandShortcutScope.rebase,
        AppCommandShortcutScope.conflict,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseAbort,
      group: AppCommandGroup.repository,
      icon: 'ban',
      shortcutScopes: [
        AppCommandShortcutScope.rebase,
        AppCommandShortcutScope.conflict,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseSquash,
      group: AppCommandGroup.repository,
      icon: 'squash',
      shortcutScopes: [AppCommandShortcutScope.rebase],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseFixup,
      group: AppCommandGroup.repository,
      icon: 'fixup',
      shortcutScopes: [AppCommandShortcutScope.rebase],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseReword,
      group: AppCommandGroup.repository,
      icon: 'pencil',
      shortcutScopes: [AppCommandShortcutScope.rebase],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseDrop,
      group: AppCommandGroup.repository,
      icon: 'trash',
      shortcutScopes: [AppCommandShortcutScope.rebase],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.nextPane,
      group: AppCommandGroup.commands,
      icon: 'arrow-right',
      shortcut: 'Ctrl+Tab',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.find,
      group: AppCommandGroup.commands,
      icon: 'inspect',
      shortcut: 'Ctrl+F',
      macShortcut: 'Cmd+F',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showOperations,
      group: AppCommandGroup.commands,
      icon: 'circle-dot',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showActivity,
      group: AppCommandGroup.commands,
      icon: 'list-view',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.activityCopy,
      group: AppCommandGroup.commands,
      icon: 'copy',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.activityRetry,
      group: AppCommandGroup.repository,
      icon: 'rotate-cw',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.activityCancel,
      group: AppCommandGroup.repository,
      icon: 'ban',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.patch,
      group: AppCommandGroup.repository,
      icon: 'file',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.createPatch,
      group: AppCommandGroup.repository,
      icon: 'file',
      shortcut: 'Ctrl+Shift+P',
      macShortcut: 'Cmd+Shift+P',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.checkoutCommit,
      group: AppCommandGroup.commands,
      icon: 'log-in',
      shortcutScopes: [AppCommandShortcutScope.history],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.saveCommitArchive,
      group: AppCommandGroup.commands,
      icon: 'archive',
      shortcutScopes: [AppCommandShortcutScope.history],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.applyPatch,
      group: AppCommandGroup.repository,
      icon: 'file',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showSnapshots,
      group: AppCommandGroup.commands,
      icon: 'box',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showCommandPalette,
      group: AppCommandGroup.commands,
      icon: 'command',
      shortcut: 'Ctrl+P',
      macShortcut: 'Cmd+P',
    ),
    AppCommandDefinition(
      id: AppCommandId.showSettings,
      group: AppCommandGroup.settings,
      icon: 'settings',
      shortcut: 'Ctrl+,',
      macShortcut: 'Cmd+,',
    ),
    AppCommandDefinition(
      id: AppCommandId.showShortcutReference,
      group: AppCommandGroup.settings,
      icon: 'shortcuts',
      shortcut: '?',
    ),
    AppCommandDefinition(
      id: AppCommandId.showLicenses,
      group: AppCommandGroup.settings,
      icon: 'badge-check',
    ),
    AppCommandDefinition(
      id: AppCommandId.reportIssue,
      group: AppCommandGroup.settings,
      icon: 'bug',
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectIndexLock,
      group: AppCommandGroup.repository,
      icon: 'recovery',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.createBranch,
      group: AppCommandGroup.repository,
      icon: 'plus',
      keyHint: 'Insert',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.sidebar,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.renameBranch,
      group: AppCommandGroup.repository,
      icon: 'pencil',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.deleteBranch,
      destructive: true,
      group: AppCommandGroup.repository,
      icon: 'trash',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.deleteRemoteBranch,
      destructive: true,
      group: AppCommandGroup.repository,
      icon: 'trash',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.checkoutBranch,
      group: AppCommandGroup.repository,
      icon: 'log-in',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.sidebar,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.addRemote,
      group: AppCommandGroup.repository,
      icon: 'plus',
      keyHint: 'Insert',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.editRemote,
      group: AppCommandGroup.repository,
      icon: 'link',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.renameRemote,
      group: AppCommandGroup.repository,
      icon: 'pencil',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.removeRemote,
      destructive: true,
      group: AppCommandGroup.repository,
      icon: 'trash',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.remoteFetch,
      group: AppCommandGroup.repository,
      icon: 'fetch',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.remotePush,
      group: AppCommandGroup.repository,
      icon: 'push',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.hostingCreatePullRequest,
      group: AppCommandGroup.repository,
      icon: 'git-pull-request',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.createTag,
      group: AppCommandGroup.repository,
      icon: 'plus',
      keyHint: 'Insert',
      shortcutScopes: [AppCommandShortcutScope.history],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.deleteTag,
      destructive: true,
      group: AppCommandGroup.repository,
      icon: 'trash',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.sidebar,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.pushTag,
      group: AppCommandGroup.repository,
      icon: 'push',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.sidebar,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.resetBranch,
      destructive: true,
      group: AppCommandGroup.repository,
      icon: 'recovery',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.fetch,
      group: AppCommandGroup.repository,
      icon: 'fetch',
      shortcut: 'Ctrl+Shift+K',
      macShortcut: 'Cmd+Shift+K',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.pull,
      group: AppCommandGroup.repository,
      icon: 'pull',
      shortcut: 'Ctrl+Down',
      macShortcut: 'Cmd+Down',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.push,
      group: AppCommandGroup.repository,
      icon: 'push',
      shortcut: 'Ctrl+Up',
      macShortcut: 'Cmd+Up',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.openInEditor,
      group: AppCommandGroup.repository,
      icon: 'external-link',
      shortcut: 'Ctrl+Alt+E',
      macShortcut: 'Cmd+Alt+E',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.openInTerminal,
      group: AppCommandGroup.repository,
      icon: 'command',
      shortcut: 'Ctrl+Alt+T',
      macShortcut: 'Cmd+Alt+T',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.openInFileManager,
      group: AppCommandGroup.repository,
      icon: 'folder-open',
      shortcut: 'Ctrl+Alt+F',
      macShortcut: 'Cmd+Alt+F',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.createStash,
      group: AppCommandGroup.repository,
      icon: 'plus',
      shortcut: 'Ctrl+S',
      macShortcut: 'Cmd+S',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.applyStash,
      group: AppCommandGroup.repository,
      icon: 'rotate-ccw',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.popStash,
      group: AppCommandGroup.repository,
      icon: 'stash',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.renameStash,
      group: AppCommandGroup.repository,
      icon: 'pencil',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.dropStash,
      destructive: true,
      group: AppCommandGroup.repository,
      icon: 'trash',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.autoStashCheckout,
      group: AppCommandGroup.repository,
      icon: 'git-fork',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.integrateBranch,
      group: AppCommandGroup.repository,
      icon: 'git-pull-request',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.mergeBranch,
      group: AppCommandGroup.repository,
      icon: 'git-merge',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.sidebar,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.rebaseBranch,
      group: AppCommandGroup.repository,
      icon: 'arrow-left-right',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.sidebar,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.interactiveRebase,
      group: AppCommandGroup.repository,
      icon: 'arrow-left-right',
      shortcutScopes: [AppCommandShortcutScope.history],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.historyCompare,
      group: AppCommandGroup.commands,
      icon: 'arrow-left-right',
      shortcutScopes: [AppCommandShortcutScope.history],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.historyBlame,
      group: AppCommandGroup.commands,
      icon: 'blame',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.historyPathHistory,
      group: AppCommandGroup.commands,
      icon: 'folder-history',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorBack,
      group: AppCommandGroup.commands,
      icon: 'back',
      shortcut: 'Alt+Left',
      macShortcut: 'Cmd+[',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorForward,
      group: AppCommandGroup.commands,
      icon: 'forward',
      shortcut: 'Alt+Right',
      macShortcut: 'Cmd+]',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorLensDiff,
      group: AppCommandGroup.commands,
      icon: 'file-diff',
      shortcut: 'Ctrl+Alt+1',
      macShortcut: 'Cmd+Alt+1',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorLensContents,
      group: AppCommandGroup.commands,
      icon: 'file-text',
      shortcut: 'Ctrl+Alt+2',
      macShortcut: 'Cmd+Alt+2',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorLensBlame,
      group: AppCommandGroup.commands,
      icon: 'blame',
      shortcut: 'Ctrl+Alt+3',
      macShortcut: 'Cmd+Alt+3',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorLensHistory,
      group: AppCommandGroup.commands,
      icon: 'history',
      shortcut: 'Ctrl+Alt+4',
      macShortcut: 'Cmd+Alt+4',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorOpenInWindow,
      group: AppCommandGroup.commands,
      icon: 'app-window',
      shortcut: 'Ctrl+Shift+N',
      macShortcut: 'Cmd+Shift+N',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorToggleMaximize,
      group: AppCommandGroup.commands,
      icon: 'maximize-2',
      shortcut: 'Ctrl+Shift+Enter',
      macShortcut: 'Cmd+Shift+Enter',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorToggleFiles,
      group: AppCommandGroup.commands,
      icon: 'panel-left',
      shortcut: 'Ctrl+Alt+B',
      macShortcut: 'Cmd+Alt+B',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.inspectorAllFiles,
      group: AppCommandGroup.commands,
      icon: 'tree-view',
      shortcutScopes: [
        AppCommandShortcutScope.history,
        AppCommandShortcutScope.diff,
      ],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.restackBranches,
      group: AppCommandGroup.repository,
      icon: 'branch',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.cherryPickSelected,
      group: AppCommandGroup.repository,
      icon: 'check',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.revertSelected,
      group: AppCommandGroup.repository,
      icon: 'rotate-ccw',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.addWorktree,
      group: AppCommandGroup.repository,
      icon: 'plus',
      keyHint: 'Insert',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.trackLfsPattern,
      group: AppCommandGroup.repository,
      icon: 'plus',
      keyHint: 'Insert',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.addIntegration,
      group: AppCommandGroup.settings,
      icon: 'plus',
      keyHint: 'Insert',
      shortcutScopes: [AppCommandShortcutScope.sidebar],
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showIntegrations,
      group: AppCommandGroup.settings,
      icon: 'command',
      requiresRepository: true,
    ),
    AppCommandDefinition(
      id: AppCommandId.showPowerTools,
      group: AppCommandGroup.repository,
      icon: 'inspect',
      requiresRepository: true,
    ),
  ];

  static AppCommandDefinition byId(AppCommandId id) =>
      commands.firstWhere((command) => command.id == id);
}
