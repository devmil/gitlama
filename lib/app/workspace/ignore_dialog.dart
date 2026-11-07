import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/repository_extensions.dart';
import '../../models/repository_state.dart';
import '../../widgets/native_menu.dart';
import '../../widgets/status_notification.dart';

/// Adds [pattern] to the repository's top-level `.gitignore`.
typedef AddIgnorePattern =
    Future<RepositoryExtensionMutationResult> Function(String pattern);

/// Asks for the `.gitignore` entry that hides a changed path, prefilled with
/// [suggestion], the entry that matches exactly that path, and adds it.
Future<void> showIgnoreDialog(
  BuildContext context, {
  required String suggestion,
  required bool directory,
  required bool tracked,
  required AddIgnorePattern onAdd,
}) => showMeridianDialog<void>(
  context: context,
  builder: (context) => IgnoreDialog(
    suggestion: suggestion,
    directory: directory,
    tracked: tracked,
    onAdd: onAdd,
  ),
);

class IgnoreDialog extends StatefulWidget {
  const IgnoreDialog({
    required this.suggestion,
    required this.directory,
    required this.tracked,
    required this.onAdd,
    super.key,
  });

  final String suggestion;
  final bool directory;

  /// Whether Git already tracks the path, which an entry does not hide.
  final bool tracked;
  final AddIgnorePattern onAdd;

  @override
  State<IgnoreDialog> createState() => _IgnoreDialogState();
}

class _IgnoreDialogState extends State<IgnoreDialog> {
  late final _entry = TextEditingController(text: widget.suggestion);
  bool _busy = false;
  RepositoryExtensionFailureCode? _failure;

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  bool get _empty => _entry.text.trim().isEmpty;

  Future<void> _add() async {
    if (_busy || _empty) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final result = await widget.onAdd(_entry.text);
      if (!mounted) return;
      if (result.reportedFailure case final failure?) {
        setState(() => _failure = failure);
        return;
      }
      if (result.state == RepositoryExtensionMutationState.outcomeUncertain) {
        StatusNotificationScope.show(
          context,
          context.l10n.mutationOutcomeUncertain,
          error: true,
        );
      }
      Navigator.pop(context);
    } on RemoteOutcomeUnknownException {
      if (!mounted) return;
      Navigator.pop(context);
      showRemoteOutcomeUnknown(context);
    } on RepositoryExtensionException catch (error) {
      if (mounted) setState(() => _failure = error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final description = widget.directory
        ? l10n.ignoreDialogFolderDescription
        : l10n.ignoreDialogFileDescription;
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: l10n.ignoreDialogTitle,
      description: widget.tracked
          ? '$description ${l10n.ignoreDialogTrackedNote}'
          : description,
      onSubmit: _add,
      submitDisabled: _busy || _empty,
      content: MeridianTextField(
        fieldKey: const Key('ignore-entry'),
        controller: _entry,
        label: l10n.ignoreDialogEntry,
        message: l10n.ignoreDialogEntryHint,
        error: switch (_failure) {
          null => null,
          RepositoryExtensionFailureCode.invalidRequest =>
            l10n.ignoreFailureInvalid,
          _ => l10n.ignoreFailureWrite,
        },
        monospace: true,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !_busy,
        contextMenuBuilder: nativeTextContextMenuBuilder,
        onChanged: (_) => setState(() => _failure = null),
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('ignore-add'),
          label: l10n.ignoreDialogAdd,
          variant: MeridianButtonVariant.primary,
          loading: _busy,
          onPressed: _busy || _empty ? null : _add,
        ),
      ],
    );
  }
}
