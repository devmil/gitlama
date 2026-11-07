// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get workflowExit => 'Exit';

  @override
  String get conflictUnknownProvenance => 'Last change unknown';

  @override
  String get patchShowInFolder => 'Show in folder';

  @override
  String get referencePickerTitle => 'Select reference';

  @override
  String get referencePickerSearch => 'Search by name, commit ID, or subject';

  @override
  String get referencePickerEmpty => 'No matching references';

  @override
  String get referencePickerHistoryHint =>
      'Search branches, tags, and loaded commits, or enter a revision.';

  @override
  String get sidebarCopyName => 'Copy name';

  @override
  String get sidebarCurrentBranch => 'Current branch';

  @override
  String get appTitle => 'GitLama';

  @override
  String get commandReportIssue => 'Report an issue…';

  @override
  String get reportIssueOpenFailed => 'The issue tracker could not be opened.';

  @override
  String get licensesTitle => 'Licenses';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsGit => 'Git';

  @override
  String get settingsIntegrations => 'Hosting accounts';

  @override
  String get settingsRepositoryBinding => 'Repository link';

  @override
  String get settingsCustomCommands => 'Tools and commands';

  @override
  String get settingsDiffRenderer => 'Diff renderer';

  @override
  String get settingsShortcuts => 'Shortcuts';

  @override
  String get settingsAccessibility => 'Accessibility';

  @override
  String get settingsAppearanceDetail =>
      'Appearance changes apply immediately and are saved automatically.';

  @override
  String get settingsGitDetail =>
      'Choose how repositories are fetched, and manage settings of the active repository.';

  @override
  String get settingsAutoFetch => 'Fetch automatically';

  @override
  String get settingsAutoFetchInterval => 'Fetch interval';

  @override
  String get settingsAutoFetchHint =>
      'Open repositories fetch their remote in the background. Nothing is merged or pulled, and a fetch that needs a sign-in is skipped.';

  @override
  String get settingsRepositoryAutoFetch =>
      'Fetch this repository automatically';

  @override
  String get settingsFollowApplication => 'Same as application';

  @override
  String get settingsOn => 'On';

  @override
  String get settingsOff => 'Off';

  @override
  String settingsAutoFetchMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get settingsIntegrationsDetail =>
      'Add and manage connections to Git hosting providers.';

  @override
  String get settingsRepositoryBindingDetail =>
      'Choose which hosting account and remote belong to this repository.';

  @override
  String get settingsCustomCommandsDetail =>
      'Use discovered tools or add a command. GitLama validates saved commands and previews each run.';

  @override
  String get settingsDiffRendererDetail =>
      'Configure and validate an external diff renderer.';

  @override
  String get settingsShortcutsDetail =>
      'Select a shortcut and press the new key combination; Escape cancels. Remove a shortcut to leave the command unbound. Conflicting and reserved shortcuts are rejected.';

  @override
  String get settingsShortcutRecording => 'Press a key combination…';

  @override
  String get settingsShortcutClear => 'Remove shortcut';

  @override
  String get settingsShortcutUnbound => 'Unbound';

  @override
  String get settingsShortcutReset => 'Reset shortcut defaults';

  @override
  String get settingsShortcutInvalid =>
      'Use Ctrl, Cmd, Alt or Shift with a letter, digit, function, arrow or Enter key.';

  @override
  String get settingsShortcutReserved =>
      'That shortcut is reserved by the operating system.';

  @override
  String get settingsShortcutConflict =>
      'That shortcut is already assigned to another command.';

  @override
  String get settingsAccessibilityDetail =>
      'Choose how GitLama follows system motion preferences.';

  @override
  String get settingsLicensesDetail =>
      'Review GitLama\'s license and the notices for bundled dependencies.';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsFollowSystem => 'Follow system';

  @override
  String get settingsDensity => 'Density';

  @override
  String get settingsDensityCompact => 'Compact';

  @override
  String get settingsDensityRegular => 'Regular';

  @override
  String get settingsDensityComfortable => 'Comfortable';

  @override
  String get settingsDateFormat => 'Date format';

  @override
  String get settingsAvatars => 'Author images';

  @override
  String get settingsAvatarsInitials => 'Initials only';

  @override
  String get settingsAvatarsGravatar => 'Use Gravatar';

  @override
  String get avatarGravatarTitle => 'Author images';

  @override
  String get avatarGravatarHint =>
      'Gravatar can show author images. Enabling it sends a hash of each visible author\'s email address to Gravatar. Images are cached for one day.';

  @override
  String get avatarGravatarTooltip => 'Show Gravatar option';

  @override
  String get avatarEnableGravatar => 'Enable Gravatar';

  @override
  String get avatarGravatarNotNow => 'Not now';

  @override
  String get settingsDateRelative => 'Relative';

  @override
  String get settingsDateLocal => 'Local';

  @override
  String get settingsDateIso => 'ISO 8601';

  @override
  String get historyDateNow => 'now';

  @override
  String historyDateMinutes(int count) {
    return '${count}m';
  }

  @override
  String historyDateHours(int count) {
    return '${count}h';
  }

  @override
  String historyDateDays(int count) {
    return '${count}d';
  }

  @override
  String get settingsMotion => 'Motion';

  @override
  String get settingsMotionReduce => 'Reduce motion';

  @override
  String get settingsMotionFull => 'Full motion';

  @override
  String settingsActiveRepository(String name) {
    return 'Active repository: $name';
  }

  @override
  String get settingsNoActiveRepository =>
      'Open a repository to manage repository settings.';

  @override
  String get settingsResetRepositoryAction => 'Reset repository settings';

  @override
  String get settingsResetRepositoryTitle => 'Reset repository settings?';

  @override
  String settingsResetRepositoryConfirmation(String name) {
    return 'Reset the saved view, navigation, filters, and draft for “$name”? Other repositories and global settings are not changed.';
  }

  @override
  String get settingsSaveFailed =>
      'The settings could not be saved. Nothing was reported as complete.';

  @override
  String get settingsOpenLicenses => 'Open licenses';

  @override
  String get shortcutSearch => 'Search shortcuts';

  @override
  String get shortcutConflictTitle => 'Context-dependent shortcuts';

  @override
  String shortcutConflictDetail(String shortcut, String commands) {
    return '$shortcut: $commands';
  }

  @override
  String get shortcutConflictWinner =>
      'Each key runs the command of the focused sidebar section.';

  @override
  String get commandGroupCommands => 'Workspace';

  @override
  String get commandGroupRepository => 'Repository';

  @override
  String get commandGroupSettings => 'Settings';

  @override
  String get startupLoading => 'Starting…';

  @override
  String get startupFailed => 'The app could not start.';

  @override
  String get retry => 'Try again';

  @override
  String get welcomeTitle => 'Start with a repository';

  @override
  String get welcomeDetail =>
      'Open an existing Git repository or initialize an empty destination.';

  @override
  String get welcomeOpen => 'Open…';

  @override
  String get welcomeClone => 'Clone…';

  @override
  String get welcomeCreate => 'Create…';

  @override
  String get openRepository => 'Open repository';

  @override
  String get cloneRepository => 'Clone repository';

  @override
  String get cloneSourceLabel => 'Repository URL or path';

  @override
  String get cloneSourceDescription =>
      'Copy a repository from a server or another folder. You choose where to put it in the next step.';

  @override
  String get cloneSourceHint => 'https://example.com/team/project.git';

  @override
  String get chooseCloneDestination => 'Choose destination';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelClone => 'Cancel clone';

  @override
  String get cloneInvalidSource =>
      'Enter a supported repository URL or absolute local path.';

  @override
  String get cloneEmbeddedCredential =>
      'Remove the password or token from the repository URL.';

  @override
  String get cloneInvalidDestination => 'Choose a valid destination directory.';

  @override
  String get cloneDestinationOccupied =>
      'The destination is not empty and was not changed.';

  @override
  String get cloneAuthenticationRequired => 'Authentication is required.';

  @override
  String get cloneCredentialBrokerUnavailable =>
      'Secure credential retry is unavailable on this platform.';

  @override
  String get clonePasswordOrToken => 'Password or token';

  @override
  String get retryAuthentication => 'Retry authentication';

  @override
  String get cloneHostKeyUntrusted => 'The SSH host key is not trusted.';

  @override
  String get inspectHostKey => 'Inspect host key';

  @override
  String get hostKeyTitle => 'Verify SSH host key';

  @override
  String get hostKeyDescription =>
      'Check that this is the server you expect. Trust it only if the fingerprint matches the one its administrator or hosting service publishes.';

  @override
  String get hostKeyServer => 'Server';

  @override
  String get hostKeyType => 'Key type';

  @override
  String get hostKeyFingerprint => 'Fingerprint';

  @override
  String get rejectHostKey => 'Reject';

  @override
  String get trustHostKey => 'Trust and retry';

  @override
  String get hostKeyProbeFailed => 'The SSH host key could not be inspected.';

  @override
  String get hostKeyChallengeExpired =>
      'The SSH host-key challenge is no longer current.';

  @override
  String get hostKeyWriteFailed =>
      'The trusted-host file could not be updated safely.';

  @override
  String get cloneTimedOut =>
      'The clone stopped after Git became unresponsive.';

  @override
  String get cloneCanceled =>
      'The clone was canceled. Any partial destination was left untouched.';

  @override
  String get cloneFailed => 'The repository could not be cloned.';

  @override
  String get initializeRepository => 'Initialize repository';

  @override
  String get initializeBareRepository => 'Initialize bare repository';

  @override
  String get initializeBareOption => 'Bare repository';

  @override
  String get initializeBareHelp =>
      'Holds only the history, without working files. Use it as a shared repository on a server.';

  @override
  String get initializeDestinationHint =>
      'Create an empty Git repository. You choose its folder in the next step.';

  @override
  String get repositoryReady => 'Repository ready';

  @override
  String get repositoryReadyDetail =>
      'The canonical repository identity and initial Git state are loaded.';

  @override
  String get recentRepositories => 'Recent repositories';

  @override
  String get noRecentRepositories => 'No successfully opened repositories yet.';

  @override
  String get recentRepositoriesFilter => 'Filter recent repositories';

  @override
  String get recentRepositoriesNoMatch =>
      'No recent repository matches the filter.';

  @override
  String get repositoryOpenFailed => 'The repository could not be opened.';

  @override
  String get repositoryPathNotFound => 'The selected path no longer exists.';

  @override
  String get repositoryPermissionDenied =>
      'GitLama does not have permission to read the selected path.';

  @override
  String get repositoryNotRepository =>
      'The selected path is not inside a Git repository.';

  @override
  String get repositoryAlreadyExists =>
      'That destination is already a Git repository.';

  @override
  String get destinationNotEmpty =>
      'The destination is not empty and was not changed.';

  @override
  String get destinationNotDirectory =>
      'The destination is not a supported directory.';

  @override
  String get gitUnavailable => 'Installed Git is unavailable.';

  @override
  String get gitUnsupported => 'The installed Git version is not supported.';

  @override
  String get workspaceChanges => 'Changes';

  @override
  String get workspaceHistory => 'History';

  @override
  String get workspaceActivity => 'Activity';

  @override
  String get activityCopy => 'Copy activity';

  @override
  String get activityCopied => 'Activity command and output copied.';

  @override
  String get toolbarBranch => 'Branch';

  @override
  String get toolbarMore => 'More';

  @override
  String get workspaceRefresh => 'Refresh';

  @override
  String get workspaceRefreshLocal => 'Refresh local view';

  @override
  String get workspaceRefreshLocalHint =>
      'Reload this repository from disk. Fetch gets new commits from remotes; Pull also updates your branch.';

  @override
  String get workspaceRefreshFailed => 'Repository refresh failed.';

  @override
  String get workspaceBranches => 'Branches';

  @override
  String get workspaceRemotes => 'Remotes';

  @override
  String get workspaceStashes => 'Stashes';

  @override
  String get workspaceTags => 'Tags';

  @override
  String get workspaceWorktrees => 'Worktrees';

  @override
  String get workspaceDetail => 'Details';

  @override
  String get workspaceEmptyHistory => 'No commits found.';

  @override
  String get historyNoCommitsYet => 'No commits yet';

  @override
  String get historyOpenChanges => 'Open Changes';

  @override
  String get historyRetryLoad => 'Retry loading history';

  @override
  String historyEndOfHistory(int count) {
    return 'End of history · $count commits';
  }

  @override
  String historyNewUpstreamCommits(int count, String ref) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new commits on $ref',
      one: '1 new commit on $ref',
    );
    return '$_temp0';
  }

  @override
  String get workspaceNoSelection => 'Select an item to inspect it.';

  @override
  String get workingDiffFailed => 'The file diff could not be loaded.';

  @override
  String statusAccelerationOffer(int seconds) {
    return 'Git took $seconds s to check this repository for changes. Turning on Git\'s untracked cache and file system monitor in this repository\'s settings makes these checks much faster.';
  }

  @override
  String statusAccelerationOfferCacheOnly(int seconds) {
    return 'Git took $seconds s to check this repository for changes. Turning on Git\'s untracked cache in this repository\'s settings makes these checks faster.';
  }

  @override
  String get statusAccelerationEnable => 'Speed up';

  @override
  String get statusAccelerationDismiss => 'Not now';

  @override
  String get statusAccelerationFailed =>
      'Git could not change this repository\'s settings.';

  @override
  String get workingDiffWaitingForGit => 'Waiting for Git…';

  @override
  String get workingDiffWaitingForGitDetail =>
      'Git is still working on this repository, for example scanning a large worktree. The diff appears when Git answers.';

  @override
  String get workingDiffEmpty => 'This file has no line changes to show.';

  @override
  String get workspaceLoadingRepository => 'Opening repository…';

  @override
  String get workspaceUnavailableRepository =>
      'This repository is unavailable.';

  @override
  String workspaceCloseTab(String name) {
    return 'Close $name';
  }

  @override
  String get workspaceOpenAnother => 'Open another repository';

  @override
  String get workspaceStatusReady => 'Repository ready';

  @override
  String get workspaceStatusLoading => 'Loading repository';

  @override
  String get workspaceStatusFailed => 'Repository unavailable';

  @override
  String get workspaceWorkingTreeClean => 'Clean';

  @override
  String get workspaceWorkingTreeDirty => 'Changes';

  @override
  String get workspaceWorkingTreeConflicted => 'Conflicts';

  @override
  String get workspaceWatchOverflow =>
      'Repository changes arrived faster than they could be displayed. Resynchronizing…';

  @override
  String get workspaceWatchFailure =>
      'Automatic repository updates are unavailable. Use Refresh to update the view.';

  @override
  String get workspaceStatusFailure =>
      'Working-tree status could not be read. Other repository data remains available.';

  @override
  String get workspaceRefsFailure =>
      'Branches and other references could not be read. Other repository data remains available.';

  @override
  String get workspaceDetachedHead =>
      'No branch is checked out. New commits will not belong to a branch until you create or switch to one.';

  @override
  String workspaceConflictCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files have conflicts.',
      one: '1 file has conflicts.',
    );
    return '$_temp0';
  }

  @override
  String get workspaceOperationMerge => 'Merge in progress';

  @override
  String get workspaceOperationRebase => 'Rebase in progress';

  @override
  String get workspaceOperationCherryPick => 'Cherry-pick in progress';

  @override
  String get workspaceOperationRevert => 'Revert in progress';

  @override
  String get workspaceOperationBisect => 'Bisect in progress';

  @override
  String logbookRepeatedFetch(int count) {
    return 'Fetched origin ×$count';
  }

  @override
  String logbookDurationSeconds(String seconds) {
    return '$seconds s';
  }

  @override
  String get close => 'Close';

  @override
  String operationsRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running',
      one: '1 running',
    );
    return '$_temp0';
  }

  @override
  String operationsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count failed',
      one: '1 failed',
    );
    return '$_temp0';
  }

  @override
  String operationsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need attention',
      one: '1 needs attention',
    );
    return '$_temp0';
  }

  @override
  String get operationsFilterAll => 'All';

  @override
  String get operationsFilterUser => 'User';

  @override
  String get operationsFilterBackground => 'Background';

  @override
  String get operationsDismiss => 'Dismiss';

  @override
  String get operationsDismissAll => 'Dismiss all';

  @override
  String get operationsDetails => 'Details';

  @override
  String get operationsEmpty => 'No matching operations';

  @override
  String get operationsDetailsUnavailable =>
      'No command details are available for this operation.';

  @override
  String get operationsDetailsExpired =>
      'These command details are no longer available.';

  @override
  String get operationsDetailsLoadFailed => 'Could not load command details.';

  @override
  String get historyWindowFailed => 'Could not open the inspection window.';

  @override
  String get operationRefresh => 'Refresh repository';

  @override
  String get operationInitialize => 'Initialize repository';

  @override
  String get operationClone => 'Clone repository';

  @override
  String get operationFetch => 'Fetch';

  @override
  String get operationPull => 'Pull';

  @override
  String get operationPush => 'Push';

  @override
  String get operationOther => 'Git operation';

  @override
  String get operationPhaseCounting => 'Counting objects';

  @override
  String get operationPhaseCompressing => 'Compressing objects';

  @override
  String get operationPhaseReceiving => 'Receiving objects';

  @override
  String get operationPhaseResolving => 'Resolving deltas';

  @override
  String get operationPhaseUpdatingFiles => 'Updating files';

  @override
  String get operationPhaseFiltering => 'Downloading file contents';

  @override
  String get operationPhaseRebasing => 'Rebasing';

  @override
  String operationPhaseProgress(String phase, int percent) {
    return '$phase $percent%';
  }

  @override
  String operationPercent(int percent) {
    return '$percent%';
  }

  @override
  String operationRunningDetail(String operation, String detail) {
    return '$operation · $detail';
  }

  @override
  String get operationStateRunning => 'Running';

  @override
  String get operationStateSucceeded => 'Succeeded';

  @override
  String get operationStateFailed => 'Failed';

  @override
  String get operationStateCanceled => 'Canceled';

  @override
  String get operationRepositoryApplication => 'Application';

  @override
  String get commandPaletteTitle => 'Commands';

  @override
  String get commandPaletteSearch => 'Search commands';

  @override
  String commandPaletteNoMatch(String query) {
    return 'No command matches “$query”';
  }

  @override
  String get shortcutReferenceTitle => 'Keyboard shortcuts';

  @override
  String get commandRepositoryRequired =>
      'Open a repository to use this command';

  @override
  String get commandFeatureUnavailable =>
      'This action is not available in the current build';

  @override
  String get commandContextUnavailable =>
      'This command needs a matching selection or active editor';

  @override
  String get commandInspectIndexLock => 'Check Git\'s lock file (index.lock)…';

  @override
  String get commandCreateBranch => 'Create branch…';

  @override
  String get commandRenameBranch => 'Rename branch…';

  @override
  String get commandDeleteBranch => 'Delete branch…';

  @override
  String get commandDeleteRemoteBranch => 'Delete remote branch…';

  @override
  String get commandCheckoutBranch => 'Check out branch…';

  @override
  String get commandAddRemote => 'Add remote…';

  @override
  String get commandEditRemote => 'Change remote URL…';

  @override
  String get commandRenameRemote => 'Rename remote…';

  @override
  String get commandRemoveRemote => 'Remove remote…';

  @override
  String get commandCreateTag => 'Create tag…';

  @override
  String get commandDeleteTag => 'Delete tag…';

  @override
  String get commandCloseRepositoryTab => 'Close repository tab';

  @override
  String get commandNextPane => 'Next pane';

  @override
  String get commandFind => 'Find';

  @override
  String get commandPushTag => 'Push tag…';

  @override
  String get commandResetBranch => 'Reset current branch…';

  @override
  String get refMutationNewName => 'New name';

  @override
  String get refMutationForceDelete => 'Delete even if it is not merged';

  @override
  String get refMutationCheckoutNewBranch => 'Check out the new branch';

  @override
  String get refMutationResetMode => 'Reset mode';

  @override
  String get refMutationResetSoft =>
      'Soft: move the branch, keep changes staged';

  @override
  String get refMutationResetMixed =>
      'Mixed: move the branch, keep changes unstaged';

  @override
  String get refMutationResetHard =>
      'Hard: move the branch, discard changes to tracked files';

  @override
  String get refMutationName => 'Name';

  @override
  String get refMutationRemoteUrl => 'Remote URL';

  @override
  String get refMutationRemoteUrlHidden =>
      'The current URL contains credentials and is not shown. Enter the complete new URL.';

  @override
  String get refMutationTagMessage => 'Annotation message (optional)';

  @override
  String get gitCommandDetails => 'Git command details';

  @override
  String secondsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String byteCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString bytes',
      one: '1 byte',
    );
    return '$_temp0';
  }

  @override
  String sizeKilobytes(String size) {
    return '$size KB';
  }

  @override
  String sizeMegabytes(String size) {
    return '$size MB';
  }

  @override
  String sizeGigabytes(String size) {
    return '$size GB';
  }

  @override
  String sizeTerabytes(String size) {
    return '$size TB';
  }

  @override
  String get commandDetails => 'Command details';

  @override
  String get pushOptions => 'Push options';

  @override
  String get integrationRunSummary =>
      'Run this configured tool with the selected repository context. The tool may change files or external systems.';

  @override
  String get integrationDiffSummary =>
      'Open the selected changes in the configured external diff tool. The tool receives temporary file paths.';

  @override
  String get integrationMergeSummary =>
      'Open the conflicted file in the configured merge tool. Review and save the result before continuing.';

  @override
  String hostingRemoveConfirm(String name) {
    return 'Remove hosting account $name from GitLama? Repository data on the server is unchanged. You will need to connect again to use its reviews and issues.';
  }

  @override
  String get rebasePreviewSummary =>
      'Your commits are replayed in this order. They get new commit IDs, and you may need to resolve conflicts along the way.';

  @override
  String get historyMergeSummary =>
      'Brings the changes of the selected branch into the current branch. Git may create a merge commit.';

  @override
  String get stashPushSummary =>
      'Save the selected changes in a stash and remove them from the working tree.';

  @override
  String get stashApplySummary =>
      'Apply stashed changes to the working tree. The stash remains available.';

  @override
  String get stashPopSummary =>
      'Apply stashed changes and remove the stash if the apply succeeds.';

  @override
  String get stashDropSummary =>
      'Delete this stash. Its changes may no longer be recoverable.';

  @override
  String get stashRenameSummary =>
      'Change this stash\'s description. Its saved changes remain.';

  @override
  String get stashCheckoutSummary =>
      'Save current changes temporarily, switch branches, then reapply them. Conflicts may need to be resolved.';

  @override
  String get bisectStartSummary =>
      'Start searching history for the commit that introduced a problem. Git will check out commits while you test them.';

  @override
  String get bisectGoodSummary =>
      'Mark the current commit as working. Git will check out the next commit to test.';

  @override
  String get bisectBadSummary =>
      'Mark the current commit as broken. Git will check out the next commit to test.';

  @override
  String get bisectSkipSummary =>
      'Skip this commit and check out another one to test.';

  @override
  String get bisectResetSummary =>
      'End the search and return to the branch you had checked out before it started.';

  @override
  String get deleteTagRemotePrompt => 'Also delete from remotes';

  @override
  String get deleteTagRemoteAvailabilityHint =>
      'A remote\'s tag is deleted only if it still points to the same commit as yours. The tag stays on this computer until every selected remote has deleted it.';

  @override
  String get deleteRefOnRemoteWarning =>
      'This also deletes it on the remote, where others may already have fetched it.';

  @override
  String get deleteTagLocalFailedAfterRemote =>
      'The selected remote tag was deleted, but the local tag could not be deleted. Check the repository state before retrying.';

  @override
  String deleteTagRemoteFailed(String remote) {
    return 'Could not delete the tag on $remote. The local tag remains. Check any earlier remotes before retrying.';
  }

  @override
  String refConfirmCreateBranch(String name) {
    return 'Create local branch $name.';
  }

  @override
  String refConfirmCreateAndCheckoutBranch(String name) {
    return 'Create local branch $name and switch to it. Uncommitted changes stay in the working tree.';
  }

  @override
  String refConfirmRenameBranch(String name, String newName) {
    return 'Rename local branch $name to $newName. Remote branches are unchanged.';
  }

  @override
  String refConfirmDeleteBranch(String name) {
    return 'Delete local branch $name. Remote branches are unchanged.';
  }

  @override
  String refConfirmDeleteBranchAndUpstream(String name, String upstream) {
    return 'Delete local branch $name and its upstream $upstream on the remote.';
  }

  @override
  String refMutationDeleteUpstream(String upstream) {
    return 'Also delete $upstream';
  }

  @override
  String get refMutationDeleteUpstreamHelp =>
      'Deleted only if it has not moved since the last fetch.';

  @override
  String deleteBranchUpstreamFailed(String upstream) {
    return 'The local branch was deleted, but $upstream could not be deleted on the remote. Fetch and check the remote branch before retrying.';
  }

  @override
  String refConfirmCheckoutBranch(String name) {
    return 'Switch to local branch $name. Files in the working tree may change.';
  }

  @override
  String refConfirmCreateTag(String name) {
    return 'Create local tag $name. It will not be published automatically.';
  }

  @override
  String refConfirmDeleteTagLocal(String name) {
    return 'Delete local tag $name. Tags on remotes are unchanged.';
  }

  @override
  String refConfirmDeleteTagRemotes(String name, String remotes) {
    return 'Delete tag $name from $remotes, then delete the local tag. Other users may already have fetched it.';
  }

  @override
  String refConfirmAddRemote(String name) {
    return 'Add remote $name to this repository. No files or remote data change.';
  }

  @override
  String refConfirmEditRemote(String name) {
    return 'Change the URL for remote $name. Future transfers will use the new address.';
  }

  @override
  String refConfirmRenameRemote(String name, String newName) {
    return 'Rename remote $name to $newName. Its remote branches and the upstreams that use it move to the new name.';
  }

  @override
  String refConfirmRemoveRemote(String name) {
    return 'Remove remote $name from this repository. The server and its branches remain available to others.';
  }

  @override
  String get refConfirmResetSoft =>
      'Move the current branch to the selected commit. Staged and working tree changes remain.';

  @override
  String get refConfirmResetMixed =>
      'Move the current branch and reset staged changes. Working tree files remain.';

  @override
  String get refConfirmResetHard =>
      'Move the current branch and discard tracked staged and working tree changes. The discarded changes are lost.';

  @override
  String get refMutationWarningDirty => 'The worktree has uncommitted changes.';

  @override
  String get refMutationWarningDetached => 'No branch is checked out.';

  @override
  String get refMutationWarningPublished => 'This branch appears on a remote.';

  @override
  String get refMutationWarningOtherWorktree =>
      'Another worktree has this branch checked out.';

  @override
  String get refMutationWarningDestructiveReset =>
      'A hard reset discards all staged and unstaged changes to tracked files.';

  @override
  String get refMutationCompleted => 'Git operation completed.';

  @override
  String get refMutationStale =>
      'Repository state changed. Preview the operation again.';

  @override
  String get refMutationFailed => 'Git did not complete the operation.';

  @override
  String get refMutationWarningResult =>
      'Git completed the operation, but the view could not be refreshed.';

  @override
  String get commandCreateStash => 'Create stash…';

  @override
  String get commandAddWorktree => 'Add worktree…';

  @override
  String get commandTrackLfsPattern => 'Track LFS pattern…';

  @override
  String get commandAddIntegration => 'Add integration…';

  @override
  String get indexLockNotFound => 'No Git lock file was found.';

  @override
  String get indexLockConfirmationTitle => 'Remove Git\'s lock file?';

  @override
  String indexLockConfirmation(String size) {
    return 'Make sure no other Git program is working in this repository first. This removes Git\'s lock file ($size), not your staged changes. Removing a lock that is still in use can damage the repository. The interrupted command does not run again automatically.';
  }

  @override
  String get indexLockRemove => 'Remove lock';

  @override
  String get indexLockRemoved =>
      'Git\'s lock file was removed. The interrupted command was not run again.';

  @override
  String get indexLockChanged =>
      'The lock file changed after it was checked. Check it again before removing it.';

  @override
  String get indexLockActiveOperation =>
      'The lock cannot be removed while repository work is active.';

  @override
  String get indexLockUnavailable =>
      'Git\'s lock file could not be checked or removed safely.';

  @override
  String get galleryTitle => 'GitLama component gallery';

  @override
  String get galleryOpenRepository => 'Open repository';

  @override
  String get galleryUnavailableAction =>
      'Unavailable action with a deliberately long label';

  @override
  String get galleryUnavailableReason => 'No repository is open';

  @override
  String get galleryLoadingRepository => 'Loading repository';

  @override
  String get galleryRefresh => 'Refresh';

  @override
  String get galleryWorkspaceMenu => 'Workspace menu';

  @override
  String get galleryHistory => 'History';

  @override
  String get galleryChanges => 'Changes';

  @override
  String get galleryActivity => 'Activity';

  @override
  String get galleryBranchRow =>
      'main  A long branch label that must remain accessible';

  @override
  String get galleryCurrent => 'Current checkout';

  @override
  String get historyObjectIdCopied => 'Full value copied.';

  @override
  String get historyHashCopied => 'Copied';

  @override
  String get historyCopyObjectId => 'Copy commit SHA';

  @override
  String get historyCopySubject => 'Copy commit subject';

  @override
  String get menuCommitHashCopied => 'Commit hash copied.';

  @override
  String get menuCommitSubjectCopied => 'Commit subject copied.';

  @override
  String get menuNameCopied => 'Name copied.';

  @override
  String historyWorkingTreeChanges(int count, int staged) {
    return 'Uncommitted changes · $count files · $staged staged';
  }

  @override
  String historyWorkingTreeConflicts(int count) {
    return 'Conflicts · $count files · open resolver';
  }

  @override
  String historyRowSemantics(
    String subject,
    String author,
    String objectId,
    String date,
    int lane,
    String references,
    int overflow,
  ) {
    return 'History row. Subject: $subject. Author: $author. Commit: $objectId. Date: $date. Lane $lane. References: $references. $overflow additional references.';
  }

  @override
  String get historySearchHint => 'Search commits';

  @override
  String get searchClear => 'Clear search';

  @override
  String get historyApplyFilter => 'Apply filter';

  @override
  String get historyBranchFilter => 'Branches';

  @override
  String historyBranchFilterCount(int count) {
    return 'Branches ($count)';
  }

  @override
  String get historyBranchFilterTooltip => 'Filter the graph by branch';

  @override
  String get historyBranchFilterSearch => 'Find a branch';

  @override
  String get historyBranchFilterNoMatches => 'No branches match.';

  @override
  String get historyBranchFilterFocus => 'Show only this branch';

  @override
  String get historyBranchFilterAdd => 'Add to graph filter';

  @override
  String get historyBranchFilterRemove => 'Remove from graph filter';

  @override
  String get historyBranchFilterShowAll => 'Show all branches';

  @override
  String get historyBranchFilterCurrent => 'Current branch';

  @override
  String historyBranchFilterSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count branches shown',
      one: '1 branch shown',
      zero: 'All branches shown',
    );
    return '$_temp0';
  }

  @override
  String get historyBranchFilterHelp =>
      'Click to add or remove. Double-click or press Enter to show only one.';

  @override
  String get historyBranchFilterShown => 'Shown in graph';

  @override
  String get historyBranchFilterNoCommits =>
      'No commits match the branch filter.';

  @override
  String get historySearchScopes => 'Search fields';

  @override
  String get historySearchHash => 'Commit hash';

  @override
  String get historySearchMessage => 'Message';

  @override
  String get historySearchAuthor => 'Author';

  @override
  String get historySearchPath => 'Changed path';

  @override
  String historyAcceptedFilter(String filter) {
    return 'Showing accepted filter: $filter';
  }

  @override
  String historyPendingFilter(String filter) {
    return 'Searching: $filter';
  }

  @override
  String get historyViewOptions => 'View options';

  @override
  String get historyShowOtherRefs => 'Show other refs';

  @override
  String get historyTargetOutsideRefScope =>
      'History doesn\'t show this commit. Commits that only other refs reach, such as notes or tool checkpoints, are hidden.';

  @override
  String get historyTargetNotShown =>
      'History doesn\'t show this commit. No ref reaches it.';

  @override
  String get historySelectionFilteredOut =>
      'The selected commit is outside this result. Selection is retained.';

  @override
  String get historyFilterFailed =>
      'The filter could not be applied. The previous result is still shown.';

  @override
  String get historyCollapseSelected => 'Collapse or expand selected merge';

  @override
  String historyCollapsedCount(int count) {
    return '$count commits collapsed';
  }

  @override
  String get historyReflog => 'Reflog';

  @override
  String get historyGraph => 'Graph';

  @override
  String get historyHeadReference => 'HEAD';

  @override
  String get repositoryDropPrompt => 'Drop repository folders to open them';

  @override
  String repositoryDropSummary(int opened, int rejected, int failed) {
    return 'Opened $opened repositories. Rejected $rejected non-folder items. $failed folders could not be opened.';
  }

  @override
  String get historyReflogRetainedFailure =>
      'Reflog refresh failed. Previously loaded reflog entries remain available.';

  @override
  String get historyReflogEmpty => 'No reflog entries are available.';

  @override
  String get historyNavigateBack => 'Back in file inspection';

  @override
  String get historyNavigateForward => 'Forward in file inspection';

  @override
  String get historyTreeBinaryFile => 'This file cannot be previewed as text.';

  @override
  String get historyTreeFileTooLarge => 'This file is too large to preview.';

  @override
  String get historyTreeEmptyFile => 'This file is empty.';

  @override
  String get historyTreeFileFailed =>
      'Could not load this file from the selected commit.';

  @override
  String get historyAuthor => 'Author';

  @override
  String get historyCoAuthors => 'Co-authors';

  @override
  String get historyCommitter => 'Committer';

  @override
  String get historyCommitDate => 'Commit date';

  @override
  String get historyBlameBefore => 'Go before this change';

  @override
  String blameAgeMinutes(int count) {
    return '$count min';
  }

  @override
  String blameAgeHours(int count) {
    return '$count h';
  }

  @override
  String blameAgeDays(int count) {
    return '$count d';
  }

  @override
  String blameAgeMonths(int count) {
    return '$count mo';
  }

  @override
  String blameAgeYears(int count) {
    return '$count y';
  }

  @override
  String get historyChangedFilesShort => 'Changed';

  @override
  String historyFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get historyFileActions => 'File actions';

  @override
  String get historyBlame => 'Blame';

  @override
  String get historyPathHistory => 'Path history';

  @override
  String historyRenamedFrom(String path) {
    return 'renamed from $path';
  }

  @override
  String get historyInspectionLoading => 'Loading inspection row…';

  @override
  String get historyRestoreFile => 'Restore this version';

  @override
  String historyRestorePreview(String path) {
    return 'Your current $path is replaced with its version from this commit. If the file or the checked-out commit changes first, nothing happens.';
  }

  @override
  String get historyRestoreNoCurrentFile => 'Not present';

  @override
  String get historyRestoreCurrentSize => 'Current file';

  @override
  String get historyRestoreSourceSize => 'Version in this commit';

  @override
  String get historyRestoreConfirm => 'Restore file';

  @override
  String get historyRestoreSucceeded =>
      'The file was restored from the selected commit.';

  @override
  String get historyRestoreStale =>
      'The file or the current commit changed. Nothing was restored; preview again.';

  @override
  String get historyRestoreReconciled =>
      'The file was restored, but the repository refresh needs attention.';

  @override
  String get historyRestoreOutcomeUncertain =>
      'Git may have changed the file. Inspect the worktree before retrying.';

  @override
  String get historyRestoreFailed => 'The file could not be restored.';

  @override
  String get diffSearchHint => 'Find in diff';

  @override
  String get diffPreviousMatch => 'Previous match';

  @override
  String get diffNextMatch => 'Next match';

  @override
  String get diffCaseSensitive => 'Case-sensitive search';

  @override
  String findMatchPosition(int current, int total) {
    return '$current of $total';
  }

  @override
  String findMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$_temp0';
  }

  @override
  String get findNoMatches => 'No matches';

  @override
  String get findInFileHint => 'Find in file';

  @override
  String get loading => 'Loading…';

  @override
  String get diffPreviousHunk => 'Previous hunk';

  @override
  String get diffNextHunk => 'Next hunk';

  @override
  String get diffSideBySide => 'Side-by-side diff';

  @override
  String get diffUnified => 'Unified diff';

  @override
  String get diffContextLines => 'Context lines';

  @override
  String diffContextValue(int count) {
    return '$count context lines';
  }

  @override
  String get diffShowMoreLines => 'Show more lines';

  @override
  String get diffCollapseFile => 'Collapse file';

  @override
  String get diffExpandFile => 'Expand file';

  @override
  String get diffWhitespace => 'Cycle whitespace comparison';

  @override
  String get diffWrap => 'Wrap long lines';

  @override
  String get diffIndicators => 'Show plus and minus indicators';

  @override
  String get diffMinimap => 'Show diff minimap';

  @override
  String get diffAllFiles => 'Show all changed files';

  @override
  String get diffNoNewline => 'No newline at end of file';

  @override
  String get diffBinaryFallback =>
      'Binary content — text comparison is unavailable';

  @override
  String get showBinaryAsText => 'Show as text';

  @override
  String get diffImageFallback => 'Image changed — open visual comparison';

  @override
  String get diffSubmoduleFallback => 'Submodule commit changed';

  @override
  String diffModeOnlyFallback(String modes) {
    return 'File mode changed: $modes';
  }

  @override
  String get diffTooLargeFallback =>
      'Diff is too large for an inline text comparison';

  @override
  String get diffImageComparison => 'Image comparison';

  @override
  String get diffOldImage => 'Before';

  @override
  String get diffNewImage => 'After';

  @override
  String diffImageDimensions(int width, int height) {
    return '$width × $height px';
  }

  @override
  String diffImageDetails(String dimensions, String size) {
    return '$dimensions · $size';
  }

  @override
  String diffImageSideDetails(String side, String details) {
    return '$side: $details';
  }

  @override
  String get diffImageMissing => 'No image exists on this side.';

  @override
  String get diffImageDecodeFailed => 'This image could not be decoded safely.';

  @override
  String get diffImageDecodeUnsupported =>
      'GitLama previews common image formats and SVGs without text, scripts, linked files or reused elements.';

  @override
  String get diffImageDecodeMalformed => 'The file is not a valid image.';

  @override
  String get diffImageDecodeTooLarge =>
      'The image is larger than GitLama previews.';

  @override
  String get diffImageDecodeTimedOut =>
      'Decoding took too long. Select the file again to retry.';

  @override
  String get diffImageSideBySide => 'Side by side';

  @override
  String get diffImageSwipe => 'Swipe';

  @override
  String get diffImageOnionSkin => 'Onion skin';

  @override
  String get diffImageDivider => 'Divider';

  @override
  String get diffImageBlend => 'Blend';

  @override
  String get diffImagePreparing => 'Preparing decoded image…';

  @override
  String get diffImageLoadFailed => 'The image could not be loaded.';

  @override
  String get diffEncoding => 'Text encoding';

  @override
  String get diffEncodingUtf8 => 'UTF-8';

  @override
  String get diffEncodingLatin1 => 'ISO-8859-1 fallback';

  @override
  String get diffEncodingInvalid => 'Not valid UTF-8 — choose an encoding';

  @override
  String get diffRendererTitle => 'Diff renderer';

  @override
  String get diffRendererName => 'Display name';

  @override
  String get diffRendererId => 'Identifier';

  @override
  String get diffRendererContainmentHelp =>
      'GitLama sends the diff to the program and shows the plain text it returns. Arguments are passed exactly as written, without a shell, and the output can\'t add links or controls.';

  @override
  String get diffRendererArgumentsHelp =>
      'One argument per line, passed exactly as written, without a shell.';

  @override
  String get diffRendererNotConfigured => 'No diff renderer is configured';

  @override
  String get diffRendererRun => 'Render diff';

  @override
  String get diffRendererPreviewTitle => 'Run the diff renderer?';

  @override
  String get diffRendererRunSummary =>
      'GitLama sends the selected diff to this program and shows the plain text it returns.';

  @override
  String get diffRendererCapabilityCommand => 'Check command';

  @override
  String get diffRendererRenderCommand => 'Render command';

  @override
  String get diffRendererProtocol => 'Protocol';

  @override
  String get diffRendererOutputFormat => 'Output format';

  @override
  String get diffRendererTimeLimit => 'Time limit';

  @override
  String get diffRendererOutputLimit => 'Output limit';

  @override
  String get diffRendererInputSize => 'Diff size';

  @override
  String get diffRendererProgram => 'Program';

  @override
  String get diffRendererValidatedTitle => 'Save this diff renderer?';

  @override
  String get diffRendererValidatedSummary =>
      'The program passed the check and can show diffs as plain text. GitLama asks before each run.';

  @override
  String get diffRendererSave => 'Save renderer';

  @override
  String get diffRendererUseBuiltIn => 'Use built-in';

  @override
  String get diffRendererPlainText =>
      'Inert plain-text output with built-in diff available';

  @override
  String get diffRendererInvalidDefinition =>
      'The renderer configuration is invalid. The built-in diff remains active.';

  @override
  String get diffRendererUnavailable =>
      'The renderer executable is unavailable. The built-in diff remains active.';

  @override
  String get diffRendererInvalidCapability =>
      'The renderer did not provide the required plain-text capability. The built-in diff remains active.';

  @override
  String get diffRendererInputTooLarge =>
      'The diff exceeds the renderer input limit. The built-in diff remains active.';

  @override
  String get diffRendererOutputTooLarge =>
      'The renderer output exceeded its limit. The built-in diff remains active.';

  @override
  String get diffRendererLaunchFailed =>
      'The renderer could not start. The built-in diff remains active.';

  @override
  String get diffRendererProcessFailed =>
      'The renderer exited with a failure. The built-in diff remains active.';

  @override
  String get diffRendererTimedOut =>
      'The renderer timed out. The built-in diff remains active.';

  @override
  String get diffRendererCanceled =>
      'The renderer was canceled. The built-in diff remains active.';

  @override
  String get diffRendererStale =>
      'The selected diff changed. The built-in diff remains active.';

  @override
  String get changesStaged => 'Staged changes';

  @override
  String get changesUnstaged => 'Unstaged changes';

  @override
  String get changesListView => 'Show files as a list';

  @override
  String get changesTreeView => 'Show files as a tree';

  @override
  String get changesPartial => 'partial';

  @override
  String get changesResizeCommit => 'Resize the commit editor';

  @override
  String get changesResizePanes => 'Resize staged and unstaged panes';

  @override
  String get workspaceResizeDetail => 'Resize the detail pane';

  @override
  String get workspaceResizeSidebar => 'Resize the repository sidebar';

  @override
  String get copyFilePath => 'Copy path';

  @override
  String get openFileExternal => 'Open in external editor';

  @override
  String openInFileBrowser(String browser) {
    return 'Open in $browser';
  }

  @override
  String get dragChangeToOtherList => 'Drag to the other change list';

  @override
  String get filePathCopied => 'File path copied.';

  @override
  String get stageAll => 'Stage all';

  @override
  String get unstageAll => 'Unstage all';

  @override
  String get stageSelected => 'Stage selected';

  @override
  String get unstageSelected => 'Unstage selected';

  @override
  String get stageFile => 'Stage file';

  @override
  String get unstageFile => 'Unstage file';

  @override
  String get inspectChanges => 'Select changed lines';

  @override
  String get inspectChangesHelp =>
      'Tick single changed lines, or a section header to take the whole section.';

  @override
  String lineSelectionCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString lines selected',
      one: '1 line selected',
      zero: 'No lines selected',
    );
    return '$_temp0';
  }

  @override
  String lineSelectionCountAtLeast(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At least $countString lines selected',
      one: 'At least 1 line selected',
    );
    return '$_temp0';
  }

  @override
  String lineSelectionSection(String header) {
    return 'Section $header';
  }

  @override
  String lineSelectionAdded(int line, String text) {
    return 'Added line $line: $text';
  }

  @override
  String lineSelectionRemoved(int line, String text) {
    return 'Removed line $line: $text';
  }

  @override
  String get stageLines => 'Stage selected changes';

  @override
  String get unstageLines => 'Unstage selected changes';

  @override
  String get stagingCompleted => 'Staged changes updated.';

  @override
  String get stagingStale =>
      'The files changed in the meantime. Nothing was staged or unstaged.';

  @override
  String get stagingFailed => 'The staged changes could not be updated.';

  @override
  String get stagingWarning =>
      'The staged changes were updated, but the file lists could not be refreshed.';

  @override
  String get stagingEmpty => 'No changes on this side.';

  @override
  String get commandStageToggle => 'Stage or unstage';

  @override
  String get commandDiffToggleLayout => 'Toggle diff layout';

  @override
  String get commandDiffRenderConfigured =>
      'Render diff with configured renderer';

  @override
  String get commandDiffToggleWrap => 'Toggle diff line wrap';

  @override
  String get commandDiffNextHunk => 'Next hunk';

  @override
  String get commandDiffPreviousHunk => 'Previous hunk';

  @override
  String get stagingLoadMore => 'Load more changes';

  @override
  String get commitSubject => 'Commit subject';

  @override
  String get commitDescription => 'Description';

  @override
  String get commitCoauthors => 'Co-authors';

  @override
  String get commitAuthor => 'Author override';

  @override
  String get commitOptions => 'Commit options';

  @override
  String get commitAction => 'Commit';

  @override
  String commitToBranch(String branch) {
    return 'Commit to $branch';
  }

  @override
  String commitAmendHash(String hash) {
    return 'Amend $hash';
  }

  @override
  String changesStagedFilesCount(int count) {
    return '$count staged';
  }

  @override
  String changesDragStageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Stage $count files',
      one: 'Stage 1 file',
    );
    return '$_temp0';
  }

  @override
  String changesDragUnstageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unstage $count files → Working tree',
      one: 'Unstage 1 file → Working tree',
    );
    return '$_temp0';
  }

  @override
  String get commitAndPush => 'Commit & push';

  @override
  String get commitAmendMessageFailed =>
      'Could not load the last commit message. Turn Amend off and on to retry, or enter a message.';

  @override
  String get commitAmend => 'Amend';

  @override
  String get commitSignOff => 'Sign off';

  @override
  String get commitSkipHooks => 'Skip hooks';

  @override
  String get commitSpellcheck => 'Spellcheck';

  @override
  String get commitTemplate => 'Template';

  @override
  String get commitRecent => 'Recent';

  @override
  String get commitSigning => 'Commit signing';

  @override
  String get commitSigningGit => 'Use Git configuration';

  @override
  String get commitSigningRequired => 'Require signature';

  @override
  String get commitSigningDisabled => 'Commit unsigned';

  @override
  String get commitHookFailure => 'Commit hook failed';

  @override
  String get commitSigningFailure => 'Commit signing failed';

  @override
  String get commitOtherFailure => 'Git rejected the commit';

  @override
  String commitFailureExitCode(int code) {
    return 'Exit code $code';
  }

  @override
  String get commitRetry => 'Retry';

  @override
  String get commitSkipHooksConfirmTitle => 'Skip commit hooks?';

  @override
  String get commitSkipHooksConfirmBody =>
      'Hooks are checks this repository runs before each commit. This attempt skips them. Type SKIP to confirm.';

  @override
  String get commitSkipHooksConfirmInput => 'Type SKIP';

  @override
  String commitCommittedObject(String objectId) {
    return 'Committed $objectId';
  }

  @override
  String get commitEmptySubject => 'Enter a subject before committing.';

  @override
  String get commitNothingStaged => 'Stage changes before committing.';

  @override
  String get commitTrailingWhitespace => 'The subject ends with whitespace.';

  @override
  String get commitPublishedWarning =>
      'This commit appears on a remote branch. Amending it rewrites published history.';

  @override
  String get commitConfirmAmend => 'Amend published commit';

  @override
  String get commitCompleted => 'Commit created.';

  @override
  String get commitStale =>
      'The current commit or the staged changes changed. Nothing was committed.';

  @override
  String get commitFailed => 'Git rejected the commit. The draft was kept.';

  @override
  String get commitWarning => 'Commit created, but refresh needs attention.';

  @override
  String get discardSelected => 'Discard selected';

  @override
  String get discardAll => 'Discard all';

  @override
  String get cleanSelected => 'Clean selected';

  @override
  String get discardFile => 'Discard file changes';

  @override
  String get cleanFile => 'Delete new file or folder';

  @override
  String get discardLines => 'Discard selected changes';

  @override
  String get discardConfirmTitle => 'Permanently discard changes?';

  @override
  String get cleanConfirmTitle => 'Permanently delete new files?';

  @override
  String discardConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This affects $count files.',
      one: 'This affects 1 file.',
    );
    return '$_temp0 The changes are deleted permanently.';
  }

  @override
  String get discardConfirmAction => 'Discard permanently';

  @override
  String get cleanConfirmAction => 'Delete permanently';

  @override
  String get discardCompleted => 'Changes were permanently discarded.';

  @override
  String get discardStale =>
      'The confirmed paths changed. Nothing was discarded.';

  @override
  String get discardFailed => 'Git could not discard the confirmed changes.';

  @override
  String get discardWarning =>
      'Changes were discarded, but refresh needs attention.';

  @override
  String get patchTitle => 'Patches';

  @override
  String get patchCreateDescription =>
      'Save changes as a patch file that you can share or apply elsewhere.';

  @override
  String get patchApplyDescription =>
      'Apply the changes in a patch file to this repository\'s files.';

  @override
  String get patchCreate => 'Create patch';

  @override
  String get patchApply => 'Apply patch';

  @override
  String get patchWrite => 'Write patch';

  @override
  String get patchChooseDestination => 'Choose destination';

  @override
  String get patchChooseFile => 'Choose patch file';

  @override
  String get patchDestination => 'Folder';

  @override
  String get patchDestinationUnset =>
      'Choose a folder to see what will be written.';

  @override
  String get patchScope => 'Contains';

  @override
  String get patchFormat => 'Format';

  @override
  String get patchFilename => 'File name';

  @override
  String get patchSize => 'Size';

  @override
  String get patchFormatUnified => 'Unified diff';

  @override
  String get patchFormatEmail => 'Email patch series';

  @override
  String get patchOverwriteWarning =>
      'A file with this name already exists in the folder. Replace it, or choose another folder.';

  @override
  String get patchOverwrite => 'Replace existing file';

  @override
  String get patchExportDone => 'Patch created.';

  @override
  String get patchExportStale =>
      'The repository or destination changed. Nothing was written.';

  @override
  String get patchExportFailed => 'The patch could not be created.';

  @override
  String get patchTarget => 'Repository';

  @override
  String get patchCurrentRepository => 'Current repository';

  @override
  String get patchFile => 'Patch file';

  @override
  String get patchFileUnset => 'Choose a .patch or .diff file.';

  @override
  String get patchCheck => 'Check';

  @override
  String get patchCheckPassed => 'Applies cleanly';

  @override
  String get patchBinary => 'Binary changes';

  @override
  String patchFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files change',
      one: '1 file changes',
    );
    return '$_temp0';
  }

  @override
  String get patchSavedTo => 'Saved to';

  @override
  String get patchYes => 'Yes';

  @override
  String get patchNo => 'No';

  @override
  String get patchApplyDone => 'Patch applied.';

  @override
  String get patchApplyStale =>
      'The patch or target files changed. Nothing was applied.';

  @override
  String get patchApplyFailed =>
      'The patch did not pass its checks and was not applied.';

  @override
  String get patchApplyWarning =>
      'The patch was applied, but the view may be out of date.';

  @override
  String get patchApplyOutcomeUncertain =>
      'Git may have applied part of the patch. Check your files before trying again.';

  @override
  String get patchScopeLines => 'Selected lines';

  @override
  String get patchScopeSelectedUnstaged => 'Selected unstaged files';

  @override
  String get patchScopeSelectedStaged => 'Selected staged files';

  @override
  String get patchScopeUnstaged => 'All unstaged changes';

  @override
  String get patchScopeStaged => 'All staged changes';

  @override
  String get patchScopeHead => 'All changes since the last commit';

  @override
  String get patchScopeCommit => 'Selected commit';

  @override
  String get patchScopeRange => 'Selected commit range';

  @override
  String get patchScopeCompare => 'Active comparison';

  @override
  String get commandFetch => 'Fetch…';

  @override
  String get commandFetchRemote => 'Fetch remote';

  @override
  String get commandPull => 'Pull…';

  @override
  String get commandPush => 'Push…';

  @override
  String get commandPushRemote => 'Push remote';

  @override
  String get commandHostingCreatePullRequest =>
      'Create pull request in browser';

  @override
  String get commandHistoryCompare => 'Compare commits';

  @override
  String get commandHistoryBlame => 'Blame file';

  @override
  String get commandHistoryPathHistory => 'File history';

  @override
  String get commandInteractiveRebase => 'Interactive rebase…';

  @override
  String get commandRebaseSquash => 'Squash rebase entry';

  @override
  String get commandRebaseFixup => 'Fixup rebase entry';

  @override
  String get commandRebaseReword => 'Reword rebase entry';

  @override
  String get commandRebaseDrop => 'Drop rebase entry';

  @override
  String get commandOpenInEditor => 'Open in editor';

  @override
  String get commandOpenInTerminal => 'Open in terminal';

  @override
  String get transferRemote => 'Remote';

  @override
  String get transferBranch => 'Branch';

  @override
  String get transferTag => 'Tag';

  @override
  String get transferTagHelp => 'The exact local tag name to publish';

  @override
  String get transferPullStrategy => 'How to combine changes';

  @override
  String get transferFfOnly => 'Only if no merge is needed';

  @override
  String get transferFfPossible => 'Merge if needed';

  @override
  String get transferRebase => 'Put my commits on top (rebase)';

  @override
  String get transferAllowDirty => 'Pull with my uncommitted changes';

  @override
  String get transferAllowDirtyHelp =>
      'No stash is created. Git may refuse overlapping edits or a rebase. Choose stash and reapply to save your changes first.';

  @override
  String get transferSetUpstream => 'Link this branch to the remote branch';

  @override
  String get transferSetUpstreamHelp =>
      'Later pulls and pushes of this branch use the same remote branch.';

  @override
  String get transferForceWithLease => 'Force push with lease';

  @override
  String get transferForceOption => 'Overwrite the remote branch';

  @override
  String get statusGlyphModified => 'Modified';

  @override
  String get statusGlyphAdded => 'Added';

  @override
  String get statusGlyphDeleted => 'Deleted';

  @override
  String get statusGlyphRenamed => 'Renamed';

  @override
  String get statusGlyphCopied => 'Copied';

  @override
  String get statusGlyphConflict => 'Conflict';

  @override
  String get statusGlyphUntracked => 'Untracked';

  @override
  String get statusGlyphIgnored => 'Ignored';

  @override
  String syncAheadBehind(int ahead, int behind) {
    return '$ahead ahead, $behind behind';
  }

  @override
  String transferAheadBehind(String ahead, String behind) {
    return 'Ahead $ahead · Behind $behind';
  }

  @override
  String get transferCredentialsTitle => 'Authentication required';

  @override
  String get transferCredentialsTransient =>
      'Credentials are used for this retry only and are not stored.';

  @override
  String get transferUsername => 'Username (optional)';

  @override
  String get transferPassword => 'Password';

  @override
  String get transferToken => 'Access token';

  @override
  String get transferUseToken => 'Use an access token';

  @override
  String transferCompleted(String ahead, String behind) {
    return 'Transfer completed. Ahead $ahead · Behind $behind.';
  }

  @override
  String get transferReconciledWarning =>
      'The transfer completed, but the view could not be refreshed.';

  @override
  String get transferFailed => 'The transfer failed.';

  @override
  String get transferFailureInvalid => 'The transfer request is invalid.';

  @override
  String get transferFailureDetached =>
      'Check out a branch before pulling or pushing.';

  @override
  String get transferFailureUpstream =>
      'Choose a valid remote and branch. Force push also needs a fetched lease.';

  @override
  String get transferFailureDirty =>
      'Commit or stash your changes first, or choose how to handle them in the Pull dialog.';

  @override
  String get transferFailureConflicted =>
      'Resolve the current conflicts before pulling.';

  @override
  String get transferFailureStale =>
      'Repository state changed after the preview. Review the transfer again.';

  @override
  String get transferFailureAuthentication =>
      'Authentication failed. Retry with credentials.';

  @override
  String get transferFailureCredentialBroker =>
      'Secure credential retry is unavailable on this platform.';

  @override
  String get transferFailureHostKey => 'SSH host-key verification failed.';

  @override
  String get transferFailureRejected =>
      'Git could not complete the transfer. Check the operation log for details.';

  @override
  String get transferFailureTimeout =>
      'The transfer stopped after producing no progress.';

  @override
  String get transferFailureCanceled => 'The transfer was canceled.';

  @override
  String get transferFailureMissingGit => 'Git could not be started.';

  @override
  String get transferFailureMissingObject =>
      'Git could not read data it needs for this transfer.';

  @override
  String get transferMissingObjectTitle => 'Missing Git objects';

  @override
  String transferMissingObjectDetail(String remote) {
    return 'Git could not read data it needs to finish. Fetching again from $remote may restore it. A failed pull may already have changed files, so review Changes before retrying. Fetching again will not discard or finish those changes.';
  }

  @override
  String get transferRefetchAction => 'Refetch objects';

  @override
  String get transferRefetchCompleted =>
      'Objects fetched. Review any changes left by the failed operation before retrying.';

  @override
  String get commandApplyStash => 'Apply stash…';

  @override
  String get commandPopStash => 'Pop stash…';

  @override
  String get commandRenameStash => 'Rename stash…';

  @override
  String get commandDropStash => 'Drop stash…';

  @override
  String get commandAutoStashCheckout => 'Auto-stash and check out…';

  @override
  String stashSelected(String selector) {
    return 'Selected stash: $selector';
  }

  @override
  String get stashMessage => 'Name (optional)';

  @override
  String get stashNewName => 'New stash name';

  @override
  String get stashIncludeUntracked => 'Include new files';

  @override
  String get stashKeepIndex => 'Keep staged changes';

  @override
  String get stashTargetBranch => 'Target branch';

  @override
  String get stashDropWarning =>
      'Dropping deletes this stash from the stack for good.';

  @override
  String get stashPreviewTitle => 'Review stash';

  @override
  String get stashRecoveryRetained =>
      'If applying fails, the stash is kept so nothing is lost.';

  @override
  String get stashCompleted => 'Stash operation completed.';

  @override
  String get stashReconciledWarning =>
      'The operation completed, but the repository refresh needs attention.';

  @override
  String get stashFailed => 'The stash operation failed.';

  @override
  String get stashConflict =>
      'The stash produced conflicts. Open the conflict workflow to continue.';

  @override
  String get stashConflictRetained =>
      'The stash produced conflicts and remains on the stack. Open the conflict workflow to continue.';

  @override
  String get stashFailureInvalid => 'The stash request is invalid.';

  @override
  String get stashFailureNothing =>
      'Git found no matching changes it could stash. Commit or stash edits inside submodules in their own repository before checking out.';

  @override
  String get stashFailureMissing => 'The selected stash no longer exists.';

  @override
  String get stashFailureStale =>
      'Repository or stash state changed after the preview. Review the operation again.';

  @override
  String get stashFailureCanceled => 'The stash operation was canceled.';

  @override
  String get stashFailureTimeout => 'The stash operation timed out.';

  @override
  String get stashFailureMissingGit => 'Git could not be started.';

  @override
  String get commandMergeBranch => 'Merge branch…';

  @override
  String get commandIntegrateBranch => 'Integrate branch…';

  @override
  String get commandRebaseBranch => 'Rebase onto branch…';

  @override
  String get commandCherryPickSelected => 'Cherry-pick selected commits…';

  @override
  String get commandRevertSelected => 'Revert selected commits…';

  @override
  String get historyMutationSourceBranch => 'Source branch';

  @override
  String get historyMutationMergeMode => 'Merge mode';

  @override
  String get historyMutationFastForwardPossible => 'Fast-forward if possible';

  @override
  String get historyMutationFastForwardOnly => 'Fast-forward only';

  @override
  String get historyMutationNoFastForward => 'Always create a merge commit';

  @override
  String get historyMutationSelectCommits =>
      'Select one or more commits in History first.';

  @override
  String get historyMutationPublishedWarning =>
      'I understand this adds commits to a published branch.';

  @override
  String get historyMutationAlreadyContained =>
      'The current branch already contains these changes. Nothing needs to change.';

  @override
  String get historyMutationCanceling => 'Canceling…';

  @override
  String get commandRepositoryBusy =>
      'Wait for the running operation in this repository to finish';

  @override
  String historyMutationBusyMerge(String source, String branch) {
    return 'Merging $source into $branch…';
  }

  @override
  String historyMutationBusyCherryPick(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cherry-picking $count commits onto $branch…',
      one: 'Cherry-picking 1 commit onto $branch…',
    );
    return '$_temp0';
  }

  @override
  String historyMutationBusyRevert(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reverting $count commits on $branch…',
      one: 'Reverting 1 commit on $branch…',
    );
    return '$_temp0';
  }

  @override
  String get conflictPredictionBusy => 'Checking for likely conflicts…';

  @override
  String rebaseBusy(String branch, String target) {
    return 'Rebasing $branch onto $target…';
  }

  @override
  String restackBusy(String root) {
    return 'Restacking the branches on $root…';
  }

  @override
  String get stashBusyPush => 'Stashing changes…';

  @override
  String get stashBusyApply => 'Applying stash…';

  @override
  String get stashBusyPop => 'Applying and removing stash…';

  @override
  String get stashBusyDrop => 'Dropping stash…';

  @override
  String get stashBusyRename => 'Renaming stash…';

  @override
  String get stashBusyAutoStashCheckout => 'Stashing changes and checking out…';

  @override
  String get branchIntegrationTitle => 'Integrate branch';

  @override
  String branchIntegrationHint(String branch) {
    return 'Choose how to bring the changes from $branch into your current branch.';
  }

  @override
  String get branchIntegrationRebaseAction => 'Rebase…';

  @override
  String get branchIntegrationMergeAction => 'Merge…';

  @override
  String get branchIntegrationRebaseDetailAny =>
      'Replays your commits on top of the other branch. They get new IDs, so avoid this for commits others already have.';

  @override
  String branchIntegrationRebaseDetail(String branch) {
    return 'Replays your commits on top of $branch. They get new IDs, so avoid this for commits others already have.';
  }

  @override
  String get branchIntegrationRebase => 'Rebase';

  @override
  String get branchIntegrationMergeDetail =>
      'Adds a merge commit that joins both histories. Your commits stay as they are.';

  @override
  String get branchIntegrationMerge => 'Merge';

  @override
  String get branchIntegrationHintAny =>
      'Choose how to bring another branch\'s changes into your current branch.';

  @override
  String get rebaseEditorTitle => 'Interactive rebase';

  @override
  String rebaseInstructionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits, oldest first',
      one: '1 commit, oldest first',
    );
    return '$_temp0';
  }

  @override
  String get rebasePublishedBadge => 'Published';

  @override
  String get rebaseReplacementMessage => 'Replacement commit message';

  @override
  String get rebaseMoveUp => 'Move instruction up';

  @override
  String get rebaseMoveDown => 'Move instruction down';

  @override
  String get rebasePublishedWarning =>
      'I understand that this rewrites published history.';

  @override
  String get rebaseStart => 'Start rebase';

  @override
  String get rebaseEditPlan => 'Edit rebase plan';

  @override
  String get rebasePreviewTitle => 'Review rebase';

  @override
  String get rebaseActionPick => 'Pick';

  @override
  String get rebaseActionReword => 'Reword';

  @override
  String get rebaseActionEdit => 'Edit';

  @override
  String get rebaseActionSquash => 'Squash';

  @override
  String get rebaseActionFixup => 'Fixup';

  @override
  String get rebaseActionDrop => 'Drop';

  @override
  String get rebaseCompleted => 'Rebase completed.';

  @override
  String rebaseConflict(int count) {
    return 'Rebase stopped with $count conflict path(s).';
  }

  @override
  String get rebaseEditStop => 'Rebase stopped at an Edit instruction.';

  @override
  String get rebaseInterrupted => 'The rebase is paused.';

  @override
  String get rebaseStale =>
      'The current commit or the rebase target changed. Review a fresh plan.';

  @override
  String get rebaseFailed => 'The interactive rebase did not complete.';

  @override
  String get historyMutationCompleted => 'History operation completed.';

  @override
  String historyMutationConflict(int count) {
    return 'The operation stopped with $count conflict path(s). Continue in the conflict workflow.';
  }

  @override
  String get historyMutationInterrupted =>
      'The operation is paused. Continue, skip or abort it.';

  @override
  String get historyMutationStale =>
      'Repository state changed after the preview. Review the operation again.';

  @override
  String get historyMutationReconciledWarning =>
      'The operation completed, but the view could not be refreshed.';

  @override
  String get historyMutationFailed => 'The history operation failed.';

  @override
  String get historyMutationFailureInvalid =>
      'The history operation request is invalid.';

  @override
  String get historyMutationFailureDirty =>
      'Commit or stash working-tree changes before changing history.';

  @override
  String get historyMutationFailureDetached =>
      'Check out a branch before changing history.';

  @override
  String get historyMutationFailureActive =>
      'Continue or abort the current Git operation first.';

  @override
  String get historyMutationFailurePublished =>
      'Confirm the published-history warning before continuing.';

  @override
  String get historyMutationFailureCanceled =>
      'The history operation was canceled.';

  @override
  String get conflictResolverTitle => 'Resolve conflicts';

  @override
  String get conflictOperationMerge => 'Merge';

  @override
  String get conflictOperationRebase => 'Rebase';

  @override
  String get conflictOperationCherryPick => 'Cherry-pick';

  @override
  String get conflictOperationRevert => 'Revert';

  @override
  String get conflictOperationSnapshot => 'Snapshot restore';

  @override
  String get conflictOperationStash => 'Stashed changes';

  @override
  String get conflictOperationStandalone => 'Unmerged files';

  @override
  String conflictRegionNumber(int number) {
    return 'Conflict $number';
  }

  @override
  String conflictFileProgress(int current, int total) {
    return 'File $current of $total';
  }

  @override
  String conflictStepProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String conflictCurrent(String label) {
    return 'Current: $label';
  }

  @override
  String conflictIncoming(String label) {
    return 'Incoming: $label';
  }

  @override
  String get conflictAncestor => 'Common ancestor';

  @override
  String get conflictResult => 'Result';

  @override
  String get conflictTakeCurrent => 'Take current';

  @override
  String get conflictTakeIncoming => 'Take incoming';

  @override
  String get conflictRemoveCurrent => 'Remove current';

  @override
  String get conflictRemoveIncoming => 'Remove incoming';

  @override
  String get conflictRemoveBoth => 'Remove both';

  @override
  String get conflictTakeBoth => 'Take both';

  @override
  String get conflictUseCurrentFile => 'Use current file';

  @override
  String get conflictUseIncomingFile => 'Use incoming file';

  @override
  String get conflictKeepDeletion => 'Keep deletion';

  @override
  String get conflictUndoResolution => 'Undo resolution';

  @override
  String get conflictPreviousFile => 'Previous file';

  @override
  String get conflictNextFile => 'Next file';

  @override
  String get conflictContinue => 'Continue';

  @override
  String get conflictSkip => 'Skip';

  @override
  String get conflictAbort => 'Abort';

  @override
  String get conflictAbortTitle => 'Abort Git operation?';

  @override
  String get conflictAbortMessage =>
      'Git puts everything back the way it was before this started. Unsaved edits in the conflict editor are lost.';

  @override
  String get conflictSkipTitle => 'Skip this step?';

  @override
  String get conflictSkipMessage =>
      'Git leaves out the commit it is applying now and moves on to the next one.';

  @override
  String get conflictLoading => 'Loading conflict state…';

  @override
  String get conflictLoadFailed =>
      'Conflict state could not be loaded. Refresh and inspect the repository before continuing.';

  @override
  String get conflictSaveFailed =>
      'The result changed outside GitLama or could not be saved. The conflict state was reloaded.';

  @override
  String get conflictContinueFailed => 'Git could not complete this step.';

  @override
  String get conflictCompleted => 'Git operation completed.';

  @override
  String get conflictAborted => 'Git operation aborted.';

  @override
  String get conflictStoppedAgain =>
      'Git stopped again, at the next conflict or step.';

  @override
  String get conflictAllResolved =>
      'All conflict paths are resolved. Continue when ready.';

  @override
  String get conflictStandaloneResolved =>
      'All unmerged files are resolved. Review the changes before committing.';

  @override
  String get conflictBinaryFile =>
      'This is a binary file. Choose a complete side or open an external merge tool.';

  @override
  String get conflictHugeFile =>
      'This file is too large for the built-in text editor. Choose a complete side or open an external merge tool.';

  @override
  String get conflictExternalTool => 'Open external tool';

  @override
  String get conflictExternalUnavailable =>
      'External merge-tool handoff is not available yet.';

  @override
  String get conflictEmptySide => 'Empty file';

  @override
  String conflictRegionsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unresolved regions',
      one: '1 unresolved region',
    );
    return '$_temp0';
  }

  @override
  String get conflictPreviousRegion => 'Previous conflict';

  @override
  String get conflictNextRegion => 'Next conflict';

  @override
  String get conflictResolveFile => 'Resolve file';

  @override
  String get conflictReviewResult =>
      'Review or edit the result, then resolve this file.';

  @override
  String get conflictSaving => 'Saving…';

  @override
  String get conflictShowAncestor => 'Show ancestor';

  @override
  String get conflictHideAncestor => 'Hide ancestor';

  @override
  String get rebaseAutosquash => 'Combine fixup commits automatically';

  @override
  String get rebaseAutosquashHint =>
      'Commits whose message starts with fixup! or squash! move behind the commit they fix and are combined with it.';

  @override
  String get rebaseDragToSquash => 'Drag onto another commit to squash';

  @override
  String get rebaseDragToReorder => 'Drag to reorder';

  @override
  String rebaseAutosquashApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fixup commits were combined automatically.',
      one: '1 fixup commit was combined automatically.',
    );
    return '$_temp0';
  }

  @override
  String get fixupSuggestionAction => 'Fixup / squash';

  @override
  String get fixupSuggestionFixup => 'Create fixup commit';

  @override
  String get fixupSuggestionSquash => 'Create squash commit';

  @override
  String get fixupSuggestionAmbiguous =>
      'Several commits changed these files. Choose the one your changes belong to.';

  @override
  String get fixupSuggestionPickHint =>
      'GitLama couldn\'t tell which commit these changes fix. Choose one of the commits that changed these files.';

  @override
  String get fixupSuggestionPickTitle => 'Which commit does this fix?';

  @override
  String get fixupSuggestionUnavailable =>
      'GitLama couldn\'t tell which commit these changes fix.';

  @override
  String get fixupSuggestionFailed =>
      'The base-commit evidence could not be loaded.';

  @override
  String get commandRestackBranches => 'Restack dependent branches';

  @override
  String get restackChooseRoot => 'Choose the stack root';

  @override
  String restackPreviewTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restack $count branches',
      one: 'Restack 1 branch',
    );
    return '$_temp0';
  }

  @override
  String get restackIncompleteWarning =>
      'GitLama couldn\'t map the whole stack. Only the branches listed here are restacked.';

  @override
  String get restackPublishedWarning =>
      'I understand that this rewrites published branches, so others may need to update their copies.';

  @override
  String get restackNothingToDo =>
      'All dependent branches are already based on their current parents.';

  @override
  String restackCompleted(int count) {
    return 'Restacked $count branches.';
  }

  @override
  String restackConflict(int completed, int total) {
    return 'Restack stopped at a conflict after $completed of $total branches. Resolve it in Changes, then re-plan to continue.';
  }

  @override
  String restackPartial(int completed, int total) {
    return 'Restack stopped after $completed of $total branches. Re-plan to continue without repeating completed rewrites.';
  }

  @override
  String get restackStale =>
      'The branch tips changed. Review a fresh restack plan.';

  @override
  String get restackCanceled => 'Restack canceled before the next branch.';

  @override
  String get restackFailed => 'The branch restack could not be completed.';

  @override
  String get namedSnapshotsTitle => 'Snapshots';

  @override
  String get namedSnapshotsEmpty => 'No snapshots yet';

  @override
  String get namedSnapshotName => 'Snapshot name';

  @override
  String get namedSnapshotCreate => 'Create snapshot';

  @override
  String get namedSnapshotInspect => 'Inspect';

  @override
  String get namedSnapshotRestore => 'Restore';

  @override
  String get namedSnapshotBranch => 'Create branch';

  @override
  String get namedSnapshotBranchTitle => 'Create branch from snapshot';

  @override
  String get namedSnapshotBranchCreated => 'Branch created from the snapshot.';

  @override
  String get namedSnapshotDeleteTitle => 'Delete snapshot?';

  @override
  String namedSnapshotDeleteMessage(String name) {
    return 'Delete “$name”? The changes saved in it are removed.';
  }

  @override
  String namedSnapshotRestoreTitle(String name) {
    return 'Restore “$name”?';
  }

  @override
  String get namedSnapshotPathsTruncated =>
      'More files change than are listed here.';

  @override
  String get namedSnapshotAcknowledgeReplacement =>
      'I understand that my current changes will be replaced.';

  @override
  String get namedSnapshotNothingToCapture =>
      'There are no changes to capture.';

  @override
  String get namedSnapshotMissing => 'The snapshot\'s saved data is missing.';

  @override
  String get namedSnapshotCorrupt => 'The snapshot metadata is corrupt.';

  @override
  String get namedSnapshotDirtyConflict =>
      'Resolve the current conflicts before creating a snapshot.';

  @override
  String get namedSnapshotActiveOperation =>
      'Finish the active Git operation before creating a snapshot.';

  @override
  String get namedSnapshotStale =>
      'The repository changed. Review a fresh restore preview.';

  @override
  String get namedSnapshotConflict =>
      'Snapshot restore stopped at conflicts. Resolve them in Changes.';

  @override
  String get namedSnapshotCanceled => 'Snapshot operation canceled.';

  @override
  String get namedSnapshotTooLarge =>
      'Snapshot metadata exceeds its safety bound.';

  @override
  String get namedSnapshotFailed => 'The snapshot operation failed.';

  @override
  String get detachedHead => 'Detached HEAD';

  @override
  String compassDetachedAt(String hash) {
    return 'Detached at $hash';
  }

  @override
  String get delete => 'Delete';

  @override
  String get loadMore => 'Load more';

  @override
  String get repositoryExtensionsTitle => 'Repository extensions';

  @override
  String get extensionWorktrees => 'Worktrees';

  @override
  String get extensionWorktreeLocked => 'Locked worktree';

  @override
  String get extensionWorktreeCurrent => 'Current worktree';

  @override
  String get extensionWorktreePath => 'Folder for the worktree';

  @override
  String get extensionWorktreeChooseFolder => 'Choose folder…';

  @override
  String get extensionWorktreeChooseFolderFailure =>
      'Could not open the folder picker. Try again or enter a path.';

  @override
  String get extensionWorktreeReference => 'Branch, tag, or commit';

  @override
  String get extensionWorktreeCreate => 'Create worktree';

  @override
  String get extensionWorktreeDeleteTitle => 'Delete worktree?';

  @override
  String extensionWorktreeDeleteBody(String path) {
    return 'Delete the linked worktree at $path? Unsaved changes or locked worktrees are refused.';
  }

  @override
  String get extensionSubmodules => 'Submodules';

  @override
  String get extensionNone => 'None';

  @override
  String get extensionInitialize => 'Initialize';

  @override
  String get extensionOpen => 'Open';

  @override
  String get extensionUpdate => 'Update';

  @override
  String get extensionSubmoduleRecorded => 'At recorded commit';

  @override
  String get extensionSubmoduleDifferent => 'Checked out at a different commit';

  @override
  String get extensionSubmoduleUninitialized => 'Not initialized';

  @override
  String get extensionSubmoduleConflicted => 'Conflicted';

  @override
  String get extensionLfs => 'Git LFS';

  @override
  String get extensionLfsPull => 'Pull objects';

  @override
  String get extensionLfsUnavailable =>
      'Git LFS is not installed or unavailable.';

  @override
  String get extensionLfsPattern => 'Tracking pattern';

  @override
  String get extensionLfsTrack => 'Track';

  @override
  String get extensionLfsUntrack => 'Untrack';

  @override
  String get extensionInspectPointer => 'Inspect pointer';

  @override
  String get extensionLfsPointerTitle => 'LFS pointer';

  @override
  String get extensionLfsStatePointer => 'Pointer';

  @override
  String get extensionLfsStateMaterialized => 'Materialized';

  @override
  String get extensionLfsStateMissing => 'Missing';

  @override
  String get extensionLfsNotPointer =>
      'This file holds its own content, not an LFS pointer.';

  @override
  String get extensionFailureInvalid => 'The extension request is invalid.';

  @override
  String get extensionFailureUnavailable =>
      'The required tool or capability is unavailable.';

  @override
  String get extensionFailureDirty =>
      'Commit or stash changes in that worktree first.';

  @override
  String get extensionFailureLocked =>
      'Unlock that worktree before removing it.';

  @override
  String get extensionFailureCurrent =>
      'The current worktree cannot be removed.';

  @override
  String get extensionFailureStale =>
      'The repository extension state changed. Refresh and try again.';

  @override
  String get extensionFailureCanceled =>
      'The extension operation was canceled.';

  @override
  String get extensionFailureTooLarge =>
      'The extension result exceeds its safety bound.';

  @override
  String get extensionFailureGit =>
      'The repository extension operation failed.';

  @override
  String get extensionWorktreeCreateDescription =>
      'Check out a branch or commit in its own folder, so you can work on it next to this one.';

  @override
  String get extensionLfsPointerDescription =>
      'Git LFS stores this file\'s content on a server. The repository holds this small pointer to it instead.';

  @override
  String get extensionLfsPointerFile => 'File';

  @override
  String get extensionLfsPointerOid => 'SHA-256';

  @override
  String get extensionLfsPointerSize => 'Size';

  @override
  String get conflictResolvedFiles => 'Resolved files';

  @override
  String get conflictUndoAll => 'Undo all';

  @override
  String get conflictSelectAll => 'Select all';

  @override
  String conflictSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String conflictBulkUseCurrent(int count) {
    return 'Use current ($count)';
  }

  @override
  String conflictBulkUseIncoming(int count) {
    return 'Use incoming ($count)';
  }

  @override
  String get namedSnapshotFactBranch => 'Branch';

  @override
  String get namedSnapshotNoBranch => 'No branch';

  @override
  String get namedSnapshotFactBase => 'Based on commit';

  @override
  String get namedSnapshotFactNewFiles => 'New files';

  @override
  String get namedSnapshotFactId => 'Snapshot ID';

  @override
  String get namedSnapshotsEmptyHelp =>
      'Save your current changes under a name to come back to them later.';

  @override
  String get restackRun => 'Restack branches';

  @override
  String get integrationTitle => 'Integrations';

  @override
  String get integrationDiscovered => 'Found on this computer';

  @override
  String get integrationConfigured => 'Your tools and commands';

  @override
  String get integrationConfigure => 'Add a tool or command';

  @override
  String get integrationKind => 'Use as';

  @override
  String get integrationName => 'Name';

  @override
  String get integrationExecutable => 'Program';

  @override
  String get integrationChooseExecutable => 'Choose program';

  @override
  String get integrationArguments => 'Arguments';

  @override
  String get integrationArgumentsHelp =>
      'One argument per line, passed exactly as written. To insert details, put repository, working_directory, file, current_branch or selected_commit in braces.';

  @override
  String get integrationExplicitShell => 'Run through the system shell';

  @override
  String get integrationConfirm => 'Ask before each run';

  @override
  String get integrationWait => 'Wait until it finishes';

  @override
  String get integrationTimeout => 'Time limit (seconds)';

  @override
  String get integrationValidateSave => 'Check and save';

  @override
  String get integrationPreviewTitle => 'Review exact command';

  @override
  String get integrationRun => 'Run';

  @override
  String get integrationEditor => 'Editor';

  @override
  String get integrationTerminal => 'Terminal';

  @override
  String get integrationFileManager => 'File manager';

  @override
  String get integrationBrowser => 'Browser';

  @override
  String get integrationDiffTool => 'Diff tool';

  @override
  String get integrationMergeTool => 'Merge tool';

  @override
  String get integrationCustom => 'Custom command';

  @override
  String get integrationInvalid =>
      'The tool definition or argument template is invalid.';

  @override
  String get integrationUnavailable =>
      'The selected executable is unavailable.';

  @override
  String get integrationMissingVariable =>
      'A required command variable is unavailable.';

  @override
  String get integrationStale =>
      'Repository state changed. Review the command again.';

  @override
  String get integrationConfirmationRequired =>
      'This command requires explicit confirmation.';

  @override
  String get integrationTimedOut =>
      'The command reached its configured time limit and was stopped.';

  @override
  String get integrationNonZero => 'The command reported a failure.';

  @override
  String get integrationLaunchFailed =>
      'The command could not be started or observed.';

  @override
  String get integrationReadFailed => 'Repository state is unavailable.';

  @override
  String get integrationDiscoveredEmpty => 'No tools found.';

  @override
  String get integrationConfiguredEmpty => 'You haven\'t added any yet.';

  @override
  String get integrationNameHelp =>
      'Shown in menus. Don\'t include passwords or tokens.';

  @override
  String get integrationExplicitShellHelp =>
      'Allows pipes and redirection. GitLama always asks before running it.';

  @override
  String get integrationWaitHelp =>
      'GitLama waits for the program to close before going on. Custom commands always wait.';

  @override
  String get powerToolsTitle => 'Repository tools';

  @override
  String get powerSearchTitle => 'Search changes';

  @override
  String get powerSearchQuery => 'Changed text';

  @override
  String get powerSearchBound =>
      'Finds commits that added or removed exactly this text, in up to 10,000 commits.';

  @override
  String get powerSearchCaseSensitive => 'Match case';

  @override
  String get powerSearchScope => 'Search scope';

  @override
  String get powerSearchAllRefs => 'All branches and tags';

  @override
  String get powerSearchCurrentBranch => 'Current branch';

  @override
  String get powerSearchAction => 'Search';

  @override
  String get powerSearchCancel => 'Cancel search';

  @override
  String get powerSearchIncompleteCommits =>
      'Results are incomplete because the 10,000-commit scan limit was reached.';

  @override
  String get powerSearchIncompleteResults =>
      'Results are incomplete because the 512-result limit was reached.';

  @override
  String powerSearchExamined(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString commits searched',
      one: '1 commit searched',
    );
    return '$_temp0';
  }

  @override
  String get powerStatisticsTitle => 'Repository statistics';

  @override
  String get powerStatisticsLoad => 'Calculate statistics';

  @override
  String get powerStatisticsIncomplete =>
      'Some counts stopped at a limit and may be too low.';

  @override
  String get powerBisectTitle => 'Find a breaking commit';

  @override
  String get powerBisectGood => 'Commit that works';

  @override
  String get powerBisectBad => 'Commit with the problem';

  @override
  String get powerBisectStart => 'Start search';

  @override
  String get powerBisectMarkGood => 'Works';

  @override
  String get powerBisectMarkBad => 'Has the problem';

  @override
  String get powerBisectSkip => 'Skip';

  @override
  String get powerBisectReset => 'End search';

  @override
  String powerBisectProgress(int tested, int remaining) {
    final intl.NumberFormat testedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String testedString = testedNumberFormat.format(tested);
    final intl.NumberFormat remainingNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String remainingString = remainingNumberFormat.format(remaining);

    return '$testedString tested · about $remainingString left';
  }

  @override
  String get powerFailed => 'The repository tool could not complete.';

  @override
  String powerSearchFound(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString commits found',
      one: '1 commit found',
      zero: 'No matching commits',
    );
    return '$_temp0';
  }

  @override
  String get powerStatisticsCommits => 'Commits';

  @override
  String get powerStatisticsBranches => 'Local branches';

  @override
  String get powerStatisticsTags => 'Tags';

  @override
  String get powerStatisticsChangedFiles => 'Files changed';

  @override
  String get powerBisectHelp =>
      'Name a commit that works and one that has the problem. GitLama checks out commits in between for you to test, until it finds the first one with the problem.';

  @override
  String get powerBisectTesting => 'Commit to test';

  @override
  String get powerBisectProgressLabel => 'Progress';

  @override
  String get powerBisectQuestion => 'Does this commit have the problem?';

  @override
  String get bisectConfirmGood => 'Mark as working';

  @override
  String get bisectConfirmBad => 'Mark as broken';

  @override
  String get bisectStartTitle => 'Start the search for the breaking commit?';

  @override
  String get bisectGoodTitle => 'Mark this commit as working?';

  @override
  String get bisectBadTitle => 'Mark this commit as broken?';

  @override
  String get bisectSkipTitle => 'Skip this commit?';

  @override
  String get bisectResetTitle => 'End the search?';

  @override
  String get hostingAccounts => 'Hosting connections';

  @override
  String get hostingAddConnection => 'Add connection';

  @override
  String get hostingNoConnections => 'No hosting connections configured.';

  @override
  String get hostingPreset => 'Provider preset';

  @override
  String get hostingConnectionId => 'Connection name';

  @override
  String get hostingConnectBeforeBinding =>
      'Add a hosting account before linking this repository.';

  @override
  String get hostingWebUrl => 'Web base URL';

  @override
  String get hostingApiUrl => 'API base URL';

  @override
  String get hostingOAuthClientId => 'OAuth client ID';

  @override
  String get hostingGuideAction => 'How to connect this provider';

  @override
  String hostingGuideTitle(String provider) {
    return 'Connect $provider';
  }

  @override
  String get hostingGuideCliNote =>
      'GitLama uses the CLI\'s current sign-in, so no OAuth application is needed.';

  @override
  String get hostingGuideEnterpriseNote =>
      'If GitHub CLI is installed, you can use its sign-in instead.';

  @override
  String get hostingGuideForgejoNote =>
      'Your server administrator may restrict app registration.';

  @override
  String get hostingGuideNoSecret => 'No client secret is needed.';

  @override
  String hostingStepAuthorizeBrowser(String action) {
    return 'Select $action. GitLama opens your browser to finish signing in.';
  }

  @override
  String hostingStepAuthorizeDevice(String action) {
    return 'Select $action. GitLama opens GitHub and shows a code to enter there.';
  }

  @override
  String hostingStepCopyApplicationId(String field) {
    return 'Copy its Application ID into the $field field.';
  }

  @override
  String hostingStepCopyClientId(String field) {
    return 'Copy its Client ID into the $field field.';
  }

  @override
  String get hostingStepRedirect => 'Add this redirect URI to the application:';

  @override
  String get hostingStepDeviceFlow => 'Turn on Device Flow for the app.';

  @override
  String get hostingStepCreateCodeberg =>
      'In Codeberg, open Settings → Applications → Manage OAuth2 Applications and create an application.';

  @override
  String get hostingStepCreateForgejo =>
      'On your server, open Settings → Applications and create an OAuth2 application.';

  @override
  String get hostingStepCreateGitLab =>
      'In GitLab, open your profile → Access → Applications and create an application.';

  @override
  String get hostingStepCreateEnterprise =>
      'On your server, open Developer settings → OAuth Apps and create an OAuth app, or ask your organization for the Client ID of an existing one.';

  @override
  String get hostingStepCreateGitHub =>
      'In GitHub, open Developer settings → OAuth Apps and create an OAuth app.';

  @override
  String hostingStepEnterServer(String field) {
    return 'Enter your server\'s address in the $field field.';
  }

  @override
  String hostingStepCliReturn(String action) {
    return 'Come back here and select $action.';
  }

  @override
  String hostingStepCliSignIn(String tool) {
    return 'In a terminal, sign in to this server with $tool:';
  }

  @override
  String get hostingGuideServerPlaceholder => 'your-server';

  @override
  String get hostingGuideOpenSettings => 'Open application settings';

  @override
  String get hostingGuideEnterName => 'Enter a connection name.';

  @override
  String get hostingGuideEnterClientId =>
      'Enter the OAuth client ID. Open the setup guide to find it.';

  @override
  String get hostingGuideEnterServer =>
      'Enter a valid server URL to fill in the API URL.';

  @override
  String get hostingGuideNameInUse =>
      'A connection with this name already exists. Choose another name.';

  @override
  String get hostingAuthenticationMethod => 'Authentication method';

  @override
  String get hostingOAuthApplication => 'OAuth application';

  @override
  String get hostingGitHubCli => 'GitHub CLI';

  @override
  String get hostingGitHubCliHint =>
      'Uses the GitHub CLI account for this host. GitLama does not copy its token into its own credential store.';

  @override
  String get hostingConnectWithCli => 'Connect with GitHub CLI';

  @override
  String get hostingGitLabCli => 'GitLab CLI';

  @override
  String get hostingGitLabCliHint =>
      'Uses the GitLab CLI account for this host. GitLama does not copy its token into its own credential store.';

  @override
  String get hostingConnectWithGitLabCli => 'Connect with GitLab CLI';

  @override
  String get hostingSaveAuthorize => 'Save and authorize';

  @override
  String get hostingReauthorize => 'Reauthorize';

  @override
  String get hostingRemove => 'Remove connection';

  @override
  String get hostingEnabled => 'Connection enabled';

  @override
  String get hostingStateEnabled => 'Enabled';

  @override
  String get hostingStateDisabled => 'Disabled';

  @override
  String get hostingBackgroundRefresh => 'Background refresh';

  @override
  String get hostingAuthorizationWaiting =>
      'Waiting for provider authorization…';

  @override
  String hostingAuthorizationCode(String code) {
    return 'Device code: $code';
  }

  @override
  String get hostingOpenBrowser => 'Open in browser';

  @override
  String get hostingBinding => 'Repository binding';

  @override
  String get hostingAutomaticBinding => 'Use automatic binding';

  @override
  String get hostingNoBinding =>
      'No connection matches this repository remote.';

  @override
  String get hostingAmbiguousBinding =>
      'More than one connection matches this remote. Choose one explicitly.';

  @override
  String get hostingConnection => 'Connection';

  @override
  String get hostingRemote => 'Remote';

  @override
  String get hostingProviderRepository => 'Provider repository';

  @override
  String get hostingSaveBinding => 'Save binding override';

  @override
  String get hostingResources => 'Provider resources';

  @override
  String get hostingFilter => 'Filter pull requests and issues';

  @override
  String get hostingChangeRequests => 'Pull requests';

  @override
  String repositoryTitleInGroup(String group, String repository) {
    return '$group / $repository';
  }

  @override
  String get hostingPullRequestMerged => 'Merged';

  @override
  String get hostingPullRequestYours => 'Yours';

  @override
  String hostingPullRequestBranches(String source, String target) {
    return '$source into $target';
  }

  @override
  String get hostingIssues => 'Issues';

  @override
  String get hostingRefresh => 'Refresh';

  @override
  String get hostingLoadMore => 'Load more';

  @override
  String get hostingLoadingCached =>
      'Refreshing; cached results remain available.';

  @override
  String get hostingEmpty => 'No provider resources found.';

  @override
  String get hostingStale => 'Cached';

  @override
  String get hostingCheckout => 'Check out';

  @override
  String get hostingReview => 'Review';

  @override
  String get hostingCreateChangeRequest => 'Create pull request';

  @override
  String get hostingCapabilityUnavailable =>
      'This provider connection does not support this action.';

  @override
  String get hostingForkCheckoutUnavailable =>
      'Fetch the fork branch before checking it out.';

  @override
  String hostingFailure(String reason) {
    return 'Provider request failed: $reason';
  }

  @override
  String get hostingFailureNotFound =>
      'The server does not know this address. Check the API base URL and the repository name, and that this account can access the repository.';

  @override
  String get hostingFailureRedirected =>
      'The server redirected the request. The repository may have been renamed or moved, or the API base URL is wrong.';

  @override
  String get hostingFailureServerError =>
      'The server reported an internal error. Try again later.';

  @override
  String get hostingFailureNetwork =>
      'The server could not be reached. Check the network connection, VPN and proxy.';

  @override
  String get hostingFailureCertificate =>
      'The secure connection could not be established. Check that the curl on your PATH trusts the server certificate.';

  @override
  String get hostingFailureTimedOut => 'The server did not answer in time.';

  @override
  String get hostingSettingsFailure =>
      'The hosting settings could not be saved.';

  @override
  String get hostingReferenceEmpty => 'No matching pull requests or issues.';

  @override
  String hostingReviewTitle(int number) {
    return 'Review #$number';
  }

  @override
  String get hostingReviewThreads => 'Review comments';

  @override
  String get hostingReviewReanchor => 'Re-anchor';

  @override
  String get hostingReviewOutdated => 'Outdated';

  @override
  String hostingReviewInlineTitle(int line) {
    return 'Comment on line $line';
  }

  @override
  String get hostingReviewInlineSave => 'Add to review';

  @override
  String get hostingReviewComment => 'Review text';

  @override
  String get hostingReviewAction => 'Review action';

  @override
  String get hostingReviewCommentAction => 'Comment';

  @override
  String get hostingReviewApprove => 'Approve';

  @override
  String get hostingReviewRequestChanges => 'Request changes';

  @override
  String get hostingReviewPreview => 'Preview review';

  @override
  String get hostingReviewAuthorize => 'Submit this review?';

  @override
  String get hostingRequestDetails => 'Request details';

  @override
  String get hostingReviewInlineComments => 'Line comments';

  @override
  String hostingReviewAuthorizeSummary(int number) {
    return 'GitLama posts your review to #$number.';
  }

  @override
  String get hostingReviewSubmit => 'Submit review';

  @override
  String get hostingReviewNoDiff => 'No review diff is available.';

  @override
  String get hostingReviewLoadFailed => 'Could not load this review.';

  @override
  String hostingReviewFailure(String reason) {
    return 'Review failed: $reason';
  }

  @override
  String get hostingChecks => 'Checks';

  @override
  String get hostingCheckRetry => 'Re-run';

  @override
  String get hostingCheckRetryAuthorize => 'Run this check again?';

  @override
  String hostingCheckRetrySummary(String name) {
    return 'GitLama asks the provider to run $name again.';
  }

  @override
  String get cliForwardingFailed =>
      'GitLama could not forward the command safely.';

  @override
  String galleryStatus(int count, String menu) {
    return 'Activations: $count · Menu: $menu';
  }

  @override
  String get stageHunk => 'Stage hunk';

  @override
  String get unstageHunk => 'Unstage hunk';

  @override
  String get discardHunk => 'Discard hunk';

  @override
  String get transferForceHelp =>
      'For commits you have rewritten. Refused if someone else pushed to it since your last fetch.';

  @override
  String get gallerySectionButton => 'Button';

  @override
  String get gallerySectionIconButton => 'IconButton';

  @override
  String get gallerySectionToolbarButton => 'ToolbarButton';

  @override
  String get gallerySectionCheckbox => 'Checkbox';

  @override
  String get gallerySectionSegmented => 'Segmented';

  @override
  String get gallerySectionSelect => 'Select';

  @override
  String get gallerySectionTextField => 'TextField';

  @override
  String get gallerySectionCompass => 'Compass';

  @override
  String get gallerySectionPalette => 'Palette';

  @override
  String get gallerySectionRepoTabs => 'RepoTabs';

  @override
  String get gallerySectionSidebarRow => 'SidebarRow';

  @override
  String get gallerySectionAvatar => 'Avatar';

  @override
  String get gallerySectionCommitRow => 'CommitRow';

  @override
  String get gallerySectionComposer => 'Composer';

  @override
  String get gallerySectionDiffHunk => 'DiffHunk';

  @override
  String get galleryDiffSampleHunk => '@@ -169,3 +169,12 @@ jobs:';

  @override
  String get galleryDiffSampleContext => '  run: |';

  @override
  String get galleryDiffSampleDeleted => '    old_value = 1';

  @override
  String get galleryDiffSampleAdded => '    new_value = 2';

  @override
  String get galleryDiffSamplePath => 'lib/app/main.dart';

  @override
  String get gallerySectionFileRow => 'FileRow';

  @override
  String get gallerySectionGraph => 'Graph';

  @override
  String get gallerySectionRefChip => 'RefChip';

  @override
  String get gallerySectionStatusGlyph => 'StatusGlyph';

  @override
  String get gallerySectionSyncBadge => 'SyncBadge';

  @override
  String get gallerySectionBanner => 'Banner';

  @override
  String get gallerySectionKbd => 'Kbd';

  @override
  String get gallerySectionLogbook => 'Logbook';

  @override
  String get gallerySectionDialog => 'Dialog';

  @override
  String get gallerySectionIsland => 'Island';

  @override
  String get gallerySectionSettingsRow => 'SettingsRow';

  @override
  String get galleryPaletteMove => 'Move';

  @override
  String get galleryPaletteRun => 'Run';

  @override
  String get galleryPaletteBackground => 'Run in background';

  @override
  String get galleryPaletteScope => 'Scope';

  @override
  String get galleryCommitToMain => 'Commit to main';

  @override
  String get galleryPush => 'Push';

  @override
  String get galleryCopyHash => 'Copy hash';

  @override
  String get galleryDiscardThreeFiles => 'Discard 3 files';

  @override
  String get galleryDiscard => 'Discard';

  @override
  String get galleryFetching => 'Fetching…';

  @override
  String get galleryPull => 'Pull';

  @override
  String get galleryCommit => 'Commit';

  @override
  String get galleryStageHunk => 'Stage hunk';

  @override
  String get galleryShowAllFiles => 'Show all 42 files';

  @override
  String get galleryFilter => 'Filter';

  @override
  String get gallerySideBySide => 'Side by side';

  @override
  String get galleryUnified => 'Unified';

  @override
  String get galleryMore => 'More';

  @override
  String get galleryCopy => 'Copy';

  @override
  String get galleryStage => 'Stage';

  @override
  String get galleryDelete => 'Delete';

  @override
  String get galleryFetch => 'Fetch';

  @override
  String get galleryStash => 'Stash';

  @override
  String get galleryBranch => 'Branch';

  @override
  String get galleryMerge => 'Merge';

  @override
  String get gallerySignCommit => 'Sign commit';

  @override
  String get galleryAmend => 'Amend';

  @override
  String get galleryStageAllMixed => 'Stage all (2 of 5)';

  @override
  String get galleryBypassHooks => 'Bypass hooks';

  @override
  String get galleryFetchAutomatically => 'Fetch automatically';

  @override
  String get galleryIncludeTags => 'Include tags';

  @override
  String get galleryModified => 'Modified';

  @override
  String get galleryAdded => 'Added';

  @override
  String get galleryDeleted => 'Deleted';

  @override
  String get galleryRenamed => 'Renamed';

  @override
  String get galleryCopied => 'Copied';

  @override
  String get galleryConflict => 'Conflict';

  @override
  String get galleryUntracked => 'Untracked';

  @override
  String get galleryIgnored => 'Ignored';

  @override
  String get galleryTwoConflicts => '2 conflicts';

  @override
  String get galleryMichaelLamers => 'Michael Lamers';

  @override
  String get galleryGitLamaReleaseBot => 'GitLama Release Bot';

  @override
  String get galleryAuthorHandle => 'ada';

  @override
  String get galleryAdaGit => 'Ada Git';

  @override
  String get gallerySearchCommits => 'Search commits, authors, hashes';

  @override
  String get galleryRefPlaceholder => 'refs/heads/main';

  @override
  String get galleryRefValue => 'feature/spline-graph';

  @override
  String get galleryInvalidRef => 'feature/..bad';

  @override
  String get galleryInvalidRefMessage => 'Branch names cannot contain “..”';

  @override
  String get galleryRebasePaused => 'Rebase paused at 3 of 7.';

  @override
  String get galleryRebaseConflicts =>
      '2 files still have conflicts in lib/app.';

  @override
  String get galleryAbort => 'Abort';

  @override
  String get galleryContinue => 'Continue';

  @override
  String get galleryPushRejected => 'Push rejected.';

  @override
  String get galleryPushRejectedMessage =>
      'origin/main has 6 commits you don’t have.';

  @override
  String get galleryPullFirst => 'Pull first';

  @override
  String get galleryAuthFailed => 'Authentication failed for git.example.com.';

  @override
  String get galleryTokenExpired => 'The token expired on 24 Sep.';

  @override
  String get galleryUpdateCredentials => 'Update credentials';

  @override
  String get galleryLfsMessage =>
      'This repository uses Git LFS. 14 files are pointers until you fetch them.';

  @override
  String get galleryDiffLayout => 'Diff layout';

  @override
  String get galleryFileList => 'File list';

  @override
  String get gallerySplit => 'Split';

  @override
  String get galleryList => 'List';

  @override
  String get galleryTree => 'Tree';

  @override
  String get galleryThemeSystem => 'System';

  @override
  String get galleryDates => 'Dates';

  @override
  String get galleryRemotes => 'Remotes';

  @override
  String get galleryDensityHelp =>
      'Changes row height only. Text and icons stay the same size.';

  @override
  String get galleryRemotesHelp =>
      'Every 10 minutes, in the background. Shown in the Logbook.';

  @override
  String get galleryRebaseTitle =>
      'Rebase windows-soak-cleanup onto origin/main';

  @override
  String get galleryRebaseDescription =>
      '4 commits will be replayed on top of 6 new commits from origin/main.';

  @override
  String get galleryAutostash => 'Autostash';

  @override
  String get galleryRebase => 'Rebase';

  @override
  String get galleryFourCommits => '4 commits';

  @override
  String get galleryFocusedIsland =>
      'Focused island: 1px polar-soft halo, solid polar selection.';

  @override
  String get galleryUnfocusedIsland =>
      'Unfocused island: selection drops to polar-soft.';

  @override
  String get galleryDetail => 'Detail';

  @override
  String get galleryPaletteQuery => 'reb';

  @override
  String get galleryPaletteCommands => 'Commands';

  @override
  String get galleryPaletteBranches => 'Branches';

  @override
  String get galleryPaletteRecent => 'Recent';

  @override
  String get galleryPaletteRebaseTarget =>
      'Rebase windows-soak-cleanup onto origin/main';

  @override
  String get galleryPaletteInteractiveRebase => 'Interactive rebase…';

  @override
  String get galleryPaletteLastCommits => 'last 5 commits';

  @override
  String get galleryPaletteBranchRef => 'feature/rebuild-graph-cache';

  @override
  String get galleryPaletteOrigin => 'origin';

  @override
  String get galleryPaletteAbortRebase => 'Abort rebase';

  @override
  String get galleryPaletteYesterday => 'yesterday';

  @override
  String compassConflicts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicts',
      one: '1 conflict',
    );
    return '$_temp0';
  }

  @override
  String compassChangedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changed files',
      one: '1 changed file',
    );
    return '$_temp0';
  }

  @override
  String get repositoryDetailsTitle => 'Repository details';

  @override
  String get repositoryDetailsLocation => 'Location';

  @override
  String get repositoryDetailsThisComputer => 'This computer';

  @override
  String repositoryDetailsHostWithAlias(String host, String alias) {
    return '$host ($alias)';
  }

  @override
  String get repositoryDetailsDisconnected => 'disconnected';

  @override
  String get repositoryDetailsPath => 'Path';

  @override
  String get repositoryDetailsGroup => 'Tab group';

  @override
  String get repositoryDetailsKind => 'Type';

  @override
  String get repositoryDetailsWorktree => 'Repository with working tree';

  @override
  String get repositoryDetailsLinkedWorktree => 'Linked working tree';

  @override
  String get repositoryDetailsBare => 'Bare repository';

  @override
  String get repositoryDetailsBranch => 'Branch';

  @override
  String get repositoryDetailsUnborn => 'no commits yet';

  @override
  String get repositoryDetailsUpstream => 'Upstream';

  @override
  String get repositoryDetailsNoUpstream => 'Not tracking a remote branch';

  @override
  String get repositoryDetailsChanges => 'Changes';

  @override
  String get repositoryDetailsClean => 'No changes';

  @override
  String get repositoryDetailsInProgress => 'Git operation';

  @override
  String get repositoryDetailsRunning => 'Activity';

  @override
  String get repositoryDetailsIdle => 'Nothing running';

  @override
  String get repositoryDetailsHealthClean => 'Working tree clean';

  @override
  String get repositoryDetailsHealthChanged => 'Changes to commit';

  @override
  String get repositoryDetailsHealthConflicted => 'Conflicts to resolve';

  @override
  String get repositoryDetailsHealthPaused => 'Git operation paused';

  @override
  String get repositoryDetailsHealthBusy => 'Working…';

  @override
  String get repositoryDetailsGit => 'Git version';

  @override
  String get repositoryCopyPath => 'Copy path';

  @override
  String get repositoryPathCopied => 'Repository path copied.';

  @override
  String commandPaletteShortcutTooltip(String shortcut) {
    return 'Commands ($shortcut)';
  }

  @override
  String compassSemantics(
    String repository,
    String branch,
    int ahead,
    int behind,
    int dirty,
    int conflicts,
  ) {
    return '$repository, $branch, $ahead ahead, $behind behind, $dirty changed files, $conflicts conflicts. Show repository details.';
  }

  @override
  String get logbookTitle => 'Logbook';

  @override
  String get commandEditBranch => 'Edit branch…';

  @override
  String get editBranchName => 'Name';

  @override
  String get editBranchUpstream => 'Upstream';

  @override
  String get editBranchNoUpstream => 'Leave empty to track no remote branch.';

  @override
  String get editBranchSave => 'Save';

  @override
  String get editBranchNameExists => 'A branch with this name already exists.';

  @override
  String get editBranchDescription =>
      'Rename the local branch or change the remote branch it tracks.';

  @override
  String refConfirmSetUpstream(String name, String upstream) {
    return 'Set $upstream as the upstream of $name.';
  }

  @override
  String refConfirmUnsetUpstream(String name) {
    return 'Remove the upstream of $name. The remote branch is unchanged.';
  }

  @override
  String get diffSelectionCopied => 'Selection copied.';

  @override
  String get diffSelectionStage => 'Stage';

  @override
  String get diffSelectionUnstage => 'Unstage';

  @override
  String get diffSelectionDiscard => 'Discard Changes…';

  @override
  String get diffCopyLines => 'Copy';

  @override
  String get diffCopyAsPatch => 'Copy as Patch';

  @override
  String get diffPatchCopied => 'Patch copied.';

  @override
  String get diffPatchUnavailable => 'The selected lines contain no changes.';

  @override
  String get transferFetchDescription =>
      'Fetch the latest changes from a remote.';

  @override
  String get transferPullDescription =>
      'Fetch a remote branch and integrate it into the current branch.';

  @override
  String get transferPushDescription => 'Publish a local branch on a remote.';

  @override
  String get transferPushTagDescription =>
      'Publish a tag on a remote so others can fetch it.';

  @override
  String get transferDeleteBranchDescription =>
      'Delete a branch on a remote. It is deleted only if it has not moved since the last fetch. Others may already have fetched it.';

  @override
  String get editBranchUpstreamUnknown =>
      'Choose a fetched remote branch, or leave the field empty.';

  @override
  String get changesExpandFolder => 'Expand folder';

  @override
  String get changesCollapseFolder => 'Collapse folder';

  @override
  String get extensionWorktreeDeleteAction => 'Delete worktree…';

  @override
  String get repositoryTabChangeIcon => 'Change icon…';

  @override
  String get repositoryTabRemoveIcon => 'Remove icon';

  @override
  String get repositoryIconTitle => 'Repository icon';

  @override
  String get repositoryIconDescription =>
      'Shown in the repository\'s tab so you can find it at a glance.';

  @override
  String get repositoryIconSymbol => 'Icon';

  @override
  String get repositoryIconColor => 'Color';

  @override
  String get repositoryIconImage => 'Image file';

  @override
  String get repositoryIconNone => 'No icon';

  @override
  String get repositoryIconChooseImage => 'Choose image…';

  @override
  String get repositoryIconRemoveImage => 'Remove image';

  @override
  String get repositoryIconImageHint =>
      'PNG, JPEG, GIF, WebP, BMP, ICO or SVG, up to 2 MB. An image replaces the icon.';

  @override
  String get repositoryIconImageUnreadable =>
      'This image can\'t be used. Choose a supported file up to 2 MB.';

  @override
  String get repositoryIconSave => 'Save';

  @override
  String get repositoryIconSaveFailed => 'The icon couldn\'t be saved.';

  @override
  String get repositoryIconNameRepository => 'Repository';

  @override
  String get repositoryIconNameCode => 'Code';

  @override
  String get repositoryIconNameTerminal => 'Terminal';

  @override
  String get repositoryIconNamePackage => 'Package';

  @override
  String get repositoryIconNameComponents => 'Components';

  @override
  String get repositoryIconNamePlugin => 'Plugin';

  @override
  String get repositoryIconNameLayers => 'Layers';

  @override
  String get repositoryIconNameDocumentation => 'Documentation';

  @override
  String get repositoryIconNameDesign => 'Design';

  @override
  String get repositoryIconNameMedia => 'Media';

  @override
  String get repositoryIconNameMobile => 'Mobile';

  @override
  String get repositoryIconNameDesktop => 'Desktop';

  @override
  String get repositoryIconNameServer => 'Server';

  @override
  String get repositoryIconNameCloud => 'Cloud';

  @override
  String get repositoryIconNameLightning => 'Lightning';

  @override
  String get repositoryIconNameStar => 'Star';

  @override
  String get repositoryIconNameFlag => 'Flag';

  @override
  String get repositoryIconNameBug => 'Bug';

  @override
  String get repositoryIconNameMagic => 'Magic';

  @override
  String get repositoryIconNameLearning => 'Learning';

  @override
  String get repositoryIconNameSecurity => 'Security';

  @override
  String get repositoryIconNameAnalytics => 'Analytics';

  @override
  String get repositoryIconNameHome => 'Home';

  @override
  String get repositoryIconNameTeam => 'Team';

  @override
  String get repositoryColorBlue => 'Blue';

  @override
  String get repositoryColorTeal => 'Teal';

  @override
  String get repositoryColorAmber => 'Amber';

  @override
  String get repositoryColorOrange => 'Orange';

  @override
  String get repositoryColorRose => 'Rose';

  @override
  String get repositoryColorViolet => 'Violet';

  @override
  String get repositoryColorCyan => 'Cyan';

  @override
  String get repositoryColorOlive => 'Olive';

  @override
  String get repositoryColorNone => 'No color';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsUpdatesDetail =>
      'Choose which releases you receive and check for a newer version.';

  @override
  String get updatesInstalledVersion => 'Installed version';

  @override
  String updatesVersionAndBuild(String version, int build) {
    return '$version (build $build)';
  }

  @override
  String get updatesChannel => 'Release channel';

  @override
  String get updatesChannelStable => 'Stable';

  @override
  String get updatesChannelBeta => 'Beta';

  @override
  String get updatesChannelHint => 'Beta also includes every stable release.';

  @override
  String get updatesCheck => 'Check for updates';

  @override
  String get updatesChecking => 'Checking for updates…';

  @override
  String updatesUpToDate(String version, int build) {
    return 'GitLama $version (build $build) is up to date.';
  }

  @override
  String get updatesNoRelease =>
      'No release has been published for this channel yet.';

  @override
  String updatesAvailable(String version, int build) {
    return 'GitLama $version (build $build) is available. Download it from the releases page.';
  }

  @override
  String get updatesOpenDownloads => 'Open downloads page';

  @override
  String get updatesAutomaticHint =>
      'GitLama looks for updates in the background and installs one after you confirm.';

  @override
  String get updatesManualHint =>
      'GitLama contacts the release site only when you check. Install the download yourself.';

  @override
  String get updatesFailureUnavailable =>
      'The release site could not be reached. Try again later.';

  @override
  String get updatesFailureInvalid => 'The release list could not be read.';

  @override
  String get updatesFailureUpdater => 'The updater could not start.';

  @override
  String get updatesFailureOpen => 'The downloads page could not be opened.';

  @override
  String get updatesFailureUnsupported =>
      'This build cannot check for updates.';

  @override
  String get diffCreatePatch => 'Create patch from this diff';

  @override
  String get historyAllChanges => 'All changes';

  @override
  String get historyAllChangesTooLarge => 'Too large';

  @override
  String menuSelectedCommits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected commits',
      one: '1 selected commit',
    );
    return '$_temp0';
  }

  @override
  String menuSelectedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected files',
      one: '1 selected file',
    );
    return '$_temp0';
  }

  @override
  String get patchCreateFromSelection => 'Create patch from selection';

  @override
  String get patchCreateFromCommit => 'Create patch from this commit';

  @override
  String get patchCreateFromFile => 'Create patch from this file';

  @override
  String get windowMinimize => 'Minimize window';

  @override
  String get windowMaximize => 'Maximize or restore window';

  @override
  String get windowClose => 'Close window';

  @override
  String get repositoryTabRename => 'Rename tab…';

  @override
  String get repositoryTabResetName => 'Use folder name';

  @override
  String get repositoryTabRenameLabel => 'Tab name';

  @override
  String get tabGroupAddToNew => 'Add to new group';

  @override
  String get tabGroupAddTo => 'Add to group';

  @override
  String get tabGroupNew => 'New group';

  @override
  String get tabGroupRemoveTab => 'Remove from group';

  @override
  String get tabGroupRename => 'Rename group…';

  @override
  String get tabGroupColor => 'Color';

  @override
  String get tabGroupIcon => 'Icon';

  @override
  String get tabGroupEdit => 'Edit group…';

  @override
  String get tabGroupEditTitle => 'Edit group';

  @override
  String get tabGroupEditDescription =>
      'Name, color and icon of the group\'s chip in the tab bar.';

  @override
  String get tabGroupEditName => 'Name';

  @override
  String get tabGroupEditPreview => 'Preview of the group in the tab bar';

  @override
  String get tabGroupEditSave => 'Save';

  @override
  String get repositoryColorCustom => 'Custom color';

  @override
  String get colorPickerWheel => 'Hue and saturation';

  @override
  String get colorPickerHue => 'Hue';

  @override
  String get colorPickerSaturation => 'Saturation';

  @override
  String get colorPickerBrightness => 'Brightness';

  @override
  String get colorPickerRed => 'Red';

  @override
  String get colorPickerGreen => 'Green';

  @override
  String get colorPickerBlue => 'Blue';

  @override
  String get colorPickerModel => 'Color model';

  @override
  String get colorPickerHsb => 'HSB';

  @override
  String get colorPickerRgb => 'RGB';

  @override
  String get colorPickerHex => 'Hex value';

  @override
  String get colorPickerInvalidHex => 'Enter six hex digits, such as #18304F';

  @override
  String get colorPickerOriginal => 'Original color';

  @override
  String get colorPickerNew => 'New color';

  @override
  String repositoryColorCustomValue(String hex) {
    return 'Custom $hex';
  }

  @override
  String colorPickerSwatch(String hex) {
    return 'Color $hex';
  }

  @override
  String colorPickerDegrees(int value) {
    return '$value°';
  }

  @override
  String colorPickerPercent(int value) {
    return '$value%';
  }

  @override
  String get repositoryTabMoveLeft => 'Move tab left';

  @override
  String get repositoryTabMoveRight => 'Move tab right';

  @override
  String get repositoryTabUnsaved => 'uncommitted changes';

  @override
  String get tabGroupCollapseAction => 'Collapse group';

  @override
  String get tabGroupExpandAction => 'Expand group';

  @override
  String get tabGroupUngroup => 'Ungroup';

  @override
  String get tabGroupClose => 'Close group';

  @override
  String get tabGroupNamePlaceholder => 'Name this group';

  @override
  String get tabGroupRenameLabel => 'Group name';

  @override
  String tabGroupUnnamed(String color) {
    return '$color group';
  }

  @override
  String tabGroupExpand(String name) {
    return 'Expand $name';
  }

  @override
  String tabGroupCollapse(String name) {
    return 'Collapse $name';
  }

  @override
  String tabGroupSemantics(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tabs',
      one: '1 tab',
    );
    return '$name, tab group, $_temp0';
  }

  @override
  String get changesFilterPlaceholder => 'Filter files';

  @override
  String get changesFilterLabel => 'Filter changed files';

  @override
  String get changesFilterClear => 'Clear filter';

  @override
  String changesFilterCount(int shown, int total) {
    return '$shown of $total';
  }

  @override
  String get changesFilterNoMatches => 'No matching files';

  @override
  String get stageShown => 'Stage shown files';

  @override
  String get unstageShown => 'Unstage shown files';

  @override
  String get stageShortShown => 'Stage shown';

  @override
  String get unstageShortShown => 'Unstage shown';

  @override
  String get discardShown => 'Discard shown files';

  @override
  String get historyRevertCommit => 'Revert commit';

  @override
  String get historyRevertCommitNow => 'Commit revert';

  @override
  String get historyRevertApplyOnly => 'Apply without committing';

  @override
  String get historyRevertApplySingleRequired =>
      'Applying without committing works with one commit at a time.';

  @override
  String get historyRevertCleanRequired =>
      'Commit or stash your changes first: reverting needs a clean working tree.';

  @override
  String get historyRevertApplied =>
      'Revert applied. Review the staged changes before committing.';

  @override
  String get historyRevertMergeUnsupported =>
      'This selection contains a merge commit. Reverting a merge requires choosing a mainline parent, which is not supported here yet.';

  @override
  String get menuRepository => 'Repository';

  @override
  String get menuChanges => 'Changes and commits';

  @override
  String get menuHistory => 'History';

  @override
  String get menuBranches => 'Branches and tags';

  @override
  String get menuRemotes => 'Remotes and sync';

  @override
  String get menuRecovery => 'Recovery and conflicts';

  @override
  String get menuTools => 'Tools';

  @override
  String get menuView => 'View';

  @override
  String get menuApplication => 'Application';

  @override
  String get menuRebase => 'Rebase';

  @override
  String get menuDiff => 'Diff';

  @override
  String get menuActivity => 'Activity';

  @override
  String get diffLargeFileInformation =>
      'File exceeds the 8 MiB preview limit. Only file information is shown.';

  @override
  String diffFileSize(String size) {
    return 'Size: $size';
  }

  @override
  String diffFileType(String extension) {
    return 'File type: $extension';
  }

  @override
  String get diffFileTypeUnknown => 'Unknown';

  @override
  String get aboutApp => 'About GitLama';

  @override
  String get aboutSourceCode => 'Source code on GitHub';

  @override
  String get aboutSourceCodeOpenFailed =>
      'The source code page could not be opened.';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get brandTooltip => 'GitLama · by Devmil Solutions';

  @override
  String get brandMaker => 'by Devmil Solutions';

  @override
  String get lamaFamily => 'The Lama family';

  @override
  String get brandWelcome => 'Open a repository.';

  @override
  String get lamaFamilyNames =>
      'GitLama · ProcessLama · MailLama · ShotLama · NoteLama';

  @override
  String get openRemoteRepository => 'Open Remote Repository…';

  @override
  String get remoteCommandUnsupported =>
      'Not available for repositories on another computer';

  @override
  String get remoteCommandDisconnected => 'Reconnect to the host to use this';

  @override
  String get remoteCommandWritesUnavailable =>
      'The host does not accept this change. Check that its GitLama helper store is usable';

  @override
  String get remoteCommandWritesOff =>
      'Turn on Allow changes on this host to use this';

  @override
  String get remoteCommandWritesReconnect =>
      'Reconnect to apply Allow changes on this host';

  @override
  String get remoteCommandWritesLedger =>
      'GitLama cannot read its record of remote changes on this computer, so changes are unavailable';

  @override
  String get remoteHosts => 'Hosts';

  @override
  String get remoteHostsIntro =>
      'Connect to another computer through your own SSH configuration. GitLama never asks for passwords or private keys.';

  @override
  String get remoteHostsEmpty =>
      'No hosts yet. Add a host with an alias from your SSH configuration.';

  @override
  String get remoteAddHost => 'Add host…';

  @override
  String get remoteAddHostTitle => 'Add host';

  @override
  String remoteAddHostRequested(String alias) {
    return 'GitLama was asked to open a repository on “$alias”, which is not a saved host yet. Save it to connect, or cancel to open nothing.';
  }

  @override
  String get remoteEditHost => 'Edit…';

  @override
  String get remoteEditHostTitle => 'Edit host';

  @override
  String get remoteDeleteHost => 'Delete host';

  @override
  String remoteDeleteHostTitle(String host) {
    return 'Delete host $host?';
  }

  @override
  String get remoteDeleteHostDetail =>
      'This removes only the host profile on this computer. Nothing changes on the host, and open tabs and commit drafts stay.';

  @override
  String get remoteSaveHost => 'Save host';

  @override
  String get remoteHostLabel => 'Name';

  @override
  String get remoteHostLabelPlaceholder => 'Workstation';

  @override
  String get remoteHostAlias => 'SSH destination';

  @override
  String get remoteAliasExample => 'user@devbox';

  @override
  String get remoteHostAliasHelp =>
      'An SSH host alias, hostname or user@host. Uses your SSH configuration, keys and agent. The host must already be trusted; password prompts and sharing an existing SSH connection are not supported.';

  @override
  String get remoteHostAppearanceHelp =>
      'Tabs of this host show its icon in this color instead of its name.';

  @override
  String get remoteAccess => 'Access';

  @override
  String get remoteAccessReadOnly => 'Read only';

  @override
  String get remoteAccessChanges => 'Allow changes';

  @override
  String get remoteAccessReadOnlyDetail =>
      'GitLama shows the repositories on this host and changes nothing.';

  @override
  String get remoteAccessChangesDetail =>
      'GitLama can stage, commit, discard, change branches and stashes, and fetch, pull and push with the host\'s own Git credentials. Changing this while connected reconnects the host.';

  @override
  String get remoteAccessFirstConnection =>
      'Applies to the account GitLama verifies when it first connects.';

  @override
  String get remoteAccessNextConnection =>
      'Applies when this host connects again.';

  @override
  String get remoteHostTrustHelp =>
      'GitLama never asks for passwords or keys. The host key must already be trusted, and your key must be loaded in the SSH agent. Check that the alias works in a terminal first.';

  @override
  String get remoteLabelInvalid =>
      'Enter a name of up to 128 characters without control characters.';

  @override
  String get remoteAliasInvalid =>
      'Use a host or user@host, up to 128 ASCII characters. Each part starts with a letter or digit and uses letters, digits, dots, underscores or hyphens. Ports and options are not allowed.';

  @override
  String get remoteAliasChangeWarning =>
      'Changing the alias removes the verified identity and the permission for staging and commits. The next connection verifies the host again.';

  @override
  String get remoteProfileSaveFailed =>
      'The host could not be saved. Try again.';

  @override
  String get remoteProfileSaveLocked =>
      'The settings file was busy because another GitLama process was writing it at the same moment. Try again.';

  @override
  String get remoteProfileSaveWriteFailed =>
      'GitLama could not write its settings file. Check that the disk has free space and that the settings folder is writable.';

  @override
  String get remoteProfileSaveRejected =>
      'The settings check rejected this change, so nothing was saved. This is a GitLama bug; please report it with the error code.';

  @override
  String get remoteProfileSaveStale =>
      'The host was changed or removed in the meantime, or its values were not accepted. Close this dialog and try again.';

  @override
  String get remoteProfileSaveUnavailable =>
      'Remote hosts are not available right now. Restart GitLama and try again.';

  @override
  String remoteProfileSaveCode(String code) {
    return 'Error code: $code';
  }

  @override
  String remoteHostRowVerified(String alias, String account) {
    return '$alias · account $account';
  }

  @override
  String remoteHostRowUnverified(String alias) {
    return '$alias · not verified yet';
  }

  @override
  String remoteHostAccount(String account) {
    return 'Verified account: $account';
  }

  @override
  String get remoteHostUnknown => 'Remote host';

  @override
  String get remoteHostUnknownAccount => 'unknown';

  @override
  String get remoteConnect => 'Connect';

  @override
  String get remoteCancelConnect => 'Cancel connection';

  @override
  String get remoteDisconnect => 'Disconnect';

  @override
  String get remoteChooseFolder => 'Choose folder…';

  @override
  String get remoteChooseFolderDisabled => 'Connect to a host first';

  @override
  String get remotePhaseIdle => 'Not connected';

  @override
  String get remotePhaseConnecting => 'Connecting through SSH…';

  @override
  String get remotePhaseHandshaking => 'Starting the GitLama helper…';

  @override
  String get remotePhaseReady => 'Connected';

  @override
  String get remotePhaseDisconnecting => 'Disconnecting…';

  @override
  String get remotePhaseDisconnected => 'Connection lost';

  @override
  String get remotePhaseFailed => 'Connection failed';

  @override
  String get remotePhaseIdentityChanged => 'Identity changed';

  @override
  String get remoteIdentityChangedTitle =>
      'This host reports a different identity';

  @override
  String remoteIdentityChangedDetail(String observed, String verified) {
    return 'The host now reports account $observed with a different helper store than the verified account $verified. GitLama did not attach to it. Trust the new identity only if you expect this change; staging and commits are then turned off.';
  }

  @override
  String get remoteTrustIdentity => 'Trust new identity';

  @override
  String get remoteHelperLocationLabel =>
      'Expected helper location on the host:';

  @override
  String get remoteHelperBuildPlaceholder => '<helper-id>';

  @override
  String get remoteHelperExactLocationHelp =>
      'Install the helper package of this GitLama version at this location and make the file executable.';

  @override
  String get remoteHelperLocationHelp =>
      'Replace <helper-id> with the helper ID of the helper package that belongs to this GitLama version, and make the file executable.';

  @override
  String get remotePhaseInstalling => 'Installing the GitLama helper…';

  @override
  String get remoteInstallHelper => 'Install helper';

  @override
  String get remoteInstallHelperHelp =>
      'GitLama can copy the helper of this version to the host over SSH and verify it there.';

  @override
  String remoteInstallHelperTitle(String host) {
    return 'Install the helper on $host?';
  }

  @override
  String remoteInstallHelperDetail(String alias) {
    return 'GitLama copies its helper over SSH alias $alias into your home directory on the host, verifies its checksum and checks that it runs. Nothing outside this directory changes and no administrator rights are needed.';
  }

  @override
  String remoteInstallHelperSize(String size) {
    return 'Size: $size';
  }

  @override
  String remoteInstallHelperDigest(String digest) {
    return 'SHA-256: $digest';
  }

  @override
  String get settingsRemoteHosts => 'Remote hosts';

  @override
  String get settingsRemoteHostsDetail =>
      'Computers GitLama reaches through your SSH configuration, what it may do there and whether it keeps their helper current.';

  @override
  String get remoteHelperVersion => 'Helper version';

  @override
  String get remoteHelperVersionDetail =>
      'Hosts keep their installed helper until a GitLama update needs a newer helper version.';

  @override
  String get remoteHelperVersionUnknown => 'Unknown';

  @override
  String get remoteAutoInstallHelper => 'Install the helper automatically';

  @override
  String get remoteAutoInstallHelperDetail =>
      'When this host lacks the helper this GitLama version needs, GitLama copies it over SSH and verifies it without asking.';

  @override
  String get remoteAccessStatusReadOnly => 'Read only';

  @override
  String get remoteAccessStatusChanges => 'Changes allowed';

  @override
  String remoteHostStatusTooltip(String host) {
    return 'What GitLama may do on $host';
  }

  @override
  String get remoteHostSettings => 'Host settings…';

  @override
  String get remoteManageConnection => 'Connection…';

  @override
  String get remoteInstallHelperConfirm => 'Install';

  @override
  String get remoteFailureInstallUnavailable =>
      'This GitLama build cannot install the helper. Install it manually at the location below.';

  @override
  String get remoteFailureInstallDirectory =>
      'The helper directory on the host could not be created or is a symbolic link.';

  @override
  String get remoteFailureInstallWrite =>
      'The helper could not be written on the host. Check the free space in your home directory.';

  @override
  String get remoteFailureInstallDigest =>
      'The helper arrived damaged on the host and was not installed. Try again.';

  @override
  String get remoteFailureInstallExecute =>
      'The helper could not run on the host. The home directory may be mounted without permission to run programs.';

  @override
  String get remoteFailureInstallFailed =>
      'The helper could not be installed. The host needs sha256sum or shasum and a standard POSIX shell.';

  @override
  String get remoteFailureOutcomeUnknown =>
      'GitLama could not confirm whether the change was applied on the host. It may or may not have been applied. Review the repository before trying again.';

  @override
  String get remoteFailureSshUnavailable =>
      'OpenSSH was not found on this computer. Install the OpenSSH client and try again.';

  @override
  String get remoteFailureSshUnsupported =>
      'The OpenSSH client on this computer is not supported. Install a current OpenSSH client.';

  @override
  String remoteFailureSshConnectionFailed(String alias) {
    return 'SSH could not connect. Check that ssh $alias works in a terminal, that the host key is trusted and that your key is loaded in the SSH agent.';
  }

  @override
  String get remoteFailureHelperNotInstalled =>
      'The GitLama helper for this version is not installed on the host.';

  @override
  String get remoteFailureUnsupportedPlatform =>
      'The host\'s system is not supported. Remote workspaces need a Linux x86_64 host or a Mac.';

  @override
  String get remoteFailureBootstrapFailed =>
      'The GitLama helper could not be started on the host.';

  @override
  String get remoteFailureHandshakeTimeout =>
      'The GitLama helper did not answer in time.';

  @override
  String get remoteFailureProtocolMismatch =>
      'The helper on the host speaks a different protocol version. Install the helper that belongs to this GitLama version.';

  @override
  String get remoteFailureBuildMismatch =>
      'The helper on the host belongs to a different helper version. Install the helper that belongs to this GitLama version.';

  @override
  String get remoteFailureGitMissing => 'Git is not installed on the host.';

  @override
  String get remoteFailureGitUnsupported =>
      'The Git version on the host is too old. Remote workspaces need Git 2.39 or newer.';

  @override
  String get remoteFailureStoreUnavailable =>
      'The helper could not use its private state folder on the host.';

  @override
  String get remoteFailureIdentityChanged =>
      'The host now reports a different account or helper store.';

  @override
  String get remoteFailureIdentityMismatch =>
      'This repository belongs to a different account or helper store on the host.';

  @override
  String get remoteFailureProtocolViolation =>
      'The helper sent an invalid reply, so the connection was closed.';

  @override
  String get remoteFailureDisconnected =>
      'The connection to the host was lost.';

  @override
  String get remoteFailureTimedOut => 'The host did not answer in time.';

  @override
  String get remoteFailureCanceled => 'The connection attempt was canceled.';

  @override
  String get remoteFailureCapacity =>
      'The limit of hosts or connections is reached.';

  @override
  String get remoteFailureUnsupported => 'This is not available for this host.';

  @override
  String get remoteFailurePathNotFound =>
      'This folder does not exist on the host.';

  @override
  String get remoteFailurePermissionDenied =>
      'The host account may not read this folder.';

  @override
  String get remoteFailureNotDirectory => 'This is not a folder.';

  @override
  String get remoteFailureDirectoryChanged =>
      'The folder changed while it was being listed.';

  @override
  String get remoteFailureCursorExpired =>
      'The listing expired. Start it again to see more.';

  @override
  String get remoteFailurePreviewExpired =>
      'The change was prepared on an older state. Review it and try again.';

  @override
  String get remoteFailurePreconditionFailed =>
      'The repository changed on the host. Review it and try again.';

  @override
  String get remoteFailureOperationIdConflict =>
      'The change could not be recorded, so nothing was applied.';

  @override
  String get remoteFailureReceiptCapacity =>
      'Too many changes on this host still need review. Check them under Remote changes first.';

  @override
  String get remoteFailureInternal =>
      'Something went wrong with the host connection.';

  @override
  String get remotePathAbsoluteRequired =>
      'Enter an absolute path that starts with /. ~ and relative paths are not supported.';

  @override
  String get remotePathInvalid =>
      'This path is too long or contains a character that is not allowed.';

  @override
  String remoteDirectoryTitle(String host) {
    return 'Choose a folder on $host';
  }

  @override
  String get remoteDirectoryUp => 'Parent folder';

  @override
  String get remoteDirectoryHome => 'Home folder';

  @override
  String get remoteDirectoryCurrent => 'Current folder';

  @override
  String get remoteDirectoryLoading => 'Loading…';

  @override
  String get remoteDirectoryPath => 'Folder path';

  @override
  String get remoteDirectoryPathPlaceholder => '/home/me/project';

  @override
  String get remoteDirectoryPathHelp =>
      'Press Enter or Go to browse this path, or Open to open it.';

  @override
  String get remotePathChecking => 'Checking this path on the host…';

  @override
  String get remotePathFolder => 'This folder exists on the host.';

  @override
  String get remotePathNotFolder => 'This path exists but is not a folder.';

  @override
  String get remotePathMissing =>
      'There is no folder at this path on the host.';

  @override
  String get remoteDirectoryNoMatch => 'No entries start with the typed name.';

  @override
  String get remoteDirectoryGo => 'Go';

  @override
  String get remoteDirectoryOpen => 'Open';

  @override
  String get remoteDirectoryOpenDisabled => 'Wait for the folder to load';

  @override
  String get remoteDirectoryLoadMore => 'Load more';

  @override
  String get remoteDirectoryTruncated =>
      'This folder has more entries than GitLama lists. Type a path to reach a folder that is not shown.';

  @override
  String get remoteDirectoryEmpty => 'This folder is empty.';

  @override
  String get remoteDirectoryUnavailable => 'No folder is shown.';

  @override
  String get remoteDirectoryRefresh => 'Refresh';

  @override
  String get remoteDirectoryRestart => 'Restart listing';

  @override
  String get remoteEntryRepository => 'Repository';

  @override
  String get remoteEntrySymlink => 'Link';

  @override
  String get remoteEntryFile => 'File';

  @override
  String get remoteEntryOther => 'Other';

  @override
  String get remoteRepositoryCapacity =>
      'This connection has reached its open repository limit. Close another repository tab on this host, then try again.';

  @override
  String get remoteOpenFailed =>
      'The repository on the host could not be opened.';

  @override
  String get remoteRecentHostMissing =>
      'The host of this repository is no longer set up. Add it again under Open Remote Repository.';

  @override
  String remoteRecentSubtitle(String host, String path) {
    return '$host · $path';
  }

  @override
  String get remoteReconnect => 'Reconnect';

  @override
  String get remoteReviewHost => 'Review host…';

  @override
  String remoteReconnectIn(String host, int seconds) {
    return 'Connection to $host lost. Reconnecting in $seconds s…';
  }

  @override
  String remoteReconnecting(String host) {
    return 'Reconnecting to $host…';
  }

  @override
  String remoteReconnectGaveUp(String host) {
    return 'Could not reconnect to $host';
  }

  @override
  String remoteReconnectStopped(String host) {
    return 'Not reconnecting to $host';
  }

  @override
  String get remoteReconnectStale => 'Showing the last received state.';

  @override
  String get remoteReconnectNow => 'Reconnect now';

  @override
  String get remoteReconnectStop => 'Stop';

  @override
  String get remoteReconnectTryAgain => 'Try again';

  @override
  String remoteReconnected(String host) {
    return 'Reconnected to $host';
  }

  @override
  String remoteStaleBanner(String host) {
    return 'Disconnected from $host — showing the last received state.';
  }

  @override
  String remoteHostBadge(String host) {
    return 'On $host';
  }

  @override
  String remoteHostBadgeDisconnected(String host) {
    return 'On $host, disconnected';
  }

  @override
  String remoteTabDisconnectedTitle(String host) {
    return 'Not connected to $host';
  }

  @override
  String get remoteTabDisconnectedDetail =>
      'Reconnect to open this repository again.';

  @override
  String get remoteTabHostDeletedDetail =>
      'The host profile of this repository was deleted. Close the tab, or add the host again and open the repository.';

  @override
  String remoteTabIdentityChangedTitle(String host) {
    return '$host reports a different identity';
  }

  @override
  String remoteTabRepositoryChangedTitle(String host) {
    return 'The repository on $host changed';
  }

  @override
  String get remoteTabRepositoryChangedDetail =>
      'This folder no longer holds the repository GitLama opened here; it may have been replaced, moved or restored. Open it again only if you expect this repository at this path.';

  @override
  String get remoteTabTrustRepository => 'Trust and open';

  @override
  String get remoteTabIdentityChangedDetail =>
      'The host\'s account, helper store or repository no longer matches what GitLama verified. Review the host and decide whether to trust it.';

  @override
  String get remoteOperationsTitle => 'Remote changes';

  @override
  String get remoteOperationsDescription =>
      'Changes GitLama made on your hosts, newest first.';

  @override
  String remoteOperationsIndicator(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remote changes to review',
      one: '1 remote change to review',
    );
    return '$_temp0';
  }

  @override
  String get remoteOperationsUncertain =>
      'GitLama could not confirm the outcome of some changes. They may or may not have been applied. Review the repository before trying again; GitLama never repeats them on its own.';

  @override
  String get remoteOperationsLedgerUnavailable =>
      'The record of remote changes on this computer cannot be read. Staging and commits on hosts stay off until it can.';

  @override
  String get remoteOperationsEmpty => 'No remote changes recorded.';

  @override
  String remoteOperationSubtitle(String host, String family, String state) {
    return '$host · $family · $state';
  }

  @override
  String get remoteOperationStage => 'Staging';

  @override
  String get remoteOperationCommit => 'Commit';

  @override
  String get remoteOperationRefs => 'Branches and tags';

  @override
  String get remoteOperationStash => 'Stash';

  @override
  String get remoteOperationDiscard => 'Discard';

  @override
  String get remoteOperationHistory => 'Merge, cherry-pick or revert';

  @override
  String get remoteOperationRebase => 'Rebase';

  @override
  String get remoteOperationRestack => 'Restack';

  @override
  String get remoteOperationBisect => 'Bisect';

  @override
  String get remoteOperationConflict => 'Conflict resolution';

  @override
  String get remoteOperationSequencer => 'Continue or abort';

  @override
  String get remoteOperationSnapshot => 'Snapshot';

  @override
  String get remoteOperationSnapshotRestore => 'Snapshot restore';

  @override
  String get remoteOperationRestore => 'File restore';

  @override
  String get remoteOperationIndexLock => 'Removing Git\'s lock file';

  @override
  String get remoteOperationPatch => 'Patch';

  @override
  String get remoteOperationExtension => 'Worktrees, submodules and LFS';

  @override
  String get remoteOperationTransfer => 'Fetch, pull or push';

  @override
  String get remoteOperationRunning => 'In progress';

  @override
  String get remoteOperationSucceeded => 'Applied';

  @override
  String get remoteOperationFailed => 'Failed';

  @override
  String get remoteOperationNotApplied => 'Not applied';

  @override
  String get remoteOperationDesiredState => 'Already in the requested state';

  @override
  String get remoteOperationPartial => 'Partly applied';

  @override
  String get remoteOperationUnknown => 'Outcome unknown';

  @override
  String get remoteOperationCheckAgain => 'Check again';

  @override
  String get remoteOperationCheckDisconnected =>
      'Connect to the host to check again';

  @override
  String get remoteOperationCheckFailed =>
      'The host could not be asked. Try again later.';

  @override
  String get remoteOperationDismiss => 'Dismiss';

  @override
  String get remoteOperationDismissFailed => 'The entry could not be removed.';

  @override
  String remoteTabLabel(String repository, String host) {
    return '$repository · $host';
  }

  @override
  String get remoteOutcomeUnknownTitle => 'Outcome unknown';

  @override
  String get remoteOutcomeUnknownCommit =>
      'The commit was sent to the host, but GitLama could not confirm whether it was created. It may or may not have been applied. Your message is kept. Review the history before trying again.';

  @override
  String get remoteOutcomeUnknownStage =>
      'The staging change was sent to the host, but GitLama could not confirm whether it was applied. It may or may not have been applied. Review the changes before trying again.';

  @override
  String get remoteOutcomeUnknownChange =>
      'The change was sent to the host, but GitLama could not confirm whether it was applied. Review it under Remote changes before trying again.';

  @override
  String get remoteTransferAuthentication =>
      'The host could not sign in to the Git server. Set up credentials for this repository on the host, then try again.';

  @override
  String get remoteTransferHostKey =>
      'The host does not trust the Git server\'s key yet. Connect to the server once from a terminal on the host, then try again.';

  @override
  String get inspectorLocation => 'Inspector location';

  @override
  String get inspectorBack => 'Back';

  @override
  String get inspectorForward => 'Forward';

  @override
  String get inspectorLensDiff => 'Diff';

  @override
  String get inspectorLensContents => 'Contents';

  @override
  String get inspectorLensHistory => 'History';

  @override
  String get inspectorLenses => 'View';

  @override
  String get inspectorScope => 'Files';

  @override
  String get inspectorScopeAll => 'All files';

  @override
  String get inspectorScopeAllUnavailable => 'Not available for comparisons';

  @override
  String get inspectorOpenInWindow => 'Open in new window';

  @override
  String get inspectorMaximize => 'Maximize inspector';

  @override
  String get inspectorRestoreLayout => 'Restore layout';

  @override
  String get inspectorShowFiles => 'Show files';

  @override
  String get inspectorHideFiles => 'Hide files';

  @override
  String get inspectorBrowseAllFiles => 'Browse all files';

  @override
  String get inspectorMoreActions => 'More actions';

  @override
  String get inspectorShowInGraph => 'Show in graph';

  @override
  String get inspectorShowInMainWindow => 'Show in main window';

  @override
  String get inspectorRepositoryNotOpen => 'Repository is not open in GitLama';

  @override
  String get inspectorShowCommit => 'Show commit';

  @override
  String get inspectorBlameAtCommit => 'Blame at this commit';

  @override
  String get inspectorBlameBefore => 'Blame before this change';

  @override
  String get inspectorLineHistory => 'Line history';

  @override
  String inspectorLines(int first, int last) {
    return 'Lines $first–$last';
  }

  @override
  String get inspectorClearLines => 'Show whole file history';

  @override
  String get inspectorNotChanged => 'Not changed in this commit';

  @override
  String get inspectorDeletedHere => 'Deleted in this commit';

  @override
  String get inspectorBlameNeedsText => 'Blame needs a text file';

  @override
  String get inspectorSubmoduleNoContents => 'Submodules have no contents here';

  @override
  String get inspectorFolderOnlyHistory => 'Folders only have a history';

  @override
  String get inspectorNoHistory => 'No commits changed this path.';

  @override
  String get inspectorLoadOlder => 'Load older history';

  @override
  String get inspectorLoadMoreFiles => 'Load more files';

  @override
  String inspectorLoading(String commit) {
    return 'Loading $commit…';
  }

  @override
  String get inspectorLoadFailed => 'This could not be loaded.';

  @override
  String get inspectorMissingObject =>
      'This commit is not available in the repository.';

  @override
  String get inspectorRepositoryClosed => 'The repository was closed.';

  @override
  String get inspectorRemoteHostNotConnected => 'The host is not connected.';

  @override
  String get inspectorRemoteHostNotConnectedDetail =>
      'Connect to it in the main window, then try again.';

  @override
  String inspectorShowing(String label) {
    return 'Showing $label';
  }

  @override
  String inspectorHistoryOf(String path) {
    return 'History of $path';
  }

  @override
  String inspectorChangedFilesIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changed files in this folder',
      one: '1 changed file in this folder',
    );
    return '$_temp0';
  }

  @override
  String get fileActionShowDiff => 'Show diff';

  @override
  String get fileActionShowContents => 'Show contents';

  @override
  String get fileActionFileHistory => 'File history';

  @override
  String get fileActionFolderHistory => 'Folder history';

  @override
  String get fileActionExternalDiff => 'Open in external diff tool';

  @override
  String get fileActionCopyCommitHash => 'Copy commit hash';

  @override
  String get fileActionNoCommit => 'No commit yet';

  @override
  String fileActionHeadSuffix(String action) {
    return '$action (HEAD)';
  }

  @override
  String get settingsInspectionOpenIn => 'Open file inspection in';

  @override
  String get settingsInspectionOpenInDetail =>
      'Choose where Blame, Contents and History open. Hold ⌘ or Ctrl to use the other place once.';

  @override
  String get settingsHistoryOtherRefs => 'Show other refs in History';

  @override
  String get settingsHistoryOtherRefsDetail =>
      'History follows branches, remote branches, tags and the stash. Turn this on to also show commits only other refs reach, such as notes or tool checkpoints. The History toolbar changes the same setting.';

  @override
  String get settingsInspectionOpenInPane => 'Detail pane';

  @override
  String get settingsInspectionOpenInWindow => 'New window';

  @override
  String get gitFolderCollapsed => 'Collapsed';

  @override
  String get gitFolderExpanded => 'Expanded';

  @override
  String get commandInspectorBack => 'Inspector back';

  @override
  String get commandInspectorForward => 'Inspector forward';

  @override
  String get commandInspectorLensDiff => 'Show diff of the file';

  @override
  String get commandInspectorLensContents => 'Show contents of the file';

  @override
  String get commandInspectorLensBlame => 'Show blame of the file';

  @override
  String get commandInspectorLensHistory => 'Show history of the file';

  @override
  String get commandInspectorOpenInWindow => 'Open inspector in new window';

  @override
  String get commandInspectorToggleMaximize => 'Maximize or restore inspector';

  @override
  String get commandInspectorToggleFiles => 'Show or hide inspector files';

  @override
  String get commandInspectorAllFiles => 'Browse all files of the commit';

  @override
  String get inspectorNoFiles => 'This commit has no files.';

  @override
  String get initializeLocation => 'Location';

  @override
  String get initializeLocationThisComputer => 'This computer';

  @override
  String get initializeRemoteDestinationHint =>
      'Create an empty Git repository on the host. In the next step, you choose a folder there or type the path of a new one.';

  @override
  String remoteInitializeDirectoryTitle(String host) {
    return 'Choose where to create the repository on $host';
  }

  @override
  String get remoteInitializePathHelp =>
      'Browse to an empty folder, or type the path of a new folder. Missing folders are created.';

  @override
  String get remoteInitializePathNew =>
      'A new folder will be created at this path.';

  @override
  String get remoteInitializeHere => 'Initialize here';

  @override
  String get mutationOutcomeUncertain =>
      'Git may have changed the repository, but GitLama could not confirm the result. Inspect the repository before trying again.';

  @override
  String get stashMessagePlaceholder => 'What are you working on?';

  @override
  String get stashPushIntro =>
      'Set changes aside for a clean working tree. You can bring them back at any time.';

  @override
  String stashScopeAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All changes ($count files)',
      one: 'All changes (1 file)',
    );
    return '$_temp0';
  }

  @override
  String get stashScopeSelected => 'Only selected files';

  @override
  String get stashIncludeUntrackedHelp =>
      'Also stash files that Git doesn\'t track yet.';

  @override
  String get stashKeepIndexHelp =>
      'Staged changes go into the stash and also stay staged.';

  @override
  String stashSelectionCount(int selected, int count) {
    return '$selected of $count selected';
  }

  @override
  String get stashSelectAll => 'Select all';

  @override
  String get stashSelectNone => 'Select none';

  @override
  String get stashSelectFilesReason => 'Select at least one file.';

  @override
  String stashSelectedUntrackedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new files can only be stashed with all changes.',
      one: '1 new file can only be stashed with all changes.',
    );
    return '$_temp0';
  }

  @override
  String get stashPreviewFiles => 'Files';

  @override
  String stashPreviewFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get stashPreviewNewFiles => 'New files';

  @override
  String get stashPreviewIncluded => 'Included';

  @override
  String get stashPreviewStaged => 'Staged changes';

  @override
  String get stashPreviewStillStaged => 'Stay staged';

  @override
  String get restackPreviewSummary =>
      'Each branch moves onto the latest commit of the branch it builds on, in the order shown.';

  @override
  String restackStepOnto(String branch) {
    return 'onto $branch';
  }

  @override
  String historyCherryPickIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Copies the $count selected commits onto the current branch as new commits.',
      one:
          'Copies the selected commit onto the current branch as a new commit.',
    );
    return '$_temp0';
  }

  @override
  String historyRevertIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Adds new commits that undo the $count selected commits. The originals stay in the history.',
      one:
          'Adds a new commit that undoes the selected commit. The original stays in the history.',
    );
    return '$_temp0';
  }

  @override
  String get historyRevertApplyIntro =>
      'Undoes the selected commit\'s changes and stages them for you to review. No commit is created.';

  @override
  String get historyRevertApplyHint =>
      'To review the changes first, apply them without committing.';

  @override
  String get historyMergePreviewTitle => 'Review merge';

  @override
  String get historyCherryPickPreviewTitle => 'Review cherry-pick';

  @override
  String get historyRevertPreviewTitle => 'Review revert';

  @override
  String get historyPreviewCurrentBranch => 'Current branch';

  @override
  String get historyPreviewConflicts => 'Conflicts';

  @override
  String get conflictCheckNone => 'None expected';

  @override
  String conflictCheckFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Likely in $count files',
      one: 'Likely in 1 file',
    );
    return '$_temp0';
  }

  @override
  String get conflictCheckUnavailable => 'Couldn\'t be checked';

  @override
  String get conflictCheckEstimate => 'The conflict check is an estimate.';

  @override
  String get conflictCheckPartial =>
      'The conflict check is an estimate and didn\'t cover every commit.';

  @override
  String rebaseEditorSummary(String branch, String onto) {
    return 'Choose what happens to each commit of $branch. They are replayed from top to bottom onto $onto.';
  }

  @override
  String rebaseConflictsExpected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count files will likely conflict. You can resolve them during the rebase.',
      one: '1 file will likely conflict. You can resolve it during the rebase.',
    );
    return '$_temp0';
  }

  @override
  String rebasePublishedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count commits in this plan are already published. Others may need to update their copies.',
      one:
          '1 commit in this plan is already published. Others may need to update their copies.',
    );
    return '$_temp0';
  }

  @override
  String rebaseStepCombinedWith(String subject) {
    return 'combined with $subject';
  }

  @override
  String get rebaseStepCombinedAbove => 'combined with the commit above';

  @override
  String rebaseStepNewMessage(String message) {
    return 'new message: $message';
  }

  @override
  String get namedSnapshotRestoreSummary =>
      'Your current changes, staged and unstaged, are replaced with the ones saved in this snapshot.';

  @override
  String namedSnapshotRestoreFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files change',
      one: '1 file changes',
    );
    return '$_temp0';
  }

  @override
  String get namedSnapshotRestoreStash =>
      'Your current changes are saved as a stash first, so you find them under Stashes.';

  @override
  String get operationFailureTitle => 'The operation failed';

  @override
  String get operationCopyReport => 'Copy support report';

  @override
  String get operationReportCopied =>
      'Support report copied. It contains no repository contents, paths or credentials.';

  @override
  String get operationUnexpectedFailure =>
      'An unexpected error stopped the operation. Copy the support report from this message or the Logbook.';

  @override
  String operationFailureWithReason(String operation, String reason) {
    return '$operation $reason';
  }

  @override
  String get operationFailureLimit => 'The request exceeded a supported limit.';

  @override
  String get operationFailureTimeout =>
      'Git did not finish within the time limit.';

  @override
  String get operationFailureMissingObject =>
      'A required Git object is missing.';

  @override
  String get operationFailureInvalidRequest =>
      'The selected changes are no longer available or the request could not be validated.';

  @override
  String get operationFailureBusy =>
      'The repository is busy. Try again after the current operation finishes.';

  @override
  String get operationFailureRead =>
      'GitLama could not read the required repository state.';

  @override
  String get stagingFailureIndexLocked =>
      'Another Git operation is using the index, or its lock file was left behind. Check the lock before trying again.';

  @override
  String get stagingFailureStatusRead =>
      'GitLama could not read the current list of changes.';

  @override
  String get stagingFailureIndexRead =>
      'GitLama could not read a valid Git index. Check access to the repository.';

  @override
  String get stagingFailureContentRead =>
      'GitLama could not read a selected file to validate the change.';

  @override
  String get stagingFailureIndexWrite =>
      'GitLama could not write or install the updated Git index. Check permissions and available disk space.';

  @override
  String get stagingFailureGit =>
      'Git rejected the staging change. Copy the support report for the failure code and command exit status.';

  @override
  String get operationFailureCanceled =>
      'The operation was canceled before it completed.';

  @override
  String get transferFailureLocked =>
      'Another Git process was working in this repository, so Git could not lock it.';

  @override
  String get operationGitOutput => 'Git output';

  @override
  String get operationReportIncludeOutput => 'Include Git output in the report';

  @override
  String get operationReportIncludeOutputDetail =>
      'It can contain paths and branch or remote names. Check it before you send it.';

  @override
  String get operationReportGitOutputHeading => 'Git output:';

  @override
  String get operationReportCopiedWithOutput =>
      'Support report copied with Git output. Check it before you send it.';

  @override
  String get repositoryLockTitle => 'The repository is locked';

  @override
  String get repositoryLockExplanation =>
      'Git keeps a lock file while it changes the repository. Another program, such as your editor, a terminal or a background fetch, may still be working, or a Git process stopped without removing its lock.';

  @override
  String get repositoryLockListTitle => 'Lock files';

  @override
  String get repositoryLockChecking => 'Checking lock files…';

  @override
  String get repositoryLockNone =>
      'No lock files remain. The other Git process has finished, so you can try again.';

  @override
  String get repositoryLockRecent =>
      'A lock was created moments ago. Another Git program is probably still working: wait for it to finish, then try again.';

  @override
  String get repositoryLockStale =>
      'These locks are several minutes old. If no other Git program is working in this repository, they were left behind and can be removed.';

  @override
  String get repositoryLockTruncated => 'There are more lock files than shown.';

  @override
  String get repositoryLockInspectFailed =>
      'GitLama could not check the lock files.';

  @override
  String get repositoryLockRemoteOnly =>
      'Lock files on another computer can only be removed there.';

  @override
  String get repositoryLockRemoveWarning =>
      'Remove locks only when no other Git program is working in this repository. Removing a lock that is still in use can damage the repository.';

  @override
  String get repositoryLockCheckAgain => 'Check again';

  @override
  String get repositoryLockRetry => 'Try again';

  @override
  String get repositoryLockRemoveAndRetry => 'Remove locks and try again';

  @override
  String get repositoryLockChanged =>
      'A lock file changed after it was listed. Check again before you remove it.';

  @override
  String get repositoryLockBusy =>
      'GitLama is still working in this repository. Wait for it to finish, then try again.';

  @override
  String get repositoryLockRemoveFailed =>
      'A lock file could not be removed. Check its permissions.';

  @override
  String get repositoryLockAgeUnknown => 'Age unknown';

  @override
  String repositoryLockAgeSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds ago',
      one: '1 second ago',
    );
    return '$_temp0';
  }

  @override
  String repositoryLockAgeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String repositoryLockAgeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String repositoryLockAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get transferPrune => 'Remove remote branches deleted on the server';

  @override
  String get transferPruneHelp =>
      'Keeps the remote branch list in step with the server (git fetch --prune).';

  @override
  String get failureFetchWithoutPrune => 'Fetch without pruning';

  @override
  String get failureCaseCollisionTitle =>
      'Branch names differ only in letter case';

  @override
  String get failureCaseCollisionRepair =>
      'Repairing removes this computer\'s copies of these remote branches and fetches again, which recreates them as the remote has them. Your own branches and the remote are not changed. To stop this for everyone, have one of the branches deleted or renamed on the server.';

  @override
  String get failureCaseCollisionServer =>
      'Have one of the branches deleted or renamed on the server. Until then, fetch without pruning.';

  @override
  String get failureCaseCollisionRepairAction => 'Repair and fetch again';

  @override
  String get failureRemoteAheadTitle => 'The remote has newer commits';

  @override
  String get failureRemoteAheadMessage =>
      'The remote branch has commits your branch does not have, so Git rejected the push. Fetch them, then pull or rebase before you push again.';

  @override
  String failureCaseCollisionMessage(String names) {
    return '$names differ only in letter case. On this computer\'s file system they share one file, so Git cannot update them in one fetch.';
  }

  @override
  String get fileActionAddToGitignore => 'Add to .gitignore…';

  @override
  String get ignoreDialogTitle => 'Add to .gitignore';

  @override
  String get ignoreDialogFileDescription =>
      'GitLama adds this entry to the .gitignore file at the top of the repository. As suggested, it matches only this file.';

  @override
  String get ignoreDialogFolderDescription =>
      'GitLama adds this entry to the .gitignore file at the top of the repository. As suggested, it matches only this folder.';

  @override
  String get ignoreDialogTrackedNote =>
      'Git already tracks this file. The entry hides it only once it is removed from the repository.';

  @override
  String get ignoreDialogEntry => 'Entry';

  @override
  String get ignoreDialogEntryHint =>
      'Use * to match any characters, for example *.log.';

  @override
  String get ignoreDialogAdd => 'Add';

  @override
  String get ignoreFailureInvalid =>
      'Git cannot use this entry. Enter one pattern that does not start with #.';

  @override
  String get ignoreFailureWrite =>
      'GitLama could not change .gitignore. It may be a link, too large or not writable.';

  @override
  String get commandSaveCommitArchive => 'Save snapshot as ZIP…';

  @override
  String get archiveProgressTitle => 'Saving snapshot';

  @override
  String get archiveProgressPreparing => 'Reading the commit…';

  @override
  String archiveProgressFiles(int files, int total) {
    return '$files of $total files';
  }

  @override
  String get archiveProgressWriting => 'Writing the ZIP file…';

  @override
  String archiveSaved(String name) {
    return 'Snapshot saved as $name.';
  }

  @override
  String archiveMissingSubmodules(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count submodules were not available and are empty folders.',
      one: '1 submodule was not available and is an empty folder.',
    );
    return '$_temp0';
  }

  @override
  String archiveUnresolvedLfs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Git LFS files could not be downloaded and hold their pointers.',
      one: '1 Git LFS file could not be downloaded and holds its pointer.',
    );
    return '$_temp0';
  }

  @override
  String get archiveFailureStale =>
      'The repository was closed before the snapshot was saved.';

  @override
  String get archiveFailureMissingCommit =>
      'The commit is no longer in the repository.';

  @override
  String get archiveFailureTooLarge =>
      'The commit has too many files for a snapshot.';

  @override
  String get archiveFailureBusy =>
      'Other snapshots of this repository are still being saved.';

  @override
  String get archiveFailureWrite => 'The ZIP file could not be written.';

  @override
  String get archiveFailureGit => 'Git could not read the commit\'s files.';

  @override
  String get settingsDiffView => 'Diffs';

  @override
  String get settingsDiffViewDetail =>
      'Choose how every diff is shown. The buttons above a diff change these settings too.';

  @override
  String get settingsDiffLayout => 'Layout';

  @override
  String get settingsDiffUnified => 'Unified';

  @override
  String get settingsDiffSideBySide => 'Side by side';

  @override
  String get settingsDiffWrap => 'Long lines';

  @override
  String get settingsDiffWrapOn => 'Wrap';

  @override
  String get settingsDiffWrapOff => 'Scroll sideways';

  @override
  String get settingsDiffWhitespace => 'Whitespace';

  @override
  String get settingsDiffWhitespacePreserve => 'Show all changes';

  @override
  String get settingsDiffWhitespaceIgnoreAll => 'Ignore all whitespace';

  @override
  String get settingsDiffWhitespaceIgnoreAmount => 'Ignore changed amounts';

  @override
  String get settingsDiffWhitespaceIgnoreEndOfLine => 'Ignore at line ends';

  @override
  String get settingsDiffIndicators => 'Plus and minus markers';

  @override
  String get settingsDiffMinimap => 'Minimap';

  @override
  String hostingBranchChecks(String branch, String checks) {
    return '$branch: $checks';
  }

  @override
  String get hostingCheckPassing => 'Checks passed';

  @override
  String get hostingCheckFailing => 'Checks failed';

  @override
  String get hostingCheckPending => 'Checks running';

  @override
  String get hostingCheckCanceled => 'Checks canceled';

  @override
  String get hostingCheckSkipped => 'Checks skipped';

  @override
  String get hostingCheckUnknown => 'Checks unknown';

  @override
  String get hostingMergeable => 'No merge conflicts';

  @override
  String get hostingMergeConflicting => 'Merge conflicts';

  @override
  String get hostingMergeChecking => 'Checking for merge conflicts';

  @override
  String get hostingPullRequestOutdated =>
      'The pull request\'s head on the host is not where this branch is. GitLama checks again shortly; fetch if the branch changed on the host.';

  @override
  String get sidebarFilterShow => 'Filter branches';

  @override
  String get sidebarFilterPlaceholder => 'Filter branches and tags';

  @override
  String get sidebarFilterClear => 'Clear filter';

  @override
  String get sidebarFilterNoMatches => 'No matching branches or tags.';

  @override
  String get commandCheckoutCommit => 'Check out commit…';

  @override
  String refConfirmCheckoutCommit(String target) {
    return 'Check out commit $target with detached HEAD? No branch will be moved. To keep new commits you make here, create a branch before switching away.';
  }

  @override
  String get commitCheckoutDirtyHelp =>
      'You have uncommitted changes. Choose how to save them before checking out this commit. Dismiss cancels checkout.';

  @override
  String get commitCheckoutStashHelp =>
      'Stash saves all tracked and untracked changes and leaves them in the stash after checkout. Ignored files stay in the working tree.';

  @override
  String get commitCheckoutReapplyHelp =>
      'Stash & reapply restores those changes at the selected commit. If this conflicts, the stash is retained and Changes opens for resolution.';

  @override
  String get commitCheckoutDismiss => 'Dismiss';

  @override
  String get commitCheckoutStash => 'Stash';

  @override
  String get commitCheckoutStashAndReapply => 'Stash & reapply';

  @override
  String get commitCheckoutAction => 'Check out commit';

  @override
  String get commitCheckoutBusy => 'Checking out commit…';

  @override
  String get hostingStepPublicClient =>
      'Disable “Confidential Client” (or enable “Public Client”) for this application. GitLama uses PKCE without a client secret.';

  @override
  String get hostingOAuthClientRejected =>
      'The OAuth application was rejected. Check the Client ID and redirect URI. In Forgejo or Codeberg, disable “Confidential Client” (or enable “Public Client”), save, then authorize again.';

  @override
  String discardMixedConfirmMessage(int tracked, int untracked) {
    String _temp0 = intl.Intl.pluralLogic(
      tracked,
      locale: localeName,
      other: 'Restore $tracked tracked files',
      one: 'Restore 1 tracked file',
    );
    String _temp1 = intl.Intl.pluralLogic(
      untracked,
      locale: localeName,
      other: 'permanently delete $untracked new files',
      one: 'permanently delete 1 new file',
    );
    return '$_temp0 and $_temp1? These unstaged changes cannot be recovered.';
  }

  @override
  String discardPartial(int completed, int total) {
    return 'Discard completed for $completed of $total files before it stopped. Check the remaining changes before trying again; the last step may have changed files.';
  }

  @override
  String get conflictResizeFiles => 'Resize conflicted files';

  @override
  String get conflictFilesTitle => 'Conflicted files';

  @override
  String get conflictComparisonTitle => 'Current / Incoming';

  @override
  String get conflictPresenceBothDeleted => 'Deleted on both sides';

  @override
  String get conflictPresenceAddedCurrent => 'Added only on the current side';

  @override
  String get conflictPresenceDeletedIncoming =>
      'Deleted on the incoming side; present on the current side';

  @override
  String get conflictPresenceAddedIncoming => 'Added only on the incoming side';

  @override
  String get conflictPresenceDeletedCurrent =>
      'Deleted on the current side; present on the incoming side';

  @override
  String get conflictPresenceBothAdded => 'Added independently on both sides';

  @override
  String get conflictPresenceBothPresent => 'Present on both sides';

  @override
  String get conflictPresenceUnknown =>
      'Unmerged path; stage details unavailable';

  @override
  String get conflictContentIdentical =>
      'Current and incoming have identical file bytes.';

  @override
  String get conflictContentLineEndings =>
      'The text differs only in line endings (LF, CRLF or CR).';

  @override
  String get conflictContentFinalNewline =>
      'The text differs only in the final newline.';

  @override
  String get conflictContentBom =>
      'The text differs only in the UTF-8 byte order mark (BOM).';

  @override
  String get conflictContentWhitespace =>
      'The text differs only in whitespace, including spaces, tabs or line endings.';

  @override
  String get conflictContentDifferent =>
      'Current and incoming have different file content.';

  @override
  String get conflictContentUnavailable =>
      'Content equality cannot be checked from this preview.';

  @override
  String get conflictContentMissingSide =>
      'An absent file is different from an empty file. Choosing the absent side keeps the deletion.';

  @override
  String get conflictModesDiffer =>
      'File types or executable permissions differ. See Entry details.';

  @override
  String get conflictNoMarkers =>
      'No text markers. Review and resolve this file to clear its unmerged state.';

  @override
  String get conflictEntryDetailsTitle => 'Entry details';

  @override
  String get conflictCurrentEntry => 'Current entry';

  @override
  String get conflictIncomingEntry => 'Incoming entry';

  @override
  String get conflictWorkingEntry => 'Saved working entry';

  @override
  String get conflictEntryAbsent => 'Absent';

  @override
  String get conflictEntryRegular => 'Regular file';

  @override
  String get conflictEntryExecutable => 'Executable file';

  @override
  String get conflictEntrySymlink =>
      'Symbolic link (content is the link target)';

  @override
  String get conflictEntrySubmodule =>
      'Submodule (content identifies a commit)';

  @override
  String get conflictEntryDirectory => 'Directory';

  @override
  String get conflictEntryUnknown => 'Unknown entry type';

  @override
  String conflictEntryFacts(String type, String mode, String bytes) {
    return '$type · mode $mode · $bytes bytes';
  }

  @override
  String get conflictPathFacts =>
      'Index stages describe this path only. Rename and directory/file conflicts can involve other paths; review all related entries. “Saved working entry” describes the file on disk, before unsaved result edits.';

  @override
  String conflictFormatFacts(String endings, String finalNewline, String bom) {
    return '$endings · $finalNewline · $bom';
  }

  @override
  String get conflictNoLineBreaks => 'No line breaks';

  @override
  String get conflictMixedLineBreaks => 'Mixed line endings';

  @override
  String get conflictFinalNewlinePresent => 'Final newline';

  @override
  String get conflictFinalNewlineAbsent => 'No final newline';

  @override
  String get conflictBomPresent => 'UTF-8 BOM';

  @override
  String get conflictBomAbsent => 'No UTF-8 BOM';

  @override
  String get conflictReviewFile => 'Needs resolution';

  @override
  String get transferLocalChangesHelp =>
      'You have uncommitted changes. Choose whether to save them before pulling or let Git try with them in place.';

  @override
  String get transferStashBeforePull => 'Stash, pull, and reapply my changes';

  @override
  String get transferStashBeforePullHelp =>
      'Save staged, unstaged, and untracked files, then restore them with their staging after the pull. Ignored files and edits inside submodules are not stashed. A named recovery copy stays in Stashes until you remove it.';

  @override
  String get transferStashPullAction => 'Stash and pull';

  @override
  String get transferPullStashRestored =>
      'Pull completed. Your changes and staging were restored. A recovery copy remains in Stashes.';

  @override
  String get transferPullStashConflict =>
      'Pull completed, but reapplying your changes caused conflicts. Resolve them in Changes. The recovery stash is kept.';

  @override
  String get transferPullStashSaved =>
      'Pull completed. Your changes could not be fully restored; they remain saved in Stashes. Review Changes before applying the recovery stash.';

  @override
  String transferPullFailedStashRestored(String reason) {
    return '$reason Your changes and staging were restored. A recovery copy remains in Stashes.';
  }

  @override
  String get transferPullFailedStashSaved =>
      'Pull did not complete. Your changes are saved in Stashes. Finish or abort any active Git operation, then apply the recovery stash. Do not pull again to restore them.';

  @override
  String get transferPullRecoveryTitle => 'Your changes after pulling';

  @override
  String get transferPullRecoveryHelp =>
      'The recovery stash is named “GitLama before pull” followed by an identifier. It includes the saved index. Applying it again after a successful restoration duplicates the attempt; remove it only after reviewing your changes.';

  @override
  String worktreeTabsTooltip(String repository, int count) {
    return '$repository · $count worktrees open';
  }

  @override
  String worktreeRowLabel(String repository) {
    return 'Open worktrees of $repository';
  }

  @override
  String get worktreeOpen => 'Open worktree';

  @override
  String get worktreeAllOpen => 'Every worktree is open';

  @override
  String get worktreeListFailed => 'Could not list the worktrees.';

  @override
  String worktreeCloseAll(int count) {
    return 'Close all $count worktrees';
  }

  @override
  String get worktreeMainTab => 'Main worktree';

  @override
  String get conflictKeepingDeletion => 'Keeping deletion';

  @override
  String get conflictUsingThisFile => 'Using this file';

  @override
  String get conflictChooseDifferently => 'Choose differently';

  @override
  String get conflictDeletionDecisionTitle =>
      'This file was deleted on one side';

  @override
  String get conflictDeletionDecisionHint =>
      'Keep the deletion, or keep the file from the side that still has it.';

  @override
  String conflictKeepFileFrom(String branch) {
    return 'Keep file from $branch';
  }

  @override
  String get conflictDeletionChosenTitle => 'Resolving deletes this file';

  @override
  String conflictDeletionChosenBody(String branch) {
    return 'You chose the deletion from $branch. Resolving removes the file from the working tree and stages the deletion.';
  }

  @override
  String conflictWholeFileChosenTitle(String branch) {
    return 'Using the whole file from $branch';
  }

  @override
  String get conflictWholeFileChosenBody =>
      'Resolving saves this version. Editing the result or picking regions replaces this choice.';

  @override
  String get conflictDeletionResult => 'The file will be deleted';

  @override
  String get conflictResolveByDeleting => 'Resolve by deleting';

  @override
  String get conflictChooseVersion => 'Choose which version to keep.';

  @override
  String get conflictResolvedHint =>
      'Check how each file was resolved. You can undo any of them before you continue.';

  @override
  String get conflictOutcomeDeleted => 'Deleted';

  @override
  String conflictOutcomeCurrent(String label) {
    return 'Kept current version ($label)';
  }

  @override
  String conflictOutcomeIncoming(String label) {
    return 'Took incoming version ($label)';
  }

  @override
  String get conflictOutcomeMerged => 'Merged result';

  @override
  String get conflictOutcomeExternal => 'Merged in external tool';

  @override
  String conflictResolvedNext(String resolved, String next) {
    return 'Resolved $resolved. Now showing $next.';
  }

  @override
  String get conflictGuideTitle => 'Conflict resolution steps';

  @override
  String get conflictStepPick => 'Pick changes';

  @override
  String get conflictStepReview => 'Review result';

  @override
  String get conflictStepResolve => 'Resolve';

  @override
  String get conflictStepContinue => 'Continue';

  @override
  String get conflictStepDone => 'Done';

  @override
  String conflictGuidePick(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Choose a side for each of the $count conflicts, or edit the result.',
      one: 'Choose a side for the conflict, or edit the result.',
    );
    return '$_temp0';
  }

  @override
  String get conflictGuideDecideDeletion =>
      'One side deleted this file. Keep the deletion or keep the file.';

  @override
  String get conflictGuideReview => 'Check the result, then resolve the file.';

  @override
  String get conflictGuideReviewDeletion =>
      'The file will be deleted. Resolve it to confirm.';

  @override
  String get conflictGuideContinue =>
      'Check how each file was resolved, then continue.';

  @override
  String get conflictGuideDone => 'All conflicts are resolved.';

  @override
  String conflictGuideResolvedCount(int resolved, int total) {
    return '$resolved of $total files resolved';
  }

  @override
  String get stagingPendingFile => 'Staging action pending';

  @override
  String get stagingWaiting => 'Waiting for repository…';

  @override
  String get stagingPreparing => 'Checking changes…';

  @override
  String get stagingUpdating => 'Updating index…';

  @override
  String get stagingRefreshing => 'Index updated. Refreshing changes…';

  @override
  String get stagingClearQueue => 'Cancel queued actions';

  @override
  String stagingQueueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actions queued.',
      one: '1 action queued.',
      zero: 'No queued actions.',
    );
    return '$_temp0';
  }

  @override
  String stagingQueueStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count queued actions were canceled because staging did not finish safely. Review the changes before trying again.',
      one:
          '1 queued action was canceled because staging did not finish safely. Review the changes before trying again.',
    );
    return '$_temp0';
  }

  @override
  String get refMutationStartingPoint => 'Starting point';

  @override
  String get refMutationTargetUnavailableTitle => 'Starting commit unavailable';

  @override
  String get refMutationTargetUnavailableDetail =>
      'The selected starting commit or its tree is unavailable in this repository. Refresh references and history, then choose a starting point again. Your input will be kept. GitLama will not automatically retry the operation.';

  @override
  String get refMutationRefreshTarget => 'Refresh and choose again';

  @override
  String get settingsStatusAcceleration => 'Faster change checks';

  @override
  String get settingsStatusAccelerationHint =>
      'Git\'s untracked cache and file system monitor make checking a large repository for changes much faster. Turning them on changes this repository\'s own Git settings.';

  @override
  String get settingsUntrackedCache => 'Untracked cache';

  @override
  String get settingsFsmonitor => 'File system monitor';

  @override
  String get settingsFsmonitorUnavailable =>
      'Not available with this Git on this system';

  @override
  String get settingsStatusAccelerationEnable => 'Turn on';

  @override
  String get settingsStatusAccelerationAllOn => 'Everything available is on.';

  @override
  String get settingsStatusAccelerationRemote =>
      'Only available for repositories on this computer.';

  @override
  String get settingsStatusAccelerationReadFailed =>
      'GitLama could not read this repository\'s Git settings.';

  @override
  String get settingsStatusAccelerationLastScanFast =>
      'The last check for changes took less than a second.';

  @override
  String settingsStatusAccelerationLastScan(int seconds) {
    return 'The last check for changes took about $seconds s.';
  }

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsDescription =>
      'Recent safe events stay in memory only (up to 1,000 events or 256 KiB). Detailed capture lasts up to 15 minutes or until the session ends. No credentials or private content are included. Preview before saving or sharing. Nothing is uploaded automatically. Clear history does not remove copies you saved or shared.';

  @override
  String get diagnosticsEnable => 'Enable detailed diagnostics for 15 minutes';

  @override
  String get diagnosticsDisable =>
      'Detailed diagnostics active — stop recording details';

  @override
  String get diagnosticsClear => 'Clear history';

  @override
  String get diagnosticsPreview => 'Preview export';

  @override
  String get diagnosticsCancel => 'Close preview';

  @override
  String get diagnosticsSave => 'Save to file';

  @override
  String get diagnosticsShare => 'Share…';

  @override
  String get diagnosticsFailed =>
      'Could not export diagnostics. Try another destination.';

  @override
  String get diagnosticsSaved => 'Diagnostics saved.';
}
