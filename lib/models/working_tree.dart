import 'dart:convert';

import 'diff.dart';
import 'discard.dart';
import 'native_paths.dart';
import 'repository_state.dart';
import 'settings.dart';

/// The rules about working-tree changes that every surface shares: how a
/// change is identified, which paths a command takes, what Discard does and
/// whether a conflict is under way.

/// A stable key for [entry] in selections: its path and rename source.
String changeKey(RepositoryStatusEntry entry) => [
  entry.path.platform.index,
  ...entry.path.units,
  if (entry.source != null) ...entry.source!.units,
].join(':');

Iterable<List<int>> _commandPaths(RepositoryStatusEntry entry) sync* {
  if (entry.source case final source?) yield repositoryPathBytes(source);
  yield repositoryPathBytes(entry.path);
}

/// The Git paths a command on [entries] takes: each path once, with the
/// source of every rename.
List<List<int>> uniqueCommandPaths(Iterable<RepositoryStatusEntry> entries) {
  final paths = <String, List<int>>{};
  for (final path in entries.expand(_commandPaths)) {
    paths[base64Encode(path)] = path;
  }
  return paths.values.toList(growable: false);
}

/// The old and new paths of [entry]'s diff on [side]; null where the file
/// is absent on that side.
(List<int>?, List<int>?) diffPaths(
  RepositoryStatusEntry entry,
  StagingSide side,
) {
  final path = repositoryPathBytes(entry.path);
  if (entry.kind == StatusEntryKind.untracked) return (null, path);
  final change = side == StagingSide.staged ? entry.index : entry.worktree;
  if ((change == ChangeKind.renamed || change == ChangeKind.copied) &&
      entry.source != null) {
    return (repositoryPathBytes(entry.source!), path);
  }
  return switch (change) {
    ChangeKind.added => (null, path),
    ChangeKind.deleted => (path, null),
    _ => (path, path),
  };
}

/// Whether Discard can apply to [entry] at all: a tracked change Git can
/// restore, or an untracked file Clean removes.
bool discardable(RepositoryStatusEntry entry) =>
    entry.kind == StatusEntryKind.untracked ||
    entry.kind == StatusEntryKind.ordinary ||
    entry.kind == StatusEntryKind.rename;

/// What Discard does to [entries]: Clean when all are untracked, Discard
/// when any are tracked changes; null when they are empty or hold
/// a change neither applies to (a conflict, an ignored file).
DiscardKind? discardKindOf(Iterable<RepositoryStatusEntry> entries) {
  var untracked = false;
  var tracked = false;
  for (final entry in entries) {
    if (!discardable(entry)) return null;
    if (entry.kind == StatusEntryKind.untracked) {
      untracked = true;
    } else {
      tracked = true;
    }
  }
  if (!untracked && !tracked) return null;
  return !tracked ? DiscardKind.clean : DiscardKind.discard;
}

/// Whether single lines of [entry]'s diff on [side] can be discarded. An
/// untracked file has no lines to restore: Clean removes it whole.
bool canDiscardLines(RepositoryStatusEntry? entry, StagingSide side) =>
    side == StagingSide.unstaged &&
    entry != null &&
    entry.kind != StatusEntryKind.untracked;

/// Whether [status] shows a conflict or a paused operation other than
/// bisect.
bool hasActiveConflicts(RepositoryStatus? status) =>
    status != null &&
    (status.workingTree == WorkingTreeState.conflicted ||
        status.entries.any((entry) => entry.conflicted) ||
        status.operations.any(
          (operation) => operation.kind != RepositoryOperationKind.bisect,
        ));

/// The entries of [status] on [side].
List<RepositoryStatusEntry> entriesOn(
  RepositoryStatus status,
  StagingSide side,
) => status.entries
    .where(
      side == StagingSide.staged
          ? (entry) => entry.staged
          : (entry) => entry.unstaged,
    )
    .toList(growable: false);

/// The other list of the Changes pane.
StagingSide otherSide(StagingSide side) =>
    side == StagingSide.staged ? StagingSide.unstaged : StagingSide.staged;

/// [path] as Changes and History name a file.
String changeDisplayIdentity(NativePathIdentity path) => path.displayText;
