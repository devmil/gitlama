/// Git's optional status accelerators for one repository: the untracked cache
/// and the filesystem monitor. Large worktrees scan much faster with them.
final class StatusAcceleration {
  const StatusAcceleration({
    required this.untrackedCache,
    required this.fsmonitor,
    required this.fsmonitorAvailable,
    this.lastScan,
  });

  /// `core.untrackedCache` is enabled.
  final bool untrackedCache;

  /// `core.fsmonitor` names Git's built-in monitor or a hook.
  final bool fsmonitor;

  /// This platform and Git version provide the built-in monitor.
  final bool fsmonitorAvailable;

  /// How long the last completed status scan took, when it was recorded.
  final Duration? lastScan;

  /// A status scan this slow is worth an offer to speed it up.
  static const slowScan = Duration(seconds: 3);

  /// Enabling would change a setting.
  bool get canImprove => !untrackedCache || (fsmonitorAvailable && !fsmonitor);

  /// The last scan was slow and enabling would change a setting.
  bool get worthOffering {
    final scan = lastScan;
    return scan != null && scan >= slowScan && canImprove;
  }
}
