import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';
import 'gitlama_git_glyphs.dart';

/// The repository context in the window bar; it opens the repository's
/// details.
class GitLamaCompass extends StatefulWidget {
  const GitLamaCompass({
    required this.repository,
    required this.branch,
    required this.onShowDetails,
    super.key,
    this.detached = false,
    this.ahead = 0,
    this.behind = 0,
    this.dirty = 0,
    this.conflicts = 0,
    this.operation,
    this.operationDetail,
    this.progress,
    this.activeProgress = false,
    this.syncSequence = 0,
    this.syncChanged = false,
    this.compact = false,
  });

  final String repository;
  final String? branch;
  final bool detached;
  final int ahead;
  final int behind;
  final int dirty;
  final int conflicts;
  final String? operation;

  /// [operation] with its current phase and completion. It replaces the text
  /// in place, so a percentage that counts up does not replay the swap.
  final String? operationDetail;
  final double? progress;
  final bool activeProgress;
  final int syncSequence;
  final bool syncChanged;
  final VoidCallback onShowDetails;
  final bool compact;

  @override
  State<GitLamaCompass> createState() => _GitLamaCompassState();
}

class _GitLamaCompassState extends State<GitLamaCompass> {
  /// Changes appeared while the Compass was on screen (NM-04).
  var _dirtyAppeared = false;
  var _shown = false;
  late bool _showConflictCount = widget.conflicts > 0;
  Timer? _conflictCollapse;

  @override
  void didUpdateWidget(GitLamaCompass oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dirtyAppeared = _shown && oldWidget.dirty == 0 && widget.dirty > 0;
    if (widget.conflicts > 0) {
      _conflictCollapse?.cancel();
      _showConflictCount = true;
    } else if (oldWidget.conflicts > 0) {
      _conflictCollapse?.cancel();
      _conflictCollapse = Timer(const Duration(milliseconds: 200), () {
        if (mounted && widget.conflicts == 0) {
          setState(() => _showConflictCount = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _conflictCollapse?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _shown = true;
    final repository = widget.repository;
    final branch = widget.branch;
    final detached = widget.detached;
    final ahead = widget.ahead;
    final behind = widget.behind;
    final dirty = widget.dirty;
    final conflicts = widget.conflicts;
    final operation = widget.operation;
    final progress = widget.progress;
    final activeProgress = widget.activeProgress;
    final onShowDetails = widget.onShowDetails;
    final compact = widget.compact;
    final colors = context.colors;
    final label = context.l10n.compassSemantics(
      repository,
      branch ?? context.l10n.detachedHead,
      ahead,
      behind,
      dirty,
      conflicts,
    );
    return Tooltip(
      message: context.l10n.repositoryDetailsTitle,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: compact
              ? GitLamaLayout.compassCompactMinWidth
              : GitLamaLayout.compassMinWidth,
          maxWidth: GitLamaLayout.compassMaxWidth,
        ),
        child: Semantics(
          excludeSemantics: true,
          button: true,
          label: label,
          onTap: onShowDetails,
          child: MeridianInteraction(
            onTap: onShowDetails,
            borderRadius: BorderRadius.circular(MeridianRadiusScale.pill),
            // The pill hugs its content between the min and max width and
            // follows it over motion-layout when the content changes
            // (NM-02). The hover edge fades in and out (NM-05).
            builder: (context, state) => AnimatedContainer(
              duration: meridianHoverDuration(context, state.hovered),
              height: GitLamaLayout.compassHeight,
              decoration: BoxDecoration(
                color: colors.pane,
                border: Border.all(
                  color: state.hovered
                      ? colors.lineStrong
                      : meridianClear(colors.lineStrong),
                ),
                borderRadius: BorderRadius.circular(MeridianRadiusScale.pill),
                boxShadow: context.meridian.shadows.shadowPane,
              ),
              child: MeridianResize(
                child: IntrinsicWidth(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      MeridianRadiusScale.pill,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: _CompassGlint(
                            sequence: widget.syncSequence,
                            changed: widget.syncChanged,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: MeridianSpace.space5,
                            end: MeridianSpace.space3,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!compact) ...[
                                      Flexible(
                                        flex: 3,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: GitLamaLayout
                                                .compassRepositoryMaxWidth,
                                          ),
                                          child: Text(
                                            repository,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.text.bodyStrong
                                                .copyWith(color: colors.ink),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '  /  ',
                                        style: context.text.body.copyWith(
                                          color: colors.inkFaint,
                                        ),
                                      ),
                                    ],
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        end: MeridianSpace.space2,
                                      ),
                                      child: MeridianIcon(
                                        detached ? 'circle-dot' : 'branch',
                                        size: MeridianIconSize.small,
                                        color: colors.accentInk,
                                      ),
                                    ),
                                    // A checkout swaps the branch name with a
                                    // rise (NM-02).
                                    Flexible(
                                      flex: 4,
                                      child: MeridianSwap(
                                        swapKey: branch,
                                        style: MeridianSwapStyle.rise,
                                        child: Text(
                                          branch ?? context.l10n.detachedHead,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.text.compassBranch
                                              .copyWith(
                                                color: colors.accentInk,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: MeridianSpace.space5),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // The state and a running operation swap
                                  // with a rise (NM-01).
                                  MeridianSwap(
                                    swapKey: operation == null
                                        ? 'state'
                                        : 'op:$operation',
                                    style: MeridianSwapStyle.rise,
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: operation == null
                                        ? _CompassState(
                                            ahead: ahead,
                                            behind: behind,
                                            dirty: dirty,
                                            conflicts: conflicts,
                                            showConflictCount:
                                                _showConflictCount,
                                            dirtyPopIn: _dirtyAppeared,
                                          )
                                        : ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: GitLamaLayout
                                                  .compassBranchMaxWidth,
                                            ),
                                            child: Text(
                                              widget.operationDetail ??
                                                  operation,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: context.text.label
                                                  .copyWith(color: colors.ink),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _CompassRule(
                            active: operation != null || activeProgress,
                            progress: progress,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-shot sync sweep runs only for a changed, person-started transfer.
class _CompassGlint extends StatefulWidget {
  const _CompassGlint({required this.sequence, required this.changed});

  final int sequence;
  final bool changed;

  @override
  State<_CompassGlint> createState() => _CompassGlintState();
}

class _CompassGlintState extends State<_CompassGlint> {
  Timer? _delay;
  var _target = 0.0;
  var _visible = false;

  @override
  void didUpdateWidget(covariant _CompassGlint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sequence == oldWidget.sequence) return;
    _delay?.cancel();
    _target = 0;
    _visible = widget.changed && !MeridianMotion.reduced(context);
    if (!_visible) return;
    _delay = Timer(GitLamaMotion.syncGlintDelay * timeDilation, () {
      if (mounted) setState(() => _target = 1);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return MeridianAnimatedValue(
      key: ValueKey(('compass-glint', widget.sequence)),
      value: _target,
      duration: GitLamaMotion.glint,
      curve: MeridianCurves.standard,
      builder: (context, progress, _) => CustomPaint(
        key: const ValueKey('compass-glint-paint'),
        painter: CompassGlintPainter(
          progress: progress,
          color: context.colors.accentSoft,
        ),
      ),
    );
  }
}

/// Paints a clipped 40 px sweep from outside the leading edge to the trailing
/// edge. The parent Compass supplies the pill clip.
class CompassGlintPainter extends CustomPainter {
  const CompassGlintPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  double centerX(Size size) =>
      -GitLamaMotion.glintWidth +
      (size.width + GitLamaMotion.glintWidth * 2) * progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerX(size);
    final half = GitLamaMotion.glintWidth / 2;
    final rect = Rect.fromLTRB(center - half, 0, center + half, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            meridianClear(color),
            color.withValues(alpha: GitLamaOpacity.glint),
            meridianClear(color),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CompassGlintPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}

/// The Compass's repository state: conflicts, changed files and sync.
class _CompassState extends StatelessWidget {
  const _CompassState({
    required this.ahead,
    required this.behind,
    required this.dirty,
    required this.conflicts,
    required this.showConflictCount,
    required this.dirtyPopIn,
  });

  final int ahead;
  final int behind;
  final int dirty;
  final int conflicts;
  final bool showConflictCount;
  final bool dirtyPopIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MeridianReveal(
          visible: showConflictCount,
          axis: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MeridianCount(
                label: context.l10n.compassConflicts(conflicts),
                tone: MeridianCountTone.attention,
                emphasizeIncrease: true,
              ),
              const SizedBox(width: MeridianSpace.space4),
            ],
          ),
        ),
        if (dirty > 0) ...[
          Tooltip(
            message: context.l10n.compassChangedFiles(dirty),
            child: _DirtyCount(dirty: dirty, popIn: dirtyPopIn),
          ),
          const SizedBox(width: MeridianSpace.space4),
        ],
        GitLamaSyncBadge(ahead: ahead, behind: behind, showZero: true),
      ],
    );
  }
}

/// The changed-file count: its dot pops in when changes appear (NM-04)
/// and the number rolls (NM-03). It does not pulse: dirty is a state.
class _DirtyCount extends StatefulWidget {
  const _DirtyCount({required this.dirty, required this.popIn});

  final int dirty;

  /// Changes just appeared on a Compass that was already on screen.
  final bool popIn;

  @override
  State<_DirtyCount> createState() => _DirtyCountState();
}

class _DirtyCountState extends State<_DirtyCount>
    with SingleTickerProviderStateMixin {
  late final MeridianSpringController _dot = MeridianSpringController(
    vsync: this,
    value: 1,
  );
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.popIn && !MeridianMotion.reduced(context)) {
      _dot
        ..jumpTo(0)
        ..animateTo(1, spring: MeridianSprings.pop);
    }
  }

  @override
  void dispose() {
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = context.text.caption.copyWith(color: context.colors.warning);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _dot.animation,
          builder: (context, child) =>
              Transform.scale(scale: _dot.value, child: child),
          child: Text('●', style: style),
        ),
        Text(' ', style: style),
        MeridianRollingNumber(value: widget.dirty, style: style),
      ],
    );
  }
}

/// The Compass's progress rule: it enters from the bottom edge over
/// `motion-quick` (NM-01); when the operation ends it fills to 100%, holds
/// and fades (NH-2, MM-63).
class _CompassRule extends StatefulWidget {
  const _CompassRule({required this.active, required this.progress});

  final bool active;
  final double? progress;

  @override
  State<_CompassRule> createState() => _CompassRuleState();
}

class _CompassRuleState extends State<_CompassRule> {
  var _finishing = false;
  Timer? _finish;

  @override
  void didUpdateWidget(_CompassRule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      // Fill to 100%, hold and fade, then collapse.
      _finish?.cancel();
      if (MeridianMotion.reduced(context)) return;
      setState(() => _finishing = true);
      _finish = Timer(
        (MeridianDurations.emphasized +
                MeridianDurations.progressHold +
                MeridianDurations.exit) *
            timeDilation,
        () {
          if (mounted) setState(() => _finishing = false);
        },
      );
    } else if (widget.active) {
      _finish?.cancel();
      _finishing = false;
    }
  }

  @override
  void dispose() {
    _finish?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = widget.active || _finishing;
    return MeridianReveal(
      visible: showing,
      axisAlignment: 1,
      duration: MeridianDurations.quick,
      child: MeridianProgressBar(
        value: _finishing ? 1 : widget.progress,
        persistent: widget.active,
      ),
    );
  }
}
