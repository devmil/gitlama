import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/gitlama_window_caption.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets(
    'native Linux border follows the active theme without duplicate updates',
    (tester) async {
      const channel = MethodChannel('gitlama/window_chrome');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      Future<void> show(Brightness brightness) => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => GitLamaWindowCaptionFrame(child: child!),
          home: const SizedBox(),
        ),
      );
      await show(Brightness.light);
      await tester.pump();
      final backgrounds = calls.where(
        (call) => call.method == 'setBackgroundColor',
      );
      expect(backgrounds, hasLength(1));
      final light = buildAppTheme(
        Brightness.light,
      ).scaffoldBackgroundColor.toARGB32();
      expect(backgrounds.last.arguments, light);
      await show(Brightness.light);
      await tester.pump();
      expect(backgrounds, hasLength(1));
      await show(Brightness.dark);
      await tester.pump();
      expect(backgrounds, hasLength(2));
      final dark = buildAppTheme(
        Brightness.dark,
      ).scaffoldBackgroundColor.toARGB32();
      expect(backgrounds.last.arguments, dark);
      expect(dark, isNot(light));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  group('GitLamaCaptionLayout.parse', () {
    test('reads both edges and skips entries it does not draw', () {
      expect(
        GitLamaCaptionLayout.parse('menu,close:spacer,minimize,maximize'),
        const GitLamaCaptionLayout(
          leading: [GitLamaCaptionButton.close],
          trailing: [
            GitLamaCaptionButton.minimize,
            GitLamaCaptionButton.maximize,
          ],
        ),
      );
    });

    test('treats a layout without a colon as leading only', () {
      expect(
        GitLamaCaptionLayout.parse('close'),
        const GitLamaCaptionLayout(
          leading: [GitLamaCaptionButton.close],
          trailing: [],
        ),
      );
    });

    test('falls back to a close button without a value', () {
      expect(GitLamaCaptionLayout.parse(null), GitLamaCaptionLayout.fallback);
      expect(
        GitLamaCaptionLayout.parse(':'),
        const GitLamaCaptionLayout(leading: [], trailing: []),
      );
    });
  });

  Widget app(Widget home) => MaterialApp(
    builder: (context, child) => GitLamaWindowCaptionFrame(child: child!),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(Brightness.light),
    home: home,
  );

  testWidgets('follows the desktop layout and its changes on Linux', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = GitLamaWindowCaptionFrame.channel;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captionLayout') return 'appmenu:close';
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      app(const GitLamaWindowCaptionBand(child: Scaffold(body: SizedBox()))),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('window-caption-band')), findsOneWidget);
    expect(find.byKey(const ValueKey('window-caption-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('window-caption-minimize')), findsNothing);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('captionLayoutChanged', 'minimize,maximize,close:'),
      ),
      (_) {},
    );
    await tester.pump();
    final minimize = tester.getRect(
      find.byKey(const ValueKey('window-caption-minimize')),
    );
    final close = tester.getRect(
      find.byKey(const ValueKey('window-caption-close')),
    );
    expect(minimize.left, lessThan(close.left));
    expect(close.right, lessThan(400));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('keeps the native title bar on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: Column(
            children: [
              GitLamaWindowDragArea(child: SizedBox(height: 40)),
              GitLamaWindowControls(),
              Expanded(child: GitLamaWindowCaptionBand(child: SizedBox())),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(DragToMoveArea), findsOneWidget);
    expect(find.byKey(const ValueKey('window-controls')), findsNothing);
    expect(find.byKey(const ValueKey('window-caption-band')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
