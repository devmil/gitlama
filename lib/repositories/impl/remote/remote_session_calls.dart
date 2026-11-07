import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../../models/remote_workspace.dart';
import '../../../models/repository_state.dart';
import '../../../rust/third_party/gitlama_contract/advanced_rebase.dart';
import '../../../rust/third_party/gitlama_contract/dto.dart';
import '../../../rust/third_party/gitlama_contract/conflict.dart';
import '../../../rust/third_party/gitlama_contract/extensions.dart';
import '../../../rust/third_party/gitlama_contract/history_operation.dart';
import '../../../rust/third_party/gitlama_contract/named_snapshot.dart';
import '../../../rust/third_party/gitlama_contract/power_tools.dart';
import '../../../rust/third_party/gitlama_contract/rebase_operation.dart';
import '../../../rust/third_party/gitlama_contract/stash.dart';
import '../../../rust/third_party/gitlama_contract/domain/path_identity.dart';
import '../../../rust/third_party/gitlama_contract/transfer.dart';
import '../../remote_connection_repository.dart';
import '../../remote_session_repository.dart';
import '../native_mappers.dart';
import '../repository_session_calls.g.dart';
import 'wire_values.dart';

/// Reads whose results depend only on their object identities and arguments
/// and leave no helper-side state behind. Their successful results are kept
/// locally; selection projections such as commit diffs are not.
const remoteImmutableReads = <String>{
  'repositorySessionCommitInspection',
  'repositorySessionTree',
  'repositorySessionCommitFileContent',
};

/// The largest patch sent to a host for applying; it travels inside one
/// request.
const remotePatchBytes = ContractLimits.patchBytes;

/// The local memory budget for immutable read results of one connection.
const remoteContentCacheBytes = 32 * 1024 * 1024;

/// Events kept per session between drains; older ones collapse.
const _maximumQueuedEvents = 1024;

/// Unknown-session publications kept until their open reply arrives.
const _maximumOrphanSessions = 8;
const _maximumOrphanBatches = 16;

final class _Session {
  _Session(this.helperId, this.generation, this.binding);

  final BigInt helperId;
  final BigInt generation;
  final String? binding;
  final events = <NativeRepositoryEvent>[];
  NativeRepositoryFailure? failure;
}

/// A helper preview of a write the core previewed too, kept by its family and
/// core token until it is executed.
final class _CorePreview {
  const _CorePreview({
    required this.helperSession,
    required this.generation,
    required this.token,
    required this.epoch,
    required this.digest,
    required this.binding,
    required this.summary,
  });

  final BigInt helperSession;
  final BigInt generation;
  final String token;
  final String epoch;
  final String digest;
  final String binding;
  final String summary;
}

/// The repository session calls of one remote helper connection.
///
/// Reads go through the generated wire encoding. Session lifecycle, events
/// and the write families are implemented here: events arrive as
/// publications and are drained locally; writes are recorded in the ledger
/// before Execute is sent and resolve from the helper's receipt.
final class RemoteSessionCalls extends WireRepositorySessionCalls {
  RemoteSessionCalls(
    this._channel, {
    required this.authority,
    required this._ledger,
    required BigInt Function() allocateSessionId,
    required this._expectedBinding,
    Random? random,
    int Function()? clock,
  }) : _allocate = allocateSessionId,
       _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _publications = _channel.publications.listen(_publish);
  }

  final RemoteChannel _channel;
  final RemoteAuthority authority;
  final RemoteOperationLedger _ledger;
  final BigInt Function() _allocate;
  final String? Function(List<int> path) _expectedBinding;
  final Random _random;
  final int Function() _clock;
  late final StreamSubscription<RemotePublication> _publications;
  final Map<BigInt, _Session> _sessions = {};
  final Map<BigInt, BigInt> _localByHelper = {};
  final Map<BigInt, List<NativeRepositoryEventsResult>> _orphans = {};

  /// Helper sessions this client closed; their late publications are dropped.
  final Set<BigInt> _closedHelperSessions = {};
  final Map<String, _CorePreview> _corePreviews = {};
  final _content = <String, ({Object? value, int bytes})>{};
  var _contentBytes = 0;

  bool get _writesStage =>
      _channel.helper.capabilities.contains(RemoteCapability.stage);
  bool get _writesCommit =>
      _channel.helper.capabilities.contains(RemoteCapability.commit);
  bool get _writesRefs =>
      _channel.helper.capabilities.contains(RemoteCapability.refs);
  bool get _writesStash =>
      _channel.helper.capabilities.contains(RemoteCapability.stash);
  bool get _writesTransfer =>
      _channel.helper.capabilities.contains(RemoteCapability.transfer);
  bool get _writesDiscard =>
      _channel.helper.capabilities.contains(RemoteCapability.discard);
  bool get _writesHistory =>
      _channel.helper.capabilities.contains(RemoteCapability.history);
  bool get _writesRecovery =>
      _channel.helper.capabilities.contains(RemoteCapability.recovery);
  bool get _writesExtensions =>
      _channel.helper.capabilities.contains(RemoteCapability.extensions);

  /// The binding of a local session, if it is live.
  String? bindingOf(BigInt sessionId) => _sessions[sessionId]?.binding;

  /// Writes sent and not yet answered, and when the last one started (ms):
  /// the operation center asks the helper often while either is recent.
  var _writesInFlight = 0;
  var _lastWriteAtMs = 0;

  /// Whether a write is running or started within [withinMs].
  bool recentlyWrote(int withinMs) =>
      _writesInFlight > 0 || _clock() - _lastWriteAtMs < withinMs;

  /// The helper's operation center, with entries of this connection's live
  /// sessions under their local session identifiers. Operations of other or
  /// closed sessions are dropped.
  Future<NativeOperationCenterSnapshot?> operationCenter({
    int maximumEntries = 64,
  }) async {
    final result = decodeNativeOperationCenterResult(
      await _call('operationCenter', {'maximumEntries': maximumEntries}),
    );
    final snapshot = result.snapshot;
    if (snapshot == null) return null;
    return NativeOperationCenterSnapshot(
      entries: [
        for (final entry in snapshot.entries)
          if (_localByHelper[entry.sessionId] case final local?)
            NativeOperationCenterEntry(
              activityId: entry.activityId,
              sessionId: local,
              cloneAttemptId: entry.cloneAttemptId,
              generation: entry.generation,
              state: entry.state,
              origin: entry.origin,
              action: entry.action,
              startedAtUnixMs: entry.startedAtUnixMs,
              finishedAtUnixMs: entry.finishedAtUnixMs,
              progress: entry.progress,
              // A remote operation is neither canceled nor retried from
              // here: an uncertain remote write is inspected, never resent.
              canCancel: false,
              canRetry: false,
              hasDetails: entry.hasDetails,
            ),
      ],
      runningCount: snapshot.runningCount,
      failedCount: snapshot.failedCount,
      warningCount: snapshot.warningCount,
      attentionCount: snapshot.attentionCount,
      truncated: snapshot.truncated,
    );
  }

  /// Dismisses a finished operation of local session [sessionId].
  Future<void> dismissOperation({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt activityId,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    await _call('operationDismiss', {
      'sessionId': wireBig(session.helperId),
      'generation': wireBig(generation),
      'activityId': wireBig(activityId),
    });
  }

  /// Creates a repository at the host [path] without opening it; see
  /// [RemoteSessionSurface.initializeRepository].
  Future<void> initializeRepository({
    required List<int> path,
    required String initialBranch,
    required bool bare,
  }) async {
    if (!_channel.helper.capabilities.contains(RemoteCapability.initialize)) {
      throw const RemoteWorkspaceException(RemoteFailureCode.writeNotPermitted);
    }
    final Object? reply;
    try {
      reply = await _channel.call('initializeRepository', {
        'path': wireBytes(path),
        'initialBranch': initialBranch,
        'bare': bare,
      });
    } on RemoteCallException catch (error) {
      throw RemoteWorkspaceException(switch (error.code) {
        RemoteErrorCode.writeNotPermitted =>
          RemoteFailureCode.writeNotPermitted,
        RemoteErrorCode.pathInvalid => RemoteFailureCode.pathInvalid,
        RemoteErrorCode.disconnected => RemoteFailureCode.disconnected,
        RemoteErrorCode.timedOut => RemoteFailureCode.timedOut,
        RemoteErrorCode.capacity => RemoteFailureCode.capacity,
        RemoteErrorCode.unsupportedCommand => RemoteFailureCode.unsupported,
        _ => RemoteFailureCode.internal,
      });
    }
    final NativeRepositoryFailureKind? failure;
    try {
      final result = readWireObject(reply, 'initializeRepository', const [
        'failure',
      ]);
      failure = wireOptional(
        result['failure'],
        decodeNativeRepositoryFailureKind,
      );
    } on WireFormatException {
      throw const RemoteWorkspaceException(RemoteFailureCode.protocolViolation);
    }
    if (failure != null) {
      throwRepositoryFailure(NativeRepositoryFailure(kind: failure));
    }
  }

  /// Stops event delivery after the channel closed.
  Future<void> retire() => _publications.cancel();

  void _publish(RemotePublication publication) {
    final NativeRepositoryEventsResult result;
    try {
      result = decodeNativeRepositoryEventsResult(publication.events);
    } on WireFormatException {
      return;
    }
    final local = _localByHelper[publication.sessionId];
    if (local == null) {
      if (_closedHelperSessions.contains(publication.sessionId)) return;
      // The open reply may still be on its way; keep a bounded backlog.
      if (_orphans.length >= _maximumOrphanSessions &&
          !_orphans.containsKey(publication.sessionId)) {
        return;
      }
      final backlog = _orphans[publication.sessionId] ??= [];
      if (backlog.length >= _maximumOrphanBatches) backlog.removeAt(0);
      backlog.add(result);
      return;
    }
    _queue(_sessions[local]!, result);
  }

  void _queue(_Session session, NativeRepositoryEventsResult result) {
    session.events.addAll(result.events);
    if (result.failure != null) session.failure = result.failure;
    if (session.events.length > _maximumQueuedEvents) {
      // Keep the newest snapshot as a resynchronization.
      final newest = session.events.lastWhere(
        (event) => event.snapshot != null,
        orElse: () => session.events.last,
      );
      session.events
        ..clear()
        ..add(
          NativeRepositoryEvent(
            kind: newest.snapshot == null
                ? newest.kind
                : NativeRepositoryEventKind.resynchronize,
            snapshot: newest.snapshot,
            readId: newest.readId,
            cacheHit: newest.cacheHit,
            watchOverflowRevision: newest.watchOverflowRevision,
          ),
        );
    }
  }

  @override
  Future<Object?> invokeRead(
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (!remoteImmutableReads.contains(method)) {
      return _call(method, arguments, bulk: remoteBulkMethods.contains(method));
    }
    final key = '$method ${jsonEncode(arguments)}';
    final cached = _content.remove(key);
    if (cached != null) {
      _content[key] = cached;
      return cached.value;
    }
    final value = await _call(method, arguments);
    if (value is Map<String, Object?> && value['failure'] == null) {
      final bytes = utf8.encode(jsonEncode(value)).length + key.length;
      if (bytes <= remoteContentCacheBytes ~/ 4) {
        _content[key] = (value: value, bytes: bytes);
        _contentBytes += bytes;
        while (_contentBytes > remoteContentCacheBytes) {
          final oldest = _content.keys.first;
          _contentBytes -= _content.remove(oldest)!.bytes;
        }
      }
    }
    return value;
  }

  Future<Object?> _call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) async {
    try {
      return await _channel.call(method, arguments, bulk: bulk);
    } on RemoteCallException catch (error) {
      throw RepositorySessionException(RepositoryFailure(_failure(error.code)));
    } on WireFormatException {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
  }

  static RepositoryFailureCode _failure(RemoteErrorCode code) => switch (code) {
    RemoteErrorCode.disconnected => RepositoryFailureCode.remoteDisconnected,
    RemoteErrorCode.timedOut => RepositoryFailureCode.timedOut,
    RemoteErrorCode.canceled => RepositoryFailureCode.canceled,
    RemoteErrorCode.capacity ||
    RemoteErrorCode.receiptCapacity => RepositoryFailureCode.capacity,
    RemoteErrorCode.unknownSession => RepositoryFailureCode.unknownSession,
    RemoteErrorCode.unsupportedCommand =>
      RepositoryFailureCode.remoteNotOffered,
    RemoteErrorCode.writeNotPermitted =>
      RepositoryFailureCode.remoteWriteNotPermitted,
    RemoteErrorCode.invalidRequest ||
    RemoteErrorCode.operationIdConflict => RepositoryFailureCode.invalidOptions,
    RemoteErrorCode.pathInvalid ||
    RemoteErrorCode.pathNotFound ||
    RemoteErrorCode.notDirectory => RepositoryFailureCode.pathNotFound,
    RemoteErrorCode.permissionDenied => RepositoryFailureCode.permissionDenied,
    RemoteErrorCode.identityMismatch =>
      RepositoryFailureCode.remoteIdentityChanged,
    RemoteErrorCode.previewExpired ||
    RemoteErrorCode.preconditionFailed ||
    RemoteErrorCode.admissionEpochRetired ||
    RemoteErrorCode.cursorExpired ||
    RemoteErrorCode.directoryChanged => RepositoryFailureCode.staleGeneration,
    RemoteErrorCode.storeUnavailable ||
    RemoteErrorCode.internal => RepositoryFailureCode.read,
  };

  @override
  BigInt helperSession(BigInt sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.unknownSession),
      );
    }
    return session.helperId;
  }

  @override
  Never unsupported(String method) => throw const RepositorySessionException(
    RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
  );

  @override
  Future<NativeRepositoryOpenResult> repositorySessionOpen({
    required String path,
    required BigInt generation,
  }) => unsupported('repositorySessionOpen');

  @override
  Future<NativeRepositoryOpenResult> repositorySessionOpenIdentity({
    required NativePathIdentity identity,
    required BigInt generation,
  }) async {
    if (identity.platform != NativePathPlatform.unix ||
        identity.units.any((unit) => unit > 0xff)) {
      return const NativeRepositoryOpenResult(
        failure: NativeRepositoryFailure(
          kind: NativeRepositoryFailureKind.invalidOptions,
        ),
      );
    }
    final path = Uint8List.fromList(identity.units);
    final reply = readWireObject(
      await _call('openRepository', {
        'path': wireBytes(path),
        'generation': wireBig(generation),
        'expectedBinding': _expectedBinding(path),
      }),
      'openRepository',
      const ['binding', 'open'],
    );
    final binding = wireOptional(reply['binding'], readWireString);
    final opened = decodeNativeRepositoryOpenResult(reply['open']);
    final session = opened.session;
    if (session == null) return opened;
    final local = _allocate();
    final state = _Session(session.sessionId, generation, binding);
    _sessions[local] = state;
    _localByHelper[session.sessionId] = local;
    _closedHelperSessions.remove(session.sessionId);
    for (final backlog
        in _orphans.remove(session.sessionId) ??
            const <NativeRepositoryEventsResult>[]) {
      _queue(state, backlog);
    }
    return NativeRepositoryOpenResult(
      session: NativeRepositorySession(
        sessionId: local,
        generation: session.generation,
        snapshot: session.snapshot,
      ),
      failure: opened.failure,
    );
  }

  @override
  Future<NativeRepositoryEventsResult> repositorySessionEvents({
    required BigInt sessionId,
    required BigInt generation,
    required int maximumEvents,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return const NativeRepositoryEventsResult(events: []);
    }
    final count = min(maximumEvents, session.events.length);
    final events = session.events.sublist(0, count);
    session.events.removeRange(0, count);
    final failure = session.failure;
    session.failure = null;
    return NativeRepositoryEventsResult(events: events, failure: failure);
  }

  @override
  Future<NativeRepositoryCommandResult> repositorySessionClose({
    required BigInt sessionId,
    required BigInt generation,
  }) async {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return const NativeRepositoryCommandResult(accepted: true);
    }
    _localByHelper.remove(session.helperId);
    _closedHelperSessions.add(session.helperId);
    _orphans.remove(session.helperId);
    final sessionKey = '"sessionId":"${session.helperId}"';
    _content.removeWhere((key, entry) {
      final remove = key.contains(sessionKey);
      if (remove) _contentBytes -= entry.bytes;
      return remove;
    });
    _corePreviews.removeWhere(
      (_, preview) => preview.helperSession == session.helperId,
    );
    if (!_channel.isOpen) {
      return const NativeRepositoryCommandResult(accepted: true);
    }
    try {
      return decodeNativeRepositoryCommandResult(
        await _call('closeRepository', {
          'sessionId': wireBig(session.helperId),
          'generation': wireBig(generation),
        }),
      );
    } on RepositorySessionException {
      // The helper closes every session when its connection ends.
      return const NativeRepositoryCommandResult(accepted: true);
    }
  }

  String _operationId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  RemoteOperationOutcome? _outcome(Object? value) => switch (value) {
    'succeeded' => RemoteOperationOutcome.succeeded,
    'failed' => RemoteOperationOutcome.failed,
    'notApplied' => RemoteOperationOutcome.notApplied,
    'desiredStateObserved' => RemoteOperationOutcome.desiredStateObserved,
    'partial' => RemoteOperationOutcome.partial,
    'unknown' => RemoteOperationOutcome.unknown,
    _ => null,
  };

  /// Whether [outcome] settles an operation: it is definite, or it ran and
  /// left work to finish, such as stash conflicts.
  static bool _known(RemoteOperationOutcome? outcome) =>
      outcome?.definite ?? false;

  /// Records [operation], sends [execute] and resolves the record from the
  /// helper's operation object. Returns the helper's result value, or throws
  /// [RemoteOutcomeUnknownException] when the outcome cannot be established.
  Future<Object?> _admit(
    RemotePendingOperation operation,
    String method,
    Map<String, Object?> arguments,
  ) async {
    // No Execute byte leaves before the intent is durable.
    await _ledger.record(operation);
    final Object? reply;
    _writesInFlight += 1;
    _lastWriteAtMs = _clock();
    try {
      // Hooks and signing run inside Execute: it gets the long deadline. A
      // deadline still leaves the outcome unknown rather than failed.
      reply = await _channel.call(method, {
        ...arguments,
        'operationId': operation.operationId,
      }, bulk: true);
    } on RemoteCallException catch (error) {
      final definite = switch (error.code) {
        RemoteErrorCode.previewExpired ||
        RemoteErrorCode.preconditionFailed ||
        RemoteErrorCode.admissionEpochRetired ||
        RemoteErrorCode.receiptCapacity ||
        RemoteErrorCode.writeNotPermitted ||
        RemoteErrorCode.invalidRequest ||
        RemoteErrorCode.unknownSession ||
        RemoteErrorCode.capacity => true,
        _ => false,
      };
      if (!definite) {
        // Lost transport, timeouts and store failures leave the outcome open.
        await _ledger.record(
          operation.stillPending(
            outcome: RemoteOperationOutcome.unknown,
            atMs: _clock(),
          ),
        );
        throw const RemoteOutcomeUnknownException();
      }
      await _ledger.record(
        operation.resolved(RemoteOperationOutcome.notApplied, atMs: _clock()),
      );
      // A preview the host no longer honours is a stale preview, as on this
      // computer: the family reports its stale state and nothing ran.
      if (error.code == RemoteErrorCode.previewExpired ||
          error.code == RemoteErrorCode.preconditionFailed) {
        return const _StaleWrite();
      }
      throw RepositorySessionException(RepositoryFailure(_failure(error.code)));
    } finally {
      _writesInFlight -= 1;
    }
    final object = readWireObject(reply, 'executed', const [
      'operation',
      'result',
    ]);
    final record = readWireObject(object['operation'], 'operation', const [
      'operationId',
      'epoch',
      'state',
      'outcome',
      'resultObjectId',
    ]);
    final outcome = _outcome(record['outcome']);
    final resultObjectId = wireOptional(
      record['resultObjectId'],
      readWireString,
    );
    final definite = _known(outcome);
    if (outcome != null && definite) {
      try {
        await _ledger.record(
          operation.resolved(
            outcome,
            resultObjectId: resultObjectId,
            atMs: _clock(),
          ),
        );
      } on Object {
        // The remote outcome stands; the local record stays pending and the
        // next lookup resolves it.
      }
    } else {
      await _ledger.record(
        operation.stillPending(outcome: outcome, atMs: _clock()),
      );
    }
    // A definite outcome stands even when its terminal receipt was not
    // durable (`terminal` false); anything else needs a later lookup.
    if (!definite) {
      throw const RemoteOutcomeUnknownException();
    }
    return object['result'];
  }

  RemotePendingOperation _operation({
    required RemoteOperationFamily family,
    required String epoch,
    required String digest,
    required String binding,
    required String summary,
  }) {
    final now = _clock();
    return RemotePendingOperation(
      operationId: _operationId(),
      epoch: epoch,
      digest: digest,
      family: family,
      authority: authority,
      binding: binding,
      pending: true,
      // The record counts Unicode scalar values, as the native ledger does.
      summary: String.fromCharCodes(
        summary.runes.take(ContractLimits.summaryCharacters),
      ),
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  @override
  Future<NativeStagingExecutionResult> repositorySessionStagingExecute({
    required BigInt sessionId,
    required BigInt generation,
    required NativeStagingRequest request,
  }) async {
    if (!_writesStage) unsupported('repositorySessionStagingExecute');
    final session = _sessions[sessionId];
    final binding = session?.binding;
    if (session == null || binding == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.unknownSession),
      );
    }
    final encoded = encodeNativeStagingRequest(request);
    final preview = readWireObject(
      await _call('previewStage', {
        'sessionId': wireBig(session.helperId),
        'generation': wireBig(generation),
        'request': encoded,
      }),
      'previewStage',
      const ['token', 'epoch', 'digest', 'expiresInMs'],
    );
    final epoch = readWireString(preview['epoch']);
    final digest = readWireString(preview['digest']);
    final result = await _admit(
      _operation(
        family: RemoteOperationFamily.stage,
        epoch: epoch,
        digest: digest,
        binding: binding,
        summary: request.side == NativeStagingSide.unstaged
            ? 'stage'
            : 'unstage',
      ),
      'executeStage',
      {
        'sessionId': wireBig(session.helperId),
        'generation': wireBig(generation),
        'token': readWireString(preview['token']),
        'epoch': epoch,
        'digest': digest,
        'request': encoded,
      },
    );
    if (result is _StaleWrite) {
      return const NativeStagingExecutionResult(
        state: NativeStagingExecutionState.stale,
      );
    }
    return result == null
        ? const NativeStagingExecutionResult(
            state: NativeStagingExecutionState.completed,
          )
        : decodeNativeStagingExecutionResult(result);
  }

  /// Previews a [family] write in the helper, which previews it in the core.
  /// Keeps the helper's token under the core's [coreTokenOf] the decoded
  /// preview, so the matching execute admits exactly this preview.
  Future<T> _previewWrite<T>({
    required BigInt sessionId,
    required BigInt generation,
    required RemoteOperationFamily family,
    required String method,
    required Map<String, Object?> request,
    required T Function(Object? value) decode,
    required BigInt? Function(T preview) coreTokenOf,
    required String summary,
  }) async {
    final session = _sessions[sessionId];
    final binding = session?.binding;
    if (session == null || binding == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.unknownSession),
      );
    }
    final reply = readWireObject(
      await _call(method, {
        'sessionId': wireBig(session.helperId),
        'generation': wireBig(generation),
        'request': request,
      }),
      method,
      const ['token', 'epoch', 'digest', 'expiresInMs', 'preview'],
    );
    final preview = decode(reply['preview']);
    final token = wireOptional(reply['token'], readWireString);
    final coreToken = coreTokenOf(preview);
    if (token != null && coreToken != null) {
      _corePreviews['${family.name}/$coreToken'] = _CorePreview(
        helperSession: session.helperId,
        generation: generation,
        token: token,
        epoch: readWireString(reply['epoch']),
        digest: readWireString(reply['digest']),
        binding: binding,
        summary: summary,
      );
    }
    return preview;
  }

  /// Admits the kept preview of [coreToken] and returns the helper's result,
  /// or null when no live preview matches: the caller reports it stale.
  Future<Object?> _executeWrite({
    required BigInt sessionId,
    required BigInt generation,
    required RemoteOperationFamily family,
    required String method,
    required BigInt coreToken,
  }) async {
    final preview = _corePreviews.remove('${family.name}/$coreToken');
    final session = _sessions[sessionId];
    if (preview == null ||
        session == null ||
        session.helperId != preview.helperSession) {
      return null;
    }
    return _admit(
      _operation(
        family: family,
        epoch: preview.epoch,
        digest: preview.digest,
        binding: preview.binding,
        summary: preview.summary,
      ),
      method,
      {
        'sessionId': wireBig(preview.helperSession),
        'generation': wireBig(generation),
        'token': preview.token,
        'epoch': preview.epoch,
        'digest': preview.digest,
      },
    );
  }

  @override
  Future<NativeCommitPreviewResult> repositorySessionCommitPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeCommitRequest request,
  }) async {
    if (!_writesCommit) unsupported('repositorySessionCommitPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.commit,
      method: 'previewCommit',
      request: encodeNativeCommitRequest(request),
      decode: decodeNativeCommitPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: request.subject,
    );
  }

  @override
  Future<NativeCommitExecutionResult> repositorySessionCommitExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesCommit) unsupported('repositorySessionCommitExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.commit,
      method: 'executeCommit',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeCommitExecutionResult(
            state: NativeCommitExecutionState.stale,
            output: [],
          )
        : decodeNativeCommitExecutionResult(result);
  }

  @override
  Future<NativeRefMutationPreviewResult> repositorySessionRefMutationPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeRefMutationRequest request,
  }) async {
    if (!_writesRefs) unsupported('repositorySessionRefMutationPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.refs,
      method: 'previewRefs',
      request: encodeNativeRefMutationRequest(request),
      decode: decodeNativeRefMutationPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: [?request.name, ?request.secondName].join(' \u2192 '),
    );
  }

  @override
  Future<NativeRefMutationExecutionResult> repositorySessionRefMutationExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesRefs) unsupported('repositorySessionRefMutationExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.refs,
      method: 'executeRefs',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeRefMutationExecutionResult(
            state: NativeRefMutationExecutionState.stale,
          )
        : decodeNativeRefMutationExecutionResult(result);
  }

  @override
  Future<NativeStashPreviewResult> repositorySessionStashPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeStashRequest request,
  }) async {
    if (!_writesStash) unsupported('repositorySessionStashPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.stash,
      method: 'previewStash',
      request: encodeNativeStashRequest(request),
      decode: decodeNativeStashPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: request.message ?? request.selector ?? '',
    );
  }

  @override
  Future<NativeStashExecutionResult> repositorySessionStashExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesStash) unsupported('repositorySessionStashExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.stash,
      method: 'executeStash',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeStashExecutionResult(
            state: NativeStashExecutionState.stale,
            activityIds: [],
            stashCreated: false,
            checkoutCompleted: false,
            reapplyCompleted: false,
            stashRetained: true,
          )
        : decodeNativeStashExecutionResult(result);
  }

  @override
  Future<NativeDiscardPreviewResult> repositorySessionDiscardPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeDiscardRequest request,
  }) async {
    if (!_writesDiscard) unsupported('repositorySessionDiscardPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.discard,
      method: 'previewDiscard',
      request: encodeNativeDiscardRequest(request),
      decode: decodeNativeDiscardPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: '',
    );
  }

  @override
  Future<NativeDiscardExecutionResult> repositorySessionDiscardExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesDiscard) unsupported('repositorySessionDiscardExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.discard,
      method: 'executeDiscard',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeDiscardExecutionResult(
            state: NativeDiscardExecutionState.stale,
          )
        : decodeNativeDiscardExecutionResult(result);
  }

  @override
  Future<NativeTransferPreviewResult> repositorySessionTransferPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeTransferRequest request,
  }) async {
    if (!_writesTransfer) unsupported('repositorySessionTransferPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.transfer,
      method: 'previewTransfer',
      request: encodeNativeTransferRequest(request),
      decode: decodeNativeTransferPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: [?request.remote, ?request.branch].join('/'),
    );
  }

  /// Runs on the host with its own Git credentials. Credentials entered here
  /// are never sent: the generated stub refuses that variant.
  @override
  Future<NativeTransferExecutionResult> repositorySessionTransferExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesTransfer) unsupported('repositorySessionTransferExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.transfer,
      method: 'executeTransfer',
      coreToken: token,
    );
    return result == null
        ? NativeTransferExecutionResult(
            state: NativeTransferExecutionState.stale,
            failure: const NativeTransferFailure(
              kind: NativeTransferFailureKind.stale,
            ),
            ahead: BigInt.zero,
            behind: BigInt.zero,
          )
        : decodeNativeTransferExecutionResult(result);
  }

  _Session _liveSession(BigInt sessionId) {
    final session = _sessions[sessionId];
    if (session == null || session.binding == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.unknownSession),
      );
    }
    return session;
  }

  /// Previews and admits a [family] write the core runs without a preview
  /// of its own (direct) or with a token it issued before (pass-through).
  /// A direct Execute carries [request] again; the helper checks it against
  /// the previewed digest.
  Future<Object?> _admitNow({
    required BigInt sessionId,
    required BigInt generation,
    required RemoteOperationFamily family,
    required String method,
    required Map<String, Object?> request,
    required String summary,
    bool direct = true,
  }) async {
    final session = _liveSession(sessionId);
    final preview = readWireObject(
      await _call('preview$method', {
        'sessionId': wireBig(session.helperId),
        'generation': wireBig(generation),
        'request': request,
      }),
      'preview$method',
      const ['token', 'epoch', 'digest', 'expiresInMs'],
    );
    final token = wireOptional(preview['token'], readWireString);
    if (token == null) return null;
    final epoch = readWireString(preview['epoch']);
    final digest = readWireString(preview['digest']);
    return _admit(
      _operation(
        family: family,
        epoch: epoch,
        digest: digest,
        binding: session.binding!,
        summary: summary,
      ),
      'execute$method',
      {
        'sessionId': wireBig(session.helperId),
        'generation': wireBig(generation),
        'token': token,
        'epoch': epoch,
        'digest': digest,
        'request': ?(direct ? request : null),
      },
    );
  }

  /// Drops a preview that was never executed. A remote write that already
  /// runs is never interrupted from here: it reports its own outcome.
  NativeRepositoryCommandResult _dropPreview(
    RemoteOperationFamily family,
    BigInt token,
  ) => NativeRepositoryCommandResult(
    accepted: _corePreviews.remove('${family.name}/$token') != null,
  );

  @override
  Future<NativeHistoryMutationPreviewResult>
  repositorySessionHistoryMutationPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeHistoryMutationRequest request,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionHistoryMutationPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.history,
      method: 'previewHistory',
      request: encodeNativeHistoryMutationRequest(request),
      decode: decodeNativeHistoryMutationPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: request.kind.name,
    );
  }

  @override
  Future<NativeHistoryMutationExecutionResult>
  repositorySessionHistoryMutationExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionHistoryMutationExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.history,
      method: 'executeHistory',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeHistoryMutationExecutionResult(
            state: NativeHistoryMutationExecutionState.stale,
            activityIds: [],
            conflictingPaths: [],
          )
        : decodeNativeHistoryMutationExecutionResult(result);
  }

  @override
  Future<NativeRepositoryCommandResult> repositorySessionHistoryMutationCancel({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async => _dropPreview(RemoteOperationFamily.history, token);

  @override
  Future<NativeRebasePreviewResult> repositorySessionRebasePreview({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
    required List<NativeRebaseInstruction> instructions,
    required bool acknowledgePublishedHistory,
    required bool applyAutosquash,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionRebasePreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.rebase,
      method: 'previewRebase',
      request: {
        'planToken': wireBig(token),
        'instructions': [
          for (final instruction in instructions)
            encodeNativeRebaseInstruction(instruction),
        ],
        'acknowledgePublishedHistory': acknowledgePublishedHistory,
        'applyAutosquash': applyAutosquash,
      },
      decode: decodeNativeRebasePreviewResult,
      coreTokenOf: (preview) => preview.token,
      summary: 'rebase',
    );
  }

  @override
  Future<NativeRebaseExecutionResult> repositorySessionRebaseExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionRebaseExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.rebase,
      method: 'executeRebase',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeRebaseExecutionResult(
            state: NativeRebaseExecutionState.stale,
            activityIds: [],
            conflictingPaths: [],
          )
        : decodeNativeRebaseExecutionResult(result);
  }

  @override
  Future<NativeRepositoryCommandResult> repositorySessionRebaseCancel({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async => _dropPreview(RemoteOperationFamily.rebase, token);

  @override
  Future<NativeRestackExecutionResult> repositorySessionRestackExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
    required bool acknowledgePublishedHistory,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionRestackExecute');
    final result = await _admitNow(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.restack,
      method: 'Restack',
      request: {
        'planToken': wireBig(token),
        'acknowledgePublishedHistory': acknowledgePublishedHistory,
      },
      summary: 'restack',
      direct: false,
    );
    return result == null || result is _StaleWrite
        ? const NativeRestackExecutionResult(
            state: NativeRestackExecutionState.stale,
            completedSteps: 0,
            totalSteps: 0,
            recoveryRefs: [],
            conflictingPaths: [],
            activityIds: [],
          )
        : decodeNativeRestackExecutionResult(result);
  }

  /// A restack runs on the host and reports its own outcome.
  @override
  Future<NativeRepositoryCommandResult> repositorySessionRestackCancel({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async => const NativeRepositoryCommandResult(accepted: false);

  @override
  Future<NativeBisectPreviewResult> repositorySessionBisectPreview({
    required BigInt sessionId,
    required BigInt generation,
    required NativeBisectAction action,
    String? good,
    String? bad,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionBisectPreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.bisect,
      method: 'previewBisect',
      request: {
        'action': encodeNativeBisectAction(action),
        'good': good,
        'bad': bad,
      },
      decode: decodeNativeBisectPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: action.name,
    );
  }

  @override
  Future<NativeBisectExecutionResult> repositorySessionBisectExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesHistory) unsupported('repositorySessionBisectExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.bisect,
      method: 'executeBisect',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeBisectExecutionResult(
            state: NativeBisectExecutionState.stale,
          )
        : decodeNativeBisectExecutionResult(result);
  }

  @override
  Future<NativeRepositoryCommandResult> repositorySessionBisectCancelPreview({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async => _dropPreview(RemoteOperationFamily.bisect, token);

  Future<NativeNamedSnapshotExecutionResult> _snapshot(
    BigInt sessionId,
    BigInt generation,
    Map<String, Object?> request,
    String summary,
  ) async {
    if (!_writesRecovery) unsupported('repositorySessionNamedSnapshot');
    final result = await _admitNow(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.snapshot,
      method: 'Snapshot',
      request: {
        'action': null,
        'name': null,
        'includeUntracked': false,
        'keepIndex': false,
        'snapshotId': null,
        'branch': null,
        ...request,
      },
      summary: summary,
    );
    return result == null || result is _StaleWrite
        ? const NativeNamedSnapshotExecutionResult(
            state: NativeNamedSnapshotExecutionState.stale,
            conflictingPaths: [],
            activityIds: [],
          )
        : decodeNativeNamedSnapshotExecutionResult(result);
  }

  @override
  Future<NativeNamedSnapshotExecutionResult>
  repositorySessionNamedSnapshotCreate({
    required BigInt sessionId,
    required BigInt generation,
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) => _snapshot(sessionId, generation, {
    'action': 'create',
    'name': name,
    'includeUntracked': includeUntracked,
    'keepIndex': keepIndex,
  }, name);

  @override
  Future<NativeNamedSnapshotExecutionResult>
  repositorySessionNamedSnapshotDelete({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt snapshotId,
  }) => _snapshot(sessionId, generation, {
    'action': 'delete',
    'snapshotId': wireBig(snapshotId),
  }, 'delete');

  @override
  Future<NativeNamedSnapshotExecutionResult>
  repositorySessionNamedSnapshotBranch({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt snapshotId,
    required List<int> branch,
  }) => _snapshot(sessionId, generation, {
    'action': 'branch',
    'snapshotId': wireBig(snapshotId),
    'branch': wireBytes(branch),
  }, utf8.decode(branch, allowMalformed: true));

  @override
  Future<NativeNamedSnapshotRestorePreviewResult>
  repositorySessionNamedSnapshotRestorePreview({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt snapshotId,
  }) async {
    if (!_writesRecovery) {
      unsupported('repositorySessionNamedSnapshotRestorePreview');
    }
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.snapshotRestore,
      method: 'previewSnapshotRestore',
      request: {'snapshotId': wireBig(snapshotId)},
      decode: decodeNativeNamedSnapshotRestorePreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: 'restore',
    );
  }

  @override
  Future<NativeNamedSnapshotExecutionResult>
  repositorySessionNamedSnapshotRestoreExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesRecovery) {
      unsupported('repositorySessionNamedSnapshotRestoreExecute');
    }
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.snapshotRestore,
      method: 'executeSnapshotRestore',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeNamedSnapshotExecutionResult(
            state: NativeNamedSnapshotExecutionState.stale,
            conflictingPaths: [],
            activityIds: [],
          )
        : decodeNativeNamedSnapshotExecutionResult(result);
  }

  @override
  Future<NativeRepositoryCommandResult>
  repositorySessionNamedSnapshotRestoreCancel({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async => _dropPreview(RemoteOperationFamily.snapshotRestore, token);

  @override
  Future<NativeRestorePreviewResult> repositorySessionRestorePreview({
    required BigInt sessionId,
    required BigInt generation,
    required String commit,
    required List<int> path,
    required int byteLimit,
  }) async {
    if (!_writesRecovery) unsupported('repositorySessionRestorePreview');
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.restore,
      method: 'previewRestore',
      request: {
        'commit': commit,
        'path': wireBytes(path),
        'byteLimit': byteLimit,
      },
      decode: decodeNativeRestorePreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: utf8.decode(path, allowMalformed: true),
    );
  }

  @override
  Future<NativeRestoreResult> repositorySessionRestoreFile({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesRecovery) unsupported('repositorySessionRestoreFile');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.restore,
      method: 'executeRestore',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativeRestoreResult(state: NativeRestoreState.stale)
        : decodeNativeRestoreResult(result);
  }

  @override
  Future<NativeIndexLockRemovalResult> repositorySessionRemoveIndexLock({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesRecovery) unsupported('repositorySessionRemoveIndexLock');
    final result = await _admitNow(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.indexLock,
      method: 'IndexLock',
      request: {'token': wireBig(token)},
      summary: 'index.lock',
      direct: false,
    );
    return result == null || result is _StaleWrite
        ? const NativeIndexLockRemovalResult(
            removed: false,
            failure: NativeIndexLockFailureKind.invalidToken,
          )
        : decodeNativeIndexLockRemovalResult(result);
  }

  /// Refs on a host are repaired there; a fetch without pruning still works.
  @override
  Future<NativeTransferExecutionResult> repositorySessionDeleteTrackingRefs({
    required BigInt sessionId,
    required BigInt generation,
    required List<String> references,
  }) async => unsupported('repositorySessionDeleteTrackingRefs');

  /// Lock files on a host are removed there; this computer only lists them.
  @override
  Future<NativeIndexLockRemovalResult> repositorySessionRemoveLock({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async => unsupported('repositorySessionRemoveLock');

  Future<NativeConflictSnapshotResult> _conflict(
    BigInt sessionId,
    BigInt generation,
    Map<String, Object?> request,
    List<int> path,
  ) async {
    if (!_writesHistory) unsupported('repositorySessionConflict');
    final result = await _admitNow(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.conflict,
      method: 'Conflict',
      request: {
        'path': wireBytes(path),
        'expectedFingerprint': null,
        'side': null,
        'regionIndex': null,
        'region': null,
        'result': null,
        ...request,
      },
      summary: utf8.decode(path, allowMalformed: true),
    );
    return result == null || result is _StaleWrite
        ? const NativeConflictSnapshotResult(activityIds: [])
        : decodeNativeConflictSnapshotResult(result);
  }

  @override
  Future<NativeConflictSnapshotResult> repositorySessionConflictChooseSide({
    required BigInt sessionId,
    required BigInt generation,
    required List<int> path,
    required BigInt expectedFingerprint,
    required NativeConflictSideChoice choice,
  }) => _conflict(sessionId, generation, {
    'action': 'chooseSide',
    'expectedFingerprint': wireBig(expectedFingerprint),
    'side': encodeNativeConflictSideChoice(choice),
  }, path);

  @override
  Future<NativeConflictSnapshotResult> repositorySessionConflictTakeRegion({
    required BigInt sessionId,
    required BigInt generation,
    required List<int> path,
    required BigInt expectedFingerprint,
    required int regionIndex,
    required NativeConflictRegionChoice choice,
  }) => _conflict(sessionId, generation, {
    'action': 'takeRegion',
    'expectedFingerprint': wireBig(expectedFingerprint),
    'regionIndex': regionIndex,
    'region': encodeNativeConflictRegionChoice(choice),
  }, path);

  @override
  Future<NativeConflictSnapshotResult> repositorySessionConflictSaveResult({
    required BigInt sessionId,
    required BigInt generation,
    required List<int> path,
    required BigInt expectedFingerprint,
    required List<int> result,
  }) => _conflict(sessionId, generation, {
    'action': 'saveResult',
    'expectedFingerprint': wireBig(expectedFingerprint),
    'result': wireBytes(result),
  }, path);

  @override
  Future<NativeConflictSnapshotResult> repositorySessionConflictUndoResolution({
    required BigInt sessionId,
    required BigInt generation,
    required List<int> path,
  }) => _conflict(sessionId, generation, {'action': 'undoResolution'}, path);

  Future<NativeConflictContinuationResult> _sequencer(
    BigInt sessionId,
    BigInt generation,
    NativeConflictSequencerAction action,
    String? message,
  ) async {
    if (!_writesHistory) unsupported('repositorySessionConflictContinue');
    final result = await _admitNow(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.sequencer,
      method: 'Sequencer',
      request: {
        'action': encodeNativeConflictSequencerAction(action),
        'message': message,
      },
      summary: message ?? action.name,
    );
    return result == null || result is _StaleWrite
        ? const NativeConflictContinuationResult(
            state: NativeConflictContinuationState.failed,
            activityIds: [],
          )
        : decodeNativeConflictContinuationResult(result);
  }

  @override
  Future<NativeConflictContinuationResult> repositorySessionConflictContinue({
    required BigInt sessionId,
    required BigInt generation,
    required NativeConflictSequencerAction action,
  }) => _sequencer(sessionId, generation, action, null);

  @override
  Future<NativeConflictContinuationResult>
  repositorySessionConflictContinueWithMessage({
    required BigInt sessionId,
    required BigInt generation,
    required NativeConflictSequencerAction action,
    required String message,
  }) => _sequencer(sessionId, generation, action, message);

  /// Reads the patch on this computer and hands its bytes to the host, which
  /// keeps a private copy until it applied it.
  @override
  Future<NativePatchApplyPreviewResult> repositorySessionPatchApplyPreview({
    required BigInt sessionId,
    required BigInt generation,
    required String patchPath,
  }) async {
    if (!_writesRecovery) unsupported('repositorySessionPatchApplyPreview');
    const invalid = NativePatchApplyPreviewResult(
      failure: NativeRepositoryFailure(
        kind: NativeRepositoryFailureKind.invalidOptions,
      ),
    );
    final Uint8List content;
    try {
      final file = File(patchPath);
      if (!file.isAbsolute || await file.length() > remotePatchBytes) {
        return invalid;
      }
      content = await file.readAsBytes();
    } on FileSystemException {
      return const NativePatchApplyPreviewResult(
        failure: NativeRepositoryFailure(
          kind: NativeRepositoryFailureKind.read,
        ),
      );
    }
    if (content.isEmpty || content.length > remotePatchBytes) return invalid;
    return _previewWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.patch,
      method: 'previewPatch',
      request: {'content': wireBytes(content)},
      decode: decodeNativePatchApplyPreviewResult,
      coreTokenOf: (preview) => preview.preview?.token,
      summary: File(patchPath).uri.pathSegments.lastOrNull ?? 'patch',
    );
  }

  @override
  Future<NativePatchApplyExecutionResult> repositorySessionPatchApplyExecute({
    required BigInt sessionId,
    required BigInt generation,
    required BigInt token,
  }) async {
    if (!_writesRecovery) unsupported('repositorySessionPatchApplyExecute');
    final result = await _executeWrite(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.patch,
      method: 'executePatch',
      coreToken: token,
    );
    return result == null || result is _StaleWrite
        ? const NativePatchApplyExecutionResult(
            state: NativePatchApplyExecutionState.stale,
          )
        : decodeNativePatchApplyExecutionResult(result);
  }

  /// Worktree roots name paths on the host: their remote authority is this
  /// computer's notion and is not sent.
  @override
  Future<NativeExtensionMutationResult> repositorySessionExtensionExecute({
    required BigInt sessionId,
    required BigInt generation,
    required NativeExtensionMutationRequest request,
  }) async {
    if (!_writesExtensions) unsupported('repositorySessionExtensionExecute');
    final root = request.worktreeRoot;
    final result = await _admitNow(
      sessionId: sessionId,
      generation: generation,
      family: RemoteOperationFamily.extension,
      method: 'Extension',
      request: encodeNativeExtensionMutationRequest(
        NativeExtensionMutationRequest(
          kind: request.kind,
          path: request.path,
          worktreeRoot: root == null
              ? null
              : NativePathIdentity(platform: root.platform, units: root.units),
          pattern: request.pattern,
          reference: request.reference,
        ),
      ),
      summary: request.kind.name,
    );
    return result == null || result is _StaleWrite
        ? const NativeExtensionMutationResult(
            state: NativeExtensionMutationState.failed,
            activityIds: [],
          )
        : decodeNativeExtensionMutationResult(result);
  }

  /// Reads the helper's receipt of [operation].
  Future<RemotePendingOperation> lookup(
    RemotePendingOperation operation,
  ) async {
    final reply = readWireObject(
      await _call('lookupOperation', {
        'epoch': operation.epoch,
        'operationId': operation.operationId,
        'digest': operation.digest,
      }),
      'lookupOperation',
      const ['operation'],
    );
    final record = readWireObject(reply['operation'], 'operation', const [
      'operationId',
      'epoch',
      'state',
      'outcome',
      'resultObjectId',
    ]);
    final outcome = _outcome(record['outcome']);
    final resultObjectId = wireOptional(
      record['resultObjectId'],
      readWireString,
    );
    final definite = record['state'] == 'terminal' && _known(outcome);
    // A dead owner's Prepared receipt is proven not applied.
    final notStarted =
        record['state'] == 'prepared' &&
        outcome == RemoteOperationOutcome.notApplied;
    if (definite || notStarted) {
      return operation.resolved(
        outcome!,
        resultObjectId: resultObjectId,
        atMs: _clock(),
      );
    }
    return operation.stillPending(
      outcome: record['outcome'] == 'running' ? null : outcome,
      atMs: _clock(),
    );
  }
}

/// What [RemoteSessionCalls._admit] returns when the host refused a write
/// because its preview expired or its preconditions changed.
final class _StaleWrite {
  const _StaleWrite();
}
