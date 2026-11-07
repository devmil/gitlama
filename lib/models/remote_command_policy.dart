import 'app_command.dart';
import 'remote_workspace.dart';

/// What the active tab may do when its repository lives on another
/// computer. A local tab has no access object.
final class RemoteTabAccess {
  const RemoteTabAccess({
    required this.profileId,
    required this.connected,
    this.capabilities = const {},
    this.writeBlock,
  });

  /// Why writes are unavailable on this side; null when they were requested,
  /// so a missing capability means the host did not offer it.
  final RemoteWriteBlock? writeBlock;

  /// The host profile the tab's authority was verified under.
  final String profileId;

  /// Whether a live connection backs the tab's state. A disconnected tab
  /// shows its last received state and grants no execution authority.
  final bool connected;

  /// What the live connection negotiated; empty while disconnected.
  final Set<RemoteCapability> capabilities;

  bool get canStage => allows(RemoteCapability.stage);

  bool get canCommit => allows(RemoteCapability.commit);

  /// Whether the live connection negotiated [capability].
  bool allows(RemoteCapability capability) =>
      connected && capabilities.contains(capability);
}

/// How a command relates to a repository on another computer.
enum RemoteCommandSupport {
  /// Works on received state and the local window alone.
  view,

  /// Reads the remote repository again; needs a live connection.
  read,

  /// Staging and unstaging; needs the negotiated stage capability.
  stage,

  /// A normal commit; needs the negotiated commit capability.
  commit,

  /// Branches, tags, upstreams, remotes and checkout; needs refs.
  refs,

  /// Stash changes; needs the negotiated stash capability.
  stash,

  /// Fetch, pull and push from the host; needs transfer.
  transfer,

  /// Irreversible discard and removal of untracked files; needs discard.
  discard,

  /// Merge, cherry-pick, revert, rebase, restack, conflict resolution and
  /// bisect; needs history.
  history,

  /// Undo, redo, snapshots, file restores, patches and index-lock removal;
  /// needs recovery.
  recovery,

  /// Worktrees, submodules and Git LFS; needs extensions.
  extensions,

  /// Not offered for repositories on another computer.
  unsupported,
}

/// The single classification of every command for remote tabs. New
/// commands must be classified here; nothing is assumed to work remotely.
RemoteCommandSupport remoteCommandSupport(AppCommandId id) => switch (id) {
  AppCommandId.openRepository ||
  AppCommandId.openRemoteRepository ||
  AppCommandId.cloneRepository ||
  AppCommandId.initializeRepository ||
  AppCommandId.closeRepositoryTab ||
  AppCommandId.showChanges ||
  AppCommandId.showHistory ||
  AppCommandId.diffToggleLayout ||
  AppCommandId.diffToggleWrap ||
  AppCommandId.diffNextHunk ||
  AppCommandId.diffPreviousHunk ||
  AppCommandId.nextPane ||
  AppCommandId.find ||
  AppCommandId.showOperations ||
  AppCommandId.showRepositoryDetails ||
  AppCommandId.showActivity ||
  AppCommandId.activityCopy ||
  AppCommandId.activityCancel ||
  AppCommandId.showCommandPalette ||
  AppCommandId.showSettings ||
  // Hosting uses received remote URLs and this computer's provider accounts.
  AppCommandId.showIntegrations ||
  AppCommandId.hostingCreatePullRequest ||
  AppCommandId.showShortcutReference ||
  AppCommandId.showLicenses ||
  AppCommandId.reportIssue ||
  AppCommandId.historyCompare ||
  AppCommandId.historyBlame ||
  AppCommandId.historyPathHistory ||
  AppCommandId.inspectorBack ||
  AppCommandId.inspectorForward ||
  AppCommandId.inspectorLensDiff ||
  AppCommandId.inspectorLensContents ||
  AppCommandId.inspectorLensBlame ||
  AppCommandId.inspectorLensHistory ||
  AppCommandId.inspectorToggleMaximize ||
  AppCommandId.inspectorToggleFiles ||
  AppCommandId.inspectorAllFiles => RemoteCommandSupport.view,
  // A patch is built on the host and saved on this computer; applying one
  // stays local-only.
  // The host reads the diff or file versions; the renderer or diff tool
  // runs on this computer.
  AppCommandId.diffRenderConfigured ||
  // An inspector window reads through this window's connection.
  AppCommandId.inspectorOpenInWindow ||
  AppCommandId.refreshRepository ||
  AppCommandId.patch ||
  AppCommandId.createPatch => RemoteCommandSupport.read,
  // The host builds the snapshot; this computer saves it.
  AppCommandId.saveCommitArchive => RemoteCommandSupport.read,
  AppCommandId.stageToggle ||
  AppCommandId.stageSelection ||
  AppCommandId.unstageSelection => RemoteCommandSupport.stage,
  AppCommandId.commitCreate => RemoteCommandSupport.commit,
  AppCommandId.createBranch ||
  AppCommandId.renameBranch ||
  AppCommandId.deleteBranch ||
  AppCommandId.checkoutCommit ||
  AppCommandId.checkoutBranch ||
  AppCommandId.addRemote ||
  AppCommandId.editRemote ||
  AppCommandId.renameRemote ||
  AppCommandId.removeRemote ||
  AppCommandId.createTag ||
  AppCommandId.deleteTag => RemoteCommandSupport.refs,
  AppCommandId.createStash ||
  AppCommandId.applyStash ||
  AppCommandId.popStash ||
  AppCommandId.renameStash ||
  AppCommandId.dropStash ||
  AppCommandId.autoStashCheckout => RemoteCommandSupport.stash,
  AppCommandId.remoteFetch ||
  AppCommandId.remotePush ||
  AppCommandId.deleteRemoteBranch ||
  AppCommandId.pushTag ||
  AppCommandId.fetch ||
  AppCommandId.pull ||
  AppCommandId.push => RemoteCommandSupport.transfer,
  AppCommandId.discardChanges => RemoteCommandSupport.discard,
  // Amend, skipped hooks and disabled signing are the user's choice, as on
  // this computer.
  AppCommandId.commitAmend => RemoteCommandSupport.commit,
  AppCommandId.resetBranch => RemoteCommandSupport.refs,
  // The panels read the host; their actions check their own families.
  AppCommandId.conflictNext ||
  AppCommandId.conflictPrevious ||
  AppCommandId.showSnapshots ||
  AppCommandId.showPowerTools => RemoteCommandSupport.read,
  AppCommandId.conflictTakeCurrent ||
  AppCommandId.conflictTakeIncoming ||
  AppCommandId.conflictTakeBoth ||
  AppCommandId.rebaseContinue ||
  AppCommandId.rebaseAbort ||
  AppCommandId.rebaseSquash ||
  AppCommandId.rebaseFixup ||
  AppCommandId.rebaseReword ||
  AppCommandId.rebaseDrop ||
  AppCommandId.integrateBranch ||
  AppCommandId.mergeBranch ||
  AppCommandId.rebaseBranch ||
  AppCommandId.interactiveRebase ||
  AppCommandId.restackBranches ||
  AppCommandId.cherryPickSelected ||
  AppCommandId.revertSelected => RemoteCommandSupport.history,
  // A patch file on this computer is applied on the host.
  AppCommandId.applyPatch ||
  AppCommandId.inspectIndexLock => RemoteCommandSupport.recovery,
  AppCommandId.addWorktree ||
  AppCommandId.trackLfsPattern => RemoteCommandSupport.extensions,
  // A retry of an operation is never offered remotely: an uncertain remote
  // write must be inspected, not resent.
  AppCommandId.activityRetry ||
  // Local tools work on this computer's files and
  // cannot reach a repository on another computer.
  AppCommandId.conflictOpenExternal ||
  AppCommandId.openInEditor ||
  AppCommandId.openInTerminal ||
  AppCommandId.openInFileManager ||
  AppCommandId.addIntegration => RemoteCommandSupport.unsupported,
};

/// Why [id] is unavailable for a tab with [access], or null when it may run.
/// A local tab ([access] null) is never restricted here.
AppCommandDisabledReason? remoteCommandReason(
  AppCommandId id,
  RemoteTabAccess? access,
) {
  if (access == null) return null;
  return switch (remoteCommandSupport(id)) {
    RemoteCommandSupport.view => null,
    RemoteCommandSupport.read =>
      access.connected ? null : AppCommandDisabledReason.remoteDisconnected,
    RemoteCommandSupport.stage => _writeReason(access, RemoteCapability.stage),
    RemoteCommandSupport.commit => _writeReason(
      access,
      RemoteCapability.commit,
    ),
    RemoteCommandSupport.refs => _writeReason(access, RemoteCapability.refs),
    RemoteCommandSupport.stash => _writeReason(access, RemoteCapability.stash),
    RemoteCommandSupport.transfer => _writeReason(
      access,
      RemoteCapability.transfer,
    ),
    RemoteCommandSupport.discard => _writeReason(
      access,
      RemoteCapability.discard,
    ),
    RemoteCommandSupport.history => _writeReason(
      access,
      RemoteCapability.history,
    ),
    RemoteCommandSupport.recovery => _writeReason(
      access,
      RemoteCapability.recovery,
    ),
    RemoteCommandSupport.extensions => _writeReason(
      access,
      RemoteCapability.extensions,
    ),
    RemoteCommandSupport.unsupported =>
      AppCommandDisabledReason.remoteUnsupported,
  };
}

/// Why a tab with [access] may not make [capability] writes, or null when
/// it may. A local tab ([access] null) is never restricted here.
AppCommandDisabledReason? remoteCapabilityReason(
  RemoteTabAccess? access,
  RemoteCapability capability,
) => access == null ? null : _writeReason(access, capability);

AppCommandDisabledReason? _writeReason(
  RemoteTabAccess access,
  RemoteCapability capability,
) => !access.connected
    ? AppCommandDisabledReason.remoteDisconnected
    : access.allows(capability)
    ? null
    : switch (access.writeBlock) {
        RemoteWriteBlock.notAllowed => AppCommandDisabledReason.remoteWritesOff,
        RemoteWriteBlock.reconnect =>
          AppCommandDisabledReason.remoteWritesReconnect,
        RemoteWriteBlock.ledgerUnavailable =>
          AppCommandDisabledReason.remoteWritesLedger,
        null => AppCommandDisabledReason.remoteWritesUnavailable,
      };
