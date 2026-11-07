import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/git_names.dart';
import 'package:gitlama/models/repository_state.dart';

void main() {
  RepositoryReference branch(List<int> name, {List<int>? upstream}) =>
      RepositoryReference(name: name, target: 'a' * 40, upstream: upstream);

  test('names that are not UTF-8 never match as decoded text', () {
    // Both decode to the same replacement character.
    final first = [0x66, 0xff];
    final second = [0x66, 0xfe];
    expect(
      utf8.decode(first, allowMalformed: true),
      utf8.decode(second, allowMalformed: true),
    );
    final refs = RepositoryRefs(
      branches: [branch(first), branch(second)],
      tags: [branch(second)],
      stashes: [
        RepositoryStash(selector: second, objectId: 'b' * 40, subject: []),
      ],
    );
    final decoded = utf8.decode(first, allowMalformed: true);
    expect(refs.branchNamed(decoded), isNull);
    expect(refs.tagNamed(decoded), isNull);
    expect(refs.stashWithSelector(decoded), isNull);
    expect(nameIs(first, decoded), isFalse);
    expect(nameIs(utf8.encode('main'), 'main'), isTrue);
    expect(nameIs(utf8.encode('main'), null), isFalse);
  });

  test('lookups compare exact bytes', () {
    final refs = RepositoryRefs(
      branches: [
        branch(
          utf8.encode('main'),
          upstream: utf8.encode('refs/remotes/origin/main'),
        ),
        branch(utf8.encode('topic')),
      ],
      tags: [branch(utf8.encode('v1.0'))],
      stashes: [
        RepositoryStash(
          selector: utf8.encode('stash@{1}'),
          objectId: 'c' * 40,
          subject: utf8.encode('WIP'),
        ),
      ],
    );
    expect(refs.branchNamed('topic')?.name, utf8.encode('topic'));
    expect(refs.branchNamed('topi'), isNull);
    expect(refs.tagNamed('v1.0'), isNotNull);
    expect(refs.stashWithSelector('stash@{1}')?.objectId, 'c' * 40);
    expect(refs.stashWithSelector(null), isNull);
    expect(
      refs.branchTracking('refs/remotes/origin/main')?.name,
      utf8.encode('main'),
    );
  });

  test('a remote name with a slash splits at the longest remote', () {
    final refs = RepositoryRefs(
      remotes: [
        RepositoryRemote(
          name: utf8.encode('team'),
          displayUrl: const [],
          branches: [branch(utf8.encode('team/fix'))],
        ),
        RepositoryRemote(
          name: utf8.encode('team/fork'),
          displayUrl: const [],
          branches: [branch(utf8.encode('fix'))],
        ),
      ],
    );
    expect(refs.splitRemoteTracking('team/fork/fix'), (
      remote: 'team/fork',
      branch: 'fix',
    ));
    expect(refs.splitRemoteTracking('team/x'), (remote: 'team', branch: 'x'));
    expect(refs.splitRemoteTracking('other/x'), isNull);
    expect(refs.remoteBranchOf('refs/remotes/team/fork/fix'), (
      remote: 'team/fork',
      branch: 'fix',
    ));
    expect(refs.remoteBranchOf('refs/remotes/team/team/fix'), (
      remote: 'team',
      branch: 'team/fix',
    ));
    expect(refs.remoteBranchOf('refs/remotes/team/missing'), isNull);
    expect(refs.remoteTrackingReferences.map((ref) => utf8.decode(ref.name)), [
      'team/team/fix',
      'team/fork/fix',
    ]);
  });

  test('a patch of a renamed file carries its source path', () {
    expect(filePatchPaths([1, 2], [1, 2]), [
      [1, 2],
    ]);
    expect(filePatchPaths([1, 2], [3]), [
      [1, 2],
      [3],
    ]);
    expect(filePatchPaths([1], null), [
      [1],
    ]);
    expect(startsWithBytes([1, 2, 3], [1, 2]), isTrue);
    expect(startsWithBytes([1], [1, 2]), isFalse);
    expect(RefNames.shortName('refs/remotes/origin/main'), 'origin/main');
    expect(RefNames.isRemoteTracking('refs/heads/x'), isFalse);
  });
}
