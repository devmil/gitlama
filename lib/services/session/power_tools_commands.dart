import '../../models/power_tools.dart';
import '../../models/repository_state.dart';
import '../../repositories/power_tools_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Diff content search, repository statistics and bisect of the active
/// repository.
final class PowerToolsCommands {
  PowerToolsCommands(
    this._repository,
    this._scope,
    PreviewRegistry previews, {
    this._otherRefs,
  }) : _jobs = previews.sessions(),
       _bisects = previews.sessions();

  final PowerToolsRepositorySessionRepository _repository;

  /// Whether History shows commits only other references reach; a search
  /// of all branches finds the commits History shows.
  final bool Function()? _otherRefs;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _jobs;
  final PreviewTokens<RepositorySessionIdentity> _bisects;

  Future<BigInt> startDiffContentSearch({
    required String query,
    int maximumCommits = 10000,
    bool caseSensitive = false,
    DiffSearchScope scope = DiffSearchScope.allRefs,
  }) async {
    final identity = _scope.requireCurrent();
    final token = await _repository.startDiffContentSearch(
      identity,
      query: query,
      maximumCommits: maximumCommits,
      caseSensitive: caseSensitive,
      scope: scope,
      otherRefs: _otherRefs?.call() ?? false,
    );
    _jobs[token] = identity;
    return token;
  }

  Future<DiffContentSearchResult> pollDiffContentSearch(BigInt token) async {
    final identity = _jobs[token];
    if (identity == null) {
      throw const PowerToolsException(PowerFailureCode.invalidRequest);
    }
    final result = await _repository.pollDiffContentSearch(identity, token);
    if (result.state != PowerJobState.pending) _jobs.remove(token);
    return result;
  }

  Future<BigInt> startRepositoryStatistics() async {
    final identity = _scope.requireCurrent();
    final token = await _repository.startRepositoryStatistics(identity);
    _jobs[token] = identity;
    return token;
  }

  Future<RepositoryStatisticsResult> pollRepositoryStatistics(
    BigInt token,
  ) async {
    final identity = _jobs[token];
    if (identity == null) {
      throw const PowerToolsException(PowerFailureCode.invalidRequest);
    }
    final result = await _repository.pollRepositoryStatistics(identity, token);
    if (result.state != PowerJobState.pending) _jobs.remove(token);
    return result;
  }

  Future<bool> cancelJob(BigInt token) async {
    final identity = _jobs.remove(token);
    if (identity == null) return false;
    return _repository.cancelPowerJob(identity, token);
  }

  Future<BisectState> bisectState() =>
      _repository.bisectState(_scope.requireCurrent());

  Future<BisectPreview> previewBisect(
    BisectAction action, {
    String? good,
    String? bad,
  }) async {
    final identity = _scope.requireCurrent();
    final preview = await _repository.previewBisect(
      identity,
      action,
      good: good,
      bad: bad,
    );
    _bisects[preview.token] = identity;
    return preview;
  }

  Future<BisectExecutionResult> executeBisect(BisectPreview preview) async {
    final identity = _bisects.remove(preview.token);
    if (identity == null) {
      throw const PowerToolsException(PowerFailureCode.invalidRequest);
    }
    return _repository.executeBisect(identity, preview.token);
  }

  Future<bool> cancelBisectPreview(BisectPreview preview) async {
    final identity = _bisects.remove(preview.token);
    if (identity == null) return false;
    return _repository.cancelBisectPreview(identity, preview.token);
  }
}
