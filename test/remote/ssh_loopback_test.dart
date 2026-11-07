@Tags(['ssh'])
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_factory.dart';
import 'package:gitlama/repositories/impl/remote/ssh_remote_connection_repository.dart';
import 'package:gitlama/repositories/remote_session_repository.dart';
import 'package:gitlama/rust/frb_generated.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/remote_workspace_service.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_directory.dart';
import 'package:gitlama/repositories/impl/repository_backend_router.dart';
import 'package:gitlama/services/settings_service.dart';

import '../support/fake_settings_repository.dart';

/// Runs only inside `scripts/verify_remote_workspaces.py --ssh-loopback`,
/// which starts a loopback sshd fixture and passes it here. Without it the
/// tests fail rather than skip.
String _fixture(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('run through scripts/verify_remote_workspaces.py');
  }
  return value;
}

/// Where the services publish ready connections for the routers.
final _directory = LiveRemoteSessions();

final class _NoLocalRepository implements RepositorySessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('remote_session_reached_local_backend');
}

final class _MemoryPending implements RemotePendingRepository {
  List<RemotePendingOperation> saved = const [];

  @override
  Future<List<RemotePendingOperation>> load() async => saved;

  @override
  Future<void> save(List<RemotePendingOperation> operations) async {
    saved = List.of(operations);
  }
}

void main() {
  late String config;
  late String buildId;
  late Directory repository;
  late SettingsService settings;

  // On macOS and Linux the core owns the SSH processes.
  setUpAll(() async {
    final library = Platform.environment['GITLAMA_NATIVE_LIBRARY'];
    if (library != null && !Platform.isWindows) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    }
  });

  setUp(() async {
    config = _fixture('GITLAMA_SSH_FIXTURE_CONFIG');
    buildId = _fixture('GITLAMA_SSH_FIXTURE_BUILD_ID');
    repository = Directory(_fixture('GITLAMA_SSH_FIXTURE_REPOSITORY'));
    settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
  });

  tearDown(() => settings.dispose());

  Future<RemoteWorkspaceService> service(
    String helperBuild, {
    RemoteHelperLoader? helper,
  }) async {
    final remote = RemoteWorkspaceService(
      SshRemoteConnectionRepository(
        helperBuild,
        qualificationConfig: config,
        helperLoader: helper,
      ),
      const WireRemoteSessionFactory(),
      _MemoryPending(),
      settings,
      directory: _directory,
    );
    await remote.initialize();
    return remote;
  }

  // Runs first: the lane removes the helper so this client installs it.
  test('a missing helper is installed through SSH and then connects', () async {
    final bytes = File(
      _fixture('GITLAMA_SSH_FIXTURE_HELPER'),
    ).readAsBytesSync();
    final remote = await service(
      buildId,
      helper: (target) async => RemoteHelperArtifact(
        buildId: buildId,
        target: target,
        sha256: sha256.convert(bytes).toString(),
        bytes: bytes,
      ),
    );
    addTearDown(remote.dispose);
    final profile = await remote.saveProfile(
      label: 'Loopback',
      alias: 'gitlama-loopback',
    );
    final missing = await remote.connect(profile.id);
    expect(missing.failure, RemoteFailureCode.helperNotInstalled);
    final target = remote.hostTarget(profile.id);
    expect(target, isNotNull, reason: 'the missing line names the host');
    final artifact = await remote.bundledHelper(target!);
    expect(artifact, isNotNull);
    final installed = await remote.installHelper(profile.id, artifact!);
    expect(installed.ready, isTrue, reason: '${installed.failure}');
    await remote.disconnect(profile.id);

    // A damaged upload is refused and leaves the working helper in place.
    final damaged = await remote.installHelper(
      profile.id,
      RemoteHelperArtifact(
        buildId: buildId,
        target: target,
        sha256: sha256.convert(bytes).toString(),
        bytes: [...bytes.take(bytes.length - 1), bytes.last ^ 1],
      ),
    );
    expect(damaged.failure, RemoteFailureCode.installDigest);
    expect((await remote.connect(profile.id)).ready, isTrue);
  });

  test(
    'the installed OpenSSH client reaches the helper through the fixed launch',
    () async {
      final remote = await service(buildId);
      addTearDown(remote.dispose);
      final profile = await remote.saveProfile(
        label: 'Loopback',
        alias: 'gitlama-loopback',
      );
      final first = await remote.connect(profile.id);
      expect(
        first.phase,
        RemoteConnectionPhase.ready,
        reason: '${first.failure}',
      );
      await remote.setWritesAllowed(profile.id, true);
      await remote.disconnect(profile.id);
      final connected = await remote.connect(profile.id);
      expect(connected.ready, isTrue);
      final authority = remote.profile(profile.id)!.authority!;
      final router = RepositoryBackendRouter(_NoLocalRepository(), _directory);
      final opened = await router.openIdentity(
        NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: utf8.encode(repository.path),
          remote: authority,
        ),
        1,
      );
      final history = await router.loadHistory(
        opened.identity,
        complete: true,
        maximumRows: 64,
      );
      expect(history.totalRows, greaterThan(0));
      final diff = await router.workingDiff(
        opened.identity,
        side: StagingSide.unstaged,
      );
      final staged = await router.executeStaging(
        opened.identity,
        StagingRequest(
          requestId: diff.requestId,
          side: StagingSide.unstaged,
          scope: StagingScope.all,
        ),
      );
      expect(staged.state, StagingExecutionState.completed);
      final preview = await router.previewCommit(
        opened.identity,
        const CommitRequest(subject: 'Committed over SSH'),
      );
      final committed = await router.executeCommit(
        opened.identity,
        preview.token,
      );
      expect(committed.state, CommitExecutionState.completed);
      expect(remote.operations.where((op) => op.pending), isEmpty);
      expect(await router.close(opened.identity), isTrue);
    },
  );

  test(
    'a repeated selection at 150 ms RTT is served without a round trip',
    () async {
      final remote = await service(buildId);
      addTearDown(remote.dispose);
      final profile = await remote.saveProfile(
        label: 'Far away',
        alias: 'gitlama-rtt150',
      );
      expect((await remote.connect(profile.id)).ready, isTrue);
      final authority = remote.profile(profile.id)!.authority!;
      final router = RepositoryBackendRouter(_NoLocalRepository(), _directory);
      final opened = await router.openIdentity(
        NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: utf8.encode(repository.path),
          remote: authority,
        ),
        1,
      );
      final history = await router.loadHistory(
        opened.identity,
        complete: true,
        maximumRows: 8,
      );
      final commit = history.rows
          .map((row) => row.objectId)
          .firstWhere((id) => id.length == 40);
      final first = Stopwatch()..start();
      await router.inspectCommit(opened.identity, commit: commit);
      first.stop();
      final repeated = Stopwatch()..start();
      await router.inspectCommit(opened.identity, commit: commit);
      repeated.stop();
      expect(first.elapsedMilliseconds, greaterThanOrEqualTo(150));
      expect(repeated.elapsedMilliseconds, lessThan(100));
    },
  );

  test(
    'a helper that is not installed for this build is reported as such',
    () async {
      final remote = await service('f' * 40);
      addTearDown(remote.dispose);
      final profile = await remote.saveProfile(
        label: 'Loopback',
        alias: 'gitlama-loopback',
      );
      final state = await remote.connect(profile.id);
      expect(state.phase, RemoteConnectionPhase.failed);
      expect(state.failure, RemoteFailureCode.helperNotInstalled);
    },
  );

  test('an untrusted host key fails without trusting it', () async {
    final knownHosts = File(_fixture('GITLAMA_SSH_FIXTURE_UNTRUSTED_HOSTS'));
    final before = knownHosts.readAsBytesSync();
    final remote = await service(buildId);
    addTearDown(remote.dispose);
    final profile = await remote.saveProfile(
      label: 'Untrusted',
      alias: 'gitlama-untrusted',
    );
    final state = await remote.connect(profile.id);
    expect(state.phase, RemoteConnectionPhase.failed);
    expect(state.failure, RemoteFailureCode.sshConnectionFailed);
    expect(knownHosts.readAsBytesSync(), before);
  });
}
