@Tags(['ssh'])
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/native_child_process_repository.dart';
import 'package:gitlama/rust/api.dart' as native;
import 'package:gitlama/rust/frb_generated.dart';

/// Runs with the core library the SSH lane builds (`GITLAMA_NATIVE_LIBRARY`).
void main() {
  setUpAll(() async {
    final library = Platform.environment['GITLAMA_NATIVE_LIBRARY'];
    expect(library, isNotNull, reason: 'set GITLAMA_NATIVE_LIBRARY');
    await RustLib.init(externalLibrary: ExternalLibrary.open(library!));
  });

  test('bytes written to the child come back in order', () async {
    final process = await startNativeRemoteProcess('cat', const []);
    final received = <int>[];
    final done = process.stdout.listen(received.addAll).asFuture<void>();
    for (var index = 0; index < 200; index++) {
      process.write(utf8.encode('$index,'));
    }
    await process.closeStdin();
    await done;
    expect(await process.exitCode, 0);
    expect(
      utf8.decode(received),
      [for (var index = 0; index < 200; index++) '$index,'].join(),
    );
  });

  test('exit codes, termination and start failures are reported', () async {
    final failing = await startNativeRemoteProcess('sh', const [
      '-c',
      'exit 7',
    ]);
    expect(await failing.exitCode, 7);

    final sleeping = await startNativeRemoteProcess('sleep', const ['30']);
    await sleeping.terminate();
    // dart:io reports a signal as its negative number.
    expect(await sleeping.exitCode, -15);

    await expectLater(
      startNativeRemoteProcess('/nonexistent/gitlama-test-binary', const []),
      throwsA(isA<ProcessException>()),
    );
  });

  test('the core keeps its own children while the transport runs', () async {
    // The regression: a dart:io child made the core's Git commands lose their
    // exit status. A long-running transport must leave them intact.
    final transport = await startNativeRemoteProcess('sleep', const ['30']);
    addTearDown(transport.terminate);
    for (var attempt = 0; attempt < 20; attempt++) {
      final probe = await native.childProcessRunCapture(
        executable: 'git',
        arguments: const ['--version'],
        timeoutMs: 10000,
        maximumBytes: 64,
      );
      expect(probe.exitCode, 0, reason: 'attempt $attempt');
    }
  });
}
