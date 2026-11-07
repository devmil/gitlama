import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../app_shortcut_activator.dart';
import '../app_theme.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

class ShortcutReferenceDialog extends StatefulWidget {
  const ShortcutReferenceDialog({super.key, required this.shortcuts});

  /// The shortcut each command shows, see [AppShortcutCatalog.shown].
  final Map<AppCommandId, AppShortcut?> shortcuts;

  @override
  State<ShortcutReferenceDialog> createState() =>
      _ShortcutReferenceDialogState();
}

class _ShortcutReferenceDialogState extends State<ShortcutReferenceDialog> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final commands = AppCommandRegistry.commands
        .where((command) => widget.shortcuts[command.id] != null)
        .where(
          (command) =>
              query.isEmpty ||
              commandLabel(context, command.id).toLowerCase().contains(query) ||
              platformShortcutLabel(
                widget.shortcuts[command.id]!,
              ).toLowerCase().contains(query),
        )
        .toList(growable: false);
    // Conflicts among the shortcuts in effect, including the user's own.
    final conflicts = <String, List<AppCommandDefinition>>{};
    for (final command in AppCommandRegistry.commands) {
      final shortcut = widget.shortcuts[command.id];
      if (shortcut != null) {
        conflicts
            .putIfAbsent(platformShortcutLabel(shortcut), () => [])
            .add(command);
      }
    }
    final conflictGroups = conflicts.entries
        .where((entry) => entry.value.length > 1)
        .toList(growable: false);
    return MeridianDialog(
      width: MeridianLayout.dialogWorkflowWidth,
      onClose: () => Navigator.pop(context),
      title: context.l10n.shortcutReferenceTitle,
      content: SizedBox(
        height: GitLamaLayout.shortcutReferenceBodyHeight,
        child: Column(
          children: [
            MeridianTextField(
              fieldKey: const Key('shortcut-search'),
              controller: _search,
              autofocus: true,
              label: context.l10n.shortcutSearch,
              icon: 'search',
              variant: MeridianTextFieldVariant.search,
              clearLabel: context.l10n.searchClear,
              onChanged: (_) => setState(() {}),
            ),
            if (conflictGroups.isNotEmpty) ...[
              const SizedBox(height: MeridianSpace.space5),
              Semantics(
                container: true,
                readOnly: true,
                label: context.l10n.shortcutConflictTitle,
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
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: MeridianCount(
                            label: context.l10n.shortcutConflictTitle,
                          ),
                        ),
                        for (final conflict in conflictGroups)
                          Text(
                            context.l10n.shortcutConflictDetail(
                              conflict.key,
                              conflict.value
                                  .map(
                                    (value) => commandLabel(context, value.id),
                                  )
                                  .join(', '),
                            ),
                            style: context.text.caption.copyWith(
                              color: context.colors.inkMuted,
                            ),
                          ),
                        Text(
                          context.l10n.shortcutConflictWinner,
                          style: context.text.caption.copyWith(
                            color: context.colors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: MeridianSpace.space3),
            Expanded(
              child: ListView(
                children: [
                  for (final group in AppCommandGroup.values)
                    if (commands.any((command) => command.group == group)) ...[
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: MeridianSpace.space4,
                          top: MeridianSpace.space5,
                          bottom: MeridianSpace.space2,
                        ),
                        child: Text(
                          commandGroupLabel(context, group).toUpperCase(),
                          style: context.text.overline.copyWith(
                            color: context.colors.inkMuted,
                          ),
                        ),
                      ),
                      for (final command in commands.where(
                        (command) => command.group == group,
                      ))
                        MeridianListRow(
                          leading: MeridianIcon(command.icon),
                          title: commandLabel(context, command.id),
                          subtitle: commandGroupLabel(context, command.group),
                          trailing: MeridianKbd(
                            keys: platformShortcutKeys(
                              widget.shortcuts[command.id]!,
                            ),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
