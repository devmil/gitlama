import '../app_shortcut_activator.dart';
import 'command_availability.dart';
import '../../widgets/status_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/reference_name.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/history.dart';
import '../../models/history_graph.dart';
import '../../models/repository_state.dart';
import '../../services/repository_session_service.dart';
import '../../services/history_service.dart';
import '../../widgets/history_graph_view.dart';
import '../../widgets/history_motion.dart';
import '../../widgets/gitlama_scroll.dart';
import '../../widgets/find_bar_labels.dart';
import '../app_theme.dart';
import 'branch_filter.dart';
import 'hosting_links.dart';
import 'sidebar.dart';
import 'power_tools.dart';
import 'labels.dart';
import 'reference_projection.dart';
import 'reference_menu.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../services/workflows/workspace_effects.dart';
import 'workspace_scope.dart';
import 'shell_scopes.dart';
import '../../services/workflows/sync_change_tracker.dart';
import '../../services/workflows/workspace_navigator.dart';
import '../gitlama_layout.dart';

class HistoryPane extends StatefulWidget {
  const HistoryPane({
    required this.state,
    this.sync = const SyncChange(),
    required this.powerToolsVisible,
    required this.onClosePowerTools,
    required this.onRevealPowerCommit,
    required this.headObjectId,
    required this.selectedObjectId,
    required this.onCommand,
    required this.shortcuts,
    super.key,
  });

  final HistoryState state;

  /// What the last transfer changed, for the arriving rows' animation.
  final SyncChange sync;
  final bool powerToolsVisible;
  final VoidCallback onClosePowerTools;
  final ValueChanged<String> onRevealPowerCommit;
  final String? headObjectId;
  final String? selectedObjectId;
  final RunAppCommand onCommand;
  final Map<AppCommandId, AppShortcut?> shortcuts;

  @override
  State<HistoryPane> createState() => HistoryPaneState();
}

class HistoryPaneState extends State<HistoryPane>
    with TickerProviderStateMixin {
  final ScrollController _controller = ScrollController();

  /// The graph's motion (docs/design-system/specs/motion.md).
  late final HistoryMotion _motion = HistoryMotion(vsync: this);

  /// What lit the graph last time, per repository, to notice a change.
  String? _lighting;

  /// The search match last pointed at (NM-33).
  var _searchIndexSeen = -1;
  List<String> _searchMatchesSeen = const [];
  String? _attentionObjectId;
  var _attentionSequence = 0;

  /// Whether the working-tree row was shown, per repository (NM-36).
  String? _wipSeen;
  final FocusNode _queryFocusNode = FocusNode(debugLabel: 'history-find');
  final TextEditingController _queryController = TextEditingController();
  var _handledBranchFilterSequence = 0;
  var _handledRevealSequence = 0;
  BigInt? _handledRevealRequest;

  /// The window's reveal, flash and focus requests.
  WorkspaceEffects? _effects;
  StreamSubscription<WorkspaceEffect>? _effectSubscription;
  var _searchHash = true;
  var _searchMessage = true;
  var _searchAuthor = true;
  var _searchPath = false;
  var _showReflog = false;
  Future<ReflogPage>? _reflog;
  String? _flashObjectId;
  var _handledCommitSequence = 0;
  String? _pendingLandingId;
  int? _pendingLandingSequence;
  String? _dismissedStaleUpstream;
  String? _initialLaneDrawRepository;
  var _handledSyncSequence = 0;
  Set<String> _syncNewRows = const {};

  /// The date column's width and what it was measured for.
  Object? _dateWidthKey;
  var _dateWidth = 0.0;

  /// The repository the query, reflog and dismissed banner belong to. One
  /// pane serves every tab, so they follow the active repository.
  String? _shownRepository;

  WorkspaceServicesScope get _scope => WorkspaceServicesScope.read(context);
  RepositorySessionService get _repositories => _scope.repositories;
  HistoryService get _service => _repositories.history;
  WorkspaceNavigator get _navigator => _scope.workflows.navigator;
  String get _dateFormat => _scope.settings.current.appearance.dateFormat;

  /// Whether History also shows commits only other references reach, such
  /// as notes or another tool's checkpoints.
  bool get _otherRefs => _scope.settings.current.appearance.historyOtherRefs;

  /// Changes which references History starts from; the workspace reloads
  /// the shown history when the setting changes.
  void _setOtherRefs(bool value) => _scope.settings.updateAppearance(
    (appearance) => appearance.copyWith(historyOtherRefs: value),
  );

  /// Shows other references and selects [objectId] once the history that
  /// includes it has loaded.
  void _showOtherRefsFor(String? objectId) {
    _setOtherRefs(true);
    if (objectId != null) {
      unawaited(_navigator.showCommit(objectId, reload: false));
    }
  }

  /// The open pull request of each branch a row names.
  HostingLinks? get _hostingLinks => HostingScope.of(context).links;

  @override
  void initState() {
    super.initState();
    _shownRepository = _repositoryId;
  }

  void _effect(WorkspaceEffect effect) {
    if (!mounted) return;
    switch (effect.kind) {
      case WorkspaceEffectKind.focusHistorySearch:
        _effects?.handled(effect);
        _queryFocusNode.requestFocus();
      case WorkspaceEffectKind.flashCommit:
        setState(_syncCommitFlash);
      case WorkspaceEffectKind.revealCommit:
        _scheduleReveal();
      case WorkspaceEffectKind.commit ||
          WorkspaceEffectKind.conflictCommand ||
          WorkspaceEffectKind.createChangeRequest:
        break;
    }
  }

  /// Takes the query from the history service and drops the reflog and the
  /// dismissed stale banner when another repository becomes active.
  void _syncRepository() {
    final repository = _repositoryId;
    if (repository == _shownRepository) return;
    _shownRepository = repository;
    final query = _service.searchQuery ?? const HistoryQuery();
    _queryController.text = query.text;
    _searchHash = query.searchHash;
    _searchMessage = query.searchMessage;
    _searchAuthor = query.searchAuthor;
    _searchPath = query.searchPath;
    _showReflog = false;
    _reflog = null;
    _dismissedStaleUpstream = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final effects = WorkspaceServicesScope.maybeOf(context)?.workflows.effects;
    if (!identical(effects, _effects)) {
      _effects = effects;
      unawaited(_effectSubscription?.cancel());
      _effectSubscription = effects?.effects.listen(_effect);
      _syncCommitFlash(initial: true);
      // Find may have asked for the search field before this pane showed.
      if (effects?.take(WorkspaceEffectKind.focusHistorySearch) != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _queryFocusNode.requestFocus();
        });
      }
    }
    _scheduleReveal();
    _maybeLandCommit();
    _maybeDrawInitialLanes();
    _maybeAnimateSyncRows();
  }

  @override
  void didUpdateWidget(covariant HistoryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRepository();
    _syncCommitFlash();
    _scheduleReveal();
    _syncBranchFilterView();
    _syncMotion();
    _maybeLandCommit();
    _maybeDrawInitialLanes();
    _maybeAnimateSyncRows();
  }

  void _maybeAnimateSyncRows() {
    if (widget.sync.sequence <= _handledSyncSequence) return;
    final page = widget.state.page;
    if (page == null) return;
    if (page.requestId == widget.sync.previousHistoryRequestId) return;
    _handledSyncSequence = widget.sync.sequence;
    final repository = _repositoryId;
    if (repository == null ||
        !MeridianMotionMemory.of(
          context,
        ).markSeen(('history-sync-rows', repository, widget.sync.sequence))) {
      return;
    }
    final firstVisible = _controller.hasClients
        ? (_controller.offset / context.meridian.density.rowExtent).floor()
        : 0;
    final visibleCount = _controller.hasClients
        ? (_controller.position.viewportDimension /
                  context.meridian.density.rowExtent)
              .ceil()
        : GitLamaMotion.laneDrawMaxRows;
    final newIndices = <int>[
      for (
        var i = firstVisible;
        i < math.min(firstVisible + visibleCount, page.rows.length);
        i++
      )
        if (page.rows[i].objectId != historyWorktreeObjectId &&
            !widget.sync.previousRows.contains(page.rows[i].objectId))
          i,
    ];
    _syncNewRows = {
      for (final i in newIndices.take(MeridianMotionScales.staggerMax))
        page.rows[i].objectId,
    };
    if (newIndices.isNotEmpty) {
      _motion.drawLanes(
        newIndices.first,
        newIndices.length,
        delay: GitLamaMotion.pullLanesDelay,
        reduced: MeridianMotion.reduced(context),
      );
    }
  }

  void _maybeDrawInitialLanes() {
    if (widget.state.page == null) return;
    final repository = _repositoryId;
    if (repository == null || repository == _initialLaneDrawRepository) return;
    _initialLaneDrawRepository = repository;
    if (!MeridianMotionMemory.of(
      context,
    ).markSeen(('history-open-lanes', repository))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final extent = context.meridian.density.rowExtent;
      final visible = (_controller.position.viewportDimension / extent).ceil();
      _motion.drawLanes(
        0,
        math.min(visible, widget.state.page?.rows.length ?? 0),
        delay: MeridianDurations.select,
        reduced: MeridianMotion.reduced(context),
      );
    });
  }

  String? get _repositoryId {
    final identity = _repositories.activeTab?.session?.identity;
    return identity == null
        ? null
        : '${identity.nativeId}:${identity.generation}';
  }

  /// Tells the graph's motion what changed since the last build: the lit
  /// ancestry (NH-3), the search match reached (NM-33) and the
  /// working-tree row appearing or going (NM-36).
  void _syncMotion() {
    final page = widget.state.page;
    if (page == null) return;
    final reduced = MeridianMotion.reduced(context);
    final repository = _repositoryId;
    final lighting =
        '$repository|${page.lightingActive}|${page.currentObjectId}';
    final previousLighting = _lighting;
    _lighting = lighting;
    if (previousLighting != null &&
        previousLighting != lighting &&
        previousLighting.startsWith('$repository|')) {
      final current = page.currentObjectId;
      _motion.lightingChanged(
        focusIndex: current == null
            ? null
            : _service.indexOfLoadedObjectId(current),
        active: page.lightingActive,
        reduced: reduced,
      );
    }
    final matches = _service.searchMatches;
    final index = _service.searchIndex;
    if (identical(matches, _searchMatchesSeen) &&
        index != _searchIndexSeen &&
        index >= 0 &&
        _searchIndexSeen >= 0) {
      _attentionObjectId = matches[index];
      _attentionSequence++;
    }
    _searchMatchesSeen = matches;
    _searchIndexSeen = index;
    final wip =
        page.offset == 0 &&
        page.rows.isNotEmpty &&
        page.rows.first.objectId == historyWorktreeObjectId;
    final wipKey = '$repository|$wip';
    final previousWip = _wipSeen;
    _wipSeen = wipKey;
    if (previousWip != null &&
        previousWip != wipKey &&
        previousWip.startsWith('$repository|')) {
      if (wip) {
        // The working-tree row opens at the top and its ring draws.
        _motion.insertRow(0, reduced: reduced);
        _motion.drawLanes(0, 1, reduced: reduced);
      } else {
        _motion.removeRow(0, reduced: reduced);
      }
    }
  }

  /// Takes the window's latest commit flash for this repository; a new
  /// commit that is HEAD lands in the graph once its row shows.
  void _syncCommitFlash({bool initial = false}) {
    final effect = _effects?.latest(WorkspaceEffectKind.flashCommit);
    final flash = effect?.payload as CommittedFlash?;
    if (effect == null ||
        flash == null ||
        flash.repository != _repositories.activeTab?.canonicalIdentity) {
      return;
    }
    final sequence = effect.id;
    if (sequence <= _handledCommitSequence) return;
    _handledCommitSequence = sequence;
    _flashObjectId = flash.objectId;
    _pendingLandingId = null;
    _pendingLandingSequence = null;
    if (flash.amend) return;
    _pendingLandingId = flash.objectId;
    _pendingLandingSequence = sequence;
    if (!initial) _maybeLandCommit();
  }

  void _maybeLandCommit() {
    final objectId = _pendingLandingId;
    final sequence = _pendingLandingSequence;
    final page = widget.state.page;
    if (objectId == null || sequence == null || page == null) return;
    final row = page.rows.where((row) => row.objectId == objectId).firstOrNull;
    if (row == null) return;
    _pendingLandingId = null;
    _pendingLandingSequence = null;
    if (!row.current) return;
    final repository = _repositoryId;
    if (repository == null ||
        !MeridianMotionMemory.of(
          context,
        ).markSeen(('gitlama-commit-land', repository, sequence))) {
      return;
    }
    final reduced = MeridianMotion.reduced(context);
    _motion.landCommit(objectId, reduced: reduced);
    if (_controller.hasClients &&
        _controller.offset < context.meridian.density.rowExtent) {
      _motion.insertRow(1, reduced: reduced);
    }
  }

  /// Scrolls History to the commit the window's latest reveal names, once
  /// per reveal and only for the history request it was made in.
  void _scheduleReveal() {
    final page = widget.state.page;
    final effect = _effects?.latest(WorkspaceEffectKind.revealCommit);
    final reveal = effect?.payload as RevealCommit?;
    final index = reveal?.requestId == page?.requestId ? reveal?.index : null;
    final sequence = effect?.id ?? 0;
    if (_handledRevealRequest != page?.requestId) {
      _handledRevealRequest = page?.requestId;
      _handledRevealSequence = 0;
    }
    if (index == null || sequence <= _handledRevealSequence) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_controller.hasClients ||
          widget.state.page?.requestId != page?.requestId ||
          _effects?.latest(WorkspaceEffectKind.revealCommit)?.id != sequence ||
          sequence <= _handledRevealSequence) {
        return;
      }
      _handledRevealSequence = sequence;
      // A row already in view stays where it is; one out of view is
      // centred.
      final position = _controller.position;
      final target = gitlamaRevealOffset(
        index: index,
        extent: context.meridian.density.rowExtent,
        pixels: position.pixels,
        viewportDimension: position.viewportDimension,
        leadingPadding: HistoryGraphView.listPadding,
      );
      if (target == null) return;
      unawaited(gitlamaScrollTo(_controller, target, context));
    });
  }

  @override
  void dispose() {
    unawaited(_effectSubscription?.cancel());
    _motion.dispose();
    _controller.dispose();
    _queryFocusNode.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _applyQuery() {
    unawaited(
      _service.applyQuery(
        HistoryQuery(
          text: _queryController.text.trim(),
          searchHash: _searchHash,
          searchMessage: _searchMessage,
          searchAuthor: _searchAuthor,
          searchPath: _searchPath,
        ),
      ),
    );
  }

  HistoryBranchFilter get _branchFilter =>
      _repositories.activeTab?.navigation.branchFilter ??
      HistoryBranchFilter.none;

  void _setBranchFilter(HistoryBranchFilter filter) {
    final tab = _repositories.activeTab;
    if (tab == null) return;
    unawaited(_repositories.setBranchFilter(tab.id, filter));
  }

  /// A different branch filter's rows replace the graph: keep the selected
  /// commit in view when it survived, otherwise start at the top. Row motion
  /// would animate unrelated commits, so the new view is taken as seen.
  void _syncBranchFilterView() {
    final sequence = _service.branchFilterSequence;
    if (sequence == _handledBranchFilterSequence) return;
    _handledBranchFilterSequence = sequence;
    final page = widget.state.page;
    if (page == null) return;
    final repository = _repositoryId;
    _lighting = '$repository|${page.lightingActive}|${page.currentObjectId}';
    final wip =
        page.offset == 0 &&
        page.rows.isNotEmpty &&
        page.rows.first.objectId == historyWorktreeObjectId;
    _wipSeen = '$repository|$wip';
    final index = page.revealIndex ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final extent = context.meridian.density.rowExtent;
      _controller.jumpTo(
        (index * extent).clamp(0.0, _controller.position.maxScrollExtent),
      );
    });
  }

  /// Whether the typed query and scopes are the ones last searched.
  bool get _queryApplied {
    final applied = _service.searchQuery;
    final text = _queryController.text.trim();
    if (applied == null) return text.isEmpty;
    return applied.text == text &&
        applied.searchHash == _searchHash &&
        applied.searchMessage == _searchMessage &&
        applied.searchAuthor == _searchAuthor &&
        applied.searchPath == _searchPath;
  }

  /// Enter searches a new query and steps through the matches of the
  /// searched one.
  void _activateSearch({required bool backwards}) {
    if (!_queryApplied || _service.searchMatches.isEmpty) {
      _applyQuery();
      return;
    }
    unawaited(_service.navigateSearch(backwards: backwards));
  }

  void _clearSearch() {
    _queryController.clear();
    _applyQuery();
    _queryFocusNode.requestFocus();
  }

  void _toggleReflog() {
    setState(() {
      _showReflog = !_showReflog;
      if (_showReflog) _reflog = _service.reflog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.state.page;
    if (widget.state.phase == HistoryLoadPhase.loading) {
      return const _HistorySkeleton();
    }
    if (widget.state.phase == HistoryLoadPhase.failed) {
      return MeridianEmptyState(
        compact: true,
        icon: 'circle-alert',
        title: context.l10n.workspaceUnavailableRepository,
        action: MeridianButton(
          label: context.l10n.historyRetryLoad,
          icon: 'rotate-ccw',
          size: MeridianControlSize.small,
          onPressed: () {
            final identity = _repositories.activeTab?.session?.identity;
            if (identity != null) unawaited(_service.load(identity));
          },
        ),
      );
    }
    if (page == null) {
      return MeridianEmptyState(
        headline: true,
        title: context.l10n.historyNoCommitsYet,
        action: MeridianButton(
          label: context.l10n.historyOpenChanges,
          onPressed: () => widget.onCommand(AppCommandId.showChanges),
        ),
      );
    }
    final headBranch = _repositories.activeTab?.session?.snapshot.refs.branches
        .where(
          (branch) =>
              branch.head && branch.behind > 0 && branch.upstream != null,
        )
        .firstOrNull;
    final staleRef = headBranch == null
        ? null
        : switch (ReferenceName(headBranch.upstream!)) {
            final name when name.kind == ReferenceKind.remoteBranch =>
              name.display,
            final name => name.fullText,
          };
    final staleKey = staleRef == null
        ? null
        : '$staleRef:${headBranch!.behind}';
    final historyContent = Column(
      children: [
        _queryBar(context, page),
        if (widget.powerToolsVisible)
          PowerToolsPanel(
            key: ValueKey(_repositories.activeTab?.id),
            repositories: _repositories,
            onClose: widget.onClosePowerTools,
            onReveal: widget.onRevealPowerCommit,
            docked: true,
          ),
        if (staleKey != null && staleKey != _dismissedStaleUpstream)
          Padding(
            padding: const EdgeInsets.all(MeridianSpace.space2),
            child: MeridianBanner(
              tone: MeridianBannerTone.info,
              message: context.l10n.historyNewUpstreamCommits(
                headBranch!.behind,
                staleRef!,
              ),
              actions: [
                MeridianButton(
                  label: context.l10n.workspaceRefresh,
                  onPressed: () {
                    final identity = _repositories.activeTab?.session?.identity;
                    if (identity != null) {
                      unawaited(_service.load(identity));
                    }
                    setState(() => _dismissedStaleUpstream = staleKey);
                  },
                ),
                MeridianButton(
                  label: context.l10n.operationsDismiss,
                  variant: MeridianButtonVariant.quiet,
                  onPressed: () =>
                      setState(() => _dismissedStaleUpstream = staleKey),
                ),
              ],
            ),
          ),
        if (_showReflog)
          Expanded(child: _reflogView(context))
        else ...[
          if (_service.searchPending)
            _HistoryNotice(
              progress: true,
              message: context.l10n.historyPendingFilter(
                _service.searchQuery?.text ?? '',
              ),
            )
          else if (_service.searchFailureCode != null ||
              widget.state.queryFailureCode != null)
            _HistoryNotice(message: context.l10n.historyFilterFailed)
          else if (page.branchFilter.isNotEmpty && page.totalRows == 0)
            _HistoryNotice(
              message: context.l10n.historyBranchFilterNoCommits,
              action: MeridianButton(
                key: const ValueKey('history-branch-filter-show-all'),
                label: context.l10n.historyBranchFilterShowAll,
                size: MeridianControlSize.small,
                onPressed: () => _setBranchFilter(HistoryBranchFilter.none),
              ),
            )
          else if (widget.state.targetNotShown)
            _HistoryNotice(
              message: page.otherRefs
                  ? context.l10n.historyTargetNotShown
                  : context.l10n.historyTargetOutsideRefScope,
              action: page.otherRefs
                  ? null
                  : MeridianButton(
                      key: const ValueKey('history-show-other-refs'),
                      label: context.l10n.historyShowOtherRefs,
                      size: MeridianControlSize.small,
                      onPressed: () =>
                          _showOtherRefsFor(widget.state.targetObjectId),
                    ),
            )
          else if (page.selectedFilteredOut)
            _HistoryNotice(message: context.l10n.historySelectionFilteredOut)
          else if (page.queryActive)
            _HistoryNotice(
              message: context.l10n.historyAcceptedFilter(page.acceptedQuery),
            )
          else if (page.collapsedCommits > 0)
            _HistoryNotice(
              message: context.l10n.historyCollapsedCount(
                page.collapsedCommits,
              ),
            ),
          Expanded(
            child: page.rows.isEmpty
                ? MeridianEmptyState(
                    compact: true,
                    icon: 'history',
                    title: context.l10n.workspaceEmptyHistory,
                  )
                : ColoredBox(
                    color: context.colors.pane,
                    child: _graph(context, page),
                  ),
          ),
        ],
      ],
    );
    // Flutter's Linux accessibility tree retains detached History nodes as
    // commits replace graph rows. Keep the workaround scoped to this pane.
    return defaultTargetPlatform == TargetPlatform.linux
        ? ExcludeSemantics(child: historyContent)
        : historyContent;
  }

  Widget _queryBar(BuildContext context, HistoryPage page) {
    final selected = widget.selectedObjectId == null
        ? null
        : _service.rowById(widget.selectedObjectId!);
    final canCollapse = selected != null && selected.parents.length > 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: ColoredBox(
        key: const ValueKey('history-query-toolbar'),
        color: context.colors.pane,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MeridianSpace.space5,
            vertical: MeridianSpace.space2,
          ),
          child: IconTheme.merge(
            data: const IconThemeData(size: MeridianSize.icon),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(
                    GitLamaLayout.historyQueryToolbarMinWidth,
                    constraints.maxWidth,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        context.l10n.workspaceHistory,
                        style: context.text.bodyStrong.copyWith(
                          color: context.colors.ink,
                        ),
                      ),
                      const SizedBox(width: MeridianSpace.space5),
                      const Spacer(),
                      BranchFilterButton(
                        filter: _branchFilter,
                        onChanged: _setBranchFilter,
                        choices: () => ReferenceProjection.of(
                          _repositories.activeTab?.session?.snapshot.refs ??
                              const RepositoryRefs(),
                        ).branchFilterChoices,
                      ),
                      NativeMenuButton<_HistoryViewOption>(
                        key: const ValueKey('history-view-options'),
                        tooltip: context.l10n.historyViewOptions,
                        icon: const MeridianIcon('eye'),
                        iconSize: MeridianSize.icon,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: MeridianSize.controlSm,
                          height: MeridianSize.controlSm,
                        ),
                        onSelected: (option) => switch (option) {
                          _HistoryViewOption.otherRefs => _setOtherRefs(
                            !_otherRefs,
                          ),
                        },
                        itemBuilder: (context) => [
                          NativeMenuItem(
                            value: _HistoryViewOption.otherRefs,
                            checked: _otherRefs,
                            title: context.l10n.historyShowOtherRefs,
                          ),
                        ],
                      ),
                      const SizedBox(width: MeridianSpace.space3),
                      ListenableBuilder(
                        listenable: _queryController,
                        builder: (context, _) => MeridianFindBar(
                          fieldKey: const ValueKey('history-query'),
                          focusNode: _queryFocusNode,
                          controller: _queryController,
                          labels: gitLamaFindBarLabels(
                            context,
                            placeholder: context.l10n.historySearchHint,
                            searched: _queryApplied,
                          ),
                          matchCount: _service.searchMatches.length,
                          currentMatch: _service.searchIndex < 0
                              ? null
                              : _service.searchIndex,
                          searching: _service.searchPending,
                          // Clearing (typing, Clear, Escape) shows every
                          // commit again and keeps typing in the field.
                          onChanged: (value) {
                            if (value.isEmpty) _clearSearch();
                          },
                          onNext: () => _activateSearch(backwards: false),
                          onPrevious: () => _activateSearch(backwards: true),
                          trailing: [
                            NativeMenuButton<_HistorySearchScope>(
                              key: const ValueKey('history-search-scopes'),
                              tooltip: context.l10n.historySearchScopes,
                              icon: const MeridianIcon('list-filter-plus'),
                              iconSize: MeridianSize.icon,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: MeridianSize.controlSm,
                                height: MeridianSize.controlSm,
                              ),
                              onSelected: (scope) => setState(() {
                                switch (scope) {
                                  case _HistorySearchScope.hash:
                                    _searchHash = !_searchHash;
                                  case _HistorySearchScope.message:
                                    _searchMessage = !_searchMessage;
                                  case _HistorySearchScope.author:
                                    _searchAuthor = !_searchAuthor;
                                  case _HistorySearchScope.path:
                                    _searchPath = !_searchPath;
                                }
                              }),
                              itemBuilder: (context) => [
                                NativeMenuItem(
                                  value: _HistorySearchScope.hash,
                                  checked: _searchHash,
                                  title: context.l10n.historySearchHash,
                                ),
                                NativeMenuItem(
                                  value: _HistorySearchScope.message,
                                  checked: _searchMessage,
                                  title: context.l10n.historySearchMessage,
                                ),
                                NativeMenuItem(
                                  value: _HistorySearchScope.author,
                                  checked: _searchAuthor,
                                  title: context.l10n.historySearchAuthor,
                                ),
                                NativeMenuItem(
                                  value: _HistorySearchScope.path,
                                  checked: _searchPath,
                                  title: context.l10n.historySearchPath,
                                ),
                              ],
                            ),
                            MeridianIconButton(
                              key: const ValueKey('history-apply-filter'),
                              label: context.l10n.historyApplyFilter,
                              icon: 'inspect',
                              size: MeridianControlSize.small,
                              onPressed: _applyQuery,
                            ),
                          ],
                        ),
                      ),
                      MeridianIconButton(
                        key: const ValueKey('history-collapse-selected'),
                        label: context.l10n.historyCollapseSelected,
                        icon: 'git-merge',
                        size: MeridianControlSize.small,
                        onPressed: canCollapse
                            ? () => unawaited(
                                _service.toggleCollapse(selected.objectId),
                              )
                            : null,
                      ),
                      SizedBox(
                        height: MeridianSize.control,
                        child: MeridianButton(
                          key: const ValueKey('history-reflog-toggle'),
                          label: _showReflog
                              ? context.l10n.historyGraph
                              : context.l10n.historyReflog,
                          variant: MeridianButtonVariant.quiet,
                          icon: _showReflog ? 'branch' : 'history',
                          size: MeridianControlSize.small,
                          onPressed: _toggleReflog,
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
    );
  }

  String _shortHistoryObjectId(String value) =>
      value.substring(0, math.min(10, value.length));

  Widget _reflogView(BuildContext context) => FutureBuilder<ReflogPage>(
    future: _reflog,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return MeridianEmptyState(
          compact: true,
          progress: true,
          title: context.l10n.loading,
        );
      }
      final page = snapshot.data!;
      if (page.entries.isEmpty) {
        return MeridianEmptyState(
          compact: true,
          icon: 'history',
          title: context.l10n.historyReflogEmpty,
        );
      }
      return Column(
        children: [
          if (page.retainedAfterFailure)
            _HistoryNotice(message: context.l10n.historyReflogRetainedFailure),
          Expanded(
            child: ListView.builder(
              itemCount: page.entries.length,
              itemExtent: context.meridian.density.rowExtent,
              itemBuilder: (context, index) {
                final entry = page.entries[index];
                return MeridianListRow(
                  title: utf8.decode(entry.summary, allowMalformed: true),
                  leading: const MeridianIcon('history'),
                  trailing: Text(_shortHistoryObjectId(entry.commit)),
                  onTap: () {
                    setState(() => _showReflog = false);
                    unawaited(_service.select(entry.commit, reveal: true));
                  },
                );
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _graph(BuildContext context, HistoryPage page) => LayoutBuilder(
    builder: (context, constraints) {
      final selectedIds = page.selectedObjectIds.toSet();
      final refs =
          _repositories.activeTab?.session?.snapshot.refs ??
          const RepositoryRefs();
      final references = ReferenceProjection.of(refs);
      final metadata = _measureHistoryMetadata(context, constraints.maxWidth);
      final metadataLeft = math.max(
        180.0,
        constraints.maxWidth - metadata.reservation,
      );
      final graphClipRight = math.max(0.0, metadataLeft - MeridianSpace.space5);
      return Stack(
        children: [
          HistoryGraphView(
            itemCount: page.totalRows,
            indexOfObjectId: _service.indexOfLoadedObjectId,
            footer: Center(
              child: Text(
                context.l10n.historyEndOfHistory(
                  page.totalRows -
                      page.rows.where((row) => row.isWorktree).length,
                ),
                style: context.text.caption.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
            ),
            queryActive: page.queryActive,
            metadataAuthorWidth: metadata.author,
            metadataHashWidth: metadata.hash,
            metadataDateWidth: metadata.date,
            alignedUpstreams: references.alignedUpstreams,
            checkedOutRef: references.checkedOutRef,
            refSyncCounts: references.refSyncCounts,
            controller: _controller,
            rowExtent: context.meridian.density.rowExtent,
            selectedObjectId: widget.selectedObjectId,
            selectedObjectIds: selectedIds,
            lightingActive: page.lightingActive,
            isSelectable: (row) => !row.objectId.startsWith('loading-'),
            onSelected: _selectGraphRow,
            onDoubleClick: (target) => widget.onCommand(
              AppCommandId.checkoutCommit,
              initialTarget: target,
            ),
            onToggleSelected: _toggleGraphRow,
            onRevealObjectId: _navigator.revealIdentity,
            dateFormat: _dateFormat,
            headLabel: context.l10n.historyHeadReference,
            copiedLabel: context.l10n.historyHashCopied,
            flashObjectId: _flashObjectId,
            flashSequence: _handledCommitSequence,
            syncEntranceIds: _syncNewRows,
            syncSequence: _handledSyncSequence,
            motion: _motion,
            selectedIndex: widget.selectedObjectId == null
                ? null
                : _service.indexOfLoadedObjectId(widget.selectedObjectId!),
            attentionObjectId: _attentionObjectId,
            attentionSequence: _attentionSequence,
            semanticLabelBuilder: (row) => context.l10n.historyRowSemantics(
              _historyGraphRowSubject(context, row),
              utf8.decode(row.author, allowMalformed: true),
              row.objectId,
              row.authorTime == 0
                  ? ''
                  : DateTime.fromMillisecondsSinceEpoch(
                      row.authorTime * 1000,
                    ).toLocal().toIso8601String(),
              row.lane + 1,
              row.refs
                  .map((value) => utf8.decode(value, allowMalformed: true))
                  .join(', '),
              math.max(0, row.refCount - row.refs.length),
            ),
            onCopyValue: (value) {
              unawaited(
                copyWithStatusNotification(
                  context,
                  value,
                  context.l10n.historyObjectIdCopied,
                ),
              );
            },
            onContextMenu: (row) => _commitContextMenu(context, row),
            onOpenPullRequest: switch (_hostingLinks) {
              final links? => (pull) => links.onOpen(pull.webUrl),
              null => null,
            },
            onReferenceContextMenu: (row, reference) =>
                _commitContextMenu(context, row),
            rowAt: (index) {
              final row = _service.rowAt(index);
              if (row == null) {
                unawaited(_service.ensureIndex(index));
                return HistoryGraphRow(
                  objectId: 'loading-$index',
                  lane: 0,
                  shape: HistoryNodeShape.commit,
                  segments: const [],
                  geometry: HistoryRowGeometry(
                    metadataLeft: metadataLeft,
                    graphClipRight: graphClipRight,
                    contentStart: 40,
                    contentAvailable: (metadataLeft - 52)
                        .clamp(0, constraints.maxWidth)
                        .toDouble(),
                  ),
                );
              }
              final refs = [
                for (final reference in row.refs)
                  utf8.decode(reference, allowMalformed: true),
              ];
              final segments = [
                for (final segment in _service.segmentsFor(row.objectId))
                  HistoryGraphSegment(
                    fromLane: segment.fromLane,
                    toLane: segment.toLane,
                    kind: HistorySegmentKind.values[segment.kind],
                    startsAtTop: segment.startsAtTop,
                    endsAtCenter: segment.endsAtCenter,
                    lit: segment.lit,
                  ),
              ];
              final contentStart = math.min(
                historyRowContentStart(row.lane, segments),
                graphClipRight,
              );
              return HistoryGraphRow(
                objectId: row.objectId,
                lane: row.lane,
                shape: HistoryNodeShape.values[row.shape],
                segments: segments,
                geometry: HistoryRowGeometry(
                  metadataLeft: metadataLeft,
                  graphClipRight: graphClipRight,
                  contentStart: contentStart,
                  contentAvailable: (metadataLeft - contentStart - 12)
                      .clamp(0, constraints.maxWidth)
                      .toDouble(),
                ),
                subject: utf8.encode(_historyRowSubject(context, row)),
                author: row.author,
                avatarHash: row.avatarHash,
                refs: row.refs,
                refCount: row.refCount,
                pullRequests:
                    _hostingLinks?.pullRequestsForRefs(row.objectId, refs) ??
                    const {},
                branchChecks:
                    _hostingLinks?.defaultBranchChecksForRefs(
                      row.objectId,
                      refs,
                    ) ??
                    const {},
                authorTime: row.authorTime,
                lit: row.lit,
                selected: row.selected,
                compared: row.compared,
                searchMatch: _service.isSearchMatch(row.objectId),
                current: row.objectId == widget.headObjectId,
                wipChangedFiles: row.wipChangedFiles,
                wipStagedFiles: row.wipStagedFiles,
              );
            },
          ),
          if (widget.state.phase == HistoryLoadPhase.preview)
            const PositionedDirectional(
              top: MeridianSpace.space4,
              end: MeridianSpace.space4,
              child: MeridianSpinner(),
            ),
        ],
      );
    },
  );

  void _selectGraphRow(String objectId) {
    if (objectId == historyWorktreeObjectId) {
      widget.onCommand(AppCommandId.showChanges);
      return;
    }
    _navigator.selectIdentity(objectId);
  }

  void _toggleGraphRow(String objectId) {
    if (objectId == historyWorktreeObjectId) {
      widget.onCommand(AppCommandId.showChanges);
      return;
    }
    _navigator.toggleIdentity(objectId);
  }

  String _historyRowSubject(BuildContext context, HistoryTopologyRow row) {
    if (!row.isWorktree) {
      return utf8.decode(row.subject, allowMalformed: true);
    }
    return row.shape == HistoryNodeShape.wipConflict.index
        ? context.l10n.historyWorkingTreeConflicts(row.wipChangedFiles)
        : context.l10n.historyWorkingTreeChanges(
            row.wipChangedFiles,
            row.wipStagedFiles,
          );
  }

  String _historyGraphRowSubject(BuildContext context, HistoryGraphRow row) {
    if (row.objectId != historyWorktreeObjectId) {
      return utf8.decode(row.subject, allowMalformed: true);
    }
    return row.shape == HistoryNodeShape.wipConflict
        ? context.l10n.historyWorkingTreeConflicts(row.wipChangedFiles)
        : context.l10n.historyWorkingTreeChanges(
            row.wipChangedFiles,
            row.wipStagedFiles,
          );
  }

  /// Every reference at the commit is included, even when its chip is clipped.
  List<NativeMenuAction> _commitContextMenu(
    BuildContext context,
    HistoryGraphRow row,
  ) {
    if (row.objectId == historyWorktreeObjectId) return const [];
    final selected = widget.state.page?.selectedObjectIds ?? const <String>[];
    final inSelection = selected.length >= 2 && selected.contains(row.objectId);
    final snapshot = _repositories.activeTab?.session?.snapshot;
    final state =
        CommandAvailabilityScope.read(context) ??
        CommandMenuState(
          snapshot: snapshot,
          scopes: const {AppCommandShortcutScope.history},
          selectedCommits: selected,
          isMergeCommit: (id) =>
              id == row.objectId && row.shape == HistoryNodeShape.merge,
        );
    NativeMenuAction command(
      AppCommandId id, {
      bool selection = false,
      String? title,
    }) {
      final target = selection ? null : row.objectId;
      final reason = state.reason(id, target: target, contextual: true);
      return NativeMenuAction(
        value: () {
          if (!mounted) return;
          if (selection) {
            widget.onCommand(id);
          } else {
            widget.onCommand(id, initialTarget: row.objectId);
          }
        },
        title: title ?? commandLabel(context, id),
        icon: AppCommandRegistry.byId(id).icon,
        activator: widget.shortcuts[id]?.activator,
        enabled: reason == null,
        disabledReason: remoteMenuReason(context, reason),
        danger: AppCommandRegistry.byId(id).destructive,
      );
    }

    final entries = snapshot == null
        ? const <String, SidebarEntry>{}
        : ReferenceProjection.of(
                snapshot.refs,
              ).historyEntriesByCommit[row.objectId] ??
              const <String, SidebarEntry>{};
    final subject = utf8.decode(row.subject, allowMalformed: true);
    return [
      if (inSelection) ...[
        NativeMenuAction.submenu(
          title: context.l10n.menuSelectedCommits(selected.length),
          children: withDestructiveLast([
            command(AppCommandId.historyCompare, selection: true),
            command(AppCommandId.cherryPickSelected, selection: true),
            command(AppCommandId.revertSelected, selection: true),
            command(
              AppCommandId.createPatch,
              selection: true,
              title: context.l10n.patchCreateFromSelection,
            ),
          ]),
        ),
        const NativeMenuAction.separator(),
      ],
      ...withDestructiveLast([
        command(
          AppCommandId.revertSelected,
          title: context.l10n.historyRevertCommit,
        ),
        command(AppCommandId.cherryPickSelected),
        command(
          AppCommandId.createPatch,
          title: context.l10n.patchCreateFromCommit,
        ),
        command(AppCommandId.checkoutCommit),
        command(AppCommandId.saveCommitArchive),
        command(AppCommandId.createBranch),
        command(AppCommandId.createTag),
        command(AppCommandId.resetBranch),
        const NativeMenuAction.separator(),
        NativeMenuAction(
          value: () => unawaited(
            copyWithStatusNotification(
              context,
              row.objectId,
              context.l10n.menuCommitHashCopied,
            ),
          ),
          title: context.l10n.historyCopyObjectId,
          icon: 'copy',
        ),
        NativeMenuAction(
          value: () => unawaited(
            copyWithStatusNotification(
              context,
              subject,
              context.l10n.menuCommitSubjectCopied,
            ),
          ),
          title: context.l10n.historyCopySubject,
          icon: 'copy',
        ),
      ]),
      if (entries.isNotEmpty) const NativeMenuAction.separator(),
      for (final entry in entries.entries)
        if (entry.value.target == row.objectId)
          NativeMenuAction.submenu(
            title: entry.key,
            children: referenceMenuItems(
              context,
              entry: entry.value,
              reference: entry.key,
              shortcuts: widget.shortcuts,
              reason: (id) => state.reason(
                id,
                reference: entry.key,
                target: entry.value.target,
                current: entry.value.current,
                contextual: true,
              ),
              onCommand: widget.onCommand,
              branchFilter: (
                filter: _branchFilter,
                onChanged: _setBranchFilter,
              ),
            ),
          ),
    ];
  }

  ({double author, double hash, double date, double reservation})
  _measureHistoryMetadata(BuildContext context, double viewportWidth) {
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final authorWidth = (viewportWidth - 650).clamp(80.0, 132.0);
    final hashWidth = measure('0000000000', context.text.codeSm);
    final dateKey = (
      _dateFormat,
      Localizations.localeOf(context),
      MediaQuery.textScalerOf(context),
      context.text.rowMeta,
    );
    if (dateKey != _dateWidthKey) {
      _dateWidthKey = dateKey;
      _dateWidth = historyDateColumnWidth(
        context,
        _dateFormat,
        context.text.rowMeta,
      );
    }
    final dateWidth = _dateWidth;
    final reservation =
        MeridianSpace.space5 +
        authorWidth +
        MeridianSpace.space5 +
        hashWidth +
        MeridianSpace.space5 +
        dateWidth +
        MeridianSpace.space5;
    return (
      author: authorWidth,
      hash: hashWidth,
      date: dateWidth,
      reservation: reservation,
    );
  }
}

enum _HistorySearchScope { hash, message, author, path }

/// What the History view options menu changes.
enum _HistoryViewOption { otherRefs }

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  /// Three rows of subject, author and date bars (specs/graph.md §9).
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(MeridianSpace.space2),
    child: Column(
      children: [
        for (final fraction in const [0.6, 0.4, 0.2])
          SizedBox(
            height: context.meridian.density.rowExtent,
            child: Row(
              children: [
                Expanded(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: fraction,
                    child: const MeridianSkeleton(
                      delay: MeridianDurations.skeletonDelay,
                    ),
                  ),
                ),
                const SizedBox(width: MeridianSpace.space5),
                const MeridianSkeleton(
                  width: GitLamaLayout.historyAuthorWidth,
                  delay: MeridianDurations.skeletonDelay,
                ),
                const SizedBox(width: MeridianSpace.space5),
                const MeridianSkeleton(
                  width: GitLamaLayout.historyMetaSkeletonWidth,
                  delay: MeridianDurations.skeletonDelay,
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({
    required this.message,
    this.progress = false,
    this.action,
  });

  final String message;
  final bool progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MeridianSpace.space2,
        vertical: MeridianSpace.space1,
      ),
      child: MeridianBanner(
        message: message,
        tone: MeridianBannerTone.info,
        actions: [?(progress ? const MeridianSpinner() : null), ?action],
      ),
    ),
  );
}
