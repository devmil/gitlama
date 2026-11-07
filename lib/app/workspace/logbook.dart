import '../../widgets/status_notification.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/activity.dart';
import '../../models/operation_center.dart';
import '../../models/workspace.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/gitlama_timeline_row.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

enum _OperationOriginFilter { all, user, background }

class OperationCenterPanel extends StatefulWidget {
  const OperationCenterPanel({
    required this.snapshot,
    required this.workspace,
    this.repositories,
    required this.onClose,
    required this.onCancel,
    this.canCancel,
    required this.onRetry,
    required this.onDismiss,
    required this.onDismissAll,
    this.visible = true,
    this.onHidden,
    this.onDetails,
    super.key,
  });

  final OperationCenterSnapshot snapshot;
  final WorkspaceState workspace;
  final RepositorySessionService? repositories;
  final VoidCallback onClose;
  final ValueChanged<OperationCenterEntry> onCancel;

  /// Whether [onCancel] can stop [entry]; defaults to the entry's own flag.
  final bool Function(OperationCenterEntry entry)? canCancel;
  final ValueChanged<OperationCenterEntry> onRetry;
  final ValueChanged<OperationCenterEntry> onDismiss;
  final VoidCallback onDismissAll;
  final bool visible;
  final VoidCallback? onHidden;
  final ValueChanged<OperationCenterEntry>? onDetails;

  @override
  State<OperationCenterPanel> createState() => _OperationsPanelState();
}

class _LogbookDisplayEntry {
  const _LogbookDisplayEntry(this.entry, this.count);
  final OperationCenterEntry entry;
  final int count;
}

class _OperationsPanelState extends State<OperationCenterPanel> {
  _OperationOriginFilter _origin = _OperationOriginFilter.all;
  BigInt? _selectedOperationKey;
  final Map<BigInt, Future<ActivityPage>> _details = {};

  /// Rows animating out: their former index, the row, and whether it was
  /// expanded, so a dismissed row leaves as it was shown.
  final Map<BigInt, (int, _LogbookDisplayEntry, bool)> _leaving = {};
  late Set<BigInt> _knownKeys;
  Set<BigInt> _newKeys = const {};

  BigInt _entryKey(OperationCenterEntry entry) =>
      entry.activityId ?? entry.startedAtUnixMs;

  List<OperationCenterEntry> _filtered(OperationCenterSnapshot snapshot) =>
      snapshot.entries
          .where(
            (entry) => switch (_origin) {
              _OperationOriginFilter.all => true,
              _OperationOriginFilter.user =>
                entry.origin == OperationCenterOrigin.user,
              _OperationOriginFilter.background =>
                entry.origin == OperationCenterOrigin.background,
            },
          )
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _knownKeys = widget.snapshot.entries.map(_entryKey).toSet();
  }

  @override
  void didUpdateWidget(covariant OperationCenterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.snapshot.entries.map(_entryKey).toSet();
    _newKeys = current.difference(_knownKeys);
    _knownKeys = current;
    final before = _present(_filtered(oldWidget.snapshot));
    final remaining = _present(_filtered(widget.snapshot));
    final after = remaining.map((item) => _entryKey(item.entry)).toSet();
    final selectedBefore = _selectedIn(before);
    for (final (index, item) in before.indexed) {
      final key = _entryKey(item.entry);
      if (after.contains(key)) continue;
      final wasSelected = identical(item, selectedBefore);
      _leaving[key] = (index, item, wasSelected);
      // The entry that moves into a dismissed selection's place takes it
      // over, instead of the selection jumping back to the top.
      if (wasSelected && remaining.isNotEmpty) {
        _selectedOperationKey = _entryKey(
          remaining[index.clamp(0, remaining.length - 1)].entry,
        );
      }
    }
    _leaving.removeWhere((key, _) => after.contains(key));
  }

  _LogbookDisplayEntry? _selectedIn(List<_LogbookDisplayEntry> entries) =>
      entries
          .where((item) => _entryKey(item.entry) == _selectedOperationKey)
          .firstOrNull ??
      entries.firstOrNull;

  List<_LogbookDisplayEntry> _present(List<OperationCenterEntry> entries) {
    final result = <_LogbookDisplayEntry>[];
    for (final entry in entries) {
      if (result.isNotEmpty &&
          entry.action == OperationCenterAction.fetch &&
          entry.origin == OperationCenterOrigin.background &&
          entry.state == OperationCenterState.succeeded &&
          result.last.entry.action == OperationCenterAction.fetch &&
          result.last.entry.origin == OperationCenterOrigin.background &&
          result.last.entry.state == OperationCenterState.succeeded) {
        final previous = result.removeLast();
        result.add(_LogbookDisplayEntry(previous.entry, previous.count + 1));
      } else {
        result.add(_LogbookDisplayEntry(entry, 1));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _present(_filtered(widget.snapshot));
    final selected = _selectedIn(entries);
    final displayRows = <(_LogbookDisplayEntry, bool, bool)>[
      for (final entry in entries) (entry, false, identical(entry, selected)),
    ];
    final leaving = _leaving.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    for (final item in leaving) {
      displayRows.insert(item.value.$1.clamp(0, displayRows.length), (
        item.value.$2,
        true,
        item.value.$3,
      ));
    }
    return MeridianPanel(
      title: context.l10n.logbookTitle,
      origin: AlignmentDirectional.topEnd,
      visible: widget.visible,
      onHidden: widget.onHidden,
      onClose: widget.onClose,
      width: math.min(
        GitLamaLayout.logbookWidth,
        MediaQuery.sizeOf(context).width - 2 * MeridianSpace.space3,
      ),
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: MeridianSpace.space6,
                end: MeridianSpace.space5,
                bottom: MeridianSpace.space4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MeridianSegmented<_OperationOriginFilter>(
                      label: context.l10n.operationsFilterAll,
                      segments: [
                        for (final value in _OperationOriginFilter.values)
                          MeridianSegment(
                            value: value,
                            label: switch (value) {
                              _OperationOriginFilter.all =>
                                context.l10n.operationsFilterAll,
                              _OperationOriginFilter.user =>
                                context.l10n.operationsFilterUser,
                              _OperationOriginFilter.background =>
                                context.l10n.operationsFilterBackground,
                            },
                          ),
                      ],
                      value: _origin,
                      size: MeridianControlSize.small,
                      onChanged: (value) => setState(() => _origin = value),
                    ),
                  ),
                  const SizedBox(width: MeridianSpace.space3),
                  MeridianIconButton(
                    label: context.l10n.operationsDismissAll,
                    icon: 'brush-cleaning',
                    size: MeridianControlSize.small,
                    onPressed:
                        widget.snapshot.failedCount == 0 &&
                            widget.snapshot.warningCount == 0
                        ? null
                        : widget.onDismissAll,
                  ),
                ],
              ),
            ),
            if (displayRows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space6),
                child: Text(
                  context.l10n.operationsEmpty,
                  style: context.text.body.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: displayRows.length,
                  itemBuilder: (context, index) {
                    final (display, exiting, isSelected) = displayRows[index];
                    final entry = display.entry;
                    final key = _entryKey(entry);
                    final started = DateTime.fromMillisecondsSinceEpoch(
                      entry.startedAtUnixMs.toInt(),
                    );
                    final elapsedMs = entry.finishedAtUnixMs == null
                        ? null
                        : entry.finishedAtUnixMs!.toInt() -
                              entry.startedAtUnixMs.toInt();
                    final progress = operationProgressLabel(
                      context,
                      entry.progress,
                    );
                    final metadata = [
                      operationRepositoryLabel(
                        context,
                        widget.workspace,
                        entry,
                      ),
                      if (elapsedMs != null)
                        context.l10n.logbookDurationSeconds(
                          (elapsedMs / 1000).toStringAsFixed(1),
                        ),
                      ?progress,
                    ].join(' · ');
                    Widget row = GitLamaTimelineRow(
                      key: ValueKey('operation-$key'),
                      state: switch (entry.state) {
                        OperationCenterState.running =>
                          GitLamaTimelineState.running,
                        OperationCenterState.succeeded =>
                          GitLamaTimelineState.succeeded,
                        OperationCenterState.warning ||
                        OperationCenterState.attention =>
                          GitLamaTimelineState.warning,
                        OperationCenterState.failed =>
                          GitLamaTimelineState.failed,
                        OperationCenterState.canceled =>
                          GitLamaTimelineState.cancelled,
                      },
                      shakeOnFailure: true,
                      verb: display.count > 1
                          ? context.l10n.logbookRepeatedFetch(display.count)
                          : entry.userFailure?.message ??
                                operationActionLabel(context, entry.action),
                      target: display.count > 1
                          ? ''
                          : operationRepositoryLabel(
                              context,
                              widget.workspace,
                              entry,
                            ),
                      metadata: metadata,
                      time: TimeOfDay.fromDateTime(started).format(context),
                      first: index == 0,
                      last: index == displayRows.length - 1,
                      selected: isSelected,
                      onActivate: () =>
                          setState(() => _selectedOperationKey = key),
                      expanded: isSelected ? _detail(context, entry) : null,
                    );
                    if (exiting) {
                      final delayIndex = displayRows
                          .skip(index + 1)
                          .where((item) => item.$2)
                          .length;
                      return MeridianRemovingRow(
                        key: ValueKey(('logbook-exit', key)),
                        delay:
                            MeridianDurations.stagger * math.min(delayIndex, 5),
                        onRemoved: () {
                          if (mounted) setState(() => _leaving.remove(key));
                        },
                        child: IgnorePointer(child: row),
                      );
                    }
                    if (_newKeys.contains(key)) {
                      row = MeridianEntrance(
                        entranceKey: ('logbook-entry', key),
                        index: index,
                        child: MeridianReveal(
                          visible: true,
                          appear: true,
                          child: row,
                        ),
                      );
                    }
                    return row;
                  },
                ),
              ),
            const SizedBox(height: MeridianSpace.space4),
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, OperationCenterEntry entry) {
    if (entry.userFailure case final failure?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(failure.message, style: context.text.body),
          const SizedBox(height: MeridianSpace.space3),
          SelectableText(
            contextMenuBuilder: nativeTextContextMenuBuilder,
            StatusNotificationScope.supportReport(context, failure.details),
            style: context.text.codeSm,
          ),
          const SizedBox(height: MeridianSpace.space3),
          Wrap(
            spacing: MeridianSpace.space3,
            children: [
              MeridianButton(
                label: context.l10n.operationCopyReport,
                variant: MeridianButtonVariant.quiet,
                size: MeridianControlSize.small,
                onPressed: () => copyWithStatusNotification(
                  context,
                  StatusNotificationScope.supportReport(
                    context,
                    failure.details,
                  ),
                  context.l10n.operationReportCopied,
                ),
              ),
              MeridianButton(
                label: context.l10n.operationsDismiss,
                variant: MeridianButtonVariant.quiet,
                size: MeridianControlSize.small,
                onPressed: () => widget.onDismiss(entry),
              ),
            ],
          ),
        ],
      );
    }
    final activityId = entry.activityId;
    final session = entry.session;
    final future =
        activityId == null ||
            session == null ||
            !entry.hasDetails ||
            widget.repositories == null
        ? null
        : _details.putIfAbsent(
            activityId,
            () => widget.repositories!.activityRecordFor(session, activityId),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (future == null)
          Text(
            context.l10n.operationsDetailsUnavailable,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          )
        else
          FutureBuilder<ActivityPage>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const MeridianSpinner();
              }
              if (snapshot.hasError) {
                return Text(context.l10n.operationsDetailsLoadFailed);
              }
              final record = snapshot.data?.records
                  .where((value) => value.id == activityId)
                  .firstOrNull;
              if (record == null) {
                return Text(
                  snapshot.data?.detailsWereEvicted(activityId!) == true
                      ? context.l10n.operationsDetailsExpired
                      : context.l10n.operationsDetailsUnavailable,
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: GitLamaLayout.logbookOutputMaxHeight,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    contextMenuBuilder: nativeTextContextMenuBuilder,
                    '\$ ${record.executable} ${record.arguments.join(' ')}\n\n${activityOutput(record)}',
                    style: context.text.codeSm.copyWith(
                      color: context.colors.inkMuted,
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: MeridianSpace.space3),
        Wrap(
          spacing: MeridianSpace.space3,
          runSpacing: MeridianSpace.space3,
          children: [
            if (entry.canRetry)
              MeridianButton(
                label: context.l10n.retry,
                variant: MeridianButtonVariant.secondary,
                size: MeridianControlSize.small,
                onPressed: () => widget.onRetry(entry),
              ),
            if (widget.canCancel?.call(entry) ?? entry.canCancel)
              MeridianButton(
                label: context.l10n.cancel,
                variant: MeridianButtonVariant.dangerQuiet,
                size: MeridianControlSize.small,
                onPressed: () => widget.onCancel(entry),
              ),
            if (entry.state == OperationCenterState.failed ||
                entry.state == OperationCenterState.warning)
              MeridianButton(
                label: context.l10n.operationsDismiss,
                variant: MeridianButtonVariant.quiet,
                size: MeridianControlSize.small,
                onPressed: () => widget.onDismiss(entry),
              ),
            if (future != null)
              MeridianButton(
                label: context.l10n.activityCopy,
                variant: MeridianButtonVariant.quiet,
                size: MeridianControlSize.small,
                onPressed: () async {
                  final page = await future;
                  final record = page.records
                      .where((value) => value.id == activityId)
                      .firstOrNull;
                  if (record == null) return;
                  await Clipboard.setData(
                    ClipboardData(text: activityClipboardText(record)),
                  );
                  if (context.mounted) {
                    StatusNotificationScope.show(
                      context,
                      context.l10n.activityCopied,
                    );
                  }
                },
              ),
            if (future != null && widget.onDetails != null)
              MeridianButton(
                label: context.l10n.operationsDetails,
                variant: MeridianButtonVariant.quiet,
                size: MeridianControlSize.small,
                onPressed: () => widget.onDetails!(entry),
              ),
          ],
        ),
      ],
    );
  }
}
