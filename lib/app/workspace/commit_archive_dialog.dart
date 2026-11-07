import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/commit_archive.dart';
import '../../models/repository_state.dart';
import '../../services/session/commit_archive_commands.dart';
import '../../widgets/status_notification.dart';
import '../app_theme.dart';

/// The snapshot's file and top folder name: the repository's name and the
/// commit's short hash, with characters file systems reject replaced.
String commitArchiveName(String repositoryLabel, String commit) {
  final cleaned = repositoryLabel
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'^[.\-]+|[.\-]+$'), '');
  final name = cleaned.isEmpty ? 'snapshot' : cleaned;
  final short = commit.length > 7 ? commit.substring(0, 7) : commit;
  return '$name-$short';
}

/// Asks where to save the zip snapshot of [commit], saves it with progress
/// and tells the person how it went.
Future<void> saveCommitArchive(
  BuildContext context, {
  required CommitArchiveCommands commands,
  required Future<String?> Function(String suggestedName) chooseDestination,
  required String commit,
  required String repositoryLabel,
}) async {
  final name = commitArchiveName(repositoryLabel, commit);
  final destination = await chooseDestination('$name.zip');
  if (destination == null || !context.mounted) return;
  final outcome = await showMeridianDialog<_ArchiveOutcome>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false,
    builder: (context) => CommitArchiveProgressDialog(
      save: (onProgress, isCanceled) => commands.save(
        commit: commit,
        prefix: name,
        destination: destination,
        onProgress: onProgress,
        isCanceled: isCanceled,
      ),
    ),
  );
  if (outcome == null || !context.mounted) return;
  final l10n = context.l10n;
  switch (outcome) {
    case _ArchiveSaved(:final status):
      final file = destination.split(RegExp(r'[\\/]')).last;
      final notes = [
        l10n.archiveSaved(file),
        if (status.missingSubmoduleCount > 0)
          l10n.archiveMissingSubmodules(status.missingSubmoduleCount),
        if (status.unresolvedLfsCount > 0)
          l10n.archiveUnresolvedLfs(status.unresolvedLfsCount),
      ];
      StatusNotificationScope.show(context, notes.join(' '));
    case _ArchiveFailed(:final code):
      if (code == CommitArchiveFailureCode.canceled) return;
      StatusNotificationScope.show(
        context,
        commitArchiveFailureMessage(context, code),
        error: true,
      );
  }
}

String commitArchiveFailureMessage(
  BuildContext context,
  CommitArchiveFailureCode code,
) => switch (code) {
  CommitArchiveFailureCode.stale => context.l10n.archiveFailureStale,
  CommitArchiveFailureCode.missingCommit =>
    context.l10n.archiveFailureMissingCommit,
  CommitArchiveFailureCode.tooLarge => context.l10n.archiveFailureTooLarge,
  CommitArchiveFailureCode.busy => context.l10n.archiveFailureBusy,
  CommitArchiveFailureCode.write => context.l10n.archiveFailureWrite,
  CommitArchiveFailureCode.invalidRequest ||
  CommitArchiveFailureCode.git ||
  CommitArchiveFailureCode.canceled => context.l10n.archiveFailureGit,
};

sealed class _ArchiveOutcome {
  const _ArchiveOutcome();
}

final class _ArchiveSaved extends _ArchiveOutcome {
  const _ArchiveSaved(this.status);

  final CommitArchiveStatus status;
}

final class _ArchiveFailed extends _ArchiveOutcome {
  const _ArchiveFailed(this.code);

  final CommitArchiveFailureCode code;
}

/// Runs a snapshot save.
typedef SaveCommitArchive =
    Future<CommitArchiveStatus> Function(
      void Function(CommitArchiveStatus status) onProgress,
      bool Function() isCanceled,
    );

/// Shows a snapshot's progress while [save] runs; Cancel stops it. Closes
/// with the outcome.
class CommitArchiveProgressDialog extends StatefulWidget {
  const CommitArchiveProgressDialog({required this.save, super.key});

  final SaveCommitArchive save;

  @override
  State<CommitArchiveProgressDialog> createState() =>
      _CommitArchiveProgressDialogState();
}

class _CommitArchiveProgressDialogState
    extends State<CommitArchiveProgressDialog> {
  CommitArchiveStatus? _status;
  bool _canceled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    _ArchiveOutcome outcome;
    try {
      outcome = _ArchiveSaved(
        await widget.save((status) {
          if (mounted) setState(() => _status = status);
        }, () => _canceled),
      );
    } on CommitArchiveException catch (error) {
      outcome = _ArchiveFailed(error.code);
    } on RepositorySessionException {
      outcome = const _ArchiveFailed(CommitArchiveFailureCode.stale);
    }
    if (mounted) Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _status;
    final building =
        status == null || status.state == CommitArchiveState.running;
    final total = status?.totalFiles ?? 0;
    return MeridianDialog(
      title: l10n.archiveProgressTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space4,
        children: [
          MeridianProgressBar(
            track: true,
            persistent: true,
            value: building && total > 0
                ? (status!.files / total).clamp(0, 1).toDouble()
                : null,
            semanticLabel: l10n.archiveProgressTitle,
          ),
          Text(
            key: const ValueKey('commit-archive-progress'),
            status == null
                ? l10n.archiveProgressPreparing
                : building
                ? l10n.archiveProgressFiles(status.files, total)
                : l10n.archiveProgressWriting,
            style: context.text.body.copyWith(color: context.colors.inkMuted),
          ),
        ],
      ),
      actions: [
        MeridianButton(
          key: const ValueKey('commit-archive-cancel'),
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: _canceled ? null : () => setState(() => _canceled = true),
        ),
      ],
    );
  }
}
