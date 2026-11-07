import 'dart:convert';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import '../../models/transfer.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../models/git_names.dart';

class TransferInputDialog extends StatefulWidget {
  const TransferInputDialog({
    super.key,
    required this.kind,
    required this.references,
    required this.remotes,
    required this.branch,
    required this.dirty,
    this.currentBranch,
    this.currentUpstream,
    this.initialRemote,
    this.initialForce = false,
    this.initialPullStrategy = PullStrategy.fastForwardOnly,
  });

  final TransferKind kind;
  final RepositoryRefs references;
  final bool initialForce;
  final List<String> remotes;
  final String? initialRemote;
  final PullStrategy initialPullStrategy;
  final String? branch;
  final List<int>? currentBranch;
  final List<int>? currentUpstream;
  final bool dirty;

  @override
  State<TransferInputDialog> createState() => _TransferInputDialogState();
}

class _TransferInputDialogState extends State<TransferInputDialog> {
  late String? _remote;
  late final TextEditingController _branch;
  late PullStrategy _strategy;
  var _allowDirty = false;
  var _stashBeforePull = false;
  var _force = false;
  // Checked by default; only applies while the branch has no upstream.
  var _setUpstream = true;
  var _prune = true;

  bool get _branchHasUpstream {
    final name = _branch.text.trim();
    if (widget.currentBranch != null &&
        nameIs(widget.currentBranch!, name) &&
        widget.currentUpstream != null) {
      return true;
    }
    for (final branch in widget.references.branches) {
      if (nameIs(branch.name, name)) {
        return branch.upstream != null;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _strategy = widget.initialPullStrategy;
    _force = widget.initialForce;
    _remote =
        widget.initialRemote != null &&
            widget.remotes.contains(widget.initialRemote)
        ? widget.initialRemote
        : widget.remotes.firstOrNull;
    _branch = TextEditingController(text: widget.branch ?? '');
  }

  @override
  void dispose() {
    _branch.dispose();
    super.dispose();
  }

  /// The branches of the selected remote. Deletion leaves out its symbolic
  /// `HEAD`, which names the default branch rather than being one.
  List<String> get _remoteBranches => [
    for (final remote in widget.references.remotes)
      if (nameIs(remote.name, _remote))
        for (final branch in remote.branches)
          if (widget.kind != TransferKind.deleteBranch ||
              !nameIs(branch.name, 'HEAD'))
            utf8.decode(branch.name, allowMalformed: true),
  ];

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _remote != null &&
        (widget.kind == TransferKind.fetch || _branch.text.trim().isNotEmpty) &&
        // The deletion is leased on the fetched remote-tracking branch.
        (widget.kind != TransferKind.deleteBranch ||
            _remoteBranches.contains(_branch.text.trim()));
    // Asked here rather than by a failed pull that needs the dialog reopened.
    final needsAcknowledgement =
        widget.kind == TransferKind.pull &&
        widget.dirty &&
        !_allowDirty &&
        !_stashBeforePull;
    final title = dialogTitle(switch (widget.kind) {
      TransferKind.fetch => context.l10n.commandFetch,
      TransferKind.pull => context.l10n.commandPull,
      TransferKind.push => context.l10n.commandPush,
      TransferKind.pushTag => context.l10n.commandPushTag,
      TransferKind.deleteTag => context.l10n.commandDeleteTag,
      TransferKind.deleteBranch => context.l10n.commandDeleteRemoteBranch,
    });
    final tagKind =
        widget.kind == TransferKind.pushTag ||
        widget.kind == TransferKind.deleteTag;
    final enabled = canSubmit && !needsAcknowledgement;
    void submit() => Navigator.pop(
      context,
      TransferRequest(
        kind: widget.kind,
        remote: _remote,
        branch: widget.kind == TransferKind.fetch ? null : _branch.text.trim(),
        pullStrategy: _strategy,
        allowDirty: _allowDirty,
        stashBeforePull: _stashBeforePull,
        // Both options belong to a push; a deletion or tag
        // transfer that carried them would be refused.
        forceWithLease: widget.kind == TransferKind.push && _force,
        setUpstream:
            widget.kind == TransferKind.push &&
            _setUpstream &&
            !_branchHasUpstream,
        prune: _prune,
      ),
    );
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      scrollable: true,
      title: title,
      onSubmit: submit,
      submitDisabled: !enabled,
      description: switch (widget.kind) {
        TransferKind.fetch => context.l10n.transferFetchDescription,
        TransferKind.pull => context.l10n.transferPullDescription,
        TransferKind.push => context.l10n.transferPushDescription,
        TransferKind.pushTag => context.l10n.transferPushTagDescription,
        TransferKind.deleteBranch =>
          context.l10n.transferDeleteBranchDescription,
        _ => null,
      },
      // Labels sit above their fields; options line up with the fields'
      // leading edge (docs/design-system/components/Dialog.md).
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MeridianSpace.space6,
        children: [
          MeridianSelect<String>(
            key: const ValueKey('transfer-remote'),
            value: _remote ?? '',
            values: widget.remotes,
            valueLabel: (value) =>
                value.isEmpty ? context.l10n.transferRemote : value,
            label: context.l10n.transferRemote,
            showLabel: true,
            expand: true,
            onChanged: widget.remotes.isEmpty
                ? null
                : (value) => setState(() => _remote = value),
          ),
          if (widget.kind != TransferKind.fetch)
            GitReferenceField(
              controller: _branch,
              selectionIcon: tagKind ? 'tag' : 'branch',
              label: tagKind
                  ? context.l10n.transferTag
                  : context.l10n.transferBranch,
              names: tagKind
                  ? [
                      for (final tag in widget.references.tags)
                        utf8.decode(tag.name, allowMalformed: true),
                    ]
                  : widget.kind == TransferKind.pull ||
                        widget.kind == TransferKind.deleteBranch
                  ? _remoteBranches
                  : [
                      for (final branch in widget.references.branches)
                        utf8.decode(branch.name, allowMalformed: true),
                    ],
              helperText: widget.kind == TransferKind.pushTag
                  ? context.l10n.transferTagHelp
                  : null,
              onChanged: (_) => setState(() {}),
            ),
          if (widget.kind == TransferKind.pull)
            MeridianSelect<PullStrategy>(
              key: const ValueKey('transfer-pull-strategy'),
              expand: true,
              showLabel: true,
              value: _strategy,
              values: PullStrategy.values,
              valueLabel: (value) => switch (value) {
                PullStrategy.fastForwardOnly => context.l10n.transferFfOnly,
                PullStrategy.fastForwardIfPossible =>
                  context.l10n.transferFfPossible,
                PullStrategy.rebase => context.l10n.transferRebase,
              },
              label: context.l10n.transferPullStrategy,
              onChanged: (value) => setState(() => _strategy = value),
            ),
          if (widget.kind == TransferKind.fetch)
            MeridianCheckbox(
              key: const ValueKey('transfer-prune'),
              value: _prune,
              label: context.l10n.transferPrune,
              description: context.l10n.transferPruneHelp,
              onChanged: (value) => setState(() => _prune = value),
            ),
          if (widget.kind == TransferKind.pull && widget.dirty) ...[
            MeridianBanner(
              tone: MeridianBannerTone.info,
              message: context.l10n.transferLocalChangesHelp,
            ),
            MeridianCheckbox(
              key: const ValueKey('transfer-stash-before-pull'),
              value: _stashBeforePull,
              label: context.l10n.transferStashBeforePull,
              description: context.l10n.transferStashBeforePullHelp,
              onChanged: (value) => setState(() {
                _stashBeforePull = value;
                if (value) _allowDirty = false;
              }),
            ),
            MeridianCheckbox(
              key: const ValueKey('transfer-allow-dirty'),
              value: _allowDirty,
              label: context.l10n.transferAllowDirty,
              description: context.l10n.transferAllowDirtyHelp,
              onChanged: (value) => setState(() {
                _allowDirty = value;
                if (value) _stashBeforePull = false;
              }),
            ),
          ],
          if (widget.kind == TransferKind.push)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: MeridianSpace.space4,
              children: [
                // A branch that already has one keeps it; nothing to ask.
                if (!_branchHasUpstream)
                  MeridianCheckbox(
                    key: const ValueKey('transfer-set-upstream'),
                    value: _setUpstream,
                    label: context.l10n.transferSetUpstream,
                    description: context.l10n.transferSetUpstreamHelp,
                    onChanged: (value) => setState(() => _setUpstream = value),
                  ),
                MeridianCheckbox(
                  value: _force,
                  key: const ValueKey('transfer-force'),
                  label: context.l10n.transferForceOption,
                  description: context.l10n.transferForceHelp,
                  onChanged: (value) => setState(() => _force = value),
                ),
              ],
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
          variant:
              widget.kind == TransferKind.deleteBranch ||
                  widget.kind == TransferKind.deleteTag
              ? MeridianButtonVariant.danger
              : MeridianButtonVariant.primary,
          label: switch (widget.kind) {
            TransferKind.fetch => context.l10n.operationFetch,
            TransferKind.pull =>
              _stashBeforePull
                  ? context.l10n.transferStashPullAction
                  : context.l10n.operationPull,
            TransferKind.push => context.l10n.operationPush,
            _ => title,
          },
          disabledReason: needsAcknowledgement
              ? context.l10n.transferFailureDirty
              : null,
          onPressed: enabled ? submit : null,
        ),
      ],
    );
  }
}
