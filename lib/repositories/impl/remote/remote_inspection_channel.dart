import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../models/remote_workspace.dart';
import '../../../models/repository_state.dart';
import '../../../models/settings.dart';
import '../../remote_inspection_host_repository.dart';
import 'wire_values.dart';

/// The window channel between inspector windows and the main window's remote
/// connections. The main window handles it; inspector windows invoke it.
///
/// Every request and reply is one JSON text. A request names the calling
/// window; a reply carries either `result`, a wire value of the remote read
/// surface, or `failure`, a [RepositoryFailureCode] name. No message text,
/// path or content of a failure crosses the channel.
const remoteInspectionChannelName = 'gitlama/remote-inspection';

/// The envelope schema of every request.
const remoteInspectionSchema = 1;

/// The largest request text: read arguments are small, a selection patch
/// names its rows.
const _maximumRequestLength = 4 * 1024 * 1024;

/// Main window: serves [remoteInspectionChannelName] and reports the open
/// windows.
final class NativeRemoteInspectionHostRepository
    implements RemoteInspectionHostRepository {
  static const _channel = WindowMethodChannel(
    remoteInspectionChannelName,
    mode: ChannelMode.unidirectional,
  );

  RemoteInspectionServer? _server;
  bool _listening = false;
  final _windows = StreamController<Set<String>>.broadcast();
  StreamSubscription<Set<String>>? _windowChanges;

  @override
  Future<void> serve(RemoteInspectionServer server) async {
    _server = server;
    _listening = true;
    await _channel.setMethodCallHandler(_handle);
    // Windows are followed only once the plugin answers.
    _windowChanges = onWindowsChanged
        .asyncMap(
          (_) async => {
            for (final window in await WindowController.getAll())
              window.windowId,
          },
        )
        .listen(
          _windows.add,
          // A failed listing closes nothing; the next change lists again.
          onError: (Object _) {},
        );
  }

  Future<String> _handle(MethodCall call) async {
    final server = _server;
    if (server == null) return _reply(RepositoryFailureCode.closed);
    return answer(server, call);
  }

  /// Answers one call of an inspector window with [server]: the envelope
  /// the channel carries in both directions.
  @visibleForTesting
  static Future<String> answer(
    RemoteInspectionServer server,
    MethodCall call,
  ) async {
    final request = _decodeRequest(call.arguments);
    if (request == null) return _reply(RepositoryFailureCode.invalidOptions);
    final window = request['window'] as String;
    try {
      switch (call.method) {
        case 'open':
          final repository = _repositoryOf(request['repository']);
          final generation = _bigOf(request['generation']);
          if (repository == null || generation == null) break;
          return _result(await server.open(window, repository, generation));
        case 'read':
          final session = _bigOf(request['session']);
          final method = request['method'];
          final arguments = request['arguments'];
          if (session == null ||
              method is! String ||
              arguments is! Map<String, Object?>) {
            break;
          }
          return _result(await server.read(window, session, method, arguments));
        case 'close':
          final session = _bigOf(request['session']);
          final generation = _bigOf(request['generation']);
          if (session == null || generation == null) break;
          await server.close(window, session, generation);
          return _result(true);
      }
      return _reply(RepositoryFailureCode.invalidOptions);
    } on RepositorySessionException catch (error) {
      return _reply(error.failure.code);
    } on WireFormatException {
      return _reply(RepositoryFailureCode.invalidOutput);
    } on Object {
      return _reply(RepositoryFailureCode.read);
    }
  }

  @override
  Stream<Set<String>> get openWindows => _windows.stream;

  @override
  Future<void> dispose() async {
    _server = null;
    final changes = _windowChanges;
    _windowChanges = null;
    try {
      await changes?.cancel();
    } on Object {
      // The engine is going away.
    }
    await _windows.close();
    if (!_listening) return;
    _listening = false;
    try {
      await _channel.setMethodCallHandler(null);
    } on Object {
      // The engine is going away.
    }
  }

  static Map<String, Object?>? _decodeRequest(Object? value) {
    if (value is! String || value.isEmpty) return null;
    if (value.length > _maximumRequestLength) return null;
    try {
      final data = jsonDecode(value);
      if (data is! Map<String, Object?> ||
          data['schema'] != remoteInspectionSchema) {
        return null;
      }
      final window = data['window'];
      if (window is! String || window.isEmpty || window.length > 64) {
        return null;
      }
      return data;
    } on FormatException {
      return null;
    }
  }

  static NativePathIdentity? _repositoryOf(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final units = value['units'];
    final remote = remoteAuthorityFromMessage(value['remote']);
    if (remote == null || units is! List || units.any((unit) => unit is! int)) {
      return null;
    }
    final repository = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: units.cast<int>(),
      remote: remote,
    );
    return repository.isValidLocation ? repository : null;
  }

  static BigInt? _bigOf(Object? value) {
    if (value is! String || value.length > 20) return null;
    final parsed = BigInt.tryParse(value);
    return parsed == null || parsed.isNegative ? null : parsed;
  }

  static String _result(Object? value) => jsonEncode({'result': value});

  static String _reply(RepositoryFailureCode code) =>
      jsonEncode({'failure': code.name});
}

/// How an inspector window reaches [remoteInspectionChannelName].
abstract interface class RemoteInspectionTransport {
  /// The calling window's identifier.
  Future<String> windowId();

  /// Sends [payload] as [method]; returns the reply text.
  Future<Object?> invoke(String method, String payload);
}

/// The inspector window's side of the window channel.
final class WindowChannelRemoteInspectionTransport
    implements RemoteInspectionTransport {
  static const _channel = WindowMethodChannel(
    remoteInspectionChannelName,
    mode: ChannelMode.unidirectional,
  );

  Future<String>? _windowId;

  @override
  Future<String> windowId() =>
      _windowId ??= WindowController.fromCurrentEngine()
          .then((controller) => controller.windowId)
          .catchError((Object error) {
            _windowId = null;
            throw error;
          });

  @override
  Future<Object?> invoke(String method, String payload) =>
      _channel.invokeMethod<Object?>(method, payload);
}
