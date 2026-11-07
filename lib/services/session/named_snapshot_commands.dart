import 'dart:convert';

import '../../models/named_snapshot.dart';
import '../../models/repository_state.dart';
import '../../repositories/named_snapshot_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Named snapshots of the active repository's working state.
final class NamedSnapshotCommands {
  NamedSnapshotCommands(this._repository, this._scope, PreviewRegistry previews)
    : _restores = previews.sessions();

  final NamedSnapshotRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _restores;

  Future<NamedSnapshotPage> page({int offset = 0, int maximum = 32}) =>
      _repository.namedSnapshots(
        _scope.requireCurrent(),
        offset: offset,
        maximum: maximum,
      );

  Future<NamedSnapshotExecutionResult> create({
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) async => _repository.createNamedSnapshot(
    _scope.requireCurrent(),
    name: name,
    includeUntracked: includeUntracked,
    keepIndex: keepIndex,
  );

  Future<NamedSnapshotRestorePreview> previewRestore(BigInt snapshotId) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewNamedSnapshotRestore(
      identity,
      snapshotId,
    );
    _restores[preview.token] = identity;
    return preview;
  }

  Future<NamedSnapshotExecutionResult> executeRestore(
    NamedSnapshotRestorePreview preview,
  ) async {
    final identity = _restores[preview.token];
    if (identity == null) {
      throw const NamedSnapshotException(
        NamedSnapshotFailureCode.invalidRequest,
      );
    }
    try {
      return await _repository.executeNamedSnapshotRestore(
        identity,
        preview.token,
      );
    } finally {
      _restores.remove(preview.token);
    }
  }

  Future<bool> cancelRestore(NamedSnapshotRestorePreview preview) async {
    final identity = _restores[preview.token];
    if (identity == null) return false;
    return _repository.cancelNamedSnapshotRestore(identity, preview.token);
  }

  Future<NamedSnapshotExecutionResult> branchFrom(
    NamedSnapshot snapshot,
    String branch,
  ) async {
    final identity = _scope.requireCurrent();
    final result = await _repository.branchFromNamedSnapshot(
      identity,
      snapshot.id,
      utf8.encode(branch),
    );
    await _scope.refreshIfOpen(identity);
    return result;
  }

  Future<NamedSnapshotExecutionResult> delete(NamedSnapshot snapshot) async {
    final identity = _scope.requireCurrent();
    final result = await _repository.deleteNamedSnapshot(identity, snapshot.id);
    await _scope.refreshIfOpen(identity);
    return result;
  }
}
