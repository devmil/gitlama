import 'dart:convert';

import 'reference_name.dart';
import 'repository_state.dart';
import 'git_names.dart';

/// One ref standing for a provider branch: its full name, the commit it
/// points at and whether it is the bound remote's remote-tracking branch.
typedef HostingBranchRef = ({String ref, String target, bool remote});

/// The provider branches that full ref names stand for in the bound hosting
/// repository. A remote-tracking branch of the bound remote names its own
/// branch; a local branch names the bound-remote branch it tracks, also once
/// that branch is gone after its pull request merged. Other refs (tags, other
/// remotes, untracked local branches) name none.
final class HostingBranchNames {
  HostingBranchNames._(
    this._remote,
    this._localUpstreams,
    this.branches,
    this._refsByBranch,
  );

  /// The names for [refs] and the bound [remote], derived once per published
  /// refs snapshot.
  factory HostingBranchNames.of(RepositoryRefs refs, List<int> remote) {
    final name = utf8.decode(remote, allowMalformed: true);
    final cached = (_cache[refs] ??= {})[name];
    if (cached != null) return cached;
    String? providerBranch(ReferenceName? reference) {
      final split = reference?.splitRemote([remote]);
      if (split == null) return null;
      return utf8.decode(split.branch, allowMalformed: true);
    }

    final upstreams = <String, String>{};
    final refsByBranch = <String, List<HostingBranchRef>>{};
    for (final branch in refs.branches) {
      final full = branchReference(branch).fullText;
      if (providerBranch(upstreamOf(branch)) case final provider?) {
        upstreams[full] = provider;
        (refsByBranch[provider] ??= []).add((
          ref: full,
          target: branch.target,
          remote: false,
        ));
      }
    }
    for (final remoteRefs in refs.remotes) {
      if (!nameIs(remoteRefs.name, name)) continue;
      for (final branch in remoteRefs.branches) {
        final provider = utf8.decode(branch.name, allowMalformed: true);
        if (provider.isEmpty || provider == 'HEAD') continue;
        (refsByBranch[provider] ??= []).add((
          ref: remoteBranchReference(remoteRefs, branch).fullText,
          target: branch.target,
          remote: true,
        ));
      }
    }
    return _cache[refs]![name] = HostingBranchNames._(
      List.unmodifiable(remote),
      upstreams,
      Set.unmodifiable(refsByBranch.keys),
      refsByBranch,
    );
  }

  static final Expando<Map<String, HostingBranchNames>> _cache = Expando();

  final List<int> _remote;
  final Map<String, String> _localUpstreams;

  /// Every provider branch some ref stands for.
  final Set<String> branches;

  final Map<String, List<HostingBranchRef>> _refsByBranch;

  /// The refs standing for provider [branch]: local branches tracking it,
  /// then its remote-tracking branch.
  List<HostingBranchRef> refsOf(String branch) =>
      _refsByBranch[branch] ?? const [];

  /// The provider branch [ref] stands for, or null.
  String? branchFor(String ref) {
    final split = ReferenceName.parse(ref).splitRemote([_remote]);
    if (split != null) {
      final branch = utf8.decode(split.branch, allowMalformed: true);
      return branch == 'HEAD' ? null : branch;
    }
    return _localUpstreams[ref];
  }
}
