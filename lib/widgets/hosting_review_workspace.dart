import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gitlama_workflow_header.dart';
import 'git_file_list/git_file_list.dart';
import 'gitlama_file_row.dart';
import 'status_notification.dart';
import '../app/file_actions/file_actions.dart';
import 'author_avatar.dart';
import 'command_preview.dart';
import 'native_menu.dart';
import '../l10n/l10n.dart';
import '../app/app_theme.dart';
import '../models/hosting.dart';
import '../services/hosting_review_service.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

final class HostingReviewWorkspace extends StatefulWidget {
  const HostingReviewWorkspace({
    required this.review,
    required this.connectionId,
    required this.repository,
    required this.pull,
    required this.onOpenUrl,
    super.key,
  });

  final HostingReviewService review;
  final String connectionId;
  final String repository;
  final HostingChangeRequest pull;
  final Future<void> Function(String url) onOpenUrl;

  @override
  State<HostingReviewWorkspace> createState() => _HostingReviewWorkspaceState();
}

class _HostingReviewWorkspaceState extends State<HostingReviewWorkspace> {
  GitFileListMode _filesMode = GitFileListMode.list;
  late final _ReviewActionHost _actionHost = _ReviewActionHost(this);

  /// The changed files of the pull request, in the same rows, list or tree
  /// and menus as every other file list.
  Widget _reviewFiles(BuildContext context, HostingReviewPage page) => Column(
    children: [
      GitFileListHeader(
        title: context.l10n.historyFilesCount(page.diffs.length),
        mode: _filesMode,
        modeKey: const ValueKey('hosting-review-files-mode'),
        onModeChanged: (mode) => setState(() => _filesMode = mode),
      ),
      Expanded(
        child: GitFileList<HostingReviewDiff>(
          listKey: const ValueKey('hosting-review-files'),
          items: page.diffs,
          displayPath: (diff) => diff.path,
          mode: _filesMode,
          preserveOrder: true,
          tailRow: page.nextPage == null
              ? null
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MeridianSpace.space4,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MeridianButton(
                      key: const Key('hosting-review-load-more'),
                      label: context.l10n.hostingLoadMore,
                      variant: MeridianButtonVariant.secondary,
                      size: MeridianControlSize.small,
                      onPressed: _loading ? null : _loadMore,
                    ),
                  ),
                ),
          fileRowBuilder: (context, row) {
            final diff = row.item!;
            final subject = FileActionSubject(
              source: FileActionSource.reviewFile,
              path: utf8.encode(diff.path),
            );
            return fileActionContextMenu(
              context: context,
              subject: () => subject,
              host: _actionHost,
              child: GitLamaFileRow(
                key: ValueKey('hosting-review-file-${diff.stableId}'),
                status: reviewDiffStatus(diff.patch),
                path: row.label,
                depth: row.depth,
                selected: diff.stableId == _selectedDiff?.stableId,
                trailing: FileActionButton(
                  subject: () => subject,
                  host: _actionHost,
                ),
                onActivate: () => setState(() => _selectedDiff = diff),
              ),
            );
          },
        ),
      ),
    ],
  );

  final _body = TextEditingController();
  HostingReviewPage? _page;
  HostingReviewDiff? _selectedDiff;
  List<HostingInlineDraft> _inline = const [];
  HostingReviewAction _action = HostingReviewAction.comment;
  HostingReviewFailure? _failure;
  Timer? _draftTimer;
  var _loading = true;
  var _busy = false;
  var _completed = false;
  var _commentsVisible = false;

  String get _draftKey => HostingReviewService.draftKey(
    widget.connectionId,
    widget.repository,
    widget.pull.number,
  );

  @override
  void initState() {
    super.initState();
    _body.addListener(_draftChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final values = await Future.wait<Object?>([
        widget.review.load(
          connectionId: widget.connectionId,
          repository: widget.repository,
          pullRequest: widget.pull.number,
          headSha: widget.pull.headSha,
        ),
        widget.review.loadDraft(
          connectionId: widget.connectionId,
          repository: widget.repository,
          pullRequest: widget.pull.number,
        ),
      ]);
      if (!mounted) return;
      final page = values[0]! as HostingReviewPage;
      final draft = values[1] as HostingReviewDraft?;
      setState(() {
        _page = page;
        _selectedDiff = page.diffs.firstOrNull;
        if (draft != null && draft.headSha == page.headSha) {
          _action = draft.action;
          _inline = List.unmodifiable(draft.inlineComments);
          _body.text = draft.body;
        }
      });
    } on HostingReviewException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final current = _page;
    final nextPage = current?.nextPage;
    if (_loading || current == null || nextPage == null) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final next = await widget.review.load(
        connectionId: widget.connectionId,
        repository: widget.repository,
        pullRequest: widget.pull.number,
        headSha: current.headSha,
        page: nextPage,
      );
      if (!mounted) return;
      if (next.connectionId != current.connectionId ||
          next.repository != current.repository ||
          next.pullRequest != current.pullRequest ||
          next.headSha != current.headSha) {
        throw const HostingReviewException(HostingReviewFailure.movedBase);
      }
      final diffs = <String, HostingReviewDiff>{
        for (final value in current.diffs) value.stableId: value,
        for (final value in next.diffs) value.stableId: value,
      }.values.toList(growable: false);
      final threads = <String, HostingReviewThread>{
        for (final value in current.threads) value.stableId: value,
        for (final value in next.threads) value.stableId: value,
      }.values.toList(growable: false);
      final checks = <String, HostingCheck>{
        for (final value in current.checks) value.stableId: value,
        for (final value in next.checks) value.stableId: value,
      }.values.toList(growable: false);
      setState(() {
        _page = HostingReviewPage(
          connectionId: current.connectionId,
          repository: current.repository,
          pullRequest: current.pullRequest,
          headSha: current.headSha,
          diffs: diffs,
          threads: threads,
          checks: checks,
          nextPage: next.nextPage,
          incomplete: next.incomplete,
        );
        _selectedDiff ??= diffs.firstOrNull;
      });
    } on HostingReviewException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _draftChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft() async {
    final page = _page;
    if (page == null) return;
    try {
      await widget.review.saveDraft(
        HostingReviewDraft(
          key: _draftKey,
          connectionId: widget.connectionId,
          repository: widget.repository,
          pullRequest: widget.pull.number,
          headSha: page.headSha,
          action: _action,
          body: _body.text,
          inlineComments: _inline,
          updatedAt: 0,
        ),
      );
    } on HostingReviewException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    }
  }

  void _addInline(HostingReviewAnchor anchor, [String body = '']) {
    final existing = _inline.indexWhere(
      (draft) => draft.path == anchor.path && draft.line == anchor.line,
    );
    unawaited(
      showMeridianDialog<String>(
        context: context,
        builder: (context) => _InlineDraftDialog(
          line: anchor.line,
          initialBody: existing < 0 ? body : _inline[existing].body,
        ),
      ).then((value) {
        if (!mounted || value == null || value.isEmpty) return;
        setState(() {
          final next = HostingInlineDraft(
            stableId: existing < 0
                ? 'draft:${anchor.stableId}'
                : _inline[existing].stableId,
            path: anchor.path,
            line: anchor.line,
            body: value,
          );
          _inline = [
            for (var index = 0; index < _inline.length; index += 1)
              if (index != existing) _inline[index],
            next,
          ];
        });
        _draftChanged();
      }),
    );
  }

  void _reanchor(HostingReviewThread thread) {
    final anchor = _page?.diffs
        .where((diff) => diff.path == thread.path)
        .expand((diff) => diff.anchors)
        .firstOrNull;
    if (anchor == null) {
      setState(() => _failure = HostingReviewFailure.movedBase);
      return;
    }
    _addInline(anchor, thread.body);
  }

  Future<void> _previewAndSubmit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final preview = await widget.review.preview(
        connectionId: widget.connectionId,
        repository: widget.repository,
        pullRequest: widget.pull.number,
        headSha: widget.pull.headSha,
        action: _action,
        body: _body.text,
        inlineComments: _inline,
      );
      if (!mounted) return;
      final authorized = await showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.hostingReviewAuthorize,
        confirmLabel: context.l10n.hostingReviewSubmit,
        cancelLabel: context.l10n.cancel,
        content: Column(
          key: const ValueKey('hosting-review-authorize'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: MeridianSpace.space6,
          children: [
            Text(
              context.l10n.hostingReviewAuthorizeSummary(widget.pull.number),
              style: context.text.body.copyWith(color: context.colors.ink),
            ),
            MeridianPropertyList(
              properties: [
                MeridianProperty(
                  label: context.l10n.hostingReviewAction,
                  value: _actionLabel(context, _action),
                  selectable: false,
                ),
                MeridianProperty(
                  label: context.l10n.hostingReviewInlineComments,
                  value: '${_inline.length}',
                  selectable: false,
                ),
              ],
            ),
            GitCommandDetails(
              title: context.l10n.hostingRequestDetails,
              commands: [preview.target, preview.payload],
            ),
          ],
        ),
      );
      if (!authorized || !mounted) return;
      final result = await widget.review.submit(preview);
      if (!mounted) return;
      if (result.state == HostingReviewSubmitState.submitted ||
          result.state == HostingReviewSubmitState.reconciled) {
        _completed = true;
        await widget.review.deleteDraft(
          connectionId: widget.connectionId,
          repository: widget.repository,
          pullRequest: widget.pull.number,
        );
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(
          () => _failure = result.failure ?? HostingReviewFailure.unavailable,
        );
        await _saveDraft();
      }
    } on HostingReviewException catch (error) {
      if (mounted) {
        setState(() => _failure = error.failure);
        await _saveDraft();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryCheck(HostingCheck check) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final preview = await widget.review.previewCheckRetry(
        connectionId: widget.connectionId,
        repository: widget.repository,
        headSha: widget.pull.headSha,
        checkStableId: check.stableId,
      );
      if (!mounted) return;
      final authorized = await showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.hostingCheckRetryAuthorize,
        confirmLabel: context.l10n.hostingCheckRetry,
        cancelLabel: context.l10n.cancel,
        content: Column(
          key: const ValueKey('hosting-check-retry-authorize'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: MeridianSpace.space4,
          children: [
            Text(
              context.l10n.hostingCheckRetrySummary(check.name),
              style: context.text.body.copyWith(color: context.colors.ink),
            ),
            GitCommandDetails(
              title: context.l10n.hostingRequestDetails,
              commands: [preview.target, preview.payload],
            ),
          ],
        ),
      );
      if (!authorized) return;
      final result = await widget.review.retryCheck(preview);
      if (!mounted) return;
      if (result.state == HostingReviewSubmitState.submitted) {
        await _load();
      } else {
        setState(
          () => _failure = result.failure ?? HostingReviewFailure.unavailable,
        );
      }
    } on HostingReviewException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(
      widget.review.cancel(
        connectionId: widget.connectionId,
        repository: widget.repository,
        pullRequest: widget.pull.number,
      ),
    );
    if (!_completed && (_body.text.isNotEmpty || _inline.isNotEmpty)) {
      unawaited(_saveDraft());
    }
    _body.dispose();
    super.dispose();
  }

  Widget _commentsContent(BuildContext context, HostingReviewPage page) =>
      ListView(
        padding: const EdgeInsets.all(MeridianSpace.space5),
        children: [
          if (_failure != null)
            SelectableText(
              contextMenuBuilder: nativeTextContextMenuBuilder,
              context.l10n.hostingReviewFailure(_failure!.name),
            ),
          Text(
            context.l10n.hostingReviewThreads,
            style: context.text.bodyStrong,
          ),
          for (final thread in page.threads)
            Padding(
              padding: const EdgeInsets.all(MeridianSpace.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AuthorAvatar(
                        author: thread.author,
                        size: MeridianLayout.avatarSmall,
                      ),
                      const SizedBox(width: MeridianSpace.space3),
                      Expanded(child: Text(thread.author)),
                      if (thread.outdated)
                        MeridianCount(
                          label: context.l10n.hostingReviewOutdated,
                          tone: MeridianCountTone.quiet,
                        ),
                      if (thread.outdated)
                        const SizedBox(width: MeridianSpace.space2),
                      if (thread.outdated)
                        MeridianButton(
                          label: context.l10n.hostingReviewReanchor,
                          size: MeridianControlSize.small,
                          variant: MeridianButtonVariant.quiet,
                          onPressed: () => _reanchor(thread),
                        ),
                    ],
                  ),
                  SelectableText(
                    contextMenuBuilder: nativeTextContextMenuBuilder,
                    thread.body,
                  ),
                ],
              ),
            ),
          const MeridianHairline(),
          Text(context.l10n.hostingChecks, style: context.text.bodyStrong),
          for (final check in page.checks)
            MeridianListRow(
              title: check.name,
              subtitle: check.state.name,
              onTap: check.detailsUrl == null
                  ? null
                  : () => widget.onOpenUrl(check.detailsUrl!),
              trailing: MeridianButton(
                key: Key('hosting-check-retry-${check.stableId}'),
                label: context.l10n.hostingCheckRetry,
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.secondary,
                onPressed: _busy ? null : () => _retryCheck(check),
              ),
            ),
          const MeridianHairline(),
          MeridianSelect<HostingReviewAction>(
            value: _action,
            values: HostingReviewAction.values,
            valueLabel: (action) => _actionLabel(context, action),
            label: context.l10n.hostingReviewAction,
            showLabel: true,
            expand: true,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() => _action = value);
                    _draftChanged();
                  },
          ),
          const SizedBox(height: MeridianSpace.space4),
          MeridianTextField(
            fieldKey: const Key('hosting-review-body'),
            controller: _body,
            minLines: 4,
            maxLines: 10,
            label: context.l10n.hostingReviewComment,
          ),
          for (final draft in _inline)
            MeridianListRow(
              title: '${draft.path}:${draft.line}',
              subtitle: draft.body,
              trailing: MeridianIconButton(
                label: context.l10n.delete,
                icon: 'close',
                size: MeridianControlSize.small,
                onPressed: () {
                  setState(
                    () => _inline = _inline
                        .where((value) => value.stableId != draft.stableId)
                        .toList(),
                  );
                  _draftChanged();
                },
              ),
            ),
          const SizedBox(height: MeridianSpace.space4),
          MeridianButton(
            key: const Key('hosting-review-preview'),
            label: context.l10n.hostingReviewPreview,
            variant: MeridianButtonVariant.primary,
            onPressed: _busy ? null : _previewAndSubmit,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < GitLamaLayout.reviewDrawerBreakpoint;
    return MeridianDialogSurface(
      margin: const EdgeInsets.all(MeridianSpace.space3),
      maxWidth: size.width - MeridianSpace.space3 * 2,
      maxHeight: size.height - MeridianSpace.space3 * 2,
      child: SizedBox(
        width: size.width - MeridianSpace.space3 * 2,
        height: size.height - MeridianSpace.space3 * 2,
        child: Column(
          children: [
            GitLamaWorkflowHeader(
              title: context.l10n.hostingReviewTitle(widget.pull.number),
              status: widget.pull.headSha,
              actions: [
                if (_loading) const MeridianSpinner(),
                if (compact)
                  MeridianIconButton(
                    label: context.l10n.hostingReviewThreads,
                    icon: 'message-square-text',
                    onPressed: page == null
                        ? null
                        : () => setState(
                            () => _commentsVisible = !_commentsVisible,
                          ),
                  ),
              ],
              exitLabel: context.l10n.close,
              onExit: () => Navigator.pop(context),
            ),
            Expanded(
              child: page == null
                  ? Center(
                      child: _failure == null
                          ? MeridianEmptyState(
                              compact: true,
                              progress: true,
                              title: context.l10n.loading,
                            )
                          : MeridianBanner(
                              tone: MeridianBannerTone.error,
                              message: context.l10n.hostingReviewLoadFailed,
                            ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final drawerWidth = math.min(
                          GitLamaLayout.reviewDrawerWidth,
                          constraints.maxWidth - MeridianSpace.space3 * 2,
                        );
                        return Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(
                                MeridianSpace.space3,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: GitLamaLayout.conflictFileListWidth,
                                    child: MeridianIsland(
                                      expandChild: true,
                                      child: _reviewFiles(context, page),
                                    ),
                                  ),
                                  const SizedBox(width: MeridianSpace.space3),
                                  Expanded(
                                    child: MeridianIsland(
                                      expandChild: true,
                                      child: _DiffReviewPane(
                                        diff: _selectedDiff,
                                        onAnchor: _addInline,
                                      ),
                                    ),
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(width: MeridianSpace.space3),
                                    SizedBox(
                                      width:
                                          GitLamaLayout.reviewCommentRailWidth,
                                      child: MeridianIsland(
                                        expandChild: true,
                                        child: _commentsContent(context, page),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (compact && _commentsVisible)
                              PositionedDirectional(
                                top: MeridianSpace.space3,
                                end: MeridianSpace.space3,
                                width: drawerWidth,
                                child: MeridianPanel(
                                  title: context.l10n.hostingReviewThreads,
                                  onClose: () =>
                                      setState(() => _commentsVisible = false),
                                  width: drawerWidth,
                                  padding: EdgeInsets.zero,
                                  child: SizedBox(
                                    height: math.max(
                                      200,
                                      constraints.maxHeight -
                                          MeridianLayout
                                              .floatingPanelHeaderHeight -
                                          MeridianSpace.space3 * 2,
                                    ),
                                    child: _commentsContent(context, page),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _InlineDraftDialog extends StatefulWidget {
  const _InlineDraftDialog({required this.line, required this.initialBody});

  final int line;
  final String initialBody;

  @override
  State<_InlineDraftDialog> createState() => _InlineDraftDialogState();
}

class _InlineDraftDialogState extends State<_InlineDraftDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MeridianDialog(
    width: MeridianLayout.dialogFormWidth,
    title: context.l10n.hostingReviewInlineTitle(widget.line),
    onSubmit: () => Navigator.pop(context, _controller.text.trim()),
    content: MeridianTextField(
      fieldKey: const Key('hosting-review-inline-body'),
      controller: _controller,
      autofocus: true,
      minLines: 3,
      maxLines: 8,
      label: context.l10n.hostingReviewComment,
    ),
    actions: [
      MeridianButton(
        label: context.l10n.cancel,
        variant: MeridianButtonVariant.quiet,
        onPressed: () => Navigator.pop(context),
      ),
      MeridianButton(
        key: const ValueKey('hosting-review-inline-save'),
        label: context.l10n.hostingReviewInlineSave,
        variant: MeridianButtonVariant.primary,
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
      ),
    ],
  );
}

final class _DiffReviewPane extends StatelessWidget {
  const _DiffReviewPane({required this.diff, required this.onAnchor});

  final HostingReviewDiff? diff;
  final void Function(HostingReviewAnchor anchor) onAnchor;

  @override
  Widget build(BuildContext context) {
    final diff = this.diff;
    if (diff == null) {
      return MeridianEmptyState(
        compact: true,
        title: context.l10n.hostingReviewNoDiff,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(MeridianSpace.space5),
      children: [
        SelectableText(
          contextMenuBuilder: nativeTextContextMenuBuilder,
          diff.patch,
          style: context.text.code,
        ),
        const SizedBox(height: MeridianSpace.space4),
        Wrap(
          spacing: MeridianSpace.space2,
          runSpacing: MeridianSpace.space2,
          children: [
            for (final anchor in diff.anchors.take(100))
              MeridianButton(
                label: '${anchor.line}',
                size: MeridianControlSize.small,
                variant: MeridianButtonVariant.secondary,
                onPressed: () => onAnchor(anchor),
              ),
          ],
        ),
      ],
    );
  }
}

String _actionLabel(BuildContext context, HostingReviewAction action) =>
    switch (action) {
      HostingReviewAction.comment => context.l10n.hostingReviewCommentAction,
      HostingReviewAction.approve => context.l10n.hostingReviewApprove,
      HostingReviewAction.requestChanges =>
        context.l10n.hostingReviewRequestChanges,
    };

/// The status letter of a provider patch: added, deleted, renamed or
/// modified.
String reviewDiffStatus(String patch) {
  bool header(String marker) =>
      patch.startsWith(marker) || patch.contains('\n$marker');
  if (header('new file mode')) return 'A';
  if (header('deleted file mode')) return 'D';
  if (header('rename from')) return 'R';
  return 'M';
}

/// The file actions of a pull-request review.
final class _ReviewActionHost extends FileActionHost {
  _ReviewActionHost(this._state);

  final _HostingReviewWorkspaceState _state;

  @override
  Set<FileAction> get capabilities => const {FileAction.copyPath};

  @override
  String get fileBrowserName => '';

  @override
  void run(
    FileActionCommand command,
    FileActionSubject subject, {
    required bool invert,
  }) {
    if (command.action != FileAction.copyPath) return;
    unawaited(_copy(utf8.decode(subject.path, allowMalformed: true)));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!_state.mounted) return;
    StatusNotificationScope.show(
      _state.context,
      _state.context.l10n.filePathCopied,
    );
  }
}
