import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../app/gitlama_layout.dart';
import '../l10n/l10n.dart';

/// Ahead and behind counts of a branch against its upstream (`.ns-sync`).
class GitLamaSyncBadge extends StatelessWidget {
  const GitLamaSyncBadge({
    required this.ahead,
    required this.behind,
    super.key,
    this.showZero = false,
    this.onAccent = false,
  });
  final int ahead;
  final int behind;
  final bool showZero;

  /// Drawn on a solid `accent` selection.
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final synced = ahead == 0 && behind == 0;
    // In sync ↔ counts swap with a rise; counts roll (NM-03, NM-21); a
    // side that reaches 0 fades and collapses.
    return MeridianSwap(
      swapKey: synced,
      style: MeridianSwapStyle.rise,
      alignment: AlignmentDirectional.centerEnd,
      child: synced
          ? (showZero
                ? MeridianIcon(
                    'check',
                    size: MeridianIconSize.small,
                    color: context.colors.inkMuted,
                  )
                : const SizedBox.shrink())
          : Tooltip(
              message: context.l10n.syncAheadBehind(ahead, behind),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MeridianReveal(
                    visible: ahead > 0,
                    axis: Axis.horizontal,
                    child: _SyncPart(
                      icon: 'arrow-up',
                      count: ahead,
                      popOnIncrease: true,
                      color: onAccent
                          ? context.colors.onAccent
                          : context.colors.accentInk,
                    ),
                  ),
                  MeridianReveal(
                    visible: ahead > 0 && behind > 0,
                    axis: Axis.horizontal,
                    child: const SizedBox(width: MeridianSpace.space3),
                  ),
                  MeridianReveal(
                    visible: behind > 0,
                    axis: Axis.horizontal,
                    child: _SyncPart(
                      icon: 'arrow-down',
                      count: behind,
                      color: onAccent
                          ? context.colors.onAccent
                          : context.colors.warning,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SyncPart extends StatelessWidget {
  const _SyncPart({
    required this.icon,
    required this.count,
    required this.color,
    this.popOnIncrease = false,
  });
  final String icon;
  final int count;
  final Color color;
  final bool popOnIncrease;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: GitLamaLayout.syncIconSize,
        child: FittedBox(
          child: MeridianIcon(icon, size: MeridianIconSize.small, color: color),
        ),
      ),
      MeridianRollingNumber(
        value: count,
        popOnIncrease: popOnIncrease,
        style: context.text.caption.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// The one-letter status of a changed file (`.ns-glyph`).
class GitLamaStatusGlyph extends StatelessWidget {
  const GitLamaStatusGlyph(this.status, {this.partial = false, super.key});
  final String status;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground, outline, label) = switch (status) {
      'M' || 'T' => (
        colors.warningBg,
        colors.warning,
        null,
        context.l10n.statusGlyphModified,
      ),
      'A' => (
        colors.successBg,
        colors.success,
        null,
        context.l10n.statusGlyphAdded,
      ),
      'D' => (
        context.git.deletedBg,
        context.git.deleted,
        null,
        context.l10n.statusGlyphDeleted,
      ),
      'R' => (
        colors.accentSoft,
        context.git.renamed,
        null,
        context.l10n.statusGlyphRenamed,
      ),
      'C' => (
        colors.accentSoft,
        context.git.renamed,
        null,
        context.l10n.statusGlyphCopied,
      ),
      'U' => (
        colors.attentionBg,
        colors.attention,
        null,
        context.l10n.statusGlyphConflict,
      ),
      '?' => (
        colors.paneAlt,
        colors.inkMuted,
        colors.lineStrong,
        context.l10n.statusGlyphUntracked,
      ),
      _ => (
        Colors.transparent,
        colors.inkFaint,
        colors.line,
        context.l10n.statusGlyphIgnored,
      ),
    };
    final glyph = status == 'T'
        ? 'M'
        : status == '·'
        ? '!'
        : status;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        width: GitLamaLayout.glyphSize,
        height: GitLamaLayout.glyphSize,
        decoration: BoxDecoration(
          color: partial ? null : background,
          borderRadius: BorderRadius.circular(context.meridian.radius.xs),
          border: outline == null ? null : Border.all(color: outline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(context.meridian.radius.xs),
          child: Stack(
            children: [
              if (partial) ...[
                Positioned.fill(child: ColoredBox(color: background)),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  height: GitLamaLayout.glyphSize / 2,
                  child: ColoredBox(color: colors.paneAlt),
                ),
              ],
              Center(
                child: Text(
                  glyph,
                  style: context.text.glyph.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
