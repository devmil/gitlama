import '../../models/advanced_rebase.dart';
import '../../models/git_names.dart';
import '../../models/history_mutation.dart';
import '../../models/rebase.dart';
import '../../models/ref_mutation.dart';
import '../../models/repository_state.dart';
import '../../models/stash.dart';
import '../../models/workspace.dart';
import '../repository_session_service.dart';
import 'repository_busy.dart';
import 'workflow.dart';
import 'workspace_navigator.dart';

/// Where a stash workflow begins: the dialog opens with these choices.
final class StashDraft {
  const StashDraft({
    required this.kind,
    this.selector,
    this.objectId,
    this.initialMessage,
    this.initialTargetBranch,
    this.statusEntries = const [],
    this.branches = const [],
  });

  final StashKind kind;
  final String? selector;
  final String? objectId;

  /// The stash's current message when it is renamed.
  final String? initialMessage;
  final String? initialTargetBranch;
  final List<RepositoryStatusEntry> statusEntries;
  final List<String> branches;
}

/// Where a merge, cherry-pick or revert begins.
final class HistoryMutationDraft {
  const HistoryMutationDraft({
    required this.kind,
    required this.selectedTargets,
    required this.branches,
    required this.publishedHistory,
    this.initialSourceName,
    this.initialTarget,
    this.dirtyWorktree = false,
    this.activeOperation = false,
  });

  final HistoryMutationKind kind;
  final List<String> selectedTargets;

  /// Local branches and remote-tracking branches (`remote/branch`).
  final List<RepositoryReference> branches;
  final bool publishedHistory;
  final String? initialSourceName;
  final String? initialTarget;
  final bool dirtyWorktree;
  final bool activeOperation;
}

/// How a branch is brought into the current one.
enum BranchIntegration { merge, rebase }

enum CommitCheckoutChoice { checkout, stash, stashAndReapply }

/// Exact, one-shot checkout plans reviewed together before choosing an effect.
final class CommitCheckoutReview {
  const CommitCheckoutReview({
    required this.target,
    required this.checkout,
    this.stash,
    this.stashAndReapply,
  });
  final String target;
  final RefMutationPreview checkout;
  final StashPreview? stash;
  final StashPreview? stashAndReapply;
  bool get dirty => stash != null;
}

/// What stash and history workflows ask of the window they run in.
abstract interface class HistoryRewriteInteraction
    implements WorkflowInteraction {
  Future<CommitCheckoutChoice?> confirmCommitCheckout(
    CommitCheckoutReview review,
  );
  Future<StashRequest?> chooseStash(StashDraft draft);
  Future<bool> confirmStash(StashPreview preview);
  Future<HistoryMutationRequest?> chooseHistoryMutation(
    HistoryMutationDraft draft,
  );
  Future<bool> confirmHistoryMutation(
    HistoryMutationPreview preview,
    ConflictPredictionResult? prediction,
  );
  Future<BranchIntegration?> chooseBranchIntegration(String? sourceName);
  Future<RepositoryReference?> chooseRebaseTarget(
    List<RepositoryReference> branches,
  );
  Future<RebaseEditResult?> editRebase(
    RebasePlan plan,
    ConflictPredictionResult? prediction,
  );
  Future<bool> confirmRebase(RebasePreview preview);
  Future<RepositoryReference?> chooseRestackRoot(
    List<RepositoryReference> branches,
  );

  /// Shows the restack plan. Null cancels; otherwise whether published
  /// history was acknowledged.
  Future<bool?> reviewRestack(RestackPlan plan);

  void reportHistoryRewrite(HistoryRewriteOutcome outcome);
}

/// How a stash or history workflow ended, for the window to report.
sealed class HistoryRewriteOutcome {
  const HistoryRewriteOutcome();
}

final class CommitCheckoutFinished extends HistoryRewriteOutcome {
  const CommitCheckoutFinished(this.state);
  final RefMutationExecutionState state;
}

final class StashFinished extends HistoryRewriteOutcome {
  const StashFinished(this.result);

  final StashExecutionResult result;
}

final class StashRefused extends HistoryRewriteOutcome {
  const StashRefused(this.code);

  final StashFailureCode code;
}

final class HistoryMutationFinished extends HistoryRewriteOutcome {
  const HistoryMutationFinished(this.preview, this.result);

  final HistoryMutationPreview preview;
  final HistoryMutationExecutionResult result;
}

final class HistoryMutationRefused extends HistoryRewriteOutcome {
  const HistoryMutationRefused(this.code);

  final HistoryMutationFailureCode code;
}

final class RebaseFinished extends HistoryRewriteOutcome {
  const RebaseFinished(this.result);

  final RebaseExecutionResult result;
}

final class RebaseRefused extends HistoryRewriteOutcome {
  const RebaseRefused(this.code);

  final RebaseFailureCode code;
}

/// Every branch above the chosen root already sits on it.
final class RestackNothingToDo extends HistoryRewriteOutcome {
  const RestackNothingToDo();
}

final class RestackFinished extends HistoryRewriteOutcome {
  const RestackFinished(this.result);

  final RestackExecutionResult result;
}

/// Which workflow a [HistoryRewriteFailed] interrupted.
enum HistoryRewriteKind { stash, historyMutation, rebase, restack }

final class HistoryRewriteFailed extends HistoryRewriteOutcome {
  const HistoryRewriteFailed(this.kind, this.failure);

  final HistoryRewriteKind kind;

  /// Null for a restack the core refused.
  final WorkflowFailure? failure;
}

/// Stash, merge, cherry-pick, revert, interactive rebase and restack, with
/// conflict prediction. Each runs under its tab's busy overlay and shows
/// Changes when it stops on a conflict.
final class HistoryRewriteWorkflowService {
  HistoryRewriteWorkflowService(
    this._repositories,
    this._busy,
    this._navigator,
  );

  final RepositorySessionService _repositories;
  final RepositoryBusyService _busy;
  final WorkspaceNavigator _navigator;

  RepositorySnapshot? get _snapshot =>
      _repositories.activeTab?.session?.snapshot;

  void _report(
    HistoryRewriteInteraction interaction,
    HistoryRewriteOutcome outcome,
  ) {
    if (interaction.active) interaction.reportHistoryRewrite(outcome);
  }

  void _showChanges(int? tabId) =>
      _navigator.selectPane(WorkspacePane.changes, tabId: tabId);

  /// Checks out an exact commit with detached HEAD, after one confirmation.
  /// Dirty checkouts explicitly choose whether their stash is reapplied.
  Future<void> checkoutCommit(
    HistoryRewriteInteraction interaction,
    String? target,
  ) async {
    final tab = _repositories.activeTab;
    final snapshot = tab?.session?.snapshot;
    if (target == null ||
        !RegExp(r'^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$').hasMatch(target) ||
        snapshot?.status == null ||
        _busy.isBusy(tab!.id) ||
        snapshot!.status!.operations.isNotEmpty ||
        snapshot.status!.entries.any((entry) => entry.conflicted)) {
      return;
    }
    final session = tab.session!.identity;
    bool current() {
      final active = _repositories.activeTab;
      final identity = active?.session?.identity;
      return interaction.active &&
          active?.id == tab.id &&
          identity?.nativeId == session.nativeId &&
          identity?.generation == session.generation &&
          identity?.backend == session.backend;
    }

    try {
      final checkout = await _repositories.refs.preview(
        RefMutationRequest(
          kind: RefMutationKind.checkoutCommit,
          target: target,
        ),
      );
      if (!current()) return;
      final dirty = checkout.warnings.contains(
        RefMutationWarning.dirtyCheckout,
      );
      final stash = dirty
          ? await _repositories.stashes.preview(
              StashRequest(
                kind: StashKind.stashCheckoutCommit,
                objectId: target,
              ),
            )
          : null;
      if (!current()) return;
      final reapply = dirty
          ? await _repositories.stashes.preview(
              StashRequest(
                kind: StashKind.autoStashCheckoutCommit,
                objectId: target,
              ),
            )
          : null;
      if (!current()) return;
      final choice = await interaction.confirmCommitCheckout(
        CommitCheckoutReview(
          target: target,
          checkout: checkout,
          stash: stash,
          stashAndReapply: reapply,
        ),
      );
      if (choice == null || !current() || _busy.isBusy(tab.id)) {
        return;
      }
      if (choice == CommitCheckoutChoice.checkout) {
        // Dirty repositories must use one of the stash choices.
        if (dirty) return;
        final result = await _busy.run(
          tab.id,
          const CommitCheckoutBusy(),
          () => _repositories.refs.execute(checkout.token),
        );
        _report(interaction, CommitCheckoutFinished(result.state));
      } else {
        final preview = choice == CommitCheckoutChoice.stash ? stash : reapply;
        if (preview == null) return;
        final result = await _busy.run(
          tab.id,
          StashBusy(preview.kind),
          () => _repositories.stashes.execute(preview),
          cancel: isRemoteTab(tab)
              ? null
              : () => _repositories.stashes.cancel(preview),
        );
        _report(interaction, StashFinished(result));
        if (result.state == StashExecutionState.conflict) _showChanges(tab.id);
      }
    } on StashException catch (error) {
      _report(interaction, StashRefused(error.code));
    } on Object catch (error) {
      _fail(interaction, HistoryRewriteKind.stash, error);
    }
  }

  /// Pushes, applies, pops, renames or drops a stash, or checks out
  /// [targetBranch] with the changes stashed around it.
  Future<void> stash(
    HistoryRewriteInteraction interaction,
    StashKind kind, {
    String? selector,
    String? objectId,
    String? targetBranch,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final stash = snapshot.refs.stashWithSelector(selector);
    final request = await interaction.chooseStash(
      StashDraft(
        kind: kind,
        selector: selector,
        objectId: objectId,
        initialMessage: kind == StashKind.rename && stash != null
            ? nameText(stash.subject)
            : null,
        initialTargetBranch: targetBranch,
        statusEntries: snapshot.status?.entries ?? const [],
        branches: snapshot.refs.branches
            .map((branch) => nameText(branch.name))
            .toList(growable: false),
      ),
    );
    if (request == null || !interaction.active) return;
    final tab = _repositories.activeTab;
    final tabId = tab?.id;
    try {
      final preview = await _repositories.stashes.preview(request);
      if (!interaction.active) return;
      if (!await interaction.confirmStash(preview) || !interaction.active) {
        return;
      }
      final result = await _busy.run(
        tabId,
        StashBusy(preview.kind),
        () => _repositories.stashes.execute(preview),
        // A remote stash runs to its receipt; it cannot be canceled.
        cancel: isRemoteTab(tab)
            ? null
            : () => _repositories.stashes.cancel(preview),
      );
      if (!interaction.active) return;
      _report(interaction, StashFinished(result));
      if (result.state == StashExecutionState.conflict) _showChanges(tabId);
    } on StashException catch (error) {
      _report(interaction, StashRefused(error.code));
    } on Object catch (error) {
      _fail(interaction, HistoryRewriteKind.stash, error);
    }
  }

  void _fail(
    HistoryRewriteInteraction interaction,
    HistoryRewriteKind kind,
    Object error,
  ) {
    final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
    _report(interaction, HistoryRewriteFailed(kind, failure));
  }

  Future<ConflictPredictionResult> _predict(ConflictPredictionTask task) =>
      _busy.run(
        _repositories.activeTabId,
        const ConflictPredictionBusy(),
        () => _repositories.historyMutations.executeConflictPrediction(task),
        cancel: () =>
            _repositories.historyMutations.cancelConflictPrediction(task),
      );

  /// Every local branch and every remote-tracking branch, by full short name.
  List<RepositoryReference> _branchChoices(RepositoryRefs refs) => [
    ...refs.branches,
    ...refs.remoteTrackingReferences,
  ];

  /// Merges a branch, or cherry-picks or reverts commits: [target] or the
  /// commits History has selected. A merge predicts its conflicts first.
  Future<void> mutateHistory(
    HistoryRewriteInteraction interaction,
    HistoryMutationKind kind, {
    String? sourceName,
    String? target,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final tabId = _repositories.activeTabId;
    final selected = kind != HistoryMutationKind.merge && target != null
        ? <String>[target]
        : _repositories.history.current.page?.selectedObjectIds ??
              const <String>[];
    final input = await interaction.chooseHistoryMutation(
      HistoryMutationDraft(
        kind: kind,
        selectedTargets: selected,
        initialSourceName: sourceName,
        initialTarget: target,
        branches: _branchChoices(snapshot.refs),
        publishedHistory: snapshot.refs.branches.any(
          (branch) => branch.head && branch.published,
        ),
        dirtyWorktree: snapshot.status?.workingTree != WorkingTreeState.clean,
        activeOperation: snapshot.status?.operations.isNotEmpty ?? false,
      ),
    );
    bool sameTab() => interaction.active && _repositories.activeTabId == tabId;
    if (input == null || !sameTab()) return;
    try {
      final preview = await _repositories.historyMutations.preview(input);
      ConflictPredictionResult? prediction;
      if (kind == HistoryMutationKind.merge && !preview.alreadyContained) {
        final task = await _repositories.historyMutations
            .beginConflictPrediction(
              ConflictPredictionKind.merge,
              preview.targets.single,
            );
        if (!interaction.active) return;
        prediction = await _predict(task);
      }
      // The preview belongs to the tab it was asked for.
      if (!sameTab()) return;
      final confirmed = await interaction.confirmHistoryMutation(
        preview,
        prediction,
      );
      if (!confirmed || !sameTab()) return;
      final result = await _busy.run(
        tabId,
        HistoryMutationBusy(preview),
        () => _repositories.historyMutations.execute(preview),
        cancel: () => _repositories.historyMutations.cancel(preview),
      );
      if (!interaction.active) return;
      _report(interaction, HistoryMutationFinished(preview, result));
      if (result.state == HistoryMutationExecutionState.conflict ||
          (preview.noCommit &&
              result.state == HistoryMutationExecutionState.completed)) {
        _showChanges(tabId);
      }
    } on HistoryMutationException catch (error) {
      _report(interaction, HistoryMutationRefused(error.code));
    } on Object catch (error) {
      _fail(interaction, HistoryRewriteKind.historyMutation, error);
    }
  }

  /// Lets the user merge [sourceName] or rebase onto it.
  Future<void> integrateBranch(
    HistoryRewriteInteraction interaction, {
    String? sourceName,
    String? target,
  }) async {
    final choice = await interaction.chooseBranchIntegration(sourceName);
    if (!interaction.active) return;
    switch (choice) {
      case BranchIntegration.merge:
        await mutateHistory(
          interaction,
          HistoryMutationKind.merge,
          sourceName: sourceName,
          target: target,
        );
      case BranchIntegration.rebase:
        await rebase(interaction, target: target);
      case null:
        break;
    }
  }

  /// Rebases the current branch interactively onto the branch at [target],
  /// or one the user chooses, after predicting its conflicts.
  Future<void> rebase(
    HistoryRewriteInteraction interaction, {
    String? target,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final branches = _branchChoices(snapshot.refs);
    final selected =
        (target == null
            ? null
            : branches
                  .where((branch) => branch.target == target)
                  .firstOrNull) ??
        await interaction.chooseRebaseTarget(
          branches.where((branch) => !branch.head).toList(),
        );
    if (selected == null || !interaction.active) return;
    final tabId = _repositories.activeTabId;
    try {
      final plan = await _repositories.rebases.loadPlan(
        selected.target,
        selected.name,
      );
      if (!interaction.active) return;
      final task = await _repositories.historyMutations.beginConflictPrediction(
        ConflictPredictionKind.rebase,
        selected.target,
      );
      if (!interaction.active) return;
      final prediction = await _predict(task);
      // The editor belongs to the tab it was asked for.
      if (!interaction.active || _repositories.activeTabId != tabId) return;
      final edit = await interaction.editRebase(plan, prediction);
      if (edit == null || !interaction.active) return;
      final preview = await _repositories.rebases.preview(
        plan,
        edit.instructions,
        edit.acknowledgePublishedHistory,
        edit.applyAutosquash,
      );
      if (!interaction.active) return;
      if (!await interaction.confirmRebase(preview) || !interaction.active) {
        return;
      }
      final result = await _busy.run(
        tabId,
        RebaseBusy(currentBranch: plan.currentBranch, onto: selected.name),
        () => _repositories.rebases.execute(preview),
        cancel: () => _repositories.rebases.cancel(preview.token),
      );
      if (!interaction.active) return;
      _report(interaction, RebaseFinished(result));
      if (result.state == RebaseExecutionState.conflict ||
          result.state == RebaseExecutionState.editStop ||
          result.state == RebaseExecutionState.interrupted) {
        _showChanges(tabId);
      }
    } on RebaseException catch (error) {
      _report(interaction, RebaseRefused(error.code));
    } on Object catch (error) {
      _fail(interaction, HistoryRewriteKind.rebase, error);
    }
  }

  /// Moves every branch stacked on [rootName] (or a root the user chooses)
  /// onto its updated base.
  Future<void> restack(
    HistoryRewriteInteraction interaction,
    String? rootName,
  ) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final root =
        (rootName == null ? null : snapshot.refs.branchNamed(rootName)) ??
        await interaction.chooseRestackRoot(snapshot.refs.branches);
    if (root == null || !interaction.active) return;
    final tabId = _repositories.activeTabId;
    try {
      final plan = await _repositories.advancedRebases.planRestack(root.name);
      if (!interaction.active) return;
      if (plan.steps.isEmpty) {
        _report(interaction, const RestackNothingToDo());
        return;
      }
      final acknowledge = await interaction.reviewRestack(plan);
      if (acknowledge == null || !interaction.active) {
        await _repositories.advancedRebases.cancelRestack(plan);
        return;
      }
      final result = await _busy.run(
        tabId,
        RestackBusy(plan.rootBranch),
        () => _repositories.advancedRebases.executeRestack(
          plan,
          acknowledgePublishedHistory: acknowledge,
        ),
        cancel: () => _repositories.advancedRebases.cancelRestack(plan),
      );
      if (!interaction.active) return;
      _report(interaction, RestackFinished(result));
      if (result.state == RestackExecutionState.conflict ||
          result.state == RestackExecutionState.partial) {
        _showChanges(tabId);
      }
    } on AdvancedRebaseException {
      _report(
        interaction,
        const HistoryRewriteFailed(HistoryRewriteKind.restack, null),
      );
    } on Object catch (error) {
      _fail(interaction, HistoryRewriteKind.restack, error);
    }
  }
}
