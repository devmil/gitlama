import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/inspection.dart';
import '../../models/discard.dart';
import '../../models/inspector.dart';
import '../../models/repository_state.dart';
import '../../services/inspector/lens_availability.dart';
import '../../widgets/native_menu.dart';

/// Every action a file or folder menu can offer. One catalogue builds every
/// file menu of the product, so a file has the same actions wherever it is
/// listed (docs/design-system/specs/inspector.md §7).
enum FileAction {
  showDiff,
  showContents,
  blame,
  fileHistory,
  folderHistory,
  openInNewWindow,
  stage,
  unstage,
  inspectChanges,
  createPatch,
  externalDiff,
  openExternally,
  revealInFileBrowser,
  copyPath,
  addToGitignore,
  discard,
  clean,
  restoreFromCommit,
}

/// Where the menu's file or folder is listed.
enum FileActionSource {
  /// A file the shown commit changed.
  committedFile,

  /// A file a comparison of two commits changed.
  comparedFile,

  /// A file of All files that the shown commit did not change.
  treeFile,

  /// A folder of All files or of the Changed tree.
  folder,

  /// A file of a history entry.
  historyEntryFile,
  unstagedFile,
  stagedFile,

  /// A folder of the Changes lists.
  changesFolder,
  conflictFile,
  reviewFile,
}

/// What a menu is about.
final class FileActionSubject {
  const FileActionSubject({
    required this.source,
    required this.path,
    this.changeKind,
    this.treeKind,
    this.statusKind,
    this.existsInWorkingTree = false,
    this.changedFolder = false,
    this.staged = false,
    this.discardable = false,
    this.untracked = false,
    this.mode,
    this.revision,
    this.oldPath,
  });

  final FileActionSource source;

  /// The repository-relative path.
  final List<int> path;

  /// How the shown commit changed the file.
  final CommitFileChangeKind? changeKind;
  final CommitTreeEntryKind? treeKind;
  final StatusEntryKind? statusKind;

  /// Whether [path] exists in the working tree, checked when the menu opens.
  final bool existsInWorkingTree;

  /// A folder of the Changed tree, whose changed files can form a patch.
  final bool changedFolder;

  /// A folder of the staged list.
  final bool staged;

  /// Whether Discard or Clean applies.
  final bool discardable;

  /// An untracked file or folder, which Clean removes.
  final bool untracked;

  /// The file mode of a changed file, when known.
  final int? mode;

  /// The commit the file is listed in, for inspector sources.
  final String? revision;

  /// This subject with [existsInWorkingTree] as checked when its menu opens.
  FileActionSubject withExistence(bool exists) => FileActionSubject(
    source: source,
    path: path,
    changeKind: changeKind,
    treeKind: treeKind,
    statusKind: statusKind,
    existsInWorkingTree: exists,
    changedFolder: changedFolder,
    staged: staged,
    discardable: discardable,
    untracked: untracked,
    mode: mode,
    revision: revision,
    oldPath: oldPath,
  );

  /// The path a renamed file came from, for patches.
  final List<int>? oldPath;

  bool get isFolder =>
      source == FileActionSource.folder ||
      source == FileActionSource.changesFolder;

  /// Inspection actions of the working tree inspect the current commit.
  bool get atHead => switch (source) {
    FileActionSource.unstagedFile ||
    FileActionSource.stagedFile ||
    FileActionSource.changesFolder ||
    FileActionSource.conflictFile => true,
    _ => false,
  };
}

/// Opens [lens] of a working-tree path at the current commit.
typedef InspectWorkingFile =
    void Function(
      List<int> path,
      InspectorLens lens, {
      required bool directory,
      required bool invert,
    });

/// One selected menu entry: an action on the file, or on the multiple
/// selection it belongs to.
final class FileActionCommand {
  const FileActionCommand(this.action, {this.selection = false});

  final FileAction action;
  final bool selection;

  @override
  bool operator ==(Object other) =>
      other is FileActionCommand &&
      other.action == action &&
      other.selection == selection;

  @override
  int get hashCode => Object.hash(action, selection);
}

/// The multiple selection a Changes file belongs to.
final class FileActionSelection {
  const FileActionSelection({
    required this.count,
    required this.staged,
    this.discardKind,
  });

  final int count;
  final bool staged;

  /// Null for unsupported or staged selections.
  final DiscardKind? discardKind;
}

/// Performs file actions for one list. [capabilities] names the actions the
/// host can perform; the catalogue omits all others.
abstract class FileActionHost {
  Set<FileAction> get capabilities;

  /// The file manager's name for "Reveal in …".
  String get fileBrowserName;

  /// Why inspection actions are unavailable, or null.
  String? inspectionUnavailableReason(BuildContext context) => null;

  /// Why [action] is unavailable here, for example on a repository on
  /// another computer. An action with a reason is listed disabled with it,
  /// even outside [capabilities], so the menu shows what exists.
  String? actionUnavailableReason(BuildContext context, FileAction action) =>
      null;

  /// [subject] with what can only be told when its menu opens, such as
  /// whether its path exists in the working tree.
  FutureOr<FileActionSubject> resolve(FileActionSubject subject) => subject;

  /// Runs [command] on [subject] after its menu has closed. [invert] is true
  /// when ⌘ or Ctrl was held, which opens inspection in the other place.
  void run(
    FileActionCommand command,
    FileActionSubject subject, {
    required bool invert,
  });
}

/// What the inspector's one lens rule says about [subject]'s file.
Map<InspectorLens, LensUnavailableReason?> _lenses(FileActionSubject subject) =>
    lensAvailabilityFor(
      directory: false,
      changed: subject.changeKind != null,
      changeKind: subject.changeKind,
      mode: subject.mode,
      treeKind: subject.treeKind,
    );

/// Whether the matrix of spec §7.1 offers [action] for [subject], before
/// the host's capabilities apply.
bool fileActionApplies(FileAction action, FileActionSubject subject) {
  final source = subject.source;
  final committed =
      source == FileActionSource.committedFile ||
      source == FileActionSource.comparedFile;
  final history = source == FileActionSource.historyEntryFile;
  final changesFile =
      source == FileActionSource.unstagedFile ||
      source == FileActionSource.stagedFile;
  return switch (action) {
    FileAction.showDiff => committed || history,
    // A submodule has no contents to show, wherever it is listed.
    FileAction.showContents =>
      (committed || history || source == FileActionSource.treeFile) &&
          _lenses(subject)[InspectorLens.contents] == null,
    FileAction.blame =>
      ((committed || history || source == FileActionSource.treeFile) &&
              _lenses(subject)[InspectorLens.blame] == null) ||
          changesFile ||
          source == FileActionSource.conflictFile ||
          source == FileActionSource.reviewFile,
    FileAction.fileHistory => !subject.isFolder,
    FileAction.folderHistory => subject.isFolder,
    FileAction.openInNewWindow =>
      committed ||
          history ||
          source == FileActionSource.treeFile ||
          source == FileActionSource.folder,
    FileAction.stage =>
      source == FileActionSource.unstagedFile ||
          (source == FileActionSource.changesFolder && !subject.staged),
    FileAction.unstage =>
      source == FileActionSource.stagedFile ||
          (source == FileActionSource.changesFolder && subject.staged),
    FileAction.inspectChanges => changesFile,
    FileAction.createPatch =>
      committed ||
          changesFile ||
          source == FileActionSource.changesFolder ||
          (source == FileActionSource.folder && subject.changedFolder),
    FileAction.externalDiff => committed || history,
    FileAction.openExternally =>
      changesFile ||
          source == FileActionSource.conflictFile ||
          ((committed ||
                  history ||
                  source == FileActionSource.treeFile ||
                  source == FileActionSource.reviewFile) &&
              subject.existsInWorkingTree),
    FileAction.revealInFileBrowser =>
      changesFile ||
          source == FileActionSource.changesFolder ||
          source == FileActionSource.conflictFile ||
          subject.existsInWorkingTree,
    FileAction.copyPath => true,
    FileAction.addToGitignore =>
      source == FileActionSource.unstagedFile ||
          (source == FileActionSource.changesFolder && !subject.staged),
    FileAction.discard =>
      (source == FileActionSource.unstagedFile ||
              source == FileActionSource.changesFolder) &&
          !subject.staged &&
          subject.discardable &&
          !subject.untracked,
    FileAction.clean =>
      (source == FileActionSource.unstagedFile ||
              source == FileActionSource.changesFolder) &&
          !subject.staged &&
          subject.discardable &&
          subject.untracked,
    FileAction.restoreFromCommit =>
      (source == FileActionSource.committedFile ||
              source == FileActionSource.treeFile ||
              history) &&
          subject.changeKind != CommitFileChangeKind.deleted,
  };
}

const _groups = [
  [
    FileAction.showDiff,
    FileAction.showContents,
    FileAction.blame,
    FileAction.fileHistory,
    FileAction.folderHistory,
    FileAction.openInNewWindow,
  ],
  [FileAction.stage, FileAction.unstage, FileAction.inspectChanges],
  [FileAction.createPatch, FileAction.externalDiff],
  [
    FileAction.openExternally,
    FileAction.revealInFileBrowser,
    FileAction.copyPath,
  ],
  [FileAction.addToGitignore],
  [FileAction.discard, FileAction.clean, FileAction.restoreFromCommit],
];

const _busyActions = {
  FileAction.stage,
  FileAction.unstage,
  FileAction.inspectChanges,
  FileAction.createPatch,
  FileAction.addToGitignore,
  FileAction.discard,
  FileAction.clean,
  FileAction.restoreFromCommit,
};

const _inspectionActions = {
  FileAction.showDiff,
  FileAction.showContents,
  FileAction.blame,
  FileAction.fileHistory,
  FileAction.folderHistory,
  FileAction.openInNewWindow,
};

String _icon(FileAction action, FileActionSubject subject) => switch (action) {
  FileAction.showDiff => 'file-diff',
  FileAction.showContents => 'file-text',
  FileAction.blame => 'blame',
  FileAction.fileHistory || FileAction.folderHistory => 'history',
  FileAction.openInNewWindow => 'app-window',
  FileAction.stage => subject.isFolder ? 'stage-all' : 'plus',
  FileAction.unstage => subject.isFolder ? 'unstage-all' : 'minus',
  FileAction.inspectChanges => 'inspect',
  FileAction.createPatch => 'file-diff',
  FileAction.externalDiff || FileAction.openExternally => 'external-link',
  FileAction.revealInFileBrowser => 'folder-open',
  FileAction.copyPath => 'copy',
  FileAction.addToGitignore => 'eye-off',
  FileAction.discard || FileAction.clean => 'trash',
  FileAction.restoreFromCommit => 'archive-restore',
};

String _title(
  BuildContext context,
  FileAction action,
  FileActionSubject subject,
  String fileBrowserName, {
  required bool inSelection,
}) {
  final l10n = context.l10n;
  final title = switch (action) {
    FileAction.showDiff => l10n.fileActionShowDiff,
    FileAction.showContents => l10n.fileActionShowContents,
    FileAction.blame => l10n.historyBlame,
    FileAction.fileHistory => l10n.fileActionFileHistory,
    FileAction.folderHistory => l10n.fileActionFolderHistory,
    FileAction.openInNewWindow => l10n.inspectorOpenInWindow,
    FileAction.stage => subject.isFolder ? l10n.stageSelected : l10n.stageFile,
    FileAction.unstage =>
      subject.isFolder ? l10n.unstageSelected : l10n.unstageFile,
    FileAction.inspectChanges => l10n.inspectChanges,
    FileAction.createPatch =>
      subject.isFolder ||
              (!inSelection &&
                  (subject.source == FileActionSource.unstagedFile ||
                      subject.source == FileActionSource.stagedFile))
          ? l10n.patchCreate
          : l10n.patchCreateFromFile,
    FileAction.externalDiff => l10n.fileActionExternalDiff,
    FileAction.openExternally => l10n.openFileExternal,
    FileAction.revealInFileBrowser => l10n.openInFileBrowser(fileBrowserName),
    FileAction.copyPath => l10n.copyFilePath,
    FileAction.addToGitignore => l10n.fileActionAddToGitignore,
    FileAction.discard =>
      subject.isFolder ? l10n.discardSelected : l10n.discardFile,
    FileAction.clean =>
      subject.isFolder ? l10n.discardSelected : l10n.cleanFile,
    FileAction.restoreFromCommit => l10n.historyRestoreFile,
  };
  final head =
      subject.atHead &&
      (action == FileAction.blame ||
          action == FileAction.fileHistory ||
          action == FileAction.folderHistory);
  return head ? l10n.fileActionHeadSuffix(title) : title;
}

/// The menu of [subject] for [host]: grouped, separated and in the order of
/// the inspector spec. [selection] adds the actions on the multiple
/// selection the file belongs to, under their own header.
List<NativeMenuItem<FileActionCommand>> buildFileActionItems(
  BuildContext context,
  FileActionSubject subject,
  FileActionHost host, {
  FileActionSelection? selection,
  bool busy = false,
  bool allowStagingWhileBusy = false,
}) {
  final capabilities = host.capabilities;
  final inspectionReason = host.inspectionUnavailableReason(context);
  final items = <NativeMenuItem<FileActionCommand>>[];
  final inSelection = selection != null && selection.count >= 2;
  if (inSelection) {
    items.add(
      NativeMenuItem.header(context.l10n.menuSelectedFiles(selection.count)),
    );
    final stage = selection.staged ? FileAction.unstage : FileAction.stage;
    final stageReason = host.actionUnavailableReason(context, stage);
    if (capabilities.contains(stage) || stageReason != null) {
      items.add(
        NativeMenuItem(
          value: FileActionCommand(stage, selection: true),
          title: selection.staged
              ? context.l10n.unstageSelected
              : context.l10n.stageSelected,
          icon: selection.staged ? 'unstage-all' : 'stage-all',
          enabled: !busy || allowStagingWhileBusy,
          disabledReason: stageReason,
        ),
      );
    }
    final patchReason = host.actionUnavailableReason(
      context,
      FileAction.createPatch,
    );
    if (capabilities.contains(FileAction.createPatch) || patchReason != null) {
      items.add(
        NativeMenuItem(
          value: const FileActionCommand(
            FileAction.createPatch,
            selection: true,
          ),
          title: context.l10n.patchCreateFromSelection,
          icon: 'file-diff',
          enabled: !busy,
          disabledReason: patchReason,
        ),
      );
    }
    if (!selection.staged && selection.discardKind != null) {
      final clean = selection.discardKind == DiscardKind.clean;
      final action = clean ? FileAction.clean : FileAction.discard;
      final reason = host.actionUnavailableReason(context, action);
      if (capabilities.contains(action) || reason != null) {
        items.add(
          NativeMenuItem(
            value: FileActionCommand(action, selection: true),
            title: clean
                ? context.l10n.cleanSelected
                : context.l10n.discardSelected,
            icon: 'trash',
            danger: true,
            enabled: !busy,
            disabledReason: reason,
          ),
        );
      }
    }
    items
      ..add(const NativeMenuItem.separator())
      ..add(
        NativeMenuItem.header(
          utf8.decode(subject.path, allowMalformed: true).split('/').last,
        ),
      );
  }
  var first = true;
  for (final group in _groups) {
    final entries = [
      for (final action in group)
        if ((capabilities.contains(action) ||
                host.actionUnavailableReason(context, action) != null) &&
            fileActionApplies(action, subject))
          action,
    ];
    if (entries.isEmpty) continue;
    if (!first) items.add(const NativeMenuItem.separator());
    first = false;
    for (final action in entries) {
      final actionReason = host.actionUnavailableReason(context, action);
      final unavailable =
          inspectionReason != null && _inspectionActions.contains(action);
      final title = _title(
        context,
        action,
        subject,
        host.fileBrowserName,
        inSelection: inSelection,
      );
      items.add(
        NativeMenuItem(
          value: FileActionCommand(action),
          title: unavailable ? '$title — $inspectionReason' : title,
          icon: _icon(action, subject),
          enabled:
              !unavailable &&
              !(busy &&
                  _busyActions.contains(action) &&
                  !(allowStagingWhileBusy &&
                      (action == FileAction.stage ||
                          action == FileAction.unstage))),
          disabledReason: unavailable ? null : actionReason,
          danger:
              action == FileAction.discard ||
              action == FileAction.clean ||
              action == FileAction.restoreFromCommit,
        ),
      );
    }
  }
  return items;
}

/// Whether ⌘ (macOS) or Ctrl (elsewhere) is held, which opens inspection in
/// the other place.
bool inspectionModifierPressed() {
  final keyboard = HardwareKeyboard.instance;
  return defaultTargetPlatform == TargetPlatform.macOS
      ? keyboard.isMetaPressed
      : keyboard.isControlPressed;
}

/// The right-click and keyboard context menu of a file or folder row.
Widget fileActionContextMenu({
  required BuildContext context,
  required FileActionSubject Function() subject,
  required FileActionHost host,
  FileActionSelection? Function()? selection,
  bool busy = false,
  required Widget child,
}) => GitLamaContextMenuWidget(
  menuItems: (_) async {
    final shown = await host.resolve(subject());
    if (!context.mounted) return null;
    return nativeMenuActions<FileActionCommand>(
      buildFileActionItems(
        context,
        shown,
        host,
        selection: selection?.call(),
        busy: busy,
      ),
      (command) =>
          host.run(command, shown, invert: inspectionModifierPressed()),
    );
  },
  child: child,
);

/// The "⋯" button of a file or folder row.
class FileActionButton extends StatelessWidget {
  const FileActionButton({
    required this.subject,
    required this.host,
    this.selection,
    this.busy = false,
    super.key,
  });

  final FileActionSubject Function() subject;
  final FileActionHost host;
  final FileActionSelection? Function()? selection;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    late FileActionSubject shown;
    FileActionSubject? resolved;
    return NativeMenuButton<FileActionCommand>(
      beforeOpen: () async => resolved = await host.resolve(subject()),
      tooltip: context.l10n.historyFileActions,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: MeridianSize.controlSm,
        height: MeridianSize.controlSm,
      ),
      iconSize: MeridianSize.icon,
      onSelected: (command) =>
          host.run(command, shown, invert: inspectionModifierPressed()),
      itemBuilder: (context) {
        shown = resolved ?? subject();
        return buildFileActionItems(
          context,
          shown,
          host,
          selection: selection?.call(),
          busy: busy,
        );
      },
    );
  }
}
