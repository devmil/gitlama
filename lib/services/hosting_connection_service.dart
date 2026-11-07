import 'dart:async';

import '../models/hosting.dart';
import '../models/hosting_link_cache.dart';
import '../models/settings.dart';
import '../repositories/hosting_link_cache_repository.dart';
import '../repositories/hosting_repository.dart';
import 'settings_service.dart';
import 'hosting_repository_session.dart';

final class HostingConnectionService {
  HostingConnectionService(
    this._repository,
    this._settings, {
    this._linkCache,
    this.linkPersistDelay = const Duration(seconds: 2),
  });

  final HostingRepository _repository;
  final HostingLinkCacheRepository? _linkCache;
  final Duration linkPersistDelay;

  /// Link entries kept in memory, one per repository.
  static const linkCacheCapacity = 32;
  final Map<NativePathIdentity, HostingLinkCacheEntry> _links = {};
  final Map<NativePathIdentity, Timer> _pendingLinks = {};
  final Set<Future<void>> _linkWrites = {};
  final SettingsService _settings;
  final StreamController<List<HostingConnection>> _changes =
      StreamController<List<HostingConnection>>.broadcast(sync: true);
  final StreamController<HostingResourceSnapshot> _resourceChanges =
      StreamController<HostingResourceSnapshot>.broadcast(sync: true);
  bool _initialized = false;
  bool _runtimeUsed = false;
  final Map<int, HostingConnection> _authorizations = {};
  final Map<int, (String, String)> _resourceRequests = {};
  final Map<int, (String, String)> _lookupRequests = {};

  HostingRepositorySession openRepositorySession({bool showResources = true}) =>
      HostingRepositorySession(this, showResources: showResources);

  List<HostingConnection> get connections =>
      List.unmodifiable(_settings.current.hostingConnections);
  Stream<List<HostingConnection>> get changes => _changes.stream;
  Stream<HostingResourceSnapshot> get resourceChanges =>
      _resourceChanges.stream;

  Future<void> openBrowser(String url) =>
      _repository.openBrowser(Uri.parse(url));
  Future<bool> githubCliAvailable() => _repository.githubCliAvailable();
  Future<bool> gitlabCliAvailable() => _repository.gitlabCliAvailable();

  /// The defaults a new connection of [preset] starts with, or null when a
  /// self-hosted preset has no valid `https` [webBase].
  Future<HostingPresetDefaults?> presetDefaults(
    HostingPreset preset, {
    String? webBase,
  }) => _repository.presetDefaults(preset, webBase: webBase);

  List<String> get expandedNodes =>
      List.unmodifiable(_settings.current.hostingExpandedNodes);

  HostingConnection? connectionFor(String id) =>
      connections.where((value) => value.id == id).firstOrNull;

  HostingBindingOverride? bindingFor(NativePathIdentity repository) => _settings
      .current
      .hostingBindings
      .where((binding) => binding.repository == repository)
      .firstOrNull;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final retained = <HostingConnection>[];
    for (final connection in _settings.current.hostingConnections) {
      try {
        retained.add(await _repository.validateConnection(connection));
      } on HostingException {
        // Invalid migrated metadata is removed without touching its secure item.
      }
    }
    if (retained.length != _settings.current.hostingConnections.length) {
      final retainedIds = retained.map((value) => value.id).toSet();
      await _saveHosting(
        (document) => document.copyWith(
          hostingConnections: retained,
          hostingBindings: document.hostingBindings
              .where((binding) => retainedIds.contains(binding.connectionId))
              .toList(growable: false),
        ),
      );
    }
  }

  Future<HostingConnection> saveConnection(HostingConnection connection) async {
    _ensureInitialized();
    final normalized = await _repository.validateConnection(connection);
    final current = connections;
    if (current.length >= 32 &&
        !current.any((value) => value.id == normalized.id)) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    if (current.any(
      (value) =>
          value.id != normalized.id &&
          value.credentialIdentity == normalized.credentialIdentity,
    )) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    final next = [
      for (final value in current)
        if (value.id != normalized.id) value,
      normalized,
    ]..sort((left, right) => left.id.compareTo(right.id));
    await _saveHosting(
      (document) => document.copyWith(hostingConnections: next),
    );
    _changes.add(List.unmodifiable(next));
    return normalized;
  }

  /// Saves hosting state, or restores the previous hosting state when the
  /// store rejects it, so a failed save never leaves an unsaved account listed.
  Future<void> _saveHosting(
    SettingsDocument Function(SettingsDocument current) change,
  ) => _settings.updateDurable(
    change,
    restore: (current, previous) => current.copyWith(
      hostingConnections: previous.hostingConnections,
      hostingBindings: previous.hostingBindings,
    ),
  );

  Future<void> removeConnection(String id) async {
    _ensureInitialized();
    final connection = connections.where((value) => value.id == id).firstOrNull;
    if (connection == null) return;
    final credential = await _repository.credentialState(connection);
    if (credential == HostingCredentialState.unreadable) {
      throw const HostingException(HostingFailureCode.credentialUnreadable);
    }
    final previous = _settings.current;
    final nextConnections = previous.hostingConnections
        .where((value) => value.id != id)
        .toList(growable: false);
    final nextBindings = previous.hostingBindings
        .where((value) => value.connectionId != id)
        .toList(growable: false);
    await _saveHosting(
      (document) => document.copyWith(
        hostingConnections: nextConnections,
        hostingBindings: nextBindings,
      ),
    );
    try {
      await _repository.removeCredential(connection);
    } on Object {
      // Put the account back, and only the hosting sections.
      await _saveHosting(
        (document) => document.copyWith(
          hostingConnections: previous.hostingConnections,
          hostingBindings: previous.hostingBindings,
        ),
      );
      rethrow;
    }
    _changes.add(List.unmodifiable(nextConnections));
  }

  Future<void> saveBinding(HostingBindingOverride binding) async {
    _ensureInitialized();
    if (!connections.any(
      (connection) => connection.id == binding.connectionId,
    )) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    final next = [
      for (final existing in _settings.current.hostingBindings)
        if (existing.repository != binding.repository) existing,
      binding,
    ];
    await _saveHosting((document) => document.copyWith(hostingBindings: next));
    _changes.add(connections);
  }

  Future<void> clearBinding(NativePathIdentity repository) async {
    _ensureInitialized();
    await _saveHosting(
      (document) => document.copyWith(
        hostingBindings: document.hostingBindings
            .where((binding) => binding.repository != repository)
            .toList(growable: false),
      ),
    );
    _changes.add(connections);
  }

  void setExpandedNodes(Iterable<String> nodes) {
    _ensureInitialized();
    final bounded = nodes.toSet().take(256).toList(growable: false)..sort();
    _settings.update(
      (document) => document.copyWith(hostingExpandedNodes: bounded),
    );
  }

  Future<HostingCredentialState> credentialState(String id) async {
    _ensureInitialized();
    final connection = connections.where((value) => value.id == id).firstOrNull;
    if (connection == null) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    return _repository.credentialState(connection);
  }

  Future<HostingOAuthSnapshot> startAuthorization(
    HostingConnection connection,
  ) async {
    _ensureInitialized();
    final normalized = await _repository.validateConnection(connection);
    final snapshot = await _repository.startAuthorization(normalized);
    if (snapshot.state == HostingOAuthState.succeeded) {
      final login = snapshot.authenticatedLogin;
      if (login == null) {
        throw const HostingOAuthException(
          HostingOAuthFailure.malformedResponse,
        );
      }
      await saveConnection(normalized.copyWith(login: login));
      return snapshot;
    }
    _runtimeUsed = true;
    _authorizations[snapshot.requestId] = normalized;
    return snapshot;
  }

  Future<HostingOAuthSnapshot?> pollAuthorization({
    required String connectionId,
    required int requestId,
  }) async {
    _ensureInitialized();
    final authorizingConnection = _authorizations[requestId];
    if (authorizingConnection == null ||
        authorizingConnection.id != connectionId) {
      return null;
    }
    final snapshot = await _repository.pollAuthorization(requestId);
    if (snapshot == null) {
      _authorizations.remove(requestId);
      return null;
    }
    if (snapshot.state == HostingOAuthState.succeeded) {
      final login = snapshot.authenticatedLogin;
      if (login == null) {
        throw const HostingOAuthException(
          HostingOAuthFailure.malformedResponse,
        );
      }
      await saveConnection(authorizingConnection.copyWith(login: login));
    }
    if (snapshot.isTerminal) _authorizations.remove(requestId);
    return snapshot;
  }

  /// Follows authorization [requestId] of [connectionId] until it ends:
  /// every [interval] it polls and emits the snapshot, and it closes after a
  /// terminal one or when the authorization is no longer known. Cancelling
  /// the subscription stops following; it does not cancel the authorization.
  Stream<HostingOAuthSnapshot> followAuthorization({
    required String connectionId,
    required int requestId,
    Duration interval = const Duration(milliseconds: 500),
  }) {
    Timer? timer;
    late final StreamController<HostingOAuthSnapshot> snapshots;
    void schedule() {
      timer = Timer(interval, () async {
        try {
          final snapshot = await pollAuthorization(
            connectionId: connectionId,
            requestId: requestId,
          );
          if (snapshots.isClosed) return;
          if (snapshot == null) {
            await snapshots.close();
            return;
          }
          snapshots.add(snapshot);
          if (snapshot.isTerminal) {
            await snapshots.close();
          } else {
            schedule();
          }
        } on Object catch (error, stackTrace) {
          if (snapshots.isClosed) return;
          snapshots.addError(error, stackTrace);
          await snapshots.close();
        }
      });
    }

    snapshots = StreamController<HostingOAuthSnapshot>(
      onListen: schedule,
      onCancel: () => timer?.cancel(),
    );
    return snapshots.stream;
  }

  Future<void> cancelAuthorization(int requestId) async {
    if (_authorizations.remove(requestId) != null) {
      await _repository.cancelAuthorization(requestId);
    }
  }

  Future<HostingResourceSnapshot> refreshResources({
    required String connectionId,
    required String providerRepository,
    int page = 1,
    bool manual = false,
  }) async {
    _ensureInitialized();
    final connection = connections
        .where((value) => value.id == connectionId)
        .firstOrNull;
    if (connection == null) {
      throw const HostingResourceException(
        HostingResourceFailure.invalidRequest,
      );
    }
    final snapshot = await _repository.startResourceRefresh(
      connection: connection,
      providerRepository: providerRepository,
      page: page,
      manual: manual,
    );
    _runtimeUsed = true;
    if (!snapshot.isTerminal) {
      _resourceRequests[snapshot.requestId] = (
        connectionId,
        providerRepository,
      );
    }
    _resourceChanges.add(snapshot);
    return snapshot;
  }

  Future<HostingResourceSnapshot?> pollResourceRefresh(int requestId) async {
    _ensureInitialized();
    if (!_resourceRequests.containsKey(requestId)) return null;
    final snapshot = await _repository.pollResourceRefresh(requestId);
    if (snapshot == null || snapshot.isTerminal) {
      _resourceRequests.remove(requestId);
    }
    if (snapshot != null) _resourceChanges.add(snapshot);
    return snapshot;
  }

  Future<void> cancelResourceRefresh(int requestId) async {
    if (_resourceRequests.remove(requestId) != null) {
      await _repository.cancelResourceRefresh(requestId);
    }
  }

  /// Starts a lookup of the CI result of commits [heads], the open pull
  /// requests for [branches] and, with [authored], those the connection's
  /// account opened.
  Future<HostingPullRequestLookupSnapshot> lookupPullRequests({
    required String connectionId,
    required String providerRepository,
    List<String> heads = const [],
    required List<String> branches,
    bool authored = false,
  }) async {
    _ensureInitialized();
    final connection = connectionFor(connectionId);
    if (connection == null) {
      throw const HostingResourceException(
        HostingResourceFailure.invalidRequest,
      );
    }
    final snapshot = await _repository.startPullRequestLookup(
      connection: connection,
      providerRepository: providerRepository,
      heads: heads,
      branches: branches,
      authoredBy: authored && connection.login.isNotEmpty
          ? connection.login
          : null,
    );
    _runtimeUsed = true;
    if (!snapshot.isTerminal) {
      _lookupRequests[snapshot.requestId] = (connectionId, providerRepository);
    }
    return snapshot;
  }

  Future<HostingPullRequestLookupSnapshot?> pollPullRequestLookup(
    int requestId,
  ) async {
    _ensureInitialized();
    if (!_lookupRequests.containsKey(requestId)) return null;
    final snapshot = await _repository.pollPullRequestLookup(requestId);
    if (snapshot == null || snapshot.isTerminal) {
      _lookupRequests.remove(requestId);
    }
    return snapshot;
  }

  Future<void> cancelPullRequestLookup(int requestId) async {
    if (_lookupRequests.remove(requestId) != null) {
      await _repository.cancelPullRequestLookup(requestId);
    }
  }

  /// The pull-request links last learned for [repository] under the given
  /// binding, from memory or private storage. Never throws.
  Future<HostingLinkCacheEntry?> cachedLinks(
    NativePathIdentity repository, {
    required String connectionId,
    required String providerRepository,
  }) async {
    var entry = _links[repository];
    if (entry == null) {
      final storage = _linkCache;
      if (storage == null) return null;
      try {
        final decoded = await storage.read(repository);
        if (decoded == null) return null;
        // What this run has learned meanwhile is newer than the storage.
        entry = _links.putIfAbsent(repository, () => decoded);
        _trimLinks();
      } on Object {
        return null;
      }
    }
    return entry.matches(connectionId, providerRepository) ? entry : null;
  }

  /// Keeps [entry] for [repository], writing it to private storage shortly.
  void rememberLinks(
    NativePathIdentity repository,
    HostingLinkCacheEntry entry,
  ) {
    _links
      ..remove(repository)
      ..[repository] = entry;
    _trimLinks();
    final storage = _linkCache;
    if (storage == null) return;
    _pendingLinks.remove(repository)?.cancel();
    _pendingLinks[repository] = Timer(linkPersistDelay, () {
      _pendingLinks.remove(repository);
      _writeLinks(storage, repository);
    });
  }

  void _writeLinks(
    HostingLinkCacheRepository storage,
    NativePathIdentity repository,
  ) {
    final entry = _links[repository];
    if (entry == null) return;
    late final Future<void> write;
    write = storage
        .write(repository, entry)
        .catchError((Object _) {})
        .whenComplete(() => _linkWrites.remove(write));
    _linkWrites.add(write);
  }

  void _trimLinks() {
    while (_links.length > linkCacheCapacity) {
      _links.remove(_links.keys.first);
    }
  }

  Future<void> deactivateResources({
    required String connectionId,
    required String providerRepository,
  }) async {
    _lookupRequests.removeWhere(
      (_, value) => value.$1 == connectionId && value.$2 == providerRepository,
    );
    for (final entry
        in _resourceRequests.entries
            .where(
              (entry) =>
                  entry.value.$1 == connectionId &&
                  entry.value.$2 == providerRepository,
            )
            .toList(growable: false)) {
      _resourceRequests.remove(entry.key);
    }
    if (_runtimeUsed) {
      await _repository.deactivateResources(
        connectionId: connectionId,
        providerRepository: providerRepository,
      );
    }
  }

  Future<HostingBindingResolution> resolveBinding({
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  }) {
    _ensureInitialized();
    return _repository.resolveBinding(
      connections: connections,
      remotes: remotes,
      overrideConnectionId: overrideConnectionId,
    );
  }

  Future<Uri> resourceLink({
    required String connectionId,
    required String providerRepository,
    required HostingResourceKind kind,
    int? number,
  }) {
    _ensureInitialized();
    final connection = connections
        .where((value) => value.id == connectionId)
        .firstOrNull;
    if (connection == null) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    return _repository.resourceLink(
      connection: connection,
      providerRepository: providerRepository,
      kind: kind,
      number: number,
    );
  }

  Future<HostingReferenceProjection?> projectReference({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int revision,
    required List<HostingRemoteReference> references,
    required bool stale,
  }) {
    _ensureInitialized();
    return _repository.projectReference(
      text: text,
      selectionBase: selectionBase,
      selectionExtent: selectionExtent,
      revision: revision,
      references: references,
      stale: stale,
    );
  }

  Future<HostingReferenceApplyResult> applyReference({
    required String text,
    required int currentRevision,
    required HostingReferenceProjection projection,
    required String insertion,
  }) {
    _ensureInitialized();
    return _repository.applyReference(
      text: text,
      currentRevision: currentRevision,
      projection: projection,
      insertion: insertion,
    );
  }

  Future<void> dispose() async {
    final storage = _linkCache;
    for (final MapEntry(key: repository, value: timer)
        in _pendingLinks.entries.toList(growable: false)) {
      timer.cancel();
      if (storage != null) _writeLinks(storage, repository);
    }
    _pendingLinks.clear();
    await Future.wait(_linkWrites.toList(growable: false));
    for (final requestId in _authorizations.keys.toList(growable: false)) {
      await _repository.cancelAuthorization(requestId);
    }
    _authorizations.clear();
    for (final requestId in _resourceRequests.keys.toList(growable: false)) {
      await _repository.cancelResourceRefresh(requestId);
    }
    _resourceRequests.clear();
    for (final requestId in _lookupRequests.keys.toList(growable: false)) {
      await _repository.cancelPullRequestLookup(requestId);
    }
    _lookupRequests.clear();
    if (_runtimeUsed) await _repository.shutdownRuntime();
    await _resourceChanges.close();
    await _changes.close();
  }

  void _ensureInitialized() {
    if (!_initialized) throw StateError('hosting_service_unavailable');
  }
}
