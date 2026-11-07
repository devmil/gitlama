import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../models/diff_syntax.dart';

/// [kind] as Meridian paints it; null for plain text.
MeridianSyntaxKind? meridianSyntaxKind(DiffSyntaxKind kind) => switch (kind) {
  DiffSyntaxKind.plain => null,
  DiffSyntaxKind.comment => MeridianSyntaxKind.comment,
  DiffSyntaxKind.keyword => MeridianSyntaxKind.keyword,
  DiffSyntaxKind.string => MeridianSyntaxKind.string,
  DiffSyntaxKind.number => MeridianSyntaxKind.number,
  DiffSyntaxKind.type => MeridianSyntaxKind.type,
  DiffSyntaxKind.function => MeridianSyntaxKind.function,
  DiffSyntaxKind.variable => MeridianSyntaxKind.variable,
  DiffSyntaxKind.constant => MeridianSyntaxKind.constant,
  DiffSyntaxKind.operator => MeridianSyntaxKind.operator,
  DiffSyntaxKind.punctuation => MeridianSyntaxKind.punctuation,
  DiffSyntaxKind.attribute => MeridianSyntaxKind.attribute,
  DiffSyntaxKind.tag => MeridianSyntaxKind.tag,
};

/// [runs] without their plain ones, as Meridian paints them.
List<MeridianSyntaxRun> meridianSyntaxRuns(List<DiffSyntaxRun> runs) => [
  for (final run in runs)
    if (meridianSyntaxKind(run.kind) case final kind?)
      MeridianSyntaxRun(run.start, run.end, kind),
];

/// Palettes by surface combination: code shows a handful of fills, marks
/// and selections, so lines share a few palettes instead of rechecking
/// contrast per line.
final _palettes =
    <(MeridianSyntaxColors, Color, List<Color>), MeridianSyntaxPalette>{};

/// The palette of code painted in [colors] on every one of [backgrounds],
/// falling back to [ink] where a colour is not readable on one of them.
MeridianSyntaxPalette syntaxPalette(
  MeridianSyntaxColors colors,
  Color ink,
  List<Color> backgrounds,
) {
  for (final MapEntry(:key, :value) in _palettes.entries) {
    if (key.$1 == colors && key.$2 == ink && listEquals(key.$3, backgrounds)) {
      return value;
    }
  }
  if (_palettes.length >= 32) _palettes.remove(_palettes.keys.first);
  return _palettes[(colors, ink, List.unmodifiable(backgrounds))] =
      MeridianSyntaxPalette(colors: colors, ink: ink, backgrounds: backgrounds);
}
