import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import 'remote_workspace.dart';

/// What the user chose before picking the destination of a new repository:
/// the host to create it on (null for this computer) and whether it is bare.
typedef InitializeRepositoryChoice = ({String? profileId, bool bare});

/// Asks where a new repository goes and whether it is bare. Hosts are
/// offered when [remote] has any; a host that does not allow changes cannot
/// be chosen and says why. Completes with null when canceled.
Future<InitializeRepositoryChoice?> showInitializeRepositoryDialog(
  BuildContext context, {
  required RemoteWorkspaceController remote,
  bool initiallyBare = false,
}) => showMeridianDialog<InitializeRepositoryChoice>(
  context: context,
  builder: (context) =>
      InitializeRepositoryDialog(remote: remote, initiallyBare: initiallyBare),
);

class InitializeRepositoryDialog extends StatefulWidget {
  const InitializeRepositoryDialog({
    super.key,
    required this.remote,
    this.initiallyBare = false,
  });

  final RemoteWorkspaceController remote;
  final bool initiallyBare;

  @override
  State<InitializeRepositoryDialog> createState() =>
      _InitializeRepositoryDialogState();
}

class _InitializeRepositoryDialogState
    extends State<InitializeRepositoryDialog> {
  /// The location value of this computer; hosts use their profile IDs.
  static const _local = '';

  late var _bare = widget.initiallyBare;
  var _location = _local;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hosts = widget.remote.hosts;
    final labels = {for (final host in hosts) host.id: host.label};
    // A host removed while the dialog is open is no longer a choice.
    if (_location != _local && !labels.containsKey(_location)) {
      _location = _local;
    }
    final local = _location == _local;
    final blocked = local
        ? null
        : widget.remote.initializeBlockedReason(context, _location);
    void submit() => Navigator.pop<InitializeRepositoryChoice>(context, (
      profileId: local ? null : _location,
      bare: _bare,
    ));
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: l10n.initializeRepository,
      description: local
          ? l10n.initializeDestinationHint
          : l10n.initializeRemoteDestinationHint,
      onSubmit: submit,
      submitDisabled: blocked != null,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (hosts.isNotEmpty)
            MeridianSelect<String>(
              key: const ValueKey('initialize-location'),
              value: _location,
              values: [_local, for (final host in hosts) host.id],
              valueLabel: (value) => value == _local
                  ? l10n.initializeLocationThisComputer
                  : labels[value] ?? '',
              label: l10n.initializeLocation,
              showLabel: true,
              expand: true,
              onChanged: (value) => setState(() => _location = value),
            ),
          if (blocked != null)
            MeridianBanner(
              key: const ValueKey('initialize-blocked'),
              tone: MeridianBannerTone.info,
              message: blocked,
            ),
          MeridianCheckbox(
            key: const ValueKey('initialize-bare'),
            label: l10n.initializeBareOption,
            description: l10n.initializeBareHelp,
            value: _bare,
            onChanged: (value) => setState(() => _bare = value),
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('initialize-continue'),
          label: l10n.chooseCloneDestination,
          variant: MeridianButtonVariant.primary,
          onPressed: blocked == null ? submit : null,
          disabledReason: blocked,
        ),
      ],
    );
  }
}
