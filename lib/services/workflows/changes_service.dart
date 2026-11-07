import '../../models/native_paths.dart';
import 'dart:async';

import '../../models/app_command.dart';
import '../../models/conflict.dart';
import '../../models/diff.dart';
import '../../models/discard.dart';
import '../../models/remote_command_policy.dart';
import '../../models/remote_contract.g.dart';
import '../../models/repository_state.dart';
import '../../models/working_tree.dart';
import '../../models/workspace.dart';
import '../remote_workspace_workflows.dart';
import '../repository_session_service.dart';
import 'repository_busy.dart';
import 'workflow.dart';
import 'workspace_navigator.dart';

/// What the Changes workflows ask of the window they run in.
abstract interface class ChangesInteraction implements WorkflowInteraction {
  /// Asks to discard or clean what [preview] lists.
  Future<bool> confirmDiscard(DiscardReview preview);

  void reportChanges(ChangesOutcome outcome);
}

/// How a Changes workflow ended, for the window to report.
sealed class ChangesOutcome {
  const ChangesOutcome();
}

final class StagingFinished extends ChangesOutcome {
  const StagingFinished(
    this.state, {
    this.diagnostic,
    this.side = StagingSide.unstaged,
  });

  final StagingExecutionState state;
  final StagingDiagnostic? diagnostic;
  final StagingSide side;
}

final class StagingFailed extends ChangesOutcome {
  final StagingSide side;
  const StagingFailed(this.failure, {this.side = StagingSide.unstaged});

  final WorkflowFailure failure;
}

final class DiscardFinished extends ChangesOutcome {
  const DiscardFinished(this.state);

  final DiscardExecutionState state;
}

/// Some previews completed before a later step stopped or became uncertain.
final class DiscardPartiallyFinished extends ChangesOutcome {
  const DiscardPartiallyFinished(this.completedFiles, this.totalFiles);

  final int completedFiles;
  final int totalFiles;
}

final class DiscardFailed extends ChangesOutcome {
  const DiscardFailed(this.failure);

  final WorkflowFailure failure;
}

/// The command is not offered for the repository, for [reason].
final class ChangesRefused extends ChangesOutcome {
  const ChangesRefused(this.reason);

  final AppCommandDisabledReason reason;
}

/// What the Changes pane of one tab has selected.
final class ChangesSelection {
  const ChangesSelection({
    this.staged = const {},
    this.unstaged = const {},
    this.focusedSide = StagingSide.unstaged,
  });

  /// [changeKey]s of the selected staged and unstaged files.
  final Set<String> staged;
  final Set<String> unstaged;

  /// The list the user worked in last; the diff and Space follow it.
  final StagingSide focusedSide;

  Set<String> of(StagingSide side) =>
      side == StagingSide.staged ? staged : unstaged;

  ChangesSelection copyWith({
    Set<String>? staged,
    Set<String>? unstaged,
    StagingSide? focusedSide,
  }) => ChangesSelection(
    staged: staged ?? this.staged,
    unstaged: unstaged ?? this.unstaged,
    focusedSide: focusedSide ?? this.focusedSide,
  );
}

/// One-shot requests the Changes pane carries out on screen.
sealed class ChangesEffect {
  const ChangesEffect(this.tabId);

  final int tabId;
}

/// Files start moving from [side] to the other list.
final class ChangesMoveStarted extends ChangesEffect {
  const ChangesMoveStarted(super.tabId, this.side, this.keys, {this.single});

  final StagingSide side;
  final Set<String> keys;

  /// The one file a file action moves to the other list, which the pane
  /// flies there; null for lines, several files or a discard.
  final RepositoryStatusEntry? single;
}

/// The move ended; files that did not move return to their list.
final class ChangesMoveEnded extends ChangesEffect {
  const ChangesMoveEnded(super.tabId, {required this.moved});

  final bool moved;
}

/// An action on [side]'s files failed; the list shows it.
final class ChangesActionFailed extends ChangesEffect {
  const ChangesActionFailed(super.tabId, this.side, this.scope);

  final StagingSide side;
  final StagingScope scope;
}

/// The window asks the working-tree diff to act on its selected lines.
final class DiffSelectionRequested extends ChangesEffect {
  const DiffSelectionRequested(super.tabId, {required this.discard});

  final bool discard;
}

final class _StageIntent {
  _StageIntent(
    this.identity,
    this.interaction,
    this.side,
    this.scope,
    this.entries,
    this.accepted,
    this.rowIds,
    this.shownDetail,
    this.selectionRevision,
  ) : paths = List.unmodifiable(
        entries.map(
          (entry) => List<int>.unmodifiable(repositoryPathBytes(entry.path)),
        ),
      );

  final RepositorySessionIdentity identity;
  final ChangesInteraction interaction;
  final StagingSide side;
  final StagingScope scope;
  final List<RepositoryStatusEntry> entries;
  final List<List<int>> paths;
  final DiffPage? accepted;
  final List<String> rowIds;
  final String? shownDetail;
  final int selectionRevision;
  final done = Completer<void>();
}

final class _TabChanges {
  var selection = const ChangesSelection();
  var conflictFlowActive = false;
  var conflictFlowDismissed = false;
  var diffRowsSelected = false;
  var probe = 0;
  var selectionRevision = 0;
  final pending = <_StageIntent>[];
  _StageIntent? running;
  StagingPhase? phase;
  var stoppedPending = 0;
}

/// The Changes pane's workflows and state for every tab: the selection and
/// focused list, staging of files or lines, Discard or Clean, the conflict
/// flow and which selection follows a move. The pane renders it and keeps
/// only layout and animation of its own.
final class ChangesService {
  ChangesService(
    this._repositories,
    this._busy,
    this._navigator, [
    this._remote,
  ]) {
    _workspace = _repositories.workspaceStates.listen((_) => _sync());
  }

  final RepositorySessionService _repositories;
  final RepositoryBusyService _busy;
  final WorkspaceNavigator _navigator;
  final RemoteWorkspaceWorkflows? _remote;
  late final StreamSubscription<WorkspaceState> _workspace;
  final Map<int, _TabChanges> _tabs = {};
  final StreamController<int> _changes = StreamController<int>.broadcast(
    sync: true,
  );
  final StreamController<ChangesEffect> _effects =
      StreamController<ChangesEffect>.broadcast(sync: true);
  var _disposed = false;

  /// Fires with a tab's ID whenever its Changes state changes.
  Stream<int> get changes => _changes.stream;

  Stream<ChangesEffect> get effects => _effects.stream;

  _TabChanges _tab(int tabId) => _tabs[tabId] ??= _TabChanges();

  void _notify(int tabId) {
    if (!_disposed) _changes.add(tabId);
  }

  void _effect(ChangesEffect effect) {
    if (!_disposed) _effects.add(effect);
  }

  ChangesSelection selectionOf(int tabId) => _tab(tabId).selection;

  /// Whether the pane of [tabId] runs a file action.
  bool busy(int tabId) => _busy.isBusy(tabId);

  static const maximumPendingStages = 32;

  /// Only whole-file actions may join an existing staging operation.
  bool canStageFiles(int tabId) =>
      !busy(tabId) ||
      (_tabs[tabId]?.running != null &&
          _tabs[tabId]!.running!.scope != StagingScope.rows &&
          !_busy.isBlocked(tabId) &&
          _tabs[tabId]!.pending.length < maximumPendingStages);

  StagingPhase? stagingPhase(int tabId) => _tabs[tabId]?.phase;
  int stoppedStages(int tabId) => _tabs[tabId]?.stoppedPending ?? 0;

  void dismissStoppedStages(int tabId) {
    _tabs[tabId]?.stoppedPending = 0;
    _notify(tabId);
  }

  int pendingStages(int tabId) => _tabs[tabId]?.pending.length ?? 0;

  Set<String> pendingKeys(int tabId, StagingSide side) => {
    for (final intent in _tabs[tabId]?.pending ?? <_StageIntent>[])
      if (intent.side == side) ...intent.entries.map(changeKey),
    if (_tabs[tabId]?.running case final intent?)
      if (intent.side == side) ...intent.entries.map(changeKey),
  };

  /// Cancel only requests which have not started; a running write keeps its outcome.
  void clearPendingStages(int tabId) {
    final state = _tabs[tabId];
    if (state == null) return;
    for (final intent in state.pending) {
      if (!intent.done.isCompleted) intent.done.complete();
    }
    state.pending.clear();
    _notify(tabId);
  }

  bool _sessionOpen(int tabId, RepositorySessionIdentity identity) {
    final current = _tabState(tabId)?.session?.identity;
    return !_disposed &&
        current != null &&
        current.nativeId == identity.nativeId &&
        current.generation == identity.generation &&
        current.backend == identity.backend;
  }

  /// Whether the conflict resolver replaces the lists of [tabId].
  bool conflictFlow(int tabId) {
    final tab = _tab(tabId);
    _applyStatus(tab, _status(tabId));
    return tab.conflictFlowActive;
  }

  /// A conflict opens the resolver unless the user left it; once the
  /// conflict is gone a new one opens it again. Reports a change.
  bool _applyStatus(_TabChanges state, RepositoryStatus? status) {
    if (status == null) return false;
    final conflicts = hasActiveConflicts(status);
    var changed = false;
    if (!conflicts && state.conflictFlowDismissed) {
      state.conflictFlowDismissed = false;
      changed = true;
    }
    if (conflicts &&
        !state.conflictFlowDismissed &&
        !state.conflictFlowActive) {
      state.conflictFlowActive = true;
      changed = true;
    }
    return changed;
  }

  RepositoryTabState? _tabState(int tabId) =>
      _repositories.activeTab?.id == tabId
      ? _repositories.activeTab
      : _repositories.workspace.tabs
            .where((tab) => tab.id == tabId)
            .firstOrNull;

  RepositoryStatus? _status(int tabId) =>
      _tabState(tabId)?.session?.snapshot.status;

  /// Follows each tab's status: selections keep only files still changed,
  /// and a new conflict opens the resolver unless the user left it.
  void _sync() {
    final open = <int>{};
    for (final tab in _repositories.workspace.tabs) {
      open.add(tab.id);
      final status = tab.session?.snapshot.status;
      if (status == null) continue;
      final state = _tab(tab.id);
      var changed = false;
      final current = status.entries.map(changeKey).toSet();
      final selection = state.selection;
      if (!current.containsAll(selection.staged) ||
          !current.containsAll(selection.unstaged)) {
        state.selection = selection.copyWith(
          staged: selection.staged.intersection(current),
          unstaged: selection.unstaged.intersection(current),
        );
        changed = true;
      }
      if (_applyStatus(state, status)) changed = true;
      if (changed) _notify(tab.id);
    }
    for (final id in _tabs.keys.toList()) {
      final state = _tabs[id]!;
      if (!open.contains(id) ||
          (state.running != null &&
              !_sessionOpen(id, state.running!.identity))) {
        clearPendingStages(id);
        _tabs.remove(id);
      }
    }
  }

  /// Selects [keys] in [side]'s list and clears the other list.
  void select(int tabId, StagingSide side, Set<String> keys) {
    final tab = _tab(tabId);
    tab.selectionRevision++;
    tab.selection = ChangesSelection(
      staged: side == StagingSide.staged ? Set.unmodifiable(keys) : const {},
      unstaged: side == StagingSide.unstaged
          ? Set.unmodifiable(keys)
          : const {},
      focusedSide: side,
    );
    _notify(tabId);
  }

  /// Makes [side] the list Space and the diff follow.
  void focus(int tabId, StagingSide side) {
    final tab = _tab(tabId);
    if (tab.selection.focusedSide == side) return;
    tab.selectionRevision++;
    tab.selection = tab.selection.copyWith(focusedSide: side);
    _notify(tabId);
  }

  /// Keeps only the selected files a filter still shows, so actions on the
  /// selection never reach hidden files.
  void retain(int tabId, Set<String> shown) {
    final tab = _tab(tabId);
    final selection = tab.selection;
    tab.selectionRevision++;
    tab.selection = selection.copyWith(
      staged: selection.staged.intersection(shown),
      unstaged: selection.unstaged.intersection(shown),
    );
    _notify(tabId);
  }

  /// Whether the working-tree diff of [tabId] has lines selected.
  void setDiffRowsSelected(int tabId, bool selected) =>
      _tab(tabId).diffRowsSelected = selected;

  /// The selected entries of [side], in status order.
  List<RepositoryStatusEntry> selectedEntries(int tabId, StagingSide side) {
    final status = _status(tabId);
    if (status == null) return const [];
    final keys = _tab(tabId).selection.of(side);
    return entriesOn(
      status,
      side,
    ).where((entry) => keys.contains(changeKey(entry))).toList(growable: false);
  }

  /// The commands the selection of [tabId] gives nothing to act on.
  Set<AppCommandId> disabledSelectionCommands(int tabId) {
    final tab = _tab(tabId);
    final selection = tab.selection;
    final diffSelected = tab.diffRowsSelected;
    final unstaged =
        selection.unstaged.isNotEmpty ||
        (selection.focusedSide == StagingSide.unstaged && diffSelected);
    final staged =
        selection.staged.isNotEmpty ||
        (selection.focusedSide == StagingSide.staged && diffSelected);
    // Discard supports any selection of eligible unstaged entries.
    final discard =
        (selection.focusedSide == StagingSide.unstaged && diffSelected) ||
        discardKindOf(selectedEntries(tabId, StagingSide.unstaged)) != null;
    return {
      if (!unstaged) AppCommandId.stageSelection,
      if (!staged) AppCommandId.unstageSelection,
      if (!discard) AppCommandId.discardChanges,
      if (!unstaged && !staged) AppCommandId.stageToggle,
    };
  }

  /// The file the diff shows: [selected] when it names a changed file,
  /// otherwise the first highlighted row of the focused list.
  String? detailIdentity(int tabId, String? selected) {
    final status = _status(tabId);
    if (status == null) return selected;
    if (selected != null &&
        status.entries.any(
          (entry) => changeDisplayIdentity(entry.path) == selected,
        )) {
      return selected;
    }
    final focused = _tab(tabId).selection.focusedSide;
    final highlighted = selectedEntries(tabId, focused).firstOrNull;
    return highlighted == null
        ? selected
        : changeDisplayIdentity(highlighted.path);
  }

  bool _refused(ChangesInteraction interaction, int tabId, AppCommandId id) {
    final reason = remoteCommandReason(
      id,
      _remote?.accessFor(_tabState(tabId)),
    );
    if (reason == null) return false;
    if (interaction.active) interaction.reportChanges(ChangesRefused(reason));
    return true;
  }

  /// Stages or unstages the selection of [side]: its chosen diff lines
  /// when the diff of that list has some, otherwise its selected files.
  void stageSelection(
    ChangesInteraction interaction,
    int tabId,
    StagingSide side,
  ) {
    final tab = _tab(tabId);
    if (tab.diffRowsSelected && tab.selection.focusedSide == side) {
      _effect(DiffSelectionRequested(tabId, discard: false));
      return;
    }
    final entries = selectedEntries(tabId, side);
    if (entries.isNotEmpty) {
      unawaited(stage(interaction, tabId, side, StagingScope.files, entries));
    }
  }

  /// Space: stages or unstages what the focused list selects.
  void toggleFocused(ChangesInteraction interaction, int tabId) {
    final tab = _tab(tabId);
    if (tab.diffRowsSelected) {
      _effect(DiffSelectionRequested(tabId, discard: false));
      return;
    }
    final side = tab.selection.focusedSide;
    final entries = selectedEntries(tabId, side);
    if (entries.isNotEmpty) {
      unawaited(stage(interaction, tabId, side, StagingScope.files, entries));
    }
  }

  /// Discards the selected diff lines, or the selected unstaged files.
  void discardSelection(ChangesInteraction interaction, int tabId) {
    if (_tab(tabId).diffRowsSelected) {
      _effect(DiffSelectionRequested(tabId, discard: true));
      return;
    }
    unawaited(
      discard(interaction, tabId, selectedEntries(tabId, StagingSide.unstaged)),
    );
  }

  /// The file to select after [moving] leave [side]: the next one in the
  /// list, or the one before when they were last.
  String? nextSelection(
    RepositoryStatus status,
    StagingSide side,
    List<RepositoryStatusEntry> moving,
  ) {
    final source = entriesOn(status, side);
    final movingKeys = moving.map(changeKey).toSet();
    final anchor = source.indexWhere(
      (entry) => movingKeys.contains(changeKey(entry)),
    );
    if (anchor < 0) return null;
    for (var index = anchor; index < source.length; index += 1) {
      final entry = source[index];
      if (!movingKeys.contains(changeKey(entry))) {
        return changeDisplayIdentity(entry.path);
      }
    }
    for (var index = anchor - 1; index >= 0; index -= 1) {
      final entry = source[index];
      if (!movingKeys.contains(changeKey(entry))) {
        return changeDisplayIdentity(entry.path);
      }
    }
    return null;
  }

  /// Stages (or, from the staged list, unstages) [entries] or the lines
  /// [rowIds] of the diff [accepted]. The selection moves to the next file
  /// of the list, or follows a single file to the other list. [shownDetail]
  /// is the file the diff shows, kept by a line action. Whole-file requests
  /// may queue; other scopes only start when no file action is running.
  Future<void> stage(
    ChangesInteraction interaction,
    int tabId,
    StagingSide side,
    StagingScope scope,
    List<RepositoryStatusEntry> entries, {
    DiffPage? accepted,
    List<String> rowIds = const [],
    String? shownDetail,
  }) async {
    final state = _tab(tabId);
    final identity = _tabState(tabId)?.session?.identity;
    if (_disposed ||
        identity == null ||
        _status(tabId) == null ||
        _refused(interaction, tabId, AppCommandId.stageSelection)) {
      return;
    }
    if (busy(tabId) && (scope != StagingScope.files || !canStageFiles(tabId))) {
      return;
    }
    // An All request starts immediately, never expands later from a queued snapshot.
    final reserved = pendingKeys(tabId, side);
    final selected = scope == StagingScope.files
        ? entries
              .where((entry) => !reserved.contains(changeKey(entry)))
              .toList()
        : entries;
    if (scope == StagingScope.files && selected.isEmpty) return;
    final intent = _StageIntent(
      identity,
      interaction,
      side,
      scope,
      List.unmodifiable(selected),
      accepted,
      List.unmodifiable(rowIds),
      shownDetail,
      state.selectionRevision,
    );
    state.stoppedPending = 0;
    state.pending.add(intent);
    if (state.running == null) {
      // run() enters its busy scope synchronously, before another intent is admitted.
      unawaited(_drainStages(tabId, state));
    } else {
      _notify(tabId);
    }
    await intent.done.future;
  }

  Future<void> _drainStages(int tabId, _TabChanges state) async {
    await _busy.run(tabId, const ChangesBusy(), blocking: false, () async {
      try {
        while (state.pending.isNotEmpty) {
          final intent = state.pending.removeAt(0);
          state.running = intent;
          state.phase = StagingPhase.waiting;
          _notify(tabId);
          var proceed = false;
          try {
            if (!_sessionOpen(tabId, intent.identity)) break;
            proceed = await _executeStage(tabId, state, intent);
          } finally {
            if (!intent.done.isCompleted) intent.done.complete();
          }
          if (!proceed) break;
        }
      } finally {
        if (state.pending.isNotEmpty &&
            _sessionOpen(tabId, state.pending.first.identity)) {
          state.stoppedPending = state.pending.length;
        }
        for (final intent in state.pending) {
          if (!intent.done.isCompleted) intent.done.complete();
        }
        state.pending.clear();
        state.running = null;
        state.phase = null;
        _notify(tabId);
      }
    });
  }

  Future<bool> _executeStage(
    int tabId,
    _TabChanges state,
    _StageIntent intent,
  ) async {
    final status = _status(tabId);
    if (status == null) return false;
    final side = intent.side;
    final scope = intent.scope;
    final entries = intent.entries;
    final interaction = intent.interaction;
    var moved = false;
    var started = false;
    try {
      final page = scope == StagingScope.rows
          ? intent.accepted ??
                await _repositories.workingCopy.diffFor(
                  intent.identity,
                  side: side,
                  maximumRows: ContractLimits.pageRows,
                )
          : null;
      if (!_sessionOpen(tabId, intent.identity)) return false;
      final paths = scope == StagingScope.files
          ? intent.paths
          : const <List<int>>[];
      final next = scope == StagingScope.rows
          ? intent.shownDetail
          : nextSelection(status, side, entries);
      _effect(
        ChangesMoveStarted(
          tabId,
          side,
          entries.map(changeKey).toSet(),
          single: scope == StagingScope.files && entries.length == 1
              ? entries.single
              : null,
        ),
      );
      started = true;
      final result = await _repositories.workingCopy.stageFor(
        intent.identity,
        StagingRequest(
          requestId: page?.requestId ?? BigInt.zero,
          side: side,
          scope: scope,
          paths: paths,
          rowIds: intent.rowIds,
        ),
        onPhase: (phase) {
          if (_sessionOpen(tabId, intent.identity) && state.phase != phase) {
            state.phase = phase;
            _notify(tabId);
          }
        },
      );
      moved =
          result.state == StagingExecutionState.completed ||
          result.state == StagingExecutionState.reconciledWithWarning;
      if (!_sessionOpen(tabId, intent.identity)) return false;
      if (moved) {
        // Completion must never replace a selection made after admission.
        if (state.selectionRevision == intent.selectionRevision) {
          _followMove(tabId, status, side, entries, next);
        }
      } else {
        _effect(ChangesActionFailed(tabId, side, scope));
      }
      if (interaction.active) {
        interaction.reportChanges(
          StagingFinished(
            result.state,
            diagnostic: result.diagnostic,
            side: side,
          ),
        );
      }
      // A degraded refresh cannot supply the coherent state needed by the next write.
      return result.state == StagingExecutionState.completed;
    } on Object catch (error) {
      if (!_sessionOpen(tabId, intent.identity)) return false;
      final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
      if (failure is! OutcomeUnknownFailure) {
        _effect(ChangesActionFailed(tabId, side, scope));
      }
      if (interaction.active) {
        interaction.reportChanges(StagingFailed(failure, side: side));
      }
      return false;
    } finally {
      if (started && _sessionOpen(tabId, intent.identity)) {
        _effect(ChangesMoveEnded(tabId, moved: moved));
      }
    }
  }

  void _followMove(
    int tabId,
    RepositoryStatus status,
    StagingSide side,
    List<RepositoryStatusEntry> entries,
    String? next,
  ) {
    final tab = _tab(tabId);
    final selection = tab.selection;
    final source = {...selection.of(side)}..removeAll(entries.map(changeKey));
    var staged = side == StagingSide.staged ? source : {...selection.staged};
    var unstaged = side == StagingSide.unstaged
        ? source
        : {...selection.unstaged};
    var focused = selection.focusedSide;
    if (next != null) {
      // The next file of the same list takes the selection.
      if (side == StagingSide.staged) {
        unstaged = {};
      } else {
        staged = {};
      }
      final nextEntry = entriesOn(
        status,
        side,
      ).where((entry) => changeDisplayIdentity(entry.path) == next).firstOrNull;
      if (nextEntry != null) {
        final keys = {changeKey(nextEntry)};
        if (side == StagingSide.staged) {
          staged = keys;
        } else {
          unstaged = keys;
        }
        focused = side;
      }
    } else if (entries.isNotEmpty) {
      // The last file follows itself to the other list.
      final keys = {changeKey(entries.first)};
      if (side == StagingSide.staged) {
        unstaged = keys;
      } else {
        staged = keys;
      }
      focused = otherSide(side);
    }
    tab.selection = ChangesSelection(
      staged: staged,
      unstaged: unstaged,
      focusedSide: focused,
    );
    _notify(tabId);
    final identity =
        next ??
        (entries.isEmpty ? null : changeDisplayIdentity(entries.first.path));
    if (identity != null && _repositories.activeTabId == tabId) {
      _navigator.selectIdentity(identity);
    }
  }

  /// Reviews every part of the selection before cleaning new files and
  /// restoring tracked changes. Each native preview keeps its own drift guard.
  Future<void> discard(
    ChangesInteraction interaction,
    int tabId,
    List<RepositoryStatusEntry> entries, {
    DiffPage? accepted,
    List<String> rowIds = const [],
  }) async {
    final kind = accepted == null
        ? discardKindOf(entries)
        : DiscardKind.discard;
    if (kind == null ||
        entries.isEmpty ||
        _busy.isBusy(tabId) ||
        _refused(interaction, tabId, AppCommandId.discardChanges)) {
      return;
    }
    final identity = _tabState(tabId)?.session?.identity;
    bool current() =>
        interaction.active &&
        identity != null &&
        _repositories.activeTabId == tabId &&
        _tabState(tabId)?.session?.identity == identity;
    if (!current()) return;
    await _busy.run(tabId, const ChangesBusy(), blocking: false, () async {
      var started = false;
      var moved = false;
      var completedFiles = 0;
      var totalFiles = 0;
      final previews = <DiscardPreview>[];
      void reportStopped(ChangesOutcome outcome) {
        if (!interaction.active) return;
        interaction.reportChanges(
          completedFiles > 0
              ? DiscardPartiallyFinished(completedFiles, totalFiles)
              : outcome,
        );
      }

      try {
        final requests = accepted != null
            ? [
                DiscardRequest(
                  kind: DiscardKind.discard,
                  scope: DiscardScope.rows,
                  workingDiffRequestId: accepted.requestId,
                  rowIds: rowIds,
                ),
              ]
            : [
                for (final part in [DiscardKind.clean, DiscardKind.discard])
                  if (entries.any(
                    (entry) =>
                        (entry.kind == StatusEntryKind.untracked) ==
                        (part == DiscardKind.clean),
                  ))
                    DiscardRequest(
                      kind: part,
                      scope: DiscardScope.files,
                      paths: uniqueCommandPaths(
                        entries
                            .where(
                              (entry) =>
                                  (entry.kind == StatusEntryKind.untracked) ==
                                  (part == DiscardKind.clean),
                            )
                            .toList(),
                      ),
                    ),
              ];
        for (final request in requests) {
          if (!current()) return;
          previews.add(await _repositories.workingCopy.previewDiscard(request));
        }
        totalFiles = previews.fold(
          0,
          (count, preview) => count + preview.fileCount,
        );
        final review = DiscardReview(
          trackedFiles: previews
              .where((p) => p.kind == DiscardKind.discard)
              .fold(0, (count, p) => count + p.fileCount),
          untrackedFiles: previews
              .where((p) => p.kind == DiscardKind.clean)
              .fold(0, (count, p) => count + p.fileCount),
        );
        if (!current() ||
            !await interaction.confirmDiscard(review) ||
            !current()) {
          return;
        }
        if (accepted == null) {
          _effect(
            ChangesMoveStarted(
              tabId,
              StagingSide.unstaged,
              entries.map(changeKey).toSet(),
            ),
          );
          started = true;
        }
        var warning = false;
        // Cleaning preserves the index bytes captured by the restore preview.
        // Restoring first can refresh index stat data and stale the clean token.
        for (final preview in previews) {
          if (!current()) {
            reportStopped(const DiscardFailed(UnexpectedFailure()));
            return;
          }
          final result = await _repositories.workingCopy.executeDiscard(
            preview,
          );
          if (result.state != DiscardExecutionState.completed &&
              result.state != DiscardExecutionState.reconciledWithWarning) {
            moved =
                moved || result.state == DiscardExecutionState.outcomeUncertain;
            reportStopped(DiscardFinished(result.state));
            return;
          }
          moved = true;
          completedFiles += preview.fileCount;
          warning =
              warning ||
              result.state == DiscardExecutionState.reconciledWithWarning;
        }
        if (interaction.active) {
          interaction.reportChanges(
            DiscardFinished(
              warning
                  ? DiscardExecutionState.reconciledWithWarning
                  : DiscardExecutionState.completed,
            ),
          );
        }
      } on Object catch (error) {
        final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
        reportStopped(DiscardFailed(failure));
      } finally {
        if (started) _effect(ChangesMoveEnded(tabId, moved: moved));
      }
    });
  }

  /// Asks whether the repository of [tabId] has a paused operation the
  /// status does not show, such as a resolved one awaiting Continue.
  Future<void> probeConflicts(int tabId) async {
    if (hasActiveConflicts(_status(tabId))) return;
    final tab = _tab(tabId);
    final probe = ++tab.probe;
    try {
      final snapshot = await _repositories.conflicts.load();
      if (probe != tab.probe || _repositories.activeTabId != tabId) return;
      if (snapshot.files.isNotEmpty ||
          snapshot.canContinue ||
          snapshot.canSkip) {
        tab
          ..conflictFlowActive = true
          ..conflictFlowDismissed = false;
        _notify(tabId);
      } else if (tab.conflictFlowActive) {
        tab
          ..conflictFlowActive = false
          ..conflictFlowDismissed = true;
        _notify(tabId);
      }
    } on ConflictException catch (error) {
      if (error.code == ConflictFailureCode.noActiveOperation &&
          probe == tab.probe &&
          _repositories.activeTabId == tabId &&
          tab.conflictFlowActive) {
        tab
          ..conflictFlowActive = false
          ..conflictFlowDismissed = true;
        _notify(tabId);
      }
    } on Object {
      // Keep an existing resolver visible when the status probe fails.
    }
  }

  /// The resolver of [tabId] closed; the lists come back until a new
  /// conflict appears.
  void finishConflictFlow(int tabId) {
    final tab = _tab(tabId);
    tab
      ..conflictFlowActive = false
      ..conflictFlowDismissed = true;
    _notify(tabId);
  }

  /// The side and files a patch of the selection covers: the focused list's
  /// selection, or the other list's when the focused one has none.
  ({StagingSide side, List<RepositoryStatusEntry> entries}) patchSelection(
    int tabId,
  ) {
    var side = _tab(tabId).selection.focusedSide;
    var entries = selectedEntries(tabId, side);
    if (entries.isEmpty) {
      final other = selectedEntries(tabId, otherSide(side));
      if (other.isNotEmpty) {
        side = otherSide(side);
        entries = other;
      }
    }
    return (side: side, entries: entries);
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final tabId in _tabs.keys.toList()) {
      clearPendingStages(tabId);
    }
    await _workspace.cancel();
    await _changes.close();
    await _effects.close();
  }
}
