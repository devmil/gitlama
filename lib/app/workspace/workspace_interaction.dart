import '../../models/operation_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../byte_size.dart';
import '../../models/advanced_rebase.dart';
import '../../models/app_shortcut.dart';
import '../../models/clone_attempt.dart';
import '../../models/git_names.dart';
import '../../models/history_mutation.dart';
import '../../models/integrations.dart';
import '../../models/rebase.dart';
import '../../models/repository_lock.dart';
import '../../models/ref_mutation.dart';
import '../../models/repository_state.dart';
import '../../models/stash.dart';
import '../../models/transfer.dart';
import '../../services/repository_session_service.dart';
import '../../services/settings_service.dart';
import '../../services/workflows/history_rewrite_workflows.dart';
import '../../services/workflows/index_lock_workflow.dart';
import '../../services/workflows/integration_launcher.dart';
import '../../services/workflows/ref_workflows.dart';
import '../../services/workflows/transfer_workflows.dart';
import '../../widgets/command_preview.dart';
import '../../widgets/git_reference_field.dart';
import '../../widgets/gitlama_workflow_header.dart';
import 'edit_branch_dialog.dart';
import 'git_credential_dialog.dart';
import 'history_mutation_dialogs.dart';
import 'host_key_dialog.dart';
import 'labels.dart';
import 'rebase_dialogs.dart';
import 'transfer_failure_dialog.dart';
import 'transfer_failure_guide.dart';
import 'ref_mutation_dialog.dart';
import 'stash_dialogs.dart';
import 'transfer_dialogs.dart';

/// Answers the workspace workflows with the window's dialogs and reports
/// their outcomes in its status line. One is made per user action, for the
/// [context] that started it; it stops asking once that context is gone.
final class WorkspaceInteraction
    implements
        RefInteraction,
        HistoryRewriteInteraction,
        IntegrationInteraction,
        IndexLockInteraction {
  WorkspaceInteraction(
    this.context, {
    required this.repositories,
    required this.settings,
  });

  final BuildContext context;
  final RepositorySessionService repositories;
  final SettingsService settings;

  @override
  bool get active => context.mounted;

  void _show(
    WorkflowMessage message, {
    OperationFailureDetails details = const OperationFailureDetails(),
  }) {
    if (context.mounted) {
      showWorkflowMessage(context, message, details: details);
    }
  }

  // Transfers.

  @override
  Future<TransferRequest?> chooseTransfer(TransferDraft draft) {
    final snapshot = draft.snapshot;
    final branchName = snapshot.status?.branchName;
    return showMeridianDialog<TransferRequest>(
      context: context,
      builder: (context) => TransferInputDialog(
        kind: draft.kind,
        initialForce: draft.initialForce,
        references: snapshot.refs,
        remotes: snapshot.refs.remotes
            .map((remote) => nameText(remote.name))
            .toList(growable: false),
        initialRemote: draft.initialRemote,
        initialPullStrategy: draft.initialPullStrategy,
        currentBranch: branchName,
        currentUpstream: snapshot.status?.upstream,
        branch:
            draft.initialBranch ??
            (branchName == null ? null : nameText(branchName)),
        dirty: snapshot.status?.workingTree != WorkingTreeState.clean,
      ),
    );
  }

  @override
  Future<bool> trustHostKey(HostKeyChallenge challenge) =>
      confirmHostKey(context, challenge);

  @override
  Future<TransferCredentials?> transferCredentials(String remote) async {
    final input = await showGitCredentialDialog(
      context,
      target: remote,
      allowToken: true,
    );
    if (input == null) return null;
    return TransferCredentials(
      username: input.username,
      password: input.token ? null : input.secret,
      token: input.token ? input.secret : null,
    );
  }

  @override
  Future<bool> offerRefetch(String remote) => showMeridianConfirm(
    context,
    title: context.l10n.transferMissingObjectTitle,
    description: context.l10n.transferMissingObjectDetail(remote),
    confirmLabel: context.l10n.transferRefetchAction,
    cancelLabel: context.l10n.cancel,
  );

  @override
  Future<TransferRemedy?> resolveTransferFailure(
    TransferFailureReport report,
  ) async {
    final session = report.session;
    if (session == null || !context.mounted) return null;
    return showTransferFailureDialog(
      context,
      guide: transferFailureGuide(context.l10n, report),
      details: transferFailureDetails(report.result, session),
      locks: _SessionLocks(repositories, session, canRemove: !report.remote),
      loadActivity: repositories.activityRecordFor,
    );
  }

  @override
  void reportTransfer(TransferOutcome outcome) => _show(
    transferOutcomeMessage(context, outcome),
    details: switch (outcome) {
      TransferWorkflowFailed(:final failure) => workflowFailureDetails(
        failure,
        operation: UserOperationKind.transfer,
      ),
      TransferFinished(:final result, :final session) => transferFailureDetails(
        result,
        session,
      ),
      TransferRefused(:final code) => OperationFailureDetails(
        operation: UserOperationKind.transfer,
        transfer: code,
      ),
      _ => const OperationFailureDetails(operation: UserOperationKind.transfer),
    },
  );

  // References.

  @override
  Future<RefMutationRequest?> chooseRefMutation(RefMutationDraft draft) =>
      showMeridianDialog<RefMutationRequest>(
        context: context,
        builder: (context) => RefMutationInputDialog(
          kind: draft.kind,
          references: draft.refs,
          choices: gitReferenceChoices(
            draft.refs,
            repositories.history.referencePickerCommitsFor(draft.session),
          ),
          previousRequest: draft.previousRequest,
          initialName: draft.initialName,
          initialTarget: draft.initialTarget,
        ),
      );

  @override
  Future<bool> recoverRefTarget() async =>
      await showMeridianDialog<bool>(
        context: context,
        builder: (context) => MeridianDialog(
          title: context.l10n.refMutationTargetUnavailableTitle,
          content: Text(context.l10n.refMutationTargetUnavailableDetail),
          actions: [
            MeridianButton(
              label: context.l10n.cancel,
              onPressed: () => Navigator.pop(context, false),
            ),
            MeridianButton(
              label: context.l10n.refMutationRefreshTarget,
              variant: MeridianButtonVariant.primary,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Future<EditBranchResult?> editBranch(String branch, RepositoryRefs refs) =>
      showMeridianDialog<EditBranchResult>(
        context: context,
        builder: (context) =>
            EditBranchDialog(branch: branch, references: refs),
      );

  @override
  Future<CommitCheckoutChoice?> confirmCommitCheckout(
    CommitCheckoutReview review,
  ) => showMeridianDialog<CommitCheckoutChoice>(
    context: context,
    builder: (context) => MeridianDialog(
      width: MeridianLayout.dialogConfirmWidth,
      title: context.l10n.commandCheckoutCommit,
      description: context.l10n.refConfirmCheckoutCommit(review.target),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: MeridianSpace.space5,
        children: [
          if (review.dirty) ...[
            Text(context.l10n.commitCheckoutDirtyHelp),
            Text(context.l10n.commitCheckoutStashHelp),
            Text(context.l10n.commitCheckoutReapplyHelp),
          ],
          GitCommandDetails(
            commands: [
              for (final argument
                  in review.dirty
                      ? review.stash!.commands
                      : [review.checkout.arguments])
                'git ${argument.join(' ')}',
            ],
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: context.l10n.commitCheckoutDismiss,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.pop(context),
        ),
        if (review.dirty) ...[
          MeridianButton(
            label: context.l10n.commitCheckoutStash,
            onPressed: () => Navigator.pop(context, CommitCheckoutChoice.stash),
          ),
          MeridianButton(
            label: context.l10n.commitCheckoutStashAndReapply,
            variant: MeridianButtonVariant.primary,
            onPressed: () =>
                Navigator.pop(context, CommitCheckoutChoice.stashAndReapply),
          ),
        ] else
          MeridianButton(
            label: context.l10n.commitCheckoutAction,
            variant: MeridianButtonVariant.primary,
            onPressed: () =>
                Navigator.pop(context, CommitCheckoutChoice.checkout),
          ),
      ],
    ),
  );

  @override
  Future<bool> confirmRefMutation(
    RefMutationRequest request,
    RefMutationPreview preview, {
    String? localTagObjectId,
  }) => showMeridianConfirm(
    context,
    title: refMutationConfirmationTitle(context, request),
    confirmLabel: refMutationConfirmationAction(context, request),
    cancelLabel: context.l10n.cancel,
    destructive: request.destructive,
    content: Builder(
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(refMutationConfirmationMessage(context, request)),
          if (request.name != null &&
              (request.secondName != null || request.target != null)) ...[
            const SizedBox(height: MeridianSpace.space5),
            GitLamaFlowStrip(
              source: request.target ?? request.name!,
              target: request.secondName ?? request.name!,
            ),
          ],
          if (request.remoteNames.isNotEmpty ||
              request.deleteUpstream != null) ...[
            const SizedBox(height: MeridianSpace.space5),
            Text(context.l10n.deleteRefOnRemoteWarning),
          ],
          for (final warning in preview.warnings)
            Padding(
              padding: const EdgeInsets.only(top: MeridianSpace.space4),
              child: MeridianBanner(
                tone: MeridianBannerTone.warning,
                message: refMutationWarningLabel(context, warning),
              ),
            ),
          GitCommandDetails(
            commands: [
              'git ${preview.arguments.join(' ')}',
              if (localTagObjectId != null)
                for (final remote in request.remoteNames)
                  'git push --force-with-lease=refs/tags/${request.name}:$localTagObjectId $remote :refs/tags/${request.name}',
              if (request.deleteUpstream case final upstream?)
                'git push --force-with-lease=refs/heads/${upstream.branch} ${upstream.remote} :refs/heads/${upstream.branch}',
            ],
          ),
        ],
      ),
    ),
  );

  @override
  void reportRef(RefOutcome outcome) => _show(
    refOutcomeMessage(context, outcome),
    details: outcome is RefWorkflowFailed
        ? workflowFailureDetails(
            outcome.failure,
            operation: UserOperationKind.refs,
          )
        : const OperationFailureDetails(operation: UserOperationKind.refs),
  );

  // Stash and history.

  @override
  Future<StashRequest?> chooseStash(StashDraft draft) =>
      showMeridianDialog<StashRequest>(
        context: context,
        builder: (context) => StashInputDialog(
          kind: draft.kind,
          selector: draft.selector,
          objectId: draft.objectId,
          initialMessage: draft.initialMessage,
          initialTargetBranch: draft.initialTargetBranch,
          statusEntries: draft.statusEntries,
          branches: draft.branches,
        ),
      );

  @override
  Future<bool> confirmStash(StashPreview preview) async =>
      await showMeridianDialog<bool>(
        context: context,
        builder: (context) => StashPreviewDialog(preview: preview),
      ) ==
      true;

  @override
  Future<HistoryMutationRequest?> chooseHistoryMutation(
    HistoryMutationDraft draft,
  ) => showMeridianDialog<HistoryMutationRequest>(
    context: context,
    builder: (context) => HistoryMutationInputDialog(
      kind: draft.kind,
      selectedTargets: draft.selectedTargets,
      initialSourceName: draft.initialSourceName,
      initialTarget: draft.initialTarget,
      branches: draft.branches,
      publishedHistory: draft.publishedHistory,
      conflictedWorktree: draft.conflictedWorktree,
      activeOperation: draft.activeOperation,
    ),
  );

  @override
  Future<bool> confirmHistoryMutation(
    HistoryMutationPreview preview,
    ConflictPredictionResult? prediction,
  ) async =>
      await showMeridianDialog<bool>(
        context: context,
        builder: (context) => HistoryMutationPreviewDialog(
          preview: preview,
          prediction: prediction,
        ),
      ) ==
      true;

  @override
  Future<BranchIntegration?> chooseBranchIntegration(String? sourceName) =>
      showMeridianDialog<BranchIntegration>(
        context: context,
        builder: (context) => BranchIntegrationDialog(sourceName: sourceName),
      );

  @override
  Future<RepositoryReference?> chooseRebaseTarget(
    List<RepositoryReference> branches,
  ) => showMeridianDialog<RepositoryReference>(
    context: context,
    builder: (context) => RebaseTargetDialog(branches: branches),
  );

  @override
  Future<RebaseEditResult?> editRebase(
    RebasePlan plan,
    ConflictPredictionResult? prediction,
  ) => showMeridianDialog<RebaseEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RebaseEditorDialog(
      plan: plan,
      prediction: prediction,
      shortcuts: AppShortcutCatalog.resolve(
        settings.current.shortcutOverrides,
        macOS: defaultTargetPlatform == TargetPlatform.macOS,
      ),
    ),
  );

  @override
  Future<bool> confirmRebase(RebasePreview preview) async =>
      await showMeridianDialog<bool>(
        context: context,
        builder: (context) => RebasePreviewDialog(preview: preview),
      ) ==
      true;

  @override
  Future<RepositoryReference?> chooseRestackRoot(
    List<RepositoryReference> branches,
  ) => showMeridianDialog<RepositoryReference>(
    context: context,
    builder: (context) => RestackRootDialog(branches: branches),
  );

  @override
  Future<bool?> reviewRestack(RestackPlan plan) => showMeridianDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RestackPreviewDialog(plan: plan),
  );

  @override
  void reportHistoryRewrite(HistoryRewriteOutcome outcome) => _show(
    historyRewriteOutcomeMessage(context, outcome),
    details: outcome is HistoryRewriteFailed && outcome.failure != null
        ? workflowFailureDetails(
            outcome.failure!,
            operation: UserOperationKind.history,
          )
        : const OperationFailureDetails(operation: UserOperationKind.history),
  );

  // Tools.

  @override
  Future<bool> confirmIntegration(IntegrationPreview preview) =>
      showMeridianConfirm(
        context,
        barrierDismissible: false,
        title: context.l10n.integrationPreviewTitle,
        content: GitLamaCommandPreviewContent(
          summary: context.l10n.integrationRunSummary,
          commandLines: [preview.executable, ...preview.arguments],
          external: true,
        ),
        confirmLabel: context.l10n.integrationRun,
        cancelLabel: context.l10n.cancel,
      );

  @override
  void reportIntegration(IntegrationOutcome outcome) =>
      _show(integrationOutcomeMessage(context, outcome));

  @override
  Future<bool> confirmIndexLockRemoval(int sizeBytes) => showMeridianConfirm(
    context,
    title: context.l10n.indexLockConfirmationTitle,
    description: context.l10n.indexLockConfirmation(
      formatByteSize(context.l10n, sizeBytes),
    ),
    confirmLabel: context.l10n.indexLockRemove,
    cancelLabel: context.l10n.cancel,
    destructive: true,
  );

  @override
  void reportIndexLock(IndexLockOutcome outcome) => _show(
    indexLockOutcomeMessage(context, outcome),
    details: outcome is IndexLockFailed
        ? workflowFailureDetails(
            outcome.failure,
            operation: UserOperationKind.indexLock,
          )
        : const OperationFailureDetails(operation: UserOperationKind.indexLock),
  );
}

/// The lock files of the session a failed transfer ran in.
final class _SessionLocks implements RepositoryLockControls {
  const _SessionLocks(
    this._repositories,
    this._session, {
    required this.canRemove,
  });

  final RepositorySessionService _repositories;
  final RepositorySessionIdentity _session;

  @override
  final bool canRemove;

  @override
  Future<RepositoryLockInspection> inspect() =>
      _repositories.workingCopy.inspectRepositoryLocks(_session);

  @override
  Future<int> remove(List<RepositoryLock> locks) =>
      _repositories.workingCopy.removeRepositoryLocks(_session, locks);
}
