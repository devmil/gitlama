import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/hosting_branches.dart';
import 'package:gitlama/models/repository_state.dart';

void main() {
  test('refs name provider branches only through the bound remote', () {
    final refs = RepositoryRefs(
      branches: [
        RepositoryReference(
          name: 'local-name'.codeUnits,
          target: 'a',
          upstream: 'refs/remotes/origin/feature/topic'.codeUnits,
        ),
        RepositoryReference(
          name: 'fork-work'.codeUnits,
          target: 'b',
          upstream: 'refs/remotes/fork/fork-work'.codeUnits,
        ),
        RepositoryReference(
          name: 'gone'.codeUnits,
          target: 'c',
          upstream: 'refs/remotes/origin/gone'.codeUnits,
          upstreamGone: true,
        ),
        RepositoryReference(name: 'untracked'.codeUnits, target: 'd'),
      ],
    );
    final names = HostingBranchNames.of(refs, 'origin'.codeUnits);

    expect(names.branchFor('refs/heads/local-name'), 'feature/topic');
    expect(
      names.branchFor('refs/remotes/origin/feature/topic'),
      'feature/topic',
    );
    expect(names.branchFor('refs/remotes/origin/HEAD'), isNull);
    expect(names.branchFor('refs/heads/fork-work'), isNull);
    expect(names.branchFor('refs/remotes/fork/fork-work'), isNull);
    expect(names.branchFor('refs/heads/gone'), 'gone');
    expect(names.branchFor('refs/heads/untracked'), isNull);
    expect(names.branchFor('refs/tags/v1'), isNull);
    expect(names.branches, {'feature/topic', 'gone'});
    expect(
      HostingBranchNames.of(
        RepositoryRefs(
          remotes: [
            RepositoryRemote(
              name: 'origin'.codeUnits,
              displayUrl: const [],
              branches: [
                RepositoryReference(name: 'HEAD'.codeUnits, target: 'a'),
                RepositoryReference(name: 'remote-only'.codeUnits, target: 'a'),
              ],
            ),
            RepositoryRemote(
              name: 'fork'.codeUnits,
              displayUrl: const [],
              branches: [
                RepositoryReference(name: 'fork-only'.codeUnits, target: 'b'),
              ],
            ),
          ],
        ),
        'origin'.codeUnits,
      ).branches,
      {'remote-only'},
    );
    expect(
      identical(HostingBranchNames.of(refs, 'origin'.codeUnits), names),
      isTrue,
    );
    expect(
      HostingBranchNames.of(
        refs,
        'fork'.codeUnits,
      ).branchFor('refs/heads/fork-work'),
      'fork-work',
    );
  });
}
