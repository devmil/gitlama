import '../../models/reference_name.dart';
import '../../models/history.dart';
import '../../models/history_graph.dart';
import '../../models/repository_state.dart';
import '../../widgets/git_reference_field.dart';
import 'branch_filter.dart';
import 'sidebar.dart';

/// Reference values derived from one immutable [RepositoryRefs] instance.
///
/// Builds read these on every frame. A repository with thousands of references
/// must derive them once per published snapshot, not once per build, so each
/// value is computed on first use and kept for the lifetime of [refs].
final class ReferenceProjection {
  ReferenceProjection._(this.refs);

  static final Expando<ReferenceProjection> _projections = Expando();

  static ReferenceProjection of(RepositoryRefs refs) =>
      _projections[refs] ??= ReferenceProjection._(refs);

  final RepositoryRefs refs;

  late final Map<String, SidebarEntry> historyEntries = historyReferenceEntries(
    refs,
  );

  late final Map<String, Map<String, SidebarEntry>> historyEntriesByCommit =
      _entriesByCommit();

  Map<String, Map<String, SidebarEntry>> _entriesByCommit() {
    final result = <String, Map<String, SidebarEntry>>{};
    for (final entry in historyEntries.entries) {
      if (entry.value.target case final target?) {
        (result[target] ??= {})[entry.key] = entry.value;
      }
    }
    return result;
  }

  late final List<BranchFilterChoice> branchFilterChoices = List.unmodifiable(
    buildBranchFilterChoices(refs),
  );

  late final Map<String, String> alignedUpstreams = alignedHistoryUpstreams(
    refs,
  );

  late final RepositoryReference? headBranch = refs.branches
      .where((branch) => branch.head)
      .firstOrNull;

  late final String? checkedOutRef = switch (headBranch) {
    final branch? => branchReference(branch).fullText,
    null => null,
  };

  late final Map<String, ({int ahead, int behind})> refSyncCounts = {
    for (final branch in refs.branches)
      branchReference(branch).fullText: (
        ahead: branch.ahead,
        behind: branch.behind,
      ),
  };

  List<HistoryTopologyRow>? _choiceCommits;
  List<GitReferenceChoice>? _choices;

  /// Picker choices for these references and the loaded [commits]. The result
  /// keeps its identity while both inputs keep theirs.
  List<GitReferenceChoice> choices(List<HistoryTopologyRow> commits) {
    final cached = _choices;
    if (cached != null && identical(_choiceCommits, commits)) return cached;
    _choiceCommits = commits;
    return _choices = List.unmodifiable(gitReferenceChoices(refs, commits));
  }
}
