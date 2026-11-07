import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/remote/protocol_messages.dart';
import 'package:gitlama/repositories/impl/remote/transaction_assembler.dart';
import 'package:gitlama/repositories/impl/remote/wire_json.dart';
import 'package:gitlama/repositories/impl/remote/wire_values.dart';

import 'support/fake_remote_process.dart';

void main() {
  late FakeRemoteProcess helper;
  late EnvelopeSession session;
  late TransactionAssembler assembler;

  const nonce = 'abcdefabcdefabcdefabcdefabcdefab';

  setUp(() {
    helper = FakeRemoteProcess();
    // The fake builds envelopes with the nonce of a recorded acknowledgement.
    helper.sent.add({'kind': 'helloAck', 'connectionNonce': nonce});
    session = EnvelopeSession(nonce: nonce, incarnation: testIncarnation);
    for (var i = 0; i < 5; i += 1) {
      session.nextRequestId();
    }
    assembler = TransactionAssembler();
  });

  Uint8List inner(Object requestId, Object? ok) =>
      encodeWireJson(helper.envelope('result', requestId, {'ok': ok}));

  CompletedTransaction? feed(Map<String, Object?> chunk) =>
      assembler.add(session.read(chunk) as ChunkMessage);

  Object? complete(List<Map<String, Object?>> chunks) {
    CompletedTransaction? done;
    for (final chunk in chunks) {
      expect(done, isNull);
      done = feed(chunk);
    }
    expect(done, isNotNull);
    final message = session.read(
      decodeTransaction(done!),
      carried: done.requestId,
    );
    return (message as ResultMessage).ok;
  }

  test('reassembles a result across chunks', () {
    final chunks = helper.chunks(
      inner(3, 'x' * 1000),
      transaction: 1,
      requestId: 3,
      parts: 4,
    );
    expect(complete(chunks), 'x' * 1000);
    expect(assembler.assembling, 0);
  });

  test('interleaved transactions', () {
    final a = helper.chunks(inner(1, 'a'), transaction: 1, requestId: 1);
    final b = helper.chunks(inner(2, 'b'), transaction: 2, requestId: 2);
    expect(feed(a[0]), isNull);
    expect(feed(b[0]), isNull);
    expect(assembler.assembling, 2);
    final doneB = feed(b[1])!;
    final doneA = feed(a[1])!;
    expect(doneA.requestId, BigInt.one);
    expect(doneB.requestId, BigInt.two);
  });

  group('transactionDoesNotPublishPartial', () {
    void rejects(List<Map<String, Object?>> chunks) {
      expect(() {
        for (final chunk in chunks) {
          final done = feed(chunk);
          if (done != null) {
            session.read(decodeTransaction(done), carried: done.requestId);
          }
        }
      }, throwsA(isA<WireFormatException>()));
    }

    test('missing first chunk', () {
      final chunks = helper.chunks(inner(1, 1), transaction: 1, requestId: 1);
      rejects([chunks[1]]);
    });

    test('duplicate chunk', () {
      final chunks = helper.chunks(
        inner(1, 1),
        transaction: 1,
        requestId: 1,
        parts: 3,
      );
      rejects([chunks[0], chunks[0]]);
    });

    test('out of order chunk', () {
      final chunks = helper.chunks(
        inner(1, 'abcdefgh'),
        transaction: 1,
        requestId: 1,
        parts: 3,
      );
      rejects([chunks[0], chunks[2], chunks[1]]);
    });

    test('wrong digest', () {
      rejects(
        helper.chunks(
          inner(1, 1),
          transaction: 1,
          requestId: 1,
          digest: 'a' * 64,
        ),
      );
    });

    test('wrong totalBytes', () {
      final bytes = inner(1, 1);
      rejects(
        helper.chunks(
          bytes,
          transaction: 1,
          requestId: 1,
          totalBytes: bytes.length + 1,
        ),
      );
      assembler.discard();
      rejects(
        helper.chunks(
          bytes,
          transaction: 2,
          requestId: 1,
          totalBytes: bytes.length - 1,
        ),
      );
    });

    test('inner request id differs from the chunks', () {
      rejects(helper.chunks(inner(2, 1), transaction: 1, requestId: 1));
    });

    test('mismatched header across chunks', () {
      final a = helper.chunks(inner(1, 1), transaction: 1, requestId: 1);
      final b = helper.chunks(inner(2, 22), transaction: 1, requestId: 2);
      rejects([a[0], b[1]]);
    });

    test('reused or decreasing transaction id', () {
      final first = helper.chunks(inner(1, 1), transaction: 2, requestId: 1);
      expect(feed(first[0]), isNull);
      expect(feed(first[1]), isNotNull);
      rejects(helper.chunks(inner(1, 1), transaction: 2, requestId: 1));
      rejects(helper.chunks(inner(1, 1), transaction: 1, requestId: 1));
    });

    test('chunk counts outside 2..16', () {
      rejects(
        helper.chunks(inner(1, 1), transaction: 1, requestId: 1, parts: 1),
      );
      assembler = TransactionAssembler();
      rejects(
        helper.chunks(
          inner(1, 'y' * 100),
          transaction: 1,
          requestId: 1,
          parts: 17,
        ),
      );
    });

    test('more than four assembling transactions', () {
      for (var id = 1; id <= 4; id += 1) {
        expect(
          feed(helper.chunks(inner(1, id), transaction: id, requestId: 1)[0]),
          isNull,
        );
      }
      rejects([helper.chunks(inner(1, 5), transaction: 5, requestId: 1)[0]]);
    });

    test('aggregate declared bytes above 32 MiB', () {
      Map<String, Object?> header(int id) => helper.chunks(
        inner(1, id),
        transaction: id,
        requestId: 1,
        totalBytes: remoteMaxTransactionBytes,
      )[0];
      expect(feed(header(1)), isNull);
      expect(feed(header(2)), isNull);
      rejects([header(3)]);
    });

    test('above the negotiated transaction limit', () {
      assembler = TransactionAssembler(maxTransactionBytes: 10);
      rejects(helper.chunks(inner(1, 'z' * 20), transaction: 1, requestId: 1));
    });

    test('disconnect mid-transaction discards it', () {
      final chunks = helper.chunks(inner(1, 1), transaction: 1, requestId: 1);
      expect(feed(chunks[0]), isNull);
      assembler.discard();
      expect(assembler.assembling, 0);
      rejects([chunks[1]]);
    });
  });
}
