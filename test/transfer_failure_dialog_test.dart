import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/transfer_failure_dialog.dart';
import 'package:gitlama/app/workspace/transfer_failure_guide.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/operation_failure.dart';
import 'package:gitlama/models/repository_lock.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/services/workflows/transfer_workflows.dart';
import 'package:gitlama/widgets/status_notification.dart';

final class _Locks implements RepositoryLockControls {
  _Locks(this.inspections, {this.canRemove = true});

  final List<RepositoryLockInspection> inspections;
  final List<List<RepositoryLock>> removed = [];
  IndexLockFailureCode? refuse;
  var inspected = 0;

  @override
  final bool canRemove;

  @override
  Future<RepositoryLockInspection> inspect() async =>
      inspections[(inspected++).clamp(0, inspections.length - 1)];

  @override
  Future<int> remove(List<RepositoryLock> locks) async {
    if (refuse case final code?) throw IndexLockException(code);
    removed.add(locks);
    return locks.length;
  }
}

RepositoryLock _lock(String path, Duration? age) => RepositoryLock(
  token: BigInt.from(path.length),
  path: path,
  worktreeScoped: false,
  sizeBytes: 0,
  age: age,
);

TransferFailureReport _report({
  TransferRequest request = const TransferRequest(
    kind: TransferKind.fetch,
    remote: 'origin',
  ),
  TransferFailureCode failure = TransferFailureCode.locked,
  TransferDiagnosis? diagnosis,
  RepositoryBackendKind backend = RepositoryBackendKind.local,
}) => TransferFailureReport(
  request: request,
  result: TransferExecutionResult(
    state: TransferExecutionState.failed,
    failure: failure,
    diagnosis: diagnosis,
    ahead: BigInt.zero,
    behind: BigInt.zero,
  ),
  session: RepositorySessionIdentity(
    nativeId: BigInt.one,
    generation: 1,
    backend: backend,
  ),
);

const _collision = TransferDiagnosis(
  kind: TransferDiagnosisKind.refCaseCollision,
  reference: 'refs/remotes/origin/npt/chore/sync',
  related: ['refs/remotes/origin/NPT/chore/sync'],
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('catalog', () {
    List<String> ids(FailureGuide guide) => [
      for (final action in guide.actions) action.id,
    ];

    test(
      'reapply recovery explains a completed pull without offering another pull',
      () async {
        for (final locale in ['en', 'de']) {
          final translated = await AppLocalizations.delegate.load(
            Locale(locale),
          );
          final report = TransferFailureReport(
            request: const TransferRequest(
              kind: TransferKind.pull,
              stashBeforePull: true,
            ),
            result: TransferExecutionResult(
              state: TransferExecutionState.completed,
              stash: const PullStashResult(
                objectId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                pullCompleted: true,
                reapplyCompleted: false,
                conflicted: true,
              ),
              ahead: BigInt.zero,
              behind: BigInt.zero,
            ),
            session: null,
          );
          final guide = transferFailureGuide(translated, report);
          expect(TransferFailureReport.explains(report.result), isTrue);
          expect(guide.message, translated.transferPullStashConflict);
          expect(guide.explanation, translated.transferPullRecoveryHelp);
          expect(guide.actions, isEmpty);
          expect(guide.showsLocks, isFalse);
        }
      },
    );

    test('a case collision names both spellings and repairs them', () {
      final guide = transferFailureGuide(l10n, _report(diagnosis: _collision));
      expect(guide.title, l10n.failureCaseCollisionTitle);
      expect(guide.message, contains('origin/npt/chore/sync'));
      expect(guide.message, contains('origin/NPT/chore/sync'));
      expect(ids(guide), ['retryWithoutPrune', 'repairTrackingRefs']);
      final repair = guide.actions.last.remedy as RepairTrackingRefs;
      expect(repair.references, [
        'refs/remotes/origin/npt/chore/sync',
        'refs/remotes/origin/NPT/chore/sync',
      ]);
    });

    test('another computer only explains a case collision', () {
      final guide = transferFailureGuide(
        l10n,
        _report(
          diagnosis: _collision,
          backend: RepositoryBackendKind.remote,
          request: const TransferRequest(
            kind: TransferKind.fetch,
            prune: false,
          ),
        ),
      );
      expect(guide.explanation, l10n.failureCaseCollisionServer);
      expect(guide.actions, isEmpty);
    });

    test('a lock offers removal, a fetch without pruning and a retry', () {
      expect(ids(transferFailureGuide(l10n, _report())), [
        'removeLocksAndRetry',
        'retryWithoutPrune',
        'retry',
      ]);
      expect(
        ids(
          transferFailureGuide(
            l10n,
            _report(request: const TransferRequest(kind: TransferKind.pull)),
          ),
        ),
        ['removeLocksAndRetry', 'retry'],
      );
    });

    test('a rejected push behind the remote offers a fetch', () {
      final guide = transferFailureGuide(
        l10n,
        _report(
          failure: TransferFailureCode.rejected,
          diagnosis: const TransferDiagnosis(
            kind: TransferDiagnosisKind.remoteAhead,
          ),
        ),
      );
      expect(guide.title, l10n.failureRemoteAheadTitle);
      expect(ids(guide), ['fetch']);
      expect(guide.actions.single.remedy, isA<FetchRemote>());
    });

    test('only failures with an entry reach the catalog', () {
      expect(TransferFailureReport.explains(_report().result), isTrue);
      expect(
        TransferFailureReport.explains(
          _report(failure: TransferFailureCode.rejected).result,
        ),
        isFalse,
      );
    });
  });

  Future<Future<TransferRemedy?>> open(
    WidgetTester tester,
    TransferFailureReport report,
    _Locks locks,
  ) async {
    late Future<TransferRemedy?> result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => StatusNotificationScope(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => result = showTransferFailureDialog(
                  context,
                  guide: transferFailureGuide(l10n, report),
                  details: const OperationFailureDetails(
                    operation: UserOperationKind.transfer,
                  ),
                  locks: locks,
                ),
                child: const Text('Fetch'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();
    return result;
  }

  Finder action(String id) => find.byKey(ValueKey('transfer-failure-$id'));

  testWidgets('stale locks are listed and removed before the retry', (
    tester,
  ) async {
    final stale = [
      _lock(
        'refs/remotes/origin/npt/chore/sync.lock',
        const Duration(hours: 3),
      ),
      _lock('packed-refs.lock', const Duration(minutes: 7)),
    ];
    final locks = _Locks([RepositoryLockInspection(locks: stale)]);
    final result = await open(tester, _report(), locks);
    expect(find.text(l10n.repositoryLockTitle), findsOneWidget);
    expect(
      find.text('refs/remotes/origin/npt/chore/sync.lock'),
      findsOneWidget,
    );
    expect(find.text('3 hours ago'), findsOneWidget);
    expect(find.text('7 minutes ago'), findsOneWidget);
    expect(find.text(l10n.repositoryLockStale), findsOneWidget);
    expect(find.text(l10n.repositoryLockRemoveWarning), findsOneWidget);

    await tester.tap(action('removeLocksAndRetry'));
    await tester.pumpAndSettle();
    expect(locks.removed.single, stale);
    expect(await result, isA<RetryTransfer>());
  });

  testWidgets('a changed lock is kept and explained', (tester) async {
    final locks = _Locks([
      RepositoryLockInspection(
        locks: [_lock('index.lock', const Duration(seconds: 5))],
      ),
    ])..refuse = IndexLockFailureCode.changed;
    await open(tester, _report(), locks);
    expect(find.text(l10n.repositoryLockRecent), findsOneWidget);
    await tester.tap(action('removeLocksAndRetry'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.repositoryLockChanged), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transfer-failure-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('a released lock invites a plain retry; Cancel declines', (
    tester,
  ) async {
    final locks = _Locks([
      RepositoryLockInspection(
        locks: [_lock('index.lock', const Duration(seconds: 2))],
      ),
      const RepositoryLockInspection(locks: []),
    ]);
    final result = await open(tester, _report(), locks);
    await tester.tap(find.byKey(const ValueKey('repository-lock-check-again')));
    await tester.pumpAndSettle();
    expect(locks.inspected, 2);
    expect(find.text(l10n.repositoryLockNone), findsOneWidget);
    expect(action('removeLocksAndRetry'), findsNothing);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('locks on another computer are only listed', (tester) async {
    final locks = _Locks([
      RepositoryLockInspection(
        locks: [_lock('HEAD.lock', null)],
        truncated: true,
      ),
    ], canRemove: false);
    final result = await open(
      tester,
      _report(backend: RepositoryBackendKind.remote),
      locks,
    );
    expect(find.text(l10n.repositoryLockAgeUnknown), findsOneWidget);
    expect(find.text(l10n.repositoryLockTruncated), findsOneWidget);
    expect(find.text(l10n.repositoryLockRemoteOnly), findsOneWidget);
    expect(action('removeLocksAndRetry'), findsNothing);
    await tester.tap(action('retry'));
    await tester.pumpAndSettle();
    expect(await result, isA<RetryTransfer>());
  });

  testWidgets('a case collision explains itself without listing locks', (
    tester,
  ) async {
    final locks = _Locks([const RepositoryLockInspection(locks: [])]);
    final result = await open(tester, _report(diagnosis: _collision), locks);
    expect(find.text(l10n.failureCaseCollisionTitle), findsOneWidget);
    expect(find.text(l10n.failureCaseCollisionRepair), findsOneWidget);
    expect(locks.inspected, 0);
    expect(find.byKey(const ValueKey('repository-lock-list')), findsNothing);
    await tester.tap(action('repairTrackingRefs'));
    await tester.pumpAndSettle();
    expect(await result, isA<RepairTrackingRefs>());
  });
}
