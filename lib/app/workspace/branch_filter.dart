import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../models/branch_order.dart';
import '../../models/history.dart';
import '../../models/reference_name.dart';
import '../../models/repository_state.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';

/// One branch the history graph can be filtered to.
final class BranchFilterChoice {
  BranchFilterChoice({
    required this.reference,
    required this.label,
    this.current = false,
    this.upstream,
    this.remote,
  }) : _folded = label.toLowerCase();

  /// The full reference name, such as `refs/remotes/origin/main`.
  final String reference;

  /// The name people know it by: `main`, `origin/main`.
  final String label;

  /// The remote of a remote-tracking branch; null for a local branch.
  final String? remote;

  /// The name within its local or remote group: `main` for `origin/main`.
  String get name => switch (remote) {
    final remote? when label.startsWith('$remote/') => label.substring(
      remote.length + 1,
    ),
    _ => label,
  };

  /// The checked-out branch.
  final bool current;

  /// The full name of the branch this one tracks, shown along with it.
  final String? upstream;

  final String _folded;

  bool matches(String foldedNeedle) =>
      foldedNeedle.isEmpty || _folded.contains(foldedNeedle);
}

/// Local branches and then remote branches of [refs], the main branch first
/// in each and the checked-out branch next among the local ones. Names that
/// are not valid UTF-8 cannot round-trip through the filter and are left out;
/// a remote's symbolic `HEAD` names no branch.
List<BranchFilterChoice> buildBranchFilterChoices(RepositoryRefs refs) {
  String? name(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  // The main branch keeps the first place when another one is checked out.
  final main = mainBranchOf(refs.branches);
  final others = refs.branches.where((branch) => !identical(branch, main));
  return [
    for (final branch in [
      ?main,
      ...others.where((branch) => branch.head),
      ...others.where((branch) => !branch.head),
    ])
      if (name(branch.name) case final value?)
        BranchFilterChoice(
          reference: branchReference(branch).fullText,
          label: value,
          current: branch.head,
          upstream: filterUpstream(branch),
        ),
    for (final remote in refs.remotes)
      if (name(remote.name) case final remoteName?)
        for (final branch in mainBranchFirst(remote.branches))
          if (name(branch.name) case final value? when value != 'HEAD')
            BranchFilterChoice(
              reference: remoteBranchReference(remote, branch).fullText,
              label: '$remoteName/$value',
              remote: remoteName,
            ),
  ];
}

/// Whether [reference] names a branch the graph can be filtered to.
bool isFilterableBranch(String reference) {
  final name = ReferenceName.parse(reference);
  return name.kind == ReferenceKind.localBranch ||
      (name.kind == ReferenceKind.remoteBranch && !name.isRemoteHead);
}

/// The branch shown along with [branch] in the graph filter: the one it
/// tracks, when the graph can be filtered to it.
String? filterUpstream(RepositoryReference branch) =>
    switch (upstreamReference(branch)) {
      final upstream? when isFilterableBranch(upstream) => upstream,
      _ => null,
    };

/// The graph-filter commands for one branch, as shown in its context menu:
/// focus on it unless that is already the case, add or remove it, and show
/// everything again while a filter is active. Focusing on or adding a branch
/// brings the [upstream] it tracks, which is removed like any other branch.
List<({String title, HistoryBranchFilter filter})> branchFilterMenuActions(
  AppLocalizations l10n,
  HistoryBranchFilter current,
  String reference, {
  String? upstream,
}) => [
  if (!current.isFocusedOn(reference, upstream: upstream))
    (
      title: l10n.historyBranchFilterFocus,
      filter: HistoryBranchFilter.focus(reference, upstream: upstream),
    ),
  if (current.contains(reference))
    (title: l10n.historyBranchFilterRemove, filter: current.toggled(reference))
  else if (current.length < HistoryBranchFilter.maximumReferences)
    (
      title: l10n.historyBranchFilterAdd,
      filter: current.toggled(reference, upstream: upstream),
    ),
  if (current.isNotEmpty)
    (title: l10n.historyBranchFilterShowAll, filter: HistoryBranchFilter.none),
];

/// The active repository's branch filter for the sidebar below it. Menus
/// [read] it when they open; rows that mark filtered branches depend on it
/// through [filterOf] and rebuild only when the filter changes.
class BranchFilterScope extends InheritedWidget {
  const BranchFilterScope({
    required this.filter,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final HistoryBranchFilter filter;
  final ValueChanged<HistoryBranchFilter> onChanged;

  static BranchFilterScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BranchFilterScope>();

  static HistoryBranchFilter filterOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BranchFilterScope>()?.filter ??
      HistoryBranchFilter.none;

  @override
  bool updateShouldNotify(BranchFilterScope oldWidget) =>
      filter != oldWidget.filter;
}

/// The history toolbar's branch filter: shows how many branches the graph is
/// limited to and opens [BranchFilterEditor].
class BranchFilterButton extends StatelessWidget {
  const BranchFilterButton({
    required this.filter,
    required this.choices,
    required this.onChanged,
    super.key,
  });

  final HistoryBranchFilter filter;

  /// Built when the editor opens, from the references known at that moment.
  final List<BranchFilterChoice> Function() choices;
  final ValueChanged<HistoryBranchFilter> onChanged;

  @override
  Widget build(BuildContext context) => MeridianPopoverAnchor(
    width: GitLamaLayout.branchFilterWidth,
    builder: (context, open) => MeridianButton(
      key: const ValueKey('history-branch-filter'),
      label: filter.isEmpty
          ? context.l10n.historyBranchFilter
          : context.l10n.historyBranchFilterCount(filter.length),
      tooltip: context.l10n.historyBranchFilterTooltip,
      icon: 'git-branch',
      trailingIcon: 'chevron-down',
      variant: filter.isEmpty
          ? MeridianButtonVariant.quiet
          : MeridianButtonVariant.secondary,
      size: MeridianControlSize.small,
      onPressed: open,
    ),
    popoverBuilder: (context) => BranchFilterEditor(
      choices: choices(),
      filter: filter,
      onChanged: onChanged,
    ),
  );
}

/// A group, folder or branch of the branch filter tree. Groups hold the local
/// branches and each remote's; folders split names at `/` like the sidebar.
final class _BranchFilterNode {
  _BranchFilterNode.folder(this.path, this.name, this.children) : choice = null;

  _BranchFilterNode.branch(BranchFilterChoice this.choice, this.name)
    : path = choice.reference,
      children = const [];

  /// Unique among all nodes: the reference of a branch, a `/`-terminated
  /// prefix of a folder.
  final String path;
  final String name;
  final BranchFilterChoice? choice;
  final List<_BranchFilterNode> children;

  late final List<BranchFilterChoice> branches = switch (choice) {
    final choice? => [choice],
    null => [for (final child in children) ...child.branches],
  };
}

/// Folders of [items] below [path], in the order their first branch comes.
List<_BranchFilterNode> _branchFilterFolders(
  List<(String, BranchFilterChoice)> items,
  String path,
) {
  final groups = <String, List<(String, BranchFilterChoice)>>{};
  for (final item in items) {
    groups.putIfAbsent(item.$1.split('/').first, () => []).add(item);
  }
  return [
    for (final MapEntry(key: segment, value: group) in groups.entries)
      if (group.length == 1 && group.single.$1 == segment)
        _BranchFilterNode.branch(group.single.$2, segment)
      else
        _BranchFilterNode.folder(
          '$path$segment/',
          segment,
          _branchFilterFolders([
            for (final (name, choice) in group)
              if (name.length > segment.length)
                (name.substring(segment.length + 1), choice),
          ], '$path$segment/'),
        ),
  ];
}

/// A local branch's name, or a remote branch's with its remote.
String _branchLabel(String reference) {
  final name = ReferenceName.parse(reference);
  return switch (name.kind) {
    ReferenceKind.localBranch || ReferenceKind.remoteBranch => name.display,
    _ => reference,
  };
}

typedef _BranchFilterRow = ({_BranchFilterNode node, int depth, bool open});

/// Picks the branches the history graph shows, as a tree of local branches
/// and each remote's. Clicking a branch adds or removes it and applies at
/// once; double-click, Enter or the row's focus action shows only that branch
/// and closes. A local branch brings the branch it tracks, which has a row of
/// its own to remove it again. Typing narrows the tree to matching branches
/// and opens every folder; Up and Down move, Space toggles (branch names
/// cannot contain spaces) and Enter or Space opens and closes a folder.
class BranchFilterEditor extends StatefulWidget {
  const BranchFilterEditor({
    required this.choices,
    required this.filter,
    required this.onChanged,
    super.key,
  });

  final List<BranchFilterChoice> choices;
  final HistoryBranchFilter filter;
  final ValueChanged<HistoryBranchFilter> onChanged;

  @override
  State<BranchFilterEditor> createState() => _BranchFilterEditorState();
}

class _BranchFilterEditorState extends State<BranchFilterEditor> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late HistoryBranchFilter _filter = widget.filter;
  List<_BranchFilterNode>? _tree;
  late Set<String> _open;
  List<_BranchFilterRow> _rows = const [];
  var _cursor = 0;

  BranchFilterChoice? get _current =>
      widget.choices.where((choice) => choice.current).firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tree != null) return;
    final tree = _tree = _buildTree(context.l10n.workspaceBranches);
    // Groups start open, and so does every folder holding the checked-out
    // branch or one the graph shows, so neither is hidden.
    _open = {
      for (final node in tree)
        if (node.choice == null) node.path,
    };
    void reveal(List<_BranchFilterNode> nodes) {
      for (final node in nodes) {
        if (node.choice != null) continue;
        if (node.branches.any(
          (choice) => choice.current || _filter.contains(choice.reference),
        )) {
          _open.add(node.path);
        }
        reveal(node.children);
      }
    }

    reveal(tree);
    _rows = _flatten();
  }

  /// References the repository no longer lists stay on top while filtered,
  /// so they can be removed; then local branches and each remote's.
  List<_BranchFilterNode> _buildTree(String localLabel) {
    final known = {for (final choice in widget.choices) choice.reference};
    final remotes = <String, List<(String, BranchFilterChoice)>>{};
    final local = <(String, BranchFilterChoice)>[];
    for (final choice in widget.choices) {
      if (choice.remote case final remote?) {
        remotes.putIfAbsent(remote, () => []).add((choice.name, choice));
      } else {
        local.add((choice.name, choice));
      }
    }
    return [
      for (final reference in widget.filter.references)
        if (!known.contains(reference))
          _BranchFilterNode.branch(
            BranchFilterChoice(
              reference: reference,
              label: _branchLabel(reference),
            ),
            _branchLabel(reference),
          ),
      if (local.isNotEmpty)
        _BranchFilterNode.folder(
          'refs/heads/',
          localLabel,
          _branchFilterFolders(local, 'refs/heads/'),
        ),
      for (final MapEntry(key: remote, value: items) in remotes.entries)
        _BranchFilterNode.folder(
          'refs/remotes/$remote/',
          remote,
          _branchFilterFolders(items, 'refs/remotes/$remote/'),
        ),
    ];
  }

  /// The visible rows. While searching, only matching branches and the
  /// folders holding them, all open.
  List<_BranchFilterRow> _flatten() {
    final needle = _query.text.trim().toLowerCase();
    final searching = needle.isNotEmpty;
    final rows = <_BranchFilterRow>[];
    bool visit(List<_BranchFilterNode> nodes, int depth) {
      var any = false;
      for (final node in nodes) {
        if (node.choice case final choice?) {
          if (!choice.matches(needle)) continue;
          rows.add((node: node, depth: depth, open: false));
          any = true;
          continue;
        }
        final open = searching || _open.contains(node.path);
        final at = rows.length;
        rows.add((node: node, depth: depth, open: open));
        if (!open) {
          any = true;
        } else if (visit(node.children, depth + 1) || !searching) {
          any = true;
        } else {
          rows.removeAt(at);
        }
      }
      return any;
    }

    visit(_tree!, 0);
    return rows;
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search(String value) {
    setState(() {
      _rows = _flatten();
      // On the first matching branch, so Enter shows it rather than folding
      // the folder above it.
      _cursor = math.max(0, _rows.indexWhere((row) => row.node.choice != null));
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _apply(HistoryBranchFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    widget.onChanged(filter);
  }

  /// Toggles the branch at [index] in the filter, or opens or closes the
  /// folder there.
  void _toggle(int index) {
    setState(() => _cursor = index);
    final node = _rows[index].node;
    if (node.choice case final choice?) {
      _apply(_filter.toggled(choice.reference, upstream: choice.upstream));
    } else if (_query.text.trim().isEmpty) {
      setState(() {
        if (!_open.remove(node.path)) _open.add(node.path);
        _rows = _flatten();
      });
    }
  }

  void _focus(BranchFilterChoice choice) {
    _apply(
      HistoryBranchFilter.focus(choice.reference, upstream: choice.upstream),
    );
    Navigator.of(context).maybePop();
  }

  void _showAll() {
    _apply(HistoryBranchFilter.none);
    Navigator.of(context).maybePop();
  }

  void _move(int delta) {
    if (_rows.isEmpty) return;
    final next = (_cursor + delta).clamp(0, _rows.length - 1);
    setState(() => _cursor = next);
    if (!_scroll.hasClients) return;
    final extent = context.meridian.density.rowExtent;
    final top = next * extent;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + extent > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + extent - position.viewportDimension);
    }
  }

  Widget _row(BuildContext context, int index, String needle) {
    final l10n = context.l10n;
    final colors = context.colors;
    final (:node, :depth, :open) = _rows[index];
    final selected = index == _cursor;
    final strong = MeridianRowColors.resolve(
      context,
      selected: selected,
      hovered: false,
    ).strong;
    Widget leading(Widget? chevron, Widget? icon) => Padding(
      padding: EdgeInsetsDirectional.only(
        start: depth * MeridianLayout.treeIndent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: MeridianLayout.chevronSize,
            child: chevron,
          ),
          const SizedBox(width: MeridianSpace.space3),
          SizedBox.square(dimension: MeridianSize.icon, child: icon),
        ],
      ),
    );

    final choice = node.choice;
    if (choice == null) {
      final shown = node.branches
          .where((choice) => _filter.contains(choice.reference))
          .length;
      return MeridianListRow(
        key: ValueKey(node.path),
        title: node.name,
        selected: selected,
        semanticValue: shown == 0
            ? null
            : l10n.historyBranchFilterSummary(shown),
        leading: leading(
          MeridianIcon(
            open ? 'chevron-down' : 'chevron-right',
            size: MeridianIconSize.small,
            color: strong ? colors.onAccent : colors.inkMuted,
          ),
          MeridianIcon(
            'folder-closed',
            size: MeridianIconSize.small,
            color: strong ? colors.onAccent : colors.inkMuted,
          ),
        ),
        trailing: shown == 0
            ? null
            : MeridianCount(
                label: '$shown',
                semanticLabel: l10n.historyBranchFilterSummary(shown),
              ),
        onTap: () => _toggle(index),
      );
    }
    final shown = _filter.contains(choice.reference);
    return MeridianListRow(
      key: ValueKey(node.path),
      title: node.name,
      match: needle.isEmpty ? null : needle,
      selected: selected,
      emphasized: choice.current,
      semanticValue: shown ? l10n.historyBranchFilterShown : null,
      leading: leading(
        null,
        shown
            ? MeridianIcon(
                'check',
                color: strong ? colors.onAccent : colors.accent,
              )
            : null,
      ),
      hoverActions: [
        MeridianIconButton(
          label: l10n.historyBranchFilterFocus,
          icon: 'focus',
          size: MeridianControlSize.small,
          onPressed: () => _focus(choice),
        ),
      ],
      onTap: () => _toggle(index),
      onDoubleTap: () => _focus(choice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final extent = context.meridian.density.rowExtent;
    final needle = _query.text.trim();
    final current = _current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(MeridianSpace.space3),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
              const SingleActivator(LogicalKeyboardKey.space): () {
                if (_rows.isNotEmpty) _toggle(_cursor);
              },
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (_rows.isEmpty) return;
                if (_rows[_cursor].node.choice case final choice?) {
                  _focus(choice);
                } else {
                  _toggle(_cursor);
                }
              },
            },
            child: MeridianTextField(
              fieldKey: const ValueKey('branch-filter-search'),
              controller: _query,
              variant: MeridianTextFieldVariant.search,
              size: MeridianControlSize.small,
              placeholder: l10n.historyBranchFilterSearch,
              clearLabel: l10n.searchClear,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _search,
            ),
          ),
        ),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(MeridianSpace.space4),
            child: Text(
              l10n.historyBranchFilterNoMatches,
              textAlign: TextAlign.center,
              style: context.text.caption.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          )
        else
          SizedBox(
            height: (_rows.length * extent).clamp(
              0.0,
              GitLamaLayout.branchFilterListMaxHeight,
            ),
            child: ListView.builder(
              key: const ValueKey('branch-filter-list'),
              controller: _scroll,
              itemExtent: extent,
              itemCount: _rows.length,
              itemBuilder: (context, index) => _row(context, index, needle),
            ),
          ),
        const MeridianHairline(),
        Padding(
          padding: const EdgeInsets.all(MeridianSpace.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.historyBranchFilterHelp,
                style: context.text.caption.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: MeridianSpace.space2),
              Text(
                l10n.historyBranchFilterSummary(_filter.length),
                key: const ValueKey('branch-filter-summary'),
                overflow: TextOverflow.ellipsis,
                style: context.text.caption.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: MeridianSpace.space3),
              // Wraps instead of overflowing with long translations.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: MeridianSpace.space2,
                runSpacing: MeridianSpace.space2,
                children: [
                  if (current != null)
                    MeridianButton(
                      key: const ValueKey('branch-filter-current'),
                      label: l10n.historyBranchFilterCurrent,
                      variant: MeridianButtonVariant.quiet,
                      size: MeridianControlSize.small,
                      onPressed: () => _focus(current),
                    ),
                  MeridianButton(
                    key: const ValueKey('branch-filter-show-all'),
                    label: l10n.historyBranchFilterShowAll,
                    size: MeridianControlSize.small,
                    onPressed: _filter.isEmpty ? null : _showAll,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
