import 'package:devmil_logging/devmil_logging.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_launcher.dart';
import 'app/inspection_window_app.dart';
import 'app/app_licenses.dart';
import 'di/app_components.dart';
import 'l10n/app_localizations_de.dart';
import 'l10n/app_localizations_en.dart';
import 'models/cli_forwarding.dart';
import 'models/inspection_window.dart';
import 'logging/app_logging.dart';

Future<void> main() async {
  installDiagnosticErrorHooks();
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    applySlowMotion();
    registerGitLamaLicenses();
    configureAppErrorHandling();
    WindowController? controller;
    try {
      controller = await WindowController.fromCurrentEngine();
    } on Object {
      // The main window can still start when the optional window plugin fails.
    }
    if (controller != null && controller.arguments.isNotEmpty) {
      final request = InspectionWindowRequest.decode(controller.arguments);
      if (request == null) {
        stderr.writeln('invalid_inspection_window_request');
        exit(2);
      }
      try {
        await windowManager.ensureInitialized();
        final l10n = Platform.localeName.toLowerCase().startsWith('de')
            ? AppLocalizationsDe()
            : AppLocalizationsEn();
        await windowManager.setTitle(l10n.appTitle);
        await windowManager.setMinimumSize(const Size(760, 480));
        await windowManager.setSize(const Size(1200, 760));
      } on Object {
        // Inspection remains usable if title customization is unavailable.
      }
      runApp(InspectionWindowApp(request: request));
      return;
    }
    final startup = await prepareProcessInvocation();
    if (startup.state == CliStartupState.forwarded) {
      exit(0);
    }
    if (startup.state == CliStartupState.rejected) {
      final l10n = Platform.localeName.toLowerCase().startsWith('de')
          ? AppLocalizationsDe()
          : AppLocalizationsEn();
      if (Platform.environment['GITLAMA_FORWARDING_DIAGNOSTICS'] == '1') {
        stderr.writeln(
          'gitlama_forwarding_failure=${startup.failure?.name ?? 'unknown'}',
        );
      }
      stderr.writeln(l10n.cliForwardingFailed);
      exit(2);
    }
    runApp(const AppLauncher());
  }, reportZoneError);
}

/// Slows every animation for design review:
/// `--dart-define=GITLAMA_SLOW_MOTION=5` sets `timeDilation` to 5 in
/// debug and profile builds. Release builds ignore it.
@visibleForTesting
void applySlowMotion({
  String factor = const String.fromEnvironment('GITLAMA_SLOW_MOTION'),
}) {
  if (kReleaseMode || factor.isEmpty) return;
  final value = double.tryParse(factor);
  if (value != null && value >= 1) timeDilation = value;
}
