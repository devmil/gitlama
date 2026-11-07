import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../models/settings.dart';
import 'app_theme.dart';

/// The theme, density and motion every window of the application takes from
/// the appearance settings, so the main window and inspector windows match.
final class AppAppearance {
  AppAppearance(this.settings);

  final AppearanceSettings settings;

  MeridianDensity get density => switch (settings.density) {
    'compact' => MeridianDensity.compact,
    'comfortable' => MeridianDensity.comfortable,
    _ => MeridianDensity.regular,
  };

  ThemeMode get themeMode => switch (settings.theme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  ThemeData get theme => buildAppTheme(Brightness.light, density: density);

  ThemeData get darkTheme => buildAppTheme(Brightness.dark, density: density);

  /// [child] with the motion the settings choose: reduced, full, or what the
  /// system asks for.
  Widget applyMotion(BuildContext context, Widget child) {
    final media = MediaQuery.of(context);
    final disableAnimations = switch (settings.reduceMotion) {
      'reduce' => true,
      'full' => false,
      _ => media.disableAnimations,
    };
    return MediaQuery(
      data: media.copyWith(disableAnimations: disableAnimations),
      child: child,
    );
  }
}
