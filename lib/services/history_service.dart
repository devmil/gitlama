import 'dart:math' as math;
import 'dart:async';

import '../models/history.dart';
import '../models/history_graph.dart';
import '../models/repository_view_cache.dart';
import '../models/repository_state.dart';
import '../repositories/history_repository.dart';
import '../models/remote_contract.g.dart';

/// Coordinates preview, complete topology and prioritized bounded metadata independently.
final class HistoryService {
  HistoryService(
    this._repository, {
    this._cachedFirstPage,
    this._onFirstPage,
    this._branchFilterFor,
    this._otherRefs,
  });

  /// Whether histories also start from references outside branches, remote
  /// branches, tags and the stash. Read at every load.
  final bool Function()? _otherRefs;

  /// The branch filter a repository's history should show when it loads.
  final HistoryBranchFilter Function(RepositorySessionIdentity session)?
  _branchFilterFor;

  /// The first page a repository showed when it was last open, if any. It
  /// stands in only under the branch filter it was shown with.
  final HistoryPage? Function(RepositorySessionIdentity session)?
  _cachedFirstPage;

  /// Receives each complete, hydrated first page of the history as shown
  /// under its branch filter.
  final void Function(RepositorySessionIdentity session, HistoryPage page)?
  _onFirstPage;

  /// Completes when a native page replaces a page presented from the cache.
  Completer<void>? _cacheReplaced;

  bool get _presentingCache =>
      _current.page?.requestId == cachedHistoryRequestId;

  final HistoryRepository _repository;
  final StreamController<HistoryState> _states =
      StreamController<HistoryState>.broadcast(sync: true);
  final StreamController<HistorySelection> _selections =
      StreamController<HistorySelection>.broadcast(sync: true);

  /// The commit or comparison last announced on [selections].
  ({String commit, String? base})? _shownSelection;
  int _operation = 0;
  int _selectionOperation = 0;
  List<String> _retainedSelectedObjectIds = const [];
  int _queryOperation = 0;
  RepositorySessionIdentity? _identity;
  HistoryState _current = const HistoryState(phase: HistoryLoadPhase.empty);
  bool _disposed = false;
  final _HistoryPages _pages = _HistoryPages();
  final Map<String, List<HistoryDisplaySegment>> _displaySegments = {};
  int? _displaySegmentsGeneration;
  int? _rowIndexGeneration;
  final Map<String, int> _rowIndex = {};
  int? _referencePickerGeneration;
  List<HistoryTopologyRow> _referencePickerCommits = const [];
  final Set<int> _loadingPages = {};
  HistoryQuery? _searchQuery;
  List<String> _searchMatches = const [];
  Set<String> _searchMatchSet = const {};
  int _searchIndex = -1;
  bool _searchPending = false;
  String? _searchFailureCode;

  /// The newest branch filter not yet sent to the native session. Requests
  /// made while one is in flight replace each other, so the native session
  /// always ends at the latest filter without replaying stale ones.
  ({RepositorySessionIdentity identity, HistoryBranchFilter filter})?
  _requestedFilter;
  Future<void>? _filterRunner;

  /// The newest branch filter change still being applied. A selection waits
  /// for it, so a reveal lands in the view that filter shows.
  Future<void>? _pendingFilter;

  /// The load replacing a shown history in place. Its page stays until the
  /// fresh topology is ready, though native no longer serves its request.
  int? _reloadingOperation;

  bool get _reloading =>
      _reloadingOperation != null && _reloadingOperation == _operation;
  int _branchFilterSequence = 0;

  Stream<HistoryState> get states => _states.stream;

  /// The commit or comparison the graph selects for inspection, whenever it
  /// changes. Reloads that keep the selection announce nothing.
  Stream<HistorySelection> get selections => _selections.stream;

  /// The session whose history is shown.
  RepositorySessionIdentity? get identity => _identity;

  /// Increments whenever a different branch filter's view is published, so
  /// the graph can restore its scroll position instead of animating rows.
  int get branchFilterSequence => _branchFilterSequence;
  HistoryState get current => _current;
  List<HistoryTopologyRow> referencePickerCommitsFor(
    RepositorySessionIdentity? identity,
  ) {
    if (identity == null ||
        _identity?.nativeId != identity.nativeId ||
        _identity?.generation != identity.generation) {
      return const [];
    }
    // Builds ask for this list on every frame. It changes only with the
    // loaded pages, and its identity lets consumers keep derived choices.
    if (_referencePickerGeneration != _pages.generation) {
      _referencePickerGeneration = _pages.generation;
      _referencePickerCommits = List.unmodifiable([
        for (final page in _pages.values)
          for (final row in page.rows)
            if (!row.isWorktree) row,
      ]);
    }
    return _referencePickerCommits;
  }

  HistoryQuery? get searchQuery => _searchQuery;
  List<String> get searchMatches => _searchMatches;
  int get searchIndex => _searchIndex;
  bool get searchPending => _searchPending;
  String? get searchFailureCode => _searchFailureCode;
  bool isSearchMatch(String objectId) => _searchMatchSet.contains(objectId);

  void clear() {
    _ensureActive();
    _operation += 1;
    _reloadingOperation = null;
    _selectionOperation += 1;
    _queryOperation += 1;
    _identity = null;
    _retainedSelectedObjectIds = const [];
    _pages.clear();
    _loadingPages.clear();
    _resetInspection();
    _clearSearch();
    _publish(const HistoryState(phase: HistoryLoadPhase.empty));
    _finishCachePresentation();
  }

  HistoryTopologyRow? rowAt(int index) {
    final offset = (index ~/ 512) * 512;
    final page = _pages[offset];
    if (page == null) return null;
    final local = index - page.offset;
    return local >= 0 && local < page.rows.length ? page.rows[local] : null;
  }

  int? indexOfLoadedObjectId(String objectId) => _loadedRowIndex[objectId];

  /// Object identity to absolute row index for every loaded page. Visible
  /// rows and selection ask repeatedly, so lookups must not scan the pages.
  Map<String, int> get _loadedRowIndex {
    if (_rowIndexGeneration != _pages.generation) {
      _rowIndexGeneration = _pages.generation;
      _rowIndex.clear();
      for (final page in _pages.values) {
        for (var index = 0; index < page.rows.length; index += 1) {
          // The first loaded occurrence wins, as the former scan did.
          _rowIndex.putIfAbsent(
            page.rows[index].objectId,
            () => page.offset + index,
          );
        }
      }
    }
    return _rowIndex;
  }

  List<HistoryDisplaySegment> segmentsFor(String objectId) {
    if (_displaySegmentsGeneration != _pages.generation) {
      final entries = _pages.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      _rebuildDisplaySegments(entries);
      _displaySegmentsGeneration = _pages.generation;
    }
    return _displaySegments[objectId] ?? const [];
  }

  void _rebuildDisplaySegments(List<MapEntry<int, HistoryPage>> pages) {
    _displaySegments.clear();
    final rowAt = <int, HistoryTopologyRow>{};
    final indexOf = <String, int>{};
    for (final entry in pages) {
      for (var local = 0; local < entry.value.rows.length; local += 1) {
        final index = entry.value.offset + local;
        final row = entry.value.rows[local];
        rowAt[index] = row;
        indexOf[row.objectId] = index;
      }
    }
    for (final entry in pages) {
      for (final segment in entry.value.segments) {
        final from = segment.fromRow ?? indexOf[segment.fromObjectId];
        final to = segment.toRow ?? indexOf[segment.toObjectId];
        final lit = segment.lit ?? rowAt[from]?.lit ?? false;
        if (from == null) continue;
        // A side branch joins its parent only on the parent's row. Curving on
        // the child row makes its continuation pass through unrelated commits.
        final lateJoin =
            segment.kind == HistorySegmentKind.join.index &&
            segment.fromLane != segment.toLane &&
            to != null &&
            to > from;
        // Native pages include crossing edges. Materialize only this page's
        // rows so the same edge returned on adjacent pages is never doubled.
        final pageStart = entry.value.offset;
        final pageEnd = pageStart + entry.value.rows.length;
        if (from >= pageStart && from < pageEnd) {
          (_displaySegments[segment.fromObjectId] ??= []).add(
            HistoryDisplaySegment(
              fromLane: segment.fromLane,
              toLane: lateJoin ? segment.fromLane : segment.toLane,
              kind: segment.kind,
              lit: lit,
            ),
          );
        }
        if (to == null || to <= from) continue;
        final first = math.max(from + 1, pageStart);
        final last = math.min(to, pageEnd - 1);
        for (var index = first; index <= last; index += 1) {
          final row = rowAt[index];
          if (row == null) continue;
          (_displaySegments[row.objectId] ??= []).add(
            HistoryDisplaySegment(
              fromLane: lateJoin ? segment.fromLane : segment.toLane,
              toLane: lateJoin && index != to
                  ? segment.fromLane
                  : segment.toLane,
              kind: segment.kind,
              lit: lit,
              startsAtTop: true,
              endsAtCenter: index == to,
            ),
          );
        }
      }
    }
  }

  HistoryTopologyRow? rowById(String objectId) => _rowById(objectId);

  Future<HistoryState>? _pendingLoad;

  Future<HistoryState> load(
    RepositorySessionIdentity identity, {
    List<String> priorityObjectIds = const [],
  }) {
    final pending = _load(identity, priorityObjectIds: priorityObjectIds);
    _pendingLoad = pending;
    return pending.whenComplete(() {
      if (identical(_pendingLoad, pending)) _pendingLoad = null;
    });
  }

  Future<HistoryState> _load(
    RepositorySessionIdentity identity, {
    List<String> priorityObjectIds = const [],
  }) async {
    _ensureActive();
    final shown = _current.page;
    // A history already on screen is replaced in place: its rows and the
    // inspected commit stay until the fresh topology is ready.
    final reloading =
        _identity == identity &&
        shown != null &&
        !_presentingCache &&
        (_current.phase == HistoryLoadPhase.preview ||
            _current.phase == HistoryLoadPhase.complete);
    if (_identity?.nativeId != identity.nativeId) {
      _retainedSelectedObjectIds = const [];
    } else if (_current.phase == HistoryLoadPhase.complete &&
        _current.page != null) {
      _retainedSelectedObjectIds = List.of(_current.page!.selectedObjectIds);
    }
    _identity = identity;
    _selectionOperation += 1;
    _queryOperation += 1;
    if (!reloading) {
      _resetInspection();
      _pages.clear();
      _loadingPages.clear();
      _clearSearch();
    }
    final operation = ++_operation;
    _reloadingOperation = reloading ? operation : null;
    final filter = _branchFilterFor?.call(identity) ?? HistoryBranchFilter.none;
    final otherRefs = _otherRefs?.call() ?? false;
    // What the repository showed last time stands in until it has loaded.
    // A graph shown under another branch filter or with other references
    // must never flash.
    final remembered = reloading ? null : _cachedFirstPage?.call(identity);
    final cached =
        remembered?.branchFilter == filter && remembered?.otherRefs == otherRefs
        ? remembered
        : null;
    final known = reloading ? shown : cached;
    _finishCachePresentation();
    if (reloading) {
      // The shown page stands in.
    } else if (cached == null) {
      _publish(const HistoryState(phase: HistoryLoadPhase.loading));
    } else {
      _cacheReplaced = Completer<void>();
      _pages[cached.offset] = cached;
      _publish(HistoryState(phase: HistoryLoadPhase.preview, page: cached));
    }
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        // Native keeps the filter across loads, so every page below arrives
        // already filtered.
        await _requestBranchFilter(identity, filter);
        if (!_accepts(identity, operation)) return _current;
        var preview = await _repository.loadHistory(
          identity,
          complete: false,
          otherRefs: otherRefs,
        );
        if (!_accepts(identity, operation)) return _current;
        // A filter can match nothing in a repository with history; its page
        // keeps the toolbar that clears it.
        if (preview.totalRows == 0 && preview.branchFilter.isEmpty) {
          _pages.clear();
          if (reloading) _finishReload(keepInspection: false);
          const empty = HistoryState(phase: HistoryLoadPhase.empty);
          _publish(empty);
          _finishCachePresentation();
          return empty;
        }
        if (known != null) preview = _withKnownMetadata(preview, known);
        if (!reloading) {
          _pages
            ..clear()
            ..[preview.offset] = preview;
          _publish(
            HistoryState(phase: HistoryLoadPhase.preview, page: preview),
          );
          _finishCachePresentation();
        }
        preview = await _hydrate(
          identity,
          operation,
          preview,
          priorityObjectIds,
        );
        if (!reloading && _accepts(identity, operation)) {
          _pages[preview.offset] = preview;
          _publish(
            HistoryState(phase: HistoryLoadPhase.preview, page: preview),
          );
        }

        var complete = await _repository.completeHistory(
          identity,
          requestId: preview.requestId,
        );
        if (!_accepts(identity, operation)) return _current;
        complete = _withKnownMetadata(complete, preview);
        if (_retainedSelectedObjectIds.isNotEmpty &&
            !_sameSelection(
              complete.selectedObjectIds,
              _retainedSelectedObjectIds,
            )) {
          complete = await _repository.selectHistory(
            identity,
            requestId: complete.requestId,
            objectId: null,
            reveal: false,
            focus: false,
            offset: 0,
          );
          if (!_accepts(identity, operation)) return _current;
        }
        for (final selectedId in _retainedSelectedObjectIds) {
          if (complete.selectedObjectIds.contains(selectedId)) continue;
          try {
            complete = await _repository.selectHistory(
              identity,
              requestId: complete.requestId,
              objectId: selectedId,
              toggle: true,
              reveal: false,
              focus: false,
              offset: 0,
            );
            if (!_accepts(identity, operation)) return _current;
          } on RepositorySessionException {
            // A selected commit can disappear when the repository changes.
          }
        }
        _retainedSelectedObjectIds = List.of(complete.selectedObjectIds);
        final keepInspection = reloading && _showsDetailOf(complete);
        if (reloading) _finishReload(keepInspection: keepInspection);
        _pages
          ..clear()
          ..[complete.offset] = complete;
        _publish(_loadedState(complete, keepInspection: keepInspection));
        complete = await _hydrate(
          identity,
          operation,
          complete,
          priorityObjectIds,
        );
        if (_accepts(identity, operation)) {
          _pages[complete.offset] = complete;
          final state = _loadedState(complete, keepInspection: keepInspection);
          _publish(state);
          if (isCacheableHistoryPage(complete)) {
            _onFirstPage?.call(identity, complete);
          }
          _restoreDetail(identity, operation);
          return state;
        }
        return _current;
      } on RepositorySessionException catch (error) {
        if (!_accepts(identity, operation)) return _current;
        if (attempt == 0 &&
            error.failure.code == RepositoryFailureCode.staleGeneration) {
          if (!_reloading) {
            _pages.clear();
            _publish(const HistoryState(phase: HistoryLoadPhase.loading));
          }
          _finishCachePresentation();
          continue;
        }
        _pages.clear();
        _finishReload(keepInspection: false);
        final state = HistoryState(
          phase: HistoryLoadPhase.failed,
          failureCode: error.failure.code.name,
        );
        _publish(state);
        _finishCachePresentation();
        return state;
      }
    }
    return _current;
  }

  /// Ends the in-place replacement of a shown history. The inspected commit
  /// stays only while the fresh history still selects it.
  void _finishReload({required bool keepInspection}) {
    _reloadingOperation = null;
    _loadingPages.clear();
    _clearSearch();
    if (!keepInspection) _resetInspection();
  }

  /// Forgets the announced selection, so the inspector shows nothing.
  void _resetInspection() {
    if (_shownSelection == null) return;
    _shownSelection = null;
    if (!_selections.isClosed) _selections.add(const HistorySelection());
  }

  HistoryState _loadedState(HistoryPage page, {required bool keepInspection}) =>
      HistoryState(
        phase: HistoryLoadPhase.complete,
        page: page,
        targetObjectId: keepInspection ? _current.targetObjectId : null,
      );

  /// The commit whose detail [page]'s selection asks for, if it is one.
  String? _detailObjectId(HistoryPage page) =>
      page.comparisonNewObjectId ??
      (page.selectedObjectIds.length == 1
          ? page.selectedObjectIds.single
          : null);

  bool _showsDetailOf(HistoryPage page) {
    final shown = _shownSelection;
    return shown != null &&
        shown.commit == _detailObjectId(page) &&
        shown.base == page.comparisonOldObjectId;
  }

  /// Native keeps a session's selection across loads, but the detail of the
  /// selected commit is loaded here. A selection made meanwhile replaces it.
  void _restoreDetail(RepositorySessionIdentity identity, int operation) {
    final page = _current.page;
    if (page == null || _showsDetailOf(page)) return;
    final newObjectId = _detailObjectId(page);
    if (newObjectId == null) return;
    _announce(
      page: page,
      oldObjectId: page.comparisonOldObjectId,
      newObjectId: newObjectId,
    );
  }

  void _finishCachePresentation() {
    final replaced = _cacheReplaced;
    _cacheReplaced = null;
    if (replaced != null && !replaced.isCompleted) replaced.complete();
  }

  /// A fresh topology arrives without subjects and authors. Rows the cache
  /// already described keep them, so the list does not blank while the
  /// metadata is read again.
  HistoryPage _withKnownMetadata(HistoryPage page, HistoryPage known) {
    final described = {
      for (final row in known.rows)
        if (row.hasMetadata) row.objectId: row,
    };
    if (described.isEmpty) return page;
    return HistoryPage(
      requestId: page.requestId,
      complete: page.complete,
      totalRows: page.totalRows,
      offset: page.offset,
      rows: [
        for (final row in page.rows)
          switch (described[row.objectId]) {
            final value? when !row.hasMetadata => row.withMetadata(
              HistoryMetadata(
                objectId: value.objectId,
                subject: value.subject,
                author: value.author,
                avatarHash: value.avatarHash,
                authorTime: value.authorTime,
                failure: value.metadataFailure,
              ),
            ),
            _ => row,
          },
      ],
      segments: page.segments,
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes,
      lightingActive: page.lightingActive,
      currentObjectId: page.currentObjectId,
      selectedObjectIds: page.selectedObjectIds,
      focusedObjectId: page.focusedObjectId,
      comparisonOldObjectId: page.comparisonOldObjectId,
      comparisonNewObjectId: page.comparisonNewObjectId,
      revealSequence: page.revealSequence,
      revealObjectId: page.revealObjectId,
      revealIndex: page.revealIndex,
      querySequence: page.querySequence,
      queryActive: page.queryActive,
      acceptedQuery: page.acceptedQuery,
      branchFilter: page.branchFilter,
      selectedFilteredOut: page.selectedFilteredOut,
      collapsedCommits: page.collapsedCommits,
      otherRefs: page.otherRefs,
    );
  }

  bool _sameSelection(List<String> left, List<String> right) =>
      left.length == right.length && left.toSet().containsAll(right);

  Future<HistoryPage> page(
    int offset, {
    int maximumRows = ContractLimits.pageRows,
  }) async {
    _ensureActive();
    final identity = _identity;
    final currentPage = _current.page;
    if (identity == null || currentPage == null) {
      throw StateError('history_not_loaded');
    }
    return _repository.historyPage(
      identity,
      requestId: currentPage.requestId,
      offset: offset,
      maximumRows: maximumRows,
    );
  }

  Future<void> ensureIndex(int index) async {
    _ensureActive();
    final identity = _identity;
    final currentPage = _current.page;
    if (identity == null ||
        currentPage == null ||
        index >= currentPage.totalRows ||
        // No native request serves this page; the loaded history asks again.
        _presentingCache ||
        _reloading) {
      return;
    }
    final offset = (index ~/ 512) * 512;
    if (_pages.containsKey(offset) || !_loadingPages.add(offset)) return;
    final operation = _operation;
    // A window of a replaced view would mix two graph layouts.
    final view = _pages.view;
    try {
      var loaded = await _repository.historyPage(
        identity,
        requestId: currentPage.requestId,
        offset: offset,
      );
      if (!_accepts(identity, operation) || _pages.view != view) return;
      loaded = await _hydrate(identity, operation, loaded, const []);
      if (!_accepts(identity, operation) || _pages.view != view) return;
      _pages[offset] = loaded;
      _publish(_current);
    } on RepositorySessionException {
      // The retained first page remains usable; refresh/retry owns topology replacement.
    } finally {
      _loadingPages.remove(offset);
    }
  }

  Future<void> select(
    String? objectId, {
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    int offset = 0,
    HistorySelectionOrigin origin = HistorySelectionOrigin.graph,
  }) async {
    _ensureActive();
    final pending = _pendingLoad;
    if (pending != null) {
      final intent = ++_selectionOperation;
      await pending;
      if (_disposed || intent != _selectionOperation) return;
    }
    if (_presentingCache) {
      // The selection belongs to the history that is still loading.
      final replaced = _cacheReplaced?.future;
      final intent = ++_selectionOperation;
      if (replaced == null) return;
      await replaced;
      if (_disposed || intent != _selectionOperation || _presentingCache) {
        return;
      }
    }
    if (_pendingFilter case final filtering?) {
      final intent = ++_selectionOperation;
      await filtering;
      if (_disposed || intent != _selectionOperation) return;
    }
    final identity = _identity;
    final currentPage = _current.page;
    if (identity == null || currentPage == null) return;
    final operation = _operation;
    final selectionOperation = ++_selectionOperation;
    final pagesView = _pages.view;
    _publish(
      HistoryState(
        phase: _current.phase,
        page: currentPage,
        targetObjectId: objectId,
      ),
    );
    try {
      final selection = await _repository.selectHistory(
        identity,
        requestId: currentPage.requestId,
        objectId: objectId,
        toggle: toggle,
        reveal: reveal,
        focus: focus,
        offset: offset,
      );
      if (!_acceptsSelection(identity, operation, selectionOperation)) return;
      final selected = _withKnownMetadata(
        selection,
        _pages[selection.offset] ?? currentPage,
      );
      _retainedSelectedObjectIds = List.of(selected.selectedObjectIds);
      final HistoryPage first;
      if (_pages.view == pagesView) {
        _pages[selected.offset] = selected;
        first = selected.offset == 0 ? selected : _pages[0] ?? currentPage;
      } else {
        // A newer view replaced the pages; keep it and load only the detail.
        first = _current.page ?? currentPage;
      }
      final newObjectId = _detailObjectId(selected);
      if (newObjectId == null) {
        _publish(HistoryState(phase: _current.phase, page: first));
        _resetInspection();
        return;
      }
      _announce(
        page: first,
        oldObjectId: selected.comparisonOldObjectId,
        newObjectId: newObjectId,
        origin: origin,
      );
    } on RepositorySessionException catch (error) {
      if (!_acceptsSelection(identity, operation, selectionOperation)) return;
      _publish(
        HistoryState(
          phase: _current.phase,
          page: _current.page,
          targetObjectId: objectId,
          // Native refuses a commit that is not part of the loaded history.
          targetNotShown:
              reveal &&
              objectId != null &&
              error.failure.code == RepositoryFailureCode.invalidOptions,
        ),
      );
    }
  }

  /// Publishes [newObjectId] (against [oldObjectId] for a comparison) as the
  /// selection and announces it for inspection.
  void _announce({
    required HistoryPage page,
    required String? oldObjectId,
    required String newObjectId,
    HistorySelectionOrigin origin = HistorySelectionOrigin.graph,
  }) {
    _publish(
      HistoryState(
        phase: _current.phase,
        page: page,
        targetObjectId: newObjectId,
      ),
    );
    final shown = _shownSelection;
    if (shown != null &&
        shown.commit == newObjectId &&
        shown.base == oldObjectId) {
      return;
    }
    _shownSelection = (commit: newObjectId, base: oldObjectId);
    _selections.add(
      HistorySelection(
        commit: newObjectId,
        base: oldObjectId,
        parents: _rowById(newObjectId)?.parents,
        origin: origin,
      ),
    );
  }

  Future<HistoryState> applyQuery(HistoryQuery query) async {
    _ensureActive();
    // The shown page of a reload names a request native no longer serves.
    if (_reloading) await _pendingLoad;
    final identity = _identity;
    final currentPage = _current.page;
    if (identity == null || currentPage == null) return _current;
    final operation = _operation;
    final queryOperation = ++_queryOperation;
    _searchQuery = query.text.isEmpty ? null : query;
    _searchMatches = const [];
    _searchMatchSet = const {};
    _searchIndex = -1;
    _searchPending = query.text.isNotEmpty;
    _searchFailureCode = null;
    _publish(
      HistoryState(
        phase: _current.phase,
        page: currentPage,
        targetObjectId: _current.targetObjectId,
        pendingQuery: query,
      ),
    );
    try {
      var matchesPage = await _repository.queryHistory(
        identity,
        requestId: currentPage.requestId,
        query: query,
      );
      if (!_acceptsQuery(identity, operation, queryOperation)) return _current;
      final matches = <String>[];
      void appendMatches(HistoryPage page) {
        matches.addAll(
          page.rows.where((row) => !row.isWorktree).map((row) => row.objectId),
        );
      }

      if (query.text.isNotEmpty) {
        appendMatches(matchesPage);
        for (
          var offset = matchesPage.rows.length;
          offset < matchesPage.totalRows;
          offset += 512
        ) {
          matchesPage = await _repository.historyPage(
            identity,
            requestId: matchesPage.requestId,
            offset: offset,
          );
          if (!_acceptsQuery(identity, operation, queryOperation)) {
            return _current;
          }
          appendMatches(matchesPage);
        }
      }
      var accepted = query.text.isEmpty
          ? matchesPage
          : await _repository.queryHistory(
              identity,
              requestId: matchesPage.requestId,
              query: const HistoryQuery(),
            );
      if (!_acceptsQuery(identity, operation, queryOperation)) return _current;
      _pages
        ..clear()
        ..[accepted.offset] = accepted;
      accepted = await _hydrate(identity, operation, accepted, const []);
      if (!_acceptsQuery(identity, operation, queryOperation)) return _current;
      _pages[accepted.offset] = accepted;
      _searchMatches = List.unmodifiable(matches);
      _searchMatchSet = Set.unmodifiable(matches);
      _searchIndex = matches.isEmpty ? -1 : 0;
      _searchPending = false;
      final state = HistoryState(
        phase: _current.phase,
        page: accepted,
        targetObjectId: _current.targetObjectId,
      );
      _publish(state);
      if (_searchIndex >= 0) {
        unawaited(select(_searchMatches[_searchIndex], reveal: true));
      }
      return state;
    } on RepositorySessionException catch (error) {
      if (!_acceptsQuery(identity, operation, queryOperation)) return _current;
      _searchPending = false;
      _searchFailureCode = error.failure.code.name;
      final state = HistoryState(
        phase: _current.phase,
        page: currentPage,
        targetObjectId: _current.targetObjectId,
        queryFailureCode: error.failure.code.name,
      );
      _publish(state);
      return state;
    }
  }

  /// Shows only the commits reachable from [filter]'s branches, or every
  /// commit for the empty filter. Rapid changes coalesce to the newest.
  Future<void> applyBranchFilter(HistoryBranchFilter filter) {
    _ensureActive();
    final applying = _applyBranchFilter(filter);
    _pendingFilter = applying;
    return applying.whenComplete(() {
      if (identical(_pendingFilter, applying)) _pendingFilter = null;
    });
  }

  Future<void> _applyBranchFilter(HistoryBranchFilter filter) async {
    final identity = _identity;
    if (identity == null) return;
    // A load under way read the filter it started with.
    if (_pendingLoad case final loading?) {
      await loading;
      if (_disposed || _identity != identity) return;
    }
    await _requestBranchFilter(identity, filter);
  }

  Future<void> _requestBranchFilter(
    RepositorySessionIdentity identity,
    HistoryBranchFilter filter,
  ) {
    _requestedFilter = (identity: identity, filter: filter);
    return _filterRunner ??= _drainBranchFilters().whenComplete(
      () => _filterRunner = null,
    );
  }

  Future<void> _drainBranchFilters() async {
    while (true) {
      final request = _requestedFilter;
      if (request == null || _disposed) return;
      _requestedFilter = null;
      await _sendBranchFilter(request.identity, request.filter);
    }
  }

  Future<void> _sendBranchFilter(
    RepositorySessionIdentity identity,
    HistoryBranchFilter filter,
  ) async {
    final currentPage = _current.page;
    final showing =
        _identity == identity &&
        currentPage != null &&
        !_presentingCache &&
        !_reloading;
    // A displayed native page shows the filter its session holds.
    if (showing && currentPage.branchFilter == filter) return;
    final operation = _operation;
    final queryOperation = showing ? ++_queryOperation : _queryOperation;
    try {
      var page = await _repository.filterHistoryBranches(
        identity,
        requestId: showing ? currentPage.requestId : BigInt.zero,
        filter: filter,
      );
      if (page == null ||
          // A newer request replaces this view before anyone sees it.
          _requestedFilter != null ||
          !_acceptsQuery(identity, operation, queryOperation) ||
          _current.page?.requestId != page.requestId) {
        return;
      }
      _clearSearch();
      _branchFilterSequence += 1;
      _pages
        ..clear()
        ..[page.offset] = page;
      _publish(
        HistoryState(
          phase: _current.phase,
          page: page,
          targetObjectId: _current.targetObjectId,
        ),
      );
      final view = _pages.view;
      page = await _hydrate(identity, operation, page, const []);
      if (!_acceptsQuery(identity, operation, queryOperation) ||
          _pages.view != view) {
        return;
      }
      _pages[page.offset] = page;
      _publish(
        HistoryState(
          phase: _current.phase,
          page: page,
          targetObjectId: _current.targetObjectId,
        ),
      );
      // The next visit starts from the graph this filter shows.
      if (isCacheableHistoryPage(page)) _onFirstPage?.call(identity, page);
    } on RepositorySessionException catch (error) {
      if (!showing || !_acceptsQuery(identity, operation, queryOperation)) {
        return;
      }
      _publish(
        HistoryState(
          phase: _current.phase,
          page: _current.page,
          targetObjectId: _current.targetObjectId,
          queryFailureCode: error.failure.code.name,
        ),
      );
    }
  }

  Future<void> navigateSearch({required bool backwards}) async {
    if (_searchMatches.isEmpty) return;
    _searchIndex = backwards
        ? (_searchIndex - 1 + _searchMatches.length) % _searchMatches.length
        : (_searchIndex + 1) % _searchMatches.length;
    _publish(_current);
    await select(_searchMatches[_searchIndex], reveal: true);
  }

  void _clearSearch() {
    _searchQuery = null;
    _searchMatches = const [];
    _searchMatchSet = const {};
    _searchIndex = -1;
    _searchPending = false;
    _searchFailureCode = null;
  }

  Future<void> toggleCollapse(String objectId, {int offset = 0}) async {
    _ensureActive();
    if (_reloading) await _pendingLoad;
    final identity = _identity;
    final currentPage = _current.page;
    if (identity == null || currentPage == null) return;
    final operation = _operation;
    final queryOperation = ++_queryOperation;
    try {
      var page = await _repository.collapseHistory(
        identity,
        requestId: currentPage.requestId,
        objectId: objectId,
        offset: offset,
      );
      if (!_acceptsQuery(identity, operation, queryOperation)) return;
      _pages
        ..clear()
        ..[page.offset] = page;
      page = await _hydrate(identity, operation, page, const []);
      if (!_acceptsQuery(identity, operation, queryOperation)) return;
      _pages[page.offset] = page;
      _publish(
        HistoryState(
          phase: _current.phase,
          page: page,
          targetObjectId: _current.targetObjectId,
        ),
      );
    } on RepositorySessionException catch (error) {
      if (!_acceptsQuery(identity, operation, queryOperation)) return;
      _publish(
        HistoryState(
          phase: _current.phase,
          page: currentPage,
          targetObjectId: _current.targetObjectId,
          queryFailureCode: error.failure.code.name,
        ),
      );
    }
  }

  Future<ReflogPage> reflog({int offset = 0}) {
    _ensureActive();
    final identity = _identity;
    if (identity == null) throw StateError('history_not_loaded');
    return _repository.reflog(identity, offset: offset);
  }

  HistoryTopologyRow? _rowById(String objectId) {
    final index = _loadedRowIndex[objectId];
    if (index == null) return null;
    // Pages are not always aligned to the paging grid, so resolve by range.
    for (final page in _pages.values) {
      final local = index - page.offset;
      if (local >= 0 &&
          local < page.rows.length &&
          page.rows[local].objectId == objectId) {
        return page.rows[local];
      }
    }
    return null;
  }

  Future<HistoryPage> _hydrate(
    RepositorySessionIdentity identity,
    int operation,
    HistoryPage page,
    List<String> priorities,
  ) async {
    // Commit metadata never changes for an object ID, so rows that arrive
    // described need no second read.
    final missing = page.rows
        .where((row) => !row.isWorktree && !row.hasMetadata)
        .map((row) => row.objectId)
        .toList();
    if (missing.isEmpty) return page;
    final visible = missing.toSet();
    final ordered = <String>[...priorities.where(visible.contains), ...missing];
    final unique = <String>[];
    final seen = <String>{};
    for (final objectId in ordered) {
      if (seen.add(objectId)) unique.add(objectId);
    }
    final metadata = <String, HistoryMetadata>{};
    for (var offset = 0; offset < unique.length; offset += 256) {
      if (!_accepts(identity, operation)) return page;
      final end = (offset + 256).clamp(0, unique.length);
      final batch = await _repository.historyMetadata(
        identity,
        requestId: page.requestId,
        objectIds: unique.sublist(offset, end),
      );
      for (final value in batch) {
        metadata[value.objectId] = value;
      }
    }
    return HistoryPage(
      requestId: page.requestId,
      complete: page.complete,
      totalRows: page.totalRows,
      offset: page.offset,
      rows: [
        for (final row in page.rows)
          switch (metadata[row.objectId]) {
            final value? => row.withMetadata(value),
            null => row,
          },
      ],
      segments: page.segments,
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes,
      lightingActive: page.lightingActive,
      currentObjectId: page.currentObjectId,
      selectedObjectIds: page.selectedObjectIds,
      focusedObjectId: page.focusedObjectId,
      comparisonOldObjectId: page.comparisonOldObjectId,
      comparisonNewObjectId: page.comparisonNewObjectId,
      revealSequence: page.revealSequence,
      revealObjectId: page.revealObjectId,
      revealIndex: page.revealIndex,
      querySequence: page.querySequence,
      queryActive: page.queryActive,
      acceptedQuery: page.acceptedQuery,
      branchFilter: page.branchFilter,
      selectedFilteredOut: page.selectedFilteredOut,
      collapsedCommits: page.collapsedCommits,
      otherRefs: page.otherRefs,
    );
  }

  bool _accepts(RepositorySessionIdentity identity, int operation) =>
      !_disposed && _identity == identity && _operation == operation;

  bool _acceptsSelection(
    RepositorySessionIdentity identity,
    int operation,
    int selectionOperation,
  ) =>
      _accepts(identity, operation) &&
      _selectionOperation == selectionOperation;

  bool _acceptsQuery(
    RepositorySessionIdentity identity,
    int operation,
    int queryOperation,
  ) => _accepts(identity, operation) && _queryOperation == queryOperation;

  void _publish(HistoryState state) {
    _current = state;
    _states.add(state);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('history_service_disposed');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _operation += 1;
    _selectionOperation += 1;
    _queryOperation += 1;
    _finishCachePresentation();
    await _states.close();
    await _selections.close();
  }
}

final class HistoryDisplaySegment {
  const HistoryDisplaySegment({
    required this.fromLane,
    required this.toLane,
    required this.kind,
    this.startsAtTop = false,
    this.endsAtCenter = false,
    this.lit = false,
  });

  final int fromLane;
  final int toLane;
  final int kind;
  final bool startsAtTop;
  final bool endsAtCenter;
  final bool lit;
}

/// Loaded history pages with a change counter, so derived lookups know when
/// they are stale without fingerprinting every page.
final class _HistoryPages {
  final Map<int, HistoryPage> _byOffset = {};
  var generation = 0;

  /// Changes whenever the pages are replaced by another view.
  var view = 0;

  HistoryPage? operator [](int offset) => _byOffset[offset];

  void operator []=(int offset, HistoryPage page) {
    _byOffset[offset] = page;
    generation += 1;
  }

  void clear() {
    _byOffset.clear();
    generation += 1;
    view += 1;
  }

  bool containsKey(int offset) => _byOffset.containsKey(offset);
  Iterable<HistoryPage> get values => _byOffset.values;
  Iterable<MapEntry<int, HistoryPage>> get entries => _byOffset.entries;
}
