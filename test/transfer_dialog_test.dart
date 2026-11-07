import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/git_credential_dialog.dart';
import 'package:gitlama/app/workspace/labels.dart';
import 'package:gitlama/app/workspace/transfer_dialogs.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/transfer.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<TransferRequest? Function()> _openPull(
  WidgetTester tester, {
  required bool dirty,
  Locale locale = const Locale('en'),
}) async {
  TransferRequest? result;
  await tester.pumpWidget(
    _app(
      locale: locale,
      Builder(
        builder: (context) => Center(
          child: MeridianButton(
            label: 'Open',
            onPressed: () async {
              result = await showMeridianDialog<TransferRequest>(
                context: context,
                builder: (context) => TransferInputDialog(
                  kind: TransferKind.pull,
                  references: const RepositoryRefs(),
                  remotes: const ['origin'],
                  branch: 'main',
                  dirty: dirty,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => result;
}

Finder get _pull => find.widgetWithText(MeridianButton, 'Pull');

void main() {
  testWidgets('a pull over uncommitted changes is acknowledged in the dialog', (
    tester,
  ) async {
    final result = await _openPull(tester, dirty: true);
    // Submitting unacknowledged fails the pull and needs the dialog reopened.
    final blocked = tester.widget<MeridianButton>(_pull);
    expect(blocked.onPressed, isNull);
    expect(
      blocked.disabledReason,
      'Commit or stash your changes first, or choose how to handle them in the Pull dialog.',
    );

    await tester.ensureVisible(find.text('Pull with my uncommitted changes'));
    await tester.tap(find.text('Pull with my uncommitted changes'));
    await tester.pumpAndSettle();
    expect(tester.widget<MeridianButton>(_pull).disabledReason, isNull);
    await tester.tap(_pull);
    await tester.pumpAndSettle();
    expect(result()?.allowDirty, isTrue);
    expect(result()?.remote, 'origin');
    expect(result()?.branch, 'main');
  });

  testWidgets(
    'stash and pull is explicit and exclusive with pulling in place',
    (tester) async {
      final result = await _openPull(tester, dirty: true);
      expect(tester.widget<MeridianButton>(_pull).onPressed, isNull);
      await tester.tap(
        find.byKey(const ValueKey('transfer-stash-before-pull')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MeridianCheckbox>(
              find.byKey(const ValueKey('transfer-stash-before-pull')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<MeridianCheckbox>(
              find.byKey(const ValueKey('transfer-allow-dirty')),
            )
            .value,
        isFalse,
      );
      expect(
        find.widgetWithText(MeridianButton, 'Stash and pull'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Pull with my uncommitted changes'));
      await tester.tap(find.text('Pull with my uncommitted changes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MeridianCheckbox>(
              find.byKey(const ValueKey('transfer-stash-before-pull')),
            )
            .value,
        isFalse,
      );
      await tester.tap(
        find.byKey(const ValueKey('transfer-stash-before-pull')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MeridianButton, 'Stash and pull'));
      await tester.pumpAndSettle();
      expect(result()?.stashBeforePull, isTrue);
      expect(result()?.allowDirty, isFalse);
    },
  );

  for (final locale in ['en', 'de']) {
    testWidgets('dirty pull choices remain usable in a short $locale window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(740, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = await _openPull(
        tester,
        dirty: true,
        locale: Locale(locale),
      );
      final l10n = await AppLocalizations.delegate.load(Locale(locale));
      await tester.ensureVisible(find.text(l10n.transferStashBeforePull));
      await tester.tap(find.text(l10n.transferStashBeforePull));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(
        MeridianButton,
        l10n.transferStashPullAction,
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result()?.stashBeforePull, isTrue);
    });
  }

  testWidgets('a pull in a clean worktree submits at once', (tester) async {
    final result = await _openPull(tester, dirty: false);
    expect(find.text('Pull with my uncommitted changes'), findsNothing);
    await tester.tap(_pull);
    await tester.pumpAndSettle();
    expect(result()?.allowDirty, isFalse);
  });

  testWidgets('a fetch prunes unless the user turns it off', (tester) async {
    final requests = <TransferRequest?>[];
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'Open',
              onPressed: () async => requests.add(
                await showMeridianDialog<TransferRequest>(
                  context: context,
                  builder: (context) => const TransferInputDialog(
                    kind: TransferKind.fetch,
                    references: RepositoryRefs(),
                    remotes: ['origin'],
                    branch: null,
                    dirty: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final fetch = find.widgetWithText(MeridianButton, 'Fetch');
    for (final prune in [true, false]) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      if (!prune) {
        await tester.tap(find.byKey(const ValueKey('transfer-prune')));
        await tester.pumpAndSettle();
      }
      await tester.tap(fetch);
      await tester.pumpAndSettle();
    }
    expect(requests.map((request) => request?.prune), [true, false]);
  });

  testWidgets('remote branch deletion accepts only a fetched branch', (
    tester,
  ) async {
    TransferRequest? result;
    final commit = '1' * 40;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Center(
            child: MeridianButton(
              label: 'Open',
              onPressed: () async {
                result = await showMeridianDialog<TransferRequest>(
                  context: context,
                  builder: (context) => TransferInputDialog(
                    kind: TransferKind.deleteBranch,
                    references: RepositoryRefs(
                      remotes: [
                        RepositoryRemote(
                          name: 'origin'.codeUnits,
                          displayUrl: 'example.test/repository'.codeUnits,
                          branches: [
                            RepositoryReference(
                              name: 'HEAD'.codeUnits,
                              target: commit,
                            ),
                            RepositoryReference(
                              name: 'topic'.codeUnits,
                              target: commit,
                            ),
                          ],
                        ),
                      ],
                    ),
                    remotes: const ['origin'],
                    branch: '',
                    dirty: false,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final delete = find.widgetWithText(MeridianButton, 'Delete remote branch');
    expect(tester.widget<MeridianButton>(delete).onPressed, isNull);
    expect(
      tester.widget<MeridianButton>(delete).variant,
      MeridianButtonVariant.danger,
    );

    final field = find.byType(EditableText);
    // The symbolic HEAD names the default branch and is no branch to delete.
    await tester.enterText(field, 'HEAD');
    await tester.pump();
    expect(tester.widget<MeridianButton>(delete).onPressed, isNull);
    await tester.enterText(field, 'missing');
    await tester.pump();
    expect(tester.widget<MeridianButton>(delete).onPressed, isNull);

    await tester.enterText(field, 'topic');
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(result?.kind, TransferKind.deleteBranch);
    expect(result?.remote, 'origin');
    expect(result?.branch, 'topic');
    // A remote-only branch has no upstream; the push options must not leak
    // into the deletion, which the core refuses as an invalid request.
    expect(result?.setUpstream, isFalse);
    expect(result?.forceWithLease, isFalse);
  });

  testWidgets('running progress names its phase in the interface language', (
    tester,
  ) async {
    Future<String?> label(Locale locale, ActivityProgress? progress) async {
      String? value;
      await tester.pumpWidget(
        _app(
          locale: locale,
          Builder(
            builder: (context) {
              value = operationProgressLabel(context, progress);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return value;
    }

    ActivityProgress progress(
      String phase,
      int completed, [
      int? total = 100,
    ]) => ActivityProgress(
      phase: phase,
      completed: BigInt.from(completed),
      total: total == null ? null : BigInt.from(total),
      unit: 'percent',
    );

    const english = Locale('en');
    expect(
      await label(english, progress('Updating files', 85)),
      'Updating files 85%',
    );
    // Git LFS delivers file contents through a filter during checkout.
    expect(
      await label(english, progress('Filtering content', 45)),
      'Downloading file contents 45%',
    );
    expect(await label(english, progress('Rebasing', 3, 7)), 'Rebasing 43%');
    expect(await label(english, progress('Unknown phase', 12)), '12%');
    expect(await label(english, progress('Updating files', 1, null)), isNull);
    expect(await label(english, progress('Updating files', 0, 0)), isNull);
    expect(await label(english, null), isNull);
    expect(
      await label(const Locale('de'), progress('Receiving objects', 7)),
      'Objekte empfangen 7 %',
    );
  });

  group('Git credential dialog', () {
    Future<GitCredentialInput? Function()> open(
      WidgetTester tester, {
      required bool allowToken,
    }) async {
      GitCredentialInput? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: MeridianButton(
                label: 'Open',
                onPressed: () async {
                  result = await showGitCredentialDialog(
                    context,
                    target: allowToken ? 'origin' : null,
                    allowToken: allowToken,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    );
    Finder retry() =>
        find.widgetWithText(MeridianButton, 'Retry authentication');

    testWidgets('stays open while the secret is empty, then submits on Enter', (
      tester,
    ) async {
      final result = await open(tester, allowToken: false);
      expect(find.text('Password or token'), findsOne);
      expect(find.text('Use an access token'), findsNothing);
      expect(tester.widget<MeridianButton>(retry().first).onPressed, isNull);

      await tester.enterText(field('git-credential-username'), 'ada');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(GitCredentialDialog), findsOne);

      await tester.enterText(field('git-credential-secret'), 's3cret');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(GitCredentialDialog), findsNothing);
      expect(result()?.username, 'ada');
      expect(result()?.secret, 's3cret');
      expect(result()?.token, isFalse);
    });

    testWidgets('offers an access token when the caller allows it', (
      tester,
    ) async {
      final result = await open(tester, allowToken: true);
      expect(find.text('origin'), findsOne);
      expect(find.text('Password'), findsOne);
      await tester.tap(find.text('Use an access token'));
      await tester.pump();
      expect(find.text('Access token'), findsOne);
      await tester.enterText(field('git-credential-secret'), 'tok');
      await tester.pump();
      await tester.tap(retry().first);
      await tester.pumpAndSettle();
      expect(result()?.username, isNull);
      expect(result()?.secret, 'tok');
      expect(result()?.token, isTrue);
    });

    testWidgets('a click on the scrim does not dismiss it', (tester) async {
      await open(tester, allowToken: false);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(GitCredentialDialog), findsOne);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(GitCredentialDialog), findsNothing);
    });
  });

  group('push dialog', () {
    Future<TransferRequest? Function()> openPush(
      WidgetTester tester, {
      List<int>? upstream,
    }) async {
      TransferRequest? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: MeridianButton(
                label: 'Open',
                onPressed: () async {
                  result = await showMeridianDialog<TransferRequest>(
                    context: context,
                    builder: (context) => TransferInputDialog(
                      kind: TransferKind.push,
                      references: const RepositoryRefs(),
                      remotes: const ['origin'],
                      branch: 'topic',
                      currentBranch: 'topic'.codeUnits,
                      currentUpstream: upstream,
                      dirty: false,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('labels sit above the fields and options line up with them', (
      tester,
    ) async {
      await openPush(tester);
      expect(find.byType(MeridianSettingsRow), findsNothing);
      final remote = tester.getRect(
        find.byKey(const ValueKey('transfer-remote')),
      );
      final label = tester.getRect(find.text('Remote'));
      // The label heads the select and starts at its edge.
      expect(
        label.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('origin')).top),
      );
      expect(label.left, closeTo(remote.left, 1));
      for (final key in ['transfer-set-upstream', 'transfer-force']) {
        expect(
          tester.getRect(find.byKey(ValueKey(key))).left,
          closeTo(remote.left, 1),
        );
      }
      // The force option says what it does, not how Git names it.
      expect(find.text('Overwrite the remote branch'), findsOne);
      expect(
        find.text(
          'For commits you have rewritten. Refused if someone else pushed '
          'to it since your last fetch.',
        ),
        findsOne,
      );
    });

    testWidgets('the overwrite option pushes with a lease', (tester) async {
      final result = await openPush(tester);
      await tester.tap(find.byKey(const ValueKey('transfer-force')));
      await tester.pump();
      await tester.tap(find.widgetWithText(MeridianButton, 'Push'));
      await tester.pumpAndSettle();
      expect(result()?.forceWithLease, isTrue);
      expect(result()?.setUpstream, isTrue);
    });

    testWidgets('a branch with an upstream is not offered a new one', (
      tester,
    ) async {
      final result = await openPush(
        tester,
        upstream: 'refs/remotes/origin/topic'.codeUnits,
      );
      expect(find.byKey(const ValueKey('transfer-set-upstream')), findsNothing);
      await tester.tap(find.widgetWithText(MeridianButton, 'Push'));
      await tester.pumpAndSettle();
      expect(result()?.setUpstream, isFalse);
      expect(result()?.forceWithLease, isFalse);
    });
  });
}
