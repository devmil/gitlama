import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/remote/remote_process.dart';

import 'support/fake_timers.dart';

/// A `dart:io` process double recording signals.
final class _FakeIoProcess implements Process {
  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  final stdinController = StreamController<List<int>>();
  final exit = Completer<int>();
  final signals = <ProcessSignal>[];
  final stdinBytes = <int>[];
  var stdinClosed = false;
  late final IOSink _stdin = IOSink(stdinController.sink);

  _FakeIoProcess() {
    stdinController.stream.listen(
      stdinBytes.addAll,
      onDone: () => stdinClosed = true,
    );
  }

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode => exit.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    return true;
  }
}

void main() {
  late FakeTimers timers;
  late _FakeIoProcess io;

  setUp(() {
    timers = FakeTimers();
    io = _FakeIoProcess();
  });

  test(
    'termination: close stdin, SIGTERM after 2 s, SIGKILL after 4 s',
    () async {
      final process = IoRemoteProcess(io, timer: timers.call, windows: false);
      var done = false;
      unawaited(process.terminate().then((_) => done = true));
      await settle();
      expect(io.stdinClosed, isTrue);
      expect(io.signals, isEmpty);
      timers.elapse(remoteTerminationGrace);
      await settle();
      expect(io.signals, [ProcessSignal.sigterm]);
      timers.elapse(remoteTerminationGrace);
      await settle();
      expect(io.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
      io.exit.complete(-9);
      await settle();
      expect(done, isTrue);
      // Idempotent: a second terminate sends nothing more.
      await process.terminate();
      expect(io.signals, hasLength(2));
    },
  );

  test('termination stops once the process exits after stdin closes', () async {
    final process = IoRemoteProcess(io, timer: timers.call, windows: false);
    final terminating = process.terminate();
    await settle();
    io.exit.complete(0);
    await terminating;
    expect(io.signals, isEmpty);
  });

  test('windows kills the process tree after the grace period', () async {
    final killed = <int>[];
    final process = IoRemoteProcess(
      io,
      timer: timers.call,
      windows: true,
      treeKiller: (pid) async {
        killed.add(pid);
        io.exit.complete(1);
      },
    );
    final terminating = process.terminate();
    await settle();
    expect(killed, isEmpty);
    timers.elapse(remoteTerminationGrace);
    await terminating;
    expect(killed, [4242]);
    expect(io.signals, isEmpty);
  });

  test('writes after stdin closed are ignored', () async {
    final process = IoRemoteProcess(io, timer: timers.call, windows: false);
    process.write([1, 2]);
    await process.closeStdin();
    process.write([3]);
    await settle();
    expect(io.stdinBytes, [1, 2]);
  });

  test('stderr flood does not block stdout processing', () async {
    final process = IoRemoteProcess(io, timer: timers.call, windows: false);
    final received = <int>[];
    process.stdout.listen(received.addAll);
    final noise = List<int>.filled(64 * 1024, 0x41);
    for (var i = 0; i < 64; i += 1) {
      io.stderrController.add(noise);
    }
    io.stdoutController.add([1, 2, 3]);
    await settle();
    expect(received, [1, 2, 3]);
    expect(process.stderrBytes, remoteStderrCapBytes);
  });

  test('a real child flooding stderr still delivers stdout', () async {
    final process = await startIoRemoteProcess('/bin/sh', [
      '-c',
      // 4 MiB of stderr exceeds any pipe buffer; stdout follows it.
      'head -c 4194304 /dev/zero >&2; printf done',
    ]);
    final stdout = await process.stdout
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 20));
    expect(stdout, 'done');
    expect(await process.exitCode, 0);
  }, skip: Platform.isWindows ? 'POSIX shell required' : false);
}
