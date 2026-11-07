@Tags(['native'])
library;

import 'dart:io';
import 'package:gitlama/models/diff.dart' as staging;
import 'package:gitlama/models/repository_state.dart' as repository_state;
import 'package:gitlama/repositories/impl/native_repository_session_repository.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/settings.dart' show StoredAppearanceNames;
import 'package:gitlama/rust/api.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/dto.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/clone.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/diff.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/extensions.dart';
import 'package:gitlama/rust/frb_generated.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/image_decoder.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/history_operation.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/hosting.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/hosting_review.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/hosting_runtime.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/recovery.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/storage.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/hosting_settings.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/domain/path_identity.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/transfer.dart';
import 'package:gitlama/rust/third_party/gitlama_contract/view_cache.dart';

import 'package:gitlama/models/commit_archive.dart';

import 'support/git_fixture.dart';

void main() {
  final configuredWaitSeconds = int.tryParse(
    Platform.environment['GITLAMA_NATIVE_TEST_WAIT_SECONDS'] ?? '',
  );
  final nativeWait = Duration(
    seconds: (configuredWaitSeconds ?? 5).clamp(5, 60).toInt(),
  );
  final configuredTimeoutSeconds = int.tryParse(
    Platform.environment['GITLAMA_NATIVE_TEST_TIMEOUT_SECONDS'] ?? '',
  );
  final nativeTestTimeout = Duration(
    seconds: (configuredTimeoutSeconds ?? 30).clamp(30, 300).toInt(),
  );
  test('packaged native library answers the typed handshake', () async {
    final path = Platform.environment['GITLAMA_NATIVE_LIBRARY'];
    expect(
      path,
      isNotNull,
      reason: 'Set the absolute extracted artifact library path.',
    );
    await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    final infos = await Future.wait(List.generate(8, (_) => coreInfo()));
    for (final info in infos) {
      expect(info.protocolVersion, 1);
      expect(
        [info.minimumGitMajor, info.minimumGitMinor, info.minimumGitPatch],
        [2, 39, 0],
      );
    }
    // Update checks compare this identity with published releases.
    final version = File('VERSION').readAsLinesSync();
    final release = await applicationRelease();
    expect(release.version, version[0]);
    expect(release.build, int.parse(version[1]));
    // The disposable view cache stores opaque bytes privately and bounded.
    final viewCacheRoot = await Directory.systemTemp.createTemp(
      'gitlama-view-cache-bridge-',
    );
    try {
      final viewDirectory =
          '${viewCacheRoot.resolveSymbolicLinksSync()}'
          '${Platform.pathSeparator}views';
      final viewIdentity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: Uint16List.fromList('/work/cached'.codeUnits),
      );
      final absent = await applicationViewCacheRead(
        directory: viewDirectory,
        identity: viewIdentity,
      );
      expect(absent.bytes, isNull);
      expect(absent.failure, isNull);
      final written = await applicationViewCacheWrite(
        directory: viewDirectory,
        identity: viewIdentity,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(written.accepted, isTrue);
      final read = await applicationViewCacheRead(
        directory: viewDirectory,
        identity: viewIdentity,
      );
      expect(read.bytes, [1, 2, 3, 4]);
      final oversized = await applicationViewCacheWrite(
        directory: viewDirectory,
        identity: viewIdentity,
        bytes: Uint8List(16 * 1024 * 1024 + 1),
      );
      expect(oversized.accepted, isFalse);
      expect(oversized.failure?.kind, NativeViewCacheFailureKind.tooLarge);
      final relative = await applicationViewCacheRead(
        directory: 'views',
        identity: viewIdentity,
      );
      expect(relative.failure?.kind, NativeViewCacheFailureKind.unavailable);
      final removed = await applicationViewCacheRemove(
        directory: viewDirectory,
        identity: viewIdentity,
      );
      expect(removed.accepted, isTrue);
      expect(
        (await applicationViewCacheRead(
          directory: viewDirectory,
          identity: viewIdentity,
        )).bytes,
        isNull,
      );
    } finally {
      await viewCacheRoot.delete(recursive: true);
    }
    final referenceText = 'Fix 🧪 #'.codeUnits;
    final referenceProjection = await hostingReferenceProject(
      text: referenceText,
      selectionBase: referenceText.length,
      selectionExtent: referenceText.length,
      revision: BigInt.from(7),
      references: [
        NativeHostingRemoteReference(
          stableId: 'gitlab:12',
          kind: NativeHostingRemoteReferenceKind.issue,
          number: BigInt.from(12),
          title: 'Cross-project issue',
          insertion: 'group/project#12',
          webUrl: 'https://example.test/group/project/issues/12',
        ),
      ],
      stale: true,
    );
    expect(referenceProjection.failure, isNull);
    expect(referenceProjection.projection!.candidates.single.stale, isTrue);
    final referenceApplied = await hostingReferenceApply(
      text: referenceText,
      currentRevision: BigInt.from(7),
      expectedRevision: referenceProjection.projection!.revision,
      expectedTextHash: referenceProjection.projection!.textHash,
      replaceStart: referenceProjection.projection!.replaceStart,
      replaceEnd: referenceProjection.projection!.replaceEnd,
      insertion: referenceProjection.projection!.candidates.single.insertion,
    );
    expect(referenceApplied.failure, isNull);
    expect(
      String.fromCharCodes(referenceApplied.text),
      'Fix 🧪 group/project#12',
    );
    expect(referenceApplied.caret, 23);
    const reviewConnection = NativeHostingConnection(
      id: 'github:review-fixture',
      preset: NativeHostingPreset.gitHub,
      login: 'fixture',
      webBaseUrl: 'https://github.com',
      apiBaseUrl: 'https://api.github.com',
      oauthClientId: 'public-client',
      authentication: NativeHostingAuthentication.oAuth,
      enabled: true,
      refreshEnabled: false,
      capabilities: [NativeHostingCapability.changeRequestReview],
      credentialIdentity: 'credential:github:review-fixture',
      allowSplitOrigin: false,
    );
    final reviewPreview = await hostingReviewPreview(
      connection: reviewConnection,
      repository: 'team/project',
      pullRequest: BigInt.from(7),
      headSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      action: NativeHostingReviewAction.requestChanges,
      body: 'Please adjust this.',
      inlineComments: [
        NativeHostingInlineDraft(
          stableId: 'draft:fixture',
          path: 'src/lib.rs',
          line: BigInt.one,
          body: 'Keep this bounded.',
        ),
      ],
    );
    expect(reviewPreview.failure, isNull);
    expect(
      reviewPreview.preview!.target,
      '/repos/team/project/pulls/7/reviews',
    );
    expect(reviewPreview.preview!.payload, contains('REQUEST_CHANGES'));
    expect(reviewPreview.preview!.payload, contains('src/lib.rs'));
    expect(
      await hostingReviewCancel(
        connectionId: reviewConnection.id,
        repository: 'team/project',
        pullRequest: BigInt.from(7),
      ),
      isFalse,
    );
    final fixture = await GitFixture.create();
    try {
      await fixture.writeBytes('tracked.txt', 'initial\n'.codeUnits);
      await fixture.commitAll('Initial fixture');
      final initial = (await fixture.run([
        'rev-parse',
        'HEAD',
      ])).stdout.toString().trim();
      await fixture.writeBytes('tracked.txt', 'initial\nsecond\n'.codeUnits);
      await fixture.commitAll('Second fixture');
      final remote = Directory(
        '${fixture.root.path}${Platform.pathSeparator}remote.git',
      );
      final remoteInit = await Process.run('git', [
        'init',
        '-q',
        '--bare',
        remote.path,
      ]);
      expect(remoteInit.exitCode, 0, reason: '${remoteInit.stderr}');
      await fixture.run(['remote', 'add', 'origin', remote.path]);
      await fixture.run(['push', '-q', '-u', 'origin', 'main']);
      final opened = await repositorySessionOpen(
        path: fixture.worktree.path,
        generation: BigInt.one,
      );
      expect(opened.failure, isNull);
      final session = opened.session!;
      final deadline = DateTime.now().add(nativeWait);
      var ready = false;
      final observedStates = <String>[];
      while (DateTime.now().isBefore(deadline) && !ready) {
        final events = await repositorySessionEvents(
          sessionId: session.sessionId,
          generation: session.generation,
          maximumEvents: 32,
        );
        expect(events.failure, isNull);
        for (final event in events.events) {
          final snapshot = event.snapshot;
          if (snapshot != null) {
            observedStates.add(
              '${snapshot.phase.name}/'
              '${snapshot.failure?.kind.name ?? "none"}/'
              '${snapshot.statusFailure?.kind.name ?? "none"}/'
              '${snapshot.refsFailure?.kind.name ?? "none"}',
            );
          }
        }
        ready = events.events.any(
          (event) => event.snapshot?.phase == NativeRepositoryPhase.ready,
        );
        if (!ready) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(
        ready,
        isTrue,
        reason: 'Observed native states: ${observedStates.join(", ")}',
      );
      final fetchPreview = await repositorySessionTransferPreview(
        sessionId: session.sessionId,
        generation: session.generation,
        request: const NativeTransferRequest(
          kind: NativeTransferKind.fetch,
          remote: 'origin',
          branch: null,
          pullStrategy: NativePullStrategy.fastForwardOnly,
          allowDirty: false,
          stashBeforePull: false,
          forceWithLease: false,
          setUpstream: false,
          refetch: false,
          prune: true,
        ),
      );
      expect(fetchPreview.failure, isNull);
      expect(fetchPreview.preview!.arguments, contains('fetch'));
      final fetched = await repositorySessionTransferExecute(
        sessionId: session.sessionId,
        generation: session.generation,
        token: fetchPreview.preview!.token,
      );
      expect(fetched.state, NativeTransferExecutionState.completed);
      Future<void> refreshReady(String expectedPath) async {
        await repositorySessionEvents(
          sessionId: session.sessionId,
          generation: session.generation,
          maximumEvents: 64,
        );
        final refreshed = await repositorySessionRefresh(
          sessionId: session.sessionId,
          generation: session.generation,
        );
        expect(refreshed.accepted, isTrue);
        final refreshDeadline = DateTime.now().add(nativeWait);
        while (DateTime.now().isBefore(refreshDeadline)) {
          final events = await repositorySessionEvents(
            sessionId: session.sessionId,
            generation: session.generation,
            maximumEvents: 32,
          );
          if (events.events.any((event) {
            final snapshot = event.snapshot;
            return snapshot?.phase == NativeRepositoryPhase.ready &&
                snapshot?.status?.entries.any(
                      (entry) =>
                          String.fromCharCodes(entry.path.units) ==
                          expectedPath,
                    ) ==
                    true;
          })) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('repository refresh did not publish a ready snapshot');
      }

      final activity = await repositorySessionActivity(
        sessionId: session.sessionId,
        generation: session.generation,
        maximumRecords: 20,
      );
      expect(activity.failure, isNull);
      expect(activity.page, isNotNull);
      expect(activity.page!.records, isNotEmpty);
      for (final record in activity.page!.records) {
        expect(record.executable, 'git');
        expect(record.stdout.length, lessThanOrEqualTo(64 * 1024));
        expect(record.stderr.length, lessThanOrEqualTo(64 * 1024));
      }
      final historyPreview = await repositorySessionHistoryLoad(
        sessionId: session.sessionId,
        generation: session.generation,
        complete: false,
        maximumRows: 32,
        otherRefs: false,
      );
      expect(historyPreview.failure, isNull);
      expect(historyPreview.page, isNotNull);
      expect(historyPreview.page!.topologyComplete, isFalse);
      expect(historyPreview.page!.otherRefs, isFalse);
      expect(historyPreview.page!.rows, isNotEmpty);
      expect(historyPreview.page!.rows.length, lessThanOrEqualTo(32));
      final historyComplete = await repositorySessionHistoryComplete(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: historyPreview.page!.requestId,
        maximumRows: 32,
      );
      expect(historyComplete.failure, isNull);
      expect(historyComplete.page!.topologyComplete, isTrue);
      expect(
        historyComplete.page!.payloadBytes,
        lessThan(BigInt.from(512 * 1024)),
      );
      expect(historyComplete.page!.totalRows, greaterThanOrEqualTo(BigInt.one));
      for (final edge in historyComplete.page!.segments) {
        expect(
          historyComplete.page!.rows[edge.fromRow.toInt()].objectId,
          edge.fromObjectId,
        );
        if (edge.toRow case final target?) {
          expect(
            historyComplete.page!.rows[target.toInt()].objectId,
            edge.toObjectId,
          );
        }
        expect(edge.lit, isFalse);
      }

      final historyMetadata = await repositorySessionHistoryMetadata(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: historyComplete.page!.requestId,
        objectIds: [historyComplete.page!.rows.first.objectId],
      );
      expect(historyMetadata.failure, isNull);
      expect(historyMetadata.rows.single.subject, isNotEmpty);
      final historyLighting = await repositorySessionHistorySelect(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: historyComplete.page!.requestId,
        options: NativeHistorySelectionOptions(
          objectId: historyComplete.page!.rows.first.objectId,
          toggle: false,
          reveal: true,
          focus: true,
          offset: BigInt.zero,
          maximumRows: 32,
        ),
      );
      expect(historyLighting.failure, isNull);
      expect(historyLighting.page!.lightingActive, isTrue);
      expect(historyLighting.page!.rows.first.selected, isTrue);
      expect(historyLighting.page!.rows.first.lit, isTrue);
      expect(historyLighting.page!.currentObjectId, isNotNull);
      expect(historyLighting.page!.revealSequence, BigInt.one);
      final head = (await fixture.run([
        'rev-parse',
        'HEAD',
      ])).stdout.toString().trim();
      final comparisonSelection = await repositorySessionHistorySelect(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: historyComplete.page!.requestId,
        options: NativeHistorySelectionOptions(
          objectId: initial,
          toggle: true,
          reveal: false,
          focus: false,
          offset: BigInt.zero,
          maximumRows: 32,
        ),
      );
      expect(comparisonSelection.failure, isNull);
      expect(comparisonSelection.page!.comparisonOldObjectId, head);
      expect(comparisonSelection.page!.comparisonNewObjectId, initial);
      final queried = await repositorySessionHistoryQuery(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: historyComplete.page!.requestId,
        options: NativeHistoryQueryOptions(
          text: 'Initial fixture',
          searchHash: false,
          searchMessage: true,
          searchAuthor: false,
          searchPath: false,
          offset: BigInt.zero,
          maximumRows: 32,
        ),
      );
      expect(queried.failure, isNull);
      expect(queried.page!.rows.single.objectId, initial);
      expect(queried.page!.acceptedQuery, 'Initial fixture');
      final filtered = await repositorySessionHistoryBranchFilter(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: historyComplete.page!.requestId,
        references: [Uint8List.fromList('refs/heads/main'.codeUnits)],
        offset: BigInt.zero,
        maximumRows: 32,
      );
      expect(filtered.failure, isNull);
      expect(filtered.page!.branchFilter, ['refs/heads/main'.codeUnits]);
      expect(filtered.page!.acceptedQuery, isEmpty);
      final reflog = await repositorySessionReflog(
        sessionId: session.sessionId,
        generation: session.generation,
        offset: BigInt.zero,
        maximumRows: 32,
      );
      expect(reflog.failure, isNull);
      expect(reflog.page.entries, isNotEmpty);
      expect(
        reflog.page.entries.first.actions,
        contains(NativeReflogAction.inspectCommit),
      );
      final comparisonDiff = await repositorySessionCommitDiffLoad(
        sessionId: session.sessionId,
        generation: session.generation,
        options: NativeCommitDiffOptions(
          commit: initial,
          firstParent: head,
          oldPath: null,
          newPath: null,
          contextLines: 3,
          whitespace: NativeDiffWhitespace.preserve,
          layout: NativeDiffLayout.unified,
          maximumRows: 32,
          forceText: false,
        ),
      );
      expect(comparisonDiff.failure, isNull);
      expect(comparisonDiff.page!.rows, isNotEmpty);
      final diff = await repositorySessionCommitDiffLoad(
        sessionId: session.sessionId,
        generation: session.generation,
        options: NativeCommitDiffOptions(
          commit: head,
          firstParent: null,
          oldPath: null,
          newPath: null,
          contextLines: 3,
          whitespace: NativeDiffWhitespace.preserve,
          layout: NativeDiffLayout.sideBySide,
          maximumRows: 32,
          forceText: false,
        ),
      );
      expect(diff.failure, isNull);
      expect(diff.page, isNotNull);
      expect(diff.page!.rows, isNotEmpty);
      expect(diff.page!.rows.length, lessThanOrEqualTo(32));
      expect(diff.page!.payloadBytes, lessThan(BigInt.from(512 * 1024)));
      expect(diff.page!.rows.where((row) => row.selectable), isNotEmpty);
      expect(
        diff.page!.rows.where((row) => row.selectable).first.stableId,
        startsWith('l:'),
      );
      final searchedDiff = await repositorySessionDiffSearch(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: diff.page!.requestId,
        query: Uint8List.fromList('second'.codeUnits),
        caseSensitive: false,
        maximumMatches: 32,
      );
      expect(searchedDiff.failure, isNull);
      expect(searchedDiff.matches, isNotEmpty);
      final hunkPositions = await repositorySessionDiffHunks(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: diff.page!.requestId,
        maximumPositions: 32,
      );
      expect(hunkPositions.failure, isNull);
      expect(hunkPositions.positions, isNotEmpty);
      final boundedContent = await repositorySessionImageDiff(
        sessionId: session.sessionId,
        generation: session.generation,
        oldRevision: initial,
        newRevision: head,
        oldPath: Uint8List.fromList('tracked.txt'.codeUnits),
        newPath: Uint8List.fromList('tracked.txt'.codeUnits),
        byteLimit: 1024,
      );
      expect(boundedContent.failure, isNull);
      expect(boundedContent.old, isNull);
      expect(boundedContent.new_, isNull);
      expect(
        boundedContent.decodeFailure,
        NativeImageDecodeFailureKind.unsupported,
      );
      // A distinct byte limit keeps this worktree read out of the content
      // cache entry the unrefreshed restore preview below reads.
      final workingContent = await repositorySessionWorkingImageDiff(
        sessionId: session.sessionId,
        generation: session.generation,
        side: NativeStagingSide.unstaged,
        oldPath: Uint8List.fromList('tracked.txt'.codeUnits),
        newPath: Uint8List.fromList('tracked.txt'.codeUnits),
        byteLimit: 2048,
      );
      expect(workingContent.failure, isNull);
      expect(
        workingContent.decodeFailure,
        NativeImageDecodeFailureKind.unsupported,
      );
      final addedContent = await repositorySessionWorkingImageDiff(
        sessionId: session.sessionId,
        generation: session.generation,
        side: NativeStagingSide.staged,
        newPath: Uint8List.fromList('tracked.txt'.codeUnits),
        byteLimit: 1024,
      );
      expect(addedContent.failure, isNull);
      expect(addedContent.old, isNull);
      await fixture.writeBytes(
        'preview.svg',
        File(
          'rust-core/application/test-fixtures/images/wallpaper.svg',
        ).readAsBytesSync(),
      );
      final svgPreview = await repositorySessionWorkingImageDiff(
        sessionId: session.sessionId,
        generation: session.generation,
        side: NativeStagingSide.unstaged,
        newPath: Uint8List.fromList('preview.svg'.codeUnits),
        byteLimit: 8 * 1024 * 1024,
      );
      expect(svgPreview.failure, isNull);
      expect(svgPreview.decodeFailure, isNull);
      expect(svgPreview.old, isNull);
      expect(svgPreview.new_?.width, 24);
      expect(svgPreview.new_?.height, 24);
      expect(svgPreview.new_?.rgba.length, 24 * 24 * 4);
      await File('${fixture.worktree.path}/preview.svg').delete();
      final noSides = await repositorySessionWorkingImageDiff(
        sessionId: session.sessionId,
        generation: session.generation,
        side: NativeStagingSide.staged,
        byteLimit: 1024,
      );
      expect(noSides.failure?.kind, NativeRepositoryFailureKind.invalidOptions);
      final diffPage = await repositorySessionDiffPage(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: diff.page!.requestId,
        offset: BigInt.zero,
        maximumRows: 32,
      );
      expect(diffPage.failure, isNull);
      expect(
        diffPage.page!.rows.map((row) => row.stableId),
        diff.page!.rows.map((row) => row.stableId),
      );
      final details = await repositorySessionCommitDetails(
        sessionId: session.sessionId,
        generation: session.generation,
        commits: [head, initial, head],
      );
      expect(details.failure, isNull);
      expect(details.details.map((value) => value.commit), [
        head,
        initial,
        head,
      ]);
      final commitInspection = await repositorySessionCommitInspection(
        sessionId: session.sessionId,
        generation: session.generation,
        commit: head,
        firstParent: initial,
      );
      expect(commitInspection.failure, isNull);
      expect(commitInspection.inspection!.files, isNotEmpty);
      final tree = await repositorySessionTree(
        sessionId: session.sessionId,
        generation: session.generation,
        commit: head,
        directory: null,
        offset: BigInt.zero,
        maximumRows: 32,
      );
      expect(tree.failure, isNull);
      expect(tree.page!.entries.single.path, 'tracked.txt'.codeUnits);
      final pathHistory = await repositorySessionPathHistory(
        sessionId: session.sessionId,
        generation: session.generation,
        options: NativePathHistoryOptions(
          revision: head,
          path: Uint8List.fromList('tracked.txt'.codeUnits),
          directory: false,
          offset: BigInt.zero,
          maximumRows: 32,
          renameHopsBefore: BigInt.zero,
        ),
      );
      expect(pathHistory.failure, isNull);
      expect(pathHistory.page!.entries.length, 2);
      final rangeHistory = await repositorySessionRangeHistory(
        sessionId: session.sessionId,
        generation: session.generation,
        revision: head,
        path: Uint8List.fromList('tracked.txt'.codeUnits),
        firstLine: 2,
        lastLine: 2,
        maximumRows: 32,
      );
      expect(rangeHistory.failure, isNull);
      expect(rangeHistory.entries, isNotEmpty);
      final blame = await repositorySessionBlameLoad(
        sessionId: session.sessionId,
        generation: session.generation,
        options: NativeBlameOptions(
          revision: head,
          path: Uint8List.fromList('tracked.txt'.codeUnits),
          firstLine: null,
          lastLine: null,
          detectMoves: true,
          detectCopies: true,
          maximumRows: 1,
        ),
      );
      expect(blame.failure, isNull);
      expect(blame.page!.totalRows, BigInt.two);
      expect(blame.page!.rows, hasLength(1));
      final finalBlameRow = await repositorySessionBlamePage(
        sessionId: session.sessionId,
        generation: session.generation,
        requestId: blame.page!.requestId,
        offset: BigInt.one,
        maximumRows: 1,
      );
      expect(finalBlameRow.failure, isNull);
      expect(finalBlameRow.page!.rows.single.finalLine, BigInt.two);
      await fixture.writeBytes('tracked.txt', 'local edit\n'.codeUnits);
      final restorePreview = await repositorySessionRestorePreview(
        sessionId: session.sessionId,
        generation: session.generation,
        commit: head,
        path: Uint8List.fromList('tracked.txt'.codeUnits),
        byteLimit: 1024,
      );
      expect(restorePreview.failure, isNull);
      expect(restorePreview.preview!.currentBytes, 'local edit\n'.codeUnits);
      final restore = await repositorySessionRestoreFile(
        sessionId: session.sessionId,
        generation: session.generation,
        token: restorePreview.preview!.token,
      );
      expect(restore.state, NativeRestoreState.restored);
      expect(
        await File('${fixture.worktree.path}/tracked.txt').readAsString(),
        'initial\nsecond\n',
      );
      await fixture.writeBytes('tracked.txt', 'INITIAL\nsecond\n'.codeUnits);
      final working = await repositorySessionWorkingDiffLoad(
        sessionId: session.sessionId,
        generation: session.generation,
        options: NativeWorkingDiffOptions(
          side: NativeStagingSide.unstaged,
          oldPath: Uint8List.fromList('tracked.txt'.codeUnits),
          newPath: Uint8List.fromList('tracked.txt'.codeUnits),
          contextLines: 3,
          whitespace: NativeDiffWhitespace.preserve,
          layout: NativeDiffLayout.unified,
          maximumRows: 32,
          forceText: false,
        ),
      );
      expect(working.failure, isNull);
      final hunk = working.page!.rows.singleWhere(
        (row) => row.kind == NativeDiffRowKind.hunk,
      );
      final staged = await repositorySessionStagingExecute(
        sessionId: session.sessionId,
        generation: session.generation,
        request: NativeStagingRequest(
          requestId: working.page!.requestId,
          side: NativeStagingSide.unstaged,
          scope: NativeStagingScope.rows,
          paths: [],
          rowIds: [hunk.stableId],
        ),
      );
      expect(staged.state, NativeStagingExecutionState.completed);
      expect(
        (await fixture.run(['show', ':tracked.txt'])).stdout,
        'INITIAL\nsecond\n',
      );
      await fixture.writeBytes('staged-new.txt', 'new bridge file\n'.codeUnits);
      await fixture.run(['add', 'staged-new.txt']);
      await refreshReady('staged-new.txt');
      final stagedNew = await repositorySessionWorkingDiffLoad(
        sessionId: session.sessionId,
        generation: session.generation,
        options: NativeWorkingDiffOptions(
          side: NativeStagingSide.staged,
          oldPath: null,
          newPath: Uint8List.fromList('staged-new.txt'.codeUnits),
          contextLines: 3,
          whitespace: NativeDiffWhitespace.preserve,
          layout: NativeDiffLayout.unified,
          maximumRows: 32,
          forceText: false,
        ),
      );
      expect(stagedNew.failure, isNull);
      expect(
        stagedNew.page!.rows,
        contains(
          isA<NativeDiffRow>().having(
            (row) => row.kind,
            'kind',
            NativeDiffRowKind.addition,
          ),
        ),
      );
      final commitTools = await repositorySessionCommitTools(
        sessionId: session.sessionId,
        generation: session.generation,
      );
      expect(commitTools.failure, isNull);
      expect(commitTools.tools!.recent, isNotEmpty);
      final commitPreview = await repositorySessionCommitPreview(
        sessionId: session.sessionId,
        generation: session.generation,
        request: const NativeCommitRequest(
          subject: 'Packaged commit workflow',
          description: 'Exercises the generated commit ABI.',
          coauthors: [],
          amend: false,
          skipHooks: false,
          signing: NativeCommitSigning.useGitConfiguration,
          signOff: false,
        ),
      );
      expect(commitPreview.failure, isNull);
      expect(commitPreview.preview!.arguments, contains('commit'));
      final committed = await repositorySessionCommitExecute(
        sessionId: session.sessionId,
        generation: session.generation,
        token: commitPreview.preview!.token,
      );
      expect(committed.state, NativeCommitExecutionState.completed);
      expect(committed.commit, isNotNull);

      await fixture.writeBytes('tracked.txt', 'patch target\n'.codeUnits);
      final patchDirectory = Directory(
        '${fixture.root.path}${Platform.pathSeparator}patches',
      )..createSync();
      final patchPreview = await repositorySessionPatchExportPreview(
        sessionId: session.sessionId,
        generation: session.generation,
        request: NativePatchExportRequest(
          workingDiffRequestId: null,
          rowIds: const [],
          selectedSide: null,
          selectedPaths: const [],
          focusedSide: null,
          comparisonOld: null,
          comparisonNew: null,
          rangeCommits: const [],
          commit: null,
          historyPaths: const [],
          workspaceDefault: true,
          destinationDirectory: patchDirectory.path,
          overwrite: false,
        ),
      );
      expect(patchPreview.failure, isNull);
      expect(patchPreview.preview!.scope, NativePatchExportScope.head);
      expect(patchPreview.preview!.byteCount, greaterThan(BigInt.zero));
      final exported = await repositorySessionPatchExportExecute(
        sessionId: session.sessionId,
        generation: session.generation,
        token: patchPreview.preview!.token!,
      );
      expect(exported.state, NativePatchExportExecutionState.completed);
      expect(File(exported.destination!).lengthSync(), greaterThan(0));
      await fixture.run(['restore', '--worktree', 'tracked.txt']);
      final applyPreview = await repositorySessionPatchApplyPreview(
        sessionId: session.sessionId,
        generation: session.generation,
        patchPath: exported.destination!,
      );
      expect(applyPreview.failure, isNull);
      expect(applyPreview.preview!.paths, [
        Uint8List.fromList('tracked.txt'.codeUnits),
      ]);
      final applied = await repositorySessionPatchApplyExecute(
        sessionId: session.sessionId,
        generation: session.generation,
        token: applyPreview.preview!.token,
      );
      expect(applied.state, NativePatchApplyExecutionState.completed);
      expect(
        await File('${fixture.worktree.path}/tracked.txt').readAsString(),
        'patch target\n',
      );
      await fixture.writeBytes('tracked.txt', 'discard me\n'.codeUnits);
      await refreshReady('tracked.txt');
      final discard = await repositorySessionDiscardPreview(
        sessionId: session.sessionId,
        generation: session.generation,
        request: NativeDiscardRequest(
          kind: NativeDiscardKind.discard,
          scope: NativeDiscardScope.files,
          workingDiffRequestId: null,
          paths: [Uint8List.fromList('tracked.txt'.codeUnits)],
          rowIds: const [],
        ),
      );
      expect(discard.failure, isNull);
      expect(discard.preview!.fileCount, BigInt.one);
      expect(
        (await repositorySessionDiscardExecute(
          sessionId: session.sessionId,
          generation: session.generation,
          token: discard.preview!.token,
        )).state,
        NativeDiscardExecutionState.completed,
      );
      expect(
        await File('${fixture.worktree.path}/tracked.txt').readAsString(),
        'INITIAL\nsecond\n',
      );
      await fixture.writeBytes('untracked.txt', 'remove me\n'.codeUnits);
      await refreshReady('untracked.txt');
      final clean = await repositorySessionDiscardPreview(
        sessionId: session.sessionId,
        generation: session.generation,
        request: NativeDiscardRequest(
          kind: NativeDiscardKind.clean,
          scope: NativeDiscardScope.files,
          workingDiffRequestId: null,
          paths: [Uint8List.fromList('untracked.txt'.codeUnits)],
          rowIds: const [],
        ),
      );
      expect(clean.failure, isNull);
      expect(
        (await repositorySessionDiscardExecute(
          sessionId: session.sessionId,
          generation: session.generation,
          token: clean.preview!.token,
        )).state,
        NativeDiscardExecutionState.completed,
      );
      expect(
        File('${fixture.worktree.path}/untracked.txt').existsSync(),
        isFalse,
      );
      final closed = await repositorySessionClose(
        sessionId: session.sessionId,
        generation: session.generation,
      );
      expect(closed.failure, isNull);
      expect(closed.accepted, isTrue);

      final cloneDestination =
          '${fixture.root.path}${Platform.pathSeparator}packaged-clone';
      final clone = await repositoryCloneCreate(
        source: fixture.worktree.path,
        destination: cloneDestination,
        initialBranch: null,
        generation: BigInt.from(2),
      );
      expect(clone.failure, isNull);
      final cloned = await repositoryCloneRun(
        attemptId: clone.snapshot!.attemptId,
        generation: clone.snapshot!.generation,
      );
      expect(cloned.failure, isNull);
      expect(cloned.snapshot!.state, NativeCloneState.succeeded);
      expect(cloned.session, isNotNull);
      expect(
        (await repositoryCloneDismiss(
          attemptId: clone.snapshot!.attemptId,
          generation: clone.snapshot!.generation,
        )).accepted,
        isTrue,
      );
      expect(
        (await repositorySessionClose(
          sessionId: cloned.session!.sessionId,
          generation: cloned.session!.generation,
        )).accepted,
        isTrue,
      );

      const hostingConnection = NativeHostingConnection(
        id: 'gitlab:fixture',
        preset: NativeHostingPreset.gitLabSelfManaged,
        login: 'fixture',
        webBaseUrl: 'https://Git.Example.test',
        apiBaseUrl: 'https://git.example.test/api/v4',
        oauthClientId: 'public-client',
        authentication: NativeHostingAuthentication.oAuth,
        enabled: true,
        refreshEnabled: true,
        capabilities: [
          NativeHostingCapability.changeRequests,
          NativeHostingCapability.issues,
        ],
        credentialIdentity: 'credential:gitlab:fixture',
        allowSplitOrigin: false,
      );
      final validatedHosting = await hostingConnectionValidate(
        connection: hostingConnection,
      );
      expect(validatedHosting.failure, isNull);
      expect(
        validatedHosting.connection!.webBaseUrl,
        'https://git.example.test',
      );
      final hostingBinding = await hostingBindingResolve(
        connections: [validatedHosting.connection!],
        remotes: [
          NativeHostingRemote(
            name: Uint8List.fromList('origin'.codeUnits),
            url: 'ssh://git@GIT.EXAMPLE.TEST:22/group/nested/project.git',
          ),
        ],
        overrideConnectionId: null,
      );
      expect(hostingBinding.state, NativeHostingBindingState.bound);
      expect(hostingBinding.providerRepository, 'group/nested/project');
      final hostingLink = await hostingResourceLink(
        connection: validatedHosting.connection!,
        providerRepository: 'group/nested/project',
        kind: NativeHostingResourceKind.changeRequest,
        number: BigInt.from(42),
      );
      expect(
        hostingLink.url,
        'https://git.example.test/group/nested/project/-/merge_requests/42',
      );
      final emptyHostingResources = await hostingEmptyResources();
      expect(emptyHostingResources.changeRequests, isEmpty);
      expect(emptyHostingResources.issues, isEmpty);
      expect(emptyHostingResources.remoteReferences, isEmpty);
      final disabledResources = await hostingResourcesStart(
        connection: const NativeHostingConnection(
          id: 'gitlab:disabled-fixture',
          preset: NativeHostingPreset.gitLabSelfManaged,
          login: 'fixture',
          webBaseUrl: 'https://git.example.test',
          apiBaseUrl: 'https://git.example.test/api/v4',
          oauthClientId: 'public-client',
          authentication: NativeHostingAuthentication.oAuth,
          enabled: false,
          refreshEnabled: false,
          capabilities: [
            NativeHostingCapability.changeRequests,
            NativeHostingCapability.issues,
          ],
          credentialIdentity: 'credential:gitlab:disabled-fixture',
          allowSplitOrigin: false,
        ),
        repositoryId: 'group/nested/project',
        page: 1,
        manual: true,
      );
      expect(
        disabledResources.failure,
        NativeHostingResourceFailure.integrationDisabled,
      );
      expect(
        (await hostingResourcesPoll(requestId: BigInt.from(999999))).snapshot,
        isNull,
      );
      expect(
        await hostingResourcesCancel(requestId: BigInt.from(999999)),
        isFalse,
      );
      await hostingResourcesDeactivate(
        connectionId: 'gitlab:disabled-fixture',
        repositoryId: 'group/nested/project',
      );
      final invalidOAuth = await hostingOauthStart(
        connection: const NativeHostingConnection(
          id: 'gitlab:oauth-fixture',
          preset: NativeHostingPreset.gitLabSelfManaged,
          login: '',
          webBaseUrl: 'https://git.example.test',
          apiBaseUrl: 'https://git.example.test/api/v4',
          oauthClientId: '',
          authentication: NativeHostingAuthentication.oAuth,
          enabled: true,
          refreshEnabled: true,
          capabilities: [],
          credentialIdentity: 'credential:gitlab:oauth-fixture',
          allowSplitOrigin: false,
        ),
      );
      expect(invalidOAuth.failure, NativeHostingOAuthFailure.invalidConnection);
      await hostingRuntimeShutdown();

      final document = NativeSettingsDocument(
        appearance: const NativeAppearanceSettings(
          theme: 'system',
          density: 'regular',
          reduceMotion: 'followSystem',
          dateFormat: 'relative',
          gravatarEnabled: false,
          sidebarWidth: 200,
          diffWidth: 420,
          changesUnstagedMode: 'list',
          changesStagedMode: 'tree',
          changesSplitRatio: 550,
          commitFilesMode: 'list',
          inspectionOpenIn: 'window',
          diffWrap: true,
          diffLayout: 'sideBySide',
          diffWhitespace: 'ignoreAll',
          diffContextLines: 6,
          diffIndicators: false,
          diffMinimap: false,
          historyOtherRefs: true,
          windowMaximized: false,
        ),
        recentRepositories: [],
        worktrees: [],
        openWorktrees: [],
        integrations: [],
        hostingConnections: [
          NativeHostingConnectionSettings(
            id: 'gitlab:fixture',
            preset: 'gitlabSelfManaged',
            login: 'fixture',
            webBaseUrl: 'https://git.example.test',
            apiBaseUrl: 'https://git.example.test/api/v4',
            oauthClientId: 'public-client',
            authentication: 'oauth',
            enabled: true,
            refreshEnabled: true,
            capabilities: ['changeRequests', 'issues'],
            credentialIdentity: 'credential:gitlab:fixture',
            allowSplitOrigin: false,
          ),
          // Every name the application writes must pass the native store: a
          // GitHub Enterprise connection through the GitHub CLI was rejected.
          for (final preset in HostingPreset.values)
            for (final authentication in HostingAuthentication.values)
              NativeHostingConnectionSettings(
                id: 'names:${preset.name}:${authentication.name}',
                preset: preset.storageName,
                login: 'fixture',
                webBaseUrl: 'https://git.example.test',
                apiBaseUrl: 'https://git.example.test/api',
                oauthClientId: '',
                authentication: authentication.storageName,
                enabled: true,
                refreshEnabled: true,
                capabilities: const [],
                credentialIdentity:
                    'credential:names:${preset.name}:${authentication.name}',
                allowSplitOrigin: false,
              ),
        ],
        hostingBindings: [],
        hostingExpandedNodes: ['changeRequests'],
        shortcutOverrides: [
          NativeShortcutOverride(
            commandId: 'showHistory',
            binding: 'Ctrl+Alt+H',
          ),
        ],
        repositoryAppearances: [
          NativeRepositoryAppearance(
            identity: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: Uint16List.fromList([47, 114]),
            ),
            icon: 'box',
            color: 'teal',
            name: 'Website',
          ),
        ],
        autoFetch: const NativeAutoFetchSettings(
          enabled: false,
          intervalMinutes: 30,
        ),
        repositoryOptions: [
          NativeRepositoryOptions(
            identity: NativePathIdentity(
              platform: NativePathPlatform.unix,
              units: Uint16List.fromList([47, 114]),
            ),
            autoFetch: true,
          ),
        ],
        tabGroups: [
          NativeTabGroup(
            name: 'Client work',
            color: 'violet',
            icon: 'server',
            collapsed: true,
            members: [
              NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: Uint16List.fromList([47, 114]),
              ),
            ],
          ),
        ],
        remoteProfiles: const [
          NativeRemoteHostProfile(
            id: '123e4567-e89b-42d3-a456-426614174000',
            label: 'Build server',
            alias: 'build-01',
            verified: NativeRemoteVerifiedIdentity(
              storeId: '0123456789abcdef0123456789abcdef',
              accountUid: '1000',
              accountName: 'builder',
            ),
            writesAllowed: false,
            autoInstallHelper: true,
          ),
        ],
        remoteWorkspacesEnabled: true,
      );
      final settingsPath =
          '${fixture.root.path}${Platform.pathSeparator}settings.json';
      final saved = await applicationSettingsSave(
        path: settingsPath,
        document: document,
      );
      expect(saved.failure, isNull);
      expect(saved.saved, isTrue);
      final loaded = await applicationSettingsLoad(path: settingsPath);
      expect(loaded.failure, isNull);
      expect(loaded.state, NativeSettingsLoadState.loaded);
      expect(
        loaded.document!.hostingConnections,
        hasLength(
          1 + HostingPreset.values.length * HostingAuthentication.values.length,
        ),
      );
      expect(loaded.document!.remoteProfiles, document.remoteProfiles);
      expect(loaded.document!.remoteWorkspacesEnabled, isTrue);
      // Every appearance name the application writes must pass the native
      // store: Reduce and Full motion were once rejected on every save.
      NativeAppearanceSettings appearance({
        String theme = 'system',
        String density = 'regular',
        String reduceMotion = 'followSystem',
        String layout = 'list',
        String openIn = 'pane',
        staging.DiffViewLayout diffLayout = staging.DiffViewLayout.unified,
        staging.DiffWhitespace diffWhitespace = staging.DiffWhitespace.preserve,
      }) => NativeAppearanceSettings(
        theme: theme,
        density: density,
        reduceMotion: reduceMotion,
        dateFormat: 'relative',
        gravatarEnabled: false,
        sidebarWidth: 200,
        diffWidth: 420,
        changesUnstagedMode: layout,
        changesStagedMode: layout,
        changesSplitRatio: 550,
        commitFilesMode: layout,
        inspectionOpenIn: openIn,
        diffWrap: false,
        diffLayout: diffLayout.name,
        diffWhitespace: diffWhitespace.name,
        diffContextLines: 3,
        diffIndicators: true,
        diffMinimap: true,
        historyOtherRefs: false,
        windowMaximized: false,
      );
      final appearances = [
        for (final theme in StoredAppearanceNames.themes)
          appearance(theme: theme),
        for (final density in StoredAppearanceNames.densities)
          appearance(density: density),
        for (final motion in StoredAppearanceNames.reduceMotion)
          appearance(reduceMotion: motion),
        for (final layout in StoredAppearanceNames.fileLayouts)
          appearance(layout: layout),
        for (final openIn in StoredAppearanceNames.inspectionOpenIn)
          appearance(openIn: openIn),
        for (final layout in staging.DiffViewLayout.values)
          appearance(diffLayout: layout),
        for (final whitespace in staging.DiffWhitespace.values)
          appearance(diffWhitespace: whitespace),
      ];
      for (final candidate in appearances) {
        final result = await applicationSettingsSave(
          path: settingsPath,
          document: NativeSettingsDocument(
            appearance: candidate,
            recentRepositories: const [],
            worktrees: const [],
            openWorktrees: const [],
            integrations: const [],
            hostingConnections: const [],
            hostingBindings: const [],
            hostingExpandedNodes: const [],
            shortcutOverrides: const [],
            repositoryAppearances: const [],
            autoFetch: const NativeAutoFetchSettings(
              enabled: true,
              intervalMinutes: 15,
            ),
            repositoryOptions: const [],
            tabGroups: const [],
            remoteProfiles: const [],
            remoteWorkspacesEnabled: false,
          ),
        );
        expect(result.failure, isNull);
        final reloaded = await applicationSettingsLoad(path: settingsPath);
        expect(reloaded.document!.appearance, candidate);
      }
      expect(loaded.document!.autoFetch.enabled, isFalse);
      expect(loaded.document!.autoFetch.intervalMinutes, 30);
      expect(loaded.document!.repositoryOptions.single.autoFetch, isTrue);
      expect(loaded.document!.repositoryAppearances.single.icon, 'box');
      expect(loaded.document!.repositoryAppearances.single.name, 'Website');
      expect(loaded.document!.tabGroups.single.name, 'Client work');
      expect(loaded.document!.tabGroups.single.collapsed, isTrue);
      expect(loaded.document!.tabGroups.single.icon, 'server');
      expect(loaded.document!.tabGroups.single.members, hasLength(1));
      expect(loaded.document!.hostingExpandedNodes, ['changeRequests']);
      expect(loaded.document!.shortcutOverrides.single.binding, 'Ctrl+Alt+H');
      expect(loaded.document!.appearance.changesUnstagedMode, 'list');
      expect(loaded.document!.appearance.changesStagedMode, 'tree');
      expect(loaded.document!.appearance.changesSplitRatio, 550);
      expect(loaded.document!.appearance.commitFilesMode, 'list');
      expect(loaded.document!.appearance.inspectionOpenIn, 'window');
      expect(loaded.document!.appearance.diffLayout, 'sideBySide');
      expect(loaded.document!.appearance.diffContextLines, 6);
      expect(loaded.document!.appearance.diffWrap, isTrue);

      final recoveryPath =
          '${fixture.root.path}${Platform.pathSeparator}recovery';
      final recovery = await applicationRecoveryBegin(directory: recoveryPath);
      expect(recovery.failure, isNull);
      expect(recovery.previousShutdown, NativePreviousShutdown.clean);
      final inspection = await applicationRecoveryInspectRepository(
        path: fixture.worktree.path,
      );
      expect(inspection.failure, isNull);
      expect(inspection.state, isNull);
      final finished = await applicationRecoveryFinishClean(
        directory: recoveryPath,
        document: document,
      );
      expect(finished.failure, isNull);
      expect(finished.completed, isTrue);
    } finally {
      await fixture.dispose();
    }
    await _verifyApplyOnlyRevertBridge(nativeWait);
    await _verifyMissingWorktreeRemovalBridge(nativeWait);
    await _verifySelectedUntrackedStagingBridge(nativeWait);
    await _verifyFreshWholeFileStagingBridge(nativeWait);
    await _verifyCommitArchiveBridge(nativeWait);
    RustLib.dispose();
  }, timeout: Timeout(nativeTestTimeout));
}

Future<void> _verifySelectedUntrackedStagingBridge(Duration wait) async {
  final fixture = await GitFixture.create();
  BigInt? sessionId;
  final generation = BigInt.from(83);
  try {
    await fixture.writeBytes('already-staged.txt', 'keep\n'.codeUnits);
    await fixture.run(['add', 'already-staged.txt']);
    await fixture.writeBytes('docs/readme.md', 'readme\n'.codeUnits);
    await fixture.writeBytes('docs/nested/plan.md', 'plan\n'.codeUnits);
    await fixture.writeBytes('unselected.txt', 'leave\n'.codeUnits);
    for (final name in ['app.apk', 'app.aab']) {
      final file = await File(
        '${fixture.worktree.path}/$name',
      ).open(mode: FileMode.write);
      try {
        await file.truncate(65 * 1024 * 1024);
      } finally {
        await file.close();
      }
    }
    final opened = await repositorySessionOpen(
      path: fixture.worktree.path,
      generation: generation,
    );
    expect(opened.failure, isNull);
    sessionId = opened.session!.sessionId;
    final deadline = DateTime.now().add(wait);
    var ready = false;
    while (!ready && DateTime.now().isBefore(deadline)) {
      final events = await repositorySessionEvents(
        sessionId: sessionId,
        generation: generation,
        maximumEvents: 32,
      );
      expect(events.failure, isNull);
      ready = events.events.any(
        (event) => event.snapshot?.phase == NativeRepositoryPhase.ready,
      );
      if (!ready) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    expect(ready, isTrue);
    final large = await repositorySessionWorkingDiffLoad(
      sessionId: sessionId,
      generation: generation,
      options: NativeWorkingDiffOptions(
        side: NativeStagingSide.unstaged,
        oldPath: null,
        newPath: Uint8List.fromList('app.apk'.codeUnits),
        contextLines: 3,
        whitespace: NativeDiffWhitespace.preserve,
        layout: NativeDiffLayout.unified,
        maximumRows: 32,
        forceText: false,
      ),
    );
    expect(large.failure, isNull);
    expect(
      large.page!.rows.any((row) => row.kind == NativeDiffRowKind.tooLarge),
      isTrue,
    );
    expect(large.page!.rows.every((row) => !row.selectable), isTrue);
    final working = await repositorySessionWorkingDiffLoad(
      sessionId: sessionId,
      generation: generation,
      options: const NativeWorkingDiffOptions(
        side: NativeStagingSide.unstaged,
        oldPath: null,
        newPath: null,
        contextLines: 3,
        whitespace: NativeDiffWhitespace.preserve,
        layout: NativeDiffLayout.unified,
        maximumRows: 32,
        forceText: false,
      ),
    );
    expect(working.failure, isNull);
    final staged = await repositorySessionStagingExecute(
      sessionId: sessionId,
      generation: generation,
      request: NativeStagingRequest(
        requestId: working.page!.requestId,
        side: NativeStagingSide.unstaged,
        scope: NativeStagingScope.files,
        paths: [
          Uint8List.fromList('docs/readme.md'.codeUnits),
          Uint8List.fromList('docs/nested/plan.md'.codeUnits),
        ],
        rowIds: [],
      ),
    );
    expect(staged.state, NativeStagingExecutionState.completed);
    expect((await fixture.run(['show', ':docs/readme.md'])).stdout, 'readme\n');
    expect(
      (await fixture.run(['show', ':docs/nested/plan.md'])).stdout,
      'plan\n',
    );
    expect(
      (await fixture.run(['show', ':already-staged.txt'])).stdout,
      'keep\n',
    );
    expect(
      (await fixture.run(['ls-files', '--', 'unselected.txt'])).stdout,
      '',
    );
  } finally {
    if (sessionId != null) {
      await repositorySessionClose(
        sessionId: sessionId,
        generation: generation,
      );
    }
    await fixture.dispose();
  }
}

Future<void> _verifyApplyOnlyRevertBridge(Duration wait) async {
  final fixture = await GitFixture.create();
  BigInt? sessionId;
  final generation = BigInt.from(81);
  try {
    await fixture.writeBytes('tracked.txt', 'base\n'.codeUnits);
    await fixture.commitAll('Base');
    await fixture.writeBytes('tracked.txt', 'changed\n'.codeUnits);
    await fixture.commitAll('Change');
    final head = (await fixture.run([
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();
    final opened = await repositorySessionOpen(
      path: fixture.worktree.path,
      generation: generation,
    );
    expect(opened.failure, isNull);
    sessionId = opened.session!.sessionId;
    final deadline = DateTime.now().add(wait);
    var ready = false;
    while (!ready && DateTime.now().isBefore(deadline)) {
      final events = await repositorySessionEvents(
        sessionId: sessionId,
        generation: generation,
        maximumEvents: 32,
      );
      expect(events.failure, isNull);
      ready = events.events.any(
        (event) => event.snapshot?.phase == NativeRepositoryPhase.ready,
      );
      if (!ready) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    expect(ready, isTrue);
    final request = NativeHistoryMutationRequest(
      kind: NativeHistoryMutationKind.revert,
      targets: [head],
      mergeMode: NativeHistoryMergeMode.fastForwardIfPossible,
      acknowledgePublishedHistory: false,
      noCommit: true,
    );
    final executionDeadline = DateTime.now().add(wait);
    NativeHistoryMutationExecutionResult result;
    do {
      final preview = await repositorySessionHistoryMutationPreview(
        sessionId: sessionId,
        generation: generation,
        request: request,
      );
      expect(preview.failure, isNull);
      expect(preview.preview!.noCommit, isTrue);
      result = await repositorySessionHistoryMutationExecute(
        sessionId: sessionId,
        generation: generation,
        token: preview.preview!.token,
      );
      if (result.state == NativeHistoryMutationExecutionState.stale) {
        // Initial watcher reconciliation can invalidate a preview after readiness.
        // Prove refusal had no effect before previewing the same immutable target again.
        expect(result.failure?.kind, NativeHistoryMutationFailureKind.stale);
        expect(
          (await fixture.run(['rev-parse', 'HEAD'])).stdout.toString().trim(),
          head,
        );
        expect((await fixture.run(['status', '--porcelain'])).stdout, isEmpty);
      }
    } while (result.state == NativeHistoryMutationExecutionState.stale &&
        DateTime.now().isBefore(executionDeadline));
    expect(result.state, NativeHistoryMutationExecutionState.completed);
    expect(
      (await fixture.run(['rev-parse', 'HEAD'])).stdout.toString().trim(),
      head,
    );
    expect(
      (await fixture.run(['status', '--porcelain'])).stdout,
      'M  tracked.txt\n',
    );
  } finally {
    if (sessionId != null) {
      await repositorySessionClose(
        sessionId: sessionId,
        generation: generation,
      );
    }
    await fixture.dispose();
  }
}

Future<void> _verifyMissingWorktreeRemovalBridge(Duration wait) async {
  final fixture = await GitFixture.create();
  BigInt? sessionId;
  final generation = BigInt.from(82);
  try {
    await fixture.run(['commit', '--allow-empty', '-qm', 'Base']);
    final missing = Directory('${fixture.root.path}/missing');
    final other = Directory('${fixture.root.path}/other-missing');
    for (final directory in [missing, other]) {
      await fixture.run(['worktree', 'add', '--detach', directory.path]);
      await directory.delete(recursive: true);
    }
    final opened = await repositorySessionOpen(
      path: fixture.worktree.path,
      generation: generation,
    );
    expect(opened.failure, isNull);
    sessionId = opened.session!.sessionId;
    final deadline = DateTime.now().add(wait);
    var ready = false;
    while (!ready && DateTime.now().isBefore(deadline)) {
      final events = await repositorySessionEvents(
        sessionId: sessionId,
        generation: generation,
        maximumEvents: 32,
      );
      expect(events.failure, isNull);
      ready = events.events.any(
        (event) => event.snapshot?.phase == NativeRepositoryPhase.ready,
      );
      if (!ready) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    expect(ready, isTrue);
    final before = await repositorySessionExtensions(
      sessionId: sessionId,
      generation: generation,
    );
    expect(before.failure, isNull);
    expect(before.inventory!.worktrees, hasLength(3));
    final selected = before.inventory!.worktrees.singleWhere(
      (entry) =>
          String.fromCharCodes(
            entry.worktreeRoot.units,
          ).split(RegExp(r'[/\\]')).last ==
          'missing',
    );
    final result = await repositorySessionExtensionExecute(
      sessionId: sessionId,
      generation: generation,
      request: NativeExtensionMutationRequest(
        kind: NativeExtensionMutationKind.worktreeDelete,
        worktreeRoot: selected.worktreeRoot,
      ),
    );
    expect(result.state, NativeExtensionMutationState.completed);
    expect(result.failure, isNull);
    final after = await repositorySessionExtensions(
      sessionId: sessionId,
      generation: generation,
    );
    expect(after.failure, isNull);
    expect(after.inventory!.worktrees, hasLength(2));
    expect(
      after.inventory!.worktrees.any(
        (entry) =>
            String.fromCharCodes(
              entry.worktreeRoot.units,
            ).split(RegExp(r'[/\\]')).last ==
            'missing',
      ),
      isFalse,
    );
    expect(
      after.inventory!.worktrees.any(
        (entry) =>
            String.fromCharCodes(
              entry.worktreeRoot.units,
            ).split(RegExp(r'[/\\]')).last ==
            'other-missing',
      ),
      isTrue,
    );
  } finally {
    if (sessionId != null) {
      await repositorySessionClose(
        sessionId: sessionId,
        generation: generation,
      );
    }
    await fixture.dispose();
  }
}

Future<void> _verifyFreshWholeFileStagingBridge(Duration wait) async {
  final fixture = await GitFixture.create();
  final service = RepositorySessionService(NativeRepositorySessionRepository());
  try {
    await fixture.writeBytes('tracked.txt', 'base\n'.codeUnits);
    await fixture.commitAll('base');
    await fixture.writeBytes('tracked.txt', 'edited\n'.codeUnits);
    await service.open(fixture.worktree.path);
    final deadline = DateTime.now().add(wait);
    while (service.current?.snapshot.phase !=
            repository_state.RepositoryPhase.ready &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      service.current?.snapshot.phase,
      repository_state.RepositoryPhase.ready,
    );
    expect(
      await NativeRepositorySessionRepository().stagingPhase(
        service.activeTab!.session!.identity,
      ),
      staging.StagingPhase.idle,
    );
    Future<staging.StagingExecutionResult> execute(staging.StagingSide side) =>
        service.workingCopy.stage(
          staging.StagingRequest(
            requestId: BigInt.zero,
            side: side,
            scope: staging.StagingScope.all,
          ),
        );
    final staged = await execute(staging.StagingSide.unstaged);
    expect(staged.state, staging.StagingExecutionState.completed);
    final lock = File(
      '${fixture.worktree.path}${Platform.pathSeparator}.git${Platform.pathSeparator}index.lock',
    );
    await lock.writeAsString('other operation');
    final locked = await execute(staging.StagingSide.staged);
    expect(locked.state, staging.StagingExecutionState.failed);
    expect(locked.diagnostic?.code, staging.StagingFailureCode.indexLocked);
    expect(locked.diagnostic?.gitVersion, matches(r'^\d+\.\d+\.\d+$'));
    expect(await lock.readAsString(), 'other operation');
    await lock.delete();
    final unstaged = await execute(staging.StagingSide.staged);
    expect(unstaged.state, staging.StagingExecutionState.completed);
    expect((await fixture.run(['diff', '--cached', '--name-only'])).stdout, '');
    expect(
      await File(
        '${fixture.worktree.path}${Platform.pathSeparator}tracked.txt',
      ).readAsString(),
      'edited\n',
    );
  } finally {
    await service.dispose();
    await fixture.dispose();
  }
}

Future<void> _verifyCommitArchiveBridge(Duration wait) async {
  final fixture = await GitFixture.create();
  final service = RepositorySessionService(NativeRepositorySessionRepository());
  final output = await Directory.systemTemp.createTemp('gitlama-archive-');
  try {
    await fixture.writeBytes('src/main.txt', 'snapshot\n'.codeUnits);
    await fixture.commitAll('base');
    final commit = ((await fixture.run(['rev-parse', 'HEAD'])).stdout as String)
        .trim();
    await service.open(fixture.worktree.path);
    final deadline = DateTime.now().add(wait);
    while (service.current?.snapshot.phase !=
            repository_state.RepositoryPhase.ready &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final destination = '${output.path}${Platform.pathSeparator}snap.zip';
    final seen = <CommitArchiveState>[];
    final status = await service.archives.save(
      commit: commit,
      prefix: 'snap',
      destination: destination,
      onProgress: (status) => seen.add(status.state),
      isCanceled: () => false,
    );
    expect(status.state, CommitArchiveState.completed);
    expect(seen.last, CommitArchiveState.completed);
    final bytes = await File(destination).readAsBytes();
    expect(bytes.length, status.archiveBytes);
    expect(bytes.take(2), 'PK'.codeUnits);
    expect(String.fromCharCodes(bytes), contains('snap/src/main.txt'));

    final canceled = '${output.path}${Platform.pathSeparator}canceled.zip';
    await expectLater(
      service.archives.save(
        commit: commit,
        prefix: 'snap',
        destination: canceled,
        onProgress: (_) {},
        isCanceled: () => true,
      ),
      throwsA(
        isA<CommitArchiveException>().having(
          (error) => error.code,
          'code',
          CommitArchiveFailureCode.canceled,
        ),
      ),
    );
    expect(File(canceled).existsSync(), isFalse);
    expect(output.listSync().map((entry) => entry.path), [destination]);
  } finally {
    await service.dispose();
    await output.delete(recursive: true);
    await fixture.dispose();
  }
}
