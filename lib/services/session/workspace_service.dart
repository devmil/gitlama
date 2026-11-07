import 'dart:async';

import '../../models/clone_attempt.dart';
import '../../models/history.dart';
import '../../models/remote_workspace.dart';
import '../../models/repository_appearance.dart';
import '../../models/repository_state.dart';
import '../../models/settings.dart';
import '../../models/workspace.dart';
import '../../repositories/session_lifecycle_repository.dart';
import '../history_service.dart';
import '../remote_reconnect.dart';
import '../repository_opener.dart';
import 'extension_commands.dart';
import 'followed_heads.dart';
import 'session_event_drain.dart';
import 'session_scope.dart';
import 'session_view_cache.dart';
import 'workspace_persistence.dart';
import 'workspace_remotes.dart';

/// The repository tabs of one window: their order and groups, each tab's
/// navigation, the active tab and its session, and the sessions' events.
///
/// It is the one owner of the session lifecycle: it opens, reopens and
/// closes sessions and drains their events. Command families reach the
/// sessions through it as a [SessionScope].
final class WorkspaceService
    implements SessionScope, ExtensionTabs, RepositoryOpener {
  WorkspaceService(
    this._sessions, {
    required this.history,
    required this._persistence,
    required this._viewCache,
    required this._chooseRepository,
    required this._remotes,
    void Function()? onPublished,
    void Function(RepositorySessionIdentity session)? onSessionClosed,
    Duration drainInterval = const Duration(milliseconds: 20),
  }) : _onPublished = onPublished ?? _nothing,
       _onSessionClosed = onSessionClosed ?? _ignoreSession {
    _drain = SessionEventDrain(
      sessions: () => [
        for (final tab in _tabs)
          if (tab.session case final session?)
            (session: session.identity, active: tab.id == _activeTabId),
      ],
      drain: _drainEvents,
      interval: drainInterval,
    );
  }

  static void _nothing() {}
  static void _ignoreSession(RepositorySessionIdentity _) {}

  final SessionLifecycleRepository _sessions;

  /// The history graph of the active tab.
  final HistoryService history;
  final WorkspacePersistence _persistence;
  final SessionViewCache _viewCache;

  /// Asks for the folder of a repository to open; null when canceled.
  final Future<String?> Function() _chooseRepository;
  final WorkspaceRemotes _remotes;

  /// Runs after every published workspace change while the workspace lives.
  final void Function() _onPublished;

  /// Runs when a tab's session closes, so its previews are forgotten.
  final void Function(RepositorySessionIdentity session) _onSessionClosed;
  late final SessionEventDrain _drain;
  final FollowedHeads _heads = FollowedHeads();
  StreamSubscription<RemoteConnectionState>? _remoteStates;

  final StreamController<RepositorySessionState> _states =
      StreamController<RepositorySessionState>.broadcast(sync: true);
  final StreamController<WorkspaceState> _workspaceStates =
      StreamController<WorkspaceState>.broadcast(sync: true);
  final List<RepositoryTabState> _tabs = [];
  final List<RepositoryTabGroup> _groups = [];
  var _nextGroupId = 1;

  /// Tabs whose pane is still chosen from the status they open with.
  final Set<int> _openingPanes = {};

  /// The commit each tab last had selected in History, by tab id. Changes
  /// reuses the tab's selection for a path.
  final Map<int, String> _historySelections = {};

  /// The reference each tab shows in its filtered graph only while it is
  /// selected in the sidebar. Never persisted.
  final Map<int, String> _revealedReferences = {};
  RepositorySessionState? _current;
  var _generation = 0;
  var _nextTabId = 1;
  int? _activeTabId;
  var _disposed = false;

  Stream<RepositorySessionState> get states => _states.stream;
  Stream<WorkspaceState> get workspaceStates => _workspaceStates.stream;
  @override
  RepositorySessionState? get current => _current;
  WorkspaceState get workspace => WorkspaceState(
    tabs: List.unmodifiable(_tabs),
    activeTabId: _activeTabId,
    groups: List.unmodifiable(_groups),
  );

  /// The canonical identity of the active tab's repository.
  NativePathIdentity? get activeCanonical => activeTab?.canonicalIdentity;

  /// The active tab's ID, without building a [workspace] value.
  int? get activeTabId => _activeTabId;

  /// The active tab, without building a [workspace] value; hot paths read
  /// this instead of `workspace.activeTab`.
  RepositoryTabState? get activeTab {
    for (final tab in _tabs) {
      if (tab.id == _activeTabId) return tab;
    }
    return null;
  }

  /// The open tabs' sessions with their repositories, for background work.
  Iterable<
    ({
      RepositorySessionIdentity session,
      NativePathIdentity canonical,
      RepositorySnapshot snapshot,
    })
  >
  get openSessions => [
    for (final tab in _tabs)
      if ((tab.session, tab.canonicalIdentity) case (
        final session?,
        final canonical?,
      ))
        (
          session: session.identity,
          canonical: canonical,
          snapshot: session.snapshot,
        ),
  ];

  /// A new generation for a session that opens outside the workspace, such
  /// as a clone.
  int nextGeneration() => ++_generation;

  bool get disposed => _disposed;

  // SessionScope

  @override
  void ensureActive() {
    if (_disposed) throw StateError('repository_session_service_disposed');
  }

  @override
  RepositorySessionIdentity requireCurrent() {
    ensureActive();
    final current = _current;
    if (current == null) throw unknownSessionFailure;
    return current.identity;
  }

  @override
  bool isOpen(RepositorySessionIdentity identity) =>
      _tabIndexForSession(identity) >= 0;

  @override
  Future<void> refreshIfOpen(RepositorySessionIdentity identity) async {
    if (isOpen(identity)) await _sessions.refresh(identity);
  }

  @override
  Future<T> followingHead<T>(
    RepositorySessionIdentity identity,
    Future<T> Function() operation,
    bool Function(T result) moved,
  ) => _heads.follow(identity, _headOf(identity), operation, moved);

  // Restoring the workspace

  Future<void> restoreWorkspace() async {
    ensureActive();
    // A remote connection change alters which tabs are stale or reconnectable.
    _remoteStates ??= _remotes.states.listen((state) {
      if (_disposed) return;
      switch (state.phase) {
        case RemoteConnectionPhase.disconnected:
          remoteReconnect.lost(state.profileId, state.failure);
        case RemoteConnectionPhase.ready:
          // Connected by the user, from any dialog: tabs of the host whose
          // sessions belong to an earlier connection reopen on this one.
          _connectionEpochs.update(
            state.profileId,
            (epoch) => epoch + 1,
            ifAbsent: () => 1,
          );
          remoteReconnect.settled(state.profileId);
          unawaited(_reopenStaleRemoteTabs(state.profileId));
        case RemoteConnectionPhase.idle:
          // Closed on purpose.
          remoteReconnect.settled(state.profileId);
        default:
          break;
      }
      _publishWorkspace();
    });
    final saved = _persistence.saved;
    if (saved == null) return;
    await _viewCache.warm(saved.openWorktrees);
    if (_disposed) return;
    final active = saved.activeWorktree;
    final selected = saved.openWorktrees.contains(active)
        ? active
        : saved.openWorktrees.lastOrNull;
    // Groups return with the first of their tabs.
    final savedGroups = <NativePathIdentity, TabGroupSettings>{
      for (final group in saved.tabGroups)
        for (final member in group.members) member: group,
    };
    final restoredGroups = <TabGroupSettings, int>{};
    int? restoredGroup(NativePathIdentity identity) {
      final saved = savedGroups[identity];
      if (saved == null) return null;
      return restoredGroups[saved] ??= _addGroup(
        name: saved.name,
        color: AppearanceColor.byKey(saved.color),
        icon: repositoryAppearanceIcons.contains(saved.icon)
            ? saved.icon
            : null,
        collapsed: saved.collapsed,
      );
    }

    // Tabs take their places in saved order at once and open side by side.
    // Only the selected one is activated, so no other history is loaded and
    // thrown away on the way to it.
    await Future.wait([
      for (final identity in saved.openWorktrees)
        _openTab(
          label: _identityLabel(identity),
          requestedIdentity: identity,
          groupId: restoredGroup(identity),
          activate: identity == selected,
          start: (generation) => _sessions.openIdentity(identity, generation),
        ).then<void>(
          (_) {},
          onError: (Object error) {
            // A failed tab remains visible while restoration continues.
            if (error is! RepositorySessionException) throw error;
          },
        ),
    ]);
    if (_disposed) return;
    if (active != null) {
      final match = _tabs.where((tab) => tab.canonicalIdentity == active);
      if (match.isNotEmpty) activateTab(match.first.id);
    }
    // Restored remote tabs connect their hosts on their own.
    for (final profileId in {
      for (final tab in _tabs)
        if (isRemoteTabStale(tab))
          ?(tab.requestedIdentity ?? tab.canonicalIdentity)?.remote?.profileId,
    }) {
      remoteReconnect.connectSoon(profileId);
    }
  }

  // Remote tabs

  /// Reconnects hosts whose open tabs lost their connection, and connects
  /// the hosts of restored tabs.
  late final RemoteReconnector remoteReconnect = RemoteReconnector(
    reconnect: reconnectRemote,
    wanted: _reconnectWanted,
  );

  /// Whether [profileId] has open tabs that need it, in a window that offers
  /// remote workspaces.
  bool _reconnectWanted(String profileId) {
    if (_disposed || _remotes.profile(profileId) == null) return false;
    return _tabs.any(
      (tab) =>
          (tab.requestedIdentity ?? tab.canonicalIdentity)?.remote?.profileId ==
          profileId,
    );
  }

  /// Counts each host's connections, so a tab can tell whether its session
  /// came from the current one.
  final Map<String, int> _connectionEpochs = {};

  /// The connection of its host each remote tab's session was opened on.
  final Map<int, int> _tabEpochs = {};

  /// Whether a remote tab shows state its connection no longer backs: it has
  /// no session, no connection, or a session of an earlier connection, which
  /// the host closed with it.
  bool isRemoteTabStale(RepositoryTabState tab) {
    final authority = (tab.canonicalIdentity ?? tab.requestedIdentity)?.remote;
    if (authority == null) return false;
    return tab.session == null ||
        !_remotes.isLive(authority) ||
        _tabEpochs[tab.id] != (_connectionEpochs[authority.profileId] ?? 0);
  }

  /// Applies a changed "Allow changes" choice to a live connection of
  /// [profileId]: it reconnects, since write capabilities are negotiated
  /// when a connection starts, and its tabs reopen on the new connection.
  /// Nothing happens without a live connection.
  Future<RemoteConnectionState?> applyRemoteAccess(String profileId) async {
    ensureActive();
    if (!_remotes.available || !_remotes.state(profileId).ready) return null;
    await _remotes.disconnect(profileId);
    if (_disposed) return null;
    return reconnectRemote(profileId);
  }

  /// Connects [profileId] and reopens its tabs on the new connection. Their
  /// navigation and drafts stay; the snapshot is replaced as a whole.
  Future<RemoteConnectionState?> reconnectRemote(String profileId) async {
    ensureActive();
    if (!_remotes.available) return null;
    final state = await _remotes.connect(profileId);
    if (_disposed || !state.ready) return state;
    for (final tab in List<RepositoryTabState>.of(_tabs)) {
      final identity = tab.requestedIdentity ?? tab.canonicalIdentity;
      if (identity?.remote?.profileId != profileId) continue;
      if (tab.phase == RepositoryTabPhase.opening) continue;
      await _reopenTab(tab.id);
    }
    return state;
  }

  /// Reopens a remote tab whose repository no longer matches the one it
  /// opened, after the user chose to trust the repository found there now.
  Future<RepositorySessionState?> reopenChangedRemoteTab(int tabId) async {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return null;
    final tab = _tabs[index];
    final identity = tab.requestedIdentity ?? tab.canonicalIdentity;
    final authority = identity?.remote;
    if (identity == null ||
        authority == null ||
        tab.failure?.code != RepositoryFailureCode.remoteIdentityChanged) {
      return null;
    }
    _remotes.forgetBinding(authority, identity.units);
    return _reopenTab(tabId);
  }

  /// Reopens the tabs of [profileId] that show state no connection backs.
  Future<void> _reopenStaleRemoteTabs(String profileId) async {
    for (final tab in List<RepositoryTabState>.of(_tabs)) {
      if (_disposed) return;
      final identity = tab.requestedIdentity ?? tab.canonicalIdentity;
      if (identity?.remote?.profileId != profileId) continue;
      if (tab.phase == RepositoryTabPhase.opening) continue;
      if (!isRemoteTabStale(tab)) continue;
      try {
        await _reopenTab(tab.id);
      } on Object {
        // The tab is left failed and offers Reconnect; a connection change
        // must not raise an error nobody awaits.
      }
    }
  }

  /// Tabs being reopened; a second request for one of them waits for none.
  final Set<int> _reopening = {};

  /// Reopens a tab's repository in place, keeping its position, group and
  /// navigation. A failure leaves the tab failed with its identity.
  Future<RepositorySessionState?> _reopenTab(int tabId) async {
    if (!_reopening.add(tabId)) return null;
    try {
      return await _reopenTabOnce(tabId);
    } finally {
      _reopening.remove(tabId);
    }
  }

  void _failReopen(int tabId, RepositoryFailure failure) {
    final failed = _tabIndex(tabId);
    if (failed < 0) return;
    _tabs[failed] = _tabs[failed].copyWith(
      phase: RepositoryTabPhase.failed,
      failure: failure,
    );
    _publishWorkspace();
  }

  Future<RepositorySessionState?> _reopenTabOnce(int tabId) async {
    final index = _tabIndex(tabId);
    if (index < 0) return null;
    final tab = _tabs[index];
    final identity = tab.requestedIdentity ?? tab.canonicalIdentity;
    if (identity == null) return null;
    final previous = tab.session?.identity;
    if (previous != null) {
      try {
        await _sessions.close(previous);
      } on RepositorySessionException {
        // The old session belongs to a closed connection.
      }
    }
    final generation = ++_generation;
    final reopening = _tabIndex(tabId);
    if (_disposed || reopening < 0) return null;
    _tabs[reopening] = RepositoryTabState(
      id: tabId,
      generation: generation,
      label: tab.label,
      phase: RepositoryTabPhase.opening,
      requestedIdentity: identity,
      navigation: tab.navigation,
      groupId: tab.groupId,
    );
    if (_activeTabId == tabId) _current = null;
    _publishWorkspace();
    final OpenedRepositorySession opened;
    try {
      opened = await _sessions.openIdentity(identity, generation);
    } on RepositorySessionException catch (error) {
      _failReopen(tabId, error.failure);
      return null;
    } on Object {
      _failReopen(tabId, const RepositoryFailure(RepositoryFailureCode.read));
      rethrow;
    }
    final current = _tabIndex(tabId);
    if (_disposed || current < 0 || _tabs[current].generation != generation) {
      await _sessions.close(opened.identity);
      return null;
    }
    return _adopt(opened, tabId: tabId, label: tab.label);
  }

  // Opening tabs

  int addRepositoryChooser() {
    ensureActive();
    final id = _nextTabId++;
    _tabs.add(
      RepositoryTabState(
        id: id,
        generation: ++_generation,
        label: '',
        phase: RepositoryTabPhase.choosing,
      ),
    );
    _activeTabId = id;
    _current = null;
    _publishWorkspace();
    return id;
  }

  Future<RepositorySessionState?> openFromChooser(
    int tabId, {
    NativePathIdentity? recent,
  }) async {
    ensureActive();
    bool available() =>
        !_disposed &&
        _tabs.any(
          (tab) => tab.id == tabId && tab.phase == RepositoryTabPhase.choosing,
        );
    if (!available()) return null;
    final path = recent == null ? await _chooseRepository() : null;
    // Cancellation and closing the chooser must not create another tab.
    if (!available() || (recent == null && path == null)) return null;
    return _openTab(
      replaceTabId: tabId,
      label: recent == null ? _pathLabel(path!) : _identityLabel(recent),
      requestedIdentity: recent,
      start: (generation) => recent == null
          ? _sessions.open(path!, generation)
          : _sessions.openIdentity(recent, generation),
    );
  }

  @override
  Future<RepositorySessionState> open(String path) => _openTab(
    label: _pathLabel(path),
    start: (generation) => _sessions.open(path, generation),
  );

  @override
  Future<RepositorySessionState> openRecent(NativePathIdentity identity) =>
      _openTab(
        label: _identityLabel(identity),
        requestedIdentity: identity,
        start: (generation) => _sessions.openIdentity(identity, generation),
      );

  Future<RepositorySessionState> initialize(
    String path, {
    String initialBranch = 'main',
    bool bare = false,
  }) => _openTab(
    label: _pathLabel(path),
    start: (generation) => _sessions.initialize(
      path,
      generation,
      initialBranch: initialBranch,
      bare: bare,
    ),
  );

  /// Creates a repository at [path] on [authority]'s connected host and
  /// opens it in a new tab.
  Future<RepositorySessionState> initializeRemote(
    RemoteAuthority authority,
    List<int> path, {
    String initialBranch = 'main',
    bool bare = false,
  }) async {
    ensureActive();
    if (!_remotes.available) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    await _remotes.initializeRepository(
      authority,
      path,
      initialBranch: initialBranch,
      bare: bare,
    );
    ensureActive();
    return openRecent(remotePathIdentity(authority, path));
  }

  /// The identity of the remote [path] of a connected host.
  static NativePathIdentity remotePathIdentity(
    RemoteAuthority authority,
    List<int> path,
  ) => NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: path,
    remote: authority,
  );

  /// Opens a session that opened outside the workspace, such as a finished
  /// clone, in a new tab. A session nobody waits for any more is closed.
  Future<RepositorySessionState> adoptOpened(
    OpenedRepositorySession opened, {
    required bool current,
  }) async {
    if (_disposed || !current) {
      await _sessions.close(opened.identity);
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.staleGeneration),
      );
    }
    return _adopt(
      opened,
      label: _identityLabel(opened.snapshot.identity?.worktreeRoot),
    );
  }

  Future<RepositorySessionState> _openTab({
    required String label,
    int? replaceTabId,
    NativePathIdentity? requestedIdentity,
    int? groupId,
    bool activate = true,
    required Future<OpenedRepositorySession> Function(int generation) start,
  }) async {
    ensureActive();
    if (requestedIdentity != null) {
      final existing = _tabs.where(
        (tab) =>
            tab.session != null &&
            (tab.canonicalIdentity == requestedIdentity ||
                tab.requestedIdentity == requestedIdentity),
      );
      if (existing.isNotEmpty) {
        final tab = existing.first;
        if (replaceTabId != null) {
          _tabs.removeWhere((item) => item.id == replaceTabId);
        }
        if (activate) activateTab(tab.id);
        return tab.session!;
      }
    }
    final generation = ++_generation;
    final tabId = replaceTabId ?? _nextTabId++;
    final replaced = replaceTabId == null ? -1 : _tabIndex(replaceTabId);
    final openingTab = RepositoryTabState(
      id: tabId,
      generation: generation,
      label: label,
      phase: RepositoryTabPhase.opening,
      requestedIdentity: requestedIdentity,
      navigation: _persistence.navigationFor(requestedIdentity),
      groupId: replaced < 0 ? groupId : _tabs[replaced].groupId,
    );
    if (replaceTabId == null) {
      _tabs.add(openingTab);
    } else {
      _tabs[_tabIndex(tabId)] = openingTab;
    }
    if (activate || _activeTabId == null) {
      _activeTabId = tabId;
      _current = null;
    }
    _publishWorkspace();
    late final OpenedRepositorySession opened;
    try {
      opened = await start(generation);
    } on RepositorySessionException catch (error) {
      final index = _tabIndex(tabId);
      if (index >= 0) {
        _tabs[index] = replaceTabId == null
            ? _tabs[index].copyWith(
                phase: RepositoryTabPhase.failed,
                failure: error.failure,
              )
            : RepositoryTabState(
                id: tabId,
                generation: generation,
                label: '',
                phase: RepositoryTabPhase.choosing,
                failure: error.failure,
                groupId: _tabs[index].groupId,
              );
        _publishWorkspace();
      }
      rethrow;
    }
    final index = _tabIndex(tabId);
    if (_disposed || index < 0) {
      await _sessions.close(opened.identity);
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.staleGeneration),
      );
    }
    final canonicalIdentity = opened.snapshot.identity?.worktreeRoot;
    if (canonicalIdentity != null) {
      final duplicateIndex = _tabs.indexWhere(
        (tab) =>
            tab.id != tabId &&
            tab.session != null &&
            (tab.canonicalIdentity == canonicalIdentity ||
                tab.requestedIdentity == canonicalIdentity),
      );
      if (duplicateIndex >= 0) {
        final duplicate = _tabs[duplicateIndex];
        await _sessions.close(opened.identity);
        final replacedActive = _activeTabId == tabId;
        _tabs.removeWhere((tab) => tab.id == tabId);
        if (activate || replacedActive) {
          activateTab(duplicate.id);
        } else {
          _publishWorkspace();
        }
        return duplicate.session!;
      }
    }
    return _adopt(opened, tabId: tabId, label: label);
  }

  RepositorySessionState _adopt(
    OpenedRepositorySession opened, {
    int? tabId,
    String? label,
  }) {
    final state = RepositorySessionState(
      identity: opened.identity,
      snapshot: _viewCache.present(opened.snapshot),
    );
    _viewCache.remember(opened.snapshot);
    final effectiveTabId = tabId ?? _nextTabId++;
    final index = _tabIndex(effectiveTabId);
    final existing = index < 0 ? null : _tabs[index];

    final tab = RepositoryTabState(
      id: effectiveTabId,
      generation: opened.identity.generation,
      label:
          label ??
          existing?.label ??
          _identityLabel(opened.snapshot.identity?.worktreeRoot),
      phase: RepositoryTabPhase.open,
      requestedIdentity: existing?.requestedIdentity,
      session: state,
      navigation: existing == null
          ? _persistence.navigationFor(opened.snapshot.identity?.worktreeRoot)
          : _isDefaultNavigation(existing.navigation)
          ? _persistence.navigationFor(
              opened.snapshot.identity?.worktreeRoot ??
                  existing.requestedIdentity,
            )
          : existing.navigation,
      groupId: existing?.groupId,
    );
    if (index < 0) {
      _tabs.add(tab);
    } else {
      _tabs[index] = tab;
    }
    final remoteProfile =
        (tab.canonicalIdentity ?? tab.requestedIdentity)?.remote?.profileId;
    _tabEpochs.removeWhere((id, _) => _tabIndex(id) < 0);
    if (remoteProfile == null) {
      _tabEpochs.remove(effectiveTabId);
    } else {
      _tabEpochs[effectiveTabId] = _connectionEpochs[remoteProfile] ?? 0;
    }
    if (tabId == null) _activeTabId = effectiveTabId;
    if (_activeTabId == effectiveTabId) {
      _current = state;
      _states.add(state);
      if (tab.navigation.pane == WorkspacePane.history) {
        _loadHistoryForTab(tab);
      }
    }
    _openingPanes.add(effectiveTabId);
    _chooseOpeningPane(effectiveTabId, opened.snapshot);
    _persistence.recordRecent(state.snapshot);
    _drain.start();
    _publishWorkspace();
    return state;
  }

  /// Shows History for a repository that opens without local changes, where
  /// the Changes pane would be empty. The last known status decides early; the
  /// first loaded status of [loaded] settles it. A pane the user picked in the
  /// meantime is kept.
  void _chooseOpeningPane(int tabId, RepositorySnapshot loaded) {
    if (!_openingPanes.contains(tabId)) return;
    final index = _tabIndex(tabId);
    if (index < 0) {
      _openingPanes.remove(tabId);
      return;
    }
    if (loaded.status != null || loaded.statusFailure != null) {
      _openingPanes.remove(tabId);
    }
    final tab = _tabs[index];
    final status = tab.session?.snapshot.status;
    if (status == null ||
        status.entries.isNotEmpty ||
        status.operations.isNotEmpty) {
      return;
    }
    _openingPanes.remove(tabId);
    if (tab.navigation.pane != WorkspacePane.changes) return;
    _tabs[index] = tab.copyWith(
      navigation: tab.navigation.copyWith(
        pane: WorkspacePane.history,
        route: WorkspaceRoute.repository,
        clearSelectedIdentity: true,
      ),
    );
    if (_activeTabId == tabId) _loadHistoryForTab(_tabs[index]);
  }

  // Tabs and groups

  void activateTab(int tabId) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0 || _activeTabId == tabId) return;
    _expandGroupOf(_tabs[index]);
    _revealedReferences.remove(_activeTabId);
    _activeTabId = tabId;
    _current = _tabs[index].session;
    if (_current case final current?) _states.add(current);
    history.clear();
    if (_tabs[index].navigation.pane == WorkspacePane.history) {
      _loadHistoryForTab(_tabs[index]);
    }
    _publishWorkspace();
  }

  void reorderTab(int tabId, int targetIndex) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0 || _tabs.length < 2) return;
    final bounded = targetIndex.clamp(0, _tabs.length - 1);
    if (index == bounded) return;
    final tab = _tabs.removeAt(index);
    _tabs.insert(bounded, tab);
    // Dropped between two tabs of a group, a tab joins it; dropped away from
    // its own group, it leaves it.
    final before = bounded > 0 ? _tabs[bounded - 1].groupId : null;
    final after = bounded < _tabs.length - 1
        ? _tabs[bounded + 1].groupId
        : null;
    final group = before != null && before == after
        ? before
        : tab.groupId != null && (before == tab.groupId || after == tab.groupId)
        ? tab.groupId
        : null;
    _tabs[bounded] = tab.copyWith(groupId: group, clearGroup: group == null);
    _keepWorktreesTogether(leader: tabId);
    _keepGroupsTogether();
    _publishWorkspace();
  }

  /// Puts [tabId] at [targetIndex] in [groupId], or in no group. Each
  /// group's tabs then gather where its first tab stands.
  void moveTab(int tabId, int targetIndex, {int? groupId}) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final group = groupId != null && _groupIndex(groupId) >= 0 ? groupId : null;
    final tab = _tabs.removeAt(index);
    _tabs.insert(
      targetIndex.clamp(0, _tabs.length),
      tab.copyWith(groupId: group, clearGroup: group == null),
    );
    _keepWorktreesTogether(leader: tabId);
    _keepGroupsTogether();
    _publishWorkspace();
  }

  /// Puts [tabId] at [targetIndex] among the other open worktrees of its
  /// repository; the worktree row's order.
  void moveWorktreeTab(int tabId, int targetIndex) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final others = [
      for (final tab in workspace.entryOf(tabId))
        if (tab.id != tabId) tab.id,
    ];
    if (others.isEmpty) return;
    final tab = _tabs.removeAt(index);
    final target = targetIndex < 0
        ? _tabIndex(others.first)
        : targetIndex < others.length
        ? _tabIndex(others[targetIndex])
        : _tabIndex(others.last) + 1;
    _tabs.insert(target, tab);
    _publishWorkspace();
  }

  /// Moves every tab of [groupId] so the group starts at [targetIndex]
  /// among the other tabs. A place inside another group moves it after that
  /// group.
  void moveTabGroup(int groupId, int targetIndex) {
    ensureActive();
    if (_groupIndex(groupId) < 0) return;
    final members = [
      for (final tab in _tabs)
        if (tab.groupId == groupId) tab,
    ];
    if (members.isEmpty) return;
    _tabs.removeWhere((tab) => tab.groupId == groupId);
    var target = targetIndex.clamp(0, _tabs.length);
    if (target > 0 && target < _tabs.length) {
      final split = _tabs[target - 1].groupId;
      if (split != null && split == _tabs[target].groupId) {
        target = _tabs.lastIndexWhere((tab) => tab.groupId == split) + 1;
      }
    }
    _tabs.insertAll(target, members);
    _publishWorkspace();
  }

  /// Gives [groupId] its [name], [color] and [icon] at once; an icon that
  /// is not one of [repositoryAppearanceIcons] clears it.
  void editTabGroup(
    int groupId, {
    required String name,
    required AppearanceColor color,
    String? icon,
  }) => _updateGroup(
    groupId,
    (group) => group.copyWith(
      name: normalizeTabName(name) ?? '',
      color: color,
      icon: icon,
      clearIcon: icon == null || !repositoryAppearanceIcons.contains(icon),
    ),
  );

  /// Puts [tabId] in a new group after the tab's current group, and returns
  /// the group's id. It takes the first colour no other group has.
  int? createTabGroup(int tabId) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return null;
    final used = {for (final group in _groups) group.color};
    final color = RepositoryAppearanceColor.values.firstWhere(
      (color) => !used.contains(PaletteColor(color)),
      orElse: () =>
          RepositoryAppearanceColor.values[_groups.length %
              RepositoryAppearanceColor.values.length],
    );
    final groupId = _addGroup(color: PaletteColor(color));
    _moveIntoGroup(index, groupId);
    _keepWorktreesTogether(leader: tabId);
    _publishWorkspace();
    return groupId;
  }

  /// Moves [tabId] to the end of [groupId].
  void addTabToGroup(int tabId, int groupId) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0 || _groupIndex(groupId) < 0) return;
    if (_tabs[index].groupId == groupId) return;
    _moveIntoGroup(index, groupId);
    _keepWorktreesTogether(leader: tabId);
    _publishWorkspace();
  }

  /// Takes [tabId] out of its group; it stands right after the group.
  void removeTabFromGroup(int tabId) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final groupId = _tabs[index].groupId;
    if (groupId == null) return;
    final worktrees = _worktreeIds(tabId);
    final tab = _tabs.removeAt(index).copyWith(clearGroup: true);
    final last = _tabs.lastIndexWhere(
      (item) => item.groupId == groupId && !worktrees.contains(item.id),
    );
    _tabs.insert(last + 1, tab);
    _keepWorktreesTogether(leader: tabId);
    _publishWorkspace();
  }

  void renameTabGroup(int groupId, String name) => _updateGroup(
    groupId,
    (group) => group.copyWith(name: normalizeTabName(name) ?? ''),
  );

  /// Collapses or expands [groupId]. Collapsing the group of the active tab
  /// activates the nearest tab outside it; with none, the group stays open.
  void setTabGroupCollapsed(int groupId, bool collapsed) {
    ensureActive();
    final groupIndex = _groupIndex(groupId);
    if (groupIndex < 0 || _groups[groupIndex].collapsed == collapsed) return;
    final activeIndex = _activeTabId == null ? -1 : _tabIndex(_activeTabId!);
    if (collapsed &&
        activeIndex >= 0 &&
        _tabs[activeIndex].groupId == groupId) {
      final replacement = _visibleNeighbour(activeIndex, except: groupId);
      if (replacement == null) return;
      _groups[groupIndex] = _groups[groupIndex].copyWith(collapsed: true);
      activateTab(replacement.id);
      return;
    }
    _groups[groupIndex] = _groups[groupIndex].copyWith(collapsed: collapsed);
    _publishWorkspace();
  }

  /// Dissolves [groupId]; its tabs stay open where they are.
  void ungroupTabs(int groupId) {
    ensureActive();
    if (_groupIndex(groupId) < 0) return;
    for (final (index, tab) in _tabs.indexed) {
      if (tab.groupId == groupId) _tabs[index] = tab.copyWith(clearGroup: true);
    }
    _groups.removeWhere((group) => group.id == groupId);
    _publishWorkspace();
  }

  /// Closes [tabIds] one after another, such as every open worktree of a
  /// repository.
  Future<void> closeTabs(List<int> tabIds) async {
    ensureActive();
    for (final tabId in tabIds) {
      if (_disposed) return;
      await closeTab(tabId);
    }
  }

  /// Closes every tab of [groupId].
  Future<void> closeTabGroup(int groupId) async {
    ensureActive();
    final members = [
      for (final tab in _tabs)
        if (tab.groupId == groupId) tab.id,
    ];
    for (final tabId in members) {
      if (_disposed) return;
      await closeTab(tabId);
    }
  }

  int _addGroup({
    String name = '',
    AppearanceColor? color,
    String? icon,
    bool collapsed = false,
  }) {
    final id = _nextGroupId++;
    _groups.add(
      RepositoryTabGroup(
        id: id,
        name: name,
        color: color ?? PaletteColor(RepositoryAppearanceColor.values.first),
        icon: icon,
        collapsed: collapsed,
      ),
    );
    return id;
  }

  int _groupIndex(int groupId) =>
      _groups.indexWhere((group) => group.id == groupId);

  void _updateGroup(
    int groupId,
    RepositoryTabGroup Function(RepositoryTabGroup group) update,
  ) {
    ensureActive();
    final index = _groupIndex(groupId);
    if (index < 0) return;
    final next = update(_groups[index]);
    if (next == _groups[index]) return;
    _groups[index] = next;
    _publishWorkspace();
  }

  /// Moves the tab at [index] to the end of [groupId] and joins it. A new
  /// group keeps the tab's place, unless the tab leaves another group; then
  /// it stands after that group.
  void _moveIntoGroup(int index, int groupId) {
    // The tab's other worktrees follow it; they do not count as group tabs.
    final worktrees = _worktreeIds(_tabs[index].id);
    final tab = _tabs.removeAt(index);
    final previous = tab.groupId;
    final last = _tabs.lastIndexWhere(
      (item) => item.groupId == groupId && !worktrees.contains(item.id),
    );
    final previousLast = previous == null
        ? -1
        : _tabs.lastIndexWhere(
            (item) => item.groupId == previous && !worktrees.contains(item.id),
          );
    final target = last >= 0
        ? last + 1
        : previousLast >= 0
        ? previousLast + 1
        : index;
    _tabs.insert(target, tab.copyWith(groupId: groupId));
  }

  /// Gathers each group's tabs where its first tab stands, keeping order.
  void _keepGroupsTogether() {
    final placed = <int>{};
    final ordered = <RepositoryTabState>[];
    for (final tab in _tabs) {
      final group = tab.groupId;
      if (group == null) {
        ordered.add(tab);
      } else if (placed.add(group)) {
        ordered.addAll(_tabs.where((item) => item.groupId == group));
      }
    }
    _tabs
      ..clear()
      ..addAll(ordered);
  }

  /// The ids of the open worktrees of [tabId]'s repository, [tabId]
  /// included.
  Set<int> _worktreeIds(int tabId) => {
    for (final tab in workspace.entryOf(tabId)) tab.id,
  };

  /// Gathers the open worktrees of each repository where its [leader] tab
  /// stands, or its first tab, in the leader's group. The tab strip shows
  /// them as one entry with a row of their own.
  void _keepWorktreesTogether({int? leader}) {
    final worktrees = <NativePathIdentity, List<RepositoryTabState>>{};
    for (final tab in _tabs) {
      if (tab.repository case final repository?) {
        (worktrees[repository] ??= []).add(tab);
      }
    }
    if (!worktrees.values.any((tabs) => tabs.length > 1)) return;
    final ordered = <RepositoryTabState>[];
    for (final tab in _tabs) {
      final members = worktrees[tab.repository];
      if (members == null || members.length < 2) {
        ordered.add(tab);
        continue;
      }
      final anchor = members.any((member) => member.id == leader)
          ? leader
          : members.first.id;
      if (tab.id != anchor) continue;
      final group = tab.groupId;
      for (final member in members) {
        ordered.add(
          member.groupId == group
              ? member
              : member.copyWith(groupId: group, clearGroup: group == null),
        );
      }
    }
    _tabs
      ..clear()
      ..addAll(ordered);
  }

  /// Drops groups without tabs and opens the active tab's group.
  void _settleGroups() {
    final used = {for (final tab in _tabs) tab.groupId};
    _groups.removeWhere((group) => !used.contains(group.id));
    final active = _activeTabId == null ? -1 : _tabIndex(_activeTabId!);
    if (active >= 0) _expandGroupOf(_tabs[active]);
  }

  void _expandGroupOf(RepositoryTabState tab) {
    final groupId = tab.groupId;
    if (groupId == null) return;
    final index = _groupIndex(groupId);
    if (index >= 0 && _groups[index].collapsed) {
      _groups[index] = _groups[index].copyWith(collapsed: false);
    }
  }

  bool _hidden(RepositoryTabState tab) =>
      _groups.any((group) => group.id == tab.groupId && group.collapsed);

  /// The closest tab to [index] that is shown and not in [except], looking
  /// right first.
  RepositoryTabState? _visibleNeighbour(int index, {int? except}) {
    for (var distance = 1; distance < _tabs.length; distance++) {
      for (final candidate in [index + distance, index - distance]) {
        if (candidate < 0 || candidate >= _tabs.length) continue;
        final tab = _tabs[candidate];
        if (tab.groupId != null && tab.groupId == except) continue;
        if (!_hidden(tab)) return tab;
      }
    }
    return null;
  }

  Future<void> closeTab(int tabId) async {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final wasActive = _activeTabId == tabId;
    final removed = _tabs.removeAt(index);
    _historySelections.remove(tabId);
    _heads.forgetTab(tabId);
    _revealedReferences.remove(tabId);
    _openingPanes.remove(tabId);
    if (removed.session case final session?) {
      _onSessionClosed(session.identity);
      await _sessions.close(session.identity);
    }
    if (wasActive) {
      history.clear();
      if (_tabs.isEmpty) {
        _activeTabId = null;
        _current = null;
      } else {
        final nearest = index.clamp(0, _tabs.length - 1);
        final replacement = !_hidden(_tabs[nearest])
            ? _tabs[nearest]
            : _visibleNeighbour(nearest) ?? _tabs[nearest];
        _activeTabId = replacement.id;
        _current = replacement.session;
        if (_current case final current?) _states.add(current);
        if (replacement.navigation.pane == WorkspacePane.history) {
          _loadHistoryForTab(replacement);
        }
      }
    }
    if (!_tabs.any((tab) => tab.session != null)) _drain.stop();
    _publishWorkspace();
  }

  // ExtensionTabs

  @override
  Future<List<NativePathIdentity>> closeWorktreeTabs(
    NativePathIdentity root,
    RepositorySessionIdentity source,
  ) async {
    final closed = <NativePathIdentity>[];
    final affected = _tabs
        .where(
          (tab) =>
              tab.session?.identity != source && tab.canonicalIdentity == root,
        )
        .map((tab) => tab.id)
        .toList(growable: false);
    for (final tabId in affected) {
      closed.add(root);
      await closeTab(tabId);
    }
    return closed;
  }

  @override
  Future<void> restoreWorktreeTabs(
    List<NativePathIdentity> worktrees,
    RepositorySessionIdentity source,
  ) async {
    for (final worktree in worktrees) {
      try {
        await openRecent(worktree);
      } on RepositorySessionException {
        // A concurrent external delete makes reopening impossible. The source
        // repository remains authoritative and is reselected below.
      }
    }
    final sourceIndex = _tabIndexForSession(source);
    if (sourceIndex >= 0) activateTab(_tabs[sourceIndex].id);
  }

  // Navigation and History

  void updateNavigation(int tabId, WorkspaceNavigation navigation) {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    if (navigation.pane != _tabs[index].navigation.pane) {
      _openingPanes.remove(tabId);
    }
    _tabs[index] = _tabs[index].copyWith(navigation: navigation);
    if (navigation.pane == WorkspacePane.history) {
      if (navigation.selectedIdentity case final selected?) {
        _historySelections[tabId] = selected;
      }
    }
    _publishWorkspace();
  }

  /// Reloads the history the active tab shows in place, keeping its
  /// selection where the reloaded history still has it.
  void reloadShownHistory() {
    ensureActive();
    final tab = activeTab;
    if (tab == null || tab.navigation.pane != WorkspacePane.history) return;
    _loadHistoryForTab(tab, entering: false);
  }

  /// Loads the history of tab [tabId] and selects a commit in it: the one the
  /// tab had selected before it left History, otherwise the current HEAD.
  Future<void> showHistory(int tabId) async {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    final session = tab.session;
    if (session == null) return;
    if (_takeHeadReveal(tab) case final reveal?) {
      await _loadHistoryAndReveal(tabId, session.identity, reveal);
      return;
    }
    await _loadHistoryAndRestoreSelection(
      tabId,
      session.identity,
      tab.navigation.selectedIdentity,
    );
  }

  /// Filters the history graph of tab [tabId] to [filter]'s branches and
  /// remembers the filter with the repository. The graph of the active tab
  /// changes straight away; another tab's applies when its history loads.
  Future<void> setBranchFilter(int tabId, HistoryBranchFilter filter) async {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    if (tab.navigation.branchFilter == filter) return;
    _tabs[index] = tab.copyWith(
      navigation: tab.navigation.copyWith(branchFilter: filter),
    );
    _publishWorkspace();
    if (tabId == _activeTabId && tab.session != null) {
      await history.applyBranchFilter(shownBranchFilter(_tabs[index]));
    }
  }

  /// Shows [reference] in the graph of tab [tabId] even when the tab's branch
  /// filter leaves it out, until another reference or null replaces it. The
  /// remembered filter does not change.
  Future<void> revealReference(int tabId, String? reference) async {
    ensureActive();
    final index = _tabIndex(tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    final before = shownBranchFilter(tab);
    if (reference == null) {
      _revealedReferences.remove(tabId);
    } else {
      _revealedReferences[tabId] = reference;
    }
    final shown = shownBranchFilter(tab);
    if (shown == before || tabId != _activeTabId || tab.session == null) {
      return;
    }
    await history.applyBranchFilter(shown);
  }

  /// The tab's branch filter plus the reference revealed in it. An empty
  /// filter already shows every reference.
  HistoryBranchFilter shownBranchFilter(RepositoryTabState tab) {
    final filter = tab.navigation.branchFilter;
    final revealed = _revealedReferences[tab.id];
    if (revealed == null ||
        filter.isEmpty ||
        filter.contains(revealed) ||
        filter.length >= HistoryBranchFilter.maximumReferences) {
      return filter;
    }
    return HistoryBranchFilter([...filter.references, revealed]);
  }

  /// The tab showing [session], if one does.
  RepositoryTabState? tabForSession(RepositorySessionIdentity session) {
    final index = _tabIndexForSession(session);
    return index < 0 ? null : _tabs[index];
  }

  /// Rescans the active repository for changes made outside the application.
  ///
  /// The application's own operations do not call this. Each holds the native
  /// mutation lease, whose release rescans the repository before the operation
  /// reports its result. A second request would discard that scan's cached
  /// reads and hold the History graph back for another pass over the worktree.
  @override
  Future<void> refresh() async {
    await _sessions.refresh(requireCurrent());
  }

  /// Completes only when a newer snapshot has reached the workspace. A refresh
  /// request being accepted is not evidence that its references are ready.
  Future<void> refreshAndWait(RepositorySessionIdentity identity) async {
    ensureActive();
    final index = _tabIndexForSession(identity);
    if (index < 0) throw unknownSessionFailure;
    final revision = _tabs[index].session!.snapshot.revision;
    final completed = Completer<void>();
    void inspect() {
      if (completed.isCompleted) return;
      final index = _tabIndexForSession(identity);
      if (index < 0) {
        completed.completeError(unknownSessionFailure);
        return;
      }
      final snapshot = _tabs[index].session!.snapshot;
      if (snapshot.revision <= revision) return;
      final failure =
          snapshot.failure ?? snapshot.refsFailure ?? snapshot.statusFailure;
      if (failure != null) {
        completed.completeError(RepositorySessionException(failure));
      } else if (snapshot.phase == RepositoryPhase.ready) {
        completed.complete();
      }
    }

    final subscription = workspaceStates.listen(
      (_) => inspect(),
      onDone: () {
        if (!completed.isCompleted) {
          completed.completeError(unknownSessionFailure);
        }
      },
    );
    // Attach the error/timeout handler before requesting a refresh.
    final waiting = completed.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.timedOut),
      ),
    );
    try {
      await Future.wait([
        _sessions.refresh(identity),
        waiting,
      ], eagerError: true);
    } finally {
      await subscription.cancel();
      // A failed refresh request must not leave an unobserved timeout future.
      if (!completed.isCompleted) completed.complete();
    }
  }

  // Events

  Future<void> _drainEvents(RepositorySessionIdentity identity) async {
    if (_disposed) return;
    try {
      final events = await _sessions.events(identity);
      if (_disposed) return;
      for (final event in events) {
        final snapshot = event.snapshot;
        final index = _tabIndexForSession(identity);
        if (index < 0) continue;
        if (event.kind == RepositorySessionEventKind.watchOverflow) {
          final revision = event.watchOverflowRevision;
          if (revision != null) {
            final previous = _tabs[index].watchOverflowRevision;
            if (previous == null || revision > previous) {
              _tabs[index] = _tabs[index].copyWith(
                watchOverflowRevision: revision,
              );
              _publishWorkspace();
            }
          }
        }
        if (snapshot == null) continue;
        final current = _tabs[index].session!;
        if (event.kind != RepositorySessionEventKind.resynchronize &&
            snapshot.revision < current.snapshot.revision) {
          continue;
        }
        _viewCache.remember(snapshot);
        final presented = _viewCache.present(snapshot);
        final next = current.copyWith(snapshot: presented);
        final reloadVisibleHistory =
            _activeTabId == _tabs[index].id &&
            _tabs[index].navigation.pane == WorkspacePane.history &&
            _historyProjectionChanged(current.snapshot, presented);
        // Taken for every snapshot: a HEAD seen while History is hidden is
        // kept for the tab and revealed only while it is still HEAD.
        final followedHead = _heads.take(identity, presented);
        final overflowRevision = _tabs[index].watchOverflowRevision;
        final recoveredFromOverflow =
            overflowRevision != null &&
            snapshot.phase == RepositoryPhase.ready &&
            snapshot.failure == null &&
            snapshot.revision > overflowRevision;
        _tabs[index] = _tabs[index].copyWith(
          phase: snapshot.phase == RepositoryPhase.failed
              ? RepositoryTabPhase.failed
              : RepositoryTabPhase.open,
          session: next,
          failure: snapshot.failure,
          clearFailure: snapshot.failure == null,
          clearWatchOverflow: recoveredFromOverflow,
        );
        if (_activeTabId == _tabs[index].id) {
          _current = next;
          _states.add(next);
          if (reloadVisibleHistory) {
            _loadHistoryForTab(
              _tabs[index],
              entering: false,
              reveal: followedHead,
            );
          } else if (followedHead != null) {
            _heads.keepReveal(_tabs[index].id, followedHead);
          }
        } else if (followedHead != null) {
          _heads.keepReveal(_tabs[index].id, followedHead);
        }
        _chooseOpeningPane(_tabs[index].id, snapshot);
        _persistence.recordRecent(snapshot);
        _publishWorkspace();
      }
    } on RepositorySessionException catch (error) {
      final index = _tabIndexForSession(identity);
      if (index >= 0) {
        final failed = _tabs[index].session!.copyWith(
          transportFailure: error.failure,
        );
        _tabs[index] = _tabs[index].copyWith(
          phase: RepositoryTabPhase.failed,
          session: failed,
          failure: error.failure,
        );
        if (_activeTabId == _tabs[index].id) {
          _current = failed;
          _states.add(failed);
        }
        _publishWorkspace();
      }
    }
  }

  /// [entering] is false for a reload of the history that is already shown,
  /// which selects nothing the tab did not have selected.
  ///
  /// [reveal] names a commit the reloaded history selects and scrolls to.
  void _loadHistoryForTab(
    RepositoryTabState tab, {
    bool entering = true,
    String? reveal,
  }) {
    final session = tab.session;
    if (session == null) return;
    final kept = _takeHeadReveal(tab);
    reveal ??= kept;
    if (reveal != null) {
      unawaited(_loadHistoryAndReveal(tab.id, session.identity, reveal));
      return;
    }
    final selectedIdentity = tab.navigation.selectedIdentity;
    unawaited(
      _loadHistoryAndRestoreSelection(
        tab.id,
        session.identity,
        selectedIdentity,
        entering: entering,
      ),
    );
  }

  /// The HEAD an operation moved [tab] to while it did not show History,
  /// while it is still HEAD.
  String? _takeHeadReveal(RepositoryTabState tab) =>
      _heads.takeReveal(tab.id, tab.session?.snapshot.status?.headObjectId);

  String? _headOf(RepositorySessionIdentity identity) {
    final index = _tabIndexForSession(identity);
    return index < 0
        ? null
        : _tabs[index].session?.snapshot.status?.headObjectId;
  }

  /// Reloads the shown history and moves its selection to [objectId], so the
  /// commits an operation brought in are on screen instead of above the old
  /// rows.
  Future<void> _loadHistoryAndReveal(
    int tabId,
    RepositorySessionIdentity identity,
    String objectId,
  ) async {
    await history.load(identity, priorityObjectIds: [objectId]);
    // Another reload may start while the selection waits and drop it.
    for (var attempt = 0; attempt < 3; attempt++) {
      final index = _tabIndex(tabId);
      if (index < 0 || _activeTabId != tabId) return;
      final tab = _tabs[index];
      final session = tab.session;
      if (session == null ||
          session.identity.nativeId != identity.nativeId ||
          session.identity.generation != identity.generation ||
          tab.navigation.pane != WorkspacePane.history) {
        return;
      }
      if (attempt == 0) {
        updateNavigation(
          tabId,
          tab.navigation.copyWith(selectedIdentity: objectId),
        );
      } else if (tab.navigation.selectedIdentity != objectId) {
        // The user selected something else in the meantime.
        return;
      }
      await history.select(objectId, reveal: true, focus: false);
      if (history.current.page?.selectedObjectIds.contains(objectId) == true) {
        return;
      }
    }
  }

  Future<void> _loadHistoryAndRestoreSelection(
    int tabId,
    RepositorySessionIdentity identity,
    String? selectedIdentity, {
    bool entering = true,
  }) async {
    final remembered =
        selectedIdentity ?? (entering ? _historySelections[tabId] : null);
    await history.load(identity, priorityObjectIds: [?remembered]);
    if (history.current.page?.selectedObjectIds.isNotEmpty == true) return;
    // A remembered commit may be gone after a rewrite; HEAD is always there.
    var expected = selectedIdentity;
    for (final useHead in const [false, true]) {
      final index = _tabIndex(tabId);
      if (index < 0 || _activeTabId != tabId) return;
      final tab = _tabs[index];
      final session = tab.session;
      if (session == null ||
          session.identity.nativeId != identity.nativeId ||
          session.identity.generation != identity.generation ||
          tab.navigation.pane != WorkspacePane.history ||
          tab.navigation.selectedIdentity != expected) {
        return;
      }
      final candidate = useHead
          ? session.snapshot.status?.headObjectId ??
                session.snapshot.identity?.headObjectId
          : remembered;
      if (candidate == null ||
          (useHead && (!entering || candidate == remembered))) {
        continue;
      }
      // The tab names the commit before its detail loads, as a selection by
      // hand does.
      if (expected != candidate) {
        expected = candidate;
        updateNavigation(
          tabId,
          tab.navigation.copyWith(selectedIdentity: candidate),
        );
      }
      await history.select(candidate, focus: true);
      if (history.current.page?.selectedObjectIds.contains(candidate) == true) {
        return;
      }
    }
  }

  // Lifecycle

  /// Closes every tab and its session. [beforeSessionsClose] runs once the
  /// tabs are gone and before their sessions close, so callers forget what
  /// belonged to them first.
  Future<void> close({void Function()? beforeSessionsClose}) async {
    _drain.stop();
    final sessions = [
      for (final tab in _tabs)
        if (tab.session case final session?) session.identity,
    ];
    _tabs.clear();
    _activeTabId = null;
    _current = null;
    _generation += 1;
    beforeSessionsClose?.call();
    history.clear();
    for (final identity in sessions) {
      await _sessions.close(identity);
    }
    _publishWorkspace();
  }

  /// Marks the workspace disposed: every later call fails, and the event
  /// drain stops.
  void retire() {
    if (_disposed) return;
    _disposed = true;
    _drain.dispose();
    unawaited(_remoteStates?.cancel());
  }

  /// Releases the streams and the reconnector after [retire] and [close].
  Future<void> dispose() async {
    retire();
    await _states.close();
    await _workspaceStates.close();
    await remoteReconnect.dispose();
  }

  int _tabIndex(int tabId) => _tabs.indexWhere((tab) => tab.id == tabId);

  int _tabIndexForSession(RepositorySessionIdentity identity) =>
      _tabs.indexWhere(
        (tab) =>
            tab.session?.identity.nativeId == identity.nativeId &&
            tab.session?.identity.generation == identity.generation,
      );

  void _publishWorkspace() {
    _keepWorktreesTogether();
    _settleGroups();
    if (!_workspaceStates.isClosed) _workspaceStates.add(workspace);
    if (!_disposed) {
      _persistence.persist(
        tabs: _tabs,
        groups: _groups,
        activeIdentity: workspace.activeTab?.canonicalIdentity,
      );
      _onPublished();
    }
  }
}

bool _historyProjectionChanged(
  RepositorySnapshot previous,
  RepositorySnapshot next,
) {
  final oldStatus = previous.status;
  final newStatus = next.status;
  if (oldStatus?.headObjectId != newStatus?.headObjectId ||
      oldStatus?.workingTree != newStatus?.workingTree ||
      oldStatus?.entries.length != newStatus?.entries.length ||
      _stagedEntryCount(oldStatus) != _stagedEntryCount(newStatus) ||
      !_sameValues(oldStatus?.branchName, newStatus?.branchName)) {
    return true;
  }
  // History displays the WIP state and file counts, not individual status paths.
  // A path-only status refresh must not restart topology and metadata loading.
  final oldRefs = previous.refs;
  final newRefs = next.refs;
  return !_sameLists(
        oldRefs.branches,
        newRefs.branches,
        (left, right) =>
            _sameValues(left.name, right.name) &&
            left.target == right.target &&
            left.head == right.head,
      ) ||
      !_sameLists(
        oldRefs.remotes,
        newRefs.remotes,
        (left, right) =>
            _sameValues(left.name, right.name) &&
            _sameLists(
              left.branches,
              right.branches,
              (oldBranch, newBranch) =>
                  _sameValues(oldBranch.name, newBranch.name) &&
                  oldBranch.target == newBranch.target,
            ),
      ) ||
      !_sameLists(
        oldRefs.tags,
        newRefs.tags,
        (left, right) =>
            _sameValues(left.name, right.name) && left.target == right.target,
      ) ||
      !_sameLists(
        oldRefs.stashes,
        newRefs.stashes,
        (left, right) =>
            _sameValues(left.selector, right.selector) &&
            left.objectId == right.objectId &&
            _sameValues(left.subject, right.subject),
      );
}

int _stagedEntryCount(RepositoryStatus? status) =>
    status?.entries.where((entry) => entry.staged).length ?? 0;

bool _sameValues<T>(List<T>? left, List<T>? right) {
  if (left == null || right == null) return left == right;
  return _sameLists(left, right, (oldValue, newValue) => oldValue == newValue);
}

bool _sameLists<T>(List<T> left, List<T> right, bool Function(T, T) equal) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (!equal(left[index], right[index])) return false;
  }
  return true;
}

String _pathLabel(String path) {
  final segments = path.split(RegExp(r'[/\\]'));
  return segments.lastWhere(
    (segment) => segment.isNotEmpty,
    orElse: () => path,
  );
}

/// A tab's label from its repository folder. Empty without one; the tab strip
/// shows its localized placeholder then.
String _identityLabel(NativePathIdentity? identity) => identity?.basename ?? '';

bool _isDefaultNavigation(WorkspaceNavigation navigation) =>
    navigation.pane == WorkspacePane.changes &&
    navigation.route == WorkspaceRoute.repository &&
    navigation.selectedIdentity == null &&
    navigation.changesScrollOffset == 0 &&
    navigation.historyScrollOffset == 0 &&
    navigation.branchFilter.isEmpty;
