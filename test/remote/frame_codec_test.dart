import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/remote/frame_codec.dart';
import 'package:gitlama/repositories/impl/remote/wire_values.dart';

import 'support/fake_timers.dart';

Uint8List _payload(int length, [int seed = 1]) =>
    Uint8List.fromList([for (var i = 0; i < length; i += 1) (i + seed) & 0xff]);

Uint8List _header(int length) {
  final header = Uint8List(4);
  ByteData.sublistView(header).setUint32(0, length, Endian.big);
  return header;
}

List<Uint8List> _drain(FrameDecoder decoder) => [
  for (var frame = decoder.next(); frame != null; frame = decoder.next()) frame,
];

void main() {
  late FakeTimers timers;
  late int deadlines;
  late FrameDecoder decoder;

  setUp(() {
    timers = FakeTimers();
    deadlines = 0;
    decoder = FrameDecoder(
      maxFrameBytes: remoteMaxFrameBytes,
      onDeadline: () => deadlines += 1,
      timer: timers.call,
    );
  });

  test('frameSplitAtEveryByte', () {
    final first = _payload(5);
    final second = _payload(300, 7);
    final bytes = [...encodeFrame(first), ...encodeFrame(second)];
    final frames = <Uint8List>[];
    for (final byte in bytes) {
      decoder.add([byte]);
      frames.addAll(_drain(decoder));
    }
    expect(frames, [first, second]);
    expect(decoder.idle, isTrue);
    expect(timers.active, 0);
  });

  test('multipleFramesOneRead', () {
    final payloads = [_payload(1), _payload(17, 3), _payload(4096, 9)];
    decoder.add([for (final payload in payloads) ...encodeFrame(payload)]);
    expect(_drain(decoder), payloads);
    expect(decoder.idle, isTrue);
  });

  group('rejectBeforeOversizedAllocation', () {
    for (final length in [remoteMaxFrameBytes + 1, 0xffffffff, 0]) {
      test('length $length', () {
        // Only the header arrives: the decision cannot depend on a payload.
        decoder.add(_header(length));
        expect(() => decoder.next(), throwsA(isA<WireFormatException>()));
        expect(timers.active, 0);
      });
    }

    test('respects a lowered limit between frames', () {
      decoder.maxFrameBytes = remoteHelloFrameBytes;
      decoder.add([
        ...encodeFrame(_payload(10)),
        ..._header(remoteHelloFrameBytes + 1),
      ]);
      expect(decoder.next(), hasLength(10));
      expect(() => decoder.next(), throwsA(isA<WireFormatException>()));
    });
  });

  test('partialFrameDeadlineIsAbsolute', () {
    final frame = encodeFrame(_payload(100));
    decoder.add(frame.sublist(0, 2));
    expect(decoder.next(), isNull);
    timers.elapse(const Duration(seconds: 10));
    // Later partial bytes do not extend the deadline.
    decoder.add(frame.sublist(2, 50));
    expect(decoder.next(), isNull);
    timers.elapse(const Duration(seconds: 4, milliseconds: 999));
    expect(deadlines, 0);
    timers.elapse(const Duration(milliseconds: 1));
    expect(deadlines, 1);
    decoder.add(frame.sublist(50));
    expect(decoder.next(), isNull);
  });

  test('a completed frame clears the deadline', () {
    final frame = encodeFrame(_payload(10));
    decoder.add(frame.sublist(0, 3));
    expect(decoder.next(), isNull);
    decoder.add(frame.sublist(3));
    expect(decoder.next(), hasLength(10));
    timers.elapse(const Duration(minutes: 1));
    expect(deadlines, 0);
  });

  test('encodeFrame rejects empty and oversized payloads', () {
    expect(
      () => encodeFrame(Uint8List(0)),
      throwsA(isA<WireFormatException>()),
    );
    expect(
      () => encodeFrame(Uint8List(11), maxFrameBytes: 10),
      throwsA(isA<WireFormatException>()),
    );
    expect(encodeFrame(Uint8List.fromList([7])), [0, 0, 0, 1, 7]);
  });
}
