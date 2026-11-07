import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../models/remote_workspace.dart';
import '../../remote_connection_repository.dart';
import 'frame_codec.dart';
import 'wire_json.dart';
import 'wire_values.dart';

const remoteProtocolMajor = 1;
const remoteProtocolMinor = 0;
const remoteHelperMagic = 'gitlama-remote-helper';

/// Bounded display/version strings in a hello.
const _maxHelloTextBytes = 128;

final _u64Max = (BigInt.one << 64) - BigInt.one;

bool isLowerHex(String text, int length) =>
    text.length == length &&
    text.codeUnits.every(
      (unit) =>
          (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66),
    );

/// Whether [buildId] is a 40-character lowercase hexadecimal helper ID: the
/// helper's compatibility version as 40 decimal digits.
bool isValidBuildId(String buildId) => isLowerHex(buildId, 40);

/// A fresh connection nonce: 16 bytes from [random] as 32 lowercase hex.
String newConnectionNonce([Random? random]) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index += 1) {
    buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

// Bootstrap

/// What a launch script's status line reports instead of a hello.
typedef BootstrapSentinel = ({
  RemoteFailureCode code,
  RemoteHelperTarget? hostTarget,
});

/// The fixed launch script's status lines. A missing helper names the host's
/// platform, so the matching bundled helper can be offered.
final bootstrapSentinels = <String, BootstrapSentinel>{
  for (final target in RemoteHelperTarget.values)
    'GITLAMA-BOOTSTRAP 1 missing ${target.host}\n': (
      code: RemoteFailureCode.helperNotInstalled,
      hostTarget: target,
    ),
  'GITLAMA-BOOTSTRAP 1 platform\n': (
    code: RemoteFailureCode.unsupportedPlatform,
    hostTarget: null,
  ),
};

final _sentinelBytes = {
  for (final entry in bootstrapSentinels.entries)
    ascii.encode(entry.key): entry.value,
};
final _maxSentinelLength = _sentinelBytes.keys.fold(
  0,
  (length, bytes) => max(length, bytes.length),
);

enum BootstrapState {
  /// Nothing conclusive yet.
  pending,

  /// The bytes are a hello frame candidate; decode them as frames.
  frames,

  /// The bytes cannot be a sentinel or a hello.
  failed,
}

/// Classifies stdout before a hello. A hello frame begins with a zero byte
/// (its length is at most 64 KiB); anything else must be exactly one
/// sentinel line followed by end of file. Banners and other shell output are
/// never scanned for a hello.
final class BootstrapProbe {
  final _bytes = <int>[];
  var _state = BootstrapState.pending;

  BootstrapState get state => _state;

  BootstrapState add(List<int> bytes) {
    if (_state != BootstrapState.pending || bytes.isEmpty) return _state;
    if (_bytes.isEmpty && bytes.first == 0) {
      return _state = BootstrapState.frames;
    }
    _bytes.addAll(bytes.take(_maxSentinelLength + 1 - _bytes.length));
    final prefix = _sentinelBytes.keys.any(
      (sentinel) =>
          _bytes.length <= sentinel.length && _startsWith(sentinel, _bytes),
    );
    if (!prefix) _state = BootstrapState.failed;
    return _state;
  }

  /// The failure for end of file before a hello.
  BootstrapSentinel? sentinel() {
    if (_state != BootstrapState.pending) return null;
    for (final entry in _sentinelBytes.entries) {
      if (entry.key.length == _bytes.length && _startsWith(entry.key, _bytes)) {
        return entry.value;
      }
    }
    return null;
  }

  static bool _startsWith(List<int> whole, List<int> prefix) {
    for (var index = 0; index < prefix.length; index += 1) {
      if (whole[index] != prefix[index]) return false;
    }
    return true;
  }
}

// Hello

/// Per-connection limits; the effective value is the smaller peer's.
final class RemoteLimits {
  const RemoteLimits({
    required this.frameBytes,
    required this.transactionBytes,
    required this.requestsPerConnection,
    required this.sessionsPerConnection,
  });

  static const local = RemoteLimits(
    frameBytes: remoteMaxFrameBytes,
    transactionBytes: ContractLimits.transactionBytes,
    requestsPerConnection: ContractLimits.requestsPerConnection,
    sessionsPerConnection: ContractLimits.sessionsPerConnection,
  );

  final int frameBytes;
  final int transactionBytes;
  final int requestsPerConnection;
  final int sessionsPerConnection;
}

/// A validated hello.
final class HelloMessage {
  const HelloMessage({
    required this.info,
    required this.limits,
    required this.offered,
  });

  /// Carries the negotiated capability intersection.
  final RemoteHelperInfo info;
  final RemoteLimits limits;

  /// Every known capability the helper offered.
  final Set<RemoteCapability> offered;
}

const _helloKeys = [
  'kind',
  'magic',
  'protocolMajor',
  'protocolMinor',
  'buildId',
  'platform',
  'architecture',
  'gitState',
  'gitVersion',
  'helperIncarnation',
  'store',
  'account',
  'capabilities',
  'limits',
];

Never _helloFailure(RemoteFailureCode code) =>
    throw RemoteWorkspaceException(code);

/// Validates a hello frame for a client of [buildId] that wants [requested].
/// Throws a [RemoteWorkspaceException]: a frame that is not a hello is
/// [RemoteFailureCode.bootstrapFailed].
HelloMessage parseHello(
  Uint8List payload, {
  required String buildId,
  required Set<RemoteCapability> requested,
  RemoteLimits local = RemoteLimits.local,
}) {
  if (payload.length > remoteHelloFrameBytes) {
    _helloFailure(RemoteFailureCode.bootstrapFailed);
  }
  final Object? value;
  try {
    value = parseWireJson(payload, WireParseLimits.frame);
  } on WireFormatException {
    _helloFailure(RemoteFailureCode.bootstrapFailed);
  }
  if (value is! Map<String, Object?> ||
      value['kind'] != 'hello' ||
      value['magic'] != remoteHelperMagic) {
    _helloFailure(RemoteFailureCode.bootstrapFailed);
  }
  final major = value['protocolMajor'];
  if (major is! int) _helloFailure(RemoteFailureCode.bootstrapFailed);
  if (major != remoteProtocolMajor) {
    _helloFailure(RemoteFailureCode.protocolMismatch);
  }
  try {
    final hello = readWireObject(value, 'hello', _helloKeys);
    final minor = readWireInt(hello['protocolMinor']);
    if (minor < 0) throw const WireFormatException('minor');
    final helperBuild = readWireString(hello['buildId']);
    if (!isValidBuildId(helperBuild)) throw const WireFormatException('build');
    _boundedText(hello['platform']);
    _boundedText(hello['architecture']);
    final gitState = readWireString(hello['gitState']);
    final gitVersion = wireOptional(hello['gitVersion'], _boundedText);
    final incarnation = readWireString(hello['helperIncarnation']);
    if (!isLowerHex(incarnation, 32)) {
      throw const WireFormatException('incarnation');
    }
    final store = readWireObject(hello['store'], 'store', ['state', 'storeId']);
    final storeState = readWireString(store['state']);
    final storeId = wireOptional(store['storeId'], readWireString);
    final account = readWireObject(hello['account'], 'account', [
      'uid',
      'name',
    ]);
    final uid = readWireBig(account['uid']);
    if (uid.isNegative) throw const WireFormatException('uid');
    final accountName = _boundedText(account['name']);
    final offered = <RemoteCapability>{
      for (final name in readWireList(hello['capabilities'], readWireString))
        ?RemoteCapability.values.asNameMap()[name],
    };
    final limits = _negotiateLimits(hello['limits'], local);

    switch (gitState) {
      case 'available' || 'missing' || 'unsupported':
        break;
      default:
        throw const WireFormatException('gitState');
    }
    switch (storeState) {
      case 'ready':
        if (storeId == null || !isLowerHex(storeId, 32)) {
          throw const WireFormatException('storeId');
        }
      case 'unavailable':
        if (storeId != null) throw const WireFormatException('storeId');
      default:
        throw const WireFormatException('store');
    }

    if (helperBuild != buildId) _helloFailure(RemoteFailureCode.buildMismatch);
    if (gitState == 'missing') _helloFailure(RemoteFailureCode.gitMissing);
    if (gitState == 'unsupported') {
      _helloFailure(RemoteFailureCode.gitUnsupported);
    }
    if (storeId == null) _helloFailure(RemoteFailureCode.storeUnavailable);

    return HelloMessage(
      info: RemoteHelperInfo(
        buildId: helperBuild,
        incarnation: incarnation,
        storeId: storeId,
        accountUid: uid.toString(),
        accountName: accountName,
        gitVersion: gitVersion,
        capabilities: requested.intersection(offered),
      ),
      limits: limits,
      offered: offered,
    );
  } on WireFormatException {
    _helloFailure(RemoteFailureCode.bootstrapFailed);
  }
}

String _boundedText(Object? value) {
  final text = readWireString(value);
  if (utf8.encode(text).length > _maxHelloTextBytes) {
    throw const WireFormatException('text');
  }
  return text;
}

RemoteLimits _negotiateLimits(Object? value, RemoteLimits local) {
  final limits = readWireObject(value, 'limits', [
    'frameBytes',
    'transactionBytes',
    'requestsPerConnection',
    'sessionsPerConnection',
  ]);
  int effective(String name, int localValue) {
    final remote = readWireBig(limits[name]);
    if (remote <= BigInt.zero) throw const WireFormatException('limit');
    return remote < BigInt.from(localValue) ? remote.toInt() : localValue;
  }

  return RemoteLimits(
    frameBytes: effective('frameBytes', local.frameBytes),
    transactionBytes: effective('transactionBytes', local.transactionBytes),
    requestsPerConnection: effective(
      'requestsPerConnection',
      local.requestsPerConnection,
    ),
    sessionsPerConnection: effective(
      'sessionsPerConnection',
      local.sessionsPerConnection,
    ),
  );
}

/// The acknowledgement for a validated [hello].
Map<String, Object?> buildHelloAck(HelloMessage hello, String nonce) => {
  'kind': 'helloAck',
  'protocolMajor': remoteProtocolMajor,
  'protocolMinor': remoteProtocolMinor,
  'buildId': hello.info.buildId,
  'helperIncarnation': hello.info.incarnation,
  'connectionNonce': nonce,
  'capabilities': [
    for (final capability in RemoteCapability.values)
      if (hello.info.capabilities.contains(capability)) capability.name,
  ],
};

// Envelopes

const _envelopeKeys = [
  'protocolMajor',
  'connectionNonce',
  'helperIncarnation',
  'requestId',
  'kind',
  'payload',
];

/// A message the helper sent after the acknowledgement.
sealed class HelperMessage {
  const HelperMessage(this.requestId);
  final BigInt requestId;
}

final class ResultMessage extends HelperMessage {
  const ResultMessage(super.requestId, {this.ok, this.error});

  final Object? ok;

  /// Null for a successful result.
  final RemoteErrorCode? error;
}

final class PublicationMessage extends HelperMessage {
  PublicationMessage(this.sequence, this.publication) : super(BigInt.zero);
  final BigInt sequence;
  final RemotePublication publication;
}

final class ChunkMessage extends HelperMessage {
  const ChunkMessage(super.requestId, this.payload);

  /// Validated by the transaction assembler.
  final Map<String, Object?> payload;
}

final class PongMessage extends HelperMessage {
  const PongMessage(super.requestId);
}

final class GoodbyeMessage extends HelperMessage {
  const GoodbyeMessage(super.requestId);
}

final class FatalMessage extends HelperMessage {
  const FatalMessage(super.requestId, this.code);
  final RemoteFailureCode code;
}

/// The fatal codes a helper may send, as client failures.
const _fatalCodes = <String, RemoteFailureCode>{
  'protocolViolation': RemoteFailureCode.protocolViolation,
  'handshakeRejected': RemoteFailureCode.protocolMismatch,
  'handshakeTimeout': RemoteFailureCode.handshakeTimeout,
  'shutdown': RemoteFailureCode.disconnected,
};

final _helperErrorCodes = {
  for (final code in RemoteErrorCode.values)
    if (code != RemoteErrorCode.disconnected) code.name: code,
};

/// One connection's envelope state: identity, client request IDs and the
/// publication sequence. Every violation throws a [WireFormatException].
final class EnvelopeSession {
  EnvelopeSession({required this.nonce, required this.incarnation});

  final String nonce;
  final String incarnation;

  var _lastRequestId = BigInt.zero;
  var _lastSequence = BigInt.zero;

  /// The newest client request ID; zero before the first.
  BigInt get lastRequestId => _lastRequestId;

  /// Allocates the next client request ID. Overflow retires the connection.
  BigInt nextRequestId() {
    if (_lastRequestId >= _u64Max) {
      throw const WireFormatException('request id overflow');
    }
    return _lastRequestId += BigInt.one;
  }

  Map<String, Object?> envelope(
    BigInt requestId,
    String kind,
    Map<String, Object?> payload,
  ) => {
    'protocolMajor': remoteProtocolMajor,
    'connectionNonce': nonce,
    'helperIncarnation': incarnation,
    'requestId': wireBig(requestId),
    'kind': kind,
    'payload': payload,
  };

  /// Validates a decoded helper envelope. [carried] is the request ID of the
  /// chunks of a reassembled transaction; its inner envelope may only be a
  /// result or publication with the same ID.
  HelperMessage read(Object? value, {BigInt? carried}) {
    final envelope = readWireObject(value, 'envelope', _envelopeKeys);
    if (envelope['protocolMajor'] != remoteProtocolMajor ||
        envelope['connectionNonce'] != nonce ||
        envelope['helperIncarnation'] != incarnation) {
      throw const WireFormatException('envelope identity');
    }
    final requestId = readWireBig(envelope['requestId']);
    if (requestId.isNegative || requestId > _lastRequestId) {
      throw const WireFormatException('request id');
    }
    final kind = readWireString(envelope['kind']);
    final payload = envelope['payload'];
    if (payload is! Map<String, Object?>) {
      throw const WireFormatException('payload');
    }
    if (carried != null &&
        (requestId != carried || (kind != 'result' && kind != 'publication'))) {
      throw const WireFormatException('transaction envelope');
    }
    switch (kind) {
      case 'result':
        if (requestId == BigInt.zero) {
          throw const WireFormatException('request id');
        }
        return _result(requestId, payload);
      case 'publication':
        if (requestId != BigInt.zero) {
          throw const WireFormatException('request id');
        }
        return _publication(payload);
      case 'chunk':
        return ChunkMessage(requestId, payload);
      case 'pong' || 'goodbye':
        if (requestId == BigInt.zero || payload.isNotEmpty) {
          throw WireFormatException(kind);
        }
        return kind == 'pong'
            ? PongMessage(requestId)
            : GoodbyeMessage(requestId);
      case 'fatal':
        final fatal = readWireObject(payload, 'fatal', ['code']);
        final code = _fatalCodes[readWireString(fatal['code'])];
        return FatalMessage(
          requestId,
          code ?? RemoteFailureCode.protocolViolation,
        );
      default:
        throw const WireFormatException('kind');
    }
  }

  ResultMessage _result(BigInt requestId, Map<String, Object?> payload) {
    if (payload.length != 1) throw const WireFormatException('result');
    if (payload.containsKey('ok')) {
      return ResultMessage(requestId, ok: payload['ok']);
    }
    final error = readWireObject(payload['error'], 'error', ['code']);
    final code = _helperErrorCodes[readWireString(error['code'])];
    if (code == null) throw const WireFormatException('error code');
    return ResultMessage(requestId, error: code);
  }

  PublicationMessage _publication(Map<String, Object?> payload) {
    final publication = readWireObject(payload, 'publication', [
      'sequence',
      'type',
      'sessionId',
      'events',
    ]);
    final sequence = readWireBig(publication['sequence']);
    if (sequence <= _lastSequence) {
      throw const WireFormatException('sequence');
    }
    if (publication['type'] != 'sessionEvents') {
      throw const WireFormatException('publication type');
    }
    final sessionId = readWireBig(publication['sessionId']);
    if (sessionId.isNegative) throw const WireFormatException('session id');
    _lastSequence = sequence;
    return PublicationMessage(
      sequence,
      RemotePublication(sessionId: sessionId, events: publication['events']),
    );
  }
}
