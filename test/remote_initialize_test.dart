import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/initialize_dialog.dart';
import 'package:gitlama/app/workspace/remote_workspace.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/widgets/status_notification.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'support/fake_remote_workspace.dart';
import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

final class _Window {
  _Window(this.settings, this.remote, this.repositories)
    : controller = RemoteWorkspaceController(
        service: remote.service,
        repositories: repositories,
      );

  final SettingsService settings;
  final FakeRemoteWorkspace remote;
  final RepositorySessionService repositories;
  final RemoteWorkspaceController controller;

  Future<void> close() async {
    await repositories.dispose();
    await remote.service.dispose();
    await settings.dispose();
  }
}

Future<_Window> _window() async {
  final settings = fakeSettingsService();
  await settings.initialize();
  final remote = FakeRemoteWorkspace(settings);
  await remote.service.initialize();
  final repositories = RepositorySessionService(
    fakeRepositorySessionRepository(),
    settings,
    null,
    null,
    null,
    remote.service,
  );
  return _Window(settings, remote, repositories);
}

/// A saved host, connected; with [writes] changes are allowed and the
/// connection negotiated them.
Future<RemoteHostProfile> _host(_Window window, {bool writes = true}) async {
  final service = window.remote.service;
  final profile = await service.saveProfile(
    label: 'Workstation',
    alias: 'devbox',
  );
  if (writes) await service.setWritesAllowed(profile.id, true);
  expect((await service.connect(profile.id)).ready, isTrue);
  return service.profile(profile.id)!;
}

Widget _launcher(Future<Object?> Function(BuildContext context) open) =>
    MaterialApp(
      builder: (context, child) => StatusNotificationScope(child: child!),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
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

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('initializing on a host', () {
    test('creates the repository on the host and opens it in a tab', () async {
      final window = await _window();
      final profile = await _host(window);
      final path = utf8.encode('/home/me/new');
      await window.repositories.initializeRemote(
        profile.authority!,
        path,
        bare: true,
      );
      final created = window.remote.sessions.initializations.single;
      expect(created.path, path);
      expect(created.bare, isTrue);
      expect(created.initialBranch, 'main');
      final tab = window.repositories.workspace.tabs.single;
      expect(tab.requestedIdentity?.remote, profile.authority);
      expect(tab.requestedIdentity?.units, path);
      await window.close();
    });

    test('reports why the host created nothing and opens no tab', () async {
      final window = await _window();
      final profile = await _host(window);
      window.remote.sessions.initializeFailure =
          const RepositorySessionException(
            RepositoryFailure(RepositoryFailureCode.destinationNotEmpty),
          );
      await expectLater(
        window.repositories.initializeRemote(
          profile.authority!,
          utf8.encode('/home/me/full'),
        ),
        throwsA(
          isA<RepositorySessionException>().having(
            (error) => error.failure.code,
            'code',
            RepositoryFailureCode.destinationNotEmpty,
          ),
        ),
      );
      expect(window.repositories.workspace.tabs, isEmpty);
      await window.close();
    });

    test('a connection without changes never asks the host', () async {
      final window = await _window();
      final profile = await _host(window, writes: false);
      expect(window.remote.service.canInitialize(profile.id), isFalse);
      await expectLater(
        window.repositories.initializeRemote(
          profile.authority!,
          utf8.encode('/home/me/new'),
        ),
        throwsA(
          isA<RemoteWorkspaceException>().having(
            (error) => error.code,
            'code',
            RemoteFailureCode.writeNotPermitted,
          ),
        ),
      );
      expect(window.remote.sessions.initializations, isEmpty);

      // A host that does not offer initialization is refused the same way.
      await window.remote.service.setWritesAllowed(profile.id, true);
      await window.remote.service.disconnect(profile.id);
      window.remote.connections.results.add(
        const FakeHello(
          capabilities: {
            RemoteCapability.read,
            RemoteCapability.listDirectory,
            RemoteCapability.stage,
            RemoteCapability.commit,
          },
        ),
      );
      expect((await window.remote.service.connect(profile.id)).ready, isTrue);
      expect(window.remote.service.canInitialize(profile.id), isFalse);
      await expectLater(
        window.repositories.initializeRemote(
          profile.authority!,
          utf8.encode('/home/me/new'),
        ),
        throwsA(
          isA<RemoteWorkspaceException>().having(
            (error) => error.code,
            'code',
            RemoteFailureCode.writeNotPermitted,
          ),
        ),
      );
      expect(window.remote.sessions.initializations, isEmpty);
      await window.close();
    });

    test('a disconnected host is reported as such', () async {
      final window = await _window();
      final profile = await _host(window);
      await window.remote.service.disconnect(profile.id);
      await expectLater(
        window.repositories.initializeRemote(
          profile.authority!,
          utf8.encode('/home/me/new'),
        ),
        throwsA(
          isA<RemoteWorkspaceException>().having(
            (error) => error.code,
            'code',
            RemoteFailureCode.disconnected,
          ),
        ),
      );
      await window.close();
    });
  });

  group('initialize dialog', () {
    testWidgets('offers this computer and each host, and says why a host '
        'cannot be chosen', (tester) async {
      _desktop(tester);
      final window = await _window();
      final service = window.remote.service;
      final reading = await service.saveProfile(label: 'Reader', alias: 'r');
      final writing = await service.saveProfile(label: 'Writer', alias: 'w');
      await service.setWritesAllowed(writing.id, true);
      InitializeRepositoryChoice? choice;
      await tester.pumpWidget(
        _launcher(
          (context) async => choice = await showInitializeRepositoryDialog(
            context,
            remote: window.controller,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      MeridianSelect<String> location() =>
          tester.widget<MeridianSelect<String>>(
            find.byKey(const ValueKey('initialize-location')),
          );
      expect(location().values, ['', reading.id, writing.id]);
      expect(location().valueLabel(''), 'This computer');
      expect(location().valueLabel(writing.id), 'Writer');
      expect(
        find.text(
          'Create an empty Git repository. You choose its folder in the next step.',
        ),
        findsOne,
      );

      location().onChanged!(reading.id);
      await tester.pump();
      expect(
        find.text('Turn on Allow changes on this host to use this'),
        findsWidgets,
      );
      // The reason sits under the location, not beside a side label.
      expect(find.byKey(const ValueKey('initialize-blocked')), findsOne);
      expect(find.byType(MeridianSettingsRow), findsNothing);
      final blocked = tester.widget<MeridianButton>(
        find.byKey(const ValueKey('initialize-continue')),
      );
      expect(blocked.onPressed, isNull);

      location().onChanged!(writing.id);
      await tester.pump();
      expect(find.textContaining('type the path of a new one'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(MeridianCheckbox, 'Bare repository'),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('initialize-continue')));
      await _settle(tester);
      expect(choice?.profileId, writing.id);
      expect(choice?.bare, isTrue);
      await window.close();
    });

    testWidgets('without hosts only the repository type is asked', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      InitializeRepositoryChoice? choice;
      await tester.pumpWidget(
        _launcher(
          (context) async => choice = await showInitializeRepositoryDialog(
            context,
            remote: window.controller,
            initiallyBare: true,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('initialize-location')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('initialize-continue')));
      await _settle(tester);
      expect(choice?.profileId, isNull);
      expect(choice?.bare, isTrue);
      await window.close();
    });

    testWidgets('a new folder typed on the host is created and opened', (
      tester,
    ) async {
      _desktop(tester);
      final window = await _window();
      final profile = await _host(window);
      window.remote.sessions.list = (directory, cursor) {
        if (directory == null || utf8.decode(directory) == '/home/me') {
          return Future.value(
            fakePage('/home/me', [
              fakeEntry('project', RemoteEntryKind.directory),
            ], parent: '/home'),
          );
        }
        return Future.error(
          const RemoteWorkspaceException(RemoteFailureCode.pathNotFound),
        );
      };
      await tester.pumpWidget(
        _launcher(
          (context) => window.controller.initializeRemoteRepository(
            context,
            profile.id,
            bare: false,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launch')));
      await _settle(tester);
      expect(
        find.text('Choose where to create the repository on Workstation'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('remote-directory-path')),
        '/home/me/fresh',
      );
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(
        find.text('A new folder will be created at this path.'),
        findsWidgets,
      );
      await tester.tap(find.text('Initialize here'));
      await _settle(tester);
      final created = window.remote.sessions.initializations.single;
      expect(utf8.decode(created.path), '/home/me/fresh');
      expect(created.bare, isFalse);
      final tab = window.repositories.workspace.tabs.single;
      expect(tab.requestedIdentity?.remote, profile.authority);
      await tester.pumpWidget(const SizedBox());
      await window.close();
    });
  });
}
