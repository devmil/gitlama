import 'dart:typed_data';

enum ActivityStatus {
  running,
  succeeded,
  failed,
  canceled,
  timedOut,
  launchError,
}

final class ActivityProgress {
  const ActivityProgress({
    required this.phase,
    required this.completed,
    this.total,
    required this.unit,
  });

  final String phase;
  final BigInt completed;
  final BigInt? total;
  final String unit;

  bool sameContent(ActivityProgress other) =>
      phase == other.phase &&
      completed == other.completed &&
      total == other.total &&
      unit == other.unit;
}

/// User-selectable command content. Never send instances to diagnostic logging.
final class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.executable,
    required this.arguments,
    required this.startedAtUnixMs,
    this.finishedAtUnixMs,
    required this.status,
    this.exitCode,
    required this.stdout,
    required this.stdoutTotalBytes,
    required this.stdoutTruncated,
    required this.stderr,
    required this.stderrTotalBytes,
    required this.stderrTruncated,
    this.progress,
  });

  final BigInt id;
  final String executable;
  final List<String> arguments;
  final BigInt startedAtUnixMs;
  final BigInt? finishedAtUnixMs;
  final ActivityStatus status;
  final int? exitCode;
  final Uint8List stdout;
  final BigInt stdoutTotalBytes;
  final bool stdoutTruncated;
  final Uint8List stderr;
  final BigInt stderrTotalBytes;
  final bool stderrTruncated;
  final ActivityProgress? progress;
}

final class ActivityPage {
  const ActivityPage({required this.records, required this.evictedThroughId});

  final List<ActivityRecord> records;
  final BigInt? evictedThroughId;

  bool detailsWereEvicted(BigInt activityId) {
    final boundary = evictedThroughId;
    return boundary != null && activityId <= boundary;
  }
}
