import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/widgets/gitlama_file_row.dart';
import 'package:flutter/gestures.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/hosting_repository.dart';
import 'package:gitlama/repositories/hosting_review_repository.dart';
import 'package:gitlama/services/hosting_connection_service.dart';
import 'package:gitlama/services/hosting_review_service.dart';
import 'package:gitlama/services/settings_service.dart';
import 'package:gitlama/widgets/hosting_review_workspace.dart';

import 'support/native_menu_model.dart';

import 'support/fake_settings_repository.dart';
import 'support/fake_hosting_preset_defaults.dart';

void main() {
  testWidgets('compact review exposes comments in a floating drawer', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    expect(find.text('old comment'), findsNothing);
    await tester.tap(find.byTooltip('Review comments'));
    await tester.pumpAndSettle();
    expect(find.text('old comment'), findsOneWidget);
    expect(find.text('Outdated'), findsOneWidget);
    await fixture.dispose(tester);
  });

  testWidgets('review never submits before matching explicit authorization', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await _pumpReview(tester, fixture);

    expect(find.text('old comment'), findsOneWidget);
    expect(find.text('Re-anchor'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hosting-review-body')),
      'approved body',
    );
    await tester.tap(find.byKey(const Key('hosting-review-preview')));
    await tester.pumpAndSettle();

    // The confirmation says what happens in words; the exact request the
    // authorization binds sits behind Request details.
    expect(find.text('Submit this review?'), findsOneWidget);
    expect(find.text('GitLama posts your review to #7.'), findsOneWidget);
    expect(find.text('Line comments'), findsOneWidget);
    await tester.tap(find.text('Request details'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('/repos/team/project/pulls/7/reviews'),
      findsOneWidget,
    );
    expect(fixture.reviewRepository.submitCalls, 0);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(fixture.reviewRepository.submitCalls, 0);

    await tester.tap(find.byKey(const Key('hosting-review-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MeridianButton, 'Submit review').last);
    await tester.pumpAndSettle();

    expect(fixture.reviewRepository.submitCalls, 1);
    expect(fixture.reviewRepository.lastSubmitted?.body, 'approved body');
    expect(fixture.reviewRepository.deletedKeys, [fixture.draftKey]);
    await fixture.dispose(tester);
  });

  testWidgets(
    'uncertain submission preserves durable draft and re-anchor text',
    (tester) async {
      final fixture = await _Fixture.create(
        submitResult: const HostingReviewSubmitResult(
          state: HostingReviewSubmitState.uncertain,
          failure: HostingReviewFailure.uncertain,
        ),
      );
      await _pumpReview(tester, fixture);

      await tester.tap(find.text('Re-anchor'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('hosting-review-inline-body')),
            )
            .controller!
            .text,
        'old comment',
      );
      await tester.tap(find.text('Add to review'));
      await tester.pumpAndSettle();
      expect(find.text('src/lib.rs:1'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('hosting-review-body')),
        'do not lose me',
      );
      await tester.tap(find.byKey(const Key('hosting-review-preview')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MeridianButton, 'Submit review').last,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('uncertain'), findsOneWidget);
      expect(fixture.reviewRepository.submitCalls, 1);
      expect(fixture.reviewRepository.deletedKeys, isEmpty);
      expect(fixture.reviewRepository.savedDrafts.last.body, 'do not lose me');
      expect(
        fixture.reviewRepository.savedDrafts.last.inlineComments,
        hasLength(1),
      );
      await fixture.dispose(tester);
    },
  );

  testWidgets('loads the next review page without replacing current rows', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await _pumpReview(tester, fixture);

    await tester.tap(find.byKey(const Key('hosting-review-load-more')));
    await tester.pumpAndSettle();

    expect(fixture.reviewRepository.loadedPages, [null, 'page:2']);
    expect(find.text('src/lib.rs'), findsOneWidget);
    expect(find.text('src/next.rs'), findsOneWidget);
    expect(find.text('new comment'), findsOneWidget);
    expect(find.byKey(const Key('hosting-review-load-more')), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets('review files use the shared rows, tree mode and menu', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await _pumpReview(tester, fixture);
    final row = find.byKey(const ValueKey('hosting-review-file-diff:1'));
    expect(row, findsOneWidget);
    expect(tester.widget<GitLamaFileRow>(row).status, 'M');
    expect(tester.widget<GitLamaFileRow>(row).selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('hosting-review-files-mode')));
    await tester.pumpAndSettle();
    expect(find.text('src'), findsOneWidget);
    expect(tester.widget<GitLamaFileRow>(row).path, 'lib.rs');

    List<Map<String, Object?>>? menu;
    final previous = nativeMenuTestPresenter;
    nativeMenuTestPresenter = (context, shown, position) async {
      menu = encodeMenuForTest(shown);
      return MenuResult(itemSelected: false);
    };
    addTearDown(() => nativeMenuTestPresenter = previous);
    await tester.tapAt(tester.getCenter(row), buttons: kSecondaryMouseButton);
    await tester.pump();
    expect(menu?.map((item) => item['title']), ['Copy path']);
    await fixture.dispose(tester);
  });

  test('review patches name their status letter', () {
    expect(reviewDiffStatus('@@ -1 +1 @@\n-a\n+b'), 'M');
    expect(reviewDiffStatus('new file mode 100644\n@@ -0,0 +1 @@'), 'A');
    expect(reviewDiffStatus('diff\ndeleted file mode 100644'), 'D');
    expect(reviewDiffStatus('similarity index 90%\nrename from a'), 'R');
  });

  testWidgets('check retry requires its exact preview authorization', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    await _pumpReview(tester, fixture);

    final retry = find.byKey(const Key('hosting-check-retry-github-check:11'));
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('Run this check again?'), findsOneWidget);
    await tester.tap(find.text('Request details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/retry'), findsOneWidget);
    expect(fixture.reviewRepository.retryCalls, 0);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(fixture.reviewRepository.retryCalls, 0);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MeridianButton, 'Re-run').last);
    await tester.pumpAndSettle();
    expect(fixture.reviewRepository.retryCalls, 1);
    await fixture.dispose(tester);
  });
}

Future<void> _pumpReview(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
}

final class _Fixture {
  _Fixture({
    required this.settings,
    required this.connections,
    required this.reviewRepository,
    required this.review,
  });

  final SettingsService settings;
  final HostingConnectionService connections;
  final _ReviewRepository reviewRepository;
  final HostingReviewService review;

  String get draftKey =>
      HostingReviewService.draftKey(_connection.id, 'team/project', 7);

  static Future<_Fixture> create({
    HostingReviewSubmitResult submitResult = const HostingReviewSubmitResult(
      state: HostingReviewSubmitState.submitted,
    ),
  }) async {
    final settings = SettingsService(
      FakeSettingsRepository(
        loaded: const LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(hostingConnections: [_connection]),
        ),
      ),
    );
    await settings.initialize();
    final connections = HostingConnectionService(
      _ConnectionRepository(),
      settings,
    );
    await connections.initialize();
    final repository = _ReviewRepository()..submitResult = submitResult;
    final review = HostingReviewService(repository, connections);
    return _Fixture(
      settings: settings,
      connections: connections,
      reviewRepository: repository,
      review: review,
    );
  }

  Widget app() => MaterialApp(
    theme: buildAppTheme(Brightness.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: HostingReviewWorkspace(
      review: review,
      connectionId: _connection.id,
      repository: 'team/project',
      pull: _pull,
      onOpenUrl: (_) async {},
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await connections.dispose();
    await settings.dispose();
  }
}

const _connection = HostingConnection(
  id: 'github:test',
  preset: HostingPreset.gitHub,
  login: 'alice',
  webBaseUrl: 'https://github.com',
  apiBaseUrl: 'https://api.github.com',
  oauthClientId: 'client',
  enabled: true,
  capabilities: [
    HostingCapability.changeRequestReview,
    HostingCapability.checkRuns,
  ],
  credentialIdentity: 'credential:test',
);

final _pull = HostingChangeRequest(
  stableId: 'pull:7',
  number: 7,
  title: 'Review this',
  author: 'alice',
  state: HostingChangeRequestState.open,
  draft: false,
  sourceRepository: 'team/project',
  sourceBranch: 'topic',
  targetRepository: 'team/project',
  targetBranch: 'main',
  headSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  webUrl: 'https://github.com/team/project/pull/7',
  reviewSummary: HostingReviewSummary.pending,
  mergeability: HostingMergeability.mergeable,
  checks: const HostingCheckSummary(state: HostingCheckState.passing),
);

final class _ReviewRepository implements HostingReviewRepository {
  var submitResult = const HostingReviewSubmitResult(
    state: HostingReviewSubmitState.submitted,
  );
  var submitCalls = 0;
  var retryCalls = 0;
  HostingReviewPreview? lastSubmitted;
  final List<HostingReviewDraft> savedDrafts = [];
  final List<String> deletedKeys = [];
  final List<String?> loadedPages = [];
  var cancelCalls = 0;

  @override
  Future<bool> cancel({
    required String connectionId,
    required String repository,
    required int pullRequest,
  }) async {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<HostingReviewPage> load({
    required HostingConnection connection,
    required String repository,
    required int pullRequest,
    required String headSha,
    String? page,
  }) async {
    loadedPages.add(page);
    if (page != null) {
      return HostingReviewPage(
        connectionId: connection.id,
        repository: repository,
        pullRequest: pullRequest,
        headSha: headSha,
        diffs: [
          HostingReviewDiff(
            stableId: 'diff:2',
            path: 'src/next.rs',
            patch: '@@ -1 +1 @@\n-before\n+after',
            anchors: [
              HostingReviewAnchor(
                stableId: '$headSha:src/next.rs:1',
                path: 'src/next.rs',
                line: 1,
              ),
            ],
          ),
        ],
        threads: const [
          HostingReviewThread(
            stableId: 'thread:new',
            path: 'src/next.rs',
            line: 1,
            anchorId: 'anchor:new',
            author: 'carol',
            body: 'new comment',
            resolved: false,
            outdated: false,
          ),
        ],
        checks: const [],
        nextPage: null,
        incomplete: false,
      );
    }
    return HostingReviewPage(
      connectionId: connection.id,
      repository: repository,
      pullRequest: pullRequest,
      headSha: headSha,
      diffs: [
        HostingReviewDiff(
          stableId: 'diff:1',
          path: 'src/lib.rs',
          patch: '@@ -1 +1 @@\n-old\n+new',
          anchors: [
            HostingReviewAnchor(
              stableId: '$headSha:src/lib.rs:1',
              path: 'src/lib.rs',
              line: 1,
            ),
          ],
        ),
      ],
      threads: const [
        HostingReviewThread(
          stableId: 'thread:old',
          path: 'src/lib.rs',
          line: 99,
          anchorId: null,
          author: 'bob',
          body: 'old comment',
          resolved: false,
          outdated: true,
        ),
      ],
      checks: const [
        HostingCheck(
          stableId: 'github-check:11',
          name: 'Build',
          state: HostingCheckState.failing,
          conclusion: 'failure',
        ),
      ],
      nextPage: 'page:2',
      incomplete: true,
    );
  }

  @override
  Future<HostingReviewPreview> preview({
    required HostingConnection connection,
    required String repository,
    required int pullRequest,
    required String headSha,
    required HostingReviewAction action,
    required String body,
    required List<HostingInlineDraft> inlineComments,
  }) async => HostingReviewPreview(
    authorizationId: 42,
    target: '/repos/team/project/pulls/7/reviews',
    payload: '{"body":"$body"}',
    connectionId: connection.id,
    repository: repository,
    pullRequest: pullRequest,
    headSha: headSha,
    action: action,
    body: body,
    inlineComments: List.unmodifiable(inlineComments),
  );

  @override
  Future<HostingReviewSubmitResult> submit({
    required HostingConnection connection,
    required HostingReviewPreview preview,
  }) async {
    submitCalls += 1;
    lastSubmitted = preview;
    return submitResult;
  }

  @override
  Future<HostingReviewDraft?> loadDraft(String key) async => null;

  @override
  Future<HostingReviewDraft> saveDraft(HostingReviewDraft draft) async {
    savedDrafts.add(draft);
    return draft;
  }

  @override
  Future<void> deleteDraft(String key) async => deletedKeys.add(key);

  @override
  Future<HostingCheckRetryPreview> previewCheckRetry({
    required HostingConnection connection,
    required String repository,
    required String headSha,
    required String checkStableId,
  }) async => HostingCheckRetryPreview(
    authorizationId: 44,
    target: '/retry',
    payload: '{}',
    connectionId: connection.id,
    repository: repository,
    headSha: headSha,
    checkStableId: checkStableId,
  );

  @override
  Future<HostingReviewSubmitResult> retryCheck({
    required HostingConnection connection,
    required HostingCheckRetryPreview preview,
  }) async {
    retryCalls += 1;
    return const HostingReviewSubmitResult(
      state: HostingReviewSubmitState.submitted,
    );
  }
}

final class _ConnectionRepository implements HostingRepository {
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
  ) async => HostingCredentialState.available;

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
