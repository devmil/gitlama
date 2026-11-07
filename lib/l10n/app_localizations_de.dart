// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get workflowExit => 'Verlassen';

  @override
  String get conflictUnknownProvenance => 'Letzte Änderung unbekannt';

  @override
  String get patchShowInFolder => 'Im Ordner anzeigen';

  @override
  String get referencePickerTitle => 'Referenz auswählen';

  @override
  String get referencePickerSearch =>
      'Nach Name, Commit-ID oder Betreff suchen';

  @override
  String get referencePickerEmpty => 'Keine passenden Referenzen';

  @override
  String get referencePickerHistoryHint =>
      'Branches, Tags und geladene Commits suchen oder eine Revision eingeben.';

  @override
  String get sidebarCopyName => 'Namen kopieren';

  @override
  String get sidebarCurrentBranch => 'Aktueller Branch';

  @override
  String get appTitle => 'GitLama';

  @override
  String get commandReportIssue => 'Problem melden…';

  @override
  String get reportIssueOpenFailed =>
      'Der Issue-Tracker konnte nicht geöffnet werden.';

  @override
  String get licensesTitle => 'Lizenzen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsGit => 'Git';

  @override
  String get settingsIntegrations => 'Hosting-Konten';

  @override
  String get settingsRepositoryBinding => 'Repository-Verknüpfung';

  @override
  String get settingsCustomCommands => 'Werkzeuge und Befehle';

  @override
  String get settingsDiffRenderer => 'Diff-Renderer';

  @override
  String get settingsShortcuts => 'Tastenkürzel';

  @override
  String get settingsAccessibility => 'Barrierefreiheit';

  @override
  String get settingsAppearanceDetail =>
      'Änderungen der Darstellung gelten sofort und werden automatisch gespeichert.';

  @override
  String get settingsGitDetail =>
      'Lege fest, wie Repositorys abgerufen werden, und verwalte Einstellungen des aktiven Repositorys.';

  @override
  String get settingsAutoFetch => 'Automatisch abrufen';

  @override
  String get settingsAutoFetchInterval => 'Abrufintervall';

  @override
  String get settingsAutoFetchHint =>
      'Geöffnete Repositorys rufen ihr Remote im Hintergrund ab. Dabei wird nichts zusammengeführt oder gepullt; ein Abruf, der eine Anmeldung braucht, wird übersprungen.';

  @override
  String get settingsRepositoryAutoFetch =>
      'Dieses Repository automatisch abrufen';

  @override
  String get settingsFollowApplication => 'Wie in der App';

  @override
  String get settingsOn => 'Ein';

  @override
  String get settingsOff => 'Aus';

  @override
  String settingsAutoFetchMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String get settingsIntegrationsDetail =>
      'Füge Verbindungen zu Git-Hosting-Anbietern hinzu und verwalte sie.';

  @override
  String get settingsRepositoryBindingDetail =>
      'Lege fest, welches Hosting-Konto und welches Remote zu diesem Repository gehören.';

  @override
  String get settingsCustomCommandsDetail =>
      'Nutze gefundene Werkzeuge oder füge einen Befehl hinzu. GitLama prüft gespeicherte Befehle und zeigt jeden Aufruf vor dem Start an.';

  @override
  String get settingsDiffRendererDetail =>
      'Konfiguriere und prüfe eine externe Diff-Darstellung.';

  @override
  String get settingsShortcutsDetail =>
      'Wähle ein Tastenkürzel und drücke die neue Tastenkombination; Escape bricht ab. Entferne ein Tastenkürzel, um den Befehl nicht zu belegen. Konflikte und reservierte Tastenkürzel werden abgelehnt.';

  @override
  String get settingsShortcutRecording => 'Tastenkombination drücken …';

  @override
  String get settingsShortcutClear => 'Tastenkürzel entfernen';

  @override
  String get settingsShortcutUnbound => 'Nicht belegt';

  @override
  String get settingsShortcutReset => 'Standardkürzel wiederherstellen';

  @override
  String get settingsShortcutInvalid =>
      'Verwende Ctrl, Cmd, Alt oder Shift mit einem Buchstaben, einer Ziffer, einer Funktions-, Pfeil- oder Eingabetaste.';

  @override
  String get settingsShortcutReserved =>
      'Dieses Tastenkürzel ist vom Betriebssystem reserviert.';

  @override
  String get settingsShortcutConflict =>
      'Dieses Tastenkürzel ist bereits einem anderen Befehl zugewiesen.';

  @override
  String get settingsAccessibilityDetail =>
      'Lege fest, wie GitLama den Systemeinstellungen für Bewegung folgt.';

  @override
  String get settingsLicensesDetail =>
      'Lies die GitLama-Lizenz und die Hinweise zu mitgelieferten Abhängigkeiten.';

  @override
  String get settingsTheme => 'Farbschema';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsFollowSystem => 'Systemeinstellung folgen';

  @override
  String get settingsDensity => 'Dichte';

  @override
  String get settingsDensityCompact => 'Kompakt';

  @override
  String get settingsDensityRegular => 'Normal';

  @override
  String get settingsDensityComfortable => 'Großzügig';

  @override
  String get settingsDateFormat => 'Datumsformat';

  @override
  String get settingsAvatars => 'Autorenbilder';

  @override
  String get settingsAvatarsInitials => 'Nur Initialen';

  @override
  String get settingsAvatarsGravatar => 'Gravatar verwenden';

  @override
  String get avatarGravatarTitle => 'Autorenbilder';

  @override
  String get avatarGravatarHint =>
      'Gravatar kann Autorenbilder anzeigen. Wenn du es aktivierst, wird ein Hash der E-Mail-Adresse jedes sichtbaren Autors an Gravatar gesendet. Bilder werden einen Tag zwischengespeichert.';

  @override
  String get avatarGravatarTooltip => 'Gravatar-Option anzeigen';

  @override
  String get avatarEnableGravatar => 'Gravatar aktivieren';

  @override
  String get avatarGravatarNotNow => 'Nicht jetzt';

  @override
  String get settingsDateRelative => 'Relativ';

  @override
  String get settingsDateLocal => 'Lokal';

  @override
  String get settingsDateIso => 'ISO 8601';

  @override
  String get historyDateNow => 'jetzt';

  @override
  String historyDateMinutes(int count) {
    return '$count Min.';
  }

  @override
  String historyDateHours(int count) {
    return '$count Std.';
  }

  @override
  String historyDateDays(int count) {
    return '$count T.';
  }

  @override
  String get settingsMotion => 'Bewegung';

  @override
  String get settingsMotionReduce => 'Bewegung reduzieren';

  @override
  String get settingsMotionFull => 'Volle Bewegung';

  @override
  String settingsActiveRepository(String name) {
    return 'Aktives Repository: $name';
  }

  @override
  String get settingsNoActiveRepository =>
      'Öffne ein Repository, um Repository-Einstellungen zu verwalten.';

  @override
  String get settingsResetRepositoryAction =>
      'Repository-Einstellungen zurücksetzen';

  @override
  String get settingsResetRepositoryTitle =>
      'Repository-Einstellungen zurücksetzen?';

  @override
  String settingsResetRepositoryConfirmation(String name) {
    return 'Gespeicherte Ansicht, Navigation, Filter und Entwurf für „$name“ zurücksetzen? Andere Repositories und globale Einstellungen bleiben unverändert.';
  }

  @override
  String get settingsSaveFailed =>
      'Die Einstellungen konnten nicht gespeichert werden. Es wurde kein Erfolg gemeldet.';

  @override
  String get settingsOpenLicenses => 'Lizenzen öffnen';

  @override
  String get shortcutSearch => 'Tastaturkürzel durchsuchen';

  @override
  String get shortcutConflictTitle => 'Kontextabhängige Tastaturkürzel';

  @override
  String shortcutConflictDetail(String shortcut, String commands) {
    return '$shortcut: $commands';
  }

  @override
  String get shortcutConflictWinner =>
      'Jede Taste führt den Befehl des fokussierten Seitenleistenabschnitts aus.';

  @override
  String get commandGroupCommands => 'Arbeitsbereich';

  @override
  String get commandGroupRepository => 'Repository';

  @override
  String get commandGroupSettings => 'Einstellungen';

  @override
  String get startupLoading => 'Wird gestartet…';

  @override
  String get startupFailed => 'Die App konnte nicht gestartet werden.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get welcomeTitle => 'Mit einem Repository beginnen';

  @override
  String get welcomeDetail =>
      'Öffne ein vorhandenes Git-Repository oder initialisiere ein leeres Ziel.';

  @override
  String get welcomeOpen => 'Öffnen…';

  @override
  String get welcomeClone => 'Klonen…';

  @override
  String get welcomeCreate => 'Erstellen…';

  @override
  String get openRepository => 'Repository öffnen';

  @override
  String get cloneRepository => 'Repository klonen';

  @override
  String get cloneSourceLabel => 'Repository-URL oder Pfad';

  @override
  String get cloneSourceDescription =>
      'Ein Repository von einem Server oder aus einem anderen Ordner kopieren. Wohin, wählst du im nächsten Schritt.';

  @override
  String get cloneSourceHint => 'https://example.com/team/projekt.git';

  @override
  String get chooseCloneDestination => 'Ziel auswählen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get cancelClone => 'Klonen abbrechen';

  @override
  String get cloneInvalidSource =>
      'Gib eine unterstützte Repository-URL oder einen absoluten lokalen Pfad ein.';

  @override
  String get cloneEmbeddedCredential =>
      'Entferne Passwort oder Token aus der Repository-URL.';

  @override
  String get cloneInvalidDestination => 'Wähle ein gültiges Zielverzeichnis.';

  @override
  String get cloneDestinationOccupied =>
      'Das Ziel ist nicht leer und wurde nicht verändert.';

  @override
  String get cloneAuthenticationRequired => 'Eine Anmeldung ist erforderlich.';

  @override
  String get cloneCredentialBrokerUnavailable =>
      'Die sichere Wiederholung mit Zugangsdaten ist auf dieser Plattform nicht verfügbar.';

  @override
  String get clonePasswordOrToken => 'Passwort oder Token';

  @override
  String get retryAuthentication => 'Anmeldung erneut versuchen';

  @override
  String get cloneHostKeyUntrusted =>
      'Dem SSH-Hostschlüssel wird nicht vertraut.';

  @override
  String get inspectHostKey => 'Hostschlüssel prüfen';

  @override
  String get hostKeyTitle => 'SSH-Hostschlüssel prüfen';

  @override
  String get hostKeyDescription =>
      'Prüfe, ob das der erwartete Server ist. Vertraue ihm nur, wenn der Fingerabdruck mit dem übereinstimmt, den sein Betreiber oder Hosting-Dienst veröffentlicht.';

  @override
  String get hostKeyServer => 'Server';

  @override
  String get hostKeyType => 'Schlüsseltyp';

  @override
  String get hostKeyFingerprint => 'Fingerabdruck';

  @override
  String get rejectHostKey => 'Ablehnen';

  @override
  String get trustHostKey => 'Vertrauen und erneut versuchen';

  @override
  String get hostKeyProbeFailed =>
      'Der SSH-Hostschlüssel konnte nicht geprüft werden.';

  @override
  String get hostKeyChallengeExpired =>
      'Die SSH-Hostschlüsselabfrage ist nicht mehr aktuell.';

  @override
  String get hostKeyWriteFailed =>
      'Die Datei mit vertrauenswürdigen Hosts konnte nicht sicher aktualisiert werden.';

  @override
  String get cloneTimedOut =>
      'Das Klonen wurde beendet, nachdem Git nicht mehr reagiert hat.';

  @override
  String get cloneCanceled =>
      'Das Klonen wurde abgebrochen. Ein unvollständiges Ziel blieb unverändert.';

  @override
  String get cloneFailed => 'Das Repository konnte nicht geklont werden.';

  @override
  String get initializeRepository => 'Repository initialisieren';

  @override
  String get initializeBareRepository => 'Bare-Repository initialisieren';

  @override
  String get initializeBareOption => 'Bare-Repository';

  @override
  String get initializeBareHelp =>
      'Enthält nur den Verlauf, keine Arbeitsdateien. Für ein gemeinsames Repository auf einem Server.';

  @override
  String get initializeDestinationHint =>
      'Erstellt ein leeres Git-Repository. Seinen Ordner wählst du im nächsten Schritt.';

  @override
  String get repositoryReady => 'Repository bereit';

  @override
  String get repositoryReadyDetail =>
      'Die kanonische Repository-Identität und der anfängliche Git-Status sind geladen.';

  @override
  String get recentRepositories => 'Zuletzt verwendete Repositories';

  @override
  String get noRecentRepositories =>
      'Noch keine erfolgreich geöffneten Repositories.';

  @override
  String get recentRepositoriesFilter =>
      'Zuletzt verwendete Repositories filtern';

  @override
  String get recentRepositoriesNoMatch =>
      'Kein zuletzt verwendetes Repository passt zum Filter.';

  @override
  String get repositoryOpenFailed =>
      'Das Repository konnte nicht geöffnet werden.';

  @override
  String get repositoryPathNotFound =>
      'Der ausgewählte Pfad ist nicht mehr vorhanden.';

  @override
  String get repositoryPermissionDenied =>
      'GitLama hat keine Berechtigung, den ausgewählten Pfad zu lesen.';

  @override
  String get repositoryNotRepository =>
      'Der ausgewählte Pfad befindet sich nicht in einem Git-Repository.';

  @override
  String get repositoryAlreadyExists =>
      'Das Ziel ist bereits ein Git-Repository.';

  @override
  String get destinationNotEmpty =>
      'Das Ziel ist nicht leer und wurde nicht verändert.';

  @override
  String get destinationNotDirectory =>
      'Das Ziel ist kein unterstütztes Verzeichnis.';

  @override
  String get gitUnavailable => 'Das installierte Git ist nicht verfügbar.';

  @override
  String get gitUnsupported =>
      'Die installierte Git-Version wird nicht unterstützt.';

  @override
  String get workspaceChanges => 'Änderungen';

  @override
  String get workspaceHistory => 'Verlauf';

  @override
  String get workspaceActivity => 'Aktivität';

  @override
  String get activityCopy => 'Aktivität kopieren';

  @override
  String get activityCopied => 'Aktivitätsbefehl und Ausgabe wurden kopiert.';

  @override
  String get toolbarBranch => 'Branch';

  @override
  String get toolbarMore => 'Mehr';

  @override
  String get workspaceRefresh => 'Aktualisieren';

  @override
  String get workspaceRefreshLocal => 'Lokale Ansicht aktualisieren';

  @override
  String get workspaceRefreshLocalHint =>
      'Lädt dieses Repository neu von der Festplatte. Fetch holt neue Commits von Remotes; Pull aktualisiert zusätzlich deinen Branch.';

  @override
  String get workspaceRefreshFailed =>
      'Repository konnte nicht aktualisiert werden.';

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
  String get workspaceEmptyHistory => 'Keine Commits gefunden.';

  @override
  String get historyNoCommitsYet => 'Noch keine Commits';

  @override
  String get historyOpenChanges => 'Änderungen öffnen';

  @override
  String get historyRetryLoad => 'Verlauf erneut laden';

  @override
  String historyEndOfHistory(int count) {
    return 'Ende des Verlaufs · $count Commits';
  }

  @override
  String historyNewUpstreamCommits(int count, String ref) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Commits auf $ref',
      one: '1 neuer Commit auf $ref',
    );
    return '$_temp0';
  }

  @override
  String get workspaceNoSelection =>
      'Wähle ein Element aus, um es zu untersuchen.';

  @override
  String get workingDiffFailed => 'Der Datei-Diff konnte nicht geladen werden.';

  @override
  String statusAccelerationOffer(int seconds) {
    return 'Git hat $seconds s gebraucht, um dieses Repository auf Änderungen zu prüfen. Mit Gits Untracked-Cache und Dateisystem-Monitor in den Einstellungen dieses Repositorys geht das deutlich schneller.';
  }

  @override
  String statusAccelerationOfferCacheOnly(int seconds) {
    return 'Git hat $seconds s gebraucht, um dieses Repository auf Änderungen zu prüfen. Mit Gits Untracked-Cache in den Einstellungen dieses Repositorys geht das schneller.';
  }

  @override
  String get statusAccelerationEnable => 'Beschleunigen';

  @override
  String get statusAccelerationDismiss => 'Nicht jetzt';

  @override
  String get statusAccelerationFailed =>
      'Git konnte die Einstellungen dieses Repositorys nicht ändern.';

  @override
  String get workingDiffWaitingForGit => 'Warte auf Git …';

  @override
  String get workingDiffWaitingForGitDetail =>
      'Git arbeitet noch an diesem Repository, zum Beispiel an einem großen Arbeitsverzeichnis. Der Diff erscheint, sobald Git antwortet.';

  @override
  String get workingDiffEmpty =>
      'Für diese Datei gibt es keine Zeilenänderungen.';

  @override
  String get workspaceLoadingRepository => 'Repository wird geöffnet…';

  @override
  String get workspaceUnavailableRepository =>
      'Dieses Repository ist nicht verfügbar.';

  @override
  String workspaceCloseTab(String name) {
    return '$name schließen';
  }

  @override
  String get workspaceOpenAnother => 'Weiteres Repository öffnen';

  @override
  String get workspaceStatusReady => 'Repository bereit';

  @override
  String get workspaceStatusLoading => 'Repository wird geladen';

  @override
  String get workspaceStatusFailed => 'Repository nicht verfügbar';

  @override
  String get workspaceWorkingTreeClean => 'Sauber';

  @override
  String get workspaceWorkingTreeDirty => 'Änderungen';

  @override
  String get workspaceWorkingTreeConflicted => 'Konflikte';

  @override
  String get workspaceWatchOverflow =>
      'Repository-Änderungen trafen schneller ein, als sie angezeigt werden konnten. Synchronisierung läuft…';

  @override
  String get workspaceWatchFailure =>
      'Automatische Repository-Aktualisierungen sind nicht verfügbar. Verwende „Aktualisieren“, um die Ansicht zu erneuern.';

  @override
  String get workspaceStatusFailure =>
      'Der Arbeitsbaumstatus konnte nicht gelesen werden. Andere Repository-Daten bleiben verfügbar.';

  @override
  String get workspaceRefsFailure =>
      'Branches und andere Referenzen konnten nicht gelesen werden. Andere Repository-Daten bleiben verfügbar.';

  @override
  String get workspaceDetachedHead =>
      'Es ist kein Branch ausgecheckt. Neue Commits gehören keinem Branch an, bis du einen erstellst oder wechselst.';

  @override
  String workspaceConflictCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien haben Konflikte.',
      one: '1 Datei hat Konflikte.',
    );
    return '$_temp0';
  }

  @override
  String get workspaceOperationMerge => 'Merge läuft';

  @override
  String get workspaceOperationRebase => 'Rebase läuft';

  @override
  String get workspaceOperationCherryPick => 'Cherry-Pick läuft';

  @override
  String get workspaceOperationRevert => 'Revert läuft';

  @override
  String get workspaceOperationBisect => 'Bisect läuft';

  @override
  String logbookRepeatedFetch(int count) {
    return 'Origin abgerufen ×$count';
  }

  @override
  String logbookDurationSeconds(String seconds) {
    return '$seconds s';
  }

  @override
  String get close => 'Schließen';

  @override
  String operationsRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laufen',
      one: '1 läuft',
    );
    return '$_temp0';
  }

  @override
  String operationsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fehlgeschlagen',
      one: '1 fehlgeschlagen',
    );
    return '$_temp0';
  }

  @override
  String operationsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count benötigen Aufmerksamkeit',
      one: '1 benötigt Aufmerksamkeit',
    );
    return '$_temp0';
  }

  @override
  String get operationsFilterAll => 'Alle';

  @override
  String get operationsFilterUser => 'Benutzer';

  @override
  String get operationsFilterBackground => 'Hintergrund';

  @override
  String get operationsDismiss => 'Ausblenden';

  @override
  String get operationsDismissAll => 'Alle ausblenden';

  @override
  String get operationsDetails => 'Details';

  @override
  String get operationsEmpty => 'Keine passenden Vorgänge';

  @override
  String get operationsDetailsUnavailable =>
      'Für diesen Vorgang sind keine Befehlsdetails verfügbar.';

  @override
  String get operationsDetailsExpired =>
      'Diese Befehlsdetails sind nicht mehr verfügbar.';

  @override
  String get operationsDetailsLoadFailed =>
      'Befehlsdetails konnten nicht geladen werden.';

  @override
  String get historyWindowFailed =>
      'Das Inspektionsfenster konnte nicht geöffnet werden.';

  @override
  String get operationRefresh => 'Repository aktualisieren';

  @override
  String get operationInitialize => 'Repository initialisieren';

  @override
  String get operationClone => 'Repository klonen';

  @override
  String get operationFetch => 'Abrufen';

  @override
  String get operationPull => 'Pullen';

  @override
  String get operationPush => 'Pushen';

  @override
  String get operationOther => 'Git-Vorgang';

  @override
  String get operationPhaseCounting => 'Objekte zählen';

  @override
  String get operationPhaseCompressing => 'Objekte komprimieren';

  @override
  String get operationPhaseReceiving => 'Objekte empfangen';

  @override
  String get operationPhaseResolving => 'Deltas auflösen';

  @override
  String get operationPhaseUpdatingFiles => 'Dateien aktualisieren';

  @override
  String get operationPhaseFiltering => 'Dateiinhalte laden';

  @override
  String get operationPhaseRebasing => 'Rebase';

  @override
  String operationPhaseProgress(String phase, int percent) {
    return '$phase $percent %';
  }

  @override
  String operationPercent(int percent) {
    return '$percent %';
  }

  @override
  String operationRunningDetail(String operation, String detail) {
    return '$operation · $detail';
  }

  @override
  String get operationStateRunning => 'Läuft';

  @override
  String get operationStateSucceeded => 'Erfolgreich';

  @override
  String get operationStateFailed => 'Fehlgeschlagen';

  @override
  String get operationStateCanceled => 'Abgebrochen';

  @override
  String get operationRepositoryApplication => 'Anwendung';

  @override
  String get commandPaletteTitle => 'Befehle';

  @override
  String get commandPaletteSearch => 'Befehle durchsuchen';

  @override
  String commandPaletteNoMatch(String query) {
    return 'Kein Befehl entspricht „$query“';
  }

  @override
  String get shortcutReferenceTitle => 'Tastaturkürzel';

  @override
  String get commandRepositoryRequired =>
      'Öffne ein Repository, um diesen Befehl zu verwenden';

  @override
  String get commandFeatureUnavailable =>
      'Diese Aktion ist im aktuellen Build nicht verfügbar';

  @override
  String get commandContextUnavailable =>
      'Dieser Befehl benötigt eine passende Auswahl oder einen aktiven Editor';

  @override
  String get commandInspectIndexLock =>
      'Sperrdatei von Git prüfen (index.lock)…';

  @override
  String get commandCreateBranch => 'Branch erstellen…';

  @override
  String get commandRenameBranch => 'Branch umbenennen…';

  @override
  String get commandDeleteBranch => 'Branch löschen…';

  @override
  String get commandDeleteRemoteBranch => 'Remote-Branch löschen…';

  @override
  String get commandCheckoutBranch => 'Branch auschecken…';

  @override
  String get commandAddRemote => 'Remote hinzufügen…';

  @override
  String get commandEditRemote => 'Remote-URL ändern…';

  @override
  String get commandRenameRemote => 'Remote umbenennen…';

  @override
  String get commandRemoveRemote => 'Remote entfernen…';

  @override
  String get commandCreateTag => 'Tag erstellen…';

  @override
  String get commandDeleteTag => 'Tag löschen…';

  @override
  String get commandCloseRepositoryTab => 'Repository-Tab schließen';

  @override
  String get commandNextPane => 'Nächster Bereich';

  @override
  String get commandFind => 'Suchen';

  @override
  String get commandPushTag => 'Tag pushen…';

  @override
  String get commandResetBranch => 'Aktuellen Branch zurücksetzen…';

  @override
  String get refMutationNewName => 'Neuer Name';

  @override
  String get refMutationForceDelete =>
      'Auch löschen, wenn er nicht gemergt ist';

  @override
  String get refMutationCheckoutNewBranch => 'Neuen Branch auschecken';

  @override
  String get refMutationResetMode => 'Reset-Modus';

  @override
  String get refMutationResetSoft =>
      'Soft: Branch verschieben, Änderungen bleiben vorgemerkt';

  @override
  String get refMutationResetMixed =>
      'Mixed: Branch verschieben, Änderungen bleiben nicht vorgemerkt';

  @override
  String get refMutationResetHard =>
      'Hard: Branch verschieben, Änderungen an verfolgten Dateien verwerfen';

  @override
  String get refMutationName => 'Name';

  @override
  String get refMutationRemoteUrl => 'Remote-URL';

  @override
  String get refMutationRemoteUrlHidden =>
      'Die aktuelle URL enthält Zugangsdaten und wird nicht angezeigt. Gib die vollständige neue URL ein.';

  @override
  String get refMutationTagMessage => 'Anmerkung (optional)';

  @override
  String get gitCommandDetails => 'Details zum Git-Befehl';

  @override
  String secondsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sekunden',
      one: '1 Sekunde',
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
      other: '$countString Byte',
      one: '1 Byte',
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
  String get commandDetails => 'Befehlsdetails';

  @override
  String get pushOptions => 'Push-Optionen';

  @override
  String get integrationRunSummary =>
      'Dieses konfigurierte Werkzeug mit dem ausgewählten Repository-Kontext starten. Es kann Dateien oder externe Systeme verändern.';

  @override
  String get integrationDiffSummary =>
      'Die ausgewählten Änderungen im konfigurierten externen Diff-Werkzeug öffnen. Das Werkzeug erhält temporäre Dateipfade.';

  @override
  String get integrationMergeSummary =>
      'Die Datei mit Konflikten im konfigurierten Merge-Werkzeug öffnen. Das Ergebnis vor dem Fortfahren prüfen und speichern.';

  @override
  String hostingRemoveConfirm(String name) {
    return 'Hosting-Konto $name aus GitLama entfernen? Repository-Daten auf dem Server bleiben unverändert. Für Reviews und Issues muss das Konto erneut verbunden werden.';
  }

  @override
  String get rebasePreviewSummary =>
      'Deine Commits werden in dieser Reihenfolge neu angewendet. Sie erhalten neue Commit-IDs, und eventuell musst du unterwegs Konflikte lösen.';

  @override
  String get historyMergeSummary =>
      'Übernimmt die Änderungen des ausgewählten Branches in den aktuellen Branch. Dabei kann Git einen Merge-Commit erstellen.';

  @override
  String get stashPushSummary =>
      'Ausgewählte Änderungen in einem Stash speichern und aus dem Arbeitsbaum entfernen.';

  @override
  String get stashApplySummary =>
      'Änderungen aus dem Stash auf den Arbeitsbaum anwenden. Der Stash bleibt erhalten.';

  @override
  String get stashPopSummary =>
      'Änderungen aus dem Stash anwenden und ihn bei Erfolg entfernen.';

  @override
  String get stashDropSummary =>
      'Diesen Stash löschen. Seine Änderungen sind danach möglicherweise nicht mehr wiederherstellbar.';

  @override
  String get stashRenameSummary =>
      'Die Beschreibung dieses Stashs ändern. Gespeicherte Änderungen bleiben erhalten.';

  @override
  String get stashCheckoutSummary =>
      'Aktuelle Änderungen vorübergehend speichern, den Branch wechseln und die Änderungen erneut anwenden. Konflikte müssen eventuell gelöst werden.';

  @override
  String get bisectStartSummary =>
      'Die Suche nach dem Commit beginnen, der ein Problem eingeführt hat. Git checkt während der Tests verschiedene Commits aus.';

  @override
  String get bisectGoodSummary =>
      'Den aktuellen Commit als funktionsfähig markieren. Git checkt den nächsten zu testenden Commit aus.';

  @override
  String get bisectBadSummary =>
      'Den aktuellen Commit als fehlerhaft markieren. Git checkt den nächsten zu testenden Commit aus.';

  @override
  String get bisectSkipSummary =>
      'Diesen Commit überspringen und einen anderen zum Testen auschecken.';

  @override
  String get bisectResetSummary =>
      'Die Suche beenden und zum zuvor ausgecheckten Branch zurückkehren.';

  @override
  String get deleteTagRemotePrompt => 'Auch auf Remotes löschen';

  @override
  String get deleteTagRemoteAvailabilityHint =>
      'Der Tag auf einem Remote wird nur gelöscht, wenn er noch auf denselben Commit zeigt wie deiner. Auf diesem Computer bleibt der Tag, bis alle ausgewählten Remotes ihn gelöscht haben.';

  @override
  String get deleteRefOnRemoteWarning =>
      'Das löscht es auch auf dem Remote, wo andere es bereits abgerufen haben könnten.';

  @override
  String get deleteTagLocalFailedAfterRemote =>
      'Der Tag wurde auf den ausgewählten Remotes gelöscht, konnte aber lokal nicht gelöscht werden. Prüfe den Repository-Zustand vor einem erneuten Versuch.';

  @override
  String deleteTagRemoteFailed(String remote) {
    return 'Der Tag konnte auf $remote nicht gelöscht werden. Der lokale Tag bleibt erhalten. Prüfe zuvor bearbeitete Remotes vor einem erneuten Versuch.';
  }

  @override
  String refConfirmCreateBranch(String name) {
    return 'Lokalen Branch $name erstellen.';
  }

  @override
  String refConfirmCreateAndCheckoutBranch(String name) {
    return 'Lokalen Branch $name erstellen und dorthin wechseln. Nicht committete Änderungen bleiben im Arbeitsbaum.';
  }

  @override
  String refConfirmRenameBranch(String name, String newName) {
    return 'Lokalen Branch $name in $newName umbenennen. Remote-Branches bleiben unverändert.';
  }

  @override
  String refConfirmDeleteBranch(String name) {
    return 'Lokalen Branch $name löschen. Remote-Branches bleiben unverändert.';
  }

  @override
  String refConfirmDeleteBranchAndUpstream(String name, String upstream) {
    return 'Lokalen Branch $name und seinen Upstream $upstream auf dem Remote löschen.';
  }

  @override
  String refMutationDeleteUpstream(String upstream) {
    return 'Auch $upstream löschen';
  }

  @override
  String get refMutationDeleteUpstreamHelp =>
      'Wird nur gelöscht, wenn er sich seit dem letzten Fetch nicht verändert hat.';

  @override
  String deleteBranchUpstreamFailed(String upstream) {
    return 'Der lokale Branch wurde gelöscht, aber $upstream konnte auf dem Remote nicht gelöscht werden. Führe einen Fetch aus und prüfe den Remote-Branch vor einem erneuten Versuch.';
  }

  @override
  String refConfirmCheckoutBranch(String name) {
    return 'Zu lokalem Branch $name wechseln. Dateien im Arbeitsbaum können sich ändern.';
  }

  @override
  String refConfirmCreateTag(String name) {
    return 'Lokalen Tag $name erstellen. Er wird nicht automatisch veröffentlicht.';
  }

  @override
  String refConfirmDeleteTagLocal(String name) {
    return 'Lokalen Tag $name löschen. Tags auf Remotes bleiben unverändert.';
  }

  @override
  String refConfirmDeleteTagRemotes(String name, String remotes) {
    return 'Tag $name auf $remotes und danach lokal löschen. Andere Personen könnten ihn bereits abgerufen haben.';
  }

  @override
  String refConfirmAddRemote(String name) {
    return 'Remote $name zu diesem Repository hinzufügen. Dateien und Daten auf dem Server bleiben unverändert.';
  }

  @override
  String refConfirmEditRemote(String name) {
    return 'URL von Remote $name ändern. Künftige Übertragungen verwenden die neue Adresse.';
  }

  @override
  String refConfirmRenameRemote(String name, String newName) {
    return 'Remote $name in $newName umbenennen. Seine Remote-Branches und die Upstreams, die es nutzen, gehen auf den neuen Namen über.';
  }

  @override
  String refConfirmRemoveRemote(String name) {
    return 'Remote $name aus diesem Repository entfernen. Der Server und seine Branches bleiben für andere verfügbar.';
  }

  @override
  String get refConfirmResetSoft =>
      'Aktuellen Branch zum gewählten Commit verschieben. Vorgemerkte und lokale Änderungen bleiben erhalten.';

  @override
  String get refConfirmResetMixed =>
      'Aktuellen Branch verschieben und vorgemerkte Änderungen zurücksetzen. Dateien im Arbeitsbaum bleiben erhalten.';

  @override
  String get refConfirmResetHard =>
      'Aktuellen Branch verschieben und vorgemerkte sowie lokale Änderungen an verfolgten Dateien verwerfen. Die verworfenen Änderungen gehen verloren.';

  @override
  String get refMutationWarningDirty =>
      'Der Arbeitsbaum enthält nicht gespeicherte Änderungen.';

  @override
  String get refMutationWarningDetached => 'Es ist kein Branch ausgecheckt.';

  @override
  String get refMutationWarningPublished =>
      'Dieser Branch scheint auf einem Remote vorhanden zu sein.';

  @override
  String get refMutationWarningOtherWorktree =>
      'Ein anderer Arbeitsbaum hat diesen Branch ausgecheckt.';

  @override
  String get refMutationWarningDestructiveReset =>
      'Ein Hard Reset verwirft alle vorgemerkten und nicht vorgemerkten Änderungen an verfolgten Dateien.';

  @override
  String get refMutationCompleted => 'Git-Operation abgeschlossen.';

  @override
  String get refMutationStale =>
      'Das Repository wurde geändert. Prüfe die Aktion erneut.';

  @override
  String get refMutationFailed => 'Git konnte die Aktion nicht abschließen.';

  @override
  String get refMutationWarningResult =>
      'Git hat die Aktion abgeschlossen, aber die Ansicht konnte nicht aktualisiert werden.';

  @override
  String get commandCreateStash => 'Stash erstellen…';

  @override
  String get commandAddWorktree => 'Arbeitsbaum hinzufügen…';

  @override
  String get commandTrackLfsPattern => 'LFS-Muster verfolgen…';

  @override
  String get commandAddIntegration => 'Integration hinzufügen…';

  @override
  String get indexLockNotFound => 'Es wurde keine Git-Sperrdatei gefunden.';

  @override
  String get indexLockConfirmationTitle => 'Sperrdatei von Git entfernen?';

  @override
  String indexLockConfirmation(String size) {
    return 'Stelle zuerst sicher, dass kein anderes Git-Programm in diesem Repository arbeitet. Dadurch wird die Sperrdatei von Git ($size) entfernt, nicht deine vorgemerkten Änderungen. Das Entfernen einer noch verwendeten Sperre kann das Repository beschädigen. Der unterbrochene Befehl wird nicht automatisch erneut ausgeführt.';
  }

  @override
  String get indexLockRemove => 'Sperre entfernen';

  @override
  String get indexLockRemoved =>
      'Die Sperrdatei von Git wurde entfernt. Der unterbrochene Befehl wurde nicht erneut ausgeführt.';

  @override
  String get indexLockChanged =>
      'Die Sperrdatei hat sich nach der Prüfung geändert. Prüfe sie vor dem Entfernen erneut.';

  @override
  String get indexLockActiveOperation =>
      'Die Sperre kann nicht entfernt werden, während Repository-Arbeit aktiv ist.';

  @override
  String get indexLockUnavailable =>
      'Die Sperrdatei von Git konnte nicht sicher geprüft oder entfernt werden.';

  @override
  String get galleryTitle => 'GitLama-Komponentengalerie';

  @override
  String get galleryOpenRepository => 'Repository öffnen';

  @override
  String get galleryUnavailableAction =>
      'Nicht verfügbare Aktion mit einer absichtlich langen Beschriftung';

  @override
  String get galleryUnavailableReason => 'Kein Repository ist geöffnet';

  @override
  String get galleryLoadingRepository => 'Repository wird geladen';

  @override
  String get galleryRefresh => 'Aktualisieren';

  @override
  String get galleryWorkspaceMenu => 'Arbeitsbereichsmenü';

  @override
  String get galleryHistory => 'Verlauf';

  @override
  String get galleryChanges => 'Änderungen';

  @override
  String get galleryActivity => 'Aktivität';

  @override
  String get galleryBranchRow =>
      'main  Eine lange Branch-Beschriftung, die zugänglich bleiben muss';

  @override
  String get galleryCurrent => 'Aktuell ausgecheckt';

  @override
  String get historyObjectIdCopied => 'Vollständiger Wert kopiert.';

  @override
  String get historyHashCopied => 'Kopiert';

  @override
  String get historyCopyObjectId => 'Commit-SHA kopieren';

  @override
  String get historyCopySubject => 'Commit-Betreff kopieren';

  @override
  String get menuCommitHashCopied => 'Commit-Hash kopiert.';

  @override
  String get menuCommitSubjectCopied => 'Commit-Betreff kopiert.';

  @override
  String get menuNameCopied => 'Name kopiert.';

  @override
  String historyWorkingTreeChanges(int count, int staged) {
    return 'Nicht committete Änderungen · $count Dateien · $staged vorgemerkt';
  }

  @override
  String historyWorkingTreeConflicts(int count) {
    return 'Konflikte · $count Dateien · Konfliktlösung öffnen';
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
    return 'Verlaufszeile. Betreff: $subject. Autor: $author. Commit: $objectId. Datum: $date. Spur $lane. Referenzen: $references. $overflow weitere Referenzen.';
  }

  @override
  String get historySearchHint => 'Commits durchsuchen';

  @override
  String get searchClear => 'Suche leeren';

  @override
  String get historyApplyFilter => 'Filter anwenden';

  @override
  String get historyBranchFilter => 'Branches';

  @override
  String historyBranchFilterCount(int count) {
    return 'Branches ($count)';
  }

  @override
  String get historyBranchFilterTooltip => 'Graph nach Branches filtern';

  @override
  String get historyBranchFilterSearch => 'Branch suchen';

  @override
  String get historyBranchFilterNoMatches => 'Keine passenden Branches.';

  @override
  String get historyBranchFilterFocus => 'Nur diesen Branch anzeigen';

  @override
  String get historyBranchFilterAdd => 'Zum Graph-Filter hinzufügen';

  @override
  String get historyBranchFilterRemove => 'Aus dem Graph-Filter entfernen';

  @override
  String get historyBranchFilterShowAll => 'Alle Branches anzeigen';

  @override
  String get historyBranchFilterCurrent => 'Aktueller Branch';

  @override
  String historyBranchFilterSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Branches angezeigt',
      one: '1 Branch angezeigt',
      zero: 'Alle Branches angezeigt',
    );
    return '$_temp0';
  }

  @override
  String get historyBranchFilterHelp =>
      'Klicken zum Hinzufügen oder Entfernen. Doppelklick oder Eingabetaste zeigt nur einen.';

  @override
  String get historyBranchFilterShown => 'Im Graph angezeigt';

  @override
  String get historyBranchFilterNoCommits =>
      'Keine Commits passen zum Branch-Filter.';

  @override
  String get historySearchScopes => 'Suchfelder';

  @override
  String get historySearchHash => 'Commit-Hash';

  @override
  String get historySearchMessage => 'Nachricht';

  @override
  String get historySearchAuthor => 'Autor';

  @override
  String get historySearchPath => 'Geänderter Pfad';

  @override
  String historyAcceptedFilter(String filter) {
    return 'Akzeptierter Filter: $filter';
  }

  @override
  String historyPendingFilter(String filter) {
    return 'Suche: $filter';
  }

  @override
  String get historyViewOptions => 'Ansichtsoptionen';

  @override
  String get historyShowOtherRefs => 'Andere Refs anzeigen';

  @override
  String get historyTargetOutsideRefScope =>
      'Der Verlauf zeigt diesen Commit nicht. Commits, die nur andere Refs erreichen, etwa Notes oder Checkpoints anderer Werkzeuge, sind ausgeblendet.';

  @override
  String get historyTargetNotShown =>
      'Der Verlauf zeigt diesen Commit nicht. Keine Ref erreicht ihn.';

  @override
  String get historySelectionFilteredOut =>
      'Der ausgewählte Commit liegt außerhalb dieses Ergebnisses. Die Auswahl bleibt erhalten.';

  @override
  String get historyFilterFailed =>
      'Der Filter konnte nicht angewendet werden. Das vorherige Ergebnis bleibt sichtbar.';

  @override
  String get historyCollapseSelected =>
      'Ausgewählten Merge ein- oder ausklappen';

  @override
  String historyCollapsedCount(int count) {
    return '$count Commits eingeklappt';
  }

  @override
  String get historyReflog => 'Reflog';

  @override
  String get historyGraph => 'Graph';

  @override
  String get historyHeadReference => 'HEAD';

  @override
  String get repositoryDropPrompt =>
      'Repository-Ordner hier ablegen, um sie zu öffnen';

  @override
  String repositoryDropSummary(int opened, int rejected, int failed) {
    return '$opened Repositorys geöffnet. $rejected Elemente abgelehnt, die keine Ordner sind. $failed Ordner konnten nicht geöffnet werden.';
  }

  @override
  String get historyReflogRetainedFailure =>
      'Die Reflog-Aktualisierung ist fehlgeschlagen. Zuvor geladene Reflog-Einträge bleiben verfügbar.';

  @override
  String get historyReflogEmpty => 'Keine Reflog-Einträge verfügbar.';

  @override
  String get historyNavigateBack => 'Zurück in der Dateiinspektion';

  @override
  String get historyNavigateForward => 'Vorwärts in der Dateiinspektion';

  @override
  String get historyTreeBinaryFile =>
      'Diese Datei kann nicht als Text angezeigt werden.';

  @override
  String get historyTreeFileTooLarge =>
      'Diese Datei ist zu groß für die Vorschau.';

  @override
  String get historyTreeEmptyFile => 'Diese Datei ist leer.';

  @override
  String get historyTreeFileFailed =>
      'Die Datei konnte nicht aus dem ausgewählten Commit geladen werden.';

  @override
  String get historyAuthor => 'Autor';

  @override
  String get historyCoAuthors => 'Mitautoren';

  @override
  String get historyCommitter => 'Committer';

  @override
  String get historyCommitDate => 'Commit-Datum';

  @override
  String get historyBlameBefore => 'Vor diese Änderung gehen';

  @override
  String blameAgeMinutes(int count) {
    return '$count Min.';
  }

  @override
  String blameAgeHours(int count) {
    return '$count Std.';
  }

  @override
  String blameAgeDays(int count) {
    return '$count T';
  }

  @override
  String blameAgeMonths(int count) {
    return '$count Mon.';
  }

  @override
  String blameAgeYears(int count) {
    return '$count J';
  }

  @override
  String get historyChangedFilesShort => 'Geändert';

  @override
  String historyFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String get historyFileActions => 'Dateiaktionen';

  @override
  String get historyBlame => 'Zeilenzuordnung';

  @override
  String get historyPathHistory => 'Pfadverlauf';

  @override
  String historyRenamedFrom(String path) {
    return 'umbenannt von $path';
  }

  @override
  String get historyInspectionLoading => 'Inspektionszeile wird geladen…';

  @override
  String get historyRestoreFile => 'Diese Version wiederherstellen';

  @override
  String historyRestorePreview(String path) {
    return 'Deine aktuelle Datei $path wird durch ihre Version aus diesem Commit ersetzt. Ändert sich die Datei oder der ausgecheckte Commit vorher, passiert nichts.';
  }

  @override
  String get historyRestoreNoCurrentFile => 'Nicht vorhanden';

  @override
  String get historyRestoreCurrentSize => 'Aktuelle Datei';

  @override
  String get historyRestoreSourceSize => 'Version in diesem Commit';

  @override
  String get historyRestoreConfirm => 'Datei wiederherstellen';

  @override
  String get historyRestoreSucceeded =>
      'Die Datei wurde aus dem ausgewählten Commit wiederhergestellt.';

  @override
  String get historyRestoreStale =>
      'Die Datei oder der aktuelle Commit hat sich geändert. Es wurde nichts wiederhergestellt; erstelle eine neue Vorschau.';

  @override
  String get historyRestoreReconciled =>
      'Die Datei wurde wiederhergestellt, aber die Repository-Aktualisierung erfordert Aufmerksamkeit.';

  @override
  String get historyRestoreOutcomeUncertain =>
      'Git hat die Datei möglicherweise geändert. Prüfe den Arbeitsbaum vor einem erneuten Versuch.';

  @override
  String get historyRestoreFailed =>
      'Die Datei konnte nicht wiederhergestellt werden.';

  @override
  String get diffSearchHint => 'Im Diff suchen';

  @override
  String get diffPreviousMatch => 'Vorheriger Treffer';

  @override
  String get diffNextMatch => 'Nächster Treffer';

  @override
  String get diffCaseSensitive => 'Groß-/Kleinschreibung beachten';

  @override
  String findMatchPosition(int current, int total) {
    return '$current von $total';
  }

  @override
  String findMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer',
      one: '1 Treffer',
    );
    return '$_temp0';
  }

  @override
  String get findNoMatches => 'Keine Treffer';

  @override
  String get findInFileHint => 'In Datei suchen';

  @override
  String get loading => 'Wird geladen…';

  @override
  String get diffPreviousHunk => 'Vorheriger Block';

  @override
  String get diffNextHunk => 'Nächster Block';

  @override
  String get diffSideBySide => 'Diff nebeneinander';

  @override
  String get diffUnified => 'Unified Diff';

  @override
  String get diffContextLines => 'Kontextzeilen';

  @override
  String diffContextValue(int count) {
    return '$count Kontextzeilen';
  }

  @override
  String get diffShowMoreLines => 'Weitere Zeilen anzeigen';

  @override
  String get diffCollapseFile => 'Datei einklappen';

  @override
  String get diffExpandFile => 'Datei ausklappen';

  @override
  String get diffWhitespace => 'Leerraumvergleich wechseln';

  @override
  String get diffWrap => 'Lange Zeilen umbrechen';

  @override
  String get diffIndicators => 'Plus- und Minuszeichen anzeigen';

  @override
  String get diffMinimap => 'Diff-Minimap anzeigen';

  @override
  String get diffAllFiles => 'Alle geänderten Dateien anzeigen';

  @override
  String get diffNoNewline => 'Kein Zeilenumbruch am Dateiende';

  @override
  String get diffBinaryFallback =>
      'Binärinhalt – Textvergleich ist nicht verfügbar';

  @override
  String get showBinaryAsText => 'Als Text anzeigen';

  @override
  String get diffImageFallback => 'Bild geändert – visuellen Vergleich öffnen';

  @override
  String get diffSubmoduleFallback => 'Submodule-Commit geändert';

  @override
  String diffModeOnlyFallback(String modes) {
    return 'Dateimodus geändert: $modes';
  }

  @override
  String get diffTooLargeFallback =>
      'Der Diff ist zu groß für einen eingebetteten Textvergleich';

  @override
  String get diffImageComparison => 'Bildvergleich';

  @override
  String get diffOldImage => 'Vorher';

  @override
  String get diffNewImage => 'Nachher';

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
  String get diffImageMissing => 'Auf dieser Seite ist kein Bild vorhanden.';

  @override
  String get diffImageDecodeFailed =>
      'Dieses Bild konnte nicht sicher dekodiert werden.';

  @override
  String get diffImageDecodeUnsupported =>
      'GitLama zeigt gängige Bildformate und SVGs ohne Text, Skripte, verknüpfte Dateien oder wiederverwendete Elemente.';

  @override
  String get diffImageDecodeMalformed => 'Die Datei ist kein gültiges Bild.';

  @override
  String get diffImageDecodeTooLarge =>
      'Das Bild ist größer, als GitLama in der Vorschau zeigt.';

  @override
  String get diffImageDecodeTimedOut =>
      'Das Dekodieren hat zu lange gedauert. Wähle die Datei erneut aus, um es noch einmal zu versuchen.';

  @override
  String get diffImageSideBySide => 'Nebeneinander';

  @override
  String get diffImageSwipe => 'Wischen';

  @override
  String get diffImageOnionSkin => 'Überblenden';

  @override
  String get diffImageDivider => 'Trennlinie';

  @override
  String get diffImageBlend => 'Mischung';

  @override
  String get diffImagePreparing => 'Dekodiertes Bild wird vorbereitet…';

  @override
  String get diffImageLoadFailed => 'Das Bild konnte nicht geladen werden.';

  @override
  String get diffEncoding => 'Textkodierung';

  @override
  String get diffEncodingUtf8 => 'UTF-8';

  @override
  String get diffEncodingLatin1 => 'ISO-8859-1-Ersatz';

  @override
  String get diffEncodingInvalid => 'Kein gültiges UTF-8 – Kodierung auswählen';

  @override
  String get diffRendererTitle => 'Diff-Renderer';

  @override
  String get diffRendererName => 'Anzeigename';

  @override
  String get diffRendererId => 'Kennung';

  @override
  String get diffRendererContainmentHelp =>
      'GitLama übergibt den Diff an das Programm und zeigt den Klartext an, den es zurückgibt. Argumente werden genau so ohne Shell übergeben, und die Ausgabe kann keine Links oder Steuerelemente hinzufügen.';

  @override
  String get diffRendererArgumentsHelp =>
      'Ein Argument pro Zeile, genau so übergeben, ohne Shell.';

  @override
  String get diffRendererNotConfigured => 'Kein Diff-Renderer ist konfiguriert';

  @override
  String get diffRendererRun => 'Diff rendern';

  @override
  String get diffRendererPreviewTitle => 'Diff-Renderer ausführen?';

  @override
  String get diffRendererRunSummary =>
      'GitLama übergibt den ausgewählten Diff an dieses Programm und zeigt den Klartext an, den es zurückgibt.';

  @override
  String get diffRendererCapabilityCommand => 'Prüfbefehl';

  @override
  String get diffRendererRenderCommand => 'Render-Befehl';

  @override
  String get diffRendererProtocol => 'Protokoll';

  @override
  String get diffRendererOutputFormat => 'Ausgabeformat';

  @override
  String get diffRendererTimeLimit => 'Zeitlimit';

  @override
  String get diffRendererOutputLimit => 'Ausgabelimit';

  @override
  String get diffRendererInputSize => 'Diff-Größe';

  @override
  String get diffRendererProgram => 'Programm';

  @override
  String get diffRendererValidatedTitle => 'Diesen Diff-Renderer speichern?';

  @override
  String get diffRendererValidatedSummary =>
      'Das Programm hat die Prüfung bestanden und kann Diffs als Klartext anzeigen. GitLama fragt vor jeder Ausführung nach.';

  @override
  String get diffRendererSave => 'Renderer speichern';

  @override
  String get diffRendererUseBuiltIn => 'Integrierte Ansicht verwenden';

  @override
  String get diffRendererPlainText =>
      'Inerte Klartextausgabe; die integrierte Diff-Ansicht bleibt verfügbar';

  @override
  String get diffRendererInvalidDefinition =>
      'Die Renderer-Konfiguration ist ungültig. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererUnavailable =>
      'Das Renderer-Programm ist nicht verfügbar. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererInvalidCapability =>
      'Der Renderer bietet die erforderliche Klartext-Fähigkeit nicht an. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererInputTooLarge =>
      'Der Diff überschreitet das Eingabelimit des Renderers. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererOutputTooLarge =>
      'Die Renderer-Ausgabe überschreitet ihr Limit. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererLaunchFailed =>
      'Der Renderer konnte nicht gestartet werden. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererProcessFailed =>
      'Der Renderer wurde mit einem Fehler beendet. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererTimedOut =>
      'Das Zeitlimit des Renderers wurde überschritten. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererCanceled =>
      'Der Renderer wurde abgebrochen. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get diffRendererStale =>
      'Der ausgewählte Diff hat sich geändert. Die integrierte Diff-Ansicht bleibt aktiv.';

  @override
  String get changesStaged => 'Vorgemerkte Änderungen';

  @override
  String get changesUnstaged => 'Nicht vorgemerkte Änderungen';

  @override
  String get changesListView => 'Dateien als Liste anzeigen';

  @override
  String get changesTreeView => 'Dateien als Baum anzeigen';

  @override
  String get changesPartial => 'teilweise';

  @override
  String get changesResizeCommit => 'Größe des Commit-Editors ändern';

  @override
  String get changesResizePanes =>
      'Bereiche für vorgemerkte und nicht vorgemerkte Änderungen skalieren';

  @override
  String get workspaceResizeDetail => 'Detailbereich skalieren';

  @override
  String get workspaceResizeSidebar => 'Repository-Seitenleiste skalieren';

  @override
  String get copyFilePath => 'Pfad kopieren';

  @override
  String get openFileExternal => 'In externem Editor öffnen';

  @override
  String openInFileBrowser(String browser) {
    return 'In $browser öffnen';
  }

  @override
  String get dragChangeToOtherList => 'In die andere Änderungsliste ziehen';

  @override
  String get filePathCopied => 'Dateipfad kopiert.';

  @override
  String get stageAll => 'Alle vormerken';

  @override
  String get unstageAll => 'Alle aus der Vormerkung nehmen';

  @override
  String get stageSelected => 'Auswahl vormerken';

  @override
  String get unstageSelected => 'Auswahl aus der Vormerkung nehmen';

  @override
  String get stageFile => 'Datei vormerken';

  @override
  String get unstageFile => 'Datei aus der Vormerkung nehmen';

  @override
  String get inspectChanges => 'Geänderte Zeilen auswählen';

  @override
  String get inspectChangesHelp =>
      'Hake einzelne geänderte Zeilen an oder eine Blocküberschrift für den ganzen Block.';

  @override
  String lineSelectionCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Zeilen ausgewählt',
      one: '1 Zeile ausgewählt',
      zero: 'Keine Zeilen ausgewählt',
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
      other: 'Mindestens $countString Zeilen ausgewählt',
      one: 'Mindestens 1 Zeile ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String lineSelectionSection(String header) {
    return 'Block $header';
  }

  @override
  String lineSelectionAdded(int line, String text) {
    return 'Hinzugefügte Zeile $line: $text';
  }

  @override
  String lineSelectionRemoved(int line, String text) {
    return 'Entfernte Zeile $line: $text';
  }

  @override
  String get stageLines => 'Ausgewählte Änderungen vormerken';

  @override
  String get unstageLines => 'Ausgewählte Änderungen aus der Vormerkung nehmen';

  @override
  String get stagingCompleted => 'Vorgemerkte Änderungen aktualisiert.';

  @override
  String get stagingStale =>
      'Die Dateien haben sich inzwischen geändert. Es wurde nichts vorgemerkt oder aus der Vormerkung genommen.';

  @override
  String get stagingFailed =>
      'Die vorgemerkten Änderungen konnten nicht aktualisiert werden.';

  @override
  String get stagingWarning =>
      'Die vorgemerkten Änderungen wurden aktualisiert, aber die Dateilisten konnten nicht neu geladen werden.';

  @override
  String get stagingEmpty => 'Auf dieser Seite gibt es keine Änderungen.';

  @override
  String get commandStageToggle => 'Vormerken oder aus der Vormerkung nehmen';

  @override
  String get commandDiffToggleLayout => 'Diff-Layout wechseln';

  @override
  String get commandDiffRenderConfigured =>
      'Diff mit konfiguriertem Renderer anzeigen';

  @override
  String get commandDiffToggleWrap => 'Diff-Zeilenumbruch umschalten';

  @override
  String get commandDiffNextHunk => 'Nächster Block';

  @override
  String get commandDiffPreviousHunk => 'Vorheriger Block';

  @override
  String get stagingLoadMore => 'Weitere Änderungen laden';

  @override
  String get commitSubject => 'Commit-Betreff';

  @override
  String get commitDescription => 'Beschreibung';

  @override
  String get commitCoauthors => 'Mitautoren';

  @override
  String get commitAuthor => 'Autor überschreiben';

  @override
  String get commitOptions => 'Commit-Optionen';

  @override
  String get commitAction => 'Commit';

  @override
  String commitToBranch(String branch) {
    return 'Commit auf $branch';
  }

  @override
  String commitAmendHash(String hash) {
    return '$hash ändern';
  }

  @override
  String changesStagedFilesCount(int count) {
    return '$count vorgemerkt';
  }

  @override
  String changesDragStageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien vormerken',
      one: '1 Datei vormerken',
    );
    return '$_temp0';
  }

  @override
  String changesDragUnstageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien entfernen → Arbeitsverzeichnis',
      one: '1 Datei entfernen → Arbeitsverzeichnis',
    );
    return '$_temp0';
  }

  @override
  String get commitAndPush => 'Commit & Push';

  @override
  String get commitAmendMessageFailed =>
      'Die letzte Commit-Nachricht konnte nicht geladen werden. Zum Wiederholen „Ändern“ aus- und einschalten oder eine Nachricht eingeben.';

  @override
  String get commitAmend => 'Ändern';

  @override
  String get commitSignOff => 'Sign-off';

  @override
  String get commitSkipHooks => 'Hooks überspringen';

  @override
  String get commitSpellcheck => 'Rechtschreibung';

  @override
  String get commitTemplate => 'Vorlage';

  @override
  String get commitRecent => 'Zuletzt verwendet';

  @override
  String get commitSigning => 'Commit-Signatur';

  @override
  String get commitSigningGit => 'Git-Konfiguration verwenden';

  @override
  String get commitSigningRequired => 'Signatur verlangen';

  @override
  String get commitSigningDisabled => 'Unsigniert committen';

  @override
  String get commitHookFailure => 'Commit-Hook fehlgeschlagen';

  @override
  String get commitSigningFailure => 'Commit-Signatur fehlgeschlagen';

  @override
  String get commitOtherFailure => 'Git hat den Commit abgelehnt';

  @override
  String commitFailureExitCode(int code) {
    return 'Exit-Code $code';
  }

  @override
  String get commitRetry => 'Erneut versuchen';

  @override
  String get commitSkipHooksConfirmTitle => 'Commit-Hooks überspringen?';

  @override
  String get commitSkipHooksConfirmBody =>
      'Hooks sind Prüfungen, die dieses Repository vor jedem Commit ausführt. Dieser Versuch überspringt sie. Gib SKIP ein, um zu bestätigen.';

  @override
  String get commitSkipHooksConfirmInput => 'SKIP eingeben';

  @override
  String commitCommittedObject(String objectId) {
    return '$objectId committed';
  }

  @override
  String get commitEmptySubject => 'Vor dem Commit einen Betreff eingeben.';

  @override
  String get commitNothingStaged =>
      'Stellen Sie Änderungen bereit, bevor Sie committen.';

  @override
  String get commitTrailingWhitespace => 'Der Betreff endet mit Leerraum.';

  @override
  String get commitPublishedWarning =>
      'Dieser Commit liegt auf einem Remote-Branch. Eine Änderung schreibt veröffentlichte Historie um.';

  @override
  String get commitConfirmAmend => 'Veröffentlichten Commit ändern';

  @override
  String get commitCompleted => 'Commit erstellt.';

  @override
  String get commitStale =>
      'Der aktuelle Commit oder die vorgemerkten Änderungen haben sich geändert. Es wurde nichts committet.';

  @override
  String get commitFailed =>
      'Git hat den Commit abgelehnt. Der Entwurf wurde behalten.';

  @override
  String get commitWarning =>
      'Commit erstellt, aber die Aktualisierung benötigt Aufmerksamkeit.';

  @override
  String get discardSelected => 'Auswahl verwerfen';

  @override
  String get discardAll => 'Alle verwerfen';

  @override
  String get cleanSelected => 'Auswahl bereinigen';

  @override
  String get discardFile => 'Dateiänderungen verwerfen';

  @override
  String get cleanFile => 'Neue Datei oder neuen Ordner löschen';

  @override
  String get discardLines => 'Ausgewählte Änderungen verwerfen';

  @override
  String get discardConfirmTitle => 'Änderungen endgültig verwerfen?';

  @override
  String get cleanConfirmTitle => 'Neue Dateien endgültig löschen?';

  @override
  String discardConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Das betrifft $count Dateien.',
      one: 'Das betrifft 1 Datei.',
    );
    return '$_temp0 Die Änderungen werden endgültig gelöscht.';
  }

  @override
  String get discardConfirmAction => 'Endgültig verwerfen';

  @override
  String get cleanConfirmAction => 'Endgültig löschen';

  @override
  String get discardCompleted => 'Die Änderungen wurden endgültig verworfen.';

  @override
  String get discardStale =>
      'Die bestätigten Pfade wurden geändert. Es wurde nichts verworfen.';

  @override
  String get discardFailed =>
      'Git konnte die bestätigten Änderungen nicht verwerfen.';

  @override
  String get discardWarning =>
      'Die Änderungen wurden verworfen, aber die Aktualisierung benötigt Aufmerksamkeit.';

  @override
  String get patchTitle => 'Patches';

  @override
  String get patchCreateDescription =>
      'Änderungen als Patch-Datei speichern, die du teilen oder anderswo anwenden kannst.';

  @override
  String get patchApplyDescription =>
      'Die Änderungen aus einer Patch-Datei auf die Dateien dieses Repositorys anwenden.';

  @override
  String get patchCreate => 'Patch erstellen';

  @override
  String get patchApply => 'Patch anwenden';

  @override
  String get patchWrite => 'Patch schreiben';

  @override
  String get patchChooseDestination => 'Ziel auswählen';

  @override
  String get patchChooseFile => 'Patch-Datei wählen';

  @override
  String get patchDestination => 'Ordner';

  @override
  String get patchDestinationUnset =>
      'Wähle einen Ordner, um zu sehen, was geschrieben wird.';

  @override
  String get patchScope => 'Enthält';

  @override
  String get patchFormat => 'Format';

  @override
  String get patchFilename => 'Dateiname';

  @override
  String get patchSize => 'Größe';

  @override
  String get patchFormatUnified => 'Unified Diff';

  @override
  String get patchFormatEmail => 'E-Mail-Patchserie';

  @override
  String get patchOverwriteWarning =>
      'In diesem Ordner gibt es bereits eine Datei mit diesem Namen. Ersetze sie oder wähle einen anderen Ordner.';

  @override
  String get patchOverwrite => 'Vorhandene Datei ersetzen';

  @override
  String get patchExportDone => 'Patch erstellt.';

  @override
  String get patchExportStale =>
      'Repository oder Ziel wurden geändert. Es wurde nichts geschrieben.';

  @override
  String get patchExportFailed => 'Der Patch konnte nicht erstellt werden.';

  @override
  String get patchTarget => 'Repository';

  @override
  String get patchCurrentRepository => 'Aktuelles Repository';

  @override
  String get patchFile => 'Patch-Datei';

  @override
  String get patchFileUnset => 'Wähle eine .patch- oder .diff-Datei.';

  @override
  String get patchCheck => 'Prüfung';

  @override
  String get patchCheckPassed => 'Lässt sich sauber anwenden';

  @override
  String get patchBinary => 'Binäre Änderungen';

  @override
  String patchFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien ändern sich',
      one: '1 Datei ändert sich',
    );
    return '$_temp0';
  }

  @override
  String get patchSavedTo => 'Gespeichert unter';

  @override
  String get patchYes => 'Ja';

  @override
  String get patchNo => 'Nein';

  @override
  String get patchApplyDone => 'Patch angewendet.';

  @override
  String get patchApplyStale =>
      'Patch oder Zieldateien wurden geändert. Es wurde nichts angewendet.';

  @override
  String get patchApplyFailed =>
      'Der Patch hat die Prüfungen nicht bestanden und wurde nicht angewendet.';

  @override
  String get patchApplyWarning =>
      'Der Patch wurde angewendet, aber die Ansicht ist eventuell nicht aktuell.';

  @override
  String get patchApplyOutcomeUncertain =>
      'Git hat den Patch möglicherweise teilweise angewendet. Prüfe deine Dateien, bevor du es erneut versuchst.';

  @override
  String get patchScopeLines => 'Ausgewählte Zeilen';

  @override
  String get patchScopeSelectedUnstaged =>
      'Ausgewählte nicht vorgemerkte Dateien';

  @override
  String get patchScopeSelectedStaged => 'Ausgewählte vorgemerkte Dateien';

  @override
  String get patchScopeUnstaged => 'Alle nicht vorgemerkten Änderungen';

  @override
  String get patchScopeStaged => 'Alle vorgemerkten Änderungen';

  @override
  String get patchScopeHead => 'Alle Änderungen seit dem letzten Commit';

  @override
  String get patchScopeCommit => 'Ausgewählter Commit';

  @override
  String get patchScopeRange => 'Ausgewählter Commit-Bereich';

  @override
  String get patchScopeCompare => 'Aktiver Vergleich';

  @override
  String get commandFetch => 'Abrufen…';

  @override
  String get commandFetchRemote => 'Remote abrufen';

  @override
  String get commandPull => 'Pullen…';

  @override
  String get commandPush => 'Pushen…';

  @override
  String get commandPushRemote => 'Zu Remote pushen';

  @override
  String get commandHostingCreatePullRequest =>
      'Pull Request im Browser erstellen';

  @override
  String get commandHistoryCompare => 'Commits vergleichen';

  @override
  String get commandHistoryBlame => 'Datei-Blame';

  @override
  String get commandHistoryPathHistory => 'Dateiverlauf';

  @override
  String get commandInteractiveRebase => 'Interaktiver Rebase…';

  @override
  String get commandRebaseSquash => 'Rebase-Eintrag squashen';

  @override
  String get commandRebaseFixup => 'Rebase-Eintrag als Fixup markieren';

  @override
  String get commandRebaseReword => 'Rebase-Eintrag umformulieren';

  @override
  String get commandRebaseDrop => 'Rebase-Eintrag verwerfen';

  @override
  String get commandOpenInEditor => 'Im Editor öffnen';

  @override
  String get commandOpenInTerminal => 'Im Terminal öffnen';

  @override
  String get transferRemote => 'Remote';

  @override
  String get transferBranch => 'Branch';

  @override
  String get transferTag => 'Tag';

  @override
  String get transferTagHelp =>
      'Der exakte Name des zu veröffentlichenden lokalen Tags';

  @override
  String get transferPullStrategy => 'Wie Änderungen zusammengeführt werden';

  @override
  String get transferFfOnly => 'Nur, wenn kein Merge nötig ist';

  @override
  String get transferFfPossible => 'Bei Bedarf mergen';

  @override
  String get transferRebase => 'Meine Commits obenauf setzen (Rebase)';

  @override
  String get transferAllowDirty =>
      'Mit meinen nicht committeten Änderungen pullen';

  @override
  String get transferAllowDirtyHelp =>
      'Es wird kein Stash erstellt. Git kann überlappende Änderungen oder einen Rebase ablehnen. Wähle Stashen und Wiederanwenden, um deine Änderungen zuerst zu sichern.';

  @override
  String get transferSetUpstream =>
      'Diesen Branch mit dem Remote-Branch verknüpfen';

  @override
  String get transferSetUpstreamHelp =>
      'Spätere Pulls und Pushes dieses Branches verwenden denselben Remote-Branch.';

  @override
  String get transferForceWithLease => 'Force-Push mit Lease';

  @override
  String get transferForceOption => 'Remote-Branch überschreiben';

  @override
  String get statusGlyphModified => 'Geändert';

  @override
  String get statusGlyphAdded => 'Hinzugefügt';

  @override
  String get statusGlyphDeleted => 'Gelöscht';

  @override
  String get statusGlyphRenamed => 'Umbenannt';

  @override
  String get statusGlyphCopied => 'Kopiert';

  @override
  String get statusGlyphConflict => 'Konflikt';

  @override
  String get statusGlyphUntracked => 'Nicht verfolgt';

  @override
  String get statusGlyphIgnored => 'Ignoriert';

  @override
  String syncAheadBehind(int ahead, int behind) {
    return '$ahead voraus, $behind zurück';
  }

  @override
  String transferAheadBehind(String ahead, String behind) {
    return 'Voraus $ahead · Zurück $behind';
  }

  @override
  String get transferCredentialsTitle => 'Authentifizierung erforderlich';

  @override
  String get transferCredentialsTransient =>
      'Die Zugangsdaten werden nur für diesen Versuch verwendet und nicht gespeichert.';

  @override
  String get transferUsername => 'Benutzername (optional)';

  @override
  String get transferPassword => 'Passwort';

  @override
  String get transferToken => 'Zugriffstoken';

  @override
  String get transferUseToken => 'Zugriffstoken verwenden';

  @override
  String transferCompleted(String ahead, String behind) {
    return 'Transfer abgeschlossen. Voraus $ahead · Zurück $behind.';
  }

  @override
  String get transferReconciledWarning =>
      'Der Transfer wurde abgeschlossen, aber die Ansicht konnte nicht aktualisiert werden.';

  @override
  String get transferFailed => 'Der Transfer ist fehlgeschlagen.';

  @override
  String get transferFailureInvalid => 'Die Transfer-Anfrage ist ungültig.';

  @override
  String get transferFailureDetached =>
      'Checke vor Pull oder Push einen Branch aus.';

  @override
  String get transferFailureUpstream =>
      'Wähle einen gültigen Remote und Branch. Force-Push benötigt außerdem eine abgerufene Lease.';

  @override
  String get transferFailureDirty =>
      'Committe oder stashe deine Änderungen zuerst oder wähle im Pull-Dialog, wie sie behandelt werden sollen.';

  @override
  String get transferFailureConflicted =>
      'Löse die aktuellen Konflikte vor dem Pull.';

  @override
  String get transferFailureStale =>
      'Der Repository-Stand hat sich nach der Vorschau geändert. Prüfe den Transfer erneut.';

  @override
  String get transferFailureAuthentication =>
      'Authentifizierung fehlgeschlagen. Mit Zugangsdaten erneut versuchen.';

  @override
  String get transferFailureCredentialBroker =>
      'Die sichere Wiederholung mit Zugangsdaten ist auf dieser Plattform nicht verfügbar.';

  @override
  String get transferFailureHostKey =>
      'Die SSH-Hostschlüsselprüfung ist fehlgeschlagen.';

  @override
  String get transferFailureRejected =>
      'Git konnte den Transfer nicht abschließen. Weitere Einzelheiten stehen im Vorgangsprotokoll.';

  @override
  String get transferFailureTimeout =>
      'Der Transfer wurde beendet, nachdem kein Fortschritt mehr gemeldet wurde.';

  @override
  String get transferFailureCanceled => 'Der Transfer wurde abgebrochen.';

  @override
  String get transferFailureMissingGit => 'Git konnte nicht gestartet werden.';

  @override
  String get transferFailureMissingObject =>
      'Git konnte Daten nicht lesen, die es für diese Übertragung braucht.';

  @override
  String get transferMissingObjectTitle => 'Fehlende Git-Objekte';

  @override
  String transferMissingObjectDetail(String remote) {
    return 'Git konnte benötigte Daten nicht lesen. Ein erneutes Abrufen von $remote kann sie wiederherstellen. Ein fehlgeschlagener Pull kann Dateien bereits geändert haben. Prüfe die Änderungen vor einem neuen Versuch. Das erneute Abrufen verwirft oder beendet diese Änderungen nicht.';
  }

  @override
  String get transferRefetchAction => 'Objekte erneut abrufen';

  @override
  String get transferRefetchCompleted =>
      'Objekte abgerufen. Prüfe Änderungen des fehlgeschlagenen Vorgangs vor einem neuen Versuch.';

  @override
  String get commandApplyStash => 'Stash anwenden…';

  @override
  String get commandPopStash => 'Stash anwenden und entfernen…';

  @override
  String get commandRenameStash => 'Stash umbenennen…';

  @override
  String get commandDropStash => 'Stash löschen…';

  @override
  String get commandAutoStashCheckout => 'Automatisch stashen und auschecken…';

  @override
  String stashSelected(String selector) {
    return 'Ausgewählter Stash: $selector';
  }

  @override
  String get stashMessage => 'Name (optional)';

  @override
  String get stashNewName => 'Neuer Stash-Name';

  @override
  String get stashIncludeUntracked => 'Neue Dateien einschließen';

  @override
  String get stashKeepIndex => 'Vorgemerkte Änderungen behalten';

  @override
  String get stashTargetBranch => 'Ziel-Branch';

  @override
  String get stashDropWarning =>
      'Das Löschen entfernt diesen Stash endgültig vom Stapel.';

  @override
  String get stashPreviewTitle => 'Stash prüfen';

  @override
  String get stashRecoveryRetained =>
      'Schlägt das Anwenden fehl, bleibt der Stash erhalten, damit nichts verloren geht.';

  @override
  String get stashCompleted => 'Stash-Vorgang abgeschlossen.';

  @override
  String get stashReconciledWarning =>
      'Der Vorgang wurde abgeschlossen, aber die Repository-Aktualisierung benötigt Aufmerksamkeit.';

  @override
  String get stashFailed => 'Der Stash-Vorgang ist fehlgeschlagen.';

  @override
  String get stashConflict =>
      'Der Stash hat Konflikte erzeugt. Öffne den Konfliktablauf, um fortzufahren.';

  @override
  String get stashConflictRetained =>
      'Der Stash hat Konflikte erzeugt und bleibt auf dem Stapel. Öffne den Konfliktablauf, um fortzufahren.';

  @override
  String get stashFailureInvalid => 'Die Stash-Anfrage ist ungültig.';

  @override
  String get stashFailureNothing =>
      'Git hat keine passenden Änderungen gefunden, die es stashen kann. Committe oder stashe Änderungen in Submodulen in deren eigenem Repository, bevor du auscheckst.';

  @override
  String get stashFailureMissing =>
      'Der ausgewählte Stash existiert nicht mehr.';

  @override
  String get stashFailureStale =>
      'Repository- oder Stash-Stand haben sich nach der Vorschau geändert. Prüfe den Vorgang erneut.';

  @override
  String get stashFailureCanceled => 'Der Stash-Vorgang wurde abgebrochen.';

  @override
  String get stashFailureTimeout =>
      'Der Stash-Vorgang hat das Zeitlimit überschritten.';

  @override
  String get stashFailureMissingGit => 'Git konnte nicht gestartet werden.';

  @override
  String get commandMergeBranch => 'Branch mergen…';

  @override
  String get commandIntegrateBranch => 'Branch integrieren…';

  @override
  String get commandRebaseBranch => 'Auf Branch rebasen…';

  @override
  String get commandCherryPickSelected => 'Ausgewählte Commits cherry-picken…';

  @override
  String get commandRevertSelected => 'Ausgewählte Commits rückgängig machen…';

  @override
  String get historyMutationSourceBranch => 'Quell-Branch';

  @override
  String get historyMutationMergeMode => 'Merge-Modus';

  @override
  String get historyMutationFastForwardPossible => 'Fast-Forward, wenn möglich';

  @override
  String get historyMutationFastForwardOnly => 'Nur Fast-Forward';

  @override
  String get historyMutationNoFastForward =>
      'Immer einen Merge-Commit erstellen';

  @override
  String get historyMutationSelectCommits =>
      'Wähle zuerst einen oder mehrere Commits im Verlauf aus.';

  @override
  String get historyMutationPublishedWarning =>
      'Ich verstehe, dass dadurch Commits zu einem veröffentlichten Branch hinzugefügt werden.';

  @override
  String get historyMutationAlreadyContained =>
      'Der aktuelle Branch enthält diese Änderungen bereits. Es muss nichts geändert werden.';

  @override
  String get historyMutationCanceling => 'Wird abgebrochen…';

  @override
  String get commandRepositoryBusy =>
      'Warte, bis der laufende Vorgang in diesem Repository abgeschlossen ist';

  @override
  String historyMutationBusyMerge(String source, String branch) {
    return '$source wird in $branch gemergt…';
  }

  @override
  String historyMutationBusyCherryPick(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Commits werden auf $branch cherry-gepickt…',
      one: '1 Commit wird auf $branch cherry-gepickt…',
    );
    return '$_temp0';
  }

  @override
  String historyMutationBusyRevert(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Commits werden auf $branch rückgängig gemacht…',
      one: '1 Commit wird auf $branch rückgängig gemacht…',
    );
    return '$_temp0';
  }

  @override
  String get conflictPredictionBusy =>
      'Wahrscheinliche Konflikte werden geprüft…';

  @override
  String rebaseBusy(String branch, String target) {
    return '$branch wird auf $target rebased…';
  }

  @override
  String restackBusy(String root) {
    return 'Branches auf $root werden neu aufgebaut…';
  }

  @override
  String get stashBusyPush => 'Änderungen werden gestasht…';

  @override
  String get stashBusyApply => 'Stash wird angewendet…';

  @override
  String get stashBusyPop => 'Stash wird angewendet und entfernt…';

  @override
  String get stashBusyDrop => 'Stash wird gelöscht…';

  @override
  String get stashBusyRename => 'Stash wird umbenannt…';

  @override
  String get stashBusyAutoStashCheckout =>
      'Änderungen werden gestasht und ausgecheckt…';

  @override
  String get branchIntegrationTitle => 'Branch integrieren';

  @override
  String branchIntegrationHint(String branch) {
    return 'Wähle, wie die Änderungen aus $branch in deinen aktuellen Branch kommen sollen.';
  }

  @override
  String get branchIntegrationRebaseAction => 'Rebasen…';

  @override
  String get branchIntegrationMergeAction => 'Mergen…';

  @override
  String get branchIntegrationRebaseDetailAny =>
      'Spielt deine Commits auf dem anderen Branch neu ab. Sie erhalten neue IDs, vermeide das also bei Commits, die andere schon haben.';

  @override
  String branchIntegrationRebaseDetail(String branch) {
    return 'Spielt deine Commits auf $branch neu ab. Sie erhalten neue IDs, vermeide das also bei Commits, die andere schon haben.';
  }

  @override
  String get branchIntegrationRebase => 'Rebase';

  @override
  String get branchIntegrationMergeDetail =>
      'Fügt einen Merge-Commit hinzu, der beide Verläufe zusammenführt. Deine Commits bleiben unverändert.';

  @override
  String get branchIntegrationMerge => 'Merge';

  @override
  String get branchIntegrationHintAny =>
      'Wähle, wie die Änderungen eines anderen Branches in deinen aktuellen Branch kommen sollen.';

  @override
  String get rebaseEditorTitle => 'Interaktiver Rebase';

  @override
  String rebaseInstructionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Commits, ältester zuerst',
      one: '1 Commit, ältester zuerst',
    );
    return '$_temp0';
  }

  @override
  String get rebasePublishedBadge => 'Veröffentlicht';

  @override
  String get rebaseReplacementMessage => 'Neue Commit-Nachricht';

  @override
  String get rebaseMoveUp => 'Anweisung nach oben verschieben';

  @override
  String get rebaseMoveDown => 'Anweisung nach unten verschieben';

  @override
  String get rebasePublishedWarning =>
      'Mir ist bewusst, dass dadurch veröffentlichter Verlauf umgeschrieben wird.';

  @override
  String get rebaseStart => 'Rebase starten';

  @override
  String get rebaseEditPlan => 'Rebase-Plan bearbeiten';

  @override
  String get rebasePreviewTitle => 'Rebase prüfen';

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
  String get rebaseCompleted => 'Rebase abgeschlossen.';

  @override
  String rebaseConflict(int count) {
    return 'Der Rebase wurde mit $count Konfliktpfad(en) angehalten.';
  }

  @override
  String get rebaseEditStop =>
      'Der Rebase wurde bei einer Edit-Anweisung angehalten.';

  @override
  String get rebaseInterrupted => 'Der Rebase ist angehalten.';

  @override
  String get rebaseStale =>
      'Der aktuelle Commit oder das Rebase-Ziel hat sich geändert. Prüfe einen neuen Plan.';

  @override
  String get rebaseFailed =>
      'Der interaktive Rebase wurde nicht abgeschlossen.';

  @override
  String get historyMutationCompleted => 'Verlaufsoperation abgeschlossen.';

  @override
  String historyMutationConflict(int count) {
    return 'Die Operation wurde mit $count Konfliktpfad(en) angehalten. Setze sie im Konfliktablauf fort.';
  }

  @override
  String get historyMutationInterrupted =>
      'Die Operation ist angehalten. Setze sie fort, überspringe sie oder brich sie ab.';

  @override
  String get historyMutationStale =>
      'Der Repository-Stand hat sich nach der Vorschau geändert. Prüfe die Operation erneut.';

  @override
  String get historyMutationReconciledWarning =>
      'Die Operation wurde abgeschlossen, aber die Ansicht konnte nicht aktualisiert werden.';

  @override
  String get historyMutationFailed =>
      'Die Verlaufsoperation ist fehlgeschlagen.';

  @override
  String get historyMutationFailureInvalid =>
      'Die Anfrage für die Verlaufsoperation ist ungültig.';

  @override
  String get historyMutationFailureDirty =>
      'Committe oder stashe Änderungen im Arbeitsbaum, bevor du den Verlauf änderst.';

  @override
  String get historyMutationFailureDetached =>
      'Checke einen Branch aus, bevor du den Verlauf änderst.';

  @override
  String get historyMutationFailureActive =>
      'Setze zuerst die aktuelle Git-Operation fort oder brich sie ab.';

  @override
  String get historyMutationFailurePublished =>
      'Bestätige die Warnung zum veröffentlichten Verlauf, bevor du fortfährst.';

  @override
  String get historyMutationFailureCanceled =>
      'Die Verlaufsoperation wurde abgebrochen.';

  @override
  String get conflictResolverTitle => 'Konflikte auflösen';

  @override
  String get conflictOperationMerge => 'Merge';

  @override
  String get conflictOperationRebase => 'Rebase';

  @override
  String get conflictOperationCherryPick => 'Cherry-Pick';

  @override
  String get conflictOperationRevert => 'Revert';

  @override
  String get conflictOperationSnapshot => 'Snapshot-Wiederherstellung';

  @override
  String get conflictOperationStash => 'Zwischengespeicherte Änderungen';

  @override
  String get conflictOperationStandalone => 'Nicht zusammengeführte Dateien';

  @override
  String conflictRegionNumber(int number) {
    return 'Konflikt $number';
  }

  @override
  String conflictFileProgress(int current, int total) {
    return 'Datei $current von $total';
  }

  @override
  String conflictStepProgress(int current, int total) {
    return 'Schritt $current von $total';
  }

  @override
  String conflictCurrent(String label) {
    return 'Aktuell: $label';
  }

  @override
  String conflictIncoming(String label) {
    return 'Eingehend: $label';
  }

  @override
  String get conflictAncestor => 'Gemeinsamer Vorfahr';

  @override
  String get conflictResult => 'Ergebnis';

  @override
  String get conflictTakeCurrent => 'Aktuelle übernehmen';

  @override
  String get conflictTakeIncoming => 'Eingehende übernehmen';

  @override
  String get conflictRemoveCurrent => 'Aktuelle entfernen';

  @override
  String get conflictRemoveIncoming => 'Eingehende entfernen';

  @override
  String get conflictRemoveBoth => 'Beide entfernen';

  @override
  String get conflictTakeBoth => 'Beide übernehmen';

  @override
  String get conflictUseCurrentFile => 'Aktuelle Datei verwenden';

  @override
  String get conflictUseIncomingFile => 'Eingehende Datei verwenden';

  @override
  String get conflictKeepDeletion => 'Löschung beibehalten';

  @override
  String get conflictUndoResolution => 'Auflösung rückgängig machen';

  @override
  String get conflictPreviousFile => 'Vorherige Datei';

  @override
  String get conflictNextFile => 'Nächste Datei';

  @override
  String get conflictContinue => 'Fortsetzen';

  @override
  String get conflictSkip => 'Überspringen';

  @override
  String get conflictAbort => 'Abbrechen';

  @override
  String get conflictAbortTitle => 'Git-Operation abbrechen?';

  @override
  String get conflictAbortMessage =>
      'Git stellt den Zustand von vor dem Start wieder her. Nicht gespeicherte Änderungen im Konflikteditor gehen verloren.';

  @override
  String get conflictSkipTitle => 'Diesen Schritt überspringen?';

  @override
  String get conflictSkipMessage =>
      'Git lässt den Commit aus, der gerade angewendet wird, und macht mit dem nächsten weiter.';

  @override
  String get conflictLoading => 'Konfliktzustand wird geladen…';

  @override
  String get conflictLoadFailed =>
      'Der Konfliktzustand konnte nicht geladen werden. Aktualisiere und prüfe das Repository vor dem Fortsetzen.';

  @override
  String get conflictSaveFailed =>
      'Das Ergebnis wurde außerhalb von GitLama geändert oder konnte nicht gespeichert werden. Der Konfliktzustand wurde neu geladen.';

  @override
  String get conflictContinueFailed =>
      'Git konnte diesen Schritt nicht abschließen.';

  @override
  String get conflictCompleted => 'Git-Operation abgeschlossen.';

  @override
  String get conflictAborted => 'Git-Operation abgebrochen.';

  @override
  String get conflictStoppedAgain =>
      'Git hat erneut angehalten, beim nächsten Konflikt oder Schritt.';

  @override
  String get conflictAllResolved =>
      'Alle Konfliktpfade sind aufgelöst. Setze fort, wenn du bereit bist.';

  @override
  String get conflictStandaloneResolved =>
      'Alle nicht zusammengeführten Dateien sind aufgelöst. Prüfe die Änderungen vor dem Commit.';

  @override
  String get conflictBinaryFile =>
      'Dies ist eine Binärdatei. Wähle eine vollständige Seite oder öffne ein externes Merge-Werkzeug.';

  @override
  String get conflictHugeFile =>
      'Diese Datei ist zu groß für den eingebauten Texteditor. Wähle eine vollständige Seite oder öffne ein externes Merge-Werkzeug.';

  @override
  String get conflictExternalTool => 'Externes Werkzeug öffnen';

  @override
  String get conflictExternalUnavailable =>
      'Die Übergabe an ein externes Merge-Werkzeug ist noch nicht verfügbar.';

  @override
  String get conflictEmptySide => 'Leere Datei';

  @override
  String conflictRegionsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ungelöste Bereiche',
      one: '1 ungelöster Bereich',
    );
    return '$_temp0';
  }

  @override
  String get conflictPreviousRegion => 'Vorheriger Konflikt';

  @override
  String get conflictNextRegion => 'Nächster Konflikt';

  @override
  String get conflictResolveFile => 'Datei als gelöst markieren';

  @override
  String get conflictReviewResult =>
      'Ergebnis prüfen oder bearbeiten und dann die Datei als gelöst markieren.';

  @override
  String get conflictSaving => 'Speichern…';

  @override
  String get conflictShowAncestor => 'Vorfahr anzeigen';

  @override
  String get conflictHideAncestor => 'Vorfahr ausblenden';

  @override
  String get rebaseAutosquash => 'Korrektur-Commits automatisch zusammenführen';

  @override
  String get rebaseAutosquashHint =>
      'Commits, deren Nachricht mit fixup! oder squash! beginnt, werden hinter den Commit verschoben, den sie korrigieren, und mit ihm zusammengeführt.';

  @override
  String get rebaseDragToSquash =>
      'Auf einen anderen Commit ziehen, um ihn zu squashen';

  @override
  String get rebaseDragToReorder => 'Ziehen zum Umsortieren';

  @override
  String rebaseAutosquashApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Korrektur-Commits wurden automatisch zusammengeführt.',
      one: '1 Korrektur-Commit wurde automatisch zusammengeführt.',
    );
    return '$_temp0';
  }

  @override
  String get fixupSuggestionAction => 'Fixup / Squash';

  @override
  String get fixupSuggestionFixup => 'Fixup-Commit erstellen';

  @override
  String get fixupSuggestionSquash => 'Squash-Commit erstellen';

  @override
  String get fixupSuggestionAmbiguous =>
      'Mehrere Commits haben diese Dateien geändert. Wähle den, zu dem deine Änderungen gehören.';

  @override
  String get fixupSuggestionPickHint =>
      'GitLama konnte nicht erkennen, welchen Commit diese Änderungen korrigieren. Wähle einen der Commits, die diese Dateien geändert haben.';

  @override
  String get fixupSuggestionPickTitle => 'Welchen Commit korrigiert das?';

  @override
  String get fixupSuggestionUnavailable =>
      'GitLama konnte nicht erkennen, welchen Commit diese Änderungen korrigieren.';

  @override
  String get fixupSuggestionFailed =>
      'Die Belege für den Basis-Commit konnten nicht geladen werden.';

  @override
  String get commandRestackBranches => 'Abhängige Branches neu aufbauen';

  @override
  String get restackChooseRoot => 'Wurzel des Stacks auswählen';

  @override
  String restackPreviewTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Branches neu aufbauen',
      one: '1 Branch neu aufbauen',
    );
    return '$_temp0';
  }

  @override
  String get restackIncompleteWarning =>
      'GitLama konnte nicht den ganzen Stack erfassen. Nur die hier aufgeführten Branches werden neu aufgebaut.';

  @override
  String get restackPublishedWarning =>
      'Mir ist bewusst, dass dadurch veröffentlichte Branches umgeschrieben werden und andere ihre Kopien anpassen müssen.';

  @override
  String get restackNothingToDo =>
      'Alle abhängigen Branches basieren bereits auf ihren aktuellen Eltern-Branches.';

  @override
  String restackCompleted(int count) {
    return '$count Branches wurden neu aufgebaut.';
  }

  @override
  String restackConflict(int completed, int total) {
    return 'Der Restack wurde nach $completed von $total Branches durch einen Konflikt angehalten. Löse ihn unter Änderungen und plane anschließend erneut.';
  }

  @override
  String restackPartial(int completed, int total) {
    return 'Der Restack wurde nach $completed von $total Branches angehalten. Plane erneut, um ohne Wiederholung abgeschlossener Umschreibungen fortzufahren.';
  }

  @override
  String get restackStale =>
      'Die Branch-Spitzen haben sich geändert. Prüfe einen neuen Restack-Plan.';

  @override
  String get restackCanceled =>
      'Der Restack wurde vor dem nächsten Branch abgebrochen.';

  @override
  String get restackFailed =>
      'Der Branch-Restack konnte nicht abgeschlossen werden.';

  @override
  String get namedSnapshotsTitle => 'Snapshots';

  @override
  String get namedSnapshotsEmpty => 'Noch keine Snapshots';

  @override
  String get namedSnapshotName => 'Name des Snapshots';

  @override
  String get namedSnapshotCreate => 'Snapshot erstellen';

  @override
  String get namedSnapshotInspect => 'Untersuchen';

  @override
  String get namedSnapshotRestore => 'Wiederherstellen';

  @override
  String get namedSnapshotBranch => 'Branch erstellen';

  @override
  String get namedSnapshotBranchTitle => 'Branch aus Snapshot erstellen';

  @override
  String get namedSnapshotBranchCreated =>
      'Branch wurde aus dem Snapshot erstellt.';

  @override
  String get namedSnapshotDeleteTitle => 'Snapshot löschen?';

  @override
  String namedSnapshotDeleteMessage(String name) {
    return '„$name“ löschen? Die darin gespeicherten Änderungen werden entfernt.';
  }

  @override
  String namedSnapshotRestoreTitle(String name) {
    return '„$name“ wiederherstellen?';
  }

  @override
  String get namedSnapshotPathsTruncated =>
      'Es ändern sich noch weitere Dateien, die hier nicht aufgeführt sind.';

  @override
  String get namedSnapshotAcknowledgeReplacement =>
      'Mir ist bewusst, dass meine aktuellen Änderungen ersetzt werden.';

  @override
  String get namedSnapshotNothingToCapture =>
      'Es gibt keine Änderungen zum Erfassen.';

  @override
  String get namedSnapshotMissing =>
      'Die gespeicherten Daten des Snapshots fehlen.';

  @override
  String get namedSnapshotCorrupt => 'Die Snapshotmetadaten sind beschädigt.';

  @override
  String get namedSnapshotDirtyConflict =>
      'Löse die aktuellen Konflikte, bevor du einen Snapshot erstellst.';

  @override
  String get namedSnapshotActiveOperation =>
      'Beende die aktive Git-Operation, bevor du einen Snapshot erstellst.';

  @override
  String get namedSnapshotStale =>
      'Das Repository hat sich geändert. Prüfe eine neue Wiederherstellungsvorschau.';

  @override
  String get namedSnapshotConflict =>
      'Die Wiederherstellung wurde bei Konflikten angehalten. Löse sie unter Änderungen.';

  @override
  String get namedSnapshotCanceled => 'Snapshotoperation abgebrochen.';

  @override
  String get namedSnapshotTooLarge =>
      'Die Snapshotmetadaten überschreiten die Sicherheitsgrenze.';

  @override
  String get namedSnapshotFailed => 'Die Snapshotoperation ist fehlgeschlagen.';

  @override
  String get detachedHead => 'Losgelöster HEAD';

  @override
  String compassDetachedAt(String hash) {
    return 'Losgelöst bei $hash';
  }

  @override
  String get delete => 'Löschen';

  @override
  String get loadMore => 'Mehr laden';

  @override
  String get repositoryExtensionsTitle => 'Repository-Erweiterungen';

  @override
  String get extensionWorktrees => 'Worktrees';

  @override
  String get extensionWorktreeLocked => 'Gesperrter Worktree';

  @override
  String get extensionWorktreeCurrent => 'Aktueller Worktree';

  @override
  String get extensionWorktreePath => 'Ordner für den Worktree';

  @override
  String get extensionWorktreeChooseFolder => 'Ordner auswählen…';

  @override
  String get extensionWorktreeChooseFolderFailure =>
      'Die Ordnerauswahl konnte nicht geöffnet werden. Erneut versuchen oder einen Pfad eingeben.';

  @override
  String get extensionWorktreeReference => 'Branch, Tag oder Commit';

  @override
  String get extensionWorktreeCreate => 'Worktree erstellen';

  @override
  String get extensionWorktreeDeleteTitle => 'Worktree löschen?';

  @override
  String extensionWorktreeDeleteBody(String path) {
    return 'Den verknüpften Worktree unter $path löschen? Worktrees mit ungespeicherten Änderungen oder Sperre werden abgelehnt.';
  }

  @override
  String get extensionSubmodules => 'Submodule';

  @override
  String get extensionNone => 'Keine';

  @override
  String get extensionInitialize => 'Initialisieren';

  @override
  String get extensionOpen => 'Öffnen';

  @override
  String get extensionUpdate => 'Aktualisieren';

  @override
  String get extensionSubmoduleRecorded => 'Beim aufgezeichneten Commit';

  @override
  String get extensionSubmoduleDifferent =>
      'Bei einem anderen Commit ausgecheckt';

  @override
  String get extensionSubmoduleUninitialized => 'Nicht initialisiert';

  @override
  String get extensionSubmoduleConflicted => 'Konflikt';

  @override
  String get extensionLfs => 'Git LFS';

  @override
  String get extensionLfsPull => 'Objekte abrufen';

  @override
  String get extensionLfsUnavailable =>
      'Git LFS ist nicht installiert oder nicht verfügbar.';

  @override
  String get extensionLfsPattern => 'Tracking-Muster';

  @override
  String get extensionLfsTrack => 'Verfolgen';

  @override
  String get extensionLfsUntrack => 'Nicht mehr verfolgen';

  @override
  String get extensionInspectPointer => 'Pointer prüfen';

  @override
  String get extensionLfsPointerTitle => 'LFS-Pointer';

  @override
  String get extensionLfsStatePointer => 'Pointer';

  @override
  String get extensionLfsStateMaterialized => 'Heruntergeladen';

  @override
  String get extensionLfsStateMissing => 'Fehlt';

  @override
  String get extensionLfsNotPointer =>
      'Diese Datei enthält ihren eigenen Inhalt, keinen LFS-Pointer.';

  @override
  String get extensionFailureInvalid => 'Die Erweiterungsanfrage ist ungültig.';

  @override
  String get extensionFailureUnavailable =>
      'Das erforderliche Werkzeug oder die Funktion ist nicht verfügbar.';

  @override
  String get extensionFailureDirty =>
      'Änderungen in diesem Arbeitsbaum zuerst committen oder stashen.';

  @override
  String get extensionFailureLocked =>
      'Diesen Arbeitsbaum vor dem Entfernen entsperren.';

  @override
  String get extensionFailureCurrent =>
      'Der aktuelle Arbeitsbaum kann nicht entfernt werden.';

  @override
  String get extensionFailureStale =>
      'Der Erweiterungsstatus hat sich geändert. Aktualisieren und erneut versuchen.';

  @override
  String get extensionFailureCanceled =>
      'Der Erweiterungsvorgang wurde abgebrochen.';

  @override
  String get extensionFailureTooLarge =>
      'Das Erweiterungsergebnis überschreitet die Sicherheitsgrenze.';

  @override
  String get extensionFailureGit =>
      'Der Repository-Erweiterungsvorgang ist fehlgeschlagen.';

  @override
  String get extensionWorktreeCreateDescription =>
      'Einen Branch oder Commit in einem eigenen Ordner auschecken, um parallel zu diesem daran zu arbeiten.';

  @override
  String get extensionLfsPointerDescription =>
      'Git LFS speichert den Inhalt dieser Datei auf einem Server. Das Repository enthält stattdessen diesen kleinen Verweis darauf.';

  @override
  String get extensionLfsPointerFile => 'Datei';

  @override
  String get extensionLfsPointerOid => 'SHA-256';

  @override
  String get extensionLfsPointerSize => 'Größe';

  @override
  String get conflictResolvedFiles => 'Aufgelöste Dateien';

  @override
  String get conflictUndoAll => 'Alle rückgängig machen';

  @override
  String get conflictSelectAll => 'Alle auswählen';

  @override
  String conflictSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String conflictBulkUseCurrent(int count) {
    return 'Aktuelle verwenden ($count)';
  }

  @override
  String conflictBulkUseIncoming(int count) {
    return 'Eingehende verwenden ($count)';
  }

  @override
  String get namedSnapshotFactBranch => 'Branch';

  @override
  String get namedSnapshotNoBranch => 'Kein Branch';

  @override
  String get namedSnapshotFactBase => 'Basiert auf Commit';

  @override
  String get namedSnapshotFactNewFiles => 'Neue Dateien';

  @override
  String get namedSnapshotFactId => 'Snapshot-ID';

  @override
  String get namedSnapshotsEmptyHelp =>
      'Speichere deine aktuellen Änderungen unter einem Namen, um später zu ihnen zurückzukehren.';

  @override
  String get restackRun => 'Branches neu aufbauen';

  @override
  String get integrationTitle => 'Integrationen';

  @override
  String get integrationDiscovered => 'Auf diesem Computer gefunden';

  @override
  String get integrationConfigured => 'Deine Werkzeuge und Befehle';

  @override
  String get integrationConfigure => 'Werkzeug oder Befehl hinzufügen';

  @override
  String get integrationKind => 'Verwenden als';

  @override
  String get integrationName => 'Name';

  @override
  String get integrationExecutable => 'Programm';

  @override
  String get integrationChooseExecutable => 'Programm auswählen';

  @override
  String get integrationArguments => 'Argumente';

  @override
  String get integrationArgumentsHelp =>
      'Ein Argument pro Zeile, genau so übergeben, wie es dasteht. Um Angaben einzufügen, setze repository, working_directory, file, current_branch oder selected_commit in geschweifte Klammern.';

  @override
  String get integrationExplicitShell => 'Über die System-Shell ausführen';

  @override
  String get integrationConfirm => 'Vor jedem Start fragen';

  @override
  String get integrationWait => 'Warten, bis es fertig ist';

  @override
  String get integrationTimeout => 'Zeitlimit (Sekunden)';

  @override
  String get integrationValidateSave => 'Prüfen und speichern';

  @override
  String get integrationPreviewTitle => 'Exakten Befehl prüfen';

  @override
  String get integrationRun => 'Ausführen';

  @override
  String get integrationEditor => 'Editor';

  @override
  String get integrationTerminal => 'Terminal';

  @override
  String get integrationFileManager => 'Dateimanager';

  @override
  String get integrationBrowser => 'Browser';

  @override
  String get integrationDiffTool => 'Diff-Werkzeug';

  @override
  String get integrationMergeTool => 'Merge-Werkzeug';

  @override
  String get integrationCustom => 'Benutzerdefinierter Befehl';

  @override
  String get integrationInvalid =>
      'Die Werkzeugdefinition oder Argumentvorlage ist ungültig.';

  @override
  String get integrationUnavailable =>
      'Die ausgewählte Programmdatei ist nicht verfügbar.';

  @override
  String get integrationMissingVariable =>
      'Eine erforderliche Befehlsvariable ist nicht verfügbar.';

  @override
  String get integrationStale =>
      'Der Repository-Status hat sich geändert. Den Befehl erneut prüfen.';

  @override
  String get integrationConfirmationRequired =>
      'Dieser Befehl erfordert eine ausdrückliche Bestätigung.';

  @override
  String get integrationTimedOut =>
      'Der Befehl hat sein Zeitlimit erreicht und wurde beendet.';

  @override
  String get integrationNonZero => 'Der Befehl hat einen Fehler gemeldet.';

  @override
  String get integrationLaunchFailed =>
      'Der Befehl konnte nicht gestartet oder überwacht werden.';

  @override
  String get integrationReadFailed =>
      'Der Repository-Status ist nicht verfügbar.';

  @override
  String get integrationDiscoveredEmpty => 'Keine Werkzeuge gefunden.';

  @override
  String get integrationConfiguredEmpty => 'Du hast noch keine hinzugefügt.';

  @override
  String get integrationNameHelp =>
      'Wird in Menüs angezeigt. Trage keine Passwörter oder Tokens ein.';

  @override
  String get integrationExplicitShellHelp =>
      'Erlaubt Pipes und Umleitungen. GitLama fragt immer vor dem Start.';

  @override
  String get integrationWaitHelp =>
      'GitLama wartet, bis das Programm beendet ist, bevor es weitergeht. Benutzerdefinierte Befehle warten immer.';

  @override
  String get powerToolsTitle => 'Repository-Werkzeuge';

  @override
  String get powerSearchTitle => 'Änderungen durchsuchen';

  @override
  String get powerSearchQuery => 'Geänderter Text';

  @override
  String get powerSearchBound =>
      'Findet Commits, die genau diesen Text hinzugefügt oder entfernt haben, in bis zu 10.000 Commits.';

  @override
  String get powerSearchCaseSensitive => 'Groß-/Kleinschreibung beachten';

  @override
  String get powerSearchScope => 'Suchbereich';

  @override
  String get powerSearchAllRefs => 'Alle Branches und Tags';

  @override
  String get powerSearchCurrentBranch => 'Aktueller Branch';

  @override
  String get powerSearchAction => 'Suchen';

  @override
  String get powerSearchCancel => 'Suche abbrechen';

  @override
  String get powerSearchIncompleteCommits =>
      'Die Ergebnisse sind unvollständig, weil die Grenze von 10.000 Commits erreicht wurde.';

  @override
  String get powerSearchIncompleteResults =>
      'Die Ergebnisse sind unvollständig, weil die Grenze von 512 Treffern erreicht wurde.';

  @override
  String powerSearchExamined(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Commits durchsucht',
      one: '1 Commit durchsucht',
    );
    return '$_temp0';
  }

  @override
  String get powerStatisticsTitle => 'Repository-Statistik';

  @override
  String get powerStatisticsLoad => 'Statistik berechnen';

  @override
  String get powerStatisticsIncomplete =>
      'Einige Zählungen haben bei einer Grenze aufgehört und sind möglicherweise zu niedrig.';

  @override
  String get powerBisectTitle => 'Fehlerhaften Commit finden';

  @override
  String get powerBisectGood => 'Commit, der funktioniert';

  @override
  String get powerBisectBad => 'Commit mit dem Fehler';

  @override
  String get powerBisectStart => 'Suche starten';

  @override
  String get powerBisectMarkGood => 'Funktioniert';

  @override
  String get powerBisectMarkBad => 'Hat den Fehler';

  @override
  String get powerBisectSkip => 'Überspringen';

  @override
  String get powerBisectReset => 'Suche beenden';

  @override
  String powerBisectProgress(int tested, int remaining) {
    final intl.NumberFormat testedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String testedString = testedNumberFormat.format(tested);
    final intl.NumberFormat remainingNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String remainingString = remainingNumberFormat.format(remaining);

    return '$testedString getestet · noch etwa $remainingString';
  }

  @override
  String get powerFailed =>
      'Das Repository-Werkzeug konnte nicht abgeschlossen werden.';

  @override
  String powerSearchFound(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Commits gefunden',
      one: '1 Commit gefunden',
      zero: 'Keine passenden Commits',
    );
    return '$_temp0';
  }

  @override
  String get powerStatisticsCommits => 'Commits';

  @override
  String get powerStatisticsBranches => 'Lokale Branches';

  @override
  String get powerStatisticsTags => 'Tags';

  @override
  String get powerStatisticsChangedFiles => 'Geänderte Dateien';

  @override
  String get powerBisectHelp =>
      'Nenne einen Commit, der funktioniert, und einen mit dem Fehler. GitLama checkt Commits dazwischen zum Testen aus, bis der erste mit dem Fehler gefunden ist.';

  @override
  String get powerBisectTesting => 'Zu testender Commit';

  @override
  String get powerBisectProgressLabel => 'Fortschritt';

  @override
  String get powerBisectQuestion => 'Hat dieser Commit den Fehler?';

  @override
  String get bisectConfirmGood => 'Als funktionsfähig markieren';

  @override
  String get bisectConfirmBad => 'Als fehlerhaft markieren';

  @override
  String get bisectStartTitle => 'Suche nach dem fehlerhaften Commit starten?';

  @override
  String get bisectGoodTitle => 'Diesen Commit als funktionsfähig markieren?';

  @override
  String get bisectBadTitle => 'Diesen Commit als fehlerhaft markieren?';

  @override
  String get bisectSkipTitle => 'Diesen Commit überspringen?';

  @override
  String get bisectResetTitle => 'Suche beenden?';

  @override
  String get hostingAccounts => 'Hosting-Verbindungen';

  @override
  String get hostingAddConnection => 'Verbindung hinzufügen';

  @override
  String get hostingNoConnections => 'Keine Hosting-Verbindungen eingerichtet.';

  @override
  String get hostingPreset => 'Anbieter-Voreinstellung';

  @override
  String get hostingConnectionId => 'Verbindungsname';

  @override
  String get hostingConnectBeforeBinding =>
      'Füge zuerst ein Hosting-Konto hinzu, um dieses Repository zu verknüpfen.';

  @override
  String get hostingWebUrl => 'Web-Basis-URL';

  @override
  String get hostingApiUrl => 'API-Basis-URL';

  @override
  String get hostingOAuthClientId => 'OAuth-Client-ID';

  @override
  String get hostingGuideAction => 'Anbieter verbinden: Anleitung';

  @override
  String hostingGuideTitle(String provider) {
    return '$provider verbinden';
  }

  @override
  String get hostingGuideCliNote =>
      'GitLama verwendet die aktuelle Anmeldung der CLI, daher ist keine OAuth-Anwendung nötig.';

  @override
  String get hostingGuideEnterpriseNote =>
      'Wenn GitHub CLI installiert ist, kannst du stattdessen dessen Anmeldung verwenden.';

  @override
  String get hostingGuideForgejoNote =>
      'Die Serveradministration kann die Registrierung von Anwendungen einschränken.';

  @override
  String get hostingGuideNoSecret => 'Ein Client-Secret ist nicht nötig.';

  @override
  String hostingStepAuthorizeBrowser(String action) {
    return 'Wähle „$action“. GitLama öffnet deinen Browser, um die Anmeldung abzuschließen.';
  }

  @override
  String hostingStepAuthorizeDevice(String action) {
    return 'Wähle „$action“. GitLama öffnet GitHub und zeigt einen Code, den du dort eingibst.';
  }

  @override
  String hostingStepCopyApplicationId(String field) {
    return 'Kopiere ihre Application ID in das Feld „$field“.';
  }

  @override
  String hostingStepCopyClientId(String field) {
    return 'Kopiere ihre Client-ID in das Feld „$field“.';
  }

  @override
  String get hostingStepRedirect =>
      'Trage diese Weiterleitungs-URI in der Anwendung ein:';

  @override
  String get hostingStepDeviceFlow => 'Aktiviere Device Flow für die App.';

  @override
  String get hostingStepCreateCodeberg =>
      'Öffne bei Codeberg Einstellungen → Anwendungen → OAuth2-Anwendungen verwalten und erstelle eine Anwendung.';

  @override
  String get hostingStepCreateForgejo =>
      'Öffne auf deinem Server Einstellungen → Anwendungen und erstelle eine OAuth2-Anwendung.';

  @override
  String get hostingStepCreateGitLab =>
      'Öffne bei GitLab Profil → Zugriff → Anwendungen und erstelle eine Anwendung.';

  @override
  String get hostingStepCreateEnterprise =>
      'Öffne auf deinem Server Developer settings → OAuth Apps und erstelle eine OAuth-App, oder frag deine Organisation nach der Client-ID einer vorhandenen App.';

  @override
  String get hostingStepCreateGitHub =>
      'Öffne bei GitHub Developer settings → OAuth Apps und erstelle eine OAuth-App.';

  @override
  String hostingStepEnterServer(String field) {
    return 'Gib die Adresse deines Servers im Feld „$field“ ein.';
  }

  @override
  String hostingStepCliReturn(String action) {
    return 'Kehre hierher zurück und wähle „$action“.';
  }

  @override
  String hostingStepCliSignIn(String tool) {
    return 'Melde dich in einem Terminal mit $tool bei diesem Server an:';
  }

  @override
  String get hostingGuideServerPlaceholder => 'dein-server';

  @override
  String get hostingGuideOpenSettings => 'Anwendungseinstellungen öffnen';

  @override
  String get hostingGuideEnterName => 'Gib einen Verbindungsnamen ein.';

  @override
  String get hostingGuideEnterClientId =>
      'Gib die OAuth-Client-ID ein. Die Anleitung zeigt, wo du sie findest.';

  @override
  String get hostingGuideEnterServer =>
      'Gib eine gültige Server-URL ein, damit die API-URL ergänzt werden kann.';

  @override
  String get hostingGuideNameInUse =>
      'Eine Verbindung mit diesem Namen existiert bereits. Wähle einen anderen Namen.';

  @override
  String get hostingAuthenticationMethod => 'Authentifizierungsmethode';

  @override
  String get hostingOAuthApplication => 'OAuth-Anwendung';

  @override
  String get hostingGitHubCli => 'GitHub CLI';

  @override
  String get hostingGitHubCliHint =>
      'Verwendet das GitHub-CLI-Konto für diesen Host. GitLama kopiert das Token nicht in den eigenen Anmeldedatenspeicher.';

  @override
  String get hostingConnectWithCli => 'Mit GitHub CLI verbinden';

  @override
  String get hostingGitLabCli => 'GitLab CLI';

  @override
  String get hostingGitLabCliHint =>
      'Verwendet das GitLab-CLI-Konto für diesen Host. GitLama kopiert das Token nicht in den eigenen Anmeldedatenspeicher.';

  @override
  String get hostingConnectWithGitLabCli => 'Mit GitLab CLI verbinden';

  @override
  String get hostingSaveAuthorize => 'Speichern und autorisieren';

  @override
  String get hostingReauthorize => 'Erneut autorisieren';

  @override
  String get hostingRemove => 'Verbindung entfernen';

  @override
  String get hostingEnabled => 'Verbindung aktiviert';

  @override
  String get hostingStateEnabled => 'Aktiviert';

  @override
  String get hostingStateDisabled => 'Deaktiviert';

  @override
  String get hostingBackgroundRefresh => 'Hintergrundaktualisierung';

  @override
  String get hostingAuthorizationWaiting =>
      'Warten auf die Autorisierung beim Anbieter…';

  @override
  String hostingAuthorizationCode(String code) {
    return 'Gerätecode: $code';
  }

  @override
  String get hostingOpenBrowser => 'Im Browser öffnen';

  @override
  String get hostingBinding => 'Repository-Zuordnung';

  @override
  String get hostingAutomaticBinding => 'Automatische Zuordnung verwenden';

  @override
  String get hostingNoBinding =>
      'Keine Verbindung passt zu diesem Repository-Remote.';

  @override
  String get hostingAmbiguousBinding =>
      'Mehrere Verbindungen passen zu diesem Remote. Eine ausdrücklich auswählen.';

  @override
  String get hostingConnection => 'Verbindung';

  @override
  String get hostingRemote => 'Remote';

  @override
  String get hostingProviderRepository => 'Anbieter-Repository';

  @override
  String get hostingSaveBinding => 'Zuordnung speichern';

  @override
  String get hostingResources => 'Anbieter-Ressourcen';

  @override
  String get hostingFilter => 'Pull Requests und Issues filtern';

  @override
  String get hostingChangeRequests => 'Pull Requests';

  @override
  String repositoryTitleInGroup(String group, String repository) {
    return '$group / $repository';
  }

  @override
  String get hostingPullRequestMerged => 'Zusammengeführt';

  @override
  String get hostingPullRequestYours => 'Eigener';

  @override
  String hostingPullRequestBranches(String source, String target) {
    return '$source in $target';
  }

  @override
  String get hostingIssues => 'Issues';

  @override
  String get hostingRefresh => 'Aktualisieren';

  @override
  String get hostingLoadMore => 'Mehr laden';

  @override
  String get hostingLoadingCached =>
      'Aktualisierung läuft; zwischengespeicherte Ergebnisse bleiben verfügbar.';

  @override
  String get hostingEmpty => 'Keine Anbieter-Ressourcen gefunden.';

  @override
  String get hostingStale => 'Zwischengespeichert';

  @override
  String get hostingCheckout => 'Auschecken';

  @override
  String get hostingReview => 'Review';

  @override
  String get hostingCreateChangeRequest => 'Pull Request erstellen';

  @override
  String get hostingCapabilityUnavailable =>
      'Diese Anbieter-Verbindung unterstützt die Aktion nicht.';

  @override
  String get hostingForkCheckoutUnavailable =>
      'Den Fork-Branch vor dem Auschecken abrufen.';

  @override
  String hostingFailure(String reason) {
    return 'Anbieteranfrage fehlgeschlagen: $reason';
  }

  @override
  String get hostingFailureNotFound =>
      'Der Server kennt diese Adresse nicht. Prüfe die API-Basis-URL und den Repository-Namen und ob dieses Konto auf das Repository zugreifen darf.';

  @override
  String get hostingFailureRedirected =>
      'Der Server hat die Anfrage umgeleitet. Das Repository wurde möglicherweise umbenannt oder verschoben, oder die API-Basis-URL ist falsch.';

  @override
  String get hostingFailureServerError =>
      'Der Server hat einen internen Fehler gemeldet. Versuche es später erneut.';

  @override
  String get hostingFailureNetwork =>
      'Der Server ist nicht erreichbar. Prüfe Netzwerkverbindung, VPN und Proxy.';

  @override
  String get hostingFailureCertificate =>
      'Die sichere Verbindung konnte nicht aufgebaut werden. Prüfe, ob das curl in deinem PATH dem Serverzertifikat vertraut.';

  @override
  String get hostingFailureTimedOut =>
      'Der Server hat nicht rechtzeitig geantwortet.';

  @override
  String get hostingSettingsFailure =>
      'Die Hosting-Einstellungen konnten nicht gespeichert werden.';

  @override
  String get hostingReferenceEmpty =>
      'Keine passenden Pull Requests oder Issues.';

  @override
  String hostingReviewTitle(int number) {
    return 'Review #$number';
  }

  @override
  String get hostingReviewThreads => 'Review-Kommentare';

  @override
  String get hostingReviewReanchor => 'Neu verankern';

  @override
  String get hostingReviewOutdated => 'Veraltet';

  @override
  String hostingReviewInlineTitle(int line) {
    return 'Kommentar zu Zeile $line';
  }

  @override
  String get hostingReviewInlineSave => 'Zum Review hinzufügen';

  @override
  String get hostingReviewComment => 'Review-Text';

  @override
  String get hostingReviewAction => 'Review-Aktion';

  @override
  String get hostingReviewCommentAction => 'Kommentieren';

  @override
  String get hostingReviewApprove => 'Genehmigen';

  @override
  String get hostingReviewRequestChanges => 'Änderungen anfordern';

  @override
  String get hostingReviewPreview => 'Review prüfen';

  @override
  String get hostingReviewAuthorize => 'Dieses Review absenden?';

  @override
  String get hostingRequestDetails => 'Anfragedetails';

  @override
  String get hostingReviewInlineComments => 'Zeilenkommentare';

  @override
  String hostingReviewAuthorizeSummary(int number) {
    return 'GitLama veröffentlicht dein Review zu #$number.';
  }

  @override
  String get hostingReviewSubmit => 'Review absenden';

  @override
  String get hostingReviewNoDiff => 'Kein Review-Diff verfügbar.';

  @override
  String get hostingReviewLoadFailed =>
      'Dieses Review konnte nicht geladen werden.';

  @override
  String hostingReviewFailure(String reason) {
    return 'Review fehlgeschlagen: $reason';
  }

  @override
  String get hostingChecks => 'Prüfungen';

  @override
  String get hostingCheckRetry => 'Erneut ausführen';

  @override
  String get hostingCheckRetryAuthorize => 'Diese Prüfung erneut ausführen?';

  @override
  String hostingCheckRetrySummary(String name) {
    return 'GitLama bittet den Anbieter, $name erneut auszuführen.';
  }

  @override
  String get cliForwardingFailed =>
      'GitLama konnte den Befehl nicht sicher weiterleiten.';

  @override
  String galleryStatus(int count, String menu) {
    return 'Aktivierungen: $count · Menü: $menu';
  }

  @override
  String get stageHunk => 'Block vormerken';

  @override
  String get unstageHunk => 'Block zurücknehmen';

  @override
  String get discardHunk => 'Block verwerfen';

  @override
  String get transferForceHelp =>
      'Für umgeschriebene Commits. Wird abgelehnt, wenn seit deinem letzten Fetch jemand anderes darauf gepusht hat.';

  @override
  String get gallerySectionButton => 'Schaltfläche';

  @override
  String get gallerySectionIconButton => 'Symbolschaltfläche';

  @override
  String get gallerySectionToolbarButton => 'Werkzeugleistenschaltfläche';

  @override
  String get gallerySectionCheckbox => 'Kontrollkästchen';

  @override
  String get gallerySectionSegmented => 'Segmentauswahl';

  @override
  String get gallerySectionSelect => 'Auswahl';

  @override
  String get gallerySectionTextField => 'Textfeld';

  @override
  String get gallerySectionCompass => 'Kompass';

  @override
  String get gallerySectionPalette => 'Befehlspalette';

  @override
  String get gallerySectionRepoTabs => 'Repository-Tabs';

  @override
  String get gallerySectionSidebarRow => 'Seitenleistenzeile';

  @override
  String get gallerySectionAvatar => 'Avatar';

  @override
  String get gallerySectionCommitRow => 'Commit-Zeile';

  @override
  String get gallerySectionComposer => 'Commit-Editor';

  @override
  String get gallerySectionDiffHunk => 'Diff-Block';

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
  String get gallerySectionFileRow => 'Dateizeile';

  @override
  String get gallerySectionGraph => 'Graph';

  @override
  String get gallerySectionRefChip => 'Referenz-Chip';

  @override
  String get gallerySectionStatusGlyph => 'Statussymbol';

  @override
  String get gallerySectionSyncBadge => 'Synchronisationsanzeige';

  @override
  String get gallerySectionBanner => 'Hinweis';

  @override
  String get gallerySectionKbd => 'Tastenkürzel';

  @override
  String get gallerySectionLogbook => 'Logbuch';

  @override
  String get gallerySectionDialog => 'Dialog';

  @override
  String get gallerySectionIsland => 'Bereich';

  @override
  String get gallerySectionSettingsRow => 'Einstellungszeile';

  @override
  String get galleryPaletteMove => 'Bewegen';

  @override
  String get galleryPaletteRun => 'Ausführen';

  @override
  String get galleryPaletteBackground => 'Im Hintergrund ausführen';

  @override
  String get galleryPaletteScope => 'Umfang';

  @override
  String get galleryCommitToMain => 'Auf main committen';

  @override
  String get galleryPush => 'Pushen';

  @override
  String get galleryCopyHash => 'Hash kopieren';

  @override
  String get galleryDiscardThreeFiles => '3 Dateien verwerfen';

  @override
  String get galleryDiscard => 'Verwerfen';

  @override
  String get galleryFetching => 'Wird abgerufen…';

  @override
  String get galleryPull => 'Pullen';

  @override
  String get galleryCommit => 'Commit';

  @override
  String get galleryStageHunk => 'Block vormerken';

  @override
  String get galleryShowAllFiles => 'Alle 42 Dateien anzeigen';

  @override
  String get galleryFilter => 'Filter';

  @override
  String get gallerySideBySide => 'Nebeneinander';

  @override
  String get galleryUnified => 'Vereinheitlicht';

  @override
  String get galleryMore => 'Mehr';

  @override
  String get galleryCopy => 'Kopieren';

  @override
  String get galleryStage => 'Vormerken';

  @override
  String get galleryDelete => 'Löschen';

  @override
  String get galleryFetch => 'Abrufen';

  @override
  String get galleryStash => 'Stash';

  @override
  String get galleryBranch => 'Branch';

  @override
  String get galleryMerge => 'Merge';

  @override
  String get gallerySignCommit => 'Commit signieren';

  @override
  String get galleryAmend => 'Ändern';

  @override
  String get galleryStageAllMixed => 'Alle vormerken (2 von 5)';

  @override
  String get galleryBypassHooks => 'Hooks umgehen';

  @override
  String get galleryFetchAutomatically => 'Automatisch abrufen';

  @override
  String get galleryIncludeTags => 'Tags einbeziehen';

  @override
  String get galleryModified => 'Geändert';

  @override
  String get galleryAdded => 'Hinzugefügt';

  @override
  String get galleryDeleted => 'Gelöscht';

  @override
  String get galleryRenamed => 'Umbenannt';

  @override
  String get galleryCopied => 'Kopiert';

  @override
  String get galleryConflict => 'Konflikt';

  @override
  String get galleryUntracked => 'Nicht verfolgt';

  @override
  String get galleryIgnored => 'Ignoriert';

  @override
  String get galleryTwoConflicts => '2 Konflikte';

  @override
  String get galleryMichaelLamers => 'Michael Lamers';

  @override
  String get galleryGitLamaReleaseBot => 'GitLama Release Bot';

  @override
  String get galleryAuthorHandle => 'ada';

  @override
  String get galleryAdaGit => 'Ada Git';

  @override
  String get gallerySearchCommits => 'Commits, Autoren und Hashes suchen';

  @override
  String get galleryRefPlaceholder => 'refs/heads/main';

  @override
  String get galleryRefValue => 'feature/spline-graph';

  @override
  String get galleryInvalidRef => 'feature/..bad';

  @override
  String get galleryInvalidRefMessage =>
      'Branchnamen dürfen „..“ nicht enthalten';

  @override
  String get galleryRebasePaused => 'Rebase bei 3 von 7 angehalten.';

  @override
  String get galleryRebaseConflicts =>
      '2 Dateien in lib/app enthalten noch Konflikte.';

  @override
  String get galleryAbort => 'Abbrechen';

  @override
  String get galleryContinue => 'Fortsetzen';

  @override
  String get galleryPushRejected => 'Push abgelehnt.';

  @override
  String get galleryPushRejectedMessage =>
      'origin/main enthält 6 Commits, die lokal fehlen.';

  @override
  String get galleryPullFirst => 'Zuerst pullen';

  @override
  String get galleryAuthFailed =>
      'Authentifizierung für git.example.com fehlgeschlagen.';

  @override
  String get galleryTokenExpired => 'Das Token ist am 24. Sep. abgelaufen.';

  @override
  String get galleryUpdateCredentials => 'Anmeldedaten aktualisieren';

  @override
  String get galleryLfsMessage =>
      'Dieses Repository verwendet Git LFS. 14 Dateien bleiben Platzhalter, bis sie abgerufen werden.';

  @override
  String get galleryDiffLayout => 'Diff-Layout';

  @override
  String get galleryFileList => 'Dateiliste';

  @override
  String get gallerySplit => 'Geteilt';

  @override
  String get galleryList => 'Liste';

  @override
  String get galleryTree => 'Baum';

  @override
  String get galleryThemeSystem => 'System';

  @override
  String get galleryDates => 'Datumsanzeige';

  @override
  String get galleryRemotes => 'Remotes';

  @override
  String get galleryDensityHelp =>
      'Ändert nur die Zeilenhöhe. Text und Symbole bleiben gleich groß.';

  @override
  String get galleryRemotesHelp =>
      'Alle 10 Minuten im Hintergrund. Wird im Logbuch angezeigt.';

  @override
  String get galleryRebaseTitle =>
      'windows-soak-cleanup auf origin/main rebasen';

  @override
  String get galleryRebaseDescription =>
      '4 Commits werden auf 6 neue Commits von origin/main übertragen.';

  @override
  String get galleryAutostash => 'Automatischer Stash';

  @override
  String get galleryRebase => 'Rebase';

  @override
  String get galleryFourCommits => '4 Commits';

  @override
  String get galleryFocusedIsland =>
      'Fokussierte Insel: 1 px weicher blauer Halo, kräftige blaue Auswahl.';

  @override
  String get galleryUnfocusedIsland =>
      'Nicht fokussierte Insel: Auswahl wird hellblau.';

  @override
  String get galleryDetail => 'Detail';

  @override
  String get galleryPaletteQuery => 'reb';

  @override
  String get galleryPaletteCommands => 'Befehle';

  @override
  String get galleryPaletteBranches => 'Branches';

  @override
  String get galleryPaletteRecent => 'Zuletzt verwendet';

  @override
  String get galleryPaletteRebaseTarget =>
      'windows-soak-cleanup auf origin/main rebasen';

  @override
  String get galleryPaletteInteractiveRebase => 'Interaktiver Rebase…';

  @override
  String get galleryPaletteLastCommits => 'letzte 5 Commits';

  @override
  String get galleryPaletteBranchRef => 'feature/rebuild-graph-cache';

  @override
  String get galleryPaletteOrigin => 'origin';

  @override
  String get galleryPaletteAbortRebase => 'Rebase abbrechen';

  @override
  String get galleryPaletteYesterday => 'gestern';

  @override
  String compassConflicts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konflikte',
      one: '1 Konflikt',
    );
    return '$_temp0';
  }

  @override
  String compassChangedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geänderte Dateien',
      one: '1 geänderte Datei',
    );
    return '$_temp0';
  }

  @override
  String get repositoryDetailsTitle => 'Repository-Details';

  @override
  String get repositoryDetailsLocation => 'Ort';

  @override
  String get repositoryDetailsThisComputer => 'Dieser Computer';

  @override
  String repositoryDetailsHostWithAlias(String host, String alias) {
    return '$host ($alias)';
  }

  @override
  String get repositoryDetailsDisconnected => 'getrennt';

  @override
  String get repositoryDetailsPath => 'Pfad';

  @override
  String get repositoryDetailsGroup => 'Tab-Gruppe';

  @override
  String get repositoryDetailsKind => 'Art';

  @override
  String get repositoryDetailsWorktree => 'Repository mit Arbeitsbaum';

  @override
  String get repositoryDetailsLinkedWorktree => 'Verknüpfter Arbeitsbaum';

  @override
  String get repositoryDetailsBare => 'Bare-Repository';

  @override
  String get repositoryDetailsBranch => 'Branch';

  @override
  String get repositoryDetailsUnborn => 'noch keine Commits';

  @override
  String get repositoryDetailsUpstream => 'Upstream';

  @override
  String get repositoryDetailsNoUpstream => 'Folgt keinem Remote-Branch';

  @override
  String get repositoryDetailsChanges => 'Änderungen';

  @override
  String get repositoryDetailsClean => 'Keine Änderungen';

  @override
  String get repositoryDetailsInProgress => 'Git-Vorgang';

  @override
  String get repositoryDetailsRunning => 'Aktivität';

  @override
  String get repositoryDetailsIdle => 'Nichts läuft';

  @override
  String get repositoryDetailsHealthClean => 'Arbeitsverzeichnis sauber';

  @override
  String get repositoryDetailsHealthChanged => 'Änderungen zum Committen';

  @override
  String get repositoryDetailsHealthConflicted => 'Konflikte zu lösen';

  @override
  String get repositoryDetailsHealthPaused => 'Git-Vorgang angehalten';

  @override
  String get repositoryDetailsHealthBusy => 'Wird ausgeführt…';

  @override
  String get repositoryDetailsGit => 'Git-Version';

  @override
  String get repositoryCopyPath => 'Pfad kopieren';

  @override
  String get repositoryPathCopied => 'Repository-Pfad kopiert.';

  @override
  String commandPaletteShortcutTooltip(String shortcut) {
    return 'Befehle ($shortcut)';
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
    return '$repository, $branch, $ahead voraus, $behind zurück, $dirty geänderte Dateien, $conflicts Konflikte. Repository-Details anzeigen.';
  }

  @override
  String get logbookTitle => 'Logbuch';

  @override
  String get commandEditBranch => 'Branch bearbeiten…';

  @override
  String get editBranchName => 'Name';

  @override
  String get editBranchUpstream => 'Upstream';

  @override
  String get editBranchNoUpstream =>
      'Leer lassen, um keinem Remote-Branch zu folgen.';

  @override
  String get editBranchSave => 'Speichern';

  @override
  String get editBranchNameExists =>
      'Ein Branch mit diesem Namen existiert bereits.';

  @override
  String get editBranchDescription =>
      'Lokalen Branch umbenennen oder den verfolgten Remote-Branch ändern.';

  @override
  String refConfirmSetUpstream(String name, String upstream) {
    return '$upstream als Upstream von $name festlegen.';
  }

  @override
  String refConfirmUnsetUpstream(String name) {
    return 'Upstream von $name entfernen. Der Remote-Branch bleibt unverändert.';
  }

  @override
  String get diffSelectionCopied => 'Auswahl kopiert.';

  @override
  String get diffSelectionStage => 'Vormerken';

  @override
  String get diffSelectionUnstage => 'Aus der Vormerkung nehmen';

  @override
  String get diffSelectionDiscard => 'Änderungen verwerfen …';

  @override
  String get diffCopyLines => 'Kopieren';

  @override
  String get diffCopyAsPatch => 'Als Patch kopieren';

  @override
  String get diffPatchCopied => 'Patch kopiert.';

  @override
  String get diffPatchUnavailable =>
      'Die ausgewählten Zeilen enthalten keine Änderungen.';

  @override
  String get transferFetchDescription =>
      'Die neuesten Änderungen von einem Remote abrufen.';

  @override
  String get transferPullDescription =>
      'Einen Remote-Branch abrufen und in den aktuellen Branch übernehmen.';

  @override
  String get transferPushDescription =>
      'Einen lokalen Branch auf einem Remote veröffentlichen.';

  @override
  String get transferPushTagDescription =>
      'Einen Tag auf einem Remote veröffentlichen, damit andere ihn abrufen können.';

  @override
  String get transferDeleteBranchDescription =>
      'Einen Branch auf einem Remote löschen. Er wird nur gelöscht, wenn er sich seit dem letzten Fetch nicht verändert hat. Andere könnten ihn bereits abgerufen haben.';

  @override
  String get editBranchUpstreamUnknown =>
      'Einen abgerufenen Remote-Branch wählen oder das Feld leer lassen.';

  @override
  String get changesExpandFolder => 'Ordner aufklappen';

  @override
  String get changesCollapseFolder => 'Ordner zuklappen';

  @override
  String get extensionWorktreeDeleteAction => 'Worktree löschen …';

  @override
  String get repositoryTabChangeIcon => 'Symbol ändern …';

  @override
  String get repositoryTabRemoveIcon => 'Symbol entfernen';

  @override
  String get repositoryIconTitle => 'Repository-Symbol';

  @override
  String get repositoryIconDescription =>
      'Wird im Tab des Repositorys angezeigt, damit du es auf einen Blick findest.';

  @override
  String get repositoryIconSymbol => 'Symbol';

  @override
  String get repositoryIconColor => 'Farbe';

  @override
  String get repositoryIconImage => 'Bilddatei';

  @override
  String get repositoryIconNone => 'Kein Symbol';

  @override
  String get repositoryIconChooseImage => 'Bild auswählen …';

  @override
  String get repositoryIconRemoveImage => 'Bild entfernen';

  @override
  String get repositoryIconImageHint =>
      'PNG, JPEG, GIF, WebP, BMP, ICO oder SVG, bis 2 MB. Ein Bild ersetzt das Symbol.';

  @override
  String get repositoryIconImageUnreadable =>
      'Dieses Bild kann nicht verwendet werden. Wähle eine unterstützte Datei bis 2 MB.';

  @override
  String get repositoryIconSave => 'Speichern';

  @override
  String get repositoryIconSaveFailed =>
      'Das Symbol konnte nicht gespeichert werden.';

  @override
  String get repositoryIconNameRepository => 'Repository';

  @override
  String get repositoryIconNameCode => 'Code';

  @override
  String get repositoryIconNameTerminal => 'Terminal';

  @override
  String get repositoryIconNamePackage => 'Paket';

  @override
  String get repositoryIconNameComponents => 'Komponenten';

  @override
  String get repositoryIconNamePlugin => 'Plugin';

  @override
  String get repositoryIconNameLayers => 'Ebenen';

  @override
  String get repositoryIconNameDocumentation => 'Dokumentation';

  @override
  String get repositoryIconNameDesign => 'Design';

  @override
  String get repositoryIconNameMedia => 'Medien';

  @override
  String get repositoryIconNameMobile => 'Mobil';

  @override
  String get repositoryIconNameDesktop => 'Desktop';

  @override
  String get repositoryIconNameServer => 'Server';

  @override
  String get repositoryIconNameCloud => 'Cloud';

  @override
  String get repositoryIconNameLightning => 'Blitz';

  @override
  String get repositoryIconNameStar => 'Stern';

  @override
  String get repositoryIconNameFlag => 'Flagge';

  @override
  String get repositoryIconNameBug => 'Käfer';

  @override
  String get repositoryIconNameMagic => 'Magie';

  @override
  String get repositoryIconNameLearning => 'Lernen';

  @override
  String get repositoryIconNameSecurity => 'Sicherheit';

  @override
  String get repositoryIconNameAnalytics => 'Analyse';

  @override
  String get repositoryIconNameHome => 'Zuhause';

  @override
  String get repositoryIconNameTeam => 'Team';

  @override
  String get repositoryColorBlue => 'Blau';

  @override
  String get repositoryColorTeal => 'Petrol';

  @override
  String get repositoryColorAmber => 'Bernstein';

  @override
  String get repositoryColorOrange => 'Orange';

  @override
  String get repositoryColorRose => 'Rosa';

  @override
  String get repositoryColorViolet => 'Violett';

  @override
  String get repositoryColorCyan => 'Cyan';

  @override
  String get repositoryColorOlive => 'Oliv';

  @override
  String get repositoryColorNone => 'Keine Farbe';

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsUpdatesDetail =>
      'Wähle, welche Versionen du erhältst, und suche nach einer neueren Version.';

  @override
  String get updatesInstalledVersion => 'Installierte Version';

  @override
  String updatesVersionAndBuild(String version, int build) {
    return '$version (Build $build)';
  }

  @override
  String get updatesChannel => 'Release-Kanal';

  @override
  String get updatesChannelStable => 'Stabil';

  @override
  String get updatesChannelBeta => 'Beta';

  @override
  String get updatesChannelHint => 'Beta enthält auch jede stabile Version.';

  @override
  String get updatesCheck => 'Nach Updates suchen';

  @override
  String get updatesChecking => 'Suche nach Updates …';

  @override
  String updatesUpToDate(String version, int build) {
    return 'GitLama $version (Build $build) ist aktuell.';
  }

  @override
  String get updatesNoRelease =>
      'Für diesen Kanal wurde noch keine Version veröffentlicht.';

  @override
  String updatesAvailable(String version, int build) {
    return 'GitLama $version (Build $build) ist verfügbar. Lade die Version von der Release-Seite.';
  }

  @override
  String get updatesOpenDownloads => 'Download-Seite öffnen';

  @override
  String get updatesAutomaticHint =>
      'GitLama sucht im Hintergrund nach Updates und installiert eines, nachdem du zugestimmt hast.';

  @override
  String get updatesManualHint =>
      'GitLama kontaktiert die Release-Seite nur, wenn du suchst. Den Download installierst du selbst.';

  @override
  String get updatesFailureUnavailable =>
      'Die Release-Seite war nicht erreichbar. Versuche es später erneut.';

  @override
  String get updatesFailureInvalid =>
      'Die Release-Liste konnte nicht gelesen werden.';

  @override
  String get updatesFailureUpdater =>
      'Der Updater konnte nicht gestartet werden.';

  @override
  String get updatesFailureOpen =>
      'Die Download-Seite konnte nicht geöffnet werden.';

  @override
  String get updatesFailureUnsupported =>
      'Dieser Build kann nicht nach Updates suchen.';

  @override
  String get diffCreatePatch => 'Patch aus diesem Diff erstellen';

  @override
  String get historyAllChanges => 'Alle Änderungen';

  @override
  String get historyAllChangesTooLarge => 'Zu groß';

  @override
  String menuSelectedCommits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählte Commits',
      one: '1 ausgewählter Commit',
    );
    return '$_temp0';
  }

  @override
  String menuSelectedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ausgewählte Dateien',
      one: '1 ausgewählte Datei',
    );
    return '$_temp0';
  }

  @override
  String get patchCreateFromSelection => 'Patch aus Auswahl erstellen';

  @override
  String get patchCreateFromCommit => 'Patch aus diesem Commit erstellen';

  @override
  String get patchCreateFromFile => 'Patch aus dieser Datei erstellen';

  @override
  String get windowMinimize => 'Fenster minimieren';

  @override
  String get windowMaximize => 'Fenster maximieren oder wiederherstellen';

  @override
  String get windowClose => 'Fenster schließen';

  @override
  String get repositoryTabRename => 'Tab umbenennen…';

  @override
  String get repositoryTabResetName => 'Ordnernamen verwenden';

  @override
  String get repositoryTabRenameLabel => 'Tabname';

  @override
  String get tabGroupAddToNew => 'Zu neuer Gruppe hinzufügen';

  @override
  String get tabGroupAddTo => 'Zu Gruppe hinzufügen';

  @override
  String get tabGroupNew => 'Neue Gruppe';

  @override
  String get tabGroupRemoveTab => 'Aus Gruppe entfernen';

  @override
  String get tabGroupRename => 'Gruppe umbenennen…';

  @override
  String get tabGroupColor => 'Farbe';

  @override
  String get tabGroupIcon => 'Symbol';

  @override
  String get tabGroupEdit => 'Gruppe bearbeiten…';

  @override
  String get tabGroupEditTitle => 'Gruppe bearbeiten';

  @override
  String get tabGroupEditDescription =>
      'Name, Farbe und Symbol des Gruppen-Chips in der Tab-Leiste.';

  @override
  String get tabGroupEditName => 'Name';

  @override
  String get tabGroupEditPreview => 'Vorschau der Gruppe in der Tab-Leiste';

  @override
  String get tabGroupEditSave => 'Speichern';

  @override
  String get repositoryColorCustom => 'Eigene Farbe';

  @override
  String get colorPickerWheel => 'Farbton und Sättigung';

  @override
  String get colorPickerHue => 'Farbton';

  @override
  String get colorPickerSaturation => 'Sättigung';

  @override
  String get colorPickerBrightness => 'Helligkeit';

  @override
  String get colorPickerRed => 'Rot';

  @override
  String get colorPickerGreen => 'Grün';

  @override
  String get colorPickerBlue => 'Blau';

  @override
  String get colorPickerModel => 'Farbmodell';

  @override
  String get colorPickerHsb => 'HSB';

  @override
  String get colorPickerRgb => 'RGB';

  @override
  String get colorPickerHex => 'Hex-Wert';

  @override
  String get colorPickerInvalidHex =>
      'Sechs Hex-Ziffern eingeben, etwa #18304F';

  @override
  String get colorPickerOriginal => 'Ursprüngliche Farbe';

  @override
  String get colorPickerNew => 'Neue Farbe';

  @override
  String repositoryColorCustomValue(String hex) {
    return 'Eigene Farbe $hex';
  }

  @override
  String colorPickerSwatch(String hex) {
    return 'Farbe $hex';
  }

  @override
  String colorPickerDegrees(int value) {
    return '$value°';
  }

  @override
  String colorPickerPercent(int value) {
    return '$value %';
  }

  @override
  String get repositoryTabMoveLeft => 'Tab nach links verschieben';

  @override
  String get repositoryTabMoveRight => 'Tab nach rechts verschieben';

  @override
  String get repositoryTabUnsaved => 'nicht committete Änderungen';

  @override
  String get tabGroupCollapseAction => 'Gruppe zuklappen';

  @override
  String get tabGroupExpandAction => 'Gruppe aufklappen';

  @override
  String get tabGroupUngroup => 'Gruppierung aufheben';

  @override
  String get tabGroupClose => 'Gruppe schließen';

  @override
  String get tabGroupNamePlaceholder => 'Gruppe benennen';

  @override
  String get tabGroupRenameLabel => 'Gruppenname';

  @override
  String tabGroupUnnamed(String color) {
    return 'Gruppe $color';
  }

  @override
  String tabGroupExpand(String name) {
    return '$name aufklappen';
  }

  @override
  String tabGroupCollapse(String name) {
    return '$name zuklappen';
  }

  @override
  String tabGroupSemantics(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tabs',
      one: '1 Tab',
    );
    return '$name, Tab-Gruppe, $_temp0';
  }

  @override
  String get changesFilterPlaceholder => 'Dateien filtern';

  @override
  String get changesFilterLabel => 'Geänderte Dateien filtern';

  @override
  String get changesFilterClear => 'Filter löschen';

  @override
  String changesFilterCount(int shown, int total) {
    return '$shown von $total';
  }

  @override
  String get changesFilterNoMatches => 'Keine passenden Dateien';

  @override
  String get stageShown => 'Angezeigte Dateien vormerken';

  @override
  String get unstageShown => 'Angezeigte Dateien aus der Vormerkung nehmen';

  @override
  String get stageShortShown => 'Angezeigte vormerken';

  @override
  String get unstageShortShown => 'Angezeigte zurücknehmen';

  @override
  String get discardShown => 'Angezeigte Dateien verwerfen';

  @override
  String get historyRevertCommit => 'Commit rückgängig machen';

  @override
  String get historyRevertCommitNow => 'Revert direkt committen';

  @override
  String get historyRevertApplyOnly => 'Ohne Commit anwenden';

  @override
  String get historyRevertApplySingleRequired =>
      'Ohne Commit anwenden geht nur mit einem Commit auf einmal.';

  @override
  String get historyRevertResolveConflicts =>
      'Löse zuerst die Konflikte: Solange Dateien in Konflikt stehen, kann kein Revert beginnen.';

  @override
  String get historyMutationFailureLocalChanges =>
      'Ein Revert ohne Commit kann deine lokalen Änderungen nicht beiseitelegen. Reverte mit Commit, oder committe oder stashe zuerst die Änderungen, mit denen er kollidiert.';

  @override
  String get historyPreviewLocalChanges => 'Lokale Änderungen';

  @override
  String get historyRevertLocalInPlace => 'Bleiben, wo sie sind';

  @override
  String get historyRevertLocalSetAside =>
      'Beiseitegelegt und wieder angewendet';

  @override
  String get historyRevertLocalInPlaceDetail =>
      'Keine deiner lokalen Änderungen ist gestagt oder betrifft eine Datei, die dieser Revert ändert. Git revertiert um sie herum.';

  @override
  String historyRevertSetAsideFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count lokale Änderungen betreffen Dateien, die dieser Revert ändert:',
      one: '1 lokale Änderung betrifft eine Datei, die dieser Revert ändert:',
    );
    return '$_temp0';
  }

  @override
  String historyRevertSetAsideMore(int count) {
    return 'und $count weitere';
  }

  @override
  String get historyRevertSetAsideStaged =>
      'Einige deiner lokalen Änderungen sind gestagt, und Git revertiert nicht über gestagte Änderungen.';

  @override
  String get historyRevertSetAsideExplain =>
      'GitLama sichert deine lokalen Änderungen in einem Stash, revertiert und wendet sie dann mit ihrem Staging wieder an. Kollidieren sie mit dem Revert, löst du die Konflikte unter Änderungen. Eine Sicherung bleibt unter Stashes.';

  @override
  String get historyRevertSetAsideAction => 'Beiseitelegen und reverten';

  @override
  String get historyRevertSetAsideRestored =>
      'Revert abgeschlossen. Deine lokalen Änderungen und ihr Staging wurden wiederhergestellt. Eine Sicherung bleibt unter Stashes.';

  @override
  String get historyRevertSetAsideConflict =>
      'Revert abgeschlossen, aber beim Wiederanwenden deiner lokalen Änderungen sind Konflikte entstanden. Löse sie unter Änderungen. Der Sicherungs-Stash bleibt erhalten.';

  @override
  String get historyRevertSetAsidePending =>
      'Der Revert hat bei Konflikten angehalten. Deine lokalen Änderungen sind beiseitegelegt und kommen zurück, wenn du den Revert fortsetzt oder abbrichst.';

  @override
  String get historyRevertSetAsideSaved =>
      'Deine lokalen Änderungen konnten nicht vollständig wiederhergestellt werden; sie bleiben unter Stashes gesichert. Prüfe Änderungen, bevor du den Sicherungs-Stash anwendest.';

  @override
  String get historyRevertApplied =>
      'Revert angewendet. Prüfe die gestagten Änderungen vor dem Commit.';

  @override
  String get historyRevertMergeUnsupported =>
      'Diese Auswahl enthält einen Merge-Commit. Für seinen Revert muss ein Hauptelternteil gewählt werden. Das wird hier noch nicht unterstützt.';

  @override
  String get menuRepository => 'Repository';

  @override
  String get menuChanges => 'Änderungen und Commits';

  @override
  String get menuHistory => 'Verlauf';

  @override
  String get menuBranches => 'Branches und Tags';

  @override
  String get menuRemotes => 'Remotes und Synchronisierung';

  @override
  String get menuRecovery => 'Wiederherstellung und Konflikte';

  @override
  String get menuTools => 'Werkzeuge';

  @override
  String get menuView => 'Ansicht';

  @override
  String get menuApplication => 'Anwendung';

  @override
  String get menuRebase => 'Rebase';

  @override
  String get menuDiff => 'Diff';

  @override
  String get menuActivity => 'Aktivität';

  @override
  String get diffLargeFileInformation =>
      'Die Datei überschreitet die Vorschaugrenze von 8 MiB. Es werden nur Dateiinformationen angezeigt.';

  @override
  String diffFileSize(String size) {
    return 'Größe: $size';
  }

  @override
  String diffFileType(String extension) {
    return 'Dateityp: $extension';
  }

  @override
  String get diffFileTypeUnknown => 'Unbekannt';

  @override
  String get aboutApp => 'Über GitLama';

  @override
  String get aboutSourceCode => 'Quellcode auf GitHub';

  @override
  String get aboutSourceCodeOpenFailed =>
      'Die Quellcode-Seite konnte nicht geöffnet werden.';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version (Build $build)';
  }

  @override
  String get brandTooltip => 'GitLama · by Devmil Solutions';

  @override
  String get brandMaker => 'by Devmil Solutions';

  @override
  String get lamaFamily => 'Die Lama-Familie';

  @override
  String get brandWelcome => 'Öffne ein Repository.';

  @override
  String get lamaFamilyNames =>
      'GitLama · ProcessLama · MailLama · ShotLama · NoteLama';

  @override
  String get openRemoteRepository => 'Remote-Repository öffnen…';

  @override
  String get remoteCommandUnsupported =>
      'Für Repositorys auf einem anderen Computer nicht verfügbar';

  @override
  String get remoteCommandDisconnected =>
      'Verbinde dich erneut mit dem Host, um das zu nutzen';

  @override
  String get remoteCommandWritesUnavailable =>
      'Der Host nimmt diese Änderung nicht an. Prüfe, ob sein GitLama-Helferspeicher nutzbar ist';

  @override
  String get remoteCommandWritesOff =>
      'Aktiviere „Änderungen auf diesem Host erlauben“, um das zu nutzen';

  @override
  String get remoteCommandWritesReconnect =>
      'Verbinde dich neu, damit „Änderungen auf diesem Host erlauben“ gilt';

  @override
  String get remoteCommandWritesLedger =>
      'GitLama kann seine Aufzeichnung der Remote-Änderungen auf diesem Computer nicht lesen, daher sind Änderungen nicht verfügbar';

  @override
  String get remoteHosts => 'Hosts';

  @override
  String get remoteHostsIntro =>
      'Verbinde dich über deine eigene SSH-Konfiguration mit einem anderen Computer. GitLama fragt nie nach Passwörtern oder privaten Schlüsseln.';

  @override
  String get remoteHostsEmpty =>
      'Noch keine Hosts. Füge einen Host mit einem Alias aus deiner SSH-Konfiguration hinzu.';

  @override
  String get remoteAddHost => 'Host hinzufügen…';

  @override
  String get remoteAddHostTitle => 'Host hinzufügen';

  @override
  String remoteAddHostRequested(String alias) {
    return 'GitLama soll ein Repository auf „$alias“ öffnen, aber dieser Host ist noch nicht gespeichert. Speichere ihn, um dich zu verbinden, oder brich ab, um nichts zu öffnen.';
  }

  @override
  String get remoteEditHost => 'Bearbeiten…';

  @override
  String get remoteEditHostTitle => 'Host bearbeiten';

  @override
  String get remoteDeleteHost => 'Host löschen';

  @override
  String remoteDeleteHostTitle(String host) {
    return 'Host $host löschen?';
  }

  @override
  String get remoteDeleteHostDetail =>
      'Dadurch wird nur das Hostprofil auf diesem Computer entfernt. Auf dem Host ändert sich nichts; offene Tabs und Commit-Entwürfe bleiben erhalten.';

  @override
  String get remoteSaveHost => 'Host speichern';

  @override
  String get remoteHostLabel => 'Name';

  @override
  String get remoteHostLabelPlaceholder => 'Arbeitsrechner';

  @override
  String get remoteHostAlias => 'SSH-Ziel';

  @override
  String get remoteAliasExample => 'user@devbox';

  @override
  String get remoteHostAliasHelp =>
      'Ein SSH-Host-Alias, Hostname oder user@host. Verwendet deine SSH-Konfiguration, Schlüssel und deinen Agenten. Der Host muss bereits vertrauenswürdig sein; Passwortabfragen und das Teilen einer bestehenden SSH-Verbindung werden nicht unterstützt.';

  @override
  String get remoteHostAppearanceHelp =>
      'Tabs dieses Hosts zeigen statt seines Namens sein Symbol in dieser Farbe.';

  @override
  String get remoteAccess => 'Zugriff';

  @override
  String get remoteAccessReadOnly => 'Nur lesen';

  @override
  String get remoteAccessChanges => 'Änderungen erlauben';

  @override
  String get remoteAccessReadOnlyDetail =>
      'GitLama zeigt die Repositorys auf diesem Host und ändert nichts.';

  @override
  String get remoteAccessChangesDetail =>
      'GitLama kann vormerken, committen, verwerfen, Branches und Stashes ändern sowie mit den Git-Zugangsdaten des Hosts fetchen, pullen und pushen. Eine Änderung während der Verbindung verbindet den Host neu.';

  @override
  String get remoteAccessFirstConnection =>
      'Gilt für das Konto, das GitLama bei der ersten Verbindung prüft.';

  @override
  String get remoteAccessNextConnection =>
      'Gilt, sobald sich dieser Host wieder verbindet.';

  @override
  String get remoteHostTrustHelp =>
      'GitLama fragt nie nach Passwörtern oder Schlüsseln. Der Hostschlüssel muss bereits vertrauenswürdig sein, und dein Schlüssel muss im SSH-Agent geladen sein. Prüfe zuerst im Terminal, ob der Alias funktioniert.';

  @override
  String get remoteLabelInvalid =>
      'Gib einen Namen mit bis zu 128 Zeichen ohne Steuerzeichen ein.';

  @override
  String get remoteAliasInvalid =>
      'Verwende einen Host oder user@host mit bis zu 128 ASCII-Zeichen. Jeder Teil beginnt mit einem Buchstaben oder einer Ziffer und enthält Buchstaben, Ziffern, Punkte, Unterstriche oder Bindestriche. Ports und Optionen sind nicht erlaubt.';

  @override
  String get remoteAliasChangeWarning =>
      'Eine Änderung des Alias entfernt die bestätigte Identität und die Erlaubnis zum Vormerken und Committen. Die nächste Verbindung bestätigt den Host erneut.';

  @override
  String get remoteProfileSaveFailed =>
      'Der Host konnte nicht gespeichert werden. Versuche es erneut.';

  @override
  String get remoteProfileSaveLocked =>
      'Die Einstellungsdatei war belegt, weil ein anderer GitLama-Prozess sie gerade schrieb. Versuche es erneut.';

  @override
  String get remoteProfileSaveWriteFailed =>
      'GitLama konnte seine Einstellungsdatei nicht schreiben. Prüfe, ob auf dem Datenträger Platz frei ist und der Einstellungsordner beschreibbar ist.';

  @override
  String get remoteProfileSaveRejected =>
      'Die Einstellungsprüfung hat diese Änderung abgelehnt, daher wurde nichts gespeichert. Das ist ein Fehler in GitLama; bitte melde ihn mit dem Fehlercode.';

  @override
  String get remoteProfileSaveStale =>
      'Der Host wurde inzwischen geändert oder entfernt, oder seine Werte wurden nicht akzeptiert. Schließe diesen Dialog und versuche es erneut.';

  @override
  String get remoteProfileSaveUnavailable =>
      'Remote-Hosts sind gerade nicht verfügbar. Starte GitLama neu und versuche es erneut.';

  @override
  String remoteProfileSaveCode(String code) {
    return 'Fehlercode: $code';
  }

  @override
  String remoteHostRowVerified(String alias, String account) {
    return '$alias · Konto $account';
  }

  @override
  String remoteHostRowUnverified(String alias) {
    return '$alias · noch nicht bestätigt';
  }

  @override
  String remoteHostAccount(String account) {
    return 'Bestätigtes Konto: $account';
  }

  @override
  String get remoteHostUnknown => 'Entfernter Host';

  @override
  String get remoteHostUnknownAccount => 'unbekannt';

  @override
  String get remoteConnect => 'Verbinden';

  @override
  String get remoteCancelConnect => 'Verbindung abbrechen';

  @override
  String get remoteDisconnect => 'Trennen';

  @override
  String get remoteChooseFolder => 'Ordner auswählen…';

  @override
  String get remoteChooseFolderDisabled =>
      'Verbinde dich zuerst mit einem Host';

  @override
  String get remotePhaseIdle => 'Nicht verbunden';

  @override
  String get remotePhaseConnecting => 'Verbindung über SSH wird aufgebaut…';

  @override
  String get remotePhaseHandshaking => 'GitLama-Helfer wird gestartet…';

  @override
  String get remotePhaseReady => 'Verbunden';

  @override
  String get remotePhaseDisconnecting => 'Wird getrennt…';

  @override
  String get remotePhaseDisconnected => 'Verbindung verloren';

  @override
  String get remotePhaseFailed => 'Verbindung fehlgeschlagen';

  @override
  String get remotePhaseIdentityChanged => 'Identität geändert';

  @override
  String get remoteIdentityChangedTitle =>
      'Dieser Host meldet eine andere Identität';

  @override
  String remoteIdentityChangedDetail(String observed, String verified) {
    return 'Der Host meldet jetzt das Konto $observed mit einem anderen Helfer-Speicher als das bestätigte Konto $verified. GitLama hat sich nicht verbunden. Vertraue der neuen Identität nur, wenn du diese Änderung erwartest; Vormerken und Committen werden dann ausgeschaltet.';
  }

  @override
  String get remoteTrustIdentity => 'Neuer Identität vertrauen';

  @override
  String get remoteHelperLocationLabel =>
      'Erwarteter Ort des Helfers auf dem Host:';

  @override
  String get remoteHelperBuildPlaceholder => '<helfer-id>';

  @override
  String get remoteHelperExactLocationHelp =>
      'Installiere das Helferpaket dieser GitLama-Version an diesem Ort und mache die Datei ausführbar.';

  @override
  String get remoteHelperLocationHelp =>
      'Ersetze <helfer-id> durch die Helfer-ID des Helferpakets, das zu dieser GitLama-Version gehört, und mache die Datei ausführbar.';

  @override
  String get remotePhaseInstalling => 'GitLama-Helfer wird installiert…';

  @override
  String get remoteInstallHelper => 'Helfer installieren';

  @override
  String get remoteInstallHelperHelp =>
      'GitLama kann den Helfer dieser Version per SSH auf den Host kopieren und dort prüfen.';

  @override
  String remoteInstallHelperTitle(String host) {
    return 'Helfer auf $host installieren?';
  }

  @override
  String remoteInstallHelperDetail(String alias) {
    return 'GitLama kopiert seinen Helfer über den SSH-Alias $alias in dein Home-Verzeichnis auf dem Host, prüft die Prüfsumme und ob er startet. Außerhalb dieses Verzeichnisses ändert sich nichts, und es werden keine Administratorrechte benötigt.';
  }

  @override
  String remoteInstallHelperSize(String size) {
    return 'Größe: $size';
  }

  @override
  String remoteInstallHelperDigest(String digest) {
    return 'SHA-256: $digest';
  }

  @override
  String get settingsRemoteHosts => 'Remote-Hosts';

  @override
  String get settingsRemoteHostsDetail =>
      'Computer, die GitLama über deine SSH-Konfiguration erreicht, was es dort darf und ob es ihren Helfer aktuell hält.';

  @override
  String get remoteHelperVersion => 'Helferversion';

  @override
  String get remoteHelperVersionDetail =>
      'Hosts behalten ihren installierten Helfer, bis ein GitLama-Update eine neuere Helferversion braucht.';

  @override
  String get remoteHelperVersionUnknown => 'Unbekannt';

  @override
  String get remoteAutoInstallHelper => 'Helfer automatisch installieren';

  @override
  String get remoteAutoInstallHelperDetail =>
      'Fehlt diesem Host der Helfer, den diese GitLama-Version braucht, kopiert GitLama ihn ohne Nachfrage über SSH und prüft ihn.';

  @override
  String get remoteAccessStatusReadOnly => 'Nur lesen';

  @override
  String get remoteAccessStatusChanges => 'Änderungen erlaubt';

  @override
  String remoteHostStatusTooltip(String host) {
    return 'Was GitLama auf $host darf';
  }

  @override
  String get remoteHostSettings => 'Host-Einstellungen…';

  @override
  String get remoteManageConnection => 'Verbindung…';

  @override
  String get remoteInstallHelperConfirm => 'Installieren';

  @override
  String get remoteFailureInstallUnavailable =>
      'Dieser GitLama-Build kann den Helfer nicht installieren. Installiere ihn manuell am unten genannten Ort.';

  @override
  String get remoteFailureInstallDirectory =>
      'Das Helferverzeichnis auf dem Host konnte nicht angelegt werden oder ist ein symbolischer Link.';

  @override
  String get remoteFailureInstallWrite =>
      'Der Helfer konnte auf dem Host nicht geschrieben werden. Prüfe den freien Speicher in deinem Home-Verzeichnis.';

  @override
  String get remoteFailureInstallDigest =>
      'Der Helfer kam beschädigt auf dem Host an und wurde nicht installiert. Versuche es erneut.';

  @override
  String get remoteFailureInstallExecute =>
      'Der Helfer konnte auf dem Host nicht starten. Das Home-Verzeichnis ist eventuell ohne Ausführungsrecht eingehängt.';

  @override
  String get remoteFailureInstallFailed =>
      'Der Helfer konnte nicht installiert werden. Der Host benötigt sha256sum oder shasum und eine übliche POSIX-Shell.';

  @override
  String get remoteFailureOutcomeUnknown =>
      'GitLama konnte nicht bestätigen, ob die Änderung auf dem Host angewendet wurde. Sie wurde möglicherweise angewendet oder auch nicht. Prüfe das Repository, bevor du es erneut versuchst.';

  @override
  String get remoteFailureSshUnavailable =>
      'OpenSSH wurde auf diesem Computer nicht gefunden. Installiere den OpenSSH-Client und versuche es erneut.';

  @override
  String get remoteFailureSshUnsupported =>
      'Der OpenSSH-Client auf diesem Computer wird nicht unterstützt. Installiere einen aktuellen OpenSSH-Client.';

  @override
  String remoteFailureSshConnectionFailed(String alias) {
    return 'SSH konnte keine Verbindung herstellen. Prüfe, ob ssh $alias im Terminal funktioniert, der Hostschlüssel vertrauenswürdig ist und dein Schlüssel im SSH-Agent geladen ist.';
  }

  @override
  String get remoteFailureHelperNotInstalled =>
      'Der GitLama-Helfer für diese Version ist auf dem Host nicht installiert.';

  @override
  String get remoteFailureUnsupportedPlatform =>
      'Das System des Hosts wird nicht unterstützt. Remote-Arbeitsbereiche brauchen einen Linux-x86_64-Host oder einen Mac.';

  @override
  String get remoteFailureBootstrapFailed =>
      'Der GitLama-Helfer konnte auf dem Host nicht gestartet werden.';

  @override
  String get remoteFailureHandshakeTimeout =>
      'Der GitLama-Helfer hat nicht rechtzeitig geantwortet.';

  @override
  String get remoteFailureProtocolMismatch =>
      'Der Helfer auf dem Host spricht eine andere Protokollversion. Installiere den Helfer, der zu dieser GitLama-Version gehört.';

  @override
  String get remoteFailureBuildMismatch =>
      'Der Helfer auf dem Host gehört zu einer anderen Helferversion. Installiere den Helfer, der zu dieser GitLama-Version gehört.';

  @override
  String get remoteFailureGitMissing =>
      'Git ist auf dem Host nicht installiert.';

  @override
  String get remoteFailureGitUnsupported =>
      'Die Git-Version auf dem Host ist zu alt. Remote-Arbeitsbereiche brauchen Git 2.39 oder neuer.';

  @override
  String get remoteFailureStoreUnavailable =>
      'Der Helfer konnte seinen privaten Zustandsordner auf dem Host nicht verwenden.';

  @override
  String get remoteFailureIdentityChanged =>
      'Der Host meldet jetzt ein anderes Konto oder einen anderen Helfer-Speicher.';

  @override
  String get remoteFailureIdentityMismatch =>
      'Dieses Repository gehört auf dem Host zu einem anderen Konto oder Helfer-Speicher.';

  @override
  String get remoteFailureProtocolViolation =>
      'Der Helfer hat eine ungültige Antwort gesendet, daher wurde die Verbindung geschlossen.';

  @override
  String get remoteFailureDisconnected =>
      'Die Verbindung zum Host ist abgebrochen.';

  @override
  String get remoteFailureTimedOut =>
      'Der Host hat nicht rechtzeitig geantwortet.';

  @override
  String get remoteFailureCanceled =>
      'Der Verbindungsversuch wurde abgebrochen.';

  @override
  String get remoteFailureCapacity =>
      'Die Höchstzahl an Hosts oder Verbindungen ist erreicht.';

  @override
  String get remoteFailureUnsupported =>
      'Das ist für diesen Host nicht verfügbar.';

  @override
  String get remoteFailurePathNotFound =>
      'Dieser Ordner existiert auf dem Host nicht.';

  @override
  String get remoteFailurePermissionDenied =>
      'Das Konto auf dem Host darf diesen Ordner nicht lesen.';

  @override
  String get remoteFailureNotDirectory => 'Das ist kein Ordner.';

  @override
  String get remoteFailureDirectoryChanged =>
      'Der Ordner hat sich während der Auflistung geändert.';

  @override
  String get remoteFailureCursorExpired =>
      'Die Auflistung ist abgelaufen. Starte sie erneut, um mehr zu sehen.';

  @override
  String get remoteFailurePreviewExpired =>
      'Die Änderung wurde auf einem älteren Stand vorbereitet. Prüfe sie und versuche es erneut.';

  @override
  String get remoteFailurePreconditionFailed =>
      'Das Repository hat sich auf dem Host geändert. Prüfe es und versuche es erneut.';

  @override
  String get remoteFailureOperationIdConflict =>
      'Die Änderung konnte nicht erfasst werden, daher wurde nichts angewendet.';

  @override
  String get remoteFailureReceiptCapacity =>
      'Zu viele Änderungen auf diesem Host müssen noch geprüft werden. Prüfe sie zuerst unter Remote-Änderungen.';

  @override
  String get remoteFailureInternal =>
      'Bei der Hostverbindung ist etwas schiefgelaufen.';

  @override
  String get remotePathAbsoluteRequired =>
      'Gib einen absoluten Pfad ein, der mit / beginnt. ~ und relative Pfade werden nicht unterstützt.';

  @override
  String get remotePathInvalid =>
      'Dieser Pfad ist zu lang oder enthält ein nicht erlaubtes Zeichen.';

  @override
  String remoteDirectoryTitle(String host) {
    return 'Ordner auf $host wählen';
  }

  @override
  String get remoteDirectoryUp => 'Übergeordneter Ordner';

  @override
  String get remoteDirectoryHome => 'Persönlicher Ordner';

  @override
  String get remoteDirectoryCurrent => 'Aktueller Ordner';

  @override
  String get remoteDirectoryLoading => 'Wird geladen…';

  @override
  String get remoteDirectoryPath => 'Ordnerpfad';

  @override
  String get remoteDirectoryPathPlaceholder => '/home/ich/projekt';

  @override
  String get remoteDirectoryPathHelp =>
      'Drücke Eingabe oder Gehe zu, um diesen Pfad zu durchsuchen, oder Öffnen, um ihn zu öffnen.';

  @override
  String get remotePathChecking => 'Pfad wird auf dem Host geprüft…';

  @override
  String get remotePathFolder => 'Dieser Ordner existiert auf dem Host.';

  @override
  String get remotePathNotFolder =>
      'Dieser Pfad existiert, ist aber kein Ordner.';

  @override
  String get remotePathMissing =>
      'Auf dem Host gibt es keinen Ordner unter diesem Pfad.';

  @override
  String get remoteDirectoryNoMatch =>
      'Keine Einträge beginnen mit dem eingegebenen Namen.';

  @override
  String get remoteDirectoryGo => 'Gehe zu';

  @override
  String get remoteDirectoryOpen => 'Öffnen';

  @override
  String get remoteDirectoryOpenDisabled => 'Warte, bis der Ordner geladen ist';

  @override
  String get remoteDirectoryLoadMore => 'Mehr laden';

  @override
  String get remoteDirectoryTruncated =>
      'Dieser Ordner hat mehr Einträge, als GitLama auflistet. Gib einen Pfad ein, um einen nicht angezeigten Ordner zu erreichen.';

  @override
  String get remoteDirectoryEmpty => 'Dieser Ordner ist leer.';

  @override
  String get remoteDirectoryUnavailable => 'Es wird kein Ordner angezeigt.';

  @override
  String get remoteDirectoryRefresh => 'Aktualisieren';

  @override
  String get remoteDirectoryRestart => 'Auflistung neu starten';

  @override
  String get remoteEntryRepository => 'Repository';

  @override
  String get remoteEntrySymlink => 'Verknüpfung';

  @override
  String get remoteEntryFile => 'Datei';

  @override
  String get remoteEntryOther => 'Sonstiges';

  @override
  String get remoteRepositoryCapacity =>
      'Die maximale Anzahl geöffneter Repositorys für diese Verbindung ist erreicht. Schließe einen anderen Repository-Tab auf diesem Host und versuche es erneut.';

  @override
  String get remoteOpenFailed =>
      'Das Repository auf dem Host konnte nicht geöffnet werden.';

  @override
  String get remoteRecentHostMissing =>
      'Der Host dieses Repositorys ist nicht mehr eingerichtet. Füge ihn unter Remote-Repository öffnen erneut hinzu.';

  @override
  String remoteRecentSubtitle(String host, String path) {
    return '$host · $path';
  }

  @override
  String get remoteReconnect => 'Neu verbinden';

  @override
  String get remoteReviewHost => 'Host prüfen…';

  @override
  String remoteReconnectIn(String host, int seconds) {
    return 'Verbindung zu $host verloren. Neuer Versuch in $seconds s…';
  }

  @override
  String remoteReconnecting(String host) {
    return 'Verbindung zu $host wird wiederhergestellt…';
  }

  @override
  String remoteReconnectGaveUp(String host) {
    return 'Verbindung zu $host konnte nicht wiederhergestellt werden';
  }

  @override
  String remoteReconnectStopped(String host) {
    return 'Keine automatische Verbindung zu $host';
  }

  @override
  String get remoteReconnectStale =>
      'Der zuletzt empfangene Stand wird angezeigt.';

  @override
  String get remoteReconnectNow => 'Jetzt verbinden';

  @override
  String get remoteReconnectStop => 'Stoppen';

  @override
  String get remoteReconnectTryAgain => 'Erneut versuchen';

  @override
  String remoteReconnected(String host) {
    return 'Wieder mit $host verbunden';
  }

  @override
  String remoteStaleBanner(String host) {
    return 'Von $host getrennt – der zuletzt empfangene Stand wird angezeigt.';
  }

  @override
  String remoteHostBadge(String host) {
    return 'Auf $host';
  }

  @override
  String remoteHostBadgeDisconnected(String host) {
    return 'Auf $host, getrennt';
  }

  @override
  String remoteTabDisconnectedTitle(String host) {
    return 'Nicht mit $host verbunden';
  }

  @override
  String get remoteTabDisconnectedDetail =>
      'Verbinde dich erneut, um dieses Repository wieder zu öffnen.';

  @override
  String get remoteTabHostDeletedDetail =>
      'Das Hostprofil dieses Repositorys wurde gelöscht. Schließe den Tab oder füge den Host erneut hinzu und öffne das Repository.';

  @override
  String remoteTabIdentityChangedTitle(String host) {
    return '$host meldet eine andere Identität';
  }

  @override
  String remoteTabRepositoryChangedTitle(String host) {
    return 'Das Repository auf $host hat sich geändert';
  }

  @override
  String get remoteTabRepositoryChangedDetail =>
      'Dieser Ordner enthält nicht mehr das Repository, das GitLama hier geöffnet hat; es wurde möglicherweise ersetzt, verschoben oder wiederhergestellt. Öffne es nur erneut, wenn du dieses Repository an diesem Pfad erwartest.';

  @override
  String get remoteTabTrustRepository => 'Vertrauen und öffnen';

  @override
  String get remoteTabIdentityChangedDetail =>
      'Konto, Helfer-Speicher oder Repository des Hosts stimmen nicht mehr mit dem überein, was GitLama bestätigt hat. Prüfe den Host und entscheide, ob du ihm vertraust.';

  @override
  String get remoteOperationsTitle => 'Remote-Änderungen';

  @override
  String get remoteOperationsDescription =>
      'Änderungen, die GitLama auf deinen Hosts vorgenommen hat, die neuesten zuerst.';

  @override
  String remoteOperationsIndicator(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Remote-Änderungen prüfen',
      one: '1 Remote-Änderung prüfen',
    );
    return '$_temp0';
  }

  @override
  String get remoteOperationsUncertain =>
      'GitLama konnte das Ergebnis einiger Änderungen nicht bestätigen. Sie wurden möglicherweise angewendet oder auch nicht. Prüfe das Repository, bevor du es erneut versuchst; GitLama wiederholt sie nie von selbst.';

  @override
  String get remoteOperationsLedgerUnavailable =>
      'Die Aufzeichnung der Remote-Änderungen auf diesem Computer kann nicht gelesen werden. Vormerken und Committen auf Hosts bleiben aus, bis sie wieder lesbar ist.';

  @override
  String get remoteOperationsEmpty => 'Keine Remote-Änderungen aufgezeichnet.';

  @override
  String remoteOperationSubtitle(String host, String family, String state) {
    return '$host · $family · $state';
  }

  @override
  String get remoteOperationStage => 'Vormerken';

  @override
  String get remoteOperationCommit => 'Commit';

  @override
  String get remoteOperationRefs => 'Branches und Tags';

  @override
  String get remoteOperationStash => 'Stash';

  @override
  String get remoteOperationDiscard => 'Verwerfen';

  @override
  String get remoteOperationHistory =>
      'Zusammenführen, Cherry-Pick oder Revert';

  @override
  String get remoteOperationRebase => 'Rebase';

  @override
  String get remoteOperationRestack => 'Restack';

  @override
  String get remoteOperationBisect => 'Bisect';

  @override
  String get remoteOperationConflict => 'Konfliktlösung';

  @override
  String get remoteOperationSequencer => 'Fortsetzen oder abbrechen';

  @override
  String get remoteOperationSnapshot => 'Snapshot';

  @override
  String get remoteOperationSnapshotRestore => 'Snapshot-Wiederherstellung';

  @override
  String get remoteOperationRestore => 'Datei wiederherstellen';

  @override
  String get remoteOperationIndexLock => 'Sperrdatei von Git entfernen';

  @override
  String get remoteOperationPatch => 'Patch';

  @override
  String get remoteOperationExtension => 'Worktrees, Submodule und LFS';

  @override
  String get remoteOperationTransfer => 'Fetch, Pull oder Push';

  @override
  String get remoteOperationRunning => 'Läuft';

  @override
  String get remoteOperationSucceeded => 'Angewendet';

  @override
  String get remoteOperationFailed => 'Fehlgeschlagen';

  @override
  String get remoteOperationNotApplied => 'Nicht angewendet';

  @override
  String get remoteOperationDesiredState => 'Bereits im gewünschten Zustand';

  @override
  String get remoteOperationPartial => 'Teilweise angewendet';

  @override
  String get remoteOperationUnknown => 'Ergebnis unbekannt';

  @override
  String get remoteOperationCheckAgain => 'Erneut prüfen';

  @override
  String get remoteOperationCheckDisconnected =>
      'Verbinde dich mit dem Host, um erneut zu prüfen';

  @override
  String get remoteOperationCheckFailed =>
      'Der Host konnte nicht gefragt werden. Versuche es später erneut.';

  @override
  String get remoteOperationDismiss => 'Ausblenden';

  @override
  String get remoteOperationDismissFailed =>
      'Der Eintrag konnte nicht entfernt werden.';

  @override
  String remoteTabLabel(String repository, String host) {
    return '$repository · $host';
  }

  @override
  String get remoteOutcomeUnknownTitle => 'Ergebnis unbekannt';

  @override
  String get remoteOutcomeUnknownCommit =>
      'Der Commit wurde an den Host gesendet, aber GitLama konnte nicht bestätigen, ob er erstellt wurde. Er wurde möglicherweise angewendet oder auch nicht. Deine Nachricht bleibt erhalten. Prüfe den Verlauf, bevor du es erneut versuchst.';

  @override
  String get remoteOutcomeUnknownStage =>
      'Die Änderung an der Vormerkung wurde an den Host gesendet, aber GitLama konnte nicht bestätigen, ob sie angewendet wurde. Sie wurde möglicherweise angewendet oder auch nicht. Prüfe die Änderungen, bevor du es erneut versuchst.';

  @override
  String get remoteOutcomeUnknownChange =>
      'Die Änderung wurde an den Host gesendet, aber GitLama konnte nicht bestätigen, ob sie angewendet wurde. Prüfe sie unter Remote-Änderungen, bevor du es erneut versuchst.';

  @override
  String get remoteTransferAuthentication =>
      'Der Host konnte sich nicht beim Git-Server anmelden. Richte die Zugangsdaten für dieses Repository auf dem Host ein und versuche es erneut.';

  @override
  String get remoteTransferHostKey =>
      'Der Host vertraut dem Schlüssel des Git-Servers noch nicht. Verbinde dich einmal in einem Terminal auf dem Host mit dem Server und versuche es dann erneut.';

  @override
  String get inspectorLocation => 'Inspektor-Position';

  @override
  String get inspectorBack => 'Zurück';

  @override
  String get inspectorForward => 'Vorwärts';

  @override
  String get inspectorLensDiff => 'Diff';

  @override
  String get inspectorLensContents => 'Inhalt';

  @override
  String get inspectorLensHistory => 'Verlauf';

  @override
  String get inspectorLenses => 'Ansicht';

  @override
  String get inspectorScope => 'Dateien';

  @override
  String get inspectorScopeAll => 'Alle Dateien';

  @override
  String get inspectorScopeAllUnavailable => 'Bei Vergleichen nicht verfügbar';

  @override
  String get inspectorOpenInWindow => 'In neuem Fenster öffnen';

  @override
  String get inspectorMaximize => 'Inspektor maximieren';

  @override
  String get inspectorRestoreLayout => 'Layout wiederherstellen';

  @override
  String get inspectorShowFiles => 'Dateien einblenden';

  @override
  String get inspectorHideFiles => 'Dateien ausblenden';

  @override
  String get inspectorBrowseAllFiles => 'Alle Dateien durchsuchen';

  @override
  String get inspectorMoreActions => 'Weitere Aktionen';

  @override
  String get inspectorShowInGraph => 'Im Graphen zeigen';

  @override
  String get inspectorShowInMainWindow => 'Im Hauptfenster zeigen';

  @override
  String get inspectorRepositoryNotOpen =>
      'Repository ist in GitLama nicht geöffnet';

  @override
  String get inspectorShowCommit => 'Commit anzeigen';

  @override
  String get inspectorBlameAtCommit => 'Zeilenzuordnung für diesen Commit';

  @override
  String get inspectorBlameBefore => 'Zeilenzuordnung vor dieser Änderung';

  @override
  String get inspectorLineHistory => 'Zeilenverlauf';

  @override
  String inspectorLines(int first, int last) {
    return 'Zeilen $first–$last';
  }

  @override
  String get inspectorClearLines => 'Gesamten Dateiverlauf zeigen';

  @override
  String get inspectorNotChanged => 'In diesem Commit nicht geändert';

  @override
  String get inspectorDeletedHere => 'In diesem Commit gelöscht';

  @override
  String get inspectorBlameNeedsText =>
      'Zeilenzuordnung benötigt eine Textdatei';

  @override
  String get inspectorSubmoduleNoContents =>
      'Submodule haben hier keinen Inhalt';

  @override
  String get inspectorFolderOnlyHistory => 'Ordner haben nur einen Verlauf';

  @override
  String get inspectorNoHistory => 'Kein Commit hat diesen Pfad geändert.';

  @override
  String get inspectorLoadOlder => 'Älteren Verlauf laden';

  @override
  String get inspectorLoadMoreFiles => 'Weitere Dateien laden';

  @override
  String inspectorLoading(String commit) {
    return '$commit wird geladen …';
  }

  @override
  String get inspectorLoadFailed => 'Das konnte nicht geladen werden.';

  @override
  String get inspectorMissingObject =>
      'Dieser Commit ist im Repository nicht verfügbar.';

  @override
  String get inspectorRepositoryClosed => 'Das Repository wurde geschlossen.';

  @override
  String get inspectorRemoteHostNotConnected => 'Der Host ist nicht verbunden.';

  @override
  String get inspectorRemoteHostNotConnectedDetail =>
      'Verbinde ihn im Hauptfenster und versuche es dann erneut.';

  @override
  String inspectorShowing(String label) {
    return '$label wird angezeigt';
  }

  @override
  String inspectorHistoryOf(String path) {
    return 'Verlauf von $path';
  }

  @override
  String inspectorChangedFilesIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geänderte Dateien in diesem Ordner',
      one: '1 geänderte Datei in diesem Ordner',
    );
    return '$_temp0';
  }

  @override
  String get fileActionShowDiff => 'Diff anzeigen';

  @override
  String get fileActionShowContents => 'Inhalt anzeigen';

  @override
  String get fileActionFileHistory => 'Dateiverlauf';

  @override
  String get fileActionFolderHistory => 'Ordnerverlauf';

  @override
  String get fileActionExternalDiff => 'Im externen Diff-Werkzeug öffnen';

  @override
  String get fileActionCopyCommitHash => 'Commit-Hash kopieren';

  @override
  String get fileActionNoCommit => 'Noch kein Commit';

  @override
  String fileActionHeadSuffix(String action) {
    return '$action (HEAD)';
  }

  @override
  String get settingsInspectionOpenIn => 'Dateiinspektion öffnen in';

  @override
  String get settingsInspectionOpenInDetail =>
      'Wähle, wo Zeilenzuordnung, Inhalt und Verlauf öffnen. Halte ⌘ oder Strg, um einmalig den anderen Ort zu nutzen.';

  @override
  String get settingsHistoryOtherRefs => 'Andere Refs im Verlauf anzeigen';

  @override
  String get settingsHistoryOtherRefsDetail =>
      'Der Verlauf folgt Branches, Remote-Branches, Tags und dem Stash. Schalte dies ein, um auch Commits zu zeigen, die nur andere Refs erreichen, etwa Notes oder Checkpoints anderer Werkzeuge. Die Verlaufsleiste ändert dieselbe Einstellung.';

  @override
  String get settingsInspectionOpenInPane => 'Detailbereich';

  @override
  String get settingsInspectionOpenInWindow => 'Neues Fenster';

  @override
  String get gitFolderCollapsed => 'Eingeklappt';

  @override
  String get gitFolderExpanded => 'Ausgeklappt';

  @override
  String get commandInspectorBack => 'Inspektor zurück';

  @override
  String get commandInspectorForward => 'Inspektor vorwärts';

  @override
  String get commandInspectorLensDiff => 'Diff der Datei anzeigen';

  @override
  String get commandInspectorLensContents => 'Inhalt der Datei anzeigen';

  @override
  String get commandInspectorLensBlame => 'Zeilenzuordnung der Datei anzeigen';

  @override
  String get commandInspectorLensHistory => 'Verlauf der Datei anzeigen';

  @override
  String get commandInspectorOpenInWindow =>
      'Inspektor in neuem Fenster öffnen';

  @override
  String get commandInspectorToggleMaximize =>
      'Inspektor maximieren oder wiederherstellen';

  @override
  String get commandInspectorToggleFiles =>
      'Inspektor-Dateien ein- oder ausblenden';

  @override
  String get commandInspectorAllFiles => 'Alle Dateien des Commits durchsuchen';

  @override
  String get inspectorNoFiles => 'Dieser Commit enthält keine Dateien.';

  @override
  String get initializeLocation => 'Ort';

  @override
  String get initializeLocationThisComputer => 'Dieser Computer';

  @override
  String get initializeRemoteDestinationHint =>
      'Erstellt ein leeres Git-Repository auf dem Host. Im nächsten Schritt wählst du dort einen Ordner oder gibst den Pfad eines neuen Ordners ein.';

  @override
  String remoteInitializeDirectoryTitle(String host) {
    return 'Wählen, wo das Repository auf $host erstellt wird';
  }

  @override
  String get remoteInitializePathHelp =>
      'Zu einem leeren Ordner wechseln oder den Pfad eines neuen Ordners eingeben. Fehlende Ordner werden erstellt.';

  @override
  String get remoteInitializePathNew =>
      'Unter diesem Pfad wird ein neuer Ordner erstellt.';

  @override
  String get remoteInitializeHere => 'Hier initialisieren';

  @override
  String get mutationOutcomeUncertain =>
      'Git hat das Repository möglicherweise geändert, aber GitLama konnte das Ergebnis nicht bestätigen. Prüfe das Repository vor einem erneuten Versuch.';

  @override
  String get stashMessagePlaceholder => 'Woran arbeitest du gerade?';

  @override
  String get stashPushIntro =>
      'Legt Änderungen beiseite, damit der Arbeitsbaum sauber ist. Du kannst sie jederzeit zurückholen.';

  @override
  String stashScopeAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle Änderungen ($count Dateien)',
      one: 'Alle Änderungen (1 Datei)',
    );
    return '$_temp0';
  }

  @override
  String get stashScopeSelected => 'Nur ausgewählte Dateien';

  @override
  String get stashIncludeUntrackedHelp =>
      'Auch Dateien stashen, die Git noch nicht verfolgt.';

  @override
  String get stashKeepIndexHelp =>
      'Vorgemerkte Änderungen kommen in den Stash und bleiben zusätzlich vorgemerkt.';

  @override
  String stashSelectionCount(int selected, int count) {
    return '$selected von $count ausgewählt';
  }

  @override
  String get stashSelectAll => 'Alle auswählen';

  @override
  String get stashSelectNone => 'Keine auswählen';

  @override
  String get stashSelectFilesReason => 'Wähle mindestens eine Datei aus.';

  @override
  String stashSelectedUntrackedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count neue Dateien können nur mit allen Änderungen gestasht werden.',
      one: '1 neue Datei kann nur mit allen Änderungen gestasht werden.',
    );
    return '$_temp0';
  }

  @override
  String get stashPreviewFiles => 'Dateien';

  @override
  String stashPreviewFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String get stashPreviewNewFiles => 'Neue Dateien';

  @override
  String get stashPreviewIncluded => 'Eingeschlossen';

  @override
  String get stashPreviewStaged => 'Vorgemerkte Änderungen';

  @override
  String get stashPreviewStillStaged => 'Bleiben vorgemerkt';

  @override
  String get restackPreviewSummary =>
      'Jeder Branch wird in der gezeigten Reihenfolge auf den neuesten Commit des Branches gesetzt, auf dem er aufbaut.';

  @override
  String restackStepOnto(String branch) {
    return 'auf $branch';
  }

  @override
  String historyCherryPickIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Kopiert die $count ausgewählten Commits als neue Commits in den aktuellen Branch.',
      one:
          'Kopiert den ausgewählten Commit als neuen Commit in den aktuellen Branch.',
    );
    return '$_temp0';
  }

  @override
  String historyRevertIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Fügt neue Commits hinzu, die die $count ausgewählten Commits rückgängig machen. Die ursprünglichen Commits bleiben im Verlauf.',
      one:
          'Fügt einen neuen Commit hinzu, der den ausgewählten Commit rückgängig macht. Der ursprüngliche Commit bleibt im Verlauf.',
    );
    return '$_temp0';
  }

  @override
  String get historyRevertApplyIntro =>
      'Macht die Änderungen des ausgewählten Commits rückgängig und merkt sie zur Prüfung vor. Es wird kein Commit erstellt.';

  @override
  String get historyRevertApplyHint =>
      'Wenn du die Änderungen zuerst prüfen möchtest, wende sie ohne Commit an.';

  @override
  String get historyMergePreviewTitle => 'Merge prüfen';

  @override
  String get historyCherryPickPreviewTitle => 'Cherry-Pick prüfen';

  @override
  String get historyRevertPreviewTitle => 'Revert prüfen';

  @override
  String get historyPreviewCurrentBranch => 'Aktueller Branch';

  @override
  String get historyPreviewConflicts => 'Konflikte';

  @override
  String get conflictCheckNone => 'Keine erwartet';

  @override
  String conflictCheckFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wahrscheinlich in $count Dateien',
      one: 'Wahrscheinlich in 1 Datei',
    );
    return '$_temp0';
  }

  @override
  String get conflictCheckUnavailable => 'Konnte nicht geprüft werden';

  @override
  String get conflictCheckEstimate => 'Die Konfliktprüfung ist eine Schätzung.';

  @override
  String get conflictCheckPartial =>
      'Die Konfliktprüfung ist eine Schätzung und hat nicht jeden Commit erfasst.';

  @override
  String rebaseEditorSummary(String branch, String onto) {
    return 'Lege fest, was mit jedem Commit von $branch passiert. Sie werden von oben nach unten auf $onto neu angewendet.';
  }

  @override
  String rebaseConflictsExpected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Dateien werden wahrscheinlich Konflikte haben. Du kannst sie während des Rebase lösen.',
      one:
          '1 Datei wird wahrscheinlich Konflikte haben. Du kannst sie während des Rebase lösen.',
    );
    return '$_temp0';
  }

  @override
  String rebasePublishedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Commits in diesem Plan sind bereits veröffentlicht. Andere müssen ihre Kopien eventuell anpassen.',
      one:
          '1 Commit in diesem Plan ist bereits veröffentlicht. Andere müssen ihre Kopien eventuell anpassen.',
    );
    return '$_temp0';
  }

  @override
  String rebaseStepCombinedWith(String subject) {
    return 'zusammengeführt mit $subject';
  }

  @override
  String get rebaseStepCombinedAbove =>
      'zusammengeführt mit dem Commit darüber';

  @override
  String rebaseStepNewMessage(String message) {
    return 'neue Nachricht: $message';
  }

  @override
  String get namedSnapshotRestoreSummary =>
      'Deine aktuellen Änderungen, vorgemerkt und nicht vorgemerkt, werden durch die in diesem Snapshot gespeicherten ersetzt.';

  @override
  String namedSnapshotRestoreFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien ändern sich',
      one: '1 Datei ändert sich',
    );
    return '$_temp0';
  }

  @override
  String get namedSnapshotRestoreStash =>
      'Deine aktuellen Änderungen werden zuerst als Stash gesichert; du findest sie unter Stashes.';

  @override
  String get operationFailureTitle => 'Der Vorgang ist fehlgeschlagen';

  @override
  String get operationCopyReport => 'Supportbericht kopieren';

  @override
  String get operationReportCopied =>
      'Supportbericht kopiert. Er enthält keine Repository-Inhalte, Pfade oder Zugangsdaten.';

  @override
  String get operationUnexpectedFailure =>
      'Ein unerwarteter Fehler hat den Vorgang beendet. Kopieren Sie den Supportbericht aus dieser Meldung oder dem Logbuch.';

  @override
  String operationFailureWithReason(String operation, String reason) {
    return '$operation $reason';
  }

  @override
  String get operationFailureLimit =>
      'Die Anfrage hat eine unterstützte Grenze überschritten.';

  @override
  String get operationFailureTimeout =>
      'Git wurde nicht innerhalb des Zeitlimits fertig.';

  @override
  String get operationFailureMissingObject =>
      'Ein benötigtes Git-Objekt fehlt.';

  @override
  String get operationFailureInvalidRequest =>
      'Die ausgewählten Änderungen sind nicht mehr verfügbar oder die Anfrage konnte nicht geprüft werden.';

  @override
  String get operationFailureBusy =>
      'Das Repository ist beschäftigt. Versuchen Sie es erneut, wenn der laufende Vorgang beendet ist.';

  @override
  String get operationFailureRead =>
      'GitLama konnte den benötigten Repository-Zustand nicht lesen.';

  @override
  String get stagingFailureIndexLocked =>
      'Ein anderer Git-Vorgang verwendet den Index oder hat seine Sperrdatei hinterlassen. Prüfen Sie die Sperre vor einem erneuten Versuch.';

  @override
  String get stagingFailureStatusRead =>
      'GitLama konnte die aktuelle Änderungsliste nicht lesen.';

  @override
  String get stagingFailureIndexRead =>
      'GitLama konnte keinen gültigen Git-Index lesen. Prüfen Sie den Zugriff auf das Repository.';

  @override
  String get stagingFailureContentRead =>
      'GitLama konnte eine ausgewählte Datei zur Prüfung der Änderung nicht lesen.';

  @override
  String get stagingFailureIndexWrite =>
      'GitLama konnte den aktualisierten Git-Index nicht schreiben oder installieren. Prüfen Sie Zugriffsrechte und freien Speicherplatz.';

  @override
  String get stagingFailureGit =>
      'Git hat die Änderung der Vormerkung abgelehnt. Kopieren Sie den Supportbericht mit Fehlercode und Exit-Status des Befehls.';

  @override
  String get operationFailureCanceled =>
      'Der Vorgang wurde vor seinem Abschluss abgebrochen.';

  @override
  String get transferFailureLocked =>
      'Ein anderer Git-Prozess arbeitete in diesem Repository, daher konnte Git es nicht sperren.';

  @override
  String get operationGitOutput => 'Git-Ausgabe';

  @override
  String get operationReportIncludeOutput =>
      'Git-Ausgabe in den Bericht aufnehmen';

  @override
  String get operationReportIncludeOutputDetail =>
      'Sie kann Pfade sowie Branch- oder Remote-Namen enthalten. Prüfe sie, bevor du sie sendest.';

  @override
  String get operationReportGitOutputHeading => 'Git-Ausgabe:';

  @override
  String get operationReportCopiedWithOutput =>
      'Supportbericht mit Git-Ausgabe kopiert. Prüfe ihn, bevor du ihn sendest.';

  @override
  String get repositoryLockTitle => 'Das Repository ist gesperrt';

  @override
  String get repositoryLockExplanation =>
      'Git legt eine Sperrdatei an, während es das Repository ändert. Ein anderes Programm, etwa dein Editor, ein Terminal oder ein Abruf im Hintergrund, arbeitet vielleicht noch, oder ein Git-Prozess wurde beendet, ohne seine Sperre zu entfernen.';

  @override
  String get repositoryLockListTitle => 'Sperrdateien';

  @override
  String get repositoryLockChecking => 'Sperrdateien werden geprüft …';

  @override
  String get repositoryLockNone =>
      'Es sind keine Sperrdateien mehr vorhanden. Der andere Git-Prozess ist fertig, du kannst es erneut versuchen.';

  @override
  String get repositoryLockRecent =>
      'Eine Sperre wurde gerade erst angelegt. Wahrscheinlich arbeitet noch ein anderes Git-Programm: Warte, bis es fertig ist, und versuche es dann erneut.';

  @override
  String get repositoryLockStale =>
      'Diese Sperren sind mehrere Minuten alt. Wenn kein anderes Git-Programm in diesem Repository arbeitet, sind sie übrig geblieben und können entfernt werden.';

  @override
  String get repositoryLockTruncated =>
      'Es gibt mehr Sperrdateien als angezeigt.';

  @override
  String get repositoryLockInspectFailed =>
      'GitLama konnte die Sperrdateien nicht prüfen.';

  @override
  String get repositoryLockRemoteOnly =>
      'Sperrdateien auf einem anderen Computer können nur dort entfernt werden.';

  @override
  String get repositoryLockRemoveWarning =>
      'Entferne Sperren nur, wenn kein anderes Git-Programm in diesem Repository arbeitet. Eine noch verwendete Sperre zu entfernen kann das Repository beschädigen.';

  @override
  String get repositoryLockCheckAgain => 'Erneut prüfen';

  @override
  String get repositoryLockRetry => 'Erneut versuchen';

  @override
  String get repositoryLockRemoveAndRetry =>
      'Sperren entfernen und erneut versuchen';

  @override
  String get repositoryLockChanged =>
      'Eine Sperrdatei hat sich geändert, nachdem sie aufgelistet wurde. Prüfe erneut, bevor du sie entfernst.';

  @override
  String get repositoryLockBusy =>
      'GitLama arbeitet noch in diesem Repository. Warte, bis es fertig ist, und versuche es dann erneut.';

  @override
  String get repositoryLockRemoveFailed =>
      'Eine Sperrdatei konnte nicht entfernt werden. Prüfe ihre Berechtigungen.';

  @override
  String get repositoryLockAgeUnknown => 'Alter unbekannt';

  @override
  String repositoryLockAgeSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Sekunden',
      one: 'vor 1 Sekunde',
    );
    return '$_temp0';
  }

  @override
  String repositoryLockAgeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Minuten',
      one: 'vor 1 Minute',
    );
    return '$_temp0';
  }

  @override
  String repositoryLockAgeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Stunden',
      one: 'vor 1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String repositoryLockAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Tagen',
      one: 'vor 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get transferPrune =>
      'Auf dem Server gelöschte Remote-Branches entfernen';

  @override
  String get transferPruneHelp =>
      'Hält die Liste der Remote-Branches mit dem Server abgeglichen (git fetch --prune).';

  @override
  String get failureFetchWithoutPrune => 'Ohne Bereinigen abrufen';

  @override
  String get failureCaseCollisionTitle =>
      'Branch-Namen unterscheiden sich nur in Groß- und Kleinschreibung';

  @override
  String get failureCaseCollisionRepair =>
      'Die Reparatur entfernt die Kopien dieser Remote-Branches auf diesem Computer und ruft erneut ab, wodurch sie so angelegt werden, wie das Remote sie hat. Deine eigenen Branches und das Remote bleiben unverändert. Damit das für alle aufhört, lass einen der Branches auf dem Server löschen oder umbenennen.';

  @override
  String get failureCaseCollisionServer =>
      'Lass einen der Branches auf dem Server löschen oder umbenennen. Bis dahin rufe ohne Bereinigen ab.';

  @override
  String get failureCaseCollisionRepairAction =>
      'Reparieren und erneut abrufen';

  @override
  String get failureRemoteAheadTitle => 'Das Remote hat neuere Commits';

  @override
  String get failureRemoteAheadMessage =>
      'Der Remote-Branch hat Commits, die deinem Branch fehlen, daher hat Git den Push abgelehnt. Rufe sie ab und führe dann Pull oder Rebase aus, bevor du erneut pushst.';

  @override
  String failureCaseCollisionMessage(String names) {
    return '$names unterscheiden sich nur in Groß- und Kleinschreibung. Im Dateisystem dieses Computers teilen sie sich eine Datei, daher kann Git sie nicht in einem Abruf aktualisieren.';
  }

  @override
  String get fileActionAddToGitignore => 'Zu .gitignore hinzufügen…';

  @override
  String get ignoreDialogTitle => 'Zu .gitignore hinzufügen';

  @override
  String get ignoreDialogFileDescription =>
      'GitLama fügt diesen Eintrag der .gitignore-Datei oben im Repository hinzu. Wie vorgeschlagen passt er nur auf diese Datei.';

  @override
  String get ignoreDialogFolderDescription =>
      'GitLama fügt diesen Eintrag der .gitignore-Datei oben im Repository hinzu. Wie vorgeschlagen passt er nur auf diesen Ordner.';

  @override
  String get ignoreDialogTrackedNote =>
      'Git verfolgt diese Datei bereits. Der Eintrag blendet sie erst aus, wenn sie aus dem Repository entfernt wurde.';

  @override
  String get ignoreDialogEntry => 'Eintrag';

  @override
  String get ignoreDialogEntryHint =>
      'Mit * passt der Eintrag auf beliebige Zeichen, zum Beispiel *.log.';

  @override
  String get ignoreDialogAdd => 'Hinzufügen';

  @override
  String get ignoreFailureInvalid =>
      'Git kann diesen Eintrag nicht verwenden. Gib ein Muster ein, das nicht mit # beginnt.';

  @override
  String get ignoreFailureWrite =>
      'GitLama konnte .gitignore nicht ändern. Die Datei ist vielleicht ein Link, zu groß oder schreibgeschützt.';

  @override
  String get commandSaveCommitArchive => 'Snapshot als ZIP speichern…';

  @override
  String get archiveProgressTitle => 'Snapshot wird gespeichert';

  @override
  String get archiveProgressPreparing => 'Commit wird gelesen…';

  @override
  String archiveProgressFiles(int files, int total) {
    return '$files von $total Dateien';
  }

  @override
  String get archiveProgressWriting => 'ZIP-Datei wird geschrieben…';

  @override
  String archiveSaved(String name) {
    return 'Snapshot als $name gespeichert.';
  }

  @override
  String archiveMissingSubmodules(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Submodule waren nicht verfügbar und sind leere Ordner.',
      one: '1 Submodul war nicht verfügbar und ist ein leerer Ordner.',
    );
    return '$_temp0';
  }

  @override
  String archiveUnresolvedLfs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Git-LFS-Dateien konnten nicht heruntergeladen werden und enthalten ihre Pointer.',
      one:
          '1 Git-LFS-Datei konnte nicht heruntergeladen werden und enthält ihren Pointer.',
    );
    return '$_temp0';
  }

  @override
  String get archiveFailureStale =>
      'Das Repository wurde geschlossen, bevor der Snapshot gespeichert war.';

  @override
  String get archiveFailureMissingCommit =>
      'Der Commit ist nicht mehr im Repository.';

  @override
  String get archiveFailureTooLarge =>
      'Der Commit hat zu viele Dateien für einen Snapshot.';

  @override
  String get archiveFailureBusy =>
      'Andere Snapshots dieses Repositorys werden noch gespeichert.';

  @override
  String get archiveFailureWrite =>
      'Die ZIP-Datei konnte nicht geschrieben werden.';

  @override
  String get archiveFailureGit =>
      'Git konnte die Dateien des Commits nicht lesen.';

  @override
  String get settingsDiffView => 'Diffs';

  @override
  String get settingsDiffViewDetail =>
      'Lege fest, wie alle Diffs angezeigt werden. Die Schaltflächen über einem Diff ändern diese Einstellungen ebenfalls.';

  @override
  String get settingsDiffLayout => 'Darstellung';

  @override
  String get settingsDiffUnified => 'Vereinheitlicht';

  @override
  String get settingsDiffSideBySide => 'Nebeneinander';

  @override
  String get settingsDiffWrap => 'Lange Zeilen';

  @override
  String get settingsDiffWrapOn => 'Umbrechen';

  @override
  String get settingsDiffWrapOff => 'Seitlich scrollen';

  @override
  String get settingsDiffWhitespace => 'Leerraum';

  @override
  String get settingsDiffWhitespacePreserve => 'Alle Änderungen zeigen';

  @override
  String get settingsDiffWhitespaceIgnoreAll => 'Leerraum ganz ignorieren';

  @override
  String get settingsDiffWhitespaceIgnoreAmount =>
      'Geänderte Mengen ignorieren';

  @override
  String get settingsDiffWhitespaceIgnoreEndOfLine =>
      'Am Zeilenende ignorieren';

  @override
  String get settingsDiffIndicators => 'Plus- und Minuszeichen';

  @override
  String get settingsDiffMinimap => 'Minimap';

  @override
  String hostingBranchChecks(String branch, String checks) {
    return '$branch: $checks';
  }

  @override
  String get hostingCheckPassing => 'Checks erfolgreich';

  @override
  String get hostingCheckFailing => 'Checks fehlgeschlagen';

  @override
  String get hostingCheckPending => 'Checks laufen';

  @override
  String get hostingCheckCanceled => 'Checks abgebrochen';

  @override
  String get hostingCheckSkipped => 'Checks übersprungen';

  @override
  String get hostingCheckUnknown => 'Checks unbekannt';

  @override
  String get hostingMergeable => 'Keine Merge-Konflikte';

  @override
  String get hostingMergeConflicting => 'Merge-Konflikte';

  @override
  String get hostingMergeChecking => 'Merge-Konflikte werden geprüft';

  @override
  String get hostingPullRequestOutdated =>
      'Der Pull Request steht auf dem Host nicht auf dem Stand dieses Branches. GitLama prüft gleich erneut; rufe ab, wenn sich der Branch auf dem Host geändert hat.';

  @override
  String get sidebarFilterShow => 'Branches filtern';

  @override
  String get sidebarFilterPlaceholder => 'Branches und Tags filtern';

  @override
  String get sidebarFilterClear => 'Filter löschen';

  @override
  String get sidebarFilterNoMatches => 'Keine passenden Branches oder Tags.';

  @override
  String get commandCheckoutCommit => 'Commit auschecken…';

  @override
  String refConfirmCheckoutCommit(String target) {
    return 'Commit $target mit losgelöstem HEAD auschecken? Kein Branch wird verschoben. Erstelle einen Branch, bevor du weiterwechselst, um neue Commits zu behalten.';
  }

  @override
  String get commitCheckoutDirtyHelp =>
      'Du hast nicht committete Änderungen. Wähle, wie sie vor dem Auschecken gespeichert werden. Ausblenden bricht das Auschecken ab.';

  @override
  String get commitCheckoutStashHelp =>
      'Stashen speichert alle versionierten und unversionierten Änderungen und behält sie nach dem Auschecken im Stash. Ignorierte Dateien bleiben im Arbeitsverzeichnis.';

  @override
  String get commitCheckoutReapplyHelp =>
      'Stashen & erneut anwenden stellt die Änderungen beim ausgewählten Commit wieder her. Bei Konflikten bleibt der Stash erhalten und Änderungen öffnet sich zur Auflösung.';

  @override
  String get commitCheckoutDismiss => 'Ausblenden';

  @override
  String get commitCheckoutStash => 'Stash';

  @override
  String get commitCheckoutStashAndReapply => 'Stashen & erneut anwenden';

  @override
  String get commitCheckoutAction => 'Commit auschecken';

  @override
  String get commitCheckoutBusy => 'Commit wird ausgecheckt…';

  @override
  String get hostingStepPublicClient =>
      'Deaktiviere für diese Anwendung „Vertraulicher Client“ (oder aktiviere „Öffentlicher Client“). GitLama verwendet PKCE ohne Client-Secret.';

  @override
  String get hostingOAuthClientRejected =>
      'Die OAuth-Anwendung wurde abgelehnt. Prüfe die Client-ID und die Weiterleitungs-URI. Deaktiviere in Forgejo oder Codeberg „Vertraulicher Client“ (oder aktiviere „Öffentlicher Client“), speichere und autorisiere erneut.';

  @override
  String discardMixedConfirmMessage(int tracked, int untracked) {
    String _temp0 = intl.Intl.pluralLogic(
      tracked,
      locale: localeName,
      other: '$tracked versionierte Dateien wiederherstellen',
      one: '1 versionierte Datei wiederherstellen',
    );
    String _temp1 = intl.Intl.pluralLogic(
      untracked,
      locale: localeName,
      other: '$untracked neue Dateien endgültig löschen',
      one: '1 neue Datei endgültig löschen',
    );
    return '$_temp0 und $_temp1? Diese nicht bereitgestellten Änderungen können nicht wiederhergestellt werden.';
  }

  @override
  String discardPartial(int completed, int total) {
    return 'Verwerfen wurde für $completed von $total Dateien abgeschlossen und dann angehalten. Prüfe die verbleibenden Änderungen vor einem erneuten Versuch; der letzte Schritt hat möglicherweise Dateien geändert.';
  }

  @override
  String get conflictResizeFiles =>
      'Konfliktdateiliste vergrößern oder verkleinern';

  @override
  String get conflictFilesTitle => 'Konfliktdateien';

  @override
  String get conflictComparisonTitle => 'Aktuell / Eingehend';

  @override
  String get conflictPresenceBothDeleted => 'Auf beiden Seiten gelöscht';

  @override
  String get conflictPresenceAddedCurrent =>
      'Nur auf der aktuellen Seite hinzugefügt';

  @override
  String get conflictPresenceDeletedIncoming =>
      'Auf der eingehenden Seite gelöscht; auf der aktuellen Seite vorhanden';

  @override
  String get conflictPresenceAddedIncoming =>
      'Nur auf der eingehenden Seite hinzugefügt';

  @override
  String get conflictPresenceDeletedCurrent =>
      'Auf der aktuellen Seite gelöscht; auf der eingehenden Seite vorhanden';

  @override
  String get conflictPresenceBothAdded =>
      'Auf beiden Seiten unabhängig hinzugefügt';

  @override
  String get conflictPresenceBothPresent => 'Auf beiden Seiten vorhanden';

  @override
  String get conflictPresenceUnknown =>
      'Nicht zusammengeführter Pfad; Indexdetails nicht verfügbar';

  @override
  String get conflictContentIdentical =>
      'Aktuelle und eingehende Datei sind bytegleich.';

  @override
  String get conflictContentLineEndings =>
      'Der Text unterscheidet sich nur in den Zeilenenden (LF, CRLF oder CR).';

  @override
  String get conflictContentFinalNewline =>
      'Der Text unterscheidet sich nur im abschließenden Zeilenumbruch.';

  @override
  String get conflictContentBom =>
      'Der Text unterscheidet sich nur in der UTF-8-Byte-Reihenfolge-Markierung (BOM).';

  @override
  String get conflictContentWhitespace =>
      'Der Text unterscheidet sich nur in Leerraum wie Leerzeichen, Tabulatoren oder Zeilenenden.';

  @override
  String get conflictContentDifferent =>
      'Aktuelle und eingehende Datei haben unterschiedlichen Inhalt.';

  @override
  String get conflictContentUnavailable =>
      'Mit dieser Vorschau lässt sich die Gleichheit des Inhalts nicht prüfen.';

  @override
  String get conflictContentMissingSide =>
      'Eine fehlende Datei ist nicht dasselbe wie eine leere Datei. Die Wahl der fehlenden Seite übernimmt die Löschung.';

  @override
  String get conflictModesDiffer =>
      'Dateitypen oder Ausführungsrechte unterscheiden sich. Siehe Eintragsdetails.';

  @override
  String get conflictNoMarkers =>
      'Keine Textmarkierungen. Prüfe das Ergebnis und löse den Dateikonflikt auf; Git führt ihn noch als offen.';

  @override
  String get conflictEntryDetailsTitle => 'Eintragsdetails';

  @override
  String get conflictCurrentEntry => 'Aktueller Eintrag';

  @override
  String get conflictIncomingEntry => 'Eingehender Eintrag';

  @override
  String get conflictWorkingEntry => 'Gespeicherter Arbeitskopie-Eintrag';

  @override
  String get conflictEntryAbsent => 'Nicht vorhanden';

  @override
  String get conflictEntryRegular => 'Reguläre Datei';

  @override
  String get conflictEntryExecutable => 'Ausführbare Datei';

  @override
  String get conflictEntrySymlink =>
      'Symbolischer Link (Inhalt ist das Linkziel)';

  @override
  String get conflictEntrySubmodule =>
      'Submodul (Inhalt bezeichnet einen Commit)';

  @override
  String get conflictEntryDirectory => 'Verzeichnis';

  @override
  String get conflictEntryUnknown => 'Unbekannter Eintragstyp';

  @override
  String conflictEntryFacts(String type, String mode, String bytes) {
    return '$type · Modus $mode · $bytes Bytes';
  }

  @override
  String get conflictPathFacts =>
      'Indexstufen beschreiben nur diesen Pfad. Umbenennungs- und Datei/Verzeichnis-Konflikte können weitere Pfade betreffen; prüfe alle zugehörigen Einträge. „Gespeicherter Arbeitskopie-Eintrag“ beschreibt die Datei auf dem Datenträger vor ungespeicherten Ergebnisänderungen.';

  @override
  String conflictFormatFacts(String endings, String finalNewline, String bom) {
    return '$endings · $finalNewline · $bom';
  }

  @override
  String get conflictNoLineBreaks => 'Keine Zeilenumbrüche';

  @override
  String get conflictMixedLineBreaks => 'Gemischte Zeilenenden';

  @override
  String get conflictFinalNewlinePresent => 'Abschließender Zeilenumbruch';

  @override
  String get conflictFinalNewlineAbsent => 'Kein abschließender Zeilenumbruch';

  @override
  String get conflictBomPresent => 'UTF-8-BOM';

  @override
  String get conflictBomAbsent => 'Kein UTF-8-BOM';

  @override
  String get conflictReviewFile => 'Noch aufzulösen';

  @override
  String get transferLocalChangesHelp =>
      'Du hast nicht committete Änderungen. Wähle, ob sie vor dem Pull gesichert werden oder Git den Pull mit ihnen versuchen soll.';

  @override
  String get transferStashBeforePull =>
      'Meine Änderungen stashen, pullen und wieder anwenden';

  @override
  String get transferStashBeforePullHelp =>
      'Gestagte, nicht gestagte und unversionierte Dateien sichern und nach dem Pull mit ihrem Staging wiederherstellen. Ignorierte Dateien und Änderungen in Submodulen werden nicht gestasht. Eine benannte Sicherung bleibt unter Stashes, bis du sie löschst.';

  @override
  String get transferStashPullAction => 'Stashen und pullen';

  @override
  String get transferPullStashRestored =>
      'Pull abgeschlossen. Deine Änderungen und ihr Staging wurden wiederhergestellt. Eine Sicherung bleibt unter Stashes.';

  @override
  String get transferPullStashConflict =>
      'Pull abgeschlossen, aber beim Wiederanwenden deiner Änderungen sind Konflikte entstanden. Löse sie unter Änderungen. Der Sicherungs-Stash bleibt erhalten.';

  @override
  String get transferPullStashSaved =>
      'Pull abgeschlossen. Deine Änderungen konnten nicht vollständig wiederhergestellt werden; sie bleiben unter Stashes gesichert. Prüfe Änderungen, bevor du den Sicherungs-Stash anwendest.';

  @override
  String transferPullFailedStashRestored(String reason) {
    return '$reason Deine Änderungen und ihr Staging wurden wiederhergestellt. Eine Sicherung bleibt unter Stashes.';
  }

  @override
  String get transferPullFailedStashSaved =>
      'Pull nicht abgeschlossen. Deine Änderungen sind unter Stashes gesichert. Schließe einen aktiven Git-Vorgang ab oder brich ihn ab und wende danach den Sicherungs-Stash an. Ein erneuter Pull stellt sie nicht wieder her.';

  @override
  String get transferPullRecoveryTitle => 'Deine Änderungen nach dem Pull';

  @override
  String get transferPullRecoveryHelp =>
      'Der Sicherungs-Stash heißt „GitLama before pull“, gefolgt von einer Kennung. Er enthält auch den gesicherten Index. Wende ihn nach erfolgreicher Wiederherstellung nicht erneut an. Lösche ihn erst, nachdem du deine Änderungen geprüft hast.';

  @override
  String worktreeTabsTooltip(String repository, int count) {
    return '$repository · $count Worktrees geöffnet';
  }

  @override
  String worktreeRowLabel(String repository) {
    return 'Geöffnete Worktrees von $repository';
  }

  @override
  String get worktreeOpen => 'Worktree öffnen';

  @override
  String get worktreeAllOpen => 'Alle Worktrees sind geöffnet';

  @override
  String get worktreeListFailed =>
      'Die Worktrees konnten nicht aufgelistet werden.';

  @override
  String worktreeCloseAll(int count) {
    return 'Alle $count Worktrees schließen';
  }

  @override
  String get worktreeMainTab => 'Haupt-Worktree';

  @override
  String get conflictKeepingDeletion => 'Löschung wird beibehalten';

  @override
  String get conflictUsingThisFile => 'Diese Datei wird verwendet';

  @override
  String get conflictChooseDifferently => 'Anders entscheiden';

  @override
  String get conflictDeletionDecisionTitle =>
      'Diese Datei wurde auf einer Seite gelöscht';

  @override
  String get conflictDeletionDecisionHint =>
      'Behalte die Löschung oder die Datei der Seite, die sie noch hat.';

  @override
  String conflictKeepFileFrom(String branch) {
    return 'Datei aus $branch behalten';
  }

  @override
  String get conflictDeletionChosenTitle =>
      'Beim Auflösen wird diese Datei gelöscht';

  @override
  String conflictDeletionChosenBody(String branch) {
    return 'Du hast die Löschung aus $branch gewählt. Beim Auflösen wird die Datei aus dem Arbeitsverzeichnis entfernt und die Löschung vorgemerkt.';
  }

  @override
  String conflictWholeFileChosenTitle(String branch) {
    return 'Die ganze Datei aus $branch wird verwendet';
  }

  @override
  String get conflictWholeFileChosenBody =>
      'Beim Auflösen wird diese Version gespeichert. Wenn du das Ergebnis bearbeitest oder Bereiche wählst, ersetzt das diese Wahl.';

  @override
  String get conflictDeletionResult => 'Die Datei wird gelöscht';

  @override
  String get conflictResolveByDeleting => 'Durch Löschen auflösen';

  @override
  String get conflictChooseVersion =>
      'Wähle, welche Version du behalten möchtest.';

  @override
  String get conflictResolvedHint =>
      'Prüfe, wie jede Datei aufgelöst wurde. Du kannst jede Auflösung rückgängig machen, bevor du fortsetzt.';

  @override
  String get conflictOutcomeDeleted => 'Gelöscht';

  @override
  String conflictOutcomeCurrent(String label) {
    return 'Aktuelle Version behalten ($label)';
  }

  @override
  String conflictOutcomeIncoming(String label) {
    return 'Eingehende Version übernommen ($label)';
  }

  @override
  String get conflictOutcomeMerged => 'Zusammengeführtes Ergebnis';

  @override
  String get conflictOutcomeExternal => 'Im externen Werkzeug zusammengeführt';

  @override
  String conflictResolvedNext(String resolved, String next) {
    return '$resolved aufgelöst. Jetzt: $next.';
  }

  @override
  String get conflictGuideTitle => 'Schritte der Konfliktlösung';

  @override
  String get conflictStepPick => 'Änderungen auswählen';

  @override
  String get conflictStepReview => 'Ergebnis prüfen';

  @override
  String get conflictStepResolve => 'Auflösen';

  @override
  String get conflictStepContinue => 'Fortsetzen';

  @override
  String get conflictStepDone => 'Fertig';

  @override
  String conflictGuidePick(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Wähle für jeden der $count Konflikte eine Seite oder bearbeite das Ergebnis.',
      one: 'Wähle eine Seite für den Konflikt oder bearbeite das Ergebnis.',
    );
    return '$_temp0';
  }

  @override
  String get conflictGuideDecideDeletion =>
      'Eine Seite hat diese Datei gelöscht. Behalte die Löschung oder die Datei.';

  @override
  String get conflictGuideReview =>
      'Prüfe das Ergebnis und löse die Datei dann auf.';

  @override
  String get conflictGuideReviewDeletion =>
      'Die Datei wird gelöscht. Löse sie auf, um das zu bestätigen.';

  @override
  String get conflictGuideContinue =>
      'Prüfe, wie jede Datei aufgelöst wurde, und setze dann fort.';

  @override
  String get conflictGuideDone => 'Alle Konflikte sind aufgelöst.';

  @override
  String conflictGuideResolvedCount(int resolved, int total) {
    return '$resolved von $total Dateien aufgelöst';
  }

  @override
  String get stagingPendingFile => 'Staging-Aktion ausstehend';

  @override
  String get stagingWaiting => 'Warten auf Repository…';

  @override
  String get stagingPreparing => 'Änderungen werden geprüft…';

  @override
  String get stagingUpdating => 'Index wird aktualisiert…';

  @override
  String get stagingRefreshing =>
      'Index aktualisiert. Änderungen werden neu geladen…';

  @override
  String get stagingClearQueue => 'Wartende Aktionen abbrechen';

  @override
  String stagingQueueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aktionen warten.',
      one: '1 Aktion wartet.',
      zero: 'Keine wartenden Aktionen.',
    );
    return '$_temp0';
  }

  @override
  String stagingQueueStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count wartende Aktionen wurden abgebrochen, weil das Staging nicht sicher abgeschlossen wurde. Prüfe die Änderungen vor einem erneuten Versuch.',
      one:
          '1 wartende Aktion wurde abgebrochen, weil das Staging nicht sicher abgeschlossen wurde. Prüfe die Änderungen vor einem erneuten Versuch.',
    );
    return '$_temp0';
  }

  @override
  String get refMutationStartingPoint => 'Ausgangspunkt';

  @override
  String get refMutationTargetUnavailableTitle =>
      'Ausgangscommit nicht verfügbar';

  @override
  String get refMutationTargetUnavailableDetail =>
      'Der ausgewählte Ausgangscommit oder sein Dateibaum ist in diesem Repository nicht verfügbar. Aktualisiere Referenzen und Verlauf und wähle den Ausgangspunkt erneut. Deine Eingaben bleiben erhalten. GitLama wiederholt den Vorgang nicht automatisch.';

  @override
  String get refMutationRefreshTarget => 'Aktualisieren und erneut wählen';

  @override
  String get settingsStatusAcceleration => 'Schnellere Änderungsprüfung';

  @override
  String get settingsStatusAccelerationHint =>
      'Gits Untracked-Cache und Dateisystem-Monitor prüfen große Repositorys deutlich schneller auf Änderungen. Das Einschalten ändert die Git-Einstellungen dieses Repositorys.';

  @override
  String get settingsUntrackedCache => 'Untracked-Cache';

  @override
  String get settingsFsmonitor => 'Dateisystem-Monitor';

  @override
  String get settingsFsmonitorUnavailable =>
      'Mit diesem Git auf diesem System nicht verfügbar';

  @override
  String get settingsStatusAccelerationEnable => 'Einschalten';

  @override
  String get settingsStatusAccelerationAllOn =>
      'Alles Verfügbare ist eingeschaltet.';

  @override
  String get settingsStatusAccelerationRemote =>
      'Nur für Repositorys auf diesem Computer verfügbar.';

  @override
  String get settingsStatusAccelerationReadFailed =>
      'GitLama konnte die Git-Einstellungen dieses Repositorys nicht lesen.';

  @override
  String get settingsStatusAccelerationLastScanFast =>
      'Die letzte Prüfung auf Änderungen dauerte weniger als eine Sekunde.';

  @override
  String settingsStatusAccelerationLastScan(int seconds) {
    return 'Die letzte Prüfung auf Änderungen dauerte etwa $seconds s.';
  }

  @override
  String get diagnosticsTitle => 'Diagnose';

  @override
  String get diagnosticsDescription =>
      'Letzte sichere Ereignisse bleiben nur im Arbeitsspeicher (bis zu 1.000 Ereignisse oder 256 KiB). Die detaillierte Aufzeichnung endet nach spätestens 15 Minuten oder mit der Sitzung. Zugangsdaten und private Inhalte sind ausgeschlossen. Prüfe die Vorschau vor dem Speichern oder Teilen. Es wird nichts automatisch hochgeladen. Verlauf löschen entfernt keine gespeicherten oder geteilten Kopien.';

  @override
  String get diagnosticsEnable =>
      'Detaillierte Diagnose für 15 Minuten aktivieren';

  @override
  String get diagnosticsDisable =>
      'Detaillierte Diagnose aktiv — Details beenden';

  @override
  String get diagnosticsClear => 'Verlauf löschen';

  @override
  String get diagnosticsPreview => 'Exportvorschau';

  @override
  String get diagnosticsCancel => 'Vorschau schließen';

  @override
  String get diagnosticsSave => 'In Datei speichern';

  @override
  String get diagnosticsShare => 'Teilen…';

  @override
  String get diagnosticsFailed =>
      'Diagnose konnte nicht exportiert werden. Versuche ein anderes Ziel.';

  @override
  String get diagnosticsSaved => 'Diagnose gespeichert.';
}
