import 'dart:async';
import 'dart:io';

import '../../../models/remote_workspace.dart';
import '../../remote_connection_repository.dart';
import 'protocol_messages.dart';
import 'remote_helper_install.dart';
import 'remote_channel_impl.dart';
import '../native_child_process_repository.dart';
import 'remote_process.dart';
import 'remote_timers.dart';
import 'ssh_command.dart';

/// Finds the OpenSSH client; null when none is installed.
typedef SshExecutableResolver = String? Function();

String? _resolveInstalledSsh() => resolveSshExecutable(
  windows: Platform.isWindows,
  environment: Platform.environment,
  currentDirectory: Directory.current.path,
  isFile: (path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.file,
);

/// Loads the helper this application can install; null when none.
typedef RemoteHelperLoader =
    Future<RemoteHelperArtifact?> Function(RemoteHelperTarget target);

/// The Dart VM reaps every child of the process while a `dart:io` process
/// runs on macOS and Linux, so the core's Git commands would lose their exit
/// status during a remote connection. There the core owns the SSH processes;
/// Windows keeps `dart:io`, which waits only for its own children.
Future<RemoteProcess> _defaultStarter(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Platform.isWindows
    ? startIoRemoteProcess(executable, arguments, environment: environment)
    : startNativeRemoteProcess(executable, arguments, environment: environment);

Future<String?> _defaultVersionReader(String executable) => Platform.isWindows
    ? readSshVersion(executable)
    : readNativeSshVersion(
        executable,
        timeout: sshVersionProbeTimeout,
        maximumBytes: sshVersionProbeBytes,
      );

/// Reaches a remote helper through the installed OpenSSH client with the
/// fixed argument array and launch command.
final class SshRemoteConnectionRepository
    implements RemoteConnectionRepository {
  SshRemoteConnectionRepository(
    this.buildId, {
    ProcessStarter? starter,
    SshVersionReader? versionReader,
    SshExecutableResolver? resolveExecutable,
    this._timer = systemRemoteTimer,
    this._offload = isolateOffload,
    this._qualificationConfig,
    this._helperLoader,
    this._installTimeout = remoteHelperInstallTimeout,
  }) : _starter = starter ?? _defaultStarter,
       _versionReader = versionReader ?? _defaultVersionReader,
       _resolveExecutable = resolveExecutable ?? _resolveInstalledSsh {
    if (!isValidBuildId(buildId)) {
      throw ArgumentError.value('<redacted>', 'buildId', 'not a build ID');
    }
  }

  /// The helper ID the helper must report: its compatibility version.
  final String buildId;
  final ProcessStarter _starter;
  final SshVersionReader _versionReader;
  final SshExecutableResolver _resolveExecutable;
  final RemoteTimerFactory _timer;
  final RemoteOffload _offload;

  /// An isolated SSH configuration for loopback qualification fixtures only.
  final String? _qualificationConfig;
  final RemoteHelperLoader? _helperLoader;
  final Duration _installTimeout;

  /// The verified client, kept after a successful probe only.
  String? _verifiedExecutable;

  @override
  Future<String?> helperBuildId() async => buildId;

  @override
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target) async {
    final artifact =
        await (_helperLoader?.call(target) ??
            loadBundledHelper(buildId: buildId, target: target));
    return artifact?.buildId == buildId && artifact?.target == target
        ? artifact
        : null;
  }

  @override
  Future<void> installHelper({
    required String alias,
    required RemoteHelperArtifact artifact,
    Future<void>? cancel,
  }) async {
    if (artifact.buildId != buildId) {
      throw const RemoteWorkspaceException(
        RemoteFailureCode.installUnavailable,
      );
    }
    final arguments = sshInstallArguments(
      alias,
      artifact.buildId,
      artifact.sha256,
      artifact.target,
      configFile: _qualificationConfig,
    );
    final executable = await _sshExecutable();
    await runHelperInstall(
      starter: _starter,
      executable: executable,
      arguments: arguments,
      artifact: artifact,
      cancel: cancel,
      timeout: _installTimeout,
    );
  }

  @override
  Future<RemoteChannel> open({
    required String alias,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    void Function(RemoteConnectionPhase phase)? onPhase,
  }) async {
    final arguments = sshArguments(
      alias,
      buildId,
      configFile: _qualificationConfig,
    );
    var canceled = false;
    if (cancel != null) {
      unawaited(
        cancel.then<void>(
          (_) => canceled = true,
          onError: (Object _) => canceled = true,
        ),
      );
    }
    void checkCanceled() {
      if (canceled) {
        throw const RemoteWorkspaceException(RemoteFailureCode.canceled);
      }
    }

    onPhase?.call(RemoteConnectionPhase.connecting);
    final executable = await _sshExecutable();
    checkCanceled();
    final RemoteProcess process;
    try {
      process = await _starter(executable, arguments);
    } on ProcessException {
      throw const RemoteWorkspaceException(RemoteFailureCode.sshUnavailable);
    }
    if (canceled) {
      await process.terminate();
      checkCanceled();
    }
    onPhase?.call(RemoteConnectionPhase.handshaking);
    return RemoteChannelImpl.connect(
      process: process,
      buildId: buildId,
      capabilities: capabilities,
      cancel: cancel,
      timer: _timer,
      offload: _offload,
    );
  }

  Future<String> _sshExecutable() async {
    final known = _verifiedExecutable;
    if (known != null) return known;
    final executable = _resolveExecutable();
    if (executable == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.sshUnavailable);
    }
    final version = await _versionReader(executable);
    if (version == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.sshUnavailable);
    }
    if (!isSupportedOpenSsh(version)) {
      throw const RemoteWorkspaceException(RemoteFailureCode.sshUnsupported);
    }
    return _verifiedExecutable = executable;
  }
}
