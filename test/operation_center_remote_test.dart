import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/operation_center_repository.dart';
import 'package:gitlama/services/operation_center_service.dart';

OperationCenterEntry _entry(
  int id,
  OperationCenterState state, {
  RepositoryBackendKind backend = RepositoryBackendKind.local,
  int started = 0,
  ActivityProgress? progress,
}) => OperationCenterEntry(
  activityId: BigInt.from(id),
  session: RepositorySessionIdentity(
    nativeId: BigInt.from(
      backend == RepositoryBackendKind.remote ? 1 << 62 : 1,
    ),
    generation: 1,
    backend: backend,
  ),
  state: state,
  origin: OperationCenterOrigin.user,
  action: OperationCenterAction.push,
  startedAtUnixMs: BigInt.from(started),
  canCancel: false,
  canRetry: false,
  hasDetails: true,
  progress: progress,
);

OperationCenterSnapshot _snapshot(List<OperationCenterEntry> entries) =>
    OperationCenterSnapshot(
      entries: entries,
      runningCount: entries
          .where((entry) => entry.state == OperationCenterState.running)
          .length,
      failedCount: entries
          .where((entry) => entry.state == OperationCenterState.failed)
          .length,
      attentionCount: 0,
      truncated: false,
    );

final class _Local implements OperationCenterRepository {
  OperationCenterSnapshot current = OperationCenterSnapshot.empty;
  final dismissed = <OperationCenterEntry>[];

  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async =>
      current;

  @override
  Future<void> dismiss(OperationCenterEntry entry) async =>
      dismissed.add(entry);

  @override
  Future<void> dismissAll() async {}
}

final class _Remote implements RemoteOperationSource {
  List<OperationCenterSnapshot> current = const [];
  final dismissed = <OperationCenterEntry>[];

  @override
  Future<List<OperationCenterSnapshot>> remoteOperations() async => current;

  @override
  Future<void> dismissRemoteOperation(OperationCenterEntry entry) async =>
      dismissed.add(entry);
}

void main() {
  test(
    'remote operations appear next to local ones, ordered by state',
    () async {
      final local = _Local()
        ..current = _snapshot([
          _entry(1, OperationCenterState.succeeded, started: 10),
        ]);
      final remote = _Remote()
        ..current = [
          _snapshot([
            _entry(
              7,
              OperationCenterState.running,
              backend: RepositoryBackendKind.remote,
              started: 5,
              progress: ActivityProgress(
                phase: 'Writing objects',
                completed: BigInt.from(3),
                total: BigInt.from(10),
                unit: 'objects',
              ),
            ),
            _entry(
              8,
              OperationCenterState.failed,
              backend: RepositoryBackendKind.remote,
              started: 1,
            ),
          ]),
        ];
      final service = OperationCenterService(local, remote: remote);
      await service.refresh();
      final snapshot = service.current;
      expect(
        [for (final entry in snapshot.entries) entry.activityId!.toInt()],
        [8, 7, 1],
      );
      expect(snapshot.runningCount, 1);
      expect(snapshot.failedCount, 1);
      expect(snapshot.entries[1].progress?.completed, BigInt.from(3));

      // A dismissal goes to the side that owns the operation.
      await service.dismiss(snapshot.entries.first);
      expect(remote.dismissed.single.activityId, BigInt.from(8));
      expect(local.dismissed, isEmpty);
      await service.dismiss(snapshot.entries.last);
      expect(local.dismissed.single.activityId, BigInt.one);
      await service.dispose();
    },
  );

  test('dismiss all clears remote failures and warnings', () async {
    final local = _Local();
    final remote = _Remote()
      ..current = [
        _snapshot([
          for (final (id, state) in [
            (1, OperationCenterState.failed),
            (2, OperationCenterState.warning),
            (3, OperationCenterState.succeeded),
            (4, OperationCenterState.running),
          ])
            _entry(id, state, backend: RepositoryBackendKind.remote),
        ]),
      ];
    final service = OperationCenterService(local, remote: remote);
    await service.refresh();
    await service.dismissAll();
    expect([
      for (final entry in remote.dismissed) entry.activityId!.toInt(),
    ], unorderedEquals([1, 2]));
    await service.dispose();
  });
}
