import 'dart:async';
import '../../widgets/diagnostic_settings.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/hosting.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/app_update_service.dart';
import '../../services/repository_session_service.dart';
import '../../services/settings_service.dart';
import '../../services/hosting_connection_service.dart';
import '../../widgets/hosting_integrations_section.dart';
import '../app_theme.dart';
import 'integrations_panel.dart';
import 'remote_hosts_settings.dart';
import 'remote_workspace.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';
import 'updates_settings.dart';

export 'shortcut_reference_dialog.dart';
import 'settings_pages.dart';

enum SettingsDestination { licenses }

enum SettingsCategory {
  appearance,
  git,
  integrations,
  repositoryBinding,
  remoteHosts,
  customCommands,
  diffView,
  diffRenderer,
  shortcuts,
  accessibility,
  updates,
  diagnostics,
  licenses,
}

/// Opens the settings and follows the destination they close with.
/// [repository] is null when no repository is open.
Future<void> showSettingsDialog(
  BuildContext context, {
  required SettingsService settings,
  required RepositorySessionService repositories,
  required HostingConnectionService hosting,
  required RepositoryTabState? repository,
  RepositoryTabState? hostingRepository,
  SettingsCategory initialCategory = SettingsCategory.appearance,
  required AppUpdateService updates,
  required RemoteWorkspaceController remote,
}) async {
  final destination = await showMeridianDialog<SettingsDestination>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SettingsDialog(
      settings: settings,
      repositories: repositories,
      hosting: hosting,
      repository: repository,
      hostingRepository: hostingRepository,
      initialCategory: initialCategory,
      onOpenUrl: hosting.openBrowser,
      updates: updates,
      remote: remote,
    ),
  );
  if (!context.mounted) return;
  switch (destination) {
    case SettingsDestination.licenses:
      showAppLicenses(context);
    case null:
      break;
  }
}

void showAppLicenses(BuildContext context) => showLicensePage(
  context: context,
  applicationName: context.l10n.appTitle,
  applicationVersion: const String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '0.1.0',
  ),
  applicationIcon: Image.asset(
    'assets/brand/tile-64.png',
    width: GitLamaLayout.welcomeMarkSize,
    height: GitLamaLayout.welcomeMarkSize,
    semanticLabel: context.l10n.appTitle,
  ),
);

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.repositories,
    required this.hosting,
    required this.repository,
    this.hostingRepository,
    required this.initialCategory,
    required this.onOpenUrl,
    this.updates,
    this.remote,
  });

  final SettingsService settings;
  final RepositorySessionService repositories;
  final HostingConnectionService? hosting;
  final RepositoryTabState? repository;

  /// The provider binding target, including a repository on another computer.
  /// Kept separate from local Git settings and executable configuration.
  final RepositoryTabState? hostingRepository;
  final SettingsCategory initialCategory;
  final Future<void> Function(String url) onOpenUrl;

  /// Null or unsupported hides the Updates category.
  final AppUpdateService? updates;

  /// Null or without remote workspaces hides the Remote hosts category.
  final RemoteWorkspaceController? remote;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsCategory _category = widget.initialCategory;
  final FocusNode _resetFocus = FocusNode(
    debugLabel: 'reset-repository-settings',
  );
  String? _saveFailure;

  @override
  void dispose() {
    _resetFocus.dispose();
    super.dispose();
  }

  String _categoryLabel(SettingsCategory category) => switch (category) {
    SettingsCategory.appearance => context.l10n.settingsAppearance,
    SettingsCategory.git => context.l10n.settingsGit,
    SettingsCategory.integrations => context.l10n.settingsIntegrations,
    SettingsCategory.repositoryBinding =>
      context.l10n.settingsRepositoryBinding,
    SettingsCategory.remoteHosts => context.l10n.settingsRemoteHosts,
    SettingsCategory.customCommands => context.l10n.settingsCustomCommands,
    SettingsCategory.diffView => context.l10n.settingsDiffView,
    SettingsCategory.diffRenderer => context.l10n.settingsDiffRenderer,
    SettingsCategory.shortcuts => context.l10n.settingsShortcuts,
    SettingsCategory.accessibility => context.l10n.settingsAccessibility,
    SettingsCategory.updates => context.l10n.settingsUpdates,
    SettingsCategory.diagnostics => context.l10n.diagnosticsTitle,
    SettingsCategory.licenses => context.l10n.licensesTitle,
  };

  String _categoryIcon(SettingsCategory category) => switch (category) {
    SettingsCategory.appearance => 'palette',
    SettingsCategory.git => 'branch',
    SettingsCategory.integrations => 'cloud',
    SettingsCategory.repositoryBinding => 'link',
    SettingsCategory.remoteHosts => 'server',
    SettingsCategory.customCommands => 'command',
    SettingsCategory.diffView => 'side-by-side',
    SettingsCategory.diffRenderer => 'file-diff',
    SettingsCategory.shortcuts => 'shortcuts',
    SettingsCategory.accessibility => 'accessibility',
    SettingsCategory.updates => 'download',
    SettingsCategory.diagnostics => 'activity',
    SettingsCategory.licenses => 'info',
  };

  List<SettingsCategory> get _categories => [
    for (final category in SettingsCategory.values)
      if (switch (category) {
        SettingsCategory.updates => widget.updates?.isSupported ?? false,
        SettingsCategory.remoteHosts => widget.remote?.enabled ?? false,
        _ => true,
      })
        category,
  ];

  void _updateAppearance(AppearanceSettings appearance) {
    widget.settings.updateAppearance((_) => appearance);
    setState(() => _saveFailure = null);
  }

  void _updateAutoFetch(AutoFetchSettings autoFetch) {
    widget.settings.updateAutoFetch(autoFetch);
    setState(() => _saveFailure = null);
  }

  void _updateRepositoryAutoFetch(NativePathIdentity repository, bool? value) {
    widget.settings.setRepositoryAutoFetch(repository, value);
    setState(() => _saveFailure = null);
  }

  Future<void> _updateShortcut(AppCommandId command, String input) async {
    try {
      await widget.settings.setShortcut(
        command,
        input,
        macOS: defaultTargetPlatform == TargetPlatform.macOS,
      );
      if (mounted) setState(() => _saveFailure = null);
    } on AppShortcutException catch (error) {
      if (!mounted) return;
      setState(() {
        _saveFailure = switch (error.code) {
          AppShortcutFailureCode.reserved =>
            context.l10n.settingsShortcutReserved,
          AppShortcutFailureCode.conflict =>
            context.l10n.settingsShortcutConflict,
          _ => context.l10n.settingsShortcutInvalid,
        };
      });
    } on Object {
      if (mounted) {
        setState(() => _saveFailure = context.l10n.settingsSaveFailed);
      }
    }
  }

  Future<void> _resetShortcuts() async {
    try {
      await widget.settings.resetShortcuts();
      if (mounted) setState(() => _saveFailure = null);
    } on Object {
      if (mounted) {
        setState(() => _saveFailure = context.l10n.settingsSaveFailed);
      }
    }
  }

  Map<AppCommandId, String?> _settingsShortcutLabels() {
    final document = widget.settings.current;
    final resolved = AppShortcutCatalog.resolve(
      document.shortcutOverrides,
      macOS: defaultTargetPlatform == TargetPlatform.macOS,
    );
    return Map.unmodifiable({
      for (final command in AppCommandRegistry.commands)
        command.id: resolved[command.id]?.canonical,
    });
  }

  Future<void> _resetRepositorySettings() async {
    final repository = widget.repository;
    final identity = repository?.canonicalIdentity;
    if (repository == null || identity == null) return;
    final confirmed = await showMeridianConfirm(
      context,
      title: context.l10n.settingsResetRepositoryTitle,
      description: context.l10n.settingsResetRepositoryConfirmation(
        repository.label,
      ),
      confirmLabel: context.l10n.settingsResetRepositoryAction,
      cancelLabel: context.l10n.cancel,
      destructive: true,
    );
    if (!mounted) return;
    if (confirmed) {
      try {
        await widget.settings.resetRepository(identity);
        if (mounted) setState(() => _saveFailure = null);
      } on Object {
        if (mounted) {
          setState(() => _saveFailure = context.l10n.settingsSaveFailed);
        }
      }
    }
    if (mounted) _resetFocus.requestFocus();
  }

  String _categoryDescription(SettingsCategory category) => switch (category) {
    SettingsCategory.appearance => context.l10n.settingsAppearanceDetail,
    SettingsCategory.git => context.l10n.settingsGitDetail,
    SettingsCategory.integrations => context.l10n.settingsIntegrationsDetail,
    SettingsCategory.repositoryBinding =>
      context.l10n.settingsRepositoryBindingDetail,
    SettingsCategory.remoteHosts => context.l10n.settingsRemoteHostsDetail,
    SettingsCategory.customCommands =>
      context.l10n.settingsCustomCommandsDetail,
    SettingsCategory.diffView => context.l10n.settingsDiffViewDetail,
    SettingsCategory.diffRenderer => context.l10n.settingsDiffRendererDetail,
    SettingsCategory.shortcuts => context.l10n.settingsShortcutsDetail,
    SettingsCategory.accessibility => context.l10n.settingsAccessibilityDetail,
    SettingsCategory.updates => context.l10n.settingsUpdatesDetail,
    SettingsCategory.diagnostics => context.l10n.diagnosticsDescription,
    SettingsCategory.licenses => context.l10n.settingsLicensesDetail,
  };

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return MeridianSettingsDialog(
      title: context.l10n.settingsTitle,
      page: math.max(0, categories.indexOf(_category)),
      onPageChanged: (index) => setState(() => _category = categories[index]),
      footer: switch (_saveFailure) {
        final failure? => Semantics(
          liveRegion: true,
          child: Text(
            failure,
            style: context.text.caption.copyWith(color: context.colors.danger),
          ),
        ),
        null => null,
      },
      pages: [
        for (final category in categories)
          MeridianSettingsPage(
            key: Key('settings-category-${category.name}'),
            label: _categoryLabel(category),
            icon: _categoryIcon(category),
            description: _categoryDescription(category),
            builder: (_) => _settingsPage(category),
          ),
      ],
    );
  }

  Widget _settingsPage(SettingsCategory category) {
    final hostingRepository = widget.hostingRepository ?? widget.repository;
    final appearance = widget.settings.current.appearance;
    final autoFetch = widget.settings.current.autoFetch;
    final shortcutLabels = _settingsShortcutLabels();
    return switch (category) {
      SettingsCategory.appearance => appearanceSettingsPage(
        context,
        appearance,
        _updateAppearance,
      ),
      SettingsCategory.git => gitSettingsPage(
        context,
        settings: widget.settings,
        workingCopy: widget.repositories.workingCopy,
        autoFetch: autoFetch,
        repository: widget.repository,
        updateAutoFetch: _updateAutoFetch,
        updateRepositoryAutoFetch: _updateRepositoryAutoFetch,
        onResetRepository: _resetRepositorySettings,
        resetFocus: _resetFocus,
      ),
      SettingsCategory.integrations => MeridianSettingsGroup(
        children: [
          if (widget.hosting case final hosting?)
            HostingIntegrationsSection(
              hosting: hosting,
              showResources: false,
              showBinding: false,
              repository: hostingRepository?.canonicalIdentity,
              remotes: [
                for (final remote
                    in hostingRepository?.session?.snapshot.refs.remotes ??
                        const <RepositoryRemote>[])
                  HostingRemote(
                    name: remote.name,
                    url: utf8.decode(remote.displayUrl, allowMalformed: true),
                  ),
              ],
              onOpenUrl: widget.onOpenUrl,
              onCheckout: (_) {},
              onResourcesChanged: (_, _, _) {},
            ),
        ],
      ),
      SettingsCategory.repositoryBinding => MeridianSettingsGroup(
        children: [
          if (widget.hosting case final hosting?)
            HostingIntegrationsSection(
              hosting: hosting,
              onOpenAccounts: () =>
                  setState(() => _category = SettingsCategory.integrations),
              showResources: false,
              showAccounts: false,
              repository: hostingRepository?.canonicalIdentity,
              remotes: [
                for (final remote
                    in hostingRepository?.session?.snapshot.refs.remotes ??
                        const <RepositoryRemote>[])
                  HostingRemote(
                    name: remote.name,
                    url: utf8.decode(remote.displayUrl, allowMalformed: true),
                  ),
              ],
              onOpenUrl: widget.onOpenUrl,
              onCheckout: (_) {},
              onResourcesChanged: (_, _, _) {},
            ),
        ],
      ),
      SettingsCategory.remoteHosts => MeridianSettingsGroup(
        children: [
          if (widget.remote case final remote? when remote.enabled)
            RemoteHostsSettings(controller: remote),
        ],
      ),
      SettingsCategory.customCommands => MeridianSettingsGroup(
        children: [
          if (widget.repository?.session == null)
            Text(context.l10n.commandRepositoryRequired)
          else
            IntegrationsPanel(
              embedded: true,
              repositories: widget.repositories,
              focusAddForm:
                  widget.initialCategory == SettingsCategory.customCommands,
              settings: widget.settings,
              hosting: null,
              hostingReview: null,
              active: widget.repository,
              onResourcesChanged: (_, _, _) {},
              onCheckout: (_) {},
              onClose: () {},
            ),
        ],
      ),
      SettingsCategory.diffRenderer => MeridianSettingsGroup(
        children: [
          Text(context.l10n.diffRendererContainmentHelp),
          if (widget.repository?.session == null)
            Text(context.l10n.commandRepositoryRequired)
          else
            DiffRendererSettingsCard(
              repositories: widget.repositories,
              settings: widget.settings,
            ),
        ],
      ),
      SettingsCategory.diffView => diffViewSettingsPage(
        context,
        appearance.diffView,
        (preferences) =>
            _updateAppearance(appearance.copyWith(diffView: preferences)),
      ),
      SettingsCategory.shortcuts => shortcutSettingsPage(
        context,
        shortcutLabels: shortcutLabels,
        onReset: _resetShortcuts,
        updateShortcut: _updateShortcut,
        onInvalid: () =>
            setState(() => _saveFailure = context.l10n.settingsShortcutInvalid),
      ),
      SettingsCategory.accessibility => accessibilitySettingsPage(
        context,
        appearance,
        _updateAppearance,
      ),
      SettingsCategory.updates => switch (widget.updates) {
        final updates? => UpdatesSettings(updates: updates),
        null => const SizedBox.shrink(),
      },
      SettingsCategory.diagnostics => const DiagnosticSettings(),
      SettingsCategory.licenses => MeridianSettingsGroup(
        children: [
          MeridianButton(
            key: const Key('settings-open-licenses'),
            variant: MeridianButtonVariant.secondary,
            onPressed: () =>
                Navigator.pop(context, SettingsDestination.licenses),
            label: context.l10n.settingsOpenLicenses,
          ),
        ],
      ),
    };
  }
}
