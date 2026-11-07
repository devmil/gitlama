import '../di/component_registry.dart';
import '../di/inspector_window_components.dart';
import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../logging/logging_utils.dart';
import '../models/inspection_window.dart';
import '../services/avatar_service.dart';
import '../services/inspection_window_service.dart';
import '../services/inspector/inspector_window_session.dart';
import '../services/inspector_reveal_service.dart';
import '../services/settings_service.dart';

final _log = AppLogger('InspectorWindow');

/// Typed, initialized services of one inspector window.
final class InspectorWindowRuntime {
  const InspectorWindowRuntime({
    required this.session,
    required this.windows,
    required this.reveal,
    required this.settings,
    required this.avatars,
    required this.shutdown,
  });

  /// The window's own read-only session and its inspector.
  final InspectorWindowSession session;

  /// More inspector windows.
  final InspectionWindowService windows;

  /// The way back to the main window's graph.
  final InspectorRevealService reveal;
  final SettingsService settings;
  final AvatarService avatars;

  /// Disposes every service in reverse order of construction.
  final Future<void> Function() shutdown;

  /// This runtime with every service kept and [shutdown] replaced.
  InspectorWindowRuntime withShutdown(Future<void> Function() shutdown) =>
      InspectorWindowRuntime(
        session: session,
        windows: windows,
        reveal: reveal,
        settings: settings,
        avatars: avatars,
        shutdown: shutdown,
      );
}

typedef InspectorWindowComponentsFactory =
    InspectorWindowComponents Function(InspectionWindowRequest request);

/// Starts the services of an inspector window for [request]. Logging starts
/// first; a failed start disposes what was built and rethrows, so a retry
/// starts from a fresh composition root. The window's isolate owns its own
/// logging, which the returned runtime's shutdown ends last.
Future<InspectorWindowRuntime> bootstrapInspectorWindow(
  InspectionWindowRequest request, {
  InspectorWindowComponentsFactory componentsFactory =
      InspectorWindowComponents.new,
}) async {
  await LoggingUtils.initialize();
  final components = componentsFactory(request);
  final operation = _log.start('components.initialize');
  try {
    await components.initialize();
    operation.complete();
    final runtime = components.runtime;
    return runtime.withShutdown(() async {
      try {
        await runtime.shutdown();
      } finally {
        await LoggingUtils.dispose();
      }
    });
  } on Object catch (error) {
    operation.fail('component_initialization');
    final componentFailure = error is ComponentInitializationException
        ? error
        : null;
    _log.warning('inspector_window_initialization_failed', {
      'error_type': LogField(error.runtimeType, LogSensitivity.diagnostic),
      if (componentFailure != null)
        'component': LogField(
          componentFailure.componentName,
          LogSensitivity.diagnostic,
        ),
    });
    try {
      await components.dispose();
    } on Object catch (cleanupError) {
      _log.warning('inspector_window_initialization_cleanup_failed', {
        'error_type': LogField(
          cleanupError.runtimeType,
          LogSensitivity.diagnostic,
        ),
      });
    }
    rethrow;
  }
}
