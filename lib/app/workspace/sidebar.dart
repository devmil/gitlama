import 'command_availability.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/branch_order.dart';
import '../../models/reference_name.dart';
import '../../models/history.dart';
import '../../models/hosting.dart';
import '../../models/repository_state.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_extensions.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../app_shortcut_activator.dart';
import '../../services/repository_session_service.dart';
import '../app_theme.dart';
import 'branch_filter.dart';
import 'remote_workspace.dart';
import 'repository_extensions.dart';
import 'status_bar.dart';
import 'labels.dart';
import 'reference_menu.dart';
import 'package:meridian_ui/meridian_ui.dart';
export '../../models/working_tree.dart' show hasActiveConflicts;
import '../gitlama_layout.dart';
import '../../widgets/keyboard_reveal.dart';
import '../../widgets/gitlama_git_glyphs.dart';
import '../../widgets/status_notification.dart';
import '../../widgets/hosting_status.dart';
import '../../models/git_names.dart';
import '../../services/workflows/workspace_navigator.dart';
import 'workspace_scope.dart';
import 'shell_scopes.dart';

typedef RunAppCommand =
    void Function(
      AppCommandId id, {
      String? initialName,
      String? initialTarget,
      String? initialReference,
      bool force,
    });

/// A context-menu action of one sidebar entry that is not an app command
/// (a worktree's folder or deletion).
class SidebarAction {
  const SidebarAction({
    required this.label,
    required this.onSelected,
    this.enabled = true,
    this.danger = false,
  });

  final String label;
  final VoidCallback onSelected;
  final bool enabled;

  /// The action deletes or discards something; it is marked and shown last.
  final bool danger;
}

class SidebarEntry {
  const SidebarEntry({
    required this.name,
    required this.subtitle,
    required this.commands,
    this.actions = const [],
    this.treePath,
    this.primaryCommand,
    this.target,
    this.commandName,
    this.mergeDropTarget = false,
    this.draggableMergeSource = false,
    this.current = false,
    this.currentDescription,
    this.containsCurrent = false,
    this.onActivate,
    this.hostingCheck,
    this.hostingCheckBranch,
    this.hostingMergeability = HostingMergeability.unknown,
    this.trackingDescription,
    this.ahead = 0,
    this.behind = 0,
    this.children = const [],
    this.filterReference,
    this.filterUpstream,
    this.revealReference,
    this.icon,
  });

  final String name;
  final String subtitle;
  final String? treePath;
  final List<AppCommandId> commands;
  final List<SidebarAction> actions;
  final AppCommandId? primaryCommand;
  final String? target;
  final String? commandName;
  final bool mergeDropTarget;
  final bool draggableMergeSource;
  final bool current;
  final String? currentDescription;

  /// Whether a descendant is the checked-out reference. Such a group stays
  /// open by default so the current branch is never hidden.
  final bool containsCurrent;
  final VoidCallback? onActivate;
  final HostingCheckState? hostingCheck;

  /// The branch [hostingCheck] belongs to, when the entry is no branch.
  final String? hostingCheckBranch;

  /// Whether the entry's open pull request merges without conflicts.
  final HostingMergeability hostingMergeability;
  final String? trackingDescription;
  final int ahead;
  final int behind;
  final List<SidebarEntry> children;

  /// The full name of a branch the history graph can be filtered to.
  final String? filterReference;

  /// The full name of the branch shown along with [filterReference].
  final String? filterUpstream;

  /// The full name of a reference that is no filter choice, but which a
  /// filtered history graph shows while this entry is selected.
  final String? revealReference;

  /// Replaces the section's icon for this row.
  final String? icon;

  /// This entry holding only [children], for a filtered view.
  SidebarEntry withChildren(List<SidebarEntry> children) => SidebarEntry(
    name: name,
    subtitle: subtitle,
    commands: commands,
    actions: actions,
    treePath: treePath,
    primaryCommand: primaryCommand,
    target: target,
    commandName: commandName,
    mergeDropTarget: mergeDropTarget,
    draggableMergeSource: draggableMergeSource,
    current: current,
    currentDescription: currentDescription,
    containsCurrent: containsCurrent,
    onActivate: onActivate,
    hostingCheck: hostingCheck,
    hostingCheckBranch: hostingCheckBranch,
    hostingMergeability: hostingMergeability,
    trackingDescription: trackingDescription,
    ahead: ahead,
    behind: behind,
    children: children,
    filterReference: filterReference,
    filterUpstream: filterUpstream,
    revealReference: revealReference,
    icon: icon,
  );
}

/// The entries of [entries] whose full name contains [foldedNeedle]
/// (lower-case), keeping the groups and remotes that hold one. A remote
/// branch's full name includes its remote (`origin/main`).
List<SidebarEntry> filterSidebarEntries(
  List<SidebarEntry> entries,
  String foldedNeedle,
) {
  final kept = <SidebarEntry>[];
  for (final entry in entries) {
    if (entry.children.isEmpty) {
      if ((entry.commandName ?? entry.name).toLowerCase().contains(
        foldedNeedle,
      )) {
        kept.add(entry);
      }
    } else if (filterSidebarEntries(entry.children, foldedNeedle)
        case final children when children.isNotEmpty) {
      kept.add(entry.withChildren(children));
    }
  }
  return kept;
}

List<AppCommandId> _localBranchCommands(bool current) => [
  AppCommandId.checkoutBranch,
  AppCommandId.mergeBranch,
  AppCommandId.rebaseBranch,
  AppCommandId.restackBranches,
  AppCommandId.autoStashCheckout,
  AppCommandId.createBranch,
  AppCommandId.createTag,
  AppCommandId.renameBranch,
  AppCommandId.deleteBranch,
];

/// The symbolic `HEAD` of a remote names its default branch; deleting it
/// would delete no branch.
List<AppCommandId> _remoteBranchCommands(String name) => [
  AppCommandId.checkoutBranch,
  AppCommandId.mergeBranch,
  AppCommandId.rebaseBranch,
  AppCommandId.createBranch,
  AppCommandId.createTag,
  if (name != 'HEAD') AppCommandId.deleteRemoteBranch,
];

const _tagCommands = <AppCommandId>[
  AppCommandId.pushTag,
  AppCommandId.deleteTag,
];

Map<String, SidebarEntry> historyReferenceEntries(RepositoryRefs refs) => {
  for (final reference in refs.branches)
    branchReference(reference).fullText: SidebarEntry(
      name: utf8.decode(reference.name, allowMalformed: true),
      subtitle: '',
      target: reference.target,
      current: reference.head,
      filterReference: branchReference(reference).fullText,
      commands: _localBranchCommands(reference.head),
      filterUpstream: filterUpstream(reference),
    ),
  for (final remote in refs.remotes)
    for (final reference in remote.branches)
      remoteBranchReference(remote, reference).fullText: SidebarEntry(
        name: utf8.decode(reference.name, allowMalformed: true),
        commandName:
            '${utf8.decode(remote.name, allowMalformed: true)}/${utf8.decode(reference.name, allowMalformed: true)}',
        subtitle: '',
        target: reference.target,
        commands: _remoteBranchCommands(
          utf8.decode(reference.name, allowMalformed: true),
        ),
        filterReference: remoteBranchReference(remote, reference).fullText,
      ),
  for (final reference in refs.tags)
    tagReference(reference).fullText: SidebarEntry(
      name: utf8.decode(reference.name, allowMalformed: true),
      subtitle: '',
      target: reference.target,
      commands: _tagCommands,
    ),
  for (final stash in refs.stashes)
    utf8.decode(stash.selector, allowMalformed: true): SidebarEntry(
      name: utf8.decode(stash.selector, allowMalformed: true),
      subtitle: '',
      target: stash.objectId,
      commands: const [
        AppCommandId.applyStash,
        AppCommandId.popStash,
        AppCommandId.renameStash,
        AppCommandId.dropStash,
      ],
    ),
};

// Group display names only; commands and drag payloads retain the full ref.
List<SidebarEntry> _branchTree(
  List<SidebarEntry> entries, {
  String prefix = '',
}) {
  final groups = <String, List<SidebarEntry>>{};
  for (final entry in entries) {
    final segment = entry.name.substring(prefix.length).split('/').first;
    groups.putIfAbsent(segment, () => []).add(entry);
  }
  return [
    for (final group in groups.entries)
      if (group.value.length == 1 &&
          group.value.single.name == '$prefix${group.key}')
        SidebarEntry(
          name: group.key,
          treePath: group.value.single.name,
          subtitle: group.value.single.subtitle,
          commands: group.value.single.commands,
          primaryCommand: group.value.single.primaryCommand,
          target: group.value.single.target,
          commandName:
              group.value.single.commandName ?? group.value.single.name,
          mergeDropTarget: group.value.single.mergeDropTarget,
          draggableMergeSource: group.value.single.draggableMergeSource,
          current: group.value.single.current,
          onActivate: group.value.single.onActivate,
          hostingCheck: group.value.single.hostingCheck,
          hostingMergeability: group.value.single.hostingMergeability,
          trackingDescription: group.value.single.trackingDescription,
          ahead: group.value.single.ahead,
          behind: group.value.single.behind,
          filterReference: group.value.single.filterReference,
          filterUpstream: group.value.single.filterUpstream,
          revealReference: group.value.single.revealReference,
          icon: group.value.single.icon,
        )
      else
        SidebarEntry(
          name: group.key,
          treePath: '$prefix${group.key}/',
          subtitle: '',
          commands: const [],
          containsCurrent: group.value.any((entry) => entry.current),
          children: _branchTree(group.value, prefix: '$prefix${group.key}/'),
        ),
  ];
}

/// Sidebar entries derived from one published reference snapshot.
final class _SidebarReferences {
  _SidebarReferences({
    required this.refs,
    required this.decorations,
    required this.l10n,
  }) {
    final local = [
      for (final reference in mainBranchFirst(refs.branches))
        _localBranch(
          reference,
          utf8.decode(reference.name, allowMalformed: true),
        ),
    ];
    currentBranchName = local.where((entry) => entry.current).firstOrNull?.name;
    branches = _branchTree(local);
    remotes = [for (final remote in refs.remotes) _remote(remote)];
    tags = [
      for (final reference in refs.tags)
        SidebarEntry(
          name: utf8.decode(reference.name, allowMalformed: true),
          subtitle: '',
          target: reference.target,
          commands: _tagCommands,
          revealReference: tagReference(reference).fullText,
        ),
    ];
    stashes = [
      for (final stash in refs.stashes)
        SidebarEntry(
          name: utf8.decode(stash.subject, allowMalformed: true),
          commandName: utf8.decode(stash.selector, allowMalformed: true),
          subtitle: utf8.decode(stash.selector, allowMalformed: true),
          primaryCommand: AppCommandId.applyStash,
          target: stash.objectId,
          // Only the newest stash is a reference; older ones are reflog
          // entries the history graph does not load.
          revealReference: nameIs(stash.selector, 'stash@{0}')
              ? ReferenceName.stashText
              : null,
          commands: const [
            AppCommandId.applyStash,
            AppCommandId.popStash,
            AppCommandId.renameStash,
            AppCommandId.dropStash,
          ],
        ),
    ];
  }

  final RepositoryRefs refs;
  final Map<String, HostingCheckState> decorations;
  final AppLocalizations l10n;
  late final String? currentBranchName;
  late final List<SidebarEntry> branches;
  late final List<SidebarEntry> remotes;
  late final List<SidebarEntry> tags;
  late final List<SidebarEntry> stashes;

  ({
    String needle,
    List<SidebarEntry> branches,
    List<SidebarEntry> remotes,
    List<SidebarEntry> tags,
  })?
  _filtered;

  /// Branches, remotes and tags matching [foldedNeedle], kept while the
  /// needle stays the same so the sections' rows are flattened once.
  ({
    List<SidebarEntry> branches,
    List<SidebarEntry> remotes,
    List<SidebarEntry> tags,
  })
  filtered(String foldedNeedle) {
    if (_filtered case final cached? when cached.needle == foldedNeedle) {
      return (
        branches: cached.branches,
        remotes: cached.remotes,
        tags: cached.tags,
      );
    }
    final next = (
      needle: foldedNeedle,
      branches: filterSidebarEntries(branches, foldedNeedle),
      remotes: filterSidebarEntries(remotes, foldedNeedle),
      tags: filterSidebarEntries(tags, foldedNeedle),
    );
    _filtered = next;
    return (branches: next.branches, remotes: next.remotes, tags: next.tags);
  }

  bool derivedFrom(
    RepositoryRefs refs,
    Map<String, HostingCheckState> decorations,
    AppLocalizations l10n,
  ) =>
      identical(this.refs, refs) &&
      identical(this.decorations, decorations) &&
      identical(this.l10n, l10n);

  SidebarEntry _localBranch(RepositoryReference reference, String name) {
    final tracked = reference.upstream != null && !reference.upstreamGone;
    return SidebarEntry(
      name: name,
      subtitle: '',
      ahead: tracked ? reference.ahead : 0,
      behind: tracked ? reference.behind : 0,
      trackingDescription:
          tracked && (reference.ahead > 0 || reference.behind > 0)
          ? l10n.transferAheadBehind(
              reference.ahead.toString(),
              reference.behind.toString(),
            )
          : null,
      hostingCheck: decorations[name],
      primaryCommand: AppCommandId.checkoutBranch,
      target: reference.target,
      mergeDropTarget: reference.head,
      draggableMergeSource: !reference.head,
      current: reference.head,
      commands: _localBranchCommands(reference.head),
      filterReference: branchReference(reference).fullText,
      filterUpstream: filterUpstream(reference),
    );
  }

  SidebarEntry _remote(RepositoryRemote remote) {
    final remoteName = utf8.decode(remote.name, allowMalformed: true);
    return SidebarEntry(
      name: remoteName,
      subtitle: '',
      primaryCommand: AppCommandId.remoteFetch,
      commands: const [
        AppCommandId.remoteFetch,
        AppCommandId.pull,
        AppCommandId.remotePush,
        AppCommandId.renameRemote,
        AppCommandId.editRemote,
        AppCommandId.removeRemote,
      ],
      children: _branchTree([
        for (final reference in mainBranchFirst(remote.branches))
          _remoteBranch(
            remote,
            reference,
            utf8.decode(reference.name, allowMalformed: true),
          ),
      ]),
    );
  }

  SidebarEntry _remoteBranch(
    RepositoryRemote remote,
    RepositoryReference reference,
    String name,
  ) {
    final full = remoteBranchReference(remote, reference);
    return SidebarEntry(
      name: name,
      subtitle: '',
      target: reference.target,
      commandName: full.display,
      commands: _remoteBranchCommands(name),
      filterReference: full.isRemoteHead ? null : full.fullText,
    );
  }
}

/// Selects the sidebar row named [ref]. [reveal] is the full name of the
/// branch the history graph shows while that row stays selected.
typedef _SelectRef = void Function(String ref, {String? reveal});

typedef _SidebarFlatRow = ({
  SidebarEntry entry,
  String path,
  int depth,
  bool expanded,
});

/// The visible rows of one section, in display order.
final class _SidebarFlatRows {
  _SidebarFlatRows({
    required this.entries,
    required this.repository,
    required this.generation,
    required this.rows,
  });

  final List<SidebarEntry> entries;
  final NativePathIdentity? repository;
  final int generation;
  final List<_SidebarFlatRow> rows;
  Map<String, int>? _indexByPath;

  int? indexOf(String path) => (_indexByPath ??= {
    for (var index = 0; index < rows.length; index += 1)
      rows[index].path: index,
  })[path];
}

typedef _BranchDrag = ({String name, String target});

class WorkspaceSidebar extends StatefulWidget {
  const WorkspaceSidebar({
    super.key,
    required this.active,
    required this.pane,
    required this.onCommand,
    required this.shortcuts,
  });

  final RepositoryTabState? active;
  final WorkspacePane? pane;
  final RunAppCommand onCommand;
  final Map<AppCommandId, AppShortcut?> shortcuts;

  @override
  State<WorkspaceSidebar> createState() => _SidebarState();
}

class _SidebarState extends State<WorkspaceSidebar> {
  bool _focused = false;
  final ScrollController _scroll = ScrollController();

  /// The reference filter: hidden until asked for with its button or by
  /// typing while the sidebar has focus, and gone again once cleared.
  final TextEditingController _filter = TextEditingController();
  final FocusNode _filterFocus = FocusNode(debugLabel: 'sidebar-filter');
  bool _filterOpen = false;

  /// Expansion chosen while filtering. Matches start revealed; the durable
  /// choices stay untouched and return when the filter is cleared.
  final Map<String, bool> _filterChoices = {};

  String get _needle => _filterOpen ? _filter.text.trim().toLowerCase() : '';
  bool get _filtering => _needle.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _filterFocus.addListener(_filterFocusChanged);
  }

  @override
  void didUpdateWidget(covariant WorkspaceSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active?.canonicalIdentity !=
        widget.active?.canonicalIdentity) {
      _closeFilter(notify: false);
    }
  }

  @override
  void dispose() {
    unawaited(_selectionChanges?.cancel());
    _scroll.dispose();
    _filterFocus.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _openFilter([String? initial]) {
    setState(() {
      if (initial != null) {
        _filter.value = TextEditingValue(
          text: initial,
          selection: TextSelection.collapsed(offset: initial.length),
        );
      }
      if (!_filterOpen) {
        _filterOpen = true;
        _expansionGeneration += 1;
      }
    });
    // Autofocus would yield to the row or button that has focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _filterOpen) _filterFocus.requestFocus();
    });
  }

  void _closeFilter({bool notify = true}) {
    if (!_filterOpen && _filter.text.isEmpty) return;
    void close() {
      _filterOpen = false;
      _filter.clear();
      _filterChoices.clear();
      _expansionGeneration += 1;
    }

    notify ? setState(close) : close();
  }

  // An empty filter goes away once focus leaves it.
  void _filterFocusChanged() {
    if (!_filterFocus.hasFocus && _filterOpen && _filter.text.trim().isEmpty) {
      _closeFilter();
    }
  }

  // Typing a character while a sidebar row has focus starts filtering with
  // it. Text fields keep their own keys, and shortcuts keep their modifiers.
  KeyEventResult _typeToFilter(KeyEvent event) {
    if (event is! KeyDownEvent || widget.active?.session == null) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    final keyboard = HardwareKeyboard.instance;
    if (character == null ||
        character.runes.length != 1 ||
        character.trim().isEmpty ||
        character.runes.single < 0x20 ||
        character.runes.single == 0x7f ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        _filterFocus.hasFocus ||
        FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    _openFilter(_filterOpen ? '${_filter.text}$character' : character);
    return KeyEventResult.handled;
  }

  // Only explicit choices are stored, per repository. Sections start open
  // except tags; groups start closed unless they hold the checked-out branch.
  final Map<NativePathIdentity?, Map<String, bool>> _expansionChoices = {};
  var _expansionGeneration = 0;
  _SidebarReferences? _references;
  final Map<String, _SidebarFlatRows> _flatRows = {};

  Map<String, bool> get _choices => _filtering
      ? _filterChoices
      : _expansionChoices[widget.active?.canonicalIdentity] ?? const {};

  static final _filteredSections = {
    AppCommandId.createBranch.name,
    AppCommandId.addRemote.name,
    AppCommandId.createTag.name,
  };

  // A repository can hold hundreds of tags, so that section starts closed;
  // pull requests fill in as branches are looked up and start closed too.
  // While filtering, the filtered sections start open.
  bool _isSectionExpanded(String name) =>
      _choices[name] ??
      (_filtering
          ? _filteredSections.contains(name) || _isDurablySectionExpanded(name)
          : _isDurablySectionExpanded(name));

  bool _isDurablySectionExpanded(String name) =>
      _expansionChoices[widget.active?.canonicalIdentity]?[name] ??
      (name != AppCommandId.createTag.name &&
          name != AppCommandId.hostingCreatePullRequest.name);

  void _setExpanded(String path, bool expanded) => setState(() {
    if (_filtering) {
      _filterChoices[path] = expanded;
    } else {
      (_expansionChoices[widget.active?.canonicalIdentity] ??= {})[path] =
          expanded;
    }
    _expansionGeneration += 1;
  });

  // The bound hosting account with the CI result of its main branch, then the
  // configured tools and commands.
  List<SidebarEntry> _integrationEntries(BuildContext context) {
    final hosting = HostingScope.of(context);
    final binding = hosting.binding;
    final main = hosting.links?.defaultBranchChecks();
    return [
      if (binding case HostingBindingResolution(
        state: HostingBindingState.bound,
        :final connectionId?,
      ))
        SidebarEntry(
          name: connectionId,
          subtitle: binding.providerRepository ?? '',
          hostingCheck: main == null || main.checks == HostingCheckState.unknown
              ? null
              : main.checks,
          hostingCheckBranch: main?.branch,
          icon: 'cloud',
          commands: const [AppCommandId.showIntegrations],
          onActivate: () => widget.onCommand(AppCommandId.showIntegrations),
        ),
      for (final integration in WorkspaceServicesScope.read(
        context,
      ).settings.current.integrations)
        SidebarEntry(
          name: integration.id,
          subtitle: integrationKindLabel(context, integration.kind),
          commands: const [AppCommandId.addIntegration],
          onActivate: () => widget.onCommand(AppCommandId.addIntegration),
        ),
    ];
  }

  // Linked pull requests; the account's own carry a marker.
  List<SidebarEntry> _pullRequestEntries(BuildContext context) {
    final links = HostingScope.of(context).links;
    if (links == null) return const [];
    final l10n = context.l10n;
    return [
      for (final HostingLinkedPullRequest(:pull, :authored) in links.linked)
        SidebarEntry(
          name: '#${pull.number} ${pull.title}',
          treePath: 'pull-request:${pull.number}',
          commandName: pull.webUrl,
          subtitle: pull.state == HostingChangeRequestState.merged
              ? l10n.hostingPullRequestMerged
              : authored
              ? l10n.hostingPullRequestYours
              : pull.sourceBranch,
          trackingDescription: l10n.hostingPullRequestBranches(
            pull.sourceBranch,
            pull.targetBranch,
          ),
          icon: pull.state == HostingChangeRequestState.merged
              ? 'git-merge'
              : authored
              ? 'user'
              : 'git-pull-request',
          target: links.localHead(pull),
          hostingCheck: pull.checks.state == HostingCheckState.unknown
              ? null
              : pull.checks.state,
          hostingMergeability: pull.mergeability,
          commands: const [],
          actions: [
            SidebarAction(
              label: l10n.hostingOpenBrowser,
              onSelected: () => links.onOpen(pull.webUrl),
            ),
            if (pull.state == HostingChangeRequestState.open &&
                pull.sourceBranch.isNotEmpty &&
                pull.headSha.isNotEmpty)
              SidebarAction(
                label: l10n.hostingCheckout,
                onSelected: () => widget.onCommand(
                  AppCommandId.createBranch,
                  initialName: pull.sourceBranch,
                  initialTarget: pull.headSha,
                ),
              ),
          ],
        ),
    ];
  }

  _SidebarReferences _referencesFor(
    RepositoryRefs refs,
    Map<String, HostingCheckState> decorations,
    AppLocalizations l10n,
  ) {
    final cached = _references;
    if (cached != null && cached.derivedFrom(refs, decorations, l10n)) {
      return cached;
    }
    return _references = _SidebarReferences(
      refs: refs,
      decorations: decorations,
      l10n: l10n,
    );
  }

  // Git groups keep their expansion outside disposable viewport rows. Each
  // section flattens once per reference snapshot and expansion change; the
  // sliver then builds only the rows inside the viewport.
  _SidebarFlatRows _flatRowsFor(String section, List<SidebarEntry> entries) {
    final repository = widget.active?.canonicalIdentity;
    final cached = _flatRows[section];
    if (cached != null &&
        identical(cached.entries, entries) &&
        cached.generation == _expansionGeneration &&
        cached.repository == repository) {
      return cached;
    }
    final choices = _choices;
    final rows = <_SidebarFlatRow>[];
    void flatten(List<SidebarEntry> entries, String path, int depth) {
      for (final entry in entries) {
        final identity = entry.treePath ?? entry.commandName ?? entry.name;
        final entryPath = '$path/$identity';
        final expanded =
            entry.children.isNotEmpty &&
            (choices[entryPath] ?? (_filtering || entry.containsCurrent));
        rows.add((
          entry: entry,
          path: entryPath,
          depth: depth,
          expanded: expanded,
        ));
        if (expanded) flatten(entry.children, entryPath, depth + 1);
      }
    }

    flatten(entries, section, 0);
    return _flatRows[section] = _SidebarFlatRows(
      entries: entries,
      repository: repository,
      generation: _expansionGeneration,
      rows: rows,
    );
  }

  Widget _referenceSliver(
    _SidebarFlatRows flat, {
    required double extent,
    required String icon,
    required String? selectedRef,
    required _SelectRef onSelectRef,
  }) => SliverFixedExtentList(
    itemExtent: extent,
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        final row = flat.rows[index];
        return _SidebarRefRow(
          key: ValueKey(row.path),
          entry: row.entry,
          icon: icon,
          depth: row.depth,
          expanded: row.expanded,
          onExpansionChanged: (value) => _setExpanded(row.path, value),
          onCommand: widget.onCommand,
          onRevealTarget: _revealTarget,
          selectedRef: selectedRef,
          onSelectRef: onSelectRef,
          shortcuts: widget.shortcuts,
        );
      },
      childCount: flat.rows.length,
      // Expanding a group shifts every later row. Resolving keys keeps the
      // state of rows that merely moved.
      findChildIndexCallback: (key) =>
          key is ValueKey<String> ? flat.indexOf(key.value) : null,
    ),
  );

  /// Shows a commit a sidebar row points at in History.
  void _revealTarget(String commit) =>
      unawaited(_navigator?.showCommit(commit, reload: false));

  /// The window's navigation; it owns which sidebar row each tab selects.
  WorkspaceNavigator? _navigator;
  StreamSubscription<void>? _selectionChanges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigator = WorkspaceServicesScope.maybeOf(
      context,
    )?.workflows.navigator;
    if (identical(navigator, _navigator)) return;
    _navigator = navigator;
    unawaited(_selectionChanges?.cancel());
    _selectionChanges = navigator?.referenceChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedRef = _navigator?.selectedReference(widget.active?.id);
    // A branch the graph filter hides is shown while it is selected here.
    void selectRef(String ref, {String? reveal}) =>
        _navigator?.selectReference(ref, reveal: reveal);

    final references = _referencesFor(
      widget.active?.session?.snapshot.refs ?? const RepositoryRefs(),
      HostingScope.of(context).branchDecorations,
      l10n,
    );
    final needle = _needle;
    final filtered = needle.isEmpty ? null : references.filtered(needle);
    final branches = filtered?.branches ?? references.branches;
    final remotes = filtered?.remotes ?? references.remotes;
    final tags = filtered?.tags ?? references.tags;
    final integrations = _integrationEntries(context);
    final pullRequests = _pullRequestEntries(context);
    final rowExtent = MediaQuery.textScalerOf(
      context,
    ).scale(context.meridian.density.rowExtent);
    // The thumb stays out of the rows until the pointer is over the sidebar
    // or the sidebar scrolls.
    final content = ColoredBox(
      color: context.colors.ground,
      child: MeridianScrollbar(
        controller: _scroll,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                vertical: MeridianSpace.space2,
                horizontal: MeridianSpace.space3,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      _SidebarGroupLabel(label: l10n.commandGroupCommands),
                      MeridianListRow(
                        title: l10n.workspaceChanges,
                        leading: const MeridianIcon(
                          'changes',
                          size: MeridianIconSize.small,
                        ),
                        selected: widget.pane == WorkspacePane.changes,
                        enabled: widget.active?.session != null,
                        onTap: () =>
                            _navigator?.selectPane(WorkspacePane.changes),
                      ),
                      MeridianListRow(
                        title: l10n.workspaceHistory,
                        leading: const MeridianIcon(
                          'history',
                          size: MeridianIconSize.small,
                        ),
                        selected: widget.pane == WorkspacePane.history,
                        enabled: widget.active?.session != null,
                        onTap: () =>
                            _navigator?.selectPane(WorkspacePane.history),
                      ),
                      _SidebarGroupLabel(
                        label: l10n.commandGroupRepository,
                        trailing: _filterOpen || widget.active?.session == null
                            ? null
                            : MeridianIconButton(
                                key: const ValueKey('sidebar-filter-show'),
                                label: l10n.sidebarFilterShow,
                                icon: 'search',
                                size: MeridianControlSize.small,
                                onGround: true,
                                onPressed: _openFilter,
                              ),
                      ),
                      if (_filterOpen)
                        _SidebarFilterField(
                          controller: _filter,
                          focusNode: _filterFocus,
                          onChanged: () => setState(() {}),
                          onClose: _closeFilter,
                        ),
                      if (filtered != null &&
                          filtered.branches.isEmpty &&
                          filtered.remotes.isEmpty &&
                          filtered.tags.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: MeridianSpace.space4,
                            vertical: MeridianSpace.space2,
                          ),
                          child: Text(
                            l10n.sidebarFilterNoMatches,
                            style: context.text.caption.copyWith(
                              color: context.colors.inkMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final (icon, label, count, command, entries) in [
                    (
                      'branch',
                      l10n.workspaceBranches,
                      widget.active?.session?.snapshot.refCounts.branches ?? 0,
                      AppCommandId.createBranch,
                      branches,
                    ),
                    (
                      'cloud',
                      l10n.workspaceRemotes,
                      widget.active?.session?.snapshot.refCounts.remotes ?? 0,
                      AppCommandId.addRemote,
                      remotes,
                    ),
                    (
                      'stash',
                      l10n.workspaceStashes,
                      widget.active?.session?.snapshot.refCounts.stashes ?? 0,
                      AppCommandId.createStash,
                      references.stashes,
                    ),
                    (
                      'tag',
                      l10n.workspaceTags,
                      widget.active?.session?.snapshot.refCounts.tags ?? 0,
                      AppCommandId.createTag,
                      tags,
                    ),
                    (
                      'box',
                      l10n.extensionLfs,
                      0,
                      AppCommandId.trackLfsPattern,
                      const <SidebarEntry>[],
                    ),
                    (
                      'command',
                      l10n.integrationTitle,
                      integrations.length,
                      AppCommandId.addIntegration,
                      integrations,
                    ),
                    (
                      'git-pull-request',
                      l10n.hostingChangeRequests,
                      pullRequests.length,
                      AppCommandId.hostingCreatePullRequest,
                      pullRequests,
                    ),
                  ]) ...[
                    SliverToBoxAdapter(
                      child: _SidebarSection(
                        key: ValueKey(command),
                        headerOnly: true,
                        expanded: _isSectionExpanded(command.name),
                        onExpansionChanged: (value) =>
                            _setExpanded(command.name, value),
                        label: label,
                        icon: icon,
                        count: count,
                        command: command,
                        entries: entries,
                        hasRepository: widget.active?.session != null,
                        onCommand: widget.onCommand,
                        onRevealTarget: _revealTarget,
                        selectedRef: selectedRef,
                        onSelectRef: selectRef,
                        shortcuts: widget.shortcuts,
                      ),
                    ),
                    if (_isSectionExpanded(command.name) && entries.isNotEmpty)
                      _referenceSliver(
                        _flatRowsFor(command.name, entries),
                        extent: rowExtent,
                        icon: icon,
                        selectedRef: selectedRef,
                        onSelectRef: selectRef,
                      ),
                    // A repository on another computer lists its worktrees
                    // on that host.
                    if (command == AppCommandId.createTag)
                      SliverToBoxAdapter(
                        child: _WorktreeSidebarSection(
                          key: ValueKey(widget.active?.canonicalIdentity),
                          repositories: WorkspaceServicesScope.read(
                            context,
                          ).repositories,
                          revision: widget.active?.session?.snapshot.revision,
                          label: l10n.workspaceWorktrees,
                          count:
                              widget
                                  .active
                                  ?.session
                                  ?.snapshot
                                  .refCounts
                                  .worktrees ??
                              0,
                          hasRepository: widget.active?.session != null,
                          onCommand: widget.onCommand,
                          onRevealTarget: _revealTarget,
                          selectedRef: selectedRef,
                          onSelectRef: selectRef,
                          shortcuts: widget.shortcuts,
                          onOpenFolder: FileActionsScope.of(context).openFolder,
                          fileBrowserName: FileActionsScope.of(
                            context,
                          ).fileBrowserName,
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
    final active = widget.active;
    return BranchFilterScope(
      filter: active?.navigation.branchFilter ?? HistoryBranchFilter.none,
      onChanged: (filter) {
        if (active == null) return;
        unawaited(
          WorkspaceServicesScope.read(
            context,
          ).repositories.setBranchFilter(active.id, filter),
        );
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) => _typeToFilter(event),
        child: MeridianSurfaceScope(
          focused: _focused,
          onGround: true,
          child: ClipRect(
            child: MeridianGlide.custom(
              selection: references.currentBranchName,
              foreground: true,
              indicator: MeridianIcon(
                'check',
                size: MeridianIconSize.small,
                color: context.colors.accentInk,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: MeridianSpace.space4),
    child: SizedBox(
      height: MeridianLayout.navSectionHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.overline.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );
}

/// The sidebar's reference filter field. Escape and its clear button clear
/// the filter and close it.
class _SidebarFilterField extends StatelessWidget {
  const _SidebarFilterField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: MeridianSpace.space2,
      end: MeridianSpace.space2,
      top: MeridianSpace.space1,
    ),
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: MeridianTextField(
        key: const ValueKey('sidebar-filter'),
        controller: controller,
        focusNode: focusNode,
        variant: MeridianTextFieldVariant.search,
        size: MeridianControlSize.small,
        label: context.l10n.sidebarFilterShow,
        showLabel: false,
        placeholder: context.l10n.sidebarFilterPlaceholder,
        autocorrect: false,
        enableSuggestions: false,
        submitsDialog: false,
        onChanged: (_) => onChanged(),
        trailing: MeridianIconButton(
          key: const ValueKey('sidebar-filter-clear'),
          label: context.l10n.sidebarFilterClear,
          icon: 'x',
          size: MeridianControlSize.small,
          onPressed: onClose,
        ),
      ),
    ),
  );
}

class SidebarRail extends StatelessWidget {
  const SidebarRail({
    super.key,
    required this.pane,
    required this.onSelectPane,
  });

  final WorkspacePane? pane;
  final ValueChanged<WorkspacePane> onSelectPane;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.ground,
    child: Padding(
      padding: const EdgeInsets.only(top: MeridianSpace.space3),
      child: Column(
        children: [
          MeridianIconButton(
            label: context.l10n.workspaceChanges,
            icon: 'changes',
            onGround: true,
            active: pane == WorkspacePane.changes,
            onPressed: () => onSelectPane(WorkspacePane.changes),
          ),
          const SizedBox(height: MeridianSpace.space2),
          MeridianIconButton(
            label: context.l10n.workspaceHistory,
            icon: 'history',
            onGround: true,
            active: pane == WorkspacePane.history,
            onPressed: () => onSelectPane(WorkspacePane.history),
          ),
        ],
      ),
    ),
  );
}

class _WorktreeSidebarSection extends StatefulWidget {
  const _WorktreeSidebarSection({
    super.key,
    required this.repositories,
    required this.revision,
    required this.label,
    required this.count,
    required this.hasRepository,
    required this.onCommand,
    required this.onRevealTarget,
    required this.selectedRef,
    required this.onSelectRef,
    required this.shortcuts,
    this.onOpenFolder,
    this.fileBrowserName,
  });

  final RepositorySessionService repositories;
  final BigInt? revision;
  final String label;
  final int count;
  final bool hasRepository;
  final RunAppCommand onCommand;
  final ValueChanged<String> onRevealTarget;
  final String? selectedRef;
  final _SelectRef onSelectRef;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final ValueChanged<NativePathIdentity>? onOpenFolder;
  final String? fileBrowserName;

  @override
  State<_WorktreeSidebarSection> createState() =>
      _WorktreeSidebarSectionState();
}

class _WorktreeSidebarSectionState extends State<_WorktreeSidebarSection> {
  Future<RepositoryExtensionInventory>? _inventory;
  RepositoryExtensionFailureCode? _deletionFailure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _WorktreeSidebarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasRepository != oldWidget.hasRepository ||
        widget.count != oldWidget.count ||
        widget.revision != oldWidget.revision) {
      _load();
    }
  }

  void _load() {
    _inventory = widget.hasRepository && widget.count > 0
        ? widget.repositories.extensions.inventory()
        : null;
  }

  Future<void> _open(WorktreeEntry worktree) async {
    try {
      await widget.repositories.extensions.openWorktree(worktree);
    } on RepositorySessionException {
      // The workspace keeps the failed tab visible with its localized error.
    }
  }

  Future<void> _delete(WorktreeEntry worktree) async {
    // The same host gate as the worktree panel: a remote tab deletes only
    // where the host allows changes to worktrees.
    final hostReason = remoteWriteReason(
      context,
      RemoteCapability.extensions,
      listen: false,
    );
    if (hostReason != null) {
      StatusNotificationScope.show(context, hostReason);
      return;
    }
    if (!await confirmWorktreeDeletion(context, worktree) || !mounted) return;
    setState(() => _deletionFailure = null);
    RepositoryExtensionFailureCode? failure;
    try {
      final result = await widget.repositories.extensions.execute(
        RepositoryExtensionMutationRequest(
          kind: RepositoryExtensionMutationKind.worktreeDelete,
          worktreeRoot: worktree.worktreeRoot,
        ),
      );
      if (result.state == RepositoryExtensionMutationState.outcomeUncertain) {
        if (mounted) {
          StatusNotificationScope.show(
            context,
            context.l10n.mutationOutcomeUncertain,
            error: true,
          );
          setState(_load);
        }
        return;
      }
      failure = result.reportedFailure;
    } on RepositoryExtensionException catch (error) {
      failure = error.code;
    } on RemoteOutcomeUnknownException {
      if (mounted) {
        showRemoteOutcomeUnknown(context);
        setState(_load);
      }
      return;
    } on RepositorySessionException {
      failure = RepositoryExtensionFailureCode.git;
    }
    if (!mounted) return;
    if (failure != null) {
      StatusNotificationScope.show(
        context,
        extensionFailureLabel(context, failure),
        error: true,
      );
    }
    setState(() {
      _deletionFailure = failure;
      _load();
    });
  }

  List<SidebarAction> _actions(
    RepositoryExtensionInventory inventory,
    WorktreeEntry worktree,
  ) => [
    if (!worktree.current)
      SidebarAction(
        label: context.l10n.extensionOpen,
        onSelected: () => unawaited(_open(worktree)),
      ),
    // A folder on another computer has no file browser here.
    if (widget.onOpenFolder case final open?
        when !worktree.worktreeRoot.isRemote)
      SidebarAction(
        label: context.l10n.openInFileBrowser(
          widget.fileBrowserName ?? platformFileBrowserName(),
        ),
        onSelected: () => open(worktree.worktreeRoot),
      ),
    SidebarAction(
      label: context.l10n.extensionWorktreeDeleteAction,
      enabled: !worktreeDeletionProtected(inventory, worktree),
      danger: true,
      onSelected: () => unawaited(_delete(worktree)),
    ),
  ];

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<RepositoryExtensionInventory>(
        future: _inventory,
        builder: (context, snapshot) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SidebarSection(
              label: widget.label,
              icon: 'folder-symlink',
              count: widget.count,
              command: AppCommandId.addWorktree,
              entries: [
                for (final worktree
                    in _inventory == null
                        ? const <WorktreeEntry>[]
                        : snapshot.data?.worktrees ?? const <WorktreeEntry>[])
                  SidebarEntry(
                    treePath: nativeIdentityLabel(worktree.worktreeRoot),
                    name: worktree.branch == null
                        ? nativeIdentityLabel(worktree.worktreeRoot)
                                  .split(RegExp(r'[/\\]'))
                                  .where((part) => part.isNotEmpty)
                                  .lastOrNull ??
                              widget.label
                        : ReferenceName(worktree.branch!).display,
                    subtitle: '',
                    current: worktree.current,
                    currentDescription: worktree.current
                        ? context.l10n.extensionWorktreeCurrent
                        : null,
                    commands: const [],
                    actions: _actions(snapshot.data!, worktree),
                    onActivate: worktree.current
                        ? null
                        : () => unawaited(_open(worktree)),
                  ),
              ],
              expandable: widget.count > 0,
              onExpand: () => setState(_load),
              hasRepository: widget.hasRepository,
              onCommand: widget.onCommand,
              onRevealTarget: widget.onRevealTarget,
              selectedRef: widget.selectedRef,
              onSelectRef: widget.onSelectRef,
              shortcuts: widget.shortcuts,
            ),
            if (_deletionFailure case final failure?)
              Padding(
                padding: const EdgeInsets.all(MeridianSpace.space3),
                child: MeridianBanner(
                  tone: MeridianBannerTone.error,
                  message: extensionFailureLabel(context, failure),
                ),
              ),
          ],
        ),
      );
}

class _SidebarSection extends StatefulWidget {
  const _SidebarSection({
    super.key,
    this.headerOnly = false,
    this.expanded,
    this.onExpansionChanged,
    required this.label,
    required this.icon,
    required this.count,
    required this.command,
    required this.entries,
    this.expandable = false,
    this.onExpand,
    required this.hasRepository,
    required this.onCommand,
    required this.onRevealTarget,
    required this.selectedRef,
    required this.onSelectRef,
    required this.shortcuts,
  });

  final bool headerOnly;
  final bool? expanded;
  final ValueChanged<bool>? onExpansionChanged;
  final String label;
  final String icon;
  final int count;
  final AppCommandId command;
  final List<SidebarEntry> entries;
  final bool expandable;
  final VoidCallback? onExpand;
  final bool hasRepository;
  final RunAppCommand onCommand;
  final ValueChanged<String> onRevealTarget;
  final String? selectedRef;
  final _SelectRef onSelectRef;
  final Map<AppCommandId, AppShortcut?> shortcuts;

  @override
  State<_SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<_SidebarSection>
    with KeyboardRevealState {
  final FocusNode _focusNode = FocusNode();
  var _localExpanded = true;
  bool get _expanded => widget.expanded ?? _localExpanded;
  void _expand(bool value) {
    if (widget.onExpansionChanged case final update?) {
      update(value);
    } else {
      setState(() => _localExpanded = value);
    }
  }

  var _hovered = false;
  var _focused = false;

  SidebarEntry? _currentEntry(List<SidebarEntry> entries) {
    for (final entry in entries) {
      if (entry.current) return entry;
      if (!entry.containsCurrent) continue;
      final nested = _currentEntry(entry.children);
      if (nested != null) return nested;
    }
    return null;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final definition = AppCommandRegistry.byId(widget.command);
    // Only a remote tab's reason disables the button here; other reasons
    // are explained when the command runs.
    final shownReason = remoteMenuReason(
      context,
      CommandAvailabilityScope.read(context)?.reason(widget.command),
    );
    final reason =
        definition.disabledReason(hasRepository: widget.hasRepository) ??
        (shownReason == null
            ? null
            : AppCommandDisabledReason.remoteUnsupported);
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.insert) {
          if (reason == null) widget.onCommand(widget.command);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MeridianGlide.custom(
        selection: _currentEntry(widget.entries)?.name,
        foreground: true,
        indicator: MeridianIcon(
          'check',
          size: MeridianIconSize.small,
          color: context.colors.accentInk,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: MeridianSpace.space4,
              ),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: CallbackShortcuts(
                  bindings: {
                    if (widget.shortcuts[widget.command] case final shortcut?)
                      shortcut.activator: () =>
                          widget.onCommand(widget.command),
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _focusNode.requestFocus();
                      if (widget.entries.isNotEmpty || widget.expandable) {
                        if (!_expanded) widget.onExpand?.call();
                        _expand(!_expanded);
                      }
                    },
                    child: Semantics(
                      button: true,
                      label: widget.label,
                      child: SizedBox(
                        height: MeridianLayout.navSectionHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: MeridianSpace.space4,
                          ),
                          child: Row(
                            children: [
                              if (widget.entries.isNotEmpty ||
                                  widget.expandable) ...[
                                SizedBox.square(
                                  dimension: MeridianLayout.chevronSize,
                                  child: MeridianIcon(
                                    _expanded
                                        ? 'chevron-down'
                                        : 'chevron-right',
                                    size: MeridianIconSize.small,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                                const SizedBox(width: MeridianSpace.space2),
                              ],
                              Expanded(
                                child: Text(
                                  widget.label.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.overline.copyWith(
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: MeridianSize.controlSm,
                                child: _hovered || (_focused && keyboardInput)
                                    ? MeridianIconButton(
                                        label: commandLabel(
                                          context,
                                          widget.command,
                                        ),
                                        icon: 'plus',
                                        size: MeridianControlSize.small,
                                        onGround: true,
                                        disabledReason: shownReason,
                                        onPressed: reason == null
                                            ? () => widget.onCommand(
                                                widget.command,
                                              )
                                            : null,
                                      )
                                    : Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: MeridianCount(
                                          label: '${widget.count}',
                                          tone: MeridianCountTone.quiet,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.headerOnly)
              MeridianReveal(
                visible: _expanded,
                child: Column(
                  children: [
                    for (final entry in widget.entries)
                      _SidebarRefRow(
                        key: ValueKey(
                          entry.treePath ?? entry.commandName ?? entry.name,
                        ),
                        entry: entry,
                        icon: widget.icon,
                        onCommand: widget.onCommand,
                        onRevealTarget: widget.onRevealTarget,
                        selectedRef: widget.selectedRef,
                        onSelectRef: widget.onSelectRef,
                        shortcuts: widget.shortcuts,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _holdsFiltered(List<SidebarEntry> entries, HistoryBranchFilter filter) =>
    entries.any(
      (entry) =>
          (entry.filterReference != null &&
              filter.contains(entry.filterReference!)) ||
          _holdsFiltered(entry.children, filter),
    );

class _SidebarRefRow extends StatefulWidget {
  const _SidebarRefRow({
    super.key,
    required this.entry,
    required this.onCommand,
    required this.onRevealTarget,
    required this.selectedRef,
    required this.onSelectRef,
    required this.shortcuts,
    required this.icon,
    this.depth = 0,
    this.expanded = true,
    this.onExpansionChanged,
  });

  final SidebarEntry entry;
  final RunAppCommand onCommand;
  final ValueChanged<String> onRevealTarget;
  final String? selectedRef;
  final _SelectRef onSelectRef;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final String icon;
  final int depth;
  final bool expanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<_SidebarRefRow> createState() => _SidebarRefRowState();
}

class _SidebarRefRowState extends State<_SidebarRefRow> {
  final FocusNode _focusNode = FocusNode();
  bool get _expanded => widget.expanded;
  void _expand(bool value) => widget.onExpansionChanged?.call(value);

  AppCommandDisabledReason? _commandReason(AppCommandId command) =>
      CommandAvailabilityScope.read(context)?.reason(
        command,
        reference: widget.entry.filterReference,
        target: widget.entry.target,
        current: widget.entry.current,
        contextual: true,
      );

  bool _commandEnabled(AppCommandId command) => _commandReason(command) == null;

  void _run(AppCommandId command) {
    if (!_commandEnabled(command)) return;
    widget.onCommand(
      command,
      initialName:
          command == AppCommandId.createBranch ||
              command == AppCommandId.createTag
          ? null
          : widget.entry.commandName ?? widget.entry.name,
      initialTarget: widget.entry.target,
      initialReference: widget.entry.filterReference,
    );
  }

  List<NativeMenuAction> _actionItems() => referenceMenuItems(
    context,
    entry: widget.entry,
    reference: widget.entry.filterReference,
    shortcuts: widget.shortcuts,
    reason: _commandReason,
    onCommand: widget.onCommand,
    branchFilter: switch (BranchFilterScope.read(context)) {
      final scope? => (filter: scope.filter, onChanged: scope.onChanged),
      null => null,
    },
  );

  Future<void> _showActions(Offset position) async {
    _focusNode.requestFocus();
    final action = await showNativeMenuItems<VoidCallback>(
      context: context,
      position: position,
      items: _actionItems(),
    );
    if (!mounted) return;
    _focusNode.requestFocus();
    action?.call();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.entry.children.isNotEmpty;
    final refName =
        widget.entry.treePath ?? widget.entry.commandName ?? widget.entry.name;
    final selected = widget.selectedRef == refName;
    final strong = MeridianRowColors.resolve(
      context,
      selected: selected,
      hovered: false,
    ).strong;
    // A filtered branch is marked, and so is a closed folder hiding one.
    final filter = BranchFilterScope.filterOf(context);
    final filtered = switch (widget.entry.filterReference) {
      final reference? => filter.contains(reference),
      null => false,
    };
    final holdsFiltered =
        hasChildren &&
        !_expanded &&
        filter.isNotEmpty &&
        _holdsFiltered(widget.entry.children, filter);
    Widget row = GestureDetector(
      onDoubleTap: widget.entry.primaryCommand == null
          ? null
          : () => _run(widget.entry.primaryCommand!),
      child: Tooltip(
        message: refName,
        child: MeridianListRow(
          title: widget.entry.name,
          selected: selected,
          emphasized: widget.entry.current,
          onTap: () {
            _focusNode.requestFocus();
            widget.onSelectRef(
              refName,
              reveal: widget.entry.target == null
                  ? null
                  : widget.entry.filterReference ??
                        widget.entry.revealReference,
            );
            if (widget.entry.onActivate case final activate?) {
              activate();
            } else if (widget.entry.target case final target?) {
              widget.onRevealTarget(target);
            } else if (hasChildren) {
              _expand(!_expanded);
            }
          },
          leading: Padding(
            padding: EdgeInsetsDirectional.only(
              start: widget.depth * MeridianLayout.treeIndent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: MeridianLayout.chevronSize,
                  child: hasChildren
                      ? MeridianIcon(
                          _expanded ? 'chevron-down' : 'chevron-right',
                          size: MeridianIconSize.small,
                          color: strong
                              ? context.colors.onAccent
                              : context.colors.inkMuted,
                        )
                      : null,
                ),
                const SizedBox(width: MeridianSpace.space3),
                Tooltip(
                  message: widget.entry.currentDescription ?? '',
                  child: MeridianGlideTarget(
                    selected: widget.entry.current,
                    child: SizedBox.square(
                      dimension: MeridianTheme.of(
                        context,
                      ).density.iconSmallSize,
                      child: MeridianIcon(
                        widget.entry.current
                            ? 'check'
                            : hasChildren
                            ? 'folder-closed'
                            : widget.entry.icon ?? widget.icon,
                        size: MeridianIconSize.small,
                        color: widget.entry.current
                            ? strong
                                  ? context.colors.onAccent
                                  : context.colors.accentInk
                            : strong
                            ? context.colors.onAccent
                            : context.colors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          titleTrailing:
              widget.entry.hostingCheck == null &&
                  widget.entry.hostingMergeability !=
                      HostingMergeability.conflicting
              ? null
              : Tooltip(
                  message: [
                    if (widget.entry.hostingCheck case final checks?)
                      switch (widget.entry.hostingCheckBranch) {
                        final branch? => context.l10n.hostingBranchChecks(
                          branch,
                          hostingCheckLabel(context, checks),
                        ),
                        null => hostingCheckLabel(context, checks),
                      },
                    ?hostingMergeabilityLabel(
                      context,
                      widget.entry.hostingMergeability,
                    ),
                  ].join('\n'),
                  child: SizedBox(
                    height: MeridianLayout.chevronSize,
                    child: HostingPullRequestStatus(
                      checks:
                          widget.entry.hostingCheck ??
                          HostingCheckState.unknown,
                      mergeability: widget.entry.hostingMergeability,
                    ),
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (filtered || holdsFiltered)
                Tooltip(
                  message: context.l10n.historyBranchFilterShown,
                  child: SizedBox.square(
                    key: const ValueKey('sidebar-ref-filtered'),
                    dimension: MeridianLayout.chevronSize,
                    child: MeridianIcon(
                      'list-filter',
                      size: MeridianIconSize.small,
                      color: strong
                          ? context.colors.onAccent
                          : filtered
                          ? context.colors.accentInk
                          : context.colors.inkMuted,
                    ),
                  ),
                ),
              if (widget.entry.ahead > 0 || widget.entry.behind > 0)
                GitLamaSyncBadge(
                  ahead: widget.entry.ahead,
                  behind: widget.entry.behind,
                  onAccent: strong,
                ),
              if (widget.entry.subtitle.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: GitLamaLayout.trackingLabelMaxWidth,
                  ),
                  child: Tooltip(
                    message:
                        widget.entry.trackingDescription ??
                        widget.entry.subtitle,
                    child: Text(
                      widget.entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.caption.copyWith(
                        color: context.colors.inkMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          semanticValue:
              widget.entry.currentDescription ??
              switch ((widget.entry.current, filtered)) {
                (true, true) =>
                  '${context.l10n.sidebarCurrentBranch}, '
                      '${context.l10n.historyBranchFilterShown}',
                (true, false) => context.l10n.sidebarCurrentBranch,
                (false, true) => context.l10n.historyBranchFilterShown,
                (false, false) => null,
              },
        ),
      ),
    );
    final hasMenu =
        widget.entry.commands.isNotEmpty || widget.entry.actions.isNotEmpty;
    if (hasMenu) {
      row = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) => _showActions(details.globalPosition),
        child: row,
      );
    }
    if (widget.entry.draggableMergeSource && widget.entry.target != null) {
      row = Draggable<_BranchDrag>(
        data: (
          name: widget.entry.commandName ?? widget.entry.name,
          target: widget.entry.target!,
        ),
        feedback: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.raised,
            borderRadius: BorderRadius.circular(context.meridian.radius.lg),
            boxShadow: context.meridian.shadows.shadowFloat,
          ),
          child: Padding(
            padding: const EdgeInsets.all(MeridianSpace.space4),
            child: Text(widget.entry.name),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.45, child: row),
        child: row,
      );
    }
    if (widget.entry.mergeDropTarget) {
      final dropChild = row;
      row = DragTarget<_BranchDrag>(
        onWillAcceptWithDetails: (details) =>
            details.data.target != widget.entry.target &&
            // The same policy as the command, not only the remote part.
            CommandAvailabilityScope.peek(context)?.reason(
                  AppCommandId.integrateBranch,
                  target: details.data.target,
                ) ==
                null,
        onAcceptWithDetails: (details) => widget.onCommand(
          AppCommandId.integrateBranch,
          initialName: details.data.name,
          initialTarget: details.data.target,
        ),
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border.all(color: context.colors.accent),
          ),
          child: dropChild,
        ),
      );
    }
    final wrapped = CallbackShortcuts(
      bindings: {
        for (final command in widget.entry.commands)
          if (widget.shortcuts[command] case final shortcut?)
            shortcut.activator: () => _run(command),
      },
      child: Focus(
        key: ValueKey(
          widget.depth == 0
              ? 'sidebar-ref-${widget.entry.treePath ?? widget.entry.name}'
              : 'sidebar-ref-${widget.depth}-${widget.entry.treePath ?? widget.entry.name}',
        ),
        focusNode: _focusNode,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (hasChildren &&
              (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  (event.logicalKey == LogicalKeyboardKey.enter &&
                      widget.entry.primaryCommand == null))) {
            _expand(
              event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  (event.logicalKey == LogicalKeyboardKey.enter && !_expanded),
            );
            return KeyEventResult.handled;
          }

          if (hasMenu &&
              (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                  (event.logicalKey == LogicalKeyboardKey.f10 &&
                      HardwareKeyboard.instance.isShiftPressed))) {
            final box = context.findRenderObject()! as RenderBox;
            unawaited(
              _showActions(box.localToGlobal(Offset(0, box.size.height))),
            );
            return KeyEventResult.handled;
          }
          final command = switch (event.logicalKey) {
            LogicalKeyboardKey.enter => widget.entry.primaryCommand,
            LogicalKeyboardKey.f2 =>
              widget.entry.commands.contains(AppCommandId.renameBranch)
                  ? AppCommandId.renameBranch
                  : widget.entry.commands.contains(AppCommandId.renameRemote)
                  ? AppCommandId.renameRemote
                  : widget.entry.commands.contains(AppCommandId.renameStash)
                  ? AppCommandId.renameStash
                  : null,
            LogicalKeyboardKey.delete =>
              widget.entry.commands.contains(AppCommandId.deleteBranch)
                  ? AppCommandId.deleteBranch
                  : widget.entry.commands.contains(
                      AppCommandId.deleteRemoteBranch,
                    )
                  ? AppCommandId.deleteRemoteBranch
                  : widget.entry.commands.contains(AppCommandId.deleteTag)
                  ? AppCommandId.deleteTag
                  : widget.entry.commands.contains(AppCommandId.removeRemote)
                  ? AppCommandId.removeRemote
                  : widget.entry.commands.contains(AppCommandId.dropStash)
                  ? AppCommandId.dropStash
                  : null,
            _ => null,
          };
          if (command == null) return KeyEventResult.ignored;
          _run(command);
          return KeyEventResult.handled;
        },
        child: row,
      ),
    );
    return wrapped;
  }
}
