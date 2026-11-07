import 'dart:convert';

import 'repository_state.dart';

/// The names a repository's main branch goes by, the preferred one first.
const mainBranchNames = ['main', 'master'];

/// The main branch among [branches]: the first of [mainBranchNames] present.
RepositoryReference? mainBranchOf(Iterable<RepositoryReference> branches) {
  for (final name in mainBranchNames) {
    final bytes = utf8.encode(name);
    for (final branch in branches) {
      if (branch.name.length == bytes.length &&
          Iterable<int>.generate(
            bytes.length,
          ).every((at) => branch.name[at] == bytes[at])) {
        return branch;
      }
    }
  }
  return null;
}

/// [branches] with the main branch first and every other branch in its given
/// order.
List<RepositoryReference> mainBranchFirst(
  Iterable<RepositoryReference> branches,
) {
  final main = mainBranchOf(branches);
  return [?main, ...branches.where((branch) => !identical(branch, main))];
}

/// The full name of the branch [branch] tracks. An upstream that is gone
/// from its remote names nothing to show.
String? upstreamReference(RepositoryReference branch) =>
    switch (branch.upstream) {
      final upstream? when !branch.upstreamGone => utf8.decode(
        upstream,
        allowMalformed: true,
      ),
      _ => null,
    };
