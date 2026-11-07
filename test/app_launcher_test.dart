import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:gitlama/app/app_launcher.dart';
import 'package:gitlama/app/native_launch_screen.dart';
import 'package:gitlama/app/app_runtime.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/services/operation_center_service.dart';

import 'support/inert_runtime.dart';
import 'support/fake_repository_session_repository.dart';
import 'support/fake_recovery_repository.dart';
import 'support/fake_settings_repository.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  testWidgets('shows localized loading while bootstrap is pending', (
    tester,
  ) async {
    final pending = Completer<AppRuntime>();
    await tester.pumpWidget(AppLauncher(bootstrap: () => pending.future));
    await tester.pump();

    expect(find.byType(MeridianSpinner), findsOneWidget);
    expect(find.text('Starting…'), findsOneWidget);
    final logo = tester.widget<Image>(find.byType(Image));
    expect((logo.image as AssetImage).assetName, 'assets/brand/tile-256.png');
    // The mark sits exactly at the centre, where the macOS cover drew it.
    expect(
      tester.getCenter(find.byType(Image)),
      tester.getCenter(find.byType(Scaffold)),
    );

    final settings = fakeSettingsService();
    pending.complete(
      testRuntime(
        repositorySessions: fakeRepositorySessionService(),
        settings: settings,
        recovery: fakeRecoveryService(settings),
        operationCenter: OperationCenterService.empty(),
        shutdown: () async {},
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('dismisses the macOS launch cover after the first frame', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeLaunchScreen.channel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeLaunchScreen.channel,
        null,
      ),
    );
    final pending = Completer<AppRuntime>();
    await tester.pumpWidget(AppLauncher(bootstrap: () => pending.future));
    // pumpWidget draws the first frame; the cover fades once, then.
    expect(calls, ['ready']);
    await tester.pump();
    expect(calls, ['ready']);
    pending.completeError(StateError('stop'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('retries failed bootstrap with a fresh attempt', (tester) async {
    var attempts = 0;
    var shutdowns = 0;
    Future<AppRuntime> bootstrap() async {
      attempts += 1;
      if (attempts == 1) throw StateError('injected');
      final settings = fakeSettingsService();
      return testRuntime(
        repositorySessions: fakeRepositorySessionService(),
        settings: settings,
        recovery: fakeRecoveryService(settings),
        operationCenter: OperationCenterService.empty(),
        shutdown: () async {
          shutdowns += 1;
        },
      );
    }

    await tester.pumpWidget(
      AppLauncher(
        bootstrap: bootstrap,
        readyBuilder: (_) => const Text('ready'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The app could not start.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('ready'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(shutdowns, 1);
  });

  testWidgets('does not expose raw startup errors', (tester) async {
    await tester.pumpWidget(
      AppLauncher(
        bootstrap: () => Future<AppRuntime>.error(
          StateError('private document title and token=secret-value'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('private document'), findsNothing);
    expect(find.textContaining('secret-value'), findsNothing);
    expect(find.text('The app could not start.'), findsOneWidget);
  });

  testWidgets('applies live theme, density, and motion settings', (
    tester,
  ) async {
    final settings = fakeSettingsService();
    await settings.initialize();
    final runtime = testRuntime(
      repositorySessions: fakeRepositorySessionService(),
      settings: settings,
      recovery: fakeRecoveryService(settings),
      operationCenter: OperationCenterService.empty(),
      shutdown: settings.dispose,
    );
    await tester.pumpWidget(
      AppLauncher(
        bootstrap: () async => runtime,
        readyBuilder: (_) => Builder(
          builder: (context) => Text(
            '${Theme.of(context).brightness.name}:'
            '${MeridianTheme.of(context).density.name}:'
            '${MediaQuery.disableAnimationsOf(context)}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    settings.updateView(
      settings.current.copyWith(
        appearance: const AppearanceSettings(
          theme: 'dark',
          density: 'compact',
          reduceMotion: 'reduce',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('dark:compact:true'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
