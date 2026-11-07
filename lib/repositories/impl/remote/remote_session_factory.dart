import '../../../models/operation_center.dart';
import '../../../models/remote_workspace.dart';
import '../../../models/settings.dart';
import '../../../models/repository_state.dart';
import '../../remote_connection_repository.dart';
import '../../remote_session_repository.dart';
import '../../repository_session_repository.dart';
import '../native_mappers.dart';
import '../native_repository_session_repository.dart';
import '../repository_session_calls.g.dart';
import 'remote_session_calls.dart';
import 'wire_values.dart';

/// Builds the session surface of a remote channel on the native session
/// adapter, so remote sessions share every projection with local ones.
final class WireRemoteSessionFactory implements RemoteSessionFactory {
  const WireRemoteSessionFactory();

  @override
  RemoteSessionSurface create(
    RemoteChannel channel, {
    required RemoteAuthority authority,
    required RemoteOperationLedger ledger,
    required BigInt Function() allocateSessionId,
    required String? Function(List<int> path) expectedBinding,
    required void Function(List<int> path, String binding) rememberBinding,
  }) {
    final calls = RemoteSessionCalls(
      channel,
      authority: authority,
      ledger: ledger,
      allocateSessionId: allocateSessionId,
      expectedBinding: expectedBinding,
    );
    return _WireRemoteSessionSurface(
      channel,
      calls,
      NativeRepositorySessionRepository.remote(
        calls,
        authority: authority,
        onOpened: (path, sessionId) {
          final binding = calls.bindingOf(sessionId);
          if (binding != null) rememberBinding(path, binding);
        },
      ),
    );
  }
}

final class _WireRemoteSessionSurface implements RemoteSessionSurface {
  _WireRemoteSessionSurface(this._channel, this._calls, this.sessions)
    : detachedReads = _DetachedReads(_calls) {
    _channel.closed.then((_) => _calls.retire());
  }

  final RemoteChannel _channel;
  final RemoteSessionCalls _calls;

  @override
  final RemoteDetachedReads detachedReads;

  /// The helper's operations as last read, and when (ms since epoch).
  OperationCenterSnapshot _operations = OperationCenterSnapshot.empty;
  var _operationsAtMs = 0;
  Future<OperationCenterSnapshot>? _reading;

  /// How long a quiet connection answers from its last read.
  static const _quietMs = 3000;

  /// How long after a write the helper is asked on every poll.
  static const _afterWriteMs = 10000;

  @override
  Future<OperationCenterSnapshot> operations() {
    if (!_channel.isOpen) return Future.value(OperationCenterSnapshot.empty);
    final now = DateTime.now().millisecondsSinceEpoch;
    final eager =
        _operations.runningCount > 0 || _calls.recentlyWrote(_afterWriteMs);
    if (!eager && now - _operationsAtMs < _quietMs) {
      return Future.value(_operations);
    }
    return _reading ??= _read(now).whenComplete(() => _reading = null);
  }

  Future<OperationCenterSnapshot> _read(int now) async {
    try {
      final native = await _calls.operationCenter();
      if (native != null) {
        _operations = operationCenterFromNative(
          native,
          backend: RepositoryBackendKind.remote,
        );
      }
    } on Object {
      // A lost connection keeps the last known state until it is gone.
    }
    _operationsAtMs = now;
    return _operations;
  }

  @override
  Future<void> dismissOperation(OperationCenterEntry entry) async {
    final session = entry.session;
    final activityId = entry.activityId;
    if (session == null || activityId == null) return;
    await _calls.dismissOperation(
      sessionId: session.nativeId,
      generation: BigInt.from(session.generation),
      activityId: activityId,
    );
    _operationsAtMs = 0;
  }

  @override
  final RepositorySessionRepository sessions;

  @override
  String? bindingOf(RepositorySessionIdentity session) =>
      _calls.bindingOf(session.nativeId);

  @override
  Future<RemotePendingOperation> lookup(RemotePendingOperation operation) =>
      _calls.lookup(operation);

  @override
  Future<void> initializeRepository({
    required List<int> path,
    required String initialBranch,
    required bool bare,
  }) => _calls.initializeRepository(
    path: path,
    initialBranch: initialBranch,
    bare: bare,
  );

  @override
  Future<RemoteDirectoryPage> listDirectory({
    List<int>? directory,
    String? cursor,
  }) async {
    final Object? reply;
    try {
      reply = await _channel.call('listDirectory', {
        'directory': directory == null ? null : wireBytes(directory),
        'cursor': cursor,
      });
    } on RemoteCallException catch (error) {
      throw RemoteWorkspaceException(switch (error.code) {
        RemoteErrorCode.pathInvalid => RemoteFailureCode.pathInvalid,
        RemoteErrorCode.pathNotFound => RemoteFailureCode.pathNotFound,
        RemoteErrorCode.permissionDenied => RemoteFailureCode.permissionDenied,
        RemoteErrorCode.notDirectory => RemoteFailureCode.notDirectory,
        RemoteErrorCode.cursorExpired => RemoteFailureCode.cursorExpired,
        RemoteErrorCode.directoryChanged => RemoteFailureCode.directoryChanged,
        RemoteErrorCode.disconnected => RemoteFailureCode.disconnected,
        RemoteErrorCode.timedOut => RemoteFailureCode.timedOut,
        RemoteErrorCode.capacity => RemoteFailureCode.capacity,
        RemoteErrorCode.unsupportedCommand => RemoteFailureCode.unsupported,
        _ => RemoteFailureCode.internal,
      });
    }
    try {
      final page = readWireObject(reply, 'listDirectory', const [
        'directory',
        'parent',
        'entries',
        'cursor',
        'truncated',
      ]);
      return RemoteDirectoryPage(
        directory: readWireBytes(page['directory']),
        parent: wireOptional(page['parent'], readWireBytes),
        entries: readWireList(page['entries'], (value) {
          final entry = readWireObject(value, 'entry', const [
            'name',
            'kind',
            'repository',
          ]);
          return RemoteDirectoryEntry(
            name: readWireBytes(entry['name']),
            kind: switch (readWireString(entry['kind'])) {
              'directory' => RemoteEntryKind.directory,
              'file' => RemoteEntryKind.file,
              'symlink' => RemoteEntryKind.symlink,
              _ => RemoteEntryKind.other,
            },
            repository: readWireBool(entry['repository']),
          );
        }),
        cursor: wireOptional(page['cursor'], readWireString),
        truncated: readWireBool(page['truncated']),
      );
    } on WireFormatException {
      throw const RemoteWorkspaceException(RemoteFailureCode.protocolViolation);
    }
  }
}

/// Sessions of the connection's calls that no tab owns. They share the
/// connection's workspace bindings, so a window opens the repository its tab
/// opened, and its immutable read cache.
final class _DetachedReads implements RemoteDetachedReads {
  _DetachedReads(this._calls);

  final RemoteSessionCalls _calls;

  @override
  Future<({BigInt? session, Object? result})> open(
    List<int> path,
    BigInt generation,
  ) async {
    final result = await _calls.repositorySessionOpenIdentity(
      identity: pathIdentityToNative(
        NativePathIdentity(platform: NativePathPlatform.unix, units: path),
      ),
      generation: generation,
    );
    return (
      session: result.session?.sessionId,
      result: encodeNativeRepositoryOpenResult(result),
    );
  }

  @override
  Future<Object?> read(
    BigInt session,
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (!remoteReadMethods.contains(method)) {
      _calls.unsupported(method);
    }
    return _calls.invokeRead(method, {
      ...arguments,
      'sessionId': wireBig(_calls.helperSession(session)),
    });
  }

  @override
  Future<void> close(BigInt session, BigInt generation) =>
      _calls.repositorySessionClose(sessionId: session, generation: generation);
}
