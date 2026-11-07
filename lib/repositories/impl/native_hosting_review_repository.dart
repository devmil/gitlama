import '../../models/hosting.dart';
import '../../rust/api.dart' as api;
import '../../rust/third_party/gitlama_contract/hosting.dart' as native;
import '../../rust/third_party/gitlama_contract/hosting_review.dart'
    as native_review;
import '../hosting_review_repository.dart';
import 'native_mappers.dart';
import 'native_enum_mappers.g.dart';

final class NativeHostingReviewRepository implements HostingReviewRepository {
  @override
  Future<HostingReviewPage> load({
    required HostingConnection connection,
    required String repository,
    required int pullRequest,
    required String headSha,
    String? page,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReviewLoad(
      connection: _connection(connection),
      repository: repository,
      pullRequest: BigInt.from(pullRequest),
      headSha: headSha,
      page: page,
    );
    _throwFailure(result.failure);
    final value = result.page;
    if (value == null) {
      throw const HostingReviewException(HostingReviewFailure.unavailable);
    }
    return _page(value);
  }

  @override
  Future<HostingReviewPreview> preview({
    required HostingConnection connection,
    required String repository,
    required int pullRequest,
    required String headSha,
    required HostingReviewAction action,
    required String body,
    required List<HostingInlineDraft> inlineComments,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReviewPreview(
      connection: _connection(connection),
      repository: repository,
      pullRequest: BigInt.from(pullRequest),
      headSha: headSha,
      action: action.toNative(),
      body: body,
      inlineComments: inlineComments.map(_inlineToNative).toList(),
    );
    _throwFailure(result.failure);
    final value = result.preview;
    if (value == null) {
      throw const HostingReviewException(HostingReviewFailure.unavailable);
    }
    return _preview(value);
  }

  @override
  Future<HostingReviewSubmitResult> submit({
    required HostingConnection connection,
    required HostingReviewPreview preview,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReviewSubmit(
      connection: _connection(connection),
      preview: _previewToNative(preview),
    );
    return HostingReviewSubmitResult(
      state: result.state.toModel(),
      failure: result.failure?.toModel(),
    );
  }

  @override
  Future<HostingCheckRetryPreview> previewCheckRetry({
    required HostingConnection connection,
    required String repository,
    required String headSha,
    required String checkStableId,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingCheckRetryPreview(
      connection: _connection(connection),
      repository: repository,
      headSha: headSha,
      checkStableId: checkStableId,
    );
    _throwFailure(result.failure);
    final value = result.preview;
    if (value == null) {
      throw const HostingReviewException(HostingReviewFailure.unavailable);
    }
    return HostingCheckRetryPreview(
      authorizationId: value.authorizationId.toInt(),
      target: value.target,
      payload: value.payload,
      connectionId: value.connectionId,
      repository: value.repository,
      headSha: value.headSha,
      checkStableId: value.checkStableId,
    );
  }

  @override
  Future<HostingReviewSubmitResult> retryCheck({
    required HostingConnection connection,
    required HostingCheckRetryPreview preview,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingCheckRetrySubmit(
      connection: _connection(connection),
      authorizationId: BigInt.from(preview.authorizationId),
      repository: preview.repository,
      headSha: preview.headSha,
      checkStableId: preview.checkStableId,
    );
    return HostingReviewSubmitResult(
      state: result.state.toModel(),
      failure: result.failure?.toModel(),
    );
  }

  @override
  Future<HostingReviewDraft?> loadDraft(String key) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReviewDraftLoad(key: key);
    _throwFailure(result.failure);
    return result.draft == null ? null : _draft(result.draft!);
  }

  @override
  Future<HostingReviewDraft> saveDraft(HostingReviewDraft draft) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReviewDraftSave(
      draft: _draftToNative(draft),
    );
    _throwFailure(result.failure);
    final value = result.draft;
    if (!result.saved || value == null) {
      throw const HostingReviewException(HostingReviewFailure.draftStorage);
    }
    return _draft(value);
  }

  @override
  Future<void> deleteDraft(String key) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReviewDraftDelete(key: key);
    _throwFailure(result.failure);
    if (!result.saved) {
      throw const HostingReviewException(HostingReviewFailure.draftStorage);
    }
  }

  @override
  Future<bool> cancel({
    required String connectionId,
    required String repository,
    required int pullRequest,
  }) async {
    await ensureNativeCoreLoaded();
    return api.hostingReviewCancel(
      connectionId: connectionId,
      repository: repository,
      pullRequest: BigInt.from(pullRequest),
    );
  }
}

HostingReviewPage _page(native_review.NativeHostingReviewPage value) =>
    HostingReviewPage(
      connectionId: value.connectionId,
      repository: value.repository,
      pullRequest: value.pullRequest.toInt(),
      headSha: value.headSha,
      diffs: [
        for (final diff in value.diffs)
          HostingReviewDiff(
            stableId: diff.stableId,
            path: diff.path,
            patch: diff.patch,
            anchors: [
              for (final anchor in diff.anchors)
                HostingReviewAnchor(
                  stableId: anchor.stableId,
                  path: anchor.path,
                  line: anchor.line.toInt(),
                ),
            ],
          ),
      ],
      threads: [
        for (final thread in value.threads)
          HostingReviewThread(
            stableId: thread.stableId,
            path: thread.path,
            line: thread.line?.toInt(),
            anchorId: thread.anchorId,
            author: thread.author,
            body: thread.body,
            resolved: thread.resolved,
            outdated: thread.outdated,
          ),
      ],
      checks: [for (final check in value.checks) _check(check)],
      nextPage: value.nextPage,
      incomplete: value.incomplete,
    );

HostingCheck _check(native.NativeHostingCheck check) => HostingCheck(
  stableId: check.stableId,
  name: check.name,
  state: check.state.toModel(),
  conclusion: check.conclusion,
  detailsUrl: check.detailsUrl,
  updatedAt: check.updatedAt,
);

HostingReviewPreview _preview(native_review.NativeHostingReviewPreview value) =>
    HostingReviewPreview(
      authorizationId: value.authorizationId.toInt(),
      target: value.target,
      payload: value.payload,
      connectionId: value.connectionId,
      repository: value.repository,
      pullRequest: value.pullRequest.toInt(),
      headSha: value.headSha,
      action: value.action.toModel(),
      body: value.body,
      inlineComments: value.inlineComments.map(_inline).toList(),
    );

native_review.NativeHostingReviewPreview _previewToNative(
  HostingReviewPreview value,
) => native_review.NativeHostingReviewPreview(
  authorizationId: BigInt.from(value.authorizationId),
  target: value.target,
  payload: value.payload,
  connectionId: value.connectionId,
  repository: value.repository,
  pullRequest: BigInt.from(value.pullRequest),
  headSha: value.headSha,
  action: value.action.toNative(),
  body: value.body,
  inlineComments: value.inlineComments.map(_inlineToNative).toList(),
);

HostingInlineDraft _inline(native_review.NativeHostingInlineDraft value) =>
    HostingInlineDraft(
      stableId: value.stableId,
      path: value.path,
      line: value.line.toInt(),
      body: value.body,
    );

native_review.NativeHostingInlineDraft _inlineToNative(
  HostingInlineDraft value,
) => native_review.NativeHostingInlineDraft(
  stableId: value.stableId,
  path: value.path,
  line: BigInt.from(value.line),
  body: value.body,
);

HostingReviewDraft _draft(native_review.NativeHostingReviewDraft value) =>
    HostingReviewDraft(
      key: value.key,
      connectionId: value.connectionId,
      repository: value.repository,
      pullRequest: value.pullRequest.toInt(),
      headSha: value.headSha,
      action: value.action.toModel(),
      body: value.body,
      inlineComments: value.inlineComments.map(_inline).toList(),
      updatedAt: value.updatedAt.toInt(),
    );

native_review.NativeHostingReviewDraft _draftToNative(
  HostingReviewDraft value,
) => native_review.NativeHostingReviewDraft(
  key: value.key,
  connectionId: value.connectionId,
  repository: value.repository,
  pullRequest: BigInt.from(value.pullRequest),
  headSha: value.headSha,
  action: value.action.toNative(),
  body: value.body,
  inlineComments: value.inlineComments.map(_inlineToNative).toList(),
  updatedAt: BigInt.from(value.updatedAt),
);

native.NativeHostingConnection _connection(HostingConnection value) =>
    native.NativeHostingConnection(
      id: value.id,
      preset: value.preset.toNative(),
      login: value.login,
      webBaseUrl: value.webBaseUrl,
      apiBaseUrl: value.apiBaseUrl,
      oauthClientId: value.oauthClientId,
      authentication: value.authentication.toNative(),
      enabled: value.enabled,
      refreshEnabled: value.refreshEnabled,
      capabilities: value.capabilities.map((item) => item.toNative()).toList(),
      credentialIdentity: value.credentialIdentity,
      allowSplitOrigin: value.allowSplitOrigin,
    );

void _throwFailure(native_review.NativeHostingReviewFailure? failure) {
  if (failure != null) {
    throw HostingReviewException(failure.toModel());
  }
}
