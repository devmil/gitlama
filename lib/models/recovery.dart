import 'settings.dart';

enum PreviousShutdown { clean, unclean }

enum RecoveryFailureCode {
  io,
  locked,
  alreadyRunning,
  notRunning,
  invalidCheckpoint,
  unsafeGitState,
  notRepository,
}

enum SequencerKind { rebase, merge, cherryPick, revert, bisect }

final class StartupRecovery {
  const StartupRecovery({
    required this.previousShutdown,
    required this.checkpoint,
  });

  final PreviousShutdown previousShutdown;
  final SettingsDocument checkpoint;
}

final class SequencerRecoveryState {
  const SequencerRecoveryState({
    required this.kind,
    this.current,
    this.total,
    required this.indexHasConflicts,
    required this.canContinue,
    required this.canAbort,
  });

  final SequencerKind kind;
  final int? current;
  final int? total;
  final bool indexHasConflicts;
  final bool canContinue;
  final bool canAbort;
}

final class RecoveryException implements Exception {
  const RecoveryException(this.code);
  final RecoveryFailureCode code;

  @override
  String toString() => 'RecoveryException(${code.name})';
}
