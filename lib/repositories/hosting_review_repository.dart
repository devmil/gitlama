import '../models/hosting.dart';

abstract interface class HostingReviewRepository {
  Future<HostingReviewPage> load({
    required HostingConnection connection,
    required String repository,
    required int pullRequest,
    required String headSha,
    String? page,
  });

  Future<HostingReviewPreview> preview({
    required HostingConnection connection,
    required String repository,
    required int pullRequest,
    required String headSha,
    required HostingReviewAction action,
    required String body,
    required List<HostingInlineDraft> inlineComments,
  });

  Future<HostingReviewSubmitResult> submit({
    required HostingConnection connection,
    required HostingReviewPreview preview,
  });

  Future<HostingCheckRetryPreview> previewCheckRetry({
    required HostingConnection connection,
    required String repository,
    required String headSha,
    required String checkStableId,
  });

  Future<HostingReviewSubmitResult> retryCheck({
    required HostingConnection connection,
    required HostingCheckRetryPreview preview,
  });

  Future<HostingReviewDraft?> loadDraft(String key);
  Future<HostingReviewDraft> saveDraft(HostingReviewDraft draft);
  Future<void> deleteDraft(String key);

  Future<bool> cancel({
    required String connectionId,
    required String repository,
    required int pullRequest,
  });
}
