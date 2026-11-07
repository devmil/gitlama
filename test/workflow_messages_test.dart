import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/labels.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/services/workflows/history_rewrite_workflows.dart';
import 'package:gitlama/services/workflows/integration_launcher.dart';
import 'package:gitlama/services/workflows/ref_workflows.dart';
import 'package:gitlama/services/workflows/repository_busy.dart';
import 'package:gitlama/services/workflows/transfer_workflows.dart';
import 'package:gitlama/services/workflows/workflow.dart';

void main() {
  testWidgets('each outcome type maps to one message and tone', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (built) {
            context = built;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final l10n = AppLocalizations.of(context);

    // A local failure after the remote tag went says so, as a failure.
    expect(
      refOutcomeMessage(
        context,
        const RefMutationFinished(
          RefMutationExecutionState.failed,
          remoteTagDeleted: true,
        ),
      ),
      (text: l10n.deleteTagLocalFailedAfterRemote, error: true),
    );
    expect(
      refOutcomeMessage(
        context,
        const RefMutationFinished(RefMutationExecutionState.completed),
      ),
      (text: l10n.refMutationCompleted, error: false),
    );
    expect(
      refOutcomeMessage(context, const UpstreamDeleteFailed('origin/topic')),
      (text: l10n.deleteBranchUpstreamFailed('origin/topic'), error: false),
    );
    // Every workflow reports an unknown remote outcome alike.
    for (final message in [
      refOutcomeMessage(
        context,
        const RefWorkflowFailed(OutcomeUnknownFailure()),
      ),
      transferOutcomeMessage(
        context,
        const TransferWorkflowFailed(OutcomeUnknownFailure()),
      ),
      historyRewriteOutcomeMessage(
        context,
        const HistoryRewriteFailed(
          HistoryRewriteKind.rebase,
          OutcomeUnknownFailure(),
        ),
      ),
    ]) {
      expect(message, (text: l10n.remoteOutcomeUnknownChange, error: true));
    }
    expect(
      transferOutcomeMessage(
        context,
        const TransferWorkflowFailed(
          RemoteConnectionFailure(RemoteFailureCode.disconnected),
        ),
      ).text,
      l10n.remoteFailureDisconnected,
    );
    expect(
      transferOutcomeMessage(
        context,
        const RemoteTransferNeedsHost(TransferFailureCode.authentication),
      ),
      (text: l10n.remoteTransferAuthentication, error: true),
    );
    expect(
      historyRewriteOutcomeMessage(
        context,
        const HistoryRewriteFailed(
          HistoryRewriteKind.stash,
          SessionFailure(RepositoryFailureCode.canceled),
        ),
      ),
      (
        text: l10n.operationFailureWithReason(
          l10n.stashFailed,
          l10n.operationFailureCanceled,
        ),
        error: true,
      ),
    );
    expect(historyRewriteOutcomeMessage(context, const RestackNothingToDo()), (
      text: l10n.restackNothingToDo,
      error: false,
    ));
    expect(
      integrationOutcomeMessage(context, const IntegrationLaunchFailed()),
      (text: l10n.integrationLaunchFailed, error: true),
    );
    expect(
      busyActivityLabel(context, const StashBusy(StashKind.push)),
      stashBusyLabel(context, StashKind.push),
    );
    expect(
      busyActivityLabel(
        context,
        RebaseBusy(currentBranch: 'main'.codeUnits, onto: 'topic'.codeUnits),
      ),
      l10n.rebaseBusy('main', 'topic'),
    );
  });
}
