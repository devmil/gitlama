@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';

import 'component_gallery_test.dart' show gallery;
import 'support/visual_capture.dart';

void main() {
  setUpAll(() async {
    final mono = FontLoader('packages/meridian_ui/JetBrains Mono')
      ..addFont(
        rootBundle.load(
          'packages/meridian_ui/assets/fonts/JetBrainsMono-Regular.ttf',
        ),
      );
    await mono.load();
    const fontPath = String.fromEnvironment('UI_REVIEW_FONT');
    if (fontPath.isNotEmpty) {
      final body = FontLoader('Roboto')
        ..addFont(
          File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await body.load();
    }
  });
  final viewports = <(String, Size, double)>[
    ('compact-minimum', const Size(900, 600), 1),
    ('compact-scaled', const Size(900, 600), 1.3),
    ('laptop', const Size(1280, 720), 1),
    ('desktop', const Size(1440, 900), 1),
    ('wide', const Size(1920, 1080), 1),
    ('desktop-scaled', const Size(1440, 900), 1.3),
  ];

  for (final (viewport, size, scale) in viewports) {
    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final brightness in Brightness.values) {
        for (final density in gitlamaDensities) {
          final golden =
              '../build/evidence/meridian/gallery-$viewport-${locale.languageCode}-${brightness.name}-${density.name}.png';
          testWidgets(
            '$viewport ${locale.languageCode} ${brightness.name} ${density.name}',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.pumpWidget(
                gallery(
                  locale: locale,
                  brightness: brightness,
                  density: density,
                  textScale: scale,
                ),
              );
              await tester.pump(const Duration(milliseconds: 100));
              expect(tester.takeException(), isNull);
              await expectLater(
                find.byType(Scaffold),
                matchesGoldenFile(golden),
              );
            },
            skip: visualCaptureSkip(golden),
          );
        }
      }
    }
  }

  for (final brightness in Brightness.values) {
    final golden =
        '../build/evidence/meridian/gallery-full-en-${brightness.name}-regular.png';
    testWidgets('full catalog en ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1280, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(gallery(brightness: brightness));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(Scaffold), matchesGoldenFile(golden));
    }, skip: visualCaptureSkip(golden));
  }
}
