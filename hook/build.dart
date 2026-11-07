import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final target = switch ((
      input.config.code.targetOS,
      input.config.code.targetArchitecture,
    )) {
      (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
      (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
      (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
      (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
      _ => throw UnsupportedError('Unsupported GitLama desktop target'),
    };
    final root = input.packageRoot.toFilePath();
    final release = input.config.linkingEnabled;
    final environment = Map<String, String>.of(Platform.environment);
    // Hooks preserve CARGO_* but intentionally drop scoped GIT_CONFIG_*.
    // Only our prefetched workspace goes offline; independent Cargokit
    // plugins keep their normal authenticated dependency resolution.
    if (environment['CARGO_GITLAMA_PREFETCHED'] == 'true') {
      environment['CARGO_NET_OFFLINE'] = 'true';
    }
    if (input.config.code.targetOS == OS.macOS) {
      final sdk = await Process.run('xcrun', const [
        '--sdk',
        'macosx',
        '--show-sdk-path',
      ]);
      if (sdk.exitCode != 0) {
        throw StateError('macos_sdk_unavailable');
      }
      environment['SDKROOT'] = (sdk.stdout as String).trim();
      environment['MACOSX_DEPLOYMENT_TARGET'] = '13.0';
    }
    final result = await Process.run(
      'cargo',
      [
        'build',
        '--manifest-path',
        '$root/rust-core/Cargo.toml',
        '--locked',
        '--target',
        target,
        if (release) '--release',
      ],
      workingDirectory: root,
      environment: environment,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'cargo',
        const [],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    final name = switch (input.config.code.targetOS) {
      OS.macOS => 'libgitlama_core.dylib',
      OS.linux => 'libgitlama_core.so',
      OS.windows => 'gitlama_core.dll',
      _ => throw UnsupportedError('Unsupported library format'),
    };
    final library = File(
      '${_targetRoot(root)}/$target/'
      '${release ? 'release' : 'debug'}/$name',
    );
    final bundled = File.fromUri(input.outputDirectory.resolve(name));
    await library.copy(bundled.path);
    output.dependencies.addAll([
      input.packageRoot.resolve('rust-core/Cargo.toml'),
      input.packageRoot.resolve('rust-core/Cargo.lock'),
      input.packageRoot.resolve('rust-core/contract/Cargo.toml'),
      input.packageRoot.resolve('rust-core/application/Cargo.toml'),
      input.packageRoot.resolve('rust-core/application/build.rs'),
      // The remote helper ID is its compatibility version.
      input.packageRoot.resolve('rust-core/remote-helper/COMPATIBILITY'),
      input.packageRoot.resolve('VERSION'),
      input.packageRoot.resolve('rust-toolchain.toml'),
      input.packageRoot.resolve('.cargo/config.toml'),
      input.packageRoot.resolve('hook/build.dart'),
      // The library's three crates: the desktop adapter, the application
      // and the bridge contract. Test fixtures are compiled into tests only.
      for (final crate in const ['src', 'application/src', 'contract/src'])
        ...Directory(
          '$root/rust-core/$crate',
        ).listSync(recursive: true).whereType<File>().map((file) => file.uri),
      // The library records the checked-out commit for diagnostics.
      ...await _gitHeadFiles(root),
    ]);
    // Builds from source, debug or release; packaging turns this off and
    // bundles the helper of the release baseline instead.
    if ((input.config.code.targetOS == OS.macOS ||
            input.config.code.targetOS == OS.linux) &&
        Platform.environment['GITLAMA_DEV_REMOTE_HELPER'] != '0') {
      output.dependencies.addAll([
        input.packageRoot.resolve('rust-core/remote-helper/Cargo.toml'),
        ...Directory(
          '$root/rust-core/remote-helper/src',
        ).listSync(recursive: true).whereType<File>().map((file) => file.uri),
      ]);
      if (input.config.code.targetOS == OS.macOS) {
        // A Mac builds the helper for its own chip natively and the Linux
        // one with cargo-zigbuild.
        final arm = input.config.code.targetArchitecture == Architecture.arm64;
        await _bundleDevelopmentHelper(
          root,
          directory: arm ? 'macos-arm64' : 'macos-x86_64',
          triple: arm ? 'aarch64-apple-darwin' : 'x86_64-apple-darwin',
          environment: environment,
        );
        // The release floor, so the helpers run on every supported host.
        await _bundleDevelopmentHelper(
          root,
          directory: 'linux-x86_64',
          triple: 'x86_64-unknown-linux-gnu',
          zigTarget: 'x86_64-unknown-linux-gnu.2.35',
        );
        await _bundleDevelopmentHelper(
          root,
          directory: 'linux-arm64',
          triple: 'aarch64-unknown-linux-gnu',
          zigTarget: 'aarch64-unknown-linux-gnu.2.35',
        );
      } else {
        await _bundleDevelopmentHelper(
          root,
          directory: 'linux-x86_64',
          triple: 'x86_64-unknown-linux-gnu',
        );
        // A cross linker with its glibc builds the arm64 helper; zig otherwise.
        final crossLinker = await _onPath('aarch64-linux-gnu-gcc');
        await _bundleDevelopmentHelper(
          root,
          directory: 'linux-arm64',
          triple: 'aarch64-unknown-linux-gnu',
          zigTarget: crossLinker ? null : 'aarch64-unknown-linux-gnu.2.35',
          environment: crossLinker
              ? {
                  ...Platform.environment,
                  'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER':
                      'aarch64-linux-gnu-gcc',
                  'CC_aarch64_unknown_linux_gnu': 'aarch64-linux-gnu-gcc',
                }
              : null,
        );
      }
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'gitlama_core',
        file: bundled.uri,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

/// Builds the remote helper of this checkout for [triple] into
/// `build/remote-helper/<directory>`, where builds from source offer to
/// install it on a host of that platform. A [zigTarget] cross-compiles with
/// cargo-zigbuild. Without the tools the application still builds, and
/// connecting shows the manual setup unless a bundle of this build is
/// already there.
Future<void> _bundleDevelopmentHelper(
  String root, {
  required String directory,
  required String triple,
  String? zigTarget,
  Map<String, String>? environment,
}) async {
  const name = 'gitlama-remote-helper';
  final destination = Directory('$root/build/remote-helper/$directory');
  final descriptor = File('${destination.path}/$name.json');
  // Why the last attempt built no helper; the application reports it.
  final failure = File(
    '$root/build/remote-helper/build-failure-$directory.txt',
  );
  Future<void> fail(String reason) async {
    failure.parent.createSync(recursive: true);
    await failure.writeAsString(
      reason.length > 4096 ? reason.substring(reason.length - 4096) : reason,
    );
  }

  try {
    final buildId = await _remoteHelperId(root);
    final tool = zigTarget == null ? 'build' : 'zigbuild';
    final result = await Process.run(
      'cargo',
      [
        tool,
        '--manifest-path',
        '$root/rust-core/Cargo.toml',
        '--locked',
        '--package',
        name,
        '--profile',
        'helper-dev',
        '--target',
        zigTarget ?? triple,
      ],
      workingDirectory: root,
      environment: environment,
    );
    // A bundle left from an earlier build stays; the application checks its
    // build ID and digest before offering it.
    if (buildId == null) {
      await fail(
        'No helper ID: rust-core/remote-helper/COMPATIBILITY has no valid '
        'version.\n',
      );
      return;
    }
    if (result.exitCode != 0) {
      await fail(
        'cargo $tool exited with ${result.exitCode}.\n${result.stderr}',
      );
      return;
    }
    final bytes = await File(
      '${_targetRoot(root)}/$triple/helper-dev/$name',
    ).readAsBytes();
    destination.createSync(recursive: true);
    // The descriptor is written last: a bundle without one is never offered.
    if (descriptor.existsSync()) descriptor.deleteSync();
    await File('${destination.path}/$name').writeAsBytes(bytes, flush: true);
    await descriptor.writeAsString(
      '${jsonEncode({'schema': 1, 'build_id': buildId, 'target': triple, 'sha256': sha256.convert(bytes).toString(), 'bytes': bytes.length})}\n',
      flush: true,
    );
    if (failure.existsSync()) failure.deleteSync();
  } on Object catch (error) {
    // Development convenience only; never fail the application build.
    try {
      await fail(
        error is ProcessException
            ? 'cargo could not be started: ${error.message}\n'
            : 'The helper could not be bundled: ${error.runtimeType}\n',
      );
    } on Object {
      // Nothing more to report.
    }
  }
}

/// Whether [tool] is on the PATH.
/// Where cargo writes its output: `CARGO_TARGET_DIR` when CI or a developer
/// redirects it (relative to [root], where cargo runs), otherwise the
/// workspace's own `rust-core/target`.
String _targetRoot(String root) {
  final configured = Platform.environment['CARGO_TARGET_DIR'];
  if (configured == null || configured.isEmpty) return '$root/rust-core/target';
  return Directory(configured).isAbsolute ? configured : '$root/$configured';
}

Future<bool> _onPath(String tool) async {
  try {
    return (await Process.run('sh', ['-c', 'command -v $tool'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The ID the core and its helper report: the helper's compatibility version
/// as 40 decimal digits, as `rust-core/application/build.rs` derives it.
Future<String?> _remoteHelperId(String root) async {
  try {
    final text = await File(
      '$root/rust-core/remote-helper/COMPATIBILITY',
    ).readAsString();
    final version = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('version '))
        .map((line) => line.substring('version '.length).trim())
        .firstOrNull;
    if (version == null || !RegExp(r'^[1-9][0-9]{0,5}$').hasMatch(version)) {
      return null;
    }
    return version.padLeft(40, '0');
  } on FileSystemException {
    return null;
  }
}

/// HEAD and its reflog, which change with every commit or checkout.
Future<List<Uri>> _gitHeadFiles(String root) async {
  final files = <Uri>[];
  try {
    for (final reference in ['HEAD', 'logs/HEAD']) {
      final result = await Process.run('git', [
        '-C',
        root,
        'rev-parse',
        '--path-format=absolute',
        '--git-path',
        reference,
      ]);
      final path = (result.stdout as String).trim();
      if (result.exitCode == 0 && File(path).existsSync()) {
        files.add(File(path).uri);
      }
    }
  } on ProcessException {
    // Without Git the source commit is fixed; rust-core/application/build.rs
    // reports it.
  }
  return files;
}
