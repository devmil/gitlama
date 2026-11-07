import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/diff.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import '../../models/stash.dart';
import '../app_theme.dart';
import 'status_bar.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../widgets/command_preview.dart';
import '../../widgets/gitlama_git_glyphs.dart';
import 'changes_section.dart';
import '../../widgets/gitlama_list_well.dart';

class StashInputDialog extends StatefulWidget {
  const StashInputDialog({
    super.key,
    required this.kind,
    required this.selector,
    required this.objectId,
    required this.initialMessage,
    required this.initialTargetBranch,
    required this.statusEntries,
    required this.branches,
  });

  final StashKind kind;
  final String? selector;
  final String? objectId;
  final String? initialMessage;
  final String? initialTargetBranch;
  final List<RepositoryStatusEntry> statusEntries;
  final List<String> branches;

  @override
  State<StashInputDialog> createState() => _StashInputDialogState();
}

/// Which changes a new stash takes.
enum _StashScope { all, selected }

class _StashInputDialogState extends State<StashInputDialog> {
  late final TextEditingController _message;

  /// Indexes into [_tracked] chosen for a partial stash.
  final Set<int> _selected = {};
  var _scope = _StashScope.all;
  var _includeUntracked = false;
  var _keepIndex = false;
  String? _targetBranch;
  late final TextEditingController _targetBranchInput;

  // Git rejects an untracked pathspec in a partial stash, so only tracked
  // changes can be picked; new files go with all changes.
  late final List<RepositoryStatusEntry> _tracked = [
    for (final entry in widget.statusEntries)
      if (entry.kind != StatusEntryKind.untracked &&
          entry.kind != StatusEntryKind.ignored)
        entry,
  ];
  late final int _untracked = widget.statusEntries
      .where((entry) => entry.kind == StatusEntryKind.untracked)
      .length;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController(text: widget.initialMessage ?? '')
      ..addListener(_changed);
    _targetBranch = widget.initialTargetBranch ?? widget.branches.firstOrNull;
    _targetBranchInput = TextEditingController(text: _targetBranch);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _message.dispose();
    _targetBranchInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final push = widget.kind == StashKind.push;
    final rename = widget.kind == StashKind.rename;
    final auto = widget.kind == StashKind.autoStashCheckout;
    final selecting = push && _scope == _StashScope.selected;
    final valid =
        (!rename || _message.text.trim().isNotEmpty) &&
        (!auto || _targetBranch != null) &&
        (!selecting || _selected.isNotEmpty);
    final label = dialogTitle(stashKindLabel(context, widget.kind));
    void submit() => Navigator.pop(
      context,
      StashRequest(
        kind: widget.kind,
        message: (push || rename) && _message.text.trim().isNotEmpty
            ? _message.text.trim()
            : null,
        selector: widget.selector,
        objectId: widget.objectId,
        paths: [
          if (selecting)
            for (final index in _selected.toList()..sort())
              _tracked[index].path.units,
        ],
        includeUntracked: push && !selecting && _includeUntracked,
        keepIndex: push && _keepIndex,
        targetBranch: auto ? _targetBranch : null,
      ),
    );
    void setScope(_StashScope value) => setState(() => _scope = value);
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      scrollable: true,
      title: label,
      description: push ? context.l10n.stashPushIntro : null,
      onSubmit: submit,
      submitDisabled: !valid,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (widget.selector != null)
            SelectableText(
              contextMenuBuilder: nativeTextContextMenuBuilder,
              context.l10n.stashSelected(widget.selector!),
            ),
          if (push || rename)
            MeridianTextField(
              controller: _message,
              autofocus: true,
              label: rename
                  ? context.l10n.stashNewName
                  : context.l10n.stashMessage,
              placeholder: push ? context.l10n.stashMessagePlaceholder : null,
              inputFormatters: [LengthLimitingTextInputFormatter(256)],
            ),
          if (push) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MeridianRadio(
                  key: const ValueKey('stash-scope-all'),
                  value: _StashScope.all,
                  groupValue: _scope,
                  onChanged: setScope,
                  label: context.l10n.stashScopeAll(
                    _tracked.length + (_includeUntracked ? _untracked : 0),
                  ),
                ),
                MeridianRadio(
                  key: const ValueKey('stash-scope-selected'),
                  value: _StashScope.selected,
                  groupValue: _scope,
                  onChanged: _tracked.isEmpty ? null : setScope,
                  label: context.l10n.stashScopeSelected,
                ),
              ],
            ),
            if (selecting)
              _StashFilePicker(
                entries: _tracked,
                selected: _selected,
                untracked: _untracked,
                onChanged: () => setState(() {}),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: MeridianSpace.space4,
              children: [
                if (!selecting)
                  MeridianCheckbox(
                    key: const ValueKey('stash-include-untracked'),
                    value: _includeUntracked,
                    label: context.l10n.stashIncludeUntracked,
                    description: context.l10n.stashIncludeUntrackedHelp,
                    onChanged: (value) =>
                        setState(() => _includeUntracked = value),
                  ),
                MeridianCheckbox(
                  key: const ValueKey('stash-keep-index'),
                  value: _keepIndex,
                  label: context.l10n.stashKeepIndex,
                  description: context.l10n.stashKeepIndexHelp,
                  onChanged: (value) => setState(() => _keepIndex = value),
                ),
              ],
            ),
          ],
          if (auto)
            GitReferenceField(
              controller: _targetBranchInput,
              label: context.l10n.stashTargetBranch,
              names: widget.branches,
              onChanged: (value) => setState(
                () => _targetBranch = widget.branches.contains(value)
                    ? value
                    : null,
              ),
            ),
          if (widget.kind == StashKind.drop)
            MeridianBanner(
              tone: MeridianBannerTone.warning,
              message: context.l10n.stashDropWarning,
            ),
        ],
      ),
      actions: [
        MeridianButton(
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
          label: context.l10n.cancel,
        ),
        MeridianButton(
          label: label,
          variant: widget.kind == StashKind.drop
              ? MeridianButtonVariant.danger
              : MeridianButtonVariant.primary,
          disabledReason: selecting && _selected.isEmpty
              ? context.l10n.stashSelectFilesReason
              : null,
          onPressed: valid ? submit : null,
        ),
      ],
    );
  }
}

/// The checklist of tracked changes for a partial stash, styled like the
/// Changes lists: status glyph, file name, then its folder.
class _StashFilePicker extends StatelessWidget {
  const _StashFilePicker({
    required this.entries,
    required this.selected,
    required this.untracked,
    required this.onChanged,
  });

  final List<RepositoryStatusEntry> entries;

  /// Indexes into [entries]; changed in place, then [onChanged] runs.
  final Set<int> selected;
  final int untracked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final all = selected.length == entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space3,
      children: [
        GitLamaListWell(
          header: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: MeridianSpace.space6,
              end: MeridianSpace.space3,
              top: MeridianSpace.space3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.stashSelectionCount(
                      selected.length,
                      entries.length,
                    ),
                    style: context.text.caption.copyWith(
                      color: colors.inkMuted,
                    ),
                  ),
                ),
                MeridianButton(
                  key: const ValueKey('stash-select-all'),
                  variant: MeridianButtonVariant.quiet,
                  size: MeridianControlSize.small,
                  label: all
                      ? context.l10n.stashSelectNone
                      : context.l10n.stashSelectAll,
                  onPressed: () {
                    if (all) {
                      selected.clear();
                    } else {
                      selected.addAll([
                        for (var index = 0; index < entries.length; index++)
                          index,
                      ]);
                    }
                    onChanged();
                  },
                ),
              ],
            ),
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return gitLamaPathRow(
              displayNativePath(entry.path),
              key: ValueKey('stash-file-$index'),
              checked: selected.contains(index),
              leading: GitLamaStatusGlyph(
                changeStatusCode(
                  entry,
                  entry.unstaged ? StagingSide.unstaged : StagingSide.staged,
                ),
              ),
              onTap: () {
                if (!selected.remove(index)) selected.add(index);
                onChanged();
              },
            );
          },
        ),
        if (untracked > 0)
          Text(
            context.l10n.stashSelectedUntrackedNote(untracked),
            style: context.text.caption.copyWith(color: colors.inkMuted),
          ),
      ],
    );
  }
}

class StashPreviewDialog extends StatelessWidget {
  const StashPreviewDialog({super.key, required this.preview});

  final StashPreview preview;

  @override
  Widget build(BuildContext context) {
    final properties = [
      if (preview.affectedPaths > 0)
        MeridianProperty(
          label: context.l10n.stashPreviewFiles,
          value: context.l10n.stashPreviewFileCount(preview.affectedPaths),
          selectable: false,
        ),
      if (preview.includesUntracked)
        MeridianProperty(
          label: context.l10n.stashPreviewNewFiles,
          value: context.l10n.stashPreviewIncluded,
          selectable: false,
        ),
      if (preview.keepsIndex)
        MeridianProperty(
          label: context.l10n.stashPreviewStaged,
          value: context.l10n.stashPreviewStillStaged,
          selectable: false,
        ),
      if (preview.targetBranch case final branch?)
        MeridianProperty(
          label: context.l10n.stashTargetBranch,
          value: branch,
          monospace: true,
        ),
    ];
    return MeridianDialog(
      width: MeridianLayout.dialogConfirmWidth,
      title: context.l10n.stashPreviewTitle,
      description: switch (preview.kind) {
        StashKind.push => context.l10n.stashPushSummary,
        StashKind.apply => context.l10n.stashApplySummary,
        StashKind.pop => context.l10n.stashPopSummary,
        StashKind.drop => context.l10n.stashDropSummary,
        StashKind.rename => context.l10n.stashRenameSummary,
        StashKind.autoStashCheckout ||
        StashKind.stashCheckoutCommit ||
        StashKind.autoStashCheckoutCommit => context.l10n.stashCheckoutSummary,
      },
      onSubmit: () => Navigator.pop(context, true),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (properties.isNotEmpty)
            MeridianPropertyList(properties: properties),
          if (preview.destructive)
            MeridianBanner(
              tone: MeridianBannerTone.warning,
              message: context.l10n.stashDropWarning,
            ),
          if (preview.kind
              case StashKind.apply ||
                  StashKind.pop ||
                  StashKind.autoStashCheckout)
            Text(
              context.l10n.stashRecoveryRetained,
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          GitCommandDetails(
            commands: [
              for (final command in preview.commands)
                'git ${command.join(' ')}',
            ],
          ),
        ],
      ),
      actions: [
        MeridianButton(
          variant: MeridianButtonVariant.quiet,
          autofocus: preview.destructive,
          onPressed: () => Navigator.pop(context, false),
          label: context.l10n.cancel,
        ),
        MeridianButton(
          label: dialogTitle(stashKindLabel(context, preview.kind)),
          variant: preview.destructive
              ? MeridianButtonVariant.danger
              : MeridianButtonVariant.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
