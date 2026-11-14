import 'package:flutter/widgets.dart';
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

  MeridianThemeMode get themeMode => switch (settings.theme) {
    'light' => MeridianThemeMode.light,
    'dark' => MeridianThemeMode.dark,
    _ => MeridianThemeMode.system,
  };

  MeridianTheme get theme => buildAppTheme(Brightness.light, density: density);

  MeridianTheme get darkTheme =>
      buildAppTheme(Brightness.dark, density: density);

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
