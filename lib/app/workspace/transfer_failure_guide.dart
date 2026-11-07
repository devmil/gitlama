import 'pull_stash_labels.dart';
import '../../l10n/app_localizations.dart';
import '../../models/transfer.dart';
import '../../services/workflows/transfer_workflows.dart';

/// How prominent a remedy is in the failure dialog.
enum FailureGuideEmphasis { primary, secondary, danger }

/// One remedy the failure dialog offers.
final class FailureGuideAction {
  const FailureGuideAction({
    required this.id,
    required this.label,
    required this.remedy,
    this.emphasis = FailureGuideEmphasis.secondary,
    this.removesLocks = false,
  });

  /// Stable for tests and support: `retry`, `retryWithoutPrune`, …
  final String id;
  final String label;
  final TransferRemedy remedy;
  final FailureGuideEmphasis emphasis;

  /// Removes the listed lock files before [remedy]; offered only while
  /// there are locks this computer may remove.
  final bool removesLocks;
}

/// What the failure dialog says about a failed transfer and which remedies
/// it offers. Built only from [transferFailureGuide].
final class FailureGuide {
  const FailureGuide({
    required this.title,
    required this.message,
    required this.actions,
    this.explanation,
    this.showsLocks = false,
  });

  final String title;
  final String message;
  final String? explanation;

  /// Lists the repository's lock files with their age.
  final bool showsLocks;
  final List<FailureGuideAction> actions;
}

/// The failure catalog: what GitLama tells the user about each diagnosis
/// the shared Git library recognises, and how they can resolve it. Add an
/// entry here when a new diagnosis needs an explanation or a remedy;
/// [TransferFailureReport.explains] decides which failures reach it.
FailureGuide transferFailureGuide(
  AppLocalizations l10n,
  TransferFailureReport report,
) {
  if (report.result.stash case final saved? when !saved.reapplyCompleted) {
    return FailureGuide(
      title: l10n.transferPullRecoveryTitle,
      message: pullStashResultLabel(l10n, saved, failure: l10n.transferFailed),
      explanation: l10n.transferPullRecoveryHelp,
      actions: const [],
    );
  }
  final request = report.request;
  final diagnosis = report.result.diagnosis;
  final pruningFetch = request.kind == TransferKind.fetch && request.prune;
  final withoutPrune = FailureGuideAction(
    id: 'retryWithoutPrune',
    label: l10n.failureFetchWithoutPrune,
    remedy: const RetryWithoutPrune(),
  );
  switch (diagnosis?.kind) {
    case TransferDiagnosisKind.refCaseCollision:
      final reference = diagnosis!.reference!;
      final spellings = [reference, ...diagnosis.related];
      final repairable =
          !report.remote &&
          spellings.every((name) => name.startsWith('refs/remotes/'));
      return FailureGuide(
        title: l10n.failureCaseCollisionTitle,
        message: l10n.failureCaseCollisionMessage(
          spellings.map(shortReferenceName).join(', '),
        ),
        explanation: repairable
            ? l10n.failureCaseCollisionRepair
            : l10n.failureCaseCollisionServer,
        actions: [
          if (pruningFetch) withoutPrune,
          if (repairable)
            FailureGuideAction(
              id: 'repairTrackingRefs',
              label: l10n.failureCaseCollisionRepairAction,
              remedy: RepairTrackingRefs(spellings),
              emphasis: FailureGuideEmphasis.primary,
            ),
        ],
      );
    case TransferDiagnosisKind.remoteAhead:
      return FailureGuide(
        title: l10n.failureRemoteAheadTitle,
        message: l10n.failureRemoteAheadMessage,
        actions: [
          FailureGuideAction(
            id: 'fetch',
            label: l10n.operationFetch,
            remedy: const FetchRemote(),
            emphasis: FailureGuideEmphasis.primary,
          ),
        ],
      );
    default:
      return FailureGuide(
        title: l10n.repositoryLockTitle,
        message: l10n.transferFailureLocked,
        explanation: l10n.repositoryLockExplanation,
        showsLocks: true,
        actions: [
          FailureGuideAction(
            id: 'removeLocksAndRetry',
            label: l10n.repositoryLockRemoveAndRetry,
            remedy: const RetryTransfer(),
            emphasis: FailureGuideEmphasis.danger,
            removesLocks: true,
          ),
          // Git can trip over its own lock while pruning; see the case
          // collision entry for the confirmed form.
          if (pruningFetch) withoutPrune,
          FailureGuideAction(
            id: 'retry',
            label: l10n.repositoryLockRetry,
            remedy: const RetryTransfer(),
            emphasis: FailureGuideEmphasis.primary,
          ),
        ],
      );
  }
}

/// `refs/remotes/origin/main` as `origin/main`, `refs/heads/main` as `main`.
String shortReferenceName(String reference) {
  for (final prefix in const ['refs/remotes/', 'refs/heads/', 'refs/tags/']) {
    if (reference.startsWith(prefix)) return reference.substring(prefix.length);
  }
  return reference;
}
