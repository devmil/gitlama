import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/patch.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/impl/native_repository_session_repository.dart';
import 'package:gitlama/repositories/impl/remote/remote_session_calls.dart';
import 'package:gitlama/repositories/impl/repository_session_calls.g.dart';
import 'package:gitlama/repositories/remote_connection_repository.dart';
import 'package:gitlama/repositories/remote_session_repository.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/dto.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/conflict.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/history_operation.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/stash.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/domain/path_identity.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/transfer.dart';

import 'support/fake_remote_channel.dart';

const _authority = RemoteAuthority(
  profileId: '123e4567-e89b-42d3-a456-426614174000',
  storeId: 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0',
  accountUid: '1000',
);
const _binding =
    'b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0';

NativeRepositorySnapshot _snapshot(int revision) => NativeRepositorySnapshot(
  revision: BigInt.from(revision),
  phase: NativeRepositoryPhase.loading,
  refCounts: NativeRepositoryRefCounts(
    branches: BigInt.zero,
    remotes: BigInt.zero,
    tags: BigInt.zero,
    stashes: BigInt.zero,
    worktrees: BigInt.zero,
  ),
  refs: const NativeRepositoryRefs(
    branches: [],
    remotes: [],
    tags: [],
    stashes: [],
    truncated: false,
  ),
);

Object? _events(int revision) => encodeNativeRepositoryEventsResult(
  NativeRepositoryEventsResult(
    events: [
      NativeRepositoryEvent(
        kind: NativeRepositoryEventKind.snapshot,
        snapshot: _snapshot(revision),
        cacheHit: false,
      ),
    ],
  ),
);

final class _Ledger implements RemoteOperationLedger {
  final recorded = <RemotePendingOperation>[];
  Object? failure;

  @override
  Future<void> record(RemotePendingOperation operation) async {
    final error = failure;
    if (error != null) throw error;
    recorded.add(operation);
  }
}

NativePathIdentity _path(String text) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: Uint16List.fromList(utf8.encode(text)),
);

void main() {
  late FakeRemoteChannel channel;
  late _Ledger ledger;
  late RemoteSessionCalls calls;
  var nextLocal = BigInt.from(1000);

  void build({Set<RemoteCapability>? capabilities}) {
    channel = FakeRemoteChannel(capabilities: capabilities);
    ledger = _Ledger();
    calls = RemoteSessionCalls(
      channel,
      authority: _authority,
      ledger: ledger,
      allocateSessionId: () => nextLocal += BigInt.one,
      expectedBinding: (_) => null,
    );
    channel.handler = (method, arguments) => switch (method) {
      'openRepository' => {
        'binding': _binding,
        'open': encodeNativeRepositoryOpenResult(
          NativeRepositoryOpenResult(
            session: NativeRepositorySession(
              sessionId: BigInt.from(7),
              generation: BigInt.from(3),
              snapshot: _snapshot(1),
            ),
          ),
        ),
      },
      'closeRepository' => encodeNativeRepositoryCommandResult(
        const NativeRepositoryCommandResult(accepted: true),
      ),
      'previewStage' => {
        'token': 'c' * 32,
        'epoch': 'e' * 32,
        'digest': 'd' * 64,
        'expiresInMs': '120000',
      },
      _ => throw const RemoteCallException(RemoteErrorCode.unsupportedCommand),
    };
  }

  Future<BigInt> open() async {
    final opened = await calls.repositorySessionOpenIdentity(
      identity: _path('/home/alice/project'),
      generation: BigInt.from(3),
    );
    return opened.session!.sessionId;
  }

  NativeStagingRequest stageRequest() => NativeStagingRequest(
    requestId: BigInt.one,
    side: NativeStagingSide.unstaged,
    scope: NativeStagingScope.all,
    paths: const [],
    rowIds: const [],
  );

  setUp(build);

  test('helper sessions get local identifiers and translated calls', () async {
    final local = await open();
    expect(local, isNot(BigInt.from(7)));
    expect(calls.bindingOf(local), _binding);
    expect(calls.helperSession(local), BigInt.from(7));
    expect(
      () => calls.helperSession(BigInt.from(7)),
      throwsA(isA<RepositorySessionException>()),
    );
    final request = channel.calls.single;
    expect(request.method, 'openRepository');
    expect(
      request.arguments['path'],
      base64.encode(utf8.encode('/home/alice/project')),
    );
  });

  test(
    'publications before the open reply are kept and late ones after close dropped',
    () async {
      channel.publish(BigInt.from(7), _events(2));
      final local = await open();
      final first = await calls.repositorySessionEvents(
        sessionId: local,
        generation: BigInt.from(3),
        maximumEvents: 64,
      );
      expect(first.events.single.snapshot!.revision, BigInt.two);
      await calls.repositorySessionClose(
        sessionId: local,
        generation: BigInt.from(3),
      );
      channel.publish(BigInt.from(7), _events(3));
      final after = await calls.repositorySessionEvents(
        sessionId: local,
        generation: BigInt.from(3),
        maximumEvents: 64,
      );
      expect(after.events, isEmpty);
    },
  );

  test(
    'a flood of events collapses to the newest snapshot as a resynchronization',
    () async {
      final local = await open();
      for (var revision = 0; revision < 1100; revision += 1) {
        channel.publish(BigInt.from(7), _events(revision));
      }
      final drained = await calls.repositorySessionEvents(
        sessionId: local,
        generation: BigInt.from(3),
        maximumEvents: 256,
      );
      expect(drained.events.length, lessThanOrEqualTo(256));
      expect(drained.events.last.snapshot!.revision, BigInt.from(1099));
    },
  );

  test('change bytes the host keeps are read back for both sides', () async {
    final local = await open();
    final previous = channel.handler!;
    final pages = <String>[];
    channel.handler = (method, arguments) {
      if (method == 'repositorySessionWorkingChangeSource') {
        return encodeNativeChangeSourceResult(
          NativeChangeSourceResult(
            token: BigInt.from(9),
            oldBytes: BigInt.from(2),
            newBytes: BigInt.from(3),
          ),
        );
      }
      if (method == 'repositorySessionChangeSourcePage') {
        final side = arguments['newSide'] == true ? 'new' : 'old';
        final offset = arguments['offset'] as String;
        pages.add('$side@$offset');
        final text = switch ((side, offset)) {
          ('old', '0') => 'ab',
          ('new', '0') => 'xy',
          _ => 'z',
        };
        return encodeNativeChangeSourcePage(
          NativeChangeSourcePage(bytes: Uint8List.fromList(text.codeUnits)),
        );
      }
      return previous(method, arguments);
    };
    final source = await NativeRepositorySessionRepository(calls)
        .workingChangeSource(
          RepositorySessionIdentity(
            nativeId: local,
            generation: 3,
            backend: RepositoryBackendKind.remote,
          ),
          side: StagingSide.unstaged,
          newPath: utf8.encode('logo.svg'),
          byteLimit: 8 * 1024 * 1024,
        );
    expect(utf8.decode(source.old!), 'ab');
    expect(utf8.decode(source.newContent!), 'xyz');
    expect(pages, ['old@0', 'new@0', 'new@2']);
  });

  test('a patch built on the host is read back page by page', () async {
    final local = await open();
    final previous = channel.handler!;
    final offsets = <String>[];
    channel.handler = (method, arguments) {
      if (method == 'repositorySessionPatchExportContent') {
        return encodeNativePatchExportContentResult(
          NativePatchExportContentResult(
            content: NativePatchExportContent(
              token: BigInt.from(7),
              scope: NativePatchExportScope.commit,
              format: NativePatchFormat.formatPatch,
              filename: 'change.patch',
              totalBytes: BigInt.from(5),
              first: Uint8List.fromList('ab'.codeUnits),
            ),
          ),
        );
      }
      if (method == 'repositorySessionPatchExportContentPage') {
        final offset = arguments['offset'] as String;
        offsets.add(offset);
        return encodeNativePatchExportContentPage(
          NativePatchExportContentPage(
            bytes: Uint8List.fromList((offset == '2' ? 'cd' : 'e').codeUnits),
          ),
        );
      }
      return previous(method, arguments);
    };
    final content = await NativeRepositorySessionRepository(calls)
        .patchExportContent(
          RepositorySessionIdentity(
            nativeId: local,
            generation: 3,
            backend: RepositoryBackendKind.remote,
          ),
          const PatchExportRequest(
            commit: 'cccccccccccccccccccccccccccccccccccccccc',
            destinationDirectory: '/ignored',
          ),
        );
    expect(utf8.decode(content.bytes), 'abcde');
    expect(content.filename, 'change.patch');
    expect(content.format, PatchFormat.formatPatch);
    expect(offsets, ['2', '4']);
  });

  test(
    'immutable reads are served locally after their first success',
    () async {
      final local = await open();
      var failing = true;
      final previous = channel.handler!;
      channel.handler = (method, arguments) {
        if (method != 'repositorySessionCommitInspection') {
          return previous(method, arguments);
        }
        return encodeNativeCommitInspectionResult(
          failing
              ? const NativeCommitInspectionResult(
                  failure: NativeRepositoryFailure(
                    kind: NativeRepositoryFailureKind.read,
                  ),
                )
              : NativeCommitInspectionResult(
                  inspection: NativeCommitInspection(
                    detail: NativeCommitDetail(
                      commit: 'c' * 40,
                      tree: 'a' * 40,
                      parents: const [],
                      author: Uint8List(0),
                      avatarHash: '',
                      authorTime: 0,
                      authorTimezone: Uint8List(0),
                      committer: Uint8List(0),
                      committerTime: 0,
                      committerTimezone: Uint8List(0),
                      message: Uint8List(0),
                    ),
                    files: const [],
                  ),
                ),
        );
      };
      Future<NativeCommitInspectionResult> inspect(BigInt session) =>
          calls.repositorySessionCommitInspection(
            sessionId: session,
            generation: BigInt.from(3),
            commit: 'c' * 40,
          );
      int requests() => channel.calls
          .where((call) => call.method == 'repositorySessionCommitInspection')
          .length;
      expect((await inspect(local)).failure, isNotNull);
      expect((await inspect(local)).failure, isNotNull);
      expect(requests(), 2, reason: 'failures are never cached');
      failing = false;
      expect((await inspect(local)).inspection, isNotNull);
      expect((await inspect(local)).inspection, isNotNull);
      expect(requests(), 3);
      await calls.repositorySessionClose(
        sessionId: local,
        generation: BigInt.from(3),
      );
      final reopened = await open();
      await inspect(reopened);
      expect(requests(), 4, reason: 'a closed session forgets its results');
    },
  );

  test(
    'calls outside the remote surface fail before anything is sent',
    () async {
      final local = await open();
      channel.calls.clear();
      expect(
        () => calls.repositorySessionDiscardPreview(
          sessionId: local,
          generation: BigInt.from(3),
          request: NativeDiscardRequest(
            kind: NativeDiscardKind.discard,
            scope: NativeDiscardScope.files,
            paths: const [],
            rowIds: const [],
          ),
        ),
        throwsA(isA<RepositorySessionException>()),
      );
      expect(channel.calls, isEmpty);
      expect(
        remoteReadMethods,
        isNot(contains('repositorySessionDiscardPreview')),
      );
    },
  );

  test('writes without the negotiated capability are unsupported', () async {
    final local = await open();
    await expectLater(
      calls.repositorySessionStagingExecute(
        sessionId: local,
        generation: BigInt.from(3),
        request: stageRequest(),
      ),
      throwsA(isA<RepositorySessionException>()),
    );
    expect(
      channel.calls.map((call) => call.method),
      isNot(contains('previewStage')),
    );
  });

  group('with write capabilities', () {
    setUp(
      () => build(
        capabilities: {
          RemoteCapability.read,
          RemoteCapability.stage,
          RemoteCapability.commit,
        },
      ),
    );

    test('a ledger failure stops the write before Execute is sent', () async {
      final local = await open();
      ledger.failure = const RemoteWorkspaceException(
        RemoteFailureCode.internal,
      );
      await expectLater(
        calls.repositorySessionStagingExecute(
          sessionId: local,
          generation: BigInt.from(3),
          request: stageRequest(),
        ),
        throwsA(isA<RemoteWorkspaceException>()),
      );
      expect(
        channel.calls.map((call) => call.method),
        isNot(contains('executeStage')),
      );
    });

    test(
      'a lost reply leaves the write pending with an unknown outcome',
      () async {
        final local = await open();
        final previous = channel.handler!;
        channel.handler = (method, arguments) {
          if (method == 'executeStage') {
            throw const RemoteCallException(RemoteErrorCode.disconnected);
          }
          return previous(method, arguments);
        };
        await expectLater(
          calls.repositorySessionStagingExecute(
            sessionId: local,
            generation: BigInt.from(3),
            request: stageRequest(),
          ),
          throwsA(isA<RemoteOutcomeUnknownException>()),
        );
        expect(ledger.recorded.first.pending, isTrue);
        expect(ledger.recorded.first.outcome, isNull);
        expect(ledger.recorded.last.pending, isTrue);
        expect(ledger.recorded.last.outcome, RemoteOperationOutcome.unknown);
        expect(
          ledger.recorded.map((operation) => operation.operationId).toSet(),
          hasLength(1),
        );
        // Exactly one Execute was sent, with the long deadline; nothing is
        // retried.
        final executes = channel.calls.where(
          (call) => call.method == 'executeStage',
        );
        expect(executes, hasLength(1));
        expect(executes.single.bulk, isTrue);
      },
    );

    test(
      'a refused admission is definite and recorded as not applied',
      () async {
        final local = await open();
        final previous = channel.handler!;
        channel.handler = (method, arguments) {
          if (method == 'executeStage') {
            throw const RemoteCallException(RemoteErrorCode.previewExpired);
          }
          return previous(method, arguments);
        };
        // An expired preview is a stale preview, as on this computer.
        final result = await calls.repositorySessionStagingExecute(
          sessionId: local,
          generation: BigInt.from(3),
          request: stageRequest(),
        );
        expect(result.state, NativeStagingExecutionState.stale);
        expect(ledger.recorded.last.pending, isFalse);
        expect(ledger.recorded.last.outcome, RemoteOperationOutcome.notApplied);

        channel.handler = (method, arguments) {
          if (method == 'executeStage') {
            throw const RemoteCallException(RemoteErrorCode.writeNotPermitted);
          }
          return previous(method, arguments);
        };
        await expectLater(
          calls.repositorySessionStagingExecute(
            sessionId: local,
            generation: BigInt.from(3),
            request: stageRequest(),
          ),
          throwsA(
            isA<RepositorySessionException>().having(
              (error) => error.failure.code,
              'code',
              RepositoryFailureCode.remoteWriteNotPermitted,
            ),
          ),
        );
        expect(ledger.recorded.last.outcome, RemoteOperationOutcome.notApplied);
      },
    );

    test(
      'a durable success resolves the record with the helper outcome',
      () async {
        final local = await open();
        final previous = channel.handler!;
        channel.handler = (method, arguments) {
          if (method == 'executeStage') {
            expect(
              arguments['operationId'],
              ledger.recorded.single.operationId,
            );
            return {
              'operation': {
                'operationId': arguments['operationId'],
                'epoch': 'e' * 32,
                'state': 'terminal',
                'outcome': 'succeeded',
                'resultObjectId': null,
              },
              'result': encodeNativeStagingExecutionResult(
                const NativeStagingExecutionResult(
                  state: NativeStagingExecutionState.completed,
                ),
              ),
            };
          }
          return previous(method, arguments);
        };
        final result = await calls.repositorySessionStagingExecute(
          sessionId: local,
          generation: BigInt.from(3),
          request: stageRequest(),
        );
        expect(result.state, NativeStagingExecutionState.completed);
        expect(ledger.recorded.last.pending, isFalse);
        expect(ledger.recorded.last.outcome, RemoteOperationOutcome.succeeded);
      },
    );

    test(
      'amend, skipped hooks and disabled signing are previewed on the host',
      () async {
        final local = await open();
        for (final request in [
          const NativeCommitRequest(
            subject: 's',
            description: '',
            coauthors: [],
            amend: true,
            skipHooks: false,
            signing: NativeCommitSigning.useGitConfiguration,
            signOff: false,
          ),
          const NativeCommitRequest(
            subject: 's',
            description: '',
            coauthors: [],
            amend: false,
            skipHooks: true,
            signing: NativeCommitSigning.useGitConfiguration,
            signOff: false,
          ),
          const NativeCommitRequest(
            subject: 's',
            description: '',
            coauthors: [],
            amend: false,
            skipHooks: false,
            signing: NativeCommitSigning.disable,
            signOff: false,
          ),
        ]) {
          try {
            await calls.repositorySessionCommitPreview(
              sessionId: local,
              generation: BigInt.from(3),
              request: request,
            );
          } on Object {
            // The fake helper answers no preview; only the request matters.
          }
        }
        final sent = [
          for (final call in channel.calls)
            if (call.method == 'previewCommit')
              call.arguments['request']! as Map<String, Object?>,
        ];
        expect(sent, hasLength(3));
        expect(sent[0]['amend'], isTrue);
        expect(sent[1]['skipHooks'], isTrue);
        expect(sent[2]['signing'], 'disable');
      },
    );
  });

  group('branches, stashes and transfers', () {
    setUp(
      () => build(
        capabilities: {
          RemoteCapability.read,
          RemoteCapability.refs,
          RemoteCapability.stash,
          RemoteCapability.transfer,
          RemoteCapability.discard,
        },
      ),
    );

    /// Answers the preview of [family] with a helper token for core token 5
    /// and its Execute with [outcome] and [result].
    void answer(
      String family,
      Object? preview, {
      required String outcome,
      Object? result,
      RemoteErrorCode? executeError,
    }) {
      final previous = channel.handler!;
      channel.handler = (method, arguments) {
        if (method == 'preview$family') {
          return {
            'token': 'c' * 32,
            'epoch': 'e' * 32,
            'digest': 'd' * 64,
            'expiresInMs': '120000',
            'preview': preview,
          };
        }
        if (method == 'execute$family') {
          expect(arguments['token'], 'c' * 32);
          expect(arguments['operationId'], ledger.recorded.first.operationId);
          if (executeError != null) throw RemoteCallException(executeError);
          return {
            'operation': {
              'operationId': arguments['operationId'],
              'epoch': 'e' * 32,
              'state': 'terminal',
              'outcome': outcome,
              'resultObjectId': null,
            },
            'result': result,
          };
        }
        return previous(method, arguments);
      };
    }

    test('a branch change is recorded under its own family', () async {
      final local = await open();
      answer(
        'Refs',
        encodeNativeRefMutationPreviewResult(
          NativeRefMutationPreviewResult(
            preview: NativeRefMutationPreview(
              token: BigInt.from(5),
              kind: NativeRefMutationKind.createBranch,
              arguments: const [],
              warnings: const [],
            ),
          ),
        ),
        outcome: 'succeeded',
        result: encodeNativeRefMutationExecutionResult(
          const NativeRefMutationExecutionResult(
            state: NativeRefMutationExecutionState.completed,
          ),
        ),
      );
      final preview = await calls.repositorySessionRefMutationPreview(
        sessionId: local,
        generation: BigInt.from(3),
        request: NativeRefMutationRequest(
          kind: NativeRefMutationKind.createBranch,
          name: 'feature',
          target: 'a' * 40,
          force: false,
          checkout: false,
        ),
      );
      final result = await calls.repositorySessionRefMutationExecute(
        sessionId: local,
        generation: BigInt.from(3),
        token: preview.preview!.token,
      );
      expect(result.state, NativeRefMutationExecutionState.completed);
      expect(ledger.recorded.first.family, RemoteOperationFamily.refs);
      expect(ledger.recorded.first.summary, 'feature');
      expect(ledger.recorded.last.outcome, RemoteOperationOutcome.succeeded);
      // The preview is admitted once; a second execute is stale.
      final again = await calls.repositorySessionRefMutationExecute(
        sessionId: local,
        generation: BigInt.from(3),
        token: preview.preview!.token,
      );
      expect(again.state, NativeRefMutationExecutionState.stale);
      expect(
        channel.calls.where((call) => call.method == 'executeRefs'),
        hasLength(1),
      );
    });

    test(
      'a discard is recorded under its own family and admitted once',
      () async {
        final local = await open();
        answer(
          'Discard',
          encodeNativeDiscardPreviewResult(
            NativeDiscardPreviewResult(
              preview: NativeDiscardPreview(
                token: BigInt.from(5),
                kind: NativeDiscardKind.discard,
                fileCount: BigInt.one,
                arguments: const [],
              ),
            ),
          ),
          outcome: 'succeeded',
          result: encodeNativeDiscardExecutionResult(
            const NativeDiscardExecutionResult(
              state: NativeDiscardExecutionState.completed,
            ),
          ),
        );
        final preview = await calls.repositorySessionDiscardPreview(
          sessionId: local,
          generation: BigInt.from(3),
          request: NativeDiscardRequest(
            kind: NativeDiscardKind.discard,
            scope: NativeDiscardScope.files,
            paths: [utf8.encode('README.md')],
            rowIds: const [],
          ),
        );
        final result = await calls.repositorySessionDiscardExecute(
          sessionId: local,
          generation: BigInt.from(3),
          token: preview.preview!.token,
        );
        expect(result.state, NativeDiscardExecutionState.completed);
        expect(ledger.recorded.first.family, RemoteOperationFamily.discard);
        expect(ledger.recorded.last.outcome, RemoteOperationOutcome.succeeded);
        final again = await calls.repositorySessionDiscardExecute(
          sessionId: local,
          generation: BigInt.from(3),
          token: preview.preview!.token,
        );
        expect(again.state, NativeDiscardExecutionState.stale);
        expect(
          channel.calls.where((call) => call.method == 'executeDiscard'),
          hasLength(1),
        );
      },
    );

    test('a reset is previewed on the host like any ref change', () async {
      final local = await open();
      try {
        await calls.repositorySessionRefMutationPreview(
          sessionId: local,
          generation: BigInt.from(3),
          request: const NativeRefMutationRequest(
            kind: NativeRefMutationKind.reset,
            name: 'main',
            force: false,
            resetMode: NativeRefResetMode.hard,
            checkout: false,
          ),
        );
      } on Object {
        // The fake helper answers no preview; only the request matters.
      }
      final sent = channel.calls.where((call) => call.method == 'previewRefs');
      expect(sent, hasLength(1));
      final request = sent.single.arguments['request']! as Map<String, Object?>;
      expect(request['kind'], 'reset');
      expect(request['resetMode'], 'hard');
    });

    test('a conflicting pop is settled as partial with its result', () async {
      final local = await open();
      answer(
        'Stash',
        encodeNativeStashPreviewResult(
          NativeStashPreviewResult(
            preview: NativeStashPreview(
              token: BigInt.from(5),
              kind: NativeStashKind.pop,
              commands: const [],
              affectedPaths: 1,
              includesUntracked: false,
              keepsIndex: false,
              destructive: false,
            ),
          ),
        ),
        outcome: 'partial',
        result: encodeNativeStashExecutionResult(
          const NativeStashExecutionResult(
            state: NativeStashExecutionState.conflict,
            activityIds: [],
            stashCreated: false,
            checkoutCompleted: false,
            reapplyCompleted: false,
            stashRetained: true,
          ),
        ),
      );
      final preview = await calls.repositorySessionStashPreview(
        sessionId: local,
        generation: BigInt.from(3),
        request: const NativeStashRequest(
          kind: NativeStashKind.pop,
          selector: 'stash@{0}',
          objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          paths: [],
          includeUntracked: false,
          keepIndex: false,
        ),
      );
      final result = await calls.repositorySessionStashExecute(
        sessionId: local,
        generation: BigInt.from(3),
        token: preview.preview!.token,
      );
      expect(result.state, NativeStashExecutionState.conflict);
      expect(result.stashRetained, isTrue);
      expect(ledger.recorded.last.pending, isFalse);
      expect(ledger.recorded.last.outcome, RemoteOperationOutcome.partial);
    });

    test('a push whose reply is lost stays pending and unknown', () async {
      final local = await open();
      answer(
        'Transfer',
        encodeNativeTransferPreviewResult(
          NativeTransferPreviewResult(
            preview: NativeTransferPreview(
              token: BigInt.from(5),
              kind: NativeTransferKind.push,
              remote: 'origin',
              branch: 'main',
              arguments: const [],
              ahead: BigInt.one,
              behind: BigInt.zero,
              dirty: false,
              forceWithLease: false,
            ),
          ),
        ),
        outcome: 'unknown',
        executeError: RemoteErrorCode.disconnected,
      );
      final preview = await calls.repositorySessionTransferPreview(
        sessionId: local,
        generation: BigInt.from(3),
        request: const NativeTransferRequest(
          kind: NativeTransferKind.push,
          remote: 'origin',
          branch: 'main',
          pullStrategy: NativePullStrategy.fastForwardOnly,
          allowDirty: false,
          stashBeforePull: false,
          forceWithLease: false,
          setUpstream: false,
          refetch: false,
          prune: true,
        ),
      );
      await expectLater(
        calls.repositorySessionTransferExecute(
          sessionId: local,
          generation: BigInt.from(3),
          token: preview.preview!.token,
        ),
        throwsA(isA<RemoteOutcomeUnknownException>()),
      );
      expect(ledger.recorded.last.family, RemoteOperationFamily.transfer);
      expect(ledger.recorded.last.summary, 'origin/main');
      expect(ledger.recorded.last.pending, isTrue);
      expect(ledger.recorded.last.outcome, RemoteOperationOutcome.unknown);
      // Credentials entered here are never sent to the host.
      expect(
        () => calls.repositorySessionTransferExecuteWithCredentials(
          sessionId: local,
          generation: BigInt.from(3),
          token: preview.preview!.token,
          password: 'secret',
        ),
        throwsA(isA<RepositorySessionException>()),
      );
      expect(
        channel.calls.where((call) => call.method == 'executeTransfer'),
        hasLength(1),
      );
    });
  });

  group('history and recovery', () {
    setUp(
      () => build(
        capabilities: {
          RemoteCapability.read,
          RemoteCapability.history,
          RemoteCapability.recovery,
        },
      ),
    );

    /// Answers previews of [family] with a helper token and records each
    /// Execute's arguments; Execute settles with [outcome] and [result].
    List<Map<String, Object?>> answer(
      String family,
      Object? preview, {
      required String outcome,
      Object? result,
    }) {
      final executed = <Map<String, Object?>>[];
      final previous = channel.handler!;
      channel.handler = (method, arguments) {
        if (method == 'preview$family') {
          return {
            'token': 'c' * 32,
            'epoch': 'e' * 32,
            'digest': 'd' * 64,
            'expiresInMs': '120000',
            'preview': ?preview,
          };
        }
        if (method == 'execute$family') {
          executed.add(arguments);
          return {
            'operation': {
              'operationId': arguments['operationId'],
              'epoch': 'e' * 32,
              'state': 'terminal',
              'outcome': outcome,
              'resultObjectId': null,
            },
            'result': result,
          };
        }
        return previous(method, arguments);
      };
      return executed;
    }

    test(
      'a conflicting merge is recorded as history and settles as partial',
      () async {
        final local = await open();
        answer(
          'History',
          encodeNativeHistoryMutationPreviewResult(
            NativeHistoryMutationPreviewResult(
              preview: NativeHistoryMutationPreview(
                token: BigInt.from(5),
                kind: NativeHistoryMutationKind.merge,
                arguments: const [],
                targets: ['a' * 40],
                currentBranch: Uint8List.fromList(utf8.encode('main')),
                currentHead: 'b' * 40,
                publishedHistory: false,
                alreadyContained: false,
                noCommit: false,
              ),
            ),
          ),
          outcome: 'partial',
          result: encodeNativeHistoryMutationExecutionResult(
            NativeHistoryMutationExecutionResult(
              state: NativeHistoryMutationExecutionState.conflict,
              activityIds: const [],
              conflictingPaths: [Uint8List.fromList(utf8.encode('a.txt'))],
            ),
          ),
        );
        final preview = await calls.repositorySessionHistoryMutationPreview(
          sessionId: local,
          generation: BigInt.from(3),
          request: NativeHistoryMutationRequest(
            kind: NativeHistoryMutationKind.merge,
            targets: ['a' * 40],
            mergeMode: NativeHistoryMergeMode.fastForwardIfPossible,
            acknowledgePublishedHistory: false,
            noCommit: false,
          ),
        );
        final result = await calls.repositorySessionHistoryMutationExecute(
          sessionId: local,
          generation: BigInt.from(3),
          token: preview.preview!.token,
        );
        expect(result.state, NativeHistoryMutationExecutionState.conflict);
        expect(ledger.recorded.last.family, RemoteOperationFamily.history);
        expect(ledger.recorded.last.outcome, RemoteOperationOutcome.partial);
        expect(ledger.recorded.last.pending, isFalse);
      },
    );

    test(
      'a conflict resolution carries its request again at Execute',
      () async {
        final local = await open();
        final executed = answer(
          'Conflict',
          null,
          outcome: 'succeeded',
          result: encodeNativeConflictSnapshotResult(
            const NativeConflictSnapshotResult(activityIds: []),
          ),
        );
        await calls.repositorySessionConflictChooseSide(
          sessionId: local,
          generation: BigInt.from(3),
          path: utf8.encode('a.txt'),
          expectedFingerprint: BigInt.from(42),
          choice: NativeConflictSideChoice.incoming,
        );
        final previewed = channel.calls
            .singleWhere((call) => call.method == 'previewConflict')
            .arguments['request'];
        expect(executed.single['request'], previewed);
        expect(previewed, containsPair('action', 'chooseSide'));
        expect(previewed, containsPair('side', 'incoming'));
        expect(ledger.recorded.last.family, RemoteOperationFamily.conflict);
      },
    );

    test('a patch on this computer travels to the host as its bytes', () async {
      final local = await open();
      final directory = await Directory.systemTemp.createTemp('remote-patch');
      addTearDown(() => directory.delete(recursive: true));
      final patch = File('${directory.path}/change.patch');
      await patch.writeAsString('diff --git a/a b/a\n');
      answer(
        'Patch',
        encodeNativePatchApplyPreviewResult(
          const NativePatchApplyPreviewResult(),
        ),
        outcome: 'succeeded',
      );
      await calls.repositorySessionPatchApplyPreview(
        sessionId: local,
        generation: BigInt.from(3),
        patchPath: patch.path,
      );
      final request =
          channel.calls
                  .singleWhere((call) => call.method == 'previewPatch')
                  .arguments['request']!
              as Map<String, Object?>;
      expect(
        base64Decode(request['content']! as String),
        utf8.encode('diff --git a/a b/a\n'),
      );
      // A patch too large for one request never leaves this computer.
      await patch.writeAsBytes(List.filled(remotePatchBytes + 1, 0x61));
      final refused = await calls.repositorySessionPatchApplyPreview(
        sessionId: local,
        generation: BigInt.from(3),
        patchPath: patch.path,
      );
      expect(refused.failure, isNotNull);
      expect(
        channel.calls.where((call) => call.method == 'previewPatch'),
        hasLength(1),
      );
    });

    test('a preview never executed is dropped by its cancel', () async {
      final local = await open();
      answer('Undo', null, outcome: 'succeeded');
      expect(
        (await calls.repositorySessionHistoryMutationCancel(
          sessionId: local,
          generation: BigInt.from(3),
          token: BigInt.from(9),
        )).accepted,
        isFalse,
      );
    });

    test('a host without history changes refuses before sending', () async {
      build(capabilities: {RemoteCapability.read});
      final local = await open();
      await expectLater(
        calls.repositorySessionConflictContinue(
          sessionId: local,
          generation: BigInt.from(3),
          action: NativeConflictSequencerAction.abort,
        ),
        throwsA(isA<RepositorySessionException>()),
      );
      expect(
        channel.calls.map((call) => call.method),
        isNot(contains('previewSequencer')),
      );
    });
  });
}
