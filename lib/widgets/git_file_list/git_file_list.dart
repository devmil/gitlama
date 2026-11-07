import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../app/app_theme.dart';

/// How a file list arranges its files.
enum GitFileListMode { list, tree }

/// A folder of a file tree: disclosure chevron, folder icon and name, with
/// the same indentation and selection fill as the file rows beside it.
class GitFolderRow extends StatelessWidget {
  const GitFolderRow({
    required this.label,
    required this.depth,
    required this.collapsed,
    required this.onToggle,
    this.trailing,
    this.selected = false,
    this.loading = false,
    super.key,
  });

  final String label;
  final int depth;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget? trailing;
  final bool selected;

  /// The folder's entries are being read.
  final bool loading;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if ((event.logicalKey == LogicalKeyboardKey.arrowLeft && !collapsed) ||
          (event.logicalKey == LogicalKeyboardKey.arrowRight && collapsed)) {
        onToggle();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: MeridianListRow(
      title: label,
      selected: selected,
      semanticValue: collapsed
          ? context.l10n.gitFolderCollapsed
          : context.l10n.gitFolderExpanded,
      leading: Padding(
        padding: EdgeInsetsDirectional.only(
          start: depth * MeridianLayout.treeIndent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeridianIcon(
              collapsed ? 'chevron-right' : 'chevron-down',
              size: MeridianIconSize.small,
            ),
            const SizedBox(width: MeridianSpace.space2),
            if (loading)
              const MeridianSpinner(size: MeridianSize.icon)
            else
              MeridianIcon(
                collapsed ? 'folder-closed' : 'folder-open',
                size: MeridianIconSize.regular,
              ),
          ],
        ),
      ),
      trailing: trailing,
      onTap: onToggle,
    ),
  );
}

/// The header of a file list: title and count, an optional scope switch,
/// the list/tree switch and extra actions. Narrow headers turn the switches
/// into icon buttons.
class GitFileListHeader extends StatelessWidget {
  const GitFileListHeader({
    required this.title,
    this.count,
    this.counts = const [],
    this.scope,
    this.compactScope,
    this.mode,
    this.onModeChanged,
    this.modeKey,
    this.extraActions = const [],
    super.key,
  });

  final String title;
  final int? count;

  /// Short coloured figures after the title, such as +12 / −3.
  final List<Widget> counts;

  /// A two-valued switch shown before the mode switch, such as Changed /
  /// All files.
  final Widget? scope;

  /// Replaces [scope] in a narrow header, usually an icon button.
  final Widget? compactScope;
  final GitFileListMode? mode;
  final ValueChanged<GitFileListMode>? onModeChanged;
  final Key? modeKey;
  final List<Widget> extraActions;

  /// Below this width the scope switch becomes [compactScope].
  static const compactScopeWidth = 240.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < GitFileListModeToggle.compactWidth;
      final mode = this.mode;
      final onModeChanged = this.onModeChanged;
      final scope = constraints.maxWidth < compactScopeWidth
          ? compactScope ?? this.scope
          : this.scope;
      return MeridianSectionHeader(
        color: context.colors.paneAlt,
        size: MeridianSectionHeaderSize.small,
        title: title,
        count: count,
        caption: compact || counts.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, figure) in counts.indexed) ...[
                    if (index > 0) const SizedBox(width: MeridianSpace.space3),
                    figure,
                  ],
                ],
              ),
        actions: [
          ?scope,
          if (mode != null && onModeChanged != null)
            GitFileListModeToggle(
              mode: mode,
              onChanged: onModeChanged,
              compact: compact,
              toggleKey: modeKey,
            ),
          ...extraActions,
        ],
      );
    },
  );
}

/// Switches a file list between a flat list and a folder tree: a segmented
/// control, or one icon button when [compact] (a header narrower than
/// [compactWidth]).
class GitFileListModeToggle extends StatelessWidget {
  const GitFileListModeToggle({
    required this.mode,
    required this.onChanged,
    this.compact = false,
    this.label,
    this.toggleKey,
    super.key,
  });

  final GitFileListMode mode;
  final ValueChanged<GitFileListMode> onChanged;
  final bool compact;

  /// The segmented control's accessible name; "Show files as a list" by
  /// default.
  final String? label;

  /// The key of the segmented control or the icon button.
  final Key? toggleKey;

  /// Below this header width the switch becomes an icon button.
  static const compactWidth = 350.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (compact) {
      final list = mode == GitFileListMode.list;
      return MeridianIconButton(
        key: toggleKey,
        label: list ? l10n.changesTreeView : l10n.changesListView,
        icon: list ? 'tree-view' : 'list-view',
        size: MeridianControlSize.small,
        onPressed: () =>
            onChanged(list ? GitFileListMode.tree : GitFileListMode.list),
      );
    }
    return MeridianSegmented<GitFileListMode>(
      key: toggleKey,
      label: label ?? l10n.changesListView,
      segments: [
        for (final value in GitFileListMode.values)
          MeridianSegment(
            value: value,
            icon: value == GitFileListMode.list ? 'list-view' : 'tree-view',
            tooltip: value == GitFileListMode.list
                ? l10n.changesListView
                : l10n.changesTreeView,
          ),
      ],
      value: mode,
      onChanged: onChanged,
      size: MeridianControlSize.small,
    );
  }
}

/// A virtualized list or tree of files. It owns which folders are
/// collapsed; the caller builds the file rows and any folder trailing.
class GitFileList<T> extends StatefulWidget {
  const GitFileList({
    required this.items,
    required this.displayPath,
    required this.mode,
    required this.fileRowBuilder,
    this.folderBuilder,
    this.leadingRows = const [],
    this.tailRow,
    this.listKey,
    this.controller,
    this.folderKey,
    this.reveal,
    this.preserveOrder = false,
    super.key,
  });

  final List<T> items;

  /// The '/'-separated path a file is listed under.
  final String Function(T) displayPath;
  final GitFileListMode mode;
  final Widget Function(BuildContext context, MeridianPathTreeRow<T> row)
  fileRowBuilder;

  /// Wraps a folder row, for example with its context menu.
  final Widget Function(
    BuildContext context,
    MeridianPathTreeRow<T> row,
    Widget folder,
  )?
  folderBuilder;

  /// Rows above the files, such as "All changes".
  final List<Widget> leadingRows;

  /// A row below the files, such as "Load more".
  final Widget? tailRow;
  final Key? listKey;
  final ScrollController? controller;

  /// The key of a folder row by its identity.
  final Key Function(String identity)? folderKey;

  /// A folder identity to expand, with every folder above it.
  final ValueListenable<String?>? reveal;

  /// Keeps [items] in their given order in list mode, for lists whose order
  /// carries meaning, such as a conflict queue.
  final bool preserveOrder;

  @override
  State<GitFileList<T>> createState() => _GitFileListState<T>();
}

class _GitFileListState<T> extends State<GitFileList<T>> {
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    widget.reveal?.addListener(_reveal);
  }

  @override
  void didUpdateWidget(covariant GitFileList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reveal != widget.reveal) {
      oldWidget.reveal?.removeListener(_reveal);
      widget.reveal?.addListener(_reveal);
    }
  }

  @override
  void dispose() {
    widget.reveal?.removeListener(_reveal);
    super.dispose();
  }

  void _reveal() {
    final identity = widget.reveal?.value;
    if (identity == null) return;
    setState(
      () => _collapsed.removeWhere(
        (folder) => identity == folder || identity.startsWith('$folder/'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.preserveOrder && widget.mode == GitFileListMode.list
        ? [
            for (final item in widget.items)
              MeridianPathTreeRow<T>.file(
                item: item,
                identity: widget.displayPath(item),
                label: widget.displayPath(item),
                depth: 0,
              ),
          ]
        : MeridianPathTree.flatten<T>(
            widget.items,
            pathOf: widget.displayPath,
            collapsed: _collapsed,
            tree: widget.mode == GitFileListMode.tree,
          );
    final leading = widget.leadingRows;
    final tail = widget.tailRow;
    return ListView.builder(
      key: widget.listKey,
      controller: widget.controller,
      itemCount: leading.length + rows.length + (tail == null ? 0 : 1),
      itemExtent: context.meridian.density.rowExtent,
      itemBuilder: (context, index) {
        if (index < leading.length) return leading[index];
        final rowIndex = index - leading.length;
        if (rowIndex >= rows.length) return tail!;
        final row = rows[rowIndex];
        if (!row.directory) return widget.fileRowBuilder(context, row);
        final collapsed = _collapsed.contains(row.identity);
        final folder = GitFolderRow(
          key: widget.folderKey?.call(row.identity),
          label: row.label,
          depth: row.depth,
          collapsed: collapsed,
          onToggle: () => setState(() {
            if (!_collapsed.remove(row.identity)) {
              _collapsed.add(row.identity);
            }
          }),
        );
        return widget.folderBuilder?.call(context, row, folder) ?? folder;
      },
    );
  }
}
