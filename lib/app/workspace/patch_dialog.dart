import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/command_preview.dart';
import '../../widgets/gitlama_list_well.dart';
import '../../widgets/status_notification.dart';
import '../../l10n/l10n.dart';
import '../byte_size.dart';
import '../../models/patch.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../services/repository_session_service.dart';
import '../app_theme.dart';
import 'package:meridian_ui/meridian_ui.dart';

Future<void> showPatchDialog(
  BuildContext context, {
  required RepositorySessionService repositories,
  required String repositoryLabel,
  required ValueChanged<NativePathIdentity> onShowInFolder,
  required PatchRequestFactory request,
  PatchDialogMode? initialMode,
  String? applyUnavailableReason,
}) => showMeridianDialog<void>(
  context: context,
  builder: (context) => _PatchDialog(
    repositories: repositories,
    repositoryLabel: repositoryLabel,
    onShowInFolder: onShowInFolder,
    request: request,
    initialMode: initialMode,
    applyUnavailableReason: applyUnavailableReason,
  ),
);

enum PatchDialogMode { create, apply }

class _PatchDialog extends StatefulWidget {
  const _PatchDialog({
    required this.repositories,
    required this.repositoryLabel,
    required this.onShowInFolder,
    required this.request,
    this.initialMode,
    this.applyUnavailableReason,
  });

  final RepositorySessionService repositories;
  final String repositoryLabel;
  final ValueChanged<NativePathIdentity> onShowInFolder;
  final PatchRequestFactory request;
  final PatchDialogMode? initialMode;

  /// Why patches cannot be applied here; Apply then explains it instead.
  final String? applyUnavailableReason;

  @override
  State<_PatchDialog> createState() => _PatchDialogState();
}

class _PatchDialogState extends State<_PatchDialog> {
  late PatchDialogMode _mode;
  var _busy = false;
  var _failed = false;
  String? _destinationDirectory;
  String? _patchPath;
  PatchExportPreview? _export;
  PatchApplyPreview? _apply;
  String? _completion;
  var _completionTone = MeridianBannerTone.success;
  String? _completedPath;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? PatchDialogMode.create;
  }

  Future<void> _chooseDestination() async {
    final destination = await widget.repositories.choosePatchDestination();
    if (destination == null || !mounted) return;
    _destinationDirectory = destination;
    await _previewExport(overwrite: false);
  }

  Future<void> _previewExport({required bool overwrite}) async {
    final destination = _destinationDirectory;
    if (destination == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _completion = null;
      _completedPath = null;
    });
    try {
      final preview = await widget.repositories.patches.previewExport(
        widget.request(destination, overwrite),
      );
      if (mounted) setState(() => _export = preview);
    } on RepositorySessionException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writePatch() async {
    final preview = _export;
    if (preview?.token == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await widget.repositories.patches.executeExport(preview!);
      if (!mounted) return;
      setState(() {
        _completion = switch (result.state) {
          PatchExportExecutionState.completed => context.l10n.patchExportDone,
          PatchExportExecutionState.stale => context.l10n.patchExportStale,
          PatchExportExecutionState.failed => context.l10n.patchExportFailed,
        };
        _failed = result.state != PatchExportExecutionState.completed;
        _completionTone = _failed
            ? MeridianBannerTone.error
            : MeridianBannerTone.success;
        _completedPath = result.state == PatchExportExecutionState.completed
            ? result.destination ?? preview.destination
            : null;
        _export = null;
      });
    } on RepositorySessionException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePatchFile() async {
    final path = await widget.repositories.choosePatchFile();
    if (path == null || !mounted) return;
    setState(() {
      _patchPath = path;
      _busy = true;
      _failed = false;
      _apply = null;
      _completion = null;
    });
    try {
      final preview = await widget.repositories.patches.previewApply(path);
      if (mounted) setState(() => _apply = preview);
    } on RepositorySessionException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyPatch() async {
    final preview = _apply;
    if (preview == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await widget.repositories.patches.executeApply(preview);
      if (!mounted) return;
      setState(() {
        _completion = switch (result.state) {
          PatchApplyExecutionState.completed => context.l10n.patchApplyDone,
          PatchApplyExecutionState.stale => context.l10n.patchApplyStale,
          PatchApplyExecutionState.failed => context.l10n.patchApplyFailed,
          PatchApplyExecutionState.reconciledWithWarning =>
            context.l10n.patchApplyWarning,
          PatchApplyExecutionState.outcomeUncertain =>
            context.l10n.patchApplyOutcomeUncertain,
        };
        _failed =
            result.state == PatchApplyExecutionState.failed ||
            result.state == PatchApplyExecutionState.stale ||
            result.state == PatchApplyExecutionState.outcomeUncertain;
        _completionTone = _failed
            ? MeridianBannerTone.error
            : result.state == PatchApplyExecutionState.reconciledWithWarning
            ? MeridianBannerTone.warning
            : MeridianBannerTone.success;
        _apply = null;
      });
    } on RemoteOutcomeUnknownException {
      if (mounted) showRemoteOutcomeUnknown(context);
    } on RepositorySessionException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final create = _mode == PatchDialogMode.create;
    final VoidCallback? primary = create
        ? (_export?.token == null || _busy ? null : _writePatch)
        : (_apply == null || _busy || widget.applyUnavailableReason != null
              ? null
              : _applyPatch);
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      scrollable: true,
      title: context.l10n.patchTitle,
      description: create
          ? context.l10n.patchCreateDescription
          : context.l10n.patchApplyDescription,
      onSubmit: primary,
      submitDisabled: primary == null,
      content: Column(
        key: const ValueKey('patch-dialog-content'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          // The mode switch hugs its two choices at the leading edge, as
          // segmented controls do elsewhere in the app.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MeridianSegmented<PatchDialogMode>(
              label: context.l10n.patchTitle,
              segments: [
                for (final value in PatchDialogMode.values)
                  MeridianSegment(
                    value: value,
                    label: value == PatchDialogMode.create
                        ? context.l10n.patchCreate
                        : context.l10n.patchApply,
                  ),
              ],
              value: _mode,
              onChanged: _busy
                  ? (_) {}
                  : (value) => setState(() {
                      _mode = value;
                      _failed = false;
                      _completion = null;
                      _completedPath = null;
                    }),
            ),
          ),
          if (_completion case final message?)
            _completionView(context, message)
          else if (create)
            _buildCreate(context)
          else
            _buildApply(context),
          if (_busy) const MeridianProgressBar(),
          if (_failed && _completion == null)
            MeridianBanner(
              tone: MeridianBannerTone.error,
              message: create
                  ? context.l10n.patchExportFailed
                  : context.l10n.patchApplyFailed,
            ),
        ],
      ),
      actions: [
        MeridianButton(
          variant: MeridianButtonVariant.quiet,
          onPressed: _busy ? null : () => Navigator.pop(context),
          label: context.l10n.close,
        ),
        MeridianButton(
          variant: MeridianButtonVariant.primary,
          label: create ? context.l10n.patchWrite : context.l10n.patchApply,
          onPressed: primary,
          disabledReason: create ? null : widget.applyUnavailableReason,
        ),
      ],
    );
  }

  /// What a finished write or apply did, with the written file when there
  /// is one, then the way to start again.
  Widget _completionView(BuildContext context, String message) {
    final path = _completedPath;
    final create = _mode == PatchDialogMode.create;
    return Column(
      key: const ValueKey('patch-completion'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        MeridianBanner(
          tone: _completionTone,
          message: message,
          actions: [
            if (path != null)
              MeridianButton(
                label: context.l10n.patchShowInFolder,
                variant: MeridianButtonVariant.secondary,
                size: MeridianControlSize.small,
                icon: 'folder-open',
                onPressed: () => widget.onShowInFolder(
                  NativePathIdentity(
                    platform: defaultTargetPlatform == TargetPlatform.windows
                        ? NativePathPlatform.windows
                        : NativePathPlatform.unix,
                    units: defaultTargetPlatform == TargetPlatform.windows
                        ? path.codeUnits
                        : utf8.encode(path),
                  ),
                ),
              ),
          ],
        ),
        if (path != null)
          MeridianPropertyList(
            properties: [
              MeridianProperty(
                label: context.l10n.patchSavedTo,
                value: path,
                monospace: true,
              ),
            ],
          ),
        _chooseButton(
          context,
          label: create
              ? context.l10n.patchChooseDestination
              : context.l10n.patchChooseFile,
          onPressed: create ? _chooseDestination : _choosePatchFile,
        ),
      ],
    );
  }

  /// The secondary action that picks a folder or a patch file, at the
  /// content's leading edge.
  Widget _chooseButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: MeridianButton(
      variant: MeridianButtonVariant.secondary,
      icon: 'folder-open',
      onPressed: _busy ? null : onPressed,
      label: label,
    ),
  );

  Widget _buildCreate(BuildContext context) {
    final preview = _export;
    final muted = context.text.caption.copyWith(color: context.colors.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        if (preview == null)
          Text(context.l10n.patchDestinationUnset, style: muted)
        else
          MeridianPropertyList(
            key: const ValueKey('patch-export-facts'),
            properties: [
              MeridianProperty(
                label: context.l10n.patchScope,
                value: _patchScopeLabel(context, preview.scope),
                selectable: false,
              ),
              MeridianProperty(
                label: context.l10n.patchFormat,
                value: preview.format == PatchFormat.unifiedDiff
                    ? context.l10n.patchFormatUnified
                    : context.l10n.patchFormatEmail,
                selectable: false,
              ),
              MeridianProperty(
                label: context.l10n.patchFilename,
                value: preview.filename,
                monospace: true,
              ),
              if (_destinationDirectory case final folder?)
                MeridianProperty(
                  label: context.l10n.patchDestination,
                  value: folder,
                  monospace: true,
                ),
              MeridianProperty(
                label: context.l10n.patchSize,
                value: formatByteSize(context.l10n, preview.byteCount),
                selectable: false,
              ),
            ],
          ),
        if (preview != null && preview.requiresOverwrite)
          MeridianBanner(
            tone: MeridianBannerTone.warning,
            message: context.l10n.patchOverwriteWarning,
          ),
        if (preview?.requiresOverwrite == true)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MeridianButton(
              key: const ValueKey('patch-overwrite'),
              variant: MeridianButtonVariant.secondary,
              onPressed: _busy ? null : () => _previewExport(overwrite: true),
              label: context.l10n.patchOverwrite,
            ),
          )
        else
          _chooseButton(
            context,
            label: context.l10n.patchChooseDestination,
            onPressed: _chooseDestination,
          ),
      ],
    );
  }

  Widget _buildApply(BuildContext context) {
    if (widget.applyUnavailableReason case final reason?) {
      return MeridianBanner(
        key: const ValueKey('patch-apply-unavailable'),
        tone: MeridianBannerTone.info,
        message: reason,
      );
    }
    final preview = _apply;
    final muted = context.text.caption.copyWith(color: context.colors.inkMuted);
    final paths = [
      for (final path in preview?.paths ?? const <List<int>>[])
        utf8.decode(path, allowMalformed: true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        if (_patchPath case final file?)
          MeridianPropertyList(
            key: const ValueKey('patch-apply-facts'),
            properties: [
              MeridianProperty(
                label: context.l10n.patchFile,
                value: file,
                monospace: true,
              ),
              MeridianProperty(
                label: context.l10n.patchTarget,
                value: widget.repositoryLabel,
              ),
              if (preview != null) ...[
                MeridianProperty(
                  label: context.l10n.patchCheck,
                  value: context.l10n.patchCheckPassed,
                  selectable: false,
                ),
                MeridianProperty(
                  label: context.l10n.patchBinary,
                  value: preview.binary
                      ? context.l10n.patchYes
                      : context.l10n.patchNo,
                  selectable: false,
                ),
              ],
            ],
          )
        else
          Text(context.l10n.patchFileUnset, style: muted),
        _chooseButton(
          context,
          label: context.l10n.patchChooseFile,
          onPressed: _choosePatchFile,
        ),
        if (paths.isNotEmpty)
          GitLamaListWell(
            key: const ValueKey('patch-apply-files'),
            header: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: MeridianSpace.space6,
                end: MeridianSpace.space6,
                top: MeridianSpace.space4,
              ),
              child: Text(
                context.l10n.patchFileCount(paths.length),
                style: muted,
              ),
            ),
            itemCount: paths.length,
            itemBuilder: (context, index) => gitLamaPathRow(
              paths[index],
              key: ValueKey('patch-apply-path-$index'),
              leading: MeridianIcon(
                'file',
                size: MeridianIconSize.small,
                color: context.colors.inkMuted,
              ),
            ),
          ),
        if (preview != null)
          GitCommandDetails(commands: ['git ${preview.arguments.join(' ')}']),
      ],
    );
  }
}

String _patchScopeLabel(BuildContext context, PatchExportScope scope) =>
    switch (scope) {
      PatchExportScope.lines => context.l10n.patchScopeLines,
      PatchExportScope.selectedFilesUnstaged =>
        context.l10n.patchScopeSelectedUnstaged,
      PatchExportScope.selectedFilesStaged =>
        context.l10n.patchScopeSelectedStaged,
      PatchExportScope.unstaged => context.l10n.patchScopeUnstaged,
      PatchExportScope.staged => context.l10n.patchScopeStaged,
      PatchExportScope.head => context.l10n.patchScopeHead,
      PatchExportScope.commit => context.l10n.patchScopeCommit,
      PatchExportScope.range => context.l10n.patchScopeRange,
      PatchExportScope.compare => context.l10n.patchScopeCompare,
    };
