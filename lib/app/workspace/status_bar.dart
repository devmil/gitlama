import '../../widgets/status_notification.dart';
import 'dart:convert';
import 'package:flutter_svg/flutter_svg.dart';
import 'brand_about.dart';
import '../../models/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../l10n/l10n.dart';
import '../../models/advanced_rebase.dart';
import '../../models/integrations.dart';
import '../../models/repository_state.dart';
import '../../models/rebase.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../services/settings_service.dart';
import '../app_theme.dart';
import 'repository_extensions.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../gitlama_layout.dart';

export '../../models/native_paths.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.active,
    this.installed,
    this.onOpenSource,
    this.statusLabel,
    this.host,
    this.trailing,
  });

  final RepositoryTabState? active;
  final InstalledRelease? installed;

  /// Opens the public source repository from About; null hides the link.
  final VoidCallback? onOpenSource;
  final String? statusLabel;

  /// Names the computer the active repository lives on, when it is remote.
  final Widget? host;

  /// Window-wide status after the repository's, such as remote changes
  /// that need review.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final status = active?.session?.snapshot.status;
    final label = switch (active?.phase) {
      RepositoryTabPhase.choosing => context.l10n.openRepository,
      RepositoryTabPhase.open => context.l10n.workspaceStatusReady,
      RepositoryTabPhase.failed => context.l10n.workspaceStatusFailed,
      _ => context.l10n.workspaceStatusLoading,
    };
    final brand = Semantics(
      button: true,
      label: context.l10n.aboutApp,
      child: Tooltip(
        message: context.l10n.brandTooltip,
        excludeFromSemantics: true,
        child: MeridianInteraction(
          onTap: () => showBrandAbout(
            context,
            installed: installed,
            onOpenSource: onOpenSource,
          ),
          builder: (context, state) => SizedBox.square(
            dimension: MeridianSize.control,
            child: Center(
              child: SvgPicture.asset(
                'resources/brand/lama-signature.svg',
                height: MeridianSize.icon,
                excludeFromSemantics: true,
                colorFilter: ColorFilter.mode(
                  state.hovered || state.focused
                      ? context.colors.inkMuted
                      : context.colors.inkFaint,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // One leading group so the notification keeps all the free width.
    return ColoredBox(
      color: context.colors.ground,
      child: MeridianStatusBar(
        leading: [
          Row(
            children: [
              brand,
              const SizedBox(width: MeridianSpace.space3),
              if (host case final host?) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: GitLamaLayout.remoteHostBadgeMaxWidth,
                  ),
                  child: host,
                ),
                const SizedBox(width: MeridianSpace.space5),
              ],
              if (status?.branchName case final branch?) ...[
                MeridianStatusBarItem(
                  icon: 'branch',
                  label: utf8.decode(branch, allowMalformed: true),
                  maxWidth: GitLamaLayout.statusBranchMaxWidth,
                ),
                const SizedBox(width: MeridianSpace.space5),
              ],
              Expanded(
                child: StatusNotificationText(fallback: statusLabel ?? label),
              ),
            ],
          ),
        ],
        trailing: [
          if (status != null)
            Text(
              '${_workingTreeLabel(context, status.workingTree)} · ${status.totalEntries}',
            ),
          ?trailing,
        ],
      ),
    );
  }
}

String _workingTreeLabel(BuildContext context, WorkingTreeState state) =>
    switch (state) {
      WorkingTreeState.clean => context.l10n.workspaceWorkingTreeClean,
      WorkingTreeState.dirty => context.l10n.workspaceWorkingTreeDirty,
      WorkingTreeState.conflicted =>
        context.l10n.workspaceWorkingTreeConflicted,
    };

String rebaseActionLabel(BuildContext context, RebaseAction action) =>
    switch (action) {
      RebaseAction.pick => context.l10n.rebaseActionPick,
      RebaseAction.reword => context.l10n.rebaseActionReword,
      RebaseAction.edit => context.l10n.rebaseActionEdit,
      RebaseAction.squash => context.l10n.rebaseActionSquash,
      RebaseAction.fixup => context.l10n.rebaseActionFixup,
      RebaseAction.drop => context.l10n.rebaseActionDrop,
    };

String rebaseResultLabel(BuildContext context, RebaseExecutionResult result) =>
    switch (result.state) {
      RebaseExecutionState.completed => context.l10n.rebaseCompleted,
      RebaseExecutionState.conflict => context.l10n.rebaseConflict(
        result.conflictingPaths.length,
      ),
      RebaseExecutionState.editStop => context.l10n.rebaseEditStop,
      RebaseExecutionState.interrupted => context.l10n.rebaseInterrupted,
      RebaseExecutionState.stale => context.l10n.rebaseStale,
      RebaseExecutionState.failed => context.l10n.rebaseFailed,
      RebaseExecutionState.reconciledWithWarning =>
        context.l10n.historyMutationReconciledWarning,
      RebaseExecutionState.outcomeUncertain =>
        context.l10n.mutationOutcomeUncertain,
    };

String restackResultLabel(
  BuildContext context,
  RestackExecutionResult result,
) => switch (result.state) {
  RestackExecutionState.completed => context.l10n.restackCompleted(
    result.completedSteps,
  ),
  RestackExecutionState.conflict => context.l10n.restackConflict(
    result.completedSteps,
    result.totalSteps,
  ),
  RestackExecutionState.partial => context.l10n.restackPartial(
    result.completedSteps,
    result.totalSteps,
  ),
  RestackExecutionState.stale => context.l10n.restackStale,
  RestackExecutionState.canceled => context.l10n.restackCanceled,
  RestackExecutionState.failed => context.l10n.restackFailed,
  RestackExecutionState.reconciledWithWarning =>
    context.l10n.historyMutationReconciledWarning,
  RestackExecutionState.outcomeUncertain =>
    context.l10n.mutationOutcomeUncertain,
};

String rebaseFailureLabel(
  BuildContext context,
  RebaseFailureCode code,
) => switch (code) {
  RebaseFailureCode.dirtyWorktree => context.l10n.historyMutationFailureDirty,
  RebaseFailureCode.detachedHead => context.l10n.historyMutationFailureDetached,
  RebaseFailureCode.activeOperation =>
    context.l10n.historyMutationFailureActive,
  RebaseFailureCode.publicationConfirmationRequired =>
    context.l10n.historyMutationFailurePublished,
  RebaseFailureCode.stale => context.l10n.rebaseStale,
  RebaseFailureCode.canceled => context.l10n.historyMutationFailureCanceled,
  RebaseFailureCode.invalidRequest ||
  RebaseFailureCode.emptyPlan ||
  RebaseFailureCode.invalidPlan ||
  RebaseFailureCode.failed ||
  RebaseFailureCode.read ||
  RebaseFailureCode.unsupported => context.l10n.rebaseFailed,
};

String displayNativePath(NativePathIdentity identity) => identity.displayText;

String? configuredFileBrowserName(SettingsService settings) {
  final configured = settings.current.integrations
      .where((value) => value.kind == IntegrationKind.fileManager)
      .firstOrNull;
  if (configured == null) return null;
  final executable = nativeIdentityLabel(configured.executable).toLowerCase();
  if (executable.contains('dolphin')) return 'Dolphin';
  if (executable.contains('nautilus')) return 'Files';
  if (executable.contains('nemo')) return 'Nemo';
  if (executable.contains('thunar')) return 'Thunar';
  if (executable.contains('pcmanfm')) return 'PCManFM';
  return configured.id;
}

String discoveredFileBrowser(String id) {
  if (id.contains('dolphin')) return 'Dolphin';
  if (id.contains('nautilus')) return 'Files';
  if (id.contains('nemo')) return 'Nemo';
  if (id.contains('thunar')) return 'Thunar';
  if (id.contains('pcmanfm')) return 'PCManFM';
  return platformFileBrowserName();
}

String platformFileBrowserName() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => 'Finder',
  TargetPlatform.windows => 'Explorer',
  TargetPlatform.linux => 'Files',
  _ => 'file browser',
};

String statusCode(RepositoryStatusEntry entry) {
  if (entry.conflicted) return 'UU';
  final index = entry.staged ? 'S' : ' ';
  final worktree = entry.unstaged ? 'M' : ' ';
  return '$index$worktree';
}
