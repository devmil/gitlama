import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../rust/api.dart' as native;
import '../../rust/third_party/gitlama_contract/child_process.dart';
import 'remote/remote_process.dart';
import 'remote/remote_timers.dart';

/// Starts [executable] as a child the Rust core owns. On macOS and Linux the
/// Dart VM reaps every child of the process while a `dart:io` process runs,
/// which makes the core's Git commands lose their exit status; these children
/// never use `dart:io`. A start failure throws [ProcessException].
Future<RemoteProcess> startNativeRemoteProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final process = NativeRemoteProcess._();
  final started = Completer<void>();
  process._subscription = native
      .childProcessStart(
        executable: executable,
        arguments: arguments,
        environment: [
          for (final MapEntry(:key, :value)
              in (environment ?? const <String, String>{}).entries)
            NativeEnvironmentVariable(name: key, value: value),
        ],
      )
      .listen(
        (event) => process._on(event, started),
        onError: (Object _) => process._ended(started),
        onDone: () => process._ended(started),
      );
  await started.future;
  return process;
}

/// A [RemoteProcess] whose child the Rust core started and waits for.
final class NativeRemoteProcess implements RemoteProcess {
  NativeRemoteProcess._();

  final RemoteTimerFactory _timer = systemRemoteTimer;
  final _stdout = StreamController<List<int>>();
  final _exit = Completer<int>();
  late final StreamSubscription<NativeChildEvent> _subscription;
  BigInt? _child;
  var _stdinClosed = false;
  Future<void>? _termination;

  void _on(NativeChildEvent event, Completer<void> started) {
    switch (event.kind) {
      case NativeChildEventKind.started:
        _child = event.childId;
        if (!started.isCompleted) started.complete();
      case NativeChildEventKind.startFailed:
        if (!started.isCompleted) {
          started.completeError(
            const ProcessException('', [], 'The process could not start'),
          );
        }
      case NativeChildEventKind.stdout:
        if (!_stdout.isClosed) _stdout.add(Uint8List.fromList(event.bytes));
      case NativeChildEventKind.stdoutClosed:
        if (!_stdout.isClosed) unawaited(_stdout.close());
      case NativeChildEventKind.exited:
        if (!_exit.isCompleted) _exit.complete(event.exitCode ?? -1);
    }
  }

  void _ended(Completer<void> started) {
    if (!started.isCompleted) {
      started.completeError(
        const ProcessException('', [], 'The process could not start'),
      );
    }
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_exit.isCompleted) _exit.complete(-1);
    unawaited(_subscription.cancel());
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(List<int> bytes) {
    final child = _child;
    if (_stdinClosed || child == null || _exit.isCompleted) return;
    if (!native.childProcessWrite(childId: child, bytes: bytes)) {
      // A closed pipe surfaces through exit and the end of stdout.
      _stdinClosed = true;
    }
  }

  @override
  Future<void> closeStdin() async {
    final child = _child;
    if (_stdinClosed || child == null) return;
    _stdinClosed = true;
    native.childProcessCloseStdin(childId: child);
  }

  @override
  Future<void> terminate() => _termination ??= _terminate();

  Future<void> _terminate() async {
    unawaited(closeStdin());
    if (await completesWithin(exitCode, remoteTerminationGrace, _timer)) {
      return;
    }
    final child = _child;
    if (child == null) return;
    native.childProcessSignal(childId: child, kill: false);
    if (await completesWithin(exitCode, remoteTerminationGrace, _timer)) {
      return;
    }
    native.childProcessSignal(childId: child, kill: true);
    await completesWithin(exitCode, remoteTerminationGrace, _timer);
  }
}

/// Runs `<executable> -V` through the core and returns its bounded standard
/// error, or null when it could not run or timed out.
Future<String?> readNativeSshVersion(
  String executable, {
  required Duration timeout,
  required int maximumBytes,
}) async {
  final result = await native.childProcessRunCapture(
    executable: executable,
    arguments: const ['-V'],
    timeoutMs: timeout.inMilliseconds,
    maximumBytes: maximumBytes,
  );
  if (!result.started || result.timedOut) return null;
  return String.fromCharCodes(result.stderr);
}
