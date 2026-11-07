import 'dart:convert';
import 'dart:typed_data';

/// A malformed or out-of-contract remote wire value. [detail] is a fixed type
/// or field name, never received content.
final class WireFormatException implements Exception {
  const WireFormatException(this.detail);
  final String detail;

  @override
  String toString() => 'WireFormatException($detail)';
}

final _u64Max = (BigInt.one << 64) - BigInt.one;
final _i64Min = -(BigInt.one << 63);
const _maxSafeInteger = 9007199254740992;

/// Canonical padded base64 of [bytes].
String wireBytes(List<int> bytes) => base64.encode(bytes);

/// Unix bytes or UTF-16 units as base64 of little-endian pairs.
String wireUnits(Uint16List units) {
  final bytes = Uint8List(units.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var index = 0; index < units.length; index += 1) {
    view.setUint16(index * 2, units[index], Endian.little);
  }
  return wireBytes(bytes);
}

List<int> wireInts(Uint32List values) => List<int>.of(values);

/// A 64-bit integer as a canonical decimal string.
String wireBig(BigInt value) => value.toString();

T? wireOptional<T>(Object? value, T Function(Object? value) decode) =>
    value == null ? null : decode(value);

bool readWireBool(Object? value) =>
    value is bool ? value : throw const WireFormatException('bool');

String readWireString(Object? value) =>
    value is String ? value : throw const WireFormatException('string');

int readWireInt(Object? value) {
  if (value is! int || value.abs() > _maxSafeInteger) {
    throw const WireFormatException('int');
  }
  return value;
}

/// Decodes a canonical decimal string within the signed or unsigned 64-bit range.
BigInt readWireBig(Object? value) {
  final text = readWireString(value);
  final digits = text.startsWith('-') ? text.substring(1) : text;
  final canonical =
      digits.isNotEmpty &&
      digits.length <= 20 &&
      digits.codeUnits.every((unit) => unit >= 0x30 && unit <= 0x39) &&
      (digits == '0' || !digits.startsWith('0')) &&
      text != '-0';
  if (!canonical) throw const WireFormatException('decimal');
  final parsed = BigInt.parse(text);
  if (parsed < _i64Min || parsed > _u64Max) {
    throw const WireFormatException('decimal range');
  }
  return parsed;
}

/// Decodes canonical padded base64; any other spelling of the same bytes is rejected.
Uint8List readWireBytes(Object? value) {
  final text = readWireString(value);
  if (text.length % 4 != 0) throw const WireFormatException('base64');
  final Uint8List bytes;
  try {
    bytes = base64.decode(text);
  } on FormatException {
    throw const WireFormatException('base64');
  }
  if (base64.encode(bytes) != text) throw const WireFormatException('base64');
  return bytes;
}

Uint16List readWireUnits(Object? value) {
  final bytes = readWireBytes(value);
  if (bytes.length.isOdd) throw const WireFormatException('units');
  final view = ByteData.sublistView(bytes);
  return Uint16List.fromList([
    for (var index = 0; index < bytes.length; index += 2)
      view.getUint16(index, Endian.little),
  ]);
}

Uint32List readWireUint32s(Object? value) => Uint32List.fromList(
  readWireList(value, (element) {
    final number = readWireInt(element);
    if (number < 0 || number > 0xffffffff) {
      throw const WireFormatException('u32');
    }
    return number;
  }),
);

List<T> readWireList<T>(Object? value, T Function(Object? value) decode) {
  if (value is! List<Object?>) throw const WireFormatException('list');
  return [for (final element in value) decode(element)];
}

/// Accepts an object with exactly the [names] keys.
Map<String, Object?> readWireObject(
  Object? value,
  String type,
  List<String> names,
) {
  if (value is! Map<String, Object?> ||
      value.length != names.length ||
      names.any((name) => !value.containsKey(name))) {
    throw WireFormatException(type);
  }
  return value;
}
