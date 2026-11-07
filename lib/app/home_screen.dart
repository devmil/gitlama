import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';
import '../models/cli_forwarding.dart';
import '../models/app_command.dart';
import '../models/app_shortcut.dart';
import '../models/clone_attempt.dart';
import '../models/operation_center.dart';
import '../models/repository_drop.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';
import '../models/workspace.dart';
import '../services/workflows/entry_workflows.dart';
import '../services/workflows/window_workflows.dart';
import '../widgets/status_notification.dart';
import 'app_runtime.dart';
import 'app_shortcut_activator.dart';
import 'app_theme.dart';
import 'gitlama_layout.dart';
import 'host_platform.dart';
import 'welcome_screen.dart';
import 'workspace/git_credential_dialog.dart';
import 'workspace/host_key_dialog.dart';
import 'workspace/initialize_dialog.dart';
import 'workspace/remote_workspace.dart';
import 'workspace/settings_dialog.dart';
import 'workspace_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.runtime, super.key});

  final AppRuntime runtime;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The window: the workspace while repositories are open, the welcome
/// screen otherwise. It owns the window's workflows and answers the entry
/// workflows' questions with dialogs.
class _HomeScreenState extends State<HomeScreen> implements EntryInteraction {
  StreamSubscription<RepositorySessionState>? _subscription;
  StreamSubscription<CloneAttemptSnapshot>? _cloneSubscription;
  StreamSubscription<WorkspaceState>? _workspaceSubscription;
  StreamSubscription<OperationCenterSnapshot>? _operationSubscription;
  StreamSubscription<EntryState>? _entrySubscription;
  StreamSubscription<bool>? _dropStateSubscription;
  StreamSubscription<RepositoryDropOutcome>? _dropOutcomeSubscription;
  StreamSubscription<SettingsDocument>? _settingsSubscription;
  StreamSubscription<CliForwardedCommand>? _forwardedSubscription;

  /// The window's remote workflows, shared with the workspace shell.
  late final RemoteWorkspaceController _remote = RemoteWorkspaceController(
    service: widget.runtime.remoteWorkspaces,
    repositories: widget.runtime.repositorySessions,
  );

  /// The window's workflows, shared with the workspace shell. They attach
  /// the window to forwarded command-line commands until it closes.
  late final WindowWorkflows _workflows = WindowWorkflows(
    repositories: widget.runtime.repositorySessions,
    operationCenter: widget.runtime.operationCenter,
    remote: _remote.workflows,
    platform: hostPlatform(),
    cli: widget.runtime.cliForwarding,
    inspectorReveal: widget.runtime.inspectorReveal,
  );
  RepositorySessionState? _repository;
  CloneAttemptSnapshot? _clone;
  late EntryState _entry;
  late WorkspaceState _workspace;
  late OperationCenterSnapshot _operations;
  bool _operationsVisible = false;
  var _dropActive = false;

  @override
  void initState() {
    super.initState();
    final sessions = widget.runtime.repositorySessions;
    _repository = sessions.current;
    _workspace = sessions.workspace;
    _operations = widget.runtime.operationCenter.current;
    _entry = _workflows.entry.current;
    _entrySubscription = _workflows.entry.states.listen((state) {
      if (mounted) setState(() => _entry = state);
    });
    _subscription = sessions.states.listen((state) {
      if (mounted) setState(() => _repository = state);
    });
    _clone = sessions.currentClone;
    _cloneSubscription = sessions.cloneStates.listen((state) {
      if (mounted) setState(() => _clone = state);
    });
    _workspaceSubscription = sessions.workspaceStates.listen((state) {
      if (mounted) setState(() => _workspace = state);
    });
    _operationSubscription = widget.runtime.operationCenter.states.listen((
      snapshot,
    ) {
      if (mounted) setState(() => _operations = snapshot);
    });
    // Host profiles and their appearance live in the settings the welcome
    // screen shows.
    _settingsSubscription = widget.runtime.settings.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _forwardedSubscription = _workflows.entry.forwardedCommands.listen(
      _forwarded,
    );
    final repositoryDrops = widget.runtime.repositoryDrops;
    _dropActive = repositoryDrops.dragging;
    _dropStateSubscription = repositoryDrops.dragStates.listen((active) {
      if (mounted) setState(() => _dropActive = active);
    });
    _dropOutcomeSubscription = repositoryDrops.outcomes.listen((outcome) {
      if (!mounted) return;
      StatusNotificationScope.show(
        context,
        context.l10n.repositoryDropSummary(
          outcome.openedRepositories,
          outcome.rejectedItems,
          outcome.failedDirectories,
        ),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_cloneSubscription?.cancel());
    unawaited(_workspaceSubscription?.cancel());
    unawaited(_operationSubscription?.cancel());
    unawaited(_entrySubscription?.cancel());
    unawaited(_dropStateSubscription?.cancel());
    unawaited(_dropOutcomeSubscription?.cancel());
    unawaited(_settingsSubscription?.cancel());
    unawaited(_forwardedSubscription?.cancel());
    unawaited(_workflows.dispose());
    unawaited(_remote.dispose());
    super.dispose();
  }

  /// Opens a repository on a host as the command line asked, whether or
  /// not the window shows tabs yet.
  void _forwarded(CliForwardedCommand command) {
    final alias = command.remoteAlias;
    final path = command.path;
    if (command.kind != CliForwardedCommandKind.openRemoteRepository ||
        alias == null ||
        path == null) {
      return;
    }
    // A stream event, not a build: the dialogs may open at once. A post-frame
    // callback would wait for a frame an idle window never schedules.
    if (mounted) unawaited(_remote.openOnHost(context, alias, path.units));
  }

  // The entry workflows' questions.

  @override
  bool get active => mounted;

  @override
  Future<String?> chooseCloneSource() async {
    var enteredSource = '';
    final source = await showMeridianDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final empty = enteredSource.trim().isEmpty;
          void choose() => Navigator.pop(context, enteredSource.trim());
          return MeridianDialog(
            width: MeridianLayout.dialogFormWidth,
            title: context.l10n.cloneRepository,
            description: context.l10n.cloneSourceDescription,
            onSubmit: choose,
            submitDisabled: empty,
            content: MeridianTextField(
              key: const ValueKey('clone-source'),
              autofocus: true,
              label: context.l10n.cloneSourceLabel,
              placeholder: context.l10n.cloneSourceHint,
              monospace: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (value) => update(() => enteredSource = value),
            ),
            actions: [
              MeridianButton(
                label: context.l10n.cancel,
                variant: MeridianButtonVariant.quiet,
                onPressed: () => Navigator.pop(context),
              ),
              MeridianButton(
                label: context.l10n.chooseCloneDestination,
                variant: MeridianButtonVariant.primary,
                onPressed: empty ? null : choose,
              ),
            ],
          );
        },
      ),
    );
    return source;
  }

  @override
  Future<({String? profileId, bool bare})?> chooseInitialize({
    required bool initiallyBare,
  }) => showInitializeRepositoryDialog(
    context,
    remote: _remote,
    initiallyBare: initiallyBare,
  );

  @override
  Future<RepositorySessionState?> initializeOnHost(
    String profileId, {
    required bool bare,
  }) => _remote.initializeRemoteRepository(context, profileId, bare: bare);

  @override
  Future<({String? username, String secret})?> cloneCredentials() async {
    final input = await showGitCredentialDialog(context);
    if (input == null) return null;
    return (username: input.username, secret: input.secret);
  }

  @override
  Future<bool> trustHostKey(HostKeyChallenge challenge) =>
      confirmHostKey(context, challenge);

  Future<void> _showSettings() => showSettingsDialog(
    context,
    settings: widget.runtime.settings,
    repositories: widget.runtime.repositorySessions,
    hosting: widget.runtime.hosting,
    repository: null,
    updates: widget.runtime.updates,
    remote: _remote,
  );

  @override
  Widget build(BuildContext context) {
    final entry = _workflows.entry;
    if (_workspace.tabs.isNotEmpty) {
      return _withRepositoryDropOverlay(
        context,
        WorkspaceShell(
          runtime: widget.runtime,
          workspace: _workspace,
          remoteController: _remote,
          workflows: _workflows,
          onOpenRepository: () => unawaited(entry.open()),
          onCloneRepository: () => unawaited(entry.clone(this)),
          onInitializeRepository: () => unawaited(entry.initialize(this)),
          notice: _workspaceNotice(context),
        ),
      );
    }
    return _withRepositoryDropOverlay(
      context,
      _withSettingsShortcut(
        WelcomeScreen(
          ready: _repository?.snapshot.phase == RepositoryPhase.ready,
          busy: _entry.busy,
          clone: _clone,
          cloneFailure: _entry.cloneFailure,
          failure: _entry.failure,
          recents: visibleRecents(
            widget.runtime.settings.current.recentRepositories,
            _remote,
          ),
          remote: _remote,
          operations: _operations,
          operationsVisible: _operationsVisible,
          workspace: _workspace,
          repositories: widget.runtime.repositorySessions,
          operationActions: _workflows.operations,
          onOpen: () => unawaited(entry.open()),
          onOpenRemote: () => unawaited(_remote.openRemoteRepository(context)),
          onClone: () => unawaited(entry.clone(this)),
          onInitialize: (bare) =>
              unawaited(entry.initialize(this, initiallyBare: bare)),
          onCancelClone: () =>
              unawaited(widget.runtime.repositorySessions.cancelClone()),
          onRetryCredentials: () =>
              unawaited(entry.retryCloneWithCredentials(this)),
          onInspectHostKey: () => unawaited(entry.inspectCloneHostKey(this)),
          onOpenRecent: (identity) => unawaited(entry.openRecent(identity)),
          onOpenRemoteRecent: (identity) =>
              unawaited(_remote.openRecent(context, identity)),
          onShowSettings: () => unawaited(_showSettings()),
          onToggleOperations: () =>
              setState(() => _operationsVisible = !_operationsVisible),
        ),
      ),
    );
  }

  // The welcome screen has no command scope; Settings keeps its shortcut,
  // and Open Remote Repository keeps its own while remote workspaces are on.
  Widget _withSettingsShortcut(Widget child) {
    final resolved = AppShortcutCatalog.resolve(
      widget.runtime.settings.current.shortcutOverrides,
      macOS: defaultTargetPlatform == TargetPlatform.macOS,
    );
    final shortcut = resolved[AppCommandId.showSettings];
    final remoteShortcut = resolved[AppCommandId.openRemoteRepository];
    return CallbackShortcuts(
      bindings: {
        if (shortcut != null)
          shortcut.activator: () => unawaited(_showSettings()),
        if (remoteShortcut != null && _remote.enabled)
          remoteShortcut.activator: () {
            if (!_entry.busy) {
              unawaited(_remote.openRemoteRepository(context));
            }
          },
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  Widget _withRepositoryDropOverlay(BuildContext context, Widget child) =>
      Stack(
        children: [
          child,
          if (_dropActive)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: context.colors.ground,
                  child: Center(
                    child: MeridianOverlayEntrance(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: GitLamaLayout.dropPromptWidth,
                        ),
                        child: MeridianDropZone(
                          label: context.l10n.repositoryDropPrompt,
                          icon: 'folder-open',
                          state: MeridianDropZoneState.active,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget? _workspaceNotice(BuildContext context) {
    final clone = _clone;
    if (clone?.phase == CloneAttemptPhase.running) {
      return MeridianProgressBar(value: cloneProgress(clone!));
    }
    final failure = _entry.cloneFailure;
    if (failure != null) {
      final action = switch (failure) {
        CloneFailureCode.authentication => MeridianButton(
          label: context.l10n.retryAuthentication,
          variant: MeridianButtonVariant.quiet,
          onPressed: _entry.busy
              ? null
              : () =>
                    unawaited(_workflows.entry.retryCloneWithCredentials(this)),
        ),
        CloneFailureCode.hostKey => MeridianButton(
          label: context.l10n.inspectHostKey,
          variant: MeridianButtonVariant.quiet,
          onPressed: _entry.busy
              ? null
              : () => unawaited(_workflows.entry.inspectCloneHostKey(this)),
        ),
        _ => null,
      };
      return Padding(
        padding: const EdgeInsets.all(MeridianSpace.space4),
        child: MeridianBanner(
          tone: MeridianBannerTone.error,
          message: cloneFailureMessage(context, failure),
          actions: [?action],
        ),
      );
    }
    final repositoryFailure = _entry.failure;
    if (repositoryFailure != null) {
      return Padding(
        padding: const EdgeInsets.all(MeridianSpace.space4),
        child: MeridianBanner(
          tone: MeridianBannerTone.error,
          message: repositoryFailureMessage(context, repositoryFailure),
        ),
      );
    }
    return null;
  }
}
