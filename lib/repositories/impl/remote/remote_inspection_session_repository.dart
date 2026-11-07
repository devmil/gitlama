import '../../../models/clone_attempt.dart';
import '../../../models/diff.dart';
import '../../../models/diff_renderer.dart';
import '../../../models/diff_syntax.dart';
import '../../../models/inspection.dart';
import '../../../models/remote_workspace.dart';
import '../../../models/repository_state.dart';
import '../../../models/settings.dart';
import '../../change_source_repository.dart';
import '../../diff_syntax_repository.dart';
import '../../inspection_session_repository.dart';

/// The read-only session of an inspector window whose repository is on a
/// remote host.
///
/// Git reads go to the host through the main window's connection
/// (the window's remote inspection calls); content is decoded and rendered on this
/// computer, as the main window does for a remote tab. Restoring a file is
/// not offered.
final class RemoteInspectionSessionRepository
    implements
        InspectionSessionRepository,
        DiffRendererRepositorySessionRepository,
        DiffSyntaxRepository {
  /// [remote] reads the host through the main window; [remoteSource] is the same adapter's
  /// content reads; [detached] decodes and renders on this computer.
  RemoteInspectionSessionRepository(
    this._remote,
    this._remoteSource,
    this._detached,
  );

  final InspectionSessionRepository _remote;
  final ChangeSourceRepositorySessionRepository _remoteSource;

  /// Where content is decoded and rendered: this computer.
  final ChangeSourceRepositorySessionRepository _detached;

  static Future<Never> _notOffered() => Future.error(
    const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
    ),
  );

  @override
  Future<OpenedRepositorySession> openIdentity(
    NativePathIdentity identity,
    int generation,
  ) => _remote.openIdentity(identity, generation);

  @override
  Future<bool> close(RepositorySessionIdentity identity) =>
      _remote.close(identity);

  @override
  Future<CommitInspection> inspectCommit(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
  }) =>
      _remote.inspectCommit(identity, commit: commit, firstParent: firstParent);

  @override
  Future<CommitTreePage> commitTree(
    RepositorySessionIdentity identity, {
    required String commit,
    List<int>? directory,
    int offset = 0,
    int maximumRows = 250,
  }) => _remote.commitTree(
    identity,
    commit: commit,
    directory: directory,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<PathHistoryPage> pathHistory(
    RepositorySessionIdentity identity, {
    String? revision,
    required List<int> path,
    bool directory = false,
    int offset = 0,
    int maximumRows = 100,
    int renameHopsBefore = 0,
  }) => _remote.pathHistory(
    identity,
    revision: revision,
    path: path,
    directory: directory,
    offset: offset,
    maximumRows: maximumRows,
    renameHopsBefore: renameHopsBefore,
  );

  @override
  Future<RangeHistoryResult> rangeHistory(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    required int firstLine,
    required int lastLine,
    int maximumRows = 100,
  }) => _remote.rangeHistory(
    identity,
    revision: revision,
    path: path,
    firstLine: firstLine,
    lastLine: lastLine,
    maximumRows: maximumRows,
  );

  @override
  Future<BlamePage> blame(
    RepositorySessionIdentity identity, {
    required String revision,
    required List<int> path,
    int? firstLine,
    int? lastLine,
    bool detectMoves = true,
    bool detectCopies = true,
    int maximumRows = ContractLimits.pageRows,
  }) => _remote.blame(
    identity,
    revision: revision,
    path: path,
    firstLine: firstLine,
    lastLine: lastLine,
    detectMoves: detectMoves,
    detectCopies: detectCopies,
    maximumRows: maximumRows,
  );

  @override
  Future<BlamePage> blamePage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _remote.blamePage(
    identity,
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<RestorePreview> previewRestore(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
    int byteLimit = 8 * 1024 * 1024,
  }) => _notOffered();

  @override
  Future<RestoreResult> restoreFile(
    RepositorySessionIdentity identity, {
    required BigInt token,
  }) => _notOffered();

  @override
  Future<DiffPage> commitDiff(
    RepositorySessionIdentity identity, {
    required String commit,
    String? firstParent,
    DiffLoadOptions options = const DiffLoadOptions(),
    int maximumRows = ContractLimits.pageRows,
  }) => _remote.commitDiff(
    identity,
    commit: commit,
    firstParent: firstParent,
    options: options,
    maximumRows: maximumRows,
  );

  @override
  Future<DiffPage> diffPage(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required int offset,
    int maximumRows = ContractLimits.pageRows,
  }) => _remote.diffPage(
    identity,
    requestId: requestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<DiffSearchResult> searchDiff(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required List<int> query,
    bool caseSensitive = false,
    int maximumMatches = 1000,
  }) => _remote.searchDiff(
    identity,
    requestId: requestId,
    query: query,
    caseSensitive: caseSensitive,
    maximumMatches: maximumMatches,
  );

  @override
  Future<ImageDiffContent> imageDiff(
    RepositorySessionIdentity identity, {
    String? oldRevision,
    required String newRevision,
    required List<int> oldPath,
    required List<int> newPath,
    int byteLimit = 8 * 1024 * 1024,
  }) async => _detached.decodeImage(
    await _remoteSource.changeSource(
      identity,
      oldRevision: oldRevision,
      newRevision: newRevision,
      oldPath: oldPath,
      newPath: newPath,
      byteLimit: byteLimit,
    ),
  );

  @override
  Future<List<int>> commitFileContent(
    RepositorySessionIdentity identity, {
    required String commit,
    required List<int> path,
  }) => _remote.commitFileContent(identity, commit: commit, path: path);

  @override
  Future<List<int>> diffHunks(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    int maximumPositions = 10000,
  }) => _remote.diffHunks(
    identity,
    requestId: requestId,
    maximumPositions: maximumPositions,
  );

  @override
  Future<List<int>?> diffSelectionPatch(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required bool working,
    required List<String> rowIds,
  }) => _remote.diffSelectionPatch(
    identity,
    requestId: requestId,
    working: working,
    rowIds: rowIds,
  );

  @override
  Future<DiffRendererPreview> validateDiffRenderer(
    RepositorySessionIdentity identity,
    DiffRendererDefinition definition,
  ) => _detached.validateDetachedDiffRenderer(identity, definition);

  @override
  Future<DiffRendererPreview> previewDiffRenderer(
    RepositorySessionIdentity identity, {
    required BigInt requestId,
    required DiffRendererDefinition definition,
  }) async => _detached.previewDetachedDiffRenderer(
    identity,
    await _remoteSource.diffRendererInput(identity, requestId),
    definition,
  );

  @override
  Future<DiffRendererResult> executeDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _detached.executeDetachedDiffRenderer(token);

  @override
  Future<DiffRendererResult> pollDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _detached.pollDetachedDiffRenderer(token);

  @override
  Future<bool> cancelDiffRenderer(
    RepositorySessionIdentity identity,
    BigInt token,
  ) => _detached.cancelDetachedDiffRenderer(token);

  /// Syntax colours are parsed on the host, like every other read.
  DiffSyntaxRepository get _syntax => switch (_remote) {
    final DiffSyntaxRepository syntax => syntax,
    _ => throw const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
    ),
  };

  @override
  Future<DiffSyntaxPage> diffSyntaxPage(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
    required int offset,
    required int maximumRows,
  }) async => _syntax.diffSyntaxPage(
    identity,
    origin: origin,
    diffRequestId: diffRequestId,
    syntaxRequestId: syntaxRequestId,
    offset: offset,
    maximumRows: maximumRows,
  );

  @override
  Future<bool> cancelDiffSyntax(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
  }) async => _syntax.cancelDiffSyntax(
    identity,
    origin: origin,
    diffRequestId: diffRequestId,
    syntaxRequestId: syntaxRequestId,
  );
}
