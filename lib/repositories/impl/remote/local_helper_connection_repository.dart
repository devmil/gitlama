import 'dart:async';
import 'dart:io';

import '../../../models/remote_workspace.dart';
import '../../remote_connection_repository.dart';
import 'protocol_messages.dart';
import 'remote_channel_impl.dart';
import 'remote_process.dart';
import 'remote_timers.dart';

/// Starts a local helper binary directly with `--stdio` and speaks the same
/// protocol as over SSH. For integration tests and developer runs; the alias
/// is ignored.
final class LocalHelperConnectionRepository
    implements RemoteConnectionRepository {
  LocalHelperConnectionRepository(
    this.helperExecutable,
    this.buildId, {
    this.environment,
    ProcessStarter? starter,
    this._timer = systemRemoteTimer,
    this._offload = isolateOffload,
  }) : _starter = starter ?? startIoRemoteProcess {
    if (!isValidBuildId(buildId)) {
      throw ArgumentError.value('<redacted>', 'buildId', 'not a build ID');
    }
  }

  /// An absolute path to the helper executable.
  final String helperExecutable;
  final String buildId;
  final Map<String, String>? environment;
  final ProcessStarter _starter;
  final RemoteTimerFactory _timer;
  final RemoteOffload _offload;

  @override
  Future<String?> helperBuildId() async => buildId;

  /// A directly started development helper is never installed.
  @override
  Future<RemoteHelperArtifact?> bundledHelper(
    RemoteHelperTarget target,
  ) async => null;

  @override
  Future<void> installHelper({
    required String alias,
    required RemoteHelperArtifact artifact,
    Future<void>? cancel,
  }) async => throw const RemoteWorkspaceException(
    RemoteFailureCode.installUnavailable,
  );

  @override
  Future<RemoteChannel> open({
    required String alias,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    void Function(RemoteConnectionPhase phase)? onPhase,
  }) async {
    var canceled = false;
    if (cancel != null) {
      unawaited(
        cancel.then<void>(
          (_) => canceled = true,
          onError: (Object _) => canceled = true,
        ),
      );
    }
    onPhase?.call(RemoteConnectionPhase.connecting);
    final RemoteProcess process;
    try {
      process = await _starter(helperExecutable, const [
        '--stdio',
      ], environment: environment);
    } on ProcessException {
      throw const RemoteWorkspaceException(
        RemoteFailureCode.helperNotInstalled,
      );
    }
    if (canceled) {
      await process.terminate();
      throw const RemoteWorkspaceException(RemoteFailureCode.canceled);
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
}
