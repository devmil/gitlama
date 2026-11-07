import 'dart:convert';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/reference_name.dart';
import '../../models/app_command.dart';
import '../../models/repository_state.dart';
import '../../models/ref_mutation.dart';
import '../../widgets/git_reference_field.dart';
import '../../widgets/gitlama_list_well.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../models/git_names.dart';

/// The marker the shared Git library writes into a display URL in place of
/// credentials. Such a URL is not the configured one.
const _redactionMarker = '[REDACTED]';

class RefMutationInputDialog extends StatefulWidget {
  const RefMutationInputDialog({
    super.key,
    required this.kind,
    required this.initialName,
    required this.initialTarget,
    required this.references,
    required this.choices,
    this.previousRequest,
  });

  final RefMutationRequest? previousRequest;
  final RepositoryRefs references;
  final List<GitReferenceChoice> choices;
  final RefMutationKind kind;
  final String? initialName;
  final String? initialTarget;

  @override
  State<RefMutationInputDialog> createState() => _RefMutationInputDialogState();
}

class _RefMutationInputDialogState extends State<RefMutationInputDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _url;
  late final TextEditingController _message;
  late final TextEditingController _secondName;
  var _force = false;
  var _checkout = true;

  /// The displayed URL of the remote being edited, or null when it hides
  /// credentials and so cannot be offered as the value to keep.
  String? _currentUrl;
  var _currentUrlHidden = false;
  var _deleteUpstream = false;
  var _resetMode = RefResetMode.soft;
  final Set<String> _remoteNames = {};

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.previousRequest?.name ?? widget.initialName ?? '',
    )..addListener(_changed);
    _target = TextEditingController(
      text: widget.previousRequest?.target ?? widget.initialTarget ?? '',
    )..addListener(_changed);
    final remote = widget.references.remotes
        .where((remote) => nameIs(remote.name, widget.initialName))
        .firstOrNull;
    if (widget.kind == RefMutationKind.editRemote && remote != null) {
      final display = utf8.decode(remote.displayUrl, allowMalformed: true);
      _currentUrlHidden = display.contains(_redactionMarker);
      if (!_currentUrlHidden) _currentUrl = display;
    }
    _url = TextEditingController(text: _currentUrl ?? '')
      ..addListener(_changed);
    _message = TextEditingController(
      text: widget.previousRequest?.message ?? '',
    );
    final previous = widget.previousRequest;
    if (previous != null) {
      _checkout = previous.checkout;
      _force = previous.force;
      _resetMode = previous.resetMode ?? RefResetMode.soft;
      _remoteNames.addAll(previous.remoteNames);
      _deleteUpstream = previous.deleteUpstream != null;
    }
    _secondName = TextEditingController(
      text:
          widget.kind == RefMutationKind.renameBranch ||
              widget.kind == RefMutationKind.renameRemote
          ? widget.previousRequest?.name ?? widget.initialName ?? ''
          : '',
    )..addListener(_changed);
  }

  void _changed() => setState(() {});

  /// A URL to write: never the display marker for hidden credentials, and,
  /// when editing, a change from the current URL.
  bool _acceptableUrl(String url) =>
      url.isNotEmpty && !url.contains(_redactionMarker) && url != _currentUrl;

  /// The upstream of the branch being deleted, when its remote-tracking ref
  /// is fetched: the lease a remote deletion needs.
  RefMutationUpstream? get _upstream {
    if (widget.kind != RefMutationKind.deleteBranch) return null;
    final name = _name.text.trim();
    final branch = widget.references.branches
        .where((branch) => nameIs(branch.name, name))
        .firstOrNull;
    final upstream = branch?.upstream;
    if (branch == null || upstream == null || branch.upstreamGone) return null;
    return branchUpstream(
      widget.references,
      utf8.decode(upstream, allowMalformed: true),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _url.dispose();
    _message.dispose();
    _secondName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsName = widget.kind != RefMutationKind.reset;
    final remoteKind =
        widget.kind == RefMutationKind.editRemote ||
        widget.kind == RefMutationKind.renameRemote;
    // A remote chosen from its row is shown, not edited: the field names
    // which remote changes.
    final fixedName = remoteKind && (widget.initialName?.isNotEmpty ?? false);
    final needsSecondName =
        widget.kind == RefMutationKind.renameBranch ||
        widget.kind == RefMutationKind.renameRemote;
    final remoteNames = [
      for (final remote in widget.references.remotes)
        utf8.decode(remote.name, allowMalformed: true),
    ];
    final needsTarget =
        widget.kind == RefMutationKind.createBranch ||
        widget.kind == RefMutationKind.createTag ||
        widget.kind == RefMutationKind.reset;
    final needsUrl =
        widget.kind == RefMutationKind.addRemote ||
        widget.kind == RefMutationKind.editRemote;
    final valid =
        (!needsName || _name.text.trim().isNotEmpty) &&
        (!needsSecondName ||
            (_secondName.text.trim().isNotEmpty &&
                (widget.kind != RefMutationKind.renameRemote ||
                    (_secondName.text.trim() != _name.text.trim() &&
                        !remoteNames.contains(_secondName.text.trim()))))) &&
        (!needsTarget || _target.text.trim().isNotEmpty) &&
        (!needsUrl || _acceptableUrl(_url.text.trim()));
    final command = switch (widget.kind) {
      RefMutationKind.createBranch => AppCommandId.createBranch,
      RefMutationKind.renameBranch => AppCommandId.renameBranch,
      RefMutationKind.deleteBranch => AppCommandId.deleteBranch,
      RefMutationKind.checkoutBranch => AppCommandId.checkoutBranch,
      RefMutationKind.checkoutCommit => AppCommandId.checkoutCommit,
      RefMutationKind.setUpstream ||
      RefMutationKind.unsetUpstream => AppCommandId.renameBranch,
      RefMutationKind.createTag => AppCommandId.createTag,
      RefMutationKind.deleteTag => AppCommandId.deleteTag,
      RefMutationKind.addRemote => AppCommandId.addRemote,
      RefMutationKind.editRemote => AppCommandId.editRemote,
      RefMutationKind.renameRemote => AppCommandId.renameRemote,
      RefMutationKind.removeRemote => AppCommandId.removeRemote,
      RefMutationKind.reset => AppCommandId.resetBranch,
    };
    final upstream = _upstream;
    final title = dialogTitle(commandLabel(context, command));
    void submit() => Navigator.pop(
      context,
      RefMutationRequest(
        kind: widget.kind,
        name: needsName ? _name.text.trim() : null,
        secondName: needsSecondName ? _secondName.text.trim() : null,
        target: needsTarget ? _target.text.trim() : null,
        url: needsUrl ? _url.text.trim() : null,
        force: _force,
        remoteNames: _remoteNames.toList(growable: false),
        deleteUpstream: _deleteUpstream ? upstream : null,
        checkout: widget.kind == RefMutationKind.createBranch && _checkout,
        resetMode: widget.kind == RefMutationKind.reset ? _resetMode : null,
        message:
            widget.kind == RefMutationKind.createTag && _message.text.isNotEmpty
            ? _message.text
            : null,
      ),
    );
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      scrollable: true,
      title: title,
      onSubmit: submit,
      submitDisabled: !valid,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        // Fields fill the width; checkboxes line up with their leading edge.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          if (fixedName)
            MeridianTextField(
              key: const ValueKey('ref-mutation-fixed-name'),
              controller: _name,
              label: context.l10n.refMutationName,
              readOnly: true,
              monospace: true,
            )
          else if (needsName)
            GitReferenceField(
              controller: _name,
              autofocus: true,
              label: context.l10n.refMutationName,
              names: widget.kind == RefMutationKind.createBranch
                  ? gitBranchNameSuggestions(widget.references)
                  : remoteKind || widget.kind == RefMutationKind.removeRemote
                  ? remoteNames
                  : widget.kind == RefMutationKind.deleteTag
                  ? [
                      for (final tag in widget.references.tags)
                        utf8.decode(tag.name, allowMalformed: true),
                    ]
                  : [
                      for (final branch in widget.references.branches)
                        utf8.decode(branch.name, allowMalformed: true),
                    ],
              normalize:
                  widget.kind == RefMutationKind.createBranch ||
                  widget.kind == RefMutationKind.createTag,
              suggestSegments: widget.kind == RefMutationKind.createBranch,
              selectionIcon:
                  remoteKind ||
                      needsUrl ||
                      widget.kind == RefMutationKind.removeRemote
                  ? 'cloud'
                  : widget.kind == RefMutationKind.deleteTag ||
                        widget.kind == RefMutationKind.createTag
                  ? 'tag'
                  : 'branch',
              suggestions:
                  (remoteKind || !needsUrl) &&
                  widget.kind != RefMutationKind.createTag,
            ),
          if (needsSecondName)
            GitReferenceField(
              key: const ValueKey('ref-mutation-new-name'),
              controller: _secondName,
              autofocus: fixedName,
              label: context.l10n.refMutationNewName,
              names: widget.kind == RefMutationKind.renameRemote
                  ? const []
                  : gitBranchNameSuggestions(widget.references),
              normalize: true,
              suggestSegments: widget.kind == RefMutationKind.renameBranch,
            ),
          if (needsUrl)
            MeridianTextField(
              controller: _url,
              autofocus: fixedName,
              label: context.l10n.refMutationRemoteUrl,
              message: _currentUrlHidden
                  ? context.l10n.refMutationRemoteUrlHidden
                  : null,
            ),
          if (needsTarget)
            GitReferenceField(
              controller: _target,
              label: widget.kind == RefMutationKind.createBranch
                  ? context.l10n.refMutationStartingPoint
                  : context.l10n.extensionWorktreeReference,
              names: gitReferenceNames(widget.references),
              choices: widget.choices,
              helperText: context.l10n.referencePickerHistoryHint,
            ),
          if (widget.kind == RefMutationKind.createBranch)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MeridianCheckbox(
                key: const ValueKey('create-branch-checkout'),
                value: _checkout,
                onChanged: (value) => setState(() => _checkout = value),
                label: context.l10n.refMutationCheckoutNewBranch,
              ),
            ),
          if (widget.kind == RefMutationKind.createTag)
            MeridianTextField(
              controller: _message,
              maxLines: 3,
              label: context.l10n.refMutationTagMessage,
              minLines: 3,
            ),
          if (widget.kind == RefMutationKind.deleteBranch)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MeridianCheckbox(
                value: _force,
                onChanged: (value) => setState(() => _force = value),
                label: context.l10n.refMutationForceDelete,
              ),
            ),
          if (upstream != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MeridianCheckbox(
                key: const ValueKey('delete-branch-upstream'),
                value: _deleteUpstream,
                onChanged: (value) => setState(() => _deleteUpstream = value),
                label: context.l10n.refMutationDeleteUpstream(upstream.label),
                description: context.l10n.refMutationDeleteUpstreamHelp,
              ),
            ),
          if (widget.kind == RefMutationKind.deleteTag &&
              widget.references.remotes.isNotEmpty)
            _RemoteChecklist(
              remotes: widget.references.remotes,
              selected: _remoteNames,
              onChanged: () => setState(() {}),
            ),
          if (widget.kind == RefMutationKind.reset)
            MeridianSelect<RefResetMode>(
              value: _resetMode,
              values: const [
                RefResetMode.soft,
                RefResetMode.mixed,
                RefResetMode.hard,
              ],
              valueLabel: (mode) => switch (mode) {
                RefResetMode.soft => context.l10n.refMutationResetSoft,
                RefResetMode.mixed => context.l10n.refMutationResetMixed,
                RefResetMode.hard => context.l10n.refMutationResetHard,
              },
              label: context.l10n.refMutationResetMode,
              showLabel: true,
              expand: true,
              onChanged: (value) => setState(() => _resetMode = value),
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
          variant: MeridianButtonVariant.primary,
          label: title,
          onPressed: valid ? submit : null,
        ),
      ],
    );
  }
}

/// The remotes a tag is also deleted from: a labelled checklist on a
/// bounded well, then what the deletion guarantees as a muted caption.
class _RemoteChecklist extends StatelessWidget {
  const _RemoteChecklist({
    required this.remotes,
    required this.selected,
    required this.onChanged,
  });

  final List<RepositoryRemote> remotes;

  /// Names of the chosen remotes; changed in place, then [onChanged] runs.
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      key: const ValueKey('delete-tag-remotes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space2,
      children: [
        Text(
          context.l10n.deleteTagRemotePrompt,
          style: context.text.label.copyWith(color: colors.ink),
        ),
        GitLamaListWell(
          itemCount: remotes.length,
          itemBuilder: (context, index) {
            final remote = remotes[index];
            final name = utf8.decode(remote.name, allowMalformed: true);
            final url = utf8.decode(remote.displayUrl, allowMalformed: true);
            return MeridianListRow(
              key: ValueKey('delete-tag-remote-$index'),
              checked: selected.contains(name),
              leading: MeridianIcon(
                'cloud',
                size: MeridianIconSize.small,
                color: colors.inkMuted,
              ),
              title: name,
              // A URL that hides credentials says nothing useful here.
              subtitle: url.isEmpty || url.contains(_redactionMarker)
                  ? null
                  : url,
              onTap: () {
                if (!selected.remove(name)) selected.add(name);
                onChanged();
              },
            );
          },
        ),
        Text(
          context.l10n.deleteTagRemoteAvailabilityHint,
          style: context.text.caption.copyWith(color: colors.inkMuted),
        ),
      ],
    );
  }
}

/// Splits a `refs/remotes/<remote>/<branch>` upstream on the longest known
/// remote name (remote names may contain slashes). Null when the
/// remote-tracking ref is not fetched.
RefMutationUpstream? branchUpstream(
  RepositoryRefs references,
  String upstream,
) {
  final split = ReferenceName.parse(
    upstream,
  ).splitRemote([for (final remote in references.remotes) remote.name]);
  if (split == null) return null;
  final owner = references.remotes.firstWhere(
    (remote) => identical(remote.name, split.remote),
  );
  final ownerName = utf8.decode(owner.name, allowMalformed: true);
  final branch = utf8.decode(split.branch, allowMalformed: true);
  final fetched = owner.branches.any(
    (candidate) => nameIs(candidate.name, branch),
  );
  return fetched
      ? RefMutationUpstream(remote: ownerName, branch: branch)
      : null;
}
