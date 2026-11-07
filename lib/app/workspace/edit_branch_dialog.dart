import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/ref_mutation.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import 'labels.dart';
import '../../models/git_names.dart';

/// The name and upstream an edited branch should have. [upstream] is a
/// remote-tracking branch such as `origin/main`, or null for none.
/// Renames a local branch and changes the remote branch it tracks.
class EditBranchDialog extends StatefulWidget {
  const EditBranchDialog({
    required this.branch,
    required this.references,
    super.key,
  });

  final String branch;
  final RepositoryRefs references;

  @override
  State<EditBranchDialog> createState() => _EditBranchDialogState();
}

class _EditBranchDialogState extends State<EditBranchDialog> {
  late final String? _initialUpstream = widget.references.upstreamLabelOf(
    widget.branch,
  );
  late final _name = TextEditingController(text: widget.branch)
    ..addListener(_changed);
  late final _upstream = TextEditingController(text: _initialUpstream ?? '')
    ..addListener(_changed);
  late final List<String> _otherBranches = [
    for (final reference in widget.references.branches)
      if (!nameIs(reference.name, widget.branch))
        utf8.decode(reference.name, allowMalformed: true),
  ];
  late final List<String> _remoteBranches = [
    for (final remote in widget.references.remotes)
      for (final branch in remote.branches)
        if (!nameIs(branch.name, 'HEAD'))
          '${utf8.decode(remote.name, allowMalformed: true)}/'
              '${utf8.decode(branch.name, allowMalformed: true)}',
  ]..sort();

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _upstream.dispose();
    super.dispose();
  }

  String get _nameValue => _name.text.trim();

  String? get _upstreamValue {
    final value = _upstream.text.trim();
    return value.isEmpty ? null : value;
  }

  bool get _nameTaken => _otherBranches.contains(_nameValue);

  // A gone upstream may stay as it is; a new one must be fetched.
  bool get _upstreamValid =>
      _upstreamValue == null ||
      _upstreamValue == _initialUpstream ||
      _remoteBranches.contains(_upstreamValue);

  bool get _changedValues =>
      _nameValue != widget.branch || _upstreamValue != _initialUpstream;

  bool get _canSave =>
      _nameValue.isNotEmpty && !_nameTaken && _upstreamValid && _changedValues;

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      EditBranchResult(name: _nameValue, upstream: _upstreamValue),
    );
  }

  @override
  Widget build(BuildContext context) => MeridianDialog(
    width: MeridianLayout.dialogFormWidth,
    scrollable: true,
    title: dialogTitle(context.l10n.commandEditBranch),
    description: context.l10n.editBranchDescription,
    onSubmit: _save,
    submitDisabled: !_canSave,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MeridianSpace.space6,
      children: [
        GitReferenceField(
          fieldKey: const ValueKey('edit-branch-name'),
          controller: _name,
          autofocus: true,
          label: context.l10n.editBranchName,
          names: _otherBranches,
          normalize: true,
          suggestSegments: true,
          helperText: _nameTaken ? context.l10n.editBranchNameExists : null,
        ),
        GitReferenceField(
          fieldKey: const ValueKey('edit-branch-upstream'),
          controller: _upstream,
          label: context.l10n.editBranchUpstream,
          names: _remoteBranches,
          helperText: _upstreamValid
              ? context.l10n.editBranchNoUpstream
              : context.l10n.editBranchUpstreamUnknown,
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
        key: const ValueKey('edit-branch-save'),
        label: context.l10n.editBranchSave,
        variant: MeridianButtonVariant.primary,
        onPressed: _canSave ? _save : null,
      ),
    ],
  );
}
