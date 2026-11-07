import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers every checked-in manual license document', () async {
    final bundle = _LicenseBundle();
    registerGitLamaLicenses(bundle: bundle);
    final expectedPackages = gitlamaLicenseAssets
        .expand((document) => document.packages)
        .toSet();
    final entries = await LicenseRegistry.licenses
        .where((entry) => entry.packages.any(expectedPackages.contains))
        .take(gitlamaLicenseAssets.length)
        .toList();

    expect(
      entries.expand((entry) => entry.packages),
      containsAll(expectedPackages),
    );
    expect(bundle.loaded, gitlamaLicenseAssets.map((value) => value.path));
  });
}

final class _LicenseBundle extends CachingAssetBundle {
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    return ByteData.sublistView(
      Uint8List.fromList('license for $key'.codeUnits),
    );
  }
}
