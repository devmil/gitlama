import '../models/diff_syntax.dart';
import '../models/repository_state.dart';

/// Syntax colours for rows of a session's accepted diff projections: read on
/// the computer that owns the repository, never awaited by a diff read.
abstract interface class DiffSyntaxRepository {
  /// Categories for up to `ContractLimits.syntaxPageRows` rows from
  /// [offset] of the accepted [origin] projection [diffRequestId].
  Future<DiffSyntaxPage> diffSyntaxPage(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
    required int offset,
    required int maximumRows,
  });

  /// Cancels one request; idempotent.
  Future<bool> cancelDiffSyntax(
    RepositorySessionIdentity identity, {
    required DiffSyntaxOrigin origin,
    required BigInt diffRequestId,
    required BigInt syntaxRequestId,
  });
}
