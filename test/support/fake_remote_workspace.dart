import 'dart:async';
import 'dart:typed_data';

import 'package:gitlama/repositories/impl/remote/remote_session_directory.dart';
import 'package:gitlama/models/operation_center.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/remote_connection_repository.dart';
import 'package:gitlama/repositories/remote_session_repository.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/remote_workspace_service.dart';
import 'package:gitlama/services/settings_service.dart';

const fakeStoreA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const fakeStoreB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// What one helper reports when a fake connection succeeds.
final class FakeHello {
  const FakeHello({
    this.storeId = fakeStoreA,
    this.accountUid = '1000',
    this.accountName = 'me',
    this.capabilities = const {
      RemoteCapability.read,
      RemoteCapability.listDirectory,
      ...remoteWriteCapabilities,
    },
  });

  final String storeId;
  final String accountUid;
  final String accountName;

  /// What the helper offers; the channel negotiates the intersection.
  final Set<RemoteCapability> capabilities;
}

final class FakeRemoteChannel implements RemoteChannel {
  FakeRemoteChannel(this.helper);

  @override
  final RemoteHelperInfo helper;
  final Completer<RemoteFailureCode?> _closed = Completer();

  /// The connection drops as if the host went away.
  void drop() {
    if (!_closed.isCompleted) _closed.complete(RemoteFailureCode.disconnected);
  }

  @override
  Stream<RemotePublication> get publications => const Stream.empty();

  @override
  Future<RemoteFailureCode?> get closed => _closed.future;

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) => Future.error(const RemoteCallException(RemoteErrorCode.internal));

  @override
  Future<void> close() async {
    if (!_closed.isCompleted) _closed.complete(null);
  }
}

/// Connects according to [results]: a [FakeHello] succeeds, a
/// [RemoteFailureCode] fails. Without results every attempt succeeds with
/// the default hello. [gate] holds attempts until it completes.
final class FakeRemoteConnections implements RemoteConnectionRepository {
  final List<Object> results = [];
  Completer<void>? gate;
  var opens = 0;
  FakeRemoteChannel? last;

  /// The helper offered for installation; none by default.
  RemoteHelperArtifact? helper;

  /// Install outcomes in order; an empty list installs successfully.
  final List<RemoteFailureCode> installResults = [];
  Completer<void>? installGate;
  final installs = <String>[];

  @override
  Future<RemoteHelperArtifact?> bundledHelper(
    RemoteHelperTarget target,
  ) async => helper?.target == target ? helper : null;

  /// The platform a host reports when its helper is missing.
  RemoteHelperTarget hostTarget = RemoteHelperTarget.linuxX86_64;

  @override
  Future<void> installHelper({
    required String alias,
    required RemoteHelperArtifact artifact,
    Future<void>? cancel,
  }) async {
    installs.add(alias);
    final gate = installGate;
    if (gate != null) {
      var canceled = false;
      await Future.any([
        gate.future,
        if (cancel != null) cancel.then((_) => canceled = true),
      ]);
      if (canceled) {
        throw const RemoteWorkspaceException(RemoteFailureCode.canceled);
      }
    }
    if (installResults.isNotEmpty) {
      throw RemoteWorkspaceException(installResults.removeAt(0));
    }
  }

  /// The helper ID this build needs.
  String helperId = '0123456789abcdef0123456789abcdef01234567';

  @override
  Future<String?> helperBuildId() async => helperId;

  @override
  Future<RemoteChannel> open({
    required String alias,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    void Function(RemoteConnectionPhase phase)? onPhase,
  }) async {
    opens += 1;
    onPhase?.call(RemoteConnectionPhase.connecting);
    final gate = this.gate;
    if (gate != null) {
      var canceled = false;
      await Future.any([
        gate.future,
        if (cancel != null) cancel.then((_) => canceled = true),
      ]);
      if (canceled) {
        throw const RemoteWorkspaceException(RemoteFailureCode.canceled);
      }
    }
    final next = results.isEmpty ? const FakeHello() : results.removeAt(0);
    if (next is RemoteFailureCode) {
      throw RemoteWorkspaceException(
        next,
        hostTarget: next == RemoteFailureCode.helperNotInstalled
            ? hostTarget
            : null,
      );
    }
    final hello = next as FakeHello;
    onPhase?.call(RemoteConnectionPhase.handshaking);
    return last = FakeRemoteChannel(
      RemoteHelperInfo(
        buildId: '0123456789abcdef0123456789abcdef01234567',
        incarnation: '00000000000000000000000000000001',
        storeId: hello.storeId,
        accountUid: hello.accountUid,
        accountName: hello.accountName,
        gitVersion: '2.43.0',
        capabilities: capabilities.intersection(hello.capabilities),
      ),
    );
  }
}

/// A directory listing answered by [list]; every request is recorded.
typedef FakeDirectoryLister =
    Future<RemoteDirectoryPage> Function(List<int>? directory, String? cursor);

final class FakeRemoteSurface implements RemoteSessionSurface {
  FakeRemoteSurface(this._factory);

  final FakeRemoteSessions _factory;

  @override
  RepositorySessionRepository get sessions =>
      _factory.repository ??
      (throw StateError('remote sessions are not used by the UI fakes'));

  @override
  RemoteDetachedReads get detachedReads =>
      throw StateError('detached reads are not used by the UI fakes');

  @override
  String? bindingOf(RepositorySessionIdentity session) => null;

  @override
  Future<OperationCenterSnapshot> operations() async =>
      OperationCenterSnapshot.empty;

  @override
  Future<void> dismissOperation(OperationCenterEntry entry) async {}

  @override
  Future<RemotePendingOperation> lookup(
    RemotePendingOperation operation,
  ) async => _factory.lookup?.call(operation) ?? operation;

  @override
  Future<void> initializeRepository({
    required List<int> path,
    required String initialBranch,
    required bool bare,
  }) async {
    _factory.initializations.add((
      path: path,
      initialBranch: initialBranch,
      bare: bare,
    ));
    final failure = _factory.initializeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<RemoteDirectoryPage> listDirectory({
    List<int>? directory,
    String? cursor,
  }) {
    _factory.listings.add((directory: directory, cursor: cursor));
    final list = _factory.list;
    if (list == null) {
      return Future.error(
        const RemoteWorkspaceException(RemoteFailureCode.unsupported),
      );
    }
    return list(directory, cursor);
  }
}

final class FakeRemoteSessions implements RemoteSessionFactory {
  FakeDirectoryLister? list;
  RemotePendingOperation Function(RemotePendingOperation operation)? lookup;
  final List<({List<int>? directory, String? cursor})> listings = [];

  /// Every repository the host was asked to create.
  final List<({List<int> path, String initialBranch, bool bare})>
  initializations = [];

  /// What creating a repository throws; null succeeds.
  Object? initializeFailure;

  /// The sessions every connection serves; most UI fakes need none.
  RepositorySessionRepository? repository;

  /// The binding callbacks the newest connection was created with.
  String? Function(List<int> path)? expectedBinding;
  void Function(List<int> path, String binding)? rememberBinding;

  @override
  RemoteSessionSurface create(
    RemoteChannel channel, {
    required RemoteAuthority authority,
    required RemoteOperationLedger ledger,
    required BigInt Function() allocateSessionId,
    required String? Function(List<int> path) expectedBinding,
    required void Function(List<int> path, String binding) rememberBinding,
  }) {
    this.expectedBinding = expectedBinding;
    this.rememberBinding = rememberBinding;
    return FakeRemoteSurface(this);
  }
}

final class FakeRemotePending implements RemotePendingRepository {
  FakeRemotePending([this.saved = const []]);

  List<RemotePendingOperation> saved;

  @override
  Future<List<RemotePendingOperation>> load() async => saved;

  @override
  Future<void> save(List<RemotePendingOperation> operations) async {
    saved = List.of(operations);
  }
}

/// A real [RemoteWorkspaceService] over the fakes.
final class FakeRemoteWorkspace {
  FakeRemoteWorkspace(SettingsService settings, {FakeRemotePending? pending})
    : pending = pending ?? FakeRemotePending() {
    service = RemoteWorkspaceService(
      connections,
      sessions,
      this.pending,
      settings,
      directory: directory,
    );
  }

  final connections = FakeRemoteConnections();

  /// Where the service publishes ready connections, for a router.
  final directory = LiveRemoteSessions();
  final sessions = FakeRemoteSessions();
  final FakeRemotePending pending;
  late final RemoteWorkspaceService service;
}

RemoteDirectoryEntry fakeEntry(
  String name,
  RemoteEntryKind kind, {
  bool repository = false,
}) => RemoteDirectoryEntry(
  name: Uint8List.fromList(name.codeUnits),
  kind: kind,
  repository: repository,
);

RemoteDirectoryPage fakePage(
  String directory,
  List<RemoteDirectoryEntry> entries, {
  String? parent,
  String? cursor,
  bool truncated = false,
}) => RemoteDirectoryPage(
  directory: Uint8List.fromList(directory.codeUnits),
  parent: parent == null ? null : Uint8List.fromList(parent.codeUnits),
  entries: entries,
  cursor: cursor,
  truncated: truncated,
);
