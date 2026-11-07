import 'pull_stash_labels.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/activity.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../app_shortcut_activator.dart';
import '../../models/history_mutation.dart';
import '../../models/integrations.dart';
import '../../models/operation_center.dart';
import '../../models/operation_failure.dart';
import '../../models/ref_mutation.dart';
import '../../models/repository_state.dart';
import '../../models/stash.dart';
import '../../models/transfer.dart';
import '../../models/workspace.dart';
import '../app_theme.dart';
import 'status_bar.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../../models/git_names.dart';
import '../../models/reference_name.dart';
import '../../models/index_lock.dart';
import '../../models/rebase.dart';
import '../../models/advanced_rebase.dart';
import '../../models/commit.dart';
import '../../models/conflict.dart';
import '../../models/diff.dart';
import '../../models/discard.dart';
import '../../services/workflows/changes_service.dart';
import '../../services/workflows/conflict_resolution.dart';
import '../../services/workflows/history_rewrite_workflows.dart';
import '../../services/workflows/index_lock_workflow.dart';
import '../../services/workflows/integration_launcher.dart';
import '../../services/workflows/ref_workflows.dart';
import '../../services/workflows/repository_busy.dart';
import '../../services/workflows/transfer_workflows.dart';
import '../../services/workflows/workflow.dart';
import '../../widgets/status_notification.dart';
import 'remote_workspace.dart';

String commandGroupLabel(BuildContext context, AppCommandGroup group) =>
    switch (group) {
      AppCommandGroup.commands => context.l10n.commandGroupCommands,
      AppCommandGroup.repository => context.l10n.commandGroupRepository,
      AppCommandGroup.settings => context.l10n.commandGroupSettings,
    };

String commandLabel(BuildContext context, AppCommandId id) => switch (id) {
  AppCommandId.openRepository => context.l10n.workspaceOpenAnother,
  AppCommandId.openRemoteRepository => context.l10n.openRemoteRepository,
  AppCommandId.cloneRepository => context.l10n.cloneRepository,
  AppCommandId.initializeRepository => context.l10n.initializeRepository,
  AppCommandId.closeRepositoryTab => context.l10n.commandCloseRepositoryTab,
  AppCommandId.refreshRepository => context.l10n.workspaceRefreshLocal,
  AppCommandId.showRepositoryDetails => context.l10n.repositoryDetailsTitle,
  AppCommandId.showChanges => context.l10n.workspaceChanges,
  AppCommandId.showHistory => context.l10n.workspaceHistory,
  AppCommandId.commitCreate => context.l10n.commitAction,
  AppCommandId.commitAmend => context.l10n.commitAmend,
  AppCommandId.stageToggle => context.l10n.commandStageToggle,
  AppCommandId.stageSelection => context.l10n.stageSelected,
  AppCommandId.unstageSelection => context.l10n.unstageSelected,
  AppCommandId.discardChanges => context.l10n.discardSelected,
  AppCommandId.diffToggleLayout => context.l10n.commandDiffToggleLayout,
  AppCommandId.diffRenderConfigured => context.l10n.commandDiffRenderConfigured,
  AppCommandId.diffToggleWrap => context.l10n.commandDiffToggleWrap,
  AppCommandId.diffNextHunk => context.l10n.commandDiffNextHunk,
  AppCommandId.diffPreviousHunk => context.l10n.commandDiffPreviousHunk,
  AppCommandId.conflictNext => context.l10n.conflictNextRegion,
  AppCommandId.conflictPrevious => context.l10n.conflictPreviousRegion,
  AppCommandId.conflictTakeCurrent => context.l10n.conflictTakeCurrent,
  AppCommandId.conflictTakeIncoming => context.l10n.conflictTakeIncoming,
  AppCommandId.conflictTakeBoth => context.l10n.conflictTakeBoth,
  AppCommandId.conflictOpenExternal => context.l10n.conflictExternalTool,
  AppCommandId.rebaseContinue => context.l10n.conflictContinue,
  AppCommandId.rebaseAbort => context.l10n.conflictAbort,
  AppCommandId.rebaseSquash => context.l10n.commandRebaseSquash,
  AppCommandId.rebaseFixup => context.l10n.commandRebaseFixup,
  AppCommandId.rebaseReword => context.l10n.commandRebaseReword,
  AppCommandId.rebaseDrop => context.l10n.commandRebaseDrop,
  AppCommandId.nextPane => context.l10n.commandNextPane,
  AppCommandId.find => context.l10n.commandFind,
  AppCommandId.showOperations => context.l10n.logbookTitle,
  AppCommandId.showActivity => context.l10n.workspaceActivity,
  AppCommandId.activityCopy => context.l10n.activityCopy,
  AppCommandId.activityRetry => context.l10n.retry,
  AppCommandId.activityCancel => context.l10n.cancel,
  AppCommandId.showSnapshots => context.l10n.namedSnapshotsTitle,
  AppCommandId.patch => context.l10n.patchTitle,
  AppCommandId.createPatch => context.l10n.patchCreate,
  AppCommandId.saveCommitArchive => context.l10n.commandSaveCommitArchive,
  AppCommandId.applyPatch => context.l10n.patchApply,
  AppCommandId.showCommandPalette => context.l10n.commandPaletteTitle,
  AppCommandId.showSettings => context.l10n.settingsTitle,
  AppCommandId.showShortcutReference => context.l10n.shortcutReferenceTitle,
  AppCommandId.showLicenses => context.l10n.licensesTitle,
  AppCommandId.reportIssue => context.l10n.commandReportIssue,
  AppCommandId.inspectIndexLock => context.l10n.commandInspectIndexLock,
  AppCommandId.createBranch => context.l10n.commandCreateBranch,
  AppCommandId.renameBranch => context.l10n.commandEditBranch,
  AppCommandId.deleteBranch => context.l10n.commandDeleteBranch,
  AppCommandId.deleteRemoteBranch => context.l10n.commandDeleteRemoteBranch,
  AppCommandId.checkoutCommit => context.l10n.commandCheckoutCommit,
  AppCommandId.checkoutBranch => context.l10n.commandCheckoutBranch,
  AppCommandId.addRemote => context.l10n.commandAddRemote,
  AppCommandId.editRemote => context.l10n.commandEditRemote,
  AppCommandId.renameRemote => context.l10n.commandRenameRemote,
  AppCommandId.removeRemote => context.l10n.commandRemoveRemote,
  AppCommandId.remoteFetch => context.l10n.commandFetchRemote,
  AppCommandId.remotePush => context.l10n.commandPushRemote,
  AppCommandId.hostingCreatePullRequest =>
    context.l10n.commandHostingCreatePullRequest,
  AppCommandId.createTag => context.l10n.commandCreateTag,
  AppCommandId.deleteTag => context.l10n.commandDeleteTag,
  AppCommandId.pushTag => context.l10n.commandPushTag,
  AppCommandId.resetBranch => context.l10n.commandResetBranch,
  AppCommandId.fetch => context.l10n.commandFetch,
  AppCommandId.pull => context.l10n.commandPull,
  AppCommandId.push => context.l10n.commandPush,
  AppCommandId.openInEditor => context.l10n.commandOpenInEditor,
  AppCommandId.openInTerminal => context.l10n.commandOpenInTerminal,
  AppCommandId.openInFileManager => context.l10n.openInFileBrowser(
    platformFileBrowserName(),
  ),
  AppCommandId.createStash => context.l10n.commandCreateStash,
  AppCommandId.applyStash => context.l10n.commandApplyStash,
  AppCommandId.popStash => context.l10n.commandPopStash,
  AppCommandId.renameStash => context.l10n.commandRenameStash,
  AppCommandId.dropStash => context.l10n.commandDropStash,
  AppCommandId.autoStashCheckout => context.l10n.commandAutoStashCheckout,
  AppCommandId.integrateBranch => context.l10n.commandIntegrateBranch,
  AppCommandId.mergeBranch => context.l10n.commandMergeBranch,
  AppCommandId.rebaseBranch => context.l10n.commandRebaseBranch,
  AppCommandId.interactiveRebase => context.l10n.commandInteractiveRebase,
  AppCommandId.historyCompare => context.l10n.commandHistoryCompare,
  AppCommandId.historyBlame => context.l10n.commandHistoryBlame,
  AppCommandId.historyPathHistory => context.l10n.commandHistoryPathHistory,
  AppCommandId.inspectorBack => context.l10n.commandInspectorBack,
  AppCommandId.inspectorForward => context.l10n.commandInspectorForward,
  AppCommandId.inspectorLensDiff => context.l10n.commandInspectorLensDiff,
  AppCommandId.inspectorLensContents =>
    context.l10n.commandInspectorLensContents,
  AppCommandId.inspectorLensBlame => context.l10n.commandInspectorLensBlame,
  AppCommandId.inspectorLensHistory => context.l10n.commandInspectorLensHistory,
  AppCommandId.inspectorOpenInWindow =>
    context.l10n.commandInspectorOpenInWindow,
  AppCommandId.inspectorToggleMaximize =>
    context.l10n.commandInspectorToggleMaximize,
  AppCommandId.inspectorToggleFiles => context.l10n.commandInspectorToggleFiles,
  AppCommandId.inspectorAllFiles => context.l10n.commandInspectorAllFiles,
  AppCommandId.restackBranches => context.l10n.commandRestackBranches,
  AppCommandId.cherryPickSelected => context.l10n.commandCherryPickSelected,
  AppCommandId.revertSelected => context.l10n.commandRevertSelected,
  AppCommandId.addWorktree => context.l10n.commandAddWorktree,
  AppCommandId.trackLfsPattern => context.l10n.commandTrackLfsPattern,
  AppCommandId.addIntegration => context.l10n.commandAddIntegration,
  AppCommandId.showIntegrations => context.l10n.integrationTitle,
  AppCommandId.showPowerTools => context.l10n.powerToolsTitle,
};

Widget detailSectionHeader(BuildContext context, {String? metadata}) =>
    MeridianSectionHeader(
      color: context.colors.pane,
      title: context.l10n.workspaceDetail,
      actions: [
        if (metadata != null)
          Text(
            metadata,
            style: MeridianTextStyles.numeric(
              context.text.caption.copyWith(color: context.colors.inkMuted),
            ),
          ),
      ],
    );

/// A command label used as a dialog title. The menu ellipsis announces that
/// a dialog follows; it does not belong in the dialog itself.
String dialogTitle(String commandLabel) => commandLabel.endsWith('…')
    ? commandLabel.substring(0, commandLabel.length - 1)
    : commandLabel;

String refMutationConfirmationTitle(
  BuildContext context,
  RefMutationRequest request,
) => dialogTitle(switch (request.kind) {
  RefMutationKind.createBranch => context.l10n.commandCreateBranch,
  RefMutationKind.renameBranch => context.l10n.commandRenameBranch,
  RefMutationKind.deleteBranch => context.l10n.commandDeleteBranch,
  RefMutationKind.checkoutBranch => context.l10n.commandCheckoutBranch,
  RefMutationKind.checkoutCommit => context.l10n.commandCheckoutCommit,
  RefMutationKind.setUpstream ||
  RefMutationKind.unsetUpstream => context.l10n.commandEditBranch,
  RefMutationKind.createTag => context.l10n.commandCreateTag,
  RefMutationKind.deleteTag => context.l10n.commandDeleteTag,
  RefMutationKind.addRemote => context.l10n.commandAddRemote,
  RefMutationKind.editRemote => context.l10n.commandEditRemote,
  RefMutationKind.renameRemote => context.l10n.commandRenameRemote,
  RefMutationKind.removeRemote => context.l10n.commandRemoveRemote,
  RefMutationKind.reset => context.l10n.commandResetBranch,
});

String refMutationConfirmationAction(
  BuildContext context,
  RefMutationRequest request,
) => switch (request.kind) {
  RefMutationKind.deleteBranch ||
  RefMutationKind.deleteTag => context.l10n.delete,
  // The command without its ellipsis: "Create branch", "Remove remote".
  _ => refMutationConfirmationTitle(context, request),
};

String refMutationConfirmationMessage(
  BuildContext context,
  RefMutationRequest request,
) => switch (request.kind) {
  RefMutationKind.createBranch =>
    request.checkout
        ? context.l10n.refConfirmCreateAndCheckoutBranch(request.name ?? '')
        : context.l10n.refConfirmCreateBranch(request.name ?? ''),
  RefMutationKind.renameBranch => context.l10n.refConfirmRenameBranch(
    request.name ?? '',
    request.secondName ?? '',
  ),
  RefMutationKind.deleteBranch => switch (request.deleteUpstream) {
    final upstream? => context.l10n.refConfirmDeleteBranchAndUpstream(
      request.name ?? '',
      upstream.label,
    ),
    null => context.l10n.refConfirmDeleteBranch(request.name ?? ''),
  },
  RefMutationKind.checkoutBranch => context.l10n.refConfirmCheckoutBranch(
    request.name ?? '',
  ),
  RefMutationKind.checkoutCommit => context.l10n.refConfirmCheckoutCommit(
    request.target ?? '',
  ),
  RefMutationKind.setUpstream => context.l10n.refConfirmSetUpstream(
    request.name ?? '',
    request.secondName ?? '',
  ),
  RefMutationKind.unsetUpstream => context.l10n.refConfirmUnsetUpstream(
    request.name ?? '',
  ),
  RefMutationKind.createTag => context.l10n.refConfirmCreateTag(
    request.name ?? '',
  ),
  RefMutationKind.deleteTag =>
    request.remoteNames.isEmpty
        ? context.l10n.refConfirmDeleteTagLocal(request.name ?? '')
        : context.l10n.refConfirmDeleteTagRemotes(
            request.name ?? '',
            request.remoteNames.join(', '),
          ),
  RefMutationKind.addRemote => context.l10n.refConfirmAddRemote(
    request.name ?? '',
  ),
  RefMutationKind.editRemote => context.l10n.refConfirmEditRemote(
    request.name ?? '',
  ),
  RefMutationKind.renameRemote => context.l10n.refConfirmRenameRemote(
    request.name ?? '',
    request.secondName ?? '',
  ),
  RefMutationKind.removeRemote => context.l10n.refConfirmRemoveRemote(
    request.name ?? '',
  ),
  RefMutationKind.reset => switch (request.resetMode) {
    RefResetMode.hard => context.l10n.refConfirmResetHard,
    RefResetMode.mixed => context.l10n.refConfirmResetMixed,
    _ => context.l10n.refConfirmResetSoft,
  },
};

String refMutationWarningLabel(
  BuildContext context,
  RefMutationWarning warning,
) => switch (warning) {
  RefMutationWarning.dirtyCheckout => context.l10n.refMutationWarningDirty,
  RefMutationWarning.detachedHead => context.l10n.refMutationWarningDetached,
  RefMutationWarning.publishedBranch =>
    context.l10n.refMutationWarningPublished,
  RefMutationWarning.checkedOutElsewhere =>
    context.l10n.refMutationWarningOtherWorktree,
  RefMutationWarning.destructiveReset =>
    context.l10n.refMutationWarningDestructiveReset,
};

String stashKindLabel(BuildContext context, StashKind kind) => switch (kind) {
  StashKind.push => context.l10n.commandCreateStash,
  StashKind.apply => context.l10n.commandApplyStash,
  StashKind.pop => context.l10n.commandPopStash,
  StashKind.drop => context.l10n.commandDropStash,
  StashKind.rename => context.l10n.commandRenameStash,
  StashKind.autoStashCheckout => context.l10n.commandAutoStashCheckout,
  StashKind.stashCheckoutCommit ||
  StashKind.autoStashCheckoutCommit => context.l10n.commandCheckoutCommit,
};

/// What a running stash operation does, shown over its repository.
String stashBusyLabel(BuildContext context, StashKind kind) => switch (kind) {
  StashKind.push => context.l10n.stashBusyPush,
  StashKind.apply => context.l10n.stashBusyApply,
  StashKind.pop => context.l10n.stashBusyPop,
  StashKind.drop => context.l10n.stashBusyDrop,
  StashKind.rename => context.l10n.stashBusyRename,
  StashKind.autoStashCheckout ||
  StashKind.stashCheckoutCommit ||
  StashKind.autoStashCheckoutCommit => context.l10n.stashBusyAutoStashCheckout,
};

/// What a running merge, cherry-pick or revert does, shown over its
/// repository.
String historyMutationBusyLabel(
  BuildContext context,
  HistoryMutationPreview preview,
) {
  final branch = utf8.decode(preview.currentBranch, allowMalformed: true);
  return switch (preview.kind) {
    HistoryMutationKind.merge => context.l10n.historyMutationBusyMerge(
      switch (preview.sourceName) {
        final name? => utf8.decode(name, allowMalformed: true),
        null => (preview.targets.firstOrNull ?? '').characters.take(10).string,
      },
      branch,
    ),
    HistoryMutationKind.cherryPick =>
      context.l10n.historyMutationBusyCherryPick(
        preview.targets.length,
        branch,
      ),
    HistoryMutationKind.revert => context.l10n.historyMutationBusyRevert(
      preview.targets.length,
      branch,
    ),
  };
}

String historyMutationKindLabel(
  BuildContext context,
  HistoryMutationKind kind,
) => switch (kind) {
  HistoryMutationKind.merge => context.l10n.commandMergeBranch,
  HistoryMutationKind.cherryPick => context.l10n.commandCherryPickSelected,
  HistoryMutationKind.revert => context.l10n.commandRevertSelected,
};

String historyMergeModeLabel(BuildContext context, HistoryMergeMode mode) =>
    switch (mode) {
      HistoryMergeMode.fastForwardIfPossible =>
        context.l10n.historyMutationFastForwardPossible,
      HistoryMergeMode.fastForwardOnly =>
        context.l10n.historyMutationFastForwardOnly,
      HistoryMergeMode.noFastForward =>
        context.l10n.historyMutationNoFastForward,
    };

String historyMutationResultLabel(
  BuildContext context,
  HistoryMutationExecutionResult result,
) => switch (result.state) {
  HistoryMutationExecutionState.completed =>
    context.l10n.historyMutationCompleted,
  HistoryMutationExecutionState.alreadyContained =>
    context.l10n.historyMutationAlreadyContained,
  HistoryMutationExecutionState.conflict =>
    context.l10n.historyMutationConflict(result.conflictingPaths.length),
  HistoryMutationExecutionState.interrupted =>
    context.l10n.historyMutationInterrupted,
  HistoryMutationExecutionState.stale => context.l10n.historyMutationStale,
  HistoryMutationExecutionState.reconciledWithWarning =>
    context.l10n.historyMutationReconciledWarning,
  HistoryMutationExecutionState.failed => historyMutationFailureLabel(
    context,
    result.failure ?? HistoryMutationFailureCode.failed,
  ),
  HistoryMutationExecutionState.outcomeUncertain =>
    context.l10n.mutationOutcomeUncertain,
};

String historyMutationFailureLabel(
  BuildContext context,
  HistoryMutationFailureCode failure,
) => switch (failure) {
  HistoryMutationFailureCode.invalidRequest =>
    context.l10n.historyMutationFailureInvalid,
  HistoryMutationFailureCode.dirtyWorktree =>
    context.l10n.historyMutationFailureDirty,
  HistoryMutationFailureCode.detachedHead =>
    context.l10n.historyMutationFailureDetached,
  HistoryMutationFailureCode.activeOperation =>
    context.l10n.historyMutationFailureActive,
  HistoryMutationFailureCode.publicationConfirmationRequired =>
    context.l10n.historyMutationFailurePublished,
  HistoryMutationFailureCode.stale => context.l10n.historyMutationStale,
  HistoryMutationFailureCode.canceled =>
    context.l10n.historyMutationFailureCanceled,
  HistoryMutationFailureCode.read ||
  HistoryMutationFailureCode.failed => context.l10n.historyMutationFailed,
  HistoryMutationFailureCode.mergeCommit =>
    context.l10n.historyRevertMergeUnsupported,
};

String stashResultLabel(BuildContext context, StashExecutionResult result) =>
    switch (result.state) {
      StashExecutionState.completed => context.l10n.stashCompleted,
      StashExecutionState.reconciledWithWarning =>
        context.l10n.stashReconciledWarning,
      StashExecutionState.stale => context.l10n.stashFailureStale,
      StashExecutionState.conflict =>
        result.stashRetained
            ? context.l10n.stashConflictRetained
            : context.l10n.stashConflict,
      StashExecutionState.failed => stashFailureLabel(
        context,
        result.failure ?? StashFailureCode.failed,
      ),
      StashExecutionState.outcomeUncertain =>
        context.l10n.mutationOutcomeUncertain,
    };

String stashFailureLabel(BuildContext context, StashFailureCode failure) =>
    switch (failure) {
      StashFailureCode.invalidRequest => context.l10n.stashFailureInvalid,
      StashFailureCode.nothingToStash => context.l10n.stashFailureNothing,
      StashFailureCode.missingStash => context.l10n.stashFailureMissing,
      StashFailureCode.stale => context.l10n.stashFailureStale,
      StashFailureCode.conflict => context.l10n.stashConflictRetained,
      StashFailureCode.canceled => context.l10n.stashFailureCanceled,
      StashFailureCode.timedOut => context.l10n.stashFailureTimeout,
      StashFailureCode.missingGit => context.l10n.stashFailureMissingGit,
      StashFailureCode.failed ||
      StashFailureCode.read ||
      StashFailureCode.write => context.l10n.stashFailed,
    };

String transferResultLabel(
  BuildContext context,
  TransferExecutionResult result,
) {
  if (result.stash case final saved?) {
    final message = pullStashResultLabel(
      context.l10n,
      saved,
      failure: transferFailureLabel(
        context,
        result.failure ?? TransferFailureCode.read,
      ),
    );
    return result.state == TransferExecutionState.reconciledWithWarning
        ? '$message ${context.l10n.transferReconciledWarning}'
        : message;
  }
  return switch (result.state) {
    TransferExecutionState.completed => context.l10n.transferCompleted(
      result.ahead.toString(),
      result.behind.toString(),
    ),
    TransferExecutionState.reconciledWithWarning =>
      context.l10n.transferReconciledWarning,
    TransferExecutionState.stale => context.l10n.transferFailureStale,
    TransferExecutionState.failed => transferFailureLabel(
      context,
      result.failure ?? TransferFailureCode.read,
    ),
    TransferExecutionState.outcomeUncertain =>
      context.l10n.mutationOutcomeUncertain,
  };
}

String transferFailureLabel(
  BuildContext context,
  TransferFailureCode failure,
) => switch (failure) {
  TransferFailureCode.invalidRequest => context.l10n.transferFailureInvalid,
  TransferFailureCode.detachedHead => context.l10n.transferFailureDetached,
  TransferFailureCode.missingUpstream => context.l10n.transferFailureUpstream,
  TransferFailureCode.dirtyWorktree => context.l10n.transferFailureDirty,
  TransferFailureCode.conflictedWorktree =>
    context.l10n.transferFailureConflicted,
  TransferFailureCode.stale => context.l10n.transferFailureStale,
  TransferFailureCode.authentication =>
    context.l10n.transferFailureAuthentication,
  TransferFailureCode.credentialBrokerUnavailable =>
    context.l10n.transferFailureCredentialBroker,
  TransferFailureCode.hostKey => context.l10n.transferFailureHostKey,
  TransferFailureCode.rejected => context.l10n.transferFailureRejected,
  TransferFailureCode.timedOut => context.l10n.transferFailureTimeout,
  TransferFailureCode.canceled => context.l10n.transferFailureCanceled,
  TransferFailureCode.missingGit => context.l10n.transferFailureMissingGit,
  TransferFailureCode.read => context.l10n.transferFailed,
  TransferFailureCode.missingObject =>
    context.l10n.transferFailureMissingObject,
  TransferFailureCode.locked => context.l10n.transferFailureLocked,
};

/// What a support report may say about a transfer that ran in [session].
OperationFailureDetails transferFailureDetails(
  TransferExecutionResult result,
  RepositorySessionIdentity? session,
) => OperationFailureDetails(
  operation: UserOperationKind.transfer,
  transfer: result.failure,
  transferDiagnosis: result.diagnosis?.kind,
  activity: switch ((session, result.activityId)) {
    (final session?, final id?) => (session: session, id: id),
    _ => null,
  },
);

/// Why a command is unavailable on a remote tab, as menus show it after the
/// title; null for any other reason, which menus keep to the disabled state.
String? remoteMenuReason(
  BuildContext context,
  AppCommandDisabledReason? reason,
) => switch (reason) {
  AppCommandDisabledReason.remoteUnsupported ||
  AppCommandDisabledReason.remoteDisconnected ||
  AppCommandDisabledReason.remoteWritesUnavailable ||
  AppCommandDisabledReason.remoteWritesOff ||
  AppCommandDisabledReason.remoteWritesReconnect ||
  AppCommandDisabledReason.remoteWritesLedger => workspaceDisabledReason(
    context,
    reason!,
  ),
  _ => null,
};

String workspaceDisabledReason(
  BuildContext context,
  AppCommandDisabledReason reason,
) => switch (reason) {
  AppCommandDisabledReason.repositoryRequired =>
    context.l10n.commandRepositoryRequired,
  AppCommandDisabledReason.repositoryBusy => context.l10n.commandRepositoryBusy,
  AppCommandDisabledReason.contextRequired =>
    context.l10n.commandContextUnavailable,
  AppCommandDisabledReason.featureUnavailable =>
    context.l10n.commandFeatureUnavailable,
  AppCommandDisabledReason.remoteUnsupported =>
    context.l10n.remoteCommandUnsupported,
  AppCommandDisabledReason.remoteDisconnected =>
    context.l10n.remoteCommandDisconnected,
  AppCommandDisabledReason.remoteWritesUnavailable =>
    context.l10n.remoteCommandWritesUnavailable,
  AppCommandDisabledReason.remoteWritesOff =>
    context.l10n.remoteCommandWritesOff,
  AppCommandDisabledReason.remoteWritesReconnect =>
    context.l10n.remoteCommandWritesReconnect,
  AppCommandDisabledReason.remoteWritesLedger =>
    context.l10n.remoteCommandWritesLedger,
};

String operationCenterSummary(
  BuildContext context,
  OperationCenterSnapshot snapshot,
) {
  final statuses = <String>[];
  if (snapshot.runningCount > 0) {
    statuses.add(context.l10n.operationsRunning(snapshot.runningCount));
  }
  if (snapshot.failedCount > 0) {
    statuses.add(context.l10n.operationsFailed(snapshot.failedCount));
  }
  if (snapshot.attentionCount > 0) {
    statuses.add(context.l10n.operationsAttention(snapshot.attentionCount));
  }
  if (statuses.isNotEmpty) {
    return statuses.join(' · ');
  }
  return '';
}

/// The banner and details label of a Git operation paused in a repository.
String repositoryOperationLabel(
  BuildContext context,
  RepositoryOperationKind operation,
) => switch (operation) {
  RepositoryOperationKind.merge => context.l10n.workspaceOperationMerge,
  RepositoryOperationKind.rebase => context.l10n.workspaceOperationRebase,
  RepositoryOperationKind.cherryPick =>
    context.l10n.workspaceOperationCherryPick,
  RepositoryOperationKind.revert => context.l10n.workspaceOperationRevert,
  RepositoryOperationKind.bisect => context.l10n.workspaceOperationBisect,
};

String operationActionLabel(
  BuildContext context,
  OperationCenterAction action,
) => switch (action) {
  OperationCenterAction.refresh => context.l10n.operationRefresh,
  OperationCenterAction.initialize => context.l10n.operationInitialize,
  OperationCenterAction.clone => context.l10n.operationClone,
  OperationCenterAction.fetch => context.l10n.operationFetch,
  OperationCenterAction.pull => context.l10n.operationPull,
  OperationCenterAction.push => context.l10n.operationPush,
  OperationCenterAction.other => context.l10n.operationOther,
};

/// The phase and completion of a running operation, or null while Git has
/// reported neither. Git names its phases in English whatever the locale.
String? operationProgressLabel(
  BuildContext context,
  ActivityProgress? progress,
) {
  final total = progress?.total;
  if (progress == null || total == null || total == BigInt.zero) return null;
  final percent = (100 * progress.completed.toDouble() / total.toDouble())
      .round();
  final phase = switch (progress.phase) {
    'Counting objects' => context.l10n.operationPhaseCounting,
    'Compressing objects' => context.l10n.operationPhaseCompressing,
    'Receiving objects' => context.l10n.operationPhaseReceiving,
    'Resolving deltas' => context.l10n.operationPhaseResolving,
    'Updating files' => context.l10n.operationPhaseUpdatingFiles,
    'Filtering content' => context.l10n.operationPhaseFiltering,
    'Rebasing' => context.l10n.operationPhaseRebasing,
    _ => null,
  };
  return phase == null
      ? context.l10n.operationPercent(percent)
      : context.l10n.operationPhaseProgress(phase, percent);
}

String activityStateLabel(BuildContext context, ActivityStatus status) =>
    switch (status) {
      ActivityStatus.running => context.l10n.operationStateRunning,
      ActivityStatus.succeeded => context.l10n.operationStateSucceeded,
      ActivityStatus.failed ||
      ActivityStatus.timedOut ||
      ActivityStatus.launchError => context.l10n.operationStateFailed,
      ActivityStatus.canceled => context.l10n.operationStateCanceled,
    };

String operationRepositoryLabel(
  BuildContext context,
  WorkspaceState workspace,
  OperationCenterEntry entry,
) {
  final entrySession = entry.session;
  if (entrySession == null) return context.l10n.operationRepositoryApplication;
  for (final tab in workspace.tabs) {
    final identity = tab.session?.identity;
    if (identity?.nativeId == entrySession.nativeId &&
        identity?.generation == entrySession.generation) {
      return tab.label;
    }
  }
  return '#${entrySession.nativeId}';
}

String activityOutput(ActivityRecord record) {
  final output = <String>[];
  if (record.stdout.isNotEmpty) {
    output.add(utf8.decode(record.stdout, allowMalformed: true));
  }
  if (record.stderr.isNotEmpty) {
    output.add(utf8.decode(record.stderr, allowMalformed: true));
  }
  return output.join('\n');
}

String activityClipboardText(ActivityRecord record) {
  final command = [record.executable, ...record.arguments].join(' ');
  final output = activityOutput(record);
  return output.isEmpty ? command : '$command\n\n$output';
}

/// Returning from a shortcut callback still consumes its key. Decline the
/// binding before dispatch so the platform text input can insert the character.
class TextAwareShortcutActivator implements ShortcutActivator {
  const TextAwareShortcutActivator(this.delegate, this.isEditingText);
  final SingleActivator delegate;
  final bool Function() isEditingText;

  @override
  Iterable<LogicalKeyboardKey> get triggers => delegate.triggers;

  @override
  String debugDescribeKeys() => delegate.debugDescribeKeys();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      !isEditingText() && delegate.accepts(event, state);
}

bool textInputHasFocus() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  return focusContext?.widget is EditableText ||
      focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
}

bool _destructive(AppCommandId command) =>
    AppCommandRegistry.byId(command).destructive;

/// The commands of a reference, stash or remote as menu items with their
/// icons and shortcuts. Commands that delete come last, after a separator.
List<NativeMenuItem<AppCommandId>> commandMenuItems(
  BuildContext context,
  Iterable<AppCommandId> commands,
  Map<AppCommandId, AppShortcut?> shortcuts, {
  bool Function(AppCommandId)? enabled,
  AppCommandDisabledReason? Function(AppCommandId)? reason,
}) {
  NativeMenuItem<AppCommandId> item(AppCommandId command) => NativeMenuItem(
    value: command,
    title: commandLabel(context, command),
    icon: AppCommandRegistry.byId(command).icon,
    activator: shortcuts[command]?.activator,
    danger: _destructive(command),
    enabled:
        (enabled?.call(command) ?? true) && (reason?.call(command) == null),
    disabledReason: remoteMenuReason(context, reason?.call(command)),
  );
  final safe = commands.where((command) => !_destructive(command));
  final destructive = commands.where(_destructive);
  return [
    ...safe.map(item),
    if (safe.isNotEmpty && destructive.isNotEmpty)
      const NativeMenuItem.separator(),
    ...destructive.map(item),
  ];
}

String integrationKindLabel(BuildContext context, IntegrationKind kind) =>
    switch (kind) {
      IntegrationKind.editor => context.l10n.integrationEditor,
      IntegrationKind.terminal => context.l10n.integrationTerminal,
      IntegrationKind.fileManager => context.l10n.integrationFileManager,
      IntegrationKind.browser => context.l10n.integrationBrowser,
      IntegrationKind.diffTool => context.l10n.integrationDiffTool,
      IntegrationKind.mergeTool => context.l10n.integrationMergeTool,
      IntegrationKind.custom => context.l10n.integrationCustom,
    };

/// A workflow outcome in the user's words, and whether it reports a failure.
typedef WorkflowMessage = ({String text, bool error});

/// Shows [message] in the status line; nothing for null.
void showWorkflowMessage(
  BuildContext context,
  WorkflowMessage? message, {
  OperationFailureDetails details = const OperationFailureDetails(),
}) {
  if (message == null) return;
  StatusNotificationScope.show(
    context,
    message.text,
    error: message.error,
    details: details,
  );
}

OperationFailureDetails workflowFailureDetails(
  WorkflowFailure failure, {
  UserOperationKind operation = UserOperationKind.operation,
}) => OperationFailureDetails(
  operation: operation,
  repository: failure is SessionFailure ? failure.code : null,
  unexpected: failure is UnexpectedFailure,
  remote: failure is RemoteConnectionFailure ? failure.code : null,
  outcomeUnknown: failure is OutcomeUnknownFailure,
);

/// The message for a failure every workflow reports alike. [session] names
/// what failed when the repository session refused the request.
WorkflowMessage workflowFailureMessage(
  BuildContext context,
  WorkflowFailure failure, {
  required String session,
  bool sessionError = true,
}) => switch (failure) {
  UnexpectedFailure() => (
    text: context.l10n.operationUnexpectedFailure,
    error: true,
  ),
  OutcomeUnknownFailure() => (
    text: context.l10n.remoteOutcomeUnknownChange,
    error: true,
  ),
  RemoteConnectionFailure(:final code) => (
    text: remoteFailureMessage(context, code),
    error: true,
  ),
  SessionFailure(:final code) => (
    text: context.l10n.operationFailureWithReason(
      session,
      operationFailureReason(context, code),
    ),
    error: sessionError,
  ),
};

String operationFailureReason(
  BuildContext context,
  RepositoryFailureCode code,
) => switch (code) {
  RepositoryFailureCode.canceled => context.l10n.operationFailureCanceled,
  RepositoryFailureCode.tooLarge => context.l10n.operationFailureLimit,
  RepositoryFailureCode.timedOut => context.l10n.operationFailureTimeout,
  RepositoryFailureCode.permissionDenied =>
    context.l10n.repositoryPermissionDenied,
  RepositoryFailureCode.missingGit => context.l10n.gitUnavailable,
  RepositoryFailureCode.missingObject =>
    context.l10n.operationFailureMissingObject,
  RepositoryFailureCode.invalidOptions || RepositoryFailureCode.invalidOutput =>
    context.l10n.operationFailureInvalidRequest,
  RepositoryFailureCode.capacity => context.l10n.operationFailureBusy,
  _ => context.l10n.operationFailureRead,
};

String stagingFailureMessage(BuildContext context, StagingFailureCode code) =>
    switch (code) {
      StagingFailureCode.indexLocked => context.l10n.stagingFailureIndexLocked,
      StagingFailureCode.indexChanged ||
      StagingFailureCode.contentChanged => context.l10n.stagingStale,
      StagingFailureCode.statusRead => context.l10n.stagingFailureStatusRead,
      StagingFailureCode.indexRead ||
      StagingFailureCode.indexUnsafe => context.l10n.stagingFailureIndexRead,
      StagingFailureCode.contentRead => context.l10n.stagingFailureContentRead,
      StagingFailureCode.indexPrepare ||
      StagingFailureCode.indexInstall => context.l10n.stagingFailureIndexWrite,
      StagingFailureCode.gitLaunch => context.l10n.gitUnavailable,
      StagingFailureCode.gitTimeout => context.l10n.operationFailureTimeout,
      StagingFailureCode.gitFailed => context.l10n.stagingFailureGit,
      StagingFailureCode.invalidRequest ||
      StagingFailureCode.patchUnavailable =>
        context.l10n.operationFailureInvalidRequest,
      StagingFailureCode.repositoryUnavailable => context.l10n.stagingFailed,
    };

String refMutationResultLabel(
  BuildContext context,
  RefMutationExecutionState state,
) => switch (state) {
  RefMutationExecutionState.completed => context.l10n.refMutationCompleted,
  RefMutationExecutionState.stale => context.l10n.refMutationStale,
  RefMutationExecutionState.failed => context.l10n.refMutationFailed,
  RefMutationExecutionState.reconciledWithWarning =>
    context.l10n.refMutationWarningResult,
  RefMutationExecutionState.outcomeUncertain =>
    context.l10n.mutationOutcomeUncertain,
};

WorkflowMessage refOutcomeMessage(BuildContext context, RefOutcome outcome) {
  bool done(RefMutationExecutionState state) =>
      state == RefMutationExecutionState.completed ||
      state == RefMutationExecutionState.reconciledWithWarning;
  return switch (outcome) {
    RefMutationFinished(:final state, :final remoteTagDeleted) => (
      text: remoteTagDeleted && !done(state)
          ? context.l10n.deleteTagLocalFailedAfterRemote
          : refMutationResultLabel(context, state),
      error:
          state == RefMutationExecutionState.failed ||
          state == RefMutationExecutionState.stale,
    ),
    RemoteTagDeleteFailed(:final remote) => (
      text: context.l10n.deleteTagRemoteFailed(remote),
      error: false,
    ),
    UpstreamDeleteFailed(:final label) => (
      text: context.l10n.deleteBranchUpstreamFailed(label),
      error: false,
    ),
    RefWorkflowFailed(:final failure, :final remoteTagDeleted) =>
      workflowFailureMessage(
        context,
        failure,
        session: remoteTagDeleted
            ? context.l10n.deleteTagLocalFailedAfterRemote
            : context.l10n.refMutationFailed,
        sessionError: false,
      ),
  };
}

WorkflowMessage transferOutcomeMessage(
  BuildContext context,
  TransferOutcome outcome,
) => switch (outcome) {
  TransferFinished(:final request, :final result) => (
    text: request.refetch && result.state == TransferExecutionState.completed
        ? context.l10n.transferRefetchCompleted
        : transferResultLabel(context, result),
    error:
        result.state == TransferExecutionState.failed ||
        result.state == TransferExecutionState.stale ||
        (result.stash != null && !result.stash!.reapplyCompleted),
  ),
  RemoteTransferNeedsHost(:final failure) => (
    text: failure == TransferFailureCode.hostKey
        ? context.l10n.remoteTransferHostKey
        : context.l10n.remoteTransferAuthentication,
    error: true,
  ),
  TransferRefused(:final code) => (
    text: transferFailureLabel(context, code),
    error: true,
  ),
  TransferHostKeyProbeFailed() => (
    text: context.l10n.hostKeyProbeFailed,
    error: true,
  ),
  TransferWorkflowFailed(:final failure) => workflowFailureMessage(
    context,
    failure,
    session: context.l10n.transferFailed,
  ),
};

WorkflowMessage historyRewriteOutcomeMessage(
  BuildContext context,
  HistoryRewriteOutcome outcome,
) => switch (outcome) {
  CommitCheckoutFinished(:final state) => refOutcomeMessage(
    context,
    RefMutationFinished(state),
  ),
  StashFinished(:final result) => (
    text: stashResultLabel(context, result),
    error:
        result.state == StashExecutionState.failed ||
        result.state == StashExecutionState.stale,
  ),
  StashRefused(:final code) => (
    text: stashFailureLabel(context, code),
    error: true,
  ),
  HistoryMutationFinished(:final preview, :final result) => (
    text:
        preview.noCommit &&
            result.state == HistoryMutationExecutionState.completed
        ? context.l10n.historyRevertApplied
        : historyMutationResultLabel(context, result),
    error:
        result.state == HistoryMutationExecutionState.failed ||
        result.state == HistoryMutationExecutionState.stale,
  ),
  HistoryMutationRefused(:final code) => (
    text: historyMutationFailureLabel(context, code),
    error: true,
  ),
  RebaseFinished(:final result) => (
    text: rebaseResultLabel(context, result),
    error:
        result.state == RebaseExecutionState.failed ||
        result.state == RebaseExecutionState.stale,
  ),
  RebaseRefused(:final code) => (
    text: rebaseFailureLabel(context, code),
    error: true,
  ),
  RestackNothingToDo() => (text: context.l10n.restackNothingToDo, error: false),
  RestackFinished(:final result) => (
    text: restackResultLabel(context, result),
    error:
        result.state == RestackExecutionState.failed ||
        result.state == RestackExecutionState.stale,
  ),
  HistoryRewriteFailed(:final kind, :final failure) => () {
    final session = switch (kind) {
      HistoryRewriteKind.stash => context.l10n.stashFailed,
      HistoryRewriteKind.historyMutation => context.l10n.historyMutationFailed,
      HistoryRewriteKind.rebase => context.l10n.rebaseFailed,
      HistoryRewriteKind.restack => context.l10n.restackFailed,
    };
    return failure == null
        ? (text: session, error: true)
        : workflowFailureMessage(context, failure, session: session);
  }(),
};

WorkflowMessage integrationOutcomeMessage(
  BuildContext context,
  IntegrationOutcome outcome,
) => switch (outcome) {
  IntegrationUnavailable() => (
    text: context.l10n.integrationUnavailable,
    error: false,
  ),
  IntegrationLaunchFailed() => (
    text: context.l10n.integrationLaunchFailed,
    error: true,
  ),
  IntegrationRefused(:final reason) => (
    text: workspaceDisabledReason(context, reason),
    error: false,
  ),
};

WorkflowMessage indexLockOutcomeMessage(
  BuildContext context,
  IndexLockOutcome outcome,
) => switch (outcome) {
  IndexLockNotFound() => (text: context.l10n.indexLockNotFound, error: false),
  IndexLockRemoved() => (text: context.l10n.indexLockRemoved, error: false),
  IndexLockRefused(:final code) => (
    text: switch (code) {
      IndexLockFailureCode.changed => context.l10n.indexLockChanged,
      IndexLockFailureCode.activeOperation =>
        context.l10n.indexLockActiveOperation,
      _ => context.l10n.indexLockUnavailable,
    },
    error: false,
  ),
  IndexLockFailed(:final failure) => workflowFailureMessage(
    context,
    failure,
    session: context.l10n.indexLockUnavailable,
    sessionError: false,
  ),
};

/// What a busy repository tab is doing, for its busy overlay.
String busyActivityLabel(BuildContext context, BusyActivity activity) =>
    switch (activity) {
      CommitCheckoutBusy() => context.l10n.commitCheckoutBusy,
      StashBusy(:final kind) => stashBusyLabel(context, kind),
      HistoryMutationBusy(:final preview) => historyMutationBusyLabel(
        context,
        preview,
      ),
      RebaseBusy(:final currentBranch, :final onto) => context.l10n.rebaseBusy(
        nameText(currentBranch),
        nameText(onto),
      ),
      RestackBusy(:final rootBranch) => context.l10n.restackBusy(
        nameText(rootBranch),
      ),
      ConflictPredictionBusy() => context.l10n.conflictPredictionBusy,
      ChangesBusy() => context.l10n.loading,
    };

WorkflowMessage conflictOutcomeMessage(
  BuildContext context,
  ConflictOutcome outcome,
) => switch (outcome) {
  ConflictRegionsRemaining(:final count) => (
    text: context.l10n.conflictRegionsRemaining(count),
    error: false,
  ),
  ConflictSaveFailed() => (text: context.l10n.conflictSaveFailed, error: false),
  ConflictContinued(:final state) => (
    text: switch (state) {
      ConflictContinuationState.completed => context.l10n.conflictCompleted,
      ConflictContinuationState.aborted => context.l10n.conflictAborted,
      ConflictContinuationState.conflict ||
      ConflictContinuationState.interrupted =>
        context.l10n.conflictStoppedAgain,
      ConflictContinuationState.failed => context.l10n.conflictContinueFailed,
      ConflictContinuationState.outcomeUncertain =>
        context.l10n.mutationOutcomeUncertain,
    },
    error: false,
  ),
  ConflictContinueFailed() => (
    text: context.l10n.conflictContinueFailed,
    error: false,
  ),
  ConflictWorkflowFailed(:final failure) => workflowFailureMessage(
    context,
    failure,
    session: context.l10n.conflictSaveFailed,
    sessionError: false,
  ),
};

WorkflowMessage changesOutcomeMessage(
  BuildContext context,
  ChangesOutcome outcome,
) => switch (outcome) {
  StagingFinished(:final state, :final diagnostic) => (
    text: switch (state) {
      StagingExecutionState.completed => context.l10n.stagingCompleted,
      StagingExecutionState.stale => context.l10n.stagingStale,
      StagingExecutionState.failed =>
        diagnostic == null
            ? context.l10n.stagingFailed
            : stagingFailureMessage(context, diagnostic.code),
      StagingExecutionState.reconciledWithWarning =>
        context.l10n.stagingWarning,
      StagingExecutionState.outcomeUncertain =>
        context.l10n.mutationOutcomeUncertain,
    },
    error:
        state == StagingExecutionState.stale ||
        state == StagingExecutionState.failed ||
        state == StagingExecutionState.outcomeUncertain,
  ),
  StagingFailed(failure: OutcomeUnknownFailure()) => (
    text: context.l10n.remoteOutcomeUnknownStage,
    error: true,
  ),
  StagingFailed(:final failure) => workflowFailureMessage(
    context,
    failure,
    session: context.l10n.stagingFailed,
  ),
  DiscardFinished(:final state) => (
    text: switch (state) {
      DiscardExecutionState.completed => context.l10n.discardCompleted,
      DiscardExecutionState.stale => context.l10n.discardStale,
      DiscardExecutionState.failed => context.l10n.discardFailed,
      DiscardExecutionState.reconciledWithWarning =>
        context.l10n.discardWarning,
      DiscardExecutionState.outcomeUncertain =>
        context.l10n.mutationOutcomeUncertain,
    },
    error: state == DiscardExecutionState.outcomeUncertain,
  ),
  DiscardPartiallyFinished(:final completedFiles, :final totalFiles) => (
    text: context.l10n.discardPartial(completedFiles, totalFiles),
    error: true,
  ),
  DiscardFailed(:final failure) => workflowFailureMessage(
    context,
    failure,
    session: context.l10n.discardFailed,
  ),
  ChangesRefused(:final reason) => (
    text: workspaceDisabledReason(context, reason),
    error: false,
  ),
};

/// The message for a commit that ran.
WorkflowMessage commitResultMessage(
  BuildContext context,
  CommitExecutionResult result,
) {
  final shortCommit = switch (result.commit) {
    final value? => value.substring(0, value.length < 7 ? value.length : 7),
    null => null,
  };
  return (
    text: switch (result.state) {
      CommitExecutionState.stale => context.l10n.commitStale,
      CommitExecutionState.failed => context.l10n.commitFailed,
      CommitExecutionState.reconciledWithWarning => context.l10n.commitWarning,
      CommitExecutionState.completed =>
        shortCommit == null
            ? context.l10n.commitCompleted
            : context.l10n.commitCommittedObject(shortCommit),
      CommitExecutionState.outcomeUncertain =>
        context.l10n.mutationOutcomeUncertain,
    },
    error: result.state == CommitExecutionState.outcomeUncertain,
  );
}

/// What [snapshot]'s worktree has checked out: the branch's short name, or
/// "Detached at `hash`" with [detached] set. Discovery names the branch before the first
/// worktree scan reports a status, which a large repository takes seconds to
/// produce.
({String label, bool detached})? checkedOut(
  BuildContext context,
  RepositorySnapshot? snapshot,
) {
  final status = snapshot?.status;
  final identity = snapshot?.identity;
  final List<int>? branch;
  if (status != null) {
    branch = status.branchName;
  } else if (identity?.headReference case final reference?) {
    final name = ReferenceName(reference);
    branch = name.kind == ReferenceKind.localBranch ? name.short : null;
  } else {
    branch = null;
  }
  if (branch != null) {
    return (label: utf8.decode(branch, allowMalformed: true), detached: false);
  }
  final headObjectId = status == null
      ? identity?.headObjectId
      : status.headObjectId;
  if (headObjectId == null) return null;
  return (
    label: context.l10n.compassDetachedAt(
      headObjectId.substring(0, math.min(8, headObjectId.length)),
    ),
    detached: true,
  );
}
