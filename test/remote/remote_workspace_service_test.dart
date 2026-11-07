import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_directory.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/remote_connection_repository.dart';
import 'package:gitlama/repositories/remote_session_repository.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/remote_workspace_service.dart';
import 'package:gitlama/services/settings_service.dart';

import '../support/fake_settings_repository.dart';
import 'support/fake_remote_channel.dart';

final class _Surface implements RemoteSessionSurface {
  _Surface(this.channel);

  final RemoteChannel channel;
  final lookups = <RemotePendingOperation>[];
  RemotePendingOperation Function(RemotePendingOperation operation)? answer;

  @override
  RepositorySessionRepository get sessions => throw UnimplementedError();

  @override
  RemoteDetachedReads get detachedReads => throw UnimplementedError();

  @override
  String? bindingOf(RepositorySessionIdentity session) => null;

  @override
  Future<OperationCenterSnapshot> operations() async =>
      OperationCenterSnapshot.empty;

  @override
  Future<void> dismissOperation(OperationCenterEntry entry) async {}

  @override
  Future<RemotePendingOperation> lookup(
    RemotePendingOperation operation,
  ) async {
    lookups.add(operation);
    return answer?.call(operation) ?? operation;
  }

  @override
  Future<RemoteDirectoryPage> listDirectory({
    List<int>? directory,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<void> initializeRepository({
    required List<int> path,
    required String initialBranch,
    required bool bare,
  }) => throw UnimplementedError();
}

final class _Factory implements RemoteSessionFactory {
  final surfaces = <_Surface>[];

  @override
  RemoteSessionSurface create(
    RemoteChannel channel, {
    required RemoteAuthority authority,
    required RemoteOperationLedger ledger,
    required BigInt Function() allocateSessionId,
    required String? Function(List<int> path) expectedBinding,
    required void Function(List<int> path, String binding) rememberBinding,
  }) {
    final surface = _Surface(channel);
    surfaces.add(surface);
    return surface;
  }
}

final class _Pending implements RemotePendingRepository {
  List<RemotePendingOperation> saved = const [];
  Object? loadFailure;
  Object? saveFailure;

  @override
  Future<List<RemotePendingOperation>> load() async {
    final failure = loadFailure;
    if (failure != null) throw failure;
    return saved;
  }

  @override
  Future<void> save(List<RemotePendingOperation> operations) async {
    final failure = saveFailure;
    if (failure != null) throw failure;
    saved = List.of(operations);
  }
}

RemotePendingOperation _operation(
  String id,
  RemoteAuthority authority, {
  bool pending = true,
}) => RemotePendingOperation(
  operationId: id * 16,
  epoch: 'e' * 32,
  digest: 'd' * 64,
  family: RemoteOperationFamily.commit,
  authority: authority,
  binding: 'b' * 64,
  pending: pending,
  outcome: pending ? null : RemoteOperationOutcome.succeeded,
  summary: 'commit',
  createdAtMs: 1,
  updatedAtMs: 1,
);

void main() {
  late SettingsService settings;
  late FakeRemoteConnectionRepository connections;
  late _Factory factory;
  late _Pending pending;
  late RemoteWorkspaceService service;
  late List<FakeRemoteChannel> channels;

  Future<void> create({_Pending? ledger}) async {
    settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    channels = [];
    connections = FakeRemoteConnectionRepository((capabilities) {
      final channel = FakeRemoteChannel(capabilities: capabilities);
      channels.add(channel);
      return channel;
    });
    factory = _Factory();
    pending = ledger ?? _Pending();
    service = RemoteWorkspaceService(
      connections,
      factory,
      pending,
      settings,
      directory: LiveRemoteSessions(),
    );
    await service.initialize();
  }

  setUp(create);
  tearDown(() async {
    await service.dispose();
    await settings.dispose();
  });

  test('profiles validate their alias and label and persist', () async {
    await expectLater(
      service.saveProfile(label: 'Box', alias: '-oProxyCommand=evil'),
      throwsA(isA<RemoteWorkspaceException>()),
    );
    await expectLater(
      service.saveProfile(label: '', alias: 'devbox'),
      throwsA(isA<RemoteWorkspaceException>()),
    );
    final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
    expect(isValidRemoteProfileId(profile.id), isTrue);
    expect(settings.current.remoteProfiles.single.alias, 'devbox');
  });

  test(
    'the first connection verifies the identity and attempts are shared',
    () async {
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      final first = service.connect(profile.id);
      final second = service.connect(profile.id);
      final states = await Future.wait([first, second]);
      expect(states.every((state) => state.ready), isTrue);
      expect(connections.requests, hasLength(1));
      expect(connections.requests.single.capabilities, {
        RemoteCapability.read,
        RemoteCapability.listDirectory,
      });
      final verified = service.profile(profile.id)!.verified!;
      expect(verified.storeId, 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0');
      expect(service.isLive(service.profile(profile.id)!.authority!), isTrue);
    },
  );

  test(
    'a changed helper identity is never attached and rebinding withdraws writes',
    () async {
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      await service.connect(profile.id);
      await service.setWritesAllowed(profile.id, true);
      final authority = service.profile(profile.id)!.authority!;
      await service.disconnect(profile.id);
      connections.next = (capabilities) {
        final channel = FakeRemoteChannel(
          capabilities: capabilities,
          storeId: 'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0',
        );
        channels.add(channel);
        return channel;
      };
      final changed = await service.connect(profile.id);
      expect(changed.phase, RemoteConnectionPhase.identityChanged);
      expect(channels.last.closeRequests, 1);
      expect(service.isLive(authority), isFalse);
      expect(
        service.observedIdentity(profile.id)!.storeId,
        'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0',
      );
      final rebound = await service.rebind(profile.id);
      expect(rebound.ready, isTrue);
      final updated = service.profile(profile.id)!;
      expect(updated.verified!.storeId, 'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0');
      expect(updated.writesAllowed, isFalse);
      expect(
        connections.requests.last.capabilities,
        isNot(contains(RemoteCapability.stage)),
      );
    },
  );

  test('changing the alias withdraws verification and writes', () async {
    final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
    await service.connect(profile.id);
    await service.setWritesAllowed(profile.id, true);
    final edited = await service.saveProfile(
      id: profile.id,
      label: 'Box',
      alias: 'otherbox',
    );
    expect(edited.verified, isNull);
    expect(edited.writesAllowed, isFalse);
    expect(channels.single.closeRequests, 1);
  });

  test(
    'writes are requested only when allowed and the ledger is readable',
    () async {
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      await service.connect(profile.id);
      await service.setWritesAllowed(profile.id, true);
      await service.disconnect(profile.id);
      await service.connect(profile.id);
      expect(
        connections.requests.last.capabilities,
        contains(RemoteCapability.commit),
      );
      await service.dispose();
      await settings.dispose();
      final unreadable = _Pending()..loadFailure = StateError('corrupt');
      await create(ledger: unreadable);
      expect(service.ledgerUsable, isFalse);
      await expectLater(
        service.record(
          _operation(
            'a',
            const RemoteAuthority(
              profileId: '123e4567-e89b-42d3-a456-426614174000',
              storeId: 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0',
              accountUid: '1000',
            ),
          ),
        ),
        throwsA(isA<RemoteWorkspaceException>()),
      );
    },
  );

  test(
    'transport failures map to typed states, including unexpected errors',
    () async {
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      connections.next = (_) => throw const RemoteWorkspaceException(
        RemoteFailureCode.helperNotInstalled,
      );
      final missing = await service.connect(profile.id);
      expect(missing.phase, RemoteConnectionPhase.failed);
      expect(missing.failure, RemoteFailureCode.helperNotInstalled);
      connections.next = (_) => throw StateError('unexpected');
      final unexpected = await service.connect(profile.id);
      expect(unexpected.failure, RemoteFailureCode.internal);
      connections.next = (_) =>
          throw const RemoteWorkspaceException(RemoteFailureCode.canceled);
      final canceled = await service.connect(profile.id);
      expect(canceled.phase, RemoteConnectionPhase.idle);
    },
  );

  test(
    'a dropped connection is reported and never reconnects by itself',
    () async {
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      await service.connect(profile.id);
      final states = <RemoteConnectionPhase>[];
      final subscription = service.states.listen(
        (state) => states.add(state.phase),
      );
      channels.single.drop();
      await pumpEventQueue();
      expect(states, [RemoteConnectionPhase.disconnected]);
      expect(service.state(profile.id).failure, RemoteFailureCode.disconnected);
      await pumpEventQueue(times: 50);
      expect(connections.requests, hasLength(1));
      await subscription.cancel();
    },
  );

  test(
    'a reconnect looks up unresolved writes of its authority only',
    () async {
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      await service.connect(profile.id);
      final authority = service.profile(profile.id)!.authority!;
      const foreign = RemoteAuthority(
        profileId: '123e4567-e89b-42d3-a456-426614174000',
        storeId: 'c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0',
        accountUid: '1000',
      );
      await service.record(_operation('a', authority));
      await service.record(_operation('b', foreign));
      await service.record(_operation('c', authority, pending: false));
      await service.disconnect(profile.id);
      final reconnect = service.connect(profile.id);
      await reconnect;
      final surface = factory.surfaces.last;
      surface.answer = (operation) =>
          operation.resolved(RemoteOperationOutcome.succeeded, atMs: 2);
      await service.reconcile(profile.id);
      expect(
        surface.lookups.map((operation) => operation.operationId).toSet(),
        {'a' * 16},
      );
      expect(
        service.operations
            .singleWhere((operation) => operation.operationId == 'a' * 16)
            .pending,
        isFalse,
      );
      expect(
        service.operations
            .singleWhere((operation) => operation.operationId == 'b' * 16)
            .pending,
        isTrue,
      );
    },
  );

  test('unresolved writes are never evicted', () async {
    final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
    await service.connect(profile.id);
    final authority = service.profile(profile.id)!.authority!;
    for (var index = 0; index < 1024; index += 1) {
      await service.record(
        _operation(
          index.toRadixString(16).padLeft(2, '0'),
          authority,
        ).stillPending(atMs: index)._withId(index),
      );
    }
    await expectLater(
      service.record(_operation('ff', authority)._withId(5000)),
      throwsA(
        isA<RemoteWorkspaceException>().having(
          (error) => error.code,
          'code',
          RemoteFailureCode.receiptCapacity,
        ),
      ),
    );
  });

  test('shutdown closes every connection within its deadline', () async {
    final first = await service.saveProfile(label: 'One', alias: 'one');
    final second = await service.saveProfile(label: 'Two', alias: 'two');
    await service.connect(first.id);
    await service.connect(second.id);
    final started = DateTime.now();
    await service.dispose();
    expect(
      DateTime.now().difference(started),
      lessThan(remoteShutdownDeadline),
    );
    expect(channels.every((channel) => channel.closeRequests == 1), isTrue);
  });
}

extension on RemotePendingOperation {
  RemotePendingOperation _withId(int index) => RemotePendingOperation(
    operationId: index.toRadixString(16).padLeft(32, '0'),
    epoch: epoch,
    digest: digest,
    family: family,
    authority: authority,
    binding: binding,
    pending: true,
    summary: summary,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs,
  );
}
