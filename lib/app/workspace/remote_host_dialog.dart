import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../byte_size.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_appearance.dart';
import '../../services/remote_workspace_service.dart';
import '../../widgets/appearance_color_row.dart';
import '../../widgets/native_menu.dart';
import '../../widgets/repository_icon.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';
import 'remote_workspace.dart';
import 'repository_icon_dialog.dart';

/// Shows the host profiles. With [choosing], the primary action continues
/// with the selected, connected host and the dialog returns its profile ID.
Future<String?> showRemoteHostDialog(
  BuildContext context, {
  required RemoteWorkspaceService service,
  bool choosing = false,
  String? initialProfileId,
  Future<void> Function(String profileId)? onAccessChanged,
}) => showMeridianDialog<String>(
  context: context,
  builder: (context) => RemoteHostDialog(
    service: service,
    choosing: choosing,
    initialProfileId: initialProfileId,
    onAccessChanged: onAccessChanged,
  ),
);

/// The status dot tone of a connection phase.
MeridianStatusTone remotePhaseTone(RemoteConnectionPhase phase) =>
    switch (phase) {
      RemoteConnectionPhase.ready => MeridianStatusTone.success,
      RemoteConnectionPhase.installing ||
      RemoteConnectionPhase.connecting ||
      RemoteConnectionPhase.handshaking ||
      RemoteConnectionPhase.disconnecting => MeridianStatusTone.accent,
      RemoteConnectionPhase.failed => MeridianStatusTone.danger,
      RemoteConnectionPhase.identityChanged ||
      RemoteConnectionPhase.disconnected => MeridianStatusTone.warning,
      RemoteConnectionPhase.idle ||
      RemoteConnectionPhase.retired => MeridianStatusTone.neutral,
    };

/// Asks before deleting the local record of [profile].
Future<bool> confirmRemoteHostDeletion(
  BuildContext context,
  RemoteHostProfile profile,
) => showMeridianConfirm(
  context,
  title: context.l10n.remoteDeleteHostTitle(profile.label),
  description: context.l10n.remoteDeleteHostDetail,
  confirmLabel: context.l10n.remoteDeleteHost,
  cancelLabel: context.l10n.cancel,
  destructive: true,
);

class RemoteHostDialog extends StatefulWidget {
  const RemoteHostDialog({
    super.key,
    required this.service,
    this.choosing = false,
    this.initialProfileId,
    this.onAccessChanged,
  });

  final RemoteWorkspaceService service;
  final bool choosing;
  final String? initialProfileId;

  /// Applies a changed access choice to a live connection of the host,
  /// reconnecting it with its tabs. Without it the choice applies on the
  /// next connection.
  final Future<void> Function(String profileId)? onAccessChanged;

  @override
  State<RemoteHostDialog> createState() => _RemoteHostDialogState();
}

class _RemoteHostDialogState extends State<RemoteHostDialog> {
  StreamSubscription<RemoteConnectionState>? _states;
  String? _selected;
  String? _failure;

  /// Profiles whose changed identity the user set aside for now.
  final Set<String> _deferredIdentity = {};

  RemoteWorkspaceService get _service => widget.service;

  /// The helper build this application needs, for the install location.
  late final Future<String?> _buildId = _service.helperBuildId();

  /// The helper this build can install; null when it carries none.
  /// Bundled helpers by host platform, loaded once per dialog.
  final Map<RemoteHelperTarget, Future<RemoteHelperArtifact?>> _bundled = {};

  Future<RemoteHelperArtifact?> _bundledFor(RemoteHostProfile profile) {
    final target = _service.hostTarget(profile.id);
    if (target == null) return Future.value();
    return _bundled.putIfAbsent(target, () => _service.bundledHelper(target));
  }

  @override
  void initState() {
    super.initState();
    final profiles = _service.profiles;
    _selected =
        profiles
            .where((profile) => profile.id == widget.initialProfileId)
            .firstOrNull
            ?.id ??
        profiles.firstOrNull?.id;
    _states = _service.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  RemoteHostProfile? get _profile =>
      _selected == null ? null : _service.profile(_selected!);

  Future<void> _connect(RemoteHostProfile profile) async {
    setState(() {
      _failure = null;
      _deferredIdentity.remove(profile.id);
    });
    try {
      await _service.connect(profile.id);
    } on RemoteWorkspaceException catch (error) {
      if (mounted && error.code != RemoteFailureCode.canceled) {
        setState(
          () => _failure = remoteFailureMessage(
            context,
            error.code,
            alias: profile.alias,
          ),
        );
      }
    }
  }

  Future<void> _install(
    RemoteHostProfile profile,
    RemoteHelperArtifact artifact,
  ) async {
    final decision = await showRemoteHelperInstallDialog(
      context,
      profile: profile,
      artifact: artifact,
    );
    if (decision == null || !mounted) return;
    setState(() {
      _failure = null;
      _deferredIdentity.remove(profile.id);
    });
    try {
      if (decision.automatic != profile.autoInstallHelper) {
        await _service.setAutoInstallHelper(profile.id, decision.automatic);
      }
    } on Object catch (error) {
      // The installation itself still runs; only the preference was lost.
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    }
    try {
      await _service.installHelper(profile.id, artifact);
    } on RemoteWorkspaceException catch (error) {
      if (mounted && error.code != RemoteFailureCode.canceled) {
        setState(
          () => _failure = remoteFailureMessage(
            context,
            error.code,
            alias: profile.alias,
          ),
        );
      }
    }
  }

  Future<void> _disconnect(RemoteHostProfile profile) async {
    try {
      await _service.disconnect(profile.id);
    } on Object {
      // The connection reports its own state; closing is best effort.
    }
  }

  Future<void> _rebind(RemoteHostProfile profile) async {
    setState(() => _failure = null);
    try {
      await _service.rebind(profile.id);
    } on RemoteWorkspaceException catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteFailureMessage(
            context,
            error.code,
            alias: profile.alias,
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    }
  }

  Future<void> _setWrites(RemoteHostProfile profile, bool allowed) async {
    if (profile.writesAllowed == allowed) return;
    setState(() => _failure = null);
    try {
      await _service.setWritesAllowed(profile.id, allowed);
      if (mounted) setState(() {});
      // Capabilities are negotiated when a connection starts: a live one
      // reconnects at once instead of asking the user to.
      if (_service.state(profile.id).ready) {
        await widget.onAccessChanged?.call(profile.id);
      }
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    }
  }

  Future<void> _setAutoInstall(RemoteHostProfile profile, bool enabled) async {
    setState(() => _failure = null);
    try {
      await _service.setAutoInstallHelper(profile.id, enabled);
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    }
  }

  Future<void> _edit([RemoteHostProfile? profile]) async {
    final saved = await showMeridianDialog<RemoteHostProfile>(
      context: context,
      builder: (context) =>
          RemoteProfileEditor(service: _service, profile: profile),
    );
    if (saved != null && mounted) {
      setState(() {
        _selected = saved.id;
        _failure = null;
      });
    }
  }

  Future<void> _delete(RemoteHostProfile profile) async {
    if (!await confirmRemoteHostDeletion(context, profile) || !mounted) {
      return;
    }
    try {
      await _service.deleteProfile(profile.id);
      if (!mounted) return;
      setState(() {
        _selected = _service.profiles.firstOrNull?.id;
        _failure = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    }
  }

  bool _canChoose(RemoteHostProfile? profile) =>
      profile != null &&
      profile.authority != null &&
      _service.state(profile.id).ready;

  void _choose() {
    final profile = _profile;
    if (_canChoose(profile)) Navigator.pop(context, profile!.id);
  }

  Widget _row(RemoteHostProfile profile) {
    final state = _service.state(profile.id);
    final phase = remotePhaseLabel(context, state.phase);
    final account = profile.verified?.accountName;
    return MeridianListRow(
      key: ValueKey('remote-host-${profile.id}'),
      leading: remoteHostMark(context, profile),
      title: profile.label,
      subtitle: account == null
          ? context.l10n.remoteHostRowUnverified(profile.alias)
          : context.l10n.remoteHostRowVerified(profile.alias, account),
      twoLine: true,
      selected: profile.id == _selected,
      semanticValue: phase,
      trailing: MeridianStatusDot(
        tone: remotePhaseTone(state.phase),
        label: phase,
      ),
      onTap: () => setState(() {
        _selected = profile.id;
        _failure = null;
      }),
    );
  }

  /// What GitLama may do on the host: read only, or also change its
  /// repositories. It can be chosen at any time; a live connection applies
  /// it by reconnecting.
  Widget _access(
    BuildContext context,
    RemoteHostProfile profile, {
    required bool busy,
  }) {
    final l10n = context.l10n;
    final state = _service.state(profile.id);
    final pending =
        state.ready &&
        _service.writeBlock(profile.id) == RemoteWriteBlock.reconnect;
    return Column(
      key: const ValueKey('remote-access'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MeridianSegmented<bool>(
          key: const ValueKey('remote-allow-writes'),
          label: l10n.remoteAccess,
          segments: [
            MeridianSegment(
              value: false,
              label: l10n.remoteAccessReadOnly,
              icon: 'eye',
            ),
            MeridianSegment(
              value: true,
              label: l10n.remoteAccessChanges,
              icon: 'pencil',
            ),
          ],
          value: profile.writesAllowed,
          onChanged: busy
              ? (_) {}
              : (value) => unawaited(_setWrites(profile, value)),
        ),
        const SizedBox(height: MeridianSpace.space2),
        Text(
          profile.writesAllowed
              ? l10n.remoteAccessChangesDetail
              : l10n.remoteAccessReadOnlyDetail,
          key: const ValueKey('remote-access-detail'),
          style: context.text.caption.copyWith(color: context.colors.inkMuted),
        ),
        if (profile.verified == null && profile.writesAllowed) ...[
          const SizedBox(height: MeridianSpace.space1),
          Text(
            l10n.remoteAccessFirstConnection,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
        ],
        // Only when the dialog cannot reconnect by itself.
        if (pending && widget.onAccessChanged == null) ...[
          const SizedBox(height: MeridianSpace.space1),
          Text(
            l10n.remoteAccessNextConnection,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
        ],
      ],
    );
  }

  /// Where to place the helper by hand.
  Widget _manualLocation() {
    final l10n = context.l10n;
    return FutureBuilder<String?>(
      future: _buildId,
      builder: (context, snapshot) {
        final buildId = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.remoteHelperLocationLabel,
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: MeridianSpace.space2),
            SelectableText(
              contextMenuBuilder: nativeTextContextMenuBuilder,
              remoteHelperLocation(
                buildId ?? l10n.remoteHelperBuildPlaceholder,
              ),
              key: const ValueKey('remote-helper-location'),
              style: context.text.codeSm.copyWith(color: context.colors.ink),
            ),
            const SizedBox(height: MeridianSpace.space2),
            Text(
              buildId == null
                  ? l10n.remoteHelperLocationHelp
                  : l10n.remoteHelperExactLocationHelp,
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _details(RemoteHostProfile profile) {
    final l10n = context.l10n;
    final state = _service.state(profile.id);
    final busy =
        state.phase == RemoteConnectionPhase.installing ||
        state.phase == RemoteConnectionPhase.connecting ||
        state.phase == RemoteConnectionPhase.handshaking;
    final observed = _service.observedIdentity(profile.id);
    final identityChanged =
        state.phase == RemoteConnectionPhase.identityChanged &&
        observed != null &&
        !_deferredIdentity.contains(profile.id);
    final failure = state.failure;
    final showFailure =
        failure != null &&
        !identityChanged &&
        state.phase != RemoteConnectionPhase.identityChanged &&
        (state.phase == RemoteConnectionPhase.failed ||
            state.phase == RemoteConnectionPhase.disconnected);
    return Column(
      key: const ValueKey('remote-host-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (busy) ...[
              const MeridianSpinner(delayed: false),
              const SizedBox(width: MeridianSpace.space3),
            ],
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  remotePhaseLabel(context, state.phase),
                  key: const ValueKey('remote-host-phase'),
                  style: context.text.bodyStrong.copyWith(
                    color: context.colors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (profile.verified case final verified?) ...[
          const SizedBox(height: MeridianSpace.space2),
          Text(
            l10n.remoteHostAccount(verified.accountName),
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
        ],
        if (showFailure) ...[
          const SizedBox(height: MeridianSpace.space4),
          MeridianBanner(
            key: const ValueKey('remote-host-failure'),
            tone: MeridianBannerTone.error,
            message: remoteFailureMessage(
              context,
              failure,
              alias: profile.alias,
            ),
          ),
          if (RemoteWorkspaceService.installResolves(failure)) ...[
            const SizedBox(height: MeridianSpace.space3),
            FutureBuilder<RemoteHelperArtifact?>(
              future: _bundledFor(profile),
              builder: (context, snapshot) {
                final artifact = snapshot.data;
                if (artifact == null) return _manualLocation();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.remoteInstallHelperHelp,
                      style: context.text.caption.copyWith(
                        color: context.colors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: MeridianSpace.space3),
                    MeridianButton(
                      key: const ValueKey('remote-install-helper'),
                      label: l10n.remoteInstallHelper,
                      icon: 'download',
                      variant: MeridianButtonVariant.primary,
                      onPressed: () => unawaited(_install(profile, artifact)),
                    ),
                  ],
                );
              },
            ),
          ] else if (failure == RemoteFailureCode.installUnavailable) ...[
            const SizedBox(height: MeridianSpace.space3),
            _manualLocation(),
          ],
        ],
        if (identityChanged) ...[
          const SizedBox(height: MeridianSpace.space4),
          MeridianBanner(
            key: const ValueKey('remote-identity-changed'),
            tone: MeridianBannerTone.warning,
            title: l10n.remoteIdentityChangedTitle,
            message: l10n.remoteIdentityChangedDetail(
              observed.accountName,
              profile.verified?.accountName ?? l10n.remoteHostUnknownAccount,
            ),
            actions: [
              MeridianButton(
                key: const ValueKey('remote-trust-identity'),
                label: l10n.remoteTrustIdentity,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.primary,
                onPressed: () => unawaited(_rebind(profile)),
              ),
              MeridianButton(
                label: l10n.cancel,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.quiet,
                onPressed: () =>
                    setState(() => _deferredIdentity.add(profile.id)),
              ),
            ],
          ),
        ],
        const SizedBox(height: MeridianSpace.space4),
        _access(context, profile, busy: busy),
        const SizedBox(height: MeridianSpace.space4),
        MeridianSwitch(
          key: const ValueKey('remote-auto-install'),
          label: l10n.remoteAutoInstallHelper,
          description: l10n.remoteAutoInstallHelperDetail,
          value: profile.autoInstallHelper,
          onChanged: (value) => unawaited(_setAutoInstall(profile, value)),
        ),
        const SizedBox(height: MeridianSpace.space4),
        Wrap(
          spacing: MeridianSpace.space3,
          runSpacing: MeridianSpace.space3,
          children: [
            if (busy)
              MeridianButton(
                key: const ValueKey('remote-cancel-connect'),
                label: l10n.remoteCancelConnect,
                icon: 'ban',
                onPressed: () => _service.cancel(profile.id),
              )
            else if (state.ready)
              MeridianButton(
                key: const ValueKey('remote-disconnect'),
                label: l10n.remoteDisconnect,
                icon: 'unlink',
                onPressed: () => unawaited(_disconnect(profile)),
              )
            else
              MeridianButton(
                key: const ValueKey('remote-connect'),
                label: l10n.remoteConnect,
                icon: 'link',
                variant: widget.choosing
                    ? MeridianButtonVariant.secondary
                    : MeridianButtonVariant.primary,
                onPressed: () => unawaited(_connect(profile)),
              ),
            MeridianButton(
              key: const ValueKey('remote-edit-host'),
              label: l10n.remoteEditHost,
              icon: 'pencil',
              variant: MeridianButtonVariant.quiet,
              onPressed: busy ? null : () => unawaited(_edit(profile)),
            ),
            MeridianButton(
              key: const ValueKey('remote-delete-host'),
              label: l10n.remoteDeleteHost,
              icon: 'trash',
              variant: MeridianButtonVariant.dangerQuiet,
              onPressed: () => unawaited(_delete(profile)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profiles = _service.profiles;
    final profile = _profile;
    final canChoose = _canChoose(profile);
    return MeridianDialog(
      width: MeridianLayout.dialogWorkflowWidth,
      onClose: () => Navigator.pop(context),
      title: widget.choosing ? l10n.openRemoteRepository : l10n.remoteHosts,
      description: l10n.remoteHostsIntro,
      onSubmit: widget.choosing ? _choose : null,
      submitDisabled: widget.choosing && !canChoose,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profiles.isEmpty)
            Text(
              l10n.remoteHostsEmpty,
              key: const ValueKey('remote-hosts-empty'),
              style: context.text.body.copyWith(color: context.colors.inkMuted),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: GitLamaLayout.remoteHostListMaxHeight,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [for (final value in profiles) _row(value)],
              ),
            ),
          if (_failure case final failure?) ...[
            const SizedBox(height: MeridianSpace.space6),
            MeridianBanner(tone: MeridianBannerTone.error, message: failure),
          ],
          if (profile != null) ...[
            const SizedBox(height: MeridianSpace.space5),
            _details(profile),
          ],
        ],
      ),
      actions: [
        MeridianButton(
          key: const ValueKey('remote-add-host'),
          label: l10n.remoteAddHost,
          icon: 'plus',
          onPressed: profiles.length >= RemoteHostProfile.capacity
              ? null
              : () => unawaited(_edit()),
          disabledReason: profiles.length >= RemoteHostProfile.capacity
              ? l10n.remoteFailureCapacity
              : null,
        ),
        if (widget.choosing)
          MeridianButton(
            key: const ValueKey('remote-choose-folder'),
            label: l10n.remoteChooseFolder,
            variant: MeridianButtonVariant.primary,
            onPressed: canChoose ? _choose : null,
            disabledReason: canChoose ? null : l10n.remoteChooseFolderDisabled,
          ),
      ],
    );
  }
}

/// What the user decided when asked to install the helper.
typedef RemoteHelperInstallDecision = ({bool automatic});

/// Asks before installing [artifact] on the host of [profile]; null when the
/// user declined.
Future<RemoteHelperInstallDecision?> showRemoteHelperInstallDialog(
  BuildContext context, {
  required RemoteHostProfile profile,
  required RemoteHelperArtifact artifact,
}) => showMeridianDialog<RemoteHelperInstallDecision>(
  context: context,
  builder: (context) =>
      RemoteHelperInstallDialog(profile: profile, artifact: artifact),
);

/// Asks before copying [artifact] to the host of [profile], naming where it
/// goes and what exactly is copied, and whether later versions may install
/// theirs without asking.
class RemoteHelperInstallDialog extends StatefulWidget {
  const RemoteHelperInstallDialog({
    super.key,
    required this.profile,
    required this.artifact,
  });

  final RemoteHostProfile profile;
  final RemoteHelperArtifact artifact;

  @override
  State<RemoteHelperInstallDialog> createState() =>
      _RemoteHelperInstallDialogState();
}

class _RemoteHelperInstallDialogState extends State<RemoteHelperInstallDialog> {
  late bool _automatic = widget.profile.autoInstallHelper;

  void _confirm() => Navigator.pop<RemoteHelperInstallDecision>(context, (
    automatic: _automatic,
  ));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = widget.profile;
    final artifact = widget.artifact;
    final code = context.text.codeSm.copyWith(color: context.colors.ink);
    final caption = context.text.caption.copyWith(
      color: context.colors.inkMuted,
    );
    return MeridianDialog(
      width: MeridianLayout.dialogConfirmWidth,
      title: l10n.remoteInstallHelperTitle(profile.label),
      onSubmit: _confirm,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.remoteInstallHelperDetail(profile.alias)),
          const SizedBox(height: MeridianSpace.space4),
          Text(l10n.remoteHelperLocationLabel, style: caption),
          const SizedBox(height: MeridianSpace.space2),
          SelectableText(
            contextMenuBuilder: nativeTextContextMenuBuilder,
            artifact.installPath,
            key: const ValueKey('remote-install-location'),
            style: code,
          ),
          const SizedBox(height: MeridianSpace.space3),
          Text(
            l10n.remoteInstallHelperSize(
              formatByteSize(l10n, artifact.bytes.length),
            ),
            style: caption,
          ),
          const SizedBox(height: MeridianSpace.space2),
          SelectableText(
            contextMenuBuilder: nativeTextContextMenuBuilder,
            l10n.remoteInstallHelperDigest(artifact.sha256),
            style: code,
          ),
          const SizedBox(height: MeridianSpace.space4),
          MeridianCheckbox(
            key: const ValueKey('remote-install-automatic'),
            label: l10n.remoteAutoInstallHelper,
            value: _automatic,
            onChanged: (value) => setState(() => _automatic = value),
          ),
          const SizedBox(height: MeridianSpace.space2),
          Text(l10n.remoteAutoInstallHelperDetail, style: caption),
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('remote-install-confirm'),
          label: l10n.remoteInstallHelperConfirm,
          variant: MeridianButtonVariant.primary,
          onPressed: _confirm,
        ),
      ],
    );
  }
}

/// Adds or edits a host profile: a label and an SSH alias, nothing else.
/// A host's icon in its colour, as its tabs show it.
Widget remoteHostMark(BuildContext context, RemoteHostProfile profile) {
  final color = AppearanceColor.byKey(profile.color);
  return MeridianIcon(
    repositoryAppearanceIcons.contains(profile.icon) ? profile.icon! : 'server',
    color: color == null ? null : repositoryAppearanceColor(context, color),
  );
}

class RemoteProfileEditor extends StatefulWidget {
  const RemoteProfileEditor({
    super.key,
    required this.service,
    this.profile,
    this.initialAlias,
  });

  final RemoteWorkspaceService service;
  final RemoteHostProfile? profile;

  /// The SSH alias a new host starts with, such as one the command line
  /// named; it also starts as the label.
  final String? initialAlias;

  @override
  State<RemoteProfileEditor> createState() => _RemoteProfileEditorState();
}

class _RemoteProfileEditorState extends State<RemoteProfileEditor> {
  late final TextEditingController _label = TextEditingController(
    text: widget.profile?.label ?? widget.initialAlias ?? '',
  );
  late final TextEditingController _alias = TextEditingController(
    text: widget.profile?.alias ?? widget.initialAlias ?? '',
  );

  /// A new host starts with the server icon and a colour no other host
  /// uses, so its tabs stand out at once.
  late AppearanceColor? _color = widget.profile == null
      ? _unusedColor()
      : AppearanceColor.byKey(widget.profile!.color);
  late String? _icon = widget.profile == null
      ? 'server'
      : repositoryAppearanceIcons.contains(widget.profile!.icon)
      ? widget.profile!.icon
      : null;
  var _attempted = false;
  var _saving = false;
  String? _failure;

  @override
  void dispose() {
    _label.dispose();
    _alias.dispose();
    super.dispose();
  }

  AppearanceColor _unusedColor() {
    final used = {
      for (final profile in widget.service.profiles) ?profile.color,
    };
    final free = RepositoryAppearanceColor.values.where(
      (color) => !used.contains(color.name),
    );
    return PaletteColor(
      free.firstOrNull ?? RepositoryAppearanceColor.values.first,
    );
  }

  String? get _labelError =>
      (_attempted || _label.text.isNotEmpty) && !isValidRemoteLabel(_label.text)
      ? context.l10n.remoteLabelInvalid
      : null;

  String? get _aliasError =>
      (_attempted || _alias.text.isNotEmpty) && !isValidRemoteAlias(_alias.text)
      ? context.l10n.remoteAliasInvalid
      : null;

  bool get _valid =>
      isValidRemoteLabel(_label.text) && isValidRemoteAlias(_alias.text);

  Future<void> _save() async {
    if (_saving) return;
    if (!_valid) {
      setState(() => _attempted = true);
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final saved = await widget.service.saveProfile(
        id: widget.profile?.id,
        label: _label.text,
        alias: _alias.text,
        color: _color?.key,
        icon: _icon,
      );
      if (mounted) Navigator.pop(context, saved);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The icon and colour the host's tabs show, laid out as the repository
  /// icon dialog lays them out: symbol, then colour.
  Widget _appearance(BuildContext context) {
    final l10n = context.l10n;
    final color = _color;
    final tint = color == null
        ? null
        : repositoryAppearanceColor(context, color);
    return Column(
      key: const ValueKey('remote-host-appearance'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppearanceHeading(l10n.repositoryIconSymbol),
        Wrap(
          spacing: MeridianSpace.space2,
          runSpacing: MeridianSpace.space2,
          children: [
            MeridianIconButton(
              key: const ValueKey('remote-host-icon-none'),
              label: l10n.repositoryIconNone,
              icon: 'ban',
              size: MeridianControlSize.small,
              active: _icon == null,
              onPressed: _saving ? null : () => setState(() => _icon = null),
            ),
            for (final icon in repositoryAppearanceIcons)
              MeridianIconButton(
                key: ValueKey('remote-host-icon-$icon'),
                label: repositoryIconLabel(context, icon),
                icon: icon,
                size: MeridianControlSize.small,
                color: tint,
                active: _icon == icon,
                onPressed: _saving ? null : () => setState(() => _icon = icon),
              ),
          ],
        ),
        const SizedBox(height: MeridianSpace.space6),
        AppearanceHeading(l10n.repositoryIconColor),
        AppearanceColorRow(
          value: color,
          noneLabel: l10n.repositoryColorNone,
          onChanged: _saving ? null : (value) => setState(() => _color = value),
        ),
        const SizedBox(height: MeridianSpace.space3),
        Text(
          l10n.remoteHostAppearanceHelp,
          style: context.text.caption.copyWith(color: context.colors.inkMuted),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.profile;
    final aliasChanged =
        editing?.verified != null &&
        _alias.text.isNotEmpty &&
        _alias.text != editing!.alias;
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: editing == null
          ? l10n.remoteAddHostTitle
          : l10n.remoteEditHostTitle,
      description: editing == null && widget.initialAlias != null
          ? l10n.remoteAddHostRequested(widget.initialAlias!)
          : null,
      onSubmit: () => unawaited(_save()),
      submitDisabled: _saving,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MeridianTextField(
            fieldKey: const ValueKey('remote-host-label'),
            controller: _label,
            autofocus: true,
            label: l10n.remoteHostLabel,
            placeholder: l10n.remoteHostLabelPlaceholder,
            error: _labelError,
            enabled: !_saving,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_save()),
          ),
          const SizedBox(height: MeridianSpace.space6),
          MeridianTextField(
            fieldKey: const ValueKey('remote-host-alias'),
            controller: _alias,
            label: l10n.remoteHostAlias,
            placeholder: l10n.remoteAliasExample,
            monospace: true,
            autocorrect: false,
            enableSuggestions: false,
            error: _aliasError,
            message: l10n.remoteHostAliasHelp,
            enabled: !_saving,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_save()),
          ),
          const SizedBox(height: MeridianSpace.space6),
          _appearance(context),
          const SizedBox(height: MeridianSpace.space6),
          Text(
            l10n.remoteHostTrustHelp,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
          if (aliasChanged) ...[
            const SizedBox(height: MeridianSpace.space6),
            MeridianBanner(
              tone: MeridianBannerTone.warning,
              message: l10n.remoteAliasChangeWarning,
            ),
          ],
          if (_failure case final failure?) ...[
            const SizedBox(height: MeridianSpace.space6),
            MeridianBanner(tone: MeridianBannerTone.error, message: failure),
          ],
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('remote-host-save'),
          label: l10n.remoteSaveHost,
          variant: MeridianButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}
