import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/shell_scopes.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/app_command.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/app/workspace/settings_dialog.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/hosting_repository.dart';
import 'package:gitlama/services/hosting_connection_service.dart';
import 'package:gitlama/services/hosting_repository_session.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/widgets/hosting_integrations_section.dart';

import 'support/fake_settings_repository.dart';
import 'support/fake_repository_session_repository.dart';
import 'package:gitlama/app/workspace_shell.dart';
import 'package:gitlama/app/workspace/sidebar.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'support/fake_hosting_preset_defaults.dart';
import 'support/inert_runtime.dart';
import 'support/fake_recovery_repository.dart';

void main() {
  for (final remote in [false, true]) {
    testWidgets(
      'workspace loads local hosting for ${remote ? 'remote' : 'local'} repository with Integrations closed',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = await _Fixture.create(
          initial: _snapshot(
            requestId: 1,
            state: HostingResourceLoadState.ready,
            resources: HostingResources(
              changeRequests: [
                _pull('Automatic request', HostingCheckState.passing),
              ],
            ),
          ),
          connections: [
            _connection(
              capabilities: const [
                HostingCapability.changeRequests,
                HostingCapability.changeRequestCheckout,
                HostingCapability.checkRuns,
                HostingCapability.issues,
              ],
            ),
          ],
        );
        fixture.repository.headChecks = HostingCheckState.failing;
        fixture.hosting.setExpandedNodes(['changeRequests']);
        final repositories = fakeRepositorySessionService();
        final operations = OperationCenterService.empty();
        final identity = NativePathIdentity(
          platform: NativePathPlatform.unix,
          units: '/fixture'.codeUnits,
          remote: remote ? _authority : null,
        );
        final workspace = WorkspaceState(
          activeTabId: 1,
          tabs: [
            RepositoryTabState(
              id: 1,
              generation: 1,
              label: 'Fixture',
              phase: RepositoryTabPhase.open,
              requestedIdentity: identity,
              session: RepositorySessionState(
                identity: RepositorySessionIdentity(
                  nativeId: BigInt.one,
                  generation: 1,
                ),
                snapshot: RepositorySnapshot(
                  revision: BigInt.one,
                  phase: RepositoryPhase.ready,
                  refs: RepositoryRefs(
                    remotes: [
                      RepositoryRemote(
                        name: 'origin'.codeUnits,
                        displayUrl: 'ssh://git@github.com:9022/team/project.git'
                            .codeUnits,
                        branches: [
                          RepositoryReference(
                            name: 'main'.codeUnits,
                            target: _mainHead,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: WorkspaceShell(
              runtime: testRuntime(
                repositorySessions: repositories,
                settings: fixture.settings,
                recovery: fakeRecoveryService(fixture.settings),
                operationCenter: operations,
                shutdown: () async {},
                hosting: fixture.hosting,
              ),
              workspace: workspace,
              onOpenRepository: () {},
              onCloneRepository: () {},
              onInitializeRepository: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HostingIntegrationsSection), findsNothing);
        expect(fixture.repository.refreshStarts, 1);
        expect(
          // The sidebar reads the resources from the shell's hosting scope.
          HostingScope.of(
            tester.element(find.byType(WorkspaceSidebar)),
          ).resources.changeRequests.single.title,
          'Automatic request',
        );
        // The Integrations section lists the bound account and repository.
        final sidebar = find.byType(WorkspaceSidebar);
        expect(
          find.descendant(of: sidebar, matching: find.text('github:test')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebar, matching: find.text('team/project')),
          findsOneWidget,
        );
        // It shows the CI result of the commit origin/main points at.
        expect(fixture.repository.headLookups, [
          [_mainHead],
        ]);
        expect(
          find.descendant(
            of: sidebar,
            matching: find.byTooltip('main: Checks failed'),
          ),
          findsOneWidget,
        );
        expect(
          fixture.repository.resolvedRemotes.single.url,
          'ssh://git@github.com:9022/team/project.git',
        );
        expect(fixture.repository.resolvedConnections.single.id, 'github:test');
        tester
            .widget<WorkspaceSidebar>(sidebar)
            .onCommand(AppCommandId.showIntegrations);
        await tester.pumpAndSettle();
        expect(find.byType(HostingIntegrationsSection), findsOneWidget);
        expect(fixture.repository.refreshStarts, 1);
        if (remote) {
          // Provider API access works even with the SSH connection unavailable.
          final checkout = tester.widget<MeridianButton>(
            find.widgetWithText(MeridianButton, 'Check out'),
          );
          expect(checkout.onPressed, isNull);
        }
        tester
            .widget<WorkspaceSidebar>(sidebar)
            .onCommand(AppCommandId.hostingCreatePullRequest);
        await tester.pumpAndSettle();
        expect(fixture.repository.openedUrls, [
          Uri.parse('https://github.com/team/project/compare'),
        ]);
        tester
            .widget<WorkspaceSidebar>(sidebar)
            .onCommand(AppCommandId.showSettings);
        await tester.pumpAndSettle();
        final dialog = tester.widget<SettingsDialog>(
          find.byType(SettingsDialog),
        );
        expect(dialog.hostingRepository?.canonicalIdentity, identity);
        expect(dialog.repository?.canonicalIdentity, remote ? null : identity);
        if (remote) {
          await tester.tap(find.text('Repository link'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('hosting-provider-repository')),
            'team/override',
          );
          await tester.ensureVisible(find.text('Save binding override'));
          fixture.repository.nextStarts.add(
            _snapshot(requestId: 2, state: HostingResourceLoadState.ready),
          );
          await tester.tap(find.text('Save binding override'));
          await tester.pumpAndSettle();
          expect(
            fixture.hosting.bindingFor(identity)?.providerRepository,
            'team/override',
          );
          // The identical path on this computer must not inherit the binding.
          expect(
            fixture.hosting.bindingFor(
              NativePathIdentity(
                platform: identity.platform,
                units: identity.units,
              ),
            ),
            isNull,
          );
          expect(fixture.settings.current.hasValidRemoteData, isTrue);
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(fixture.repository.deactivated, hasLength(remote ? 2 : 1));
        await repositories.dispose();
        await operations.dispose();
        await fixture.dispose();
      },
    );
  }

  testWidgets(
    'repository hosting loads before panel opens and survives closing it',
    (tester) async {
      final fixture = await _Fixture.create(
        initial: _snapshot(
          requestId: 1,
          state: HostingResourceLoadState.ready,
          resources: HostingResources(
            changeRequests: [
              _pull('Loaded without panel', HostingCheckState.passing),
            ],
          ),
        ),
      );
      fixture.hosting.setExpandedNodes(['changeRequests']);
      final session = fixture.hosting.openRepositorySession();
      final identity = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: [1],
      );
      final remotes = [
        HostingRemote(
          name: 'origin'.codeUnits,
          url: 'ssh://git@github.com:9022/team/project.git',
        ),
      ];
      await session.update(identity, remotes);
      expect(session.binding?.state, HostingBindingState.bound);
      expect(
        session.resources.changeRequests.single.title,
        'Loaded without panel',
      );
      expect(fixture.repository.refreshStarts, 1);

      await tester.pumpWidget(
        fixture.app(session: session, showConfiguration: false),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Loaded without panel'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(fixture.repository.deactivated, isEmpty);
      expect(session.resources.changeRequests, hasLength(1));
      await session.update(identity, remotes);
      expect(fixture.repository.refreshStarts, 1);

      await tester.pumpWidget(
        fixture.app(session: session, showConfiguration: false),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Loaded without panel'), findsOneWidget);
      expect(fixture.repository.refreshStarts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await session.update(null, const []);
      expect(session.binding, isNull);
      expect(session.resources.changeRequests, isEmpty);
      expect(fixture.repository.deactivated, hasLength(1));
      session.dispose();
      await fixture.dispose();
    },
  );

  testWidgets(
    'repository change cancels late refresh and loads the new session',
    (tester) async {
      final fixture = await _Fixture.create(
        initial: _snapshot(
          requestId: 2,
          state: HostingResourceLoadState.ready,
          resources: HostingResources(
            changeRequests: [
              _pull('Current repository', HostingCheckState.passing),
            ],
          ),
        ),
      );
      final delayed = Completer<HostingResourceSnapshot>();
      fixture.repository.delayedStart = delayed;
      final session = fixture.hosting.openRepositorySession();
      final remotes = [
        HostingRemote(
          name: 'origin'.codeUnits,
          url: 'git@github.com:team/project.git',
        ),
      ];
      final first = session.update(
        NativePathIdentity(platform: NativePathPlatform.unix, units: [1]),
        remotes,
      );
      await tester.pump();
      expect(session.busy, isTrue);
      await session.update(
        NativePathIdentity(platform: NativePathPlatform.unix, units: [2]),
        remotes,
      );
      expect(
        session.resources.changeRequests.single.title,
        'Current repository',
      );
      delayed.complete(
        _snapshot(
          requestId: 1,
          state: HostingResourceLoadState.loading,
          resources: HostingResources(
            changeRequests: [
              _pull('Old repository', HostingCheckState.passing),
            ],
          ),
        ),
      );
      await first;
      expect(
        session.resources.changeRequests.single.title,
        'Current repository',
      );
      expect(session.busy, isFalse);
      expect(fixture.repository.canceled, [1]);
      session.dispose();
      await fixture.dispose();
    },
  );

  testWidgets('connection save rebinds a repository without a mounted panel', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    final session = fixture.hosting.openRepositorySession();
    await session.update(
      NativePathIdentity(platform: NativePathPlatform.unix, units: [1]),
      [
        HostingRemote(
          name: 'origin'.codeUnits,
          url: 'git@github.com:team/project.git',
        ),
      ],
    );
    fixture.repository.nextStarts.add(
      _snapshot(requestId: 2, state: HostingResourceLoadState.ready),
    );
    await fixture.hosting.saveConnection(_connection());
    await tester.pump();
    expect(fixture.repository.bindingResolutions, 2);
    expect(fixture.repository.refreshStarts, 2);
    session.dispose();
    await fixture.dispose();
  });

  testWidgets('saving a connection rechecks an open repository binding', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
      connections: const [],
    );
    await tester.pumpWidget(fixture.app(showResources: false));
    await tester.pump();
    expect(find.byKey(const Key('hosting-binding-connection')), findsNothing);
    final initialResolutions = fixture.repository.bindingResolutions;

    await fixture.hosting.saveConnection(_connection());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hosting-binding-connection')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('hosting-provider-repository')),
          )
          .controller!
          .text,
      'team/project',
    );
    expect(
      fixture.repository.bindingResolutions,
      greaterThan(initialResolutions),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('settings and repository views show separate hosting controls', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false),
    );
    await tester.pump();
    expect(find.byKey(const Key('hosting-add-connection')), findsOneWidget);
    expect(find.byKey(const Key('hosting-resource-filter')), findsNothing);
    expect(find.byKey(const Key('hosting-binding-connection')), findsNothing);

    await tester.pumpWidget(
      fixture.app(showAccounts: false, showResources: false),
    );
    await tester.pump();
    expect(find.byKey(const Key('hosting-add-connection')), findsNothing);
    expect(find.byKey(const Key('hosting-binding-connection')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(fixture.repository.deactivated, isEmpty);

    await tester.pumpWidget(fixture.app(showConfiguration: false));
    await tester.pump();
    expect(find.byKey(const Key('hosting-add-connection')), findsNothing);
    expect(find.byKey(const Key('hosting-resource-filter')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('hosting labels clear their fields at narrow German text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(
        showBinding: false,
        showResources: false,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('de'),
        textScale: 1.3,
      ),
    );
    await tester.tap(find.text('Verbindung hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hosting-web-url')), findsNothing);

    final name = find.text('Verbindungsname');
    final nameField = find.byKey(const Key('hosting-connection-id'));
    expect(
      tester.getBottomLeft(name).dy,
      lessThan(tester.getTopLeft(nameField).dy),
    );
    final oauth = find.text('OAuth-Client-ID');
    await tester.ensureVisible(oauth);
    await tester.pump();
    expect(
      tester.getBottomLeft(oauth).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('hosting-oauth-client-id'))).dy,
      ),
    );

    await tester.tap(find.byType(MeridianSelect<HostingPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitLab Self-Managed').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hosting-web-url')), findsOneWidget);
    expect(find.byKey(const Key('hosting-api-url')), findsOneWidget);
    for (final (label, key) in [
      ('Web-Basis-URL', const Key('hosting-web-url')),
      ('API-Basis-URL', const Key('hosting-api-url')),
    ]) {
      final labelFinder = find.text(label);
      await tester.ensureVisible(labelFinder);
      await tester.pump();
      expect(
        tester.getBottomLeft(labelFinder).dy,
        lessThan(tester.getTopLeft(find.byKey(key)).dy),
      );
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets(
    'loading keeps stale rows and filter expansion does not overwrite preference',
    (tester) async {
      final fixture = await _Fixture.create(
        initial: _snapshot(
          requestId: 1,
          state: HostingResourceLoadState.loading,
          stale: true,
          resources: HostingResources(
            changeRequests: [_pull('Keep visible', HostingCheckState.unknown)],
            issues: [_issue('Separate issue')],
          ),
        ),
      );
      await tester.pumpWidget(fixture.app());
      await tester.pump();

      expect(find.byType(MeridianProgressBar), findsOneWidget);
      expect(
        find.text('Refreshing; cached results remain available.'),
        findsOneWidget,
      );
      expect(fixture.settings.current.hostingExpandedNodes, isEmpty);

      await tester.enterText(
        find.byKey(const Key('hosting-resource-filter')),
        'keep',
      );
      await tester.pump();
      expect(find.textContaining('Keep visible'), findsOneWidget);
      expect(fixture.settings.current.hostingExpandedNodes, isEmpty);

      await tester.enterText(
        find.byKey(const Key('hosting-resource-filter')),
        '',
      );
      await tester.pump();
      final pullGroup = find.text('Pull requests');
      await tester.ensureVisible(pullGroup);
      await tester.pump();
      await tester.tap(pullGroup);
      await tester.pump();
      expect(fixture.settings.current.hostingExpandedNodes, ['changeRequests']);
      await tester.tap(pullGroup);
      await tester.pump();
      expect(fixture.settings.current.hostingExpandedNodes, isEmpty);
      expect(find.byType(MeridianProgressBar), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(fixture.repository.deactivated, [('github:test', 'team/project')]);
      await fixture.dispose();
    },
  );

  testWidgets('repository switch rejects late resource publication', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(
        requestId: 1,
        state: HostingResourceLoadState.loading,
        resources: HostingResources(
          changeRequests: [_pull('Old request', HostingCheckState.pending)],
        ),
      ),
    );
    fixture.repository.nextStarts.add(
      _snapshot(
        requestId: 2,
        state: HostingResourceLoadState.ready,
        resources: HostingResources(
          changeRequests: [_pull('New request', HostingCheckState.passing)],
        ),
      ),
    );
    await tester.pumpWidget(fixture.app(repositoryUnit: 1));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('hosting-resource-filter')),
      'request',
    );
    await tester.pump();
    expect(find.textContaining('Old request'), findsOneWidget);

    await tester.pumpWidget(fixture.app(repositoryUnit: 2));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('hosting-resource-filter')),
      'request',
    );
    await tester.pump();
    expect(find.textContaining('Old request'), findsNothing);
    expect(find.textContaining('New request'), findsOneWidget);
    expect(
      fixture.repository.deactivated,
      contains(('github:test', 'team/project')),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('authorization opens the browser and keeps a retry action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    expect(find.text('No provider resources found.'), findsOneWidget);

    await tester.tap(find.text('Add connection'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const Key('hosting-connection-id')),
      'github:new',
    );
    await tester.enterText(
      find.byKey(const Key('hosting-oauth-client-id')),
      'public-client',
    );
    final authorize = find.widgetWithText(MeridianButton, 'Save and authorize');
    tester.widget<MeridianButton>(authorize).onPressed!();
    await tester.pump();

    expect(find.text('Device code: ABCD-EFGH'), findsOneWidget);
    expect(fixture.openedUrls, ['https://github.com/login/device']);
    await tester.tap(find.text('Open in browser'));
    await tester.pump();
    expect(fixture.openedUrls, [
      'https://github.com/login/device',
      'https://github.com/login/device',
    ]);

    final semantics = tester.getSemantics(find.bySemanticsLabel('Refresh'));
    expect(
      semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('completed OAuth connection closes and clears the form', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false),
    );
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hosting-connection-id')),
      'Work Forgejo',
    );
    await tester.enterText(
      find.byKey(const Key('hosting-oauth-client-id')),
      'public-client',
    );
    fixture.repository.completeAuthorization = true;
    tester
        .widget<MeridianButton>(
          find.widgetWithText(MeridianButton, 'Save and authorize'),
        )
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      fixture.hosting.connections.any((item) => item.id == 'Work Forgejo'),
      isTrue,
    );
    expect(find.byKey(const Key('hosting-connection-id')), findsNothing);
    expect(find.text('Device code: ABCD-EFGH'), findsNothing);
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hosting-connection-id')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('Tab stays in the connection form through its save action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false, withSidebar: true),
    );
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MeridianSelect<HostingPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgejo').last);
    await tester.pumpAndSettle();
    final name = find.byKey(const Key('hosting-connection-id'));
    await tester.ensureVisible(name);
    await tester.tap(name);
    await tester.pump();
    for (final field in [
      const Key('hosting-web-url'),
      const Key('hosting-api-url'),
      const Key('hosting-oauth-client-id'),
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(field),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasPrimaryFocus,
        isTrue,
        reason: 'Tab should focus $field',
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focusedWidget = FocusManager.instance.primaryFocus!.context!.widget;
    expect(
      find.ancestor(
        of: find.byWidget(focusedWidget),
        matching: find.widgetWithText(MeridianButton, 'Save and authorize'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('Forgejo URL derives its API endpoint and guide explains setup', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false),
    );
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MeridianSelect<HostingPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgejo').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hosting-web-url')),
      'forge.example.test',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hosting-api-url')))
          .controller!
          .text,
      'https://forge.example.test/api/v1',
    );

    await tester.tap(find.byKey(const Key('hosting-setup-guide')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Settings → Applications'), findsOneWidget);
    expect(
      find.textContaining('Disable “Confidential Client”'),
      findsOneWidget,
    );
    expect(find.textContaining('127.0.0.1:49351'), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();

    final authorize = find.widgetWithText(MeridianButton, 'Save and authorize');
    tester.widget<MeridianButton>(authorize).onPressed!();
    await tester.pump();
    expect(find.text('Enter a connection name.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('A self-hosted server must be an https origin', (tester) async {
    // Regression: the form accepted http://localhost, which a saved connection
    // can never use; the native preset rules decide now.
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false),
    );
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MeridianSelect<HostingPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgejo').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hosting-web-url')),
      'http://localhost:3000',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hosting-api-url')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('hosting-connection-id')),
      'forge',
    );
    await tester.enterText(
      find.byKey(const Key('hosting-oauth-client-id')),
      'client',
    );
    final authorize = find.widgetWithText(MeridianButton, 'Save and authorize');
    await tester.ensureVisible(authorize);
    tester.widget<MeridianButton>(authorize).onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a valid server URL to fill in the API URL.'),
      findsOneWidget,
    );
    expect(fixture.repository.presetDefaultRequests.last, (
      HostingPreset.forgejo,
      'http://localhost:3000',
    ));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('GitHub Enterprise derives the API endpoint of its server kind', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false),
    );
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MeridianSelect<HostingPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub Enterprise Server').last);
    await tester.pumpAndSettle();
    String api() => tester
        .widget<TextField>(find.byKey(const Key('hosting-api-url')))
        .controller!
        .text;

    await tester.enterText(
      find.byKey(const Key('hosting-web-url')),
      'github.example.test',
    );
    await tester.pump();
    expect(api(), 'https://github.example.test/api/v3');
    // An Enterprise Cloud tenant serves its API from a sibling host.
    await tester.enterText(
      find.byKey(const Key('hosting-web-url')),
      'https://octo.ghe.com/',
    );
    await tester.pump();
    expect(api(), 'https://api.octo.ghe.com');
    await tester.enterText(
      find.byKey(const Key('hosting-web-url')),
      'notghe.com',
    );
    await tester.pump();
    expect(api(), 'https://notghe.com/api/v3');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('GitLab CLI uses host credentials without an OAuth application', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(
      fixture.app(showBinding: false, showResources: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MeridianSelect<HostingPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitLab').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byType(MeridianSelect<HostingAuthentication>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MeridianSelect<HostingAuthentication>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitLab CLI').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hosting-oauth-client-id')), findsNothing);
    await tester.tap(find.byKey(const Key('hosting-setup-guide')));
    await tester.pumpAndSettle();
    expect(find.textContaining('glab auth login'), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hosting-connection-id')),
      'Work GitLab',
    );
    await tester.ensureVisible(find.text('Connect with GitLab CLI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect with GitLab CLI'));
    await tester.pumpAndSettle();
    final connected = fixture.hosting.connections.singleWhere(
      (connection) => connection.id == 'Work GitLab',
    );
    expect(connected.authentication, HostingAuthentication.gitLabCli);
    expect(connected.oauthClientId, isEmpty);
    expect(find.byKey(const Key('hosting-connection-id')), findsNothing);
    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hosting-connection-id')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  testWidgets('create pull request opens the canonical provider comparison', (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      initial: _snapshot(requestId: 1, state: HostingResourceLoadState.ready),
    );
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    fixture.changeRequests.add(null);
    await tester.pump();
    expect(fixture.openedUrls, ['https://github.com/team/project/compare']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });

  for (final failure in const [
    HostingResourceFailure.unavailable,
    HostingResourceFailure.permissionDenied,
  ]) {
    testWidgets('${failure.name} is selectable and does not become empty', (
      tester,
    ) async {
      final fixture = await _Fixture.create(
        initial: HostingResourceSnapshot(
          requestId: 1,
          state: HostingResourceLoadState.failed,
          page: 1,
          resources: const HostingResources(),
          stale: false,
          hasMore: false,
          failure: failure,
        ),
      );
      await tester.pumpWidget(fixture.app());
      await tester.pump();

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining(failure.name), findsOneWidget);
      expect(find.text('No provider resources found.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await fixture.dispose();
    });
  }

  for (final locale in [const Locale('en'), const Locale('de')]) {
    testWidgets(
      'OAuth client rejection explains public-client setup in ${locale.languageCode}',
      (tester) async {
        final fixture = await _Fixture.create(
          initial: _snapshot(
            requestId: 1,
            state: HostingResourceLoadState.ready,
          ),
        );
        fixture.repository.oauthFailure = HostingOAuthFailure.invalidConnection;
        await tester.pumpWidget(
          fixture.app(showBinding: false, showResources: false, locale: locale),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(HostingIntegrationsSection)),
        );
        await tester.tap(find.text(l10n.hostingAddConnection));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('hosting-connection-id')),
          'test-connection',
        );
        await tester.enterText(
          find.byKey(const Key('hosting-oauth-client-id')),
          'test-client',
        );
        tester
            .widget<MeridianButton>(
              find.widgetWithText(MeridianButton, l10n.hostingSaveAuthorize),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        expect(
          find.textContaining(l10n.hostingOAuthClientRejected),
          findsOneWidget,
        );
        expect(find.textContaining('invalidConnection'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await fixture.dispose();
      },
    );
  }

  testWidgets('a transport failure names its cause', (tester) async {
    final fixture = await _Fixture.create(
      initial: const HostingResourceSnapshot(
        requestId: 1,
        state: HostingResourceLoadState.failed,
        page: 1,
        resources: HostingResources(),
        stale: false,
        hasMore: false,
        failure: HostingResourceFailure.network,
      ),
    );
    await tester.pumpWidget(fixture.app());
    await tester.pump();

    expect(
      find.text(
        'Provider request failed: The server could not be reached. '
        'Check the network connection, VPN and proxy.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });
}

const _authority = RemoteAuthority(
  profileId: '00000000-0000-4000-8000-000000000000',
  storeId: '0123456789abcdef0123456789abcdef',
  accountUid: '1000',
);

final class _Fixture {
  _Fixture(this.settings, this.hosting, this.repository);

  final SettingsService settings;
  final HostingConnectionService hosting;
  final _HostingRepository repository;
  final GlobalKey<HostingIntegrationsSectionState> sectionKey =
      GlobalKey<HostingIntegrationsSectionState>();
  final List<String> openedUrls = [];
  final StreamController<void> changeRequests = StreamController.broadcast(
    sync: true,
  );

  static Future<_Fixture> create({
    required HostingResourceSnapshot initial,
    List<HostingConnection>? connections,
  }) async {
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(
            hostingConnections: connections ?? [_connection()],
          ),
        ),
      ),
    );
    await settings.initialize();
    final repository = _HostingRepository()..nextStarts.add(initial);
    final hosting = HostingConnectionService(repository, settings);
    await hosting.initialize();
    return _Fixture(settings, hosting, repository);
  }

  Widget app({
    HostingRepositorySession? session,
    int repositoryUnit = 1,
    bool showConfiguration = true,
    bool showAccounts = true,
    bool showBinding = true,
    bool showResources = true,
    bool withSidebar = false,
    ThemeData? theme,
    Locale? locale,
    double textScale = 1,
  }) {
    final section = HostingIntegrationsSection(
      key: sectionKey,
      createChangeRequests: changeRequests.stream,
      session: session,
      showConfiguration: showConfiguration,
      showAccounts: showAccounts,
      showBinding: showBinding,
      showResources: showResources,
      hosting: hosting,
      repository: NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: [repositoryUnit],
      ),
      remotes: [
        HostingRemote(
          name: 'origin'.codeUnits,
          url: 'https://github.com/team/project.git',
        ),
      ],
      onOpenUrl: (url) async => openedUrls.add(url),
      onCheckout: (_) {},
      onResourcesChanged: (_, _, _) {},
    );
    return MaterialApp(
      theme: theme ?? buildAppTheme(Brightness.light),
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: withSidebar
            ? Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: Column(
                      children: [
                        for (final label in [
                          'Appearance',
                          'Git',
                          'Diff renderer',
                        ])
                          TextButton(onPressed: () {}, child: Text(label)),
                      ],
                    ),
                  ),
                  Expanded(child: ListView(children: [section])),
                ],
              )
            : ListView(children: [section]),
      ),
    );
  }

  Future<void> dispose() async {
    await hosting.dispose();
    await settings.dispose();
    await changeRequests.close();
  }
}

const _mainHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

HostingConnection _connection({
  List<HostingCapability> capabilities = const [
    HostingCapability.changeRequests,
    HostingCapability.changeRequestCheckout,
    HostingCapability.issues,
  ],
}) => HostingConnection(
  id: 'github:test',
  preset: HostingPreset.gitHub,
  login: 'tester',
  webBaseUrl: 'https://github.com',
  apiBaseUrl: 'https://api.github.com',
  oauthClientId: 'public-client',
  enabled: true,
  capabilities: capabilities,
  credentialIdentity: 'credential:github:test',
);

HostingResourceSnapshot _snapshot({
  required int requestId,
  required HostingResourceLoadState state,
  HostingResources resources = const HostingResources(),
  bool stale = false,
}) => HostingResourceSnapshot(
  requestId: requestId,
  state: state,
  page: 1,
  resources: resources,
  stale: stale,
  hasMore: false,
);

HostingChangeRequest _pull(String title, HostingCheckState state) =>
    HostingChangeRequest(
      stableId: title,
      number: 1,
      title: title,
      author: 'alice',
      state: HostingChangeRequestState.open,
      draft: false,
      sourceRepository: 'team/project',
      sourceBranch: 'topic',
      targetRepository: 'team/project',
      targetBranch: 'main',
      headSha: 'abc123',
      webUrl: 'https://github.com/team/project/pull/1',
      reviewSummary: HostingReviewSummary.unknown,
      mergeability: HostingMergeability.unknown,
      checks: HostingCheckSummary(state: state),
    );

HostingIssue _issue(String title) => HostingIssue(
  stableId: title,
  number: 2,
  title: title,
  state: HostingIssueState.open,
  author: 'bob',
  assignees: const [],
  labels: const [],
  private: false,
  updatedAt: '',
  webUrl: 'https://github.com/team/project/issues/2',
);

final class _HostingRepository implements HostingRepository {
  final List<(HostingPreset, String?)> presetDefaultRequests = [];

  /// The CI result lookups answer for every head; without it they fail.
  HostingCheckState? headChecks;
  final List<List<String>> headLookups = [];

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

  final List<Uri> openedUrls = [];

  @override
  Future<void> openBrowser(Uri url) async => openedUrls.add(url);

  final List<HostingResourceSnapshot> nextStarts = [];
  final List<(String, String)> deactivated = [];
  var bindingResolutions = 0;
  List<HostingRemote> resolvedRemotes = [];
  List<HostingConnection> resolvedConnections = [];
  var refreshStarts = 0;
  Completer<HostingResourceSnapshot>? delayedStart;
  final List<int> canceled = [];
  var nextOAuthId = 100;
  HostingOAuthFailure? oauthFailure;
  bool completeAuthorization = false;

  @override
  Future<HostingConnection> validateConnection(
    HostingConnection connection,
  ) async => connection;

  @override
  Future<HostingBindingResolution> resolveBinding({
    required List<HostingConnection> connections,
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  }) async {
    bindingResolutions += 1;
    resolvedRemotes = remotes;
    resolvedConnections = connections;
    return const HostingBindingResolution(
      state: HostingBindingState.bound,
      remote: [111, 114, 105, 103, 105, 110],
      connectionId: 'github:test',
      providerRepository: 'team/project',
      webUrl: 'https://github.com/team/project',
    );
  }

  @override
  Future<Uri> resourceLink({
    required HostingConnection connection,
    required String providerRepository,
    required HostingResourceKind kind,
    int? number,
  }) async => Uri.parse('https://github.com/team/project/compare');

  @override
  Future<HostingCredentialState> credentialState(
    HostingConnection connection,
  ) async => HostingCredentialState.available;

  @override
  Future<HostingCredentialState> removeCredential(
    HostingConnection connection,
  ) async => HostingCredentialState.missing;

  @override
  Future<HostingOAuthSnapshot> startAuthorization(
    HostingConnection connection,
  ) async => oauthFailure != null
      ? HostingOAuthSnapshot(
          requestId: nextOAuthId++,
          state: HostingOAuthState.failed,
          failure: oauthFailure,
        )
      : connection.authentication != HostingAuthentication.oauth
      ? HostingOAuthSnapshot(
          requestId: nextOAuthId++,
          state: HostingOAuthState.succeeded,
          authenticatedLogin: 'fixture-user',
        )
      : HostingOAuthSnapshot(
          requestId: nextOAuthId++,
          state: HostingOAuthState.waitingForDevice,
          browserUrl: Uri.parse('https://github.com/login/device'),
          userCode: 'ABCD-EFGH',
        );

  @override
  Future<HostingOAuthSnapshot?> pollAuthorization(int requestId) async =>
      completeAuthorization
      ? HostingOAuthSnapshot(
          requestId: requestId,
          state: HostingOAuthState.succeeded,
          authenticatedLogin: 'fixture-user',
        )
      : HostingOAuthSnapshot(
          requestId: requestId,
          state: HostingOAuthState.waitingForDevice,
          browserUrl: Uri.parse('https://github.com/login/device'),
          userCode: 'ABCD-EFGH',
        );

  @override
  Future<bool> cancelAuthorization(int requestId) async => true;

  @override
  Future<HostingResourceSnapshot> startResourceRefresh({
    required HostingConnection connection,
    required String providerRepository,
    required int page,
    required bool manual,
  }) async {
    refreshStarts++;
    final delayed = delayedStart;
    delayedStart = null;
    return delayed == null ? nextStarts.removeAt(0) : await delayed.future;
  }

  @override
  Future<HostingResourceSnapshot?> pollResourceRefresh(int requestId) async =>
      null;

  @override
  Future<bool> cancelResourceRefresh(int requestId) async {
    canceled.add(requestId);
    return true;
  }

  @override
  Future<HostingPullRequestLookupSnapshot> startPullRequestLookup({
    required HostingConnection connection,
    required String providerRepository,
    List<String> heads = const [],
    required List<String> branches,
    String? authoredBy,
  }) async {
    final checks = headChecks;
    if (checks == null) {
      throw const HostingResourceException(HostingResourceFailure.unavailable);
    }
    headLookups.add(heads);
    return HostingPullRequestLookupSnapshot(
      requestId: 1,
      state: HostingResourceLoadState.ready,
      heads: {for (final head in heads) head: checks},
      branches: {for (final branch in branches) branch: const []},
      authored: authoredBy == null ? null : const [],
    );
  }

  @override
  Future<HostingPullRequestLookupSnapshot?> pollPullRequestLookup(
    int requestId,
  ) async => null;

  @override
  Future<bool> cancelPullRequestLookup(int requestId) async => true;

  @override
  Future<void> deactivateResources({
    required String connectionId,
    required String providerRepository,
  }) async => deactivated.add((connectionId, providerRepository));

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

  @override
  Future<void> shutdownRuntime() async {}
}
