import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/app/workspace/settings_dialog.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/app_update.dart';
import 'package:gitlama/repositories/app_updater_repository.dart';
import 'package:gitlama/repositories/installed_release_repository.dart';
import 'package:gitlama/repositories/release_index_repository.dart';
import 'package:gitlama/services/app_update_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_repository_session_repository.dart';
import 'support/fake_settings_repository.dart';

final class _Installed implements InstalledReleaseRepository {
  _Installed(this.release);
  final InstalledRelease? release;

  @override
  Future<InstalledRelease> load() async =>
      release ?? (throw StateError('native_unavailable'));
}

final class _Updater implements AppUpdaterRepository {
  _Updater({required this.isAvailable});

  @override
  final bool isAvailable;
  final List<ReleaseChannel> configured = [];
  var checks = 0;

  @override
  Future<void> configure({
    required ReleaseChannel channel,
    required Duration checkInterval,
  }) async => configured.add(channel);

  @override
  Future<void> checkForUpdates() async => checks += 1;
}

final class _Index implements ReleaseIndexRepository {
  _Index({required this.isAvailable});

  @override
  final bool isAvailable;
  Completer<List<PublishedRelease>>? response;
  AppUpdateException? openFailure;
  var opened = 0;

  @override
  Future<List<PublishedRelease>> load() =>
      (response = Completer<List<PublishedRelease>>()).future;

  @override
  Future<void> openDownloads() async {
    final failure = openFailure;
    if (failure != null) throw failure;
    opened += 1;
  }

  @override
  Future<void> openIssues() async {}

  @override
  Future<void> openSource() async {}
}

const _installed = InstalledRelease(version: '0.1.0-beta.14', build: 15);
const _newer = PublishedRelease(
  version: '0.1.0-beta.15',
  build: 16,
  channel: ReleaseChannel.beta,
);

Future<(AppUpdateService, SettingsService)> _pump(
  WidgetTester tester, {
  required _Updater updater,
  required _Index index,
  InstalledRelease? installed = _installed,
  Locale locale = const Locale('en'),
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = SettingsService(FakeSettingsRepository());
  await settings.initialize();
  final updates = AppUpdateService(
    _Installed(installed),
    updater,
    index,
    settings,
  );
  await updates.initialize();
  // The fakes hold no resources. Their futures belong to the test's fake
  // clock, so a teardown outside it could never finish disposing them.
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsDialog(
          settings: settings,
          repositories: fakeRepositorySessionService(),
          hosting: null,
          repository: null,
          initialCategory: SettingsCategory.appearance,
          onOpenUrl: (_) async {},
          updates: updates,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (updates, settings);
}

Future<void> _openUpdates(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings-category-updates')));
  await tester.pumpAndSettle();
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('settings-updates-status'))).data!;

void main() {
  testWidgets('reports a newer release and opens the downloads page', (
    tester,
  ) async {
    final index = _Index(isAvailable: true);
    await _pump(tester, updater: _Updater(isAvailable: false), index: index);
    await _openUpdates(tester);

    expect(find.text('0.1.0-beta.14 (build 15)'), findsOneWidget);
    expect(
      find.text(
        'GitLama contacts the release site only when you check. '
        'Install the download yourself.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-updates-open-downloads')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('settings-updates-check')));
    await tester.pump();
    expect(_status(tester), 'Checking for updates…');

    index.response!.complete(const [_newer]);
    await tester.pumpAndSettle();
    expect(
      _status(tester),
      'GitLama 0.1.0-beta.15 (build 16) is available. '
      'Download it from the releases page.',
    );

    await tester.tap(find.byKey(const Key('settings-updates-open-downloads')));
    await tester.pumpAndSettle();
    expect(index.opened, 1);

    index.openFailure = const AppUpdateException(
      AppUpdateFailureCode.openFailed,
    );
    await tester.tap(find.byKey(const Key('settings-updates-open-downloads')));
    await tester.pumpAndSettle();
    expect(_status(tester), 'The downloads page could not be opened.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the current state and failures in German', (tester) async {
    final index = _Index(isAvailable: true);
    await _pump(
      tester,
      updater: _Updater(isAvailable: false),
      index: index,
      locale: const Locale('de'),
    );
    await _openUpdates(tester);

    await tester.tap(find.byKey(const Key('settings-updates-check')));
    await tester.pump();
    index.response!.complete(const [
      PublishedRelease(
        version: '0.1.0-beta.14',
        build: 15,
        channel: ReleaseChannel.beta,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(_status(tester), 'GitLama 0.1.0-beta.14 (Build 15) ist aktuell.');

    await tester.tap(find.byKey(const Key('settings-updates-check')));
    await tester.pump();
    index.response!.completeError(
      const AppUpdateException(AppUpdateFailureCode.unavailable),
    );
    await tester.pumpAndSettle();
    expect(
      _status(tester),
      'Die Release-Seite war nicht erreichbar. Versuche es später erneut.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the platform updater takes over and follows the channel', (
    tester,
  ) async {
    final updater = _Updater(isAvailable: true);
    final (updates, settings) = await _pump(
      tester,
      updater: updater,
      index: _Index(isAvailable: false),
    );
    await _openUpdates(tester);

    expect(
      find.text(
        'GitLama looks for updates in the background and installs one '
        'after you confirm.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('settings-updates-check')));
    await tester.pumpAndSettle();
    expect(updater.checks, 1);
    expect(_status(tester), isEmpty);

    await tester.tap(find.text('Stable'));
    await tester.pumpAndSettle();
    expect(settings.current.releaseChannel, ReleaseChannel.stable);
    expect(updates.channel, ReleaseChannel.stable);
    expect(updater.configured, [ReleaseChannel.beta, ReleaseChannel.stable]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the category when updates are unsupported', (
    tester,
  ) async {
    await _pump(
      tester,
      updater: _Updater(isAvailable: true),
      index: _Index(isAvailable: true),
      installed: null,
    );

    expect(find.byKey(const Key('settings-category-licenses')), findsOneWidget);
    expect(find.byKey(const Key('settings-category-updates')), findsNothing);
  });

  testWidgets('fits a narrow window with long German text', (tester) async {
    final index = _Index(isAvailable: true);
    await _pump(
      tester,
      updater: _Updater(isAvailable: false),
      index: index,
      locale: const Locale('de'),
      size: const Size(560, 480),
    );

    await tester.tap(find.byType(MeridianSelect<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-updates-check')));
    await tester.pump();
    index.response!.complete(const [_newer]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-updates-open-downloads')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
