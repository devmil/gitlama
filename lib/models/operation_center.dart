import 'activity.dart';
import 'repository_state.dart';
import 'operation_failure.dart';

enum OperationCenterState {
  running,
  attention,
  warning,
  succeeded,
  failed,
  canceled,
}

enum OperationCenterOrigin { user, background }

enum OperationCenterAction {
  refresh,
  initialize,
  clone,
  fetch,
  pull,
  push,
  other,
}

final class OperationCenterEntry {
  const OperationCenterEntry({
    this.activityId,
    this.session,
    this.cloneAttemptId,
    required this.state,
    required this.origin,
    required this.action,
    required this.startedAtUnixMs,
    required this.canCancel,
    required this.canRetry,
    required this.hasDetails,
    this.finishedAtUnixMs,
    this.progress,
    this.userFailure,
  });

  final BigInt? activityId;
  final RepositorySessionIdentity? session;
  final BigInt? cloneAttemptId;
  final OperationCenterState state;
  final OperationCenterOrigin origin;
  final OperationCenterAction action;
  final BigInt startedAtUnixMs;
  final BigInt? finishedAtUnixMs;
  final ActivityProgress? progress;
  final bool canCancel;
  final bool canRetry;
  final bool hasDetails;
  final UserOperationFailure? userFailure;

  /// Whether both entries present the same operation state.
  bool sameContent(OperationCenterEntry other) {
    final progress = this.progress;
    final otherProgress = other.progress;
    return activityId == other.activityId &&
        userFailure?.id == other.userFailure?.id &&
        session?.nativeId == other.session?.nativeId &&
        session?.generation == other.session?.generation &&
        cloneAttemptId == other.cloneAttemptId &&
        state == other.state &&
        origin == other.origin &&
        action == other.action &&
        startedAtUnixMs == other.startedAtUnixMs &&
        finishedAtUnixMs == other.finishedAtUnixMs &&
        canCancel == other.canCancel &&
        canRetry == other.canRetry &&
        hasDetails == other.hasDetails &&
        (progress == null
            ? otherProgress == null
            : otherProgress != null && progress.sameContent(otherProgress));
  }
}

final class OperationCenterSnapshot {
  const OperationCenterSnapshot({
    required this.entries,
    required this.runningCount,
    required this.failedCount,
    this.warningCount = 0,
    required this.attentionCount,
    required this.truncated,
  });

  static const empty = OperationCenterSnapshot(
    entries: [],
    runningCount: 0,
    failedCount: 0,
    warningCount: 0,
    attentionCount: 0,
    truncated: false,
  );

  final List<OperationCenterEntry> entries;
  final int runningCount;
  final int failedCount;
  final int warningCount;
  final int attentionCount;
  final bool truncated;

  /// Whether a poll result would present exactly what this snapshot presents.
  bool sameContent(OperationCenterSnapshot other) {
    if (identical(this, other)) return true;
    if (runningCount != other.runningCount ||
        failedCount != other.failedCount ||
        warningCount != other.warningCount ||
        attentionCount != other.attentionCount ||
        truncated != other.truncated ||
        entries.length != other.entries.length) {
      return false;
    }
    for (var index = 0; index < entries.length; index += 1) {
      if (!entries[index].sameContent(other.entries[index])) return false;
    }
    return true;
  }
}
