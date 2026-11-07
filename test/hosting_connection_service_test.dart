import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/hosting_link_cache_codec.dart';
import 'package:gitlama/repositories/impl/private_entry_store.dart';
import 'package:gitlama/repositories/impl/coded_cache_repositories.dart';
import 'package:gitlama/app/workspace/hosting_links.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/hosting_link_cache.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/hosting_repository.dart';
import 'package:gitlama/services/hosting_connection_service.dart';
import 'package:gitlama/services/hosting_repository_session.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_settings_repository.dart';
import 'support/fake_hosting_preset_defaults.dart';

void main() {
  test(
    'migration drops invalid metadata without touching secure data',
    () async {
      final valid = _connection('github:valid');
      final invalid = _connection('github:invalid');
      final settingsRepository = FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.migrated,
          document: SettingsDocument(
            hostingConnections: [valid, invalid],
            hostingBindings: [_binding(valid.id, 1), _binding(invalid.id, 2)],
          ),
        ),
      );
      final settings = SettingsService(settingsRepository);
      await settings.initialize();
      final repository = _HostingRepository()..invalidIds.add(invalid.id);
      final service = HostingConnectionService(repository, settings);

      await service.initialize();

      expect(service.connections.map((value) => value.id), [valid.id]);
      expect(settings.current.hostingBindings.single.connectionId, valid.id);
      expect(repository.removedIds, isEmpty);
      await service.dispose();
      await settings.dispose();
    },
  );

  test(
    'unreadable credential blocks removal and preserves every account',
    () async {
      final first = _connection('github:first');
      final second = _connection('github:second');
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(
              hostingConnections: [first, second],
              hostingBindings: [_binding(first.id, 1), _binding(second.id, 2)],
            ),
          ),
        ),
      );
      await settings.initialize();
      final repository = _HostingRepository()
        ..credentialStates[first.id] = HostingCredentialState.unreadable;
      final service = HostingConnectionService(repository, settings);
      await service.initialize();

      await expectLater(
        service.removeConnection(first.id),
        throwsA(
          isA<HostingException>().having(
            (error) => error.code,
            'code',
            HostingFailureCode.credentialUnreadable,
          ),
        ),
      );

      expect(service.connections.map((value) => value.id), [
        first.id,
        second.id,
      ]);
      expect(settings.current.hostingBindings, hasLength(2));
      expect(repository.removedIds, isEmpty);
      await service.dispose();
      await settings.dispose();
    },
  );

  test('a rejected save leaves no unsaved connection listed', () async {
    final settingsRepository = FakeSettingsRepository()
      ..saveFailure = const SettingsException(
        SettingsFailureCode.invalidDocument,
      );
    final settings = SettingsService(
      settingsRepository,
      debounce: Duration.zero,
    );
    await settings.initialize();
    final service = HostingConnectionService(_HostingRepository(), settings);
    await service.initialize();
    final changes = <List<HostingConnection>>[];
    final subscription = service.changes.listen(changes.add);

    await expectLater(
      service.saveConnection(_connection('github:rejected')),
      throwsA(isA<SettingsException>()),
    );

    expect(service.connections, isEmpty);
    expect(changes, isEmpty);
    // Later settings saves are not blocked by the rejected connection.
    settingsRepository.saveFailure = null;
    await settings.flush();
    expect(settingsRepository.saves.last.hostingConnections, isEmpty);
    await subscription.cancel();
    await service.dispose();
    await settings.dispose();
  });

  test('removal deletes only the selected identity and its bindings', () async {
    final first = _connection('github:first');
    final second = _connection('github:second');
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(
            hostingConnections: [first, second],
            hostingBindings: [_binding(first.id, 1), _binding(second.id, 2)],
          ),
        ),
      ),
    );
    await settings.initialize();
    final repository = _HostingRepository();
    final service = HostingConnectionService(repository, settings);
    await service.initialize();

    await service.removeConnection(first.id);

    expect(service.connections.map((value) => value.id), [second.id]);
    expect(settings.current.hostingBindings.single.connectionId, second.id);
    expect(repository.removedIds, [first.id]);
    await service.dispose();
    await settings.dispose();
  });

  test(
    'authorization owns login persistence and disposal cancellation',
    () async {
      final pending = _connection('github:pending').copyWith(login: '');
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: const LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(),
          ),
        ),
      );
      await settings.initialize();
      final repository = _HostingRepository();
      final service = HostingConnectionService(repository, settings);
      await service.initialize();

      final started = await service.startAuthorization(pending);
      repository.oauthSnapshots[started.requestId] = HostingOAuthSnapshot(
        requestId: started.requestId,
        state: HostingOAuthState.succeeded,
        authenticatedLogin: 'authenticated-user',
      );
      final completed = await service.pollAuthorization(
        connectionId: pending.id,
        requestId: started.requestId,
      );

      expect(completed!.state, HostingOAuthState.succeeded);
      expect(service.connections.single.login, 'authenticated-user');
      final second = await service.startAuthorization(pending);
      await service.dispose();
      expect(repository.canceledIds, [second.requestId]);
      expect(repository.shutdowns, 1);
      await settings.dispose();
    },
  );

  test('following an authorization polls until it ends', () async {
    final pending = _connection('github:follow').copyWith(login: '');
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: const LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(),
        ),
      ),
    );
    await settings.initialize();
    final repository = _HostingRepository();
    final service = HostingConnectionService(repository, settings);
    await service.initialize();

    final started = await service.startAuthorization(pending);
    final seen = <HostingOAuthState>[];
    final done = Completer<void>();
    service
        .followAuthorization(
          connectionId: pending.id,
          requestId: started.requestId,
          interval: Duration.zero,
        )
        .listen((snapshot) {
          seen.add(snapshot.state);
          if (seen.length == 2) {
            repository.oauthSnapshots[started.requestId] = HostingOAuthSnapshot(
              requestId: started.requestId,
              state: HostingOAuthState.succeeded,
              authenticatedLogin: 'followed-user',
            );
          }
        }, onDone: done.complete);
    await done.future;

    expect(seen, [
      HostingOAuthState.queued,
      HostingOAuthState.queued,
      HostingOAuthState.succeeded,
    ]);
    expect(service.connections.single.login, 'followed-user');
    expect(
      await service
          .followAuthorization(
            connectionId: pending.id,
            requestId: started.requestId,
            interval: Duration.zero,
          )
          .isEmpty,
      isTrue,
      reason: 'a finished authorization is no longer followed',
    );
    await service.dispose();
    await settings.dispose();
  });

  test('resource lifecycle cancels on deactivation and shutdown', () async {
    final connection = _connection('github:resources');
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(hostingConnections: [connection]),
        ),
      ),
    );
    await settings.initialize();
    final repository = _HostingRepository();
    final service = HostingConnectionService(repository, settings);
    await service.initialize();

    final first = await service.refreshResources(
      connectionId: connection.id,
      providerRepository: 'team/project',
    );
    await service.deactivateResources(
      connectionId: connection.id,
      providerRepository: 'team/project',
    );
    expect(repository.deactivatedResources, [(connection.id, 'team/project')]);
    expect(await service.pollResourceRefresh(first.requestId), isNull);

    final second = await service.refreshResources(
      connectionId: connection.id,
      providerRepository: 'team/project',
      page: 2,
      manual: true,
    );
    await service.dispose();
    expect(repository.canceledResourceIds, [second.requestId]);
    expect(repository.shutdowns, 1);
    await settings.dispose();
  });

  test(
    'binding overrides and tree expansion persist through the service',
    () async {
      final connection = _connection('github:binding');
      final settingsRepository = FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(hostingConnections: [connection]),
        ),
      );
      final settings = SettingsService(settingsRepository);
      await settings.initialize();
      final service = HostingConnectionService(_HostingRepository(), settings);
      await service.initialize();
      final repository = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: [1, 2, 3],
      );

      await service.saveBinding(
        HostingBindingOverride(
          repository: repository,
          remote: 'origin'.codeUnits,
          connectionId: connection.id,
          providerRepository: 'team/project',
        ),
      );
      service.setExpandedNodes(['issues', 'changeRequests', 'issues']);
      await settings.flush();

      expect(
        service.bindingFor(repository)!.providerRepository,
        'team/project',
      );
      expect(service.expandedNodes, ['changeRequests', 'issues']);
      expect(settingsRepository.saves.last.hostingExpandedNodes, [
        'changeRequests',
        'issues',
      ]);

      await service.clearBinding(repository);
      expect(service.bindingFor(repository), isNull);
      await service.dispose();
      await settings.dispose();
    },
  );

  group('repository session', () {
    final repositoryIdentity = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: [7],
    );
    final remotes = [
      HostingRemote(
        name: 'origin'.codeUnits,
        url: 'https://github.com/team/project.git',
      ),
    ];

    Future<(HostingConnectionService, _HostingRepository, SettingsService)>
    boundService({_MemoryLinkCache? linkCache}) async {
      final connection = _connection('github:alice');
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(hostingConnections: [connection]),
          ),
        ),
      );
      await settings.initialize();
      final repository = _HostingRepository()
        ..binding = HostingBindingResolution(
          state: HostingBindingState.bound,
          remote: 'origin'.codeUnits,
          connectionId: connection.id,
          providerRepository: 'team/project',
        );
      final service = HostingConnectionService(
        repository,
        settings,
        linkCache: linkCache == null
            ? null
            : CodedHostingLinkCacheRepository(linkCache),
        linkPersistDelay: const Duration(milliseconds: 10),
      );
      await service.initialize();
      return (service, repository, settings);
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 700));

    test(
      'links visible branches on demand and marks authored pull requests',
      () async {
        final (service, repository, settings) = await boundService();
        repository
          ..branchPulls['feature/topic'] = [_pull(7, 'feature/topic', 'bob')]
          ..authoredPulls = [_pull(9, 'mine', 'alice')];
        final session = service.openRepositorySession();
        await session.update(repositoryIdentity, remotes);

        session.requestBranches(['feature/topic', 'quiet']);
        session.requestBranches(['quiet']);
        await settle();

        expect(repository.lookups, [('feature/topic,quiet', 'alice')]);
        expect(
          session.pullRequestsForBranch('feature/topic')!.single.number,
          7,
        );
        expect(session.pullRequestsForBranch('quiet'), isEmpty);
        expect(session.pullRequestsForBranch('unasked'), isNull);
        expect(
          [
            for (final linked in session.linkedPullRequests)
              (linked.pull.number, linked.authored),
          ],
          [(9, true), (7, false)],
        );
        expect(session.lookingUp, isFalse);

        // Known branches are not asked again.
        session.requestBranches(['feature/topic', 'quiet']);
        await settle();
        expect(repository.lookups, hasLength(1));

        session.dispose();
        await service.dispose();
        await settings.dispose();
      },
    );

    test('a failed lookup keeps resolved branches and does not retry until a '
        'manual refresh', () async {
      final (service, repository, settings) = await boundService();
      repository
        ..branchPulls['first'] = [_pull(3, 'first', 'bob')]
        ..failingBranches.add('broken');
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      await settle();
      repository.lookups.clear();

      session.requestBranches(['first', 'broken']);
      await settle();
      expect(session.pullRequestsForBranch('first')!.single.number, 3);
      expect(session.lookupFailure, HostingResourceFailure.rateLimited);
      session.requestBranches(['broken']);
      await settle();
      expect(repository.lookups, [('first,broken', null)]);

      repository.failingBranches.clear();
      await session.refresh(manual: true);
      session.requestBranches(['broken']);
      await settle();
      expect(repository.lookups.last.$1, 'broken');
      expect(session.pullRequestsForBranch('broken'), isEmpty);

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('cached links show at once and are looked up again when asked for, '
        'then stored', () async {
      final storage = _MemoryLinkCache()
        ..entries[repositoryIdentity] = encodeHostingLinks(
          HostingLinkCacheEntry(
            connectionId: 'github:alice',
            providerRepository: 'team/project',
            branches: {
              'feature/topic': [_pull(7, 'feature/topic', 'bob')],
            },
            authored: [_pull(9, 'mine', 'alice')],
          ),
        );
      final (service, repository, settings) = await boundService(
        linkCache: storage,
      );
      repository
        ..branchPulls['feature/topic'] = [
          _pull(
            7,
            'feature/topic',
            'bob',
            state: HostingChangeRequestState.merged,
          ),
        ]
        ..authoredPulls = const [];
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      // The cache answers before any lookup has run.
      await Future<void>.delayed(Duration.zero);
      expect(
        session.pullRequestsForBranch('feature/topic')!.single.state,
        HostingChangeRequestState.open,
      );
      expect(session.linkedPullRequests.map((linked) => linked.pull.number), [
        9,
        7,
      ]);

      session.requestBranches(['feature/topic']);
      await settle();
      expect(repository.lookups.last, ('feature/topic', 'alice'));
      expect(
        session.pullRequestsForBranch('feature/topic')!.single.state,
        HostingChangeRequestState.merged,
      );
      // The authored query answered that the account has none open now.
      expect(session.linkedPullRequests.map((linked) => linked.pull.number), [
        7,
      ]);

      final stored = decodeHostingLinks(storage.entries[repositoryIdentity]!)!;
      expect(
        stored.branches['feature/topic']!.single.state,
        HostingChangeRequestState.merged,
      );
      expect(stored.authored, isEmpty);

      // A manual refresh keeps the links shown while they are looked up again.
      repository.lookups.clear();
      await session.refresh(manual: true);
      expect(session.pullRequestsForBranch('feature/topic'), hasLength(1));
      session.requestBranches(['feature/topic']);
      await settle();
      expect(repository.lookups.map((lookup) => lookup.$1), ['feature/topic']);

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('a cache entry of another binding is not shown', () async {
      final storage = _MemoryLinkCache()
        ..entries[repositoryIdentity] = encodeHostingLinks(
          HostingLinkCacheEntry(
            connectionId: 'github:other',
            providerRepository: 'team/project',
            branches: {
              'feature/topic': [_pull(7, 'feature/topic', 'bob')],
            },
          ),
        );
      final (service, _, settings) = await boundService(linkCache: storage);
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      await Future<void>.delayed(Duration.zero);
      expect(session.pullRequestsForBranch('feature/topic'), isNull);
      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('merged pull requests follow the open ones', () async {
      final (service, repository, settings) = await boundService();
      repository
        ..branchPulls['done'] = [
          _pull(12, 'done', 'bob', state: HostingChangeRequestState.merged),
        ]
        ..branchPulls['topic'] = [_pull(3, 'topic', 'bob')];
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      session.requestBranches(['done', 'topic']);
      await settle();
      expect(
        [
          for (final linked in session.linkedPullRequests)
            (linked.pull.number, linked.pull.state),
        ],
        [
          (3, HostingChangeRequestState.open),
          (12, HostingChangeRequestState.merged),
        ],
      );
      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('a pull request linked only through a deleted branch is not shown, '
        "while the account's open ones stay", () async {
      final (service, repository, settings) = await boundService();
      repository
        ..branchPulls['feature/topic'] = [_pull(7, 'feature/topic', 'bob')]
        ..branchPulls['local-only'] = [_pull(8, 'local-only', 'bob')]
        ..branchPulls['done'] = [
          _pull(12, 'done', 'alice', state: HostingChangeRequestState.merged),
        ]
        ..authoredPulls = [_pull(9, 'mine', 'alice')];
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      session.requestBranches(['feature/topic', 'local-only', 'done']);
      await settle();
      expect(
        [
          for (final linked in session.linkedPullRequests)
            (linked.pull.number, linked.viaBranch),
        ],
        [(9, false), (12, true), (8, true), (7, true)],
      );

      HostingLinks links(RepositoryRefs refs) =>
          HostingLinks(session: session, refs: refs, onOpen: (_) {});
      final withBranches = RepositoryRefs(
        branches: [
          RepositoryReference(
            name: 'work'.codeUnits,
            target: 'b',
            upstream: 'refs/remotes/origin/local-only'.codeUnits,
            upstreamGone: true,
          ),
        ],
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: const [],
            branches: [
              RepositoryReference(name: 'feature/topic'.codeUnits, target: 'a'),
              RepositoryReference(name: 'done'.codeUnits, target: 'c'),
            ],
          ),
        ],
      );
      expect(links(withBranches).linked.map((linked) => linked.pull.number), [
        9,
        12,
        8,
        7,
      ]);
      // The merged branch was deleted on the server and pruned locally; the
      // tracking local branch keeps its pull request.
      final pruned = RepositoryRefs(
        branches: withBranches.branches,
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: const [],
            branches: [
              RepositoryReference(name: 'feature/topic'.codeUnits, target: 'a'),
            ],
          ),
        ],
      );
      expect(links(pruned).linked.map((linked) => linked.pull.number), [
        9,
        8,
        7,
      ]);
      expect(
        links(
          const RepositoryRefs(),
        ).linked.map((linked) => linked.pull.number),
        [9],
      );
      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('a pull request stands only at the commit of its head, with its '
        'checks and mergeability', () async {
      final (service, repository, settings) = await boundService();
      repository.branchPulls['topic'] = [
        _pull(
          7,
          'topic',
          'bob',
          head: 'head',
          checks: HostingCheckState.failing,
          mergeability: HostingMergeability.conflicting,
        ),
      ];
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      session.requestBranches(['topic']);
      await settle();
      repository.lookups.clear();

      RepositoryRefs refs({required String local, required String remote}) =>
          RepositoryRefs(
            branches: [
              RepositoryReference(
                name: 'topic'.codeUnits,
                target: local,
                upstream: 'refs/remotes/origin/topic'.codeUnits,
              ),
            ],
            remotes: [
              RepositoryRemote(
                name: 'origin'.codeUnits,
                displayUrl: const [],
                branches: [
                  RepositoryReference(name: 'topic'.codeUnits, target: remote),
                ],
              ),
            ],
          );
      const local = 'refs/heads/topic';
      const tracking = 'refs/remotes/origin/topic';
      Map<String, HistoryReferencePullRequest> at(
        RepositoryRefs refs,
        String objectId,
        List<String> names,
      ) => HostingLinks(
        session: session,
        refs: refs,
        onOpen: (_) {},
      ).pullRequestsForRefs(objectId, names);

      // Pushed: the remote-tracking branch is at the head, the local branch
      // has a newer commit.
      final pushed = refs(local: 'newer', remote: 'head');
      final remoteChip = at(pushed, 'head', [tracking])[tracking]!;
      expect(remoteChip.number, 7);
      expect(remoteChip.checks, HostingCheckState.failing);
      expect(remoteChip.mergeability, HostingMergeability.conflicting);
      expect(remoteChip.outdated, isFalse);
      expect(at(pushed, 'newer', [local]), isEmpty);

      // Not fetched yet: the local branch is at the head.
      final ahead = refs(local: 'head', remote: 'older');
      expect(at(ahead, 'head', [local]).keys, [local]);
      expect(at(ahead, 'older', [tracking]), isEmpty);
      await settle();
      expect(repository.lookups, isEmpty);

      // No ref is at the head: the remote-tracking branch shows it as
      // outdated, and the branch is looked up again at once for these refs.
      final moved = refs(local: 'mine', remote: 'theirs');
      expect(at(moved, 'mine', [local]), isEmpty);
      expect(at(moved, 'theirs', [tracking])[tracking]!.outdated, isTrue);
      await settle();
      expect(repository.lookups, [('topic', null)]);
      at(moved, 'theirs', [tracking]);
      await settle();
      expect(repository.lookups, hasLength(1));

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('a pull request whose host has not caught up with a push is looked '
        'up again a few times later', () async {
      final (service, repository, settings) = await boundService();
      repository.branchPulls['topic'] = [
        _pull(7, 'topic', 'bob', head: 'before'),
      ];
      final session = HostingRepositorySession(
        service,
        showResources: true,
        movedRecheckDelay: const Duration(milliseconds: 50),
      );
      await session.update(repositoryIdentity, remotes);
      session.requestBranches(['topic']);
      await settle();
      repository.lookups.clear();

      // Pushed: both refs are at the new commit, the host still answers the
      // previous head.
      final pushed = RepositoryRefs(
        branches: [
          RepositoryReference(
            name: 'topic'.codeUnits,
            target: 'pushed',
            upstream: 'refs/remotes/origin/topic'.codeUnits,
          ),
        ],
        remotes: [
          RepositoryRemote(
            name: 'origin'.codeUnits,
            displayUrl: const [],
            branches: [
              RepositoryReference(name: 'topic'.codeUnits, target: 'pushed'),
            ],
          ),
        ],
      );
      const tracking = 'refs/remotes/origin/topic';
      HistoryReferencePullRequest? chip() => HostingLinks(
        session: session,
        refs: pushed,
        onOpen: (_) {},
      ).pullRequestsForRefs('pushed', [tracking])[tracking];

      expect(chip()!.outdated, isTrue);
      await settle();
      expect(repository.lookups, hasLength(1));
      // Each later answer that is still behind asks again, up to a limit.
      for (var attempt = 2; attempt <= 4; attempt++) {
        expect(chip()!.outdated, isTrue);
        await settle();
        expect(repository.lookups, hasLength(attempt));
      }
      expect(chip()!.outdated, isTrue);
      await settle();
      expect(repository.lookups, hasLength(4));

      // Once the host caught up, the chip is current.
      final next = HostingRepositorySession(
        service,
        showResources: true,
        movedRecheckDelay: const Duration(milliseconds: 50),
      );
      repository.branchPulls['topic'] = [
        _pull(7, 'topic', 'bob', head: 'before'),
      ];
      await next.update(repositoryIdentity, remotes);
      next.requestBranches(['topic']);
      await settle();
      HistoryReferencePullRequest? nextChip() => HostingLinks(
        session: next,
        refs: pushed,
        onOpen: (_) {},
      ).pullRequestsForRefs('pushed', [tracking])[tracking];
      expect(nextChip()!.outdated, isTrue);
      await settle();
      repository.branchPulls['topic'] = [
        _pull(7, 'topic', 'bob', head: 'pushed'),
      ];
      expect(nextChip()!.outdated, isTrue);
      await settle();
      expect(nextChip()!.outdated, isFalse);
      next.dispose();

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('branches with running checks are looked up again later', () async {
      final (service, repository, settings) = await boundService();
      repository
        ..branchPulls['running'] = [
          _pull(4, 'running', 'bob', checks: HostingCheckState.pending),
        ]
        ..branchPulls['done'] = [
          _pull(5, 'done', 'bob', checks: HostingCheckState.passing),
        ];
      final session = HostingRepositorySession(
        service,
        showResources: true,
        pendingRecheckDelay: const Duration(milliseconds: 300),
      );
      await session.update(repositoryIdentity, remotes);
      await settle();
      repository.lookups.clear();
      session.requestBranches(['running', 'done']);
      await settle();
      expect(repository.lookups, [('running,done', null)]);

      repository.branchPulls['running'] = [
        _pull(4, 'running', 'bob', checks: HostingCheckState.passing),
      ];
      await settle();
      expect(repository.lookups.last.$1, 'running');
      expect(
        session.pullRequestsForBranch('running')!.single.checks.state,
        HostingCheckState.passing,
      );
      // Settled answers are not asked again.
      await settle();
      expect(repository.lookups, hasLength(2));

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('reads the CI result of a head, again while its checks run, and '
        'again for a moved head', () async {
      final (service, repository, settings) = await boundService();
      const main = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const moved = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      repository.headChecks[main] = HostingCheckState.pending;
      final session = HostingRepositorySession(
        service,
        showResources: true,
        pendingRecheckDelay: const Duration(milliseconds: 300),
      );
      await session.update(repositoryIdentity, remotes);
      await settle();
      repository.lookups.clear();

      expect(session.requestHeadChecks(main), isNull);
      expect(session.requestHeadChecks(main), isNull);
      await settle();
      expect(repository.headLookups, [
        [main],
      ]);
      expect(session.requestHeadChecks(main), HostingCheckState.pending);

      repository.headChecks[main] = HostingCheckState.passing;
      await settle();
      expect(repository.headLookups, hasLength(2));
      expect(session.requestHeadChecks(main), HostingCheckState.passing);
      // A settled result is not asked again.
      await settle();
      expect(repository.headLookups, hasLength(2));
      // Heads alone ask for no branches.
      expect(repository.lookups, isEmpty);

      repository.headChecks[moved] = HostingCheckState.failing;
      expect(session.requestHeadChecks(moved), isNull);
      await settle();
      expect(repository.headLookups.last, [moved]);
      expect(session.requestHeadChecks(moved), HostingCheckState.failing);

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('a failed head lookup is not retried until a manual refresh, which '
        'keeps the known result shown', () async {
      final (service, repository, settings) = await boundService();
      const main = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      repository.headChecks[main] = HostingCheckState.failing;
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      await settle();
      session.requestHeadChecks(main);
      await settle();
      expect(session.requestHeadChecks(main), HostingCheckState.failing);

      repository.failHeads = true;
      await session.refresh(manual: true);
      expect(session.requestHeadChecks(main), HostingCheckState.failing);
      await settle();
      expect(repository.headLookups, hasLength(2));
      expect(session.requestHeadChecks(main), HostingCheckState.failing);
      await settle();
      expect(repository.headLookups, hasLength(2));

      repository.failHeads = false;
      repository.headChecks[main] = HostingCheckState.passing;
      await session.refresh(manual: true);
      await settle();
      expect(repository.headLookups, hasLength(3));
      expect(session.requestHeadChecks(main), HostingCheckState.passing);

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('History shows the main branch\'s CI result on its remote-tracking '
        'branch at its commit only', () async {
      final (service, repository, settings) = await boundService();
      const main = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      repository.headChecks[main] = HostingCheckState.failing;
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      await settle();
      final links = HostingLinks(
        session: session,
        refs: RepositoryRefs(
          branches: [
            RepositoryReference(
              name: 'main'.codeUnits,
              target: main,
              upstream: 'refs/remotes/origin/main'.codeUnits,
            ),
          ],
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: const [],
              branches: [
                RepositoryReference(name: 'main'.codeUnits, target: main),
              ],
            ),
          ],
        ),
        onOpen: (_) {},
      );
      const tracking = 'refs/remotes/origin/main';
      const refs = ['refs/heads/main', tracking];

      // Unknown until the lookup answers, then on the remote-tracking branch.
      expect(links.defaultBranchChecksForRefs(main, refs), isEmpty);
      await settle();
      expect(repository.headLookups, [
        [main],
      ]);
      expect(links.defaultBranchChecksForRefs(main, refs), {
        tracking: HostingCheckState.failing,
      });
      // Not on another commit, nor without the remote-tracking branch.
      expect(links.defaultBranchChecksForRefs('other', refs), isEmpty);
      expect(
        links.defaultBranchChecksForRefs(main, ['refs/heads/main']),
        isEmpty,
      );

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });

    test('a later page appends only its own rows, once each', () async {
      final (service, repository, settings) = await boundService();
      final first = _pull(1, 'one', 'bob');
      final second = _pull(2, 'two', 'bob');
      repository.pages
        ..[1] = HostingResources(changeRequests: [first])
        ..[2] = HostingResources(changeRequests: [second, first]);
      final session = service.openRepositorySession();
      await session.update(repositoryIdentity, remotes);
      await settle();
      expect(session.resources.changeRequests.map((pull) => pull.number), [1]);

      await session.refresh(manual: true, page: 2);
      expect(session.resources.changeRequests.map((pull) => pull.number), [1]);
      await settle();
      expect(session.resources.changeRequests.map((pull) => pull.number), [
        1,
        2,
      ]);

      session.dispose();
      await service.dispose();
      await settings.dispose();
    });
  });
}

HostingChangeRequest _pull(
  int number,
  String branch,
  String author, {
  HostingChangeRequestState state = HostingChangeRequestState.open,
  String? head,
  HostingCheckState checks = HostingCheckState.unknown,
  HostingMergeability mergeability = HostingMergeability.unknown,
}) => HostingChangeRequest(
  stableId: 'https://github.com/team/project/pull/$number',
  number: number,
  title: 'Pull $number',
  author: author,
  state: state,
  draft: false,
  sourceRepository: 'team/project',
  sourceBranch: branch,
  targetRepository: 'team/project',
  targetBranch: 'main',
  headSha: head ?? 'abc$number',
  webUrl: 'https://github.com/team/project/pull/$number',
  reviewSummary: HostingReviewSummary.unknown,
  mergeability: mergeability,
  checks: HostingCheckSummary(state: checks),
);

HostingConnection _connection(String id) => HostingConnection(
  id: id,
  preset: HostingPreset.gitHub,
  login: id.split(':').last,
  webBaseUrl: 'https://github.com',
  apiBaseUrl: 'https://api.github.com',
  oauthClientId: 'public-client',
  enabled: true,
  refreshEnabled: true,
  capabilities: const [
    HostingCapability.changeRequests,
    HostingCapability.checkRuns,
    HostingCapability.issues,
  ],
  credentialIdentity: 'credential:$id',
  allowSplitOrigin: true,
);

HostingBindingOverride _binding(String connectionId, int repository) =>
    HostingBindingOverride(
      repository: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: [repository],
      ),
      remote: 'origin'.codeUnits,
      connectionId: connectionId,
      providerRepository: 'team/project',
    );

final class _MemoryLinkCache implements PrivateEntryStore {
  final Map<NativePathIdentity, Uint8List> entries = {};

  @override
  Future<Uint8List?> read(NativePathIdentity repository) async =>
      entries[repository];

  @override
  Future<void> write(NativePathIdentity repository, Uint8List bytes) async {
    entries[repository] = bytes;
  }

  @override
  Future<void> remove(NativePathIdentity repository) async {
    entries.remove(repository);
  }
}

final class _HostingRepository implements HostingRepository {
  final List<(HostingPreset, String?)> presetDefaultRequests = [];

  @override
  Future<HostingPresetDefaults?> presetDefaults(
    HostingPreset preset, {
    String? webBase,
  }) async {
    presetDefaultRequests.add((preset, webBase));
    return fakeHostingPresetDefaults(preset, webBase: webBase);
  }

  @override
  Future<bool> githubCliAvailable() async => true;

  @override
  Future<bool> gitlabCliAvailable() async => true;

  @override
  Future<void> openBrowser(Uri url) async {}

  final Set<String> invalidIds = {};
  final Map<String, HostingCredentialState> credentialStates = {};
  final List<String> removedIds = [];
  final Map<int, HostingOAuthSnapshot> oauthSnapshots = {};
  final List<int> canceledIds = [];
  final List<int> canceledResourceIds = [];
  final List<(String, String)> deactivatedResources = [];
  final Map<int, HostingResourceSnapshot> resourceSnapshots = {};
  var binding = const HostingBindingResolution(
    state: HostingBindingState.unmatched,
  );

  /// Rows each page finishes with; a started page first shows page 1, as the
  /// native cache does.
  final Map<int, HostingResources> pages = {};
  final List<(String, String?)> lookups = [];
  final List<List<String>> headLookups = [];
  final Map<String, HostingCheckState> headChecks = {};
  bool failHeads = false;
  final Map<String, List<HostingChangeRequest>> branchPulls = {};
  List<HostingChangeRequest> authoredPulls = const [];
  final Set<String> failingBranches = {};
  final Map<int, HostingPullRequestLookupSnapshot> lookupSnapshots = {};
  var nextRequestId = 1;
  var shutdowns = 0;

  @override
  Future<HostingConnection> validateConnection(
    HostingConnection connection,
  ) async {
    if (invalidIds.contains(connection.id)) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    return connection;
  }

  @override
  Future<HostingCredentialState> credentialState(
    HostingConnection connection,
  ) async =>
      credentialStates[connection.id] ?? HostingCredentialState.available;

  @override
  Future<HostingCredentialState> removeCredential(
    HostingConnection connection,
  ) async {
    removedIds.add(connection.id);
    return HostingCredentialState.missing;
  }

  @override
  Future<HostingBindingResolution> resolveBinding({
    required List<HostingConnection> connections,
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  }) async => binding;

  @override
  Future<Uri> resourceLink({
    required HostingConnection connection,
    required String providerRepository,
    required HostingResourceKind kind,
    int? number,
  }) async => Uri.https('example.test', '/team/project');

  @override
  Future<HostingOAuthSnapshot> startAuthorization(
    HostingConnection connection,
  ) async {
    final snapshot = HostingOAuthSnapshot(
      requestId: nextRequestId++,
      state: HostingOAuthState.queued,
    );
    oauthSnapshots[snapshot.requestId] = snapshot;
    return snapshot;
  }

  @override
  Future<HostingOAuthSnapshot?> pollAuthorization(int requestId) async =>
      oauthSnapshots[requestId];

  @override
  Future<bool> cancelAuthorization(int requestId) async {
    canceledIds.add(requestId);
    return true;
  }

  @override
  Future<void> shutdownRuntime() async {
    shutdowns += 1;
  }

  @override
  Future<HostingResourceSnapshot> startResourceRefresh({
    required HostingConnection connection,
    required String providerRepository,
    required int page,
    required bool manual,
  }) async {
    final snapshot = HostingResourceSnapshot(
      requestId: nextRequestId++,
      state: HostingResourceLoadState.loading,
      page: page,
      resources: pages[1] ?? const HostingResources(),
      stale: false,
      hasMore: false,
    );
    resourceSnapshots[snapshot.requestId] = HostingResourceSnapshot(
      requestId: snapshot.requestId,
      state: HostingResourceLoadState.ready,
      page: page,
      resources: pages[page] ?? const HostingResources(),
      stale: false,
      hasMore: true,
    );
    return snapshot;
  }

  @override
  Future<HostingPullRequestLookupSnapshot> startPullRequestLookup({
    required HostingConnection connection,
    required String providerRepository,
    List<String> heads = const [],
    required List<String> branches,
    String? authoredBy,
  }) async {
    if (heads.isNotEmpty) headLookups.add(heads);
    if (branches.isNotEmpty || authoredBy != null) {
      lookups.add((branches.join(','), authoredBy));
    }
    final requestId = nextRequestId++;
    final resolved = branches.takeWhile(
      (branch) => !failingBranches.contains(branch),
    );
    lookupSnapshots[requestId] = HostingPullRequestLookupSnapshot(
      requestId: requestId,
      state: resolved.length == branches.length && !failHeads
          ? HostingResourceLoadState.ready
          : HostingResourceLoadState.failed,
      heads: {
        if (!failHeads)
          for (final head in heads)
            head: headChecks[head] ?? HostingCheckState.unknown,
      },
      branches: {
        for (final branch in resolved) branch: branchPulls[branch] ?? const [],
      },
      authored: authoredBy == null ? null : authoredPulls,
      failure: resolved.length == branches.length && !failHeads
          ? null
          : HostingResourceFailure.rateLimited,
    );
    return HostingPullRequestLookupSnapshot(
      requestId: requestId,
      state: HostingResourceLoadState.loading,
    );
  }

  @override
  Future<HostingPullRequestLookupSnapshot?> pollPullRequestLookup(
    int requestId,
  ) async => lookupSnapshots.remove(requestId);

  @override
  Future<bool> cancelPullRequestLookup(int requestId) async => true;

  @override
  Future<HostingResourceSnapshot?> pollResourceRefresh(int requestId) async =>
      resourceSnapshots[requestId];

  @override
  Future<bool> cancelResourceRefresh(int requestId) async {
    canceledResourceIds.add(requestId);
    return true;
  }

  @override
  Future<void> deactivateResources({
    required String connectionId,
    required String providerRepository,
  }) async {
    deactivatedResources.add((connectionId, providerRepository));
  }

  @override
  Future<HostingReferenceProjection?> projectReference({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int revision,
    required List<HostingRemoteReference> references,
    required bool stale,
  }) async => null;

  @override
  Future<HostingReferenceApplyResult> applyReference({
    required String text,
    required int currentRevision,
    required HostingReferenceProjection projection,
    required String insertion,
  }) async => HostingReferenceApplyResult(text: text, caret: 0);
}
