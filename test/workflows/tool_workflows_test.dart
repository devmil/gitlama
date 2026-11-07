import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/history.dart';
import 'package:gitlama/models/history_graph.dart';
import 'package:gitlama/models/host_platform.dart';
import 'package:gitlama/models/index_lock.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/patch.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/services/workflows/index_lock_workflow.dart';
import 'package:gitlama/services/workflows/integration_launcher.dart';
import 'package:gitlama/services/workflows/patch_request_builder.dart';
import 'package:gitlama/services/workflows/window_workflows.dart';

import '../support/fake_settings_repository.dart';
import '../support/recording_interaction.dart';
import '../support/workflow_fake_repository.dart';

final _root = NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: '/repository'.codeUnits,
);

RepositorySnapshot _snapshot({bool identity = true}) => RepositorySnapshot(
  revision: BigInt.one,
  phase: RepositoryPhase.ready,
  identity: !identity
      ? null
      : RepositoryIdentity(
          commonGitDir: _root,
          worktreeRoot: _root,
          gitDir: _root,
          kind: RepositoryKind.worktree,
          headKind: HeadKind.attached,
          gitMajor: 2,
          gitMinor: 50,
          gitPatch: 1,
        ),
  status: RepositoryStatus(
    workingTree: WorkingTreeState.clean,
    branchName: 'main'.codeUnits,
    headObjectId: '1' * 40,
    ahead: BigInt.zero,
    behind: BigInt.zero,
    entries: const [],
    totalEntries: BigInt.zero,
    entriesTruncated: false,
    operations: const [],
  ),
);

NativePathIdentity _path(String value) => NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: value.codeUnits,
);

void main() {
  late WorkflowFakeRepository repository;
  late SettingsService settings;
  late RepositorySessionService repositories;
  late WindowWorkflows workflows;
  late RecordingInteraction interaction;

  Future<void> open({
    HostPlatform platform = HostPlatform.linux,
    bool identity = true,
  }) async {
    repository = WorkflowFakeRepository(_snapshot(identity: identity));
    settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    repositories = RepositorySessionService(repository, settings);
    await repositories.open('/repository');
    workflows = WindowWorkflows(
      repositories: repositories,
      operationCenter: OperationCenterService.empty(),
      platform: platform,
    );
    interaction = RecordingInteraction();
  }

  tearDown(() async {
    await workflows.dispose();
    await repositories.dispose();
  });

  Future<void> configure(IntegrationDefinition definition) => settings
      .saveDurable(settings.current.copyWith(integrations: [definition]));

  group('integrations', () {
    // Moved from home_screen_test: 'editor launch without confirmation
    // returns to the workspace'.
    test('a configured editor without confirmation runs at once', () async {
      await open();
      await configure(
        IntegrationDefinition(
          id: 'Editor fixture',
          kind: IntegrationKind.editor,
          executable: _path('/editor'),
          arguments: const ['{file}'],
        ),
      );
      await workflows.integrations.open(interaction, IntegrationKind.editor);
      expect(repository.calls, ['executeIntegration']);
      expect(interaction.log, isEmpty);
      final request = repository.integrationRequests.single;
      expect(request.configured?.id, 'Editor fixture');
      expect(request.variables.file?.units, '/repository'.codeUnits);
      expect(request.variables.currentBranch, 'main'.codeUnits);
      expect(request.variables.selectedCommit, '1' * 40);
    });

    test('a command that asks first runs only once confirmed', () async {
      await open();
      await configure(
        IntegrationDefinition(
          id: 'Editor fixture',
          kind: IntegrationKind.editor,
          executable: _path('/editor'),
          arguments: const ['{file}'],
          requiresConfirmation: true,
        ),
      );
      repository.integrationRequiresConfirmation = true;
      interaction.confirmIntegrationAnswer = false;
      await workflows.integrations.open(interaction, IntegrationKind.editor);
      expect(repository.calls, isEmpty);
      expect(repository.integrationCancels, 1);
      interaction.confirmIntegrationAnswer = true;
      await workflows.integrations.open(interaction, IntegrationKind.editor);
      expect(repository.calls, ['executeIntegration']);
    });

    test('without a tool the window hears it is unavailable', () async {
      await open();
      await workflows.integrations.open(interaction, IntegrationKind.terminal);
      expect(interaction.outcomes.single, isA<IntegrationUnavailable>());
    });

    test('a failed launch is reported', () async {
      await open();
      repository
        ..candidates = [
          IntegrationCandidate(
            id: 'code',
            kind: IntegrationKind.editor,
            executable: _path('/code'),
            launchMode: IntegrationLaunchMode.detached,
          ),
        ]
        ..integrationState = IntegrationExecutionState.failed;
      await workflows.integrations.open(interaction, IntegrationKind.editor);
      expect(repository.integrationRequests.single.discoveredId, 'code');
      expect(interaction.outcomes.single, isA<IntegrationLaunchFailed>());
    });

    test(
      'a file manager selects a file where it can, else opens its folder',
      () async {
        for (final (platform, id, arguments, file) in [
          (
            HostPlatform.macOS,
            'finder',
            ['-R', '{file}'],
            '/repository/a/b.txt',
          ),
          (
            HostPlatform.windows,
            'explorer',
            ['/select,{file}'],
            '/repository/a/b.txt',
          ),
          (
            HostPlatform.linux,
            'org.kde.dolphin',
            ['--select', '{file}'],
            '/repository/a/b.txt',
          ),
          (HostPlatform.linux, 'xdg-open', ['{file}'], '/repository/a'),
        ]) {
          await open(platform: platform);
          repository.candidates = [
            IntegrationCandidate(
              id: id,
              kind: IntegrationKind.fileManager,
              executable: _path('/tool'),
              launchMode: IntegrationLaunchMode.detached,
            ),
          ];
          await workflows.integrations.open(
            interaction,
            IntegrationKind.fileManager,
            file: _path('a/b.txt'),
          );
          final request = repository.integrationRequests.single;
          expect(request.configured?.arguments, arguments, reason: id);
          expect(request.discoveredId, isNull);
          expect(String.fromCharCodes(request.variables.file!.units), file);
          await workflows.dispose();
          await repositories.dispose();
        }
        await open();
      },
    );

    test('an editor opens a file with the platform arguments', () {
      expect(
        IntegrationLauncher.fileArguments(
          IntegrationKind.editor,
          'code',
          HostPlatform.macOS,
        ),
        ['-t', '{file}'],
      );
      expect(
        IntegrationLauncher.fileArguments(
          IntegrationKind.editor,
          'code',
          HostPlatform.windows,
        ),
        ['{file}'],
      );
      expect(IntegrationLauncher.folderArguments('nautilus-gio'), [
        'open',
        '{file}',
      ]);
      expect(IntegrationLauncher.folderArguments('nautilus'), ['{file}']);
    });

    test('a folder on another computer is never opened here', () async {
      await open();
      await workflows.integrations.openFolder(
        interaction,
        NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: '/remote'.codeUnits,
          remote: const RemoteAuthority(
            profileId: 'host',
            storeId: 'store',
            accountUid: '1000',
          ),
        ),
      );
      expect(
        (interaction.outcomes.single as IntegrationRefused).reason,
        AppCommandDisabledReason.remoteUnsupported,
      );
      expect(repository.integrationRequests, isEmpty);
    });
  });

  group('index lock', () {
    test('a present lock is removed once confirmed', () async {
      await open();
      repository.indexLock = IndexLockInspection(
        present: true,
        token: BigInt.from(77),
        sizeBytes: BigInt.from(14),
      );
      await workflows.indexLock.run(interaction);
      expect(interaction.log, [
        'confirmIndexLock:14',
        'indexLock:IndexLockRemoved',
      ]);
      expect(repository.removedIndexLockToken, BigInt.from(77));
    });

    test('a missing, declined or changed lock removes nothing', () async {
      await open();
      await workflows.indexLock.run(interaction);
      expect(interaction.outcomes.single, isA<IndexLockNotFound>());
      repository.indexLock = IndexLockInspection(
        present: true,
        token: BigInt.from(77),
        sizeBytes: BigInt.from(14),
      );
      interaction.removeLock = false;
      await workflows.indexLock.run(interaction);
      expect(repository.removedIndexLockToken, isNull);
      interaction.removeLock = true;
      repository.removeIndexLockError = const IndexLockException(
        IndexLockFailureCode.changed,
      );
      await workflows.indexLock.run(interaction);
      expect(
        (interaction.outcomes.last as IndexLockRefused).code,
        IndexLockFailureCode.changed,
      );
    });
  });

  group('patch requests', () {
    HistoryPage page({
      List<String> selected = const [],
      String? oldId,
      String? newId,
    }) => HistoryPage(
      requestId: BigInt.one,
      complete: true,
      totalRows: 3,
      offset: 0,
      rows: [
        for (final id in ['c', 'b', 'a'])
          HistoryTopologyRow(
            objectId: id,
            parents: const [],
            refs: const [],
            lane: 0,
            shape: HistoryNodeShape.commit.index,
          ),
      ],
      laneCount: 1,
      payloadBytes: 0,
      selectedObjectIds: selected,
      comparisonOldObjectId: oldId,
      comparisonNewObjectId: newId,
    );

    test('History exports what it shows', () {
      final none = PatchRequestBuilder.history(page())('/out', false);
      expect(none.workspaceDefault, isTrue);
      final one = PatchRequestBuilder.history(page(selected: ['b']))(
        '/out',
        true,
      );
      expect(one.commit, 'b');
      expect(one.overwrite, isTrue);
      // A range runs oldest first in graph order, whatever the click order.
      final range = PatchRequestBuilder.history(page(selected: ['a', 'c']))(
        '/out',
        false,
      );
      expect(range.rangeCommits, ['a', 'c']);
      final compared = PatchRequestBuilder.history(
        page(selected: ['a', 'c'], oldId: 'a', newId: 'c'),
      )('/out', false);
      expect(compared.comparisonOld, 'a');
      expect(compared.comparisonNew, 'c');
      expect(compared.rangeCommits, isEmpty);
      final forced = PatchRequestBuilder.history(
        page(oldId: 'a', newId: 'c'),
        commit: 'b',
      )('/out', false);
      expect(forced.commit, 'b');
      expect(forced.comparisonOld, isNull);
    });

    test('a diff exports its commit or comparison, limited to paths', () {
      final commit = PatchRequestBuilder.diff(const CommitTarget('c'), [
        [1],
      ])('/out', false);
      expect(commit.commit, 'c');
      expect(commit.historyPaths, [
        [1],
      ]);
      final comparison = PatchRequestBuilder.diff(
        const ComparisonTarget(base: 'a', commit: 'c'),
        const [],
      )('/out', false);
      expect(comparison.comparisonOld, 'a');
      expect(comparison.comparisonNew, 'c');
      expect(comparison.commit, isNull);
    });

    test('working-tree patches take lines, selected files or a side', () {
      final side = PatchRequestBuilder.workingTree(side: StagingSide.staged)(
        '/out',
        false,
      );
      expect(side.focusedSide, PatchSide.staged);
      expect(side.selectedSide, isNull);
      final files = PatchRequestBuilder.workingTree(
        side: StagingSide.unstaged,
        paths: const [
          [1],
        ],
      )('/out', false);
      expect(files.selectedSide, PatchSide.unstaged);
      expect(files.focusedSide, isNull);
      final lines = PatchRequestBuilder.workingTree(
        side: StagingSide.unstaged,
        accepted: DiffPage(
          requestId: BigInt.from(5),
          layout: DiffViewLayout.unified,
          totalRows: 0,
          offset: 0,
          rows: const [],
          payloadBytes: 0,
        ),
        rowIds: const ['r1'],
      )('/out', false);
      expect(lines.workingDiffRequestId, BigInt.from(5));
      expect(lines.rowIds, ['r1']);
      expect(lines.focusedSide, isNull);
    });
  });

  group('navigation', () {
    test('a pane switch loads History or clears its selection', () async {
      await open();
      workflows.navigator.selectPane(WorkspacePane.history);
      expect(repositories.activeTab?.navigation.pane, WorkspacePane.history);
      workflows.navigator.nextPane();
      expect(repositories.activeTab?.navigation.pane, WorkspacePane.changes);
    });

    test('another tab only remembers its pane', () async {
      // Without an identity each path opens its own tab.
      await open(identity: false);
      final first = repositories.activeTabId!;
      await repositories.open('/second');
      workflows.navigator.selectPane(WorkspacePane.history, tabId: first);
      final tab = repositories.workspace.tabs.firstWhere(
        (tab) => tab.id == first,
      );
      expect(tab.navigation.pane, WorkspacePane.history);
      expect(repositories.activeTabId, isNot(first));
    });

    test('showing a commit selects it in History', () async {
      await open();
      await workflows.navigator.showCommit('abc');
      final navigation = repositories.activeTab!.navigation;
      expect(navigation.pane, WorkspacePane.history);
      expect(navigation.selectedIdentity, 'abc');
      expect(await workflows.navigator.compareSelected(), isFalse);
    });
  });
}
