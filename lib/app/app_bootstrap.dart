import '../di/app_components.dart';
import '../di/component_registry.dart';
import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../logging/logging_utils.dart';
import 'app_runtime.dart';

final _log = AppLogger('Bootstrap');

typedef AppComponentsFactory = AppComponents Function();

Future<AppRuntime> bootstrapApp({
  AppComponentsFactory componentsFactory = AppComponents.new,
}) async {
  await LoggingUtils.initialize();
  final components = componentsFactory();
  final operation = _log.start('components.initialize');
  try {
    await components.initialize();
    operation.complete();
    final runtime = components.runtime;
    return runtime.withShutdown(() async {
      await runtime.shutdown();
      await LoggingUtils.dispose();
    });
  } on Object catch (error) {
    operation.fail('component_initialization');
    final componentFailure = error is ComponentInitializationException
        ? error
        : null;
    _log.warning('application_initialization_failed', {
      'error_type': LogField(error.runtimeType, LogSensitivity.diagnostic),
      if (componentFailure != null) ...{
        'component': LogField(
          componentFailure.componentName,
          LogSensitivity.diagnostic,
        ),
        'cause_type': LogField(
          componentFailure.cause.runtimeType,
          LogSensitivity.diagnostic,
        ),
      },
    });
    try {
      await components.dispose();
    } on Object catch (cleanupError) {
      _log.warning('application_initialization_cleanup_failed', {
        'error_type': LogField(
          cleanupError.runtimeType,
          LogSensitivity.diagnostic,
        ),
      });
    }
    rethrow;
  }
}
