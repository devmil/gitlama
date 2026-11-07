import 'dart:async';

import '../../models/clone_attempt.dart';
import '../../models/operation_center.dart';
import '../../models/repository_state.dart';
import '../../models/transfer.dart';
import '../repository_session_service.dart';
import 'sync_change_tracker.dart';
import 'workflow.dart';

/// Where a transfer the user starts begins: the dialog opens with these
/// choices over [snapshot]'s references.
final class TransferDraft {
  const TransferDraft({
    required this.kind,
    required this.snapshot,
    this.initialForce = false,
    this.initialRemote,
    this.initialBranch,
    this.initialPullStrategy = PullStrategy.fastForwardOnly,
  });

  final TransferKind kind;
  final RepositorySnapshot snapshot;
  final bool initialForce;
  final String? initialRemote;

  /// The branch to preselect; the checked-out branch when null.
  final String? initialBranch;
  final PullStrategy initialPullStrategy;
}

/// What a transfer asks of the window it runs in.
abstract interface class TransferInteraction implements WorkflowInteraction {
  /// Lets the user choose the transfer; null cancels.
  Future<TransferRequest?> chooseTransfer(TransferDraft draft);

  /// Asks whether to trust [challenge]'s host key.
  Future<bool> trustHostKey(HostKeyChallenge challenge);

  /// Asks for credentials for [remote]; null cancels.
  Future<TransferCredentials?> transferCredentials(String remote);

  /// Offers to fetch [remote] again after a missing local object.
  Future<bool> offerRefetch(String remote);

  /// Explains a failure the failure catalog recognises and lets the user
  /// choose a remedy; null leaves it.
  Future<TransferRemedy?> resolveTransferFailure(TransferFailureReport report);

  void reportTransfer(TransferOutcome outcome);
}

/// A failed transfer that the failure catalog can explain.
final class TransferFailureReport {
  const TransferFailureReport({
    required this.request,
    required this.result,
    required this.session,
  });

  final TransferRequest request;
  final TransferExecutionResult result;

  /// The session the transfer ran in; locks and refs are repaired there.
  final RepositorySessionIdentity? session;

  /// Lock files and refs of a repository on another computer are not
  /// changed from this one.
  bool get remote => session?.backend == RepositoryBackendKind.remote;

  /// Whether the catalog has something to say about [result].
  static bool explains(TransferExecutionResult result) =>
      (result.stash != null && !result.stash!.reapplyCompleted) ||
      result.failure == TransferFailureCode.locked ||
      switch (result.diagnosis?.kind) {
        TransferDiagnosisKind.refCaseCollision ||
        TransferDiagnosisKind.remoteAhead => true,
        _ => false,
      };
}

/// What the user chose to do about a failed transfer.
sealed class TransferRemedy {
  const TransferRemedy();
}

/// Run the same transfer again.
final class RetryTransfer extends TransferRemedy {
  const RetryTransfer();
}

/// Run the fetch again without pruning deleted remote branches.
final class RetryWithoutPrune extends TransferRemedy {
  const RetryWithoutPrune();
}

/// Delete the local remote-tracking [references], then run the transfer again.
final class RepairTrackingRefs extends TransferRemedy {
  const RepairTrackingRefs(this.references);

  final List<String> references;
}

/// Fetch the transfer's remote.
final class FetchRemote extends TransferRemedy {
  const FetchRemote();
}

/// How a transfer ended, for the window to report.
sealed class TransferOutcome {
  const TransferOutcome();
}

/// The transfer ran; [result] tells how.
final class TransferFinished extends TransferOutcome {
  const TransferFinished(this.request, this.result, {this.session});

  final TransferRequest request;
  final TransferExecutionResult result;

  /// The session the transfer ran in, whose activity holds its Git output.
  final RepositorySessionIdentity? session;
}

/// A transfer of a repository on another computer needed a host key or
/// credentials, which are never entered on this computer for it.
final class RemoteTransferNeedsHost extends TransferOutcome {
  const RemoteTransferNeedsHost(this.failure);

  /// [TransferFailureCode.hostKey] or [TransferFailureCode.authentication].
  final TransferFailureCode failure;
}

/// The transfer was refused before it ran.
final class TransferRefused extends TransferOutcome {
  const TransferRefused(this.code);

  final TransferFailureCode code;
}

/// The host key could not be read.
final class TransferHostKeyProbeFailed extends TransferOutcome {
  const TransferHostKeyProbeFailed();
}

final class TransferWorkflowFailed extends TransferOutcome {
  const TransferWorkflowFailed(this.failure);

  final WorkflowFailure failure;
}

/// Fetch, pull and push with their host-key trust, credential retry and
/// refetch offer. It owns the transfers it runs, so the operation center can
/// cancel them, and records the sync baseline so the window can show what a
/// transfer changed.
final class TransferWorkflowService {
  TransferWorkflowService(this._repositories, this._sync);

  final RepositorySessionService _repositories;
  final SyncChangeTracker _sync;
  final List<({TransferPreview preview, RepositorySessionIdentity? session})>
  _running = [];
  final StreamController<void> _runningChanges =
      StreamController<void>.broadcast(sync: true);
  var _disposed = false;

  /// Fires when a transfer starts or ends.
  Stream<void> get runningChanges => _runningChanges.stream;

  /// Lets the user choose a transfer from [draft], then runs it.
  Future<void> start(
    TransferInteraction interaction,
    TransferDraft draft,
  ) async {
    final request = await interaction.chooseTransfer(draft);
    if (request == null || !interaction.active) return;
    await execute(interaction, request);
  }

  /// Runs [request] for the active tab. With [notifyResult] the window
  /// reports how it ended; failures are always reported. Completes with
  /// whether it succeeded.
  Future<bool> execute(
    TransferInteraction interaction,
    TransferRequest request, {
    bool notifyResult = true,
  }) async {
    final beforeTab = _repositories.activeTab;
    final sourceIdentity = beforeTab?.session?.identity;
    // A remote transfer runs with the host's own trust and credentials:
    // nothing is trusted or entered on this computer for it.
    final remote = isRemoteTab(beforeTab);
    final baseline = _sync.capture();
    try {
      final preview = await _repositories.transfers.preview(request);
      if (!interaction.active) return false;
      var result = await _run(preview);
      if (!interaction.active) return false;
      bool needsStashRecovery() =>
          result.stash != null && !result.stash!.reapplyCompleted;
      if (!needsStashRecovery() &&
          remote &&
          (result.failure == TransferFailureCode.hostKey ||
              result.failure == TransferFailureCode.authentication)) {
        interaction.reportTransfer(RemoteTransferNeedsHost(result.failure!));
        return false;
      }
      if (!needsStashRecovery() &&
          result.failure == TransferFailureCode.hostKey) {
        final challenge = await _repositories.transfers.probeHostKey(preview);
        if (!interaction.active) return false;
        final accept = await interaction.trustHostKey(challenge);
        await _repositories.transfers.resolveHostKey(
          preview,
          challenge,
          accept: accept,
        );
        if (!accept || !interaction.active) return false;
        result = await _run(preview);
        if (!interaction.active) return false;
      }
      if (!needsStashRecovery() &&
          result.failure == TransferFailureCode.authentication) {
        final credentials = await interaction.transferCredentials(
          preview.remote,
        );
        if (credentials == null || !interaction.active) return false;
        result = await _run(preview, credentials: credentials);
        if (!interaction.active) return false;
      }
      bool sameSession() {
        final active = _repositories.activeTab;
        final activeIdentity = active?.session?.identity;
        return beforeTab != null &&
            active?.id == beforeTab.id &&
            sourceIdentity != null &&
            activeIdentity?.nativeId == sourceIdentity.nativeId &&
            activeIdentity?.generation == sourceIdentity.generation;
      }

      // Recovery is not a retryable transfer. The pull may already be complete,
      // or a Git sequencer may own the index while the saved work waits.
      if (needsStashRecovery()) {
        if (result.stash!.pullCompleted && baseline != null) {
          _sync.expect(baseline);
        }
        if (sameSession()) {
          await interaction.resolveTransferFailure(
            TransferFailureReport(
              request: request,
              result: result,
              session: sourceIdentity,
            ),
          );
        } else {
          interaction.reportTransfer(
            TransferFinished(request, result, session: sourceIdentity),
          );
        }
        return false;
      }

      // The catalog dialog reports this failure itself; a remedy starts afresh.
      if (TransferFailureReport.explains(result) && sameSession()) {
        final remedy = await interaction.resolveTransferFailure(
          TransferFailureReport(
            request: request,
            result: result,
            session: sourceIdentity,
          ),
        );
        if (remedy == null || !interaction.active || !sameSession()) {
          return false;
        }
        return await _apply(
          interaction,
          request,
          remedy,
          sourceIdentity!,
          notifyResult: notifyResult,
        );
      }
      if (notifyResult) {
        interaction.reportTransfer(
          TransferFinished(request, result, session: sourceIdentity),
        );
      }

      if (result.failure == TransferFailureCode.missingObject &&
          !request.refetch &&
          sameSession()) {
        final refetch = await interaction.offerRefetch(preview.remote);
        if (refetch && interaction.active && sameSession()) {
          await execute(
            interaction,
            TransferRequest(
              kind: TransferKind.fetch,
              remote: preview.remote,
              refetch: true,
            ),
          );
        }
      }
      final succeeded =
          result.state == TransferExecutionState.completed ||
          result.state == TransferExecutionState.reconciledWithWarning;
      if (succeeded && baseline != null) _sync.expect(baseline);
      return succeeded;
    } on TransferException catch (error) {
      if (interaction.active) {
        interaction.reportTransfer(TransferRefused(error.code));
      }
      return false;
    } on CloneException {
      if (interaction.active) {
        interaction.reportTransfer(const TransferHostKeyProbeFailed());
      }
      return false;
    } on Object catch (error) {
      final failure = WorkflowFailure.of(error) ?? const UnexpectedFailure();
      if (interaction.active) {
        interaction.reportTransfer(TransferWorkflowFailed(failure));
      }
      return false;
    }
  }

  Future<bool> _apply(
    TransferInteraction interaction,
    TransferRequest request,
    TransferRemedy remedy,
    RepositorySessionIdentity session, {
    required bool notifyResult,
  }) async {
    switch (remedy) {
      case RetryTransfer():
        return execute(interaction, request, notifyResult: notifyResult);
      case RetryWithoutPrune():
        return execute(
          interaction,
          request.copyWith(prune: false),
          notifyResult: notifyResult,
        );
      case FetchRemote():
        return execute(
          interaction,
          TransferRequest(kind: TransferKind.fetch, remote: request.remote),
        );
      case RepairTrackingRefs(:final references):
        final repaired = await _repositories.transfers.deleteTrackingRefs(
          session,
          references,
        );
        if (!interaction.active) return false;
        if (repaired.state != TransferExecutionState.completed) {
          interaction.reportTransfer(
            TransferFinished(request, repaired, session: session),
          );
          return false;
        }
        return execute(interaction, request, notifyResult: notifyResult);
    }
  }

  Future<TransferExecutionResult> _run(
    TransferPreview preview, {
    TransferCredentials? credentials,
  }) async {
    final running = (
      preview: preview,
      session: _repositories.activeTab?.session?.identity,
    );
    _running.add(running);
    _notify();
    try {
      return await _repositories.transfers.execute(
        preview,
        credentials: credentials,
      );
    } finally {
      _running.remove(running);
      _notify();
    }
  }

  /// The user transfer that a running Fetch, Pull or Push entry of the
  /// operation center stands for, when this window started it.
  TransferPreview? transferFor(OperationCenterEntry entry) {
    if (entry.state != OperationCenterState.running ||
        entry.origin != OperationCenterOrigin.user) {
      return null;
    }
    final kinds = switch (entry.action) {
      OperationCenterAction.fetch => const {TransferKind.fetch},
      OperationCenterAction.pull => const {TransferKind.pull},
      OperationCenterAction.push => const {
        TransferKind.push,
        TransferKind.pushTag,
        TransferKind.deleteTag,
        TransferKind.deleteBranch,
      },
      _ => const <TransferKind>{},
    };
    for (final running in _running) {
      final session = running.session;
      if (kinds.contains(running.preview.kind) &&
          session != null &&
          session.nativeId == entry.session?.nativeId &&
          session.generation == entry.session?.generation) {
        return running.preview;
      }
    }
    return null;
  }

  void _notify() {
    if (!_disposed) _runningChanges.add(null);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _runningChanges.close();
  }
}
