import 'package:logging/logging.dart';

import 'log_privacy.dart';
import 'logging_utils.dart';

final class AppLogger {
  AppLogger(String name) : _logger = LoggingUtils.logger(name);

  final Logger _logger;

  void debug(String code, [Map<String, LogField> fields = const {}]) {
    _logger.fine(LogEvent(code, fields));
  }

  void info(String code, [Map<String, LogField> fields = const {}]) {
    _logger.info(LogEvent(code, fields));
  }

  void warning(String code, [Map<String, LogField> fields = const {}]) {
    _logger.warning(LogEvent(code, fields));
  }

  void severe(String code, [Map<String, LogField> fields = const {}]) {
    _logger.severe(LogEvent(code, fields));
  }

  LoggedOperation start(String operation) {
    debug('operation_started', {
      'operation': LogField(operation, LogSensitivity.public),
    });
    return LoggedOperation._(this, operation);
  }
}

/// Emits no more than one terminal event for a started operation.
final class LoggedOperation {
  LoggedOperation._(this._owner, this._operation)
    : _stopwatch = Stopwatch()..start();

  final AppLogger _owner;
  final String _operation;
  final Stopwatch _stopwatch;
  bool _finished = false;

  void complete() => _finish('operation_completed');

  void fail(String failureCode) => _finish(
    'operation_failed',
    warning: true,
    fields: {'failure_code': LogField(failureCode, LogSensitivity.public)},
  );

  void _finish(
    String code, {
    bool warning = false,
    Map<String, LogField> fields = const {},
  }) {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    final safeFields = <String, LogField>{
      'operation': LogField(_operation, LogSensitivity.public),
      'elapsed_ms': LogField(
        _stopwatch.elapsedMilliseconds.clamp(0, 86400000),
        LogSensitivity.diagnostic,
      ),
      ...fields,
    };
    if (warning) {
      _owner.warning(code, safeFields);
    } else {
      _owner.debug(code, safeFields);
    }
  }
}
