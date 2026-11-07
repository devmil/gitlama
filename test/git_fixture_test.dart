import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/git_fixture.dart';

void main() {
  test(
    'isolated fixture covers unborn, unusual paths, bytes and hooks',
    () async {
      final fixture = await GitFixture.create();
      try {
        final unborn = await fixture.run([
          'status',
          '--porcelain=v2',
          '--branch',
        ]);
        expect(unborn.stdout, contains('# branch.oid (initial)'));
        expect(
          (await fixture.run([
            'config',
            '--local',
            '--get',
            'core.autocrlf',
          ])).stdout.toString().trim(),
          'false',
        );

        await fixture.writeBytes('space ünicode.txt', [0x6c, 0x66, 0x0a]);
        await fixture.writeBytes('crlf.txt', [
          0x63,
          0x72,
          0x6c,
          0x66,
          0x0d,
          0x0a,
        ]);
        final hook = File(
          '${fixture.worktree.path}${Platform.pathSeparator}.git${Platform.pathSeparator}hooks${Platform.pathSeparator}pre-commit',
        );
        await hook.parent.create(recursive: true);
        await hook.writeAsString('exit 99\n');
        await fixture.commitAll('byte fixture');

        expect(await File('${fixture.worktree.path}/crlf.txt').readAsBytes(), [
          0x63,
          0x72,
          0x6c,
          0x66,
          0x0d,
          0x0a,
        ]);
        final names = await fixture.run(['ls-files', '-z']);
        expect(names.stdout, contains('space ünicode.txt'));
      } finally {
        await fixture.dispose();
      }
    },
  );

  test('isolated fixture builds bare, shallow and linked worktrees', () async {
    final fixture = await GitFixture.create();
    try {
      await fixture.writeBytes('base.txt', 'base\n'.codeUnits);
      await fixture.commitAll('base');

      final bare = Directory('${fixture.root.path}/bare.git');
      await fixture.run(['init', '-q', '--bare', bare.path]);
      final shallow = Directory('${fixture.root.path}/shallow');
      await fixture.run([
        'clone',
        '-q',
        '--depth=1',
        fixture.worktree.uri.toString(),
        shallow.path,
      ]);
      final linked = Directory('${fixture.root.path}/linked');
      await fixture.run(['worktree', 'add', '-q', '-b', 'linked', linked.path]);

      expect(File('${bare.path}/HEAD').existsSync(), isTrue);
      expect(File('${shallow.path}/.git/shallow').existsSync(), isTrue);
      expect(File('${linked.path}/.git').existsSync(), isTrue);
    } finally {
      await fixture.dispose();
    }
  });

  test('isolated fixture builds merge-heavy and conflict states', () async {
    final fixture = await GitFixture.create();
    try {
      await fixture.writeBytes('shared.txt', 'base\n'.codeUnits);
      await fixture.commitAll('base');
      await fixture.run(['checkout', '-q', '-b', 'topic']);
      await fixture.writeBytes('shared.txt', 'topic\n'.codeUnits);
      await fixture.commitAll('topic');
      await fixture.run(['checkout', '-q', 'main']);
      await fixture.writeBytes('main.txt', 'main\n'.codeUnits);
      await fixture.commitAll('main side');
      await fixture.run([
        'merge',
        '-q',
        '--no-ff',
        'topic',
        '-m',
        'merge topic',
      ]);
      final parents = await fixture.run(['show', '-s', '--format=%P', 'HEAD']);
      expect((parents.stdout as String).trim().split(' '), hasLength(2));

      await fixture.run(['checkout', '-q', '-b', 'conflict-left']);
      await fixture.writeBytes('shared.txt', 'left\n'.codeUnits);
      await fixture.commitAll('left');
      await fixture.run(['checkout', '-q', 'main']);
      await fixture.writeBytes('shared.txt', 'right\n'.codeUnits);
      await fixture.commitAll('right');
      final conflict = await fixture.run([
        'merge',
        'conflict-left',
      ], allowFailure: true);
      expect(conflict.exitCode, isNonZero);
      final unmerged = await fixture.run(['ls-files', '--unmerged']);
      expect(unmerged.stdout, isNotEmpty);
    } finally {
      await fixture.dispose();
    }
  });

  test('fixture cleanup removes inaccessible files on Unix', () async {
    final fixture = await GitFixture.create();
    final blocked = File('${fixture.worktree.path}/blocked.txt');
    try {
      await blocked.writeAsString('blocked');
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', ['000', blocked.path]);
        expect(chmod.exitCode, 0);
      }
    } finally {
      await fixture.dispose();
    }
    expect(fixture.root.existsSync(), isFalse);
  });
}
