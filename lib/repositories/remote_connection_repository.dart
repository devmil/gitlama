import '../models/remote_workspace.dart';

/// A call failed with a typed protocol code. Carries no received text.
final class RemoteCallException implements Exception {
  const RemoteCallException(this.code);
  final RemoteErrorCode code;

  @override
  String toString() => 'RemoteCallException(${code.name})';
}

/// One `sessionEvents` publication.
final class RemotePublication {
  const RemotePublication({required this.sessionId, required this.events});

  /// The helper-local session ID.
  final BigInt sessionId;

  /// The raw decoded JSON value of the `NativeRepositoryEventsResult`.
  final Object? events;
}

/// One handshaken connection to a remote helper.
abstract interface class RemoteChannel {
  /// The validated hello and the negotiated capabilities.
  RemoteHelperInfo get helper;

  Stream<RemotePublication> get publications;

  /// Completes once when the channel becomes unusable: null for an orderly
  /// close the client requested, otherwise the failure.
  Future<RemoteFailureCode?> get closed;

  bool get isOpen;

  /// Sends a call and completes with the decoded `ok` JSON value or throws a
  /// [RemoteCallException]. [bulk] selects the 120 second deadline instead of
  /// 30 seconds.
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  });

  /// Graceful shutdown, bounded, followed by process termination.
  Future<void> close();
}

abstract interface class RemoteConnectionRepository {
  /// The helper for [target] bundled with this application, verified against
  /// its build, platform and digest; null when this build carries none.
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target);

  /// Copies [artifact] to [alias] through a fixed installation command and
  /// verifies it there. Only an explicit user action calls this. Failures
  /// throw [RemoteWorkspaceException] with an `install…`, `sshConnectionFailed`,
  /// `unsupportedPlatform` or `canceled` code.
  Future<void> installHelper({
    required String alias,
    required RemoteHelperArtifact artifact,
    Future<void>? cancel,
  });

  /// The build ID a helper must report, which also names its install
  /// directory; null when this build has none.
  Future<String?> helperBuildId();

  /// Starts the transport for [alias] and completes the handshake.
  ///
  /// When [cancel] completes before the handshake finishes, the process is
  /// terminated and a [RemoteWorkspaceException] with
  /// [RemoteFailureCode.canceled] is thrown. [onPhase] reports
  /// [RemoteConnectionPhase.connecting] and
  /// [RemoteConnectionPhase.handshaking]. Every failure before a usable
  /// channel is a [RemoteWorkspaceException].
  Future<RemoteChannel> open({
    required String alias,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    void Function(RemoteConnectionPhase phase)? onPhase,
  });
}
