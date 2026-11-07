import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/reference_name.dart';
import 'package:gitlama/models/repository_state.dart';

List<int> _bytes(String value) => utf8.encode(value);

void main() {
  test('full names are classified and shortened on their bytes', () {
    final cases = {
      'refs/heads/feature/topic': (ReferenceKind.localBranch, 'feature/topic'),
      'refs/remotes/origin/main': (ReferenceKind.remoteBranch, 'origin/main'),
      'refs/tags/v1.0': (ReferenceKind.tag, 'v1.0'),
      'refs/stash': (ReferenceKind.stash, 'stash'),
      'refs/notes/commits': (ReferenceKind.other, 'refs/notes/commits'),
      'refs/heads/': (ReferenceKind.other, 'refs/heads/'),
      'HEAD': (ReferenceKind.other, 'HEAD'),
    };
    for (final MapEntry(key: full, value: (kind, display)) in cases.entries) {
      final name = ReferenceName.parse(full);
      expect(name.kind, kind, reason: full);
      expect(name.display, display, reason: full);
      expect(name.fullText, full);
    }
  });

  test('a name that is not UTF-8 keeps its exact bytes', () {
    final full = [..._bytes('refs/heads/'), 0xff, 0xfe];
    final name = ReferenceName(full);
    expect(name.kind, ReferenceKind.localBranch);
    expect(name.short, [0xff, 0xfe]);
    expect(name, ReferenceName.localBranch([0xff, 0xfe]));
    expect(name, isNot(ReferenceName.localBranch(_bytes('��'))));
  });

  test('a remote branch splits at the longest known remote', () {
    final name = ReferenceName.parse('refs/remotes/team/origin/main');
    final split = name.splitRemote([_bytes('team'), _bytes('team/origin')])!;
    expect(utf8.decode(split.remote), 'team/origin');
    expect(utf8.decode(split.branch), 'main');
    expect(name.splitRemote([_bytes('other')]), isNull);
    expect(ReferenceName.parse('refs/heads/main').splitRemote([]), isNull);
    expect(ReferenceName.parse('refs/remotes/origin/HEAD').isRemoteHead, true);
    expect(ReferenceName.parse('refs/remotes/origin/main').isRemoteHead, false);
  });

  test('references use the full name the core sent', () {
    final remote = RepositoryRemote(
      name: _bytes('origin'),
      displayUrl: const [],
    );
    const reported = RepositoryReference(
      name: [0x6d, 0x61, 0x69, 0x6e],
      fullName: [
        ...[0x72, 0x65, 0x66, 0x73, 0x2f, 0x68, 0x65, 0x61, 0x64, 0x73, 0x2f],
        0x6d, 0x61, 0x69, 0x6e, //
      ],
      target: 'a',
    );
    expect(branchReference(reported).fullText, 'refs/heads/main');
    final double = RepositoryReference(name: _bytes('main'), target: 'a');
    expect(branchReference(double).fullText, 'refs/heads/main');
    expect(
      remoteBranchReference(remote, double).fullText,
      'refs/remotes/origin/main',
    );
    expect(tagReference(double).fullText, 'refs/tags/main');
  });
}
