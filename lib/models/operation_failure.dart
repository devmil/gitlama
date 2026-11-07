import 'app_update.dart';
import 'diff.dart';
import 'repository_state.dart';
import 'host_platform.dart';
import 'remote_workspace.dart';
import 'transfer.dart';

enum UserOperationKind {
  operation,
  stage,
  unstage,
  discard,
  commit,
  refs,
  transfer,
  history,
  conflict,
  indexLock,
}

/// Only typed, allowlisted facts enter a support report. User-facing messages are
/// deliberately excluded because they may contain repository names or other user data.
final class OperationFailureDetails {
  const OperationFailureDetails({
    this.operation = UserOperationKind.operation,
    this.staging,
    this.repository,
    this.unexpected = false,
    this.remote,
    this.outcomeUnknown = false,
    this.transfer,
    this.transferDiagnosis,
    this.activity,
  });

  final UserOperationKind operation;
  final StagingDiagnostic? staging;
  final RepositoryFailureCode? repository;
  final bool unexpected;
  final RemoteFailureCode? remote;
  final bool outcomeUnknown;
  final TransferFailureCode? transfer;
  final TransferDiagnosisKind? transferDiagnosis;

  /// The Git command that failed, whose output the failure dialog offers.
  /// Only its number enters the report.
  final ({RepositorySessionIdentity session, BigInt id})? activity;

  String report({InstalledRelease? release, required HostPlatform platform}) {
    final diagnostic = staging;
    return [
      'GitLama support report',
      'Format: 1',
      if (release != null &&
          RegExp(r'^[0-9A-Za-z.+-]+$').hasMatch(release.version))
        'Version: ${release.version}',
      if (release != null) 'Build: ${release.build}',
      'Platform: ${platform.name}',
      'Operation: ${operation.name}',
      if (diagnostic?.gitVersion != null &&
          RegExp(r'^\d+\.\d+\.\d+$').hasMatch(diagnostic!.gitVersion!))
        'Git: ${diagnostic.gitVersion}',
      'Code: ${diagnostic != null
          ? 'staging.${diagnostic.code.name}'
          : repository != null
          ? 'repository.${repository!.name}'
          : remote != null
          ? 'remote.${remote!.name}'
          : transfer != null
          ? 'transfer.${transfer!.name}'
          : outcomeUnknown
          ? 'operation.outcomeUnknown'
          : unexpected
          ? 'operation.unexpected'
          : 'operation.failed'}',
      if (transferDiagnosis case final diagnosis?)
        'Diagnosis: ${diagnosis.name}',
      if ((diagnostic?.activityId ?? activity?.id) case final id?)
        'Activity: $id',
      if (diagnostic?.exitCode != null) 'Exit code: ${diagnostic!.exitCode}',
    ].join('\n');
  }
}

/// Retained in the in-memory Logbook until dismissed or evicted. The localized
/// message is for display only, and never enters copied diagnostics.
final class UserOperationFailure {
  const UserOperationFailure({
    required this.id,
    required this.message,
    required this.details,
  });
  final BigInt id;
  final String message;
  final OperationFailureDetails details;
}
