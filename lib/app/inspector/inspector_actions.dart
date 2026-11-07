import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../byte_size.dart';
import '../../l10n/l10n.dart';
import '../../models/git_names.dart';
import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../models/integrations.dart';
import '../../models/repository_state.dart';
import '../../services/inspector/inspector_service.dart';
import '../../services/inspector/lens_availability.dart';
import '../../widgets/status_notification.dart';
import '../file_actions/file_actions.dart';
import 'commit_diff_pane.dart';
import 'inspector_host.dart';

/// Whether showing [lens] opens a window. A diff always stays in place.
/// Blame, Contents and History open one where no inspector is visible, and
/// otherwise by the setting, inverted once by ⌘ or Ctrl.
bool opensInWindow({
  required InspectorLens lens,
  required bool inspectorVisible,
  required String setting,
  required bool invert,
}) {
  if (lens == InspectorLens.diff) return false;
  if (!inspectorVisible) return true;
  final window = setting == 'window';
  return invert ? !window : window;
}

/// Shows [location] in the inspector, or in a new window when the setting,
/// the modifier or [window] asks for one and the host can open windows.
Future<void> inspectLocation(
  InspectorService service,
  InspectorHost host,
  InspectorLocation location, {
  bool invert = false,
  bool window = false,
}) async {
  final inWindow =
      host.supportsWindows &&
      (window ||
          opensInWindow(
            lens: location.lens,
            inspectorVisible: true,
            setting: host.inspectionOpenIn,
            invert: invert,
          ));
  if (inWindow) {
    await host.openInWindow(location);
  } else {
    await service.navigate(location);
  }
}

/// The file actions of an inspector's lists.
final class InspectorFileActions extends FileActionHost {
  InspectorFileActions({
    required this.context,
    required this.service,
    required this.host,
  });

  /// The context dialogs and notifications use.
  final BuildContext Function() context;
  final InspectorService service;
  final InspectorHost host;

  List<IntegrationDefinition> get _diffTools =>
      host.repositories?.configuredIntegrations(IntegrationKind.diffTool) ??
      const [];

  @override
  Set<FileAction> get capabilities => {
    FileAction.showDiff,
    FileAction.showContents,
    FileAction.blame,
    FileAction.fileHistory,
    FileAction.folderHistory,
    if (host.supportsWindows) FileAction.openInNewWindow,
    if (host.canCreatePatch) FileAction.createPatch,
    if (_diffTools.isNotEmpty) FileAction.externalDiff,
    if (host.canOpenWorkingCopy) ...{
      FileAction.openExternally,
      FileAction.revealInFileBrowser,
    },
    FileAction.copyPath,
    if (host.canRestore) FileAction.restoreFromCommit,
  };

  @override
  String get fileBrowserName => host.fileBrowserName;

  /// Asks the host whether the file of a commit exists in the working tree,
  /// so the editor and file manager are offered only for files that are
  /// there.
  @override
  Future<FileActionSubject> resolve(FileActionSubject subject) async =>
      subject.withExistence(
        host.canOpenWorkingCopy && await host.existsInWorkingTree(subject.path),
      );

  @override
  String? actionUnavailableReason(BuildContext context, FileAction action) =>
      host.remote &&
          switch (action) {
            FileAction.openExternally ||
            FileAction.revealInFileBrowser ||
            FileAction.restoreFromCommit => true,
            _ => false,
          }
      ? context.l10n.remoteCommandUnsupported
      : null;

  InspectorTarget? _targetFor(FileActionSubject subject) {
    final shown = service.current.location?.target;
    final revision = subject.revision;
    if (revision == null || revision == shown?.commit) return shown;
    return CommitTarget(revision);
  }

  /// The location of [subject] in [lens], keeping the shown scope when the
  /// target stays.
  InspectorLocation? locationFor(
    FileActionSubject subject,
    InspectorLens lens,
  ) {
    final target = _targetFor(subject);
    if (target == null) return null;
    final shown = service.current.location;
    return InspectorLocation(
      target: target,
      scope: shown?.target == target ? shown!.scope : InspectorScope.changed,
      path: subject.path,
      directory: subject.isFolder,
      lens: subject.isFolder ? InspectorLens.history : lens,
    );
  }

  @override
  void run(
    FileActionCommand command,
    FileActionSubject subject, {
    required bool invert,
  }) {
    final lens = switch (command.action) {
      FileAction.showDiff => InspectorLens.diff,
      FileAction.showContents => InspectorLens.contents,
      FileAction.blame => InspectorLens.blame,
      FileAction.fileHistory ||
      FileAction.folderHistory => InspectorLens.history,
      _ => null,
    };
    if (lens != null) {
      final location = locationFor(subject, lens);
      if (location == null) return;
      unawaited(inspectLocation(service, host, location, invert: invert));
      return;
    }
    switch (command.action) {
      case FileAction.openInNewWindow:
        final changed =
            subject.changeKind != null &&
            subject.source != FileActionSource.treeFile;
        final location = locationFor(
          subject,
          changed ? InspectorLens.diff : InspectorLens.contents,
        );
        if (location != null) unawaited(host.openInWindow(location));
      case FileAction.createPatch:
        final target = _targetFor(subject);
        if (target != null) host.createPatch(target, _patchPaths(subject));
      case FileAction.externalDiff:
        final repositories = host.repositories;
        final target = _targetFor(subject);
        final tool = _diffTools.firstOrNull;
        if (repositories == null || target == null || tool == null) return;
        final shown = context();
        if (!shown.mounted) return;
        unawaited(
          runExternalCommitDiff(
            shown,
            repositories,
            definition: tool,
            oldRevision: target.base,
            newRevision: target.commit,
            oldPath: subject.oldPath ?? subject.path,
            newPath: subject.path,
          ),
        );
      case FileAction.openExternally:
        host.openWorkingCopy(subject.path, reveal: false);
      case FileAction.revealInFileBrowser:
        host.openWorkingCopy(subject.path, reveal: true);
      case FileAction.copyPath:
        unawaited(_copy(utf8.decode(subject.path, allowMalformed: true)));
      case FileAction.restoreFromCommit:
        final shown = context();
        if (!shown.mounted) return;
        unawaited(
          confirmRestore(
            shown,
            service,
            subject.path,
            commit: subject.revision,
          ),
        );
      case FileAction.showDiff ||
          FileAction.showContents ||
          FileAction.blame ||
          FileAction.fileHistory ||
          FileAction.folderHistory ||
          FileAction.stage ||
          FileAction.unstage ||
          FileAction.inspectChanges ||
          FileAction.addToGitignore ||
          FileAction.discard ||
          FileAction.clean:
        break;
    }
  }

  List<List<int>> _patchPaths(FileActionSubject subject) {
    if (!subject.isFolder) return filePatchPaths(subject.path, subject.oldPath);
    final prefix = [...subject.path, 0x2f];
    return [
      for (final file
          in service.current.inspection?.files ?? const <CommitFileChange>[])
        if (startsWithBytes(changeDisplayPath(file), prefix))
          changeDisplayPath(file),
    ];
  }

  Future<void> _copy(String text) => copyPathWithNotification(context(), text);
}

/// Previews restoring [path] to its content in [commit] (or the shown
/// target), asks for confirmation and reports the outcome.
Future<void> confirmRestore(
  BuildContext context,
  InspectorService service,
  List<int> path, {
  String? commit,
}) async {
  try {
    final preview = await service.previewRestore(path, commit: commit);
    if (!context.mounted) return;
    final l10n = context.l10n;
    final source = preview.sourceBytes.length;
    final current = preview.currentBytes?.length;
    // Two different sizes that round alike are shown exactly.
    final exact =
        current != null &&
        current != source &&
        formatByteSize(l10n, current) == formatByteSize(l10n, source);
    String size(int bytes) =>
        exact ? l10n.byteCount(bytes) : formatByteSize(l10n, bytes);
    final accepted = await showMeridianConfirm(
      context,
      title: context.l10n.historyRestoreFile,
      description: context.l10n.historyRestorePreview(
        utf8.decode(path, allowMalformed: true),
      ),
      content: MeridianPropertyList(
        properties: [
          MeridianProperty(
            label: context.l10n.historyRestoreSourceSize,
            value: size(source),
            selectable: false,
          ),
          MeridianProperty(
            label: context.l10n.historyRestoreCurrentSize,
            value: current == null
                ? context.l10n.historyRestoreNoCurrentFile
                : size(current),
            selectable: false,
          ),
        ],
      ),
      confirmLabel: context.l10n.historyRestoreConfirm,
      cancelLabel: context.l10n.cancel,
      destructive: true,
    );
    if (!accepted) return;
    final result = await service.restoreFile(preview.token);
    if (!context.mounted) return;
    final message = switch (result.state) {
      RestoreState.restored => context.l10n.historyRestoreSucceeded,
      RestoreState.stale => context.l10n.historyRestoreStale,
      RestoreState.reconciledWithWarning =>
        context.l10n.historyRestoreReconciled,
      RestoreState.outcomeUncertain =>
        context.l10n.historyRestoreOutcomeUncertain,
      RestoreState.failed => context.l10n.historyRestoreFailed,
    };
    StatusNotificationScope.show(context, message);
  } on Object {
    if (!context.mounted) return;
    StatusNotificationScope.show(
      context,
      context.l10n.historyRestoreFailed,
      error: true,
    );
  }
}

/// The status letter of a change kind.
String commitFileCode(CommitFileChangeKind kind) => switch (kind) {
  CommitFileChangeKind.modified => 'M',
  CommitFileChangeKind.added => 'A',
  CommitFileChangeKind.deleted => 'D',
  CommitFileChangeKind.renamed => 'R',
  CommitFileChangeKind.copied => 'C',
  CommitFileChangeKind.modeChanged => 'T',
  CommitFileChangeKind.typeChanged => 'T',
  CommitFileChangeKind.binary => 'B',
  CommitFileChangeKind.image => 'I',
  CommitFileChangeKind.submodule => 'S',
  CommitFileChangeKind.conflict => 'U',
  CommitFileChangeKind.untracked => '?',
};

/// The subject of a changed file of the inspector's target. Whether its
/// path exists in the working tree is checked when its menu opens; see
/// [InspectorFileActions.resolve].
FileActionSubject changedFileSubject(
  CommitFileChange file,
  InspectorTarget target,
) => FileActionSubject(
  source: target is ComparisonTarget
      ? FileActionSource.comparedFile
      : FileActionSource.committedFile,
  path: changeDisplayPath(file),
  oldPath: file.oldPath.isEmpty ? null : file.oldPath,
  changeKind: file.kind,
  mode: file.newMode,
  revision: target.commit,
);

/// Failure messages of the inspector.
String inspectorFailureMessage(
  BuildContext context,
  RepositoryFailureCode? code,
) => switch (code) {
  RepositoryFailureCode.missingObject => context.l10n.inspectorMissingObject,
  RepositoryFailureCode.closed ||
  RepositoryFailureCode.retiredSession ||
  RepositoryFailureCode.unknownSession =>
    context.l10n.inspectorRepositoryClosed,
  _ => context.l10n.inspectorLoadFailed,
};
