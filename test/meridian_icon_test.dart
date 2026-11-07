import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_icons.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  testWidgets('Lucide icon sizes follow the three Meridian roles', (
    tester,
  ) async {
    for (final (size, extent) in [
      (MeridianIconSize.small, 14.0),
      (MeridianIconSize.regular, 16.0),
      (MeridianIconSize.toolbar, 18.0),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Center(child: MeridianIcon('check', size: size)),
        ),
      );
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, extent);
      expect(svg.height, extent);
      expect(tester.getSize(find.byType(SvgPicture)), Size.square(extent));
    }
  });

  test('every GitLama icon alias is a licensed Lucide file in meridian_ui', () {
    const header = '<!-- @license lucide-static v1.37.0 - ISC -->';
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, Object?>;
    final meridian = (config['packages']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((package) => package['name'] == 'meridian_ui');
    final rootUri = meridian['rootUri']! as String;
    final root = Uri.file(
      '${Directory.current.path}/.dart_tool/',
    ).resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
    expect(gitlamaIconAliases, isNotEmpty);
    for (final MapEntry(key: alias, value: asset)
        in gitlamaIconAliases.entries) {
      const prefix = 'packages/meridian_ui/';
      expect(asset, startsWith(prefix), reason: alias);
      final file = File.fromUri(root.resolve(asset.substring(prefix.length)));
      expect(file.existsSync(), isTrue, reason: '$alias → $asset');
      expect(file.readAsStringSync().startsWith(header), isTrue, reason: alias);
    }
  });

  testWidgets('an alias draws its Meridian Lucide asset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Center(child: MeridianIcon('fetch')),
      ),
    );
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      'packages/meridian_ui/assets/icons/arrow-down-to-line.svg',
    );
  });
}
