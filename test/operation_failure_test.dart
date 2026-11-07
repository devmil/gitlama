import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_update.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/host_platform.dart';
import 'package:gitlama/models/operation_failure.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/services/operation_center_service.dart';

void main() {
  test('support reports contain stable typed reasons and no user message', () {
    final details = OperationFailureDetails(
      operation: UserOperationKind.unstage,
      staging: StagingDiagnostic(
        code: StagingFailureCode.indexLocked,
        gitVersion: '2.50.1',
        activityId: BigInt.from(7),
        exitCode: 128,
      ),
    );
    final report = details.report(
      release: const InstalledRelease(version: '0.1.0-beta.44', build: 45),
      platform: HostPlatform.macOS,
    );
    expect(report, contains('Code: staging.indexLocked'));
    expect(report, contains('Git: 2.50.1'));
    expect(report, contains('Exit code: 128'));
    expect(report, contains('Build: 45'));
    final malicious = const OperationFailureDetails(
      staging: StagingDiagnostic(
        code: StagingFailureCode.gitFailed,
        gitVersion: 'https://private.invalid/token',
      ),
    );
    expect(
      malicious.report(platform: HostPlatform.macOS),
      isNot(contains('private.invalid')),
    );
  });

  test('transfer reports name the failure code and Git command only', () {
    final report = OperationFailureDetails(
      operation: UserOperationKind.transfer,
      transfer: TransferFailureCode.locked,
      activity: (
        session: RepositorySessionIdentity(nativeId: BigInt.two, generation: 3),
        id: BigInt.from(41),
      ),
    ).report(platform: HostPlatform.macOS);
    expect(report, contains('Operation: transfer'));
    expect(report, contains('Code: transfer.locked'));
    expect(report, contains('Activity: 41'));
  });

  test(
    'user failures survive polling and have bounded, dismissible retention',
    () async {
      final service = OperationCenterService.empty();
      await service.initialize();
      for (var i = 0; i < 40; i++) {
        service.recordUserFailure(
          'private-sentinel-$i',
          const OperationFailureDetails(),
        );
      }
      expect(
        service.current.entries.length,
        OperationCenterService.userFailureCapacity,
      );
      expect(
        service.current.entries.map((entry) => entry.activityId).toSet().length,
        32,
      );
      await service.refresh();
      expect(service.current.failedCount, 32);
      final first = service.current.entries.first;
      expect(
        first.userFailure!.details.report(platform: HostPlatform.macOS),
        isNot(contains('private-sentinel')),
      );
      await service.dismiss(first);
      expect(service.current.failedCount, 31);
      await service.dismissAll();
      expect(service.current.entries, isEmpty);
      await service.dispose();
    },
  );
}
