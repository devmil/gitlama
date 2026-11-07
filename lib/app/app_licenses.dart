import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const gitlamaLicenseAssets = <({String path, List<String> packages})>[
  (path: 'LICENSE', packages: ['GitLama', 'QSpline', 'devmil-git']),
  (path: 'THIRD_PARTY_NOTICES.md', packages: ['GitLama notices']),
  (path: 'assets/fonts/OFL.txt', packages: ['JetBrains Mono']),
  (
    path: 'assets/licenses/FLUTTER-DEPENDENCIES.md',
    packages: ['Flutter production dependencies'],
  ),
  (
    path: 'assets/licenses/RUST-DEPENDENCIES.md',
    packages: ['Rust production dependencies'],
  ),
  (path: 'assets/licenses/SYNTAX-GRAMMARS.md', packages: ['Syntax grammars']),
];

var _registered = false;

void registerGitLamaLicenses({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  final source = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final document in gitlamaLicenseAssets) {
      final text = await source.loadString(document.path);
      yield LicenseEntryWithLineBreaks(document.packages, text);
    }
  });
}
