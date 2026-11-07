import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../l10n/l10n.dart';
import '../../models/diff_renderer.dart';
import '../../models/hosting.dart';
import '../../models/integrations.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/repository_session_service.dart';
import '../../services/settings_service.dart';
import '../../services/hosting_connection_service.dart';
import '../../services/hosting_repository_session.dart';
import '../../services/hosting_review_service.dart';
import '../../widgets/hosting_integrations_section.dart';
import '../../widgets/hosting_review_workspace.dart';
import '../app_theme.dart';
import '../../services/workflows/workspace_effects.dart';
import 'workspace_scope.dart';
import '../workspace_shell.dart';
import '../inspector/commit_diff_pane.dart';
import 'labels.dart';

import 'package:meridian_ui/meridian_ui.dart';

import '../gitlama_layout.dart';
import '../../widgets/command_preview.dart';
import '../../widgets/gitlama_list_well.dart';

class IntegrationsPanel extends StatefulWidget {
  const IntegrationsPanel({
    required this.repositories,
    required this.focusAddForm,
    required this.settings,
    required this.hosting,
    required this.hostingReview,
    required this.active,
    required this.onResourcesChanged,
    required this.onCheckout,
    required this.onClose,
    this.hostingSession,
    this.checkoutDisabledReason,
    this.onManageHosting,
    this.embedded = false,
    super.key,
  });

  final RepositorySessionService repositories;
  final bool embedded;
  final bool focusAddForm;
  final SettingsService settings;
  final HostingConnectionService? hosting;
  final HostingRepositorySession? hostingSession;
  final String? checkoutDisabledReason;
  final HostingReviewService? hostingReview;
  final RepositoryTabState? active;
  final void Function(
    HostingBindingResolution? binding,
    HostingResources resources,
    bool stale,
  )
  onResourcesChanged;
  final ValueChanged<HostingChangeRequest> onCheckout;
  final VoidCallback onClose;
  final VoidCallback? onManageHosting;

  @override
  State<IntegrationsPanel> createState() => _IntegrationsPanelState();
}

class _IntegrationsPanelState extends State<IntegrationsPanel> {
  final TextEditingController _id = TextEditingController();
  final FocusNode _idFocus = FocusNode(debugLabel: 'integration-add-name');
  final TextEditingController _executable = TextEditingController();
  final TextEditingController _arguments = TextEditingController();
  final TextEditingController _timeout = TextEditingController(text: '30');
  IntegrationKind _kind = IntegrationKind.custom;
  bool _explicitShell = false;
  bool _wait = true;
  bool _confirmation = true;
  bool _busy = false;
  IntegrationFailureCode? _failure;
  List<IntegrationCandidate> _discovered = const [];
  final StreamController<void> _changeRequests = StreamController.broadcast(
    sync: true,
  );
  StreamSubscription<WorkspaceEffect>? _changeRequestEffects;
  var _effectsBound = false;

  @override
  void initState() {
    super.initState();
    if (widget.embedded) unawaited(_discover());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_effectsBound) return;
    _effectsBound = true;
    // The workspace's Create pull request command reaches the hosting
    // section through this panel; Settings has no such command.
    _changeRequestEffects = listenForEffects(
      context,
      WorkspaceEffectKind.createChangeRequest,
      (_) => _changeRequests.add(null),
    );
  }

  @override
  void dispose() {
    unawaited(_changeRequestEffects?.cancel());
    unawaited(_changeRequests.close());
    _id.dispose();
    _idFocus.dispose();
    _executable.dispose();
    _arguments.dispose();
    _timeout.dispose();
    super.dispose();
  }

  void _focusAddForm() {
    if (!mounted) return;
    _idFocus.requestFocus();
    final focusContext = _idFocus.context;
    if (focusContext == null) return;
    Scrollable.ensureVisible(
      focusContext,
      alignment: 0.45,
      duration: MeridianMotion.of(context, MeridianDurations.layout),
      curve: MeridianDurations.layoutCurve,
    );
  }

  Future<void> _discover() async {
    setState(() => _busy = true);
    try {
      final values = <IntegrationCandidate>[];
      for (final kind in const [
        IntegrationKind.editor,
        IntegrationKind.terminal,
        IntegrationKind.fileManager,
        IntegrationKind.diffTool,
        IntegrationKind.mergeTool,
      ]) {
        values.addAll(await widget.repositories.integrations.discover(kind));
      }
      if (mounted) setState(() => _discovered = values);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (widget.focusAddForm) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _focusAddForm());
        }
      }
    }
  }

  IntegrationVariables get _variables {
    final active = widget.repositories.activeTab;
    final root = active?.canonicalIdentity;
    final status = active?.session?.snapshot.status;
    return IntegrationVariables(
      url: 'https://example.invalid/',
      file: root,
      currentBranch: status?.branchName,
      selectedCommit: status?.headObjectId,
      diffLeft: root,
      diffRight: root,
      mergeBase: root,
      mergeCurrent: root,
      mergeIncoming: root,
      mergeResult: root,
    );
  }

  // Browser handoff needs no checkout and must not pass a remote path to
  // the local external-tool boundary. Hosting validates the URL itself.
  Future<void> _openUrl(String url) => widget.hosting!.openBrowser(url);

  Future<void> _chooseExecutable() async {
    final selected = await openFile();
    if (selected != null && mounted) {
      _executable.text = selected.path;
    }
  }

  NativePathIdentity? _executableIdentity() {
    final platform = widget.repositories.activeTab?.canonicalIdentity?.platform;
    final path = _executable.text.trim();
    if (platform == null || path.isEmpty) return null;
    return NativePathIdentity(
      platform: platform,
      units: platform == NativePathPlatform.windows
          ? path.codeUnits
          : utf8.encode(path),
    );
  }

  IntegrationDefinition? _definition() {
    final id = _id.text.trim();
    final executable = _executableIdentity();
    final timeout = int.tryParse(_timeout.text.trim());
    if (id.isEmpty || executable == null || timeout == null) return null;
    return IntegrationDefinition(
      id: id,
      kind: _kind,
      executable: executable,
      arguments: _arguments.text
          .split('\n')
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      execution: _explicitShell
          ? IntegrationExecution.explicitShell
          : IntegrationExecution.direct,
      launchMode: _wait
          ? IntegrationLaunchMode.wait
          : IntegrationLaunchMode.detached,
      requiresConfirmation: _confirmation,
      timeoutSeconds: timeout,
    );
  }

  Future<void> _validateAndSave() async {
    final definition = _definition();
    if (definition == null || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final preview = await widget.repositories.integrations.preview(
        IntegrationRequest(
          kind: definition.kind,
          configured: definition,
          variables: _variables,
        ),
      );
      await widget.repositories.integrations.cancel(preview);
      await widget.settings.saveIntegration(definition);
      if (mounted) {
        _id.clear();
        _executable.clear();
        _arguments.clear();
        setState(() {});
      }
    } on IntegrationException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(IntegrationRequest request) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final preview = await widget.repositories.integrations.preview(request);
      if (!mounted) return;
      final confirmed = await showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.integrationPreviewTitle,
        content: GitLamaCommandPreviewContent(
          summary: context.l10n.integrationRunSummary,
          commandLines: [preview.executable, ...preview.arguments],
          external: true,
        ),
        confirmLabel: context.l10n.integrationRun,
        cancelLabel: context.l10n.cancel,
      );
      if (!confirmed) {
        await widget.repositories.integrations.cancel(preview);
        return;
      }
      final result = await widget.repositories.integrations.execute(
        preview,
        confirmed: true,
      );
      if (result.failure case final failure?) {
        if (mounted) setState(() => _failure = failure);
      }
    } on IntegrationException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(IntegrationDefinition definition) {
    unawaited(widget.settings.removeIntegration(definition.id));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (_busy) const MeridianProgressBar(),
          if (_failure case final failure?)
            MeridianBanner(
              tone: MeridianBannerTone.error,
              message: _integrationFailureLabel(context, failure),
            ),
          _toolControls(),
        ],
      );
    }
    return MeridianPanel(
      title: context.l10n.hostingResources,
      onClose: widget.onClose,
      width: GitLamaLayout.integrationsPanelWidth,
      padding: EdgeInsets.zero,
      actions: [
        MeridianIconButton(
          label: context.l10n.settingsIntegrations,
          icon: 'settings',
          size: MeridianControlSize.small,
          onPressed: widget.onManageHosting,
        ),
      ],
      child: SizedBox(
        height: floatingPanelBodyHeight(
          context,
          GitLamaLayout.integrationsBodyHeight,
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('integration-list'),
                padding: const EdgeInsets.fromLTRB(
                  MeridianSpace.space5,
                  0,
                  MeridianSpace.space5,
                  MeridianSpace.space5,
                ),
                children: [
                  if (widget.hosting case final hosting?)
                    HostingIntegrationsSection(
                      createChangeRequests: _changeRequests.stream,
                      showConfiguration: false,
                      hosting: hosting,
                      session: widget.hostingSession,
                      repository: widget.active?.canonicalIdentity,
                      remotes: [
                        for (final remote
                            in widget.active?.session?.snapshot.refs.remotes ??
                                const <RepositoryRemote>[])
                          HostingRemote(
                            name: remote.name,
                            url: utf8.decode(
                              remote.displayUrl,
                              allowMalformed: true,
                            ),
                          ),
                      ],
                      onOpenUrl: _openUrl,
                      onCheckout: widget.onCheckout,
                      checkoutDisabledReason: widget.checkoutDisabledReason,
                      onReview: widget.hostingReview == null
                          ? null
                          : (pull, connectionId, providerRepository) {
                              showMeridianDialog<bool>(
                                context: context,
                                builder: (context) => HostingReviewWorkspace(
                                  review: widget.hostingReview!,
                                  connectionId: connectionId,
                                  repository: providerRepository,
                                  pull: pull,
                                  onOpenUrl: _openUrl,
                                ),
                              );
                            },
                      onResourcesChanged: widget.onResourcesChanged,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: MeridianSpace.space4,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: context.text.bodyStrong.copyWith(color: context.colors.ink),
        ),
      ),
      ...children,
    ],
  );

  Widget _empty(String message) => Text(
    message,
    style: context.text.caption.copyWith(color: context.colors.inkMuted),
  );

  Widget _toolControls() {
    final configured = widget.settings.current.integrations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space8,
      children: [
        _section(context.l10n.integrationDiscovered, [
          if (_discovered.isEmpty)
            _empty(context.l10n.integrationDiscoveredEmpty)
          else
            GitLamaListWell(
              itemCount: _discovered.length,
              itemBuilder: (context, index) {
                final candidate = _discovered[index];
                return MeridianListRow(
                  title: integrationKindLabel(context, candidate.kind),
                  subtitle: candidate.id,
                  trailing: MeridianButton(
                    label: context.l10n.integrationRun,
                    variant: MeridianButtonVariant.quiet,
                    size: MeridianControlSize.small,
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _run(
                              IntegrationRequest(
                                kind: candidate.kind,
                                discoveredId: candidate.id,
                                variables: _variables,
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
        ]),
        _section(context.l10n.integrationConfigured, [
          if (configured.isEmpty)
            _empty(context.l10n.integrationConfiguredEmpty)
          else
            GitLamaListWell(
              itemCount: configured.length,
              itemBuilder: (context, index) {
                final definition = configured[index];
                return MeridianListRow(
                  title: definition.id,
                  subtitle: integrationKindLabel(context, definition.kind),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: MeridianSpace.space2,
                    children: [
                      MeridianButton(
                        key: ValueKey('integration-run-${definition.id}'),
                        label: context.l10n.integrationRun,
                        variant: MeridianButtonVariant.quiet,
                        size: MeridianControlSize.small,
                        onPressed: _busy
                            ? null
                            : () => unawaited(
                                _run(
                                  IntegrationRequest(
                                    kind: definition.kind,
                                    configured: definition,
                                    variables: _variables,
                                  ),
                                ),
                              ),
                      ),
                      MeridianButton(
                        label: context.l10n.delete,
                        variant: MeridianButtonVariant.dangerQuiet,
                        size: MeridianControlSize.small,
                        onPressed: _busy ? null : () => _remove(definition),
                      ),
                    ],
                  ),
                );
              },
            ),
        ]),
        _section(context.l10n.integrationConfigure, [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: MeridianSpace.space6,
            children: [
              MeridianSelect<IntegrationKind>(
                value: _kind,
                values: IntegrationKind.values,
                valueLabel: (kind) => integrationKindLabel(context, kind),
                label: context.l10n.integrationKind,
                showLabel: true,
                expand: true,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _kind = value;
                        if (_kind == IntegrationKind.custom) _wait = true;
                      }),
              ),
              MeridianTextField(
                fieldKey: const Key('integration-id'),
                controller: _id,
                focusNode: _idFocus,
                enabled: !_busy,
                label: context.l10n.integrationName,
                message: context.l10n.integrationNameHelp,
              ),
              _ProgramField(
                fieldKey: const Key('integration-executable'),
                controller: _executable,
                enabled: !_busy,
                onChoose: _chooseExecutable,
              ),
              MeridianTextField(
                controller: _arguments,
                enabled: !_busy,
                minLines: 2,
                maxLines: 5,
                label: context.l10n.integrationArguments,
                message: context.l10n.integrationArgumentsHelp,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: MeridianSpace.space4,
                children: [
                  MeridianCheckbox(
                    label: context.l10n.integrationExplicitShell,
                    description: context.l10n.integrationExplicitShellHelp,
                    value: _explicitShell,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _explicitShell = value),
                  ),
                  MeridianCheckbox(
                    label: context.l10n.integrationConfirm,
                    value: _confirmation,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _confirmation = value),
                  ),
                  MeridianCheckbox(
                    label: context.l10n.integrationWait,
                    description: context.l10n.integrationWaitHelp,
                    value: _wait,
                    onChanged: _kind == IntegrationKind.custom || _busy
                        ? null
                        : (value) => setState(() => _wait = value),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: GitLamaLayout.shortFieldWidth,
                  child: MeridianTextField(
                    controller: _timeout,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    label: context.l10n.integrationTimeout,
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: MeridianButton(
                  label: context.l10n.integrationValidateSave,
                  variant: MeridianButtonVariant.primary,
                  onPressed: _busy ? null : _validateAndSave,
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }
}

/// The program of a tool: a path field with a Choose button beside it.
class _ProgramField extends StatelessWidget {
  const _ProgramField({
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.onChoose,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    spacing: MeridianSpace.space3,
    children: [
      Expanded(
        child: MeridianTextField(
          fieldKey: fieldKey,
          controller: controller,
          enabled: enabled,
          label: context.l10n.integrationExecutable,
        ),
      ),
      MeridianButton(
        label: context.l10n.integrationChooseExecutable,
        icon: 'folder-open',
        onPressed: enabled ? onChoose : null,
      ),
    ],
  );
}

class DiffRendererSettingsCard extends StatefulWidget {
  const DiffRendererSettingsCard({
    super.key,
    required this.repositories,
    required this.settings,
  });

  final RepositorySessionService repositories;
  final SettingsService settings;

  @override
  State<DiffRendererSettingsCard> createState() =>
      _DiffRendererSettingsCardState();
}

class _DiffRendererSettingsCardState extends State<DiffRendererSettingsCard> {
  late final TextEditingController _id;
  late final TextEditingController _title;
  late final TextEditingController _executable;
  late final TextEditingController _arguments;
  bool _busy = false;
  DiffRendererFailureCode? _failure;

  String _pathLabel(NativePathIdentity identity) =>
      identity.platform == NativePathPlatform.windows
      ? String.fromCharCodes(identity.units)
      : utf8.decode(identity.units, allowMalformed: true);

  @override
  void initState() {
    super.initState();
    final renderer = widget.settings.current.diffRenderer;
    _id = TextEditingController(text: renderer?.id ?? 'plain-text');
    _title = TextEditingController(text: renderer?.title ?? '');
    _executable = TextEditingController(
      text: renderer == null ? '' : _pathLabel(renderer.executable),
    );
    _arguments = TextEditingController(
      text: renderer?.arguments.join('\n') ?? '',
    );
  }

  @override
  void dispose() {
    _id.dispose();
    _title.dispose();
    _executable.dispose();
    _arguments.dispose();
    super.dispose();
  }

  Future<void> _chooseExecutable() async {
    final selected = await openFile();
    if (selected != null && mounted) _executable.text = selected.path;
  }

  DiffRendererDefinition? _definition() {
    final platform = widget.repositories.activeTab?.canonicalIdentity?.platform;
    if (platform == null ||
        _id.text.trim().isEmpty ||
        _title.text.trim().isEmpty ||
        _executable.text.trim().isEmpty) {
      return null;
    }
    return DiffRendererDefinition(
      id: _id.text.trim(),
      title: _title.text.trim(),
      executable: NativePathIdentity(
        platform: platform,
        units: platform == NativePathPlatform.windows
            ? _executable.text.trim().codeUnits
            : utf8.encode(_executable.text.trim()),
      ),
      arguments: _arguments.text
          .split('\n')
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  Future<void> _validateAndSave() async {
    final definition = _definition();
    if (_busy) return;
    if (definition == null) {
      setState(() => _failure = DiffRendererFailureCode.invalidDefinition);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final preview = await widget.repositories.validateDiffRenderer(
        definition,
      );
      if (!mounted) return;
      final save = await showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.diffRendererValidatedTitle,
        confirmLabel: context.l10n.diffRendererSave,
        cancelLabel: context.l10n.cancel,
        content: DiffRendererPreviewContent(
          preview: preview,
          summary: context.l10n.diffRendererValidatedSummary,
          run: false,
        ),
      );
      if (save) {
        await widget.settings.saveDiffRenderer(definition);
        if (mounted) setState(() {});
      }
    } on DiffRendererException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await widget.settings.saveDiffRenderer(null);
    if (!mounted) return;
    _title.clear();
    _executable.clear();
    _arguments.clear();
    setState(() => _failure = null);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: MeridianSpace.space6,
    children: [
      if (_busy) const MeridianProgressBar(),
      if (_failure case final failure?)
        MeridianBanner(
          tone: MeridianBannerTone.error,
          message: rendererFailureLabel(context, failure),
        ),
      MeridianTextField(
        fieldKey: const Key('diff-renderer-id'),
        controller: _id,
        enabled: !_busy,
        label: context.l10n.diffRendererId,
      ),
      MeridianTextField(
        fieldKey: const Key('diff-renderer-title'),
        controller: _title,
        enabled: !_busy,
        label: context.l10n.diffRendererName,
      ),
      _ProgramField(
        fieldKey: const Key('diff-renderer-executable'),
        controller: _executable,
        enabled: !_busy,
        onChoose: _chooseExecutable,
      ),
      MeridianTextField(
        fieldKey: const Key('diff-renderer-arguments'),
        controller: _arguments,
        enabled: !_busy,
        minLines: 2,
        maxLines: 4,
        label: context.l10n.integrationArguments,
        message: context.l10n.diffRendererArgumentsHelp,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: MeridianSpace.space4,
        children: [
          MeridianButton(
            label: context.l10n.delete,
            variant: MeridianButtonVariant.dangerQuiet,
            onPressed: _busy || widget.settings.current.diffRenderer == null
                ? null
                : _remove,
          ),
          MeridianButton(
            key: const Key('diff-renderer-validate-save'),
            label: context.l10n.diffRendererSave,
            variant: MeridianButtonVariant.primary,
            onPressed: _busy ? null : _validateAndSave,
          ),
        ],
      ),
    ],
  );
}

String _integrationFailureLabel(
  BuildContext context,
  IntegrationFailureCode failure,
) => switch (failure) {
  IntegrationFailureCode.invalidRequest => context.l10n.integrationInvalid,
  IntegrationFailureCode.unavailable => context.l10n.integrationUnavailable,
  IntegrationFailureCode.missingVariable =>
    context.l10n.integrationMissingVariable,
  IntegrationFailureCode.stale => context.l10n.integrationStale,
  IntegrationFailureCode.confirmationRequired =>
    context.l10n.integrationConfirmationRequired,
  IntegrationFailureCode.canceled => context.l10n.operationStateCanceled,
  IntegrationFailureCode.timedOut => context.l10n.integrationTimedOut,
  IntegrationFailureCode.nonZeroExit => context.l10n.integrationNonZero,
  IntegrationFailureCode.launch => context.l10n.integrationLaunchFailed,
  IntegrationFailureCode.read => context.l10n.integrationReadFailed,
};
