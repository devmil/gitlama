import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/app/byte_size.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  test('small sizes stay in bytes', () {
    expect(formatByteSize(en, 0), '0 bytes');
    expect(formatByteSize(en, 1), '1 byte');
    expect(formatByteSize(en, 1023), '1,023 bytes');
    expect(formatByteSize(de, 1023), '1.023 Byte');
  });

  test('larger sizes use binary units, one decimal below ten', () {
    expect(formatByteSize(en, 1024), '1 KB');
    expect(formatByteSize(en, 1536), '1.5 KB');
    expect(formatByteSize(en, 48213), '47 KB');
    expect(formatByteSize(en, 1048576), '1 MB');
    expect(formatByteSize(en, 8 * 1024 * 1024 + 300 * 1024), '8.3 MB');
    expect(formatByteSize(en, 5 * 1024 * 1024 * 1024), '5 GB');
    expect(formatByteSize(en, 3 * 1024 * 1024 * 1024 * 1024), '3 TB');
  });

  test('a value that rounds up to the next unit uses that unit', () {
    expect(formatByteSize(en, 1024 * 1024 - 1), '1 MB');
    expect(formatByteSize(en, 10 * 1024 - 20), '10 KB');
  });

  test('German uses its decimal comma and grouping', () {
    expect(formatByteSize(de, 1536), '1,5 KB');
    expect(formatByteSize(de, 48213), '47 KB');
    expect(formatByteSize(de, 2000 * 1024 * 1024 * 1024 * 1024), '2.000 TB');
  });
}
