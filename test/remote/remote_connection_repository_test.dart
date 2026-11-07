import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/impl/remote/local_helper_connection_repository.dart';
import 'package:gitlama/repositories/impl/remote/remote_process.dart';
import 'package:gitlama/repositories/impl/remote/ssh_command.dart';
import 'package:gitlama/repositories/impl/remote/ssh_remote_connection_repository.dart';

import 'support/fake_remote_process.dart';
import 'support/fake_timers.dart';

Future<Object?> _inline(Object? Function() work) async => work();

Matcher _fails(RemoteFailureCode code) => throwsA(
  isA<RemoteWorkspaceException>().having((e) => e.code, 'code', code),
);

void main() {
  late FakeTimers timers;
  late FakeRemoteProcess helper;
  late List<(String, List<String>, Map<String, String>?)> starts;

  setUp(() {
    timers = FakeTimers();
    helper = FakeRemoteProcess();
    starts = [];
  });

  Future<RemoteProcess> starter(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    starts.add((executable, arguments, environment));
    return helper;
  }

  SshRemoteConnectionRepository ssh({
    String? executable = '/usr/bin/ssh',
    String? version = 'OpenSSH_9.6p1 Ubuntu',
    ProcessStarter? start,
  }) => SshRemoteConnectionRepository(
    testBuildId,
    starter: start ?? starter,
    resolveExecutable: () => executable,
    versionReader: (_) async => version,
    timer: timers.call,
    offload: _inline,
  );

  test('opens over ssh with the fixed arguments and reports phases', () async {
    final phases = <RemoteConnectionPhase>[];
    final opening = ssh().open(
      alias: 'devbox',
      capabilities: {RemoteCapability.read},
      onPhase: phases.add,
    );
    await settle();
    expect(starts.single.$1, '/usr/bin/ssh');
    expect(starts.single.$2, sshArguments('devbox', testBuildId));
    helper.emitJson(helloJson());
    final channel = await opening;
    expect(channel.isOpen, isTrue);
    expect(channel.helper.capabilities, {RemoteCapability.read});
    expect(phases, [
      RemoteConnectionPhase.connecting,
      RemoteConnectionPhase.handshaking,
    ]);
  });

  test('missing, failing and old OpenSSH clients are typed', () async {
    await expectLater(
      ssh(executable: null).open(alias: 'devbox', capabilities: const {}),
      _fails(RemoteFailureCode.sshUnavailable),
    );
    await expectLater(
      ssh(version: null).open(alias: 'devbox', capabilities: const {}),
      _fails(RemoteFailureCode.sshUnavailable),
    );
    await expectLater(
      ssh(
        version: 'OpenSSH_8.2p1',
      ).open(alias: 'devbox', capabilities: const {}),
      _fails(RemoteFailureCode.sshUnsupported),
    );
    await expectLater(
      ssh(
        start: (executable, arguments, {environment}) =>
            throw const ProcessException('ssh', []),
      ).open(alias: 'devbox', capabilities: const {}),
      _fails(RemoteFailureCode.sshUnavailable),
    );
    expect(starts, isEmpty);
  });

  test('an invalid alias never starts a process', () async {
    await expectLater(
      ssh().open(alias: '-oProxyCommand=x', capabilities: const {}),
      _fails(RemoteFailureCode.unsupported),
    );
    expect(starts, isEmpty);
  });

  test('cancel during the handshake terminates and throws canceled', () async {
    final cancel = Completer<void>();
    final opening = ssh().open(
      alias: 'devbox',
      capabilities: const {},
      cancel: cancel.future,
    );
    await settle();
    expect(starts, hasLength(1));
    cancel.complete();
    await expectLater(opening, _fails(RemoteFailureCode.canceled));
    await settle();
    expect(helper.terminateCalls, 1);
  });

  test('cancel before the start never hands out a channel', () async {
    final opening = ssh().open(
      alias: 'devbox',
      capabilities: const {},
      cancel: Future<void>.value(),
    );
    await expectLater(opening, _fails(RemoteFailureCode.canceled));
  });

  test('rejects an invalid build id', () {
    expect(() => SshRemoteConnectionRepository('main'), throwsArgumentError);
    expect(
      () => LocalHelperConnectionRepository('/x', 'ABC'),
      throwsArgumentError,
    );
  });

  test('local helper starts the binary with --stdio', () async {
    final repository = LocalHelperConnectionRepository(
      '/opt/helper/gitlama-remote-helper',
      testBuildId,
      environment: const {'HOME': '/tmp/home'},
      starter: starter,
      timer: timers.call,
      offload: _inline,
    );
    final opening = repository.open(alias: 'ignored', capabilities: const {});
    await settle();
    expect(starts.single.$1, '/opt/helper/gitlama-remote-helper');
    expect(starts.single.$2, ['--stdio']);
    expect(starts.single.$3, {'HOME': '/tmp/home'});
    helper.emitJson(helloJson());
    expect((await opening).isOpen, isTrue);
  });
}
