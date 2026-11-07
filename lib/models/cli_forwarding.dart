import 'settings.dart';

enum CliStartupState { owner, forwarded, rejected }

enum CliForwardingFailureCode {
  unsupportedPlatform,
  invalidArguments,
  notRunning,
  authentication,
  versionSkew,
  invalidPath,
  notRepository,
  busy,
  precondition,
  transport,
}

final class CliStartupResult {
  const CliStartupResult({required this.state, this.failure});

  final CliStartupState state;
  final CliForwardingFailureCode? failure;
}

enum CliForwardedCommandKind {
  activate,
  openRepository,
  openRemoteRepository,
  refresh,
  fetch,
  pull,
}

enum CliPullStrategy { fastForwardOnly, fastForwardIfPossible, rebase }

final class CliForwardedCommand {
  const CliForwardedCommand({
    required this.requestId,
    required this.kind,
    this.path,
    this.pullStrategy,
    this.remoteAlias,
  });

  final BigInt requestId;
  final CliForwardedCommandKind kind;

  /// The repository to open: on this computer, or for
  /// [CliForwardedCommandKind.openRemoteRepository] the absolute POSIX path
  /// on the host [remoteAlias] names, with no remote authority yet.
  final NativePathIdentity? path;
  final CliPullStrategy? pullStrategy;

  /// The SSH alias of the saved host a remote open names.
  final String? remoteAlias;
}

enum CliForwardingResponse {
  accepted,
  precondition,
  busy,
  unsupported,
  internal,
}

final class CliForwardingException implements Exception {
  const CliForwardingException(this.code);

  final CliForwardingFailureCode code;
}
