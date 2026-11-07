import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'remote_timers.dart';
import 'wire_values.dart';
import '../../../models/remote_contract.g.dart';

/// The hard frame payload ceiling (4 MiB). A peer cannot raise it.
const remoteMaxFrameBytes = ContractLimits.frameBytes;

/// The hello frame ceiling (64 KiB).
const remoteHelloFrameBytes = ContractLimits.helloBytes;

/// An incomplete frame fails this long after its first byte, regardless of
/// later partial bytes.
const remotePartialFrameDeadline = Duration(seconds: 15);

const _headerBytes = 4;

/// Encodes one frame: a 4-byte big-endian length and [payload].
Uint8List encodeFrame(
  Uint8List payload, {
  int maxFrameBytes = remoteMaxFrameBytes,
}) {
  if (payload.isEmpty || payload.length > maxFrameBytes) {
    throw const WireFormatException('frame length');
  }
  final frame = Uint8List(_headerBytes + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);
  frame.setRange(_headerBytes, frame.length, payload);
  return frame;
}

/// Incremental frame decoder. [add] only buffers; [next] extracts complete
/// frames in order so the caller can change [maxFrameBytes] between frames
/// (the hello limit before the negotiated frame limit).
///
/// A declared length of zero or above [maxFrameBytes] throws a
/// [WireFormatException] before any payload buffer is allocated. A frame left
/// incomplete for [remotePartialFrameDeadline] since its first observed byte
/// calls [onDeadline] once.
final class FrameDecoder {
  FrameDecoder({
    required this.maxFrameBytes,
    required this.onDeadline,
    this._timer = systemRemoteTimer,
  });

  int maxFrameBytes;
  final void Function() onDeadline;
  final RemoteTimerFactory _timer;

  final _input = ListQueue<Uint8List>();
  var _inputOffset = 0;
  final _header = Uint8List(_headerBytes);
  var _headerFill = 0;
  Uint8List? _payload;
  var _payloadFill = 0;
  Timer? _deadline;
  var _closed = false;

  /// Whether no partial frame is buffered.
  bool get idle => _input.isEmpty && _headerFill == 0 && _payload == null;

  void add(List<int> bytes) {
    if (_closed || bytes.isEmpty) return;
    _input.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  /// The next complete frame payload, or null when more bytes are needed.
  Uint8List? next() {
    if (_closed) return null;
    while (_headerFill < _headerBytes) {
      if (!_take(_header, _headerFill, (n) => _headerFill += n)) {
        _armDeadline();
        return null;
      }
    }
    var payload = _payload;
    if (payload == null) {
      final length = ByteData.sublistView(_header).getUint32(0, Endian.big);
      if (length == 0 || length > maxFrameBytes) {
        close();
        throw const WireFormatException('frame length');
      }
      payload = _payload = Uint8List(length);
    }
    while (_payloadFill < payload.length) {
      if (!_take(payload, _payloadFill, (n) => _payloadFill += n)) {
        _armDeadline();
        return null;
      }
    }
    _payload = null;
    _payloadFill = 0;
    _headerFill = 0;
    _deadline?.cancel();
    _deadline = null;
    return payload;
  }

  /// Stops the deadline and drops buffered bytes.
  void close() {
    _closed = true;
    _deadline?.cancel();
    _deadline = null;
    _input.clear();
    _payload = null;
  }

  bool _take(Uint8List target, int fill, void Function(int) advance) {
    if (_input.isEmpty) return false;
    final chunk = _input.first;
    final count = (chunk.length - _inputOffset).clamp(0, target.length - fill);
    target.setRange(fill, fill + count, chunk, _inputOffset);
    advance(count);
    _inputOffset += count;
    if (_inputOffset == chunk.length) {
      _input.removeFirst();
      _inputOffset = 0;
    }
    return true;
  }

  void _armDeadline() {
    if (_deadline != null || (_headerFill == 0 && _payload == null)) return;
    _deadline = _timer(remotePartialFrameDeadline, () {
      if (_closed) return;
      close();
      onDeadline();
    });
  }
}
