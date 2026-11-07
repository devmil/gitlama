import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/status_acceleration.dart';
import 'package:gitlama/services/repository_session_service.dart';

import 'support/fake_repository_session_repository.dart';

RepositorySessionIdentity _identity(
  int id, {
  RepositoryBackendKind backend = RepositoryBackendKind.local,
}) => RepositorySessionIdentity(
  nativeId: BigInt.from(id),
  generation: 1,
  backend: backend,
);

void main() {
  test('a slow scan with something to enable is worth offering', () {
    const slow = Duration(seconds: 4);
    expect(
      const StatusAcceleration(
        untrackedCache: false,
        fsmonitor: false,
        fsmonitorAvailable: false,
        lastScan: slow,
      ).worthOffering,
      isTrue,
    );
    expect(
      const StatusAcceleration(
        untrackedCache: true,
        fsmonitor: false,
        fsmonitorAvailable: true,
        lastScan: slow,
      ).worthOffering,
      isTrue,
    );
    expect(
      const StatusAcceleration(
        untrackedCache: true,
        fsmonitor: false,
        fsmonitorAvailable: false,
        lastScan: slow,
      ).worthOffering,
      isFalse,
    );
    expect(
      const StatusAcceleration(
        untrackedCache: false,
        fsmonitor: false,
        fsmonitorAvailable: true,
        lastScan: Duration(seconds: 1),
      ).worthOffering,
      isFalse,
    );
    expect(
      const StatusAcceleration(
        untrackedCache: false,
        fsmonitor: false,
        fsmonitorAvailable: true,
      ).worthOffering,
      isFalse,
    );
  });

  test('the offer is checked once per session and stays dismissed', () async {
    final repository = FakeRepositorySessionRepository(null)
      ..acceleration = const StatusAcceleration(
        untrackedCache: false,
        fsmonitor: false,
        fsmonitorAvailable: true,
        lastScan: Duration(seconds: 9),
      );
    final commands = RepositorySessionService(repository).workingCopy;
    final first = _identity(1);
    expect(
      (await commands.statusAccelerationOffer(first))?.worthOffering,
      isTrue,
    );
    expect(
      (await commands.statusAccelerationOffer(first))?.worthOffering,
      isTrue,
    );
    expect(repository.accelerationReads, 1);

    commands.dismissStatusAccelerationOffer(first);
    expect(await commands.statusAccelerationOffer(first), isNull);
    expect(await commands.statusAccelerationOffer(_identity(2)), isNotNull);
    expect(repository.accelerationReads, 2);
  });

  test(
    'the settings read past a dismissal and enabling is announced',
    () async {
      final repository = FakeRepositorySessionRepository(null)
        ..acceleration = const StatusAcceleration(
          untrackedCache: false,
          fsmonitor: false,
          fsmonitorAvailable: false,
        );
      final commands = RepositorySessionService(repository).workingCopy;
      final first = _identity(1);
      commands.dismissStatusAccelerationOffer(first);
      expect(
        (await commands.statusAcceleration(first))?.untrackedCache,
        isFalse,
      );
      expect(
        await commands.statusAcceleration(
          _identity(2, backend: RepositoryBackendKind.remote),
        ),
        isNull,
      );
      expect(repository.accelerationReads, 1);

      final announced = commands.statusAccelerationEnabled.first;
      await commands.enableStatusAcceleration(first);
      expect((await announced).nativeId, first.nativeId);
    },
  );

  test('remote sessions are never offered local Git settings', () async {
    final repository = FakeRepositorySessionRepository(null);
    final commands = RepositorySessionService(repository).workingCopy;
    expect(
      await commands.statusAccelerationOffer(
        _identity(3, backend: RepositoryBackendKind.remote),
      ),
      isNull,
    );
    expect(repository.accelerationReads, 0);
  });
}
