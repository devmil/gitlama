import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

enum GitLamaTimelineState { running, succeeded, warning, failed, cancelled }

/// Shared Logbook and Activity timeline row. Content remains selectable in its
/// expanded slot while the summary is a single keyboard and pointer target.
class GitLamaTimelineRow extends StatefulWidget {
  const GitLamaTimelineRow({
    required this.state,
    required this.verb,
    required this.target,
    required this.metadata,
    required this.time,
    required this.onActivate,
    super.key,
    this.expanded,
    this.first = false,
    this.last = false,
    this.selected = false,
    this.shakeOnFailure = false,
  });

  final GitLamaTimelineState state;
  final String verb;
  final String target;
  final String metadata;
  final String time;
  final VoidCallback onActivate;
  final Widget? expanded;
  final bool first;
  final bool last;
  final bool selected;
  final bool shakeOnFailure;

  @override
  State<GitLamaTimelineRow> createState() => _GitLamaTimelineRowState();
}

class _GitLamaTimelineRowState extends State<GitLamaTimelineRow> {
  Widget? _retainedExpanded;
  var _failureTrigger = 0;
  var _drawCompletion = false;
  Timer? _completionTimer;

  @override
  void initState() {
    super.initState();
    _retainedExpanded = widget.expanded;
  }

  @override
  void didUpdateWidget(covariant GitLamaTimelineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != null) _retainedExpanded = widget.expanded;
    if (oldWidget.state != widget.state) {
      _completionTimer?.cancel();
      _drawCompletion =
          oldWidget.state == GitLamaTimelineState.running &&
          widget.state == GitLamaTimelineState.succeeded;
      if (_drawCompletion) {
        _completionTimer = Timer(GitLamaMotion.landRingClose, () {
          if (mounted) setState(() => _drawCompletion = false);
        });
      }
    }
    if (widget.shakeOnFailure &&
        oldWidget.state != GitLamaTimelineState.failed &&
        widget.state == GitLamaTimelineState.failed) {
      _failureTrigger++;
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final selected = widget.selected;
    final first = widget.first;
    final last = widget.last;
    final onActivate = widget.onActivate;
    final verb = widget.verb;
    final target = widget.target;
    final time = widget.time;
    final metadata = widget.metadata;
    final expanded = widget.expanded;
    final colors = context.colors;
    final tone = switch (state) {
      GitLamaTimelineState.running => colors.accent,
      GitLamaTimelineState.succeeded => colors.success,
      GitLamaTimelineState.warning => colors.warning,
      GitLamaTimelineState.failed => colors.danger,
      GitLamaTimelineState.cancelled => colors.inkMuted,
    };
    final icon = switch (state) {
      GitLamaTimelineState.running => null,
      GitLamaTimelineState.succeeded => 'check',
      GitLamaTimelineState.warning => 'triangle-alert',
      GitLamaTimelineState.failed => 'close',
      GitLamaTimelineState.cancelled => 'minus',
    };
    final rail = PositionedDirectional(
      start:
          MeridianSpace.space6 +
          (GitLamaLayout.logbookMarkSize - GitLamaLayout.logbookRailWidth) / 2,
      top: first ? MeridianSpace.space3 + GitLamaLayout.logbookMarkSize / 2 : 0,
      bottom: last
          ? MeridianSpace.space3 + GitLamaLayout.logbookMarkSize / 2
          : 0,
      width: GitLamaLayout.logbookRailWidth,
      child: MeridianAnimatedValue(
        value: state == GitLamaTimelineState.succeeded ? 1 : 0,
        duration: MeridianDurations.select,
        builder: (context, progress, child) => ColoredBox(
          color: Color.lerp(colors.line, colors.success, progress)!,
        ),
      ),
    );
    return MeridianShake(
      trigger: _failureTrigger,
      strength: MeridianShakeStrength.field,
      child: MeridianInteraction(
        onTap: onActivate,
        // The selected and hovered fills sit under the rail, so the line
        // runs unbroken through the selected row.
        builder: (context, interaction) => ColoredBox(
          color: selected
              ? colors.accentSoft
              : interaction.hovered
              ? colors.paneHover
              : Colors.transparent,
          child: Stack(
            children: [
              rail,
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MeridianSpace.space6,
                  vertical: MeridianSpace.space3,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: GitLamaLayout.logbookMarkSize,
                      height: GitLamaLayout.logbookMarkSize,
                      decoration: BoxDecoration(
                        color: colors.raised,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: state == GitLamaTimelineState.cancelled
                              ? colors.lineStrong
                              : tone,
                          width: GitLamaLayout.logbookRailWidth,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: MeridianSwap(
                        swapKey: state,
                        style: state == GitLamaTimelineState.failed
                            ? MeridianSwapStyle.scale
                            : MeridianSwapStyle.fade,
                        child: icon == null
                            ? MeridianSpinner(color: tone)
                            : state == GitLamaTimelineState.succeeded &&
                                  _drawCompletion
                            ? MeridianStrokeIcon(
                                'check',
                                duration: GitLamaMotion.landRingClose,
                                color: tone,
                                size: MeridianTheme.of(
                                  context,
                                ).density.iconSmallSize,
                                appear: true,
                              )
                            : MeridianIcon(
                                icon,
                                size: MeridianIconSize.small,
                                color: tone,
                              ),
                      ),
                    ),
                    const SizedBox(width: MeridianSpace.space4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: verb,
                                        style: context.text.bodyStrong.copyWith(
                                          color: colors.ink,
                                        ),
                                      ),
                                      if (target.isNotEmpty)
                                        TextSpan(
                                          text: ' $target',
                                          style: context.text.body.copyWith(
                                            color: colors.ink,
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: MeridianSpace.space3),
                              Text(
                                time,
                                style: context.text.caption.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                          if (metadata.isNotEmpty)
                            Text(
                              metadata,
                              style: context.text.caption.copyWith(
                                color: colors.inkMuted,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          MeridianReveal(
                            visible: expanded != null,
                            child: Column(
                              children: [
                                const SizedBox(height: MeridianSpace.space3),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: MeridianSpace.space5,
                                    vertical: MeridianSpace.space4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: switch (state) {
                                      GitLamaTimelineState.warning =>
                                        colors.warningBg,
                                      GitLamaTimelineState.failed =>
                                        colors.dangerBg,
                                      _ => colors.paneAlt,
                                    },
                                    borderRadius: BorderRadius.circular(
                                      context.meridian.radius.md,
                                    ),
                                  ),
                                  child:
                                      expanded ??
                                      _retainedExpanded ??
                                      const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
