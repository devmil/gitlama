import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';
import '../models/repository_appearance.dart';
import '../models/settings.dart';
import '../app/app_theme.dart';

/// The colour an appearance colour stands for in the current theme. A
/// custom colour is content: it stays the same in light and dark.
Color repositoryAppearanceColor(BuildContext context, AppearanceColor color) =>
    switch (color) {
      PaletteColor(:final value) => paletteAppearanceColor(context, value),
      CustomColor(:final rgb) => Color(rgb).withAlpha(0xFF),
    };

/// A palette colour in the current theme: its categorical series.
Color paletteAppearanceColor(
  BuildContext context,
  RepositoryAppearanceColor color,
) => context.colors.series[color.index];

/// The colour's name, for menus and accessibility labels.
String repositoryColorLabel(BuildContext context, AppearanceColor color) =>
    switch (color) {
      PaletteColor(:final value) => paletteColorLabel(context, value),
      CustomColor(:final hex) => context.l10n.repositoryColorCustomValue(hex),
    };

/// A palette colour's name.
String paletteColorLabel(
  BuildContext context,
  RepositoryAppearanceColor color,
) {
  final l10n = context.l10n;
  return switch (color) {
    RepositoryAppearanceColor.blue => l10n.repositoryColorBlue,
    RepositoryAppearanceColor.teal => l10n.repositoryColorTeal,
    RepositoryAppearanceColor.amber => l10n.repositoryColorAmber,
    RepositoryAppearanceColor.orange => l10n.repositoryColorOrange,
    RepositoryAppearanceColor.rose => l10n.repositoryColorRose,
    RepositoryAppearanceColor.violet => l10n.repositoryColorViolet,
    RepositoryAppearanceColor.cyan => l10n.repositoryColorCyan,
    RepositoryAppearanceColor.olive => l10n.repositoryColorOlive,
  };
}

/// A repository's mark in its tab: the custom [image] when it could be read,
/// else the chosen icon in the chosen colour, else a colour dot. Nothing
/// when the repository has no appearance.
class RepositoryIcon extends StatelessWidget {
  const RepositoryIcon({
    required this.appearance,
    this.image,
    this.fallbackColor,
    super.key,
  });

  final RepositoryAppearance? appearance;
  final RepositoryIconImage? image;

  /// The icon colour when the appearance names none.
  final Color? fallbackColor;

  static bool shows(RepositoryAppearance? appearance) =>
      appearance != null && appearance.hasMark;

  @override
  Widget build(BuildContext context) {
    final appearance = this.appearance;
    if (!shows(appearance)) return const SizedBox.shrink();
    final meridian = context.meridian;
    final size = meridian.density.iconSmallSize;
    final color = AppearanceColor.byKey(appearance!.color);
    final tint = color == null
        ? fallbackColor ?? meridian.colors.inkMuted
        : repositoryAppearanceColor(context, color);
    final image = this.image;
    final Widget mark;
    if (image != null) {
      mark = ClipRRect(
        borderRadius: BorderRadius.circular(meridian.radius.xs),
        child: switch (image.format) {
          RepositoryIconFormat.svg => SvgPicture.memory(
            image.bytes,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
          RepositoryIconFormat.raster => Image.memory(
            image.bytes,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                _Dot(color: tint, size: size),
          ),
        },
      );
    } else if (appearance.icon case final icon?
        when repositoryAppearanceIcons.contains(icon)) {
      mark = MeridianIcon(icon, size: MeridianIconSize.small, color: tint);
    } else {
      mark = _Dot(color: tint, size: size);
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        key: const ValueKey('repository-icon'),
        dimension: size,
        child: Center(child: mark),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size / 2,
    height: size / 2,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
