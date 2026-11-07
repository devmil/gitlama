import 'dart:async';
import 'dart:io';

import '../../../logging/app_logger.dart';
import 'remote_timers.dart';

final _log = AppLogger('RemoteProcess');

/// Grace after closing stdin, and again after the polite termination signal.
const remoteTerminationGrace = Duration(seconds: 2);

/// Most stderr bytes accounted per process. Stderr is drained continuously
/// and discarded; it is never logged, stored or shown.
const remoteStderrCapBytes = 64 * 1024;

/// An owned child process speaking the remote protocol over stdin/stdout.
abstract interface class RemoteProcess {
  /// Single-subscription protocol bytes.
  Stream<List<int>> get stdout;

  /// Queues protocol bytes for stdin. Ignored after stdin closed or the
  /// process exited.
  void write(List<int> bytes);

  Future<void> closeStdin();

  Future<int> get exitCode;

  /// Closes stdin, waits [remoteTerminationGrace] for exit, then signals
  /// termination, waits again and forcibly kills. Idempotent.
  Future<void> terminate();
}

/// Starts an owned child process without a shell.
typedef ProcessStarter =
    Future<RemoteProcess> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

/// Runs a Windows process-tree kill for [pid].
typedef TreeKiller = Future<void> Function(int pid);

/// The production [ProcessStarter]. A start failure throws the
/// [ProcessException]; callers map it to a typed failure.
Future<RemoteProcess> startIoRemoteProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    runInShell: false,
  );
  return IoRemoteProcess(process);
}

/// A [RemoteProcess] over a `dart:io` [Process].
final class IoRemoteProcess implements RemoteProcess {
  IoRemoteProcess(
    this._process, {
    this._timer = systemRemoteTimer,
    bool? windows,
    TreeKiller? treeKiller,
  }) : _windows = windows ?? Platform.isWindows,
       _treeKiller = treeKiller ?? _taskkillTree {
    // Drain stderr continuously so a chatty ProxyCommand or login script
    // never blocks the child; count up to the cap, keep nothing.
    _process.stderr.listen(
      (chunk) {
        if (_stderrBytes < remoteStderrCapBytes) {
          _stderrBytes = (_stderrBytes + chunk.length).clamp(
            0,
            remoteStderrCapBytes,
          );
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    _process.stdin.done.catchError((Object _) {});
    _process.exitCode.then<void>((_) => _exited = true);
  }

  final Process _process;
  final RemoteTimerFactory _timer;
  final bool _windows;
  final TreeKiller _treeKiller;
  var _stderrBytes = 0;
  var _stdinClosed = false;
  var _exited = false;
  Future<void>? _termination;

  /// Stderr bytes seen, saturating at [remoteStderrCapBytes].
  int get stderrBytes => _stderrBytes;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(List<int> bytes) {
    if (_stdinClosed || _exited) return;
    try {
      _process.stdin.add(bytes);
    } on Object {
      // A closed pipe surfaces through exit/stdout end; nothing to report.
      _stdinClosed = true;
    }
  }

  @override
  Future<void> closeStdin() async {
    if (_stdinClosed) return;
    _stdinClosed = true;
    try {
      await _process.stdin.close();
    } on Object {
      // The process already exited.
    }
  }

  @override
  Future<void> terminate() => _termination ??= _terminate();

  Future<void> _terminate() async {
    unawaited(closeStdin());
    if (await completesWithin(exitCode, remoteTerminationGrace, _timer)) {
      return;
    }
    if (_windows) {
      // Windows: the OpenSSH client may own ProxyCommand descendants, so kill
      // the tree. Tree ownership on Windows (job objects) is not qualified;
      // this is best effort until a tested job boundary exists.
      try {
        await _treeKiller(_process.pid);
      } on Object {
        _log.warning('remote_process_tree_kill_failed');
      }
      if (await completesWithin(exitCode, remoteTerminationGrace, _timer)) {
        return;
      }
      _process.kill();
      return;
    }
    _process.kill(ProcessSignal.sigterm);
    if (await completesWithin(exitCode, remoteTerminationGrace, _timer)) {
      return;
    }
    _process.kill(ProcessSignal.sigkill);
    if (!await completesWithin(exitCode, remoteTerminationGrace, _timer)) {
      _log.warning('remote_process_kill_unconfirmed');
    }
  }
}

Future<void> _taskkillTree(int pid) async {
  // Only the system copy; a bare name could resolve in the current directory.
  final root = Platform.environment['SystemRoot'];
  if (root == null) throw StateError('SystemRoot');
  await Process.run('$root\\System32\\taskkill.exe', [
    '/T',
    '/F',
    '/PID',
    '$pid',
  ], runInShell: false).timeout(remoteTerminationGrace);
}
