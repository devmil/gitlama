import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/inspector/inspector_navigation.dart';
import 'package:gitlama/services/inspector/inspector_service.dart';
import 'package:gitlama/services/inspector/lens_availability.dart';

String _id(String letter) => letter * 40;
final _a = _id('a');
final _b = _id('b');
final _c = _id('c');
final _identity = RepositorySessionIdentity(
  nativeId: BigInt.one,
  generation: 1,
);

CommitFileChange _change(
  String path, {
  CommitFileChangeKind kind = CommitFileChangeKind.modified,
  String? oldPath,
  int mode = 0x81a4,
}) => CommitFileChange(
  oldMode: mode,
  newMode: mode,
  kind: kind,
  oldPath: (oldPath ?? path).codeUnits,
  newPath: kind == CommitFileChangeKind.deleted ? const [] : path.codeUnits,
);

/// A repository answering the inspector's reads from in-memory commits.
final class _Repository implements RepositorySessionRepository {
  final Map<String, List<String>> parents = {};
  final Map<String, List<CommitFileChange>> files = {};
  final List<String> calls = [];
  final List<({String commit, String? firstParent, DiffLoadOptions options})>
  diffs = [];
  final List<({BigInt requestId, int offset})> blamePages = [];
  final List<({String commit, String? firstParent})> inspections = [];
  Map<String, Completer<void>> gates = {};
  var tooLargeAllChanges = false;
  var failInspect = false;
  var failNextHistoryPage = false;
  var _request = 0;
  var blameRows = 513;
  List<PathHistoryEntry> historyEntries = const [];
  int? historyNextOffset;

  Future<void> _gate(String key) async {
    final gate = gates[key];
    if (gate != null) await gate.future;
  }

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) async {
    calls.add('inspect:${commit[0]}');
    inspections.add((commit: commit, firstParent: firstParent));
    await _gate('inspect:$commit');
    if (failInspect) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.missingObject),
      );
    }
    return CommitInspection(
      detail: CommitIdentityDetail(
        commit: commit,
        tree: 'tree',
        parents: parents[commit] ?? const [],
        author: 'A'.codeUnits,
        authorTime: 1,
        authorTimezone: const [],
        committer: 'A'.codeUnits,
        committerTime: 1,
        committerTimezone: const [],
        message: commit.substring(0, 1).codeUnits,
      ),
      // Without a base the native read compares with the empty tree.
      files: firstParent == null && (parents[commit]?.isNotEmpty ?? false)
          ? const []
          : files[commit] ?? const [],
    );
  }

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = 512,
  }) async {
    calls.add('diff:${commit[0]}');
    diffs.add((commit: commit, firstParent: firstParent, options: options));
    await _gate('diff:$commit');
    if (tooLargeAllChanges && options.newPath == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.tooLarge),
      );
    }
    return DiffPage(
      requestId: BigInt.from(++_request),
      layout: options.layout,
      totalRows: 600,
      offset: 0,
      rows: [
        DiffDisplayRow(
          stableId: 'row',
          kind: DiffRowKind.context,
          text: '${firstParent?[0] ?? 'root'}->${commit[0]}'.codeUnits,
        ),
      ],
      payloadBytes: 1,
    );
  }

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => DiffPage(
    requestId: requestId,
    layout: DiffViewLayout.unified,
    totalRows: 600,
    offset: offset,
    rows: const [
      DiffDisplayRow(stableId: 'later', kind: DiffRowKind.context, text: []),
    ],
    payloadBytes: 1,
  );

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) async {
    calls.add('content:${commit[0]}');
    return [...commit.substring(0, 1).codeUnits, ...path];
  }

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) async {
    calls.add('tree:${String.fromCharCodes(directory ?? const [])}@$offset');
    final prefix = directory == null
        ? ''
        : '${String.fromCharCodes(directory)}/';
    if (directory == null && offset == 0) {
      return CommitTreePage(
        commit: commit,
        entries: [
          CommitTreeEntry(
            stableId: 'lib',
            path: 'lib'.codeUnits,
            objectId: commit,
            kind: CommitTreeEntryKind.directory,
            mode: 0x4000,
          ),
          CommitTreeEntry(
            stableId: 'link',
            path: 'link'.codeUnits,
            objectId: commit,
            kind: CommitTreeEntryKind.symlink,
            mode: 0xa000,
          ),
        ],
        nextOffset: 2,
      );
    }
    return CommitTreePage(
      commit: commit,
      entries: [
        CommitTreeEntry(
          stableId: '$prefix$offset',
          path: '${prefix}file$offset'.codeUnits,
          objectId: commit,
          kind: CommitTreeEntryKind.file,
          mode: 0x81a4,
        ),
      ],
    );
  }

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = 512,
  }) async {
    calls.add('blame:${revision[0]}');
    return BlamePage(
      requestId: BigInt.from(++_request),
      revision: revision,
      path: path,
      totalRows: blameRows,
      offset: 0,
      rows: const [],
    );
  }

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async {
    blamePages.add((requestId: requestId, offset: offset));
    if (requestId != BigInt.from(_request)) {
      // Native keeps only the newest blame projection.
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.staleGeneration),
      );
    }
    return BlamePage(
      requestId: requestId,
      revision: '',
      path: const [],
      totalRows: blameRows,
      offset: offset,
      rows: [
        BlameRow(
          stableId: 'line-${offset + 1}',
          finalLine: offset + 1,
          originalLine: offset + 1,
          content: const [],
          author: const [],
          authorTime: 1,
          summary: const [],
          originalPath: const [],
          boundary: false,
          spanFirstLine: offset + 1,
          spanLastLine: offset + 1,
        ),
      ],
    );
  }

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) async {
    calls.add('history@$offset');
    if (offset > 0 && failNextHistoryPage) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.read),
      );
    }
    return PathHistoryPage(
      entries: offset == 0
          ? historyEntries
          : [
              PathHistoryEntry(
                stableId: 'older',
                commit: _c,
                author: const [],
                authorTime: 1,
                summary: const [],
                path: path,
              ),
            ],
      nextOffset: offset == 0 ? historyNextOffset : null,
      renameHops: 0,
      incomplete: false,
    );
  }

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) async {
    calls.add('range:$firstLine-$lastLine');
    return RangeHistoryResult(
      entries: [
        RangeHistoryEntry(
          stableId: 'range',
          commit: _b,
          author: const [],
          authorTime: 1,
          summary: const [],
        ),
      ],
      incomplete: false,
    );
  }

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) async => RestorePreview(
    token: BigInt.two,
    commit: commit,
    path: path,
    sourceBytes: const [],
  );

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) async => const RestoreResult(state: RestoreState.restored);

  Completer<void>? imageGate;
  final imageStarted = Completer<void>();

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async {
    if (!imageStarted.isCompleted) imageStarted.complete();
    await imageGate?.future;
    return const ImageDiffContent();
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

_Repository _repository() => _Repository()
  ..parents[_a] = const []
  ..parents[_b] = [_a]
  ..parents[_c] = [_b]
  ..files[_a] = [_change('f'), _change('lib/g')]
  ..files[_b] = [
    _change('f'),
    _change('gone', kind: CommitFileChangeKind.deleted),
    _change('image.png', kind: CommitFileChangeKind.image),
    _change('module', kind: CommitFileChangeKind.submodule, mode: 0xe000),
  ]
  ..files[_c] = [_change('f')];

InspectorService _service(_Repository repository) =>
    InspectorService(repository)..attach(_identity);

InspectorLocation _commit(String commit, {String? path}) =>
    InspectorLocation(target: CommitTarget(commit), path: path?.codeUnits);

void main() {
  group('navigation stack', () {
    test('push truncates forward entries and back/forward move', () {
      final stack = InspectorNavigation();
      stack.push(_commit(_a));
      stack.push(_commit(_b));
      stack.push(_commit(_c));
      expect(stack.back()!.target, CommitTarget(_b));
      expect(stack.canForward, isTrue);
      stack.push(_commit(_a, path: 'f'));
      expect(stack.canForward, isFalse);
      expect(stack.length, 3);
      expect(stack.backEntries().map((item) => item.target.commit), [_b, _a]);
      expect(stack.jump(-2)!.target, CommitTarget(_a));
      expect(stack.forwardEntries(), hasLength(2));
    });

    test('replace overwrites the current entry and holds at most 100', () {
      final stack = InspectorNavigation();
      stack.replace(_commit(_a));
      expect(stack.length, 1);
      stack.replace(_commit(_b));
      expect(stack.length, 1);
      expect(stack.current!.target, CommitTarget(_b));
      for (var index = 0; index < 150; index += 1) {
        stack.push(_commit(_a, path: '$index'));
      }
      expect(stack.length, 100);
      expect(stack.current!.path, '149'.codeUnits);
    });
  });

  group('lens availability', () {
    test('changed, deleted, binary, submodule, symlink, unchanged, folder', () {
      expect(
        lensAvailability(directory: false, change: _change('f')).values,
        everyElement(isNull),
      );
      final deleted = lensAvailability(
        directory: false,
        change: _change('f', kind: CommitFileChangeKind.deleted),
      );
      expect(deleted[InspectorLens.diff], isNull);
      expect(deleted[InspectorLens.contents], LensUnavailableReason.deleted);
      expect(deleted[InspectorLens.blame], LensUnavailableReason.deleted);
      final image = lensAvailability(
        directory: false,
        change: _change('f', kind: CommitFileChangeKind.image),
      );
      expect(image[InspectorLens.contents], isNull);
      expect(image[InspectorLens.blame], LensUnavailableReason.needsText);
      final module = lensAvailability(
        directory: false,
        change: _change('m', mode: 0xe000),
      );
      expect(module[InspectorLens.contents], LensUnavailableReason.submodule);
      final link = lensAvailability(
        directory: false,
        treeKind: CommitTreeEntryKind.symlink,
      );
      expect(link[InspectorLens.diff], LensUnavailableReason.notChanged);
      expect(link[InspectorLens.contents], isNull);
      expect(link[InspectorLens.blame], LensUnavailableReason.needsText);
      final folder = lensAvailability(directory: true);
      expect(folder[InspectorLens.history], isNull);
      expect(folder[InspectorLens.diff], LensUnavailableReason.directory);
    });

    test('sticky lens falls back to diff, then contents, then history', () {
      final unchanged = lensAvailability(directory: false);
      expect(stickyLens(InspectorLens.blame, unchanged), InspectorLens.blame);
      expect(stickyLens(InspectorLens.diff, unchanged), InspectorLens.contents);
      final deleted = lensAvailability(
        directory: false,
        change: _change('f', kind: CommitFileChangeKind.deleted),
      );
      expect(stickyLens(InspectorLens.blame, deleted), InspectorLens.diff);
      final folder = lensAvailability(directory: true);
      expect(stickyLens(InspectorLens.diff, folder), InspectorLens.history);
    });
  });

  test('back restores the commit shown before', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_a), fromHost: true);
    await service.navigate(_commit(_b), fromHost: true);
    expect(service.current.diff!.newObjectId, _b);
    await service.back();
    expect(service.current.location!.target, CommitTarget(_a));
    expect(service.current.inspection!.detail.commit, _a);
    expect(service.current.diff!.newObjectId, _a);
    expect(service.current.diff!.diff.rows.single.text, 'root->a'.codeUnits);
    expect(service.current.canForward, isTrue);
    await service.forward();
    expect(service.current.diff!.newObjectId, _b);
    await service.dispose();
  });

  test('back to blame reloads its pages', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_b));
    await service.navigate(
      _commit(_b, path: 'f').copyWith(lens: InspectorLens.blame),
    );
    await service.navigate(
      _commit(_a, path: 'f').copyWith(lens: InspectorLens.blame),
    );
    await service.back();
    expect(service.current.blame!.revision, _b);
    await service.ensureBlameIndex(600 - 88);
    expect(service.blameRowAt(512)!.finalLine, 513);
    expect(
      repository.blamePages.single.requestId,
      service.current.blame!.requestId,
    );
    await service.dispose();
  });

  test('a commit diff compares with its first parent', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_b));
    expect(repository.diffs.single.firstParent, _a);
    expect(service.current.inspection!.files, hasLength(4));
    // Without a parent hint the parents are read first, so the file list
    // compares with the parent and not with the empty tree.
    expect(repository.inspections.map((call) => call.firstParent), [null, _a]);
    repository.inspections.clear();
    await service.navigate(_commit(_c), parentHint: [_b]);
    expect(repository.inspections.single.firstParent, _b);
    await service.dispose();
  });

  test('comparisons diff base to commit and never list all files', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      InspectorLocation(
        target: ComparisonTarget(base: _a, commit: _c),
        scope: InspectorScope.all,
      ),
    );
    expect(service.current.location!.scope, InspectorScope.changed);
    expect(service.current.diff!.oldObjectId, _a);
    expect(service.current.diff!.diff.rows.single.text, 'a->c'.codeUnits);
    await service.dispose();
  });

  test('a target too large for one patch focuses its first file', () async {
    final repository = _repository()..tooLargeAllChanges = true;
    final service = _service(repository);
    await service.navigate(_commit(_b));
    expect(service.allChangesTooLarge, isTrue);
    expect(service.current.location!.path, 'f'.codeUnits);
    expect(service.diffOptions.newPath, 'f'.codeUnits);
    expect(service.current.canBack, isFalse);
    repository.tooLargeAllChanges = false;
    await service.navigate(_commit(_c));
    expect(service.allChangesTooLarge, isFalse);
    expect(service.current.location!.path, isNull);
    await service.dispose();
  });

  test(
    'a new file of the same target does not read the target again',
    () async {
      final repository = _repository();
      final service = _service(repository);
      await service.navigate(_commit(_b));
      repository.calls.clear();
      await service.navigate(_commit(_b, path: 'f'));
      expect(repository.calls, ['diff:b']);
      expect(service.diffOptions.newPath, 'f'.codeUnits);
      expect(service.current.canBack, isTrue);
      await service.dispose();
    },
  );

  test(
    'pushing the shown location does nothing; replace keeps one entry',
    () async {
      final repository = _repository();
      final service = _service(repository);
      await service.navigate(_commit(_b));
      repository.calls.clear();
      await service.navigate(_commit(_b));
      expect(repository.calls, isEmpty);
      await service.navigate(
        _commit(_b, path: 'f'),
        mode: InspectorNavigationMode.replace,
      );
      expect(service.current.canBack, isFalse);
      await service.navigate(
        _commit(_b, path: 'gone'),
        mode: InspectorNavigationMode.replace,
      );
      expect(service.current.canBack, isFalse);
      expect(service.current.location!.path, 'gone'.codeUnits);
      await service.dispose();
    },
  );

  test('the lens sticks while available and falls back otherwise', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      _commit(_b, path: 'f').copyWith(lens: InspectorLens.blame),
    );
    expect(service.current.blame, isNotNull);
    await service.navigate(
      _commit(_b, path: 'gone').copyWith(lens: InspectorLens.blame),
    );
    expect(service.current.location!.lens, InspectorLens.diff);
    expect(
      service.current.lensAvailability[InspectorLens.blame],
      LensUnavailableReason.deleted,
    );
    await service.navigate(
      _commit(_b, path: 'image.png').copyWith(lens: InspectorLens.blame),
    );
    expect(service.current.location!.lens, InspectorLens.diff);
    await service.navigate(
      _commit(_b, path: 'image.png').copyWith(lens: InspectorLens.contents),
    );
    expect(service.current.fileBytes, isNotNull);
    await service.dispose();
  });

  test('unchanged files in all files open their contents', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      InspectorLocation(
        target: CommitTarget(_b),
        scope: InspectorScope.all,
        path: 'lib/file0'.codeUnits,
      ),
    );
    expect(service.current.location!.lens, InspectorLens.contents);
    expect(service.current.fileBytes, [98, ...'lib/file0'.codeUnits]);
    expect(service.current.expanded, contains('lib'));
    expect(service.current.tree.keys, containsAll(['', 'lib']));
    await service.navigate(
      service.current.location!.copyWith(
        path: 'link'.codeUnits,
        lens: InspectorLens.blame,
      ),
    );
    expect(service.current.location!.lens, InspectorLens.contents);
    await service.dispose();
  });

  test('folders load once, collapse and load more', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      InspectorLocation(target: CommitTarget(_b), scope: InspectorScope.all),
    );
    expect(service.current.tree['']!.entries, hasLength(2));
    await service.loadMoreDirectory(null);
    expect(service.current.tree['']!.entries, hasLength(3));
    expect(service.current.tree['']!.nextOffset, isNull);
    await service.expandDirectory('lib'.codeUnits);
    await service.expandDirectory('lib'.codeUnits);
    expect(
      repository.calls.where((call) => call.startsWith('tree:lib')),
      hasLength(1),
    );
    service.collapseDirectory('lib'.codeUnits);
    expect(service.current.expanded, isNot(contains('lib')));
    await service.dispose();
  });

  test('targetShown follows inspector navigation but not the host', () async {
    final repository = _repository();
    final service = _service(repository);
    final shown = <InspectorTarget>[];
    final subscription = service.targetShown.listen(shown.add);
    await service.navigate(_commit(_a), fromHost: true);
    await service.navigate(_commit(_b), fromHost: true);
    expect(shown, isEmpty);
    await service.back();
    expect(shown, [CommitTarget(_a)]);
    await service.navigate(_commit(_a, path: 'f'));
    expect(shown, [CommitTarget(_a)]);
    await service.navigate(_commit(_c, path: 'f'));
    expect(shown, [CommitTarget(_a), CommitTarget(_c)]);
    await subscription.cancel();
    await service.dispose();
  });

  test('the newest navigation wins over a slower earlier one', () async {
    final repository = _repository();
    final gate = Completer<void>();
    repository.gates['inspect:$_a'] = gate;
    final service = _service(repository);
    final slow = service.navigate(_commit(_a));
    await service.navigate(_commit(_b));
    gate.complete();
    await slow;
    expect(service.current.location!.target, CommitTarget(_b));
    expect(service.current.diff!.newObjectId, _b);
    await service.dispose();
  });

  test('history selects its first entry and shows that change', () async {
    final repository = _repository()
      ..historyEntries = [
        PathHistoryEntry(
          stableId: 'c',
          commit: _c,
          author: const [],
          authorTime: 1,
          summary: const [],
          path: 'f'.codeUnits,
          oldPath: 'old'.codeUnits,
        ),
        PathHistoryEntry(
          stableId: 'b',
          commit: _b,
          author: const [],
          authorTime: 1,
          summary: const [],
          path: 'f'.codeUnits,
        ),
      ]
      ..historyNextOffset = 2;
    final service = _service(repository);
    await service.navigate(_commit(_c, path: 'f'));
    await service.navigate(
      _commit(_c, path: 'f').copyWith(lens: InspectorLens.history),
    );
    expect(service.current.location!.historyCommit, _c);
    expect(service.current.historyEntry!.detail.commit, _c);
    expect(repository.diffs.last.options.oldPath, 'old'.codeUnits);
    expect(repository.diffs.last.firstParent, _b);
    expect(service.current.diff!.newObjectId, _c);
    await service.selectHistoryEntry(_b);
    expect(service.current.location!.historyCommit, _b);
    expect(service.current.diff!.diff.rows.single.text, 'a->b'.codeUnits);
    expect(service.current.backLocations, hasLength(1));
    // Show Commit, then Back, returns to the selected entry.
    await service.navigate(_commit(_b, path: 'f'));
    await service.back();
    expect(service.current.location!.historyCommit, _b);
    expect(service.current.historyEntry!.detail.commit, _b);
    await service.loadMoreHistory();
    expect(service.current.history!.entries, hasLength(3));
    await service.dispose();
  });

  test('a failed older history page keeps loaded rows for retry', () async {
    final repository = _repository()
      ..historyEntries = [
        PathHistoryEntry(
          stableId: 'b',
          commit: _b,
          author: const [],
          authorTime: 1,
          summary: const [],
          path: 'f'.codeUnits,
        ),
      ]
      ..historyNextOffset = 1
      ..failNextHistoryPage = true;
    final service = _service(repository);
    await service.navigate(
      _commit(_c, path: 'f').copyWith(lens: InspectorLens.history),
    );
    await service.loadMoreHistory();
    expect(service.current.historyMoreFailed, isTrue);
    expect(service.current.history!.entries, hasLength(1));
    repository.failNextHistoryPage = false;
    await service.loadMoreHistory();
    expect(service.current.history!.entries, hasLength(2));
    await service.dispose();
  });

  test('line history uses the range read', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      _commit(_c, path: 'f').copyWith(
        lens: InspectorLens.history,
        lines: const InspectorLineRange(3, 9),
      ),
    );
    expect(repository.calls, contains('range:3-9'));
    expect(service.current.rangeHistory!.entries.single.commit, _b);
    expect(service.current.location!.historyCommit, _b);
    expect(await service.up(), isTrue);
    expect(service.current.location!.lines, isNull);
    expect(service.current.location!.lens, InspectorLens.history);
    await service.dispose();
  });

  test('up climbs from lens to file to all changes to changed', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      InspectorLocation(
        target: CommitTarget(_b),
        scope: InspectorScope.all,
        path: 'f'.codeUnits,
        lens: InspectorLens.blame,
      ),
    );
    expect(await service.up(), isTrue);
    expect(service.current.location!.lens, InspectorLens.diff);
    expect(await service.up(), isTrue);
    expect(service.current.location!.path, isNull);
    expect(await service.up(), isTrue);
    expect(service.current.location!.scope, InspectorScope.changed);
    expect(await service.up(), isFalse);
    await service.navigate(
      service.current.location!.copyWith(
        path: 'gone'.codeUnits,
        lens: InspectorLens.history,
      ),
    );
    expect(await service.up(), isTrue);
    expect(service.current.location!.lens, InspectorLens.diff);
    await service.dispose();
  });

  test('a failed target keeps its location and Back still works', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_a));
    repository.failInspect = true;
    await service.navigate(_commit(_b));
    expect(service.current.phase, InspectorPhase.failed);
    expect(service.current.failureCode, RepositoryFailureCode.missingObject);
    expect(service.current.location!.target, CommitTarget(_b));
    repository.failInspect = false;
    await service.retry();
    expect(service.current.phase, InspectorPhase.ready);
    await service.back();
    expect(service.current.location!.target, CommitTarget(_a));
    await service.dispose();
  });

  test('anchors are restored by Back without publishing', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_a, path: 'f'));
    var published = 0;
    final subscription = service.states.listen((_) => published += 1);
    service.reportAnchor(40);
    expect(published, 0);
    await service.navigate(_commit(_b));
    await service.back();
    expect(service.current.location!.anchor, 40);
    await subscription.cancel();
    await service.dispose();
  });

  test('detach drops late results and the stack', () async {
    final repository = _repository();
    final gate = Completer<void>();
    repository.gates['diff:$_b'] = gate;
    final service = _service(repository);
    await service.navigate(_commit(_a));
    final pending = service.navigate(_commit(_b));
    await Future<void>.delayed(Duration.zero);
    service.detach();
    gate.complete();
    await pending;
    expect(service.current.phase, InspectorPhase.empty);
    expect(service.current.location, isNull);
    service.attach(_identity);
    await service.navigate(_commit(_c));
    expect(service.current.canBack, isFalse);
    await service.dispose();
  });

  test('diff options keep the file and survive navigation', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_b, path: 'f'));
    await service.updateDiffOptions(
      service.diffOptions.copyWith(
        contextLines: 6,
        layout: DiffViewLayout.sideBySide,
      ),
    );
    expect(repository.diffs.last.options.newPath, 'f'.codeUnits);
    expect(service.current.diff!.diff.layout, DiffViewLayout.sideBySide);
    await service.navigate(_commit(_c));
    expect(repository.diffs.last.options.contextLines, 6);
    expect(repository.diffs.last.options.newPath, isNull);
    await service.ensureDiffIndex(512);
    expect(service.diffRowAt(512)!.stableId, 'later');
    await service.dispose();
  });

  test('stored diff preferences load every new diff', () async {
    final repository = _repository();
    var preferences = const DiffViewPreferences(
      layout: DiffViewLayout.sideBySide,
      whitespace: DiffWhitespace.ignoreAll,
      contextLines: 0,
    );
    final service = InspectorService(
      repository,
      diffPreferences: () => preferences,
    )..attach(_identity);
    await service.navigate(_commit(_b, path: 'f'));
    expect(repository.diffs.last.options.layout, DiffViewLayout.sideBySide);
    expect(repository.diffs.last.options.whitespace, DiffWhitespace.ignoreAll);
    expect(repository.diffs.last.options.contextLines, 0);
    expect(repository.diffs.last.options.newPath, 'f'.codeUnits);
    // Context widened for one diff is not carried to the next.
    await service.updateDiffOptions(
      service.diffOptions.copyWith(contextLines: 9),
    );
    preferences = preferences.copyWith(layout: DiffViewLayout.unified);
    await service.navigate(_commit(_c));
    expect(repository.diffs.last.options.layout, DiffViewLayout.unified);
    expect(repository.diffs.last.options.contextLines, 0);
    await service.dispose();
  });

  test('restore previews the shown or a named commit', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_b, path: 'f'));
    expect((await service.previewRestore('f'.codeUnits)).commit, _b);
    expect(
      (await service.previewRestore('f'.codeUnits, commit: _a)).commit,
      _a,
    );
    final result = await service.restoreFile(BigInt.two);
    expect(result.state, RestoreState.restored);
    await service.dispose();
  });

  test('an unchanged file opens in all files', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(_commit(_b, path: 'lib/file0'));
    expect(service.current.location!.scope, InspectorScope.all);
    expect(service.current.location!.lens, InspectorLens.contents);
    expect(service.current.canBack, isFalse);
    await service.dispose();
  });

  test('blame before opens the parent at the original line', () async {
    final repository = _repository();
    final service = _service(repository);
    await service.navigate(
      _commit(_c, path: 'f').copyWith(lens: InspectorLens.blame),
    );
    await service.blameBefore(
      BlameRow(
        stableId: 'line',
        finalLine: 8,
        originalLine: 4,
        content: const [],
        commit: _c,
        author: const [],
        authorTime: 1,
        summary: const [],
        originalPath: 'f'.codeUnits,
        boundary: false,
        spanFirstLine: 8,
        spanLastLine: 8,
      ),
    );
    expect(service.current.location!.target, CommitTarget(_b));
    expect(service.current.location!.lens, InspectorLens.blame);
    expect(service.current.location!.anchor, 3);
    expect(service.current.blame!.revision, _b);
    await service.back();
    expect(service.current.blame!.revision, _c);
    await service.dispose();
  });

  test('a late image cannot publish after the location changes', () async {
    final repository = _repository()..imageGate = Completer<void>();
    final service = _service(repository);
    await service.navigate(_commit(_b, path: 'image.png'));
    final pending = service.imageDiff(
      DiffDisplayRow(
        stableId: 'image',
        kind: DiffRowKind.image,
        text: const [],
        oldPath: 'image.png'.codeUnits,
        newPath: 'image.png'.codeUnits,
      ),
    );
    await repository.imageStarted.future;
    await service.navigate(_commit(_c));
    repository.imageGate!.complete();
    expect(await pending, isNull);
    await service.dispose();
  });
}
