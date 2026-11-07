import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../models/remote_workspace.dart';
import 'protocol_messages.dart';

/// The oldest supported OpenSSH client (8.9 adds `SessionType` and
/// `ForkAfterAuthentication` handling the launch relies on).
const minimumOpenSshMajor = 8;
const minimumOpenSshMinor = 9;

/// Bound for the `ssh -V` probe.
const sshVersionProbeTimeout = Duration(seconds: 5);

/// Bytes of `ssh -V` stderr considered; the rest is discarded.
const sshVersionProbeBytes = 4096;

/// The fixed SSH options of every remote connection, in order.
const sshFixedArguments = <String>[
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
];

/// The `case` patterns of every host a helper is built for.
final _supportedHosts = RemoteHelperTarget.values
    .map((target) => target.host)
    .join('|');

/// The fixed launch string for POSIX shells, including macOS's zsh. Its only
/// variable part is the validated [buildId]; no user input is ever part of
/// it. A missing helper reports the host's platform. On macOS, a
/// noninteractive login sees only Apple's Git shim, so a Homebrew or
/// `/usr/local` Git comes first when present.
String sshLaunchCommand(String buildId) {
  if (!isValidBuildId(buildId)) {
    throw ArgumentError.value('<redacted>', 'buildId', 'not a build ID');
  }
  return 'h="\$HOME/.local/lib/gitlama/remote/$buildId/gitlama-remote-helper"; '
      'p="\$(uname -s)/\$(uname -m)"; '
      'case "\$p" in $_supportedHosts) ;; '
      "*) printf 'GITLAMA-BOOTSTRAP 1 platform\\n'; exit 3;; esac; "
      'case "\$p" in Darwin/*) for d in /usr/local/bin /opt/homebrew/bin; do '
      '[ ! -x "\$d/git" ] || PATH="\$d:\$PATH"; done; export PATH;; esac; '
      '[ -x "\$h" ] || '
      "{ printf 'GITLAMA-BOOTSTRAP 1 missing %s\\n' \"\$p\"; exit 3; }; "
      'exec "\$h" --stdio';
}

/// The largest helper the installation accepts.
const remoteHelperInstallLimit = 128 * 1024 * 1024;

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// The fixed POSIX installation command. It reads the helper from standard
/// input into a private temporary file beside its destination, verifies the
/// digest and that the file runs and reports [buildId], and only then renames
/// it into place. A host of another platform than [target] is refused. Its
/// only variable parts are the validated [buildId], [sha256] and [target];
/// it answers with one `GITLAMA-INSTALL 1 <result>` line. macOS has
/// `shasum` where Linux has `sha256sum`.
String sshInstallCommand(
  String buildId,
  String sha256,
  RemoteHelperTarget target,
) {
  if (!isValidBuildId(buildId)) {
    throw ArgumentError.value('<redacted>', 'buildId', 'not a build ID');
  }
  if (!_sha256Pattern.hasMatch(sha256)) {
    throw ArgumentError.value('<redacted>', 'sha256', 'not a digest');
  }
  String fail(String result) =>
      "{ printf 'GITLAMA-INSTALL 1 $result\\n'; exit 3; }";
  const limit = remoteHelperInstallLimit;
  return [
    'umask 077',
    'b=$buildId',
    's=$sha256',
    '[ "\$(uname -s)/\$(uname -m)" = ${target.host} ] || ${fail('platform')}',
    '{ command -v sha256sum || command -v shasum; } >/dev/null 2>&1 || '
        '${fail('tools')}',
    'r="\$HOME/.local/lib/gitlama"',
    'd="\$r/remote/\$b"',
    'for p in "\$r" "\$r/remote" "\$d" "\$d/gitlama-remote-helper"; do '
        '[ ! -L "\$p" ] || ${fail('directory')}; done',
    'mkdir -p "\$d" && chmod 700 "\$r" "\$r/remote" "\$d" || '
        '${fail('directory')}',
    't="\$d/.gitlama-remote-helper.\$\$"',
    "trap 'rm -f \"\$t\"' EXIT",
    'head -c ${limit + 1} > "\$t" || ${fail('write')}',
    '[ "\$(wc -c < "\$t" | tr -d " ")" -le $limit ] || ${fail('write')}',
    'if command -v sha256sum >/dev/null 2>&1; then '
        'v="\$(sha256sum < "\$t" | cut -c1-64)"; '
        'else v="\$(shasum -a 256 < "\$t" | cut -c1-64)"; fi',
    '[ "\$v" = "\$s" ] || ${fail('digest')}',
    'chmod 700 "\$t" || ${fail('execute')}',
    '"\$t" --version 2>/dev/null | grep -F -q "\\"buildId\\":\\"\$b\\"" || '
        '${fail('execute')}',
    'mv -f "\$t" "\$d/gitlama-remote-helper" || ${fail('write')}',
    "printf 'GITLAMA-INSTALL 1 installed\\n'",
  ].join('; ');
}

/// The `ssh` argument array that installs a helper on [alias].
List<String> sshInstallArguments(
  String alias,
  String buildId,
  String sha256,
  RemoteHelperTarget target, {
  String? configFile,
}) {
  if (!isValidRemoteAlias(alias)) {
    throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
  }
  return [
    if (configFile != null) ...['-F', configFile],
    ...sshFixedArguments,
    '--',
    alias,
    sshInstallCommand(buildId, sha256, target),
  ];
}

/// The complete `ssh` argument array for [alias]. An alias that is not a
/// supported SSH host or `user@host` throws [RemoteWorkspaceException] with
/// [RemoteFailureCode.unsupported].
///
/// [configFile] replaces the user's SSH configuration with an isolated one.
/// Only qualification fixtures pass it; it is never persisted or offered.
List<String> sshArguments(String alias, String buildId, {String? configFile}) {
  if (!isValidRemoteAlias(alias)) {
    throw const RemoteWorkspaceException(RemoteFailureCode.unsupported);
  }
  return [
    if (configFile != null) ...['-F', configFile],
    ...sshFixedArguments,
    '--',
    alias,
    sshLaunchCommand(buildId),
  ];
}

final _openSshVersion = RegExp(
  r'OpenSSH_(?:for_Windows_)?(\d{1,4})\.(\d{1,4})',
);

/// Parses `OpenSSH_<major>.<minor>` from `ssh -V` output.
({int major, int minor})? parseOpenSshVersion(String text) {
  final match = _openSshVersion.firstMatch(text);
  if (match == null) return null;
  return (major: int.parse(match.group(1)!), minor: int.parse(match.group(2)!));
}

/// Whether `ssh -V` output names a supported OpenSSH client.
bool isSupportedOpenSsh(String text) {
  final version = parseOpenSshVersion(text);
  if (version == null) return false;
  return version.major > minimumOpenSshMajor ||
      (version.major == minimumOpenSshMajor &&
          version.minor >= minimumOpenSshMinor);
}

/// Finds the installed OpenSSH client. Never searches the current directory
/// or relative `PATH` entries.
String? resolveSshExecutable({
  required bool windows,
  required Map<String, String> environment,
  required String currentDirectory,
  required bool Function(String path) isFile,
}) {
  final candidates = <String>[];
  if (windows) {
    final systemRoot = environment['SystemRoot'] ?? environment['SYSTEMROOT'];
    if (systemRoot != null && _isWindowsAbsolute(systemRoot)) {
      candidates.add('${_trimWindows(systemRoot)}\\System32\\OpenSSH\\ssh.exe');
    }
    final current = _trimWindows(currentDirectory).toLowerCase();
    for (final entry
        in (environment['Path'] ?? environment['PATH'] ?? '').split(';')) {
      if (!_isWindowsAbsolute(entry) || entry.contains('"')) continue;
      final directory = _trimWindows(entry);
      if (directory.toLowerCase() == current) continue;
      candidates.add('$directory\\ssh.exe');
    }
  } else {
    candidates.add('/usr/bin/ssh');
    final current = _trimPosix(currentDirectory);
    for (final entry in (environment['PATH'] ?? '').split(':')) {
      if (!entry.startsWith('/')) continue;
      final directory = _trimPosix(entry);
      if (directory == current) continue;
      candidates.add(directory == '/' ? '/ssh' : '$directory/ssh');
    }
  }
  for (final candidate in candidates) {
    if (isFile(candidate)) return candidate;
  }
  return null;
}

bool _isWindowsAbsolute(String path) => RegExp(r'^[A-Za-z]:\\').hasMatch(path);

String _trimWindows(String path) {
  var result = path;
  while (result.endsWith('\\')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _trimPosix(String path) {
  var result = path;
  while (result.length > 1 && result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Reads `ssh -V` output (bounded) or null when the probe failed.
typedef SshVersionReader = Future<String?> Function(String executable);

/// Runs `<executable> -V` without a shell, keeps the first
/// [sshVersionProbeBytes] bytes of stderr and kills the probe after
/// [sshVersionProbeTimeout]. The text is only parsed for a version.
Future<String?> readSshVersion(String executable) async {
  final Process process;
  try {
    process = await Process.start(executable, const ['-V'], runInShell: false);
  } on ProcessException {
    return null;
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  final bytes = <int>[];
  final stdoutDone = process.stdout.drain<void>().catchError((Object _) {});
  final stderrDone = process.stderr
      .listen((chunk) {
        final room = sshVersionProbeBytes - bytes.length;
        if (room > 0) bytes.addAll(chunk.take(room));
      })
      .asFuture<void>()
      .catchError((Object _) {});
  try {
    await Future.wait([
      process.exitCode,
      stdoutDone,
      stderrDone,
    ]).timeout(sshVersionProbeTimeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return null;
  }
  return latin1.decode(bytes);
}
