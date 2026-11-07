import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'log_privacy.dart';

final _log = AppLogger('Uncaught');

void configureAppErrorHandling() {
  FlutterError.onError = (details) {
    _log.severe('flutter_error', {
      'error_type': LogField(
        details.exception.runtimeType,
        LogSensitivity.diagnostic,
      ),
    });
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.severe('platform_error', {
      'error_type': LogField(error.runtimeType, LogSensitivity.diagnostic),
    });
    return true;
  };
}

void reportZoneError(Object error, StackTrace stack) {
  _log.severe('zone_error', {
    'error_type': LogField(error.runtimeType, LogSensitivity.diagnostic),
    if (error case FlutterError())
      'failure_code': LogField(
        _flutterFailureCode(error),
        LogSensitivity.diagnostic,
      ),
  });
}

String _flutterFailureCode(FlutterError error) {
  final message = error.message;
  return switch (message) {
    final value when value.contains('Unable to load asset') =>
      'asset_unavailable',
    final value when value.contains('overflowed') => 'layout_overflow',
    final value when value.contains('setState() called after dispose') =>
      'state_after_dispose',
    final value when value.contains('deactivated widget') =>
      'deactivated_widget_access',
    final value when value.contains('during build') => 'mutation_during_build',
    final value when value.contains('used after being disposed') =>
      'object_after_dispose',
    final value when value.contains('has no ScrollPosition attached') =>
      'scroll_position_unavailable',
    final value when value.contains('multiple ScrollPositions') =>
      'multiple_scroll_positions',
    final value when value.contains('infinite') => 'invalid_layout_constraint',
    final value when value.contains('hit test') => 'invalid_hit_test',
    _ => 'unclassified_flutter_error',
  };
}
