import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';
import '../models/hosting.dart';
import 'gitlama_git_glyphs.dart';
import 'hosting_status.dart';

enum GitLamaRefKind { head, local, remote, tag, stash, other }

/// A compact Git reference label shared by History and commit details.
class GitLamaRefChip extends StatelessWidget {
  const GitLamaRefChip({
    required this.name,
    required this.kind,
    super.key,
    this.upstream,
    this.lane = 0,
    this.onAccent = false,
    this.detached = false,
    this.ahead = 0,
    this.behind = 0,
    this.checks = HostingCheckState.unknown,
  });

  final String name;
  final GitLamaRefKind kind;
  final String? upstream;
  final int lane;
  final bool onAccent;
  final bool detached;
  final int ahead;
  final int behind;
  final HostingCheckState checks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedOverride =
        onAccent &&
        (kind == GitLamaRefKind.local ||
            kind == GitLamaRefKind.remote ||
            kind == GitLamaRefKind.tag);
    final fill = selectedOverride
        ? colors.onAccentMuted
        : switch (kind) {
            GitLamaRefKind.head => onAccent ? colors.onAccent : colors.ink,
            GitLamaRefKind.local => colors.accentSoft,
            GitLamaRefKind.tag => context.git.tagBg,
            _ => Colors.transparent,
          };
    final ink = selectedOverride
        ? colors.accent
        : switch (kind) {
            GitLamaRefKind.head => onAccent ? colors.accent : colors.pane,
            GitLamaRefKind.local => colors.accentInk,
            GitLamaRefKind.tag => context.git.tagInk,
            _ => onAccent ? colors.onAccent : colors.inkMuted,
          };
    final outline =
        !onAccent &&
        (kind == GitLamaRefKind.remote || kind == GitLamaRefKind.stash);
    Widget chip = Container(
      constraints: const BoxConstraints(
        maxWidth: GitLamaLayout.refChipMaxWidth,
      ),
      height: GitLamaLayout.refChipHeight,
      padding: EdgeInsetsDirectional.only(
        start: kind == GitLamaRefKind.tag
            ? GitLamaLayout.tagPaddingStart
            : GitLamaLayout.refChipPaddingX,
        end: GitLamaLayout.refChipPaddingX,
      ),
      decoration: BoxDecoration(
        color: fill,
        border: outline ? Border.all(color: colors.lineStrong) : null,
        borderRadius: BorderRadius.circular(
          kind == GitLamaRefKind.stash
              ? MeridianRadiusScale.pill
              : context.meridian.radius.sm,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == GitLamaRefKind.remote ||
              kind == GitLamaRefKind.stash ||
              detached) ...[
            _RefIcon(
              detached
                  ? 'circle-dot'
                  : kind == GitLamaRefKind.stash
                  ? 'stash'
                  : 'cloud',
              ink,
            ),
            const SizedBox(width: MeridianSpace.space2),
          ] else if (kind == GitLamaRefKind.head ||
              kind == GitLamaRefKind.local ||
              kind == GitLamaRefKind.tag) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: kind == GitLamaRefKind.head
                    ? ink
                    : colors.series[lane % colors.series.length],
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: GitLamaLayout.refDotSize),
            ),
            const SizedBox(width: MeridianSpace.space2),
          ],
          // The chip hugs the name and keeps both of its ends (the remote
          // and the distinguishing suffix) when it reaches its maximum.
          Flexible(
            child: MeridianMiddleEllipsis(
              name,
              style:
                  (kind == GitLamaRefKind.head
                          ? context.text.chipStrong
                          : context.text.caption)
                      .copyWith(color: ink),
            ),
          ),
          if (upstream != null) ...[
            const SizedBox(width: MeridianSpace.space2),
            Container(
              width: MeridianLayout.hairline,
              height: GitLamaLayout.refPairDividerHeight,
              color: colors.lineStrong,
            ),
            const SizedBox(width: MeridianSpace.space2),
            _RefIcon(
              'cloud',
              kind == GitLamaRefKind.head
                  ? ink.withValues(alpha: GitLamaOpacity.headChipUpstream)
                  : colors.inkMuted,
            ),
            const SizedBox(width: MeridianSpace.space1),
            Flexible(
              child: MeridianMiddleEllipsis(
                upstream!,
                style: context.text.caption.copyWith(
                  color: kind == GitLamaRefKind.head
                      ? ink.withValues(alpha: GitLamaOpacity.headChipUpstream)
                      : colors.inkMuted,
                ),
              ),
            ),
          ] else if (ahead > 0 || behind > 0) ...[
            const SizedBox(width: MeridianSpace.space1),
            GitLamaSyncBadge(ahead: ahead, behind: behind, onAccent: onAccent),
          ],
          if (checks != HostingCheckState.unknown) ...[
            const SizedBox(width: MeridianSpace.space1),
            Tooltip(
              key: const ValueKey('history-branch-checks'),
              message: hostingCheckLabel(context, checks),
              child: HostingPullRequestStatus(
                checks: checks,
                mergeability: HostingMergeability.unknown,
                extent: GitLamaLayout.refIconSize,
                // Filled chips use their own surface, not the selected row's ink.
                onAccent:
                    onAccent &&
                    !selectedOverride &&
                    kind != GitLamaRefKind.head,
                // The checked-out branch's chip is filled with `ink`.
                onInk: !onAccent && kind == GitLamaRefKind.head,
              ),
            ),
          ],
        ],
      ),
    );
    if (kind == GitLamaRefKind.tag) {
      chip = ClipPath(clipper: _TagNotch(), child: chip);
    }
    return Tooltip(
      message: upstream == null ? name : '$name\n$upstream',
      child: chip,
    );
  }
}

/// The pull request of the branch a reference chip names, as its number,
/// followed by its CI result and a conflict mark where the provider reports
/// them. A merged one shows the merge glyph and recedes, as do drafts and
/// one whose head is at another commit.
class GitLamaPullRequestChip extends StatelessWidget {
  const GitLamaPullRequestChip({
    required this.number,
    super.key,
    this.draft = false,
    this.merged = false,
    this.outdated = false,
    this.checks = HostingCheckState.unknown,
    this.mergeability = HostingMergeability.unknown,
    this.onAccent = false,
  });

  final int number;
  final bool draft;
  final bool merged;
  final bool outdated;
  final HostingCheckState checks;
  final HostingMergeability mergeability;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = onAccent
        ? colors.onAccent
        : draft || merged || outdated
        ? colors.inkMuted
        : colors.accentInk;
    return Container(
      height: GitLamaLayout.refChipHeight,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: GitLamaLayout.refChipPaddingX,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: onAccent ? colors.onAccentMuted : colors.lineStrong,
        ),
        borderRadius: BorderRadius.circular(MeridianRadiusScale.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RefIcon(merged ? 'git-merge' : 'git-pull-request', ink),
          const SizedBox(width: MeridianSpace.space1),
          Text('#$number', style: context.text.caption.copyWith(color: ink)),
          if (checks != HostingCheckState.unknown ||
              mergeability == HostingMergeability.conflicting) ...[
            const SizedBox(width: MeridianSpace.space1),
            HostingPullRequestStatus(
              checks: checks,
              mergeability: mergeability,
              extent: GitLamaLayout.refIconSize,
              onAccent: onAccent,
            ),
          ],
        ],
      ),
    );
  }
}

class _RefIcon extends StatelessWidget {
  const _RefIcon(this.name, this.color);
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: GitLamaLayout.refIconSize,
    child: FittedBox(
      fit: BoxFit.contain,
      child: MeridianIcon(name, size: MeridianIconSize.small, color: color),
    ),
  );
}

class _TagNotch extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(GitLamaLayout.tagNotch, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(GitLamaLayout.tagNotch, size.height)
    ..lineTo(0, size.height / 2)
    ..close();

  @override
  bool shouldReclip(covariant _TagNotch oldClipper) => false;
}
