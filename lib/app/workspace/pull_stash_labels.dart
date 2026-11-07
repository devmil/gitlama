import '../../l10n/app_localizations.dart';
import '../../models/transfer.dart';

String pullStashResultLabel(
  AppLocalizations l10n,
  PullStashResult saved, {
  required String failure,
}) {
  if (!saved.pullCompleted) {
    return saved.reapplyCompleted
        ? l10n.transferPullFailedStashRestored(failure)
        : l10n.transferPullFailedStashSaved;
  }
  if (saved.reapplyCompleted) return l10n.transferPullStashRestored;
  return saved.conflicted
      ? l10n.transferPullStashConflict
      : l10n.transferPullStashSaved;
}
