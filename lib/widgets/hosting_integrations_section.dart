import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'author_avatar.dart';
import 'native_menu.dart';
import 'gitlama_list_well.dart';
import 'gitlama_selection_field.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/hosting.dart';
import '../models/settings.dart';
import '../services/hosting_connection_service.dart';
import '../services/hosting_repository_session.dart';

import 'package:meridian_ui/meridian_ui.dart';

import '../app/gitlama_layout.dart';

final class HostingIntegrationsSection extends StatefulWidget {
  const HostingIntegrationsSection({
    required this.hosting,
    required this.repository,
    required this.remotes,
    required this.onOpenUrl,
    required this.onCheckout,
    required this.onResourcesChanged,
    this.session,
    this.onReview,
    this.checkoutDisabledReason,
    this.onOpenAccounts,
    this.showConfiguration = true,
    this.showAccounts = true,
    this.showBinding = true,
    this.showResources = true,
    this.createChangeRequests,
    super.key,
  });

  final HostingConnectionService hosting;

  /// Requests to open the provider page that creates a pull request for the
  /// bound repository, for example from the workspace's command.
  final Stream<void>? createChangeRequests;
  final HostingRepositorySession? session;
  final VoidCallback? onOpenAccounts;
  final bool showConfiguration;
  final bool showAccounts;
  final bool showBinding;
  final bool showResources;
  final NativePathIdentity? repository;
  final List<HostingRemote> remotes;
  final Future<void> Function(String url) onOpenUrl;
  final ValueChanged<HostingChangeRequest> onCheckout;

  /// Repository write restrictions, independent of provider API access.
  final String? checkoutDisabledReason;
  final void Function(
    HostingChangeRequest pull,
    String connectionId,
    String providerRepository,
  )?
  onReview;
  final void Function(
    HostingBindingResolution? binding,
    HostingResources resources,
    bool stale,
  )
  onResourcesChanged;

  @override
  State<HostingIntegrationsSection> createState() =>
      HostingIntegrationsSectionState();
}

final class HostingIntegrationsSectionState
    extends State<HostingIntegrationsSection> {
  final _connectionId = TextEditingController();
  // Filled from the native preset defaults.
  final _webBase = TextEditingController();
  final _apiBase = TextEditingController();
  final _oauthClientId = TextEditingController();
  final _providerRepository = TextEditingController();
  final _filter = TextEditingController();
  var _addConnectionExpanded = false;
  HostingPreset _preset = HostingPreset.gitHub;
  HostingAuthentication _authentication = HostingAuthentication.oauth;
  bool _githubCliAvailable = false;
  bool _gitlabCliAvailable = false;
  late final HostingRepositorySession _session;
  StreamSubscription<void>? _sessionSubscription;
  HostingBindingResolution? get _binding => _session.binding;
  HostingResources get _resources => _session.resources;
  HostingResourceSnapshot? get _resourceSnapshot => _session.snapshot;
  HostingOAuthSnapshot? _oauth;
  String? _selectedConnectionId;
  List<int>? _selectedRemote;
  Object? _localFailure;
  Object? get _failure => _localFailure ?? _session.failure;
  set _failure(Object? value) => _localFailure = value;
  String? _formError;
  int? _openedOAuthRequestId;
  int? _newConnectionAuthorizationRequestId;
  bool _apiManuallyEdited = false;
  HostingPresetDefaults? _defaults;
  var _defaultsRequest = 0;
  StreamSubscription<HostingOAuthSnapshot>? _oauthFollow;
  StreamSubscription<void>? _changeRequests;
  var _localBusy = false;
  bool get _busy => _localBusy || _session.busy;
  set _busy(bool value) => _localBusy = value;

  @override
  void initState() {
    super.initState();
    _changeRequests = widget.createChangeRequests?.listen(
      (_) => unawaited(_createChangeRequest()),
    );
    _filter.addListener(_filterChanged);
    _session =
        widget.session ??
        widget.hosting.openRepositorySession(
          showResources: widget.showResources,
        );
    _sessionSubscription = _session.changes.listen((_) => _sessionChanged());
    unawaited(_detectClis());
    unawaited(_loadDefaults());
    if (widget.session == null) {
      unawaited(_session.update(widget.repository, widget.remotes));
    }
    _updateBindingFields();
  }

  @override
  void didUpdateWidget(covariant HostingIntegrationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.createChangeRequests != oldWidget.createChangeRequests) {
      unawaited(_changeRequests?.cancel());
      _changeRequests = widget.createChangeRequests?.listen(
        (_) => unawaited(_createChangeRequest()),
      );
    }
    if (widget.session == null) {
      unawaited(_session.update(widget.repository, widget.remotes));
    }
  }

  void _updateBindingFields() {
    final binding = _binding;
    _selectedConnectionId = binding?.connectionId;
    _selectedRemote = binding == null || binding.remote.isEmpty
        ? widget.remotes.firstOrNull?.name
        : binding.remote;
    _providerRepository.text = binding?.providerRepository ?? '';
  }

  HostingBindingResolution? _lastBinding;
  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      if (!identical(_lastBinding, _binding)) {
        _lastBinding = _binding;
        _updateBindingFields();
      }
    });
    widget.onResourcesChanged(
      _binding,
      _resources,
      _resourceSnapshot?.stale ?? false,
    );
  }

  @override
  void dispose() {
    unawaited(_oauthFollow?.cancel());
    unawaited(_changeRequests?.cancel());
    unawaited(_sessionSubscription?.cancel());
    if (widget.session == null) _session.dispose();
    if (_oauth case final oauth? when !oauth.isTerminal) {
      unawaited(widget.hosting.cancelAuthorization(oauth.requestId));
    }
    _connectionId.dispose();
    _webBase.dispose();
    _apiBase.dispose();
    _oauthClientId.dispose();
    _providerRepository.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _filterChanged() => setState(() {});

  Future<void> _detectClis() async {
    try {
      final results = await Future.wait([
        widget.hosting.githubCliAvailable(),
        widget.hosting.gitlabCliAvailable(),
      ]);
      if (mounted) {
        setState(() {
          _githubCliAvailable = results[0];
          _gitlabCliAvailable = results[1];
        });
      }
    } on Object {
      // OAuth setup remains available when optional CLI detection fails.
    }
  }

  Future<void> _resolveBinding({required bool refresh}) =>
      _session.resolve(refresh: refresh);

  Future<void> _refresh({required bool manual, int page = 1}) {
    _localFailure = null;
    return _session.refresh(manual: manual, page: page);
  }

  Future<void> _saveBinding() async {
    final repository = widget.repository;
    final connectionId = _selectedConnectionId;
    final remote = _selectedRemote;
    final providerRepository = _providerRepository.text.trim();
    if (repository == null ||
        connectionId == null ||
        remote == null ||
        providerRepository.isEmpty ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.hosting.saveBinding(
        HostingBindingOverride(
          repository: repository,
          remote: remote,
          connectionId: connectionId,
          providerRepository: providerRepository,
        ),
      );
      await _resolveBinding(refresh: true);
    } on Object {
      if (mounted) setState(() => _failure = const _SettingsFailure());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearBinding() async {
    final repository = widget.repository;
    if (repository == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.hosting.clearBinding(repository);
      await _resolveBinding(refresh: true);
    } on Object {
      if (mounted) setState(() => _failure = const _SettingsFailure());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectPreset(HostingPreset preset) {
    setState(() {
      _preset = preset;
      _authentication = HostingAuthentication.oauth;
      _apiManuallyEdited = false;
      _formError = null;
      _defaults = null;
      _webBase.clear();
      _apiBase.clear();
    });
    unawaited(_loadDefaults());
  }

  static bool _selfHosted(HostingPreset preset) =>
      preset == HostingPreset.gitLabSelfManaged ||
      preset == HostingPreset.forgejo ||
      preset == HostingPreset.gitHubEnterprise;

  /// Reads the native defaults for the selected preset and, for a self-hosted
  /// preset, the entered web origin. Public presets fill both fields; a
  /// self-hosted preset derives the API field unless the user edited it.
  /// Answers that a newer request replaced only return their value.
  Future<HostingPresetDefaults?> _loadDefaults() async {
    final preset = _preset;
    final selfHosted = _selfHosted(preset);
    final webBase = _webBase.text.trim();
    final request = ++_defaultsRequest;
    HostingPresetDefaults? defaults;
    try {
      defaults = await widget.hosting.presetDefaults(
        preset,
        webBase: selfHosted && webBase.isNotEmpty ? webBase : null,
      );
    } on Object {
      defaults = null;
    }
    if (!mounted || request != _defaultsRequest) return defaults;
    setState(() {
      _defaults = defaults;
      if (!selfHosted) {
        _webBase.text = defaults?.webBaseUrl ?? '';
        _apiBase.text = defaults?.apiBaseUrl ?? '';
      } else if (!_apiManuallyEdited) {
        _apiBase.text = defaults?.apiBaseUrl ?? '';
      }
    });
    return defaults;
  }

  /// The validated web origin of the current form, from the native rules.
  String? _normalizedWebBase() => _defaults?.webBaseUrl;

  void _webBaseChanged(String value) => unawaited(_loadDefaults());

  /// The authentication methods the preset allows and this computer offers.
  List<HostingAuthentication> get _availableAuthentications => [
    for (final method
        in _defaults?.authentications ?? const [HostingAuthentication.oauth])
      if (method == HostingAuthentication.oauth ||
          (method == HostingAuthentication.gitHubCli && _githubCliAvailable) ||
          (method == HostingAuthentication.gitLabCli && _gitlabCliAvailable))
        method,
  ];

  Future<void> _openOAuthBrowser(HostingOAuthSnapshot snapshot) async {
    final url = snapshot.browserUrl;
    if (url == null || _openedOAuthRequestId == snapshot.requestId) return;
    _openedOAuthRequestId = snapshot.requestId;
    try {
      await widget.onOpenUrl(url.toString());
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  /// The provider setup guide: numbered steps, the exact values to paste
  /// in code, and what needs no secret as a closing caption.
  Future<void> _showSetupGuide() => showMeridianDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = context.l10n;
      final preset = _preset;
      final webBase = _normalizedWebBase() ?? '';
      final host = Uri.tryParse(webBase)?.host ?? '';
      final server = host.isEmpty ? l10n.hostingGuideServerPlaceholder : host;
      final gitHub =
          preset == HostingPreset.gitHub ||
          preset == HostingPreset.gitHubEnterprise;
      final steps = switch (_authentication) {
        HostingAuthentication.gitHubCli => [
          HostingGuideStep(
            l10n.hostingStepCliSignIn(l10n.hostingGitHubCli),
            code: preset == HostingPreset.gitHub
                ? 'gh auth login'
                : 'gh auth login --hostname $server',
          ),
          HostingGuideStep(
            l10n.hostingStepCliReturn(l10n.hostingConnectWithCli),
          ),
        ],
        HostingAuthentication.gitLabCli => [
          HostingGuideStep(
            l10n.hostingStepCliSignIn(l10n.hostingGitLabCli),
            code: preset == HostingPreset.gitLab
                ? 'glab auth login'
                : 'glab auth login --hostname $server',
          ),
          HostingGuideStep(
            l10n.hostingStepCliReturn(l10n.hostingConnectWithGitLabCli),
          ),
        ],
        HostingAuthentication.oauth => [
          if (preset == HostingPreset.gitLabSelfManaged ||
              preset == HostingPreset.forgejo ||
              preset == HostingPreset.gitHubEnterprise)
            HostingGuideStep(l10n.hostingStepEnterServer(l10n.hostingWebUrl)),
          HostingGuideStep(switch (preset) {
            HostingPreset.gitHub => l10n.hostingStepCreateGitHub,
            HostingPreset.gitHubEnterprise => l10n.hostingStepCreateEnterprise,
            HostingPreset.gitLab ||
            HostingPreset.gitLabSelfManaged => l10n.hostingStepCreateGitLab,
            HostingPreset.forgejo => l10n.hostingStepCreateForgejo,
            HostingPreset.codeberg => l10n.hostingStepCreateCodeberg,
          }),
          if (preset == HostingPreset.forgejo ||
              preset == HostingPreset.codeberg)
            HostingGuideStep(l10n.hostingStepPublicClient),
          if (gitHub)
            HostingGuideStep(l10n.hostingStepDeviceFlow)
          else
            HostingGuideStep(
              l10n.hostingStepRedirect,
              code: hostingOAuthRedirectUri,
            ),
          HostingGuideStep(
            preset == HostingPreset.gitLab ||
                    preset == HostingPreset.gitLabSelfManaged
                ? l10n.hostingStepCopyApplicationId(l10n.hostingOAuthClientId)
                : l10n.hostingStepCopyClientId(l10n.hostingOAuthClientId),
          ),
          HostingGuideStep(
            gitHub
                ? l10n.hostingStepAuthorizeDevice(l10n.hostingSaveAuthorize)
                : l10n.hostingStepAuthorizeBrowser(l10n.hostingSaveAuthorize),
          ),
        ],
      };
      final note = switch (_authentication) {
        HostingAuthentication.gitHubCli ||
        HostingAuthentication.gitLabCli => l10n.hostingGuideCliNote,
        HostingAuthentication.oauth => switch (preset) {
          HostingPreset.forgejo =>
            '${l10n.hostingGuideNoSecret} ${l10n.hostingGuideForgejoNote}',
          HostingPreset.gitHubEnterprise =>
            '${l10n.hostingGuideNoSecret} ${l10n.hostingGuideEnterpriseNote}',
          _ => l10n.hostingGuideNoSecret,
        },
      };
      final settingsUrl = switch (preset) {
        HostingPreset.gitHub ||
        HostingPreset.gitHubEnterprise => '$webBase/settings/developers',
        HostingPreset.gitLab || HostingPreset.gitLabSelfManaged =>
          '$webBase/-/user_settings/applications',
        HostingPreset.forgejo ||
        HostingPreset.codeberg => '$webBase/user/settings/applications',
      };
      final canOpenSettings =
          _authentication == HostingAuthentication.oauth &&
          Uri.tryParse(settingsUrl)?.host.isNotEmpty == true;
      return MeridianDialog(
        key: const ValueKey('hosting-setup-guide-dialog'),
        width: MeridianLayout.dialogFormWidth,
        onClose: () => Navigator.pop(dialogContext),
        title: l10n.hostingGuideTitle(_presetLabel(preset)),
        content: HostingGuideSteps(steps: steps, note: note),
        actions: [
          if (canOpenSettings)
            MeridianButton(
              label: l10n.hostingGuideOpenSettings,
              icon: 'external-link',
              variant: MeridianButtonVariant.primary,
              onPressed: () async {
                try {
                  await widget.onOpenUrl(settingsUrl);
                } on Object catch (error) {
                  if (mounted) setState(() => _failure = error);
                }
              },
            ),
        ],
      );
    },
  );

  Future<HostingConnection?> _draftConnection() async {
    final id = _connectionId.text.trim();
    final l10n = context.l10n;
    if (id.isEmpty) {
      setState(() => _formError = l10n.hostingGuideEnterName);
      return null;
    }
    if (widget.hosting.connections.any((connection) => connection.id == id)) {
      setState(() => _formError = l10n.hostingGuideNameInUse);
      return null;
    }
    if (_authentication == HostingAuthentication.oauth &&
        _oauthClientId.text.trim().isEmpty) {
      setState(() => _formError = l10n.hostingGuideEnterClientId);
      return null;
    }
    // The native rules validate the entered origin; the form keeps no copy.
    final defaults = await _loadDefaults();
    if (!mounted) return null;
    final apiBase = _apiBase.text.trim();
    if (defaults == null || defaults.preset != _preset || apiBase.isEmpty) {
      setState(() => _formError = l10n.hostingGuideEnterServer);
      return null;
    }
    setState(() => _formError = null);
    return HostingConnection(
      id: id,
      preset: _preset,
      login: '',
      webBaseUrl: defaults.webBaseUrl,
      apiBaseUrl: apiBase,
      oauthClientId: _oauthClientId.text.trim(),
      authentication: _authentication,
      enabled: true,
      refreshEnabled: true,
      capabilities: defaults.capabilities,
      credentialIdentity: 'credential:$id',
    );
  }

  void _finishNewConnection() {
    _newConnectionAuthorizationRequestId = null;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _addConnectionExpanded = false;
      _connectionId.clear();
      _webBase.clear();
      _apiBase.clear();
      _oauthClientId.clear();
      _preset = HostingPreset.gitHub;
      _authentication = HostingAuthentication.oauth;
      _apiManuallyEdited = false;
      _openedOAuthRequestId = null;
      _oauth = null;
      _formError = null;
      _failure = null;
      _defaults = null;
    });
    unawaited(_loadDefaults());
  }

  Future<void> _authorize(
    HostingConnection connection, {
    bool fromNewConnection = false,
  }) async {
    if (_busy) return;
    unawaited(_oauthFollow?.cancel());
    _oauthFollow = null;
    _newConnectionAuthorizationRequestId = null;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final snapshot = await widget.hosting.startAuthorization(connection);
      if (!mounted) return;
      setState(() {
        _oauth = snapshot;
        if (snapshot.failure != null) _failure = snapshot.failure;
      });
      unawaited(_openOAuthBrowser(snapshot));
      if (!snapshot.isTerminal) {
        if (fromNewConnection) {
          _newConnectionAuthorizationRequestId = snapshot.requestId;
        }
        _scheduleOAuthPoll(connection.id, snapshot.requestId);
      } else if (snapshot.state == HostingOAuthState.succeeded) {
        await _resolveBinding(refresh: true);
        if (mounted) {
          if (fromNewConnection) {
            _finishNewConnection();
          } else {
            setState(() => _oauth = null);
          }
        }
      }
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scheduleOAuthPoll(String connectionId, int requestId) {
    unawaited(_oauthFollow?.cancel());
    _oauthFollow = widget.hosting
        .followAuthorization(connectionId: connectionId, requestId: requestId)
        .listen(
          (snapshot) => unawaited(_oauthProgress(snapshot)),
          onError: (Object error) {
            if (mounted) setState(() => _failure = error);
          },
        );
  }

  Future<void> _oauthProgress(HostingOAuthSnapshot snapshot) async {
    if (!mounted) return;
    final requestId = snapshot.requestId;
    setState(() {
      _oauth = snapshot;
      if (snapshot.failure != null) _failure = snapshot.failure;
    });
    unawaited(_openOAuthBrowser(snapshot));
    if (snapshot.state == HostingOAuthState.succeeded) {
      await _resolveBinding(refresh: true);
      if (mounted) {
        if (_newConnectionAuthorizationRequestId == requestId) {
          _finishNewConnection();
        } else {
          setState(() => _oauth = null);
        }
      }
    } else if (snapshot.isTerminal &&
        _newConnectionAuthorizationRequestId == requestId) {
      _newConnectionAuthorizationRequestId = null;
    }
  }

  Future<void> _removeConnection(HostingConnection connection) async {
    final confirmed = await showMeridianConfirm(
      context,
      title: context.l10n.hostingRemove,
      description: context.l10n.hostingRemoveConfirm(connection.id),
      confirmLabel: context.l10n.hostingRemove,
      cancelLabel: context.l10n.cancel,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await widget.hosting.removeConnection(connection.id);
      await _resolveBinding(refresh: true);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _toggleConnection(
    HostingConnection connection, {
    bool? enabled,
    bool? refreshEnabled,
  }) async {
    try {
      await widget.hosting.saveConnection(
        connection.copyWith(enabled: enabled, refreshEnabled: refreshEnabled),
      );
      await _resolveBinding(refresh: true);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _createChangeRequest() async {
    if (_binding?.connectionId == null ||
        _binding?.providerRepository == null) {
      await _resolveBinding(refresh: false);
    }
    if (!mounted) return;
    final binding = _binding;
    if (binding?.connectionId == null || binding?.providerRepository == null) {
      return;
    }
    try {
      final link = await widget.hosting.resourceLink(
        connectionId: binding!.connectionId!,
        providerRepository: binding.providerRepository!,
        kind: HostingResourceKind.createChangeRequest,
      );
      await widget.onOpenUrl(link.toString());
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Widget _inset(Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.paneAlt,
        borderRadius: BorderRadius.circular(context.meridian.radius.lg),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connections = widget.hosting.connections;
    final binding = _binding;
    final boundConnection = connections
        .where((connection) => connection.id == binding?.connectionId)
        .firstOrNull;
    final query = _filter.text.trim().toLowerCase();
    final pulls = _resources.changeRequests
        .where(
          (pull) =>
              query.isEmpty ||
              pull.title.toLowerCase().contains(query) ||
              pull.author.toLowerCase().contains(query) ||
              pull.number.toString().contains(query),
        )
        .toList(growable: false);
    final issues = _resources.issues
        .where(
          (issue) =>
              query.isEmpty ||
              issue.title.toLowerCase().contains(query) ||
              issue.author.toLowerCase().contains(query) ||
              issue.number.toString().contains(query),
        )
        .toList(growable: false);
    final expanded = widget.hosting.expandedNodes.toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showConfiguration && widget.showAccounts) ...[
          Text(l10n.hostingAccounts, style: context.text.bodyStrong),
          const SizedBox(height: MeridianSpace.space5),
          if (connections.isEmpty)
            _inset(
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space8),
                child: Row(
                  children: [
                    const MeridianIcon('cloud-off'),
                    const SizedBox(width: MeridianSpace.space5),
                    Expanded(child: Text(l10n.hostingNoConnections)),
                  ],
                ),
              ),
            ),
          for (final connection in connections) ...[
            _inset(
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MeridianListRow(
                      title: connection.id,
                      subtitle: connection.login.isEmpty
                          ? _presetLabel(connection.preset)
                          : '${_presetLabel(connection.preset)} · ${connection.login}',
                      leading: const MeridianIcon('cloud'),
                      titleTrailing: MeridianCount(
                        label: connection.enabled
                            ? l10n.hostingStateEnabled
                            : l10n.hostingStateDisabled,
                        tone: connection.enabled
                            ? MeridianCountTone.accent
                            : MeridianCountTone.quiet,
                      ),
                    ),
                    const SizedBox(height: MeridianSpace.space5),
                    MeridianSwitch(
                      label: l10n.hostingEnabled,
                      value: connection.enabled,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                _toggleConnection(connection, enabled: value),
                    ),
                    MeridianSwitch(
                      label: l10n.hostingBackgroundRefresh,
                      value: connection.refreshEnabled,
                      onChanged: !connection.enabled || _busy
                          ? null
                          : (value) => _toggleConnection(
                              connection,
                              refreshEnabled: value,
                            ),
                    ),
                    const SizedBox(height: MeridianSpace.space4),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: MeridianSpace.space4,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        MeridianButton(
                          label: l10n.hostingReauthorize,
                          variant: MeridianButtonVariant.quiet,
                          onPressed: _busy
                              ? null
                              : () => _authorize(connection),
                        ),
                        MeridianButton(
                          label: l10n.hostingRemove,
                          icon: 'trash',
                          variant: MeridianButtonVariant.dangerQuiet,
                          onPressed: _busy
                              ? null
                              : () => _removeConnection(connection),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MeridianSpace.space5),
          ],
          const SizedBox(height: MeridianSpace.space5),
          FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: _inset(
              MeridianDisclosure(
                expanded: _addConnectionExpanded,
                onExpansionChanged: (value) =>
                    setState(() => _addConnectionExpanded = value),
                key: const Key('hosting-add-connection'),
                title: l10n.hostingAddConnection,
                child: Padding(
                  padding: const EdgeInsets.all(MeridianSpace.space6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: MeridianSelect<HostingPreset>(
                          value: _preset,
                          values: HostingPreset.values,
                          valueLabel: _presetLabel,
                          label: l10n.hostingPreset,
                          showLabel: true,
                          expand: true,
                          onChanged: _busy ? null : _selectPreset,
                        ),
                      ),
                      const SizedBox(height: MeridianSpace.space4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: MeridianButton(
                            key: const Key('hosting-setup-guide'),
                            label: l10n.hostingGuideAction,
                            icon: 'circle-help',
                            variant: MeridianButtonVariant.quiet,
                            onPressed: _showSetupGuide,
                          ),
                        ),
                      ),
                      const SizedBox(height: MeridianSpace.space8),
                      if (_availableAuthentications.length > 1) ...[
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(3),
                          child: MeridianSelect<HostingAuthentication>(
                            key: ValueKey('hosting-auth-${_preset.name}'),
                            value: _authentication,
                            values: _availableAuthentications,
                            valueLabel: (value) => switch (value) {
                              HostingAuthentication.oauth =>
                                l10n.hostingOAuthApplication,
                              HostingAuthentication.gitHubCli =>
                                l10n.hostingGitHubCli,
                              HostingAuthentication.gitLabCli =>
                                l10n.hostingGitLabCli,
                            },
                            label: l10n.hostingAuthenticationMethod,
                            showLabel: true,
                            expand: true,
                            onChanged: _busy
                                ? null
                                : (value) =>
                                      setState(() => _authentication = value),
                          ),
                        ),
                        if (_authentication ==
                            HostingAuthentication.gitHubCli) ...[
                          const SizedBox(height: MeridianSpace.space4),
                          Text(l10n.hostingGitHubCliHint),
                        ],
                        if (_authentication ==
                            HostingAuthentication.gitLabCli) ...[
                          const SizedBox(height: MeridianSpace.space4),
                          Text(l10n.hostingGitLabCliHint),
                        ],
                        const SizedBox(height: MeridianSpace.space8),
                      ],
                      _HostingTextField(
                        focusOrder: 4,
                        fieldKey: const Key('hosting-connection-id'),
                        label: l10n.hostingConnectionId,
                        controller: _connectionId,
                        enabled: !_busy,
                      ),
                      if (_selfHosted(_preset)) ...[
                        const SizedBox(height: MeridianSpace.space8),
                        _HostingTextField(
                          focusOrder: 5,
                          fieldKey: const Key('hosting-web-url'),
                          label: l10n.hostingWebUrl,
                          controller: _webBase,
                          enabled: !_busy,
                          keyboardType: TextInputType.url,
                          onChanged: _webBaseChanged,
                        ),
                        const SizedBox(height: MeridianSpace.space8),
                        _HostingTextField(
                          focusOrder: 6,
                          fieldKey: const Key('hosting-api-url'),
                          label: l10n.hostingApiUrl,
                          controller: _apiBase,
                          enabled: !_busy,
                          keyboardType: TextInputType.url,
                          onChanged: (_) => _apiManuallyEdited = true,
                        ),
                      ],
                      const SizedBox(height: MeridianSpace.space8),
                      if (_authentication == HostingAuthentication.oauth)
                        _HostingTextField(
                          focusOrder: 7,
                          fieldKey: const Key('hosting-oauth-client-id'),
                          label: l10n.hostingOAuthClientId,
                          controller: _oauthClientId,
                          enabled: !_busy,
                        ),
                      if (_formError case final error?) ...[
                        const SizedBox(height: MeridianSpace.space5),
                        Text(
                          error,
                          style: context.text.body.copyWith(
                            color: context.colors.danger,
                          ),
                        ),
                      ],
                      if (_failure case final failure?) ...[
                        const SizedBox(height: MeridianSpace.space5),
                        Text(
                          _settingsFailure(failure)
                              ? l10n.hostingSettingsFailure
                              : l10n.hostingFailure(
                                  _failureReason(l10n, failure),
                                ),
                          style: context.text.body.copyWith(
                            color: context.colors.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: MeridianSpace.space8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(8),
                          child: MeridianButton(
                            label: switch (_authentication) {
                              HostingAuthentication.gitHubCli =>
                                l10n.hostingConnectWithCli,
                              HostingAuthentication.gitLabCli =>
                                l10n.hostingConnectWithGitLabCli,
                              HostingAuthentication.oauth =>
                                l10n.hostingSaveAuthorize,
                            },
                            variant: MeridianButtonVariant.primary,
                            onPressed: _busy
                                ? null
                                : () async {
                                    final connection = await _draftConnection();
                                    if (connection != null) {
                                      unawaited(
                                        _authorize(
                                          connection,
                                          fromNewConnection: true,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_oauth case final oauth?) ...[
            const SizedBox(height: MeridianSpace.space5),
            _inset(
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.hostingAuthorizationWaiting),
                    if (oauth.userCode case final code?) ...[
                      const SizedBox(height: MeridianSpace.space4),
                      SelectableText(
                        contextMenuBuilder: nativeTextContextMenuBuilder,
                        l10n.hostingAuthorizationCode(code),
                      ),
                    ],
                    if (oauth.browserUrl case final browserUrl?) ...[
                      const SizedBox(height: MeridianSpace.space4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: MeridianButton(
                          label: l10n.hostingOpenBrowser,
                          variant: MeridianButtonVariant.quiet,
                          onPressed: () =>
                              widget.onOpenUrl(browserUrl.toString()),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
        if (widget.showConfiguration && widget.showBinding) ...[
          Text(l10n.hostingBinding, style: context.text.bodyStrong),
          const SizedBox(height: MeridianSpace.space5),
          _inset(
            Padding(
              padding: const EdgeInsets.all(MeridianSpace.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.repository == null)
                    Text(l10n.commandRepositoryRequired)
                  else if (connections.isEmpty) ...[
                    Text(l10n.hostingConnectBeforeBinding),
                    if (widget.onOpenAccounts != null) ...[
                      const SizedBox(height: MeridianSpace.space5),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: MeridianButton(
                          label: l10n.hostingAddConnection,
                          icon: 'link',
                          variant: MeridianButtonVariant.secondary,
                          onPressed: widget.onOpenAccounts,
                        ),
                      ),
                    ],
                  ] else ...[
                    if (binding?.state == HostingBindingState.unmatched) ...[
                      Text(l10n.hostingNoBinding),
                      const SizedBox(height: MeridianSpace.space8),
                    ],
                    if (binding?.state == HostingBindingState.ambiguous) ...[
                      Text(l10n.hostingAmbiguousBinding),
                      const SizedBox(height: MeridianSpace.space8),
                    ],
                    GitLamaSelectionField<String>(
                      key: const Key('hosting-binding-connection'),
                      initialValue:
                          connections.any(
                            (value) => value.id == _selectedConnectionId,
                          )
                          ? _selectedConnectionId
                          : null,
                      label: l10n.hostingConnection,
                      labelAbove: true,
                      icon: 'link',
                      items: [
                        for (final connection in connections.where(
                          (value) => value.enabled,
                        ))
                          GitLamaSelectOption(
                            value: connection.id,
                            label: connection.id,
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _selectedConnectionId = value),
                    ),
                    const SizedBox(height: MeridianSpace.space8),
                    GitLamaSelectionField<String>(
                      key: const Key('hosting-binding-remote'),
                      initialValue: _selectedRemote == null
                          ? null
                          : base64Url.encode(_selectedRemote!),
                      label: l10n.hostingRemote,
                      labelAbove: true,
                      icon: 'cloud',
                      items: [
                        for (final remote in widget.remotes)
                          GitLamaSelectOption(
                            value: base64Url.encode(remote.name),
                            label: utf8.decode(
                              remote.name,
                              allowMalformed: true,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(
                              () => _selectedRemote = value == null
                                  ? null
                                  : base64Url.decode(value),
                            ),
                    ),
                    const SizedBox(height: MeridianSpace.space8),
                    _HostingTextField(
                      fieldKey: const Key('hosting-provider-repository'),
                      label: l10n.hostingProviderRepository,
                      controller: _providerRepository,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: MeridianSpace.space8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: MeridianSpace.space4,
                      runSpacing: MeridianSpace.space4,
                      children: [
                        MeridianButton(
                          label: l10n.hostingAutomaticBinding,
                          variant: MeridianButtonVariant.quiet,
                          onPressed: _busy ? null : _clearBinding,
                        ),
                        MeridianButton(
                          label: l10n.hostingSaveBinding,
                          variant: MeridianButtonVariant.primary,
                          onPressed: _busy ? null : _saveBinding,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (widget.showResources) ...[
          const MeridianHairline(),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.hostingResources,
                  style: context.text.bodyStrong,
                ),
              ),
              MeridianButton(
                label: l10n.hostingRefresh,
                icon: 'refresh',
                variant: MeridianButtonVariant.quiet,
                onPressed: binding?.state == HostingBindingState.bound && !_busy
                    ? () => _refresh(manual: true)
                    : null,
              ),
              MeridianButton(
                label: l10n.hostingCreateChangeRequest,
                variant: MeridianButtonVariant.secondary,
                onPressed: binding?.state == HostingBindingState.bound
                    ? _createChangeRequest
                    : null,
              ),
            ],
          ),
          MeridianTextField(
            fieldKey: const Key('hosting-resource-filter'),
            controller: _filter,
            label: l10n.hostingFilter,
            variant: MeridianTextFieldVariant.search,
            clearLabel: l10n.searchClear,
          ),
          if (_resourceSnapshot?.state == HostingResourceLoadState.loading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MeridianProgressBar(),
                if (_resources.changeRequests.isNotEmpty ||
                    _resources.issues.isNotEmpty)
                  Text(l10n.hostingLoadingCached),
              ],
            ),
          if (_failure case final failure?)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: MeridianSpace.space4,
              ),
              child: SelectableText(
                contextMenuBuilder: nativeTextContextMenuBuilder,
                _settingsFailure(failure)
                    ? l10n.hostingSettingsFailure
                    : l10n.hostingFailure(_failureReason(l10n, failure)),
                style: context.text.body.copyWith(color: context.colors.danger),
              ),
            ),
          _resourceGroup(
            id: 'changeRequests',
            title: l10n.hostingChangeRequests,
            count: pulls.length,
            forceExpanded: query.isNotEmpty,
            expanded: expanded.contains('changeRequests'),
            children: [
              for (final pull in pulls)
                _pullTile(pull, boundConnection, binding?.providerRepository),
            ],
          ),
          _resourceGroup(
            id: 'issues',
            title: l10n.hostingIssues,
            count: issues.length,
            forceExpanded: query.isNotEmpty,
            expanded: expanded.contains('issues'),
            children: [for (final issue in issues) _issueTile(issue)],
          ),
          if (_resourceSnapshot?.state == HostingResourceLoadState.ready &&
              pulls.isEmpty &&
              issues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(MeridianSpace.space5),
              child: Text(l10n.hostingEmpty),
            ),
          if (_resourceSnapshot?.hasMore == true)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MeridianButton(
                label: l10n.hostingLoadMore,
                variant: MeridianButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => _refresh(
                        manual: true,
                        page: (_resourceSnapshot?.page ?? 1) + 1,
                      ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _resourceGroup({
    required String id,
    required String title,
    required int count,
    required bool forceExpanded,
    required bool expanded,
    required List<Widget> children,
  }) => MeridianDisclosure(
    key: ValueKey('hosting-group-$id-${forceExpanded || expanded}'),
    initiallyExpanded: forceExpanded || expanded,
    title: title,
    trailing: MeridianCount(label: '$count', tone: MeridianCountTone.quiet),
    enabled: !forceExpanded,
    onExpansionChanged: forceExpanded
        ? null
        : (value) {
            final nodes = widget.hosting.expandedNodes.toSet();
            value ? nodes.add(id) : nodes.remove(id);
            widget.hosting.setExpandedNodes(nodes);
          },
    child: Column(children: children),
  );

  Widget _pullTile(
    HostingChangeRequest pull,
    HostingConnection? connection,
    String? providerRepository,
  ) {
    final checkoutSupported =
        connection?.capabilities.contains(
          HostingCapability.changeRequestCheckout,
        ) ==
        true;
    final sameRepository =
        pull.sourceRepository.isNotEmpty &&
        pull.sourceRepository == providerRepository;
    final reviewSupported =
        connection?.capabilities.contains(
              HostingCapability.changeRequestReview,
            ) ==
            true &&
        widget.onReview != null;
    return MeridianListRow(
      key: ValueKey('hosting-pull-${pull.stableId}'),
      leading: AuthorAvatar(
        author: pull.author,
        size: MeridianLayout.avatarSmall,
      ),
      title: '#${pull.number} ${pull.title}',
      subtitle:
          '${pull.author} · ${pull.sourceBranch} → ${pull.targetBranch} · ${pull.checks.state.name}',
      trailing: Wrap(
        children: [
          MeridianButton(
            label: context.l10n.hostingCheckout,
            variant: MeridianButtonVariant.secondary,
            size: MeridianControlSize.small,
            disabledReason: !checkoutSupported
                ? context.l10n.hostingCapabilityUnavailable
                : !sameRepository
                ? context.l10n.hostingForkCheckoutUnavailable
                : widget.checkoutDisabledReason,
            onPressed:
                checkoutSupported &&
                    sameRepository &&
                    widget.checkoutDisabledReason == null
                ? () => widget.onCheckout(pull)
                : null,
          ),
          MeridianButton(
            label: context.l10n.hostingReview,
            variant: MeridianButtonVariant.secondary,
            size: MeridianControlSize.small,
            disabledReason: reviewSupported
                ? null
                : context.l10n.hostingCapabilityUnavailable,
            onPressed: reviewSupported
                ? () => widget.onReview!(
                    pull,
                    connection!.id,
                    providerRepository!,
                  )
                : null,
          ),
          MeridianIconButton(
            label: context.l10n.hostingOpenBrowser,
            icon: 'external-link',
            size: MeridianControlSize.small,
            onPressed: () => widget.onOpenUrl(pull.webUrl),
          ),
        ],
      ),
    );
  }

  Widget _issueTile(HostingIssue issue) => MeridianListRow(
    key: ValueKey('hosting-issue-${issue.stableId}'),
    leading: AuthorAvatar(
      author: issue.author,
      size: MeridianLayout.avatarSmall,
    ),
    title: '#${issue.number} ${issue.title}',
    subtitle: '${issue.author} · ${issue.state.name}',
    trailing: MeridianIconButton(
      label: context.l10n.hostingOpenBrowser,
      icon: 'external-link',
      size: MeridianControlSize.small,
      onPressed: () => widget.onOpenUrl(issue.webUrl),
    ),
  );
}

class _HostingTextField extends StatelessWidget {
  const _HostingTextField({
    required this.label,
    required this.controller,
    required this.enabled,
    this.fieldKey,
    this.keyboardType,
    this.onChanged,
    this.focusOrder,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final Key? fieldKey;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final double? focusOrder;

  @override
  Widget build(BuildContext context) {
    final field = LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < GitLamaLayout.contentMaxWidth;
        final input = MeridianTextField(
          label: label,
          showLabel: stacked,
          fieldKey: fieldKey,
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: onChanged,
        );
        return stacked
            ? input
            : MeridianSettingsRow(label: label, children: [input]);
      },
    );
    return focusOrder == null
        ? field
        : FocusTraversalOrder(
            order: NumericFocusOrder(focusOrder!),
            child: field,
          );
  }
}

final class _SettingsFailure {
  const _SettingsFailure();
}

/// Whether [failure] is a rejected settings save, not a provider answer.
bool _settingsFailure(Object failure) =>
    failure is _SettingsFailure || failure is SettingsException;

/// Where the provider sends the browser back after OAuth sign-in; the
/// native hosting runtime listens there (`LOOPBACK_CALLBACK`).
const hostingOAuthRedirectUri = 'http://127.0.0.1:49351/oauth/callback';

/// One instruction of a provider setup guide, with the exact text to paste
/// or run, if any.
@immutable
final class HostingGuideStep {
  const HostingGuideStep(this.text, {this.code});

  final String text;
  final String? code;
}

/// A setup guide's numbered steps, then a muted caption.
class HostingGuideSteps extends StatelessWidget {
  const HostingGuideSteps({required this.steps, this.note, super.key});

  final List<HostingGuideStep> steps;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        for (final (index, step) in steps.indexed)
          Row(
            key: ValueKey('hosting-guide-step-${index + 1}'),
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: MeridianSpace.space4,
            children: [
              GitLamaStepNumber(index + 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: MeridianSpace.space3,
                  children: [
                    Text(
                      step.text,
                      style: context.text.body.copyWith(color: colors.ink),
                    ),
                    if (step.code case final code?)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.paneAlt,
                          borderRadius: BorderRadius.circular(
                            context.meridian.radius.md,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: MeridianSpace.space5,
                            vertical: MeridianSpace.space4,
                          ),
                          child: SelectableText(
                            contextMenuBuilder: nativeTextContextMenuBuilder,
                            code,
                            style: context.text.codeSm.copyWith(
                              color: colors.ink,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        if (note case final note?)
          Text(
            note,
            style: context.text.caption.copyWith(color: colors.inkMuted),
          ),
      ],
    );
  }
}

String _presetLabel(HostingPreset preset) => switch (preset) {
  HostingPreset.gitHub => 'GitHub',
  HostingPreset.gitLab => 'GitLab',
  HostingPreset.gitLabSelfManaged => 'GitLab Self-Managed',
  HostingPreset.forgejo => 'Forgejo',
  HostingPreset.codeberg => 'Codeberg',
  HostingPreset.gitHubEnterprise => 'GitHub Enterprise Server',
};

/// The cause of a transport failure in words; other failures keep their code.
String _failureReason(AppLocalizations l10n, Object failure) =>
    switch (failure) {
      HostingOAuthFailure.invalidConnection ||
      HostingOAuthException(
        failure: HostingOAuthFailure.invalidConnection,
      ) => l10n.hostingOAuthClientRejected,
      _ => switch (_failureCode(failure)) {
        'notFound' => l10n.hostingFailureNotFound,
        'redirected' => l10n.hostingFailureRedirected,
        'serverError' => l10n.hostingFailureServerError,
        'network' => l10n.hostingFailureNetwork,
        'certificate' => l10n.hostingFailureCertificate,
        'timedOut' => l10n.hostingFailureTimedOut,
        final code => code,
      },
    };

String _failureCode(Object failure) => switch (failure) {
  HostingResourceException(:final failure) => failure.name,
  HostingOAuthException(:final failure) => failure.name,
  HostingException(:final code) => code.name,
  final HostingResourceFailure value => value.name,
  final HostingOAuthFailure value => value.name,
  _ => 'unavailable',
};
