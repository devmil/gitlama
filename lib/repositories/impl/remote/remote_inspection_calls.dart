import 'dart:convert';

import '../../../models/remote_workspace.dart';
import '../../../models/repository_state.dart';
import '../../../rust/third_party/gitlama_contract/dto.dart';
import '../../../rust/third_party/gitlama_contract/domain/path_identity.dart'
    as native;
import '../repository_session_calls.g.dart';
import 'remote_inspection_channel.dart';
import 'wire_values.dart';

/// The repository session calls of an inspector window whose repository is
/// on a remote host: every read goes through the main window's connection,
/// in a session the main window opened for this window.
///
/// The session identifiers are the main window's for that session; the main
/// window addresses its helper session itself.
final class WindowRemoteInspectionCalls extends WireRepositorySessionCalls {
  WindowRemoteInspectionCalls(this._transport, {required this.authority});

  final RemoteInspectionTransport _transport;
  final RemoteAuthority authority;

  @override
  BigInt helperSession(BigInt sessionId) => sessionId;

  /// Every write family fails before anything is sent: an inspector window
  /// only reads.
  @override
  Object? noSuchMethod(Invocation invocation) => Future<Never>.error(
    const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
    ),
  );

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
    required native.NativePathIdentity identity,
    required BigInt generation,
  }) async {
    if (identity.platform != native.NativePathPlatform.unix) {
      return const NativeRepositoryOpenResult(
        failure: NativeRepositoryFailure(
          kind: NativeRepositoryFailureKind.invalidOptions,
        ),
      );
    }
    final result = await _send('open', {
      'repository': {
        'units': identity.units.toList(),
        'remote': authority.toMessage(),
      },
      'generation': generation.toString(),
    });
    try {
      return decodeNativeRepositoryOpenResult(result);
    } on WireFormatException {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
  }

  /// The window reads; the main window's session keeps no events for it.
  @override
  Future<NativeRepositoryEventsResult> repositorySessionEvents({
    required BigInt sessionId,
    required BigInt generation,
    required int maximumEvents,
  }) async => const NativeRepositoryEventsResult(events: <Never>[]);

  @override
  Future<NativeRepositoryCommandResult> repositorySessionClose({
    required BigInt sessionId,
    required BigInt generation,
  }) async {
    try {
      await _send('close', {
        'session': sessionId.toString(),
        'generation': generation.toString(),
      });
    } on RepositorySessionException {
      // The main window closes the window's sessions when it goes away.
    }
    return const NativeRepositoryCommandResult(accepted: true);
  }

  @override
  Future<Object?> invokeRead(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final session = arguments['sessionId'];
    if (session is! String) unsupported(method);
    return _send('read', {
      'session': session,
      'method': method,
      'arguments': arguments,
    });
  }

  Future<Object?> _send(String method, Map<String, Object?> body) async {
    final Object? reply;
    try {
      final window = await _transport.windowId();
      reply = await _transport.invoke(
        method,
        jsonEncode({
          'schema': remoteInspectionSchema,
          'window': window,
          ...body,
        }),
      );
    } on RepositorySessionException {
      rethrow;
    } on Object {
      // No main window answers: its connection is out of reach.
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.remoteDisconnected),
      );
    }
    final Object? data;
    try {
      data = reply is String ? jsonDecode(reply) : null;
    } on FormatException {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOutput),
      );
    }
    if (data is Map<String, Object?> && data.length == 1) {
      if (data.containsKey('result')) return data['result'];
      final name = data['failure'];
      final failure = RepositoryFailureCode.values
          .where((code) => code.name == name)
          .firstOrNull;
      if (failure != null) {
        throw RepositorySessionException(RepositoryFailure(failure));
      }
    }
    throw const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.invalidOutput),
    );
  }
}
