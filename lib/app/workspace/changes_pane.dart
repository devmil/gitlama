import '../../models/operation_failure.dart';
import '../../widgets/status_notification.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import '../../models/discard.dart';
import '../../models/diff.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/history.dart';
import '../../models/integrations.dart';
import '../../models/patch.dart';
import '../../models/remote_command_policy.dart';
import '../../models/repository_state.dart';
import '../../models/workspace.dart';
import '../app_shortcut_activator.dart';
import '../welcome_screen.dart' show repositoryFailureDetail;
import '../gitlama_layout.dart';
import '../../services/repository_session_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/conflict_resolver.dart';
import 'shell_chrome.dart';
import 'sidebar.dart';
import 'commit_editor.dart';
import '../../widgets/git_file_list/git_file_list.dart';
import 'changes_section.dart';
import 'history_pane.dart';
import 'working_tree_detail.dart';
import 'status_bar.dart';
import 'patch_dialog.dart';
import 'ignore_dialog.dart';
import '../../models/repository_extensions.dart';
import '../../models/remote_workspace.dart';
import 'labels.dart';
import 'command_availability.dart';
import 'remote_workspace.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../models/conflict.dart';
import '../../models/working_tree.dart';
import '../../services/workflows/changes_service.dart';
import '../../services/workflows/patch_request_builder.dart';
import 'workspace_scope.dart';
import 'shell_scopes.dart';
import '../../services/workflows/sync_change_tracker.dart';
import '../../services/workflows/workspace_effects.dart';
import '../app_theme.dart';
import 'diff_view_preferences.dart';

class PrimaryPane extends StatelessWidget {
  const PrimaryPane({
    super.key,
    required this.active,
    required this.powerToolsVisible,
    required this.onClosePowerTools,
    required this.onRevealPowerCommit,
    required this.onCommand,
    required this.history,
    this.sync = const SyncChange(),
    required this.shortcuts,
    required this.changesFilePaneWidth,
    required this.onChangesFilePaneWidthChanged,
  });

  final RepositoryTabState? active;
  final bool powerToolsVisible;
  final VoidCallback onClosePowerTools;
  final ValueChanged<String> onRevealPowerCommit;
  final RunAppCommand onCommand;
  final HistoryState history;

  /// What the last transfer changed, for History's arriving rows.
  final SyncChange sync;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final double changesFilePaneWidth;
  final ValueChanged<double> onChangesFilePaneWidthChanged;

  @override
  Widget build(BuildContext context) {
    if (active == null || active!.phase == RepositoryTabPhase.opening) {
      return MeridianEmptyState(
        compact: true,
        progress: true,
        title: context.l10n.workspaceLoadingRepository,
      );
    }
    if (active!.phase == RepositoryTabPhase.failed) {
      if (remoteTabFailure(context, active!) case final remote?) return remote;
      // A remote open, such as a worktree's, reports nowhere else why it
      // failed; a local one already shows it in the window's banner.
      final failure = remoteAuthorityOf(active!) == null
          ? null
          : active!.failure?.code;
      return MeridianEmptyState(
        compact: true,
        icon: 'circle-alert',
        title: context.l10n.workspaceUnavailableRepository,
        message: failure == null
            ? null
            : repositoryFailureDetail(context, failure),
      );
    }
    final pane = active!.navigation.pane;
    final status = active!.session?.snapshot.status;
    return Column(
      children: [
        if (pane == WorkspacePane.history)
          RepositoryConditions(active: active!, onCommand: onCommand),
        Expanded(
          child: switch (pane) {
            WorkspacePane.changes =>
              status == null
                  ? MeridianEmptyState(
                      compact: true,
                      icon: 'changes',
                      title: context.l10n.workspaceLoadingRepository,
                    )
                  : ChangesPane(
                      active: active!,
                      onCommand: onCommand,
                      tabId: active!.id,
                      status: status,
                      selectedIdentity: active!.navigation.selectedIdentity,
                      shortcuts: shortcuts,
                      filePaneWidth: changesFilePaneWidth,
                      onFilePaneWidthChanged: onChangesFilePaneWidthChanged,
                    ),
            WorkspacePane.history => HistoryPane(
              powerToolsVisible: powerToolsVisible,
              onClosePowerTools: onClosePowerTools,
              onRevealPowerCommit: onRevealPowerCommit,
              state: history,
              sync: sync,
              headObjectId:
                  active!.session?.snapshot.status?.headObjectId ??
                  active!.session?.snapshot.identity?.headObjectId,
              selectedObjectId: active!.navigation.selectedIdentity,
              onCommand: onCommand,
              shortcuts: shortcuts,
            ),
          },
        ),
      ],
    );
  }
}

class ChangesPane extends StatefulWidget {
  const ChangesPane({
    required this.active,
    required this.onCommand,
    required this.tabId,
    required this.status,
    required this.selectedIdentity,
    required this.shortcuts,
    required this.filePaneWidth,
    required this.onFilePaneWidthChanged,
    super.key,
  });

  final RepositoryTabState active;
  final RunAppCommand onCommand;

  final int tabId;
  final RepositoryStatus status;
  final String? selectedIdentity;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final double filePaneWidth;
  final ValueChanged<double> onFilePaneWidthChanged;

  @override
  State<ChangesPane> createState() => ChangesPaneState();
}

class ChangesPaneState extends State<ChangesPane>
    implements ChangesInteraction {
  String? _discoveredFileBrowserName;
  final ScrollController _stagedScroll = ScrollController();
  final ScrollController _unstagedScroll = ScrollController();

  /// Narrows both file lists by path.
  final TextEditingController _filter = TextEditingController();
  GlobalKey<ChangesSectionState> _stagedSectionKey = GlobalKey();
  GlobalKey<ChangesSectionState> _unstagedSectionKey = GlobalKey();
  var _mutationSequence = 0;
  StagingSide? _mutationSource;
  Set<String> _movingKeys = const {};
  String? _flightKey;
  var _commitFailureVisible = false;
  late double _splitRatio;
  double? _commitEditorHeight;
  double? _naturalCommitEditorHeight;
  double _compactChangesFileHeight = 400;
  GlobalKey<CommitEditorState> _commitEditorKey =
      GlobalKey<CommitEditorState>();

  /// The window's Changes workflows; they own the selection, the focused
  /// list, staging, discarding and the conflict flow of every tab.
  ChangesService? _service;
  StreamSubscription<int>? _changesSubscription;
  StreamSubscription<ChangesEffect>? _effectsSubscription;
  StreamSubscription<WorkspaceEffect>? _flashSubscription;

  /// The last commit flash of this repository: the staged list empties as
  /// the commit leaves.
  int get _commitFlash {
    final effect = WorkspaceServicesScope.of(
      context,
    ).workflows.effects.latest(WorkspaceEffectKind.flashCommit);
    final flash = effect?.payload as CommittedFlash?;
    if (effect == null || flash == null) return 0;
    return flash.repository == widget.active.canonicalIdentity ? effect.id : 0;
  }

  ChangesService get _changes => _service!;
  WorkspaceServicesScope get _scope => WorkspaceServicesScope.read(context);
  RepositorySessionService get _repositories => _scope.repositories;
  SettingsService get _settings => _scope.settings;
  FileActionsScope get _files => FileActionsScope.of(context);
  WorkspaceEffects get _effects =>
      WorkspaceServicesScope.of(context).workflows.effects;
  int get _tabId => widget.tabId;
  ChangesSelection get _selection => _changes.selectionOf(_tabId);
  StagingSide get _focusedSide => _selection.focusedSide;
  bool get _busy => _changes.busy(_tabId);

  /// The file the diff shows: the navigation selection, or the highlighted row
  /// when that selection names no changed file. Re-entering Changes clears the
  /// navigation selection while the rows stay highlighted.
  String? get _detailIdentity =>
      _changes.detailIdentity(_tabId, widget.selectedIdentity);

  Set<AppCommandId> get disabledSelectionCommands =>
      _changes.disabledSelectionCommands(_tabId);

  @override
  bool get active => mounted;

  @override
  Future<bool> confirmDiscard(DiscardReview preview) => showMeridianConfirm(
    context,
    title: preview.kind == DiscardKind.clean
        ? context.l10n.cleanConfirmTitle
        : context.l10n.discardConfirmTitle,
    description: preview.mixed
        ? context.l10n.discardMixedConfirmMessage(
            preview.trackedFiles,
            preview.untrackedFiles,
          )
        : context.l10n.discardConfirmMessage(preview.fileCount),
    confirmLabel: preview.kind == DiscardKind.clean
        ? context.l10n.cleanConfirmAction
        : context.l10n.discardConfirmAction,
    cancelLabel: context.l10n.cancel,
    destructive: true,
  );

  @override
  void reportChanges(ChangesOutcome outcome) {
    if (!mounted) return;
    final details = switch (outcome) {
      StagingFinished(:final diagnostic, :final side) =>
        OperationFailureDetails(
          operation: side == StagingSide.staged
              ? UserOperationKind.unstage
              : UserOperationKind.stage,
          staging: diagnostic,
        ),
      StagingFailed(:final failure, :final side) => workflowFailureDetails(
        failure,
        operation: side == StagingSide.staged
            ? UserOperationKind.unstage
            : UserOperationKind.stage,
      ),
      DiscardFailed(:final failure) => workflowFailureDetails(
        failure,
        operation: UserOperationKind.discard,
      ),
      _ => const OperationFailureDetails(operation: UserOperationKind.discard),
    };
    showWorkflowMessage(
      context,
      changesOutcomeMessage(context, outcome),
      details: details,
    );
  }

  @override
  void initState() {
    super.initState();
    _splitRatio = _settings.current.appearance.changesSplitRatio / 1000.0;
    unawaited(_discoverFileBrowser());
    _filter.addListener(_filterChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paneCommands = PaneCommandContextScope.maybeOf(context);
    if (!identical(paneCommands, _paneCommands)) {
      _paneCommands
        ?..withdrawSelections(_disabledSelectionAnswer)
        ..withdrawHandler(PaneRole.changes, _handler);
      _paneCommands = paneCommands
        ?..registerSelections(_disabledSelectionAnswer)
        ..registerHandler(PaneRole.changes, _handler);
    }
    final service = WorkspaceServicesScope.of(context).workflows.changes;
    if (!identical(service, _service)) {
      _service = service;
      unawaited(_changesSubscription?.cancel());
      unawaited(_effectsSubscription?.cancel());
      _changesSubscription = service.changes.listen((tabId) {
        if (mounted && tabId == _tabId) setState(() {});
      });
      _effectsSubscription = service.effects.listen(_effect);
      unawaited(_flashSubscription?.cancel());
      _flashSubscription = WorkspaceServicesScope.of(context).workflows.effects
          .of(WorkspaceEffectKind.flashCommit)
          .listen((_) {
            if (mounted) setState(() {});
          });
      unawaited(service.probeConflicts(_tabId));
    }
  }

  /// Carries out what the Changes workflows ask of the lists on screen.
  void _effect(ChangesEffect effect) {
    if (!mounted || effect.tabId != _tabId) return;
    switch (effect) {
      case ChangesMoveStarted(:final side, :final keys, :final single):
        String? flightKey;
        if (single != null) {
          final source = side == StagingSide.staged
              ? _stagedSectionKey.currentState
              : _unstagedSectionKey.currentState;
          final destination = side == StagingSide.staged
              ? _unstagedSectionKey.currentState
              : _stagedSectionKey.currentState;
          if (destination?.willShowEntry(single) == true &&
              source?.captureEntry(single) == true) {
            flightKey = changeKey(single);
          }
        }
        setState(() {
          _mutationSequence++;
          _mutationSource = side;
          _movingKeys = keys;
          _flightKey = flightKey;
        });
      case ChangesMoveEnded(:final moved):
        if (moved) return;
        setState(() {
          _mutationSequence++;
          _movingKeys = const {};
          _flightKey = null;
        });
      case ChangesActionFailed(:final side, :final scope):
        (side == StagingSide.staged ? _stagedSectionKey : _unstagedSectionKey)
            .currentState
            ?.showActionFailure(scope);
      case DiffSelectionRequested():
        // The working-tree diff listens for these itself.
        break;
    }
  }

  /// A new filter keeps only the selected files it still shows, so actions
  /// on the selection never reach hidden files.
  void _filterChanged() {
    final query = _filter.text;
    _changes.retain(_tabId, {
      for (final entry in widget.status.entries)
        if (changesFilterMatches(entry, query)) changeKey(entry),
    });
  }

  Future<void> _discoverFileBrowser() async {
    try {
      final candidates = await _repositories.integrations.discover(
        IntegrationKind.fileManager,
      );
      if (mounted && candidates.isNotEmpty) {
        setState(
          () => _discoveredFileBrowserName = discoveredFileBrowser(
            candidates.first.id,
          ),
        );
      }
    } on Object {
      // The normal integration action reports availability when invoked.
    }
  }

  void _setFileMode(StagingSide side, GitFileListMode mode) {
    final value = mode.name;
    _settings.updateAppearance(
      (appearance) => side == StagingSide.unstaged
          ? appearance.copyWith(changesUnstagedMode: value)
          : appearance.copyWith(changesStagedMode: value),
    );
  }

  void _persistSplitRatio() {
    _settings.updateAppearance(
      (appearance) =>
          appearance.copyWith(changesSplitRatio: (_splitRatio * 1000).round()),
    );
  }

  /// The localized reason [id] is unavailable for the repository on another
  /// computer this pane shows, or null for a local repository.
  String? _remoteReason(AppCommandId id, {bool listen = false}) {
    final state = listen
        ? CommandAvailabilityScope.read(context)
        : CommandAvailabilityScope.peek(context);
    final reason = remoteCommandReason(id, state?.remote);
    return reason == null ? null : workspaceDisabledReason(context, reason);
  }

  /// Shows why [id] is unavailable remotely and reports whether it was.
  bool _refusedRemotely(AppCommandId id) {
    final reason = _remoteReason(id);
    if (reason == null) return false;
    StatusNotificationScope.show(context, reason);
    return true;
  }

  void runCommand(AppCommandId command) {
    final action = switch (command) {
      AppCommandId.commitCreate =>
        () => _commitEditorKey.currentState?.submit(),
      AppCommandId.commitAmend =>
        () => _commitEditorKey.currentState?.prepareAmend(),
      AppCommandId.stageToggle => _stageToggleUnlessEditing,
      AppCommandId.stageSelection => () => _changes.stageSelection(
        this,
        _tabId,
        StagingSide.unstaged,
      ),
      AppCommandId.unstageSelection => () => _changes.stageSelection(
        this,
        _tabId,
        StagingSide.staged,
      ),
      AppCommandId.discardChanges => () => _changes.discardSelection(
        this,
        _tabId,
      ),
      _ => () => _effects.emit(
        WorkspaceEffectKind.conflictCommand,
        command,
        false,
      ),
    };
    action();
  }

  void _stageToggleUnlessEditing() {
    if (textInputHasFocus()) return;
    _changes.toggleFocused(this, _tabId);
  }

  @override
  void didUpdateWidget(covariant ChangesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId) {
      _stagedSectionKey = GlobalKey();
      _unstagedSectionKey = GlobalKey();
      _commitEditorKey = GlobalKey<CommitEditorState>();
      unawaited(_changes.probeConflicts(widget.tabId));
    } else if (hasActiveConflicts(oldWidget.status) &&
        !hasActiveConflicts(widget.status)) {
      unawaited(_changes.probeConflicts(widget.tabId));
    }
  }

  PaneCommandContext? _paneCommands;

  late final PaneCommandHandler _handler = PaneCommandHandler(
    run: runCommand,
    showPatchWorkflow: ({required bool apply}) => showPatchWorkflow(
      initialMode: apply ? PatchDialogMode.apply : PatchDialogMode.create,
    ),
  );

  Set<AppCommandId> _disabledSelectionAnswer() => disabledSelectionCommands;

  @override
  void dispose() {
    _paneCommands
      ?..withdrawSelections(_disabledSelectionAnswer)
      ..withdrawHandler(PaneRole.changes, _handler);
    unawaited(_changesSubscription?.cancel());
    unawaited(_effectsSubscription?.cancel());
    unawaited(_flashSubscription?.cancel());
    _stagedScroll.dispose();
    _unstagedScroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _stage(
    StagingSide side,
    StagingScope scope,
    List<RepositoryStatusEntry> entries, {
    DiffPage? accepted,
    List<String> rowIds = const [],
  }) => _changes.stage(
    this,
    _tabId,
    side,
    scope,
    entries,
    accepted: accepted,
    rowIds: rowIds,
    shownDetail: _detailIdentity,
  );

  Future<void> _discard(
    List<RepositoryStatusEntry> entries, {
    DiffPage? accepted,
    List<String> rowIds = const [],
  }) => _changes.discard(
    this,
    _tabId,
    entries,
    accepted: accepted,
    rowIds: rowIds,
  );

  /// Offers the `.gitignore` entry that matches exactly [path] and adds the
  /// entry the person confirms.
  Future<void> _ignore(
    List<int> path, {
    required bool directory,
    required bool tracked,
  }) async {
    final reason = remoteWriteReason(
      context,
      RemoteCapability.extensions,
      listen: false,
    );
    if (reason != null) {
      StatusNotificationScope.show(context, reason);
      return;
    }
    final extensions = _repositories.extensions;
    await showIgnoreDialog(
      context,
      suggestion:
          extensions.exactIgnorePattern(path, directory: directory) ?? '',
      directory: directory,
      tracked: tracked,
      onAdd: (pattern) => extensions.execute(
        RepositoryExtensionMutationRequest(
          kind: RepositoryExtensionMutationKind.ignoreAdd,
          pattern: pattern,
        ),
      ),
    );
  }

  Future<void> _partial(StagingSide side, RepositoryStatusEntry entry) async {
    _changes.focus(_tabId, side);
    final (oldPath, newPath) = diffPaths(entry, side);
    final discardReason = _remoteReason(AppCommandId.discardChanges);
    final patchReason = _remoteReason(AppCommandId.createPatch);
    final stageReason = _remoteReason(AppCommandId.stageSelection);
    final choice = await showMeridianDialog<Object>(
      context: context,
      builder: (context) => WorkingDiffSelectionDialog(
        side: side,
        oldPath: oldPath,
        newPath: newPath,
        repositories: _repositories,
        allowDiscard: discardReason == null && canDiscardLines(entry, side),
        allowPatch: patchReason == null,
        stageDisabledReason: stageReason,
      ),
    );
    if (choice == null || !mounted) return;
    if (choice is PartialStagingChoice) {
      await _stage(
        side,
        StagingScope.rows,
        [entry],
        accepted: choice.page,
        rowIds: choice.rowIds,
      );
    } else if (choice is PartialDiscardChoice) {
      await _discard([entry], accepted: choice.page, rowIds: choice.rowIds);
    } else if (choice is PartialPatchChoice) {
      await showPatchWorkflow(accepted: choice.page, rowIds: choice.rowIds);
    }
  }

  Future<void> _showPatchDialog(
    PatchRequestFactory request, {
    PatchDialogMode? initialMode,
  }) => showPatchDialog(
    context,
    repositories: _repositories,
    repositoryLabel: context.l10n.patchCurrentRepository,
    onShowInFolder: _files.revealInFileBrowser,
    applyUnavailableReason: _remoteReason(AppCommandId.applyPatch),
    initialMode: initialMode,
    request: request,
  );

  Future<void> showPatchWorkflow({
    DiffPage? accepted,
    List<String> rowIds = const [],
    PatchDialogMode? initialMode,
  }) async {
    if (_refusedRemotely(
      initialMode == PatchDialogMode.apply
          ? AppCommandId.applyPatch
          : AppCommandId.createPatch,
    )) {
      return;
    }
    final selection = _changes.patchSelection(_tabId);
    await _showPatchDialog(
      PatchRequestBuilder.workingTree(
        side: selection.side,
        paths: uniqueCommandPaths(selection.entries),
        accepted: accepted,
        rowIds: rowIds,
      ),
      initialMode: initialMode,
    );
  }

  Future<void> _createPatchForEntries(
    StagingSide side,
    List<RepositoryStatusEntry> entries,
  ) async {
    if (_refusedRemotely(AppCommandId.createPatch)) return;
    await _showPatchDialog(
      PatchRequestBuilder.files(side, uniqueCommandPaths(entries)),
      initialMode: PatchDialogMode.create,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stageReason = _remoteReason(
      AppCommandId.stageSelection,
      listen: true,
    );
    final discardReason = _remoteReason(AppCommandId.discardChanges);
    final patchReason = _remoteReason(AppCommandId.createPatch);
    final externalReason = _remoteReason(AppCommandId.openInEditor);
    final ignoreReason = remoteWriteReason(
      context,
      RemoteCapability.extensions,
    );
    // A repository on another computer resolves conflicts when its host
    // allows history changes; otherwise its conflicted files stay in the
    // lists.
    if (_changes.conflictFlow(_tabId) &&
        _remoteReason(AppCommandId.conflictTakeCurrent) == null) {
      final root = widget.active.canonicalIdentity;
      final diffView = DiffViewPreferencesScope.maybeOf(context);
      return ConflictResolver(
        // A new tab gets a new resolver; its session keeps the drafts.
        key: ValueKey(_tabId),
        shortcuts: widget.shortcuts,
        wrap: diffView?.preferences.wrap,
        onWrapChanged: switch (diffView) {
          final scope? => (wrap) => scope.onChanged(
            scope.preferences.copyWith(wrap: wrap),
          ),
          null => null,
        },
        fileBrowserName:
            configuredFileBrowserName(_settings) ??
            _discoveredFileBrowserName ??
            platformFileBrowserName(),
        onOpenWorkingFile: root == null || externalReason != null
            ? null
            : (path, {required reveal}) {
                final relative = relativeNativePath(root, path);
                reveal
                    ? _files.revealInFileBrowser(relative)
                    : _files.openExternal(relative);
              },
        onInspect: _files.inspectWorkingFile,
        inspectionUnavailableReason: widget.status.headObjectId == null
            ? context.l10n.fileActionNoCommit
            : null,
        banner: RepositoryConditions(
          active: widget.active,
          onCommand: widget.onCommand,
          onSkip: () => _effects.emit(
            WorkspaceEffectKind.conflictCommand,
            ConflictSequencerAction.skip,
            false,
          ),
        ),
        onFinished: () {
          final conflicts = WorkspaceServicesScope.of(
            context,
          ).workflows.conflicts;
          if (conflicts.active case final session?) conflicts.finish(session);
          _changes.finishConflictFlow(_tabId);
        },
      );
    }
    final staged = widget.status.entries
        .where((entry) => entry.staged)
        .toList();
    final unstaged = widget.status.entries
        .where((entry) => entry.unstaged)
        .toList();
    final query = _filter.text;
    final filtering = query.trim().isNotEmpty;
    // The lists show what the filter lets through; the composer still
    // commits everything staged.
    final shownStaged = filtering
        ? staged.where((entry) => changesFilterMatches(entry, query)).toList()
        : staged;
    final shownUnstaged = filtering
        ? unstaged.where((entry) => changesFilterMatches(entry, query)).toList()
        : unstaged;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumEditorHeight =
            140.0 +
            48.0 * math.max(0.0, MediaQuery.textScalerOf(context).scale(1) - 1);
        final maximumEditorHeight = math.max(
          minimumEditorHeight,
          constraints.maxHeight - 120 - MeridianSpace.space3,
        );
        // Until the user resizes it, the composer takes its natural height so
        // the default layout never needs a scrollbar.
        // Handlers read the laid-out size; build uses the last measurement.
        double editorHeight({bool measure = false}) =>
            (_commitEditorHeight ??
                    (measure
                        ? _commitEditorKey.currentContext?.size?.height
                        : _naturalCommitEditorHeight) ??
                    minimumEditorHeight)
                .clamp(minimumEditorHeight, maximumEditorHeight)
                .toDouble();
        if (_commitEditorHeight == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final height = _commitEditorKey.currentContext?.size?.height;
            if (!mounted || height == null) return;
            if (height == _naturalCommitEditorHeight) return;
            setState(() => _naturalCommitEditorHeight = height);
          });
        }
        void resizeEditor(double height) => setState(() {
          _commitEditorHeight = height
              .clamp(minimumEditorHeight, maximumEditorHeight)
              .toDouble();
        });
        final appearance = _settings.current.appearance;
        final stagedSection = ChangesSection(
          key: _stagedSectionKey,
          mutationSequence: _mutationSequence,
          mutationSource: _mutationSource,
          movingKeys: _movingKeys,
          flightKey: _flightKey,
          commitSequence: _commitFlash,
          title: context.l10n.changesStaged,
          side: StagingSide.staged,
          stacked: true,
          mode: GitFileListMode.values.byName(appearance.changesStagedMode),
          onModeChanged: (mode) => _setFileMode(StagingSide.staged, mode),
          entries: shownStaged,
          totalEntries: filtering ? staged.length : null,
          controller: _stagedScroll,
          selected: _selection.staged,
          busy: _busy,
          canQueueStage: _changes.canStageFiles(_tabId),
          allowSelectionWhileBusy: _changes.stagingPhase(_tabId) != null,
          pendingKeys: _changes.pendingKeys(_tabId, StagingSide.staged),
          onSelectIdentity: _scope.workflows.navigator.selectIdentity,
          onSelectionChanged: (selection) =>
              _changes.select(_tabId, StagingSide.staged, selection),
          onSelected: () => _stage(
            StagingSide.staged,
            StagingScope.files,
            shownStaged
                .where((entry) => _selection.staged.contains(changeKey(entry)))
                .toList(),
          ),
          onAll: () => filtering
              ? _stage(StagingSide.staged, StagingScope.files, shownStaged)
              : _stage(StagingSide.staged, StagingScope.all, staged),
          onFiles: (entries) =>
              _stage(StagingSide.staged, StagingScope.files, entries),
          onPartial: (entry) => _partial(StagingSide.staged, entry),
          onCreatePatch: (entries) =>
              unawaited(_createPatchForEntries(StagingSide.staged, entries)),
          inspectionUnavailableReason: widget.status.headObjectId == null
              ? context.l10n.fileActionNoCommit
              : null,
          fileBrowserName:
              configuredFileBrowserName(_settings) ??
              _discoveredFileBrowserName ??
              platformFileBrowserName(),
          onDropFiles: (entries) =>
              _stage(StagingSide.unstaged, StagingScope.files, entries),
          onDiscardSelected: null,
          onDiscardFiles: null,
          onDiscardAll: null,
          stageDisabledReason: stageReason,
          patchDisabledReason: patchReason,
          externalDisabledReason: externalReason,
        );
        final unstagedSection = ChangesSection(
          key: _unstagedSectionKey,
          mutationSequence: _mutationSequence,
          mutationSource: _mutationSource,
          movingKeys: _movingKeys,
          flightKey: _flightKey,
          title: context.l10n.changesUnstaged,
          side: StagingSide.unstaged,
          stacked: true,
          mode: GitFileListMode.values.byName(appearance.changesUnstagedMode),
          onModeChanged: (mode) => _setFileMode(StagingSide.unstaged, mode),
          entries: shownUnstaged,
          totalEntries: filtering ? unstaged.length : null,
          controller: _unstagedScroll,
          selected: _selection.unstaged,
          busy: _busy,
          canQueueStage: _changes.canStageFiles(_tabId),
          allowSelectionWhileBusy: _changes.stagingPhase(_tabId) != null,
          pendingKeys: _changes.pendingKeys(_tabId, StagingSide.unstaged),
          onSelectIdentity: _scope.workflows.navigator.selectIdentity,
          onSelectionChanged: (selection) =>
              _changes.select(_tabId, StagingSide.unstaged, selection),
          onSelected: () => _stage(
            StagingSide.unstaged,
            StagingScope.files,
            shownUnstaged
                .where(
                  (entry) => _selection.unstaged.contains(changeKey(entry)),
                )
                .toList(),
          ),
          onAll: () => filtering
              ? _stage(StagingSide.unstaged, StagingScope.files, shownUnstaged)
              : _stage(StagingSide.unstaged, StagingScope.all, unstaged),
          onFiles: (entries) =>
              _stage(StagingSide.unstaged, StagingScope.files, entries),
          onPartial: (entry) => _partial(StagingSide.unstaged, entry),
          onCreatePatch: (entries) =>
              unawaited(_createPatchForEntries(StagingSide.unstaged, entries)),
          inspectionUnavailableReason: widget.status.headObjectId == null
              ? context.l10n.fileActionNoCommit
              : null,
          fileBrowserName:
              configuredFileBrowserName(_settings) ??
              _discoveredFileBrowserName ??
              platformFileBrowserName(),
          onDropFiles: (entries) =>
              _stage(StagingSide.staged, StagingScope.files, entries),
          onDiscardSelected: discardReason != null
              ? null
              : () => unawaited(
                  _discard(
                    shownUnstaged
                        .where(
                          (entry) =>
                              _selection.unstaged.contains(changeKey(entry)),
                        )
                        .toList(),
                  ),
                ),
          onDiscardFiles: discardReason != null
              ? null
              : (entries) => unawaited(_discard(entries)),
          onDiscardAll: discardReason != null
              ? null
              : () => unawaited(_discard(shownUnstaged)),
          onIgnore: ignoreReason != null
              ? null
              : (path, {required directory, required tracked}) => unawaited(
                  _ignore(path, directory: directory, tracked: tracked),
                ),
          stageDisabledReason: stageReason,
          patchDisabledReason: patchReason,
          externalDisabledReason: externalReason,
          discardDisabledReason: discardReason,
          ignoreDisabledReason: ignoreReason,
        );
        final files = MeridianSplitPane(
          axis: Axis.vertical,
          ratio: _splitRatio,
          onRatioChanged: (ratio) => setState(
            () => _splitRatio = ratio.clamp(
              GitLamaLayout.changesSplitRatioMin,
              GitLamaLayout.changesSplitRatioMax,
            ),
          ),
          onRatioChangeEnd: (_) => _persistSplitRatio(),
          keyboardStep: GitLamaLayout.paneResizeStep,
          focusable: false,
          semanticLabel: context.l10n.changesResizePanes,
          handleKey: const ValueKey('changes-pane-splitter'),
          first: unstagedSection,
          second: stagedSection,
        );
        final stageShortcut = widget.shortcuts[AppCommandId.stageToggle];
        final maximumFilePaneWidth = math.max(
          GitLamaLayout.codePaneMinWidth,
          constraints.maxWidth -
              GitLamaLayout.changesDiffMinWidth -
              MeridianSpace.space3,
        );
        final minimumFilePaneWidth = math.min(
          GitLamaLayout.changesFilePaneMinWidth,
          maximumFilePaneWidth,
        );
        final filePaneWidth = widget.filePaneWidth
            .clamp(minimumFilePaneWidth, maximumFilePaneWidth)
            .toDouble();
        final compactChanges = MediaQuery.sizeOf(context).width < 1100;
        final compactFileHeight = _compactChangesFileHeight
            .clamp(560.0, 850.0)
            .toDouble();
        final compactDetailHeight = math.max(
          400.0,
          constraints.maxHeight - compactFileHeight - MeridianSpace.space3,
        );
        final fileRegion = MeridianIsland(
          expandChild: true,
          child: Column(
            children: [
              RepositoryConditions(
                active: widget.active,
                onCommand: widget.onCommand,
                onSkip: () => _effects.emit(
                  WorkspaceEffectKind.conflictCommand,
                  ConflictSequencerAction.skip,
                  false,
                ),
              ),
              if (_changes.stoppedStages(_tabId) > 0)
                MeridianBanner(
                  tone: MeridianBannerTone.warning,
                  message: context.l10n.stagingQueueStopped(
                    _changes.stoppedStages(_tabId),
                  ),
                  onDismiss: () => _changes.dismissStoppedStages(_tabId),
                  dismissLabel: context.l10n.close,
                ),
              if (_changes.stagingPhase(_tabId) case final phase?)
                MeridianBanner(
                  key: const ValueKey('staging-progress'),
                  tone: MeridianBannerTone.info,
                  message:
                      '${switch (phase) {
                        StagingPhase.idle || StagingPhase.waiting => context.l10n.stagingWaiting,
                        StagingPhase.preparing => context.l10n.stagingPreparing,
                        StagingPhase.updating => context.l10n.stagingUpdating,
                        StagingPhase.refreshing => context.l10n.stagingRefreshing,
                      }} ${context.l10n.stagingQueueCount(_changes.pendingStages(_tabId))}',
                  actions: [
                    if (_changes.pendingStages(_tabId) > 0)
                      MeridianButton(
                        label: context.l10n.stagingClearQueue,
                        variant: MeridianButtonVariant.quiet,
                        size: MeridianControlSize.small,
                        onPressed: () => _changes.clearPendingStages(_tabId),
                      ),
                  ],
                ),
              _ChangesFilterBar(
                controller: _filter,
                shown: shownStaged.length + shownUnstaged.length,
                total: staged.length + unstaged.length,
              ),
              Expanded(child: files),
              paneSplitter(
                context,
                key: const ValueKey('changes-commit-splitter'),
                axis: Axis.horizontal,
                label: context.l10n.changesResizeCommit,
                value: editorHeight(),
                onDrag: (delta) =>
                    resizeEditor(editorHeight(measure: true) - delta),
                onIncrease: () =>
                    resizeEditor(editorHeight(measure: true) + 32),
                onDecrease: () =>
                    resizeEditor(editorHeight(measure: true) - 32),
                // Back to the composer's own height.
                onReset: () => setState(() => _commitEditorHeight = null),
              ),
              ConstrainedBox(
                key: const ValueKey('changes-commit-editor'),
                constraints: _commitEditorHeight == null
                    ? BoxConstraints(
                        minHeight: minimumEditorHeight,
                        maxHeight: maximumEditorHeight,
                      )
                    : BoxConstraints.tightFor(height: editorHeight()),
                child: CommitEditor(
                  key: _commitEditorKey,
                  repositories: _repositories,
                  hosting: HostingScope.of(context).hosting,
                  hostingResources: HostingScope.of(context).resources,
                  hostingResourcesStale: HostingScope.of(context).stale,
                  shortcut: widget.shortcuts[AppCommandId.commitCreate],
                  branchName: widget.status.branchName,
                  headObjectId: widget.status.headObjectId,
                  stagedCount: staged.length,
                  onFailureVisibilityChanged: (visible) {
                    if (_commitFailureVisible == visible) return;
                    setState(() => _commitFailureVisible = visible);
                  },
                  onPush: () => widget.onCommand(AppCommandId.push),
                  fill: _commitEditorHeight != null,
                  suggestionPaths: uniqueCommandPaths(
                    staged
                        .where(
                          (entry) =>
                              _selection.staged.isEmpty ||
                              _selection.staged.contains(changeKey(entry)),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ],
          ),
        );
        final detailRegion = MeridianIsland(
          expandChild: true,
          child: WorkingTreeDetailPane(
            tabId: _tabId,
            status: widget.status,
            selectedIdentity: _detailIdentity,
            repositories: _repositories,
            side: _focusedSide,
            busy: _busy,
            onStage: (entry, page, rows) => _stage(
              _focusedSide,
              StagingScope.rows,
              [entry],
              accepted: page,
              rowIds: rows,
            ),
            onDiscard: (entry, page, rows) =>
                _discard([entry], accepted: page, rowIds: rows),
            onCreatePatch: (entry) =>
                unawaited(_createPatchForEntries(_focusedSide, [entry])),
            allowDiscard: discardReason == null,
            stageDisabledReason: stageReason,
            patchDisabledReason: patchReason,
          ),
        );
        return CallbackShortcuts(
          bindings: {
            if (stageShortcut != null)
              TextAwareShortcutActivator(
                stageShortcut.activator,
                textInputHasFocus,
              ): () => runAvailableCommand(
                context,
                AppCommandId.stageToggle,
                _stageToggleUnlessEditing,
              ),
          },
          child: Focus(
            autofocus: true,
            child: compactChanges
                ? SingleChildScrollView(
                    key: const PageStorageKey('changes-compact-scroll'),
                    child: Column(
                      children: [
                        SizedBox(
                          key: const ValueKey('changes-file-column'),
                          height: compactFileHeight,
                          child: fileRegion,
                        ),
                        paneSplitter(
                          context,
                          key: const ValueKey('changes-workspace-splitter'),
                          axis: Axis.horizontal,
                          label: context.l10n.workspaceResizeDetail,
                          value: compactFileHeight,
                          onDrag: (delta) => setState(
                            () => _compactChangesFileHeight =
                                compactFileHeight + delta,
                          ),
                          onIncrease: () => setState(
                            () => _compactChangesFileHeight =
                                compactFileHeight + 32,
                          ),
                          onDecrease: () => setState(
                            () => _compactChangesFileHeight =
                                compactFileHeight - 32,
                          ),
                        ),
                        SizedBox(
                          key: const ValueKey('changes-detail-column'),
                          height: compactDetailHeight,
                          child: detailRegion,
                        ),
                      ],
                    ),
                  )
                // The pane clamps the width itself; the split pane adds no
                // minimums of its own.
                : MeridianSplitPane(
                    extent: filePaneWidth,
                    onExtentChanged: widget.onFilePaneWidthChanged,
                    firstMinExtent: 0,
                    secondMinExtent: 0,
                    keyboardStep: GitLamaLayout.paneResizeStep,
                    focusable: false,
                    semanticLabel: context.l10n.workspaceResizeDetail,
                    handleKey: const ValueKey('changes-workspace-splitter'),
                    first: KeyedSubtree(
                      key: const ValueKey('changes-file-column'),
                      child: fileRegion,
                    ),
                    second: KeyedSubtree(
                      key: const ValueKey('changes-detail-column'),
                      child: detailRegion,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// The field that narrows the Unstaged and Staged lists by path, with how
/// many files it shows. Escape clears it.
class _ChangesFilterBar extends StatelessWidget {
  const _ChangesFilterBar({
    required this.controller,
    required this.shown,
    required this.total,
  });

  final TextEditingController controller;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final active = controller.text.trim().isNotEmpty;
    return MeridianSectionHeader(
      color: colors.pane,
      middle: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): controller.clear,
        },
        child: Semantics(
          label: l10n.changesFilterLabel,
          child: MeridianTextField(
            key: const ValueKey('changes-filter'),
            controller: controller,
            variant: MeridianTextFieldVariant.search,
            size: MeridianControlSize.small,
            width: 0,
            placeholder: l10n.changesFilterPlaceholder,
            clearLabel: l10n.changesFilterClear,
            trailingText: active ? l10n.changesFilterCount(shown, total) : null,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
      ),
    );
  }
}
