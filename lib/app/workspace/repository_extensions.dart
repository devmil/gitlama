import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/status_notification.dart';
import '../../l10n/l10n.dart';
import '../byte_size.dart';
import '../../models/reference_name.dart';
import '../../models/integrations.dart';
import '../../models/repository_state.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_extensions.dart';
import '../../widgets/git_reference_field.dart';
import '../../models/settings.dart';
import '../../services/repository_session_service.dart';
import 'status_bar.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';
import 'reference_projection.dart';
import 'remote_directory_picker.dart';
import 'remote_workspace.dart';

class RepositoryExtensionsPanel extends StatefulWidget {
  const RepositoryExtensionsPanel({
    required this.repositories,
    required this.focusLfsPattern,
    required this.fileBrowserName,
    required this.onOpenFileBrowser,
    required this.onClose,
    super.key,
  });

  final RepositorySessionService repositories;
  final bool focusLfsPattern;
  final String fileBrowserName;
  final ValueChanged<NativePathIdentity> onOpenFileBrowser;
  final VoidCallback onClose;

  @override
  State<RepositoryExtensionsPanel> createState() =>
      _RepositoryExtensionsPanelState();
}

class _RepositoryExtensionsPanelState extends State<RepositoryExtensionsPanel> {
  String? _discoveredFileBrowserName;
  final TextEditingController _worktreePath = TextEditingController();
  final TextEditingController _worktreeReference = TextEditingController(
    text: 'HEAD',
  );
  final TextEditingController _lfsPattern = TextEditingController();
  final FocusNode _lfsPatternFocus = FocusNode(
    debugLabel: 'extension-lfs-pattern',
  );
  RepositoryExtensionInventory? _inventory;
  RepositoryExtensionFailureCode? _failure;
  bool _busy = false;
  late final int _section = widget.focusLfsPattern ? 2 : 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_discoverFileBrowser());
  }

  Future<void> _discoverFileBrowser() async {
    if (widget.fileBrowserName != platformFileBrowserName()) return;
    try {
      final candidates = await widget.repositories.integrations.discover(
        IntegrationKind.fileManager,
      );
      if (mounted && candidates.isNotEmpty) {
        setState(
          () => _discoveredFileBrowserName = discoveredFileBrowser(
            candidates.first.id,
          ),
        );
      }
    } on Object {
      // The action reports availability if discovery fails when invoked.
    }
  }

  @override
  void dispose() {
    _worktreePath.dispose();
    _worktreeReference.dispose();
    _lfsPattern.dispose();
    _lfsPatternFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final inventory = await widget.repositories.extensions.inventory();
      if (mounted) {
        setState(() => _inventory = inventory);
        if (widget.focusLfsPattern && inventory.lfsAvailable) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _lfsPatternFocus.requestFocus();
            final focusContext = _lfsPatternFocus.context;
            if (focusContext == null) return;
            Scrollable.ensureVisible(
              focusContext,
              alignment: 0.45,
              duration: MeridianMotion.of(context, MeridianDurations.layout),
              curve: MeridianDurations.layoutCurve,
            );
          });
        }
      }
    } on RepositoryExtensionException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether the repository's host refuses extension changes; says why.
  bool _refusedByHost() {
    final reason = remoteWriteReason(
      context,
      RemoteCapability.extensions,
      listen: false,
    );
    if (reason == null) return false;
    StatusNotificationScope.show(context, reason);
    return true;
  }

  Future<void> _run(RepositoryExtensionMutationRequest request) async {
    if (_busy || _refusedByHost()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final result = await widget.repositories.extensions.execute(request);
      if (!mounted) return;
      if (result.reportedFailure case final failure?) {
        setState(() => _failure = failure);
      } else {
        if (result.state == RepositoryExtensionMutationState.outcomeUncertain) {
          StatusNotificationScope.show(
            context,
            context.l10n.mutationOutcomeUncertain,
            error: true,
          );
        }
        await _load();
      }
    } on RemoteOutcomeUnknownException {
      if (mounted) showRemoteOutcomeUnknown(context);
    } on RepositoryExtensionException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCreateWorktree() async {
    if (_refusedByHost()) return;
    var pickingDirectory = false;
    var pickerFailed = false;
    final accepted = await showMeridianDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => MeridianDialog(
          width: MeridianLayout.dialogFormWidth,
          scrollable: true,
          title: context.l10n.extensionWorktreeCreate,
          description: context.l10n.extensionWorktreeCreateDescription,
          onSubmit: () => Navigator.pop(context, true),
          submitDisabled: pickingDirectory || _worktreePath.text.trim().isEmpty,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: MeridianSpace.space6,
            children: [
              GitReferenceField(
                controller: _worktreeReference,
                choices:
                    ReferenceProjection.of(
                      widget
                              .repositories
                              .workspace
                              .activeTab
                              ?.session
                              ?.snapshot
                              .refs ??
                          const RepositoryRefs(),
                    ).choices(
                      widget.repositories.history.referencePickerCommitsFor(
                        widget
                            .repositories
                            .workspace
                            .activeTab
                            ?.session
                            ?.identity,
                      ),
                    ),
                helperText: context.l10n.referencePickerHistoryHint,
                label: context.l10n.extensionWorktreeReference,
                names: gitReferenceNames(
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
              // The folder button belongs to the path above it and starts at
              // the fields' leading edge.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: MeridianSpace.space3,
                children: [
                  MeridianTextField(
                    fieldKey: const Key('extension-worktree-path'),
                    controller: _worktreePath,
                    autofocus: true,
                    enabled: !pickingDirectory,
                    onChanged: (_) => update(() => pickerFailed = false),
                    label: context.l10n.extensionWorktreePath,
                    error: pickerFailed
                        ? context.l10n.extensionWorktreeChooseFolderFailure
                        : null,
                  ),
                  MeridianButton(
                    key: const Key('extension-worktree-choose-folder'),
                    label: context.l10n.extensionWorktreeChooseFolder,
                    icon: MeridianIcons.folderOpen,
                    variant: MeridianButtonVariant.quiet,
                    loading: pickingDirectory,
                    onPressed: pickingDirectory
                        ? null
                        : () async {
                            update(() {
                              pickingDirectory = true;
                              pickerFailed = false;
                            });
                            try {
                              final path = await _chooseWorktreeFolder(context);
                              if (!mounted ||
                                  !context.mounted ||
                                  ModalRoute.of(context)?.isCurrent != true) {
                                return;
                              }
                              if (path != null) {
                                _worktreePath.value = TextEditingValue(
                                  text: path,
                                  selection: TextSelection.collapsed(
                                    offset: path.length,
                                  ),
                                );
                              }
                            } on RepositoryExtensionException {
                              if (mounted &&
                                  context.mounted &&
                                  ModalRoute.of(context)?.isCurrent == true) {
                                update(() => pickerFailed = true);
                              }
                            } finally {
                              if (mounted &&
                                  context.mounted &&
                                  ModalRoute.of(context)?.isCurrent == true) {
                                update(() => pickingDirectory = false);
                              }
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            MeridianButton(
              label: context.l10n.cancel,
              variant: MeridianButtonVariant.quiet,
              onPressed: () => Navigator.pop(context, false),
            ),
            MeridianButton(
              label: context.l10n.extensionWorktreeCreate,
              variant: MeridianButtonVariant.primary,
              onPressed: pickingDirectory || _worktreePath.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) await _createWorktree();
  }

  /// A folder on this computer, or on the host for a repository on another
  /// computer; null when the user cancels.
  Future<String?> _chooseWorktreeFolder(BuildContext context) async {
    final authority = _inventory?.worktrees
        .where((entry) => entry.current)
        .firstOrNull
        ?.worktreeRoot
        .remote;
    if (authority == null) {
      return widget.repositories.chooseWorktreeDestination();
    }
    final service = RemoteWorkspaceScope.maybeOf(context)?.service;
    final profile = service?.profile(authority.profileId);
    if (service == null || profile == null) {
      throw const RepositoryExtensionException(
        RepositoryExtensionFailureCode.unavailable,
      );
    }
    final path = await showRemoteDirectoryPicker(
      context,
      service: service,
      profile: profile,
    );
    return path == null ? null : displayRemotePath(path);
  }

  Future<void> _createWorktree() async {
    final inventory = _inventory;
    final path = _worktreePath.text.trim();
    final reference = _worktreeReference.text.trim();
    if (inventory == null || path.isEmpty || reference.isEmpty) return;
    final platform = inventory.worktrees
        .firstWhere((entry) => entry.current)
        .worktreeRoot
        .platform;
    await _run(
      RepositoryExtensionMutationRequest(
        kind: RepositoryExtensionMutationKind.worktreeCreate,
        worktreeRoot: NativePathIdentity(
          platform: platform,
          units: platform == NativePathPlatform.windows
              ? path.codeUnits
              : utf8.encode(path),
        ),
        reference: reference,
      ),
    );
  }

  Future<void> _deleteWorktree(WorktreeEntry entry) async {
    if (_refusedByHost()) return;
    final confirmed = await confirmWorktreeDeletion(context, entry);
    if (!confirmed || !mounted) return;
    await _run(
      RepositoryExtensionMutationRequest(
        kind: RepositoryExtensionMutationKind.worktreeDelete,
        worktreeRoot: entry.worktreeRoot,
      ),
    );
  }

  Future<void> _openWorktree(WorktreeEntry entry) async {
    try {
      await widget.repositories.extensions.openWorktree(entry);
    } on RepositorySessionException {
      // The workspace keeps the failed tab visible with its error.
    }
  }

  Future<void> _enter(SubmoduleEntry entry) async {
    try {
      await widget.repositories.extensions.enterSubmodule(entry);
    } on RepositoryExtensionException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    }
  }

  Future<void> _inspectPointer(LfsEntry entry) async {
    try {
      final pointer = await widget.repositories.extensions.inspectLfsPointer(
        entry,
      );
      if (!mounted) return;
      await showMeridianDialog<void>(
        context: context,
        builder: (context) => MeridianDialog(
          width: MeridianLayout.dialogConfirmWidth,
          onClose: () => Navigator.pop(context),
          title: context.l10n.extensionLfsPointerTitle,
          description: pointer == null
              ? context.l10n.extensionLfsNotPointer
              : context.l10n.extensionLfsPointerDescription,
          content: MeridianPropertyList(
            key: const ValueKey('lfs-pointer-details'),
            properties: [
              MeridianProperty(
                label: context.l10n.extensionLfsPointerFile,
                value: utf8.decode(entry.path, allowMalformed: true),
                monospace: true,
              ),
              if (pointer != null) ...[
                MeridianProperty(
                  label: context.l10n.extensionLfsPointerOid,
                  value: pointer.oidSha256,
                  monospace: true,
                ),
                MeridianProperty(
                  label: context.l10n.extensionLfsPointerSize,
                  value: formatByteSize(context.l10n, pointer.size.toInt()),
                  selectable: false,
                ),
              ],
            ],
          ),
        ),
      );
    } on RepositoryExtensionException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = _inventory;
    return MeridianPanel(
      title: context.l10n.repositoryExtensionsTitle,
      onClose: widget.onClose,
      width: GitLamaLayout.extensionsPanelWidth,
      padding: EdgeInsets.zero,
      actions: [
        MeridianIconButton(
          label: context.l10n.workspaceRefresh,
          icon: 'refresh',
          size: MeridianControlSize.small,
          onPressed: _busy ? null : () => unawaited(_load()),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: GitLamaLayout.extensionsBodyMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const MeridianProgressBar(),
            if (_failure case final failure?)
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space4),
                child: MeridianBanner(
                  tone: MeridianBannerTone.error,
                  message: extensionFailureLabel(context, failure),
                ),
              ),
            Flexible(
              child: inventory == null
                  ? MeridianEmptyState(
                      compact: true,
                      progress: true,
                      title: context.l10n.loading,
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        MeridianSpace.space5,
                        0,
                        MeridianSpace.space5,
                        MeridianSpace.space5,
                      ),
                      children: [
                        MeridianDisclosure(
                          title: context.l10n.extensionWorktrees,
                          initiallyExpanded: _section == 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in inventory.worktrees)
                                MeridianListRow(
                                  title: entry.branch != null
                                      ? ReferenceName(entry.branch!).display
                                      : nativeIdentityLabel(entry.worktreeRoot)
                                                .split(RegExp(r'[/\\]'))
                                                .where(
                                                  (part) => part.isNotEmpty,
                                                )
                                                .lastOrNull ??
                                            nativeIdentityLabel(
                                              entry.worktreeRoot,
                                            ),
                                  subtitle: nativeIdentityLabel(
                                    entry.worktreeRoot,
                                  ),
                                  trailing: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: MeridianSpace.space2,
                                    children: [
                                      MeridianCount(
                                        label: entry.locked
                                            ? context
                                                  .l10n
                                                  .extensionWorktreeLocked
                                            : entry.current
                                            ? context
                                                  .l10n
                                                  .extensionWorktreeCurrent
                                            : entry.head?.substring(0, 8) ??
                                                  context.l10n.detachedHead,
                                      ),
                                      MeridianButton(
                                        label: context.l10n.extensionOpen,
                                        variant: MeridianButtonVariant.quiet,
                                        size: MeridianControlSize.small,
                                        onPressed: entry.current || _busy
                                            ? null
                                            : () => unawaited(
                                                _openWorktree(entry),
                                              ),
                                      ),
                                      MeridianButton(
                                        label: context.l10n.openInFileBrowser(
                                          _discoveredFileBrowserName ??
                                              widget.fileBrowserName,
                                        ),
                                        variant: MeridianButtonVariant.quiet,
                                        size: MeridianControlSize.small,
                                        onPressed: _busy
                                            ? null
                                            : () => widget.onOpenFileBrowser(
                                                entry.worktreeRoot,
                                              ),
                                      ),
                                      MeridianButton(
                                        label: context.l10n.delete,
                                        variant:
                                            MeridianButtonVariant.dangerQuiet,
                                        size: MeridianControlSize.small,
                                        onPressed:
                                            worktreeDeletionProtected(
                                                  inventory,
                                                  entry,
                                                ) ||
                                                _busy
                                            ? null
                                            : () => unawaited(
                                                _deleteWorktree(entry),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: MeridianSpace.space6),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: MeridianButton(
                                  label: context.l10n.extensionWorktreeCreate,
                                  icon: 'plus',
                                  variant: MeridianButtonVariant.primary,
                                  onPressed: _busy
                                      ? null
                                      : () => unawaited(_showCreateWorktree()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        MeridianDisclosure(
                          title: context.l10n.extensionSubmodules,
                          initiallyExpanded: _section == 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (inventory.submodules.isEmpty)
                                MeridianListRow(
                                  title: context.l10n.extensionNone,
                                ),
                              for (final entry in inventory.submodules)
                                MeridianListRow(
                                  title: utf8.decode(
                                    entry.path,
                                    allowMalformed: true,
                                  ),
                                  trailing: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: MeridianSpace.space2,
                                    children: [
                                      MeridianCount(
                                        label: _submoduleStateLabel(
                                          context,
                                          entry.state,
                                        ),
                                      ),
                                      MeridianButton(
                                        label:
                                            entry.state ==
                                                SubmoduleState.uninitialized
                                            ? context.l10n.extensionInitialize
                                            : context.l10n.extensionUpdate,
                                        variant: MeridianButtonVariant.quiet,
                                        size: MeridianControlSize.small,
                                        onPressed: _busy
                                            ? null
                                            : () => unawaited(
                                                _run(
                                                  RepositoryExtensionMutationRequest(
                                                    kind:
                                                        entry.state ==
                                                            SubmoduleState
                                                                .uninitialized
                                                        ? RepositoryExtensionMutationKind
                                                              .submoduleInit
                                                        : RepositoryExtensionMutationKind
                                                              .submoduleUpdate,
                                                    path: entry.path,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      MeridianButton(
                                        label: context.l10n.extensionOpen,
                                        variant: MeridianButtonVariant.quiet,
                                        size: MeridianControlSize.small,
                                        onPressed:
                                            _busy ||
                                                entry.state ==
                                                    SubmoduleState.uninitialized
                                            ? null
                                            : () => unawaited(_enter(entry)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        MeridianDisclosure(
                          title: context.l10n.extensionLfs,
                          initiallyExpanded: _section == 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Spacer(),
                                  MeridianButton(
                                    label: context.l10n.extensionLfsPull,
                                    variant: MeridianButtonVariant.quiet,
                                    onPressed: inventory.lfsAvailable && !_busy
                                        ? () => unawaited(
                                            _run(
                                              const RepositoryExtensionMutationRequest(
                                                kind:
                                                    RepositoryExtensionMutationKind
                                                        .lfsPull,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                              if (!inventory.lfsAvailable)
                                MeridianListRow(
                                  title: context.l10n.extensionLfsUnavailable,
                                ),
                              if (inventory.lfsAvailable)
                                Row(
                                  children: [
                                    Expanded(
                                      child: MeridianTextField(
                                        fieldKey: const Key(
                                          'extension-lfs-pattern',
                                        ),
                                        controller: _lfsPattern,
                                        focusNode: _lfsPatternFocus,
                                        enabled: !_busy,
                                        label: context.l10n.extensionLfsPattern,
                                      ),
                                    ),
                                    MeridianButton(
                                      label: context.l10n.extensionLfsTrack,
                                      variant: MeridianButtonVariant.quiet,
                                      onPressed: _busy
                                          ? null
                                          : () => unawaited(
                                              _run(
                                                RepositoryExtensionMutationRequest(
                                                  kind:
                                                      RepositoryExtensionMutationKind
                                                          .lfsTrack,
                                                  pattern: _lfsPattern.text
                                                      .trim(),
                                                ),
                                              ),
                                            ),
                                    ),
                                    MeridianButton(
                                      label: context.l10n.extensionLfsUntrack,
                                      variant: MeridianButtonVariant.quiet,
                                      onPressed: _busy
                                          ? null
                                          : () => unawaited(
                                              _run(
                                                RepositoryExtensionMutationRequest(
                                                  kind:
                                                      RepositoryExtensionMutationKind
                                                          .lfsUntrack,
                                                  pattern: _lfsPattern.text
                                                      .trim(),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              for (final entry in inventory.lfsEntries)
                                MeridianListRow(
                                  title: utf8.decode(
                                    entry.path,
                                    allowMalformed: true,
                                  ),
                                  trailing: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: MeridianSpace.space2,
                                    children: [
                                      MeridianCount(
                                        label: _lfsStateLabel(
                                          context,
                                          entry.state,
                                        ),
                                      ),
                                      MeridianButton(
                                        label: context
                                            .l10n
                                            .extensionInspectPointer,
                                        variant: MeridianButtonVariant.quiet,
                                        size: MeridianControlSize.small,
                                        onPressed: _busy
                                            ? null
                                            : () => unawaited(
                                                _inspectPointer(entry),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String nativeIdentityLabel(NativePathIdentity identity) =>
    switch (identity.platform) {
      NativePathPlatform.unix => utf8.decode(
        identity.units.map((value) => value & 0xff).toList(growable: false),
        allowMalformed: true,
      ),
      NativePathPlatform.windows => String.fromCharCodes(identity.units),
    };

/// Asks before a linked worktree and its files are removed.
Future<bool> confirmWorktreeDeletion(
  BuildContext context,
  WorktreeEntry entry,
) => showMeridianConfirm(
  context,
  title: context.l10n.extensionWorktreeDeleteTitle,
  description: context.l10n.extensionWorktreeDeleteBody(
    nativeIdentityLabel(entry.worktreeRoot),
  ),
  confirmLabel: context.l10n.delete,
  cancelLabel: context.l10n.cancel,
  destructive: true,
);

bool worktreeDeletionProtected(
  RepositoryExtensionInventory inventory,
  WorktreeEntry entry,
) =>
    entry.current ||
    entry.locked ||
    inventory.worktrees.length == 1 ||
    entry.gitDir == entry.commonGitDir;

String _submoduleStateLabel(
  BuildContext context,
  SubmoduleState state,
) => switch (state) {
  SubmoduleState.atRecordedCommit => context.l10n.extensionSubmoduleRecorded,
  SubmoduleState.differentCommit => context.l10n.extensionSubmoduleDifferent,
  SubmoduleState.uninitialized => context.l10n.extensionSubmoduleUninitialized,
  SubmoduleState.conflicted => context.l10n.extensionSubmoduleConflicted,
};

String _lfsStateLabel(BuildContext context, LfsPathState state) =>
    switch (state) {
      LfsPathState.pointer => context.l10n.extensionLfsStatePointer,
      LfsPathState.materialized => context.l10n.extensionLfsStateMaterialized,
      LfsPathState.missing => context.l10n.extensionLfsStateMissing,
    };

String extensionFailureLabel(
  BuildContext context,
  RepositoryExtensionFailureCode failure,
) => switch (failure) {
  RepositoryExtensionFailureCode.invalidRequest =>
    context.l10n.extensionFailureInvalid,
  RepositoryExtensionFailureCode.unavailable =>
    context.l10n.extensionFailureUnavailable,
  RepositoryExtensionFailureCode.dirty => context.l10n.extensionFailureDirty,
  RepositoryExtensionFailureCode.locked => context.l10n.extensionFailureLocked,
  RepositoryExtensionFailureCode.currentWorktree =>
    context.l10n.extensionFailureCurrent,
  RepositoryExtensionFailureCode.stale => context.l10n.extensionFailureStale,
  RepositoryExtensionFailureCode.canceled =>
    context.l10n.extensionFailureCanceled,
  RepositoryExtensionFailureCode.tooLarge =>
    context.l10n.extensionFailureTooLarge,
  RepositoryExtensionFailureCode.read ||
  RepositoryExtensionFailureCode.git => context.l10n.extensionFailureGit,
};
