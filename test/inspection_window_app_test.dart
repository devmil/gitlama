import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/inspection_window_app.dart';
import 'package:gitlama/app/inspector_window_runtime.dart';
import 'package:gitlama/di/inspector_window_components.dart';
import 'package:gitlama/models/diff.dart';
import 'package:gitlama/models/inspection.dart';
import 'package:gitlama/models/inspection_window.dart';
import 'package:gitlama/models/inspector.dart';
import 'package:gitlama/models/inspector_reveal.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/repositories/avatar_repository.dart';
import 'package:gitlama/repositories/impl/remote/remote_inspection_channel.dart';
import 'package:gitlama/repositories/core_repository.dart';
import 'package:gitlama/repositories/inspection_window_repository.dart';
import 'package:gitlama/repositories/inspector_reveal_repository.dart';
import 'package:gitlama/repositories/repository_session_repository.dart';
import 'package:gitlama/services/inspector_reveal_service.dart';
import 'package:gitlama/widgets/gitlama_window_caption.dart';

import 'support/fake_settings_repository.dart';

const _commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _parent = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _repository = NativePathIdentity(
  platform: NativePathPlatform.unix,
  units: '/work/notelama'.codeUnits,
);

final class _Core implements CoreRepository {
  _Core({this.failures = 0});

  /// How many initializations fail before one succeeds.
  int failures;
  int attempts = 0;

  @override
  Future<void> initialize() async {
    attempts += 1;
    if (failures > 0) {
      failures -= 1;
      throw StateError('core_unavailable');
    }
  }
}

final class _Session implements RepositorySessionRepository {
  int closed = 0;
  final List<String> calls = [];

  @override
  Future<({RepositorySessionIdentity identity, RepositorySnapshot snapshot})>
  openIdentity(NativePathIdentity identity, int generation) async => (
    identity: RepositorySessionIdentity(nativeId: BigInt.two, generation: 1),
    snapshot: RepositorySnapshot(
      revision: BigInt.one,
      phase: RepositoryPhase.ready,
    ),
  );

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) async {
    calls.add('inspect:${firstParent ?? '-'}');
    return CommitInspection(
      detail: CommitIdentityDetail(
        commit: commit,
        tree: 'tree',
        parents: commit == _commit ? const [_parent] : const [],
        author: 'Ada'.codeUnits,
        authorTime: 1,
        authorTimezone: const [],
        committer: 'Ada'.codeUnits,
        committerTime: 1,
        committerTimezone: const [],
        message: 'Move Meridian'.codeUnits,
      ),
      files: [
        CommitFileChange(
          oldMode: 0x81a4,
          newMode: 0x81a4,
          kind: CommitFileChangeKind.modified,
          oldPath: 'pubspec.lock'.codeUnits,
          newPath: 'pubspec.lock'.codeUnits,
        ),
      ],
    );
  }

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = 512,
  }) async {
    calls.add('diff:${firstParent ?? '-'}');
    return DiffPage(
      requestId: BigInt.one,
      layout: options.layout,
      totalRows: 0,
      offset: 0,
      rows: const [],
      payloadBytes: 0,
    );
  }

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = 512,
  }) async {
    calls.add('blame');
    return BlamePage(
      requestId: BigInt.two,
      revision: revision,
      path: path,
      totalRows: 0,
      offset: 0,
      rows: const [],
    );
  }

  @override
  Future<bool> close(RepositorySessionIdentity identity) async {
    closed += 1;
    return true;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class _Windows implements InspectionWindowRepository {
  final List<InspectionWindowRequest> opened = [];

  @override
  Future<void> open(InspectionWindowRequest request) async =>
      opened.add(request);
}

final class _Reveal implements InspectorRevealRepository {
  _Reveal(this.answer);

  bool answer;
  final List<InspectorRevealRequest> requests = [];

  @override
  Future<void> listen(
    Future<bool> Function(InspectorRevealRequest) onReveal,
  ) async {}

  @override
  Future<bool> reveal(InspectorRevealRequest request) async {
    requests.add(request);
    return answer;
  }

  @override
  Future<void> dispose() async {}
}

/// A main window without a connection to the host.
final class _Disconnected implements RemoteInspectionTransport {
  final List<String> methods = [];

  @override
  Future<String> windowId() async => '3';

  @override
  Future<Object?> invoke(String method, String payload) async {
    methods.add(method);
    return '{"failure":"remoteDisconnected"}';
  }
}

final class _Avatars implements AvatarRepository {
  @override
  Future<Uint8List?> load(String hash, {required bool enabled}) async => null;

  @override
  Future<void> clearCache() async {}
}

InspectorWindowComponents _components(
  InspectionWindowRequest request, {
  required _Session session,
  _Windows? windows,
  _Reveal? reveal,
  _Core? core,
  FakeSettingsRepository? settings,
}) => InspectorWindowComponents(
  request,
  coreRepositoryFactory: () => core ?? _Core(),
  sessionRepositoryFactory: () => session,
  inspectionWindowRepositoryFactory: () => windows ?? _Windows(),
  revealRepositoryFactory: () => reveal ?? _Reveal(true),
  settingsRepositoryFactory: () => settings ?? FakeSettingsRepository(),
  avatarRepositoryFactory: _Avatars.new,
);

void main() {
  late _Session session;
  late _Windows windows;
  late _Reveal reveal;
  final titles = <String>[];

  Future<void> pump(
    WidgetTester tester,
    InspectorLocation location, {
    bool revealAnswer = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    session = _Session();
    windows = _Windows();
    reveal = _Reveal(revealAnswer);
    titles.clear();
    final request = InspectionWindowRequest(
      repository: _repository,
      location: location,
    );
    await tester.pumpWidget(
      InspectionWindowApp(
        request: request,
        bootstrap: (request) => bootstrapInspectorWindow(
          request,
          componentsFactory: (request) => _components(
            request,
            session: session,
            windows: windows,
            reveal: reveal,
          ),
        ),
        setTitle: (title) async => titles.add(title),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a window shows the same inspector with Back and Forward', (
    tester,
  ) async {
    await pump(
      tester,
      InspectorLocation(
        target: const CommitTarget(_commit),
        path: 'pubspec.lock'.codeUnits,
        lens: InspectorLens.blame,
      ),
    );
    expect(find.byKey(const ValueKey('inspector-window')), findsOneWidget);
    expect(find.byKey(const ValueKey('inspector-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('inspector-forward')), findsOneWidget);
    expect(find.byKey(const ValueKey('inspector-lens')), findsOneWidget);
    // No Close button: the window closes through its title bar.
    expect(find.text('Close'), findsNothing);
    // No graph of its own, so no maximize; a way back instead.
    expect(find.byKey(const ValueKey('inspector-maximize')), findsNothing);
    expect(
      find.byKey(const ValueKey('inspector-show-in-main-window')),
      findsOneWidget,
    );
    // The parent is read first, so the diff compares with it.
    expect(session.calls, containsAllInOrder(['inspect:-', 'blame']));
    expect(titles.last, 'notelama — aaaaaaaa · pubspec.lock · Blame');
  });

  testWidgets('on Linux the window draws its own caption', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = GitLamaWindowCaptionFrame.channel;
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'captionLayout') return 'appmenu:close';
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pump(
      tester,
      InspectorLocation(
        target: const CommitTarget(_commit),
        path: 'pubspec.lock'.codeUnits,
        lens: InspectorLens.blame,
      ),
    );
    final caption = find.byKey(const ValueKey('inspector-window-caption'));
    expect(caption, findsOneWidget);
    expect(
      find.descendant(of: caption, matching: find.text(titles.last)),
      findsOneWidget,
    );
    // The native frame follows the window's ground colour.
    expect(calls.map((call) => call.method), contains('setBackgroundColor'));

    await tester.tap(find.byKey(const ValueKey('window-caption-close')));
    await tester.pump();
    expect(calls.last.method, 'close');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a lens change is navigation the window can undo', (
    tester,
  ) async {
    await pump(
      tester,
      InspectorLocation(
        target: const CommitTarget(_commit),
        path: 'pubspec.lock'.codeUnits,
        lens: InspectorLens.blame,
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('inspector-lens')),
        matching: find.text('Diff'),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.calls.last, 'diff:$_parent');
    expect(titles.last, 'notelama — aaaaaaaa · pubspec.lock');
    await tester.tap(find.byKey(const ValueKey('inspector-back')));
    await tester.pumpAndSettle();
    expect(titles.last, 'notelama — aaaaaaaa · pubspec.lock · Blame');
  });

  testWidgets('open in new window passes the location on', (tester) async {
    await pump(tester, const InspectorLocation(target: CommitTarget(_commit)));
    await tester.tap(find.byKey(const ValueKey('inspector-open-window')));
    await tester.pump();
    expect(windows.opened.single.location.target, const CommitTarget(_commit));
    expect(windows.opened.single.repository, _repository);
  });

  testWidgets('show in main window turns off when the repository is closed', (
    tester,
  ) async {
    await pump(
      tester,
      const InspectorLocation(target: CommitTarget(_commit)),
      revealAnswer: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('inspector-show-in-main-window')),
    );
    await tester.pumpAndSettle();
    expect(reveal.requests.single.commit, _commit);
    expect(reveal.requests.single.repository, _repository);
    final button = tester.widget<MeridianIconButton>(
      find.byKey(const ValueKey('inspector-show-in-main-window')),
    );
    expect(button.onPressed, isNull);
    expect(button.disabledReason, 'Repository is not open in GitLama');
  });

  testWidgets('closing the window closes its session', (tester) async {
    await pump(tester, const InspectorLocation(target: CommitTarget(_commit)));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(session.closed, 1);
  });

  group('window runtime', () {
    InspectionWindowRequest request() => InspectionWindowRequest(
      repository: _repository,
      location: const InspectorLocation(target: CommitTarget(_commit)),
    );

    testWidgets('a failed start offers Retry, which starts afresh', (
      tester,
    ) async {
      final core = _Core(failures: 1);
      final sessions = <_Session>[];
      var roots = 0;
      await tester.pumpWidget(
        InspectionWindowApp(
          request: request(),
          bootstrap: (request) => bootstrapInspectorWindow(
            request,
            componentsFactory: (request) {
              roots += 1;
              final session = _Session();
              sessions.add(session);
              return _components(request, session: session, core: core);
            },
          ),
          setTitle: (_) async {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const ValueKey('inspector-window')), findsNothing);
      // The failed root opened no session.
      expect(sessions.single.closed, 0);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(roots, 2);
      expect(core.attempts, 2);
      expect(find.byKey(const ValueKey('inspector-window')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(sessions.last.closed, 1);
    });

    test('shutdown closes the session once', () async {
      final session = _Session();
      final settings = FakeSettingsRepository();
      final runtime = await bootstrapInspectorWindow(
        request(),
        componentsFactory: (request) =>
            _components(request, session: session, settings: settings),
      );
      expect(runtime.session.failed, isFalse);
      await runtime.shutdown();
      expect(session.closed, 1);
      await runtime.shutdown();
      expect(session.closed, 1);
    });

    testWidgets('the window takes theme and density from the settings', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(
        loaded: const LoadedSettings(
          state: SettingsLoadState.loaded,
          document: SettingsDocument(
            appearance: AppearanceSettings(
              theme: 'dark',
              density: 'compact',
              reduceMotion: 'reduce',
            ),
          ),
        ),
      );
      final titles = <String>[];
      await tester.pumpWidget(
        InspectionWindowApp(
          request: request(),
          bootstrap: (request) => bootstrapInspectorWindow(
            request,
            componentsFactory: (request) =>
                _components(request, session: _Session(), settings: settings),
          ),
          setTitle: (title) async => titles.add(title),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(
        find.byKey(const ValueKey('inspector-window')),
      );
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(MeridianTheme.of(context).density, MeridianDensity.compact);
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      // Named once for the location, not on every build.
      expect(titles, hasLength(1));
      await tester.pump();
      expect(titles, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('a remote repository', () {
    const authority = RemoteAuthority(
      profileId: '0f8fad5b-d9cb-469f-a165-70867728950e',
      storeId: '0123456789abcdef0123456789abcdef',
      accountUid: '1000',
    );
    final remote = NativePathIdentity(
      platform: NativePathPlatform.unix,
      units: '/work/notelama'.codeUnits,
      remote: authority,
    );
    FakeSettingsRepository settings() => FakeSettingsRepository(
      loaded: const LoadedSettings(
        state: SettingsLoadState.loaded,
        document: SettingsDocument(
          remoteProfiles: [
            RemoteHostProfile(
              id: '0f8fad5b-d9cb-469f-a165-70867728950e',
              label: 'Workstation',
              alias: 'devbox',
            ),
          ],
        ),
      ),
    );

    testWidgets('names its host and opens windows of the same host', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final windows = _Windows();
      final titles = <String>[];
      await tester.pumpWidget(
        InspectionWindowApp(
          request: InspectionWindowRequest(
            repository: remote,
            location: const InspectorLocation(target: CommitTarget(_commit)),
          ),
          bootstrap: (request) => bootstrapInspectorWindow(
            request,
            componentsFactory: (request) => InspectorWindowComponents(
              request,
              coreRepositoryFactory: _Core.new,
              sessionRepositoryFactory: _Session.new,
              inspectionWindowRepositoryFactory: () => windows,
              revealRepositoryFactory: () => _Reveal(true),
              settingsRepositoryFactory: settings,
              avatarRepositoryFactory: _Avatars.new,
            ),
          ),
          setTitle: (title) async => titles.add(title),
        ),
      );
      await tester.pumpAndSettle();
      expect(titles.last, 'notelama · Workstation — aaaaaaaa');
      await tester.tap(find.byKey(const ValueKey('inspector-open-window')));
      await tester.pump();
      expect(windows.opened.single.repository, remote);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('reads through the main window and says when its host is '
        'not connected', (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = _Disconnected();
      await tester.pumpWidget(
        InspectionWindowApp(
          request: InspectionWindowRequest(
            repository: remote,
            location: const InspectorLocation(target: CommitTarget(_commit)),
          ),
          bootstrap: (request) => bootstrapInspectorWindow(
            request,
            componentsFactory: (request) => InspectorWindowComponents(
              request,
              coreRepositoryFactory: _Core.new,
              inspectionWindowRepositoryFactory: _Windows.new,
              revealRepositoryFactory: () => _Reveal(true),
              settingsRepositoryFactory: settings,
              avatarRepositoryFactory: _Avatars.new,
              remoteInspectionTransportFactory: () => transport,
            ),
          ),
          setTitle: (_) async {},
        ),
      );
      await tester.pumpAndSettle();
      // The window asked the main window, naming its host.
      expect(transport.methods, ['open']);
      expect(
        find.byKey(const ValueKey('inspector-window-disconnected')),
        findsOneWidget,
      );
      expect(find.text('Not connected to Workstation'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inspector-window-retry')));
      await tester.pumpAndSettle();
      expect(transport.methods, ['open', 'open']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('reveal requests', () {
    test('round-trip a commit and a comparison', () {
      final commit = InspectorRevealRequest(
        repository: _repository,
        commit: _commit,
      );
      final decoded = InspectorRevealRequest.decode(commit.encode())!;
      expect(decoded.repository, _repository);
      expect(decoded.commit, _commit);
      expect(decoded.base, isNull);
      final comparison = InspectorRevealRequest(
        repository: _repository,
        commit: _commit,
        base: _parent,
      );
      expect(InspectorRevealRequest.decode(comparison.encode())!.base, _parent);
    });

    test('keep the authority of a remote repository', () {
      const authority = RemoteAuthority(
        profileId: '0f8fad5b-d9cb-469f-a165-70867728950e',
        storeId: '0123456789abcdef0123456789abcdef',
        accountUid: '1000',
      );
      final remote = NativePathIdentity(
        platform: NativePathPlatform.unix,
        units: '/work/notelama'.codeUnits,
        remote: authority,
      );
      final decoded = InspectorRevealRequest.decode(
        InspectorRevealRequest(repository: remote, commit: _commit).encode(),
      )!;
      expect(decoded.repository, remote);
      // The same path on this computer is a different repository.
      expect(decoded.repository == _repository, isFalse);
      expect(
        InspectorRevealRequest.decode(
          '{"schema":2,"platform":"unix","units":[47],"commit":"$_commit",'
          '"remote":{"profileId":"x","storeId":"y","accountUid":"1"}}',
        ),
        isNull,
      );
      // Schema 1 never named a remote repository.
      expect(
        InspectorRevealRequest.decode(
          '{"schema":1,"platform":"unix","units":[47],"commit":"$_commit",'
          '"remote":${jsonEncode(authority.toMessage())}}',
        ),
        isNull,
      );
    });

    test('reject malformed requests', () {
      expect(InspectorRevealRequest.decode(null), isNull);
      expect(InspectorRevealRequest.decode(42), isNull);
      expect(InspectorRevealRequest.decode('{"schema":2}'), isNull);
      expect(
        InspectorRevealRequest.decode(
          '{"schema":1,"platform":"unix","units":[47],"commit":"HEAD"}',
        ),
        isNull,
      );
      expect(
        InspectorRevealRequest.decode(
          '{"schema":1,"platform":"unix","units":[],"commit":"$_commit"}',
        ),
        isNull,
      );
      expect(
        InspectorRevealRequest.decode(
          '{"schema":1,"platform":"unix","units":[47],"commit":"$_commit",'
          '"base":"main"}',
        ),
        isNull,
      );
      expect(InspectorRevealRequest.decode('x' * 65537), isNull);
    });

    test('the service names the target of a comparison', () async {
      final repository = _Reveal(true);
      final service = InspectorRevealService(repository);
      expect(
        await service.reveal(
          _repository,
          const ComparisonTarget(base: _parent, commit: _commit),
        ),
        isTrue,
      );
      expect(repository.requests.single.base, _parent);
    });
  });
}
