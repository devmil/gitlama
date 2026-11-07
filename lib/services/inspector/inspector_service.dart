import 'dart:async';
import 'dart:collection';

import '../../models/diff.dart';
import '../../models/diff_renderer.dart';
import '../../models/diff_syntax.dart';
import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../models/repository_state.dart';
import '../../repositories/inspection_repository.dart';
import '../diff_syntax_service.dart';
import 'inspector_navigation.dart';
import 'inspector_state.dart';
import 'lens_availability.dart';
import '../../models/git_names.dart';

export 'inspector_state.dart';

/// Owns one inspector: its location, Back/Forward stack and the reads behind
/// each lens. A native session keeps a single committed diff and a single
/// blame projection, so one session serves one inspector and every
/// navigation reloads them.
final class InspectorService {
  /// Without [syntax] diffs show plain text. Without [diffPreferences] a
  /// diff loads the way the previous one did.
  InspectorService(this._repository, {this._syntax, this._diffPreferences});

  final InspectionRepository _repository;
  final DiffSyntaxService? _syntax;

  /// How the stored preferences load diffs, read for every new diff.
  final DiffViewPreferences Function()? _diffPreferences;
  DiffSyntaxView? _syntaxView;
  final StreamController<InspectorState> _states =
      StreamController<InspectorState>.broadcast(sync: true);
  final StreamController<InspectorTarget> _targets =
      StreamController<InspectorTarget>.broadcast(sync: true);
  final InspectorNavigation _navigation = InspectorNavigation();
  InspectorState _current = const InspectorState();
  RepositorySessionIdentity? _identity;
  bool _disposed = false;

  /// Invalidates every read of a location that is no longer shown.
  int _token = 0;
  int _diffToken = 0;
  int _searchToken = 0;
  int _imageToken = 0;
  int _historyToken = 0;
  int _treeToken = 0;

  final Map<int, DiffPage> _diffPages = {};
  final Set<int> _loadingDiffPages = {};
  final Map<int, BlamePage> _blamePages = {};
  final Set<int> _loadingBlamePages = {};
  DiffLoadOptions _diffOptions = const DiffLoadOptions();

  /// The first parent the shown target's diff is computed against.
  String? _firstParent;

  /// The commit and base of the diff on screen.
  ({String commit, String? firstParent})? _diffSource;
  bool _allChangesTooLarge = false;
  final _LruCache<String, CommitInspection> _inspections = _LruCache(8);

  Stream<InspectorState> get states => _states.stream;
  InspectorState get current => _current;

  /// Targets reached by navigating inside the inspector (Back, Forward,
  /// Show Commit), so a graph can follow.
  Stream<InspectorTarget> get targetShown => _targets.stream;
  RepositorySessionIdentity? get identity => _identity;
  DiffLoadOptions get diffOptions => _diffOptions;

  /// The patch of every changed file of the shown target exceeds the read
  /// limit; its files open one at a time.
  bool get allChangesTooLarge => _allChangesTooLarge;

  /// The syntax colours of the shown diff, or null for plain text. A new
  /// diff gets a new view.
  DiffSyntaxView? get diffSyntax => _syntaxView;

  /// Gives the shown diff's accepted [page] to its syntax view, replacing
  /// the view when the page belongs to another diff.
  void _acceptSyntax(DiffPage page) {
    final syntax = _syntax;
    final identity = _identity;
    if (syntax == null || identity == null) return;
    var view = _syntaxView;
    if (view == null || view.diffRequestId != page.requestId) {
      view?.dispose();
      view = _syntaxView = syntax.view(
        identity: identity,
        origin: DiffSyntaxOrigin.committed,
        diffRequestId: page.requestId,
      );
    }
    view.accept(page);
  }

  void _retireSyntax() {
    _syntaxView?.dispose();
    _syntaxView = null;
  }

  Map<int, DiffDisplayRow> get loadedDiffRows => {
    for (final page in _diffPages.values)
      for (var index = 0; index < page.rows.length; index += 1)
        page.offset + index: page.rows[index],
  };

  /// Starts serving [identity]. A different session discards everything
  /// shown for the previous one.
  void attach(RepositorySessionIdentity identity) {
    _ensureActive();
    final previous = _identity;
    if (previous != null &&
        previous.nativeId == identity.nativeId &&
        previous.generation == identity.generation) {
      return;
    }
    _reset();
    _identity = identity;
  }

  /// Forgets the session, the stack and everything shown.
  void detach() {
    if (_disposed) return;
    _reset();
    _identity = null;
    _publish(const InspectorState());
  }

  void _reset() {
    _token += 1;
    _diffToken += 1;
    _searchToken += 1;
    _imageToken += 1;
    _historyToken += 1;
    _treeToken += 1;
    _navigation.clear();
    _diffPages.clear();
    _retireSyntax();
    _loadingDiffPages.clear();
    _blamePages.clear();
    _loadingBlamePages.clear();
    _inspections.clear();
    _firstParent = null;
    _diffSource = null;
    _allChangesTooLarge = false;
    if (_current.phase != InspectorPhase.empty) {
      _publish(const InspectorState());
    }
  }

  /// Shows [location]. A push adds it after the current entry; a replace
  /// overwrites the current entry. [fromHost] marks a navigation the host
  /// asked for (a graph selection), which [targetShown] does not echo.
  /// [parentHint] names the target's parents when the host already knows
  /// them, so the diff can start without an extra read.
  /// Lists every file of the shown commit when [canBrowseAllFiles] allows
  /// it; completes with whether it did.
  Future<bool> browseAllFiles() async {
    final location = current.location;
    if (location == null || !canBrowseAllFiles(location)) return false;
    await navigate(location.copyWith(scope: InspectorScope.all));
    return true;
  }

  Future<void> navigate(
    InspectorLocation location, {
    InspectorNavigationMode mode = InspectorNavigationMode.push,
    bool fromHost = false,
    List<String>? parentHint,
  }) async {
    if (_disposed || _identity == null) return;
    final next = location.normalized();
    final shown = _navigation.current;
    if (shown != null && shown.sameAs(next)) {
      if (_current.phase != InspectorPhase.failed &&
          _current.contentFailureCode == null) {
        if (mode == InspectorNavigationMode.replace) {
          _navigation.replace(next);
          _current = _current.copyWith(location: next);
        }
        return;
      }
      _navigation.replace(next);
    } else if (mode == InspectorNavigationMode.push) {
      _navigation.push(next);
    } else {
      _navigation.replace(next);
    }
    await _show(next, emitTarget: !fromHost, parentHint: parentHint);
  }

  /// Loads the current location again, after a failure.
  Future<void> retry() async {
    final location = _navigation.current;
    if (_disposed || _identity == null || location == null) return;
    await _show(location, emitTarget: false, force: true);
  }

  Future<void> back() => jump(-1);

  Future<void> forward() => jump(1);

  /// Moves [delta] entries along the stack: negative goes back.
  Future<void> jump(int delta) async {
    if (_disposed || _identity == null) return;
    final location = _navigation.jump(delta);
    if (location == null) return;
    await _show(location, emitTarget: true);
  }

  /// Moves one level up: from a line range to the whole history, from a
  /// lens to the diff, from a file to every change, and from all files to
  /// the changed ones. Returns false when there is no level above.
  Future<bool> up() async {
    final location = _navigation.current;
    if (_disposed || location == null) return false;
    final InspectorLocation next;
    if (location.path == null) {
      if (location.scope != InspectorScope.all) return false;
      next = location.copyWith(scope: InspectorScope.changed, anchor: 0);
    } else if (location.lens == InspectorLens.history &&
        location.lines != null) {
      next = location.copyWith(
        clearLines: true,
        clearHistoryCommit: true,
        anchor: 0,
      );
    } else if (location.lens != InspectorLens.diff &&
        _current.lensAvailability[InspectorLens.diff] == null &&
        _current.lensAvailability.isNotEmpty) {
      next = location.copyWith(lens: InspectorLens.diff, anchor: 0);
    } else {
      next = location.copyWith(clearPath: true, anchor: 0);
    }
    await navigate(next);
    return true;
  }

  /// Shows the blame of [row]'s file in the parent of the commit that last
  /// changed the line, at that line.
  Future<void> blameBefore(BlameRow row) async {
    final identity = _identity;
    final commit = row.commit;
    if (identity == null || commit == null || row.boundary) return;
    try {
      final inspection = await _inspect(identity, commit);
      final parent = inspection.detail.parents.firstOrNull;
      if (parent == null || _identity != identity) return;
      await navigate(
        InspectorLocation(
          target: CommitTarget(parent),
          path: row.originalPath,
          lens: InspectorLens.blame,
          anchor: row.originalLine > 0 ? row.originalLine - 1 : 0,
        ),
      );
    } on RepositorySessionException {
      return;
    }
  }

  /// Records the first visible row of the shown content, without
  /// publishing, so Back and Forward restore it.
  void reportAnchor(int anchor) {
    final location = _navigation.current;
    if (location == null || anchor < 0 || location.anchor == anchor) return;
    final updated = location.copyWith(anchor: anchor);
    _navigation.replace(updated);
    if (_current.location?.sameAs(updated) ?? false) {
      _current = _current.copyWith(location: updated);
    }
  }

  Future<void> _show(
    InspectorLocation location, {
    required bool emitTarget,
    List<String>? parentHint,
    bool force = false,
  }) async {
    final identity = _identity;
    if (identity == null) return;
    final token = ++_token;
    _diffToken += 1;
    _searchToken += 1;
    _imageToken += 1;
    _historyToken += 1;
    _diffPages.clear();
    _retireSyntax();
    _loadingDiffPages.clear();
    _blamePages.clear();
    _loadingBlamePages.clear();
    final previous = _current;
    final targetChanged =
        force ||
        previous.inspection == null ||
        previous.phase == InspectorPhase.failed ||
        previous.location?.target != location.target;
    if (targetChanged) {
      _treeToken += 1;
      _allChangesTooLarge = false;
      if (emitTarget && previous.location?.target != location.target) {
        _targets.add(location.target);
      }
    }
    _publish(
      InspectorState(
        location: location,
        phase: targetChanged ? InspectorPhase.loading : InspectorPhase.ready,
        inspection: targetChanged ? null : previous.inspection,
        contentLoading: true,
        tree: targetChanged ? const {} : previous.tree,
        expanded: targetChanged ? const {} : previous.expanded,
        canBack: _navigation.canBack,
        canForward: _navigation.canForward,
        backLocations: _navigation.backEntries(),
        forwardLocations: _navigation.forwardEntries(),
      ),
    );
    try {
      final CommitInspection inspection;
      if (targetChanged) {
        final loaded = await _loadTarget(identity, location.target, parentHint);
        if (!_accepts(identity, token)) return;
        inspection = loaded.inspection;
        _firstParent = loaded.firstParent;
        _publish(
          _current.copyWith(
            phase: InspectorPhase.ready,
            inspection: inspection,
          ),
        );
      } else {
        inspection = previous.inspection!;
      }
      var shown = location;
      final path = location.path;
      final change = path == null ? null : _changeFor(inspection, path);
      // A file the target did not change is only listed in All files.
      if (path != null &&
          change == null &&
          !location.directory &&
          location.scope == InspectorScope.changed &&
          location.target is CommitTarget) {
        shown = location.copyWith(scope: InspectorScope.all);
        _navigation.replace(shown);
        _publish(_current.copyWith(location: shown));
      }
      if (shown.scope == InspectorScope.all) {
        await _ensureTree(identity, token, shown);
        if (!_accepts(identity, token)) return;
      }
      var availability = const <InspectorLens, LensUnavailableReason?>{};
      if (path != null) {
        availability = lensAvailability(
          directory: location.directory,
          change: change,
          treeKind: _treeKindFor(path),
        );
        final lens = stickyLens(shown.lens, availability);
        if (lens != shown.lens) {
          shown = shown.copyWith(lens: lens).normalized();
          _navigation.replace(shown);
        }
      }
      _publish(
        _current.copyWith(location: shown, lensAvailability: availability),
      );
      await _loadContent(identity, token, shown, inspection, change);
    } on RepositorySessionException catch (error) {
      if (!_accepts(identity, token)) return;
      if (_current.inspection == null) {
        _publish(
          _current.copyWith(
            phase: InspectorPhase.failed,
            failureCode: error.failure.code,
            contentLoading: false,
          ),
        );
      } else {
        _publish(
          _current.copyWith(
            contentLoading: false,
            contentFailureCode: error.failure.code,
          ),
        );
      }
    }
  }

  Future<({CommitInspection inspection, String? firstParent})> _loadTarget(
    RepositorySessionIdentity identity,
    InspectorTarget target,
    List<String>? parentHint,
  ) async {
    final base = target.base;
    if (base != null) {
      final inspection = await _inspect(
        identity,
        target.commit,
        firstParent: base,
      );
      return (inspection: inspection, firstParent: base);
    }
    final inspection = await _inspect(
      identity,
      target.commit,
      parentHint: parentHint,
    );
    return (
      inspection: inspection,
      firstParent: inspection.detail.parents.firstOrNull,
    );
  }

  /// The detail and changed files of [commit] against [firstParent], or
  /// against its own first parent when none is given. Without a parent the
  /// native read compares with the empty tree, so an unknown parent costs
  /// one extra read.
  Future<CommitInspection> _inspect(
    RepositorySessionIdentity identity,
    String commit, {
    String? firstParent,
    List<String>? parentHint,
  }) async {
    final parent = firstParent ?? parentHint?.firstOrNull;
    final key = '${parent ?? ''}:$commit';
    if (_inspections[key] case final cached?) return cached;
    if (parent != null || parentHint != null) {
      final inspection = await _repository.inspectCommit(
        identity,
        commit: commit,
        firstParent: parent,
      );
      _inspections[key] = inspection;
      return inspection;
    }
    final first = await _repository.inspectCommit(identity, commit: commit);
    final discovered = first.detail.parents.firstOrNull;
    if (discovered == null) {
      _inspections[key] = first;
      return first;
    }
    final discoveredKey = '$discovered:$commit';
    if (_inspections[discoveredKey] case final cached?) return cached;
    final inspection = await _repository.inspectCommit(
      identity,
      commit: commit,
      firstParent: discovered,
    );
    _inspections[discoveredKey] = inspection;
    _inspections[key] = inspection;
    return inspection;
  }

  CommitFileChange? _changeFor(CommitInspection inspection, List<int> path) {
    for (final file in inspection.files) {
      if (sameBytes(changeDisplayPath(file), path)) return file;
    }
    return null;
  }

  CommitTreeEntryKind? _treeKindFor(List<int> path) {
    for (final directory in _current.tree.values) {
      for (final entry in directory.entries) {
        if (sameBytes(entry.path, path)) return entry.kind;
      }
    }
    return null;
  }

  Future<void> _loadContent(
    RepositorySessionIdentity identity,
    int token,
    InspectorLocation location,
    CommitInspection inspection,
    CommitFileChange? change,
  ) async {
    final path = location.path;
    if (path == null) {
      await _loadTargetDiff(identity, token, location, inspection, null);
      return;
    }
    switch (location.lens) {
      case InspectorLens.diff:
        await _loadTargetDiff(identity, token, location, inspection, change);
      case InspectorLens.contents:
        final bytes = await _repository.commitFileContent(
          identity,
          commit: location.target.commit,
          path: path,
        );
        if (!_accepts(identity, token)) return;
        _publish(_current.copyWith(fileBytes: bytes, contentLoading: false));
      case InspectorLens.blame:
        final blame = await _repository.blame(
          identity,
          revision: location.target.commit,
          path: path,
        );
        if (!_accepts(identity, token)) return;
        _blamePages
          ..clear()
          ..[blame.offset] = blame;
        _publish(_current.copyWith(blame: blame, contentLoading: false));
      case InspectorLens.history:
        await _loadHistory(identity, token, location);
    }
  }

  DiffLoadOptions _preferences() =>
      _diffPreferences?.call().applyTo(const DiffLoadOptions()) ??
      DiffLoadOptions(
        contextLines: _diffOptions.contextLines,
        whitespace: _diffOptions.whitespace,
        layout: _diffOptions.layout,
      );

  static DiffLoadOptions _fileOptions(
    CommitFileChange file,
    DiffLoadOptions options,
  ) => DiffLoadOptions(
    oldPath: file.oldPath.isEmpty ? file.newPath : file.oldPath,
    newPath: file.newPath.isEmpty ? file.oldPath : file.newPath,
    contextLines: options.contextLines,
    whitespace: options.whitespace,
    layout: options.layout,
  );

  Future<void> _loadTargetDiff(
    RepositorySessionIdentity identity,
    int token,
    InspectorLocation location,
    CommitInspection inspection,
    CommitFileChange? change,
  ) async {
    final commit = location.target.commit;
    final firstParent = _firstParent;
    var options = change == null
        ? _preferences()
        : _fileOptions(change, _preferences());
    DiffPage page;
    try {
      page = await _repository.commitDiff(
        identity,
        commit: commit,
        firstParent: firstParent,
        options: options,
      );
    } on RepositorySessionException catch (error) {
      if (change != null ||
          error.failure.code != RepositoryFailureCode.tooLarge) {
        rethrow;
      }
      // Two distant commits can differ by more than one patch may hold;
      // their file list still loads, and so does each file's diff.
      final file = inspection.files.firstOrNull;
      if (file == null || !_accepts(identity, token)) rethrow;
      _allChangesTooLarge = true;
      final focused = location
          .copyWith(path: changeDisplayPath(file), lens: InspectorLens.diff)
          .normalized();
      _navigation.replace(focused);
      final availability = lensAvailability(directory: false, change: file);
      _publish(
        _current.copyWith(location: focused, lensAvailability: availability),
      );
      options = _fileOptions(file, _preferences());
      page = await _repository.commitDiff(
        identity,
        commit: commit,
        firstParent: firstParent,
        options: options,
      );
    }
    if (!_accepts(identity, token)) return;
    _setDiff(page, options, commit: commit, firstParent: firstParent);
    _publish(
      _current.copyWith(
        diff: InspectorDiff(
          oldObjectId: location.target.base,
          newObjectId: commit,
          diff: page,
          allChangesTooLarge: _allChangesTooLarge,
        ),
        contentLoading: false,
      ),
    );
  }

  void _setDiff(
    DiffPage page,
    DiffLoadOptions options, {
    required String commit,
    required String? firstParent,
  }) {
    _diffOptions = options;
    _diffSource = (commit: commit, firstParent: firstParent);
    _diffPages
      ..clear()
      ..[page.offset] = page;
    _loadingDiffPages.clear();
    _acceptSyntax(page);
  }

  Future<void> _loadHistory(
    RepositorySessionIdentity identity,
    int token,
    InspectorLocation location,
  ) async {
    final path = location.path!;
    final commit = location.target.commit;
    final List<String> commits;
    if (location.lines case final lines?) {
      final range = await _repository.rangeHistory(
        identity,
        revision: commit,
        path: path,
        firstLine: lines.first,
        lastLine: lines.last,
      );
      if (!_accepts(identity, token)) return;
      commits = [for (final entry in range.entries) entry.commit];
      _publish(_current.copyWith(rangeHistory: range));
    } else {
      final page = await _repository.pathHistory(
        identity,
        revision: commit,
        path: path,
        directory: location.directory,
      );
      if (!_accepts(identity, token)) return;
      commits = [for (final entry in page.entries) entry.commit];
      _publish(_current.copyWith(history: page));
    }
    final selected = location.historyCommit ?? commits.firstOrNull;
    if (selected == null) {
      _publish(_current.copyWith(contentLoading: false));
      return;
    }
    var shown = location;
    if (location.historyCommit == null) {
      shown = location.copyWith(historyCommit: selected);
      _navigation.replace(shown);
      _publish(_current.copyWith(location: shown));
    }
    await _loadHistoryEntry(identity, token, shown, selected);
  }

  /// Selects the history entry of [commit] without adding a stack entry and
  /// shows that commit's change to the path.
  Future<void> selectHistoryEntry(String commit) async {
    final identity = _identity;
    final location = _navigation.current;
    if (identity == null ||
        location == null ||
        location.lens != InspectorLens.history ||
        location.historyCommit == commit) {
      return;
    }
    final shown = location.copyWith(historyCommit: commit, anchor: 0);
    _navigation.replace(shown);
    _diffToken += 1;
    _searchToken += 1;
    _imageToken += 1;
    _diffPages.clear();
    _retireSyntax();
    _loadingDiffPages.clear();
    _publish(
      _current.copyWith(
        location: shown,
        clearDiff: true,
        clearHistoryEntry: true,
        clearContentFailure: true,
        contentLoading: true,
      ),
    );
    try {
      await _loadHistoryEntry(identity, _token, shown, commit);
    } on RepositorySessionException catch (error) {
      if (!_accepts(identity, _token)) return;
      _publish(
        _current.copyWith(
          contentLoading: false,
          contentFailureCode: error.failure.code,
        ),
      );
    }
  }

  Future<void> _loadHistoryEntry(
    RepositorySessionIdentity identity,
    int token,
    InspectorLocation location,
    String commit,
  ) async {
    final historyToken = ++_historyToken;
    bool current() =>
        _accepts(identity, token) && historyToken == _historyToken;
    final inspection = await _inspect(identity, commit);
    if (!current()) return;
    if (location.directory) {
      _publish(
        _current.copyWith(historyEntry: inspection, contentLoading: false),
      );
      return;
    }
    final path = location.path!;
    final entry = _current.history?.entries
        .where((item) => item.commit == commit)
        .firstOrNull;
    final newPath = entry?.path ?? path;
    final oldPath = entry?.oldPath ?? newPath;
    final firstParent = inspection.detail.parents.firstOrNull;
    final options = _preferences().copyWith(oldPath: oldPath, newPath: newPath);
    final page = await _repository.commitDiff(
      identity,
      commit: commit,
      firstParent: firstParent,
      options: options,
    );
    if (!current()) return;
    _setDiff(page, options, commit: commit, firstParent: firstParent);
    _publish(
      _current.copyWith(
        historyEntry: inspection,
        diff: InspectorDiff(oldObjectId: null, newObjectId: commit, diff: page),
        contentLoading: false,
      ),
    );
  }

  Future<void> loadMoreHistory() async {
    final identity = _identity;
    final location = _navigation.current;
    final page = _current.history;
    if (identity == null ||
        location == null ||
        location.lens != InspectorLens.history ||
        location.lines != null ||
        page?.nextOffset == null ||
        _current.historyLoadingMore) {
      return;
    }
    final token = _token;
    _publish(
      _current.copyWith(historyLoadingMore: true, historyMoreFailed: false),
    );
    try {
      final next = await _repository.pathHistory(
        identity,
        revision: location.target.commit,
        path: location.path!,
        directory: location.directory,
        offset: page!.nextOffset!,
        renameHopsBefore: page.renameHops,
      );
      if (!_accepts(identity, token)) return;
      _publish(
        _current.copyWith(
          history: PathHistoryPage(
            entries: List.unmodifiable([...page.entries, ...next.entries]),
            nextOffset: next.nextOffset,
            renameHops: next.renameHops,
            incomplete: page.incomplete || next.incomplete,
          ),
          historyLoadingMore: false,
        ),
      );
    } on RepositorySessionException {
      if (!_accepts(identity, token)) return;
      _publish(
        _current.copyWith(historyLoadingMore: false, historyMoreFailed: true),
      );
    }
  }

  Future<void> _ensureTree(
    RepositorySessionIdentity identity,
    int token,
    InspectorLocation location,
  ) async {
    await _loadDirectory(identity, null);
    final path = location.path;
    if (path == null) return;
    final expanded = {..._current.expanded};
    for (var index = 0; index < path.length; index += 1) {
      if (path[index] != 0x2f) continue;
      final directory = path.sublist(0, index);
      if (directory.isEmpty) continue;
      expanded.add(inspectorTreeKey(directory));
      if (!_accepts(identity, token)) return;
      await _loadDirectory(identity, directory);
    }
    if (location.directory) {
      expanded.add(inspectorTreeKey(path));
      await _loadDirectory(identity, path);
    }
    if (!_accepts(identity, token)) return;
    _publish(_current.copyWith(expanded: expanded));
  }

  /// Shows [directory]'s entries in the All files tree, loading them once
  /// or again after a failure. Null is the root.
  Future<void> expandDirectory(List<int>? directory) async {
    final identity = _identity;
    if (identity == null || _current.inspection == null) return;
    _publish(
      _current.copyWith(
        expanded: {..._current.expanded, inspectorTreeKey(directory)},
      ),
    );
    await _loadDirectory(identity, directory);
  }

  void collapseDirectory(List<int> directory) {
    final key = inspectorTreeKey(directory);
    if (!_current.expanded.contains(key)) return;
    _publish(_current.copyWith(expanded: {..._current.expanded}..remove(key)));
  }

  Future<void> loadMoreDirectory(List<int>? directory) async {
    final identity = _identity;
    if (identity == null) return;
    await _loadDirectory(identity, directory, more: true);
  }

  Future<void> _loadDirectory(
    RepositorySessionIdentity identity,
    List<int>? directory, {
    bool more = false,
  }) async {
    final commit = _current.location?.target.commit;
    if (commit == null) return;
    final key = inspectorTreeKey(directory);
    final loaded = _current.tree[key];
    if (loaded != null &&
        (loaded.loading ||
            (!more && !loaded.failed) ||
            (more && loaded.nextOffset == null))) {
      return;
    }
    final token = _treeToken;
    final offset = more ? loaded!.nextOffset! : 0;
    _publish(
      _current.copyWith(
        tree: {
          ..._current.tree,
          key: InspectorTreeDirectory(
            entries: loaded?.entries ?? const [],
            nextOffset: loaded?.nextOffset,
            loading: true,
          ),
        },
      ),
    );
    try {
      final page = await _repository.commitTree(
        identity,
        commit: commit,
        directory: directory,
        offset: offset,
      );
      if (_identity != identity || token != _treeToken) return;
      _publish(
        _current.copyWith(
          tree: {
            ..._current.tree,
            key: InspectorTreeDirectory(
              entries: List.unmodifiable([
                if (more) ...?loaded?.entries,
                ...page.entries,
              ]),
              nextOffset: page.nextOffset,
            ),
          },
        ),
      );
    } on RepositorySessionException {
      if (_identity != identity || token != _treeToken) return;
      _publish(
        _current.copyWith(
          tree: {
            ..._current.tree,
            key: InspectorTreeDirectory(
              entries: loaded?.entries ?? const [],
              nextOffset: loaded?.nextOffset,
              failed: true,
            ),
          },
        ),
      );
    }
  }

  DiffDisplayRow? diffRowAt(int index) {
    final offset = (index ~/ 512) * 512;
    final page = _diffPages[offset];
    if (page == null) return null;
    final local = index - page.offset;
    return local >= 0 && local < page.rows.length ? page.rows[local] : null;
  }

  Future<void> ensureDiffIndex(int index) async {
    final identity = _identity;
    final diff = _current.diff;
    if (identity == null || diff == null || index >= diff.diff.totalRows) {
      return;
    }
    final offset = (index ~/ 512) * 512;
    if (_diffPages.containsKey(offset) || !_loadingDiffPages.add(offset)) {
      return;
    }
    final token = _diffToken;
    try {
      final page = await _repository.diffPage(
        identity,
        requestId: diff.diff.requestId,
        offset: offset,
      );
      if (_identity != identity || token != _diffToken) return;
      _diffPages[offset] = page;
      _publish(_current);
      _acceptSyntax(page);
    } on RepositorySessionException {
      return;
    } finally {
      _loadingDiffPages.remove(offset);
    }
  }

  /// Reloads the shown diff with other display options, keeping its file.
  Future<void> updateDiffOptions(DiffLoadOptions options) async {
    final identity = _identity;
    final diff = _current.diff;
    final source = _diffSource;
    if (identity == null || diff == null || source == null) return;
    final token = ++_diffToken;
    _searchToken += 1;
    _imageToken += 1;
    try {
      final page = await _repository.commitDiff(
        identity,
        commit: source.commit,
        firstParent: source.firstParent,
        options: options,
      );
      if (_identity != identity || token != _diffToken) return;
      _diffOptions = options;
      _diffPages
        ..clear()
        ..[page.offset] = page;
      _loadingDiffPages.clear();
      _acceptSyntax(page);
      _publish(
        _current.copyWith(
          diff: InspectorDiff(
            oldObjectId: diff.oldObjectId,
            newObjectId: diff.newObjectId,
            diff: page,
            allChangesTooLarge: diff.allChangesTooLarge,
          ),
        ),
      );
    } on RepositorySessionException {
      return;
    }
  }

  Future<DiffSearchResult?> searchDiff(
    String query, {
    bool caseSensitive = false,
  }) async {
    final identity = _identity;
    final diff = _current.diff;
    if (identity == null || diff == null || query.isEmpty) return null;
    final token = ++_searchToken;
    try {
      final result = await _repository.searchDiff(
        identity,
        requestId: diff.diff.requestId,
        query: query.codeUnits,
        caseSensitive: caseSensitive,
      );
      if (_identity != identity ||
          token != _searchToken ||
          result.requestId != _current.diff?.diff.requestId) {
        return null;
      }
      return result;
    } on RepositorySessionException {
      return null;
    }
  }

  /// A unified patch of the selected rows of the shown diff, or null when
  /// the selection holds no change line or the diff has moved on.
  Future<List<int>?> diffSelectionPatch(List<String> rowIds) async {
    final identity = _identity;
    final diff = _current.diff;
    if (identity == null || diff == null || rowIds.isEmpty) return null;
    try {
      return await _repository.diffSelectionPatch(
        identity,
        requestId: diff.diff.requestId,
        working: false,
        rowIds: rowIds,
      );
    } on RepositorySessionException {
      return null;
    }
  }

  Future<List<int>> diffHunks() async {
    final identity = _identity;
    final diff = _current.diff;
    if (identity == null || diff == null) return const [];
    try {
      return await _repository.diffHunks(
        identity,
        requestId: diff.diff.requestId,
      );
    } on RepositorySessionException {
      return const [];
    }
  }

  Future<ImageDiffContent?> imageDiff(DiffDisplayRow row) async {
    final identity = _identity;
    final diff = _current.diff;
    final oldPath = row.oldPath ?? row.newPath;
    final newPath = row.newPath ?? row.oldPath;
    if (identity == null ||
        diff == null ||
        oldPath == null ||
        newPath == null) {
      return null;
    }
    final requestId = diff.diff.requestId;
    final token = ++_imageToken;
    try {
      final content = await _repository.imageDiff(
        identity,
        oldRevision: diff.oldObjectId ?? _diffSource?.firstParent,
        newRevision: diff.newObjectId,
        oldPath: oldPath,
        newPath: newPath,
      );
      if (_identity != identity ||
          token != _imageToken ||
          _current.diff?.diff.requestId != requestId) {
        return null;
      }
      return content;
    } on RepositorySessionException {
      return null;
    }
  }

  Future<DiffRendererPreview> previewDiffRenderer(
    DiffRendererDefinition definition,
  ) async {
    final identity = _identity;
    final requestId = _current.diff?.diff.requestId;
    final repository = _repository;
    if (identity == null ||
        requestId == null ||
        repository is! DiffRendererRepositorySessionRepository) {
      throw const DiffRendererException(DiffRendererFailureCode.stale);
    }
    return (repository as DiffRendererRepositorySessionRepository)
        .previewDiffRenderer(
          identity,
          requestId: requestId,
          definition: definition,
        );
  }

  Future<DiffRendererResult> executeDiffRenderer(
    DiffRendererPreview preview,
  ) async {
    final repository = _repository;
    if (repository is! DiffRendererRepositorySessionRepository) {
      return const DiffRendererResult(
        state: DiffRendererState.fallback,
        failure: DiffRendererFailureCode.stale,
      );
    }
    return (repository as DiffRendererRepositorySessionRepository)
        .executeDiffRenderer(preview.source, preview.token);
  }

  Future<DiffRendererResult> pollDiffRenderer(
    DiffRendererPreview preview,
  ) async {
    final repository = _repository;
    if (repository is! DiffRendererRepositorySessionRepository) {
      return const DiffRendererResult(
        state: DiffRendererState.fallback,
        failure: DiffRendererFailureCode.stale,
      );
    }
    return (repository as DiffRendererRepositorySessionRepository)
        .pollDiffRenderer(preview.source, preview.token);
  }

  Future<void> cancelDiffRenderer(DiffRendererPreview preview) async {
    final repository = _repository;
    if (repository is DiffRendererRepositorySessionRepository) {
      await (repository as DiffRendererRepositorySessionRepository)
          .cancelDiffRenderer(preview.source, preview.token);
    }
  }

  BlameRow? blameRowAt(int index) {
    final offset = (index ~/ 512) * 512;
    final page = _blamePages[offset];
    if (page == null) return null;
    final local = index - page.offset;
    return local >= 0 && local < page.rows.length ? page.rows[local] : null;
  }

  Future<void> ensureBlameIndex(int index) async {
    final identity = _identity;
    final first = _current.blame;
    if (identity == null ||
        first == null ||
        index < 0 ||
        index >= first.totalRows) {
      return;
    }
    final offset = (index ~/ 512) * 512;
    if (_blamePages.containsKey(offset) || !_loadingBlamePages.add(offset)) {
      return;
    }
    final token = _token;
    try {
      final page = await _repository.blamePage(
        identity,
        requestId: first.requestId,
        offset: offset,
      );
      if (!_accepts(identity, token) ||
          _current.blame?.requestId != first.requestId) {
        return;
      }
      _blamePages[offset] = page;
      _publish(_current);
    } on RepositorySessionException {
      // Loaded rows stay; scrolling requests the page again.
    } finally {
      _loadingBlamePages.remove(offset);
    }
  }

  /// Previews restoring [path] to its content in [commit], or in the shown
  /// target.
  Future<RestorePreview> previewRestore(
    List<int> path, {
    String? commit,
  }) async {
    final identity = _identity;
    final source = commit ?? _current.location?.target.commit;
    if (identity == null || source == null) {
      throw StateError('inspector_not_loaded');
    }
    return _repository.previewRestore(identity, commit: source, path: path);
  }

  Future<RestoreResult> restoreFile(BigInt token) async {
    final identity = _identity;
    if (identity == null) throw StateError('inspector_not_loaded');
    return _repository.restoreFile(identity, token: token);
  }

  bool _accepts(RepositorySessionIdentity identity, int token) =>
      !_disposed && _identity == identity && token == _token;

  void _publish(InspectorState state) {
    if (_disposed) return;
    _current = state;
    _states.add(state);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('inspector_service_disposed');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _reset();
    _disposed = true;
    _identity = null;
    await _states.close();
    await _targets.close();
  }
}

final class _LruCache<K, V> {
  _LruCache(this.capacity);

  final int capacity;
  final LinkedHashMap<K, V> _values = LinkedHashMap();

  V? operator [](K key) {
    final value = _values.remove(key);
    if (value != null) _values[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > capacity) {
      _values.remove(_values.keys.first);
    }
  }

  void clear() => _values.clear();
}
