import 'dart:async';
import 'dart:typed_data';

import 'package:gitlama/app/app_runtime.dart';
import 'package:gitlama/models/app_update.dart';
import 'package:gitlama/models/hosting.dart';
import 'package:gitlama/repositories/app_updater_repository.dart';
import 'package:gitlama/repositories/avatar_repository.dart';
import 'package:gitlama/repositories/hosting_repository.dart';
import 'package:gitlama/repositories/hosting_review_repository.dart';
import 'package:gitlama/repositories/installed_release_repository.dart';
import 'package:gitlama/repositories/release_index_repository.dart';
import 'package:gitlama/services/app_update_service.dart';
import 'package:gitlama/services/avatar_service.dart';
import 'package:gitlama/services/cli_forwarding_service.dart';
import 'package:gitlama/services/hosting_connection_service.dart';
import 'package:gitlama/services/hosting_review_service.dart';
import 'package:gitlama/services/inspection_window_service.dart';
import 'package:gitlama/services/inspector_reveal_service.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/services/recovery_service.dart';
import 'package:gitlama/services/remote_workspace_service.dart';
import 'package:gitlama/services/repository_appearance_service.dart';
import 'package:gitlama/services/repository_drop_service.dart';
import 'package:gitlama/services/repository_session_service.dart';
import 'package:gitlama/services/settings_service.dart';

import 'fake_remote_workspace.dart';
import 'fake_repository_icon_repository.dart';

/// A runtime for a widget test: the services the test provides, and inert
/// real services for every other field, as production always has them. The
/// inert services hold no connections, hosting accounts, avatars or update
/// channels; nothing they do reaches a network, a window or a disk.
AppRuntime testRuntime({
  required RepositorySessionService repositorySessions,
  required SettingsService settings,
  required RecoveryService recovery,
  required OperationCenterService operationCenter,
  required Future<void> Function() shutdown,
  RemoteWorkspaceService? remoteWorkspaces,
  InspectionWindowService inspectionWindows =
      const InspectionWindowService.unavailable(),
  InspectorRevealService? inspectorReveal,
  AvatarService? avatars,
  RepositoryAppearanceService? repositoryAppearances,
  RepositoryDropController repositoryDrops = const DisabledRepositoryDrops(),
  HostingConnectionService? hosting,
  HostingReviewService? hostingReview,
  CliForwardingController cliForwarding =
      const DisabledCliForwardingController(),
  AppUpdateService? updates,
}) {
  final connections =
      hosting ?? HostingConnectionService(InertHostingRepository(), settings);
  // As the composition root does; with no accounts it settles at once.
  if (hosting == null) unawaited(connections.initialize());
  return AppRuntime(
    repositorySessions: repositorySessions,
    remoteWorkspaces: remoteWorkspaces ?? FakeRemoteWorkspace(settings).service,
    inspectionWindows: inspectionWindows,
    inspectorReveal: inspectorReveal ?? InspectorRevealService.unavailable(),
    settings: settings,
    avatars:
        avatars ??
        AvatarService(const _NoAvatars(), settings, canEnable: false),
    repositoryAppearances:
        repositoryAppearances ??
        RepositoryAppearanceService(FakeRepositoryIconRepository(), settings),
    recovery: recovery,
    operationCenter: operationCenter,
    repositoryDrops: repositoryDrops,
    hosting: connections,
    hostingReview:
        hostingReview ?? HostingReviewService(const _NoReviews(), connections),
    cliForwarding: cliForwarding,
    updates:
        updates ??
        AppUpdateService(
          const _UnknownRelease(),
          const _NoUpdater(),
          const _NoReleaseIndex(),
          settings,
        ),
    shutdown: shutdown,
  );
}

/// A hosting backend with no accounts: nothing is bound, nothing is found.
final class InertHostingRepository implements HostingRepository {
  @override
  Future<bool> githubCliAvailable() async => false;

  @override
  Future<bool> gitlabCliAvailable() async => false;

  @override
  Future<void> openBrowser(Uri url) async {}

  @override
  Future<HostingBindingResolution> resolveBinding({
    required List<HostingConnection> connections,
    required List<HostingRemote> remotes,
    String? overrideConnectionId,
  }) async =>
      const HostingBindingResolution(state: HostingBindingState.unmatched);

  @override
  Future<void> deactivateResources({
    required String connectionId,
    required String providerRepository,
  }) async {}

  @override
  Future<void> shutdownRuntime() async {}

  @override
  Future<HostingReferenceProjection?> projectReference({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    required int revision,
    required List<HostingRemoteReference> references,
    required bool stale,
  }) async => null;

  @override
  Future<bool> cancelAuthorization(int requestId) async => false;

  @override
  Future<bool> cancelResourceRefresh(int requestId) async => false;

  @override
  Future<bool> cancelPullRequestLookup(int requestId) async => false;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('inert_hosting_repository');
}

final class _NoReviews implements HostingReviewRepository {
  const _NoReviews();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('inert_hosting_review_repository');
}

final class _NoAvatars implements AvatarRepository {
  const _NoAvatars();

  @override
  Future<Uint8List?> load(String hash, {required bool enabled}) async => null;

  @override
  Future<void> clearCache() async {}
}

final class _UnknownRelease implements InstalledReleaseRepository {
  const _UnknownRelease();

  @override
  Future<InstalledRelease> load() =>
      Future.error(const AppUpdateException(AppUpdateFailureCode.unavailable));
}

final class _NoUpdater implements AppUpdaterRepository {
  const _NoUpdater();

  @override
  bool get isAvailable => false;

  @override
  Future<void> configure({
    required ReleaseChannel channel,
    required Duration checkInterval,
  }) async {}

  @override
  Future<void> checkForUpdates() async {}
}

final class _NoReleaseIndex implements ReleaseIndexRepository {
  const _NoReleaseIndex();

  @override
  bool get isAvailable => false;

  @override
  Future<List<PublishedRelease>> load() async => const [];

  @override
  Future<void> openDownloads() async {}

  @override
  Future<void> openIssues() async {}
}
