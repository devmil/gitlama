import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/repository_lock.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/status_acceleration.dart';
import 'package:gitlama/models/repository_view_cache.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/history_service.dart';

void main() {
  test('a selection carries who made it', () async {
    final repository = _HistoryRepository();
    final service = HistoryService(repository);
    final selections = <HistorySelection>[];
    final subscription = service.selections.listen(selections.add);
    await service.load(
      RepositorySessionIdentity(nativeId: BigInt.one, generation: 1),
    );
    // The inspector following Back selects without being inspected again;
    // a click made meanwhile is an ordinary graph selection.
    await service.select(
      'c',
      reveal: true,
      origin: HistorySelectionOrigin.inspector,
    );
    await service.select('a');
    expect(selections.map((selection) => selection.origin), [
      HistorySelectionOrigin.inspector,
      HistorySelectionOrigin.graph,
    ]);
    await subscription.cancel();
    await service.dispose();
  });

  test(
    'graph selection announces the commit without reading its diff',
    () async {
      final repository = _HistoryRepository();
      final service = HistoryService(repository);
      final selections = <HistorySelection>[];
      final subscription = service.selections.listen(selections.add);
      await service.load(
        RepositorySessionIdentity(nativeId: BigInt.one, generation: 1),
      );
      final batches = repository.metadataBatches.length;
      await service.select('c', reveal: true);
      expect(service.current.page!.selectedObjectIds, ['c']);
      expect(service.current.page!.revealObjectId, 'c');
      expect(service.current.targetObjectId, 'c');
      expect(repository.metadataBatches.length, batches);
      // The inspector reads the diff; the graph never does.
      expect(repository.diffOptions, isEmpty);
      expect(selections.single.commit, 'c');
      expect(selections.single.base, isNull);
      await subscription.cancel();
      await service.dispose();
    },
  );

  test(
    'latest selection waits for loading history and needs only one click',
    () async {
      final repository = _HistoryRepository(blockGenerationOne: true);
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      final load = service.load(identity);
      await repository.firstStarted.future;
      final first = service.select('a', reveal: true);
      final latest = service.select('c', reveal: true);
      repository.releaseFirst.complete();
      await Future.wait([load, first, latest]);
      expect(service.current.page!.selectedObjectIds, ['c']);
      expect(service.current.targetObjectId, 'c');
      await service.dispose();
    },
  );

  test(
    'reloading a shown history keeps its rows and inspected commit on screen',
    () async {
      final repository = _HistoryRepository();
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      await service.select('c');
      final shown = service.current.page!;
      final states = <HistoryState>[];
      final selections = <HistorySelection>[];
      final subscription = service.states.listen(states.add);
      final announced = service.selections.listen(selections.add);

      final reloaded = await service.load(identity);

      expect(states, isNotEmpty);
      expect(states.every((state) => state.page != null), isTrue);
      expect(
        states.map((state) => state.phase),
        everyElement(HistoryLoadPhase.complete),
      );
      // The partial preview never replaces the complete graph on screen.
      expect(states.every((state) => state.page!.complete), isTrue);
      expect(states.every((state) => state.targetObjectId == 'c'), isTrue);
      expect(reloaded.page!.requestId, isNot(shown.requestId));
      expect(reloaded.page!.selectedObjectIds, ['c']);
      // The inspected commit stays, so the inspector is not asked again.
      expect(selections, isEmpty);
      await subscription.cancel();
      await announced.cancel();
      await service.dispose();
    },
  );

  test('a reload that loses the selected commit drops its detail', () async {
    final repository = _HistoryRepository();
    final service = HistoryService(repository);
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    await service.load(identity);
    await service.select('c');
    repository.rejectSelection = true;
    final selections = <HistorySelection>[];
    final subscription = service.selections.listen(selections.add);

    final reloaded = await service.load(identity);

    expect(reloaded.page!.selectedObjectIds, isEmpty);
    expect(reloaded.targetObjectId, isNull);
    expect(selections.single.commit, isNull);
    await subscription.cancel();
    await service.dispose();
  });

  test('a loaded history shows the commit its session kept selected', () async {
    final repository = _HistoryRepository()..keepsSelection = true;
    final service = HistoryService(repository);
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    await service.load(identity);
    await service.select('b');
    // Another repository was shown meanwhile.
    service.clear();

    final selections = <HistorySelection>[];
    final subscription = service.selections.listen(selections.add);
    final loaded = await service.load(identity);
    for (var attempt = 0; attempt < 10; attempt += 1) {
      if (selections.isNotEmpty) break;
      await Future<void>.delayed(Duration.zero);
    }

    expect(loaded.page!.selectedObjectIds, ['b']);
    expect(selections.last.commit, 'b');
    expect(service.current.targetObjectId, 'b');
    await subscription.cancel();
    await service.dispose();
  });

  test('a reveal waits for the branch filter being applied', () async {
    final repository = _HistoryRepository();
    final service = HistoryService(repository);
    await service.load(
      RepositorySessionIdentity(nativeId: BigInt.one, generation: 1),
    );
    repository.calls.clear();
    final gate = repository.filterGate = Completer<void>();

    final filtering = service.applyBranchFilter(
      HistoryBranchFilter(['refs/heads/topic']),
    );
    final revealing = service.select('b', reveal: true);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, ['filter']);
    gate.complete();
    await Future.wait([filtering, revealing]);

    expect(repository.calls, ['filter', 'select']);
    expect(service.current.page!.selectedObjectIds, ['b']);
    await service.dispose();
  });

  test('publishes topology before prioritized bounded metadata', () async {
    final repository = _HistoryRepository();
    final service = HistoryService(repository);
    final phases = <HistoryLoadPhase>[];
    final subscription = service.states.listen(
      (state) => phases.add(state.phase),
    );
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    final result = await service.load(identity, priorityObjectIds: const ['b']);

    expect(phases.take(2), [
      HistoryLoadPhase.loading,
      HistoryLoadPhase.preview,
    ]);
    expect(result.phase, HistoryLoadPhase.complete);
    expect(result.page!.totalRows, 3);
    expect(result.page!.rows.map((row) => row.lane), [0, 1, 0]);
    expect(result.page!.rows.every((row) => row.hasMetadata), isTrue);
    expect(repository.metadataBatches.first.first, 'b');
    expect(
      repository.metadataBatches.every((batch) => batch.length <= 256),
      isTrue,
    );
    await subscription.cancel();
    await service.dispose();
  });

  test('restarts history after frozen refs change during completion', () async {
    final repository = _HistoryRepository(failFirstCompletion: true);
    final service = HistoryService(repository);
    final phases = <HistoryLoadPhase>[];
    final subscription = service.states.listen(
      (state) => phases.add(state.phase),
    );
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );

    final result = await service.load(identity);

    expect(result.phase, HistoryLoadPhase.complete);
    expect(repository.completionAttempts, 2);
    expect(repository.previewAttempts, 2);
    expect(phases, isNot(contains(HistoryLoadPhase.failed)));
    await subscription.cancel();
    await service.dispose();
  });

  test(
    'reference picker is read-only and scoped to the exact session generation',
    () async {
      final service = HistoryService(_HistoryRepository());
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      final before = service.current;
      expect(
        service.referencePickerCommitsFor(identity).map((row) => row.objectId),
        ['a', 'b', 'c'],
      );
      expect(service.current, same(before));
      expect(
        service.referencePickerCommitsFor(
          RepositorySessionIdentity(nativeId: BigInt.two, generation: 1),
        ),
        isEmpty,
      );
      expect(
        service.referencePickerCommitsFor(
          RepositorySessionIdentity(nativeId: BigInt.one, generation: 2),
        ),
        isEmpty,
      );
      service.clear();
      expect(service.referencePickerCommitsFor(identity), isEmpty);
      await service.dispose();
    },
  );

  test(
    'projects long parent edges through every intervening graph row',
    () async {
      final service = HistoryService(_HistoryRepository());
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);

      final source = service.segmentsFor('a').single;
      expect(source.startsAtTop, isFalse);
      expect(source.endsAtCenter, isFalse);
      expect((source.fromLane, source.toLane), (0, 0));

      final continuation = service.segmentsFor('b').single;
      expect(continuation.startsAtTop, isTrue);
      expect(continuation.endsAtCenter, isFalse);
      expect(continuation.lit, source.lit);
      expect((continuation.fromLane, continuation.toLane), (0, 0));

      final target = service.segmentsFor('c').single;
      expect(target.startsAtTop, isTrue);
      expect(target.endsAtCenter, isTrue);
      expect(target.lit, source.lit);
      expect((target.fromLane, target.toLane), (0, 1));
      await service.dispose();
    },
  );

  test(
    'merged release lane joins at the shared parent below the first-parent row',
    () async {
      final service = HistoryService(_HistoryRepository(mergedRelease: true));
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);

      final mergeEdge = service
          .segmentsFor('merge')
          .singleWhere((segment) => segment.kind == 2);
      expect((mergeEdge.fromLane, mergeEdge.toLane), (0, 1));
      final releaseJoin = service
          .segmentsFor('release')
          .singleWhere((segment) => segment.kind == 1);
      expect((releaseJoin.fromLane, releaseJoin.toLane), (1, 1));
      final crossing = service
          .segmentsFor('search')
          .singleWhere((segment) => segment.kind == 1);
      expect((crossing.fromLane, crossing.toLane), (1, 1));
      expect(crossing.startsAtTop, isTrue);
      expect(crossing.endsAtCenter, isFalse);
      final join = service
          .segmentsFor('base')
          .singleWhere((segment) => segment.kind == 1);
      expect((join.fromLane, join.toLane), (1, 0));
      expect(join.endsAtCenter, isTrue);
      await service.dispose();
    },
  );

  test(
    'crossing edges survive unloaded endpoints and page arrival order',
    () async {
      final repository = _HistoryRepository(
        totalRows: 1700,
        crossingEdges: true,
      );
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      await service.ensureIndex(1100);
      expect(service.rowAt(520), isNull);
      expect(service.rowAt(1600), isNull);
      final middle = service.segmentsFor('paged-1100').single;
      expect(middle.startsAtTop, isTrue);
      expect(middle.endsAtCenter, isFalse);
      expect(middle.lit, isTrue);
      expect((middle.fromLane, middle.toLane), (2, 2));
      await service.ensureIndex(520);
      final source = service.segmentsFor('paged-520').single;
      expect(source.startsAtTop, isFalse);
      expect((source.fromLane, source.toLane), (2, 2));
      expect(service.segmentsFor('paged-521').single.startsAtTop, isTrue);
      expect(service.segmentsFor('paged-1023').single.endsAtCenter, isFalse);
      expect(service.segmentsFor('paged-1024').single.startsAtTop, isTrue);
      await service.ensureIndex(1600);
      expect(service.segmentsFor('paged-1600').single.endsAtCenter, isTrue);
      expect(
        (
          service.segmentsFor('paged-1600').single.fromLane,
          service.segmentsFor('paged-1600').single.toLane,
        ),
        (2, 1),
      );
      expect(service.segmentsFor('paged-1601'), isEmpty);
      expect(service.segmentsFor('paged-1100'), hasLength(1));
      expect(repository.requestedOffsets, [1024, 512, 1536]);
      await service.dispose();
    },
  );

  test('late preview cannot replace a newer repository generation', () async {
    final repository = _HistoryRepository(blockGenerationOne: true);
    final service = HistoryService(repository);
    final first = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    final second = RepositorySessionIdentity(
      nativeId: BigInt.two,
      generation: 2,
    );
    final old = service.load(first);
    await repository.firstStarted.future;
    final current = await service.load(second);
    repository.releaseFirst.complete();
    await old;
    expect(current.phase, HistoryLoadPhase.complete);
    expect(service.current.page!.rows.first.objectId, 'a');
    expect(service.current.phase, HistoryLoadPhase.complete);
    await service.dispose();
  });

  test(
    'fetches offscreen topology pages without a load-older barrier',
    () async {
      final repository = _HistoryRepository(totalRows: 1025);
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      expect(service.rowAt(700), isNull);
      await service.ensureIndex(700);
      expect(service.rowAt(700)!.objectId, 'paged-700');
      expect(repository.requestedOffsets, contains(512));
      await service.dispose();
    },
  );

  test('publishes native ancestry lighting for the retained request', () async {
    final repository = _HistoryRepository();
    final service = HistoryService(repository);
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    await service.load(identity);
    await service.select('a');
    expect(service.current.page!.lightingActive, isTrue);
    expect(service.current.page!.rows.first.selected, isTrue);
    expect(service.current.page!.rows.first.lit, isTrue);
    await service.select('a', reveal: true, focus: false);
    final firstReveal = service.current.page!.revealSequence;
    await service.select('a', reveal: true, focus: false);
    expect(service.current.page!.revealSequence, firstReveal + 1);
    expect(service.current.page!.revealObjectId, 'a');
    expect(service.current.page!.revealIndex, 0);
    await service.dispose();
  });

  test('newer selection wins and comparisons retain byte direction', () async {
    final repository = _HistoryRepository(delayA: true);
    final service = HistoryService(repository);
    final selections = <HistorySelection>[];
    final subscription = service.selections.listen(selections.add);
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    await service.load(identity);
    final delayedA = service.select('a', reveal: true);
    await repository.aStarted.future;
    expect(service.current.targetObjectId, 'a');
    await service.select('b', reveal: true);
    repository.releaseA.complete();
    await delayedA;
    expect(service.current.targetObjectId, 'b');
    expect(selections.last.commit, 'b');

    await service.select('a');
    await service.select('b', toggle: true);
    expect(selections.last.base, 'a');
    expect(selections.last.commit, 'b');

    await service.select('b');
    await service.select('a', toggle: true);
    expect(selections.last.base, 'b');
    expect(selections.last.commit, 'a');
    await subscription.cancel();
    await service.dispose();
  });

  test(
    'clearing a retired session invalidates pending reveal effects',
    () async {
      final repository = _HistoryRepository(delayA: true);
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      final delayed = service.select('a', reveal: true);
      await repository.aStarted.future;
      service.clear();
      repository.releaseA.complete();
      await delayed;
      expect(service.current.phase, HistoryLoadPhase.empty);
      expect(service.current.page, isNull);
      await service.dispose();
    },
  );

  test(
    'newest query wins while pending and retained selection stays identity-based',
    () async {
      final repository = _HistoryRepository(delayQueryB: true);
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      await service.select('a');
      final delayed = service.applyQuery(const HistoryQuery(text: 'b'));
      await repository.queryBStarted.future;
      expect(service.current.pendingQuery!.text, 'b');
      expect(service.current.page!.totalRows, 3);
      final accepted = await service.applyQuery(
        const HistoryQuery(text: 'none'),
      );
      repository.releaseQueryB.complete();
      await delayed;
      expect(accepted.page!.acceptedQuery, '');
      expect(service.current.page!.acceptedQuery, '');
      expect(service.current.page!.totalRows, 3);
      expect(service.searchMatches, isEmpty);
      expect(service.current.page!.selectedObjectIds, ['a']);
      expect(service.current.page!.selectedFilteredOut, isFalse);
      await service.dispose();
    },
  );

  test(
    'refresh restores multiple selected identities and honors deselection',
    () async {
      final repository = _HistoryRepository();
      final service = HistoryService(repository);
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);
      await service.select('a');
      await service.select('b', toggle: true);
      expect(service.current.page!.selectedObjectIds, ['a', 'b']);

      await service.load(identity);
      expect(service.current.page!.selectedObjectIds, ['a', 'b']);
      await service.select('a', toggle: true);
      expect(service.current.page!.selectedObjectIds, ['b']);
      await service.load(identity);
      expect(service.current.page!.selectedObjectIds, ['b']);
      await service.dispose();
    },
  );

  test(
    'history text search retains topology and navigates stable matches',
    () async {
      final service = HistoryService(_HistoryRepository());
      final identity = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await service.load(identity);

      final searched = await service.applyQuery(const HistoryQuery(text: 'b'));

      expect(searched.page!.totalRows, 3);
      expect(searched.page!.acceptedQuery, isEmpty);
      expect(service.searchMatches, ['b']);
      expect(service.isSearchMatch('b'), isTrue);
      expect(service.isSearchMatch('a'), isFalse);
      await service.navigateSearch(backwards: false);
      expect(service.current.targetObjectId, 'b');
      await service.dispose();
    },
  );

  group('other refs', () {
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    HistoryPage remembered({required bool otherRefs}) => HistoryPage(
      requestId: cachedHistoryRequestId,
      complete: false,
      totalRows: 2,
      offset: 0,
      rows: const [_b, _c],
      laneCount: 1,
      payloadBytes: 0,
      otherRefs: otherRefs,
    );

    test('each load asks for the reference scope of the moment', () async {
      final repository = _HistoryRepository();
      var otherRefs = false;
      final service = HistoryService(repository, otherRefs: () => otherRefs);

      await service.load(identity);
      otherRefs = true;
      await service.load(identity);

      expect(repository.otherRefsRequests, [false, true]);
      await service.dispose();
    });

    test('a graph cached with other references never stands in', () async {
      Future<List<HistoryLoadPhase>> phasesFor({
        required bool cached,
        required bool shown,
      }) async {
        final service = HistoryService(
          _HistoryRepository(),
          cachedFirstPage: (_) => remembered(otherRefs: cached),
          otherRefs: () => shown,
        );
        final phases = <HistoryLoadPhase>[];
        final subscription = service.states.listen(
          (state) => phases.add(state.phase),
        );
        await service.load(identity);
        await subscription.cancel();
        await service.dispose();
        return phases;
      }

      expect(
        (await phasesFor(cached: false, shown: false)).first,
        HistoryLoadPhase.preview,
      );
      expect(
        (await phasesFor(cached: true, shown: false)).first,
        HistoryLoadPhase.loading,
      );
      expect(
        (await phasesFor(cached: false, shown: true)).first,
        HistoryLoadPhase.loading,
      );
    });

    test('a revealed commit the history does not load is reported', () async {
      final repository = _HistoryRepository();
      final service = HistoryService(repository);
      await service.load(identity);
      repository.rejectSelection = true;

      await service.select('hidden', reveal: true);
      expect(service.current.targetObjectId, 'hidden');
      expect(service.current.targetNotShown, isTrue);

      // Only a reveal asks for the commit to be shown.
      await service.select('hidden');
      expect(service.current.targetNotShown, isFalse);

      // The next publication forgets it.
      repository.rejectSelection = false;
      await service.select('b', reveal: true);
      expect(service.current.targetNotShown, isFalse);
      await service.dispose();
    });
  });

  group('branch filter', () {
    final identity = RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: 1,
    );
    final topic = HistoryBranchFilter(['refs/heads/topic']);

    test('loads the remembered filter before anything is published', () async {
      final repository = _HistoryRepository();
      final unfiltered = HistoryPage(
        requestId: cachedHistoryRequestId,
        complete: false,
        totalRows: 3,
        offset: 0,
        rows: const [_a, _b, _c],
        laneCount: 2,
        payloadBytes: 0,
      );
      final service = HistoryService(
        repository,
        cachedFirstPage: (_) => unfiltered,
        branchFilterFor: (_) => topic,
      );
      final published = <HistoryPage>[];
      final subscription = service.states.listen((state) {
        if (state.page case final page?) published.add(page);
      });

      await service.load(identity);

      expect(repository.calls.first, 'filter');
      expect(repository.filterRequests.single.requestId, BigInt.zero);
      expect(repository.filterRequests.single.filter, topic);
      // The cached graph is unfiltered and must never stand in.
      expect(published, isNotEmpty);
      expect(published.every((page) => page.branchFilter == topic), isTrue);
      expect(service.current.page!.rows.map((row) => row.objectId), ['b', 'c']);
      await subscription.cancel();
      await service.dispose();
    });

    test(
      'the graph last shown under the filter stands in while loading',
      () async {
        final repository = _HistoryRepository();
        HistoryPage remembered(HistoryBranchFilter filter) => HistoryPage(
          requestId: cachedHistoryRequestId,
          complete: false,
          totalRows: 2,
          offset: 0,
          rows: const [_b, _c],
          laneCount: 1,
          payloadBytes: 0,
          branchFilter: filter,
        );
        final phases = <HistoryLoadPhase>[];
        final service = HistoryService(
          repository,
          cachedFirstPage: (_) => remembered(topic),
          branchFilterFor: (_) => topic,
        );
        final subscription = service.states.listen(
          (state) => phases.add(state.phase),
        );

        await service.load(identity);

        expect(phases, isNot(contains(HistoryLoadPhase.loading)));
        expect(phases.first, HistoryLoadPhase.preview);
        await subscription.cancel();
        await service.dispose();

        // A graph remembered under another filter does not.
        final other = HistoryService(
          _HistoryRepository(),
          cachedFirstPage: (_) =>
              remembered(HistoryBranchFilter(['refs/heads/x'])),
          branchFilterFor: (_) => topic,
        );
        final otherPhases = <HistoryLoadPhase>[];
        final otherSubscription = other.states.listen(
          (state) => otherPhases.add(state.phase),
        );
        await other.load(identity);
        expect(otherPhases.first, HistoryLoadPhase.loading);
        await otherSubscription.cancel();
        await other.dispose();
      },
    );

    test('a filter change is remembered for the next visit', () async {
      final repository = _HistoryRepository();
      final remembered = <HistoryPage>[];
      final service = HistoryService(
        repository,
        onFirstPage: (_, page) => remembered.add(page),
      );
      await service.load(identity);
      remembered.clear();

      await service.applyBranchFilter(topic);

      expect(remembered.single.branchFilter, topic);
      await service.dispose();
    });

    test('applies to the shown graph and coalesces rapid changes', () async {
      final repository = _HistoryRepository();
      final service = HistoryService(repository);
      await service.load(identity);
      repository.filterRequests.clear();
      final sequence = service.branchFilterSequence;
      final gate = repository.filterGate = Completer<void>();

      final changes = [
        service.applyBranchFilter(HistoryBranchFilter(['refs/heads/one'])),
        service.applyBranchFilter(HistoryBranchFilter(['refs/heads/two'])),
        service.applyBranchFilter(HistoryBranchFilter(['refs/heads/three'])),
      ];
      gate.complete();
      await Future.wait(changes);

      // The superseded middle request is never sent; the first one's answer
      // is not shown because a newer request was already waiting.
      expect(
        repository.filterRequests.map((request) => request.filter.references),
        [
          ['refs/heads/one'],
          ['refs/heads/three'],
        ],
      );
      expect(repository.nativeFilter.references, ['refs/heads/three']);
      final page = service.current.page!;
      expect(page.branchFilter.references, ['refs/heads/three']);
      expect(page.rows.map((row) => row.objectId), ['b', 'c']);
      expect(service.branchFilterSequence, sequence + 1);

      // The shown filter is not sent again.
      await service.applyBranchFilter(
        HistoryBranchFilter(['refs/heads/three']),
      );
      expect(repository.filterRequests, hasLength(2));

      await service.applyBranchFilter(HistoryBranchFilter.none);
      expect(service.current.page!.rows.map((row) => row.objectId), [
        'a',
        'b',
        'c',
      ]);
      await service.dispose();
    });

    test('discards a window of the view a filter replaced', () async {
      final repository = _HistoryRepository(totalRows: 1200);
      final service = HistoryService(repository);
      await service.load(identity);
      final gate = repository.pageGate = Completer<void>();

      final pending = service.ensureIndex(600);
      await repository.pageStarted.future;
      await service.applyBranchFilter(topic);
      gate.complete();
      await pending;

      expect(service.current.page!.branchFilter, topic);
      expect(service.rowAt(600), isNull);
      expect(service.rowAt(0)!.objectId, 'b');
      await service.dispose();
    });

    test('a filter matching nothing keeps a page to clear it from', () async {
      final repository = _HistoryRepository(totalRows: 0);
      final service = HistoryService(
        repository,
        branchFilterFor: (_) => HistoryBranchFilter(['refs/heads/gone']),
      );
      repository.emptyWhenFiltered = true;

      final state = await service.load(identity);

      expect(state.phase, HistoryLoadPhase.complete);
      expect(state.page!.totalRows, 0);
      expect(state.page!.branchFilter.references, ['refs/heads/gone']);
      await service.dispose();
    });

    test('a filter change clears the search it invalidates', () async {
      final repository = _HistoryRepository();
      final service = HistoryService(repository);
      await service.load(identity);
      await service.applyQuery(const HistoryQuery(text: 'b'));
      expect(service.searchMatches, isNotEmpty);

      await service.applyBranchFilter(topic);

      expect(service.searchQuery, isNull);
      expect(service.searchMatches, isEmpty);
      await service.dispose();
    });
  });
}

final class _HistoryRepository implements RepositorySessionRepository {
  _HistoryRepository({
    this.crossingEdges = false,
    this.mergedRelease = false,
    this.blockGenerationOne = false,
    this.totalRows = 3,
    this.delayA = false,
    this.delayQueryB = false,
    this.failFirstCompletion = false,
  });

  final bool crossingEdges;
  final bool mergedRelease;
  final bool blockGenerationOne;
  final int totalRows;
  final bool delayA;
  final bool delayQueryB;
  final bool delayImage = false;
  final bool failFirstCompletion;
  int previewAttempts = 0;
  int completionAttempts = 0;
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  final aStarted = Completer<void>();
  final releaseA = Completer<void>();
  final queryBStarted = Completer<void>();
  final releaseQueryB = Completer<void>();
  final imageStarted = Completer<void>();
  final releaseImage = Completer<void>();
  final List<List<String>> metadataBatches = [];
  final List<int> requestedOffsets = [];
  final List<int> requestedBlameOffsets = [];
  final List<String> blameRevisions = [];
  final Map<String, String> parentByCommit = {};
  final List<DiffLoadOptions> diffOptions = [];
  Completer<void>? diffGate;
  final diffStarted = Completer<void>();

  /// Comparisons whose patch of every file exceeds the read limit.
  var tooLargeAllChanges = false;
  BigInt? restoredToken;
  var _request = 0;
  var _revealSequence = 0;
  String? _current;
  String? _focused;
  final List<String> _selected = [];

  /// The native session's branch filter, which later loads keep.
  var nativeFilter = HistoryBranchFilter.none;
  final List<({BigInt requestId, HistoryBranchFilter filter})> filterRequests =
      [];
  Completer<void>? filterGate;
  final List<String> calls = [];
  var emptyWhenFiltered = false;

  /// Whether a load reports the selection the native session retained.
  var keepsSelection = false;

  /// Whether selecting fails, as for a commit the repository no longer has.
  var rejectSelection = false;

  /// The reference scope of every history load.
  final List<bool> otherRefsRequests = [];

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = 512,
  }) async {
    if (!complete) otherRefsRequests.add(otherRefs);
    if (crossingEdges) return _crossingPage(BigInt.one, 0, maximumRows);
    if (mergedRelease) {
      return HistoryPage(
        requestId: BigInt.from(++_request),
        complete: complete,
        totalRows: 4,
        offset: 0,
        rows: const [
          HistoryTopologyRow(
            objectId: 'merge',
            parents: ['search', 'release'],
            refs: [],
            lane: 0,
            shape: 1,
          ),
          HistoryTopologyRow(
            objectId: 'release',
            parents: ['base'],
            refs: [],
            lane: 1,
            shape: 0,
          ),
          HistoryTopologyRow(
            objectId: 'search',
            parents: ['base'],
            refs: [],
            lane: 0,
            shape: 0,
          ),
          HistoryTopologyRow(
            objectId: 'base',
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ],
        segments: const [
          HistoryTopologySegment(
            fromObjectId: 'merge',
            toObjectId: 'search',
            parentOrdinal: 0,
            fromLane: 0,
            toLane: 0,
            kind: 0,
          ),
          HistoryTopologySegment(
            fromObjectId: 'merge',
            toObjectId: 'release',
            parentOrdinal: 1,
            fromLane: 0,
            toLane: 1,
            kind: 2,
          ),
          HistoryTopologySegment(
            fromObjectId: 'release',
            toObjectId: 'base',
            parentOrdinal: 0,
            fromLane: 1,
            toLane: 0,
            kind: 1,
          ),
          HistoryTopologySegment(
            fromObjectId: 'search',
            toObjectId: 'base',
            parentOrdinal: 0,
            fromLane: 0,
            toLane: 0,
            kind: 0,
          ),
        ],
        laneCount: 2,
        payloadBytes: 0,
      );
    }
    if (!complete) previewAttempts += 1;
    if (blockGenerationOne && identity.generation == 1 && !complete) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    calls.add('load');
    final request = BigInt.from(++_request);
    final rows = nativeFilter.isNotEmpty
        ? emptyWhenFiltered
              ? const <HistoryTopologyRow>[]
              : const [_b, _c]
        : complete
        ? const [_a, _b, _c]
        : const [_a, _b];
    return HistoryPage(
      requestId: request,
      complete: complete,
      totalRows: nativeFilter.isNotEmpty ? rows.length : totalRows,
      offset: 0,
      rows: rows,
      branchFilter: nativeFilter,
      selectedObjectIds: keepsSelection ? List.of(_selected) : const [],
      segments: complete
          ? const [
              HistoryTopologySegment(
                fromObjectId: 'a',
                toObjectId: 'c',
                parentOrdinal: 0,
                fromLane: 0,
                toLane: 1,
                kind: 1,
              ),
            ]
          : const [],
      laneCount: 2,
      payloadBytes: 256,
    );
  }

  @override
  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  }) async {
    metadataBatches.add(List.of(objectIds));
    return [
      for (final objectId in objectIds)
        HistoryMetadata(
          objectId: objectId,
          subject: objectId.codeUnits,
          author: const [65],
          failure: objectId == 'c'
              ? HistoryMetadataFailure.objectTooLarge
              : null,
        ),
    ];
  }

  Completer<void>? pageGate;
  final pageStarted = Completer<void>();

  @override
  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async {
    requestedOffsets.add(offset);
    if (crossingEdges) return _crossingPage(requestId, offset, maximumRows);
    final gate = pageGate;
    if (gate != null) {
      pageGate = null;
      pageStarted.complete();
      await gate.future;
    }
    final count = (totalRows - offset).clamp(0, maximumRows);
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: totalRows,
      offset: offset,
      rows: [
        for (var index = 0; index < count; index += 1)
          HistoryTopologyRow(
            objectId: 'paged-${offset + index}',
            parents: const [],
            refs: const [],
            lane: 0,
            shape: 0,
          ),
      ],
      laneCount: 1,
      payloadBytes: count * 64,
    );
  }

  HistoryPage _crossingPage(BigInt requestId, int offset, int maximumRows) {
    final end = (offset + maximumRows).clamp(0, totalRows);
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: totalRows,
      offset: offset,
      rows: [
        for (var i = offset; i < end; i++)
          HistoryTopologyRow(
            objectId: 'paged-$i',
            parents: const [],
            refs: const [],
            lane: 0,
            shape: 0,
          ),
      ],
      segments: offset <= 1600 && end > 520
          ? const [
              HistoryTopologySegment(
                fromObjectId: 'paged-520',
                toObjectId: 'paged-1600',
                parentOrdinal: 0,
                fromLane: 2,
                toLane: 1,
                kind: 1,
                fromRow: 520,
                toRow: 1600,
                lit: true,
              ),
            ]
          : const [],
      laneCount: 3,
      payloadBytes: 0,
    );
  }

  @override
  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = 512,
  }) async {
    completionAttempts += 1;
    if (failFirstCompletion && completionAttempts == 1) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.staleGeneration),
      );
    }
    final page = await loadHistory(
      identity,
      complete: true,
      maximumRows: maximumRows,
    );
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: page.totalRows,
      offset: page.offset,
      rows: page.rows,
      segments: page.segments,
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes,
      branchFilter: page.branchFilter,
      selectedObjectIds: page.selectedObjectIds,
    );
  }

  @override
  Future<HistoryPage> selectHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String? objectId,
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    required int offset,
    int maximumRows = 512,
  }) async {
    calls.add('select');
    if (rejectSelection && objectId != null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.invalidOptions),
      );
    }
    if (delayA && objectId == 'a' && !aStarted.isCompleted) {
      aStarted.complete();
      await releaseA.future;
    }
    _current = objectId;
    if (objectId == null) {
      _selected.clear();
    } else if (toggle) {
      _selected.contains(objectId)
          ? _selected.remove(objectId)
          : _selected.add(objectId);
    } else {
      _selected
        ..clear()
        ..add(objectId);
    }
    if (focus) _focused = objectId;
    if (reveal) _revealSequence += 1;
    const sourceRows = [_a, _b, _c];
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: sourceRows.length,
      offset: 0,
      rows: [
        for (final row in sourceRows)
          HistoryTopologyRow(
            objectId: row.objectId,
            parents: row.parents,
            refs: row.refs,
            lane: row.lane,
            shape: row.shape,
            subject: row.subject,
            author: row.author,
            selected: _selected.contains(row.objectId),
            current: row.objectId == _current,
            lit: row.objectId == _current,
          ),
      ],
      laneCount: 2,
      payloadBytes: 256,
      lightingActive: objectId != null,
      currentObjectId: _current,
      selectedObjectIds: List.of(_selected),
      focusedObjectId: _focused,
      comparisonOldObjectId: _selected.length == 2 ? _selected[0] : null,
      comparisonNewObjectId: _selected.length == 2 ? _selected[1] : null,
      revealSequence: _revealSequence,
      revealObjectId: reveal ? objectId : null,
      revealIndex: reveal && objectId != null
          ? sourceRows.indexWhere((row) => row.objectId == objectId)
          : null,
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
    diffOptions.add(options);
    if (tooLargeAllChanges && options.newPath == null) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.tooLarge),
      );
    }
    if (diffGate != null) {
      if (!diffStarted.isCompleted) diffStarted.complete();
      await diffGate!.future;
    }
    return DiffPage(
      requestId: BigInt.from(++_request),
      layout: options.layout,
      totalRows: 1,
      offset: 0,
      rows: [
        DiffDisplayRow(
          stableId: 'comparison',
          kind: DiffRowKind.context,
          text: '${firstParent ?? 'root'}->$commit'.codeUnits,
        ),
      ],
      payloadBytes: 16,
    );
  }

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => _emptyHistoryDiff;

  @override
  Future<DiffPage> workingDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int contextLines = 3,
    DiffWhitespace whitespace = DiffWhitespace.preserve,
    DiffViewLayout layout = DiffViewLayout.unified,
    bool forceText = false,
    int maximumRows = 512,
  }) async => _emptyHistoryDiff;

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => _emptyHistoryDiff;

  @override
  Future<StagingPhase?> stagingPhase(
    RepositorySessionIdentity identity,
  ) async => null;

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) async =>
      const StagingExecutionResult(state: StagingExecutionState.completed);

  @override
  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) async => DiffSearchResult(
    requestId: requestId,
    matches: const [],
    totalMatches: 0,
    truncated: false,
  );

  @override
  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  }) async => null;

  @override
  Future<List<int>> diffHunks(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumPositions = 10000,
  }) async => const [];

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async {
    if (delayImage && !imageStarted.isCompleted) {
      imageStarted.complete();
      await releaseImage.future;
    }
    return const ImageDiffContent(
      newImage: DecodedImageContent(width: 1, height: 1, rgba: [1, 2, 3, 255]),
    );
  }

  @override
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => const ImageDiffContent();

  @override
  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = 512,
  }) async {
    if (delayQueryB && query.text == 'b' && !queryBStarted.isCompleted) {
      queryBStarted.complete();
      await releaseQueryB.future;
    }
    final rows = switch (query.text) {
      'b' => const [_b],
      'none' => const <HistoryTopologyRow>[],
      _ => const [_a, _b, _c],
    };
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: rows.length,
      offset: 0,
      rows: rows,
      laneCount: 2,
      payloadBytes: 128,
      querySequence: _request++,
      queryActive: query.active,
      acceptedQuery: query.text,
      selectedObjectIds: List.of(_selected),
      selectedFilteredOut: _selected.any(
        (id) => !rows.any((row) => row.objectId == id),
      ),
    );
  }

  @override
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = 512,
  }) async {
    calls.add('filter');
    filterRequests.add((requestId: requestId, filter: filter));
    final gate = filterGate;
    if (gate != null) {
      filterGate = null;
      await gate.future;
    }
    nativeFilter = filter;
    if (requestId == BigInt.zero) return null;
    final rows = filter.isEmpty ? const [_a, _b, _c] : const [_b, _c];
    return HistoryPage(
      requestId: requestId,
      complete: true,
      totalRows: rows.length,
      offset: 0,
      rows: rows,
      laneCount: 1,
      payloadBytes: 128,
      branchFilter: filter,
    );
  }

  @override
  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = 512,
  }) async => HistoryPage(
    requestId: requestId,
    complete: true,
    totalRows: 2,
    offset: 0,
    rows: const [_a, _c],
    laneCount: 1,
    payloadBytes: 96,
    collapsedCommits: 1,
  );

  @override
  Future<ReflogPage> reflog(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximumRows = 256,
  }) async => const ReflogPage(entries: []);

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) async => CommitInspection(
    detail: CommitIdentityDetail(
      commit: commit,
      tree: 'tree-$commit',
      parents: firstParent == null ? [?parentByCommit[commit]] : [firstParent],
      author: const [65],
      authorTime: 1,
      authorTimezone: const [43, 48, 48, 48, 48],
      committer: const [65],
      committerTime: 1,
      committerTimezone: const [43, 48, 48, 48, 48],
      message: commit.codeUnits,
    ),
    files: const [
      CommitFileChange(
        oldMode: 0x81a4,
        newMode: 0x81a4,
        kind: CommitFileChangeKind.modified,
        oldPath: [102],
        newPath: [102],
      ),
    ],
  );

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) async => CommitTreePage(commit: commit, entries: const []);

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) async => const [];

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) async =>
      const PathHistoryPage(entries: [], renameHops: 0, incomplete: false);

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) async => const RangeHistoryResult(entries: [], incomplete: false);

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
    blameRevisions.add(revision);
    return BlamePage(
      requestId: BigInt.one,
      revision: revision,
      path: path,
      totalRows: 513,
      offset: 0,
      rows: const [
        BlameRow(
          stableId: 'line-1',
          finalLine: 1,
          originalLine: 1,
          content: [97],
          author: [65],
          authorTime: 1,
          summary: [97],
          originalPath: [102],
          boundary: false,
          spanFirstLine: 1,
          spanLastLine: 1,
        ),
      ],
    );
  }

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async {
    requestedBlameOffsets.add(offset);
    return BlamePage(
      requestId: requestId,
      revision: 'a',
      path: 'src/f'.codeUnits,
      totalRows: 513,
      offset: offset,
      rows: const [
        BlameRow(
          stableId: 'line-513',
          finalLine: 513,
          originalLine: 513,
          content: [122],
          author: [65],
          authorTime: 1,
          summary: [122],
          originalPath: [102],
          boundary: false,
          spanFirstLine: 513,
          spanLastLine: 513,
        ),
      ],
    );
  }

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) async => RestorePreview(
    token: BigInt.one,
    commit: commit,
    path: path,
    sourceBytes: const [],
  );

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) async {
    restoredToken = token;
    return const RestoreResult(state: RestoreState.restored);
  }

  @override
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) async => const ActivityPage(records: [], evictedThroughId: null);
  @override
  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) async => const ActivityPage(records: [], evictedThroughId: null);
  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => throw UnimplementedError();

  @override
  Future<CommitTools> commitTools(RepositorySessionIdentity identity) async =>
      const CommitTools();

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) async => CommitPreview(
    token: BigInt.one,
    warnings: const [],
    arguments: const ['commit', '--file=-'],
  );

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const CommitExecutionResult(state: CommitExecutionState.completed);

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) async => DiscardPreview(
    token: BigInt.one,
    kind: DiscardKind.discard,
    fileCount: 1,
    arguments: [],
  );

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async =>
      const DiscardExecutionResult(state: DiscardExecutionState.completed);

  @override
  Future<bool> close(RepositorySessionIdentity identity) async => true;
  @override
  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  }) async => const [];
  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) async => const IndexLockInspection(present: false);
  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  }) => open(path, generation);
  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  open(String path, int generation) async => (
    identity: RepositorySessionIdentity(
      nativeId: BigInt.one,
      generation: generation,
    ),
    snapshot: RepositorySnapshot(
      revision: BigInt.zero,
      phase: RepositoryPhase.ready,
    ),
  );
  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) =>
      open('', generation);
  @override
  Future<void> refresh(RepositorySessionIdentity identity) async {}
  @override
  Future<void> removeIndexLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {}

  @override
  Future<StatusAcceleration> statusAcceleration(
    RepositorySessionIdentity identity,
  ) async => const StatusAcceleration(
    untrackedCache: true,
    fsmonitor: false,
    fsmonitorAvailable: false,
  );

  @override
  Future<StatusAcceleration> enableStatusAcceleration(
    RepositorySessionIdentity identity,
  ) => statusAcceleration(identity);

  @override
  Future<RepositoryLockInspection> inspectRepositoryLocks(
    RepositorySessionIdentity identity,
  ) async => const RepositoryLockInspection(locks: []);

  @override
  Future<bool> removeRepositoryLock(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => false;
}

final _emptyHistoryDiff = DiffPage(
  requestId: BigInt.zero,
  layout: DiffViewLayout.unified,
  totalRows: 0,
  offset: 0,
  rows: const [],
  payloadBytes: 0,
);

const _a = HistoryTopologyRow(
  objectId: 'a',
  lit: true,
  parents: ['b'],
  refs: [],
  lane: 0,
  shape: 0,
);
const _b = HistoryTopologyRow(
  objectId: 'b',
  parents: ['c'],
  refs: [],
  lane: 1,
  shape: 0,
);
const _c = HistoryTopologyRow(
  objectId: 'c',
  parents: [],
  refs: [],
  lane: 0,
  shape: 0,
);
