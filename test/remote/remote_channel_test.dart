import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/impl/remote/remote_channel_impl.dart';
import 'package:gitlama/repositories/impl/remote/wire_json.dart';
import 'package:gitlama/repositories/remote_connection_repository.dart';

import 'support/fake_remote_process.dart';
import 'support/fake_timers.dart';

Future<Object?> _inline(Object? Function() work) async => work();

Matcher _callFails(RemoteErrorCode code) =>
    throwsA(isA<RemoteCallException>().having((e) => e.code, 'code', code));

void main() {
  late FakeTimers timers;
  late FakeRemoteProcess helper;

  setUp(() {
    timers = FakeTimers();
    helper = FakeRemoteProcess();
  });

  Future<RemoteChannelImpl> connect({
    Future<void>? cancel,
    RemoteOffload offload = _inline,
    Set<RemoteCapability> capabilities = const {
      RemoteCapability.read,
      RemoteCapability.listDirectory,
    },
  }) => RemoteChannelImpl.connect(
    process: helper,
    buildId: testBuildId,
    capabilities: capabilities,
    cancel: cancel,
    timer: timers.call,
    offload: offload,
    random: Random(1),
  );

  Future<RemoteFailureCode> handshakeFailure(
    void Function() script, {
    Future<void>? cancel,
    void Function(RemoteWorkspaceException error)? onError,
  }) async {
    final future = connect(cancel: cancel);
    script();
    try {
      await future;
    } on RemoteWorkspaceException catch (error) {
      onError?.call(error);
      return error.code;
    }
    fail('handshake succeeded');
  }

  Future<RemoteChannelImpl> open({RemoteOffload offload = _inline}) async {
    final future = connect(offload: offload);
    helper.emitJson(helloJson());
    return future;
  }

  group('bootstrap', () {
    test('bannerIsNotProtocol', () async {
      final code = await handshakeFailure(() {
        helper.emit(utf8.encode('Last login: Mon\n'));
        helper.emitJson(helloJson());
      });
      expect(code, RemoteFailureCode.bootstrapFailed);
      await settle();
      expect(helper.sentOf('helloAck'), isEmpty);
      expect(helper.terminateCalls, 1);
    });

    test('missing helper sentinel then EOF names the host platform', () async {
      Object? error;
      final code = await handshakeFailure(() {
        helper.emit(utf8.encode('GITLAMA-BOOTSTRAP 1 '));
        helper.emit(utf8.encode('missing Darwin/arm64\n'));
        helper.exit(3);
      }, onError: (failure) => error = failure);
      expect(code, RemoteFailureCode.helperNotInstalled);
      expect(
        (error as RemoteWorkspaceException?)?.hostTarget,
        RemoteHelperTarget.macosArm64,
      );
    });

    test('platform sentinel then EOF', () async {
      final code = await handshakeFailure(() {
        helper.emit(utf8.encode('GITLAMA-BOOTSTRAP 1 platform\n'));
        helper.exit(3);
      });
      expect(code, RemoteFailureCode.unsupportedPlatform);
    });

    test('exit 255 before hello is a connection failure', () async {
      final code = await handshakeFailure(() => helper.exit(255));
      expect(code, RemoteFailureCode.sshConnectionFailed);
    });

    test('other exit before hello is a bootstrap failure', () async {
      final code = await handshakeFailure(() => helper.exit(127));
      expect(code, RemoteFailureCode.bootstrapFailed);
    });

    test('hello deadline', () async {
      final code = await handshakeFailure(
        () => timers.elapse(remoteHelloDeadline),
      );
      expect(code, RemoteFailureCode.handshakeTimeout);
    });

    test('oversized hello frame', () async {
      final code = await handshakeFailure(
        () => helper.emit([0, 1, 0, 1]), // 65537 bytes declared
      );
      expect(code, RemoteFailureCode.bootstrapFailed);
    });

    test('hello validation failures surface their code', () async {
      final code = await handshakeFailure(
        () => helper.emitJson(helloJson(overrides: {'buildId': 'e' * 40})),
      );
      expect(code, RemoteFailureCode.buildMismatch);
      expect(helper.sentOf('helloAck'), isEmpty);
    });

    test('cancel before hello terminates the process', () async {
      final cancel = Completer<void>();
      final code = await handshakeFailure(
        cancel.complete,
        cancel: cancel.future,
      );
      expect(code, RemoteFailureCode.canceled);
      await settle();
      expect(helper.terminateCalls, 1);
    });
  });

  test('handshake sends the acknowledgement and negotiates', () async {
    final channel = await open();
    expect(channel.isOpen, isTrue);
    expect(channel.helper.capabilities, {
      RemoteCapability.read,
      RemoteCapability.listDirectory,
    });
    expect(helper.sent, hasLength(1));
    final ack = helper.ack;
    expect(ack['buildId'], testBuildId);
    expect(ack['helperIncarnation'], testIncarnation);
    expect(ack['capabilities'], ['read', 'listDirectory']);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(helper.nonce), isTrue);
    expect(channel.callCapacity, 28);
  });

  test('calls complete with ok values and helper errors', () async {
    final channel = await open();
    final first = channel.call('listDirectory', {'directory': null});
    final second = expectLater(
      channel.call('openRepository', {'path': 'AA=='}),
      _callFails(RemoteErrorCode.pathNotFound),
    );
    final calls = helper.sentOf('call');
    expect(calls.map((c) => c['requestId']), ['1', '2']);
    expect(calls.first['payload'], {
      'method': 'listDirectory',
      'args': {'directory': null},
    });
    expect(calls.first['connectionNonce'], helper.nonce);
    helper.emitEnvelope('result', 2, {
      'error': {'code': 'pathNotFound'},
    });
    helper.emitResult(1, {'entries': <Object?>[]});
    expect(await first, {'entries': <Object?>[]});
    await second;
  });

  test('replyCannotCompleteDifferentGeneration', () async {
    final channel = await open();
    final timedOut = channel.call('a', const {});
    timers.elapse(remoteInteractiveDeadline);
    await expectLater(timedOut, _callFails(RemoteErrorCode.timedOut));
    final current = channel.call('b', const {});
    // A late result for the retired request is ignored, not given to b.
    helper.emitResult(1, 'late');
    await settle();
    expect(channel.isOpen, isTrue);
    final currentId = helper.sentOf('call').last['requestId']!;
    helper.emitResult(currentId, 'mine');
    expect(await current, 'mine');
    // A duplicate result for a completed request is ignored too.
    helper.emitResult(currentId, 'again');
    await settle();
    expect(channel.isOpen, isTrue);
  });

  test('a result for a never-issued id is a protocol violation', () async {
    final channel = await open();
    helper.emitResult(99, 'x');
    expect(await channel.closed, RemoteFailureCode.protocolViolation);
    expect(helper.terminateCalls, 1);
  });

  test('deadline completes timedOut and sends cancel', () async {
    final channel = await open();
    final bulk = expectLater(
      channel.call('repositorySessionHistoryQuery', const {}, bulk: true),
      _callFails(RemoteErrorCode.timedOut),
    );
    // Answer every ping so liveness does not close the channel first.
    Future<void> keepAlive(Duration total) async {
      for (var step = Duration.zero; step < total; step += remotePingInterval) {
        timers.elapse(remotePingInterval);
        helper.emitEnvelope(
          'pong',
          helper.sentOf('ping').last['requestId']!,
          {},
        );
        await settle();
      }
    }

    await keepAlive(remoteInteractiveDeadline);
    expect(helper.sentOf('cancel'), isEmpty);
    expect(channel.isOpen, isTrue);
    await keepAlive(remoteBulkDeadline - remoteInteractiveDeadline);
    await bulk;
    final cancel = helper.sentOf('cancel').single;
    expect(cancel['payload'], {'target': '1'});
    final ids = helper.sent
        .skip(1)
        .map((m) => int.parse(m['requestId']! as String));
    expect(ids.toList(), [for (var i = 1; i <= ids.length; i += 1) i]);
    expect(channel.isOpen, isTrue);
  });

  test('capacity limit', () async {
    final channel = await open();
    final calls = [for (var i = 0; i < 28; i += 1) channel.call('m', const {})];
    await expectLater(
      channel.call('m', const {}),
      _callFails(RemoteErrorCode.capacity),
    );
    helper.emitResult(1, null);
    await calls.first;
    expect(channel.call('m', const {}), completion(isNull));
    helper.emitResult(29, null);
    await settle();
    timers.elapse(remoteInteractiveDeadline);
    for (final call in calls.skip(1)) {
      await expectLater(call, _callFails(RemoteErrorCode.timedOut));
    }
  });

  test('disconnect completes all pending exactly once', () async {
    final channel = await open();
    final outcomes = <Object>[];
    final calls = [
      for (var i = 0; i < 3; i += 1)
        channel
            .call('m', const {})
            .then<void>(
              (v) => outcomes.add(v ?? 'null'),
              onError: (Object e) => outcomes.add(e),
            ),
    ];
    helper.exit(0);
    await Future.wait(calls);
    expect(outcomes, hasLength(3));
    expect(
      outcomes,
      everyElement(
        isA<RemoteCallException>().having(
          (e) => e.code,
          'code',
          RemoteErrorCode.disconnected,
        ),
      ),
    );
    expect(await channel.closed, RemoteFailureCode.disconnected);
    // Late timers and results after disconnect change nothing.
    timers.elapse(const Duration(minutes: 5));
    await settle();
    expect(outcomes, hasLength(3));
    await expectLater(
      channel.call('m', const {}),
      _callFails(RemoteErrorCode.disconnected),
    );
  });

  test('ping every 15 s and liveness close after 45 s of silence', () async {
    final channel = await open();
    timers.elapse(remotePingInterval);
    expect(helper.sentOf('ping'), hasLength(1));
    helper.emitEnvelope('pong', helper.sentOf('ping').single['requestId']!, {});
    await settle();
    timers.elapse(const Duration(seconds: 44));
    expect(channel.isOpen, isTrue);
    expect(helper.sentOf('ping').length, greaterThanOrEqualTo(3));
    timers.elapse(const Duration(seconds: 1));
    expect(channel.isOpen, isFalse);
    expect(await channel.closed, RemoteFailureCode.disconnected);
    await settle();
    expect(helper.terminateCalls, 1);
  });

  test('close() sends shutdown, waits for goodbye, then terminates', () async {
    final channel = await open();
    final pending = channel.call('m', const {});
    final closing = channel.close();
    expect(channel.isOpen, isFalse);
    expect(await channel.closed, isNull);
    await expectLater(pending, _callFails(RemoteErrorCode.disconnected));
    final shutdown = helper.sentOf('shutdown').single;
    expect(helper.terminateCalls, 0);
    helper.emitEnvelope('goodbye', shutdown['requestId']!, {});
    await closing;
    expect(helper.terminateCalls, greaterThanOrEqualTo(1));
    expect(identical(channel.close(), channel.close()), isTrue);
  });

  test('close() is bounded when the helper never answers', () async {
    final channel = await open();
    var done = false;
    unawaited(channel.close().then((_) => done = true));
    await settle();
    expect(done, isFalse);
    timers.elapse(remoteShutdownGrace);
    await settle();
    expect(done, isTrue);
    expect(helper.terminateCalls, greaterThanOrEqualTo(1));
  });

  group('protocol violations close the channel', () {
    final cases = <String, void Function(FakeRemoteProcess helper)>{
      'wrong nonce': (h) => h.emitEnvelope('pong', 1, {}, nonce: 'f' * 32),
      'wrong incarnation': (h) =>
          h.emitJson(h.envelope('pong', 1, {}, incarnation: 'e' * 32)),
      'wrong major': (h) => h.emitJson(h.envelope('pong', 1, {}, major: 2)),
      'unknown kind': (h) => h.emitEnvelope('surprise', 0, {}),
      'result id 0': (h) => h.emitResult(0, 1),
      'not json': (h) => h.emit([0, 0, 0, 2, 0x7b, 0x7b]),
      'zero length frame': (h) => h.emit([0, 0, 0, 0]),
      'malformed chunk': (h) => h.emitEnvelope('chunk', 0, {'transaction': 1}),
    };
    for (final MapEntry(key: name, value: script) in cases.entries) {
      test(name, () async {
        final channel = await open();
        channel.call('m', const {}).ignore();
        script(helper);
        expect(await channel.closed, RemoteFailureCode.protocolViolation);
        expect(channel.isOpen, isFalse);
        await settle();
        expect(helper.terminateCalls, 1);
      });
    }

    test('decreasing publication sequence', () async {
      final channel = await open();
      final received = <RemotePublication>[];
      channel.publications.listen(received.add);
      void publish(String sequence) => helper.emitEnvelope('publication', 0, {
        'sequence': sequence,
        'type': 'sessionEvents',
        'sessionId': '7',
        'events': {'events': <Object?>[]},
      });
      publish('2');
      publish('1');
      expect(await channel.closed, RemoteFailureCode.protocolViolation);
      expect(received, hasLength(1));
      expect(received.single.sessionId, BigInt.from(7));
    });

    test('partial frame deadline', () async {
      final channel = await open();
      helper.emit([0, 0, 0, 10, 1]);
      await settle();
      timers.elapse(const Duration(seconds: 15));
      expect(await channel.closed, RemoteFailureCode.protocolViolation);
    });
  });

  test('fatal from the helper closes with its code', () async {
    final channel = await open();
    helper.emitEnvelope('fatal', 0, {'code': 'handshakeTimeout'});
    expect(await channel.closed, RemoteFailureCode.handshakeTimeout);
  });

  test('chunked results reassemble; partial ones never complete', () async {
    final channel = await open();
    final big = channel.call('m', const {});
    final other = channel.call('n', const {});
    final innerBig = encodeWireJson(
      helper.envelope('result', 1, {'ok': 'x' * 5000}),
    );
    final innerOther = encodeWireJson(
      helper.envelope('result', 2, {'ok': 'y'}),
    );
    final a = helper.chunks(innerBig, transaction: 1, requestId: 1, parts: 3);
    final b = helper.chunks(innerOther, transaction: 2, requestId: 2);
    var bigDone = false;
    unawaited(big.then((_) => bigDone = true));
    helper.emitJson(a[0]);
    helper.emitJson(b[0]);
    helper.emitJson(a[1]);
    helper.emitJson(b[1]);
    expect(await other, 'y');
    expect(bigDone, isFalse);
    helper.emitJson(a[2]);
    expect(await big, 'x' * 5000);
  });

  test('disconnect mid-transaction never presents it', () async {
    final channel = await open();
    final call = channel.call('m', const {});
    final inner = encodeWireJson(helper.envelope('result', 1, {'ok': 1}));
    helper.emitJson(helper.chunks(inner, transaction: 1, requestId: 1)[0]);
    helper.exit(0);
    await expectLater(call, _callFails(RemoteErrorCode.disconnected));
  });

  test('large frames and transactions decode on a worker isolate', () async {
    final channel = await open(offload: isolateOffload);
    final large = channel.call('m', const {});
    final text = 'z' * (300 * 1024);
    helper.emitResult(1, text);
    expect(await large, text);
    final chunked = channel.call('n', const {});
    final inner = encodeWireJson(helper.envelope('result', 2, {'ok': text}));
    for (final chunk in helper.chunks(inner, transaction: 1, requestId: 2)) {
      helper.emitJson(chunk);
    }
    expect(await chunked, text);
    // A small frame queued behind an offloaded one keeps its order.
    final small = channel.call('o', const {});
    helper.emitResult(3, 's');
    expect(await small, 's');
  });
}
