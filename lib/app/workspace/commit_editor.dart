import '../../models/operation_failure.dart';
import '../../widgets/status_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/advanced_rebase.dart';
import '../../models/commit.dart';
import '../../models/app_shortcut.dart';
import '../../models/hosting.dart';
import '../../models/app_command.dart';
import '../../models/remote_command_policy.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../app_shortcut_activator.dart';
import '../../services/repository_session_service.dart';
import '../../services/hosting_connection_service.dart';
import '../../widgets/gitlama_composer.dart';
import '../../widgets/gitlama_list_well.dart';
import '../../widgets/hosting_reference_text_field.dart';
import '../app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../services/workflows/commit_workflow.dart';
import '../../services/workflows/workflow.dart';
import 'workspace_scope.dart';
import '../../services/workflows/workspace_effects.dart';
import '../gitlama_layout.dart';
import 'command_availability.dart';
import 'labels.dart';

enum CommitOverflowAction { template, skipHooks, signOff, options }

class CommitEditor extends StatefulWidget {
  const CommitEditor({
    required this.repositories,
    required this.hosting,
    required this.hostingResources,
    required this.hostingResourcesStale,
    required this.suggestionPaths,
    required this.shortcut,
    required this.branchName,
    required this.headObjectId,
    required this.stagedCount,
    required this.onFailureVisibilityChanged,
    required this.onPush,
    this.fill = false,
    super.key,
  });

  final RepositorySessionService repositories;
  final HostingConnectionService? hosting;
  final HostingResources hostingResources;
  final bool hostingResourcesStale;
  final List<List<int>> suggestionPaths;
  final AppShortcut? shortcut;
  final List<int>? branchName;
  final String? headObjectId;
  final int stagedCount;
  final ValueChanged<bool> onFailureVisibilityChanged;

  /// Starts the push that the Push command starts. Commit and push commits
  /// and then hands over to it, so both pushes behave alike.
  final VoidCallback onPush;

  /// The editor was given a height: the description grows to fill it.
  final bool fill;

  @override
  State<CommitEditor> createState() => CommitEditorState();
}

class CommitEditorState extends State<CommitEditor>
    implements CommitInteraction {
  late final TextEditingController _subject;
  late final TextEditingController _description;
  final FocusNode _descriptionFocus = FocusNode(
    debugLabel: 'commit-description',
  );
  final TextEditingController _coauthors = TextEditingController();
  final TextEditingController _author = TextEditingController();
  CommitTools _tools = const CommitTools();
  var _toolsLoading = false;
  var _toolsSequence = 0;
  var _amendMessageRequested = false;
  var _amend = false;
  var _skipHooks = false;
  var _signing = CommitSigning.useGitConfiguration;
  var _signOff = false;
  late bool _spellcheck;
  var _busy = false;
  var _attemptedSubmit = false;
  CommitExecutionResult? _failure;
  CommitExecutionResult? _lastFailure;
  var _failurePush = false;
  var _commitSucceeded = false;

  /// The last remote commit was sent but its outcome is unknown. The draft
  /// stays; nothing is retried.
  var _outcomeUnknown = false;
  var _clearSequence = 0;
  Timer? _successTimer;

  void submit() => unawaited(_submit(push: false));

  /// What the repository on another computer allows; null for a local one.
  /// Amend, skipped hooks and disabled signing work on a host as here; Commit
  /// & Push also needs the host's transfer permission.
  RemoteTabAccess? get _remote =>
      CommandAvailabilityScope.peek(context)?.remote;

  /// Why [command] is unavailable on the repository's host; null when it may
  /// run or the repository is on this computer.
  String? _remoteReason(AppCommandId command, RemoteTabAccess? remote) =>
      switch (remoteCommandReason(command, remote)) {
        final reason? => workspaceDisabledReason(context, reason),
        null => null,
      };

  /// Why committing (or amending) cannot run now, or null. The button, the
  /// menu command and the shortcut all ask the shared command policy.
  String? _commitReason(CommandMenuState? state) {
    final command = _amend
        ? AppCommandId.commitAmend
        : AppCommandId.commitCreate;
    if (state == null) {
      return _amend || widget.stagedCount > 0
          ? null
          : context.l10n.commitNothingStaged;
    }
    return switch (state.reason(command)) {
      null => null,
      AppCommandDisabledReason.contextRequired when !_amend =>
        context.l10n.commitNothingStaged,
      final reason => workspaceDisabledReason(context, reason),
    };
  }

  void prepareAmend() {
    if (_busy || _remoteReason(AppCommandId.commitAmend, _remote) != null) {
      return;
    }
    _setAmend(true);
  }

  void _setAmend(bool value) {
    setState(() {
      _amend = value;
      _amendMessageRequested =
          value && _subject.text.isEmpty && _description.text.isEmpty;
      _fillAmendMessage();
    });
    if (_amendMessageRequested && !_toolsLoading) {
      unawaited(_loadTools());
    }
  }

  void _fillAmendMessage() {
    if (!_amendMessageRequested) return;
    final message = _tools.recent
        .where((message) => message.objectId == widget.headObjectId)
        .firstOrNull;
    if (message == null) return;
    _amendMessageRequested = false;
    _applyMessage(message.subject, message.description);
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.repositories.activeCommitDraft;
    _spellcheck = WidgetsBinding
        .instance
        .platformDispatcher
        .nativeSpellCheckServiceDefined;
    _subject = TextEditingController(text: draft.subject)
      ..addListener(_saveDraft);
    _description = TextEditingController(text: draft.description)
      ..addListener(_saveDraft);
    unawaited(_loadTools());
  }

  Future<void> _loadTools() async {
    final sequence = ++_toolsSequence;
    final identity = widget.repositories.activeTab?.canonicalIdentity;
    _toolsLoading = true;
    try {
      final tools = await widget.repositories.loadCommitTools();
      if (!mounted ||
          sequence != _toolsSequence ||
          identity != widget.repositories.activeTab?.canonicalIdentity) {
        return;
      }
      setState(() {
        _tools = tools;
        _fillAmendMessage();
      });
    } on RepositorySessionException {
      // The editor remains usable without optional templates and history.
    } finally {
      if (mounted && sequence == _toolsSequence) {
        _toolsLoading = false;
        if (_amendMessageRequested &&
            identity == widget.repositories.activeTab?.canonicalIdentity) {
          _amendMessageRequested = false;
          StatusNotificationScope.show(
            context,
            context.l10n.commitAmendMessageFailed,
            error: true,
          );
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant CommitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headObjectId != widget.headObjectId ||
        oldWidget.repositories != widget.repositories) {
      _tools = const CommitTools();
      unawaited(_loadTools());
    }
  }

  void _saveDraft() {
    // A delayed HEAD message must never replace an intervening edit.
    _amendMessageRequested = false;
    if (_subject.value.composing.isValid &&
        !_subject.value.composing.isCollapsed) {
      return;
    }
    if (_description.value.composing.isValid &&
        !_description.value.composing.isCollapsed) {
      return;
    }
    widget.repositories.updateCommitDraft(
      CommitDraft(subject: _subject.text, description: _description.text),
    );
    if (mounted) setState(() {});
  }

  void _applyMessage(String subject, String description) {
    _subject.value = TextEditingValue(
      text: subject,
      selection: TextSelection.collapsed(offset: subject.length),
    );
    _description.value = TextEditingValue(
      text: description,
      selection: TextSelection.collapsed(offset: description.length),
    );
  }

  void _applyTemplate() {
    final template = _tools.template;
    if (template == null) return;
    final normalized = template.replaceAll('\r\n', '\n').trimRight();
    final split = normalized.indexOf('\n');
    _applyMessage(
      split < 0 ? normalized : normalized.substring(0, split),
      split < 0 ? '' : normalized.substring(split + 1).trimLeft(),
    );
  }

  Future<void> _applyFixupSuggestion({required bool squash}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final suggestion = await widget.repositories.advancedRebases
          .suggestFixupBase(paths: widget.suggestionPaths);
      if (!mounted) return;
      List<int>? message = squash
          ? suggestion.squashMessage
          : suggestion.fixupMessage;
      if (message == null && suggestion.evidence.isNotEmpty) {
        final selected = await showMeridianDialog<FixupEvidence>(
          context: context,
          builder: (context) => MeridianDialog(
            key: const ValueKey('fixup-base-dialog'),
            width: MeridianLayout.dialogFormWidth,
            title: context.l10n.fixupSuggestionPickTitle,
            description: suggestion.state == FixupSuggestionState.ambiguous
                ? context.l10n.fixupSuggestionAmbiguous
                : context.l10n.fixupSuggestionPickHint,
            content: GitLamaListWell(
              itemCount: suggestion.evidence.length,
              itemBuilder: (context, index) {
                final evidence = suggestion.evidence[index];
                return MeridianListRow(
                  onTap: () => Navigator.pop(context, evidence),
                  title: utf8.decode(evidence.subject, allowMalformed: true),
                  subtitle: evidence.path == null
                      ? evidence.commit.substring(0, 8)
                      : utf8.decode(evidence.path!, allowMalformed: true),
                );
              },
            ),
            actions: [
              MeridianButton(
                label: context.l10n.cancel,
                variant: MeridianButtonVariant.quiet,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
        if (selected != null) {
          message = [
            ...utf8.encode(squash ? 'squash! ' : 'fixup! '),
            ...selected.subject,
          ];
        }
      }
      if (message != null && mounted) {
        _applyMessage(
          utf8.decode(message, allowMalformed: true),
          _description.text,
        );
      } else if (mounted && suggestion.evidence.isEmpty) {
        StatusNotificationScope.show(
          context,
          context.l10n.fixupSuggestionUnavailable,
        );
      }
    } on AdvancedRebaseException {
      if (mounted) {
        StatusNotificationScope.show(
          context,
          context.l10n.fixupSuggestionFailed,
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  bool get active => mounted;

  @override
  Future<bool> confirmPublishedAmend() => showMeridianConfirm(
    context,
    title: context.l10n.commitConfirmAmend,
    description: context.l10n.commitPublishedWarning,
    confirmLabel: context.l10n.commitConfirmAmend,
    cancelLabel: context.l10n.cancel,
    destructive: true,
  );

  CommitInteraction get _interaction => this;

  StreamSubscription<WorkspaceEffect>? _commitRequests;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The Commit and Amend commands reach the Composer on screen.
    _commitRequests ??= listenForEffects(
      context,
      WorkspaceEffectKind.commit,
      (effect) => effect.payload == true ? prepareAmend() : submit(),
    );
  }

  /// The Composer's commit workflow of this window.
  CommitWorkflow get _workflow =>
      WorkspaceServicesScope.of(context).workflows.commits;

  Future<void> _submit({required bool push, CommitRetry? retry}) async {
    if (_busy) return;
    final remote = _remote;
    final reason =
        _commitReason(CommandAvailabilityScope.peek(context)) ??
        (push ? _remoteReason(AppCommandId.push, remote) : null);
    if (reason != null) {
      StatusNotificationScope.show(context, reason);
      return;
    }
    if (_subject.text.trim().isEmpty) {
      setState(() => _attemptedSubmit = true);
      return;
    }
    final draft = CommitDraft(
      subject: _subject.text,
      description: _description.text,
    );
    setState(() {
      _busy = true;
      _failure = null;
      _commitSucceeded = false;
      _outcomeUnknown = false;
    });
    widget.onFailureVisibilityChanged(false);
    try {
      final outcome = await _workflow.commit(
        _interaction,
        CommitRequest(
          subject: draft.subject,
          description: draft.description,
          coauthors: _coauthors.text
              .split(';')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
          author: _author.text.trim().isEmpty ? null : _author.text.trim(),
          amend: _amend,
          skipHooks: _skipHooks,
          signing: _signing,
          signOff: _signOff,
        ),
        draft,
        push: push,
        retry: retry,
      );
      if (!mounted) return;
      switch (outcome) {
        case CommitDeclined():
          return;
        case CommitRejected(:final result):
          setState(() {
            _failure = result;
            _lastFailure = result;
            _failurePush = push;
            if (retry == CommitRetry.skipHooks) _skipHooks = true;
          });
          widget.onFailureVisibilityChanged(true);
        case CommitFinished(:final result, :final committed, :final pushNext):
          if (retry == CommitRetry.skipHooks) _skipHooks = true;
          if (committed &&
              _subject.text == draft.subject &&
              _description.text == draft.description) {
            _applyMessage('', '');
            _clearSequence += 1;
            _coauthors.clear();
            _author.clear();
            _amend = false;
          }
          if (committed) {
            _successTimer?.cancel();
            setState(() => _commitSucceeded = true);
            _successTimer = Timer(
              MeridianDurations.celebrate * timeDilation,
              () {
                if (mounted) setState(() => _commitSucceeded = false);
              },
            );
          }
          showWorkflowMessage(
            context,
            commitResultMessage(context, result),
            details: const OperationFailureDetails(
              operation: UserOperationKind.commit,
            ),
          );
          if (pushNext) widget.onPush();
        case CommitWorkflowFailed(failure: OutcomeUnknownFailure()):
          // Never report an unknown outcome as a failure, never retry it,
          // and keep the draft for when the user has reviewed the repository.
          setState(() => _outcomeUnknown = true);
          widget.onFailureVisibilityChanged(true);
          showRemoteOutcomeUnknown(
            context,
            message: context.l10n.remoteOutcomeUnknownCommit,
          );
        case CommitWorkflowFailed(:final failure):
          showWorkflowMessage(
            context,
            workflowFailureMessage(
              context,
              failure,
              session: context.l10n.commitFailed,
            ),
            details: workflowFailureDetails(
              failure,
              operation: UserOperationKind.commit,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOptions() => showMeridianDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        void refresh(VoidCallback update) {
          setState(update);
          setDialogState(() {});
        }

        return MeridianDialog(
          width: MeridianLayout.dialogFormWidth,
          onClose: () => Navigator.pop(dialogContext),
          title: context.l10n.commitOptions,
          // The options apply as they change; Enter closes the dialog.
          onSubmit: () => Navigator.pop(dialogContext),
          content: Column(
            key: const ValueKey('commit-options-content'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: MeridianSpace.space6,
            children: [
              MeridianTextField(
                controller: _coauthors,
                enabled: !_busy,
                label: context.l10n.commitCoauthors,
              ),
              MeridianTextField(
                controller: _author,
                enabled: !_busy,
                label: context.l10n.commitAuthor,
              ),
              MeridianSelect<CommitSigning>(
                key: const ValueKey('commit-options-signing'),
                value: _signing,
                values: CommitSigning.values,
                valueLabel: (value) => _signingLabel(context, value),
                label: context.l10n.commitSigning,
                showLabel: true,
                expand: true,
                onChanged: _busy
                    ? null
                    : (value) => refresh(() => _signing = value),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: MeridianSpace.space4,
                children: [
                  MeridianCheckbox(
                    label: context.l10n.commitSignOff,
                    value: _signOff,
                    onChanged: _busy
                        ? null
                        : (value) => refresh(() => _signOff = value),
                  ),
                  MeridianCheckbox(
                    label: context.l10n.commitSkipHooks,
                    value: _skipHooks,
                    onChanged: _busy
                        ? null
                        : (value) => refresh(() => _skipHooks = value),
                  ),
                  MeridianCheckbox(
                    label: context.l10n.commitSpellcheck,
                    value: _spellcheck,
                    onChanged:
                        _busy ||
                            !WidgetsBinding
                                .instance
                                .platformDispatcher
                                .nativeSpellCheckServiceDefined
                        ? null
                        : (value) => refresh(() => _spellcheck = value),
                  ),
                ],
              ),
              Wrap(
                key: const ValueKey('commit-options-message-tools'),
                spacing: MeridianSpace.space3,
                runSpacing: MeridianSpace.space3,
                children: [
                  MeridianButton(
                    label: context.l10n.commitTemplate,
                    variant: MeridianButtonVariant.secondary,
                    onPressed: _busy || _tools.template == null
                        ? null
                        : () {
                            _applyTemplate();
                            setDialogState(() {});
                          },
                  ),
                  MeridianMenuAnchor(
                    entries: [
                      MeridianMenuItem(
                        label: context.l10n.fixupSuggestionFixup,
                        onSelected: () =>
                            unawaited(_applyFixupSuggestion(squash: false)),
                      ),
                      MeridianMenuItem(
                        label: context.l10n.fixupSuggestionSquash,
                        onSelected: () =>
                            unawaited(_applyFixupSuggestion(squash: true)),
                      ),
                    ],
                    builder: (context, open) => MeridianButton(
                      label: context.l10n.fixupSuggestionAction,
                      variant: MeridianButtonVariant.secondary,
                      trailingIcon: 'chevron-down',
                      onPressed: _busy ? null : open,
                    ),
                  ),
                  MeridianMenuAnchor(
                    entries: [
                      for (
                        var index = 0;
                        index < _tools.recent.length;
                        index += 1
                      )
                        MeridianMenuItem(
                          label: _tools.recent[index].subject,
                          onSelected: () {
                            final message = _tools.recent[index];
                            _applyMessage(message.subject, message.description);
                            setDialogState(() {});
                          },
                        ),
                    ],
                    builder: (context, open) => MeridianButton(
                      label: context.l10n.commitRecent,
                      variant: MeridianButtonVariant.secondary,
                      trailingIcon: 'chevron-down',
                      onPressed: _busy || _tools.recent.isEmpty ? null : open,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  @override
  Future<bool> confirmSkipHooks() async {
    final controller = TextEditingController();
    var confirmed = false;
    final accepted = await showMeridianDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => MeridianDialog(
          width: MeridianLayout.dialogConfirmWidth,
          title: context.l10n.commitSkipHooksConfirmTitle,
          description: context.l10n.commitSkipHooksConfirmBody,
          onSubmit: () => Navigator.pop(dialogContext, true),
          submitDisabled: !confirmed,
          content: MeridianTextField(
            controller: controller,
            autofocus: true,
            label: context.l10n.commitSkipHooksConfirmInput,
            onChanged: (value) => setDialogState(
              () => confirmed = value.trim().toUpperCase() == 'SKIP',
            ),
          ),
          actions: [
            MeridianButton(
              label: context.l10n.cancel,
              variant: MeridianButtonVariant.quiet,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            MeridianButton(
              label: context.l10n.commitSkipHooks,
              variant: MeridianButtonVariant.danger,
              onPressed: confirmed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return accepted ?? false;
  }

  Future<void> _retryWithoutHooks() =>
      _submit(push: _failurePush, retry: CommitRetry.skipHooks);

  Future<void> _retryUnsigned() async {
    setState(() => _signing = CommitSigning.disable);
    await _submit(push: _failurePush, retry: CommitRetry.unsigned);
  }

  String _signingLabel(BuildContext context, CommitSigning signing) =>
      switch (signing) {
        CommitSigning.useGitConfiguration => context.l10n.commitSigningGit,
        CommitSigning.require => context.l10n.commitSigningRequired,
        CommitSigning.disable => context.l10n.commitSigningDisabled,
      };

  /// A remote commit whose outcome is unknown: neither failed nor retried.
  Widget _outcomeUnknownBanner(BuildContext context) => MeridianBanner(
    key: const ValueKey('commit-outcome-unknown'),
    tone: MeridianBannerTone.warning,
    title: context.l10n.remoteOutcomeUnknownTitle,
    message: context.l10n.remoteOutcomeUnknownCommit,
    onDismiss: () {
      setState(() => _outcomeUnknown = false);
      widget.onFailureVisibilityChanged(false);
    },
    dismissLabel: context.l10n.remoteOperationDismiss,
  );

  Widget _failurePanel(BuildContext context, CommitExecutionResult failure) {
    final colors = context.colors;
    final title = switch (failure.failureKind) {
      CommitFailureKind.hook => context.l10n.commitHookFailure,
      CommitFailureKind.signing => context.l10n.commitSigningFailure,
      CommitFailureKind.other || null => context.l10n.commitOtherFailure,
    };
    final heading = failure.exitCode == null
        ? title
        : '$title · ${context.l10n.commitFailureExitCode(failure.exitCode!)}';
    final output = failure.output.take(40).join('\n');
    return Column(
      key: _failure == null ? null : const ValueKey('commit-failure-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MeridianBanner(
          visible: _failure != null,
          tone: MeridianBannerTone.error,
          title: heading,
          message: context.l10n.commitFailed,
          actions: [
            MeridianButton(
              label: context.l10n.commitRetry,
              size: MeridianControlSize.small,
              onPressed: _busy
                  ? null
                  : () => unawaited(_submit(push: _failurePush)),
            ),
            if (failure.failureKind == CommitFailureKind.hook)
              MeridianButton(
                label: context.l10n.commitSkipHooks,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.dangerQuiet,
                onPressed: _busy ? null : () => unawaited(_retryWithoutHooks()),
              ),
            if (failure.failureKind == CommitFailureKind.signing)
              MeridianButton(
                label: context.l10n.commitSigningDisabled,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.dangerQuiet,
                onPressed: _busy ? null : () => unawaited(_retryUnsigned()),
              ),
          ],
        ),
        if (output.isNotEmpty)
          MeridianReveal(
            visible: _failure != null,
            child: Column(
              children: [
                const SizedBox(height: MeridianSpace.space3),
                Container(
                  constraints: const BoxConstraints(
                    maxHeight: GitLamaLayout.commitFailureOutputMaxHeight,
                  ),
                  padding: const EdgeInsets.all(MeridianSpace.space3),
                  decoration: BoxDecoration(
                    color: colors.paneAlt,
                    border: Border.all(color: colors.line),
                    borderRadius: BorderRadius.circular(
                      context.meridian.radius.sm,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      contextMenuBuilder: nativeTextContextMenuBuilder,
                      output,
                      style: context.text.codeSm.copyWith(color: colors.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _commitFooter(
    BuildContext context, {
    required bool canCommit,
    required String? commitReason,
    RemoteTabAccess? remote,
  }) {
    final colors = context.colors;
    final remoteReason = commitReason;
    final amendReason = _remoteReason(AppCommandId.commitAmend, remote);
    // Commit & Push also pushes from the host.
    final pushReason = remoteReason ?? _remoteReason(AppCommandId.push, remote);
    final branch = widget.branchName == null
        ? null
        : utf8.decode(widget.branchName!, allowMalformed: true);
    final shortBranch = branch == null
        ? null
        : branch.characters.length > 12
        ? '${branch.characters.take(11)}…'
        : branch;
    final hash = widget.headObjectId;
    final actionLabel = _amend && hash != null
        ? context.l10n.commitAmendHash(
            hash.substring(0, math.min(8, hash.length)),
          )
        : shortBranch == null
        ? context.l10n.commitAction
        : context.l10n.commitToBranch(shortBranch);
    final commitShortcut = switch (widget.shortcut) {
      final shortcut? => platformShortcutKeys(shortcut),
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: amendReason ?? '',
              child: MeridianCheckbox(
                key: const ValueKey('commit-amend'),
                label: context.l10n.commitAmend,
                value: _amend,
                onChanged: _busy || amendReason != null ? null : _setAmend,
              ),
            ),
            const SizedBox(width: MeridianSpace.space4),
            Text(
              context.l10n.changesStagedFilesCount(widget.stagedCount),
              style: context.text.caption.copyWith(color: colors.inkMuted),
            ),
            const Spacer(),
            NativeMenuButton<CommitOverflowAction>(
              key: const ValueKey('commit-options-menu'),
              enabled: !_busy,
              tooltip: context.l10n.commitOptions,
              icon: const MeridianIcon('more'),
              onSelected: (value) {
                switch (value) {
                  case CommitOverflowAction.template:
                    _applyTemplate();
                  case CommitOverflowAction.skipHooks:
                    setState(() => _skipHooks = !_skipHooks);
                  case CommitOverflowAction.signOff:
                    setState(() => _signOff = !_signOff);
                  case CommitOverflowAction.options:
                    unawaited(_showOptions());
                }
              },
              itemBuilder: (context) => [
                NativeMenuItem(
                  value: CommitOverflowAction.template,
                  title: context.l10n.commitTemplate,
                  enabled: _tools.template != null,
                ),
                NativeMenuItem(
                  value: CommitOverflowAction.options,
                  title: context.l10n.commitOptions,
                ),
                NativeMenuItem(
                  value: CommitOverflowAction.skipHooks,
                  checked: _skipHooks,
                  title: context.l10n.commitSkipHooks,
                ),
                NativeMenuItem(
                  value: CommitOverflowAction.signOff,
                  checked: _signOff,
                  title: context.l10n.commitSignOff,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: MeridianSpace.space4),
        Row(
          children: [
            Expanded(
              child: MeridianButton(
                key: const ValueKey('commit-push-menu'),
                label: context.l10n.commitAndPush,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.secondary,
                onPressed: canCommit && pushReason == null
                    ? () => unawaited(_submit(push: true))
                    : null,
                disabledReason:
                    pushReason ??
                    (canCommit ? null : context.l10n.commitEmptySubject),
              ),
            ),
            const SizedBox(width: MeridianSpace.space4),
            Expanded(
              child: MeridianButton(
                label: actionLabel,
                animateLabel: true,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.primary,
                success: _commitSucceeded,
                shortcut: commitShortcut,
                shortcutReveal: MeridianKbdReveal.whileModifierHeld,
                onPressed: canCommit && remoteReason == null
                    ? () => unawaited(_submit(push: false))
                    : null,
                disabledReason:
                    remoteReason ??
                    (canCommit ? null : context.l10n.commitEmptySubject),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_commitRequests?.cancel());
    _successTimer?.cancel();
    _subject.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    _coauthors.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.meridian;
    final empty = _subject.text.trim().isEmpty;
    final trailing =
        _subject.text.isNotEmpty && _subject.text.trimRight() != _subject.text;
    final length = _subject.text.characters.length;
    final subjectError = empty && _attemptedSubmit
        ? context.l10n.commitEmptySubject
        : trailing
        ? context.l10n.commitTrailingWhitespace
        : null;
    final availability = CommandAvailabilityScope.read(context);
    final remote = availability?.remote;
    final commitReason = _commitReason(availability);
    final canCommit = !_busy && !empty && commitReason == null;
    final fill = widget.fill;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      if (widget.shortcut case final shortcut?) shortcut.activator: submit,
    };
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        child: GitLamaComposer(
          subject: HostingReferenceTextField(
            key: const ValueKey('commit-subject-field'),
            height: GitLamaLayout.composerSubjectHeight,
            style: context.text.bodyStrong,
            maxLines: 1,
            controller: _subject,
            programmaticClearSequence: _clearSequence,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _descriptionFocus.requestFocus(),
            hosting: widget.hosting,
            references: widget.hostingResources.remoteReferences,
            stale: widget.hostingResourcesStale,
            enabled: !_busy,
            placeholder: context.l10n.commitSubject,
            trailingWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SubjectCounter(length: length),
                if (subjectError != null) ...[
                  const SizedBox(width: MeridianSpace.space2),
                  Tooltip(
                    message: subjectError,
                    child: Semantics(
                      label: subjectError,
                      liveRegion: true,
                      child: MeridianIcon(
                        'circle-x',
                        size: MeridianIconSize.regular,
                        color: tokens.colors.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          fill: fill,
          descriptionMinHeight: fill ? _descriptionMinHeight(context) : 0,
          description: MeridianResize(
            child: HostingReferenceTextField(
              key: const ValueKey('commit-description-field'),
              controller: _description,
              programmaticClearSequence: _clearSequence,
              focusNode: _descriptionFocus,
              hosting: widget.hosting,
              references: widget.hostingResources.remoteReferences,
              stale: widget.hostingResourcesStale,
              enabled: !_busy,
              minLines: fill ? null : GitLamaLayout.composerDescriptionMinLines,
              maxLines: fill ? null : GitLamaLayout.composerDescriptionMaxLines,
              expands: fill,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              spellCheckConfiguration:
                  _spellcheck &&
                      WidgetsBinding
                          .instance
                          .platformDispatcher
                          .nativeSpellCheckServiceDefined
                  ? const SpellCheckConfiguration()
                  : const SpellCheckConfiguration.disabled(),
              placeholder: context.l10n.commitDescription,
            ),
          ),
          failure: _outcomeUnknown
              ? _outcomeUnknownBanner(context)
              : _lastFailure == null
              ? null
              : _failurePanel(context, _lastFailure!),
          failureVisible: _outcomeUnknown || _failure != null,
          footer: _commitFooter(
            context,
            canCommit: canCommit,
            commitReason: commitReason,
            remote: remote,
          ),
        ),
      ),
    );
  }
}

/// The description field's height at its minimum line count: the lines
/// plus the field's padding and edge.
double _descriptionMinHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: '\n' * (GitLamaLayout.composerDescriptionMinLines - 1),
      style: context.text.body,
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final lines = painter.height;
  painter.dispose();
  return lines + 2 * (MeridianSpace.space3 + MeridianLayout.hairline);
}

class _SubjectCounter extends StatefulWidget {
  const _SubjectCounter({required this.length});

  final int length;

  @override
  State<_SubjectCounter> createState() => _SubjectCounterState();
}

class _SubjectCounterState extends State<_SubjectCounter> {
  var _nudgeRun = 0;
  var _nudgeTarget = 0.0;

  @override
  void didUpdateWidget(covariant _SubjectCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.length <= GitLamaLayout.subjectLimit &&
        widget.length > GitLamaLayout.subjectLimit &&
        !MeridianMotion.reduced(context)) {
      _nudgeRun++;
      _nudgeTarget = MeridianMotionScales.nudge;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _nudgeTarget = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = widget.length > GitLamaLayout.subjectLimit
        ? 2.0
        : widget.length > GitLamaLayout.subjectGuide
        ? 1.0
        : 0.0;
    return MeridianAnimatedValue(
      value: tone,
      duration: MeridianDurations.select,
      builder: (context, colorProgress, _) {
        final color = colorProgress <= 1
            ? Color.lerp(colors.inkMuted, colors.warning, colorProgress)!
            : Color.lerp(colors.warning, colors.danger, colorProgress - 1)!;
        return MeridianAnimatedValue(
          key: ValueKey(('subject-counter-nudge', _nudgeRun)),
          value: _nudgeTarget,
          spring: MeridianSprings.snappy,
          builder: (context, offset, _) => Transform.translate(
            key: const ValueKey('commit-subject-counter'),
            offset: Offset(offset, 0),
            child: Text(
              '${widget.length}/${GitLamaLayout.subjectGuide}',
              style:
                  (tone == 2 ? context.text.counterOver : context.text.caption)
                      .copyWith(color: color),
            ),
          ),
        );
      },
    );
  }
}
