import 'package:devmil_logging/devmil_logging.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/diff.dart';
import '../../models/repository_state.dart';
import '../../services/diff_syntax_service.dart';
import '../../services/repository_session_service.dart';
import '../../widgets/diff_view.dart';
import '../../widgets/image_diff_view.dart';
import 'shell_chrome.dart';
import '../inspector/commit_diff_pane.dart';
import 'status_bar.dart';
import 'labels.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';
import '../../widgets/gitlama_scroll.dart';
import '../../widgets/find_bar_labels.dart';
import '../../models/working_tree.dart';
import '../../services/workflows/changes_service.dart';
import 'workspace_scope.dart';
import 'command_availability.dart';
import 'diff_view_preferences.dart';

class WorkingTreeDetailPane extends StatefulWidget {
  const WorkingTreeDetailPane({
    required this.tabId,
    required this.status,
    required this.selectedIdentity,
    required this.repositories,
    required this.side,
    required this.busy,
    required this.onStage,
    required this.onDiscard,
    required this.onCreatePatch,
    this.allowDiscard = true,
    this.stageDisabledReason,
    this.patchDisabledReason,
    super.key,
  });

  /// Whether discarding lines is offered at all.
  final bool allowDiscard;

  /// Why staging lines is unavailable, or null when it is offered.
  final String? stageDisabledReason;

  /// Why a patch cannot be created, or null.
  final String? patchDisabledReason;

  bool get _stageBlocked => busy || stageDisabledReason != null;

  final StagingSide side;
  final bool busy;
  final Future<void> Function(RepositoryStatusEntry, DiffPage, List<String>)
  onStage;
  final Future<void> Function(RepositoryStatusEntry, DiffPage, List<String>)
  onDiscard;

  /// Creates a patch of the file whose diff is on screen.
  final ValueChanged<RepositoryStatusEntry> onCreatePatch;

  /// The tab whose Changes this diff belongs to.
  final int tabId;
  final RepositoryStatus? status;
  final String? selectedIdentity;
  final RepositorySessionService repositories;

  @override
  State<WorkingTreeDetailPane> createState() => WorkingTreeDetailPaneState();
}

class WorkingTreeDetailPaneState extends State<WorkingTreeDetailPane>
    with DiffViewPreferencesState<WorkingTreeDetailPane> {
  static const _pageSize = 512;

  DiffLoadOptions _options = const DiffLoadOptions();
  DiffTextEncoding _encoding = DiffTextEncoding.utf8;
  DiffPage? _page;

  /// The syntax colours of [_page]'s diff.
  DiffSyntaxView? _syntax;
  final Set<String> _selectedRows = {};
  final Map<int, DiffDisplayRow> _rows = {};
  final Set<int> _loadingPages = {};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<int> _matches = const [];
  int _match = -1;
  bool _caseSensitive = false;
  String _searchedQuery = '';
  bool _searchedCaseSensitive = false;
  Object? _failure;
  var _loading = false;
  // Git has not answered for a while, typically because a large worktree's
  // status scan is still running. The load keeps going.
  var _waitingForGit = false;
  Timer? _waitingTimer;
  var _generation = 0;
  var _loadInFlight = false;
  var _loadQueued = false;
  var _quietLoad = false;
  double? _pendingScrollOffset;
  Set<String>? _priorContextPositions;
  Set<String> _revealContextIds = {};
  Timer? _contextRevealTimer;

  RepositoryStatusEntry? get _entry {
    final status = widget.status;
    if (status == null) return null;
    for (final entry in status.entries) {
      if (displayNativePath(entry.path) == widget.selectedIdentity) {
        return entry;
      }
    }
    return null;
  }

  ChangesService? _changes;
  StreamSubscription<ChangesEffect>? _effects;
  bool? _publishedRowsSelected;
  PaneCommandContext? _paneCommands;
  final FocusNode _paneFocus = FocusNode();
  late final PaneCommandHandler _handler = PaneCommandHandler(
    run: (_) {},
    focusFind: _focusFind,
    hasFocus: () => _paneFocus.hasFocus,
  );

  /// Focuses the find field with its query selected, for Find.
  bool _focusFind() {
    if (_searchFocus.context == null) return false;
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _options = diffPreferences.applyTo(_options);
    _scheduleLoad();
  }

  @override
  bool diffLoadedOtherwise(DiffViewPreferences preferences) =>
      !preferences.loads(_options);

  @override
  void loadDiffPreferences(DiffViewPreferences preferences) =>
      _applyOptions(preferences.applyTo(_options));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paneCommands = PaneCommandContextScope.maybeOf(context);
    if (!identical(paneCommands, _paneCommands)) {
      _paneCommands?.withdrawHandler(PaneRole.workingDiff, _handler);
      _paneCommands = paneCommands
        ?..registerHandler(PaneRole.workingDiff, _handler);
    }
    final changes = WorkspaceServicesScope.maybeOf(context)?.workflows.changes;
    if (identical(changes, _changes)) return;
    _changes = changes;
    unawaited(_effects?.cancel());
    // Stage, unstage and Discard act on the lines selected here.
    _effects = changes?.effects.listen((effect) {
      if (!mounted ||
          effect is! DiffSelectionRequested ||
          effect.tabId != widget.tabId) {
        return;
      }
      effect.discard ? discardSelection() : stageSelection();
    });
  }

  /// Tells the Changes workflows whether lines are selected here, once
  /// the frame that changed it is done.
  void _publishRowsSelected() {
    final selected = hasSelectedRows;
    if (selected == _publishedRowsSelected) return;
    _publishedRowsSelected = selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changes?.setDiffRowsSelected(widget.tabId, selected);
    });
  }

  @override
  void dispose() {
    _paneCommands?.withdrawHandler(PaneRole.workingDiff, _handler);
    _paneFocus.dispose();
    unawaited(_effects?.cancel());
    _changes?.setDiffRowsSelected(widget.tabId, false);
    _contextRevealTimer?.cancel();
    _waitingTimer?.cancel();
    _retireSyntax();
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkingTreeDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIdentity != widget.selectedIdentity ||
        oldWidget.side != widget.side) {
      // Another file is detected as Git sees it again.
      _options = _options.copyWith(forceText: false);
      _scheduleLoad();
    } else if (oldWidget.status != widget.status) {
      // Any file change publishes a new status. Reload in place so an
      // unaffected diff keeps its rows, scroll position and selection.
      _scheduleLoad(preserveSelection: true, quiet: true);
    }
  }

  /// [quiet] reloads the same file without clearing what is shown: the new
  /// diff replaces the old one once its loaded pages are fetched again.
  void _scheduleLoad({bool preserveSelection = false, bool quiet = false}) {
    _generation += 1;
    if (!preserveSelection) _selectedRows.clear();
    _quietLoad = _loadQueued ? _quietLoad && quiet : quiet;
    _loadQueued = true;
    if (!_loadInFlight) unawaited(_drainLoads());
  }

  void _applyOptions(DiffLoadOptions options) {
    if (options.layout == _options.layout &&
        options.contextLines == _options.contextLines &&
        options.whitespace == _options.whitespace &&
        options.forceText == _options.forceText) {
      return;
    }
    final preserveSelection =
        options.contextLines == _options.contextLines &&
        options.whitespace == _options.whitespace;
    _priorContextPositions = options.contextLines > _options.contextLines
        ? {
            for (final row in _rows.values)
              if (row.kind == DiffRowKind.context) diffContextPosition(row),
          }
        : null;
    _pendingScrollOffset = _scroll.hasClients ? _scroll.offset : null;
    _options = options;
    _scheduleLoad(preserveSelection: preserveSelection);
  }

  Future<void> _drainLoads() async {
    _loadInFlight = true;
    try {
      while (mounted && _loadQueued) {
        _loadQueued = false;
        await _load(_generation, quiet: _quietLoad);
      }
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _load(int generation, {bool quiet = false}) async {
    final entry = _entry;
    if (entry == null) {
      setState(() {
        _page = null;
        _rows.clear();
        _loadingPages.clear();
        _clearSearchState(clearField: true);
        _failure = null;
        _loading = false;
      });
      return;
    }
    final side = widget.side == StagingSide.staged && entry.staged
        ? StagingSide.staged
        : entry.unstaged
        ? StagingSide.unstaged
        : StagingSide.staged;
    final (oldPath, newPath) = diffPaths(entry, side);
    final inPlace = quiet && _page != null && _failure == null;
    if (!inPlace) {
      setState(() {
        _loading = true;
        _failure = null;
        _page = null;
        _retireSyntax();
        _rows.clear();
        _loadingPages.clear();
        _clearSearchState(clearField: true);
      });
    }
    _waitingTimer?.cancel();
    _waitingTimer = Timer(_waitingNotice, () {
      if (mounted && generation == _generation && _loading) {
        setState(() => _waitingForGit = true);
      }
    });
    try {
      final DiffPage page;
      try {
        page = await _diffUntilAnswered(generation, side, oldPath, newPath);
      } finally {
        if (generation == _generation) {
          _waitingTimer?.cancel();
          _waitingForGit = false;
        }
      }
      if (!mounted || generation != _generation) return;
      if (inPlace) {
        await _replaceInPlace(page, generation);
        return;
      }
      setState(() {
        _page = page;
        _storePage(page);
        _markNewContextRows();
        _loading = false;
      });
      _scheduleContextRevealClear();
      final offset = _pendingScrollOffset;
      _pendingScrollOffset = null;
      if (offset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation || !_scroll.hasClients) {
            return;
          }
          _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
        });
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      assert(() {
        final code = error is RepositorySessionException
            ? error.failure.code.name
            : error.runtimeType.toString();
        recordDiagnostic(
          DiagnosticEvent('working_diff_load_failed.$code', detailed: true),
        );
        return true;
      }());
      setState(() {
        _failure = Object();
        _loading = false;
      });
    }
  }

  /// How long a diff may load before the pane says it is waiting for Git.
  static const _waitingNotice = Duration(seconds: 2);

  /// Loads the diff, asking again while Git has not answered and the same
  /// change stays selected. Each retry resumes the read already running.
  Future<DiffPage> _diffUntilAnswered(
    int generation,
    StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
  ) async {
    while (true) {
      try {
        return await widget.repositories.workingCopy.diff(
          side: side,
          oldPath: oldPath,
          newPath: newPath,
          contextLines: _options.contextLines,
          whitespace: _options.whitespace,
          layout: _options.layout,
          forceText: _options.forceText,
          maximumRows: _pageSize,
        );
      } on RepositorySessionException catch (error) {
        if (error.failure.code != RepositoryFailureCode.timedOut ||
            !mounted ||
            generation != _generation) {
          rethrow;
        }
        if (!_waitingForGit) setState(() => _waitingForGit = true);
      }
    }
  }

  /// Swaps in [page] after fetching every other page shown so far, so rows
  /// never fall back to placeholders. Selection keeps the rows that still
  /// exist; an active search runs again on the new diff.
  Future<void> _replaceInPlace(DiffPage page, int generation) async {
    final offsets = {
      for (final index in _rows.keys) (index ~/ _pageSize) * _pageSize,
    }..remove(page.offset);
    final pages = [page];
    for (final offset in offsets) {
      if (offset >= page.totalRows) continue;
      final next = await widget.repositories.workingCopy.diffPage(
        requestId: page.requestId,
        offset: offset,
        maximumRows: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      pages.add(next);
    }
    setState(() {
      _page = page;
      _rows.clear();
      _loadingPages.clear();
      for (final value in pages) {
        _storePage(value);
      }
      _markNewContextRows();
      final ids = {for (final row in _rows.values) row.stableId};
      _selectedRows.retainAll(ids);
      _loading = false;
    });
    _scheduleContextRevealClear();
    if (_searchedQuery.isNotEmpty) await _runSearch(reveal: false);
  }

  Future<void> _loadPage(int offset) async {
    final page = _page;
    if (page == null || offset < 0 || offset >= page.totalRows) return;
    if (!_loadingPages.add(offset)) return;
    final generation = _generation;
    try {
      final next = await widget.repositories.workingCopy.diffPage(
        requestId: page.requestId,
        offset: offset,
        maximumRows: _pageSize,
      );
      if (!mounted ||
          generation != _generation ||
          next.requestId != _page?.requestId) {
        return;
      }
      setState(() {
        _storePage(next);
        _loadingPages.remove(offset);
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = Object();
        _loadingPages.remove(offset);
      });
    }
  }

  void _storePage(DiffPage page) {
    for (var index = 0; index < page.rows.length; index += 1) {
      _rows[page.offset + index] = page.rows[index];
    }
    // The rows show as plain text now; colours follow when the user idles.
    if (_syntax?.diffRequestId != page.requestId) {
      _retireSyntax();
      _syntax = widget.repositories.workingCopy.syntaxView(page.requestId);
    }
    _syntax?.accept(page);
  }

  void _retireSyntax() {
    _syntax?.dispose();
    _syntax = null;
  }

  void _markNewContextRows() {
    final prior = _priorContextPositions;
    _priorContextPositions = null;
    _revealContextIds = prior == null
        ? {}
        : {
            for (final row in _rows.values)
              if (row.kind == DiffRowKind.context &&
                  !prior.contains(diffContextPosition(row)))
                row.stableId,
          };
  }

  void _scheduleContextRevealClear() {
    _contextRevealTimer?.cancel();
    if (_revealContextIds.isEmpty) return;
    _contextRevealTimer = Timer(MeridianDurations.layout, () {
      if (mounted) setState(() => _revealContextIds = {});
    });
  }

  DiffDisplayRow _rowAt(int index) {
    if (_rows[index] case final row?) return row;
    final offset = (index ~/ _pageSize) * _pageSize;
    unawaited(_loadPage(offset));
    return DiffDisplayRow(
      stableId: 'working-loading-${_page?.requestId}-$index',
      kind: DiffRowKind.context,
      text: utf8.encode('…'),
      loading: true,
    );
  }

  /// The changed lines among the selected rows: only they can be staged,
  /// unstaged or discarded. Selected context lines are for copying, as are
  /// all lines of a binary file shown as text.
  List<String> _changeRows([Iterable<String>? ids]) {
    if (_options.forceText) return const [];
    final selected = (ids ?? _selectedRows).toSet();
    return [
      for (final row in _rows.values)
        if (row.selectable && selected.contains(row.stableId)) row.stableId,
    ];
  }

  bool get hasSelectedRows => _changeRows().isNotEmpty;

  void stageSelection() {
    if (widget.stageDisabledReason == null) {
      unawaited(_applyRows(_changeRows()));
    }
  }

  void discardSelection() {
    if (_canDiscard) {
      unawaited(_applyRows(_changeRows(), discard: true));
    }
  }

  String get _stageLabel => widget.side == StagingSide.staged
      ? context.l10n.diffSelectionUnstage
      : context.l10n.diffSelectionStage;

  List<NativeMenuAction> _menuItems(List<String> ids) {
    final rows = _changeRows(ids);
    final disabled = widget.busy || rows.isEmpty;
    return [
      NativeMenuAction(
        value: () => unawaited(_applyRows(rows)),
        title: _stageLabel,
        icon: widget.side == StagingSide.staged ? 'minus' : 'plus',
        enabled: !disabled && widget.stageDisabledReason == null,
      ),
      if (_canDiscard)
        NativeMenuAction(
          value: () => unawaited(_applyRows(rows, discard: true)),
          title: context.l10n.diffSelectionDiscard,
          icon: 'trash',
          enabled: !disabled,
          danger: true,
        ),
    ];
  }

  Future<List<int>?> _selectionPatch(List<String> ids) async {
    final page = _page;
    if (page == null) return null;
    try {
      return await widget.repositories.workingCopy.selectionPatch(
        requestId: page.requestId,
        rowIds: ids,
      );
    } on RepositorySessionException {
      return null;
    }
  }

  bool get _canDiscard =>
      widget.allowDiscard && canDiscardLines(_entry, widget.side);

  Future<void> _applyRows(List<String> rows, {bool discard = false}) async {
    final page = _page;
    final entry = _entry;
    if (widget.busy || page == null || entry == null || rows.isEmpty) return;
    if (discard) {
      await widget.onDiscard(entry, page, rows);
    } else {
      await widget.onStage(entry, page, rows);
    }
    if (mounted) _scheduleLoad(quiet: true);
  }

  Widget _hunkButton(String label, String hunk, {bool discard = false}) =>
      MeridianButton(
        key: ValueKey('${discard ? 'discard' : 'stage'}-hunk-$hunk'),
        label: label,
        icon: discard
            ? 'undo'
            : widget.side == StagingSide.staged
            ? 'unstage-all'
            : 'stage-all',
        variant: discard
            ? MeridianButtonVariant.dangerQuiet
            : MeridianButtonVariant.secondary,
        size: MeridianControlSize.small,
        disabledReason: discard ? null : widget.stageDisabledReason,
        onPressed: widget.busy || (!discard && widget._stageBlocked)
            ? null
            : () => unawaited(_applyRows([hunk], discard: discard)),
      );

  /// Stage or unstage, and discard, on the lines the text selection
  /// touches; none when those lines hold no change.
  Widget? _selectionActions(List<String> ids) {
    final rows = _changeRows(ids);
    if (rows.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: MeridianSpace.space2,
      children: [
        MeridianButton(
          key: const ValueKey('diff-selection-stage'),
          label: _stageLabel,
          variant: MeridianButtonVariant.secondary,
          size: MeridianControlSize.small,
          disabledReason: widget.stageDisabledReason,
          onPressed: widget._stageBlocked
              ? null
              : () => unawaited(_applyRows(rows)),
        ),
        if (_canDiscard)
          MeridianButton(
            key: const ValueKey('diff-selection-discard'),
            label: context.l10n.diffSelectionDiscard,
            variant: MeridianButtonVariant.secondary,
            size: MeridianControlSize.small,
            onPressed: widget.busy
                ? null
                : () => unawaited(_applyRows(rows, discard: true)),
          ),
      ],
    );
  }

  Widget _hunkActions(DiffDisplayRow row) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_canDiscard)
        _hunkButton(context.l10n.discardHunk, row.stableId, discard: true),
      _hunkButton(
        widget.side == StagingSide.staged
            ? context.l10n.unstageHunk
            : context.l10n.stageHunk,
        row.stableId,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    _publishRowsSelected();
    final tokens = context.meridian;
    final imageRow = imageDiffRow(_rows.values);
    final entry = _entry;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f3): () =>
            unawaited(_activateSearch()),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            unawaited(_activateSearch(backwards: true)),
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: Focus(
        focusNode: _paneFocus,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.colors.pane,
            border: Border(left: BorderSide(color: tokens.colors.line)),
          ),
          child: Column(
            children: [
              detailSectionHeader(
                context,
                metadata: entry == null ? null : statusCode(entry),
              ),
              if (_loading) const MeridianProgressBar(),
              Expanded(
                child: entry == null
                    ? MeridianEmptyState(
                        compact: true,
                        icon: 'inspect',
                        title: context.l10n.workspaceNoSelection,
                      )
                    : _failure != null
                    ? MeridianEmptyState(
                        compact: true,
                        icon: 'circle-alert',
                        title: context.l10n.workingDiffFailed,
                      )
                    : _page == null
                    ? _waitingForGit
                          ? MeridianEmptyState(
                              compact: true,
                              icon: 'hourglass',
                              title: context.l10n.workingDiffWaitingForGit,
                              message:
                                  context.l10n.workingDiffWaitingForGitDetail,
                            )
                          : const SizedBox.shrink()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: MeridianSpace.space4,
                              vertical: MeridianSpace.space3,
                            ),
                            child: Row(
                              children: [
                                const MeridianIcon('file'),
                                const SizedBox(width: MeridianSpace.space3),
                                Expanded(
                                  child: Text(
                                    widget.selectedIdentity!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const MeridianHairline(),
                          SizedBox(
                            key: const ValueKey('working-diff-toolbar-surface'),
                            width: double.infinity,
                            child: ColoredBox(
                              color: tokens.colors.pane,
                              child: Padding(
                                padding: EdgeInsets.zero,
                                child: DiffToolbar(
                                  path: widget.selectedIdentity!,
                                  pinned: [
                                    MeridianIconButton(
                                      key: const ValueKey(
                                        'working-diff-create-patch',
                                      ),
                                      label: context.l10n.diffCreatePatch,
                                      icon: 'file-diff',
                                      size: MeridianControlSize.small,
                                      disabledReason:
                                          widget.patchDisabledReason,
                                      onPressed:
                                          widget.busy ||
                                              _entry == null ||
                                              widget.patchDisabledReason != null
                                          ? null
                                          : () => widget.onCreatePatch(_entry!),
                                    ),
                                  ],
                                  children: [
                                    ListenableBuilder(
                                      listenable: _search,
                                      builder: (context, _) => MeridianFindBar(
                                        fieldKey: const Key(
                                          'working-diff-search',
                                        ),
                                        controller: _search,
                                        focusNode: _searchFocus,
                                        labels: gitLamaFindBarLabels(
                                          context,
                                          placeholder:
                                              context.l10n.diffSearchHint,
                                          searched:
                                              _search.text == _searchedQuery &&
                                              _caseSensitive ==
                                                  _searchedCaseSensitive,
                                        ),
                                        matchCount: _matches.length,
                                        currentMatch: _match < 0
                                            ? null
                                            : _match,
                                        onChanged: (value) {
                                          if (value.isEmpty) _clearSearch();
                                        },
                                        onNext: () =>
                                            unawaited(_activateSearch()),
                                        onPrevious: () => unawaited(
                                          _activateSearch(backwards: true),
                                        ),
                                        caseSensitive: _caseSensitive,
                                        onCaseSensitiveChanged: (value) {
                                          setState(
                                            () => _caseSensitive = value,
                                          );
                                          if (_search.text.isNotEmpty) {
                                            unawaited(_runSearch());
                                          }
                                        },
                                      ),
                                    ),
                                    ...DiffViewingActions(
                                      // The stored choices: context widened
                                      // by Show More is not one of them.
                                      options: diffPreferences.applyTo(
                                        _options,
                                      ),
                                      onOptionsChanged: (value) =>
                                          changeDiffPreferences(
                                            diffPreferences.withLoadOptions(
                                              value,
                                            ),
                                          ),
                                      wrap: diffPreferences.wrap,
                                      onWrapChanged: (value) =>
                                          changeDiffPreferences(
                                            diffPreferences.copyWith(
                                              wrap: value,
                                            ),
                                          ),
                                      showIndicators:
                                          diffPreferences.showIndicators,
                                      onIndicatorsChanged: (value) =>
                                          changeDiffPreferences(
                                            diffPreferences.copyWith(
                                              showIndicators: value,
                                            ),
                                          ),
                                      showMinimap: diffPreferences.showMinimap,
                                      onMinimapChanged: (value) =>
                                          changeDiffPreferences(
                                            diffPreferences.copyWith(
                                              showMinimap: value,
                                            ),
                                          ),
                                      encoding: _encoding,
                                      onEncodingChanged: (value) =>
                                          setState(() => _encoding = value),
                                    ).buttons(context),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _page!.totalRows == 0
                                // Ignored whitespace, line-ending conversion
                                // or an empty file leave no rows.
                                ? MeridianEmptyState(
                                    compact: true,
                                    key: const ValueKey('working-diff-empty'),
                                    icon: 'file-diff',
                                    title: context.l10n.workingDiffEmpty,
                                  )
                                : imageRow != null
                                ? ImageDiffView(
                                    key: ValueKey(
                                      'image-diff-${_page!.requestId}-'
                                      '${imageRow.stableId}',
                                    ),
                                    load: () => widget.repositories.workingCopy
                                        .imageDiff(
                                          side: widget.side,
                                          oldPath: imageRow.oldPath,
                                          newPath: imageRow.newPath,
                                        ),
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: DiffView(
                                          // Per file, not per load: an in-place
                                          // reload keeps scroll and selection.
                                          key: ValueKey((
                                            widget.selectedIdentity,
                                            widget.side,
                                          )),
                                          syntax: _syntax,
                                          hunkActions: _options.forceText
                                              ? null
                                              : _hunkActions,
                                          onShowAsText: () => _applyOptions(
                                            _options.copyWith(forceText: true),
                                          ),
                                          selectionActions: _selectionActions,
                                          loadedRows: _rows.values,
                                          menuItems: _menuItems,
                                          onCopyPatch: _selectionPatch,
                                          itemCount: _page!.totalRows,
                                          hunkIndices: {
                                            for (final entry in _rows.entries)
                                              if (entry.value.kind ==
                                                  DiffRowKind.hunk)
                                                entry.key,
                                          },
                                          fallbackIndices: {
                                            for (final entry in _rows.entries)
                                              if (isDiffFallbackRow(
                                                entry.value,
                                                _encoding,
                                              ))
                                                entry.key,
                                          },
                                          rowAt: _rowAt,
                                          revealContextIds: _revealContextIds,
                                          onShowMoreContext:
                                              _options.contextLines < 10000
                                              ? () => _applyOptions(
                                                  _options.copyWith(
                                                    contextLines:
                                                        (_options.contextLines +
                                                                3)
                                                            .clamp(0, 10000),
                                                  ),
                                                )
                                              : null,
                                          layout: _page!.layout,
                                          selectedIds: _selectedRows,
                                          onSelectionChanged: (rows) =>
                                              setState(() {
                                                _selectedRows
                                                  ..clear()
                                                  ..addAll(rows);
                                              }),
                                          controller: _scroll,
                                          wrap: diffPreferences.wrap,
                                          showIndicators:
                                              diffPreferences.showIndicators,
                                          encoding: _encoding,
                                          searchMatchIndices: _matches.toSet(),
                                          currentSearchIndex: _match < 0
                                              ? null
                                              : _matches[_match],
                                        ),
                                      ),
                                      if (diffPreferences.showMinimap)
                                        DiffMinimap(
                                          controller: _scroll,
                                          totalRows: _page!.totalRows,
                                          rows: _rows,
                                          searchMatches: _matches.toSet(),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activateSearch({bool backwards = false}) async {
    final query = _search.text;
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    if (query != _searchedQuery ||
        _caseSensitive != _searchedCaseSensitive ||
        _matches.isEmpty) {
      await _runSearch(backwards: backwards);
      return;
    }
    _moveMatch(backwards ? -1 : 1);
  }

  /// [reveal] false refreshes the matches of a reloaded diff without moving
  /// the view.
  Future<void> _runSearch({bool backwards = false, bool reveal = true}) async {
    final page = _page;
    final query = _search.text;
    if (page == null || query.isEmpty) {
      _clearSearch();
      return;
    }
    try {
      final result = await widget.repositories.workingCopy.search(
        requestId: page.requestId,
        query: query,
        caseSensitive: _caseSensitive,
      );
      if (!mounted || result.requestId != _page?.requestId) return;
      setState(() {
        _searchedQuery = query;
        _searchedCaseSensitive = _caseSensitive;
        _matches = result.matches;
        _match = _matches.isEmpty
            ? -1
            : !reveal
            ? _match.clamp(0, _matches.length - 1)
            : (backwards ? _matches.length - 1 : 0);
      });
      if (reveal && _match >= 0) await _jumpTo(_matches[_match]);
    } on RepositorySessionException {
      if (mounted) _clearSearch();
    }
  }

  void _moveMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _match = (_match + delta) % _matches.length);
    unawaited(_jumpTo(_matches[_match]));
  }

  Future<void> _jumpTo(int row) async {
    if (!_rows.containsKey(row)) {
      await _loadPage((row ~/ _pageSize) * _pageSize);
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    await gitlamaScrollTo(_scroll, row * GitLamaLayout.diffLineHeight, context);
  }

  void _clearSearch() {
    setState(() {
      _search.clear();
      _clearSearchState();
    });
  }

  void _clearSearchState({bool clearField = false}) {
    if (clearField) _search.clear();
    _matches = const [];
    _match = -1;
    _searchedQuery = '';
    _searchedCaseSensitive = _caseSensitive;
  }
}
