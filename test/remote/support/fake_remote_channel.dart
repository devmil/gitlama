import 'dart:async';

import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/remote_connection_repository.dart';

typedef FakeCallHandler =
    FutureOr<Object?> Function(String method, Map<String, Object?> arguments);

/// A scripted channel: each call is answered by [handler] and recorded.
final class FakeRemoteChannel implements RemoteChannel {
  FakeRemoteChannel({
    this.handler,
    Set<RemoteCapability>? capabilities,
    this.storeId = 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0',
    this.accountUid = '1000',
    this.accountName = 'alice',
  }) : capabilities =
           capabilities ??
           {RemoteCapability.read, RemoteCapability.listDirectory};

  FakeCallHandler? handler;
  final Set<RemoteCapability> capabilities;
  final String storeId;
  final String accountUid;
  final String accountName;
  final calls =
      <({String method, Map<String, Object?> arguments, bool bulk})>[];
  final _publications = StreamController<RemotePublication>.broadcast(
    sync: true,
  );
  final _closed = Completer<RemoteFailureCode?>();
  var closeRequests = 0;

  @override
  RemoteHelperInfo get helper => RemoteHelperInfo(
    buildId: '0123456789abcdef0123456789abcdef01234567',
    incarnation: 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1',
    storeId: storeId,
    accountUid: accountUid,
    accountName: accountName,
    gitVersion: '2.45.0',
    capabilities: capabilities,
  );

  @override
  Stream<RemotePublication> get publications => _publications.stream;

  @override
  Future<RemoteFailureCode?> get closed => _closed.future;

  @override
  bool get isOpen => !_closed.isCompleted;

  void publish(BigInt sessionId, Object? events) => _publications.add(
    RemotePublication(sessionId: sessionId, events: events),
  );

  /// Ends the channel as the transport would after a drop.
  void drop([RemoteFailureCode reason = RemoteFailureCode.disconnected]) {
    if (!_closed.isCompleted) _closed.complete(reason);
  }

  @override
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) async {
    calls.add((method: method, arguments: arguments, bulk: bulk));
    if (!isOpen) throw const RemoteCallException(RemoteErrorCode.disconnected);
    final respond = handler;
    if (respond == null) {
      throw const RemoteCallException(RemoteErrorCode.unsupportedCommand);
    }
    return respond(method, arguments);
  }

  @override
  Future<void> close() async {
    closeRequests += 1;
    if (!_closed.isCompleted) _closed.complete(null);
  }
}

/// Answers `open` with scripted channels or failures, recording requests.
final class FakeRemoteConnectionRepository
    implements RemoteConnectionRepository {
  FakeRemoteConnectionRepository(this.next);

  FutureOr<RemoteChannel> Function(Set<RemoteCapability> capabilities) next;
  final requests = <({String alias, Set<RemoteCapability> capabilities})>[];

  @override
  Future<RemoteHelperArtifact?> bundledHelper(
    RemoteHelperTarget target,
  ) async => null;

  @override
  Future<void> installHelper({
    required String alias,
    required RemoteHelperArtifact artifact,
    Future<void>? cancel,
  }) async => throw const RemoteWorkspaceException(
    RemoteFailureCode.installUnavailable,
  );

  @override
  Future<String?> helperBuildId() async =>
      '0123456789abcdef0123456789abcdef01234567';

  @override
  Future<RemoteChannel> open({
    required String alias,
    required Set<RemoteCapability> capabilities,
    Future<void>? cancel,
    void Function(RemoteConnectionPhase phase)? onPhase,
  }) async {
    requests.add((alias: alias, capabilities: capabilities));
    onPhase?.call(RemoteConnectionPhase.connecting);
    onPhase?.call(RemoteConnectionPhase.handshaking);
    return next(capabilities);
  }
}
