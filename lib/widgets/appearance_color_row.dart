import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../models/repository_appearance.dart';
import 'repository_icon.dart';

/// The colour picker's strings in the app's language.
MeridianColorPickerLabels colorPickerLabels(BuildContext context) {
  final l10n = context.l10n;
  return MeridianColorPickerLabels(
    wheel: l10n.colorPickerWheel,
    hue: l10n.colorPickerHue,
    saturation: l10n.colorPickerSaturation,
    brightness: l10n.colorPickerBrightness,
    red: l10n.colorPickerRed,
    green: l10n.colorPickerGreen,
    blue: l10n.colorPickerBlue,
    hsv: l10n.colorPickerHsb,
    rgb: l10n.colorPickerRgb,
    channels: l10n.colorPickerModel,
    hex: l10n.colorPickerHex,
    invalidHex: l10n.colorPickerInvalidHex,
    original: l10n.colorPickerOriginal,
    current: l10n.colorPickerNew,
    swatch: l10n.colorPickerSwatch,
    degrees: l10n.colorPickerDegrees,
    percent: l10n.colorPickerPercent,
  );
}

/// The theme's palette as swatches, then a well for any other colour: an
/// [AppearanceColor] choice on Meridian's [MeridianColorChoiceRow].
///
/// [value] is the chosen colour; `null` is "no colour", offered as a first
/// swatch only when [noneLabel] is given. Palette colours are the theme's
/// series colours in [RepositoryAppearanceColor] order.
class AppearanceColorRow extends StatelessWidget {
  const AppearanceColorRow({
    required this.value,
    required this.onChanged,
    super.key,
    this.noneLabel,
  });

  final AppearanceColor? value;

  /// `null` disables the row.
  final ValueChanged<AppearanceColor?>? onChanged;

  /// Names the "no colour" swatch; without it there is none.
  final String? noneLabel;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MeridianColorChoiceRow(
      value: switch (value) {
        PaletteColor(:final value) => MeridianSeriesColor(value.index),
        final CustomColor custom => MeridianCustomColor(
          repositoryAppearanceColor(context, custom),
        ),
        null => null,
      },
      allowNone: noneLabel != null,
      noneLabel: noneLabel,
      customLabel: context.l10n.repositoryColorCustom,
      seriesLabels: [
        for (final color in RepositoryAppearanceColor.values)
          paletteColorLabel(context, color),
      ],
      pickerLabels: colorPickerLabels(context),
      onChanged: onChanged == null
          ? null
          : (choice) => onChanged(switch (choice) {
              MeridianSeriesColor(:final index) => PaletteColor(
                RepositoryAppearanceColor.values[index],
              ),
              MeridianCustomColor(:final color) => CustomColor(
                color.toARGB32(),
              ),
              null => null,
            }),
    );
  }
}

/// Names one choice in an appearance dialog (symbol, colour, image).
class AppearanceHeading extends StatelessWidget {
  const AppearanceHeading(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MeridianSpace.space3),
    child: Text(
      label,
      style: context.text.label.copyWith(color: context.colors.inkMuted),
    ),
  );
}
