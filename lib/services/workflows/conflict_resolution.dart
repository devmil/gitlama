import 'dart:async';
import 'dart:convert';

import '../../models/conflict.dart';
import '../conflict/conflict_merge_draft.dart';
import '../../models/git_names.dart';
import '../../models/integrations.dart';
import '../../models/repository_state.dart';
import '../repository_session_service.dart';
import '../source_syntax_service.dart';
import 'workflow.dart';

/// What resolving conflicts asks of the window it runs in.
abstract interface class ConflictInteraction implements WorkflowInteraction {
  /// Asks to skip or abort the paused operation.
  Future<bool> confirmSequencer(ConflictSequencerAction action);

  /// Lets the user pick one of several merge tools; null cancels.
  Future<IntegrationDefinition?> chooseMergeTool(
    List<IntegrationDefinition> tools,
  );

  /// Asks to run the external merge [preview] describes.
  Future<bool> confirmExternalMerge(IntegrationPreview preview);

  void reportConflict(ConflictOutcome outcome);
}

/// How a conflict workflow ended, for the window to report.
sealed class ConflictOutcome {
  const ConflictOutcome();
}

/// Resolve was refused because [count] conflicts remain in the result.
final class ConflictRegionsRemaining extends ConflictOutcome {
  const ConflictRegionsRemaining(this.count);

  final int count;
}

/// Saving, choosing a side, undoing or an external merge failed.
final class ConflictSaveFailed extends ConflictOutcome {
  const ConflictSaveFailed();
}

/// Continue, Skip or Abort ran; [state] tells how.
final class ConflictContinued extends ConflictOutcome {
  const ConflictContinued(this.state);

  final ConflictContinuationState state;
}

final class ConflictContinueFailed extends ConflictOutcome {
  const ConflictContinueFailed();
}

final class ConflictWorkflowFailed extends ConflictOutcome {
  const ConflictWorkflowFailed(this.failure);

  final WorkflowFailure failure;
}

/// One file's unsaved resolution: its region choices, the edited text and a
/// whole side chosen but not yet saved. It belongs to the file version
/// [fingerprint] names.
final class ConflictFileDraft {
  const ConflictFileDraft({
    required this.fingerprint,
    required this.text,
    this.draft,
    this.side,
    this.focusedRegion = 0,
  });

  final BigInt fingerprint;
  final String text;
  final ConflictMergeDraft? draft;
  final ConflictSideChoice? side;
  final int focusedRegion;
}

/// What the resolver shows for one repository's paused operation.
final class ConflictResolutionState {
  const ConflictResolutionState({
    this.snapshot,
    this.selectedIndex = 0,
    this.loading = true,
    this.busy = false,
    this.loadFailed = false,
    this.finished = false,
  });

  final ConflictSnapshot? snapshot;
  final int selectedIndex;
  final bool loading;

  /// A mutation or sequencer step runs; actions wait for it.
  final bool busy;
  final bool loadFailed;

  /// The operation ended (or there is none); the resolver closes.
  final bool finished;

  ConflictFile? get selectedFile {
    final files = snapshot?.files ?? const <ConflictFile>[];
    if (files.isEmpty) return null;
    return files[selectedIndex.clamp(0, files.length - 1)];
  }

  ConflictResolutionState copyWith({
    ConflictSnapshot? snapshot,
    int? selectedIndex,
    bool? loading,
    bool? busy,
    bool? loadFailed,
    bool? finished,
  }) => ConflictResolutionState(
    snapshot: snapshot ?? this.snapshot,
    selectedIndex: selectedIndex ?? this.selectedIndex,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    loadFailed: loadFailed ?? this.loadFailed,
    finished: finished ?? this.finished,
  );
}

/// The conflict resolution of one repository session: its snapshot, the
/// unsaved drafts of every file, the merge message and the save, undo,
/// external-merge and Continue, Skip and Abort workflows. It outlives the
/// resolver widget, so switching tabs or files keeps unsaved choices.
final class ConflictSession {
  ConflictSession._(this._repositories, this.identity);

  final RepositorySessionService _repositories;
  final RepositorySessionIdentity identity;
  final Map<String, ConflictFileDraft> _drafts = {};

  /// How each file was resolved in this step of the operation, for the
  /// resolved files' summary. A resolution from before GitLama opened the
  /// operation is unknown.
  final Map<String, ConflictResolutionKind> _resolutions = {};
  final StreamController<ConflictResolutionState> _states =
      StreamController<ConflictResolutionState>.broadcast(sync: true);
  var _state = const ConflictResolutionState();
  var _disposed = false;
  bool _mergeMessageBound = false;

  /// The merge commit's subject and description while a merge is paused.
  String mergeSubject = '';
  String mergeDescription = '';

  ConflictResolutionState get current => _state;
  Stream<ConflictResolutionState> get states => _states.stream;

  /// Syntax colours for the files' sides and results; null shows plain text.
  SourceSyntaxService? get syntax => _repositories.sourceSyntax;

  void _emit(ConflictResolutionState state) {
    _state = state;
    if (!_disposed) _states.add(state);
  }

  /// Whether the repository still shows this session, so a result read for
  /// it may be applied.
  bool get _shown {
    final active = _repositories.activeTab?.session?.identity;
    return active?.nativeId == identity.nativeId &&
        active?.generation == identity.generation;
  }

  static String _key(List<int> path) => base64.encode(path);

  /// The unsaved draft of [file], if it was drafted at this version.
  ConflictFileDraft? draftOf(ConflictFile file) {
    final saved = _drafts[_key(file.path)];
    return saved?.fingerprint == file.fingerprint ? saved : null;
  }

  /// How the file at [path] was resolved, if this session resolved it.
  ConflictResolutionKind? resolutionOf(List<int> path) =>
      _resolutions[_key(path)];

  /// What choosing the whole [side] of [file] does to it.
  static ConflictResolutionKind sideResolution(
    ConflictFile file,
    ConflictSideChoice side,
  ) => switch (side) {
    ConflictSideChoice.current when !file.current.present =>
      ConflictResolutionKind.deleted,
    ConflictSideChoice.incoming when !file.incoming.present =>
      ConflictResolutionKind.deleted,
    ConflictSideChoice.current => ConflictResolutionKind.current,
    ConflictSideChoice.incoming => ConflictResolutionKind.incoming,
  };

  /// Records [kind] for [path] once [snapshot] no longer lists it as
  /// conflicted.
  void _recordResolution(
    ConflictSnapshot snapshot,
    List<int> path,
    ConflictResolutionKind kind,
  ) {
    if (snapshot.files.any((file) => sameBytes(file.path, path))) return;
    _resolutions[_key(path)] = kind;
  }

  /// Keeps [draft] for [file] until it is saved or the file changes.
  void remember(ConflictFile file, ConflictFileDraft draft) =>
      _drafts[_key(file.path)] = draft;

  /// Reads the paused operation again. Drafts of files that changed are
  /// dropped; the merge message is taken from Git once per operation.
  Future<void> load() async {
    _emit(_state.copyWith(loading: true));
    try {
      final snapshot = await _repositories.conflicts.load();
      if (!_shown) return;
      _drafts.removeWhere(
        (key, value) => !snapshot.files.any(
          (file) =>
              _key(file.path) == key && file.fingerprint == value.fingerprint,
        ),
      );
      if (snapshot.operation == ConflictOperationKind.merge &&
          !_mergeMessageBound) {
        final message = snapshot.suggestedMessage ?? '';
        final lineBreak = message.indexOf('\n');
        mergeSubject = lineBreak < 0
            ? message.trim()
            : message.substring(0, lineBreak).trim();
        mergeDescription = lineBreak < 0
            ? ''
            : message
                  .substring(lineBreak + 1)
                  .split('\n')
                  .where((line) => !line.trimLeft().startsWith('#'))
                  .join('\n')
                  .trim();
        _mergeMessageBound = true;
      }
      _emit(
        _state.copyWith(
          snapshot: snapshot,
          selectedIndex: _clamp(_state.selectedIndex, snapshot),
          loading: false,
          loadFailed: false,
          finished: _ended(snapshot),
        ),
      );
    } on ConflictException catch (error) {
      if (error.code == ConflictFailureCode.noActiveOperation) {
        _emit(_state.copyWith(loading: false, finished: true));
        return;
      }
      _emit(_state.copyWith(loading: false, loadFailed: true));
    } on Object {
      _emit(_state.copyWith(loading: false, loadFailed: true));
    }
  }

  static int _clamp(int index, ConflictSnapshot snapshot) =>
      index.clamp(0, snapshot.files.isEmpty ? 0 : snapshot.files.length - 1);

  static bool _ended(ConflictSnapshot snapshot) =>
      snapshot.operation == ConflictOperationKind.standalone &&
      snapshot.files.isEmpty;

  /// Shows the file at [index].
  void select(int index) {
    final files = _state.snapshot?.files ?? const <ConflictFile>[];
    if (index < 0 || index >= files.length || index == _state.selectedIndex) {
      return;
    }
    _emit(_state.copyWith(selectedIndex: index));
  }

  /// Saves [file]'s result: the whole [side] chosen for it, or [text], which
  /// must hold no conflict marker. [unresolved] counts the conflicts a
  /// refused result still holds. Completes with whether it was saved.
  Future<bool> save(
    ConflictInteraction interaction,
    ConflictFile file, {
    required String text,
    ConflictSideChoice? side,
    int? unresolved,
    bool reportFailure = true,
  }) async {
    if (side != null) {
      await _mutate(
        interaction,
        () => _repositories.conflicts.chooseSide(file, side),
        file.path,
        resolution: sideResolution(file, side),
      );
      return true;
    }
    if (file.kind != ConflictFileKind.text) return false;
    if (hasConflictMarkers(text)) {
      if (reportFailure && interaction.active) {
        interaction.reportConflict(
          ConflictRegionsRemaining(unresolved ?? file.regions.length),
        );
      }
      return false;
    }
    try {
      final snapshot = await _repositories.conflicts.saveResult(
        file,
        utf8.encode(text),
      );
      _drafts.remove(_key(file.path));
      _recordResolution(snapshot, file.path, ConflictResolutionKind.merged);
      _emit(
        _state.copyWith(
          snapshot: snapshot,
          selectedIndex: _clamp(_shownAfter(snapshot, file.path), snapshot),
          finished: _ended(snapshot),
        ),
      );
      return true;
    } on RemoteOutcomeUnknownException {
      if (interaction.active) {
        interaction.reportConflict(
          const ConflictWorkflowFailed(OutcomeUnknownFailure()),
        );
      }
      return false;
    } on Object {
      if (reportFailure && interaction.active) {
        interaction.reportConflict(const ConflictSaveFailed());
      }
      return false;
    }
  }

  int _indexOf(ConflictSnapshot snapshot, List<int> path) {
    final index = snapshot.files.indexWhere(
      (file) => sameBytes(file.path, path),
    );
    return index < 0 ? _state.selectedIndex : index;
  }

  /// The file to show once the file of [path] changed: itself while it is
  /// still conflicted, otherwise the next conflicted file in queue order,
  /// starting over at the first after the last.
  int _shownAfter(ConflictSnapshot snapshot, List<int> path) {
    final index = snapshot.files.indexWhere(
      (file) => sameBytes(file.path, path),
    );
    if (index >= 0) return index;
    return _state.selectedIndex < snapshot.files.length
        ? _state.selectedIndex
        : 0;
  }

  /// Puts the conflict of [path] back, undoing its resolution.
  Future<void> undo(ConflictInteraction interaction, List<int> path) async {
    if (_state.busy) return;
    await _mutate(
      interaction,
      () => _repositories.conflicts.undoResolution(path),
      path,
    );
    _resolutions.remove(_key(path));
  }

  /// Resolves every file of [paths] still conflicted with its whole [side],
  /// one after another, dropping their unsaved drafts. A failure stops the
  /// rest and reloads.
  Future<void> chooseSideForAll(
    ConflictInteraction interaction,
    List<List<int>> paths,
    ConflictSideChoice side,
  ) => _mutateEach(
    interaction,
    paths,
    (path) {
      final file = _state.snapshot?.files
          .where((file) => sameBytes(file.path, path))
          .firstOrNull;
      return file == null
          ? null
          : _repositories.conflicts.chooseSide(file, side);
    },
    resolution: (path) {
      final file = _state.snapshot?.files
          .where((file) => sameBytes(file.path, path))
          .firstOrNull;
      return file == null ? null : sideResolution(file, side);
    },
  );

  /// Puts the conflicts of every path of [paths] back.
  Future<void> undoAll(
    ConflictInteraction interaction,
    List<List<int>> paths,
  ) => _mutateEach(interaction, paths, (path) {
    _resolutions.remove(_key(path));
    return _repositories.conflicts.undoResolution(path);
  });

  /// Runs [operation] for each of [paths] under one busy state and shows
  /// each snapshot as it arrives; the shown file stays selected while it
  /// remains. [operation] returns null to pass over a path.
  Future<void> _mutateEach(
    ConflictInteraction interaction,
    List<List<int>> paths,
    Future<ConflictSnapshot>? Function(List<int> path) operation, {
    ConflictResolutionKind? Function(List<int> path)? resolution,
  }) async {
    if (_state.busy || paths.isEmpty) return;
    _emit(_state.copyWith(busy: true));
    try {
      for (final path in paths) {
        if (_state.finished || !_shown) break;
        final kind = resolution?.call(path);
        final pending = operation(path);
        if (pending == null) continue;
        final shown = _state.selectedFile?.path;
        final snapshot = await pending;
        _drafts.remove(_key(path));
        if (kind != null) _recordResolution(snapshot, path, kind);
        _emit(
          _state.copyWith(
            snapshot: snapshot,
            selectedIndex: _clamp(
              shown == null ? _state.selectedIndex : _indexOf(snapshot, shown),
              snapshot,
            ),
            loadFailed: false,
            finished: _ended(snapshot),
          ),
        );
      }
    } on Object {
      if (interaction.active) {
        interaction.reportConflict(const ConflictSaveFailed());
      }
      await load();
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }

  Future<void> _mutate(
    ConflictInteraction interaction,
    Future<ConflictSnapshot> Function() operation,
    List<int> path, {
    ConflictResolutionKind? resolution,
  }) async {
    _emit(_state.copyWith(busy: true));
    try {
      final snapshot = await operation();
      _drafts.remove(_key(path));
      if (resolution != null) _recordResolution(snapshot, path, resolution);
      _emit(
        _state.copyWith(
          snapshot: snapshot,
          selectedIndex: _clamp(_shownAfter(snapshot, path), snapshot),
          loadFailed: false,
          finished: _ended(snapshot),
        ),
      );
    } on Object {
      if (interaction.active) {
        interaction.reportConflict(const ConflictSaveFailed());
      }
      await load();
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }

  /// Continues, skips or aborts the paused operation. Skip and Abort ask
  /// first; Continue waits until no file is conflicted.
  Future<void> sequence(
    ConflictInteraction interaction,
    ConflictSequencerAction action,
  ) async {
    if (_state.busy) return;
    if (action == ConflictSequencerAction.continueOperation &&
        _state.snapshot?.files.isNotEmpty == true) {
      return;
    }
    if (action != ConflictSequencerAction.continueOperation &&
        (!await interaction.confirmSequencer(action) || !interaction.active)) {
      return;
    }
    _emit(_state.copyWith(busy: true));
    try {
      final result = await _repositories.conflicts.continueOperation(
        action,
        mergeMessage:
            action == ConflictSequencerAction.continueOperation &&
                _state.snapshot?.operation == ConflictOperationKind.merge
            ? '${mergeSubject.trim()}\n\n${mergeDescription.trim()}'.trim()
            : null,
      );
      if (interaction.active) {
        interaction.reportConflict(ConflictContinued(result.state));
      }
      // The next step of the operation resolves its own files.
      if (result.state != ConflictContinuationState.failed) {
        _resolutions.clear();
      }
      if (result.state == ConflictContinuationState.completed ||
          result.state == ConflictContinuationState.aborted) {
        _emit(_state.copyWith(finished: true));
      }
      if (result.state == ConflictContinuationState.conflict ||
          result.state == ConflictContinuationState.interrupted ||
          result.state == ConflictContinuationState.outcomeUncertain) {
        await load();
      }
    } on RemoteOutcomeUnknownException {
      if (interaction.active) {
        interaction.reportConflict(
          const ConflictWorkflowFailed(OutcomeUnknownFailure()),
        );
      }
    } on Object {
      if (interaction.active) {
        interaction.reportConflict(const ConflictContinueFailed());
      }
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }

  /// The configured merge tools.
  List<IntegrationDefinition> get mergeTools =>
      _repositories.configuredIntegrations(IntegrationKind.mergeTool);

  /// Merges [file] in an external tool: [definition], the only configured
  /// tool, or the one the user picks among several.
  Future<void> mergeExternally(
    ConflictInteraction interaction,
    ConflictFile file, {
    IntegrationDefinition? definition,
  }) async {
    final tools = mergeTools;
    if (_state.busy || tools.isEmpty) return;
    final tool =
        definition ??
        tools.singleOrNull ??
        await interaction.chooseMergeTool(tools);
    if (tool == null || !interaction.active) return;
    _emit(_state.copyWith(busy: true));
    IntegrationPreview? preview;
    try {
      preview = await _repositories.integrations.previewExternalConflictMerge(
        file,
        tool,
      );
      if (!interaction.active) return;
      if (!await interaction.confirmExternalMerge(preview)) {
        await _repositories.integrations.cancel(preview);
        return;
      }
      final result = await _repositories.integrations.execute(
        preview,
        confirmed: true,
      );
      if (result.state != IntegrationExecutionState.completed) {
        throw IntegrationException(
          result.failure ?? IntegrationFailureCode.launch,
        );
      }
      if (!interaction.active) return;
      await load();
      if (_state.snapshot case final snapshot?) {
        _recordResolution(snapshot, file.path, ConflictResolutionKind.external);
      }
    } on Object {
      if (preview != null) await _repositories.integrations.cancel(preview);
      if (interaction.active) {
        interaction.reportConflict(const ConflictSaveFailed());
      }
    } finally {
      _emit(_state.copyWith(busy: false));
    }
  }

  /// Stops publishing. The stream closes after the event being delivered,
  /// since a listener may end the session from inside it.
  Future<void> _dispose() async {
    _disposed = true;
    await Future<void>.delayed(Duration.zero);
    await _states.close();
  }
}

/// The conflict sessions of a window, one per repository session, so the
/// drafts of each repository survive switching tabs.
final class ConflictResolutionService {
  ConflictResolutionService(this._repositories);

  final RepositorySessionService _repositories;
  final Map<String, ConflictSession> _sessions = {};

  /// The conflict session of the active repository, or null without one.
  ConflictSession? get active {
    final identity = _repositories.activeTab?.session?.identity;
    if (identity == null) return null;
    _forgetClosed();
    return _sessions['${identity.nativeId}:${identity.generation}'] ??=
        ConflictSession._(_repositories, identity);
  }

  /// Drops the sessions of repositories no longer open.
  void _forgetClosed() {
    final open = {
      for (final tab in _repositories.workspace.tabs)
        if (tab.session?.identity case final identity?)
          '${identity.nativeId}:${identity.generation}',
    };
    final closed = _sessions.keys.where((key) => !open.contains(key)).toList();
    for (final key in closed) {
      unawaited(_sessions.remove(key)!._dispose());
    }
  }

  /// Forgets the session of the active repository once its operation
  /// ended, so the next conflict starts afresh.
  void finish(ConflictSession session) {
    final key = '${session.identity.nativeId}:${session.identity.generation}';
    if (identical(_sessions[key], session)) {
      unawaited(_sessions.remove(key)!._dispose());
    }
  }

  Future<void> dispose() async {
    for (final session in _sessions.values) {
      await session._dispose();
    }
    _sessions.clear();
  }
}
