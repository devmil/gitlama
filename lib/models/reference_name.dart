import 'dart:convert';

import 'repository_state.dart';

/// What a full Git reference name names.
enum ReferenceKind {
  /// `refs/heads/<branch>`.
  localBranch,

  /// `refs/remotes/<remote>/<branch>`, also a remote's symbolic `HEAD`.
  remoteBranch,

  /// `refs/tags/<tag>`.
  tag,

  /// `refs/stash`.
  stash,

  /// Anything else: notes, replace refs, pseudo refs.
  other,
}

const _heads = [
  0x72, 0x65, 0x66, 0x73, 0x2f, 0x68, 0x65, 0x61, 0x64, 0x73, 0x2f, //
]; // refs/heads/
const _remotes = [
  0x72, 0x65, 0x66, 0x73, 0x2f, 0x72, 0x65, 0x6d, 0x6f, 0x74, 0x65, 0x73, //
  0x2f,
]; // refs/remotes/
const _tags = [
  0x72, 0x65, 0x66, 0x73, 0x2f, 0x74, 0x61, 0x67, 0x73, 0x2f, //
]; // refs/tags/
const _stash = [
  0x72, 0x65, 0x66, 0x73, 0x2f, 0x73, 0x74, 0x61, 0x73, 0x68, //
]; // refs/stash

/// One full reference name, classified and shortened on its bytes.
///
/// Git reference names are bytes. Classification and the short name work on
/// those bytes, so a name that is not valid UTF-8 is never compared in its
/// lossy decoded form; only [display] decodes, for showing.
final class ReferenceName {
  ReferenceName._(this.full, this.kind, this._shortStart);

  /// Classifies [full], such as `refs/remotes/origin/main`.
  factory ReferenceName(List<int> full) {
    final bytes = List<int>.unmodifiable(full);
    if (_startsWith(bytes, _heads) && bytes.length > _heads.length) {
      return ReferenceName._(bytes, ReferenceKind.localBranch, _heads.length);
    }
    if (_startsWith(bytes, _remotes) && bytes.length > _remotes.length) {
      return ReferenceName._(
        bytes,
        ReferenceKind.remoteBranch,
        _remotes.length,
      );
    }
    if (_startsWith(bytes, _tags) && bytes.length > _tags.length) {
      return ReferenceName._(bytes, ReferenceKind.tag, _tags.length);
    }
    if (_same(bytes, _stash)) {
      return ReferenceName._(bytes, ReferenceKind.stash, 5);
    }
    return ReferenceName._(bytes, ReferenceKind.other, 0);
  }

  /// [full] from its decoded form, for names that are carried as text.
  factory ReferenceName.parse(String full) => ReferenceName(utf8.encode(full));

  /// `refs/heads/<branch>`.
  factory ReferenceName.localBranch(List<int> branch) =>
      ReferenceName([..._heads, ...branch]);

  /// `refs/remotes/<remote>/<branch>`.
  factory ReferenceName.remoteBranch(List<int> remote, List<int> branch) =>
      ReferenceName([..._remotes, ...remote, 0x2f, ...branch]);

  /// `refs/tags/<tag>`.
  factory ReferenceName.tag(List<int> tag) => ReferenceName([..._tags, ...tag]);

  /// The full name of the stash, the newest stash entry.
  static const stashText = 'refs/stash';

  /// The full name's bytes.
  final List<int> full;
  final ReferenceKind kind;
  final int _shortStart;

  /// The name people know it by, as bytes: `main` for a local branch,
  /// `origin/main` for a remote-tracking branch, `v1.0` for a tag, `stash`
  /// for the stash and the full name for anything else.
  List<int> get short => full.sublist(_shortStart);

  /// [full] decoded for showing and for text-keyed lookups.
  String get fullText => utf8.decode(full, allowMalformed: true);

  /// [short] decoded for showing.
  String get display => utf8.decode(short, allowMalformed: true);

  /// The remote of a remote-tracking branch whose remote is one of
  /// [remotes] (the longest match, since remote names may contain `/`), and
  /// the branch within it; null for any other reference.
  ({List<int> remote, List<int> branch})? splitRemote(
    Iterable<List<int>> remotes,
  ) {
    if (kind != ReferenceKind.remoteBranch) return null;
    final rest = short;
    List<int>? best;
    for (final remote in remotes) {
      if (rest.length > remote.length + 1 &&
          rest[remote.length] == 0x2f &&
          _startsWith(rest, remote) &&
          (best == null || remote.length > best.length)) {
        best = remote;
      }
    }
    if (best == null) return null;
    return (remote: best, branch: rest.sublist(best.length + 1));
  }

  /// Whether this is a remote's symbolic `HEAD`, which names no branch.
  bool get isRemoteHead =>
      kind == ReferenceKind.remoteBranch &&
      full.length >= 5 &&
      _same(full.sublist(full.length - 5), const [
        0x2f,
        0x48,
        0x45,
        0x41,
        0x44,
      ]);

  @override
  bool operator ==(Object other) =>
      other is ReferenceName && _same(other.full, full);

  @override
  int get hashCode => Object.hashAll(full);

  @override
  String toString() => 'ReferenceName($kind)';
}

bool _startsWith(List<int> value, List<int> prefix) {
  if (value.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index += 1) {
    if (value[index] != prefix[index]) return false;
  }
  return true;
}

bool _same(List<int> left, List<int> right) =>
    left.length == right.length && _startsWith(left, right);

/// The full name of a local [branch] of [RepositoryRefs.branches].
ReferenceName branchReference(RepositoryReference branch) =>
    switch (branch.fullName) {
      final full? => ReferenceName(full),
      null => ReferenceName.localBranch(branch.name),
    };

/// The full name of [branch], a remote-tracking branch of [remote].
ReferenceName remoteBranchReference(
  RepositoryRemote remote,
  RepositoryReference branch,
) => switch (branch.fullName) {
  final full? => ReferenceName(full),
  null => ReferenceName.remoteBranch(remote.name, branch.name),
};

/// The full name of a [tag] of [RepositoryRefs.tags].
ReferenceName tagReference(RepositoryReference tag) => switch (tag.fullName) {
  final full? => ReferenceName(full),
  null => ReferenceName.tag(tag.name),
};

/// The upstream [branch] tracks, when it has one.
ReferenceName? upstreamOf(RepositoryReference branch) =>
    switch (branch.upstream) {
      final upstream? => ReferenceName(upstream),
      null => null,
    };
