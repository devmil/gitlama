import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../models/hosting.dart';

String hostingCheckIcon(HostingCheckState state) => switch (state) {
  HostingCheckState.passing => 'circle-check',
  HostingCheckState.failing => 'circle-x',
  HostingCheckState.pending => 'clock',
  HostingCheckState.canceled => 'ban',
  HostingCheckState.skipped => 'skip-forward',
  HostingCheckState.unknown => 'circle-help',
};

Color hostingCheckColor(BuildContext context, HostingCheckState state) =>
    hostingCheckStateColor(context.colors, state);

/// The colour of [state] in [colors].
Color hostingCheckStateColor(MeridianColors colors, HostingCheckState state) =>
    switch (state) {
      HostingCheckState.passing => colors.success,
      HostingCheckState.failing => colors.danger,
      HostingCheckState.pending => colors.warning,
      HostingCheckState.canceled ||
      HostingCheckState.skipped ||
      HostingCheckState.unknown => colors.inkMuted,
    };

/// The brand's colours for the brightness opposite the current theme: the
/// palette whose state colours read on the current `ink`.
MeridianColors _inverseColors(BuildContext context) {
  final theme = MeridianTheme.of(context);
  final brightness = theme.brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return MeridianTheme.resolve(
    brand: theme.brand,
    brightness: brightness,
  ).colors;
}

String hostingCheckLabel(BuildContext context, HostingCheckState state) =>
    switch (state) {
      HostingCheckState.passing => context.l10n.hostingCheckPassing,
      HostingCheckState.failing => context.l10n.hostingCheckFailing,
      HostingCheckState.pending => context.l10n.hostingCheckPending,
      HostingCheckState.canceled => context.l10n.hostingCheckCanceled,
      HostingCheckState.skipped => context.l10n.hostingCheckSkipped,
      HostingCheckState.unknown => context.l10n.hostingCheckUnknown,
    };

/// The label of a reported mergeability; null when it is unknown.
String? hostingMergeabilityLabel(
  BuildContext context,
  HostingMergeability mergeability,
) => switch (mergeability) {
  HostingMergeability.mergeable => context.l10n.hostingMergeable,
  HostingMergeability.conflicting => context.l10n.hostingMergeConflicting,
  HostingMergeability.checking => context.l10n.hostingMergeChecking,
  HostingMergeability.unknown => null,
};

/// The CI result of a pull request's head and, when it has conflicts, a
/// conflict mark: each only where the provider reported it. Shows nothing
/// when neither is known, so a provider without them adds no noise.
class HostingPullRequestStatus extends StatelessWidget {
  const HostingPullRequestStatus({
    required this.checks,
    required this.mergeability,
    super.key,
    this.extent,
    this.onAccent = false,
    this.onInk = false,
  });

  final HostingCheckState checks;
  final HostingMergeability mergeability;

  /// The icons' extent; small icons by default.
  final double? extent;

  /// On the accent fill of a selected row, where state colours would not
  /// read; the icons then use the fill's ink.
  final bool onAccent;

  /// On an `ink` fill, such as the checked-out branch chip, where the
  /// theme's state colours lack contrast; the icons then take the state
  /// colours of the opposite brightness, which are made for that ground.
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final showChecks = checks != HostingCheckState.unknown;
    final showConflicts = mergeability == HostingMergeability.conflicting;
    if (!showChecks && !showConflicts) return const SizedBox.shrink();
    final colors = onInk ? _inverseColors(context) : context.colors;
    Widget icon(String name, Color color, String label, Key key) => Semantics(
      key: key,
      label: label,
      child: MeridianIcon(
        name,
        size: MeridianIconSize.small,
        extent: extent,
        color: onAccent ? colors.onAccent : color,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showChecks)
          icon(
            hostingCheckIcon(checks),
            hostingCheckStateColor(colors, checks),
            hostingCheckLabel(context, checks),
            const ValueKey('hosting-status-checks'),
          ),
        if (showChecks && showConflicts)
          const SizedBox(width: MeridianSpace.space1),
        if (showConflicts)
          icon(
            'triangle-alert',
            colors.danger,
            context.l10n.hostingMergeConflicting,
            const ValueKey('hosting-status-conflicts'),
          ),
      ],
    );
  }
}
