import '../../widgets/status_notification.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/activity.dart';
import '../../models/app_command.dart';
import 'command_availability.dart';
import '../../models/repository_state.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/gitlama_timeline_row.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

class ActivitySlot extends StatefulWidget {
  const ActivitySlot({
    required this.repositories,
    required this.session,
    required this.selectedActivityId,
    super.key,
  });

  final RepositorySessionService repositories;
  final RepositorySessionIdentity? session;
  final BigInt? selectedActivityId;

  @override
  State<ActivitySlot> createState() => ActivitySlotState();
}

class ActivitySlotState extends State<ActivitySlot> {
  bool _hasRecords = false;
  bool get hasSelection => _selected != null || _hasRecords;
  late Future<ActivityPage> _page;
  BigInt? _selected;
  bool _refreshing = false;
  int _revision = 0;

  Future<void> refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final page = await _load();
      if (mounted && revision == _revision) {
        setState(() {
          _page = Future.value(page);
        });
      }
    } on RepositorySessionException {
      // Keep the last page until the next operation poll succeeds.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedActivityId;
    _page = _load();
  }

  PaneCommandContext? _paneCommands;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paneCommands = PaneCommandContextScope.maybeOf(context);
    if (!identical(paneCommands, _paneCommands)) {
      _paneCommands
        ?..withdrawActivity(_hasSelectionAnswer)
        ..withdrawHandler(PaneRole.activity, _handler);
      _paneCommands = paneCommands
        ?..registerActivity(_hasSelectionAnswer)
        ..registerHandler(PaneRole.activity, _handler);
    }
  }

  late final PaneCommandHandler _handler = PaneCommandHandler(
    run: (command) {
      if (command == AppCommandId.activityCopy) unawaited(copySelected());
    },
    refresh: () => unawaited(refresh()),
  );

  bool _hasSelectionAnswer() => hasSelection;

  @override
  void dispose() {
    _paneCommands
      ?..withdrawActivity(_hasSelectionAnswer)
      ..withdrawHandler(PaneRole.activity, _handler);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ActivitySlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedActivityId != widget.selectedActivityId ||
        oldWidget.session != widget.session) {
      _revision += 1;
      _hasRecords = false;
      _selected = widget.selectedActivityId;
      _page = _load();
    }
  }

  Future<void> copySelected() async {
    final page = await _page;
    if (!mounted) return;
    ActivityRecord? selected;
    for (final record in page.records) {
      if (record.id == _selected) selected = record;
    }
    selected ??= page.records.lastOrNull;
    if (selected == null || activityOutput(selected).isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: activityClipboardText(selected)),
    );
    if (!mounted) return;
    StatusNotificationScope.show(context, context.l10n.activityCopied);
  }

  Future<ActivityPage> _load() {
    final session = widget.session;
    final revision = _revision;
    return session == null
        ? Future.value(const ActivityPage(records: [], evictedThroughId: null))
        : widget.repositories.activityFor(session, maximumRecords: 64).then((
            page,
          ) {
            if (mounted && revision == _revision) {
              _hasRecords = page.records.isNotEmpty;
            }
            return page;
          });
  }

  @override
  Widget build(BuildContext context) => Container(
    height: GitLamaLayout.activityHeight,
    width: double.infinity,
    margin: const EdgeInsetsDirectional.only(
      start: MeridianSpace.space3,
      end: MeridianSpace.space3,
      bottom: MeridianSpace.space3,
    ),
    child: MeridianIsland(
      title: context.l10n.workspaceActivity,
      expandChild: true,
      actions: [
        MeridianIconButton(
          label: context.l10n.activityCopy,
          icon: 'copy',
          size: MeridianControlSize.small,
          onPressed: () => unawaited(copySelected()),
        ),
      ],
      child: FutureBuilder<ActivityPage>(
        future: _page,
        builder: (context, snapshot) {
          final records = snapshot.data?.records ?? const <ActivityRecord>[];
          ActivityRecord? selected;
          for (final record in records) {
            if (record.id == _selected) selected = record;
          }
          selected ??= records.lastOrNull;
          if (records.isEmpty) {
            return MeridianEmptyState(
              compact: true,
              title: context.l10n.operationsEmpty,
            );
          }
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final isSelected = selected?.id == record.id;
              return GitLamaTimelineRow(
                key: ValueKey('activity-${record.id}'),
                state: switch (record.status) {
                  ActivityStatus.running => GitLamaTimelineState.running,
                  ActivityStatus.succeeded => GitLamaTimelineState.succeeded,
                  ActivityStatus.canceled => GitLamaTimelineState.cancelled,
                  ActivityStatus.failed ||
                  ActivityStatus.timedOut ||
                  ActivityStatus.launchError => GitLamaTimelineState.failed,
                },
                verb: record.executable,
                target: record.arguments.join(' '),
                metadata: activityStateLabel(context, record.status),
                time: TimeOfDay.fromDateTime(
                  DateTime.fromMillisecondsSinceEpoch(
                    record.startedAtUnixMs.toInt(),
                  ),
                ).format(context),
                first: index == 0,
                last: index == records.length - 1,
                selected: isSelected,
                onActivate: () => setState(() => _selected = record.id),
                expanded: isSelected
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record.executable} ${record.arguments.join(' ')}',
                            style: context.text.codeSm.copyWith(
                              color: context.colors.inkMuted,
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: GitLamaLayout.activityOutputMaxHeight,
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                contextMenuBuilder:
                                    nativeTextContextMenuBuilder,
                                activityOutput(record),
                                style: context.text.codeSm.copyWith(
                                  color: context.colors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
    ),
  );
}
