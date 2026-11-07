import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// Exit a repository workflow.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get workflowExit;

  /// Fallback when conflict provenance is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Last change unknown'**
  String get conflictUnknownProvenance;

  /// Reveal an exported patch in the file manager.
  ///
  /// In en, this message translates to:
  /// **'Show in folder'**
  String get patchShowInFolder;

  /// Opens the searchable reference selector.
  ///
  /// In en, this message translates to:
  /// **'Select reference'**
  String get referencePickerTitle;

  /// Search field in the reference selector.
  ///
  /// In en, this message translates to:
  /// **'Search by name, commit ID, or subject'**
  String get referencePickerSearch;

  /// Empty reference search result.
  ///
  /// In en, this message translates to:
  /// **'No matching references'**
  String get referencePickerEmpty;

  /// Explains the available commit search scope and manual revision entry.
  ///
  /// In en, this message translates to:
  /// **'Search branches, tags, and loaded commits, or enter a revision.'**
  String get referencePickerHistoryHint;

  /// Copies the selected sidebar reference name.
  ///
  /// In en, this message translates to:
  /// **'Copy name'**
  String get sidebarCopyName;

  /// Accessible state of the checked out branch in the sidebar.
  ///
  /// In en, this message translates to:
  /// **'Current branch'**
  String get sidebarCurrentBranch;

  /// Application display name.
  ///
  /// In en, this message translates to:
  /// **'GitLama'**
  String get appTitle;

  /// Application menu command that opens the public issue tracker in the browser.
  ///
  /// In en, this message translates to:
  /// **'Report an issue…'**
  String get commandReportIssue;

  /// Status line failure when the browser could not open the issue tracker.
  ///
  /// In en, this message translates to:
  /// **'The issue tracker could not be opened.'**
  String get reportIssueOpenFailed;

  /// Command and page title for application and dependency licenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licensesTitle;

  /// Application settings command and dialog title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Appearance Settings category.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Repository-scoped Git Settings category.
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get settingsGit;

  /// Hosting integrations Settings category.
  ///
  /// In en, this message translates to:
  /// **'Hosting accounts'**
  String get settingsIntegrations;

  /// Repository hosting link Settings category.
  ///
  /// In en, this message translates to:
  /// **'Repository link'**
  String get settingsRepositoryBinding;

  /// Custom commands Settings category.
  ///
  /// In en, this message translates to:
  /// **'Tools and commands'**
  String get settingsCustomCommands;

  /// Diff renderer Settings category.
  ///
  /// In en, this message translates to:
  /// **'Diff renderer'**
  String get settingsDiffRenderer;

  /// Settings category title for application keyboard shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get settingsShortcuts;

  /// Accessibility Settings category.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsAccessibility;

  /// Appearance Settings category guidance.
  ///
  /// In en, this message translates to:
  /// **'Appearance changes apply immediately and are saved automatically.'**
  String get settingsAppearanceDetail;

  /// Repository-scoped Git Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Choose how repositories are fetched, and manage settings of the active repository.'**
  String get settingsGitDetail;

  /// Global background fetch toggle label.
  ///
  /// In en, this message translates to:
  /// **'Fetch automatically'**
  String get settingsAutoFetch;

  /// Background fetch interval label.
  ///
  /// In en, this message translates to:
  /// **'Fetch interval'**
  String get settingsAutoFetchInterval;

  /// Explains what background fetch does and does not do.
  ///
  /// In en, this message translates to:
  /// **'Open repositories fetch their remote in the background. Nothing is merged or pulled, and a fetch that needs a sign-in is skipped.'**
  String get settingsAutoFetchHint;

  /// Per-repository background fetch override label.
  ///
  /// In en, this message translates to:
  /// **'Fetch this repository automatically'**
  String get settingsRepositoryAutoFetch;

  /// Choice that follows the application-wide setting.
  ///
  /// In en, this message translates to:
  /// **'Same as application'**
  String get settingsFollowApplication;

  /// Enabled choice.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsOn;

  /// Disabled choice.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsOff;

  /// A background fetch interval.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String settingsAutoFetchMinutes(int count);

  /// Hosting integrations Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Add and manage connections to Git hosting providers.'**
  String get settingsIntegrationsDetail;

  /// Repository hosting link Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Choose which hosting account and remote belong to this repository.'**
  String get settingsRepositoryBindingDetail;

  /// Custom command Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Use discovered tools or add a command. GitLama validates saved commands and previews each run.'**
  String get settingsCustomCommandsDetail;

  /// Diff renderer Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Configure and validate an external diff renderer.'**
  String get settingsDiffRendererDetail;

  /// Instructions shown above the application shortcut recorders.
  ///
  /// In en, this message translates to:
  /// **'Select a shortcut and press the new key combination; Escape cancels. Remove a shortcut to leave the command unbound. Conflicting and reserved shortcuts are rejected.'**
  String get settingsShortcutsDetail;

  /// Shown in a shortcut recorder while it waits for the new key combination.
  ///
  /// In en, this message translates to:
  /// **'Press a key combination…'**
  String get settingsShortcutRecording;

  /// Accessible label of the button that leaves a command without a shortcut.
  ///
  /// In en, this message translates to:
  /// **'Remove shortcut'**
  String get settingsShortcutClear;

  /// Label for an application command with no effective shortcut.
  ///
  /// In en, this message translates to:
  /// **'Unbound'**
  String get settingsShortcutUnbound;

  /// Action that removes all custom shortcut overrides.
  ///
  /// In en, this message translates to:
  /// **'Reset shortcut defaults'**
  String get settingsShortcutReset;

  /// Validation error for a malformed shortcut binding.
  ///
  /// In en, this message translates to:
  /// **'Use Ctrl, Cmd, Alt or Shift with a letter, digit, function, arrow or Enter key.'**
  String get settingsShortcutInvalid;

  /// Validation error for an operating-system-reserved shortcut.
  ///
  /// In en, this message translates to:
  /// **'That shortcut is reserved by the operating system.'**
  String get settingsShortcutReserved;

  /// Validation error when two application commands have the same effective shortcut.
  ///
  /// In en, this message translates to:
  /// **'That shortcut is already assigned to another command.'**
  String get settingsShortcutConflict;

  /// Accessibility Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Choose how GitLama follows system motion preferences.'**
  String get settingsAccessibilityDetail;

  /// Packaged license Settings guidance.
  ///
  /// In en, this message translates to:
  /// **'Review GitLama\'s license and the notices for bundled dependencies.'**
  String get settingsLicensesDetail;

  /// Theme selector label.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Force the light application theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Force the dark application theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Follow the operating-system appearance or motion setting.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsFollowSystem;

  /// Workspace density selector label.
  ///
  /// In en, this message translates to:
  /// **'Density'**
  String get settingsDensity;

  /// Compact workspace density.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get settingsDensityCompact;

  /// Regular workspace density.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get settingsDensityRegular;

  /// Comfortable workspace density.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get settingsDensityComfortable;

  /// History date-format selector label.
  ///
  /// In en, this message translates to:
  /// **'Date format'**
  String get settingsDateFormat;

  /// Label for author image selection in appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Author images'**
  String get settingsAvatars;

  /// Local-only author avatar option.
  ///
  /// In en, this message translates to:
  /// **'Initials only'**
  String get settingsAvatarsInitials;

  /// Opt-in Gravatar image option.
  ///
  /// In en, this message translates to:
  /// **'Use Gravatar'**
  String get settingsAvatarsGravatar;

  /// Title of the Gravatar opt-in dialog.
  ///
  /// In en, this message translates to:
  /// **'Author images'**
  String get avatarGravatarTitle;

  /// Explains the Gravatar network request and cache before opt-in.
  ///
  /// In en, this message translates to:
  /// **'Gravatar can show author images. Enabling it sends a hash of each visible author\'s email address to Gravatar. Images are cached for one day.'**
  String get avatarGravatarHint;

  /// Tooltip on a local author avatar while Gravatar is disabled.
  ///
  /// In en, this message translates to:
  /// **'Show Gravatar option'**
  String get avatarGravatarTooltip;

  /// Action to opt in to Gravatar images.
  ///
  /// In en, this message translates to:
  /// **'Enable Gravatar'**
  String get avatarEnableGravatar;

  /// Dismisses the Gravatar offer without enabling it.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get avatarGravatarNotNow;

  /// Relative history date format.
  ///
  /// In en, this message translates to:
  /// **'Relative'**
  String get settingsDateRelative;

  /// Local history date format.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get settingsDateLocal;

  /// ISO history date format.
  ///
  /// In en, this message translates to:
  /// **'ISO 8601'**
  String get settingsDateIso;

  /// Relative history date for the current minute.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get historyDateNow;

  /// No description provided for @historyDateMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String historyDateMinutes(int count);

  /// No description provided for @historyDateHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String historyDateHours(int count);

  /// No description provided for @historyDateDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String historyDateDays(int count);

  /// Motion preference selector label.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get settingsMotion;

  /// Reduce application motion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsMotionReduce;

  /// Allow full application motion.
  ///
  /// In en, this message translates to:
  /// **'Full motion'**
  String get settingsMotionFull;

  /// No description provided for @settingsActiveRepository.
  ///
  /// In en, this message translates to:
  /// **'Active repository: {name}'**
  String settingsActiveRepository(String name);

  /// Repository Settings state without an active repository.
  ///
  /// In en, this message translates to:
  /// **'Open a repository to manage repository settings.'**
  String get settingsNoActiveRepository;

  /// Reset only the active repository's saved Settings.
  ///
  /// In en, this message translates to:
  /// **'Reset repository settings'**
  String get settingsResetRepositoryAction;

  /// Repository Settings reset confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Reset repository settings?'**
  String get settingsResetRepositoryTitle;

  /// No description provided for @settingsResetRepositoryConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Reset the saved view, navigation, filters, and draft for “{name}”? Other repositories and global settings are not changed.'**
  String settingsResetRepositoryConfirmation(String name);

  /// Safe Settings persistence failure.
  ///
  /// In en, this message translates to:
  /// **'The settings could not be saved. Nothing was reported as complete.'**
  String get settingsSaveFailed;

  /// Open packaged license notices from Settings.
  ///
  /// In en, this message translates to:
  /// **'Open licenses'**
  String get settingsOpenLicenses;

  /// Shortcut-reference search label.
  ///
  /// In en, this message translates to:
  /// **'Search shortcuts'**
  String get shortcutSearch;

  /// Shortcut-reference heading for keys whose command depends on the focused section.
  ///
  /// In en, this message translates to:
  /// **'Context-dependent shortcuts'**
  String get shortcutConflictTitle;

  /// No description provided for @shortcutConflictDetail.
  ///
  /// In en, this message translates to:
  /// **'{shortcut}: {commands}'**
  String shortcutConflictDetail(String shortcut, String commands);

  /// Rule that selects the active contextual shortcut command.
  ///
  /// In en, this message translates to:
  /// **'Each key runs the command of the focused sidebar section.'**
  String get shortcutConflictWinner;

  /// Workspace command group label.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get commandGroupCommands;

  /// Repository command group label.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get commandGroupRepository;

  /// Settings command group label.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commandGroupSettings;

  /// Shown while application services initialize.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get startupLoading;

  /// Stable public message shown after bootstrap fails.
  ///
  /// In en, this message translates to:
  /// **'The app could not start.'**
  String get startupFailed;

  /// Retries application bootstrap with a fresh component registry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// Welcome heading before a repository is open.
  ///
  /// In en, this message translates to:
  /// **'Start with a repository'**
  String get welcomeTitle;

  /// Repository welcome guidance.
  ///
  /// In en, this message translates to:
  /// **'Open an existing Git repository or initialize an empty destination.'**
  String get welcomeDetail;

  /// Open an existing repository from welcome.
  ///
  /// In en, this message translates to:
  /// **'Open…'**
  String get welcomeOpen;

  /// Clone a repository from welcome.
  ///
  /// In en, this message translates to:
  /// **'Clone…'**
  String get welcomeClone;

  /// Create a repository from welcome.
  ///
  /// In en, this message translates to:
  /// **'Create…'**
  String get welcomeCreate;

  /// Opens a native directory picker for a repository.
  ///
  /// In en, this message translates to:
  /// **'Open repository'**
  String get openRepository;

  /// Starts the clone workflow.
  ///
  /// In en, this message translates to:
  /// **'Clone repository'**
  String get cloneRepository;

  /// Label for a clone source.
  ///
  /// In en, this message translates to:
  /// **'Repository URL or path'**
  String get cloneSourceLabel;

  /// Description of the Clone repository dialog.
  ///
  /// In en, this message translates to:
  /// **'Copy a repository from a server or another folder. You choose where to put it in the next step.'**
  String get cloneSourceDescription;

  /// Credential-free clone source example.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/team/project.git'**
  String get cloneSourceHint;

  /// Continues clone by choosing its destination.
  ///
  /// In en, this message translates to:
  /// **'Choose destination'**
  String get chooseCloneDestination;

  /// Closes a dialog without applying it.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Cancels the running clone process tree.
  ///
  /// In en, this message translates to:
  /// **'Cancel clone'**
  String get cancelClone;

  /// Clone source validation failure.
  ///
  /// In en, this message translates to:
  /// **'Enter a supported repository URL or absolute local path.'**
  String get cloneInvalidSource;

  /// Credential-bearing clone URL refusal.
  ///
  /// In en, this message translates to:
  /// **'Remove the password or token from the repository URL.'**
  String get cloneEmbeddedCredential;

  /// Clone destination validation failure.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid destination directory.'**
  String get cloneInvalidDestination;

  /// Clone occupied-destination refusal.
  ///
  /// In en, this message translates to:
  /// **'The destination is not empty and was not changed.'**
  String get cloneDestinationOccupied;

  /// Clone authentication failure.
  ///
  /// In en, this message translates to:
  /// **'Authentication is required.'**
  String get cloneAuthenticationRequired;

  /// Credential broker availability failure.
  ///
  /// In en, this message translates to:
  /// **'Secure credential retry is unavailable on this platform.'**
  String get cloneCredentialBrokerUnavailable;

  /// Ephemeral clone secret field.
  ///
  /// In en, this message translates to:
  /// **'Password or token'**
  String get clonePasswordOrToken;

  /// Retries clone through the ephemeral credential broker.
  ///
  /// In en, this message translates to:
  /// **'Retry authentication'**
  String get retryAuthentication;

  /// Clone SSH trust failure.
  ///
  /// In en, this message translates to:
  /// **'The SSH host key is not trusted.'**
  String get cloneHostKeyUntrusted;

  /// Probes the SSH endpoint and opens its host-key challenge.
  ///
  /// In en, this message translates to:
  /// **'Inspect host key'**
  String get inspectHostKey;

  /// SSH host-key challenge title.
  ///
  /// In en, this message translates to:
  /// **'Verify SSH host key'**
  String get hostKeyTitle;

  /// Description of the SSH host key confirmation.
  ///
  /// In en, this message translates to:
  /// **'Check that this is the server you expect. Trust it only if the fingerprint matches the one its administrator or hosting service publishes.'**
  String get hostKeyDescription;

  /// Host key confirmation: the server name and port.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get hostKeyServer;

  /// Host key confirmation: the key algorithm.
  ///
  /// In en, this message translates to:
  /// **'Key type'**
  String get hostKeyType;

  /// Host key confirmation: the key fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get hostKeyFingerprint;

  /// Rejects the exact pending SSH host key.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get rejectHostKey;

  /// Accepts the exact pending SSH host key and retries clone.
  ///
  /// In en, this message translates to:
  /// **'Trust and retry'**
  String get trustHostKey;

  /// SSH keyscan or fingerprint failure.
  ///
  /// In en, this message translates to:
  /// **'The SSH host key could not be inspected.'**
  String get hostKeyProbeFailed;

  /// Stale or mismatched SSH challenge.
  ///
  /// In en, this message translates to:
  /// **'The SSH host-key challenge is no longer current.'**
  String get hostKeyChallengeExpired;

  /// Atomic known-hosts update failure.
  ///
  /// In en, this message translates to:
  /// **'The trusted-host file could not be updated safely.'**
  String get hostKeyWriteFailed;

  /// Clone idle timeout failure.
  ///
  /// In en, this message translates to:
  /// **'The clone stopped after Git became unresponsive.'**
  String get cloneTimedOut;

  /// Clone cancellation result.
  ///
  /// In en, this message translates to:
  /// **'The clone was canceled. Any partial destination was left untouched.'**
  String get cloneCanceled;

  /// Stable generic clone failure.
  ///
  /// In en, this message translates to:
  /// **'The repository could not be cloned.'**
  String get cloneFailed;

  /// Initializes a worktree repository in an explicit destination.
  ///
  /// In en, this message translates to:
  /// **'Initialize repository'**
  String get initializeRepository;

  /// Initializes a bare repository in an explicit destination.
  ///
  /// In en, this message translates to:
  /// **'Initialize bare repository'**
  String get initializeBareRepository;

  /// Choose a bare repository without a working tree.
  ///
  /// In en, this message translates to:
  /// **'Bare repository'**
  String get initializeBareOption;

  /// Explains what a bare repository is, under its checkbox.
  ///
  /// In en, this message translates to:
  /// **'Holds only the history, without working files. Use it as a shared repository on a server.'**
  String get initializeBareHelp;

  /// Description of the Initialize repository dialog for this computer.
  ///
  /// In en, this message translates to:
  /// **'Create an empty Git repository. You choose its folder in the next step.'**
  String get initializeDestinationHint;

  /// Heading after a repository reaches Ready.
  ///
  /// In en, this message translates to:
  /// **'Repository ready'**
  String get repositoryReady;

  /// Repository-ready detail.
  ///
  /// In en, this message translates to:
  /// **'The canonical repository identity and initial Git state are loaded.'**
  String get repositoryReadyDetail;

  /// Heading for successful repository identities.
  ///
  /// In en, this message translates to:
  /// **'Recent repositories'**
  String get recentRepositories;

  /// Empty recent repository state.
  ///
  /// In en, this message translates to:
  /// **'No successfully opened repositories yet.'**
  String get noRecentRepositories;

  /// Accessible name and placeholder of the filter above the recent repositories.
  ///
  /// In en, this message translates to:
  /// **'Filter recent repositories'**
  String get recentRepositoriesFilter;

  /// Shown when the recent repository filter hides every entry.
  ///
  /// In en, this message translates to:
  /// **'No recent repository matches the filter.'**
  String get recentRepositoriesNoMatch;

  /// Stable generic repository failure.
  ///
  /// In en, this message translates to:
  /// **'The repository could not be opened.'**
  String get repositoryOpenFailed;

  /// Repository opening failed because the selected path does not exist.
  ///
  /// In en, this message translates to:
  /// **'The selected path no longer exists.'**
  String get repositoryPathNotFound;

  /// Repository opening failed because the selected path cannot be read.
  ///
  /// In en, this message translates to:
  /// **'GitLama does not have permission to read the selected path.'**
  String get repositoryPermissionDenied;

  /// Repository opening failed because Git did not find a repository.
  ///
  /// In en, this message translates to:
  /// **'The selected path is not inside a Git repository.'**
  String get repositoryNotRepository;

  /// Initialization found an existing repository.
  ///
  /// In en, this message translates to:
  /// **'That destination is already a Git repository.'**
  String get repositoryAlreadyExists;

  /// Safe initialization refusal for occupied destinations.
  ///
  /// In en, this message translates to:
  /// **'The destination is not empty and was not changed.'**
  String get destinationNotEmpty;

  /// Initialization destination type failure.
  ///
  /// In en, this message translates to:
  /// **'The destination is not a supported directory.'**
  String get destinationNotDirectory;

  /// Installed Git could not be launched.
  ///
  /// In en, this message translates to:
  /// **'Installed Git is unavailable.'**
  String get gitUnavailable;

  /// Installed Git is below the supported version.
  ///
  /// In en, this message translates to:
  /// **'The installed Git version is not supported.'**
  String get gitUnsupported;

  /// Changes pane label.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get workspaceChanges;

  /// History pane label.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get workspaceHistory;

  /// Activity panel action.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get workspaceActivity;

  /// Copy the selected activity command and output.
  ///
  /// In en, this message translates to:
  /// **'Copy activity'**
  String get activityCopy;

  /// Confirmation after copying an activity record.
  ///
  /// In en, this message translates to:
  /// **'Activity command and output copied.'**
  String get activityCopied;

  /// Compact create-branch toolbar label.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get toolbarBranch;

  /// Compact toolbar menu for additional repository actions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get toolbarMore;

  /// Refreshes the active repository.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get workspaceRefresh;

  /// Command palette label for reloading local repository state without network access.
  ///
  /// In en, this message translates to:
  /// **'Refresh local view'**
  String get workspaceRefreshLocal;

  /// Toolbar tooltip explaining the scope of repository refresh.
  ///
  /// In en, this message translates to:
  /// **'Reload this repository from disk. Fetch gets new commits from remotes; Pull also updates your branch.'**
  String get workspaceRefreshLocalHint;

  /// Failure to start a user-requested repository refresh.
  ///
  /// In en, this message translates to:
  /// **'Repository refresh failed.'**
  String get workspaceRefreshFailed;

  /// Branches sidebar section.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get workspaceBranches;

  /// Remotes sidebar section.
  ///
  /// In en, this message translates to:
  /// **'Remotes'**
  String get workspaceRemotes;

  /// Stashes sidebar section.
  ///
  /// In en, this message translates to:
  /// **'Stashes'**
  String get workspaceStashes;

  /// Tags sidebar section.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get workspaceTags;

  /// Worktrees sidebar section.
  ///
  /// In en, this message translates to:
  /// **'Worktrees'**
  String get workspaceWorktrees;

  /// Repository detail-region heading.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get workspaceDetail;

  /// History state when the active query contains no commits.
  ///
  /// In en, this message translates to:
  /// **'No commits found.'**
  String get workspaceEmptyHistory;

  /// Empty repository History headline.
  ///
  /// In en, this message translates to:
  /// **'No commits yet'**
  String get historyNoCommitsYet;

  /// Open the Changes island from empty History.
  ///
  /// In en, this message translates to:
  /// **'Open Changes'**
  String get historyOpenChanges;

  /// Retry the failed History load.
  ///
  /// In en, this message translates to:
  /// **'Retry loading history'**
  String get historyRetryLoad;

  /// Footer after the final loaded commit.
  ///
  /// In en, this message translates to:
  /// **'End of history · {count} commits'**
  String historyEndOfHistory(int count);

  /// History banner when the checked-out branch is behind its upstream.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new commit on {ref}} other{{count} new commits on {ref}}}'**
  String historyNewUpstreamCommits(int count, String ref);

  /// Empty detail-region state.
  ///
  /// In en, this message translates to:
  /// **'Select an item to inspect it.'**
  String get workspaceNoSelection;

  /// Safe inline working-tree diff load failure.
  ///
  /// In en, this message translates to:
  /// **'The file diff could not be loaded.'**
  String get workingDiffFailed;

  /// Offers to enable Git's untracked cache and built-in file system monitor after a slow status scan.
  ///
  /// In en, this message translates to:
  /// **'Git took {seconds} s to check this repository for changes. Turning on Git\'s untracked cache and file system monitor in this repository\'s settings makes these checks much faster.'**
  String statusAccelerationOffer(int seconds);

  /// Offers to enable Git's untracked cache after a slow status scan where no built-in monitor exists.
  ///
  /// In en, this message translates to:
  /// **'Git took {seconds} s to check this repository for changes. Turning on Git\'s untracked cache in this repository\'s settings makes these checks faster.'**
  String statusAccelerationOfferCacheOnly(int seconds);

  /// Button that enables Git's status accelerators for the repository.
  ///
  /// In en, this message translates to:
  /// **'Speed up'**
  String get statusAccelerationEnable;

  /// Hides the status acceleration offer for this session.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get statusAccelerationDismiss;

  /// Shown when enabling Git's status accelerators failed.
  ///
  /// In en, this message translates to:
  /// **'Git could not change this repository\'s settings.'**
  String get statusAccelerationFailed;

  /// Shown while a working-tree diff takes longer than expected to load.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Git…'**
  String get workingDiffWaitingForGit;

  /// Explains that the slow working-tree diff keeps loading.
  ///
  /// In en, this message translates to:
  /// **'Git is still working on this repository, for example scanning a large worktree. The diff appears when Git answers.'**
  String get workingDiffWaitingForGitDetail;

  /// Shown in place of a working-tree diff that has no rows.
  ///
  /// In en, this message translates to:
  /// **'This file has no line changes to show.'**
  String get workingDiffEmpty;

  /// Pending repository-tab state.
  ///
  /// In en, this message translates to:
  /// **'Opening repository…'**
  String get workspaceLoadingRepository;

  /// Failed repository-tab state.
  ///
  /// In en, this message translates to:
  /// **'This repository is unavailable.'**
  String get workspaceUnavailableRepository;

  /// No description provided for @workspaceCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close {name}'**
  String workspaceCloseTab(String name);

  /// Opens another repository without closing current tabs.
  ///
  /// In en, this message translates to:
  /// **'Open another repository'**
  String get workspaceOpenAnother;

  /// Ready status-bar label.
  ///
  /// In en, this message translates to:
  /// **'Repository ready'**
  String get workspaceStatusReady;

  /// Loading status-bar label.
  ///
  /// In en, this message translates to:
  /// **'Loading repository'**
  String get workspaceStatusLoading;

  /// Failed status-bar label.
  ///
  /// In en, this message translates to:
  /// **'Repository unavailable'**
  String get workspaceStatusFailed;

  /// Status-bar label for a clean working tree.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get workspaceWorkingTreeClean;

  /// Status-bar label for a dirty working tree.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get workspaceWorkingTreeDirty;

  /// Status-bar label for a conflicted working tree.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get workspaceWorkingTreeConflicted;

  /// Persistent banner while recovering from a native watcher overflow.
  ///
  /// In en, this message translates to:
  /// **'Repository changes arrived faster than they could be displayed. Resynchronizing…'**
  String get workspaceWatchOverflow;

  /// Persistent banner for a repository watcher failure.
  ///
  /// In en, this message translates to:
  /// **'Automatic repository updates are unavailable. Use Refresh to update the view.'**
  String get workspaceWatchFailure;

  /// Persistent banner for a status-section failure.
  ///
  /// In en, this message translates to:
  /// **'Working-tree status could not be read. Other repository data remains available.'**
  String get workspaceStatusFailure;

  /// Persistent banner for a refs-section failure.
  ///
  /// In en, this message translates to:
  /// **'Branches and other references could not be read. Other repository data remains available.'**
  String get workspaceRefsFailure;

  /// Persistent detached-HEAD repository condition.
  ///
  /// In en, this message translates to:
  /// **'No branch is checked out. New commits will not belong to a branch until you create or switch to one.'**
  String get workspaceDetachedHead;

  /// Persistent merge-conflict count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file has conflicts.} other{{count} files have conflicts.}}'**
  String workspaceConflictCount(int count);

  /// Repository condition for an in-progress merge.
  ///
  /// In en, this message translates to:
  /// **'Merge in progress'**
  String get workspaceOperationMerge;

  /// Repository condition for an in-progress rebase.
  ///
  /// In en, this message translates to:
  /// **'Rebase in progress'**
  String get workspaceOperationRebase;

  /// Repository condition for an in-progress cherry-pick.
  ///
  /// In en, this message translates to:
  /// **'Cherry-pick in progress'**
  String get workspaceOperationCherryPick;

  /// Repository condition for an in-progress revert.
  ///
  /// In en, this message translates to:
  /// **'Revert in progress'**
  String get workspaceOperationRevert;

  /// Repository condition for an in-progress bisect.
  ///
  /// In en, this message translates to:
  /// **'Bisect in progress'**
  String get workspaceOperationBisect;

  /// Collapsed consecutive successful background fetches.
  ///
  /// In en, this message translates to:
  /// **'Fetched origin ×{count}'**
  String logbookRepeatedFetch(int count);

  /// Elapsed operation duration in seconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String logbookDurationSeconds(String seconds);

  /// Generic close action.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Running operation count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 running} other{{count} running}}'**
  String operationsRunning(int count);

  /// Failed operation count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 failed} other{{count} failed}}'**
  String operationsFailed(int count);

  /// Operation attention count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 needs attention} other{{count} need attention}}'**
  String operationsAttention(int count);

  /// All operation origins filter.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get operationsFilterAll;

  /// User operation origin filter.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get operationsFilterUser;

  /// Background operation origin filter.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get operationsFilterBackground;

  /// Dismiss retained operation action.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get operationsDismiss;

  /// Dismiss all retained failures action.
  ///
  /// In en, this message translates to:
  /// **'Dismiss all'**
  String get operationsDismissAll;

  /// Open operation activity details action.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get operationsDetails;

  /// Empty operation center state.
  ///
  /// In en, this message translates to:
  /// **'No matching operations'**
  String get operationsEmpty;

  /// Operation with no linked command details.
  ///
  /// In en, this message translates to:
  /// **'No command details are available for this operation.'**
  String get operationsDetailsUnavailable;

  /// Selected operation command details were evicted from bounded activity.
  ///
  /// In en, this message translates to:
  /// **'These command details are no longer available.'**
  String get operationsDetailsExpired;

  /// Loading selected operation command details failed.
  ///
  /// In en, this message translates to:
  /// **'Could not load command details.'**
  String get operationsDetailsLoadFailed;

  /// Opening a read-only blame or tree window failed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the inspection window.'**
  String get historyWindowFailed;

  /// Operation name for repository refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh repository'**
  String get operationRefresh;

  /// Operation name for repository initialization.
  ///
  /// In en, this message translates to:
  /// **'Initialize repository'**
  String get operationInitialize;

  /// Operation name for repository clone.
  ///
  /// In en, this message translates to:
  /// **'Clone repository'**
  String get operationClone;

  /// Operation name for fetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get operationFetch;

  /// Operation name for pull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get operationPull;

  /// Operation name for push.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get operationPush;

  /// Fallback typed operation name.
  ///
  /// In en, this message translates to:
  /// **'Git operation'**
  String get operationOther;

  /// Transfer phase while the remote counts objects.
  ///
  /// In en, this message translates to:
  /// **'Counting objects'**
  String get operationPhaseCounting;

  /// Transfer phase while objects are compressed.
  ///
  /// In en, this message translates to:
  /// **'Compressing objects'**
  String get operationPhaseCompressing;

  /// Transfer phase while objects are downloaded.
  ///
  /// In en, this message translates to:
  /// **'Receiving objects'**
  String get operationPhaseReceiving;

  /// Transfer phase while received deltas are resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolving deltas'**
  String get operationPhaseResolving;

  /// Phase while Git writes the working tree.
  ///
  /// In en, this message translates to:
  /// **'Updating files'**
  String get operationPhaseUpdatingFiles;

  /// Phase while a content filter such as Git LFS delivers file contents.
  ///
  /// In en, this message translates to:
  /// **'Downloading file contents'**
  String get operationPhaseFiltering;

  /// Phase while commits are replayed.
  ///
  /// In en, this message translates to:
  /// **'Rebasing'**
  String get operationPhaseRebasing;

  /// A running operation's current phase and its completion.
  ///
  /// In en, this message translates to:
  /// **'{phase} {percent}%'**
  String operationPhaseProgress(String phase, int percent);

  /// A running operation's completion when its phase is unknown.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String operationPercent(int percent);

  /// Toolbar text for a running operation with its progress.
  ///
  /// In en, this message translates to:
  /// **'{operation} · {detail}'**
  String operationRunningDetail(String operation, String detail);

  /// Running operation state.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get operationStateRunning;

  /// Succeeded operation state.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get operationStateSucceeded;

  /// Failed operation state.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get operationStateFailed;

  /// Canceled operation state.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get operationStateCanceled;

  /// Operation scope when no repository session exists yet.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get operationRepositoryApplication;

  /// Command palette title.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commandPaletteTitle;

  /// Command palette search field label.
  ///
  /// In en, this message translates to:
  /// **'Search commands'**
  String get commandPaletteSearch;

  /// Command palette empty search result.
  ///
  /// In en, this message translates to:
  /// **'No command matches “{query}”'**
  String commandPaletteNoMatch(String query);

  /// Read-only keyboard shortcut reference title.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutReferenceTitle;

  /// Command disabled reason when no repository is open.
  ///
  /// In en, this message translates to:
  /// **'Open a repository to use this command'**
  String get commandRepositoryRequired;

  /// Command capability disabled reason.
  ///
  /// In en, this message translates to:
  /// **'This action is not available in the current build'**
  String get commandFeatureUnavailable;

  /// Command cannot run because its contextual target is not active.
  ///
  /// In en, this message translates to:
  /// **'This command needs a matching selection or active editor'**
  String get commandContextUnavailable;

  /// Inspect Git index lock command.
  ///
  /// In en, this message translates to:
  /// **'Check Git\'s lock file (index.lock)…'**
  String get commandInspectIndexLock;

  /// Create branch command.
  ///
  /// In en, this message translates to:
  /// **'Create branch…'**
  String get commandCreateBranch;

  /// Rename branch command.
  ///
  /// In en, this message translates to:
  /// **'Rename branch…'**
  String get commandRenameBranch;

  /// Delete branch command.
  ///
  /// In en, this message translates to:
  /// **'Delete branch…'**
  String get commandDeleteBranch;

  /// Delete a branch on its remote.
  ///
  /// In en, this message translates to:
  /// **'Delete remote branch…'**
  String get commandDeleteRemoteBranch;

  /// Checkout branch command.
  ///
  /// In en, this message translates to:
  /// **'Check out branch…'**
  String get commandCheckoutBranch;

  /// Add remote command.
  ///
  /// In en, this message translates to:
  /// **'Add remote…'**
  String get commandAddRemote;

  /// Edit remote command; it changes the URL only.
  ///
  /// In en, this message translates to:
  /// **'Change remote URL…'**
  String get commandEditRemote;

  /// Rename remote command.
  ///
  /// In en, this message translates to:
  /// **'Rename remote…'**
  String get commandRenameRemote;

  /// Remove remote command.
  ///
  /// In en, this message translates to:
  /// **'Remove remote…'**
  String get commandRemoveRemote;

  /// Create tag command.
  ///
  /// In en, this message translates to:
  /// **'Create tag…'**
  String get commandCreateTag;

  /// Delete tag command.
  ///
  /// In en, this message translates to:
  /// **'Delete tag…'**
  String get commandDeleteTag;

  /// Close the active repository tab command.
  ///
  /// In en, this message translates to:
  /// **'Close repository tab'**
  String get commandCloseRepositoryTab;

  /// Move between the Changes and History panes.
  ///
  /// In en, this message translates to:
  /// **'Next pane'**
  String get commandNextPane;

  /// Open History and focus its repository search field.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get commandFind;

  /// Push one exact local tag command.
  ///
  /// In en, this message translates to:
  /// **'Push tag…'**
  String get commandPushTag;

  /// Reset current branch command.
  ///
  /// In en, this message translates to:
  /// **'Reset current branch…'**
  String get commandResetBranch;

  /// New branch name field.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get refMutationNewName;

  /// Allow deletion of an unmerged branch.
  ///
  /// In en, this message translates to:
  /// **'Delete even if it is not merged'**
  String get refMutationForceDelete;

  /// Option to switch to a branch right after creating it.
  ///
  /// In en, this message translates to:
  /// **'Check out the new branch'**
  String get refMutationCheckoutNewBranch;

  /// Reset mode field.
  ///
  /// In en, this message translates to:
  /// **'Reset mode'**
  String get refMutationResetMode;

  /// Soft reset mode.
  ///
  /// In en, this message translates to:
  /// **'Soft: move the branch, keep changes staged'**
  String get refMutationResetSoft;

  /// Mixed reset mode.
  ///
  /// In en, this message translates to:
  /// **'Mixed: move the branch, keep changes unstaged'**
  String get refMutationResetMixed;

  /// Hard reset mode.
  ///
  /// In en, this message translates to:
  /// **'Hard: move the branch, discard changes to tracked files'**
  String get refMutationResetHard;

  /// Branch, tag, or remote name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get refMutationName;

  /// Remote URL field.
  ///
  /// In en, this message translates to:
  /// **'Remote URL'**
  String get refMutationRemoteUrl;

  /// Shown under the remote URL field when the current URL hides credentials.
  ///
  /// In en, this message translates to:
  /// **'The current URL contains credentials and is not shown. Enter the complete new URL.'**
  String get refMutationRemoteUrlHidden;

  /// Optional annotated tag message field.
  ///
  /// In en, this message translates to:
  /// **'Annotation message (optional)'**
  String get refMutationTagMessage;

  /// Disclosure with the exact git commands a workflow runs.
  ///
  /// In en, this message translates to:
  /// **'Git command details'**
  String get gitCommandDetails;

  /// A duration in seconds, such as a time limit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String secondsCount(int count);

  /// A size in bytes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 byte} other{{count} bytes}}'**
  String byteCount(int count);

  /// A size in kilobytes (1,024 bytes); size is already a formatted number such as 47 or 1.5.
  ///
  /// In en, this message translates to:
  /// **'{size} KB'**
  String sizeKilobytes(String size);

  /// A size in megabytes (1,024 KB); size is already a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String sizeMegabytes(String size);

  /// A size in gigabytes (1,024 MB); size is already a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{size} GB'**
  String sizeGigabytes(String size);

  /// A size in terabytes (1,024 GB); size is already a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{size} TB'**
  String sizeTerabytes(String size);

  /// Disclosure title over the exact command line of an external program GitLama is about to run.
  ///
  /// In en, this message translates to:
  /// **'Command details'**
  String get commandDetails;

  /// Tooltip for the arrow attached to the Push toolbar button.
  ///
  /// In en, this message translates to:
  /// **'Push options'**
  String get pushOptions;

  /// integrationRunSummary text.
  ///
  /// In en, this message translates to:
  /// **'Run this configured tool with the selected repository context. The tool may change files or external systems.'**
  String get integrationRunSummary;

  /// integrationDiffSummary text.
  ///
  /// In en, this message translates to:
  /// **'Open the selected changes in the configured external diff tool. The tool receives temporary file paths.'**
  String get integrationDiffSummary;

  /// integrationMergeSummary text.
  ///
  /// In en, this message translates to:
  /// **'Open the conflicted file in the configured merge tool. Review and save the result before continuing.'**
  String get integrationMergeSummary;

  /// No description provided for @hostingRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove hosting account {name} from GitLama? Repository data on the server is unchanged. You will need to connect again to use its reviews and issues.'**
  String hostingRemoveConfirm(String name);

  /// Rebase review: what starting the rebase does.
  ///
  /// In en, this message translates to:
  /// **'Your commits are replayed in this order. They get new commit IDs, and you may need to resolve conflicts along the way.'**
  String get rebasePreviewSummary;

  /// Explains what merging a branch does.
  ///
  /// In en, this message translates to:
  /// **'Brings the changes of the selected branch into the current branch. Git may create a merge commit.'**
  String get historyMergeSummary;

  /// stashPushSummary text.
  ///
  /// In en, this message translates to:
  /// **'Save the selected changes in a stash and remove them from the working tree.'**
  String get stashPushSummary;

  /// stashApplySummary text.
  ///
  /// In en, this message translates to:
  /// **'Apply stashed changes to the working tree. The stash remains available.'**
  String get stashApplySummary;

  /// stashPopSummary text.
  ///
  /// In en, this message translates to:
  /// **'Apply stashed changes and remove the stash if the apply succeeds.'**
  String get stashPopSummary;

  /// stashDropSummary text.
  ///
  /// In en, this message translates to:
  /// **'Delete this stash. Its changes may no longer be recoverable.'**
  String get stashDropSummary;

  /// stashRenameSummary text.
  ///
  /// In en, this message translates to:
  /// **'Change this stash\'s description. Its saved changes remain.'**
  String get stashRenameSummary;

  /// stashCheckoutSummary text.
  ///
  /// In en, this message translates to:
  /// **'Save current changes temporarily, switch branches, then reapply them. Conflicts may need to be resolved.'**
  String get stashCheckoutSummary;

  /// bisectStartSummary text.
  ///
  /// In en, this message translates to:
  /// **'Start searching history for the commit that introduced a problem. Git will check out commits while you test them.'**
  String get bisectStartSummary;

  /// bisectGoodSummary text.
  ///
  /// In en, this message translates to:
  /// **'Mark the current commit as working. Git will check out the next commit to test.'**
  String get bisectGoodSummary;

  /// bisectBadSummary text.
  ///
  /// In en, this message translates to:
  /// **'Mark the current commit as broken. Git will check out the next commit to test.'**
  String get bisectBadSummary;

  /// bisectSkipSummary text.
  ///
  /// In en, this message translates to:
  /// **'Skip this commit and check out another one to test.'**
  String get bisectSkipSummary;

  /// bisectResetSummary text.
  ///
  /// In en, this message translates to:
  /// **'End the search and return to the branch you had checked out before it started.'**
  String get bisectResetSummary;

  /// Label above the remotes a deleted tag is also removed from.
  ///
  /// In en, this message translates to:
  /// **'Also delete from remotes'**
  String get deleteTagRemotePrompt;

  /// Caption under the remote checklist: when a remote tag deletion is accepted and when the local tag goes.
  ///
  /// In en, this message translates to:
  /// **'A remote\'s tag is deleted only if it still points to the same commit as yours. The tag stays on this computer until every selected remote has deleted it.'**
  String get deleteTagRemoteAvailabilityHint;

  /// Shown before a ref deletion that also deletes it on a remote.
  ///
  /// In en, this message translates to:
  /// **'This also deletes it on the remote, where others may already have fetched it.'**
  String get deleteRefOnRemoteWarning;

  /// Partial remote tag deletion result.
  ///
  /// In en, this message translates to:
  /// **'The selected remote tag was deleted, but the local tag could not be deleted. Check the repository state before retrying.'**
  String get deleteTagLocalFailedAfterRemote;

  /// No description provided for @deleteTagRemoteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the tag on {remote}. The local tag remains. Check any earlier remotes before retrying.'**
  String deleteTagRemoteFailed(String remote);

  /// No description provided for @refConfirmCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create local branch {name}.'**
  String refConfirmCreateBranch(String name);

  /// No description provided for @refConfirmCreateAndCheckoutBranch.
  ///
  /// In en, this message translates to:
  /// **'Create local branch {name} and switch to it. Uncommitted changes stay in the working tree.'**
  String refConfirmCreateAndCheckoutBranch(String name);

  /// No description provided for @refConfirmRenameBranch.
  ///
  /// In en, this message translates to:
  /// **'Rename local branch {name} to {newName}. Remote branches are unchanged.'**
  String refConfirmRenameBranch(String name, String newName);

  /// No description provided for @refConfirmDeleteBranch.
  ///
  /// In en, this message translates to:
  /// **'Delete local branch {name}. Remote branches are unchanged.'**
  String refConfirmDeleteBranch(String name);

  /// No description provided for @refConfirmDeleteBranchAndUpstream.
  ///
  /// In en, this message translates to:
  /// **'Delete local branch {name} and its upstream {upstream} on the remote.'**
  String refConfirmDeleteBranchAndUpstream(String name, String upstream);

  /// Option to delete the branch's upstream on the remote as well.
  ///
  /// In en, this message translates to:
  /// **'Also delete {upstream}'**
  String refMutationDeleteUpstream(String upstream);

  /// Explain the lease that protects remote branch deletion.
  ///
  /// In en, this message translates to:
  /// **'Deleted only if it has not moved since the last fetch.'**
  String get refMutationDeleteUpstreamHelp;

  /// Partial branch deletion result.
  ///
  /// In en, this message translates to:
  /// **'The local branch was deleted, but {upstream} could not be deleted on the remote. Fetch and check the remote branch before retrying.'**
  String deleteBranchUpstreamFailed(String upstream);

  /// No description provided for @refConfirmCheckoutBranch.
  ///
  /// In en, this message translates to:
  /// **'Switch to local branch {name}. Files in the working tree may change.'**
  String refConfirmCheckoutBranch(String name);

  /// No description provided for @refConfirmCreateTag.
  ///
  /// In en, this message translates to:
  /// **'Create local tag {name}. It will not be published automatically.'**
  String refConfirmCreateTag(String name);

  /// No description provided for @refConfirmDeleteTagLocal.
  ///
  /// In en, this message translates to:
  /// **'Delete local tag {name}. Tags on remotes are unchanged.'**
  String refConfirmDeleteTagLocal(String name);

  /// No description provided for @refConfirmDeleteTagRemotes.
  ///
  /// In en, this message translates to:
  /// **'Delete tag {name} from {remotes}, then delete the local tag. Other users may already have fetched it.'**
  String refConfirmDeleteTagRemotes(String name, String remotes);

  /// No description provided for @refConfirmAddRemote.
  ///
  /// In en, this message translates to:
  /// **'Add remote {name} to this repository. No files or remote data change.'**
  String refConfirmAddRemote(String name);

  /// No description provided for @refConfirmEditRemote.
  ///
  /// In en, this message translates to:
  /// **'Change the URL for remote {name}. Future transfers will use the new address.'**
  String refConfirmEditRemote(String name);

  /// No description provided for @refConfirmRenameRemote.
  ///
  /// In en, this message translates to:
  /// **'Rename remote {name} to {newName}. Its remote branches and the upstreams that use it move to the new name.'**
  String refConfirmRenameRemote(String name, String newName);

  /// No description provided for @refConfirmRemoveRemote.
  ///
  /// In en, this message translates to:
  /// **'Remove remote {name} from this repository. The server and its branches remain available to others.'**
  String refConfirmRemoveRemote(String name);

  /// refConfirmResetSoft text.
  ///
  /// In en, this message translates to:
  /// **'Move the current branch to the selected commit. Staged and working tree changes remain.'**
  String get refConfirmResetSoft;

  /// refConfirmResetMixed text.
  ///
  /// In en, this message translates to:
  /// **'Move the current branch and reset staged changes. Working tree files remain.'**
  String get refConfirmResetMixed;

  /// refConfirmResetHard text.
  ///
  /// In en, this message translates to:
  /// **'Move the current branch and discard tracked staged and working tree changes. The discarded changes are lost.'**
  String get refConfirmResetHard;

  /// Dirty checkout warning.
  ///
  /// In en, this message translates to:
  /// **'The worktree has uncommitted changes.'**
  String get refMutationWarningDirty;

  /// Detached HEAD warning.
  ///
  /// In en, this message translates to:
  /// **'No branch is checked out.'**
  String get refMutationWarningDetached;

  /// Published branch warning.
  ///
  /// In en, this message translates to:
  /// **'This branch appears on a remote.'**
  String get refMutationWarningPublished;

  /// Other-worktree checkout warning.
  ///
  /// In en, this message translates to:
  /// **'Another worktree has this branch checked out.'**
  String get refMutationWarningOtherWorktree;

  /// Hard reset destructive-scope warning.
  ///
  /// In en, this message translates to:
  /// **'A hard reset discards all staged and unstaged changes to tracked files.'**
  String get refMutationWarningDestructiveReset;

  /// Ref mutation success message.
  ///
  /// In en, this message translates to:
  /// **'Git operation completed.'**
  String get refMutationCompleted;

  /// Ref mutation stale-preview message.
  ///
  /// In en, this message translates to:
  /// **'Repository state changed. Preview the operation again.'**
  String get refMutationStale;

  /// Ref mutation failure message.
  ///
  /// In en, this message translates to:
  /// **'Git did not complete the operation.'**
  String get refMutationFailed;

  /// Ref mutation post-commit warning.
  ///
  /// In en, this message translates to:
  /// **'Git completed the operation, but the view could not be refreshed.'**
  String get refMutationWarningResult;

  /// Create stash command.
  ///
  /// In en, this message translates to:
  /// **'Create stash…'**
  String get commandCreateStash;

  /// Add worktree command.
  ///
  /// In en, this message translates to:
  /// **'Add worktree…'**
  String get commandAddWorktree;

  /// Opens the Git LFS tracking flow.
  ///
  /// In en, this message translates to:
  /// **'Track LFS pattern…'**
  String get commandTrackLfsPattern;

  /// Opens the integration configuration flow.
  ///
  /// In en, this message translates to:
  /// **'Add integration…'**
  String get commandAddIntegration;

  /// Index lock inspection found no lock.
  ///
  /// In en, this message translates to:
  /// **'No Git lock file was found.'**
  String get indexLockNotFound;

  /// Index lock removal confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Remove Git\'s lock file?'**
  String get indexLockConfirmationTitle;

  /// Explicit index lock removal warning; size is a formatted file size such as 0 bytes.
  ///
  /// In en, this message translates to:
  /// **'Make sure no other Git program is working in this repository first. This removes Git\'s lock file ({size}), not your staged changes. Removing a lock that is still in use can damage the repository. The interrupted command does not run again automatically.'**
  String indexLockConfirmation(String size);

  /// Confirmed index lock removal action.
  ///
  /// In en, this message translates to:
  /// **'Remove lock'**
  String get indexLockRemove;

  /// Index lock removal completion.
  ///
  /// In en, this message translates to:
  /// **'Git\'s lock file was removed. The interrupted command was not run again.'**
  String get indexLockRemoved;

  /// Changed index lock refusal.
  ///
  /// In en, this message translates to:
  /// **'The lock file changed after it was checked. Check it again before removing it.'**
  String get indexLockChanged;

  /// Active operation lock-removal refusal.
  ///
  /// In en, this message translates to:
  /// **'The lock cannot be removed while repository work is active.'**
  String get indexLockActiveOperation;

  /// Generic safe index lock failure.
  ///
  /// In en, this message translates to:
  /// **'Git\'s lock file could not be checked or removed safely.'**
  String get indexLockUnavailable;

  /// Title of the internal shared-component gallery.
  ///
  /// In en, this message translates to:
  /// **'GitLama component gallery'**
  String get galleryTitle;

  /// Gallery label for repository opening.
  ///
  /// In en, this message translates to:
  /// **'Open repository'**
  String get galleryOpenRepository;

  /// Gallery disabled-action stress label.
  ///
  /// In en, this message translates to:
  /// **'Unavailable action with a deliberately long label'**
  String get galleryUnavailableAction;

  /// Reason the gallery action is disabled.
  ///
  /// In en, this message translates to:
  /// **'No repository is open'**
  String get galleryUnavailableReason;

  /// Gallery busy button label.
  ///
  /// In en, this message translates to:
  /// **'Loading repository'**
  String get galleryLoadingRepository;

  /// Refresh action label.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get galleryRefresh;

  /// Gallery menu accessible label.
  ///
  /// In en, this message translates to:
  /// **'Workspace menu'**
  String get galleryWorkspaceMenu;

  /// History workspace label in the gallery.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get galleryHistory;

  /// Changes workspace label in the gallery.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get galleryChanges;

  /// Activity workspace label in the gallery.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get galleryActivity;

  /// Gallery row label used to test elision and semantics.
  ///
  /// In en, this message translates to:
  /// **'main  A long branch label that must remain accessible'**
  String get galleryBranchRow;

  /// Accessible current-checkout state.
  ///
  /// In en, this message translates to:
  /// **'Current checkout'**
  String get galleryCurrent;

  /// Confirmation after copying a full history-row value.
  ///
  /// In en, this message translates to:
  /// **'Full value copied.'**
  String get historyObjectIdCopied;

  /// Shown for a moment in place of a commit hash after it is copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get historyHashCopied;

  /// Copy the full commit object ID from the graph context menu.
  ///
  /// In en, this message translates to:
  /// **'Copy commit SHA'**
  String get historyCopyObjectId;

  /// Copy the commit subject from the graph context menu.
  ///
  /// In en, this message translates to:
  /// **'Copy commit subject'**
  String get historyCopySubject;

  /// Status confirmation after a menu copies a full commit hash.
  ///
  /// In en, this message translates to:
  /// **'Commit hash copied.'**
  String get menuCommitHashCopied;

  /// Status confirmation after a menu copies a commit subject.
  ///
  /// In en, this message translates to:
  /// **'Commit subject copied.'**
  String get menuCommitSubjectCopied;

  /// Status confirmation after a menu copies a branch, tag, stash or remote name.
  ///
  /// In en, this message translates to:
  /// **'Name copied.'**
  String get menuNameCopied;

  /// Dirty working-tree pseudo-commit summary.
  ///
  /// In en, this message translates to:
  /// **'Uncommitted changes · {count} files · {staged} staged'**
  String historyWorkingTreeChanges(int count, int staged);

  /// Conflicted working-tree pseudo-commit summary.
  ///
  /// In en, this message translates to:
  /// **'Conflicts · {count} files · open resolver'**
  String historyWorkingTreeConflicts(int count);

  /// Complete accessible description for a history row.
  ///
  /// In en, this message translates to:
  /// **'History row. Subject: {subject}. Author: {author}. Commit: {objectId}. Date: {date}. Lane {lane}. References: {references}. {overflow} additional references.'**
  String historyRowSemantics(
    String subject,
    String author,
    String objectId,
    String date,
    int lane,
    String references,
    int overflow,
  );

  /// History search field hint.
  ///
  /// In en, this message translates to:
  /// **'Search commits'**
  String get historySearchHint;

  /// Clears the text of a search or filter field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClear;

  /// Apply the pending history query.
  ///
  /// In en, this message translates to:
  /// **'Apply filter'**
  String get historyApplyFilter;

  /// Toolbar button that opens the history branch filter.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get historyBranchFilter;

  /// Branch filter button while the graph is filtered.
  ///
  /// In en, this message translates to:
  /// **'Branches ({count})'**
  String historyBranchFilterCount(int count);

  /// Tooltip of the history branch filter button.
  ///
  /// In en, this message translates to:
  /// **'Filter the graph by branch'**
  String get historyBranchFilterTooltip;

  /// Placeholder of the branch filter search field.
  ///
  /// In en, this message translates to:
  /// **'Find a branch'**
  String get historyBranchFilterSearch;

  /// Branch filter editor state when no branch matches the search text.
  ///
  /// In en, this message translates to:
  /// **'No branches match.'**
  String get historyBranchFilterNoMatches;

  /// Shows one branch in the history graph.
  ///
  /// In en, this message translates to:
  /// **'Show only this branch'**
  String get historyBranchFilterFocus;

  /// Branch context menu command that adds the branch to the history graph filter.
  ///
  /// In en, this message translates to:
  /// **'Add to graph filter'**
  String get historyBranchFilterAdd;

  /// Branch context menu command that removes the branch from the history graph filter.
  ///
  /// In en, this message translates to:
  /// **'Remove from graph filter'**
  String get historyBranchFilterRemove;

  /// Clears the history branch filter.
  ///
  /// In en, this message translates to:
  /// **'Show all branches'**
  String get historyBranchFilterShowAll;

  /// Shows only the checked-out branch in the graph.
  ///
  /// In en, this message translates to:
  /// **'Current branch'**
  String get historyBranchFilterCurrent;

  /// No description provided for @historyBranchFilterSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{All branches shown} =1{1 branch shown} other{{count} branches shown}}'**
  String historyBranchFilterSummary(int count);

  /// Explains how the branch filter editor is used.
  ///
  /// In en, this message translates to:
  /// **'Click to add or remove. Double-click or press Enter to show only one.'**
  String get historyBranchFilterHelp;

  /// Accessible state of a branch in the graph filter.
  ///
  /// In en, this message translates to:
  /// **'Shown in graph'**
  String get historyBranchFilterShown;

  /// Notice when the branch filter leaves no commits in the history graph.
  ///
  /// In en, this message translates to:
  /// **'No commits match the branch filter.'**
  String get historyBranchFilterNoCommits;

  /// History search scope menu label.
  ///
  /// In en, this message translates to:
  /// **'Search fields'**
  String get historySearchScopes;

  /// History hash search scope.
  ///
  /// In en, this message translates to:
  /// **'Commit hash'**
  String get historySearchHash;

  /// History message search scope.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get historySearchMessage;

  /// History author search scope.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get historySearchAuthor;

  /// History path search scope.
  ///
  /// In en, this message translates to:
  /// **'Changed path'**
  String get historySearchPath;

  /// No description provided for @historyAcceptedFilter.
  ///
  /// In en, this message translates to:
  /// **'Showing accepted filter: {filter}'**
  String historyAcceptedFilter(String filter);

  /// No description provided for @historyPendingFilter.
  ///
  /// In en, this message translates to:
  /// **'Searching: {filter}'**
  String historyPendingFilter(String filter);

  /// Tooltip of the History toolbar menu that changes what the graph shows.
  ///
  /// In en, this message translates to:
  /// **'View options'**
  String get historyViewOptions;

  /// Menu item and button that make History also show commits only references outside branches, remote branches, tags and the stash reach, such as notes or another tool's checkpoints.
  ///
  /// In en, this message translates to:
  /// **'Show other refs'**
  String get historyShowOtherRefs;

  /// Shown when the user asks to show a commit that only references outside branches, remote branches, tags and the stash may reach.
  ///
  /// In en, this message translates to:
  /// **'History doesn\'t show this commit. Commits that only other refs reach, such as notes or tool checkpoints, are hidden.'**
  String get historyTargetOutsideRefScope;

  /// Shown when the user asks to show a commit that no reference reaches, while History shows every reference.
  ///
  /// In en, this message translates to:
  /// **'History doesn\'t show this commit. No ref reaches it.'**
  String get historyTargetNotShown;

  /// Explains retained selection outside a history query.
  ///
  /// In en, this message translates to:
  /// **'The selected commit is outside this result. Selection is retained.'**
  String get historySelectionFilteredOut;

  /// History query failure with retained result.
  ///
  /// In en, this message translates to:
  /// **'The filter could not be applied. The previous result is still shown.'**
  String get historyFilterFailed;

  /// History merge collapse action.
  ///
  /// In en, this message translates to:
  /// **'Collapse or expand selected merge'**
  String get historyCollapseSelected;

  /// No description provided for @historyCollapsedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} commits collapsed'**
  String historyCollapsedCount(int count);

  /// Open recoverable reference history.
  ///
  /// In en, this message translates to:
  /// **'Reflog'**
  String get historyReflog;

  /// Return to the commit graph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get historyGraph;

  /// Checked-out commit reference badge.
  ///
  /// In en, this message translates to:
  /// **'HEAD'**
  String get historyHeadReference;

  /// Overlay shown while folders are dragged over the application window.
  ///
  /// In en, this message translates to:
  /// **'Drop repository folders to open them'**
  String get repositoryDropPrompt;

  /// Sanitized result of an operating-system folder drop.
  ///
  /// In en, this message translates to:
  /// **'Opened {opened} repositories. Rejected {rejected} non-folder items. {failed} folders could not be opened.'**
  String repositoryDropSummary(int opened, int rejected, int failed);

  /// Retained reflog error message.
  ///
  /// In en, this message translates to:
  /// **'Reflog refresh failed. Previously loaded reflog entries remain available.'**
  String get historyReflogRetainedFailure;

  /// Empty reflog message.
  ///
  /// In en, this message translates to:
  /// **'No reflog entries are available.'**
  String get historyReflogEmpty;

  /// Navigate to the prior file inspection location.
  ///
  /// In en, this message translates to:
  /// **'Back in file inspection'**
  String get historyNavigateBack;

  /// Navigate to the next file inspection location.
  ///
  /// In en, this message translates to:
  /// **'Forward in file inspection'**
  String get historyNavigateForward;

  /// Binary or invalid text in a committed file preview.
  ///
  /// In en, this message translates to:
  /// **'This file cannot be previewed as text.'**
  String get historyTreeBinaryFile;

  /// Committed file exceeds the preview byte limit.
  ///
  /// In en, this message translates to:
  /// **'This file is too large to preview.'**
  String get historyTreeFileTooLarge;

  /// Committed file has no content.
  ///
  /// In en, this message translates to:
  /// **'This file is empty.'**
  String get historyTreeEmptyFile;

  /// Committed file preview failed.
  ///
  /// In en, this message translates to:
  /// **'Could not load this file from the selected commit.'**
  String get historyTreeFileFailed;

  /// Commit author label.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get historyAuthor;

  /// Commit co-author trailer label.
  ///
  /// In en, this message translates to:
  /// **'Co-authors'**
  String get historyCoAuthors;

  /// Commit committer label.
  ///
  /// In en, this message translates to:
  /// **'Committer'**
  String get historyCommitter;

  /// Commit date label.
  ///
  /// In en, this message translates to:
  /// **'Commit date'**
  String get historyCommitDate;

  /// Open file blame at the parent of the attributed commit.
  ///
  /// In en, this message translates to:
  /// **'Go before this change'**
  String get historyBlameBefore;

  /// Age of a blame attribution in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String blameAgeMinutes(int count);

  /// Age of a blame attribution in hours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String blameAgeHours(int count);

  /// Age of a blame attribution in days.
  ///
  /// In en, this message translates to:
  /// **'{count} d'**
  String blameAgeDays(int count);

  /// Age of a blame attribution in months.
  ///
  /// In en, this message translates to:
  /// **'{count} mo'**
  String blameAgeMonths(int count);

  /// Age of a blame attribution in years.
  ///
  /// In en, this message translates to:
  /// **'{count} y'**
  String blameAgeYears(int count);

  /// Changed-only file filter.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get historyChangedFilesShort;

  /// Count of files in a commit detail list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String historyFilesCount(int count);

  /// Open inspection actions for a commit file.
  ///
  /// In en, this message translates to:
  /// **'File actions'**
  String get historyFileActions;

  /// Open line attribution for a file.
  ///
  /// In en, this message translates to:
  /// **'Blame'**
  String get historyBlame;

  /// Open rename-aware history for a path.
  ///
  /// In en, this message translates to:
  /// **'Path history'**
  String get historyPathHistory;

  /// Previous path in a rename history row.
  ///
  /// In en, this message translates to:
  /// **'renamed from {path}'**
  String historyRenamedFrom(String path);

  /// Placeholder while a virtualized inspection row loads.
  ///
  /// In en, this message translates to:
  /// **'Loading inspection row…'**
  String get historyInspectionLoading;

  /// Preview restoring a file from the inspected commit.
  ///
  /// In en, this message translates to:
  /// **'Restore this version'**
  String get historyRestoreFile;

  /// Restore-file confirmation: what happens and when it stops.
  ///
  /// In en, this message translates to:
  /// **'Your current {path} is replaced with its version from this commit. If the file or the checked-out commit changes first, nothing happens.'**
  String historyRestorePreview(String path);

  /// Restore-file confirmation: the file does not exist now.
  ///
  /// In en, this message translates to:
  /// **'Not present'**
  String get historyRestoreNoCurrentFile;

  /// Restore-file confirmation: size of the file it replaces.
  ///
  /// In en, this message translates to:
  /// **'Current file'**
  String get historyRestoreCurrentSize;

  /// Restore-file confirmation: size of the version being restored.
  ///
  /// In en, this message translates to:
  /// **'Version in this commit'**
  String get historyRestoreSourceSize;

  /// Confirm the previewed restore.
  ///
  /// In en, this message translates to:
  /// **'Restore file'**
  String get historyRestoreConfirm;

  /// Restore success message.
  ///
  /// In en, this message translates to:
  /// **'The file was restored from the selected commit.'**
  String get historyRestoreSucceeded;

  /// Restore precondition failure message.
  ///
  /// In en, this message translates to:
  /// **'The file or the current commit changed. Nothing was restored; preview again.'**
  String get historyRestoreStale;

  /// Restore succeeded with a reconciliation warning.
  ///
  /// In en, this message translates to:
  /// **'The file was restored, but the repository refresh needs attention.'**
  String get historyRestoreReconciled;

  /// Restore outcome-uncertain message.
  ///
  /// In en, this message translates to:
  /// **'Git may have changed the file. Inspect the worktree before retrying.'**
  String get historyRestoreOutcomeUncertain;

  /// Definite restore failure message.
  ///
  /// In en, this message translates to:
  /// **'The file could not be restored.'**
  String get historyRestoreFailed;

  /// Search the retained diff content.
  ///
  /// In en, this message translates to:
  /// **'Find in diff'**
  String get diffSearchHint;

  /// Move to the previous diff search match.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get diffPreviousMatch;

  /// Move to the next diff search match.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get diffNextMatch;

  /// Toggle case-sensitive diff search.
  ///
  /// In en, this message translates to:
  /// **'Case-sensitive search'**
  String get diffCaseSensitive;

  /// Find bar counter: the current match of all matches.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String findMatchPosition(int current, int total);

  /// Find bar counter while no match is current.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String findMatchCount(int count);

  /// Find bar counter when a search found nothing.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get findNoMatches;

  /// Placeholder of the find bar over a file's contents.
  ///
  /// In en, this message translates to:
  /// **'Find in file'**
  String get findInFileHint;

  /// A pane or panel whose content is still loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// Move to the previous diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Previous hunk'**
  String get diffPreviousHunk;

  /// Move to the next diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Next hunk'**
  String get diffNextHunk;

  /// Switch to the side-by-side diff layout.
  ///
  /// In en, this message translates to:
  /// **'Side-by-side diff'**
  String get diffSideBySide;

  /// Switch to the unified diff layout.
  ///
  /// In en, this message translates to:
  /// **'Unified diff'**
  String get diffUnified;

  /// Choose the number of context lines.
  ///
  /// In en, this message translates to:
  /// **'Context lines'**
  String get diffContextLines;

  /// No description provided for @diffContextValue.
  ///
  /// In en, this message translates to:
  /// **'{count} context lines'**
  String diffContextValue(int count);

  /// Expand the context around a diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Show more lines'**
  String get diffShowMoreLines;

  /// Hide a file's diff rows.
  ///
  /// In en, this message translates to:
  /// **'Collapse file'**
  String get diffCollapseFile;

  /// Show a file's diff rows.
  ///
  /// In en, this message translates to:
  /// **'Expand file'**
  String get diffExpandFile;

  /// Cycle through exact and whitespace-ignoring comparison policies.
  ///
  /// In en, this message translates to:
  /// **'Cycle whitespace comparison'**
  String get diffWhitespace;

  /// Toggle wrapped diff lines.
  ///
  /// In en, this message translates to:
  /// **'Wrap long lines'**
  String get diffWrap;

  /// Toggle non-color addition and deletion indicators.
  ///
  /// In en, this message translates to:
  /// **'Show plus and minus indicators'**
  String get diffIndicators;

  /// Toggle the bounded diff overview.
  ///
  /// In en, this message translates to:
  /// **'Show diff minimap'**
  String get diffMinimap;

  /// Clear the selected-file diff scope.
  ///
  /// In en, this message translates to:
  /// **'Show all changed files'**
  String get diffAllFiles;

  /// Diff marker for a missing final newline.
  ///
  /// In en, this message translates to:
  /// **'No newline at end of file'**
  String get diffNoNewline;

  /// Fallback for binary diff content.
  ///
  /// In en, this message translates to:
  /// **'Binary content — text comparison is unavailable'**
  String get diffBinaryFallback;

  /// Action that shows a file Git or GitLama treats as binary as text anyway; the result may be unreadable.
  ///
  /// In en, this message translates to:
  /// **'Show as text'**
  String get showBinaryAsText;

  /// Action label for a deferred image comparison.
  ///
  /// In en, this message translates to:
  /// **'Image changed — open visual comparison'**
  String get diffImageFallback;

  /// Fallback for a submodule commit change.
  ///
  /// In en, this message translates to:
  /// **'Submodule commit changed'**
  String get diffSubmoduleFallback;

  /// No description provided for @diffModeOnlyFallback.
  ///
  /// In en, this message translates to:
  /// **'File mode changed: {modes}'**
  String diffModeOnlyFallback(String modes);

  /// Fallback for bounded oversized content.
  ///
  /// In en, this message translates to:
  /// **'Diff is too large for an inline text comparison'**
  String get diffTooLargeFallback;

  /// Image comparison dialog title.
  ///
  /// In en, this message translates to:
  /// **'Image comparison'**
  String get diffImageComparison;

  /// Old image side label.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get diffOldImage;

  /// New image side label.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get diffNewImage;

  /// Pixel dimensions of one image side in an image diff.
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} px'**
  String diffImageDimensions(int width, int height);

  /// Pixel dimensions and stored file size of one image side, such as 640 × 480 px · 47 KB.
  ///
  /// In en, this message translates to:
  /// **'{dimensions} · {size}'**
  String diffImageDetails(String dimensions, String size);

  /// Image side label followed by its dimensions and size, such as Before: 640 × 480 px · 47 KB.
  ///
  /// In en, this message translates to:
  /// **'{side}: {details}'**
  String diffImageSideDetails(String side, String details);

  /// Missing side in an added or deleted image comparison.
  ///
  /// In en, this message translates to:
  /// **'No image exists on this side.'**
  String get diffImageMissing;

  /// Bounded image decoding failure.
  ///
  /// In en, this message translates to:
  /// **'This image could not be decoded safely.'**
  String get diffImageDecodeFailed;

  /// Why an image cannot be previewed: unsupported format or SVG feature.
  ///
  /// In en, this message translates to:
  /// **'GitLama previews common image formats and SVGs without text, scripts, linked files or reused elements.'**
  String get diffImageDecodeUnsupported;

  /// Why an image cannot be previewed: corrupt file.
  ///
  /// In en, this message translates to:
  /// **'The file is not a valid image.'**
  String get diffImageDecodeMalformed;

  /// Why an image cannot be previewed: size limits.
  ///
  /// In en, this message translates to:
  /// **'The image is larger than GitLama previews.'**
  String get diffImageDecodeTooLarge;

  /// Why an image cannot be previewed: busy or timed out.
  ///
  /// In en, this message translates to:
  /// **'Decoding took too long. Select the file again to retry.'**
  String get diffImageDecodeTimedOut;

  /// Side-by-side image comparison mode.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get diffImageSideBySide;

  /// Swipe image comparison mode.
  ///
  /// In en, this message translates to:
  /// **'Swipe'**
  String get diffImageSwipe;

  /// Onion-skin image comparison mode.
  ///
  /// In en, this message translates to:
  /// **'Onion skin'**
  String get diffImageOnionSkin;

  /// Label for the swipe divider control.
  ///
  /// In en, this message translates to:
  /// **'Divider'**
  String get diffImageDivider;

  /// Label for the onion-skin blend control.
  ///
  /// In en, this message translates to:
  /// **'Blend'**
  String get diffImageBlend;

  /// Status while decoded RGBA pixels are uploaded for display.
  ///
  /// In en, this message translates to:
  /// **'Preparing decoded image…'**
  String get diffImagePreparing;

  /// Shown when image sides for an inline comparison cannot be read.
  ///
  /// In en, this message translates to:
  /// **'The image could not be loaded.'**
  String get diffImageLoadFailed;

  /// Tooltip for selecting a diff text encoding.
  ///
  /// In en, this message translates to:
  /// **'Text encoding'**
  String get diffEncoding;

  /// UTF-8 diff text encoding option.
  ///
  /// In en, this message translates to:
  /// **'UTF-8'**
  String get diffEncodingUtf8;

  /// Latin-1 diff text fallback option.
  ///
  /// In en, this message translates to:
  /// **'ISO-8859-1 fallback'**
  String get diffEncodingLatin1;

  /// Visible fallback for invalid UTF-8 diff bytes.
  ///
  /// In en, this message translates to:
  /// **'Not valid UTF-8 — choose an encoding'**
  String get diffEncodingInvalid;

  /// Title for optional diff renderer configuration and output.
  ///
  /// In en, this message translates to:
  /// **'Diff renderer'**
  String get diffRendererTitle;

  /// Label for a renderer display name.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get diffRendererName;

  /// Label of the diff renderer's stored identifier field.
  ///
  /// In en, this message translates to:
  /// **'Identifier'**
  String get diffRendererId;

  /// Security and containment explanation for diff renderers.
  ///
  /// In en, this message translates to:
  /// **'GitLama sends the diff to the program and shows the plain text it returns. Arguments are passed exactly as written, without a shell, and the output can\'t add links or controls.'**
  String get diffRendererContainmentHelp;

  /// Help for direct renderer argument entry.
  ///
  /// In en, this message translates to:
  /// **'One argument per line, passed exactly as written, without a shell.'**
  String get diffRendererArgumentsHelp;

  /// Tooltip when no optional renderer is configured.
  ///
  /// In en, this message translates to:
  /// **'No diff renderer is configured'**
  String get diffRendererNotConfigured;

  /// Action to run a configured renderer.
  ///
  /// In en, this message translates to:
  /// **'Render diff'**
  String get diffRendererRun;

  /// Title of the confirmation before an external diff renderer runs.
  ///
  /// In en, this message translates to:
  /// **'Run the diff renderer?'**
  String get diffRendererPreviewTitle;

  /// What running the diff renderer does, above its facts.
  ///
  /// In en, this message translates to:
  /// **'GitLama sends the selected diff to this program and shows the plain text it returns.'**
  String get diffRendererRunSummary;

  /// Label of the command line that checks what a diff renderer can do.
  ///
  /// In en, this message translates to:
  /// **'Check command'**
  String get diffRendererCapabilityCommand;

  /// Label for the exact renderer execution command.
  ///
  /// In en, this message translates to:
  /// **'Render command'**
  String get diffRendererRenderCommand;

  /// Label of the renderer protocol version.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get diffRendererProtocol;

  /// Label of the media type a renderer returns.
  ///
  /// In en, this message translates to:
  /// **'Output format'**
  String get diffRendererOutputFormat;

  /// Label of how long a renderer may run.
  ///
  /// In en, this message translates to:
  /// **'Time limit'**
  String get diffRendererTimeLimit;

  /// Label of the most text a renderer may return.
  ///
  /// In en, this message translates to:
  /// **'Output limit'**
  String get diffRendererOutputLimit;

  /// Label of the size of the diff sent to a renderer.
  ///
  /// In en, this message translates to:
  /// **'Diff size'**
  String get diffRendererInputSize;

  /// Label of the program a diff renderer runs.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get diffRendererProgram;

  /// Title of the confirmation that saves a diff renderer after its check passed.
  ///
  /// In en, this message translates to:
  /// **'Save this diff renderer?'**
  String get diffRendererValidatedTitle;

  /// What saving a checked diff renderer means, above its facts.
  ///
  /// In en, this message translates to:
  /// **'The program passed the check and can show diffs as plain text. GitLama asks before each run.'**
  String get diffRendererValidatedSummary;

  /// Action to save a validated renderer.
  ///
  /// In en, this message translates to:
  /// **'Save renderer'**
  String get diffRendererSave;

  /// Action to return to the authoritative built-in diff.
  ///
  /// In en, this message translates to:
  /// **'Use built-in'**
  String get diffRendererUseBuiltIn;

  /// Renderer output containment and fallback summary.
  ///
  /// In en, this message translates to:
  /// **'Inert plain-text output with built-in diff available'**
  String get diffRendererPlainText;

  /// Renderer fallback reason for invalid configuration.
  ///
  /// In en, this message translates to:
  /// **'The renderer configuration is invalid. The built-in diff remains active.'**
  String get diffRendererInvalidDefinition;

  /// Renderer fallback reason for an unavailable executable.
  ///
  /// In en, this message translates to:
  /// **'The renderer executable is unavailable. The built-in diff remains active.'**
  String get diffRendererUnavailable;

  /// Renderer fallback reason for an invalid capability response.
  ///
  /// In en, this message translates to:
  /// **'The renderer did not provide the required plain-text capability. The built-in diff remains active.'**
  String get diffRendererInvalidCapability;

  /// Renderer fallback reason for oversized input.
  ///
  /// In en, this message translates to:
  /// **'The diff exceeds the renderer input limit. The built-in diff remains active.'**
  String get diffRendererInputTooLarge;

  /// Renderer fallback reason for oversized output.
  ///
  /// In en, this message translates to:
  /// **'The renderer output exceeded its limit. The built-in diff remains active.'**
  String get diffRendererOutputTooLarge;

  /// Renderer fallback reason for launch failure.
  ///
  /// In en, this message translates to:
  /// **'The renderer could not start. The built-in diff remains active.'**
  String get diffRendererLaunchFailed;

  /// Renderer fallback reason for a failed process.
  ///
  /// In en, this message translates to:
  /// **'The renderer exited with a failure. The built-in diff remains active.'**
  String get diffRendererProcessFailed;

  /// Renderer fallback reason for timeout.
  ///
  /// In en, this message translates to:
  /// **'The renderer timed out. The built-in diff remains active.'**
  String get diffRendererTimedOut;

  /// Renderer fallback reason for cancellation.
  ///
  /// In en, this message translates to:
  /// **'The renderer was canceled. The built-in diff remains active.'**
  String get diffRendererCanceled;

  /// Renderer fallback reason for stale source identity.
  ///
  /// In en, this message translates to:
  /// **'The selected diff changed. The built-in diff remains active.'**
  String get diffRendererStale;

  /// Heading for index changes.
  ///
  /// In en, this message translates to:
  /// **'Staged changes'**
  String get changesStaged;

  /// Heading for working-tree changes.
  ///
  /// In en, this message translates to:
  /// **'Unstaged changes'**
  String get changesUnstaged;

  /// Uses a flat list for a Changes file pane.
  ///
  /// In en, this message translates to:
  /// **'Show files as a list'**
  String get changesListView;

  /// Uses a directory tree for a Changes file pane.
  ///
  /// In en, this message translates to:
  /// **'Show files as a tree'**
  String get changesTreeView;

  /// Marks a file that has staged and unstaged changes.
  ///
  /// In en, this message translates to:
  /// **'partial'**
  String get changesPartial;

  /// Accessible label for the splitter above the commit editor.
  ///
  /// In en, this message translates to:
  /// **'Resize the commit editor'**
  String get changesResizeCommit;

  /// Accessible label for the Changes pane splitter.
  ///
  /// In en, this message translates to:
  /// **'Resize staged and unstaged panes'**
  String get changesResizePanes;

  /// Accessible label for the workspace detail pane splitter.
  ///
  /// In en, this message translates to:
  /// **'Resize the detail pane'**
  String get workspaceResizeDetail;

  /// Accessible label for the repository sidebar splitter.
  ///
  /// In en, this message translates to:
  /// **'Resize the repository sidebar'**
  String get workspaceResizeSidebar;

  /// Copies a repository-relative file path.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyFilePath;

  /// Opens a changed file in the configured or discovered editor.
  ///
  /// In en, this message translates to:
  /// **'Open in external editor'**
  String get openFileExternal;

  /// Opens a file, folder, or worktree in the named system file browser.
  ///
  /// In en, this message translates to:
  /// **'Open in {browser}'**
  String openInFileBrowser(String browser);

  /// Tooltip for the immediate staging drag handle.
  ///
  /// In en, this message translates to:
  /// **'Drag to the other change list'**
  String get dragChangeToOtherList;

  /// Confirms that a changed file path was copied.
  ///
  /// In en, this message translates to:
  /// **'File path copied.'**
  String get filePathCopied;

  /// Stages every working-tree change.
  ///
  /// In en, this message translates to:
  /// **'Stage all'**
  String get stageAll;

  /// Removes every index change from the staged set.
  ///
  /// In en, this message translates to:
  /// **'Unstage all'**
  String get unstageAll;

  /// Stages the selected files.
  ///
  /// In en, this message translates to:
  /// **'Stage selected'**
  String get stageSelected;

  /// Unstages the selected files.
  ///
  /// In en, this message translates to:
  /// **'Unstage selected'**
  String get unstageSelected;

  /// Stages one file.
  ///
  /// In en, this message translates to:
  /// **'Stage file'**
  String get stageFile;

  /// Unstages one file.
  ///
  /// In en, this message translates to:
  /// **'Unstage file'**
  String get unstageFile;

  /// Opens partial staging for one file.
  ///
  /// In en, this message translates to:
  /// **'Select changed lines'**
  String get inspectChanges;

  /// Explains how lines and sections are picked in the select-changed-lines dialog.
  ///
  /// In en, this message translates to:
  /// **'Tick single changed lines, or a section header to take the whole section.'**
  String get inspectChangesHelp;

  /// How many changed lines are picked in the select-changed-lines dialog.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No lines selected} =1{1 line selected} other{{count} lines selected}}'**
  String lineSelectionCount(int count);

  /// Picked line count when a picked section still has lines that are not loaded yet.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{At least 1 line selected} other{At least {count} lines selected}}'**
  String lineSelectionCountAtLeast(int count);

  /// Accessible name of a section header checkbox in the select-changed-lines dialog.
  ///
  /// In en, this message translates to:
  /// **'Section {header}'**
  String lineSelectionSection(String header);

  /// Accessible name of an added line's checkbox in the select-changed-lines dialog.
  ///
  /// In en, this message translates to:
  /// **'Added line {line}: {text}'**
  String lineSelectionAdded(int line, String text);

  /// Accessible name of a removed line's checkbox in the select-changed-lines dialog.
  ///
  /// In en, this message translates to:
  /// **'Removed line {line}: {text}'**
  String lineSelectionRemoved(int line, String text);

  /// Stages selected hunks or lines.
  ///
  /// In en, this message translates to:
  /// **'Stage selected changes'**
  String get stageLines;

  /// Unstages selected hunks or lines.
  ///
  /// In en, this message translates to:
  /// **'Unstage selected changes'**
  String get unstageLines;

  /// A staging mutation completed.
  ///
  /// In en, this message translates to:
  /// **'Staged changes updated.'**
  String get stagingCompleted;

  /// A staging request was refused because its accepted state drifted.
  ///
  /// In en, this message translates to:
  /// **'The files changed in the meantime. Nothing was staged or unstaged.'**
  String get stagingStale;

  /// A staging mutation failed before commit.
  ///
  /// In en, this message translates to:
  /// **'The staged changes could not be updated.'**
  String get stagingFailed;

  /// A staging mutation committed but reconciliation degraded.
  ///
  /// In en, this message translates to:
  /// **'The staged changes were updated, but the file lists could not be refreshed.'**
  String get stagingWarning;

  /// A staged or unstaged list is empty.
  ///
  /// In en, this message translates to:
  /// **'No changes on this side.'**
  String get stagingEmpty;

  /// Command title for toggling selected changes between the index and working tree.
  ///
  /// In en, this message translates to:
  /// **'Stage or unstage'**
  String get commandStageToggle;

  /// Switches between unified and side-by-side diff layouts.
  ///
  /// In en, this message translates to:
  /// **'Toggle diff layout'**
  String get commandDiffToggleLayout;

  /// Runs the configured diff renderer for the active diff.
  ///
  /// In en, this message translates to:
  /// **'Render diff with configured renderer'**
  String get commandDiffRenderConfigured;

  /// Toggles line wrapping in the active diff.
  ///
  /// In en, this message translates to:
  /// **'Toggle diff line wrap'**
  String get commandDiffToggleWrap;

  /// Moves to the next diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Next hunk'**
  String get commandDiffNextHunk;

  /// Moves to the previous diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Previous hunk'**
  String get commandDiffPreviousHunk;

  /// Loads the next bounded working-diff page.
  ///
  /// In en, this message translates to:
  /// **'Load more changes'**
  String get stagingLoadMore;

  /// Label for the commit subject field.
  ///
  /// In en, this message translates to:
  /// **'Commit subject'**
  String get commitSubject;

  /// Label for the commit description field.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commitDescription;

  /// Label for comma-separated co-author identities.
  ///
  /// In en, this message translates to:
  /// **'Co-authors'**
  String get commitCoauthors;

  /// Label for an optional commit author identity.
  ///
  /// In en, this message translates to:
  /// **'Author override'**
  String get commitAuthor;

  /// Secondary commit-editor options dialog title.
  ///
  /// In en, this message translates to:
  /// **'Commit options'**
  String get commitOptions;

  /// Creates a commit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get commitAction;

  /// Creates a commit on the current branch.
  ///
  /// In en, this message translates to:
  /// **'Commit to {branch}'**
  String commitToBranch(String branch);

  /// Amends the current commit.
  ///
  /// In en, this message translates to:
  /// **'Amend {hash}'**
  String commitAmendHash(String hash);

  /// Count of staged files in the composer.
  ///
  /// In en, this message translates to:
  /// **'{count} staged'**
  String changesStagedFilesCount(int count);

  /// Badge while dragging files into the index.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Stage 1 file} other{Stage {count} files}}'**
  String changesDragStageCount(int count);

  /// Badge while dragging files out of the index.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Unstage 1 file → Working tree} other{Unstage {count} files → Working tree}}'**
  String changesDragUnstageCount(int count);

  /// Creates a commit and then pushes it.
  ///
  /// In en, this message translates to:
  /// **'Commit & push'**
  String get commitAndPush;

  /// Safe notification when the HEAD message requested by Amend could not be loaded; toggling retries the read.
  ///
  /// In en, this message translates to:
  /// **'Could not load the last commit message. Turn Amend off and on to retry, or enter a message.'**
  String get commitAmendMessageFailed;

  /// Amends the current HEAD commit.
  ///
  /// In en, this message translates to:
  /// **'Amend'**
  String get commitAmend;

  /// Adds the configured author sign-off trailer.
  ///
  /// In en, this message translates to:
  /// **'Sign off'**
  String get commitSignOff;

  /// Runs commit with hooks disabled.
  ///
  /// In en, this message translates to:
  /// **'Skip hooks'**
  String get commitSkipHooks;

  /// Enables platform spellchecking in the commit editor.
  ///
  /// In en, this message translates to:
  /// **'Spellcheck'**
  String get commitSpellcheck;

  /// Applies the configured commit template.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get commitTemplate;

  /// Opens recent commit messages.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get commitRecent;

  /// Opens the commit-signing policy menu.
  ///
  /// In en, this message translates to:
  /// **'Commit signing'**
  String get commitSigning;

  /// Leaves commit signing to the repository Git configuration.
  ///
  /// In en, this message translates to:
  /// **'Use Git configuration'**
  String get commitSigningGit;

  /// Requires Git to sign the commit.
  ///
  /// In en, this message translates to:
  /// **'Require signature'**
  String get commitSigningRequired;

  /// Disables Git commit signing for this attempt.
  ///
  /// In en, this message translates to:
  /// **'Commit unsigned'**
  String get commitSigningDisabled;

  /// Inline title for a typed commit-hook failure.
  ///
  /// In en, this message translates to:
  /// **'Commit hook failed'**
  String get commitHookFailure;

  /// Inline title for a typed commit-signing failure.
  ///
  /// In en, this message translates to:
  /// **'Commit signing failed'**
  String get commitSigningFailure;

  /// Inline title for another Git commit failure.
  ///
  /// In en, this message translates to:
  /// **'Git rejected the commit'**
  String get commitOtherFailure;

  /// No description provided for @commitFailureExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit code {code}'**
  String commitFailureExitCode(int code);

  /// Retries the failed commit with the same policy.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commitRetry;

  /// Typed confirmation title before bypassing commit hooks.
  ///
  /// In en, this message translates to:
  /// **'Skip commit hooks?'**
  String get commitSkipHooksConfirmTitle;

  /// Explains the typed hook-bypass confirmation.
  ///
  /// In en, this message translates to:
  /// **'Hooks are checks this repository runs before each commit. This attempt skips them. Type SKIP to confirm.'**
  String get commitSkipHooksConfirmBody;

  /// Label for the hook-bypass confirmation field.
  ///
  /// In en, this message translates to:
  /// **'Type SKIP'**
  String get commitSkipHooksConfirmInput;

  /// No description provided for @commitCommittedObject.
  ///
  /// In en, this message translates to:
  /// **'Committed {objectId}'**
  String commitCommittedObject(String objectId);

  /// Commit subject validation hint.
  ///
  /// In en, this message translates to:
  /// **'Enter a subject before committing.'**
  String get commitEmptySubject;

  /// Why Commit is disabled while nothing is staged.
  ///
  /// In en, this message translates to:
  /// **'Stage changes before committing.'**
  String get commitNothingStaged;

  /// Commit subject whitespace warning.
  ///
  /// In en, this message translates to:
  /// **'The subject ends with whitespace.'**
  String get commitTrailingWhitespace;

  /// Warning shown before amending a published commit.
  ///
  /// In en, this message translates to:
  /// **'This commit appears on a remote branch. Amending it rewrites published history.'**
  String get commitPublishedWarning;

  /// Confirmation action for a published amend.
  ///
  /// In en, this message translates to:
  /// **'Amend published commit'**
  String get commitConfirmAmend;

  /// Commit success message.
  ///
  /// In en, this message translates to:
  /// **'Commit created.'**
  String get commitCompleted;

  /// A commit preview became stale.
  ///
  /// In en, this message translates to:
  /// **'The current commit or the staged changes changed. Nothing was committed.'**
  String get commitStale;

  /// Commit failure message.
  ///
  /// In en, this message translates to:
  /// **'Git rejected the commit. The draft was kept.'**
  String get commitFailed;

  /// Commit succeeded with degraded reconciliation.
  ///
  /// In en, this message translates to:
  /// **'Commit created, but refresh needs attention.'**
  String get commitWarning;

  /// Discards selected tracked worktree changes.
  ///
  /// In en, this message translates to:
  /// **'Discard selected'**
  String get discardSelected;

  /// Discards all compatible unstaged changes.
  ///
  /// In en, this message translates to:
  /// **'Discard all'**
  String get discardAll;

  /// Deletes selected untracked paths.
  ///
  /// In en, this message translates to:
  /// **'Clean selected'**
  String get cleanSelected;

  /// Discards one tracked file's worktree changes.
  ///
  /// In en, this message translates to:
  /// **'Discard file changes'**
  String get discardFile;

  /// Deletes one untracked path.
  ///
  /// In en, this message translates to:
  /// **'Delete new file or folder'**
  String get cleanFile;

  /// Discards selected hunk or line changes.
  ///
  /// In en, this message translates to:
  /// **'Discard selected changes'**
  String get discardLines;

  /// Irreversible discard confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Permanently discard changes?'**
  String get discardConfirmTitle;

  /// Irreversible clean confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete new files?'**
  String get cleanConfirmTitle;

  /// Irreversible action confirmation body.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This affects 1 file.} other{This affects {count} files.}} The changes are deleted permanently.'**
  String discardConfirmMessage(int count);

  /// Confirms tracked discard.
  ///
  /// In en, this message translates to:
  /// **'Discard permanently'**
  String get discardConfirmAction;

  /// Confirms untracked deletion.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get cleanConfirmAction;

  /// Irreversible action success.
  ///
  /// In en, this message translates to:
  /// **'Changes were permanently discarded.'**
  String get discardCompleted;

  /// Irreversible preview stale result.
  ///
  /// In en, this message translates to:
  /// **'The confirmed paths changed. Nothing was discarded.'**
  String get discardStale;

  /// Irreversible action failure.
  ///
  /// In en, this message translates to:
  /// **'Git could not discard the confirmed changes.'**
  String get discardFailed;

  /// Irreversible action reconciliation warning.
  ///
  /// In en, this message translates to:
  /// **'Changes were discarded, but refresh needs attention.'**
  String get discardWarning;

  /// Patch creation and application dialog title.
  ///
  /// In en, this message translates to:
  /// **'Patches'**
  String get patchTitle;

  /// Description of the Patches dialog while creating a patch.
  ///
  /// In en, this message translates to:
  /// **'Save changes as a patch file that you can share or apply elsewhere.'**
  String get patchCreateDescription;

  /// Description of the Patches dialog while applying a patch.
  ///
  /// In en, this message translates to:
  /// **'Apply the changes in a patch file to this repository\'s files.'**
  String get patchApplyDescription;

  /// Patch creation action.
  ///
  /// In en, this message translates to:
  /// **'Create patch'**
  String get patchCreate;

  /// Patch application action.
  ///
  /// In en, this message translates to:
  /// **'Apply patch'**
  String get patchApply;

  /// Writes a checked patch export.
  ///
  /// In en, this message translates to:
  /// **'Write patch'**
  String get patchWrite;

  /// Chooses a patch export directory.
  ///
  /// In en, this message translates to:
  /// **'Choose destination'**
  String get patchChooseDestination;

  /// Chooses a patch to apply.
  ///
  /// In en, this message translates to:
  /// **'Choose patch file'**
  String get patchChooseFile;

  /// Patch output destination label.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get patchDestination;

  /// Patch destination empty state.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder to see what will be written.'**
  String get patchDestinationUnset;

  /// Patch export scope label.
  ///
  /// In en, this message translates to:
  /// **'Contains'**
  String get patchScope;

  /// Patch format label.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get patchFormat;

  /// Patch filename label.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get patchFilename;

  /// Patch byte count label.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get patchSize;

  /// Unified patch format.
  ///
  /// In en, this message translates to:
  /// **'Unified diff'**
  String get patchFormatUnified;

  /// Git format-patch output format.
  ///
  /// In en, this message translates to:
  /// **'Email patch series'**
  String get patchFormatEmail;

  /// Patch overwrite confirmation warning.
  ///
  /// In en, this message translates to:
  /// **'A file with this name already exists in the folder. Replace it, or choose another folder.'**
  String get patchOverwriteWarning;

  /// Confirms patch destination overwrite.
  ///
  /// In en, this message translates to:
  /// **'Replace existing file'**
  String get patchOverwrite;

  /// Patch export success.
  ///
  /// In en, this message translates to:
  /// **'Patch created.'**
  String get patchExportDone;

  /// Patch export stale result.
  ///
  /// In en, this message translates to:
  /// **'The repository or destination changed. Nothing was written.'**
  String get patchExportStale;

  /// Patch export failure.
  ///
  /// In en, this message translates to:
  /// **'The patch could not be created.'**
  String get patchExportFailed;

  /// Patch application target label.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get patchTarget;

  /// Current patch target repository.
  ///
  /// In en, this message translates to:
  /// **'Current repository'**
  String get patchCurrentRepository;

  /// Patch input file label.
  ///
  /// In en, this message translates to:
  /// **'Patch file'**
  String get patchFile;

  /// Patch input empty state.
  ///
  /// In en, this message translates to:
  /// **'Choose a .patch or .diff file.'**
  String get patchFileUnset;

  /// Patch apply preflight label.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get patchCheck;

  /// Patch preflight success.
  ///
  /// In en, this message translates to:
  /// **'Applies cleanly'**
  String get patchCheckPassed;

  /// Patch binary involvement label.
  ///
  /// In en, this message translates to:
  /// **'Binary changes'**
  String get patchBinary;

  /// Count above the files a patch changes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file changes} other{{count} files change}}'**
  String patchFileCount(int count);

  /// Label of the path a patch was written to.
  ///
  /// In en, this message translates to:
  /// **'Saved to'**
  String get patchSavedTo;

  /// Affirmative patch detail value.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get patchYes;

  /// Negative patch detail value.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get patchNo;

  /// Patch apply success.
  ///
  /// In en, this message translates to:
  /// **'Patch applied.'**
  String get patchApplyDone;

  /// Patch apply stale result.
  ///
  /// In en, this message translates to:
  /// **'The patch or target files changed. Nothing was applied.'**
  String get patchApplyStale;

  /// Patch apply failure.
  ///
  /// In en, this message translates to:
  /// **'The patch did not pass its checks and was not applied.'**
  String get patchApplyFailed;

  /// Patch apply reconciliation warning.
  ///
  /// In en, this message translates to:
  /// **'The patch was applied, but the view may be out of date.'**
  String get patchApplyWarning;

  /// Patch apply whose result could not be confirmed.
  ///
  /// In en, this message translates to:
  /// **'Git may have applied part of the patch. Check your files before trying again.'**
  String get patchApplyOutcomeUncertain;

  /// Selected line patch scope.
  ///
  /// In en, this message translates to:
  /// **'Selected lines'**
  String get patchScopeLines;

  /// Selected unstaged file patch scope.
  ///
  /// In en, this message translates to:
  /// **'Selected unstaged files'**
  String get patchScopeSelectedUnstaged;

  /// Selected staged file patch scope.
  ///
  /// In en, this message translates to:
  /// **'Selected staged files'**
  String get patchScopeSelectedStaged;

  /// Unstaged patch scope.
  ///
  /// In en, this message translates to:
  /// **'All unstaged changes'**
  String get patchScopeUnstaged;

  /// Staged patch scope.
  ///
  /// In en, this message translates to:
  /// **'All staged changes'**
  String get patchScopeStaged;

  /// HEAD patch scope.
  ///
  /// In en, this message translates to:
  /// **'All changes since the last commit'**
  String get patchScopeHead;

  /// Single commit patch scope.
  ///
  /// In en, this message translates to:
  /// **'Selected commit'**
  String get patchScopeCommit;

  /// Commit range patch scope.
  ///
  /// In en, this message translates to:
  /// **'Selected commit range'**
  String get patchScopeRange;

  /// Comparison patch scope.
  ///
  /// In en, this message translates to:
  /// **'Active comparison'**
  String get patchScopeCompare;

  /// Fetch command.
  ///
  /// In en, this message translates to:
  /// **'Fetch…'**
  String get commandFetch;

  /// Fetches the selected remote after preview.
  ///
  /// In en, this message translates to:
  /// **'Fetch remote'**
  String get commandFetchRemote;

  /// Pull command.
  ///
  /// In en, this message translates to:
  /// **'Pull…'**
  String get commandPull;

  /// Push command.
  ///
  /// In en, this message translates to:
  /// **'Push…'**
  String get commandPush;

  /// Pushes to the selected remote after preview.
  ///
  /// In en, this message translates to:
  /// **'Push remote'**
  String get commandPushRemote;

  /// Opens the bound provider's pull-request creation page.
  ///
  /// In en, this message translates to:
  /// **'Create pull request in browser'**
  String get commandHostingCreatePullRequest;

  /// Compares the two selected commits.
  ///
  /// In en, this message translates to:
  /// **'Compare commits'**
  String get commandHistoryCompare;

  /// Opens blame for the selected file.
  ///
  /// In en, this message translates to:
  /// **'Blame file'**
  String get commandHistoryBlame;

  /// Opens history for the selected file.
  ///
  /// In en, this message translates to:
  /// **'File history'**
  String get commandHistoryPathHistory;

  /// Opens the interactive rebase editor.
  ///
  /// In en, this message translates to:
  /// **'Interactive rebase…'**
  String get commandInteractiveRebase;

  /// Marks the focused rebase entry as squash.
  ///
  /// In en, this message translates to:
  /// **'Squash rebase entry'**
  String get commandRebaseSquash;

  /// Marks the focused rebase entry as fixup.
  ///
  /// In en, this message translates to:
  /// **'Fixup rebase entry'**
  String get commandRebaseFixup;

  /// Marks the focused rebase entry for rewording.
  ///
  /// In en, this message translates to:
  /// **'Reword rebase entry'**
  String get commandRebaseReword;

  /// Marks the focused rebase entry for removal.
  ///
  /// In en, this message translates to:
  /// **'Drop rebase entry'**
  String get commandRebaseDrop;

  /// Open the active repository in the configured editor.
  ///
  /// In en, this message translates to:
  /// **'Open in editor'**
  String get commandOpenInEditor;

  /// Open the active repository in the configured terminal.
  ///
  /// In en, this message translates to:
  /// **'Open in terminal'**
  String get commandOpenInTerminal;

  /// Transfer remote field.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get transferRemote;

  /// Transfer branch field.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get transferBranch;

  /// Exact local tag field for a tag push.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get transferTag;

  /// Help text for the exact local tag push field.
  ///
  /// In en, this message translates to:
  /// **'The exact local tag name to publish'**
  String get transferTagHelp;

  /// Pull strategy field.
  ///
  /// In en, this message translates to:
  /// **'How to combine changes'**
  String get transferPullStrategy;

  /// Fast-forward only pull strategy.
  ///
  /// In en, this message translates to:
  /// **'Only if no merge is needed'**
  String get transferFfOnly;

  /// Merge pull strategy.
  ///
  /// In en, this message translates to:
  /// **'Merge if needed'**
  String get transferFfPossible;

  /// Rebase pull strategy.
  ///
  /// In en, this message translates to:
  /// **'Put my commits on top (rebase)'**
  String get transferRebase;

  /// Dirty pull acknowledgement.
  ///
  /// In en, this message translates to:
  /// **'Pull with my uncommitted changes'**
  String get transferAllowDirty;

  /// Explains the option to pull while the working tree has uncommitted changes.
  ///
  /// In en, this message translates to:
  /// **'No stash is created. Git may refuse overlapping edits or a rebase. Choose stash and reapply to save your changes first.'**
  String get transferAllowDirtyHelp;

  /// Set upstream push option.
  ///
  /// In en, this message translates to:
  /// **'Link this branch to the remote branch'**
  String get transferSetUpstream;

  /// Explains setting the pushed branch as the upstream of the local branch.
  ///
  /// In en, this message translates to:
  /// **'Later pulls and pushes of this branch use the same remote branch.'**
  String get transferSetUpstreamHelp;

  /// Safe force-push option.
  ///
  /// In en, this message translates to:
  /// **'Force push with lease'**
  String get transferForceWithLease;

  /// Push dialog option: force push with lease, in plain words.
  ///
  /// In en, this message translates to:
  /// **'Overwrite the remote branch'**
  String get transferForceOption;

  /// Accessible label for the modified file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get statusGlyphModified;

  /// Accessible label for the added file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get statusGlyphAdded;

  /// Accessible label for the deleted file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get statusGlyphDeleted;

  /// Accessible label for the renamed file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get statusGlyphRenamed;

  /// Accessible label for the copied file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get statusGlyphCopied;

  /// Accessible label for the conflict file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get statusGlyphConflict;

  /// Accessible label for the untracked file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Untracked'**
  String get statusGlyphUntracked;

  /// Accessible label for the ignored file status glyph.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get statusGlyphIgnored;

  /// Tooltip for ahead and behind sync counts.
  ///
  /// In en, this message translates to:
  /// **'{ahead} ahead, {behind} behind'**
  String syncAheadBehind(int ahead, int behind);

  /// No description provided for @transferAheadBehind.
  ///
  /// In en, this message translates to:
  /// **'Ahead {ahead} · Behind {behind}'**
  String transferAheadBehind(String ahead, String behind);

  /// Transfer credentials title.
  ///
  /// In en, this message translates to:
  /// **'Authentication required'**
  String get transferCredentialsTitle;

  /// Transient credential explanation.
  ///
  /// In en, this message translates to:
  /// **'Credentials are used for this retry only and are not stored.'**
  String get transferCredentialsTransient;

  /// Transfer username field.
  ///
  /// In en, this message translates to:
  /// **'Username (optional)'**
  String get transferUsername;

  /// Transfer password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get transferPassword;

  /// Transfer token field.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get transferToken;

  /// Token credential selector.
  ///
  /// In en, this message translates to:
  /// **'Use an access token'**
  String get transferUseToken;

  /// No description provided for @transferCompleted.
  ///
  /// In en, this message translates to:
  /// **'Transfer completed. Ahead {ahead} · Behind {behind}.'**
  String transferCompleted(String ahead, String behind);

  /// Transfer reconciliation warning.
  ///
  /// In en, this message translates to:
  /// **'The transfer completed, but the view could not be refreshed.'**
  String get transferReconciledWarning;

  /// Generic transfer failure.
  ///
  /// In en, this message translates to:
  /// **'The transfer failed.'**
  String get transferFailed;

  /// Invalid transfer failure.
  ///
  /// In en, this message translates to:
  /// **'The transfer request is invalid.'**
  String get transferFailureInvalid;

  /// Detached head transfer failure.
  ///
  /// In en, this message translates to:
  /// **'Check out a branch before pulling or pushing.'**
  String get transferFailureDetached;

  /// Missing upstream failure.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid remote and branch. Force push also needs a fetched lease.'**
  String get transferFailureUpstream;

  /// Dirty pull failure.
  ///
  /// In en, this message translates to:
  /// **'Commit or stash your changes first, or choose how to handle them in the Pull dialog.'**
  String get transferFailureDirty;

  /// Conflicted pull failure.
  ///
  /// In en, this message translates to:
  /// **'Resolve the current conflicts before pulling.'**
  String get transferFailureConflicted;

  /// Stale transfer failure.
  ///
  /// In en, this message translates to:
  /// **'Repository state changed after the preview. Review the transfer again.'**
  String get transferFailureStale;

  /// Authentication transfer failure.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Retry with credentials.'**
  String get transferFailureAuthentication;

  /// Credential broker failure.
  ///
  /// In en, this message translates to:
  /// **'Secure credential retry is unavailable on this platform.'**
  String get transferFailureCredentialBroker;

  /// Host-key transfer failure.
  ///
  /// In en, this message translates to:
  /// **'SSH host-key verification failed.'**
  String get transferFailureHostKey;

  /// Git transfer failure without a more specific diagnosis.
  ///
  /// In en, this message translates to:
  /// **'Git could not complete the transfer. Check the operation log for details.'**
  String get transferFailureRejected;

  /// Transfer timeout failure.
  ///
  /// In en, this message translates to:
  /// **'The transfer stopped after producing no progress.'**
  String get transferFailureTimeout;

  /// Transfer canceled failure.
  ///
  /// In en, this message translates to:
  /// **'The transfer was canceled.'**
  String get transferFailureCanceled;

  /// Missing Git transfer failure.
  ///
  /// In en, this message translates to:
  /// **'Git could not be started.'**
  String get transferFailureMissingGit;

  /// Local Git object failure.
  ///
  /// In en, this message translates to:
  /// **'Git could not read data it needs for this transfer.'**
  String get transferFailureMissingObject;

  /// Title for the object refetch offer.
  ///
  /// In en, this message translates to:
  /// **'Missing Git objects'**
  String get transferMissingObjectTitle;

  /// No description provided for @transferMissingObjectDetail.
  ///
  /// In en, this message translates to:
  /// **'Git could not read data it needs to finish. Fetching again from {remote} may restore it. A failed pull may already have changed files, so review Changes before retrying. Fetching again will not discard or finish those changes.'**
  String transferMissingObjectDetail(String remote);

  /// Requests reachable Git objects again.
  ///
  /// In en, this message translates to:
  /// **'Refetch objects'**
  String get transferRefetchAction;

  /// Object refetch completed without retrying the failed operation.
  ///
  /// In en, this message translates to:
  /// **'Objects fetched. Review any changes left by the failed operation before retrying.'**
  String get transferRefetchCompleted;

  /// Apply stash command.
  ///
  /// In en, this message translates to:
  /// **'Apply stash…'**
  String get commandApplyStash;

  /// Pop stash command.
  ///
  /// In en, this message translates to:
  /// **'Pop stash…'**
  String get commandPopStash;

  /// Rename stash command.
  ///
  /// In en, this message translates to:
  /// **'Rename stash…'**
  String get commandRenameStash;

  /// Drop stash command.
  ///
  /// In en, this message translates to:
  /// **'Drop stash…'**
  String get commandDropStash;

  /// Auto-stash checkout command.
  ///
  /// In en, this message translates to:
  /// **'Auto-stash and check out…'**
  String get commandAutoStashCheckout;

  /// No description provided for @stashSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected stash: {selector}'**
  String stashSelected(String selector);

  /// Optional stash message field.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get stashMessage;

  /// Stash rename field.
  ///
  /// In en, this message translates to:
  /// **'New stash name'**
  String get stashNewName;

  /// Include-untracked stash option.
  ///
  /// In en, this message translates to:
  /// **'Include new files'**
  String get stashIncludeUntracked;

  /// Keep-index stash option.
  ///
  /// In en, this message translates to:
  /// **'Keep staged changes'**
  String get stashKeepIndex;

  /// Auto-stash checkout target field.
  ///
  /// In en, this message translates to:
  /// **'Target branch'**
  String get stashTargetBranch;

  /// Irreversible stash drop warning.
  ///
  /// In en, this message translates to:
  /// **'Dropping deletes this stash from the stack for good.'**
  String get stashDropWarning;

  /// Stash preview title.
  ///
  /// In en, this message translates to:
  /// **'Review stash'**
  String get stashPreviewTitle;

  /// Failed stash retention detail.
  ///
  /// In en, this message translates to:
  /// **'If applying fails, the stash is kept so nothing is lost.'**
  String get stashRecoveryRetained;

  /// Stash completion result.
  ///
  /// In en, this message translates to:
  /// **'Stash operation completed.'**
  String get stashCompleted;

  /// Stash reconciliation warning.
  ///
  /// In en, this message translates to:
  /// **'The operation completed, but the repository refresh needs attention.'**
  String get stashReconciledWarning;

  /// Generic stash failure.
  ///
  /// In en, this message translates to:
  /// **'The stash operation failed.'**
  String get stashFailed;

  /// Stash conflict result.
  ///
  /// In en, this message translates to:
  /// **'The stash produced conflicts. Open the conflict workflow to continue.'**
  String get stashConflict;

  /// Stash conflict with retained entry result.
  ///
  /// In en, this message translates to:
  /// **'The stash produced conflicts and remains on the stack. Open the conflict workflow to continue.'**
  String get stashConflictRetained;

  /// Invalid stash request failure.
  ///
  /// In en, this message translates to:
  /// **'The stash request is invalid.'**
  String get stashFailureInvalid;

  /// Nothing-to-stash failure.
  ///
  /// In en, this message translates to:
  /// **'Git found no matching changes it could stash. Commit or stash edits inside submodules in their own repository before checking out.'**
  String get stashFailureNothing;

  /// Missing stash failure.
  ///
  /// In en, this message translates to:
  /// **'The selected stash no longer exists.'**
  String get stashFailureMissing;

  /// Stale stash preview failure.
  ///
  /// In en, this message translates to:
  /// **'Repository or stash state changed after the preview. Review the operation again.'**
  String get stashFailureStale;

  /// Canceled stash failure.
  ///
  /// In en, this message translates to:
  /// **'The stash operation was canceled.'**
  String get stashFailureCanceled;

  /// Timed-out stash failure.
  ///
  /// In en, this message translates to:
  /// **'The stash operation timed out.'**
  String get stashFailureTimeout;

  /// Missing Git stash failure.
  ///
  /// In en, this message translates to:
  /// **'Git could not be started.'**
  String get stashFailureMissingGit;

  /// Merge branch command.
  ///
  /// In en, this message translates to:
  /// **'Merge branch…'**
  String get commandMergeBranch;

  /// Choose merge or rebase for a dragged branch.
  ///
  /// In en, this message translates to:
  /// **'Integrate branch…'**
  String get commandIntegrateBranch;

  /// Interactive rebase command.
  ///
  /// In en, this message translates to:
  /// **'Rebase onto branch…'**
  String get commandRebaseBranch;

  /// Cherry-pick selected commits command.
  ///
  /// In en, this message translates to:
  /// **'Cherry-pick selected commits…'**
  String get commandCherryPickSelected;

  /// Revert selected commits command.
  ///
  /// In en, this message translates to:
  /// **'Revert selected commits…'**
  String get commandRevertSelected;

  /// Merge source branch field.
  ///
  /// In en, this message translates to:
  /// **'Source branch'**
  String get historyMutationSourceBranch;

  /// Merge fast-forward policy field.
  ///
  /// In en, this message translates to:
  /// **'Merge mode'**
  String get historyMutationMergeMode;

  /// Normal merge policy.
  ///
  /// In en, this message translates to:
  /// **'Fast-forward if possible'**
  String get historyMutationFastForwardPossible;

  /// Fast-forward-only merge policy.
  ///
  /// In en, this message translates to:
  /// **'Fast-forward only'**
  String get historyMutationFastForwardOnly;

  /// No-fast-forward merge policy.
  ///
  /// In en, this message translates to:
  /// **'Always create a merge commit'**
  String get historyMutationNoFastForward;

  /// Missing commit selection guidance.
  ///
  /// In en, this message translates to:
  /// **'Select one or more commits in History first.'**
  String get historyMutationSelectCommits;

  /// Published history confirmation.
  ///
  /// In en, this message translates to:
  /// **'I understand this adds commits to a published branch.'**
  String get historyMutationPublishedWarning;

  /// The operation would not change the history.
  ///
  /// In en, this message translates to:
  /// **'The current branch already contains these changes. Nothing needs to change.'**
  String get historyMutationAlreadyContained;

  /// History mutation cancellation state.
  ///
  /// In en, this message translates to:
  /// **'Canceling…'**
  String get historyMutationCanceling;

  /// Command disabled reason while an operation blocks the repository.
  ///
  /// In en, this message translates to:
  /// **'Wait for the running operation in this repository to finish'**
  String get commandRepositoryBusy;

  /// Shown over the repository while a merge runs.
  ///
  /// In en, this message translates to:
  /// **'Merging {source} into {branch}…'**
  String historyMutationBusyMerge(String source, String branch);

  /// Shown over the repository while a cherry-pick runs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Cherry-picking 1 commit onto {branch}…} other{Cherry-picking {count} commits onto {branch}…}}'**
  String historyMutationBusyCherryPick(int count, String branch);

  /// Shown over the repository while a revert runs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Reverting 1 commit on {branch}…} other{Reverting {count} commits on {branch}…}}'**
  String historyMutationBusyRevert(int count, String branch);

  /// Shown over the repository while conflicts are predicted.
  ///
  /// In en, this message translates to:
  /// **'Checking for likely conflicts…'**
  String get conflictPredictionBusy;

  /// Shown over the repository while a rebase runs.
  ///
  /// In en, this message translates to:
  /// **'Rebasing {branch} onto {target}…'**
  String rebaseBusy(String branch, String target);

  /// Shown over the repository while a restack runs.
  ///
  /// In en, this message translates to:
  /// **'Restacking the branches on {root}…'**
  String restackBusy(String root);

  /// Shown over the repository while changes are stashed.
  ///
  /// In en, this message translates to:
  /// **'Stashing changes…'**
  String get stashBusyPush;

  /// Shown over the repository while a stash is applied.
  ///
  /// In en, this message translates to:
  /// **'Applying stash…'**
  String get stashBusyApply;

  /// Shown over the repository while a stash is popped.
  ///
  /// In en, this message translates to:
  /// **'Applying and removing stash…'**
  String get stashBusyPop;

  /// Shown over the repository while a stash is dropped.
  ///
  /// In en, this message translates to:
  /// **'Dropping stash…'**
  String get stashBusyDrop;

  /// Shown over the repository while a stash is renamed.
  ///
  /// In en, this message translates to:
  /// **'Renaming stash…'**
  String get stashBusyRename;

  /// Shown over the repository while changes are stashed for a checkout.
  ///
  /// In en, this message translates to:
  /// **'Stashing changes and checking out…'**
  String get stashBusyAutoStashCheckout;

  /// Merge or rebase intent dialog title.
  ///
  /// In en, this message translates to:
  /// **'Integrate branch'**
  String get branchIntegrationTitle;

  /// Branch integration dialog: what the choice is about.
  ///
  /// In en, this message translates to:
  /// **'Choose how to bring the changes from {branch} into your current branch.'**
  String branchIntegrationHint(String branch);

  /// Branch integration dialog: button that continues with a rebase.
  ///
  /// In en, this message translates to:
  /// **'Rebase…'**
  String get branchIntegrationRebaseAction;

  /// Branch integration dialog: primary button that continues with a merge.
  ///
  /// In en, this message translates to:
  /// **'Merge…'**
  String get branchIntegrationMergeAction;

  /// Branch integration dialog: what rebasing does when the branch is chosen next.
  ///
  /// In en, this message translates to:
  /// **'Replays your commits on top of the other branch. They get new IDs, so avoid this for commits others already have.'**
  String get branchIntegrationRebaseDetailAny;

  /// Branch integration dialog: what rebasing onto the branch does.
  ///
  /// In en, this message translates to:
  /// **'Replays your commits on top of {branch}. They get new IDs, so avoid this for commits others already have.'**
  String branchIntegrationRebaseDetail(String branch);

  /// Branch integration dialog: label of the rebase explanation.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get branchIntegrationRebase;

  /// Branch integration dialog: what merging does.
  ///
  /// In en, this message translates to:
  /// **'Adds a merge commit that joins both histories. Your commits stay as they are.'**
  String get branchIntegrationMergeDetail;

  /// Branch integration dialog: label of the merge explanation.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get branchIntegrationMerge;

  /// Branch integration dialog when the other branch is chosen next.
  ///
  /// In en, this message translates to:
  /// **'Choose how to bring another branch\'s changes into your current branch.'**
  String get branchIntegrationHintAny;

  /// Interactive rebase editor title.
  ///
  /// In en, this message translates to:
  /// **'Interactive rebase'**
  String get rebaseEditorTitle;

  /// Interactive rebase editor: how many commits the plan has and their order.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 commit, oldest first} other{{count} commits, oldest first}}'**
  String rebaseInstructionCount(int count);

  /// Published commit badge.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get rebasePublishedBadge;

  /// Reword message field.
  ///
  /// In en, this message translates to:
  /// **'Replacement commit message'**
  String get rebaseReplacementMessage;

  /// Rebase row move-up action.
  ///
  /// In en, this message translates to:
  /// **'Move instruction up'**
  String get rebaseMoveUp;

  /// Rebase row move-down action.
  ///
  /// In en, this message translates to:
  /// **'Move instruction down'**
  String get rebaseMoveDown;

  /// Interactive rebase acknowledgement for rewriting published commits.
  ///
  /// In en, this message translates to:
  /// **'I understand that this rewrites published history.'**
  String get rebasePublishedWarning;

  /// Start interactive rebase action.
  ///
  /// In en, this message translates to:
  /// **'Start rebase'**
  String get rebaseStart;

  /// Opens the interactive rebase editor for the chosen target branch.
  ///
  /// In en, this message translates to:
  /// **'Edit rebase plan'**
  String get rebaseEditPlan;

  /// Rebase review title.
  ///
  /// In en, this message translates to:
  /// **'Review rebase'**
  String get rebasePreviewTitle;

  /// Localized rebaseActionPick message.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get rebaseActionPick;

  /// Localized rebaseActionReword message.
  ///
  /// In en, this message translates to:
  /// **'Reword'**
  String get rebaseActionReword;

  /// Localized rebaseActionEdit message.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get rebaseActionEdit;

  /// Localized rebaseActionSquash message.
  ///
  /// In en, this message translates to:
  /// **'Squash'**
  String get rebaseActionSquash;

  /// Localized rebaseActionFixup message.
  ///
  /// In en, this message translates to:
  /// **'Fixup'**
  String get rebaseActionFixup;

  /// Localized rebaseActionDrop message.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get rebaseActionDrop;

  /// Localized rebaseCompleted message.
  ///
  /// In en, this message translates to:
  /// **'Rebase completed.'**
  String get rebaseCompleted;

  /// No description provided for @rebaseConflict.
  ///
  /// In en, this message translates to:
  /// **'Rebase stopped with {count} conflict path(s).'**
  String rebaseConflict(int count);

  /// Localized rebaseEditStop message.
  ///
  /// In en, this message translates to:
  /// **'Rebase stopped at an Edit instruction.'**
  String get rebaseEditStop;

  /// Localized rebaseInterrupted message.
  ///
  /// In en, this message translates to:
  /// **'The rebase is paused.'**
  String get rebaseInterrupted;

  /// Localized rebaseStale message.
  ///
  /// In en, this message translates to:
  /// **'The current commit or the rebase target changed. Review a fresh plan.'**
  String get rebaseStale;

  /// Localized rebaseFailed message.
  ///
  /// In en, this message translates to:
  /// **'The interactive rebase did not complete.'**
  String get rebaseFailed;

  /// History mutation completion.
  ///
  /// In en, this message translates to:
  /// **'History operation completed.'**
  String get historyMutationCompleted;

  /// No description provided for @historyMutationConflict.
  ///
  /// In en, this message translates to:
  /// **'The operation stopped with {count} conflict path(s). Continue in the conflict workflow.'**
  String historyMutationConflict(int count);

  /// Non-conflict sequencer interruption.
  ///
  /// In en, this message translates to:
  /// **'The operation is paused. Continue, skip or abort it.'**
  String get historyMutationInterrupted;

  /// Stale history mutation.
  ///
  /// In en, this message translates to:
  /// **'Repository state changed after the preview. Review the operation again.'**
  String get historyMutationStale;

  /// History mutation reconciliation warning.
  ///
  /// In en, this message translates to:
  /// **'The operation completed, but the view could not be refreshed.'**
  String get historyMutationReconciledWarning;

  /// Generic history mutation failure.
  ///
  /// In en, this message translates to:
  /// **'The history operation failed.'**
  String get historyMutationFailed;

  /// Invalid history mutation failure.
  ///
  /// In en, this message translates to:
  /// **'The history operation request is invalid.'**
  String get historyMutationFailureInvalid;

  /// Dirty-tree history mutation failure.
  ///
  /// In en, this message translates to:
  /// **'Commit or stash working-tree changes before changing history.'**
  String get historyMutationFailureDirty;

  /// Detached-head history mutation failure.
  ///
  /// In en, this message translates to:
  /// **'Check out a branch before changing history.'**
  String get historyMutationFailureDetached;

  /// Active sequencer history mutation failure.
  ///
  /// In en, this message translates to:
  /// **'Continue or abort the current Git operation first.'**
  String get historyMutationFailureActive;

  /// Missing publication acknowledgement.
  ///
  /// In en, this message translates to:
  /// **'Confirm the published-history warning before continuing.'**
  String get historyMutationFailurePublished;

  /// Canceled history mutation failure.
  ///
  /// In en, this message translates to:
  /// **'The history operation was canceled.'**
  String get historyMutationFailureCanceled;

  /// Localized conflictResolverTitle message.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflicts'**
  String get conflictResolverTitle;

  /// Localized conflictOperationMerge message.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get conflictOperationMerge;

  /// Localized conflictOperationRebase message.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get conflictOperationRebase;

  /// Localized conflictOperationCherryPick message.
  ///
  /// In en, this message translates to:
  /// **'Cherry-pick'**
  String get conflictOperationCherryPick;

  /// Localized conflictOperationRevert message.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get conflictOperationRevert;

  /// Localized conflictOperationSnapshot message.
  ///
  /// In en, this message translates to:
  /// **'Snapshot restore'**
  String get conflictOperationSnapshot;

  /// Localized conflictOperationStash message.
  ///
  /// In en, this message translates to:
  /// **'Stashed changes'**
  String get conflictOperationStash;

  /// Label for conflicts detected without an active Git operation.
  ///
  /// In en, this message translates to:
  /// **'Unmerged files'**
  String get conflictOperationStandalone;

  /// No description provided for @conflictRegionNumber.
  ///
  /// In en, this message translates to:
  /// **'Conflict {number}'**
  String conflictRegionNumber(int number);

  /// No description provided for @conflictFileProgress.
  ///
  /// In en, this message translates to:
  /// **'File {current} of {total}'**
  String conflictFileProgress(int current, int total);

  /// No description provided for @conflictStepProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String conflictStepProgress(int current, int total);

  /// No description provided for @conflictCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: {label}'**
  String conflictCurrent(String label);

  /// No description provided for @conflictIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming: {label}'**
  String conflictIncoming(String label);

  /// Localized conflictAncestor message.
  ///
  /// In en, this message translates to:
  /// **'Common ancestor'**
  String get conflictAncestor;

  /// Localized conflictResult message.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get conflictResult;

  /// Localized conflictTakeCurrent message.
  ///
  /// In en, this message translates to:
  /// **'Take current'**
  String get conflictTakeCurrent;

  /// Localized conflictTakeIncoming message.
  ///
  /// In en, this message translates to:
  /// **'Take incoming'**
  String get conflictTakeIncoming;

  /// Remove an accepted conflict side from the draft.
  ///
  /// In en, this message translates to:
  /// **'Remove current'**
  String get conflictRemoveCurrent;

  /// Remove an accepted conflict side from the draft.
  ///
  /// In en, this message translates to:
  /// **'Remove incoming'**
  String get conflictRemoveIncoming;

  /// Remove an accepted conflict side from the draft.
  ///
  /// In en, this message translates to:
  /// **'Remove both'**
  String get conflictRemoveBoth;

  /// Localized conflictTakeBoth message.
  ///
  /// In en, this message translates to:
  /// **'Take both'**
  String get conflictTakeBoth;

  /// Localized conflictUseCurrentFile message.
  ///
  /// In en, this message translates to:
  /// **'Use current file'**
  String get conflictUseCurrentFile;

  /// Localized conflictUseIncomingFile message.
  ///
  /// In en, this message translates to:
  /// **'Use incoming file'**
  String get conflictUseIncomingFile;

  /// Localized conflictKeepDeletion message.
  ///
  /// In en, this message translates to:
  /// **'Keep deletion'**
  String get conflictKeepDeletion;

  /// Localized conflictUndoResolution message.
  ///
  /// In en, this message translates to:
  /// **'Undo resolution'**
  String get conflictUndoResolution;

  /// Localized conflictPreviousFile message.
  ///
  /// In en, this message translates to:
  /// **'Previous file'**
  String get conflictPreviousFile;

  /// Localized conflictNextFile message.
  ///
  /// In en, this message translates to:
  /// **'Next file'**
  String get conflictNextFile;

  /// Localized conflictContinue message.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get conflictContinue;

  /// Localized conflictSkip message.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get conflictSkip;

  /// Localized conflictAbort message.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get conflictAbort;

  /// Localized conflictAbortTitle message.
  ///
  /// In en, this message translates to:
  /// **'Abort Git operation?'**
  String get conflictAbortTitle;

  /// Abort confirmation in the conflict resolver.
  ///
  /// In en, this message translates to:
  /// **'Git puts everything back the way it was before this started. Unsaved edits in the conflict editor are lost.'**
  String get conflictAbortMessage;

  /// Localized conflictSkipTitle message.
  ///
  /// In en, this message translates to:
  /// **'Skip this step?'**
  String get conflictSkipTitle;

  /// Skip confirmation in the conflict resolver.
  ///
  /// In en, this message translates to:
  /// **'Git leaves out the commit it is applying now and moves on to the next one.'**
  String get conflictSkipMessage;

  /// Localized conflictLoading message.
  ///
  /// In en, this message translates to:
  /// **'Loading conflict state…'**
  String get conflictLoading;

  /// Localized conflictLoadFailed message.
  ///
  /// In en, this message translates to:
  /// **'Conflict state could not be loaded. Refresh and inspect the repository before continuing.'**
  String get conflictLoadFailed;

  /// Localized conflictSaveFailed message.
  ///
  /// In en, this message translates to:
  /// **'The result changed outside GitLama or could not be saved. The conflict state was reloaded.'**
  String get conflictSaveFailed;

  /// Localized conflictContinueFailed message.
  ///
  /// In en, this message translates to:
  /// **'Git could not complete this step.'**
  String get conflictContinueFailed;

  /// Localized conflictCompleted message.
  ///
  /// In en, this message translates to:
  /// **'Git operation completed.'**
  String get conflictCompleted;

  /// Localized conflictAborted message.
  ///
  /// In en, this message translates to:
  /// **'Git operation aborted.'**
  String get conflictAborted;

  /// Localized conflictStoppedAgain message.
  ///
  /// In en, this message translates to:
  /// **'Git stopped again, at the next conflict or step.'**
  String get conflictStoppedAgain;

  /// Localized conflictAllResolved message.
  ///
  /// In en, this message translates to:
  /// **'All conflict paths are resolved. Continue when ready.'**
  String get conflictAllResolved;

  /// Completion message when unmerged files have no active sequencer operation.
  ///
  /// In en, this message translates to:
  /// **'All unmerged files are resolved. Review the changes before committing.'**
  String get conflictStandaloneResolved;

  /// Localized conflictBinaryFile message.
  ///
  /// In en, this message translates to:
  /// **'This is a binary file. Choose a complete side or open an external merge tool.'**
  String get conflictBinaryFile;

  /// Localized conflictHugeFile message.
  ///
  /// In en, this message translates to:
  /// **'This file is too large for the built-in text editor. Choose a complete side or open an external merge tool.'**
  String get conflictHugeFile;

  /// Localized conflictExternalTool message.
  ///
  /// In en, this message translates to:
  /// **'Open external tool'**
  String get conflictExternalTool;

  /// Localized conflictExternalUnavailable message.
  ///
  /// In en, this message translates to:
  /// **'External merge-tool handoff is not available yet.'**
  String get conflictExternalUnavailable;

  /// Localized conflictEmptySide message.
  ///
  /// In en, this message translates to:
  /// **'Empty file'**
  String get conflictEmptySide;

  /// No description provided for @conflictRegionsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unresolved region} other{{count} unresolved regions}}'**
  String conflictRegionsRemaining(int count);

  /// Conflict resolver control or status.
  ///
  /// In en, this message translates to:
  /// **'Previous conflict'**
  String get conflictPreviousRegion;

  /// Conflict resolver control or status.
  ///
  /// In en, this message translates to:
  /// **'Next conflict'**
  String get conflictNextRegion;

  /// Conflict resolver control or status.
  ///
  /// In en, this message translates to:
  /// **'Resolve file'**
  String get conflictResolveFile;

  /// Conflict resolver control or status.
  ///
  /// In en, this message translates to:
  /// **'Review or edit the result, then resolve this file.'**
  String get conflictReviewResult;

  /// Localized conflictSaving message.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get conflictSaving;

  /// Localized conflictShowAncestor message.
  ///
  /// In en, this message translates to:
  /// **'Show ancestor'**
  String get conflictShowAncestor;

  /// Localized conflictHideAncestor message.
  ///
  /// In en, this message translates to:
  /// **'Hide ancestor'**
  String get conflictHideAncestor;

  /// Interactive rebase option: autosquash.
  ///
  /// In en, this message translates to:
  /// **'Combine fixup commits automatically'**
  String get rebaseAutosquash;

  /// Explains the autosquash option.
  ///
  /// In en, this message translates to:
  /// **'Commits whose message starts with fixup! or squash! move behind the commit they fix and are combined with it.'**
  String get rebaseAutosquashHint;

  /// Localized rebaseDragToSquash message.
  ///
  /// In en, this message translates to:
  /// **'Drag onto another commit to squash'**
  String get rebaseDragToSquash;

  /// Localized rebaseDragToReorder message.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get rebaseDragToReorder;

  /// Rebase review: how many commits autosquash combined.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 fixup commit was combined automatically.} other{{count} fixup commits were combined automatically.}}'**
  String rebaseAutosquashApplied(int count);

  /// Localized fixupSuggestionAction message.
  ///
  /// In en, this message translates to:
  /// **'Fixup / squash'**
  String get fixupSuggestionAction;

  /// Localized fixupSuggestionFixup message.
  ///
  /// In en, this message translates to:
  /// **'Create fixup commit'**
  String get fixupSuggestionFixup;

  /// Localized fixupSuggestionSquash message.
  ///
  /// In en, this message translates to:
  /// **'Create squash commit'**
  String get fixupSuggestionSquash;

  /// Fixup target dialog when several commits match.
  ///
  /// In en, this message translates to:
  /// **'Several commits changed these files. Choose the one your changes belong to.'**
  String get fixupSuggestionAmbiguous;

  /// Fixup target dialog when no commit could be inferred.
  ///
  /// In en, this message translates to:
  /// **'GitLama couldn\'t tell which commit these changes fix. Choose one of the commits that changed these files.'**
  String get fixupSuggestionPickHint;

  /// Title of the dialog that picks the commit a fixup or squash commit targets.
  ///
  /// In en, this message translates to:
  /// **'Which commit does this fix?'**
  String get fixupSuggestionPickTitle;

  /// Notification when no fixup target could be inferred.
  ///
  /// In en, this message translates to:
  /// **'GitLama couldn\'t tell which commit these changes fix.'**
  String get fixupSuggestionUnavailable;

  /// Localized fixupSuggestionFailed message.
  ///
  /// In en, this message translates to:
  /// **'The base-commit evidence could not be loaded.'**
  String get fixupSuggestionFailed;

  /// Localized commandRestackBranches message.
  ///
  /// In en, this message translates to:
  /// **'Restack dependent branches'**
  String get commandRestackBranches;

  /// Localized restackChooseRoot message.
  ///
  /// In en, this message translates to:
  /// **'Choose the stack root'**
  String get restackChooseRoot;

  /// Restack review title with the number of branches that move.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restack 1 branch} other{Restack {count} branches}}'**
  String restackPreviewTitle(int count);

  /// Restack review: the branch graph could not be read completely.
  ///
  /// In en, this message translates to:
  /// **'GitLama couldn\'t map the whole stack. Only the branches listed here are restacked.'**
  String get restackIncompleteWarning;

  /// Restack acknowledgement for rewriting published branches.
  ///
  /// In en, this message translates to:
  /// **'I understand that this rewrites published branches, so others may need to update their copies.'**
  String get restackPublishedWarning;

  /// Localized restackNothingToDo message.
  ///
  /// In en, this message translates to:
  /// **'All dependent branches are already based on their current parents.'**
  String get restackNothingToDo;

  /// No description provided for @restackCompleted.
  ///
  /// In en, this message translates to:
  /// **'Restacked {count} branches.'**
  String restackCompleted(int count);

  /// No description provided for @restackConflict.
  ///
  /// In en, this message translates to:
  /// **'Restack stopped at a conflict after {completed} of {total} branches. Resolve it in Changes, then re-plan to continue.'**
  String restackConflict(int completed, int total);

  /// No description provided for @restackPartial.
  ///
  /// In en, this message translates to:
  /// **'Restack stopped after {completed} of {total} branches. Re-plan to continue without repeating completed rewrites.'**
  String restackPartial(int completed, int total);

  /// Localized restackStale message.
  ///
  /// In en, this message translates to:
  /// **'The branch tips changed. Review a fresh restack plan.'**
  String get restackStale;

  /// Localized restackCanceled message.
  ///
  /// In en, this message translates to:
  /// **'Restack canceled before the next branch.'**
  String get restackCanceled;

  /// Localized restackFailed message.
  ///
  /// In en, this message translates to:
  /// **'The branch restack could not be completed.'**
  String get restackFailed;

  /// Localized namedSnapshotsTitle message.
  ///
  /// In en, this message translates to:
  /// **'Snapshots'**
  String get namedSnapshotsTitle;

  /// Localized namedSnapshotsEmpty message.
  ///
  /// In en, this message translates to:
  /// **'No snapshots yet'**
  String get namedSnapshotsEmpty;

  /// Localized namedSnapshotName message.
  ///
  /// In en, this message translates to:
  /// **'Snapshot name'**
  String get namedSnapshotName;

  /// Localized namedSnapshotCreate message.
  ///
  /// In en, this message translates to:
  /// **'Create snapshot'**
  String get namedSnapshotCreate;

  /// Localized namedSnapshotInspect message.
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get namedSnapshotInspect;

  /// Localized namedSnapshotRestore message.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get namedSnapshotRestore;

  /// Localized namedSnapshotBranch message.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get namedSnapshotBranch;

  /// Localized namedSnapshotBranchTitle message.
  ///
  /// In en, this message translates to:
  /// **'Create branch from snapshot'**
  String get namedSnapshotBranchTitle;

  /// Localized namedSnapshotBranchCreated message.
  ///
  /// In en, this message translates to:
  /// **'Branch created from the snapshot.'**
  String get namedSnapshotBranchCreated;

  /// Localized namedSnapshotDeleteTitle message.
  ///
  /// In en, this message translates to:
  /// **'Delete snapshot?'**
  String get namedSnapshotDeleteTitle;

  /// No description provided for @namedSnapshotDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? The changes saved in it are removed.'**
  String namedSnapshotDeleteMessage(String name);

  /// Snapshot restore title with the snapshot name.
  ///
  /// In en, this message translates to:
  /// **'Restore “{name}”?'**
  String namedSnapshotRestoreTitle(String name);

  /// Snapshot restore: the file list is shortened.
  ///
  /// In en, this message translates to:
  /// **'More files change than are listed here.'**
  String get namedSnapshotPathsTruncated;

  /// Snapshot restore acknowledgement.
  ///
  /// In en, this message translates to:
  /// **'I understand that my current changes will be replaced.'**
  String get namedSnapshotAcknowledgeReplacement;

  /// Localized namedSnapshotNothingToCapture message.
  ///
  /// In en, this message translates to:
  /// **'There are no changes to capture.'**
  String get namedSnapshotNothingToCapture;

  /// Localized namedSnapshotMissing message.
  ///
  /// In en, this message translates to:
  /// **'The snapshot\'s saved data is missing.'**
  String get namedSnapshotMissing;

  /// Localized namedSnapshotCorrupt message.
  ///
  /// In en, this message translates to:
  /// **'The snapshot metadata is corrupt.'**
  String get namedSnapshotCorrupt;

  /// Localized namedSnapshotDirtyConflict message.
  ///
  /// In en, this message translates to:
  /// **'Resolve the current conflicts before creating a snapshot.'**
  String get namedSnapshotDirtyConflict;

  /// Localized namedSnapshotActiveOperation message.
  ///
  /// In en, this message translates to:
  /// **'Finish the active Git operation before creating a snapshot.'**
  String get namedSnapshotActiveOperation;

  /// Localized namedSnapshotStale message.
  ///
  /// In en, this message translates to:
  /// **'The repository changed. Review a fresh restore preview.'**
  String get namedSnapshotStale;

  /// Localized namedSnapshotConflict message.
  ///
  /// In en, this message translates to:
  /// **'Snapshot restore stopped at conflicts. Resolve them in Changes.'**
  String get namedSnapshotConflict;

  /// Localized namedSnapshotCanceled message.
  ///
  /// In en, this message translates to:
  /// **'Snapshot operation canceled.'**
  String get namedSnapshotCanceled;

  /// Localized namedSnapshotTooLarge message.
  ///
  /// In en, this message translates to:
  /// **'Snapshot metadata exceeds its safety bound.'**
  String get namedSnapshotTooLarge;

  /// Localized namedSnapshotFailed message.
  ///
  /// In en, this message translates to:
  /// **'The snapshot operation failed.'**
  String get namedSnapshotFailed;

  /// Localized detachedHead message.
  ///
  /// In en, this message translates to:
  /// **'Detached HEAD'**
  String get detachedHead;

  /// No description provided for @compassDetachedAt.
  ///
  /// In en, this message translates to:
  /// **'Detached at {hash}'**
  String compassDetachedAt(String hash);

  /// Localized delete message.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Localized loadMore message.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Repository extensions'**
  String get repositoryExtensionsTitle;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Worktrees'**
  String get extensionWorktrees;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Locked worktree'**
  String get extensionWorktreeLocked;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Current worktree'**
  String get extensionWorktreeCurrent;

  /// Label of the folder field in the Create worktree dialog.
  ///
  /// In en, this message translates to:
  /// **'Folder for the worktree'**
  String get extensionWorktreePath;

  /// Opens the native folder picker for the new worktree destination.
  ///
  /// In en, this message translates to:
  /// **'Choose folder…'**
  String get extensionWorktreeChooseFolder;

  /// Safe failure message when the worktree folder picker is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not open the folder picker. Try again or enter a path.'**
  String get extensionWorktreeChooseFolderFailure;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Branch, tag, or commit'**
  String get extensionWorktreeReference;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Create worktree'**
  String get extensionWorktreeCreate;

  /// Confirmation dialog title before removing a linked worktree.
  ///
  /// In en, this message translates to:
  /// **'Delete worktree?'**
  String get extensionWorktreeDeleteTitle;

  /// No description provided for @extensionWorktreeDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete the linked worktree at {path}? Unsaved changes or locked worktrees are refused.'**
  String extensionWorktreeDeleteBody(String path);

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Submodules'**
  String get extensionSubmodules;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get extensionNone;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Initialize'**
  String get extensionInitialize;

  /// Repository extension open action.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get extensionOpen;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get extensionUpdate;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'At recorded commit'**
  String get extensionSubmoduleRecorded;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Checked out at a different commit'**
  String get extensionSubmoduleDifferent;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Not initialized'**
  String get extensionSubmoduleUninitialized;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Conflicted'**
  String get extensionSubmoduleConflicted;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Git LFS'**
  String get extensionLfs;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Pull objects'**
  String get extensionLfsPull;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Git LFS is not installed or unavailable.'**
  String get extensionLfsUnavailable;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Tracking pattern'**
  String get extensionLfsPattern;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get extensionLfsTrack;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Untrack'**
  String get extensionLfsUntrack;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Inspect pointer'**
  String get extensionInspectPointer;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'LFS pointer'**
  String get extensionLfsPointerTitle;

  /// LFS object is a pointer.
  ///
  /// In en, this message translates to:
  /// **'Pointer'**
  String get extensionLfsStatePointer;

  /// LFS object has local content.
  ///
  /// In en, this message translates to:
  /// **'Materialized'**
  String get extensionLfsStateMaterialized;

  /// LFS object content is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get extensionLfsStateMissing;

  /// LFS pointer dialog description when the file is not a pointer.
  ///
  /// In en, this message translates to:
  /// **'This file holds its own content, not an LFS pointer.'**
  String get extensionLfsNotPointer;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The extension request is invalid.'**
  String get extensionFailureInvalid;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The required tool or capability is unavailable.'**
  String get extensionFailureUnavailable;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Commit or stash changes in that worktree first.'**
  String get extensionFailureDirty;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'Unlock that worktree before removing it.'**
  String get extensionFailureLocked;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The current worktree cannot be removed.'**
  String get extensionFailureCurrent;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The repository extension state changed. Refresh and try again.'**
  String get extensionFailureStale;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The extension operation was canceled.'**
  String get extensionFailureCanceled;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The extension result exceeds its safety bound.'**
  String get extensionFailureTooLarge;

  /// Repository extension workflow message.
  ///
  /// In en, this message translates to:
  /// **'The repository extension operation failed.'**
  String get extensionFailureGit;

  /// Description of the Create worktree dialog.
  ///
  /// In en, this message translates to:
  /// **'Check out a branch or commit in its own folder, so you can work on it next to this one.'**
  String get extensionWorktreeCreateDescription;

  /// Description of the LFS pointer details dialog.
  ///
  /// In en, this message translates to:
  /// **'Git LFS stores this file\'s content on a server. The repository holds this small pointer to it instead.'**
  String get extensionLfsPointerDescription;

  /// LFS pointer details: the file path.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get extensionLfsPointerFile;

  /// LFS pointer details: the SHA-256 object ID of the content.
  ///
  /// In en, this message translates to:
  /// **'SHA-256'**
  String get extensionLfsPointerOid;

  /// LFS pointer details: the size of the content.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get extensionLfsPointerSize;

  /// Heading of the list of resolved conflict files that can be undone.
  ///
  /// In en, this message translates to:
  /// **'Resolved files'**
  String get conflictResolvedFiles;

  /// Puts the conflicts of every resolved file back.
  ///
  /// In en, this message translates to:
  /// **'Undo all'**
  String get conflictUndoAll;

  /// Ticks every conflicted file for resolving together.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get conflictSelectAll;

  /// No description provided for @conflictSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String conflictSelectedCount(int count);

  /// Resolves every ticked conflicted file with the current (ours) side.
  ///
  /// In en, this message translates to:
  /// **'Use current ({count})'**
  String conflictBulkUseCurrent(int count);

  /// Resolves every ticked conflicted file with the incoming (theirs) side.
  ///
  /// In en, this message translates to:
  /// **'Use incoming ({count})'**
  String conflictBulkUseIncoming(int count);

  /// Snapshot details fact: the branch the snapshot was taken on.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get namedSnapshotFactBranch;

  /// Snapshot details: taken while no branch was checked out (detached HEAD).
  ///
  /// In en, this message translates to:
  /// **'No branch'**
  String get namedSnapshotNoBranch;

  /// Snapshot details fact: the commit the snapshot's changes are based on.
  ///
  /// In en, this message translates to:
  /// **'Based on commit'**
  String get namedSnapshotFactBase;

  /// Snapshot fact and count tooltip: number of new (untracked) files saved.
  ///
  /// In en, this message translates to:
  /// **'New files'**
  String get namedSnapshotFactNewFiles;

  /// Snapshot details fact: the snapshot's own commit ID, shortened.
  ///
  /// In en, this message translates to:
  /// **'Snapshot ID'**
  String get namedSnapshotFactId;

  /// Empty snapshot list: what a snapshot is for.
  ///
  /// In en, this message translates to:
  /// **'Save your current changes under a name to come back to them later.'**
  String get namedSnapshotsEmptyHelp;

  /// Confirms the previewed branch restack.
  ///
  /// In en, this message translates to:
  /// **'Restack branches'**
  String get restackRun;

  /// Repository integrations sidebar and command label.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get integrationTitle;

  /// Heading for platform-discovered external tools.
  ///
  /// In en, this message translates to:
  /// **'Found on this computer'**
  String get integrationDiscovered;

  /// Heading for saved external tools and commands.
  ///
  /// In en, this message translates to:
  /// **'Your tools and commands'**
  String get integrationConfigured;

  /// Heading for the external tool configuration form.
  ///
  /// In en, this message translates to:
  /// **'Add a tool or command'**
  String get integrationConfigure;

  /// Label for an external integration capability kind.
  ///
  /// In en, this message translates to:
  /// **'Use as'**
  String get integrationKind;

  /// Label for a non-secret command display name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get integrationName;

  /// Label for an external executable path.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get integrationExecutable;

  /// Tooltip for selecting an executable.
  ///
  /// In en, this message translates to:
  /// **'Choose program'**
  String get integrationChooseExecutable;

  /// Label for structured native command arguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get integrationArguments;

  /// Help for one-argument-per-line templates and supported variables.
  ///
  /// In en, this message translates to:
  /// **'One argument per line, passed exactly as written. To insert details, put repository, working_directory, file, current_branch or selected_commit in braces.'**
  String get integrationArgumentsHelp;

  /// Label for deliberate explicit shell execution.
  ///
  /// In en, this message translates to:
  /// **'Run through the system shell'**
  String get integrationExplicitShell;

  /// Label for requiring command confirmation.
  ///
  /// In en, this message translates to:
  /// **'Ask before each run'**
  String get integrationConfirm;

  /// Label for waiting for an external tool to exit.
  ///
  /// In en, this message translates to:
  /// **'Wait until it finishes'**
  String get integrationWait;

  /// Label for the custom command timeout.
  ///
  /// In en, this message translates to:
  /// **'Time limit (seconds)'**
  String get integrationTimeout;

  /// Action that validates and persists an integration.
  ///
  /// In en, this message translates to:
  /// **'Check and save'**
  String get integrationValidateSave;

  /// Title for exact command preview confirmation.
  ///
  /// In en, this message translates to:
  /// **'Review exact command'**
  String get integrationPreviewTitle;

  /// Action to execute a reviewed external command.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get integrationRun;

  /// Editor integration kind.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get integrationEditor;

  /// Terminal integration kind.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get integrationTerminal;

  /// File manager integration kind.
  ///
  /// In en, this message translates to:
  /// **'File manager'**
  String get integrationFileManager;

  /// Browser integration kind.
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get integrationBrowser;

  /// Diff tool integration kind.
  ///
  /// In en, this message translates to:
  /// **'Diff tool'**
  String get integrationDiffTool;

  /// Merge tool integration kind.
  ///
  /// In en, this message translates to:
  /// **'Merge tool'**
  String get integrationMergeTool;

  /// Custom command integration kind.
  ///
  /// In en, this message translates to:
  /// **'Custom command'**
  String get integrationCustom;

  /// Invalid integration failure.
  ///
  /// In en, this message translates to:
  /// **'The tool definition or argument template is invalid.'**
  String get integrationInvalid;

  /// Unavailable executable failure.
  ///
  /// In en, this message translates to:
  /// **'The selected executable is unavailable.'**
  String get integrationUnavailable;

  /// Missing command variable failure.
  ///
  /// In en, this message translates to:
  /// **'A required command variable is unavailable.'**
  String get integrationMissingVariable;

  /// Stale integration preview failure.
  ///
  /// In en, this message translates to:
  /// **'Repository state changed. Review the command again.'**
  String get integrationStale;

  /// Missing command confirmation failure.
  ///
  /// In en, this message translates to:
  /// **'This command requires explicit confirmation.'**
  String get integrationConfirmationRequired;

  /// Custom command timeout failure.
  ///
  /// In en, this message translates to:
  /// **'The command reached its configured time limit and was stopped.'**
  String get integrationTimedOut;

  /// External command nonzero exit failure.
  ///
  /// In en, this message translates to:
  /// **'The command reported a failure.'**
  String get integrationNonZero;

  /// External process launch failure.
  ///
  /// In en, this message translates to:
  /// **'The command could not be started or observed.'**
  String get integrationLaunchFailed;

  /// External command repository read failure.
  ///
  /// In en, this message translates to:
  /// **'Repository state is unavailable.'**
  String get integrationReadFailed;

  /// Custom commands settings: no editor, terminal or other tool was found on this computer.
  ///
  /// In en, this message translates to:
  /// **'No tools found.'**
  String get integrationDiscoveredEmpty;

  /// Custom commands settings: no tool or command has been added.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t added any yet.'**
  String get integrationConfiguredEmpty;

  /// Help under the name field of a custom tool or command.
  ///
  /// In en, this message translates to:
  /// **'Shown in menus. Don\'t include passwords or tokens.'**
  String get integrationNameHelp;

  /// Explains running a custom command through the system shell.
  ///
  /// In en, this message translates to:
  /// **'Allows pipes and redirection. GitLama always asks before running it.'**
  String get integrationExplicitShellHelp;

  /// Explains waiting for a tool to finish.
  ///
  /// In en, this message translates to:
  /// **'GitLama waits for the program to close before going on. Custom commands always wait.'**
  String get integrationWaitHelp;

  /// Title for repository search, bisect and statistics.
  ///
  /// In en, this message translates to:
  /// **'Repository tools'**
  String get powerToolsTitle;

  /// Diff-content search section title.
  ///
  /// In en, this message translates to:
  /// **'Search changes'**
  String get powerSearchTitle;

  /// Diff-content query field label.
  ///
  /// In en, this message translates to:
  /// **'Changed text'**
  String get powerSearchQuery;

  /// Bounded literal diff search explanation.
  ///
  /// In en, this message translates to:
  /// **'Finds commits that added or removed exactly this text, in up to 10,000 commits.'**
  String get powerSearchBound;

  /// Case sensitivity control for diff search.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get powerSearchCaseSensitive;

  /// Scope control for diff search.
  ///
  /// In en, this message translates to:
  /// **'Search scope'**
  String get powerSearchScope;

  /// Search all references.
  ///
  /// In en, this message translates to:
  /// **'All branches and tags'**
  String get powerSearchAllRefs;

  /// Search only the current branch.
  ///
  /// In en, this message translates to:
  /// **'Current branch'**
  String get powerSearchCurrentBranch;

  /// Start diff-content search action.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get powerSearchAction;

  /// Cancel diff-content search action.
  ///
  /// In en, this message translates to:
  /// **'Cancel search'**
  String get powerSearchCancel;

  /// Commit-limit explanation.
  ///
  /// In en, this message translates to:
  /// **'Results are incomplete because the 10,000-commit scan limit was reached.'**
  String get powerSearchIncompleteCommits;

  /// Result-limit explanation.
  ///
  /// In en, this message translates to:
  /// **'Results are incomplete because the 512-result limit was reached.'**
  String get powerSearchIncompleteResults;

  /// How many commits the change search looked at.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 commit searched} other{{count} commits searched}}'**
  String powerSearchExamined(int count);

  /// Repository statistics section title.
  ///
  /// In en, this message translates to:
  /// **'Repository statistics'**
  String get powerStatisticsTitle;

  /// Start statistics scan action.
  ///
  /// In en, this message translates to:
  /// **'Calculate statistics'**
  String get powerStatisticsLoad;

  /// Statistics safety-bound explanation.
  ///
  /// In en, this message translates to:
  /// **'Some counts stopped at a limit and may be too low.'**
  String get powerStatisticsIncomplete;

  /// Visual bisect section title.
  ///
  /// In en, this message translates to:
  /// **'Find a breaking commit'**
  String get powerBisectTitle;

  /// Known-good commit field label.
  ///
  /// In en, this message translates to:
  /// **'Commit that works'**
  String get powerBisectGood;

  /// Known-bad commit field label.
  ///
  /// In en, this message translates to:
  /// **'Commit with the problem'**
  String get powerBisectBad;

  /// Start visual bisect action.
  ///
  /// In en, this message translates to:
  /// **'Start search'**
  String get powerBisectStart;

  /// Mark current bisect commit good.
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get powerBisectMarkGood;

  /// Mark current bisect commit bad.
  ///
  /// In en, this message translates to:
  /// **'Has the problem'**
  String get powerBisectMarkBad;

  /// Skip current bisect commit.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get powerBisectSkip;

  /// Reset an active bisect.
  ///
  /// In en, this message translates to:
  /// **'End search'**
  String get powerBisectReset;

  /// Progress of the search for a breaking commit (git bisect).
  ///
  /// In en, this message translates to:
  /// **'{tested} tested · about {remaining} left'**
  String powerBisectProgress(int tested, int remaining);

  /// Generic repository power-tool failure.
  ///
  /// In en, this message translates to:
  /// **'The repository tool could not complete.'**
  String get powerFailed;

  /// How many commits the change search found.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No matching commits} =1{1 commit found} other{{count} commits found}}'**
  String powerSearchFound(int count);

  /// Repository statistics fact: number of commits.
  ///
  /// In en, this message translates to:
  /// **'Commits'**
  String get powerStatisticsCommits;

  /// Repository statistics fact: number of local branches.
  ///
  /// In en, this message translates to:
  /// **'Local branches'**
  String get powerStatisticsBranches;

  /// Repository statistics fact: number of tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get powerStatisticsTags;

  /// Repository statistics fact: number of distinct files changed by any commit in history.
  ///
  /// In en, this message translates to:
  /// **'Files changed'**
  String get powerStatisticsChangedFiles;

  /// Explains the search for a breaking commit (git bisect) before it starts.
  ///
  /// In en, this message translates to:
  /// **'Name a commit that works and one that has the problem. GitLama checks out commits in between for you to test, until it finds the first one with the problem.'**
  String get powerBisectHelp;

  /// Fact label: the commit checked out for testing during the search for a breaking commit.
  ///
  /// In en, this message translates to:
  /// **'Commit to test'**
  String get powerBisectTesting;

  /// Fact label: progress of the search for a breaking commit.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get powerBisectProgressLabel;

  /// Question above the answers while testing a commit in the search for a breaking commit.
  ///
  /// In en, this message translates to:
  /// **'Does this commit have the problem?'**
  String get powerBisectQuestion;

  /// Confirms marking the current bisect commit as good.
  ///
  /// In en, this message translates to:
  /// **'Mark as working'**
  String get bisectConfirmGood;

  /// Confirms marking the current bisect commit as bad.
  ///
  /// In en, this message translates to:
  /// **'Mark as broken'**
  String get bisectConfirmBad;

  /// Confirmation title before git bisect start.
  ///
  /// In en, this message translates to:
  /// **'Start the search for the breaking commit?'**
  String get bisectStartTitle;

  /// Confirmation title before git bisect good.
  ///
  /// In en, this message translates to:
  /// **'Mark this commit as working?'**
  String get bisectGoodTitle;

  /// Confirmation title before git bisect bad.
  ///
  /// In en, this message translates to:
  /// **'Mark this commit as broken?'**
  String get bisectBadTitle;

  /// Confirmation title before git bisect skip.
  ///
  /// In en, this message translates to:
  /// **'Skip this commit?'**
  String get bisectSkipTitle;

  /// Confirmation title before git bisect reset.
  ///
  /// In en, this message translates to:
  /// **'End the search?'**
  String get bisectResetTitle;

  /// Hosting connection settings section title.
  ///
  /// In en, this message translates to:
  /// **'Hosting connections'**
  String get hostingAccounts;

  /// Action to add a hosting connection.
  ///
  /// In en, this message translates to:
  /// **'Add connection'**
  String get hostingAddConnection;

  /// Empty hosting connection state.
  ///
  /// In en, this message translates to:
  /// **'No hosting connections configured.'**
  String get hostingNoConnections;

  /// Hosting provider preset field label.
  ///
  /// In en, this message translates to:
  /// **'Provider preset'**
  String get hostingPreset;

  /// Stable hosting connection identity field label.
  ///
  /// In en, this message translates to:
  /// **'Connection name'**
  String get hostingConnectionId;

  /// Guidance when a repository cannot be linked before an account exists.
  ///
  /// In en, this message translates to:
  /// **'Add a hosting account before linking this repository.'**
  String get hostingConnectBeforeBinding;

  /// Hosting web base URL field label.
  ///
  /// In en, this message translates to:
  /// **'Web base URL'**
  String get hostingWebUrl;

  /// Hosting API base URL field label.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get hostingApiUrl;

  /// Public OAuth client identifier field label.
  ///
  /// In en, this message translates to:
  /// **'OAuth client ID'**
  String get hostingOAuthClientId;

  /// Open setup instructions for the selected hosting provider.
  ///
  /// In en, this message translates to:
  /// **'How to connect this provider'**
  String get hostingGuideAction;

  /// No description provided for @hostingGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect {provider}'**
  String hostingGuideTitle(String provider);

  /// Setup guide caption for CLI sign-in.
  ///
  /// In en, this message translates to:
  /// **'GitLama uses the CLI\'s current sign-in, so no OAuth application is needed.'**
  String get hostingGuideCliNote;

  /// Setup guide caption for GitHub Enterprise Server.
  ///
  /// In en, this message translates to:
  /// **'If GitHub CLI is installed, you can use its sign-in instead.'**
  String get hostingGuideEnterpriseNote;

  /// Setup guide caption for Forgejo.
  ///
  /// In en, this message translates to:
  /// **'Your server administrator may restrict app registration.'**
  String get hostingGuideForgejoNote;

  /// Setup guide caption for OAuth sign-in.
  ///
  /// In en, this message translates to:
  /// **'No client secret is needed.'**
  String get hostingGuideNoSecret;

  /// Setup guide last step for browser sign-in.
  ///
  /// In en, this message translates to:
  /// **'Select {action}. GitLama opens your browser to finish signing in.'**
  String hostingStepAuthorizeBrowser(String action);

  /// Setup guide last step for GitHub device sign-in.
  ///
  /// In en, this message translates to:
  /// **'Select {action}. GitLama opens GitHub and shows a code to enter there.'**
  String hostingStepAuthorizeDevice(String action);

  /// Setup guide step: copy the GitLab application ID.
  ///
  /// In en, this message translates to:
  /// **'Copy its Application ID into the {field} field.'**
  String hostingStepCopyApplicationId(String field);

  /// Setup guide step: copy the client ID.
  ///
  /// In en, this message translates to:
  /// **'Copy its Client ID into the {field} field.'**
  String hostingStepCopyClientId(String field);

  /// Setup guide step before the redirect URI.
  ///
  /// In en, this message translates to:
  /// **'Add this redirect URI to the application:'**
  String get hostingStepRedirect;

  /// Setup guide step: enable GitHub device flow.
  ///
  /// In en, this message translates to:
  /// **'Turn on Device Flow for the app.'**
  String get hostingStepDeviceFlow;

  /// Setup guide step: create the Codeberg application.
  ///
  /// In en, this message translates to:
  /// **'In Codeberg, open Settings → Applications → Manage OAuth2 Applications and create an application.'**
  String get hostingStepCreateCodeberg;

  /// Setup guide step: create the Forgejo application.
  ///
  /// In en, this message translates to:
  /// **'On your server, open Settings → Applications and create an OAuth2 application.'**
  String get hostingStepCreateForgejo;

  /// Setup guide step: create the GitLab application.
  ///
  /// In en, this message translates to:
  /// **'In GitLab, open your profile → Access → Applications and create an application.'**
  String get hostingStepCreateGitLab;

  /// Setup guide step: create or obtain a GitHub Enterprise OAuth app.
  ///
  /// In en, this message translates to:
  /// **'On your server, open Developer settings → OAuth Apps and create an OAuth app, or ask your organization for the Client ID of an existing one.'**
  String get hostingStepCreateEnterprise;

  /// Setup guide step: create the GitHub OAuth app.
  ///
  /// In en, this message translates to:
  /// **'In GitHub, open Developer settings → OAuth Apps and create an OAuth app.'**
  String get hostingStepCreateGitHub;

  /// Setup guide step for self-hosted providers.
  ///
  /// In en, this message translates to:
  /// **'Enter your server\'s address in the {field} field.'**
  String hostingStepEnterServer(String field);

  /// Setup guide step after the CLI sign-in.
  ///
  /// In en, this message translates to:
  /// **'Come back here and select {action}.'**
  String hostingStepCliReturn(String action);

  /// Setup guide step before the CLI sign-in command.
  ///
  /// In en, this message translates to:
  /// **'In a terminal, sign in to this server with {tool}:'**
  String hostingStepCliSignIn(String tool);

  /// Stands for the server name in a setup command when none is entered yet.
  ///
  /// In en, this message translates to:
  /// **'your-server'**
  String get hostingGuideServerPlaceholder;

  /// Open provider OAuth application settings.
  ///
  /// In en, this message translates to:
  /// **'Open application settings'**
  String get hostingGuideOpenSettings;

  /// Validation message for an empty connection name.
  ///
  /// In en, this message translates to:
  /// **'Enter a connection name.'**
  String get hostingGuideEnterName;

  /// Validation message for an empty public OAuth client ID.
  ///
  /// In en, this message translates to:
  /// **'Enter the OAuth client ID. Open the setup guide to find it.'**
  String get hostingGuideEnterClientId;

  /// Validation message for an invalid self-managed hosting server URL.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid server URL to fill in the API URL.'**
  String get hostingGuideEnterServer;

  /// Duplicate hosting connection name validation.
  ///
  /// In en, this message translates to:
  /// **'A connection with this name already exists. Choose another name.'**
  String get hostingGuideNameInUse;

  /// Hosting connection authentication method field label.
  ///
  /// In en, this message translates to:
  /// **'Authentication method'**
  String get hostingAuthenticationMethod;

  /// Hosting authentication through a public OAuth application.
  ///
  /// In en, this message translates to:
  /// **'OAuth application'**
  String get hostingOAuthApplication;

  /// Hosting authentication through GitHub CLI.
  ///
  /// In en, this message translates to:
  /// **'GitHub CLI'**
  String get hostingGitHubCli;

  /// Explanation of GitHub CLI credential ownership.
  ///
  /// In en, this message translates to:
  /// **'Uses the GitHub CLI account for this host. GitLama does not copy its token into its own credential store.'**
  String get hostingGitHubCliHint;

  /// Connect hosting account using GitHub CLI credential.
  ///
  /// In en, this message translates to:
  /// **'Connect with GitHub CLI'**
  String get hostingConnectWithCli;

  /// GitLab CLI authentication option.
  ///
  /// In en, this message translates to:
  /// **'GitLab CLI'**
  String get hostingGitLabCli;

  /// GitLab CLI credential ownership explanation.
  ///
  /// In en, this message translates to:
  /// **'Uses the GitLab CLI account for this host. GitLama does not copy its token into its own credential store.'**
  String get hostingGitLabCliHint;

  /// Connect using an existing GitLab CLI credential.
  ///
  /// In en, this message translates to:
  /// **'Connect with GitLab CLI'**
  String get hostingConnectWithGitLabCli;

  /// Action to validate and authorize a new hosting connection.
  ///
  /// In en, this message translates to:
  /// **'Save and authorize'**
  String get hostingSaveAuthorize;

  /// Action to authorize an existing hosting connection again.
  ///
  /// In en, this message translates to:
  /// **'Reauthorize'**
  String get hostingReauthorize;

  /// Action and confirmation title for removing a hosting connection.
  ///
  /// In en, this message translates to:
  /// **'Remove connection'**
  String get hostingRemove;

  /// Hosting connection enabled toggle.
  ///
  /// In en, this message translates to:
  /// **'Connection enabled'**
  String get hostingEnabled;

  /// Enabled hosting account state.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get hostingStateEnabled;

  /// Disabled hosting account state.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get hostingStateDisabled;

  /// Hosting background refresh toggle.
  ///
  /// In en, this message translates to:
  /// **'Background refresh'**
  String get hostingBackgroundRefresh;

  /// Pending OAuth authorization status.
  ///
  /// In en, this message translates to:
  /// **'Waiting for provider authorization…'**
  String get hostingAuthorizationWaiting;

  /// No description provided for @hostingAuthorizationCode.
  ///
  /// In en, this message translates to:
  /// **'Device code: {code}'**
  String hostingAuthorizationCode(String code);

  /// Action to open a canonical provider URL.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get hostingOpenBrowser;

  /// Repository hosting binding section title.
  ///
  /// In en, this message translates to:
  /// **'Repository binding'**
  String get hostingBinding;

  /// Action to remove an explicit binding override.
  ///
  /// In en, this message translates to:
  /// **'Use automatic binding'**
  String get hostingAutomaticBinding;

  /// No matching hosting binding state.
  ///
  /// In en, this message translates to:
  /// **'No connection matches this repository remote.'**
  String get hostingNoBinding;

  /// Ambiguous hosting binding state.
  ///
  /// In en, this message translates to:
  /// **'More than one connection matches this remote. Choose one explicitly.'**
  String get hostingAmbiguousBinding;

  /// Hosting connection selector label.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get hostingConnection;

  /// Git remote selector label for hosting binding.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get hostingRemote;

  /// Provider-native repository identity field label.
  ///
  /// In en, this message translates to:
  /// **'Provider repository'**
  String get hostingProviderRepository;

  /// Action to save a repository hosting override.
  ///
  /// In en, this message translates to:
  /// **'Save binding override'**
  String get hostingSaveBinding;

  /// Provider resources section title.
  ///
  /// In en, this message translates to:
  /// **'Provider resources'**
  String get hostingResources;

  /// Provider resource descendant filter label.
  ///
  /// In en, this message translates to:
  /// **'Filter pull requests and issues'**
  String get hostingFilter;

  /// Provider pull or merge request group title.
  ///
  /// In en, this message translates to:
  /// **'Pull requests'**
  String get hostingChangeRequests;

  /// Toolbar title of a repository tab inside a named tab group.
  ///
  /// In en, this message translates to:
  /// **'{group} / {repository}'**
  String repositoryTitleInGroup(String group, String repository);

  /// Marks a linked pull request that was merged.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get hostingPullRequestMerged;

  /// Marks a linked pull request the bound hosting account opened.
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get hostingPullRequestYours;

  /// Source and target branch of a pull request.
  ///
  /// In en, this message translates to:
  /// **'{source} into {target}'**
  String hostingPullRequestBranches(String source, String target);

  /// Provider issue group title.
  ///
  /// In en, this message translates to:
  /// **'Issues'**
  String get hostingIssues;

  /// Manual provider refresh action.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get hostingRefresh;

  /// Explicit next provider page action.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get hostingLoadMore;

  /// Background refresh status while cached content remains visible.
  ///
  /// In en, this message translates to:
  /// **'Refreshing; cached results remain available.'**
  String get hostingLoadingCached;

  /// Successful empty provider resource state.
  ///
  /// In en, this message translates to:
  /// **'No provider resources found.'**
  String get hostingEmpty;

  /// Cached provider resource marker.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get hostingStale;

  /// Pull request checkout action.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get hostingCheckout;

  /// Open in-app review action.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get hostingReview;

  /// Open canonical create pull request page action.
  ///
  /// In en, this message translates to:
  /// **'Create pull request'**
  String get hostingCreateChangeRequest;

  /// Reason a provider action is disabled.
  ///
  /// In en, this message translates to:
  /// **'This provider connection does not support this action.'**
  String get hostingCapabilityUnavailable;

  /// Reason checkout is disabled for an unresolved fork branch.
  ///
  /// In en, this message translates to:
  /// **'Fetch the fork branch before checking it out.'**
  String get hostingForkCheckoutUnavailable;

  /// No description provided for @hostingFailure.
  ///
  /// In en, this message translates to:
  /// **'Provider request failed: {reason}'**
  String hostingFailure(String reason);

  /// Provider answered 404 or 410.
  ///
  /// In en, this message translates to:
  /// **'The server does not know this address. Check the API base URL and the repository name, and that this account can access the repository.'**
  String get hostingFailureNotFound;

  /// Provider answered with a redirect.
  ///
  /// In en, this message translates to:
  /// **'The server redirected the request. The repository may have been renamed or moved, or the API base URL is wrong.'**
  String get hostingFailureRedirected;

  /// Provider answered with a 5xx status.
  ///
  /// In en, this message translates to:
  /// **'The server reported an internal error. Try again later.'**
  String get hostingFailureServerError;

  /// Provider host could not be resolved or connected.
  ///
  /// In en, this message translates to:
  /// **'The server could not be reached. Check the network connection, VPN and proxy.'**
  String get hostingFailureNetwork;

  /// TLS handshake or certificate verification failed.
  ///
  /// In en, this message translates to:
  /// **'The secure connection could not be established. Check that the curl on your PATH trusts the server certificate.'**
  String get hostingFailureCertificate;

  /// Provider request timed out.
  ///
  /// In en, this message translates to:
  /// **'The server did not answer in time.'**
  String get hostingFailureTimedOut;

  /// Safe hosting settings persistence failure.
  ///
  /// In en, this message translates to:
  /// **'The hosting settings could not be saved.'**
  String get hostingSettingsFailure;

  /// Empty commit-message reference picker state.
  ///
  /// In en, this message translates to:
  /// **'No matching pull requests or issues.'**
  String get hostingReferenceEmpty;

  /// Review workspace title.
  ///
  /// In en, this message translates to:
  /// **'Review #{number}'**
  String hostingReviewTitle(int number);

  /// Review thread list title.
  ///
  /// In en, this message translates to:
  /// **'Review comments'**
  String get hostingReviewThreads;

  /// Action to create a new draft from an outdated comment anchor.
  ///
  /// In en, this message translates to:
  /// **'Re-anchor'**
  String get hostingReviewReanchor;

  /// State of a review comment on an older diff.
  ///
  /// In en, this message translates to:
  /// **'Outdated'**
  String get hostingReviewOutdated;

  /// Inline review draft dialog title.
  ///
  /// In en, this message translates to:
  /// **'Comment on line {line}'**
  String hostingReviewInlineTitle(int line);

  /// Saves a line comment into the review draft.
  ///
  /// In en, this message translates to:
  /// **'Add to review'**
  String get hostingReviewInlineSave;

  /// Review body field label.
  ///
  /// In en, this message translates to:
  /// **'Review text'**
  String get hostingReviewComment;

  /// Review action selector label.
  ///
  /// In en, this message translates to:
  /// **'Review action'**
  String get hostingReviewAction;

  /// Comment-only review action.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get hostingReviewCommentAction;

  /// Approve review action.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get hostingReviewApprove;

  /// Request-changes review action.
  ///
  /// In en, this message translates to:
  /// **'Request changes'**
  String get hostingReviewRequestChanges;

  /// Open exact review target and payload preview.
  ///
  /// In en, this message translates to:
  /// **'Preview review'**
  String get hostingReviewPreview;

  /// Title of the confirmation before a review is posted.
  ///
  /// In en, this message translates to:
  /// **'Submit this review?'**
  String get hostingReviewAuthorize;

  /// Disclosure title over the exact request sent to the hosting provider.
  ///
  /// In en, this message translates to:
  /// **'Request details'**
  String get hostingRequestDetails;

  /// Review confirmation: how many line comments are included.
  ///
  /// In en, this message translates to:
  /// **'Line comments'**
  String get hostingReviewInlineComments;

  /// What submitting the review does.
  ///
  /// In en, this message translates to:
  /// **'GitLama posts your review to #{number}.'**
  String hostingReviewAuthorizeSummary(int number);

  /// Submit the authorized review payload.
  ///
  /// In en, this message translates to:
  /// **'Submit review'**
  String get hostingReviewSubmit;

  /// Empty review diff state.
  ///
  /// In en, this message translates to:
  /// **'No review diff is available.'**
  String get hostingReviewNoDiff;

  /// Safe review loading failure banner.
  ///
  /// In en, this message translates to:
  /// **'Could not load this review.'**
  String get hostingReviewLoadFailed;

  /// Safe typed review failure.
  ///
  /// In en, this message translates to:
  /// **'Review failed: {reason}'**
  String hostingReviewFailure(String reason);

  /// Provider check details section title.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get hostingChecks;

  /// Retry a provider check or pipeline.
  ///
  /// In en, this message translates to:
  /// **'Re-run'**
  String get hostingCheckRetry;

  /// Title of the confirmation before a check is re-run.
  ///
  /// In en, this message translates to:
  /// **'Run this check again?'**
  String get hostingCheckRetryAuthorize;

  /// What re-running a check does.
  ///
  /// In en, this message translates to:
  /// **'GitLama asks the provider to run {name} again.'**
  String hostingCheckRetrySummary(String name);

  /// CLI forwarding failure written before the app UI starts.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not forward the command safely.'**
  String get cliForwardingFailed;

  /// No description provided for @galleryStatus.
  ///
  /// In en, this message translates to:
  /// **'Activations: {count} · Menu: {menu}'**
  String galleryStatus(int count, String menu);

  /// Stage one complete diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Stage hunk'**
  String get stageHunk;

  /// Unstage one complete diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Unstage hunk'**
  String get unstageHunk;

  /// Discard one complete unstaged diff hunk.
  ///
  /// In en, this message translates to:
  /// **'Discard hunk'**
  String get discardHunk;

  /// Explain the lease protection used for force push.
  ///
  /// In en, this message translates to:
  /// **'For commits you have rewritten. Refused if someone else pushed to it since your last fetch.'**
  String get transferForceHelp;

  /// Meridian gallery specimen text for gallerySectionButton.
  ///
  /// In en, this message translates to:
  /// **'Button'**
  String get gallerySectionButton;

  /// Meridian gallery specimen text for gallerySectionIconButton.
  ///
  /// In en, this message translates to:
  /// **'IconButton'**
  String get gallerySectionIconButton;

  /// Meridian gallery specimen text for gallerySectionToolbarButton.
  ///
  /// In en, this message translates to:
  /// **'ToolbarButton'**
  String get gallerySectionToolbarButton;

  /// Meridian gallery specimen text for gallerySectionCheckbox.
  ///
  /// In en, this message translates to:
  /// **'Checkbox'**
  String get gallerySectionCheckbox;

  /// Meridian gallery specimen text for gallerySectionSegmented.
  ///
  /// In en, this message translates to:
  /// **'Segmented'**
  String get gallerySectionSegmented;

  /// Meridian gallery specimen text for gallerySectionSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get gallerySectionSelect;

  /// Meridian gallery specimen text for gallerySectionTextField.
  ///
  /// In en, this message translates to:
  /// **'TextField'**
  String get gallerySectionTextField;

  /// Meridian gallery specimen text for gallerySectionCompass.
  ///
  /// In en, this message translates to:
  /// **'Compass'**
  String get gallerySectionCompass;

  /// Meridian gallery specimen text for gallerySectionPalette.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get gallerySectionPalette;

  /// Meridian gallery specimen text for gallerySectionRepoTabs.
  ///
  /// In en, this message translates to:
  /// **'RepoTabs'**
  String get gallerySectionRepoTabs;

  /// Meridian gallery specimen text for gallerySectionSidebarRow.
  ///
  /// In en, this message translates to:
  /// **'SidebarRow'**
  String get gallerySectionSidebarRow;

  /// Meridian gallery specimen text for gallerySectionAvatar.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get gallerySectionAvatar;

  /// Meridian gallery specimen text for gallerySectionCommitRow.
  ///
  /// In en, this message translates to:
  /// **'CommitRow'**
  String get gallerySectionCommitRow;

  /// Meridian gallery specimen text for gallerySectionComposer.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get gallerySectionComposer;

  /// Meridian gallery specimen text for gallerySectionDiffHunk.
  ///
  /// In en, this message translates to:
  /// **'DiffHunk'**
  String get gallerySectionDiffHunk;

  /// Sample hunk header in the component gallery.
  ///
  /// In en, this message translates to:
  /// **'@@ -169,3 +169,12 @@ jobs:'**
  String get galleryDiffSampleHunk;

  /// Sample unchanged code line in the component gallery.
  ///
  /// In en, this message translates to:
  /// **'  run: |'**
  String get galleryDiffSampleContext;

  /// Sample deleted code line in the component gallery.
  ///
  /// In en, this message translates to:
  /// **'    old_value = 1'**
  String get galleryDiffSampleDeleted;

  /// Sample added code line in the component gallery.
  ///
  /// In en, this message translates to:
  /// **'    new_value = 2'**
  String get galleryDiffSampleAdded;

  /// Sample file path in the component gallery.
  ///
  /// In en, this message translates to:
  /// **'lib/app/main.dart'**
  String get galleryDiffSamplePath;

  /// Meridian gallery specimen text for gallerySectionFileRow.
  ///
  /// In en, this message translates to:
  /// **'FileRow'**
  String get gallerySectionFileRow;

  /// Meridian gallery specimen text for gallerySectionGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get gallerySectionGraph;

  /// Meridian gallery specimen text for gallerySectionRefChip.
  ///
  /// In en, this message translates to:
  /// **'RefChip'**
  String get gallerySectionRefChip;

  /// Meridian gallery specimen text for gallerySectionStatusGlyph.
  ///
  /// In en, this message translates to:
  /// **'StatusGlyph'**
  String get gallerySectionStatusGlyph;

  /// Meridian gallery specimen text for gallerySectionSyncBadge.
  ///
  /// In en, this message translates to:
  /// **'SyncBadge'**
  String get gallerySectionSyncBadge;

  /// Meridian gallery specimen text for gallerySectionBanner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get gallerySectionBanner;

  /// Meridian gallery specimen text for gallerySectionKbd.
  ///
  /// In en, this message translates to:
  /// **'Kbd'**
  String get gallerySectionKbd;

  /// Meridian gallery specimen text for gallerySectionLogbook.
  ///
  /// In en, this message translates to:
  /// **'Logbook'**
  String get gallerySectionLogbook;

  /// Meridian gallery specimen text for gallerySectionDialog.
  ///
  /// In en, this message translates to:
  /// **'Dialog'**
  String get gallerySectionDialog;

  /// Meridian gallery specimen text for gallerySectionIsland.
  ///
  /// In en, this message translates to:
  /// **'Island'**
  String get gallerySectionIsland;

  /// Meridian gallery specimen text for gallerySectionSettingsRow.
  ///
  /// In en, this message translates to:
  /// **'SettingsRow'**
  String get gallerySectionSettingsRow;

  /// Meridian gallery specimen text for galleryPaletteMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get galleryPaletteMove;

  /// Meridian gallery specimen text for galleryPaletteRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get galleryPaletteRun;

  /// Meridian gallery specimen text for galleryPaletteBackground.
  ///
  /// In en, this message translates to:
  /// **'Run in background'**
  String get galleryPaletteBackground;

  /// Meridian gallery specimen text for galleryPaletteScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get galleryPaletteScope;

  /// Meridian gallery specimen text for galleryCommitToMain.
  ///
  /// In en, this message translates to:
  /// **'Commit to main'**
  String get galleryCommitToMain;

  /// Meridian gallery specimen text for galleryPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get galleryPush;

  /// Meridian gallery specimen text for galleryCopyHash.
  ///
  /// In en, this message translates to:
  /// **'Copy hash'**
  String get galleryCopyHash;

  /// Meridian gallery specimen text for galleryDiscardThreeFiles.
  ///
  /// In en, this message translates to:
  /// **'Discard 3 files'**
  String get galleryDiscardThreeFiles;

  /// Meridian gallery specimen text for galleryDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get galleryDiscard;

  /// Meridian gallery specimen text for galleryFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching…'**
  String get galleryFetching;

  /// Meridian gallery specimen text for galleryPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get galleryPull;

  /// Meridian gallery specimen text for galleryCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get galleryCommit;

  /// Meridian gallery specimen text for galleryStageHunk.
  ///
  /// In en, this message translates to:
  /// **'Stage hunk'**
  String get galleryStageHunk;

  /// Meridian gallery specimen text for galleryShowAllFiles.
  ///
  /// In en, this message translates to:
  /// **'Show all 42 files'**
  String get galleryShowAllFiles;

  /// Meridian gallery specimen text for galleryFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get galleryFilter;

  /// Meridian gallery specimen text for gallerySideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get gallerySideBySide;

  /// Meridian gallery specimen text for galleryUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified'**
  String get galleryUnified;

  /// Meridian gallery specimen text for galleryMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get galleryMore;

  /// Meridian gallery specimen text for galleryCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get galleryCopy;

  /// Meridian gallery specimen text for galleryStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get galleryStage;

  /// Meridian gallery specimen text for galleryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get galleryDelete;

  /// Meridian gallery specimen text for galleryFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get galleryFetch;

  /// Meridian gallery specimen text for galleryStash.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get galleryStash;

  /// Meridian gallery specimen text for galleryBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get galleryBranch;

  /// Meridian gallery specimen text for galleryMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get galleryMerge;

  /// Meridian gallery specimen text for gallerySignCommit.
  ///
  /// In en, this message translates to:
  /// **'Sign commit'**
  String get gallerySignCommit;

  /// Meridian gallery specimen text for galleryAmend.
  ///
  /// In en, this message translates to:
  /// **'Amend'**
  String get galleryAmend;

  /// Meridian gallery specimen text for galleryStageAllMixed.
  ///
  /// In en, this message translates to:
  /// **'Stage all (2 of 5)'**
  String get galleryStageAllMixed;

  /// Meridian gallery specimen text for galleryBypassHooks.
  ///
  /// In en, this message translates to:
  /// **'Bypass hooks'**
  String get galleryBypassHooks;

  /// Meridian gallery specimen text for galleryFetchAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Fetch automatically'**
  String get galleryFetchAutomatically;

  /// Meridian gallery specimen text for galleryIncludeTags.
  ///
  /// In en, this message translates to:
  /// **'Include tags'**
  String get galleryIncludeTags;

  /// Meridian gallery specimen text for galleryModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get galleryModified;

  /// Meridian gallery specimen text for galleryAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get galleryAdded;

  /// Meridian gallery specimen text for galleryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get galleryDeleted;

  /// Meridian gallery specimen text for galleryRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get galleryRenamed;

  /// Meridian gallery specimen text for galleryCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get galleryCopied;

  /// Meridian gallery specimen text for galleryConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get galleryConflict;

  /// Meridian gallery specimen text for galleryUntracked.
  ///
  /// In en, this message translates to:
  /// **'Untracked'**
  String get galleryUntracked;

  /// Meridian gallery specimen text for galleryIgnored.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get galleryIgnored;

  /// Meridian gallery specimen text for galleryTwoConflicts.
  ///
  /// In en, this message translates to:
  /// **'2 conflicts'**
  String get galleryTwoConflicts;

  /// Meridian gallery specimen text for galleryMichaelLamers.
  ///
  /// In en, this message translates to:
  /// **'Michael Lamers'**
  String get galleryMichaelLamers;

  /// Meridian gallery specimen text for galleryGitLamaReleaseBot.
  ///
  /// In en, this message translates to:
  /// **'GitLama Release Bot'**
  String get galleryGitLamaReleaseBot;

  /// Meridian gallery specimen text for galleryAuthorHandle.
  ///
  /// In en, this message translates to:
  /// **'ada'**
  String get galleryAuthorHandle;

  /// Meridian gallery specimen text for galleryAdaGit.
  ///
  /// In en, this message translates to:
  /// **'Ada Git'**
  String get galleryAdaGit;

  /// Meridian gallery specimen text for gallerySearchCommits.
  ///
  /// In en, this message translates to:
  /// **'Search commits, authors, hashes'**
  String get gallerySearchCommits;

  /// Meridian gallery specimen text for galleryRefPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'refs/heads/main'**
  String get galleryRefPlaceholder;

  /// Meridian gallery specimen text for galleryRefValue.
  ///
  /// In en, this message translates to:
  /// **'feature/spline-graph'**
  String get galleryRefValue;

  /// Meridian gallery specimen text for galleryInvalidRef.
  ///
  /// In en, this message translates to:
  /// **'feature/..bad'**
  String get galleryInvalidRef;

  /// Meridian gallery specimen text for galleryInvalidRefMessage.
  ///
  /// In en, this message translates to:
  /// **'Branch names cannot contain “..”'**
  String get galleryInvalidRefMessage;

  /// Meridian gallery specimen text for galleryRebasePaused.
  ///
  /// In en, this message translates to:
  /// **'Rebase paused at 3 of 7.'**
  String get galleryRebasePaused;

  /// Meridian gallery specimen text for galleryRebaseConflicts.
  ///
  /// In en, this message translates to:
  /// **'2 files still have conflicts in lib/app.'**
  String get galleryRebaseConflicts;

  /// Meridian gallery specimen text for galleryAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get galleryAbort;

  /// Meridian gallery specimen text for galleryContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get galleryContinue;

  /// Meridian gallery specimen text for galleryPushRejected.
  ///
  /// In en, this message translates to:
  /// **'Push rejected.'**
  String get galleryPushRejected;

  /// Meridian gallery specimen text for galleryPushRejectedMessage.
  ///
  /// In en, this message translates to:
  /// **'origin/main has 6 commits you don’t have.'**
  String get galleryPushRejectedMessage;

  /// Meridian gallery specimen text for galleryPullFirst.
  ///
  /// In en, this message translates to:
  /// **'Pull first'**
  String get galleryPullFirst;

  /// Meridian gallery specimen text for galleryAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed for git.example.com.'**
  String get galleryAuthFailed;

  /// Meridian gallery specimen text for galleryTokenExpired.
  ///
  /// In en, this message translates to:
  /// **'The token expired on 24 Sep.'**
  String get galleryTokenExpired;

  /// Meridian gallery specimen text for galleryUpdateCredentials.
  ///
  /// In en, this message translates to:
  /// **'Update credentials'**
  String get galleryUpdateCredentials;

  /// Meridian gallery specimen text for galleryLfsMessage.
  ///
  /// In en, this message translates to:
  /// **'This repository uses Git LFS. 14 files are pointers until you fetch them.'**
  String get galleryLfsMessage;

  /// Meridian gallery specimen text for galleryDiffLayout.
  ///
  /// In en, this message translates to:
  /// **'Diff layout'**
  String get galleryDiffLayout;

  /// Meridian gallery specimen text for galleryFileList.
  ///
  /// In en, this message translates to:
  /// **'File list'**
  String get galleryFileList;

  /// Meridian gallery specimen text for gallerySplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get gallerySplit;

  /// Meridian gallery specimen text for galleryList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get galleryList;

  /// Meridian gallery specimen text for galleryTree.
  ///
  /// In en, this message translates to:
  /// **'Tree'**
  String get galleryTree;

  /// Meridian gallery specimen text for galleryThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get galleryThemeSystem;

  /// Meridian gallery specimen text for galleryDates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get galleryDates;

  /// Meridian gallery specimen text for galleryRemotes.
  ///
  /// In en, this message translates to:
  /// **'Remotes'**
  String get galleryRemotes;

  /// Meridian gallery specimen text for galleryDensityHelp.
  ///
  /// In en, this message translates to:
  /// **'Changes row height only. Text and icons stay the same size.'**
  String get galleryDensityHelp;

  /// Meridian gallery specimen text for galleryRemotesHelp.
  ///
  /// In en, this message translates to:
  /// **'Every 10 minutes, in the background. Shown in the Logbook.'**
  String get galleryRemotesHelp;

  /// Meridian gallery specimen text for galleryRebaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Rebase windows-soak-cleanup onto origin/main'**
  String get galleryRebaseTitle;

  /// Meridian gallery specimen text for galleryRebaseDescription.
  ///
  /// In en, this message translates to:
  /// **'4 commits will be replayed on top of 6 new commits from origin/main.'**
  String get galleryRebaseDescription;

  /// Meridian gallery specimen text for galleryAutostash.
  ///
  /// In en, this message translates to:
  /// **'Autostash'**
  String get galleryAutostash;

  /// Meridian gallery specimen text for galleryRebase.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get galleryRebase;

  /// Meridian gallery specimen text for galleryFourCommits.
  ///
  /// In en, this message translates to:
  /// **'4 commits'**
  String get galleryFourCommits;

  /// Meridian gallery specimen text for galleryFocusedIsland.
  ///
  /// In en, this message translates to:
  /// **'Focused island: 1px polar-soft halo, solid polar selection.'**
  String get galleryFocusedIsland;

  /// Meridian gallery specimen text for galleryUnfocusedIsland.
  ///
  /// In en, this message translates to:
  /// **'Unfocused island: selection drops to polar-soft.'**
  String get galleryUnfocusedIsland;

  /// Meridian gallery specimen text for galleryDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get galleryDetail;

  /// Meridian gallery specimen text for galleryPaletteQuery.
  ///
  /// In en, this message translates to:
  /// **'reb'**
  String get galleryPaletteQuery;

  /// Meridian gallery specimen text for galleryPaletteCommands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get galleryPaletteCommands;

  /// Meridian gallery specimen text for galleryPaletteBranches.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get galleryPaletteBranches;

  /// Meridian gallery specimen text for galleryPaletteRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get galleryPaletteRecent;

  /// Meridian gallery specimen text for galleryPaletteRebaseTarget.
  ///
  /// In en, this message translates to:
  /// **'Rebase windows-soak-cleanup onto origin/main'**
  String get galleryPaletteRebaseTarget;

  /// Meridian gallery specimen text for galleryPaletteInteractiveRebase.
  ///
  /// In en, this message translates to:
  /// **'Interactive rebase…'**
  String get galleryPaletteInteractiveRebase;

  /// Meridian gallery specimen text for galleryPaletteLastCommits.
  ///
  /// In en, this message translates to:
  /// **'last 5 commits'**
  String get galleryPaletteLastCommits;

  /// Meridian gallery specimen text for galleryPaletteBranchRef.
  ///
  /// In en, this message translates to:
  /// **'feature/rebuild-graph-cache'**
  String get galleryPaletteBranchRef;

  /// Meridian gallery specimen text for galleryPaletteOrigin.
  ///
  /// In en, this message translates to:
  /// **'origin'**
  String get galleryPaletteOrigin;

  /// Meridian gallery specimen text for galleryPaletteAbortRebase.
  ///
  /// In en, this message translates to:
  /// **'Abort rebase'**
  String get galleryPaletteAbortRebase;

  /// Meridian gallery specimen text for galleryPaletteYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get galleryPaletteYesterday;

  /// No description provided for @compassConflicts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 conflict} other{{count} conflicts}}'**
  String compassConflicts(int count);

  /// No description provided for @compassChangedFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 changed file} other{{count} changed files}}'**
  String compassChangedFiles(int count);

  /// Title and tooltip of the overlay the Compass opens with details about the active repository.
  ///
  /// In en, this message translates to:
  /// **'Repository details'**
  String get repositoryDetailsTitle;

  /// Details row: the computer the repository is on.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get repositoryDetailsLocation;

  /// Details value: the repository is on this computer.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get repositoryDetailsThisComputer;

  /// Details value: a remote host's name with the OpenSSH alias GitLama connects through.
  ///
  /// In en, this message translates to:
  /// **'{host} ({alias})'**
  String repositoryDetailsHostWithAlias(String host, String alias);

  /// Details suffix: the remote host's connection is down.
  ///
  /// In en, this message translates to:
  /// **'disconnected'**
  String get repositoryDetailsDisconnected;

  /// Details row: the repository's folder.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get repositoryDetailsPath;

  /// Details row: the tab group the repository's tab belongs to.
  ///
  /// In en, this message translates to:
  /// **'Tab group'**
  String get repositoryDetailsGroup;

  /// Details row: what kind of repository it is.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get repositoryDetailsKind;

  /// Details value: a normal repository.
  ///
  /// In en, this message translates to:
  /// **'Repository with working tree'**
  String get repositoryDetailsWorktree;

  /// Details value: a working tree linked to another repository with git worktree.
  ///
  /// In en, this message translates to:
  /// **'Linked working tree'**
  String get repositoryDetailsLinkedWorktree;

  /// Details value: a repository without working tree.
  ///
  /// In en, this message translates to:
  /// **'Bare repository'**
  String get repositoryDetailsBare;

  /// Details row: the checked-out branch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get repositoryDetailsBranch;

  /// Details suffix: the branch has no commits yet.
  ///
  /// In en, this message translates to:
  /// **'no commits yet'**
  String get repositoryDetailsUnborn;

  /// Details row: the remote branch the current branch tracks.
  ///
  /// In en, this message translates to:
  /// **'Upstream'**
  String get repositoryDetailsUpstream;

  /// Details value: the current branch has no upstream.
  ///
  /// In en, this message translates to:
  /// **'Not tracking a remote branch'**
  String get repositoryDetailsNoUpstream;

  /// Details row: uncommitted changes and conflicts.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get repositoryDetailsChanges;

  /// Details value: the working tree has no changes.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get repositoryDetailsClean;

  /// Details row: a merge, rebase or similar Git operation that is in progress.
  ///
  /// In en, this message translates to:
  /// **'Git operation'**
  String get repositoryDetailsInProgress;

  /// Details row: work GitLama is running in the repository now.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get repositoryDetailsRunning;

  /// Details value: GitLama runs nothing in the repository.
  ///
  /// In en, this message translates to:
  /// **'Nothing running'**
  String get repositoryDetailsIdle;

  /// Details headline: the repository has no changes, conflicts or paused operations.
  ///
  /// In en, this message translates to:
  /// **'Working tree clean'**
  String get repositoryDetailsHealthClean;

  /// Details headline: the working tree has uncommitted changes.
  ///
  /// In en, this message translates to:
  /// **'Changes to commit'**
  String get repositoryDetailsHealthChanged;

  /// Details headline: the working tree has unresolved conflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts to resolve'**
  String get repositoryDetailsHealthConflicted;

  /// Details headline: a merge, rebase or similar Git operation waits to be continued.
  ///
  /// In en, this message translates to:
  /// **'Git operation paused'**
  String get repositoryDetailsHealthPaused;

  /// Details headline: GitLama is running work in the repository.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get repositoryDetailsHealthBusy;

  /// Details row: the Git version that runs the repository, on its host for a remote repository.
  ///
  /// In en, this message translates to:
  /// **'Git version'**
  String get repositoryDetailsGit;

  /// Copies a repository's folder path to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get repositoryCopyPath;

  /// Confirms that a repository's path was copied.
  ///
  /// In en, this message translates to:
  /// **'Repository path copied.'**
  String get repositoryPathCopied;

  /// Tooltip of the toolbar button that opens the command palette, with its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Commands ({shortcut})'**
  String commandPaletteShortcutTooltip(String shortcut);

  /// No description provided for @compassSemantics.
  ///
  /// In en, this message translates to:
  /// **'{repository}, {branch}, {ahead} ahead, {behind} behind, {dirty} changed files, {conflicts} conflicts. Show repository details.'**
  String compassSemantics(
    String repository,
    String branch,
    int ahead,
    int behind,
    int dirty,
    int conflicts,
  );

  /// Title and toolbar label for the operation logbook.
  ///
  /// In en, this message translates to:
  /// **'Logbook'**
  String get logbookTitle;

  /// Command that opens the dialog to rename a local branch or change its upstream.
  ///
  /// In en, this message translates to:
  /// **'Edit branch…'**
  String get commandEditBranch;

  /// Edit branch dialog field for the branch name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get editBranchName;

  /// Edit branch dialog field for the tracked remote branch.
  ///
  /// In en, this message translates to:
  /// **'Upstream'**
  String get editBranchUpstream;

  /// Edit branch choice that removes the upstream.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to track no remote branch.'**
  String get editBranchNoUpstream;

  /// Edit branch dialog confirmation action.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editBranchSave;

  /// Edit branch validation for a taken name.
  ///
  /// In en, this message translates to:
  /// **'A branch with this name already exists.'**
  String get editBranchNameExists;

  /// Edit branch dialog description.
  ///
  /// In en, this message translates to:
  /// **'Rename the local branch or change the remote branch it tracks.'**
  String get editBranchDescription;

  /// Confirmation text for setting a branch upstream.
  ///
  /// In en, this message translates to:
  /// **'Set {upstream} as the upstream of {name}.'**
  String refConfirmSetUpstream(String name, String upstream);

  /// Confirmation text for removing a branch upstream.
  ///
  /// In en, this message translates to:
  /// **'Remove the upstream of {name}. The remote branch is unchanged.'**
  String refConfirmUnsetUpstream(String name);

  /// Status after the diff text selection is copied.
  ///
  /// In en, this message translates to:
  /// **'Selection copied.'**
  String get diffSelectionCopied;

  /// Stages the diff lines touched by the text selection.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get diffSelectionStage;

  /// Unstages the diff lines touched by the text selection.
  ///
  /// In en, this message translates to:
  /// **'Unstage'**
  String get diffSelectionUnstage;

  /// Discards the diff lines touched by the text selection after confirmation.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes…'**
  String get diffSelectionDiscard;

  /// Diff context menu action copying the selected text.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get diffCopyLines;

  /// Diff context menu action copying the selected changed lines as a unified patch.
  ///
  /// In en, this message translates to:
  /// **'Copy as Patch'**
  String get diffCopyAsPatch;

  /// Confirmation after copying a patch of diff lines.
  ///
  /// In en, this message translates to:
  /// **'Patch copied.'**
  String get diffPatchCopied;

  /// Copy as Patch had no changed line to include.
  ///
  /// In en, this message translates to:
  /// **'The selected lines contain no changes.'**
  String get diffPatchUnavailable;

  /// Fetch dialog description.
  ///
  /// In en, this message translates to:
  /// **'Fetch the latest changes from a remote.'**
  String get transferFetchDescription;

  /// Pull dialog description.
  ///
  /// In en, this message translates to:
  /// **'Fetch a remote branch and integrate it into the current branch.'**
  String get transferPullDescription;

  /// Push dialog description.
  ///
  /// In en, this message translates to:
  /// **'Publish a local branch on a remote.'**
  String get transferPushDescription;

  /// Description of the Push tag dialog.
  ///
  /// In en, this message translates to:
  /// **'Publish a tag on a remote so others can fetch it.'**
  String get transferPushTagDescription;

  /// Explain remote branch deletion, its lease and that others may already have fetched the branch.
  ///
  /// In en, this message translates to:
  /// **'Delete a branch on a remote. It is deleted only if it has not moved since the last fetch. Others may already have fetched it.'**
  String get transferDeleteBranchDescription;

  /// Edit branch validation for an unknown upstream.
  ///
  /// In en, this message translates to:
  /// **'Choose a fetched remote branch, or leave the field empty.'**
  String get editBranchUpstreamUnknown;

  /// Chevron of a collapsed folder in the changes tree.
  ///
  /// In en, this message translates to:
  /// **'Expand folder'**
  String get changesExpandFolder;

  /// Chevron of an expanded folder in the changes tree.
  ///
  /// In en, this message translates to:
  /// **'Collapse folder'**
  String get changesCollapseFolder;

  /// Sidebar context-menu action that deletes a linked worktree after confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete worktree…'**
  String get extensionWorktreeDeleteAction;

  /// Repository tab context-menu action that opens the icon dialog.
  ///
  /// In en, this message translates to:
  /// **'Change icon…'**
  String get repositoryTabChangeIcon;

  /// Repository tab context-menu action that removes the tab's icon.
  ///
  /// In en, this message translates to:
  /// **'Remove icon'**
  String get repositoryTabRemoveIcon;

  /// Title of the dialog that chooses a repository tab's icon.
  ///
  /// In en, this message translates to:
  /// **'Repository icon'**
  String get repositoryIconTitle;

  /// Explains where a repository icon appears.
  ///
  /// In en, this message translates to:
  /// **'Shown in the repository\'s tab so you can find it at a glance.'**
  String get repositoryIconDescription;

  /// Heading of the icon choices in the repository icon dialog.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get repositoryIconSymbol;

  /// Heading of the colour choices in the repository icon dialog.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get repositoryIconColor;

  /// Heading of the custom image choice in the repository icon dialog.
  ///
  /// In en, this message translates to:
  /// **'Image file'**
  String get repositoryIconImage;

  /// Choice that shows no icon, only the colour if one is chosen.
  ///
  /// In en, this message translates to:
  /// **'No icon'**
  String get repositoryIconNone;

  /// Opens a file picker for a custom repository icon image.
  ///
  /// In en, this message translates to:
  /// **'Choose image…'**
  String get repositoryIconChooseImage;

  /// Removes the custom repository icon image.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get repositoryIconRemoveImage;

  /// Supported custom repository icon files.
  ///
  /// In en, this message translates to:
  /// **'PNG, JPEG, GIF, WebP, BMP, ICO or SVG, up to 2 MB. An image replaces the icon.'**
  String get repositoryIconImageHint;

  /// Shown when a chosen repository icon image cannot be read.
  ///
  /// In en, this message translates to:
  /// **'This image can\'t be used. Choose a supported file up to 2 MB.'**
  String get repositoryIconImageUnreadable;

  /// Saves the repository icon.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get repositoryIconSave;

  /// Shown when saving the repository icon fails.
  ///
  /// In en, this message translates to:
  /// **'The icon couldn\'t be saved.'**
  String get repositoryIconSaveFailed;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get repositoryIconNameRepository;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get repositoryIconNameCode;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get repositoryIconNameTerminal;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get repositoryIconNamePackage;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get repositoryIconNameComponents;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Plugin'**
  String get repositoryIconNamePlugin;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get repositoryIconNameLayers;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get repositoryIconNameDocumentation;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Design'**
  String get repositoryIconNameDesign;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get repositoryIconNameMedia;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get repositoryIconNameMobile;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get repositoryIconNameDesktop;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get repositoryIconNameServer;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get repositoryIconNameCloud;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Lightning'**
  String get repositoryIconNameLightning;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get repositoryIconNameStar;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Flag'**
  String get repositoryIconNameFlag;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get repositoryIconNameBug;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Magic'**
  String get repositoryIconNameMagic;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get repositoryIconNameLearning;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get repositoryIconNameSecurity;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get repositoryIconNameAnalytics;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get repositoryIconNameHome;

  /// Repository icon choice.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get repositoryIconNameTeam;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get repositoryColorBlue;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get repositoryColorTeal;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get repositoryColorAmber;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get repositoryColorOrange;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get repositoryColorRose;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get repositoryColorViolet;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get repositoryColorCyan;

  /// Repository icon colour.
  ///
  /// In en, this message translates to:
  /// **'Olive'**
  String get repositoryColorOlive;

  /// Colour choice that uses the default icon colour.
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get repositoryColorNone;

  /// Settings category for release channel and update checks.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdates;

  /// Description of the Updates settings category.
  ///
  /// In en, this message translates to:
  /// **'Choose which releases you receive and check for a newer version.'**
  String get settingsUpdatesDetail;

  /// Label of the installed application version.
  ///
  /// In en, this message translates to:
  /// **'Installed version'**
  String get updatesInstalledVersion;

  /// An application version with its build number.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {build})'**
  String updatesVersionAndBuild(String version, int build);

  /// Label of the choice between stable and beta releases.
  ///
  /// In en, this message translates to:
  /// **'Release channel'**
  String get updatesChannel;

  /// Release channel that receives stable releases only.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get updatesChannelStable;

  /// Release channel that receives beta and stable releases.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get updatesChannelBeta;

  /// Explains the beta release channel.
  ///
  /// In en, this message translates to:
  /// **'Beta also includes every stable release.'**
  String get updatesChannelHint;

  /// Button that looks for a newer release.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updatesCheck;

  /// Status while an update check runs.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updatesChecking;

  /// Status when no newer release exists.
  ///
  /// In en, this message translates to:
  /// **'GitLama {version} (build {build}) is up to date.'**
  String updatesUpToDate(String version, int build);

  /// Status when the selected channel has no release.
  ///
  /// In en, this message translates to:
  /// **'No release has been published for this channel yet.'**
  String get updatesNoRelease;

  /// Status when a newer release exists on Linux or Windows.
  ///
  /// In en, this message translates to:
  /// **'GitLama {version} (build {build}) is available. Download it from the releases page.'**
  String updatesAvailable(String version, int build);

  /// Button that opens the public releases page in the browser.
  ///
  /// In en, this message translates to:
  /// **'Open downloads page'**
  String get updatesOpenDownloads;

  /// Explains the macOS updater.
  ///
  /// In en, this message translates to:
  /// **'GitLama looks for updates in the background and installs one after you confirm.'**
  String get updatesAutomaticHint;

  /// Explains the update check on Linux and Windows.
  ///
  /// In en, this message translates to:
  /// **'GitLama contacts the release site only when you check. Install the download yourself.'**
  String get updatesManualHint;

  /// Update check failure: network or server.
  ///
  /// In en, this message translates to:
  /// **'The release site could not be reached. Try again later.'**
  String get updatesFailureUnavailable;

  /// Update check failure: malformed release index.
  ///
  /// In en, this message translates to:
  /// **'The release list could not be read.'**
  String get updatesFailureInvalid;

  /// Update check failure: platform updater.
  ///
  /// In en, this message translates to:
  /// **'The updater could not start.'**
  String get updatesFailureUpdater;

  /// Failure to open the releases page in the browser.
  ///
  /// In en, this message translates to:
  /// **'The downloads page could not be opened.'**
  String get updatesFailureOpen;

  /// Update check failure: unsupported build or platform.
  ///
  /// In en, this message translates to:
  /// **'This build cannot check for updates.'**
  String get updatesFailureUnsupported;

  /// Diff toolbar action writing the diff on screen to a patch file.
  ///
  /// In en, this message translates to:
  /// **'Create patch from this diff'**
  String get diffCreatePatch;

  /// First row of a commit's file list; shows the diff of every changed file.
  ///
  /// In en, this message translates to:
  /// **'All changes'**
  String get historyAllChanges;

  /// Shown on the all-changes row when the combined diff exceeds the read limit; files open one at a time.
  ///
  /// In en, this message translates to:
  /// **'Too large'**
  String get historyAllChangesTooLarge;

  /// Context menu group title for actions on the selected commits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected commit} other{{count} selected commits}}'**
  String menuSelectedCommits(int count);

  /// Context menu group title for actions on the selected files.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected file} other{{count} selected files}}'**
  String menuSelectedFiles(int count);

  /// Context menu action writing the selected commits to a patch file.
  ///
  /// In en, this message translates to:
  /// **'Create patch from selection'**
  String get patchCreateFromSelection;

  /// Context menu action writing one commit to a patch file.
  ///
  /// In en, this message translates to:
  /// **'Create patch from this commit'**
  String get patchCreateFromCommit;

  /// Context menu action writing one file's changes in the shown commit or comparison to a patch file.
  ///
  /// In en, this message translates to:
  /// **'Create patch from this file'**
  String get patchCreateFromFile;

  /// Linux window caption button minimizing the main window.
  ///
  /// In en, this message translates to:
  /// **'Minimize window'**
  String get windowMinimize;

  /// Linux window caption button toggling between maximized and restored.
  ///
  /// In en, this message translates to:
  /// **'Maximize or restore window'**
  String get windowMaximize;

  /// Linux window caption button closing the main window.
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get windowClose;

  /// Repository tab context-menu action that edits the tab's name in place.
  ///
  /// In en, this message translates to:
  /// **'Rename tab…'**
  String get repositoryTabRename;

  /// Repository tab context-menu action that removes the tab's custom name.
  ///
  /// In en, this message translates to:
  /// **'Use folder name'**
  String get repositoryTabResetName;

  /// Accessible name of the field that edits a repository tab's name in place.
  ///
  /// In en, this message translates to:
  /// **'Tab name'**
  String get repositoryTabRenameLabel;

  /// Repository tab context-menu action that starts a tab group with this tab.
  ///
  /// In en, this message translates to:
  /// **'Add to new group'**
  String get tabGroupAddToNew;

  /// Repository tab context submenu listing the tab groups.
  ///
  /// In en, this message translates to:
  /// **'Add to group'**
  String get tabGroupAddTo;

  /// Item in the Add to group submenu that starts a new group.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get tabGroupNew;

  /// Repository tab context-menu action that takes the tab out of its group.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get tabGroupRemoveTab;

  /// Tab group chip context-menu action that edits the group's name in place.
  ///
  /// In en, this message translates to:
  /// **'Rename group…'**
  String get tabGroupRename;

  /// Tab group editor heading over the group colours.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get tabGroupColor;

  /// Tab group editor heading over the icons the group's chip can show.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get tabGroupIcon;

  /// Tab group chip context menu item that opens the group editor.
  ///
  /// In en, this message translates to:
  /// **'Edit group…'**
  String get tabGroupEdit;

  /// Title of the dialog that sets a tab group's name, colour and icon.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get tabGroupEditTitle;

  /// Description of the tab group editor.
  ///
  /// In en, this message translates to:
  /// **'Name, color and icon of the group\'s chip in the tab bar.'**
  String get tabGroupEditDescription;

  /// Label of the tab group name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tabGroupEditName;

  /// Accessibility label of the tab group editor's live preview.
  ///
  /// In en, this message translates to:
  /// **'Preview of the group in the tab bar'**
  String get tabGroupEditPreview;

  /// Button that saves the tab group editor.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get tabGroupEditSave;

  /// Swatch that opens a colour picker for any colour beside the palette.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get repositoryColorCustom;

  /// Accessibility label of the colour picker's hue and saturation wheel.
  ///
  /// In en, this message translates to:
  /// **'Hue and saturation'**
  String get colorPickerWheel;

  /// Colour picker slider for the hue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get colorPickerHue;

  /// Colour picker slider for the saturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get colorPickerSaturation;

  /// Colour picker slider for the brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get colorPickerBrightness;

  /// Colour picker slider for the red channel.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorPickerRed;

  /// Colour picker slider for the green channel.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorPickerGreen;

  /// Colour picker slider for the blue channel.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorPickerBlue;

  /// Accessibility label of the colour picker's HSB/RGB switch.
  ///
  /// In en, this message translates to:
  /// **'Color model'**
  String get colorPickerModel;

  /// Colour picker segment for hue, saturation and brightness sliders.
  ///
  /// In en, this message translates to:
  /// **'HSB'**
  String get colorPickerHsb;

  /// Colour picker segment for red, green and blue sliders.
  ///
  /// In en, this message translates to:
  /// **'RGB'**
  String get colorPickerRgb;

  /// Accessibility label of the colour picker's hex field.
  ///
  /// In en, this message translates to:
  /// **'Hex value'**
  String get colorPickerHex;

  /// Error under an invalid hex colour value.
  ///
  /// In en, this message translates to:
  /// **'Enter six hex digits, such as #18304F'**
  String get colorPickerInvalidHex;

  /// The colour before the edit; a tap restores it.
  ///
  /// In en, this message translates to:
  /// **'Original color'**
  String get colorPickerOriginal;

  /// The colour being picked.
  ///
  /// In en, this message translates to:
  /// **'New color'**
  String get colorPickerNew;

  /// Name of a custom colour for menus and accessibility labels.
  ///
  /// In en, this message translates to:
  /// **'Custom {hex}'**
  String repositoryColorCustomValue(String hex);

  /// Accessibility label of a colour swatch without a name.
  ///
  /// In en, this message translates to:
  /// **'Color {hex}'**
  String colorPickerSwatch(String hex);

  /// A hue in degrees.
  ///
  /// In en, this message translates to:
  /// **'{value}°'**
  String colorPickerDegrees(int value);

  /// A saturation or brightness in percent.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String colorPickerPercent(int value);

  /// Screen reader action that moves a repository tab one place to the left.
  ///
  /// In en, this message translates to:
  /// **'Move tab left'**
  String get repositoryTabMoveLeft;

  /// Screen reader action that moves a repository tab one place to the right.
  ///
  /// In en, this message translates to:
  /// **'Move tab right'**
  String get repositoryTabMoveRight;

  /// Announced after a repository tab's name when its working tree has changes.
  ///
  /// In en, this message translates to:
  /// **'uncommitted changes'**
  String get repositoryTabUnsaved;

  /// Tab group chip context-menu action that hides the group's tabs.
  ///
  /// In en, this message translates to:
  /// **'Collapse group'**
  String get tabGroupCollapseAction;

  /// Tab group chip context-menu action that shows the group's tabs.
  ///
  /// In en, this message translates to:
  /// **'Expand group'**
  String get tabGroupExpandAction;

  /// Tab group chip context-menu action that dissolves the group and keeps its tabs open.
  ///
  /// In en, this message translates to:
  /// **'Ungroup'**
  String get tabGroupUngroup;

  /// Tab group chip context-menu action that closes every tab of the group.
  ///
  /// In en, this message translates to:
  /// **'Close group'**
  String get tabGroupClose;

  /// Placeholder of the field that names a tab group in place.
  ///
  /// In en, this message translates to:
  /// **'Name this group'**
  String get tabGroupNamePlaceholder;

  /// Accessible name of the field that edits a tab group's name in place.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get tabGroupRenameLabel;

  /// Name of a tab group the user has not named, after its colour.
  ///
  /// In en, this message translates to:
  /// **'{color} group'**
  String tabGroupUnnamed(String color);

  /// Tooltip of a collapsed tab group's chip.
  ///
  /// In en, this message translates to:
  /// **'Expand {name}'**
  String tabGroupExpand(String name);

  /// Tooltip of an expanded tab group's chip.
  ///
  /// In en, this message translates to:
  /// **'Collapse {name}'**
  String tabGroupCollapse(String name);

  /// Accessible label of a tab group's chip.
  ///
  /// In en, this message translates to:
  /// **'{name}, tab group, {count, plural, =1{1 tab} other{{count} tabs}}'**
  String tabGroupSemantics(String name, int count);

  /// Placeholder of the field that filters the Unstaged and Staged file lists by path.
  ///
  /// In en, this message translates to:
  /// **'Filter files'**
  String get changesFilterPlaceholder;

  /// Accessible name of the Changes file filter field.
  ///
  /// In en, this message translates to:
  /// **'Filter changed files'**
  String get changesFilterLabel;

  /// Button that clears the Changes file filter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get changesFilterClear;

  /// How many changed files the filter shows out of all of them.
  ///
  /// In en, this message translates to:
  /// **'{shown} of {total}'**
  String changesFilterCount(int shown, int total);

  /// Empty state of a Changes file list whose files the filter hides.
  ///
  /// In en, this message translates to:
  /// **'No matching files'**
  String get changesFilterNoMatches;

  /// Stages the files the Changes filter shows.
  ///
  /// In en, this message translates to:
  /// **'Stage shown files'**
  String get stageShown;

  /// Unstages the files the Changes filter shows.
  ///
  /// In en, this message translates to:
  /// **'Unstage shown files'**
  String get unstageShown;

  /// Short label of the button that stages the files the Changes filter shows.
  ///
  /// In en, this message translates to:
  /// **'Stage shown'**
  String get stageShortShown;

  /// Short label of the button that unstages the files the Changes filter shows.
  ///
  /// In en, this message translates to:
  /// **'Unstage shown'**
  String get unstageShortShown;

  /// Discards the changes of the files the Changes filter shows.
  ///
  /// In en, this message translates to:
  /// **'Discard shown files'**
  String get discardShown;

  /// Revert workflow text.
  ///
  /// In en, this message translates to:
  /// **'Revert commit'**
  String get historyRevertCommit;

  /// Revert workflow text.
  ///
  /// In en, this message translates to:
  /// **'Commit revert'**
  String get historyRevertCommitNow;

  /// Revert workflow text.
  ///
  /// In en, this message translates to:
  /// **'Apply without committing'**
  String get historyRevertApplyOnly;

  /// Why applying a revert without committing is unavailable for several commits.
  ///
  /// In en, this message translates to:
  /// **'Applying without committing works with one commit at a time.'**
  String get historyRevertApplySingleRequired;

  /// Warning in the revert dialog while the worktree has unresolved conflicts.
  ///
  /// In en, this message translates to:
  /// **'Resolve the conflicted files first: a revert can\'t start while files are conflicted.'**
  String get historyRevertResolveConflicts;

  /// Failure when an apply-only revert would need to set colliding or staged local changes aside.
  ///
  /// In en, this message translates to:
  /// **'An apply-only revert can\'t set your local changes aside. Revert with a commit instead, or commit or stash the changes it collides with first.'**
  String get historyMutationFailureLocalChanges;

  /// Property label in the revert review for what happens to the local changes.
  ///
  /// In en, this message translates to:
  /// **'Local changes'**
  String get historyPreviewLocalChanges;

  /// Revert review value: Git reverts with the local changes left untouched.
  ///
  /// In en, this message translates to:
  /// **'Stay where they are'**
  String get historyRevertLocalInPlace;

  /// Revert review value: the local changes are stashed and reapplied around the revert.
  ///
  /// In en, this message translates to:
  /// **'Set aside and reapplied'**
  String get historyRevertLocalSetAside;

  /// Revert review explanation when local changes stay in place.
  ///
  /// In en, this message translates to:
  /// **'None of your local changes is staged or touches a file this revert changes, so Git reverts around them.'**
  String get historyRevertLocalInPlaceDetail;

  /// Revert review heading above the local paths that collide with the revert.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 local change touches a file this revert changes:} other{{count} local changes touch files this revert changes:}}'**
  String historyRevertSetAsideFiles(int count);

  /// Revert review: how many colliding paths are not listed.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String historyRevertSetAsideMore(int count);

  /// Revert review: staged changes require setting the local changes aside.
  ///
  /// In en, this message translates to:
  /// **'Some of your local changes are staged, and Git doesn\'t revert over staged changes.'**
  String get historyRevertSetAsideStaged;

  /// Revert review: how local changes are set aside and reapplied.
  ///
  /// In en, this message translates to:
  /// **'GitLama saves your local changes in a stash, reverts, then reapplies them with their staging. If they conflict with the revert, you resolve them in Changes. A recovery copy remains in Stashes.'**
  String get historyRevertSetAsideExplain;

  /// Confirm button of a revert that sets local changes aside.
  ///
  /// In en, this message translates to:
  /// **'Set aside and revert'**
  String get historyRevertSetAsideAction;

  /// Result after a revert that set local changes aside and restored them.
  ///
  /// In en, this message translates to:
  /// **'Reverted. Your local changes and staging were restored. A recovery copy remains in Stashes.'**
  String get historyRevertSetAsideRestored;

  /// Result after a revert whose set-aside local changes conflict when reapplied.
  ///
  /// In en, this message translates to:
  /// **'Reverted, but reapplying your local changes caused conflicts. Resolve them in Changes. The recovery stash is kept.'**
  String get historyRevertSetAsideConflict;

  /// Result when a revert with set-aside local changes stops at conflicts.
  ///
  /// In en, this message translates to:
  /// **'The revert stopped at conflicts. Your local changes are set aside and come back when you continue or abort the revert.'**
  String get historyRevertSetAsidePending;

  /// Result when set-aside local changes could not be restored automatically.
  ///
  /// In en, this message translates to:
  /// **'Your local changes could not be fully restored; they remain saved in Stashes. Review Changes before applying the recovery stash.'**
  String get historyRevertSetAsideSaved;

  /// Revert workflow text.
  ///
  /// In en, this message translates to:
  /// **'Revert applied. Review the staged changes before committing.'**
  String get historyRevertApplied;

  /// Revert workflow text.
  ///
  /// In en, this message translates to:
  /// **'This selection contains a merge commit. Reverting a merge requires choosing a mainline parent, which is not supported here yet.'**
  String get historyRevertMergeUnsupported;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get menuRepository;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Changes and commits'**
  String get menuChanges;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get menuHistory;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Branches and tags'**
  String get menuBranches;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Remotes and sync'**
  String get menuRemotes;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Recovery and conflicts'**
  String get menuRecovery;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get menuTools;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get menuApplication;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get menuRebase;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get menuDiff;

  /// Native menu group label.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get menuActivity;

  /// Metadata-only diff explanation before generating a patch for large file content.
  ///
  /// In en, this message translates to:
  /// **'File exceeds the 8 MiB preview limit. Only file information is shown.'**
  String get diffLargeFileInformation;

  /// Size of the largest selected diff side, formatted such as 47 KB.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String diffFileSize(String size);

  /// File extension for metadata-only diff information.
  ///
  /// In en, this message translates to:
  /// **'File type: {extension}'**
  String diffFileType(String extension);

  /// File without an extension in diff information.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get diffFileTypeUnknown;

  /// Accessible label and title for the product About dialog.
  ///
  /// In en, this message translates to:
  /// **'About GitLama'**
  String get aboutApp;

  /// The installed version in About.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (build {build})'**
  String aboutVersion(String version, String build);

  /// Tooltip for the family signature.
  ///
  /// In en, this message translates to:
  /// **'GitLama · by Devmil Solutions'**
  String get brandTooltip;

  /// Maker attribution on welcome and About.
  ///
  /// In en, this message translates to:
  /// **'by Devmil Solutions'**
  String get brandMaker;

  /// About dialog family heading.
  ///
  /// In en, this message translates to:
  /// **'The Lama family'**
  String get lamaFamily;

  /// Repository welcome headline.
  ///
  /// In en, this message translates to:
  /// **'Open a repository.'**
  String get brandWelcome;

  /// Product names in the Lama family.
  ///
  /// In en, this message translates to:
  /// **'GitLama · ProcessLama · MailLama · ShotLama · NoteLama'**
  String get lamaFamilyNames;

  /// Command that opens a repository on another computer over SSH.
  ///
  /// In en, this message translates to:
  /// **'Open Remote Repository…'**
  String get openRemoteRepository;

  /// Disabled reason of a command for a repository on another computer.
  ///
  /// In en, this message translates to:
  /// **'Not available for repositories on another computer'**
  String get remoteCommandUnsupported;

  /// Disabled reason while a remote repository's host connection is down.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to the host to use this'**
  String get remoteCommandDisconnected;

  /// Disabled reason when the host did not offer a requested write capability.
  ///
  /// In en, this message translates to:
  /// **'The host does not accept this change. Check that its GitLama helper store is usable'**
  String get remoteCommandWritesUnavailable;

  /// Disabled reason when the host profile does not allow changes.
  ///
  /// In en, this message translates to:
  /// **'Turn on Allow changes on this host to use this'**
  String get remoteCommandWritesOff;

  /// Disabled reason when changes were allowed after the connection started.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to apply Allow changes on this host'**
  String get remoteCommandWritesReconnect;

  /// Disabled reason when the local pending-operations record is unreadable.
  ///
  /// In en, this message translates to:
  /// **'GitLama cannot read its record of remote changes on this computer, so changes are unavailable'**
  String get remoteCommandWritesLedger;

  /// Title of the dialog that manages host profiles for remote workspaces.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get remoteHosts;

  /// Introduction of the host dialog.
  ///
  /// In en, this message translates to:
  /// **'Connect to another computer through your own SSH configuration. GitLama never asks for passwords or private keys.'**
  String get remoteHostsIntro;

  /// Empty host list.
  ///
  /// In en, this message translates to:
  /// **'No hosts yet. Add a host with an alias from your SSH configuration.'**
  String get remoteHostsEmpty;

  /// Opens the form that adds a host profile.
  ///
  /// In en, this message translates to:
  /// **'Add host…'**
  String get remoteAddHost;

  /// Title of the form that adds a host profile.
  ///
  /// In en, this message translates to:
  /// **'Add host'**
  String get remoteAddHostTitle;

  /// Explains the add-host form when the command line named an SSH alias no host profile has.
  ///
  /// In en, this message translates to:
  /// **'GitLama was asked to open a repository on “{alias}”, which is not a saved host yet. Save it to connect, or cancel to open nothing.'**
  String remoteAddHostRequested(String alias);

  /// Edits the selected host profile.
  ///
  /// In en, this message translates to:
  /// **'Edit…'**
  String get remoteEditHost;

  /// Title of the form that edits a host profile.
  ///
  /// In en, this message translates to:
  /// **'Edit host'**
  String get remoteEditHostTitle;

  /// Deletes a host profile.
  ///
  /// In en, this message translates to:
  /// **'Delete host'**
  String get remoteDeleteHost;

  /// Confirmation title for deleting a host profile.
  ///
  /// In en, this message translates to:
  /// **'Delete host {host}?'**
  String remoteDeleteHostTitle(String host);

  /// Explains what deleting a host profile does.
  ///
  /// In en, this message translates to:
  /// **'This removes only the host profile on this computer. Nothing changes on the host, and open tabs and commit drafts stay.'**
  String get remoteDeleteHostDetail;

  /// Saves a host profile.
  ///
  /// In en, this message translates to:
  /// **'Save host'**
  String get remoteSaveHost;

  /// Field for a host profile's display name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get remoteHostLabel;

  /// Example name of a host profile.
  ///
  /// In en, this message translates to:
  /// **'Workstation'**
  String get remoteHostLabelPlaceholder;

  /// Field for the OpenSSH Host alias of a host profile.
  ///
  /// In en, this message translates to:
  /// **'SSH destination'**
  String get remoteHostAlias;

  /// Example SSH alias.
  ///
  /// In en, this message translates to:
  /// **'user@devbox'**
  String get remoteAliasExample;

  /// Help below the SSH alias field.
  ///
  /// In en, this message translates to:
  /// **'An SSH host alias, hostname or user@host. Uses your SSH configuration, keys and agent. The host must already be trusted; password prompts and sharing an existing SSH connection are not supported.'**
  String get remoteHostAliasHelp;

  /// Explains the host's tab appearance.
  ///
  /// In en, this message translates to:
  /// **'Tabs of this host show its icon in this color instead of its name.'**
  String get remoteHostAppearanceHelp;

  /// Label of the choice what GitLama may do on a host.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get remoteAccess;

  /// Access choice: GitLama only reads the host.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get remoteAccessReadOnly;

  /// Access choice: GitLama may change repositories on the host.
  ///
  /// In en, this message translates to:
  /// **'Allow changes'**
  String get remoteAccessChanges;

  /// Explains read-only access.
  ///
  /// In en, this message translates to:
  /// **'GitLama shows the repositories on this host and changes nothing.'**
  String get remoteAccessReadOnlyDetail;

  /// Explains allowed changes.
  ///
  /// In en, this message translates to:
  /// **'GitLama can stage, commit, discard, change branches and stashes, and fetch, pull and push with the host\'s own Git credentials. Changing this while connected reconnects the host.'**
  String get remoteAccessChangesDetail;

  /// Shown when changes are allowed for a host never connected.
  ///
  /// In en, this message translates to:
  /// **'Applies to the account GitLama verifies when it first connects.'**
  String get remoteAccessFirstConnection;

  /// Shown when the choice waits for the next connection.
  ///
  /// In en, this message translates to:
  /// **'Applies when this host connects again.'**
  String get remoteAccessNextConnection;

  /// Explains the SSH prerequisites of a host profile.
  ///
  /// In en, this message translates to:
  /// **'GitLama never asks for passwords or keys. The host key must already be trusted, and your key must be loaded in the SSH agent. Check that the alias works in a terminal first.'**
  String get remoteHostTrustHelp;

  /// Validation error of the host name field.
  ///
  /// In en, this message translates to:
  /// **'Enter a name of up to 128 characters without control characters.'**
  String get remoteLabelInvalid;

  /// Validation error of the SSH alias field.
  ///
  /// In en, this message translates to:
  /// **'Use a host or user@host, up to 128 ASCII characters. Each part starts with a letter or digit and uses letters, digits, dots, underscores or hyphens. Ports and options are not allowed.'**
  String get remoteAliasInvalid;

  /// Warning when the alias of a verified host profile changes.
  ///
  /// In en, this message translates to:
  /// **'Changing the alias removes the verified identity and the permission for staging and commits. The next connection verifies the host again.'**
  String get remoteAliasChangeWarning;

  /// A host profile change could not be saved.
  ///
  /// In en, this message translates to:
  /// **'The host could not be saved. Try again.'**
  String get remoteProfileSaveFailed;

  /// A host profile change failed because the settings file was locked.
  ///
  /// In en, this message translates to:
  /// **'The settings file was busy because another GitLama process was writing it at the same moment. Try again.'**
  String get remoteProfileSaveLocked;

  /// A host profile change failed while writing the settings file.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not write its settings file. Check that the disk has free space and that the settings folder is writable.'**
  String get remoteProfileSaveWriteFailed;

  /// A host profile change failed the settings consistency check.
  ///
  /// In en, this message translates to:
  /// **'The settings check rejected this change, so nothing was saved. This is a GitLama bug; please report it with the error code.'**
  String get remoteProfileSaveRejected;

  /// A host profile change referred to a missing host or invalid values.
  ///
  /// In en, this message translates to:
  /// **'The host was changed or removed in the meantime, or its values were not accepted. Close this dialog and try again.'**
  String get remoteProfileSaveStale;

  /// A host profile change failed because the remote workspace service had stopped.
  ///
  /// In en, this message translates to:
  /// **'Remote hosts are not available right now. Restart GitLama and try again.'**
  String get remoteProfileSaveUnavailable;

  /// A stable code identifying why a host profile change failed.
  ///
  /// In en, this message translates to:
  /// **'Error code: {code}'**
  String remoteProfileSaveCode(String code);

  /// Second line of a verified host in the host list.
  ///
  /// In en, this message translates to:
  /// **'{alias} · account {account}'**
  String remoteHostRowVerified(String alias, String account);

  /// Second line of a host that never connected.
  ///
  /// In en, this message translates to:
  /// **'{alias} · not verified yet'**
  String remoteHostRowUnverified(String alias);

  /// The account a host profile verified.
  ///
  /// In en, this message translates to:
  /// **'Verified account: {account}'**
  String remoteHostAccount(String account);

  /// Name of a host whose profile was deleted.
  ///
  /// In en, this message translates to:
  /// **'Remote host'**
  String get remoteHostUnknown;

  /// Placeholder for an account that was never verified.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get remoteHostUnknownAccount;

  /// Connects to a host.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get remoteConnect;

  /// Cancels a connection attempt in progress.
  ///
  /// In en, this message translates to:
  /// **'Cancel connection'**
  String get remoteCancelConnect;

  /// Closes the connection to a host.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get remoteDisconnect;

  /// Continues with choosing a folder on the connected host.
  ///
  /// In en, this message translates to:
  /// **'Choose folder…'**
  String get remoteChooseFolder;

  /// Why choosing a folder is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Connect to a host first'**
  String get remoteChooseFolderDisabled;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get remotePhaseIdle;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Connecting through SSH…'**
  String get remotePhaseConnecting;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Starting the GitLama helper…'**
  String get remotePhaseHandshaking;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get remotePhaseReady;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting…'**
  String get remotePhaseDisconnecting;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get remotePhaseDisconnected;

  /// Connection state of a host.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get remotePhaseFailed;

  /// Connection state of a host whose account or helper store changed.
  ///
  /// In en, this message translates to:
  /// **'Identity changed'**
  String get remotePhaseIdentityChanged;

  /// Title when a host's account or helper store changed.
  ///
  /// In en, this message translates to:
  /// **'This host reports a different identity'**
  String get remoteIdentityChangedTitle;

  /// Explains a changed host identity.
  ///
  /// In en, this message translates to:
  /// **'The host now reports account {observed} with a different helper store than the verified account {verified}. GitLama did not attach to it. Trust the new identity only if you expect this change; staging and commits are then turned off.'**
  String remoteIdentityChangedDetail(String observed, String verified);

  /// Accepts a host's changed identity.
  ///
  /// In en, this message translates to:
  /// **'Trust new identity'**
  String get remoteTrustIdentity;

  /// Label above the helper install path.
  ///
  /// In en, this message translates to:
  /// **'Expected helper location on the host:'**
  String get remoteHelperLocationLabel;

  /// Placeholder for the build identity in the helper install path.
  ///
  /// In en, this message translates to:
  /// **'<helper-id>'**
  String get remoteHelperBuildPlaceholder;

  /// Explains the exact helper install path of this build.
  ///
  /// In en, this message translates to:
  /// **'Install the helper package of this GitLama version at this location and make the file executable.'**
  String get remoteHelperExactLocationHelp;

  /// Explains the helper install path.
  ///
  /// In en, this message translates to:
  /// **'Replace <helper-id> with the helper ID of the helper package that belongs to this GitLama version, and make the file executable.'**
  String get remoteHelperLocationHelp;

  /// Connection state of a host while the helper is copied to it.
  ///
  /// In en, this message translates to:
  /// **'Installing the GitLama helper…'**
  String get remotePhaseInstalling;

  /// Button that installs the GitLama helper on a host.
  ///
  /// In en, this message translates to:
  /// **'Install helper'**
  String get remoteInstallHelper;

  /// Explains the install helper button.
  ///
  /// In en, this message translates to:
  /// **'GitLama can copy the helper of this version to the host over SSH and verify it there.'**
  String get remoteInstallHelperHelp;

  /// Title of the helper install confirmation.
  ///
  /// In en, this message translates to:
  /// **'Install the helper on {host}?'**
  String remoteInstallHelperTitle(String host);

  /// Explains what installing the helper does.
  ///
  /// In en, this message translates to:
  /// **'GitLama copies its helper over SSH alias {alias} into your home directory on the host, verifies its checksum and checks that it runs. Nothing outside this directory changes and no administrator rights are needed.'**
  String remoteInstallHelperDetail(String alias);

  /// Size of the helper to install, formatted such as 4.2 MB.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String remoteInstallHelperSize(String size);

  /// Checksum of the helper to install.
  ///
  /// In en, this message translates to:
  /// **'SHA-256: {digest}'**
  String remoteInstallHelperDigest(String digest);

  /// Settings category listing the remote host profiles.
  ///
  /// In en, this message translates to:
  /// **'Remote hosts'**
  String get settingsRemoteHosts;

  /// Description of the Remote hosts settings category.
  ///
  /// In en, this message translates to:
  /// **'Computers GitLama reaches through your SSH configuration, what it may do there and whether it keeps their helper current.'**
  String get settingsRemoteHostsDetail;

  /// Label of the remote helper compatibility version this GitLama needs.
  ///
  /// In en, this message translates to:
  /// **'Helper version'**
  String get remoteHelperVersion;

  /// Explains when hosts need a new helper.
  ///
  /// In en, this message translates to:
  /// **'Hosts keep their installed helper until a GitLama update needs a newer helper version.'**
  String get remoteHelperVersionDetail;

  /// Shown when the helper version of this build is unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get remoteHelperVersionUnknown;

  /// Switch that lets GitLama install its helper on a host without asking.
  ///
  /// In en, this message translates to:
  /// **'Install the helper automatically'**
  String get remoteAutoInstallHelper;

  /// Explains automatic helper installation.
  ///
  /// In en, this message translates to:
  /// **'When this host lacks the helper this GitLama version needs, GitLama copies it over SSH and verifies it without asking.'**
  String get remoteAutoInstallHelperDetail;

  /// Status bar: GitLama may only read on the host of the active tab.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get remoteAccessStatusReadOnly;

  /// Status bar: GitLama may change repositories on the host of the active tab.
  ///
  /// In en, this message translates to:
  /// **'Changes allowed'**
  String get remoteAccessStatusChanges;

  /// Tooltip of the status bar host menu.
  ///
  /// In en, this message translates to:
  /// **'What GitLama may do on {host}'**
  String remoteHostStatusTooltip(String host);

  /// Menu item that opens the host dialog.
  ///
  /// In en, this message translates to:
  /// **'Host settings…'**
  String get remoteHostSettings;

  /// Button that opens the host dialog to connect, disconnect or set up a host.
  ///
  /// In en, this message translates to:
  /// **'Connection…'**
  String get remoteManageConnection;

  /// Confirms the helper installation.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get remoteInstallHelperConfirm;

  /// Install failure.
  ///
  /// In en, this message translates to:
  /// **'This GitLama build cannot install the helper. Install it manually at the location below.'**
  String get remoteFailureInstallUnavailable;

  /// Install failure.
  ///
  /// In en, this message translates to:
  /// **'The helper directory on the host could not be created or is a symbolic link.'**
  String get remoteFailureInstallDirectory;

  /// Install failure.
  ///
  /// In en, this message translates to:
  /// **'The helper could not be written on the host. Check the free space in your home directory.'**
  String get remoteFailureInstallWrite;

  /// Install failure.
  ///
  /// In en, this message translates to:
  /// **'The helper arrived damaged on the host and was not installed. Try again.'**
  String get remoteFailureInstallDigest;

  /// Install failure.
  ///
  /// In en, this message translates to:
  /// **'The helper could not run on the host. The home directory may be mounted without permission to run programs.'**
  String get remoteFailureInstallExecute;

  /// Install failure.
  ///
  /// In en, this message translates to:
  /// **'The helper could not be installed. The host needs sha256sum or shasum and a standard POSIX shell.'**
  String get remoteFailureInstallFailed;

  /// A remote write whose outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not confirm whether the change was applied on the host. It may or may not have been applied. Review the repository before trying again.'**
  String get remoteFailureOutcomeUnknown;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'OpenSSH was not found on this computer. Install the OpenSSH client and try again.'**
  String get remoteFailureSshUnavailable;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The OpenSSH client on this computer is not supported. Install a current OpenSSH client.'**
  String get remoteFailureSshUnsupported;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'SSH could not connect. Check that ssh {alias} works in a terminal, that the host key is trusted and that your key is loaded in the SSH agent.'**
  String remoteFailureSshConnectionFailed(String alias);

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The GitLama helper for this version is not installed on the host.'**
  String get remoteFailureHelperNotInstalled;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The host\'s system is not supported. Remote workspaces need a Linux x86_64 host or a Mac.'**
  String get remoteFailureUnsupportedPlatform;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The GitLama helper could not be started on the host.'**
  String get remoteFailureBootstrapFailed;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The GitLama helper did not answer in time.'**
  String get remoteFailureHandshakeTimeout;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The helper on the host speaks a different protocol version. Install the helper that belongs to this GitLama version.'**
  String get remoteFailureProtocolMismatch;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The helper on the host belongs to a different helper version. Install the helper that belongs to this GitLama version.'**
  String get remoteFailureBuildMismatch;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'Git is not installed on the host.'**
  String get remoteFailureGitMissing;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The Git version on the host is too old. Remote workspaces need Git 2.39 or newer.'**
  String get remoteFailureGitUnsupported;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The helper could not use its private state folder on the host.'**
  String get remoteFailureStoreUnavailable;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The host now reports a different account or helper store.'**
  String get remoteFailureIdentityChanged;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'This repository belongs to a different account or helper store on the host.'**
  String get remoteFailureIdentityMismatch;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The helper sent an invalid reply, so the connection was closed.'**
  String get remoteFailureProtocolViolation;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The connection to the host was lost.'**
  String get remoteFailureDisconnected;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The host did not answer in time.'**
  String get remoteFailureTimedOut;

  /// Connection failure.
  ///
  /// In en, this message translates to:
  /// **'The connection attempt was canceled.'**
  String get remoteFailureCanceled;

  /// Capacity failure.
  ///
  /// In en, this message translates to:
  /// **'The limit of hosts or connections is reached.'**
  String get remoteFailureCapacity;

  /// Unsupported remote request.
  ///
  /// In en, this message translates to:
  /// **'This is not available for this host.'**
  String get remoteFailureUnsupported;

  /// Directory listing failure.
  ///
  /// In en, this message translates to:
  /// **'This folder does not exist on the host.'**
  String get remoteFailurePathNotFound;

  /// Directory listing failure.
  ///
  /// In en, this message translates to:
  /// **'The host account may not read this folder.'**
  String get remoteFailurePermissionDenied;

  /// Directory listing failure.
  ///
  /// In en, this message translates to:
  /// **'This is not a folder.'**
  String get remoteFailureNotDirectory;

  /// Directory listing failure.
  ///
  /// In en, this message translates to:
  /// **'The folder changed while it was being listed.'**
  String get remoteFailureDirectoryChanged;

  /// Directory listing failure.
  ///
  /// In en, this message translates to:
  /// **'The listing expired. Start it again to see more.'**
  String get remoteFailureCursorExpired;

  /// Remote write failure.
  ///
  /// In en, this message translates to:
  /// **'The change was prepared on an older state. Review it and try again.'**
  String get remoteFailurePreviewExpired;

  /// Remote write failure.
  ///
  /// In en, this message translates to:
  /// **'The repository changed on the host. Review it and try again.'**
  String get remoteFailurePreconditionFailed;

  /// Remote write failure.
  ///
  /// In en, this message translates to:
  /// **'The change could not be recorded, so nothing was applied.'**
  String get remoteFailureOperationIdConflict;

  /// Remote write failure.
  ///
  /// In en, this message translates to:
  /// **'Too many changes on this host still need review. Check them under Remote changes first.'**
  String get remoteFailureReceiptCapacity;

  /// Unexpected remote failure.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong with the host connection.'**
  String get remoteFailureInternal;

  /// Validation error of the remote path field.
  ///
  /// In en, this message translates to:
  /// **'Enter an absolute path that starts with /. ~ and relative paths are not supported.'**
  String get remotePathAbsoluteRequired;

  /// Validation error of the remote path field.
  ///
  /// In en, this message translates to:
  /// **'This path is too long or contains a character that is not allowed.'**
  String get remotePathInvalid;

  /// Title of the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder on {host}'**
  String remoteDirectoryTitle(String host);

  /// Goes to the parent folder in the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get remoteDirectoryUp;

  /// Goes to the home folder in the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'Home folder'**
  String get remoteDirectoryHome;

  /// Accessible name of the shown folder path.
  ///
  /// In en, this message translates to:
  /// **'Current folder'**
  String get remoteDirectoryCurrent;

  /// Remote folder picker loading state.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get remoteDirectoryLoading;

  /// Field for typing an absolute remote path.
  ///
  /// In en, this message translates to:
  /// **'Folder path'**
  String get remoteDirectoryPath;

  /// Example absolute remote path.
  ///
  /// In en, this message translates to:
  /// **'/home/me/project'**
  String get remoteDirectoryPathPlaceholder;

  /// Help below the remote path field.
  ///
  /// In en, this message translates to:
  /// **'Press Enter or Go to browse this path, or Open to open it.'**
  String get remoteDirectoryPathHelp;

  /// Shown while the typed remote path is being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking this path on the host…'**
  String get remotePathChecking;

  /// The typed remote path is an existing folder.
  ///
  /// In en, this message translates to:
  /// **'This folder exists on the host.'**
  String get remotePathFolder;

  /// The typed remote path names a file or another non-folder entry.
  ///
  /// In en, this message translates to:
  /// **'This path exists but is not a folder.'**
  String get remotePathNotFolder;

  /// The typed remote path does not exist on the host.
  ///
  /// In en, this message translates to:
  /// **'There is no folder at this path on the host.'**
  String get remotePathMissing;

  /// Shown when the typed path filters out every entry of the listed folder.
  ///
  /// In en, this message translates to:
  /// **'No entries start with the typed name.'**
  String get remoteDirectoryNoMatch;

  /// Browses the typed remote path.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get remoteDirectoryGo;

  /// Opens the chosen remote folder as a repository.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get remoteDirectoryOpen;

  /// Why opening is unavailable in the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'Wait for the folder to load'**
  String get remoteDirectoryOpenDisabled;

  /// Loads the next page of a remote folder.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get remoteDirectoryLoadMore;

  /// Notice for a truncated remote folder listing.
  ///
  /// In en, this message translates to:
  /// **'This folder has more entries than GitLama lists. Type a path to reach a folder that is not shown.'**
  String get remoteDirectoryTruncated;

  /// Empty remote folder.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty.'**
  String get remoteDirectoryEmpty;

  /// Remote folder picker without a listing.
  ///
  /// In en, this message translates to:
  /// **'No folder is shown.'**
  String get remoteDirectoryUnavailable;

  /// Lists a changed remote folder again.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get remoteDirectoryRefresh;

  /// Restarts an expired remote folder listing.
  ///
  /// In en, this message translates to:
  /// **'Restart listing'**
  String get remoteDirectoryRestart;

  /// A remote folder that looks like a Git repository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get remoteEntryRepository;

  /// A symbolic link in the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get remoteEntrySymlink;

  /// A file in the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get remoteEntryFile;

  /// A special entry in the remote folder picker.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get remoteEntryOther;

  /// Opening a repository exceeded the SSH connection session limit; explains how to retry.
  ///
  /// In en, this message translates to:
  /// **'This connection has reached its open repository limit. Close another repository tab on this host, then try again.'**
  String get remoteRepositoryCapacity;

  /// A remote repository failed to open.
  ///
  /// In en, this message translates to:
  /// **'The repository on the host could not be opened.'**
  String get remoteOpenFailed;

  /// A recent remote repository whose host profile was deleted or changed.
  ///
  /// In en, this message translates to:
  /// **'The host of this repository is no longer set up. Add it again under Open Remote Repository.'**
  String get remoteRecentHostMissing;

  /// Second line of a recent remote repository.
  ///
  /// In en, this message translates to:
  /// **'{host} · {path}'**
  String remoteRecentSubtitle(String host, String path);

  /// Reconnects a host and reopens its tabs.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get remoteReconnect;

  /// Opens the host dialog to decide about a changed identity.
  ///
  /// In en, this message translates to:
  /// **'Review host…'**
  String get remoteReviewHost;

  /// Banner title while waiting for the next automatic reconnection.
  ///
  /// In en, this message translates to:
  /// **'Connection to {host} lost. Reconnecting in {seconds} s…'**
  String remoteReconnectIn(String host, int seconds);

  /// Banner title while an automatic reconnection runs.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to {host}…'**
  String remoteReconnecting(String host);

  /// Banner title after automatic reconnection ended without success.
  ///
  /// In en, this message translates to:
  /// **'Could not reconnect to {host}'**
  String remoteReconnectGaveUp(String host);

  /// Banner title when automatic reconnection was stopped or needs the user.
  ///
  /// In en, this message translates to:
  /// **'Not reconnecting to {host}'**
  String remoteReconnectStopped(String host);

  /// Detail of a disconnected remote tab.
  ///
  /// In en, this message translates to:
  /// **'Showing the last received state.'**
  String get remoteReconnectStale;

  /// Starts the next reconnection at once.
  ///
  /// In en, this message translates to:
  /// **'Reconnect now'**
  String get remoteReconnectNow;

  /// Ends automatic reconnection.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get remoteReconnectStop;

  /// Reconnects after automatic reconnection ended.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get remoteReconnectTryAgain;

  /// Notification after a lost connection was restored.
  ///
  /// In en, this message translates to:
  /// **'Reconnected to {host}'**
  String remoteReconnected(String host);

  /// Persistent notice of a disconnected remote tab.
  ///
  /// In en, this message translates to:
  /// **'Disconnected from {host} — showing the last received state.'**
  String remoteStaleBanner(String host);

  /// Badge naming the host a repository lives on.
  ///
  /// In en, this message translates to:
  /// **'On {host}'**
  String remoteHostBadge(String host);

  /// Badge of a host whose connection is down.
  ///
  /// In en, this message translates to:
  /// **'On {host}, disconnected'**
  String remoteHostBadgeDisconnected(String host);

  /// Title of a remote tab that could not open.
  ///
  /// In en, this message translates to:
  /// **'Not connected to {host}'**
  String remoteTabDisconnectedTitle(String host);

  /// Explains a remote tab that is not connected.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to open this repository again.'**
  String get remoteTabDisconnectedDetail;

  /// Explains a remote tab whose host profile is gone.
  ///
  /// In en, this message translates to:
  /// **'The host profile of this repository was deleted. Close the tab, or add the host again and open the repository.'**
  String get remoteTabHostDeletedDetail;

  /// Title of a remote tab whose host identity changed.
  ///
  /// In en, this message translates to:
  /// **'{host} reports a different identity'**
  String remoteTabIdentityChangedTitle(String host);

  /// Title of a remote tab whose repository no longer matches the one it opened, on a host that still matches.
  ///
  /// In en, this message translates to:
  /// **'The repository on {host} changed'**
  String remoteTabRepositoryChangedTitle(String host);

  /// Explains a remote tab whose repository no longer matches the one it opened.
  ///
  /// In en, this message translates to:
  /// **'This folder no longer holds the repository GitLama opened here; it may have been replaced, moved or restored. Open it again only if you expect this repository at this path.'**
  String get remoteTabRepositoryChangedDetail;

  /// Trusts the repository now at a remote tab's path and opens it again.
  ///
  /// In en, this message translates to:
  /// **'Trust and open'**
  String get remoteTabTrustRepository;

  /// Explains a remote tab whose host identity changed.
  ///
  /// In en, this message translates to:
  /// **'The host\'s account, helper store or repository no longer matches what GitLama verified. Review the host and decide whether to trust it.'**
  String get remoteTabIdentityChangedDetail;

  /// Title of the list of recorded remote staging and commits.
  ///
  /// In en, this message translates to:
  /// **'Remote changes'**
  String get remoteOperationsTitle;

  /// Remote changes dialog: what the list shows.
  ///
  /// In en, this message translates to:
  /// **'Changes GitLama made on your hosts, newest first.'**
  String get remoteOperationsDescription;

  /// Status bar entry for remote writes that need review.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 remote change to review} other{{count} remote changes to review}}'**
  String remoteOperationsIndicator(int count);

  /// Explains remote writes with an unknown outcome.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not confirm the outcome of some changes. They may or may not have been applied. Review the repository before trying again; GitLama never repeats them on its own.'**
  String get remoteOperationsUncertain;

  /// The local record of remote writes is unreadable.
  ///
  /// In en, this message translates to:
  /// **'The record of remote changes on this computer cannot be read. Staging and commits on hosts stay off until it can.'**
  String get remoteOperationsLedgerUnavailable;

  /// Empty list of remote writes.
  ///
  /// In en, this message translates to:
  /// **'No remote changes recorded.'**
  String get remoteOperationsEmpty;

  /// Second line of a remote write.
  ///
  /// In en, this message translates to:
  /// **'{host} · {family} · {state}'**
  String remoteOperationSubtitle(String host, String family, String state);

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Staging'**
  String get remoteOperationStage;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get remoteOperationCommit;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Branches and tags'**
  String get remoteOperationRefs;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get remoteOperationStash;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get remoteOperationDiscard;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Merge, cherry-pick or revert'**
  String get remoteOperationHistory;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get remoteOperationRebase;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Restack'**
  String get remoteOperationRestack;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Bisect'**
  String get remoteOperationBisect;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Conflict resolution'**
  String get remoteOperationConflict;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Continue or abort'**
  String get remoteOperationSequencer;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Snapshot'**
  String get remoteOperationSnapshot;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Snapshot restore'**
  String get remoteOperationSnapshotRestore;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'File restore'**
  String get remoteOperationRestore;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Removing Git\'s lock file'**
  String get remoteOperationIndexLock;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Patch'**
  String get remoteOperationPatch;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Worktrees, submodules and LFS'**
  String get remoteOperationExtension;

  /// Family of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Fetch, pull or push'**
  String get remoteOperationTransfer;

  /// State of a remote write.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get remoteOperationRunning;

  /// State of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get remoteOperationSucceeded;

  /// State of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get remoteOperationFailed;

  /// State of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Not applied'**
  String get remoteOperationNotApplied;

  /// State of a remote write whose target state was observed.
  ///
  /// In en, this message translates to:
  /// **'Already in the requested state'**
  String get remoteOperationDesiredState;

  /// State of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Partly applied'**
  String get remoteOperationPartial;

  /// State of a remote write.
  ///
  /// In en, this message translates to:
  /// **'Outcome unknown'**
  String get remoteOperationUnknown;

  /// Asks the host to look up a remote write again without repeating it.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get remoteOperationCheckAgain;

  /// Why checking a remote write is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Connect to the host to check again'**
  String get remoteOperationCheckDisconnected;

  /// Checking remote writes failed.
  ///
  /// In en, this message translates to:
  /// **'The host could not be asked. Try again later.'**
  String get remoteOperationCheckFailed;

  /// Removes a resolved remote write from the list.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get remoteOperationDismiss;

  /// Dismissing a remote write failed.
  ///
  /// In en, this message translates to:
  /// **'The entry could not be removed.'**
  String get remoteOperationDismissFailed;

  /// Label of a tab whose repository lives on another computer.
  ///
  /// In en, this message translates to:
  /// **'{repository} · {host}'**
  String remoteTabLabel(String repository, String host);

  /// Title of a remote commit whose outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'Outcome unknown'**
  String get remoteOutcomeUnknownTitle;

  /// A remote commit whose outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'The commit was sent to the host, but GitLama could not confirm whether it was created. It may or may not have been applied. Your message is kept. Review the history before trying again.'**
  String get remoteOutcomeUnknownCommit;

  /// A remote staging change whose outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'The staging change was sent to the host, but GitLama could not confirm whether it was applied. It may or may not have been applied. Review the changes before trying again.'**
  String get remoteOutcomeUnknownStage;

  /// A remote branch, stash or transfer change whose outcome is unknown.
  ///
  /// In en, this message translates to:
  /// **'The change was sent to the host, but GitLama could not confirm whether it was applied. Review it under Remote changes before trying again.'**
  String get remoteOutcomeUnknownChange;

  /// A remote transfer failed authentication on the host; credentials are never entered locally for it.
  ///
  /// In en, this message translates to:
  /// **'The host could not sign in to the Git server. Set up credentials for this repository on the host, then try again.'**
  String get remoteTransferAuthentication;

  /// A remote transfer failed because the host does not trust the server's SSH key.
  ///
  /// In en, this message translates to:
  /// **'The host does not trust the Git server\'s key yet. Connect to the server once from a terminal on the host, then try again.'**
  String get remoteTransferHostKey;

  /// Accessible name of the inspector's location bar.
  ///
  /// In en, this message translates to:
  /// **'Inspector location'**
  String get inspectorLocation;

  /// Inspector Back button.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get inspectorBack;

  /// Inspector Forward button.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get inspectorForward;

  /// Lens showing a file's changes.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get inspectorLensDiff;

  /// Lens showing a file's content at a commit.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get inspectorLensContents;

  /// Lens showing the commits that changed a path.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get inspectorLensHistory;

  /// Accessible name of the lens switch.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get inspectorLenses;

  /// Accessible name of the Changed / All files switch.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get inspectorScope;

  /// Scope listing the complete tree at a commit.
  ///
  /// In en, this message translates to:
  /// **'All files'**
  String get inspectorScopeAll;

  /// Why All files is disabled.
  ///
  /// In en, this message translates to:
  /// **'Not available for comparisons'**
  String get inspectorScopeAllUnavailable;

  /// Opens the current location or file in an inspector window.
  ///
  /// In en, this message translates to:
  /// **'Open in new window'**
  String get inspectorOpenInWindow;

  /// Hides the history graph so the inspector fills the column.
  ///
  /// In en, this message translates to:
  /// **'Maximize inspector'**
  String get inspectorMaximize;

  /// Shows the history graph again.
  ///
  /// In en, this message translates to:
  /// **'Restore layout'**
  String get inspectorRestoreLayout;

  /// Shows the inspector file list.
  ///
  /// In en, this message translates to:
  /// **'Show files'**
  String get inspectorShowFiles;

  /// Hides the inspector file list.
  ///
  /// In en, this message translates to:
  /// **'Hide files'**
  String get inspectorHideFiles;

  /// Switches the file list to all files.
  ///
  /// In en, this message translates to:
  /// **'Browse all files'**
  String get inspectorBrowseAllFiles;

  /// Inspector overflow menu.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get inspectorMoreActions;

  /// Selects the commit in the history graph.
  ///
  /// In en, this message translates to:
  /// **'Show in graph'**
  String get inspectorShowInGraph;

  /// Reveals the commit in the main GitLama window.
  ///
  /// In en, this message translates to:
  /// **'Show in main window'**
  String get inspectorShowInMainWindow;

  /// Why Show in main window is disabled.
  ///
  /// In en, this message translates to:
  /// **'Repository is not open in GitLama'**
  String get inspectorRepositoryNotOpen;

  /// Opens a commit in the inspector.
  ///
  /// In en, this message translates to:
  /// **'Show commit'**
  String get inspectorShowCommit;

  /// Opens the blame of a file at a history entry.
  ///
  /// In en, this message translates to:
  /// **'Blame at this commit'**
  String get inspectorBlameAtCommit;

  /// Opens the blame at the parent of a line's commit.
  ///
  /// In en, this message translates to:
  /// **'Blame before this change'**
  String get inspectorBlameBefore;

  /// History of the selected lines.
  ///
  /// In en, this message translates to:
  /// **'Line history'**
  String get inspectorLineHistory;

  /// Chip naming the line range of a history.
  ///
  /// In en, this message translates to:
  /// **'Lines {first}–{last}'**
  String inspectorLines(int first, int last);

  /// Removes the line range of a history.
  ///
  /// In en, this message translates to:
  /// **'Show whole file history'**
  String get inspectorClearLines;

  /// Why the Diff lens is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Not changed in this commit'**
  String get inspectorNotChanged;

  /// Why Contents and Blame are unavailable.
  ///
  /// In en, this message translates to:
  /// **'Deleted in this commit'**
  String get inspectorDeletedHere;

  /// Why Blame is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Blame needs a text file'**
  String get inspectorBlameNeedsText;

  /// Why Contents is unavailable for a submodule.
  ///
  /// In en, this message translates to:
  /// **'Submodules have no contents here'**
  String get inspectorSubmoduleNoContents;

  /// Why a lens is unavailable for a folder.
  ///
  /// In en, this message translates to:
  /// **'Folders only have a history'**
  String get inspectorFolderOnlyHistory;

  /// Empty path history.
  ///
  /// In en, this message translates to:
  /// **'No commits changed this path.'**
  String get inspectorNoHistory;

  /// Loads the next history page.
  ///
  /// In en, this message translates to:
  /// **'Load older history'**
  String get inspectorLoadOlder;

  /// Loads more entries of a folder.
  ///
  /// In en, this message translates to:
  /// **'Load more files'**
  String get inspectorLoadMoreFiles;

  /// A target is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading {commit}…'**
  String inspectorLoading(String commit);

  /// Generic lens load failure.
  ///
  /// In en, this message translates to:
  /// **'This could not be loaded.'**
  String get inspectorLoadFailed;

  /// A target object is missing.
  ///
  /// In en, this message translates to:
  /// **'This commit is not available in the repository.'**
  String get inspectorMissingObject;

  /// The window's repository session ended.
  ///
  /// In en, this message translates to:
  /// **'The repository was closed.'**
  String get inspectorRepositoryClosed;

  /// An inspector window of a repository on a remote host could not open it because the main window has no connection to the host.
  ///
  /// In en, this message translates to:
  /// **'The host is not connected.'**
  String get inspectorRemoteHostNotConnected;

  /// What to do when an inspector window's remote host is not connected.
  ///
  /// In en, this message translates to:
  /// **'Connect to it in the main window, then try again.'**
  String get inspectorRemoteHostNotConnectedDetail;

  /// Announcement after a navigation.
  ///
  /// In en, this message translates to:
  /// **'Showing {label}'**
  String inspectorShowing(String label);

  /// Accessible name of the history list.
  ///
  /// In en, this message translates to:
  /// **'History of {path}'**
  String inspectorHistoryOf(String path);

  /// Folder history entry file count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 changed file in this folder} other{{count} changed files in this folder}}'**
  String inspectorChangedFilesIn(int count);

  /// File action.
  ///
  /// In en, this message translates to:
  /// **'Show diff'**
  String get fileActionShowDiff;

  /// File action.
  ///
  /// In en, this message translates to:
  /// **'Show contents'**
  String get fileActionShowContents;

  /// File action.
  ///
  /// In en, this message translates to:
  /// **'File history'**
  String get fileActionFileHistory;

  /// Folder action.
  ///
  /// In en, this message translates to:
  /// **'Folder history'**
  String get fileActionFolderHistory;

  /// File action.
  ///
  /// In en, this message translates to:
  /// **'Open in external diff tool'**
  String get fileActionExternalDiff;

  /// Copies a full commit id.
  ///
  /// In en, this message translates to:
  /// **'Copy commit hash'**
  String get fileActionCopyCommitHash;

  /// Why an inspection action is unavailable.
  ///
  /// In en, this message translates to:
  /// **'No commit yet'**
  String get fileActionNoCommit;

  /// An inspection action at the current commit.
  ///
  /// In en, this message translates to:
  /// **'{action} (HEAD)'**
  String fileActionHeadSuffix(String action);

  /// Setting for where Blame, Contents and History open.
  ///
  /// In en, this message translates to:
  /// **'Open file inspection in'**
  String get settingsInspectionOpenIn;

  /// Explains the inspection setting.
  ///
  /// In en, this message translates to:
  /// **'Choose where Blame, Contents and History open. Hold ⌘ or Ctrl to use the other place once.'**
  String get settingsInspectionOpenInDetail;

  /// Settings label for whether History also shows commits only references outside branches, remote branches, tags and the stash reach.
  ///
  /// In en, this message translates to:
  /// **'Show other refs in History'**
  String get settingsHistoryOtherRefs;

  /// Explains the setting for showing other refs in History.
  ///
  /// In en, this message translates to:
  /// **'History follows branches, remote branches, tags and the stash. Turn this on to also show commits only other refs reach, such as notes or tool checkpoints. The History toolbar changes the same setting.'**
  String get settingsHistoryOtherRefsDetail;

  /// Inspection opens in the Detail pane.
  ///
  /// In en, this message translates to:
  /// **'Detail pane'**
  String get settingsInspectionOpenInPane;

  /// Inspection opens in a new window.
  ///
  /// In en, this message translates to:
  /// **'New window'**
  String get settingsInspectionOpenInWindow;

  /// State of a collapsed folder row.
  ///
  /// In en, this message translates to:
  /// **'Collapsed'**
  String get gitFolderCollapsed;

  /// State of an expanded folder row.
  ///
  /// In en, this message translates to:
  /// **'Expanded'**
  String get gitFolderExpanded;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Inspector back'**
  String get commandInspectorBack;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Inspector forward'**
  String get commandInspectorForward;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Show diff of the file'**
  String get commandInspectorLensDiff;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Show contents of the file'**
  String get commandInspectorLensContents;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Show blame of the file'**
  String get commandInspectorLensBlame;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Show history of the file'**
  String get commandInspectorLensHistory;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Open inspector in new window'**
  String get commandInspectorOpenInWindow;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Maximize or restore inspector'**
  String get commandInspectorToggleMaximize;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Show or hide inspector files'**
  String get commandInspectorToggleFiles;

  /// Command name.
  ///
  /// In en, this message translates to:
  /// **'Browse all files of the commit'**
  String get commandInspectorAllFiles;

  /// An empty commit tree.
  ///
  /// In en, this message translates to:
  /// **'This commit has no files.'**
  String get inspectorNoFiles;

  /// Choice of the computer a new repository is created on: this computer or a remote host.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get initializeLocation;

  /// Location choice for a repository on the computer running GitLama.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get initializeLocationThisComputer;

  /// Description of the Initialize repository dialog for a host.
  ///
  /// In en, this message translates to:
  /// **'Create an empty Git repository on the host. In the next step, you choose a folder there or type the path of a new one.'**
  String get initializeRemoteDestinationHint;

  /// Title of the remote folder picker when initializing a repository.
  ///
  /// In en, this message translates to:
  /// **'Choose where to create the repository on {host}'**
  String remoteInitializeDirectoryTitle(String host);

  /// Help below the remote path field when initializing a repository.
  ///
  /// In en, this message translates to:
  /// **'Browse to an empty folder, or type the path of a new folder. Missing folders are created.'**
  String get remoteInitializePathHelp;

  /// The typed remote path does not exist yet and will be created by initialization.
  ///
  /// In en, this message translates to:
  /// **'A new folder will be created at this path.'**
  String get remoteInitializePathNew;

  /// Creates the repository in the chosen remote folder.
  ///
  /// In en, this message translates to:
  /// **'Initialize here'**
  String get remoteInitializeHere;

  /// A change whose result Git could not confirm; the user must inspect the repository before retrying.
  ///
  /// In en, this message translates to:
  /// **'Git may have changed the repository, but GitLama could not confirm the result. Inspect the repository before trying again.'**
  String get mutationOutcomeUncertain;

  /// Placeholder in the optional stash name field.
  ///
  /// In en, this message translates to:
  /// **'What are you working on?'**
  String get stashMessagePlaceholder;

  /// Explains what creating a stash does.
  ///
  /// In en, this message translates to:
  /// **'Set changes aside for a clean working tree. You can bring them back at any time.'**
  String get stashPushIntro;

  /// Create stash scope: every change, with the file count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{All changes (1 file)} other{All changes ({count} files)}}'**
  String stashScopeAll(int count);

  /// Create stash scope: only files picked in the list.
  ///
  /// In en, this message translates to:
  /// **'Only selected files'**
  String get stashScopeSelected;

  /// Explains the include-new-files stash option.
  ///
  /// In en, this message translates to:
  /// **'Also stash files that Git doesn\'t track yet.'**
  String get stashIncludeUntrackedHelp;

  /// Explains the keep-staged-changes stash option.
  ///
  /// In en, this message translates to:
  /// **'Staged changes go into the stash and also stay staged.'**
  String get stashKeepIndexHelp;

  /// How many files of the partial stash list are selected.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {count} selected'**
  String stashSelectionCount(int selected, int count);

  /// Selects every file in the partial stash list.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get stashSelectAll;

  /// Clears the partial stash file selection.
  ///
  /// In en, this message translates to:
  /// **'Select none'**
  String get stashSelectNone;

  /// Why Create stash is disabled with no file selected.
  ///
  /// In en, this message translates to:
  /// **'Select at least one file.'**
  String get stashSelectFilesReason;

  /// Untracked files cannot join a partial stash.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new file can only be stashed with all changes.} other{{count} new files can only be stashed with all changes.}}'**
  String stashSelectedUntrackedNote(int count);

  /// Stash review fact label: affected files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get stashPreviewFiles;

  /// Stash review fact value: number of affected files.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String stashPreviewFileCount(int count);

  /// Stash review fact label: untracked files.
  ///
  /// In en, this message translates to:
  /// **'New files'**
  String get stashPreviewNewFiles;

  /// Stash review fact value: untracked files are included.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get stashPreviewIncluded;

  /// Stash review fact label: staged changes.
  ///
  /// In en, this message translates to:
  /// **'Staged changes'**
  String get stashPreviewStaged;

  /// Stash review fact value: staged changes stay staged.
  ///
  /// In en, this message translates to:
  /// **'Stay staged'**
  String get stashPreviewStillStaged;

  /// Restack review: what happens to the listed branches.
  ///
  /// In en, this message translates to:
  /// **'Each branch moves onto the latest commit of the branch it builds on, in the order shown.'**
  String get restackPreviewSummary;

  /// Restack step: the branch a listed branch moves onto.
  ///
  /// In en, this message translates to:
  /// **'onto {branch}'**
  String restackStepOnto(String branch);

  /// Explains what cherry-picking the selected commits does.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copies the selected commit onto the current branch as a new commit.} other{Copies the {count} selected commits onto the current branch as new commits.}}'**
  String historyCherryPickIntro(int count);

  /// Explains what reverting the selected commits does.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Adds a new commit that undoes the selected commit. The original stays in the history.} other{Adds new commits that undo the {count} selected commits. The originals stay in the history.}}'**
  String historyRevertIntro(int count);

  /// Explains reverting without committing.
  ///
  /// In en, this message translates to:
  /// **'Undoes the selected commit\'s changes and stages them for you to review. No commit is created.'**
  String get historyRevertApplyIntro;

  /// Revert dialog: points to the apply-without-committing action.
  ///
  /// In en, this message translates to:
  /// **'To review the changes first, apply them without committing.'**
  String get historyRevertApplyHint;

  /// Merge review title.
  ///
  /// In en, this message translates to:
  /// **'Review merge'**
  String get historyMergePreviewTitle;

  /// Cherry-pick review title.
  ///
  /// In en, this message translates to:
  /// **'Review cherry-pick'**
  String get historyCherryPickPreviewTitle;

  /// Revert review title.
  ///
  /// In en, this message translates to:
  /// **'Review revert'**
  String get historyRevertPreviewTitle;

  /// History operation review fact label: the branch that changes.
  ///
  /// In en, this message translates to:
  /// **'Current branch'**
  String get historyPreviewCurrentBranch;

  /// Review fact label: the conflict check result.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get historyPreviewConflicts;

  /// Conflict check result: no conflicts expected.
  ///
  /// In en, this message translates to:
  /// **'None expected'**
  String get conflictCheckNone;

  /// Conflict check result: number of files that will likely conflict.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Likely in 1 file} other{Likely in {count} files}}'**
  String conflictCheckFiles(int count);

  /// Conflict check result: the check failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t be checked'**
  String get conflictCheckUnavailable;

  /// Caveat under a conflict check result.
  ///
  /// In en, this message translates to:
  /// **'The conflict check is an estimate.'**
  String get conflictCheckEstimate;

  /// Caveat under an incomplete conflict check result.
  ///
  /// In en, this message translates to:
  /// **'The conflict check is an estimate and didn\'t cover every commit.'**
  String get conflictCheckPartial;

  /// Interactive rebase editor: the branch being edited and its new base.
  ///
  /// In en, this message translates to:
  /// **'Choose what happens to each commit of {branch}. They are replayed from top to bottom onto {onto}.'**
  String rebaseEditorSummary(String branch, String onto);

  /// Interactive rebase editor: the conflict check expects conflicts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file will likely conflict. You can resolve it during the rebase.} other{{count} files will likely conflict. You can resolve them during the rebase.}}'**
  String rebaseConflictsExpected(int count);

  /// Explains the published-history acknowledgement in the rebase editor.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 commit in this plan is already published. Others may need to update their copies.} other{{count} commits in this plan are already published. Others may need to update their copies.}}'**
  String rebasePublishedNote(int count);

  /// Rebase review step: the commit a squash or fixup joins.
  ///
  /// In en, this message translates to:
  /// **'combined with {subject}'**
  String rebaseStepCombinedWith(String subject);

  /// Rebase review step: a squash or fixup joins the previous commit.
  ///
  /// In en, this message translates to:
  /// **'combined with the commit above'**
  String get rebaseStepCombinedAbove;

  /// Rebase review step: the replacement message of a reworded commit.
  ///
  /// In en, this message translates to:
  /// **'new message: {message}'**
  String rebaseStepNewMessage(String message);

  /// Snapshot restore: what restoring does.
  ///
  /// In en, this message translates to:
  /// **'Your current changes, staged and unstaged, are replaced with the ones saved in this snapshot.'**
  String get namedSnapshotRestoreSummary;

  /// Snapshot restore: header of the list of files that change.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file changes} other{{count} files change}}'**
  String namedSnapshotRestoreFileCount(int count);

  /// Caption in the snapshot restore review: where the replaced changes go.
  ///
  /// In en, this message translates to:
  /// **'Your current changes are saved as a stash first, so you find them under Stashes.'**
  String get namedSnapshotRestoreStash;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'The operation failed'**
  String get operationFailureTitle;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy support report'**
  String get operationCopyReport;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Support report copied. It contains no repository contents, paths or credentials.'**
  String get operationReportCopied;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error stopped the operation. Copy the support report from this message or the Logbook.'**
  String get operationUnexpectedFailure;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'{operation} {reason}'**
  String operationFailureWithReason(String operation, String reason);

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'The request exceeded a supported limit.'**
  String get operationFailureLimit;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Git did not finish within the time limit.'**
  String get operationFailureTimeout;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'A required Git object is missing.'**
  String get operationFailureMissingObject;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'The selected changes are no longer available or the request could not be validated.'**
  String get operationFailureInvalidRequest;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'The repository is busy. Try again after the current operation finishes.'**
  String get operationFailureBusy;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not read the required repository state.'**
  String get operationFailureRead;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Another Git operation is using the index, or its lock file was left behind. Check the lock before trying again.'**
  String get stagingFailureIndexLocked;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not read the current list of changes.'**
  String get stagingFailureStatusRead;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not read a valid Git index. Check access to the repository.'**
  String get stagingFailureIndexRead;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not read a selected file to validate the change.'**
  String get stagingFailureContentRead;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not write or install the updated Git index. Check permissions and available disk space.'**
  String get stagingFailureIndexWrite;

  /// User-initiated operation failure and privacy-safe support diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Git rejected the staging change. Copy the support report for the failure code and command exit status.'**
  String get stagingFailureGit;

  /// Explains a canceled repository workflow.
  ///
  /// In en, this message translates to:
  /// **'The operation was canceled before it completed.'**
  String get operationFailureCanceled;

  /// Transfer failed because a Git lock file was held.
  ///
  /// In en, this message translates to:
  /// **'Another Git process was working in this repository, so Git could not lock it.'**
  String get transferFailureLocked;

  /// Disclosure title for the command line and output of the failed Git command.
  ///
  /// In en, this message translates to:
  /// **'Git output'**
  String get operationGitOutput;

  /// Option to append the failed command's output to the copied support report.
  ///
  /// In en, this message translates to:
  /// **'Include Git output in the report'**
  String get operationReportIncludeOutput;

  /// Privacy note under the include-output option.
  ///
  /// In en, this message translates to:
  /// **'It can contain paths and branch or remote names. Check it before you send it.'**
  String get operationReportIncludeOutputDetail;

  /// Heading before the Git output in a copied support report.
  ///
  /// In en, this message translates to:
  /// **'Git output:'**
  String get operationReportGitOutputHeading;

  /// Status message after copying a report that includes Git output.
  ///
  /// In en, this message translates to:
  /// **'Support report copied with Git output. Check it before you send it.'**
  String get operationReportCopiedWithOutput;

  /// Title of the dialog shown when Git found another process's lock file.
  ///
  /// In en, this message translates to:
  /// **'The repository is locked'**
  String get repositoryLockTitle;

  /// Explains Git lock files in the locked-repository dialog.
  ///
  /// In en, this message translates to:
  /// **'Git keeps a lock file while it changes the repository. Another program, such as your editor, a terminal or a background fetch, may still be working, or a Git process stopped without removing its lock.'**
  String get repositoryLockExplanation;

  /// Heading of the list of Git lock files.
  ///
  /// In en, this message translates to:
  /// **'Lock files'**
  String get repositoryLockListTitle;

  /// Shown while GitLama lists the lock files.
  ///
  /// In en, this message translates to:
  /// **'Checking lock files…'**
  String get repositoryLockChecking;

  /// No lock file was found after the failure.
  ///
  /// In en, this message translates to:
  /// **'No lock files remain. The other Git process has finished, so you can try again.'**
  String get repositoryLockNone;

  /// At least one lock is less than a minute old.
  ///
  /// In en, this message translates to:
  /// **'A lock was created moments ago. Another Git program is probably still working: wait for it to finish, then try again.'**
  String get repositoryLockRecent;

  /// All locks are at least five minutes old.
  ///
  /// In en, this message translates to:
  /// **'These locks are several minutes old. If no other Git program is working in this repository, they were left behind and can be removed.'**
  String get repositoryLockStale;

  /// The lock list stopped at its limit.
  ///
  /// In en, this message translates to:
  /// **'There are more lock files than shown.'**
  String get repositoryLockTruncated;

  /// Lock inspection failed.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not check the lock files.'**
  String get repositoryLockInspectFailed;

  /// Remote repositories: locks are listed but not removed from this computer.
  ///
  /// In en, this message translates to:
  /// **'Lock files on another computer can only be removed there.'**
  String get repositoryLockRemoteOnly;

  /// Warning before removing Git lock files.
  ///
  /// In en, this message translates to:
  /// **'Remove locks only when no other Git program is working in this repository. Removing a lock that is still in use can damage the repository.'**
  String get repositoryLockRemoveWarning;

  /// Lists the lock files again.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get repositoryLockCheckAgain;

  /// Runs the failed operation again.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get repositoryLockRetry;

  /// Removes the listed lock files, then runs the failed operation again.
  ///
  /// In en, this message translates to:
  /// **'Remove locks and try again'**
  String get repositoryLockRemoveAndRetry;

  /// A lock changed between listing and removal.
  ///
  /// In en, this message translates to:
  /// **'A lock file changed after it was listed. Check again before you remove it.'**
  String get repositoryLockChanged;

  /// Removal refused while GitLama runs a repository operation.
  ///
  /// In en, this message translates to:
  /// **'GitLama is still working in this repository. Wait for it to finish, then try again.'**
  String get repositoryLockBusy;

  /// Removing a lock failed.
  ///
  /// In en, this message translates to:
  /// **'A lock file could not be removed. Check its permissions.'**
  String get repositoryLockRemoveFailed;

  /// A lock whose modification time is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Age unknown'**
  String get repositoryLockAgeUnknown;

  /// Age of a lock file in seconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second ago} other{{count} seconds ago}}'**
  String repositoryLockAgeSeconds(int count);

  /// Age of a lock file in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String repositoryLockAgeMinutes(int count);

  /// Age of a lock file in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String repositoryLockAgeHours(int count);

  /// Age of a lock file in days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String repositoryLockAgeDays(int count);

  /// Fetch option: prune remote-tracking branches.
  ///
  /// In en, this message translates to:
  /// **'Remove remote branches deleted on the server'**
  String get transferPrune;

  /// Help for the prune fetch option.
  ///
  /// In en, this message translates to:
  /// **'Keeps the remote branch list in step with the server (git fetch --prune).'**
  String get transferPruneHelp;

  /// Remedy: run the fetch again without --prune.
  ///
  /// In en, this message translates to:
  /// **'Fetch without pruning'**
  String get failureFetchWithoutPrune;

  /// Title when refs differing only in case collide.
  ///
  /// In en, this message translates to:
  /// **'Branch names differ only in letter case'**
  String get failureCaseCollisionTitle;

  /// Explains the case-collision repair.
  ///
  /// In en, this message translates to:
  /// **'Repairing removes this computer\'s copies of these remote branches and fetches again, which recreates them as the remote has them. Your own branches and the remote are not changed. To stop this for everyone, have one of the branches deleted or renamed on the server.'**
  String get failureCaseCollisionRepair;

  /// Case collision that cannot be repaired from this computer.
  ///
  /// In en, this message translates to:
  /// **'Have one of the branches deleted or renamed on the server. Until then, fetch without pruning.'**
  String get failureCaseCollisionServer;

  /// Remedy: delete the colliding remote-tracking refs and fetch again.
  ///
  /// In en, this message translates to:
  /// **'Repair and fetch again'**
  String get failureCaseCollisionRepairAction;

  /// Push rejected because the remote is ahead.
  ///
  /// In en, this message translates to:
  /// **'The remote has newer commits'**
  String get failureRemoteAheadTitle;

  /// Explains a rejected non-fast-forward push.
  ///
  /// In en, this message translates to:
  /// **'The remote branch has commits your branch does not have, so Git rejected the push. Fetch them, then pull or rebase before you push again.'**
  String get failureRemoteAheadMessage;

  /// Names the colliding refs, comma-separated.
  ///
  /// In en, this message translates to:
  /// **'{names} differ only in letter case. On this computer\'s file system they share one file, so Git cannot update them in one fetch.'**
  String failureCaseCollisionMessage(String names);

  /// Opens a dialog that adds an ignore entry for a changed file or folder.
  ///
  /// In en, this message translates to:
  /// **'Add to .gitignore…'**
  String get fileActionAddToGitignore;

  /// Title of the dialog that adds a .gitignore entry.
  ///
  /// In en, this message translates to:
  /// **'Add to .gitignore'**
  String get ignoreDialogTitle;

  /// Explains the .gitignore dialog for a file.
  ///
  /// In en, this message translates to:
  /// **'GitLama adds this entry to the .gitignore file at the top of the repository. As suggested, it matches only this file.'**
  String get ignoreDialogFileDescription;

  /// Explains the .gitignore dialog for a folder.
  ///
  /// In en, this message translates to:
  /// **'GitLama adds this entry to the .gitignore file at the top of the repository. As suggested, it matches only this folder.'**
  String get ignoreDialogFolderDescription;

  /// Shown when the file to ignore is already tracked.
  ///
  /// In en, this message translates to:
  /// **'Git already tracks this file. The entry hides it only once it is removed from the repository.'**
  String get ignoreDialogTrackedNote;

  /// Label of the .gitignore entry field.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get ignoreDialogEntry;

  /// Hint below the .gitignore entry field.
  ///
  /// In en, this message translates to:
  /// **'Use * to match any characters, for example *.log.'**
  String get ignoreDialogEntryHint;

  /// Adds the entry to .gitignore.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get ignoreDialogAdd;

  /// The .gitignore entry is empty, a comment or not one line.
  ///
  /// In en, this message translates to:
  /// **'Git cannot use this entry. Enter one pattern that does not start with #.'**
  String get ignoreFailureInvalid;

  /// Writing .gitignore failed.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not change .gitignore. It may be a link, too large or not writable.'**
  String get ignoreFailureWrite;

  /// Saves every file and folder of a commit as a zip file.
  ///
  /// In en, this message translates to:
  /// **'Save snapshot as ZIP…'**
  String get commandSaveCommitArchive;

  /// Title of the dialog shown while a commit's zip snapshot is saved.
  ///
  /// In en, this message translates to:
  /// **'Saving snapshot'**
  String get archiveProgressTitle;

  /// Shown before the snapshot's files are counted.
  ///
  /// In en, this message translates to:
  /// **'Reading the commit…'**
  String get archiveProgressPreparing;

  /// Progress of a snapshot.
  ///
  /// In en, this message translates to:
  /// **'{files} of {total} files'**
  String archiveProgressFiles(int files, int total);

  /// Shown while the finished snapshot is written to the chosen file.
  ///
  /// In en, this message translates to:
  /// **'Writing the ZIP file…'**
  String get archiveProgressWriting;

  /// Shown when a commit's snapshot was saved.
  ///
  /// In en, this message translates to:
  /// **'Snapshot saved as {name}.'**
  String archiveSaved(String name);

  /// Snapshot submodules whose commit was not available.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 submodule was not available and is an empty folder.} other{{count} submodules were not available and are empty folders.}}'**
  String archiveMissingSubmodules(int count);

  /// Snapshot LFS files whose content could not be obtained.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Git LFS file could not be downloaded and holds its pointer.} other{{count} Git LFS files could not be downloaded and hold their pointers.}}'**
  String archiveUnresolvedLfs(int count);

  /// Snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'The repository was closed before the snapshot was saved.'**
  String get archiveFailureStale;

  /// Snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'The commit is no longer in the repository.'**
  String get archiveFailureMissingCommit;

  /// Snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'The commit has too many files for a snapshot.'**
  String get archiveFailureTooLarge;

  /// Snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'Other snapshots of this repository are still being saved.'**
  String get archiveFailureBusy;

  /// Snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'The ZIP file could not be written.'**
  String get archiveFailureWrite;

  /// Snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'Git could not read the commit\'s files.'**
  String get archiveFailureGit;

  /// Settings category title for how diffs are shown.
  ///
  /// In en, this message translates to:
  /// **'Diffs'**
  String get settingsDiffView;

  /// Explains the diff settings.
  ///
  /// In en, this message translates to:
  /// **'Choose how every diff is shown. The buttons above a diff change these settings too.'**
  String get settingsDiffViewDetail;

  /// Setting for the unified or side-by-side diff layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get settingsDiffLayout;

  /// Diffs show old and new lines in one column.
  ///
  /// In en, this message translates to:
  /// **'Unified'**
  String get settingsDiffUnified;

  /// Diffs show old and new lines in two columns.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get settingsDiffSideBySide;

  /// Setting for how diff lines longer than the view are shown.
  ///
  /// In en, this message translates to:
  /// **'Long lines'**
  String get settingsDiffWrap;

  /// Long diff lines wrap.
  ///
  /// In en, this message translates to:
  /// **'Wrap'**
  String get settingsDiffWrapOn;

  /// Long diff lines scroll horizontally.
  ///
  /// In en, this message translates to:
  /// **'Scroll sideways'**
  String get settingsDiffWrapOff;

  /// Setting for which whitespace changes diffs ignore.
  ///
  /// In en, this message translates to:
  /// **'Whitespace'**
  String get settingsDiffWhitespace;

  /// Diffs show every whitespace change.
  ///
  /// In en, this message translates to:
  /// **'Show all changes'**
  String get settingsDiffWhitespacePreserve;

  /// Diffs ignore all whitespace.
  ///
  /// In en, this message translates to:
  /// **'Ignore all whitespace'**
  String get settingsDiffWhitespaceIgnoreAll;

  /// Diffs ignore changes in the amount of whitespace.
  ///
  /// In en, this message translates to:
  /// **'Ignore changed amounts'**
  String get settingsDiffWhitespaceIgnoreAmount;

  /// Diffs ignore whitespace at the end of lines.
  ///
  /// In en, this message translates to:
  /// **'Ignore at line ends'**
  String get settingsDiffWhitespaceIgnoreEndOfLine;

  /// Setting for the + and - markers on diff rows.
  ///
  /// In en, this message translates to:
  /// **'Plus and minus markers'**
  String get settingsDiffIndicators;

  /// Setting for the change overview beside a diff.
  ///
  /// In en, this message translates to:
  /// **'Minimap'**
  String get settingsDiffMinimap;

  /// CI result of a branch's head on the hosting account, such as the main branch of the bound repository. checks is a CI result label such as 'Checks passed'.
  ///
  /// In en, this message translates to:
  /// **'{branch}: {checks}'**
  String hostingBranchChecks(String branch, String checks);

  /// CI result of a pull request's head: every check passed.
  ///
  /// In en, this message translates to:
  /// **'Checks passed'**
  String get hostingCheckPassing;

  /// CI result of a pull request's head: a check failed.
  ///
  /// In en, this message translates to:
  /// **'Checks failed'**
  String get hostingCheckFailing;

  /// CI result of a pull request's head: checks are still running.
  ///
  /// In en, this message translates to:
  /// **'Checks running'**
  String get hostingCheckPending;

  /// CI result of a pull request's head: checks were canceled.
  ///
  /// In en, this message translates to:
  /// **'Checks canceled'**
  String get hostingCheckCanceled;

  /// CI result of a pull request's head: checks were skipped.
  ///
  /// In en, this message translates to:
  /// **'Checks skipped'**
  String get hostingCheckSkipped;

  /// CI result of a pull request's head is not known.
  ///
  /// In en, this message translates to:
  /// **'Checks unknown'**
  String get hostingCheckUnknown;

  /// An open pull request merges into its target without conflicts.
  ///
  /// In en, this message translates to:
  /// **'No merge conflicts'**
  String get hostingMergeable;

  /// An open pull request has conflicts with its target.
  ///
  /// In en, this message translates to:
  /// **'Merge conflicts'**
  String get hostingMergeConflicting;

  /// The provider is still computing whether a pull request has conflicts.
  ///
  /// In en, this message translates to:
  /// **'Checking for merge conflicts'**
  String get hostingMergeChecking;

  /// Tooltip line of a pull request chip whose head is at none of its branch's refs.
  ///
  /// In en, this message translates to:
  /// **'The pull request\'s head on the host is not where this branch is. GitLama checks again shortly; fetch if the branch changed on the host.'**
  String get hostingPullRequestOutdated;

  /// Button and accessible name of the sidebar's branch, remote and tag filter.
  ///
  /// In en, this message translates to:
  /// **'Filter branches'**
  String get sidebarFilterShow;

  /// Placeholder of the sidebar's reference filter field.
  ///
  /// In en, this message translates to:
  /// **'Filter branches and tags'**
  String get sidebarFilterPlaceholder;

  /// Clears and closes the sidebar's reference filter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get sidebarFilterClear;

  /// Shown while the sidebar's reference filter matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No matching branches or tags.'**
  String get sidebarFilterNoMatches;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Check out commit…'**
  String get commandCheckoutCommit;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Check out commit {target} with detached HEAD? No branch will be moved. To keep new commits you make here, create a branch before switching away.'**
  String refConfirmCheckoutCommit(String target);

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'You have uncommitted changes. Choose how to save them before checking out this commit. Dismiss cancels checkout.'**
  String get commitCheckoutDirtyHelp;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Stash saves all tracked and untracked changes and leaves them in the stash after checkout. Ignored files stay in the working tree.'**
  String get commitCheckoutStashHelp;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Stash & reapply restores those changes at the selected commit. If this conflicts, the stash is retained and Changes opens for resolution.'**
  String get commitCheckoutReapplyHelp;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commitCheckoutDismiss;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get commitCheckoutStash;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Stash & reapply'**
  String get commitCheckoutStashAndReapply;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Check out commit'**
  String get commitCheckoutAction;

  /// Detached commit checkout confirmation or action.
  ///
  /// In en, this message translates to:
  /// **'Checking out commit…'**
  String get commitCheckoutBusy;

  /// Public OAuth client setup and client configuration rejection.
  ///
  /// In en, this message translates to:
  /// **'Disable “Confidential Client” (or enable “Public Client”) for this application. GitLama uses PKCE without a client secret.'**
  String get hostingStepPublicClient;

  /// Public OAuth client setup and client configuration rejection.
  ///
  /// In en, this message translates to:
  /// **'The OAuth application was rejected. Check the Client ID and redirect URI. In Forgejo or Codeberg, disable “Confidential Client” (or enable “Public Client”), save, then authorize again.'**
  String get hostingOAuthClientRejected;

  /// No description provided for @discardMixedConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'{tracked, plural, =1{Restore 1 tracked file} other{Restore {tracked} tracked files}} and {untracked, plural, =1{permanently delete 1 new file} other{permanently delete {untracked} new files}}? These unstaged changes cannot be recovered.'**
  String discardMixedConfirmMessage(int tracked, int untracked);

  /// No description provided for @discardPartial.
  ///
  /// In en, this message translates to:
  /// **'Discard completed for {completed} of {total} files before it stopped. Check the remaining changes before trying again; the last step may have changed files.'**
  String discardPartial(int completed, int total);

  /// Conflict resolver: Resize conflicted files
  ///
  /// In en, this message translates to:
  /// **'Resize conflicted files'**
  String get conflictResizeFiles;

  /// Conflict resolver: Conflicted files
  ///
  /// In en, this message translates to:
  /// **'Conflicted files'**
  String get conflictFilesTitle;

  /// Conflict resolver: Current / Incoming
  ///
  /// In en, this message translates to:
  /// **'Current / Incoming'**
  String get conflictComparisonTitle;

  /// Conflict resolver: Deleted on both sides
  ///
  /// In en, this message translates to:
  /// **'Deleted on both sides'**
  String get conflictPresenceBothDeleted;

  /// Conflict resolver: Added only on the current side
  ///
  /// In en, this message translates to:
  /// **'Added only on the current side'**
  String get conflictPresenceAddedCurrent;

  /// Conflict resolver: Deleted on the incoming side; present on the current side
  ///
  /// In en, this message translates to:
  /// **'Deleted on the incoming side; present on the current side'**
  String get conflictPresenceDeletedIncoming;

  /// Conflict resolver: Added only on the incoming side
  ///
  /// In en, this message translates to:
  /// **'Added only on the incoming side'**
  String get conflictPresenceAddedIncoming;

  /// Conflict resolver: Deleted on the current side; present on the incoming side
  ///
  /// In en, this message translates to:
  /// **'Deleted on the current side; present on the incoming side'**
  String get conflictPresenceDeletedCurrent;

  /// Conflict resolver: Added independently on both sides
  ///
  /// In en, this message translates to:
  /// **'Added independently on both sides'**
  String get conflictPresenceBothAdded;

  /// Conflict resolver: Present on both sides
  ///
  /// In en, this message translates to:
  /// **'Present on both sides'**
  String get conflictPresenceBothPresent;

  /// Conflict resolver: Unmerged path; stage details unavailable
  ///
  /// In en, this message translates to:
  /// **'Unmerged path; stage details unavailable'**
  String get conflictPresenceUnknown;

  /// Conflict resolver: Current and incoming have identical file bytes.
  ///
  /// In en, this message translates to:
  /// **'Current and incoming have identical file bytes.'**
  String get conflictContentIdentical;

  /// Conflict resolver: The text differs only in line endings (LF, CRLF or CR).
  ///
  /// In en, this message translates to:
  /// **'The text differs only in line endings (LF, CRLF or CR).'**
  String get conflictContentLineEndings;

  /// Conflict resolver: The text differs only in the final newline.
  ///
  /// In en, this message translates to:
  /// **'The text differs only in the final newline.'**
  String get conflictContentFinalNewline;

  /// Conflict resolver: The text differs only in the UTF-8 byte order mark (BOM).
  ///
  /// In en, this message translates to:
  /// **'The text differs only in the UTF-8 byte order mark (BOM).'**
  String get conflictContentBom;

  /// Conflict resolver: The text differs only in whitespace, including spaces, tabs or line endings.
  ///
  /// In en, this message translates to:
  /// **'The text differs only in whitespace, including spaces, tabs or line endings.'**
  String get conflictContentWhitespace;

  /// Conflict resolver: Current and incoming have different file content.
  ///
  /// In en, this message translates to:
  /// **'Current and incoming have different file content.'**
  String get conflictContentDifferent;

  /// Conflict resolver: Content equality cannot be checked from this preview.
  ///
  /// In en, this message translates to:
  /// **'Content equality cannot be checked from this preview.'**
  String get conflictContentUnavailable;

  /// Conflict resolver: An absent file is different from an empty file. Choosing the absent side keeps the deletion.
  ///
  /// In en, this message translates to:
  /// **'An absent file is different from an empty file. Choosing the absent side keeps the deletion.'**
  String get conflictContentMissingSide;

  /// Conflict resolver: File types or executable permissions differ. Compare the entry details before choosing a complete side.
  ///
  /// In en, this message translates to:
  /// **'File types or executable permissions differ. See Entry details.'**
  String get conflictModesDiffer;

  /// Conflict resolver: No text conflict markers remain, but Git still records this path as unmerged. Review the result and its file type, then resolve the file.
  ///
  /// In en, this message translates to:
  /// **'No text markers. Review and resolve this file to clear its unmerged state.'**
  String get conflictNoMarkers;

  /// Conflict resolver: Entry details
  ///
  /// In en, this message translates to:
  /// **'Entry details'**
  String get conflictEntryDetailsTitle;

  /// Conflict resolver: Current entry
  ///
  /// In en, this message translates to:
  /// **'Current entry'**
  String get conflictCurrentEntry;

  /// Conflict resolver: Incoming entry
  ///
  /// In en, this message translates to:
  /// **'Incoming entry'**
  String get conflictIncomingEntry;

  /// Conflict resolver: Saved working entry
  ///
  /// In en, this message translates to:
  /// **'Saved working entry'**
  String get conflictWorkingEntry;

  /// Conflict resolver: Absent
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get conflictEntryAbsent;

  /// Conflict resolver: Regular file
  ///
  /// In en, this message translates to:
  /// **'Regular file'**
  String get conflictEntryRegular;

  /// Conflict resolver: Executable file
  ///
  /// In en, this message translates to:
  /// **'Executable file'**
  String get conflictEntryExecutable;

  /// Conflict resolver: Symbolic link (content is the link target)
  ///
  /// In en, this message translates to:
  /// **'Symbolic link (content is the link target)'**
  String get conflictEntrySymlink;

  /// Conflict resolver: Submodule (content identifies a commit)
  ///
  /// In en, this message translates to:
  /// **'Submodule (content identifies a commit)'**
  String get conflictEntrySubmodule;

  /// Conflict resolver: Directory
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get conflictEntryDirectory;

  /// Conflict resolver: Unknown entry type
  ///
  /// In en, this message translates to:
  /// **'Unknown entry type'**
  String get conflictEntryUnknown;

  /// Conflict resolver: {type} · mode {mode} · {bytes} bytes
  ///
  /// In en, this message translates to:
  /// **'{type} · mode {mode} · {bytes} bytes'**
  String conflictEntryFacts(String type, String mode, String bytes);

  /// Conflict resolver: Index stages describe this path only. Rename and directory/file conflicts can involve other paths; review all related entries. “Saved working entry” describes the file on disk, before unsaved result edits.
  ///
  /// In en, this message translates to:
  /// **'Index stages describe this path only. Rename and directory/file conflicts can involve other paths; review all related entries. “Saved working entry” describes the file on disk, before unsaved result edits.'**
  String get conflictPathFacts;

  /// Conflict resolver: {endings} · {finalNewline} · {bom}
  ///
  /// In en, this message translates to:
  /// **'{endings} · {finalNewline} · {bom}'**
  String conflictFormatFacts(String endings, String finalNewline, String bom);

  /// Conflict resolver: No line breaks
  ///
  /// In en, this message translates to:
  /// **'No line breaks'**
  String get conflictNoLineBreaks;

  /// Conflict resolver: Mixed line endings
  ///
  /// In en, this message translates to:
  /// **'Mixed line endings'**
  String get conflictMixedLineBreaks;

  /// Conflict resolver: Final newline
  ///
  /// In en, this message translates to:
  /// **'Final newline'**
  String get conflictFinalNewlinePresent;

  /// Conflict resolver: No final newline
  ///
  /// In en, this message translates to:
  /// **'No final newline'**
  String get conflictFinalNewlineAbsent;

  /// Conflict resolver: UTF-8 BOM
  ///
  /// In en, this message translates to:
  /// **'UTF-8 BOM'**
  String get conflictBomPresent;

  /// Conflict resolver: No UTF-8 BOM
  ///
  /// In en, this message translates to:
  /// **'No UTF-8 BOM'**
  String get conflictBomAbsent;

  /// Conflict file count label when there are no remaining text markers but the path remains unmerged.
  ///
  /// In en, this message translates to:
  /// **'Needs resolution'**
  String get conflictReviewFile;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'You have uncommitted changes. Choose whether to save them before pulling or let Git try with them in place.'**
  String get transferLocalChangesHelp;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Stash, pull, and reapply my changes'**
  String get transferStashBeforePull;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Save staged, unstaged, and untracked files, then restore them with their staging after the pull. Ignored files and edits inside submodules are not stashed. A named recovery copy stays in Stashes until you remove it.'**
  String get transferStashBeforePullHelp;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Stash and pull'**
  String get transferStashPullAction;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Pull completed. Your changes and staging were restored. A recovery copy remains in Stashes.'**
  String get transferPullStashRestored;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Pull completed, but reapplying your changes caused conflicts. Resolve them in Changes. The recovery stash is kept.'**
  String get transferPullStashConflict;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Pull completed. Your changes could not be fully restored; they remain saved in Stashes. Review Changes before applying the recovery stash.'**
  String get transferPullStashSaved;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'{reason} Your changes and staging were restored. A recovery copy remains in Stashes.'**
  String transferPullFailedStashRestored(String reason);

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Pull did not complete. Your changes are saved in Stashes. Finish or abort any active Git operation, then apply the recovery stash. Do not pull again to restore them.'**
  String get transferPullFailedStashSaved;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'Your changes after pulling'**
  String get transferPullRecoveryTitle;

  /// Guidance for explicitly saving and restoring local changes around pull.
  ///
  /// In en, this message translates to:
  /// **'The recovery stash is named “GitLama before pull” followed by an identifier. It includes the saved index. Applying it again after a successful restoration duplicates the attempt; remove it only after reviewing your changes.'**
  String get transferPullRecoveryHelp;

  /// Tooltip of a repository tab that holds several open worktrees.
  ///
  /// In en, this message translates to:
  /// **'{repository} · {count} worktrees open'**
  String worktreeTabsTooltip(String repository, int count);

  /// Marker and screen-reader name of the row of open worktrees under the tab strip.
  ///
  /// In en, this message translates to:
  /// **'Open worktrees of {repository}'**
  String worktreeRowLabel(String repository);

  /// Button at the end of the worktree row that lists the repository's worktrees to open.
  ///
  /// In en, this message translates to:
  /// **'Open worktree'**
  String get worktreeOpen;

  /// Disabled item of the worktree row's menu when no other worktree exists.
  ///
  /// In en, this message translates to:
  /// **'Every worktree is open'**
  String get worktreeAllOpen;

  /// Notification when the worktree row's menu cannot read the repository's worktrees.
  ///
  /// In en, this message translates to:
  /// **'Could not list the worktrees.'**
  String get worktreeListFailed;

  /// Tab context-menu action that closes every open worktree of the repository.
  ///
  /// In en, this message translates to:
  /// **'Close all {count} worktrees'**
  String worktreeCloseAll(int count);

  /// Tooltip note of the worktree row's tab for the repository's main worktree.
  ///
  /// In en, this message translates to:
  /// **'Main worktree'**
  String get worktreeMainTab;

  /// Chosen state of a side header whose side deleted the file; pressing it again clears the choice.
  ///
  /// In en, this message translates to:
  /// **'Keeping deletion'**
  String get conflictKeepingDeletion;

  /// Chosen state of a side header whose whole file is chosen; pressing it again clears the choice.
  ///
  /// In en, this message translates to:
  /// **'Using this file'**
  String get conflictUsingThisFile;

  /// Clears a whole-file choice so the regions or another side can be picked.
  ///
  /// In en, this message translates to:
  /// **'Choose differently'**
  String get conflictChooseDifferently;

  /// Banner title when one side of a conflicted file deleted it and no choice is made yet.
  ///
  /// In en, this message translates to:
  /// **'This file was deleted on one side'**
  String get conflictDeletionDecisionTitle;

  /// Banner text that asks the user to decide on a deleted file.
  ///
  /// In en, this message translates to:
  /// **'Keep the deletion, or keep the file from the side that still has it.'**
  String get conflictDeletionDecisionHint;

  /// Banner action that keeps the version of the side that still has the file.
  ///
  /// In en, this message translates to:
  /// **'Keep file from {branch}'**
  String conflictKeepFileFrom(String branch);

  /// Banner title after the user chose to keep a deletion.
  ///
  /// In en, this message translates to:
  /// **'Resolving deletes this file'**
  String get conflictDeletionChosenTitle;

  /// Banner text after the user chose to keep a deletion.
  ///
  /// In en, this message translates to:
  /// **'You chose the deletion from {branch}. Resolving removes the file from the working tree and stages the deletion.'**
  String conflictDeletionChosenBody(String branch);

  /// Banner title after the user chose one side's whole file.
  ///
  /// In en, this message translates to:
  /// **'Using the whole file from {branch}'**
  String conflictWholeFileChosenTitle(String branch);

  /// Banner text after the user chose one side's whole file.
  ///
  /// In en, this message translates to:
  /// **'Resolving saves this version. Editing the result or picking regions replaces this choice.'**
  String get conflictWholeFileChosenBody;

  /// Result pane placeholder after the user chose to keep a deletion.
  ///
  /// In en, this message translates to:
  /// **'The file will be deleted'**
  String get conflictDeletionResult;

  /// Resolve button label when the chosen result deletes the file.
  ///
  /// In en, this message translates to:
  /// **'Resolve by deleting'**
  String get conflictResolveByDeleting;

  /// Result pane hint for a binary or huge conflicted file before a side is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose which version to keep.'**
  String get conflictChooseVersion;

  /// Text above the resolved files' list once every conflict is resolved.
  ///
  /// In en, this message translates to:
  /// **'Check how each file was resolved. You can undo any of them before you continue.'**
  String get conflictResolvedHint;

  /// How a resolved file was resolved: it was deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get conflictOutcomeDeleted;

  /// How a resolved file was resolved: the whole current file.
  ///
  /// In en, this message translates to:
  /// **'Kept current version ({label})'**
  String conflictOutcomeCurrent(String label);

  /// How a resolved file was resolved: the whole incoming file.
  ///
  /// In en, this message translates to:
  /// **'Took incoming version ({label})'**
  String conflictOutcomeIncoming(String label);

  /// How a resolved file was resolved: an edited or region-picked result.
  ///
  /// In en, this message translates to:
  /// **'Merged result'**
  String get conflictOutcomeMerged;

  /// How a resolved file was resolved: in an external merge tool.
  ///
  /// In en, this message translates to:
  /// **'Merged in external tool'**
  String get conflictOutcomeExternal;

  /// Status message after a conflicted file was resolved and the resolver moved on to the next conflicted file.
  ///
  /// In en, this message translates to:
  /// **'Resolved {resolved}. Now showing {next}.'**
  String conflictResolvedNext(String resolved, String next);

  /// Accessibility label of the conflict resolver's step line.
  ///
  /// In en, this message translates to:
  /// **'Conflict resolution steps'**
  String get conflictGuideTitle;

  /// Conflict resolver step: pick the changes for each conflict.
  ///
  /// In en, this message translates to:
  /// **'Pick changes'**
  String get conflictStepPick;

  /// Conflict resolver step: review the result of the file.
  ///
  /// In en, this message translates to:
  /// **'Review result'**
  String get conflictStepReview;

  /// Conflict resolver step: mark the files resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get conflictStepResolve;

  /// Conflict resolver step: continue the paused operation.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get conflictStepContinue;

  /// Conflict resolver step: finished, for conflicts without an operation to continue.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get conflictStepDone;

  /// Conflict resolver guidance while the shown text file still has conflicts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Choose a side for the conflict, or edit the result.} other{Choose a side for each of the {count} conflicts, or edit the result.}}'**
  String conflictGuidePick(int count);

  /// Conflict resolver guidance for a file one side deleted.
  ///
  /// In en, this message translates to:
  /// **'One side deleted this file. Keep the deletion or keep the file.'**
  String get conflictGuideDecideDeletion;

  /// Conflict resolver guidance once the shown file has no conflict left.
  ///
  /// In en, this message translates to:
  /// **'Check the result, then resolve the file.'**
  String get conflictGuideReview;

  /// Conflict resolver guidance once the deletion was chosen for the shown file.
  ///
  /// In en, this message translates to:
  /// **'The file will be deleted. Resolve it to confirm.'**
  String get conflictGuideReviewDeletion;

  /// Conflict resolver guidance once every file is resolved.
  ///
  /// In en, this message translates to:
  /// **'Check how each file was resolved, then continue.'**
  String get conflictGuideContinue;

  /// Conflict resolver guidance once every file of standalone conflicts is resolved.
  ///
  /// In en, this message translates to:
  /// **'All conflicts are resolved.'**
  String get conflictGuideDone;

  /// Conflict resolver: how many conflicted files are resolved.
  ///
  /// In en, this message translates to:
  /// **'{resolved} of {total} files resolved'**
  String conflictGuideResolvedCount(int resolved, int total);

  /// Changes file row: a staging or unstaging action is running or queued.
  ///
  /// In en, this message translates to:
  /// **'Staging action pending'**
  String get stagingPendingFile;

  /// Staging progress while waiting for the repository mutation lease.
  ///
  /// In en, this message translates to:
  /// **'Waiting for repository…'**
  String get stagingWaiting;

  /// Staging progress while checking fresh repository status.
  ///
  /// In en, this message translates to:
  /// **'Checking changes…'**
  String get stagingPreparing;

  /// Staging progress while building and installing the private index.
  ///
  /// In en, this message translates to:
  /// **'Updating index…'**
  String get stagingUpdating;

  /// Staging progress after the confirmed index update, while reconciling repository state.
  ///
  /// In en, this message translates to:
  /// **'Index updated. Refreshing changes…'**
  String get stagingRefreshing;

  /// Cancel staging and unstaging requests that have not started.
  ///
  /// In en, this message translates to:
  /// **'Cancel queued actions'**
  String get stagingClearQueue;

  /// No description provided for @stagingQueueCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No queued actions.} =1{1 action queued.} other{{count} actions queued.}}'**
  String stagingQueueCount(int count);

  /// No description provided for @stagingQueueStopped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 queued action was canceled because staging did not finish safely. Review the changes before trying again.} other{{count} queued actions were canceled because staging did not finish safely. Review the changes before trying again.}}'**
  String stagingQueueStopped(int count);

  /// Reference target recovery and selection
  ///
  /// In en, this message translates to:
  /// **'Starting point'**
  String get refMutationStartingPoint;

  /// Reference target recovery and selection
  ///
  /// In en, this message translates to:
  /// **'Starting commit unavailable'**
  String get refMutationTargetUnavailableTitle;

  /// Reference target recovery and selection
  ///
  /// In en, this message translates to:
  /// **'The selected starting commit or its tree is unavailable in this repository. Refresh references and history, then choose a starting point again. Your input will be kept. GitLama will not automatically retry the operation.'**
  String get refMutationTargetUnavailableDetail;

  /// Reference target recovery and selection
  ///
  /// In en, this message translates to:
  /// **'Refresh and choose again'**
  String get refMutationRefreshTarget;

  /// Heading of the per-repository Git status accelerator settings.
  ///
  /// In en, this message translates to:
  /// **'Faster change checks'**
  String get settingsStatusAcceleration;

  /// Explains Git's status accelerators in the settings.
  ///
  /// In en, this message translates to:
  /// **'Git\'s untracked cache and file system monitor make checking a large repository for changes much faster. Turning them on changes this repository\'s own Git settings.'**
  String get settingsStatusAccelerationHint;

  /// Label of the core.untrackedCache state in the settings.
  ///
  /// In en, this message translates to:
  /// **'Untracked cache'**
  String get settingsUntrackedCache;

  /// Label of the core.fsmonitor state in the settings.
  ///
  /// In en, this message translates to:
  /// **'File system monitor'**
  String get settingsFsmonitor;

  /// Shown when Git provides no built-in file system monitor here.
  ///
  /// In en, this message translates to:
  /// **'Not available with this Git on this system'**
  String get settingsFsmonitorUnavailable;

  /// Button that enables the missing Git status accelerators for the repository.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get settingsStatusAccelerationEnable;

  /// Shown when every available status accelerator is enabled.
  ///
  /// In en, this message translates to:
  /// **'Everything available is on.'**
  String get settingsStatusAccelerationAllOn;

  /// Shown in place of the status accelerators for a repository on another computer.
  ///
  /// In en, this message translates to:
  /// **'Only available for repositories on this computer.'**
  String get settingsStatusAccelerationRemote;

  /// Shown when the status accelerator state could not be read.
  ///
  /// In en, this message translates to:
  /// **'GitLama could not read this repository\'s Git settings.'**
  String get settingsStatusAccelerationReadFailed;

  /// Duration of the last status scan when under a second.
  ///
  /// In en, this message translates to:
  /// **'The last check for changes took less than a second.'**
  String get settingsStatusAccelerationLastScanFast;

  /// Duration of the last status scan in whole seconds.
  ///
  /// In en, this message translates to:
  /// **'The last check for changes took about {seconds} s.'**
  String settingsStatusAccelerationLastScan(int seconds);

  /// User-controlled diagnostic capture and export: diagnosticsTitle
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// User-controlled diagnostic capture and export: diagnosticsDescription
  ///
  /// In en, this message translates to:
  /// **'Recent safe events stay in memory only (up to 1,000 events or 256 KiB). Detailed capture lasts up to 15 minutes or until the session ends. No credentials or private content are included. Preview before saving or sharing. Nothing is uploaded automatically. Clear history does not remove copies you saved or shared.'**
  String get diagnosticsDescription;

  /// User-controlled diagnostic capture and export: diagnosticsEnable
  ///
  /// In en, this message translates to:
  /// **'Enable detailed diagnostics for 15 minutes'**
  String get diagnosticsEnable;

  /// User-controlled diagnostic capture and export: diagnosticsDisable
  ///
  /// In en, this message translates to:
  /// **'Detailed diagnostics active — stop recording details'**
  String get diagnosticsDisable;

  /// User-controlled diagnostic capture and export: diagnosticsClear
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get diagnosticsClear;

  /// User-controlled diagnostic capture and export: diagnosticsPreview
  ///
  /// In en, this message translates to:
  /// **'Preview export'**
  String get diagnosticsPreview;

  /// User-controlled diagnostic capture and export: diagnosticsCancel
  ///
  /// In en, this message translates to:
  /// **'Close preview'**
  String get diagnosticsCancel;

  /// User-controlled diagnostic capture and export: diagnosticsSave
  ///
  /// In en, this message translates to:
  /// **'Save to file'**
  String get diagnosticsSave;

  /// User-controlled diagnostic capture and export: diagnosticsShare
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get diagnosticsShare;

  /// User-controlled diagnostic capture and export: diagnosticsFailed
  ///
  /// In en, this message translates to:
  /// **'Could not export diagnostics. Try another destination.'**
  String get diagnosticsFailed;

  /// User-controlled diagnostic capture and export: diagnosticsSaved
  ///
  /// In en, this message translates to:
  /// **'Diagnostics saved.'**
  String get diagnosticsSaved;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
