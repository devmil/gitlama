import 'dart:async';

import '../../models/history.dart';
import '../../models/settings.dart';
import '../repository_session_service.dart';

/// What a one-shot request asks the window to do.
enum WorkspaceEffectKind {
  /// Scroll History to a commit: payload [RevealCommit].
  revealCommit,

  /// Flash a commit the Composer just made: payload [CommittedFlash].
  flashCommit,

  /// Put the keyboard focus into History's search field.
  focusHistorySearch,

  /// Commit (payload false) or prepare an amend (true) in the Composer.
  commit,

  /// Run a conflict command in the resolver: payload an `AppCommandId`.
  conflictCommand,

  /// Open the provider page that creates a pull request for the branch.
  createChangeRequest,
}

/// History should scroll row [index] of history request [requestId] into
/// view.
typedef RevealCommit = ({BigInt requestId, int index});

/// The Composer made [objectId] in [repository]; [amend] when it replaced
/// HEAD.
typedef CommittedFlash = ({
  NativePathIdentity? repository,
  String objectId,
  bool amend,
});

/// A one-shot request for the screen: reveal, flash or focus something. The
/// [id] increases with every effect, so a surface that appears later can
/// tell an effect it has not handled yet from one it has.
final class WorkspaceEffect {
  const WorkspaceEffect(this.id, this.kind, [this.payload]);

  final int id;
  final WorkspaceEffectKind kind;
  final Object? payload;
}

/// The window's one channel for effects. Services emit; widgets listen and
/// read the [latest] effect of a kind when they mount.
final class WorkspaceEffects {
  WorkspaceEffects(this._repositories) {
    _history = _repositories.history.states.listen(_followHistory);
  }

  final RepositorySessionService _repositories;
  late final StreamSubscription<HistoryState> _history;
  final StreamController<WorkspaceEffect> _effects =
      StreamController<WorkspaceEffect>.broadcast(sync: true);
  final Map<WorkspaceEffectKind, WorkspaceEffect> _latest = {};
  final Map<WorkspaceEffectKind, WorkspaceEffect> _pending = {};
  var _next = 1;
  var _disposed = false;
  ({BigInt requestId, int sequence})? _revealed;

  Stream<WorkspaceEffect> get effects => _effects.stream;

  /// The effects of [kind] from now on.
  Stream<WorkspaceEffect> of(WorkspaceEffectKind kind) =>
      effects.where((effect) => effect.kind == kind);

  /// The last effect of [kind], for a surface that mounts after it.
  WorkspaceEffect? latest(WorkspaceEffectKind kind) => _latest[kind];

  /// The effect of [kind] nobody handled yet, which this call handles.
  /// Focus requests use it: a surface that mounts after the request still
  /// gets it once.
  WorkspaceEffect? take(WorkspaceEffectKind kind) {
    final effect = _pending.remove(kind);
    return effect;
  }

  /// Marks the effect of [kind] handled by a surface that was listening.
  void handled(WorkspaceEffect effect) {
    if (identical(_pending[effect.kind], effect)) _pending.remove(effect.kind);
  }

  /// Publishes an effect of [kind]. A [sticky] effect waits for a surface
  /// that shows later ([take]); others reach only the surfaces listening
  /// now, such as a command for an editor that may not be on screen.
  void emit(WorkspaceEffectKind kind, [Object? payload, bool sticky = true]) {
    if (_disposed) return;
    final effect = WorkspaceEffect(_next++, kind, payload);
    _latest[kind] = effect;
    if (sticky) {
      _pending[kind] = effect;
    } else {
      _pending.remove(kind);
    }
    _effects.add(effect);
  }

  /// History marks a reveal in its state; this turns each new one into an
  /// effect.
  void _followHistory(HistoryState state) {
    final page = state.page;
    final index = page?.revealIndex;
    if (page == null || index == null || page.revealSequence == 0) return;
    final revealed = _revealed;
    if (revealed != null &&
        revealed.requestId == page.requestId &&
        revealed.sequence >= page.revealSequence) {
      return;
    }
    _revealed = (requestId: page.requestId, sequence: page.revealSequence);
    emit(WorkspaceEffectKind.revealCommit, (
      requestId: page.requestId,
      index: index,
    ));
  }

  Future<void> dispose() async {
    _disposed = true;
    await _history.cancel();
    await _effects.close();
  }
}
