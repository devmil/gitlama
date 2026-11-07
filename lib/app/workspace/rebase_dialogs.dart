import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/advanced_rebase.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/history_mutation.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import '../../models/rebase.dart';
import '../app_shortcut_activator.dart';
import '../../widgets/gitlama_list_well.dart';
import '../../models/inspector.dart' show shortObjectId;
import '../app_theme.dart';
import 'status_bar.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../widgets/command_preview.dart';
import '../gitlama_layout.dart';

class RebaseTargetDialog extends StatefulWidget {
  const RebaseTargetDialog({super.key, required this.branches});

  final List<RepositoryReference> branches;

  @override
  State<RebaseTargetDialog> createState() => _RebaseTargetDialogState();
}

class _RebaseTargetDialogState extends State<RebaseTargetDialog> {
  RepositoryReference? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.branches.firstOrNull;
  }

  @override
  Widget build(BuildContext context) => MeridianDialog(
    width: MeridianLayout.dialogFormWidth,
    title: dialogTitle(context.l10n.commandRebaseBranch),
    onSubmit: () => Navigator.pop(context, _selected),
    submitDisabled: _selected == null,
    content: GitBranchSelector(
      selected: _selected,
      label: context.l10n.historyMutationSourceBranch,
      branches: widget.branches,
      onChanged: (value) => setState(() => _selected = value),
    ),
    actions: [
      MeridianButton(
        label: context.l10n.cancel,
        variant: MeridianButtonVariant.quiet,
        onPressed: () => Navigator.pop(context),
      ),
      MeridianButton(
        label: context.l10n.rebaseEditPlan,
        variant: MeridianButtonVariant.primary,
        onPressed: _selected == null
            ? null
            : () => Navigator.pop(context, _selected),
      ),
    ],
  );
}

class RebaseEditorDialog extends StatefulWidget {
  const RebaseEditorDialog({
    super.key,
    required this.plan,
    required this.prediction,
    required this.shortcuts,
  });

  final RebasePlan plan;
  final ConflictPredictionResult? prediction;
  final Map<AppCommandId, AppShortcut?> shortcuts;

  @override
  State<RebaseEditorDialog> createState() => _RebaseEditorDialogState();
}

class RestackRootDialog extends StatefulWidget {
  const RestackRootDialog({super.key, required this.branches});
  final List<RepositoryReference> branches;
  @override
  State<RestackRootDialog> createState() => _RestackRootDialogState();
}

class _RestackRootDialogState extends State<RestackRootDialog> {
  String _query = '';
  @override
  Widget build(BuildContext context) => MeridianDialog(
    width: MeridianLayout.dialogFormWidth,
    title: context.l10n.restackChooseRoot,
    content: SizedBox(
      height: GitLamaLayout.rebaseTargetListHeight,
      child: Column(
        children: [
          MeridianTextField(
            autofocus: true,
            label: context.l10n.referencePickerSearch,
            variant: MeridianTextFieldVariant.search,
            clearLabel: context.l10n.searchClear,
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
          const SizedBox(height: MeridianSpace.space5),
          Expanded(
            child: ListView(
              children: [
                for (final branch in widget.branches)
                  if ('${utf8.decode(branch.name, allowMalformed: true)} ${branch.target}'
                      .toLowerCase()
                      .contains(_query))
                    MeridianListRow(
                      leading: const MeridianIcon(
                        'branch',
                        size: MeridianIconSize.toolbar,
                      ),
                      title: utf8.decode(branch.name, allowMalformed: true),
                      subtitle: branch.target.substring(0, 8),
                      onTap: () => Navigator.pop(context, branch),
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      MeridianButton(
        label: context.l10n.cancel,
        variant: MeridianButtonVariant.quiet,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}

class RestackPreviewDialog extends StatefulWidget {
  const RestackPreviewDialog({super.key, required this.plan});

  final RestackPlan plan;

  @override
  State<RestackPreviewDialog> createState() => _RestackPreviewDialogState();
}

class _RestackPreviewDialogState extends State<RestackPreviewDialog> {
  var _acknowledge = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.plan.steps;
    final needsAcknowledgement = widget.plan.publishedCount > 0;
    void submit() => Navigator.pop(context, _acknowledge);
    return MeridianDialog(
      width: MeridianLayout.dialogConfirmWidth,
      title: context.l10n.restackPreviewTitle(steps.length),
      description: context.l10n.restackPreviewSummary,
      onSubmit: submit,
      submitDisabled: needsAcknowledgement && !_acknowledge,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (widget.plan.incomplete)
            MeridianBanner(
              tone: MeridianBannerTone.warning,
              message: context.l10n.restackIncompleteWarning,
            ),
          if (steps.isNotEmpty)
            GitLamaListWell(
              itemCount: steps.length,
              itemBuilder: (context, index) {
                final step = steps[index];
                return MeridianListRow(
                  key: ValueKey('restack-step-$index'),
                  leading: GitLamaStepNumber(index + 1),
                  title: utf8.decode(step.branch, allowMalformed: true),
                  subtitle: context.l10n.restackStepOnto(
                    utf8.decode(step.newParent, allowMalformed: true),
                  ),
                  trailing: step.published
                      ? MeridianCount(label: context.l10n.rebasePublishedBadge)
                      : null,
                );
              },
            ),
          if (needsAcknowledgement)
            MeridianCheckbox(
              label: context.l10n.restackPublishedWarning,
              value: _acknowledge,
              onChanged: (value) => setState(() => _acknowledge = value),
            ),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          autofocus: true,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          label: context.l10n.restackRun,
          variant: MeridianButtonVariant.danger,
          onPressed: needsAcknowledgement && !_acknowledge ? null : submit,
        ),
      ],
    );
  }
}

class _RebaseEditorDialogState extends State<RebaseEditorDialog> {
  late List<RebaseInstruction> _instructions;
  final Map<BigInt, TextEditingController> _rewordControllers = {};
  BigInt? _selectedInstructionId;
  var _acknowledgePublished = false;
  var _applyAutosquash = false;

  @override
  void initState() {
    super.initState();
    _instructions = List.of(widget.plan.instructions);
    _selectedInstructionId = _instructions.firstOrNull?.id;
  }

  TextEditingController _rewordController(RebaseInstruction instruction) =>
      _rewordControllers.putIfAbsent(
        instruction.id,
        () => TextEditingController(
          text: instruction.replacementMessage == null
              ? ''
              : utf8.decode(
                  instruction.replacementMessage!,
                  allowMalformed: true,
                ),
        ),
      );

  @override
  void dispose() {
    for (final controller in _rewordControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    if (_instructions.isEmpty) return false;
    if (_instructions.first.action == RebaseAction.squash ||
        _instructions.first.action == RebaseAction.fixup) {
      return false;
    }
    if (_instructions.any(
      (item) =>
          item.action == RebaseAction.reword &&
          (item.replacementMessage == null || item.replacementMessage!.isEmpty),
    )) {
      return false;
    }
    return widget.plan.publishedCount == 0 || _acknowledgePublished;
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _instructions.length || from == to) return;
    setState(() {
      final item = _instructions.removeAt(from);
      _instructions.insert(to, item);
    });
  }

  void _setAction(int index, RebaseAction action) {
    setState(() {
      _instructions[index] = _instructions[index].copyWith(
        action: action,
        clearReplacementMessage: action != RebaseAction.reword,
      );
    });
  }

  void _runCommand(AppCommandId command) {
    final index = _instructions.indexWhere(
      (item) => item.id == _selectedInstructionId,
    );
    if (index < 0) return;
    final action = switch (command) {
      AppCommandId.rebaseSquash => RebaseAction.squash,
      AppCommandId.rebaseFixup => RebaseAction.fixup,
      AppCommandId.rebaseReword => RebaseAction.reword,
      AppCommandId.rebaseDrop => RebaseAction.drop,
      _ => null,
    };
    if (action != null) _setAction(index, action);
  }

  void _squashOnto(BigInt draggedId, BigInt targetId) {
    final from = _instructions.indexWhere((item) => item.id == draggedId);
    final target = _instructions.indexWhere((item) => item.id == targetId);
    if (from < 0 || target < 0 || from == target) return;
    setState(() {
      final item = _instructions.removeAt(from);
      final adjustedTarget = _instructions.indexWhere(
        (candidate) => candidate.id == targetId,
      );
      _instructions.insert(
        adjustedTarget + 1,
        item.copyWith(action: RebaseAction.squash),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final ontoName = plan.ontoName;
    final conflicts = switch (widget.prediction) {
      final prediction? when prediction.failure == null =>
        prediction.conflictingPaths.length,
      _ => 0,
    };
    final dialog = MeridianDialog(
      width: MeridianLayout.dialogWorkflowWidth,
      title: context.l10n.rebaseEditorTitle,
      description: context.l10n.rebaseEditorSummary(
        utf8.decode(plan.currentBranch, allowMalformed: true),
        ontoName == null
            ? shortObjectId(plan.onto)
            : utf8.decode(ontoName, allowMalformed: true),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (conflicts > 0)
            MeridianBanner(
              tone: MeridianBannerTone.warning,
              message: context.l10n.rebaseConflictsExpected(conflicts),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: MeridianSpace.space3,
            children: [
              Text(
                context.l10n.rebaseInstructionCount(_instructions.length),
                style: context.text.caption.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: GitLamaLayout.rebaseInstructionListMaxHeight,
                ),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) =>
                      MeridianLift(lifted: true, child: child),
                  itemCount: _instructions.length,
                  onReorderItem: _move,
                  itemBuilder: (context, index) {
                    final instruction = _instructions[index];
                    return Focus(
                      key: ValueKey(instruction.id),
                      onFocusChange: (focused) {
                        if (focused) _selectedInstructionId = instruction.id;
                      },
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final keyboard = HardwareKeyboard.instance;
                        final modifier =
                            keyboard.isControlPressed || keyboard.isMetaPressed;
                        if (modifier &&
                            event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _move(index, index - 1);
                          return KeyEventResult.handled;
                        }
                        if (modifier &&
                            event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _move(index, index + 1);
                          return KeyEventResult.handled;
                        }
                        if (!modifier && !keyboard.isAltPressed) {
                          final action = switch (event.character
                              ?.toLowerCase()) {
                            'p' => RebaseAction.pick,
                            'r' => RebaseAction.reword,
                            'e' => RebaseAction.edit,
                            's' => RebaseAction.squash,
                            'f' => RebaseAction.fixup,
                            'd' => RebaseAction.drop,
                            _ => null,
                          };
                          if (action != null) {
                            _setAction(index, action);
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: DragTarget<BigInt>(
                        onWillAcceptWithDetails: (details) =>
                            details.data != instruction.id,
                        onAcceptWithDetails: (details) =>
                            _squashOnto(details.data, instruction.id),
                        builder: (context, candidates, rejected) => Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: MeridianSpace.space2,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: candidates.isEmpty
                                  ? context.colors.paneAlt
                                  : context.colors.accentSoft,
                              borderRadius: BorderRadius.circular(
                                context.meridian.radius.lg,
                              ),
                            ),
                            child: _RebaseConnector(
                              active:
                                  instruction.action == RebaseAction.squash ||
                                  instruction.action == RebaseAction.fixup,
                              child: MeridianAnimatedValue(
                                value:
                                    instruction.action == RebaseAction.squash ||
                                        instruction.action == RebaseAction.fixup
                                    ? GitLamaLayout.rebaseIndent
                                    : MeridianSpace.space4,
                                spring: MeridianSprings.snappy,
                                builder: (context, indent, child) => Padding(
                                  padding: EdgeInsetsDirectional.only(
                                    start: indent,
                                    end: MeridianSpace.space4,
                                    bottom:
                                        instruction.action ==
                                            RebaseAction.reword
                                        ? MeridianSpace.space4
                                        : 0,
                                  ),
                                  child: child,
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: MeridianTheme.of(
                                        context,
                                      ).density.rowExtent,
                                      child: Row(
                                        children: [
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Tooltip(
                                              message: context
                                                  .l10n
                                                  .rebaseDragToReorder,
                                              child: const SizedBox.square(
                                                dimension:
                                                    MeridianSize.controlSm,
                                                child: Center(
                                                  child: MeridianIcon(
                                                    'grip-vertical',
                                                    size:
                                                        MeridianIconSize.small,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(
                                            width: MeridianSpace.space2,
                                          ),
                                          MeridianSelect<RebaseAction>(
                                            width:
                                                GitLamaLayout.rebaseActionWidth,
                                            animateValue: true,
                                            value: instruction.action,
                                            values: RebaseAction.values,
                                            valueLabel: (action) =>
                                                rebaseActionLabel(
                                                  context,
                                                  action,
                                                ),
                                            onChanged: (value) =>
                                                _setAction(index, value),
                                          ),
                                          const SizedBox(
                                            width: MeridianSpace.space4,
                                          ),
                                          Text(
                                            instruction.oid.substring(0, 8),
                                            style: context.text.codeSm.copyWith(
                                              color: context.colors.inkMuted,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: MeridianSpace.space4,
                                          ),
                                          Expanded(
                                            child: MeridianAnimatedValue(
                                              value:
                                                  instruction.action ==
                                                      RebaseAction.drop
                                                  ? 1
                                                  : 0,
                                              duration: MeridianDurations.quick,
                                              // The strike ends with the
                                              // subject's (ellipsised) text,
                                              // not the row.
                                              builder: (context, progress, _) => Align(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: Stack(
                                                  children: [
                                                    Opacity(
                                                      opacity:
                                                          1 -
                                                          (1 -
                                                                  GitLamaOpacity
                                                                      .ignoredRow) *
                                                              progress,
                                                      child: Text(
                                                        utf8.decode(
                                                          instruction.subject,
                                                          allowMalformed: true,
                                                        ),
                                                        key: ValueKey(
                                                          'rebase-subject-$index',
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        // Sized to the shown
                                                        // line, so the strike
                                                        // can match it.
                                                        textWidthBasis:
                                                            TextWidthBasis
                                                                .longestLine,
                                                        style:
                                                            context.text.body,
                                                      ),
                                                    ),
                                                    if (progress > 0)
                                                      Positioned.fill(
                                                        child: IgnorePointer(
                                                          child: MeridianStroke(
                                                            key: ValueKey(
                                                              'rebase-strike-$index',
                                                            ),
                                                            color: context
                                                                .colors
                                                                .inkMuted,
                                                            progress: progress,
                                                            strokeWidth:
                                                                MeridianLayout
                                                                    .hairline,
                                                            path: (size) => Path()
                                                              ..moveTo(
                                                                0,
                                                                size.height / 2,
                                                              )
                                                              ..lineTo(
                                                                size.width,
                                                                size.height / 2,
                                                              ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (instruction.published)
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional.symmetric(
                                                    horizontal:
                                                        MeridianSpace.space3,
                                                  ),
                                              child: MeridianCount(
                                                label: context
                                                    .l10n
                                                    .rebasePublishedBadge,
                                              ),
                                            ),
                                          LongPressDraggable<BigInt>(
                                            data: instruction.id,
                                            feedback: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: MeridianTheme.of(
                                                  context,
                                                ).colors.raised,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      context
                                                          .meridian
                                                          .radius
                                                          .lg,
                                                    ),
                                                boxShadow: MeridianTheme.of(
                                                  context,
                                                ).shadows.shadowFloat,
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  MeridianSpace.space4,
                                                ),
                                                child: Text(
                                                  context
                                                      .l10n
                                                      .rebaseDragToSquash,
                                                ),
                                              ),
                                            ),
                                            child: Tooltip(
                                              message: context
                                                  .l10n
                                                  .rebaseDragToSquash,
                                              child: const MeridianIcon(
                                                'git-merge',
                                              ),
                                            ),
                                          ),
                                          MeridianIconButton(
                                            label: context.l10n.rebaseMoveUp,
                                            icon: 'arrow-up',
                                            size: MeridianControlSize.small,
                                            onPressed: index == 0
                                                ? null
                                                : () => _move(index, index - 1),
                                          ),
                                          MeridianIconButton(
                                            label: context.l10n.rebaseMoveDown,
                                            icon: 'arrow-down',
                                            size: MeridianControlSize.small,
                                            onPressed:
                                                index ==
                                                    _instructions.length - 1
                                                ? null
                                                : () => _move(index, index + 1),
                                          ),
                                          NativeMenuButton<RebaseAction>(
                                            tooltip: context.l10n.toolbarMore,
                                            icon: const MeridianIcon('more'),
                                            initialValue: instruction.action,
                                            onSelected: (action) =>
                                                _setAction(index, action),
                                            itemBuilder: (_) => [
                                              for (final action
                                                  in RebaseAction.values)
                                                NativeMenuItem(
                                                  value: action,
                                                  title: rebaseActionLabel(
                                                    context,
                                                    action,
                                                  ),
                                                  checked:
                                                      action ==
                                                      instruction.action,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (instruction.action ==
                                        RebaseAction.reword)
                                      MeridianTextField(
                                        fieldKey: ValueKey(
                                          'reword-${instruction.id}',
                                        ),
                                        controller: _rewordController(
                                          instruction,
                                        ),
                                        label: context
                                            .l10n
                                            .rebaseReplacementMessage,
                                        onChanged: (value) => setState(() {
                                          _instructions[index] = instruction
                                              .copyWith(
                                                replacementMessage: utf8.encode(
                                                  value,
                                                ),
                                              );
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: MeridianSpace.space4,
            children: [
              MeridianCheckbox(
                key: const ValueKey('rebase-autosquash'),
                label: context.l10n.rebaseAutosquash,
                description: context.l10n.rebaseAutosquashHint,
                value: _applyAutosquash,
                onChanged: (value) => setState(() => _applyAutosquash = value),
              ),
              if (plan.publishedCount > 0)
                MeridianCheckbox(
                  key: const ValueKey('rebase-acknowledge-published'),
                  label: context.l10n.rebasePublishedWarning,
                  description: context.l10n.rebasePublishedNote(
                    plan.publishedCount,
                  ),
                  value: _acknowledgePublished,
                  onChanged: (value) =>
                      setState(() => _acknowledgePublished = value),
                ),
            ],
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
          label: context.l10n.rebaseStart,
          variant: MeridianButtonVariant.primary,
          onPressed: !_valid
              ? null
              : () => Navigator.pop(context, (
                  instructions: List<RebaseInstruction>.unmodifiable(
                    _instructions,
                  ),
                  acknowledgePublishedHistory: _acknowledgePublished,
                  applyAutosquash: _applyAutosquash,
                )),
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        for (final command in const [
          AppCommandId.rebaseSquash,
          AppCommandId.rebaseFixup,
          AppCommandId.rebaseReword,
          AppCommandId.rebaseDrop,
        ])
          if (widget.shortcuts[command] case final shortcut?)
            shortcut.activator: () => _runCommand(command),
      },
      child: Focus(autofocus: true, child: dialog),
    );
  }
}

class _RebaseConnector extends StatelessWidget {
  const _RebaseConnector({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => MeridianAnimatedValue(
    value: active ? 1 : 0,
    duration: GitLamaMotion.laneDrawRow,
    builder: (context, progress, child) => Stack(
      fit: StackFit.passthrough,
      children: [
        child!,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: GitLamaLayout.rebaseIndent,
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) => MeridianStroke(
                size: constraints.biggest,
                color: context.colors.accent,
                progress: progress,
                strokeWidth: MeridianLayout.hairline,
                path: (size) => Path()
                  ..moveTo(0, 0)
                  ..lineTo(0, size.height / 2)
                  ..quadraticBezierTo(
                    0,
                    size.height * .75,
                    size.width,
                    size.height * .75,
                  ),
              ),
            ),
          ),
        ),
      ],
    ),
    child: child,
  );
}

class RebasePreviewDialog extends StatelessWidget {
  const RebasePreviewDialog({super.key, required this.preview});

  final RebasePreview preview;

  @override
  Widget build(BuildContext context) {
    final instructions = preview.instructions;
    String subject(RebaseInstruction instruction) =>
        utf8.decode(instruction.subject, allowMalformed: true);
    String? detail(RebaseInstruction instruction) {
      switch (instruction.action) {
        case RebaseAction.squash || RebaseAction.fixup:
          final base = instructions
              .where((item) => item.id == instruction.autosquashBaseId)
              .firstOrNull;
          return base == null
              ? context.l10n.rebaseStepCombinedAbove
              : context.l10n.rebaseStepCombinedWith(subject(base));
        case RebaseAction.reword:
          final message = instruction.replacementMessage;
          if (message == null) return null;
          return context.l10n.rebaseStepNewMessage(
            utf8.decode(message, allowMalformed: true).split('\n').first,
          );
        case RebaseAction.pick || RebaseAction.edit || RebaseAction.drop:
          return null;
      }
    }

    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: context.l10n.rebasePreviewTitle,
      description: context.l10n.rebasePreviewSummary,
      onSubmit: () => Navigator.pop(context, true),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (instructions.isNotEmpty)
            GitLamaListWell(
              itemCount: instructions.length,
              itemBuilder: (context, index) {
                final instruction = instructions[index];
                return MeridianListRow(
                  key: ValueKey('rebase-step-$index'),
                  leading: GitLamaStepNumber(index + 1),
                  title: subject(instruction),
                  subtitle: detail(instruction),
                  twoLine: detail(instruction) != null,
                  meta: rebaseActionLabel(context, instruction.action),
                  dimmed: instruction.action == RebaseAction.drop,
                );
              },
            ),
          if (preview.autosquashApplied > 0)
            Text(
              context.l10n.rebaseAutosquashApplied(preview.autosquashApplied),
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          GitCommandDetails(
            commands: [
              'git ${preview.arguments.join(' ')}',
              '',
              utf8.decode(preview.todo, allowMalformed: true).trimRight(),
            ],
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          autofocus: true,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context, false),
        ),
        MeridianButton(
          label: context.l10n.rebaseStart,
          variant: MeridianButtonVariant.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
