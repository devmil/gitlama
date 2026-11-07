import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../models/app_shortcut.dart';
import '../models/inspection_window.dart';
import '../models/inspector.dart';
import '../models/repository_state.dart';
import '../models/diff.dart';
import '../models/settings.dart';
import 'workspace/diff_view_preferences.dart';
import '../services/inspector/inspector_service.dart';
import '../services/repository_session_service.dart';
import '../widgets/author_avatar.dart';
import '../widgets/git_file_list/git_file_list.dart';
import '../widgets/gitlama_window_caption.dart';
import '../widgets/native_menu.dart';
import '../widgets/status_notification.dart';
import 'app_appearance.dart';
import 'app_theme.dart';
import 'inspector/inspector_host.dart';
import 'inspector/inspector_view.dart';
import 'inspector_window_runtime.dart';
import 'startup_screen.dart';
import 'workspace/status_bar.dart';

final _log = AppLogger('InspectorWindowLauncher');

typedef InspectorWindowBootstrap =
    Future<InspectorWindowRuntime> Function(InspectionWindowRequest request);

/// A separate window showing one inspector on its own read-only session.
///
/// Like the main window's launcher it bootstraps its services in a fresh
/// composition root, shows a failed start with Retry, and shuts the
/// services down when it goes away. Theme, density and motion follow the
/// appearance settings.
class InspectionWindowApp extends StatefulWidget {
  const InspectionWindowApp({
    required this.request,
    this.bootstrap = bootstrapInspectorWindow,
    this.setTitle = _setWindowTitle,
    super.key,
  });

  final InspectionWindowRequest request;
  final InspectorWindowBootstrap bootstrap;
  final Future<void> Function(String title) setTitle;

  @override
  State<InspectionWindowApp> createState() => _InspectionWindowAppState();
}

Future<void> _setWindowTitle(String title) async {
  try {
    await windowManager.setTitle(title);
  } on Object {
    // The title stays the application's when the plugin is unavailable.
  }
}

class _InspectionWindowAppState extends State<InspectionWindowApp> {
  InspectorWindowRuntime? _runtime;
  StreamSubscription<SettingsDocument>? _settingsSubscription;
  AppearanceSettings _appearance = const AppearanceSettings();
  late Future<InspectorWindowRuntime> _startup;

  @override
  void initState() {
    super.initState();
    unawaited(NativeMenus.prepare());
    _startup = _start();
  }

  Future<InspectorWindowRuntime> _start() async {
    final runtime = await widget.bootstrap(widget.request);
    if (!mounted) {
      await _shutDown(runtime);
      return runtime;
    }
    setState(() {
      _runtime = runtime;
      _appearance = runtime.settings.current.appearance;
    });
    await _settingsSubscription?.cancel();
    // Only an appearance change rebuilds the app; the inspector rebuilds
    // its own subtree.
    _settingsSubscription = runtime.settings.changes.listen((document) {
      if (mounted && _themeOf(document.appearance) != _themeOf(_appearance)) {
        setState(() => _appearance = document.appearance);
      }
    });
    return runtime;
  }

  static (String, String, String) _themeOf(AppearanceSettings settings) =>
      (settings.theme, settings.density, settings.reduceMotion);

  void _retry() {
    _log.info('inspector_window_bootstrap_retried');
    setState(() {
      _startup = _start();
    });
  }

  static Future<void> _shutDown(InspectorWindowRuntime runtime) =>
      runtime.shutdown().catchError((Object error, StackTrace _) {
        _log.warning('inspector_window_shutdown_failed', {
          'error_type': LogField(error.runtimeType, LogSensitivity.diagnostic),
        });
      });

  @override
  void dispose() {
    unawaited(_settingsSubscription?.cancel());
    if (_runtime case final runtime?) unawaited(_shutDown(runtime));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = AppAppearance(_appearance);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appearance.theme,
      darkTheme: appearance.darkTheme,
      themeMode: appearance.themeMode,
      builder: (context, child) => appearance.applyMotion(
        context,
        NativeMenus.scope(
          child: GitLamaWindowCaptionFrame(
            child: StatusNotificationScope(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      home: FutureBuilder<InspectorWindowRuntime>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            final runtime = snapshot.data!;
            return AvatarScope(
              service: runtime.avatars,
              child: _InspectorWindowHome(
                request: widget.request,
                runtime: runtime,
                setTitle: widget.setTitle,
              ),
            );
          }
          return StartupScreen(
            failed:
                snapshot.connectionState == ConnectionState.done &&
                snapshot.hasError,
            onRetry: _retry,
          );
        },
      ),
    );
  }
}

/// The inspector of a started window. It rebuilds on the inspector's
/// changes and names the window after its location, outside of build.
class _InspectorWindowHome extends StatefulWidget {
  const _InspectorWindowHome({
    required this.request,
    required this.runtime,
    required this.setTitle,
  });

  final InspectionWindowRequest request;
  final InspectorWindowRuntime runtime;
  final Future<void> Function(String title) setTitle;

  @override
  State<_InspectorWindowHome> createState() => _InspectorWindowHomeState();
}

class _InspectorWindowHomeState extends State<_InspectorWindowHome> {
  late final _WindowInspectorHost _host = _WindowInspectorHost(
    request: widget.request,
    services: widget.runtime,
    settings: () => widget.runtime.settings.current,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  StreamSubscription<InspectorState>? _states;
  late GitFileListMode _filesMode =
      GitFileListMode.values
          .where(
            (mode) =>
                mode.name ==
                widget.runtime.settings.current.appearance.commitFilesMode,
          )
          .firstOrNull ??
      GitFileListMode.tree;
  double _sidebarWidth = 280;
  String? _title;

  /// The window starts with the stored diff preferences and keeps its own
  /// changes; only the main window writes the settings.
  late DiffViewPreferences _diffView =
      widget.runtime.settings.current.appearance.diffView;

  InspectorService get _inspector => widget.runtime.session.inspector;

  @override
  void initState() {
    super.initState();
    _states = _inspector.states.listen((_) {
      if (!mounted) return;
      setState(() {});
      _updateTitle();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTitle();
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  /// The label of the remote host profile the repository is on, if any.
  String? get _hostLabel {
    final authority = widget.request.repository.remote;
    if (authority == null) return null;
    return widget.runtime.settings.current.remoteProfiles
        .where((profile) => profile.id == authority.profileId)
        .firstOrNull
        ?.label;
  }

  /// `<repository> — <location>`, so windows are told apart in the task
  /// switcher; a remote repository names its host too.
  void _updateTitle() {
    final location = _inspector.current.location;
    final units = widget.request.repository.units;
    final path = displayNativePath(widget.request.repository);
    final folder = path
        .split(RegExp(r'[/\\]'))
        .lastWhere(
          (part) => part.isNotEmpty,
          orElse: () => String.fromCharCodes(units),
        );
    final host = _hostLabel;
    final name = host == null
        ? folder
        : context.l10n.remoteTabLabel(folder, host);
    final title = location == null
        ? '$name — ${context.l10n.appTitle}'
        : '$name — ${inspectorLabel(context, location)}';
    if (title == _title) return;
    _title = title;
    unawaited(widget.setTitle(title));
  }

  /// Why the repository did not open. A remote host the main window is
  /// not connected to can be connected there, then tried again.
  Widget _failure(BuildContext context) {
    final session = widget.runtime.session;
    if (session.failure != RepositoryFailureCode.remoteDisconnected) {
      return MeridianEmptyState(
        compact: true,
        title: context.l10n.inspectorRepositoryClosed,
      );
    }
    final host = _hostLabel;
    return MeridianEmptyState(
      key: const ValueKey('inspector-window-disconnected'),
      compact: true,
      icon: 'wifi-off',
      title: host == null
          ? context.l10n.inspectorRemoteHostNotConnected
          : context.l10n.remoteTabDisconnectedTitle(host),
      message: context.l10n.inspectorRemoteHostNotConnectedDetail,
      action: MeridianButton(
        key: const ValueKey('inspector-window-retry'),
        label: context.l10n.retry,
        onPressed: () async {
          await session.retry();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// The Linux runner hides the GTK title bar, so the window draws its
  /// title and window buttons itself, as the main window's toolbar does.
  Widget _caption(BuildContext context) => GitLamaWindowDragArea(
    child: SizedBox(
      key: const ValueKey('inspector-window-caption'),
      height: MeridianSize.toolbar,
      child: Row(
        children: [
          const SizedBox(width: MeridianSpace.space5),
          Expanded(
            child: Text(
              _title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.bodyStrong,
            ),
          ),
          const GitLamaWindowControls(),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.runtime.session;
    final macOS = defaultTargetPlatform == TargetPlatform.macOS;
    return Scaffold(
      backgroundColor: context.colors.ground,
      body: SafeArea(
        child: Column(
          children: [
            if (GitLamaWindowCaptionFrame.drawsCaption) _caption(context),
            Expanded(
              child: Padding(
                padding: GitLamaWindowCaptionFrame.drawsCaption
                    ? const EdgeInsets.fromLTRB(
                        MeridianSpace.space3,
                        0,
                        MeridianSpace.space3,
                        MeridianSpace.space3,
                      )
                    : const EdgeInsets.all(MeridianSpace.space3),
                child: MeridianIsland(
                  expandChild: true,
                  child: session.failed
                      ? _failure(context)
                      : DiffViewPreferencesScope(
                          preferences: _diffView,
                          onChanged: (value) =>
                              setState(() => _diffView = value),
                          child: InspectorView(
                            key: const ValueKey('inspector-window'),
                            service: _inspector,
                            host: _host,
                            shortcuts: AppShortcutCatalog.resolve(
                              widget.runtime.settings.current.shortcutOverrides,
                              macOS: macOS,
                            ),
                            filesMode: _filesMode,
                            onFilesModeChanged: (mode) =>
                                setState(() => _filesMode = mode),
                            sidebarWidth: _sidebarWidth,
                            onSidebarWidthChanged: (width) =>
                                setState(() => _sidebarWidth = width),
                          ),
                        ),
                ),
              ),
            ),
            StatusBar(active: null, statusLabel: context.l10n.appTitle),
          ],
        ),
      ),
    );
  }
}

/// An inspector window: no graph of its own, a way back to the main window.
final class _WindowInspectorHost extends InspectorHost {
  _WindowInspectorHost({
    required this.request,
    required this.services,
    required this.settings,
    required this.onChanged,
  });

  final InspectionWindowRequest request;
  final InspectorWindowRuntime services;
  final SettingsDocument Function() settings;

  /// Rebuilds the window after the host's own state changed.
  final void Function() onChanged;

  /// The main window answered that the repository is not open there; the
  /// action stays off until the location changes.
  InspectorTarget? _unreachable;

  @override
  bool get isWindow => true;

  @override
  bool get supportsWindows => true;

  /// A remote repository's window reads through the main window; local
  /// tools, file managers and restores do not reach its host.
  @override
  bool get remote => request.repository.isRemote;

  @override
  Future<void> openInWindow(InspectorLocation location) =>
      services.windows.open(repository: request.repository, location: location);

  @override
  bool get canShowInGraph =>
      _unreachable == null ||
      _unreachable != services.session.inspector.current.target;

  @override
  Future<bool> showInGraph(InspectorTarget target) async {
    final revealed = await services.reveal.reveal(request.repository, target);
    _unreachable = revealed ? null : target;
    onChanged();
    return revealed;
  }

  @override
  String get inspectionOpenIn => settings().appearance.inspectionOpenIn;

  @override
  RepositorySessionService? get repositories => null;

  @override
  bool get canOpenWorkingCopy => false;

  @override
  void openWorkingCopy(List<int> path, {required bool reveal}) {}

  @override
  String get fileBrowserName => platformFileBrowserName();

  @override
  bool get canCreatePatch => false;

  @override
  void createPatch(InspectorTarget target, List<List<int>> paths) {}

  @override
  bool get canRestore => false;
}
