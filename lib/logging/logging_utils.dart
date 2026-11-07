import 'package:devmil_logging/devmil_logging.dart';
import 'diagnostic_policy.dart';
import 'package:logging/logging.dart';

/// Process logging with console-only output and privacy filtering.
///
/// The base starter persists no logs. Add the reviewed bounded-file module only
/// when a product needs exportable diagnostics.
final class LoggingUtils {
  LoggingUtils._();

  static DiagnosticLease? _subscription;

  static Logger logger(String name) => Logger(name);

  static Future<void> initialize() async {
    if (_subscription != null) return;
    configureDiagnosticPolicy();
    _subscription = DiagnosticHistory.instance.acquire();
  }

  static Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.close();
  }
}
