import 'package:devmil_logging/devmil_logging.dart';
import 'diagnostic_policy.dart';
import 'package:logging/logging.dart';

/// Process logging with bounded private history and user-controlled export.
/// Console output requires an explicit diagnostic define in a debug build.
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
