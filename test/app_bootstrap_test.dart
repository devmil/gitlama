import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_bootstrap.dart';
import 'package:gitlama/di/app_components.dart';
import 'package:gitlama/di/component_registry.dart';
import 'package:gitlama/repositories/core_repository.dart';
import 'package:gitlama/models/cli_forwarding.dart';
import 'package:gitlama/repositories/cli_forwarding_repository.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/repositories/operation_center_repository.dart';
import 'package:gitlama/repositories/repository_drop_repository.dart';
import 'package:gitlama/repositories/window_geometry_repository.dart';
import 'package:gitlama/models/repository_drop.dart';

import 'support/fake_settings_repository.dart';
import 'support/fake_recovery_repository.dart';

void main() {
  test('production composition fails closed when native readiness fails', () {
    final repository = _InjectedCoreRepository(
      failure: StateError('native_protocol_mismatch private-path'),
    );

    expect(
      () => bootstrapApp(
        componentsFactory: () => AppComponents(
          coreRepositoryFactory: () => repository,
          cliForwardingRepositoryFactory: _CliRepository.new,
          settingsRepositoryFactory: FakeSettingsRepository.new,
          recoveryRepositoryFactory: FakeRecoveryRepository.new,
          repositoryDropRepositoryFactory: _EmptyDropRepository.new,
          windowGeometryRepositoryFactory: _UnavailableWindowRepository.new,
          operationCenterRepositoryFactory: _EmptyOperationRepository.new,
        ),
      ),
      throwsA(isA<ComponentInitializationException>()),
    );
  });

  test(
    'retry creates fresh production composition after native failure',
    () async {
      var attempts = 0;
      final repositories = <_InjectedCoreRepository>[];

      Future<void> attempt() async {
        await bootstrapApp(
          componentsFactory: () {
            attempts += 1;
            final repository = _InjectedCoreRepository(
              failure: attempts == 1 ? StateError('native_unavailable') : null,
            );
            repositories.add(repository);
            return AppComponents(
              coreRepositoryFactory: () => repository,
              cliForwardingRepositoryFactory: _CliRepository.new,
              settingsRepositoryFactory: FakeSettingsRepository.new,
              recoveryRepositoryFactory: FakeRecoveryRepository.new,
              repositoryDropRepositoryFactory: _EmptyDropRepository.new,
              windowGeometryRepositoryFactory: _UnavailableWindowRepository.new,
              operationCenterRepositoryFactory: _EmptyOperationRepository.new,
            );
          },
        );
      }

      await expectLater(
        attempt(),
        throwsA(isA<ComponentInitializationException>()),
      );
      late AppComponents components;
      final runtime = await bootstrapApp(
        componentsFactory: () {
          attempts += 1;
          final repository = _InjectedCoreRepository();
          repositories.add(repository);
          return components = AppComponents(
            coreRepositoryFactory: () => repository,
            cliForwardingRepositoryFactory: _CliRepository.new,
            settingsRepositoryFactory: FakeSettingsRepository.new,
            recoveryRepositoryFactory: FakeRecoveryRepository.new,
            repositoryDropRepositoryFactory: _EmptyDropRepository.new,
            windowGeometryRepositoryFactory: _UnavailableWindowRepository.new,
            operationCenterRepositoryFactory: _EmptyOperationRepository.new,
          );
        },
      );

      // Every service of the composition reaches the widget tree.
      final composed = components.runtime;
      expect(runtime.repositorySessions, same(composed.repositorySessions));
      expect(runtime.remoteWorkspaces, same(composed.remoteWorkspaces));
      expect(runtime.remoteWorkspaces, isNotNull);
      expect(runtime.inspectionWindows, same(composed.inspectionWindows));
      expect(runtime.inspectorReveal, same(composed.inspectorReveal));
      expect(runtime.settings, same(composed.settings));
      expect(runtime.avatars, same(composed.avatars));
      expect(
        runtime.repositoryAppearances,
        same(composed.repositoryAppearances),
      );
      expect(runtime.recovery, same(composed.recovery));
      expect(runtime.operationCenter, same(composed.operationCenter));
      expect(runtime.repositoryDrops, same(composed.repositoryDrops));
      expect(runtime.repositoryDrops, isNotNull);
      expect(runtime.hosting, same(composed.hosting));
      expect(runtime.hostingReview, same(composed.hostingReview));
      expect(runtime.hostingReview, isNotNull);
      expect(runtime.cliForwarding, same(composed.cliForwarding));
      expect(runtime.updates, same(composed.updates));
      expect(attempts, 2);
      expect(repositories, hasLength(2));
      expect(repositories[0], isNot(same(repositories[1])));
      expect(repositories[0].initializations, 1);
      expect(repositories[1].initializations, 1);
      await runtime.shutdown();
    },
  );
}

final class _InjectedCoreRepository implements CoreRepository {
  _InjectedCoreRepository({this.failure});

  final Object? failure;
  int initializations = 0;

  @override
  Future<void> initialize() async {
    initializations += 1;
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}

final class _EmptyDropRepository implements RepositoryDropRepository {
  @override
  Stream<RepositoryDropEvent> get events => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

final class _CliRepository implements CliForwardingRepository {
  @override
  Future<CliStartupResult> prepareProcessInvocation() async =>
      const CliStartupResult(state: CliStartupState.owner);

  @override
  Future<CliStartupResult> ensureOwner() async =>
      const CliStartupResult(state: CliStartupState.owner);

  @override
  Future<CliForwardedCommand?> poll() async => null;

  @override
  Future<bool> respond(
    BigInt requestId,
    CliForwardingResponse response,
  ) async => true;

  @override
  Future<void> dispose() async {}
}

final class _UnavailableWindowRepository implements WindowGeometryRepository {
  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<bool> initialize() async => false;

  @override
  Future<void> restore(WindowGeometry? geometry) async {}

  @override
  Future<void> activate() async {}

  @override
  Future<WindowGeometry> read() => throw StateError('window_unavailable');

  @override
  Future<void> dispose() async {}
}

final class _EmptyOperationRepository implements OperationCenterRepository {
  @override
  Future<OperationCenterSnapshot> snapshot({int maximumEntries = 256}) async =>
      OperationCenterSnapshot.empty;

  @override
  Future<void> dismiss(OperationCenterEntry entry) async {}

  @override
  Future<void> dismissAll() async {}
}
