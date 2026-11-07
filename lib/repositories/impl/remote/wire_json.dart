import 'dart:convert';
import 'dart:typed_data';

import 'wire_values.dart';
import '../../../models/remote_contract.g.dart';

/// Structural bounds for one parsed document.
final class WireParseLimits {
  const WireParseLimits({required this.depth, required this.collection});

  /// One frame: nesting 16, at most 4096 items per array or object.
  static const frame = WireParseLimits(
    depth: ContractLimits.jsonDepth,
    collection: ContractLimits.frameCollection,
  );

  /// A reassembled transaction, already bounded by its total byte ceiling.
  static const transaction = WireParseLimits(
    depth: ContractLimits.jsonDepth,
    collection: ContractLimits.transactionCollection,
  );

  final int depth;
  final int collection;
}

/// Parses UTF-8 JSON strictly: duplicate keys, fractions, exponents, invalid
/// UTF-8, lone surrogates, trailing bytes and excessive nesting or collection
/// sizes are rejected. Objects decode as `Map<String, Object?>` and arrays as
/// `List<Object?>`.
Object? parseWireJson(Uint8List bytes, WireParseLimits limits) {
  final parser = _Parser(bytes, limits);
  final value = parser.value(0);
  parser.whitespace();
  if (parser.offset != bytes.length) {
    throw const WireFormatException('trailing');
  }
  return value;
}

/// Compact UTF-8 JSON for an encoded wire value.
Uint8List encodeWireJson(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

final class _Parser {
  _Parser(this.bytes, this.limits);

  final Uint8List bytes;
  final WireParseLimits limits;
  var offset = 0;

  Never fail(String detail) => throw WireFormatException(detail);

  void whitespace() {
    while (offset < bytes.length) {
      final byte = bytes[offset];
      if (byte != 0x20 && byte != 0x0a && byte != 0x0d && byte != 0x09) {
        return;
      }
      offset += 1;
    }
  }

  int peek() => offset < bytes.length ? bytes[offset] : fail('json');

  Object? value(int depth) {
    whitespace();
    final byte = peek();
    switch (byte) {
      case 0x7b: // {
        return object(depth + 1);
      case 0x5b: // [
        return array(depth + 1);
      case 0x22: // "
        return string();
      case 0x74: // t
        literal('true');
        return true;
      case 0x66: // f
        literal('false');
        return false;
      case 0x6e: // n
        literal('null');
        return null;
      default:
        if (byte == 0x2d || (byte >= 0x30 && byte <= 0x39)) return number();
        fail('json');
    }
  }

  void literal(String text) {
    for (final unit in text.codeUnits) {
      if (peek() != unit) fail('json');
      offset += 1;
    }
  }

  Map<String, Object?> object(int depth) {
    if (depth > limits.depth) fail('depth');
    offset += 1;
    final map = <String, Object?>{};
    whitespace();
    if (peek() == 0x7d) {
      offset += 1;
      return map;
    }
    while (true) {
      whitespace();
      if (peek() != 0x22) fail('json');
      final key = string();
      whitespace();
      if (peek() != 0x3a) fail('json');
      offset += 1;
      if (map.length == limits.collection) fail('collection');
      if (map.containsKey(key)) fail('duplicate key');
      map[key] = value(depth);
      whitespace();
      final next = peek();
      offset += 1;
      if (next == 0x7d) return map;
      if (next != 0x2c) fail('json');
    }
  }

  List<Object?> array(int depth) {
    if (depth > limits.depth) fail('depth');
    offset += 1;
    final list = <Object?>[];
    whitespace();
    if (peek() == 0x5d) {
      offset += 1;
      return list;
    }
    while (true) {
      if (list.length == limits.collection) fail('collection');
      list.add(value(depth));
      whitespace();
      final next = peek();
      offset += 1;
      if (next == 0x5d) return list;
      if (next != 0x2c) fail('json');
    }
  }

  int number() {
    final start = offset;
    if (peek() == 0x2d) offset += 1;
    final first = peek();
    if (first < 0x30 || first > 0x39) fail('json');
    offset += 1;
    if (first != 0x30) {
      while (offset < bytes.length &&
          bytes[offset] >= 0x30 &&
          bytes[offset] <= 0x39) {
        offset += 1;
      }
    }
    if (offset < bytes.length) {
      final next = bytes[offset];
      // The protocol has no fractional or exponent numbers.
      if (next == 0x2e || next == 0x65 || next == 0x45) fail('number');
      if (next >= 0x30 && next <= 0x39) fail('number');
    }
    if (offset - start > 17) fail('number');
    final parsed = int.parse(String.fromCharCodes(bytes, start, offset));
    if (parsed.abs() > 9007199254740992) fail('number');
    return parsed;
  }

  String string() {
    offset += 1;
    final units = <int>[];
    var runStart = offset;
    void flushRun() {
      if (offset > runStart) {
        final String run;
        try {
          run = utf8.decode(
            Uint8List.sublistView(bytes, runStart, offset),
            allowMalformed: false,
          );
        } on FormatException {
          fail('utf8');
        }
        units.addAll(run.codeUnits);
      }
    }

    while (true) {
      final byte = peek();
      if (byte == 0x22) {
        flushRun();
        offset += 1;
        break;
      }
      if (byte < 0x20) fail('json');
      if (byte != 0x5c) {
        offset += 1;
        continue;
      }
      flushRun();
      offset += 1;
      final escape = peek();
      offset += 1;
      switch (escape) {
        case 0x22:
          units.add(0x22);
        case 0x5c:
          units.add(0x5c);
        case 0x2f:
          units.add(0x2f);
        case 0x62:
          units.add(0x08);
        case 0x66:
          units.add(0x0c);
        case 0x6e:
          units.add(0x0a);
        case 0x72:
          units.add(0x0d);
        case 0x74:
          units.add(0x09);
        case 0x75:
          units.add(hex4());
        default:
          fail('json');
      }
      runStart = offset;
    }
    // Lone surrogates are not valid Unicode text.
    for (var index = 0; index < units.length; index += 1) {
      final unit = units[index];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (index + 1 >= units.length ||
            units[index + 1] < 0xdc00 ||
            units[index + 1] > 0xdfff) {
          fail('surrogate');
        }
        index += 1;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        fail('surrogate');
      }
    }
    return String.fromCharCodes(units);
  }

  int hex4() {
    if (offset + 4 > bytes.length) fail('json');
    var value = 0;
    for (var index = 0; index < 4; index += 1) {
      final byte = bytes[offset + index];
      final digit = switch (byte) {
        >= 0x30 && <= 0x39 => byte - 0x30,
        >= 0x41 && <= 0x46 => byte - 0x37,
        >= 0x61 && <= 0x66 => byte - 0x57,
        _ => fail('json'),
      };
      value = value * 16 + digit;
    }
    offset += 4;
    return value;
  }
}
