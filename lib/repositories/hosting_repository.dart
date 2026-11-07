import '../models/hosting.dart';

abstract interface class HostingRepository {
  Future<bool> githubCliAvailable();
  Future<bool> gitlabCliAvailable();

  Future<void> openBrowser(Uri url);

  Future<HostingConnection> validateConnection(HostingConnection connection);

  /// The defaults a new connection of [preset] starts with, or null when a
  /// self-hosted preset has no valid `https` [webBase].
  Future<HostingPresetDefaults?> presetDefaults(
    HostingPreset preset, {
    String? webBase,
  });

  Future<HostingBindingResolution> resolveBinding({
    required List<HostingConnection> connections,
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  });

  Future<Uri> resourceLink({
    required HostingConnection connection,
    required String providerRepository,
    required HostingResourceKind kind,
    int? number,
  });

  Future<HostingCredentialState> credentialState(HostingConnection connection);

  Future<HostingCredentialState> removeCredential(HostingConnection connection);

  Future<HostingOAuthSnapshot> startAuthorization(HostingConnection connection);

  Future<HostingOAuthSnapshot?> pollAuthorization(int requestId);

  Future<bool> cancelAuthorization(int requestId);

  Future<HostingResourceSnapshot> startResourceRefresh({
    required HostingConnection connection,
    required String providerRepository,
    required int page,
    required bool manual,
  });

  Future<HostingResourceSnapshot?> pollResourceRefresh(int requestId);

  Future<bool> cancelResourceRefresh(int requestId);

  /// Starts a lookup of the CI result of commits [heads], the open pull
  /// requests for [branches] of [providerRepository] and, with [authoredBy],
  /// those that login opened.
  Future<HostingPullRequestLookupSnapshot> startPullRequestLookup({
    required HostingConnection connection,
    required String providerRepository,
    List<String> heads = const [],
    required List<String> branches,
    String? authoredBy,
  });

  Future<HostingPullRequestLookupSnapshot?> pollPullRequestLookup(
    int requestId,
  );

  Future<bool> cancelPullRequestLookup(int requestId);

  Future<void> deactivateResources({
    required String connectionId,
    required String providerRepository,
  });

  Future<HostingReferenceProjection?> projectReference({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int revision,
    required List<HostingRemoteReference> references,
    required bool stale,
  });

  Future<HostingReferenceApplyResult> applyReference({
    required String text,
    required int currentRevision,
    required HostingReferenceProjection projection,
    required String insertion,
  });

  Future<void> shutdownRuntime();
}
