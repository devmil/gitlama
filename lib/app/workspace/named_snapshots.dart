import '../../widgets/status_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import '../../models/named_snapshot.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/gitlama_ref_chip.dart';
import '../app_theme.dart';
import '../workspace_shell.dart';
import 'remote_workspace.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';
import '../../widgets/gitlama_list_well.dart';

class NamedSnapshotsPanel extends StatefulWidget {
  const NamedSnapshotsPanel({
    required this.repositories,
    required this.onClose,
    required this.onConflict,
    super.key,
  });

  final RepositorySessionService repositories;
  final VoidCallback onClose;
  final VoidCallback onConflict;

  @override
  State<NamedSnapshotsPanel> createState() => _NamedSnapshotsPanelState();
}

class _NamedSnapshotsPanelState extends State<NamedSnapshotsPanel> {
  final TextEditingController _name = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<NamedSnapshot> _entries = [];
  var _includeUntracked = true;
  var _keepIndex = false;
  var _loading = true;
  var _busy = false;
  int? _nextOffset;
  BigInt? _selectedId;
  NamedSnapshotFailureCode? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && _nextOffset == null) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await widget.repositories.snapshots.page(
        offset: reset ? 0 : _nextOffset!,
        maximum: 24,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(page.entries);
        _nextOffset = page.nextOffset;
        if (_selectedId == null ||
            !_entries.any((entry) => entry.id == _selectedId)) {
          _selectedId = _entries.firstOrNull?.id;
        }
        _loading = false;
      });
    } on NamedSnapshotException catch (error) {
      if (mounted) {
        setState(() {
          _failure = error.code;
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (_busy || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await widget.repositories.snapshots.create(
        name: name,
        includeUntracked: _includeUntracked,
        keepIndex: _keepIndex,
      );
      if (!mounted) return;
      if (result.state == NamedSnapshotExecutionState.conflict) {
        widget.onConflict();
        return;
      }
      _reportUncertain(result);
      _name.clear();
      _selectedId = result.snapshot?.id;
      await _load(reset: true);
    } on RemoteOutcomeUnknownException {
      if (mounted) showRemoteOutcomeUnknown(context);
    } on NamedSnapshotException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks the user to inspect the repository when Git could not confirm what
  /// a snapshot operation changed.
  void _reportUncertain(NamedSnapshotExecutionResult result) {
    if (result.state == NamedSnapshotExecutionState.outcomeUncertain) {
      StatusNotificationScope.show(
        context,
        context.l10n.mutationOutcomeUncertain,
        error: true,
      );
    }
  }

  Future<void> _restore(NamedSnapshot snapshot) async {
    setState(() => _busy = true);
    try {
      final preview = await widget.repositories.snapshots.previewRestore(
        snapshot.id,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      final confirmed = await showMeridianDialog<bool>(
        context: context,
        builder: (context) => NamedSnapshotRestoreDialog(preview: preview),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      final result = await widget.repositories.snapshots.executeRestore(
        preview,
      );
      if (!mounted) return;
      _selectedId = snapshot.id;
      if (result.state == NamedSnapshotExecutionState.conflict) {
        widget.onConflict();
        return;
      }
      _reportUncertain(result);
      await _load(reset: true);
    } on RemoteOutcomeUnknownException {
      if (mounted) showRemoteOutcomeUnknown(context);
    } on NamedSnapshotException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _branch(NamedSnapshot snapshot) async {
    final controller = TextEditingController();
    final branch = await showMeridianDialog<String>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final name = controller.text.trim();
          void create() => Navigator.pop(context, name);
          return MeridianDialog(
            width: MeridianLayout.dialogFormWidth,
            title: context.l10n.namedSnapshotBranchTitle,
            onSubmit: create,
            submitDisabled: name.isEmpty,
            content: GitReferenceField(
              controller: controller,
              autofocus: true,
              normalize: true,
              suggestSegments: true,
              label: context.l10n.refMutationName,
              names: gitBranchNameSuggestions(
                widget
                        .repositories
                        .workspace
                        .activeTab
                        ?.session
                        ?.snapshot
                        .refs ??
                    const RepositoryRefs(),
              ),
            ),
            actions: [
              MeridianButton(
                label: context.l10n.cancel,
                variant: MeridianButtonVariant.quiet,
                onPressed: () => Navigator.pop(context),
              ),
              MeridianButton(
                label: context.l10n.namedSnapshotBranch,
                variant: MeridianButtonVariant.primary,
                onPressed: name.isEmpty ? null : create,
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (branch == null || branch.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repositories.snapshots.branchFrom(snapshot, branch);
      if (mounted) {
        StatusNotificationScope.show(
          context,
          context.l10n.namedSnapshotBranchCreated,
        );
      }
    } on NamedSnapshotException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(NamedSnapshot snapshot) async {
    final confirmed = await showMeridianConfirm(
      context,
      title: context.l10n.namedSnapshotDeleteTitle,
      description: context.l10n.namedSnapshotDeleteMessage(snapshot.name),
      confirmLabel: context.l10n.delete,
      cancelLabel: context.l10n.cancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repositories.snapshots.delete(snapshot);
      if (mounted) await _load(reset: true);
    } on RemoteOutcomeUnknownException {
      if (mounted) showRemoteOutcomeUnknown(context);
    } on NamedSnapshotException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _inspect(NamedSnapshot snapshot) => showMeridianDialog<void>(
    context: context,
    builder: (context) {
      String count(int value) =>
          NumberFormat.decimalPattern(context.l10n.localeName).format(value);
      return MeridianDialog(
        width: MeridianLayout.dialogConfirmWidth,
        onClose: () => Navigator.pop(context),
        title: snapshot.name,
        content: MeridianPropertyList(
          key: const Key('named-snapshot-facts'),
          properties: [
            MeridianProperty(
              label: context.l10n.namedSnapshotFactBranch,
              value: snapshot.baseRef == null
                  ? context.l10n.namedSnapshotNoBranch
                  : utf8.decode(snapshot.baseRef!, allowMalformed: true),
            ),
            MeridianProperty(
              label: context.l10n.namedSnapshotFactBase,
              value: snapshot.baseOid.substring(0, 8),
              monospace: true,
            ),
            MeridianProperty(
              label: context.l10n.changesStaged,
              value: count(snapshot.stagedCount),
              selectable: false,
            ),
            MeridianProperty(
              label: context.l10n.changesUnstaged,
              value: count(snapshot.unstagedCount),
              selectable: false,
            ),
            MeridianProperty(
              label: context.l10n.namedSnapshotFactNewFiles,
              value: count(snapshot.untrackedCount),
              selectable: false,
            ),
            MeridianProperty(
              label: context.l10n.namedSnapshotFactId,
              value: snapshot.objectId.substring(0, 8),
              monospace: true,
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    // A host that allows no recovery changes still lists its snapshots.
    final remoteReason = remoteWriteReason(context, RemoteCapability.recovery);
    return MeridianPanel(
      title: context.l10n.namedSnapshotsTitle,
      onClose: widget.onClose,
      width: GitLamaLayout.snapshotsPanelWidth,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: floatingPanelBodyHeight(
          context,
          GitLamaLayout.snapshotsBodyHeight,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(MeridianSpace.space5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.paneAlt,
                  borderRadius: BorderRadius.circular(
                    context.meridian.radius.lg,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(MeridianSpace.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: MeridianSpace.space5,
                    children: [
                      MeridianTextField(
                        controller: _name,
                        enabled: !_busy,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(128),
                        ],
                        label: context.l10n.namedSnapshotName,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => unawaited(_create()),
                      ),
                      Wrap(
                        spacing: MeridianSpace.space7,
                        runSpacing: MeridianSpace.space4,
                        children: [
                          MeridianCheckbox(
                            label: context.l10n.stashIncludeUntracked,
                            value: _includeUntracked,
                            onChanged: _busy
                                ? null
                                : (value) =>
                                      setState(() => _includeUntracked = value),
                          ),
                          MeridianCheckbox(
                            label: context.l10n.stashKeepIndex,
                            value: _keepIndex,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _keepIndex = value),
                          ),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: MeridianButton(
                          label: context.l10n.namedSnapshotCreate,
                          variant: MeridianButtonVariant.primary,
                          size: MeridianControlSize.small,
                          disabledReason: remoteReason,
                          onPressed:
                              _busy ||
                                  _name.text.trim().isEmpty ||
                                  remoteReason != null
                              ? null
                              : _create,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space5),
                child: MeridianBanner(
                  tone: MeridianBannerTone.error,
                  message: _namedSnapshotFailureLabel(context, _failure!),
                ),
              ),
            if (_busy) const MeridianProgressBar(),
            Expanded(
              child: _loading && _entries.isEmpty
                  ? MeridianEmptyState(
                      compact: true,
                      progress: true,
                      title: context.l10n.loading,
                    )
                  : _entries.isEmpty
                  ? MeridianEmptyState(
                      compact: true,
                      icon: 'stash',
                      title: context.l10n.namedSnapshotsEmpty,
                      message: context.l10n.namedSnapshotsEmptyHelp,
                    )
                  : MeridianList.builder(
                      controller: _scroll,
                      itemCount:
                          _entries.length + (_nextOffset == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == _entries.length) {
                          return Center(
                            child: MeridianButton(
                              label: context.l10n.loadMore,
                              variant: MeridianButtonVariant.quiet,
                              size: MeridianControlSize.small,
                              onPressed: _loading
                                  ? null
                                  : () => unawaited(_load(reset: false)),
                            ),
                          );
                        }
                        final entry = _entries[index];
                        return MeridianListRow(
                          selected: entry.id == _selectedId,
                          onTap: () => setState(() => _selectedId = entry.id),
                          title: entry.name,
                          subtitle: MaterialLocalizations.of(context)
                              .formatMediumDate(
                                DateTime.fromMillisecondsSinceEpoch(
                                  entry.createdAtUnixMs.toInt(),
                                ),
                              ),
                          titleTrailing: entry.baseRef == null
                              ? null
                              : GitLamaRefChip(
                                  name: utf8.decode(
                                    entry.baseRef!,
                                    allowMalformed: true,
                                  ),
                                  kind: GitLamaRefKind.local,
                                ),
                          leading: MeridianIcon(
                            entry.state == NamedSnapshotState.ready
                                ? 'stash'
                                : 'triangle-alert',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: MeridianSpace.space2,
                            children: [
                              Tooltip(
                                message: context.l10n.changesStaged,
                                child: MeridianCount(
                                  label: '${entry.stagedCount}',
                                ),
                              ),
                              Tooltip(
                                message: context.l10n.changesUnstaged,
                                child: MeridianCount(
                                  label: '${entry.unstagedCount}',
                                ),
                              ),
                              Tooltip(
                                message: context.l10n.namedSnapshotFactNewFiles,
                                child: MeridianCount(
                                  label: '${entry.untrackedCount}',
                                ),
                              ),
                              const SizedBox(width: MeridianSpace.space1),
                              NativeMenuButton<String>(
                                enabled: !_busy,
                                onSelected: (action) {
                                  switch (action) {
                                    case 'inspect':
                                      _inspect(entry);
                                    case 'restore':
                                      unawaited(_restore(entry));
                                    case 'branch':
                                      unawaited(_branch(entry));
                                    case 'delete':
                                      unawaited(_delete(entry));
                                  }
                                },
                                itemBuilder: (context) => [
                                  NativeMenuItem(
                                    value: 'inspect',
                                    title: context.l10n.namedSnapshotInspect,
                                  ),
                                  NativeMenuItem(
                                    value: 'restore',
                                    enabled:
                                        entry.state == NamedSnapshotState.ready,
                                    disabledReason: remoteReason,
                                    title: context.l10n.namedSnapshotRestore,
                                  ),
                                  NativeMenuItem(
                                    value: 'branch',
                                    enabled:
                                        entry.state == NamedSnapshotState.ready,
                                    disabledReason: remoteReason,
                                    title: context.l10n.namedSnapshotBranch,
                                  ),
                                  const NativeMenuItem.separator(),
                                  NativeMenuItem(
                                    value: 'delete',
                                    disabledReason: remoteReason,
                                    title: context.l10n.delete,
                                    danger: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
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

/// Confirms replacing the current changes with a snapshot's.
@visibleForTesting
class NamedSnapshotRestoreDialog extends StatefulWidget {
  const NamedSnapshotRestoreDialog({required this.preview, super.key});

  final NamedSnapshotRestorePreview preview;

  @override
  State<NamedSnapshotRestoreDialog> createState() =>
      _NamedSnapshotRestoreDialogState();
}

class _NamedSnapshotRestoreDialogState
    extends State<NamedSnapshotRestoreDialog> {
  var _acknowledge = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final paths = preview.replacementPaths;
    final muted = context.text.caption.copyWith(color: context.colors.inkMuted);
    void submit() => Navigator.pop(context, true);
    return MeridianDialog(
      width: MeridianLayout.dialogConfirmWidth,
      title: context.l10n.namedSnapshotRestoreTitle(preview.snapshot.name),
      description: context.l10n.namedSnapshotRestoreSummary,
      onSubmit: submit,
      submitDisabled: !_acknowledge,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (paths.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: MeridianSpace.space3,
              children: [
                GitLamaListWell(
                  header: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: MeridianSpace.space6,
                      end: MeridianSpace.space6,
                      top: MeridianSpace.space4,
                    ),
                    child: Text(
                      context.l10n.namedSnapshotRestoreFileCount(paths.length),
                      style: muted,
                    ),
                  ),
                  itemCount: paths.length,
                  itemBuilder: (context, index) => gitLamaPathRow(
                    utf8.decode(paths[index], allowMalformed: true),
                    key: ValueKey('snapshot-restore-path-$index'),
                    leading: MeridianIcon(
                      'file',
                      size: MeridianIconSize.small,
                      color: context.colors.inkMuted,
                    ),
                  ),
                ),
                if (preview.replacementPathsTruncated)
                  Text(context.l10n.namedSnapshotPathsTruncated, style: muted),
              ],
            ),
          Text(context.l10n.namedSnapshotRestoreStash, style: muted),
          MeridianCheckbox(
            label: context.l10n.namedSnapshotAcknowledgeReplacement,
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
          onPressed: () => Navigator.pop(context, false),
        ),
        MeridianButton(
          label: context.l10n.namedSnapshotRestore,
          variant: MeridianButtonVariant.danger,
          onPressed: _acknowledge ? submit : null,
        ),
      ],
    );
  }
}

String _namedSnapshotFailureLabel(
  BuildContext context,
  NamedSnapshotFailureCode code,
) => switch (code) {
  NamedSnapshotFailureCode.nothingToCapture =>
    context.l10n.namedSnapshotNothingToCapture,
  NamedSnapshotFailureCode.missing => context.l10n.namedSnapshotMissing,
  NamedSnapshotFailureCode.corrupt => context.l10n.namedSnapshotCorrupt,
  NamedSnapshotFailureCode.dirtyConflict =>
    context.l10n.namedSnapshotDirtyConflict,
  NamedSnapshotFailureCode.activeOperation =>
    context.l10n.namedSnapshotActiveOperation,
  NamedSnapshotFailureCode.stale => context.l10n.namedSnapshotStale,
  NamedSnapshotFailureCode.conflict => context.l10n.namedSnapshotConflict,
  NamedSnapshotFailureCode.canceled => context.l10n.namedSnapshotCanceled,
  NamedSnapshotFailureCode.tooLarge => context.l10n.namedSnapshotTooLarge,
  NamedSnapshotFailureCode.invalidRequest ||
  NamedSnapshotFailureCode.read ||
  NamedSnapshotFailureCode.write ||
  NamedSnapshotFailureCode.git => context.l10n.namedSnapshotFailed,
};
