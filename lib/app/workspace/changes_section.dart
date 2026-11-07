import '../../widgets/status_notification.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/diff.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/diff_line_selection.dart';
import '../../widgets/gitlama_file_row.dart';
import '../app_theme.dart';
import '../../widgets/git_file_list/git_file_list.dart';
import '../file_actions/file_actions.dart';
import '../../models/inspector.dart';
import 'status_bar.dart';

import 'package:meridian_ui/meridian_ui.dart';

import 'shell_scopes.dart';
import '../gitlama_layout.dart';
import '../../models/discard.dart';
import '../../models/working_tree.dart';
export '../../models/working_tree.dart'
    show changeKey, uniqueCommandPaths, diffPaths;

class ChangesSection extends StatefulWidget {
  const ChangesSection({
    super.key,
    required this.title,
    required this.side,
    required this.stacked,
    required this.mode,
    required this.onModeChanged,
    required this.entries,
    this.commitSequence = 0,
    this.mutationSequence = 0,
    this.mutationSource,
    this.movingKeys = const {},
    this.flightKey,
    required this.controller,
    required this.selected,
    required this.busy,
    this.canQueueStage = false,
    this.allowSelectionWhileBusy = false,
    this.pendingKeys = const {},
    required this.onSelectIdentity,
    required this.onSelectionChanged,
    required this.onSelected,
    required this.onAll,
    required this.onFiles,
    required this.onPartial,
    required this.onCreatePatch,
    required this.fileBrowserName,
    this.inspectionUnavailableReason,
    required this.onDropFiles,
    required this.onDiscardSelected,
    required this.onDiscardFiles,
    required this.onDiscardAll,
    this.onIgnore,
    this.totalEntries,
    this.stageDisabledReason,
    this.patchDisabledReason,
    this.externalDisabledReason,
    this.discardDisabledReason,
    this.ignoreDisabledReason,
  });

  final String title;
  final StagingSide side;
  final bool stacked;
  final GitFileListMode mode;
  final ValueChanged<GitFileListMode> onModeChanged;
  final List<RepositoryStatusEntry> entries;
  final int commitSequence;
  final int mutationSequence;
  final StagingSide? mutationSource;
  final Set<String> movingKeys;
  final String? flightKey;
  final ScrollController controller;
  final Set<String> selected;
  final bool busy;
  final bool canQueueStage;
  final bool allowSelectionWhileBusy;
  final Set<String> pendingKeys;
  final ValueChanged<String> onSelectIdentity;
  final ValueChanged<Set<String>> onSelectionChanged;
  final VoidCallback onSelected;
  final VoidCallback onAll;
  final ValueChanged<List<RepositoryStatusEntry>> onFiles;
  final ValueChanged<RepositoryStatusEntry> onPartial;
  final ValueChanged<List<RepositoryStatusEntry>> onCreatePatch;
  final String fileBrowserName;

  /// Moves files dropped from the other section to this one.
  final ValueChanged<List<RepositoryStatusEntry>> onDropFiles;
  final VoidCallback? onDiscardSelected;
  final ValueChanged<List<RepositoryStatusEntry>>? onDiscardFiles;

  /// Why inspection at the current commit is unavailable, or null.
  final String? inspectionUnavailableReason;
  final VoidCallback? onDiscardAll;

  /// Offers a `.gitignore` entry for a path of this list: [directory] for a
  /// folder, [tracked] when Git already tracks some of it.
  final void Function(
    List<int> path, {
    required bool directory,
    required bool tracked,
  })?
  onIgnore;

  /// Every changed file of this side while a filter shows only [entries];
  /// `null` without a filter. The bulk actions then act on the shown files.
  final int? totalEntries;

  /// Why staging and unstaging are unavailable (for a repository on
  /// another computer), or null when they are offered.
  final String? stageDisabledReason;

  /// Why patches cannot be created here, or null.
  final String? patchDisabledReason;

  /// Why files cannot be opened in local tools, or null.
  final String? externalDisabledReason;

  /// Why Discard and Clean are unavailable; they stay visible, disabled.
  final String? discardDisabledReason;

  /// Why Add to .gitignore is unavailable; it stays visible, disabled.
  final String? ignoreDisabledReason;

  bool get _stageBlocked =>
      (busy && !canQueueStage) || stageDisabledReason != null;

  @override
  State<ChangesSection> createState() => ChangesSectionState();
}

class ChangesSectionState extends State<ChangesSection> {
  int _allFailures = 0;
  int _selectedFailures = 0;

  void showActionFailure(StagingScope scope) {
    if (!mounted) return;
    setState(() {
      if (scope == StagingScope.all) {
        _allFailures++;
      } else {
        _selectedFailures++;
      }
    });
  }

  final Set<String> _collapsedDirectories = {};
  final List<(int, _ChangesFileRow)> _exitingRows = [];
  final Set<String> _arrivingKeys = {};
  final Map<String, GlobalKey> _travelKeys = {};
  int? _pendingCommitSequence;
  Set<String>? _pendingRemovalKeys;

  bool willShowEntry(RepositoryStatusEntry entry) {
    final simulated = [...widget.entries];
    if (!simulated.any((item) => changeKey(item) == changeKey(entry))) {
      simulated.add(entry);
    }
    simulated.sort(
      (a, b) => displayNativePath(a.path).compareTo(displayNativePath(b.path)),
    );
    final rows = widget.mode == GitFileListMode.list
        ? [
            for (final item in simulated)
              _ChangesFileRow(
                entry: item,
                depth: 0,
                label: _changesFileLabel(item, basename: false),
              ),
          ]
        : _changesTreeRows(simulated, _collapsedDirectories);
    final index = rows.indexWhere(
      (row) => row.entry != null && changeKey(row.entry!) == changeKey(entry),
    );
    if (index < 0) return false;
    final extent = context.meridian.density.rowExtent;
    final top = widget.controller.hasClients ? widget.controller.offset : 0.0;
    final bottom = widget.controller.hasClients
        ? top + widget.controller.position.viewportDimension
        : (context.size?.height ?? 0) - MeridianSize.islandHeader;
    return index * extent < bottom && (index + 1) * extent > top;
  }

  bool captureEntry(RepositoryStatusEntry entry) {
    final key = _travelKeys[changeKey(entry)];
    final context = key?.currentContext;
    if (context == null) return false;
    MeridianTravel.capture(context, ('file', changeKey(entry)));
    return true;
  }

  GlobalKey _travelKey(RepositoryStatusEntry entry) {
    if (_travelKeys.length > 512) {
      _travelKeys.removeWhere((_, key) => key.currentContext == null);
    }
    return _travelKeys.putIfAbsent(changeKey(entry), GlobalKey.new);
  }

  int? _selectionAnchor;

  @override
  void didUpdateWidget(covariant ChangesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commitSequence != oldWidget.commitSequence &&
        widget.side == StagingSide.staged) {
      _pendingCommitSequence = widget.commitSequence;
      _exitingRows.clear();
    }
    if (widget.mutationSequence != oldWidget.mutationSequence) {
      _pendingRemovalKeys =
          widget.mutationSource == widget.side && widget.movingKeys.isNotEmpty
          ? widget.movingKeys
          : null;
      _arrivingKeys.clear();
      _exitingRows.clear();
    }
    if (_pendingCommitSequence != null || _pendingRemovalKeys != null) {
      final current = widget.entries.map(changeKey).toSet();
      final oldRows = oldWidget.mode == GitFileListMode.list
          ? [
              for (final entry in oldWidget.entries)
                _ChangesFileRow(
                  entry: entry,
                  depth: 0,
                  label: _changesFileLabel(entry, basename: false),
                ),
            ]
          : _changesTreeRows(oldWidget.entries, _collapsedDirectories);
      final top = widget.controller.hasClients
          ? widget.controller.offset / context.meridian.density.rowExtent
          : 0.0;
      final visible = widget.controller.hasClients
          ? widget.controller.position.viewportDimension /
                context.meridian.density.rowExtent
          : 20.0;
      for (var i = 0; i < oldRows.length; i++) {
        final row = oldRows[i];
        if (row.entry case final entry?
            when !current.contains(changeKey(entry)) &&
                (_pendingCommitSequence != null ||
                    _pendingRemovalKeys?.contains(changeKey(entry)) == true) &&
                i >= top - 1 &&
                i <= top + visible + 1) {
          _exitingRows.add((i, row));
        }
      }
      if (_exitingRows.isNotEmpty) {
        _pendingCommitSequence = null;
        _pendingRemovalKeys = null;
      }
    }
    if (widget.mutationSource != widget.side && widget.movingKeys.isNotEmpty) {
      final oldKeys = oldWidget.entries.map(changeKey).toSet();
      for (final entry in widget.entries) {
        final key = changeKey(entry);
        if (!oldKeys.contains(key) && widget.movingKeys.contains(key)) {
          _arrivingKeys.add(key);
        }
      }
    }
    if ((_selectionAnchor ?? -1) >= widget.entries.length) {
      _selectionAnchor = null;
    }
  }

  late final _ChangesActionHost _actionHost = _ChangesActionHost(this);

  FileActionSubject _fileSubject(RepositoryStatusEntry entry, bool stage) =>
      FileActionSubject(
        source: stage
            ? FileActionSource.unstagedFile
            : FileActionSource.stagedFile,
        path: repositoryPathBytes(entry.path),
        statusKind: entry.kind,
        existsInWorkingTree: true,
        staged: !stage,
        discardable: discardable(entry),
        untracked: entry.kind == StatusEntryKind.untracked,
      );

  /// Actions on the selected files come first under their own title, then
  /// the actions on the file under the pointer, so each entry names what it
  /// changes.
  List<NativeMenuAction> _fileMenu(RepositoryStatusEntry entry, bool stage) {
    final selection = widget.selected.contains(changeKey(entry))
        ? widget.entries
              .where((value) => widget.selected.contains(changeKey(value)))
              .toList(growable: false)
        : const <RepositoryStatusEntry>[];
    final subject = _fileSubject(entry, stage);
    return nativeMenuActions<FileActionCommand>(
      buildFileActionItems(
        context,
        subject,
        _actionHost,
        selection: selection.length >= 2
            ? FileActionSelection(
                count: selection.length,
                staged: !stage,
                discardKind: discardKindOf(selection),
              )
            : null,
        busy: widget.busy,
        allowStagingWhileBusy: widget.canQueueStage,
      ),
      (command) => _runFileAction(
        command,
        entries: command.selection ? selection : [entry],
        target: entry.path,
        subject: subject,
      ),
    );
  }

  void _runFileAction(
    FileActionCommand command, {
    required List<RepositoryStatusEntry> entries,
    required NativePathIdentity target,
    required FileActionSubject subject,
    String? copiedPath,
  }) {
    switch (command.action) {
      case FileAction.stage || FileAction.unstage:
        widget.onFiles(entries);
      case FileAction.inspectChanges:
        widget.onPartial(entries.single);
      case FileAction.createPatch:
        widget.onCreatePatch(entries);
      case FileAction.copyPath:
        unawaited(_copyPath(copiedPath ?? displayNativePath(target)));
      case FileAction.openExternally:
        Future<void>.delayed(Duration.zero, () {
          if (mounted) FileActionsScope.maybeOf(context)?.openExternal(target);
        });
      case FileAction.revealInFileBrowser:
        Future<void>.delayed(Duration.zero, () {
          if (mounted) {
            FileActionsScope.maybeOf(context)?.revealInFileBrowser(target);
          }
        });
      case FileAction.discard || FileAction.clean:
        widget.onDiscardFiles?.call(entries);
      case FileAction.addToGitignore:
        widget.onIgnore?.call(
          subject.path,
          directory: subject.isFolder,
          tracked: entries.any(
            (entry) => entry.kind != StatusEntryKind.untracked,
          ),
        );
      case FileAction.blame:
        FileActionsScope.maybeOf(context)?.inspectWorkingFile?.call(
          subject.path,
          InspectorLens.blame,
          directory: false,
          invert: inspectionModifierPressed(),
        );
      case FileAction.fileHistory || FileAction.folderHistory:
        FileActionsScope.maybeOf(context)?.inspectWorkingFile?.call(
          subject.path,
          InspectorLens.history,
          directory: subject.isFolder,
          invert: inspectionModifierPressed(),
        );
      case FileAction.showDiff ||
          FileAction.showContents ||
          FileAction.openInNewWindow ||
          FileAction.externalDiff ||
          FileAction.restoreFromCommit:
        break;
    }
  }

  Future<void> _copyPath(String path) =>
      copyPathWithNotification(context, path);

  List<NativeMenuAction> _directoryMenu(_ChangesFileRow row, bool stage) {
    final discard = discardKindOf(row.entries);
    final subject = FileActionSubject(
      source: FileActionSource.changesFolder,
      path: utf8.encode(row.identity),
      existsInWorkingTree: row.entries.isNotEmpty,
      staged: !stage,
      discardable: discard != null,
      untracked: discard == DiscardKind.clean,
    );
    final target = row.entries.isEmpty
        ? null
        : directoryNativePath(row.entries.first.path, row.identity);
    return nativeMenuActions<FileActionCommand>(
      buildFileActionItems(
        context,
        subject,
        _actionHost,
        busy: widget.busy,
        allowStagingWhileBusy: widget.canQueueStage,
      ),
      (command) {
        if (target == null &&
            command.action == FileAction.revealInFileBrowser) {
          return;
        }
        _runFileAction(
          command,
          entries: row.entries,
          target: target ?? row.entries.first.path,
          subject: subject,
          copiedPath: row.identity,
        );
      },
    );
  }

  void _selectEntry(RepositoryStatusEntry entry) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final toggle =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final extend =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final index = widget.entries.indexOf(entry);
    final next = <String>{};
    if (extend && _selectionAnchor != null && widget.entries.isNotEmpty) {
      next.addAll(widget.selected);
      final start = math.min(_selectionAnchor!, index);
      final end = math.max(_selectionAnchor!, index);
      for (var cursor = start; cursor <= end; cursor += 1) {
        next.add(changeKey(widget.entries[cursor]));
      }
    } else if (toggle) {
      next.addAll(widget.selected);
      final key = changeKey(entry);
      if (!next.remove(key)) next.add(key);
      _selectionAnchor = index;
    } else {
      next.add(changeKey(entry));
      _selectionAnchor = index;
    }
    widget.onSelectionChanged(next);
    widget.onSelectIdentity(displayNativePath(entry.path));
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.side == StagingSide.unstaged;
    final filtered = widget.totalEntries != null;
    final allLabel = switch ((stage, filtered)) {
      (true, false) => context.l10n.stageAll,
      (true, true) => context.l10n.stageShown,
      (false, false) => context.l10n.unstageAll,
      (false, true) => context.l10n.unstageShown,
    };
    final selectedEntries = widget.entries
        .where((entry) => widget.selected.contains(changeKey(entry)))
        .toList(growable: false);
    final selectedDiscard = discardKindOf(selectedEntries);
    final canDiscardSelected =
        widget.onDiscardSelected != null &&
        widget.discardDisabledReason == null &&
        selectedDiscard != null;
    final rows = widget.mode == GitFileListMode.list
        ? [
            for (final entry in widget.entries)
              _ChangesFileRow(
                entry: entry,
                depth: 0,
                label: _changesFileLabel(entry, basename: false),
              ),
          ]
        : _changesTreeRows(widget.entries, _collapsedDirectories);
    final displayRows = <(_ChangesFileRow, bool)>[
      for (final row in rows) (row, false),
    ];
    for (final (index, row) in _exitingRows.reversed) {
      displayRows.insert(index.clamp(0, displayRows.length), (row, true));
    }
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          MeridianSectionHeader(
            color: context.colors.pane,
            titleChild: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(header: true, child: Text(widget.title)),
                ),
                const SizedBox(width: MeridianSpace.space2),
                MeridianCount(
                  label: '${widget.entries.length}',
                  tone: filtered
                      ? MeridianCountTone.neutral
                      : MeridianCountTone.quiet,
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: math.min(
                  constraints.maxWidth - 76,
                  GitLamaLayout.changesHeaderActionsMaxWidth,
                ),
                // Starts at the trailing edge, so staging stays in view
                // when the header is too narrow for every action.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GitFileListModeToggle(
                        toggleKey: ValueKey('changes-${widget.side.name}-mode'),
                        label: widget.title,
                        mode: widget.mode,
                        onChanged: widget.onModeChanged,
                        compact:
                            constraints.maxWidth <
                            GitFileListModeToggle.compactWidth,
                      ),
                      const SizedBox(width: MeridianSpace.space4),
                      // Discarding sits apart from staging, behind a
                      // divider, so a slip of the pointer never destroys
                      // work: destructive actions first, then staging with
                      // its primary action at the trailing edge.
                      if (widget.onDiscardSelected != null ||
                          widget.discardDisabledReason != null)
                        MeridianIconButton(
                          label: selectedDiscard == DiscardKind.clean
                              ? context.l10n.cleanSelected
                              : context.l10n.discardSelected,
                          icon: 'trash',
                          size: MeridianControlSize.small,
                          color: context.colors.danger,
                          disabledReason: widget.discardDisabledReason,
                          onPressed: widget.busy || !canDiscardSelected
                              ? null
                              : widget.onDiscardSelected,
                        ),
                      if (widget.onDiscardAll != null ||
                          widget.discardDisabledReason != null)
                        MeridianIconButton(
                          label: filtered
                              ? context.l10n.discardShown
                              : context.l10n.discardAll,
                          icon: 'brush-cleaning',
                          size: MeridianControlSize.small,
                          color: context.colors.danger,
                          disabledReason: widget.discardDisabledReason,
                          onPressed:
                              widget.busy ||
                                  widget.entries.isEmpty ||
                                  widget.discardDisabledReason != null
                              ? null
                              : widget.onDiscardAll,
                        ),
                      if (widget.onDiscardSelected != null ||
                          widget.onDiscardAll != null ||
                          widget.discardDisabledReason != null)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: MeridianSpace.space4,
                          ),
                          child: SizedBox(
                            height: MeridianSize.controlSm,
                            child: MeridianHairline(axis: Axis.vertical),
                          ),
                        ),
                      MeridianShake(
                        trigger: _selectedFailures,
                        child: MeridianIconButton(
                          label: stage
                              ? context.l10n.stageSelected
                              : context.l10n.unstageSelected,
                          icon: _stagingArrow(widget.side, widget.stacked),
                          size: MeridianControlSize.small,
                          disabledReason: widget.stageDisabledReason,
                          onPressed:
                              widget._stageBlocked ||
                                  widget.selected.isEmpty ||
                                  widget.selected.every(
                                    widget.pendingKeys.contains,
                                  )
                              ? null
                              : widget.onSelected,
                        ),
                      ),
                      if (constraints.maxWidth >= 460)
                        MeridianShake(
                          trigger: _allFailures,
                          child: MeridianButton(
                            label: filtered
                                ? (stage
                                      ? context.l10n.stageShortShown
                                      : context.l10n.unstageShortShown)
                                : allLabel,
                            tooltip: filtered ? allLabel : null,
                            icon: _stagingAllIcon(widget.side),
                            size: MeridianControlSize.small,
                            variant: stage
                                ? MeridianButtonVariant.secondary
                                : MeridianButtonVariant.quiet,
                            disabledReason: widget.stageDisabledReason,
                            onPressed:
                                widget.busy ||
                                    widget._stageBlocked ||
                                    widget.entries.isEmpty
                                ? null
                                : widget.onAll,
                          ),
                        )
                      else
                        MeridianShake(
                          trigger: _allFailures,
                          child: MeridianIconButton(
                            label: allLabel,
                            icon: _stagingAllIcon(widget.side),
                            size: MeridianControlSize.small,
                            disabledReason: widget.stageDisabledReason,
                            onPressed:
                                widget.busy ||
                                    widget._stageBlocked ||
                                    widget.entries.isEmpty
                                ? null
                                : widget.onAll,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                SingleActivator(
                  LogicalKeyboardKey.keyA,
                  meta: defaultTargetPlatform == TargetPlatform.macOS,
                  control: defaultTargetPlatform != TargetPlatform.macOS,
                ): () => widget.onSelectionChanged({
                  for (final entry in widget.entries) changeKey(entry),
                }),
              },
              child: DragTarget<_ChangesDrag>(
                onWillAcceptWithDetails: (details) =>
                    !widget._stageBlocked && details.data.side != widget.side,
                onAcceptWithDetails: (details) =>
                    widget.onDropFiles(details.data.entries),
                builder: (context, candidates, _) => MeridianAnimatedValue(
                  value: candidates.isEmpty ? 0 : 1,
                  duration: MeridianDurations.quick,
                  builder: (context, hover, child) {
                    final colors = context.colors;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          colors.pane,
                          meridianSelectionFill(context),
                          hover,
                        ),
                        border: Border.all(
                          color: Color.lerp(
                            meridianClear(colors.accent),
                            colors.accent,
                            hover,
                          )!,
                          width: GitLamaLayout.dropTargetBorder,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: displayRows.isEmpty
                      ? MeridianEmptyState(
                          key: ValueKey(('changes-empty', widget.side)),
                          compact: true,
                          title: filtered && widget.totalEntries! > 0
                              ? context.l10n.changesFilterNoMatches
                              : context.l10n.stagingEmpty,
                        )
                      : ListView.builder(
                          key: ValueKey('changes-${widget.side.name}-list'),
                          controller: widget.controller,
                          itemCount: displayRows.length,
                          itemExtent: _exitingRows.isEmpty
                              ? context.meridian.density.rowExtent
                              : null,
                          itemBuilder: (context, index) {
                            final (row, exiting) = displayRows[index];
                            if (exiting) {
                              final entry = row.entry!;
                              return MeridianRemovingRow(
                                key: ValueKey((
                                  'commit-exit',
                                  widget.commitSequence,
                                  widget.mutationSequence,
                                  changeKey(entry),
                                )),
                                onRemoved: () {
                                  if (mounted) {
                                    setState(
                                      () => _exitingRows.removeWhere(
                                        (item) => item.$2.entry == entry,
                                      ),
                                    );
                                  }
                                },
                                child: SizedBox(
                                  height: MeridianTheme.of(
                                    context,
                                  ).density.rowExtent,
                                  child: IgnorePointer(
                                    child: GitLamaFileRow(
                                      status: changeStatusCode(
                                        entry,
                                        widget.side,
                                      ),
                                      path: row.label,
                                      depth: row.depth,
                                      staged: true,
                                      partial: entry.staged && entry.unstaged,
                                      onActivate: () {},
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (row.directory) {
                              final collapsed = _collapsedDirectories.contains(
                                row.identity,
                              );
                              final selectedDirectory =
                                  row.entries.isNotEmpty &&
                                  row.entries.every(
                                    (entry) => widget.selected.contains(
                                      changeKey(entry),
                                    ),
                                  );
                              return GitLamaContextMenuWidget(
                                menuItems: (_) => _directoryMenu(row, stage),
                                child: MeridianListRow(
                                  key: ValueKey(
                                    'changes-${widget.side.name}-directory-${row.identity}',
                                  ),
                                  title: row.label,
                                  selected: selectedDirectory,
                                  // Selecting a folder never folds it; only
                                  // its chevron does.
                                  onTap: () => widget.onSelectionChanged({
                                    for (final entry in row.entries)
                                      changeKey(entry),
                                  }),
                                  leading: Padding(
                                    padding: EdgeInsetsDirectional.only(
                                      start: row.depth * 14.0,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Semantics(
                                          button: true,
                                          label: collapsed
                                              ? context.l10n.changesExpandFolder
                                              : context
                                                    .l10n
                                                    .changesCollapseFolder,
                                          child: MeridianInteraction(
                                            key: ValueKey(
                                              'changes-${widget.side.name}-directory-toggle-${row.identity}',
                                            ),
                                            canRequestFocus: false,
                                            onTap: () => setState(() {
                                              if (!_collapsedDirectories.remove(
                                                row.identity,
                                              )) {
                                                _collapsedDirectories.add(
                                                  row.identity,
                                                );
                                              }
                                            }),
                                            child: MeridianIcon(
                                              collapsed
                                                  ? 'chevron-right'
                                                  : 'chevron-down',
                                              size: MeridianIconSize.small,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                          width: MeridianSpace.space2,
                                        ),
                                        MeridianIcon(
                                          collapsed
                                              ? 'folder-closed'
                                              : 'folder-open',
                                          size: MeridianIconSize.regular,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                            final entry = row.entry!;
                            final key = changeKey(entry);
                            final actionEntries = widget.selected.contains(key)
                                ? selectedEntries
                                : [entry];
                            final dragEntries = actionEntries;
                            final actionDiscard = discardKindOf(actionEntries);
                            final drag = _ChangesDrag(widget.side, dragEntries);
                            final dragTheme = context.meridian;
                            final dragFeedback = DecoratedBox(
                              decoration: BoxDecoration(
                                color: dragTheme.colors.raised,
                                borderRadius: BorderRadius.circular(
                                  context.meridian.radius.md,
                                ),
                                boxShadow: dragTheme.shadows.shadowFloat,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: MeridianSpace.space4,
                                  vertical: MeridianSpace.space3,
                                ),
                                child: Text(
                                  stage
                                      ? context.l10n.changesDragStageCount(
                                          dragEntries.length,
                                        )
                                      : context.l10n.changesDragUnstageCount(
                                          dragEntries.length,
                                        ),
                                  style: context.text.label.copyWith(
                                    color: dragTheme.colors.ink,
                                  ),
                                ),
                              ),
                            );
                            final content = GitLamaContextMenuWidget(
                              menuItems: (_) => _fileMenu(entry, stage),
                              child: GitLamaFileRow(
                                key: ValueKey(
                                  'changes-${widget.side.name}-file-$key',
                                ),
                                status: changeStatusCode(entry, widget.side),
                                path: row.label,
                                depth: row.depth,
                                staged: !stage,
                                partial: entry.staged && entry.unstaged,
                                selected: widget.selected.contains(key),
                                onActivate:
                                    widget.busy &&
                                        !widget.allowSelectionWhileBusy
                                    ? () {}
                                    : () => _selectEntry(entry),
                                stageIcon: _stagingArrow(
                                  widget.side,
                                  widget.stacked,
                                ),
                                onStage:
                                    widget._stageBlocked ||
                                        actionEntries.every(
                                          (entry) => widget.pendingKeys
                                              .contains(changeKey(entry)),
                                        )
                                    ? null
                                    : () => widget.onFiles(actionEntries),
                                onDiscard:
                                    widget.busy ||
                                        widget.discardDisabledReason != null ||
                                        widget.onDiscardFiles == null ||
                                        actionDiscard == null
                                    ? null
                                    : () =>
                                          widget.onDiscardFiles!(actionEntries),
                                stageActionLabel: actionEntries.length > 1
                                    ? (stage
                                          ? context.l10n.stageSelected
                                          : context.l10n.unstageSelected)
                                    : null,
                                discardActionLabel:
                                    actionDiscard == DiscardKind.clean
                                    ? (actionEntries.length > 1
                                          ? context.l10n.cleanSelected
                                          : context.l10n.cleanFile)
                                    : actionEntries.length > 1
                                    ? context.l10n.discardSelected
                                    : null,
                                trailing: widget.pendingKeys.contains(key)
                                    ? MeridianSpinner(
                                        semanticLabel:
                                            context.l10n.stagingPendingFile,
                                      )
                                    : Draggable<_ChangesDrag>(
                                        data: drag,
                                        maxSimultaneousDrags:
                                            widget._stageBlocked ? 0 : 1,
                                        feedback: MeridianLift(
                                          lifted: true,
                                          child: dragFeedback,
                                        ),
                                        child: Tooltip(
                                          message: context
                                              .l10n
                                              .dragChangeToOtherList,
                                          child: const Padding(
                                            padding: EdgeInsets.all(
                                              MeridianSpace.space2,
                                            ),
                                            child: MeridianIcon(
                                              'grip-vertical',
                                              size: MeridianIconSize.small,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            );
                            final draggable = LongPressDraggable<_ChangesDrag>(
                              data: drag,
                              maxSimultaneousDrags: widget._stageBlocked
                                  ? 0
                                  : 1,
                              feedback: MeridianLift(
                                lifted: true,
                                child: dragFeedback,
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.35,
                                child: content,
                              ),
                              child: content,
                            );
                            Widget moving = MeridianTravel(
                              key: _travelKey(entry),
                              travelKey: ('file', key),
                              child: entry.kind == StatusEntryKind.ignored
                                  ? Opacity(opacity: 0.6, child: draggable)
                                  : draggable,
                            );
                            if (_arrivingKeys.contains(key)) {
                              moving = widget.flightKey == key
                                  ? MeridianAttention(
                                      trigger: widget.mutationSequence,
                                      memoryKey: ('stage-flight', key),
                                      child: moving,
                                    )
                                  : MeridianEntrance(
                                      entranceKey: (
                                        'stage-arrival',
                                        widget.side,
                                        key,
                                        widget.mutationSequence,
                                      ),
                                      index: _arrivingKeys.toList().indexOf(
                                        key,
                                      ),
                                      child: moving,
                                    );
                            }
                            return moving;
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangesDrag {
  const _ChangesDrag(this.side, this.entries);

  final StagingSide side;
  final List<RepositoryStatusEntry> entries;
}

class _ChangesFileRow {
  const _ChangesFileRow({
    required this.entry,
    required this.depth,
    required this.label,
  }) : directory = false,
       identity = '',
       entries = const [];

  const _ChangesFileRow.directory({
    required this.identity,
    required this.label,
    required this.depth,
    required this.entries,
  }) : directory = true,
       entry = null;

  final RepositoryStatusEntry? entry;
  final int depth;
  final bool directory;
  final String identity;
  final String label;
  final List<RepositoryStatusEntry> entries;
}

/// The tree rows of [entries]: folders first, then files, with collapsed
/// folders' contents left out. Rows are built by the shared path tree, so
/// every file list arranges a tree the same way.
List<_ChangesFileRow> _changesTreeRows(
  List<RepositoryStatusEntry> entries,
  Set<String> collapsed,
) => [
  for (final row in MeridianPathTree.flatten<RepositoryStatusEntry>(
    entries,
    pathOf: (entry) => displayNativePath(entry.path),
    collapsed: collapsed,
  ))
    if (row.directory)
      _ChangesFileRow.directory(
        identity: row.identity,
        label: row.label,
        depth: row.depth,
        entries: row.descendants,
      )
    else
      _ChangesFileRow(
        entry: row.item!,
        depth: row.depth,
        label: _changesFileLabel(row.item!, basename: true),
      ),
];

/// Whether [entry]'s path (or the path it was renamed from) contains every
/// whitespace-separated term of [query], ignoring case. An empty query
/// matches everything.
bool changesFilterMatches(RepositoryStatusEntry entry, String query) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) return true;
  final path = _changesFileLabel(entry, basename: false).toLowerCase();
  return terms.every(path.contains);
}

String _changesFileLabel(
  RepositoryStatusEntry entry, {
  required bool basename,
}) {
  String display(NativePathIdentity identity) {
    final value = displayNativePath(identity).replaceAll('\\', '/');
    return basename ? value.split('/').last : value;
  }

  final target = display(entry.path);
  return entry.source == null ? target : '${display(entry.source!)} → $target';
}

String _stagingArrow(StagingSide side, bool stacked) =>
    switch ((side, stacked)) {
      (StagingSide.unstaged, false) => 'arrow-right',
      (StagingSide.staged, false) => 'arrow-left',
      (StagingSide.unstaged, true) => 'arrow-down',
      (StagingSide.staged, true) => 'arrow-up',
    };

String _stagingAllIcon(StagingSide side) => switch (side) {
  StagingSide.unstaged => 'stage-all',
  StagingSide.staged => 'unstage-all',
};

/// The status letter [GitLamaStatusGlyph] shows for [entry] on [side].
String changeStatusCode(RepositoryStatusEntry entry, StagingSide side) {
  if (entry.conflicted) return 'U';
  if (entry.kind == StatusEntryKind.untracked) return '?';
  if (entry.kind == StatusEntryKind.ignored) return '!';
  if (entry.kind == StatusEntryKind.rename) return 'R';
  final change = side == StagingSide.staged ? entry.index : entry.worktree;
  return switch (change) {
    ChangeKind.added => 'A',
    ChangeKind.deleted => 'D',
    ChangeKind.renamed => 'R',
    ChangeKind.copied => 'C',
    ChangeKind.updatedButUnmerged => 'U',
    ChangeKind.typeChanged || ChangeKind.modified => 'M',
    ChangeKind.unmodified => '!',
  };
}

class PartialStagingChoice {
  const PartialStagingChoice(this.page, this.rowIds);

  final DiffPage page;
  final List<String> rowIds;
}

class PartialDiscardChoice {
  const PartialDiscardChoice(this.page, this.rowIds);

  final DiffPage page;
  final List<String> rowIds;
}

class PartialPatchChoice {
  const PartialPatchChoice(this.page, this.rowIds);

  final DiffPage page;
  final List<String> rowIds;
}

class WorkingDiffSelectionDialog extends StatefulWidget {
  const WorkingDiffSelectionDialog({
    super.key,
    required this.side,
    required this.oldPath,
    required this.newPath,
    required this.repositories,
    required this.allowDiscard,
    this.allowPatch = true,
    this.stageDisabledReason,
  });

  final StagingSide side;
  final List<int>? oldPath;
  final List<int>? newPath;
  final RepositorySessionService repositories;
  final bool allowDiscard;

  /// Whether a patch of the selected lines is offered.
  final bool allowPatch;

  /// Why staging the selected lines is unavailable, or null.
  final String? stageDisabledReason;

  @override
  State<WorkingDiffSelectionDialog> createState() =>
      _WorkingDiffSelectionDialogState();
}

class _WorkingDiffSelectionDialogState
    extends State<WorkingDiffSelectionDialog> {
  DiffPage? _page;
  final List<DiffDisplayRow> _rows = [];
  final DiffLineSelection _selection = DiffLineSelection();
  Object? _failure;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final page = await widget.repositories.workingCopy.diff(
        side: widget.side,
        oldPath: widget.oldPath,
        newPath: widget.newPath,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _rows
          ..clear()
          ..addAll(page.rows);
        _index();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final page = _page;
    if (_loading || page == null || _rows.length >= page.totalRows) return;
    setState(() => _loading = true);
    try {
      final next = await widget.repositories.workingCopy.diffPage(
        requestId: page.requestId,
        offset: _rows.length,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(next.rows);
        _index();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _loading = false;
        });
      }
    }
  }

  void _index() {
    _selection.update(_rows, _page?.totalRows ?? _rows.length);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final action = widget.side == StagingSide.unstaged
        ? context.l10n.stageLines
        : context.l10n.unstageLines;
    final colors = context.colors;
    final picked = _selection.pickedLines;
    final hasMore = _rows.length < (page?.totalRows ?? 0);
    final all = _selection.allChecked;
    final Widget list = _failure != null
        ? MeridianEmptyState(
            compact: true,
            icon: 'circle-alert',
            title: context.l10n.workingDiffFailed,
          )
        : _loading && page == null
        ? MeridianEmptyState(
            compact: true,
            progress: true,
            title: context.l10n.loading,
          )
        : ListView.builder(
            key: const ValueKey('line-selection-list'),
            itemCount: _rows.length + (hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _rows.length) {
                return Padding(
                  padding: const EdgeInsets.all(MeridianSpace.space3),
                  child: Center(
                    child: MeridianButton(
                      label: context.l10n.stagingLoadMore,
                      variant: MeridianButtonVariant.quiet,
                      size: MeridianControlSize.small,
                      onPressed: _loading ? null : _loadMore,
                    ),
                  ),
                );
              }
              final row = _rows[index];
              final hunk = row.kind == DiffRowKind.hunk;
              final pickable = hunk || (row.selectable && !row.loading);
              return DiffLineSelectionRow(
                key: ValueKey('line-selection-${row.stableId}'),
                row: row,
                checked: hunk
                    ? _selection.hunkChecked(row.stableId)
                    : _selection.lineChecked(row),
                onChanged: !pickable
                    ? null
                    : (value) => setState(() {
                        if (hunk) {
                          _selection.setHunk(row.stableId, value);
                        } else {
                          _selection.setLine(row, value);
                        }
                      }),
              );
            },
          );
    return MeridianDialog(
      width: MeridianLayout.dialogWorkflowWidth,
      title: context.l10n.inspectChanges,
      description: context.l10n.inspectChangesHelp,
      content: SizedBox(
        height: GitLamaLayout.previewDialogBodyHeight,
        // The outline is drawn over the rows, whose fills reach the edges.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: colors.line),
            borderRadius: BorderRadius.circular(context.meridian.radius.lg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(context.meridian.radius.lg),
            child: ColoredBox(
              color: colors.pane,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: colors.paneAlt,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: MeridianSpace.space5,
                        end: MeridianSpace.space3,
                        top: MeridianSpace.space2,
                        bottom: MeridianSpace.space2,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              key: const ValueKey('line-selection-count'),
                              picked.more
                                  ? context.l10n.lineSelectionCountAtLeast(
                                      picked.count,
                                    )
                                  : context.l10n.lineSelectionCount(
                                      picked.count,
                                    ),
                              style: context.text.caption.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                          ),
                          MeridianButton(
                            key: const ValueKey('line-selection-all'),
                            variant: MeridianButtonVariant.quiet,
                            size: MeridianControlSize.small,
                            label: all
                                ? context.l10n.stashSelectNone
                                : context.l10n.stashSelectAll,
                            onPressed: page == null || _failure != null
                                ? null
                                : () => setState(
                                    all
                                        ? _selection.clear
                                        : _selection.selectAll,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  MeridianHairline(color: colors.line),
                  Expanded(child: list),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        MeridianButton(
          label: context.l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        if (widget.allowDiscard)
          MeridianButton(
            label: context.l10n.discardLines,
            variant: MeridianButtonVariant.dangerQuiet,
            onPressed: page == null || _selection.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    PartialDiscardChoice(page, _selection.rowIds),
                  ),
          ),
        if (widget.allowPatch)
          MeridianButton(
            label: context.l10n.patchCreate,
            onPressed: page == null || _selection.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    PartialPatchChoice(page, _selection.rowIds),
                  ),
          ),
        MeridianButton(
          label: action,
          variant: MeridianButtonVariant.primary,
          disabledReason: widget.stageDisabledReason,
          onPressed:
              page == null ||
                  _selection.isEmpty ||
                  widget.stageDisabledReason != null
              ? null
              : () => Navigator.pop(
                  context,
                  PartialStagingChoice(page, _selection.rowIds),
                ),
        ),
      ],
    );
  }
}

/// The file actions of the working-tree lists.
final class _ChangesActionHost extends FileActionHost {
  _ChangesActionHost(this._state);

  final ChangesSectionState _state;

  @override
  Set<FileAction> get capabilities => {
    FileAction.stage,
    FileAction.unstage,
    FileAction.inspectChanges,
    FileAction.createPatch,
    FileAction.openExternally,
    FileAction.revealInFileBrowser,
    FileAction.copyPath,
    if (_state.widget.onDiscardFiles != null) ...{
      FileAction.discard,
      FileAction.clean,
    },
    if (_state.widget.onIgnore != null) FileAction.addToGitignore,
    if (FileActionsScope.maybeOf(_state.context)?.inspectWorkingFile !=
        null) ...{
      FileAction.blame,
      FileAction.fileHistory,
      FileAction.folderHistory,
    },
  };

  @override
  String get fileBrowserName => _state.widget.fileBrowserName;

  @override
  String? inspectionUnavailableReason(BuildContext context) =>
      _state.widget.inspectionUnavailableReason;

  @override
  String? actionUnavailableReason(BuildContext context, FileAction action) {
    final widget = _state.widget;
    return switch (action) {
      FileAction.stage || FileAction.unstage => widget.stageDisabledReason,
      FileAction.createPatch => widget.patchDisabledReason,
      FileAction.openExternally ||
      FileAction.revealInFileBrowser => widget.externalDisabledReason,
      FileAction.discard || FileAction.clean => widget.discardDisabledReason,
      FileAction.addToGitignore => widget.ignoreDisabledReason,
      _ => null,
    };
  }

  @override
  void run(
    FileActionCommand command,
    FileActionSubject subject, {
    required bool invert,
  }) {}
}
