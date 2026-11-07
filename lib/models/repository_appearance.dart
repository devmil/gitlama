import 'dart:convert';
import 'dart:typed_data';

/// The icons a repository tab can show (Meridian's Lucide names).
const repositoryAppearanceIcons = <String>[
  'folder-git-2',
  'code-xml',
  'square-terminal',
  'box',
  'blocks',
  'puzzle',
  'layers',
  'book-open',
  'palette',
  'image',
  'smartphone',
  'monitor',
  'server',
  'cloud',
  'zap',
  'star',
  'flag',
  'bug',
  'wand-sparkles',
  'graduation-cap',
  'shield-check',
  'chart-line',
  'house',
  'users',
];

/// The colours a repository icon can take: Meridian's categorical series,
/// in order (`series-1` … `series-8`).
enum RepositoryAppearanceColor {
  blue,
  teal,
  amber,
  orange,
  rose,
  violet,
  cyan,
  olive;

  static RepositoryAppearanceColor? byKey(String? key) {
    for (final value in values) {
      if (value.name == key) return value;
    }
    return null;
  }
}

/// A colour a repository mark or a tab group takes: a [PaletteColor] from
/// the theme's series, which follows light and dark, or a [CustomColor]
/// the user picked, which stays the same in both.
sealed class AppearanceColor {
  const AppearanceColor();

  /// The colour [key] names: a palette colour's name or `rgb-rrggbb`.
  /// `null` when it names none.
  static AppearanceColor? byKey(String? key) {
    if (key == null) return null;
    if (RepositoryAppearanceColor.byKey(key) case final palette?) {
      return PaletteColor(palette);
    }
    final custom = RegExp(r'^rgb-([0-9a-f]{6})$').firstMatch(key);
    return custom == null
        ? null
        : CustomColor(int.parse(custom.group(1)!, radix: 16));
  }

  /// How settings store the colour; [byKey] reads it back.
  String get key;
}

final class PaletteColor extends AppearanceColor {
  const PaletteColor(this.value);

  final RepositoryAppearanceColor value;

  @override
  String get key => value.name;

  @override
  bool operator ==(Object other) =>
      other is PaletteColor && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class CustomColor extends AppearanceColor {
  /// [rgb] is `0xRRGGBB`; any alpha is dropped.
  const CustomColor(int rgb) : rgb = rgb & 0xFFFFFF;

  final int rgb;

  /// `#RRGGBB`, as people read and type it.
  String get hex => '#${_digits.toUpperCase()}';

  String get _digits => rgb.toRadixString(16).padLeft(6, '0');

  @override
  String get key => 'rgb-$_digits';

  @override
  bool operator ==(Object other) => other is CustomColor && other.rgb == rgb;

  @override
  int get hashCode => rgb.hashCode;
}

enum RepositoryIconFormat { raster, svg }

/// A repository's custom image, read and bounded by its repository.
final class RepositoryIconImage {
  const RepositoryIconImage({required this.bytes, required this.format});

  final Uint8List bytes;
  final RepositoryIconFormat format;
}

/// The longest tab or group name, in UTF-8 bytes (the settings store's
/// bound).
const maxTabNameBytes = 256;

/// [name] as a tab or group name: one line, trimmed and bounded; `null`
/// when nothing is left.
String? normalizeTabName(String? name) {
  if (name == null) return null;
  var normalized = name
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f-\u009f]+'), ' ')
      .trim();
  while (utf8.encode(normalized).length > maxTabNameBytes) {
    final runes = normalized.runes.toList()..removeLast();
    normalized = String.fromCharCodes(runes).trimRight();
  }
  return normalized.isEmpty ? null : normalized;
}
