import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/integrations_panel.dart';
import 'package:gitlama/app/workspace/named_snapshots.dart';
import 'package:gitlama/app/workspace/power_tools.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/integrations.dart';
import 'package:gitlama/models/named_snapshot.dart';
import 'package:gitlama/models/power_tools.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/integration_repository.dart';
import 'package:gitlama/repositories/named_snapshot_repository.dart';
import 'package:gitlama/repositories/power_tools_repository.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/widgets/gitlama_list_well.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

final _unix = NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: '/usr/bin/tool'.codeUnits,
);

class _PanelRepository extends FakeRepositorySessionRepository
    implements
        PowerToolsRepositorySessionRepository,
        NamedSnapshotRepositorySessionRepository,
        IntegrationRepositorySessionRepository {
  _PanelRepository({this.discovered = const []}) : super(null);

  final List<IntegrationCandidate> discovered;
  BisectAction? previewed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<BigInt> startDiffContentSearch(
    RepositorySessionIdentity identity, {
    required String query,
    required int maximumCommits,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
    bool otherRefs = false,
  }) async => BigInt.from(201);

  @override
  Future<DiffContentSearchResult> pollDiffContentSearch(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const DiffContentSearchResult(
    state: PowerJobState.completed,
    matches: [
      DiffContentMatch(
        commit: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
        summary: 'Parse remote URLs',
      ),
    ],
    examinedCommits: 12000,
    completeness: SearchCompleteness.complete,
    activityIds: [],
  );

  @override
  Future<BigInt> startRepositoryStatistics(
    RepositorySessionIdentity identity,
  ) async => BigInt.from(202);

  @override
  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => const RepositoryStatisticsResult(
    state: PowerJobState.completed,
    commitCount: 18342,
    localBranchCount: 12,
    tagCount: 87,
    changedPathCount: 2410,
    incomplete: true,
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
  }) async {
    previewed = action;
    return BisectPreview(
      token: BigInt.from(203),
      action: action,
      arguments: const ['bisect', 'start'],
    );
  }

  @override
  Future<bool> cancelBisectPreview(
    RepositorySessionIdentity identity,
    BigInt token,
  ) async => true;

  @override
  Future<NamedSnapshotPage> namedSnapshots(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximum = 32,
  }) async => NamedSnapshotPage(
    total: 1,
    entries: [
      NamedSnapshot(
        id: BigInt.one,
        name: 'Try the new layout',
        createdAtUnixMs: BigInt.zero,
        baseOid: 'a1b2c3d4e5f6a7b8',
        objectId: 'f1e2d3c4b5a6f7e8',
        stagedCount: 2,
        unstagedCount: 1500,
        untrackedCount: 1,
        includesUntracked: true,
        keepsIndex: false,
        state: NamedSnapshotState.ready,
      ),
    ],
  );

  @override
  Future<List<IntegrationCandidate>> discoverIntegrations(
    IntegrationKind kind,
  ) async => discovered.where((value) => value.kind == kind).toList();
}

Future<RepositorySessionService> _service(
  WidgetTester tester,
  _PanelRepository repository,
) async {
  final service = RepositorySessionService(repository);
  await tester.runAsync(() => service.open('/repository'));
  return service;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(
        child: Align(alignment: Alignment.topRight, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('repository tools: headed sections, facts and counts', (
    tester,
  ) async {
    final repository = _PanelRepository();
    final service = await _service(tester, repository);
    await _pump(
      tester,
      PowerToolsPanel(repositories: service, onClose: () {}, onReveal: (_) {}),
    );
    for (final title in [
      'Search changes',
      'Repository statistics',
      'Find a breaking commit',
    ]) {
      expect(
        find.widgetWithText(MeridianSectionHeader, title),
        findsOneWidget,
        reason: title,
      );
    }
    expect(find.textContaining('up to 10,000 commits'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('power-search-query')),
      'parse',
    );
    await tester.tap(find.byKey(const Key('power-search-start')));
    await tester.pumpAndSettle();
    expect(
      find.text('1 commit found · 12,000 commits searched'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GitLamaListWell),
        matching: find.text('Parse remote URLs'),
      ),
      findsOneWidget,
    );
    // The commit ID is shortened for reading.
    expect(find.text('a1b2c3d4e5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('power-statistics-load')));
    await tester.pumpAndSettle();
    final facts = find.byKey(const Key('power-statistics-facts'));
    expect(
      find.descendant(of: facts, matching: find.text('18,342')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: facts, matching: find.text('Files changed')),
      findsOneWidget,
    );
    expect(find.textContaining('may be too low'), findsOneWidget);
  });

  testWidgets('starting the search asks with an action title', (tester) async {
    final repository = _PanelRepository();
    final service = await _service(tester, repository);
    await _pump(
      tester,
      PowerToolsPanel(repositories: service, onClose: () {}, onReveal: (_) {}),
    );
    expect(find.textContaining('Name a commit that works'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('power-bisect-start')));
    await tester.tap(find.byKey(const Key('power-bisect-start')));
    // The progress bar runs while the question is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.previewed, BisectAction.start);
    expect(
      find.text('Start the search for the breaking commit?'),
      findsOneWidget,
    );
    expect(find.text('Review Git command'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('snapshot details are facts, in German too', (tester) async {
    final service = await _service(tester, _PanelRepository());
    await _pump(
      tester,
      NamedSnapshotsPanel(
        repositories: service,
        onClose: () {},
        onConflict: () {},
      ),
      locale: const Locale('de'),
    );
    tester
        .widget<NativeMenuButton<String>>(find.byType(NativeMenuButton<String>))
        .onSelected('inspect');
    await tester.pumpAndSettle();
    final facts = find.byKey(const Key('named-snapshot-facts'));
    expect(facts, findsOneWidget);
    for (final text in [
      'Branch',
      'Kein Branch',
      'a1b2c3d4',
      'Neue Dateien',
      '1.500',
    ]) {
      expect(
        find.descendant(of: facts, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('custom commands list tools in wells with plain labels', (
    tester,
  ) async {
    final repository = _PanelRepository(
      discovered: [
        IntegrationCandidate(
          id: 'code',
          kind: IntegrationKind.editor,
          executable: _unix,
          launchMode: IntegrationLaunchMode.detached,
        ),
      ],
    );
    final service = await _service(tester, repository);
    final settings = fakeSettingsService();
    await settings.initialize();
    await _pump(
      tester,
      SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: IntegrationsPanel(
            embedded: true,
            repositories: service,
            focusAddForm: false,
            settings: settings,
            hosting: null,
            hostingReview: null,
            active: null,
            onResourcesChanged: (_, _, _) {},
            onCheckout: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Found on this computer'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GitLamaListWell),
        matching: find.text('code'),
      ),
      findsOneWidget,
    );
    expect(find.text("You haven't added any yet."), findsOneWidget);
    for (final label in [
      'Use as',
      'Name',
      'Program',
      'Run through the system shell',
      'Ask before each run',
      'Wait until it finishes',
      'Time limit (seconds)',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Labels sit above their fields.
    expect(
      tester.getTopLeft(find.text('Program')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('integration-executable'))).dy,
      ),
    );
  });
}
