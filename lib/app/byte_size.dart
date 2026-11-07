import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// [bytes] for people: "512 bytes", "47 KB", "1.5 MB", "2 GB", with the
/// number format of [l10n]'s locale ("1,5 MB" in German).
///
/// Units are binary (1 KB = 1,024 bytes). Values below 10 keep one decimal,
/// larger ones none. Where precision matters (two sizes that round to the
/// same text) show the exact `l10n.byteCount` instead.
String formatByteSize(AppLocalizations l10n, int bytes) {
  if (bytes < _unit) return l10n.byteCount(bytes);
  final units = <String Function(String)>[
    l10n.sizeKilobytes,
    l10n.sizeMegabytes,
    l10n.sizeGigabytes,
    l10n.sizeTerabytes,
  ];
  var value = bytes / _unit;
  var index = 0;
  while (true) {
    final digits = value < 10 ? 1 : 0;
    final rounded = _round(value, digits);
    // 1,023.7 KB reads as 1 MB, not as 1,024 KB.
    if (rounded < _unit || index == units.length - 1) {
      final format = NumberFormat.decimalPattern(l10n.localeName)
        ..minimumFractionDigits = 0
        ..maximumFractionDigits = digits;
      return units[index](format.format(rounded));
    }
    value /= _unit;
    index++;
  }
}

const _unit = 1024;

double _round(double value, int digits) =>
    digits == 0 ? value.roundToDouble() : (value * 10).roundToDouble() / 10;
