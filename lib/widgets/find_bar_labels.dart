import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';

/// GitLama's strings for a [MeridianFindBar].
///
/// [placeholder] names what the bar searches ("Find in diff"). A bar that
/// searches only on Enter passes [searched] `false` while the typed query
/// has not run yet, so the counter does not claim "No matches" for it.
MeridianFindBarLabels gitLamaFindBarLabels(
  BuildContext context, {
  required String placeholder,
  bool searched = true,
}) {
  final l10n = context.l10n;
  return MeridianFindBarLabels(
    placeholder: placeholder,
    previous: l10n.diffPreviousMatch,
    next: l10n.diffNextMatch,
    caseSensitive: l10n.diffCaseSensitive,
    clear: l10n.searchClear,
    position: (current, total) => l10n.findMatchPosition(current, total),
    count: l10n.findMatchCount,
    noMatches: searched ? l10n.findNoMatches : '',
  );
}
