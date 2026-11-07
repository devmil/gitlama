enum HostingPreset {
  gitHub,
  gitLab,
  gitLabSelfManaged,
  forgejo,
  codeberg,
  gitHubEnterprise,
}

enum HostingAuthentication { oauth, gitHubCli, gitLabCli }

/// Names written to the settings document. The native store accepts exactly
/// these; `test/fixtures/settings_storage_names.json` pins both sides.
extension HostingPresetStorage on HostingPreset {
  String get storageName => switch (this) {
    HostingPreset.gitHub => 'github',
    HostingPreset.gitLab => 'gitlab',
    HostingPreset.gitLabSelfManaged => 'gitlabSelfManaged',
    HostingPreset.forgejo => 'forgejo',
    HostingPreset.codeberg => 'codeberg',
    HostingPreset.gitHubEnterprise => 'gitHubEnterprise',
  };
}

extension HostingAuthenticationStorage on HostingAuthentication {
  String get storageName => name;
}

enum HostingCapability {
  changeRequests,
  changeRequestCheckout,
  changeRequestReview,
  commitStatuses,
  checkRuns,
  issues,
  remoteReferences,
}

/// The defaults a new connection of one preset starts with. The native preset
/// rules derive them; a self-hosted preset needs its `https` web origin.
final class HostingPresetDefaults {
  const HostingPresetDefaults({
    required this.preset,
    required this.webBaseUrl,
    required this.apiBaseUrl,
    required this.gitHubTenant,
    required this.capabilities,
    required this.authentications,
  });

  final HostingPreset preset;

  /// The normalized web origin.
  final String webBaseUrl;
  final String apiBaseUrl;

  /// A GitHub Enterprise Cloud tenant whose API lives on a sibling host.
  final bool gitHubTenant;
  final List<HostingCapability> capabilities;

  /// Allowed authentication methods; the first is the default.
  final List<HostingAuthentication> authentications;
}

final class HostingConnection {
  const HostingConnection({
    required this.id,
    required this.preset,
    required this.login,
    required this.webBaseUrl,
    required this.apiBaseUrl,
    required this.oauthClientId,
    this.authentication = HostingAuthentication.oauth,
    required this.enabled,
    this.refreshEnabled = true,
    required this.capabilities,
    required this.credentialIdentity,
    this.allowSplitOrigin = false,
  });

  final String id;
  final HostingPreset preset;
  final String login;
  final String webBaseUrl;
  final String apiBaseUrl;
  final String oauthClientId;
  final HostingAuthentication authentication;
  final bool enabled;
  final bool refreshEnabled;
  final List<HostingCapability> capabilities;
  final String credentialIdentity;
  final bool allowSplitOrigin;

  HostingConnection copyWith({
    String? login,
    bool? enabled,
    bool? refreshEnabled,
  }) => HostingConnection(
    id: id,
    preset: preset,
    login: login ?? this.login,
    webBaseUrl: webBaseUrl,
    apiBaseUrl: apiBaseUrl,
    oauthClientId: oauthClientId,
    authentication: authentication,
    enabled: enabled ?? this.enabled,
    refreshEnabled: refreshEnabled ?? this.refreshEnabled,
    capabilities: capabilities,
    credentialIdentity: credentialIdentity,
    allowSplitOrigin: allowSplitOrigin,
  );
}

final class HostingRemote {
  const HostingRemote({required this.name, required this.url});

  final List<int> name;
  final String url;
}

enum HostingBindingState { unmatched, ambiguous, bound }

final class HostingBindingResolution {
  const HostingBindingResolution({
    required this.state,
    this.remote = const [],
    this.server = '',
    this.connectionId,
    this.providerRepository,
    this.webUrl,
  });

  final HostingBindingState state;
  final List<int> remote;
  final String server;
  final String? connectionId;
  final String? providerRepository;
  final String? webUrl;
}

enum HostingCredentialState { missing, available, expired, unreadable }

enum HostingOAuthState {
  queued,
  waitingForBrowser,
  waitingForDevice,
  exchanging,
  succeeded,
  failed,
  canceled,
}

enum HostingOAuthFailure {
  invalidConnection,
  busy,
  unavailable,
  unauthorized,
  rateLimited,
  malformedResponse,
  expired,
  denied,
  secureStore,
  notFound,
  redirected,
  serverError,
  network,
  certificate,
  timedOut,
}

final class HostingOAuthSnapshot {
  const HostingOAuthSnapshot({
    required this.requestId,
    required this.state,
    this.browserUrl,
    this.userCode,
    this.authenticatedLogin,
    this.failure,
  });

  final int requestId;
  final HostingOAuthState state;
  final Uri? browserUrl;
  final String? userCode;
  final String? authenticatedLogin;
  final HostingOAuthFailure? failure;

  bool get isTerminal => switch (state) {
    HostingOAuthState.succeeded ||
    HostingOAuthState.failed ||
    HostingOAuthState.canceled => true,
    _ => false,
  };
}

enum HostingResourceKind {
  repository,
  changeRequest,
  createChangeRequest,
  issue,
}

enum HostingChangeRequestState { open, closed, merged }

enum HostingReviewSummary { none, pending, approved, changesRequested, unknown }

enum HostingMergeability { mergeable, conflicting, checking, unknown }

enum HostingCheckState { pending, passing, failing, canceled, skipped, unknown }

final class HostingCheck {
  const HostingCheck({
    required this.stableId,
    required this.name,
    required this.state,
    required this.conclusion,
    this.detailsUrl,
    this.updatedAt,
  });

  final String stableId;
  final String name;
  final HostingCheckState state;
  final String conclusion;
  final String? detailsUrl;
  final String? updatedAt;
}

final class HostingCheckSummary {
  const HostingCheckSummary({required this.state, this.checks = const []});

  final HostingCheckState state;
  final List<HostingCheck> checks;
}

final class HostingChangeRequest {
  const HostingChangeRequest({
    required this.stableId,
    required this.number,
    required this.title,
    required this.author,
    required this.state,
    required this.draft,
    required this.sourceRepository,
    required this.sourceBranch,
    required this.targetRepository,
    required this.targetBranch,
    required this.headSha,
    required this.webUrl,
    required this.reviewSummary,
    required this.mergeability,
    required this.checks,
  });

  final String stableId;
  final int number;
  final String title;
  final String author;
  final HostingChangeRequestState state;
  final bool draft;
  final String sourceRepository;
  final String sourceBranch;
  final String targetRepository;
  final String targetBranch;
  final String headSha;
  final String webUrl;
  final HostingReviewSummary reviewSummary;
  final HostingMergeability mergeability;
  final HostingCheckSummary checks;
}

enum HostingIssueState { open, closed }

final class HostingIssue {
  const HostingIssue({
    required this.stableId,
    required this.number,
    required this.title,
    required this.state,
    required this.author,
    required this.assignees,
    required this.labels,
    required this.private,
    required this.updatedAt,
    required this.webUrl,
  });

  final String stableId;
  final int number;
  final String title;
  final HostingIssueState state;
  final String author;
  final List<String> assignees;
  final List<String> labels;
  final bool private;
  final String updatedAt;
  final String webUrl;
}

enum HostingRemoteReferenceKind { issue, changeRequest }

final class HostingRemoteReference {
  const HostingRemoteReference({
    required this.stableId,
    required this.kind,
    required this.number,
    required this.title,
    required this.insertion,
    required this.webUrl,
  });

  final String stableId;
  final HostingRemoteReferenceKind kind;
  final int number;
  final String title;
  final String insertion;
  final String webUrl;
}

enum HostingReferenceFailure {
  invalidRequest,
  staleRevision,
  changedText,
  staleRange,
}

final class HostingReferenceCandidate {
  const HostingReferenceCandidate({
    required this.stableId,
    required this.kind,
    required this.number,
    required this.title,
    required this.insertion,
    required this.webUrl,
    required this.stale,
  });

  final String stableId;
  final HostingRemoteReferenceKind kind;
  final int number;
  final String title;
  final String insertion;
  final String webUrl;
  final bool stale;
}

final class HostingReferenceProjection {
  const HostingReferenceProjection({
    required this.revision,
    required this.textHash,
    required this.replaceStart,
    required this.replaceEnd,
    required this.query,
    required this.candidates,
  });

  final int revision;
  final int textHash;
  final int replaceStart;
  final int replaceEnd;
  final String query;
  final List<HostingReferenceCandidate> candidates;
}

final class HostingReferenceApplyResult {
  const HostingReferenceApplyResult({
    required this.text,
    required this.caret,
    this.failure,
  });

  final String text;
  final int caret;
  final HostingReferenceFailure? failure;
}

enum HostingReviewAction { comment, approve, requestChanges }

enum HostingReviewFailure {
  invalidRequest,
  integrationDisabled,
  credentialMissing,
  credentialUnreadable,
  credentialExpired,
  unauthorized,
  permissionDenied,
  rateLimited,
  malformedResponse,
  unavailable,
  canceled,
  unsupported,
  movedBase,
  staleAuthorization,
  uncertain,
  draftStorage,
}

final class HostingInlineDraft {
  const HostingInlineDraft({
    required this.stableId,
    required this.path,
    required this.line,
    required this.body,
  });

  final String stableId;
  final String path;
  final int line;
  final String body;
}

final class HostingReviewAnchor {
  const HostingReviewAnchor({
    required this.stableId,
    required this.path,
    required this.line,
  });

  final String stableId;
  final String path;
  final int line;
}

final class HostingReviewDiff {
  const HostingReviewDiff({
    required this.stableId,
    required this.path,
    required this.patch,
    required this.anchors,
  });

  final String stableId;
  final String path;
  final String patch;
  final List<HostingReviewAnchor> anchors;
}

final class HostingReviewThread {
  const HostingReviewThread({
    required this.stableId,
    required this.path,
    required this.line,
    required this.anchorId,
    required this.author,
    required this.body,
    required this.resolved,
    required this.outdated,
  });

  final String stableId;
  final String? path;
  final int? line;
  final String? anchorId;
  final String author;
  final String body;
  final bool resolved;
  final bool outdated;
}

final class HostingReviewPage {
  const HostingReviewPage({
    required this.connectionId,
    required this.repository,
    required this.pullRequest,
    required this.headSha,
    required this.diffs,
    required this.threads,
    required this.checks,
    required this.nextPage,
    required this.incomplete,
  });

  final String connectionId;
  final String repository;
  final int pullRequest;
  final String headSha;
  final List<HostingReviewDiff> diffs;
  final List<HostingReviewThread> threads;
  final List<HostingCheck> checks;
  final String? nextPage;
  final bool incomplete;
}

final class HostingReviewPreview {
  const HostingReviewPreview({
    required this.authorizationId,
    required this.target,
    required this.payload,
    required this.connectionId,
    required this.repository,
    required this.pullRequest,
    required this.headSha,
    required this.action,
    required this.body,
    required this.inlineComments,
  });

  final int authorizationId;
  final String target;
  final String payload;
  final String connectionId;
  final String repository;
  final int pullRequest;
  final String headSha;
  final HostingReviewAction action;
  final String body;
  final List<HostingInlineDraft> inlineComments;
}

enum HostingReviewSubmitState { submitted, reconciled, failed, uncertain }

final class HostingReviewSubmitResult {
  const HostingReviewSubmitResult({required this.state, this.failure});

  final HostingReviewSubmitState state;
  final HostingReviewFailure? failure;
}

final class HostingCheckRetryPreview {
  const HostingCheckRetryPreview({
    required this.authorizationId,
    required this.target,
    required this.payload,
    required this.connectionId,
    required this.repository,
    required this.headSha,
    required this.checkStableId,
  });

  final int authorizationId;
  final String target;
  final String payload;
  final String connectionId;
  final String repository;
  final String headSha;
  final String checkStableId;
}

final class HostingReviewDraft {
  const HostingReviewDraft({
    required this.key,
    required this.connectionId,
    required this.repository,
    required this.pullRequest,
    required this.headSha,
    required this.action,
    required this.body,
    required this.inlineComments,
    required this.updatedAt,
  });

  final String key;
  final String connectionId;
  final String repository;
  final int pullRequest;
  final String headSha;
  final HostingReviewAction action;
  final String body;
  final List<HostingInlineDraft> inlineComments;
  final int updatedAt;
}

final class HostingResources {
  const HostingResources({
    this.changeRequests = const [],
    this.issues = const [],
    this.remoteReferences = const [],
  });

  final List<HostingChangeRequest> changeRequests;
  final List<HostingIssue> issues;
  final List<HostingRemoteReference> remoteReferences;
}

Map<String, HostingCheckState> hostingBranchDecorations(
  HostingBindingResolution? binding,
  HostingResources resources,
) {
  final repository = binding?.providerRepository;
  final decorations = <String, HostingCheckState>{};
  if (repository == null) return decorations;
  for (final pull in resources.changeRequests) {
    if (pull.sourceRepository != repository) continue;
    decorations.update(
      pull.sourceBranch,
      (current) => _worseCheckState(current, pull.checks.state),
      ifAbsent: () => pull.checks.state,
    );
  }
  return Map.unmodifiable(decorations);
}

HostingCheckState _worseCheckState(
  HostingCheckState left,
  HostingCheckState right,
) {
  const priority = <HostingCheckState, int>{
    HostingCheckState.failing: 6,
    HostingCheckState.canceled: 5,
    HostingCheckState.pending: 4,
    HostingCheckState.unknown: 3,
    HostingCheckState.skipped: 2,
    HostingCheckState.passing: 1,
  };
  return priority[left]! >= priority[right]! ? left : right;
}

enum HostingResourceLoadState { inactive, loading, ready, failed, canceled }

enum HostingResourceFailure {
  invalidRequest,
  integrationDisabled,
  credentialMissing,
  credentialUnreadable,
  credentialExpired,
  unauthorized,
  permissionDenied,
  rateLimited,
  malformedResponse,
  unavailable,
  notFound,
  redirected,
  serverError,
  network,
  certificate,
  timedOut,
}

final class HostingResourceSnapshot {
  const HostingResourceSnapshot({
    required this.requestId,
    required this.state,
    required this.page,
    required this.resources,
    required this.stale,
    required this.hasMore,
    this.failure,
  });

  final int requestId;
  final HostingResourceLoadState state;
  final int page;
  final HostingResources resources;
  final bool stale;
  final bool hasMore;
  final HostingResourceFailure? failure;

  bool get isTerminal => switch (state) {
    HostingResourceLoadState.ready ||
    HostingResourceLoadState.failed ||
    HostingResourceLoadState.canceled => true,
    _ => false,
  };
}

/// Progress of one on-demand pull-request lookup. [heads] holds the CI result
/// of every requested commit resolved so far; [branches] holds every
/// branch resolved so far, mapped to its open pull requests (an empty list
/// means the branch has none); [authored] stays null until the authored query,
/// when requested, resolves.
final class HostingPullRequestLookupSnapshot {
  const HostingPullRequestLookupSnapshot({
    required this.requestId,
    required this.state,
    this.heads = const {},
    this.branches = const {},
    this.authored,
    this.failure,
  });

  final int requestId;
  final HostingResourceLoadState state;
  final Map<String, HostingCheckState> heads;
  final Map<String, List<HostingChangeRequest>> branches;
  final List<HostingChangeRequest>? authored;
  final HostingResourceFailure? failure;

  bool get isTerminal => switch (state) {
    HostingResourceLoadState.ready ||
    HostingResourceLoadState.failed ||
    HostingResourceLoadState.canceled => true,
    _ => false,
  };
}

/// A pull request linked to the active repository: one the account authored,
/// or one whose source branch the repository shows.
final class HostingLinkedPullRequest {
  const HostingLinkedPullRequest({
    required this.pull,
    required this.authored,
    this.viaBranch = false,
  });

  final HostingChangeRequest pull;

  /// Whether the bound account opened it.
  final bool authored;

  /// Whether it is linked only through its source branch, not as one of the
  /// account's open pull requests.
  final bool viaBranch;
}

enum HostingFailureCode {
  invalidConnection,
  invalidRemote,
  invalidLink,
  ambiguous,
  credentialMissing,
  credentialUnreadable,
  credentialExpired,
  credentialStore,
}

final class HostingException implements Exception {
  const HostingException(this.code);

  final HostingFailureCode code;
}

final class HostingOAuthException implements Exception {
  const HostingOAuthException(this.failure);

  final HostingOAuthFailure failure;
}

final class HostingResourceException implements Exception {
  const HostingResourceException(this.failure);

  final HostingResourceFailure failure;
}

final class HostingReferenceException implements Exception {
  const HostingReferenceException(this.failure);

  final HostingReferenceFailure failure;
}

final class HostingReviewException implements Exception {
  const HostingReviewException(this.failure);

  final HostingReviewFailure failure;
}
