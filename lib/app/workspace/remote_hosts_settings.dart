import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/remote_workspace.dart';
import '../../services/remote_workspace_service.dart';
import '../app_theme.dart';
import 'remote_host_dialog.dart';
import 'remote_workspace.dart';

/// The Remote hosts settings: every host profile with what GitLama may do
/// there and whether it keeps the host's helper current by itself. The
/// connection itself is managed in the host dialog.
class RemoteHostsSettings extends StatefulWidget {
  const RemoteHostsSettings({super.key, required this.controller});

  final RemoteWorkspaceController controller;

  @override
  State<RemoteHostsSettings> createState() => _RemoteHostsSettingsState();
}

class _RemoteHostsSettingsState extends State<RemoteHostsSettings> {
  StreamSubscription<RemoteConnectionState>? _states;
  late final Future<int?> _helperVersion = _service.helperVersion();
  String? _failure;

  /// Profiles with a change in flight; their controls wait for it.
  final Set<String> _saving = {};

  RemoteWorkspaceService get _service => widget.controller.service!;

  @override
  void initState() {
    super.initState();
    _states = _service.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  /// Runs a profile change, showing why it failed.
  Future<void> _change(String profileId, Future<void> Function() change) async {
    setState(() {
      _saving.add(profileId);
      _failure = null;
    });
    try {
      await change();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _failure = remoteProfileSaveFailureMessage(context, error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(profileId));
    }
  }

  Future<void> _setWrites(RemoteHostProfile profile, bool allowed) =>
      _change(profile.id, () async {
        await _service.setWritesAllowed(profile.id, allowed);
        // Capabilities are negotiated when a connection starts: a live one
        // reconnects with its tabs.
        if (_service.state(profile.id).ready) {
          await widget.controller.repositories.applyRemoteAccess(profile.id);
        }
      });

  Future<void> _edit([RemoteHostProfile? profile]) async {
    await showMeridianDialog<RemoteHostProfile>(
      context: context,
      builder: (context) =>
          RemoteProfileEditor(service: _service, profile: profile),
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(RemoteHostProfile profile) async {
    if (!await confirmRemoteHostDeletion(context, profile) || !mounted) {
      return;
    }
    await _change(profile.id, () => _service.deleteProfile(profile.id));
  }

  Future<void> _manage(RemoteHostProfile profile) async {
    await widget.controller.showHosts(context, profileId: profile.id);
    if (mounted) setState(() {});
  }

  Widget _host(RemoteHostProfile profile) {
    final l10n = context.l10n;
    final state = _service.state(profile.id);
    final phase = remotePhaseLabel(context, state.phase);
    final account = profile.verified?.accountName;
    final saving = _saving.contains(profile.id);
    final installing = widget.controller.connecting(profile.id);
    final caption = context.text.caption.copyWith(
      color: context.colors.inkMuted,
    );
    return FocusTraversalGroup(
      key: ValueKey('settings-remote-host-${profile.id}'),
      child: MeridianSettingsGroup(
        children: [
          MeridianListRow(
            leading: remoteHostMark(context, profile),
            title: profile.label,
            subtitle: account == null
                ? l10n.remoteHostRowUnverified(profile.alias)
                : l10n.remoteHostRowVerified(profile.alias, account),
            twoLine: true,
            semanticValue: phase,
            trailing: MeridianStatusDot(
              tone: remotePhaseTone(state.phase),
              label: phase,
            ),
          ),
          MeridianSegmented<bool>(
            key: ValueKey('settings-remote-access-${profile.id}'),
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
            onChanged: saving
                ? (_) {}
                : (value) => unawaited(_setWrites(profile, value)),
          ),
          MeridianSwitch(
            key: ValueKey('settings-remote-auto-install-${profile.id}'),
            label: l10n.remoteAutoInstallHelper,
            description: l10n.remoteAutoInstallHelperDetail,
            value: profile.autoInstallHelper,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _change(
                      profile.id,
                      () => _service.setAutoInstallHelper(profile.id, value),
                    ),
                  ),
          ),
          if (widget.controller.needsHelper(profile.id) && !installing)
            Text(
              remoteFailureMessage(
                context,
                state.failure ?? RemoteFailureCode.helperNotInstalled,
                alias: profile.alias,
              ),
              style: caption.copyWith(color: context.colors.danger),
            ),
          Wrap(
            spacing: MeridianSpace.space3,
            runSpacing: MeridianSpace.space3,
            children: [
              if (widget.controller.needsHelper(profile.id))
                MeridianButton(
                  key: ValueKey('settings-remote-install-${profile.id}'),
                  label: l10n.remoteInstallHelper,
                  icon: 'download',
                  variant: MeridianButtonVariant.primary,
                  loading: installing,
                  onPressed: installing
                      ? null
                      : () => unawaited(
                          widget.controller.installHelper(context, profile.id),
                        ),
                ),
              MeridianButton(
                key: ValueKey('settings-remote-manage-${profile.id}'),
                label: l10n.remoteManageConnection,
                icon: 'link',
                onPressed: () => unawaited(_manage(profile)),
              ),
              MeridianButton(
                key: ValueKey('settings-remote-edit-${profile.id}'),
                label: l10n.remoteEditHost,
                icon: 'pencil',
                variant: MeridianButtonVariant.quiet,
                onPressed: saving || installing
                    ? null
                    : () => unawaited(_edit(profile)),
              ),
              MeridianButton(
                key: ValueKey('settings-remote-delete-${profile.id}'),
                label: l10n.remoteDeleteHost,
                icon: 'trash',
                variant: MeridianButtonVariant.dangerQuiet,
                onPressed: saving ? null : () => unawaited(_delete(profile)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profiles = _service.profiles;
    final caption = context.text.caption.copyWith(
      color: context.colors.inkMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<int?>(
          future: _helperVersion,
          builder: (context, snapshot) => MeridianSettingsRow(
            label: l10n.remoteHelperVersion,
            help: l10n.remoteHelperVersionDetail,
            children: [
              Text(
                snapshot.data?.toString() ?? l10n.remoteHelperVersionUnknown,
                key: const ValueKey('settings-remote-helper-version'),
                style: context.text.body.copyWith(color: context.colors.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: MeridianSpace.space6),
        if (_failure case final failure?) ...[
          MeridianBanner(tone: MeridianBannerTone.error, message: failure),
          const SizedBox(height: MeridianSpace.space5),
        ],
        if (profiles.isEmpty)
          Text(
            l10n.remoteHostsEmpty,
            key: const ValueKey('settings-remote-hosts-empty'),
            style: caption,
          )
        else
          for (final profile in profiles) ...[
            _host(profile),
            const SizedBox(height: MeridianSpace.space7),
          ],
        const SizedBox(height: MeridianSpace.space4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: MeridianButton(
            key: const ValueKey('settings-remote-add-host'),
            label: l10n.remoteAddHost,
            icon: 'plus',
            variant: MeridianButtonVariant.secondary,
            onPressed: profiles.length >= RemoteHostProfile.capacity
                ? null
                : () => unawaited(_edit()),
            disabledReason: profiles.length >= RemoteHostProfile.capacity
                ? l10n.remoteFailureCapacity
                : null,
          ),
        ),
      ],
    );
  }
}
