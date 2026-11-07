import 'dart:convert';

import '../../models/branch_order.dart';
import '../../models/git_names.dart';
import '../../models/history_graph.dart';
import '../../models/hosting.dart';
import '../../models/hosting_branches.dart';
import '../../models/reference_name.dart';
import '../../models/repository_state.dart';
import '../../services/hosting_repository_session.dart';

/// Pull requests linked to what the active repository shows, for the views
/// that show them. Asking for a reference's pull request starts its lookup,
/// so only branches that come into view cost a provider request.
final class HostingLinks {
  HostingLinks({
    required HostingRepositorySession session,
    required RepositoryRefs refs,
    required this.onOpen,
  }) : _session = session,
       _refs = refs,
       _names = switch (session.binding) {
         HostingBindingResolution(
           state: HostingBindingState.bound,
           :final remote,
         )
             when remote.isNotEmpty =>
           HostingBranchNames.of(refs, remote),
         _ => null,
       };

  final HostingRepositorySession _session;
  final RepositoryRefs _refs;
  final HostingBranchNames? _names;

  /// Opens a pull request's web page.
  final void Function(String webUrl) onOpen;

  /// Pull requests the account authored first, then the open and the merged
  /// ones of looked-up branches. One linked only through its branch goes once
  /// no local or remote-tracking branch stands for that branch anymore.
  List<HostingLinkedPullRequest> get linked {
    final branches = _names?.branches ?? const <String>{};
    return [
      for (final linked in _session.linkedPullRequests)
        if (!linked.viaBranch || branches.contains(linked.pull.sourceBranch))
          linked,
    ];
  }

  bool get lookingUp => _session.lookingUp;

  /// The pull request for each of [refs], which point at commit [objectId],
  /// whose branch has one. A pull request stands only at the commit of its
  /// head: when a local branch and its remote-tracking branch differ, only
  /// the one at the head shows it. When no ref of the branch is at the head
  /// (the pull request or the refs moved since), it stands on the
  /// remote-tracking branch, marked outdated, and the branch is looked up
  /// again. Branches not looked up yet are queued and appear once their
  /// lookup answers.
  Map<String, HistoryReferencePullRequest> pullRequestsForRefs(
    String objectId,
    List<String> refs,
  ) {
    final names = _names;
    if (names == null || refs.isEmpty) return const {};
    final branches = <String, String>{
      for (final ref in refs) ref: ?names.branchFor(ref),
    };
    if (branches.isEmpty) return const {};
    _session.requestBranches(branches.values);
    final result = <String, HistoryReferencePullRequest>{};
    for (final MapEntry(key: ref, value: branch) in branches.entries) {
      final pull = _shownPull(_session.pullRequestsForBranch(branch));
      if (pull == null) continue;
      final head = pull.headSha;
      final open = pull.state == HostingChangeRequestState.open;
      var outdated = false;
      if (head.isNotEmpty) {
        final branchRefs = names.refsOf(branch);
        if (branchRefs.any((candidate) => candidate.target == head)) {
          if (objectId != head) continue;
        } else {
          final remote = branchRefs.where((candidate) => candidate.remote);
          final fallback = remote.isEmpty ? branchRefs : remote;
          if (!fallback.any((candidate) => candidate.ref == ref)) continue;
          if (open) {
            outdated = true;
            _session.recheckBranch(
              branch,
              [for (final candidate in branchRefs) candidate.target].join(' '),
            );
          }
        }
      }
      result[ref] = HistoryReferencePullRequest(
        number: pull.number,
        title: pull.title,
        webUrl: pull.webUrl,
        draft: pull.draft,
        merged: pull.state == HostingChangeRequestState.merged,
        checks: open ? pull.checks.state : HostingCheckState.unknown,
        mergeability: open ? pull.mergeability : HostingMergeability.unknown,
        outdated: outdated,
      );
    }
    return result;
  }

  // A branch's newest open pull request, or else its newest merged one.
  static HostingChangeRequest? _shownPull(List<HostingChangeRequest>? pulls) {
    HostingChangeRequest? shown;
    for (final pull in pulls ?? const <HostingChangeRequest>[]) {
      final open = pull.state == HostingChangeRequestState.open;
      final shownOpen = shown?.state == HostingChangeRequestState.open;
      if (shown == null ||
          (open && !shownOpen) ||
          (open == shownOpen && pull.number > shown.number)) {
        shown = pull;
      }
    }
    return shown;
  }

  /// The pull request's head commit when a local or remote-tracking branch
  /// points at it, so History can show it; otherwise null.
  String? localHead(HostingChangeRequest pull) {
    final head = pull.headSha;
    if (head.isEmpty) return null;
    final present =
        _refs.branches.any((branch) => branch.target == head) ||
        _refs.remotes.any(
          (remote) => remote.branches.any((branch) => branch.target == head),
        );
    return present ? head : null;
  }

  /// The bound remote's main branch and the CI result of the commit its
  /// remote-tracking branch points at, asked for when not known yet; null
  /// without such a branch. The result is unknown until a lookup answers.
  ({String branch, HostingCheckState checks})? defaultBranchChecks() {
    final main = _defaultBranch();
    if (main == null) return null;
    return (
      branch: main.branch,
      checks:
          _session.requestHeadChecks(main.target) ?? HostingCheckState.unknown,
    );
  }

  /// The CI result of the bound remote's main branch for the one of [refs]
  /// that is its remote-tracking branch, when that branch points at commit
  /// [objectId]; asked for when not known yet. Empty until a lookup answers.
  Map<String, HostingCheckState> defaultBranchChecksForRefs(
    String objectId,
    List<String> refs,
  ) {
    final main = _defaultBranch();
    if (main == null || main.target != objectId || !refs.contains(main.ref)) {
      return const {};
    }
    return switch (_session.requestHeadChecks(main.target)) {
      final checks? when checks != HostingCheckState.unknown => {
        main.ref: checks,
      },
      _ => const {},
    };
  }

  // The bound remote's main remote-tracking branch: its name on the remote,
  // its full ref name and the commit it points at.
  ({String branch, String ref, String target})? _defaultBranch() {
    final remote = switch (_session.binding) {
      HostingBindingResolution(state: HostingBindingState.bound, :final remote)
          when remote.isNotEmpty =>
        _refs.remotes
            .where((value) => sameBytes(value.name, remote))
            .firstOrNull,
      _ => null,
    };
    final main = remote == null ? null : mainBranchOf(remote.branches);
    if (remote == null || main == null) return null;
    return (
      branch: utf8.decode(main.name, allowMalformed: true),
      ref: remoteBranchReference(remote, main).fullText,
      target: main.target,
    );
  }

  /// Asks for the pull requests of the branch [ref] names, without waiting.
  void request(String? ref) {
    if (ref == null) return;
    if (_names?.branchFor(ref) case final branch?) {
      _session.requestBranches([branch]);
    }
  }
}
