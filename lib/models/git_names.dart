import 'dart:convert';

import 'reference_name.dart';
import 'repository_state.dart';

/// Whether [left] and [right] hold the same bytes. Git names and paths are
/// bytes; two different names that are not valid UTF-8 decode to the same
/// replacement text, so names are compared here and never as decoded text.
bool sameBytes(List<int>? left, List<int>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Whether [bytes] begins with [prefix].
bool startsWithBytes(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index += 1) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

/// Whether the Git name [bytes] is [name]. A name typed or carried as text
/// matches only the exact bytes it encodes to.
bool nameIs(List<int> bytes, String? name) =>
    name != null && sameBytes(bytes, utf8.encode(name));

/// [bytes] as text for display and for requests that take text.
String nameText(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// Full reference names built from and read as text, on top of the
/// byte-level [ReferenceName], which owns the namespaces.
abstract final class RefNames {
  /// `refs/heads/<branch>`.
  static String branch(String name) =>
      ReferenceName.localBranch(utf8.encode(name)).fullText;

  /// `refs/remotes/<remote>/<branch>`.
  static String remoteTracking(String remote, String branch) =>
      ReferenceName.remoteBranch(
        utf8.encode(remote),
        utf8.encode(branch),
      ).fullText;

  /// [reference] without its namespace: a branch, `<remote>/<branch>` or a
  /// tag name; [reference] itself when it is none of these.
  static String shortName(String reference) =>
      ReferenceName(utf8.encode(reference)).display;

  static bool isRemoteTracking(String? reference) =>
      reference != null &&
      ReferenceName(utf8.encode(reference)).kind == ReferenceKind.remoteBranch;
}

/// Lookups by exact name bytes over one snapshot's references.
extension RepositoryRefLookup on RepositoryRefs {
  /// The checked-out local branch, if HEAD is on one.
  RepositoryReference? get headBranch =>
      branches.where((branch) => branch.head).firstOrNull;

  /// The local branch named [name].
  RepositoryReference? branchNamed(String name) {
    final bytes = utf8.encode(name);
    return branches
        .where((branch) => sameBytes(branch.name, bytes))
        .firstOrNull;
  }

  /// The tag named [name].
  RepositoryReference? tagNamed(String name) {
    final bytes = utf8.encode(name);
    return tags.where((tag) => sameBytes(tag.name, bytes)).firstOrNull;
  }

  /// The stash entry whose selector (`stash@{n}`) is [selector].
  RepositoryStash? stashWithSelector(String? selector) {
    if (selector == null) return null;
    final bytes = utf8.encode(selector);
    return stashes
        .where((stash) => sameBytes(stash.selector, bytes))
        .firstOrNull;
  }

  /// The local branch whose upstream is the fully qualified [reference].
  RepositoryReference? branchTracking(String reference) {
    final bytes = utf8.encode(reference);
    return branches
        .where((branch) => sameBytes(branch.upstream, bytes))
        .firstOrNull;
  }

  /// The remote and branch of the remote-tracking branch [shortName]
  /// (`<remote>/<branch>`). A remote name may contain a slash, so the longest
  /// configured remote name that prefixes it wins.
  ({String remote, String branch})? splitRemoteTracking(String shortName) {
    final bytes = utf8.encode(shortName);
    final candidates = remotes.toList()
      ..sort((left, right) => right.name.length.compareTo(left.name.length));
    for (final remote in candidates) {
      final prefix = [...remote.name, 0x2f];
      if (bytes.length <= prefix.length || !startsWithBytes(bytes, prefix)) {
        continue;
      }
      return (
        remote: nameText(remote.name),
        branch: nameText(bytes.sublist(prefix.length)),
      );
    }
    return null;
  }

  /// The remote and branch whose remote-tracking branch is the fully
  /// qualified [reference], when such a branch is fetched.
  ({String remote, String branch})? remoteBranchOf(String? reference) {
    if (reference == null) return null;
    final bytes = utf8.encode(reference);
    for (final remote in remotes) {
      for (final branch in remote.branches) {
        if (sameBytes(bytes, remoteBranchReference(remote, branch).full)) {
          return (remote: nameText(remote.name), branch: nameText(branch.name));
        }
      }
    }
    return null;
  }

  /// The upstream of the local branch [branch] as `remote/branch`, or null
  /// when it has none.
  String? upstreamLabelOf(String branch) {
    final reference = branchNamed(branch);
    final upstream = reference == null ? null : upstreamOf(reference);
    if (upstream == null) return null;
    return upstream.kind == ReferenceKind.remoteBranch
        ? upstream.display
        : upstream.fullText;
  }

  /// Every remote-tracking branch as a reference named `<remote>/<branch>`,
  /// marked as published.
  List<RepositoryReference> get remoteTrackingReferences => [
    for (final remote in remotes)
      for (final branch in remote.branches)
        RepositoryReference(
          name: [...remote.name, 0x2f, ...branch.name],
          target: branch.target,
          published: true,
        ),
  ];
}

/// The paths a patch of one file needs: [path], and the path it was renamed
/// from when that differs, since a rename is only complete with its source.
List<List<int>> filePatchPaths(List<int> path, List<int>? oldPath) => [
  path,
  if (oldPath != null && !sameBytes(oldPath, path)) oldPath,
];
