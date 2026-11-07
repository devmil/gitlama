import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final class GitFixture {
  GitFixture._(this.root, this._environment, this._sentinel);

  final Directory root;
  final Map<String, String> _environment;
  final File _sentinel;

  Directory get worktree =>
      Directory('${root.path}${Platform.pathSeparator}worktree');

  static Future<GitFixture> create() async {
    final root = await Directory.systemTemp.createTemp('gitlama-git-');
    final globalConfig = File(
      '${root.path}${Platform.pathSeparator}global.gitconfig',
    );
    await globalConfig.writeAsString('');
    final sentinel = File(
      '${root.path}${Platform.pathSeparator}credential-helper-ran',
    );
    final askpass = File(
      '${root.path}${Platform.pathSeparator}${Platform.isWindows ? 'askpass.cmd' : 'askpass.sh'}',
    );
    await askpass.writeAsString(
      Platform.isWindows
          ? '@echo off\r\ntype nul > "${sentinel.path}"\r\nexit /b 97\r\n'
          : '#!/bin/sh\n: > "${sentinel.path}"\nexit 97\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['700', askpass.path]);
      if (chmod.exitCode != 0) {
        throw StateError('fixture_askpass_permissions_failed');
      }
    }
    final fixture = GitFixture._(root, {
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': globalConfig.path,
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_ASKPASS': askpass.path,
      'SSH_ASKPASS': askpass.path,
      'GCM_INTERACTIVE': 'Never',
      'GIT_AUTHOR_NAME': 'GitLama Fixture',
      'GIT_AUTHOR_EMAIL': 'fixture@gitlama.invalid',
      'GIT_COMMITTER_NAME': 'GitLama Fixture',
      'GIT_COMMITTER_EMAIL': 'fixture@gitlama.invalid',
    }, sentinel);
    await fixture.run([
      'init',
      '-q',
      '-b',
      'main',
      fixture.worktree.path,
    ], directory: root);
    final disabledHooks = Directory(
      '${root.path}${Platform.pathSeparator}disabled-hooks',
    );
    await disabledHooks.create();
    await fixture.run(['config', 'core.hooksPath', disabledHooks.path]);
    await fixture.run(['config', 'core.autocrlf', 'false']);
    return fixture;
  }

  Future<ProcessResult> run(
    List<String> arguments, {
    Directory? directory,
    bool allowFailure = false,
  }) async {
    final result = await Process.run(
      'git',
      ['-c', 'credential.helper=', ...arguments],
      workingDirectory: (directory ?? worktree).path,
      environment: _environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure && result.exitCode != 0) {
      throw StateError('fixture_git_failed_${result.exitCode}');
    }
    return result;
  }

  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    final file = File('${worktree.path}${Platform.pathSeparator}$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  }

  Future<void> commitAll(String message) async {
    await run(['add', '--all']);
    await run(['commit', '-q', '-m', message]);
  }

  Future<void> dispose() async {
    if (_sentinel.existsSync()) {
      throw StateError('credential_helper_executed');
    }
    await root.delete(recursive: true);
  }
}
