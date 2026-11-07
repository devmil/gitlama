import '../services/app_update_service.dart';
import '../services/repository_session_service.dart';
import '../services/inspection_window_service.dart';
import '../services/inspector_reveal_service.dart';
import '../services/cli_forwarding_service.dart';
import '../services/operation_center_service.dart';
import '../services/repository_drop_service.dart';
import '../services/recovery_service.dart';
import '../services/repository_appearance_service.dart';
import '../services/settings_service.dart';
import '../services/avatar_service.dart';
import '../services/hosting_connection_service.dart';
import '../services/hosting_review_service.dart';
import '../services/remote_workspace_service.dart';

/// Typed, initialized capabilities exposed to the widget tree.
///
/// Add service fields here as product slices are introduced. Do not expose the
/// component registry itself.
final class AppRuntime {
  const AppRuntime({
    required this.repositorySessions,
    required this.remoteWorkspaces,
    required this.inspectionWindows,
    required this.inspectorReveal,
    required this.settings,
    required this.avatars,
    required this.repositoryAppearances,
    required this.recovery,
    required this.operationCenter,
    required this.repositoryDrops,
    required this.hosting,
    required this.hostingReview,
    required this.cliForwarding,
    required this.updates,
    required this.shutdown,
  });

  final RepositorySessionService repositorySessions;

  /// Remote host profiles and connections.
  final RemoteWorkspaceService remoteWorkspaces;

  /// Inspector windows; see [InspectionWindowService.available].
  final InspectionWindowService inspectionWindows;

  /// Serves inspector windows that reveal commits in this window's graph.
  final InspectorRevealService inspectorReveal;
  final SettingsService settings;
  final AvatarService avatars;
  final RepositoryAppearanceService repositoryAppearances;
  final RecoveryService recovery;
  final OperationCenterService operationCenter;

  /// Folders dropped on the window; [DisabledRepositoryDrops] where none
  /// are accepted.
  final RepositoryDropController repositoryDrops;
  final HostingConnectionService hosting;
  final HostingReviewService hostingReview;

  /// Commands forwarded from the command line;
  /// [DisabledCliForwardingController] where none arrive.
  final CliForwardingController cliForwarding;
  final AppUpdateService updates;
  final Future<void> Function() shutdown;

  /// This runtime with every service kept and [shutdown] replaced.
  ///
  /// Wrappers use this instead of copying fields one by one, so a service
  /// added later cannot be dropped on the way to the widget tree.
  AppRuntime withShutdown(Future<void> Function() shutdown) => AppRuntime(
    repositorySessions: repositorySessions,
    remoteWorkspaces: remoteWorkspaces,
    inspectionWindows: inspectionWindows,
    inspectorReveal: inspectorReveal,
    settings: settings,
    avatars: avatars,
    repositoryAppearances: repositoryAppearances,
    recovery: recovery,
    operationCenter: operationCenter,
    repositoryDrops: repositoryDrops,
    hosting: hosting,
    hostingReview: hostingReview,
    cliForwarding: cliForwarding,
    updates: updates,
    shutdown: shutdown,
  );
}
