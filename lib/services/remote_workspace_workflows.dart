import 'dart:async';

import '../models/app_command.dart';
import '../models/remote_command_policy.dart';
import '../models/remote_workspace.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';
import '../models/workspace.dart';
import 'remote_reconnect.dart';
import 'remote_workspace_service.dart';
import 'repository_session_service.dart';

/// What a remote workflow asks of the window it runs in: decisions only the
/// user can make and messages for them. The workflows decide everything else.
abstract interface class RemoteWorkspaceInteraction {
  /// Whether the window that started the workflow still shows it; a workflow
  /// stops asking and reporting once it does not.
  bool get active;

  /// Asks to install [artifact] on [profile]'s host, and whether future
  /// installations may run without asking. Null declines.
  Future<({bool automatic})?> confirmHelperInstall(
    RemoteHostProfile profile,
    RemoteHelperArtifact artifact,
  );

  /// Opens the host dialog, optionally with [profileId] selected; with
  /// [choosing] the user picks a host, which completes with its ID.
  Future<String?> showHosts({String? profileId, bool choosing = false});

  /// Offers to save a host with SSH alias [alias], which no profile has
  /// yet; completes with the saved profile, or null when the user declined.
  Future<RemoteHostProfile?> addHost(String alias);

  /// Lets the user choose a folder on [profile]'s host.
  Future<List<int>?> chooseFolder(
    RemoteHostProfile profile, {
    bool forInitialize = false,
  });

  void reportFailure(RemoteFailureCode code, {String? alias});

  void reportSaveFailure(Object error);

  void reportMessage(RemoteWorkflowMessage message);

  void reportDisabled(AppCommandDisabledReason reason);
}

/// Messages a workflow reports that are not a [RemoteFailureCode].
enum RemoteWorkflowMessage { openFailed, repositoryCapacity, recentHostMissing }

/// The window's remote workspace workflows: connecting for use, installing
/// the helper, reconnecting, changing a host's access, opening and creating
/// repositories on hosts. One instance serves a window, so concurrent
/// requests for a host share one attempt and every control sees it.
final class RemoteWorkspaceWorkflows {
  RemoteWorkspaceWorkflows({required this.service, required this.repositories});

  /// Absent when remote workspaces are unavailable in this build or test.
  final RemoteWorkspaceService? service;
  final RepositorySessionService repositories;
  final Map<String, Future<void>> _reconnects = {};
  final Map<String, Future<bool>> _installs = {};
  final StreamController<void> _activity = StreamController<void>.broadcast(
    sync: true,
  );
  var _disposed = false;

  /// Fires whenever a reconnect or installation the user started begins or
  /// ends.
  Stream<void> get activity => _activity.stream;

  Future<T> _track<T>(
    Map<String, Future<T>> running,
    String profileId,
    Future<T> Function() start,
  ) {
    final existing = running[profileId];
    if (existing != null) return existing;
    _notify();
    return running[profileId] = start().whenComplete(() {
      running.remove(profileId);
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) _activity.add(null);
  }

  /// Whether this build offers remote workspaces.
  bool get enabled => service != null;

  /// What [tab] may do on its host; null for a local tab.
  RemoteTabAccess? accessFor(RepositoryTabState? tab) {
    if (tab == null) return null;
    final authority = (tab.canonicalIdentity ?? tab.requestedIdentity)?.remote;
    if (authority == null) return null;
    final connected = !repositories.isRemoteTabStale(tab);
    final state = service?.state(authority.profileId);
    return RemoteTabAccess(
      profileId: authority.profileId,
      connected: connected,
      capabilities: connected && (state?.ready ?? false)
          ? state?.helper?.capabilities ?? const {}
          : const {},
      writeBlock: service?.writeBlock(authority.profileId),
    );
  }

  String? hostLabel(RemoteAuthority authority) =>
      service?.profile(authority.profileId)?.label;

  RemoteConnectionState state(String profileId) =>
      service?.state(profileId) ??
      RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.idle,
      );

  RemoteReconnectState? reconnectState(String profileId) =>
      repositories.remoteReconnect.stateOf(profileId);

  void stopReconnecting(String profileId) =>
      repositories.remoteReconnect.stop(profileId);

  /// Whether [profileId] is connecting right now.
  bool connecting(String profileId) =>
      _installs.containsKey(profileId) ||
      _reconnects.containsKey(profileId) ||
      reconnectState(profileId)?.phase == RemoteReconnectPhase.connecting ||
      switch (state(profileId).phase) {
        RemoteConnectionPhase.installing ||
        RemoteConnectionPhase.connecting ||
        RemoteConnectionPhase.handshaking => true,
        _ => false,
      };

  bool needsHelper(String profileId) => RemoteWorkspaceService.installResolves(
    reconnectState(profileId)?.failure ?? state(profileId).failure,
  );

  List<RemoteHostProfile> get hosts =>
      enabled ? service?.profiles ?? const [] : const [];

  /// Installs this version's helper on [profileId]'s host after the user
  /// confirmed it, then reconnects the host's tabs. Without a helper to
  /// install the host dialog shows the manual setup. Concurrent requests
  /// share one installation. Completes with whether the host is connected.
  Future<bool> installHelper(
    RemoteWorkspaceInteraction interaction,
    String profileId,
  ) => _track(
    _installs,
    profileId,
    () => _installHelper(interaction, profileId),
  );

  Future<bool> _installHelper(
    RemoteWorkspaceInteraction interaction,
    String profileId,
  ) async {
    final service = this.service;
    final profile = service?.profile(profileId);
    if (service == null || profile == null) return false;
    final artifact = await service.installableHelper(profileId);
    if (!interaction.active) return false;
    if (artifact == null) {
      await interaction.showHosts(profileId: profileId);
      return service.state(profileId).ready;
    }
    final decision = await interaction.confirmHelperInstall(profile, artifact);
    if (decision == null || !interaction.active) return false;
    if (decision.automatic != profile.autoInstallHelper) {
      try {
        await service.setAutoInstallHelper(profileId, decision.automatic);
      } on Object catch (error) {
        // The installation still runs; only the preference was not saved.
        if (interaction.active) interaction.reportSaveFailure(error);
      }
    }
    final RemoteConnectionState result;
    try {
      result = await service.installHelper(profileId, artifact);
    } on RemoteWorkspaceException catch (error) {
      if (interaction.active && error.code != RemoteFailureCode.canceled) {
        interaction.reportFailure(error.code, alias: profile.alias);
      }
      return false;
    }
    if (!interaction.active) return result.ready;
    if (result.ready) {
      // The host is connected; its tabs reopen on the new connection. This
      // never goes through [reconnect], which may be waiting for this
      // installation.
      try {
        await repositories.remoteReconnect.reconnectNow(profileId);
      } on Object {
        // A tab that could not reopen shows its own failure.
      }
      return true;
    }
    if (result.phase == RemoteConnectionPhase.identityChanged) {
      await interaction.showHosts(profileId: profileId);
      return false;
    }
    if (result.failure case final failure?) {
      interaction.reportFailure(failure, alias: profile.alias);
    }
    return false;
  }

  /// Chooses a host, then a folder on it, and opens the repository there.
  /// [open] replaces opening a new tab, as a chooser tab does for itself.
  Future<void> openRemoteRepository(
    RemoteWorkspaceInteraction interaction, {
    Future<void> Function(NativePathIdentity identity)? open,
  }) async {
    final service = this.service;
    if (service == null) return;
    final profileId = await interaction.showHosts(choosing: true);
    if (profileId == null || !interaction.active) return;
    final profile = service.profile(profileId);
    final authority = profile?.authority;
    if (profile == null || authority == null) return;
    final path = await interaction.chooseFolder(profile);
    if (path == null || !interaction.active) return;
    try {
      if (open != null) {
        await open(
          RepositorySessionService.remotePathIdentity(authority, path),
        );
      } else {
        await repositories.openRemoteRepository(authority, path);
      }
    } on RepositorySessionException catch (error) {
      if (interaction.active) {
        interaction.reportMessage(
          error.failure.code == RepositoryFailureCode.capacity
              ? RemoteWorkflowMessage.repositoryCapacity
              : RemoteWorkflowMessage.openFailed,
        );
      }
    }
  }

  /// Opens [path] on the saved host with SSH alias [alias], as asked from
  /// the command line: offers to save an unknown alias as a host first, so
  /// connecting to a new host stays the user's decision, then connects the
  /// host and opens the path in a tab, or activates the tab that shows it.
  Future<void> openOnHost(
    RemoteWorkspaceInteraction interaction,
    String alias,
    List<int> path,
  ) async {
    final service = this.service;
    if (service == null) {
      interaction.reportFailure(RemoteFailureCode.unsupportedPlatform);
      return;
    }
    var profile = service.profiles
        .where((profile) => profile.alias == alias)
        .firstOrNull;
    profile ??= await interaction.addHost(alias);
    if (profile == null || !interaction.active) return;
    if (!await connectForUse(interaction, profile) || !interaction.active) {
      return;
    }
    // Connecting verifies a new host, which gives the profile its authority.
    final authority = service.profile(profile.id)?.authority;
    if (authority == null) {
      interaction.reportMessage(RemoteWorkflowMessage.openFailed);
      return;
    }
    try {
      await repositories.openRecent(
        RepositorySessionService.remotePathIdentity(authority, path),
      );
    } on RepositorySessionException catch (error) {
      if (interaction.active) {
        interaction.reportMessage(
          error.failure.code == RepositoryFailureCode.capacity
              ? RemoteWorkflowMessage.repositoryCapacity
              : RemoteWorkflowMessage.openFailed,
        );
      }
    }
  }

  /// Reconnects a host whose access changed, with its tabs.
  Future<void> applyAccess(String profileId) =>
      repositories.applyRemoteAccess(profileId);

  /// Lets GitLama only read on [profileId]'s host, or also change its
  /// repositories. A live connection reconnects with its tabs at once, since
  /// what a connection may do is agreed when it starts.
  Future<void> setAccess(
    RemoteWorkspaceInteraction interaction,
    String profileId, {
    required bool allowChanges,
  }) async {
    final service = this.service;
    final profile = service?.profile(profileId);
    if (service == null ||
        profile == null ||
        profile.writesAllowed == allowChanges) {
      return;
    }
    try {
      await service.setWritesAllowed(profileId, allowChanges);
      if (service.state(profileId).ready) await applyAccess(profileId);
    } on Object catch (error) {
      if (interaction.active) interaction.reportSaveFailure(error);
    }
  }

  /// Closes [profileId]'s connection; its tabs keep their last state.
  Future<void> disconnect(String profileId) async {
    try {
      await service?.disconnect(profileId);
    } on Object {
      // The connection reports its own state; closing is best effort.
    }
  }

  /// Connects [profileId] again and reopens its tabs in place. Concurrent
  /// requests share one attempt; a changed identity opens the host dialog
  /// for an explicit decision.
  Future<void> reconnect(
    RemoteWorkspaceInteraction interaction,
    String profileId,
  ) => _track(_reconnects, profileId, () => _reconnect(interaction, profileId));

  Future<void> _reconnect(
    RemoteWorkspaceInteraction interaction,
    String profileId,
  ) async {
    RemoteConnectionState? result;
    RemoteFailureCode? failure;
    try {
      result = await repositories.remoteReconnect.reconnectNow(profileId);
    } on RemoteWorkspaceException catch (error) {
      failure = error.code;
    } on RepositorySessionException {
      failure = RemoteFailureCode.internal;
    }
    if (!interaction.active) return;
    if (result?.phase == RemoteConnectionPhase.identityChanged) {
      await interaction.showHosts(profileId: profileId);
      return;
    }
    failure ??= result == null || result.ready
        ? null
        : result.failure ?? RemoteFailureCode.disconnected;
    // A missing or broken helper is fixed where it happened, unless this
    // reconnect follows an installation.
    if (RemoteWorkspaceService.installResolves(failure) &&
        !_installs.containsKey(profileId)) {
      await installHelper(interaction, profileId);
      return;
    }
    // A failure that is retried shows in the tab with its next attempt.
    if (failure != null &&
        failure != RemoteFailureCode.canceled &&
        !remoteFailureRetriable(failure)) {
      interaction.reportFailure(
        failure,
        alias: service?.profile(profileId)?.alias,
      );
    }
  }

  /// Opens a recent remote repository, connecting its host first. [open]
  /// replaces the default of opening it in a new tab.
  Future<void> openRecent(
    RemoteWorkspaceInteraction interaction,
    NativePathIdentity identity, {
    Future<void> Function()? open,
  }) async {
    final authority = identity.remote;
    final service = this.service;
    if (authority == null || service == null) return;
    final profile = service.profile(authority.profileId);
    if (profile == null || profile.authority != authority) {
      interaction.reportMessage(RemoteWorkflowMessage.recentHostMissing);
      return;
    }
    if (!await connectForUse(interaction, profile) || !interaction.active) {
      return;
    }
    try {
      if (open != null) {
        await open();
      } else {
        await repositories.openRecent(identity);
      }
    } on RepositorySessionException catch (error) {
      if (interaction.active) {
        interaction.reportMessage(
          error.failure.code == RepositoryFailureCode.capacity
              ? RemoteWorkflowMessage.repositoryCapacity
              : RemoteWorkflowMessage.openFailed,
        );
      }
    }
  }

  /// Connects [profile]'s host for something the user asked for, installing
  /// its helper or showing the host dialog where that resolves a failure.
  /// Reports any other failure and completes with whether the host is ready.
  Future<bool> connectForUse(
    RemoteWorkspaceInteraction interaction,
    RemoteHostProfile profile,
  ) async {
    final service = this.service;
    if (service == null) return false;
    final RemoteConnectionState state;
    try {
      state = await service.connect(profile.id);
    } on RemoteWorkspaceException catch (error) {
      if (interaction.active) {
        interaction.reportFailure(error.code, alias: profile.alias);
      }
      return false;
    }
    if (!interaction.active) return false;
    if (state.phase == RemoteConnectionPhase.identityChanged) {
      await interaction.showHosts(profileId: profile.id);
      return false;
    }
    if (!state.ready && RemoteWorkspaceService.installResolves(state.failure)) {
      return await installHelper(interaction, profile.id) && interaction.active;
    }
    if (!state.ready) {
      if (state.failure case final failure?) {
        interaction.reportFailure(failure, alias: profile.alias);
      }
      return false;
    }
    return true;
  }

  /// Whether repositories can be created on [profileId]'s host as far as the
  /// profile tells before connecting: null when they may be.
  RemoteInitializeBlock? initializeBlock(String profileId) {
    final profile = service?.profile(profileId);
    if (profile == null) return RemoteInitializeBlock.hostMissing;
    return profile.writesAllowed ? null : RemoteInitializeBlock.writesOff;
  }

  /// Creates a repository on [profileId]'s host and opens it in a new tab:
  /// connects the host when needed, lets the user choose an empty folder or
  /// type a new one, then initializes it there. Completes with null when the
  /// user canceled or a connection failure was reported. The host's reasons
  /// for creating nothing arrive as [RepositorySessionException], with the
  /// codes of initializing a repository on this computer.
  Future<RepositorySessionState?> initializeRemoteRepository(
    RemoteWorkspaceInteraction interaction,
    String profileId, {
    required bool bare,
  }) async {
    final service = this.service;
    final selected = service?.profile(profileId);
    if (service == null || selected == null) return null;
    if (!await connectForUse(interaction, selected) || !interaction.active) {
      return null;
    }
    // Changes allowed after the connection started need a new connection,
    // as a changed access does elsewhere; the host's tabs reopen on it.
    if (service.writeBlock(profileId) == RemoteWriteBlock.reconnect) {
      try {
        await applyAccess(profileId);
      } on Object {
        // The capability check below reports what is still missing.
      }
      if (!interaction.active) return null;
    }
    // A first connection verifies the host and sets its authority.
    final profile = service.profile(profileId);
    final authority = profile?.authority;
    if (profile == null || authority == null) return null;
    if (service.canInitialize(profileId) != true) {
      interaction.reportDisabled(
        remoteCapabilityReason(
              RemoteTabAccess(
                profileId: profileId,
                connected: true,
                capabilities:
                    service.state(profileId).helper?.capabilities ?? const {},
                writeBlock: service.writeBlock(profileId),
              ),
              RemoteCapability.initialize,
            ) ??
            AppCommandDisabledReason.remoteWritesUnavailable,
      );
      return null;
    }
    final path = await interaction.chooseFolder(profile, forInitialize: true);
    if (path == null || !interaction.active) return null;
    try {
      return await repositories.initializeRemote(authority, path, bare: bare);
    } on RemoteWorkspaceException catch (error) {
      if (interaction.active) {
        interaction.reportFailure(error.code, alias: profile.alias);
      }
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _activity.close();
  }
}

/// Why a repository cannot be created on a host before connecting to it.
enum RemoteInitializeBlock { hostMissing, writesOff }
