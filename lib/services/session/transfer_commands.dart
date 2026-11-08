import 'package:devmil_logging/devmil_logging.dart';
import 'package:logging/logging.dart';

import '../../models/clone_attempt.dart';
import '../../models/repository_state.dart';
import '../../models/transfer.dart';
import '../../repositories/transfer_repository.dart';
import '../preview_registry.dart';
import 'session_scope.dart';

/// Fetch, pull and push of the active repository, and the background fetch.
final _log = Logger('Transfers');

final class TransferCommands {
  TransferCommands(this._repository, this._scope, PreviewRegistry previews)
    : _previews = previews.sessions();

  final TransferRepositorySessionRepository _repository;
  final SessionScope _scope;
  final PreviewTokens<RepositorySessionIdentity> _previews;

  Future<TransferPreview> preview(TransferRequest request) async {
    final identity = _scope.requireCurrent();
    final preview = await _trace(
      'transfer_preview',
      request.kind,
      () => _repository.previewTransfer(identity, request),
    );
    _previews[preview.token] = identity;
    return preview;
  }

  Future<TransferExecutionResult> execute(
    TransferPreview preview, {
    TransferCredentials? credentials,
  }) async {
    _scope.ensureActive();
    final identity = _previews[preview.token];
    if (identity == null) throw unknownPreviewFailure;
    Future<TransferExecutionResult> run() => _trace(
      'transfer_execute',
      preview.kind,
      () => _repository.executeTransfer(
        identity,
        preview.token,
        credentials: credentials,
      ),
    );
    final result = preview.kind == TransferKind.pull
        ? await _scope.followingHead(
            identity,
            run,
            (result) =>
                result.state == TransferExecutionState.completed ||
                result.state == TransferExecutionState.reconciledWithWarning,
          )
        : await run();
    // A credential or host-key retry runs the same preview again.
    final retryable =
        result.failure == TransferFailureCode.authentication ||
        result.failure == TransferFailureCode.hostKey;
    if (!retryable) _previews.remove(preview.token);
    return result;
  }

  /// Deletes remote-tracking refs of [session] a fetch could not update.
  Future<TransferExecutionResult> deleteTrackingRefs(
    RepositorySessionIdentity session,
    List<String> references,
  ) {
    _scope.ensureActive();
    return _repository.deleteTrackingRefs(session, references);
  }

  Future<bool> cancel(TransferPreview preview) async {
    final identity = _previews[preview.token];
    if (identity == null) return false;
    return _repository.cancelTransfer(identity, preview.token);
  }

  Future<HostKeyChallenge> probeHostKey(TransferPreview preview) {
    final identity = _previews[preview.token];
    if (identity == null) throw unknownPreviewFailure;
    return _repository.probeTransferHostKey(identity, preview.token);
  }

  Future<void> resolveHostKey(
    TransferPreview preview,
    HostKeyChallenge challenge, {
    required bool accept,
  }) {
    final identity = _previews[preview.token];
    if (identity == null) throw unknownPreviewFailure;
    return _repository.resolveTransferHostKey(
      identity,
      preview.token,
      challenge,
      accept: accept,
    );
  }

  /// Fetches [session]'s remote without prompting. A fetch that cannot run
  /// is left for the next run.
  Future<void> backgroundFetch(RepositorySessionIdentity session) async {
    try {
      final preview = await _trace(
        'background_fetch_preview',
        TransferKind.fetch,
        () => _repository.previewTransfer(
          session,
          const TransferRequest(kind: TransferKind.fetch),
        ),
      );
      await _trace(
        'background_fetch_execute',
        TransferKind.fetch,
        () => _repository.executeBackgroundFetch(session, preview.token),
      );
    } on TransferException {
      // Nothing to fetch from, or the repository is busy; the next run tries
      // again.
    } on RepositorySessionException {
      // The tab closed while its fetch was prepared.
    }
  }

  // Only closed product enums and elapsed time cross the diagnostic boundary.
  // Never pass previews, requests, credentials or external exceptions to it.
  Future<T> _trace<T>(
    String phase,
    TransferKind kind,
    Future<T> Function() run,
  ) async {
    final watch = Stopwatch()..start();
    final fields = {'kind': kind.index};
    _log.info(DiagnosticEvent('${phase}_started', fields: fields));
    try {
      final result = await run();
      _log.info(
        DiagnosticEvent(
          '${phase}_finished',
          fields: {
            ...fields,
            if (result is TransferExecutionResult) ...{
              'state': result.state.index,
              'failure': result.failure?.index ?? -1,
            },
          },
        ),
      );
      return result;
    } catch (error) {
      _log.warning(
        DiagnosticEvent(
          '${phase}_failed',
          fields: {
            ...fields,
            'failure': error is TransferException ? error.code.index : -1,
          },
        ),
      );
      rethrow;
    } finally {
      _log.fine(
        DiagnosticEvent(
          '${phase}_timing',
          detailed: true,
          fields: {...fields, 'elapsed_ms': watch.elapsedMilliseconds},
        ),
      );
    }
  }
}
