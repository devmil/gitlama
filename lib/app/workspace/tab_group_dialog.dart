import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/repository_appearance.dart';
import '../../models/workspace.dart';
import '../../widgets/appearance_color_row.dart';
import '../../widgets/native_menu.dart';
import '../../widgets/repository_icon.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';
import 'repository_icon_dialog.dart';

/// What the group editor saves.
typedef TabGroupEdit = ({String name, AppearanceColor color, String? icon});

/// Lets a person set a tab group's name, colour and icon at once, with the
/// group as the tab bar will show it. Completes with the edit, or `null`
/// when it was cancelled.
Future<TabGroupEdit?> showTabGroupDialog(
  BuildContext context, {
  required RepositoryTabGroup group,
  required List<String> tabLabels,
}) => showMeridianDialog<TabGroupEdit>(
  context: context,
  builder: (context) => TabGroupDialog(group: group, tabLabels: tabLabels),
);

class TabGroupDialog extends StatefulWidget {
  const TabGroupDialog({
    required this.group,
    required this.tabLabels,
    super.key,
  });

  final RepositoryTabGroup group;

  /// The group's tabs in order, as their tabs name them.
  final List<String> tabLabels;

  @override
  State<TabGroupDialog> createState() => _TabGroupDialogState();
}

class _TabGroupDialogState extends State<TabGroupDialog> {
  late final _name = TextEditingController(text: widget.group.name);
  late AppearanceColor _color = widget.group.color;
  late String? _icon = repositoryAppearanceIcons.contains(widget.group.icon)
      ? widget.group.icon
      : null;

  @override
  void initState() {
    super.initState();
    _name.addListener(_nameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_nameChanged)
      ..dispose();
    super.dispose();
  }

  void _nameChanged() => setState(() {});

  void _save() => Navigator.pop<TabGroupEdit>(context, (
    name: normalizeTabName(_name.text) ?? '',
    color: _color,
    icon: _icon,
  ));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tint = repositoryAppearanceColor(context, _color);
    return MeridianDialog(
      width: MeridianLayout.dialogFormWidth,
      title: l10n.tabGroupEditTitle,
      description: l10n.tabGroupEditDescription,
      onSubmit: _save,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Preview(
            group: RepositoryTabGroup(
              id: widget.group.id,
              color: _color,
              name: normalizeTabName(_name.text) ?? '',
              icon: _icon,
            ),
            tabLabels: widget.tabLabels,
          ),
          const SizedBox(height: MeridianSpace.space6),
          MeridianTextField(
            key: const ValueKey('tab-group-name'),
            controller: _name,
            label: l10n.tabGroupEditName,
            placeholder: l10n.tabGroupNamePlaceholder,
            autofocus: true,
            textInputAction: TextInputAction.done,
            contextMenuBuilder: nativeTextContextMenuBuilder,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: MeridianSpace.space6),
          AppearanceHeading(l10n.tabGroupColor),
          AppearanceColorRow(
            value: _color,
            onChanged: (color) {
              if (color != null) setState(() => _color = color);
            },
          ),
          const SizedBox(height: MeridianSpace.space6),
          AppearanceHeading(l10n.tabGroupIcon),
          Wrap(
            spacing: MeridianSpace.space2,
            runSpacing: MeridianSpace.space2,
            children: [
              MeridianIconButton(
                key: const ValueKey('tab-group-icon-none'),
                label: l10n.repositoryIconNone,
                icon: 'ban',
                size: MeridianControlSize.small,
                active: _icon == null,
                onPressed: () => setState(() => _icon = null),
              ),
              for (final icon in repositoryAppearanceIcons)
                MeridianIconButton(
                  key: ValueKey('tab-group-icon-$icon'),
                  label: repositoryIconLabel(context, icon),
                  icon: icon,
                  size: MeridianControlSize.small,
                  color: tint,
                  active: _icon == icon,
                  onPressed: () => setState(() => _icon = icon),
                ),
            ],
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.cancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        MeridianButton(
          key: const ValueKey('tab-group-save'),
          label: l10n.tabGroupEditSave,
          variant: MeridianButtonVariant.primary,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// The group as the tab bar will show it: its chip and its first tabs on
/// the tab bar's ground.
class _Preview extends StatelessWidget {
  const _Preview({required this.group, required this.tabLabels});

  final RepositoryTabGroup group;
  final List<String> tabLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = tabLabels.take(GitLamaLayout.tabGroupPreviewTabs);
    return Semantics(
      key: const ValueKey('tab-group-preview'),
      label: l10n.tabGroupEditPreview,
      container: true,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: Container(
            height: MeridianLayout.tabStripHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: MeridianSpace.space3,
            ),
            decoration: BoxDecoration(
              color: context.colors.ground,
              borderRadius: BorderRadius.circular(context.meridian.radius.md),
              border: Border.all(color: context.colors.line),
            ),
            child: MeridianTabStrip<int, int>(
              tabs: [
                for (final (index, label) in labels.indexed)
                  MeridianStripTab(
                    id: index,
                    label: label,
                    group: group.id,
                    renamable: false,
                  ),
              ],
              groups: [
                MeridianStripGroup(
                  id: group.id,
                  color: repositoryAppearanceColor(context, group.color),
                  name: group.name,
                  icon: group.icon,
                  label: l10n.tabGroupUnnamed(
                    repositoryColorLabel(context, group.color),
                  ),
                ),
              ],
              activeTab: 0,
              onActivate: (_) {},
            ),
          ),
        ),
      ),
    );
  }
}
