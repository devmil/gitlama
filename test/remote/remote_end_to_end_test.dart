@Tags(['remote'])
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/diff_renderer.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/patch.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/repositories/impl/native_repository_session_repository.dart';
import 'package:gitlama/repositories/impl/remote/local_helper_connection_repository.dart';
import 'package:gitlama/repositories/impl/remote/remote_inspection_calls.dart';
import 'package:gitlama/repositories/impl/remote/remote_inspection_channel.dart';
import 'package:gitlama/repositories/impl/remote/remote_inspection_session_repository.dart';
import 'package:gitlama/repositories/remote_inspection_host_repository.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_factory.dart';
import 'package:gitlama/repositories/remote_session_repository.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/inspector/inspector_window_session.dart';
import 'package:gitlama/services/remote_inspection_host_service.dart';
import 'package:gitlama/services/remote_workspace_service.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_directory.dart';
import 'package:gitlama/repositories/impl/repository_backend_router.dart';
import 'package:gitlama/services/settings_service.dart';

import '../support/fake_settings_repository.dart';

/// The helper `cargo test -p gitlama-remote-helper` builds, in the target
/// directory CI may redirect. This lane runs after it; a missing helper
/// fails rather than skips.
final _helper = File('${_cargoTargetRoot()}/debug/gitlama-remote-helper');

String _cargoTargetRoot() {
  final root = Directory.current.path;
  final configured = Platform.environment['CARGO_TARGET_DIR'];
  if (configured == null || configured.isEmpty) return '$root/rust-core/target';
  return Directory(configured).isAbsolute ? configured : '$root/$configured';
}

/// Remote sessions must never reach the local backend.
/// Where the services publish ready connections for the routers.
final _directory = LiveRemoteSessions();

final class _NoLocalRepository implements RepositorySessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('remote_session_reached_local_backend');
}

/// This computer's part of content a remote host reads: it records what
/// arrived instead of decoding, comparing, rendering or saving it.
final class _RecordingDetached
    implements
        RepositorySessionRepository,
        ChangeSourceRepositorySessionRepository,
        PatchRepositorySessionRepository {
  final List<ChangeSourceBytes> images = [];
  final List<ChangeSourceBytes> diffTools = [];
  final List<List<int>> rendererInputs = [];
  final List<PatchExportContent> patches = [];
  final List<BigInt> executed = [];

  @override
  Future<ImageDiffContent> decodeImage(ChangeSourceBytes source) async {
    images.add(source);
    return const ImageDiffContent();
  }

  @override
  Future<IntegrationPreview> previewDetachedDiffTool(
    ChangeSourceBytes source,
    IntegrationDefinition definition,
  ) async {
    diffTools.add(source);
    return IntegrationPreview(
      token: BigInt.from(41),
      kind: IntegrationKind.diffTool,
      definitionId: definition.id,
      executable: 'diff-tool',
      arguments: const [],
      explicitShell: false,
      waitsForExit: true,
      requiresConfirmation: false,
    );
  }

  @override
  Future<IntegrationExecutionResult> executeDetachedIntegration(
    BigInt token, {
    required bool confirmed,
  }) async {
    executed.add(token);
    return const IntegrationExecutionResult(
      state: IntegrationExecutionState.completed,
    );
  }

  @override
  Future<DiffRendererPreview> previewDetachedDiffRenderer(
    RepositorySessionIdentity source,
    List<int> input,
    DiffRendererDefinition definition,
  ) async {
    rendererInputs.add(input);
    throw const DiffRendererException(DiffRendererFailureCode.unavailable);
  }

  @override
  Future<PatchExportPreview> previewPatchSave(
    PatchExportContent content, {
    required String destinationDirectory,
    required bool overwrite,
  }) async {
    patches.add(content);
    return PatchExportPreview(
      token: BigInt.one,
      scope: content.scope,
      format: content.format,
      filename: content.filename,
      destination: '$destinationDirectory/${content.filename}',
      byteCount: content.bytes.length,
      requiresOverwrite: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('remote_session_reached_local_backend');
}

/// No window opens or closes during a test.
final class _NoWindows implements RemoteInspectionHostRepository {
  @override
  Future<void> serve(RemoteInspectionServer server) async {}

  @override
  Stream<Set<String>> get openWindows => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

/// An inspector window's calls, answered by the main window through the
/// channel's envelope.
final class _ThroughMainWindow implements RemoteInspectionTransport {
  _ThroughMainWindow(this.server);

  final RemoteInspectionServer server;

  @override
  Future<String> windowId() async => '2';

  @override
  Future<Object?> invoke(String method, String payload) =>
      NativeRemoteInspectionHostRepository.answer(
        server,
        MethodCall(method, payload),
      );
}

final class _MemoryPending implements RemotePendingRepository {
  List<RemotePendingOperation> saved = const [];
  var saves = 0;

  @override
  Future<List<RemotePendingOperation>> load() async => saved;

  @override
  Future<void> save(List<RemotePendingOperation> operations) async {
    saves += 1;
    saved = List.of(operations);
  }
}

Future<String> _git(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    [
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      '-c',
      'commit.gpgsign=false',
      '-c',
      'init.defaultBranch=main',
      ...arguments,
    ],
    workingDirectory: directory.path,
    environment: const {'GIT_CONFIG_NOSYSTEM': '1'},
  );
  if (result.exitCode != 0) throw StateError('git ${arguments.first} failed');
  return (result.stdout as String).trim();
}

void main() {
  late Directory home;
  late Directory repository;
  late String buildId;
  late SettingsService settings;
  late _MemoryPending pending;
  late RemoteWorkspaceService remote;
  late RepositoryBackendRouter router;
  late _RecordingDetached detached;

  setUp(() async {
    expect(
      _helper.existsSync(),
      isTrue,
      reason: 'build the helper with cargo test -p gitlama-remote-helper',
    );
    final version = await Process.run(_helper.path, ['--version']);
    buildId =
        (jsonDecode(version.stdout as String)
                as Map<String, Object?>)['buildId']
            as String;
    home = (await Directory.systemTemp.createTemp(
      'gitlama-remote-e2e-',
    )).absolute;
    home = Directory(home.resolveSymbolicLinksSync());
    repository = Directory('${home.path}/project')..createSync();
    await _git(repository, ['init', '-q']);
    await _git(repository, ['config', 'user.name', 'Remote Person']);
    await _git(repository, ['config', 'user.email', 'remote@example.invalid']);
    await _git(repository, ['config', 'commit.gpgsign', 'false']);
    File('${repository.path}/README.md').writeAsStringSync('hello\n');
    await _git(repository, ['add', '.']);
    await _git(repository, ['commit', '-qm', 'initial']);
    File('${repository.path}/README.md').writeAsStringSync('hello\nremote\n');
    settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    pending = _MemoryPending();
    remote = RemoteWorkspaceService(
      LocalHelperConnectionRepository(
        _helper.path,
        buildId,
        environment: {'HOME': home.path},
      ),
      const WireRemoteSessionFactory(),
      pending,
      settings,
      directory: _directory,
    );
    await remote.initialize();
    router = RepositoryBackendRouter(_NoLocalRepository(), _directory);
    detached = _RecordingDetached();
  });

  tearDown(() async {
    await remote.dispose();
    await settings.dispose();
    await home.delete(recursive: true);
  });

  Future<RemoteAuthority> connect({bool writes = false}) async {
    final profile = await remote.saveProfile(
      label: 'Workstation',
      alias: 'local',
    );
    final first = await remote.connect(profile.id);
    expect(first.phase, RemoteConnectionPhase.ready);
    if (!writes) return remote.profile(profile.id)!.authority!;
    await remote.setWritesAllowed(profile.id, true);
    await remote.disconnect(profile.id);
    final second = await remote.connect(profile.id);
    expect(second.helper!.capabilities, contains(RemoteCapability.commit));
    return remote.profile(profile.id)!.authority!;
  }

  NativePathIdentity remoteIdentity(RemoteAuthority authority) =>
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: utf8.encode(repository.path),
        remote: authority,
      );

  Future<RepositorySnapshot> settle(
    RepositorySessionIdentity session,
    RepositorySnapshot initial,
  ) async {
    var snapshot = initial;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (snapshot.status == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final event in await router.events(session)) {
        if (event.snapshot != null) snapshot = event.snapshot!;
      }
    }
    return snapshot;
  }

  test(
    'a remote repository browses through the helper with its authority',
    () async {
      final authority = await connect();
      expect(remote.profiles.single.verified?.storeId, hasLength(32));
      final opened = await router.openIdentity(remoteIdentity(authority), 1);
      expect(opened.identity.backend, RepositoryBackendKind.remote);
      expect(opened.identity.nativeId >= remoteSessionIdBase, isTrue);
      expect(opened.snapshot.identity!.worktreeRoot.remote, authority);
      final snapshot = await settle(opened.identity, opened.snapshot);
      expect(snapshot.identity!.worktreeRoot.remote, authority);
      expect(
        snapshot.status!.entries.map((entry) => utf8.decode(entry.path.units)),
        contains('README.md'),
      );
      final history = await router.loadHistory(
        opened.identity,
        complete: true,
        maximumRows: 32,
      );
      // The commit plus the row of uncommitted changes.
      expect(history.totalRows, 2);
      final diff = await router.workingDiff(
        opened.identity,
        side: StagingSide.unstaged,
      );
      expect(diff.rows, isNotEmpty);
      // Mutations outside the negotiated surface never reach the helper.
      await expectLater(
        router.previewDiscard(
          opened.identity,
          const DiscardRequest(
            kind: DiscardKind.discard,
            scope: DiscardScope.files,
          ),
        ),
        throwsA(
          isA<RepositorySessionException>().having(
            (error) => error.failure.code,
            'code',
            RepositoryFailureCode.remoteNotOffered,
          ),
        ),
      );
      await expectLater(
        router.executeStaging(
          opened.identity,
          StagingRequest(
            requestId: diff.requestId,
            side: StagingSide.unstaged,
            scope: StagingScope.files,
            paths: [utf8.encode('README.md')],
          ),
        ),
        throwsA(isA<RepositorySessionException>()),
      );
      expect(
        await _git(repository, ['diff', '--cached', '--name-only']),
        isEmpty,
      );
      expect(await router.close(opened.identity), isTrue);
    },
  );

  test('an inspector window reads the host through the main window', () async {
    final authority = await connect();
    // The tab opened the repository, so its binding is known.
    final tab = await router.openIdentity(remoteIdentity(authority), 1);
    final host = RemoteInspectionHostService(
      _NoWindows(),
      (authority) => _directory.surfaceFor(authority)?.detachedReads,
    );
    await host.initialize();
    final head = await _git(repository, ['rev-parse', 'HEAD']);
    final reads = NativeRepositorySessionRepository.remote(
      WindowRemoteInspectionCalls(
        _ThroughMainWindow(host),
        authority: authority,
      ),
      authority: authority,
    );
    final window = InspectorWindowSession(
      RemoteInspectionSessionRepository(reads, reads, detached),
      InspectionWindowRequest(
        repository: remoteIdentity(authority),
        location: InspectorLocation(
          target: CommitTarget(head),
          path: utf8.encode('README.md'),
          lens: InspectorLens.blame,
        ),
      ),
    );
    await window.initialize();
    expect(window.failed, isFalse);
    final state = window.inspector.current;
    expect(state.failureCode, isNull);
    expect(state.inspection?.detail.commit, head);
    await window.inspector.ensureBlameIndex(0);
    expect(window.inspector.blameRowAt(0)?.commit, head);
    expect(host.sessionCount, 1);
    // The window's session is its own: the tab closes without it.
    expect(await router.close(tab.identity), isTrue);
    await window.inspector.navigate(
      InspectorLocation(target: CommitTarget(head)),
    );
    expect(window.inspector.current.inspection?.files, isNotEmpty);
    await window.close();
    expect(host.sessionCount, 0);
    await host.dispose();
  });

  test(
    'staging and a normal commit are recorded before and after they run',
    () async {
      final authority = await connect(writes: true);
      final opened = await router.openIdentity(remoteIdentity(authority), 1);
      await settle(opened.identity, opened.snapshot);
      final diff = await router.workingDiff(
        opened.identity,
        side: StagingSide.unstaged,
      );
      final staged = await router.executeStaging(
        opened.identity,
        StagingRequest(
          requestId: diff.requestId,
          side: StagingSide.unstaged,
          scope: StagingScope.files,
          paths: [utf8.encode('README.md')],
        ),
      );
      expect(staged.state, StagingExecutionState.completed);
      expect(await router.stagingPhase(opened.identity), StagingPhase.idle);
      expect(
        await _git(repository, ['diff', '--cached', '--name-only']),
        'README.md',
      );
      final preview = await router.previewCommit(
        opened.identity,
        const CommitRequest(subject: 'Remote commit'),
      );
      final committed = await router.executeCommit(
        opened.identity,
        preview.token,
      );
      expect(committed.state, CommitExecutionState.completed);
      final head = await _git(repository, ['rev-parse', 'HEAD']);
      expect(committed.commit, head);
      expect(
        await _git(repository, ['log', '-1', '--format=%an']),
        'Remote Person',
      );
      final operations = remote.operations;
      expect(operations, hasLength(2));
      expect(operations.every((operation) => !operation.pending), isTrue);
      expect(operations.last.family, RemoteOperationFamily.commit);
      expect(operations.last.outcome, RemoteOperationOutcome.succeeded);
      expect(operations.last.resultObjectId, head);
      expect(operations.last.summary, 'Remote commit');
      // Every operation was saved before Execute and again when it resolved.
      expect(pending.saves, 4);
      // An amend replaces the commit on the host, under the same family.
      final parent = await _git(repository, ['rev-parse', 'HEAD~1']);
      final amendPreview = await router.previewCommit(
        opened.identity,
        const CommitRequest(subject: 'Remote commit, amended', amend: true),
      );
      final amended = await router.executeCommit(
        opened.identity,
        amendPreview.token,
      );
      expect(amended.state, CommitExecutionState.completed);
      expect(await _git(repository, ['rev-parse', 'HEAD~1']), parent);
      expect(
        await _git(repository, ['log', '-1', '--format=%s']),
        'Remote commit, amended',
      );
      expect(remote.operations.last.summary, 'Remote commit, amended');
      expect(remote.operations.last.outcome, RemoteOperationOutcome.succeeded);
    },
  );

  test(
    'branches, stashes and pushes run on the host under their own families',
    () async {
      final bare = '${home.path}/origin.git';
      await _git(home, ['init', '-q', '--bare', bare]);
      await _git(repository, ['remote', 'add', 'origin', bare]);
      final authority = await connect(writes: true);
      final opened = await router.openIdentity(remoteIdentity(authority), 1);
      await settle(opened.identity, opened.snapshot);
      final head = await _git(repository, ['rev-parse', 'HEAD']);

      final branch = await router.previewRefMutation(
        opened.identity,
        RefMutationRequest(
          kind: RefMutationKind.createBranch,
          name: 'feature',
          target: head,
          checkout: true,
        ),
      );
      final created = await router.executeRefMutation(
        opened.identity,
        branch.token,
      );
      expect(created.state, RefMutationExecutionState.completed);
      expect(
        await _git(repository, ['symbolic-ref', 'HEAD']),
        'refs/heads/feature',
      );

      final stash = await router.previewStash(
        opened.identity,
        const StashRequest(kind: StashKind.push, message: 'remote stash'),
      );
      final stashed = await router.executeStash(opened.identity, stash.token);
      expect(stashed.state, StashExecutionState.completed);
      expect(await _git(repository, ['stash', 'list']), contains('remote'));
      expect(await _git(repository, ['status', '--porcelain']), isEmpty);

      final push = await router.previewTransfer(
        opened.identity,
        const TransferRequest(
          kind: TransferKind.push,
          remote: 'origin',
          branch: 'feature',
          setUpstream: true,
        ),
      );
      final pushed = await router.executeTransfer(opened.identity, push.token);
      expect(pushed.state, TransferExecutionState.completed);
      expect(
        await _git(Directory(bare), ['rev-parse', 'feature']),
        await _git(repository, ['rev-parse', 'HEAD']),
      );
      // Credentials entered on this computer are never sent to the host.
      final again = await router.previewTransfer(
        opened.identity,
        const TransferRequest(kind: TransferKind.fetch, remote: 'origin'),
      );
      await expectLater(
        router.executeTransfer(
          opened.identity,
          again.token,
          credentials: const TransferCredentials(password: 'secret'),
        ),
        throwsA(isA<RepositorySessionException>()),
      );

      expect(remote.operations.map((operation) => operation.family), [
        RemoteOperationFamily.refs,
        RemoteOperationFamily.stash,
        RemoteOperationFamily.transfer,
      ]);
      expect(
        remote.operations.every((operation) => !operation.pending),
        isTrue,
      );
      expect(
        remote.operations.every(
          (operation) => operation.outcome == RemoteOperationOutcome.succeeded,
        ),
        isTrue,
      );
    },
  );

  test(
    'a lost connection keeps tabs bound and reconnect needs the user',
    () async {
      final authority = await connect();
      final opened = await router.openIdentity(remoteIdentity(authority), 1);
      final profileId = authority.profileId;
      final states = <RemoteConnectionPhase>[];
      final subscription = remote.states.listen(
        (state) => states.add(state.phase),
      );
      await remote.disconnect(profileId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(remote.isLive(authority), isFalse);
      expect(router.isLiveRemote(opened.identity), isTrue);
      await expectLater(
        router.loadHistory(opened.identity, complete: true),
        throwsA(isA<RepositorySessionException>()),
      );
      // Nothing reconnects by itself.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(remote.state(profileId).ready, isFalse);
      final again = await remote.connect(profileId);
      expect(again.ready, isTrue);
      final reopened = await router.openIdentity(remoteIdentity(authority), 2);
      expect(reopened.identity.nativeId, isNot(opened.identity.nativeId));
      await subscription.cancel();
      expect(states, contains(RemoteConnectionPhase.disconnecting));
    },
  );

  test('a changed helper store is never attached silently', () async {
    final authority = await connect();
    await remote.disconnect(authority.profileId);
    Directory('${home.path}/.local/state/gitlama').deleteSync(recursive: true);
    final changed = await remote.connect(authority.profileId);
    expect(changed.phase, RemoteConnectionPhase.identityChanged);
    expect(remote.isLive(authority), isFalse);
    await expectLater(
      router.openIdentity(remoteIdentity(authority), 1),
      throwsA(
        isA<RepositorySessionException>().having(
          (error) => error.failure.code,
          'code',
          RepositoryFailureCode.remoteDisconnected,
        ),
      ),
    );
    final rebound = await remote.rebind(authority.profileId);
    expect(rebound.ready, isTrue);
    final profile = remote.profile(authority.profileId)!;
    expect(profile.verified!.storeId, isNot(authority.storeId));
    expect(profile.writesAllowed, isFalse);
  });

  test('a new repository is created on the host and opens there', () async {
    final readOnly = await connect();
    final path = utf8.encode('${home.path}/created/project');
    await expectLater(
      remote.initializeRepository(
        readOnly,
        path,
        initialBranch: 'main',
        bare: false,
      ),
      throwsA(
        isA<RemoteWorkspaceException>().having(
          (error) => error.code,
          'code',
          RemoteFailureCode.writeNotPermitted,
        ),
      ),
    );
    expect(Directory('${home.path}/created').existsSync(), isFalse);
    await remote.setWritesAllowed(readOnly.profileId, true);
    await remote.disconnect(readOnly.profileId);
    expect((await remote.connect(readOnly.profileId)).ready, isTrue);
    final authority = remote.profile(readOnly.profileId)!.authority!;
    await remote.initializeRepository(
      authority,
      path,
      initialBranch: 'trunk',
      bare: false,
    );
    expect(
      await _git(Directory('${home.path}/created/project'), [
        'symbolic-ref',
        'HEAD',
      ]),
      'refs/heads/trunk',
    );
    // Asking again, as after a lost answer, reports the repository.
    await expectLater(
      remote.initializeRepository(
        authority,
        path,
        initialBranch: 'trunk',
        bare: false,
      ),
      throwsA(
        isA<RepositorySessionException>().having(
          (error) => error.failure.code,
          'code',
          RepositoryFailureCode.existingRepository,
        ),
      ),
    );
    await expectLater(
      remote.initializeRepository(
        authority,
        utf8.encode(repository.path),
        initialBranch: 'main',
        bare: false,
      ),
      throwsA(
        isA<RepositorySessionException>().having(
          (error) => error.failure.code,
          'code',
          RepositoryFailureCode.existingRepository,
        ),
      ),
    );
    final opened = await router.openIdentity(
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: path,
        remote: authority,
      ),
      1,
    );
    expect(opened.identity.backend, RepositoryBackendKind.remote);
    expect(await router.close(opened.identity), isTrue);
  });

  test(
    'the directory picker pages the remote home without local file access',
    () async {
      final authority = await connect();
      final page = await remote.listDirectory(authority.profileId);
      expect(utf8.decode(page.directory), home.path);
      final project = page.entries.singleWhere(
        (entry) => utf8.decode(entry.name) == 'project',
      );
      expect(project.kind, RemoteEntryKind.directory);
      expect(project.repository, isTrue);
    },
  );

  test('images, file versions, rendered diffs and patches are read on the host '
      'and finished here', () async {
    final svg = File('${repository.path}/logo.svg');
    svg.writeAsStringSync('<svg width="1" height="1"/>');
    // Above one page, so the versions arrive in several.
    final big = File('${repository.path}/big.bin');
    final firstBig = List<int>.generate(2600 * 1024, (index) => index % 251);
    big.writeAsBytesSync(firstBig);
    await _git(repository, ['add', 'logo.svg', 'big.bin']);
    await _git(repository, ['commit', '-qm', 'assets']);
    final before = await _git(repository, ['rev-parse', 'HEAD']);
    svg.writeAsStringSync('<svg width="2" height="2"/>');
    final secondBig = firstBig.reversed.toList();
    big.writeAsBytesSync(secondBig);
    await _git(repository, ['commit', '-qam', 'changed assets']);
    final after = await _git(repository, ['rev-parse', 'HEAD']);
    svg.writeAsStringSync('<svg width="3" height="3"/>');

    final authority = await connect();
    router = RepositoryBackendRouter(detached, _directory);
    final opened = await router.openIdentity(remoteIdentity(authority), 1);
    final session = opened.identity;
    await settle(session, opened.snapshot);
    final logo = utf8.encode('logo.svg');

    await router.workingImageDiff(
      session,
      side: StagingSide.unstaged,
      oldPath: logo,
      newPath: logo,
    );
    await router.imageDiff(
      session,
      oldRevision: before,
      newRevision: after,
      oldPath: logo,
      newPath: logo,
    );
    expect(utf8.decode(detached.images.first.old!), contains('"2"'));
    expect(utf8.decode(detached.images.first.newContent!), contains('"3"'));
    expect(utf8.decode(detached.images.last.old!), contains('"1"'));
    expect(utf8.decode(detached.images.last.newContent!), contains('"2"'));

    final bigPath = utf8.encode('big.bin');
    final preview = await router.previewExternalCommitDiff(
      session,
      oldRevision: before,
      newRevision: after,
      oldPath: bigPath,
      newPath: bigPath,
      definition: IntegrationDefinition(
        id: 'tool',
        kind: IntegrationKind.diffTool,
        executable: NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: utf8.encode('/usr/bin/true'),
        ),
        arguments: const ['{diff_left}', '{diff_right}'],
        launchMode: IntegrationLaunchMode.wait,
      ),
    );
    expect(detached.diffTools.single.old, firstBig);
    expect(detached.diffTools.single.newContent, secondBig);
    final ran = await router.executeIntegration(
      session,
      preview.token,
      confirmed: true,
    );
    expect(ran.state, IntegrationExecutionState.completed);
    expect(detached.executed, [preview.token]);

    final diff = await router.workingDiff(session, side: StagingSide.unstaged);
    await expectLater(
      router.previewDiffRenderer(
        session,
        requestId: diff.requestId,
        definition: DiffRendererDefinition(
          id: 'renderer',
          title: 'Renderer',
          executable: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: utf8.encode('/usr/bin/true'),
          ),
        ),
      ),
      throwsA(isA<DiffRendererException>()),
    );
    // The only working change is the image; its renderer input names it.
    expect(utf8.decode(detached.rendererInputs.single), contains('logo.svg'));

    final patch = await router.previewPatchExport(
      session,
      PatchExportRequest(commit: after, destinationDirectory: '/chosen'),
    );
    expect(patch.destination, '/chosen/${patch.filename}');
    expect(detached.patches.single.format, PatchFormat.formatPatch);
    expect(
      utf8.decode(detached.patches.single.bytes, allowMalformed: true),
      contains('changed assets'),
    );
    expect(await router.close(session), isTrue);
  });
}
