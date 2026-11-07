import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:gitlama/repositories/impl/remote/frame_codec.dart';
import 'package:gitlama/repositories/impl/remote/remote_process.dart';
import 'package:gitlama/repositories/impl/remote/wire_json.dart';

const testBuildId = '0123456789abcdef0123456789abcdef01234567';
const testIncarnation = '00112233445566778899aabbccddeeff';
const testStoreId = 'ffeeddccbbaa99887766554433221100';

Map<String, Object?> helloJson({
  Map<String, Object?> overrides = const {},
  Map<String, Object?>? limits,
}) => {
  'kind': 'hello',
  'magic': 'gitlama-remote-helper',
  'protocolMajor': 1,
  'protocolMinor': 0,
  'buildId': testBuildId,
  'platform': 'linux',
  'architecture': 'x86_64',
  'gitState': 'available',
  'gitVersion': '2.43.0',
  'helperIncarnation': testIncarnation,
  'store': {'state': 'ready', 'storeId': testStoreId},
  'account': {'uid': '1000', 'name': 'alice'},
  'capabilities': ['read', 'listDirectory', 'stage', 'commit'],
  'limits':
      limits ??
      {
        'frameBytes': '4194304',
        'transactionBytes': '16777216',
        'requestsPerConnection': '32',
        'sessionsPerConnection': '16',
      },
  ...overrides,
};

Uint8List jsonFrame(Object? value) => encodeFrame(encodeWireJson(value));

/// A scripted helper process: tests emit stdout bytes and read the frames the
/// client wrote.
final class FakeRemoteProcess implements RemoteProcess {
  final stdoutController = StreamController<List<int>>();
  final _exit = Completer<int>();
  final _written = FrameDecoder(
    maxFrameBytes: remoteMaxFrameBytes,
    onDeadline: () {},
  );
  final sent = <Map<String, Object?>>[];
  var stdinClosed = false;
  var terminateCalls = 0;

  /// When false, [terminate] leaves the process running (a stuck child).
  var exitOnTerminate = true;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(List<int> bytes) {
    if (stdinClosed) return;
    _written.add(bytes);
    while (true) {
      final frame = _written.next();
      if (frame == null) return;
      sent.add(
        parseWireJson(frame, WireParseLimits.frame)! as Map<String, Object?>,
      );
    }
  }

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  Future<void> terminate() async {
    terminateCalls += 1;
    stdinClosed = true;
    if (exitOnTerminate) exit(143);
  }

  void emit(List<int> bytes) => stdoutController.add(bytes);

  void emitJson(Object? value) => emit(jsonFrame(value));

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    if (!stdoutController.isClosed) unawaited(stdoutController.close());
  }

  void endStdout() {
    if (!stdoutController.isClosed) unawaited(stdoutController.close());
  }

  Map<String, Object?> get ack =>
      sent.firstWhere((message) => message['kind'] == 'helloAck');

  String get nonce => ack['connectionNonce']! as String;

  /// Client envelopes of [kind].
  List<Map<String, Object?>> sentOf(String kind) =>
      sent.where((message) => message['kind'] == kind).toList();

  Map<String, Object?> envelope(
    String kind,
    Object requestId,
    Map<String, Object?> payload, {
    String? nonce,
    String incarnation = testIncarnation,
    int major = 1,
  }) => {
    'protocolMajor': major,
    'connectionNonce': nonce ?? this.nonce,
    'helperIncarnation': incarnation,
    'requestId': '$requestId',
    'kind': kind,
    'payload': payload,
  };

  void emitEnvelope(
    String kind,
    Object requestId,
    Map<String, Object?> payload, {
    String? nonce,
  }) => emitJson(envelope(kind, requestId, payload, nonce: nonce));

  void emitResult(Object requestId, Object? ok) =>
      emitEnvelope('result', requestId, {'ok': ok});

  /// Chunks [inner] (an encoded envelope) as transaction [transaction].
  List<Map<String, Object?>> chunks(
    Uint8List inner, {
    required int transaction,
    required Object requestId,
    int parts = 2,
    String? digest,
    int? totalBytes,
  }) {
    final size = (inner.length / parts).ceil();
    return [
      for (var index = 0; index < parts; index += 1)
        envelope('chunk', requestId, {
          'transaction': '$transaction',
          'index': '$index',
          'count': '$parts',
          'totalBytes': '${totalBytes ?? inner.length}',
          'digest': digest ?? sha256.convert(inner).toString(),
          'data': base64.encode(
            inner.sublist(
              index * size,
              (index + 1) * size > inner.length
                  ? inner.length
                  : (index + 1) * size,
            ),
          ),
        }),
    ];
  }
}
