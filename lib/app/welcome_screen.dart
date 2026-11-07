import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';
import '../models/clone_attempt.dart';
import '../models/operation_center.dart';
import '../models/repository_state.dart';
import '../models/settings.dart';
import '../models/workspace.dart';
import '../services/repository_session_service.dart';
import '../services/workflows/operation_center_actions.dart';
import '../widgets/gitlama_window_caption.dart';
import '../widgets/status_notification.dart';
import 'app_theme.dart';
import 'gitlama_layout.dart';
import 'workspace/labels.dart';
import 'workspace/logbook.dart';
import 'workspace/recent_repositories.dart';
import 'workspace/remote_workspace.dart';

/// The window without open repositories: the open, clone and create actions,
/// the recent repositories and what failed. The home screen owns the
/// workflows; this only shows their state and forwards the user's choices.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.ready,
    required this.busy,
    required this.clone,
    required this.cloneFailure,
    required this.failure,
    required this.recents,
    required this.remote,
    required this.operations,
    required this.operationsVisible,
    required this.workspace,
    required this.repositories,
    required this.operationActions,
    required this.onOpen,
    required this.onOpenRemote,
    required this.onClone,
    required this.onInitialize,
    required this.onCancelClone,
    required this.onRetryCredentials,
    required this.onInspectHostKey,
    required this.onOpenRecent,
    required this.onOpenRemoteRecent,
    required this.onShowSettings,
    required this.onToggleOperations,
  });

  /// A repository is open and ready in this window.
  final bool ready;
  final bool busy;
  final CloneAttemptSnapshot? clone;
  final CloneFailureCode? cloneFailure;
  final RepositoryFailureCode? failure;
  final List<NativePathIdentity> recents;
  final RemoteWorkspaceController remote;
  final OperationCenterSnapshot operations;
  final bool operationsVisible;
  final WorkspaceState workspace;
  final RepositorySessionService repositories;
  final OperationCenterActions operationActions;
  final VoidCallback onOpen;
  final VoidCallback onOpenRemote;
  final VoidCallback onClone;

  /// Creates a repository; true opens the dialog with Bare chosen.
  final ValueChanged<bool> onInitialize;
  final VoidCallback onCancelClone;
  final VoidCallback onRetryCredentials;
  final VoidCallback onInspectHostKey;
  final ValueChanged<NativePathIdentity> onOpenRecent;
  final ValueChanged<NativePathIdentity> onOpenRemoteRecent;
  final VoidCallback onShowSettings;
  final VoidCallback onToggleOperations;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: context.colors.ground,
      bottomNavigationBar: SizedBox(
        height: MeridianLayout.statusBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space3),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusNotificationText(),
          ),
        ),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(MeridianLayout.tabStripHeight),
        child: ColoredBox(
          color: context.colors.ground,
          child: SizedBox(
            height: MeridianLayout.tabStripHeight,
            child: Row(
              children: [
                Expanded(
                  child: GitLamaWindowDragArea(
                    // The title occupies the whole row. Let its text and
                    // padding pass window gestures to the caption below.
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          if (defaultTargetPlatform == TargetPlatform.macOS)
                            const SizedBox(
                              width: MeridianLayout.macOSTrafficLightInset,
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: MeridianSpace.space4,
                              ),
                              child: Text(
                                l10n.appTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodyStrong.copyWith(
                                  color: MeridianTheme.of(context).colors.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Outside the drag area, whose double-tap would delay a tap.
                MeridianIconButton(
                  key: const Key('welcome-settings'),
                  label: l10n.settingsTitle,
                  icon: 'settings',
                  onGround: true,
                  onPressed: onShowSettings,
                ),
                const SizedBox(width: MeridianSpace.space3),
                const GitLamaWindowControls(),
                const SizedBox(width: MeridianSpace.space3),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: GitLamaLayout.contentMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(MeridianSpace.space8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Image.asset(
                                'assets/brand/tile-64.png',
                                width: GitLamaLayout.welcomeMarkSize,
                                height: GitLamaLayout.welcomeMarkSize,
                              ),
                            ),
                            const SizedBox(height: MeridianSpace.space6),
                            Text(
                              ready ? l10n.repositoryReady : l10n.welcomeTitle,
                              textAlign: TextAlign.center,
                              style: context.text.display.copyWith(
                                color: context.colors.ink,
                              ),
                            ),
                            const SizedBox(height: MeridianSpace.space4),
                            Text(
                              ready
                                  ? l10n.repositoryReadyDetail
                                  : l10n.welcomeDetail,
                              textAlign: TextAlign.center,
                              style: context.text.body.copyWith(
                                color: MeridianTheme.of(
                                  context,
                                ).colors.inkMuted,
                              ),
                            ),
                            const SizedBox(height: MeridianSpace.space8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: MeridianSpace.space4,
                              runSpacing: MeridianSpace.space4,
                              children: [
                                MeridianButton(
                                  label: l10n.welcomeOpen,
                                  icon: 'folder-open',
                                  variant: MeridianButtonVariant.primary,
                                  loading: busy,
                                  onPressed: busy ? null : onOpen,
                                ),
                                if (remote.enabled)
                                  MeridianButton(
                                    key: const ValueKey('welcome-open-remote'),
                                    label: l10n.openRemoteRepository,
                                    icon: 'server',
                                    onPressed: busy ? null : onOpenRemote,
                                  ),
                                MeridianButton(
                                  label: l10n.welcomeClone,
                                  icon: 'fetch',
                                  loading:
                                      clone?.phase == CloneAttemptPhase.running,
                                  onPressed: busy ? null : onClone,
                                ),
                                MeridianButton(
                                  label: l10n.welcomeCreate,
                                  icon: 'plus',
                                  loading: busy,
                                  onPressed: busy
                                      ? null
                                      : () => onInitialize(false),
                                ),
                                MeridianButton(
                                  label: l10n.initializeBareRepository,
                                  variant: MeridianButtonVariant.quiet,
                                  loading: busy,
                                  onPressed: busy
                                      ? null
                                      : () => onInitialize(true),
                                ),
                              ],
                            ),
                            if (clone?.phase == CloneAttemptPhase.running) ...[
                              const SizedBox(height: MeridianSpace.space4),
                              MeridianProgressBar(value: cloneProgress(clone!)),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: MeridianButton(
                                  label: l10n.cancelClone,
                                  variant: MeridianButtonVariant.quiet,
                                  onPressed: onCancelClone,
                                ),
                              ),
                            ],
                            if (cloneFailure case final failure?) ...[
                              const SizedBox(height: MeridianSpace.space4),
                              MeridianBanner(
                                tone: MeridianBannerTone.error,
                                message: cloneFailureMessage(context, failure),
                              ),
                              if (failure == CloneFailureCode.authentication)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: MeridianButton(
                                    label: l10n.retryAuthentication,
                                    variant: MeridianButtonVariant.quiet,
                                    onPressed: busy ? null : onRetryCredentials,
                                  ),
                                ),
                              if (failure == CloneFailureCode.hostKey)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: MeridianButton(
                                    label: l10n.inspectHostKey,
                                    variant: MeridianButtonVariant.quiet,
                                    onPressed: busy ? null : onInspectHostKey,
                                  ),
                                ),
                            ],
                            if (failure case final failure?) ...[
                              const SizedBox(height: MeridianSpace.space4),
                              MeridianBanner(
                                tone: MeridianBannerTone.error,
                                message: repositoryFailureMessage(
                                  context,
                                  failure,
                                ),
                              ),
                            ],
                            const SizedBox(height: MeridianSpace.space8),
                            MeridianIsland(
                              title: l10n.recentRepositories,
                              child: recents.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(
                                        MeridianSpace.space5,
                                      ),
                                      child: Text(l10n.noRecentRepositories),
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.only(
                                        top: MeridianSpace.space3,
                                      ),
                                      child: RecentRepositoryList(
                                        recents: recents,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: MeridianSpace.space4,
                                        ),
                                        searchText: (identity) =>
                                            identity.isRemote
                                            ? '${remoteRecentName(identity)} '
                                                  '${remoteRecentSubtitle(context, remote, identity)}'
                                            : identity.displayText,
                                        onSubmit: busy
                                            ? null
                                            : (identity) => identity.isRemote
                                                  ? onOpenRemoteRecent(identity)
                                                  : onOpenRecent(identity),
                                        rowBuilder:
                                            (
                                              context,
                                              identity,
                                              query,
                                            ) => identity.isRemote
                                            ? MeridianListRow(
                                                leading: const MeridianIcon(
                                                  'server',
                                                ),
                                                title: remoteRecentName(
                                                  identity,
                                                ),
                                                subtitle: remoteRecentSubtitle(
                                                  context,
                                                  remote,
                                                  identity,
                                                ),
                                                match: query,
                                                onTap: busy
                                                    ? null
                                                    : () => onOpenRemoteRecent(
                                                        identity,
                                                      ),
                                              )
                                            : MeridianListRow(
                                                leading: const MeridianIcon(
                                                  'folder-closed',
                                                ),
                                                title: identity.basename,
                                                subtitle: identity.displayText,
                                                match: query,
                                                onTap: busy
                                                    ? null
                                                    : () => onOpenRecent(
                                                        identity,
                                                      ),
                                              ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (operations.entries.isNotEmpty)
            PositionedDirectional(
              top: MeridianSpace.space4,
              end: MeridianSpace.space4,
              child: MeridianButton(
                label: operationCenterSummary(context, operations),
                icon: operationsVisible ? 'chevron-up' : 'circle-dot',
                onPressed: onToggleOperations,
              ),
            ),
          if (operationsVisible)
            PositionedDirectional(
              top: MeridianSize.toolbar + MeridianSpace.space2,
              end: MeridianSpace.space3,
              width:
                  MediaQuery.sizeOf(context).width <
                      GitLamaLayout.logbookWidth + 2 * MeridianSpace.space3
                  ? MediaQuery.sizeOf(context).width - 2 * MeridianSpace.space3
                  : GitLamaLayout.logbookWidth,
              child: OperationCenterPanel(
                snapshot: operations,
                workspace: workspace,
                repositories: repositories,
                onClose: onToggleOperations,
                onCancel: operationActions.cancel,
                canCancel: operationActions.canCancel,
                onRetry: operationActions.retry,
                onDismiss: operationActions.dismiss,
                onDismissAll: operationActions.dismissAll,
              ),
            ),
        ],
      ),
    );
  }
}

/// How far [snapshot]'s clone has come, or null while it cannot tell.
double? cloneProgress(CloneAttemptSnapshot snapshot) {
  final progress = snapshot.progress;
  final total = progress?.total;
  if (progress == null || total == null || total == BigInt.zero) return null;
  return (progress.completed.toDouble() / total.toDouble()).clamp(0, 1);
}

/// What went wrong with a clone, in the user's words.
String cloneFailureMessage(BuildContext context, CloneFailureCode failure) {
  final l10n = context.l10n;
  return switch (failure) {
    CloneFailureCode.invalidSource => l10n.cloneInvalidSource,
    CloneFailureCode.embeddedCredential => l10n.cloneEmbeddedCredential,
    CloneFailureCode.invalidDestination => l10n.cloneInvalidDestination,
    CloneFailureCode.destinationOccupied => l10n.cloneDestinationOccupied,
    CloneFailureCode.authentication => l10n.cloneAuthenticationRequired,
    CloneFailureCode.credentialBrokerUnavailable =>
      l10n.cloneCredentialBrokerUnavailable,
    CloneFailureCode.hostKey => l10n.cloneHostKeyUntrusted,
    CloneFailureCode.hostKeyProbeFailed => l10n.hostKeyProbeFailed,
    CloneFailureCode.hostKeyChallengeExpired => l10n.hostKeyChallengeExpired,
    CloneFailureCode.hostKeyWriteFailed => l10n.hostKeyWriteFailed,
    CloneFailureCode.missingGit => l10n.gitUnavailable,
    CloneFailureCode.timedOut => l10n.cloneTimedOut,
    CloneFailureCode.canceled => l10n.cloneCanceled,
    _ => l10n.cloneFailed,
  };
}

/// Why a repository could not be opened or created.
String repositoryFailureMessage(
  BuildContext context,
  RepositoryFailureCode failure,
) =>
    repositoryFailureDetail(context, failure) ??
    context.l10n.repositoryOpenFailed;

/// The specific reason a repository could not be opened or created, or null
/// when [failure] has no more to say than that it failed.
String? repositoryFailureDetail(
  BuildContext context,
  RepositoryFailureCode failure,
) {
  final l10n = context.l10n;
  return switch (failure) {
    RepositoryFailureCode.existingRepository => l10n.repositoryAlreadyExists,
    RepositoryFailureCode.destinationNotEmpty => l10n.destinationNotEmpty,
    RepositoryFailureCode.destinationNotDirectory =>
      l10n.destinationNotDirectory,
    RepositoryFailureCode.missingGit => l10n.gitUnavailable,
    RepositoryFailureCode.unsupported => l10n.gitUnsupported,
    RepositoryFailureCode.pathNotFound => l10n.repositoryPathNotFound,
    RepositoryFailureCode.permissionDenied => l10n.repositoryPermissionDenied,
    RepositoryFailureCode.notRepository => l10n.repositoryNotRepository,
    RepositoryFailureCode.capacity => l10n.remoteRepositoryCapacity,
    _ => null,
  };
}
