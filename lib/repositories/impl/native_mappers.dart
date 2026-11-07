/// Mappers between the bridge types and the app models that more than one
/// native repository implementation uses. Repository implementations share
/// these instead of importing each other.
library;

import 'package:devmil_logging/devmil_logging.dart';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';

import '../../models/activity.dart';
import '../../models/app_shortcut.dart';
import '../../models/app_update.dart';
import '../../models/diff.dart';
import '../../models/diff_renderer.dart';
import '../../models/hosting.dart';
import '../../models/integrations.dart';
import '../../models/operation_center.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../rust/third_party/gitlama_contract/dto.dart' as native_api;
import '../../rust/frb_generated.dart';
import '../../rust/api.dart' as diagnostic_api;
import '../../rust/third_party/gitlama_contract/storage.dart' as native;
import '../../rust/third_party/gitlama_contract/diff_renderer.dart' as native;
import '../../rust/third_party/gitlama_contract/hosting_settings.dart'
    as native;
import '../../rust/third_party/gitlama_contract/integrations.dart' as native;
import '../../rust/third_party/gitlama_contract/domain/path_identity.dart'
    as native;
import 'native_enum_mappers.g.dart';

SettingsDocument settingsDocumentFromNative(
  native.NativeSettingsDocument document,
) => SettingsDocument(
  appearance: AppearanceSettings(
    theme: document.appearance.theme,
    density: document.appearance.density,
    reduceMotion: document.appearance.reduceMotion,
    dateFormat: document.appearance.dateFormat,
    gravatarEnabled: document.appearance.gravatarEnabled,
    sidebarWidth: document.appearance.sidebarWidth,
    diffWidth: document.appearance.diffWidth,
    changesUnstagedMode: document.appearance.changesUnstagedMode,
    changesStagedMode: document.appearance.changesStagedMode,
    changesSplitRatio: document.appearance.changesSplitRatio,
    commitFilesMode: document.appearance.commitFilesMode,
    inspectionOpenIn: document.appearance.inspectionOpenIn,
    diffView: DiffViewPreferences(
      wrap: document.appearance.diffWrap,
      layout: DiffViewLayout.values.byName(document.appearance.diffLayout),
      whitespace: DiffWhitespace.values.byName(
        document.appearance.diffWhitespace,
      ),
      contextLines: document.appearance.diffContextLines,
      showIndicators: document.appearance.diffIndicators,
      showMinimap: document.appearance.diffMinimap,
    ),
    historyOtherRefs: document.appearance.historyOtherRefs,
    windowX: document.appearance.windowX,
    windowY: document.appearance.windowY,
    windowWidth: document.appearance.windowWidth?.toInt(),
    windowHeight: document.appearance.windowHeight?.toInt(),
    windowMaximized: document.appearance.windowMaximized,
  ),
  recentRepositories: [
    for (final identity in document.recentRepositories)
      pathIdentityFromNative(identity),
  ],
  worktrees: [
    for (final worktree in document.worktrees)
      WorktreeSettings(
        identity: pathIdentityFromNative(worktree.identity),
        filter: worktree.filter,
        anchor: worktree.anchor,
        pane: worktree.pane,
        route: worktree.route,
        changesScrollOffset: worktree.changesScrollOffset.toInt(),
        historyScrollOffset: worktree.historyScrollOffset.toInt(),
        draft: CommitDraft(
          subject: worktree.draft.subject,
          description: worktree.draft.description,
        ),
        branchFilter: List.unmodifiable(worktree.branchFilter),
      ),
  ],
  openWorktrees: [
    for (final identity in document.openWorktrees)
      pathIdentityFromNative(identity),
  ],
  activeWorktree: document.activeWorktree == null
      ? null
      : pathIdentityFromNative(document.activeWorktree!),
  integrations: [
    for (final integration in document.integrations)
      IntegrationDefinition(
        id: integration.id,
        kind: IntegrationKind.values.byName(integration.kind),
        executable: pathIdentityFromNative(integration.executable),
        arguments: List.unmodifiable(integration.arguments),
        execution: integration.explicitShell
            ? IntegrationExecution.explicitShell
            : IntegrationExecution.direct,
        launchMode: integration.wait
            ? IntegrationLaunchMode.wait
            : IntegrationLaunchMode.detached,
        requiresConfirmation: integration.requiresConfirmation,
        timeoutSeconds: integration.timeoutSeconds,
      ),
  ],
  diffRenderer: document.diffRenderer == null
      ? null
      : DiffRendererDefinition(
          id: document.diffRenderer!.id,
          title: document.diffRenderer!.title,
          executable: pathIdentityFromNative(document.diffRenderer!.executable),
          arguments: List.unmodifiable(document.diffRenderer!.arguments),
        ),
  hostingConnections: [
    for (final connection in document.hostingConnections)
      HostingConnection(
        id: connection.id,
        preset: _hostingPresetFromStorage(connection.preset),
        login: connection.login,
        webBaseUrl: connection.webBaseUrl,
        apiBaseUrl: connection.apiBaseUrl,
        oauthClientId: connection.oauthClientId,
        authentication: _hostingAuthenticationFromStorage(
          connection.authentication,
        ),
        enabled: connection.enabled,
        refreshEnabled: connection.refreshEnabled,
        capabilities: [
          for (final capability in connection.capabilities)
            HostingCapability.values.byName(capability),
        ],
        credentialIdentity: connection.credentialIdentity,
        allowSplitOrigin: connection.allowSplitOrigin,
      ),
  ],
  hostingBindings: [
    for (final binding in document.hostingBindings)
      HostingBindingOverride(
        repository: pathIdentityFromNative(binding.repository),
        remote: binding.remote,
        connectionId: binding.connectionId,
        providerRepository: binding.providerRepository,
      ),
  ],
  hostingExpandedNodes: List.unmodifiable(document.hostingExpandedNodes),
  shortcutOverrides: [
    for (final override in document.shortcutOverrides)
      if (!AppShortcutCatalog.retiredCommandIds.contains(override.commandId))
        ShortcutOverride(
          commandId: override.commandId,
          binding: override.binding,
        ),
  ],
  repositoryAppearances: [
    for (final appearance in document.repositoryAppearances)
      RepositoryAppearance(
        identity: pathIdentityFromNative(appearance.identity),
        icon: appearance.icon,
        color: appearance.color,
        image: appearance.image == null
            ? null
            : pathIdentityFromNative(appearance.image!),
        name: appearance.name,
      ),
  ],
  releaseChannel: ReleaseChannel.fromStorage(document.releaseChannel),
  autoFetch: AutoFetchSettings(
    enabled: document.autoFetch.enabled,
    intervalMinutes: document.autoFetch.intervalMinutes,
  ),
  repositoryOptions: [
    for (final options in document.repositoryOptions)
      RepositoryOptions(
        identity: pathIdentityFromNative(options.identity),
        autoFetch: options.autoFetch,
      ),
  ],
  tabGroups: [
    for (final group in document.tabGroups)
      TabGroupSettings(
        name: group.name,
        color: group.color,
        icon: group.icon,
        collapsed: group.collapsed,
        members: [
          for (final member in group.members) pathIdentityFromNative(member),
        ],
      ),
  ],
  remoteProfiles: [
    for (final profile in document.remoteProfiles)
      RemoteHostProfile(
        id: profile.id,
        label: profile.label,
        alias: profile.alias,
        verified: profile.verified == null
            ? null
            : RemoteVerifiedIdentity(
                storeId: profile.verified!.storeId,
                accountUid: profile.verified!.accountUid,
                accountName: profile.verified!.accountName,
              ),
        writesAllowed: profile.writesAllowed,
        autoInstallHelper: profile.autoInstallHelper,
        color: profile.color,
        icon: profile.icon,
      ),
  ],
);

NativePathIdentity pathIdentityFromNative(native.NativePathIdentity identity) =>
    NativePathIdentity(
      platform: identity.platform.toModel(),
      units: identity.units,
      remote: identity.remote == null
          ? null
          : RemoteAuthority(
              profileId: identity.remote!.profileId,
              storeId: identity.remote!.storeId,
              accountUid: identity.remote!.accountUid,
            ),
    );

native.NativeSettingsDocument settingsDocumentToNative(
  SettingsDocument document,
) => native.NativeSettingsDocument(
  appearance: native.NativeAppearanceSettings(
    theme: document.appearance.theme,
    density: document.appearance.density,
    reduceMotion: document.appearance.reduceMotion,
    dateFormat: document.appearance.dateFormat,
    gravatarEnabled: document.appearance.gravatarEnabled,
    sidebarWidth: document.appearance.sidebarWidth,
    diffWidth: document.appearance.diffWidth,
    changesUnstagedMode: document.appearance.changesUnstagedMode,
    changesStagedMode: document.appearance.changesStagedMode,
    changesSplitRatio: document.appearance.changesSplitRatio,
    commitFilesMode: document.appearance.commitFilesMode,
    inspectionOpenIn: document.appearance.inspectionOpenIn,
    diffWrap: document.appearance.diffView.wrap,
    diffLayout: document.appearance.diffView.layout.name,
    diffWhitespace: document.appearance.diffView.whitespace.name,
    diffContextLines: document.appearance.diffView.contextLines,
    diffIndicators: document.appearance.diffView.showIndicators,
    diffMinimap: document.appearance.diffView.showMinimap,
    historyOtherRefs: document.appearance.historyOtherRefs,
    windowX: document.appearance.windowX,
    windowY: document.appearance.windowY,
    windowWidth: document.appearance.windowWidth,
    windowHeight: document.appearance.windowHeight,
    windowMaximized: document.appearance.windowMaximized,
  ),
  recentRepositories: [
    for (final identity in document.recentRepositories)
      pathIdentityToNative(identity),
  ],
  worktrees: [
    for (final worktree in document.worktrees)
      native.NativeWorktreeSettings(
        identity: pathIdentityToNative(worktree.identity),
        filter: worktree.filter,
        anchor: worktree.anchor,
        pane: worktree.pane,
        route: worktree.route,
        changesScrollOffset: BigInt.from(worktree.changesScrollOffset),
        historyScrollOffset: BigInt.from(worktree.historyScrollOffset),
        draft: native.NativeCommitDraft(
          subject: worktree.draft.subject,
          description: worktree.draft.description,
        ),
        branchFilter: worktree.branchFilter,
      ),
  ],
  openWorktrees: [
    for (final identity in document.openWorktrees)
      pathIdentityToNative(identity),
  ],
  activeWorktree: document.activeWorktree == null
      ? null
      : pathIdentityToNative(document.activeWorktree!),
  integrations: [
    for (final integration in document.integrations)
      native.NativeIntegrationSettings(
        id: integration.id,
        kind: integration.kind.name,
        executable: pathIdentityToNative(integration.executable),
        arguments: integration.arguments,
        explicitShell:
            integration.execution == IntegrationExecution.explicitShell,
        wait: integration.launchMode == IntegrationLaunchMode.wait,
        requiresConfirmation: integration.requiresConfirmation,
        timeoutSeconds: integration.timeoutSeconds,
      ),
  ],
  diffRenderer: document.diffRenderer == null
      ? null
      : native.NativeDiffRendererSettings(
          id: document.diffRenderer!.id,
          title: document.diffRenderer!.title,
          executable: pathIdentityToNative(document.diffRenderer!.executable),
          arguments: document.diffRenderer!.arguments,
        ),
  hostingConnections: [
    for (final connection in document.hostingConnections)
      native.NativeHostingConnectionSettings(
        id: connection.id,
        preset: connection.preset.storageName,
        login: connection.login,
        webBaseUrl: connection.webBaseUrl,
        apiBaseUrl: connection.apiBaseUrl,
        oauthClientId: connection.oauthClientId,
        authentication: connection.authentication.storageName,
        enabled: connection.enabled,
        refreshEnabled: connection.refreshEnabled,
        capabilities: [
          for (final capability in connection.capabilities) capability.name,
        ],
        credentialIdentity: connection.credentialIdentity,
        allowSplitOrigin: connection.allowSplitOrigin,
      ),
  ],
  hostingBindings: [
    for (final binding in document.hostingBindings)
      native.NativeHostingBindingSettings(
        repository: pathIdentityToNative(binding.repository),
        remote: binding.remote,
        connectionId: binding.connectionId,
        providerRepository: binding.providerRepository,
      ),
  ],
  hostingExpandedNodes: document.hostingExpandedNodes,
  shortcutOverrides: [
    for (final override in document.shortcutOverrides)
      native.NativeShortcutOverride(
        commandId: override.commandId,
        binding: override.binding,
      ),
  ],
  repositoryAppearances: [
    for (final appearance in document.repositoryAppearances)
      native.NativeRepositoryAppearance(
        identity: pathIdentityToNative(appearance.identity),
        icon: appearance.icon,
        color: appearance.color,
        image: appearance.image == null
            ? null
            : pathIdentityToNative(appearance.image!),
        name: appearance.name,
      ),
  ],
  releaseChannel: document.releaseChannel?.name,
  autoFetch: native.NativeAutoFetchSettings(
    enabled: document.autoFetch.enabled,
    intervalMinutes: document.autoFetch.intervalMinutes,
  ),
  repositoryOptions: [
    for (final options in document.repositoryOptions)
      native.NativeRepositoryOptions(
        identity: pathIdentityToNative(options.identity),
        autoFetch: options.autoFetch,
      ),
  ],
  tabGroups: [
    for (final group in document.tabGroups)
      native.NativeTabGroup(
        name: group.name,
        color: group.color,
        icon: group.icon,
        collapsed: group.collapsed,
        members: [
          for (final member in group.members) pathIdentityToNative(member),
        ],
      ),
  ],
  remoteProfiles: [
    for (final profile in document.remoteProfiles)
      native.NativeRemoteHostProfile(
        id: profile.id,
        label: profile.label,
        alias: profile.alias,
        verified: profile.verified == null
            ? null
            : native.NativeRemoteVerifiedIdentity(
                storeId: profile.verified!.storeId,
                accountUid: profile.verified!.accountUid,
                accountName: profile.verified!.accountName,
              ),
        writesAllowed: profile.writesAllowed,
        autoInstallHelper: profile.autoInstallHelper,
        color: profile.color,
        icon: profile.icon,
      ),
  ],
  // Remote workspaces are always on; older versions read this switch.
  remoteWorkspacesEnabled: true,
);

native.NativePathIdentity pathIdentityToNative(NativePathIdentity identity) =>
    native.NativePathIdentity(
      platform: identity.platform.toNative(),
      units: identity.units,
      remote: identity.remote == null
          ? null
          : native.NativeRemoteAuthority(
              profileId: identity.remote!.profileId,
              storeId: identity.remote!.storeId,
              accountUid: identity.remote!.accountUid,
            ),
    );

HostingPreset _hostingPresetFromStorage(String value) =>
    HostingPreset.values
        .where((preset) => preset.storageName == value)
        .firstOrNull ??
    (throw const SettingsException(SettingsFailureCode.invalidDocument));

HostingAuthentication _hostingAuthenticationFromStorage(String value) =>
    HostingAuthentication.values
        .where((authentication) => authentication.storageName == value)
        .firstOrNull ??
    (throw const SettingsException(SettingsFailureCode.invalidDocument));

({RepositorySessionIdentity identity, RepositorySnapshot snapshot})
repositorySessionFromNative(native_api.NativeRepositorySession session) {
  return (
    identity: RepositorySessionIdentity(
      nativeId: session.sessionId,
      generation: session.generation.toInt(),
    ),
    snapshot: repositorySnapshotFromNative(session.snapshot),
  );
}

RepositorySnapshot repositorySnapshotFromNative(
  native_api.NativeRepositorySnapshot snapshot,
) => RepositorySnapshot(
  revision: snapshot.revision,
  phase: snapshot.phase.toModel(),
  failure: repositoryFailureFromNative(snapshot.failure),
  watchFailure: repositoryFailureFromNative(snapshot.watchFailure),
  identity: snapshot.identity == null
      ? null
      : _repositoryIdentityFromNative(snapshot.identity!),
  status: snapshot.status == null
      ? null
      : _repositoryStatusFromNative(snapshot.status!),
  statusFailure: repositoryFailureFromNative(snapshot.statusFailure),
  refsFailure: repositoryFailureFromNative(snapshot.refsFailure),
  refCounts: RepositoryRefCounts(
    branches: snapshot.refCounts.branches.toInt(),
    remotes: snapshot.refCounts.remotes.toInt(),
    tags: snapshot.refCounts.tags.toInt(),
    stashes: snapshot.refCounts.stashes.toInt(),
    worktrees: snapshot.refCounts.worktrees.toInt(),
  ),
  refs: RepositoryRefs(
    branches: [
      for (final reference in snapshot.refs.branches)
        RepositoryReference(
          name: List.unmodifiable(reference.name),
          fullName: List.unmodifiable(reference.fullName),
          target: reference.target,
          head: reference.head,
          published: reference.published,
          upstream: reference.upstream == null
              ? null
              : List.unmodifiable(reference.upstream!),
          ahead: reference.ahead.toInt(),
          behind: reference.behind.toInt(),
          upstreamGone: reference.upstreamGone,
        ),
    ],
    remotes: [
      for (final remote in snapshot.refs.remotes)
        RepositoryRemote(
          name: List.unmodifiable(remote.name),
          displayUrl: List.unmodifiable(remote.displayUrl),
          branches: [
            for (final reference in remote.branches)
              RepositoryReference(
                name: List.unmodifiable(reference.name),
                fullName: List.unmodifiable(reference.fullName),
                target: reference.target,
                head: reference.head,
                published: reference.published,
              ),
          ],
        ),
    ],
    tags: [
      for (final reference in snapshot.refs.tags)
        RepositoryReference(
          name: List.unmodifiable(reference.name),
          fullName: List.unmodifiable(reference.fullName),
          target: reference.target,
          head: reference.head,
          published: reference.published,
        ),
    ],
    stashes: [
      for (final stash in snapshot.refs.stashes)
        RepositoryStash(
          selector: List.unmodifiable(stash.selector),
          objectId: stash.objectId,
          subject: List.unmodifiable(stash.subject),
        ),
    ],
    truncated: snapshot.refs.truncated,
  ),
);

RepositoryStatus _repositoryStatusFromNative(
  native_api.NativeRepositoryStatus status,
) => RepositoryStatus(
  workingTree: status.workingTree.toModel(),
  branchName: status.branchName,
  headObjectId: status.headObjectId,
  upstream: status.upstream,
  ahead: status.ahead,
  behind: status.behind,
  entries: [
    for (final entry in status.entries)
      RepositoryStatusEntry(
        kind: entry.kind.toModel(),
        path: pathIdentityFromNative(entry.path),
        source: entry.source == null
            ? null
            : pathIdentityFromNative(entry.source!),
        index: entry.index.toModel(),
        worktree: entry.worktree.toModel(),
      ),
  ],
  totalEntries: status.totalEntries,
  entriesTruncated: status.entriesTruncated,
  operations: [
    for (final operation in status.operations)
      RepositoryOperationState(
        kind: operation.kind.toModel(),
        current: operation.current,
        total: operation.total,
      ),
  ],
);

RepositoryIdentity _repositoryIdentityFromNative(
  native_api.NativeRepositoryIdentity identity,
) => RepositoryIdentity(
  commonGitDir: pathIdentityFromNative(identity.commonGitDir),
  worktreeRoot: pathIdentityFromNative(identity.worktreeRoot),
  gitDir: pathIdentityFromNative(identity.gitDir),
  kind: identity.kind.toModel(),
  headKind: identity.headKind.toModel(),
  headReference: identity.headReference,
  headObjectId: identity.headObjectId,
  gitMajor: identity.gitMajor,
  gitMinor: identity.gitMinor,
  gitPatch: identity.gitPatch,
);

RepositoryFailure? repositoryFailureFromNative(
  native_api.NativeRepositoryFailure? failure,
) => failure == null ? null : RepositoryFailure(failure.kind.toModel());

Never _throwRepositoryFailure(native_api.NativeRepositoryFailure failure) =>
    throw RepositorySessionException(RepositoryFailure(failure.kind.toModel()));

void throwRepositoryFailure(native_api.NativeRepositoryFailure? failure) {
  if (failure != null) _throwRepositoryFailure(failure);
}

void throwRepositoryCommandFailure(
  native_api.NativeRepositoryCommandResult result,
) {
  throwRepositoryFailure(result.failure);
  if (!result.accepted) {
    throw const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.closed),
    );
  }
}

Future<void>? _bridge;

/// Loads the native library once per process; a failed load is retried
/// by the next call.
Future<void> ensureNativeCoreLoaded() => _bridge ??= Future<void>(_load);

Future<void> _load() async {
  try {
    final executable = File(Platform.resolvedExecutable);
    final path = switch (Platform.operatingSystem) {
      'macos' =>
        '${executable.parent.parent.path}/Frameworks/'
            'gitlama_core.framework/gitlama_core',
      'linux' => '${executable.parent.path}/lib/libgitlama_core.so',
      'windows' => '${executable.parent.path}/gitlama_core.dll',
      _ => throw UnsupportedError('unsupported_platform'),
    };
    await RustLib.init(externalLibrary: ExternalLibrary.open(path));
    _nativeDiagnostics ??= NativeDiagnosticBridge(
      detach: diagnostic_api.detachNativeDiagnostics,
      drain: diagnostic_api.drainNativeDiagnostics,
      configure: (detailed, clear) => diagnostic_api.configureNativeDiagnostics(
        detailed: detailed,
        clear: clear,
      ),
    )..start(diagnostic_api.watchNativeDiagnostics());
  } on Object {
    _bridge = null;
    rethrow;
  }
}

/// The application view of a native operation center snapshot. Remote
/// helpers report theirs with [backend] remote and local session ids.
OperationCenterSnapshot operationCenterFromNative(
  native_api.NativeOperationCenterSnapshot snapshot, {
  RepositoryBackendKind backend = RepositoryBackendKind.local,
}) {
  return OperationCenterSnapshot(
    entries: [
      for (final entry in snapshot.entries)
        OperationCenterEntry(
          activityId: entry.activityId,
          session: entry.sessionId == null
              ? null
              : RepositorySessionIdentity(
                  nativeId: entry.sessionId!,
                  generation: entry.generation.toInt(),
                  backend: backend,
                ),
          cloneAttemptId: entry.cloneAttemptId,
          state: entry.state.toModel(),
          origin: entry.origin.toModel(),
          action: entry.action.toModel(),
          startedAtUnixMs: entry.startedAtUnixMs,
          finishedAtUnixMs: entry.finishedAtUnixMs,
          progress: switch (entry.progress) {
            final progress? => ActivityProgress(
              phase: progress.phase,
              completed: progress.completed,
              total: progress.total,
              unit: progress.unit,
            ),
            null => null,
          },
          canCancel: entry.canCancel,
          canRetry: entry.canRetry,
          hasDetails: entry.hasDetails,
        ),
    ],
    runningCount: snapshot.runningCount,
    failedCount: snapshot.failedCount,
    warningCount: snapshot.warningCount,
    attentionCount: snapshot.attentionCount,
    truncated: snapshot.truncated,
  );
}

NativeDiagnosticBridge? _nativeDiagnostics;
