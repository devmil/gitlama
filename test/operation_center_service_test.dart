import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/operation_center_repository.dart';
import 'package:gitlama/services/operation_center_service.dart';

void main() {
  test(
    'publishes completion while closed and routes typed dismissal',
    () async {
      final entry = OperationCenterEntry(
        activityId: BigInt.from(9),
        session: RepositorySessionIdentity(nativeId: BigInt.one, generation: 2),
        state: OperationCenterState.failed,
        origin: OperationCenterOrigin.user,
        action: OperationCenterAction.push,
        startedAtUnixMs: BigInt.one,
        canCancel: false,
        canRetry: false,
        hasDetails: true,
      );
      final repository = _OperationRepository(
        OperationCenterSnapshot(
          entries: [entry],
          runningCount: 0,
          failedCount: 1,
          attentionCount: 0,
          truncated: false,
        ),
      );
      final service = OperationCenterService(repository);
      await service.initialize();
      expect(service.current.failedCount, 1);

      repository.current = OperationCenterSnapshot.empty;
      await service.refresh();
      expect(service.current.entries, isEmpty);

      repository.current = OperationCenterSnapshot(
        entries: [entry],
        runningCount: 0,
        failedCount: 1,
        attentionCount: 0,
        truncated: false,
      );
      await service.dismiss(entry);
      expect(repository.dismissed, same(entry));
      await service.dismissAll();
      expect(repository.dismissAllCount, 1);
      await service.dispose();
    },
  );
}

final class _OperationRepository implements OperationCenterRepository {
  _OperationRepository(this.current);

  OperationCenterSnapshot current;
  OperationCenterEntry? dismissed;
  int dismissAllCount = 0;

  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async =>
      current;

  @override
  Future<void> dismiss(OperationCenterEntry entry) async {
    dismissed = entry;
  }

  @override
  Future<void> dismissAll() async {
    dismissAllCount += 1;
  }
}
