import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/app_update.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/app_updater_repository.dart';
import 'package:gitlama/repositories/impl/native_app_updater_repository.dart';
import 'package:gitlama/repositories/impl/native_release_index_repository.dart';
import 'package:gitlama/repositories/installed_release_repository.dart';
import 'package:gitlama/repositories/release_index_repository.dart';
import 'package:gitlama/services/app_update_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'support/fake_settings_repository.dart';

final class _Installed implements InstalledReleaseRepository {
  _Installed(this.release);
  final InstalledRelease? release;

  @override
  Future<InstalledRelease> load() async =>
      release ?? (throw StateError('native_unavailable'));
}

final class _Updater implements AppUpdaterRepository {
  _Updater({this.isAvailable = true});

  @override
  final bool isAvailable;
  final List<ReleaseChannel> configured = [];
  final List<Completer<void>> pending = [];
  var checks = 0;
  var hold = false;
  AppUpdateException? failure;

  @override
  Future<void> configure({
    required ReleaseChannel channel,
    required Duration checkInterval,
  }) async {
    expect(checkInterval, const Duration(days: 1));
    if (hold) {
      final gate = Completer<void>();
      pending.add(gate);
      await gate.future;
    }
    final error = failure;
    if (error != null) throw error;
    configured.add(channel);
  }

  @override
  Future<void> checkForUpdates() async => checks += 1;
}

final class _Index implements ReleaseIndexRepository {
  _Index({this.isAvailable = true, this.releases = const []});

  @override
  final bool isAvailable;
  List<PublishedRelease> releases;
  AppUpdateException? failure;
  var opened = 0;
  var issuesOpened = 0;

  @override
  Future<List<PublishedRelease>> load() async {
    final error = failure;
    if (error != null) throw error;
    return releases;
  }

  @override
  Future<void> openDownloads() async => opened += 1;

  @override
  Future<void> openIssues() async => issuesOpened += 1;
}

const _beta14 = InstalledRelease(version: '0.1.0-beta.14', build: 15);
const _stable = InstalledRelease(version: '1.4.0', build: 41);

Future<SettingsService> _settings([ReleaseChannel? channel]) async {
  final settings = SettingsService(
    FakeSettingsRepository(
      loaded: LoadedSettings(
        state: SettingsLoadState.loaded,
        document: SettingsDocument(releaseChannel: channel),
      ),
    ),
  );
  await settings.initialize();
  return settings;
}

void main() {
  group('release index', () {
    final fixture = File('test/fixtures/release_index.json');

    test('reads the index the release workflow produces', () {
      final releases = parseReleaseIndex(fixture.readAsBytesSync());

      expect(
        [for (final release in releases) (release.version, release.build)],
        [('1.5.0-beta.1', 42), ('1.4.0', 41), ('1.4.0-beta.3', 40)],
      );
      expect(
        [for (final release in releases) release.channel],
        [ReleaseChannel.beta, ReleaseChannel.stable, ReleaseChannel.beta],
      );
      expect(
        AppUpdateService.latestRelease(releases, ReleaseChannel.beta)?.build,
        42,
      );
      expect(
        AppUpdateService.latestRelease(releases, ReleaseChannel.stable)?.build,
        41,
      );
    });

    test('rejects oversized, foreign and malformed documents', () {
      String release({
        Object? version = '1.0.0',
        Object? build = 3,
        Object? channel = 'stable',
      }) =>
          '{"version":${_json(version)},"build":${_json(build)},'
          '"channel":${_json(channel)}}';
      String index(String releases, {String product = 'GitLama'}) =>
          '{"schema_version":1,"product":"$product","releases":[$releases]}';

      expect(parseReleaseIndex(index(release()).codeUnits).single.build, 3);
      for (final document in [
        '',
        'not json',
        '[]',
        '{"schema_version":2,"product":"GitLama","releases":[${release()}]}',
        index(release(), product: 'AnotherApp'),
        index(''),
        index(List.filled(11, release()).join(',')),
        index('${release()},${release()}'),
        index(release(version: '')),
        index(release(version: 7)),
        index(release(build: 0)),
        index(release(build: '3')),
        index(release(build: 1.5)),
        index(release(channel: 'nightly')),
        index(release(version: '1.0.0-beta.1')),
        index(release(channel: 'beta')),
        index('7'),
      ]) {
        expect(
          () => parseReleaseIndex(document.codeUnits),
          throwsA(
            isA<AppUpdateException>().having(
              (error) => error.code,
              'code',
              AppUpdateFailureCode.invalidIndex,
            ),
          ),
          reason: document,
        );
      }
      expect(
        () => parseReleaseIndex(List.filled(releaseIndexMaximumBytes + 1, 32)),
        throwsA(isA<AppUpdateException>()),
      );
    });

    test('refuses a plain HTTP index before any request', () async {
      var clients = 0;
      final repository = NativeReleaseIndexRepository(
        index: Uri.parse('http://devmil.de/gitlama/_data/releases.json'),
        available: true,
        createClient: () {
          clients += 1;
          return HttpClient();
        },
      );

      await expectLater(
        repository.load(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            AppUpdateFailureCode.invalidIndex,
          ),
        ),
      );
      expect(clients, 0);
    });

    test('opens only the fixed downloads page and reports a refusal', () async {
      final opened = <Uri>[];
      var accept = true;
      final repository = NativeReleaseIndexRepository(
        available: true,
        open: (uri) async {
          opened.add(uri);
          return accept;
        },
      );

      await repository.openDownloads();
      expect(
        opened.single.toString(),
        NativeReleaseIndexRepository.downloadsUrl,
      );
      accept = false;
      await expectLater(
        repository.openDownloads(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            AppUpdateFailureCode.openFailed,
          ),
        ),
      );
    });

    test('opens only the fixed issue tracker and reports a refusal', () async {
      final opened = <Uri>[];
      var accept = true;
      final repository = NativeReleaseIndexRepository(
        available: true,
        open: (uri) async {
          opened.add(uri);
          if (uri.scheme != 'https') throw StateError('unexpected');
          return accept;
        },
      );

      await repository.openIssues();
      expect(
        opened.single.toString(),
        'https://github.com/devmil/gitlama/issues',
      );
      accept = false;
      await expectLater(
        repository.openIssues(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            AppUpdateFailureCode.openFailed,
          ),
        ),
      );
    });
  });

  group('index platforms', () {
    test('reports a newer build on the selected channel', () async {
      final settings = await _settings();
      final index = _Index(
        releases: const [
          PublishedRelease(
            version: '0.1.0-beta.15',
            build: 16,
            channel: ReleaseChannel.beta,
          ),
        ],
      );
      final service = AppUpdateService(
        _Installed(_beta14),
        _Updater(isAvailable: false),
        index,
        settings,
      );
      await service.initialize();

      expect(service.isSupported, isTrue);
      expect(service.installsUpdates, isFalse);
      // A prerelease build follows beta until the user chooses.
      expect(service.channel, ReleaseChannel.beta);
      final check = await service.check();
      expect(check.status, AppUpdateStatus.updateAvailable);
      expect(check.available?.version, '0.1.0-beta.15');
      expect(check.installed.build, 15);

      await service.openDownloads();
      expect(index.opened, 1);
      await service.openIssues();
      expect(index.issuesOpened, 1);
      await service.dispose();
      await settings.dispose();
    });

    test(
      'stable ignores beta releases and an equal build is current',
      () async {
        final settings = await _settings();
        final index = _Index(
          releases: const [
            PublishedRelease(
              version: '1.5.0-beta.1',
              build: 42,
              channel: ReleaseChannel.beta,
            ),
            PublishedRelease(
              version: '1.4.0',
              build: 41,
              channel: ReleaseChannel.stable,
            ),
          ],
        );
        final service = AppUpdateService(
          _Installed(_stable),
          _Updater(isAvailable: false),
          index,
          settings,
        );
        await service.initialize();

        expect(service.channel, ReleaseChannel.stable);
        expect((await service.check()).status, AppUpdateStatus.upToDate);

        await service.selectChannel(ReleaseChannel.beta);
        expect(settings.current.releaseChannel, ReleaseChannel.beta);
        final beta = await service.check();
        expect(beta.status, AppUpdateStatus.updateAvailable);
        expect(beta.available?.build, 42);

        index.releases = const [
          PublishedRelease(
            version: '1.5.0-beta.1',
            build: 42,
            channel: ReleaseChannel.beta,
          ),
        ];
        await service.selectChannel(ReleaseChannel.stable);
        expect(
          (await service.check()).status,
          AppUpdateStatus.noPublishedRelease,
        );
        await service.dispose();
        await settings.dispose();
      },
    );

    test('passes index failures through with their code', () async {
      final settings = await _settings();
      final index = _Index()
        ..failure = const AppUpdateException(AppUpdateFailureCode.unavailable);
      final service = AppUpdateService(
        _Installed(_stable),
        _Updater(isAvailable: false),
        index,
        settings,
      );
      await service.initialize();

      await expectLater(
        service.check(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            AppUpdateFailureCode.unavailable,
          ),
        ),
      );
      await service.dispose();
      await settings.dispose();
    });
  });

  group('platform updater', () {
    test(
      'configures at startup, follows the channel and opens the checker',
      () async {
        final settings = await _settings();
        final updater = _Updater();
        final index = _Index(isAvailable: false);
        final service = AppUpdateService(
          _Installed(_beta14),
          updater,
          index,
          settings,
        );
        await service.initialize();

        expect(service.installsUpdates, isTrue);
        expect(updater.configured, [ReleaseChannel.beta]);

        // Unrelated settings changes do not reconfigure the updater.
        settings.updateView(
          settings.current.copyWith(
            appearance: settings.current.appearance.copyWith(theme: 'dark'),
          ),
        );
        await service.selectChannel(ReleaseChannel.stable);
        final check = await service.check();
        expect(check.status, AppUpdateStatus.nativeCheckerOpened);
        expect(updater.configured, [
          ReleaseChannel.beta,
          ReleaseChannel.stable,
        ]);
        expect(updater.checks, 1);

        await service.dispose();
        await service.selectChannel(ReleaseChannel.beta);
        await pumpEventQueue();
        expect(updater.configured, hasLength(2));
        await settings.dispose();
      },
    );

    test('quick channel changes end on the last choice', () async {
      final settings = await _settings(ReleaseChannel.stable);
      final updater = _Updater();
      final service = AppUpdateService(
        _Installed(_stable),
        updater,
        _Index(isAvailable: false),
        settings,
      );
      await service.initialize();
      updater.hold = true;

      unawaited(service.selectChannel(ReleaseChannel.beta));
      await pumpEventQueue();
      unawaited(service.selectChannel(ReleaseChannel.stable));
      await pumpEventQueue();
      unawaited(service.selectChannel(ReleaseChannel.beta));
      await pumpEventQueue();
      while (updater.pending.isNotEmpty) {
        updater.pending.removeAt(0).complete();
        await pumpEventQueue();
      }

      expect(updater.configured.last, ReleaseChannel.beta);
      expect(service.channel, ReleaseChannel.beta);
      await service.dispose();
      await settings.dispose();
    });

    test('an updater that cannot start fails the check, not startup', () async {
      final settings = await _settings();
      final updater = _Updater()
        ..failure = const AppUpdateException(
          AppUpdateFailureCode.nativeUpdater,
        );
      final service = AppUpdateService(
        _Installed(_stable),
        updater,
        _Index(isAvailable: false),
        settings,
      );

      await service.initialize();
      await expectLater(
        service.check(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            AppUpdateFailureCode.nativeUpdater,
          ),
        ),
      );
      expect(updater.checks, 0);

      updater.failure = null;
      expect(
        (await service.check()).status,
        AppUpdateStatus.nativeCheckerOpened,
      );
      await service.dispose();
      await settings.dispose();
    });
  });

  test(
    'an unknown installed release disables updates without failing',
    () async {
      final settings = await _settings();
      final updater = _Updater();
      final service = AppUpdateService(
        _Installed(null),
        updater,
        _Index(),
        settings,
      );

      await service.initialize();

      expect(service.isSupported, isFalse);
      expect(service.installed, isNull);
      expect(updater.configured, isEmpty);
      await expectLater(
        service.check(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.code,
            'code',
            AppUpdateFailureCode.unsupported,
          ),
        ),
      );
      await service.dispose();
      await settings.dispose();
    },
  );

  group('macOS updater channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(NativeAppUpdaterRepository.channelName);
    final calls = <MethodCall>[];
    Object? Function(MethodCall call)? respond;

    setUp(() {
      calls.clear();
      respond = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return respond?.call(call);
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('sends the pinned feed, the channel and the interval', () async {
      final repository = NativeAppUpdaterRepository(available: true);

      await repository.configure(
        channel: ReleaseChannel.beta,
        checkInterval: const Duration(days: 1),
      );
      await repository.checkForUpdates();

      expect(calls.first.method, 'configure');
      expect(calls.first.arguments, {
        'feedUrl': 'https://devmil.de/gitlama/appcast.xml',
        'releaseChannel': 'beta',
        'checkIntervalSeconds': 86400,
      });
      expect(calls.last.method, 'checkForUpdates');
    });

    test('maps a native refusal to a stable failure code', () async {
      final repository = NativeAppUpdaterRepository(available: true);
      respond = (_) => throw PlatformException(
        code: 'app_update_unavailable',
        message: 'private detail',
      );

      await expectLater(
        repository.checkForUpdates(),
        throwsA(
          isA<AppUpdateException>()
              .having(
                (error) => error.code,
                'code',
                AppUpdateFailureCode.nativeUpdater,
              )
              .having(
                (error) => error.toString(),
                'text',
                isNot(contains('private detail')),
              ),
        ),
      );
    });

    test('an unavailable updater never reaches the platform', () async {
      final repository = NativeAppUpdaterRepository(available: false);

      await expectLater(
        repository.checkForUpdates(),
        throwsA(isA<AppUpdateException>()),
      );
      expect(calls, isEmpty);
      // Widget tests and debug runs have no platform updater.
      expect(NativeAppUpdaterRepository().isAvailable, isFalse);
    });
  });
}

String _json(Object? value) => value is String ? '"$value"' : '$value';
