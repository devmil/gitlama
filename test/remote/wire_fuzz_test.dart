import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/remote/frame_codec.dart';
import 'package:gitlama/repositories/impl/remote/wire_json.dart';
import 'package:gitlama/repositories/impl/remote/wire_values.dart';
import 'package:gitlama/repositories/impl/repository_session_calls.g.dart';

/// Seeded, bounded mutation fuzzing of the client's parsers. Every failure
/// must be a [WireFormatException]; no other exception may escape.
const _seed = 0x5eed6175;
const _iterations = 20000;

final class _XorShift {
  _XorShift(this._state);
  int _state;

  int next() {
    _state ^= (_state << 13) & 0xffffffff;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xffffffff;
    return _state & 0x7fffffff;
  }

  int below(int bound) => bound <= 0 ? 0 : next() % bound;
}

final _corpus = [
  '{"protocolMajor":1,"connectionNonce":"00112233445566778899aabbccddeeff","helperIncarnation":"ffeeddccbbaa99887766554433221100","requestId":"7","kind":"result","payload":{"ok":{"events":[],"failure":null}}}',
  '{"events":[{"kind":"snapshot","snapshot":null,"readId":"18446744073709551615","cacheHit":false,"watchOverflowRevision":null}],"failure":null}',
  r'[[[[{"a":[1,2,3],"b":"\u00e9\ud83d\ude00"}]]]]',
].map((text) => Uint8List.fromList(utf8.encode(text))).toList();

const _tokens = [
  '"',
  '{',
  '}',
  '[',
  ']',
  ',',
  ':',
  r'\u',
  '-0',
  '1e9',
  '1.5',
  '"a":1,"a":2',
];

Uint8List _mutate(_XorShift random, Uint8List input) {
  var bytes = List<int>.of(input);
  for (var round = 0; round <= random.below(4); round += 1) {
    switch (random.below(6)) {
      case 0 when bytes.isNotEmpty:
        final index = random.below(bytes.length);
        bytes[index] ^= 1 << random.below(8);
      case 1 when bytes.isNotEmpty:
        bytes = bytes.sublist(0, random.below(bytes.length));
      case 2:
        final index = random.below(bytes.length + 1);
        final token = _tokens[random.below(_tokens.length)];
        bytes.insertAll(index, utf8.encode(token));
      case 3 when bytes.length > 1:
        final start = random.below(bytes.length);
        final end = (start + random.below(16)).clamp(0, bytes.length);
        bytes.insertAll(random.below(bytes.length), bytes.sublist(start, end));
      case 4:
        bytes = [
          for (var i = 0; i < random.below(64); i += 1) random.below(256),
        ];
      default:
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  test('strict JSON and generated decoders fail only with typed errors', () {
    final random = _XorShift(_seed);
    var parsed = 0;
    var rejected = 0;
    for (var iteration = 0; iteration < _iterations; iteration += 1) {
      final input = _mutate(random, _corpus[iteration % _corpus.length]);
      try {
        final value = parseWireJson(input, WireParseLimits.frame);
        parsed += 1;
        for (final decode in <void Function(Object?)>[
          decodeNativeRepositoryEventsResult,
          decodeNativeHistoryResult,
          readWireBig,
          readWireBytes,
        ]) {
          try {
            decode(value);
          } on WireFormatException {
            // Expected for arbitrary values.
          }
        }
        expect(
          parseWireJson(encodeWireJson(value), WireParseLimits.frame),
          equals(value),
        );
      } on WireFormatException {
        rejected += 1;
      }
    }
    expect(parsed + rejected, _iterations);
    expect(parsed, greaterThan(0));
    expect(rejected, greaterThan(0));
  });

  test('random frame streams and splits never change decoded frames', () {
    final random = _XorShift(_seed + 1);
    for (var iteration = 0; iteration < 2000; iteration += 1) {
      final frames = [
        for (var index = 0; index < 1 + random.below(4); index += 1)
          Uint8List.fromList([
            for (var byte = 0; byte < 1 + random.below(300); byte += 1)
              random.below(256),
          ]),
      ];
      final stream = [for (final frame in frames) ...encodeFrame(frame)];
      final decoder = FrameDecoder(maxFrameBytes: 1024, onDeadline: () {});
      final decoded = <Uint8List>[];
      var offset = 0;
      while (offset < stream.length) {
        final end = (offset + 1 + random.below(64)).clamp(0, stream.length);
        decoder.add(stream.sublist(offset, end));
        offset = end;
        for (
          var frame = decoder.next();
          frame != null;
          frame = decoder.next()
        ) {
          decoded.add(frame);
        }
      }
      expect(decoded, frames);
      expect(decoder.idle, isTrue);
      decoder.close();
    }
  });
}
