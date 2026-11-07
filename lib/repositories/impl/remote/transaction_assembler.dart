import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'protocol_messages.dart';
import 'wire_json.dart';
import 'wire_values.dart';
import '../../../models/remote_contract.g.dart';

/// At most this many transactions assemble at once per connection.
const remoteMaxAssemblingTransactions = 4;

/// Aggregate declared bytes of assembling transactions per connection.
const remoteMaxAssemblingBytes = 32 * 1024 * 1024;

/// One transaction's carried bytes.
const remoteMaxTransactionBytes = ContractLimits.transactionBytes;

const remoteMinTransactionChunks = 2;
const remoteMaxTransactionChunks = 16;

/// Decoded bytes of one chunk.
const remoteMaxChunkBytes = 1024 * 1024;

const _chunkKeys = [
  'transaction',
  'index',
  'count',
  'totalBytes',
  'digest',
  'data',
];

/// A transaction whose last chunk arrived with an exact length. Its digest is
/// verified by [decodeTransaction], which may run off the UI isolate.
final class CompletedTransaction {
  const CompletedTransaction({
    required this.requestId,
    required this.bytes,
    required this.digest,
  });

  final BigInt requestId;
  final Uint8List bytes;

  /// Lowercase hex SHA-256 the helper declared.
  final String digest;
}

/// Verifies the digest and parses the inner envelope with transaction bounds.
/// Throws a [WireFormatException] on any mismatch.
Object? decodeTransaction(CompletedTransaction transaction) {
  if (sha256.convert(transaction.bytes).toString() != transaction.digest) {
    throw const WireFormatException('transaction digest');
  }
  return parseWireJson(transaction.bytes, WireParseLimits.transaction);
}

final class _Assembly {
  _Assembly({
    required this.requestId,
    required this.count,
    required this.totalBytes,
    required this.digest,
  }) : bytes = BytesBuilder(copy: false);

  final BigInt requestId;
  final int count;
  final int totalBytes;
  final String digest;
  final BytesBuilder bytes;
  var nextIndex = 0;
}

/// Reassembles chunked results and publications. Every violation throws a
/// [WireFormatException]; the caller then closes the connection, and partial
/// transactions are never presented.
final class TransactionAssembler {
  TransactionAssembler({this.maxTransactionBytes = remoteMaxTransactionBytes});

  /// The negotiated transaction ceiling, at most [remoteMaxTransactionBytes].
  final int maxTransactionBytes;

  final _assembling = <BigInt, _Assembly>{};
  var _lastTransaction = BigInt.zero;
  var _reservedBytes = 0;

  int get assembling => _assembling.length;

  /// Adds one chunk; returns the transaction when this was its last chunk.
  CompletedTransaction? add(ChunkMessage chunk) {
    final fields = readWireObject(chunk.payload, 'chunk', _chunkKeys);
    final id = readWireBig(fields['transaction']);
    final index = _small(fields['index']);
    final count = _small(fields['count']);
    final totalBytes = _small(fields['totalBytes']);
    final digest = readWireString(fields['digest']);
    final data = readWireBytes(fields['data']);
    if (data.isEmpty || data.length > remoteMaxChunkBytes) {
      throw const WireFormatException('chunk data');
    }

    var assembly = _assembling[id];
    if (assembly == null) {
      if (id <= _lastTransaction || index != 0) {
        throw const WireFormatException('transaction order');
      }
      if (count < remoteMinTransactionChunks ||
          count > remoteMaxTransactionChunks ||
          totalBytes < 1 ||
          totalBytes > maxTransactionBytes ||
          totalBytes > remoteMaxTransactionBytes ||
          !isLowerHex(digest, 64)) {
        throw const WireFormatException('transaction header');
      }
      if (_assembling.length >= remoteMaxAssemblingTransactions ||
          _reservedBytes + totalBytes > remoteMaxAssemblingBytes) {
        throw const WireFormatException('transaction capacity');
      }
      _lastTransaction = id;
      _reservedBytes += totalBytes;
      assembly = _assembling[id] = _Assembly(
        requestId: chunk.requestId,
        count: count,
        totalBytes: totalBytes,
        digest: digest,
      );
    } else if (index != assembly.nextIndex ||
        count != assembly.count ||
        totalBytes != assembly.totalBytes ||
        digest != assembly.digest ||
        chunk.requestId != assembly.requestId) {
      throw const WireFormatException('transaction chunk');
    }

    if (assembly.bytes.length + data.length > assembly.totalBytes) {
      throw const WireFormatException('transaction length');
    }
    assembly.bytes.add(data);
    assembly.nextIndex += 1;
    if (assembly.nextIndex < assembly.count) return null;

    _assembling.remove(id);
    _reservedBytes -= assembly.totalBytes;
    if (assembly.bytes.length != assembly.totalBytes) {
      throw const WireFormatException('transaction length');
    }
    return CompletedTransaction(
      requestId: assembly.requestId,
      bytes: assembly.bytes.takeBytes(),
      digest: assembly.digest,
    );
  }

  /// Drops every partial transaction (disconnect).
  void discard() {
    _assembling.clear();
    _reservedBytes = 0;
  }

  static int _small(Object? value) {
    final number = readWireBig(value);
    if (number.isNegative || number > BigInt.from(remoteMaxTransactionBytes)) {
      throw const WireFormatException('chunk field');
    }
    return number.toInt();
  }
}
