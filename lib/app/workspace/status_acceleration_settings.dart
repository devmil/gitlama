import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/repository_state.dart';
import '../../models/status_acceleration.dart';
import '../../services/session/working_copy_commands.dart';
import '../app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// Git's status accelerators of the active repository: whether the untracked
/// cache and the file system monitor are on, and a way to turn on what is
/// missing. The same settings the slow-status offer enables.
class StatusAccelerationSettings extends StatefulWidget {
  const StatusAccelerationSettings({
    super.key,
    required this.workingCopy,
    required this.identity,
  });

  final WorkingCopyCommands workingCopy;
  final RepositorySessionIdentity identity;

  @override
  State<StatusAccelerationSettings> createState() =>
      _StatusAccelerationSettingsState();
}

class _StatusAccelerationSettingsState
    extends State<StatusAccelerationSettings> {
  StatusAcceleration? _acceleration;
  var _loading = true;
  var _enabling = false;
  var _readFailed = false;
  var _enableFailed = false;

  bool get _remote => widget.identity.backend != RepositoryBackendKind.local;

  @override
  void initState() {
    super.initState();
    if (_remote) {
      _loading = false;
    } else {
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    try {
      final acceleration = await widget.workingCopy.statusAcceleration(
        widget.identity,
      );
      if (!mounted) return;
      setState(() {
        _acceleration = acceleration;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _readFailed = true;
      });
    }
  }

  Future<void> _enable() async {
    setState(() {
      _enabling = true;
      _enableFailed = false;
    });
    try {
      final enabled = await widget.workingCopy.enableStatusAcceleration(
        widget.identity,
      );
      if (!mounted) return;
      setState(() {
        _acceleration = enabled;
        _enabling = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _enabling = false;
        _enableFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = context.text.caption.copyWith(color: context.colors.inkMuted);
    final acceleration = _acceleration;
    String state(bool on) => on ? l10n.settingsOn : l10n.settingsOff;
    return MeridianSettingsGroup(
      key: const Key('settings-status-acceleration'),
      title: l10n.settingsStatusAcceleration,
      children: [
        Text(l10n.settingsStatusAccelerationHint, style: muted),
        if (_remote)
          Text(l10n.settingsStatusAccelerationRemote)
        else if (_loading)
          const SizedBox.shrink()
        else if (_readFailed || acceleration == null)
          Text(
            l10n.settingsStatusAccelerationReadFailed,
            style: context.text.caption.copyWith(color: context.colors.danger),
          )
        else ...[
          MeridianSettingsRow(
            label: l10n.settingsUntrackedCache,
            children: [
              Text(
                state(acceleration.untrackedCache),
                key: const Key('settings-untracked-cache'),
              ),
            ],
          ),
          MeridianSettingsRow(
            label: l10n.settingsFsmonitor,
            children: [
              Text(
                acceleration.fsmonitor || acceleration.fsmonitorAvailable
                    ? state(acceleration.fsmonitor)
                    : l10n.settingsFsmonitorUnavailable,
                key: const Key('settings-fsmonitor'),
              ),
            ],
          ),
          if (acceleration.lastScan case final scan?)
            Text(
              scan < const Duration(seconds: 1)
                  ? l10n.settingsStatusAccelerationLastScanFast
                  : l10n.settingsStatusAccelerationLastScan(
                      (scan.inMilliseconds / 1000).round(),
                    ),
              style: muted,
            ),
          if (acceleration.canImprove)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MeridianButton(
                key: const Key('settings-status-acceleration-enable'),
                variant: MeridianButtonVariant.secondary,
                onPressed: _enabling ? null : _enable,
                label: l10n.settingsStatusAccelerationEnable,
              ),
            )
          else
            Text(l10n.settingsStatusAccelerationAllOn, style: muted),
          if (_enableFailed)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.statusAccelerationFailed,
                style: context.text.caption.copyWith(
                  color: context.colors.danger,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
