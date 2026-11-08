import 'package:devmil_logging/devmil_logging.dart';
import 'package:gitlama/logging/logging_utils.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/repositories/impl/repository_view_cache_codec.dart';
import 'package:gitlama/repositories/impl/private_entry_store.dart';
import 'package:gitlama/repositories/impl/coded_cache_repositories.dart';
import 'package:gitlama/models/advanced_rebase.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/commit.dart';
import 'package:gitlama/models/conflict.dart';
import 'package:gitlama/models/discard.dart';
import 'package:gitlama/models/clone_attempt.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/history_mutation.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/patch.dart';
import 'package:gitlama/models/power_tools.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/repository_appearance.dart';
import 'package:gitlama/models/repository_lock.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/status_acceleration.dart';
import 'package:gitlama/models/repository_view_cache.dart';
import 'package:gitlama/models/ref_mutation.dart';
import 'package:gitlama/models/repository_extensions.dart';
import 'package:gitlama/models/rebase.dart';
import 'package:gitlama/models/named_snapshot.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/stash.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/repositories/clone_repository.dart';
import 'package:gitlama/repositories/directory_picker_repository.dart';
import 'package:gitlama/services/clone_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/repository_view_cache_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_settings_repository.dart';

void main() {
  test(
    'a finished operation leaves the rescan to its mutation lease',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      await service.open('/repository');
      // A second refresh would block reads for another pass over the worktree.
      repository.failRefresh = true;
      final result = await service.executeStaging(
        StagingRequest(
          requestId: BigInt.one,
          side: StagingSide.unstaged,
          scope: StagingScope.all,
        ),
      );
      expect(result.state, StagingExecutionState.completed);
      expect(repository.stagingCalls, 1);
      expect(repository.refreshCount, 0);
      // An explicit refresh still reaches the repository.
      await expectLater(
        service.refresh(),
        throwsA(isA<RepositorySessionException>()),
      );
      expect(repository.refreshCount, 1);
      await service.dispose();
    },
  );

  test(
    'fresh metadata retry delegates conflict refusal to the native boundary',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      await service.open('/repository');
      repository.stagingOutcomes.addAll([
        StagingExecutionState.stale,
        StagingExecutionState.failed,
      ]);
      final result = await service.executeStaging(
        StagingRequest(
          requestId: BigInt.one,
          side: StagingSide.unstaged,
          scope: StagingScope.all,
        ),
      );
      expect(result.state, StagingExecutionState.failed);
      expect(repository.stagingCalls, 2);
      expect(repository.stagingRequest?.requestId, BigInt.zero);
      expect(repository.workingDiffIdentity, isNull);
      await service.dispose();
    },
  );

  for (final scope in StagingScope.values) {
    test(
      'stale staging retries once only for whole-file scope $scope',
      () async {
        final repository = _ControlledRepository();
        final service = RepositorySessionService(repository);
        await service.open('/repository');
        repository.stagingOutcomes.addAll([
          StagingExecutionState.stale,
          StagingExecutionState.completed,
        ]);
        final result = await service.executeStaging(
          StagingRequest(
            requestId: BigInt.from(77),
            side: StagingSide.unstaged,
            scope: scope,
            paths: scope == StagingScope.files
                ? [
                    [97],
                  ]
                : [],
            rowIds: scope == StagingScope.rows ? ['row'] : [],
          ),
        );
        expect(
          result.state,
          scope == StagingScope.rows
              ? StagingExecutionState.stale
              : StagingExecutionState.completed,
        );
        expect(repository.stagingCalls, scope == StagingScope.rows ? 1 : 2);
        if (scope != StagingScope.rows) {
          expect(repository.stagingRequest!.requestId, BigInt.zero);
        }
        await service.dispose();
      },
    );
  }

  test(
    'repeated drift stops after one retry and failed operations are never retried',
    () async {
      for (final state in [
        StagingExecutionState.stale,
        StagingExecutionState.failed,
      ]) {
        final repository = _ControlledRepository();
        final service = RepositorySessionService(repository);
        await service.open('/repository');
        repository.stagingOutcomes.addAll([state, state]);
        final result = await service.executeStaging(
          StagingRequest(
            requestId: BigInt.one,
            side: StagingSide.unstaged,
            scope: StagingScope.all,
          ),
        );
        expect(result.state, state);
        expect(
          repository.stagingCalls,
          state == StagingExecutionState.stale ? 2 : 1,
        );
        await service.dispose();
      }
    },
  );

  test('chooser replaces its tab and reuses an already open recent', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    await service.open('/first');
    final id = service.addRepositoryChooser();
    expect(service.current, isNull);
    expect(service.workspace.tabs.last.canonicalIdentity, isNull);
    final recent = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/second'.codeUnits,
    );
    final opened = await service.openFromChooser(id, recent: recent);
    expect(service.workspace.tabs, hasLength(2));
    expect(service.workspace.activeTabId, id);
    expect(service.workspace.activeTab!.session, opened);
    final duplicate = service.addRepositoryChooser();
    await service.openFromChooser(duplicate, recent: recent);
    expect(service.workspace.tabs, hasLength(2));
    expect(service.workspace.activeTabId, id);
    await service.dispose();
  });

  test(
    'chooser cancellation and closure during picking create no session',
    () async {
      final picker = _ChooserPicker();
      final service = RepositorySessionService(
        _ControlledRepository(),
        null,
        picker,
      );
      final id = service.addRepositoryChooser();
      final canceled = service.openFromChooser(id);
      picker.result.complete(null);
      expect(await canceled, isNull);
      expect(service.workspace.activeTab!.phase, RepositoryTabPhase.choosing);
      picker.result = Completer<String?>();
      final closed = service.openFromChooser(id);
      await service.closeTab(id);
      picker.result.complete('/late');
      expect(await closed, isNull);
      expect(service.workspace.tabs, isEmpty);
      await service.dispose();
    },
  );

  test('failed chooser open stays retryable in the same tab', () async {
    final repository = _ControlledRepository()..failNextOpen = true;
    final service = RepositorySessionService(repository);
    final id = service.addRepositoryChooser();
    final recent = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/retry'.codeUnits,
    );
    await expectLater(
      service.openFromChooser(id, recent: recent),
      throwsA(isA<RepositorySessionException>()),
    );
    expect(service.workspace.activeTab!.phase, RepositoryTabPhase.choosing);
    expect(service.workspace.activeTab!.failure, isNotNull);
    expect(service.workspace.activeTab!.canonicalIdentity, isNull);
    await service.openFromChooser(id, recent: recent);
    expect(service.workspace.tabs.single.id, id);
    expect(service.workspace.activeTab!.phase, RepositoryTabPhase.open);
    await service.dispose();
  });

  test('closing chooser during native open disposes late session', () async {
    final repository = _ControlledRepository(delayOpen: true);
    final service = RepositorySessionService(repository);
    final id = service.addRepositoryChooser();
    final pending = service.openFromChooser(
      id,
      recent: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/late'.codeUnits,
      ),
    );
    final failure = expectLater(
      pending,
      throwsA(isA<RepositorySessionException>()),
    );
    final generation = service.workspace.activeTab!.generation;
    await service.closeTab(id);
    repository.completeOpen(generation);
    await failure;
    expect(repository.closedGenerations, contains(generation));
    expect(service.workspace.tabs, isEmpty);
    await service.dispose();
  });

  test(
    'concurrent opens retain both tabs without stealing activation',
    () async {
      final repository = _ControlledRepository(delayOpen: true);
      final service = RepositorySessionService(repository);
      final published = <int>[];
      final subscription = service.states.listen(
        (state) => published.add(state.identity.generation),
      );

      final first = service.open('first');
      final second = service.open('second');
      repository.completeOpen(2);
      final current = await second;
      repository.completeOpen(1);
      final firstOpened = await first;

      expect(current.identity.generation, 2);
      expect(firstOpened.identity.generation, 1);
      expect(published, [2]);
      expect(service.workspace.tabs, hasLength(2));
      expect(service.workspace.activeTab?.session?.identity.generation, 2);
      expect(repository.closedGenerations, isEmpty);

      await service.dispose();
      await subscription.cancel();
    },
  );

  test(
    'tab activation, reorder, and close preserve repository identity',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('first');
      final second = await service.open('second');
      final firstTab = service.workspace.tabs.first;
      final secondTab = service.workspace.tabs.last;

      service.activateTab(firstTab.id);
      service.reorderTab(firstTab.id, 1);

      expect(service.current?.identity.generation, first.identity.generation);
      expect(service.workspace.tabs.map((tab) => tab.id), [
        secondTab.id,
        firstTab.id,
      ]);
      await service.closeTab(firstTab.id);
      expect(service.current?.identity.generation, second.identity.generation);
      expect(repository.closedGenerations, [first.identity.generation]);

      await service.dispose();
    },
  );

  group('worktree tabs', () {
    List<String> order(RepositorySessionService service) => [
      for (final tab in service.workspace.tabs) tab.label,
    ];
    int idOf(RepositorySessionService service, String label) =>
        service.workspace.tabs.firstWhere((tab) => tab.label == label).id;
    NativePathIdentity pathOf(String value) => NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: value.codeUnits,
    );

    test('stand together in one entry and share a group', () async {
      final service = RepositorySessionService(
        _ControlledRepository(canonicalIdentity: true),
      );
      for (final name in ['/a', '/b', '/a@feature', '/c']) {
        await service.open(name);
      }

      // A worktree opened later joins the open worktrees of its repository.
      expect(order(service), ['a', 'a@feature', 'b', 'c']);
      expect(service.workspace.tabEntries.map((entry) => entry.length), [
        2,
        1,
        1,
      ]);
      service.activateTab(idOf(service, 'a@feature'));
      expect(service.workspace.activeWorktrees.map((tab) => tab.label), [
        'a',
        'a@feature',
      ]);
      expect(
        service.workspace.tabs
            .firstWhere((tab) => tab.label == 'a@feature')
            .isMainWorktree,
        isFalse,
      );

      // Another repository's tab shows no worktree row.
      service.activateTab(idOf(service, 'c'));
      expect(service.workspace.activeWorktrees, isEmpty);

      // Joining a group takes the repository's other worktrees along.
      final group = service.createTabGroup(idOf(service, 'c'))!;
      service.addTabToGroup(idOf(service, 'a@feature'), group);
      expect(order(service), ['b', 'c', 'a', 'a@feature']);
      expect(service.workspace.tabs.map((tab) => tab.groupId), [
        null,
        group,
        group,
        group,
      ]);
      service.removeTabFromGroup(idOf(service, 'a'));
      expect(order(service), ['b', 'c', 'a', 'a@feature']);
      expect(service.workspace.tabs.map((tab) => tab.groupId), [
        null,
        group,
        null,
        null,
      ]);

      // Moving the entry's lead tab moves the whole entry.
      service.moveTab(idOf(service, 'a'), 0);
      expect(order(service), ['a', 'a@feature', 'b', 'c']);

      await service.dispose();
    });

    test('reorder in their row and close together', () async {
      final repository = _ControlledRepository(canonicalIdentity: true);
      final service = RepositorySessionService(repository);
      for (final name in ['/a', '/a@one', '/a@two', '/b']) {
        await service.open(name);
      }

      service.moveWorktreeTab(idOf(service, 'a@two'), 0);
      expect(order(service), ['a@two', 'a', 'a@one', 'b']);
      service.moveWorktreeTab(idOf(service, 'a@two'), 2);
      expect(order(service), ['a', 'a@one', 'a@two', 'b']);

      // Opening an open worktree again shows its tab.
      service.activateTab(idOf(service, 'b'));
      await service.openRecent(pathOf('/a@one'));
      expect(service.workspace.tabs, hasLength(4));
      expect(service.workspace.activeTab?.label, 'a@one');

      // A deleted worktree's tab leaves the row; the last one folds it.
      await service.closeTab(idOf(service, 'a@two'));
      expect(service.workspace.activeWorktrees, hasLength(2));
      await service.closeTab(idOf(service, 'a@one'));
      expect(service.workspace.activeWorktrees, isEmpty);

      await service.open('/a@one');
      await service.closeTabs([
        for (final tab in service.workspace.activeWorktrees) tab.id,
      ]);
      expect(order(service), ['b']);

      await service.dispose();
    });
  });

  group('tab groups', () {
    List<String> order(RepositorySessionService service) => [
      for (final tab in service.workspace.tabs) tab.label,
    ];
    int? groupOf(RepositorySessionService service, String label) =>
        service.workspace.tabs.firstWhere((tab) => tab.label == label).groupId;
    int idOf(RepositorySessionService service, String label) =>
        service.workspace.tabs.firstWhere((tab) => tab.label == label).id;

    test('keep their tabs together as tabs join, move and close', () async {
      final service = RepositorySessionService(
        _ControlledRepository(canonicalIdentity: true),
      );
      for (final name in ['/a', '/b', '/c', '/d']) {
        await service.open(name);
      }

      final group = service.createTabGroup(idOf(service, 'a'))!;
      expect(service.workspace.groups.single.id, group);
      expect(
        service.workspace.groups.single.color,
        PaletteColor(RepositoryAppearanceColor.values.first),
      );

      service.addTabToGroup(idOf(service, 'c'), group);
      expect(order(service), ['a', 'c', 'b', 'd']);

      // Dropped between two tabs of the group, a tab joins it.
      service.reorderTab(idOf(service, 'd'), 1);
      expect(order(service), ['a', 'd', 'c', 'b']);
      expect(groupOf(service, 'd'), group);

      // Dropped away from its group, a tab leaves it.
      service.reorderTab(idOf(service, 'a'), 3);
      expect(order(service), ['d', 'c', 'b', 'a']);
      expect(groupOf(service, 'a'), isNull);

      // A tab taken out of a group stands right after it.
      service.removeTabFromGroup(idOf(service, 'd'));
      expect(order(service), ['c', 'd', 'b', 'a']);
      expect(groupOf(service, 'd'), isNull);

      // A second group takes the next colour; leaving the middle of a group
      // puts the tab after it.
      service.addTabToGroup(idOf(service, 'b'), group);
      expect(order(service), ['c', 'b', 'd', 'a']);
      service.addTabToGroup(idOf(service, 'd'), group);
      expect(order(service), ['c', 'b', 'd', 'a']);
      final second = service.createTabGroup(idOf(service, 'b'))!;
      expect(order(service), ['c', 'd', 'b', 'a']);
      expect(
        service.workspace.group(second)?.color,
        PaletteColor(RepositoryAppearanceColor.values[1]),
      );

      // A group without tabs is gone.
      await service.closeTab(idOf(service, 'b'));
      expect(service.workspace.group(second), isNull);
      service.ungroupTabs(group);
      expect(service.workspace.groups, isEmpty);
      expect(
        service.workspace.tabs.every((tab) => tab.groupId == null),
        isTrue,
      );
      expect(order(service), ['c', 'd', 'a']);

      await service.dispose();
    });

    test('dragged tabs join and leave groups where they are dropped', () async {
      final service = RepositorySessionService(
        _ControlledRepository(canonicalIdentity: true),
      );
      for (final name in ['/a', '/b', '/c', '/d']) {
        await service.open(name);
      }
      final group = service.createTabGroup(idOf(service, 'b'))!;
      service.addTabToGroup(idOf(service, 'c'), group);
      expect(order(service), ['a', 'b', 'c', 'd']);

      // Dropped at the group's front, a tab joins it.
      service.moveTab(idOf(service, 'd'), 1, groupId: group);
      expect(order(service), ['a', 'd', 'b', 'c']);
      expect(groupOf(service, 'd'), group);

      // Dropped just before the group, a member leaves it.
      service.moveTab(idOf(service, 'c'), 1);
      expect(order(service), ['a', 'c', 'd', 'b']);
      expect(groupOf(service, 'c'), isNull);

      // An ungrouped tab dropped inside a group stands after it instead.
      service.moveTab(idOf(service, 'a'), 2);
      expect(order(service), ['c', 'd', 'b', 'a']);
      expect(groupOf(service, 'a'), isNull);

      // The last tab out takes the group with it.
      service.moveTab(idOf(service, 'd'), 0);
      service.moveTab(idOf(service, 'b'), 0);
      expect(order(service), ['b', 'd', 'c', 'a']);
      expect(service.workspace.groups, isEmpty);

      await service.dispose();
    });

    test(
      'a dragged group moves its tabs together, around other groups',
      () async {
        final service = RepositorySessionService(
          _ControlledRepository(canonicalIdentity: true),
        );
        for (final name in ['/a', '/b', '/c', '/d', '/e']) {
          await service.open(name);
        }
        final first = service.createTabGroup(idOf(service, 'a'))!;
        service.addTabToGroup(idOf(service, 'b'), first);
        final second = service.createTabGroup(idOf(service, 'c'))!;
        service.addTabToGroup(idOf(service, 'd'), second);
        expect(order(service), ['a', 'b', 'c', 'd', 'e']);

        service.moveTabGroup(first, 3);
        expect(order(service), ['c', 'd', 'e', 'a', 'b']);
        expect(groupOf(service, 'a'), first);

        // A place inside another group moves the group after that one.
        service.moveTabGroup(first, 1);
        expect(order(service), ['c', 'd', 'a', 'b', 'e']);

        service.moveTabGroup(first, 0);
        expect(order(service), ['a', 'b', 'c', 'd', 'e']);
        expect(groupOf(service, 'c'), second);

        await service.dispose();
      },
    );

    test(
      'collapse only with another tab to show, and open when activated',
      () async {
        final service = RepositorySessionService(
          _ControlledRepository(canonicalIdentity: true),
        );
        await service.open('/a');
        await service.open('/b');
        final group = service.createTabGroup(idOf(service, 'a'))!;
        service.activateTab(idOf(service, 'a'));

        service.setTabGroupCollapsed(group, true);
        expect(service.workspace.group(group)?.collapsed, isTrue);
        expect(service.workspace.activeTab?.label, 'b');

        service.activateTab(idOf(service, 'a'));
        expect(service.workspace.group(group)?.collapsed, isFalse);

        // With every tab in the group, collapsing would hide the active tab.
        service.addTabToGroup(idOf(service, 'b'), group);
        service.setTabGroupCollapsed(group, true);
        expect(service.workspace.group(group)?.collapsed, isFalse);

        service.renameTabGroup(group, '  Client\twork  ');
        expect(service.workspace.group(group)?.name, 'Client work');
        service.editTabGroup(
          group,
          name: ' Client\nteam ',
          color: const PaletteColor(RepositoryAppearanceColor.rose),
          icon: 'server',
        );
        expect(
          service.workspace.group(group),
          RepositoryTabGroup(
            id: group,
            name: 'Client team',
            color: const PaletteColor(RepositoryAppearanceColor.rose),
            icon: 'server',
          ),
        );

        await service.closeTabGroup(group);
        expect(service.workspace.tabs, isEmpty);
        expect(service.workspace.groups, isEmpty);
        await service.dispose();
      },
    );

    test(
      'are saved with their repositories and restored with the tabs',
      () async {
        NativePathIdentity path(String value) => NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: value.codeUnits,
        );
        final first = path('/work/first');
        final second = path('/work/second');
        final third = path('/work/third');
        final settings = SettingsService(
          FakeSettingsRepository(
            loaded: LoadedSettings(
              state: SettingsLoadState.loaded,
              document: SettingsDocument(
                openWorktrees: [first, second, third],
                activeWorktree: first,
                tabGroups: [
                  TabGroupSettings(
                    name: 'Client',
                    color: 'violet',
                    icon: 'server',
                    collapsed: true,
                    members: [second, third],
                  ),
                ],
              ),
            ),
          ),
        );
        await settings.initialize();
        final service = RepositorySessionService(
          _ControlledRepository(),
          settings,
        );

        await service.restoreWorkspace();

        final group = service.workspace.groups.single;
        expect(group.name, 'Client');
        expect(
          group.color,
          const PaletteColor(RepositoryAppearanceColor.violet),
        );
        expect(group.icon, 'server');
        expect(group.collapsed, isTrue);
        expect(
          [for (final tab in service.workspace.tabs) tab.groupId],
          [null, group.id, group.id],
        );

        // A custom colour is saved by its value.
        service.editTabGroup(
          group.id,
          name: 'Clients',
          color: const CustomColor(0xC2410C),
          icon: 'users',
        );
        service.removeTabFromGroup(service.workspace.tabs[2].id);
        expect(settings.current.tabGroups, [
          TabGroupSettings(
            name: 'Clients',
            color: 'rgb-c2410c',
            icon: 'users',
            collapsed: true,
            members: [second],
          ),
        ]);
        // Only catalogue icons are kept; anything else clears the icon.
        service.editTabGroup(
          group.id,
          name: 'Clients',
          color: const CustomColor(0xC2410C),
          icon: 'not-an-icon',
        );
        expect(settings.current.tabGroups.single.icon, isNull);
        await service.dispose();
        await settings.dispose();
      },
    );
  });

  test('opening an existing canonical repository activates its tab', () async {
    final repository = _ControlledRepository(canonicalIdentity: true);
    final service = RepositorySessionService(repository);
    final first = await service.open('/same');
    await service.open('/other');
    final reopened = await service.open('/same');

    expect(service.workspace.tabs, hasLength(2));
    expect(service.workspace.activeTab?.label, 'same');
    expect(reopened.identity, first.identity);
    expect(repository.closedGenerations, [3]);

    await service.dispose();
  });

  test(
    'saved tabs and active identity restore without dropping peers',
    () async {
      final firstIdentity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/work/first'.codeUnits,
      );
      final secondIdentity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/work/second'.codeUnits,
      );
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(
              worktrees: [
                WorktreeSettings(
                  identity: firstIdentity,
                  pane: 'history',
                  route: 'commit',
                  anchor: 'abc123',
                  historyScrollOffset: 240,
                ),
                WorktreeSettings(identity: secondIdentity),
              ],
              openWorktrees: [firstIdentity, secondIdentity],
              activeWorktree: firstIdentity,
            ),
          ),
        ),
      );
      await settings.initialize();
      final repository = _ControlledRepository();
      repository.historyRows = const [
        HistoryTopologyRow(
          objectId: 'abc123',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ];
      final service = RepositorySessionService(repository, settings);

      await service.restoreWorkspace();
      for (var attempt = 0; attempt < 10; attempt += 1) {
        if (service.inspector.current.diff != null) break;
        await Future<void>.delayed(Duration.zero);
      }

      expect(service.workspace.tabs, hasLength(2));
      expect(service.workspace.activeTab?.canonicalIdentity, firstIdentity);
      expect(
        service.workspace.activeTab?.navigation.pane,
        WorkspacePane.history,
      );
      expect(
        service.workspace.activeTab?.navigation.route,
        WorkspaceRoute.commit,
      );
      expect(
        service.workspace.activeTab?.navigation.selectedIdentity,
        'abc123',
      );
      expect(service.workspace.activeTab?.navigation.historyScrollOffset, 240);
      expect(repository.historyLoadCount, greaterThanOrEqualTo(1));
      expect(repository.selectedHistoryObjectId, 'abc123');
      expect(service.inspector.current.diff?.newObjectId, 'abc123');
      expect(settings.current.openWorktrees, [firstIdentity, secondIdentity]);
      await service.dispose();
      await settings.dispose();
    },
  );

  test(
    'a saved branch filter reaches native history first and persists changes',
    () async {
      final identity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/work/filtered'.codeUnits,
      );
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(
              worktrees: [
                WorktreeSettings(
                  identity: identity,
                  pane: 'history',
                  branchFilter: const ['refs/heads/topic'],
                ),
              ],
              openWorktrees: [identity],
              activeWorktree: identity,
            ),
          ),
        ),
      );
      await settings.initialize();
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository, settings);

      await service.restoreWorkspace();
      for (var attempt = 0; attempt < 10; attempt += 1) {
        if (repository.historyLoadCount > 0) break;
        await Future<void>.delayed(Duration.zero);
      }

      final tab = service.workspace.activeTab!;
      expect(tab.navigation.branchFilter.references, ['refs/heads/topic']);
      expect(repository.branchFilterRequests.first.references, [
        'refs/heads/topic',
      ]);

      await service.setBranchFilter(
        tab.id,
        HistoryBranchFilter(['refs/heads/topic', 'refs/heads/main']),
      );
      expect(settings.current.worktrees.single.branchFilter, [
        'refs/heads/main',
        'refs/heads/topic',
      ]);
      expect(repository.branchFilterRequests.last.references, [
        'refs/heads/main',
        'refs/heads/topic',
      ]);

      // A branch selected in the sidebar joins the shown filter only.
      await service.revealReference(tab.id, 'refs/heads/other');
      expect(repository.branchFilterRequests.last.references, [
        'refs/heads/main',
        'refs/heads/other',
        'refs/heads/topic',
      ]);
      expect(settings.current.worktrees.single.branchFilter, [
        'refs/heads/main',
        'refs/heads/topic',
      ]);
      expect(service.workspace.activeTab!.navigation.branchFilter.references, [
        'refs/heads/main',
        'refs/heads/topic',
      ]);
      var requests = repository.branchFilterRequests.length;
      await service.revealReference(tab.id, null);
      expect(repository.branchFilterRequests, hasLength(requests + 1));
      expect(repository.branchFilterRequests.last.references, [
        'refs/heads/main',
        'refs/heads/topic',
      ]);
      // A branch the filter already names changes nothing.
      requests = repository.branchFilterRequests.length;
      await service.revealReference(tab.id, 'refs/heads/topic');
      expect(repository.branchFilterRequests, hasLength(requests));

      await service.setBranchFilter(tab.id, HistoryBranchFilter.none);
      expect(settings.current.worktrees.single.branchFilter, isEmpty);
      // An unfiltered graph already shows every branch.
      requests = repository.branchFilterRequests.length;
      await service.revealReference(tab.id, 'refs/heads/other');
      expect(repository.branchFilterRequests, hasLength(requests));
      await service.dispose();
      await settings.dispose();
    },
  );

  group('automatic fetch', () {
    NativePathIdentity path(String value) => NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: value.codeUnits,
    );
    Future<RepositorySessionService> opened(
      _ControlledRepository repository,
      SettingsService settings, {
      bool remote = true,
    }) async {
      final service = RepositorySessionService(repository, settings);
      final session = await service.open('/work/big');
      repository.queuedEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            identity: session.snapshot.identity,
            refs: RepositoryRefs(
              remotes: [
                if (remote)
                  RepositoryRemote(
                    name: 'origin'.codeUnits,
                    displayUrl: const [],
                  ),
              ],
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return service;
    }

    test('fetches open repositories in the background by default', () async {
      final repository = _ControlledRepository(canonicalIdentity: true);
      final settings = fakeSettingsService();
      await settings.initialize();
      final service = await opened(repository, settings);

      await service.autoFetch();

      expect(repository.backgroundFetches, hasLength(1));
      await service.dispose();
      await settings.dispose();
    });

    test('a repository without a remote is left alone', () async {
      final repository = _ControlledRepository(canonicalIdentity: true);
      final settings = fakeSettingsService();
      await settings.initialize();
      final service = await opened(repository, settings, remote: false);

      await service.autoFetch();

      expect(repository.backgroundFetches, isEmpty);
      await service.dispose();
      await settings.dispose();
    });

    test('the repository override wins over the application setting', () async {
      final repository = _ControlledRepository(canonicalIdentity: true);
      final settings = fakeSettingsService();
      await settings.initialize();
      final service = await opened(repository, settings);
      final canonical = service.workspace.activeTab!.canonicalIdentity!;
      expect(canonical, path('/work/big'));

      settings.updateView(
        settings.current.copyWith(
          autoFetch: const AutoFetchSettings(enabled: false),
        ),
      );
      await service.autoFetch();
      expect(repository.backgroundFetches, isEmpty);

      settings.updateView(
        settings.current.withAutoFetchOverride(canonical, true),
      );
      await service.autoFetch();
      expect(repository.backgroundFetches, hasLength(1));

      settings.updateView(
        settings.current
            .copyWith(autoFetch: const AutoFetchSettings())
            .withAutoFetchOverride(canonical, false),
      );
      await service.autoFetch();
      expect(repository.backgroundFetches, hasLength(1));

      // Following the application again removes the entry.
      settings.updateView(
        settings.current.withAutoFetchOverride(canonical, null),
      );
      expect(settings.current.repositoryOptions, isEmpty);
      await service.autoFetch();
      expect(repository.backgroundFetches, hasLength(2));
      await service.dispose();
      await settings.dispose();
    });

    test('a failed fetch does not stop the next run', () async {
      final repository = _ControlledRepository(canonicalIdentity: true)
        ..transferResult = TransferExecutionResult(
          state: TransferExecutionState.failed,
          failure: TransferFailureCode.authentication,
          ahead: BigInt.zero,
          behind: BigInt.zero,
        );
      final settings = fakeSettingsService();
      await settings.initialize();
      final service = await opened(repository, settings);

      await service.autoFetch();
      await service.autoFetch();

      expect(repository.backgroundFetches, hasLength(2));
      await service.dispose();
      await settings.dispose();
    });
  });

  group('known repository view', () {
    final big = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/work/big'.codeUnits,
    );
    RepositoryReference branch(String name, {bool head = false}) =>
        RepositoryReference(name: name.codeUnits, target: 'a' * 40, head: head);
    // One local change keeps these repositories on the Changes pane.
    RepositoryStatus status(String head, {bool clean = false}) =>
        RepositoryStatus(
          workingTree: clean ? WorkingTreeState.clean : WorkingTreeState.dirty,
          headObjectId: head,
          ahead: BigInt.zero,
          behind: BigInt.zero,
          entries: [
            if (!clean)
              RepositoryStatusEntry(
                kind: StatusEntryKind.ordinary,
                path: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: 'tracked.txt'.codeUnits,
                ),
                index: ChangeKind.unmodified,
                worktree: ChangeKind.modified,
              ),
          ],
          totalEntries: clean ? BigInt.zero : BigInt.one,
          entriesTruncated: false,
          operations: const [],
        );
    RepositoryViewCacheEntry knownView() => RepositoryViewCacheEntry(
      refs: RepositoryRefs(branches: [branch('main', head: true)]),
      refCounts: const RepositoryRefCounts(branches: 1),
      status: status('abc'),
      history: cacheableHistoryPage(
        HistoryPage(
          requestId: BigInt.from(7),
          complete: true,
          totalRows: 1,
          offset: 0,
          rows: [
            HistoryTopologyRow(
              objectId: 'abc',
              parents: const [],
              refs: const [],
              lane: 0,
              shape: 0,
              subject: 'Known subject'.codeUnits,
              author: 'Ada'.codeUnits,
              selected: true,
              lit: true,
            ),
          ],
          laneCount: 1,
          payloadBytes: 10,
          selectedObjectIds: const ['abc'],
          lightingActive: true,
        ),
      ),
    );
    Future<RepositoryViewCacheService> cacheWith(
      _MemoryViewCacheRepository storage,
    ) async {
      final cache = RepositoryViewCacheService(
        CodedRepositoryViewCacheRepository(
          storage,
          runInBackground: <T>(work) async => work(),
        ),
        persistDelay: const Duration(milliseconds: 1),
      );
      await cache.warm([big]);
      return cache;
    }

    test('a repository last seen without changes opens on History', () async {
      final storage = _MemoryViewCacheRepository()
        ..entries[big] = encodeRepositoryView(
          RepositoryViewCacheEntry(
            refs: knownView().refs,
            refCounts: knownView().refCounts,
            status: status('abc', clean: true),
            history: knownView().history,
          ),
        );
      final service = RepositorySessionService(
        _ControlledRepository(canonicalIdentity: true),
        null,
        null,
        null,
        await cacheWith(storage),
      );

      await service.open('/work/big');

      expect(
        service.workspace.activeTab!.navigation.pane,
        WorkspacePane.history,
      );
      await service.dispose();
    });

    test('stands in until the repository has loaded', () async {
      final storage = _MemoryViewCacheRepository()
        ..entries[big] = encodeRepositoryView(knownView());
      final cache = await cacheWith(storage);
      final repository = _ControlledRepository(canonicalIdentity: true)
        ..historyBarrier = Completer<void>()
        ..historyRows = const [
          HistoryTopologyRow(
            objectId: 'def',
            parents: ['abc'],
            refs: [],
            lane: 0,
            shape: 0,
          ),
          HistoryTopologyRow(
            objectId: 'abc',
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ];
      final service = RepositorySessionService(
        repository,
        null,
        null,
        null,
        cache,
      );
      final opened = await service.open('/work/big');

      // The repository itself has reported nothing yet.
      expect(opened.snapshot.phase, RepositoryPhase.unloaded);
      expect(opened.snapshot.refs.branches.single.name, 'main'.codeUnits);
      expect(opened.snapshot.refCounts.branches, 1);
      expect(opened.snapshot.status?.headObjectId, 'abc');

      final phases = <HistoryLoadPhase>[];
      final subscription = service.history.states.listen(
        (state) => phases.add(state.phase),
      );
      final loading = service.history.load(opened.identity);
      final presented = service.history.current;
      expect(presented.phase, HistoryLoadPhase.preview);
      expect(presented.page?.requestId, cachedHistoryRequestId);
      expect(presented.page?.rows.single.subject, 'Known subject'.codeUnits);
      // Selection and lighting belong to the session that produced them.
      expect(presented.page?.rows.single.selected, isFalse);
      expect(presented.page?.selectedObjectIds, isEmpty);
      expect(presented.page?.lightingActive, isFalse);
      // No native request exists for the stand-in page.
      await service.history.ensureIndex(0);
      expect(repository.historyLoadCount, 1);

      repository.historyBarrier!.complete();
      final loaded = await loading;
      expect(loaded.phase, HistoryLoadPhase.complete);
      expect(loaded.page?.requestId, BigInt.one);
      expect(loaded.page?.rows.map((row) => row.objectId), ['def', 'abc']);
      // The row the cache described keeps its subject while it is read again.
      expect(loaded.page?.rows.last.subject, 'Known subject'.codeUnits);
      expect(phases, isNot(contains(HistoryLoadPhase.loading)));

      repository.queuedEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            identity: opened.snapshot.identity,
            status: status('def'),
            refCounts: const RepositoryRefCounts(branches: 2),
            refs: RepositoryRefs(
              branches: [branch('main', head: true), branch('topic')],
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(service.current?.snapshot.refs.branches, hasLength(2));
      expect(service.current?.snapshot.status?.headObjectId, 'def');
      expect(cache.entry(big)?.refs?.branches, hasLength(2));
      expect(cache.entry(big)?.history?.rows, hasLength(2));

      await subscription.cancel();
      await service.dispose();
      await cache.dispose();
      final stored = decodeRepositoryView(storage.entries[big]!);
      expect(stored?.refs?.branches, hasLength(2));
      expect(stored?.status?.headObjectId, 'def');
      expect(stored?.history?.rows.map((row) => row.objectId), ['def', 'abc']);
    });

    for (final (name, bytes) in [
      ('a damaged entry', Uint8List.fromList([0, 159, 146, 150, 1, 2])),
      (
        'an entry of another schema',
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': 'gitlama.repository-view',
              'schema': repositoryViewCacheSchema + 1,
              'refs': <String, Object?>{},
            }),
          ),
        ),
      ),
    ]) {
      test('$name falls back to loading', () async {
        final storage = _MemoryViewCacheRepository()..entries[big] = bytes;
        final cache = await cacheWith(storage);
        expect(cache.entry(big), isNull);
        expect(storage.removed, [big]);

        final repository = _ControlledRepository(canonicalIdentity: true)
          ..historyRows = const [
            HistoryTopologyRow(
              objectId: 'abc',
              parents: [],
              refs: [],
              lane: 0,
              shape: 0,
            ),
          ];
        final service = RepositorySessionService(
          repository,
          null,
          null,
          null,
          cache,
        );
        final opened = await service.open('/work/big');
        expect(opened.snapshot.refs.branches, isEmpty);
        expect(opened.snapshot.status, isNull);
        final phases = <HistoryLoadPhase>[];
        final subscription = service.history.states.listen(
          (state) => phases.add(state.phase),
        );
        final loaded = await service.history.load(opened.identity);
        expect(phases.first, HistoryLoadPhase.loading);
        expect(loaded.phase, HistoryLoadPhase.complete);
        expect(loaded.page?.rows.single.objectId, 'abc');
        await subscription.cancel();
        await service.dispose();
        await cache.dispose();
      });
    }

    test('storage that fails is the same as an empty cache', () async {
      final storage = _MemoryViewCacheRepository()..failing = true;
      final cache = await cacheWith(storage);
      expect(cache.entry(big), isNull);
      cache.rememberSnapshot(
        big,
        RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: status('abc'),
        ),
      );
      // The entry still serves tab changes within this session.
      expect(cache.entry(big)?.status?.headObjectId, 'abc');
      await cache.dispose();
    });
  });

  test('the history reference scope follows the setting', () async {
    final identity = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/work/first'.codeUnits,
    );
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(
            worktrees: [WorktreeSettings(identity: identity, pane: 'history')],
            openWorktrees: [identity],
            activeWorktree: identity,
          ),
        ),
      ),
    );
    await settings.initialize();
    final repository = _ControlledRepository(canonicalIdentity: true)
      ..historyRows = const [
        HistoryTopologyRow(
          objectId: 'abc',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ];
    final service = RepositorySessionService(repository, settings);
    await service.restoreWorkspace();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.historyOtherRefs, [false]);

    // Another appearance change keeps the shown history.
    settings.updateAppearance((value) => value.copyWith(dateFormat: 'iso'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.historyOtherRefs, [false]);

    settings.updateAppearance(
      (value) => value.copyWith(historyOtherRefs: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.historyOtherRefs, [false, true]);
    expect(service.history.current.phase, HistoryLoadPhase.complete);

    // A search of all branches finds the commits History shows.
    await service.powerTools.startDiffContentSearch(query: 'needle');
    expect(repository.diffSearchOtherRefs, isTrue);
    settings.updateAppearance(
      (value) => value.copyWith(historyOtherRefs: false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.historyOtherRefs, [false, true, false]);
    await service.powerTools.startDiffContentSearch(query: 'needle');
    expect(repository.diffSearchOtherRefs, isFalse);
    await service.dispose();
    await settings.dispose();
  });

  test('restore opens saved tabs side by side and loads one history', () async {
    final identities = [
      for (final name in ['first', 'second', 'third'])
        NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: '/work/$name'.codeUnits,
        ),
    ];
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(
            worktrees: [
              for (final identity in identities)
                WorktreeSettings(identity: identity, pane: 'history'),
            ],
            openWorktrees: identities,
            activeWorktree: identities[1],
          ),
        ),
      ),
    );
    await settings.initialize();
    final repository =
        _ControlledRepository(delayOpen: true, canonicalIdentity: true)
          ..historyRows = const [
            HistoryTopologyRow(
              objectId: 'abc',
              parents: [],
              refs: [],
              lane: 0,
              shape: 0,
            ),
          ];
    final service = RepositorySessionService(repository, settings);

    final restoring = service.restoreWorkspace();
    await Future<void>.delayed(Duration.zero);
    // Every repository is opening before the first one has answered.
    expect(repository.openCalls, 3);
    expect(
      service.workspace.tabs.map((tab) => tab.requestedIdentity),
      identities,
    );
    expect(service.workspace.activeTab?.requestedIdentity, identities[1]);

    // Answers arrive in any order; the tabs keep theirs.
    for (final generation in [3, 1, 2]) {
      repository.completeOpen(generation);
      await Future<void>.delayed(Duration.zero);
    }
    await restoring;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      service.workspace.tabs.map((tab) => tab.canonicalIdentity),
      identities,
    );
    expect(service.workspace.activeTab?.canonicalIdentity, identities[1]);
    // One preview and one completion, for the selected repository only.
    expect(repository.historyLoadCount, 2);
    expect(service.history.current.phase, HistoryLoadPhase.complete);
    await service.dispose();
    await settings.dispose();
  });

  test(
    'event drain rejects stale revisions and replaces on resynchronize',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final revisions = <BigInt>[];
      final subscription = service.states.listen(
        (state) => revisions.add(state.snapshot.revision),
      );
      final opened = await service.open('repository');
      repository.queuedEvents.addAll([
        _snapshotEvent(RepositorySessionEventKind.snapshot, 2),
        _snapshotEvent(RepositorySessionEventKind.snapshot, 1),
        _snapshotEvent(RepositorySessionEventKind.resynchronize, 3),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(opened.snapshot.revision, BigInt.zero);
      expect(revisions, [BigInt.zero, BigInt.from(2), BigInt.from(3)]);
      expect(service.current?.snapshot.revision, BigInt.from(3));
      expect(repository.maximumEventRequests, everyElement(64));

      await service.dispose();
      await subscription.cancel();
    },
  );

  test('first ready status reloads an already visible history', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final opened = await service.open('repository');
    final tab = service.workspace.activeTab!;
    service.updateNavigation(
      tab.id,
      tab.navigation.copyWith(pane: WorkspacePane.history),
    );
    await service.history.load(opened.identity);
    final initialLoads = repository.historyLoadCount;
    repository.historyRows = const [
      HistoryTopologyRow(
        objectId: historyWorktreeObjectId,
        parents: [],
        refs: [],
        lane: 0,
        shape: 0,
        wipChangedFiles: 1,
      ),
    ];

    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(repository.historyLoadCount, greaterThan(initialLoads));
    expect(
      service.history.current.page?.rows.single.objectId,
      historyWorktreeObjectId,
    );
    await service.dispose();
  });

  test('a repository that opens with local changes stays on Changes', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    await service.open('repository');
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            headObjectId: 'def',
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.untracked,
                path: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: 'new.txt'.codeUnits,
                ),
                index: ChangeKind.unmodified,
                worktree: ChangeKind.unmodified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final tab = service.workspace.activeTab!;
    expect(tab.navigation.pane, WorkspacePane.changes);

    // Committing everything later does not move the user to History.
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: RepositorySnapshot(
          revision: BigInt.two,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            headObjectId: 'abc',
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.workspace.activeTab!.navigation.pane, WorkspacePane.changes);
    await service.dispose();
  });

  test('History opens on HEAD and returns to its last selection', () async {
    final repository = _ControlledRepository()
      ..historyRows = const [
        HistoryTopologyRow(
          objectId: 'def',
          parents: ['abc'],
          refs: [],
          lane: 0,
          shape: 0,
        ),
        HistoryTopologyRow(
          objectId: 'abc',
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ];
    final service = RepositorySessionService(repository);
    await service.open('repository');
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            headObjectId: 'def',
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final tabId = service.workspace.activeTab!.id;
    WorkspaceNavigation navigation() => service.workspace.activeTab!.navigation;
    void open(WorkspacePane pane) => service.updateNavigation(
      tabId,
      navigation().copyWith(pane: pane, clearSelectedIdentity: true),
    );

    // A repository without local changes opens on History by itself.
    expect(navigation().pane, WorkspacePane.history);
    expect(repository.selectedHistoryObjectId, 'def');
    expect(service.history.current.page?.selectedObjectIds, ['def']);
    expect(navigation().selectedIdentity, 'def');

    service.updateNavigation(
      tabId,
      navigation().copyWith(selectedIdentity: 'abc'),
    );
    await service.history.select('abc');
    open(WorkspacePane.changes);
    service.updateNavigation(
      tabId,
      navigation().copyWith(selectedIdentity: 'tracked.txt'),
    );
    await service.history.select(null, focus: false);
    expect(service.history.current.page?.selectedObjectIds, isEmpty);

    open(WorkspacePane.history);
    await service.showHistory(tabId);
    expect(service.history.current.page?.selectedObjectIds, ['abc']);
    expect(navigation().selectedIdentity, 'abc');

    // Leaving History while it loads selects nothing behind the user's back.
    open(WorkspacePane.history);
    final shown = service.showHistory(tabId);
    open(WorkspacePane.changes);
    await service.history.select(null, focus: false);
    await shown;
    expect(navigation().selectedIdentity, isNull);
    await service.dispose();
  });

  test('only a pull that moved HEAD reveals it in History', () async {
    final repository = _ControlledRepository()
      ..historyRows = [
        HistoryTopologyRow(
          objectId: 'f' * 40,
          parents: const [],
          refs: const [],
          lane: 0,
          shape: 0,
        ),
      ];
    final service = RepositorySessionService(repository);
    final opened = await service.open('repository');
    final tab = service.workspace.activeTab!;
    service.updateNavigation(
      tab.id,
      tab.navigation.copyWith(pane: WorkspacePane.history),
    );
    await service.history.load(opened.identity);
    var revision = 0;
    Future<void> head(String objectId) async {
      repository.queuedEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: RepositorySnapshot(
            revision: BigInt.from(revision += 1),
            phase: RepositoryPhase.ready,
            status: RepositoryStatus(
              workingTree: WorkingTreeState.clean,
              headObjectId: objectId,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: const [],
              totalEntries: BigInt.zero,
              entriesTruncated: false,
              operations: const [],
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    Future<void> transfer(
      TransferKind kind,
      TransferExecutionState state,
    ) async {
      repository.transferResult = TransferExecutionResult(
        state: state,
        failure: state == TransferExecutionState.failed
            ? TransferFailureCode.rejected
            : null,
        ahead: BigInt.zero,
        behind: BigInt.zero,
      );
      await service.executeTransfer(
        await service.previewTransfer(TransferRequest(kind: kind)),
      );
    }

    String? selected() =>
        service.workspace.activeTab?.navigation.selectedIdentity;
    const completed = TransferExecutionState.completed;

    await head('a' * 40);
    // A commit from outside moves HEAD without moving the view.
    await head('b' * 40);
    expect(selected(), isNull);

    // Neither does a fetch, a pull that failed or one already up to date.
    await transfer(TransferKind.fetch, completed);
    await head('c' * 40);
    await transfer(TransferKind.pull, TransferExecutionState.failed);
    await head('d' * 40);
    await transfer(TransferKind.pull, completed);
    await head('d' * 40);
    await head('e' * 40);
    expect(selected(), isNull);
    expect(repository.selectedHistoryObjectId, isNull);

    await transfer(TransferKind.pull, completed);
    await head('f' * 40);
    // The selection follows the reload the pull caused.
    for (
      var wait = 0;
      wait < 100 && repository.selectedHistoryObjectId == null;
      wait++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(repository.selectedHistoryObjectId, 'f' * 40);
    expect(selected(), 'f' * 40);

    // The pull is settled; the next commit leaves the selection alone.
    await head('0' * 40);
    expect(selected(), 'f' * 40);
    await service.dispose();
  });

  test('path-only status refresh keeps visible history loaded', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final opened = await service.open('repository');
    final tab = service.workspace.activeTab!;
    service.updateNavigation(
      tab.id,
      tab.navigation.copyWith(pane: WorkspacePane.history),
    );
    await service.history.load(opened.identity);
    final initialLoads = repository.historyLoadCount;
    RepositorySnapshot snapshot(int revision, String path) =>
        RepositorySnapshot(
          revision: BigInt.from(revision),
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.dirty,
            ahead: BigInt.zero,
            behind: BigInt.zero,
            entries: [
              RepositoryStatusEntry(
                kind: StatusEntryKind.untracked,
                path: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: path.codeUnits,
                ),
                index: ChangeKind.unmodified,
                worktree: ChangeKind.unmodified,
              ),
            ],
            totalEntries: BigInt.one,
            entriesTruncated: false,
            operations: const [],
          ),
        );
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(1, 'first.txt'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final loaded = repository.historyLoadCount;
    expect(loaded, greaterThan(initialLoads));
    expect(
      service.current?.snapshot.status?.entries.single.path.units,
      'first.txt'.codeUnits,
    );
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(2, 'second.txt'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(repository.historyLoadCount, loaded);
    expect(
      service.current?.snapshot.status?.entries.single.path.units,
      'second.txt'.codeUnits,
    );
    await service.dispose();
  });

  test('a merged branch tip reloads visible history once', () async {
    const oldTip = '1111111111111111111111111111111111111111';
    const newTip = '2222222222222222222222222222222222222222';
    RepositorySnapshot snapshot(int revision, String tip, {int ahead = 0}) =>
        RepositorySnapshot(
          revision: BigInt.from(revision),
          phase: RepositoryPhase.ready,
          status: RepositoryStatus(
            workingTree: WorkingTreeState.clean,
            headObjectId: tip,
            ahead: BigInt.from(ahead),
            behind: BigInt.zero,
            entries: const [],
            totalEntries: BigInt.zero,
            entriesTruncated: false,
            operations: const [],
          ),
          refs: RepositoryRefs(
            branches: [
              RepositoryReference(
                name: 'main'.codeUnits,
                target: tip,
                head: true,
              ),
            ],
          ),
        );
    final repository = _ControlledRepository()
      ..historyRows = const [
        HistoryTopologyRow(
          objectId: oldTip,
          parents: [],
          refs: [],
          lane: 0,
          shape: 0,
        ),
      ];
    final service = RepositorySessionService(repository);
    final opened = await service.open('repository');
    final tab = service.workspace.activeTab!;
    service.updateNavigation(
      tab.id,
      tab.navigation.copyWith(pane: WorkspacePane.history),
    );
    await service.history.load(opened.identity);
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(1, oldTip),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final originalLoads = repository.historyLoadCount;
    repository.historyRows = const [
      HistoryTopologyRow(
        objectId: newTip,
        parents: [oldTip],
        refs: [],
        lane: 0,
        shape: 0,
      ),
    ];
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(2, newTip),
      ),
    );
    final preview = await service.previewHistoryMutation(
      const HistoryMutationRequest(
        kind: HistoryMutationKind.merge,
        targets: [newTip],
      ),
    );
    await service.executeHistoryMutation(preview);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // One reload, plus the page this fake reads to select the merged HEAD.
    expect(repository.historyLoadCount, originalLoads + 3);
    expect(service.history.current.page?.rows.single.objectId, newTip);
    expect(service.history.current.page?.selectedObjectIds, [newTip]);
    expect(service.workspace.activeTab?.navigation.selectedIdentity, newTip);

    final updatedLoads = repository.historyLoadCount;
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: snapshot(3, newTip, ahead: 1),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(repository.historyLoadCount, updatedLoads);
    await service.dispose();
  });

  test(
    'watch overflow is isolated per tab until a newer ready snapshot',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('first');
      final second = await service.open('second');
      repository.queuedEventsBySession[first.identity.nativeId] = [
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.watchOverflow,
          watchOverflowRevision: BigInt.from(4),
        ),
        _snapshotEvent(RepositorySessionEventKind.resynchronize, 4),
      ];

      // The first tab is hidden; hidden tabs drain every 200 ms.
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(
        service.workspace.tabs
            .firstWhere(
              (tab) =>
                  tab.session?.identity.nativeId == first.identity.nativeId,
            )
            .watchOverflowRevision,
        BigInt.from(4),
      );
      expect(
        service.workspace.tabs
            .firstWhere(
              (tab) =>
                  tab.session?.identity.nativeId == second.identity.nativeId,
            )
            .watchOverflowRevision,
        isNull,
      );

      repository.queuedEventsBySession[first.identity.nativeId] = [
        _snapshotEvent(RepositorySessionEventKind.resynchronize, 5),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(
        service.workspace.tabs
            .firstWhere(
              (tab) =>
                  tab.session?.identity.nativeId == first.identity.nativeId,
            )
            .watchOverflowRevision,
        isNull,
      );
      await service.dispose();
    },
  );

  test(
    'status transitions preserve selection and clear only owning failures',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('first');
      final firstTab = service.workspace.tabs.first;
      service.updateNavigation(
        firstTab.id,
        firstTab.navigation.copyWith(selectedIdentity: 'tracked.txt'),
      );
      final second = await service.open('second');
      repository.queuedEventsBySession[first.identity.nativeId] = [
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            statusFailure: const RepositoryFailure(RepositoryFailureCode.read),
          ),
        ),
      ];
      repository.queuedEventsBySession[second.identity.nativeId] = [
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: RepositorySnapshot(
            revision: BigInt.one,
            phase: RepositoryPhase.ready,
            refsFailure: const RepositoryFailure(RepositoryFailureCode.read),
          ),
        ),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 60));

      repository.queuedEventsBySession[first.identity.nativeId] = [
        _snapshotEvent(RepositorySessionEventKind.snapshot, 2),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final firstAfter = service.workspace.tabs.firstWhere(
        (tab) => tab.session?.identity.nativeId == first.identity.nativeId,
      );
      final secondAfter = service.workspace.tabs.firstWhere(
        (tab) => tab.session?.identity.nativeId == second.identity.nativeId,
      );
      expect(firstAfter.navigation.selectedIdentity, 'tracked.txt');
      expect(firstAfter.session?.snapshot.statusFailure, isNull);
      expect(
        secondAfter.session?.snapshot.refsFailure?.code,
        RepositoryFailureCode.read,
      );
      await service.dispose();
    },
  );

  test('close is idempotent and stops publication', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    await service.open('repository');
    await service.close();
    await service.close();
    expect(repository.closedGenerations, [1]);
    expect(service.current, isNull);
    await service.dispose();
  });

  test(
    'activity stays on-demand and uses the requested native bound',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      await service.open('repository');

      final page = await service.activity(maximumRecords: 7);

      expect(page.records, isEmpty);
      expect(repository.maximumActivityRequests, [7]);
      await service.dispose();
    },
  );

  test('ready identity becomes recent and init options remain typed', () async {
    final repository = _ControlledRepository();
    final settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    final service = RepositorySessionService(repository, settings);

    await service.initialize('destination', initialBranch: 'trunk', bare: true);
    final identity = _repositoryIdentity();
    repository.queuedEvents.add(
      RepositorySessionEvent(
        kind: RepositorySessionEventKind.snapshot,
        snapshot: RepositorySnapshot(
          revision: BigInt.one,
          phase: RepositoryPhase.ready,
          identity: identity,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repository.initializeRequests, [('destination', 'trunk', true)]);
    expect(settings.current.recentRepositories, [identity.worktreeRoot]);
    await service.dispose();
    await settings.dispose();
  });

  test(
    'clone publishes bounded progress and adopts the returned session',
    () async {
      final repository = _ControlledRepository();
      final clones = _ControlledCloneRepository();
      final service = RepositorySessionService(
        repository,
        null,
        null,
        CloneService(clones),
      );
      final phases = <CloneAttemptPhase>[];
      final subscription = service.cloneStates.listen(
        (snapshot) => phases.add(snapshot.phase),
      );

      final opened = await service.clone(
        source: 'https://example.test/team/repository.git',
        destination: '/tmp/repository',
      );

      expect(phases, [CloneAttemptPhase.pending, CloneAttemptPhase.succeeded]);
      expect(opened?.identity.generation, 1);
      expect(service.current?.identity.generation, 1);
      expect(clones.createdSource, 'https://example.test/team/repository.git');
      await service.dismissClone();
      expect(service.currentClone, isNull);
      await service.dispose();
      await subscription.cancel();
    },
  );

  test('clone cancellation is routed only to a running attempt', () async {
    final repository = _ControlledRepository();
    final clones = _ControlledCloneRepository(blockRun: true);
    final service = RepositorySessionService(
      repository,
      null,
      null,
      CloneService(clones),
    );
    final running = service.clone(
      source: 'https://example.test/team/repository.git',
      destination: '/tmp/repository',
    );
    await clones.runStarted.future;
    clones.publishRunning();
    await Future<void>.delayed(const Duration(milliseconds: 70));

    await service.cancelClone();
    expect(clones.cancelCount, 1);
    clones.completeCanceled();
    expect(await running, isNull);
    expect(service.currentClone?.phase, CloneAttemptPhase.canceled);
    await service.dispose();
  });

  test(
    'ref mutation preview and execution stay on the active generation',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      await service.open('/repository');
      const request = RefMutationRequest(
        kind: RefMutationKind.createBranch,
        name: 'topic',
        target: '1111111111111111111111111111111111111111',
      );
      final preview = await service.previewRefMutation(request);
      expect(preview.kind, RefMutationKind.createBranch);
      final result = await service.executeRefMutation(preview.token);
      expect(result.state, RefMutationExecutionState.completed);
      expect(repository.refMutationRequest, request);
      expect(repository.executedRefMutationToken, BigInt.from(44));
      expect(repository.refreshCount, 0);
      await service.dispose();
    },
  );

  test('staging stays bound to its session after tab closure', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final opened = await service.open('/repository');
    repository.workingDiffResult = DiffPage(
      requestId: BigInt.two,
      layout: DiffViewLayout.unified,
      totalRows: 0,
      offset: 0,
      rows: [],
      payloadBytes: 0,
    );

    final page = await service.workingDiff(side: StagingSide.unstaged);
    expect(page.requestId, BigInt.two);
    expect(repository.workingDiffIdentity, opened.identity);

    repository.stagingBarrier = Completer<void>();
    final execution = service.executeStaging(
      StagingRequest(
        requestId: BigInt.two,
        side: StagingSide.unstaged,
        scope: StagingScope.files,
        paths: [
          [116, 114, 97, 99, 107, 101, 100],
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.stagingRequest?.requestId, BigInt.two);
    await service.closeTab(service.workspace.activeTab!.id);
    repository.stagingBarrier!.complete();

    expect((await execution).state, StagingExecutionState.completed);
    expect(repository.stagingIdentity, opened.identity);
    expect(repository.refreshCount, 0);
    await service.dispose();
  });

  test(
    'commit clears only the draft revision that actually committed',
    () async {
      final identity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/work/repository'.codeUnits,
      );
      final settings = SettingsService(
        FakeSettingsRepository(
          loaded: LoadedSettings(
            state: SettingsLoadState.loaded,
            document: SettingsDocument(
              worktrees: [
                WorktreeSettings(
                  identity: identity,
                  draft: const CommitDraft(
                    subject: 'submitted',
                    description: 'body',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await settings.initialize();
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository, settings);
      await service.openRecent(identity);
      const submitted = CommitDraft(subject: 'submitted', description: 'body');
      final preview = await service.previewCommit(
        const CommitRequest(subject: 'submitted', description: 'body'),
      );
      repository.commitBarrier = Completer<void>();
      final execution = service.executeCommit(preview, submitted);
      await Future<void>.delayed(Duration.zero);
      service.updateCommitDraft(
        const CommitDraft(subject: 'new edit', description: 'kept'),
      );
      repository.commitBarrier!.complete();
      expect((await execution).state, CommitExecutionState.completed);
      expect(service.commitSequence, 1);
      expect(
        service.lastCommittedObjectId,
        '1111111111111111111111111111111111111111',
      );
      expect(service.lastCommitWasAmend, isFalse);
      expect(service.activeCommitDraft.subject, 'new edit');
      expect(repository.commitRequest?.subject, 'submitted');

      repository.commitBarrier = null;
      final latest = service.activeCommitDraft;
      final second = await service.previewCommit(
        CommitRequest(
          subject: latest.subject,
          description: latest.description,
          amend: true,
        ),
      );
      await service.executeCommit(second, latest);
      expect(service.commitSequence, 2);
      expect(service.lastCommitWasAmend, isTrue);
      expect(service.activeCommitDraft.subject, isEmpty);
      expect(repository.refreshCount, 0);
      final committedTab = service.workspace.activeTab!.id;
      await service.open('/other');
      expect(service.commitSequence, 0);
      expect(service.lastCommittedObjectId, isNull);
      expect(service.lastCommitWasAmend, isFalse);
      service.activateTab(committedTab);
      expect(service.commitSequence, 2);
      await service.dispose();
      await settings.dispose();
    },
  );

  test('patch previews execute against their owning session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final export = await service.previewPatchExport(
      const PatchExportRequest(
        workspaceDefault: true,
        destinationDirectory: '/output',
      ),
    );
    await service.open('/second');
    final exported = await service.executePatchExport(export);
    expect(exported.state, PatchExportExecutionState.completed);
    expect(repository.patchExportIdentity, first.identity);

    service.activateTab(service.workspace.tabs.first.id);
    final apply = await service.previewPatchApply('/input/change.patch');
    await service.open('/third');
    final applied = await service.executePatchApply(apply);
    expect(applied.state, PatchApplyExecutionState.completed);
    expect(repository.patchApplyIdentity, first.identity);
    expect(repository.refreshCount, 0);
    await service.dispose();
  });

  test(
    'transfer diagnostics retain outcomes and gate timing without private data',
    () async {
      await LoggingUtils.initialize();
      final history = DiagnosticHistory.instance;
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      try {
        final tab = await service.open('/private-path-sentinel');
        for (final detailed in [false, true]) {
          history.clear();
          if (detailed) {
            history.enableDetailed();
          } else {
            history.disableDetailed();
          }
          for (final kind in [
            TransferKind.fetch,
            TransferKind.pull,
            TransferKind.push,
          ]) {
            final preview = await service.previewTransfer(
              TransferRequest(
                kind: kind,
                remote: 'private-remote-sentinel',
                branch: 'private-branch-sentinel',
              ),
            );
            await service.executeTransfer(
              preview,
              credentials: const TransferCredentials(token: 'secret-sentinel'),
            );
          }
          repository.transferResult = TransferExecutionResult(
            state: TransferExecutionState.failed,
            failure: TransferFailureCode.authentication,
            ahead: BigInt.zero,
            behind: BigInt.zero,
          );
          await service.transfers.backgroundFetch(tab.identity);
          final text = history.snapshot(
            application: 'gitlama',
            version: 'test',
          );
          expect(text, contains('transfer_preview_started'));
          expect(text, contains('transfer_execute_finished'));
          expect(text, contains('background_fetch_execute_finished'));
          expect(text, contains('failure=6'));
          expect(text.contains('transfer_execute_timing'), detailed);
          expect(text, isNot(contains('sentinel')));
        }
      } finally {
        await service.dispose();
        history.disableDetailed();
        history.clear();
        await LoggingUtils.dispose();
      }
    },
  );

  test('transfer retry stays bound to the preview session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final preview = await service.previewTransfer(
      const TransferRequest(kind: TransferKind.push),
    );
    await service.open('/second');
    repository.transferResult = TransferExecutionResult(
      state: TransferExecutionState.failed,
      failure: TransferFailureCode.authentication,
      ahead: BigInt.one,
      behind: BigInt.zero,
    );
    expect(
      (await service.executeTransfer(preview)).failure,
      TransferFailureCode.authentication,
    );
    repository.transferResult = TransferExecutionResult(
      state: TransferExecutionState.completed,
      ahead: BigInt.zero,
      behind: BigInt.zero,
    );
    await service.executeTransfer(
      preview,
      credentials: const TransferCredentials(token: 'transient'),
    );
    expect(repository.transferIdentity, first.identity);
    expect(repository.transferCredentials?.token, 'transient');
    expect(repository.refreshCount, 0);
    await service.dispose();
  });

  test(
    'History reveals a HEAD an operation moved while it was hidden',
    () async {
      const oldTip = '1111111111111111111111111111111111111111';
      const newTip = '2222222222222222222222222222222222222222';
      RepositorySnapshot snapshot(int revision, String tip) =>
          RepositorySnapshot(
            revision: BigInt.from(revision),
            phase: RepositoryPhase.ready,
            status: RepositoryStatus(
              workingTree: WorkingTreeState.clean,
              headObjectId: tip,
              ahead: BigInt.zero,
              behind: BigInt.zero,
              entries: const [],
              totalEntries: BigInt.zero,
              entriesTruncated: false,
              operations: const [],
            ),
          );
      final repository = _ControlledRepository()
        ..historyRows = const [
          HistoryTopologyRow(
            objectId: newTip,
            parents: [oldTip],
            refs: [],
            lane: 0,
            shape: 0,
          ),
          HistoryTopologyRow(
            objectId: oldTip,
            parents: [],
            refs: [],
            lane: 0,
            shape: 0,
          ),
        ];
      final service = RepositorySessionService(repository);
      await service.open('repository');
      repository.queuedEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: snapshot(1, oldTip),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // A clean repository opens on History; the user moves to Changes.
      final tab = service.workspace.activeTab!;
      service.updateNavigation(
        tab.id,
        tab.navigation.copyWith(pane: WorkspacePane.changes),
      );
      final preview = await service.previewHistoryMutation(
        const HistoryMutationRequest(
          kind: HistoryMutationKind.cherryPick,
          targets: [newTip],
        ),
      );
      await service.executeHistoryMutation(preview);
      repository.queuedEvents.add(
        RepositorySessionEvent(
          kind: RepositorySessionEventKind.snapshot,
          snapshot: snapshot(2, newTip),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final hidden = service.workspace.activeTab!;
      service.updateNavigation(
        hidden.id,
        hidden.navigation.copyWith(pane: WorkspacePane.history),
      );
      await service.showHistory(hidden.id);
      expect(service.history.current.page?.selectedObjectIds, [newTip]);
      expect(service.workspace.activeTab?.navigation.selectedIdentity, newTip);
      expect(repository.selectedHistoryReveal, isTrue);
      await service.dispose();
    },
  );

  test('a running stash or history operation can be canceled', () async {
    final repository = _ControlledRepository()
      ..stashGate = Completer<void>()
      ..historyMutationGate = Completer<void>();
    final service = RepositorySessionService(repository);
    final opened = await service.open('/first');
    final stash = await service.previewStash(
      const StashRequest(kind: StashKind.push),
    );
    final stashing = service.executeStash(stash);
    await Future<void>.delayed(Duration.zero);
    expect(await service.cancelStash(stash), isTrue);
    expect(repository.canceledStashIdentity, opened.identity);
    repository.stashGate!.complete();
    await stashing;
    // A finished stash is gone and cannot be canceled any more.
    expect(await service.cancelStash(stash), isFalse);

    final mutation = await service.previewHistoryMutation(
      const HistoryMutationRequest(
        kind: HistoryMutationKind.cherryPick,
        targets: ['1111111111111111111111111111111111111111'],
      ),
    );
    final mutating = service.executeHistoryMutation(mutation);
    await Future<void>.delayed(Duration.zero);
    expect(await service.cancelHistoryMutation(mutation), isTrue);
    expect(repository.canceledHistoryMutationIdentity, opened.identity);
    repository.historyMutationGate!.complete();
    await mutating;
    expect(await service.cancelHistoryMutation(mutation), isFalse);
    await service.dispose();
  });

  test('stash execution stays bound to the preview session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final preview = await service.previewStash(
      const StashRequest(kind: StashKind.push, includeUntracked: true),
    );
    await service.open('/second');
    final result = await service.executeStash(preview);
    expect(result.state, StashExecutionState.completed);
    expect(repository.stashIdentity, first.identity);
    expect(repository.refreshCount, 0);
    await service.dispose();
  });

  test(
    'history mutation execution stays bound to the preview session',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('/first');
      final preview = await service.previewHistoryMutation(
        const HistoryMutationRequest(
          kind: HistoryMutationKind.cherryPick,
          targets: ['1111111111111111111111111111111111111111'],
        ),
      );
      await service.open('/second');
      final result = await service.executeHistoryMutation(preview);
      expect(result.state, HistoryMutationExecutionState.completed);
      expect(repository.historyMutationIdentity, first.identity);
      expect(repository.refreshCount, 0);
      await service.dispose();
    },
  );

  test(
    'conflict prediction and cancellation stay bound to their session',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('/first');
      final task = await service.beginConflictPrediction(
        ConflictPredictionKind.merge,
        '1111111111111111111111111111111111111111',
      );
      await service.open('/second');
      expect(await service.cancelConflictPrediction(task), isTrue);
      final result = await service.executeConflictPrediction(task);
      expect(result.complete, isTrue);
      expect(repository.conflictPredictionIdentity, first.identity);
      expect(repository.canceledConflictPredictionIdentity, first.identity);
      await service.dispose();
    },
  );

  test('rebase preview, cancellation and execution retain session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final plan = await service.loadRebasePlan(
      '1111111111111111111111111111111111111111',
      'main'.codeUnits,
    );
    await service.open('/second');
    final preview = await service.previewRebase(
      plan,
      plan.instructions,
      false,
      false,
    );
    expect(await service.cancelRebase(plan.token), isTrue);
    final result = await service.executeRebase(preview);
    expect(result.state, RebaseExecutionState.completed);
    expect(repository.rebaseIdentity, first.identity);
    expect(repository.canceledRebaseIdentity, first.identity);
    expect(repository.refreshCount, 0);
    await service.dispose();
  });

  test('fixup evidence and restack execution retain their session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final suggestion = await service.suggestFixupBase(
      paths: ['lib/a.dart'.codeUnits],
    );
    final plan = await service.planRestack('main'.codeUnits);
    await service.open('/second');
    expect(await service.cancelRestack(plan), isTrue);
    final result = await service.executeRestack(
      plan,
      acknowledgePublishedHistory: false,
    );
    expect(suggestion.state, FixupSuggestionState.suggested);
    expect(result.state, RestackExecutionState.completed);
    expect(repository.advancedRebaseIdentity, first.identity);
    expect(repository.canceledRestackIdentity, first.identity);
    expect(repository.refreshCount, 1);
    await service.dispose();
  });

  test('named snapshot restore remains bound to its preview session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final page = await service.namedSnapshots();
    final preview = await service.previewNamedSnapshotRestore(
      page.entries.single.id,
    );
    await service.open('/second');
    expect(await service.cancelNamedSnapshotRestore(preview), isTrue);
    final result = await service.executeNamedSnapshotRestore(preview);
    expect(result.state, NamedSnapshotExecutionState.completed);
    expect(repository.namedSnapshotIdentity, first.identity);
    expect(repository.canceledNamedSnapshotIdentity, first.identity);
    expect(repository.refreshCount, 0);
    await service.dispose();
  });

  test(
    'repository extension reads and mutations use the active session',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('/first');
      final inventory = await service.repositoryExtensions();
      expect(inventory.worktrees.single.current, isTrue);
      expect(repository.extensionIdentity, first.identity);
      await service.executeRepositoryExtension(
        const RepositoryExtensionMutationRequest(
          kind: RepositoryExtensionMutationKind.lfsPull,
        ),
      );
      expect(repository.extensionIdentity, first.identity);
      expect(repository.refreshCount, 0);
      await service.dispose();
    },
  );

  test(
    'failed worktree deletion restores the affected repository session',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final source = await service.openRecent(_path('/first'));
      await service.openRecent(_path('/linked'));
      service.activateTab(service.workspace.tabs.first.id);
      repository.extensionResult = const RepositoryExtensionMutationResult(
        state: RepositoryExtensionMutationState.failed,
        activityIds: [],
        failure: RepositoryExtensionFailureCode.dirty,
      );

      final result = await service.executeRepositoryExtension(
        RepositoryExtensionMutationRequest(
          kind: RepositoryExtensionMutationKind.worktreeDelete,
          worktreeRoot: _path('/linked'),
        ),
      );

      expect(result.failure, RepositoryExtensionFailureCode.dirty);
      expect(repository.closedGenerations, [2]);
      expect(
        service.workspace.tabs.map((tab) => tab.canonicalIdentity),
        containsAll([_path('/first'), _path('/linked')]),
      );
      expect(service.current?.identity, source.identity);
      await service.dispose();
    },
  );

  test(
    'integration preview and execution remain bound to the source session',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('/first');
      final preview = await service.previewIntegration(
        const IntegrationRequest(
          kind: IntegrationKind.custom,
          discoveredId: 'fixture',
        ),
      );
      await service.open('/second');
      final result = await service.executeIntegration(preview, confirmed: true);
      expect(result.state, IntegrationExecutionState.completed);
      expect(repository.integrationIdentity, first.identity);
      await service.dispose();
    },
  );

  test('power jobs remain bound to the source session', () async {
    final repository = _ControlledRepository();
    final service = RepositorySessionService(repository);
    final first = await service.open('/first');
    final token = await service.startDiffContentSearch(query: 'needle');
    await service.open('/second');
    final result = await service.pollDiffContentSearch(token);
    expect(result.state, PowerJobState.completed);
    expect(repository.integrationIdentity, first.identity);
    await service.dispose();
  });

  test(
    'conflict resolution and continuation retain the loaded session',
    () async {
      final repository = _ControlledRepository();
      final service = RepositorySessionService(repository);
      final first = await service.open('/first');
      final snapshot = await service.loadConflicts();
      await service.open('/second');
      final result = await service.continueConflictOperation(
        ConflictSequencerAction.continueOperation,
      );
      expect(snapshot.canContinue, isTrue);
      expect(result.state, ConflictContinuationState.completed);
      expect(repository.conflictIdentity, first.identity);
      expect(repository.refreshCount, 0);
      await service.dispose();
    },
  );

  test(
    'SSH challenge is bound, accepted, and retried through one attempt',
    () async {
      final repository = _ControlledRepository();
      final clones = _ControlledCloneRepository(hostKeyFlow: true);
      final service = RepositorySessionService(
        repository,
        null,
        null,
        CloneService(clones),
      );
      expect(
        await service.clone(
          source: 'ssh://git@example.test/repository',
          destination: '/tmp/repository',
        ),
        isNull,
      );

      final challenge = await service.probeCloneHostKey();
      expect(challenge.host, 'example.test');
      expect(service.currentClone?.hostKeyChallenge, same(challenge));
      final opened = await service.resolveCloneHostKey(
        challenge: challenge,
        accept: true,
      );

      expect(clones.acceptCount, 1);
      expect(clones.hostKeyRunCount, 1);
      expect(opened?.identity.generation, 1);
      await service.dispose();
    },
  );
}

RepositorySessionEvent _snapshotEvent(
  RepositorySessionEventKind kind,
  int revision,
) => RepositorySessionEvent(
  kind: kind,
  snapshot: RepositorySnapshot(
    revision: BigInt.from(revision),
    phase: RepositoryPhase.ready,
  ),
);

final class _ControlledRepository
    implements
        RepositorySessionRepository,
        PatchRepositorySessionRepository,
        TransferRepositorySessionRepository,
        StashRepositorySessionRepository,
        HistoryMutationRepositorySessionRepository,
        RebaseRepositorySessionRepository,
        ConflictRepositorySessionRepository,
        AdvancedRebaseRepositorySessionRepository,
        NamedSnapshotRepositorySessionRepository,
        ExtensionRepositorySessionRepository,
        IntegrationRepositorySessionRepository,
        PowerToolsRepositorySessionRepository {
  _ControlledRepository({
    this.delayOpen = false,
    this.canonicalIdentity = false,
  });

  final bool delayOpen;
  final bool canonicalIdentity;
  final Map<int, Completer<void>> _openBarriers = {};
  final List<RepositorySessionEvent> queuedEvents = [];
  final Map<BigInt, List<RepositorySessionEvent>> queuedEventsBySession = {};
  final List<int> closedGenerations = [];
  final List<int> maximumEventRequests = [];
  final List<int> maximumActivityRequests = [];
  final List<(String, String, bool)> initializeRequests = [];
  RefMutationRequest? refMutationRequest;
  BigInt? executedRefMutationToken;
  DiffPage workingDiffResult = _emptyControlledDiff;
  RepositorySessionIdentity? workingDiffIdentity;
  RepositorySessionIdentity? stagingIdentity;
  StagingRequest? stagingRequest;
  final List<StagingExecutionState> stagingOutcomes = [];
  int stagingCalls = 0;
  bool failRefresh = false;
  Completer<void>? stagingBarrier;
  CommitRequest? commitRequest;
  Completer<void>? commitBarrier;
  RepositorySessionIdentity? patchExportIdentity;
  RepositorySessionIdentity? patchApplyIdentity;
  RepositorySessionIdentity? transferIdentity;
  RepositorySessionIdentity? historyMutationIdentity;
  RepositorySessionIdentity? conflictPredictionIdentity;
  RepositorySessionIdentity? canceledConflictPredictionIdentity;
  RepositorySessionIdentity? rebaseIdentity;
  RepositorySessionIdentity? canceledRebaseIdentity;
  RepositorySessionIdentity? conflictIdentity;
  RepositorySessionIdentity? advancedRebaseIdentity;
  RepositorySessionIdentity? canceledRestackIdentity;
  RepositorySessionIdentity? namedSnapshotIdentity;
  RepositorySessionIdentity? extensionIdentity;
  RepositorySessionIdentity? integrationIdentity;
  bool? diffSearchOtherRefs;

  /// The reference scope of every history preview.
  final List<bool> historyOtherRefs = [];
  RepositorySessionIdentity? canceledNamedSnapshotIdentity;
  TransferCredentials? transferCredentials;
  RepositorySessionIdentity? stashIdentity;
  RepositorySessionIdentity? canceledStashIdentity;
  bool? selectedHistoryReveal;
  RepositorySessionIdentity? canceledHistoryMutationIdentity;
  Completer<void>? stashGate;
  Completer<void>? historyMutationGate;
  TransferExecutionResult transferResult = TransferExecutionResult(
    state: TransferExecutionState.completed,
    ahead: BigInt.zero,
    behind: BigInt.zero,
  );
  RepositoryExtensionMutationResult extensionResult =
      const RepositoryExtensionMutationResult(
        state: RepositoryExtensionMutationState.completed,
        activityIds: [],
      );
  int refreshCount = 0;
  int commitPreviewCount = 0;
  int historyLoadCount = 0;
  int openCalls = 0;
  Completer<void>? historyBarrier;
  String? selectedHistoryObjectId;
  List<HistoryTopologyRow> historyRows = const [];

  bool failNextOpen = false;

  void completeOpen(int generation) => _openBarriers[generation]!.complete();

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  open(String path, int generation) async {
    openCalls += 1;
    if (failNextOpen) {
      failNextOpen = false;
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.discovery),
      );
    }
    if (delayOpen) {
      final barrier = _openBarriers.putIfAbsent(
        generation,
        Completer<void>.new,
      );
      await barrier.future;
    }
    return (
      identity: RepositorySessionIdentity(
        nativeId: BigInt.from(generation),
        generation: generation,
      ),
      snapshot: RepositorySnapshot(
        revision: BigInt.zero,
        phase: RepositoryPhase.unloaded,
        identity: canonicalIdentity
            ? RepositoryIdentity(
                kind: RepositoryKind.worktree,
                headKind: HeadKind.attached,
                gitMajor: 2,
                gitMinor: 50,
                gitPatch: 1,
                worktreeRoot: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: path.codeUnits,
                ),
                // `/repo@name` is the linked worktree `name` of `/repo`.
                gitDir: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: path.contains('@')
                      ? '${path.split('@').first}/.git/worktrees/'
                                '${path.split('@').last}'
                            .codeUnits
                      : '$path/.git'.codeUnits,
                ),
                commonGitDir: NativePathIdentity(
                  platform: NativePathPlatform.unix,
                  units: '${path.split('@').first}/.git'.codeUnits,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) => open(
    canonicalIdentity
        ? String.fromCharCodes(identity.units)
        : 'native-identity',
    generation,
  );

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  initialize(
    String path,
    int generation, {
    String initialBranch = 'main',
    bool bare = false,
  }) {
    initializeRequests.add((path, initialBranch, bare));
    return open(path, generation);
  }

  @override
  Future<List<RepositorySessionEvent>> events(
    RepositorySessionIdentity identity, {
    int maximumEvents = 64,
  }) async {
    maximumEventRequests.add(maximumEvents);
    final queue = queuedEventsBySession[identity.nativeId] ?? queuedEvents;
    final events = queue.take(maximumEvents).toList(growable: false);
    queue.removeRange(0, events.length);
    return events;
  }

  @override
  Future<void> refresh(RepositorySessionIdentity identity) async {
    refreshCount += 1;
    if (failRefresh) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.read),
      );
    }
  }

  @override
  Future<ActivityPage> activity(
    RepositorySessionIdentity identity, {
    int maximumRecords = 20,
  }) async {
    maximumActivityRequests.add(maximumRecords);
    return const ActivityPage(records: [], evictedThroughId: null);
  }

  @override
  Future<ActivityPage> activityRecord(
    RepositorySessionIdentity identity,
    BigInt activityId,
  ) async => const ActivityPage(records: [], evictedThroughId: null);

  @override
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = 512,
  }) async {
    historyLoadCount += 1;
    if (!complete) historyOtherRefs.add(otherRefs);
    await historyBarrier?.future;
    return HistoryPage(
      requestId: BigInt.one,
      complete: complete,
      totalRows: historyRows.length,
      offset: 0,
      rows: historyRows,
      laneCount: historyRows.isEmpty ? 0 : 1,
      payloadBytes: 0,
    );
  }

  @override
  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) => loadHistory(identity, complete: true, maximumRows: maximumRows);

  @override
  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = 512,
  }) => loadHistory(identity, complete: true, maximumRows: maximumRows);

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
    selectedHistoryObjectId = objectId;
    selectedHistoryReveal = reveal;
    final page = await historyPage(
      identity,
      requestId: requestId,
      offset: offset,
      maximumRows: maximumRows,
    );
    return HistoryPage(
      requestId: page.requestId,
      complete: page.complete,
      totalRows: page.totalRows,
      offset: page.offset,
      rows: [
        for (final row in page.rows)
          HistoryTopologyRow(
            objectId: row.objectId,
            parents: row.parents,
            refs: row.refs,
            refCount: row.refCount,
            refsTruncated: row.refsTruncated,
            lane: row.lane,
            shape: row.shape,
            subject: row.subject,
            author: row.author,
            avatarHash: row.avatarHash,
            authorTime: row.authorTime,
            metadataFailure: row.metadataFailure,
            selected: row.objectId == objectId,
            current: row.objectId == objectId,
            lit: row.objectId == objectId,
          ),
      ],
      segments: page.segments,
      laneCount: page.laneCount,
      payloadBytes: page.payloadBytes,
      lightingActive: objectId != null,
      currentObjectId: objectId,
      selectedObjectIds: [?objectId],
      focusedObjectId: focus ? objectId : null,
    );
  }

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = 512,
  }) async => _emptyControlledDiff;

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => _emptyControlledDiff;

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
  }) async {
    workingDiffIdentity = identity;
    return workingDiffResult;
  }

  @override
  Future<DiffPage> workingDiffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => _emptyControlledDiff;

  @override
  Future<StagingPhase?> stagingPhase(
    RepositorySessionIdentity identity,
  ) async => null;

  @override
  Future<StagingExecutionResult> executeStaging(
    RepositorySessionIdentity identity,
    StagingRequest request,
  ) async {
    stagingIdentity = identity;
    stagingRequest = request;
    stagingCalls++;
    await stagingBarrier?.future;
    return StagingExecutionResult(
      state: stagingOutcomes.isEmpty
          ? StagingExecutionState.completed
          : stagingOutcomes.removeAt(0),
    );
  }

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
  }) async => const ImageDiffContent();

  @override
  Future<ImageDiffContent> workingImageDiff(
    RepositorySessionIdentity identity, {
    required StagingSide side,
    List<int>? oldPath,
    List<int>? newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => const ImageDiffContent();

  @override
  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  }) async => const [];

  @override
  Future<IndexLockInspection> inspectIndexLock(
    RepositorySessionIdentity identity,
  ) async => const IndexLockInspection(present: false);

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

  @override
  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = 512,
  }) => historyPage(identity, requestId: requestId, offset: offset);

  final List<HistoryBranchFilter> branchFilterRequests = [];

  @override
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = 512,
  }) async {
    branchFilterRequests.add(filter);
    return null;
  }

  @override
  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = 512,
  }) => historyPage(identity, requestId: requestId, offset: offset);

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
      tree: commit,
      parents: const [],
      author: const [],
      authorTime: 0,
      authorTimezone: const [],
      committer: const [],
      committerTime: 0,
      committerTimezone: const [],
      message: const [],
    ),
    files: const [],
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
  }) async => BlamePage(
    requestId: BigInt.one,
    revision: revision,
    path: path,
    totalRows: 0,
    offset: 0,
    rows: const [],
  );

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = 512,
  }) async => BlamePage(
    requestId: requestId,
    revision: '',
    path: const [],
    totalRows: 0,
    offset: offset,
    rows: const [],
  );

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
  }) async => const RestoreResult(state: RestoreState.restored);

  @override
  Future<RefMutationPreview> previewRefMutation(
    RepositorySessionIdentity identity,
    RefMutationRequest request,
  ) async {
    refMutationRequest = request;
    return RefMutationPreview(
      token: BigInt.from(44),
      kind: request.kind,
      arguments: const ['branch', 'topic'],
      warnings: const [],
    );
  }

  @override
  Future<RefMutationExecutionResult> executeRefMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    executedRefMutationToken = token;
    return const RefMutationExecutionResult(
      state: RefMutationExecutionState.completed,
    );
  }

  @override
  Future<CommitTools> commitTools(RepositorySessionIdentity identity) async =>
      const CommitTools();

  @override
  Future<CommitPreview> previewCommit(
    RepositorySessionIdentity identity,
    CommitRequest request,
  ) async {
    commitRequest = request;
    return CommitPreview(
      token: BigInt.from(commitPreviewCount += 1),
      warnings: const [],
      arguments: const ['commit', '--file=-'],
    );
  }

  @override
  Future<CommitExecutionResult> executeCommit(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    await commitBarrier?.future;
    return const CommitExecutionResult(
      state: CommitExecutionState.completed,
      commit: '1111111111111111111111111111111111111111',
    );
  }

  @override
  Future<DiscardPreview> previewDiscard(
    RepositorySessionIdentity identity,
    DiscardRequest request,
  ) async => DiscardPreview(
    token: BigInt.one,
    kind: request.kind,
    fileCount: request.paths.length,
    arguments: const [],
  );

  @override
  Future<DiscardExecutionResult> executeDiscard(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async =>
      const DiscardExecutionResult(state: DiscardExecutionState.completed);

  @override
  Future<PatchExportPreview> previewPatchExport(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async => PatchExportPreview(
    token: BigInt.from(77),
    scope: PatchExportScope.head,
    format: PatchFormat.unifiedDiff,
    filename: 'repository.patch',
    destination: '${request.destinationDirectory}/repository.patch',
    byteCount: 42,
    requiresOverwrite: false,
  );

  @override
  Future<PatchExportContent> patchExportContent(
    RepositorySessionIdentity identity,
    PatchExportRequest request,
  ) async => PatchExportContent(
    scope: PatchExportScope.unstaged,
    format: PatchFormat.unifiedDiff,
    filename: 'repository.patch',
    bytes: 'diff\n'.codeUnits,
  );

  @override
  Future<PatchExportPreview> previewPatchSave(
    PatchExportContent content, {
    required String destinationDirectory,
    required bool overwrite,
  }) async => PatchExportPreview(
    token: BigInt.one,
    scope: content.scope,
    format: content.format,
    filename: content.filename,
    destination: '$destinationDirectory/${content.filename}',
    byteCount: content.bytes.length,
    requiresOverwrite: false,
  );

  @override
  Future<PatchExportExecutionResult> executePatchSave(BigInt token) async =>
      const PatchExportExecutionResult(
        state: PatchExportExecutionState.completed,
      );

  @override
  Future<PatchExportExecutionResult> executePatchExport(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    patchExportIdentity = identity;
    return const PatchExportExecutionResult(
      state: PatchExportExecutionState.completed,
      destination: '/output/repository.patch',
    );
  }

  @override
  Future<PatchApplyPreview> previewPatchApply(
    RepositorySessionIdentity identity,
    String patchPath,
  ) async => PatchApplyPreview(
    token: BigInt.from(78),
    paths: const [
      [116, 114, 97, 99, 107, 101, 100],
    ],
    binary: false,
    arguments: const ['apply', '--recount', '<patch>'],
  );

  @override
  Future<PatchApplyExecutionResult> executePatchApply(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    patchApplyIdentity = identity;
    return PatchApplyExecutionResult(state: PatchApplyExecutionState.completed);
  }

  @override
  Future<TransferPreview> previewTransfer(
    RepositorySessionIdentity identity,
    TransferRequest request,
  ) async => TransferPreview(
    token: BigInt.from(79),
    kind: request.kind,
    remote: 'origin',
    branch: 'main',
    arguments: const ['push', '--progress', 'origin'],
    ahead: BigInt.one,
    behind: BigInt.zero,
    dirty: false,
    expectedRemoteObjectId: null,
    forceWithLease: false,
  );

  @override
  Future<TransferExecutionResult> executeTransfer(
    RepositorySessionIdentity identity,
    BigInt token, {
    TransferCredentials? credentials,
  }) async {
    transferIdentity = identity;
    transferCredentials = credentials;
    return transferResult;
  }

  final List<RepositorySessionIdentity> backgroundFetches = [];

  @override
  Future<TransferExecutionResult> executeBackgroundFetch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    backgroundFetches.add(identity);
    return transferResult;
  }

  @override
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity identity,
    List<String> references,
  ) async => TransferExecutionResult(
    state: TransferExecutionState.completed,
    ahead: BigInt.zero,
    behind: BigInt.zero,
  );

  @override
  Future<bool> cancelTransfer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<HostKeyChallenge> probeTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => HostKeyChallenge(
    challengeId: BigInt.one,
    host: 'example.test',
    port: 22,
    algorithm: 'ssh-ed25519',
    fingerprint: 'SHA256:test',
  );

  @override
  Future<void> resolveTransferHostKey(
    RepositorySessionIdentity identity,
    BigInt token,
    HostKeyChallenge challenge, {
    required bool accept,
  }) async {}

  @override
  Future<StashPreview> previewStash(
    RepositorySessionIdentity identity,
    StashRequest request,
  ) async {
    stashIdentity = identity;
    return StashPreview(
      token: BigInt.from(80),
      kind: request.kind,
      commands: const [
        ['stash', 'push'],
      ],
      affectedPaths: 1,
      includesUntracked: request.includeUntracked,
      keepsIndex: request.keepIndex,
      destructive: false,
    );
  }

  @override
  Future<StashExecutionResult> executeStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    stashIdentity = identity;
    if (stashGate case final gate?) await gate.future;
    return const StashExecutionResult(
      state: StashExecutionState.completed,
      activityIds: ['80'],
      stashCreated: true,
      checkoutCompleted: false,
      reapplyCompleted: false,
      stashRetained: false,
    );
  }

  @override
  Future<bool> cancelStash(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledStashIdentity = identity;
    return true;
  }

  @override
  Future<HistoryMutationPreview> previewHistoryMutation(
    RepositorySessionIdentity identity,
    HistoryMutationRequest request,
  ) async {
    historyMutationIdentity = identity;
    return HistoryMutationPreview(
      token: BigInt.from(85),
      kind: request.kind,
      arguments: const ['cherry-pick', '1'],
      targets: request.targets,
      currentBranch: 'main'.codeUnits,
      currentHead: '0' * 40,
      publishedHistory: false,
      alreadyContained: false,
    );
  }

  @override
  Future<HistoryMutationExecutionResult> executeHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    historyMutationIdentity = identity;
    if (historyMutationGate case final gate?) await gate.future;
    return const HistoryMutationExecutionResult(
      state: HistoryMutationExecutionState.completed,
      activityIds: ['85'],
      conflictingPaths: [],
    );
  }

  @override
  Future<bool> cancelHistoryMutation(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledHistoryMutationIdentity = identity;
    return true;
  }

  @override
  Future<BigInt> beginConflictPrediction(
    RepositorySessionIdentity identity,
  ) async {
    conflictPredictionIdentity = identity;
    return BigInt.from(86);
  }

  @override
  Future<ConflictPredictionResult> executeConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
    ConflictPredictionKind kind,
    String target,
  ) async {
    conflictPredictionIdentity = identity;
    return ConflictPredictionResult(
      kind: kind,
      target: target,
      conflictingPaths: const [],
      analyzedCommits: 1,
      totalCommits: 1,
      complete: true,
      activityIds: const ['86'],
    );
  }

  @override
  Future<bool> cancelConflictPrediction(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledConflictPredictionIdentity = identity;
    return true;
  }

  @override
  Future<RebasePlan> loadRebasePlan(
    RepositorySessionIdentity identity,
    String onto,
    List<int>? ontoName,
  ) async {
    rebaseIdentity = identity;
    return RebasePlan(
      token: BigInt.from(87),
      onto: onto,
      ontoName: ontoName,
      currentBranch: 'topic'.codeUnits,
      currentHead: '2' * 40,
      instructions: [
        RebaseInstruction(
          id: BigInt.one,
          action: RebaseAction.pick,
          oid: '2' * 40,
          subject: 'topic commit'.codeUnits,
          published: false,
        ),
      ],
      publishedCount: 0,
      activityIds: const ['87'],
    );
  }

  @override
  Future<RebasePreview> previewRebase(
    RepositorySessionIdentity identity,
    BigInt token,
    List<RebaseInstruction> instructions,
    bool acknowledgePublishedHistory,
    bool applyAutosquash,
  ) async {
    rebaseIdentity = identity;
    return RebasePreview(
      token: token,
      arguments: const ['rebase', '--interactive', '1'],
      todo: 'pick 2 topic commit\n'.codeUnits,
      instructionCount: instructions.length,
      publishedCount: 0,
      instructions: instructions,
      autosquashApplied: 0,
    );
  }

  @override
  Future<RebaseExecutionResult> executeRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    rebaseIdentity = identity;
    return const RebaseExecutionResult(
      state: RebaseExecutionState.completed,
      activityIds: ['87'],
      conflictingPaths: [],
    );
  }

  @override
  Future<bool> cancelRebase(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledRebaseIdentity = identity;
    return true;
  }

  @override
  Future<FixupSuggestion> suggestFixupBase(
    RepositorySessionIdentity identity, {
    String? selectedCommit,
    List<List<int>> paths = const [],
  }) async {
    advancedRebaseIdentity = identity;
    return FixupSuggestion(
      state: FixupSuggestionState.suggested,
      candidate: '1' * 40,
      subject: 'base'.codeUnits,
      fixupMessage: 'fixup! base'.codeUnits,
      squashMessage: 'squash! base'.codeUnits,
      evidence: const [],
      activityIds: const ['88'],
    );
  }

  @override
  Future<RestackPlan> planRestack(
    RepositorySessionIdentity identity,
    List<int> rootBranch,
  ) async {
    advancedRebaseIdentity = identity;
    return RestackPlan(
      token: BigInt.from(88),
      rootBranch: rootBranch,
      steps: [
        RestackStep(
          id: 0,
          branch: 'topic'.codeUnits,
          expectedHead: '2' * 40,
          oldParent: '1' * 40,
          newParent: rootBranch,
          expectedNewParentHead: '3' * 40,
          published: false,
        ),
      ],
      publishedCount: 0,
      incomplete: false,
      activityIds: const ['88'],
    );
  }

  @override
  Future<RestackExecutionResult> executeRestack(
    RepositorySessionIdentity identity,
    BigInt token,
    bool acknowledgePublishedHistory,
  ) async {
    advancedRebaseIdentity = identity;
    return const RestackExecutionResult(
      state: RestackExecutionState.completed,
      completedSteps: 1,
      totalSteps: 1,
      recoveryRefs: [],
      conflictingPaths: [],
      activityIds: ['88'],
    );
  }

  @override
  Future<bool> cancelRestack(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledRestackIdentity = identity;
    return true;
  }

  NamedSnapshot get _snapshot => NamedSnapshot(
    id: BigInt.one,
    name: 'checkpoint',
    createdAtUnixMs: BigInt.one,
    baseOid: '1' * 40,
    objectId: '2' * 40,
    stagedCount: 1,
    unstagedCount: 0,
    untrackedCount: 0,
    includesUntracked: true,
    keepsIndex: false,
    state: NamedSnapshotState.ready,
  );

  @override
  Future<NamedSnapshotPage> namedSnapshots(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximum = 32,
  }) async {
    namedSnapshotIdentity = identity;
    return NamedSnapshotPage(entries: [_snapshot], total: 1);
  }

  @override
  Future<NamedSnapshotExecutionResult> createNamedSnapshot(
    RepositorySessionIdentity identity, {
    required String name,
    required bool includeUntracked,
    required bool keepIndex,
  }) async {
    namedSnapshotIdentity = identity;
    return NamedSnapshotExecutionResult(
      state: NamedSnapshotExecutionState.completed,
      snapshot: _snapshot,
      conflictingPaths: const [],
      activityIds: const ['89'],
    );
  }

  @override
  Future<NamedSnapshotRestorePreview> previewNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) async {
    namedSnapshotIdentity = identity;
    return NamedSnapshotRestorePreview(
      token: BigInt.from(89),
      snapshot: _snapshot,
      replacementPaths: const [],
      replacementPathsTruncated: false,
      replacesIndex: true,
      replacesWorktree: true,
    );
  }

  @override
  Future<NamedSnapshotExecutionResult> executeNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    namedSnapshotIdentity = identity;
    return const NamedSnapshotExecutionResult(
      state: NamedSnapshotExecutionState.completed,
      conflictingPaths: [],
      activityIds: ['89'],
    );
  }

  @override
  Future<bool> cancelNamedSnapshotRestore(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    canceledNamedSnapshotIdentity = identity;
    return true;
  }

  @override
  Future<NamedSnapshotExecutionResult> branchFromNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
    List<int> branch,
  ) => createNamedSnapshot(
    identity,
    name: 'branch',
    includeUntracked: false,
    keepIndex: false,
  );

  @override
  Future<NamedSnapshotExecutionResult> deleteNamedSnapshot(
    RepositorySessionIdentity identity,
    BigInt snapshotId,
  ) => createNamedSnapshot(
    identity,
    name: 'delete',
    includeUntracked: false,
    keepIndex: false,
  );

  @override
  Future<RepositoryExtensionInventory> repositoryExtensions(
    RepositorySessionIdentity identity,
  ) async {
    extensionIdentity = identity;
    return RepositoryExtensionInventory(
      worktrees: [
        WorktreeEntry(
          worktreeRoot: _path('/first'),
          gitDir: _path('/first/.git'),
          commonGitDir: _path('/first/.git'),
          locked: false,
          prunable: false,
          current: true,
        ),
      ],
      submodules: const [],
      lfsAvailable: false,
      lfsUnavailableReason: true,
      lfsEntries: const [],
      activityIds: const [],
    );
  }

  @override
  Future<NativePathIdentity> enterSubmodule(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    extensionIdentity = identity;
    return _path('/first/submodule');
  }

  @override
  Future<LfsPointer?> inspectLfsPointer(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    extensionIdentity = identity;
    return null;
  }

  @override
  String? exactIgnorePattern(List<int> path, {required bool directory}) =>
      '/${String.fromCharCodes(path)}${directory ? '/' : ''}';

  @override
  Future<RepositoryExtensionMutationResult> executeRepositoryExtension(
    RepositorySessionIdentity identity,
    RepositoryExtensionMutationRequest request,
  ) async {
    extensionIdentity = identity;
    return extensionResult;
  }

  @override
  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) async => const [];

  @override
  Future<IntegrationPreview> previewIntegration(
    RepositorySessionIdentity identity,
    IntegrationRequest request,
  ) async {
    integrationIdentity = identity;
    return IntegrationPreview(
      token: BigInt.from(101),
      kind: request.kind,
      definitionId: request.discoveredId ?? request.configured?.id ?? 'tool',
      executable: '/tool',
      arguments: const [],
      explicitShell: false,
      waitsForExit: true,
      requiresConfirmation: true,
    );
  }

  @override
  Future<IntegrationPreview> previewExternalConflictMerge(
    RepositorySessionIdentity identity,
    ConflictFile file,
    IntegrationDefinition definition,
  ) => previewIntegration(
    identity,
    IntegrationRequest(kind: IntegrationKind.mergeTool, configured: definition),
  );

  @override
  Future<IntegrationPreview> previewExternalCommitDiff(
    RepositorySessionIdentity identity, {
    required String? oldRevision,
    required String newRevision,
    required List<int>? oldPath,
    required List<int>? newPath,
    required IntegrationDefinition definition,
  }) => previewIntegration(
    identity,
    IntegrationRequest(kind: IntegrationKind.diffTool, configured: definition),
  );

  @override
  Future<IntegrationExecutionResult> executeIntegration(
    RepositorySessionIdentity identity,
    BigInt token, {
    required bool confirmed,
  }) async {
    integrationIdentity = identity;
    return const IntegrationExecutionResult(
      state: IntegrationExecutionState.completed,
    );
  }

  @override
  Future<bool> cancelIntegration(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    integrationIdentity = identity;
    return true;
  }

  @override
  Future<BigInt> startDiffContentSearch(
    RepositorySessionIdentity identity, {
    required String query,
    required int maximumCommits,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
    bool otherRefs = false,
  }) async {
    integrationIdentity = identity;
    diffSearchOtherRefs = otherRefs;
    return BigInt.from(201);
  }

  @override
  Future<DiffContentSearchResult> pollDiffContentSearch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async {
    integrationIdentity = identity;
    return const DiffContentSearchResult(
      state: PowerJobState.completed,
      matches: [],
      examinedCommits: 0,
      completeness: SearchCompleteness.complete,
      activityIds: [],
    );
  }

  @override
  Future<BigInt> startRepositoryStatistics(
    RepositorySessionIdentity identity,
  ) async {
    integrationIdentity = identity;
    return BigInt.from(202);
  }

  @override
  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const RepositoryStatisticsResult(
    state: PowerJobState.completed,
    commitCount: 1,
    localBranchCount: 1,
    tagCount: 0,
    changedPathCount: 0,
    incomplete: false,
    activityIds: [],
  );

  @override
  Future<bool> cancelPowerJob(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<BisectState> bisectState(RepositorySessionIdentity identity) async =>
      const BisectState(active: false, timeline: []);

  @override
  Future<BisectPreview> previewBisect(
    RepositorySessionIdentity identity,
    BisectAction action, {
    String? good,
    String? bad,
  }) async => BisectPreview(
    token: BigInt.from(203),
    action: action,
    arguments: const ['bisect', 'start'],
  );

  @override
  Future<BisectExecutionResult> executeBisect(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const BisectExecutionResult(
    state: BisectExecutionState.completed,
    bisect: BisectState(active: true, timeline: []),
  );

  @override
  Future<bool> cancelBisectPreview(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<ConflictSnapshot> loadConflicts(
    RepositorySessionIdentity identity,
  ) async {
    conflictIdentity = identity;
    return _controlledConflict;
  }

  @override
  Future<ConflictSnapshot> saveConflictResult(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    List<int> result,
  ) async {
    conflictIdentity = identity;
    return _controlledConflict;
  }

  @override
  Future<ConflictSnapshot> chooseConflictSide(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    ConflictSideChoice choice,
  ) async {
    conflictIdentity = identity;
    return _controlledConflict;
  }

  @override
  Future<ConflictSnapshot> takeConflictRegion(
    RepositorySessionIdentity identity,
    List<int> path,
    BigInt expectedFingerprint,
    int regionIndex,
    ConflictRegionChoice choice,
  ) async {
    conflictIdentity = identity;
    return _controlledConflict;
  }

  @override
  Future<ConflictSnapshot> undoConflictResolution(
    RepositorySessionIdentity identity,
    List<int> path,
  ) async {
    conflictIdentity = identity;
    return _controlledConflict;
  }

  @override
  Future<ConflictContinuationResult> continueConflictOperation(
    RepositorySessionIdentity identity,
    ConflictSequencerAction action, {
    String? mergeMessage,
  }) async {
    conflictIdentity = identity;
    return const ConflictContinuationResult(
      state: ConflictContinuationState.completed,
      activityIds: ['88'],
    );
  }

  @override
  Future<bool> close(RepositorySessionIdentity identity) async {
    closedGenerations.add(identity.generation);
    return true;
  }
}

final _emptyControlledDiff = DiffPage(
  requestId: BigInt.zero,
  layout: DiffViewLayout.unified,
  totalRows: 0,
  offset: 0,
  rows: const [],
  payloadBytes: 0,
);

final _controlledConflict = ConflictSnapshot(
  operation: ConflictOperationKind.merge,
  currentLabel: 'main'.codeUnits,
  incomingLabel: 'topic'.codeUnits,
  files: const [],
  resolvedUndoPaths: const [],
  canContinue: true,
  canSkip: false,
);

final class _ControlledCloneRepository implements CloneRepository {
  _ControlledCloneRepository({this.blockRun = false, this.hostKeyFlow = false});

  final bool blockRun;
  final bool hostKeyFlow;
  final runStarted = Completer<void>();
  final _completion = Completer<CloneRunCompletion>();
  CloneAttemptSnapshot? _snapshot;
  String? createdSource;
  var cancelCount = 0;
  var acceptCount = 0;
  var hostKeyRunCount = 0;

  @override
  Future<CloneAttemptSnapshot> create({
    required String source,
    required String destination,
    String? initialBranch,
    required int generation,
  }) async {
    createdSource = source;
    return _snapshot = CloneAttemptSnapshot(
      attemptId: BigInt.one,
      generation: generation,
      phase: CloneAttemptPhase.pending,
      partialDestination: false,
    );
  }

  @override
  Future<CloneRunCompletion> run(CloneAttemptSnapshot attempt) async {
    if (blockRun) {
      runStarted.complete();
      return _completion.future;
    }
    if (hostKeyFlow) {
      final failed = _copy(
        CloneAttemptPhase.failed,
        failure: const CloneFailure(CloneFailureCode.hostKey),
      );
      _snapshot = failed;
      return CloneRunCompletion(snapshot: failed);
    }
    final succeeded = _copy(CloneAttemptPhase.succeeded);
    return CloneRunCompletion(
      snapshot: succeeded,
      openedSession: (
        identity: RepositorySessionIdentity(
          nativeId: BigInt.from(99),
          generation: attempt.generation,
        ),
        snapshot: RepositorySnapshot(
          revision: BigInt.zero,
          phase: RepositoryPhase.unloaded,
        ),
      ),
    );
  }

  @override
  Future<CloneRunCompletion> runWithCredentials(
    CloneAttemptSnapshot attempt, {
    String? username,
    String? password,
    String? token,
  }) => run(attempt);

  @override
  Future<HostKeyChallenge> probeHostKey(CloneAttemptSnapshot attempt) async {
    final challenge = HostKeyChallenge(
      challengeId: BigInt.from(77),
      host: 'example.test',
      port: 22,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:fixture',
    );
    _snapshot = _copy(
      CloneAttemptPhase.failed,
      failure: const CloneFailure(CloneFailureCode.hostKey),
      hostKeyChallenge: challenge,
    );
    return challenge;
  }

  @override
  Future<void> acceptHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) async {
    expect(challenge.challengeId, BigInt.from(77));
    acceptCount += 1;
  }

  @override
  Future<void> rejectHostKey(
    CloneAttemptSnapshot attempt,
    HostKeyChallenge challenge,
  ) => throw UnimplementedError();

  @override
  Future<CloneRunCompletion> runWithHostKey(CloneAttemptSnapshot attempt) =>
      _runWithHostKey(attempt);

  Future<CloneRunCompletion> _runWithHostKey(
    CloneAttemptSnapshot attempt,
  ) async {
    hostKeyRunCount += 1;
    final succeeded = _copy(CloneAttemptPhase.succeeded);
    _snapshot = succeeded;
    return CloneRunCompletion(
      snapshot: succeeded,
      openedSession: (
        identity: RepositorySessionIdentity(
          nativeId: BigInt.from(100),
          generation: attempt.generation,
        ),
        snapshot: RepositorySnapshot(
          revision: BigInt.zero,
          phase: RepositoryPhase.unloaded,
        ),
      ),
    );
  }

  @override
  Future<CloneAttemptSnapshot> retry(
    CloneAttemptSnapshot attempt, {
    String? destination,
  }) async => _snapshot = CloneAttemptSnapshot(
    attemptId: attempt.attemptId,
    generation: attempt.generation,
    phase: CloneAttemptPhase.pending,
    partialDestination: false,
  );

  void publishRunning() => _snapshot = _copy(CloneAttemptPhase.running);

  void completeCanceled() {
    final canceled = _copy(
      CloneAttemptPhase.canceled,
      failure: const CloneFailure(CloneFailureCode.canceled),
    );
    _completion.complete(CloneRunCompletion(snapshot: canceled));
  }

  CloneAttemptSnapshot _copy(
    CloneAttemptPhase phase, {
    CloneFailure? failure,
    HostKeyChallenge? hostKeyChallenge,
  }) {
    final current = _snapshot!;
    return CloneAttemptSnapshot(
      attemptId: current.attemptId,
      generation: current.generation,
      phase: phase,
      failure: failure,
      partialDestination: false,
      hostKeyChallenge: hostKeyChallenge,
    );
  }

  @override
  Future<CloneAttemptSnapshot> snapshot(CloneAttemptSnapshot attempt) async =>
      _snapshot!;

  @override
  Future<void> cancel(CloneAttemptSnapshot attempt) async {
    cancelCount += 1;
  }

  @override
  Future<void> dismiss(CloneAttemptSnapshot attempt) async {}
}

RepositoryIdentity _repositoryIdentity() {
  final path = NativePathIdentity(
    platform: NativePathPlatform.unix,
    units: const [47, 114, 101, 112, 111],
  );
  return RepositoryIdentity(
    commonGitDir: path,
    worktreeRoot: path,
    gitDir: path,
    kind: RepositoryKind.worktree,
    headKind: HeadKind.unborn,
    headReference: const [114, 101, 102, 115],
    gitMajor: 2,
    gitMinor: 50,
    gitPatch: 1,
  );
}

NativePathIdentity _path(String value) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: value.codeUnits,
);

class _ChooserPicker implements DirectoryPickerRepository {
  @override
  Future<String?> chooseSaveFile({
    required String suggestedName,
    required String extension,
  }) async => null;

  Completer<String?> result = Completer<String?>();
  @override
  Future<String?> chooseDirectory({required bool canCreateDirectories}) =>
      result.future;
  @override
  Future<String?> choosePatchFile() async => null;
}

final class _MemoryViewCacheRepository implements PrivateEntryStore {
  final Map<NativePathIdentity, Uint8List> entries = {};
  final List<NativePathIdentity> removed = [];
  bool failing = false;

  @override
  Future<Uint8List?> read(NativePathIdentity repository) async {
    if (failing) throw StateError('view_cache_unavailable');
    return entries[repository];
  }

  @override
  Future<void> write(NativePathIdentity repository, Uint8List bytes) async {
    if (failing) throw StateError('view_cache_unavailable');
    entries[repository] = bytes;
  }

  @override
  Future<void> remove(NativePathIdentity repository) async {
    removed.add(repository);
    entries.remove(repository);
  }
}
