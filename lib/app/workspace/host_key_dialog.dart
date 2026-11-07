import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/clone_attempt.dart';

/// The default SSH port, left out of the server name.
const _sshPort = 22;

/// Asks whether to trust a server's SSH host key the first time GitLama
/// meets it. It must be answered explicitly, so the scrim does not cancel.
Future<bool> confirmHostKey(BuildContext context, HostKeyChallenge challenge) =>
    showMeridianConfirm(
      context,
      barrierDismissible: false,
      title: context.l10n.hostKeyTitle,
      description: context.l10n.hostKeyDescription,
      confirmLabel: context.l10n.trustHostKey,
      cancelLabel: context.l10n.rejectHostKey,
      content: HostKeyDetails(challenge),
    );

/// The server, key type and fingerprint of a host key to check.
class HostKeyDetails extends StatelessWidget {
  const HostKeyDetails(this.challenge, {super.key});

  final HostKeyChallenge challenge;

  @override
  Widget build(BuildContext context) => MeridianPropertyList(
    key: const ValueKey('host-key-details'),
    properties: [
      MeridianProperty(
        label: context.l10n.hostKeyServer,
        value: challenge.port == _sshPort
            ? challenge.host
            : '${challenge.host}:${challenge.port}',
        monospace: true,
      ),
      MeridianProperty(
        label: context.l10n.hostKeyType,
        value: challenge.algorithm,
        monospace: true,
      ),
      MeridianProperty(
        label: context.l10n.hostKeyFingerprint,
        value: challenge.fingerprint,
        monospace: true,
      ),
    ],
  );
}
