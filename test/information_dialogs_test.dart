import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/inspector/commit_diff_pane.dart';
import 'package:gitlama/app/workspace/history_mutation_dialogs.dart';
import 'package:gitlama/app/workspace/remote_operations.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/diff_renderer.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/services/workflows/history_rewrite_workflows.dart';
import 'package:gitlama/widgets/author_avatar.dart';
import 'package:gitlama/widgets/gitlama_list_well.dart';
import 'package:gitlama/widgets/hosting_integrations_section.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'support/fake_remote_workspace.dart';
import 'support/fake_settings_repository.dart';

/// Pumps a launcher whose button runs [open], taps it and settles.
Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Center(
          child: MeridianButton(
            key: const ValueKey('launch'),
            label: 'Open',
            onPressed: () => open(context),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('launch')));
  await tester.pumpAndSettle();
}

final _preview = DiffRendererPreview(
  token: BigInt.one,
  source: RepositorySessionIdentity(nativeId: BigInt.one, generation: 1),
  title: 'JSON diff',
  executable: '/usr/bin/json-diff',
  capabilityArguments: const ['--capabilities'],
  arguments: const ['--render', 'two words'],
  protocol: 'gitlama-diff-renderer-v1',
  mediaType: 'text/plain',
  inputBytes: 48213,
  outputLimitBytes: 1024,
  timeoutSeconds: 10,
);

void main() {
  group('branch integration', () {
    Future<BranchIntegration?> choose(
      WidgetTester tester,
      Future<void> Function() act, {
      String? source = 'topic',
    }) async {
      BranchIntegration? chosen;
      var closed = false;
      await _open(tester, (context) async {
        chosen = await showMeridianDialog<BranchIntegration>(
          context: context,
          builder: (_) => BranchIntegrationDialog(sourceName: source),
        );
        closed = true;
      });
      await act();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      return chosen;
    }

    testWidgets('explains both choices and merges by default', (tester) async {
      final chosen = await choose(tester, () async {
        expect(
          find.text(
            'Choose how to bring the changes from topic into your current '
            'branch.',
          ),
          findsOneWidget,
        );
        // Each choice is a fact with its consequence, not a bare hint.
        expect(find.byType(MeridianPropertyList), findsOneWidget);
        expect(find.textContaining('Adds a merge commit'), findsOneWidget);
        expect(
          find.textContaining('Replays your commits on top of topic'),
          findsOneWidget,
        );
        final merge = tester.widget<MeridianButton>(
          find.byKey(const ValueKey('branch-integration-merge')),
        );
        final rebase = tester.widget<MeridianButton>(
          find.byKey(const ValueKey('branch-integration-rebase')),
        );
        expect(merge.label, 'Merge…');
        expect(merge.variant, MeridianButtonVariant.primary);
        expect(rebase.label, 'Rebase…');
        expect(rebase.variant, isNot(MeridianButtonVariant.primary));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      });
      expect(chosen, BranchIntegration.merge);
    });

    testWidgets('rebase and cancel return their answers', (tester) async {
      expect(
        await choose(
          tester,
          () => tester.tap(
            find.byKey(const ValueKey('branch-integration-rebase')),
          ),
        ),
        BranchIntegration.rebase,
      );
      expect(
        await choose(
          tester,
          () => tester.tap(find.widgetWithText(MeridianButton, 'Cancel')),
          source: null,
        ),
        isNull,
      );
    });

    testWidgets('names the other branch generically when none is given', (
      tester,
    ) async {
      await _open(
        tester,
        (context) => showMeridianDialog<BranchIntegration>(
          context: context,
          builder: (_) => const BranchIntegrationDialog(),
        ),
      );
      expect(
        find.text(
          "Choose how to bring another branch's changes into your current "
          'branch.',
        ),
        findsOneWidget,
      );
      expect(find.text('Source branch'), findsNothing);
    });
  });

  testWidgets('the Gravatar offer says not now, or only closes', (
    tester,
  ) async {
    bool? enabled;
    await _open(tester, (context) async {
      enabled = await showMeridianDialog<bool>(
        context: context,
        builder: (_) => const GravatarOfferDialog(canEnable: true),
      );
    });
    expect(find.textContaining('sends a hash'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);

    await _open(
      tester,
      (context) => showMeridianDialog<bool>(
        context: context,
        builder: (_) => const GravatarOfferDialog(canEnable: false),
      ),
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Enable Gravatar'), findsNothing);
  });

  testWidgets('a diff renderer shows facts, with commands behind details', (
    tester,
  ) async {
    await _open(
      tester,
      (context) => showMeridianDialog<void>(
        context: context,
        builder: (_) => MeridianDialog(
          content: DiffRendererPreviewContent(
            preview: _preview,
            summary: 'summary',
          ),
        ),
      ),
    );
    expect(find.text('JSON diff'), findsOneWidget);
    expect(find.text('/usr/bin/json-diff'), findsOneWidget);
    expect(find.text('47 KB'), findsOneWidget);
    expect(find.text('1 KB'), findsOneWidget);
    expect(find.text('10 seconds'), findsOneWidget);
    // The exact command lines are there, one argument per line, so an
    // argument with a space stays one argument.
    expect(find.textContaining('--render'), findsNothing);
    await tester.tap(find.text('Command details'));
    await tester.pumpAndSettle();
    expect(
      find.text('/usr/bin/json-diff\n--render\ntwo words'),
      findsOneWidget,
    );
    expect(find.text('/usr/bin/json-diff\n--capabilities'), findsOneWidget);
    expect(find.text('gitlama-diff-renderer-v1'), findsOneWidget);
  });

  testWidgets('saving a renderer shows its output format, not run limits', (
    tester,
  ) async {
    await _open(
      tester,
      (context) => showMeridianDialog<void>(
        context: context,
        builder: (_) => MeridianDialog(
          content: DiffRendererPreviewContent(
            preview: _preview,
            summary: 'summary',
            run: false,
          ),
        ),
      ),
    );
    expect(find.text('Output format'), findsOneWidget);
    expect(find.text('Diff size'), findsNothing);
    expect(find.text('Time limit'), findsNothing);
  });

  testWidgets('a setup guide numbers its steps and sets values in code', (
    tester,
  ) async {
    await _open(
      tester,
      (context) => showMeridianDialog<void>(
        context: context,
        builder: (_) => const MeridianDialog(
          content: HostingGuideSteps(
            note: 'No client secret is needed.',
            steps: [
              HostingGuideStep('Create an application.'),
              HostingGuideStep(
                'Add this redirect URI:',
                code: hostingOAuthRedirectUri,
              ),
              HostingGuideStep('Select Save and authorize.'),
            ],
          ),
        ),
      ),
    );
    for (final number in [1, 2, 3]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('hosting-guide-step-$number')),
          matching: find.byWidgetPredicate(
            (widget) => widget is GitLamaStepNumber && widget.number == number,
          ),
        ),
        findsOneWidget,
      );
    }
    expect(find.text(hostingOAuthRedirectUri), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('hosting-guide-step-2'))).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('hosting-guide-step-1')))
            .dy,
      ),
    );
    expect(find.text('No client secret is needed.'), findsOneWidget);
  });

  testWidgets('remote changes sit in a bounded list', (tester) async {
    final settings = fakeSettingsService();
    await tester.runAsync(settings.initialize);
    const authority = RemoteAuthority(
      profileId: 'profile',
      storeId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      accountUid: '1000',
    );
    final workspace = FakeRemoteWorkspace(
      settings,
      pending: FakeRemotePending([
        for (var index = 0; index < 12; index++)
          RemotePendingOperation(
            operationId: '$index'.padLeft(32, '0'),
            epoch: 'e',
            digest: 'd',
            family: RemoteOperationFamily.stage,
            authority: authority,
            binding: 'b',
            pending: false,
            outcome: RemoteOperationOutcome.succeeded,
            summary: 'Change $index',
            createdAtMs: index,
            updatedAtMs: index,
          ),
      ]),
    );
    await tester.runAsync(workspace.service.initialize);
    await _open(
      tester,
      (context) =>
          showRemoteOperationsDialog(context, service: workspace.service),
    );
    final list = find.byKey(const ValueKey('remote-operations-list'));
    expect(list, findsOneWidget);
    expect(tester.widget(list), isA<GitLamaListWell>());
    expect(
      tester.getSize(list).height,
      lessThanOrEqualTo(GitLamaLayout.dialogListMaxHeight),
    );
    expect(
      find.text('Changes GitLama made on your hosts, newest first.'),
      findsOneWidget,
    );
    await tester.runAsync(workspace.service.dispose);
  });
}
