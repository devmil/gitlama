import 'dart:convert';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/history_mutation.dart';
import '../../models/inspector.dart' show shortObjectId;
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../widgets/command_preview.dart';
import '../../models/git_names.dart';
import '../../services/workflows/history_rewrite_workflows.dart'
    show BranchIntegration;

class HistoryMutationInputDialog extends StatefulWidget {
  const HistoryMutationInputDialog({
    super.key,
    required this.kind,
    required this.selectedTargets,
    required this.branches,
    required this.publishedHistory,
    this.initialSourceName,
    this.initialTarget,
    this.dirtyWorktree = false,
    this.activeOperation = false,
  });

  final HistoryMutationKind kind;
  final List<String> selectedTargets;
  final List<RepositoryReference> branches;
  final bool publishedHistory;
  final String? initialSourceName;
  final String? initialTarget;
  final bool dirtyWorktree;
  final bool activeOperation;

  @override
  State<HistoryMutationInputDialog> createState() =>
      _HistoryMutationInputDialogState();
}

class _HistoryMutationInputDialogState
    extends State<HistoryMutationInputDialog> {
  late RepositoryReference? _branch;
  var _mergeMode = HistoryMergeMode.fastForwardIfPossible;
  var _acknowledgePublished = false;

  @override
  void initState() {
    super.initState();
    _branch = widget.branches.cast<RepositoryReference?>().firstWhere(
      (branch) =>
          branch != null &&
          (branch.target == widget.initialTarget ||
              nameIs(branch.name, widget.initialSourceName)),
      orElse: () => widget.branches.firstOrNull,
    );
  }

  @override
  Widget build(BuildContext context) {
    final merge = widget.kind == HistoryMutationKind.merge;
    final revert = widget.kind == HistoryMutationKind.revert;
    final targets = merge
        ? <String>[if (_branch case final branch?) branch.target]
        : widget.selectedTargets;
    final needsAcknowledgement =
        widget.publishedHistory &&
        widget.kind == HistoryMutationKind.cherryPick;
    final valid =
        targets.isNotEmpty &&
        (!needsAcknowledgement || _acknowledgePublished) &&
        (!revert || (!widget.dirtyWorktree && !widget.activeOperation));
    void submit() => Navigator.pop(
      context,
      HistoryMutationRequest(
        kind: widget.kind,
        targets: targets,
        sourceName: merge && _branch != null ? _branch!.name : null,
        mergeMode: _mergeMode,
        acknowledgePublishedHistory: _acknowledgePublished,
      ),
    );
    final blocked = revert && widget.activeOperation
        ? context.l10n.historyMutationFailureActive
        : revert && widget.dirtyWorktree
        ? context.l10n.historyRevertCleanRequired
        : null;
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      scrollable: true,
      onSubmit: submit,
      submitDisabled: !valid,
      title: revert && targets.length == 1
          ? context.l10n.historyRevertCommit
          : dialogTitle(historyMutationKindLabel(context, widget.kind)),
      description: switch (widget.kind) {
        HistoryMutationKind.merge => context.l10n.historyMergeSummary,
        _ when targets.isEmpty => context.l10n.historyMutationSelectCommits,
        HistoryMutationKind.cherryPick => context.l10n.historyCherryPickIntro(
          targets.length,
        ),
        HistoryMutationKind.revert => context.l10n.historyRevertIntro(
          targets.length,
        ),
      },
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (merge) ...[
            GitBranchSelector(
              selected: _branch,
              label: context.l10n.historyMutationSourceBranch,
              branches: widget.branches,
              onChanged: (value) => setState(() => _branch = value),
            ),
            MeridianSelect<HistoryMergeMode>(
              value: _mergeMode,
              values: HistoryMergeMode.values,
              valueLabel: (mode) => historyMergeModeLabel(context, mode),
              label: context.l10n.historyMutationMergeMode,
              showLabel: true,
              expand: true,
              onChanged: (value) => setState(() => _mergeMode = value),
            ),
          ],
          if (blocked != null)
            MeridianBanner(tone: MeridianBannerTone.warning, message: blocked),
          if (revert && targets.isNotEmpty)
            Text(
              targets.length == 1
                  ? context.l10n.historyRevertApplyHint
                  : context.l10n.historyRevertApplySingleRequired,
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          if (needsAcknowledgement)
            MeridianCheckbox(
              label: context.l10n.historyMutationPublishedWarning,
              value: _acknowledgePublished,
              onChanged: (value) =>
                  setState(() => _acknowledgePublished = value),
            ),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        if (revert)
          MeridianButton(
            label: context.l10n.historyRevertApplyOnly,
            disabledReason: targets.length > 1
                ? context.l10n.historyRevertApplySingleRequired
                : null,
            onPressed: valid && targets.length == 1
                ? () => Navigator.pop(
                    context,
                    HistoryMutationRequest(
                      kind: widget.kind,
                      targets: targets,
                      noCommit: true,
                    ),
                  )
                : null,
          ),
        MeridianButton(
          label: revert
              ? context.l10n.historyRevertCommitNow
              : dialogTitle(historyMutationKindLabel(context, widget.kind)),
          variant: MeridianButtonVariant.primary,
          onPressed: valid ? submit : null,
        ),
      ],
    );
  }
}

class HistoryMutationPreviewDialog extends StatelessWidget {
  const HistoryMutationPreviewDialog({
    super.key,
    required this.preview,
    required this.prediction,
  });

  final HistoryMutationPreview preview;
  final ConflictPredictionResult? prediction;

  @override
  Widget build(BuildContext context) {
    final branch = utf8.decode(preview.currentBranch, allowMalformed: true);
    final source = preview.sourceName;
    final prediction = this.prediction;
    final merge = preview.kind == HistoryMutationKind.merge;
    final caveats = [
      if (prediction != null && prediction.failure == null)
        prediction.complete
            ? context.l10n.conflictCheckEstimate
            : context.l10n.conflictCheckPartial,
    ];
    return MeridianDialog(
      width: MeridianLayout.dialogConfirmWidth,
      title: switch (preview.kind) {
        HistoryMutationKind.merge => context.l10n.historyMergePreviewTitle,
        HistoryMutationKind.cherryPick =>
          context.l10n.historyCherryPickPreviewTitle,
        HistoryMutationKind.revert => context.l10n.historyRevertPreviewTitle,
      },
      description: switch (preview.kind) {
        HistoryMutationKind.merge => context.l10n.historyMergeSummary,
        HistoryMutationKind.cherryPick => context.l10n.historyCherryPickIntro(
          preview.targets.length,
        ),
        HistoryMutationKind.revert =>
          preview.noCommit
              ? context.l10n.historyRevertApplyIntro
              : context.l10n.historyRevertIntro(preview.targets.length),
      },
      onSubmit: () => Navigator.pop(context, true),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          MeridianPropertyList(
            properties: [
              if (merge)
                MeridianProperty(
                  label: context.l10n.historyMutationSourceBranch,
                  value: source == null
                      ? shortObjectId(preview.targets.firstOrNull ?? '')
                      : utf8.decode(source, allowMalformed: true),
                  monospace: true,
                ),
              MeridianProperty(
                label: context.l10n.historyPreviewCurrentBranch,
                value: branch,
                monospace: true,
              ),
              if (prediction != null)
                MeridianProperty(
                  label: context.l10n.historyPreviewConflicts,
                  value: prediction.failure != null
                      ? context.l10n.conflictCheckUnavailable
                      : prediction.conflictingPaths.isEmpty
                      ? context.l10n.conflictCheckNone
                      : context.l10n.conflictCheckFiles(
                          prediction.conflictingPaths.length,
                        ),
                  selectable: false,
                ),
            ],
          ),
          if (preview.alreadyContained)
            MeridianBanner(
              tone: MeridianBannerTone.info,
              message: context.l10n.historyMutationAlreadyContained,
            ),
          if (caveats.isNotEmpty)
            Text(
              caveats.join(' '),
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          GitCommandDetails(commands: ['git ${preview.arguments.join(' ')}']),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context, false),
        ),
        MeridianButton(
          label: switch (preview.kind) {
            HistoryMutationKind.revert =>
              preview.noCommit
                  ? context.l10n.historyRevertApplyOnly
                  : context.l10n.historyRevertCommitNow,
            _ => dialogTitle(historyMutationKindLabel(context, preview.kind)),
          },
          variant: MeridianButtonVariant.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// Asks how to bring another branch into the current one: merge (the
/// default) or rebase, each explained in a sentence.
class BranchIntegrationDialog extends StatelessWidget {
  const BranchIntegrationDialog({this.sourceName, super.key});

  /// The branch to bring in, or null when it is chosen next.
  final String? sourceName;

  @override
  Widget build(BuildContext context) {
    final sourceName = this.sourceName;
    return MeridianDialog(
      key: const ValueKey('branch-integration-dialog'),
      width: MeridianLayout.dialogConfirmWidth,
      title: context.l10n.branchIntegrationTitle,
      description: sourceName == null
          ? context.l10n.branchIntegrationHintAny
          : context.l10n.branchIntegrationHint(sourceName),
      onSubmit: () => Navigator.pop(context, BranchIntegration.merge),
      content: MeridianPropertyList(
        properties: [
          MeridianProperty(
            label: context.l10n.branchIntegrationMerge,
            value: context.l10n.branchIntegrationMergeDetail,
            selectable: false,
          ),
          MeridianProperty(
            label: context.l10n.branchIntegrationRebase,
            value: sourceName == null
                ? context.l10n.branchIntegrationRebaseDetailAny
                : context.l10n.branchIntegrationRebaseDetail(sourceName),
            selectable: false,
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('branch-integration-rebase'),
          label: context.l10n.branchIntegrationRebaseAction,
          onPressed: () => Navigator.pop(context, BranchIntegration.rebase),
        ),
        MeridianButton(
          key: const ValueKey('branch-integration-merge'),
          label: context.l10n.branchIntegrationMergeAction,
          variant: MeridianButtonVariant.primary,
          autofocus: true,
          onPressed: () => Navigator.pop(context, BranchIntegration.merge),
        ),
      ],
    );
  }
}
