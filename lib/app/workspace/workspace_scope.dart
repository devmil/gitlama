import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/hosting_connection_service.dart';
import '../../services/inspection_window_service.dart';
import '../../services/repository_session_service.dart';
import '../../services/settings_service.dart';
import '../../services/workflows/window_workflows.dart';
import '../../services/workflows/workspace_effects.dart';

/// The services and workflows of the workspace window for every widget
/// below the shell, instead of passing them down through each layer.
/// They stay the same for the window's lifetime; widgets that depend on
/// what they publish listen to their streams.
class WorkspaceServicesScope extends InheritedWidget {
  const WorkspaceServicesScope({
    super.key,
    required this.repositories,
    required this.settings,
    required this.workflows,
    this.hosting,
    required this.inspectionWindows,
    required super.child,
  });

  final RepositorySessionService repositories;
  final SettingsService settings;
  final WindowWorkflows workflows;
  final HostingConnectionService? hosting;
  final InspectionWindowService inspectionWindows;

  static WorkspaceServicesScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No WorkspaceServicesScope above this widget.');
    return scope!;
  }

  static WorkspaceServicesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceServicesScope>();

  /// The scope without depending on it, for State lifecycle methods and
  /// handlers; its services stay the same for the window's lifetime.
  static WorkspaceServicesScope read(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<WorkspaceServicesScope>();
    assert(scope != null, 'No WorkspaceServicesScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(WorkspaceServicesScope oldWidget) =>
      repositories != oldWidget.repositories ||
      settings != oldWidget.settings ||
      workflows != oldWidget.workflows ||
      hosting != oldWidget.hosting ||
      inspectionWindows != oldWidget.inspectionWindows;
}

/// Carries out the window's effects of [kind] for the widget at [context]:
/// one requested before it showed (after its first frame) and every later
/// one. Each effect is handled once. Cancel the subscription on dispose.
StreamSubscription<WorkspaceEffect>? listenForEffects(
  BuildContext context,
  WorkspaceEffectKind kind,
  void Function(WorkspaceEffect effect) onEffect,
) {
  final effects = WorkspaceServicesScope.maybeOf(context)?.workflows.effects;
  if (effects == null) return null;
  if (effects.take(kind) case final pending?) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) onEffect(pending);
    });
  }
  return effects.of(kind).listen((effect) {
    effects.handled(effect);
    if (context.mounted) onEffect(effect);
  });
}
