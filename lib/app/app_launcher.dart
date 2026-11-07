import '../widgets/status_notification.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../models/settings.dart';
import 'app_bootstrap.dart';
import 'app_runtime.dart';
import 'app_appearance.dart';
import 'startup_screen.dart';
import 'home_screen.dart';
import 'native_launch_screen.dart';
import '../widgets/author_avatar.dart';
import '../widgets/native_menu.dart';
import '../widgets/gitlama_window_caption.dart';

final _log = AppLogger('Launcher');

typedef AppBootstrap = Future<AppRuntime> Function();
typedef ReadyBuilder = Widget Function(AppRuntime runtime);

class AppLauncher extends StatefulWidget {
  const AppLauncher({
    super.key,
    this.bootstrap = bootstrapApp,
    this.readyBuilder,
  });

  final AppBootstrap bootstrap;
  final ReadyBuilder? readyBuilder;

  @override
  State<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<AppLauncher> {
  AppRuntime? _runtime;
  StreamSubscription<SettingsDocument>? _settingsSubscription;
  AppearanceSettings _appearance = const AppearanceSettings();
  late Future<AppRuntime> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _start();
    unawaited(NativeMenus.prepare());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(NativeLaunchScreen.dismiss()),
    );
  }

  Future<AppRuntime> _start() async {
    final runtime = await widget.bootstrap();
    if (!mounted) {
      await runtime.shutdown();
    } else {
      setState(() {
        _runtime = runtime;
        _appearance = runtime.settings.current.appearance;
      });
      await _settingsSubscription?.cancel();
      _settingsSubscription = runtime.settings.changes.listen((document) {
        if (mounted) setState(() => _appearance = document.appearance);
      });
    }
    return runtime;
  }

  void _retry() {
    _log.info('application_bootstrap_retried');
    setState(() {
      _startup = _start();
    });
  }

  @override
  void dispose() {
    unawaited(_settingsSubscription?.cancel());
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(
        runtime.shutdown().catchError((Object error, StackTrace stack) {
          _log.warning('application_shutdown_failed', {
            'error_type': LogField(
              error.runtimeType,
              LogSensitivity.diagnostic,
            ),
          });
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = AppAppearance(_appearance);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appearance.theme,
      darkTheme: appearance.darkTheme,
      themeMode: appearance.themeMode,
      builder: (context, child) => appearance.applyMotion(
        context,
        NativeMenus.scope(
          child: GitLamaWindowCaptionFrame(
            child: StatusNotificationScope(
              operations: _runtime?.operationCenter,
              release: _runtime?.updates.installed,
              loadActivity: _runtime?.repositorySessions.activityRecordFor,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      home: FutureBuilder<AppRuntime>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            return AvatarScope(
              service: snapshot.data!.avatars,
              child:
                  widget.readyBuilder?.call(snapshot.data!) ??
                  HomeScreen(runtime: snapshot.data!),
            );
          }
          final failed =
              snapshot.connectionState == ConnectionState.done &&
              snapshot.hasError;
          return StartupScreen(failed: failed, onRetry: _retry);
        },
      ),
    );
  }
}
