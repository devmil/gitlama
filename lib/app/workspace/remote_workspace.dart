import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/remote_command_policy.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/remote_reconnect.dart';
import '../../services/remote_workspace_service.dart';
import '../../services/remote_workspace_workflows.dart';
import '../../services/repository_session_service.dart';
import '../../models/repository_appearance.dart';
import '../../widgets/gitlama_repo_tabs.dart';
import '../../widgets/native_menu.dart';
import '../../widgets/repository_icon.dart';
import '../../widgets/status_notification.dart';
import '../app_theme.dart';
import 'command_availability.dart';
import 'labels.dart';
import 'remote_directory_picker.dart';
import 'remote_host_dialog.dart';

/// Why the active tab's host does not allow [capability] writes, localized;
/// null for a local tab or when allowed. With [listen] a build rebuilds when
/// availability changes; event handlers pass false.
String? remoteWriteReason(
  BuildContext context,
  RemoteCapability capability, {
  bool listen = true,
}) => switch (remoteCapabilityReason(
  (listen
          ? CommandAvailabilityScope.read(context)
          : CommandAvailabilityScope.peek(context))
      ?.remote,
  capability,
)) {
  final reason? => workspaceDisabledReason(context, reason),
  null => null,
};

/// The remote authority a tab's repository belongs to, or null for a
/// repository on this computer.
RemoteAuthority? remoteAuthorityOf(RepositoryTabState tab) =>
    (tab.canonicalIdentity ?? tab.requestedIdentity)?.remote;

/// Presents remote workspaces to the window. The workflows live in
/// [RemoteWorkspaceWorkflows]; this adapter answers their questions with the
/// window's dialogs and messages. One controller serves a window: the home
/// screen creates it and the workspace shell uses it.
final class RemoteWorkspaceController {
  RemoteWorkspaceController({
    required RemoteWorkspaceService? service,
    required RepositorySessionService repositories,
  }) : workflows = RemoteWorkspaceWorkflows(
         service: service,
         repositories: repositories,
       ) {
    _activity = workflows.activity.listen((_) => activity.value += 1);
  }

  final RemoteWorkspaceWorkflows workflows;
  late final StreamSubscription<void> _activity;

  /// Changes whenever a reconnect or installation the user started begins
  /// or ends, so the controls showing [connecting] follow it.
  final ValueNotifier<int> activity = ValueNotifier(0);

  RemoteWorkspaceService? get service => workflows.service;
  RepositorySessionService get repositories => workflows.repositories;
  bool get enabled => workflows.enabled;
  RemoteTabAccess? accessFor(RepositoryTabState? tab) =>
      workflows.accessFor(tab);
  String? hostLabel(RemoteAuthority authority) =>
      workflows.hostLabel(authority);
  RemoteConnectionState state(String profileId) => workflows.state(profileId);
  RemoteReconnectState? reconnectState(String profileId) =>
      workflows.reconnectState(profileId);
  void stopReconnecting(String profileId) =>
      workflows.stopReconnecting(profileId);
  bool connecting(String profileId) => workflows.connecting(profileId);
  bool needsHelper(String profileId) => workflows.needsHelper(profileId);
  List<RemoteHostProfile> get hosts => workflows.hosts;

  Future<bool> installHelper(BuildContext context, String profileId) =>
      workflows.installHelper(_WindowInteraction(context, this), profileId);

  Future<void> openRemoteRepository(
    BuildContext context, {
    Future<void> Function(NativePathIdentity identity)? open,
  }) => workflows.openRemoteRepository(
    _WindowInteraction(context, this),
    open: open,
  );

  /// Opens [path] on the saved host [alias], as the command line asked.
  Future<void> openOnHost(BuildContext context, String alias, List<int> path) =>
      workflows.openOnHost(_WindowInteraction(context, this), alias, path);

  /// Manages host profiles, optionally with [profileId] selected.
  Future<void> showHosts(BuildContext context, {String? profileId}) =>
      _WindowInteraction(context, this).showHosts(profileId: profileId);

  Future<void> setAccess(
    BuildContext context,
    String profileId, {
    required bool allowChanges,
  }) => workflows.setAccess(
    _WindowInteraction(context, this),
    profileId,
    allowChanges: allowChanges,
  );

  Future<void> disconnect(String profileId) => workflows.disconnect(profileId);

  Future<void> reconnect(BuildContext context, String profileId) =>
      workflows.reconnect(_WindowInteraction(context, this), profileId);

  Future<void> openRecent(
    BuildContext context,
    NativePathIdentity identity, {
    Future<void> Function()? open,
  }) => workflows.openRecent(
    _WindowInteraction(context, this),
    identity,
    open: open,
  );

  /// Why repositories cannot be created on [profileId]'s host, localized, as
  /// far as the profile tells before connecting; null when they may be.
  String? initializeBlockedReason(BuildContext context, String profileId) =>
      switch (workflows.initializeBlock(profileId)) {
        RemoteInitializeBlock.hostMissing =>
          context.l10n.remoteRecentHostMissing,
        RemoteInitializeBlock.writesOff => context.l10n.remoteCommandWritesOff,
        null => null,
      };

  Future<RepositorySessionState?> initializeRemoteRepository(
    BuildContext context,
    String profileId, {
    required bool bare,
  }) => workflows.initializeRemoteRepository(
    _WindowInteraction(context, this),
    profileId,
    bare: bare,
  );

  Future<void> dispose() async {
    await _activity.cancel();
    activity.dispose();
    await workflows.dispose();
  }
}

/// Answers a remote workflow with the dialogs and messages of the window
/// that started it.
final class _WindowInteraction implements RemoteWorkspaceInteraction {
  _WindowInteraction(this.context, this.controller);

  final BuildContext context;
  final RemoteWorkspaceController controller;

  @override
  bool get active => context.mounted;

  @override
  Future<({bool automatic})?> confirmHelperInstall(
    RemoteHostProfile profile,
    RemoteHelperArtifact artifact,
  ) => showRemoteHelperInstallDialog(
    context,
    profile: profile,
    artifact: artifact,
  );

  @override
  Future<String?> showHosts({String? profileId, bool choosing = false}) async {
    final service = controller.service;
    if (service == null || !context.mounted) return null;
    return showRemoteHostDialog(
      context,
      service: service,
      initialProfileId: profileId,
      choosing: choosing,
      onAccessChanged: controller.workflows.applyAccess,
    );
  }

  @override
  Future<RemoteHostProfile?> addHost(String alias) async {
    final service = controller.service;
    if (service == null || !context.mounted) return null;
    return showMeridianDialog<RemoteHostProfile>(
      context: context,
      builder: (context) =>
          RemoteProfileEditor(service: service, initialAlias: alias),
    );
  }

  @override
  Future<List<int>?> chooseFolder(
    RemoteHostProfile profile, {
    bool forInitialize = false,
  }) async {
    final service = controller.service;
    if (service == null || !context.mounted) return null;
    return showRemoteDirectoryPicker(
      context,
      service: service,
      profile: profile,
      purpose: forInitialize
          ? RemoteDirectoryPurpose.initialize
          : RemoteDirectoryPurpose.open,
    );
  }

  @override
  void reportFailure(RemoteFailureCode code, {String? alias}) {
    if (!context.mounted) return;
    StatusNotificationScope.show(
      context,
      remoteFailureMessage(context, code, alias: alias),
      error: true,
    );
  }

  @override
  void reportSaveFailure(Object error) {
    if (!context.mounted) return;
    StatusNotificationScope.show(
      context,
      remoteProfileSaveFailureMessage(context, error),
      error: true,
    );
  }

  @override
  void reportMessage(RemoteWorkflowMessage message) {
    if (!context.mounted) return;
    StatusNotificationScope.show(context, switch (message) {
      RemoteWorkflowMessage.openFailed => context.l10n.remoteOpenFailed,
      RemoteWorkflowMessage.repositoryCapacity =>
        context.l10n.remoteRepositoryCapacity,
      RemoteWorkflowMessage.recentHostMissing =>
        context.l10n.remoteRecentHostMissing,
    }, error: true);
  }

  @override
  void reportDisabled(AppCommandDisabledReason reason) {
    if (!context.mounted) return;
    StatusNotificationScope.show(
      context,
      workspaceDisabledReason(context, reason),
      error: true,
    );
  }
}

/// Makes the window's [RemoteWorkspaceController] available below it.
class RemoteWorkspaceScope extends InheritedWidget {
  const RemoteWorkspaceScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final RemoteWorkspaceController controller;

  static RemoteWorkspaceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RemoteWorkspaceScope>()
      ?.controller;

  // Connection and tab states change without a new controller.
  @override
  bool updateShouldNotify(RemoteWorkspaceScope oldWidget) => true;
}

/// The host [authority] belongs to as the user knows it: the profile's
/// label, or a generic name once the profile was deleted.
String remoteHostName(
  BuildContext context,
  RemoteWorkspaceController? controller,
  RemoteAuthority authority,
) => controller?.hostLabel(authority) ?? context.l10n.remoteHostUnknown;

String remotePhaseLabel(
  BuildContext context,
  RemoteConnectionPhase phase,
) => switch (phase) {
  RemoteConnectionPhase.idle => context.l10n.remotePhaseIdle,
  RemoteConnectionPhase.installing => context.l10n.remotePhaseInstalling,
  RemoteConnectionPhase.connecting => context.l10n.remotePhaseConnecting,
  RemoteConnectionPhase.handshaking => context.l10n.remotePhaseHandshaking,
  RemoteConnectionPhase.ready => context.l10n.remotePhaseReady,
  RemoteConnectionPhase.disconnecting => context.l10n.remotePhaseDisconnecting,
  RemoteConnectionPhase.disconnected => context.l10n.remotePhaseDisconnected,
  RemoteConnectionPhase.failed => context.l10n.remotePhaseFailed,
  RemoteConnectionPhase.identityChanged =>
    context.l10n.remotePhaseIdentityChanged,
  RemoteConnectionPhase.retired => context.l10n.remotePhaseIdle,
};

/// The expected location of the helper on a host, with [buildId] standing
/// for this build's identity.
String remoteHelperLocation(String buildId) =>
    '~/.local/lib/gitlama/remote/$buildId/gitlama-remote-helper';

/// Why a host profile change failed, with a stable code the user can report.
String remoteProfileSaveFailureMessage(BuildContext context, Object error) {
  final l10n = context.l10n;
  final reason = switch (error) {
    SettingsException(code: SettingsFailureCode.locked) =>
      l10n.remoteProfileSaveLocked,
    SettingsException(code: SettingsFailureCode.io) =>
      l10n.remoteProfileSaveWriteFailed,
    SettingsException() => l10n.remoteProfileSaveRejected,
    RemoteWorkspaceException(code: RemoteFailureCode.capacity) =>
      l10n.remoteFailureCapacity,
    RemoteWorkspaceException(code: RemoteFailureCode.unsupported) =>
      l10n.remoteProfileSaveStale,
    StateError() => l10n.remoteProfileSaveUnavailable,
    _ => l10n.remoteProfileSaveFailed,
  };
  return '$reason\n${l10n.remoteProfileSaveCode(remoteProfileSaveFailureCode(error))}';
}

/// A stable, localized explanation of [code]. [alias] names the SSH alias
/// where the advice is to check it in a terminal.
String remoteFailureMessage(
  BuildContext context,
  RemoteFailureCode code, {
  String? alias,
}) {
  final l10n = context.l10n;
  return switch (code) {
    RemoteFailureCode.outcomeUnknown => l10n.remoteFailureOutcomeUnknown,
    RemoteFailureCode.sshUnavailable => l10n.remoteFailureSshUnavailable,
    RemoteFailureCode.sshUnsupported => l10n.remoteFailureSshUnsupported,
    RemoteFailureCode.sshConnectionFailed =>
      l10n.remoteFailureSshConnectionFailed(alias ?? l10n.remoteAliasExample),
    RemoteFailureCode.helperNotInstalled =>
      l10n.remoteFailureHelperNotInstalled,
    RemoteFailureCode.unsupportedPlatform =>
      l10n.remoteFailureUnsupportedPlatform,
    RemoteFailureCode.bootstrapFailed => l10n.remoteFailureBootstrapFailed,
    RemoteFailureCode.handshakeTimeout => l10n.remoteFailureHandshakeTimeout,
    RemoteFailureCode.protocolMismatch => l10n.remoteFailureProtocolMismatch,
    RemoteFailureCode.buildMismatch => l10n.remoteFailureBuildMismatch,
    RemoteFailureCode.gitMissing => l10n.remoteFailureGitMissing,
    RemoteFailureCode.gitUnsupported => l10n.remoteFailureGitUnsupported,
    RemoteFailureCode.storeUnavailable => l10n.remoteFailureStoreUnavailable,
    RemoteFailureCode.identityChanged => l10n.remoteFailureIdentityChanged,
    RemoteFailureCode.identityMismatch => l10n.remoteFailureIdentityMismatch,
    RemoteFailureCode.protocolViolation => l10n.remoteFailureProtocolViolation,
    RemoteFailureCode.disconnected => l10n.remoteFailureDisconnected,
    RemoteFailureCode.timedOut => l10n.remoteFailureTimedOut,
    RemoteFailureCode.canceled => l10n.remoteFailureCanceled,
    RemoteFailureCode.capacity => l10n.remoteFailureCapacity,
    RemoteFailureCode.unsupported => l10n.remoteFailureUnsupported,
    RemoteFailureCode.pathInvalid => l10n.remotePathAbsoluteRequired,
    RemoteFailureCode.pathNotFound => l10n.remoteFailurePathNotFound,
    RemoteFailureCode.permissionDenied => l10n.remoteFailurePermissionDenied,
    RemoteFailureCode.notDirectory => l10n.remoteFailureNotDirectory,
    RemoteFailureCode.directoryChanged => l10n.remoteFailureDirectoryChanged,
    RemoteFailureCode.cursorExpired => l10n.remoteFailureCursorExpired,
    RemoteFailureCode.writeNotPermitted => l10n.remoteCommandWritesUnavailable,
    RemoteFailureCode.previewExpired => l10n.remoteFailurePreviewExpired,
    RemoteFailureCode.preconditionFailed =>
      l10n.remoteFailurePreconditionFailed,
    RemoteFailureCode.operationIdConflict =>
      l10n.remoteFailureOperationIdConflict,
    RemoteFailureCode.receiptCapacity => l10n.remoteFailureReceiptCapacity,
    RemoteFailureCode.installUnavailable =>
      l10n.remoteFailureInstallUnavailable,
    RemoteFailureCode.installDirectory => l10n.remoteFailureInstallDirectory,
    RemoteFailureCode.installWrite => l10n.remoteFailureInstallWrite,
    RemoteFailureCode.installDigest => l10n.remoteFailureInstallDigest,
    RemoteFailureCode.installExecute => l10n.remoteFailureInstallExecute,
    RemoteFailureCode.installFailed => l10n.remoteFailureInstallFailed,
    RemoteFailureCode.internal => l10n.remoteFailureInternal,
  };
}

/// A host badge: an icon and the host's name, readable without colour.
class RemoteHostBadge extends StatelessWidget {
  const RemoteHostBadge({
    super.key,
    required this.host,
    this.disconnected = false,
  });

  final String host;
  final bool disconnected;

  @override
  Widget build(BuildContext context) {
    final label = disconnected
        ? context.l10n.remoteHostBadgeDisconnected(host)
        : context.l10n.remoteHostBadge(host);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeridianIcon(
              disconnected ? 'wifi-off' : 'server',
              size: MeridianIconSize.small,
            ),
            const SizedBox(width: MeridianSpace.space2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _HostAction {
  readOnly,
  allowChanges,
  reconnect,
  disconnect,
  installHelper,
  settings,
}

/// The status bar's host of the active remote tab: its name, what GitLama
/// may do there, and a native menu that switches between Read only and
/// Allow changes, reconnects or disconnects, installs the helper and opens
/// the host's settings.
class RemoteHostStatus extends StatelessWidget {
  const RemoteHostStatus({
    super.key,
    required this.controller,
    required this.authority,
    required this.disconnected,
  });

  final RemoteWorkspaceController controller;
  final RemoteAuthority authority;
  final bool disconnected;

  Future<void> _run(BuildContext context, _HostAction action) async {
    final profileId = authority.profileId;
    switch (action) {
      case _HostAction.readOnly:
        await controller.setAccess(context, profileId, allowChanges: false);
      case _HostAction.allowChanges:
        await controller.setAccess(context, profileId, allowChanges: true);
      case _HostAction.reconnect:
        await controller.reconnect(context, profileId);
      case _HostAction.disconnect:
        await controller.disconnect(profileId);
      case _HostAction.installHelper:
        await controller.installHelper(context, profileId);
      case _HostAction.settings:
        await controller.showHosts(context, profileId: profileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = remoteHostName(context, controller, authority);
    final profile = controller.service?.profile(authority.profileId);
    final badge = RemoteHostBadge(host: host, disconnected: disconnected);
    if (profile == null || !controller.enabled) return badge;
    final changes = profile.writesAllowed;
    final connecting = controller.connecting(authority.profileId);
    final ready = controller.state(authority.profileId).ready;
    final access = changes
        ? l10n.remoteAccessStatusChanges
        : l10n.remoteAccessStatusReadOnly;
    return NativeMenuButton<_HostAction>(
      key: const ValueKey('remote-host-status'),
      tooltip: l10n.remoteHostStatusTooltip(host),
      padding: EdgeInsets.zero,
      onSelected: (action) => unawaited(_run(context, action)),
      itemBuilder: (context) => [
        NativeMenuItem(
          value: _HostAction.readOnly,
          title: l10n.remoteAccessReadOnly,
          icon: 'eye',
          checked: !changes,
        ),
        NativeMenuItem(
          value: _HostAction.allowChanges,
          title: l10n.remoteAccessChanges,
          icon: 'pencil',
          checked: changes,
        ),
        const NativeMenuItem.separator(),
        if (ready)
          NativeMenuItem(
            value: _HostAction.disconnect,
            title: l10n.remoteDisconnect,
            icon: 'unlink',
          )
        else
          NativeMenuItem(
            value: _HostAction.reconnect,
            title: l10n.remoteReconnect,
            icon: 'refresh',
            enabled: !connecting,
          ),
        if (controller.needsHelper(authority.profileId))
          NativeMenuItem(
            value: _HostAction.installHelper,
            title: l10n.remoteInstallHelper,
            icon: 'download',
            enabled: !connecting,
          ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          value: _HostAction.settings,
          title: l10n.remoteHostSettings,
          icon: 'settings',
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: badge),
          const SizedBox(width: MeridianSpace.space3),
          MeridianIcon(
            changes ? 'pencil' : 'eye',
            size: MeridianIconSize.small,
          ),
          const SizedBox(width: MeridianSpace.space2),
          Text(
            access,
            key: const ValueKey('remote-host-access'),
            maxLines: 1,
            style: context.text.caption.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(width: MeridianSpace.space1),
          const MeridianIcon('chevron-down', size: MeridianIconSize.small),
        ],
      ),
    );
  }
}

/// The persistent notice of an open remote tab whose connection is gone:
/// its content stays visible as the last received state. It never takes
/// focus.
class RemoteTabBanner extends StatelessWidget {
  const RemoteTabBanner({super.key, required this.tab});

  final RepositoryTabState tab;

  @override
  Widget build(BuildContext context) {
    final controller = RemoteWorkspaceScope.maybeOf(context);
    final authority = remoteAuthorityOf(tab);
    if (controller == null ||
        authority == null ||
        tab.session == null ||
        !controller.repositories.isRemoteTabStale(tab)) {
      return const SizedBox.shrink();
    }
    final host = remoteHostName(context, controller, authority);
    final known = controller.hostLabel(authority) != null;
    return Padding(
      key: const ValueKey('remote-stale-banner'),
      padding: const EdgeInsetsDirectional.only(
        start: MeridianSpace.space3,
        end: MeridianSpace.space3,
        bottom: MeridianSpace.space3,
      ),
      child: RemoteReconnectListener(
        controller: controller,
        profileId: authority.profileId,
        builder: (context, reconnect) {
          final connecting = controller.connecting(authority.profileId);
          final status = reconnect == null
              ? null
              : remoteReconnectStatus(context, controller, host, reconnect);
          return MeridianBanner(
            tone: MeridianBannerTone.warning,
            icon: 'wifi-off',
            title: status?.title,
            message: status?.detail ?? context.l10n.remoteStaleBanner(host),
            actions: controller.enabled && known
                ? remoteReconnectActions(
                    context,
                    controller,
                    authority.profileId,
                    reconnect,
                    connecting: connecting,
                    size: MeridianControlSize.small,
                  )
                : const [],
          );
        },
      ),
    );
  }
}

/// How a tab shows the host of [authority]: its name, and the colour and
/// icon the user gave it.
RemoteTabHost remoteTabHost(
  BuildContext context,
  RemoteWorkspaceController controller,
  RemoteAuthority authority, {
  required bool disconnected,
}) {
  final profile = controller.service?.profile(authority.profileId);
  final color = AppearanceColor.byKey(profile?.color);
  return (
    name: remoteHostName(context, controller, authority),
    disconnected: disconnected,
    color: color == null ? null : repositoryAppearanceColor(context, color),
    icon: repositoryAppearanceIcons.contains(profile?.icon)
        ? profile!.icon
        : null,
  );
}

/// What a tab says about automatic reconnection of its host.
({String title, String? reason, String detail}) remoteReconnectStatus(
  BuildContext context,
  RemoteWorkspaceController controller,
  String host,
  RemoteReconnectState state,
) {
  final l10n = context.l10n;
  final alias = controller.service?.profile(state.profileId)?.alias;
  final reason = state.failure == null
      ? null
      : remoteFailureMessage(context, state.failure!, alias: alias);
  final detail = reason == null
      ? l10n.remoteReconnectStale
      : '$reason ${l10n.remoteReconnectStale}';
  return switch (state.phase) {
    RemoteReconnectPhase.waiting => (
      title: l10n.remoteReconnectIn(
        host,
        remoteReconnectSeconds(state.nextAttemptAt),
      ),
      reason: reason,
      detail: detail,
    ),
    RemoteReconnectPhase.connecting => (
      title: l10n.remoteReconnecting(host),
      reason: reason,
      detail: detail,
    ),
    RemoteReconnectPhase.stopped => (
      title: state.gaveUp
          ? l10n.remoteReconnectGaveUp(host)
          : l10n.remoteReconnectStopped(host),
      reason: reason,
      detail: detail,
    ),
  };
}

/// Whole seconds until [at], at least 0.
int remoteReconnectSeconds(DateTime? at) {
  if (at == null) return 0;
  final remaining = at.difference(DateTime.now());
  if (remaining.isNegative) return 0;
  return (remaining.inMilliseconds / 1000).ceil();
}

/// Reconnect now and Stop while automatic attempts run; Reconnect (or Try
/// again after they ended) otherwise.
List<Widget> remoteReconnectActions(
  BuildContext context,
  RemoteWorkspaceController controller,
  String profileId,
  RemoteReconnectState? state, {
  required bool connecting,
  MeridianControlSize size = MeridianControlSize.regular,
  bool primary = false,
}) {
  final l10n = context.l10n;
  final automatic =
      state != null && state.phase != RemoteReconnectPhase.stopped;
  final install = !connecting && controller.needsHelper(profileId);
  return [
    if (install)
      MeridianButton(
        key: const ValueKey('remote-install-helper'),
        label: l10n.remoteInstallHelper,
        icon: primary ? 'download' : null,
        size: size,
        variant: primary
            ? MeridianButtonVariant.primary
            : MeridianButtonVariant.secondary,
        onPressed: () =>
            unawaited(controller.installHelper(context, profileId)),
      ),
    MeridianButton(
      key: const ValueKey('remote-reconnect'),
      label: automatic
          ? l10n.remoteReconnectNow
          : state?.gaveUp ?? false
          ? l10n.remoteReconnectTryAgain
          : l10n.remoteReconnect,
      icon: primary ? 'refresh' : null,
      size: size,
      variant: primary && !install
          ? MeridianButtonVariant.primary
          : install
          ? MeridianButtonVariant.quiet
          : MeridianButtonVariant.secondary,
      loading: connecting,
      onPressed: connecting
          ? null
          : () => unawaited(controller.reconnect(context, profileId)),
    ),
    if (automatic && !connecting)
      MeridianButton(
        key: const ValueKey('remote-reconnect-stop'),
        label: l10n.remoteReconnectStop,
        size: size,
        variant: MeridianButtonVariant.quiet,
        onPressed: () => controller.stopReconnecting(profileId),
      ),
  ];
}

/// Rebuilds [builder] when automatic reconnection of [profileId] changes,
/// and every second while it counts down to the next attempt.
class RemoteReconnectListener extends StatefulWidget {
  const RemoteReconnectListener({
    super.key,
    required this.controller,
    required this.profileId,
    required this.builder,
  });

  final RemoteWorkspaceController controller;
  final String profileId;
  final Widget Function(BuildContext context, RemoteReconnectState? state)
  builder;

  @override
  State<RemoteReconnectListener> createState() =>
      _RemoteReconnectListenerState();
}

class _RemoteReconnectListenerState extends State<RemoteReconnectListener> {
  StreamSubscription<String>? _changes;
  StreamSubscription<RemoteConnectionState>? _connection;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(RemoteReconnectListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.profileId != widget.profileId) {
      _unlisten(oldWidget.controller);
      _listen();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _listen() {
    widget.controller.activity.addListener(_rebuild);
    _connection = widget.controller.service?.states
        .where((state) => state.profileId == widget.profileId)
        .listen((_) => _rebuild());
    _changes = widget.controller.repositories.remoteReconnect.changes
        .where((profileId) => profileId == widget.profileId)
        .listen((_) {
          if (mounted) setState(_syncTick);
        });
    _syncTick();
  }

  /// Counts down only while an attempt is due.
  void _syncTick() {
    final waiting =
        widget.controller.reconnectState(widget.profileId)?.phase ==
        RemoteReconnectPhase.waiting;
    if (waiting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!waiting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _unlisten(RemoteWorkspaceController controller) {
    controller.activity.removeListener(_rebuild);
    unawaited(_changes?.cancel());
    unawaited(_connection?.cancel());
  }

  @override
  void dispose() {
    _unlisten(widget.controller);
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    widget.controller.reconnectState(widget.profileId),
  );
}

/// The body of a remote tab that could not open: a dropped connection
/// offers Reconnect; a changed host identity explains and opens the host
/// for a decision; a repository that no longer matches the one the tab
/// opened, on a host that still does, can be trusted and opened again.
/// Null for any other tab.
Widget? remoteTabFailure(BuildContext context, RepositoryTabState tab) {
  final authority = remoteAuthorityOf(tab);
  final code = tab.failure?.code;
  if (authority == null ||
      (code != RepositoryFailureCode.remoteDisconnected &&
          code != RepositoryFailureCode.remoteIdentityChanged)) {
    return null;
  }
  return _RemoteTabFailure(
    tab: tab,
    authority: authority,
    identityChanged: code == RepositoryFailureCode.remoteIdentityChanged,
  );
}

class _RemoteTabFailure extends StatelessWidget {
  const _RemoteTabFailure({
    required this.tab,
    required this.authority,
    required this.identityChanged,
  });

  final RepositoryTabState tab;
  final RemoteAuthority authority;
  final bool identityChanged;

  @override
  Widget build(BuildContext context) {
    final controller = RemoteWorkspaceScope.maybeOf(context);
    final host = remoteHostName(context, controller, authority);
    final known = controller?.hostLabel(authority) != null;
    final usable = controller != null && controller.enabled && known;
    final path = displayRemotePath(
      (tab.requestedIdentity ?? tab.canonicalIdentity)?.units ?? const [],
    );
    // A connected host vouched for its account and store, so only the
    // repository at the path changed.
    final repositoryChanged =
        identityChanged &&
        usable &&
        controller.state(authority.profileId).phase !=
            RemoteConnectionPhase.identityChanged;
    return Center(
      key: const ValueKey('remote-tab-failure'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: MeridianLayout.dialogWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MeridianSpace.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: MeridianIcon(
                  identityChanged ? 'shield-alert' : 'wifi-off',
                  size: MeridianIconSize.toolbar,
                ),
              ),
              const SizedBox(height: MeridianSpace.space4),
              Text(
                repositoryChanged
                    ? context.l10n.remoteTabRepositoryChangedTitle(host)
                    : identityChanged
                    ? context.l10n.remoteTabIdentityChangedTitle(host)
                    : context.l10n.remoteTabDisconnectedTitle(host),
                textAlign: TextAlign.center,
                style: context.text.bodyStrong.copyWith(
                  color: context.colors.ink,
                ),
              ),
              const SizedBox(height: MeridianSpace.space3),
              Text(
                repositoryChanged
                    ? context.l10n.remoteTabRepositoryChangedDetail
                    : identityChanged
                    ? context.l10n.remoteTabIdentityChangedDetail
                    : known
                    ? context.l10n.remoteTabDisconnectedDetail
                    : context.l10n.remoteTabHostDeletedDetail,
                textAlign: TextAlign.center,
                style: context.text.body.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              if (path.isNotEmpty) ...[
                const SizedBox(height: MeridianSpace.space3),
                Text(
                  path,
                  textAlign: TextAlign.center,
                  style: context.text.codeSm.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              ],
              if (usable) ...[
                const SizedBox(height: MeridianSpace.space5),
                Center(
                  child: repositoryChanged
                      ? MeridianButton(
                          key: const ValueKey('remote-trust-repository'),
                          label: context.l10n.remoteTabTrustRepository,
                          icon: 'rotate-cw',
                          variant: MeridianButtonVariant.primary,
                          onPressed: () => unawaited(
                            controller.repositories
                                .reopenChangedRemoteTab(tab.id)
                                .then<void>(
                                  (_) {},
                                  onError: (Object _) {
                                    // The tab shows the failure it reopened with.
                                  },
                                ),
                          ),
                        )
                      : identityChanged
                      ? MeridianButton(
                          key: const ValueKey('remote-review-identity'),
                          label: context.l10n.remoteReviewHost,
                          icon: 'server',
                          variant: MeridianButtonVariant.primary,
                          onPressed: () => unawaited(
                            controller.showHosts(
                              context,
                              profileId: authority.profileId,
                            ),
                          ),
                        )
                      : RemoteReconnectListener(
                          controller: controller,
                          profileId: authority.profileId,
                          builder: (context, reconnect) {
                            final status = reconnect == null
                                ? null
                                : remoteReconnectStatus(
                                    context,
                                    controller,
                                    host,
                                    reconnect,
                                  );
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (status != null) ...[
                                  Text(
                                    status.title,
                                    key: const ValueKey(
                                      'remote-reconnect-status',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: context.text.body.copyWith(
                                      color: context.colors.ink,
                                    ),
                                  ),
                                  if (status.reason case final reason?) ...[
                                    const SizedBox(
                                      height: MeridianSpace.space2,
                                    ),
                                    Text(
                                      reason,
                                      textAlign: TextAlign.center,
                                      style: context.text.caption.copyWith(
                                        color: context.colors.inkMuted,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: MeridianSpace.space4),
                                ],
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: MeridianSpace.space3,
                                  children: remoteReconnectActions(
                                    context,
                                    controller,
                                    authority.profileId,
                                    reconnect,
                                    connecting: controller.connecting(
                                      authority.profileId,
                                    ),
                                    primary: true,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Recent repositories as the welcome screen and chooser list them: remote
/// ones only while remote workspaces are on.
List<NativePathIdentity> visibleRecents(
  List<NativePathIdentity> recents,
  RemoteWorkspaceController? controller,
) => [
  for (final identity in recents)
    if (!identity.isRemote || (controller?.enabled ?? false)) identity,
];

/// A remote recent's secondary line: its host and path.
String remoteRecentSubtitle(
  BuildContext context,
  RemoteWorkspaceController? controller,
  NativePathIdentity identity,
) => context.l10n.remoteRecentSubtitle(
  remoteHostName(context, controller, identity.remote!),
  displayRemotePath(identity.units),
);

/// The last path segment of a remote recent, for its title.
String remoteRecentName(NativePathIdentity identity) {
  final path = displayRemotePath(identity.units);
  final trimmed = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final separator = trimmed.lastIndexOf('/');
  return separator < 0 || separator == trimmed.length - 1
      ? trimmed
      : trimmed.substring(separator + 1);
}
