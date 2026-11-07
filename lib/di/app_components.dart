import 'package:flutter/scheduler.dart';

import '../app/app_runtime.dart';
import '../models/cli_forwarding.dart';
import 'component_registry.dart';
import '../repositories/app_updater_repository.dart';
import '../repositories/application_open_repository.dart';
import '../repositories/impl/native_application_open_repository.dart';
import '../repositories/core_repository.dart';
import '../repositories/avatar_repository.dart';
import '../repositories/impl/native_app_updater_repository.dart';
import '../repositories/impl/native_avatar_repository.dart';
import '../repositories/impl/native_source_syntax_repository.dart';
import '../repositories/source_syntax_repository.dart';
import '../repositories/impl/native_installed_release_repository.dart';
import '../repositories/impl/native_release_index_repository.dart';
import '../repositories/installed_release_repository.dart';
import '../repositories/release_index_repository.dart';
import '../repositories/cli_forwarding_repository.dart';
import '../repositories/clone_repository.dart';
import '../repositories/directory_picker_repository.dart';
import '../repositories/impl/native_core_repository.dart';
import '../repositories/impl/native_inspection_window_repository.dart';
import '../repositories/impl/native_inspector_reveal_repository.dart';
import '../repositories/inspector_reveal_repository.dart';
import '../repositories/inspection_window_repository.dart';
import '../repositories/impl/native_clone_repository.dart';
import '../repositories/impl/native_cli_forwarding_repository.dart';
import '../repositories/impl/native_directory_picker_repository.dart';
import '../repositories/impl/native_operation_center_repository.dart';
import '../repositories/impl/native_repository_drop_repository.dart';
import '../repositories/impl/coded_cache_repositories.dart';
import '../repositories/impl/native_entry_store_repository.dart';
import '../repositories/impl/native_hosting_repository.dart';
import '../repositories/impl/native_hosting_review_repository.dart';
import '../repositories/impl/native_remote_connection_repository.dart';
import '../repositories/impl/native_remote_pending_repository.dart';
import '../repositories/impl/native_repository_session_repository.dart';
import '../repositories/impl/remote/remote_session_directory.dart';
import '../repositories/impl/remote/remote_session_factory.dart';
import '../repositories/impl/repository_backend_router.dart';
import '../repositories/remote_connection_repository.dart';
import '../repositories/remote_session_repository.dart';
import '../repositories/impl/native_recovery_repository.dart';
import '../repositories/impl/native_repository_icon_repository.dart';
import '../repositories/repository_session_repository.dart';
import '../repositories/repository_view_cache_repository.dart';
import '../repositories/operation_center_repository.dart';
import '../repositories/repository_drop_repository.dart';
import '../repositories/hosting_link_cache_repository.dart';
import '../repositories/hosting_repository.dart';
import '../repositories/hosting_review_repository.dart';
import '../repositories/recovery_repository.dart';
import '../repositories/remote_inspection_host_repository.dart';
import '../repositories/impl/remote/remote_inspection_channel.dart';
import '../repositories/repository_icon_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/impl/native_settings_repository.dart';
import '../repositories/impl/native_window_geometry_repository.dart';
import '../repositories/window_geometry_repository.dart';
import '../repositories/working_tree_path_repository.dart';
import '../repositories/impl/native_working_tree_path_repository.dart';
import '../services/app_update_service.dart';
import '../services/clone_service.dart';
import '../services/core_service.dart';
import '../services/diff_syntax_service.dart';
import '../services/source_syntax_service.dart';
import '../services/avatar_service.dart';
import '../services/inspection_window_service.dart';
import '../services/inspector_reveal_service.dart';
import '../services/cli_forwarding_service.dart';
import '../services/operation_center_service.dart';
import '../services/repository_drop_service.dart';
import '../services/hosting_connection_service.dart';
import '../services/hosting_review_service.dart';
import '../services/remote_inspection_host_service.dart';
import '../services/remote_workspace_service.dart';
import '../services/repository_session_service.dart';
import '../services/session/session_view_cache.dart';
import '../services/repository_view_cache_service.dart';
import '../services/recovery_service.dart';
import '../services/repository_appearance_service.dart';
import '../services/settings_service.dart';
import '../services/window_geometry_service.dart';
import '../services/working_tree_paths.dart';

Future<CliStartupResult> prepareProcessInvocation() =>
    NativeCliForwardingRepository().prepareProcessInvocation();

/// Production composition root.
///
/// Add repositories before their owning services. Give every resource an
/// initializer and disposer here rather than scattering lifecycle work.
final class AppComponents {
  AppComponents({
    CoreRepository Function()? coreRepositoryFactory,
    CliForwardingRepository Function()? cliForwardingRepositoryFactory,
    SettingsRepository Function()? settingsRepositoryFactory,
    RecoveryRepository Function()? recoveryRepositoryFactory,
    WindowGeometryRepository Function()? windowGeometryRepositoryFactory,
    OperationCenterRepository Function()? operationCenterRepositoryFactory,
    RepositoryDropRepository Function()? repositoryDropRepositoryFactory,
    RepositoryViewCacheRepository Function()?
    repositoryViewCacheRepositoryFactory,
    RemoteConnectionRepository Function()? remoteConnectionRepositoryFactory,
    RemotePendingRepository Function()? remotePendingRepositoryFactory,
    HostingLinkCacheRepository Function()? hostingLinkCacheRepositoryFactory,
    InstalledReleaseRepository Function()? installedReleaseRepositoryFactory,
    AppUpdaterRepository Function()? appUpdaterRepositoryFactory,
    ReleaseIndexRepository Function()? releaseIndexRepositoryFactory,
    RemoteInspectionHostRepository Function()?
    remoteInspectionHostRepositoryFactory,
  }) : _registry = ComponentRegistry() {
    _registry.register<CoreRepository>(
      (_) => (coreRepositoryFactory ?? NativeCoreRepository.new)(),
    );
    _registry.register<ApplicationOpenRepository>(
      (_) => NativeApplicationOpenRepository(),
    );
    _registry.register<AvatarRepository>((_) => NativeAvatarRepository());
    _registry.register<SourceSyntaxRepository>(
      (_) => const NativeSourceSyntaxRepository(),
    );
    _registry.register<CliForwardingRepository>(
      (_) =>
          (cliForwardingRepositoryFactory ??
          NativeCliForwardingRepository.new)(),
    );
    _registry.register<DirectoryPickerRepository>(
      (_) => NativeDirectoryPickerRepository(),
    );
    _registry.register<NativeRepositorySessionRepository>(
      (_) => NativeRepositorySessionRepository(),
    );
    _registry.register<RemoteSessionDirectory>((_) => LiveRemoteSessions());
    _registry.register<WorkingTreePathRepository>(
      (_) => const NativeWorkingTreePathRepository(),
    );
    // Local sessions reach the native library, remote ones their
    // connection; every session family goes through this one router.
    _registry.register<CompleteSessionBackend>(
      (resolver) => RepositoryBackendRouter(
        resolver.resolve<NativeRepositorySessionRepository>(),
        resolver.resolve<RemoteSessionDirectory>(),
      ),
    );
    _registry.register<RemoteConnectionRepository>(
      (_) =>
          (remoteConnectionRepositoryFactory ??
          NativeRemoteConnectionRepository.new)(),
    );
    _registry.register<RemotePendingRepository>(
      (_) =>
          (remotePendingRepositoryFactory ??
          NativeRemotePendingRepository.new)(),
    );
    _registry.register<RemoteSessionFactory>(
      (_) => const WireRemoteSessionFactory(),
    );
    _registry.register<RepositoryViewCacheRepository>(
      (_) =>
          (repositoryViewCacheRepositoryFactory ??
          () => CodedRepositoryViewCacheRepository(NativeEntryStore()))(),
    );
    _registry.register<HostingLinkCacheRepository>(
      (_) =>
          (hostingLinkCacheRepositoryFactory ??
          () => CodedHostingLinkCacheRepository(
            NativeEntryStore(folder: 'hosting-links'),
          ))(),
    );
    _registry.register<InspectionWindowRepository>(
      (_) => NativeInspectionWindowRepository(),
    );
    _registry.register<InspectionWindowService>(
      (resolver) => InspectionWindowService(
        resolver.resolve<InspectionWindowRepository>(),
      ),
    );
    _registry.register<InspectorRevealRepository>(
      (_) => NativeInspectorRevealRepository(),
    );
    _registry.register<RemoteInspectionHostRepository>(
      (_) =>
          (remoteInspectionHostRepositoryFactory ??
          NativeRemoteInspectionHostRepository.new)(),
    );
    _registry.register<InspectorRevealService>(
      (resolver) =>
          InspectorRevealService(resolver.resolve<InspectorRevealRepository>()),
      dispose: (service) => service.dispose(),
    );
    _registry.register<OperationCenterRepository>(
      (_) =>
          (operationCenterRepositoryFactory ??
          NativeOperationCenterRepository.new)(),
    );
    _registry.register<RepositoryDropRepository>(
      (_) =>
          (repositoryDropRepositoryFactory ??
          NativeRepositoryDropRepository.new)(),
    );
    _registry.register<HostingRepository>((_) => NativeHostingRepository());
    _registry.register<HostingReviewRepository>(
      (_) => NativeHostingReviewRepository(),
    );
    _registry.register<CloneRepository>((_) => NativeCloneRepository());
    _registry.register<RepositoryIconRepository>(
      (_) => NativeRepositoryIconRepository(),
    );
    _registry.register<SettingsRepository>(
      (_) => (settingsRepositoryFactory ?? NativeSettingsRepository.new)(),
    );
    _registry.register<RecoveryRepository>(
      (_) => (recoveryRepositoryFactory ?? NativeRecoveryRepository.new)(),
    );
    _registry.register<WindowGeometryRepository>(
      (_) =>
          (windowGeometryRepositoryFactory ??
          NativeWindowGeometryRepository.new)(),
    );
    _registry.register<InstalledReleaseRepository>(
      (_) =>
          (installedReleaseRepositoryFactory ??
          NativeInstalledReleaseRepository.new)(),
    );
    _registry.register<AppUpdaterRepository>(
      (_) => (appUpdaterRepositoryFactory ?? NativeAppUpdaterRepository.new)(),
    );
    _registry.register<ReleaseIndexRepository>(
      (_) =>
          (releaseIndexRepositoryFactory ?? NativeReleaseIndexRepository.new)(),
    );
    _registry.register<CoreService>(
      (resolver) => CoreService(resolver.resolve<CoreRepository>()),
      initialize: (service) => service.initialize(),
    );
    _registry.register<SettingsService>(
      (resolver) => SettingsService(resolver.resolve<SettingsRepository>()),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<AvatarService>(
      (resolver) => AvatarService(
        resolver.resolve<AvatarRepository>(),
        resolver.resolve<SettingsService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<RepositoryAppearanceService>(
      (resolver) => RepositoryAppearanceService(
        resolver.resolve<RepositoryIconRepository>(),
        resolver.resolve<SettingsService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<WindowGeometryService>(
      (resolver) => WindowGeometryService(
        resolver.resolve<WindowGeometryRepository>(),
        resolver.resolve<SettingsService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<CloneService>(
      (resolver) => CloneService(resolver.resolve<CloneRepository>()),
      dispose: (service) => service.dispose(),
    );
    _registry.register<RepositoryViewCacheService>(
      (resolver) => RepositoryViewCacheService(
        resolver.resolve<RepositoryViewCacheRepository>(),
      ),
      dispose: (service) => service.dispose(),
    );
    _registry.register<RemoteWorkspaceService>(
      (resolver) => RemoteWorkspaceService(
        resolver.resolve<RemoteConnectionRepository>(),
        resolver.resolve<RemoteSessionFactory>(),
        resolver.resolve<RemotePendingRepository>(),
        resolver.resolve<SettingsService>(),
        directory: resolver.resolve<RemoteSessionDirectory>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    // Inspector windows of remote repositories read through this window's
    // connections; registered after them, so it closes their sessions first.
    _registry.register<RemoteInspectionHostService>(
      (resolver) {
        final directory = resolver.resolve<RemoteSessionDirectory>();
        return RemoteInspectionHostService(
          resolver.resolve<RemoteInspectionHostRepository>(),
          (authority) => directory.surfaceFor(authority)?.detachedReads,
        );
      },
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    // Syntax colours for every diff of this window, local or on a host.
    _registry.register<DiffSyntaxService>(
      (resolver) => DiffSyntaxService(
        resolver.resolve<CompleteSessionBackend>(),
        nextFrame: () => SchedulerBinding.instance.endOfFrame,
      ),
      dispose: (service) => service.dispose(),
    );
    // Syntax colours for texts this window holds, such as conflicted files,
    // parsed on this computer for local and remote repositories alike.
    _registry.register<SourceSyntaxService>(
      (resolver) => SourceSyntaxService(
        resolver.resolve<SourceSyntaxRepository>(),
        nextFrame: () => SchedulerBinding.instance.endOfFrame,
      ),
      dispose: (service) => service.dispose(),
    );
    _registry.register<RepositorySessionService>(
      (resolver) => RepositorySessionService.composed(
        SessionBackends.complete(resolver.resolve<CompleteSessionBackend>()),
        settings: resolver.resolve<SettingsService>(),
        picker: resolver.resolve<DirectoryPickerRepository>(),
        clones: resolver.resolve<CloneService>(),
        viewCache: ServiceSessionViewCache(
          resolver.resolve<RepositoryViewCacheService>(),
        ),
        remotes: resolver.resolve<RemoteWorkspaceService>(),
        workingTreePaths: WorkingTreePaths(
          resolver.resolve<WorkingTreePathRepository>(),
        ),
        diffSyntax: resolver.resolve<DiffSyntaxService>(),
        sourceSyntax: resolver.resolve<SourceSyntaxService>(),
      ),
      initialize: (service) => service.restoreWorkspace(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<OperationCenterService>(
      (resolver) => OperationCenterService(
        resolver.resolve<OperationCenterRepository>(),
        remote: resolver.resolve<RemoteWorkspaceService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<RepositoryDropService>(
      (resolver) => RepositoryDropService(
        resolver.resolve<RepositoryDropRepository>(),
        resolver.resolve<RepositorySessionService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<RecoveryService>(
      (resolver) => RecoveryService(
        resolver.resolve<RecoveryRepository>(),
        resolver.resolve<SettingsService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<HostingConnectionService>(
      (resolver) => HostingConnectionService(
        resolver.resolve<HostingRepository>(),
        resolver.resolve<SettingsService>(),
        linkCache: resolver.resolve<HostingLinkCacheRepository>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<HostingReviewService>(
      (resolver) => HostingReviewService(
        resolver.resolve<HostingReviewRepository>(),
        resolver.resolve<HostingConnectionService>(),
      ),
    );
    _registry.register<AppUpdateService>(
      (resolver) => AppUpdateService(
        resolver.resolve<InstalledReleaseRepository>(),
        resolver.resolve<AppUpdaterRepository>(),
        resolver.resolve<ReleaseIndexRepository>(),
        resolver.resolve<SettingsService>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<CliForwardingService>(
      (resolver) => CliForwardingService(
        resolver.resolve<CliForwardingRepository>(),
        resolver.resolve<RepositorySessionService>(),
        resolver.resolve<WindowGeometryService>(),
        applicationOpen: resolver.resolve<ApplicationOpenRepository>(),
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
  }

  final ComponentRegistry _registry;

  Future<void> initialize() => _registry.initializeAll();

  AppRuntime get runtime => AppRuntime(
    repositorySessions: _registry.resolve<RepositorySessionService>(),
    remoteWorkspaces: _registry.resolve<RemoteWorkspaceService>(),
    inspectionWindows: _registry.resolve<InspectionWindowService>(),
    inspectorReveal: _registry.resolve<InspectorRevealService>(),
    settings: _registry.resolve<SettingsService>(),
    avatars: _registry.resolve<AvatarService>(),
    repositoryAppearances: _registry.resolve<RepositoryAppearanceService>(),
    recovery: _registry.resolve<RecoveryService>(),
    operationCenter: _registry.resolve<OperationCenterService>(),
    repositoryDrops: _registry.resolve<RepositoryDropService>(),
    hosting: _registry.resolve<HostingConnectionService>(),
    hostingReview: _registry.resolve<HostingReviewService>(),
    cliForwarding: _registry.resolve<CliForwardingService>(),
    updates: _registry.resolve<AppUpdateService>(),
    shutdown: dispose,
  );

  Future<void> dispose() => _registry.dispose();
}
