import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/remote_workspace.dart';
import 'package:gitlama/repositories/impl/remote/ssh_command.dart';

import 'support/fake_remote_process.dart';

void main() {
  test('ssh argument array is the fixed policy', () {
    expect(sshArguments('build-box.lan', testBuildId), [
      '-T',
      '-o',
      'RequestTTY=no',
      '-o',
      'StdinNull=no',
      '-o',
      'BatchMode=yes',
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'ForwardAgent=no',
      '-o',
      'ForwardX11=no',
      '-o',
      'ClearAllForwardings=yes',
      '-o',
      'GSSAPIDelegateCredentials=no',
      '-o',
      'ControlMaster=no',
      '-o',
      'ControlPath=none',
      '-o',
      'ForkAfterAuthentication=no',
      '-o',
      'RemoteCommand=none',
      '-o',
      'SessionType=default',
      '-o',
      'PermitLocalCommand=no',
      '-o',
      'ConnectTimeout=10',
      '-o',
      'ConnectionAttempts=1',
      '-o',
      'ServerAliveInterval=15',
      '-o',
      'ServerAliveCountMax=3',
      '--',
      'build-box.lan',
      sshLaunchCommand(testBuildId),
    ]);
  });

  test('launch string is the documented script with only the build id', () {
    expect(
      sshLaunchCommand(testBuildId),
      'h="\$HOME/.local/lib/gitlama/remote/$testBuildId/gitlama-remote-helper"; '
      'p="\$(uname -s)/\$(uname -m)"; '
      'case "\$p" in Linux/x86_64|Linux/aarch64|Darwin/arm64|Darwin/x86_64) ;; '
      "*) printf 'GITLAMA-BOOTSTRAP 1 platform\\n'; exit 3;; esac; "
      'case "\$p" in Darwin/*) for d in /usr/local/bin /opt/homebrew/bin; do '
      '[ ! -x "\$d/git" ] || PATH="\$d:\$PATH"; done; export PATH;; esac; '
      '[ -x "\$h" ] || '
      "{ printf 'GITLAMA-BOOTSTRAP 1 missing %s\\n' \"\$p\"; exit 3; }; "
      'exec "\$h" --stdio',
    );
    // No part of the alias reaches the remote command.
    final args = sshArguments('alias-zz9', testBuildId);
    expect(args.last.contains('alias-zz9'), isFalse);
    for (final invalid in [
      'A' * 40,
      'abc',
      '${testBuildId}0',
      '$testBuildId;'.substring(1),
      '../../../../../../../../../../../../../x',
    ]) {
      expect(() => sshLaunchCommand(invalid), throwsArgumentError);
    }
  });

  test('user destinations stay one argument', () {
    for (final destination in [
      'user@host',
      'me@192.0.2.1',
      'build.bot@dev-box',
    ]) {
      final args = sshArguments(destination, testBuildId);
      expect(args[args.length - 3], '--');
      expect(args[args.length - 2], destination);
      expect(args.last.contains(destination), isFalse);
      final install = sshInstallArguments(
        destination,
        testBuildId,
        'a' * 64,
        RemoteHelperTarget.linuxX86_64,
      );
      expect(install[install.length - 2], destination);
      expect(install.last.contains(destination), isFalse);
    }
  });

  test('malicious aliases are rejected', () {
    for (final alias in [
      '',
      '-oProxyCommand=sh',
      '-p',
      'host name',
      'host"x',
      "host'x",
      'host\nx',
      'user@@host',
      '-oProxyCommand=x@host',
      'user@host;id',
      'user name@host',
      'user@-host',
      '@host',
      'user@',
      'user@host:22',
      'ssh://x',
      '*',
      'host*',
      'a;b',
      r'$(id)',
      '`id`',
      'a|b',
      'x' * 129,
      '.hidden',
      '_x',
    ]) {
      expect(
        () => sshArguments(alias, testBuildId),
        throwsA(
          isA<RemoteWorkspaceException>().having(
            (e) => e.code,
            'code',
            RemoteFailureCode.unsupported,
          ),
        ),
        reason: 'alias of length ${alias.length}',
      );
    }
    expect(sshArguments('x' * 128, testBuildId), contains('x' * 128));
  });

  group('OpenSSH version parsing', () {
    test('parses and compares against 8.9', () {
      expect(
        parseOpenSshVersion('OpenSSH_9.6p1 Ubuntu-3ubuntu13, OpenSSL 3.0.13'),
        (major: 9, minor: 6),
      );
      expect(parseOpenSshVersion('OpenSSH_for_Windows_9.5p1, LibreSSL 3.8.2'), (
        major: 9,
        minor: 5,
      ));
      expect(isSupportedOpenSsh('OpenSSH_8.9p1 Ubuntu-3'), isTrue);
      expect(isSupportedOpenSsh('OpenSSH_10.0p2'), isTrue);
      expect(isSupportedOpenSsh('OpenSSH_8.8p1'), isFalse);
      expect(isSupportedOpenSsh('OpenSSH_7.4p1'), isFalse);
      expect(isSupportedOpenSsh('Sun_SSH_1.1'), isFalse);
      expect(isSupportedOpenSsh(''), isFalse);
    });
  });

  group('ssh executable resolution', () {
    test('prefers /usr/bin/ssh and never the current directory', () {
      final files = {'/usr/bin/ssh', '/work/repo/ssh', '/opt/ssh/bin/ssh'};
      expect(
        resolveSshExecutable(
          windows: false,
          environment: {'PATH': '/work/repo:/opt/ssh/bin'},
          currentDirectory: '/work/repo',
          isFile: files.contains,
        ),
        '/usr/bin/ssh',
      );
      files.remove('/usr/bin/ssh');
      expect(
        resolveSshExecutable(
          windows: false,
          environment: {'PATH': '.:bin::/work/repo/:/opt/ssh/bin'},
          currentDirectory: '/work/repo',
          isFile: files.contains,
        ),
        '/opt/ssh/bin/ssh',
      );
      expect(
        resolveSshExecutable(
          windows: false,
          environment: {'PATH': '.:/work/repo'},
          currentDirectory: '/work/repo',
          isFile: files.contains,
        ),
        isNull,
      );
    });

    test('windows uses the system OpenSSH first', () {
      final files = {
        r'C:\Windows\System32\OpenSSH\ssh.exe',
        r'C:\repo\ssh.exe',
        r'D:\tools\ssh.exe',
      };
      expect(
        resolveSshExecutable(
          windows: true,
          environment: {'SystemRoot': r'C:\Windows', 'Path': r'C:\repo'},
          currentDirectory: r'C:\repo',
          isFile: files.contains,
        ),
        r'C:\Windows\System32\OpenSSH\ssh.exe',
      );
      files.remove(r'C:\Windows\System32\OpenSSH\ssh.exe');
      expect(
        resolveSshExecutable(
          windows: true,
          environment: {
            'SystemRoot': r'C:\Windows',
            'Path': r'c:\REPO\;.;tools;"D:\tools";D:\tools\',
          },
          currentDirectory: r'C:\repo',
          isFile: files.contains,
        ),
        r'D:\tools\ssh.exe',
      );
    });
  });
}
