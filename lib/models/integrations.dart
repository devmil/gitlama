import 'settings.dart';

enum IntegrationKind {
  editor,
  terminal,
  fileManager,
  browser,
  diffTool,
  mergeTool,
  custom,
}

enum IntegrationExecution { direct, explicitShell }

enum IntegrationLaunchMode { detached, wait }

final class IntegrationDefinition {
  const IntegrationDefinition({
    required this.id,
    required this.kind,
    required this.executable,
    required this.arguments,
    this.execution = IntegrationExecution.direct,
    this.launchMode = IntegrationLaunchMode.detached,
    this.requiresConfirmation = false,
    this.timeoutSeconds = 30,
  });

  final String id;
  final IntegrationKind kind;
  final NativePathIdentity executable;
  final List<String> arguments;
  final IntegrationExecution execution;
  final IntegrationLaunchMode launchMode;
  final bool requiresConfirmation;
  final int timeoutSeconds;
}

final class IntegrationVariables {
  const IntegrationVariables({
    this.url,
    this.file,
    this.currentBranch,
    this.selectedCommit,
    this.diffLeft,
    this.diffRight,
    this.mergeBase,
    this.mergeCurrent,
    this.mergeIncoming,
    this.mergeResult,
  });

  final String? url;
  final NativePathIdentity? file;
  final List<int>? currentBranch;
  final String? selectedCommit;
  final NativePathIdentity? diffLeft;
  final NativePathIdentity? diffRight;
  final NativePathIdentity? mergeBase;
  final NativePathIdentity? mergeCurrent;
  final NativePathIdentity? mergeIncoming;
  final NativePathIdentity? mergeResult;
}

final class IntegrationRequest {
  const IntegrationRequest({
    required this.kind,
    this.discoveredId,
    this.configured,
    this.variables = const IntegrationVariables(),
  });

  final IntegrationKind kind;
  final String? discoveredId;
  final IntegrationDefinition? configured;
  final IntegrationVariables variables;
}

final class IntegrationCandidate {
  const IntegrationCandidate({
    required this.id,
    required this.kind,
    required this.executable,
    required this.launchMode,
  });

  final String id;
  final IntegrationKind kind;
  final NativePathIdentity executable;
  final IntegrationLaunchMode launchMode;
}

enum IntegrationFailureCode {
  invalidRequest,
  unavailable,
  missingVariable,
  stale,
  confirmationRequired,
  canceled,
  timedOut,
  nonZeroExit,
  launch,
  read,
}

final class IntegrationPreview {
  const IntegrationPreview({
    required this.token,
    required this.kind,
    required this.definitionId,
    required this.executable,
    required this.arguments,
    required this.explicitShell,
    required this.waitsForExit,
    required this.requiresConfirmation,
  });

  final BigInt token;
  final IntegrationKind kind;
  final String definitionId;
  final String executable;
  final List<String> arguments;
  final bool explicitShell;
  final bool waitsForExit;
  final bool requiresConfirmation;
}

enum IntegrationExecutionState {
  completed,
  detached,
  failed,
  canceled,
  timedOut,
  stale,
}

final class IntegrationExecutionResult {
  const IntegrationExecutionResult({
    required this.state,
    this.activityId,
    this.processId,
    this.failure,
  });

  final IntegrationExecutionState state;
  final String? activityId;
  final int? processId;
  final IntegrationFailureCode? failure;
}

final class IntegrationException implements Exception {
  const IntegrationException(this.code);

  final IntegrationFailureCode code;
}
