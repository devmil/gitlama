import 'package:devmil_logging/devmil_logging.dart';
import 'log_privacy.dart';

// Reviewed static product messages. Interpolated legacy text and external
// exceptions are excluded. Add typed DiagnosticEvent numeric fields for new sites.
const _reviewedMessages = <String>{
  "application_bootstrap_retried",
  "application_initialization_cleanup_failed",
  "application_initialization_failed",
  "application_shutdown_failed",
  "development_helper_lookup",
  "flutter_error",
  "inspector_window_bootstrap_retried",
  "inspector_window_initialization_cleanup_failed",
  "inspector_window_initialization_failed",
  "inspector_window_shutdown_failed",
  "platform_error",
  "remote_channel_failed",
  "remote_handshake_failed",
  "remote_helper_auto_install",
  "remote_inspection_host_unavailable",
  "remote_inspection_session_opened",
  "remote_inspection_window_sessions_closed",
  "remote_process_cleanup_failed",
  "remote_process_kill_unconfirmed",
  "remote_process_tree_kill_failed",
  "remote_profiles_save_failed",
  "remote_repository_initialized",
  "settings_background_save_failed",
  "zone_error",
};

const _reviewedComponents = <String>{
  "Bootstrap",
  "InspectorWindow",
  "InspectorWindowLauncher",
  "Launcher",
  "RemoteChannel",
  "RemoteHelper",
  "RemoteInspectionHost",
  "RemoteProcess",
  "RemoteWorkspace",
  "Settings",
  "Uncaught",
};

void configureDiagnosticPolicy() {
  DiagnosticHistory.instance.formatReviewedRecord = (record) {
    final component = _reviewedComponents.contains(record.loggerName)
        ? record.loggerName
        : 'component';
    final Object event = record.object ?? record.message;
    if (event is LogEvent) {
      final safe = LogEvent(event.code, {
        for (final entry in event.fields.entries)
          if (entry.value.sensitivity == LogSensitivity.public ||
              (entry.value.sensitivity == LogSensitivity.diagnostic &&
                  (entry.value.value is num ||
                      entry.value.value is bool ||
                      entry.value.value is Type)) ||
              const {
                'failure_code',
                'code',
                'stage',
                'contract',
                'error_type',
              }.contains(entry.key) ||
              (DiagnosticHistory.instance.detailed &&
                  entry.value.sensitivity == LogSensitivity.diagnostic))
            entry.key: entry.value,
      });
      return '$component: ${LogPrivacy.format(safe)}';
    }
    return event is String && _reviewedMessages.contains(event)
        ? '$component: $event'
        : null;
  };
}
