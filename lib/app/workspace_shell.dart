import 'workspace/diff_view_preferences.dart';
import 'workspace/command_availability.dart';
import '../widgets/status_notification.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import '../models/app_update.dart';
import '../models/cli_forwarding.dart';
import '../models/app_command.dart';
import '../models/app_shortcut.dart';
import '../models/history.dart';
import '../models/history_graph.dart';
import '../models/history_mutation.dart';
import '../models/hosting.dart';
import '../models/integrations.dart';
import '../models/operation_center.dart';
import '../models/patch.dart';
import '../models/repository_state.dart';
import '../models/ref_mutation.dart';
import '../models/remote_command_policy.dart';
import '../models/settings.dart';
import '../models/stash.dart';
import '../models/transfer.dart';
import '../models/workspace.dart';
import 'app_shortcut_activator.dart';
import '../services/operation_center_service.dart';
import '../services/repository_appearance_service.dart';
import '../services/app_update_service.dart';
import '../services/remote_workspace_service.dart';
import '../services/repository_session_service.dart';
import '../services/settings_service.dart';
import '../services/hosting_connection_service.dart';
import '../services/hosting_review_service.dart';
import '../services/inspection_window_service.dart';
import '../services/hosting_repository_session.dart';
import 'workspace/shell_chrome.dart';
import 'workspace/sidebar.dart';
import 'workspace/hosting_links.dart';
import 'inspector/inspector_actions.dart';
import 'file_actions/file_actions.dart';
import '../models/inspector.dart';
import '../services/inspector_reveal_service.dart';
import '../models/inspection.dart';
import '../services/inspector/inspector_service.dart';
import '../services/inspector/lens_availability.dart';
import 'workspace/activity.dart';
import 'workspace/named_snapshots.dart';
import 'workspace/power_tools.dart';
import 'workspace/integrations_panel.dart';
import 'workspace/repository_extensions.dart';
import 'workspace/logbook.dart';
import 'workspace/status_bar.dart';
import 'workspace/patch_dialog.dart';
import 'workspace/commit_archive_dialog.dart';
import 'workspace/command_palette.dart';
import 'workspace/repository_details.dart';
import 'workspace/settings_dialog.dart';
import 'workspace/labels.dart';
import 'workspace/reference_projection.dart';
import 'workspace/remote_operations.dart';
import 'workspace/remote_workspace.dart';
import 'workspace/workspace_interaction.dart';
import 'workspace/workspace_scope.dart';
import '../models/git_names.dart';
import 'app_runtime.dart';
import 'workspace/shell_scopes.dart';
import 'host_platform.dart';
import '../services/workflows/patch_request_builder.dart';
import '../services/workflows/sync_change_tracker.dart';
import '../services/workflows/transfer_workflows.dart';
import '../services/workflows/window_workflows.dart';
import '../services/workflows/workspace_effects.dart';

import 'package:meridian_ui/meridian_ui.dart';

import 'gitlama_layout.dart';

part 'workspace/shell_commands.dart';
part 'workspace/shell_hosting.dart';

double floatingPanelBodyHeight(BuildContext context, double preferred) =>
    math.min(
      preferred,
      math.max(
        0,
        MediaQuery.sizeOf(context).height -
            MeridianSize.toolbar -
            MeridianLayout.tabStripHeight -
            MeridianLayout.floatingPanelHeaderHeight -
            MeridianLayout.statusBarHeight -
            MeridianSpace.space4,
      ),
    );

/// The floating panels over the workspace, of which one shows at a time.
enum ShellPanel { operations, snapshots, extensions, integrations, powerTools }

/// Floating tool panels hang `space-2` below the repository tab strip
/// (plan decision 2.7), and below the worktree row while it shows.
double _floatingPanelTopFor(WorkspaceState workspace) =>
    MeridianSize.toolbar +
    MeridianLayout.tabStripHeight *
        (workspace.activeWorktrees.isEmpty ? 1 : 2) +
    MeridianSpace.space2;

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    required this.runtime,
    required this.workspace,
    this.remoteController,
    this.workflows,
    required this.onOpenRepository,
    required this.onCloneRepository,
    required this.onInitializeRepository,
    super.key,
    this.notice,
  });

  /// The window's initialized services.
  final AppRuntime runtime;
  final WorkspaceState workspace;

  /// The window's remote workflows; the shell creates its own without one.
  final RemoteWorkspaceController? remoteController;

  /// The window's workflows; the shell creates its own without them.
  final WindowWorkflows? workflows;
  final VoidCallback onOpenRepository;
  final VoidCallback onCloneRepository;
  final VoidCallback onInitializeRepository;
  final Widget? notice;

  RepositorySessionService get repositories => runtime.repositorySessions;
  OperationCenterService get operationCenter => runtime.operationCenter;
  InspectionWindowService get inspectionWindows => runtime.inspectionWindows;

  /// Serves inspector windows that reveal commits in this window.
  InspectorRevealService get inspectorReveal => runtime.inspectorReveal;
  SettingsService get settings => runtime.settings;
  RepositoryAppearanceService get appearances => runtime.repositoryAppearances;
  HostingConnectionService get hosting => runtime.hosting;
  HostingReviewService get hostingReview => runtime.hostingReview;
  AppUpdateService get updates => runtime.updates;
  RemoteWorkspaceService get remoteWorkspaces => runtime.remoteWorkspaces;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  /// The Refresh icon spins while a refresh runs (NM-11).
  var _refreshSpinning = false;
  var _refreshRun = 0;
  Timer? _refreshSpin;
  bool _activityVisible = false;
  BigInt? _activitySelectionId;

  /// The floating panel shown over the workspace; one at a time.
  ShellPanel? _panel;
  bool _operationsMounted = false;
  bool _extensionsFocusLfs = false;
  bool _integrationsFocusAdd = false;
  double? _compactDetailHeight;
  double _commitFileListWidth = 280;
  late OperationCenterSnapshot _operations;
  StreamSubscription<OperationCenterSnapshot>? _operationSubscription;
  StreamSubscription<void>? _operationPollSubscription;
  StreamSubscription<HistoryState>? _historySubscription;
  StreamSubscription<SettingsDocument>? _settingsSubscription;
  late HistoryState _history;
  StreamSubscription<InspectorState>? _inspectorSubscription;
  StreamSubscription<String>? _reconnectedSubscription;
  late InspectorState _inspector;

  /// The History inspector fills the workspace column.
  bool _inspectorMaximized = false;

  /// The History inspector hides its file list.
  final ValueNotifier<bool> _inspectorFilesHidden = ValueNotifier(false);
  late SyncChange _sync;
  StreamSubscription<SyncChange>? _syncSubscription;
  StreamSubscription<void>? _busySubscription;
  StreamSubscription<void>? _transferSubscription;
  StreamSubscription<CliForwardedCommand>? _forwardedSubscription;
  final GlobalKey _compassKey = GlobalKey();
  final GlobalKey _paletteButtonKey = GlobalKey();
  bool _paletteOpen = false;
  bool _detailsOpen = false;

  /// Fires after each shell frame while the details overlay is open, so it
  /// follows the repository's status and running work.
  final ValueNotifier<int> _detailsRevision = ValueNotifier(0);

  Rect? _compassRect() => _globalRect(_compassKey);

  Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  final GlobalKey _shellStackKey = GlobalKey();
  double _logbookEnd = MeridianSpace.space3;

  void _measureCompass() {
    final box = _compassKey.currentContext?.findRenderObject();
    final shell = _shellStackKey.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        shell is! RenderBox ||
        !shell.hasSize ||
        !mounted) {
      return;
    }
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    final shellRight = shell.localToGlobal(Offset(shell.size.width, 0)).dx;
    final end = math.max(MeridianSpace.space3, shellRight - right);
    if ((_logbookEnd - end).abs() > 0.5) {
      setState(() => _logbookEnd = end);
    }
  }

  Map<String, HostingCheckState> _hostingBranchDecorations = const {};
  HostingBindingResolution? _hostingBinding;
  HostingResources _hostingResources = const HostingResources();
  bool _hostingResourcesStale = false;
  NativePathIdentity? _hostingResourcesRepository;
  late final HostingRepositorySession _hostingSession;
  StreamSubscription<void>? _hostingSessionSubscription;

  /// A controller the shell created because none was given; it disposes it.
  RemoteWorkspaceController? _ownRemote;

  RemoteWorkspaceController get _remote =>
      widget.remoteController ??
      (_ownRemote ??= RemoteWorkspaceController(
        service: widget.remoteWorkspaces,
        repositories: widget.repositories,
      ));

  /// Workflows the shell created because none were given; it disposes them.
  WindowWorkflows? _ownWorkflows;

  WindowWorkflows get _workflows =>
      widget.workflows ??
      (_ownWorkflows ??= WindowWorkflows(
        repositories: widget.repositories,
        operationCenter: widget.operationCenter,
        remote: _remote.workflows,
        platform: hostPlatform(),
        inspectorReveal: widget.inspectorReveal,
      ));

  /// Answers the workflows for an action started from this shell.
  WorkspaceInteraction get _interaction => WorkspaceInteraction(
    context,
    repositories: widget.repositories,
    settings: widget.settings,
  );

  void _listenWorkflows() {
    unawaited(_syncSubscription?.cancel());
    unawaited(_busySubscription?.cancel());
    unawaited(_transferSubscription?.cancel());
    unawaited(_forwardedSubscription?.cancel());
    final workflows = _workflows;
    _forwardedSubscription = workflows.entry.forwardedCommands.listen(
      _forwarded,
    );
    _sync = workflows.sync.current;
    _syncSubscription = workflows.sync.changes.listen((change) {
      if (mounted) setState(() => _sync = change);
    });
    _busySubscription = workflows.busy.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // The operation center offers Cancel while a transfer runs.
    _transferSubscription = workflows.transfers.runningChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Tells when a host whose connection was lost is connected again; a tab
  /// in the background never takes focus for it.
  void _listenReconnected() {
    unawaited(_reconnectedSubscription?.cancel());
    _reconnectedSubscription = widget.repositories.remoteReconnect.reconnected
        .listen((profileId) {
          final label = widget.remoteWorkspaces.profile(profileId)?.label;
          if (!mounted || label == null) return;
          StatusNotificationScope.show(
            context,
            context.l10n.remoteReconnected(label),
          );
        });
  }

  /// What the active tab may do on another computer; null for a local tab.
  RemoteTabAccess? get _activeRemote => _remote.accessFor(_active);

  /// Why [id] is unavailable for the active remote tab, or null.
  String? _remoteReasonText(AppCommandId id) =>
      switch (remoteCommandReason(id, _activeRemote)) {
        final reason? => workspaceDisabledReason(context, reason),
        null => null,
      };

  /// Refuses [id] for the active remote tab with its localized reason.
  bool _refusedRemotely(AppCommandId id) {
    final reason = remoteCommandReason(id, _activeRemote);
    if (reason == null) return false;
    StatusNotificationScope.show(
      context,
      workspaceDisabledReason(context, reason),
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _listenReconnected();
    _listenWorkflows();
    _hostingSession = widget.hosting.openRepositorySession();
    _hostingSessionSubscription = _hostingSession.changes.listen(
      (_) => _hostingSessionChanged(),
    );
    _updateHostingSession();
    _operations = widget.operationCenter.current;
    _history = widget.repositories.history.current;
    _inspector = widget.repositories.inspector.current;
    _inspectorSubscription = widget.repositories.inspector.states.listen((
      state,
    ) {
      if (mounted) setState(() => _inspector = state);
    });
    _operationSubscription = widget.operationCenter.states.listen((snapshot) {
      if (mounted) setState(() => _operations = snapshot);
    });
    _operationPollSubscription = widget.operationCenter.polls.listen((_) {
      if (mounted) _paneCommands.handler(PaneRole.activity)?.refresh?.call();
    });
    _historySubscription = widget.repositories.history.states.listen((state) {
      if (mounted) setState(() => _history = state);
    });
    _settingsSubscription = widget.settings.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteWorkspaces != widget.remoteWorkspaces ||
        oldWidget.repositories != widget.repositories ||
        oldWidget.remoteController != widget.remoteController) {
      unawaited(_ownRemote?.dispose());
      _ownRemote = null;
    }
    if (oldWidget.repositories != widget.repositories) _listenReconnected();
    if (oldWidget.workflows != widget.workflows ||
        oldWidget.repositories != widget.repositories) {
      final own = _ownWorkflows;
      _ownWorkflows = null;
      _listenWorkflows();
      unawaited(own?.dispose());
    }
    final activeRepository = _active?.canonicalIdentity;
    if (_hostingResourcesRepository != null &&
        _hostingResourcesRepository != activeRepository) {
      _hostingResourcesRepository = null;
      _hostingResources = const HostingResources();
      _hostingResourcesStale = false;
      _hostingBranchDecorations = const {};
      _hostingBinding = null;
    }
    _updateHostingSession();
  }

  /// Runs a fetch or pull forwarded from the command line, once, after
  /// the frame that delivered it; it opens its usual dialog.
  void _forwarded(CliForwardedCommand command) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (command.kind) {
        case CliForwardedCommandKind.fetch:
          if (_refusedRemotely(AppCommandId.fetch)) return;
          _runTransfer(TransferKind.fetch);
        case CliForwardedCommandKind.pull:
          if (_refusedRemotely(AppCommandId.pull)) return;
          _runTransfer(
            TransferKind.pull,
            initialPullStrategy: switch (command.pullStrategy) {
              CliPullStrategy.fastForwardIfPossible =>
                PullStrategy.fastForwardIfPossible,
              CliPullStrategy.rebase => PullStrategy.rebase,
              _ => PullStrategy.fastForwardOnly,
            },
          );
        // The home screen opens remote repositories, with or without tabs.
        case CliForwardedCommandKind.activate ||
            CliForwardedCommandKind.openRepository ||
            CliForwardedCommandKind.openRemoteRepository ||
            CliForwardedCommandKind.refresh:
          break;
      }
    });
  }

  @override
  void dispose() {
    unawaited(_forwardedSubscription?.cancel());
    unawaited(_reconnectedSubscription?.cancel());
    unawaited(_hostingSessionSubscription?.cancel());
    _hostingSession.dispose();
    _refreshSpin?.cancel();
    unawaited(_operationSubscription?.cancel());
    unawaited(_operationPollSubscription?.cancel());
    unawaited(_historySubscription?.cancel());
    unawaited(_inspectorSubscription?.cancel());
    _inspectorFilesHidden.dispose();
    unawaited(_settingsSubscription?.cancel());
    _detailsRevision.dispose();
    unawaited(_syncSubscription?.cancel());
    unawaited(_busySubscription?.cancel());
    unawaited(_transferSubscription?.cancel());
    unawaited(_ownWorkflows?.dispose());
    unawaited(_ownRemote?.dispose());
    super.dispose();
  }

  RepositoryTabState? get _active => widget.workspace.activeTab;

  /// Moves the active tab's strip entry one place; a repository's open
  /// worktrees move together.
  void _moveActive(int delta) {
    final active = _active;
    if (active == null) return;
    final workspace = widget.workspace;
    final entries = workspace.tabEntries;
    final index = entries.indexWhere(
      (entry) => entry.any((tab) => tab.id == active.id),
    );
    final neighbour = index + delta;
    if (index < 0 || neighbour < 0 || neighbour >= entries.length) return;
    final entry = entries[index];
    final leader = entry.first.id;
    final others = [
      for (final tab in workspace.tabs)
        if (tab.id != leader) tab.id,
    ];
    // The leader passes the whole neighbouring entry; the service gathers
    // the rest of its entry beside it.
    final target = delta > 0
        ? others.indexOf(entries[neighbour].last.id) + 1
        : others.indexOf(entries[neighbour].first.id);
    widget.repositories.reorderTab(leader, target);
  }

  void _selectPane(WorkspacePane pane) => _workflows.navigator.selectPane(pane);

  /// Find searches the diff holding the keyboard focus, or the working-tree
  /// diff Changes shows; otherwise History's commit search.
  void _findInRepository() {
    final diffs = [
      for (final role in const [PaneRole.workingDiff, PaneRole.commitDiff])
        ?_paneCommands.handler(role),
    ];
    final focused = diffs.where((diff) => diff.hasFocus?.call() ?? false);
    final shown = _active?.navigation.pane == WorkspacePane.changes
        ? _paneCommands.handler(PaneRole.workingDiff)
        : null;
    for (final diff in [...focused, ?shown]) {
      if (diff.focusFind?.call() ?? false) return;
    }
    _selectPane(WorkspacePane.history);
    _workflows.effects.emit(WorkspaceEffectKind.focusHistorySearch);
  }

  void _revealPowerCommit(String identity) {
    _togglePowerTools();
    unawaited(_workflows.navigator.showCommit(identity));
  }

  /// Shows [panel] in place of any other floating panel, or hides it when
  /// it is shown.
  void _toggle(ShellPanel panel) => setState(() {
    _panel = _panel == panel ? null : panel;
    if (_panel == ShellPanel.operations) _operationsMounted = true;
    if (panel == ShellPanel.extensions) _extensionsFocusLfs = false;
    if (panel == ShellPanel.integrations) _integrationsFocusAdd = false;
  });

  void _toggleOperations() => _toggle(ShellPanel.operations);
  void _toggleSnapshots() => _toggle(ShellPanel.snapshots);
  void _toggleExtensions() => _toggle(ShellPanel.extensions);
  void _toggleIntegrations() => _toggle(ShellPanel.integrations);
  void _togglePowerTools() => _toggle(ShellPanel.powerTools);

  void _showExtensions({bool focusLfs = false}) => setState(() {
    _panel = ShellPanel.extensions;
    _extensionsFocusLfs = focusLfs;
  });

  bool get _operationsVisible => _panel == ShellPanel.operations;
  bool get _snapshotsVisible => _panel == ShellPanel.snapshots;
  bool get _extensionsVisible => _panel == ShellPanel.extensions;
  bool get _integrationsVisible => _panel == ShellPanel.integrations;
  bool get _powerToolsVisible => _panel == ShellPanel.powerTools;

  @override
  Widget build(BuildContext context) {
    final tokens = context.meridian;
    final shortcutBindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        meta: true,
        shift: true,
      ): () =>
          _moveActive(-1),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        meta: true,
        shift: true,
      ): () =>
          _moveActive(1),
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        control: true,
        shift: true,
      ): () =>
          _moveActive(-1),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        control: true,
        shift: true,
      ): () =>
          _moveActive(1),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (_operationsVisible) {
          setState(() => _panel = null);
        }
      },
    };
    final shortcuts = AppShortcutCatalog.resolve(
      widget.settings.current.shortcutOverrides,
      macOS: defaultTargetPlatform == TargetPlatform.macOS,
    );
    final hostingLinks = _hostingLinks();
    final alternateDefaults = AppShortcutCatalog.resolve(
      const [],
      macOS: defaultTargetPlatform != TargetPlatform.macOS,
    );
    final overriddenCommands = widget.settings.current.shortcutOverrides
        .map((entry) => entry.commandId)
        .toSet();
    final activeShortcutScope = switch (_active?.navigation.pane) {
      WorkspacePane.changes
          when hasActiveConflicts(_active?.session?.snapshot.status) =>
        AppCommandShortcutScope.conflict,
      WorkspacePane.changes => AppCommandShortcutScope.changes,
      WorkspacePane.history => AppCommandShortcutScope.history,
      _ => AppCommandShortcutScope.global,
    };
    void addBinding(MapEntry<AppCommandId, AppShortcut?> entry) {
      final shortcut = entry.value;
      if (shortcut == null) return;
      final scopes = AppCommandRegistry.byId(entry.key).shortcutScopes;
      if (!scopes.contains(AppCommandShortcutScope.global) &&
          !scopes.contains(activeShortcutScope)) {
        return;
      }
      final activator = _isTextCharacterShortcut(shortcut)
          ? TextAwareShortcutActivator(shortcut.activator, () => _isEditingText)
          : shortcut.activator;
      shortcutBindings[activator] = () {
        if (entry.key == AppCommandId.showShortcutReference) {
          _showShortcutReferenceUnlessEditing();
        } else {
          _executeCommand(entry.key);
        }
      };
    }

    for (final entry in shortcuts.entries) {
      addBinding(entry);
    }
    for (final entry in alternateDefaults.entries) {
      if (!overriddenCommands.contains(entry.key.name)) addBinding(entry);
    }
    if (_operationsVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureCompass());
    }
    if (_detailsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _detailsRevision.value++;
      });
    }
    final shell = CallbackShortcuts(
      bindings: shortcutBindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: tokens.colors.ground,
          body: SafeArea(
            child: Stack(
              key: _shellStackKey,
              children: [
                Column(
                  children: [
                    SizedBox(
                      key: const Key('repository-toolbar'),
                      height: MeridianSize.toolbar,
                      child: StreamBuilder<void>(
                        stream: widget.appearances.changes,
                        builder: (context, _) => WorkspaceToolbar(
                          active: _active,
                          repositoryLabel: switch (_active) {
                            final active? => repositoryTitle(
                              context,
                              widget.workspace,
                              active,
                              name: widget.appearances.nameFor(
                                active.canonicalIdentity,
                              ),
                            ),
                            null => null,
                          },
                          onCommand: _executeCommand,
                          operations: _operations,
                          operationsVisible: _operationsVisible,
                          activityVisible: _activityVisible,
                          shortcuts: shortcuts,
                          compassKey: _compassKey,
                          paletteButtonKey: _paletteButtonKey,
                          paletteOpen: _paletteOpen,
                          onOpenPalette: () => unawaited(
                            _showCommandPalette(
                              originRect: _globalRect(_paletteButtonKey),
                            ),
                          ),
                          detailsOpen: _detailsOpen,
                          onShowDetails: () =>
                              unawaited(_showRepositoryDetails()),
                          refreshing: _refreshSpinning,
                          syncSequence: _sync.sequence,
                          syncChanged: _sync.changed,
                          repositoryBusy: _activeBusy,
                        ),
                      ),
                    ),
                    RepositoryTabs(
                      workspace: widget.workspace,
                      repositories: widget.repositories,
                      appearances: widget.appearances,
                      fileBrowserName:
                          configuredFileBrowserName(widget.settings) ??
                          platformFileBrowserName(),
                      onOpenFolder: (folder) => _openFolder(folder),
                      onOpenRepository: () =>
                          widget.repositories.addRepositoryChooser(),
                      onAddWorktree: () =>
                          _executeCommand(AppCommandId.addWorktree),
                      remoteHost: (tab) => switch (remoteAuthorityOf(tab)) {
                        final authority? => remoteTabHost(
                          context,
                          _remote,
                          authority,
                          disconnected:
                              tab.session != null &&
                              widget.repositories.isRemoteTabStale(tab),
                        ),
                        null => null,
                      },
                    ),
                    ?widget.notice,
                    if (_active case final active?)
                      RemoteTabBanner(tab: active),
                    Expanded(
                      child: _blockedByOperation(
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              _active?.phase == RepositoryTabPhase.choosing
                              ? RepositoryChooser(
                                  key: ValueKey(_active!.id),
                                  tab: _active!,
                                  repositories: widget.repositories,
                                  settings: widget.settings,
                                )
                              : WorkspaceBody(
                                  active: _active,
                                  powerToolsVisible: _powerToolsVisible,
                                  onClosePowerTools: _togglePowerTools,
                                  onRevealPowerCommit: _revealPowerCommit,
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  commitFileListWidth: _commitFileListWidth,
                                  onCommitFileListWidthChanged: (width) =>
                                      setState(
                                        () => _commitFileListWidth = width,
                                      ),
                                  compactDetailHeight: _compactDetailHeight,
                                  onCompactDetailHeightChanged: (height) =>
                                      setState(
                                        () => _compactDetailHeight = height,
                                      ),
                                  onCommand: _executeCommand,
                                  history: _history,
                                  shortcuts: shortcuts,
                                  openMotionKey:
                                      _active?.phase ==
                                              RepositoryTabPhase.open &&
                                          _active?.session?.snapshot.status !=
                                              null
                                      ? _active?.canonicalIdentity
                                      : null,
                                  sync: _sync,
                                ),
                        ),
                      ),
                    ),
                    if (_activityVisible)
                      ActivitySlot(
                        repositories: widget.repositories,
                        session: _active?.session?.identity,
                        selectedActivityId: _activitySelectionId,
                      ),
                    StatusBar(
                      active: _active,
                      installed: widget.updates.installed,
                      onOpenSource: _openSourceCode,
                      host: switch (_active) {
                        final active? => switch (remoteAuthorityOf(active)) {
                          final authority? => RemoteHostStatus(
                            controller: _remote,
                            authority: authority,
                            disconnected: widget.repositories.isRemoteTabStale(
                              active,
                            ),
                          ),
                          null => null,
                        },
                        null => null,
                      },
                      trailing: _remote.enabled
                          ? RemoteOperationsIndicator(
                              service: widget.remoteWorkspaces,
                            )
                          : null,
                    ),
                  ],
                ),
                if (_operationsMounted)
                  PositionedDirectional(
                    top: MeridianSize.toolbar + MeridianSpace.space2,
                    end: _logbookEnd,
                    width: math.min(
                      GitLamaLayout.logbookWidth,
                      MediaQuery.sizeOf(context).width -
                          2 * MeridianSpace.space3,
                    ),
                    child: OperationCenterPanel(
                      snapshot: _operations,
                      visible: _operationsVisible,
                      onHidden: () {
                        if (mounted && !_operationsVisible) {
                          setState(() => _operationsMounted = false);
                        }
                      },
                      workspace: widget.workspace,
                      repositories: widget.repositories,
                      onClose: _toggleOperations,
                      onCancel: _workflows.operations.cancel,
                      canCancel: _workflows.operations.canCancel,
                      onRetry: _workflows.operations.retry,
                      onDismiss: _workflows.operations.dismiss,
                      onDismissAll: _workflows.operations.dismissAll,
                      onDetails: (entry) => setState(() {
                        _activitySelectionId = entry.activityId;
                        _activityVisible = true;
                      }),
                    ),
                  ),
                if (_snapshotsVisible)
                  PositionedDirectional(
                    top: _floatingPanelTopFor(widget.workspace),
                    end: MeridianSpace.space3,
                    width: GitLamaLayout.snapshotsPanelWidth,
                    child: NamedSnapshotsPanel(
                      key: ValueKey(_active?.session?.identity.nativeId),
                      repositories: widget.repositories,
                      onClose: _toggleSnapshots,
                      onConflict: () {
                        _toggleSnapshots();
                        _selectPane(WorkspacePane.changes);
                      },
                    ),
                  ),
                if (_extensionsVisible)
                  PositionedDirectional(
                    top: _floatingPanelTopFor(widget.workspace),
                    end: MeridianSpace.space3,
                    width: GitLamaLayout.extensionsPanelWidth,
                    child: RepositoryExtensionsPanel(
                      key: ValueKey((
                        _active?.session?.identity.nativeId,
                        _extensionsFocusLfs,
                      )),
                      repositories: widget.repositories,
                      focusLfsPattern: _extensionsFocusLfs,
                      fileBrowserName:
                          configuredFileBrowserName(widget.settings) ??
                          platformFileBrowserName(),
                      onOpenFileBrowser: (path) =>
                          _openTool(IntegrationKind.fileManager, file: path),
                      onClose: _toggleExtensions,
                    ),
                  ),
                if (_integrationsVisible)
                  PositionedDirectional(
                    top: _floatingPanelTopFor(widget.workspace),
                    end: MeridianSpace.space3,
                    width: GitLamaLayout.integrationsPanelWidth,
                    child: IntegrationsPanel(
                      key: ValueKey((
                        _active?.session?.identity.nativeId,
                        _integrationsFocusAdd,
                      )),
                      repositories: widget.repositories,
                      focusAddForm: _integrationsFocusAdd,
                      settings: widget.settings,
                      hosting: widget.hosting,
                      hostingReview: widget.hostingReview,
                      active: _active,
                      hostingSession: _hostingSession,
                      checkoutDisabledReason: _remoteReasonText(
                        AppCommandId.createBranch,
                      ),
                      onResourcesChanged: (_, _, _) {},
                      onCheckout: (pull) => _executeCommand(
                        AppCommandId.createBranch,
                        initialName: pull.sourceBranch,
                        initialTarget: pull.headSha,
                      ),
                      onClose: _toggleIntegrations,
                      onManageHosting: () => unawaited(
                        _showSettings(
                          initialCategory: SettingsCategory.integrations,
                        ),
                      ),
                    ),
                  ),
                if (_powerToolsVisible &&
                    _active?.navigation.pane != WorkspacePane.history)
                  PositionedDirectional(
                    top: _floatingPanelTopFor(widget.workspace),
                    end: MeridianSpace.space3,
                    width: math.min(
                      GitLamaLayout.powerToolsPanelWidth,
                      MediaQuery.sizeOf(context).width -
                          MeridianSpace.space3 * 2,
                    ),
                    child: PowerToolsPanel(
                      key: ValueKey(_active?.session?.identity.nativeId),
                      repositories: widget.repositories,
                      onClose: _togglePowerTools,
                      onReveal: _revealPowerCommit,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return WorkspaceServicesScope(
      repositories: widget.repositories,
      settings: widget.settings,
      workflows: _workflows,
      hosting: widget.hosting,
      // A repository on another computer opens no inspector window; the
      // host says so.
      inspectionWindows: widget.inspectionWindows,
      child: FileActionsScope(
        openExternal: (file) => _openTool(IntegrationKind.editor, file: file),
        revealInFileBrowser: (file) =>
            _openTool(IntegrationKind.fileManager, file: file),
        openFolder: _openFolder,
        fileBrowserName:
            configuredFileBrowserName(widget.settings) ??
            platformFileBrowserName(),
        inspectWorkingFile: _inspectWorkingFile,
        child: DiffViewPreferencesScope(
          preferences: widget.settings.current.appearance.diffView,
          onChanged: (preferences) => widget.settings.updateAppearance(
            (appearance) => appearance.copyWith(diffView: preferences),
          ),
          child: HostingScope(
            hosting: widget.hosting,
            binding: _hostingBinding,
            resources: _hostingResources,
            stale: _hostingResourcesStale,
            branchDecorations: _hostingBranchDecorations,
            links: hostingLinks,
            child: InspectorHostScope(
              maximized: _inspectorMaximized,
              onToggleMaximized: () =>
                  setState(() => _inspectorMaximized = !_inspectorMaximized),
              onOpenWindowFailed: _inspectionWindowFailed,
              filesHidden: _inspectorFilesHidden,
              onCreatePatch: (target, paths) =>
                  unawaited(_createDiffPatch(target, paths)),
              child: RemoteWorkspaceScope(
                controller: _remote,
                child: PaneCommandContextScope(
                  context: _paneCommands,
                  child: CommandAvailabilityScope(
                    state: () => _commandMenuState,
                    child: shell,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the mounted panes contribute to command availability.
  final PaneCommandContext _paneCommands = PaneCommandContext();

  /// Rebuilds the shell from its part files' extensions, which may not
  /// call the protected [setState] themselves.
  void _update(VoidCallback change) => setState(change);
}
