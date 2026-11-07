import '../../models/git_names.dart';
import '../../models/ref_mutation.dart';
import '../../models/repository_state.dart';
import '../../models/transfer.dart';
import '../repository_session_service.dart';
import 'transfer_workflows.dart';
import 'workflow.dart';

/// Where a reference change the user starts begins: the dialog opens with
/// these choices over [refs].
final class RefMutationDraft {
  const RefMutationDraft({
    required this.kind,
    required this.refs,
    this.initialName,
    this.initialTarget,
    this.previousRequest,
    this.session,
  });

  final RefMutationKind kind;
  final RepositoryRefs refs;
  final String? initialName;
  final String? initialTarget;
  final RefMutationRequest? previousRequest;
  final RepositorySessionIdentity? session;
}

/// What a reference workflow asks of the window it runs in. Deleting a tag
/// or an upstream on a remote runs a transfer, so it answers those questions
/// too.
abstract interface class RefInteraction implements TransferInteraction {
  /// Lets the user describe the change; null cancels.
  Future<RefMutationRequest?> chooseRefMutation(RefMutationDraft draft);

  /// Offers refresh and reselection after a missing target. Never retries a write.
  Future<bool> recoverRefTarget();

  /// Lets the user rename [branch] and change its upstream; null cancels.
  Future<EditBranchResult?> editBranch(String branch, RepositoryRefs refs);

  /// Asks to confirm [request] as [preview] describes it. [localTagObjectId]
  /// is the deleted tag's target, which its remote deletion leases.
  Future<bool> confirmRefMutation(
    RefMutationRequest request,
    RefMutationPreview preview, {
    String? localTagObjectId,
  });

  void reportRef(RefOutcome outcome);
}

/// How a reference workflow ended, for the window to report.
sealed class RefOutcome {
  const RefOutcome();
}

/// The change ran; [state] tells how. [remoteTagDeleted] says a deleted
/// tag is already gone on a remote, whatever happened locally.
final class RefMutationFinished extends RefOutcome {
  const RefMutationFinished(this.state, {this.remoteTagDeleted = false});

  final RefMutationExecutionState state;
  final bool remoteTagDeleted;
}

/// Deleting the tag on [remote] failed, so the local tag stays.
final class RemoteTagDeleteFailed extends RefOutcome {
  const RemoteTagDeleteFailed(this.remote);

  final String remote;
}

/// The local branch was deleted, its upstream [label] on the remote not.
final class UpstreamDeleteFailed extends RefOutcome {
  const UpstreamDeleteFailed(this.label);

  final String label;
}

final class RefWorkflowFailed extends RefOutcome {
  const RefWorkflowFailed(this.failure, {this.remoteTagDeleted = false});

  final WorkflowFailure failure;
  final bool remoteTagDeleted;
}

/// Branch, tag and remote changes with their ordering rules: a rename runs
/// before the upstream change that names it, a tag goes on its remotes
/// before locally, and an upstream only after its local branch.
final class RefWorkflowService {
  RefWorkflowService(this._repositories, this._transfers);

  final RepositorySessionService _repositories;
  final TransferWorkflowService _transfers;

  RepositorySnapshot? get _snapshot =>
      _repositories.activeTab?.session?.snapshot;

  /// Lets the user describe a [kind] change of the active repository, then
  /// confirms and runs it.
  Future<void> mutate(
    RefInteraction interaction,
    RefMutationKind kind, {
    String? initialName,
    String? initialTarget,
  }) async {
    final identity = _repositories.activeTab?.session?.identity;
    RefMutationRequest? previous;
    while (interaction.active) {
      final snapshot = _snapshot;
      final request = await interaction.chooseRefMutation(
        RefMutationDraft(
          kind: kind,
          refs: snapshot?.refs ?? const RepositoryRefs(),
          session: identity,
          initialName: initialName,
          // Commands outside a commit context always start at HEAD.
          initialTarget: initialTarget ?? snapshot?.status?.headObjectId,
          previousRequest: previous,
        ),
      );
      if (request == null || !interaction.active) return;
      if (!_sameSession(identity)) {
        interaction.reportRef(
          const RefMutationFinished(RefMutationExecutionState.stale),
        );
        return;
      }
      final missing = await run(
        interaction,
        request,
        recoverMissingTarget: true,
      );
      if (!missing || !interaction.active || !_sameSession(identity)) return;
      if (!await interaction.recoverRefTarget() || !interaction.active) return;
      if (!_sameSession(identity)) return;
      try {
        await _repositories.refreshAndWait(identity!);
        if (!interaction.active || !_sameSession(identity)) return;
        await _repositories.history.load(identity);
        if (!interaction.active || !_sameSession(identity)) return;
      } on Object catch (error) {
        if (interaction.active) {
          interaction.reportRef(
            RefWorkflowFailed(
              WorkflowFailure.of(error) ?? const UnexpectedFailure(),
            ),
          );
        }
        return;
      }
      // Reopen for an explicit choice, retaining the failed target and all input.
      previous = request;
    }
  }

  bool _sameSession(RepositorySessionIdentity? identity) {
    final current = _repositories.activeTab?.session?.identity;
    return identity != null &&
        current != null &&
        identity.nativeId == current.nativeId &&
        identity.generation == current.generation &&
        identity.backend == current.backend;
  }

  /// Confirms and runs [request]. Deleting a tag deletes it on the chosen
  /// remotes first; deleting a branch deletes its upstream afterwards, and
  /// only when the local branch went. Returns true only when the caller should
  /// offer missing-target recovery; no mutation is retried here.
  Future<bool> run(
    RefInteraction interaction,
    RefMutationRequest request, {
    bool recoverMissingTarget = false,
  }) async {
    var remoteTagDeleted = false;
    RefMutationPreview? issued;
    final identity = _repositories.activeTab?.session?.identity;
    void ensureSession() {
      if (!_sameSession(identity)) {
        throw const RepositorySessionException(
          RepositoryFailure(RepositoryFailureCode.staleGeneration),
        );
      }
    }

    try {
      ensureSession();
      final preview = await _repositories.refs.preview(request);
      issued = preview;
      if (!interaction.active) return false;
      ensureSession();
      final localTagObjectId = request.kind == RefMutationKind.deleteTag
          ? _snapshot?.refs.tagNamed(request.name ?? '')?.target
          : null;
      final confirmed = await interaction.confirmRefMutation(
        request,
        preview,
        localTagObjectId: localTagObjectId,
      );
      if (!confirmed || !interaction.active) return false;
      ensureSession();
      for (final remote in request.remoteNames) {
        final succeeded = await _transfers.execute(
          interaction,
          TransferRequest(
            kind: TransferKind.deleteTag,
            remote: remote,
            branch: request.name,
          ),
          notifyResult: false,
        );
        if (succeeded) remoteTagDeleted = true;
        if (!interaction.active) return false;
        ensureSession();
        if (!succeeded) {
          interaction.reportRef(RemoteTagDeleteFailed(remote));
          return false;
        }
      }
      final result = await _repositories.refs.execute(preview.token);
      if (!interaction.active) return false;
      final localDone = _done(result.state);
      // The remote branch goes only after the local one, so an unmerged
      // branch that git refuses to delete keeps its upstream too.
      if (request.deleteUpstream case final upstream? when localDone) {
        if (!_sameSession(identity)) {
          interaction.reportRef(UpstreamDeleteFailed(upstream.label));
          return false;
        }
        final succeeded = await _transfers.execute(
          interaction,
          TransferRequest(
            kind: TransferKind.deleteBranch,
            remote: upstream.remote,
            branch: upstream.branch,
          ),
          notifyResult: false,
        );
        if (!interaction.active) return false;
        if (!succeeded) {
          interaction.reportRef(UpstreamDeleteFailed(upstream.label));
          return false;
        }
      }
      interaction.reportRef(
        RefMutationFinished(result.state, remoteTagDeleted: remoteTagDeleted),
      );
    } on Object catch (error) {
      if (recoverMissingTarget &&
          request.target != null &&
          !remoteTagDeleted &&
          error is RepositorySessionException &&
          error.failure.code == RepositoryFailureCode.missingObject) {
        return true;
      }
      final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
      if (interaction.active) {
        interaction.reportRef(
          RefWorkflowFailed(failure, remoteTagDeleted: remoteTagDeleted),
        );
      }
    } finally {
      if (issued != null) _repositories.refs.discard(issued.token);
    }
    return false;
  }

  /// Renames a local branch and changes its upstream in one dialog. The
  /// rename runs first, so the upstream change addresses the new name.
  /// Without a branch to edit the plain rename dialog opens.
  Future<void> editBranch(
    RefInteraction interaction,
    String? initialName,
  ) async {
    final snapshot = _snapshot;
    final status = snapshot?.status;
    final branch =
        initialName ??
        (status?.branchName == null ? null : nameText(status!.branchName!));
    if (snapshot == null || branch == null) {
      await mutate(interaction, RefMutationKind.renameBranch);
      return;
    }
    final edit = await interaction.editBranch(branch, snapshot.refs);
    if (edit == null || !interaction.active) return;
    final upstream = snapshot.refs.upstreamLabelOf(branch);
    final requests = [
      if (edit.name != branch)
        RefMutationRequest(
          kind: RefMutationKind.renameBranch,
          name: branch,
          secondName: edit.name,
        ),
      if (edit.upstream != upstream)
        edit.upstream == null
            ? RefMutationRequest(
                kind: RefMutationKind.unsetUpstream,
                name: edit.name,
              )
            : RefMutationRequest(
                kind: RefMutationKind.setUpstream,
                name: edit.name,
                secondName: edit.upstream,
              ),
    ];
    var state = RefMutationExecutionState.completed;
    try {
      for (final request in requests) {
        final preview = await _repositories.refs.preview(request);
        if (!interaction.active) return;
        if (preview.warnings.isNotEmpty &&
            !await interaction.confirmRefMutation(request, preview)) {
          return;
        }
        if (!interaction.active) return;
        final result = await _repositories.refs.execute(preview.token);
        if (!interaction.active) return;
        state = result.state;
        if (!_done(state)) break;
      }
    } on Object catch (error) {
      final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
      if (interaction.active) interaction.reportRef(RefWorkflowFailed(failure));
      return;
    }
    if (interaction.active) interaction.reportRef(RefMutationFinished(state));
  }

  /// Checks out [name]. A remote-tracking branch ([reference] under
  /// `refs/remotes/`, or a name that is no local branch but starts with a
  /// remote) checks out the local branch that tracks it, or creates one.
  Future<void> checkout(
    RefInteraction interaction,
    String? name,
    String? reference,
  ) async {
    final refs = _snapshot?.refs;
    if (refs != null &&
        name != null &&
        (RefNames.isRemoteTracking(reference) ||
            (reference == null && refs.branchNamed(name) == null))) {
      if (refs.splitRemoteTracking(name) case final tracking?) {
        final remoteRef = RefNames.remoteTracking(
          tracking.remote,
          tracking.branch,
        );
        final local = refs.branchTracking(remoteRef);
        if (local != null) {
          await mutate(
            interaction,
            RefMutationKind.checkoutBranch,
            initialName: nameText(local.name),
          );
        } else {
          await mutate(
            interaction,
            RefMutationKind.createBranch,
            initialName: tracking.branch,
            initialTarget: remoteRef,
          );
        }
        return;
      }
    }
    await mutate(
      interaction,
      RefMutationKind.checkoutBranch,
      initialName: name,
    );
  }

  /// Deletes a branch on its remote. [reference] is the full name of the
  /// remote-tracking branch to preselect; a remote name may contain a slash,
  /// so the remote and branch come from the references rather than from
  /// splitting it. Without a matching branch nothing is preselected, not even
  /// the checked-out one: the user picks what to delete.
  Future<void> deleteRemoteBranch(
    TransferInteraction interaction,
    String? reference,
  ) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final target = snapshot.refs.remoteBranchOf(reference);
    await _transfers.start(
      interaction,
      TransferDraft(
        kind: TransferKind.deleteBranch,
        snapshot: snapshot,
        initialRemote: target?.remote,
        initialBranch: target?.branch ?? '',
      ),
    );
  }

  static bool _done(RefMutationExecutionState state) =>
      state == RefMutationExecutionState.completed ||
      state == RefMutationExecutionState.reconciledWithWarning;
}
