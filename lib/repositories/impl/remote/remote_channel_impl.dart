import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../../../logging/app_logger.dart';
import '../../../logging/log_privacy.dart';
import '../../../models/remote_workspace.dart';
import '../../remote_connection_repository.dart';
import 'frame_codec.dart';
import 'protocol_messages.dart';
import 'remote_process.dart';
import 'remote_timers.dart';
import 'transaction_assembler.dart';
import 'wire_json.dart';
import 'wire_values.dart';

final _log = AppLogger('RemoteChannel');

/// The helper must send its hello this long after the process started.
const remoteHelloDeadline = Duration(seconds: 10);
const remoteInteractiveDeadline = Duration(seconds: 30);
const remoteBulkDeadline = Duration(seconds: 120);
const remotePingInterval = Duration(seconds: 15);

/// No frame for this long marks the connection disconnected.
const remoteLivenessTimeout = Duration(seconds: 45);

/// [RemoteChannel.close] waits this long for `goodbye` or exit.
const remoteShutdownGrace = Duration(seconds: 5);

/// Request slots of a connection kept for cancel, ping and shutdown.
const remoteReservedControlSlots = 4;

/// Frames at least this large are parsed off the UI isolate.
const remoteOffloadThresholdBytes = 256 * 1024;

/// After the process exits, stdout gets this long to deliver its end.
const remoteExitDrainGrace = Duration(seconds: 2);

/// Runs CPU-bound decoding; production uses [Isolate.run].
typedef RemoteOffload = Future<Object?> Function(Object? Function() work);

Future<Object?> isolateOffload(Object? Function() work) => Isolate.run(work);

// Built outside instance methods so the closures capture only their bytes.
Object? Function() _frameJob(Uint8List bytes) =>
    () => parseWireJson(bytes, WireParseLimits.frame);

Object? Function() _transactionJob(CompletedTransaction transaction) =>
    () => decodeTransaction(transaction);

enum _Stage { handshake, open, closing, closed }

final class _PendingCall {
  _PendingCall(this.completer);
  final Completer<Object?> completer;
  Timer? deadline;
}

/// A [RemoteChannel] driving one owned [RemoteProcess].
final class RemoteChannelImpl implements RemoteChannel {
  RemoteChannelImpl._(
    this._process,
    this._buildId,
    this._requested,
    this._timer,
    this._offload,
    this._random,
  );

  /// Performs the handshake on [process] and returns the open channel.
  /// Throws [RemoteWorkspaceException]; the process is terminated on failure.
  static Future<RemoteChannelImpl> connect({
    required RemoteProcess process,
    required String buildId,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    RemoteTimerFactory timer = systemRemoteTimer,
    RemoteOffload offload = isolateOffload,
    Random? random,
  }) {
    final channel = RemoteChannelImpl._(
      process,
      buildId,
      capabilities,
      timer,
      offload,
      random ?? Random.secure(),
    );
    channel._start(cancel);
    return channel._handshake.future;
  }

  final RemoteProcess _process;
  final String _buildId;
  final Set<RemoteCapability> _requested;
  final RemoteTimerFactory _timer;
  final RemoteOffload _offload;
  final Random _random;

  final _handshake = Completer<RemoteChannelImpl>();
  final _closed = Completer<RemoteFailureCode?>();
  final _goodbye = Completer<void>();
  final _publications = StreamController<RemotePublication>.broadcast();
  final _probe = BootstrapProbe();
  final _pending = <BigInt, _PendingCall>{};
  late final _decoder = FrameDecoder(
    maxFrameBytes: remoteHelloFrameBytes,
    onDeadline: _protocolFailure,
    timer: _timer,
  );

  var _stage = _Stage.handshake;
  late StreamSubscription<List<int>> _stdout;
  HelloMessage? _hello;
  EnvelopeSession? _session;
  TransactionAssembler? _assembler;
  var _busy = false;
  var _stdoutDone = false;
  int? _exitCode;
  Timer? _helloTimer;
  Timer? _exitDrainTimer;
  Timer? _pingTimer;
  Timer? _livenessTimer;
  Future<void>? _closing;

  @override
  RemoteHelperInfo get helper => _hello!.info;

  /// The negotiated limits.
  RemoteLimits get limits => _hello!.limits;

  /// Calls that can be outstanding at once.
  int get callCapacity =>
      max(1, _hello!.limits.requestsPerConnection - remoteReservedControlSlots);

  @override
  Stream<RemotePublication> get publications => _publications.stream;

  @override
  Future<RemoteFailureCode?> get closed => _closed.future;

  @override
  bool get isOpen => _stage == _Stage.open;

  // Lifecycle

  void _start(Future<void>? cancel) {
    _helloTimer = _timer(
      remoteHelloDeadline,
      () => _failHandshake(RemoteFailureCode.handshakeTimeout),
    );
    _stdout = _process.stdout.listen(
      _onData,
      onError: (Object _) => _onStdoutEnd(),
      onDone: _onStdoutEnd,
      cancelOnError: true,
    );
    _process.exitCode.then<void>(_onExit, onError: (Object _) => _onExit(-1));
    cancel?.then<void>(
      (_) => _failHandshake(RemoteFailureCode.canceled),
      onError: (Object _) => _failHandshake(RemoteFailureCode.canceled),
    );
  }

  void _onExit(int code) {
    _exitCode = code;
    if (_stdoutDone || _stage == _Stage.closed) return;
    // A descendant (ProxyCommand) can hold stdout open after ssh exited.
    _exitDrainTimer = _timer(remoteExitDrainGrace, _onStdoutEnd);
  }

  void _onStdoutEnd() {
    if (_stdoutDone) return;
    _stdoutDone = true;
    _exitDrainTimer?.cancel();
    switch (_stage) {
      case _Stage.handshake:
        unawaited(_bootstrapEnded());
      case _Stage.open:
        _fail(RemoteFailureCode.disconnected);
      case _Stage.closing:
        if (!_goodbye.isCompleted) _goodbye.complete();
      case _Stage.closed:
        break;
    }
  }

  Future<void> _bootstrapEnded() async {
    final sentinel = _probe.sentinel();
    if (sentinel != null) {
      _failHandshake(sentinel.code, hostTarget: sentinel.hostTarget);
      return;
    }
    if (_exitCode == null) {
      await completesWithin(_process.exitCode, remoteExitDrainGrace, _timer);
    }
    _failHandshake(
      _exitCode == 255
          ? RemoteFailureCode.sshConnectionFailed
          : RemoteFailureCode.bootstrapFailed,
    );
  }

  void _failHandshake(
    RemoteFailureCode code, {
    RemoteHelperTarget? hostTarget,
  }) {
    if (_stage != _Stage.handshake) return;
    _stage = _Stage.closed;
    _release();
    if (!_closed.isCompleted) _closed.complete(code);
    _handshake.completeError(
      RemoteWorkspaceException(code, hostTarget: hostTarget),
    );
    _log.info('remote_handshake_failed', {
      'failure_code': LogField(code.name, LogSensitivity.public),
    });
  }

  void _fail(RemoteFailureCode code) {
    if (_stage == _Stage.closing) {
      if (!_goodbye.isCompleted) _goodbye.complete();
      return;
    }
    if (_stage != _Stage.open) return;
    _stage = _Stage.closed;
    _release();
    _closed.complete(code);
    _log.warning('remote_channel_failed', {
      'failure_code': LogField(code.name, LogSensitivity.public),
    });
  }

  void _protocolFailure() {
    if (_stage == _Stage.handshake) {
      _failHandshake(RemoteFailureCode.bootstrapFailed);
    } else {
      _fail(RemoteFailureCode.protocolViolation);
    }
  }

  /// Stops timers and input, fails every pending call once and terminates
  /// the process.
  void _release() {
    for (final timer in [
      _helloTimer,
      _exitDrainTimer,
      _pingTimer,
      _livenessTimer,
    ]) {
      timer?.cancel();
    }
    _decoder.close();
    _assembler?.discard();
    unawaited(_stdout.cancel().catchError((Object _) {}));
    _failPending();
    unawaited(_publications.close());
    unawaited(_terminate());
  }

  void _failPending() {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final call in pending) {
      call.deadline?.cancel();
      call.completer.completeError(
        const RemoteCallException(RemoteErrorCode.disconnected),
      );
    }
  }

  Future<void> _terminate() => _process.terminate().catchError((Object _) {
    _log.warning('remote_process_cleanup_failed');
  });

  @override
  Future<void> close() => _closing ??= _closeGracefully();

  Future<void> _closeGracefully() async {
    switch (_stage) {
      case _Stage.handshake:
        _failHandshake(RemoteFailureCode.canceled);
        await _terminate();
        return;
      case _Stage.closed || _Stage.closing:
        await _terminate();
        return;
      case _Stage.open:
        break;
    }
    _stage = _Stage.closing;
    _closed.complete(null);
    _pingTimer?.cancel();
    _livenessTimer?.cancel();
    _failPending();
    unawaited(_publications.close());
    _sendControl('shutdown', const {});
    if (!_stdoutDone) {
      await completesWithin(
        Future.any<Object?>([_goodbye.future, _process.exitCode]),
        remoteShutdownGrace,
        _timer,
      );
    }
    _stage = _Stage.closed;
    _release();
    await _terminate();
  }

  // Input

  void _onData(List<int> chunk) {
    if (_stage == _Stage.closed) return;
    if (_stage == _Stage.handshake && _probe.state != BootstrapState.frames) {
      switch (_probe.add(chunk)) {
        case BootstrapState.failed:
          _failHandshake(RemoteFailureCode.bootstrapFailed);
          return;
        case BootstrapState.pending:
          return;
        case BootstrapState.frames:
          break;
      }
    }
    _decoder.add(chunk);
    _drain();
  }

  void _drain() {
    while (!_busy && _stage != _Stage.closed) {
      final Uint8List? frame;
      try {
        frame = _decoder.next();
      } on WireFormatException {
        _protocolFailure();
        return;
      }
      if (frame == null) return;
      if (_stage == _Stage.handshake) {
        _onHello(frame);
        continue;
      }
      _touchLiveness();
      if (frame.length >= remoteOffloadThresholdBytes) {
        _runOffloaded(_frameJob(frame), null);
        return;
      }
      final Object? value;
      try {
        value = parseWireJson(frame, WireParseLimits.frame);
      } on WireFormatException {
        _protocolFailure();
        return;
      }
      _onEnvelope(value, null);
    }
  }

  /// Decodes off the UI isolate while input waits, preserving frame order.
  void _runOffloaded(Object? Function() job, BigInt? carried) {
    _busy = true;
    _stdout.pause();
    _offload(job).then<void>(
      (value) {
        _busy = false;
        if (_stage == _Stage.closed) return;
        _onEnvelope(value, carried);
        if (_stage == _Stage.closed) return;
        _stdout.resume();
        _drain();
      },
      onError: (Object _) {
        _busy = false;
        _protocolFailure();
      },
    );
  }

  void _onHello(Uint8List frame) {
    final HelloMessage hello;
    try {
      hello = parseHello(frame, buildId: _buildId, requested: _requested);
    } on RemoteWorkspaceException catch (error) {
      _failHandshake(error.code);
      return;
    }
    final nonce = newConnectionNonce(_random);
    _hello = hello;
    _session = EnvelopeSession(
      nonce: nonce,
      incarnation: hello.info.incarnation,
    );
    _assembler = TransactionAssembler(
      maxTransactionBytes: hello.limits.transactionBytes,
    );
    _decoder.maxFrameBytes = hello.limits.frameBytes;
    _helloTimer?.cancel();
    _write(buildHelloAck(hello, nonce));
    _stage = _Stage.open;
    _schedulePing();
    _touchLiveness();
    _handshake.complete(this);
  }

  void _onEnvelope(Object? value, BigInt? carried) {
    if (_stage == _Stage.closed) return;
    final HelperMessage message;
    try {
      message = _session!.read(value, carried: carried);
    } on WireFormatException {
      _protocolFailure();
      return;
    }
    switch (message) {
      case ResultMessage(:final requestId, :final ok, :final error):
        final call = _pending.remove(requestId);
        // A retired, timed out or unknown request: the late result is ignored.
        if (call == null) return;
        call.deadline?.cancel();
        if (error == null) {
          call.completer.complete(ok);
        } else {
          call.completer.completeError(RemoteCallException(error));
        }
      case PublicationMessage(:final publication):
        if (_stage == _Stage.open) _publications.add(publication);
      case ChunkMessage():
        final CompletedTransaction? transaction;
        try {
          transaction = _assembler!.add(message);
        } on WireFormatException {
          _protocolFailure();
          return;
        }
        if (transaction != null) {
          _runOffloaded(_transactionJob(transaction), transaction.requestId);
        }
      case PongMessage():
        break;
      case GoodbyeMessage():
        if (!_goodbye.isCompleted) _goodbye.complete();
      case FatalMessage(:final code):
        _fail(code);
    }
  }

  // Output

  @override
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) {
    if (_stage != _Stage.open) {
      return Future.error(
        const RemoteCallException(RemoteErrorCode.disconnected),
      );
    }
    if (_pending.length >= callCapacity) {
      return Future.error(const RemoteCallException(RemoteErrorCode.capacity));
    }
    final BigInt requestId;
    try {
      requestId = _session!.nextRequestId();
    } on WireFormatException {
      _fail(RemoteFailureCode.disconnected);
      return Future.error(
        const RemoteCallException(RemoteErrorCode.disconnected),
      );
    }
    final Uint8List frame;
    try {
      frame = encodeFrame(
        encodeWireJson(
          _session!.envelope(requestId, 'call', {
            'method': method,
            'args': arguments,
          }),
        ),
        maxFrameBytes: _hello!.limits.frameBytes,
      );
    } on Object {
      // Unencodable or oversized arguments never reach the helper.
      return Future.error(
        const RemoteCallException(RemoteErrorCode.invalidRequest),
      );
    }
    final pending = _PendingCall(Completer<Object?>());
    _pending[requestId] = pending;
    pending.deadline = _timer(
      bulk ? remoteBulkDeadline : remoteInteractiveDeadline,
      () => _expire(requestId),
    );
    _process.write(frame);
    return pending.completer.future;
  }

  void _expire(BigInt requestId) {
    final call = _pending.remove(requestId);
    if (call == null) return;
    call.completer.completeError(
      const RemoteCallException(RemoteErrorCode.timedOut),
    );
    // Expiry is not proof the helper stopped; a late result is ignored.
    _sendControl('cancel', {'target': wireBig(requestId)});
  }

  void _sendControl(String kind, Map<String, Object?> payload) {
    if (_stage != _Stage.open && _stage != _Stage.closing) return;
    final BigInt requestId;
    try {
      requestId = _session!.nextRequestId();
    } on WireFormatException {
      _fail(RemoteFailureCode.disconnected);
      return;
    }
    _write(_session!.envelope(requestId, kind, payload));
  }

  void _write(Map<String, Object?> message) =>
      _process.write(encodeFrame(encodeWireJson(message)));

  void _schedulePing() {
    _pingTimer = _timer(remotePingInterval, () {
      if (_stage != _Stage.open) return;
      _sendControl('ping', const {});
      _schedulePing();
    });
  }

  void _touchLiveness() {
    _livenessTimer?.cancel();
    if (_stage != _Stage.open) return;
    _livenessTimer = _timer(
      remoteLivenessTimeout,
      () => _fail(RemoteFailureCode.disconnected),
    );
  }
}
