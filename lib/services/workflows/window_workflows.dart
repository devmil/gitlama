import '../../models/host_platform.dart';
import 'dart:async';

import '../cli_forwarding_service.dart';
import '../inspector_reveal_service.dart';
import '../operation_center_service.dart';
import '../remote_workspace_workflows.dart';
import '../repository_session_service.dart';
import 'changes_service.dart';
import 'commit_workflow.dart';
import 'entry_workflows.dart';
import 'conflict_resolution.dart';
import 'history_rewrite_workflows.dart';
import 'index_lock_workflow.dart';
import 'integration_launcher.dart';
import 'operation_center_actions.dart';
import 'ref_workflows.dart';
import 'repository_busy.dart';
import 'sync_change_tracker.dart';
import 'transfer_workflows.dart';
import 'workspace_effects.dart';
import 'workspace_navigator.dart';

/// The workflows of one window. The window creates them with its remote
/// workflows, shows their questions as dialogs and disposes them with
/// itself; nothing outside the window shares them.
final class WindowWorkflows {
  factory WindowWorkflows({
    required RepositorySessionService repositories,
    required OperationCenterService operationCenter,
    RemoteWorkspaceWorkflows? remote,
    required HostPlatform platform,
    CliForwardingController cli = const DisabledCliForwardingController(),
    InspectorRevealService? inspectorReveal,
  }) {
    final busy = RepositoryBusyService();
    final navigator = WorkspaceNavigator(repositories);
    final sync = SyncChangeTracker(repositories);
    final transfers = TransferWorkflowService(repositories, sync);
    final effects = WorkspaceEffects(repositories);
    // Inspector windows reveal commits in this window's History.
    if (inspectorReveal != null) {
      unawaited(
        inspectorReveal.listen(navigator.revealFromInspectorWindow).catchError((
          Object _,
        ) {
          // Windows still inspect; only their way back is unavailable.
        }),
      );
    }
    return WindowWorkflows._(
      repositories: repositories,
      busy: busy,
      navigator: navigator,
      sync: sync,
      transfers: transfers,
      refs: RefWorkflowService(repositories, transfers),
      history: HistoryRewriteWorkflowService(repositories, busy, navigator),
      integrations: IntegrationLauncher(repositories, remote, platform),
      indexLock: IndexLockWorkflow(repositories),
      conflicts: ConflictResolutionService(repositories),
      changes: ChangesService(repositories, busy, navigator, remote),
      commits: CommitWorkflow(repositories, effects),
      effects: effects,
      entry: EntryWorkflowService(repositories, cli),
      operations: OperationCenterActions(
        repositories,
        operationCenter,
        transfers,
      ),
    );
  }

  WindowWorkflows._({
    required this.repositories,
    required this.busy,
    required this.navigator,
    required this.sync,
    required this.transfers,
    required this.refs,
    required this.history,
    required this.integrations,
    required this.indexLock,
    required this.conflicts,
    required this.changes,
    required this.commits,
    required this.entry,
    required this.effects,
    required this.operations,
  });

  final RepositorySessionService repositories;

  /// Which tabs are busy and with what.
  final RepositoryBusyService busy;
  final WorkspaceNavigator navigator;
  final SyncChangeTracker sync;
  final TransferWorkflowService transfers;
  final RefWorkflowService refs;
  final HistoryRewriteWorkflowService history;
  final IntegrationLauncher integrations;
  final IndexLockWorkflow indexLock;

  /// The conflict resolution of each open repository, with its drafts.
  final ConflictResolutionService conflicts;

  /// The Changes pane's selection, staging, discard and conflict flow.
  final ChangesService changes;

  /// The Composer's commit with its confirmations and retries.
  final CommitWorkflow commits;

  /// Opening, cloning and creating repositories, and forwarded commands.
  final EntryWorkflowService entry;

  /// The window's one channel for reveal, flash and focus requests.
  final WorkspaceEffects effects;
  final OperationCenterActions operations;

  Future<void> dispose() async {
    await navigator.dispose();
    await entry.dispose();
    await effects.dispose();
    await changes.dispose();
    await conflicts.dispose();
    await sync.dispose();
    await transfers.dispose();
    await busy.dispose();
  }
}
