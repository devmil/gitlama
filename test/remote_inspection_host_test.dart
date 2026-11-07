import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/remote_inspection.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/impl/remote/remote_inspection_channel.dart';
import 'package:gitlama/di/inspector_window_components.dart';
import 'package:gitlama/repositories/impl/remote/remote_inspection_calls.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_directory.dart';
import 'package:gitlama/repositories/impl/repository_session_calls.g.dart';
import 'package:gitlama/repositories/remote_inspection_host_repository.dart';
import 'package:gitlama/repositories/remote_session_repository.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/dto.dart';
import 'package:gitlama/services/inspector/inspector_window_session.dart';
import 'package:gitlama/services/remote_inspection_host_service.dart';

const _authority = RemoteAuthority(
  profileId: '0f8fad5b-d9cb-469f-a165-70867728950e',
  storeId: '0123456789abcdef0123456789abcdef',
  accountUid: '1000',
);
const _commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _repository = NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: '/srv/notelama'.codeUnits,
  remote: _authority,
);

/// A connection's detached sessions; every call is recorded.
final class _Reads implements RemoteDetachedReads {
  var _next = 900;
  final opened = <BigInt>[];
  final closed = <BigInt>[];
  final reads = <({BigInt session, String method})>[];

  /// What a read throws; null answers.
  Object? failure;

  /// Holds opens until completed.
  Completer<void>? gate;

  @override
  Future<({BigInt? session, Object? result})> open(
    List<int> path,
    BigInt generation,
  ) async {
    await gate?.future;
    final session = BigInt.from(_next++);
    opened.add(session);
    return (session: session, result: _openResult(session, generation));
  }

  @override
  Future<Object?> read(
    BigInt session,
    String method,
    Map<String, Object?> arguments,
  ) async {
    reads.add((session: session, method: method));
    if (failure case final failure?) throw failure;
    return encodeNativeCommitInspectionResult(
      const NativeCommitInspectionResult(
        failure: NativeRepositoryFailure(
          kind: NativeRepositoryFailureKind.missingObject,
        ),
      ),
    );
  }

  @override
  Future<void> close(BigInt session, BigInt generation) async {
    closed.add(session);
  }
}

Object? _openResult(BigInt session, BigInt generation) =>
    encodeNativeRepositoryOpenResult(
      NativeRepositoryOpenResult(
        session: NativeRepositorySession(
          sessionId: session,
          generation: generation,
          snapshot: NativeRepositorySnapshot(
            revision: BigInt.one,
            phase: NativeRepositoryPhase.ready,
            refCounts: NativeRepositoryRefCounts(
              branches: BigInt.zero,
              remotes: BigInt.zero,
              tags: BigInt.zero,
              stashes: BigInt.zero,
              worktrees: BigInt.zero,
            ),
            refs: const NativeRepositoryRefs(
              branches: [],
              remotes: [],
              tags: [],
              stashes: [],
              truncated: false,
            ),
          ),
        ),
      ),
    );

final class _Surface implements RemoteSessionSurface {
  _Surface(this.detachedReads);

  @override
  final RemoteDetachedReads detachedReads;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('only detached reads are served to windows');
}

final class _Host implements RemoteInspectionHostRepository {
  RemoteInspectionServer? server;
  final windows = StreamController<Set<String>>.broadcast();
  var disposed = 0;

  /// Whether serving fails, as without the window plugin.
  bool failServe = false;

  @override
  Future<void> serve(RemoteInspectionServer server) async {
    if (failServe) throw StateError('no window plugin');
    this.server = server;
  }

  @override
  Stream<Set<String>> get openWindows => windows.stream;

  @override
  Future<void> dispose() async => disposed += 1;
}

/// Reaches the main window through the channel's envelope, as a window does.
final class _Direct implements RemoteInspectionTransport {
  _Direct(this.server);

  final RemoteInspectionServer? server;
  final String window = '7';
  final payloads = <String>[];

  @override
  Future<String> windowId() async => window;

  @override
  Future<Object?> invoke(String method, String payload) async {
    payloads.add(payload);
    final server = this.server;
    if (server == null) {
      throw PlatformException(code: 'CHANNEL_UNREGISTERED');
    }
    return NativeRemoteInspectionHostRepository.answer(
      server,
      MethodCall(method, payload),
    );
  }
}

void main() {
  late LiveRemoteSessions directory;
  late _Reads reads;
  late _Surface surface;
  late _Host host;
  late RemoteInspectionHostService service;
  var live = true;

  setUp(() async {
    directory = LiveRemoteSessions();
    reads = _Reads();
    surface = _Surface(reads);
    live = true;
    directory.publish(_authority, surface, live: () => live);
    host = _Host();
    service = RemoteInspectionHostService(
      host,
      (authority) => directory.surfaceFor(authority)?.detachedReads,
    );
    await service.initialize();
  });

  tearDown(() => service.dispose());

  /// Sends one raw request through the envelope.
  Future<Map<String, Object?>> send(
    String method,
    Map<String, Object?> body, {
    String window = '7',
  }) async =>
      jsonDecode(
            await NativeRemoteInspectionHostRepository.answer(
              service,
              MethodCall(
                method,
                jsonEncode({'schema': 1, 'window': window, ...body}),
              ),
            ),
          )
          as Map<String, Object?>;

  Future<BigInt> open({String window = '7'}) async {
    final reply = await send('open', {
      'repository': {
        'units': _repository.units.toList(),
        'remote': _authority.toMessage(),
      },
      'generation': '5',
    }, window: window);
    expect(reply.keys, ['result']);
    return reads.opened.last;
  }

  Map<String, Object?> readOf(BigInt session, String method) => {
    'session': '$session',
    'method': method,
    'arguments': {'sessionId': '$session', 'generation': '5'},
  };

  group('the main window', () {
    test('opens, reads and closes a session of the window', () async {
      expect(host.server, same(service));
      final session = await open();
      expect(service.sessionCount, 1);
      final reply = await send(
        'read',
        readOf(session, 'repositorySessionCommitInspection'),
      );
      expect(reply.keys, ['result']);
      expect(reads.reads.single.session, session);
      await send('close', {'session': '$session', 'generation': '5'});
      expect(reads.closed, [session]);
      expect(service.sessionCount, 0);
    });

    test('forwards only the inspector reads', () async {
      final session = await open();
      for (final method in [
        // A write.
        'repositorySessionCommitExecute',
        // A read the inspector does not make.
        'repositorySessionHistoryLoad',
        'listDirectory',
      ]) {
        expect(await send('read', readOf(session, method)), {
          'failure': 'remoteNotOffered',
        });
      }
      expect(reads.reads, isEmpty);
    });

    test('the inspector reads are reads the helper offers', () {
      expect(remoteReadMethods.containsAll(remoteInspectionReadMethods), true);
    });

    test('answers only the window that opened a session', () async {
      final session = await open(window: '7');
      expect(
        await send(
          'read',
          readOf(session, 'repositorySessionTree'),
          window: '8',
        ),
        {'failure': 'unknownSession'},
      );
      expect(
        await send('read', readOf(BigInt.from(4242), 'repositorySessionTree')),
        {'failure': 'unknownSession'},
      );
      // Another window cannot close it either.
      await send('close', {
        'session': '$session',
        'generation': '5',
      }, window: '8');
      expect(reads.closed, isEmpty);
    });

    test('refuses a host that is not connected', () async {
      directory.withdraw(_authority);
      expect(
        await send('open', {
          'repository': {
            'units': _repository.units.toList(),
            'remote': _authority.toMessage(),
          },
          'generation': '5',
        }),
        {'failure': 'remoteDisconnected'},
      );
      expect(reads.opened, isEmpty);
    });

    test('drops the sessions of a connection that is gone', () async {
      final session = await open();
      live = false;
      expect(await send('read', readOf(session, 'repositorySessionTree')), {
        'failure': 'remoteDisconnected',
      });
      expect(service.sessionCount, 0);
      // A reconnect is a new connection: the old session does not exist
      // on it.
      live = true;
      directory.publish(_authority, _Surface(_Reads()), live: () => true);
      expect(await send('read', readOf(session, 'repositorySessionTree')), {
        'failure': 'unknownSession',
      });
    });

    test('closes a session opened while the connection went away', () async {
      reads.gate = Completer();
      final opening = send('open', {
        'repository': {
          'units': _repository.units.toList(),
          'remote': _authority.toMessage(),
        },
        'generation': '5',
      });
      await Future<void>.delayed(Duration.zero);
      directory.withdraw(_authority);
      reads.gate!.complete();
      expect(await opening, {'failure': 'remoteDisconnected'});
      expect(reads.closed, reads.opened);
      expect(service.sessionCount, 0);
    });

    test('closes the sessions of a window that closed', () async {
      final kept = await open(window: '7');
      final gone = await open(window: '8');
      host.windows.add({'0', '7'});
      await Future<void>.delayed(Duration.zero);
      expect(reads.closed, [gone]);
      expect(service.sessionCount, 1);
      expect((await send('read', readOf(kept, 'repositorySessionTree'))).keys, [
        'result',
      ]);
    });

    test('bounds the sessions of one window', () async {
      for (var index = 0; index < remoteInspectionSessionsPerWindow; index++) {
        await open();
      }
      expect(
        await send('open', {
          'repository': {
            'units': _repository.units.toList(),
            'remote': _authority.toMessage(),
          },
          'generation': '5',
        }),
        {'failure': 'capacity'},
      );
    });

    test('closes every session when it shuts down', () async {
      final first = await open(window: '7');
      final second = await open(window: '8');
      await service.dispose();
      expect(reads.closed, unorderedEquals([first, second]));
      expect(host.disposed, 1);
      expect(await send('read', readOf(first, 'repositorySessionTree')), {
        'failure': 'closed',
      });
    });

    test('still starts when windows cannot reach it', () async {
      final failing = _Host()..failServe = true;
      final other = RemoteInspectionHostService(
        failing,
        (authority) => directory.surfaceFor(authority)?.detachedReads,
      );
      await other.initialize();
      await other.dispose();
      expect(failing.disposed, 1);
    });

    test('a failure crosses the channel as its code only', () async {
      final session = await open();
      reads.failure = StateError('/home/someone/secret.txt: token=abc');
      final text = await NativeRemoteInspectionHostRepository.answer(
        service,
        MethodCall(
          'read',
          jsonEncode({
            'schema': 1,
            'window': '7',
            ...readOf(session, 'repositorySessionTree'),
          }),
        ),
      );
      expect(text, '{"failure":"read"}');
      reads.failure = const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.pathNotFound),
      );
      expect(await send('read', readOf(session, 'repositorySessionTree')), {
        'failure': 'pathNotFound',
      });
    });

    test('rejects malformed requests', () async {
      Future<String> raw(String method, Object? arguments) =>
          NativeRemoteInspectionHostRepository.answer(
            service,
            MethodCall(method, arguments),
          );
      const invalid = '{"failure":"invalidOptions"}';
      expect(await raw('open', null), invalid);
      expect(await raw('open', 42), invalid);
      expect(await raw('open', '{'), invalid);
      expect(await raw('open', '{"schema":2,"window":"7"}'), invalid);
      expect(await raw('open', '{"schema":1,"window":""}'), invalid);
      expect(await raw('unknown', '{"schema":1,"window":"7"}'), invalid);
      // A local path is never opened through a connection.
      expect(
        await raw(
          'open',
          jsonEncode({
            'schema': 1,
            'window': '7',
            'repository': {'units': _repository.units.toList()},
            'generation': '5',
          }),
        ),
        invalid,
      );
      expect(
        await raw(
          'open',
          jsonEncode({
            'schema': 1,
            'window': '7',
            'repository': {
              'units': 'relative'.codeUnits,
              'remote': _authority.toMessage(),
            },
            'generation': '5',
          }),
        ),
        invalid,
      );
      expect(
        await raw(
          'read',
          jsonEncode({
            'schema': 1,
            'window': '7',
            'session': '-1',
            'method': 'repositorySessionTree',
            'arguments': <String, Object?>{},
          }),
        ),
        invalid,
      );
      expect(reads.opened, isEmpty);
    });
  });

  group('an inspector window', () {
    InspectorWindowSession windowSession(_Direct transport) =>
        InspectorWindowSession(
          remoteInspectionSession(_authority, transport: transport),
          InspectionWindowRequest(
            repository: _repository,
            location: const InspectorLocation(target: CommitTarget(_commit)),
          ),
        );

    test('opens, reads and closes through the main window', () async {
      final transport = _Direct(service);
      final session = windowSession(transport);
      await session.initialize();
      expect(session.failed, isFalse);
      expect(reads.opened, hasLength(1));
      // The inspector read its commit through the session it opened.
      expect(reads.reads.first.session, reads.opened.single);
      expect(reads.reads.first.method, 'repositorySessionCommitInspection');
      // The window names itself and the authority, never a local path.
      final open = jsonDecode(transport.payloads.first) as Map;
      expect(open['window'], '7');
      expect((open['repository'] as Map)['remote'], _authority.toMessage());
      await session.close();
      expect(reads.closed, reads.opened);
      expect(service.sessionCount, 0);
    });

    test('reports a host the main window is not connected to', () async {
      directory.withdraw(_authority);
      final session = windowSession(_Direct(service));
      await session.initialize();
      expect(session.failed, isTrue);
      expect(session.failure, RepositoryFailureCode.remoteDisconnected);
      await session.close();
    });

    test('reports a main window that does not answer', () async {
      final session = windowSession(_Direct(null));
      await session.initialize();
      expect(session.failure, RepositoryFailureCode.remoteDisconnected);
      await session.close();
    });

    test('retries once the host is connected', () async {
      directory.withdraw(_authority);
      final session = windowSession(_Direct(service));
      await session.initialize();
      expect(session.failed, isTrue);
      directory.publish(_authority, surface, live: () => true);
      await session.retry();
      expect(session.failed, isFalse);
      expect(reads.opened, hasLength(1));
      await session.close();
      expect(reads.closed, reads.opened);
    });

    test('sends no write to the main window', () async {
      final transport = _Direct(service);
      final calls = WindowRemoteInspectionCalls(
        transport,
        authority: _authority,
      );
      await expectLater(
        calls.repositorySessionRestorePreview(
          sessionId: BigInt.one,
          generation: BigInt.one,
          commit: _commit,
          path: const [97],
          byteLimit: 1,
        ),
        throwsA(
          isA<RepositorySessionException>().having(
            (error) => error.failure.code,
            'code',
            RepositoryFailureCode.remoteNotOffered,
          ),
        ),
      );
      expect(transport.payloads, isEmpty);
    });
  });
}
