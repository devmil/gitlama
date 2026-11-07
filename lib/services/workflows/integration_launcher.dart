import '../../models/app_command.dart';
import '../../models/host_platform.dart';
import '../../models/integrations.dart';
import '../../models/native_paths.dart';
import '../../models/remote_command_policy.dart';
import '../../models/settings.dart';
import '../remote_workspace_workflows.dart';
import '../repository_session_service.dart';
import 'workflow.dart';

/// What launching a tool asks of the window it runs in.
abstract interface class IntegrationInteraction implements WorkflowInteraction {
  /// Asks to run [preview], which needs confirmation.
  Future<bool> confirmIntegration(IntegrationPreview preview);

  void reportIntegration(IntegrationOutcome outcome);
}

/// Why a tool did not start, for the window to report.
sealed class IntegrationOutcome {
  const IntegrationOutcome();
}

/// No tool of the requested kind is configured or installed.
final class IntegrationUnavailable extends IntegrationOutcome {
  const IntegrationUnavailable();
}

final class IntegrationLaunchFailed extends IntegrationOutcome {
  const IntegrationLaunchFailed();
}

/// The command is not offered for the active repository, for [reason].
final class IntegrationRefused extends IntegrationOutcome {
  const IntegrationRefused(this.reason);

  final AppCommandDisabledReason reason;
}

/// Opens the repository, a file or a folder in an editor, terminal or file
/// manager: the configured tool first, otherwise the first one installed,
/// with the arguments each platform's tools need. A tool on this computer
/// never receives a path on another computer.
final class IntegrationLauncher {
  IntegrationLauncher(this._repositories, this._remote, this._platform);

  final RepositorySessionService _repositories;
  final RemoteWorkspaceWorkflows? _remote;
  final HostPlatform _platform;

  void _report(IntegrationInteraction interaction, IntegrationOutcome outcome) {
    if (interaction.active) interaction.reportIntegration(outcome);
  }

  /// Refuses [id] when the active tab's host does not offer it.
  bool _refused(IntegrationInteraction interaction, AppCommandId id) {
    final reason = remoteCommandReason(
      id,
      _remote?.accessFor(_repositories.activeTab),
    );
    if (reason == null) return false;
    _report(interaction, IntegrationRefused(reason));
    return true;
  }

  /// Runs [definition], a configured tool, on the repository or [file].
  Future<void> runConfigured(
    IntegrationInteraction interaction,
    IntegrationDefinition definition, {
    NativePathIdentity? file,
  }) async {
    if (file?.isRemote ?? false) return;
    await _launch(
      interaction,
      IntegrationRequest(
        kind: definition.kind,
        configured: definition,
        variables: _variables(file: file),
      ),
    );
  }

  /// Opens the repository, or [file] in it, with a tool of [kind].
  Future<void> open(
    IntegrationInteraction interaction,
    IntegrationKind kind, {
    NativePathIdentity? file,
  }) async {
    // A file this computer wrote, such as a saved patch, opens locally even
    // while the active repository lives on another computer.
    final localFile = file != null && !file.isRemote && _absolute(file);
    if ((file?.isRemote ?? false) ||
        !localFile &&
            _refused(interaction, switch (kind) {
              IntegrationKind.terminal => AppCommandId.openInTerminal,
              IntegrationKind.fileManager => AppCommandId.openInFileManager,
              _ => AppCommandId.openInEditor,
            })) {
      return;
    }
    final configured = _repositories.configuredIntegrations(kind).firstOrNull;
    if (configured != null) {
      await runConfigured(interaction, configured, file: file);
      return;
    }
    try {
      final candidate = (await _repositories.integrations.discover(
        kind,
      )).firstOrNull;
      if (!interaction.active) return;
      if (candidate == null) {
        _report(interaction, const IntegrationUnavailable());
        return;
      }
      final opensFile =
          (kind == IntegrationKind.editor ||
              kind == IntegrationKind.fileManager) &&
          file != null;
      await _launch(
        interaction,
        IntegrationRequest(
          kind: kind,
          discoveredId: opensFile ? null : candidate.id,
          configured: opensFile
              ? IntegrationDefinition(
                  id: candidate.id,
                  kind: kind,
                  executable: candidate.executable,
                  arguments: fileArguments(kind, candidate.id, _platform),
                  launchMode: candidate.launchMode,
                )
              : null,
          variables: _variables(
            file:
                file != null &&
                    kind == IntegrationKind.fileManager &&
                    !selectsFile(candidate.id, _platform)
                ? parentNativePath(file)
                : file,
          ),
        ),
      );
    } on Object {
      _report(interaction, const IntegrationLaunchFailed());
    }
  }

  /// Opens [folder] itself (a repository or worktree root) in the configured
  /// or discovered file manager, whichever repository is active.
  Future<void> openFolder(
    IntegrationInteraction interaction,
    NativePathIdentity folder,
  ) async {
    if (folder.isRemote) {
      _report(
        interaction,
        const IntegrationRefused(AppCommandDisabledReason.remoteUnsupported),
      );
      return;
    }
    final configured = _repositories
        .configuredIntegrations(IntegrationKind.fileManager)
        .firstOrNull;
    if (configured != null) {
      await runConfigured(interaction, configured, file: folder);
      return;
    }
    try {
      final candidate = (await _repositories.integrations.discover(
        IntegrationKind.fileManager,
      )).firstOrNull;
      if (!interaction.active) return;
      if (candidate == null) {
        _report(interaction, const IntegrationUnavailable());
        return;
      }
      await _launch(
        interaction,
        IntegrationRequest(
          kind: IntegrationKind.fileManager,
          configured: IntegrationDefinition(
            id: candidate.id,
            kind: IntegrationKind.fileManager,
            executable: candidate.executable,
            arguments: folderArguments(candidate.id),
            launchMode: candidate.launchMode,
          ),
          variables: _variables(file: folder),
        ),
      );
    } on Object {
      _report(interaction, const IntegrationLaunchFailed());
    }
  }

  /// The arguments that make a discovered tool of [kind] open (an editor) or
  /// reveal (a file manager) `{file}` on [platform].
  static List<String> fileArguments(
    IntegrationKind kind,
    String candidateId,
    HostPlatform platform,
  ) => switch ((kind, platform)) {
    (IntegrationKind.editor, HostPlatform.macOS) => const ['-t', '{file}'],
    (IntegrationKind.editor, _) => const ['{file}'],
    (IntegrationKind.fileManager, HostPlatform.macOS) => const ['-R', '{file}'],
    (IntegrationKind.fileManager, HostPlatform.windows) => const [
      '/select,{file}',
    ],
    (IntegrationKind.fileManager, HostPlatform.linux)
        when selectsFile(candidateId, platform) =>
      const ['--select', '{file}'],
    _ => const ['{file}'],
  };

  /// Whether a discovered file manager can select a file in its folder; the
  /// others are given the folder instead.
  static bool selectsFile(String candidateId, HostPlatform platform) =>
      platform != HostPlatform.linux ||
      candidateId.contains('dolphin') ||
      candidateId.contains('nautilus');

  /// The arguments that open a folder itself; the discovered commands open
  /// `{repository}`.
  static List<String> folderArguments(String candidateId) =>
      candidateId.endsWith('-gio')
      ? const ['open', '{file}']
      : const ['{file}'];

  static bool _absolute(NativePathIdentity path) =>
      path.units.isNotEmpty && path.units.first == 47;

  IntegrationVariables _variables({NativePathIdentity? file}) {
    final active = _repositories.activeTab;
    final root = active?.canonicalIdentity;
    final status = active?.session?.snapshot.status;
    // An absolute local folder (another tab's) stays local even while the
    // active repository lives on another computer.
    final localFolder =
        file != null &&
        !file.isRemote &&
        (root?.isRemote ?? false) &&
        _absolute(file);
    return IntegrationVariables(
      file: root == null || file == null
          ? root
          : localFolder
          ? file
          : repositoryFileIdentity(root, file),
      currentBranch: status?.branchName,
      selectedCommit:
          _repositories.history.current.targetObjectId ?? status?.headObjectId,
    );
  }

  Future<void> _launch(
    IntegrationInteraction interaction,
    IntegrationRequest request,
  ) async {
    if (_repositories.activeTab?.session == null ||
        request.variables.file == null) {
      return;
    }
    final variables = request.variables;
    if ([
      variables.file,
      variables.diffLeft,
      variables.diffRight,
      variables.mergeBase,
      variables.mergeCurrent,
      variables.mergeIncoming,
      variables.mergeResult,
    ].any((path) => path?.isRemote ?? false)) {
      _report(
        interaction,
        const IntegrationRefused(AppCommandDisabledReason.remoteUnsupported),
      );
      return;
    }
    IntegrationPreview? preview;
    try {
      preview = await _repositories.integrations.preview(request);
      if (!interaction.active) return;
      final confirmed =
          !preview.requiresConfirmation ||
          await interaction.confirmIntegration(preview);
      if (!confirmed) {
        await _repositories.integrations.cancel(preview);
        return;
      }
      final result = await _repositories.integrations.execute(
        preview,
        confirmed: true,
      );
      if (result.state != IntegrationExecutionState.completed &&
          result.state != IntegrationExecutionState.detached) {
        _report(interaction, const IntegrationLaunchFailed());
      }
    } on Object {
      if (preview != null) await _repositories.integrations.cancel(preview);
      _report(interaction, const IntegrationLaunchFailed());
    }
  }
}
