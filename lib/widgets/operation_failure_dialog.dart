import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../app/gitlama_layout.dart';
import '../app/workspace/labels.dart' show activityClipboardText;
import '../l10n/l10n.dart';
import '../models/activity.dart';
import '../models/operation_failure.dart';
import '../models/repository_state.dart';
import 'native_menu.dart';
import 'status_notification.dart';

/// A failed user action: what the window says and what a report may carry.
typedef OperationFailure = ({String message, OperationFailureDetails details});

/// Reads the record of one Git command for the failure dialog.
typedef ActivityRecordLoader =
    Future<ActivityPage> Function(
      RepositorySessionIdentity session,
      BigInt activityId,
    );

/// Tells the user that an action they started failed. It shows the latest of
/// [failure] while open, the output of the Git command behind it when there
/// is one, and copies a support report. [actions] come before Close.
class OperationFailureDialog extends StatefulWidget {
  const OperationFailureDialog({
    required this.failure,
    this.loadActivity,
    this.title,
    this.content,
    this.actions = const [],
    this.closeLabel,
    super.key,
  });

  final ValueListenable<OperationFailure> failure;
  final ActivityRecordLoader? loadActivity;

  /// Replaces the generic "The operation failed".
  final String? title;

  /// Shown above the Git output.
  final Widget? content;
  final List<Widget> actions;

  /// Replaces "Close" when the dialog asks for a decision.
  final String? closeLabel;

  @override
  State<OperationFailureDialog> createState() => _OperationFailureDialogState();
}

class _OperationFailureDialogState extends State<OperationFailureDialog> {
  final _records = <BigInt, Future<ActivityRecord?>>{};
  var _includeOutput = false;

  Future<ActivityRecord?>? _record(OperationFailureDetails details) {
    final activity = details.activity;
    final load = widget.loadActivity;
    if (activity == null || load == null) return null;
    return _records.putIfAbsent(activity.id, () async {
      try {
        final page = await load(activity.session, activity.id);
        return page.records
            .where((value) => value.id == activity.id)
            .firstOrNull;
      } on Object {
        return null;
      }
    });
  }

  Future<void> _copy(OperationFailure failure) async {
    final report = StatusNotificationScope.supportReport(
      context,
      failure.details,
    );
    final record = _includeOutput ? await _record(failure.details) : null;
    if (!mounted) return;
    await copyWithStatusNotification(
      context,
      record == null
          ? report
          : '$report\n\n${context.l10n.operationReportGitOutputHeading}\n'
                '${activityClipboardText(record)}',
      record == null
          ? context.l10n.operationReportCopied
          : context.l10n.operationReportCopiedWithOutput,
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.failure,
    builder: (context, failure, _) {
      final record = _record(failure.details);
      void close() => Navigator.of(context).pop();
      return MeridianDialog(
        key: const ValueKey('operation-failure-dialog'),
        width: MeridianLayout.dialogFormWidth,
        title: widget.title ?? context.l10n.operationFailureTitle,
        description: failure.message,
        onSubmit: widget.actions.isEmpty ? close : null,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: MeridianSpace.space4,
          children: [
            ?widget.content,
            FutureBuilder<ActivityRecord?>(
              future: record,
              builder: (context, snapshot) {
                final value = snapshot.data;
                final copy = MeridianButton(
                  key: const ValueKey('operation-failure-copy-report'),
                  label: context.l10n.operationCopyReport,
                  icon: MeridianIcons.copy,
                  variant: MeridianButtonVariant.secondary,
                  size: MeridianControlSize.small,
                  onPressed: () => _copy(failure),
                );
                if (value == null) {
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: copy,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: MeridianSpace.space4,
                  children: [
                    MeridianDisclosure(
                      key: const ValueKey('operation-failure-git-output'),
                      title: context.l10n.operationGitOutput,
                      child: _GitOutput(record: value),
                    ),
                    Row(
                      spacing: MeridianSpace.space4,
                      children: [
                        Expanded(
                          child: MeridianCheckbox(
                            key: const ValueKey(
                              'operation-failure-include-output',
                            ),
                            value: _includeOutput,
                            label: context.l10n.operationReportIncludeOutput,
                            description:
                                context.l10n.operationReportIncludeOutputDetail,
                            onChanged: (value) =>
                                setState(() => _includeOutput = value),
                          ),
                        ),
                        copy,
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        actions: [
          MeridianButton(
            key: const ValueKey('operation-failure-close'),
            label: widget.closeLabel ?? context.l10n.close,
            variant: widget.actions.isEmpty
                ? MeridianButtonVariant.primary
                : MeridianButtonVariant.quiet,
            onPressed: close,
          ),
          ...widget.actions,
        ],
      );
    },
  );
}

/// The command line and output of a Git command, selectable and bounded.
class _GitOutput extends StatelessWidget {
  const _GitOutput({required this.record});

  final ActivityRecord record;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.ground,
      borderRadius: BorderRadius.circular(MeridianTheme.of(context).radius.sm),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: GitLamaLayout.logbookOutputMaxHeight,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MeridianSpace.space3),
        child: SelectableText(
          contextMenuBuilder: nativeTextContextMenuBuilder,
          '\$ ${activityClipboardText(record)}',
          style: context.text.codeSm.copyWith(color: context.colors.inkMuted),
        ),
      ),
    ),
  );
}
