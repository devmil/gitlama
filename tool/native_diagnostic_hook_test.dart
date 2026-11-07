import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:logging/logging.dart';
import 'package:devmil_logging/devmil_logging.dart';
import 'package:gitlama/rust/api.dart' as native;
import 'package:gitlama/rust/frb_generated.dart';

// Explicit host-library qualification, separate from portable unit tests.
void main() {
  test(
    'native availability hook reaches the shared Dart diagnostic history',
    () async {
      final path = Platform.environment['DEVMIL_LOGGING_NATIVE_LIBRARY'];
      if (path == null) {
        throw StateError('DEVMIL_LOGGING_NATIVE_LIBRARY is required');
      }
      await RustLib.init(externalLibrary: ExternalLibrary.open(path));
      final history = DiagnosticHistory.instance;
      history.clear();
      final lease = history.acquire();
      final arrived = Completer<void>();
      final listener = Logger.root.onRecord.listen((record) {
        final event = record.object;
        if (event is DiagnosticEvent &&
            event.code == 'native.hook_ready' &&
            !arrived.isCompleted) {
          arrived.complete();
        }
      });
      final bridge = NativeDiagnosticBridge(
        detach: native.detachNativeDiagnostics,
        drain: native.drainNativeDiagnostics,
        configure: (detailed, clear) =>
            native.configureNativeDiagnostics(detailed: detailed, clear: clear),
      );
      try {
        bridge.start(native.watchNativeDiagnostics());
        await arrived.future.timeout(const Duration(seconds: 10));
        expect(
          history.snapshot(application: 'gitlama', version: 'native-test'),
          contains('native.hook_ready'),
        );
        history.enableDetailed();
        await native.configureNativeDiagnostics(detailed: true, clear: false);
        history.clear();
        await native.configureNativeDiagnostics(detailed: false, clear: true);
        expect(await native.drainNativeDiagnostics(), isEmpty);
      } finally {
        await bridge.close();
        await listener.cancel();
        await lease.close();
        RustLib.dispose();
      }
    },
  );
}
