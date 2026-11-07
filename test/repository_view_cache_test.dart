import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/repository_view_cache_codec.dart';
import 'package:gitlama/repositories/impl/private_entry_store.dart';
import 'package:gitlama/repositories/impl/coded_cache_repositories.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/repository_view_cache.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/services/repository_view_cache_service.dart';

void main() {
  NativePathIdentity path(String value, {bool windows = false}) =>
      NativePathIdentity(
        platform: windows
            ? NativePathPlatform.windows
            : NativePathPlatform.unix,
        units: value.codeUnits,
      );

  RepositoryViewCacheEntry entry() => RepositoryViewCacheEntry(
    refs: RepositoryRefs(
      branches: [
        RepositoryReference(
          name: 'main'.codeUnits,
          target: 'a' * 40,
          head: true,
          published: true,
          upstream: 'refs/remotes/origin/main'.codeUnits,
          ahead: 2,
          behind: 3,
        ),
        // Reference names are bytes; they need not be valid UTF-8.
        const RepositoryReference(
          name: [0xff, 0xfe, 0x2f, 0x78],
          target: 'b',
          upstreamGone: true,
        ),
      ],
      remotes: [
        RepositoryRemote(
          name: 'origin'.codeUnits,
          displayUrl: 'example.test/repository'.codeUnits,
          branches: [RepositoryReference(name: 'topic'.codeUnits, target: 'c')],
        ),
      ],
      tags: [RepositoryReference(name: 'v1'.codeUnits, target: 'd')],
      stashes: [
        RepositoryStash(
          selector: 'stash@{0}'.codeUnits,
          objectId: 'e',
          subject: utf8.encode('WIP 🧪'),
        ),
      ],
      truncated: true,
    ),
    refCounts: const RepositoryRefCounts(
      branches: 2,
      remotes: 1,
      tags: 1,
      stashes: 1,
      worktrees: 4,
    ),
    status: RepositoryStatus(
      workingTree: WorkingTreeState.dirty,
      branchName: 'main'.codeUnits,
      headObjectId: 'a' * 40,
      upstream: 'origin/main'.codeUnits,
      ahead: BigInt.parse('18446744073709551615'),
      behind: BigInt.one,
      entries: [
        RepositoryStatusEntry(
          kind: StatusEntryKind.rename,
          path: path('lib/new name.dart'),
          source: path('lib/old.dart'),
          index: ChangeKind.renamed,
          worktree: ChangeKind.modified,
        ),
        RepositoryStatusEntry(
          kind: StatusEntryKind.untracked,
          // A lone surrogate is a valid Windows path unit.
          path: NativePathIdentity(
            platform: NativePathPlatform.windows,
            units: const [0x43, 0x3a, 0x5c, 0xd800, 0x61],
          ),
          index: ChangeKind.unmodified,
          worktree: ChangeKind.unmodified,
        ),
      ],
      totalEntries: BigInt.two,
      entriesTruncated: false,
      operations: const [
        RepositoryOperationState(
          kind: RepositoryOperationKind.rebase,
          current: 2,
          total: 5,
        ),
        RepositoryOperationState(kind: RepositoryOperationKind.bisect),
      ],
    ),
    history: cacheableHistoryPage(
      HistoryPage(
        requestId: BigInt.from(12),
        complete: true,
        totalRows: 30100,
        offset: 0,
        rows: [
          HistoryTopologyRow(
            objectId: 'a' * 40,
            parents: ['b' * 40, 'c' * 40],
            refs: ['refs/heads/main'.codeUnits],
            refCount: 3,
            refsTruncated: true,
            lane: 2,
            shape: 1,
            subject: utf8.encode('Merge 🧪'),
            author: 'Ada'.codeUnits,
            avatarHash: 'hash',
            authorTime: 1789776000,
            current: true,
            selected: true,
            lit: true,
          ),
          const HistoryTopologyRow(
            objectId: 'wip',
            parents: [],
            refs: [],
            lane: 0,
            shape: 5,
            metadataFailure: HistoryMetadataFailure.subjectTooLarge,
            wipChangedFiles: 4,
            wipStagedFiles: 1,
          ),
        ],
        segments: const [
          HistoryTopologySegment(
            fromRow: 0,
            toRow: 900,
            lit: true,
            fromObjectId: 'a',
            toObjectId: 'b',
            parentOrdinal: 1,
            fromLane: 2,
            toLane: 0,
            kind: 3,
          ),
        ],
        laneCount: 3,
        payloadBytes: 99,
        currentObjectId: 'a' * 40,
        selectedObjectIds: ['a' * 40],
        lightingActive: true,
      ),
    ),
  );

  test('an entry survives storage unchanged', () {
    final original = entry();
    final restored = decodeRepositoryView(encodeRepositoryView(original))!;

    final branch = restored.refs!.branches.first;
    expect(branch.name, 'main'.codeUnits);
    expect(branch.target, 'a' * 40);
    expect(branch.head, isTrue);
    expect(branch.published, isTrue);
    expect(branch.upstream, 'refs/remotes/origin/main'.codeUnits);
    expect([branch.ahead, branch.behind, branch.upstreamGone], [2, 3, false]);
    expect(restored.refs!.branches.last.name, [0xff, 0xfe, 0x2f, 0x78]);
    expect(restored.refs!.branches.last.upstream, isNull);
    expect(restored.refs!.branches.last.upstreamGone, isTrue);
    final remote = restored.refs!.remotes.single;
    expect(remote.name, 'origin'.codeUnits);
    expect(remote.displayUrl, 'example.test/repository'.codeUnits);
    expect(remote.branches.single.name, 'topic'.codeUnits);
    expect(restored.refs!.tags.single.target, 'd');
    final stash = restored.refs!.stashes.single;
    expect(stash.selector, 'stash@{0}'.codeUnits);
    expect(stash.objectId, 'e');
    expect(stash.subject, utf8.encode('WIP 🧪'));
    expect(restored.refs!.truncated, isTrue);
    final counts = restored.refCounts!;
    expect(
      [
        counts.branches,
        counts.remotes,
        counts.tags,
        counts.stashes,
        counts.worktrees,
      ],
      [2, 1, 1, 1, 4],
    );

    final status = restored.status!;
    expect(status.workingTree, WorkingTreeState.dirty);
    expect(status.branchName, 'main'.codeUnits);
    expect(status.headObjectId, 'a' * 40);
    expect(status.upstream, 'origin/main'.codeUnits);
    expect(status.ahead, BigInt.parse('18446744073709551615'));
    expect(status.behind, BigInt.one);
    expect(status.totalEntries, BigInt.two);
    expect(status.entriesTruncated, isFalse);
    final renamed = status.entries.first;
    expect(renamed.kind, StatusEntryKind.rename);
    expect(renamed.path, path('lib/new name.dart'));
    expect(renamed.source, path('lib/old.dart'));
    expect(renamed.index, ChangeKind.renamed);
    expect(renamed.worktree, ChangeKind.modified);
    final untracked = status.entries.last;
    expect(untracked.path.platform, NativePathPlatform.windows);
    expect(untracked.path.units, [0x43, 0x3a, 0x5c, 0xd800, 0x61]);
    expect(untracked.source, isNull);
    expect(status.operations.first.kind, RepositoryOperationKind.rebase);
    expect(status.operations.first.current, 2);
    expect(status.operations.first.total, 5);
    expect(status.operations.last.current, isNull);

    final history = restored.history!;
    expect(history.requestId, cachedHistoryRequestId);
    expect(history.complete, isFalse);
    expect(history.totalRows, 30100);
    expect(history.laneCount, 3);
    expect(history.currentObjectId, 'a' * 40);
    expect(history.selectedObjectIds, isEmpty);
    expect(history.lightingActive, isFalse);
    final merge = history.rows.first;
    expect(merge.objectId, 'a' * 40);
    expect(merge.parents, ['b' * 40, 'c' * 40]);
    expect(merge.refs.single, 'refs/heads/main'.codeUnits);
    expect([merge.refCount, merge.refsTruncated], [3, true]);
    expect([merge.lane, merge.shape], [2, 1]);
    expect(merge.subject, utf8.encode('Merge 🧪'));
    expect(merge.author, 'Ada'.codeUnits);
    expect(merge.avatarHash, 'hash');
    expect(merge.authorTime, 1789776000);
    expect(merge.current, isTrue);
    expect([merge.selected, merge.lit], [false, false]);
    final wip = history.rows.last;
    expect(wip.metadataFailure, HistoryMetadataFailure.subjectTooLarge);
    expect([wip.wipChangedFiles, wip.wipStagedFiles], [4, 1]);
    final segment = history.segments.single;
    expect([segment.fromRow, segment.toRow, segment.lit], [0, 900, true]);
    expect(
      [
        segment.fromObjectId,
        segment.toObjectId,
        segment.parentOrdinal,
        segment.fromLane,
        segment.toLane,
        segment.kind,
      ],
      ['a', 'b', 1, 2, 0, 3],
    );
  });

  test('only a complete first page without a search may stand in later', () {
    HistoryPage page({
      bool complete = true,
      int offset = 0,
      bool queryActive = false,
      HistoryBranchFilter branchFilter = HistoryBranchFilter.none,
      int collapsedCommits = 0,
      bool otherRefs = false,
    }) => HistoryPage(
      requestId: BigInt.one,
      complete: complete,
      totalRows: 1,
      offset: offset,
      rows: const [
        HistoryTopologyRow(
          objectId: 'a',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ],
      laneCount: 1,
      payloadBytes: 0,
      queryActive: queryActive,
      branchFilter: branchFilter,
      collapsedCommits: collapsedCommits,
      otherRefs: otherRefs,
    );
    expect(isCacheableHistoryPage(page()), isTrue);
    expect(isCacheableHistoryPage(page(complete: false)), isFalse);
    expect(isCacheableHistoryPage(page(offset: 512)), isFalse);
    expect(isCacheableHistoryPage(page(queryActive: true)), isFalse);
    // A filtered page stands in for the same filter and names it.
    final filtered = page(
      branchFilter: HistoryBranchFilter(['refs/heads/main']),
    );
    expect(isCacheableHistoryPage(filtered), isTrue);
    final restored = decodeRepositoryView(
      encodeRepositoryView(
        RepositoryViewCacheEntry(history: cacheableHistoryPage(filtered)),
      ),
    )!;
    expect(restored.history!.branchFilter.references, ['refs/heads/main']);
    expect(restored.history!.otherRefs, isFalse);
    // A page names whether it shows other references, so it stands in only
    // for the same reference scope.
    final withOtherRefs = decodeRepositoryView(
      encodeRepositoryView(
        RepositoryViewCacheEntry(
          history: cacheableHistoryPage(page(otherRefs: true)),
        ),
      ),
    )!;
    expect(withOtherRefs.history!.otherRefs, isTrue);
    expect(isCacheableHistoryPage(page(collapsedCommits: 2)), isFalse);
  });

  group('an entry that cannot be used is absent', () {
    Map<String, Object?> document() =>
        jsonDecode(utf8.decode(encodeRepositoryView(entry())))
            as Map<String, Object?>;
    Uint8List bytes(Object? value) =>
        Uint8List.fromList(utf8.encode(jsonEncode(value)));

    test('another schema, as after an update without migration', () {
      for (final schema in [0, repositoryViewCacheSchema + 1, '1', null]) {
        expect(
          decodeRepositoryView(bytes(document()..['schema'] = schema)),
          isNull,
        );
      }
      expect(
        decodeRepositoryView(bytes(document()..['format'] = 'other')),
        isNull,
      );
    });

    test('a truncated or foreign file', () {
      final encoded = encodeRepositoryView(entry());
      expect(decodeRepositoryView(Uint8List(0)), isNull);
      expect(
        decodeRepositoryView(encoded.sublist(0, encoded.length ~/ 2)),
        isNull,
      );
      expect(decodeRepositoryView([0xff, 0xfe, 0x00, 0x01]), isNull);
      expect(decodeRepositoryView(bytes([1, 2, 3])), isNull);
      expect(decodeRepositoryView(bytes('text')), isNull);
    });

    test('values this version does not know', () {
      final unknownState = document();
      (unknownState['status']! as Map<String, Object?>)['workingTree'] =
          'rebasing';
      expect(decodeRepositoryView(bytes(unknownState)), isNull);

      final wrongType = document();
      (wrongType['refs']! as Map<String, Object?>)['branches'] = 'main';
      expect(decodeRepositoryView(bytes(wrongType)), isNull);

      final shortRow = document();
      ((shortRow['history']! as Map<String, Object?>)['rows']!
          as List<Object?>)[0] = [
        'a',
      ];
      expect(decodeRepositoryView(bytes(shortRow)), isNull);

      final impossibleTotal = document();
      (impossibleTotal['history']! as Map<String, Object?>)['totalRows'] = 1;
      expect(decodeRepositoryView(bytes(impossibleTotal)), isNull);

      final oddPath = document();
      final entries =
          (oddPath['status']! as Map<String, Object?>)['entries']!
              as List<Object?>;
      ((entries[0]! as List<Object?>)[1]! as Map<String, Object?>)['units'] =
          base64.encode([1, 2, 3]);
      expect(decodeRepositoryView(bytes(oddPath)), isNull);
    });

    test('an entry without content', () {
      expect(
        decodeRepositoryView(
          bytes({
            'format': 'gitlama.repository-view',
            'schema': repositoryViewCacheSchema,
          }),
        ),
        isNull,
      );
    });
  });

  test('remote path never becomes a local cache entry', () async {
    final local = path('/work/shared');
    final remote = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/work/shared'.codeUnits,
      remote: const RemoteAuthority(
        profileId: '123e4567-e89b-42d3-a456-426614174000',
        storeId: '0123456789abcdef0123456789abcdef',
        accountUid: '1000',
      ),
    );
    final storage = _RecordingViewCacheRepository()
      ..entries[local] = encodeRepositoryView(entry())
      ..entries[remote] = encodeRepositoryView(entry());
    final cache = RepositoryViewCacheService(
      CodedRepositoryViewCacheRepository(
        storage,
        runInBackground: <T>(work) async => work(),
      ),
      persistDelay: Duration.zero,
    );

    await cache.warm([local, remote]);
    expect(cache.entry(local), isNotNull);
    expect(cache.entry(remote), isNull);

    cache.rememberHistory(remote, entry().history!);
    cache.forget(remote);
    await cache.flush();
    expect(cache.entry(remote), isNull);
    expect(cache.entry(local), isNotNull);
    expect(storage.touched, isNot(contains(remote)));
    expect(storage.touched, [local]);
    await cache.dispose();
  });
}

final class _RecordingViewCacheRepository implements PrivateEntryStore {
  final Map<NativePathIdentity, Uint8List> entries = {};
  final List<NativePathIdentity> touched = [];

  @override
  Future<Uint8List?> read(NativePathIdentity repository) async {
    touched.add(repository);
    return entries[repository];
  }

  @override
  Future<void> write(NativePathIdentity repository, Uint8List bytes) async {
    touched.add(repository);
    entries[repository] = bytes;
  }

  @override
  Future<void> remove(NativePathIdentity repository) async {
    touched.add(repository);
    entries.remove(repository);
  }
}
