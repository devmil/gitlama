import 'dart:async';

import '../models/advanced_rebase.dart';
import '../models/activity.dart';
import '../models/clone_attempt.dart';
import '../models/commit.dart';
import '../models/conflict.dart';
import '../models/discard.dart';
import '../models/diff.dart';
import '../models/diff_renderer.dart';
import '../models/index_lock.dart';
import '../models/history.dart';
import '../models/history_mutation.dart';
import '../models/integrations.dart';
import '../models/patch.dart';
import '../models/power_tools.dart';
import '../models/remote_workspace.dart';
import '../models/repository_appearance.dart';
import '../models/repository_state.dart';
import '../models/ref_mutation.dart';
import '../models/repository_extensions.dart';
import '../models/rebase.dart';
import '../models/named_snapshot.dart';
import '../models/settings.dart';
import '../models/stash.dart';
import '../models/workspace.dart';
import '../models/transfer.dart';
import '../repositories/directory_picker_repository.dart';
import '../repositories/repository_session_repository.dart';
import 'auto_fetch_scheduler.dart';
import 'clone_service.dart';
import 'diff_syntax_service.dart';
import 'source_syntax_service.dart';
import 'commit_composer.dart';
import 'history_service.dart';
import 'inspector/inspector_service.dart';
import 'preview_registry.dart';
import 'remote_reconnect.dart';
import 'repository_opener.dart';
import 'repository_view_cache_service.dart';
import 'session/activity_commands.dart';
import 'session/advanced_rebase_commands.dart';
import 'session/commit_archive_commands.dart';
import 'session/conflict_commands.dart';
import 'session/diff_renderer_commands.dart';
import 'session/extension_commands.dart';
import 'session/history_inspector_link.dart';
import 'session/history_mutation_commands.dart';
import 'session/integration_commands.dart';
import 'session/named_snapshot_commands.dart';
import 'session/patch_commands.dart';
import 'session/power_tools_commands.dart';
import 'session/rebase_commands.dart';
import 'session/ref_mutation_commands.dart';
import 'session/session_view_cache.dart';
import 'session/stash_commands.dart';
import 'session/transfer_commands.dart';
import 'session/workspace_persistence.dart';
import 'session/workspace_remotes.dart';
import 'session/workspace_service.dart';
import 'session/working_copy_commands.dart';
import 'settings_service.dart';
import 'working_tree_paths.dart';

export 'session/workspace_service.dart' show WorkspaceService;

/// The families of reads and commands one session backend serves, each its
/// own capability. A backend that lacks a family is given one that refuses
/// every call, so no command looks its family up at call time.
final class SessionBackends {
  const SessionBackends({
    required this.sessions,
    required this.patches,
    required this.archives,
    required this.transfers,
    required this.stashes,
    required this.historyMutations,
    required this.rebases,
    required this.conflicts,
    required this.advancedRebases,
    required this.namedSnapshots,
    required this.extensions,
    required this.integrations,
    required this.powerTools,
    required this.diffRenderers,
  });

  /// Every family of [backend].
  factory SessionBackends.complete(CompleteSessionBackend backend) =>
      SessionBackends(
        sessions: backend,
        patches: backend,
        archives: backend,
        transfers: backend,
        stashes: backend,
        historyMutations: backend,
        rebases: backend,
        conflicts: backend,
        advancedRebases: backend,
        namedSnapshots: backend,
        extensions: backend,
        integrations: backend,
        powerTools: backend,
        diffRenderers: backend,
      );

  /// The families [repository] implements, and refusing stand-ins for the
  /// others: narrow test doubles implement only what a test needs.
  factory SessionBackends.of(RepositorySessionRepository repository) {
    T family<T>(String name) => repository is T
        ? repository as T
        : _UnavailableFamily('${name}_repository_unavailable') as T;
    return SessionBackends(
      sessions: repository,
      patches: family<PatchRepositorySessionRepository>('patch'),
      archives: family<CommitArchiveRepositorySessionRepository>(
        'commit_archive',
      ),
      transfers: family<TransferRepositorySessionRepository>('transfer'),
      stashes: family<StashRepositorySessionRepository>('stash'),
      historyMutations: family<HistoryMutationRepositorySessionRepository>(
        'history_mutation',
      ),
      rebases: family<RebaseRepositorySessionRepository>('rebase'),
      conflicts: family<ConflictRepositorySessionRepository>('conflict'),
      advancedRebases: family<AdvancedRebaseRepositorySessionRepository>(
        'advanced_rebase',
      ),
      namedSnapshots: family<NamedSnapshotRepositorySessionRepository>(
        'named_snapshot',
      ),
      extensions: family<ExtensionRepositorySessionRepository>('extension'),
      integrations: family<IntegrationRepositorySessionRepository>(
        'integration',
      ),
      powerTools: family<PowerToolsRepositorySessionRepository>('power_tools'),
      diffRenderers: repository is DiffRendererRepositorySessionRepository
          ? repository as DiffRendererRepositorySessionRepository
          : const _NoDiffRenderers(),
    );
  }

  /// The lifecycle, history, inspection and the families every backend has.
  final RepositorySessionRepository sessions;
  final PatchRepositorySessionRepository patches;
  final CommitArchiveRepositorySessionRepository archives;
  final TransferRepositorySessionRepository transfers;
  final StashRepositorySessionRepository stashes;
  final HistoryMutationRepositorySessionRepository historyMutations;
  final RebaseRepositorySessionRepository rebases;
  final ConflictRepositorySessionRepository conflicts;
  final AdvancedRebaseRepositorySessionRepository advancedRebases;
  final NamedSnapshotRepositorySessionRepository namedSnapshots;
  final ExtensionRepositorySessionRepository extensions;
  final IntegrationRepositorySessionRepository integrations;
  final PowerToolsRepositorySessionRepository powerTools;
  final DiffRendererRepositorySessionRepository diffRenderers;
}

/// A family the backend does not serve: every call fails with [code].
final class _UnavailableFamily
    implements
        PatchRepositorySessionRepository,
        CommitArchiveRepositorySessionRepository,
        TransferRepositorySessionRepository,
        StashRepositorySessionRepository,
        HistoryMutationRepositorySessionRepository,
        RebaseRepositorySessionRepository,
        ConflictRepositorySessionRepository,
        AdvancedRebaseRepositorySessionRepository,
        NamedSnapshotRepositorySessionRepository,
        ExtensionRepositorySessionRepository,
        IntegrationRepositorySessionRepository,
        PowerToolsRepositorySessionRepository {
  const _UnavailableFamily(this.code);

  final String code;

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError(code);
}

/// A backend that runs no diff renderer refuses every definition.
final class _NoDiffRenderers
    implements DiffRendererRepositorySessionRepository {
  const _NoDiffRenderers();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw const DiffRendererException(
        DiffRendererFailureCode.invalidDefinition,
      );
}

/// The repository workspace of one window, composed of narrow services.
///
/// [workspaceService] owns the tabs, groups, navigation, the active session
/// and the session lifecycle; [history] and [inspector] the History graph
/// and its Detail inspector; each command family its own capability of the
/// backend ([transfers], [stashes], ...); [composer] the Composer's drafts
/// and commits. The members below forward to them for widgets that still
/// use one object; new code uses the family services directly.
final class RepositorySessionService implements RepositoryOpener {
  /// Composes the workspace over [repository]. The optional collaborators
  /// are absent in narrow tests: without [settings] nothing is persisted,
  /// without [picker] nothing can be chosen, without [clones] nothing can be
  /// cloned, without [viewCache] repositories load without a known view, and
  /// without [remote] there are no remote workspaces.
  factory RepositorySessionService(
    RepositorySessionRepository repository, [
    SettingsService? settings,
    DirectoryPickerRepository? picker,
    CloneService? clones,
    RepositoryViewCacheService? viewCache,
    WorkspaceRemotes? remote,
  ]) => RepositorySessionService.composed(
    SessionBackends.of(repository),
    settings: settings,
    picker: picker ?? const _NoDirectoryPicker(),
    clones: clones,
    viewCache: viewCache == null
        ? const NoSessionViewCache()
        : ServiceSessionViewCache(viewCache),
    remotes: remote ?? const NoWorkspaceRemotes(),
  );

  RepositorySessionService.composed(
    SessionBackends backends, {
    SettingsService? settings,
    required this._picker,
    this._clones,
    required this._viewCache,
    required WorkspaceRemotes remotes,
    WorkingTreePaths? workingTreePaths,
    this.diffSyntax,
    this.sourceSyntax,
  }) : _settings = settings,
       workingTreePaths = workingTreePaths ?? WorkingTreePaths.unchecked() {
    final sessions = backends.sessions;
    history = HistoryService(
      sessions,
      cachedFirstPage: (session) {
        final repository = workspaceService
            .tabForSession(session)
            ?.canonicalIdentity;
        return repository == null
            ? null
            : _viewCache.entry(repository)?.history;
      },
      onFirstPage: (session, page) {
        final tab = workspaceService.tabForSession(session);
        final repository = tab?.canonicalIdentity;
        // A branch revealed from the sidebar is gone on the next visit.
        if (tab == null ||
            repository == null ||
            page.branchFilter != tab.navigation.branchFilter) {
          return;
        }
        _viewCache.rememberHistory(repository, page);
      },
      branchFilterFor: (session) {
        final tab = workspaceService.tabForSession(session);
        return tab == null
            ? HistoryBranchFilter.none
            : workspaceService.shownBranchFilter(tab);
      },
      otherRefs: settings == null
          ? null
          : () => settings.current.appearance.historyOtherRefs,
    );
    inspector = InspectorService(
      sessions,
      syntax: diffSyntax,
      diffPreferences: settings == null
          ? null
          : () => settings.current.appearance.diffView,
    );
    _link = HistoryInspectorLink(history, inspector);
    workspaceService = WorkspaceService(
      sessions,
      history: history,
      persistence: settings == null
          ? const TransientWorkspacePersistence()
          : SettingsWorkspacePersistence(settings),
      viewCache: _viewCache,
      chooseRepository: () =>
          _picker.chooseDirectory(canCreateDirectories: false),
      remotes: remotes,
      onPublished: () => _autoFetch?.sync(),
      onSessionClosed: _forgetSession,
    );
    final scope = workspaceService;
    composer = CommitComposer(settings, sessions);
    activityCommands = ActivityCommands(sessions, scope);
    workingCopy = WorkingCopyCommands(
      sessions,
      scope,
      _previews,
      syntax: diffSyntax,
    );
    refs = RefMutationCommands(sessions, scope, _previews);
    patches = PatchCommands(backends.patches, scope, _previews);
    archives = CommitArchiveCommands(backends.archives, scope);
    transfers = TransferCommands(backends.transfers, scope, _previews);
    stashes = StashCommands(backends.stashes, scope, _previews);
    historyMutations = HistoryMutationCommands(
      backends.historyMutations,
      scope,
      _previews,
    );
    rebases = RebaseCommands(backends.rebases, scope, _previews);
    conflicts = ConflictCommands(backends.conflicts, scope);
    advancedRebases = AdvancedRebaseCommands(
      backends.advancedRebases,
      scope,
      _previews,
    );
    snapshots = NamedSnapshotCommands(
      backends.namedSnapshots,
      scope,
      _previews,
    );
    extensions = ExtensionCommands(backends.extensions, scope, scope);
    integrations = IntegrationCommands(backends.integrations, scope, _previews);
    powerTools = PowerToolsCommands(
      backends.powerTools,
      scope,
      _previews,
      otherRefs: settings == null
          ? null
          : () => settings.current.appearance.historyOtherRefs,
    );
    diffRenderers = DiffRendererCommands(backends.diffRenderers, scope);
    _autoFetch = switch (settings) {
      final settings? => AutoFetchScheduler(
        settings,
        candidates: () => [
          for (final open in workspaceService.openSessions)
            (
              session: open.session,
              canonical: open.canonical,
              hasRemotes: open.snapshot.refs.remotes.isNotEmpty,
            ),
        ],
        fetch: transfers.backgroundFetch,
      ),
      null => null,
    };
    _historyOtherRefs = settings?.current.appearance.historyOtherRefs ?? false;
    _settingsChanges = settings?.changes.listen(_followHistoryOtherRefs);
  }

  final SettingsService? _settings;

  /// The history reference scope last seen in the settings; a change
  /// reloads the shown history.
  bool _historyOtherRefs = false;
  StreamSubscription<SettingsDocument>? _settingsChanges;

  void _followHistoryOtherRefs(SettingsDocument document) {
    final otherRefs = document.appearance.historyOtherRefs;
    if (otherRefs == _historyOtherRefs) return;
    _historyOtherRefs = otherRefs;
    if (!workspaceService.disposed) workspaceService.reloadShownHistory();
  }

  /// Syntax colours of this window's diffs; null shows plain text.
  final DiffSyntaxService? diffSyntax;

  /// Syntax colours of texts this window holds, such as conflicted files;
  /// null shows plain text.
  final SourceSyntaxService? sourceSyntax;
  final DirectoryPickerRepository _picker;

  /// Clone attempts; absent where cloning is unavailable.
  final CloneService? _clones;
  final SessionViewCache _viewCache;

  /// Background fetching of open local repositories; absent without
  /// settings.
  AutoFetchScheduler? _autoFetch;
  late final HistoryInspectorLink _link;

  /// Every preview token the command families issued, so a closed session
  /// or workspace forgets all of them.
  final PreviewRegistry _previews = PreviewRegistry();

  /// Whether paths of a commit exist in the working tree, for file menus.
  final WorkingTreePaths workingTreePaths;

  /// Tabs, groups, navigation, the active session and the session lifecycle.
  late final WorkspaceService workspaceService;

  /// The History graph of the active repository.
  late final HistoryService history;

  /// The History Detail inspector of the active repository. It shares the
  /// tab's native session with [history] and follows its selection.
  late final InspectorService inspector;

  /// Drafts, commit previews and commit flashes of the Composer.
  late final CommitComposer composer;
  late final ActivityCommands activityCommands;
  late final WorkingCopyCommands workingCopy;
  late final RefMutationCommands refs;
  late final PatchCommands patches;
  late final TransferCommands transfers;
  late final StashCommands stashes;
  late final HistoryMutationCommands historyMutations;
  late final RebaseCommands rebases;
  late final ConflictCommands conflicts;
  late final AdvancedRebaseCommands advancedRebases;
  late final NamedSnapshotCommands snapshots;
  late final ExtensionCommands extensions;

  /// Zip snapshots of commits.
  late final CommitArchiveCommands archives;
  late final IntegrationCommands integrations;
  late final PowerToolsCommands powerTools;
  late final DiffRendererCommands diffRenderers;

  void _forgetSession(RepositorySessionIdentity session) {
    _previews.forgetSession(session);
    composer.forgetSession(session);
    conflicts.forgetSession(session);
  }

  // Workspace

  Stream<RepositorySessionState> get states => workspaceService.states;
  Stream<CloneAttemptSnapshot> get cloneStates =>
      _clones?.states ?? const Stream.empty();
  Stream<WorkspaceState> get workspaceStates =>
      workspaceService.workspaceStates;
  @override
  RepositorySessionState? get current => workspaceService.current;
  CloneAttemptSnapshot? get currentClone => _clones?.current;
  WorkspaceState get workspace => workspaceService.workspace;

  /// The active tab's ID, without building a [workspace] value.
  int? get activeTabId => workspaceService.activeTabId;

  /// The active tab, without building a [workspace] value.
  RepositoryTabState? get activeTab => workspaceService.activeTab;

  /// Increments with each Composer commit in the active worktree.
  int get commitSequence =>
      composer.commitSequence(workspaceService.activeCanonical);

  /// The commit the last Composer commit in the active worktree made.
  String? get lastCommittedObjectId =>
      composer.lastCommittedObjectId(workspaceService.activeCanonical);

  /// Whether the last Composer commit in the active worktree amended HEAD.
  bool get lastCommitWasAmend =>
      composer.lastCommitWasAmend(workspaceService.activeCanonical);

  Future<void> restoreWorkspace() => workspaceService.restoreWorkspace();

  /// Reconnects hosts whose open tabs lost their connection, and connects
  /// the hosts of restored tabs.
  RemoteReconnector get remoteReconnect => workspaceService.remoteReconnect;

  int addRepositoryChooser() => workspaceService.addRepositoryChooser();

  Future<RepositorySessionState?> openFromChooser(
    int tabId, {
    NativePathIdentity? recent,
  }) => workspaceService.openFromChooser(tabId, recent: recent);

  @override
  Future<RepositorySessionState> open(String path) =>
      workspaceService.open(path);

  @override
  Future<RepositorySessionState> openRecent(NativePathIdentity identity) =>
      workspaceService.openRecent(identity);

  /// Opens the repository at the remote [path] of a connected host.
  Future<RepositorySessionState> openRemoteRepository(
    RemoteAuthority authority,
    List<int> path,
  ) => openRecent(remotePathIdentity(authority, path));

  /// The identity of the remote [path] of a connected host.
  static NativePathIdentity remotePathIdentity(
    RemoteAuthority authority,
    List<int> path,
  ) => WorkspaceService.remotePathIdentity(authority, path);

  /// Whether a remote tab shows state its connection no longer backs.
  bool isRemoteTabStale(RepositoryTabState tab) =>
      workspaceService.isRemoteTabStale(tab);

  /// Applies a changed "Allow changes" choice to a live connection of
  /// [profileId]; see [WorkspaceService.applyRemoteAccess].
  Future<RemoteConnectionState?> applyRemoteAccess(String profileId) =>
      workspaceService.applyRemoteAccess(profileId);

  /// Trusts the repository now found at a remote tab's path and reopens it;
  /// see [WorkspaceService.reopenChangedRemoteTab].
  Future<RepositorySessionState?> reopenChangedRemoteTab(int tabId) =>
      workspaceService.reopenChangedRemoteTab(tabId);

  /// Connects [profileId] and reopens its tabs on the new connection.
  Future<RemoteConnectionState?> reconnectRemote(String profileId) =>
      workspaceService.reconnectRemote(profileId);

  Future<RepositorySessionState?> chooseAndOpen() async {
    final path = await _picker.chooseDirectory(canCreateDirectories: false);
    return path == null ? null : open(path);
  }

  Future<RepositorySessionState?> chooseAndInitialize({
    bool bare = false,
  }) async {
    final path = await _picker.chooseDirectory(canCreateDirectories: true);
    return path == null ? null : initialize(path, bare: bare);
  }

  Future<RepositorySessionState?> chooseAndClone({
    required String source,
  }) async {
    final path = await _picker.chooseDirectory(canCreateDirectories: true);
    return path == null ? null : clone(source: source, destination: path);
  }

  Future<RepositorySessionState> initialize(
    String path, {
    String initialBranch = 'main',
    bool bare = false,
  }) => workspaceService.initialize(
    path,
    initialBranch: initialBranch,
    bare: bare,
  );

  /// Creates a repository at [path] on [authority]'s connected host, a
  /// missing folder or an empty one, and opens it in a new tab. The host's
  /// reasons for creating nothing arrive as [RepositorySessionException]
  /// with the failure codes of [initialize]; a connection that cannot make
  /// the call throws [RemoteWorkspaceException], with
  /// [RemoteFailureCode.writeNotPermitted] when changes are not allowed.
  Future<RepositorySessionState> initializeRemote(
    RemoteAuthority authority,
    List<int> path, {
    String initialBranch = 'main',
    bool bare = false,
  }) => workspaceService.initializeRemote(
    authority,
    path,
    initialBranch: initialBranch,
    bare: bare,
  );

  // Clones

  Future<RepositorySessionState?> clone({
    required String source,
    required String destination,
    String? initialBranch,
  }) async {
    workspaceService.ensureActive();
    return _adoptClone(
      await _requireClones().clone(
        source: source,
        destination: destination,
        initialBranch: initialBranch,
        generation: workspaceService.nextGeneration(),
      ),
    );
  }

  Future<RepositorySessionState?> retryClone({String? destination}) async {
    workspaceService.ensureActive();
    return _adoptClone(await _requireClones().retry(destination: destination));
  }

  Future<RepositorySessionState?> retryCloneWithCredentials({
    String? username,
    String? password,
    String? token,
    String? destination,
  }) async {
    workspaceService.ensureActive();
    return _adoptClone(
      await _requireClones().retryWithCredentials(
        username: username,
        password: password,
        token: token,
        destination: destination,
      ),
    );
  }

  Future<RepositorySessionState?> chooseAndRetryCloneWithCredentials({
    String? username,
    String? password,
    String? token,
  }) async {
    final current = currentClone;
    if (current == null) {
      throw const CloneException(
        CloneFailure(CloneFailureCode.invalidAttemptState),
      );
    }
    String? destination;
    if (current.partialDestination) {
      destination = await _picker.chooseDirectory(canCreateDirectories: true);
      if (destination == null) return null;
    }
    return retryCloneWithCredentials(
      username: username,
      password: password,
      token: token,
      destination: destination,
    );
  }

  Future<HostKeyChallenge> probeCloneHostKey() {
    workspaceService.ensureActive();
    return _requireClones().probeHostKey();
  }

  Future<RepositorySessionState?> resolveCloneHostKey({
    required HostKeyChallenge challenge,
    required bool accept,
  }) async {
    workspaceService.ensureActive();
    final current = currentClone;
    String? destination;
    if (accept &&
        current != null &&
        current.hostKeyChallenge?.challengeId == challenge.challengeId &&
        current.partialDestination) {
      destination = await _picker.chooseDirectory(canCreateDirectories: true);
      if (destination == null) return null;
    }
    final outcome = await _requireClones().resolveHostKey(
      challenge: challenge,
      accept: accept,
      destination: destination,
    );
    return outcome == null ? null : _adoptClone(outcome);
  }

  /// Opens the tab of a finished clone, or closes a session the user no
  /// longer waits for.
  Future<RepositorySessionState?> _adoptClone(CloneOutcome outcome) async {
    final opened = outcome.opened;
    if (opened == null) return null;
    return workspaceService.adoptOpened(opened, current: outcome.current);
  }

  Future<void> cancelClone() async {
    workspaceService.ensureActive();
    await _requireClones().cancel();
  }

  Future<void> dismissClone() async {
    workspaceService.ensureActive();
    await _requireClones().dismiss();
  }

  CloneService _requireClones() =>
      _clones ?? (throw StateError('clone_service_unavailable'));

  // Tabs, groups and navigation

  void activateTab(int tabId) => workspaceService.activateTab(tabId);

  void reorderTab(int tabId, int targetIndex) =>
      workspaceService.reorderTab(tabId, targetIndex);

  /// Puts [tabId] at [targetIndex] in [groupId], or in no group.
  void moveTab(int tabId, int targetIndex, {int? groupId}) =>
      workspaceService.moveTab(tabId, targetIndex, groupId: groupId);

  /// Puts [tabId] at [targetIndex] among the other open worktrees of its
  /// repository.
  void moveWorktreeTab(int tabId, int targetIndex) =>
      workspaceService.moveWorktreeTab(tabId, targetIndex);

  /// Moves every tab of [groupId] so the group starts at [targetIndex].
  void moveTabGroup(int groupId, int targetIndex) =>
      workspaceService.moveTabGroup(groupId, targetIndex);

  /// Gives [groupId] its [name], [color] and [icon] at once; an icon that
  /// is not one of [repositoryAppearanceIcons] clears it.
  void editTabGroup(
    int groupId, {
    required String name,
    required AppearanceColor color,
    String? icon,
  }) => workspaceService.editTabGroup(
    groupId,
    name: name,
    color: color,
    icon: icon,
  );

  /// Puts [tabId] in a new group and returns the group's id.
  int? createTabGroup(int tabId) => workspaceService.createTabGroup(tabId);

  /// Moves [tabId] to the end of [groupId].
  void addTabToGroup(int tabId, int groupId) =>
      workspaceService.addTabToGroup(tabId, groupId);

  /// Takes [tabId] out of its group; it stands right after the group.
  void removeTabFromGroup(int tabId) =>
      workspaceService.removeTabFromGroup(tabId);

  void renameTabGroup(int groupId, String name) =>
      workspaceService.renameTabGroup(groupId, name);

  /// Collapses or expands [groupId].
  void setTabGroupCollapsed(int groupId, bool collapsed) =>
      workspaceService.setTabGroupCollapsed(groupId, collapsed);

  /// Dissolves [groupId]; its tabs stay open where they are.
  void ungroupTabs(int groupId) => workspaceService.ungroupTabs(groupId);

  /// Closes every tab of [groupId].
  Future<void> closeTabGroup(int groupId) =>
      workspaceService.closeTabGroup(groupId);

  Future<void> closeTab(int tabId) => workspaceService.closeTab(tabId);

  /// Closes [tabIds] one after another.
  Future<void> closeTabs(List<int> tabIds) =>
      workspaceService.closeTabs(tabIds);

  void updateNavigation(int tabId, WorkspaceNavigation navigation) =>
      workspaceService.updateNavigation(tabId, navigation);

  /// Loads the history of tab [tabId] and selects a commit in it.
  Future<void> showHistory(int tabId) => workspaceService.showHistory(tabId);

  /// Filters the history graph of tab [tabId] to [filter]'s branches.
  Future<void> setBranchFilter(int tabId, HistoryBranchFilter filter) =>
      workspaceService.setBranchFilter(tabId, filter);

  /// Shows [reference] in the graph of tab [tabId] until another reference
  /// or null replaces it.
  Future<void> revealReference(int tabId, String? reference) =>
      workspaceService.revealReference(tabId, reference);

  /// Rescans the active repository for changes made outside the application;
  /// see [WorkspaceService.refresh].
  @override
  Future<void> refresh() => workspaceService.refresh();

  Future<void> refreshAndWait(RepositorySessionIdentity identity) =>
      workspaceService.refreshAndWait(identity);

  // Activity and undo

  Future<ActivityPage> activity({int maximumRecords = 20}) =>
      activityCommands.activity(maximumRecords: maximumRecords);

  Future<ActivityPage> activityFor(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) => activityCommands.activityFor(identity, maximumRecords: maximumRecords);

  Future<ActivityPage> activityRecordFor(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) => activityCommands.activityRecordFor(identity, activityId);

  // References

  Future<RefMutationPreview> previewRefMutation(RefMutationRequest request) =>
      refs.preview(request);

  Future<RefMutationExecutionResult> executeRefMutation(BigInt token) =>
      refs.execute(token);

  // Transfers

  Future<TransferPreview> previewTransfer(TransferRequest request) =>
      transfers.preview(request);

  Future<TransferExecutionResult> executeTransfer(
    TransferPreview preview, {
    TransferCredentials? credentials,
  }) => transfers.execute(preview, credentials: credentials);

  Future<bool> cancelTransfer(TransferPreview preview) =>
      transfers.cancel(preview);

  Future<HostKeyChallenge> probeTransferHostKey(TransferPreview preview) =>
      transfers.probeHostKey(preview);

  Future<void> resolveTransferHostKey(
    TransferPreview preview,
    HostKeyChallenge challenge, {
    required bool accept,
  }) => transfers.resolveHostKey(preview, challenge, accept: accept);

  // Stashes

  Future<StashPreview> previewStash(StashRequest request) =>
      stashes.preview(request);

  Future<StashExecutionResult> executeStash(StashPreview preview) =>
      stashes.execute(preview);

  Future<bool> cancelStash(StashPreview preview) => stashes.cancel(preview);

  // History mutations

  Future<HistoryMutationPreview> previewHistoryMutation(
    HistoryMutationRequest request,
  ) => historyMutations.preview(request);

  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    HistoryMutationPreview preview,
  ) => historyMutations.execute(preview);

  Future<bool> cancelHistoryMutation(HistoryMutationPreview preview) =>
      historyMutations.cancel(preview);

  Future<ConflictPredictionTask> beginConflictPrediction(
    ConflictPredictionKind kind,
    String target,
  ) => historyMutations.beginConflictPrediction(kind, target);

  Future<ConflictPredictionResult> executeConflictPrediction(
    ConflictPredictionTask task,
  ) => historyMutations.executeConflictPrediction(task);

  Future<bool> cancelConflictPrediction(ConflictPredictionTask task) =>
      historyMutations.cancelConflictPrediction(task);

  // Rebase and restack

  Future<RebasePlan> loadRebasePlan(String onto, List<int>? ontoName) =>
      rebases.loadPlan(onto, ontoName);

  Future<RebasePreview> previewRebase(
    RebasePlan plan,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) => rebases.preview(
    plan,
    instructions,
    acknowledgePublishedHistory,
    applyAutosquash,
  );

  Future<RebaseExecutionResult> executeRebase(RebasePreview preview) =>
      rebases.execute(preview);

  Future<bool> cancelRebase(BigInt token) => rebases.cancel(token);

  Future<FixupSuggestion> suggestFixupBase({
    String? selectedCommit,
    List<List<int>> paths = const [],
  }) => advancedRebases.suggestFixupBase(
    selectedCommit: selectedCommit,
    paths: paths,
  );

  Future<RestackPlan> planRestack(List<int> rootBranch) =>
      advancedRebases.planRestack(rootBranch);

  Future<RestackExecutionResult> executeRestack(
    RestackPlan plan, {
    required bool acknowledgePublishedHistory,
  }) => advancedRebases.executeRestack(
    plan,
    acknowledgePublishedHistory: acknowledgePublishedHistory,
  );

  Future<bool> cancelRestack(RestackPlan plan) =>
      advancedRebases.cancelRestack(plan);

  // Named snapshots

  Future<NamedSnapshotPage> namedSnapshots({
    int offset = 0,
    int maximum = 32,
  }) => snapshots.page(offset: offset, maximum: maximum);

  Future<NamedSnapshotExecutionResult> createNamedSnapshot({
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) => snapshots.create(
    name: name,
    includeUntracked: includeUntracked,
    keepIndex: keepIndex,
  );

  Future<NamedSnapshotRestorePreview> previewNamedSnapshotRestore(
    BigInt snapshotId,
  ) => snapshots.previewRestore(snapshotId);

  Future<NamedSnapshotExecutionResult> executeNamedSnapshotRestore(
    NamedSnapshotRestorePreview preview,
  ) => snapshots.executeRestore(preview);

  Future<bool> cancelNamedSnapshotRestore(
    NamedSnapshotRestorePreview preview,
  ) => snapshots.cancelRestore(preview);

  Future<NamedSnapshotExecutionResult> branchFromNamedSnapshot(
    NamedSnapshot snapshot,
    String branch,
  ) => snapshots.branchFrom(snapshot, branch);

  Future<NamedSnapshotExecutionResult> deleteNamedSnapshot(
    NamedSnapshot snapshot,
  ) => snapshots.delete(snapshot);

  // Worktrees, submodules and LFS

  Future<RepositoryExtensionInventory> repositoryExtensions() =>
      extensions.inventory();

  Future<String?> chooseWorktreeDestination() async {
    workspaceService.ensureActive();
    try {
      final path = await _picker.chooseDirectory(canCreateDirectories: true);
      return workspaceService.disposed ? null : path;
    } on Object {
      throw const RepositoryExtensionException(
        RepositoryExtensionFailureCode.unavailable,
      );
    }
  }

  Future<RepositorySessionState> enterSubmodule(SubmoduleEntry submodule) =>
      extensions.enterSubmodule(submodule);

  Future<RepositorySessionState> openWorktree(WorktreeEntry worktree) =>
      extensions.openWorktree(worktree);

  Future<LfsPointer?> inspectLfsPointer(LfsEntry entry) =>
      extensions.inspectLfsPointer(entry);

  Future<RepositoryExtensionMutationResult> executeRepositoryExtension(
    RepositoryExtensionMutationRequest request,
  ) => extensions.execute(request);

  // Integrations

  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) => integrations.discover(kind);

  List<IntegrationDefinition> configuredIntegrations(IntegrationKind kind) =>
      List.unmodifiable(
        _settings?.current.integrations.where((value) => value.kind == kind) ??
            const <IntegrationDefinition>[],
      );

  Future<DiffRendererPreview> validateDiffRenderer(
    DiffRendererDefinition definition,
  ) => diffRenderers.validate(definition);

  Future<IntegrationPreview> previewIntegration(IntegrationRequest request) =>
      integrations.preview(request);

  Future<IntegrationPreview> previewExternalConflictMerge(
    ConflictFile file,
    IntegrationDefinition definition,
  ) => integrations.previewExternalConflictMerge(file, definition);

  Future<IntegrationPreview> previewExternalCommitDiff({
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  }) => integrations.previewExternalCommitDiff(
    oldRevision: oldRevision,
    newRevision: newRevision,
    oldPath: oldPath,
    newPath: newPath,
    definition: definition,
  );

  Future<IntegrationExecutionResult> executeIntegration(
    IntegrationPreview preview, {
    required bool confirmed,
  }) => integrations.execute(preview, confirmed: confirmed);

  Future<bool> cancelIntegration(IntegrationPreview preview) =>
      integrations.cancel(preview);

  // Power tools

  Future<BigInt> startDiffContentSearch({
    required String query,
    int maximumCommits = 10000,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
  }) => powerTools.startDiffContentSearch(
    query: query,
    maximumCommits: maximumCommits,
    caseSensitive: caseSensitive,
    scope: scope,
  );

  Future<DiffContentSearchResult> pollDiffContentSearch(BigInt token) =>
      powerTools.pollDiffContentSearch(token);

  Future<BigInt> startRepositoryStatistics() =>
      powerTools.startRepositoryStatistics();

  Future<RepositoryStatisticsResult> pollRepositoryStatistics(BigInt token) =>
      powerTools.pollRepositoryStatistics(token);

  Future<bool> cancelPowerJob(BigInt token) => powerTools.cancelJob(token);

  Future<BisectState> bisectState() => powerTools.bisectState();

  Future<BisectPreview> previewBisect(
    BisectAction action, {
    String? good,
    String? bad,
  }) => powerTools.previewBisect(action, good: good, bad: bad);

  Future<BisectExecutionResult> executeBisect(BisectPreview preview) =>
      powerTools.executeBisect(preview);

  Future<bool> cancelBisectPreview(BisectPreview preview) =>
      powerTools.cancelBisectPreview(preview);

  // Conflicts

  Future<ConflictSnapshot> loadConflicts() => conflicts.load();

  Future<ConflictSnapshot> saveConflictResult(
    ConflictFile file,
    List<int> result,
  ) => conflicts.saveResult(file, result);

  Future<ConflictSnapshot> chooseConflictSide(
    ConflictFile file,
    ConflictSideChoice choice,
  ) => conflicts.chooseSide(file, choice);

  Future<ConflictSnapshot> takeConflictRegion(
    ConflictFile file,
    int regionIndex,
    ConflictRegionChoice choice,
  ) => conflicts.takeRegion(file, regionIndex, choice);

  Future<ConflictSnapshot> undoConflictResolution(List<int> path) =>
      conflicts.undoResolution(path);

  Future<ConflictContinuationResult> continueConflictOperation(
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) => conflicts.continueOperation(action, mergeMessage: mergeMessage);

  // Working copy

  Future<DiffPage> workingDiff({
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = ContractLimits.pageRows,
  }) => workingCopy.diff(
    side: side,
    oldPath: oldPath,
    newPath: newPath,
    contextLines: contextLines,
    whitespace: whitespace,
    layout: layout,
    forceText: forceText,
    maximumRows: maximumRows,
  );

  Future<ImageDiffContent> workingImageDiff({
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
  }) => workingCopy.imageDiff(side: side, oldPath: oldPath, newPath: newPath);

  Future<DiffPage> workingDiffPage({
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => workingCopy.diffPage(
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  Future<DiffSearchResult> searchWorkingDiff({
    required BigInt requestId,
    required String query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) => workingCopy.search(
    requestId: requestId,
    query: query,
    caseSensitive: caseSensitive,
    maximumMatches: maximumMatches,
  );

  /// A unified patch of the selected working-diff rows; see
  /// [WorkingCopyRepository.diffSelectionPatch].
  Future<List<int>?> workingDiffSelectionPatch({
    required BigInt requestId,
    required List<String> rowIds,
  }) => workingCopy.selectionPatch(requestId: requestId, rowIds: rowIds);

  Future<StagingExecutionResult> executeStaging(StagingRequest request) =>
      workingCopy.stage(request);

  Future<DiscardPreview> previewDiscard(DiscardRequest request) =>
      workingCopy.previewDiscard(request);

  Future<DiscardExecutionResult> executeDiscard(DiscardPreview preview) =>
      workingCopy.executeDiscard(preview);

  Future<({RepositorySessionIdentity identity, IndexLockInspection inspection})>
  inspectIndexLock() => workingCopy.inspectIndexLock();

  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => workingCopy.removeIndexLock(identity, token);

  // Patches

  /// Asks where to save a commit's zip snapshot, suggesting [suggestedName];
  /// null when the person cancels.
  Future<String?> chooseArchiveDestination(String suggestedName) =>
      _picker.chooseSaveFile(suggestedName: suggestedName, extension: 'zip');

  Future<String?> choosePatchDestination() =>
      _picker.chooseDirectory(canCreateDirectories: true);

  Future<String?> choosePatchFile() => _picker.choosePatchFile();

  Future<PatchExportPreview> previewPatchExport(PatchExportRequest request) =>
      patches.previewExport(request);

  Future<PatchExportExecutionResult> executePatchExport(
    PatchExportPreview preview,
  ) => patches.executeExport(preview);

  Future<PatchApplyPreview> previewPatchApply(String patchPath) =>
      patches.previewApply(patchPath);

  Future<PatchApplyExecutionResult> executePatchApply(
    PatchApplyPreview preview,
  ) => patches.executeApply(preview);

  // Composer

  CommitDraft get activeCommitDraft =>
      composer.draft(workspaceService.activeCanonical);

  void updateCommitDraft(CommitDraft draft) {
    workspaceService.ensureActive();
    final identity = workspaceService.activeCanonical;
    if (identity == null) return;
    composer.updateDraft(identity, draft);
  }

  Future<CommitTools> loadCommitTools() =>
      composer.tools(workspaceService.requireCurrent());

  Future<CommitPreview> previewCommit(CommitRequest request) async {
    final session = workspaceService.requireCurrent();
    final canonical = workspaceService.activeCanonical;
    if (canonical == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    return composer.previewCommit(session, canonical, request);
  }

  Future<CommitExecutionResult> executeCommit(
    CommitPreview preview,
    CommitDraft submittedDraft,
  ) {
    workspaceService.ensureActive();
    return composer.executeCommit(preview, submittedDraft);
  }

  // Background fetching

  /// Fetches the remote of every open repository that wants it, one after
  /// another. A fetch never prompts: one that needs a sign-in or an unknown
  /// host fails and is listed as background work, like one made offline.
  Future<void> autoFetch() async => _autoFetch?.run();

  // Lifecycle

  /// Closes every tab, its session and every preview, and the running clone.
  Future<void> close() async {
    await _clones?.close();
    _autoFetch?.stop();
    await workspaceService.close(
      beforeSessionsClose: () {
        // Every family, not only some: a token of a closed session admits
        // nothing.
        _previews.clear();
        composer.clear();
      },
    );
  }

  Future<void> dispose() async {
    if (workspaceService.disposed) return;
    workspaceService.retire();
    // Not awaited: a broadcast subscription's cancel future belongs to the
    // root zone, and nothing is pending behind it.
    unawaited(_autoFetch?.dispose());
    unawaited(_settingsChanges?.cancel());
    _link.dispose();
    await close();
    await inspector.dispose();
    await history.dispose();
    await workspaceService.dispose();
  }
}

/// A window that cannot choose folders.
final class _NoDirectoryPicker implements DirectoryPickerRepository {
  const _NoDirectoryPicker();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('directory_picker_unavailable');
}
