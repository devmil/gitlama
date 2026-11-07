import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/services/remote_workspace_workflows.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_remote_workspace.dart';
import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

final class _Interaction implements RemoteWorkspaceInteraction {
  final List<Object> reports = [];
  var hostDialogs = 0;
  String? chosenHost;
  List<int>? chosenFolder;
  final List<String> offeredAliases = [];

  /// Saves the offered host when set; null declines.
  Future<RemoteHostProfile?> Function(String alias)? saveOffered;

  @override
  bool active = true;

  @override
  Future<({bool automatic})?> confirmHelperInstall(
    RemoteHostProfile profile,
    RemoteHelperArtifact artifact,
  ) async => null;

  @override
  Future<String?> showHosts({String? profileId, bool choosing = false}) async {
    hostDialogs += 1;
    return chosenHost;
  }

  @override
  Future<RemoteHostProfile?> addHost(String alias) async {
    offeredAliases.add(alias);
    return saveOffered?.call(alias);
  }

  @override
  Future<List<int>?> chooseFolder(
    RemoteHostProfile profile, {
    bool forInitialize = false,
  }) async => chosenFolder;

  @override
  void reportFailure(RemoteFailureCode code, {String? alias}) =>
      reports.add(code);

  @override
  void reportSaveFailure(Object error) => reports.add('save');

  @override
  void reportMessage(RemoteWorkflowMessage message) => reports.add(message);

  @override
  void reportDisabled(AppCommandDisabledReason reason) => reports.add(reason);
}

void main() {
  late SettingsService settings;
  late FakeRemoteWorkspace remote;
  late RepositorySessionService repositories;
  late RemoteWorkspaceWorkflows workflows;

  setUp(() async {
    settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    remote = FakeRemoteWorkspace(settings);
    await remote.service.initialize();
    repositories = RepositorySessionService(
      fakeRepositorySessionRepository(),
      settings,
      null,
      null,
      null,
      remote.service,
    );
    workflows = RemoteWorkspaceWorkflows(
      service: remote.service,
      repositories: repositories,
    );
  });

  tearDown(() async {
    await workflows.dispose();
    await repositories.dispose();
    await remote.service.dispose();
    await settings.dispose();
  });

  test('a recent repository of a deleted host says so', () async {
    final interaction = _Interaction();
    await workflows.openRecent(
      interaction,
      NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: const [47, 114],
        remote: const RemoteAuthority(
          profileId: '123e4567-e89b-42d3-a456-426614174000',
          storeId: '0123456789abcdef0123456789abcdef',
          accountUid: '1000',
        ),
      ),
    );
    expect(interaction.reports, [RemoteWorkflowMessage.recentHostMissing]);
  });

  for (final recent in [false, true]) {
    for (final capacity in [false, true]) {
      test(
        'remote open recent=$recent capacity=$capacity reports the reason',
        () async {
          final profile = await remote.service.saveProfile(
            label: 'Workstation',
            alias: 'devbox',
          );
          await remote.service.connect(profile.id);
          final connected = remote.service.profile(profile.id)!;
          final interaction = _Interaction()
            ..chosenHost = profile.id
            ..chosenFolder = [47, 114];
          Future<void> fail() async {
            throw RepositorySessionException(
              RepositoryFailure(
                capacity
                    ? RepositoryFailureCode.capacity
                    : RepositoryFailureCode.invalidOutput,
              ),
            );
          }

          if (recent) {
            await workflows.openRecent(
              interaction,
              RepositorySessionService.remotePathIdentity(
                connected.authority!,
                [47, 114],
              ),
              open: fail,
            );
          } else {
            await workflows.openRemoteRepository(
              interaction,
              open: (_) => fail(),
            );
          }
          expect(interaction.reports, [
            capacity
                ? RemoteWorkflowMessage.repositoryCapacity
                : RemoteWorkflowMessage.openFailed,
          ]);
        },
      );
    }
  }

  group('opening a path on a host from the command line', () {
    final path = utf8.encode('/home/me/project');

    NativePathIdentity? openedIdentity() =>
        repositories.workspace.activeTab?.requestedIdentity;

    test('connects the saved host and opens the path', () async {
      final profile = await remote.service.saveProfile(
        label: 'Workstation',
        alias: 'me@devbox',
      );
      final interaction = _Interaction();
      await workflows.openOnHost(interaction, 'me@devbox', path);
      expect(interaction.offeredAliases, isEmpty);
      expect(interaction.reports, isEmpty);
      expect(remote.service.state(profile.id).ready, isTrue);
      expect(
        openedIdentity(),
        RepositorySessionService.remotePathIdentity(
          remote.service.profile(profile.id)!.authority!,
          path,
        ),
      );
    });

    test('an unknown alias is offered as a new host first', () async {
      final interaction = _Interaction();
      await workflows.openOnHost(interaction, 'newbox', path);
      // Declined: nothing is saved, connected or opened.
      expect(interaction.offeredAliases, ['newbox']);
      expect(remote.service.profiles, isEmpty);
      expect(openedIdentity(), isNull);

      interaction.saveOffered = (alias) =>
          remote.service.saveProfile(label: alias, alias: alias);
      await workflows.openOnHost(interaction, 'newbox', path);
      final saved = remote.service.profiles.single;
      expect(saved.alias, 'newbox');
      expect(openedIdentity()?.remote, saved.authority);
      expect(openedIdentity()?.units, path);
    });

    test('a host that cannot connect reports why and opens nothing', () async {
      await remote.service.saveProfile(label: 'Workstation', alias: 'devbox');
      remote.connections.results.add(RemoteFailureCode.sshConnectionFailed);
      final interaction = _Interaction();
      await workflows.openOnHost(interaction, 'devbox', path);
      expect(interaction.reports, [RemoteFailureCode.sshConnectionFailed]);
      expect(openedIdentity(), isNull);
    });
  });

  test('repositories cannot be created on a read-only host', () async {
    final profile = await remote.service.saveProfile(
      label: 'Workstation',
      alias: 'devbox',
    );
    expect(
      workflows.initializeBlock(profile.id),
      RemoteInitializeBlock.writesOff,
    );
    expect(
      workflows.initializeBlock('00000000-0000-4000-8000-000000000000'),
      RemoteInitializeBlock.hostMissing,
    );
  });

  test('a window that went away is not asked or told anything', () async {
    final profile = await remote.service.saveProfile(
      label: 'Workstation',
      alias: 'devbox',
    );
    remote.connections.results.add(RemoteFailureCode.sshConnectionFailed);
    final interaction = _Interaction()..active = false;
    expect(await workflows.connectForUse(interaction, profile), isFalse);
    expect(interaction.reports, isEmpty);
    expect(interaction.hostDialogs, 0);
  });

  test('concurrent reconnects of a host share one attempt', () async {
    final profile = await remote.service.saveProfile(
      label: 'Workstation',
      alias: 'devbox',
    );
    final interaction = _Interaction();
    final events = <void>[];
    final subscription = workflows.activity.listen(events.add);
    final first = workflows.reconnect(interaction, profile.id);
    final second = workflows.reconnect(interaction, profile.id);
    expect(identical(first, second), isTrue);
    expect(workflows.connecting(profile.id), isTrue);
    await first;
    expect(workflows.connecting(profile.id), isFalse);
    expect(events, hasLength(2));
    await subscription.cancel();
  });
}
