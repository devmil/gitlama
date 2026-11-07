import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../models/index_lock.dart';
import '../../models/operation_failure.dart';
import '../../models/repository_lock.dart';
import '../../services/workflows/transfer_workflows.dart';
import '../../widgets/operation_failure_dialog.dart';
import '../app_theme.dart';
import 'transfer_failure_guide.dart';

/// A lock younger than this is probably held by a Git program still running.
const repositoryLockRecentAge = Duration(minutes: 1);

/// Locks at least this old were probably left behind by a stopped process.
const repositoryLockStaleAge = Duration(minutes: 5);

/// Lists and removes the lock files of the repository an action failed in.
abstract interface class RepositoryLockControls {
  /// Locks of a repository on another computer are only listed.
  bool get canRemove;

  Future<RepositoryLockInspection> inspect();

  /// Completes with how many locks were removed. Throws
  /// [IndexLockException] when one changed or cannot be removed.
  Future<int> remove(List<RepositoryLock> locks);
}

/// Shows what the failure catalog says about a failed action and the
/// remedies it offers. Completes with the chosen remedy; null leaves it.
Future<TransferRemedy?> showTransferFailureDialog(
  BuildContext context, {
  required FailureGuide guide,
  required OperationFailureDetails details,
  required RepositoryLockControls? locks,
  ActivityRecordLoader? loadActivity,
}) => showMeridianDialog<TransferRemedy>(
  context: context,
  builder: (context) => TransferFailureDialog(
    guide: guide,
    details: details,
    locks: locks,
    loadActivity: loadActivity,
  ),
);

class TransferFailureDialog extends StatefulWidget {
  const TransferFailureDialog({
    required this.guide,
    required this.details,
    required this.locks,
    this.loadActivity,
    super.key,
  });

  final FailureGuide guide;
  final OperationFailureDetails details;

  /// Lists the repository's lock files when [FailureGuide.showsLocks].
  final RepositoryLockControls? locks;
  final ActivityRecordLoader? loadActivity;

  @override
  State<TransferFailureDialog> createState() => _TransferFailureDialogState();
}

class _TransferFailureDialogState extends State<TransferFailureDialog> {
  late final _failure = ValueNotifier<OperationFailure>((
    message: widget.guide.message,
    details: widget.details,
  ));
  RepositoryLockInspection? _inspection;
  var _inspectionFailed = false;
  var _busy = false;
  String? _removalError;

  bool get _showsLocks => widget.guide.showsLocks && widget.locks != null;

  @override
  void initState() {
    super.initState();
    if (_showsLocks) _inspect();
  }

  @override
  void dispose() {
    _failure.dispose();
    super.dispose();
  }

  Future<void> _inspect() async {
    setState(() {
      _busy = true;
      _removalError = null;
    });
    RepositoryLockInspection? inspection;
    try {
      inspection = await widget.locks!.inspect();
    } on Object {
      inspection = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _inspection = inspection;
      _inspectionFailed = inspection == null;
    });
  }

  Future<void> _choose(FailureGuideAction action) async {
    if (!action.removesLocks) {
      Navigator.of(context).pop(action.remedy);
      return;
    }
    setState(() {
      _busy = true;
      _removalError = null;
    });
    try {
      await widget.locks!.remove(_inspection?.locks ?? const []);
      if (mounted) Navigator.of(context).pop(action.remedy);
    } on IndexLockException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _removalError = repositoryLockRemovalMessage(context.l10n, error.code);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _removalError = context.l10n.repositoryLockRemoveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final guide = widget.guide;
    final locks = _inspection?.locks ?? const <RepositoryLock>[];
    final canRemoveLocks = widget.locks?.canRemove ?? false;
    final actions = [
      for (final action in guide.actions)
        if (!action.removesLocks || (canRemoveLocks && locks.isNotEmpty))
          action,
    ];
    return OperationFailureDialog(
      key: const ValueKey('transfer-failure-dialog'),
      failure: _failure,
      loadActivity: widget.loadActivity,
      title: guide.title,
      closeLabel: actions.isEmpty ? null : l10n.cancel,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: MeridianSpace.space4,
        children: [
          if (guide.explanation case final explanation?)
            Text(
              explanation,
              key: const ValueKey('transfer-failure-explanation'),
              style: context.text.body.copyWith(color: context.colors.inkMuted),
            ),
          if (_showsLocks) ...[
            _LockList(
              inspection: _inspection,
              checking: _busy && _inspection == null && !_inspectionFailed,
              failed: _inspectionFailed,
              onCheckAgain: _busy ? null : _inspect,
            ),
            if (_inspection case final inspection?)
              if (repositoryLockAdvice(l10n, inspection) case final advice?)
                MeridianBanner(
                  key: const ValueKey('repository-lock-advice'),
                  message: advice,
                  tone: inspection.locks.isEmpty
                      ? MeridianBannerTone.success
                      : MeridianBannerTone.info,
                ),
            if (locks.isNotEmpty)
              MeridianBanner(
                message: canRemoveLocks
                    ? l10n.repositoryLockRemoveWarning
                    : l10n.repositoryLockRemoteOnly,
                tone: MeridianBannerTone.warning,
              ),
          ],
          if (_removalError case final error?)
            MeridianBanner(
              key: const ValueKey('repository-lock-removal-error'),
              message: error,
              tone: MeridianBannerTone.error,
            ),
        ],
      ),
      actions: [
        for (final action in actions)
          MeridianButton(
            key: ValueKey('transfer-failure-${action.id}'),
            label: action.label,
            variant: switch (action.emphasis) {
              FailureGuideEmphasis.primary => MeridianButtonVariant.primary,
              FailureGuideEmphasis.secondary => MeridianButtonVariant.secondary,
              FailureGuideEmphasis.danger => MeridianButtonVariant.danger,
            },
            onPressed: _busy ? null : () => _choose(action),
          ),
      ],
    );
  }
}

class _LockList extends StatelessWidget {
  const _LockList({
    required this.inspection,
    required this.checking,
    required this.failed,
    required this.onCheckAgain,
  });

  final RepositoryLockInspection? inspection;
  final bool checking;
  final bool failed;
  final VoidCallback? onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final caption = context.text.caption.copyWith(
      color: context.colors.inkMuted,
    );
    final locks = inspection?.locks ?? const <RepositoryLock>[];
    return Column(
      key: const ValueKey('repository-lock-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: MeridianSpace.space3,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.repositoryLockListTitle,
                style: context.text.label,
              ),
            ),
            MeridianButton(
              key: const ValueKey('repository-lock-check-again'),
              label: l10n.repositoryLockCheckAgain,
              icon: MeridianIcons.refreshCw,
              variant: MeridianButtonVariant.quiet,
              size: MeridianControlSize.small,
              onPressed: onCheckAgain,
            ),
          ],
        ),
        if (checking)
          Row(
            spacing: MeridianSpace.space3,
            children: [
              const MeridianSpinner(),
              Text(l10n.repositoryLockChecking, style: caption),
            ],
          )
        else if (failed)
          Text(l10n.repositoryLockInspectFailed, style: caption)
        else if (locks.isNotEmpty)
          MeridianPropertyList(
            properties: [
              for (final lock in locks)
                MeridianProperty(
                  label: repositoryLockAgeLabel(l10n, lock.age),
                  value: lock.path,
                  monospace: true,
                ),
            ],
          ),
        if (inspection?.truncated ?? false)
          Text(l10n.repositoryLockTruncated, style: caption),
      ],
    );
  }
}

/// What the locks' ages suggest; null when they do not suggest anything.
String? repositoryLockAdvice(
  AppLocalizations l10n,
  RepositoryLockInspection inspection,
) {
  final locks = inspection.locks;
  if (locks.isEmpty) {
    return inspection.truncated ? null : l10n.repositoryLockNone;
  }
  if (locks.any(
    (lock) =>
        (lock.age ?? Duration.zero) < repositoryLockRecentAge &&
        lock.age != null,
  )) {
    return l10n.repositoryLockRecent;
  }
  if (locks.every(
    (lock) => lock.age != null && lock.age! >= repositoryLockStaleAge,
  )) {
    return l10n.repositoryLockStale;
  }
  return null;
}

/// How long ago Git took a lock, in its largest whole unit.
String repositoryLockAgeLabel(AppLocalizations l10n, Duration? age) {
  if (age == null) return l10n.repositoryLockAgeUnknown;
  if (age.inDays > 0) return l10n.repositoryLockAgeDays(age.inDays);
  if (age.inHours > 0) return l10n.repositoryLockAgeHours(age.inHours);
  if (age.inMinutes > 0) return l10n.repositoryLockAgeMinutes(age.inMinutes);
  return l10n.repositoryLockAgeSeconds(age.inSeconds);
}

@visibleForTesting
String repositoryLockRemovalMessage(
  AppLocalizations l10n,
  IndexLockFailureCode code,
) => switch (code) {
  IndexLockFailureCode.changed => l10n.repositoryLockChanged,
  IndexLockFailureCode.activeOperation => l10n.repositoryLockBusy,
  _ => l10n.repositoryLockRemoveFailed,
};
