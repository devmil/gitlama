import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/impl/remote/remote_helper_install.dart';
import 'package:gitlama/repositories/impl/remote/remote_process.dart';
import 'package:gitlama/repositories/impl/remote/ssh_command.dart';
import 'package:gitlama/repositories/impl/remote/ssh_remote_connection_repository.dart';

import 'support/fake_remote_process.dart' show testBuildId;
import 'support/fake_timers.dart';

Matcher _fails(RemoteFailureCode code) => throwsA(
  isA<RemoteWorkspaceException>().having((e) => e.code, 'code', code),
);

/// An installer process: records stdin and answers when told to.
final class _InstallProcess implements RemoteProcess {
  final _stdout = StreamController<List<int>>();
  final _exit = Completer<int>();
  final received = BytesBuilder();
  var stdinClosed = false;
  var terminated = 0;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(List<int> bytes) {
    if (!stdinClosed) received.add(bytes);
  }

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  Future<void> terminate() async {
    terminated += 1;
    finish(143);
  }

  void finish(int code, [String output = '']) {
    if (output.isNotEmpty) _stdout.add(latin1.encode(output));
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

RemoteHelperArtifact _artifact(
  List<int> bytes, {
  RemoteHelperTarget target = RemoteHelperTarget.linuxX86_64,
}) => RemoteHelperArtifact(
  buildId: testBuildId,
  target: target,
  sha256: sha256.convert(bytes).toString(),
  bytes: bytes,
);

void main() {
  group('bundled helper', () {
    late Directory root;
    // The macOS bundle sits beside the executable directory, so that
    // directory is nested to keep the bundle inside [root].
    late String executableDirectory;

    setUp(() {
      root = Directory.systemTemp.createTempSync('gitlama-bundle');
      executableDirectory = '${root.path}/bin';
    });
    tearDown(() => root.deleteSync(recursive: true));

    String bundle(
      List<int> binary,
      Map<String, Object?> descriptor, {
      RemoteHelperTarget target = RemoteHelperTarget.linuxX86_64,
    }) {
      final directory = Directory(
        remoteHelperBundleDirectory(
          executableDirectory: executableDirectory,
          macOS: Platform.isMacOS,
          windows: Platform.isWindows,
          target: target,
        ),
      )..createSync(recursive: true);
      File('${directory.path}/gitlama-remote-helper').writeAsBytesSync(binary);
      File(
        '${directory.path}/gitlama-remote-helper.json',
      ).writeAsStringSync(jsonEncode(descriptor));
      return '$executableDirectory/gitlama';
    }

    Map<String, Object?> descriptor(
      List<int> binary, {
      RemoteHelperTarget target = RemoteHelperTarget.linuxX86_64,
    }) => {
      'schema': 1,
      'build_id': testBuildId,
      'target': target.triple,
      'sha256': sha256.convert(binary).toString(),
      'bytes': binary.length,
    };

    test('places the helper where each package bundles it', () {
      expect(
        remoteHelperBundleDirectory(
          executableDirectory: '/opt/gitlama',
          macOS: false,
          windows: false,
          target: RemoteHelperTarget.linuxX86_64,
        ),
        '/opt/gitlama/lib/remote-helper/linux-x86_64',
      );
      expect(
        remoteHelperBundleDirectory(
          executableDirectory: '/Applications/GitLama.app/Contents/MacOS',
          macOS: true,
          windows: false,
          target: RemoteHelperTarget.macosArm64,
        ),
        '/Applications/GitLama.app/Contents/MacOS/../Resources/'
        'remote-helper/macos-arm64',
      );
      expect(
        remoteHelperBundleDirectory(
          executableDirectory: r'C:\GitLama',
          macOS: false,
          windows: true,
          target: RemoteHelperTarget.macosX86_64,
        ),
        r'C:\GitLama\remote-helper\macos-x86_64',
      );
    });

    test('loads a verified helper of this build', () async {
      final binary = utf8.encode('helper');
      final executable = bundle(binary, descriptor(binary));
      final artifact = await loadBundledHelper(
        buildId: testBuildId,
        target: RemoteHelperTarget.linuxX86_64,
        executable: executable,
      );
      expect(artifact, isNotNull);
      expect(artifact!.bytes, binary);
      expect(artifact.target, RemoteHelperTarget.linuxX86_64);
      expect(artifact.sha256, sha256.convert(binary).toString());
      expect(
        artifact.installPath,
        '~/.local/lib/gitlama/remote/$testBuildId/gitlama-remote-helper',
      );
    });

    test('each host platform gets its own helper', () async {
      final linux = utf8.encode('linux helper');
      final mac = utf8.encode('mac helper');
      final executable = bundle(linux, descriptor(linux));
      bundle(
        mac,
        descriptor(mac, target: RemoteHelperTarget.macosArm64),
        target: RemoteHelperTarget.macosArm64,
      );
      final arm = await loadBundledHelper(
        buildId: testBuildId,
        target: RemoteHelperTarget.macosArm64,
        executable: executable,
      );
      expect(arm?.bytes, mac);
      expect(arm?.target, RemoteHelperTarget.macosArm64);
      expect(
        await loadBundledHelper(
          buildId: testBuildId,
          target: RemoteHelperTarget.macosX86_64,
          executable: executable,
        ),
        isNull,
      );
      // A descriptor naming another platform than its directory is refused.
      bundle(
        mac,
        descriptor(mac, target: RemoteHelperTarget.linuxX86_64),
        target: RemoteHelperTarget.macosArm64,
      );
      expect(
        await loadBundledHelper(
          buildId: testBuildId,
          target: RemoteHelperTarget.macosArm64,
          executable: executable,
        ),
        isNull,
      );
    });

    test('refuses another build, an altered binary or no bundle', () async {
      final binary = utf8.encode('helper');
      Future<RemoteHelperArtifact?> load(String executable) =>
          loadBundledHelper(
            buildId: testBuildId,
            target: RemoteHelperTarget.linuxX86_64,
            executable: executable,
          );
      expect(await load('$executableDirectory/gitlama'), isNull);
      final executable = bundle(binary, {
        ...descriptor(binary),
        'build_id': 'f' * 40,
      });
      expect(await load(executable), isNull);
      bundle(utf8.encode('altered'), descriptor(binary));
      expect(await load(executable), isNull);
    });
  });

  group('development helper', () {
    late Directory checkout;
    late String executable;

    setUp(() {
      checkout = Directory.systemTemp.createTempSync('gitlama-checkout');
      // Where `flutter run` places the macOS debug application.
      final bin = Directory(
        '${checkout.path}/build/macos/Build/Products/Debug/'
        'GitLama.app/Contents/MacOS',
      )..createSync(recursive: true);
      executable = '${bin.path}/GitLama';
    });
    tearDown(() => checkout.deleteSync(recursive: true));

    void place(List<int> binary, {String buildId = testBuildId}) {
      final directory = Directory(
        '${checkout.path}/build/'
        '${developmentHelperDirectory(RemoteHelperTarget.linuxX86_64)}',
      )..createSync(recursive: true);
      File('${directory.path}/gitlama-remote-helper').writeAsBytesSync(binary);
      File('${directory.path}/gitlama-remote-helper.json').writeAsStringSync(
        jsonEncode({
          'schema': 1,
          'build_id': buildId,
          'target': RemoteHelperTarget.linuxX86_64.triple,
          'sha256': sha256.convert(binary).toString(),
          'bytes': binary.length,
        }),
      );
    }

    test(
      'a build from source finds the helper its build hook placed',
      () async {
        final binary = utf8.encode('development helper');
        place(binary);
        final artifact = await loadBundledHelper(
          buildId: testBuildId,
          target: RemoteHelperTarget.linuxX86_64,
          executable: executable,
        );
        // The build hook builds development helpers on macOS and Linux only.
        expect(artifact?.bytes, Platform.isWindows ? isNull : binary);
      },
    );

    test('another build or an installed package ignores it', () async {
      final binary = utf8.encode('development helper');
      place(binary, buildId: 'f' * 40);
      expect(
        await loadBundledHelper(
          buildId: testBuildId,
          target: RemoteHelperTarget.linuxX86_64,
          executable: executable,
        ),
        isNull,
      );
      // An installed application has no `build` directory above it, even
      // with a bundle next to the checkout.
      place(binary);
      expect(
        await loadBundledHelper(
          buildId: testBuildId,
          target: RemoteHelperTarget.linuxX86_64,
          executable:
              '${checkout.path}/Applications/GitLama.app/'
              'Contents/MacOS/GitLama',
        ),
        isNull,
      );
    });
  });

  group('installation', () {
    late _InstallProcess process;
    late List<List<String>> starts;

    setUp(() {
      process = _InstallProcess();
      starts = [];
    });

    SshRemoteConnectionRepository repository({
      Duration timeout = remoteHelperInstallTimeout,
      RemoteHelperArtifact? bundled,
    }) => SshRemoteConnectionRepository(
      testBuildId,
      starter: (executable, arguments, {environment}) async {
        starts.add(arguments);
        return process;
      },
      resolveExecutable: () => '/usr/bin/ssh',
      versionReader: (_) async => 'OpenSSH_9.6p1',
      helperLoader: (target) async => bundled,
      installTimeout: timeout,
    );

    test('streams the helper into the fixed command', () async {
      final bytes = List<int>.generate(600 * 1024, (index) => index % 251);
      final artifact = _artifact(bytes);
      final installing = repository().installHelper(
        alias: 'devbox',
        artifact: artifact,
      );
      await settle();
      expect(
        starts.single,
        sshInstallArguments(
          'devbox',
          testBuildId,
          artifact.sha256,
          RemoteHelperTarget.linuxX86_64,
        ),
      );
      expect(process.received.toBytes(), bytes);
      expect(process.stdinClosed, isTrue);
      process.finish(0, 'welcome to the host\nGITLAMA-INSTALL 1 installed\n');
      await installing;
    });

    test('maps each installer result to its failure', () async {
      const results = {
        'platform': RemoteFailureCode.unsupportedPlatform,
        'tools': RemoteFailureCode.installFailed,
        'directory': RemoteFailureCode.installDirectory,
        'write': RemoteFailureCode.installWrite,
        'digest': RemoteFailureCode.installDigest,
        'execute': RemoteFailureCode.installExecute,
      };
      for (final MapEntry(:key, :value) in results.entries) {
        process = _InstallProcess();
        final installing = repository().installHelper(
          alias: 'devbox',
          artifact: _artifact([1, 2, 3]),
        );
        await settle();
        process.finish(3, 'GITLAMA-INSTALL 1 $key\n');
        await expectLater(installing, _fails(value), reason: key);
      }
    });

    test('ssh failures and silent exits are typed', () async {
      final unreachable = repository().installHelper(
        alias: 'devbox',
        artifact: _artifact([1]),
      );
      await settle();
      process.finish(255);
      await expectLater(
        unreachable,
        _fails(RemoteFailureCode.sshConnectionFailed),
      );

      process = _InstallProcess();
      final silent = repository().installHelper(
        alias: 'devbox',
        artifact: _artifact([1]),
      );
      await settle();
      process.finish(0, 'login banner\n');
      await expectLater(silent, _fails(RemoteFailureCode.installFailed));
    });

    test('cancel and timeout terminate the installer', () async {
      final cancel = Completer<void>();
      final canceled = repository().installHelper(
        alias: 'devbox',
        artifact: _artifact([1]),
        cancel: cancel.future,
      );
      await settle();
      cancel.complete();
      await expectLater(canceled, _fails(RemoteFailureCode.canceled));
      expect(process.terminated, 1);

      process = _InstallProcess();
      final stuck = repository(
        timeout: const Duration(milliseconds: 10),
      ).installHelper(alias: 'devbox', artifact: _artifact([1]));
      await expectLater(stuck, _fails(RemoteFailureCode.timedOut));
      expect(process.terminated, 1);
    });

    test('only a helper of this build is offered or installed', () async {
      final foreign = RemoteHelperArtifact(
        buildId: 'f' * 40,
        target: RemoteHelperTarget.linuxX86_64,
        sha256: 'a' * 64,
        bytes: const [1],
      );
      const linux = RemoteHelperTarget.linuxX86_64;
      expect(await repository(bundled: foreign).bundledHelper(linux), isNull);
      final own = _artifact([1]);
      expect(await repository(bundled: own).bundledHelper(linux), same(own));
      // A Mac host never gets a helper built for another platform.
      expect(
        await repository(
          bundled: own,
        ).bundledHelper(RemoteHelperTarget.macosArm64),
        isNull,
      );
      await expectLater(
        repository().installHelper(alias: 'devbox', artifact: foreign),
        _fails(RemoteFailureCode.installUnavailable),
      );
      expect(starts, isEmpty);
    });
  });

  group('installation command', () {
    late Directory home;

    setUp(
      () => home = Directory.systemTemp.createTempSync('gitlama-install-home'),
    );
    tearDown(() => home.deleteSync(recursive: true));

    /// The helper platform of the machine running the tests, if any.
    final host = SysInfo.target;

    /// Login shells the installer meets: sh, bash and macOS's zsh.
    final shells = [
      for (final shell in ['/bin/sh', '/bin/bash', '/bin/zsh'])
        if (File(shell).existsSync()) shell,
    ];

    Future<ProcessResult> install(
      List<int> bytes, {
      String? digest,
      String shell = '/bin/sh',
      RemoteHelperTarget? target,
      String path = '/usr/bin:/bin',
    }) async {
      final process = await Process.start(
        shell,
        [
          '-c',
          sshInstallCommand(
            testBuildId,
            digest ?? _digest(bytes),
            target ?? host!,
          ),
        ],
        environment: {'HOME': home.path, 'PATH': path},
      );
      process.stdin.add(bytes);
      await process.stdin.close();
      final output = await process.stdout.transform(latin1.decoder).join();
      await process.stderr.drain<void>();
      return ProcessResult(process.pid, await process.exitCode, output, '');
    }

    List<int> reporting(String buildId) =>
        utf8.encode('#!/bin/sh\nprintf \'{"buildId":"$buildId"}\\n\'\n');

    File installed() => File(
      '${home.path}/.local/lib/gitlama/remote/$testBuildId/'
      'gitlama-remote-helper',
    );

    test('installs a helper that reports this build', () async {
      for (final shell in shells) {
        final script = reporting(testBuildId);
        final result = await install(script, shell: shell);
        expect(result.stdout, 'GITLAMA-INSTALL 1 installed\n', reason: shell);
        expect(installed().readAsBytesSync(), script);
        expect(installed().statSync().mode & 0x1ff, 0x1c0);
        expect(installed().parent.listSync().map((entry) => entry.path), [
          installed().path,
        ]);
        installed().deleteSync();
      }
    }, skip: host == null ? 'no helper platform for this machine' : false);

    test('uses shasum where sha256sum is missing, as on macOS', () async {
      // Only the tools the installer needs, with shasum instead of sha256sum.
      final tools = Directory('${home.path}/tools')..createSync();
      for (final tool in [
        'uname',
        'head',
        'wc',
        'tr',
        'cut',
        'chmod',
        'mkdir',
        'mv',
        'rm',
        'grep',
        'sh',
      ]) {
        final resolved = Process.runSync('/bin/sh', [
          '-c',
          'command -v $tool',
        ]).stdout.toString().trim();
        Link('${tools.path}/$tool').createSync(resolved);
      }
      final digest = Process.runSync('/bin/sh', [
        '-c',
        'command -v sha256sum || command -v shasum',
      ]).stdout.toString().trim();
      File('${tools.path}/shasum').writeAsStringSync(
        digest.endsWith('shasum')
            ? '#!/bin/sh\nexec $digest "\$@"\n'
            : '#!/bin/sh\n[ "\$1 \$2" = "-a 256" ] || exit 2\nexec $digest\n',
      );
      Process.runSync('chmod', ['755', '${tools.path}/shasum']);
      final result = await install(reporting(testBuildId), path: tools.path);
      expect(result.stdout, 'GITLAMA-INSTALL 1 installed\n');
      expect(installed().existsSync(), isTrue);
    }, skip: host == null ? 'no helper platform for this machine' : false);

    test('refuses a helper built for another platform', () async {
      final other = RemoteHelperTarget.values.firstWhere(
        (target) => target != host,
      );
      expect(
        (await install(reporting(testBuildId), target: other)).stdout,
        'GITLAMA-INSTALL 1 platform\n',
      );
      expect(installed().existsSync(), isFalse);
    }, skip: host == null ? 'no helper platform for this machine' : false);

    test('refuses a damaged or foreign helper and leaves nothing', () async {
      final script = reporting('f' * 40);
      expect(
        (await install(script, digest: 'a' * 64)).stdout,
        'GITLAMA-INSTALL 1 digest\n',
      );
      expect((await install(script)).stdout, 'GITLAMA-INSTALL 1 execute\n');
      final directory = Directory(
        '${home.path}/.local/lib/gitlama/remote/$testBuildId',
      );
      expect(directory.listSync(), isEmpty);
    }, skip: host == null ? 'no helper platform for this machine' : false);

    test('refuses a symbolic link in the install path', () async {
      Directory('${home.path}/elsewhere').createSync();
      Directory('${home.path}/.local').createSync();
      Link('${home.path}/.local/lib').createSync('${home.path}/elsewhere');
      Directory('${home.path}/elsewhere/gitlama').createSync();
      Link(
        '${home.path}/elsewhere/gitlama/remote',
      ).createSync('${home.path}/elsewhere');
      expect(
        (await install(utf8.encode('x'))).stdout,
        'GITLAMA-INSTALL 1 directory\n',
      );
      expect(
        Directory('${home.path}/elsewhere/$testBuildId').existsSync(),
        isFalse,
      );
    }, skip: host == null ? 'no helper platform for this machine' : false);
  });
}

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

/// The machine running the tests, read from `uname` once.
abstract final class SysInfo {
  /// The helper platform matching this machine; null on others.
  static final RemoteHelperTarget? target = () {
    if (Platform.isWindows) return null;
    final system = Process.runSync('uname', ['-s']).stdout.toString().trim();
    final machine = Process.runSync('uname', ['-m']).stdout.toString().trim();
    return RemoteHelperTarget.values
        .where((target) => target.host == '$system/$machine')
        .firstOrNull;
  }();
}
