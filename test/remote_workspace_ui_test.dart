import 'package:gitlama/services/cli_forwarding_service.dart';
import 'package:gitlama/models/cli_forwarding.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_runtime.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/home_screen.dart';
import 'package:gitlama/app/inspector/inspector_view.dart';
import 'package:gitlama/app/inspector/pane_inspector_host.dart';
import 'package:gitlama/app/workspace/command_availability.dart';
import 'package:gitlama/app/workspace/command_palette.dart';
import 'package:gitlama/app/workspace/remote_directory_picker.dart';
import 'package:gitlama/app/workspace/remote_host_dialog.dart';
import 'package:gitlama/app/workspace/remote_operations.dart';
import 'package:gitlama/app/workspace/remote_workspace.dart';
import 'package:gitlama/app/workspace/settings_dialog.dart';
import 'package:gitlama/app/workspace/status_bar.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/app_shortcut.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/inspector_reveal.dart';
import 'package:gitlama/models/remote_command_policy.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_extensions.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/repositories/inspection_window_repository.dart';
import 'package:gitlama/services/inspection_window_service.dart';
import 'package:gitlama/services/inspector/inspector_service.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/remote_workspace_service.dart';
import 'package:gitlama/repositories/impl/repository_backend_router.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/services/workflows/workspace_navigator.dart';
import 'package:gitlama/widgets/git_file_list/git_file_list.dart';
import 'package:gitlama/widgets/status_notification.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'support/inert_runtime.dart';
import 'support/fake_recovery_repository.dart';
import 'support/fake_remote_workspace.dart';
import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

const _writesOff = 'Turn on Allow changes on this host to use this';

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: StatusNotificationScope(child: child!),
  ),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildAppTheme(Brightness.light),
  home: home,
);

/// A window with one button that runs [open] and records its result.
Widget _launcher(
  Future<Object?> Function(BuildContext context) open, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => _app(
  locale: locale,
  textScale: textScale,
  Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: MeridianButton(
          key: const ValueKey('launch'),
          label: 'Launch',
          onPressed: () => unawaited(open(context)),
        ),
      ),
    ),
  ),
);

Future<SettingsService> _settings() async {
  final settings = fakeSettingsService();
  await settings.initialize();
  return settings;
}

/// A desktop-sized window, so dialogs and the workspace fit.
void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _field(Key key) => find.byKey(key);

/// The folder the remote picker shows.
String? _currentFolder(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('remote-directory-current')))
    .data;

RepositorySnapshot _snapshot({bool staged = false, bool unstaged = false}) =>
    RepositorySnapshot(
      revision: BigInt.one,
      phase: RepositoryPhase.ready,
      status: RepositoryStatus(
        workingTree: staged || unstaged
            ? WorkingTreeState.dirty
            : WorkingTreeState.clean,
        headObjectId: '1111111111111111111111111111111111111111',
        branchName: 'main'.codeUnits,
        ahead: BigInt.zero,
        behind: BigInt.zero,
        entries: [
          if (staged)
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'README.md'.codeUnits,
              ),
              index: ChangeKind.modified,
              worktree: ChangeKind.unmodified,
            ),
          if (unstaged)
            RepositoryStatusEntry(
              kind: StatusEntryKind.ordinary,
              path: NativePathIdentity(
                platform: NativePathPlatform.unix,
                units: 'notes.txt'.codeUnits,
              ),
              index: ChangeKind.unmodified,
              worktree: ChangeKind.modified,
            ),
        ],
        totalEntries: BigInt.from((staged ? 1 : 0) + (unstaged ? 1 : 0)),
        entriesTruncated: false,
        operations: [],
      ),
    );

final class _Window {
  _Window(this.settings, this.remote, this.repositories, this.runtime);

  final SettingsService settings;
  final FakeRemoteWorkspace remote;
  final RepositorySessionService repositories;
  final AppRuntime runtime;

  RemoteWorkspaceService get service => remote.service;

  /// Unmounts the window and stops every service and timer it started.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await repositories.dispose();
    await remote.service.dispose();
    await runtime.operationCenter.dispose();
    await settings.dispose();
    await tester.pump(const Duration(seconds: 1));
  }
}

/// A whole window over a real remote workspace service and its fakes.
Future<_Window> _window({
  bool staged = false,
  bool unstaged = false,
  Object? executeCommitError,
  Object? executeDiscardError,
  FakeRemotePending? pending,
  bool routed = false,
  CliForwardingController cli = const DisabledCliForwardingController(),
}) async {
  final settings = await _settings();
  final remote = FakeRemoteWorkspace(settings, pending: pending);
  await remote.service.initialize();
  final local = fakeRepositorySessionRepository(
    snapshot: _snapshot(staged: staged, unstaged: unstaged),
    executeCommitError: executeCommitError,
    executeDiscardError: executeDiscardError,
  );
  final repositories = RepositorySessionService(
    // The production router sends remote identities to their connection.
    routed ? RepositoryBackendRouter(local, remote.directory) : local,
    settings,
    null,
    null,
    null,
    remote.service,
  );
  await repositories.restoreWorkspace();
  final operations = OperationCenterService.empty();
  final runtime = testRuntime(
    repositorySessions: repositories,
    remoteWorkspaces: remote.service,
    settings: settings,
    recovery: fakeRecoveryService(settings),
    operationCenter: operations,
    shutdown: () async {},
    cliForwarding: cli,
  );
  return _Window(settings, remote, repositories, runtime);
}

Future<RemoteHostProfile> _connectedProfile(
  RemoteWorkspaceService service, {
  bool writes = false,
}) async {
  var profile = await service.saveProfile(
    label: 'Workstation',
    alias: 'devbox',
  );
  expect((await service.connect(profile.id)).ready, isTrue);
  if (writes) {
    await service.setWritesAllowed(profile.id, true);
    await service.disconnect(profile.id);
    expect((await service.connect(profile.id)).ready, isTrue);
  }
  profile = service.profile(profile.id)!;
  return profile;
}

const _helper = RemoteHelperArtifact(
  buildId: '0123456789abcdef0123456789abcdef01234567',
  target: RemoteHelperTarget.linuxX86_64,
  sha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
  bytes: [1, 2, 3],
);

/// Records the inspector windows the shell opens.
final class _RecordingWindows implements InspectionWindowRepository {
  final List<InspectionWindowRequest> opened = [];

  @override
  Future<void> open(InspectionWindowRequest request) async =>
      opened.add(request);
}

Future<void> _openRemoteTab(_Window window, RemoteHostProfile profile) async {
  await window.repositories.openRemoteRepository(
    profile.authority!,
    utf8.encode('/home/me/project'),
  );
}

void main() {
  group('policy', () {
    test('every command has one remote classification', () {
      const connected = RemoteTabAccess(profileId: 'p', connected: true);
      const writes = RemoteTabAccess(
        profileId: 'p',
        connected: true,
        capabilities: remoteWriteCapabilities,
      );
      // An older negotiation without ref, stash and transfer writes.
      const commitsOnly = RemoteTabAccess(
        profileId: 'p',
        connected: true,
        capabilities: {RemoteCapability.stage, RemoteCapability.commit},
      );
      const stale = RemoteTabAccess(
        profileId: 'p',
        connected: false,
        capabilities: {RemoteCapability.stage, RemoteCapability.commit},
      );
      for (final id in AppCommandId.values) {
        expect(remoteCommandReason(id, null), isNull, reason: id.name);
      }
      for (final id in [
        AppCommandId.createBranch,
        AppCommandId.checkoutBranch,
        AppCommandId.deleteTag,
        AppCommandId.addRemote,
        AppCommandId.createStash,
        AppCommandId.popStash,
        AppCommandId.fetch,
        AppCommandId.pull,
        AppCommandId.push,
        AppCommandId.deleteRemoteBranch,
        AppCommandId.renameRemote,
        AppCommandId.discardChanges,
        // Families added later: history, recovery and extensions.
        AppCommandId.resetBranch,
        AppCommandId.mergeBranch,
        AppCommandId.cherryPickSelected,
        AppCommandId.revertSelected,
        AppCommandId.interactiveRebase,
        AppCommandId.rebaseContinue,
        AppCommandId.conflictTakeIncoming,
        AppCommandId.applyPatch,
        AppCommandId.addWorktree,
        AppCommandId.trackLfsPattern,
      ]) {
        expect(remoteCommandReason(id, writes), isNull, reason: id.name);
        expect(
          remoteCommandReason(id, commitsOnly),
          AppCommandDisabledReason.remoteWritesUnavailable,
          reason: id.name,
        );
        expect(
          remoteCommandReason(id, connected),
          AppCommandDisabledReason.remoteWritesUnavailable,
          reason: id.name,
        );
      }
      // Local file-based tools and resending an uncertain write.
      for (final id in [
        AppCommandId.openInTerminal,
        AppCommandId.openInEditor,
        AppCommandId.conflictOpenExternal,
        AppCommandId.activityRetry,
      ]) {
        expect(
          remoteCommandReason(id, writes),
          AppCommandDisabledReason.remoteUnsupported,
          reason: id.name,
        );
      }
      // Provider requests and browser handoff use local accounts and received
      // metadata, independently of the SSH connection or host write access.
      for (final id in [
        AppCommandId.showIntegrations,
        AppCommandId.hostingCreatePullRequest,
      ]) {
        for (final access in [connected, writes, commitsOnly, stale]) {
          expect(remoteCommandReason(id, access), isNull, reason: id.name);
        }
      }
      // A patch is built and a rendered diff read on the host and finished
      // here: they need only a live connection.
      for (final id in [
        AppCommandId.createPatch,
        AppCommandId.patch,
        AppCommandId.diffRenderConfigured,
        // An inspector window reads through this window's connection.
        AppCommandId.inspectorOpenInWindow,
        // Panels that read the host; their actions check their families.
        AppCommandId.showPowerTools,
        AppCommandId.showSnapshots,
      ]) {
        expect(remoteCommandReason(id, connected), isNull, reason: id.name);
        expect(
          remoteCommandReason(id, stale),
          AppCommandDisabledReason.remoteDisconnected,
          reason: id.name,
        );
      }
      // Without writes this side says why; a write it asked for but the host
      // did not offer is the host's decision.
      for (final (block, reason) in [
        (RemoteWriteBlock.notAllowed, AppCommandDisabledReason.remoteWritesOff),
        (
          RemoteWriteBlock.reconnect,
          AppCommandDisabledReason.remoteWritesReconnect,
        ),
        (
          RemoteWriteBlock.ledgerUnavailable,
          AppCommandDisabledReason.remoteWritesLedger,
        ),
      ]) {
        expect(
          remoteCommandReason(
            AppCommandId.push,
            RemoteTabAccess(profileId: 'p', connected: true, writeBlock: block),
          ),
          reason,
          reason: block.name,
        );
      }
      expect(remoteCommandReason(AppCommandId.historyBlame, stale), isNull);
      expect(
        remoteCommandReason(AppCommandId.refreshRepository, stale),
        AppCommandDisabledReason.remoteDisconnected,
      );
      expect(
        remoteCommandReason(AppCommandId.stageSelection, connected),
        AppCommandDisabledReason.remoteWritesUnavailable,
      );
      expect(remoteCommandReason(AppCommandId.stageSelection, writes), isNull);
      expect(remoteCommandReason(AppCommandId.commitCreate, writes), isNull);
      // An amend is a commit on the host.
      expect(
        remoteCommandReason(AppCommandId.commitAmend, commitsOnly),
        isNull,
      );
      expect(
        remoteCommandReason(AppCommandId.commitCreate, stale),
        AppCommandDisabledReason.remoteDisconnected,
      );
    });

    test('typed remote paths are absolute UTF-8 POSIX paths only', () {
      expect(parseRemotePathInput('').error, RemotePathInputError.empty);
      expect(
        parseRemotePathInput('~/project').error,
        RemotePathInputError.notAbsolute,
      );
      expect(
        parseRemotePathInput('project').error,
        RemotePathInputError.notAbsolute,
      );
      expect(
        parseRemotePathInput('/srv/a\u0000b').error,
        RemotePathInputError.invalid,
      );
      expect(
        parseRemotePathInput('/${'x' * remotePathByteCapacity}').error,
        RemotePathInputError.invalid,
      );
      expect(parseRemotePathInput('/srv/ünï').path, utf8.encode('/srv/ünï'));
      expect(
        remoteChildPath(utf8.encode('/'), utf8.encode('home')),
        utf8.encode('/home'),
      );
      expect(
        remoteChildPath(utf8.encode('/home'), utf8.encode('me')),
        utf8.encode('/home/me'),
      );
    });
  });

  test('paths inside a remote repository stay on its computer', () {
    const authority = RemoteAuthority(
      profileId: '00000000-0000-4000-8000-000000000000',
      storeId: fakeStoreA,
      accountUid: '1000',
    );
    final root = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: utf8.encode('/home/me/project'),
      remote: authority,
    );
    final relative = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: utf8.encode('src/main.dart'),
    );
    final file = repositoryFileIdentity(root, relative);
    expect(utf8.decode(file.units), '/home/me/project/src/main.dart');
    expect(file.remote, authority);
    final absolute = repositoryFileIdentity(
      root,
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: utf8.encode('/etc/hosts'),
      ),
    );
    expect(absolute.remote, authority);
    expect(parentNativePath(file).remote, authority);
    expect(directoryNativePath(file, 'home/me').remote, authority);
    // A local repository keeps local paths.
    final local = repositoryFileIdentity(
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: utf8.encode('/work'),
      ),
      relative,
    );
    expect(local.isRemote, isFalse);
  });

  group('experimental setting', () {
    testWidgets('remote entry points are always offered', (tester) async {
      _desktop(tester);
      final window = await _window();
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      expect(find.byKey(const ValueKey('welcome-open-remote')), findsOneWidget);
      await tester.pumpWidget(
        _app(
          const CommandPaletteDialog(
            hasRepository: false,
            disabledSelectionCommands: {},
            shortcuts: {},
            activeScopes: {AppCommandShortcutScope.global},
            customCommands: [],
            availability: CommandMenuState(),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Open Remote Repository…'), findsOneWidget);
      await window.close(tester);
    });
  });

  group('host dialog', () {
    testWidgets('validates profiles and explains connection failures', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      remote.connections.results.addAll([
        RemoteFailureCode.sshConnectionFailed,
        RemoteFailureCode.helperNotInstalled,
      ]);
      final applied = <String>[];
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(
            context,
            service: remote.service,
            onAccessChanged: (profileId) async => applied.add(profileId),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-hosts-empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('remote-add-host')));
      await _settle(tester);
      await tester.enterText(
        _field(const ValueKey('remote-host-label')),
        'Workstation',
      );
      await tester.enterText(
        _field(const ValueKey('remote-host-alias')),
        'me@@devbox',
      );
      await tester.pump();
      expect(find.textContaining('Ports and options'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('remote-host-save')));
      await _settle(tester);
      expect(remote.service.profiles, isEmpty);

      await tester.enterText(
        _field(const ValueKey('remote-host-alias')),
        'devbox',
      );
      await _settle(tester);
      expect(find.textContaining('Ports and options'), findsNothing);
      expect(find.textContaining('never asks for passwords'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('remote-host-save')));
      await _settle(tester);
      final profile = remote.service.profiles.single;
      expect(profile.label, 'Workstation');
      expect(profile.alias, 'devbox');
      expect(find.text('Workstation'), findsOneWidget);
      expect(find.text('Not connected'), findsWidgets);

      // Access can be chosen before the first connection; it applies to the
      // account that connection verifies.
      expect(find.text('Read only'), findsOneWidget);
      await tester.tap(find.text('Allow changes'));
      await _settle(tester);
      expect(remote.service.profiles.single.writesAllowed, isTrue);
      expect(
        find.text(
          'Applies to the account GitLama verifies when it first connects.',
        ),
        findsOneWidget,
      );
      // Nothing is live, so nothing reconnects.
      expect(applied, isEmpty);

      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(find.textContaining('ssh devbox works in a terminal'), findsOne);

      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(find.textContaining('helper for this version'), findsOneWidget);
      expect(
        find.text(
          '~/.local/lib/gitlama/remote/'
          '0123456789abcdef0123456789abcdef01234567/gitlama-remote-helper',
        ),
        findsOneWidget,
      );

      // The next attempt succeeds and verifies the account.
      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(find.text('Connected'), findsWidgets);
      expect(find.text('Verified account: me'), findsOneWidget);
      // A live connection applies a changed choice at once.
      await tester.tap(find.text('Read only'));
      await _settle(tester);
      expect(remote.service.profiles.single.writesAllowed, isFalse);
      expect(applied, [profile.id]);
      await remote.service.dispose();
    });

    testWidgets('a new host gets the server icon and a colour of its own', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      await remote.service.saveProfile(
        label: 'First',
        alias: 'first',
        color: 'blue',
        icon: 'server',
      );
      await tester.pumpWidget(
        _launcher(
          (context) => showMeridianDialog<RemoteHostProfile>(
            context: context,
            builder: (context) => RemoteProfileEditor(service: remote.service),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-host-appearance')), findsOne);
      await tester.enterText(
        _field(const ValueKey('remote-host-label')),
        'Second',
      );
      await tester.enterText(
        _field(const ValueKey('remote-host-alias')),
        'second',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-host-save')));
      await _settle(tester);
      final second = remote.service.profiles.firstWhere(
        (profile) => profile.label == 'Second',
      );
      expect(second.icon, 'server');
      expect(second.color, isNotNull);
      expect(second.color, isNot('blue'));
      await remote.service.dispose();
    });

    testWidgets('a failed host save names its cause and a stable code', (
      tester,
    ) async {
      _desktop(tester);
      final repository = FakeSettingsRepository();
      final settings = SettingsService(repository);
      await settings.initialize();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(context, service: remote.service),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-add-host')));
      await _settle(tester);
      await tester.enterText(
        _field(const ValueKey('remote-host-label')),
        'Fedora',
      );
      await tester.enterText(
        _field(const ValueKey('remote-host-alias')),
        'fedora',
      );
      for (final (failure, reason, code) in [
        (
          const SettingsException(SettingsFailureCode.locked),
          'another GitLama process was writing it',
          'settings_locked',
        ),
        (
          const SettingsException(SettingsFailureCode.io),
          'could not write its settings file',
          'settings_io',
        ),
        (
          const SettingsException(
            SettingsFailureCode.invalidDocument,
            rule: 'remote_profiles',
          ),
          'settings check rejected this change',
          'settings_invalidDocument_remote_profiles',
        ),
      ]) {
        repository.saveFailure = failure;
        await tester.tap(find.byKey(const ValueKey('remote-host-save')));
        await _settle(tester);
        expect(find.textContaining(reason), findsOneWidget);
        expect(find.textContaining('Error code: $code'), findsOneWidget);
        expect(remote.service.profiles, isEmpty);
      }

      repository.saveFailure = null;
      await tester.tap(find.byKey(const ValueKey('remote-host-save')));
      await _settle(tester);
      expect(remote.service.profiles.single.alias, 'fedora');
      await remote.service.dispose();
    });

    testWidgets('a missing helper is installed only after confirmation', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      await remote.service.saveProfile(label: 'Workstation', alias: 'devbox');
      remote.connections
        ..helper = const RemoteHelperArtifact(
          buildId: '0123456789abcdef0123456789abcdef01234567',
          target: RemoteHelperTarget.linuxX86_64,
          sha256:
              '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
          bytes: [1, 2, 3],
        )
        ..results.add(RemoteFailureCode.helperNotInstalled)
        ..installResults.add(RemoteFailureCode.installExecute);
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(context, service: remote.service),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('remote-helper-location')),
        findsNothing,
      );

      // Declining the confirmation copies nothing.
      await tester.tap(find.byKey(const ValueKey('remote-install-helper')));
      await _settle(tester);
      expect(find.text('Install the helper on Workstation?'), findsOneWidget);
      expect(
        find.text(
          '~/.local/lib/gitlama/remote/'
          '0123456789abcdef0123456789abcdef01234567/gitlama-remote-helper',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('SHA-256: 9f86d0'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await _settle(tester);
      expect(remote.connections.installs, isEmpty);

      // A failed install explains itself and offers another attempt.
      await tester.tap(find.byKey(const ValueKey('remote-install-helper')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-install-confirm')));
      await _settle(tester);
      expect(remote.connections.installs, ['devbox']);
      expect(find.textContaining('could not run on the host'), findsOneWidget);

      // The next install shows its progress, then connects.
      remote.connections.installGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('remote-install-helper')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-install-confirm')));
      await _settle(tester);
      expect(find.text('Installing the GitLama helper…'), findsWidgets);
      expect(
        find.byKey(const ValueKey('remote-cancel-connect')),
        findsOneWidget,
      );
      remote.connections.installGate!.complete();
      await _settle(tester);
      expect(find.text('Connected'), findsWidgets);
      expect(remote.connections.opens, 2);
      await remote.service.dispose();
    });

    testWidgets('a Mac host is offered the Mac helper, never another', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await remote.service.saveProfile(
        label: 'Studio',
        alias: 'studio',
      );
      remote.connections
        ..hostTarget = RemoteHelperTarget.macosArm64
        ..helper = const RemoteHelperArtifact(
          buildId: '0123456789abcdef0123456789abcdef01234567',
          target: RemoteHelperTarget.linuxX86_64,
          sha256:
              '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
          bytes: [1, 2, 3],
        )
        ..results.addAll([
          RemoteFailureCode.helperNotInstalled,
          RemoteFailureCode.helperNotInstalled,
        ]);
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(context, service: remote.service),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(
        remote.service.hostTarget(profile.id),
        RemoteHelperTarget.macosArm64,
      );
      // Only a Linux helper is bundled: the location is explained instead.
      expect(find.byKey(const ValueKey('remote-install-helper')), findsNothing);
      expect(
        find.byKey(const ValueKey('remote-helper-location')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());

      // With the Mac helper bundled, it is offered.
      remote.connections.helper = const RemoteHelperArtifact(
        buildId: '0123456789abcdef0123456789abcdef01234567',
        target: RemoteHelperTarget.macosArm64,
        sha256:
            '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
        bytes: [1, 2, 3],
      );
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(context, service: remote.service),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('remote-install-helper')),
        findsOneWidget,
      );
      await remote.service.dispose();
    });

    testWidgets('canceling an install leaves the host disconnected', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await remote.service.saveProfile(
        label: 'Workstation',
        alias: 'devbox',
      );
      remote.connections.installGate = Completer<void>();
      final installing = remote.service.installHelper(
        profile.id,
        const RemoteHelperArtifact(
          buildId: '0123456789abcdef0123456789abcdef01234567',
          target: RemoteHelperTarget.linuxX86_64,
          sha256:
              '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
          bytes: [1],
        ),
      );
      expect(
        remote.service.state(profile.id).phase,
        RemoteConnectionPhase.installing,
      );
      // A concurrent connect joins the install instead of racing it.
      expect(remote.service.connect(profile.id), same(installing));
      remote.service.cancel(profile.id);
      final result = await installing;
      expect(result.phase, RemoteConnectionPhase.idle);
      expect(result.failure, isNull);
      expect(remote.connections.opens, 0);
      await remote.service.dispose();
    });

    testWidgets('a connection in progress shows its phase and cancels', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      await remote.service.saveProfile(label: 'Workstation', alias: 'devbox');
      remote.connections.gate = Completer<void>();
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(context, service: remote.service),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-connect')));
      await _settle(tester);
      expect(find.text('Connecting through SSH…'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('remote-cancel-connect')));
      await _settle(tester);
      expect(find.text('Not connected'), findsWidgets);
      expect(find.byKey(const ValueKey('remote-host-failure')), findsNothing);
      await remote.service.dispose();
    });

    testWidgets('a changed identity is trusted only explicitly', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service, writes: true);
      expect(remote.service.profile(profile.id)!.writesAllowed, isTrue);
      await remote.service.disconnect(profile.id);
      remote.connections.results.addAll([
        const FakeHello(storeId: fakeStoreB, accountName: 'other'),
        const FakeHello(storeId: fakeStoreB, accountName: 'other'),
      ]);
      expect(
        (await remote.service.connect(profile.id)).phase,
        RemoteConnectionPhase.identityChanged,
      );
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(
            context,
            service: remote.service,
            initialProfileId: profile.id,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('remote-identity-changed')),
        findsOneWidget,
      );
      expect(find.textContaining('account other'), findsOneWidget);
      // Nothing changed without a decision.
      expect(remote.service.profile(profile.id)!.verified!.storeId, fakeStoreA);
      await tester.tap(find.byKey(const ValueKey('remote-trust-identity')));
      await _settle(tester);
      final rebound = remote.service.profile(profile.id)!;
      expect(rebound.verified!.storeId, fakeStoreB);
      expect(rebound.writesAllowed, isFalse);
      expect(remote.service.state(profile.id).ready, isTrue);
      expect(
        find.byKey(const ValueKey('remote-identity-changed')),
        findsNothing,
      );
      await remote.service.dispose();
    });

    testWidgets('deleting a host asks first and keeps everything else', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      await remote.service.saveProfile(label: 'Workstation', alias: 'devbox');
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(context, service: remote.service),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-delete-host')));
      await _settle(tester);
      expect(find.textContaining('removes only the host profile'), findsOne);
      await tester.tap(find.widgetWithText(MeridianButton, 'Delete host').last);
      await _settle(tester);
      expect(remote.service.profiles, isEmpty);
      await remote.service.dispose();
    });
  });

  group('helper installation', () {
    test('a host left to GitLama gets its helper once per attempt', () async {
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final service = remote.service;
      final profile = await service.saveProfile(label: 'Box', alias: 'devbox');
      remote.connections.helper = _helper;

      // Asked by default: the failure is reported, nothing is copied.
      remote.connections.results.add(RemoteFailureCode.helperNotInstalled);
      final asked = await service.connect(profile.id);
      expect(asked.failure, RemoteFailureCode.helperNotInstalled);
      expect(remote.connections.installs, isEmpty);
      expect(await service.installableHelper(profile.id), same(_helper));

      await service.setAutoInstallHelper(profile.id, true);
      remote.connections.results.add(RemoteFailureCode.helperNotInstalled);
      expect((await service.connect(profile.id)).ready, isTrue);
      expect(remote.connections.installs, ['devbox']);
      await service.disconnect(profile.id);

      // Still missing after its installation: reported, never repeated.
      remote.connections.results.addAll([
        RemoteFailureCode.helperNotInstalled,
        RemoteFailureCode.helperNotInstalled,
      ]);
      final still = await service.connect(profile.id);
      expect(still.failure, RemoteFailureCode.helperNotInstalled);
      expect(remote.connections.installs, ['devbox', 'devbox']);

      // Without a bundled helper only manual setup remains.
      remote.connections
        ..helper = null
        ..results.add(RemoteFailureCode.helperNotInstalled);
      expect(
        (await service.connect(profile.id)).failure,
        RemoteFailureCode.helperNotInstalled,
      );
      expect(remote.connections.installs, hasLength(2));

      // Another alias may reach another computer: ask again.
      final edited = await service.saveProfile(
        id: profile.id,
        label: 'Box',
        alias: 'otherbox',
      );
      expect(edited.autoInstallHelper, isFalse);
      await service.dispose();
      await settings.dispose();
    });

    testWidgets('the Remote hosts settings list and edit every host', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await window.service.saveProfile(label: 'Pi', alias: 'pi');
      window.remote.connections.helperId = '7'.padLeft(40, '0');
      final controller = RemoteWorkspaceController(
        service: window.service,
        repositories: window.repositories,
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SettingsDialog(
              settings: window.settings,
              repositories: window.repositories,
              hosting: null,
              repository: null,
              initialCategory: SettingsCategory.remoteHosts,
              onOpenUrl: (_) async {},
              remote: controller,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(
        find.byKey(const Key('settings-category-remoteHosts')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('settings-remote-helper-version')),
            )
            .data,
        '7',
      );
      expect(find.text('Workstation'), findsOneWidget);
      expect(find.text('Pi'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey('settings-remote-auto-install-${profile.id}')),
      );
      await _settle(tester);
      expect(window.service.profile(profile.id)!.autoInstallHelper, isTrue);

      // Allowing changes on a live host reconnects it.
      final opens = window.remote.connections.opens;
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('settings-remote-access-${profile.id}')),
          matching: find.text('Allow changes'),
        ),
      );
      await _settle(tester);
      expect(window.service.profile(profile.id)!.writesAllowed, isTrue);
      expect(window.remote.connections.opens, opens + 1);

      final pi = window.service.profiles.firstWhere((p) => p.alias == 'pi');
      await tester.ensureVisible(
        find.byKey(ValueKey('settings-remote-delete-${pi.id}')),
      );
      await tester.tap(find.byKey(ValueKey('settings-remote-delete-${pi.id}')));
      await _settle(tester);
      await tester.tap(find.widgetWithText(MeridianButton, 'Delete host').last);
      await _settle(tester);
      expect(window.service.profiles.map((p) => p.alias), ['devbox']);
      expect(find.text('Pi'), findsNothing);
      await window.close(tester);
    });
  });

  group('directory picker', () {
    testWidgets('navigates, validates typed paths and drops late replies', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service);
      final late = Completer<RemoteDirectoryPage>();
      remote.sessions.list = (directory, cursor) {
        final path = directory == null ? null : utf8.decode(directory);
        if (path == null || (path == '/home/me' && cursor == null)) {
          return Future.value(
            fakePage(
              '/home/me',
              [
                fakeEntry(
                  'project',
                  RemoteEntryKind.directory,
                  repository: true,
                ),
                fakeEntry('notes.txt', RemoteEntryKind.file),
              ],
              parent: '/home',
              cursor: cursor == null ? 'next' : null,
            ),
          );
        }
        if (path == '/home/me' && cursor == 'next') {
          return Future.value(
            fakePage('/home/me', [
              fakeEntry('later', RemoteEntryKind.directory),
            ], parent: '/home'),
          );
        }
        if (path == '/home/me/project') return late.future;
        if (path == '/home') {
          return Future.value(
            fakePage('/home', [
              fakeEntry('me', RemoteEntryKind.directory),
            ], parent: '/'),
          );
        }
        return Future.error(
          const RemoteWorkspaceException(RemoteFailureCode.pathNotFound),
        );
      };
      Uint8List? chosen;
      await tester.pumpWidget(
        _launcher(
          (context) async => chosen = await showRemoteDirectoryPicker(
            context,
            service: remote.service,
            profile: profile,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(_currentFolder(tester), '/home/me');
      expect(find.text('Repository'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('remote-directory-more')));
      await _settle(tester);
      expect(find.text('later'), findsOneWidget);
      expect(find.byKey(const ValueKey('remote-directory-more')), findsNothing);

      // Entering the project waits; going up meanwhile supersedes it.
      await tester.tap(find.text('project'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-directory-up')));
      await _settle(tester);
      expect(_currentFolder(tester), '/home');
      // The late reply of the superseded request changes nothing.
      late.complete(fakePage('/home/me/project', const [], parent: '/home/me'));
      await _settle(tester);
      expect(_currentFolder(tester), '/home');
      await tester.tap(find.text('me'));
      await _settle(tester);
      expect(_currentFolder(tester), '/home/me');

      await tester.enterText(
        _field(const ValueKey('remote-directory-path')),
        '~/work',
      );
      await tester.pump();
      expect(find.textContaining('absolute path that starts with /'), findsOne);
      await tester.tap(find.byKey(const ValueKey('remote-directory-open')));
      await _settle(tester);
      expect(chosen, isNull);

      await tester.enterText(
        _field(const ValueKey('remote-directory-path')),
        '/missing',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-directory-go')));
      await _settle(tester);
      expect(find.text('This folder does not exist on the host.'), findsOne);
      // The listing stays where it was.
      expect(_currentFolder(tester), '/home/me');

      await tester.enterText(
        _field(const ValueKey('remote-directory-path')),
        '/srv/repo',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-directory-open')));
      await _settle(tester);
      expect(chosen, utf8.encode('/srv/repo'));
      await remote.service.dispose();
    });

    testWidgets('typing follows the path and tells whether it is a folder', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service);
      final listed = <String>[];
      remote.sessions.list = (directory, cursor) {
        final path = directory == null ? '/home/me' : utf8.decode(directory);
        listed.add(path);
        return switch (path) {
          '/home/me' => Future.value(
            fakePage('/home/me', [
              fakeEntry('project', RemoteEntryKind.directory, repository: true),
              fakeEntry('projects', RemoteEntryKind.directory),
              fakeEntry('notes.txt', RemoteEntryKind.file),
              fakeEntry('link', RemoteEntryKind.symlink),
            ], parent: '/home'),
          ),
          '/home/me/project' => Future.value(
            fakePage('/home/me/project', [
              fakeEntry('src', RemoteEntryKind.directory),
            ], parent: '/home/me'),
          ),
          '/home/me/projects' => Future.value(
            fakePage('/home/me/projects', const [], parent: '/home/me'),
          ),
          '/home/me/link' => Future.error(
            const RemoteWorkspaceException(RemoteFailureCode.notDirectory),
          ),
          _ => Future.error(
            const RemoteWorkspaceException(RemoteFailureCode.pathNotFound),
          ),
        };
      };
      Uint8List? chosen;
      await tester.pumpWidget(
        _launcher(
          (context) async => chosen = await showRemoteDirectoryPicker(
            context,
            service: remote.service,
            profile: profile,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      final field = _field(const ValueKey('remote-directory-path'));
      Future<void> type(String text) async {
        await tester.enterText(field, text);
        await _settle(tester);
      }

      Finder mark(String status) =>
          find.byKey(ValueKey('remote-directory-path-$status'));

      // The folder being typed in is listed, filtered by the typed name.
      await type('/home/me/pro');
      expect(_currentFolder(tester), '/home/me');
      expect(find.text('project'), findsOneWidget);
      expect(find.text('projects'), findsOneWidget);
      expect(find.text('notes.txt'), findsNothing);
      expect(mark('missing'), findsOneWidget);
      expect(
        find.text('There is no folder at this path on the host.'),
        findsOne,
      );

      // Typing on within the same folder reuses its listing.
      final listings = listed.length;
      await type('/home/me/project');
      expect(listed, hasLength(listings));
      expect(mark('folder'), findsOneWidget);
      expect(find.text('This folder exists on the host.'), findsOne);
      await type('/home/me/notes.txt');
      expect(mark('notFolder'), findsOneWidget);
      // A link is checked on the host.
      await type('/home/me/link');
      expect(listed.last, '/home/me/link');
      expect(mark('notFolder'), findsOneWidget);
      await type('/home/me/xyz');
      expect(find.text('No entries start with the typed name.'), findsOne);

      // A trailing separator lists the folder itself.
      await type('/home/me/project/');
      expect(_currentFolder(tester), '/home/me/project');
      expect(find.text('src'), findsOneWidget);
      expect(mark('folder'), findsOneWidget);
      // A missing parent is reported without an error banner.
      await type('/nowhere/deeper');
      expect(mark('missing'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote-directory-failure')),
        findsNothing,
      );

      // Choosing an entry puts its path into the field.
      await type('/home/me/pro');
      await tester.tap(find.text('projects'));
      await _settle(tester);
      expect(_currentFolder(tester), '/home/me/projects');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '/home/me/projects/',
      );
      await tester.tap(find.byKey(const ValueKey('remote-directory-open')));
      await _settle(tester);
      expect(chosen, utf8.encode('/home/me/projects'));
      await remote.service.dispose();
    });

    testWidgets('an entered folder is shown from its top', (tester) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service);
      remote.sessions.list = (directory, cursor) {
        final path = directory == null ? '/home/me' : utf8.decode(directory);
        return Future.value(
          fakePage(path, [
            for (var index = 0; index < 40; index += 1)
              fakeEntry('folder$index', RemoteEntryKind.directory),
          ], parent: '/home'),
        );
      };
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteDirectoryPicker(
            context,
            service: remote.service,
            profile: profile,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      final entries = find.byKey(const ValueKey('remote-directory-entries'));
      ScrollController controller() =>
          tester.widget<ListView>(entries).controller!;
      await tester.scrollUntilVisible(
        find.text('folder30'),
        200,
        scrollable: find.descendant(
          of: entries,
          matching: find.byType(Scrollable),
        ),
      );
      expect(controller().offset, greaterThan(0));
      await tester.tap(find.text('folder30'));
      await _settle(tester);
      expect(_currentFolder(tester), '/home/me/folder30');
      expect(controller().offset, 0);
      await remote.service.dispose();
    });

    testWidgets('a superseded listing never replaces the newer one', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service);
      final slow = Completer<RemoteDirectoryPage>();
      remote.sessions.list = (directory, cursor) {
        final path = directory == null ? null : utf8.decode(directory);
        return switch (path) {
          null => Future.value(
            fakePage('/home/me', [
              fakeEntry('slow', RemoteEntryKind.directory),
              fakeEntry('fast', RemoteEntryKind.directory),
            ]),
          ),
          '/home/me/slow' => slow.future,
          _ => Future.value(fakePage(path, const [])),
        };
      };
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteDirectoryPicker(
            context,
            service: remote.service,
            profile: profile,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      await tester.tap(find.text('slow'));
      await tester.pump();
      await tester.enterText(
        _field(const ValueKey('remote-directory-path')),
        '/srv',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-directory-go')));
      await _settle(tester);
      expect(_currentFolder(tester), '/srv');
      slow.complete(fakePage('/home/me/slow', const []));
      await _settle(tester);
      expect(_currentFolder(tester), '/srv');

      await remote.service.dispose();
    });

    testWidgets('changed and expired listings offer their recovery', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service);
      var calls = 0;
      remote.sessions.list = (directory, cursor) {
        calls += 1;
        if (cursor == 'next') {
          return Future.error(
            const RemoteWorkspaceException(RemoteFailureCode.cursorExpired),
          );
        }
        return Future.value(
          fakePage(
            '/home/me',
            [fakeEntry('a', RemoteEntryKind.directory)],
            cursor: 'next',
            truncated: true,
          ),
        );
      };
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteDirectoryPicker(
            context,
            service: remote.service,
            profile: profile,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('remote-directory-truncated')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('remote-directory-more')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('remote-directory-restart')),
        findsOneWidget,
      );
      final before = calls;
      await tester.tap(find.byKey(const ValueKey('remote-directory-restart')));
      await _settle(tester);
      expect(calls, before + 1);
      expect(remote.sessions.listings.last.cursor, isNull);
      expect(
        find.byKey(const ValueKey('remote-directory-failure')),
        findsNothing,
      );
      await remote.service.dispose();
    });
  });

  group('remote tabs', () {
    testWidgets('show their host, stay visible when stale and reconnect', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      expect(find.text('project · Workstation'), findsOneWidget);
      expect(find.text('On Workstation'), findsWidgets);
      expect(find.byKey(const ValueKey('remote-stale-banner')), findsNothing);

      window.remote.connections.last!.drop();
      await _settle(tester);
      // The banner says what happened and when the next attempt runs.
      expect(
        find.text('Connection to Workstation lost. Reconnecting in 2 s…'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The connection to the host was lost. '
          'Showing the last received state.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('remote-reconnect-stop')), findsOne);
      // The received state stays on screen.
      expect(find.text('project · Workstation'), findsOneWidget);
      expect(find.text('On Workstation, disconnected'), findsWidgets);

      final opens = window.remote.connections.opens;
      await tester.tap(find.byKey(const ValueKey('remote-reconnect')));
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 1);
      expect(find.byKey(const ValueKey('remote-stale-banner')), findsNothing);

      // Stop ends the automatic attempts until the user reconnects.
      window.remote.connections.last!.drop();
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-reconnect-stop')));
      await _settle(tester);
      expect(find.text('Not reconnecting to Workstation'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(window.remote.connections.opens, opens + 1);

      // Without Stop the connection returns on its own and says so.
      await tester.tap(find.byKey(const ValueKey('remote-reconnect')));
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 2);
      window.remote.connections.last!.drop();
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 3);
      expect(find.byKey(const ValueKey('remote-stale-banner')), findsNothing);
      expect(find.text('Reconnected to Workstation'), findsOneWidget);
      await window.close(tester);
    });

    testWidgets('opening from a chooser tab replaces that tab', (tester) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      final chooser = window.repositories.addRepositoryChooser();
      final tabs = window.repositories.workspace.tabs.length;
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('repository-chooser-remote')));
      await _settle(tester);
      await tester.tap(find.byKey(ValueKey('remote-host-${profile.id}')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-choose-folder')));
      await _settle(tester);
      await tester.enterText(
        _field(const ValueKey('remote-directory-path')),
        '/home/me/project',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remote-directory-open')));
      await _settle(tester);
      final workspace = window.repositories.workspace;
      expect(workspace.tabs, hasLength(tabs));
      expect(
        workspace.tabs.where((tab) => tab.phase == RepositoryTabPhase.choosing),
        isEmpty,
      );
      expect(workspace.activeTabId, chooser);
      expect(find.text('project · Workstation'), findsOneWidget);
      await window.close(tester);
    });

    testWidgets('a host with a colour and icon marks its tabs by them', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      var profile = await _connectedProfile(window.service);
      profile = await window.service.saveProfile(
        id: profile.id,
        label: profile.label,
        alias: profile.alias,
        color: 'teal',
        icon: 'cloud',
      );
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      // The label is the repository's alone; the icon tells the host.
      expect(find.text('project · Workstation'), findsNothing);
      expect(find.text('project'), findsWidgets);
      final mark = tester.widget<MeridianIcon>(
        find.byWidgetPredicate(
          (widget) =>
              widget is MeridianIcon &&
              (widget.key as ValueKey<String>?)?.value.startsWith(
                    'remote-tab-host-',
                  ) ==
                  true,
        ),
      );
      expect(mark.name, 'cloud');
      expect(mark.color, isNotNull);
      await window.close(tester);
    });

    testWidgets('changing access while connected reconnects with the tabs', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      final opens = window.remote.connections.opens;
      await window.service.setWritesAllowed(profile.id, true);
      expect(window.service.writeBlock(profile.id), RemoteWriteBlock.reconnect);
      await window.repositories.applyRemoteAccess(profile.id);
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 1);
      expect(window.service.writeBlock(profile.id), isNull);
      final tab = window.repositories.workspace.tabs.single;
      expect(window.repositories.isRemoteTabStale(tab), isFalse);
      await window.close(tester);
    });

    testWidgets('restored remote tabs connect their host on their own', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      await window.service.disconnect(profile.id);
      await tester.pump();
      final opens = window.remote.connections.opens;
      // The next window restores the saved tabs.
      final restored = RepositorySessionService(
        fakeRepositorySessionRepository(snapshot: _snapshot()),
        window.settings,
        null,
        null,
        null,
        window.service,
      );
      await restored.restoreWorkspace();
      await tester.pump();
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 1);
      final tab = restored.workspace.tabs.single;
      expect(restored.isRemoteTabStale(tab), isFalse);
      expect(restored.remoteReconnect.stateOf(profile.id), isNull);
      await restored.dispose();
      await window.close(tester);
    });

    testWidgets('a remote tab that could not open offers Reconnect', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(routed: true);
      final profile = await _connectedProfile(window.service);
      await window.service.disconnect(profile.id);
      try {
        await _openRemoteTab(window, profile);
      } on RepositorySessionException {
        // The tab stays, failed, with its identity.
      }
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-tab-failure')), findsOneWidget);
      expect(find.text('Not connected to Workstation'), findsOneWidget);
      window.remote.connections.results.add(
        RemoteFailureCode.sshConnectionFailed,
      );
      final opens = window.remote.connections.opens;
      await tester.tap(find.byKey(const ValueKey('remote-reconnect')));
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 1);
      // A failure that may pass is retried; the tab says why and when.
      expect(find.textContaining('ssh devbox works in a terminal'), findsOne);
      expect(
        find.text('Connection to Workstation lost. Reconnecting in 5 s…'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      expect(window.remote.connections.opens, opens + 2);
      expect(find.byKey(const ValueKey('remote-tab-failure')), findsNothing);
      await window.close(tester);
    });

    testWidgets('the command line opens a path on a new host once saved', (
      tester,
    ) async {
      _desktop(tester);
      final cli = _ForwardedCommands();
      final window = await _window(routed: true, cli: cli);
      window.remote.sessions.repository = _FullRepository();
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      final path = utf8.encode('/home/me/project');
      cli.add(
        CliForwardedCommand(
          requestId: BigInt.one,
          kind: CliForwardedCommandKind.openRemoteRepository,
          remoteAlias: 'me@devbox',
          path: NativePathIdentity(
            platform: NativePathPlatform.unix,
            units: path,
          ),
        ),
      );
      await _settle(tester);
      // No host has the alias: the user decides whether to save it.
      expect(find.textContaining('which is not a saved host yet'), findsOne);
      String field(String key) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(field('remote-host-alias'), 'me@devbox');
      expect(field('remote-host-label'), 'me@devbox');
      await tester.tap(find.byKey(const ValueKey('remote-host-save')));
      await _settle(tester);
      final profile = window.remote.service.profiles.single;
      expect(profile.alias, 'me@devbox');
      final tab = window.repositories.workspace.activeTab!;
      expect(tab.requestedIdentity?.remote, profile.authority);
      expect(tab.requestedIdentity?.units, path);
      await window.close(tester);
    });

    testWidgets('a remote worktree past the session limit says why', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(routed: true);
      final profile = await _connectedProfile(window.service);
      final sessions = window.remote.sessions;
      final host = _FullRepository();
      sessions.repository = host;
      await _openRemoteTab(window, profile);
      // The connection holds as many repositories as the helper allows.
      host.full = true;
      NativePathIdentity remote(String path) => NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: utf8.encode(path),
        remote: profile.authority,
      );
      await expectLater(
        window.repositories.openWorktree(
          WorktreeEntry(
            worktreeRoot: remote('/home/me/feature'),
            gitDir: remote('/home/me/project/.git/worktrees/feature'),
            commonGitDir: remote('/home/me/project/.git'),
            locked: false,
            prunable: false,
            current: false,
          ),
        ),
        throwsA(isA<RepositorySessionException>()),
      );
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      expect(
        window.repositories.workspace.activeTab?.failure?.code,
        RepositoryFailureCode.capacity,
      );
      expect(
        find.text(
          'This connection has reached its open repository limit. Close '
          'another repository tab on this host, then try again.',
        ),
        findsOneWidget,
      );
      await window.close(tester);
    });

    testWidgets('a replaced repository on a trusted host opens on request', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(routed: true);
      final profile = await _connectedProfile(window.service);
      final sessions = window.remote.sessions;
      final host = _BoundRepository(sessions);
      sessions.repository = host;
      await _openRemoteTab(window, profile);
      // The host restarted and its filesystem now names the folder anew.
      host.binding = 'after';
      await window.repositories.reconnectRemote(profile.id);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-tab-failure')), findsOneWidget);
      expect(find.text('The repository on Workstation changed'), findsOne);
      expect(
        find.byKey(const ValueKey('remote-review-identity')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('remote-trust-repository')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-tab-failure')), findsNothing);
      expect(
        sessions.expectedBinding!(utf8.encode('/home/me/project')),
        'after',
      );
      await window.close(tester);
    });

    testWidgets('the status bar switches what GitLama may do on the host', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      String access() => tester
          .widget<Text>(find.byKey(const ValueKey('remote-host-access')))
          .data!;
      AppCommandDisabledReason? reason(AppCommandId id) =>
          CommandAvailabilityScope.peek(
            tester.element(find.byKey(const ValueKey('repository-toolbar'))),
          )!.reason(id);
      expect(access(), 'Read only');
      expect(reason(AppCommandId.mergeBranch), isNotNull);

      // Allowing changes reconnects the host with its tabs at once.
      final opens = window.remote.connections.opens;
      await tester.tap(find.byKey(const ValueKey('remote-host-status')));
      await _settle(tester);
      await tester.tap(find.text('Allow changes').last);
      await _settle(tester);
      expect(window.service.profile(profile.id)!.writesAllowed, isTrue);
      expect(window.remote.connections.opens, opens + 1);
      expect(access(), 'Changes allowed');
      expect(
        remoteCommandReason(
          AppCommandId.mergeBranch,
          CommandAvailabilityScope.peek(
            tester.element(find.byKey(const ValueKey('repository-toolbar'))),
          )!.remote,
        ),
        isNull,
      );

      // And back to reading only.
      await tester.tap(find.byKey(const ValueKey('remote-host-status')));
      await _settle(tester);
      await tester.tap(find.text('Read only').last);
      await _settle(tester);
      expect(window.service.profile(profile.id)!.writesAllowed, isFalse);
      expect(access(), 'Read only');
      expect(
        reason(AppCommandId.createBranch),
        AppCommandDisabledReason.remoteWritesOff,
      );
      await window.close(tester);
    });

    testWidgets('a tab whose host lacks the helper installs it in place', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(routed: true);
      final profile = await _connectedProfile(window.service);
      await window.service.disconnect(profile.id);
      try {
        await _openRemoteTab(window, profile);
      } on RepositorySessionException {
        // The tab stays, failed, with its identity.
      }
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      // An updated GitLama needs a helper the host does not have yet.
      window.remote.connections
        ..helper = _helper
        ..results.add(RemoteFailureCode.helperNotInstalled);
      await tester.tap(find.byKey(const ValueKey('remote-reconnect')));
      await _settle(tester);
      // Reconnecting asks right away instead of only reporting the failure.
      expect(find.text('Install the helper on Workstation?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await _settle(tester);
      expect(window.remote.connections.installs, isEmpty);
      // The tab keeps offering the installation.
      expect(find.textContaining('helper for this version'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('remote-install-helper')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-install-automatic')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-install-confirm')));
      await _settle(tester);
      expect(window.remote.connections.installs, ['devbox']);
      expect(window.service.profile(profile.id)!.autoInstallHelper, isTrue);
      // Connected and reopened in place.
      expect(find.byKey(const ValueKey('remote-tab-failure')), findsNothing);
      expect(window.service.state(profile.id).ready, isTrue);

      // The next update installs without asking.
      await window.service.disconnect(profile.id);
      window.remote.connections.results.add(
        RemoteFailureCode.helperNotInstalled,
      );
      expect((await window.service.connect(profile.id)).ready, isTrue);
      expect(window.remote.connections.installs, ['devbox', 'devbox']);
      await window.close(tester);
    });

    testWidgets('a deleted host keeps a generic badge', (tester) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      await window.service.deleteProfile(profile.id);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      expect(find.text('project · Remote host'), findsOneWidget);
      // Without its profile the tab cannot reconnect.
      expect(find.byKey(const ValueKey('remote-reconnect')), findsNothing);
      await window.close(tester);
    });

    testWidgets(
      'commands without their capability are disabled with a reason',
      (tester) async {
        _desktop(tester);
        final window = await _window();
        final profile = await _connectedProfile(window.service);
        await _openRemoteTab(window, profile);
        await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
        await _settle(tester);

        final branch = tester.widget<MeridianToolbarButton>(
          find.byKey(const ValueKey('toolbar-action-createBranch')),
        );
        expect(branch.onPressed, isNull);
        expect(branch.disabledReason, _writesOff);
        final fetch = tester.widget<MeridianToolbarButton>(
          find.byKey(const ValueKey('toolbar-action-fetch')),
        );
        expect(fetch.onPressed, isNull);
        expect(fetch.disabledReason, _writesOff);
        final state = CommandAvailabilityScope.peek(
          tester.element(find.byKey(const ValueKey('repository-toolbar'))),
        )!;
        // A reset is a ref change on the host; a terminal is a local tool.
        expect(
          state.reason(AppCommandId.resetBranch),
          AppCommandDisabledReason.remoteWritesOff,
        );
        expect(
          state.reason(AppCommandId.openInTerminal),
          AppCommandDisabledReason.remoteUnsupported,
        );

        await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
        await _settle(tester);
        await tester.enterText(
          find.byKey(const Key('command-palette-query')),
          'branch',
        );
        await _settle(tester);
        final create = tester.widget<MeridianListRow>(
          find.widgetWithText(MeridianListRow, 'Create branch…'),
        );
        expect(create.enabled, isFalse);
        expect(create.subtitle, _writesOff);
        await window.close(tester);
      },
    );

    testWidgets('an inspection opens a window that names its host', (
      tester,
    ) async {
      _desktop(tester);
      final windows = _RecordingWindows();
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      final identity = window.repositories.activeTab!.canonicalIdentity!;
      expect(identity.remote, profile.authority);
      final inspector = InspectorService(fakeRepositorySessionRepository());
      inspector.attach(
        RepositorySessionIdentity(nativeId: BigInt.one, generation: 1),
      );
      await inspector.navigate(
        const InspectorLocation(target: CommitTarget(_inspected)),
      );
      PaneInspectorHost host({
        required bool connected,
        NativePathIdentity? repository,
      }) => PaneInspectorHost(
        historyService: window.repositories.history,
        repositoryIdentity: repository ?? identity,
        inspectionWindows: InspectionWindowService(windows),
        repositories: window.repositories,
        inspectionOpenIn: 'pane',
        fileBrowserName: 'Files',
        maximized: false,
        onToggleMaximize: () {},
        onOpenFile: (_) {},
        onRevealFile: (_) {},
        onCreatePatch: (_, _) {},
        onOpenWindowFailed: () {},
        remote: true,
        remoteConnected: connected,
      );
      Future<void> show(PaneInspectorHost host) async {
        await tester.pumpWidget(
          _app(
            InspectorView(
              service: inspector,
              host: host,
              shortcuts: AppShortcutCatalog.resolve(const [], macOS: false),
              filesMode: GitFileListMode.tree,
              onFilesModeChanged: (_) {},
              sidebarWidth: 280,
              onSidebarWidthChanged: (_) {},
            ),
          ),
        );
        await _settle(tester);
      }

      final open = find.byKey(const ValueKey('inspector-open-window'));
      await show(host(connected: true));
      expect(open, findsOneWidget);
      await tester.tap(open);
      await _settle(tester);
      final request = windows.opened.single;
      // The window reads the host, never a same-named local path.
      expect(request.repository, identity);
      expect(request.repository.remote, profile.authority);
      expect(request.location.target, const CommitTarget(_inspected));

      // Without the connection the action stays, disabled with its reason.
      await show(host(connected: false));
      final disconnected = tester.widget<MeridianIconButton>(open);
      expect(disconnected.onPressed, isNull);
      expect(disconnected.disabledReason, 'Reconnect to the host to use this');

      // A remote tab whose identity lost its host opens nothing.
      final bare = host(
        connected: true,
        repository: NativePathIdentity(
          platform: identity.platform,
          units: identity.units,
        ),
      );
      expect(bare.supportsWindows, isFalse);
      await bare.openInWindow(
        const InspectorLocation(target: CommitTarget(_inspected)),
      );
      expect(windows.opened, hasLength(1));

      // Show in main window finds the remote tab, not a local namesake.
      final navigator = WorkspaceNavigator(window.repositories);
      expect(
        await navigator.revealFromInspectorWindow(
          InspectorRevealRequest(
            repository: NativePathIdentity(
              platform: identity.platform,
              units: identity.units,
            ),
            commit: _inspected,
          ),
        ),
        isFalse,
      );
      expect(
        await navigator.revealFromInspectorWindow(
          InspectorRevealRequest.decode(
            InspectorRevealRequest(
              repository: identity,
              commit: _inspected,
            ).encode(),
          )!,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await inspector.dispose();
      await window.close(tester);
    });

    testWidgets('the same commands stay available for a local tab', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      await window.repositories.open('/local/project');
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      final branch = tester.widget<MeridianToolbarButton>(
        find.byKey(const ValueKey('toolbar-action-createBranch')),
      );
      expect(branch.onPressed, isNotNull);
      expect(find.text('On Workstation'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('toolbar-command-palette')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('command-palette-query')),
        'branch',
      );
      await _settle(tester);
      final create = tester.widget<MeridianListRow>(
        find.widgetWithText(MeridianListRow, 'Create branch…'),
      );
      expect(create.enabled, isTrue);
      expect(create.subtitle, isNull);
      await window.close(tester);
    });

    testWidgets('staging and commits follow the negotiated capability', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(staged: true);
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      final state = CommandAvailabilityScope.peek(
        tester.element(find.byKey(const ValueKey('repository-toolbar'))),
      )!;
      expect(
        state.reason(AppCommandId.commitCreate),
        AppCommandDisabledReason.remoteWritesOff,
      );
      // Commit & Push and amend need the host's permission like a commit.
      final commitAndPush = tester.widget<MeridianButton>(
        find.byKey(const ValueKey('commit-push-menu')),
      );
      expect(commitAndPush.onPressed, isNull);
      expect(commitAndPush.disabledReason, _writesOff);
      expect(
        tester
            .widget<MeridianCheckbox>(
              find.byKey(const ValueKey('commit-amend')),
            )
            .onChanged,
        isNull,
      );
      // Discard stays visible, disabled with why.
      final discardAll = tester.widget<MeridianIconButton>(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is MeridianIconButton &&
                  widget.icon == 'brush-cleaning',
            )
            .first,
      );
      expect(discardAll.onPressed, isNull);
      expect(discardAll.disabledReason, contains('Allow changes'));

      // Writes apply from the next connection, and the reason says so.
      await window.service.setWritesAllowed(profile.id, true);
      await _settle(tester);
      expect(
        CommandAvailabilityScope.peek(
          tester.element(find.byKey(const ValueKey('repository-toolbar'))),
        )!.reason(AppCommandId.createBranch),
        AppCommandDisabledReason.remoteWritesReconnect,
      );
      await window.service.disconnect(profile.id);
      await window.repositories.reconnectRemote(profile.id);
      await _settle(tester);
      final writable = CommandAvailabilityScope.peek(
        tester.element(find.byKey(const ValueKey('repository-toolbar'))),
      )!;
      expect(writable.reason(AppCommandId.commitCreate), isNull);
      expect(
        remoteCommandReason(AppCommandId.commitAmend, writable.remote),
        isNull,
      );
      expect(
        writable.remote!.capabilities,
        containsAll(remoteWriteCapabilities),
      );
      // Branches and stashes follow their own capabilities; fetch and push
      // need a configured remote, which the fixture has none of.
      for (final id in [AppCommandId.createBranch, AppCommandId.createStash]) {
        expect(writable.reason(id), isNull, reason: id.name);
      }
      // Renaming needs a remote and discarding a selection; the host allows
      // both.
      for (final id in [
        AppCommandId.renameRemote,
        AppCommandId.discardChanges,
        // Families added later: history, recovery and extensions.
        AppCommandId.resetBranch,
        AppCommandId.mergeBranch,
        AppCommandId.cherryPickSelected,
        AppCommandId.revertSelected,
        AppCommandId.interactiveRebase,
        AppCommandId.rebaseContinue,
        AppCommandId.conflictTakeIncoming,
        AppCommandId.commitAmend,
        AppCommandId.applyPatch,
        AppCommandId.addWorktree,
        AppCommandId.trackLfsPattern,
      ]) {
        expect(
          remoteCommandReason(id, writable.remote),
          isNull,
          reason: id.name,
        );
      }
      // A terminal still opens on this computer only.
      expect(
        remoteCommandReason(AppCommandId.openInTerminal, writable.remote),
        AppCommandDisabledReason.remoteUnsupported,
      );
      await window.close(tester);
    });

    testWidgets('connecting from any dialog reopens the stale tabs', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      final tab = window.repositories.workspace.activeTab!;
      expect(window.repositories.isRemoteTabStale(tab), isFalse);
      await window.service.disconnect(profile.id);
      expect(
        window.repositories.isRemoteTabStale(
          window.repositories.workspace.activeTab!,
        ),
        isTrue,
      );
      // The host dialog connects through the service, not reconnectRemote.
      expect((await window.service.connect(profile.id)).ready, isTrue);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      final reopened = window.repositories.workspace.activeTab!;
      expect(reopened.id, tab.id);
      expect(window.repositories.isRemoteTabStale(reopened), isFalse);
      // A session of the closed connection is gone on the host; the tab runs
      // on a new one.
      expect(reopened.generation, isNot(tab.generation));
      await window.close(tester);
    });

    testWidgets('a discard with an unknown outcome asks for review', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(
        unstaged: true,
        executeDiscardError: const RemoteOutcomeUnknownException(),
      );
      final profile = await _connectedProfile(window.service, writes: true);
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      await tester.tap(find.text('notes.txt'));
      await tester.pump();
      await tester.tap(find.byTooltip('Discard selected'));
      await _settle(tester);
      await tester.tap(find.text('Discard permanently'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('could not confirm whether it was applied'),
        findsNWidgets(2),
      );
      await window.close(tester);
    });

    testWidgets('a commit with an unknown outcome keeps its draft', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window(
        staged: true,
        executeCommitError: const RemoteOutcomeUnknownException(),
      );
      final profile = await _connectedProfile(window.service, writes: true);
      await _openRemoteTab(window, profile);
      await tester.pumpWidget(_app(HomeScreen(runtime: window.runtime)));
      await _settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('commit-subject-field')),
          matching: find.byType(EditableText),
        ),
        'Remote subject',
      );
      await tester.pump();
      final commit = find.descendant(
        of: find.byKey(const ValueKey('changes-commit-editor')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MeridianButton &&
              widget.variant == MeridianButtonVariant.primary,
        ),
      );
      expect(tester.widget<MeridianButton>(commit).onPressed, isNotNull);
      await tester.tap(commit);
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('commit-outcome-unknown')),
        findsOneWidget,
      );
      expect(
        find.textContaining('may or may not have been applied'),
        findsWidgets,
      );
      expect(
        find.text('Git rejected the commit. The draft was kept.'),
        findsNothing,
      );
      expect(find.text('Remote subject'), findsOneWidget);
      await window.close(tester);
    });
  });

  group('remote changes', () {
    testWidgets('unknown outcomes are listed for review, never retried', (
      tester,
    ) async {
      _desktop(tester);
      final settings = await _settings();
      final pending = FakeRemotePending();
      final remote = FakeRemoteWorkspace(settings, pending: pending);
      final profile = await remote.service.saveProfile(
        label: 'Workstation',
        alias: 'devbox',
      );
      remote.connections.results.add(const FakeHello());
      await remote.service.initialize();
      await remote.service.connect(profile.id);
      final authority = remote.service.profile(profile.id)!.authority!;
      await remote.service.disconnect(profile.id);
      await remote.service.record(
        RemotePendingOperation(
          operationId: '0123456789abcdef0123456789abcdef',
          epoch: 'e',
          digest: 'd',
          family: RemoteOperationFamily.commit,
          authority: authority,
          binding: 'b',
          pending: true,
          outcome: RemoteOperationOutcome.unknown,
          summary: 'Fix the parser',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: RemoteOperationsIndicator(service: remote.service),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('1 remote change to review'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('remote-operations-indicator')),
      );
      await _settle(tester);
      expect(find.text('Fix the parser'), findsOneWidget);
      expect(find.textContaining('Outcome unknown'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote-operations-uncertain')),
        findsOneWidget,
      );
      expect(find.textContaining('Retry'), findsNothing);
      final check = tester.widget<MeridianButton>(
        find.byKey(
          const ValueKey(
            'remote-operation-check-0123456789abcdef0123456789abcdef',
          ),
        ),
      );
      // Looking up needs a live connection.
      expect(check.onPressed, isNull);
      await remote.service.dispose();
    });
  });

  group('German at 130 % in 900 × 600', () {
    void compact(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the Remote hosts settings and the install prompt fit', (
      tester,
    ) async {
      compact(tester);
      final window = await _window();
      final profile = await window.service.saveProfile(
        label: 'Arbeitsrechner im Büro',
        alias: 'entwicklungsrechner',
      );
      window.remote.connections
        ..helper = _helper
        ..results.add(RemoteFailureCode.helperNotInstalled);
      await window.service.connect(profile.id);
      final controller = RemoteWorkspaceController(
        service: window.service,
        repositories: window.repositories,
      );
      await tester.pumpWidget(
        _app(
          locale: const Locale('de'),
          textScale: 1.3,
          Scaffold(
            body: SettingsDialog(
              settings: window.settings,
              repositories: window.repositories,
              hosting: null,
              repository: null,
              initialCategory: SettingsCategory.remoteHosts,
              onOpenUrl: (_) async {},
              remote: controller,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Helfer automatisch installieren'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final install = find.byKey(
        ValueKey('settings-remote-install-${profile.id}'),
      );
      await tester.ensureVisible(install);
      await _settle(tester);
      await tester.tap(install);
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-install-automatic')), findsOne);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('remote-install-confirm')));
      await _settle(tester);
      expect(window.remote.connections.installs, ['entwicklungsrechner']);
      expect(window.service.state(profile.id).ready, isTrue);
      await window.close(tester);
    });

    testWidgets('the host dialog and its failures fit', (tester) async {
      compact(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await remote.service.saveProfile(
        label: 'Arbeitsrechner im Büro',
        alias: 'entwicklungsrechner',
      );
      remote.connections.results.add(RemoteFailureCode.helperNotInstalled);
      await remote.service.connect(profile.id);
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteHostDialog(
            context,
            service: remote.service,
            choosing: true,
          ),
          locale: const Locale('de'),
          textScale: 1.3,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(find.text('Remote-Repository öffnen…'), findsOneWidget);
      expect(find.byKey(const ValueKey('remote-host-failure')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey('remote-edit-host')),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('remote-edit-host')));
      await _settle(tester);
      expect(find.text('Host bearbeiten'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await remote.service.dispose();
    });

    testWidgets('the folder picker and remote changes fit', (tester) async {
      compact(tester);
      final settings = await _settings();
      final remote = FakeRemoteWorkspace(settings);
      await remote.service.initialize();
      final profile = await _connectedProfile(remote.service);
      remote.sessions.list = (directory, cursor) => Future.value(
        fakePage(
          '/home/me/ein/sehr/langer/pfad/zu/einem/projektordner',
          [
            for (var index = 0; index < 20; index += 1)
              fakeEntry(
                'verzeichnis-$index',
                RemoteEntryKind.directory,
                repository: index.isEven,
              ),
          ],
          parent: '/home/me',
          cursor: 'next',
          truncated: true,
        ),
      );
      await tester.pumpWidget(
        _launcher(
          (context) => showRemoteDirectoryPicker(
            context,
            service: remote.service,
            profile: profile,
          ),
          locale: const Locale('de'),
          textScale: 1.3,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(find.text('Ordner auf Workstation wählen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        _field(const ValueKey('remote-directory-path')),
        'relativ',
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await remote.service.dispose();

      final operations = FakeRemoteWorkspace(
        settings,
        pending: FakeRemotePending([
          RemotePendingOperation(
            operationId: 'ffffffffffffffffffffffffffffffff',
            epoch: 'e',
            digest: 'd',
            family: RemoteOperationFamily.stage,
            authority: profile.authority!,
            binding: 'b',
            pending: true,
            outcome: RemoteOperationOutcome.unknown,
            summary: 'Änderungen an der Konfiguration stagen',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        ]),
      );
      await operations.service.initialize();
      await tester.pumpWidget(
        _launcher(
          (context) =>
              showRemoteOperationsDialog(context, service: operations.service),
          locale: const Locale('de'),
          textScale: 1.3,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(find.text('Remote-Änderungen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await operations.service.dispose();
    });

    testWidgets('a stale remote tab fits', (tester) async {
      compact(tester);
      final window = await _window();
      final profile = await _connectedProfile(window.service);
      await _openRemoteTab(window, profile);
      window.remote.connections.last!.drop();
      await tester.pumpWidget(
        _app(
          HomeScreen(runtime: window.runtime),
          locale: const Locale('de'),
          textScale: 1.3,
        ),
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('remote-stale-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await window.close(tester);
    });
  });
}

const _inspected = 'cccccccccccccccccccccccccccccccccccccccc';

/// A host whose repository opens only under the binding it was first opened
/// with, as the helper checks it.
final class _BoundRepository extends FakeRepositorySessionRepository {
  _BoundRepository(this._remote) : super(null);

  final FakeRemoteSessions _remote;
  String binding = 'before';

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) {
    final expected = _remote.expectedBinding!(identity.units);
    if (expected != null && expected != binding) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.remoteIdentityChanged),
      );
    }
    _remote.rememberBinding!(identity.units, binding);
    return super.openIdentity(identity, generation);
  }
}

final class _FullRepository extends FakeRepositorySessionRepository {
  _FullRepository() : super(null);

  bool full = false;

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) {
    if (full) {
      throw const RepositorySessionException(
        RepositoryFailure(RepositoryFailureCode.capacity),
      );
    }
    return super.openIdentity(identity, generation);
  }
}

/// Forwards commands to the window as the command line would.
final class _ForwardedCommands implements CliForwardingController {
  final StreamController<CliForwardedCommand> _commands =
      StreamController<CliForwardedCommand>.broadcast();

  void add(CliForwardedCommand command) => _commands.add(command);

  @override
  Stream<CliForwardedCommand> get commands => _commands.stream;

  @override
  void attach() {}

  @override
  void detach() {}
}
