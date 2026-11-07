import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/widgets/image_diff_view.dart';

Future<void> _pump(WidgetTester tester, ImageDiffContent content) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ImageDiffComparison(content: content)),
      ),
    );

void main() {
  testWidgets('a decode failure says why once instead of two empty sides', (
    tester,
  ) async {
    await _pump(
      tester,
      const ImageDiffContent(failure: ImageDecodeFailure.unsupported),
    );
    expect(find.text('This image could not be decoded safely.'), findsOne);
    expect(find.textContaining('SVGs without text'), findsOne);
    expect(find.text('No image exists on this side.'), findsNothing);
    expect(find.text('Side by side'), findsNothing);
  });

  testWidgets('a new image compares against a missing old side', (
    tester,
  ) async {
    await _pump(
      tester,
      const ImageDiffContent(
        newImage: DecodedImageContent(
          width: 1,
          height: 1,
          rgba: [255, 0, 0, 255],
        ),
      ),
    );
    expect(find.text('Side by side'), findsOne);
    expect(find.text('No image exists on this side.'), findsOne);
  });

  testWidgets('each side shows its pixel dimensions and file size', (
    tester,
  ) async {
    await _pump(
      tester,
      const ImageDiffContent(
        old: DecodedImageContent(
          width: 1,
          height: 1,
          rgba: [255, 0, 0, 255],
          encodedBytes: 512,
        ),
        newImage: DecodedImageContent(
          width: 2,
          height: 1,
          rgba: [255, 0, 0, 255, 0, 255, 0, 255],
          encodedBytes: 2048,
        ),
      ),
    );
    expect(find.text('Before: 1 × 1 px · 512 bytes'), findsOne);
    expect(find.text('After: 2 × 1 px · 2 KB'), findsOne);

    // Stacked modes list both sides once instead of overlapping labels.
    await tester.tap(find.text('Swipe'));
    await tester.pumpAndSettle();
    expect(find.text('Before: 1 × 1 px · 512 bytes'), findsOne);
    expect(find.text('After: 2 × 1 px · 2 KB'), findsOne);
  });

  testWidgets('a side without a reported file size shows its dimensions', (
    tester,
  ) async {
    await _pump(
      tester,
      ImageDiffContent(
        newImage: DecodedImageContent(
          width: 3,
          height: 4,
          rgba: [
            for (var i = 0; i < 12; i++) ...[0, 0, 0, 255],
          ],
        ),
      ),
    );
    expect(find.text('After: 3 × 4 px'), findsOne);
    expect(find.text('Before'), findsOne);
  });
}
