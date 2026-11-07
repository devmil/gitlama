part of '../workspace_shell.dart';

/// The shell's commands: their availability, the one dispatcher every
/// menu, palette and shortcut runs, and what each command opens.
extension _ShellCommands on _WorkspaceShellState {
  CommandMenuState get _commandMenuState => _menuStateFor();

  CommandMenuState _menuStateFor([String? target]) => CommandMenuState(
    snapshot: _active?.session?.snapshot,
    busy: _workflows.busy.isBusy(_active?.id),
    canQueueStaging:
        _active != null && _workflows.changes.canStageFiles(_active!.id),
    scopes: _activeCommandScopes,
    selectedCommits: _history.page?.selectedObjectIds ?? const [],
    disabledSelections: _paneCommands.disabledSelections,
    hasActivity: _paneCommands.hasActivitySelection,
    hasDiff: _paneCommands.hasDiff,
    hasHistoryPath:
        _inspector.location?.path != null ||
        (_inspector.inspection?.files.isNotEmpty ?? false),
    inspectorShown: _inspector.location != null,
    canBrowseAllFiles: canBrowseAllFiles(_inspector.location),
    inspectorCanBack: _inspector.canBack,
    inspectorCanForward: _inspector.canForward,
    // Any commit a menu targets, selected or not.
    isMergeCommit: (id) {
      final index = widget.repositories.history.indexOfLoadedObjectId(id);
      if (index == null) return false;
      return (widget.repositories.history.rowAt(index)?.parents.length ?? 0) >
          1;
    },
    canRetryActivity: _operations.entries.any((entry) => entry.canRetry),
    canCancelActivity: _operations.entries.any(_workflows.operations.canCancel),
    remote: _activeRemote,
  );

  void _executeCommand(
    AppCommandId id, {
    String? initialName,
    String? initialTarget,
    String? initialReference,
    bool force = false,
  }) {
    final head = _active?.session?.snapshot.refs.branches
        .where((branch) => branch.head)
        .firstOrNull;
    final disabled = _menuStateFor(initialTarget).reason(
      id,
      target: initialTarget,
      reference:
          initialReference ??
          (initialName == null ? null : RefNames.branch(initialName)),
      current:
          initialReference == null &&
          initialName != null &&
          head != null &&
          initialName == utf8.decode(head.name, allowMalformed: true),
      contextual: initialName != null || initialTarget != null,
    );
    if (disabled != null) {
      StatusNotificationScope.show(
        context,
        workspaceDisabledReason(context, disabled),
      );
      return;
    }
    switch (id) {
      case AppCommandId.openRepository:
        widget.onOpenRepository();
      case AppCommandId.openRemoteRepository:
        unawaited(_remote.openRemoteRepository(context));
      case AppCommandId.cloneRepository:
        widget.onCloneRepository();
      case AppCommandId.initializeRepository:
        widget.onInitializeRepository();
      case AppCommandId.closeRepositoryTab:
        final tab = _active;
        if (tab != null) unawaited(widget.repositories.closeTab(tab.id));
      case AppCommandId.showRepositoryDetails:
        unawaited(_showRepositoryDetails());
      case AppCommandId.refreshRepository:
        unawaited(_refreshRepository());
      case AppCommandId.showChanges:
        _selectPane(WorkspacePane.changes);
      case AppCommandId.showHistory:
        _selectPane(WorkspacePane.history);
      case AppCommandId.commitCreate:
        _runChangesCommand(id);
      case AppCommandId.commitAmend:
        _runChangesCommand(id);
      case AppCommandId.stageToggle:
        _runChangesCommand(id);
      case AppCommandId.stageSelection:
        _runChangesCommand(id);
      case AppCommandId.unstageSelection:
        _runChangesCommand(id);
      case AppCommandId.discardChanges:
        _runChangesCommand(id);
      case AppCommandId.diffToggleLayout:
        _runDiffCommand(id);
      case AppCommandId.diffRenderConfigured:
        _runDiffCommand(id);
      case AppCommandId.diffToggleWrap:
        _runDiffCommand(id);
      case AppCommandId.diffNextHunk:
        _runDiffCommand(id);
      case AppCommandId.diffPreviousHunk:
        _runDiffCommand(id);
      case AppCommandId.conflictNext:
        _runChangesCommand(id);
      case AppCommandId.conflictPrevious:
        _runChangesCommand(id);
      case AppCommandId.conflictTakeCurrent:
        _runChangesCommand(id);
      case AppCommandId.conflictTakeIncoming:
        _runChangesCommand(id);
      case AppCommandId.conflictTakeBoth:
        _runChangesCommand(id);
      case AppCommandId.conflictOpenExternal:
        _runChangesCommand(id);
      case AppCommandId.rebaseContinue:
        _runChangesCommand(id);
      case AppCommandId.rebaseAbort:
        _runChangesCommand(id);
      case AppCommandId.rebaseSquash:
        _contextualCommandUnavailable();
      case AppCommandId.rebaseFixup:
        _contextualCommandUnavailable();
      case AppCommandId.rebaseReword:
        _contextualCommandUnavailable();
      case AppCommandId.rebaseDrop:
        _contextualCommandUnavailable();
      case AppCommandId.nextPane:
        _selectPane(
          _active?.navigation.pane == WorkspacePane.changes
              ? WorkspacePane.history
              : WorkspacePane.changes,
        );
      case AppCommandId.find:
        _findInRepository();
      case AppCommandId.showOperations:
        _toggleOperations();
      case AppCommandId.showActivity:
        _update(() => _activityVisible = !_activityVisible);
      case AppCommandId.activityCopy:
        _copyCurrentActivity();
      case AppCommandId.activityRetry:
        _runLatestOperation(retry: true);
      case AppCommandId.activityCancel:
        _runLatestOperation(retry: false);
      case AppCommandId.showSnapshots:
        _toggleSnapshots();
      case AppCommandId.patch:
        unawaited(_showPatchWorkflow());
      case AppCommandId.createPatch:
        unawaited(
          _showPatchWorkflow(
            initialMode: PatchDialogMode.create,
            commitOverride: initialTarget,
          ),
        );
      case AppCommandId.applyPatch:
        unawaited(_showPatchWorkflow(initialMode: PatchDialogMode.apply));
      case AppCommandId.saveCommitArchive:
        final commit =
            initialTarget ??
            (_history.page?.selectedObjectIds ?? const <String>[])
                .where((id) => id != historyWorktreeObjectId)
                .singleOrNull;
        if (commit != null &&
            _active != null &&
            !_refusedRemotely(AppCommandId.saveCommitArchive)) {
          unawaited(
            saveCommitArchive(
              context,
              commands: widget.repositories.archives,
              chooseDestination: widget.repositories.chooseArchiveDestination,
              commit: commit,
              repositoryLabel: _active!.label,
            ),
          );
        }
      case AppCommandId.showCommandPalette:
        unawaited(_showCommandPalette());
      case AppCommandId.showSettings:
        unawaited(_showSettings());
      case AppCommandId.showShortcutReference:
        unawaited(_showShortcutReference());
      case AppCommandId.showLicenses:
        _showLicenses();
      case AppCommandId.reportIssue:
        unawaited(_reportIssue());
      case AppCommandId.inspectIndexLock:
        unawaited(_workflows.indexLock.run(_interaction));
      case AppCommandId.createBranch:
        unawaited(
          _runRefMutation(
            RefMutationKind.createBranch,
            initialName: initialName,
            initialTarget: initialTarget,
          ),
        );
      case AppCommandId.renameBranch:
        unawaited(_workflows.refs.editBranch(_interaction, initialName));
      case AppCommandId.deleteBranch:
        unawaited(
          _runRefMutation(
            RefMutationKind.deleteBranch,
            initialName: initialName,
          ),
        );
      case AppCommandId.deleteRemoteBranch:
        unawaited(
          _workflows.refs.deleteRemoteBranch(_interaction, initialReference),
        );
      case AppCommandId.checkoutCommit:
        unawaited(
          _workflows.history.checkoutCommit(
            _interaction,
            initialTarget ??
                (_history.page?.selectedObjectIds ?? const <String>[])
                    .where((id) => id != historyWorktreeObjectId)
                    .singleOrNull,
          ),
        );
      case AppCommandId.checkoutBranch:
        unawaited(
          _workflows.refs.checkout(_interaction, initialName, initialReference),
        );
      case AppCommandId.addRemote:
        unawaited(_runRefMutation(RefMutationKind.addRemote));
      case AppCommandId.editRemote:
        unawaited(
          _runRefMutation(RefMutationKind.editRemote, initialName: initialName),
        );
      case AppCommandId.renameRemote:
        unawaited(
          _runRefMutation(
            RefMutationKind.renameRemote,
            initialName: initialName,
          ),
        );
      case AppCommandId.removeRemote:
        unawaited(
          _runRefMutation(
            RefMutationKind.removeRemote,
            initialName: initialName,
          ),
        );
      case AppCommandId.remoteFetch:
        _runTransfer(TransferKind.fetch, initialRemote: initialName);
      case AppCommandId.remotePush:
        _runTransfer(
          TransferKind.push,
          initialRemote: initialName,
          initialForce: force,
        );
      case AppCommandId.hostingCreatePullRequest:
        _createHostingPullRequest();
      case AppCommandId.createTag:
        unawaited(
          _runRefMutation(
            RefMutationKind.createTag,
            initialName: initialName,
            initialTarget: initialTarget,
          ),
        );
      case AppCommandId.deleteTag:
        unawaited(
          _runRefMutation(RefMutationKind.deleteTag, initialName: initialName),
        );
      case AppCommandId.pushTag:
        _runTransfer(TransferKind.pushTag, initialBranch: initialName);
      case AppCommandId.resetBranch:
        unawaited(
          _runRefMutation(RefMutationKind.reset, initialTarget: initialTarget),
        );
      case AppCommandId.fetch:
        _runTransfer(TransferKind.fetch, initialRemote: initialName);
      case AppCommandId.pull:
        _runTransfer(TransferKind.pull, initialRemote: initialName);
      case AppCommandId.push:
        _runTransfer(
          TransferKind.push,
          initialRemote: initialName,
          initialForce: force,
        );
      case AppCommandId.openInEditor:
        _openTool(IntegrationKind.editor);
      case AppCommandId.openInTerminal:
        _openTool(IntegrationKind.terminal);
      case AppCommandId.openInFileManager:
        _openTool(IntegrationKind.fileManager);
      case AppCommandId.createStash:
        unawaited(_workflows.history.stash(_interaction, StashKind.push));
      case AppCommandId.applyStash:
        unawaited(
          _workflows.history.stash(
            _interaction,
            StashKind.apply,
            selector: initialName,
            objectId: initialTarget,
          ),
        );
      case AppCommandId.popStash:
        unawaited(
          _workflows.history.stash(
            _interaction,
            StashKind.pop,
            selector: initialName,
            objectId: initialTarget,
          ),
        );
      case AppCommandId.renameStash:
        unawaited(
          _workflows.history.stash(
            _interaction,
            StashKind.rename,
            selector: initialName,
            objectId: initialTarget,
          ),
        );
      case AppCommandId.dropStash:
        unawaited(
          _workflows.history.stash(
            _interaction,
            StashKind.drop,
            selector: initialName,
            objectId: initialTarget,
          ),
        );
      case AppCommandId.autoStashCheckout:
        unawaited(
          _workflows.history.stash(
            _interaction,
            StashKind.autoStashCheckout,
            targetBranch: initialName,
          ),
        );
      case AppCommandId.mergeBranch:
        unawaited(
          _workflows.history.mutateHistory(
            _interaction,
            HistoryMutationKind.merge,
            sourceName: initialName,
            target: initialTarget,
          ),
        );
      case AppCommandId.integrateBranch:
        unawaited(
          _workflows.history.integrateBranch(
            _interaction,
            sourceName: initialName,
            target: initialTarget,
          ),
        );
      case AppCommandId.rebaseBranch:
        unawaited(
          _workflows.history.rebase(_interaction, target: initialTarget),
        );
      case AppCommandId.interactiveRebase:
        unawaited(_workflows.history.rebase(_interaction));
      case AppCommandId.historyCompare:
        unawaited(_compareSelectedHistory());
      case AppCommandId.historyBlame:
        unawaited(_openHistoryInspection(InspectorLens.blame));
      case AppCommandId.historyPathHistory:
        unawaited(_openHistoryInspection(InspectorLens.history));
      case AppCommandId.inspectorBack:
        unawaited(widget.repositories.inspector.back());
      case AppCommandId.inspectorForward:
        unawaited(widget.repositories.inspector.forward());
      case AppCommandId.inspectorLensDiff:
        unawaited(_openHistoryInspection(InspectorLens.diff));
      case AppCommandId.inspectorLensContents:
        unawaited(_openHistoryInspection(InspectorLens.contents));
      case AppCommandId.inspectorLensBlame:
        unawaited(_openHistoryInspection(InspectorLens.blame));
      case AppCommandId.inspectorLensHistory:
        unawaited(_openHistoryInspection(InspectorLens.history));
      case AppCommandId.inspectorOpenInWindow:
        final location = _inspector.location;
        if (location != null) unawaited(_openInspectorWindow(location));
      case AppCommandId.inspectorToggleMaximize:
        _update(() => _inspectorMaximized = !_inspectorMaximized);
      case AppCommandId.inspectorToggleFiles:
        _inspectorFilesHidden.value = !_inspectorFilesHidden.value;
      case AppCommandId.inspectorAllFiles:
        unawaited(widget.repositories.inspector.browseAllFiles());
      case AppCommandId.restackBranches:
        unawaited(_workflows.history.restack(_interaction, initialName));
      case AppCommandId.cherryPickSelected:
        unawaited(
          _workflows.history.mutateHistory(
            _interaction,
            HistoryMutationKind.cherryPick,
            target: initialTarget,
          ),
        );
      case AppCommandId.revertSelected:
        unawaited(
          _workflows.history.mutateHistory(
            _interaction,
            HistoryMutationKind.revert,
            target: initialTarget,
          ),
        );
      case AppCommandId.addWorktree:
        _toggleExtensions();
      case AppCommandId.trackLfsPattern:
        _showExtensions(focusLfs: true);
      case AppCommandId.addIntegration:
        unawaited(
          _showSettings(initialCategory: SettingsCategory.customCommands),
        );
      case AppCommandId.showIntegrations:
        _toggleIntegrations();
      case AppCommandId.showPowerTools:
        _togglePowerTools();
    }
  }

  Future<void> _refreshRepository() async {
    // The Refresh icon spins once a refresh outlasts refreshSpinDelay
    // (NM-11).
    final run = ++_refreshRun;
    _refreshSpin?.cancel();
    _refreshSpin = Timer(GitLamaMotion.refreshSpinDelay * timeDilation, () {
      if (mounted && run == _refreshRun) {
        _update(() => _refreshSpinning = true);
      }
    });
    try {
      await widget.repositories.refresh();
    } on RepositorySessionException {
      if (mounted) {
        StatusNotificationScope.show(
          context,
          context.l10n.workspaceRefreshFailed,
          error: true,
        );
      }
    }
    if (run == _refreshRun) {
      _refreshSpin?.cancel();
      if (mounted && _refreshSpinning) {
        _update(() => _refreshSpinning = false);
      }
    }
    if (!mounted) return;
    await widget.operationCenter.refresh();
    _paneCommands.handler(PaneRole.activity)?.refresh?.call();
  }

  void _runChangesCommand(AppCommandId id) {
    _selectPane(WorkspacePane.changes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paneCommands.handler(PaneRole.changes)?.run(id);
    });
  }

  void _runDiffCommand(AppCommandId id) {
    final diff = _paneCommands.handler(PaneRole.commitDiff);
    if (diff == null) {
      _contextualCommandUnavailable();
      return;
    }
    diff.run(id);
  }

  void _contextualCommandUnavailable() {
    StatusNotificationScope.show(
      context,
      context.l10n.commandContextUnavailable,
    );
  }

  void _createHostingPullRequest() {
    if (!_integrationsVisible) _toggleIntegrations();
    final effects = _workflows.effects;
    effects.emit(WorkspaceEffectKind.createChangeRequest);
    // The hosting section takes the request when it is (or comes) on screen;
    // one still pending after the frame found no section to carry it out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (effects.take(WorkspaceEffectKind.createChangeRequest) != null) {
        _contextualCommandUnavailable();
      }
    });
  }

  Future<void> _compareSelectedHistory() async {
    if (!await _workflows.navigator.compareSelected()) {
      _contextualCommandUnavailable();
    }
  }

  /// Shows [lens] of the inspected file, or of the commit's first changed
  /// file: in the Detail pane or a window, by the setting and ⌘ or Ctrl.
  Future<void> _openHistoryInspection(InspectorLens lens) async {
    final location = _inspector.location;
    final files = _inspector.inspection?.files ?? const <CommitFileChange>[];
    final path =
        location?.path ??
        files
            .map(changeDisplayPath)
            .where((path) => path.isNotEmpty)
            .firstOrNull;
    if (location == null || path == null) {
      _contextualCommandUnavailable();
      return;
    }
    final next = location.copyWith(
      path: path,
      directory: location.path == null ? false : location.directory,
      lens: lens,
      clearLines: true,
      clearHistoryCommit: true,
      anchor: 0,
    );
    final window =
        _inspectionWindowsAllowed &&
        opensInWindow(
          lens: lens,
          inspectorVisible: _active?.navigation.pane == WorkspacePane.history,
          setting: widget.settings.current.appearance.inspectionOpenIn,
          invert: inspectionModifierPressed(),
        );
    if (window) {
      await _openInspectorWindow(next);
    } else {
      await widget.repositories.inspector.navigate(next);
    }
  }

  /// Whether the active tab's inspection may open a window: windows are
  /// available, and a remote tab's host is connected, since its windows read
  /// through this window's connection.
  bool get _inspectionWindowsAllowed =>
      widget.inspectionWindows.available && (_activeRemote?.connected ?? true);

  Future<void> _openInspectorWindow(InspectorLocation location) async {
    final windows = widget.inspectionWindows;
    final repository = _active?.canonicalIdentity;
    // A remote tab's window must name its host, never a local path.
    if (!_inspectionWindowsAllowed ||
        repository == null ||
        repository.isRemote != (_activeRemote != null)) {
      _contextualCommandUnavailable();
      return;
    }
    try {
      await windows.open(repository: repository, location: location);
    } on Object {
      _inspectionWindowFailed();
    }
  }

  /// Opens a working-tree path at the current commit. Where no inspector is
  /// on screen, inspection opens a window; without windows (or a remote host
  /// that is not connected) the History inspector shows it.
  void _inspectWorkingFile(
    List<int> path,
    InspectorLens lens, {
    required bool directory,
    required bool invert,
  }) {
    final active = _active;
    final head = active?.session?.snapshot.status?.headObjectId;
    if (active == null || head == null) {
      _contextualCommandUnavailable();
      return;
    }
    final location = InspectorLocation(
      target: CommitTarget(head),
      path: path,
      directory: directory,
      lens: lens,
    );
    if (_inspectionWindowsAllowed) {
      unawaited(_openInspectorWindow(location));
      return;
    }
    unawaited(_showInHistoryInspector(location));
  }

  Future<void> _showInHistoryInspector(InspectorLocation location) => _workflows
      .navigator
      .showInHistoryInspector(location, stillWanted: () => mounted);

  void _inspectionWindowFailed() {
    if (!mounted) return;
    StatusNotificationScope.show(
      context,
      context.l10n.historyWindowFailed,
      error: true,
    );
  }

  void _copyCurrentActivity() {
    if (!_activityVisible) _update(() => _activityVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paneCommands.handler(PaneRole.activity)?.run(AppCommandId.activityCopy);
    });
  }

  void _runLatestOperation({required bool retry}) {
    final operations = _workflows.operations;
    final selected = operations.latest(retry: retry);
    if (selected == null) {
      if (!_operationsVisible) _toggleOperations();
    } else if (retry) {
      operations.retry(selected);
    } else {
      operations.cancel(selected);
    }
  }

  Future<void> _showCommandPalette({Rect? originRect}) async {
    if (_paletteOpen) return;
    _update(() => _paletteOpen = true);
    var ranCommand = false;
    final selected = await showCommandPalette<Object>(
      context: context,
      originRect: originRect,
      ranCommand: () => ranCommand,
      builder: (context) => CommandPaletteDialog(
        onRun: () => ranCommand = true,
        availability: _commandMenuState,
        hasRepository: _active?.session != null,
        disabledSelectionCommands: _paneCommands.disabledSelections,
        activeScopes: _activeCommandScopes,
        shortcuts: _shownShortcuts(),
        customCommands: widget.settings.current.integrations
            .where((value) => value.kind == IntegrationKind.custom)
            .toList(growable: false),
        customCommandsDisabledReason: switch (remoteCommandReason(
          AppCommandId.showIntegrations,
          _activeRemote,
        )) {
          final reason? => workspaceDisabledReason(context, reason),
          null => null,
        },
      ),
    );
    if (!mounted) return;
    _update(() => _paletteOpen = false);
    if (selected is AppCommandId) {
      _executeCommand(selected);
    } else if (selected is IntegrationDefinition) {
      unawaited(_workflows.integrations.runConfigured(_interaction, selected));
    }
  }

  /// The Compass grows into the active repository's details.
  Future<void> _showRepositoryDetails() async {
    if (_detailsOpen || _repositoryDetails() == null) return;
    _update(() => _detailsOpen = true);
    await showRepositoryDetails(
      context: context,
      anchor: _compassRect(),
      builder: (context) => RepositoryDetailsPanel(
        read: _repositoryDetails,
        changes: _detailsRevision,
        fileBrowserName:
            configuredFileBrowserName(widget.settings) ??
            platformFileBrowserName(),
        onCopyPath: _copyRepositoryPath,
        onOpenFolder: (folder) => _openFolder(folder),
      ),
    );
    if (!mounted) return;
    _update(() => _detailsOpen = false);
  }

  RepositoryDetails? _repositoryDetails() {
    final tab = _active;
    if (!mounted || tab == null || tab.phase == RepositoryTabPhase.choosing) {
      return null;
    }
    final authority = remoteAuthorityOf(tab);
    final group = widget.workspace.group(tab.groupId);
    return RepositoryDetails.of(
      tab,
      name: widget.appearances.nameFor(tab.canonicalIdentity) ?? tab.label,
      group: group == null || group.name.isEmpty ? null : group.name,
      remote: authority != null,
      host: authority == null ? null : _remote.hostLabel(authority),
      hostAlias: authority == null
          ? null
          : _remote.service?.profile(authority.profileId)?.alias,
      hostDisconnected:
          authority != null && widget.repositories.isRemoteTabStale(tab),
      operations: _operations,
    );
  }

  Future<void> _copyRepositoryPath(NativePathIdentity path) =>
      copyWithStatusNotification(
        context,
        path.displayText,
        context.l10n.repositoryPathCopied,
      );

  Set<AppCommandShortcutScope> get _activeCommandScopes {
    final pane = _active?.navigation.pane;
    if (pane == WorkspacePane.changes) {
      final conflict = hasActiveConflicts(_active?.session?.snapshot.status);
      return {
        conflict
            ? AppCommandShortcutScope.conflict
            : AppCommandShortcutScope.changes,
      };
    }
    if (pane == WorkspacePane.history) {
      return {
        AppCommandShortcutScope.history,
        if (_inspector.diff != null) AppCommandShortcutScope.diff,
      };
    }
    return const {AppCommandShortcutScope.global};
  }

  /// Opens the repository, or [file] in it, with a tool of [kind].
  void _openTool(IntegrationKind kind, {NativePathIdentity? file}) =>
      unawaited(_workflows.integrations.open(_interaction, kind, file: file));

  /// Opens [folder] itself (a repository or worktree root) in the file
  /// manager.
  void _openFolder(NativePathIdentity folder) =>
      unawaited(_workflows.integrations.openFolder(_interaction, folder));

  Future<void> _showPatchWorkflow({
    PatchDialogMode? initialMode,
    String? commitOverride,
  }) async {
    if (_active?.session == null ||
        _refusedRemotely(
          initialMode == PatchDialogMode.apply
              ? AppCommandId.applyPatch
              : AppCommandId.createPatch,
        )) {
      return;
    }
    // The Changes pane makes patches of its own selection.
    final changes = _paneCommands.handler(PaneRole.changes)?.showPatchWorkflow;
    if (_active?.navigation.pane == WorkspacePane.changes && changes != null) {
      await changes(apply: initialMode == PatchDialogMode.apply);
      return;
    }
    await _showPatchDialog(
      PatchRequestBuilder.history(_history.page, commit: commitOverride),
      initialMode: initialMode,
    );
  }

  Future<void> _showPatchDialog(
    PatchRequestFactory request, {
    PatchDialogMode? initialMode,
  }) => showPatchDialog(
    context,
    repositories: widget.repositories,
    repositoryLabel: _active!.label,
    onShowInFolder: (path) =>
        _openTool(IntegrationKind.fileManager, file: path),
    applyUnavailableReason: _remoteReasonText(AppCommandId.applyPatch),
    initialMode: initialMode,
    request: request,
  );

  /// Creates a patch of the commit or comparison whose diff is on screen,
  /// limited to [paths] when the diff shows one file.
  Future<void> _createDiffPatch(
    InspectorTarget target,
    List<List<int>> paths,
  ) async {
    if (_active?.session == null ||
        _refusedRemotely(AppCommandId.createPatch)) {
      return;
    }
    await _showPatchDialog(
      PatchRequestBuilder.diff(target, paths),
      initialMode: PatchDialogMode.create,
    );
  }

  Future<void> _runRefMutation(
    RefMutationKind kind, {
    String? initialName,
    String? initialTarget,
  }) => _workflows.refs.mutate(
    _interaction,
    kind,
    initialName: initialName,
    initialTarget: initialTarget,
  );

  /// Lets the user start a [kind] transfer of the active repository.
  void _runTransfer(
    TransferKind kind, {
    bool initialForce = false,
    String? initialRemote,
    String? initialBranch,
    PullStrategy initialPullStrategy = PullStrategy.fastForwardOnly,
  }) {
    final snapshot = _active?.session?.snapshot;
    if (snapshot == null) return;
    unawaited(
      _workflows.transfers.start(
        _interaction,
        TransferDraft(
          kind: kind,
          snapshot: snapshot,
          initialForce: initialForce,
          initialRemote: initialRemote,
          initialBranch: initialBranch,
          initialPullStrategy: initialPullStrategy,
        ),
      ),
    );
  }

  bool get _activeBusy => _workflows.busy.isBlocked(_active?.id);

  /// The repository area of the active tab, under a busy overlay while an
  /// operation blocks it. The area keeps its place in the tree so its
  /// scroll positions survive.
  Widget _blockedByOperation(Widget child) {
    final blocking = _workflows.busy.blockingOf(_active?.id);
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(excluding: blocking != null, child: child),
        if (blocking != null)
          MeridianBusyOverlay(
            key: ObjectKey(blocking),
            message: busyActivityLabel(context, blocking.activity),
            action: !blocking.cancellable
                ? null
                : MeridianButton(
                    label: blocking.canceling
                        ? context.l10n.historyMutationCanceling
                        : context.l10n.cancel,
                    variant: MeridianButtonVariant.quiet,
                    onPressed: blocking.canceling
                        ? null
                        : () => unawaited(_workflows.busy.cancel(blocking)),
                  ),
          ),
      ],
    );
  }

  void _showShortcutReferenceUnlessEditing() {
    if (_isEditingText) return;
    unawaited(_showShortcutReference());
  }

  bool get _isEditingText => textInputHasFocus();

  bool _isTextCharacterShortcut(AppShortcut shortcut) {
    final activator = shortcut.activator;
    return !activator.alt &&
        !activator.control &&
        !activator.meta &&
        (shortcut.key == 'Space' || shortcut.key.characters.length == 1);
  }

  Map<AppCommandId, AppShortcut?> _shownShortcuts() => AppShortcutCatalog.shown(
    widget.settings.current.shortcutOverrides,
    macOS: defaultTargetPlatform == TargetPlatform.macOS,
  );

  Future<void> _showShortcutReference() => showMeridianDialog<void>(
    context: context,
    builder: (context) => ShortcutReferenceDialog(shortcuts: _shownShortcuts()),
  );

  Future<void> _showSettings({
    SettingsCategory initialCategory = SettingsCategory.appearance,
  }) => showSettingsDialog(
    context,
    settings: widget.settings,
    repositories: widget.repositories,
    hosting: widget.hosting,
    // Repository settings are local; a remote tab has none to change.
    repository: _activeRemote == null ? _active : null,
    hostingRepository: _active,
    initialCategory: initialCategory,
    updates: widget.updates,
    remote: _remote,
  );

  void _showLicenses() => showAppLicenses(context);

  Future<void> _reportIssue() async {
    try {
      await widget.updates.openIssues();
    } on AppUpdateException {
      if (mounted) {
        showWorkflowMessage(context, (
          text: context.l10n.reportIssueOpenFailed,
          error: true,
        ));
      }
    }
  }

  Future<void> _openSourceCode() async {
    try {
      await widget.updates.openSource();
    } on AppUpdateException {
      if (mounted) {
        showWorkflowMessage(context, (
          text: context.l10n.aboutSourceCodeOpenFailed,
          error: true,
        ));
      }
    }
  }
}
