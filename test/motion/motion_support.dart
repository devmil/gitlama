import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';

/// [child] in GitLama's theme on a Meridian ground, with reduce motion
/// on or off and a fresh motion memory.
Widget motionHost(
  Widget child, {
  bool reduced = false,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: app!,
  ),
  home: MeridianGround(child: MeridianMotionScope(child: child)),
);

/// Pumps [total] in 16 ms frames, so tickers started along the way run.
Future<void> pumpFrames(WidgetTester tester, Duration total) async {
  var left = total;
  const frame = Duration(milliseconds: 16);
  while (left > Duration.zero) {
    final step = left < frame ? left : frame;
    await tester.pump(step);
    left -= step;
  }
}
