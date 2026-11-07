import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

import '../../models/hosting.dart';
import '../../rust/api.dart' as api;
import '../../rust/third_party/gitlama_contract/hosting.dart' as native;
import '../../rust/third_party/gitlama_contract/hosting_runtime.dart'
    as native_runtime;
import '../hosting_repository.dart';
import 'native_mappers.dart';
import 'native_enum_mappers.g.dart';

final class NativeHostingRepository implements HostingRepository {
  @override
  Future<bool> githubCliAvailable() async {
    await ensureNativeCoreLoaded();
    return api.hostingGithubCliAvailable();
  }

  @override
  Future<bool> gitlabCliAvailable() async {
    await ensureNativeCoreLoaded();
    return api.hostingGitlabCliAvailable();
  }

  @override
  Future<void> openBrowser(Uri url) async {
    final localHttp =
        url.scheme == 'http' &&
        (url.host == 'localhost' || url.host == '127.0.0.1');
    if ((!localHttp && url.scheme != 'https') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const HostingException(HostingFailureCode.invalidLink);
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw const HostingException(HostingFailureCode.invalidLink);
    }
  }

  @override
  Future<HostingConnection> validateConnection(
    HostingConnection connection,
  ) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingConnectionValidate(
      connection: _toNative(connection),
    );
    _throwFailure(result.failure);
    final normalized = result.connection;
    if (normalized == null) {
      throw const HostingException(HostingFailureCode.invalidConnection);
    }
    return _fromNative(normalized);
  }

  @override
  Future<HostingPresetDefaults?> presetDefaults(
    HostingPreset preset, {
    String? webBase,
  }) async {
    await ensureNativeCoreLoaded();
    final defaults = (await api.hostingPresetDefaults(
      preset: preset.toNative(),
      webBase: webBase,
    )).defaults;
    if (defaults == null) return null;
    return HostingPresetDefaults(
      preset: defaults.preset.toModel(),
      webBaseUrl: defaults.webBaseUrl,
      apiBaseUrl: defaults.apiBaseUrl,
      gitHubTenant: defaults.githubTenant,
      capabilities: [
        for (final capability in defaults.capabilities) capability.toModel(),
      ],
      authentications: [
        for (final method in defaults.authentications) method.toModel(),
      ],
    );
  }

  @override
  Future<HostingBindingResolution> resolveBinding({
    required List<HostingConnection> connections,
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingBindingResolve(
      connections: connections.map(_toNative).toList(growable: false),
      remotes: [
        for (final remote in remotes)
          native.NativeHostingRemote(
            name: Uint8List.fromList(remote.name),
            url: remote.url,
          ),
      ],
      overrideConnectionId: overrideConnectionId,
    );
    if (result.failure != native.NativeHostingFailureKind.ambiguous) {
      _throwFailure(result.failure);
    }
    return HostingBindingResolution(
      state: result.state.toModel(),
      remote: result.remote,
      server: result.server,
      connectionId: result.connectionId,
      providerRepository: result.providerRepository,
      webUrl: result.webUrl,
    );
  }

  @override
  Future<Uri> resourceLink({
    required HostingConnection connection,
    required String providerRepository,
    required HostingResourceKind kind,
    int? number,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingResourceLink(
      connection: _toNative(connection),
      providerRepository: providerRepository,
      kind: kind.toNative(),
      number: number == null ? null : BigInt.from(number),
    );
    _throwFailure(result.failure);
    final value = result.url;
    if (value == null) {
      throw const HostingException(HostingFailureCode.invalidLink);
    }
    return Uri.parse(value);
  }

  @override
  Future<HostingCredentialState> credentialState(
    HostingConnection connection,
  ) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingCredentialState(
      connection: _toNative(connection),
    );
    return result.state.toModel();
  }

  @override
  Future<HostingCredentialState> removeCredential(
    HostingConnection connection,
  ) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingCredentialRemove(
      connection: _toNative(connection),
    );
    _throwFailure(result.failure);
    return result.state.toModel();
  }

  @override
  Future<HostingOAuthSnapshot> startAuthorization(
    HostingConnection connection,
  ) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingOauthStart(
      connection: _toNative(connection),
    );
    final failure = result.failure;
    if (failure != null) throw HostingOAuthException(_oauthFailure(failure));
    final snapshot = result.snapshot;
    if (snapshot == null) {
      throw const HostingOAuthException(HostingOAuthFailure.unavailable);
    }
    return _oauthSnapshot(snapshot);
  }

  @override
  Future<HostingOAuthSnapshot?> pollAuthorization(int requestId) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingOauthPoll(
      requestId: BigInt.from(requestId),
    );
    return result.snapshot == null ? null : _oauthSnapshot(result.snapshot!);
  }

  @override
  Future<bool> cancelAuthorization(int requestId) async {
    await ensureNativeCoreLoaded();
    return api.hostingOauthCancel(requestId: BigInt.from(requestId));
  }

  @override
  Future<HostingResourceSnapshot> startResourceRefresh({
    required HostingConnection connection,
    required String providerRepository,
    required int page,
    required bool manual,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingResourcesStart(
      connection: _toNative(connection),
      repositoryId: providerRepository,
      page: page,
      manual: manual,
    );
    final failure = result.failure;
    if (failure != null) {
      throw HostingResourceException(_resourceFailure(failure));
    }
    final snapshot = result.snapshot;
    if (snapshot == null) {
      throw const HostingResourceException(HostingResourceFailure.unavailable);
    }
    return _resourceSnapshot(snapshot);
  }

  @override
  Future<HostingResourceSnapshot?> pollResourceRefresh(int requestId) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingResourcesPoll(
      requestId: BigInt.from(requestId),
    );
    return result.snapshot == null ? null : _resourceSnapshot(result.snapshot!);
  }

  @override
  Future<bool> cancelResourceRefresh(int requestId) async {
    await ensureNativeCoreLoaded();
    return api.hostingResourcesCancel(requestId: BigInt.from(requestId));
  }

  @override
  Future<HostingPullRequestLookupSnapshot> startPullRequestLookup({
    required HostingConnection connection,
    required String providerRepository,
    List<String> heads = const [],
    required List<String> branches,
    String? authoredBy,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingPullRequestLookupStart(
      connection: _toNative(connection),
      repositoryId: providerRepository,
      heads: heads,
      branches: branches,
      authoredBy: authoredBy,
    );
    final failure = result.failure;
    if (failure != null) {
      throw HostingResourceException(_resourceFailure(failure));
    }
    final snapshot = result.snapshot;
    if (snapshot == null) {
      throw const HostingResourceException(HostingResourceFailure.unavailable);
    }
    return _lookupSnapshot(snapshot);
  }

  @override
  Future<HostingPullRequestLookupSnapshot?> pollPullRequestLookup(
    int requestId,
  ) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingPullRequestLookupPoll(
      requestId: BigInt.from(requestId),
    );
    return result.snapshot == null ? null : _lookupSnapshot(result.snapshot!);
  }

  @override
  Future<bool> cancelPullRequestLookup(int requestId) async {
    await ensureNativeCoreLoaded();
    return api.hostingPullRequestLookupCancel(
      requestId: BigInt.from(requestId),
    );
  }

  @override
  Future<void> deactivateResources({
    required String connectionId,
    required String providerRepository,
  }) async {
    await ensureNativeCoreLoaded();
    await api.hostingResourcesDeactivate(
      connectionId: connectionId,
      repositoryId: providerRepository,
    );
  }

  @override
  Future<HostingReferenceProjection?> projectReference({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int revision,
    required List<HostingRemoteReference> references,
    required bool stale,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReferenceProject(
      text: text.codeUnits,
      selectionBase: selectionBase,
      selectionExtent: selectionExtent,
      revision: BigInt.from(revision),
      references: [
        for (final reference in references)
          native.NativeHostingRemoteReference(
            stableId: reference.stableId,
            kind: reference.kind.toNative(),
            number: BigInt.from(reference.number),
            title: reference.title,
            insertion: reference.insertion,
            webUrl: reference.webUrl,
          ),
      ],
      stale: stale,
    );
    final failure = result.failure;
    if (failure != null) {
      throw HostingReferenceException(failure.toModel());
    }
    final projection = result.projection;
    if (projection == null) return null;
    return HostingReferenceProjection(
      revision: projection.revision.toInt(),
      textHash: projection.textHash.toInt(),
      replaceStart: projection.replaceStart,
      replaceEnd: projection.replaceEnd,
      query: projection.query,
      candidates: [
        for (final candidate in projection.candidates)
          HostingReferenceCandidate(
            stableId: candidate.stableId,
            kind: candidate.kind.toModel(),
            number: candidate.number.toInt(),
            title: candidate.title,
            insertion: candidate.insertion,
            webUrl: candidate.webUrl,
            stale: candidate.stale,
          ),
      ],
    );
  }

  @override
  Future<HostingReferenceApplyResult> applyReference({
    required String text,
    required int currentRevision,
    required HostingReferenceProjection projection,
    required String insertion,
  }) async {
    await ensureNativeCoreLoaded();
    final result = await api.hostingReferenceApply(
      text: text.codeUnits,
      currentRevision: BigInt.from(currentRevision),
      expectedRevision: BigInt.from(projection.revision),
      expectedTextHash: BigInt.from(projection.textHash),
      replaceStart: projection.replaceStart,
      replaceEnd: projection.replaceEnd,
      insertion: insertion,
    );
    return HostingReferenceApplyResult(
      text: String.fromCharCodes(result.text),
      caret: result.caret,
      failure: result.failure?.toModel(),
    );
  }

  @override
  Future<void> shutdownRuntime() async {
    await ensureNativeCoreLoaded();
    await api.hostingRuntimeShutdown();
  }
}

HostingOAuthSnapshot _oauthSnapshot(
  native_runtime.NativeHostingOAuthSnapshot snapshot,
) => HostingOAuthSnapshot(
  requestId: snapshot.requestId.toInt(),
  state: snapshot.state.toModel(),
  browserUrl: snapshot.browserUrl == null
      ? null
      : Uri.parse(snapshot.browserUrl!),
  userCode: snapshot.userCode,
  authenticatedLogin: snapshot.authenticatedLogin,
  failure: snapshot.failure == null ? null : _oauthFailure(snapshot.failure!),
);

HostingOAuthFailure _oauthFailure(
  native_runtime.NativeHostingOAuthFailure failure,
) => failure.toModel();

HostingResourceSnapshot _resourceSnapshot(
  native_runtime.NativeHostingResourceSnapshot snapshot,
) => HostingResourceSnapshot(
  requestId: snapshot.requestId.toInt(),
  state: snapshot.state.toModel(),
  page: snapshot.page,
  resources: _resources(snapshot.resources),
  stale: snapshot.stale,
  hasMore: snapshot.hasMore,
  failure: snapshot.failure == null
      ? null
      : _resourceFailure(snapshot.failure!),
);

HostingPullRequestLookupSnapshot _lookupSnapshot(
  native_runtime.NativeHostingPullRequestLookupSnapshot snapshot,
) => HostingPullRequestLookupSnapshot(
  requestId: snapshot.requestId.toInt(),
  state: snapshot.state.toModel(),
  heads: {for (final head in snapshot.heads) head.head: head.checks.toModel()},
  branches: {
    for (final branch in snapshot.branches)
      branch.branch: List.unmodifiable(
        branch.changeRequests.map(_changeRequest),
      ),
  },
  authored: switch (snapshot.authored) {
    final authored? => List.unmodifiable(authored.map(_changeRequest)),
    null => null,
  },
  failure: snapshot.failure == null
      ? null
      : _resourceFailure(snapshot.failure!),
);

HostingChangeRequest _changeRequest(native.NativeHostingChangeRequest change) =>
    HostingChangeRequest(
      stableId: change.stableId,
      number: change.number.toInt(),
      title: change.title,
      author: change.author,
      state: change.state.toModel(),
      draft: change.draft,
      sourceRepository: change.sourceRepository,
      sourceBranch: change.sourceBranch,
      targetRepository: change.targetRepository,
      targetBranch: change.targetBranch,
      headSha: change.headSha,
      webUrl: change.webUrl,
      reviewSummary: change.reviewSummary.toModel(),
      mergeability: change.mergeability.toModel(),
      checks: HostingCheckSummary(
        state: change.checks.state.toModel(),
        checks: [
          for (final check in change.checks.checks)
            HostingCheck(
              stableId: check.stableId,
              name: check.name,
              state: check.state.toModel(),
              conclusion: check.conclusion,
              detailsUrl: check.detailsUrl,
              updatedAt: check.updatedAt,
            ),
        ],
      ),
    );

HostingResources _resources(native.NativeHostingResources resources) =>
    HostingResources(
      changeRequests: [
        for (final change in resources.changeRequests) _changeRequest(change),
      ],
      issues: [
        for (final issue in resources.issues)
          HostingIssue(
            stableId: issue.stableId,
            number: issue.number.toInt(),
            title: issue.title,
            state: issue.state.toModel(),
            author: issue.author,
            assignees: List.unmodifiable(issue.assignees),
            labels: List.unmodifiable(issue.labels),
            private: issue.private,
            updatedAt: issue.updatedAt,
            webUrl: issue.webUrl,
          ),
      ],
      remoteReferences: [
        for (final reference in resources.remoteReferences)
          HostingRemoteReference(
            stableId: reference.stableId,
            kind: reference.kind.toModel(),
            number: reference.number.toInt(),
            title: reference.title,
            insertion: reference.insertion,
            webUrl: reference.webUrl,
          ),
      ],
    );

HostingResourceFailure _resourceFailure(
  native_runtime.NativeHostingResourceFailure failure,
) => failure.toModel();

native.NativeHostingConnection _toNative(HostingConnection connection) =>
    native.NativeHostingConnection(
      id: connection.id,
      preset: connection.preset.toNative(),
      login: connection.login,
      webBaseUrl: connection.webBaseUrl,
      apiBaseUrl: connection.apiBaseUrl,
      oauthClientId: connection.oauthClientId,
      authentication: connection.authentication.toNative(),
      enabled: connection.enabled,
      refreshEnabled: connection.refreshEnabled,
      capabilities: [
        for (final capability in connection.capabilities) capability.toNative(),
      ],
      credentialIdentity: connection.credentialIdentity,
      allowSplitOrigin: connection.allowSplitOrigin,
    );

HostingConnection _fromNative(native.NativeHostingConnection connection) =>
    HostingConnection(
      id: connection.id,
      preset: connection.preset.toModel(),
      login: connection.login,
      webBaseUrl: connection.webBaseUrl,
      apiBaseUrl: connection.apiBaseUrl,
      oauthClientId: connection.oauthClientId,
      authentication: connection.authentication.toModel(),
      enabled: connection.enabled,
      refreshEnabled: connection.refreshEnabled,
      capabilities: [
        for (final capability in connection.capabilities) capability.toModel(),
      ],
      credentialIdentity: connection.credentialIdentity,
      allowSplitOrigin: connection.allowSplitOrigin,
    );

void _throwFailure(native.NativeHostingFailureKind? failure) {
  if (failure != null) {
    throw HostingException(failure.toModel());
  }
}
