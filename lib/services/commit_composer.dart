import '../models/commit.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';
import '../repositories/commit_repository.dart';
import 'preview_registry.dart';
import 'settings_service.dart';

/// The Composer's state per worktree: durable drafts, the one-use commit
/// previews and the last commit each worktree made, which History flashes.
///
/// It owns the commit family of the session backend.
final class CommitComposer {
  CommitComposer(this._settings, this._repository);

  /// Absent where drafts are not kept.
  final SettingsService? _settings;
  final CommitRepository _repository;

  final PreviewRegistry _previews = PreviewRegistry();
  late final _owners = _previews
      .family<
        ({
          RepositorySessionIdentity session,
          NativePathIdentity canonical,
          bool amend,
        })
      >((value) => value.session);
  final Map<NativePathIdentity, ({int sequence, String objectId, bool amend})>
  _flashes = {};
  var _sequence = 0;

  /// Increments with each commit [canonical] made.
  int commitSequence(NativePathIdentity? canonical) =>
      canonical == null ? 0 : _flashes[canonical]?.sequence ?? 0;

  String? lastCommittedObjectId(NativePathIdentity? canonical) =>
      canonical == null ? null : _flashes[canonical]?.objectId;

  bool lastCommitWasAmend(NativePathIdentity? canonical) =>
      canonical != null && (_flashes[canonical]?.amend ?? false);

  CommitDraft draft(NativePathIdentity? canonical) {
    final settings = _settings;
    if (canonical == null || settings == null) return const CommitDraft();
    return settings.current.worktrees
            .where((worktree) => worktree.identity == canonical)
            .map((worktree) => worktree.draft)
            .firstOrNull ??
        const CommitDraft();
  }

  /// Keeps [draft] for [canonical]; saved in the background.
  void updateDraft(NativePathIdentity canonical, CommitDraft draft) =>
      _writeDraft(canonical, draft, durable: false);

  /// The commit options [session] offers: hooks, signing and templates.
  Future<CommitTools> tools(RepositorySessionIdentity session) =>
      _repository.commitTools(session);

  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity session,
    NativePathIdentity canonical,
    CommitRequest request,
  ) async {
    final preview = await _repository.previewCommit(session, request);
    _owners[preview.token] = (
      session: session,
      canonical: canonical,
      amend: request.amend,
    );
    return preview;
  }

  /// Commits [preview]. A commit that went through clears the draft when it
  /// is still the one that was submitted.
  Future<CommitExecutionResult> executeCommit(
    CommitPreview preview,
    CommitDraft submittedDraft,
  ) async {
    final owner = _owners.remove(preview.token);
    if (owner == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOptions),
      );
    }
    final result = await _repository.executeCommit(
      owner.session,
      preview.token,
    );
    final committed =
        result.state == CommitExecutionState.completed ||
        result.state == CommitExecutionState.reconciledWithWarning;
    if (committed && result.commit != null) {
      _sequence += 1;
      _flashes[owner.canonical] = (
        sequence: _sequence,
        objectId: result.commit!,
        amend: owner.amend,
      );
      while (_flashes.length > 16) {
        _flashes.remove(_flashes.keys.first);
      }
    }
    if (committed && draft(owner.canonical).matches(submittedDraft)) {
      await _writeDraft(owner.canonical, const CommitDraft(), durable: true);
    }
    return result;
  }

  void forgetSession(RepositorySessionIdentity session) =>
      _previews.forgetSession(session);

  void clear() => _previews.clear();

  Future<void> _writeDraft(
    NativePathIdentity canonical,
    CommitDraft draft, {
    required bool durable,
  }) async {
    final settings = _settings;
    if (settings == null) return;
    SettingsDocument withDraft(SettingsDocument current, CommitDraft draft) {
      final worktrees = List<WorktreeSettings>.of(current.worktrees);
      final index = worktrees.indexWhere(
        (worktree) => worktree.identity == canonical,
      );
      final existing = index < 0
          ? WorktreeSettings(identity: canonical)
          : worktrees[index];
      final updated = existing.copyWith(draft: draft);
      if (index < 0) {
        worktrees.add(updated);
      } else {
        worktrees[index] = updated;
      }
      return current.copyWith(worktrees: worktrees);
    }

    if (durable) {
      final previous = this.draft(canonical);
      // A rejected save restores this worktree's previous draft only.
      await settings.updateDurable(
        (current) => withDraft(current, draft),
        restore: (current, _) => withDraft(current, previous),
      );
    } else {
      settings.update((current) => withDraft(current, draft));
    }
  }
}
