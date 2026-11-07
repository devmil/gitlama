import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/repository_state.dart';
import '../../models/status_acceleration.dart';
import '../../models/workspace.dart';
import '../app_theme.dart';
import 'sidebar.dart';
import 'command_availability.dart';
import 'labels.dart';
import 'workspace_scope.dart';
import 'package:meridian_ui/meridian_ui.dart';

class RepositoryConditions extends StatefulWidget {
  const RepositoryConditions({
    super.key,
    required this.active,
    this.onCommand,
    this.onSkip,
  });

  final RepositoryTabState active;
  final RunAppCommand? onCommand;
  final VoidCallback? onSkip;

  @override
  State<RepositoryConditions> createState() => _RepositoryConditionsState();
}

class _RepositoryConditionsState extends State<RepositoryConditions> {
  bool _recentlyResolved = false;
  bool _pulseContinue = false;
  Timer? _pulseTimer;
  Timer? _resetTimer;

  /// The status accelerators offered for [_offerSession], once checked.
  StatusAcceleration? _acceleration;
  (BigInt, int)? _offerSession;
  var _enabling = false;
  var _enableFailed = false;
  StreamSubscription<RepositorySessionIdentity>? _accelerationEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accelerationEnabled ??= WorkspaceServicesScope.maybeOf(context)
        ?.repositories
        .workingCopy
        .statusAccelerationEnabled
        .listen(_followEnabledAcceleration);
    _checkOffer();
  }

  /// Settings enabled elsewhere, such as in the settings dialog, end the
  /// offer for that session.
  void _followEnabledAcceleration(RepositorySessionIdentity identity) {
    if (!mounted || _enabling) return;
    if ((identity.nativeId, identity.generation) != _offerSession) return;
    setState(() {
      _acceleration = null;
      _enableFailed = false;
    });
  }

  /// Asks once per session, after its first status scan, whether a slow
  /// status is worth speeding up.
  void _checkOffer() {
    final session = widget.active.session;
    final services = WorkspaceServicesScope.maybeOf(context);
    if (session == null ||
        services == null ||
        session.snapshot.status == null) {
      return;
    }
    final identity = session.identity;
    final key = (identity.nativeId, identity.generation);
    if (key == _offerSession) return;
    _offerSession = key;
    _acceleration = null;
    _enabling = false;
    _enableFailed = false;
    unawaited(
      services.repositories.workingCopy.statusAccelerationOffer(identity).then((
        offer,
      ) {
        if (mounted && _offerSession == key) {
          setState(() => _acceleration = offer);
        }
      }),
    );
  }

  Future<void> _enableAcceleration(RepositorySessionIdentity identity) async {
    final services = WorkspaceServicesScope.maybeOf(context);
    if (services == null) return;
    final key = _offerSession;
    setState(() => _enabling = true);
    try {
      final enabled = await services.repositories.workingCopy
          .enableStatusAcceleration(identity);
      if (!mounted || _offerSession != key) return;
      setState(() {
        _acceleration = enabled;
        _enabling = false;
      });
    } on Object {
      if (!mounted || _offerSession != key) return;
      setState(() {
        _enabling = false;
        _enableFailed = true;
      });
    }
  }

  void _dismissAcceleration(RepositorySessionIdentity identity) {
    WorkspaceServicesScope.maybeOf(
      context,
    )?.repositories.workingCopy.dismissStatusAccelerationOffer(identity);
    setState(() {
      _acceleration = null;
      _enableFailed = false;
    });
  }

  Widget? _accelerationBanner(BuildContext context) {
    final offer = _acceleration;
    final identity = widget.active.session?.identity;
    if (offer == null || identity == null) return null;
    if (!_enableFailed && !_enabling && !offer.worthOffering) return null;
    final seconds = ((offer.lastScan?.inMilliseconds ?? 0) / 1000).round();
    return MeridianBanner(
      key: const ValueKey('status-acceleration-offer'),
      tone: _enableFailed ? MeridianBannerTone.error : MeridianBannerTone.info,
      icon: _enableFailed ? null : 'gauge',
      message: _enableFailed
          ? context.l10n.statusAccelerationFailed
          : offer.fsmonitorAvailable && !offer.fsmonitor
          ? context.l10n.statusAccelerationOffer(seconds)
          : context.l10n.statusAccelerationOfferCacheOnly(seconds),
      actions: [
        if (!_enableFailed)
          MeridianButton(
            label: context.l10n.statusAccelerationEnable,
            variant: MeridianButtonVariant.primary,
            size: MeridianControlSize.small,
            onPressed: _enabling ? null : () => _enableAcceleration(identity),
          ),
      ],
      onDismiss: () => _dismissAcceleration(identity),
      dismissLabel: context.l10n.statusAccelerationDismiss,
    );
  }

  int _conflictCount(RepositoryTabState active) =>
      active.session?.snapshot.status?.entries
          .where((entry) => entry.conflicted)
          .length ??
      0;

  @override
  void didUpdateWidget(covariant RepositoryConditions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkOffer();
    final previous = _conflictCount(oldWidget.active);
    final current = _conflictCount(widget.active);
    if (current > 0) {
      _pulseTimer?.cancel();
      _resetTimer?.cancel();
      _recentlyResolved = false;
      _pulseContinue = false;
    } else if (previous > 0) {
      _recentlyResolved = true;
      _pulseContinue = false;
      _pulseTimer?.cancel();
      _pulseTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted && _conflictCount(widget.active) == 0) {
          setState(() => _pulseContinue = true);
        }
      });
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _recentlyResolved = false;
            _pulseContinue = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_accelerationEnabled?.cancel());
    _pulseTimer?.cancel();
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final onCommand = widget.onCommand;
    final onSkip = widget.onSkip;
    final snapshot = active.session?.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final status = snapshot.status;
    final conflictCount =
        status?.entries.where((entry) => entry.conflicted).length ?? 0;
    final conditions = <(MeridianBannerTone, String)>[
      if (active.watchOverflowRevision != null)
        (MeridianBannerTone.warning, context.l10n.workspaceWatchOverflow),
      if (snapshot.watchFailure != null)
        (MeridianBannerTone.error, context.l10n.workspaceWatchFailure),
      if (snapshot.statusFailure != null)
        (MeridianBannerTone.error, context.l10n.workspaceStatusFailure),
      if (snapshot.refsFailure != null)
        (MeridianBannerTone.error, context.l10n.workspaceRefsFailure),
      if (snapshot.identity?.headKind == HeadKind.detached)
        (MeridianBannerTone.info, context.l10n.workspaceDetachedHead),
      if (conflictCount > 0)
        (
          MeridianBannerTone.attention,
          context.l10n.workspaceConflictCount(conflictCount),
        ),
      if (conflictCount == 0 && _recentlyResolved)
        (MeridianBannerTone.success, context.l10n.conflictAllResolved),
      if (status != null)
        for (final operation in status.operations)
          (
            operation.kind == RepositoryOperationKind.bisect
                ? MeridianBannerTone.info
                : MeridianBannerTone.attention,
            repositoryOperationLabel(context, operation.kind),
          ),
    ];
    final accelerationBanner = _accelerationBanner(context);
    if (conditions.isEmpty && accelerationBanner == null) {
      return const SizedBox.shrink();
    }
    // A repository on another computer continues, skips or aborts when its
    // host allows history changes; otherwise the buttons say why not.
    // The same policy as the commands: Continue waits for resolved conflicts;
    // Skip and Abort follow Abort, which a remote tab may refuse.
    final availability = CommandAvailabilityScope.read(context);
    String? text(AppCommandDisabledReason? reason) =>
        reason == null ? null : workspaceDisabledReason(context, reason);
    final abortReason = text(availability?.reason(AppCommandId.rebaseAbort));
    final remoteReason = abortReason;
    final paused = status?.operations
        .where((operation) => operation.kind != RepositoryOperationKind.bisect)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(MeridianSpace.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (kind, message) in conditions) ...[
            MeridianBanner(
              tone: kind,
              icon: kind == MeridianBannerTone.success ? 'circle-check' : null,
              message: message,
              actions:
                  paused != null &&
                      message ==
                          repositoryOperationLabel(context, paused.kind) &&
                      onCommand != null
                  ? [
                      MeridianPulse(
                        active: _pulseContinue,
                        once: true,
                        color: context.colors.accent,
                        spread: MeridianSpace.space4,
                        borderRadius: BorderRadius.circular(
                          context.meridian.radius.md,
                        ),
                        child: MeridianButton(
                          label: context.l10n.conflictContinue,
                          variant: MeridianButtonVariant.primary,
                          disabledReason: conflictCount > 0
                              ? context.l10n.workspaceConflictCount(
                                  conflictCount,
                                )
                              : text(
                                  availability?.reason(
                                    AppCommandId.rebaseContinue,
                                  ),
                                ),
                          onPressed:
                              conflictCount > 0 ||
                                  availability?.reason(
                                        AppCommandId.rebaseContinue,
                                      ) !=
                                      null
                              ? null
                              : () => onCommand(AppCommandId.rebaseContinue),
                        ),
                      ),
                      if (onSkip != null && paused.kind.canSkip)
                        MeridianButton(
                          label: context.l10n.conflictSkip,
                          variant: MeridianButtonVariant.secondary,
                          disabledReason: remoteReason,
                          onPressed: remoteReason == null ? onSkip : null,
                        ),
                      MeridianButton(
                        label: context.l10n.conflictAbort,
                        variant: MeridianButtonVariant.dangerQuiet,
                        disabledReason: remoteReason,
                        onPressed: remoteReason == null
                            ? () => onCommand(AppCommandId.rebaseAbort)
                            : null,
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: MeridianSpace.space3),
          ],
          if (accelerationBanner != null) ...[
            accelerationBanner,
            const SizedBox(height: MeridianSpace.space3),
          ],
        ],
      ),
    );
  }
}

/// One-line diff chrome; the action strip scrolls when the detail pane narrows.
