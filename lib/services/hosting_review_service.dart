import '../models/hosting.dart';
import '../repositories/hosting_review_repository.dart';
import 'hosting_connection_service.dart';

final class HostingReviewService {
  HostingReviewService(this._repository, this._connections);

  final HostingReviewRepository _repository;
  final HostingConnectionService _connections;

  Future<HostingReviewPage> load({
    required String connectionId,
    required String repository,
    required int pullRequest,
    required String headSha,
    String? page,
  }) => _repository.load(
    connection: _connection(connectionId),
    repository: repository,
    pullRequest: pullRequest,
    headSha: headSha,
    page: page,
  );

  Future<HostingReviewPreview> preview({
    required String connectionId,
    required String repository,
    required int pullRequest,
    required String headSha,
    required HostingReviewAction action,
    required String body,
    required List<HostingInlineDraft> inlineComments,
  }) => _repository.preview(
    connection: _connection(connectionId),
    repository: repository,
    pullRequest: pullRequest,
    headSha: headSha,
    action: action,
    body: body,
    inlineComments: inlineComments,
  );

  Future<HostingReviewSubmitResult> submit(HostingReviewPreview preview) =>
      _repository.submit(
        connection: _connection(preview.connectionId),
        preview: preview,
      );

  Future<HostingCheckRetryPreview> previewCheckRetry({
    required String connectionId,
    required String repository,
    required String headSha,
    required String checkStableId,
  }) => _repository.previewCheckRetry(
    connection: _connection(connectionId),
    repository: repository,
    headSha: headSha,
    checkStableId: checkStableId,
  );

  Future<HostingReviewSubmitResult> retryCheck(
    HostingCheckRetryPreview preview,
  ) => _repository.retryCheck(
    connection: _connection(preview.connectionId),
    preview: preview,
  );

  Future<HostingReviewDraft?> loadDraft({
    required String connectionId,
    required String repository,
    required int pullRequest,
  }) => _repository.loadDraft(draftKey(connectionId, repository, pullRequest));

  Future<HostingReviewDraft> saveDraft(HostingReviewDraft draft) =>
      _repository.saveDraft(draft);

  Future<void> deleteDraft({
    required String connectionId,
    required String repository,
    required int pullRequest,
  }) =>
      _repository.deleteDraft(draftKey(connectionId, repository, pullRequest));

  Future<bool> cancel({
    required String connectionId,
    required String repository,
    required int pullRequest,
  }) => _repository.cancel(
    connectionId: connectionId,
    repository: repository,
    pullRequest: pullRequest,
  );

  static String draftKey(
    String connectionId,
    String repository,
    int pullRequest,
  ) =>
      '${connectionId.length}:$connectionId${repository.length}:$repository:$pullRequest';

  HostingConnection _connection(String id) {
    final connection = _connections.connections
        .where((value) => value.id == id)
        .firstOrNull;
    if (connection == null || !connection.enabled) {
      throw const HostingReviewException(
        HostingReviewFailure.integrationDisabled,
      );
    }
    return connection;
  }
}
