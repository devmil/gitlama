import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../models/reference_name.dart';
import '../../models/app_command.dart';
import '../../models/history_graph.dart';
import '../../models/remote_command_policy.dart';
import '../../models/repository_state.dart';
import '../../widgets/status_notification.dart';
import 'labels.dart';
import '../../models/git_names.dart';

/// Availability is evaluated when a menu opens and again before dispatch.
final class CommandMenuState {
  const CommandMenuState({
    this.snapshot,
    this.busy = false,
    this.canQueueStaging = false,
    this.scopes = const {AppCommandShortcutScope.global},
    this.selectedCommits = const [],
    this.disabledSelections = const {},
    this.canRetryActivity = false,
    this.canCancelActivity = false,
    this.hasActivity = false,
    this.mergeCommits = const {},
    this.isMergeCommit,
    this.hasHistoryPath = false,
    this.hasDiff = false,
    this.inspectorShown = false,
    this.canBrowseAllFiles = false,
    this.inspectorCanBack = false,
    this.inspectorCanForward = false,
    this.remote,
  });

  final RepositorySnapshot? snapshot;
  final bool busy;
  final bool canQueueStaging;
  final Set<AppCommandShortcutScope> scopes;
  final List<String> selectedCommits;
  final Set<AppCommandId> disabledSelections;
  final bool canRetryActivity;
  final bool canCancelActivity;
  final bool hasActivity;
  final Set<String> mergeCommits;

  /// Whether a loaded commit is a merge, for any target a menu names; it
  /// complements [mergeCommits].
  final bool Function(String objectId)? isMergeCommit;

  bool _merge(String objectId) =>
      mergeCommits.contains(objectId) ||
      (isMergeCommit?.call(objectId) ?? false);
  final bool hasHistoryPath;
  final bool hasDiff;

  /// The History inspector shows a commit.
  final bool inspectorShown;

  /// "Browse all files" applies to what the inspector shows.
  final bool canBrowseAllFiles;
  final bool inspectorCanBack;
  final bool inspectorCanForward;

  /// What the active tab may do on another computer; null for a local tab.
  final RemoteTabAccess? remote;

  AppCommandDisabledReason? reason(
    AppCommandId id, {
    String? reference,
    String? target,
    bool current = false,
    bool contextual = false,
  }) {
    final definition = AppCommandRegistry.byId(id);
    final basic = definition.disabledReason(
      hasRepository: snapshot != null,
      repositoryBusy:
          busy &&
          !(canQueueStaging &&
              const {
                AppCommandId.stageSelection,
                AppCommandId.unstageSelection,
                AppCommandId.stageToggle,
              }.contains(id)) &&
          !const {
            AppCommandId.activityCancel,
            AppCommandId.activityCopy,
            AppCommandId.showChanges,
            AppCommandId.showHistory,
            AppCommandId.showActivity,
            AppCommandId.showOperations,
          }.contains(id),
      // Shortcut scopes choose keyboard routing, not which workflows a menu can open.
      activeScopes: null,
    );
    if (basic != null) return basic;
    final remoteReason = remoteCommandReason(id, remote);
    if (remoteReason != null) return remoteReason;
    final status = snapshot?.status;
    final refs = snapshot?.refs;
    final head = refs?.branches.where((branch) => branch.head).firstOrNull;
    final headRef = head == null ? null : branchReference(head).fullText;
    final upstream = head?.upstream == null
        ? null
        : utf8.decode(head!.upstream!, allowMalformed: true);
    final sameBranch = current || (reference != null && reference == headRef);
    final sameCheckout =
        sameBranch || (reference != null && reference == upstream);
    final sameTarget = target != null && target == status?.headObjectId;
    final selected = target == null
        ? selectedCommits.where((id) => id != historyWorktreeObjectId).toList()
        : [target];
    final activeOperation = status?.operations.isNotEmpty ?? false;
    final sequencerOperation =
        status?.operations.any(
          (operation) => operation.kind != RepositoryOperationKind.bisect,
        ) ??
        false;
    final clean = status?.workingTree == WorkingTreeState.clean;
    final attached = status?.branchName != null || head != null;
    final conflicts = status?.entries.any((entry) => entry.conflicted) ?? false;
    final unavailable = switch (id) {
      AppCommandId.checkoutBranch =>
        sameCheckout ||
            activeOperation ||
            (refs?.branches.isEmpty == true &&
                refs?.remotes.every((remote) => remote.branches.isEmpty) ==
                    true),
      AppCommandId.autoStashCheckout =>
        sameCheckout ||
            clean ||
            activeOperation ||
            (refs?.branches.isEmpty ?? true),
      AppCommandId.deleteBranch =>
        sameBranch || activeOperation || (refs?.branches.isEmpty ?? true),
      AppCommandId.deleteRemoteBranch =>
        refs?.remotes.every(
              (remote) => remote.branches.every(
                (branch) => nameIs(branch.name, 'HEAD'),
              ),
            ) ??
            true,
      AppCommandId.integrateBranch ||
      AppCommandId.mergeBranch ||
      AppCommandId.rebaseBranch =>
        sameBranch ||
            sameTarget ||
            !clean ||
            !attached ||
            activeOperation ||
            (refs?.branches.isEmpty == true &&
                refs?.remotes.every((remote) => remote.branches.isEmpty) ==
                    true),
      AppCommandId.interactiveRebase ||
      AppCommandId.restackBranches => !clean || !attached || activeOperation,
      AppCommandId.revertSelected || AppCommandId.cherryPickSelected =>
        selected.isEmpty ||
            !clean ||
            !attached ||
            activeOperation ||
            selected.any(_merge),
      AppCommandId.historyCompare => selected.length != 2,
      AppCommandId.checkoutCommit =>
        selected.length != 1 || activeOperation || conflicts,
      AppCommandId.saveCommitArchive => selected.length != 1,
      AppCommandId.historyBlame ||
      AppCommandId.historyPathHistory ||
      AppCommandId.inspectorLensDiff ||
      AppCommandId.inspectorLensContents ||
      AppCommandId.inspectorLensBlame ||
      AppCommandId.inspectorLensHistory => !hasHistoryPath,
      AppCommandId.inspectorBack => !inspectorCanBack,
      AppCommandId.inspectorForward => !inspectorCanForward,
      AppCommandId.inspectorOpenInWindow ||
      AppCommandId.inspectorToggleMaximize ||
      AppCommandId.inspectorToggleFiles => !inspectorShown,
      AppCommandId.inspectorAllFiles => !canBrowseAllFiles,
      AppCommandId.stageToggle ||
      AppCommandId.stageSelection ||
      AppCommandId.unstageSelection ||
      AppCommandId.discardChanges => disabledSelections.contains(id),
      AppCommandId.commitCreate =>
        status == null ||
            activeOperation ||
            !(status.entries.any((entry) => entry.staged)),
      AppCommandId.commitAmend =>
        status?.headObjectId == null || activeOperation,
      AppCommandId.conflictNext ||
      AppCommandId.conflictPrevious ||
      AppCommandId.conflictTakeCurrent ||
      AppCommandId.conflictTakeIncoming ||
      AppCommandId.conflictTakeBoth ||
      AppCommandId.conflictOpenExternal => !conflicts,
      AppCommandId.rebaseContinue => !sequencerOperation || conflicts,
      AppCommandId.rebaseAbort => !sequencerOperation,
      // These verbs are available inside the plan editor, which owns its selection.
      AppCommandId.rebaseSquash ||
      AppCommandId.rebaseFixup ||
      AppCommandId.rebaseReword ||
      AppCommandId.rebaseDrop => true,
      AppCommandId.renameBranch => refs?.branches.isEmpty ?? true,
      AppCommandId.editRemote ||
      AppCommandId.renameRemote ||
      AppCommandId.removeRemote ||
      AppCommandId.remoteFetch ||
      AppCommandId.remotePush ||
      AppCommandId.fetch ||
      AppCommandId.pull ||
      AppCommandId.push ||
      AppCommandId.pushTag =>
        (refs?.remotes.isEmpty ?? true) ||
            (id == AppCommandId.pushTag && (refs?.tags.isEmpty ?? true)),
      AppCommandId.deleteTag => refs?.tags.isEmpty ?? true,
      AppCommandId.createStash => status == null || clean || activeOperation,
      AppCommandId.applyStash ||
      AppCommandId.popStash ||
      AppCommandId.renameStash ||
      AppCommandId.dropStash =>
        (refs?.stashes.isEmpty ?? true) || activeOperation,
      AppCommandId.diffToggleLayout ||
      AppCommandId.diffRenderConfigured ||
      AppCommandId.diffToggleWrap ||
      AppCommandId.diffNextHunk ||
      AppCommandId.diffPreviousHunk => !hasDiff,
      AppCommandId.activityCopy => !hasActivity,
      AppCommandId.activityRetry => !canRetryActivity,
      AppCommandId.activityCancel => !canCancelActivity,
      _ => false,
    };
    return unavailable ? AppCommandDisabledReason.contextRequired : null;
  }
}

class CommandAvailabilityScope extends InheritedWidget {
  const CommandAvailabilityScope({
    super.key,
    required this.state,
    required super.child,
  });

  final CommandMenuState Function() state;

  static CommandMenuState? read(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CommandAvailabilityScope>()
      ?.state();

  /// The current state without depending on the scope, for event handlers.
  static CommandMenuState? peek(BuildContext context) => context
      .getInheritedWidgetOfExactType<CommandAvailabilityScope>()
      ?.state();

  @override
  bool updateShouldNotify(CommandAvailabilityScope oldWidget) => true;
}

/// What mounted panes contribute to command availability. A pane registers
/// how to answer while it is mounted and withdraws on dispose; the shell
/// asks when a menu opens or a key is pressed, without reaching into pane
/// state through keys.
final class PaneCommandContext {
  Set<AppCommandId> Function()? _disabledSelections;
  bool Function()? _hasActivitySelection;
  var _diffs = 0;

  /// The selection commands the Changes pane cannot run now; all of them
  /// without a Changes pane.
  Set<AppCommandId> get disabledSelections =>
      _disabledSelections?.call() ??
      const {
        AppCommandId.stageToggle,
        AppCommandId.stageSelection,
        AppCommandId.unstageSelection,
        AppCommandId.discardChanges,
      };

  bool get hasActivitySelection => _hasActivitySelection?.call() ?? true;

  /// Whether a commit diff is shown.
  bool get hasDiff => _diffs > 0;

  void registerSelections(Set<AppCommandId> Function() answer) =>
      _disabledSelections = answer;

  void withdrawSelections(Set<AppCommandId> Function() answer) {
    if (identical(_disabledSelections, answer)) _disabledSelections = null;
  }

  void registerActivity(bool Function() answer) =>
      _hasActivitySelection = answer;

  void withdrawActivity(bool Function() answer) {
    if (identical(_hasActivitySelection, answer)) _hasActivitySelection = null;
  }

  void addDiff() => _diffs += 1;

  void removeDiff() => _diffs -= 1;

  final Map<PaneRole, PaneCommandHandler> _handlers = {};

  /// Lets the mounted pane of [role] receive commands.
  void registerHandler(PaneRole role, PaneCommandHandler handler) =>
      _handlers[role] = handler;

  void withdrawHandler(PaneRole role, PaneCommandHandler handler) {
    if (identical(_handlers[role], handler)) _handlers.remove(role);
  }

  /// The handler of the mounted pane of [role], or null.
  PaneCommandHandler? handler(PaneRole role) => _handlers[role];
}

/// Panes that receive commands from the shell.
enum PaneRole { changes, workingDiff, commitDiff, activity }

/// How a mounted pane receives commands and requests from the shell.
final class PaneCommandHandler {
  const PaneCommandHandler({
    required this.run,
    this.refresh,
    this.showPatchWorkflow,
    this.focusFind,
    this.hasFocus,
  });

  final void Function(AppCommandId command) run;

  /// Moves the keyboard focus into the pane's find field; false when the
  /// pane shows none now.
  final bool Function()? focusFind;

  /// Whether the keyboard focus is inside the pane.
  final bool Function()? hasFocus;

  /// Reloads what the pane shows.
  final void Function()? refresh;

  /// Opens the patch dialog for the pane's own selection.
  final Future<void> Function({required bool apply})? showPatchWorkflow;
}

/// Makes the shell's [PaneCommandContext] available to its panes.
class PaneCommandContextScope extends InheritedWidget {
  const PaneCommandContextScope({
    super.key,
    required this.context,
    required super.child,
  });

  final PaneCommandContext context;

  static PaneCommandContext? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PaneCommandContextScope>()?.context;

  @override
  bool updateShouldNotify(PaneCommandContextScope oldWidget) =>
      oldWidget.context != context;
}

/// Runs [command] with [run] when the shared policy allows it now, and
/// otherwise says why. Shortcuts a pane binds itself use this, so they apply
/// the same check as the shell's dispatcher.
void runAvailableCommand(
  BuildContext context,
  AppCommandId command,
  void Function() run,
) {
  final reason = CommandAvailabilityScope.peek(context)?.reason(command);
  if (reason == null) {
    run();
  } else {
    StatusNotificationScope.show(
      context,
      workspaceDisabledReason(context, reason),
    );
  }
}
