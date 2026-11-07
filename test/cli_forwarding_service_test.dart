import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/cli_forwarding.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/cli_forwarding_repository.dart';
import 'package:gitlama/repositories/application_open_repository.dart';
import 'package:gitlama/repositories/window_geometry_repository.dart';
import 'package:gitlama/services/cli_forwarding_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/services/window_geometry_service.dart';

import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

void main() {
  test(
    'OS paths wait for attachment and later batches open in order',
    () async {
      final native = _ForwardingRepository();
      final paths = _ApplicationOpenRepository()
        ..pending.addAll(['/work/first repository', '/work/second']);
      final sessions = fakeRepositorySessionService();
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final windowRepository = _WindowRepository();
      final window = WindowGeometryService(windowRepository, settings);
      await window.initialize();
      final service = CliForwardingService(
        native,
        sessions,
        window,
        applicationOpen: paths,
      );
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(paths.takes, 0);
      expect(sessions.workspace.tabs, isEmpty);

      service.attach();
      service.attach();
      await _waitFor(() => sessions.workspace.activeTab?.label == 'second');
      paths.pending.add('/work/日本語');
      await _waitFor(() => sessions.workspace.activeTab?.label == '日本語');
      expect(sessions.workspace.tabs.map((tab) => tab.label), [
        'first repository',
        'second',
        '日本語',
      ]);
      expect(windowRepository.activationCount, 3);
      expect(native.responses, isEmpty);

      await service.dispose();
      paths.pending.add('/work/after-dispose');
      final takes = paths.takes;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(paths.takes, takes);
      await sessions.dispose();
      await window.dispose();
      await settings.dispose();
    },
  );

  test('pending OS open does not block IPC and stops after disposal', () async {
    final native = _ForwardingRepository();
    final paths = _ApplicationOpenRepository()..pending.add('/work/pending');
    final sessions = fakeRepositorySessionService();
    final settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    final activation = Completer<void>();
    final windowRepository = _WindowRepository()
      ..activation = activation.future;
    final window = WindowGeometryService(windowRepository, settings);
    await window.initialize();
    final service = CliForwardingService(
      native,
      sessions,
      window,
      applicationOpen: paths,
    );
    await service.initialize();
    service.attach();
    await _waitFor(() => windowRepository.activationCount == 1);
    native.add(
      CliForwardedCommand(
        requestId: BigInt.one,
        kind: CliForwardedCommandKind.fetch,
      ),
    );
    await _waitFor(() => native.responses.isNotEmpty);
    expect(
      native.responses.single.response,
      CliForwardingResponse.precondition,
    );
    expect(sessions.workspace.tabs, isEmpty);
    await service.dispose();
    activation.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sessions.workspace.tabs, isEmpty);
    await sessions.dispose();
    await window.dispose();
    await settings.dispose();
  });

  test('bootstrap rejects a process that did not win ownership', () async {
    final native = _ForwardingRepository(
      startupState: CliStartupState.forwarded,
    );
    final sessions = fakeRepositorySessionService();
    final settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    final window = WindowGeometryService(_WindowRepository(), settings);
    await window.initialize();
    final service = CliForwardingService(native, sessions, window);

    await expectLater(
      service.initialize(),
      throwsA(
        isA<CliForwardingException>().having(
          (error) => error.code,
          'code',
          CliForwardingFailureCode.transport,
        ),
      ),
    );

    await service.dispose();
    await sessions.dispose();
    await window.dispose();
    await settings.dispose();
  });

  test(
    'forwarded commands share GUI preconditions and preserve pull policy',
    () async {
      final native = _ForwardingRepository();
      final sessions = fakeRepositorySessionService();
      final settings = SettingsService(FakeSettingsRepository());
      await settings.initialize();
      final windowRepository = _WindowRepository();
      final window = WindowGeometryService(windowRepository, settings);
      await window.initialize();
      final service = CliForwardingService(native, sessions, window);
      await service.initialize();

      service.attach();
      native.add(
        CliForwardedCommand(
          requestId: BigInt.one,
          kind: CliForwardedCommandKind.fetch,
        ),
      );
      await _waitFor(() => native.responses.length == 1);
      expect(
        native.responses.single.response,
        CliForwardingResponse.precondition,
      );

      await sessions.open('/repository');
      final received = <CliForwardedCommand>[];
      final subscription = service.commands.listen(received.add);
      native.add(
        CliForwardedCommand(
          requestId: BigInt.two,
          kind: CliForwardedCommandKind.pull,
          pullStrategy: CliPullStrategy.rebase,
        ),
      );
      await _waitFor(() => received.isNotEmpty);
      expect(native.responses.last.response, CliForwardingResponse.accepted);
      expect(received.single.pullStrategy, CliPullStrategy.rebase);
      expect(windowRepository.activationCount, 1);

      await subscription.cancel();
      await service.dispose();
      await sessions.dispose();
      await window.dispose();
      await settings.dispose();
    },
  );

  test('a remote open reaches a window, without one it is refused', () async {
    final native = _ForwardingRepository();
    final sessions = fakeRepositorySessionService();
    final settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    final windowRepository = _WindowRepository();
    final window = WindowGeometryService(windowRepository, settings);
    await window.initialize();
    final service = CliForwardingService(native, sessions, window);
    await service.initialize();
    service.attach();
    CliForwardedCommand remoteOpen(int id) => CliForwardedCommand(
      requestId: BigInt.from(id),
      kind: CliForwardedCommandKind.openRemoteRepository,
      remoteAlias: 'fedora',
      path: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: [47, 115, 114, 118],
      ),
    );

    native.add(remoteOpen(1));
    await _waitFor(() => native.responses.length == 1);
    expect(
      native.responses.single.response,
      CliForwardingResponse.precondition,
    );

    final received = <CliForwardedCommand>[];
    final subscription = service.commands.listen(received.add);
    native.add(remoteOpen(2));
    await _waitFor(() => received.isNotEmpty);
    expect(native.responses.last.response, CliForwardingResponse.accepted);
    expect(received.single.remoteAlias, 'fedora');
    expect(received.single.path?.units, [47, 115, 114, 118]);
    expect(windowRepository.activationCount, 1);
    // It opens nothing itself: the window connects the host first.
    expect(sessions.workspace.tabs, isEmpty);

    await subscription.cancel();
    await service.dispose();
    await sessions.dispose();
    await window.dispose();
    await settings.dispose();
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

final class _ForwardingRepository implements CliForwardingRepository {
  _ForwardingRepository({this.startupState = CliStartupState.owner});

  final CliStartupState startupState;
  final List<CliForwardedCommand> _pending = [];
  final List<({BigInt requestId, CliForwardingResponse response})> responses =
      [];

  void add(CliForwardedCommand command) => _pending.add(command);

  @override
  Future<CliStartupResult> prepareProcessInvocation() async =>
      const CliStartupResult(state: CliStartupState.owner);

  @override
  Future<CliStartupResult> ensureOwner() async =>
      CliStartupResult(state: startupState);

  @override
  Future<CliForwardedCommand?> poll() async =>
      _pending.isEmpty ? null : _pending.removeAt(0);

  @override
  Future<bool> respond(BigInt requestId, CliForwardingResponse response) async {
    responses.add((requestId: requestId, response: response));
    return true;
  }

  @override
  Future<void> dispose() async {}
}

final class _WindowRepository implements WindowGeometryRepository {
  int activationCount = 0;
  Future<void>? activation;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> restore(WindowGeometry? geometry) async {}

  @override
  Future<void> activate() async {
    activationCount += 1;
    await activation;
  }

  @override
  Future<WindowGeometry> read() async => const WindowGeometry(
    x: 0,
    y: 0,
    width: 900,
    height: 600,
    maximized: false,
  );

  @override
  Future<void> dispose() async {}
}

final class _ApplicationOpenRepository implements ApplicationOpenRepository {
  final pending = <String>[];
  var takes = 0;

  @override
  Future<List<String>> takePaths() async {
    takes += 1;
    final result = List<String>.of(pending);
    pending.clear();
    return result;
  }
}
