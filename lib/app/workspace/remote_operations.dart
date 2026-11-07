import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/remote_workspace.dart';
import '../../services/remote_workspace_service.dart';
import '../../widgets/gitlama_list_well.dart';
import '../app_theme.dart';

/// Whether [operation] still needs the user's attention: it is unresolved,
/// or its outcome was not definite.
bool remoteOperationNeedsReview(RemotePendingOperation operation) =>
    operation.pending ||
    switch (operation.outcome) {
      RemoteOperationOutcome.succeeded ||
      RemoteOperationOutcome.failed ||
      RemoteOperationOutcome.notApplied => false,
      _ => true,
    };

String remoteOperationStateLabel(
  BuildContext context,
  RemotePendingOperation operation,
) {
  final l10n = context.l10n;
  if (operation.pending && operation.outcome == null) {
    return l10n.remoteOperationRunning;
  }
  return switch (operation.outcome) {
    RemoteOperationOutcome.succeeded => l10n.remoteOperationSucceeded,
    RemoteOperationOutcome.failed => l10n.remoteOperationFailed,
    RemoteOperationOutcome.notApplied => l10n.remoteOperationNotApplied,
    RemoteOperationOutcome.desiredStateObserved =>
      l10n.remoteOperationDesiredState,
    RemoteOperationOutcome.partial => l10n.remoteOperationPartial,
    RemoteOperationOutcome.unknown || null => l10n.remoteOperationUnknown,
  };
}

String remoteOperationFamilyLabel(
  BuildContext context,
  RemoteOperationFamily family,
) => switch (family) {
  RemoteOperationFamily.stage => context.l10n.remoteOperationStage,
  RemoteOperationFamily.commit => context.l10n.remoteOperationCommit,
  RemoteOperationFamily.refs => context.l10n.remoteOperationRefs,
  RemoteOperationFamily.stash => context.l10n.remoteOperationStash,
  RemoteOperationFamily.transfer => context.l10n.remoteOperationTransfer,
  RemoteOperationFamily.discard => context.l10n.remoteOperationDiscard,
  RemoteOperationFamily.history => context.l10n.remoteOperationHistory,
  RemoteOperationFamily.rebase => context.l10n.remoteOperationRebase,
  RemoteOperationFamily.restack => context.l10n.remoteOperationRestack,
  RemoteOperationFamily.bisect => context.l10n.remoteOperationBisect,
  RemoteOperationFamily.conflict => context.l10n.remoteOperationConflict,
  RemoteOperationFamily.sequencer => context.l10n.remoteOperationSequencer,
  RemoteOperationFamily.snapshot => context.l10n.remoteOperationSnapshot,
  RemoteOperationFamily.snapshotRestore =>
    context.l10n.remoteOperationSnapshotRestore,
  RemoteOperationFamily.restore => context.l10n.remoteOperationRestore,
  RemoteOperationFamily.indexLock => context.l10n.remoteOperationIndexLock,
  RemoteOperationFamily.patch => context.l10n.remoteOperationPatch,
  RemoteOperationFamily.extension => context.l10n.remoteOperationExtension,
};

String _familyIcon(RemoteOperationFamily family) => switch (family) {
  RemoteOperationFamily.stage => 'layers',
  RemoteOperationFamily.commit => 'check',
  RemoteOperationFamily.refs => 'branch',
  RemoteOperationFamily.stash => 'stash',
  RemoteOperationFamily.transfer => 'push',
  RemoteOperationFamily.discard => 'trash',
  RemoteOperationFamily.history => 'git-merge',
  RemoteOperationFamily.rebase => 'squash',
  RemoteOperationFamily.restack => 'git-fork',
  RemoteOperationFamily.bisect => 'search',
  RemoteOperationFamily.conflict => 'circle-alert',
  RemoteOperationFamily.sequencer => 'skip-forward',
  RemoteOperationFamily.snapshot => 'save',
  RemoteOperationFamily.snapshotRestore => 'recovery',
  RemoteOperationFamily.restore => 'rotate-ccw',
  RemoteOperationFamily.indexLock => 'key',
  RemoteOperationFamily.patch => 'file-diff',
  RemoteOperationFamily.extension => 'puzzle',
};

/// A compact status bar entry while remote writes need review. It opens the
/// list of remote changes.
class RemoteOperationsIndicator extends StatefulWidget {
  const RemoteOperationsIndicator({super.key, required this.service});

  final RemoteWorkspaceService service;

  @override
  State<RemoteOperationsIndicator> createState() =>
      _RemoteOperationsIndicatorState();
}

class _RemoteOperationsIndicatorState extends State<RemoteOperationsIndicator> {
  StreamSubscription<List<RemotePendingOperation>>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.service.operationChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.service.operations
        .where(remoteOperationNeedsReview)
        .length;
    if (count == 0) return const SizedBox.shrink();
    return MeridianButton(
      key: const ValueKey('remote-operations-indicator'),
      label: context.l10n.remoteOperationsIndicator(count),
      icon: 'circle-alert',
      size: MeridianControlSize.small,
      variant: MeridianButtonVariant.quiet,
      onPressed: () => unawaited(
        showRemoteOperationsDialog(context, service: widget.service),
      ),
    );
  }
}

Future<void> showRemoteOperationsDialog(
  BuildContext context, {
  required RemoteWorkspaceService service,
}) => showMeridianDialog<void>(
  context: context,
  builder: (context) => RemoteOperationsDialog(service: service),
);

/// Remote staging and commits this computer recorded, newest first. An
/// uncertain outcome is never retried: the user reviews the repository and
/// may ask the host to look the operation up again.
class RemoteOperationsDialog extends StatefulWidget {
  const RemoteOperationsDialog({super.key, required this.service});

  final RemoteWorkspaceService service;

  @override
  State<RemoteOperationsDialog> createState() => _RemoteOperationsDialogState();
}

class _RemoteOperationsDialogState extends State<RemoteOperationsDialog> {
  StreamSubscription<List<RemotePendingOperation>>? _changes;
  StreamSubscription<RemoteConnectionState>? _states;
  final Set<String> _checking = {};
  String? _failure;

  @override
  void initState() {
    super.initState();
    _changes = widget.service.operationChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _states = widget.service.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_states?.cancel());
    super.dispose();
  }

  Future<void> _check(String profileId) async {
    setState(() {
      _checking.add(profileId);
      _failure = null;
    });
    try {
      await widget.service.reconcile(profileId);
    } on Object {
      if (mounted) {
        setState(() => _failure = context.l10n.remoteOperationCheckFailed);
      }
    } finally {
      if (mounted) setState(() => _checking.remove(profileId));
    }
  }

  Future<void> _dismiss(RemotePendingOperation operation) async {
    try {
      await widget.service.dismissOperation(operation.operationId);
    } on Object {
      if (mounted) {
        setState(() => _failure = context.l10n.remoteOperationDismissFailed);
      }
    }
  }

  Widget _row(RemotePendingOperation operation) {
    final l10n = context.l10n;
    final service = widget.service;
    final profileId = operation.authority.profileId;
    final profile = service.profile(profileId);
    final host = profile?.label ?? l10n.remoteHostUnknown;
    final connected =
        profile?.authority == operation.authority &&
        service.state(profileId).ready;
    final state = remoteOperationStateLabel(context, operation);
    final summary = operation.summary.isEmpty
        ? remoteOperationFamilyLabel(context, operation.family)
        : operation.summary;
    return MeridianListRow(
      key: ValueKey('remote-operation-${operation.operationId}'),
      leading: MeridianIcon(_familyIcon(operation.family)),
      title: summary,
      subtitle: l10n.remoteOperationSubtitle(
        host,
        remoteOperationFamilyLabel(context, operation.family),
        state,
      ),
      twoLine: true,
      semanticValue: state,
      trailing: operation.pending
          ? MeridianButton(
              key: ValueKey('remote-operation-check-${operation.operationId}'),
              label: l10n.remoteOperationCheckAgain,
              size: MeridianControlSize.small,
              loading: _checking.contains(profileId),
              onPressed: connected && !_checking.contains(profileId)
                  ? () => unawaited(_check(profileId))
                  : null,
              disabledReason: connected
                  ? null
                  : l10n.remoteOperationCheckDisconnected,
            )
          : MeridianButton(
              key: ValueKey(
                'remote-operation-dismiss-${operation.operationId}',
              ),
              label: l10n.remoteOperationDismiss,
              size: MeridianControlSize.small,
              variant: MeridianButtonVariant.quiet,
              onPressed: () => unawaited(_dismiss(operation)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final operations = widget.service.operations.reversed.toList(
      growable: false,
    );
    final uncertain = operations.any(remoteOperationNeedsReview);
    return MeridianDialog(
      width: MeridianLayout.dialogWorkflowWidth,
      onClose: () => Navigator.pop(context),
      title: l10n.remoteOperationsTitle,
      description: l10n.remoteOperationsDescription,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (!widget.service.ledgerUsable)
            MeridianBanner(
              tone: MeridianBannerTone.error,
              message: l10n.remoteOperationsLedgerUnavailable,
            ),
          if (uncertain)
            MeridianBanner(
              key: const ValueKey('remote-operations-uncertain'),
              tone: MeridianBannerTone.warning,
              message: l10n.remoteOperationsUncertain,
            ),
          if (_failure case final failure?)
            MeridianBanner(tone: MeridianBannerTone.error, message: failure),
          if (operations.isEmpty)
            Text(
              l10n.remoteOperationsEmpty,
              style: context.text.body.copyWith(color: context.colors.inkMuted),
            )
          else
            GitLamaListWell(
              key: const ValueKey('remote-operations-list'),
              itemCount: operations.length,
              itemBuilder: (context, index) => _row(operations[index]),
            ),
        ],
      ),
    );
  }
}
