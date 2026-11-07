import 'dart:async';

import '../models/cli_forwarding.dart';
import '../models/settings.dart';
import '../repositories/cli_forwarding_repository.dart';
import '../repositories/application_open_repository.dart';
import 'repository_opener.dart';
import 'window_geometry_service.dart';

abstract interface class CliForwardingController {
  Stream<CliForwardedCommand> get commands;

  /// Starts serving forwarded commands for the window that shows them.
  void attach();

  /// Stops serving them when that window goes; [attach] resumes.
  void detach();
}

final class DisabledCliForwardingController implements CliForwardingController {
  const DisabledCliForwardingController();

  @override
  Stream<CliForwardedCommand> get commands => const Stream.empty();

  @override
  void attach() {}

  @override
  void detach() {}
}

final class CliForwardingService implements CliForwardingController {
  CliForwardingService(
    this._repository,
    this._sessions,
    this._window, {
    this.applicationOpen,
  });

  final ApplicationOpenRepository? applicationOpen;

  final CliForwardingRepository _repository;
  final RepositoryOpener _sessions;
  final WindowGeometryService _window;
  final StreamController<CliForwardedCommand> _commands =
      StreamController<CliForwardedCommand>.broadcast();
  Timer? _poller;
  bool _polling = false;
  bool _openingApplicationPaths = false;
  bool _disposed = false;

  @override
  Stream<CliForwardedCommand> get commands => _commands.stream;

  Future<void> initialize() async {
    final result = await _repository.ensureOwner();
    if (result.state != CliStartupState.owner) {
      throw CliForwardingException(
        result.failure ?? CliForwardingFailureCode.transport,
      );
    }
  }

  @override
  void attach() {
    if (_disposed || _poller != null) return;
    // A forwarded command comes from a terminal. A tenth of a second is
    // imperceptible there and spares the interface thread 30 polls a second.
    _poller = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_drain()),
    );
    unawaited(_drain());
  }

  @override
  void detach() {
    _poller?.cancel();
    _poller = null;
  }

  Future<void> _drain() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      if (!_openingApplicationPaths) {
        final paths = await applicationOpen?.takePaths() ?? const <String>[];
        if (!_disposed && paths.isNotEmpty) {
          unawaited(_openApplicationPaths(paths));
        }
      }
      for (var count = 0; count < 8; count += 1) {
        if (_disposed) return;
        final command = await _repository.poll();
        if (command == null) break;
        await _dispatch(command);
      }
    } on CliForwardingException {
      // The next bounded poll retries. No native detail enters diagnostics.
    } finally {
      _polling = false;
    }
  }

  Future<void> _openApplicationPaths(List<String> paths) async {
    _openingApplicationPaths = true;
    try {
      for (final path in paths) {
        if (_disposed) return;
        try {
          await _window.activate();
          if (_disposed) return;
          await _sessions.open(path);
        } on Object {
          // The regular repository state exposes the typed open failure.
          // A failed item must not prevent later paths from opening.
        }
      }
    } finally {
      _openingApplicationPaths = false;
    }
  }

  Future<void> _dispatch(CliForwardedCommand command) async {
    switch (command.kind) {
      case CliForwardedCommandKind.activate:
        await _accept(command);
        await _window.activate();
      case CliForwardedCommandKind.openRepository:
        final path = command.path;
        if (path == null) {
          await _respond(command, CliForwardingResponse.precondition);
          return;
        }
        await _accept(command);
        await _window.activate();
        unawaited(_open(path));
      case CliForwardedCommandKind.openRemoteRepository:
        // The window connects the host, with its dialogs.
        if (command.path == null ||
            command.remoteAlias == null ||
            !_commands.hasListener) {
          await _respond(command, CliForwardingResponse.precondition);
          return;
        }
        await _accept(command);
        await _window.activate();
        _commands.add(command);
      case CliForwardedCommandKind.refresh:
        if (_sessions.current == null) {
          await _respond(command, CliForwardingResponse.precondition);
          return;
        }
        await _accept(command);
        await _window.activate();
        unawaited(_sessions.refresh().catchError((_) {}));
      case CliForwardedCommandKind.fetch || CliForwardedCommandKind.pull:
        if (_sessions.current == null || !_commands.hasListener) {
          await _respond(command, CliForwardingResponse.precondition);
          return;
        }
        await _accept(command);
        await _window.activate();
        _commands.add(command);
    }
  }

  Future<void> _open(NativePathIdentity path) async {
    try {
      await _sessions.openRecent(path);
    } on Object {
      // The regular repository state exposes the typed open failure.
    }
  }

  Future<void> _accept(CliForwardedCommand command) =>
      _respond(command, CliForwardingResponse.accepted);

  Future<void> _respond(
    CliForwardedCommand command,
    CliForwardingResponse response,
  ) async {
    if (!await _repository.respond(command.requestId, response)) {
      throw const CliForwardingException(CliForwardingFailureCode.transport);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _poller?.cancel();
    await _commands.close();
    await _repository.dispose();
  }
}
