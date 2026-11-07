import 'settings.dart';
import 'repository_state.dart';

final class DiffRendererDefinition {
  const DiffRendererDefinition({
    required this.id,
    required this.title,
    required this.executable,
    this.arguments = const [],
  });

  final String id;
  final String title;
  final NativePathIdentity executable;
  final List<String> arguments;
}

enum DiffRendererFailureCode {
  invalidDefinition,
  unavailable,
  invalidCapability,
  inputTooLarge,
  outputTooLarge,
  launchFailed,
  processFailed,
  timedOut,
  canceled,
  stale,
}

final class DiffRendererException implements Exception {
  const DiffRendererException(this.code);
  final DiffRendererFailureCode code;
}

final class DiffRendererPreview {
  const DiffRendererPreview({
    required this.token,
    required this.source,
    required this.title,
    required this.executable,
    required this.capabilityArguments,
    required this.arguments,
    required this.protocol,
    required this.mediaType,
    required this.inputBytes,
    required this.outputLimitBytes,
    required this.timeoutSeconds,
  });

  final BigInt token;
  final RepositorySessionIdentity source;
  final String title;
  final String executable;
  final List<String> capabilityArguments;
  final List<String> arguments;
  final String protocol;
  final String mediaType;
  final int inputBytes;
  final int outputLimitBytes;
  final int timeoutSeconds;
}

enum DiffRendererState { pending, ready, fallback, canceled }

final class DiffRendererResult {
  const DiffRendererResult({
    required this.state,
    this.title,
    this.text,
    this.accessibilityText,
    this.activityIds = const [],
    this.failure,
  });

  final DiffRendererState state;
  final String? title;
  final String? text;
  final String? accessibilityText;
  final List<String> activityIds;
  final DiffRendererFailureCode? failure;
}
