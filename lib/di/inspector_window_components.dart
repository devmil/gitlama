import 'package:flutter/scheduler.dart';

import '../app/inspector_window_runtime.dart';
import '../models/inspection_window.dart';
import '../models/repository_state.dart';
import '../repositories/avatar_repository.dart';
import '../repositories/core_repository.dart';
import '../repositories/impl/native_avatar_repository.dart';
import '../repositories/impl/native_core_repository.dart';
import '../repositories/impl/native_inspection_window_repository.dart';
import '../repositories/impl/native_inspector_reveal_repository.dart';
import '../repositories/impl/native_repository_session_repository.dart';
import '../repositories/impl/native_settings_repository.dart';
import '../models/remote_workspace.dart';
import '../repositories/impl/remote/remote_inspection_calls.dart';
import '../repositories/impl/remote/remote_inspection_channel.dart';
import '../repositories/impl/remote/remote_inspection_session_repository.dart';
import '../repositories/inspection_session_repository.dart';
import '../repositories/inspection_window_repository.dart';
import '../repositories/inspector_reveal_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/avatar_service.dart';
import '../services/core_service.dart';
import '../services/diff_syntax_service.dart';
import '../repositories/diff_syntax_repository.dart';
import '../services/inspection_window_service.dart';
import '../services/inspector/inspector_window_session.dart';
import '../services/inspector_reveal_service.dart';
import '../services/settings_service.dart';
import 'component_registry.dart';

/// The composition root of one inspector window: its own read-only session,
/// more inspector windows, the way back to the main window, and the
/// settings and avatars it shows. Each window is its own engine and isolate.
///
/// A repository on a remote host is read through the main window's
/// connection to it, which this engine cannot reach itself.
///
/// Repositories come before their owning services; disposal runs in reverse.
final class InspectorWindowComponents {
  InspectorWindowComponents(
    InspectionWindowRequest request, {
    CoreRepository Function()? coreRepositoryFactory,
    InspectionSessionRepository Function()? sessionRepositoryFactory,
    InspectionWindowRepository Function()? inspectionWindowRepositoryFactory,
    InspectorRevealRepository Function()? revealRepositoryFactory,
    SettingsRepository Function()? settingsRepositoryFactory,
    AvatarRepository Function()? avatarRepositoryFactory,
    RemoteInspectionTransport Function()? remoteInspectionTransportFactory,
  }) : _registry = ComponentRegistry() {
    _registry.register<CoreRepository>(
      (_) => (coreRepositoryFactory ?? NativeCoreRepository.new)(),
    );
    final authority = request.repository.remote;
    _registry.register<InspectionSessionRepository>(
      (_) =>
          sessionRepositoryFactory?.call() ??
          switch (authority) {
            null => NativeRepositorySessionRepository(),
            final authority => remoteInspectionSession(
              authority,
              transport: remoteInspectionTransportFactory?.call(),
            ),
          },
    );
    _registry.register<InspectionWindowRepository>(
      (_) =>
          (inspectionWindowRepositoryFactory ??
          NativeInspectionWindowRepository.new)(),
    );
    _registry.register<InspectorRevealRepository>(
      (_) => (revealRepositoryFactory ?? NativeInspectorRevealRepository.new)(),
    );
    _registry.register<SettingsRepository>(
      (_) => (settingsRepositoryFactory ?? NativeSettingsRepository.new)(),
    );
    _registry.register<AvatarRepository>(
      (_) => (avatarRepositoryFactory ?? NativeAvatarRepository.new)(),
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
        canEnable: false,
      ),
      initialize: (service) => service.initialize(),
      dispose: (service) => service.dispose(),
    );
    _registry.register<InspectionWindowService>(
      (resolver) => InspectionWindowService(
        resolver.resolve<InspectionWindowRepository>(),
      ),
    );
    _registry.register<InspectorRevealService>(
      (resolver) =>
          InspectorRevealService(resolver.resolve<InspectorRevealRepository>()),
      dispose: (service) => service.dispose(),
    );
    // This window's own syntax colours, parsed where its session reads.
    _registry.register<DiffSyntaxService>(
      (resolver) => DiffSyntaxService(switch (resolver
          .resolve<InspectionSessionRepository>()) {
        final DiffSyntaxRepository syntax => syntax,
        _ => const _NoDiffSyntax(),
      }, nextFrame: () => SchedulerBinding.instance.endOfFrame),
      dispose: (service) => service.dispose(),
    );
    _registry.register<InspectorWindowSession>(
      (resolver) => InspectorWindowSession(
        resolver.resolve<InspectionSessionRepository>(),
        request,
        syntax: resolver.resolve<DiffSyntaxService>(),
      ),
      initialize: (session) => session.initialize(),
      dispose: (session) => session.close(),
    );
  }

  final ComponentRegistry _registry;

  Future<void> initialize() => _registry.initializeAll();

  InspectorWindowRuntime get runtime => InspectorWindowRuntime(
    session: _registry.resolve<InspectorWindowSession>(),
    windows: _registry.resolve<InspectionWindowService>(),
    reveal: _registry.resolve<InspectorRevealService>(),
    settings: _registry.resolve<SettingsService>(),
    avatars: _registry.resolve<AvatarService>(),
    shutdown: dispose,
  );

  Future<void> dispose() => _registry.dispose();
}

/// The session of an inspector window whose repository is on a remote host:
/// the host's reads go through the main window over [transport] (the window
/// channel by default); content is decoded and rendered on this computer.
InspectionSessionRepository remoteInspectionSession(
  RemoteAuthority authority, {
  RemoteInspectionTransport? transport,
}) {
  final remote = NativeRepositorySessionRepository.remote(
    WindowRemoteInspectionCalls(
      transport ?? WindowChannelRemoteInspectionTransport(),
      authority: authority,
    ),
    authority: authority,
  );
  return RemoteInspectionSessionRepository(
    remote,
    remote,
    NativeRepositorySessionRepository(),
  );
}

/// A session without syntax colours: its diffs stay plain.
final class _NoDiffSyntax implements DiffSyntaxRepository {
  const _NoDiffSyntax();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(
    const RepositorySessionException(
      RepositoryFailure(RepositoryFailureCode.remoteNotOffered),
    ),
  );
}
