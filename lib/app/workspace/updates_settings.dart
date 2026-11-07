import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/app_update.dart';
import '../../services/app_update_service.dart';
import '../app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// The Updates category: the release channel and the update check.
class UpdatesSettings extends StatefulWidget {
  const UpdatesSettings({super.key, required this.updates});

  final AppUpdateService updates;

  @override
  State<UpdatesSettings> createState() => _UpdatesSettingsState();
}

class _UpdatesSettingsState extends State<UpdatesSettings> {
  var _checking = false;
  var _generation = 0;
  AppUpdateCheck? _result;
  AppUpdateFailureCode? _failure;

  @override
  void dispose() {
    _generation += 1;
    super.dispose();
  }

  Future<void> _run(Future<AppUpdateCheck?> Function() action) async {
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _result = null;
      _failure = null;
    });
    AppUpdateCheck? result;
    AppUpdateFailureCode? failure;
    try {
      result = await action();
    } on AppUpdateException catch (error) {
      failure = error.code;
    } on Object {
      failure = AppUpdateFailureCode.unavailable;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _checking = false;
      _result = result;
      _failure = failure;
    });
  }

  Future<void> _selectChannel(ReleaseChannel channel) => _run(() async {
    try {
      await widget.updates.selectChannel(channel);
    } on AppUpdateException {
      rethrow;
    } on Object {
      throw const AppUpdateException(AppUpdateFailureCode.nativeUpdater);
    }
    return null;
  });

  Future<void> _openDownloads() async {
    try {
      await widget.updates.openDownloads();
    } on AppUpdateException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    }
  }

  String? _status(BuildContext context) {
    final l10n = context.l10n;
    if (_checking) return l10n.updatesChecking;
    final result = _result;
    if (result == null) return null;
    return switch (result.status) {
      AppUpdateStatus.nativeCheckerOpened => null,
      AppUpdateStatus.upToDate => l10n.updatesUpToDate(
        result.installed.version,
        result.installed.build,
      ),
      AppUpdateStatus.noPublishedRelease => l10n.updatesNoRelease,
      AppUpdateStatus.updateAvailable => l10n.updatesAvailable(
        result.available?.version ?? '',
        result.available?.build ?? 0,
      ),
    };
  }

  String? _failureText(BuildContext context) => switch (_failure) {
    null => null,
    AppUpdateFailureCode.unavailable => context.l10n.updatesFailureUnavailable,
    AppUpdateFailureCode.invalidIndex => context.l10n.updatesFailureInvalid,
    AppUpdateFailureCode.nativeUpdater => context.l10n.updatesFailureUpdater,
    AppUpdateFailureCode.openFailed => context.l10n.updatesFailureOpen,
    AppUpdateFailureCode.unsupported => context.l10n.updatesFailureUnsupported,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final updates = widget.updates;
    final installed = updates.installed;
    final status = _status(context);
    final failure = _failureText(context);
    return MeridianSettingsGroup(
      children: [
        if (installed != null)
          MeridianSettingsRow(
            label: l10n.updatesInstalledVersion,
            children: [
              Text(
                l10n.updatesVersionAndBuild(installed.version, installed.build),
                key: const Key('settings-updates-installed'),
                style: context.text.body.copyWith(color: context.colors.ink),
              ),
            ],
          ),
        MeridianSettingsRow(
          label: l10n.updatesChannel,
          children: [
            MeridianSegmented<ReleaseChannel>(
              key: const Key('settings-updates-channel'),
              label: l10n.updatesChannel,
              value: updates.channel,
              onChanged: _selectChannel,
              segments: [
                MeridianSegment(
                  value: ReleaseChannel.stable,
                  label: l10n.updatesChannelStable,
                ),
                MeridianSegment(
                  value: ReleaseChannel.beta,
                  label: l10n.updatesChannelBeta,
                ),
              ],
            ),
          ],
        ),
        Text(
          l10n.updatesChannelHint,
          style: context.text.caption.copyWith(color: context.colors.inkMuted),
        ),
        MeridianButton(
          key: const Key('settings-updates-check'),
          variant: MeridianButtonVariant.secondary,
          onPressed: _checking ? null : () => _run(updates.check),
          label: l10n.updatesCheck,
        ),
        Text(
          updates.installsUpdates
              ? l10n.updatesAutomaticHint
              : l10n.updatesManualHint,
          style: context.text.caption.copyWith(color: context.colors.inkMuted),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            failure ?? status ?? '',
            key: const Key('settings-updates-status'),
            style: context.text.caption.copyWith(
              color: failure == null
                  ? context.colors.ink
                  : context.colors.danger,
            ),
          ),
        ),
        if (failure == null &&
            _result?.status == AppUpdateStatus.updateAvailable)
          MeridianButton(
            key: const Key('settings-updates-open-downloads'),
            onPressed: _openDownloads,
            label: l10n.updatesOpenDownloads,
          ),
      ],
    );
  }
}
