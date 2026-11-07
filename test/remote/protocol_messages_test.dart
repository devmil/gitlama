import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/impl/remote/protocol_messages.dart';
import 'package:gitlama/repositories/impl/remote/wire_json.dart';
import 'package:gitlama/repositories/impl/remote/wire_values.dart';

import 'support/fake_remote_process.dart';

HelloMessage _parse(Object? json, {Set<RemoteCapability>? requested}) =>
    parseHello(
      encodeWireJson(json),
      buildId: testBuildId,
      requested: requested ?? RemoteCapability.values.toSet(),
    );

Matcher _fails(RemoteFailureCode code) => throwsA(
  isA<RemoteWorkspaceException>().having((e) => e.code, 'code', code),
);

void main() {
  group('bootstrap sentinels', () {
    test('missing and platform lines are recognized whole', () {
      for (final MapEntry(key: line, value: sentinel)
          in bootstrapSentinels.entries) {
        final probe = BootstrapProbe();
        for (final byte in ascii.encode(line)) {
          expect(probe.add([byte]), BootstrapState.pending);
        }
        expect(probe.sentinel(), sentinel);
      }
      // Every helper platform has its own missing line.
      expect({
        for (final sentinel in bootstrapSentinels.values) ?sentinel.hostTarget,
      }, RemoteHelperTarget.values.toSet());
    });

    test('a missing helper on an unknown platform is not a sentinel', () {
      final probe = BootstrapProbe()
        ..add(ascii.encode('GITLAMA-BOOTSTRAP 1 missing Linux/riscv64\n'));
      expect(probe.sentinel(), isNull);
    });

    test('a truncated sentinel is not a sentinel', () {
      final probe = BootstrapProbe()
        ..add(ascii.encode('GITLAMA-BOOTSTRAP 1 mis'));
      expect(probe.state, BootstrapState.pending);
      expect(probe.sentinel(), isNull);
    });

    test('bytes after a sentinel fail', () {
      final probe = BootstrapProbe();
      expect(
        probe.add(ascii.encode('GITLAMA-BOOTSTRAP 1 missing Linux/x86_64\nx')),
        BootstrapState.failed,
      );
      expect(probe.sentinel(), isNull);
    });

    test('a banner fails immediately', () {
      expect(
        BootstrapProbe().add(ascii.encode('Welcome to host\n')),
        BootstrapState.failed,
      );
    });

    test('a zero first byte selects frame decoding', () {
      expect(BootstrapProbe().add([0, 0, 1, 0]), BootstrapState.frames);
    });
  });

  group('hello validation', () {
    test('accepts a valid hello and negotiates', () {
      final hello = _parse(
        helloJson(
          limits: {
            'frameBytes': '1048576',
            'transactionBytes': '99999999999999',
            'requestsPerConnection': '16',
            // A helper from before the limit was raised.
            'sessionsPerConnection': '8',
          },
          overrides: {
            'capabilities': ['read', 'futureThing', 'listDirectory'],
          },
        ),
        requested: {RemoteCapability.read, RemoteCapability.stage},
      );
      expect(hello.info.buildId, testBuildId);
      expect(hello.info.incarnation, testIncarnation);
      expect(hello.info.storeId, testStoreId);
      expect(hello.info.accountUid, '1000');
      expect(hello.info.accountName, 'alice');
      expect(hello.info.gitVersion, '2.43.0');
      expect(hello.info.capabilities, {RemoteCapability.read});
      expect(hello.offered, {
        RemoteCapability.read,
        RemoteCapability.listDirectory,
      });
      expect(hello.limits.frameBytes, 1048576);
      expect(hello.limits.transactionBytes, 16777216);
      expect(hello.limits.requestsPerConnection, 16);
      expect(hello.limits.sessionsPerConnection, 8);
    });

    test('wrong build', () {
      expect(
        () => _parse(helloJson(overrides: {'buildId': 'f' * 40})),
        _fails(RemoteFailureCode.buildMismatch),
      );
    });

    test('wrong major', () {
      expect(
        () => _parse(helloJson(overrides: {'protocolMajor': 2})),
        _fails(RemoteFailureCode.protocolMismatch),
      );
    });

    test('wrong magic', () {
      expect(
        () => _parse(helloJson(overrides: {'magic': 'other'})),
        _fails(RemoteFailureCode.bootstrapFailed),
      );
    });

    test('missing and unsupported git', () {
      expect(
        () => _parse(
          helloJson(overrides: {'gitState': 'missing', 'gitVersion': null}),
        ),
        _fails(RemoteFailureCode.gitMissing),
      );
      expect(
        () => _parse(
          helloJson(
            overrides: {'gitState': 'unsupported', 'gitVersion': '2.20.0'},
          ),
        ),
        _fails(RemoteFailureCode.gitUnsupported),
      );
    });

    test('store unavailable', () {
      expect(
        () => _parse(
          helloJson(
            overrides: {
              'store': {'state': 'unavailable', 'storeId': null},
            },
          ),
        ),
        _fails(RemoteFailureCode.storeUnavailable),
      );
    });

    test('malformed hellos are bootstrap failures', () {
      final cases = <Map<String, Object?>>[
        {...helloJson()..remove('platform')},
        helloJson(overrides: {'extra': 1}),
        helloJson(overrides: {'helperIncarnation': 'ABC'}),
        helloJson(overrides: {'buildId': 'ABCDEF' * 6 + 'abcd'}),
        helloJson(overrides: {'gitState': 'maybe'}),
        helloJson(
          overrides: {
            'store': {'state': 'ready', 'storeId': null},
          },
        ),
        helloJson(
          overrides: {
            'account': {'uid': '01', 'name': 'x'},
          },
        ),
        helloJson(
          overrides: {
            'account': {'uid': '1', 'name': 'x' * 129},
          },
        ),
        helloJson(
          limits: {
            'frameBytes': '0',
            'transactionBytes': '1',
            'requestsPerConnection': '1',
            'sessionsPerConnection': '1',
          },
        ),
        helloJson(
          limits: {
            'frameBytes': 4194304,
            'transactionBytes': '1',
            'requestsPerConnection': '1',
            'sessionsPerConnection': '1',
          },
        ),
      ];
      for (final json in cases) {
        expect(() => _parse(json), _fails(RemoteFailureCode.bootstrapFailed));
      }
      expect(
        () => parseHello(
          utf8.encode('{"kind":"hello"'),
          buildId: testBuildId,
          requested: const {},
        ),
        _fails(RemoteFailureCode.bootstrapFailed),
      );
    });
  });

  test('helloAck contents', () {
    final hello = _parse(
      helloJson(),
      requested: {RemoteCapability.listDirectory, RemoteCapability.read},
    );
    final nonce = newConnectionNonce(Random(7));
    final ack = buildHelloAck(hello, nonce);
    expect(ack, {
      'kind': 'helloAck',
      'protocolMajor': 1,
      'protocolMinor': 0,
      'buildId': testBuildId,
      'helperIncarnation': testIncarnation,
      'connectionNonce': nonce,
      'capabilities': ['read', 'listDirectory'],
    });
    expect(isLowerHex(nonce, 32), isTrue);
    expect(newConnectionNonce(), isNot(newConnectionNonce()));
  });

  group('envelope validation', () {
    const nonce = 'abcdefabcdefabcdefabcdefabcdefab';
    late EnvelopeSession session;
    Map<String, Object?> envelope(
      String kind,
      String requestId,
      Map<String, Object?> payload, {
      String nonce = nonce,
      String incarnation = testIncarnation,
      Object major = 1,
    }) => {
      'protocolMajor': major,
      'connectionNonce': nonce,
      'helperIncarnation': incarnation,
      'requestId': requestId,
      'kind': kind,
      'payload': payload,
    };
    Map<String, Object?> publication(String sequence) =>
        envelope('publication', '0', {
          'sequence': sequence,
          'type': 'sessionEvents',
          'sessionId': '18446744073709551615',
          'events': {'any': true},
        });

    setUp(() {
      session = EnvelopeSession(nonce: nonce, incarnation: testIncarnation);
      session.nextRequestId();
      session.nextRequestId();
    });

    test('client envelopes carry increasing ids from 1', () {
      final fresh = EnvelopeSession(nonce: nonce, incarnation: testIncarnation);
      expect(fresh.nextRequestId(), BigInt.one);
      expect(fresh.nextRequestId(), BigInt.two);
      expect(fresh.envelope(BigInt.two, 'ping', const {}), {
        'protocolMajor': 1,
        'connectionNonce': nonce,
        'helperIncarnation': testIncarnation,
        'requestId': '2',
        'kind': 'ping',
        'payload': <String, Object?>{},
      });
    });

    test('accepts results, errors and publications', () {
      final ok = session.read(envelope('result', '2', {'ok': 5}));
      expect(ok, isA<ResultMessage>().having((m) => m.ok, 'ok', 5));
      final error = session.read(
        envelope('result', '1', {
          'error': {'code': 'pathNotFound'},
        }),
      );
      expect(
        error,
        isA<ResultMessage>().having(
          (m) => m.error,
          'error',
          RemoteErrorCode.pathNotFound,
        ),
      );
      final message = session.read(publication('1')) as PublicationMessage;
      expect(
        message.publication.sessionId,
        BigInt.parse('18446744073709551615'),
      );
      expect(message.publication.events, {'any': true});
    });

    test('rejects wrong identity and shape', () {
      final bad = [
        envelope('result', '1', {'ok': 1}, nonce: 'f' * 32),
        envelope('result', '1', {'ok': 1}, incarnation: 'e' * 32),
        envelope('result', '1', {'ok': 1}, major: 2),
        {
          ...envelope('result', '1', {'ok': 1}),
          'extra': null,
        },
        envelope('result', '0', {'ok': 1}),
        envelope('result', '3', {'ok': 1}),
        envelope('result', '01', {'ok': 1}),
        envelope('result', '1', {'ok': 1, 'error': null}),
        envelope('result', '1', {
          'error': {'code': 'disconnected'},
        }),
        envelope('result', '1', {
          'error': {'code': 'somethingNew'},
        }),
        envelope('publication', '1', {}),
        envelope('pong', '0', {}),
        envelope('pong', '1', {'x': 1}),
        envelope('call', '1', {}),
        envelope('mystery', '1', {}),
      ];
      for (final value in bad) {
        expect(() => session.read(value), throwsA(isA<WireFormatException>()));
      }
    });

    test('publication sequence strictly increases', () {
      session.read(publication('1'));
      session.read(publication('3'));
      expect(
        () => session.read(publication('3')),
        throwsA(isA<WireFormatException>()),
      );
      expect(
        () => session.read(publication('2')),
        throwsA(isA<WireFormatException>()),
      );
      final fresh = EnvelopeSession(nonce: nonce, incarnation: testIncarnation);
      expect(
        () => fresh.read(publication('0')),
        throwsA(isA<WireFormatException>()),
      );
    });

    test('fatal codes map to failures', () {
      final fatal =
          session.read(envelope('fatal', '0', {'code': 'shutdown'}))
              as FatalMessage;
      expect(fatal.code, RemoteFailureCode.disconnected);
      final unknown =
          session.read(envelope('fatal', '0', {'code': '???'})) as FatalMessage;
      expect(unknown.code, RemoteFailureCode.protocolViolation);
    });

    test('carried envelopes must match the transaction', () {
      expect(
        () => session.read(
          envelope('result', '1', {'ok': 1}),
          carried: BigInt.two,
        ),
        throwsA(isA<WireFormatException>()),
      );
      expect(
        () => session.read(envelope('pong', '1', {}), carried: BigInt.one),
        throwsA(isA<WireFormatException>()),
      );
      expect(
        session.read(envelope('result', '2', {'ok': 1}), carried: BigInt.two),
        isA<ResultMessage>(),
      );
    });
  });
}
