import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/cli_forwarding.dart';
import 'package:gitlama/models/clone_attempt.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/directory_picker_repository.dart';
import 'package:gitlama/services/cli_forwarding_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/workflows/entry_workflows.dart';

import '../support/workflow_fake_repository.dart';

final class _Cli implements CliForwardingController {
  final StreamController<CliForwardedCommand> controller =
      StreamController<CliForwardedCommand>.broadcast(sync: true);
  var attached = 0;
  var detached = 0;

  @override
  Stream<CliForwardedCommand> get commands => controller.stream;

  @override
  void attach() => attached += 1;

  @override
  void detach() => detached += 1;
}

final class _Picker implements DirectoryPickerRepository {
  @override
  Future<String?> chooseSaveFile({
    required String suggestedName,
    required String extension,
  }) async => null;

  _Picker(this.path);

  String? path;
  var asked = 0;

  @override
  Future<String?> chooseDirectory({required bool canCreateDirectories}) async {
    asked += 1;
    return path;
  }

  @override
  Future<String?> choosePatchFile() async => null;
}

final class _Interaction implements EntryInteraction {
  @override
  bool active = true;
  String? source;

  @override
  Future<String?> chooseCloneSource() async => source;

  @override
  Future<({String? profileId, bool bare})?> chooseInitialize({
    required bool initiallyBare,
  }) async => null;

  @override
  Future<RepositorySessionState?> initializeOnHost(
    String profileId, {
    required bool bare,
  }) async => null;

  @override
  Future<({String? username, String secret})?> cloneCredentials() async => null;

  @override
  Future<bool> trustHostKey(HostKeyChallenge challenge) async => false;
}

void main() {
  late _Cli cli;
  late _Picker picker;
  late RepositorySessionService repositories;
  late EntryWorkflowService entry;

  setUp(() {
    cli = _Cli();
    picker = _Picker(null);
    repositories = RepositorySessionService(
      WorkflowFakeRepository(
        RepositorySnapshot(revision: BigInt.one, phase: RepositoryPhase.ready),
      ),
      null,
      picker,
    );
    entry = EntryWorkflowService(repositories, cli);
  });

  tearDown(() async {
    await entry.dispose();
    await repositories.dispose();
    await cli.controller.close();
  });

  test(
    'the window serves forwarded commands for as long as it lives',
    () async {
      expect(cli.attached, 1);
      final received = <BigInt>[];
      entry.forwardedCommands.listen(
        (command) => received.add(command.requestId),
      );
      cli.controller.add(
        CliForwardedCommand(
          requestId: BigInt.one,
          kind: CliForwardedCommandKind.fetch,
        ),
      );
      cli.controller.add(
        CliForwardedCommand(
          requestId: BigInt.two,
          kind: CliForwardedCommandKind.pull,
        ),
      );
      // Each command arrives once; nothing replays it later.
      expect(received, [BigInt.one, BigInt.two]);
      await entry.dispose();
      expect(cli.detached, 1);
    },
  );

  test('a cancelled choice opens nothing and fails nothing', () async {
    await entry.open();
    expect(picker.asked, 1);
    expect(entry.current.busy, isFalse);
    expect(entry.current.failure, isNull);
  });

  test('a failed open is kept until the next attempt', () async {
    final states = <EntryState>[];
    entry.states.listen(states.add);
    await entry.run(
      () async => throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.notRepository),
      ),
    );
    expect(entry.current.failure, RepositoryFailureCode.notRepository);
    expect(entry.current.busy, isFalse);
    expect(states.first.busy, isTrue);
    await entry.run(() async => null);
    expect(entry.current.failure, isNull);
  });

  test('one entry action runs at a time', () async {
    final gate = Completer<RepositorySessionState?>();
    final first = entry.run(() => gate.future);
    var second = false;
    await entry.run(() async {
      second = true;
      return null;
    });
    expect(second, isFalse);
    gate.complete(null);
    await first;
  });

  test('cancelling the clone source clones nothing', () async {
    final interaction = _Interaction();
    await entry.clone(interaction);
    expect(entry.current.busy, isFalse);
    expect(entry.current.cloneFailure, isNull);
  });
}
