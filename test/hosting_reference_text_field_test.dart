import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/repositories/hosting_repository.dart';
import 'package:gitlama/services/hosting_connection_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/widgets/hosting_reference_text_field.dart';

import 'support/fake_settings_repository.dart';
import 'support/fake_hosting_preset_defaults.dart';

void main() {
  testWidgets('keyboard selection inserts the exact provider reference', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await tester.pumpWidget(fixture.app(stale: true));
    final initialSize = tester.getSize(find.byType(HostingReferenceTextField));

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Fix 😀 #');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('hosting-reference-results')), findsOneWidget);
    expect(tester.getSize(find.byType(HostingReferenceTextField)), initialSize);
    expect(find.text('Cached'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(fixture.controller.text, 'Fix 😀 group/project#12');
    expect(
      fixture.controller.selection,
      TextSelection.collapsed(offset: fixture.controller.text.length),
    );
    expect(fixture.repository.appliedInsertions, ['group/project#12']);
    await fixture.dispose(tester);
  });

  testWidgets('empty cache still presents a non-resizing result state', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await tester.pumpWidget(fixture.app(references: const []));
    final initialSize = tester.getSize(find.byType(HostingReferenceTextField));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '#');
    await tester.pump();
    await tester.pump();

    expect(find.text('No matching pull requests or issues.'), findsOneWidget);
    expect(tester.getSize(find.byType(HostingReferenceTextField)), initialSize);
    await fixture.dispose(tester);
  });

  testWidgets('escape preserves the UTF-16 caret and composing hides results', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await tester.pumpWidget(fixture.app());
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Ä 😀 #1');
    await tester.pump();
    await tester.pump();
    final caret = fixture.controller.selection;

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const Key('hosting-reference-results')), findsNothing);
    expect(fixture.controller.selection, caret);

    fixture.controller.value = const TextEditingValue(
      text: '#',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 1),
    );
    await tester.pump();
    expect(find.byKey(const Key('hosting-reference-results')), findsNothing);
    await fixture.dispose(tester);
  });
}

final class _Fixture {
  _Fixture({
    required this.repository,
    required this.settings,
    required this.hosting,
  });

  final _ReferenceRepository repository;
  final SettingsService settings;
  final HostingConnectionService hosting;
  final controller = TextEditingController();

  static Future<_Fixture> create() async {
    final repository = _ReferenceRepository();
    final settings = SettingsService(FakeSettingsRepository());
    await settings.initialize();
    final hosting = HostingConnectionService(repository, settings);
    await hosting.initialize();
    return _Fixture(
      repository: repository,
      settings: settings,
      hosting: hosting,
    );
  }

  Widget app({
    bool stale = false,
    List<HostingRemoteReference> references = _references,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: HostingReferenceTextField(
            controller: controller,
            placeholder: 'Message',
            hosting: hosting,
            references: references,
            stale: stale,
          ),
        ),
      ),
    ),
  );

  static const _references = [
    HostingRemoteReference(
      stableId: 'issue:1',
      kind: HostingRemoteReferenceKind.issue,
      number: 1,
      title: 'First issue',
      insertion: '#1',
      webUrl: 'https://example.test/issues/1',
    ),
    HostingRemoteReference(
      stableId: 'merge:12',
      kind: HostingRemoteReferenceKind.changeRequest,
      number: 12,
      title: 'Cross-project merge request',
      insertion: 'group/project#12',
      webUrl: 'https://example.test/group/project/merge_requests/12',
    ),
  ];

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await hosting.dispose();
    await settings.dispose();
  }
}

final class _ReferenceRepository implements HostingRepository {
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

  final List<String> appliedInsertions = [];

  @override
  Future<HostingReferenceProjection?> projectReference({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int revision,
    required List<HostingRemoteReference> references,
    required bool stale,
  }) async {
    if (selectionBase != selectionExtent) return null;
    final hash = text.lastIndexOf('#', selectionExtent - 1);
    if (hash < 0 || (hash > 0 && text.codeUnitAt(hash - 1) == 0x5c)) {
      return null;
    }
    return HostingReferenceProjection(
      revision: revision,
      textHash: text.hashCode,
      replaceStart: hash,
      replaceEnd: selectionExtent,
      query: text.substring(hash + 1, selectionExtent),
      candidates: [
        for (final reference in references)
          HostingReferenceCandidate(
            stableId: reference.stableId,
            kind: reference.kind,
            number: reference.number,
            title: reference.title,
            insertion: reference.insertion,
            webUrl: reference.webUrl,
            stale: stale,
          ),
      ],
    );
  }

  @override
  Future<HostingReferenceApplyResult> applyReference({
    required String text,
    required int currentRevision,
    required HostingReferenceProjection projection,
    required String insertion,
  }) async {
    appliedInsertions.add(insertion);
    final next = text.replaceRange(
      projection.replaceStart,
      projection.replaceEnd,
      insertion,
    );
    return HostingReferenceApplyResult(
      text: next,
      caret: projection.replaceStart + insertion.length,
    );
  }

  @override
  Future<HostingConnection> validateConnection(HostingConnection value) async =>
      value;

  @override
  Future<HostingBindingResolution> resolveBinding({
    required List<HostingConnection> connections,
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  }) async =>
      const HostingBindingResolution(state: HostingBindingState.unmatched);

  @override
  Future<Uri> resourceLink({
    required HostingConnection connection,
    required String providerRepository,
    required HostingResourceKind kind,
    int? number,
  }) async => Uri.parse('https://example.test');

  @override
  Future<HostingCredentialState> credentialState(
    HostingConnection connection,
  ) async => HostingCredentialState.missing;

  @override
  Future<HostingCredentialState> removeCredential(
    HostingConnection connection,
  ) async => HostingCredentialState.missing;

  @override
  Future<HostingOAuthSnapshot> startAuthorization(
    HostingConnection connection,
  ) async =>
      const HostingOAuthSnapshot(requestId: 1, state: HostingOAuthState.failed);

  @override
  Future<HostingOAuthSnapshot?> pollAuthorization(int requestId) async => null;

  @override
  Future<bool> cancelAuthorization(int requestId) async => true;

  @override
  Future<HostingResourceSnapshot> startResourceRefresh({
    required HostingConnection connection,
    required String providerRepository,
    required int page,
    required bool manual,
  }) async => const HostingResourceSnapshot(
    requestId: 1,
    state: HostingResourceLoadState.ready,
    page: 1,
    resources: HostingResources(),
    stale: false,
    hasMore: false,
  );

  @override
  Future<HostingResourceSnapshot?> pollResourceRefresh(int requestId) async =>
      null;

  @override
  Future<bool> cancelResourceRefresh(int requestId) async => true;

  @override
  Future<HostingPullRequestLookupSnapshot> startPullRequestLookup({
    required HostingConnection connection,
    required String providerRepository,
    List<String> heads = const [],
    required List<String> branches,
    String? authoredBy,
  }) async =>
      throw const HostingResourceException(HostingResourceFailure.unavailable);

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
  }) async {}

  @override
  Future<void> shutdownRuntime() async {}
}
