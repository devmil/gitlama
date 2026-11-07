import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'keyboard_reveal.dart';
import 'gitlama_git_glyphs.dart';
import '../app/gitlama_layout.dart';

/// The file row shared by commit details and the working-tree lists.
class GitLamaFileRow extends StatefulWidget {
  const GitLamaFileRow({
    required this.status,
    required this.path,
    required this.onActivate,
    this.added,
    this.deleted,
    this.staged = false,
    this.partial = false,
    this.depth = 0,
    this.onStage,
    this.onDiscard,
    this.stageActionLabel,
    this.stageIcon,
    this.discardActionLabel,
    this.selected = false,
    this.trailing,
    this.leading,
    super.key,
  });

  /// The status letter; empty for a file the shown commit did not change,
  /// which keeps the glyph's slot so names align.
  final String status;
  final String path;
  final int? added;
  final int? deleted;
  final bool staged;
  final bool partial;
  final int depth;
  final VoidCallback onActivate;
  final VoidCallback? onStage;
  final VoidCallback? onDiscard;
  final String? stageActionLabel;

  /// The stage action's icon; the toolbar's per-selection arrow, so the row
  /// and the toolbar show the same glyph for the same action.
  final String? stageIcon;
  final String? discardActionLabel;
  final bool selected;
  final Widget? trailing;

  /// A control before the status glyph, such as a selection checkbox.
  final Widget? leading;

  @override
  State<GitLamaFileRow> createState() => _GitLamaFileRowState();
}

class _GitLamaFileRowState extends State<GitLamaFileRow>
    with KeyboardRevealState {
  bool _hovered = false;
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.space &&
          widget.onStage != null) {
        widget.onStage!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final revealed = _hovered || (_focused && keyboardInput);
    final row = MeridianRowColors.resolve(
      context,
      selected: widget.selected,
      hovered: revealed,
    );
    final slash = widget.path.lastIndexOf('/');
    final directory = slash < 0 ? '' : widget.path.substring(0, slash + 1);
    final name = widget.path.substring(slash + 1);
    final actionsVisible = revealed && widget.onStage != null;
    final actionLabel =
        widget.stageActionLabel ??
        (widget.staged ? context.l10n.unstageFile : context.l10n.stageFile);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.status.isEmpty
          ? widget.path
          : '${widget.status}, ${widget.path}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // Full width like MeridianListRow, so file and folder rows in one
        // tree share the same selection fill.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: row.fill,
            borderRadius: BorderRadius.circular(context.meridian.radius.sm),
          ),
          child: MeridianInteraction(
            focusNode: _focusNode,
            onTap: widget.onActivate,
            child: SizedBox(
              height: context.meridian.density.rowExtent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MeridianSpace.space4 + MeridianSpace.space2,
                ),
                child: Row(
                  children: [
                    SizedBox(width: widget.depth * MeridianLayout.treeIndent),
                    if (widget.leading case final leading?)
                      MeridianSurfaceScope.withFill(
                        context,
                        fill: row.fill,
                        child: leading,
                      ),
                    _StatusFlip(status: widget.status, partial: widget.partial),
                    const SizedBox(width: MeridianSpace.space4),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final nameStyle = context.text.body.copyWith(
                            color: row.primary,
                          );
                          final directoryStyle = context.text.body.copyWith(
                            color: row.secondary,
                          );
                          final suffix = widget.partial
                              ? '  ${context.l10n.changesPartial}'
                              : '';
                          final scaler = MediaQuery.textScalerOf(context);
                          final direction = Directionality.of(context);
                          final nameWidth = _fileTextWidth(
                            '$name$suffix',
                            nameStyle,
                            scaler,
                            direction,
                          );
                          final shownDirectory = _elideDirectoryStart(
                            directory,
                            constraints.maxWidth - nameWidth,
                            directoryStyle,
                            scaler,
                            direction,
                          );
                          return Text.rich(
                            TextSpan(
                              children: [
                                if (shownDirectory.isNotEmpty)
                                  TextSpan(
                                    text: shownDirectory,
                                    style: directoryStyle,
                                  ),
                                TextSpan(text: name, style: nameStyle),
                                if (widget.partial)
                                  TextSpan(
                                    text: suffix,
                                    style: context.text.caption.copyWith(
                                      color: row.secondary,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: MeridianSpace.space3),
                    if (actionsVisible) ...[
                      // Publishing the row fill keeps the actions visible on
                      // a focused (solid accent) selection.
                      MeridianSurfaceScope.withFill(
                        context,
                        fill: row.fill,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MeridianIconButton(
                              label: actionLabel,
                              icon:
                                  widget.stageIcon ??
                                  (widget.staged ? 'unstage-all' : 'stage-all'),
                              size: MeridianControlSize.small,
                              onPressed: widget.onStage,
                            ),
                            if (!widget.staged && widget.onDiscard != null)
                              MeridianIconButton(
                                label:
                                    widget.discardActionLabel ??
                                    context.l10n.discardFile,
                                icon: 'undo',
                                size: MeridianControlSize.small,
                                onPressed: widget.onDiscard,
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      if (widget.added case final added?)
                        Text(
                          '+$added',
                          style: context.text.codeSm.copyWith(
                            color:
                                widget.selected &&
                                    row.primary == colors.onAccent
                                ? colors.onAccentMuted
                                : colors.success,
                          ),
                        ),
                      if (widget.deleted case final deleted?) ...[
                        const SizedBox(width: MeridianSpace.space3),
                        Text(
                          '−$deleted',
                          style: context.text.codeSm.copyWith(
                            color:
                                widget.selected &&
                                    row.primary == colors.onAccent
                                ? colors.onAccentMuted
                                : context.git.deleted,
                          ),
                        ),
                      ],
                    ],
                    if (widget.trailing case final trailing?)
                      MeridianSurfaceScope.withFill(
                        context,
                        fill: row.fill,
                        child: IconTheme.merge(
                          data: IconThemeData(color: row.icon),
                          child: trailing,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns a changed Git status mark edge-on before revealing the new mark.
class _StatusFlip extends StatefulWidget {
  const _StatusFlip({required this.status, required this.partial});

  final String status;
  final bool partial;

  @override
  State<_StatusFlip> createState() => _StatusFlipState();
}

class _StatusFlipState extends State<_StatusFlip> {
  late String _shownStatus = widget.status;
  late bool _shownPartial = widget.partial;
  var _scale = 1.0;
  Timer? _midpoint;

  @override
  void didUpdateWidget(covariant _StatusFlip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == oldWidget.status &&
        widget.partial == oldWidget.partial) {
      return;
    }
    _midpoint?.cancel();
    if (MeridianMotion.reduced(context)) {
      _shownStatus = widget.status;
      _shownPartial = widget.partial;
      _scale = 1;
      return;
    }
    _scale = 0;
    _midpoint = Timer((MeridianDurations.quick ~/ 2) * timeDilation, () {
      if (!mounted) return;
      setState(() {
        _shownStatus = widget.status;
        _shownPartial = widget.partial;
        _scale = 1;
      });
    });
  }

  @override
  void dispose() {
    _midpoint?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _shownStatus.isEmpty
      // An unchanged file keeps the glyph's slot so names align.
      ? const SizedBox.square(dimension: GitLamaLayout.glyphSize)
      : MeridianAnimatedValue(
          value: _scale,
          duration: MeridianDurations.quick ~/ 2,
          curve: _scale == 0 ? MeridianCurves.exit : MeridianCurves.standard,
          builder: (context, scale, child) =>
              Transform.scale(scaleY: scale, child: child),
          child: GitLamaStatusGlyph(_shownStatus, partial: _shownPartial),
        );
}

double _fileTextWidth(
  String value,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

String _elideDirectoryStart(
  String directory,
  double available,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
) {
  if (directory.isEmpty || available <= 0) return '';
  if (_fileTextWidth(directory, style, scaler, direction) <= available) {
    return directory;
  }
  if (_fileTextWidth('…', style, scaler, direction) > available) return '';
  final parts = directory.characters.toList(growable: false);
  var low = 0;
  var high = parts.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final candidate = '…${parts.skip(middle).join()}';
    if (_fileTextWidth(candidate, style, scaler, direction) <= available) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return '…${parts.skip(low).join()}';
}
