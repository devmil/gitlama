import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../models/inspection.dart';
import 'native_menu.dart';
import 'author_avatar.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

/// A read-only file surface. Attribution occupies a gutter; source text keeps
/// its whitespace, line numbers and a shared horizontal scroll position.
class BlameCodeView extends StatefulWidget {
  const BlameCodeView({
    required this.page,
    required this.rowAt,
    required this.ensureRow,
    required this.onSelectCommit,
    required this.onBlameBefore,
    this.anchor = 0,
    this.onRangeHistory,
    this.onCopyCommit,
    this.onOpenInWindow,
    this.onAnchorChanged,
    super.key,
  });

  final BlamePage page;
  final BlameRow? Function(int index) rowAt;
  final Future<void> Function(int index) ensureRow;
  final ValueChanged<String> onSelectCommit;
  final ValueChanged<BlameRow> onBlameBefore;
  final ValueChanged<BlameRow>? onRangeHistory;
  final ValueChanged<String>? onCopyCommit;

  /// Opens the blame at a line's commit in a new window.
  final ValueChanged<BlameRow>? onOpenInWindow;

  /// Reports the first visible line after scrolling settles.
  final ValueChanged<int>? onAnchorChanged;
  final int anchor;

  @override
  State<BlameCodeView> createState() => _BlameCodeViewState();
}

class _BlameCodeViewState extends State<BlameCodeView> {
  static const _lineHeight = GitLamaLayout.diffLineHeight;
  late final ScrollController _vertical = ScrollController(
    initialScrollOffset: widget.anchor * _lineHeight,
  )..addListener(_scrolled);
  Timer? _anchorReport;

  void _scrolled() {
    final report = widget.onAnchorChanged;
    if (report == null) return;
    _anchorReport?.cancel();
    _anchorReport = Timer(MeridianDurations.quick, () {
      if (!mounted || !_vertical.hasClients) return;
      report((_vertical.offset / _lineHeight).floor());
    });
  }

  @override
  void dispose() {
    _anchorReport?.cancel();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final page = widget.page;
      final tokens = context.meridian;
      final longestLoadedLine = page.rows.fold<int>(
        0,
        (length, row) => math.max(length, row.content.length),
      );
      final contentWidth = math.max(
        constraints.maxWidth,
        math.max(
          1120.0,
          (GitLamaLayout.blameBandWidth +
                  GitLamaLayout.diffGutterWidth +
                  longestLoadedLine * 8.5)
              .clamp(0.0, 20000.0),
        ),
      );
      return Scrollbar(
        thumbVisibility: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: constraints.maxHeight,
            child: ListView.builder(
              controller: _vertical,
              key: ValueKey('blame-code:${page.revision}:${page.path}'),
              itemCount: page.totalRows,
              itemExtent: _lineHeight,
              itemBuilder: (context, index) {
                final row = widget.rowAt(index);
                if (row == null) {
                  unawaited(widget.ensureRow(index));
                }
                final author = row == null
                    ? ''
                    : utf8.decode(row.author, allowMalformed: true);
                final summary = row == null
                    ? ''
                    : utf8.decode(row.summary, allowMalformed: true);
                final commit = row?.commit;
                final previous = index == 0 ? null : widget.rowAt(index - 1);
                final next = index + 1 == page.totalRows
                    ? null
                    : widget.rowAt(index + 1);
                final groupStart =
                    row != null &&
                    (previous == null || previous.commit != commit);
                final groupEnd =
                    row != null && (next == null || next.commit != commit);
                final annotation = groupStart ? author : '';
                return GitLamaContextMenuWidget(
                  menuItems: (_) => row == null
                      ? null
                      : [
                          if (commit != null)
                            NativeMenuAction(
                              value: () => widget.onSelectCommit(commit),
                              title: context.l10n.inspectorShowCommit,
                              icon: 'git-commit-horizontal',
                            ),
                          if (!row.boundary && commit != null)
                            NativeMenuAction(
                              value: () => widget.onBlameBefore(row),
                              title: context.l10n.inspectorBlameBefore,
                              icon: 'blame',
                            ),
                          if (widget.onRangeHistory case final history?)
                            NativeMenuAction(
                              value: () => history(row),
                              title: context.l10n.inspectorLineHistory,
                              icon: 'history',
                            ),
                          if (commit != null &&
                              (widget.onCopyCommit != null ||
                                  widget.onOpenInWindow != null))
                            const NativeMenuAction.separator(),
                          if ((commit, widget.onCopyCommit) case (
                            final commit?,
                            final copy?,
                          ))
                            NativeMenuAction(
                              value: () => copy(commit),
                              title: context.l10n.fileActionCopyCommitHash,
                              icon: 'copy',
                            ),
                          if ((commit, widget.onOpenInWindow) case (
                            _?,
                            final open?,
                          ))
                            NativeMenuAction(
                              value: () => open(row),
                              title: context.l10n.inspectorOpenInWindow,
                              icon: 'app-window',
                            ),
                        ],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: index.isEven
                          ? tokens.colors.pane
                          : tokens.colors.paneAlt.withValues(
                              alpha: GitLamaOpacity.unlit,
                            ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: GitLamaLayout.blameBandWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: commit == null
                                  ? null
                                  : tokens.colors.paneAlt.withValues(
                                      alpha: .65,
                                    ),
                              border: Border(
                                top: groupStart
                                    ? BorderSide(
                                        color: tokens.colors.line,
                                        width: MeridianLayout.hairline,
                                      )
                                    : BorderSide.none,
                                bottom: groupEnd
                                    ? BorderSide(
                                        color: tokens.colors.line,
                                        width: MeridianLayout.hairline,
                                      )
                                    : BorderSide.none,
                                left: BorderSide(
                                  color: commit == null
                                      ? tokens.colors.pane
                                      : tokens.colors.line,
                                  width: GitLamaLayout.diffPickRail,
                                ),
                              ),
                            ),
                            child: Tooltip(
                              message: row == null
                                  ? context.l10n.historyInspectionLoading
                                  : commit == null || row.boundary
                                  ? '$author · $summary'
                                  : '$author · $summary · ${context.l10n.historyBlameBefore}',
                              child: MeridianInteraction(
                                onTap: commit == null || row!.boundary
                                    ? null
                                    : () => widget.onBlameBefore(row),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: MeridianSpace.space4,
                                  ),
                                  child: Row(
                                    children: [
                                      if (groupStart && author.isNotEmpty) ...[
                                        AuthorAvatar(
                                          author: author,
                                          size: MeridianLayout.avatarSmall,
                                        ),
                                        const SizedBox(
                                          width: MeridianSpace.space2,
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          annotation,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.text.rowMeta.copyWith(
                                            color: tokens.colors.ink,
                                          ),
                                        ),
                                      ),
                                      if (groupStart)
                                        Text(
                                          _blameAge(context, row.authorTime),
                                          style: context.text.rowMeta.copyWith(
                                            color: tokens.colors.inkMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        MeridianHairline(
                          axis: Axis.vertical,
                          color: tokens.colors.line,
                        ),
                        SizedBox(
                          width: GitLamaLayout.diffGutterWidth,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: MeridianSpace.space4,
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                '${row?.finalLine ?? index + 1}',
                                style: context.text.codeSm.copyWith(
                                  color: tokens.colors.inkMuted,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        MeridianHairline(
                          axis: Axis.vertical,
                          color: tokens.colors.line,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: GitLamaLayout.diffSignWidth,
                              end: MeridianSpace.space6,
                            ),
                            child: SelectableText(
                              contextMenuBuilder: nativeTextContextMenuBuilder,
                              row == null
                                  ? '…'
                                  : utf8.decode(
                                      row.content,
                                      allowMalformed: true,
                                    ),
                              maxLines: 1,
                              style: context.text.code.copyWith(
                                color: tokens.colors.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

String _blameAge(BuildContext context, int unixSeconds) {
  final seconds = math.max(
    0,
    DateTime.now().millisecondsSinceEpoch ~/ 1000 - unixSeconds,
  );
  if (seconds < 3600) {
    return context.l10n.blameAgeMinutes(math.max(1, seconds ~/ 60));
  }
  if (seconds < 86400) return context.l10n.blameAgeHours(seconds ~/ 3600);
  if (seconds < 86400 * 30) {
    return context.l10n.blameAgeDays(seconds ~/ 86400);
  }
  if (seconds < 86400 * 365) {
    return context.l10n.blameAgeMonths(seconds ~/ (86400 * 30));
  }
  return context.l10n.blameAgeYears(seconds ~/ (86400 * 365));
}
