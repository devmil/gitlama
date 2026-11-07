import 'package:gitlama/models/clone_attempt.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/advanced_rebase.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/services/workflows/history_rewrite_workflows.dart';
import 'package:gitlama/services/workflows/index_lock_workflow.dart';
import 'package:gitlama/services/workflows/integration_launcher.dart';
import 'package:gitlama/services/workflows/ref_workflows.dart';
import 'package:gitlama/services/workflows/transfer_workflows.dart';

/// Answers every workflow question from scripted values and records what
/// was asked and reported, in order.
final class RecordingInteraction
    implements
        RefInteraction,
        HistoryRewriteInteraction,
        IntegrationInteraction,
        IndexLockInteraction {
  CommitCheckoutChoice? checkoutChoice;
  CommitCheckoutReview? lastCheckoutReview;
  @override
  Future<CommitCheckoutChoice?> confirmCommitCheckout(
    CommitCheckoutReview review,
  ) async {
    lastCheckoutReview = review;
    return _ask('confirmCommitCheckout', checkoutChoice);
  }

  @override
  bool active = true;

  /// Every question and report, by name, in order.
  final List<String> log = [];
  final List<Object> outcomes = [];

  TransferRequest? Function(TransferDraft draft)? transfer;
  TransferDraft? lastTransferDraft;
  bool trustHost = true;
  TransferCredentials? credentials;
  bool refetch = true;
  TransferRemedy? remedy;
  TransferFailureReport? lastFailureReport;
  RefMutationRequest? Function(RefMutationDraft draft)? refMutation;
  RefMutationDraft? lastRefDraft;
  EditBranchResult? edit;
  bool confirmRef = true;
  bool recoverTarget = false;
  StashRequest? Function(StashDraft draft)? stash;
  StashDraft? lastStashDraft;
  bool confirmStashAnswer = true;
  HistoryMutationRequest? Function(HistoryMutationDraft draft)? mutation;
  HistoryMutationDraft? lastMutationDraft;
  bool confirmMutation = true;
  ConflictPredictionResult? lastPrediction;
  BranchIntegration? integration;
  RepositoryReference? rebaseTarget;
  RebaseEditResult? rebaseEdit;
  bool confirmRebaseAnswer = true;
  RepositoryReference? restackRoot;
  bool? restackReview = false;
  bool confirmIntegrationAnswer = true;
  bool removeLock = true;

  /// Runs when a question is asked, for tests that change state meanwhile.
  void Function(String question)? onAsk;

  T _ask<T>(String question, T answer) {
    log.add(question);
    onAsk?.call(question);
    return answer;
  }

  void _report(String name, Object outcome) {
    log.add(name);
    outcomes.add(outcome);
  }

  @override
  Future<TransferRequest?> chooseTransfer(TransferDraft draft) async {
    lastTransferDraft = draft;
    return _ask('chooseTransfer', transfer?.call(draft));
  }

  @override
  Future<bool> trustHostKey(HostKeyChallenge challenge) async =>
      _ask('trustHostKey', trustHost);

  @override
  Future<TransferCredentials?> transferCredentials(String remote) async =>
      _ask('credentials:$remote', credentials);

  @override
  Future<bool> offerRefetch(String remote) async =>
      _ask('offerRefetch:$remote', refetch);

  @override
  Future<TransferRemedy?> resolveTransferFailure(
    TransferFailureReport report,
  ) async {
    lastFailureReport = report;
    final answer = remedy;
    // A remedy is chosen once; the retried transfer is left alone.
    remedy = null;
    return _ask('resolveTransferFailure', answer);
  }

  @override
  void reportTransfer(TransferOutcome outcome) =>
      _report('transfer:${outcome.runtimeType}', outcome);

  @override
  Future<RefMutationRequest?> chooseRefMutation(RefMutationDraft draft) async {
    lastRefDraft = draft;
    return _ask('chooseRef:${draft.kind.name}', refMutation?.call(draft));
  }

  @override
  Future<bool> recoverRefTarget() async =>
      _ask('recoverRefTarget', recoverTarget);

  @override
  Future<EditBranchResult?> editBranch(
    String branch,
    RepositoryRefs refs,
  ) async => _ask('editBranch:$branch', edit);

  @override
  Future<bool> confirmRefMutation(
    RefMutationRequest request,
    RefMutationPreview preview, {
    String? localTagObjectId,
  }) async => _ask(
    'confirmRef:${request.kind.name}${localTagObjectId == null ? '' : ':$localTagObjectId'}',
    confirmRef,
  );

  @override
  void reportRef(RefOutcome outcome) =>
      _report('ref:${outcome.runtimeType}', outcome);

  @override
  Future<StashRequest?> chooseStash(StashDraft draft) async {
    lastStashDraft = draft;
    return _ask('chooseStash', stash?.call(draft));
  }

  @override
  Future<bool> confirmStash(StashPreview preview) async =>
      _ask('confirmStash', confirmStashAnswer);

  @override
  Future<HistoryMutationRequest?> chooseHistoryMutation(
    HistoryMutationDraft draft,
  ) async {
    lastMutationDraft = draft;
    return _ask('chooseMutation', mutation?.call(draft));
  }

  @override
  Future<bool> confirmHistoryMutation(
    HistoryMutationPreview preview,
    ConflictPredictionResult? prediction,
  ) async {
    lastPrediction = prediction;
    return _ask('confirmMutation', confirmMutation);
  }

  @override
  Future<BranchIntegration?> chooseBranchIntegration(
    String? sourceName,
  ) async => _ask('chooseIntegration', integration);

  @override
  Future<RepositoryReference?> chooseRebaseTarget(
    List<RepositoryReference> branches,
  ) async => _ask('chooseRebaseTarget', rebaseTarget);

  @override
  Future<RebaseEditResult?> editRebase(
    RebasePlan plan,
    ConflictPredictionResult? prediction,
  ) async {
    lastPrediction = prediction;
    return _ask('editRebase', rebaseEdit);
  }

  @override
  Future<bool> confirmRebase(RebasePreview preview) async =>
      _ask('confirmRebase', confirmRebaseAnswer);

  @override
  Future<RepositoryReference?> chooseRestackRoot(
    List<RepositoryReference> branches,
  ) async => _ask('chooseRestackRoot', restackRoot);

  @override
  Future<bool?> reviewRestack(RestackPlan plan) async =>
      _ask('reviewRestack', restackReview);

  @override
  void reportHistoryRewrite(HistoryRewriteOutcome outcome) =>
      _report('history:${outcome.runtimeType}', outcome);

  @override
  Future<bool> confirmIntegration(IntegrationPreview preview) async =>
      _ask('confirmIntegration', confirmIntegrationAnswer);

  @override
  void reportIntegration(IntegrationOutcome outcome) =>
      _report('integration:${outcome.runtimeType}', outcome);

  @override
  Future<bool> confirmIndexLockRemoval(int sizeBytes) async =>
      _ask('confirmIndexLock:$sizeBytes', removeLock);

  @override
  void reportIndexLock(IndexLockOutcome outcome) =>
      _report('indexLock:${outcome.runtimeType}', outcome);
}
