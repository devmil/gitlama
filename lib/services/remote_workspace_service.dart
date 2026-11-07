import 'dart:async';
import 'dart:math';

import '../logging/app_logger.dart';
import '../logging/log_privacy.dart';
import '../models/operation_center.dart';
import '../models/remote_workspace.dart';
import '../models/settings.dart';
import '../repositories/remote_connection_repository.dart';
import '../repositories/remote_session_repository.dart';
import 'operation_center_service.dart';
import 'session/workspace_remotes.dart';
import 'settings_service.dart';

final _log = AppLogger('RemoteWorkspace');

/// A stable code for a failed host profile change, safe to show and log.
String remoteProfileSaveFailureCode(Object error) => switch (error) {
  SettingsException(:final code, :final rule) => [
    'settings_${code.name}',
    ?rule,
  ].join('_'),
  RemoteWorkspaceException(:final code) => 'remote_${code.name}',
  StateError() => 'service_disposed',
  _ => 'unexpected_${error.runtimeType}',
};

/// How long application shutdown waits for remote connections to close.
const remoteShutdownDeadline = Duration(seconds: 5);

/// Remote sessions use identifiers from here up, disjoint from local ones.
final remoteSessionIdBase = BigInt.one << 62;

final class _Connection {
  _Connection(this.profileId, this.channel, this.surface, this.authority);

  final String profileId;
  final RemoteChannel channel;
  final RemoteSessionSurface surface;
  final RemoteAuthority authority;
  var closing = false;
}

/// Owns host profiles, remote connections and the record of remote writes.
///
/// Nothing connects at startup: a connection starts only from an explicit
/// user action, and a failed or dropped connection stays down until the user
/// reconnects. A helper reporting a different store or account than the
/// profile verified is never attached silently; the user rebinds explicitly,
/// which also withdraws write permission.
final class RemoteWorkspaceService
    implements RemoteOperationLedger, RemoteOperationSource, WorkspaceRemotes {
  RemoteWorkspaceService(
    this._connections,
    this._sessions,
    this._pending,
    this._settings, {
    required this._directory,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Where ready connections publish their session surfaces for routing.
  final RemoteSessionDirectory _directory;

  final RemoteConnectionRepository _connections;
  final RemoteSessionFactory _sessions;
  final RemotePendingRepository _pending;
  final SettingsService _settings;
  final Random _random;

  final Map<String, _Connection> _live = {};
  final Map<String, Future<RemoteConnectionState>> _attempts = {};
  final Map<String, Completer<void>> _cancels = {};
  final Map<String, RemoteConnectionState> _states = {};

  /// Whether the latest connection attempt of each profile asked for writes.
  final Map<String, bool> _writesRequested = {};

  /// Why the live connection of [profileId] grants no writes; null when it
  /// asked for them, so a missing capability is the host's decision.
  RemoteWriteBlock? writeBlock(String profileId) {
    final selected = profile(profileId);
    if (selected == null || !selected.writesAllowed) {
      return RemoteWriteBlock.notAllowed;
    }
    if (!_ledgerUsable) return RemoteWriteBlock.ledgerUnavailable;
    if (_writesRequested[profileId] != true) return RemoteWriteBlock.reconnect;
    return null;
  }

  /// The platform each host reported when its helper was missing.
  final Map<String, RemoteHelperTarget> _hostTargets = {};

  /// What a helper reported when its identity did not match, by profile.
  final Map<String, RemoteVerifiedIdentity> _observed = {};

  /// Workspace bindings seen this run, so a reconnect detects a replaced
  /// repository at the same path.
  final Map<String, String> _bindings = {};
  final StreamController<RemoteConnectionState> _stateChanges =
      StreamController<RemoteConnectionState>.broadcast(sync: true);
  final StreamController<List<RemotePendingOperation>> _operationChanges =
      StreamController<List<RemotePendingOperation>>.broadcast(sync: true);
  List<RemotePendingOperation> _operations = const [];
  var _ledgerUsable = false;
  var _nextSession = remoteSessionIdBase;
  var _initialized = false;
  var _disposed = false;

  /// Loads the record of remote writes. An unreadable record is kept, and
  /// writes stay unavailable until it can be read.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _operations = List.unmodifiable(await _pending.load());
      _ledgerUsable = true;
    } on Object {
      // Without a readable record no remote write may start; reads still work.
      _ledgerUsable = false;
    }
  }

  @override
  bool get available => true;

  List<RemoteHostProfile> get profiles => _settings.current.remoteProfiles;

  @override
  RemoteHostProfile? profile(String id) =>
      profiles.where((profile) => profile.id == id).firstOrNull;

  @override
  RemoteConnectionState state(String profileId) =>
      _states[profileId] ??
      RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.idle,
      );

  @override
  Stream<RemoteConnectionState> get states => _stateChanges.stream;

  /// Remote writes, newest last. Pending ones need reconciliation.
  List<RemotePendingOperation> get operations => _operations;

  Stream<List<RemotePendingOperation>> get operationChanges =>
      _operationChanges.stream;

  /// Whether remote writes can be recorded durably on this computer.
  bool get ledgerUsable => _ledgerUsable;

  /// The identity a helper reported that did not match its profile.
  RemoteVerifiedIdentity? observedIdentity(String profileId) =>
      _observed[profileId];

  void _publish(RemoteConnectionState state) {
    _states[state.profileId] = state;
    if (!_stateChanges.isClosed) _stateChanges.add(state);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('remote_workspace_service_disposed');
  }

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _saveProfiles(List<RemoteHostProfile> profiles) async {
    try {
      // A rejected save restores only the profiles, not settings others
      // changed meanwhile.
      await _settings.updateDurable(
        (document) =>
            document.copyWith(remoteProfiles: List.unmodifiable(profiles)),
        restore: (current, previous) =>
            current.copyWith(remoteProfiles: previous.remoteProfiles),
      );
    } on Object catch (error) {
      _log.warning('remote_profiles_save_failed', {
        'failure_code': LogField(
          remoteProfileSaveFailureCode(error),
          LogSensitivity.public,
        ),
      });
      rethrow;
    }
  }

  /// Creates or edits a profile. Changing the alias of a profile withdraws
  /// its verified identity and write permission: the alias may now reach a
  /// different computer.
  /// Saves a profile with the [color] and [icon] its tabs show; null shows
  /// none.
  Future<RemoteHostProfile> saveProfile({
    String? id,
    required String label,
    required String alias,
    String? color,
    String? icon,
  }) async {
    _ensureActive();
    if (!isValidRemoteLabel(label) || !isValidRemoteAlias(alias)) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    final existing = id == null ? null : profile(id);
    if (id != null && existing == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    if (existing == null && profiles.length >= RemoteHostProfile.capacity) {
      throw const RemoteWorkspaceException(RemoteFailureCode.capacity);
    }
    final RemoteHostProfile saved;
    if (existing == null) {
      saved = RemoteHostProfile(
        id: _uuid(),
        label: label,
        alias: alias,
        color: color,
        icon: icon,
      );
    } else if (existing.alias != alias) {
      await disconnect(existing.id);
      _observed.remove(existing.id);
      saved = existing.copyWith(
        label: label,
        alias: alias,
        clearVerified: true,
        writesAllowed: false,
        autoInstallHelper: false,
        color: () => color,
        icon: () => icon,
      );
    } else {
      saved = existing.copyWith(
        label: label,
        color: () => color,
        icon: () => icon,
      );
    }
    await _saveProfiles([
      for (final profile in profiles)
        if (profile.id != saved.id) profile,
      saved,
    ]);
    return saved;
  }

  /// Removes a profile's local record. Remote files, open tabs, drafts and
  /// recorded operations are kept; they stay bound to the old authority.
  Future<void> deleteProfile(String id) async {
    _ensureActive();
    await disconnect(id);
    _observed.remove(id);
    await _saveProfiles([
      for (final profile in profiles)
        if (profile.id != id) profile,
    ]);
    _states.remove(id);
  }

  /// Allows or withdraws staging and normal commits for the profile's
  /// verified identity. Takes effect on the next connection.
  /// Allows or forbids changes on a host. Before the host's first
  /// connection the choice applies to the identity that connection verifies;
  /// a changed identity withdraws it. A live connection keeps what it
  /// negotiated until it reconnects.
  Future<void> setWritesAllowed(String id, bool allowed) async {
    _ensureActive();
    final existing = profile(id);
    if (existing == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    await _saveProfiles([
      for (final profile in profiles)
        profile.id == id ? profile.copyWith(writesAllowed: allowed) : profile,
    ]);
  }

  /// Lets GitLama install its helper on the host without asking whenever
  /// the host lacks the helper this version needs, or asks again.
  Future<void> setAutoInstallHelper(String id, bool enabled) async {
    _ensureActive();
    final existing = profile(id);
    if (existing == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    if (existing.autoInstallHelper == enabled) return;
    await _saveProfiles([
      for (final profile in profiles)
        profile.id == id
            ? profile.copyWith(autoInstallHelper: enabled)
            : profile,
    ]);
  }

  /// Failures a (re)installation of the bundled helper can resolve.
  static bool installResolves(RemoteFailureCode? code) => switch (code) {
    RemoteFailureCode.helperNotInstalled ||
    RemoteFailureCode.installDirectory ||
    RemoteFailureCode.installWrite ||
    RemoteFailureCode.installDigest ||
    RemoteFailureCode.installExecute ||
    RemoteFailureCode.installFailed => true,
    _ => false,
  };

  /// The helper this application can install on [profileId]'s host; null
  /// until a connection found the host's platform, or when this build
  /// carries no helper for it.
  Future<RemoteHelperArtifact?> installableHelper(String profileId) async {
    final target = hostTarget(profileId);
    return target == null ? null : bundledHelper(target);
  }

  /// The compatibility version of the helper this application needs; null
  /// when unknown.
  Future<int?> helperVersion() async {
    final buildId = await helperBuildId();
    return buildId == null ? null : int.tryParse(buildId);
  }

  /// The build ID of the helper this application needs; null when unknown.
  Future<String?> helperBuildId() async {
    try {
      return await _connections.helperBuildId();
    } on Object {
      return null;
    }
  }

  /// The platform [profileId]'s host reported when its helper was missing;
  /// null until a connection attempt found no helper.
  RemoteHelperTarget? hostTarget(String profileId) => _hostTargets[profileId];

  /// The helper for [target] this application can install on a host; null
  /// when this build carries none.
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target) async {
    try {
      return await _connections.bundledHelper(target);
    } on Object {
      return null;
    }
  }

  /// Installs [artifact] on the profile's host after the user confirmed it,
  /// then connects. Shares the attempt slot with [connect] so the two never
  /// overlap; [cancel] stops either step.
  Future<RemoteConnectionState> installHelper(
    String profileId,
    RemoteHelperArtifact artifact,
  ) {
    _ensureActive();
    final live = _live[profileId];
    if (live != null && !live.closing) return Future.value(state(profileId));
    final existing = _attempts[profileId];
    if (existing != null) return existing;
    return _attempts[profileId] = _install(profileId, artifact).whenComplete(
      () {
        _attempts.remove(profileId);
        _cancels.remove(profileId);
      },
    );
  }

  Future<RemoteConnectionState> _install(
    String profileId,
    RemoteHelperArtifact artifact, {
    Completer<void>? cancel,
  }) async {
    final selected = profile(profileId);
    if (selected == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    cancel ??= _cancels[profileId] = Completer<void>();
    _publish(
      RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.installing,
      ),
    );
    try {
      await _connections.installHelper(
        alias: selected.alias,
        artifact: artifact,
        cancel: cancel.future,
      );
    } on Object catch (error) {
      final code = error is RemoteWorkspaceException
          ? error.code
          : RemoteFailureCode.internal;
      final failed = RemoteConnectionState(
        profileId: profileId,
        phase: code == RemoteFailureCode.canceled
            ? RemoteConnectionPhase.idle
            : RemoteConnectionPhase.failed,
        failure: code == RemoteFailureCode.canceled ? null : code,
      );
      _publish(failed);
      return failed;
    }
    if (cancel.isCompleted || _disposed) {
      final idle = RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.idle,
      );
      _publish(idle);
      return idle;
    }
    // Never installs twice in one attempt: a helper that is still missing
    // after its installation is a failure to show.
    return _connect(profileId, cancel: cancel, autoInstall: false);
  }

  /// Connects a profile. Concurrent requests share one attempt.
  @override
  Future<RemoteConnectionState> connect(String profileId) {
    _ensureActive();
    final live = _live[profileId];
    if (live != null && !live.closing) return Future.value(state(profileId));
    return _attempts[profileId] ??= _connect(profileId).whenComplete(() {
      _attempts.remove(profileId);
      _cancels.remove(profileId);
    });
  }

  /// Cancels a connection attempt in progress.
  void cancel(String profileId) {
    final cancel = _cancels[profileId];
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  Future<RemoteConnectionState> _connect(
    String profileId, {
    Completer<void>? cancel,
    bool autoInstall = true,
  }) async {
    final selected = profile(profileId);
    if (selected == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    cancel ??= _cancels[profileId] = Completer<void>();
    _publish(
      RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.connecting,
      ),
    );
    final writes = selected.writesAllowed && _ledgerUsable;
    _writesRequested[profileId] = writes;
    final requested = {
      RemoteCapability.read,
      RemoteCapability.listDirectory,
      if (writes) ...remoteWriteCapabilities,
    };
    final RemoteChannel channel;
    try {
      channel = await _connections.open(
        alias: selected.alias,
        capabilities: requested,
        cancel: cancel.future,
        onPhase: (phase) =>
            _publish(RemoteConnectionState(profileId: profileId, phase: phase)),
      );
    } on Object catch (error) {
      // Only typed failures carry a cause; anything else is internal.
      final code = error is RemoteWorkspaceException
          ? error.code
          : RemoteFailureCode.internal;
      if (error is RemoteWorkspaceException && error.hostTarget != null) {
        _hostTargets[profileId] = error.hostTarget!;
      }
      // A host the user lets GitLama look after receives the helper of this
      // version as soon as it lacks it, within the same attempt.
      if (autoInstall &&
          code == RemoteFailureCode.helperNotInstalled &&
          !cancel.isCompleted &&
          !_disposed &&
          (profile(profileId)?.autoInstallHelper ?? false)) {
        final artifact = await installableHelper(profileId);
        if (artifact != null && !cancel.isCompleted && !_disposed) {
          _log.info('remote_helper_auto_install');
          return _install(profileId, artifact, cancel: cancel);
        }
      }
      final failed = RemoteConnectionState(
        profileId: profileId,
        phase: code == RemoteFailureCode.canceled
            ? RemoteConnectionPhase.idle
            : RemoteConnectionPhase.failed,
        failure: code == RemoteFailureCode.canceled ? null : code,
      );
      _publish(failed);
      return failed;
    }
    final helper = channel.helper;
    final reported = RemoteVerifiedIdentity(
      storeId: helper.storeId,
      accountUid: helper.accountUid,
      accountName: helper.accountName,
    );
    var current = profile(profileId);
    if (_disposed || current == null || current.alias != selected.alias) {
      await channel.close();
      throw const RemoteWorkspaceException(RemoteFailureCode.canceled);
    }
    final verified = current.verified;
    if (verified != null &&
        (verified.storeId != reported.storeId ||
            verified.accountUid != reported.accountUid)) {
      _observed[profileId] = reported;
      await channel.close();
      final changed = RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.identityChanged,
        failure: RemoteFailureCode.identityChanged,
      );
      _publish(changed);
      return changed;
    }
    if (verified == null || verified.accountName != reported.accountName) {
      // The first explicit connection of a profile verifies its identity.
      current = current.copyWith(verified: reported);
      try {
        await _saveProfiles([
          for (final profile in profiles)
            profile.id == profileId ? current : profile,
        ]);
      } on Object {
        await channel.close();
        final failed = RemoteConnectionState(
          profileId: profileId,
          phase: RemoteConnectionPhase.failed,
          failure: RemoteFailureCode.internal,
        );
        _publish(failed);
        return failed;
      }
    }
    final authority = current.authority!;
    final surface = _sessions.create(
      channel,
      authority: authority,
      ledger: this,
      allocateSessionId: () => _nextSession += BigInt.one,
      expectedBinding: (path) => _bindings[_bindingKey(authority, path)],
      rememberBinding: (path, binding) =>
          _bindings[_bindingKey(authority, path)] = binding,
    );
    final connection = _Connection(profileId, channel, surface, authority);
    _live[profileId] = connection;
    _directory.publish(
      authority,
      surface,
      live: () =>
          identical(_live[profileId], connection) &&
          !connection.closing &&
          connection.channel.isOpen,
    );
    _observed.remove(profileId);
    final ready = RemoteConnectionState(
      profileId: profileId,
      phase: RemoteConnectionPhase.ready,
      helper: helper,
    );
    _publish(ready);
    unawaited(
      channel.closed.then((reason) {
        if (_live[profileId] != connection) return;
        _live.remove(profileId);
        _directory.withdraw(connection.authority);
        if (_disposed) return;
        _publish(
          RemoteConnectionState(
            profileId: profileId,
            phase: connection.closing || reason == null
                ? RemoteConnectionPhase.idle
                : RemoteConnectionPhase.disconnected,
            failure: connection.closing ? null : reason,
          ),
        );
      }),
    );
    unawaited(_reconcile(connection));
    return ready;
  }

  /// Accepts the identity a helper reported after it changed, withdrawing
  /// write permission, and connects again.
  Future<RemoteConnectionState> rebind(String profileId) async {
    _ensureActive();
    final observed = _observed[profileId];
    final existing = profile(profileId);
    if (observed == null || existing == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
    }
    await _saveProfiles([
      for (final profile in profiles)
        profile.id == profileId
            ? profile.copyWith(
                verified: observed,
                writesAllowed: false,
                autoInstallHelper: false,
              )
            : profile,
    ]);
    _observed.remove(profileId);
    return connect(profileId);
  }

  /// Closes a profile's connection. Its tabs keep their last received state
  /// as stale.
  @override
  Future<void> disconnect(String profileId) async {
    cancel(profileId);
    final connection = _live[profileId];
    if (connection == null) return;
    connection.closing = true;
    _publish(
      RemoteConnectionState(
        profileId: profileId,
        phase: RemoteConnectionPhase.disconnecting,
      ),
    );
    await connection.channel.close();
  }

  @override
  Future<List<OperationCenterSnapshot>> remoteOperations() => Future.wait([
    for (final connection in _live.values)
      if (!connection.closing && connection.channel.isOpen)
        connection.surface.operations(),
  ]);

  @override
  Future<void> dismissRemoteOperation(OperationCenterEntry entry) async {
    final session = entry.session;
    if (session == null) return;
    for (final connection in _live.values) {
      if (connection.surface.bindingOf(session) != null) {
        await connection.surface.dismissOperation(entry);
        return;
      }
    }
  }

  @override
  bool isLive(RemoteAuthority authority) =>
      _directory.surfaceFor(authority) != null;

  /// Forgets a binding after the user chose to reopen a replaced workspace.
  @override
  void forgetBinding(RemoteAuthority authority, List<int> path) {
    _bindings.remove(_bindingKey(authority, path));
  }

  static String _bindingKey(RemoteAuthority authority, List<int> path) =>
      '${authority.profileId}/${authority.storeId}/${authority.accountUid}/'
      '${path.join(',')}';

  /// One page of a remote directory on a connected profile.
  Future<RemoteDirectoryPage> listDirectory(
    String profileId, {
    List<int>? directory,
    String? cursor,
  }) {
    final connection = _live[profileId];
    if (connection == null || connection.closing) {
      throw const RemoteWorkspaceException(RemoteFailureCode.disconnected);
    }
    return connection.surface.listDirectory(
      directory: directory,
      cursor: cursor,
    );
  }

  /// Whether [profileId]'s live connection may create repositories; null
  /// when it is not connected.
  bool? canInitialize(String profileId) {
    final connection = _live[profileId];
    if (connection == null ||
        connection.closing ||
        !connection.channel.isOpen) {
      return null;
    }
    return connection.channel.helper.capabilities.contains(
      RemoteCapability.initialize,
    );
  }

  /// Creates a repository at [path] on [authority]'s connected host without
  /// opening it. Throws [RemoteWorkspaceException] with
  /// [RemoteFailureCode.disconnected] without a live connection of that
  /// authority and [RemoteFailureCode.writeNotPermitted] when the connection
  /// may not create repositories; the host's reasons for creating nothing
  /// arrive as [RepositorySessionException].
  @override
  Future<void> initializeRepository(
    RemoteAuthority authority,
    List<int> path, {
    required String initialBranch,
    required bool bare,
  }) async {
    _ensureActive();
    final surface = _directory.surfaceFor(authority);
    if (surface == null) {
      throw const RemoteWorkspaceException(RemoteFailureCode.disconnected);
    }
    if (canInitialize(authority.profileId) != true) {
      throw const RemoteWorkspaceException(RemoteFailureCode.writeNotPermitted);
    }
    await surface.initializeRepository(
      path: path,
      initialBranch: initialBranch,
      bare: bare,
    );
    _log.info('remote_repository_initialized');
  }

  @override
  Future<void> record(RemotePendingOperation operation) async {
    if (!_ledgerUsable) {
      throw const RemoteWorkspaceException(RemoteFailureCode.internal);
    }
    final next = [
      for (final existing in _operations)
        if (existing.operationId != operation.operationId) existing,
      operation,
    ];
    // Resolved operations beyond the bound go first; unresolved ones never.
    while (next.length > ContractLimits.pendingOperations) {
      final index = next.indexWhere((entry) => !entry.pending);
      if (index < 0) {
        throw const RemoteWorkspaceException(RemoteFailureCode.receiptCapacity);
      }
      next.removeAt(index);
    }
    await _pending.save(next);
    _operations = List.unmodifiable(next);
    if (!_operationChanges.isClosed) _operationChanges.add(_operations);
  }

  /// Removes a resolved operation the user acknowledged.
  Future<void> dismissOperation(String operationId) async {
    final remaining = [
      for (final operation in _operations)
        if (operation.operationId != operationId || operation.pending)
          operation,
    ];
    if (remaining.length == _operations.length) return;
    await _pending.save(remaining);
    _operations = List.unmodifiable(remaining);
    if (!_operationChanges.isClosed) _operationChanges.add(_operations);
  }

  /// Looks up every unresolved operation of the connection's authority. A
  /// lookup never executes anything; unresolved operations stay pending.
  Future<void> _reconcile(_Connection connection) async {
    for (final operation in _operations) {
      if (!operation.pending || operation.authority != connection.authority) {
        continue;
      }
      try {
        await record(await connection.surface.lookup(operation));
      } on Object {
        // A failed lookup leaves the operation pending for the next one.
      }
    }
  }

  /// Looks up a profile's unresolved operations again.
  Future<void> reconcile(String profileId) async {
    final connection = _live[profileId];
    if (connection != null) await _reconcile(connection);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final cancel in _cancels.values) {
      if (!cancel.isCompleted) cancel.complete();
    }
    final closing = [
      for (final connection in _live.values)
        (connection..closing = true).channel.close(),
    ];
    await Future.wait(
      closing,
    ).timeout(remoteShutdownDeadline, onTimeout: () => const []);
    for (final connection in _live.values) {
      _directory.withdraw(connection.authority);
    }
    _live.clear();
    await _stateChanges.close();
    await _operationChanges.close();
  }
}
