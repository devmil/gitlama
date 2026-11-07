import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../logging/app_logger.dart';
import '../../../logging/log_privacy.dart';
import '../../../models/remote_workspace.dart';
import 'remote_process.dart';
import 'ssh_command.dart';

/// How long an installation may take, including the upload.
const remoteHelperInstallTimeout = Duration(minutes: 10);

/// Bytes of installer output considered; the rest is discarded.
const _installOutputBytes = 4096;

/// Where release packages place the helper for [target], relative to the
/// application executable's directory.
String remoteHelperBundleDirectory({
  required String executableDirectory,
  required bool macOS,
  required bool windows,
  required RemoteHelperTarget target,
}) {
  final separator = windows ? r'\' : '/';
  final parts = macOS
      ? ['..', 'Resources', 'remote-helper', target.directory]
      : windows
      ? ['remote-helper', target.directory]
      : ['lib', 'remote-helper', target.directory];
  return [executableDirectory, ...parts].join(separator);
}

final _log = AppLogger('RemoteHelper');

/// Where the build hook of a build from source places the helper for
/// [target], relative to the checkout's `build` directory.
String developmentHelperDirectory(RemoteHelperTarget target) =>
    'remote-helper/${target.directory}';

/// Loads the helper bundled next to [executable] (the running application by
/// default) and verifies its descriptor against [buildId] and its digest.
/// A build from source, which runs from the `build` directory of its
/// checkout in debug and release mode alike, has no packaged helper and uses
/// the one its build hook placed there. Null when the build carries no helper
/// or the bundle was altered.
Future<RemoteHelperArtifact?> loadBundledHelper({
  required String buildId,
  required RemoteHelperTarget target,
  String? executable,
}) async {
  final path = executable ?? Platform.resolvedExecutable;
  final packaged = await _loadHelper(
    remoteHelperBundleDirectory(
      executableDirectory: File(path).parent.path,
      macOS: Platform.isMacOS,
      windows: Platform.isWindows,
      target: target,
    ),
    buildId,
    target,
  );
  if (packaged != null || Platform.isWindows) return packaged;
  // Installed packages never run from a `build` directory.
  for (
    var directory = File(path).parent;
    directory.parent.path != directory.path;
    directory = directory.parent
  ) {
    if (directory.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ==
        'build') {
      if (File(
        '${directory.path}/remote-helper/'
        'build-failure-${target.directory}.txt',
      ).existsSync()) {
        // build/remote-helper/build-failure-<target>.txt says why.
        _developmentResult('build_failed');
      }
      return _loadHelper(
        '${directory.path}/${developmentHelperDirectory(target)}',
        buildId,
        target,
        development: true,
      );
    }
  }
  return null;
}

/// Says in the debug console why a development helper is not offered.
void _developmentResult(String result) => _log.info(
  'development_helper_lookup',
  {'result': LogField(result, LogSensitivity.public)},
);

Future<RemoteHelperArtifact?> _loadHelper(
  String directory,
  String buildId,
  RemoteHelperTarget target, {
  bool development = false,
}) async {
  void reject(String result) {
    if (development) _developmentResult(result);
  }

  final separator = Platform.isWindows ? r'\' : '/';
  final descriptorFile = File(
    '$directory${separator}gitlama-remote-helper.json',
  );
  final binaryFile = File('$directory${separator}gitlama-remote-helper');
  try {
    if (!descriptorFile.existsSync() || !binaryFile.existsSync()) {
      reject('incomplete');
      return null;
    }
    final text = await descriptorFile.readAsString();
    final descriptor = text.length > 4096 ? null : jsonDecode(text);
    if (descriptor is! Map<String, Object?> ||
        descriptor['schema'] != 1 ||
        descriptor['target'] != target.triple) {
      reject('invalid_descriptor');
      return null;
    }
    if (descriptor['build_id'] != buildId) {
      reject('other_build');
      return null;
    }
    final bytes = await _readBounded(binaryFile);
    if (bytes == null ||
        descriptor['bytes'] != bytes.length ||
        descriptor['sha256'] != sha256.convert(bytes).toString()) {
      reject('digest_mismatch');
      return null;
    }
    if (development) _developmentResult('loaded');
    return RemoteHelperArtifact(
      buildId: buildId,
      target: target,
      sha256: descriptor['sha256']! as String,
      bytes: bytes,
    );
  } on Object {
    // An unreadable or altered bundle offers manual setup only.
    reject('unreadable');
    return null;
  }
}

Future<Uint8List?> _readBounded(File file) async {
  final length = await file.length();
  if (length < 1 || length > remoteHelperInstallLimit) return null;
  return file.readAsBytes();
}

/// Runs the fixed installation command and maps its single result line.
Future<void> runHelperInstall({
  required ProcessStarter starter,
  required String executable,
  required List<String> arguments,
  required RemoteHelperArtifact artifact,
  Future<void>? cancel,
  Duration timeout = remoteHelperInstallTimeout,
}) async {
  final RemoteProcess process;
  try {
    process = await starter(executable, arguments);
  } on ProcessException {
    throw const RemoteWorkspaceException(RemoteFailureCode.sshUnavailable);
  }
  final output = BytesBuilder(copy: false);
  final drained = process.stdout
      .listen((chunk) {
        final room = _installOutputBytes - output.length;
        if (room > 0) {
          output.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
        }
      })
      .asFuture<void>()
      .catchError((Object _) {});
  var canceled = false;
  final done = Completer<void>();
  unawaited(
    cancel?.then<void>((_) {
      canceled = true;
      if (!done.isCompleted) done.complete();
    }, onError: (Object _) {}),
  );
  const chunk = 256 * 1024;
  for (var offset = 0; offset < artifact.bytes.length; offset += chunk) {
    if (canceled) break;
    final end = offset + chunk < artifact.bytes.length
        ? offset + chunk
        : artifact.bytes.length;
    process.write(artifact.bytes.sublist(offset, end));
  }
  await process.closeStdin();
  int? status;
  unawaited(
    process.exitCode.then((code) {
      status = code;
      if (!done.isCompleted) done.complete();
    }),
  );
  await done.future.timeout(timeout, onTimeout: () {});
  if (canceled || status == null) {
    await process.terminate();
    throw RemoteWorkspaceException(
      canceled ? RemoteFailureCode.canceled : RemoteFailureCode.timedOut,
    );
  }
  await drained.timeout(const Duration(seconds: 2), onTimeout: () {});
  // Login scripts may print before the installer; only its last line counts.
  final line = latin1
      .decode(output.takeBytes())
      .split('\n')
      .map((value) => value.trim())
      .lastWhere((value) => value.isNotEmpty, orElse: () => '');
  const prefix = 'GITLAMA-INSTALL 1 ';
  if (status == 0 && line == '${prefix}installed') return;
  throw RemoteWorkspaceException(switch (line) {
    '${prefix}platform' => RemoteFailureCode.unsupportedPlatform,
    '${prefix}directory' => RemoteFailureCode.installDirectory,
    '${prefix}write' => RemoteFailureCode.installWrite,
    '${prefix}digest' => RemoteFailureCode.installDigest,
    '${prefix}execute' => RemoteFailureCode.installExecute,
    '' when status == 255 => RemoteFailureCode.sshConnectionFailed,
    _ => RemoteFailureCode.installFailed,
  });
}
