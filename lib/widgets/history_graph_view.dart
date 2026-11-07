import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'native_menu.dart';
import 'author_avatar.dart';
import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../models/history_graph.dart';
import '../models/hosting.dart';
import 'hosting_status.dart';
import '../models/reference_name.dart';
import 'history_motion.dart';
import 'gitlama_ref_chip.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

typedef HistoryRowProvider = HistoryGraphRow Function(int index);
typedef HistoryRowIndex = int? Function(String objectId);
typedef HistorySemanticLabelBuilder = String Function(HistoryGraphRow row);
typedef HistoryContextMenuBuilder =
    List<NativeMenuAction> Function(HistoryGraphRow row);
typedef HistoryReferenceContextMenuBuilder =
    List<NativeMenuAction>? Function(HistoryGraphRow row, String reference);

double historyGraphWidthForLaneCount(int laneCount) =>
    GitLamaLayout.graphLaneOrigin +
    laneCount * GitLamaLayout.laneWidth +
    GitLamaLayout.graphNodeInkRadius;

double historyLaneX(int lane) =>
    GitLamaLayout.graphLaneOrigin + lane * GitLamaLayout.laneWidth;

double historyRowContentStart(
  int lane,
  Iterable<HistoryGraphSegment> segments,
) {
  var occupiedLane = lane;
  for (final segment in segments) {
    occupiedLane = math.max(
      occupiedLane,
      math.max(segment.fromLane, segment.toLane),
    );
  }
  return (historyLaneX(occupiedLane) +
          GitLamaLayout.graphNodeInkRadius +
          MeridianSpace.space4)
      .ceilToDouble();
}

/// Fixed-extent virtualized history proof. Rust supplies topology, lanes and geometry;
/// this widget paints only the rows Flutter asks for.
class HistoryGraphView extends StatelessWidget {
  const HistoryGraphView({
    required this.itemCount,
    required this.rowAt,
    this.indexOfObjectId,
    required this.onSelected,
    this.alignedUpstreams = const {},
    this.checkedOutRef,
    this.refSyncCounts = const {},
    this.selectedObjectId,
    this.selectedObjectIds,
    this.rowExtent = 24,
    this.controller,
    this.isSelectable,
    this.lightingActive = false,
    this.queryActive = false,
    this.onCopyValue,
    this.semanticLabelBuilder,
    this.onToggleSelected,
    this.onDoubleClick,
    this.onRevealObjectId,
    this.onContextMenu,
    this.onReferenceContextMenu,
    this.onOpenPullRequest,
    this.dateFormat = 'iso',
    this.metadataAuthorWidth = 132,
    this.metadataHashWidth = 72,
    this.metadataDateWidth = 84,
    this.headLabel,
    this.flashObjectId,
    this.flashSequence = 0,
    this.footer,
    this.motion,
    this.selectedIndex,
    this.attentionObjectId,
    this.attentionSequence = 0,
    this.copiedLabel,
    this.syncEntranceIds = const {},
    this.syncSequence = 0,
    super.key,
  });

  final int itemCount;
  final HistoryRowProvider rowAt;

  /// Finds a loaded row after insertion or removal so its element and
  /// semantics node move with the commit instead of being recreated.
  final HistoryRowIndex? indexOfObjectId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onDoubleClick;
  final Map<String, String> alignedUpstreams;
  final String? checkedOutRef;
  final Map<String, ({int ahead, int behind})> refSyncCounts;
  final String? selectedObjectId;
  final Set<String>? selectedObjectIds;
  final double rowExtent;
  final ScrollController? controller;
  final bool Function(HistoryGraphRow row)? isSelectable;
  final bool lightingActive;
  final bool queryActive;
  final ValueChanged<String>? onCopyValue;
  final HistorySemanticLabelBuilder? semanticLabelBuilder;
  final ValueChanged<String>? onToggleSelected;
  final ValueChanged<String>? onRevealObjectId;
  final HistoryContextMenuBuilder? onContextMenu;
  final HistoryReferenceContextMenuBuilder? onReferenceContextMenu;

  /// Opens a row's [HistoryGraphRow.pullRequests] entry.
  final ValueChanged<HistoryReferencePullRequest>? onOpenPullRequest;
  final String dateFormat;
  final double metadataAuthorWidth;
  final double metadataHashWidth;
  final double metadataDateWidth;
  final String? headLabel;
  final String? flashObjectId;
  final int flashSequence;
  final Widget? footer;

  /// The graph's motion: lane lighting, lane drawing and the commit
  /// landing (docs/design-system/specs/motion.md).
  final HistoryMotion? motion;

  /// The index of the single selected row. With a [controller] the
  /// selection bar glides between rows (NM-31); multi-selection and
  /// comparison ranges keep per-row fills.
  final int? selectedIndex;

  /// A row to point at once (a search match reached with next or
  /// previous, NM-33): each new [attentionSequence] tints it.
  final String? attentionObjectId;
  final int attentionSequence;

  /// Shown for a moment in place of a hash that was copied (NM-34).
  final String? copiedLabel;
  final Set<String> syncEntranceIds;
  final int syncSequence;

  /// The padding around the rows, above the first row included.
  static const listPadding = MeridianSpace.space2;

  @override
  Widget build(BuildContext context) {
    final litRows = <int, bool>{};
    final motion = this.motion;
    final glide =
        controller != null &&
        selectedIndex != null &&
        (selectedObjectIds == null || selectedObjectIds!.length <= 1);
    Widget list = ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(listPadding),
      itemCount: itemCount + (footer == null ? 0 : 1),
      itemExtent: rowExtent,
      findChildIndexCallback: indexOfObjectId == null
          ? null
          : (key) {
              if (key is! ValueKey<String> ||
                  !key.value.startsWith('history-row-')) {
                return null;
              }
              final objectId = key.value.substring('history-row-'.length);
              if (objectId.startsWith('loading-')) {
                final index = int.tryParse(
                  objectId.substring('loading-'.length),
                );
                return index != null && index >= 0 && index < itemCount
                    ? index
                    : null;
              }
              return indexOfObjectId!(objectId);
            },
      itemBuilder: (context, index) {
        if (index == itemCount) return footer!;
        final row = rowAt(index);
        if (row.objectId.startsWith('loading-')) {
          // Rows still loading breathe as skeletons; the loaded rows fade
          // in over them (NM-38).
          motion?.notePlaceholder(index);
          return RepaintBoundary(
            key: ValueKey('history-row-${row.objectId}'),
            child: _LoadingRow(geometry: row.geometry),
          );
        }
        litRows[index] = row.lit;
        final incomingLit = index == 0
            ? row.lit
            : litRows.putIfAbsent(index - 1, () => rowAt(index - 1).lit);
        final rowWidget = _HistoryRow(
          row: row,
          index: index,
          motion: motion,
          glided: glide,
          attentionTrigger: attentionObjectId == row.objectId
              ? attentionSequence
              : 0,
          alignedUpstreams: alignedUpstreams,
          checkedOutRef: checkedOutRef,
          refSyncCounts: refSyncCounts,
          selected:
              selectedObjectIds?.contains(row.objectId) ??
              (row.selected || selectedObjectId == row.objectId),
          comparisonHighlighted: row.compared,
          selectable: isSelectable?.call(row) ?? true,
          onSelected: onSelected,
          onDoubleClick: onDoubleClick,
          lightingActive: lightingActive,
          queryActive: queryActive,
          incomingLit: incomingLit,
          onCopyValue: onCopyValue,
          semanticLabel: semanticLabelBuilder?.call(row),
          onToggleSelected: onToggleSelected,
          onRevealObjectId: onRevealObjectId,
          onReferenceContextMenu: onReferenceContextMenu,
          onOpenPullRequest: onOpenPullRequest,
          dateFormat: dateFormat,
          metadataAuthorWidth: metadataAuthorWidth,
          metadataHashWidth: metadataHashWidth,
          metadataDateWidth: metadataDateWidth,
          headLabel: headLabel,
          copiedLabel: copiedLabel,
          flashSequence: flashObjectId == row.objectId ? flashSequence : null,
        );
        Widget content = onContextMenu == null
            ? rowWidget
            : GitLamaContextMenuWidget(
                menuItems: (_) => onContextMenu!(row),
                child: rowWidget,
              );
        if (motion != null) {
          content = _LoadedFade(motion: motion, index: index, child: content);
        }
        if (syncEntranceIds.contains(row.objectId)) {
          content = MeridianEntrance(
            entranceKey: ('history-sync-row', row.objectId, syncSequence),
            index: syncEntranceIds.toList().indexOf(row.objectId),
            child: content,
          );
        }
        return RepaintBoundary(
          key: ValueKey('history-row-${row.objectId}'),
          child: motion == null
              ? content
              // A row inserted above (NH-1) slides the rows below down from
              // their old places; the new row fades in.
              : AnimatedBuilder(
                  animation: motion,
                  child: content,
                  builder: (context, child) {
                    final insertion = motion.insertion(index);
                    return Transform.translate(
                      offset: Offset(
                        0,
                        insertion == null ? 0 : -rowExtent * insertion.shift,
                      ),
                      child: Opacity(
                        opacity: insertion?.opacity ?? 1,
                        child: child,
                      ),
                    );
                  },
                ),
        );
      },
    );
    if (controller != null) {
      list = MeridianSelectionGlide(
        controller: controller!,
        itemExtent: rowExtent,
        selectedIndex: glide ? selectedIndex : null,
        padding: const EdgeInsets.all(listPadding),
        indicator: const MeridianSelectionFill(),
        child: list,
      );
    }
    if (motion == null) return list;
    return HistoryMotionScope(motion: motion, child: list);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.row,
    required this.index,
    required this.motion,
    required this.glided,
    required this.attentionTrigger,
    required this.alignedUpstreams,
    required this.checkedOutRef,
    required this.refSyncCounts,
    required this.selected,
    required this.comparisonHighlighted,
    required this.onSelected,
    required this.onDoubleClick,
    required this.selectable,
    required this.lightingActive,
    required this.queryActive,
    required this.incomingLit,
    required this.onCopyValue,
    required this.semanticLabel,
    required this.onToggleSelected,
    required this.onRevealObjectId,
    required this.onReferenceContextMenu,
    required this.onOpenPullRequest,
    required this.dateFormat,
    required this.metadataAuthorWidth,
    required this.metadataHashWidth,
    required this.metadataDateWidth,
    required this.headLabel,
    required this.copiedLabel,
    required this.flashSequence,
  });

  final HistoryGraphRow row;
  final int index;
  final HistoryMotion? motion;

  /// A `MeridianSelectionGlide` paints this row's selection bar.
  final bool glided;
  final int attentionTrigger;
  final Map<String, String> alignedUpstreams;
  final String? checkedOutRef;
  final Map<String, ({int ahead, int behind})> refSyncCounts;
  final bool selected;
  final bool comparisonHighlighted;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onDoubleClick;
  final bool selectable;
  final bool lightingActive;
  final bool queryActive;
  final bool incomingLit;
  final ValueChanged<String>? onCopyValue;
  final String? semanticLabel;
  final ValueChanged<String>? onToggleSelected;
  final ValueChanged<String>? onRevealObjectId;
  final HistoryReferenceContextMenuBuilder? onReferenceContextMenu;
  final ValueChanged<HistoryReferencePullRequest>? onOpenPullRequest;
  final String dateFormat;
  final double metadataAuthorWidth;
  final double metadataHashWidth;
  final double metadataDateWidth;
  final String? headLabel;
  final String? copiedLabel;
  final int? flashSequence;

  T? _referenceValue<T>(_DisplayReference reference, Map<String, T> values) =>
      values[reference.raw] ??
      switch (reference.tracking) {
        final tracking? => values[tracking],
        null => null,
      };

  Widget _referenceBadge(
    BuildContext context,
    _DisplayReference reference,
    bool onAccent,
  ) {
    final menu = onReferenceContextMenu?.call(row, reference.raw);
    final sync = refSyncCounts[reference.raw];
    final badge = MeridianInteraction(
      onTap: onCopyValue == null
          ? null
          : onRevealObjectId == null
          ? () => onCopyValue!(reference.raw)
          : () => onRevealObjectId!(row.objectId),
      onSecondaryTap: menu == null && onCopyValue != null
          ? () => onCopyValue!(reference.raw)
          : null,
      borderRadius: BorderRadius.circular(context.meridian.radius.sm),
      child: GitLamaRefChip(
        name: reference.label,
        kind: row.current && reference.raw == checkedOutRef
            ? GitLamaRefKind.head
            : switch (reference.kind) {
                _ReferenceKind.local => GitLamaRefKind.local,
                _ReferenceKind.remote => GitLamaRefKind.remote,
                _ReferenceKind.tag => GitLamaRefKind.tag,
                _ReferenceKind.stash => GitLamaRefKind.stash,
                _ReferenceKind.other => GitLamaRefKind.other,
              },
        upstream: switch (reference.tracking) {
          final tracking? => ReferenceName.parse(tracking).display,
          null => null,
        },
        lane: row.lane,
        onAccent: onAccent,
        ahead: reference.tracking == null ? sync?.ahead ?? 0 : 0,
        behind: reference.tracking == null ? sync?.behind ?? 0 : 0,
        checks: _referenceValue(reference, row.pullRequests) == null
            ? _referenceValue(reference, row.branchChecks) ??
                  HostingCheckState.unknown
            : HostingCheckState.unknown,
      ),
    );
    final chip = menu == null
        ? badge
        : GitLamaContextMenuWidget(
            key: ValueKey('history-ref-${reference.raw}'),
            menuItems: (_) => menu,
            child: badge,
          );
    if (row.current &&
        reference.raw == checkedOutRef &&
        flashSequence != null &&
        motion?.landing(row.objectId) != null) {
      return MeridianEntrance(
        entranceKey: ('head-chip', row.objectId, flashSequence),
        child: chip,
      );
    }
    return chip;
  }

  // A branch's pull request follows its chip. Without one, CI is inside the
  // reference chip; paired references use the upstream's provider data.
  Widget _withPullRequest(
    BuildContext context,
    _DisplayReference reference,
    bool onAccent,
    Widget chip,
  ) {
    final pull = _referenceValue(reference, row.pullRequests);
    if (pull == null) return chip;
    final open = onOpenPullRequest;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        const SizedBox(width: MeridianSpace.space1),
        Tooltip(
          message: [
            '#${pull.number} ${pull.title}',
            if (pull.merged) context.l10n.hostingPullRequestMerged,
            if (pull.checks != HostingCheckState.unknown)
              hostingCheckLabel(context, pull.checks),
            ?hostingMergeabilityLabel(context, pull.mergeability),
            if (pull.outdated) context.l10n.hostingPullRequestOutdated,
          ].join('\n'),
          child: MeridianInteraction(
            key: ValueKey('history-pull-request-${pull.number}'),
            onTap: open == null ? null : () => open(pull),
            borderRadius: BorderRadius.circular(MeridianRadiusScale.pill),
            child: GitLamaPullRequestChip(
              number: pull.number,
              draft: pull.draft,
              merged: pull.merged,
              outdated: pull.outdated,
              checks: pull.checks,
              mergeability: pull.mergeability,
              onAccent: onAccent,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortHash = row.objectId.substring(
      0,
      math.min(10, row.objectId.length),
    );
    final subject = utf8.decode(row.subject, allowMalformed: true);
    final author = utf8.decode(row.author, allowMalformed: true);
    final refs = [
      for (final reference in row.refs)
        utf8.decode(reference, allowMalformed: true),
    ];
    final displayRefs = _displayReferences(refs, alignedUpstreams);
    if (row.current && checkedOutRef != null && !refs.contains(checkedOutRef)) {
      displayRefs.add(_displayReference(checkedOutRef!));
    }
    displayRefs.sort(
      (a, b) => _referenceRank(
        a,
        row.current ? checkedOutRef : null,
      ).compareTo(_referenceRank(b, row.current ? checkedOutRef : null)),
    );
    final authored = row.authorTime == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.authorTime * 1000).toLocal();
    final date = authored == null
        ? ''
        : _formatHistoryDate(context, authored, dateFormat);
    final tokens = context.meridian;
    final wip =
        row.shape == HistoryNodeShape.wip ||
        row.shape == HistoryNodeShape.wipConflict;
    return Semantics(
      selected: selected,
      button: selectable,
      label: [
        semanticLabel ??
            [subject, author, row.objectId, date, ...refs].join(', '),
        if (row.current && headLabel != null) headLabel!,
      ].join(', '),
      child: MeridianInteraction(
        onDoubleTap: selectable && !wip && onDoubleClick != null
            ? () => onDoubleClick!(row.objectId)
            : null,
        onTap: selectable
            ? () {
                final keyboard = HardwareKeyboard.instance;
                final toggle =
                    keyboard.isControlPressed || keyboard.isMetaPressed;
                if (toggle && onToggleSelected != null) {
                  onToggleSelected!(row.objectId);
                } else {
                  onSelected(row.objectId);
                }
              }
            : null,
        builder: (context, interaction) {
          final rowColors = MeridianRowColors.resolve(
            context,
            selected: selected,
            hovered: interaction.hovered,
          );
          final onAccent = rowColors.strong;
          // Under the selection glide the bar is painted for the row.
          final baseFill = comparisonHighlighted && !selected
              ? tokens.colors.accentSoft
              : selected && glided
              ? meridianClear(rowColors.fill)
              : rowColors.fill;
          final flags = HistoryLitFlags(
            lit: row.lit,
            incomingLit: incomingLit,
            segmentLit: [for (final segment in row.segments) segment.lit],
            lightingActive: lightingActive,
          );
          motion?.observeLighting(row.objectId, index, flags);
          final subjectStyle = context.text.body.copyWith(
            color: wip ? rowColors.secondary : rowColors.primary,
            fontStyle: wip ? FontStyle.italic : FontStyle.normal,
          );
          final metadataStyle = context.text.rowMeta.copyWith(
            color: rowColors.secondary,
          );
          final hashStyle = context.text.codeSm.copyWith(
            color: rowColors.secondary,
          );
          final detached = row.current && checkedOutRef == null;
          final visibleLimit =
              GitLamaLayout.graphMaxRefChips - (detached ? 1 : 0);
          final visibleRefs = displayRefs.take(visibleLimit).toList();
          final searchDim = queryActive && !row.searchMatch;
          // Rows outside a search fade over `laneDim`; clearing it returns
          // over `motion-hover-out` (NM-32).
          return MeridianAnimatedValue(
            value: searchDim ? GitLamaOpacity.unlit : 1,
            duration: searchDim
                ? GitLamaMotion.laneDim
                : MeridianDurations.hoverOut,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: DecoratedBox(
              key: ValueKey('history-flash-${row.objectId}-$flashSequence'),
              decoration: BoxDecoration(
                color: baseFill,
                borderRadius: BorderRadius.circular(context.meridian.radius.sm),
              ),
              child: MeridianAttention(
                trigger: flashSequence ?? 0,
                memoryKey: ('history-commit', row.objectId),
                delay: GitLamaMotion.commitTintDelay,
                child: MeridianAttention(
                  // A search match reached with next or previous tints once
                  // (NM-33).
                  key: ValueKey('history-search-attention-${row.objectId}'),
                  trigger: attentionTrigger,
                  memoryKey: ('history-search', row.objectId),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        key: const ValueKey('history-graph-paint'),
                        painter: _HistoryGraphPainter(
                          row: row,
                          rowIndex: index,
                          motion: motion,
                          laneColors: tokens.colors.series,
                          wipColor: tokens.colors.inkMuted,
                          conflictColor: tokens.colors.attention,
                          nodeBackgroundColor: selected
                              ? rowColors.fill
                              : baseFill.a == 0
                              ? tokens.colors.pane
                              : baseFill,
                          selectedOnAccent: onAccent,
                          onAccentColor: tokens.colors.onAccent,
                          faintColor: tokens.colors.inkFaint,
                          addedBackgroundColor: tokens.colors.successBg,
                          flags: flags,
                          comparisonHighlighted: comparisonHighlighted,
                          comparisonColor: tokens.colors.accent,
                        ),
                      ),
                      PositionedDirectional(
                        start: row.geometry.contentStart,
                        width: math.max(0, row.geometry.contentAvailable),
                        top: 0,
                        bottom: 0,
                        // Text dims with the row's lanes (NH-3).
                        child: _LitText(
                          motion: motion,
                          objectId: row.objectId,
                          flags: flags,
                          child: Row(
                            children: [
                              if (detached) ...[
                                if (flashSequence != null &&
                                    motion?.landing(row.objectId) != null)
                                  MeridianEntrance(
                                    entranceKey: (
                                      'detached-head-chip',
                                      row.objectId,
                                      flashSequence,
                                    ),
                                    child: GitLamaRefChip(
                                      name: shortHash,
                                      kind: GitLamaRefKind.head,
                                      detached: true,
                                      onAccent: onAccent,
                                    ),
                                  )
                                else
                                  GitLamaRefChip(
                                    name: shortHash,
                                    kind: GitLamaRefKind.head,
                                    detached: true,
                                    onAccent: onAccent,
                                  ),
                                const SizedBox(width: MeridianSpace.space2),
                              ],
                              // Chips added while the row is on screen pop in;
                              // removed ones fade and shrink away (NM-35).
                              _RefChips(
                                chips: [
                                  for (final reference in visibleRefs)
                                    (
                                      reference.raw,
                                      _withPullRequest(
                                        context,
                                        reference,
                                        onAccent,
                                        Tooltip(
                                          message: reference.tracking == null
                                              ? reference.raw
                                              : '${reference.raw}\n${reference.tracking}',
                                          child: _referenceBadge(
                                            context,
                                            reference,
                                            onAccent,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (displayRefs.length > visibleLimit) ...[
                                Tooltip(
                                  message: displayRefs
                                      .skip(visibleLimit)
                                      .map((reference) => reference.raw)
                                      .join('\n'),
                                  child: MeridianCount(
                                    label:
                                        '+${displayRefs.length - visibleLimit}',
                                  ),
                                ),
                                const SizedBox(width: MeridianSpace.space2),
                              ],
                              Expanded(
                                child: Text(
                                  subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: subjectStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: row.geometry.metadataLeft,
                        end: MeridianSpace.space5,
                        top: 0,
                        bottom: 0,
                        child: _LitText(
                          motion: motion,
                          objectId: row.objectId,
                          flags: flags,
                          child: Row(
                            textDirection: Directionality.of(context),
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                flex: 14,
                                child: SizedBox(
                                  width: metadataAuthorWidth,
                                  child: Tooltip(
                                    message: author,
                                    child: Row(
                                      children: [
                                        if (author.isNotEmpty) ...[
                                          DecoratedBox(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: onAccent
                                                  ? Border.all(
                                                      color: tokens
                                                          .colors
                                                          .onAccent,
                                                    )
                                                  : null,
                                            ),
                                            child: AuthorAvatar(
                                              author: author,
                                              avatarHash: row.avatarHash,
                                              size: MeridianLayout.avatarSmall,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: MeridianSpace.space3,
                                          ),
                                        ],
                                        Expanded(
                                          child: MeridianInteraction(
                                            onTap:
                                                onCopyValue == null ||
                                                    author.isEmpty
                                                ? null
                                                : () => onCopyValue!(author),
                                            child: Text(
                                              author,
                                              maxLines: 1,
                                              textAlign: TextAlign.start,
                                              overflow: TextOverflow.ellipsis,
                                              style: metadataStyle,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: MeridianSpace.space5),
                              Flexible(
                                flex: 10,
                                child: SizedBox(
                                  width: metadataHashWidth,
                                  child: Tooltip(
                                    message: row.objectId,
                                    child: _HashCell(
                                      hash: shortHash,
                                      copiedLabel: copiedLabel,
                                      style: hashStyle,
                                      onCopy: onCopyValue == null
                                          ? null
                                          : () => onCopyValue!(row.objectId),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: MeridianSpace.space5),
                              Flexible(
                                flex: 11,
                                child: SizedBox(
                                  width: metadataDateWidth,
                                  child: Tooltip(
                                    message: authored?.toIso8601String() ?? '',
                                    child: MeridianInteraction(
                                      onTap:
                                          onCopyValue == null ||
                                              authored == null
                                          ? null
                                          : () => onCopyValue!(
                                              authored.toIso8601String(),
                                            ),
                                      child: Text(
                                        date,
                                        maxLines: 1,
                                        textAlign: TextAlign.end,
                                        style: metadataStyle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Row text at the opacity of the row's lighting: full when lit or when
/// nothing is lit, `unlitText` otherwise, following the lanes' transition
/// (NH-3). Rebuilds only its opacity while a transition runs.
class _LitText extends StatefulWidget {
  const _LitText({
    required this.motion,
    required this.objectId,
    required this.flags,
    required this.child,
  });

  final HistoryMotion? motion;
  final String objectId;
  final HistoryLitFlags flags;
  final Widget child;

  @override
  State<_LitText> createState() => _LitTextState();
}

class _LitTextState extends State<_LitText> {
  static double _opacity(HistoryLitFlags flags) =>
      !flags.lightingActive || flags.lit ? 1 : GitLamaOpacity.unlitText;

  double get _current {
    final transition = widget.motion?.litTransition(widget.objectId);
    if (transition == null) return _opacity(widget.flags);
    return lerpDouble(
      _opacity(transition.from),
      _opacity(transition.to),
      transition.t,
    )!;
  }

  late double _shown = _current;

  @override
  void initState() {
    super.initState();
    widget.motion?.addListener(_tick);
  }

  @override
  void didUpdateWidget(_LitText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      oldWidget.motion?.removeListener(_tick);
      widget.motion?.addListener(_tick);
    }
    _shown = _current;
  }

  void _tick() {
    final next = _current;
    if (next != _shown) setState(() => _shown = next);
  }

  @override
  void dispose() {
    widget.motion?.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: _shown, child: widget.child);
}

enum _ReferenceKind { local, remote, tag, stash, other }

typedef _DisplayReference = ({
  String raw,
  String label,
  _ReferenceKind kind,
  String? tracking,
});

List<_DisplayReference> _displayReferences(
  List<String> refs,
  Map<String, String> alignedUpstreams,
) {
  final present = refs.toSet();
  final mergedRemotes = <String>{};
  for (final ref in refs) {
    final upstream = alignedUpstreams[ref];
    if (upstream != null && present.contains(upstream)) {
      mergedRemotes.add(upstream);
    }
  }
  return [
    for (final ref in refs)
      if (!mergedRemotes.contains(ref))
        _displayReference(
          ref,
          tracking: present.contains(alignedUpstreams[ref])
              ? alignedUpstreams[ref]
              : null,
        ),
  ];
}

int _referenceRank(_DisplayReference reference, String? checkedOutRef) =>
    reference.raw == checkedOutRef
    ? 0
    : switch (reference.kind) {
        _ReferenceKind.local => 1,
        _ReferenceKind.remote => 2,
        _ReferenceKind.tag => 3,
        _ReferenceKind.stash => 4,
        _ReferenceKind.other => 5,
      };

_DisplayReference _displayReference(String raw, {String? tracking}) {
  final name = ReferenceName.parse(raw);
  return (
    raw: raw,
    label: name.display,
    kind: switch (name.kind) {
      ReferenceKind.localBranch => _ReferenceKind.local,
      ReferenceKind.remoteBranch => _ReferenceKind.remote,
      ReferenceKind.tag => _ReferenceKind.tag,
      ReferenceKind.stash => _ReferenceKind.stash,
      ReferenceKind.other => _ReferenceKind.other,
    },
    tracking: switch (name.kind) {
      ReferenceKind.localBranch ||
      ReferenceKind.remoteBranch ||
      ReferenceKind.tag => tracking,
      _ => null,
    },
  );
}

/// The width of the history's date column for [format] in [style]: the
/// widest shape its dates can take, every digit the widest digit, so no
/// date in it is cut off.
double historyDateColumnWidth(
  BuildContext context,
  String format,
  TextStyle style,
) {
  final direction = Directionality.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  double measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  var widestDigit = '0';
  var widestDigitWidth = 0.0;
  for (var digit = 0; digit <= 9; digit++) {
    final width = measure('$digit');
    if (width > widestDigitWidth) {
      widestDigit = '$digit';
      widestDigitWidth = width;
    }
  }
  final samples = historyDateColumnSamples(context, format);
  final digits = RegExp('[0-9]');
  return samples
      .map((sample) => measure(sample.replaceAll(digits, widestDigit)))
      .fold(0.0, math.max)
      .ceilToDouble();
}

/// Every text shape a date in [format] can take: each month with each
/// weekday for local dates, plus the relative labels.
@visibleForTesting
List<String> historyDateColumnSamples(BuildContext context, String format) {
  return [
    if (format == 'iso')
      '2000-01-01'
    else ...[
      // Relative dates older than a month show as local dates too. Days
      // 22 to 28 pair every month with every weekday.
      for (var month = 1; month <= 12; month++)
        for (var day = 22; day <= 28; day++)
          MaterialLocalizations.of(
            context,
          ).formatMediumDate(DateTime(2000, month, day)),
      if (format != 'local') ...[
        context.l10n.historyDateNow,
        context.l10n.historyDateMinutes(59),
        context.l10n.historyDateHours(23),
        context.l10n.historyDateDays(29),
      ],
    ],
  ];
}

String _formatHistoryDate(BuildContext context, DateTime value, String format) {
  if (format == 'iso') return value.toIso8601String().substring(0, 10);
  if (format == 'local') {
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }
  final difference = DateTime.now().difference(value);
  if (difference.isNegative || difference.inMinutes < 1) {
    return context.l10n.historyDateNow;
  }
  if (difference.inHours < 1) {
    return context.l10n.historyDateMinutes(difference.inMinutes);
  }
  if (difference.inDays < 1) {
    return context.l10n.historyDateHours(difference.inHours);
  }
  if (difference.inDays < 30) {
    return context.l10n.historyDateDays(difference.inDays);
  }
  return MaterialLocalizations.of(context).formatMediumDate(value);
}

class _HistoryGraphPainter extends CustomPainter {
  _HistoryGraphPainter({
    required this.row,
    required this.rowIndex,
    required this.laneColors,
    required this.wipColor,
    required this.conflictColor,
    required this.nodeBackgroundColor,
    required this.selectedOnAccent,
    required this.onAccentColor,
    required this.faintColor,
    required this.addedBackgroundColor,
    required this.flags,
    required this.comparisonHighlighted,
    required this.comparisonColor,
    this.motion,
  }) : super(repaint: motion);

  final HistoryGraphRow row;
  final int rowIndex;
  final List<Color> laneColors;
  final Color wipColor;
  final Color conflictColor;
  final Color nodeBackgroundColor;
  final bool selectedOnAccent;
  final Color onAccentColor;
  final Color faintColor;
  final Color addedBackgroundColor;

  /// The row's lighting now; a [HistoryMotion] transition crossfades to it.
  final HistoryLitFlags flags;
  final bool comparisonHighlighted;
  final Color comparisonColor;

  /// Lighting, lane drawing and the commit landing (read while painting).
  final HistoryMotion? motion;

  bool get lightingActive => flags.lightingActive;

  @override
  void paint(Canvas canvas, Size size) {
    final draw = motion?.drawProgress(rowIndex) ?? 1;
    if (draw <= 0) return;
    canvas.save();
    // Lanes draw in from the top (NH-2, NH-7): nodes included.
    canvas.clipRect(
      Rect.fromLTWH(0, 0, row.geometry.graphClipRight, size.height * draw),
    );
    final transition = motion?.litTransition(row.objectId);
    // A lighting change crossfades the old lighting into the new one: all
    // edges first, then the node backgrounds, then the nodes (NH-3).
    final passes = transition == null
        ? [(flags, 1.0)]
        : [(transition.from, 1 - transition.t), (transition.to, transition.t)];
    for (final (passFlags, alpha) in passes) {
      _paintSegments(canvas, size, passFlags, alpha);
    }
    _paintNodeBackground(canvas, size);
    for (final (passFlags, alpha) in passes) {
      _paintNode(canvas, size, passFlags, alpha);
    }
    canvas.restore();
  }

  void _paintSegments(
    Canvas canvas,
    Size size,
    HistoryLitFlags flags,
    double alpha,
  ) {
    final lightingActive = flags.lightingActive;
    final lit = !lightingActive || flags.lit;
    final incomingLit = !lightingActive || flags.incomingLit;
    final centerY = size.height / 2;
    final segments = row.segments;
    // The graph is clipped at the metadata columns. A wide history carries
    // hundreds of lanes beyond that edge through every row; skip them.
    final visibleRight = row.geometry.graphClipRight + GitLamaLayout.laneWidth;
    final paints = List<Paint?>.filled(laneColors.length * 2, null);
    Paint edgePaint(int lane, bool isLit) =>
        paints[_laneColorIndex(lane) * 2 + (isLit ? 1 : 0)] ??= _edgePaint(
          lane,
          isLit,
          alpha,
        );
    final path = Path();
    // Straight lanes first, then the edges that cross them.
    for (var pass = 0; pass < 2; pass += 1) {
      for (var i = 0; i < segments.length; i += 1) {
        final segment = segments[i];
        if ((segment.fromLane == segment.toLane) != (pass == 0)) continue;
        final fromX = historyLaneX(segment.fromLane);
        final toX = historyLaneX(segment.toLane);
        if (math.min(fromX, toX) > visibleRight) continue;
        final segmentLit = i < flags.segmentLit.length
            ? flags.segmentLit[i]
            : segment.lit;
        final startY = segment.startsAtTop ? 0.0 : centerY;
        final endY = segment.endsAtCenter ? centerY : size.height;
        path
          ..reset()
          ..moveTo(fromX, startY);
        if (fromX == toX) {
          path.lineTo(toX, endY);
        } else {
          final midpoint = (startY + endY) / 2;
          path.cubicTo(fromX, midpoint, toX, midpoint, toX, endY);
        }
        if (segmentLit != null) {
          canvas.drawPath(
            path,
            edgePaint(segment.fromLane, !lightingActive || segmentLit),
          );
        } else if (segment.startsAtTop &&
            !segment.endsAtCenter &&
            incomingLit != lit) {
          canvas.save();
          canvas.clipRect(Rect.fromLTRB(0, 0, size.width, centerY));
          canvas.drawPath(path, edgePaint(segment.fromLane, incomingLit));
          canvas.restore();
          canvas.save();
          canvas.clipRect(Rect.fromLTRB(0, centerY, size.width, size.height));
          canvas.drawPath(path, edgePaint(segment.fromLane, lit));
          canvas.restore();
        } else {
          canvas.drawPath(
            path,
            edgePaint(
              segment.fromLane,
              segment.startsAtTop ? incomingLit : lit,
            ),
          );
        }
        if (segment.kind == HistorySegmentKind.missing) {
          final terminal = Offset(
            toX,
            endY == size.height ? size.height - 2 : endY,
          );
          canvas.drawCircle(terminal, 2, Paint()..color = nodeBackgroundColor);
          canvas.drawCircle(
            terminal,
            2,
            Paint()
              ..color = _fade(
                selectedOnAccent ? onAccentColor : faintColor,
                alpha,
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
    }
  }

  void _paintNodeBackground(Canvas canvas, Size size) {
    final center = Offset(historyLaneX(row.lane), size.height / 2);
    final background = Paint()..color = nodeBackgroundColor;
    switch (row.shape) {
      case HistoryNodeShape.commit when row.current:
        canvas.drawCircle(
          center,
          GitLamaLayout.graphHeadOuterRadius,
          background,
        );
      case HistoryNodeShape.boundary:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: GitLamaLayout.graphBoundarySquare,
            height: GitLamaLayout.graphBoundarySquare,
          ),
          background,
        );
      case HistoryNodeShape.graft || HistoryNodeShape.replace:
        canvas.drawCircle(
          center,
          GitLamaLayout.graphHeadOuterRadius,
          background,
        );
      default:
        canvas.drawCircle(center, GitLamaLayout.graphCommitRadius, background);
    }
  }

  void _paintNode(
    Canvas canvas,
    Size size,
    HistoryLitFlags flags,
    double alpha,
  ) {
    if (alpha <= 0) return;
    final lit = !flags.lightingActive || flags.lit;
    final centerY = size.height / 2;
    final nodeX = historyLaneX(row.lane);
    final center = Offset(nodeX, centerY);
    final nodeColor = selectedOnAccent
        ? onAccentColor
        : _laneColor(
            row.lane,
          ).withValues(alpha: lit ? 1 : GitLamaOpacity.unlit);
    final nodePaint = Paint()..color = _fade(nodeColor, alpha);
    switch (row.shape) {
      case HistoryNodeShape.wip || HistoryNodeShape.wipConflict:
        if (row.shape == HistoryNodeShape.wip &&
            row.wipStagedFiles > 0 &&
            row.wipStagedFiles < row.wipChangedFiles) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(
              nodeX - GitLamaLayout.graphCommitRadius,
              centerY,
              GitLamaLayout.graphCommitRadius * 2,
              GitLamaLayout.graphCommitRadius,
            ),
          );
          canvas.drawCircle(
            center,
            GitLamaLayout.graphCommitRadius,
            Paint()
              ..color = _fade(
                selectedOnAccent ? onAccentColor : addedBackgroundColor,
                alpha,
              ),
          );
          canvas.restore();
        }
        final color = selectedOnAccent
            ? onAccentColor
            : row.shape == HistoryNodeShape.wipConflict
            ? conflictColor
            : wipColor;
        _drawDashedCircle(
          canvas,
          center,
          GitLamaLayout.graphCommitRadius,
          _fade(color.withValues(alpha: lit ? 1 : GitLamaOpacity.unlit), alpha),
        );
      case HistoryNodeShape.commit:
        if (row.current) {
          final landing = motion?.landing(row.objectId);
          if (landing != null) {
            _paintLanding(canvas, center, nodePaint.color, landing);
          } else {
            canvas.drawCircle(
              center,
              GitLamaLayout.graphHeadOuterRadius,
              Paint()
                ..color = nodePaint.color
                ..style = PaintingStyle.stroke
                ..strokeWidth = GitLamaLayout.graphHeadOuterStroke,
            );
            canvas.drawCircle(
              center,
              GitLamaLayout.graphHeadInnerRadius,
              nodePaint,
            );
          }
        } else {
          canvas.drawCircle(
            center,
            GitLamaLayout.graphCommitRadius,
            Paint()
              ..color = nodePaint.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = GitLamaLayout.graphRingStroke,
          );
        }
      case HistoryNodeShape.stash:
        _drawDashedCircle(
          canvas,
          center,
          GitLamaLayout.graphCommitRadius,
          nodePaint.color,
        );
      case HistoryNodeShape.merge:
        nodePaint.style = PaintingStyle.stroke;
        nodePaint.strokeWidth = GitLamaLayout.graphRingStroke;
        canvas.drawCircle(center, GitLamaLayout.graphCommitRadius, nodePaint);
        nodePaint.style = PaintingStyle.fill;
        canvas.drawCircle(center, GitLamaLayout.graphMergeDotRadius, nodePaint);
      case HistoryNodeShape.boundary:
        nodePaint
          ..style = PaintingStyle.stroke
          ..color = _fade(selectedOnAccent ? onAccentColor : wipColor, alpha)
          ..strokeWidth = GitLamaLayout.graphBoundaryStroke;
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: GitLamaLayout.graphBoundarySquare,
            height: GitLamaLayout.graphBoundarySquare,
          ),
          nodePaint,
        );
      case HistoryNodeShape.graft || HistoryNodeShape.replace:
        nodePaint.style = PaintingStyle.stroke;
        nodePaint.strokeWidth = GitLamaLayout.graphBoundaryStroke;
        canvas.drawCircle(center, GitLamaLayout.graphCommitRadius, nodePaint);
        if (row.shape == HistoryNodeShape.graft) {
          canvas.drawCircle(
            center,
            GitLamaLayout.graphHeadOuterRadius,
            nodePaint,
          );
        } else {
          canvas.drawArc(
            Rect.fromCircle(
              center: center,
              radius: GitLamaLayout.graphHeadOuterRadius,
            ),
            -math.pi / 4,
            math.pi / 2,
            false,
            nodePaint,
          );
        }
    }
  }

  /// NH-1: the WIP ring closing into the new HEAD node.
  void _paintLanding(
    Canvas canvas,
    Offset center,
    Color color,
    HistoryLanding landing,
  ) {
    if (landing.ringOpacity > 0) {
      _drawDashedCircle(
        canvas,
        center,
        GitLamaLayout.graphCommitRadius,
        _fade(color, landing.ringOpacity),
        gapFactor: 1 - landing.ringClose,
        strokeWidth: GitLamaLayout.graphHeadOuterStroke,
      );
    }
    if (landing.halo > 0) {
      final radius =
          GitLamaLayout.graphHeadInnerRadius +
          (GitLamaLayout.graphHeadOuterRadius -
                  GitLamaLayout.graphHeadInnerRadius) *
              landing.halo;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = GitLamaLayout.graphHeadOuterStroke,
      );
    }
    if (landing.core > 0) {
      canvas.drawCircle(
        center,
        GitLamaLayout.graphHeadInnerRadius * landing.core,
        Paint()..color = color,
      );
    }
  }

  int _laneColorIndex(int lane) =>
      ((lane % laneColors.length) + laneColors.length) % laneColors.length;

  Color _laneColor(int lane) => laneColors[_laneColorIndex(lane)];

  static Color _fade(Color color, double alpha) =>
      alpha >= 1 ? color : color.withValues(alpha: color.a * alpha);

  Paint _edgePaint(int lane, bool isLit, double alpha) => Paint()
    ..color = _fade(
      selectedOnAccent
          ? onAccentColor
          : _laneColor(
              lane,
            ).withValues(alpha: isLit ? 1 : GitLamaOpacity.unlit),
      alpha,
    )
    ..strokeWidth = isLit
        ? GitLamaLayout.graphStrokeLit
        : GitLamaLayout.graphRingStroke
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  @override
  bool shouldRepaint(covariant _HistoryGraphPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.rowIndex != rowIndex ||
      oldDelegate.motion != motion ||
      oldDelegate.laneColors != laneColors ||
      oldDelegate.wipColor != wipColor ||
      oldDelegate.conflictColor != conflictColor ||
      oldDelegate.nodeBackgroundColor != nodeBackgroundColor ||
      oldDelegate.selectedOnAccent != selectedOnAccent ||
      oldDelegate.onAccentColor != onAccentColor ||
      oldDelegate.faintColor != faintColor ||
      oldDelegate.addedBackgroundColor != addedBackgroundColor ||
      oldDelegate.flags != flags ||
      oldDelegate.comparisonHighlighted != comparisonHighlighted ||
      oldDelegate.comparisonColor != comparisonColor;
}

void _drawDashedCircle(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  double gapFactor = 1,
  double strokeWidth = GitLamaLayout.graphRingStroke,
}) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (gapFactor <= 0) {
    canvas.drawCircle(center, radius, paint);
    return;
  }
  final circumference = 2 * math.pi * radius;
  // A shrinking gap closes the dashes into a ring (NH-1).
  final dash =
      GitLamaLayout.graphDash + GitLamaLayout.graphDash * (1 - gapFactor);
  for (
    var position = 0.0;
    position < circumference;
    position += GitLamaLayout.graphDash * 2
  ) {
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      position / radius,
      dash / radius,
      false,
      paint,
    );
  }
}

/// A row's short hash. Copying it swaps the text for a check and "Copied"
/// for `copiedHold`, then back (NM-34).
class _HashCell extends StatefulWidget {
  const _HashCell({
    required this.hash,
    required this.style,
    this.copiedLabel,
    this.onCopy,
  });

  final String hash;
  final String? copiedLabel;
  final TextStyle style;
  final VoidCallback? onCopy;

  @override
  State<_HashCell> createState() => _HashCellState();
}

class _HashCellState extends State<_HashCell> {
  var _copied = false;
  Timer? _hold;

  void _copy() {
    widget.onCopy?.call();
    _hold?.cancel();
    setState(() => _copied = true);
    _hold = Timer(GitLamaMotion.copiedHold * timeDilation, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MeridianInteraction(
    onTap: widget.onCopy == null ? null : _copy,
    child: MeridianSwap(
      swapKey: _copied,
      style: MeridianSwapStyle.rise,
      rise: MeridianMotionScales.riseOverlay,
      child: _copied
          ? Row(
              key: const ValueKey('history-hash-copied'),
              mainAxisSize: MainAxisSize.min,
              children: [
                MeridianStrokeIcon(
                  MeridianIcons.check,
                  appear: true,
                  duration: MeridianLayout.successCheckDraw,
                  size: context.meridian.density.iconSmallSize,
                  color: widget.style.color,
                ),
                if (widget.copiedLabel case final label?) ...[
                  const SizedBox(width: MeridianSpace.space1),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: widget.style,
                    ),
                  ),
                ],
              ],
            )
          : Text(
              widget.hash,
              maxLines: 1,
              textAlign: TextAlign.start,
              style: widget.style,
            ),
    ),
  );
}

/// A row's ref chips. A chip that appears while the row is on screen pops
/// in from 0.6 on `spring-pop`; one that goes fades and shrinks over
/// `motion-exit` (NM-35). A row built fresh (scrolled into view) shows its
/// chips at rest.
class _RefChips extends StatefulWidget {
  const _RefChips({required this.chips});

  final List<(String, Widget)> chips;

  @override
  State<_RefChips> createState() => _RefChipsState();
}

class _RefChipsState extends State<_RefChips> {
  /// Chips that arrived after the first build.
  final Set<String> _arrived = {};

  /// Chips on their way out, with the widget they last showed.
  final Map<String, (int, Widget)> _leaving = {};

  @override
  void didUpdateWidget(_RefChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MeridianMotion.reduced(context)) return;
    final before = {for (final (key, _) in oldWidget.chips) key};
    final after = {for (final (key, _) in widget.chips) key};
    _arrived.addAll(after.difference(before));
    for (final (i, (key, chip)) in oldWidget.chips.indexed) {
      if (!after.contains(key)) _leaving[key] = (i, chip);
    }
    for (final key in after) {
      _leaving.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final (key, chip) in widget.chips)
        KeyedSubtree(
          key: ValueKey(('chip', key)),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              end: MeridianSpace.space2,
            ),
            child: _arrived.contains(key) ? _ChipPop(child: chip) : chip,
          ),
        ),
    ];
    for (final MapEntry(key: key, value: (index, chip)) in _leaving.entries) {
      children.insert(
        index.clamp(0, children.length),
        KeyedSubtree(
          key: ValueKey(('leaving', key)),
          child: MeridianRemovingRow(
            axis: Axis.horizontal,
            onRemoved: () {
              if (mounted) setState(() => _leaving.remove(key));
            },
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: MeridianSpace.space2,
                  ),
                  child: chip,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Pops [child] in from `badgeLeaveScale` (0.6) on `spring-pop`.
class _ChipPop extends StatefulWidget {
  const _ChipPop({required this.child});

  final Widget child;

  @override
  State<_ChipPop> createState() => _ChipPopState();
}

class _ChipPopState extends State<_ChipPop>
    with SingleTickerProviderStateMixin {
  late final MeridianSpringController _scale = MeridianSpringController(
    vsync: this,
    value: MeridianOpacity.badgeLeaveScale,
  )..animateTo(1, spring: MeridianSprings.pop);

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _scale.animation,
    child: widget.child,
    builder: (context, child) =>
        Transform.scale(scale: _scale.value, child: child),
  );
}

/// A history row that has not loaded yet: breathing skeleton bars where
/// the subject and the metadata will be (NM-38).
class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.geometry});

  final HistoryRowGeometry geometry;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Stack(
      fit: StackFit.expand,
      children: [
        PositionedDirectional(
          start: geometry.contentStart,
          width: math.max(0, geometry.contentAvailable),
          top: 0,
          bottom: 0,
          child: const Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: MeridianSkeleton(),
            ),
          ),
        ),
        PositionedDirectional(
          start: geometry.metadataLeft,
          end: MeridianSpace.space5,
          top: 0,
          bottom: 0,
          child: const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MeridianSkeleton(
              width: GitLamaLayout.historyMetaSkeletonWidth,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Fades a loaded row in over `motion-quick` when it replaces a loading
/// placeholder; every other row shows at rest (NM-38).
class _LoadedFade extends StatefulWidget {
  const _LoadedFade({
    required this.motion,
    required this.index,
    required this.child,
  });

  final HistoryMotion motion;
  final int index;
  final Widget child;

  @override
  State<_LoadedFade> createState() => _LoadedFadeState();
}

class _LoadedFadeState extends State<_LoadedFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    value: 1,
    duration: MeridianDurations.quick,
  );

  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.motion.consumePlaceholder(widget.index) &&
        !MeridianMotion.reduced(context)) {
      _opacity.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
