import '../models/history.dart';
import '../models/repository_state.dart';
import '../models/remote_contract.g.dart';

/// History reads of a repository session: the graph, its queries, branch
/// filters, metadata and the reflog. [HistoryService] owns it.
abstract interface class HistoryRepository {
  /// Loads the history from HEAD, branches, remote branches, tags and the
  /// stash; with [otherRefs] also from every other reference.
  Future<HistoryPage> loadHistory(
    RepositorySessionIdentity identity, {
    required bool complete,
    bool otherRefs = false,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<HistoryPage> historyPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<HistoryPage> completeHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<HistoryPage> selectHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String? objectId,
    bool toggle = false,
    bool reveal = false,
    bool focus = true,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<HistoryPage> queryHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryQuery query,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<HistoryPage> collapseHistory(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required String objectId,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<ReflogPage> reflog(
    RepositorySessionIdentity identity, {
    int offset = 0,
    int maximumRows = 256,
  });

  /// Replaces the session's branch filter, which later history loads keep.
  /// Returns the window at [offset] of the filtered view when [requestId]
  /// names the retained history, otherwise null.
  Future<HistoryPage?> filterHistoryBranches(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required HistoryBranchFilter filter,
    int offset = 0,
    int maximumRows = ContractLimits.pageRows,
  });

  Future<List<HistoryMetadata>> historyMetadata(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<String> objectIds,
  });
}
